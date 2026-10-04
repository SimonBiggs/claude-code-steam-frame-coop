extends Node3D
## Player 1: the giant who tilts the maze.
## VR (Steam Frame): squeeze the RIGHT trigger near either side handle to grab the board, then move your
## hand: up/down tilts it sideways, push/pull tilts it away/towards you. Rest your LEFT hand on the
## other handle while the right one holds to steer with both hands. Left stick: tilt directly.
## A: level the board. Right stick up/down: raise or lower the table. The table fits your height.
## Flat (split screen / non-VR host): WASD or the left stick tilts, mouse nudges, Space / A levels it.
## On the TV machine this is a ghost: a big friendly face and two hands drawn from the host's snapshots.

const GRAB_DIST := 0.13
const HAND_GAIN := 8.0  # tilt units per metre of hand movement (0.12 m = full tilt)

var index := 0
var main
var vr := false
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
var camera: Camera3D
var hud: Control
var hud_label: Label
var pad_lost_t := -1.0
var color := Color(1.0, 0.85, 0.55)
var home := false
var falling := false
var lp := Vector3.ZERO
var v := Vector2.ZERO

var want_tilt := Vector2.ZERO
var bot_tilt := Vector2.ZERO
var bot := false
var mouse_tilt := Vector2.ZERO
var grabbing := false
var grab_side := 1
var grab_r := Vector3.ZERO
var grab_l := Vector3.ZERO
var grab_tilt := Vector2.ZERO
var left_on := false
var trig_was := false
var a_was := false
var fit_t := 0.8
var fitted := false
var fit_head := 0.0
var refit_t := 0.0
var mittens: Array[MeshInstance3D] = []
var fake_trigger := -1.0  # bots (BOT_VR): >= 0 replaces the real right trigger

var net_head := Transform3D()
var net_hand_r := Transform3D()
var net_hand_l := Transform3D()
var ghost_head: Node3D
var ghost_hands: Array[MeshInstance3D] = []


func set_active(on: bool) -> void:
	active = on


func is_local() -> bool:
	return not ghost and not remote


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


# --- VR ----------------------------------------------------------------------------

func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	cam.near = 0.02
	for h in [left, right]:
		var mitten := MeshInstance3D.new()
		mitten.mesh = main.sphere_mesh(0.035)
		mitten.material_override = main.make_material(Color(1.0, 0.85, 0.55), 0.1)
		mitten.scale = Vector3(0.9, 0.7, 1.25)
		mitten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var hh: XRController3D = h
		hh.add_child(mitten)
		mittens.append(mitten)


func vr_trigger() -> bool:
	if fake_trigger >= 0.0:
		return vr and fake_trigger > 0.6
	return vr and hand_r.get_float("trigger") > 0.6


func vr_a() -> bool:
	return vr and hand_r.is_button_pressed("ax_button")


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
	elif vr:
		_vr_update(delta)
	else:
		_flat_update(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)


func _vr_update(delta: float) -> void:
	if xr_origin.world_scale != 1.0:
		xr_origin.world_scale = 1.0
	_fit(delta)
	var board: Node3D = main.board
	var trig := vr_trigger()
	var rp := hand_r.global_position
	var lpos := hand_l.global_position
	var near_side := -1
	for i in 2:
		var hw: Vector3 = board.handle_world(i)
		if rp.distance_to(hw) < GRAB_DIST:
			near_side = i
	if trig and not trig_was and near_side >= 0 and main.state != "over":
		grabbing = true
		grab_side = near_side
		grab_r = rp
		grab_l = lpos
		grab_tilt = want_tilt
		left_on = lpos.distance_to(board.handle_world(1 - near_side)) < GRAB_DIST * 1.4
		hand_r.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.08, 0.0)
		main.sound("grab", -8.0)
	if not trig:
		grabbing = false
	trig_was = trig
	if grabbing:
		if not left_on and lpos.distance_to(board.handle_world(1 - grab_side)) < GRAB_DIST:
			left_on = true  # left hand joined in (no button needed)
			grab_r = rp
			grab_l = lpos
			grab_tilt = want_tilt
		var dr := rp - grab_r
		var side := -1.0 if grab_side == 0 else 1.0
		var t := grab_tilt
		if left_on:
			var dl := lpos - grab_l
			# Right hand on the right handle: raising it pushes marbles left (and vice versa).
			var dy_right := dr.y if grab_side == 1 else dl.y
			var dy_left := dl.y if grab_side == 1 else dr.y
			t.x = grab_tilt.x + (dy_left - dy_right) * 0.5 * HAND_GAIN
			t.y = grab_tilt.y + (dr.z + dl.z) * 0.5 * HAND_GAIN
		else:
			t.x = grab_tilt.x - side * dr.y * HAND_GAIN
			t.y = grab_tilt.y + dr.z * HAND_GAIN
		want_tilt = t.limit_length(1.0)
	var s := hand_l.get_vector2("primary")
	if s.length() > 0.15:
		want_tilt = Vector2(s.x, -s.y).limit_length(1.0)
		grab_tilt = want_tilt
		grab_r = rp
		grab_l = lpos
	var a := vr_a()
	if a and not a_was and main.state == "play":
		want_tilt = Vector2.ZERO
		grab_tilt = Vector2.ZERO
		grab_r = rp
		grab_l = lpos
		main.sound("grab", -6.0, 0.7)
	a_was = a
	var r := hand_r.get_vector2("primary")
	if absf(r.y) > 0.5:
		main.set_board_height(main.board_y + signf(r.y) * 0.25 * delta)
	for i in 2:
		board.set_handle_glow(i, (grabbing and (i == grab_side or left_on)) or near_side == i)
	var head := xr_camera.global_position
	global_position = Vector3(head.x, 0.0, head.z)
	yaw = xr_camera.global_rotation.y


