extends Node3D
## Player 1: the friendly GIANT sitting at the table.
## VR: XROrigin3D.world_scale makes the village a miniature. Grip or trigger near a goblin, boulder,
##   ember or knight picks it up; let go to drop it, or throw it (hand speed from recent positions).
##   Right stick: walk around the table (snap 45°). Left stick up/down: lean in / back.
##   B / Y: re-centre the table in front of you. A / X: restart after game over. Menu: pause.
## Flat fallback (split screen / no headset): a big hand cursor moved with the mouse (or the second
##   controller's left stick); hold the left mouse button (or RT / A) to grab, release to throw.
## TV: a ghost of the giant (big friendly head + hands) placed from the host's snapshots.

const W := preload("res://games/giants_table/world.gd")
const GRAB_OFFSET := Vector3(0.0, -0.35, -0.75)  # grab point in hand space (fingers point -Z)
const VR_REACH := 1.3
const FLAT_REACH := 1.9
const THROW_MULT := 1.25
const MAX_THROW := 70.0
const HEAD_ABOVE_TABLE := 0.45   # metres between the giant's eyes and the tabletop
const SEAT_DIST := 0.95          # metres from the table centre to the giant's eyes
const FLAT_CAM_POS := Vector3(0.0, 23.0, 22.0)

var main
var index := 0
var color := Color(0.3, 0.7, 1.0)
var vr := false
var ghost := false
var flat := false
var remote := false
var active := true
var is_down := false
var carried := false
var joy := -1
var mouse_on := false  # flat giant reads the mouse (local split screen and flat host)

var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var camera: Camera3D       # flat view
var wrist_label: Label3D
var head: Node3D           # big friendly face, seen by the knights
var hands: Array = []
var calibrated := false
var calib_t := 0.0
var snap_ready := true
var recenter_was := false
var flat_cursor := Vector3(0.0, 0.0, 6.0)
var mouse_delta := Vector2.ZERO
var bot := false
var bot_target := Vector3.ZERO
var bot_grip := false
# TV ghost state
var net_head := Transform3D()
var net_hands: Array = []
var net_grips: Array = []


class Hand:
	var root: Node3D          # visual (world space)
	var fingers: Array = []
	var thumb: Node3D
	var marker: MeshInstance3D
	var marker_mat: StandardMaterial3D
	var ctrl: XRController3D
	var pos := Vector3.ZERO   # grab point, world space
	var yaw := 0.0
	var hist: Array = []      # [[msec, pos], ...]
	var vel := Vector3.ZERO
	var grip := 0.0
	var gripping := false
	var held = null
	var hold_off := Vector3.ZERO
	var refuse_t := 0.0


func body_layer() -> int:
	return 2  # the giant's own head: hidden from the giant's camera


func _ready() -> void:
	add_to_group("giant")
	process_priority = 10  # after the XR controllers have their new poses


func setup_vr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	origin.world_scale = W.S
	cam.near = 0.4
	cam.far = 2000.0
	cam.cull_mask = 0xFFFFF & ~body_layer()
	for c in [left, right]:
		var h := _make_hand(c == left)
		h.ctrl = c
		h.root.reparent(c, false)  # drawn with the freshest controller pose
		h.root.transform = Transform3D()
		hands.append(h)
	wrist_label = Label3D.new()
	wrist_label.pixel_size = 0.0055
	wrist_label.font_size = 40
	wrist_label.outline_size = 26
	wrist_label.outline_modulate = Color.BLACK
	wrist_label.modulate = Color(1.0, 0.92, 0.7)
	wrist_label.no_depth_test = true
	wrist_label.render_priority = 5
	wrist_label.position = Vector3(0.0, 0.9, 1.4)
	wrist_label.rotation_degrees = Vector3(-50, 0, 0)
	left.add_child(wrist_label)
	# Start seated at the table's south side; re-centred once the headset reports a pose.
	origin.global_position = Vector3(0.0, HEAD_ABOVE_TABLE * W.S - 1.2 * W.S, SEAT_DIST * W.S)


func setup_flat(cam: Camera3D, use_mouse: bool) -> void:
	flat = true
	mouse_on = use_mouse
	camera = cam
	camera.fov = 62.0
	camera.near = 0.2
	camera.far = 1000.0
	camera.cull_mask = 0xFFFFF & ~body_layer()
	camera.global_position = FLAT_CAM_POS
	camera.look_at(Vector3(0.0, 0.0, 1.0), Vector3.UP)
	hands.append(_make_hand(false))
	_ensure_head()


