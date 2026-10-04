extends Node
## A TV player (players[1..6]): watches the easel in their own split-screen view and guesses what the
## artist is drawing by picking one of FOUR answers (their own shuffled set: one right, three decoys).
## D-pad / left stick (arrows, WASD on the TV machine) moves the highlight, A (Enter / Space) picks.
## A wrong pick locks you out for a moment and crosses that answer out; the host decides and scores.
## TEAM PAINT rounds: the TV players PAINT the word together (left stick / D-pad moves your brush ring,
## hold A or RT to paint) and the VR player guesses. The final VOTE: pick your favourite picture.
## X / Y / B (Q / E / R on the keyboard) cheer: a "YAY!" pops out of your critter on the easel.
## On the host, the TV machine's guessers are "remote": their picks arrive as "guess" actions and their
## team-paint brush as player state (pos = brush, yaw = 1 while painting).

const CHEERS: Array[String] = ["YAY!", "WOW!", "HA HA!"]
const BRUSH_SPEED := 0.65

var index := 1
var main
var remote := false
var ghost := false
var vr := false
var fake_vr := false
var active := false
var joy := -1
var key_set := 99  # 0: arrows + Enter (local P2), 1: arrows/WASD + Space/Enter (TV machine P2), 99: pad only
var pad_lost_t := -1.0
var color := Color.WHITE
var camera: Camera3D
var hud: Control
var hud_label: Label
var ui_scale := 1.0

var score := 0
var got := false
var lock_left := 0.0
var wrong_mask := 0
var cursor_i := 0
var pending_t := 0.0
var flash_t := 0.0
var flash_text := ""
var flash_col := Color.WHITE
var edges := {}
var stick_armed := true
var bot := false
var bot_think := 0.0
var bot_t := 0.0
var bot_cheer_t := 4.0
var idle_t := 0.0
var touched := false  # pressed anything this round (for the tips)

# Stats for the streaks and the end-of-game awards (host side; streak is mirrored).
var streak := 0
var best_streak := 0
var firsts := 0
var rights := 0
var wrongs := 0
var fastest := 999.0
var cheers := 0
var team_ink := 0
var cheer_cd := 0.0

# TEAM PAINT brush (canvas metres) and painting state.
var tv_cursor := Vector2.ZERO
var tv_down := false
var tv_cur_id := -1
var tv_last := Vector2.ZERO
var tv_smooth := Vector2.ZERO
var send_t := 0.0
# The VOTE.
var vote := -1  # confirmed (host's word)
var vote_cursor := 0

var hint_label: Label
var time_label: Label
var status_label: Label
var banner_label: Label
var streak_label: Label
var timer_bg: ColorRect
var timer_fill: ColorRect
var opt_root: Control
var opt_panels: Array[PanelContainer] = []
var opt_labels: Array[Label] = []
var big_panel: PanelContainer
var big_label: Label
var styles := {}


func set_active(on: bool) -> void:
	if on and not active:
		# Whatever is held right now (the A that joined us) must be let go before it does anything.
		edges = {"pick": true, "l": true, "r": true, "u": true, "d": true, "c0": true, "c1": true, "c2": true}
		stick_armed = false
		tv_cursor = Vector2(-0.45 + 0.18 * ((index - 1) % 6), -0.1 + 0.12 * ((index - 1) % 2))
	active = on


func is_local() -> bool:
	return not remote and not ghost


## Host: a TV machine player's team-paint brush.
func apply_remote_state(pos: Vector3, yaw_v: float, _pitch: float) -> void:
	tv_cursor = Vector2(pos.x, pos.y)
	tv_down = yaw_v > 0.5


func reset_round() -> void:
	got = false
	lock_left = 0.0
	wrong_mask = 0
	pending_t = 0.0
	cursor_i = 0
	idle_t = 0.0
	touched = false
	tv_down = false
	tv_cur_id = -1
	vote = -1
	bot_think = randf_range(2.5, 6.0)
	bot_t = 0.0


func reset_stats() -> void:
	streak = 0
	best_streak = 0
	firsts = 0
	rights = 0
	wrongs = 0
	fastest = 999.0
	cheers = 0
	team_ink = 0


# --- Input -----------------------------------------------------------------------------

func _edge(key: String, down: bool) -> bool:
	var was: bool = edges.get(key, false)
	edges[key] = down
	return down and not was


