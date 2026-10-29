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
		quit_quietly(tree, 0))


## `s` seconds, or less when the runner (BOT_DEADLINE: tools/multibot.ts --seconds) would kill this machine first:
## the host ends DEADLINE_SPARE s before it, joiners 10 s earlier still (they leave first, the host sees a normal leave).
const DEADLINE_SPARE := 25.0

static func within_deadline(s: float, joining := OS.has_environment("DUO_JOIN")) -> float:
	if not OS.has_environment("BOT_DEADLINE"):
		return s
	var limit := float(OS.get_environment("BOT_DEADLINE")) - DEADLINE_SPARE - (10.0 if joining else 0.0)
	return clampf(s, 5.0, maxf(5.0, limit))


## Every bot quits through here (never get_tree().quit(): tests/bot_end_test.gd checks; runs ending at --quit-after
## come here too, via the QuitAfter service, core/quit_after.gd). Stops every sound, gives the
## audio thread a moment to drop the stopped playbacks, then quits. Quitting while a sound plays leaked its
## AudioStreamWAV + playback ("ObjectDB instances were leaked at exit"): the AudioServer frees a stopped playback only
## on its next mix, which never comes after quit() (stopping in _exit_tree is too late, 2026-10-29).
static func quit_quietly(tree: SceneTree, code := 0) -> void:
	if tree.has_meta("bot_quitting"):
		return
	tree.set_meta("bot_quitting", true)
	tree.paused = true  # the game stops starting new sounds (one started in the last frames leaked too)
	_stop_sounds(tree)
	# In REAL time: under --fixed-fps a 0.2 s game timer passes in a few real ms, before the audio thread mixes once
	# (local --quit-after runs still leaked, 2026-10-29). Block briefly so it mixes, then let the main thread's
	# AudioServer update free the dropped playbacks.
	# Until a frame passes with nothing playing (UI sounds keep working while paused, so one can start on the way out;
	# fishing_lake still leaked one in half its runs, 2026-10-29). At most 6 passes.
	for i in 6:
		_stop_sounds(tree)
		OS.delay_msec(100)
		await tree.process_frame
		if not _any_playing(tree):
			break
	# Caches kept on Engine metadata (synthesized sounds, materials: rhythm_band, block_builders, fishing_lake, ...)
	# live for the whole process and were reported as leaks at exit: drop them, the process is ending anyway.
	# (Only caches: flags like save_test_mode must stay, or a save on the way out would go to the real saves.)
	for m in Engine.get_meta_list():
		var v = Engine.get_meta(m)
		if v is Object or v is Dictionary or v is Array:
			Engine.remove_meta(m)
	# This run's own test saves (core/save.gd test_dir(): fresh per process).
	var Save := load("res://core/save.gd")
	if Save.test_mode() or Engine.has_meta(Save.TEST_META):
		Save.remove_tree(Save.test_dir())
	await tree.process_frame
	tree.quit(code)


static func _stop_sounds(tree: SceneTree) -> void:
	for type in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for n in tree.root.find_children("*", type, true, false):
			n.stop()


static func _any_playing(tree: SceneTree) -> bool:
	for type in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for n in tree.root.find_children("*", type, true, false):
			if n.playing:
				return true
	return false
