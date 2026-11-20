extends Node
## TV seat (a service, core/services.gd): pads at the TV can play with the VR player when the Steam Machine itself is
## the VR host.
##
## Why (2026-11-19): since mid-November the Steam Machine runs the arcade as the VR HOST and SteamVR streams it to the
## Steam Frame (vrlink); its TV shows the window, which is the XR mirror. core/party.gd never seats a VR host's own
## pads (written when the Frame ran the game natively and the TV was a separate machine), and every game draws TV
## players only on TV machines, so kids pressed A at the TV and nothing happened, with nothing telling them how to join.
## What this does: the Steam Machine becomes "two machines". On an A press from a real pad at the TV, the streamed VR
## host (core/machine.gd streamed_vr_host) starts a second copy of the arcade: flat (--xr-mode off), joining this one
## at 127.0.0.1 like any TV machine (lobby + games, nothing per game). Its window covers the mirror on the TV and it
## seats the pad that pressed A first (party.gd DUO_TV_CLIENT_PAD). The host keeps ignoring its own pads while it
## runs (it even swallows them: the host's TV menu is invisible under XR and an A there started games unseen). When the
## TV screen closes (nobody played for a while, the VR host went away) the mirror is back.
##   - TV prompt: the mirror can't show 2D (Godot draws no canvas into a stereo XR viewport: renderer_viewport.cpp
##     "Stereo rendering does not support 2D"), so the prompt is its own small borderless OS window (a popup, never
##     focused, V-Sync off so it can't pace the headset) pinned bottom-centre over the mirror: "Press A to join on the
##     TV" while a real pad is connected, "Starting the TV screen..." until it joins, and a failure says so (and the
##     log says why). The headset never sees it (it is not part of the XR view).
##   - Never more than one TV screen, at most one start per MIN_GAP_MS and MAX_STARTS per WINDOW_MS, none while
##     core/tv_share.gd says the TV belongs to another game (pads_off: and a running one closes then). Every start,
##     join and exit is logged here; the TV screen's own output goes to res://.dev/tv-seat.log.
##   - The second copy shares the project folder, so it differs where two copies would collide (all set at start):
##     its own user:// (XDG_DATA_HOME = <our user dir>/tv_seat: saves, logs, telemetry outbox), no LAN updates taken
##     (DUO_UPDATE_RECEIVE=0: it must never write into the project), a gdev bridge that neither takes .dev/cmd nor
##     records .dev/frames nor serves the :8090 stream (core/dev/gdev_main.gd, DUO_TV_CLIENT), no crash-restart file
##     (GDEV_SUPERVISED / GDEV_RESTART_FILE unset), our DUO_PORT, and the headset's own controller hidden from SDL.
##   - Sound: SteamVR makes "vrlink-sink" the default output while the Frame streams; the TV screen moves its sound to
##     the TV (core/room_audio.gd) and says which output (or that there is none).
## The TV screen (DUO_TV_CLIENT=1) runs this same service in its client role: it quits when the host process is gone,
## when it can't reach the host, or when nobody has played on it for CLIENT_IDLE_QUIT seconds.
## Tests: tests/tv_seat_test.gd (decisions), tests/tv_seat_e2e.tscn (host + a real spawned headless TV screen).
## Hooks: DUO_FAKE_STREAMED_VR=1 (core/machine.gd), TV_SEAT_VIRTUAL_REAL=1 (bot pads count as real pads at the TV),
## TV_SEAT_TEST_PAD=1 (the TV screen plugs in a bot pad), meta FAKE_PADS_META ([{id, name}] instead of Input's pads).

