extends Node3D
## One kart: the VR player's (index 0), a TV player's (1-6) or a CPU buddy.
## Arcade driving without the physics engine: speed + yaw, the track keeps it between the walls,
## ramps launch it, bumps push it, nothing ever wrecks it.
## Who simulates it: local / host machine for its own karts and the CPUs; the TV machine for its own
## players (instant response). "remote" = a TV player's kart on the host (follows the positions the
## TV sends); "ghost" = a host kart drawn on the TV machine from snapshots.

const MAX_SPEED := 14.0
const ACCEL := 9.0
const BRAKE := 18.0
const REVERSE_MAX := 5.0
const COAST := 3.0
const TURN := 1.9
const BOOST_GAIN := 0.45
const R := 0.9
const GRAVITY := 24.0
const NO_KEYS := 99
const KEYS_WASD := 0  # split screen P1 (+ mouse)
const KEYS_ARROWS := 1  # split screen P2
const KEYS_BOTH := 2  # the TV machine's P2

var index := 0
var main
var color := Color.WHITE
var kart_name := "P1"
var cpu := false
var vr := false
var remote := false
var ghost := false
var active := false
var joy := -1
var key_set := NO_KEYS
var mouse_look := false
var bot := false  # tests: autopilot drives (also uses items and boost)
var camera: Camera3D
var hud: Control
var hud_label: Label
var place_label: Label
var item_label: Label
var hint_label: Label
var boost_fill: ColorRect
var pad_lost_t := -1.0
var net_started := false
var cockpit  # cockpit.gd when this kart is driven from VR (or fake VR in tests)
var hand_l: XRController3D  # for core/net.gd's wrist menu
var hand_r: XRController3D

# Driving state.
var speed := 0.0
var yaw := 0.0
var vy := 0.0
var on_ground := true
var air_t := 0.0
var steer_s := 0.0
var push_v := Vector3.ZERO
var hint := -1
var s := 0.0
var lat := 0.0
var road_h := 0.0
var tangent := Vector3.FORWARD
var total := 0.0  # distance raced since the start line (negative on the grid)
var finished := false
var finish_time := 0.0
var place := 1
var grid_slot := 0
var item := ""
var shield_t := 0.0
var boost_t := 0.0
var slip_t := 0.0
var charge := 0.3
var pad_cd := 0.0
var bump_cd := 0.0
var wall_cd := 0.0
var wrong_t := 0.0
var stuck_t := 0.0
var reverse_t := 0.0
var item_hold_t := 0.0
var cpu_lane := 0.0
var cpu_skill := 0.92
var hold_still := false  # on the grid before GO

# Input this frame.
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var want_item := false
var want_boost := false
var item_was := false
var boost_was := false
var mouse_dx := 0.0
var mouse_steer := 0.0

# Networking.
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var net_boost := false
var net_slip := false
var net_shield := false
var net_speed := 0.0
var net_steer := 0.0
var tp_guard := 0.0

