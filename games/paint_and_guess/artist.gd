extends Node3D
## Player 1: the ARTIST (players[0]).
## VR (Steam Frame): hold the RIGHT trigger to paint with the glowing brush in your right hand. Paint
## by touching the easel with the brush tip, or from further away by pointing at it (a laser shows
## where the paint lands). A: next colour (or touch a paint pot on the tray). Touch the CLEAR bubble to
## wipe the canvas and the NEW WORD bubble (early in a round) for an easier word.
## Left stick: walk around · right stick left/right: turn · right stick up/down: easel height.
## The easel fits your height at the start and again when a shorter/taller (or sitting) kid takes over.
## Flat (split screen / non-VR host): mouse or WASD / left stick moves the brush, left mouse / Space /
## A / RT paints, C / right mouse / X / RB changes colour, Backspace / Y clears, N / B new word.
## fake_vr (bots): the VR code path driven by a virtual head and hand (bot_* fields).
## On the TV machine this is a ghost: a floating brush that follows the host's brush cursor.

const TIP := 0.11  # brush tip ahead of the controller
const TOUCH_FRONT := 0.12  # tip this close in front of the board paints directly
const TOUCH_BACK := 0.3  # ...or pushed this far through it
const LASER_RANGE := 3.5
const STAND_Z := 0.85
const BRUSH_W := 0.022

var index := 0
var main
var vr := false
var fake_vr := false
var ghost := false
var remote := false
var active := true
var joy := -1
var key_set := 0
var yaw := 0.0
var pitch := 0.0
var hand_l: XRController3D
var hand_r: XRController3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var origin: Node3D  # xr_origin or the fake one
var head: Node3D  # xr_camera or the fake one
var hand: Node3D  # hand_r or the fake one
var camera: Camera3D
var hud: Control
var hud_label: Label
var pad_lost_t := -1.0
var color := Color(1.0, 0.85, 0.55)
var score := 0

var color_idx := 1
var cursor := Vector2.ZERO
var cursor_on := false
var cur_id := -1
var last_pt := Vector2.ZERO
var smooth_pt := Vector2.ZERO
var mouse_d := Vector2.ZERO
var edges := {}
var touching := {}
var trig_was := false
var a_was := false
var turn_was := false
var fit_t := 0.8
var fitted := false
var fit_head := 0.0
var refit_t := 0.0

# Bots: flat
var bot := false
var bot_cursor := Vector2.ZERO
var bot_paint := false
# Bots: fake VR
var bot_hand_pos := Vector3(0.2, 1.2, 0.5)
var bot_hand_fwd := Vector3(0, 0, -1)
var bot_trigger := false
var bot_a := false
var bot_lstick := Vector2.ZERO

var brush: Node3D
var brush_tip: MeshInstance3D
var brush_label: Label3D
var laser: MeshInstance3D
var ghost_brush: Node3D
var net_cursor := Vector2.ZERO
var net_on := false


func set_active(on: bool) -> void:
	active = on


func is_local() -> bool:
	return not ghost and not remote


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func drawing() -> bool:
	return cur_id >= 0


# --- Setup ------------------------------------------------------------------------

