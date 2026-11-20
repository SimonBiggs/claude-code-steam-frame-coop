extends Node
## VR watch (a service, core/services.gd): the arcade keeps going when the XR runtime goes away.
##
## Why (2026-11-13 18:19): the Frame's stream to SteamVR stalled, vrserver's own watchdog aborted it, and ~13 s later
## SteamVR's client library INSIDE our process (vrclient.so, "pipes.cpp: Stalled cross-thread pipe ... Fatal assert")
## called abort() and took the whole arcade down with it. That abort can't be caught from GDScript, so:
##  - While a VR session runs here, this ARMS a restart: it writes the restart file gdev run reads (tools/gdev,
##    RESTART; path in env GDEV_RESTART_FILE): "if I crash, start me again flat (--xr-mode off) with DUO_VR_LOST".
##  - It watches for the runtime going: OpenXR's session_loss_pending / instance_exiting, or SteamVR's vrserver
##    process vanishing (checked every second). Then it saves, asks for that restart AT ONCE ("now") and stops itself
##    before vrclient can abort us: back in ~5 s, flat, on the TV, in the arcade menu with the same game picked,
##    networking like a TV ("auto": the Decks find it again).
##  - The flat run after a loss shows a friendly card ("VR stopped — put the headset back on to rejoin"), then a
##    small banner, and watches for the headset coming back (vrserver running + the vrlink driver log saying the
##    headset connected after we started). In the arcade menu it then restarts INTO VR (DUO_VR_REJOIN); in a game it
##    says "back to the arcade menu to rejoin VR" (never pulls the TV players out of a game).
##  - Not under gdev run (no supervisor: GDEV_SUPERVISED unset) it says so and tries going flat in-process instead
##    (uninitialize OpenXR, use_xr off, back to the arcade): no promise vrclient won't abort anyway.
##  - Launched while SteamVR wasn't running (2026-11-19 19:17: "Failed to create XR instance", Godot ran flat): the
##    failed xrCreateInstance leaves SteamVR's vrclient.so loaded in our process, and when SteamVR then started it
##    abort()ed the arcade ("double free or corruption", 19:20:12) ~20 s later. So a run that WANTED VR but came up
##    flat waits for the headset like the flat run after a loss (quietly: no "VR stopped" card, only the banner once
##    the headset is back), restarts into VR from the arcade menu as soon as it is, and meanwhile arms a crash
##    restart (a plain relaunch: VR if the runtime is up, else flat and waiting again).
##  - While VR is live the main window's V-Sync is off (Godot's OpenXR docs: the runtime paces frames). With V-Sync
##    on, the TV's 60 Hz capped the arcade at 60 fps while the Frame asked for 90 Hz (2026-11-19 "it's going like 50").
##    Engine.max_fps caps it at VR_MAX_FPS so a paused session can't spin. Restored when VR ends.
##  - A CLEAN exit nobody asked for also comes back (2026-11-19 19:44: the headset went to standby, SteamVR went down
##    and Godot quit by itself, exit 0, no crash signal: the armed "if I crash" restart didn't fire and the arcade was
##    gone). Deliberate quits (the arcade's / pause menu's Quit, gdev commands) go through VrWatch.quit_on_purpose();
##    any other end of the tree while VR is live or we wait for it writes a "now" restart (unasked_quit_spec), and
##    tools/gdev stop marks its own stop so it never restarts.
##  - VR WANTED, one step (2026-11-20; 11-19 the kids asked Claude to "open Duo Arena on the Steam Frame", the arcade was
##    launched while SteamVR wasn't running and came up flat; starting SteamVR then crashed it). `arcade-vr` (tools/) or
##    the "Arcade VR" Steam shortcut (launch-vr.sh: DUO_VR_WANT=1) leaves a wish in .dev/vr_want; while it stands
##    (WANT_TTL) and VR isn't live, this starts SteamVR (steam://rungameid/250820), waits for the headset and restarts
##    the arcade INTO VR from the arcade menu, showing each step on the TV ("Starting VR...", "Put the Frame on and
##    choose Steam Machine", "Headset found!") and in .dev/vr_status (arcade-vr prints it). If OpenXR already failed
##    in this process (vrclient loaded) it first restarts flat with --xr-mode off, so SteamVR starting can't abort it.
##    Slow steps say so (SteamVR slow, headset not coming); the wish expires visibly ("VR didn't start").
##  - HEADSET ASLEEP (2026-11-19 19:37: the Frame went to standby at 10% battery, 7 min later SteamVR went down and took
##    the arcade with it). vrserver logs "0 - entering standby" / "0 - leaving standby" (device 0 = the headset). Asleep
##    longer than ASLEEP_GO_FLAT while VR is live: the arcade goes flat ON PURPOSE (before SteamVR can die under it), so
##    the TV can keep playing; the TV card then says "The headset is asleep — put it on to wake it; low battery? charge
##    it", and the arcade rejoins VR by itself when the headset wakes (standby left, or a new headset connect).
## The launcher decides nothing (Simon's rule): every decision is here, hot-reloadable.
## Tests (fake VR, no SteamVR): VR_WATCH_FAKE=1 with BOT_VR=1 counts as a live session (unless --xr-mode off was
## passed); VR_WATCH_SERVER names the runtime process to watch (default vrserver), VR_WATCH_LINK_LOG the headset
## log (default Steam's driver_vrlink.txt), VR_WATCH_SERVER_LOG the vrserver log (standby lines), VR_WATCH_STEAMVR_CMD a
## shell command run instead of starting SteamVR. tests/vr_watch_test.gd + tools/vr-survive-test.

