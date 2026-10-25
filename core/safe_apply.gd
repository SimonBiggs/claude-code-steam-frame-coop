extends Node
## Safe apply: new code reaches every machine at once (duo-deploy and LAN updates write files into the game folder
## straight away) but is only SWITCHED ON at a safe point, so a deploy never changes a game while someone is playing it
## (Simon, 2026-10-24: "deployment should be all the time" + "make deployment not interrupt play").
## docs/MULTI_MACHINE.md "Deploys while playing".
##
## How: the gdev bridge (addons/gdev/bridge.gd) hot-reloads any .gd/.tscn whose file changed. This node runs just
## before the bridge's 4-times-a-second scan (process_priority) and, for a file that must wait, records the new
## mtime + md5 in the bridge's own tables so the bridge sees nothing new. The file waits in `held` (path -> the md5
## the game is still running). Applying puts the old md5 back and runs the bridge's scan, which reloads as usual
## (in place, keeping state, calling _on_hot_reload()). No bridge change, so no relaunch was needed to ship this.
##
## When does a held file apply?
## - Mid-game: core/, tests/, the running game's own folder and anything already loaded wait for the arcade menu.
##   Other games' files, arcade/ scripts and anything not loaded go through (nothing is running them).
##   A game may mark a safe moment itself (between levels): get_tree().current_scene.set_meta("safe_to_apply", true),
##   used only when it isn't networked, so machines never play different versions.
## - In the arcade menu: once the files have stopped changing for SETTLE_MS (a deploy copies many files; applying half
##   of one gave transitional errors). Alone: right away. In a lobby, all machines switch TOGETHER: each sends the
##   lobby host its disk version (hash of every game script), and the host says "apply now" once everyone has the same
##   files (or after LOBBY_WAIT_MS, so one missing machine can't hold everyone up for long).
## - Starting a game applies everything first (arcade._launch), and the lobby host holds a start back while a
##   machine's files are still arriving or differ (START_WAIT_MS at most), so nobody plays a mixed-version game.
## A small "update ready" note sits in the corner while something waits; never a popup.
## Opt out (apply at once, the old way): env GDEV_APPLY=now. Offscreen test runs (godot.ts) apply at once unless
## GDEV_APPLY=safe. On a machine: touch <game>/.dev/apply_now to apply what's waiting immediately.

signal applied(paths: Array)

const SELF := "res://core/safe_apply.gd"
const ARCADE_SCENE := "res://arcade.tscn"
const NODE_NAME := "SafeApply"
const MANAGED := ["res://core/", "res://games/", "res://arcade/", "res://tests/", "res://arcade.tscn"]
const SETTLE_MS := 1000
const LOBBY_WAIT_MS := 20000  # lobby host: apply anyway this long after something started waiting
const CLIENT_WAIT_MS := 30000  # joiner: apply anyway if the host never says (a host without safe apply)
const START_WAIT_MS := 15000  # lobby host: start anyway after holding a start back this long
const STATE_EVERY_MS := 3000

var held := {}  # path -> md5 of the version still running
var last_change_ms := -100000  # last time a game file changed on disk
var held_since_ms := 0
var members := {}  # lobby host: peer -> {"ver": String, "held": int}
var stats := {"held": 0, "released": 0, "applies": 0, "lobby_applies": 0, "scan_us": 0, "scan_us_max": 0}
var _apply_now_until := 0
var _since_scan := 0.0
const SCAN_EVERY := 1.0  # seconds between file checks while holding (the bridge's own 0.25 s cadence is slowed to this:
# two checks a second cost more than the bridge's four did, and held code doesn't need to be noticed sooner)  # .dev/apply_now was touched: anything arriving until then applies at once
var last_apply := {}  # {"ms": int, "unix": float, "paths": int, "why": String}
var _ver := ""
var _ver_dirty := true
var _known_count := 0
var _sent := ""
var _sent_ms := 0
var _pending_since := 0  # lobby host: when something first waited somewhere in the lobby
var _start_wait_since := 0
var _lobby_applied_ms := -100000
var _note_layer: CanvasLayer
var _note: Label
var mode: String = OS.get_environment("GDEV_APPLY") if OS.has_environment("GDEV_APPLY") \
		else ("now" if OS.has_environment("GDEV_CONTROL_PORT") else "safe")


# --- For other scripts (static: fine to call when there is no SafeApply node) ---------------------------------------

static func node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NODE_NAME) if tree else null


## Make the node once per launch (the arcade calls this). Needs the gdev bridge: without it nothing hot-reloads anyway.
static func ensure() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.has_meta("safe_apply") or tree.root.get_node_or_null("GDev") == null:
		return
	tree.root.set_meta("safe_apply", true)  # (the node is added at the end of the frame: never make two)
	var n: Node = (load(SELF) as GDScript).new()
	n.name = NODE_NAME
	tree.root.add_child.call_deferred(n)


