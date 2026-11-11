extends Node
## Telemetry push (2026-11-11): every arcade machine sends its RUN lines (core/telemetry.gd) to the Steam Machine
## whenever it can reach it on the home network, so balance can be judged from how the family really plays on the
## Decks without the TV (agents may not read Deck logs). The Steam Machine side: tools/duo-telemetry-recv (user
## service duo-telemetry-recv), which stores them per device in ~/.cache/duo-arena/telemetry/<device>.jsonl.
## - OUTBOX: Telemetry.run() appends each line to user://telemetry_outbox.jsonl; lines leave it only when the
##   receiver acknowledges them (by id = first 16 hex of the line's MD5, so a resend after a lost reply is ignored).
##   The first start after this landed also queues the machine's older telemetry.jsonl (the runs nobody saw).
## - WHEN: on arcade start, a few seconds after each RUN line (after each round) and every RETRY_S seconds.
## - FINDING the Steam Machine: UDP "DUO_TELEMETRY_HELLO" broadcast (and the address that answered last time, and
##   this machine itself) on PORT; the receiver answers with its HTTP port, then a POST /runs per batch.
## - NO SILENT LOSS: the outbox is capped at MAX_BYTES; past that the OLDEST lines go, with a log line every time,
##   and the count is sent with the next batch so the Steam Machine records the loss too. A log line also says when
##   the Steam Machine hasn't been reached for over a week.
## - Only RUN lines (game stats) and this machine's name leave it, only to private addresses. Tests never push
##   (core/save.gd test mode) unless DUO_TELEMETRY_PUSH_TEST=1 (tools/telemetry-push-test: own outbox, own receiver
##   on DUO_TELEMETRY_PORT, marked "test" so the real receiver refuses it).
## Env: DUO_TELEMETRY_PUSH=0 (off), DUO_TELEMETRY_PORT, DUO_TELEMETRY_HOST (skip finding: send to this address),
## DUO_TELEMETRY_DEVICE (name override), DUO_TELEMETRY_RETRY (seconds).

const Save := preload("res://core/save.gd")
const Machine := preload("res://core/machine.gd")
const PORT := 7870
const OUTBOX := "user://telemetry_outbox.jsonl"
const OUTBOX_TEST := "user://telemetry_outbox_test.jsonl"
const META := "user://telemetry_outbox.json"
const META_TEST := "user://telemetry_outbox_test.json"
const MAX_BYTES := 3000000  ## about 6000 RUN lines (several months of play)
const BATCH := 150
const RETRY_S := 600.0
const HELLO_MS := 1500
const WARN_DAYS := 7
const LOG := "TELEMETRY PUSH: "

var _next_try := 0.0  # seconds (Time.get_ticks_msec / 1000) when the next attempt may start
var _state := "idle"  # idle | hello | send
var _udp: PacketPeerUDP
var _nonce := ""
var _hello_until := 0
var _http: HTTPRequest
var _sent_ids: Array = []
var _said_unreachable := false


# --- Static: who pushes, the outbox ----------------------------------------------

static func push_test() -> bool:
	return OS.get_environment("DUO_TELEMETRY_PUSH_TEST") == "1"


static func enabled() -> bool:
	if OS.get_environment("DUO_TELEMETRY_PUSH") == "0":
		return false
	return push_test() or not Save.test_mode()


static func outbox_path() -> String:
	return OUTBOX_TEST if push_test() else OUTBOX


static func meta_path() -> String:
	return META_TEST if push_test() else META


static func port() -> int:
	return int(OS.get_environment("DUO_TELEMETRY_PORT")) if OS.has_environment("DUO_TELEMETRY_PORT") else PORT


## This machine's name on the Steam Machine (its hostname: "samuel-deck", "steammachine").
static func device() -> String:
	var d := OS.get_environment("DUO_TELEMETRY_DEVICE") if OS.has_environment("DUO_TELEMETRY_DEVICE") else ""
	if d == "":
		d = OS.get_environment("DUO_HOSTNAME") if OS.has_environment("DUO_HOSTNAME") \
			else FileAccess.get_file_as_string("/etc/hostname")
	var out := ""
	for ch in d.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-":
			out += ch
	return out.left(40) if out != "" else Machine.kind()


static func id_of(line: String) -> String:
	return line.md5_text().left(16)


static func read_meta() -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path())) if FileAccess.file_exists(meta_path()) else null
	return v if v is Dictionary else {}


