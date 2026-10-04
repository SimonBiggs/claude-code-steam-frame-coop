extends RefCounted
## Shared resource cache for the engine kits (meshes, materials, themes, sounds, synthesised audio).
## It lives in Engine metadata (not static vars), so it survives scene reloads and hot reloads, and it
## is emptied when the game quits so GPU resources are never reported as leaked at exit.
##
## Usage:
##   const ResCache := preload("res://core/res_cache.gd")
##   var m: Mesh = ResCache.get_or_make("mk_slime_v1", func() -> Resource: return _build_slime())
##
## Keys are global: prefix them with the module name ("mk_", "ui_", "sky_", ...) and bump a version
## suffix when the generator changes (hot reload keeps the old entry otherwise).

const META := "engine_kit_cache"
const JANITOR_META := "engine_kit_cache_janitor"


## Cached resource for `key`, building it with `maker` (a Callable returning a Resource) the first time.
static func get_or_make(key: String, maker: Callable) -> Resource:
	var d := _dict()
	if d.has(key):
		var cached: Resource = d[key]
		if cached != null:
			return cached
	var made: Resource = maker.call()
	d[key] = made
	return made


## True when `key` is cached.
static func has(key: String) -> bool:
	return _dict().has(key)


## The cached resource for `key`, or null.
static func fetch(key: String) -> Resource:
	var d := _dict()
	if d.has(key):
		var r: Resource = d[key]
		return r
	return null


## Store `res` under `key` (replaces any older entry).
static func put(key: String, res: Resource) -> void:
	_dict()[key] = res


## Drop every entry whose key starts with `prefix` ("" = everything).
static func clear(prefix: String = "") -> void:
	if not Engine.has_meta(META):
		return
	var d: Dictionary = Engine.get_meta(META)
	if prefix == "":
		d.clear()
		return
	for k in d.keys():
		if str(k).begins_with(prefix):
			d.erase(k)


static func _dict() -> Dictionary:
	if not Engine.has_meta(META):
		Engine.set_meta(META, {})
	_ensure_janitor()
	var d: Dictionary = Engine.get_meta(META)
	return d


## A node parked under the root that empties the cache when the SceneTree shuts down.
static func _ensure_janitor() -> void:
	if Engine.has_meta(JANITOR_META):
		var j: Object = Engine.get_meta(JANITOR_META)
		if is_instance_valid(j):
			return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var node := Janitor.new()
	node.name = "EngineKitCacheJanitor"
	Engine.set_meta(JANITOR_META, node)
	tree.root.add_child.call_deferred(node)


class Janitor extends Node:
	## Empties the shared cache when the game quits (root's children leave the tree last).
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _exit_tree() -> void:
		if Engine.has_meta("engine_kit_cache"):
			var d: Dictionary = Engine.get_meta("engine_kit_cache")
			d.clear()
			Engine.remove_meta("engine_kit_cache")
		if Engine.has_meta("engine_kit_cache_janitor"):
			Engine.remove_meta("engine_kit_cache_janitor")