func attach_xr(o: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = o
	xr_camera = cam
	hand_l = left
	hand_r = right
	origin = o
	head = cam
	hand = right
	cam.near = 0.02
	var mitten := MeshInstance3D.new()
	mitten.mesh = main.sphere_mesh(0.035)
	mitten.material_override = main.make_material(Color(1.0, 0.85, 0.55), 0.1)
	mitten.scale = Vector3(0.9, 0.7, 1.25)
	left.add_child(mitten)
	_build_brush(right)


## Bots: the VR code path with a virtual head and right hand.
func attach_fake_vr() -> void:
	fake_vr = true
	origin = Node3D.new()
	origin.name = "FakeOrigin"
	main.add_child(origin)
	head = Node3D.new()
	origin.add_child(head)
	head.position = Vector3(0.3, 1.35, 2.2)  # a short kid standing off to the side: the fit fixes it
	hand = Node3D.new()
	main.add_child(hand)
	_build_brush(hand)


func _build_brush(parent: Node3D) -> void:
	brush = Node3D.new()
	parent.add_child(brush)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.012
	cm.height = TIP - 0.01
	cm.radial_segments = 10
	cm.rings = 1
	body.mesh = cm
	body.rotation.x = -PI * 0.5
	body.position = Vector3(0, 0, -TIP * 0.5 + 0.005)
	body.material_override = main.make_material(Color(0.75, 0.5, 0.3), 0.0)
	brush.add_child(body)
	brush_tip = MeshInstance3D.new()
	brush_tip.mesh = main.sphere_mesh(0.016)
	brush_tip.position = Vector3(0, 0, -TIP)
	brush.add_child(brush_tip)
	# What to draw + time left, on the brush itself (always in view while painting). Secret: layer 2.
	brush_label = Label3D.new()
	brush_label.font_size = 40
	brush_label.outline_size = 14
	brush_label.pixel_size = 0.00065
	brush_label.position = Vector3(0, 0.045, 0.0)
	brush_label.rotation.x = -0.6
	brush_label.layers = 2
	brush.add_child(brush_label)
	laser = MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.002
	lm.bottom_radius = 0.002
	lm.height = 1.0
	lm.radial_segments = 6
	lm.rings = 1
	laser.mesh = lm
	main.add_child(laser)
	laser.visible = false


# --- Per frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
	elif vr or fake_vr:
		_vr_update(delta)
	else:
		_flat_update(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)


func _paint(ok: bool, p: Vector2, held: bool) -> void:
	cursor = p
	cursor_on = ok
	if not (held and ok and main.can_draw()):
		cur_id = -1
		return
	p = main.canvas.clamp_point(p)
	if cur_id < 0 or p.distance_to(last_pt) > 0.3:
		if main.canvas.is_full():
			cur_id = -1
			return
		cur_id = main.stroke_begin(color_idx, BRUSH_W, p)
		last_pt = p
		smooth_pt = p
		_buzz(0.3, 0.04)
		return
	smooth_pt = smooth_pt.lerp(p, 0.55)
	if smooth_pt.distance_to(last_pt) < 0.006:
		return
	if main.canvas.stroke_len(cur_id) >= main.canvas.MAX_STROKE_POINTS:
		cur_id = main.stroke_begin(color_idx, BRUSH_W, last_pt)
	main.stroke_add(cur_id, smooth_pt)
	last_pt = smooth_pt


func next_color(i: int = -1) -> void:
	color_idx = i if i >= 0 else (color_idx + 1) % main.canvas.COLORS.size()
	cur_id = -1
	main.sound("color", -6.0, 0.9 + 0.05 * color_idx)
	if color_idx < main.canvas.pots.size():
		main.canvas.poke(main.canvas.pots[color_idx], 0.4)
	_buzz(0.4, 0.05)


func _buzz(amp: float, dur: float) -> void:
	if vr:
		hand_r.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)
	elif joy >= 0 and not fake_vr:
		Input.start_joy_vibration(joy, amp * 0.5, amp * 0.3, dur)


# --- VR ------------------------------------------------------------------------------

func _trigger() -> bool:
	if fake_vr:
		return bot_trigger
	return hand_r.get_float("trigger") > 0.5


func _a() -> bool:
	if fake_vr:
		return bot_a
	return hand_r.is_button_pressed("ax_button")


func vr_trigger() -> bool:
	return (vr or fake_vr) and _trigger()


func _vr_update(delta: float) -> void:
	if vr and xr_origin.world_scale != 1.0:
		xr_origin.world_scale = 1.0
	if fake_vr:
		hand.global_position = bot_hand_pos
		if bot_hand_fwd.length() > 0.01:
			hand.look_at(bot_hand_pos + bot_hand_fwd, Vector3.UP if absf(bot_hand_fwd.normalized().y) < 0.95 else Vector3.FORWARD)
	_fit(delta)
	_move(delta)
	var canvas = main.canvas
	var trig := _trigger()
	var fwd := -hand.global_basis.z.normalized()
	var tip := hand.global_position + fwd * TIP
	var c: Vector3 = canvas.to_canvas(tip)
	var ok := false
	var p := Vector2.ZERO
	var use_laser := false
	var hit_w := Vector3.ZERO
	if c.z < TOUCH_FRONT and c.z > -TOUCH_BACK and canvas.inside(Vector2(c.x, c.y), 0.04):
		ok = true
		p = Vector2(c.x, c.y)
	else:
		var o: Vector3 = canvas.to_canvas(hand.global_position)
		var d: Vector3 = canvas.board_root.global_basis.inverse() * fwd
		if o.z > 0.0 and d.z < -0.05:
			var t := -o.z / d.z
			var hit := o + d * t
			if t < LASER_RANGE and canvas.inside(Vector2(hit.x, hit.y), 0.0):
				ok = true
				use_laser = true
				p = Vector2(hit.x, hit.y)
				hit_w = canvas.canvas_to_world(p)
	# Touch / point at the pots and bubbles (only when not painting, so brushing past is harmless).
	if not drawing():
		_buttons(tip, fwd, trig and not trig_was)
	_paint(ok, p, trig)
	trig_was = trig
	var a := _a()
	if a and not a_was:
		next_color()
	a_was = a
	var col: Color = canvas.COLORS[color_idx]
	brush_tip.material_override = main.flat_material(col)
	brush_tip.scale = Vector3.ONE * (1.35 if drawing() else 1.0)
	brush_label.text = main.brush_text()
	laser.visible = use_laser
	if use_laser:
		var from := hand.global_position + fwd * TIP
		var mid := (from + hit_w) * 0.5
		var seg_len := from.distance_to(hit_w)
		laser.global_transform = Transform3D(Basis.looking_at(hit_w - from, Vector3.UP if absf(fwd.y) < 0.95 else Vector3.FORWARD) \
			* Basis(Vector3.RIGHT, PI * 0.5), mid)
		laser.scale = Vector3(1.0, seg_len, 1.0)
		laser.material_override = main.flat_material(Color(col.r, col.g, col.b).lerp(Color(1, 1, 1), 0.3))
	yaw = head.global_rotation.y
	global_position = Vector3(head.global_position.x, 0.0, head.global_position.z)