const Machine := preload("res://core/machine.gd")
const TvShare := preload("res://core/tv_share.gd")
const RoomAudio := preload("res://core/room_audio.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Party := preload("res://core/party.gd")

const MIN_GAP_MS := 15000
const MAX_STARTS := 4
const WINDOW_MS := 600000
const CONNECT_WAIT_MS := 60000  # host: a TV screen that hasn't joined by then failed (it is closed)
const FAIL_SHOW_MS := 12000
const CLIENT_CONNECT_GRACE := 60.0
const CLIENT_LOST_GRACE := 30.0
const CLIENT_IDLE_QUIT := 150.0
const SLOW_FPS := 45.0
const SLOW_SECONDS := 3.0
const TEXT_JOIN := "Press A to join on the TV"
const TEXT_STARTING := "Starting the TV screen..."
const TEXT_FAILED := "Couldn't start the TV screen"
const FAKE_PADS_META := "tv_seat_fake_pads"
const STEAM_VIRTUAL_PAD := "0x28de/0x11ff"  # Steam Input's virtual pad: hiding it would hide every pad
## Left over from the VR host / tests: never passed to the TV screen.
const UNSET_ENV := ["BOT_VR", "BOT_VR_SEATED", "BOT_VR_EYE", "DUO_HOST", "DUO_HOST_ORIGINAL", "DUO_JOIN_ORIGINAL",
	"ARCADE_GAME", "ARCADE_AUTOPICK", "DUO_SOLO", "DUO_FLAT_HOST", "DUO_VR_LOST", "DUO_VR_REJOIN", "DUO_RESUME_GAME",
	"DUO_MACHINE_KIND", "DUO_MACHINE_NAME", "BOT_MACHINE", "GDEV_SUPERVISED", "GDEV_RESTART_FILE", "GDEV_CONTROL_PORT",
	"VR_WATCH_FAKE", "VR_WATCH_FAKE_FAILED", "TV_SHARE_FAKE", "TV_SHARE_FORCE_VR", "DUO_FAKE_STREAMED_VR",
	"TV_SEAT_VIRTUAL_REAL", "XR_RUNTIME_JSON"]

# Host role
var client_pid := -1
var client_started_ms := 0
var client_joined := false  # the TV screen reached us at least once since it started
var starts: Array = []  # Time.get_ticks_msec() of each start
var failed_ms := -1000000
var fail_reason := ""
var shown := ""  # the prompt state on the TV: "", "join", "starting", "failed"
var prompt_off := ""  # why the prompt window was turned off for this run ("" = it may show)
var _win: Window
var _title: Label
var _sub: Label
var _slow_t := 0.0
var _t := 0.0
var _handed_off := false
var _swallow_told := false
var _exited := {}  # TV screen pid -> exit code, once it has exited
# Client role
var _c_unconnected := 0.0
var _c_ever := false
var _c_idle := 0.0
var _c_audio_t := 0.0
var _c_parent := 0
var _c_quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Machine.tv_seat_client():
		_client_start()


func _handoff() -> Dictionary:
	_handed_off = true
	return {"client_pid": client_pid, "client_started_ms": client_started_ms, "client_joined": client_joined,
		"starts": starts, "failed_ms": failed_ms, "fail_reason": fail_reason, "prompt_off": prompt_off,
		"c_unconnected": _c_unconnected, "c_ever": _c_ever, "c_idle": _c_idle, "swallow_told": _swallow_told}


func _adopt(s: Dictionary) -> void:
	client_pid = int(s.get("client_pid", -1))
	client_started_ms = int(s.get("client_started_ms", 0))
	client_joined = bool(s.get("client_joined", false))
	starts = s.get("starts", [])
	failed_ms = int(s.get("failed_ms", -1000000))
	fail_reason = str(s.get("fail_reason", ""))
	prompt_off = str(s.get("prompt_off", ""))
	_c_unconnected = float(s.get("c_unconnected", 0.0))
	_c_ever = bool(s.get("c_ever", false))
	_c_idle = float(s.get("c_idle", 0.0))
	_swallow_told = bool(s.get("swallow_told", false))


func _exit_tree() -> void:
	_free_window()
	if not _handed_off and client_running():
		_kill_client("the VR host is closing")


# --- Decisions (static: tests/tv_seat_test.gd) ----------------------------------------------------------------------

## What the TV prompt says: "" (nothing), "join", "starting" or "failed".
static func prompt_state(streamed: bool, real_pads: int, pads_off: bool, running: bool, joined: bool, ms_since_fail: int) -> String:
	if not streamed or pads_off:
		return ""
	if running:
		return "" if joined else "starting"  # (joined: the TV screen covers the mirror; the prompt must not float on it)
	if ms_since_fail < FAIL_SHOW_MS:
		return "failed"
	return "join" if real_pads > 0 else ""


## Why a TV screen can't start now ("" = it can).
static func start_refusal(now_ms: int, started: Array, running: bool, pads_off: bool) -> String:
	if pads_off:
		return "the TV belongs to another game (core/tv_share.gd)"
	if running:
		return "a TV screen is already running"
	var recent := 0
	for t in started:
		if now_ms - int(t) < MIN_GAP_MS:
			return "one started %.0f s ago (at most one per %d s)" % [(now_ms - int(t)) / 1000.0, MIN_GAP_MS / 1000]
		if now_ms - int(t) < WINDOW_MS:
			recent += 1
	if recent >= MAX_STARTS:
		return "%d starts in the last %d minutes (too many: something is wrong, see the log)" % [recent, WINDOW_MS / 60000]
	return ""


## The pads at the TV that count as players: [{id, name}] -> ids. Bot pads (id >= Party.VIRTUAL_PAD_BASE) only with
## virtual_ok; the VR player's own controllers never.
static func real_pads(pads: Array, virtual_ok: bool) -> Array[int]:
	var out: Array[int] = []
	for p in pads:
		var id := int(p.id)
		if id < 0 or (id >= Party.VIRTUAL_PAD_BASE and not virtual_ok) or Machine.headset_pad_name(str(p.name)):
			continue
		out.append(id)
	return out


## The command that starts the TV screen: {"path", "args"}. o: exe, project, port, pad, parent, headless, log,
## data_home, sdl_ignore (SDL_GAMECONTROLLER_IGNORE_DEVICES value or ""), test_pad.
## Through sh (its output goes to the log file) and env (the variables cleared / set): both exec, so the pid we get
## is the TV screen's own Godot.
static func spawn_command(o: Dictionary) -> Dictionary:
	var env_args: Array = []
	for k in UNSET_ENV:
		env_args.append_array(["-u", k])
	env_args.append_array([
		"DUO_TV_CLIENT=1", "DUO_JOIN=127.0.0.1", "DUO_PORT=%d" % int(o.port),
		"DUO_TV_CLIENT_PARENT=%d" % int(o.parent), "DUO_TV_CLIENT_PAD=%d" % int(o.pad),
		"DUO_UPDATE_RECEIVE=0", "GDEV_APPLY=safe", "XDG_DATA_HOME=%s" % str(o.data_home)])
	if str(o.get("sdl_ignore", "")) != "":
		env_args.append("SDL_GAMECONTROLLER_IGNORE_DEVICES=%s" % str(o.sdl_ignore))
	if bool(o.get("test_pad", false)):
		env_args.append("TV_SEAT_TEST_PAD=1")
	var godot_args: Array = [str(o.exe), "--path", str(o.project), "--xr-mode", "off"]
	if bool(o.get("headless", false)):
		godot_args.append("--headless")
	var args: Array = ["-c", "log=\"$1\"; shift; exec \"$@\" >>\"$log\" 2>&1", "tv-seat", str(o.log), "/usr/bin/env"]
	args.append_array(env_args)
	args.append_array(godot_args)
	return {"path": "/bin/sh", "args": args}


# --- Host role ------------------------------------------------------------------------------------------------------

func host_active() -> bool:
	return Machine.streamed_vr_host() and not Machine.tv_seat_client()


func client_running() -> bool:
	return _alive(client_pid)


## Asks the OS about a TV screen until it has exited, then remembers its exit code (Godot errors when a reaped
## child is asked about again).
func _alive(pid: int) -> bool:
	if pid <= 0 or _exited.has(pid):
		return false
	if OS.is_process_running(pid):
		return true
	_exited[pid] = OS.get_process_exit_code(pid)
	return false


## The pads connected here: [{id, name}] (FAKE_PADS_META in tests), plus bot pads with TV_SEAT_VIRTUAL_REAL.
func connected_pads() -> Array:
	if Engine.has_meta(FAKE_PADS_META):
		return Engine.get_meta(FAKE_PADS_META)
	var out := []
	for d in Input.get_connected_joypads():
		out.append({"id": d, "name": Input.get_joy_name(d)})
	if OS.has_environment("TV_SEAT_VIRTUAL_REAL"):
		for d in Engine.get_meta(Party.VIRTUAL_META, []):
			out.append({"id": int(d), "name": "bot pad"})
	return out


func tv_pads() -> Array[int]:
	return real_pads(connected_pads(), OS.has_environment("TV_SEAT_VIRTUAL_REAL") or Engine.has_meta(FAKE_PADS_META))


func _input(event: InputEvent) -> void:
	if Machine.tv_seat_client():
		_client_input(event)
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion) or not host_active():
		return
	if not tv_pads().has(event.device):
		return  # (the headset's own controllers, an ignored pad)
	# The host's TV menu can't be seen under XR: a TV pad must never drive it (an A there started a game unseen).
	get_viewport().set_input_as_handled()
	if not _swallow_told:
		_swallow_told = true
		print("TvSeat: pads at the TV don't drive the VR host's (invisible) menus; they play on the TV screen")
	var jb := event as InputEventJoypadButton
	if jb != null and jb.pressed and jb.button_index == JOY_BUTTON_A and not client_running():
		press(jb.device)


