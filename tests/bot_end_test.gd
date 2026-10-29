extends SceneTree
## Every tests/*_bot.gd must be able to END BY ITSELF in a networked run (tools/multibot.ts kills a machine still
## running at --seconds and reports a timeout): it quits itself with a BOT RESULT line, finishes through tests/bot_kit.gd
## (finish()), or arms tests/bot_end.gd in its _ready. Helper brains (dungeon_delve_deep_bot.gd) are exempt.
##   godot-test --headless --path . -s res://tests/bot_end_test.gd

const HELPERS := ["dungeon_delve_deep_bot.gd"]
const LATE := 120.0  ## a host end this late must be capped by bot_end.gd within_deadline
var weak_re := RegEx.create_from_string("slot_stick\\(.*normalized\\(\\) \\* (0\\.[0-2]\\d*)\\b")
var late_re := RegEx.create_from_string("(\\d+(?:\\.\\d+)?) if host else")


func _initialize() -> void:
	var bad: Array[String] = []
	var late: Array[String] = []
	var flat: Array[String] = []
	var n := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not f.ends_with("_bot.gd") or f in HELPERS:
			continue
		n += 1
		var src := FileAccess.get_file_as_string("res://tests/" + f)
		# quit() alone is not enough (often only a BOT_COUNT-style side mode quits): it must come with a BOT RESULT line.
		if not ("finish(" in src or "bot_end.gd" in src or ("quit(" in src and "BOT RESULT" in src)):
			bad.append(f)
		# A long networked end of its own ("150.0 if host else (140.0 if client ...") must stay inside the runner's
		# limit: tools/multibot.ts kills at --seconds (default 180, dev.bots.run callers pass less), so it goes through
		# bot_end.gd within_deadline (crystal_saga ended at 240 s and always timed out, 2026-10-29).
		# A flat host (TV / Deck hosting, DUO_FLAT_HOST) seats its own pads in slot 0 (core/party.gd allow_slot0): a bot
		# whose game has one must seat a player there, or the host machine plays empty (tiny_town_tycoon's host never
		# built a town; crystal_saga's never had a hero, 2026-10-29).
		var game := "res://games/%s/main.gd" % f.trim_suffix("_bot.gd")
		if FileAccess.file_exists(game) and "allow_slot0" in FileAccess.get_file_as_string(game) \
				and not ("has_vr" in src or "flat_host" in src or "DUO_FLAT_HOST" in src):
			flat.append(f)
		# A joining machine's party lists other machines' players too: compare kit.seated() (its own seats), not
		# party.player_count(), with seated_want (failed with a flat host's P1, 2026-10-29).
		if "player_count(), kit.seated_want(" in src:
			flat.append(f + " (kit.seated())")
		# A bot's stick push of 0.2 or less is inside core/party.gd's deadzone: it does nothing (crystal_saga's heroes
		# never turned to face what they shot, 2026-10-29). Push 0.5 for a gentle "face it".
		var weak := weak_re.search(src)
		if weak != null:
			flat.append("%s (stick push %s is inside the 0.2 deadzone)" % [f, weak.get_string(1)])
		var m := late_re.search(src)
		if m != null and float(m.get_string(1)) >= LATE and not "within_deadline(" in src:
			late.append("%s (%s s)" % [f, m.get_string(1)])
	if not late.is_empty():
		printerr("SCRIPT ERROR: BOT END: these bots end late in networked runs without bot_end.gd within_deadline (the runner kills them first): " + ", ".join(late))
	if not flat.is_empty():
		printerr("SCRIPT ERROR: BOT END: these bots break networked play (a flat host: join one pad there when not main.net.has_vr; clients check kit.seated(); sticks): " + ", ".join(flat))
	if bad.is_empty() and late.is_empty() and flat.is_empty():
		print("BOT END: PASS (%d bots can end by themselves, inside the runner's limit)" % n)
	elif not bad.is_empty():
		printerr("SCRIPT ERROR: BOT END: these bots never end by themselves (arm tests/bot_end.gd in _ready): " + ", ".join(bad))
	quit(1 if not (bad.is_empty() and late.is_empty() and flat.is_empty()) else 0)
