extends Node3D
## Player 1, the dragon rider (players[0]), sitting in the saddle holding the reins.
## VR (Steam Frame): steer with your HANDS, like holding reins: pull both hands back towards you =
## climb, push them forward = dive, move them left / right (or tip them like a steering wheel) = turn.
## Right trigger = flap the wings (speed boost). A = re-centre the reins and your seat.
## Thumbsticks also steer (up = climb). The seat fits itself to your head (sitting / small riders),
## and re-fits if the headset is handed to someone taller or shorter.
## Flat (split screen / non-VR host): W/S or stick up/down = climb/dive, A/D or stick = turn,
## Space / click / RT / A = flap, mouse / right stick look around.
## On the TV machine this is a ghost: a rider with a helmet and mittens, from the host's snapshots.

const NEUTRAL_DEFAULT := Vector3(0.0, -0.5, -0.38)  # hands relative to the eyes when the reins are slack
const MOUSE_SENS := 0.0028
const KEYS := {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "flap": KEY_SPACE}

var index := 0
var main
var color := Color(1.0, 0.6, 0.3)
var vr := false
var ghost := false
var remote := false
var active := true
var joy := -1
var key_set := 0
var mouse_look := true
var pad_lost_t := -1.0
var net_started := true
var camera: Camera3D
var hud
var yaw := 0.0  # flat: look offset around the chase camera
var pitch := 0.0
var look_idle := 0.0
var bot_input := Vector2.ZERO
var bot_flap := false
var bot_drive := false  # tests: steer with bot_input instead of real input

var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var fit_xf := Transform3D()
var fitted := false
var fit_t := 0.6
var fit_head_y := 0.0
var refit_t := 0.0
var neutral := NEUTRAL_DEFAULT
var a_was := false
var rein_input := Vector2.ZERO

var figure: Node3D
var head: Node3D
var mitten_l: MeshInstance3D
var mitten_r: MeshInstance3D
var rein_l: MeshInstance3D
var rein_r: MeshInstance3D
var net_head := Transform3D(Basis(), Vector3(0, 0.85, 0.12))
var net_hl := Transform3D(Basis(), Vector3(-0.22, 0.35, -0.3))
var net_hr := Transform3D(Basis(), Vector3(0.22, 0.35, -0.3))


func _ready() -> void:
	var suit: StandardMaterial3D = main.color_mat(color, 0.1)
	var skin: StandardMaterial3D = main.color_mat(Color(1.0, 0.82, 0.68), 0.0)
	var helmet: StandardMaterial3D = main.color_mat(Color(0.95, 0.85, 0.4), 0.2)
	var mitt: StandardMaterial3D = main.color_mat(Color(0.95, 0.5, 0.3), 0.1)
	var rein_mat: StandardMaterial3D = main.color_mat(Color(0.75, 0.35, 0.2), 0.1)
	figure = Node3D.new()
	add_child(figure)
	_mesh(figure, main.capsule_mesh(0.24, 0.8), suit, Vector3(0, 0.4, 0.15))
	head = Node3D.new()
	figure.add_child(head)
	_mesh(head, main.sphere_mesh(0.17), skin, Vector3.ZERO)
	_mesh(head, main.sphere_mesh(0.19), helmet, Vector3(0, 0.06, 0.02)).scale = Vector3(1.0, 0.75, 1.05)
	_mesh(head, main.box_mesh(Vector3(0.26, 0.07, 0.04)), main.color_mat(Color(0.3, 0.8, 1.0), 0.8), Vector3(0, 0.03, -0.16))
	mitten_l = _mesh(self, main.sphere_mesh(0.05), mitt, Vector3.ZERO)
	mitten_r = _mesh(self, main.sphere_mesh(0.05), mitt, Vector3.ZERO)
	mitten_l.scale = Vector3(0.9, 0.75, 1.3)
	mitten_r.scale = Vector3(0.9, 0.75, 1.3)
	rein_l = _mesh(self, main.cyl_mesh(0.012, 0.012, 1.0, 4), rein_mat, Vector3.ZERO)
	rein_r = _mesh(self, main.cyl_mesh(0.012, 0.012, 1.0, 4), rein_mat, Vector3.ZERO)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func set_active(on: bool) -> void:
	active = on


func haptic(which: String, amp: float) -> void:
	if vr:
		var h: XRController3D = hand_l if which == "l" else hand_r
		h.trigger_haptic_pulse("haptic", 0.0, amp, 0.08, 0.0)
	elif joy >= 0:
		Input.start_joy_vibration(joy, amp * 0.4, amp * 0.2, 0.1)


# --- Setup -------------------------------------------------------------------

func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	camera = cam
	cam.near = 0.04
	cam.far = 1500.0
	figure.visible = false  # you are the rider: just your mittens
	origin.world_scale = 1.0


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 72.0
	camera.near = 0.1
	camera.far = 1500.0


