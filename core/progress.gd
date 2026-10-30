extends RefCounted
## The family's progress in every story game, for the arcade's Family Trophy Hall (arcade/hall.gd), read from the
## games' saves through core/save.gd WITHOUT loading any game scene. Each deepened game opts in with
##   games/<game>/progress.gd:
##     const SAVE_ID := "tower_stack"   # its core/save.gd game_id
##     const WHO := "wren"              # its story friend (a story picture: StoryCard.has_picture)
##     const GROWS := "tower"           # what the family grows (a story picture or a UiKit icon kind)
##     const COLOR := Color(...)
##     static func progress_summary(data: Dictionary, today: String) -> Dictionary  # {"grown": int, "daily": bool, "played"?: bool}
##     static func sample(today: String) -> Dictionary   # a save as the game writes it (grown > 0, daily done)
## found by itself (one scan of res://games, cached), like core/story_pictures.gd. tests/progress_test.gd fails when a
## game with a daily seed (a deepened game) has no progress.gd, or its summary misreads its own sample save.
##   var rows := Progress.summaries()            # {game id: {"grown", "daily", "played"}}
##   Progress.pack(rows) / Progress.unpack(arr)   # compact form for the lobby network
##   Progress.merge(host_rows, my_rows)           # one family: the further-grown of each game, either's daily

const Save := preload("res://core/save.gd")
const Seeded := preload("res://core/seeded.gd")

static var _paths: Dictionary = {}  # game id -> its progress.gd path (found at once: a file check per game)
static var _scripts: Dictionary = {}  # game id -> its loaded script (loaded when first needed, or a few per frame)
static var _scanned := false
## How long finding every progress.gd took, and loading (compiling) them so far, in ms. Loading is ~0.5 ms a game on
## the Steam Machine, so the lobby never loads them all in one frame: load_some() a few per frame (tests/progress_test.gd).
static var scan_ms := 0.0
static var load_ms := 0.0


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	if not DirAccess.dir_exists_absolute("res://games"):
		return
	var t0 := Time.get_ticks_usec()
	for g in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/progress.gd" % g
		if FileAccess.file_exists(path):
			_paths[g] = path
	scan_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Does this game have a progress.gd? (never loads it)
static func has(id: String) -> bool:
	_scan()
	return _paths.has(id)


## The progress.gd script of a game (null if it has none); loads it now if it isn't yet.
static func script_of(id: String):
	_scan()
	if not _scripts.has(id) and _paths.has(id):
		var t0 := Time.get_ticks_usec()
		_scripts[id] = load(String(_paths[id]))
		load_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return _scripts.get(id)


## Is this game's script loaded already?
static func is_loaded(id: String) -> bool:
	return _scripts.has(id)


## Load scripts until `budget_ms` is used up (at least one). True once every game's script is loaded.
static func load_some(budget_ms: float = 4.0) -> bool:
	_scan()
	var t0 := Time.get_ticks_usec()
	for id in _paths:
		if _scripts.has(id):
			continue
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			return false
		script_of(String(id))
	return true


## Every game id with a progress.gd.
static func ids() -> Array[String]:
	_scan()
	var out: Array[String] = []
	for g in _paths:
		out.append(String(g))
	return out


## One game's summary from a save Dictionary: {"grown": int >= 0, "daily": bool, "played": bool}.
static func summary_of(id: String, data: Dictionary, today: String = "") -> Dictionary:
	var s = script_of(id)
	if s == null:
		return {}
	var r: Variant = s.progress_summary(data, today if today != "" else Seeded.today())
	var d: Dictionary = r if r is Dictionary else {}
	var daily := bool(d.get("daily", false))
	return {"grown": maxi(0, int(d.get("grown", 0))), "daily": daily, "played": bool(d.get("played", false)) or daily}


## Every opted-in game's summary from this machine's saves (only the games in `only`, when given).
static func summaries(only: Array = []) -> Dictionary:
	var today := Seeded.today()
	var out := {}
	for id in ids():
		if not only.is_empty() and not only.has(id):
			continue
		out[id] = summary_of(id, Save.load_data(String(script_of(id).SAVE_ID)), today)
	return out


