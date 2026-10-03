extends Node3D
## Player 1, the pilot at the control desk.
## VR (Steam Frame): touch buttons and switches with either hand (a glowing fingertip shows the touch
## point); squeeze the RIGHT trigger near a plug, the dial knob or the launch lever to grab it and move
## your hand. Left stick shuffles you round the desk, right stick up/down raises or lowers the desk.
## The desk sizes itself to your head height a moment after starting (sitting is fine).
## Split screen / non-VR host: a pointer. Mouse: click to press, hold and drag to grab.
## Controller: left stick moves the pointer, A / RT clicks and holds.
## On the TV machine this is a "ghost": a helmet and two mittens drawn from the host's snapshots.

const TIP := Vector3(0.0, -0.01, -0.07)  # fingertip, relative to the aim pose
const POINTER_SPEED := 750.0

var index := 0
var main
var vr := false
var ghost := false
var remote := false
var active := true
var yaw := 0.0
var pitch := 0.0
var hand_l: XRController3D
var hand_r: XRController3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var camera: Camera3D
var joy := -1
var cursor := Vector2(-1, -1)
var last_mouse := Vector2(-1, -1)
var pointer_pos := Vector3.ZERO
var pointer_held := false
var held_t := 0.0
var cursor_ball: MeshInstance3D
var bot_hand := {}  # tests: {pos: Vector3 (world), grip: bool} replaces the real hands
var recenter_t := 0.8
var recentered := false
var net_head := Transform3D()
var net_hand_r := Transform3D()
var net_hand_l := Transform3D()
var ghost_head: Node3D
var ghost_hands: Array = []


func _ready() -> void:
	add_to_group("players")


## Hands for the panel: id, world position, grip, and whether it's a screen pointer.
func panel_hands() -> Array:
	if not bot_hand.is_empty():
		return [{"id": "bot", "pos": bot_hand.pos, "grip": bot_hand.grip, "pointer": true}]
	if vr:
		return [{"id": "l", "pos": hand_l.global_transform * TIP, "grip": false, "pointer": false},
			{"id": "r", "pos": hand_r.global_transform * TIP, "grip": hand_r.get_float("trigger") > 0.6, "pointer": false}]
	if camera == null:
		return []
	return [{"id": "p", "pos": pointer_pos, "grip": pointer_held, "pointer": true}]


func haptic(hand_id: String, amp: float) -> void:
	if vr:
		var h: XRController3D = hand_l if hand_id == "l" else hand_r
		h.trigger_haptic_pulse("haptic", 0.0, amp, 0.06, 0.0)
	elif joy >= 0:
		Input.start_joy_vibration(joy, amp * 0.4, amp * 0.2, 0.06)


func vr_trigger_held() -> bool:
	return vr and hand_r.get_float("trigger") > 0.6


# --- VR ----------------------------------------------------------------------

func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	cam.cull_mask = 0xFFFFF & ~main.MANUAL_LAYER
	cam.near = 0.03
	for h in [left, right]:
		var mitten := MeshInstance3D.new()
		mitten.mesh = main.sphere_mesh(0.04)
		mitten.material_override = main.make_material(Color(1.0, 0.55, 0.25), 0.1)
		mitten.scale = Vector3(0.9, 0.7, 1.3)
		mitten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(mitten)
		var tip := MeshInstance3D.new()
		tip.mesh = main.sphere_mesh(0.012)
		tip.material_override = main.make_material(Color(0.5, 1.0, 1.0), 2.0)
		tip.position = TIP
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(tip)


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
	elif vr:
		_vr_update(delta)
	elif camera != null:
		_pointer_update(delta)


func _vr_update(delta: float) -> void:
	if not recentered:
		recenter_t -= delta
		if recenter_t <= 0.0 and xr_camera.position != Vector3.ZERO:
			_recenter()
	var s := hand_l.get_vector2("primary")
	if s.length() > 0.2:
		var b := Basis(Vector3.UP, xr_camera.global_rotation.y)
		xr_origin.global_position += b * Vector3(s.x, 0.0, -s.y) * 0.6 * delta
	var head := xr_camera.global_position
	var fix := Vector3(clampf(head.x, -0.9, 0.9) - head.x, 0.0, clampf(head.z, -0.05, 0.9) - head.z)
	xr_origin.global_position += fix
	var r := hand_r.get_vector2("primary")
	if absf(r.y) > 0.5:
		main.panel.set_top(main.panel.top + signf(r.y) * 0.25 * delta)
	head = xr_camera.global_position
	global_position = Vector3(head.x, 0.0, head.z)
	yaw = xr_camera.global_rotation.y


## Face the desk and fit its height to the pilot (standing or sitting).
func _recenter() -> void:
	recentered = true
	var head := xr_camera.global_position
	var rot := Basis(Vector3.UP, -xr_camera.global_rotation.y)
	xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
	head = xr_camera.global_position
	xr_origin.global_position += Vector3(-head.x, 0.0, 0.12 - head.z)
	main.panel.set_top(head.y - 0.58)
	print("VR: recentred at the desk, head %.2f m, desk %.2f m" % [head.y, main.panel.top])


# --- Pointer (split screen / non-VR host) --------------------------------------