# Visuals.
var body: Node3D
var driver: Node3D
var head: Node3D
var wheel_vis: MeshInstance3D
var wheels: Array[MeshInstance3D] = []
var bubble: MeshInstance3D
var flame: CPUParticles3D
var tag: Label3D
var spin_vis := 0.0
var wheel_roll := 0.0


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var paint: StandardMaterial3D = main.make_material(color, 0.15)
	var dark: StandardMaterial3D = main.make_material(Color(0.12, 0.12, 0.16), 0.0)
	var white: StandardMaterial3D = main.make_material(Color(0.97, 0.97, 1.0), 0.0)
	_mesh(body, main.box_mesh(Vector3(1.3, 0.32, 1.9)), paint, Vector3(0, 0.38, 0))
	var nose := _mesh(body, main.box_mesh(Vector3(1.0, 0.24, 0.7)), paint, Vector3(0, 0.42, -1.15))
	nose.rotation.x = -0.25
	_mesh(body, main.box_mesh(Vector3(1.5, 0.12, 0.35)), white, Vector3(0, 0.3, -1.45))  # bumper
	_mesh(body, main.box_mesh(Vector3(0.8, 0.5, 0.15)), dark, Vector3(0, 0.75, 0.62))  # seat back
	_mesh(body, main.box_mesh(Vector3(1.5, 0.12, 0.3)), paint.duplicate(), Vector3(0, 1.0, 1.0)).material_override = main.make_material(color.lightened(0.3), 0.3)  # spoiler
	for x in [-0.72, 0.72]:
		for z in [-0.75, 0.7]:
			var w := _mesh(body, main.cyl_mesh(0.3, 0.3, 0.26, 12), dark, Vector3(float(x), 0.3, float(z)))
			w.rotation.z = PI * 0.5
			wheels.append(w)
	driver = Node3D.new()
	body.add_child(driver)
	_mesh(driver, main.capsule_mesh(0.26, 0.7), paint, Vector3(0, 0.75, 0.35))
	head = Node3D.new()
	driver.add_child(head)
	head.position = Vector3(0, 1.25, 0.32)
	_mesh(head, main.sphere_mesh(0.24), white, Vector3.ZERO)
	_mesh(head, main.box_mesh(Vector3(0.36, 0.12, 0.08)), main.make_material(Color(0.2, 0.6, 1.0), 0.5), Vector3(0, 0.0, -0.21))
	_mesh(head, main.box_mesh(Vector3(0.06, 0.3, 0.42)), paint, Vector3(0, 0.12, 0.0))  # helmet stripe
	wheel_vis = _mesh(body, main.torus_mesh(0.13, 0.17), dark, Vector3(0, 0.95, -0.1))
	wheel_vis.rotation.x = deg_to_rad(55.0)
	bubble = _mesh(self, main.sphere_mesh(1.55), main.bubble_material(), Vector3(0, 0.75, 0))
	bubble.visible = false
	flame = CPUParticles3D.new()
	flame.amount = 16
	flame.lifetime = 0.35
	flame.direction = Vector3(0, 0.2, 1)
	flame.spread = 15.0
	flame.initial_velocity_min = 4.0
	flame.initial_velocity_max = 6.0
	flame.gravity = Vector3.ZERO
	flame.scale_amount_min = 0.6
	flame.scale_amount_max = 1.2
	flame.mesh = main.box_mesh(Vector3(0.18, 0.18, 0.18))
	flame.material_override = main.make_material(Color(1.0, 0.6, 0.15), 3.0)
	flame.position = Vector3(0, 0.5, 1.05)
	flame.emitting = false
	add_child(flame)
	tag = Label3D.new()
	tag.text = kart_name
	tag.font_size = 64
	tag.pixel_size = 0.012
	tag.outline_size = 16
	tag.modulate = color.lightened(0.35)
	tag.position = Vector3(0, 2.1, 0.3)
	tag.rotation.y = 0.0  # faces backwards (+Z): readable by whoever is chasing
	add_child(tag)
	visible = active


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
	visible = on


func is_local() -> bool:
	return not remote and not ghost and not cpu


func is_sim() -> bool:
	return not remote and not ghost


func is_human() -> bool:
	return not cpu


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Hide your own driver figure when you are sitting in it (VR).
func set_first_person(on: bool) -> void:
	driver.visible = not on
	wheel_vis.visible = not on
	tag.visible = not on


# --- Placement -------------------------------------------------------------------------

func place_at(pos: Vector3, y: float, new_total: float) -> void:
	position = pos
	yaw = y
	rotation = Vector3(0, yaw, 0)
	target_pos = pos
	target_yaw = y
	speed = 0.0
	vy = 0.0
	on_ground = true
	push_v = Vector3.ZERO
	total = new_total
	hint = -1
	tp_guard = 0.6
	_locate()


func reset_race() -> void:
	finished = false
	finish_time = 0.0
	item = ""
	shield_t = 0.0
	boost_t = 0.0
	slip_t = 0.0
	charge = 0.3
	wrong_t = 0.0
	stuck_t = 0.0
	reverse_t = 0.0
	spin_vis = 0.0


func _locate() -> void:
	var r: Array = main.track.locate(position, hint)
	hint = r[0]
	s = r[1]
	lat = r[2]
	road_h = r[3]
	tangent = r[4]


func track_progress_reset() -> void:
	_locate()


## Distance raced: follows s around the loop and counts laps.
func track_progress() -> void:
	var old_s := s
	_locate()
	var L: float = main.track.length
	var ds := s - old_s
	if ds < -L * 0.5:
		ds += L
	elif ds > L * 0.5:
		ds -= L
	total += ds


# --- Input -----------------------------------------------------------------------------

