extends Node3D
## Player 1: the GARDENER at the big raised bed.
## VR (Steam Frame; only the sticks, RIGHT trigger, A and hand positions reach the game):
##   XROrigin3D.world_scale = 4 makes the bed a waist-high diorama. RIGHT trigger near the seed tray
##   picks a seed: let go over the soil to plant it (you can toss it too). Trigger on the watering can
##   picks it up: point your hand DOWN to pour. Trigger on a ripe fruit picks it into the basket.
##   Pests: flick them with either hand, or point at one and pull the trigger.
##   Left stick: shuffle round the bed. Right stick: left/right snap turn, up/down raise or lower the bed.
##   A: re-fit the bed to you. The bed also fits itself to your height at the start (and when the
##   headset is handed to someone taller or shorter).
## Flat fallback (split screen / no headset): a glove moved by the mouse (or the second controller's
##   left stick); hold left click (or RT / A) to grab, drag, let go. Holding the can pours.
## TV: a ghost of the gardener (big friendly head in a straw hat + gloves) from the host's snapshots.

const W := preload("res://games/bee_garden/world.gd")

const GRAB_OFFSET := Vector3(0.0, -0.05, -0.2)   # grab point in hand space (world units)
const VR_REACH := 0.55
const FLAT_REACH := 0.7
const HEAD_ABOVE_SOIL := 0.62   # metres between the eyes and the soil
const EYE_Z := 0.95             # metres from the bed centre to the eyes
const FLAT_CAM_POS := Vector3(-0.6, 8.2, 8.8)
const FLICK_SPEED := 5.0        # world units / s (1.25 m/s)
const POUR_DIR := Vector3(0.0, 0.54, -0.84)  # spout direction in can space

var main
var index := 0
var color := Color(0.4, 0.75, 0.35)
var vr := false
var flat := false
var ghost := false
var remote := false
var active := true
var joy := -1
var mouse_on := false

var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var camera: Camera3D
var head: Node3D
var hands: Array = []
var can: Node3D
var stream: CPUParticles3D
var calibrated := false
var calib_t := 0.0
var snap_ready := true
var a_was := false
var flat_cursor := Vector3(0.0, 0.0, 0.8)
var mouse_delta := Vector2.ZERO
var pour_snd_t := 0.0
var bot := false
var bot_target := Vector3.ZERO
var bot_grip := false
# TV ghost state
var net_head := Transform3D()
var net_hands: Array = []
var net_held: Array = []
var net_pour: Array = []


class Hand:
	var root: Node3D
	var ctrl: XRController3D
	var right := true
	var xf := Transform3D()
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var hist: Array = []
	var gripping := false
	var held := ""        # "", "seed" or "can"
	var seed_kind := 0
	var seed_node: MeshInstance3D
	var pour := false


func body_layer() -> int:
	return 2  # the gardener's own head: hidden from the gardener's camera


func _ready() -> void:
	add_to_group("gardener")
	process_priority = 10  # after the XR controllers have their new poses
	can = W.make_can()
	main.add_child(can)
	stream = CPUParticles3D.new()
	stream.amount = 40
	stream.lifetime = 0.55
	stream.local_coords = false
	stream.direction = Vector3(0, 0, -1)
	stream.spread = 8.0
	stream.initial_velocity_min = 1.2
	stream.initial_velocity_max = 1.6
	stream.gravity = Vector3(0, -9.0, 0)
	stream.scale_amount_min = 0.6
	stream.scale_amount_max = 1.0
	var dm := W.sphere(0.035, 6)
	var wm := W.mat(Color(0.5, 0.75, 1.0), 0.6)
	dm.material = wm
	stream.mesh = dm
	stream.emitting = false
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(stream)