const UiKit := preload("res://core/ui_kit.gd")
const Machine := preload("res://core/machine.gd")

const POLL := 1.0  # seconds between checks
const CARD_SECONDS := 9.0  # the big card, then a small banner
const REJOIN_DELAY := 2.0  # "Headset is back" shown this long before restarting into VR
const STOPPED_TEXT := "VR stopped — put the headset back on to rejoin"
const LINK_LOG := "~/.local/share/Steam/logs/driver_vrlink.txt"
## vrlink log lines: the headset (re)connected / the link or server went away.
const LINK_UP := "ReceivedHMDStaticProps"
const LINK_DOWN := ["startup with PID", "Connection inactive", "SVLServer::Shutdown"]
const VR_MAX_FPS := 150  # above the Frame's 90 / 120 Hz; only stops a paused session spinning
const QUIT_META := "duo_quit_on_purpose"
const XR_OFF_META := "vr_watch_xr_off"  # this process was started with --xr-mode off (read once)
## VR wanted (arcade-vr / launch-vr.sh) and the headset's standby.
const WANT_FILE := ".dev/vr_want"  # (in the project dir) unix time of the wish
const STATUS_FILE := ".dev/vr_status"  # "<unix>\t<stage>\t<title>\t<body>" for arcade-vr
const WANT_TTL := 900.0  # a wish older than this gives up, visibly
const STEAMVR_URL := "steam://rungameid/250820"
const STEAMVR_RETRY := 90.0  # ask Steam for SteamVR again if it still isn't up after this
const SLOW_STEAMVR := 120.0
const SLOW_HEADSET := 300.0
const SERVER_LOG := "~/.local/share/Steam/logs/vrserver.txt"
const STANDBY_IN := " - 0 - entering standby"
const STANDBY_OUT := " - 0 - leaving standby"
const SERVER_START := "startup with PID"
const ASLEEP_AFTER := 20.0  # standby this long = asleep (taking the headset off for a moment isn't)
const ASLEEP_GO_FLAT := 180.0  # live VR, headset asleep this long: go flat on purpose
const GAVE_UP_SECONDS := 20.0
## What the TV says at each step of "VR wanted" (title, body).
const WANT_TEXT := {
	"starting": ["Starting VR...", "Getting SteamVR ready on the Steam Machine."],
	"slow_steamvr": ["SteamVR is slow to start", "Still trying. If nothing happens, ask Claude to start VR again."],
	"steamvr_failed": ["Couldn't start SteamVR", "Ask Claude to start VR again."],
	"headset": ["Put the Frame on", "Then choose Steam Machine in the headset."],
	"slow_headset": ["Still waiting for the Frame", "Is it switched on and charged?\nPut it on and choose Steam Machine."],
	"asleep": ["The headset is asleep", "Put it on to wake it up.\nLow battery? Plug it in to charge."],
	"ready": ["Headset found!", "Starting VR..."],
	"ready_in_game": ["Headset ready!", "Go back to the arcade menu to start VR."],
	"ready_unsupervised": ["Headset ready!", "Restart the arcade to play in VR."],
	"gave_up": ["VR didn't start", "Ask Claude to try again."],
}

var started_at := 0.0  # unix time this process started watching
var lost_at := 0.0  # > 0: this is the flat run after VR stopped (DUO_VR_LOST) or a rejoin that found no headset
var lost_reason := ""  # tests read it
var live := false  # a VR session is running here
var servers: Array = []  # runtime process ids seen while live
var armed_for := ""  # the game id the armed restart file names
var headset_back := false
var state := "idle"  # idle | live | lost | rejoining | gone (tests read it)
var _t := 0.0
var _xr: XRInterface
var _signals_on := false
var _gone := false
var _ui: Control
var _card: Control
var _banner: Control
var _banner_label: Label
var _rejoin_t := -1.0
var launch_flat := false  # VR was wanted at launch but OpenXR didn't start (SteamVR not running): waiting quietly
var _vsync_saved := -1  # the window's V-Sync mode before VR turned it off (-1: not changed)
var _max_fps_saved := -1
var _handed_off := false  # replaced by a newer VrWatch (hot reload): leaving the tree then is not a quit
var want_stage := ""  # the "VR wanted" step shown now ("" = not wanting), tests read it
var asleep_since := 0.0  # unix time the headset went to standby (0 = awake / unknown)
var asleep_flat := false  # this flat run started because the headset fell asleep (DUO_VR_ASLEEP)
var _steamvr_asked_at := -1.0e9
var _server_seen_at := 0.0  # when vrserver was first seen running during this wish
var _want_ui: Control
var _want_title: Label
var _want_body: Label
var _gave_up_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_at = Time.get_unix_time_from_system()
	asleep_flat = OS.has_environment("DUO_VR_ASLEEP")
	OS.unset_environment("DUO_VR_ASLEEP")
	if OS.has_environment("DUO_VR_WANT"):
		# The env wish (launch-vr.sh) becomes the file wish and leaves the env: a later flat run in this process line
		# (VR ended on purpose) must not start SteamVR again by itself.
		OS.unset_environment("DUO_VR_WANT")
		if want_time() <= 0.0:
			want_vr("launched by the Arcade VR shortcut")
	if OS.has_environment("DUO_VR_LOST"):
		lost_at = maxf(1.0, float(OS.get_environment("DUO_VR_LOST")))
		lost_reason = "restarted flat after VR stopped"
		print("VrWatch: flat after VR stopped (DUO_VR_LOST); watching for the headset to come back")
	elif OS.has_environment("DUO_VR_REJOIN"):
		print("VrWatch: restarted to rejoin VR")
	elif xr_failed_at_launch():
		launch_flat = true
		lost_at = started_at
		lost_reason = "VR wasn't running at launch"
		print("VrWatch: launched flat: OpenXR didn't start (SteamVR not running?); watching for the headset to " +
			"join VR (and a crash restart is armed: SteamVR's vrclient is loaded in this process)")


