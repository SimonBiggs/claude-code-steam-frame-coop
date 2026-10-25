extends Node
## LAN update boot guard (autoload "LanUpdateGuard"; docs/MULTI_MACHINE.md "Updates over the home network").
## Deliberately tiny and NOT part of update bundles (addons/ never travels over the network, like addons/gdev), so a
## broken update can never break the code that rolls it back. core/lan_update.gd does everything else.
## - restore(): put back the files saved before the last update (res://.update/backup) and mark that version bad.
## - After an update is applied (core/lan_update.gd writes res://.update/boot_pending.json and calls watch()), and
##   at every start while that file exists: if the arcade isn't running a valid script within HEALTH_SECONDS, or the
##   game was started BOOT_TRIES times without getting healthy (a crash loop), roll back and reload the arcade.

const META := "res://.update"
const HEALTH_SECONDS := 15.0
const BOOT_TRIES := 3

var _watch_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var p := read_json(META + "/boot_pending.json")
	if p.is_empty():
		return
	var tries := int(p.get("attempts", 0)) + 1
	p["attempts"] = tries
	write_text(META + "/boot_pending.json", JSON.stringify(p))
	if tries >= BOOT_TRIES:
		print("LanUpdate: started %d times since the update without getting healthy, rolling back" % tries)
		restore("crash loop")
		return
	watch()


## Check the arcade is healthy in HEALTH_SECONDS (core/lan_update.gd calls this right after applying an update).
func watch() -> void:
	_watch_t = HEALTH_SECONDS


func _process(delta: float) -> void:
	if _watch_t < 0.0:
		return
	_watch_t -= delta
	if _watch_t > 0.0:
		return
	_watch_t = -1.0
	if not FileAccess.file_exists(META + "/boot_pending.json"):
		return
	var scene := get_tree().current_scene
	var s: Script = scene.get_script() if scene != null else null
	if scene != null and s != null and s.can_instantiate():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META + "/boot_pending.json"))
		print("LanUpdate: update healthy")
		return
	print("LanUpdate: the game isn't running after the update, rolling back")
	restore("not healthy")
	get_tree().change_scene_to_file.call_deferred("res://arcade.tscn")


## Undo the last applied update from res://.update/backup (restore.json: "replaced" = files saved under files/,
## "added" = files the update created). Marks the update's version bad so it isn't fetched again. Returns true if a
## backup was there. Shared by core/lan_update.gd (script check failed) and the boot check above.
static func restore(reason: String) -> bool:
	var info := read_json(META + "/backup/restore.json")
	if info.is_empty():
		return false
	for rel in info.get("replaced", []):
		var data := FileAccess.get_file_as_bytes(META + "/backup/files/" + str(rel))
		var path := "res://" + str(rel)
		write_bytes(path, data)
		if path.ends_with(".gd") and ResourceLoader.has_cached(path):  # the running game must get the good code back
			var s := load(path) as GDScript
			if s != null:
				s.source_code = data.get_string_from_utf8()
				s.reload(true)
	for rel in info.get("added", []):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://" + str(rel)))
	for f in ["manifest.json", "manifest.sig"]:
		var g := ProjectSettings.globalize_path(META + "/" + f)
		if FileAccess.file_exists(META + "/backup/meta/" + f):
			write_bytes(META + "/" + f, FileAccess.get_file_as_bytes(META + "/backup/meta/" + f))
		elif FileAccess.file_exists(META + "/" + f):
			DirAccess.remove_absolute(g)
	var state := read_json(META + "/state.json")
	var bad: Array = state.get("bad", [])
	bad.append(str(info.get("to", "")))
	state["bad"] = bad
	write_text(META + "/state.json", JSON.stringify(state))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(META + "/boot_pending.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(META + "/backup/restore.json"))
	print("LanUpdate: ROLLED BACK update %s to %s (%s)" % [info.get("to", "?"), info.get("from", "?"), reason])
	return true


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


static func write_text(path: String, text: String) -> bool:
	return write_bytes(path, text.to_utf8_buffer())


## Atomic write: a temp file next to it, then rename over (a half-written file is never seen).
static func write_bytes(path: String, data: PackedByteArray) -> bool:
	var g := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(g.get_base_dir())
	var tmp := g + ".lanupd.tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	f.close()
	return DirAccess.rename_absolute(tmp, g) == OK