func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func read_input(delta: float) -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	var item_now := false
	var boost_now := false
	if cpu or bot or finished:
		_auto_drive(delta)
		return
	if cockpit != null:
		var c: Array = cockpit.read_input(delta)
		throttle = c[0]
		brake = c[1]
		steer = c[2]
		item_now = c[3]
		boost_now = c[4]
	else:
		if key_set == KEYS_WASD:
			throttle += _key(KEY_W)
			brake += _key(KEY_S)
			steer += _key(KEY_D) - _key(KEY_A)
			item_now = item_now or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E)
			boost_now = boost_now or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_Q)
			if not main.has_local_arrow_keys():
				throttle += _key(KEY_UP)
				brake += _key(KEY_DOWN)
				steer += _key(KEY_RIGHT) - _key(KEY_LEFT)
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				throttle += 1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.0
				item_now = item_now or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		elif key_set == KEYS_ARROWS:
			throttle += _key(KEY_UP)
			brake += _key(KEY_DOWN)
			steer += _key(KEY_RIGHT) - _key(KEY_LEFT)
			item_now = item_now or Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_SLASH)
			boost_now = boost_now or Input.is_physical_key_pressed(KEY_PERIOD)
		elif key_set == KEYS_BOTH:
			throttle += maxf(_key(KEY_W), _key(KEY_UP))
			brake += maxf(_key(KEY_S), _key(KEY_DOWN))
			steer += maxf(_key(KEY_D), _key(KEY_RIGHT)) - maxf(_key(KEY_A), _key(KEY_LEFT))
			item_now = item_now or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E)
			boost_now = boost_now or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_Q)
		if joy >= 0:
			var sx := Input.get_joy_axis(joy, JOY_AXIS_LEFT_X)
			if absf(sx) > 0.15:
				steer += sx
			if Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
				throttle += 1.0
			throttle += maxf(0.0, Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT))
			if Input.is_joy_button_pressed(joy, JOY_BUTTON_B):
				brake += 1.0
			brake += maxf(0.0, Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT))
			item_now = item_now or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER)
			boost_now = boost_now or Input.is_joy_button_pressed(joy, JOY_BUTTON_Y) or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
		if mouse_look:
			mouse_steer = clampf(mouse_steer + mouse_dx * 0.006, -1.0, 1.0)
			mouse_dx = 0.0
			mouse_steer = move_toward(mouse_steer, 0.0, 1.2 * delta)
			steer += mouse_steer
	throttle = clampf(throttle, 0.0, 1.0)
	brake = clampf(brake, 0.0, 1.0)
	steer = clampf(steer, -1.0, 1.0)
	want_item = item_now and not item_was
	want_boost = boost_now and not boost_was
	item_was = item_now
	boost_was = boost_now


func _input(event: InputEvent) -> void:
	if not mouse_look or not active:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_dx += mm.relative.x


## CPU buddies, finished karts and test bots: follow the track with a personal lane.
func _auto_drive(delta: float) -> void:
	auto_inputs(delta)
	want_item = false
	want_boost = false
	if finished:
		throttle *= 0.5
		return
	if cpu or bot:
		if item != "":
			item_hold_t += delta
			if item_hold_t > 1.5 + float(index % 3):
				want_item = true
				item_hold_t = 0.0
		if charge >= 1.0 and absf(steer) < 0.3:
			want_boost = true


## Steer towards a point a little way ahead on the track (shared with the fake-VR test).
func auto_inputs(delta: float) -> void:
	var ahead := 9.0 + absf(speed) * 0.5
	cpu_lane = sin(main.race_t * 0.25 + index * 1.7) * 2.2
	var p: Array = main.track.point_at(s + ahead, cpu_lane)
	var tp: Vector3 = p[0]
	var to := tp - position
	var want := atan2(-to.x, -to.z)
	var diff := wrapf(want - yaw, -PI, PI)
	steer = clampf(-diff * 2.2, -1.0, 1.0)
	throttle = 1.0
	brake = 0.0
	# Stuck against a wall (or facing backwards): back up for a moment.
	if reverse_t > 0.0:
		reverse_t -= delta
		throttle = 0.0
		brake = 1.0
		steer = -steer
		return
	if not hold_still and main.state == "race" and absf(speed) < 1.0:
		stuck_t += delta
		if stuck_t > 1.5:
			stuck_t = 0.0
			reverse_t = 0.9
	else:
		stuck_t = 0.0


# --- Simulation --------------------------------------------------------------------------