## True in the arcade menu while no game is starting: code may switch now (also the gate for LAN updates).
static func safe_now() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var s := tree.current_scene if tree else null
	if s == null or s.scene_file_path != ARCADE_SCENE:
		return false
	return not bool(s.get("starting"))


static func held_count() -> int:
	var n := node()
	return n.held.size() if n else 0


## Apply everything that waits (a game is about to start, or a game follows another machine into a new game).
## Deferred: the caller's own script may be one of the files, and a script must never be swapped while one of its
## functions is running. Returns true if anything waits: the caller should go on a moment later (next frame or after).
static func flush(why: String = "starting a game", for_scene_change: bool = false) -> bool:
	var n := node()
	if n == null:
		return false
	n.check_now()  # (files that arrived since the last check count too)
	if n.held.is_empty():
		return false
	n.apply_all.call_deferred(why, for_scene_change)
	return true


## Leave the running game for another scene (the arcade menu, or the game another machine plays): a safe point, so
## what waited switches on first, then the scene changes (both at the end of this frame, in that order). Use this
## instead of change_scene_to_file when leaving a game.
static func change_scene(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	flush("leaving for " + path.get_file(), true)
	tree.change_scene_to_file.call_deferred(path)


## Lobby host: may a game start now? False while a lobby machine's files are still arriving, differ from ours, or wait
## to be applied (then it asks everyone to apply). Gives up holding after START_WAIT_MS.
static func start_ok() -> bool:
	var n := node()
	return n == null or n._start_ok()


# --- The bridge's tables -----------------------------------------------------------------------------------------------

func _bridge() -> Node:
	var b := get_node_or_null("/root/GDev")
	if b == null or not ("mtimes" in b and "hashes" in b and "poll_t" in b):
		return null
	return b


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000  # before the bridge (an autoload at priority 0) in every frame
	print("SafeApply: ready (%s)" % ("apply at a safe point" if mode == "safe" else "apply at once"))


func _process(delta: float) -> void:
	var b := _bridge()
	if b == null:
		return
	var due := float(b.poll_t) + delta >= 0.25  # the bridge scans this frame
	_since_scan += delta
	if mode == "safe" and due and _since_scan < SCAN_EVERY and held.is_empty() \
			and Time.get_ticks_msec() >= _apply_now_until:
		b.set("poll_t", -delta)  # skip this one (the bridge adds delta: 0)
		due = false
	if mode == "safe" and due:
		_since_scan = 0.0
		var t := Time.get_ticks_usec()
		_intercept(b)
		stats.scan_us = Time.get_ticks_usec() - t
		stats.scan_us_max = maxi(int(stats.scan_us_max), int(stats.scan_us))
		if FileAccess.file_exists("res://.dev/apply_now"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.dev/apply_now"))
			_apply_now_until = Time.get_ticks_msec() + 15000
			print("SafeApply: asked to apply now (.dev/apply_now)")
	if due and (not held.is_empty() or (_lobby_role() == "host" and _anyone_waiting())):
		_decide()  # (a lobby host also leads when only joiners have something waiting)
	_lobby_talk()
	_update_note()


## Hide changed files from the bridge until they may apply. Only stats files the bridge already knows (new files never
## reload anything); md5 only when the mtime moved, like the bridge.
func _intercept(b: Node) -> void:
	var mt: Dictionary = b.mtimes
	var hs: Dictionary = b.hashes
	if mt.size() != _known_count:  # a file appeared (the bridge records it on its own)
		_known_count = mt.size()
		_changed()
	for path in mt.keys():
		var m := FileAccess.get_modified_time(path)
		if m == int(mt[path]):
			continue
		if m == 0 and not FileAccess.file_exists(path):  # deleted: nothing to reload
			mt.erase(path)
			hs.erase(path)
			held.erase(path)
			_known_count = mt.size()
			_changed()
			continue
		var h := FileAccess.get_md5(path)
		var old: String = hs.get(path, "")
		if h == old:
			mt[path] = m  # touched, not changed
			continue
		_changed()
		if path == SELF or path.begins_with("res://addons/") or not hs.has(path):
			continue  # this file itself (a fix must reach a stuck machine), addons, unknown: the bridge decides
		if not held.has(path):
			held[path] = old
			if held.size() == 1:
				held_since_ms = Time.get_ticks_msec()
			stats.held += 1
		elif held[path] == h:
			held.erase(path)  # changed back to what is running
		mt[path] = m
		hs[path] = h


## Look for changed files right now (not only at the next check). Never reloads anything itself.
func check_now() -> void:
	var b := _bridge()
	if b != null and mode == "safe":
		_intercept(b)


func _changed() -> void:
	last_change_ms = Time.get_ticks_msec()
	_ver_dirty = true


func settled() -> bool:
	return Time.get_ticks_msec() - last_change_ms >= SETTLE_MS


# --- When -------------------------------------------------------------------------------------------------------------

func _arcade() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.scene_file_path == ARCADE_SCENE else null


## "host" (a lobby with joiners), "client" (in or joining a lobby) or "" (alone / not in the arcade).
func _lobby_role() -> String:
	var a := _arcade()
	if a == null or multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return ""
	var m := str(a.get("mode"))
	if m == "host" and not (a.get("machines") as Dictionary).is_empty():
		return "host"
	if m == "client":
		return "client"
	return ""


func _connected() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not p is OfflineMultiplayerPeer \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _decide() -> void:
	if Time.get_ticks_msec() < _apply_now_until:
		apply_all("asked (.dev/apply_now)", false)
		return
	if not settled():
		return
	if safe_now():
		match _lobby_role():
			"host":
				if _all_match() or (_pending_since != 0 and Time.get_ticks_msec() - _pending_since > LOBBY_WAIT_MS):
					_apply_lobby()
			"client":
				if Time.get_ticks_msec() - held_since_ms > CLIENT_WAIT_MS:
					apply_all("the lobby host never said (waited %d s)" % (CLIENT_WAIT_MS / 1000), false)
			_:
				apply_all("arcade menu", false)
		return
	var s := get_tree().current_scene
	if s != null and bool(s.get_meta("safe_to_apply", false)) and _lobby_role() == "" \
			and (multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		apply_all("the game's safe point", false)
		return
	var free: Array = []
	for path in held:
		if _free_mid_game(str(path), s):
			free.append(path)
	if not free.is_empty():
		_release(free, false)


## Mid-game: may this file switch now? Only if the running game can't be using it.
func _free_mid_game(path: String, s: Node) -> bool:
	var scene_path := s.scene_file_path if s != null else ""
	if path.ends_with(".tscn"):
		return path != scene_path and not ResourceLoader.has_cached(path)
	if path.begins_with("res://arcade/"):
		return true  # the arcade isn't running; its script has no nodes now
	if path.begins_with("res://core/") or path.begins_with("res://tests/"):
		return false
	if scene_path != "" and path.begins_with(scene_path.get_base_dir() + "/"):
		return false
	return not ResourceLoader.has_cached(path)


# --- Applying ---------------------------------------------------------------------------------------------------------

func apply_all(why: String, for_scene_change: bool) -> bool:
	var b := _bridge()
	if b != null and mode == "safe":
		_intercept(b)  # files that arrived since the last scan switch on too (the bridge's scan below would see them)
	if held.is_empty():
		return false
	var n := held.size()
	_release(held.keys(), for_scene_change)
	stats.applies += 1
	last_apply = {"ms": Time.get_ticks_msec(), "unix": Time.get_unix_time_from_system(), "paths": n, "why": why}
	print("SafeApply: applied %d waiting file%s (%s)" % [n, "" if n == 1 else "s", why])
	return true


## Give files back to the bridge and let it reload them right now (one scan: every file switches in the same frame).
## A changed scene that is in use is replaced in the resource cache (its next use gets the new one) instead of the
## bridge restarting the current scene, except the scene on screen itself in the menu (arcade.tscn: restarted; the
## arcade keeps its tab and selection).
func _release(paths: Array, for_scene_change: bool) -> void:
	var b := _bridge()
	if b == null:
		held.clear()
		return
	var mt: Dictionary = b.mtimes
	var hs: Dictionary = b.hashes
	var cur := get_tree().current_scene
	var cur_path := cur.scene_file_path if cur != null else ""
	var scripts := 0
	for p in paths:
		if not held.has(p):
			continue
		var old: String = held[p]
		held.erase(p)
		stats.released += 1
		if str(p).ends_with(".tscn") and (p != cur_path or for_scene_change):
			if ResourceLoader.has_cached(p):
				ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
			continue
		hs[p] = old
		mt[p] = -1
		scripts += 1
	if scripts > 0:
		if b.has_method("_scan_files"):
			b.call("_scan_files", false)
		else:
			b.set("poll_t", 1.0)
	applied.emit(paths)


# --- Lobby: everyone switches together --------------------------------------------------------------------------------

## md5 over every game script's md5 (what is on disk, waiting or not). Same files = same version.
func disk_version() -> String:
	if not _ver_dirty and _ver != "":
		return _ver
	var b := _bridge()
	if b == null:
		return ""
	var hs: Dictionary = b.hashes
	var keys: Array = []
	for k in hs:
		var p := str(k)
		for root in MANAGED:
			if p.begins_with(root):
				keys.append(p)
				break
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [k, hs[k]])
	_ver = "\n".join(parts).md5_text()
	_ver_dirty = false
	return _ver


func _all_match() -> bool:
	var v := disk_version()
	var a := _arcade()
	if a == null:
		return false
	for id in a.get("machines"):
		if not members.has(id) or str(members[id].ver) != v:
			return false
	return true


func _anyone_waiting() -> bool:
	if not held.is_empty():
		return true
	var a := _arcade()
	for id in members:
		if a != null and (a.get("machines") as Dictionary).has(id) and int(members[id].held) > 0:
			return true
	return false


## Lobby host: everyone switches now (the joiners on the message, this machine at the end of the frame: the arcade may
## be the caller and is likely one of the files).
func _apply_lobby() -> void:
	var now := Time.get_ticks_msec()
	if now - _lobby_applied_ms < 1000:
		return
	_lobby_applied_ms = now
	var v := disk_version()
	stats.lobby_applies += 1
	var a := _arcade()
	if _connected():
		for id in a.get("machines"):
			_sa_apply.rpc_id(id, v)
			if members.has(id):
				members[id].held = 0  # it switches on this message (reliable, and before any game start that follows)
	if not held.is_empty():
		apply_all.call_deferred("lobby: everyone switches now", false)


func _start_ok() -> bool:
	if mode != "safe" or _lobby_role() != "host":
		return true
	check_now()
	var now := Time.get_ticks_msec()
	var all_same := _all_match()
	var waiting := _anyone_waiting() or (not held.is_empty() and now - _lobby_applied_ms < 1000)
	if not waiting and settled():
		_start_wait_since = 0
		return true  # (different code with nothing arriving: a machine that missed a deploy; LAN updates fix that)
	if _start_wait_since == 0:
		_start_wait_since = now
		print("SafeApply: holding the game start until every machine has the same code")
	if now - _start_wait_since > START_WAIT_MS:
		print("SafeApply: starting anyway (machines still differ after %d s)" % (START_WAIT_MS / 1000))
		_start_wait_since = 0
		if _anyone_waiting():
			_apply_lobby()
		return true
	if all_same and settled():
		_apply_lobby()  # everyone has it: switch now, the start follows
	return false


func _lobby_talk() -> void:
	var role := _lobby_role()
	var now := Time.get_ticks_msec()
	if role == "client" and _connected():
		var msg := "%s/%d/%d" % [disk_version(), held.size(), multiplayer.get_unique_id()]
		if msg != _sent or now - _sent_ms > STATE_EVERY_MS:
			_sent = msg
			_sent_ms = now
			_sa_state.rpc_id(1, disk_version(), held.size())
	elif role == "host":
		if _pending_since == 0 and _anyone_waiting():
			_pending_since = now
		elif _pending_since != 0 and not _anyone_waiting():
			_pending_since = 0
	else:
		_pending_since = 0
		_sent = ""
		if not members.is_empty():
			members.clear()


## Joiner -> lobby host: what code I have on disk, and how many files wait to be applied.
@rpc("any_peer", "call_remote", "reliable")
func _sa_state(ver: String, held_n: int) -> void:
	members[multiplayer.get_remote_sender_id()] = {"ver": ver, "held": held_n}


## Lobby host -> joiners: switch to what you have now (everyone at the same moment).
@rpc("any_peer", "call_remote", "reliable")
func _sa_apply(ver: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if ver != disk_version():
		print("SafeApply: the lobby host switched with different files (still arriving here?)")
	apply_all("lobby host said switch", false)


# --- The corner note --------------------------------------------------------------------------------------------------

func _update_note() -> void:
	var want := ""
	if not held.is_empty():
		want = "updating…" if safe_now() else "• update ready"
	if want == "":
		if _note != null and is_instance_valid(_note):
			_note.visible = false
		return
	if _note == null or not is_instance_valid(_note):
		_note_layer = CanvasLayer.new()
		_note_layer.layer = 95
		add_child(_note_layer)
		_note = Label.new()
		_note.name = "UpdateNote"
		_note.add_theme_font_size_override("font_size", 16)
		_note.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.55))
		_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		_note.add_theme_constant_override("outline_size", 4)
		_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_note_layer.add_child(_note)
		_note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_note.offset_left = -260
		_note.offset_top = -30
		_note.offset_right = -12
		_note.offset_bottom = -8
	_note.text = want
	_note.visible = true
