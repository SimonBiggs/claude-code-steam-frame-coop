extends Node
## gdev bridge LOADER (development only). The autoload the `gdev` CLI installs as res://addons/gdev/bridge.gd.
## FROZEN: this file only changes with a game relaunch (it is never hot-reloaded), so it does as little as possible.
## All bridge logic (hot reload, recording, live stream, commands) is in a hot-reloadable script:
##   res://core/dev/gdev_main.gd  (the project's own copy, if any: changes there go live like any game code)
##   res://addons/gdev/gdev_main.gd  (gdev's default copy, installed next to this file)
## This loader runs it as a child node ("Impl"), checks its file twice a second, and swaps in a changed copy once it
## compiles (state handed over: impl._handoff() -> Dictionary -> new impl._adopt()). A copy that doesn't compile is
## refused (logged) and the running one keeps going; at start, if neither file compiles, the last copy that did
## (user://gdev/last_good_main.gd) runs.
## Other code reaches the logic through /root/GDev.impl.

const IMPLS := ["res://core/dev/gdev_main.gd", "res://addons/gdev/gdev_main.gd"]
const LAST_GOOD := "user://gdev/last_good_main.gd"
const CHECK_EVERY := 0.5
const SWAP_WAIT_MS := 3000  # longest wait for the running copy to finish a screen readback before swapping

var impl: Node
var impl_path := ""
var impl_src := ""
var pending: GDScript  # a new copy, compiled, waiting for the running one to be idle
var pending_src := ""
var pending_since := 0
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for path in IMPLS:
		if not FileAccess.file_exists(path):
			continue
		var src := FileAccess.get_file_as_string(path)
		var g := _compile(src, path)
		if g != null:
			_run(g, src, path, {})
			return
	if FileAccess.file_exists(LAST_GOOD):
		var src := FileAccess.get_file_as_string(LAST_GOOD)
		var g := _compile(src, LAST_GOOD)
		if g != null:
			print("[gdev] running the last good bridge logic (%s)" % LAST_GOOD)
			_run(g, src, IMPLS[0] if FileAccess.file_exists(IMPLS[0]) else IMPLS[1], {})
			impl_src = ""  # (so a fixed file is picked up)
			return
	print("[gdev] no bridge logic that compiles (%s): hot reload is off" % ", ".join(IMPLS))


func _process(delta: float) -> void:
	_t += delta
	if _t >= CHECK_EVERY:
		_t = 0.0
		_check()
	if pending != null:
		var idle := impl == null or not impl.has_method("busy") or not bool(impl.call("busy"))
		if idle or Time.get_ticks_msec() - pending_since > SWAP_WAIT_MS:
			var g := pending
			pending = null
			var state: Dictionary = {}
			if impl != null and impl.has_method("_handoff"):
				state = impl.call("_handoff")
			_run(g, pending_src, impl_path, state)


func _check() -> void:
	var path := ""
	for p in IMPLS:
		if FileAccess.file_exists(p):
			path = p
			break
	if path == "":
		return
	var src := FileAccess.get_file_as_string(path)
	if src == impl_src or src == pending_src:
		return
	var g := _compile(src, path)
	if g == null:
		pending_src = src  # refused: don't try this exact text again
		print("[gdev] %s doesn't compile (error above): the running bridge logic stays" % path)
		return
	impl_path = path
	pending = g
	pending_src = src
	pending_since = Time.get_ticks_msec()


func _compile(src: String, path: String) -> GDScript:
	var g := GDScript.new()
	g.source_code = src
	if g.reload() != OK or not g.can_instantiate():
		return null
	g.set_meta("gdev_path", path)
	return g


func _run(g: GDScript, src: String, path: String, state: Dictionary) -> void:
	var n: Node = g.new()
	if n.has_method("_adopt") and not state.is_empty():
		n.call("_adopt", state)
	if impl != null:
		impl.name = "OldImpl"
		remove_child(impl)
		impl.queue_free()
	n.name = "Impl"
	impl = n
	impl_path = path
	impl_src = src
	pending_src = ""
	add_child(n)
	if path != LAST_GOOD:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAST_GOOD.get_base_dir()))
		var f := FileAccess.open(LAST_GOOD, FileAccess.WRITE)
		if f:
			f.store_string(src)
			f.close()