# --- Per frame (main calls these: input before the dragon flies, place after) ----

## Rein input: x = turn (-1 left .. +1 right), y = climb (+1) / dive (-1).
func steer_input(delta: float) -> Vector2:
	if bot_drive:
		return bot_input
	if vr:
		return _vr_input(delta)
	var v := Vector2(float(_key("right")) - float(_key("left")), float(_key("up")) - float(_key("down")))
	if joy >= 0:
		var s := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), -Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if s.length() > 0.18:
			v += s
	return v.limit_length(1.0)


func flap_held() -> bool:
	if bot_drive:
		return bot_flap
	if vr:
		return hand_r.get_float("trigger") > 0.6
	if _key("flap"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		return Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(joy, JOY_BUTTON_A) \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	return false


func vr_trigger_held() -> bool:
	return vr and hand_r.get_float("trigger") > 0.6


func _key(action: String) -> bool:
	if key_set < 0:
		return false
	return Input.is_physical_key_pressed(KEYS[action])


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and not vr and not ghost and camera != null \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		yaw = clampf(yaw - motion.relative.x * MOUSE_SENS, -2.6, 2.6)
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -0.9, 0.7)
		look_idle = 0.0


## Called after the dragon moved this frame.
func place(delta: float) -> void:
	if ghost:
		_ghost_place()
	elif vr:
		_vr_place(delta)
	else:
		_flat_place(delta)


# --- VR ----------------------------------------------------------------------

func _hand_local(h: XRController3D) -> Vector3:
	return fit_xf * h.transform.origin


func _vr_input(_delta: float) -> Vector2:
	var a := hand_r.is_button_pressed("ax_button")
	if a and not a_was:
		fitted = false
		fit_t = 0.0
		print("VR: A pressed, re-centring the seat and reins")
	a_was = a
	var stick := hand_l.get_vector2("primary") + hand_r.get_vector2("primary")
	var v := Vector2.ZERO
	if stick.length() > 0.25:
		v = stick.limit_length(1.0)
	if fitted and hand_l.get_has_tracking_data() and hand_r.get_has_tracking_data():
		var eye: Vector3 = main.dragon.EYE
		var l: Vector3 = _hand_local(hand_l) - eye
		var r: Vector3 = _hand_local(hand_r) - eye
		var avg: Vector3 = (l + r) * 0.5
		var d: Vector3 = avg - neutral
		var climb := clampf(d.z / 0.09, -1.0, 1.0)  # pulled back towards you = climb (sensitive: kids found diving hard)
		var turn := clampf(d.x / 0.12 + (l.y - r.y) / 0.18, -1.0, 1.0)
		# Reins only turn: their up/down drifted with how each kid held their hands and kept the
		# dragon stuck at the ceiling. Height comes from looking up/down (and the stick).
		# Abigail's idea: raise the reins to fly up, lower them to fly down. Measured from the eyes
		# (not a calibrated rest pose), with a wide comfy middle zone around tummy height.
		var lift := clampf((avg.y + 0.45) / 0.2, -1.0, 1.0)
		rein_input = Vector2(_dead(turn, 0.12), _dead(lift, 0.3) + 0.0 * climb)
		v += rein_input
	# Look where you want to go: looking well down dives, looking up climbs (what the kids tried first).
	if vr and xr_camera != null:
		var look_pitch := xr_camera.global_basis.get_euler().x  # negative = looking down
		var gaze := 0.0
		if absf(look_pitch) > deg_to_rad(22.0):
			gaze = clampf((absf(look_pitch) - deg_to_rad(22.0)) / deg_to_rad(20.0), 0.0, 1.0) * signf(look_pitch)
		v.y += gaze
	return v.limit_length(1.0)


func _dead(x: float, dz: float) -> float:
	if absf(x) < dz:
		return 0.0
	return signf(x) * (absf(x) - dz) / (1.0 - dz)


func _vr_place(delta: float) -> void:
	if xr_origin.world_scale != 1.0:
		xr_origin.world_scale = 1.0
	var cam_local := xr_camera.transform  # tracking space
	if not fitted:
		fit_t -= delta
		if fit_t <= 0.0 and cam_local.origin != Vector3.ZERO:
			_fit(cam_local)
	else:
		# Someone else put the headset on (or sat down / stood up): fit again.
		if absf(cam_local.origin.y - fit_head_y) > 0.25:
			refit_t += delta
			if refit_t > 1.5:
				print("VR: head height changed %.2f -> %.2f m, re-fitting" % [fit_head_y, cam_local.origin.y])
				_fit(cam_local)
		else:
			refit_t = 0.0
	xr_origin.global_transform = main.dragon.global_transform * fit_xf
	mitten_l.global_transform = hand_l.global_transform
	mitten_r.global_transform = hand_r.global_transform
	mitten_l.scale = Vector3(0.9, 0.75, 1.3)
	mitten_r.scale = Vector3(0.9, 0.75, 1.3)
	_reins(hand_l.global_position, hand_r.global_position)


