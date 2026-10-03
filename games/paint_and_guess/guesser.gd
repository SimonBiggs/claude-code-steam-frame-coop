extends Node
## A TV player (players[1..6]): watches the easel in their own split-screen view and guesses what the
## artist is drawing by picking one of FOUR answers (their own shuffled set: one right, three decoys).
## D-pad / left stick (arrows, WASD on the TV machine) moves the highlight, A (Enter / Space) picks.
## A wrong pick locks you out for a moment and crosses that answer out; the host decides and scores.
## On the host, the TV machine's guessers are "remote": their picks arrive as "guess" actions.

var index := 1
var main
var remote := false
var ghost := false
var vr := false
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

var hint_label: Label
var time_label: Label
var status_label: Label
var opt_root: Control
var opt_panels: Array[PanelContainer] = []
var opt_labels: Array[Label] = []
var styles := {}


func set_active(on: bool) -> void:
	active = on


func is_local() -> bool:
	return not remote and not ghost


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func reset_round() -> void:
	got = false
	lock_left = 0.0
	wrong_mask = 0
	pending_t = 0.0
	cursor_i = 0
	bot_think = randf_range(2.5, 6.0)


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


func _poll_input() -> void:
	var left := false
	var right := false
	var up := false
	var down := false
	var pick := false
	if key_set == 0:
		left = _k(KEY_LEFT)
		right = _k(KEY_RIGHT)
		up = _k(KEY_UP)
		down = _k(KEY_DOWN)
		pick = _k(KEY_ENTER) or _k(KEY_KP_ENTER) or _k(KEY_SHIFT)
	elif key_set == 1:
		left = _k(KEY_LEFT) or _k(KEY_A)
		right = _k(KEY_RIGHT) or _k(KEY_D)
		up = _k(KEY_UP) or _k(KEY_W)
		down = _k(KEY_DOWN) or _k(KEY_S)
		pick = _k(KEY_SPACE) or _k(KEY_ENTER) or _k(KEY_KP_ENTER)
	if joy >= 0:
		left = left or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)
		right = right or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)
		up = up or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)
		down = down or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)
		pick = pick or Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() < 0.3:
			stick_armed = true
		elif stick_armed and st.length() > 0.6:
			stick_armed = false
			if absf(st.x) > absf(st.y):
				right = right or st.x > 0.0
				left = left or st.x < 0.0
			else:
				down = down or st.y > 0.0
				up = up or st.y < 0.0
			# Sticks are not edge-tracked below: move once now.
			_nav(Vector2i(1 if st.x > 0.0 else -1, 0) if absf(st.x) > absf(st.y) else Vector2i(0, 1 if st.y > 0.0 else -1))
			left = false
			right = false
			up = false
			down = false
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


## Move the highlight around the 2x2 grid of answers.
func _nav(d: Vector2i) -> void:
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
	if main.state != "draw" or not active:
		return
	var opts: Array = main.options_for(index)
	if opts.size() < 4 or got or pending_t > 0.0:
		return
	if lock_left > 0.0 or (wrong_mask >> cursor_i) & 1 == 1:
		main.sound("nope", -8.0)
		return
	pending_t = 1.0
	main.submit_guess(self, cursor_i)


func on_result(ok: bool, pts: int) -> void:
	pending_t = 0.0
	if ok:
		flash_text = "YOU GOT IT!  +%d" % pts
		flash_col = Color(0.4, 1.0, 0.5)
		flash_t = 2.5
		if joy >= 0:
			Input.start_joy_vibration(joy, 0.5, 0.8, 0.35)
	else:
		flash_text = "NOPE!"
		flash_col = Color(1.0, 0.45, 0.4)
		flash_t = 1.2
		if joy >= 0:
			Input.start_joy_vibration(joy, 0.8, 0.2, 0.2)


## Bots: think for a moment, then pick an answer that isn't crossed out yet.
func _bot_play(delta: float) -> void:
	if main.state != "draw" or got or lock_left > 0.0 or pending_t > 0.0:
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
	if main == null or not main.ready_to_play:
		return
	if not main.is_host_side():
		lock_left = maxf(0.0, lock_left - delta)  # the host's value arrives in snapshots too
	if active and is_local() and not main.get_tree().paused:
		if bot:
			_bot_play(delta)
		else:
			_poll_input()
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
	var tag := ColorRect.new()
	tag.color = color
	tag.size = Vector2(16, 16)
	tag.position = Vector2(14, 20)
	root.add_child(tag)
	hud_label = _label(26)
	hud_label.position = Vector2(38, 8)
	root.add_child(hud_label)
	hint_label = _label(40)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_label)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint_label.offset_top = 4
	time_label = _label(34)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(time_label)
	time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	time_label.offset_left = -220
	time_label.offset_right = -14
	time_label.offset_top = 8
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


func _update_hud() -> void:
	var s := ui_scale
	hud_label.add_theme_font_size_override("font_size", int(26 * s))
	hint_label.add_theme_font_size_override("font_size", int(42 * s))
	time_label.add_theme_font_size_override("font_size", int(34 * s))
	status_label.add_theme_font_size_override("font_size", int(30 * s))
	hud_label.text = main.hud_text(self)
	var st: String = main.state
	time_label.text = "%d" % int(ceilf(main.time_left)) if st == "draw" else ""
	time_label.modulate = Color(1.0, 0.4, 0.35) if st == "draw" and main.time_left <= 10.0 else Color(1, 1, 1)
	hint_label.text = main.hint_text if st == "draw" else ""
	var opts: Array = main.options_for(index)
	var show_opts := (st == "draw" or st == "reveal") and opts.size() == 4 and active
	opt_root.visible = show_opts
	if flash_t > 0.0:
		status_label.text = flash_text
		status_label.modulate = flash_col
	elif not active:
		status_label.text = ""
	elif st == "draw" and got:
		status_label.text = "YOU GOT IT! Watch the others…"
		status_label.modulate = Color(0.5, 1.0, 0.6)
	elif st == "draw" and lock_left > 0.0:
		status_label.text = "Oops! Wait %d…" % int(ceilf(lock_left))
		status_label.modulate = Color(1.0, 0.6, 0.5)
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