## OpenXR was asked for (project setting, no --xr-mode off) but didn't start: Godot fell back to flat.
func xr_failed_at_launch() -> bool:
	if _flat_by_launch():
		return false  # (--xr-mode off: OpenXR never tried, nothing loaded)
	if OS.has_environment("VR_WATCH_FAKE"):
		return OS.has_environment("VR_WATCH_FAKE_FAILED")
	if DisplayServer.get_name() == "headless" or Machine.kind() == "deck":
		return false  # (a Deck has no SteamVR: its OpenXR never starts and no headset will come)
	if not bool(ProjectSettings.get_setting("xr/openxr/enabled", false)):
		return false
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and not xr.is_initialized()


func _handoff() -> Dictionary:
	_handed_off = true
	return {"started_at": started_at, "lost_at": lost_at, "lost_reason": lost_reason, "servers": servers,
		"armed_for": armed_for, "launch_flat": launch_flat, "vsync_saved": _vsync_saved, "max_fps_saved": _max_fps_saved,
		"asleep_since": asleep_since, "asleep_flat": asleep_flat, "steamvr_asked_at": _steamvr_asked_at,
		"server_seen_at": _server_seen_at}


func _adopt(s: Dictionary) -> void:
	started_at = float(s.get("started_at", started_at))
	lost_at = float(s.get("lost_at", 0.0))
	lost_reason = str(s.get("lost_reason", ""))
	servers = s.get("servers", [])
	armed_for = str(s.get("armed_for", ""))
	launch_flat = bool(s.get("launch_flat", false))
	_vsync_saved = int(s.get("vsync_saved", -1))
	_max_fps_saved = int(s.get("max_fps_saved", -1))
	asleep_since = float(s.get("asleep_since", 0.0))
	asleep_flat = bool(s.get("asleep_flat", false))
	_steamvr_asked_at = float(s.get("steamvr_asked_at", -1.0e9))
	_server_seen_at = float(s.get("server_seen_at", 0.0))


func _process(delta: float) -> void:
	if _rejoin_t >= 0.0:
		_rejoin_t -= delta
		if _rejoin_t < 0.0:
			_restart_into_vr()
	_t -= delta
	if _t > 0.0 or _gone:
		return
	_t = POLL
	var now_live := session_live()
	_pace_for_vr(now_live)
	_asleep_check(now_live)
	if _gone:
		return
	if now_live:
		_connect_signals()
		if not live:
			_on_live_start()
		_watch_live()
	elif live:
		live = false
		state = "idle"
		_disarm()
	if lost_at > 0.0:
		if now_live:
			print("VrWatch: VR is back")
			lost_at = 0.0
			launch_flat = false
			headset_back = false
			OS.unset_environment("DUO_VR_LOST")
			_clear_ui()
		else:
			_flat_tick()
	elif OS.has_environment("DUO_VR_REJOIN") and not now_live and Time.get_unix_time_from_system() - started_at > 3.0:
		# We restarted to rejoin VR but no session came up (the headset wasn't ready after all): flat again, waiting
		# for a NEWER headset connect than this start (so it never loops).
		OS.unset_environment("DUO_VR_REJOIN")
		lost_at = started_at
		lost_reason = "the headset wasn't ready to rejoin"
		print("VrWatch: rejoining VR found no headset session; flat, watching again")
	_want_check(now_live)
	if _gave_up_t >= 0.0:
		_gave_up_t -= POLL
		if _gave_up_t < 0.0:
			_clear_want_ui()
			want_stage = ""


## V-Sync off and an fps cap while VR is live (the runtime paces frames); the window's own settings back after.
func _pace_for_vr(now_live: bool) -> void:
	if now_live and _vsync_saved < 0:
		_vsync_saved = DisplayServer.window_get_vsync_mode()
		_max_fps_saved = Engine.max_fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = VR_MAX_FPS
		print("VrWatch: VR live: window V-Sync off (was mode %d), max_fps %d: the headset paces frames" % [
			_vsync_saved, VR_MAX_FPS])
	elif not now_live and _vsync_saved >= 0:
		DisplayServer.window_set_vsync_mode(_vsync_saved)
		Engine.max_fps = _max_fps_saved
		print("VrWatch: VR not live: window V-Sync mode %d, max_fps %d again" % [_vsync_saved, _max_fps_saved])
		_vsync_saved = -1
		_max_fps_saved = -1


# --- Live VR -------------------------------------------------------------------------------------------------------