func _k(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


func action_pressed() -> bool:
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	if key_set == 1:
		return _k(KEY_SPACE)
	return false


func _poll_input(delta: float) -> void:
	var left := false
	var right := false
	var up := false
	var down := false
	var pick := false
	var paint := false
	var cheer: Array[bool] = [false, false, false]
	var analog := Vector2.ZERO
	if key_set == 0:
		left = _k(KEY_LEFT)
		right = _k(KEY_RIGHT)
		up = _k(KEY_UP)
		down = _k(KEY_DOWN)
		pick = _k(KEY_ENTER) or _k(KEY_KP_ENTER) or _k(KEY_SHIFT)
		cheer[0] = _k(KEY_PERIOD)
		cheer[1] = _k(KEY_SLASH)
	elif key_set == 1:
		left = _k(KEY_LEFT) or _k(KEY_A)
		right = _k(KEY_RIGHT) or _k(KEY_D)
		up = _k(KEY_UP) or _k(KEY_W)
		down = _k(KEY_DOWN) or _k(KEY_S)
		pick = _k(KEY_SPACE) or _k(KEY_ENTER) or _k(KEY_KP_ENTER)
		cheer[0] = _k(KEY_Q)
		cheer[1] = _k(KEY_E)
		cheer[2] = _k(KEY_R)
	if joy >= 0:
		left = left or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)
		right = right or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)
		up = up or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)
		down = down or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)
		pick = pick or Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
		paint = Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		cheer[0] = cheer[0] or Input.is_joy_button_pressed(joy, JOY_BUTTON_X)
		cheer[1] = cheer[1] or Input.is_joy_button_pressed(joy, JOY_BUTTON_Y)
		cheer[2] = cheer[2] or Input.is_joy_button_pressed(joy, JOY_BUTTON_B)
		analog = Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
	for k in 3:
		if _edge("c%d" % k, cheer[k]):
			do_cheer(k)
	var mode: String = main.guesser_mode()
	if mode == "paint":
		# Team paint: the stick / D-pad steer the brush ring, A or RT paints.
		var mv := Vector2((1.0 if right else 0.0) - (1.0 if left else 0.0), (1.0 if up else 0.0) - (1.0 if down else 0.0))
		if analog.length() > 0.2:
			mv += Vector2(analog.x, -analog.y)
		if mv.length() > 0.0:
			touched = true
		tv_cursor = main.canvas.clamp_point(tv_cursor + mv.limit_length(1.0) * BRUSH_SPEED * delta)
		tv_down = pick or paint
		edges["pick"] = pick
		for k in ["l", "r", "u", "d"]:
			edges[k] = true
		return
	tv_down = false
	if analog.length() < 0.3:
		stick_armed = true
	elif stick_armed and analog.length() > 0.6:
		stick_armed = false
		_nav(Vector2i(1 if analog.x > 0.0 else -1, 0) if absf(analog.x) > absf(analog.y) else Vector2i(0, 1 if analog.y > 0.0 else -1))
	if _edge("l", left):
		_nav(Vector2i(-1, 0))
	if _edge("r", right):
		_nav(Vector2i(1, 0))
	if _edge("u", up):
		_nav(Vector2i(0, -1))
	if _edge("d", down):
		_nav(Vector2i(0, 1))
	if _edge("pick", pick):
		confirm()


## Move the highlight: the 2x2 grid of answers, or the pictures in the vote.
func _nav(d: Vector2i) -> void:
	touched = true
	idle_t = 0.0
	if main.state == "vote":
		var n: int = main.vote_count()
		if n <= 0:
			return
		var cols := 3 if n > 4 else 2
		var step := d.x + d.y * cols
		vote_cursor = posmod(vote_cursor + step, n)
		main.sound("pick", -10.0, 1.0 + 0.06 * vote_cursor)
		return
	if main.state != "draw" or got:
		return
	var col := cursor_i % 2
	var row := cursor_i / 2
	if d.x != 0:
		col = 1 - col
	if d.y != 0:
		row = 1 - row
	cursor_i = row * 2 + col
	main.sound("pick", -10.0, 1.0 + 0.08 * cursor_i)


func select(i: int) -> void:
	cursor_i = clampi(i, 0, 3)