func setup_vr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	origin.world_scale = W.S
	cam.near = 0.1
	cam.far = 600.0
	cam.cull_mask = 0xFFFFF & ~body_layer() & ~W.TV_LAYER
	for c in [left, right]:
		var h := _make_hand(c == right)
		h.ctrl = c
		h.root.reparent(c, false)  # drawn with the freshest controller pose
		h.root.transform = Transform3D()
		hands.append(h)
	origin.global_position = Vector3(0.0, HEAD_ABOVE_SOIL * W.S - 1.2 * W.S, EYE_Z * W.S)


func setup_flat(cam: Camera3D, use_mouse: bool) -> void:
	flat = true
	mouse_on = use_mouse
	camera = cam
	camera.fov = 68.0
	camera.near = 0.1
	camera.far = 600.0
	camera.cull_mask = 0xFFFFF & ~body_layer() & ~W.TV_LAYER
	camera.global_position = FLAT_CAM_POS
	camera.look_at(Vector3(-0.6, -0.4, 0.2), Vector3.UP)
	hands.append(_make_hand(true))
	_ensure_head()


func setup_ghost() -> void:
	ghost = true
	for i in 2:
		hands.append(_make_hand(i == 1))
	_ensure_head()


# --- Visuals -----------------------------------------------------------------

func _make_hand(right: bool) -> Hand:
	var h := Hand.new()
	h.right = right
	h.root = Node3D.new()
	main.add_child(h.root)
	var glove := W.cmat(Color(0.95, 0.55, 0.3) if right else Color(0.95, 0.65, 0.35))
	W.mesh_node(h.root, W.sphere(0.16, 12), glove, Vector3(0, 0, 0.05), Vector3(1.0, 0.6, 1.3))
	for i in 3:
		var f := W.mesh_node(h.root, W.cyl(0.04, 0.045, 0.18, 6), glove, Vector3(-0.07 + i * 0.07, 0.0, -0.17))
		f.rotation.x = PI / 2.0
	var thumb := W.mesh_node(h.root, W.cyl(0.04, 0.045, 0.14, 6), glove, Vector3(0.14 if not right else -0.14, 0.0, -0.02))
	thumb.rotation = Vector3(PI / 2.0, 0.0, 0.6 if right else -0.6)
	var cuff := W.mesh_node(h.root, W.cyl(0.13, 0.15, 0.12, 10), W.cmat(Color(0.35, 0.55, 0.8)), Vector3(0, 0, 0.24))
	cuff.rotation.x = PI / 2.0
	h.seed_node = W.mesh_node(main, W.sphere(0.07, 8), W.cmat(Color(0.45, 0.3, 0.15)), Vector3.ZERO, Vector3(1.0, 0.8, 1.3))
	h.seed_node.visible = false
	return h


func _ensure_head() -> void:
	if head != null:
		return
	head = Node3D.new()
	main.add_child(head)
	W.mesh_node(head, W.sphere(0.5, 16), W.cmat(Color(1.0, 0.8, 0.65)), Vector3.ZERO)
	for side in [-1.0, 1.0]:
		W.mesh_node(head, W.sphere(0.1, 8), W.cmat(Color(0.15, 0.1, 0.08)), Vector3(side * 0.18, 0.08, -0.45))
		W.mesh_node(head, W.sphere(0.09, 8), W.cmat(Color(1.0, 0.55, 0.55)), Vector3(side * 0.3, -0.12, -0.38), Vector3(1.0, 0.6, 0.5))
	W.mesh_node(head, W.sphere(0.09, 8), W.cmat(Color(1.0, 0.68, 0.55)), Vector3(0, -0.03, -0.5))
	var smile := MeshInstance3D.new()
	var sm := TorusMesh.new()
	sm.inner_radius = 0.09
	sm.outer_radius = 0.12
	sm.rings = 10
	sm.ring_segments = 5
	smile.mesh = sm
	smile.material_override = W.cmat(Color(0.55, 0.2, 0.15))
	smile.position = Vector3(0.0, -0.22, -0.43)
	smile.rotation.x = PI / 2.0
	smile.scale = Vector3(1.0, 1.0, 0.5)
	head.add_child(smile)
	var straw := W.cmat(Color(0.95, 0.82, 0.45))
	W.mesh_node(head, W.cyl(0.95, 0.95, 0.05, 18), straw, Vector3(0, 0.3, 0))
	W.mesh_node(head, W.cyl(0.38, 0.48, 0.35, 14), straw, Vector3(0, 0.48, 0))
	W.mesh_node(head, W.cyl(0.485, 0.485, 0.08, 14), W.cmat(Color(0.9, 0.35, 0.4)), Vector3(0, 0.36, 0))
	W.mesh_node(head, W.sphere(0.1, 8), W.cmat(Color(1.0, 0.9, 0.3), 0.3), Vector3(0.4, 0.4, -0.25))
	_set_layers(head, body_layer())


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


