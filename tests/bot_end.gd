extends RefCounted
## Every bot must END BY ITSELF in networked runs: tools/multibot.ts (the shared host + joiners runner) kills a machine
## still running at --seconds and calls it a timeout (FAIL). Bots without a finish of their own (no tests/bot_kit.gd
## finish(), no quit()) arm this in _ready: when networked (DUO_HOST / DUO_JOIN) or when BOT_END is set, it quits with
## exit 0 after BOT_END seconds (default: host 150 s, joiners 140 s, so joiners leave first and the host sees a normal
## leave). Local runs without BOT_END keep ending at --quit-after. Pass/fail stays the runner's rule (exit code, no
## SCRIPT ERROR, BOT RESULT if any says PASS). core_math-style check: tests/bot_end_test.gd finds bots that never end.

static func arm(node: Node, host_s := 150.0, joiner_s := 140.0) -> void:
	var joining := OS.has_environment("DUO_JOIN")
	if not (joining or OS.has_environment("DUO_HOST") or OS.has_environment("BOT_END")):
		return
	var s: float = joiner_s if joining else host_s
	if OS.has_environment("BOT_END"):
		s = float(OS.get_environment("BOT_END"))
	var tree := node.get_tree()  # (the tree, not the node: a bot may be freed by a scene change before its end)
	tree.create_timer(s, true, false, true).timeout.connect(func() -> void:
		print("BOT END: ran %d s, quitting (tests/bot_end.gd)" % int(s))
		tree.quit(0))