func confirm() -> void:
	touched = true
	idle_t = 0.0
	if main.state == "vote" and active:
		main.submit_vote(self, vote_cursor)
		return
	if main.state != "draw" or not active or main.round_type == "team":
		return
	var opts: Array = main.options_for(index)
	if opts.size() < 4 or got or pending_t > 0.0:
		return
	if lock_left > 0.0 or (wrong_mask >> cursor_i) & 1 == 1:
		main.sound("nope", -8.0)
		return
	pending_t = 1.0
	main.submit_guess(self, cursor_i)


func do_cheer(kind: int) -> void:
	if cheer_cd > 0.0 or not active:
		return
	cheer_cd = 0.7
	main.submit_cheer(self, kind)


func on_result(ok: bool, pts: int) -> void:
	pending_t = 0.0
	if ok:
		flash_text = "YOU GOT IT!  +%d" % pts
		flash_col = Color(0.4, 1.0, 0.5)
		flash_t = 2.5
		if joy >= 0:
			Input.start_joy_vibration(joy, 0.5, 0.8, 0.35)
	else:
		flash_text = "NOPE! Try another one"
		flash_col = Color(1.0, 0.45, 0.4)
		flash_t = 1.2
		if joy >= 0:
			Input.start_joy_vibration(joy, 0.8, 0.2, 0.2)


func flash(text: String, col: Color, t: float = 2.0) -> void:
	flash_text = text
	flash_col = col
	flash_t = t


## Bots: think for a moment, then pick an answer that isn't crossed out yet; paint doodles in TEAM
## PAINT, vote for a random picture and cheer now and then.
func _bot_play(delta: float) -> void:
	bot_t += delta
	bot_cheer_t -= delta
	if bot_cheer_t <= 0.0:
		bot_cheer_t = randf_range(5.0, 11.0)
		if main.state == "draw" or main.state == "reveal":
			do_cheer(randi() % 3)
	var mode: String = main.guesser_mode()
	if mode == "paint":
		var k := float(index) * 1.3
		var u := fmod(bot_t * 0.35 + k, 1.0)
		var c := Vector2(-0.35 + 0.14 * ((index - 1) % 6), 0.05 * ((index - 1) % 3) - 0.05)
		tv_cursor = main.canvas.clamp_point(c + Vector2(cos(u * TAU + k), sin(u * TAU * 2.0 + k)) * Vector2(0.18, 0.14))
		tv_down = fmod(bot_t, 3.0) < 2.4
		return
	tv_down = false
	if main.state == "vote":
		if vote < 0 and pending_t <= 0.0 and bot_t > 1.0 + index * 0.4:
			var n: int = main.vote_count()
			if n > 0:
				vote_cursor = randi() % n
				pending_t = 1.5
				confirm()
		return
	if main.state != "draw" or got or lock_left > 0.0 or pending_t > 0.0 or main.round_type == "team":
		return
	bot_think -= delta
	if bot_think > 0.0:
		return
	var free: Array[int] = []
	for i in 4:
		if (wrong_mask >> i) & 1 == 0:
			free.append(i)
	if free.is_empty():
		return
	select(free[randi() % free.size()])
	bot_think = randf_range(1.0, 2.5)
	confirm()


func _process(delta: float) -> void:
	pending_t = maxf(0.0, pending_t - delta)
	flash_t = maxf(0.0, flash_t - delta)
	cheer_cd = maxf(0.0, cheer_cd - delta)
	if main == null or not main.ready_to_play:
		return
	if not main.is_host_side():
		lock_left = maxf(0.0, lock_left - delta)  # the host's value arrives in snapshots too
	if active and is_local() and not main.get_tree().paused:
		if main.state == "draw":
			idle_t += delta
		if bot:
			_bot_play(delta)
		else:
			_poll_input(delta)
		# The TV machine tells the host where its team-paint brush is (30 Hz, unreliable).
		if not main.is_host_side() and main.guesser_mode() == "paint":
			send_t -= delta
			if send_t <= 0.0:
				send_t = 1.0 / 30.0
				main.net.send_state(Vector3(tv_cursor.x, tv_cursor.y, 0.0), 1.0 if tv_down else 0.0, 0.0, index)
	if hud != null:
		_update_hud()


# --- HUD -------------------------------------------------------------------------------