func setup_ghost() -> void:
	ghost = true
	for i in 2:
		hands.append(_make_hand(i == 0))
	_ensure_head()


# --- Visuals -----------------------------------------------------------------

func _make_hand(left: bool) -> Hand:
	var h := Hand.new()
	h.root = Node3D.new()
	main.add_child(h.root)
	var skin := W.mat(Color(1.0, 0.78, 0.62), 0.0, 0.7)
	var palm := MeshInstance3D.new()
	palm.mesh = W.box(Vector3(1.45, 0.45, 1.5))
	palm.material_override = skin
	palm.position = Vector3(0.0, 0.0, 0.25)
	h.root.add_child(palm)
	var cuff := MeshInstance3D.new()
	cuff.mesh = W.cyl(0.7, 0.75, 0.9, 12)
	cuff.material_override = W.mat(color.darkened(0.1))
	cuff.rotation.x = PI / 2.0
	cuff.position = Vector3(0.0, 0.0, 1.35)
	h.root.add_child(cuff)
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.54 + i * 0.36, 0.0, -0.45)
		h.root.add_child(f)
		var fm := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.16
		cap.height = 1.0 if i != 0 and i != 3 else 0.85
		cap.radial_segments = 8
		cap.rings = 2
		fm.mesh = cap
		fm.material_override = skin
		fm.rotation.x = PI / 2.0
		fm.position.z = -cap.height * 0.42
		f.add_child(fm)
		h.fingers.append(f)
	h.thumb = Node3D.new()
	var side := 1.0 if left else -1.0
	h.thumb.position = Vector3(0.75 * side, -0.05, 0.25)
	h.thumb.rotation.y = 0.7 * side
	h.root.add_child(h.thumb)
	var tm := MeshInstance3D.new()
	var tcap := CapsuleMesh.new()
	tcap.radius = 0.17
	tcap.height = 0.8
	tcap.radial_segments = 8
	tcap.rings = 2
	tm.mesh = tcap
	tm.material_override = skin
	tm.rotation.x = PI / 2.0
	tm.position.z = -0.3
	h.thumb.add_child(tm)
	# A soft shadow on the table under the grab point: depth cue for VR and the flat view.
	h.marker = MeshInstance3D.new()
	h.marker.mesh = W.cyl(0.8, 0.8, 0.02, 20)
	h.marker_mat = StandardMaterial3D.new()
	h.marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	h.marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	h.marker_mat.albedo_color = Color(0.1, 0.05, 0.0, 0.35)
	h.marker.material_override = h.marker_mat
	h.marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(h.marker)
	return h


func _ensure_head() -> void:
	if head != null:
		return
	head = Node3D.new()
	main.add_child(head)
	var face := MeshInstance3D.new()
	face.mesh = W.sphere(2.4, 20)
	face.material_override = W.mat(Color(1.0, 0.8, 0.65), 0.0, 0.8)
	head.add_child(face)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = W.sphere(0.5, 12)
		eye.material_override = W.mat(Color.WHITE)
		eye.position = Vector3(side * 0.85, 0.35, -2.05)
		head.add_child(eye)
		var pupil := MeshInstance3D.new()
		pupil.mesh = W.sphere(0.26, 10)
		pupil.material_override = W.mat(Color(0.15, 0.1, 0.08))
		pupil.position = Vector3(side * 0.85, 0.35, -2.45)
		head.add_child(pupil)
		var cheek := MeshInstance3D.new()
		cheek.mesh = W.sphere(0.45, 10)
		cheek.material_override = W.mat(Color(1.0, 0.55, 0.55))
		cheek.position = Vector3(side * 1.35, -0.5, -1.75)
		cheek.scale = Vector3(1.0, 0.6, 0.5)
		head.add_child(cheek)
	var nose := MeshInstance3D.new()
	nose.mesh = W.sphere(0.5, 12)
	nose.material_override = W.mat(Color(1.0, 0.7, 0.58))
	nose.position = Vector3(0.0, -0.2, -2.4)
	head.add_child(nose)
	var beard := MeshInstance3D.new()
	beard.mesh = W.sphere(1.8, 16)
	beard.material_override = W.mat(Color(0.75, 0.45, 0.25))
	beard.position = Vector3(0.0, -1.9, -0.7)
	beard.scale = Vector3(1.05, 0.8, 0.9)
	head.add_child(beard)
	var smile := MeshInstance3D.new()
	var sm := TorusMesh.new()
	sm.inner_radius = 0.45
	sm.outer_radius = 0.6
	smile.mesh = sm
	smile.material_override = W.mat(Color(0.5, 0.15, 0.12))
	smile.position = Vector3(0.0, -0.95, -2.1)
	smile.rotation.x = PI / 2.0
	smile.scale = Vector3(1.0, 1.0, 0.5)
	head.add_child(smile)
	var hat := MeshInstance3D.new()
	hat.mesh = W.cyl(1.0, 2.5, 2.2, 16)
	hat.material_override = W.mat(color)
	hat.position = Vector3(0.0, 2.2, 0.2)
	head.add_child(hat)
	var bobble := MeshInstance3D.new()
	bobble.mesh = W.sphere(0.7, 10)
	bobble.material_override = W.mat(Color(1.0, 0.95, 0.85))
	bobble.position = Vector3(0.0, 3.5, 0.2)
	head.add_child(bobble)
	_set_layers(head, body_layer())


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


