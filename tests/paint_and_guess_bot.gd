extends Node
## Headless bot for Paint and Guess. The artist (local / DUO_HOST) paints doodles - circles, zigzags and
## spirals in different colours - and every local guesser thinks for a moment, then picks one of its
## four answers (wrong ones get crossed out, so it always finds the right one within four tries).
## BOT_PLAYERS=N: guessers to have (local split screen: up to 5; TV machine (DUO_JOIN): up to 6).
## BOT_VR=1 (local / host): the artist is driven through the VR code path with a fake head and hand:
## touch-painting, laser-painting from a step back, A for colours, touching CLEAR / NEW WORD / a pot,
## and walking with the left stick.
## Local mode also joins one guesser by pressing A on a fake controller, checks Start does NOT join,
## skips ahead to the last round after the first one, and plays again from the final scores.

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var join_time := 0.0
var report_t := 0.0
var cont_t := 0.0
var rounds_done := 0
var games_done := 0
var last_state := ""
var stroke_t := 0.0
var shape := 0
var vr_t := 0.0
var vr_step := ""
var max_points := 0
var wrong_total := 0
var right_total := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/paint_and_guess/main.tscn").instantiate()
	add_child(main)


func _pad_press(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)


func _process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
	if mode == "local" and joined and t > join_time + 0.3 and not has_meta("start_checked"):
		set_meta("start_checked", true)
		print("BOT: Start on a new controller: joined=%s, menu opened=%s" % [main.joy_owner.has(FAKE_PAD + 1), get_tree().paused])
		if get_tree().paused:
			_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # close the menu again
	if get_tree().paused:
		return
	if has_meta("pad_join") and t > join_time + 0.5:
		remove_meta("pad_join")
		_pad_press(FAKE_PAD, JOY_BUTTON_A)
	if mode == "local" and joined and t > join_time + 0.8 and not has_meta("pad_checked"):
		set_meta("pad_checked", true)
		print("BOT: fake controller %d drives P%d, paused=%s" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1, get_tree().paused])
	for i in range(1, main.players.size()):
		var g = main.players[i]
		if g.active and g.is_local():
			g.bot = true
	if mode != "client":
		var a = main.players[0]
		if a.fake_vr:
			_drive_vr(a, delta)
		elif not a.vr:
			_drive_flat(a, delta)
	_track(mode)
	if (main.state == "reveal" or main.state == "over") and main.state_t > 2.0:
		cont_t -= delta
		if cont_t <= 0.0:
			cont_t = 1.0
			main.debug_continue()
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


func _join_players(mode: String) -> void:
	if mode == "host":
		return
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else 2
	var cap := 5 if mode == "local" else 6
	var target := clampi(want, 1, cap)
	var extra := target - 1
	print("BOT: %s mode, joining %d extra guessers" % [mode, extra])
	if mode == "local":
		_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # Start must open the menu, not join
		if extra > 0:
			set_meta("pad_join", true)  # A on the fake controller once the menu is closed again
			extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


## A doodle point for shape k at phase u (0..1), in canvas metres.
func _doodle(k: int, u: float) -> Vector2:
	match k % 4:
		0:
			return Vector2(cos(u * TAU), sin(u * TAU)) * 0.25 + Vector2(-0.2, 0.05)
		1:
			return Vector2(-0.45 + u * 0.9, 0.15 * (1.0 if int(u * 8.0) % 2 == 0 else -1.0) * fmod(u * 8.0, 1.0) - 0.2)
		2:
			var r := 0.05 + u * 0.3
			return Vector2(cos(u * TAU * 3.0), sin(u * TAU * 3.0)) * r + Vector2(0.2, 0.0)
		_:
			return Vector2(sin(u * TAU * 2.0) * 0.4, cos(u * TAU) * 0.3)


## Flat artist: paint a shape for ~2 s, lift the brush, next shape (sometimes a new colour), and wipe
## the canvas once per round.
func _drive_flat(a, delta: float) -> void:
	a.bot = true
	if main.state != "draw" and main.state != "wait":
		a.bot_paint = false
		return
	stroke_t += delta
	var u := stroke_t / 2.0
	if u >= 1.15:
		stroke_t = 0.0
		shape += 1
		if shape % 2 == 0:
			a.next_color()
		if shape % 7 == 6:
			main.artist_clear()
		return
	a.bot_paint = u < 1.0
	a.bot_cursor = _doodle(shape, minf(u, 1.0))