## A VR session is running on this machine (a real OpenXR headset, or the fake one in tests).
func session_live() -> bool:
	if _flat_by_launch():
		return false
	if OS.has_environment("VR_WATCH_FAKE"):
		return OS.has_environment("BOT_VR")
	_xr = XRServer.find_interface("OpenXR")
	return _xr != null and _xr.is_initialized()


## Started with --xr-mode off (the flat restarts). OS.get_cmdline_args() leaves out the engine options Godot itself
## handled, --xr-mode among them (2026-11-20: a flat-first restart read as "OpenXR failed at launch" and restarted
## itself in a loop), so the process's own command line is read (/proc/self/cmdline), once.
func _flat_by_launch() -> bool:
	if not Engine.has_meta(XR_OFF_META):
		Engine.set_meta(XR_OFF_META, preload("res://core/quit_after.gd").engine_arg("--xr-mode") == "off")
	return bool(Engine.get_meta(XR_OFF_META))


func _connect_signals() -> void:
	if _signals_on:
		return
	var xr := XRServer.find_interface("OpenXR")
	if xr == null:
		return
	_signals_on = true
	for s in ["session_loss_pending", "instance_exiting"]:
		if xr.has_signal(s) and not xr.is_connected(s, _on_xr_gone):
			xr.connect(s, _on_xr_gone.bind(s))
	if xr.has_signal("session_stopping") and not xr.is_connected("session_stopping", _on_xr_stopping):
		xr.connect("session_stopping", _on_xr_stopping)


func _on_xr_gone(sig: String) -> void:
	lost("OpenXR " + sig)


func _on_xr_stopping() -> void:
	# The runtime paused us (headset asleep / dashboard): not a loss, it comes back by itself. Logged for the record.
	print("VrWatch: OpenXR session_stopping (paused by the runtime)")


func _on_live_start() -> void:
	live = true
	state = "live"
	servers = find_processes(server_name())
	print("VrWatch: VR session live; watching %s %s" % [server_name(), servers])
	_arm()


func _watch_live() -> void:
	if armed_for != _game_id():
		_arm()  # the restart brings the arcade back on the game being played
	if servers.is_empty():
		servers = find_processes(server_name())  # (started after us, or a runtime other than SteamVR: nothing)
		return
	for pid in servers:
		if DirAccess.dir_exists_absolute("/proc/%d" % int(pid)):
			return
	lost("%s stopped (pid %s)" % [server_name(), servers])


## The XR runtime went away: come back flat. Under gdev run: save, ask for an immediate restart, stop at once (no XR
## cleanup calls into a dead runtime). Otherwise: try to go flat in this process.
func lost(reason: String) -> void:
	if _gone:
		return
	lost_reason = reason
	print("VrWatch: VR LOST: %s" % reason)
	_flush_saves()
	if supervised():
		_gone = true
		state = "gone"
		_write_restart(_flat_spec(reason, true))
		print("VrWatch: restarting flat through gdev run")
		OS.kill(OS.get_process_id())
		return
	print("VrWatch: not under gdev run (no restart supervisor): going flat in this process (vrclient may still abort)")
	_go_flat_in_process()


func _go_flat_in_process() -> void:
	live = false
	state = "lost"
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized() and not OS.has_environment("VR_WATCH_FAKE"):
		get_viewport().use_xr = false
		xr.uninitialize()
	OS.unset_environment("BOT_VR")
	OS.set_environment("DUO_VR_LOST", str(Time.get_unix_time_from_system()))
	lost_at = Time.get_unix_time_from_system()
	started_at = lost_at
	_become_tv()
	_resume_in_arcade(_game_id())
	get_tree().change_scene_to_file("res://arcade.tscn")


## Network like a TV from now on (the arcade read "frame" at launch: host, no auto).
func _become_tv() -> void:
	OS.set_environment("DUO_JOIN_ORIGINAL", Machine.join_target())
	OS.set_environment("DUO_HOST_ORIGINAL", "")


func _resume_in_arcade(game_id: String) -> void:
	if game_id != "":
		OS.set_environment("DUO_RESUME_GAME", game_id)


# --- Flat after a loss ---------------------------------------------------------------------------------------------

func _flat_tick() -> void:
	state = "rejoining" if _rejoin_t >= 0.0 else "lost"
	if launch_flat and armed_for != "flat:" + _game_id():
		_arm_launch_flat()
	if _rejoin_t >= 0.0 or want_time() > 0.0:
		return  # (a VR wish: _want_check shows the steps and rejoins)
	headset_back = _headset_is_back()
	if launch_flat and not headset_back:
		return  # never started VR: nothing to say on the TV until a headset turns up
	_show_ui()
	if not headset_back:
		_set_banner(_stopped_line())
		return
	if not supervised():
		_set_banner("Headset is back! Restart the arcade from the headset to rejoin VR")
		return
	if not _in_arcade_menu():
		_set_banner("Headset is back! Go back to the arcade menu to rejoin VR")
		return
	print("VrWatch: headset is back: restarting into VR")
	_set_banner("Headset is back — starting VR...")
	_rejoin_t = REJOIN_DELAY


func _restart_into_vr() -> void:
	if _gone:
		return
	_gone = true
	state = "gone"
	_flush_saves()
	var env := {"DUO_VR_REJOIN": str(Time.get_unix_time_from_system())}
	if OS.has_environment("VR_WATCH_FAKE"):
		env["BOT_VR"] = "1"  # (tests: the fake headset comes back)
	if _game_id() != "":
		env["DUO_RESUME_GAME"] = _game_id()
	_write_restart({"args": [], "env": env, "unset": ["DUO_VR_LOST", "DUO_VR_ASLEEP", "DUO_VR_WANT"], "now": true,
		"reason": "headset is back"})
	quit_on_purpose(get_tree())


