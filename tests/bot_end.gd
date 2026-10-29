extends RefCounted
## Every bot must END BY ITSELF in networked runs: tools/multibot.ts (the shared host + joiners runner) kills a machine
## still running at --seconds and calls it a timeout (FAIL). Bots without a finish of their own (no tests/bot_kit.gd
## finish(), no quit()) arm this in _ready: when networked (DUO_HOST / DUO_JOIN) or when BOT_END is set, it quits with
## exit 0 after BOT_END seconds (default: host 150 s, joiners 140 s, so joiners leave first and the host sees a normal
## leave). Local runs without BOT_END keep ending at --quit-after. Pass/fail stays the runner's rule (exit code, no
## SCRIPT ERROR, BOT RESULT if any says PASS). core_math-style check: tests/bot_end_test.gd finds bots that never end.
## The runner's own limit wins: multibot sets BOT_DEADLINE (its --seconds per machine), and a bot's end is pulled in to
## leave time for loading and leaving (within_deadline), so a short --seconds (dev.bots.run's 150 s) can't kill a bot
## that was about to end by itself (2026-10-29: bee_garden / block_builders "only passed with 230 s"). Bots with their
## own end time (bot_kit finish() at a fixed second) use within_deadline too.

static func arm(node: Node, host_s := 150.0, joiner_s := 140.0) -> void:
	var joining := OS.has_environment("DUO_JOIN")
	if not (joining or OS.has_environment("DUO_HOST") or OS.has_environment("BOT_END")):
		return
	var s: float = joiner_s if joining else host_s
	if OS.has_environment("BOT_END"):
		s = float(OS.get_environment("BOT_END"))
	s = within_deadline(s, joining)
	var tree := node.get_tree()  # (the tree, not the node: a bot may be freed by a scene change before its end)
	tree.create_timer(s, true, false, true).timeout.connect(func() -> void:
		print("BOT END: ran %d s, quitting (tests/bot_end.gd)" % int(s))
		tree.quit(0))


## `s` seconds, or less when the runner (BOT_DEADLINE: tools/multibot.ts --seconds) would kill this machine first:
## the host ends DEADLINE_SPARE s before it, joiners 10 s earlier still (they leave first, the host sees a normal leave).
const DEADLINE_SPARE := 25.0

static func within_deadline(s: float, joining := OS.has_environment("DUO_JOIN")) -> float:
	if not OS.has_environment("BOT_DEADLINE"):
		return s
	var limit := float(OS.get_environment("BOT_DEADLINE")) - DEADLINE_SPARE - (10.0 if joining else 0.0)
	return clampf(s, 5.0, maxf(5.0, limit))