func _buttons(tip: Vector3, fwd: Vector3, trig_edge: bool) -> void:
	var canvas = main.canvas
	var targets: Array = []
	for i in canvas.pots.size():
		targets.append(["pot%d" % i, canvas.pot_world(i), 0.06])
	targets.append(["clear", canvas.clear_world(), 0.11])
	targets.append(["skip", canvas.skip_world(), 0.11])
	var hp := hand.global_position
	for tgt in targets:
		var key: String = tgt[0]
		var pos: Vector3 = tgt[1]
		var r: float = tgt[2]
		var touch := tip.distance_to(pos) < r or hp.distance_to(pos) < r
		if touch and not touching.get(key, false):
			_press(key)
		touching[key] = touch
		if trig_edge and not touch:
			var to := pos - hp
			var along := to.dot(fwd)
			if along > 0.0 and along < LASER_RANGE and (to - fwd * along).length() < r * 0.9:
				_press(key)


func _press(key: String) -> void:
	if key.begins_with("pot"):
		next_color(int(key.substr(3)))
	elif key == "clear":
		main.canvas.poke(main.canvas.clear_bubble)
		main.artist_clear()
		_buzz(0.6, 0.1)
	elif key == "skip":
		main.canvas.poke(main.canvas.skip_bubble)
		main.artist_skip()
		_buzz(0.6, 0.1)


func _lstick() -> Vector2:
	if fake_vr:
		return bot_lstick
	return hand_l.get_vector2("primary")


func _rstick() -> Vector2:
	if fake_vr:
		return Vector2.ZERO
	return hand_r.get_vector2("primary")


## Walk with the left stick (in the direction the LEFT hand points, not the head), snap-turn and
## raise/lower the easel with the right stick.
func _move(delta: float) -> void:
	var s := _lstick()
	if s.length() > 0.2:
		var basis_src: Node3D = hand_l if vr else head
		var f := -basis_src.global_basis.z
		f.y = 0.0
		if f.length() < 0.05:
			f = -head.global_basis.z
			f.y = 0.0
		f = f.normalized()
		var right := Vector3(-f.z, 0.0, f.x)
		origin.global_position += (right * s.x + f * s.y) * 1.3 * delta
	var hp := head.global_position
	var fix := Vector3(clampf(hp.x, -3.0, 3.0) - hp.x, 0.0, clampf(hp.z, 0.3, 3.5) - hp.z)
	origin.global_position += fix
	var r := _rstick()
	var turn := absf(r.x) > 0.7
	if turn and not turn_was:
		var ang := -signf(r.x) * deg_to_rad(30.0)
		var pivot := head.global_position
		var rot := Basis(Vector3.UP, ang)
		origin.global_transform = Transform3D(rot * origin.global_basis, pivot + rot * (origin.global_position - pivot))
	turn_was = turn
	if absf(r.y) > 0.5 and absf(r.x) < 0.5:
		main.canvas.set_height(main.canvas.cy + signf(r.y) * 0.3 * delta)