## Fit the table to the player a moment after starting (standing, sitting or a short kid), and again
## when the headset is clearly on a different head (height changed a lot for a few seconds).
func _fit(delta: float) -> void:
	var head := xr_camera.global_position
	if not fitted:
		fit_t -= delta
		if fit_t <= 0.0 and xr_camera.position != Vector3.ZERO:
			_do_fit()
		return
	if absf(head.y - fit_head) > 0.28:
		refit_t += delta
		if refit_t > 2.5:
			_do_fit()
	else:
		refit_t = 0.0


func _do_fit() -> void:
	fitted = true
	refit_t = 0.0
	var head := xr_camera.global_position
	# Face the board (-Z) and stand just behind its near edge.
	var rot := Basis(Vector3.UP, -xr_camera.global_rotation.y)
	xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
	head = xr_camera.global_position
	xr_origin.global_position += Vector3(-head.x, 0.0, 0.66 - head.z)
	fit_head = head.y
	main.set_board_height(clampf(head.y - 0.62, 0.4, 1.3))
	print("VR: fitted the table to head height %.2f m (table %.2f m)" % [head.y, main.board_y])


# --- Flat --------------------------------------------------------------------------

func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 62.0
	_place_camera()


func _place_camera() -> void:
	var by: float = main.board_y
	camera.position = Vector3(0.0, by + 1.0, 0.95)
	camera.look_at(Vector3(0.0, by - 0.05, -0.08), Vector3.UP)


func _input(event: InputEvent) -> void:
	if vr or ghost or camera == null:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and key_set == 0:
		mouse_tilt = (mouse_tilt + mm.relative * 0.004).limit_length(1.0)


func _flat_update(delta: float) -> void:
	if camera != null:
		_place_camera()
	if bot:
		want_tilt = bot_tilt.limit_length(1.0)
		return
	var k := Vector2.ZERO
	if key_set == 0:
		k = Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
		if not main.has_local_marble_keys():
			k += Vector2(_key(KEY_RIGHT) - _key(KEY_LEFT), _key(KEY_DOWN) - _key(KEY_UP))
	var level := key_set == 0 and Input.is_physical_key_pressed(KEY_SPACE)
	if joy >= 0:
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() > 0.15:
			k += st
		level = level or Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
	if level:
		mouse_tilt = Vector2.ZERO
	mouse_tilt = mouse_tilt.move_toward(Vector2.ZERO, 0.15 * delta)
	want_tilt = (k.limit_length(1.0) + mouse_tilt).limit_length(1.0)
	if level:
		want_tilt = Vector2.ZERO


func _key(kk: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(kk) else 0.0


func action_pressed() -> bool:
	if vr:
		return vr_trigger() or vr_a()
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set == 0 and Input.is_physical_key_pressed(KEY_SPACE)


# --- Networked co-op -----------------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if camera != null:
		return camera.global_transform
	return Transform3D(Basis(), Vector3(0, 1.6, 0.66))


func hand_r_transform() -> Transform3D:
	return hand_r.global_transform if vr else Transform3D()


func hand_l_transform() -> Transform3D:
	return hand_l.global_transform if vr else Transform3D()


## TV machine: a big friendly face looming over the board, plus two hands.
func _ghost_update(delta: float) -> void:
	if ghost_head == null:
		ghost_head = Node3D.new()
		main.add_child(ghost_head)
		var face := MeshInstance3D.new()
		face.mesh = main.sphere_mesh(0.13)
		face.material_override = main.make_material(Color(1.0, 0.8, 0.6), 0.0)
		ghost_head.add_child(face)
		for s in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = main.sphere_mesh(0.025)
			eye.material_override = main.make_material(Color(0.1, 0.1, 0.15), 0.0)
			eye.position = Vector3(s * 0.045, 0.03, -0.115)
			ghost_head.add_child(eye)
		var visor := MeshInstance3D.new()
		visor.mesh = main.box_mesh(Vector3(0.2, 0.06, 0.05))
		visor.material_override = main.make_material(Color(0.25, 0.25, 0.3), 0.0)
		visor.position = Vector3(0, 0.08, -0.09)
		ghost_head.add_child(visor)
		for i in 2:
			var h := MeshInstance3D.new()
			h.mesh = main.sphere_mesh(0.045)
			h.material_override = face.material_override
			h.scale = Vector3(0.9, 0.7, 1.25)
			main.add_child(h)
			ghost_hands.append(h)
	ghost_head.visible = net_head != Transform3D()
	if not ghost_head.visible:
		return
	var k := 1.0 - exp(-15.0 * delta)
	ghost_head.global_transform = ghost_head.global_transform.interpolate_with(net_head.orthonormalized(), k)
	var hands: Array[Transform3D] = [net_hand_l, net_hand_r]
	for i in 2:
		var h := ghost_hands[i]
		var tr := hands[i]
		h.visible = tr != Transform3D()
		if h.visible:
			h.global_position = h.global_position.lerp(tr.origin, k)