## Compact for the network: [date, id, grown, flags, id, grown, flags...] (flags: 1 = daily done, 2 = played today).
static func pack(rows: Dictionary) -> Array:
	var out: Array = [Seeded.today()]
	for id in rows:
		var r: Dictionary = rows[id]
		out.append_array([String(id), int(r.get("grown", 0)), (1 if r.get("daily", false) else 0) | (2 if r.get("played", false) else 0)])
	return out


## pack() back to rows. Another day's dailies (the sender's clock is on yesterday) don't count as done today.
static func unpack(arr: Array) -> Dictionary:
	var out := {}
	if arr.is_empty():
		return out
	var same_day := String(arr[0]) == Seeded.today()
	var k := 1
	while k + 2 < arr.size():
		var id := String(arr[k])
		var flags := int(arr[k + 2])
		out[id] = {"grown": maxi(0, int(arr[k + 1])), "daily": same_day and (flags & 1) != 0, "played": same_day and (flags & 2) != 0}
		k += 3
	return out


## One family across machines: each game as far as either has grown it, its daily done if either did it.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for id in b:
		var rb: Dictionary = b[id]
		if not out.has(id):
			out[id] = rb.duplicate()
			continue
		var ra: Dictionary = out[id]
		ra.grown = maxi(int(ra.get("grown", 0)), int(rb.get("grown", 0)))
		ra.daily = bool(ra.get("daily", false)) or bool(rb.get("daily", false))
		ra.played = bool(ra.get("played", false)) or bool(rb.get("played", false))
	return out


## Problems (empty = fine): a deepened game (one using Seeded's daily seed) without a progress.gd, a picture that
## doesn't exist, a summary that crashes on an empty save or misreads the game's own sample save.
## pretend_missing: game ids to treat as having no progress.gd (tests prove the check can fail).
static func check(game_ids: Array, pretend_missing: Array = []) -> Array[String]:
	const StoryCard := preload("res://core/story_card.gd")
	var out: Array[String] = []
	var today := Seeded.today()
	for id in game_ids:
		var deep := false
		var dir := "res://games/%s/" % id
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".gd"):
					var src := FileAccess.get_file_as_string(dir + f)
					if src.contains("daily_seed(") or src.contains("daily_key("):
						deep = true
						break
		var s = null if pretend_missing.has(id) else script_of(String(id))
		if s == null:
			if deep:
				out.append("%s has a daily challenge but no games/%s/progress.gd (the arcade's Family Trophy Hall can't show it)" % [id, id])
			continue
		for c in ["SAVE_ID", "WHO", "GROWS", "COLOR"]:
			if not c in s.get_script_constant_map():
				out.append("games/%s/progress.gd has no %s" % [id, c])
		if not out.is_empty() and String(out[-1]).begins_with("games/%s/" % id):
			continue
		if not StoryCard.has_picture(String(s.WHO)):
			out.append("games/%s/progress.gd WHO %s is not a story picture" % [id, s.WHO])
		if not StoryCard.has_picture(String(s.GROWS)) and not FileAccess.get_file_as_string("res://core/ui_kit.gd").contains("\t\t\t\"%s\":" % s.GROWS):
			out.append("games/%s/progress.gd GROWS %s is neither a story picture nor a UiKit icon" % [id, s.GROWS])
		var empty := summary_of(String(id), {}, today)
		if int(empty.get("grown", -1)) != 0 or bool(empty.get("daily", true)):
			out.append("games/%s/progress.gd: an empty save must read as grown 0, daily not done (got %s)" % [id, str(empty)])
		var sam: Dictionary = summary_of(String(id), s.sample(today), today)
		if int(sam.get("grown", 0)) <= 0 or not bool(sam.get("daily", false)):
			out.append("games/%s/progress.gd: its sample save must read as grown > 0, daily done (got %s)" % [id, str(sam)])
		var old: Dictionary = summary_of(String(id), s.sample("2000-01-01"), today)
		if bool(old.get("daily", true)):
			out.append("games/%s/progress.gd: a daily done on another day must not count as done today" % id)
	return out