func _style(key: String, bg: Color, border: Color) -> StyleBoxFlat:
	if styles.has(key):
		return styles[key]
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(4)
	s.set_corner_radius_all(14)
	s.content_margin_left = 8
	s.content_margin_right = 8
	styles[key] = s
	return s


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func build_hud(root: Control) -> void:
	hud = root
	timer_bg = ColorRect.new()
	timer_bg.color = Color(0, 0, 0, 0.45)
	timer_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(timer_bg)
	timer_bg.anchor_right = 1.0
	timer_bg.offset_bottom = 8
	timer_fill = ColorRect.new()
	timer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_bg.add_child(timer_fill)
	timer_fill.anchor_bottom = 1.0
	var tag := ColorRect.new()
	tag.color = color
	tag.size = Vector2(16, 16)
	tag.position = Vector2(14, 22)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tag)
	hud_label = _label(26)
	hud_label.position = Vector2(38, 10)
	root.add_child(hud_label)
	streak_label = _label(26)
	streak_label.modulate = Color(1.0, 0.6, 0.2)
	root.add_child(streak_label)
	hint_label = _label(40)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_label)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint_label.offset_top = 8
	banner_label = _label(24)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner_label)
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_label.offset_top = 58
	time_label = _label(34)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(time_label)
	time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	time_label.offset_left = -220
	time_label.offset_right = -14
	time_label.offset_top = 10
	status_label = _label(30)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)
	status_label.anchor_left = 0.0
	status_label.anchor_right = 1.0
	status_label.anchor_top = 0.62
	status_label.anchor_bottom = 0.69
	opt_root = Control.new()
	opt_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(opt_root)
	opt_root.anchor_left = 0.03
	opt_root.anchor_right = 0.97
	opt_root.anchor_top = 0.70
	opt_root.anchor_bottom = 0.98
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	opt_root.add_child(grid)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 4:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(pc)
		var l := _label(34)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(l)
		opt_panels.append(pc)
		opt_labels.append(l)
	# One big panel for TEAM PAINT and the VOTE (same place as the answers).
	big_panel = PanelContainer.new()
	big_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(big_panel)
	big_panel.anchor_left = 0.03
	big_panel.anchor_right = 0.97
	big_panel.anchor_top = 0.72
	big_panel.anchor_bottom = 0.97
	big_label = _label(34)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big_panel.add_child(big_label)
	big_panel.visible = false