func _headset_is_back() -> bool:
	if find_processes(server_name()).is_empty():
		return false
	var srv := read_tail(server_log_path(), 65536)
	if standby_since(srv) > 0.0:
		return false  # still asleep
	# A new connect after we started, or (the link never dropped) the headset woke up after we started.
	return link_up_since(read_tail(link_log_path(), 65536), started_at + 1.0) or woke_since(srv, started_at + 1.0)


func _in_arcade_menu() -> bool:
	if not is_inside_tree():
		return false
	var s := get_tree().current_scene
	return s != null and s.scene_file_path == "res://arcade.tscn"


## Does this vrlink log text say the headset connected after `since` (unix time) and is still connected?
static func link_up_since(text: String, since: float) -> bool:
	var up := text.rfind(LINK_UP)
	if up < 0:
		return false
	for m in LINK_DOWN:
		if text.rfind(m) > up:
			return false
	var line_start := text.rfind("\n", up) + 1
	return log_time(text.substr(line_start, 40)) > since


## "Fri Nov 13 2026 18:18:31.835389 [Info] ..." (local time) -> unix time; 0 if it doesn't parse.
static func log_time(line: String) -> float:
	var p := line.strip_edges().split(" ", false)
	if p.size() < 5:
		return 0.0
	var month := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].find(p[1]) + 1
	var hms := p[4].split(":")
	if month <= 0 or hms.size() < 3 or not p[2].is_valid_int() or not p[3].is_valid_int():
		return 0.0
	var t := Time.get_unix_time_from_datetime_dict({"year": int(p[3]), "month": month, "day": int(p[2]),
		"hour": int(hms[0]), "minute": int(hms[1]), "second": int(float(hms[2]))})
	return float(t) - float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0 + fmod(float(hms[2]), 1.0)


# --- The card ------------------------------------------------------------------------------------------------------

