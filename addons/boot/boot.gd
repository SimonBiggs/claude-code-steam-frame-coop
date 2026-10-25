extends Node
## Boot (autoload "Boot"): the arcade's ONE game autoload, and FROZEN: it only changes with a game relaunch, so it
## does as little as possible. Everything else that lives for the whole run (SafeApply, LanUpdate, the VR text guard,
## runtime settings, ...) is a SERVICE listed in res://core/services.gd, a normal hot-reloadable script: adding,
## removing or replacing a service is a file change, never a restart (Simon, 2026-10-25: "make it so that everything
## hot reloads"). docs/MULTI_MACHINE.md "Everything hot-reloads".
## - Once a second it runs services.gd's sync(root): create missing services (fixed node names, e.g. /root/SafeApply,
##   so other code's references survive), replace changed ones (state via _handoff()/_adopt()), drop removed ones.
## - The registry itself is compiled from its file here (never reloaded in place) whenever the file changes AND the
##   safe-apply gate allows it (SafeApply.may_apply(path): not mid-game, all lobby machines together). A registry
##   that doesn't compile is refused (logged); the last good one keeps running, and is kept in user:// for the next
##   start too.
## - ESSENTIAL: services that must exist even when game code is broken (they live in addons/, which updates never
##   touch): the LAN update rollback guard.

const REGISTRY := "res://core/services.gd"
const LAST_GOOD := "user://boot/services_last_good.gd"
const ESSENTIAL := [["LanUpdateGuard", "res://addons/lan_update/guard.gd"]]
const EVERY := 1.0

var registry: GDScript
var registry_src := ""
var refused_src := ""
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := get_tree().root
	for e in ESSENTIAL:
		if root.get_node_or_null(e[0]) == null and ResourceLoader.exists(e[1]):
			var s := load(e[1]) as GDScript
			if s != null and s.can_instantiate():
				var n: Node = s.new()
				n.name = e[0]
				root.add_child.call_deferred(n)
	_read_registry(true)
	_sync.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	if _t < EVERY:
		return
	_t = 0.0
	_read_registry(false)
	_sync()


func _read_registry(first: bool) -> void:
	if not FileAccess.file_exists(REGISTRY):
		return
	var src := FileAccess.get_file_as_string(REGISTRY)
	if src == registry_src or src == refused_src:
		return
	if not first:
		var sa := get_tree().root.get_node_or_null("SafeApply")
		if sa != null and sa.has_method("may_apply") and not bool(sa.call("may_apply", REGISTRY)):
			return  # mid-game, or the lobby hasn't switched yet: later
	var g := _compile(src)
	if g != null:
		registry = g
		registry_src = src
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAST_GOOD.get_base_dir()))
		var f := FileAccess.open(LAST_GOOD, FileAccess.WRITE)
		if f:
			f.store_string(src)
			f.close()
		print("Boot: services list %s" % ("loaded" if first else "changed: applying"))
		return
	refused_src = src
	print("Boot: %s doesn't compile (error above): keeping the last good services list" % REGISTRY)
	if registry == null and FileAccess.file_exists(LAST_GOOD):
		registry = _compile(FileAccess.get_file_as_string(LAST_GOOD))


func _compile(src: String) -> GDScript:
	var g := GDScript.new()
	g.source_code = src
	return g if g.reload() == OK else null


func _sync() -> void:
	if registry != null and registry.has_method("sync"):
		registry.call("sync", get_tree().root, self)