## A pad at the TV pressed A: start the TV screen (or say why not).
func press(device: int) -> void:
	var now := Time.get_ticks_msec()
	var running := client_running()
	var why := start_refusal(now, starts, running, TvShare.pads_off())
	if why != "":
		print("TvSeat: A on %s, but no TV screen now: %s" % [Party.device_label(device), why])
		if not running and not TvShare.pads_off():
			_fail(why)  # (the rate limit: shown on the TV)
		return
	var proj := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dev := ProjectSettings.globalize_path("res://.dev")
	var log_path := (dev if DirAccess.dir_exists_absolute(dev) else OS.get_user_data_dir()).path_join("tv-seat.log")
	if FileAccess.file_exists(log_path) and FileAccess.open(log_path, FileAccess.READ).get_length() > (2 << 20):
		DirAccess.rename_absolute(log_path, log_path + ".1")
	var port := int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else 7777  # (as core/net.gd)
	var spec := spawn_command({"exe": OS.get_executable_path(), "project": proj, "port": port, "pad": device,
		"parent": OS.get_process_id(), "headless": DisplayServer.get_name() == "headless", "log": log_path,
		"data_home": OS.get_user_data_dir().path_join("tv_seat"), "sdl_ignore": _sdl_ignore(),
		"test_pad": OS.has_environment("TV_SEAT_TEST_PAD")})
	starts.append(now)
	client_joined = false
	client_started_ms = now
	client_pid = OS.create_process(str(spec.path), PackedStringArray(spec.args))
	if client_pid <= 0:
		client_pid = -1
		print("TvSeat: CAN'T start the TV screen: running %s failed" % OS.get_executable_path())
		_fail("couldn't run Godot")
		return
	print("TvSeat: %s pressed A: starting the TV screen (pid %d, port %d, output in %s)" % [
		Party.device_label(device), client_pid, port, log_path])


