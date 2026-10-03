extends Node
## Headless bot for Paint and Guess. The artist (local / DUO_HOST) paints doodles - circles, zigzags and
## spirals in different colours (incl. RAINBOW and SPARKLE), undoes a stroke now and then - and every
## local guesser thinks for a moment, then picks one of its four answers (wrong ones get crossed out,
## so it always finds the right one within four tries) and cheers. In TEAM PAINT the guessers paint
## with their brush rings and the artist pops balloons (one wrong, then the right one). At the end
## everyone votes in the gallery vote.
## BOT_PLAYERS=N: guessers to have (local split screen: up to 5; TV machine (DUO_JOIN): up to 6).
## BOT_VR=1 (local / host): the artist is driven through the VR code path with a fake head and hand:
## touch-painting, laser-painting from a step back, A for colours, touching CLEAR / UNDO / NEW WORD / a
## pot (RAINBOW), walking with the left stick, touching balloons and voting by touching a picture.
## Local / host mode skips intros and jumps from round 1 to TEAM PAINT (3) to the GOLDEN FINAL (5), so a
## short run sees every kind of round, the vote and the final scores; local mode also joins one guesser
## by pressing A on a fake controller, checks Start does NOT join, and plays again from the final scores.
## Real controllers are attached to this machine: their button presses are swallowed (they must not
## pause or join the test), and if anything else pauses the game the bot resumes it.

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
var my_pause := false
var paused_t := 0.0
var seen_types := {}
var balloon_tries := 0
var votes_cast := 0
var undo_done := -1


class RealPadFilter extends Node:
	## Sits after the bot in the tree, so it sees input first: real controllers (device < 40) are ignored.
	func _input(event: InputEvent) -> void:
		var jb := event as InputEventJoypadButton
		var jm := event as InputEventJoypadMotion
		if (jb != null and jb.device < FAKE_PAD) or (jm != null and jm.device < FAKE_PAD):
			get_viewport().set_input_as_handled()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/paint_and_guess/main.tscn").instantiate()
	add_child(main)
	var filt := RealPadFilter.new()
	filt.name = "RealPadFilter"
	filt.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(filt)


func _pad_press(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)


## Something paused the game that wasn't us (a real controller's Start, a stray key): resume it.
func _unstick(delta: float) -> void:
	if not get_tree().paused or my_pause:
		paused_t = 0.0
		return
	paused_t += delta
	if paused_t < 1.0:
		return
	paused_t = 0.0
	print("BOT: the game was paused by something else (a real controller?) - resuming")
	for n in main.get_children():
		if n is CanvasLayer and n.get("panel") != null and n.has_method("_resume"):
			if n.panel.visible:
				n._resume()
	if get_tree().paused:
		get_tree().paused = false
		if main.net.mode == "client":
			main.net.send_action("pause", [false])
		else:
			main._set_pause_banner(false, "")


func _process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	_unstick(delta)
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
	if mode == "local" and joined and t > join_time + 0.3 and not has_meta("start_checked"):
		set_meta("start_checked", true)
		print("BOT: Start on a new controller: joined=%s, menu opened=%s" % [main.joy_owner.has(FAKE_PAD + 1), get_tree().paused])
		if get_tree().paused:
			_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # close the menu again
		my_pause = false
	# Robustness check: a real controller's Start must be ignored, and a pause from outside gets undone.
	if OS.has_environment("BOT_PAUSE_TEST") and t > 6.0 and not has_meta("pause_tested"):
		set_meta("pause_tested", true)
		_pad_press(0, JOY_BUTTON_START)
		print("BOT: real controller 0 pressed Start: paused=%s (must be false)" % get_tree().paused)
		for n in main.get_children():
			if n is CanvasLayer and n.has_method("_open"):
				n._open()
				print("BOT: opened the pause menu from outside (like a real controller would): paused=%s" % get_tree().paused)
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
		# Short runs: skip the intros (after a moment to read them).
		if main.state == "intro" and main.state_t > 1.5 and main.state_t < 4.0:
			main.state_t = 99.0
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
		my_pause = true
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