func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = 0xFFFFF & ~main.MANUAL_LAYER
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 74.0
	var top: float = main.panel.top
	camera.position = Vector3(0, top + 0.95, 0.55)
	camera.look_at(Vector3(0, top - 0.05, -0.55))
	global_position = Vector3(0, 0, 0.3)
	cursor_ball = MeshInstance3D.new()
	cursor_ball.mesh = main.sphere_mesh(0.016)
	cursor_ball.material_override = main.make_material(Color(0.5, 1.0, 1.0), 2.5)
	cursor_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(cursor_ball)
	main.set_layers(cursor_ball, main.PANEL_LAYER)


func _pointer_update(delta: float) -> void:
	var vp := camera.get_viewport()
	var vsize := Vector2(vp.get_visible_rect().size)
	if cursor.x < 0.0:
		cursor = vsize * Vector2(0.5, 0.55)
	var view: Control = get_meta("view") if has_meta("view") else null
	var mouse_in := false
	if view != null and view.size.x > 0.0:
		var m := view.get_local_mouse_position()
		mouse_in = Rect2(Vector2.ZERO, view.size).has_point(m)
		m = m * vsize / view.size
		if mouse_in and m.distance_to(last_mouse) > 0.5:
			cursor = m
		last_mouse = m
	if joy >= 0:
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() > 0.15:
			cursor += st * st.length() * POINTER_SPEED * delta
	cursor = cursor.clamp(Vector2.ZERO, vsize)
	var held := mouse_in and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not get_tree().paused
	if joy >= 0:
		held = held or Input.is_joy_button_pressed(joy, JOY_BUTTON_A) or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	held_t = held_t + delta if held else 0.0
	pointer_held = held
	var surface: Node3D = main.panel.surface
	var n := surface.global_basis.z.normalized()
	var plane := Plane(n, surface.global_position)
	var hit = plane.intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	if hit != null:
		var local: Vector3 = surface.global_transform.affine_inverse() * (hit as Vector3)
		# A quick click pokes down onto the buttons; holding lifts the finger so dragging doesn't press.
		local.z = 0.0 if held and held_t < 0.25 else 0.1
		pointer_pos = surface.global_transform * local
	if cursor_ball:
		cursor_ball.global_position = pointer_pos
		cursor_ball.scale = Vector3.ONE * (0.7 if held else 1.0)
	yaw = camera.global_rotation.y
	pitch = camera.global_rotation.x


# --- Networked co-op ---------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if camera:
		return camera.global_transform
	return Transform3D(Basis(), Vector3(0, 1.6, 0.2))


func hand_r_transform() -> Transform3D:
	if vr:
		return hand_r.global_transform
	if not bot_hand.is_empty():
		return Transform3D(Basis(), bot_hand.pos)
	return Transform3D(Basis(), pointer_pos) if camera else Transform3D()


func hand_l_transform() -> Transform3D:
	return hand_l.global_transform if vr else Transform3D()


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func set_active(on: bool) -> void:
	active = on


## Client: [pos, yaw, pitch, active, head, right hand, left hand].
func apply_net_state(st: Array) -> void:
	if st.size() > 6:
		net_head = st[4]
		net_hand_r = st[5]
		net_hand_l = st[6]


## TV machine: a friendly helmeted pilot and two orange mittens at the desk.
func _ghost_update(delta: float) -> void:
	if ghost_head == null:
		ghost_head = Node3D.new()
		main.add_child(ghost_head)
		var helmet := MeshInstance3D.new()
		helmet.mesh = main.sphere_mesh(0.17)
		helmet.material_override = main.make_material(Color(0.95, 0.95, 1.0), 0.0)
		ghost_head.add_child(helmet)
		var visor := MeshInstance3D.new()
		visor.mesh = main.sphere_mesh(0.12)
		visor.material_override = main.make_material(Color(0.3, 0.6, 0.95), 0.6)
		visor.scale = Vector3(1.0, 0.75, 0.6)
		visor.position = Vector3(0, 0, -0.1)
		ghost_head.add_child(visor)
		var suit := MeshInstance3D.new()
		suit.mesh = main.capsule_mesh(0.28, 1.0)
		suit.material_override = main.make_material(Color(1.0, 0.55, 0.25), 0.0)
		suit.name = "Suit"
		main.add_child(suit)
		ghost_head.set_meta("suit", suit)
		for i in 2:
			var h := MeshInstance3D.new()
			h.mesh = main.sphere_mesh(0.045)
			h.material_override = suit.material_override
			main.add_child(h)
			ghost_hands.append(h)
	if net_head == Transform3D():
		return
	var k := 1.0 - exp(-20.0 * delta)
	ghost_head.global_transform = ghost_head.global_transform.interpolate_with(net_head.orthonormalized(), k)
	var suit: MeshInstance3D = ghost_head.get_meta("suit")
	var hp := ghost_head.global_position
	suit.global_position = Vector3(hp.x, maxf(0.5, hp.y - 0.75), hp.z)
	suit.scale = Vector3(1, clampf((hp.y - 0.1) / 1.5, 0.4, 1.2), 1)
	var hands: Array = [net_hand_l, net_hand_r]
	for i in 2:
		var h: MeshInstance3D = ghost_hands[i]
		var tr: Transform3D = hands[i]
		h.visible = tr != Transform3D()
		if h.visible:
			h.global_position = h.global_position.lerp(tr.origin, k)