func _show_ui() -> void:
	if _ui != null and is_instance_valid(_ui):
		return
	_ui = UiKit.ui_root(self, 120)
	_ui.name = "VrStopped"
	_card = UiKit.panel("card")
	_card.visible = not launch_flat  # "VR stopped" is wrong when VR never started: only the banner
	var box := UiKit.vbox()
	box.custom_minimum_size.x = 620.0
	var asleep := asleep_flat or standby_since(read_tail(server_log_path(), 65536)) > 0.0
	box.add_child(UiKit.title("The headset is asleep" if asleep else "VR stopped"))
	box.add_child(UiKit.paragraph(("Put it on to wake it up and rejoin.\nLow battery? Plug it in to charge." if asleep
		else "Put the headset back on to rejoin.") + "\nEveryone else can keep playing here.",
		"body", null, HORIZONTAL_ALIGNMENT_CENTER))
	_card.add_child(box)
	_ui.add_child(_card)
	UiKit.pin(_card, Control.PRESET_CENTER)
	UiKit.pop_in(_card)
	_banner = UiKit.panel("pill")
	_banner_label = UiKit.label(_stopped_line(), "small", null, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_child(_banner_label)
	_banner.visible = false
	_ui.add_child(_banner)
	UiKit.pin(_banner, Control.PRESET_CENTER_TOP)
	_banner.position.y += 12.0
	print("VrWatch: card shown: %s" % ui_text_all(_card))
	if not is_inside_tree():
		return  # (tests build it outside a running tree)
	get_tree().create_timer(CARD_SECONDS, true, false, true).timeout.connect(func() -> void:
		if _card != null and is_instance_valid(_card):
			UiKit.pop_out(_card)
		if _banner != null and is_instance_valid(_banner):
			_banner.visible = true)


func _set_banner(text: String) -> void:
	if _banner_label != null and is_instance_valid(_banner_label) and _banner_label.text != text:
		_banner_label.text = text
		if _banner.visible:
			UiKit.pin(_banner, Control.PRESET_CENTER_TOP)
			_banner.position.y += 12.0
		if not text.begins_with("VR stopped") and not text.begins_with("Headset asleep") and not text.begins_with("VR is off") \
				and _banner != null:
			_banner.visible = true  # news (headset back) shows at once, card or not


func _clear_ui() -> void:
	if _ui != null and is_instance_valid(_ui):
		var layer := _ui.get_parent()
		if layer is CanvasLayer and layer.get_parent() == self:
			layer.queue_free()
		else:
			_ui.queue_free()
	_ui = null


## The words on screen now (tests).
func ui_text() -> String:
	var out := []
	if _card != null and is_instance_valid(_card) and _card.visible:
		for l in _card.find_children("*", "Label", true, false):
			out.append((l as Label).text)
	if _banner != null and is_instance_valid(_banner) and _banner.visible:
		out.append(_banner_label.text)
	return " | ".join(out)


## The banner while flat after VR went: asleep (charge it), SteamVR gone entirely (nothing brings it back by itself:
## ask for it), or plain "VR stopped".
func _stopped_line() -> String:
	if standby_since(read_tail(server_log_path(), 65536)) > 0.0 or (asleep_flat and not find_processes(server_name()).is_empty()):
		return "Headset asleep — put it on (or charge it) to rejoin VR"
	if find_processes(server_name()).is_empty() and lost_at > 0.0 and not launch_flat:
		return "VR is off — ask Claude to start VR again"
	return STOPPED_TEXT


static func ui_text_all(n: Node) -> String:
	var out := []
	if n != null and is_instance_valid(n):
		for l in n.find_children("*", "Label", true, false):
			out.append((l as Label).text.replace("\n", " "))
	return " / ".join(out)


# --- VR wanted: one step from "play VR" to playing (arcade-vr, launch-vr.sh) ----------------------------------------

## Ask for VR (arcade-vr writes the same file from the shell).
func want_vr(why: String) -> void:
	_write_file(_proj_path(WANT_FILE), str(Time.get_unix_time_from_system()))
	print("VrWatch: VR wanted (%s)" % why)


## When VR was asked for (unix time), 0 if not (or the wish is older than WANT_TTL: then it gives up, visibly).
func want_time() -> float:
	var path := _proj_path(WANT_FILE)
	if not FileAccess.file_exists(path):
		return 0.0
	var t := FileAccess.get_file_as_string(path).strip_edges().to_float()
	if t <= 0.0:
		t = float(FileAccess.get_modified_time(path))
	return t


func _want_check(now_live: bool) -> void:
	var at := want_time()
	if at <= 0.0:
		if want_stage != "" and _gave_up_t < 0.0:
			_clear_want_ui()
			want_stage = ""
		return
	if now_live:
		print("VrWatch: VR wanted and VR is live: done")
		DirAccess.remove_absolute(_proj_path(WANT_FILE))
		_write_status("live", "VR is running", "")
		_clear_want_ui()
		want_stage = ""
		return
	if _gone or _rejoin_t >= 0.0:
		return
	var now := Time.get_unix_time_from_system()
	if now - at > WANT_TTL:
		print("VrWatch: VR wanted %d s ago and it never came: giving up (shown on the TV)" % int(now - at))
		DirAccess.remove_absolute(_proj_path(WANT_FILE))
		_set_want_stage("gave_up")
		_gave_up_t = GAVE_UP_SECONDS
		return
	var server := not find_processes(server_name()).is_empty()
	if not server and launch_flat and supervised():
		# OpenXR failed at launch, so SteamVR's vrclient is loaded in THIS process: SteamVR starting now would abort us
		# (2026-11-19 19:20 "double free or corruption"). Restart flat without OpenXR first; the wish stays.
		print("VrWatch: VR wanted but OpenXR already failed in this process: restarting flat (--xr-mode off) " +
			"before starting SteamVR")
		_set_want_stage("starting")
		_gone = true
		state = "gone"
		_flush_saves()
		_write_restart(want_flat_spec(_game_id()))
		quit_on_purpose(get_tree())
		return
	state = "wanting"
	var stage := ""
	if not server:
		_server_seen_at = 0.0
		if now - _steamvr_asked_at > STEAMVR_RETRY:
			if not _start_steamvr():
				_set_want_stage("steamvr_failed")
				return
		stage = "slow_steamvr" if now - at > SLOW_STEAMVR else "starting"
	else:
		if _server_seen_at <= 0.0:
			_server_seen_at = now
			print("VrWatch: SteamVR is running; waiting for the headset")
		var srv_log := read_tail(server_log_path(), 65536)
		var since := started_at + 1.0 if (lost_at > 0.0 or OS.has_environment("DUO_VR_REJOIN")) else 0.0
		var connected := link_up_since(read_tail(link_log_path(), 65536), since) or (since > 0.0 and woke_since(srv_log, since))
		var sb := standby_since(srv_log)
		if sb > 0.0 and now - sb > ASLEEP_AFTER:
			stage = "asleep"
		elif not connected or sb > 0.0:
			stage = "slow_headset" if now - maxf(at, _server_seen_at) > SLOW_HEADSET else "headset"
		elif not supervised():
			stage = "ready_unsupervised"
		elif not _in_arcade_menu():
			stage = "ready_in_game"
		else:
			stage = "ready"
	_set_want_stage(stage)
	if stage == "ready":
		print("VrWatch: VR wanted and the headset is connected: restarting into VR")
		_rejoin_t = REJOIN_DELAY


## The flat restart before starting SteamVR (no OpenXR in the process at all), same game, wish kept.
static func want_flat_spec(game_id: String) -> Dictionary:
	var env := {}
	if game_id != "":
		env["DUO_RESUME_GAME"] = game_id
	return {"args": ["--xr-mode", "off"], "env": env,
		"unset": ["DUO_VR_LOST", "DUO_VR_REJOIN", "BOT_VR", "DUO_VR_WANT", "ARCADE_GAME"], "now": true,
		"reason": "VR wanted: restarting flat without OpenXR before starting SteamVR"}


## Ask Steam to start SteamVR (or the test's command). False (said in the log) if it couldn't even be asked.
func _start_steamvr() -> bool:
	_steamvr_asked_at = Time.get_unix_time_from_system()
	var cmd := OS.get_environment("VR_WATCH_STEAMVR_CMD")
	var pid := OS.create_process("sh", ["-c", cmd]) if cmd != "" else OS.create_process("steam", [STEAMVR_URL])
	if pid <= 0:
		push_warning("VrWatch: VR wanted but SteamVR couldn't be started (%s)" % (cmd if cmd != "" else "steam " + STEAMVR_URL))
		return false
	print("VrWatch: VR wanted: asked Steam to start SteamVR (%s, pid %d)" % [cmd if cmd != "" else "steam " + STEAMVR_URL, pid])
	return true


func _set_want_stage(stage: String) -> void:
	if stage == want_stage and _want_ui != null and is_instance_valid(_want_ui):
		return
	var words: Array = WANT_TEXT.get(stage, ["", ""])
	if stage != want_stage:
		print("VrWatch: VR wanted: %s — %s" % [words[0], String(words[1]).replace("\n", " ")])
		_write_status(stage, words[0], words[1])
	want_stage = stage
	if _card != null and is_instance_valid(_card):
		_card.visible = false  # one message at a time: the steps replace "VR stopped"
	if _banner != null and is_instance_valid(_banner):
		_banner.visible = false
	if _want_ui == null or not is_instance_valid(_want_ui):
		_want_ui = UiKit.ui_root(self, 121)
		_want_ui.name = "VrWanted"
		var card := UiKit.panel("card")
		card.name = "WantCard"
		var box := UiKit.vbox()
		box.custom_minimum_size.x = 640.0
		_want_title = UiKit.title(words[0])
		box.add_child(_want_title)
		_want_body = UiKit.paragraph(words[1], "body", null, HORIZONTAL_ALIGNMENT_CENTER)
		box.add_child(_want_body)
		card.add_child(box)
		_want_ui.add_child(card)
		UiKit.pin(card, Control.PRESET_CENTER_TOP)
		card.position.y += 24.0
		UiKit.pop_in(card)
	else:
		_want_title.text = words[0]
		_want_body.text = words[1]
		var card := _want_ui.get_node_or_null("WantCard") as Control
		if card != null:
			UiKit.pin(card, Control.PRESET_CENTER_TOP)
			card.position.y += 24.0


func _clear_want_ui() -> void:
	if _want_ui != null and is_instance_valid(_want_ui):
		var layer := _want_ui.get_parent()
		if layer is CanvasLayer and layer.get_parent() == self:
			layer.queue_free()
		else:
			_want_ui.queue_free()
	_want_ui = null


## The "VR wanted" words on screen now (tests).
func want_text() -> String:
	return ui_text_all(_want_ui) if _want_ui != null and is_instance_valid(_want_ui) else ""


func _write_status(stage: String, title: String, body: String) -> void:
	_write_file(_proj_path(STATUS_FILE), "%d\t%s\t%s\t%s\n" % [int(Time.get_unix_time_from_system()), stage, title,
		body.replace("\n", " ")])


# --- Headset asleep ------------------------------------------------------------------------------------------------

## Live VR: notice the headset's standby; asleep too long -> go flat on purpose (and rejoin when it wakes).
func _asleep_check(now_live: bool) -> void:
	if not now_live:
		asleep_since = 0.0
		return
	var sb := standby_since(read_tail(server_log_path(), 65536))
	var now := Time.get_unix_time_from_system()
	if sb <= 0.0:
		if asleep_since > 0.0:
			print("VrWatch: the headset woke up")
		asleep_since = 0.0
		return
	if asleep_since <= 0.0 and now - sb > ASLEEP_AFTER:
		asleep_since = sb
		print("VrWatch: the headset is asleep (standby since %d s); going flat if it sleeps %d s" % [int(now - sb),
			int(ASLEEP_GO_FLAT)])
	if asleep_since > 0.0 and now - asleep_since > ASLEEP_GO_FLAT and supervised() and not _gone:
		# Before SteamVR dies under us (2026-11-19: standby 19:37, SteamVR down + arcade gone 19:44): the TV gets a
		# working flat arcade with "the headset is asleep" on it, and VR comes back when the headset wakes.
		print("VrWatch: the headset has been asleep %d s: going flat (the TV keeps playing; VR rejoins when it wakes)" %
			int(now - asleep_since))
		lost_reason = "headset asleep"
		_gone = true
		state = "gone"
		_flush_saves()
		_write_restart(_flat_spec("headset asleep", true))
		quit_on_purpose(get_tree())


## When the headset went to standby, if it is in standby now per this vrserver log text (0 = awake / unknown).
static func standby_since(text: String) -> float:
	var i := text.rfind(STANDBY_IN)
	if i < 0 or text.rfind(STANDBY_OUT) > i or text.rfind(SERVER_START) > i:
		return 0.0
	return log_time(text.substr(text.rfind("\n", i) + 1, 40))


## Did the headset leave standby after `since` (unix time) and stay awake?
static func woke_since(text: String, since: float) -> bool:
	var o := text.rfind(STANDBY_OUT)
	if o < 0 or text.rfind(STANDBY_IN) > o:
		return false
	return log_time(text.substr(text.rfind("\n", o) + 1, 40)) > since


static func server_log_path() -> String:
	var p := OS.get_environment("VR_WATCH_SERVER_LOG") if OS.has_environment("VR_WATCH_SERVER_LOG") else SERVER_LOG
	return OS.get_environment("HOME") + p.substr(1) if p.begins_with("~") else p


static func _proj_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://" + rel)


static func _write_file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		push_warning("VrWatch: can't write %s (%d)" % [path, FileAccess.get_open_error()])
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)