static func write_meta(m: Dictionary) -> void:
	var f := FileAccess.open(meta_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(m))


static func pending() -> PackedStringArray:
	if not FileAccess.file_exists(outbox_path()):
		return PackedStringArray()
	return FileAccess.get_file_as_string(outbox_path()).split("\n", false)


static func _write_lines(lines: PackedStringArray) -> void:
	var f := FileAccess.open(outbox_path(), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + ("\n" if lines.size() > 0 else ""))


## Queue one RUN line (core/telemetry.gd run()). Nothing in test runs.
static func enqueue(line: String) -> void:
	if not enabled() or line.strip_edges() == "":
		return
	var p := outbox_path()
	var f := FileAccess.open(p, FileAccess.READ_WRITE) if FileAccess.file_exists(p) else FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		print(LOG + "can't write the outbox %s: this RUN line is only in telemetry.jsonl" % p)
		return
	f.seek_end()
	f.store_string(line.replace("\n", " ") + "\n")
	var big := f.get_length() > MAX_BYTES
	f.close()
	if big:
		trim()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var n := tree.root.get_node_or_null("TelemetryPush")
		if n != null and n.has_method("request_flush"):
			n.call("request_flush")


## Keep the outbox under MAX_BYTES by dropping the OLDEST lines (to 3/4 of it), never silently.
static func trim(max_bytes: int = MAX_BYTES) -> int:
	var lines := pending()
	var size := 0
	for l in lines:
		size += l.length() + 1
	if size <= max_bytes:
		return 0
	var drop := 0
	while drop < lines.size() and size > max_bytes * 3 / 4:
		size -= lines[drop].length() + 1
		drop += 1
	_write_lines(lines.slice(drop))
	var m := read_meta()
	m["dropped"] = int(m.get("dropped", 0)) + drop
	m["dropped_unreported"] = int(m.get("dropped_unreported", 0)) + drop
	write_meta(m)
	print(LOG + "WARNING outbox full (Steam Machine not reached since %s): dropped the %d oldest unsent RUN lines (%d dropped in all, %d still waiting)"
		% [_when(int(m.get("last_ok", 0))), drop, int(m["dropped"]), lines.size() - drop])
	return drop


## Remove the lines the receiver acknowledged.
static func ack(ids: Array) -> int:
	var gone := {}
	for i in ids:
		gone[str(i)] = true
	var keep := PackedStringArray()
	var removed := 0
	for l in pending():
		if gone.has(id_of(l)):
			removed += 1
		else:
			keep.append(l)
	_write_lines(keep)
	return removed


## First start with the push: queue this machine's own earlier RUN lines (not copies of other hosts' lines).
static func seed_from_history() -> int:
	var m := read_meta()
	if bool(m.get("seeded", false)) or push_test():
		return 0
	var n := 0
	var src := "user://telemetry.jsonl"
	if FileAccess.file_exists(src):
		var f := FileAccess.open(outbox_path(), FileAccess.READ_WRITE) if FileAccess.file_exists(outbox_path()) \
			else FileAccess.open(outbox_path(), FileAccess.WRITE)
		if f != null:
			f.seek_end()
			for l in FileAccess.get_file_as_string(src).split("\n", false):
				if l.begins_with("{") and not l.contains("\"copy\":true"):
					f.store_string(l + "\n")
					n += 1
			f.close()
	m["seeded"] = true
	write_meta(m)
	if n > 0:
		print(LOG + "queued %d earlier RUN lines from telemetry.jsonl" % n)
		trim()
	return n


static func _when(t: int) -> String:
	if t <= 0:
		return "never"
	var days := (int(Time.get_unix_time_from_system()) - t) / 86400
	return "today" if days < 1 else "%d days ago" % days


# --- The service ------------------------------------------------------------------

func _ready() -> void:
	name = "TelemetryPush"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not enabled():
		set_process(false)
		return
	seed_from_history()
	var m := read_meta()
	var waiting := pending().size()
	var last := int(m.get("last_ok", 0))
	print(LOG + "%s: %d RUN lines waiting, Steam Machine last reached %s" % [device(), waiting, _when(last)])
	if waiting > 0 and last > 0 and int(Time.get_unix_time_from_system()) - last > WARN_DAYS * 86400:
		print(LOG + "WARNING the Steam Machine hasn't been reached for %s; %d RUN lines kept for it" % [_when(last), waiting])
	_next_try = _now() + 3.0