func _pose_hand(h: Hand, xf: Transform3D, grip: float) -> void:
	if h.ctrl == null:
		h.root.global_transform = xf
	for f in h.fingers:
		f.rotation.x = -grip * 1.25
	h.thumb.rotation.x = -grip * 0.6
	var g := W.height(h.pos.x, h.pos.z)
	var above := h.pos.y - g
	h.marker.visible = g > -50.0 and above > 0.0 and above < 25.0
	if h.marker.visible:
		h.marker.global_position = Vector3(h.pos.x, g + 0.04, h.pos.z)
		var s := clampf(1.2 - above * 0.04, 0.4, 1.2)
		h.marker.scale = Vector3(s, 1.0, s)
		h.marker_mat.albedo_color.a = clampf(0.5 - above * 0.02, 0.12, 0.5)


# --- Update ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		mouse_delta += motion.relative


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
		return
	if vr:
		_vr_controls(delta)
		for h in hands:
			var xf: Transform3D = h.ctrl.global_transform
			h.pos = xf * GRAB_OFFSET
			h.yaw = xf.basis.get_euler().y
			var g := maxf(h.ctrl.get_float("grip"), h.ctrl.get_float("trigger"))
			if bot:
				g = 1.0 if bot_grip and h == hands[1] else 0.0
			_update_hand(h, g, delta)
			_pose_hand(h, xf, maxf(g, 0.6 if h.held != null else 0.0))
		_update_wrist()
	elif flat:
		var h: Hand = hands[0]
		_flat_controls(h, delta)


func _flat_controls(h: Hand, delta: float) -> void:
	var grip := 0.0
	if bot:
		flat_cursor = flat_cursor.move_toward(Vector3(bot_target.x, 0.0, bot_target.z), 30.0 * delta)
		grip = 1.0 if bot_grip else 0.0
	else:
		var right := camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var back := Vector3(-right.z, 0.0, right.x)
		flat_cursor += (right * mouse_delta.x + back * mouse_delta.y) * 0.035
		if joy >= 0:
			var s := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
			if s.length() > 0.18:
				flat_cursor += (right * s.x + back * s.y) * 16.0 * delta
			if Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(joy, JOY_BUTTON_A) \
					or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER):
				grip = 1.0
		if mouse_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			grip = 1.0
	mouse_delta = Vector2.ZERO
	var fc := Vector2(flat_cursor.x, flat_cursor.z).limit_length(W.EDGE + 2.0)
	flat_cursor = Vector3(fc.x, 0.0, fc.y)
	var g := maxf(W.height(fc.x, fc.y), 0.0)
	var hover := 2.6
	if grip > 0.5:
		hover = 5.0 if h.held != null else 0.9
	var want := Vector3(fc.x, g + hover, fc.y)
	h.pos = h.pos.lerp(want, 1.0 - exp(-14.0 * delta)) if h.pos != Vector3.ZERO else want
	h.yaw = 0.0
	_update_hand(h, grip, delta)
	var xf := Transform3D(Basis(), h.pos - GRAB_OFFSET + Vector3(0.0, 0.25, 0.0))
	_pose_hand(h, xf, maxf(grip, 0.6 if h.held != null else 0.0))
	if head:
		head.global_position = FLAT_CAM_POS + Vector3(0.0, 2.0, 3.0)
		head.look_at(h.pos, Vector3.UP)


