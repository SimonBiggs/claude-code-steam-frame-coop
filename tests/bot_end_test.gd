extends SceneTree
## Every tests/*_bot.gd must be able to END BY ITSELF in a networked run (tools/multibot.ts kills a machine still
## running at --seconds and reports a timeout): it quits itself (quit(...)), finishes through tests/bot_kit.gd
## (finish()), or arms tests/bot_end.gd in its _ready. Helper brains (dungeon_delve_deep_bot.gd) are exempt.
##   godot-test --headless --path . -s res://tests/bot_end_test.gd

const HELPERS := ["dungeon_delve_deep_bot.gd"]


func _initialize() -> void:
	var bad: Array[String] = []
	var n := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not f.ends_with("_bot.gd") or f in HELPERS:
			continue
		n += 1
		var src := FileAccess.get_file_as_string("res://tests/" + f)
		if not ("quit(" in src or "finish(" in src or "bot_end.gd" in src):
			bad.append(f)
	if bad.is_empty():
		print("BOT END: PASS (%d bots can end by themselves)" % n)
	else:
		printerr("SCRIPT ERROR: BOT END: these bots never end by themselves (arm tests/bot_end.gd in _ready): " + ", ".join(bad))
	quit(1 if not bad.is_empty() else 0)