# --- Restart file (tools/gdev RESTART) -----------------------------------------------------------------------------

## Every quit somebody chose (the arcade's Quit, the pause menu's Quit, a dev command) goes through here, so the
## arcade only comes back after quits nobody asked for (tests/vr_watch_test.gd fails a bare quit() in arcade/ core/).
static func quit_on_purpose(tree: SceneTree, code: int = 0) -> void:
	Engine.set_meta(QUIT_META, true)
	tree.quit(code)


func _exit_tree() -> void:
	if _gone or _handed_off or is_queued_for_deletion() or Engine.has_meta(QUIT_META) or not supervised():
		return
	var spec := unasked_quit_spec()
	if spec.is_empty():
		return
	print("VrWatch: the arcade is closing and nobody asked (%s): restarting it through gdev run" % spec.reason)
	_write_restart(spec)


## The restart for a quit nobody asked for ({} = none: plain flat play, nothing to come back for).
func unasked_quit_spec() -> Dictionary:
	if live:
		return _flat_spec("closed by itself while VR was live (OpenXR / SteamVR went away)", true)
	if launch_flat:
		var s := launch_flat_spec(_game_id())
		s.now = true
		s.reason = "closed by itself while flat waiting for VR"
		return s
	if lost_at > 0.0:
		return _flat_spec("closed by itself while flat after VR stopped", true)
	return {}