## Grab / hold / throw. Runs on the host (and in local split screen).
func _update_hand(h: Hand, grip: float, delta: float) -> void:
	h.grip = grip
	h.refuse_t -= delta
	var now := Time.get_ticks_msec()
	h.hist.append([now, h.pos])
	while h.hist.size() > 2 and now - int(h.hist[0][0]) > 90:
		h.hist.pop_front()
	if h.hist.size() >= 2:
		var dt := float(now - int(h.hist[0][0])) / 1000.0
		if dt > 0.005:
			var p0: Vector3 = h.hist[0][1]
			h.vel = (h.pos - p0) / dt
	if h.held != null and (not is_instance_valid(h.held) or h.held.is_queued_for_deletion()):
		h.held = null
	if grip > 0.55 and not h.gripping:
		if _try_grab(h):
			h.gripping = true
		elif not flat:
			h.gripping = true  # VR: a squeeze on nothing stays a squeeze until let go
	elif grip < 0.35 and h.gripping:
		h.gripping = false
		_release(h)
	if h.held != null:
		h.hold_off = h.hold_off.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
		h.held.hold_at(h.pos + h.hold_off, h.yaw)


func _try_grab(h: Hand) -> bool:
	if main.game_over:
		return false
	var best = null
	var best_d := INF
	var reach := FLAT_REACH if flat else VR_REACH
	for group in ["goblins", "boulders", "embers", "knights"]:
		for o in get_tree().get_nodes_in_group(group):
			if o.is_queued_for_deletion() or (group == "knights" and not o.active):
				continue
			var c: Vector3 = o.grab_center()
			var d := 0.0
			if flat:
				d = Vector2(c.x - h.pos.x, c.z - h.pos.z).length() - o.radius
			else:
				d = c.distance_to(h.pos) - o.radius
			if group == "knights":
				d += 0.3  # prefer goblins and boulders when they're bunched up
			if d < reach and d < best_d:
				best_d = d
				best = o
	if best == null:
		return false
	if not best.can_grab():
		if h.refuse_t <= 0.0:
			h.refuse_t = 1.0
			main.popup(best.grab_center() + Vector3.UP * 0.9, "OUCH! Too spiky!\nKnights, get this one!", Color(1.0, 0.6, 0.5))
			main.sound("hurt", -6.0, 0.7)
			haptic(h, 0.9, 0.15)
		return false
	for other in hands:
		if other.held == best:
			other.held = null
	best.on_grabbed()
	h.held = best
	h.hold_off = best.grab_center() - h.pos
	main.on_grabbed(best)
	haptic(h, 0.45, 0.06)
	return true


func _release(h: Hand) -> void:
	if h.held == null:
		return
	var v := h.vel * THROW_MULT
	if flat:
		v = Vector3(h.vel.x, 0.0, h.vel.z) * 1.4 + Vector3.UP * 4.0
	v = v.limit_length(MAX_THROW)
	var obj = h.held
	h.held = null
	obj.on_released(v)
	main.on_released(obj, v)
	if v.length() > 14.0:
		haptic(h, 0.3, 0.05)


func haptic(h: Hand, amp: float, dur: float) -> void:
	if vr and h.ctrl:
		h.ctrl.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


## Rumble whichever hand is nearest to a thud.
func thud_haptic(pos: Vector3, strength: float) -> void:
	if not vr:
		return
	for h in hands:
		var d: float = h.pos.distance_to(pos)
		if d < 8.0:
			haptic(h, clampf(strength * (1.0 - d / 8.0), 0.05, 1.0), 0.06)


func release_all() -> void:
	for h in hands:
		if h.held != null and is_instance_valid(h.held):
			_release(h)
		h.gripping = false


# --- VR seat: calibration, walking round the table, leaning ------------------

