extends Node
## Several machines in ONE arcade lobby (run it with tools/multibot.ts: a host + N joiners, each its own process).
## Every machine runs this same bot; BOT_MACHINE (0 = host) picks its part and BOT_GROUP_T0 is the shared clock.
##   tools/multibot.ts -n 3 res://tests/arcade_lobby_bot.tscn
## Timeline (seconds after T0):
##   A  the joiners press LB / RB / d-pad one after another (never at the same moment), then the host;
##   B  every machine presses at the SAME moment, each heading for a different game (conflicting choices);
##   then hands off: every machine must settle on the same game (BOT AGREE selection=...), without rebuilding its
##   menu or sending / receiving selections more than the presses explain, and with no traffic at all once settled
##   (the 2026-10-24 bug: a selection received from another machine was broadcast back, so machines with different
##   choices bounced it forever, rebuilding the menu each time; only showed with several Decks connected);
##   C  machine 1 presses A: every machine must start the same game (BOT AGREE started=...).
## Alone (no BOT_MACHINES) it still runs: one local lobby, the same presses.

var arcade: Node
var me := int(OS.get_environment("BOT_MACHINE")) if OS.has_environment("BOT_MACHINE") else 0
var count := int(OS.get_environment("BOT_MACHINES")) if OS.has_environment("BOT_MACHINES") else 1
var t0_ms := int(OS.get_environment("BOT_GROUP_T0")) if OS.has_environment("BOT_GROUP_T0") else 0
var plan: Array = []  # [time, button, machine] for every machine (the same list everywhere)
var my_presses: Array = []
var failures := 0
var phase := "wait"
var input_end := 0.0
var quiet_from: Dictionary = {}
var started_scene := ""
var expected_index := -1

const SETTLE := 2.5  # seconds after the last press until every machine must agree
const QUIET_AFTER := 1.0  # from here on nothing may change hands any more


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_plan()
	# The arcade becomes the current scene, so starting a game replaces IT and this bot (a sibling under the root)
	# keeps watching.
	arcade = load("res://arcade.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arcade)
	(func() -> void: get_tree().current_scene = arcade).call_deferred()
	print("LOBBY BOT: machine %d of %d, %d presses planned (%d mine)" % [me, count, plan.size(), my_presses.size()])


func _make_plan() -> void:
	var dirs := [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_DOWN]
	var t := 1.0
	# A: one machine at a time (joiners first, then the host), presses 0.35 s apart, 0.6 s between machines.
	for k in range(1, count) + [0]:
		for j in 3:
			plan.append([t, dirs[(k + j) % dirs.size()], k])
			t += 0.35
		t += 0.6
	# B: everyone at once, each to a different place (machine k: k RBs then a d-pad down; host: LB).
	t += 0.5
	for k in count:
		var presses: Array = [JOY_BUTTON_LEFT_SHOULDER] if k == 0 else []
		for j in k:
			presses.append(JOY_BUTTON_RIGHT_SHOULDER)
		presses.append(JOY_BUTTON_DPAD_DOWN)
		for j in presses.size():
			plan.append([t + j * 0.06, presses[j], k])
	for p in plan:
		input_end = maxf(input_end, p[0])
		if p[2] == me:
			my_presses.append(p)


var _game_t := -4.0  # no shared clock (run alone, e.g. --fixed-fps): game time, starting 4 s from now

func _now() -> float:
	if t0_ms == 0:
		return _game_t
	return (Time.get_unix_time_from_system() * 1000.0 - t0_ms) / 1000.0


func _fail(msg: String) -> void:
	failures += 1
	print("BOT ASSERT FAILED: machine %d: %s" % [me, msg])


func _press(button: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)


func _process(delta: float) -> void:
	_game_t += delta
	var now := _now()
	if phase == "wait":
		if now >= 0.0:
			_check_connected()
			phase = "input"
		return
	if phase == "input":
		while not my_presses.is_empty() and now >= float(my_presses[0][0]):
			_press(int(my_presses.pop_front()[1]))
		if now >= input_end + QUIET_AFTER and not quiet_from:
			quiet_from = arcade.stats.duplicate()
		if now >= input_end + SETTLE:
			_check_settled()
			phase = "start"
		return
	if phase == "start":
		if now >= input_end + SETTLE + 0.5 and me == mini(1, count - 1) and not has_meta("pressed_a"):
			set_meta("pressed_a", true)
			_press(JOY_BUTTON_A)
		var scene := get_tree().current_scene
		if scene != null and scene != arcade and is_instance_valid(scene) and scene.scene_file_path != "":
			started_scene = scene.scene_file_path
			print("BOT AGREE started=%s" % started_scene)
			if started_scene != str(arcade_games()[expected_index].scene):
				_fail("started %s, but everyone had settled on %s" % [started_scene, arcade_games()[expected_index].name])
			phase = "done"
			set_meta("done_at", now)
		elif now >= input_end + SETTLE + 6.0:
			_fail("no game started within 5.5 s of A being pressed on machine 1")
			phase = "done"
			set_meta("done_at", now)
		return
	if phase == "done" and now >= float(get_meta("done_at")) + 2.0:
		print("BOT RESULT: %s (machine %d)" % ["PASS" if failures == 0 else "FAIL", me])
		preload("res://tests/bot_end.gd").quit_quietly(get_tree(), 0 if failures == 0 else 1)
		phase = "quit"


func arcade_games() -> Array:
	return preload("res://arcade/arcade.gd").GAMES


func _check_connected() -> void:
	if count < 2:
		return
	if me == 0:
		if arcade.mode != "host" or arcade.machines.size() != count - 1:
			_fail("host: mode %s with %d of %d joiners connected at T0" % [arcade.mode, arcade.machines.size(), count - 1])
	elif arcade.mode != "client" or arcade.join_deadline != 0:
		_fail("joiner not connected to the lobby at T0 (mode %s)" % arcade.mode)


func _check_settled() -> void:
	var s: Dictionary = arcade.stats
	var total := plan.size()
	var mine := 0
	for p in plan:
		if p[2] == me:
			mine += 1
	expected_index = int(arcade.selected)
	print("LOBBY BOT: machine %d settled on %s (%d); rebuilds %d, sent %d, received %d (presses: %d, mine %d)" % [
		me, arcade_games()[expected_index].name, expected_index, s.show_category, s.sync_out, s.sync_in, total, mine])
	print("BOT AGREE selection=%d" % expected_index)
	# The focused card must be the selection (the TV shows what the machine thinks is chosen).
	var f: Control = get_viewport().gui_get_focus_owner()
	if not arcade.cards.has(expected_index) or f != arcade.cards[expected_index]:
		_fail("the highlighted card is not the selected game %d" % expected_index)
	# Bounded work: each press anywhere moves this machine at most once (one rebuild, one selection change). Plus
	# the first build, and the host's hello to each joiner.
	if s.show_category > total + 3:
		_fail("menu rebuilt %d times for %d presses (echo storm?)" % [s.show_category, total])
	if s.sync_out > 2 * mine + 2:
		_fail("sent %d selections for %d own presses (echoing other machines' choices?)" % [s.sync_out, mine])
	if s.sync_in > 2 * total + count + 2:
		_fail("received %d selections for %d presses (RPC storm)" % [s.sync_in, total])
	for k in s:
		if quiet_from.has(k) and s[k] != quiet_from[k]:
			_fail("%s still changing %.1f s after the last press (%d -> %d): machines are bouncing the selection" % [
				k, SETTLE - QUIET_AFTER, quiet_from[k], s[k]])