## The right balloon / a wrong one for TEAM PAINT.
func _balloon_choice(want_right: bool) -> int:
	var o: Array = main.options_for(0)
	for i in o.size():
		if (str(o[i]) == main.word) == want_right and (main.vr_wrong_mask >> i) & 1 == 0:
			return i
	return -1


## Flat artist: paint a shape for ~2 s, lift the brush, next shape (sometimes a new colour), undo and
## wipe now and then. TEAM PAINT: click a wrong balloon, then the right one. Vote: click a picture.
func _drive_flat(a, delta: float) -> void:
	a.bot = true
	var amode: String = main.artist_mode()
	if amode == "guess":
		stroke_t += delta
		var target := _balloon_choice(balloon_tries > 0)
		if target >= 0 and main.state_t > 4.0 + balloon_tries * 2.5:
			var bl: Vector3 = main.canvas.balloon_local(target)
			a.bot_cursor = Vector2(bl.x, bl.y)
			a.bot_paint = not a.bot_paint
			if a.bot_paint:
				balloon_tries += 1
				print("BOT: artist clicks balloon %d ('%s')" % [target, str(main.options_for(0)[target])])
		else:
			a.bot_paint = false
		return
	if amode == "vote":
		if main.artist_vote_k < 0 and main.state_t > 2.0:
			var k := randi() % maxi(1, main.canvas.vote_cells.size())
			var c: Vector2 = main.canvas.vote_cells[k] if k < main.canvas.vote_cells.size() else Vector2.ZERO
			a.bot_cursor = c
			a.bot_paint = not a.bot_paint
		return
	if amode != "paint":
		a.bot_paint = false
		balloon_tries = 0
		return
	stroke_t += delta
	var u := stroke_t / 2.0
	if u >= 1.15:
		stroke_t = 0.0
		shape += 1
		if shape % 2 == 0:
			a.next_color(8 if shape % 6 == 2 else (9 if shape % 6 == 4 else -1))
		if shape % 5 == 3 and undo_done != main.round_n:
			undo_done = main.round_n
			main.artist_undo()
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
	var amode: String = main.artist_mode()
	var rest: Vector3 = a.head.global_position + Vector3(0.2, -0.3, -0.3)
	if amode == "guess":
		# TEAM PAINT: touch a wrong balloon, then the right one.
		var target := _balloon_choice(balloon_tries > 0)
		a.bot_trigger = false
		a.bot_hand_fwd = -n
		if target >= 0 and main.state_t > 4.0 + balloon_tries * 2.5 and main.vr_lock <= 0.0:
			a.bot_hand_pos = canvas.balloon_world(target)
			if not has_meta("bal_touch%d" % balloon_tries):
				set_meta("bal_touch%d" % balloon_tries, true)
				print("BOT VR: touching balloon %d ('%s')" % [target, str(main.options_for(0)[target])])
				balloon_tries += 1
		else:
			a.bot_hand_pos = rest
		return
	if amode == "vote":
		a.bot_trigger = false
		a.bot_hand_fwd = -n
		if main.artist_vote_k < 0 and main.state_t > 2.0 and not main.canvas.vote_cells.is_empty():
			var c: Vector2 = main.canvas.vote_cells[0]
			a.bot_hand_pos = canvas.canvas_to_world(c, 0.0) + n * (a.TIP - 0.01) if main.state_t > 2.4 else canvas.canvas_to_world(c, 0.3)
			if not has_meta("vote_touch"):
				set_meta("vote_touch", true)
				print("BOT VR: touching picture 1 to vote")
		else:
			a.bot_hand_pos = rest
		return
	if main.state != "draw":
		a.bot_trigger = false
		a.bot_hand_pos = rest
		a.bot_hand_fwd = -n
		vr_t = 0.0
		balloon_tries = 0
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
		step = "touch RAINBOW pot"
		a.bot_trigger = false
		a.bot_hand_fwd = -n
		a.bot_hand_pos = canvas.pot_world(canvas.RAINBOW) + n * (a.TIP + 0.01) if vr_t > 6.3 else canvas.canvas_to_world(Vector2(0, -0.2), 0.3)
	elif vr_t < 8.4:
		step = "rainbow touch-paint"
		var p3 := _doodle(1, (vr_t - 6.8) / 1.6)
		a.bot_hand_fwd = -n
		a.bot_hand_pos = canvas.canvas_to_world(p3, 0.04) + n * a.TIP
		a.bot_trigger = vr_t > 6.95
	elif vr_t < 9.2:
		step = "walk"
		a.bot_trigger = false
		a.bot_lstick = Vector2(0.0, 0.6 if vr_t < 8.8 else -0.6)
		a.bot_hand_pos = rest
	elif vr_t < 10.0:
		step = "touch UNDO"
		a.bot_hand_fwd = -n
		a.bot_hand_pos = canvas.undo_world() + n * 0.02 if vr_t > 9.6 else canvas.canvas_to_world(Vector2(0.4, 0.0), 0.3)
	elif vr_t < 11.0 and not has_meta("vr_cleared"):
		step = "touch CLEAR"
		a.bot_hand_fwd = -n
		a.bot_hand_pos = canvas.clear_world() + n * 0.02 if vr_t > 10.5 else canvas.canvas_to_world(Vector2(0.4, 0.2), 0.3)
		if vr_t > 10.8 and main.canvas.point_count == 0:
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
	seen_types[main.round_type] = true
	if st != last_state:
		if st == "reveal":
			rounds_done += 1
			var got := 0
			for g in main.active_guessers():
				if g.got:
					got += 1
			print("BOT %s: ROUND %d (%s, %s) COMPLETE - '%s' guessed by %d/%d, canvas %d strokes / %d points, gallery %d" % [mode,
				main.round_n, main.round_type, main.theme, main.reveal_word, got, main.active_guessers().size(),
				main.canvas.strokes.size(), main.canvas.point_count, main.room.pictures.size()])
			# Jump ahead so a short run sees every kind of round, the vote and the final scores:
			# default: 1 -> TEAM PAINT (3) -> vote; 4+ players: 1 -> SPEED (4) -> GOLDEN FINAL (5) -> vote;
			# host / fake VR: 1 -> TEAM PAINT (3) -> GOLDEN FINAL (5) -> vote.
			if mode != "client":
				var many := int(OS.get_environment("BOT_PLAYERS")) >= 4 if OS.has_environment("BOT_PLAYERS") else false
				var plan := {1: 2, 3: 4} if (mode == "host" or main.players[0].fake_vr) else ({1: 3} if many else {1: 2, 3: 5})
				if plan.has(main.round_n):
					main.round_n = int(plan[main.round_n])
		elif st == "vote":
			print("BOT %s: VOTE with %d pictures %s" % [mode, main.vote_count(), str(main.vote_words)])
		elif st == "over":
			games_done += 1
			print("BOT %s: GAME OVER seen (%s) awards: %s; gallery %d, rounds seen %s" % [mode, main._scoreboard(),
				str(main.get_meta("awards", "")).replace("\n", " | "), main.room.pictures.size(), str(seen_types.keys())])
		elif st == "intro" and last_state == "over":
			print("BOT %s: playing again" % mode)
		last_state = st


func _report(mode: String) -> void:
	var act: Array[String] = []
	for i in range(1, main.players.size()):
		var g = main.players[i]
		if g.active:
			act.append("P%d:%d%s%s%s%s" % [g.index + 1, g.score, "✓" if g.got else "", " lock" if g.lock_left > 0.0 else "",
				" s%d" % g.streak if g.streak > 0 else "", " v%d" % g.vote if g.vote >= 0 else ""])
	var views := 0
	var cell := Vector2.ZERO
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
			cell = p.get_meta("view").size
	print("BOT %s t=%.0f state=%s round=%d(%s) time=%.0f hint='%s' artist=%d strokes=%d live=%d chunks=%d points=%d (max %d) rev=%d opts=%s views=%d cell=%s rounds_done=%d games_done=%d [%s]" % [
		mode, t, main.state, main.round_n, main.round_type, main.time_left, main.hint_text, main.players[0].score,
		main.canvas.strokes.size(), main.canvas.lives.size(), main.canvas.chunks.size(), main.canvas.point_count, max_points, main.canvas.rev,
		str(main.options_for(1)), views, cell, rounds_done, games_done, ", ".join(act)])
