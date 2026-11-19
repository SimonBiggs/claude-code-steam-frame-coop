extends Node
## TV share (a service, core/services.gd): a VR launch never takes the TV off a game someone is playing there.
##
## Why (2026-11-14): someone in the Steam Frame launched the arcade while the kids played Stick Fight on the TV. Steam
## runs a Frame launch on the Steam Machine, so the arcade's window opened on the TV, gamescope focused it (the newest
## window wins) and Stick Fight vanished behind it.
## What this does: while this run is a VR one (a live VR session, or the flat run waiting for the headset after VR
## stopped: DUO_VR_LOST / DUO_VR_REJOIN) AND another Steam game is running on this machine, the arcade's window is
## taken off the screen (X11 unmap via xdotool; Godot can't hide its main window itself). gamescope / KWin then show
## the other game again and give it the focus. XR keeps rendering (Godot draws to the unmapped window as usual; the
## headset has its own swapchain). The VR player sees a card "TV busy: VR only"; real controllers on this machine
## (the TV game's pads) can't seat or drive menus (pads_off(): core/party.gd, core/ui_input.gd). When the other game
## ends, the window comes back and the TV can join as usual.
## Sound: SteamVR already moves the default sink to the headset ("vrlink-sink") while the Frame streams.
## Never a silent fallback: when the window can't be taken off (not X11, no xdotool), it says so in the log and on the
## VR card, and the TV shows the arcade as before.
## "Another Steam game": a `reaper SteamLaunch AppId=N` process that is not one of our own ancestors (our own launch)
## and not SteamVR. Read in a worker thread every POLL seconds.
## Tests: tests/tv_share_test.gd (parsing, decisions, guards). TV_SHARE_FAKE=<file>: read the process list from that
## file (lines "pid cmdline") instead of /proc; TV_SHARE_FORCE_VR=1 counts this run as a VR one (offscreen checks).

const POLL := 3.0
## Steam apps that are not "a game on the TV": SteamVR (Steam's gameprocess_log, 2026-11-14: the arcade came in as
## "reaper SteamLaunch AppId=2443052841", Stick Fight as AppId=674940; SteamVR started inside the arcade's tree, no reaper).
const IGNORE_APPS := ["250820"]
const CARD_LINE := "TV busy: playing in VR only"
const META := "tv_share_hidden"

var hidden := false  # our window is off the screen (tests read it)
var others: Array = []  # the other games' app ids last seen
var problem := ""  # why the window could not be taken off (tests read it)
var _t := 1.0
var _task := -1
var _result: Array = []
var _mutex := Mutex.new()
var _ancestors: Array = []
var _told := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ancestors = ancestors(OS.get_process_id())


func _handoff() -> Dictionary:
	return {"hidden": hidden, "others": others, "told": _told}


func _adopt(s: Dictionary) -> void:
	hidden = bool(s.get("hidden", false))
	others = s.get("others", [])
	_told = bool(s.get("told", false))


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_mutex.lock()
		var found := _result.duplicate()
		_mutex.unlock()
		_decide(found)
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL
	if not vr_run() and not hidden:
		return
	var fake := OS.get_environment("TV_SHARE_FAKE")
	var anc := _ancestors.duplicate()
	_task = WorkerThreadPool.add_task(func() -> void:
		var r := other_games(read_fake(fake) if fake != "" else read_procs(), anc)
		_mutex.lock()
		_result = r
		_mutex.unlock())


## This run belongs to the VR player: a live VR session, the flat run waiting for the headset to come back, or a test.
func vr_run() -> bool:
	if OS.has_environment("TV_SHARE_FORCE_VR") or OS.has_environment("DUO_VR_LOST") or OS.has_environment("DUO_VR_REJOIN"):
		return true
	var w := get_node_or_null("/root/VrWatch")
	if w != null and w.has_method("session_live"):
		return bool(w.call("session_live"))
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and xr.is_initialized()


