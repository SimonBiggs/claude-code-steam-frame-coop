extends RefCounted
## The games' own story card pictures (core/story_card.gd draws them). Each games/<game>/story_pictures.gd has
##   const NAMES: Array[String] = ["beaver", ...]
##   static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void   # match kind: one case per name
## and is found by itself the first time a picture is asked for (one scan of res://games, cached). So a game adds
## pictures in its own file and two games never edit the same line (core/story_card.gd's SHARED_PICTURES is frozen:
## tests/story_pictures_test.gd).

static var _by_name: Dictionary = {}   # name -> the game's story_pictures.gd script
static var _files: Array[String] = []
static var _dupes: Array[String] = []
static var _scanned := false


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	if not DirAccess.dir_exists_absolute("res://games"):
		return
	for g in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/story_pictures.gd" % g
		if not ResourceLoader.exists(path):
			continue
		_files.append(path)
		var s = load(path)  # (untyped: NAMES is the game script's own constant)
		if s == null:
			continue
		for n in s.NAMES:
			if _by_name.has(n):
				_dupes.append("picture %s is in two games' story_pictures.gd" % n)
			else:
				_by_name[n] = s


## The game script that draws this picture, or null.
static func find(kind: String):
	_scan()
	return _by_name.get(kind)


## Every game's picture names.
static func names() -> Array[String]:
	_scan()
	var out: Array[String] = []
	for n in _by_name:
		out.append(String(n))
	return out


## Every file with game pictures.
static func files() -> Array[String]:
	_scan()
	return _files.duplicate()


## Problems (empty = fine): a NAMES entry without its case in that file, a name in two games or also shared.
static func check(shared: Array[String], shared_path: String) -> Array[String]:
	_scan()
	var out: Array[String] = _dupes.duplicate()
	var lists := {shared_path: shared}
	for path in _files:
		var names: Array[String] = []
		for n in load(path).NAMES:
			names.append(String(n))
			if shared.has(String(n)):
				out.append("picture %s is shared and in %s" % [n, path])
		lists[path] = names
	for path in lists:
		var src := FileAccess.get_file_as_string(path)
		for n in lists[path]:
			var re := RegEx.create_from_string("\\n\\t+(\"[a-z]+\", )*\"%s\"(, \"[a-z]+\")*:" % n)
			if re.search(src) == null:
				out.append("picture %s has no drawing in %s" % [n, path])
	return out