## SDL_GAMECONTROLLER_IGNORE_DEVICES for the TV screen: what it was plus the headset's own controllers (by USB id), so
## not even games that read pads directly see the VR player's hands as a TV pad.
func _sdl_ignore() -> String:
	var have := OS.get_environment("SDL_GAMECONTROLLER_IGNORE_DEVICES")
	var add: Array = []
	for d in Input.get_connected_joypads():
		if not Machine.headset_pad_name(Input.get_joy_name(d)):
			continue
		var info := Input.get_joy_info(d)
		if not info.has("vendor_id") or not info.has("product_id"):
			print("TvSeat: the headset's controllers (pad %d) have no USB id: the TV screen filters them by name only" % d)
			continue
		var id := "0x%04x/0x%04x" % [int(info.vendor_id), int(info.product_id)]
		if id == STEAM_VIRTUAL_PAD:
			print("TvSeat: the headset's controllers come through Steam Input (%s): the TV screen filters them by name only" % id)
		elif not add.has(id) and not have.contains(id):
			add.append(id)
	if add.is_empty():
		return have
	print("TvSeat: hiding the headset's controllers (%s) from the TV screen" % ", ".join(add))
	return ",".join(([have] if have != "" else []) + add)


func _kill_client(why: String) -> void:
	print("TvSeat: closing the TV screen (pid %d): %s" % [client_pid, why])
	OS.kill(client_pid)  # (Godot reaps it here: never ask about this pid again)
	_exited[client_pid] = -1
	client_pid = -1


func _fail(why: String) -> void:
	failed_ms = Time.get_ticks_msec()
	fail_reason = why


