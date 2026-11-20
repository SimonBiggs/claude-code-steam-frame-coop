extends Node
## PlayReport (2026-11-20): the family's STANDALONE Godot games (Sprout Hop, Portal Explorer, Sheepdog Scramble,
## Seven Kart, Snake, ...) tell the Steam Machine when and how long they were played, the same way the arcade does
## (core/telemetry_push.gd -> tools/duo-telemetry-recv). Before this they reported nothing at all, so "what do they
## play" was blind to them.
## ONE source: duo-arena/tools/play_report.gd. tools/play-report-install copies it into a game as
## addons/play_report/play_report.gd + an autoload "PlayReport" (game-deploy-deck runs it before every deploy;
## dev.debt "play-report-missing" / "play-report-stale" flags a game without it or with an old copy). Edit only here.
## - One RUN line per play session: {"game": "standalone:<slug>", "standalone": true, "session", "secs" (time the
##   game was running, not counting Deck sleep), "active_secs" (time with input in the last 2 min), "end": quit |
##   playing (a progress line every 10 min; readers keep the newest per session) | killed (found at the next start:
##   the game was closed without quitting cleanly, e.g. Steam's Exit or a battery death)}.
## - Every start checks in (even with nothing to send) with "app": "<slug>", so the Steam Machine knows this device
##   launched the game and that the network path works (dev.debt "telemetry-device-silent").
## - Lines wait in user://play_report_outbox.jsonl until the receiver acknowledges them (ids = MD5 of the line).
## - Never in tests: headless, SAVE_TEST, DUO_TELEMETRY_PUSH=0, PLAY_REPORT=0, or a scene under res://tests/.
## - Only these numbers, the game name and this machine's host name leave it, only to private addresses.
## Env: PLAY_REPORT=0 (off) / force (tests: on even headless), DUO_TELEMETRY_PORT, DUO_TELEMETRY_HOST (send here), DUO_TELEMETRY_DEVICE (name).

const PORT := 7870
const OUTBOX := "user://play_report_outbox.jsonl"
const SESSION := "user://play_report_session.json"
const META := "user://play_report.json"
const BEAT_S := 30.0
const PROGRESS_S := 600.0
const RETRY_S := 600.0
const IDLE_S := 120.0
const MAX_LINES := 5000
const HELLO_MS := 1500
const LOG := "PLAY REPORT: "

var game := ""
var title := ""
var _on := false
var _sid := ""
var _start := 0
var _secs := 0.0
var _active := 0.0
var _last_input := -1000000
var _next_beat := 0.0
var _next_progress := 0.0
var _next_try := 3.0
var _clock := 0.0
var _state := "idle"
var _udp: PacketPeerUDP
var _nonce := ""
var _hello_until := 0
var _http: HTTPRequest
var _checkin := true
var _ended := false


static func enabled() -> bool:
	if OS.get_environment("PLAY_REPORT") == "force":  # tools/play-report-test only (its own receiver and device name)
		return true
	for k in ["PLAY_REPORT", "DUO_TELEMETRY_PUSH"]:
		if OS.get_environment(k) == "0":
			return false
	if OS.has_environment("SAVE_TEST") or DisplayServer.get_name() == "headless":
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.current_scene != null and tree.current_scene.scene_file_path.begins_with("res://tests/"):
		return false
	return true


static func slug_of(name_: String) -> String:
	var out := ""
	for ch in name_.strip_edges().to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out.strip_edges() if out != "" else "game"


static func device() -> String:
	var d := OS.get_environment("DUO_TELEMETRY_DEVICE") if OS.has_environment("DUO_TELEMETRY_DEVICE") \
		else FileAccess.get_file_as_string("/etc/hostname")
	var out := ""
	for ch in d.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-":
			out += ch
	return out.left(40) if out != "" else "unknown"


static func machine() -> String:
	var h := device()
	if h.contains("steamdeck") or OS.get_environment("SteamDeck") == "1":
		return "deck"
	return "tv" if h.contains("steammachine") else "pc"


static func id_of(line: String) -> String:
	return line.md5_text().left(16)


