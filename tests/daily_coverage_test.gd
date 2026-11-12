extends SceneTree
## DAILY COVERAGE: every game with a TODAY'S level (a daily seed: games/<id>/*.gd calls daily_seed( or
## Seeded.today()) must prove that daily over many dates: some tests/*_test.gd that loads res://games/<id>/ must
## call Seeded.validate_days (core/seeded.gd: 400+ dates, plus the 60 days from whenever the test runs, each
## checked by the game's validator and the same all day). A daily nobody can finish is a whole day lost for the
## family (2026-11-12: Hide and Seek's TODAY'S STREET hid both friends at the far end of the house on that date
## only). Also checks Seeded.today()'s test-only date override (DUO_TODAY) and the date list.
##   godot-test --headless --path . -s res://tests/daily_coverage_test.gd
## Prints "SCRIPT ERROR: ..." per failure and "DAILY COVERAGE: PASS|FAIL".

const Seeded := preload("res://core/seeded.gd")

## Games whose "daily" is not a generated level (nothing to validate), with the reason. Keep it short.
const NOT_A_LEVEL := {}

var fails := 0


func _initialize() -> void:
	var tests := {}  # path -> text
	for f in DirAccess.get_files_at("res://tests"):
		if f.ends_with("_test.gd"):
			tests["res://tests/" + f] = FileAccess.get_file_as_string("res://tests/" + f)
	var games := 0
	for id in DirAccess.get_directories_at("res://games"):
		if not _has_daily(id):
			continue
		games += 1
		if NOT_A_LEVEL.has(id):
			continue
		var covered := false
		for p in tests:
			var t: String = tests[p]
			if t.contains("res://games/%s/" % id) and t.contains("Seeded.validate_days("):
				covered = true
				break
		if not covered:
			_fail("%s has a TODAY'S level but no test runs Seeded.validate_days over it (add it to tests/%s_gen_test.gd)" % [id, id])
	_expect(games >= 30, "found the games with a daily (%d)" % games)
	var ds := Seeded.dates(400)
	_expect(ds.size() >= 400 and ds.has(Time.get_date_string_from_system()), "the dates cover 400 days and today (%d)" % ds.size())
	_expect(ds.has("2026-11-12") and ds[0] == "2026-10-01", "the dates start 2026-10-01 and include 2026-11-12")
	if OS.has_environment("DUO_TODAY") and OS.has_environment("SAVE_TEST"):
		_expect(Seeded.today() == OS.get_environment("DUO_TODAY"), "DUO_TODAY sets today in test runs")
	print("DAILY COVERAGE: %d games with a daily; %s" % [games, "PASS" if fails == 0 else "FAIL (%d)" % fails])
	quit(0 if fails == 0 else 1)


func _has_daily(id: String) -> bool:
	var dir := "res://games/%s/" % id
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd") or f == "progress.gd":
			continue
		var t := FileAccess.get_file_as_string(dir + f)
		if t.contains("daily_seed(") or t.contains("Seeded.today()"):
			return true
	return false


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(why: String) -> void:
	fails += 1
	print("SCRIPT ERROR: DAILY COVERAGE: " + why)