func _exit_tree() -> void:
	if _udp != null:
		_udp.close()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Try soon (a new RUN line). Several in a row make one attempt.
func request_flush() -> void:
	if _state == "idle":
		_next_try = minf(_next_try, _now() + 4.0)


func _retry_s() -> float:
	return float(OS.get_environment("DUO_TELEMETRY_RETRY")) if OS.has_environment("DUO_TELEMETRY_RETRY") else RETRY_S


func _process(_dt: float) -> void:
	if _state == "idle":
		if _now() >= _next_try:
			_next_try = _now() + _retry_s()
			if pending().size() > 0:
				_hello()
	elif _state == "hello":
		_poll_hello()


func _hello() -> void:
	if OS.has_environment("DUO_TELEMETRY_HOST"):
		_send(OS.get_environment("DUO_TELEMETRY_HOST"), port())
		return
	if _udp == null:
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		if _udp.bind(0) != OK:
			_udp = null
			print(LOG + "can't open a UDP socket to look for the Steam Machine; trying again later")
			return
	_nonce = str(randi())
	var msg := ("DUO_TELEMETRY_HELLO " + _nonce).to_utf8_buffer()
	var tried := {}
	for ip in [str(read_meta().get("sink", "")), "127.0.0.1", "255.255.255.255"]:
		if ip == "" or tried.has(ip):
			continue
		tried[ip] = true
		_udp.set_dest_address(ip, port())
		_udp.put_packet(msg)
	_hello_until = Time.get_ticks_msec() + HELLO_MS
	_state = "hello"


func _poll_hello() -> void:
	while _udp != null and _udp.get_available_packet_count() > 0:
		var txt := _udp.get_packet().get_string_from_utf8()
		var ip := _udp.get_packet_ip()
		var parts := txt.split(" ")
		if parts.size() >= 3 and parts[0] == "DUO_TELEMETRY_HERE" and parts[2] == _nonce and _private(ip):
			_said_unreachable = false
			_send(ip, int(parts[1]))
			return
	if Time.get_ticks_msec() > _hello_until:
		_state = "idle"
		if not _said_unreachable:
			_said_unreachable = true
			print(LOG + "Steam Machine not found on this network; %d RUN lines kept for later (last reached %s)"
				% [pending().size(), _when(int(read_meta().get("last_ok", 0)))])


static func _private(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return ip == "::1"
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254)


func _send(ip: String, http_port: int) -> void:
	var lines := pending()
	if lines.is_empty():
		_state = "idle"
		return
	var runs: Array = []
	_sent_ids = []
	for l in lines.slice(0, BATCH):
		var id := id_of(l)
		runs.append({"id": id, "line": l})
		_sent_ids.append(id)
	var m := read_meta()
	var body := JSON.stringify({"device": device(), "dropped": int(m.get("dropped_unreported", 0)), "test": push_test(), "runs": runs})
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 10.0
		add_child(_http)
		_http.request_completed.connect(_on_done)
	var url := "http://%s:%d/runs" % [ip, http_port]
	set_meta("sink_try", ip)
	set_meta("sink_port", http_port)
	if _http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body) != OK:
		print(LOG + "couldn't start sending to %s; trying again later" % url)
		_state = "idle"
		return
	_state = "send"


func _on_done(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
	_state = "idle"
	var v: Variant = JSON.parse_string(data.get_string_from_utf8()) if code == 200 else null
	if result != HTTPRequest.RESULT_SUCCESS or not v is Dictionary:
		print(LOG + "sending failed (result %d, HTTP %d); %d RUN lines kept for later" % [result, code, pending().size()])
		return
	var d: Dictionary = v
	var removed := ack(d.get("acked", []))
	var m := read_meta()
	m["last_ok"] = int(Time.get_unix_time_from_system())
	m["sink"] = str(get_meta("sink_try", ""))
	m["dropped_unreported"] = 0
	m["sent"] = int(m.get("sent", 0)) + removed
	write_meta(m)
	var left := pending().size()
	print(LOG + "sent %d RUN lines to the Steam Machine (%d new, %d already there), %d waiting"
		% [removed, int(d.get("new", 0)), int(d.get("dup", 0)), left])
	if left > 0 and removed > 0:
		_send(str(m["sink"]), int(get_meta("sink_port", port())))