static func _read_json(p: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	return v if v is Dictionary else {}


static func _write_json(p: String, d: Dictionary) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


static func pending() -> PackedStringArray:
	return FileAccess.get_file_as_string(OUTBOX).split("\n", false) if FileAccess.file_exists(OUTBOX) else PackedStringArray()


static func _write_lines(lines: PackedStringArray) -> void:
	if lines.size() > MAX_LINES:
		print(LOG + "WARNING outbox full: dropped the %d oldest unsent lines" % (lines.size() - MAX_LINES))
		lines = lines.slice(lines.size() - MAX_LINES)
	var f := FileAccess.open(OUTBOX, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + ("\n" if lines.size() > 0 else ""))


static func enqueue(line: String) -> void:
	var lines := pending()
	lines.append(line.replace("\n", " "))
	_write_lines(lines)


func _ready() -> void:
	name = "PlayReport"
	process_mode = Node.PROCESS_MODE_ALWAYS
	title = str(ProjectSettings.get_setting("application/config/name", "game"))
	game = slug_of(title)
	_on = enabled()
	if not _on:
		set_process(false)
		set_process_input(false)
		return
	var old := _read_json(SESSION)  # a session that never quit cleanly (killed, crashed, battery)
	if old.has("session"):
		enqueue(_line(old, "killed"))
	_sid = "%s-%d-%d" % [device(), int(Time.get_unix_time_from_system()), randi() % 100000]
	_start = int(Time.get_unix_time_from_system())
	_beat()
	print(LOG + "%s on %s: %d lines waiting, Steam Machine last reached %s" % [game, device(), pending().size(), _when(int(_read_json(META).get("last_ok", 0)))])


func _line(s: Dictionary, end: String) -> String:
	var t := int(s.get("start", 0))
	return JSON.stringify({"game": "standalone:" + str(s.get("game", game)), "standalone": true, "title": str(s.get("title", title)),
		"session": str(s.get("session", "")), "secs": snappedf(float(s.get("secs", 0.0)), 0.1),
		"active_secs": snappedf(float(s.get("active", 0.0)), 0.1), "end": end, "t": t,
		"date": Time.get_datetime_string_from_unix_time(t), "t_end": int(s.get("at", t)), "machine": machine(), "host": device()})


func _session() -> Dictionary:
	return {"session": _sid, "game": game, "title": title, "start": _start, "secs": _secs, "active": _active,
		"at": int(Time.get_unix_time_from_system())}


func _beat() -> void:
	_write_json(SESSION, _session())


func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton or e is InputEventScreenTouch \
			or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.3):
		_last_input = Time.get_ticks_msec()


func _process(dt: float) -> void:
	if not enabled():  # a test scene took over
		_on = false
		set_process(false)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION))
		return
	var d := minf(dt, 1.0)  # the first frame after a Deck wakes up must not count the sleep
	_clock += d
	_secs += d
	if Time.get_ticks_msec() - _last_input < IDLE_S * 1000.0:
		_active += d
	if _clock >= _next_beat:
		_next_beat = _clock + BEAT_S
		_beat()
	if _clock >= PROGRESS_S and _clock >= _next_progress:
		_next_progress = _clock + PROGRESS_S
		enqueue(_line(_session(), "playing"))
		_next_try = minf(_next_try, _clock + 2.0)
	if _state == "idle" and _clock >= _next_try:
		_next_try = _clock + RETRY_S
		if _checkin or pending().size() > 0:
			_hello()
	elif _state == "hello":
		_poll_hello()


func _exit_tree() -> void:
	if not _on or _ended:
		return
	_ended = true
	enqueue(_line(_session(), "quit"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION))
	_send_blocking()
	if _udp != null:
		_udp.close()


# --- Sending (same protocol as core/telemetry_push.gd) --------------------------------

func _hello() -> void:
	if OS.has_environment("DUO_TELEMETRY_HOST"):
		_send(OS.get_environment("DUO_TELEMETRY_HOST"), _port())
		return
	if _udp == null:
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		if _udp.bind(0) != OK:
			_udp = null
			return
	_nonce = str(randi())
	var msg := ("DUO_TELEMETRY_HELLO " + _nonce).to_utf8_buffer()
	var tried := {}
	for ip in [str(_read_json(META).get("sink", "")), "127.0.0.1", "255.255.255.255"]:
		if ip == "" or tried.has(ip):
			continue
		tried[ip] = true
		_udp.set_dest_address(ip, _port())
		_udp.put_packet(msg)
	_hello_until = Time.get_ticks_msec() + HELLO_MS
	_state = "hello"