## The TV screen is connected to us (lobby or game): a peer on this machine's loopback address.
func _client_peer_here() -> bool:
	var mp := get_tree().get_multiplayer()
	var peer := mp.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or not mp.is_server():
		return false
	for id in mp.get_peers():
		var p := peer.get_peer(id)
		if p != null and p.get_remote_address() in ["127.0.0.1", "::1", "::ffff:127.0.0.1"]:
			return true
	return false


func _process(delta: float) -> void:
	if Machine.tv_seat_client():
		_client_tick(delta)
		return
	_host_tick(delta)


func _host_tick(delta: float) -> void:
	var streamed := host_active()
	if client_pid > 0:
		if not _alive(client_pid):
			var code := int(_exited.get(client_pid, -1))
			if client_joined:
				print("TvSeat: the TV screen closed (pid %d, exit %d): the TV shows the VR view again" % [client_pid, code])
			else:
				print("TvSeat: the TV screen did not work: it closed before joining (pid %d, exit %d); its output: res://.dev/tv-seat.log" % [client_pid, code])
				_fail("it closed before joining")
			client_pid = -1
		else:
			if not client_joined and _client_peer_here():
				client_joined = true
				print("TvSeat: the TV screen joined (pid %d, %.1f s after the press)" % [client_pid, (Time.get_ticks_msec() - client_started_ms) / 1000.0])
			var why := ""
			if not streamed:
				why = "VR isn't streamed from here any more (this machine seats its own pads now)"
			elif TvShare.pads_off():
				why = "another game has the TV (core/tv_share.gd)"
			elif not client_joined and Time.get_ticks_msec() - client_started_ms > CONNECT_WAIT_MS:
				why = "it didn't join within %d s" % (CONNECT_WAIT_MS / 1000)
				print("TvSeat: the TV screen did not work: %s; its output: res://.dev/tv-seat.log" % why)
				_fail(why)
			if why != "":
				_kill_client(why)
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		var st := prompt_state(streamed, tv_pads().size(), TvShare.pads_off(), client_running(), client_joined,
			Time.get_ticks_msec() - failed_ms)
		_show(st if prompt_off == "" else "")
	if _win != null and streamed and not OS.has_environment("DUO_FAKE_STREAMED_VR"):
		_watch_speed(delta)


## While the prompt window is up: frames slower than SLOW_FPS for SLOW_SECONDS (a compositor pacing the second
## window) close it and keep it closed this run (said in the log).
func _watch_speed(delta: float) -> void:
	_slow_t = _slow_t + delta if delta > 1.0 / SLOW_FPS else maxf(0.0, _slow_t - delta)
	if _slow_t < SLOW_SECONDS:
		return
	prompt_off = "the VR view ran under %d fps while the TV prompt window was up" % int(SLOW_FPS)
	print("TvSeat: TV prompt OFF for this run: %s (A at the TV still starts the TV screen)" % prompt_off)
	_show("")


# --- The TV prompt (its own small window: the XR mirror draws no 2D) ------------------------------------------------

func _show(st: String) -> void:
	if st == shown:
		return
	shown = st
	if st == "":
		_free_window()
		print("TvSeat: TV prompt hidden")
		return
	if _win == null or not is_instance_valid(_win):
		_make_window()
	var sub := ""
	match st:
		"join":
			_title.text = TEXT_JOIN
			sub = "Play with the VR player"
		"starting":
			_title.text = TEXT_STARTING
		"failed":
			_title.text = TEXT_FAILED
			sub = fail_reason.substr(0, 1).to_upper() + fail_reason.substr(1)
	_sub.text = sub
	_sub.visible = sub != ""
	print("TvSeat: TV prompt: %s%s" % [_title.text, (" (%s)" % sub) if sub != "" else ""])


func _make_window() -> void:
	var main_size := Vector2(DisplayServer.window_get_size())
	if main_size.x < 64.0 or main_size.y < 64.0:
		main_size = Vector2(1920, 1080)
	var s := main_size.y / 1080.0
	_win = Window.new()
	_win.name = "TvSeatPrompt"
	_win.title = "TV seat"
	_win.borderless = true
	_win.unfocusable = true
	_win.transient = true
	_win.popup_window = true  # X11 override-redirect: drawn over the mirror, never takes the focus
	_win.size = Vector2i(int(760.0 * s), int(150.0 * s))
	_win.position = DisplayServer.window_get_position() + Vector2i(int((main_size.x - _win.size.x) / 2.0),
		int(main_size.y - _win.size.y - 36.0 * s))
	add_child(_win)
	var ui := UiKit.ui_root(_win, 1, s)
	var panel := UiKit.panel("card")
	ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := UiKit.vbox()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	_title = UiKit.label(TEXT_JOIN, "heading", null, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	_sub = UiKit.label("", "small", null, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_sub)
	var wid := _win.get_window_id()
	if wid != DisplayServer.INVALID_WINDOW_ID and wid != DisplayServer.MAIN_WINDOW_ID:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, wid)  # never pace the headset by the TV's 60 Hz
	_slow_t = 0.0