# --- Update ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		mouse_delta += motion.relative


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
		_draw_items(delta)
		return
	if vr:
		_vr_controls(delta)
		for h in hands:
			var hh: Hand = h
			hh.xf = hh.ctrl.global_transform
			hh.pos = hh.xf * GRAB_OFFSET
			var g := false
			if hh.right:
				g = hh.ctrl.get_float("trigger") > (0.35 if hh.gripping else 0.6)
			else:
				g = _left_touch_grip(hh)
			_update_hand(hh, g, delta)
		_flicks()
	elif flat:
		_flat_controls(hands[0], delta)
	_draw_items(delta)


func _flat_controls(h: Hand, delta: float) -> void:
	var grip := false
	if bot:
		flat_cursor = flat_cursor.move_toward(Vector3(bot_target.x, 0.0, bot_target.z), 9.0 * delta)
		grip = bot_grip
	else:
		var right := camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var back := Vector3(-right.z, 0.0, right.x)
		flat_cursor += (right * mouse_delta.x + back * mouse_delta.y) * 0.012
		if joy >= 0:
			var s := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
			if s.length() > 0.18:
				flat_cursor += (right * s.x + back * s.y) * 6.0 * delta
			if Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(joy, JOY_BUTTON_A) \
					or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER):
				grip = true
		if mouse_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			grip = true
	mouse_delta = Vector2.ZERO
	flat_cursor.x = clampf(flat_cursor.x, -6.3, 4.8)
	flat_cursor.z = clampf(flat_cursor.z, -2.4, 3.0)
	flat_cursor.y = 0.0
	var hover := 1.0
	if h.held == "":
		hover = 0.45 if grip else 1.0
	var want := flat_cursor + Vector3(0.0, hover, 0.0)
	if Vector2(flat_cursor.x - W.HIVE_POS.x, flat_cursor.z - W.HIVE_POS.z).length() < 1.0:
		want.y += 0.8  # up by the hive (wasps)
	h.pos = h.pos.lerp(want, 1.0 - exp(-14.0 * delta)) if h.pos != Vector3.ZERO else want
	var hb := Basis(Vector3.RIGHT, -0.6)
	h.xf = Transform3D(hb, h.pos - hb * GRAB_OFFSET)
	h.root.global_transform = h.xf
	_update_hand(h, grip, delta)
	if head:
		head.global_position = FLAT_CAM_POS + Vector3(0.0, 0.5, 1.2)
		head.look_at(h.pos, Vector3.UP)


## Grab / hold / let go. Runs on the host (and in local split screen).
func _update_hand(h: Hand, grip: bool, delta: float) -> void:
	var now := Time.get_ticks_msec()
	h.hist.append([now, h.pos])
	while h.hist.size() > 2 and now - int(h.hist[0][0]) > 90:
		h.hist.pop_front()
	if h.hist.size() >= 2:
		var dt := float(now - int(h.hist[0][0])) / 1000.0
		if dt > 0.005:
			var p0: Vector3 = h.hist[0][1]
			h.vel = (h.pos - p0) / dt
	if grip and not h.gripping:
		h.gripping = true
		_grab(h)
	elif not grip and h.gripping:
		h.gripping = false
		_release(h)
	h.pour = false
	if h.held == "can":
		var cx := _can_xf(h)
		var dir: Vector3 = cx.basis * POUR_DIR
		h.pour = dir.y < -0.12
		if h.pour:
			main.water_at(cx * W.SPOUT_TIP, delta)
			pour_snd_t -= delta
			if pour_snd_t <= 0.0:
				pour_snd_t = 0.3
				main.sound("water", -12.0, randf_range(0.9, 1.1))