func _vr_controls(delta: float) -> void:
	calib_t += delta
	if not calibrated and calib_t > 0.5 and xr_camera.position != Vector3.ZERO:
		calibrated = true
		recenter(0.0)
	var rc := hand_l.is_button_pressed("by_button") or hand_r.is_button_pressed("by_button")
	# A new (taller or shorter) person put the headset on: re-fit the table to their eye height.
	var head_y := xr_camera.position.y
	if calibrated and not has_meta("calib_y"):
		rc = true  # first frame after this code arrived: fit to whoever is wearing it now
	elif calibrated and absf(head_y - float(get_meta("calib_y", head_y))) > 0.15:
		set_meta("height_off_t", float(get_meta("height_off_t", 0.0)) + delta)
		if float(get_meta("height_off_t", 0.0)) > 1.5:
			rc = true
	else:
		set_meta("height_off_t", 0.0)
	# Squeeze BOTH triggers for a second: bring the table to wherever you're standing and facing
	# (the Frame's B button doesn't reach the game).
	if hand_l.get_float("trigger") > 0.8 and hand_r.get_float("trigger") > 0.8:
		set_meta("both_t", float(get_meta("both_t", 0.0)) + delta)
		if float(get_meta("both_t", 0.0)) > 1.0:
			set_meta("both_t", -100.0)
			rc = true
	else:
		set_meta("both_t", 0.0)
	if rc and not recenter_was:
		var flat_pos := Vector2(xr_camera.global_position.x, xr_camera.global_position.z)
		recenter(atan2(flat_pos.x, flat_pos.y))
		main.sound("pickup", -8.0, 0.7)
	recenter_was = rc
	var turn := hand_r.get_vector2("primary").x
	if absf(turn) > 0.7 and snap_ready:
		snap_ready = false
		_orbit(-signf(turn) * deg_to_rad(45.0))
	elif absf(turn) < 0.3:
		snap_ready = true
	var lean := hand_l.get_vector2("primary").y
	if absf(lean) > 0.2:
		var hp := xr_camera.global_position
		var to_c := Vector3(-hp.x, 0.0, -hp.z)
		var d := to_c.length()
		var step := lean * 8.0 * delta
		if d - step < 6.0 or d - step > 30.0:
			step = 0.0
		if d > 0.01:
			xr_origin.global_position += to_c / d * step


## Put the table in front of the giant: eyes HEAD_ABOVE_TABLE above it, SEAT_DIST from the centre,
## looking at the centre from angle `theta` (0 = the south side).
func recenter(theta: float) -> void:
	set_meta("calib_y", xr_camera.position.y)
	set_meta("height_off_t", 0.0)
	var local := xr_camera.transform
	var head_yaw := local.basis.get_euler().y
	var origin_yaw := theta - head_yaw
	var basis := Basis(Vector3.UP, origin_yaw)
	var want := Vector3(sin(theta), 0.0, cos(theta)) * SEAT_DIST * W.S
	want.y = HEAD_ABOVE_TABLE * W.S
	var off := basis * local.origin
	xr_origin.global_transform = Transform3D(basis, want - off)


func _orbit(angle: float) -> void:
	var rot := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	xr_origin.global_transform = rot * xr_origin.global_transform
	main.sound("dash", -10.0, 0.6)


func _update_wrist() -> void:
	var status := ""
	if main.net.mode == "host" and not main.net.connected:
		status = "\nWaiting for the knights to join…"
	wrist_label.text = "WAVE %d   SCORE %d\nEMBERS %d / %d%s" % [main.wave, main.score, main.embers, main.max_embers, status]


func restart_held() -> bool:
	if vr:
		return hand_r.is_button_pressed("ax_button") or hand_l.is_button_pressed("ax_button")
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
	var gr: Array = []
	for h in hands:
		hx.append(h.root.global_transform)
		gr.append(maxf(h.grip, 0.6 if h.held != null else 0.0))
	return [head_transform(), hx, gr, vr]


func apply_net_state(st: Array) -> void:
	net_head = st[0]
	net_hands = st[1]
	net_grips = st[2]


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func _ghost_update(delta: float) -> void:
	var k := 1.0 - exp(-20.0 * delta)
	if net_head != Transform3D():
		var target := net_head.orthonormalized()
		head.global_transform = head.global_transform.interpolate_with(target, k)
		head.visible = true
	for i in hands.size():
		var h: Hand = hands[i]
		var on := i < net_hands.size()
		h.root.visible = on
		h.marker.visible = false
		if not on:
			continue
		var xf: Transform3D = net_hands[i]
		var g: float = net_grips[i]
		var cur := h.root.global_transform.interpolate_with(xf.orthonormalized(), k)
		h.pos = cur * GRAB_OFFSET
		_pose_hand(h, cur, g)