## Fake VR artist: the same hand logic the Steam Frame uses.
func _drive_vr(a, delta: float) -> void:
	var canvas = main.canvas
	var n: Vector3 = canvas.normal()
	vr_t += delta
	if t > 30.0 and not has_meta("vr_sat_down"):
		set_meta("vr_sat_down", true)
		a.head.position.y -= 0.4  # the headset goes to a smaller kid / they sit down: the easel should follow
		print("BOT VR: head drops to %.2f m" % a.head.global_position.y)
	a.bot_lstick = Vector2.ZERO
	a.bot_a = false
	if main.state != "draw":
		a.bot_trigger = false
		a.bot_hand_pos = a.head.global_position + Vector3(0.2, -0.3, -0.3)
		a.bot_hand_fwd = -n
		vr_t = 0.0
		return
	var step := ""
	if vr_t < 3.0:
		step = "touch-paint"
		var p := _doodle(0, vr_t / 3.0)
		var tip: Vector3 = canvas.canvas_to_world(p, 0.04)
		a.bot_hand_fwd = -n
		a.bot_hand_pos = tip + n * a.TIP
		a.bot_trigger = vr_t > 0.15
	elif vr_t < 3.4:
		step = "A (colour)"
		a.bot_trigger = false
		a.bot_a = vr_t < 3.2
		a.bot_hand_pos = canvas.canvas_to_world(Vector2(0, 0), 0.5)
	elif vr_t < 6.0:
		step = "laser-paint"
		var p2 := _doodle(2, (vr_t - 3.4) / 2.6)
		var from: Vector3 = canvas.canvas_to_world(Vector2(0.1, -0.1), 1.0)
		var to: Vector3 = canvas.canvas_to_world(p2, 0.0)
		a.bot_hand_pos = from
		a.bot_hand_fwd = (to - from).normalized()
		a.bot_trigger = vr_t > 3.6
	elif vr_t < 6.8:
		step = "touch pot"
		a.bot_trigger = false
		a.bot_hand_fwd = -n
		a.bot_hand_pos = canvas.pot_world(4) + n * (a.TIP + 0.01) if vr_t > 6.3 else canvas.canvas_to_world(Vector2(0, -0.2), 0.3)
	elif vr_t < 7.6:
		step = "walk"
		a.bot_lstick = Vector2(0.0, 0.6 if vr_t < 7.2 else -0.6)
		a.bot_hand_pos = a.head.global_position + Vector3(0.2, -0.3, -0.3)
	elif vr_t < 8.6 and not has_meta("vr_cleared"):
		step = "touch CLEAR"
		a.bot_hand_fwd = -n
		a.bot_hand_pos = canvas.clear_world() + n * 0.02 if vr_t > 8.1 else canvas.canvas_to_world(Vector2(0.4, 0.2), 0.3)
		if vr_t > 8.4 and main.canvas.point_count == 0:
			set_meta("vr_cleared", true)
	else:
		vr_t = 0.0
	if step != vr_step:
		vr_step = step
		print("BOT VR: %s (colour %d, head %.2f m, canvas centre %.2f m, points %d)" % [step, a.color_idx,
			a.head.global_position.y, canvas.cy, canvas.point_count])
	# Ask for a NEW WORD once, early in the first round.
	if main.round_n == 1 and main.state_t > 1.0 and main.state_t < 1.8 and main.skips_left == 2:
		if not has_meta("vr_skip"):
			set_meta("vr_skip", true)
			print("BOT VR: touching NEW WORD (word was '%s')" % main.word)
		a.bot_trigger = false
		a.bot_hand_pos = canvas.skip_world() + n * 0.02 if main.state_t > 1.3 else canvas.canvas_to_world(Vector2(0.5, -0.1), 0.3)


func _track(mode: String) -> void:
	var st: String = main.state
	max_points = maxi(max_points, main.canvas.point_count)
	if st != last_state:
		if st == "reveal":
			rounds_done += 1
			var got := 0
			for g in main.active_guessers():
				if g.got:
					got += 1
			print("BOT %s: ROUND %d COMPLETE - '%s' guessed by %d/%d, canvas %d strokes / %d points" % [mode, main.round_n,
				main.reveal_word, got, main.active_guessers().size(), main.canvas.strokes.size(), main.canvas.point_count])
			if mode == "local" and rounds_done == 1:
				main.round_n = main.ROUNDS - 1  # jump to the last round to reach the final scores
		elif st == "over":
			games_done += 1
			print("BOT %s: GAME OVER seen (%s)" % [mode, main._scoreboard()])
		elif st == "intro" and last_state == "over":
			print("BOT %s: playing again" % mode)
		last_state = st


func _report(mode: String) -> void:
	var act: Array[String] = []
	for i in range(1, main.players.size()):
		var g = main.players[i]
		if g.active:
			act.append("P%d:%d%s%s" % [g.index + 1, g.score, "✓" if g.got else "", " lock" if g.lock_left > 0.0 else ""])
	var views := 0
	var cell := Vector2.ZERO
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
			cell = p.get_meta("view").size
	print("BOT %s t=%.0f state=%s round=%d time=%.0f hint='%s' artist=%d strokes=%d points=%d (max %d) rev=%d opts=%s views=%d cell=%s rounds_done=%d games_done=%d [%s]" % [
		mode, t, main.state, main.round_n, main.time_left, main.hint_text, main.players[0].score,
		main.canvas.strokes.size(), main.canvas.point_count, max_points, main.canvas.rev,
		str(main.options_for(1)), views, cell, rounds_done, games_done, ", ".join(act)])