func _grab(h: Hand) -> void:
	if not main.can_interact():
		return
	var reach := FLAT_REACH if flat else VR_REACH
	if flat:
		var pest = main.pest_near(h.pos, reach + 0.2, true)
		if pest != null:
			main.shoo(pest, h.pos - Vector3(0, 0, -0.5))
			return
	if main.try_harvest(h.pos, reach, flat):
		haptic(h, 0.5, 0.08)
		return
	var k: int = main.tray_pick(h.pos, reach * 0.8, flat)
	if k >= 0:
		h.held = "seed"
		h.seed_kind = k
		main.sound("pick", -6.0, 1.0 + k * 0.1)
		haptic(h, 0.3, 0.05)
		return
	var other_has_can := false
	for o in hands:
		if o != h and o.held == "can":
			other_has_can = true
	var can_at := W.CAN_HOME + Vector3(0.0, 0.3, 0.0)
	var d := Vector2(h.pos.x - can_at.x, h.pos.z - can_at.z).length() if flat else h.pos.distance_to(can_at)
	if not other_has_can and d < reach + 0.15:
		h.held = "can"
		main.sound("pick", -6.0, 0.7)
		haptic(h, 0.3, 0.05)
		if not main.has_meta("told_pour"):
			main.set_meta("told_pour", true)
			main.popup(can_at + Vector3.UP * 1.0, "Point it DOWN to pour!" if vr else "Drag it over the plants!", Color(0.6, 0.85, 1.0))
		return
	if vr:
		var fwd: Vector3 = -h.xf.basis.z
		var pest = main.pest_on_ray(h.xf.origin, fwd)
		if pest != null:
			main.mist(h.xf.origin + fwd * 0.3, pest.global_position)
			main.shoo(pest, h.xf.origin)
			haptic(h, 0.4, 0.06)


## The Frame's left trigger never reaches the game, so the left hand works by touch (the kids
## wanted both hands): touching the seed tray, the can, a ripe plant or a pest grabs/uses it; a
## downward toss plants a held seed; touching the can's spot again puts the can back.
func _left_touch_grip(h: Hand) -> bool:
	var now := Time.get_ticks_msec()
	if h.gripping:
		if h.held == "seed":
			return not (h.vel.y < -0.9 and now > int(get_meta("l_grab_at", 0)) + 300)
		if h.held == "can":
			var home := W.CAN_HOME + Vector3(0.0, 0.3, 0.0)
			return not (h.pos.distance_to(home) < VR_REACH and now > int(get_meta("l_grab_at", 0)) + 1200)
		return now < int(get_meta("l_grab_at", 0)) + 150  # a touch (harvest / shoo) is a short tap
	if now < int(get_meta("l_probe_ok", 0)):
		return false
	var near_tray := h.pos.distance_to(W.TRAY_POS + Vector3(0.0, 0.12, 0.0)) < 0.75
	var near_can := h.pos.distance_to(W.CAN_HOME + Vector3(0.0, 0.3, 0.0)) < VR_REACH + 0.15
	var near_plants := h.pos.y < 1.05
	if not (near_tray or near_can or near_plants):
		return false
	# Probe: try a grab here; keep "gripping" only if something was actually taken or used.
	set_meta("l_probe_ok", now + 400)
	set_meta("l_grab_at", now)
	return true


func _release(h: Hand) -> void:
	if h.held == "seed":
		var v := h.vel
		if flat:
			v = Vector3.ZERO
		main.drop_seed(h.seed_kind, h.pos, v.limit_length(12.0))
	elif h.held == "can":
		main.sound("pick", -10.0, 0.5)
	h.held = ""
	h.pour = false


