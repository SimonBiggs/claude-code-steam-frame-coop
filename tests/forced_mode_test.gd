extends SceneTree
## A mode forced by an env setting (<GAME>_MODE=hard: bots, launchers, the arcade's What's New "try") is set on the
## HOST only and reaches every TV machine through the host's net state: games read it with net.forced_mode("XX_MODE")
## (core/net.gd) and bots ask BotKit.mode_forced(main.net, "XX_MODE") / forced_mode(...) (tests/bot_kit.gd) before
## their "mode was picked / saved" checks. 2026-11-12: Dodge Ball, Fruit Catch and Tiny Town Tycoon bots failed their
## mode-pick checks on a forced mode, and Dungeon Delve needed DD_MODE on both machines (the TV read its own env).
## Fails:
##   - any games/**.gd or tests/*.gd reading a *_MODE env directly (OS.get_environment / has_environment), except the
##     bots' own choices (*BOT_MODE: which orb a bot walks to);
##   - `var x := net.forced_mode(...)` (a Variant: Dungeon Delve's main.gd failed to parse, 2026-11-12);
##   - Net.forced_mode not giving a TV machine the host's value (and ignoring its own env).
##   godot-test --headless --path . -s res://tests/forced_mode_test.gd   -> FORCED MODE: PASS / FAIL

const NetScript := preload("res://core/net.gd")

var fails: Array[String] = []


func _initialize() -> void:
	var re := RegEx.create_from_string("OS\\.(get|has)_environment\\(\"([A-Z0-9_]*_MODE)\"\\)")
	var infer_re := RegEx.create_from_string(":=\\s*(main\\.)?net\\.forced_mode\\(")
	var files: Array[String] = []
	_collect("res://games", files)
	for f in DirAccess.get_files_at("res://tests"):
		if f.ends_with(".gd") and f != "forced_mode_test.gd":
			files.append("res://tests/" + f)
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for m in re.search_all(lines[i]):
				var key := m.get_string(2)
				if key.ends_with("BOT_MODE"):
					continue
				var how := "BotKit.mode_forced(main.net, \"%s\")" % key if path.begins_with("res://tests") else "net.forced_mode(\"%s\")" % key
				fails.append("%s:%d reads %s straight from this machine's env: use %s (a TV machine gets the host's)" % [path, i + 1, key, how])
			if infer_re.search(lines[i]) != null:
				fails.append("%s:%d infers a type from net.forced_mode() (net is an untyped Node, so it's a Variant and the script won't parse): write `var x: String = ...`" % [path, i + 1])
	_runtime()
	for f in fails:
		print("  FAIL ", f)
	print("FORCED MODE: %s (%d files scanned)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(), files.size()])
	quit(0 if fails.is_empty() else 1)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)


## The host publishes its forced mode; a TV machine reads the host's, never its own env.
func _runtime() -> void:
	OS.set_environment("FMT_TEST_MODE", "hard")
	var host = NetScript.new()
	if host.forced_mode("FMT_TEST_MODE") != "hard" or String(host.state_get(NetScript.FORCED_MODE_KEY, "")) != "hard":
		fails.append("the host / local game doesn't read its env and share it as net state '%s'" % NetScript.FORCED_MODE_KEY)
	if host.forced_mode("FMT_UNSET_MODE") != "":
		fails.append("an unset env isn't \"\"")
	var tv = NetScript.new()
	tv.mode = "client"
	if tv.forced_mode("FMT_TEST_MODE") != "":
		fails.append("a TV machine read its own env instead of the host's net state")
	tv._state[NetScript.FORCED_MODE_KEY] = "brave"
	if tv.forced_mode("FMT_TEST_MODE") != "brave":
		fails.append("a TV machine doesn't get the host's forced mode from net state")
	host.free()
	tv.free()
	OS.unset_environment("FMT_TEST_MODE")