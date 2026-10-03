extends Node3D
## One kart: the VR player's (index 0), a TV player's (1-6) or a CPU buddy.
## Arcade driving without the physics engine: speed + yaw, the track keeps it between the walls,
## ramps launch it, bumps push it, nothing ever wrecks it.
## Who simulates it: local / host machine for its own karts and the CPUs; the TV machine for its own
## players (instant response). "remote" = a TV player's kart on the host (follows the positions the
## TV sends); "ghost" = a host kart drawn on the TV machine from snapshots.
## DRIFT: TV karts hold the drift button (B / RB, or brake key) in a fast turn and slide; the VR kart,
## CPUs and bots drift automatically by holding a hard turn (no sideways slide for the VR rider). Sparks
## charge blue -> orange -> pink; straighten up for a MINI-TURBO. ROCKET START: press go during the
## countdown (after the second red light) for a boost at GO.
## VR comfort: the VR kart's speed changes are rate-limited (no jolts from bananas, walls or boosts),
## wall nudges turn it gently, bumps push it softly and ramps toss it less.

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
const DRIFT_LEVELS: Array[float] = [0.7, 1.5, 2.4]  # seconds of drifting for blue / orange / pink sparks
const TURBO_TIME: Array[float] = [0.55, 0.9, 1.3]
const SPARK_COLORS: Array[Color] = [Color(0.9, 0.9, 0.9), Color(0.3, 0.7, 1.0), Color(1.0, 0.6, 0.15), Color(1.0, 0.35, 0.9)]
const VR_DECEL := 15.0  # m/s/s: the most the VR kart's speed may drop per second
const VR_ACCEL := 11.0

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
var drift_fill: ColorRect
var minimap: Control
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
var item_count := 0  # the triple mushroom has three goes
var shield_t := 0.0
var boost_t := 0.0
var slip_t := 0.0
var star_t := 0.0
var wobble_t := 0.0
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
var start_hold_t := 0.0
var drift_t := 0.0
var drift_level := 0
var drift_dir := 0
var drift_vis := 0.0
var drift_off_t := 0.0

# Race stats (host), for the fun awards.
var st_air := 0
var st_turbo := 0
var st_items := 0
var st_walls := 0
var st_hits := 0
var st_bumps := 0
var worst_place := 1

# Input this frame.
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var drift_btn := false
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
var net_star := false
var net_speed := 0.0
var net_steer := 0.0
var net_drift := 0
var net_drift_dir := 0
var tp_guard := 0.0