## Fit the easel to the player a moment after starting (standing, sitting or a short kid), and again
## when the headset is clearly on a different head (height changed a lot for a few seconds).
func _fit(delta: float) -> void:
	var hp := head.global_position
	if not fitted:
		fit_t -= delta
		if fit_t <= 0.0 and head.position != Vector3.ZERO:
			_do_fit(true)
		return
	if absf(hp.y - fit_head) > 0.28:
		refit_t += delta
		if refit_t > 2.5:
			_do_fit(false)
	else:
		refit_t = 0.0


func _do_fit(first: bool) -> void:
	fitted = true
	refit_t = 0.0
	if first:
		# Face the easel (-Z) and stand a comfy arm's length in front of it.
		var hp := head.global_position
		var rot := Basis(Vector3.UP, -head.global_rotation.y)
		origin.global_transform = Transform3D(rot * origin.global_basis, hp + rot * (origin.global_position - hp))
		hp = head.global_position
		origin.global_position += Vector3(-hp.x, 0.0, STAND_Z - hp.z)
	var h := head.global_position.y
	fit_head = h
	main.canvas.set_height(h - 0.3)
	print("VR: fitted the easel to head height %.2f m (canvas centre %.2f m)" % [h, main.canvas.cy])


# --- Flat -----------------------------------------------------------------------------

func attach_camera(cam: Camera3D) -> void:
	camera = cam


func _input(event: InputEvent) -> void:
	if vr or fake_vr or ghost or key_set != 0:
		return
	var mm := event as InputEventMouseMotion
	if mm:
		mouse_d += mm.relative


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _edge(key: String, down: bool) -> bool:
	var was: bool = edges.get(key, false)
	edges[key] = down
	return down and not was


func _flat_update(delta: float) -> void:
	if bot:
		mouse_d = Vector2.ZERO
		_paint(true, bot_cursor, bot_paint)
		return
	var mv := Vector2.ZERO
	var held := false
	var col_btn := false
	var clr_btn := false
	var skip_btn := false
	if key_set == 0:
		mv += Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_W) - _key(KEY_S))
		held = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)
		col_btn = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(KEY_C)
		clr_btn = Input.is_physical_key_pressed(KEY_BACKSPACE)
		skip_btn = Input.is_physical_key_pressed(KEY_N)
	if joy >= 0:
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), -Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() > 0.15:
			mv += st
		held = held or Input.is_joy_button_pressed(joy, JOY_BUTTON_A) or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		col_btn = col_btn or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
		clr_btn = clr_btn or Input.is_joy_button_pressed(joy, JOY_BUTTON_Y)
		skip_btn = skip_btn or Input.is_joy_button_pressed(joy, JOY_BUTTON_B)
	var p := cursor + mv.limit_length(1.0) * 0.75 * delta + Vector2(mouse_d.x, -mouse_d.y) * 0.0012
	mouse_d = Vector2.ZERO
	p = main.canvas.clamp_point(p)
	_paint(true, p, held)
	if _edge("col", col_btn):
		next_color()
	if _edge("clr", clr_btn):
		main.artist_clear()
	if _edge("skip", skip_btn):
		main.artist_skip()


func action_pressed() -> bool:
	if vr or fake_vr:
		return _trigger() or _a()
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set == 0 and Input.is_physical_key_pressed(KEY_SPACE)


# --- TV machine ghost ---------------------------------------------------------------------

func _ghost_update(delta: float) -> void:
	var canvas = main.canvas
	if ghost_brush == null:
		ghost_brush = Node3D.new()
		main.add_child(ghost_brush)
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.02
		cm.height = 0.24
		cm.radial_segments = 10
		cm.rings = 1
		body.mesh = cm
		body.position = Vector3(0, 0.13, 0)
		body.material_override = main.make_material(Color(0.75, 0.5, 0.3), 0.0)
		ghost_brush.add_child(body)
		brush_tip = MeshInstance3D.new()
		brush_tip.mesh = main.sphere_mesh(0.022)
		ghost_brush.add_child(brush_tip)
	ghost_brush.visible = net_on
	if not net_on:
		return
	var target: Vector3 = canvas.canvas_to_world(net_cursor, 0.03)
	var k := 1.0 - exp(-20.0 * delta)
	ghost_brush.global_position = ghost_brush.global_position.lerp(target, k)
	ghost_brush.global_basis = canvas.board_root.global_basis * Basis(Vector3(0, 0, 1), -0.5) * Basis(Vector3(1, 0, 0), 0.5)
	brush_tip.material_override = main.flat_material(canvas.COLORS[color_idx])