func _decide(found: Array) -> void:
	others = found
	var want_hidden := vr_run() and not found.is_empty()
	if want_hidden == hidden:
		return
	if want_hidden:
		print("TvShare: another game is on the TV (Steam app %s): VR only, giving the TV back" % ", ".join(found))
		problem = _set_mapped(false)
		if problem != "":
			print("TvShare: CAN'T give the TV back: %s (the arcade stays on the TV)" % problem)
			_tell("TV busy: sorry, I took it")
			return
		hidden = true
		Engine.set_meta(META, true)
		_tell(CARD_LINE)
	else:
		print("TvShare: the TV is free again: the arcade is back on it")
		var p := _set_mapped(true)
		if p != "":
			print("TvShare: CAN'T show the arcade on the TV again: %s" % p)
		hidden = false
		Engine.set_meta(META, false)


## Unmap / map our main window. Returns "" or why it couldn't.
func _set_mapped(on: bool) -> String:
	if DisplayServer.get_name() != "X11":
		return "display server is %s, not X11" % DisplayServer.get_name()
	var wid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if wid == 0:
		return "no X window id"
	var out := []
	var code := OS.execute("xdotool", ["windowmap" if on else "windowunmap", str(wid)], out, true)
	if code != 0:
		return "xdotool failed (exit %d): %s" % [code, "".join(out).strip_edges()]
	return ""


func _tell(line: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var scene := get_tree().current_scene
	if cam is XRCamera3D and scene != null:
		preload("res://core/story_card.gd").show_vr(scene, cam, {"who": "TV", "line": line, "duration": 5.0})
	print("TvShare card: %s" % line)


## True while the TV belongs to another game: real controllers here are that game's, not ours.
static func pads_off() -> bool:
	return bool(Engine.get_meta(META, false))


# --- Finding other games -------------------------------------------------------------------------------------------

## [{pid, ppid, cmd}] for every `reaper` process (Steam's launcher for each game) on this machine.
static func read_procs() -> Array:
	var out := []
	for d in DirAccess.get_directories_at("/proc"):
		if not d.is_valid_int():
			continue
		var f := FileAccess.open("/proc/%s/comm" % d, FileAccess.READ)
		if f == null or f.get_line().strip_edges() != "reaper":
			continue
		out.append({"pid": int(d), "cmd": cmdline(int(d))})
	return out


static func cmdline(pid: int) -> String:
	var f := FileAccess.open("/proc/%d/cmdline" % pid, FileAccess.READ)
	if f == null:
		return ""
	var b := f.get_buffer(8192)
	for i in b.size():
		if b[i] == 0:
			b[i] = 32
	return b.get_string_from_utf8().strip_edges()


## Test list: one "pid cmdline" per line.
static func read_fake(path: String) -> Array:
	var out := []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var sp := line.strip_edges().split(" ", false, 1)
		if sp.size() == 2 and sp[0].is_valid_int():
			out.append({"pid": int(sp[0]), "cmd": sp[1]})
	return out


## The Steam app ids of games running that are not us (not one of `ancestors`) and not SteamVR.
static func other_games(procs: Array, ancestors_of_me: Array) -> Array:
	var out := []
	var re := RegEx.create_from_string("\\bSteamLaunch\\b.*\\bAppId=(\\d+)")
	for p in procs:
		if ancestors_of_me.has(int(p.pid)):
			continue
		var m := re.search(str(p.cmd))
		if m == null:
			continue
		var app := m.get_string(1)
		if app in IGNORE_APPS or app == "0" or out.has(app):
			continue
		out.append(app)
	return out


## pid, its parent, grandparent ... up to init.
static func ancestors(pid: int) -> Array:
	var out := []
	var p := pid
	while p > 1 and out.size() < 64:
		out.append(p)
		var f := FileAccess.open("/proc/%d/stat" % p, FileAccess.READ)
		if f == null:
			break
		var s := f.get_line()
		var close := s.rfind(")")
		var parts := s.substr(close + 2).split(" ")
		p = int(parts[1]) if parts.size() > 1 else 0
	return out
