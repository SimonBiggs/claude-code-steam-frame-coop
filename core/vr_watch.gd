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
## The launcher decides nothing (Simon's rule): every decision is here, hot-reloadable.
## Tests (fake VR, no SteamVR): VR_WATCH_FAKE=1 with BOT_VR=1 counts as a live session (unless --xr-mode off was
## passed); VR_WATCH_SERVER names the runtime process to watch (default vrserver), VR_WATCH_LINK_LOG the headset
## log (default Steam's driver_vrlink.txt). tests/vr_watch_test.gd + tools/vr-survive-test.

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_at = Time.get_unix_time_from_system()
	if OS.has_environment("DUO_VR_LOST"):
		lost_at = maxf(1.0, float(OS.get_environment("DUO_VR_LOST")))
		lost_reason = "restarted flat after VR stopped"
		print("VrWatch: flat after VR stopped (DUO_VR_LOST); watching for the headset to come back")
	elif OS.has_environment("DUO_VR_REJOIN"):
		print("VrWatch: restarted to rejoin VR")


func _handoff() -> Dictionary:
	return {"started_at": started_at, "lost_at": lost_at, "lost_reason": lost_reason, "servers": servers,
		"armed_for": armed_for}


func _adopt(s: Dictionary) -> void:
	started_at = float(s.get("started_at", started_at))
	lost_at = float(s.get("lost_at", 0.0))
	lost_reason = str(s.get("lost_reason", ""))
	servers = s.get("servers", [])
	armed_for = str(s.get("armed_for", ""))


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


# --- Live VR -------------------------------------------------------------------------------------------------------

## A VR session is running on this machine (a real OpenXR headset, or the fake one in tests).
func session_live() -> bool:
	if _flat_by_launch():
		return false
	if OS.has_environment("VR_WATCH_FAKE"):
		return OS.has_environment("BOT_VR")
	_xr = XRServer.find_interface("OpenXR")
	return _xr != null and _xr.is_initialized()


func _flat_by_launch() -> bool:
	var a := OS.get_cmdline_args()
	var i := a.find("--xr-mode")
	return i >= 0 and i + 1 < a.size() and a[i + 1] == "off"


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
	_show_ui()
	if _rejoin_t >= 0.0:
		return
	headset_back = _headset_is_back()
	if not headset_back:
		_set_banner(STOPPED_TEXT)
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
	_write_restart({"args": [], "env": env, "unset": ["DUO_VR_LOST"], "now": true, "reason": "headset is back"})
	get_tree().quit()


func _headset_is_back() -> bool:
	if find_processes(server_name()).is_empty():
		return false
	return link_up_since(read_tail(link_log_path(), 65536), started_at + 1.0)


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
	var box := UiKit.vbox()
	box.custom_minimum_size.x = 620.0
	box.add_child(UiKit.title("VR stopped"))
	box.add_child(UiKit.paragraph("Put the headset back on to rejoin.\nEveryone else can keep playing here.",
		"body", null, HORIZONTAL_ALIGNMENT_CENTER))
	_card.add_child(box)
	_ui.add_child(_card)
	UiKit.pin(_card, Control.PRESET_CENTER)
	UiKit.pop_in(_card)
	_banner = UiKit.panel("pill")
	_banner_label = UiKit.label(STOPPED_TEXT, "small", null, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_child(_banner_label)
	_banner.visible = false
	_ui.add_child(_banner)
	UiKit.pin(_banner, Control.PRESET_CENTER_TOP)
	_banner.position.y += 12.0
	print("VrWatch: card shown: VR stopped / Put the headset back on to rejoin.")
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
		if not text.begins_with("VR stopped") and _banner != null:
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


# --- Restart file (tools/gdev RESTART) -----------------------------------------------------------------------------

static func supervised() -> bool:
	return OS.get_environment("GDEV_SUPERVISED") == "1" and OS.get_environment("GDEV_RESTART_FILE") != ""


func _arm() -> void:
	armed_for = _game_id()
	if supervised():
		_write_restart(_flat_spec("the VR runtime crashed", false))


func _disarm() -> void:
	armed_for = ""
	if supervised() and not _gone:
		DirAccess.remove_absolute(OS.get_environment("GDEV_RESTART_FILE"))


func _flat_spec(reason: String, now: bool) -> Dictionary:
	var env := {"DUO_VR_LOST": str(Time.get_unix_time_from_system())}
	if _game_id() != "":
		env["DUO_RESUME_GAME"] = _game_id()
	return {"args": ["--xr-mode", "off"], "env": env,
		"unset": ["BOT_VR", "ARCADE_GAME", "DUO_VR_REJOIN", "DUO_HOST", "DUO_JOIN"], "now": now, "reason": reason}


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