## VR: a quick flick of either hand shoos a pest away.
func _flicks() -> void:
	for h in hands:
		var hh: Hand = h
		if hh.vel.length() < FLICK_SPEED:
			continue
		var pest = main.pest_near(hh.pos, 0.6, false)
		if pest != null:
			main.shoo(pest, hh.pos - hh.vel.normalized())
			haptic(hh, 0.6, 0.08)


func _can_xf(h: Hand) -> Transform3D:
	if flat:
		var b := Basis(Vector3.RIGHT, -1.15)
		var tip_off: Vector3 = b * W.SPOUT_TIP
		return Transform3D(b, h.pos + Vector3(0.0, 0.25, 0.0) - Vector3(tip_off.x, 0.0, tip_off.z))
	return h.xf * Transform3D(Basis(), Vector3(0.0, 0.0, 0.05))


## Where the can, seeds and water stream are drawn (host, local and TV ghost alike).
func _draw_items(delta: float) -> void:
	var can_hand: Hand = null
	for h in hands:
		var hh: Hand = h
		if hh.held == "can":
			can_hand = hh
		hh.seed_node.visible = hh.held == "seed"
		if hh.seed_node.visible:
			hh.seed_node.global_position = hh.pos
			var kd: Dictionary = W.KINDS[clampi(hh.seed_kind, 0, 2)]
			hh.seed_node.material_override = W.cmat(Color(kd.petal).darkened(0.35), 0.2)
	var pouring := false
	if can_hand != null:
		var target := _can_xf(can_hand)
		can.global_transform = can.global_transform.interpolate_with(target, 1.0 - exp(-30.0 * delta)) if ghost else target
		pouring = can_hand.pour
	else:
		var home := Transform3D(Basis(Vector3.UP, PI * 0.5), W.CAN_HOME + Vector3(0.0, 0.47, 0.0))
		can.global_transform = can.global_transform.interpolate_with(home, 1.0 - exp(-10.0 * delta))
	stream.emitting = pouring
	if pouring:
		stream.global_transform = can.global_transform * Transform3D(Basis(), W.SPOUT_TIP)
		stream.direction = POUR_DIR


func haptic(h: Hand, amp: float, dur: float) -> void:
	if vr and h.ctrl:
		h.ctrl.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)
	elif joy >= 0:
		Input.start_joy_vibration(joy, amp * 0.4, amp * 0.2, dur)


func buzz_right(amp: float) -> void:
	for h in hands:
		if h.right:
			haptic(h, amp, 0.08)


func let_go_all() -> void:
	for h in hands:
		h.held = ""
		h.gripping = false
		h.pour = false


# --- VR: fitting the bed to the player, moving around -------------------------

func _vr_controls(delta: float) -> void:
	if xr_origin.world_scale != W.S:
		xr_origin.world_scale = W.S
	calib_t += delta
	if not calibrated and calib_t > 0.5 and xr_camera.position != Vector3.ZERO:
		calibrated = true
		refit(true)
	var a := hand_r.is_button_pressed("ax_button") or hand_l.is_button_pressed("ax_button")
	if a and not a_was and calibrated:
		refit(true)
		main.sound("pick", -8.0, 0.7)
	a_was = a
	# Someone taller or shorter put the headset on (or they sat down): re-fit the height.
	var head_y := xr_camera.position.y
	if calibrated and absf(head_y - float(get_meta("calib_y", head_y))) > 0.15 * W.S:
		set_meta("height_off_t", float(get_meta("height_off_t", 0.0)) + delta)
		if float(get_meta("height_off_t", 0.0)) > 1.5:
			refit(false)
	else:
		set_meta("height_off_t", 0.0)
	var r := hand_r.get_vector2("primary")
	if absf(r.x) > 0.7 and snap_ready:
		snap_ready = false
		_snap_turn(-signf(r.x) * deg_to_rad(45.0))
	elif absf(r.x) < 0.3:
		snap_ready = true
	if absf(r.y) > 0.5 and absf(r.x) < 0.5:
		xr_origin.global_position.y -= signf(r.y) * 0.25 * W.S * delta  # stick up: bed comes up
		set_meta("calib_y", xr_camera.position.y)
	var l := hand_l.get_vector2("primary")
	if l.length() > 0.2:
		var b := Basis(Vector3.UP, xr_camera.global_rotation.y)
		xr_origin.global_position += b * Vector3(l.x, 0.0, -l.y) * 0.6 * W.S * delta
	# Don't wander off too far.
	var hp := xr_camera.global_position
	var fix := Vector3(clampf(hp.x, -8.0, 8.0) - hp.x, 0.0, clampf(hp.z, -6.0, 7.0) - hp.z)
	xr_origin.global_position += fix
	global_position = Vector3(hp.x, 0.0, hp.z)


