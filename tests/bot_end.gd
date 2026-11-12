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
	tally()  # count this bot's checks and failure lines from the start, in local runs too (the shared verdict, below)
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
		quit_quietly(tree, 0, ", ended by tests/bot_end.gd after %d s" % int(s)))


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
## `note` says why it ended (", stopped at the --quit-after frame limit"): it goes into the BOT RESULT line this
## prints for a bot that hasn't said one (say_result).
static func quit_quietly(tree: SceneTree, code := 0, note := "") -> void:
	if tree.has_meta("bot_quitting"):
		return
	tree.set_meta("bot_quitting", true)
	# Bots on tests/bot_kit.gd that haven't finished say their checks so far, before the scene (and the kit) goes.
	if not said():
		tree.call_group("bot_frame_limit", "on_frame_limit", note if note != "" else ", ended before its finish()")
	tree.paused = true  # the game stops starting new sounds
	# Free the game first: with no game code left nothing can start a sound on the way out (paused UI code still
	# could, and one started in the very last frame leaked: fishing_lake, kart_race, rhythm_band, dodge_ball,
	# 2026-10-29). A static coroutine, so it keeps going after the bot that called it is freed.
	if tree.current_scene != null:
		tree.current_scene.queue_free()
	_stop_sounds(tree)
	# In REAL time: under --fixed-fps a 0.2 s game timer passes in a few real ms, before the audio thread mixes once.
	# Block briefly so it mixes, then let the main thread's AudioServer update free the dropped playbacks; repeat
	# until a frame passes with nothing playing (at most 6 passes).
	for i in 6:
		await tree.process_frame
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
	# Freeing the scene ran the bots' _exit_tree (some say their own BOT RESULT there, dragon_rider): any bot that
	# still hasn't said one gets the shared tally's verdict now. A run without a verdict tests nothing (2026-11-11).
	say_result(note)
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


# --- The shared verdict ---------------------------------------------------------------------------------------------
## Every bot ends with "BOT RESULT: PASS / FAIL (N checks)" in local, host AND joining runs: tools/multibot.ts and
## brepl dev.bots.run fail a run without one (it tested nothing: penalty_shootout's networked runs, 2026-11-11).
## bot_kit bots say it in finish(). Bots without bot_kit count their checks here:
##   const BotEnd := preload("res://tests/bot_end.gd")
##   BotEnd.check(main.score > 0, "somebody scored")   # a failure prints "SCRIPT ERROR: BOT ASSERT FAILED: ..."
## and arm() (or check()) starts the Tally: a Logger that also counts every failure line the bot prints its own way
## ("Bot: FAIL ...", "BOT: HOUSE FAIL", "BOT: ERROR instruction text ...", "SCRIPT ERROR: BOT DEEP: ...") and every script error, and notices when a bot
## printed a BOT RESULT itself. quit_quietly prints the tally's verdict when nobody did; 0 checks is a FAIL.

static var _tally: Tally


class Tally extends Logger:
	var mutex := Mutex.new()
	var checks := 0
	var fails := 0
	var said := false
	var first_fail := ""

	func _log_message(message: String, _error: bool) -> void:
		mutex.lock()
		for line in message.split("\n", false):
			if "BOT RESULT:" in line:
				said = true
			elif is_fail_line(line):
				fails += 1
				if first_fail == "":
					first_fail = line.strip_edges().left(160)
		mutex.unlock()

	func _log_error(_function: String, file: String, line: int, _code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		mutex.lock()
		fails += 1
		if first_fail == "":
			first_fail = ("script error: %s @ %s:%d" % [rationale, file, line]).left(160)
		mutex.unlock()

	## A failure line in any of the bots' own styles (no RegEx: loggers run on any thread).
	static func is_fail_line(line: String) -> bool:
		var l := line.strip_edges()
		if l.begins_with("SCRIPT ERROR"):
			return true
		if not l.to_lower().begins_with("bot"):
			return false
		for w in ["FAIL", "FAILED", "FAIL:", "FAILED:", "ERROR", "ERROR:"]:
			if (" " + w + " ") in (" " + l.replace("\t", " ") + " "):
				return true
		return false


## The tally (started on first use: arm() and check() start it).
static func tally() -> Tally:
	if _tally == null:
		_tally = Tally.new()
		OS.add_logger(_tally)
	return _tally


## Count one check; a failed one prints a failure line (the runner and the tally both count it). Returns ok.
static func check(ok: bool, what: String) -> bool:
	var t := tally()
	t.mutex.lock()
	t.checks += 1
	t.mutex.unlock()
	if not ok:
		printerr("SCRIPT ERROR: BOT ASSERT FAILED: " + what)
	return ok


## Whether a BOT RESULT line was printed already (by bot_kit, the bot itself, or say_result).
static func said() -> bool:
	return _tally != null and _tally.said


## Print the tally's BOT RESULT unless one was said already (or no tally ran: a test that isn't a bot).
static func say_result(note := "") -> void:
	if _tally == null or _tally.said:
		return
	_tally.mutex.lock()
	var checks := _tally.checks
	var fails := _tally.fails
	var first := _tally.first_fail
	_tally.mutex.unlock()
	if fails > 0:
		printerr("SCRIPT ERROR: BOT RESULT: FAIL (%d failure line(s), %d checks%s; first: %s)" % [fails, checks, note, first])
	elif checks == 0:
		printerr("SCRIPT ERROR: BOT RESULT: FAIL (0 checks%s: this bot counted nothing; use tests/bot_end.gd check() or tests/bot_kit.gd)" % note)
	else:
		print("BOT RESULT: PASS (%d checks%s)" % [checks, note])