func sim(delta: float) -> void:
	if not active:
		return
	read_input(delta)
	bump_cd -= delta
	wall_cd -= delta
	pad_cd -= delta
	if hold_still:
		speed = 0.0
		_update_visual(delta)
		return
	shield_t = maxf(0.0, shield_t - delta)
	boost_t = maxf(0.0, boost_t - delta)
	if slip_t > 0.0:
		slip_t = maxf(0.0, slip_t - delta)
	if main.state == "race" and not finished:
		charge = minf(1.0, charge + delta / 14.0)
	if want_item and item != "":
		main.use_item(self)
	if want_boost and charge >= 1.0:
		charge = 0.0
		boost(1.6)
		main.on_boost(self, "BOOST!")
	var top: float = MAX_SPEED * float(main.rubber(self))
	if boost_t > 0.0:
		top *= 1.0 + BOOST_GAIN
	var thr := throttle
	if slip_t > 0.0:
		thr = 0.0
		speed = move_toward(speed, 0.0, 14.0 * delta)
	if thr > 0.05 and speed < top:
		speed = minf(top, speed + ACCEL * thr * (1.0 - 0.45 * maxf(0.0, speed) / top) * delta + (BRAKE * delta if speed < 0.0 else 0.0))
	elif speed > top:
		speed = move_toward(speed, top, 8.0 * delta)
	if brake > 0.05:
		if speed > 0.3:
			speed = maxf(0.0, speed - BRAKE * brake * delta)
		elif thr < 0.05:
			speed = maxf(-REVERSE_MAX, speed - 7.0 * brake * delta)
	if thr < 0.05 and brake < 0.05:
		speed = move_toward(speed, 0.0, COAST * delta)
	if boost_t > 0.0 and slip_t <= 0.0:
		speed = maxf(speed, top * 0.92)
	# Smooth, gentle turning (also comfy in VR).
	steer_s = move_toward(steer_s, steer, 5.0 * delta)
	var grip := clampf(absf(speed) / 5.0, 0.0, 1.0)
	var rate := TURN * steer_s * grip * (1.0 - 0.25 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
	if speed < 0.0:
		rate = -rate
	if not on_ground:
		rate *= 0.5
	yaw = wrapf(yaw - rate * delta, -PI, PI)
	var fwd := forward()
	position += fwd * speed * delta + push_v * delta
	push_v = push_v.move_toward(Vector3.ZERO, 14.0 * delta)
	var old_s := s
	_locate()
	var L: float = main.track.length
	var ds := s - old_s
	if ds < -L * 0.5:
		ds += L
	elif ds > L * 0.5:
		ds -= L
	total += ds
	# Walls: slide along them, never stop dead.
	var limit: float = main.track.wall_limit() - R * 0.7
	if absf(lat) > limit:
		var rt := Vector3(-tangent.z, 0.0, tangent.x)
		var sd := signf(lat)
		position -= rt * (absf(lat) - limit) * sd
		var into := fwd.dot(rt) * sd * signf(speed if absf(speed) > 0.01 else 1.0)
		if into > 0.0:
			var along := atan2(-tangent.x, -tangent.z)
			if fwd.dot(tangent) < 0.0:
				along = wrapf(along + PI, -PI, PI)
			yaw = lerp_angle(yaw, along, clampf(into * 0.5, 0.0, 0.5))
			var impact := absf(speed) * into
			speed *= 1.0 - 0.35 * into
			push_v -= rt * sd * minf(impact * 0.3, 3.0)
			if impact > 3.0 and wall_cd <= 0.0:
				wall_cd = 0.4
				main.on_wall(self, impact)
		lat = limit * sd
	# Ground, hills and ramps.
	var g: float = main.track.ground(s, lat, road_h)
	if on_ground:
		var predicted := position.y + vy * delta
		if main.track.at_ramp_lip(s, lat) and speed > 4.0 and g < predicted - 0.05:
			on_ground = false
			air_t = 0.0
			vy = maxf(vy, 5.0 + speed * 0.12)
		elif g < predicted - 0.35:
			on_ground = false
			air_t = 0.0
		else:
			vy = clampf((g - position.y) / maxf(delta, 0.001), -12.0, 12.0)
			position.y = g
	if not on_ground:
		air_t += delta
		vy -= GRAVITY * delta
		position.y += vy * delta
		if position.y <= g:
			position.y = g
			on_ground = true
			vy = 0.0
			main.on_land(self, air_t)
	if position.y < g - 3.0:
		position.y = g
	# Boost pads.
	if on_ground and pad_cd <= 0.0 and main.track.on_pad(s, lat):
		pad_cd = 0.8
		boost(1.2)
		main.on_boost(self, "")
	# Wrong way hint (for humans).
	if main.state == "race" and absf(speed) > 2.0 and fwd.dot(tangent) * signf(speed) < -0.3:
		wrong_t += delta
	else:
		wrong_t = maxf(0.0, wrong_t - delta * 2.0)
	_update_visual(delta)
	if main.net.mode == "client":
		main.net.send_state(position, yaw, speed + (1000.0 if boost_t > 0.0 else 0.0), index)


func boost(t: float) -> void:
	boost_t = maxf(boost_t, t)
	slip_t = 0.0


func slip() -> void:
	slip_t = 1.1
	speed *= 0.4
	boost_t = 0.0
	spin_vis = TAU


## Look: body spins on a banana (not the VR rider's view), wheels roll, flame on boost.
func _update_visual(delta: float) -> void:
	rotation = Vector3(0, yaw, 0)
	var slope := 0.0
	if on_ground:
		slope = clampf(vy / maxf(absf(speed), 2.0), -0.4, 0.4) * signf(speed if absf(speed) > 0.1 else 1.0)
	body.rotation.x = lerpf(body.rotation.x, slope, 1.0 - exp(-8.0 * delta))
	if spin_vis > 0.0:
		spin_vis = maxf(0.0, spin_vis - delta * TAU * 1.2)
	body.rotation.y = spin_vis if cockpit == null else sin(spin_vis * 3.0) * 0.06
	wheel_roll += speed * delta / 0.3
	for w in wheels:
		w.rotation = Vector3(-wheel_roll, 0, PI * 0.5)
	for k in 2:
		wheels[k * 2].rotation.y = steer_s * 0.4
	wheel_vis.rotation = Vector3(deg_to_rad(55.0), 0, 0)
	wheel_vis.rotate_object_local(Vector3.UP, steer_s * 1.4)
	bubble.visible = shield_t > 0.0
	if bubble.visible:
		bubble.rotation.y += delta
		var pulse := 1.0 + sin(main.race_t * 6.0) * 0.03
		bubble.scale = Vector3.ONE * pulse
	flame.emitting = boost_t > 0.0


## Host: a TV player's kart, following the positions the TV machine sends.
func apply_remote_state(pos: Vector3, y: float, p: float) -> void:
	if tp_guard > 0.0:
		return  # an old position from before a teleport
	target_pos = pos
	target_yaw = y
	net_boost = p > 500.0
	net_speed = p - 1000.0 if net_boost else p
	net_started = true


func follow_remote(delta: float) -> void:
	tp_guard -= delta
	if not active:
		return
	if position.distance_to(target_pos) > 8.0:
		position = target_pos
	else:
		position = position.lerp(target_pos, 1.0 - exp(-18.0 * delta))
	yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-18.0 * delta))
	speed = net_speed
	shield_t = maxf(0.0, shield_t - delta)
	slip_t = maxf(0.0, slip_t - delta)
	boost_t = 0.3 if net_boost else maxf(0.0, boost_t - delta)
	track_progress()
	_update_visual(delta)