# Visuals.
var body: Node3D
var body_mat: StandardMaterial3D
var driver: Node3D
var head: Node3D
var wheel_vis: MeshInstance3D
var wheels_mm: MultiMesh
var bubble: MeshInstance3D
var flame: CPUParticles3D
var sparks: CPUParticles3D
var spark_level := -1
var tag: Label3D
var spin_vis := 0.0
var wheel_roll := 0.0


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	body_mat = StandardMaterial3D.new()
	body_mat.vertex_color_use_as_albedo = true
	body_mat.vertex_color_is_srgb = true
	body_mat.roughness = 0.45
	body_mat.metallic = 0.1
	var bm := MeshInstance3D.new()
	bm.mesh = main.kart_body_mesh(color)
	bm.material_override = body_mat
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(bm)
	# Four wheels in one MultiMesh (tyre + coloured hub), turned and rolled every frame.
	wheels_mm = MultiMesh.new()
	wheels_mm.transform_format = MultiMesh.TRANSFORM_3D
	wheels_mm.mesh = main.wheel_mesh()
	wheels_mm.instance_count = 4
	var wmi := MultiMeshInstance3D.new()
	wmi.multimesh = wheels_mm
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.vertex_color_is_srgb = true
	wm.roughness = 0.8
	wmi.material_override = wm
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(wmi)
	driver = Node3D.new()
	body.add_child(driver)
	var dm := MeshInstance3D.new()
	dm.mesh = main.driver_mesh(color)
	dm.material_override = body_mat
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	driver.add_child(dm)
	head = Node3D.new()
	driver.add_child(head)
	head.position = Vector3(0, 1.25, 0.32)
	var hm := MeshInstance3D.new()
	hm.mesh = main.helmet_mesh(color)
	hm.material_override = body_mat
	hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(hm)
	wheel_vis = _mesh(body, main.torus_mesh(0.13, 0.17), main.make_material(Color(0.12, 0.12, 0.16), 0.0), Vector3(0, 0.95, -0.1))
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
	flame.position = Vector3(0, 0.5, 1.15)
	flame.emitting = false
	add_child(flame)
	sparks = CPUParticles3D.new()
	sparks.amount = 18
	sparks.lifetime = 0.3
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.75, 0.02, 0.05)
	sparks.direction = Vector3(0, 0.6, 1)
	sparks.spread = 40.0
	sparks.initial_velocity_min = 2.5
	sparks.initial_velocity_max = 4.5
	sparks.gravity = Vector3(0, -9.0, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	sparks.mesh = main.box_mesh(Vector3(0.07, 0.07, 0.07))
	sparks.position = Vector3(0, 0.12, 0.75)
	sparks.emitting = false
	body.add_child(sparks)
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


## Auto-drift: the VR kart, CPUs and bots drift by holding a hard turn (no button needed).
func auto_drift() -> bool:
	return cockpit != null or cpu or bot


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
	if cockpit != null:
		cockpit.fade()  # a teleport in VR: blink rather than jump


func reset_race() -> void:
	finished = false
	finish_time = 0.0
	item = ""
	item_count = 0
	shield_t = 0.0
	boost_t = 0.0
	slip_t = 0.0
	star_t = 0.0
	wobble_t = 0.0
	charge = 0.3
	wrong_t = 0.0
	stuck_t = 0.0
	reverse_t = 0.0
	spin_vis = 0.0
	start_hold_t = 0.0
	drift_t = 0.0
	drift_level = 0
	drift_dir = 0
	st_air = 0
	st_turbo = 0
	st_items = 0
	st_walls = 0
	st_hits = 0
	st_bumps = 0
	worst_place = 1


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
	drift_btn = false
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
			drift_btn = Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
			item_now = item_now or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER)
			boost_now = boost_now or Input.is_joy_button_pressed(joy, JOY_BUTTON_Y)
		if mouse_look:
			mouse_steer = clampf(mouse_steer + mouse_dx * 0.006, -1.0, 1.0)
			mouse_dx = 0.0
			mouse_steer = move_toward(mouse_steer, 0.0, 1.2 * delta)
			steer += mouse_steer
		# Braking in a fast turn is a drift (kids find it on their own); RB drifts too.
		drift_btn = drift_btn or brake > 0.5
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
		# Rocket start: press go on the last red light (holding the whole countdown does nothing).
		if throttle > 0.5:
			start_hold_t += delta
		else:
			start_hold_t = 0.0
		_update_visual(delta)
		return
	var prev_speed := speed
	shield_t = maxf(0.0, shield_t - delta)
	boost_t = maxf(0.0, boost_t - delta)
	star_t = maxf(0.0, star_t - delta)
	wobble_t = maxf(0.0, wobble_t - delta)
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
	if star_t > 0.0:
		top *= 1.2
	if wobble_t > 0.0:
		top *= 0.72
	var thr := throttle
	if slip_t > 0.0:
		thr = 0.0
		speed = move_toward(speed, 0.0, 14.0 * delta)
	_drift(delta)
	var brk := brake if drift_t <= 0.0 else 0.0
	if thr > 0.05 and speed < top:
		speed = minf(top, speed + ACCEL * thr * (1.0 - 0.45 * maxf(0.0, speed) / top) * delta + (BRAKE * delta if speed < 0.0 else 0.0))
	elif speed > top:
		speed = move_toward(speed, top, 8.0 * delta)
	if brk > 0.05:
		if speed > 0.3:
			speed = maxf(0.0, speed - BRAKE * brk * delta)
		elif thr < 0.05:
			speed = maxf(-REVERSE_MAX, speed - 7.0 * brk * delta)
	if thr < 0.05 and brk < 0.05:
		speed = move_toward(speed, 0.0, COAST * delta)
	if (boost_t > 0.0 or star_t > 0.0) and slip_t <= 0.0:
		speed = maxf(speed, top * 0.92)
	# Smooth, gentle turning (also comfy in VR); a drift tightens the turn.
	steer_s = move_toward(steer_s, steer, 5.0 * delta)
	var grip := clampf(absf(speed) / 5.0, 0.0, 1.0)
	var rate := TURN * steer_s * grip * (1.0 - 0.25 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
	if drift_t > 0.0 and not auto_drift():
		rate = TURN * grip * (float(drift_dir) * 0.55 + steer_s * 0.6)  # always curving into the drift
	if speed < 0.0:
		rate = -rate
	if not on_ground:
		rate *= 0.5
	yaw = wrapf(yaw - rate * delta, -PI, PI)
	var fwd := forward()
	if cockpit != null:
		speed = clampf(speed, prev_speed - VR_DECEL * delta, prev_speed + VR_ACCEL * delta)  # no jolts in VR
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
			# VR: turn along the wall gently over a few frames instead of snapping the view round.
			var w := clampf(into * 0.5, 0.0, 0.5) if cockpit == null else clampf(into * 3.0 * delta, 0.0, 0.06)
			yaw = lerp_angle(yaw, along, w)
			var impact := absf(speed) * into
			var loss := absf(speed) * 0.35 * into
			if cockpit != null:
				loss = minf(loss, VR_DECEL * delta)
			speed -= signf(speed) * loss
			push_v -= rt * sd * minf(impact * 0.3, 3.0) * (0.35 if cockpit != null else 1.0)
			if impact > 3.0 and wall_cd <= 0.0:
				wall_cd = 0.4
				st_walls += 1
				main.on_wall(self, impact)
		lat = limit * sd
	# Ground, hills and ramps.
	var g: float = main.track.ground(s, lat, road_h)
	if on_ground:
		var predicted := position.y + vy * delta
		if main.track.at_ramp_lip(s, lat) and speed > 4.0 and g < predicted - 0.05:
			on_ground = false
			air_t = 0.0
			vy = maxf(vy, (5.0 + speed * 0.12) * (0.65 if cockpit != null else 1.0))  # a softer hop for the VR rider
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
			if air_t > 0.4:
				st_air += 1
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
		main.net.send_state(position, yaw, speed + 1000.0 * float(net_code()), index)


## Boost / drift / star flags packed into the number the TV sends alongside the speed.
func net_code() -> int:
	return (1 if boost_t > 0.0 else 0) + 2 * drift_level + (8 if drift_dir > 0 else 0) + (16 if star_t > 0.0 else 0) \
		+ (32 if drift_t > 0.0 else 0)


## Drifting: charge sparks while sliding round a bend, release for a mini-turbo.
func _drift(delta: float) -> void:
	var going := false
	if on_ground and speed > 6.5 and slip_t <= 0.0 and main.state == "race":
		if auto_drift():
			going = absf(steer_s) > (0.42 if drift_t > 0.0 else 0.52) and (drift_t > 0.0 or speed > 7.5)
		else:
			going = drift_btn and (drift_t > 0.0 or absf(steer) > 0.35)
	if going:
		drift_off_t = 0.0
		if drift_t <= 0.0:
			drift_dir = 1 if (steer if not auto_drift() else steer_s) > 0.0 else -1
			main.on_drift_start(self)
		drift_t += delta * (0.8 + 0.5 * absf(steer))
		var lvl := 0
		for i in DRIFT_LEVELS.size():
			if drift_t >= DRIFT_LEVELS[i]:
				lvl = i + 1
		if lvl > drift_level:
			drift_level = lvl
			main.on_drift_level(self, lvl)
	elif drift_t > 0.0:
		# A little grace so a wobble of the wheel doesn't cancel a long drift.
		drift_off_t += delta
		if drift_off_t > (0.18 if auto_drift() else 0.05) or speed < 4.0:
			if drift_level > 0:
				boost(TURBO_TIME[drift_level - 1])
				st_turbo += 1
				main.on_mini_turbo(self, drift_level)
			drift_t = 0.0
			drift_level = 0
			drift_dir = 0


## At GO: a boost if go was pressed at the right moment.
func try_rocket_start() -> bool:
	var ok := start_hold_t > 0.05 and start_hold_t < 1.45
	if cpu:
		ok = randf() < 0.4
	start_hold_t = 0.0
	if ok:
		boost(1.3)
	return ok


func boost(t: float) -> void:
	boost_t = maxf(boost_t, t)
	slip_t = 0.0


func slip() -> void:
	slip_t = 1.1
	if cockpit == null:
		speed *= 0.4  # the VR kart slows smoothly instead (sim eases it down while slipping)
	boost_t = 0.0
	drift_t = 0.0
	drift_level = 0
	spin_vis = TAU


## Honked at: a silly wobble that slows you for a moment.
func wobble() -> void:
	wobble_t = 0.9


## Look: body spins on a banana (not the VR rider's view), wheels roll, flame on boost, drift sparks.
func _update_visual(delta: float) -> void:
	rotation = Vector3(0, yaw, 0)
	var slope := 0.0
	if on_ground:
		slope = clampf(vy / maxf(absf(speed), 2.0), -0.4, 0.4) * signf(speed if absf(speed) > 0.1 else 1.0)
	body.rotation.x = lerpf(body.rotation.x, slope, 1.0 - exp(-8.0 * delta))
	if spin_vis > 0.0:
		spin_vis = maxf(0.0, spin_vis - delta * TAU * 1.2)
	var ddir := drift_dir if not ghost else net_drift_dir
	drift_vis = lerpf(drift_vis, float(ddir) * 0.38 if cockpit == null else 0.0, 1.0 - exp(-8.0 * delta))
	if cockpit == null:
		body.rotation.y = spin_vis + drift_vis
		body.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.12 if wobble_t > 0.0 else 0.0
	else:
		body.rotation.y = sin(spin_vis * 3.0) * 0.06
	wheel_roll += speed * delta / 0.3
	var wheel_pos: Array[Vector3] = [Vector3(-0.72, 0.3, -0.75), Vector3(0.72, 0.3, -0.75), Vector3(-0.72, 0.3, 0.7), Vector3(0.72, 0.3, 0.7)]
	for i in 4:
		var b := Basis(Vector3.UP, steer_s * 0.4 if i < 2 else 0.0) * Basis(Vector3.RIGHT, -wheel_roll)
		if i % 2 == 0:
			b = b * Basis(Vector3.UP, PI)  # hubs face outwards on both sides
		wheels_mm.set_instance_transform(i, Transform3D(b, wheel_pos[i]))
	wheel_vis.rotation = Vector3(deg_to_rad(55.0), 0, 0)
	wheel_vis.rotate_object_local(Vector3.UP, steer_s * 1.4)
	bubble.visible = shield_t > 0.0
	if bubble.visible:
		bubble.rotation.y += delta
		var pulse := 1.0 + sin(main.race_t * 6.0) * 0.03
		bubble.scale = Vector3.ONE * pulse
	flame.emitting = boost_t > 0.0
	var lvl := drift_level if not ghost else net_drift
	var sliding := (drift_t > 0.0) if not ghost else net_drift_dir != 0
	sparks.emitting = sliding and on_ground
	if sliding and lvl != spark_level:
		spark_level = lvl
		sparks.material_override = main.make_material(SPARK_COLORS[clampi(lvl, 0, 3)], 3.0)
		sparks.amount = 10 if lvl == 0 else 18
	# Rainbow star: the paint glows through the colours.
	var starring := star_t > 0.0 if not ghost else net_star
	if starring:
		body_mat.emission_enabled = true
		body_mat.emission = Color.from_hsv(fmod(Time.get_ticks_msec() * 0.0015, 1.0), 0.8, 1.0)
		body_mat.emission_energy_multiplier = 1.4
	elif body_mat.emission_enabled:
		body_mat.emission_enabled = false


## Host: a TV player's kart, following the positions the TV machine sends.
func apply_remote_state(pos: Vector3, y: float, p: float) -> void:
	if tp_guard > 0.0:
		return  # an old position from before a teleport
	target_pos = pos
	target_yaw = y
	var code := int(floorf((p + 500.0) / 1000.0))
	net_speed = p - 1000.0 * code
	net_boost = code & 1 != 0
	net_drift = (code >> 1) & 3
	net_drift_dir = (1 if code & 8 != 0 else -1) if code & 32 != 0 else 0
	net_star = code & 16 != 0
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
	star_t = 0.3 if net_star else maxf(0.0, star_t - delta)
	wobble_t = maxf(0.0, wobble_t - delta)
	boost_t = 0.3 if net_boost else maxf(0.0, boost_t - delta)
	drift_level = net_drift
	drift_dir = net_drift_dir
	drift_t = 0.5 if drift_dir != 0 else 0.0
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