static func _port() -> int:
	return int(OS.get_environment("DUO_TELEMETRY_PORT")) if OS.has_environment("DUO_TELEMETRY_PORT") else PORT


func _poll_hello() -> void:
	while _udp != null and _udp.get_available_packet_count() > 0:
		var parts := _udp.get_packet().get_string_from_utf8().split(" ")
		var ip := _udp.get_packet_ip()
		if parts.size() >= 3 and parts[0] == "DUO_TELEMETRY_HERE" and parts[2] == _nonce and _private(ip):
			_send(ip, int(parts[1]))
			return
	if Time.get_ticks_msec() > _hello_until:
		_state = "idle"


static func _private(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return ip == "::1"
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254)


func _body() -> String:
	var lines := pending()
	var runs: Array = []
	for l in lines.slice(0, 150):
		runs.append({"id": id_of(l), "line": l})
	return JSON.stringify({"device": device(), "app": game, "dropped": 0, "test": false, "runs": runs,
		"checkin": _checkin, "waiting": lines.size()})


func _send(ip: String, http_port: int) -> void:
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 10.0
		add_child(_http)
		_http.request_completed.connect(_on_done)
	set_meta("sink_try", ip)
	if _http.request("http://%s:%d/runs" % [ip, http_port], PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, _body()) != OK:
		_state = "idle"
		return
	_state = "send"


func _on_done(result: int, code: int, _h: PackedStringArray, data: PackedByteArray) -> void:
	_state = "idle"
	var v: Variant = JSON.parse_string(data.get_string_from_utf8()) if code == 200 else null
	if result != HTTPRequest.RESULT_SUCCESS or not v is Dictionary:
		_next_try = minf(_next_try, _clock + 60.0)
		print(LOG + "sending failed (result %d, HTTP %d); %d lines kept for later" % [result, code, pending().size()])
		return
	_took(v, str(get_meta("sink_try", "")))


func _took(v: Dictionary, sink: String) -> void:
	_checkin = false
	var gone := {}
	for i in v.get("acked", []):
		gone[str(i)] = true
	var keep := PackedStringArray()
	for l in pending():
		if not gone.has(id_of(l)):
			keep.append(l)
	_write_lines(keep)
	var m := _read_json(META)
	m["last_ok"] = int(Time.get_unix_time_from_system())
	m["sink"] = sink
	_write_json(META, m)
	print(LOG + "reached the Steam Machine at %s: %d sent, %d waiting" % [sink, gone.size(), keep.size()])


## At quit: one quick try (1.5 s at most) to the address that answered last time, so the final line arrives now.
func _send_blocking() -> void:
	var sink := OS.get_environment("DUO_TELEMETRY_HOST") if OS.has_environment("DUO_TELEMETRY_HOST") else str(_read_json(META).get("sink", ""))
	if sink == "" or pending().is_empty():
		return
	var c := HTTPClient.new()
	if c.connect_to_host(sink, _port()) != OK:
		return
	var until := Time.get_ticks_msec() + 1500
	while c.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING] and Time.get_ticks_msec() < until:
		c.poll()
		OS.delay_msec(10)
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		return
	if c.request(HTTPClient.METHOD_POST, "/runs", PackedStringArray(["Content-Type: application/json"]), _body()) != OK:
		return
	while c.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < until:
		c.poll()
		OS.delay_msec(10)
	var buf := PackedByteArray()
	while c.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < until:
		c.poll()
		buf.append_array(c.read_response_body_chunk())
		OS.delay_msec(5)
	var v: Variant = JSON.parse_string(buf.get_string_from_utf8()) if c.get_response_code() == 200 else null
	if v is Dictionary:
		_took(v, sink)


static func _when(t: int) -> String:
	if t <= 0:
		return "never"
	var days := (int(Time.get_unix_time_from_system()) - t) / 86400
	return "today" if days < 1 else "%d days ago" % days
