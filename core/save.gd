extends Node
## Save: simple persistent saves in user:// per game id. The data is a Dictionary (any Godot values:
## ints stay ints, Vector3s stay Vector3s), stored with a version number and written atomically
## (temp file, then rename, keeping the previous file as .bak, so a crash or power cut mid-write
## never loses progress). Objects are never decoded when loading.
## Bots and tests (a scene under res://tests/, tests/bot_kit.gd, or env SAVE_TEST=1) save into
## user://test_saves/ instead, so they never touch the family's saves.
## Usage as a node (autosave a moment after changes, and when the game exits):
##   const Save := preload("res://core/save.gd")
##   save = Save.new(); save.game_id = "dungeon"; save.version = 2; save.defaults = {"gold": 0}
##   add_child(save)                      # loads save.data
##   save.data["gold"] += 5; save.mark_dirty()
## Or one-shot: var d := Save.load_data("dungeon", {"gold": 0})  /  Save.store("dungeon", d)
## Migrations: set save.migrate = func(data: Dictionary, from_version: int) -> Dictionary.

## Emitted after a successful write.
signal saved
## Emitted after loading (data ready).
signal loaded

const MAGIC := "LRA-SAVE"
const SAVE_DIR := "user://saves/"
const TEST_DIR := "user://test_saves/"
const TEST_META := "save_test_mode"

## Which game this save belongs to (the file name): letters, digits, _ and - only.
var game_id := "game"
## Bump when the data layout changes; older files go through `migrate`.
var version := 1
## Keys missing from a loaded file are filled from here (deep copy).
var defaults := {}
## Optional func(data: Dictionary, from_version: int) -> Dictionary.
var migrate: Callable
## Seconds after mark_dirty() before writing (changes in between are batched).
var autosave_delay := 2.0
## The live data. Change it, then call mark_dirty() (or save_now()).
var data := {}

var _dirty := false
var _dirty_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload()


## Read the file again (discarding unsaved changes).
func reload() -> void:
	data = load_data(game_id, defaults, version, migrate)
	_dirty = false
	loaded.emit()


## Something changed: write it soon (batched).
func mark_dirty() -> void:
	if not _dirty:
		_dirty_t = autosave_delay
	_dirty = true


## Write now. Returns true on success.
func save_now() -> bool:
	_dirty = false
	var ok := store(game_id, data, version)
	if ok:
		saved.emit()
	return ok


func has_unsaved_changes() -> bool:
	return _dirty


func _process(delta: float) -> void:
	if not _dirty:
		return
	_dirty_t -= delta
	if _dirty_t <= 0.0:
		save_now()


func _exit_tree() -> void:
	if _dirty:
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _dirty:
		save_now()


# --- Static API ---------------------------------------------------------------------------

## Is this a bot / test run (saves go to TEST_DIR)?
static func test_mode() -> bool:
	if Engine.has_meta(TEST_META) or OS.has_environment("SAVE_TEST"):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.current_scene != null:
		return tree.current_scene.scene_file_path.begins_with("res://tests/")
	return false


## The file a game's save lives in.
static func path_for(id: String) -> String:
	var clean := ""
	for ch in id:
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-" else "_"
	return (TEST_DIR if test_mode() else SAVE_DIR) + clean + ".save"


## Load a game's data: defaults filled in, migrated to `current_version`. Never fails: a missing or
## damaged file gives the defaults (a damaged file falls back to the .bak copy first).
static func load_data(id: String, default_data: Dictionary = {}, current_version: int = 1, migrator: Callable = Callable()) -> Dictionary:
	var path := path_for(id)
	var rec := _read(path)
	if rec.is_empty():
		rec = _read(path + ".bak")
		if not rec.is_empty():
			print("Save: %s was damaged, using the backup" % path)
	var d: Dictionary = {}
	var from := current_version
	if not rec.is_empty():
		d = rec.get("data", {})
		from = int(rec.get("version", 1))
	if from < current_version and migrator.is_valid():
		var m: Variant = migrator.call(d, from)
		if m is Dictionary:
			d = m
	for k in default_data:
		if not d.has(k):
			var v: Variant = default_data[k]
			d[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return d


## Write a game's data atomically. Returns true on success.
static func store(id: String, d: Dictionary, current_version: int = 1) -> bool:
	var path := path_for(id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_var({"magic": MAGIC, "version": current_version, "game": id,
		"time": int(Time.get_unix_time_from_system()), "data": d}, false)
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	if not ok:
		push_warning("Save: writing %s failed" % tmp)
		return false
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(abs_path, abs_path + ".bak")
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)
	if err != OK:
		push_warning("Save: can't move %s into place (%s)" % [tmp, error_string(err)])
		return false
	return true


## Delete a game's save (and its backup).
static func erase(id: String) -> void:
	var path := path_for(id)
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func exists(id: String) -> bool:
	return FileAccess.file_exists(path_for(id))


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 8:
		return {}
	# store_var writes a 32-bit length, then the value: check it before decoding a damaged file.
	if int(f.get_32()) != f.get_length() - 4:
		return {}
	f.seek(0)
	var v: Variant = f.get_var(false)
	f.close()
	if not (v is Dictionary):
		return {}
	var rec: Dictionary = v
	if str(rec.get("magic", "")) != MAGIC or not (rec.get("data") is Dictionary):
		return {}
	return rec