func _update_hud() -> void:
	var s := ui_scale
	hud_label.add_theme_font_size_override("font_size", int(26 * s))
	streak_label.add_theme_font_size_override("font_size", int(24 * s))
	hint_label.add_theme_font_size_override("font_size", int(42 * s))
	banner_label.add_theme_font_size_override("font_size", int(24 * s))
	banner_label.offset_top = 58.0 * s
	time_label.add_theme_font_size_override("font_size", int(34 * s))
	status_label.add_theme_font_size_override("font_size", int(30 * s))
	big_label.add_theme_font_size_override("font_size", int(32 * s))
	hud_label.text = main.hud_text(self)
	streak_label.position = Vector2(38, hud_label.position.y + hud_label.size.y)
	streak_label.text = ("STREAK x%d!" % streak) if streak >= 2 else ""
	var st: String = main.state
	var team: bool = main.round_type == "team"
	var frac: float = main.time_frac()
	timer_bg.visible = st == "draw" or st == "vote"
	timer_fill.anchor_right = clampf(frac, 0.0, 1.0)
	timer_fill.color = Color(0.35, 1.0, 0.45) if frac > 0.5 else (Color(1.0, 0.85, 0.2) if frac > 0.2 else Color(1.0, 0.3, 0.25))
	time_label.text = "%d" % int(ceilf(main.time_left)) if st == "draw" or st == "vote" else ""
	time_label.modulate = Color(1.0, 0.4, 0.35) if (st == "draw" and main.time_left <= 10.0) else Color(1, 1, 1)
	banner_label.text = main.banner_text() if active else ""
	if st == "draw" and team:
		hint_label.text = "PAINT:  %s" % str(main.team_word).to_upper() if main.team_word != "" else "PAINT IT TOGETHER!"
		hint_label.modulate = Color(1.0, 0.9, 0.5)
	elif st == "vote":
		hint_label.text = "VOTE FOR THE BEST PICTURE!"
		hint_label.modulate = Color(1.0, 0.85, 0.4)
	else:
		hint_label.text = main.hint_text if st == "draw" else ""
		hint_label.modulate = Color(1, 1, 1)
	var opts: Array = main.options_for(index)
	var show_opts: bool = (st == "draw" or st == "reveal") and not team and opts.size() == 4 and active
	opt_root.visible = show_opts
	big_panel.visible = active and ((st == "draw" and team) or st == "vote")
	if big_panel.visible:
		_update_big_panel(st)
	if flash_t > 0.0:
		status_label.text = flash_text
		status_label.modulate = flash_col
	elif not active:
		status_label.text = ""
	elif st == "draw" and team:
		status_label.text = "" if touched else "Move your brush ring - hold A to paint!"
		status_label.modulate = Color(1.0, 0.95, 0.6)
	elif st == "draw" and got:
		status_label.text = "YOU GOT IT!  Cheer the artist: X / Y / B"
		status_label.modulate = Color(0.5, 1.0, 0.6)
	elif st == "draw" and lock_left > 0.0:
		status_label.text = "Oops! Wait %d…" % int(ceilf(lock_left))
		status_label.modulate = Color(1.0, 0.6, 0.5)
	elif st == "draw" and idle_t > 7.0 and not touched:
		status_label.text = "Tip: D-pad to choose, then press A!"
		status_label.modulate = Color(1.0, 0.9, 0.4) if fmod(idle_t, 1.0) < 0.6 else Color(1, 1, 1)
	elif st == "draw":
		status_label.text = "What is it? Pick with A!"
		status_label.modulate = Color(1, 1, 1)
	else:
		status_label.text = ""
	if not show_opts:
		return
	var answer: String = main.reveal_word
	for i in 4:
		var l := opt_labels[i]
		l.add_theme_font_size_override("font_size", int(34 * s))
		var w: String = opts[i]
		l.text = w.to_upper()
		var crossed := (wrong_mask >> i) & 1 == 1
		var key := "idle"
		var bg := Color(0.12, 0.14, 0.26, 0.88)
		var border := Color(0.3, 0.35, 0.55)
		if st == "reveal" and answer != "":
			if w == answer:
				key = "answer"
				bg = Color(0.15, 0.5, 0.2, 0.92)
				border = Color(0.5, 1.0, 0.5)
		elif crossed:
			key = "crossed"
			bg = Color(0.3, 0.08, 0.08, 0.8)
			border = Color(0.6, 0.2, 0.2)
			l.text = "✗ " + w.to_upper()
		elif got:
			key = "done"
			bg = Color(0.1, 0.12, 0.18, 0.6)
			border = Color(0.25, 0.25, 0.3)
		if i == cursor_i and st == "draw" and not got:
			key += "_sel" + ("L" if lock_left > 0.0 else "")
			border = color.lerp(Color(1, 1, 1), 0.3) if lock_left <= 0.0 else Color(0.6, 0.4, 0.4)
			bg = bg.lerp(Color(color.r, color.g, color.b, 0.95), 0.35)
		l.modulate = Color(0.6, 0.55, 0.55) if crossed or (got and st == "draw") else Color(1, 1, 1)
		opt_panels[i].add_theme_stylebox_override("panel", _style(key + str(index), bg, border))


func _update_big_panel(st: String) -> void:
	var bg := Color(0.12, 0.14, 0.26, 0.88)
	if st == "vote":
		var n: int = main.vote_count()
		var t := "Pick your favourite:  <  #%d  >" % (vote_cursor + 1)
		if n > 0:
			t += "   (%s)" % str(main.vote_word(vote_cursor)).to_upper()
		t += "\nPress A to vote!" if vote < 0 else ("\nYou voted for #%d - A again to change" % (vote + 1))
		big_label.text = t
		bg = Color(0.25, 0.18, 0.05, 0.9)
	else:
		big_label.text = "TEAM PAINT!  Paint  %s  together!\nLeft stick / D-pad moves your ring · HOLD A (or RT) to paint\nThe VR player guesses with the balloons" % \
			str(main.team_word).to_upper()
		bg = Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.9)
	big_panel.add_theme_stylebox_override("panel", _style("big_%s_%d" % [st, index], bg, color.lerp(Color(1, 1, 1), 0.3)))