func _free_window() -> void:
	if _win != null and is_instance_valid(_win):
		_win.queue_free()
	_win = null
	_title = null
	_sub = null


## What the TV prompt says now ("" = nothing): tests and gdev read it.
func ui_text() -> String:
	if shown == "" or _title == null:
		return ""
	return _title.text + ("\n" + _sub.text if _sub.visible else "")


# --- Client role (the TV screen) ------------------------------------------------------------------------------------

func _client_start() -> void:
	_c_parent = int(OS.get_environment("DUO_TV_CLIENT_PARENT"))
	var names := []
	for d in Input.get_connected_joypads():
		names.append("%d %s%s" % [d, Input.get_joy_name(d), " (VR hands: ignored)" if Machine.headset_pad(d) else ""])
	print("TvSeat: this is the TV screen for the VR host (pid %d) on this machine; pads: %s" % [
		_c_parent, ", ".join(names) if not names.is_empty() else "none"])
	if OS.has_environment("TV_SEAT_TEST_PAD"):
		var pads: Array = Engine.get_meta(Party.VIRTUAL_META, [])
		if not pads.has(Party.VIRTUAL_PAD_BASE):
			pads.append(Party.VIRTUAL_PAD_BASE)
		Engine.set_meta(Party.VIRTUAL_META, pads)
		print("TvSeat: test pad %d plugged in" % Party.VIRTUAL_PAD_BASE)
	RoomAudio.use_room_output("TV screen")


func _client_input(event: InputEvent) -> void:
	var jb := event as InputEventJoypadButton
	var jm := event as InputEventJoypadMotion
	var played := (jb != null and jb.pressed) or (jm != null and absf(jm.axis_value) > 0.5)
	if played and not Machine.headset_pad(event.device):
		_c_idle = 0.0


func _client_tick(delta: float) -> void:
	if _c_quitting:
		return
	_t -= delta
	_c_idle += delta
	if _t > 0.0:
		return
	var step := 1.0 - _t  # (seconds since the last check)
	_t = 1.0
	if _c_parent > 0 and not DirAccess.dir_exists_absolute("/proc/%d" % _c_parent):
		_client_quit("the VR host (pid %d) is gone" % _c_parent)
		return
	var mp := get_tree().get_multiplayer()
	var up := mp.multiplayer_peer != null and not mp.is_server() \
		and mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if up:
		if not _c_ever:
			print("TvSeat: the TV screen reached the VR host")
		_c_ever = true
		_c_unconnected = 0.0
	else:
		_c_unconnected += step
		var limit := CLIENT_LOST_GRACE if _c_ever else CLIENT_CONNECT_GRACE
		if _c_unconnected > limit:
			_client_quit("can't reach the VR host for %d s" % int(limit))
			return
	if _seated_here():
		_c_idle = 0.0
	elif _c_idle > CLIENT_IDLE_QUIT:
		_client_quit("nobody has played on the TV for %d s" % int(CLIENT_IDLE_QUIT))
		return
	_c_audio_t -= step
	if _c_audio_t <= 0.0:
		_c_audio_t = 5.0
		RoomAudio.use_room_output("TV screen")  # (SteamVR may move the default sink again)


func _seated_here() -> bool:
	var scene := get_tree().current_scene
	var party = scene.get("party") if scene != null else null
	return party is Node and is_instance_valid(party) and party.has_method("local_slots") and not party.call("local_slots").is_empty()


func _client_quit(why: String) -> void:
	_c_quitting = true
	print("TvSeat: closing the TV screen: %s (the TV shows the VR view again)" % why)
	preload("res://core/vr_watch.gd").quit_on_purpose(get_tree())
