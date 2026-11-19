extends SceneTree
## gdev's live `run PATH` command (core/dev/gdev_main.gd run_file): compiles a file and calls its run(tree);
## a broken file or one without run() is reported, never crashes the game.
##   godot-test --headless --path . -s res://tests/gdev_run_test.gd   -> GDEV RUN: PASS / FAIL

const GdevMain := preload("res://core/dev/gdev_main.gd")

var fails: Array[String] = []


func _initialize() -> void:
	var dir := OS.get_user_data_dir()
	var ok := dir + "/gdev_run_ok.gd"
	var bad := dir + "/gdev_run_bad.gd"
	var norun := dir + "/gdev_run_norun.gd"
	_write(ok, "extends RefCounted\nfunc run(tree: SceneTree) -> Variant:\n\treturn 40 + 2\n")
	_write(bad, "")  # (no broken-syntax case: its parse error prints SCRIPT ERROR, which landings count as a failure)
	_write(norun, "extends RefCounted\nfunc other() -> int:\n\treturn 1\n")
	_check(GdevMain.run_file(ok, self) == "run result: 42", "a good file runs: " + GdevMain.run_file(ok, self))
	_check(GdevMain.run_file(bad, self).begins_with("run: can't compile"), "an empty file is reported")
	_check(GdevMain.run_file(norun, self).contains("no func run"), "a file without run() is reported")
	_check(GdevMain.run_file("", self).begins_with("run: can't compile"), "no path is reported")
	_check(GdevMain.run_file(dir + "/missing.gd", self).begins_with("run: can't compile"), "a missing file is reported")
	for f in [ok, bad, norun]:
		DirAccess.remove_absolute(f)
	for f in fails:
		print("  FAIL ", f)
	print("GDEV RUN: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	quit(0 if fails.is_empty() else 1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