## Put the rider's eyes at the saddle's eye point, facing the dragon's head. The hands at this
## moment become "slack reins" if they look sensible (below the eyes, in front).
func _fit(cam_local: Transform3D) -> void:
	fitted = true
	refit_t = 0.0
	fit_head_y = cam_local.origin.y
	var head_yaw := cam_local.basis.get_euler().y
	var r := Basis(Vector3.UP, -head_yaw)
	fit_xf = Transform3D(r, main.dragon.EYE - r * cam_local.origin)
	neutral = NEUTRAL_DEFAULT
	if hand_l.get_has_tracking_data() and hand_r.get_has_tracking_data():
		var eye: Vector3 = main.dragon.EYE
		var avg: Vector3 = (_hand_local(hand_l) + _hand_local(hand_r)) * 0.5 - eye
		if avg.y < -0.15 and avg.y > -0.8 and avg.z < -0.1 and avg.z > -0.7 and absf(avg.x) < 0.25:
			neutral = avg
	print("VR: seat fitted, head %.2f m above the floor, reins neutral %s" % [fit_head_y, neutral])
	main.on_rider_fitted()


# --- Flat ----------------------------------------------------------------------

func _flat_place(delta: float) -> void:
	if joy >= 0:
		var look := Vector2(Input.get_joy_axis(joy, JOY_AXIS_RIGHT_X), Input.get_joy_axis(joy, JOY_AXIS_RIGHT_Y))
		if look.length() > 0.2:
			yaw = clampf(yaw - look.x * 2.2 * delta, -2.6, 2.6)
			pitch = clampf(pitch - look.y * 1.5 * delta, -0.9, 0.7)
			look_idle = 0.0
	look_idle += delta
	if look_idle > 1.5:
		yaw = lerpf(yaw, 0.0, 1.0 - exp(-1.5 * delta))
		pitch = lerpf(pitch, 0.0, 1.0 - exp(-1.5 * delta))
	var d: Node3D = main.dragon
	var hands := Vector3(d.steer * 0.08, 0.0, -d.climb * 0.08)
	net_head = Transform3D(Basis.from_euler(Vector3(pitch * 0.6, yaw * 0.5, 0.0)), d.EYE)
	net_hl = Transform3D(Basis(), Vector3(-0.2, 0.33 - d.steer * 0.06, -0.32) + hands)
	net_hr = Transform3D(Basis(), Vector3(0.2, 0.33 + d.steer * 0.06, -0.32) + hands)
	_pose_figure()
	if camera != null:
		# Chase camera above and behind the deck, turning with the look offset.
		var dt: Transform3D = d.global_transform
		var orbit := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var pivot := dt * Vector3(0, 1.4, 1.0)
		var cam_pos := pivot + dt.basis * (orbit * Vector3(0, 1.9, 7.2))
		var look_at_pt := pivot + dt.basis * (orbit * Vector3(0, -0.6, -14.0))
		camera.global_position = cam_pos
		camera.look_at(look_at_pt, Vector3.UP)


# --- Ghost (TV machine) / shared ------------------------------------------------

func _ghost_place() -> void:
	_pose_figure()


func _pose_figure() -> void:
	var dt: Transform3D = main.dragon.global_transform
	head.global_transform = dt * net_head
	mitten_l.global_transform = dt * net_hl
	mitten_r.global_transform = dt * net_hr
	mitten_l.scale = Vector3(0.9, 0.75, 1.3)
	mitten_r.scale = Vector3(0.9, 0.75, 1.3)
	figure.global_transform = dt
	head.global_transform = dt * net_head
	_reins(mitten_l.global_position, mitten_r.global_position)


func _reins(pl: Vector3, pr: Vector3) -> void:
	var ring: Vector3 = main.dragon.global_transform * main.dragon.REINS_RING
	for pair in [[rein_l, pl], [rein_r, pr]]:
		var m: MeshInstance3D = pair[0]
		var p: Vector3 = pair[1]
		var d := p - ring
		var len := d.length()
		if len < 0.01:
			continue
		m.global_transform = Transform3D(main.basis_y_to(d / len) * Basis.from_scale(Vector3(1.0, len, 1.0)), (p + ring) * 0.5)


## Head and hands relative to the dragon, for the TV's ghost rider.
func net_pose() -> Array:
	if vr:
		var inv: Transform3D = main.dragon.global_transform.affine_inverse()
		return [inv * xr_camera.global_transform, inv * hand_l.global_transform, inv * hand_r.global_transform]
	return [net_head, net_hl, net_hr]


func apply_net_pose(a: Array) -> void:
	if a.size() < 3:
		return
	net_head = a[0]
	net_hl = a[1]
	net_hr = a[2]