## Put the bed in front of the gardener: eyes HEAD_ABOVE_SOIL above the soil, EYE_Z from its centre.
## full = also face the bed and step back to the front edge; otherwise only the height changes.
func refit(full: bool) -> void:
	set_meta("calib_y", xr_camera.position.y)
	set_meta("height_off_t", 0.0)
	if full:
		var local := xr_camera.transform
		var head_yaw := local.basis.get_euler().y
		var basis := Basis(Vector3.UP, -head_yaw)
		var want := Vector3(0.0, HEAD_ABOVE_SOIL * W.S, EYE_Z * W.S)
		var off := basis * local.origin
		xr_origin.global_transform = Transform3D(basis, want - off)
	else:
		xr_origin.global_position.y += HEAD_ABOVE_SOIL * W.S - xr_camera.global_position.y
	print("Gardener: bed fitted (head %.2f m above the floor)" % (xr_camera.position.y / W.S))


func _snap_turn(angle: float) -> void:
	var pivot := xr_camera.global_position
	var rot := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	var xf := xr_origin.global_transform
	xf.origin -= pivot
	xf = rot * xf
	xf.origin += pivot
	xr_origin.global_transform = xf


func restart_held() -> bool:
	if vr:
		return hand_r.get_float("trigger") > 0.6 or hand_r.is_button_pressed("ax_button")
	if joy >= 0:
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
	return false


# --- Network -----------------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if head:
		return head.global_transform
	return Transform3D()


func net_state() -> Array:
	var hx: Array = []
	var held: Array = []
	var pour: Array = []
	for h in hands:
		hx.append(h.xf)
		held.append(h.held + str(h.seed_kind) if h.held == "seed" else h.held)
		pour.append(h.pour)
	return [head_transform(), hx, held, pour, vr]


func apply_net_state(st: Array) -> void:
	net_head = st[0]
	net_hands = st[1]
	net_held = st[2]
	net_pour = st[3]


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func _ghost_update(delta: float) -> void:
	var k := 1.0 - exp(-20.0 * delta)
	if net_head != Transform3D():
		head.global_transform = head.global_transform.interpolate_with(net_head.orthonormalized(), k)
	for i in hands.size():
		var h: Hand = hands[i]
		var on := i < net_hands.size()
		h.root.visible = on
		if not on:
			h.held = ""
			continue
		var xf: Transform3D = net_hands[i]
		h.xf = h.root.global_transform.interpolate_with(xf.orthonormalized(), k)
		h.root.global_transform = h.xf
		h.pos = h.xf * GRAB_OFFSET
		var held: String = net_held[i] if i < net_held.size() else ""
		if held.begins_with("seed"):
			h.held = "seed"
			h.seed_kind = int(held.substr(4))
		else:
			h.held = held
		h.pour = net_pour[i] if i < net_pour.size() else false
	# A flat gardener has one hand: its can is drawn tilted like on the host.
	flat = net_hands.size() == 1
