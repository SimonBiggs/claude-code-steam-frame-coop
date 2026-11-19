extends SceneTree
## Every arcade game writes a RUN line (core/telemetry.gd Telemetry.run) when a round, show or case ends, so the
## family's real play reaches the Steam Machine (core/telemetry_push.gd -> duo-telemetry-recv -> dev.playRuns) and
## balance can be judged from it. 2026-11-12: Quiz Show and Mystery Manor never wrote one, so their play was invisible.
## Also: a RUN line without its own "secs" is timed by Telemetry.run (secs_auto), so play-record never shows 0 minutes.
## Fails: a games/<id>/ folder (except engine_template) with no Telemetry.run( call in any of its scripts.
##   godot-test --headless --path . -s res://tests/telemetry_coverage_test.gd   -> TELEMETRY COVERAGE: PASS / FAIL

const SKIP := ["engine_template"]

var fails: Array[String] = []


func _initialize() -> void:
	var games := DirAccess.get_directories_at("res://games")
	for g in games:
		if g in SKIP:
			continue
		if not _calls_run("res://games/" + g):
			fails.append("games/%s never calls Telemetry.run(...): add one where a round / show / case ends (host only), e.g. Telemetry.run(GAME_ID, {\"end\": end, ...})" % g)
	_auto_secs()
	for f in fails:
		print("  FAIL ", f)
	print("TELEMETRY COVERAGE: %s (%d games)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(), games.size() - SKIP.size()])
	quit(0 if fails.is_empty() else 1)


func _calls_run(dir: String) -> bool:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and FileAccess.get_file_as_string(dir + "/" + f).contains("Telemetry.run("):
			return true
	for d in DirAccess.get_directories_at(dir):
		if _calls_run(dir + "/" + d):
			return true
	return false

func _auto_secs() -> void:
	const Telemetry := preload("res://core/telemetry.gd")
	Telemetry.game_started()
	OS.delay_msec(120)
	var a := Telemetry.run("telemetry_coverage_test", {"end": "test"})
	var b := Telemetry.run("telemetry_coverage_test", {"end": "test", "secs": 7})
	if not (a.get("secs_auto", false) and float(a.get("secs", 0)) >= 0.1):
		fails.append("Telemetry.run without secs should add secs_auto timing (got %s)" % [a])
	if b.has("secs_auto") or int(b.secs) != 7:
		fails.append("Telemetry.run must keep a game's own secs (got %s)" % [b])
