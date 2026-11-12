extends SceneTree
## ONE season test setting for every game (core/season_kit.gd SeasonKit.override): ARCADE_SEASON=winter dresses
## every game for winter, ARCADE_SEASON_<GAME_ID> just one. 2026-11-12: 23 games each read their own BB_SEASON,
## PS_SEASON, KART_SEASON ... (some checked the value, some didn't). This guard fails:
##  - any OS.get_environment / has_environment of a ..._SEASON name outside core/season_kit.gd (use
##    SeasonKit.override(game_id, fallback, allowed) instead);
##  - any "XX_SEASON" string that isn't ARCADE_SEASON (a What's New "try", a bot or test setting an old name);
##  - the helper itself: per-game beats all-games, a bad value warns and falls back, nothing set = the fallback.
##   godot-test --headless --path . -s res://tests/season_override_test.gd     Prints SEASON OVERRIDE: PASS / FAIL.

const SeasonKit := preload("res://core/season_kit.gd")
const ROOTS := ["res://games", "res://core", "res://arcade", "res://tests", "res://tools"]
const HOME := "res://core/season_kit.gd"

var fails: Array[String] = []


func _initialize() -> void:
	var env_read := RegEx.create_from_string("(get|has)_environment\\(\\s*\"[A-Z0-9_]*SEASON[A-Z0-9_]*\"")
	var old_name := RegEx.create_from_string("\"([A-Z0-9]+_SEASON)\\b")
	# The checks can fail (a line written the old way, built so this file doesn't match itself).
	var q := "\""
	var fake := "\tseason = OS.get_environment(" + q + "XX" + "_SEASON" + q + ")"
	_expect(env_read.search(fake) != null and old_name.search(fake) != null, "the guard catches an old-style read")
	_expect(env_read.search("\tseason = SeasonKit.override(\"x\", Seeded.season())") == null, "the helper call passes")
	var files: Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	_expect(files.size() > 100, "found the game scripts (%d)" % files.size())
	for f in files:
		if f == HOME or f == "res://tests/season_override_test.gd":
			continue
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var l := lines[i]
			if env_read.search(l) != null:
				fails.append("%s:%d reads a season env itself: use SeasonKit.override(game_id, fallback, allowed) (core/season_kit.gd)" % [f, i + 1])
			for m in old_name.search_all(l):
				if m.get_string(1) != "ARCADE_SEASON":
					fails.append("%s:%d uses %s: set ARCADE_SEASON (or ARCADE_SEASON_<GAME_ID>) instead, read by SeasonKit.override" % [f, i + 1, m.get_string(1)])
	_helper()
	for f in fails:
		print("SEASON OVERRIDE: FAIL ", f)
	print("SEASON OVERRIDE: %s (%d scripts)" % ["PASS" if fails.is_empty() else "FAIL", files.size()])
	quit(0 if fails.is_empty() else 1)


func _helper() -> void:
	var keep := {}
	for k in ["ARCADE_SEASON", "ARCADE_SEASON_TEST_GAME"]:
		keep[k] = OS.get_environment(k) if OS.has_environment(k) else null
		OS.unset_environment(k)
	_expect(SeasonKit.override("test_game", "spring") == "spring", "nothing set: the fallback")
	OS.set_environment("ARCADE_SEASON", "winter")
	_expect(SeasonKit.override("test_game", "spring") == "winter", "ARCADE_SEASON=winter: winter")
	_expect(SeasonKit.override("test_game", "spring", {"spring": 1, "winter": 2}) == "winter", "a Dictionary of seasons works")
	OS.set_environment("ARCADE_SEASON_TEST_GAME", "summer")
	_expect(SeasonKit.override("test_game", "spring") == "summer", "the game's own ARCADE_SEASON_<ID> wins")
	_expect(SeasonKit.override("other_game", "spring") == "winter", "another game still gets ARCADE_SEASON")
	OS.set_environment("ARCADE_SEASON_TEST_GAME", "monsoon")
	_expect(SeasonKit.override("test_game", "spring") == "spring", "a season the game doesn't know: warns, uses the fallback")
	_expect(SeasonKit.override("test_game", "spring", ["spring"]) == "spring", "the game's own allowed list counts")
	for k in keep:
		if keep[k] == null:
			OS.unset_environment(k)
		else:
			OS.set_environment(k, keep[k])


func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), out)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