static func supervised() -> bool:
	return OS.get_environment("GDEV_SUPERVISED") == "1" and OS.get_environment("GDEV_RESTART_FILE") != ""


func _arm() -> void:
	armed_for = _game_id()
	if supervised():
		_write_restart(_flat_spec("the VR runtime crashed", false))


## Flat because VR didn't start at launch: if SteamVR's vrclient (loaded by the failed start) aborts us, start again
## as a plain launch (VR if the runtime is up by then), in the same game.
func _arm_launch_flat() -> void:
	armed_for = "flat:" + _game_id()
	if supervised():
		_write_restart(launch_flat_spec(_game_id()))


static func launch_flat_spec(game_id: String) -> Dictionary:
	var env := {}
	if game_id != "":
		env["DUO_RESUME_GAME"] = game_id
	return {"args": [], "env": env, "unset": ["DUO_VR_LOST", "DUO_VR_REJOIN", "BOT_VR", "DUO_VR_WANT"], "now": false,
		"reason": "crashed while flat waiting for VR (SteamVR's vrclient is loaded in the arcade)"}


func _disarm() -> void:
	armed_for = ""
	if supervised() and not _gone:
		DirAccess.remove_absolute(OS.get_environment("GDEV_RESTART_FILE"))


func _flat_spec(reason: String, now: bool) -> Dictionary:
	var env := {"DUO_VR_LOST": str(Time.get_unix_time_from_system())}
	if asleep_since > 0.0:
		env["DUO_VR_ASLEEP"] = "1"  # the flat run's card: "the headset is asleep" (charge it), not just "VR stopped"
	if _game_id() != "":
		env["DUO_RESUME_GAME"] = _game_id()
	return {"args": ["--xr-mode", "off"], "env": env,
		"unset": ["BOT_VR", "ARCADE_GAME", "DUO_VR_REJOIN", "DUO_HOST", "DUO_JOIN", "DUO_VR_WANT"], "now": now, "reason": reason}


func _write_restart(spec: Dictionary) -> void:
	var path := OS.get_environment("GDEV_RESTART_FILE")
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("VrWatch: can't write the restart file %s (%d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(spec))
	f.close()
	DirAccess.rename_absolute(tmp, path)


func _flush_saves() -> void:
	for n in get_tree().root.find_children("*", "", true, false):
		if n.has_method("save_now") and n.has_method("has_unsaved_changes") and n.call("has_unsaved_changes"):
			n.call("save_now")


## The arcade game being played ("" in the menu): res://games/<id>/... -> <id>.
func _game_id() -> String:
	if not is_inside_tree():
		return ""
	var s := get_tree().current_scene
	if s == null or not s.scene_file_path.begins_with("res://games/"):
		return ""
	return s.scene_file_path.trim_prefix("res://games/").get_slice("/", 0)


# --- Processes and logs --------------------------------------------------------------------------------------------

static func server_name() -> String:
	return OS.get_environment("VR_WATCH_SERVER") if OS.has_environment("VR_WATCH_SERVER") else "vrserver"


static func link_log_path() -> String:
	var p := OS.get_environment("VR_WATCH_LINK_LOG") if OS.has_environment("VR_WATCH_LINK_LOG") else LINK_LOG
	return OS.get_environment("HOME") + p.substr(1) if p.begins_with("~") else p


## Ids of this user's running processes called `comm_name` (Linux /proc).
static func find_processes(comm_name: String) -> Array:
	var out := []
	for d in DirAccess.get_directories_at("/proc"):
		if d.is_valid_int() and proc_comm(int(d)) == comm_name:
			out.append(int(d))
	return out


## A process's name (/proc/<pid>/comm; get_file_as_string reads /proc files as empty: their length is 0).
static func proc_comm(pid: int) -> String:
	var f := FileAccess.open("/proc/%d/comm" % pid, FileAccess.READ)
	return f.get_line().strip_edges() if f != null else ""


static func read_tail(path: String, n: int) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var size := f.get_length()
	f.seek(maxi(0, size - n))
	return f.get_buffer(mini(n, size)).get_string_from_utf8()