## TV machine: a host kart (VR player / CPU) drawn from snapshots.
func follow_ghost(delta: float) -> void:
	if not active:
		return
	if position.distance_to(target_pos) > 8.0:
		position = target_pos
	else:
		position = position.lerp(target_pos, 1.0 - exp(-14.0 * delta))
	yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-14.0 * delta))
	speed = net_speed
	steer_s = lerpf(steer_s, net_steer, 1.0 - exp(-10.0 * delta))
	shield_t = 1.0 if net_shield else 0.0
	boost_t = 0.3 if net_boost else 0.0
	if net_slip and slip_t <= 0.0:
		slip_t = 1.0
		spin_vis = TAU
	elif not net_slip:
		slip_t = 0.0
	_locate()
	_update_visual(delta)


# --- Camera --------------------------------------------------------------------------------

func update_camera(delta: float) -> void:
	if camera == null or not active:
		return
	var fwd := forward()
	var want := position - fwd * 6.2 + Vector3(0, 2.6, 0)
	if not camera.has_meta("placed"):
		camera.set_meta("placed", true)
		camera.global_position = want
	camera.global_position = camera.global_position.lerp(want, 1.0 - exp(-7.0 * delta))
	var look := position + fwd * 4.0 + Vector3(0, 1.0, 0)
	if camera.global_position.distance_to(look) > 0.1:
		camera.look_at(look, Vector3.UP)
	var fov := 70.0 + (10.0 if boost_t > 0.0 else 0.0) + clampf(absf(speed) - 10.0, 0.0, 6.0)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-4.0 * delta))
