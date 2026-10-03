extends Node3D
## A tiny runner (TV players 2 to 7), third person: run, jump, reach the flag.
## Controller: left stick move, right stick turn the camera, A (or RB / RT) jump.
## Keyboard (P2 only): WASD move, Space jump, arrow keys or mouse turn the camera.
## Players 3-7: one controller each (press A on a spare controller to drop in).
## A runner's own movement is simulated on its own machine (instant); the host decides who has
## reached the flag. Hazards (falling, lava, water) send you back to your last safe spot.

const Art := preload("res://games/block_builders/art.gd")

const SPEED := 4.3
const JUMP_V := 7.6
const GRAVITY := 26.0
const STEP := 0.62
const HEIGHT := 0.9
const BODY_R := 0.28
const SPRING_V := 14.5
const COYOTE := 0.13
const JUMP_BUFFER := 0.15
const CAM_DIST := 5.2
const CAM_HEIGHT := 3.0
const KEYS := {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE, "turn_l": KEY_LEFT, "turn_r": KEY_RIGHT}

var main
var index := 1
var color := Color.WHITE
var joy := -1
var key_set := -1      # 0 = keyboard (P2 only), -1 = controller only
var mouse_on := false  # TV machine: the mouse turns P2's camera
var remote := false    # host: driven by the TV machine
var active := true
var claimed := false
var vr := false
var ghost := false

var finished := false  # at the flag (host decides; snapshots tell the TV)
var flag_sent := false
var face := -PI * 0.5
var cam_yaw := -PI * 0.5
var vy := 0.0
var on_ground := true
var air_t := 0.0
var jump_buf := 0.0
var jump_was := false
var bob_t := 0.0
var safe_pos := Vector3.ZERO
var safe_t := 0.0
var respawn_t := 0.0
var net_target := Vector3.ZERO
var net_started := false
var last_pos := Vector3.ZERO
var mouse_dx := 0.0
var bot_input := {}    # tests: {"move": Vector3, "jump": bool}
var level_seq_seen := -1

var camera: Camera3D
var hud_label: Label
var hint_label: Label
var pivot: Node3D
var body_mat: StandardMaterial3D
var tag: Label3D
var legs: Array = []


func _ready() -> void:
	add_to_group("runners")
	net_target = global_position
	safe_pos = global_position
	last_pos = global_position
	pivot = Node3D.new()
	add_child(pivot)
	body_mat = Art.mat(color, 0.0, 0.6)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 0.62
	cap.radial_segments = 12
	cap.rings = 3
	body.mesh = cap
	body.material_override = body_mat
	body.position.y = 0.42
	pivot.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = Art.sphere(0.2, 12)
	head.material_override = Art.mat(Color(1.0, 0.84, 0.68))
	head.position.y = 0.86
	pivot.add_child(head)
	var cap_m := MeshInstance3D.new()
	cap_m.mesh = Art.cyl(0.16, 0.22, 0.12, 12)
	cap_m.material_override = Art.mat(color.lightened(0.25), 0.3)
	cap_m.position = Vector3(0, 1.02, 0)
	pivot.add_child(cap_m)
	var visor := MeshInstance3D.new()
	visor.mesh = Art.box(Vector3(0.26, 0.03, 0.18))
	visor.material_override = cap_m.material_override
	visor.position = Vector3(0, 0.98, -0.2)
	pivot.add_child(visor)
	var eyes := MeshInstance3D.new()
	eyes.mesh = Art.box(Vector3(0.2, 0.06, 0.03))
	eyes.material_override = Art.mat(Color(0.08, 0.08, 0.12))
	eyes.position = Vector3(0, 0.88, -0.19)
	pivot.add_child(eyes)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = Art.box(Vector3(0.12, 0.22, 0.14))
		leg.material_override = Art.mat(color.darkened(0.35))
		leg.position = Vector3(side * 0.11, 0.11, 0)
		pivot.add_child(leg)
		legs.append(leg)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 30
	tag.outline_size = 10
	tag.modulate = color
	tag.position.y = 1.5
	tag.layers = Art.TV_LAYER
	add_child(tag)


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 400.0
	_update_camera(1.0)


func set_active(on: bool) -> void:
	active = on
	visible = on


# --- Input ---------------------------------------------------------------------

func _key(action: String) -> bool:
	if key_set != 0:
		return false
	return Input.is_physical_key_pressed(KEYS[action])


func _stick(ax: JoyAxis, ay: JoyAxis, dead: float) -> Vector2:
	if joy < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(joy, ax), Input.get_joy_axis(joy, ay))
	var l := v.length()
	if l < dead:
		return Vector2.ZERO
	return v / l * ((minf(l, 1.0) - dead) / (1.0 - dead))


func _joy_btn(b: JoyButton) -> bool:
	return joy >= 0 and Input.is_joy_button_pressed(joy, b)


func _input(event: InputEvent) -> void:
	var m := event as InputEventMouseMotion
	if m and mouse_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		mouse_dx += m.relative.x


func read_move(delta: float) -> Vector3:
	if not bot_input.is_empty():
		var bm: Vector3 = bot_input.get("move", Vector3.ZERO)
		return bm.limit_length(1.0)
	var turn := float(_key("turn_r")) - float(_key("turn_l"))
	cam_yaw -= turn * 2.4 * delta + mouse_dx * 0.004
	mouse_dx = 0.0
	var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15)
	cam_yaw -= look.x * absf(look.x) * 3.0 * delta
	var v := Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(float(_joy_btn(JOY_BUTTON_DPAD_RIGHT)) - float(_joy_btn(JOY_BUTTON_DPAD_LEFT)),
			float(_joy_btn(JOY_BUTTON_DPAD_DOWN)) - float(_joy_btn(JOY_BUTTON_DPAD_UP)))
	return Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)


func jump_held() -> bool:
	if not bot_input.is_empty():
		return bot_input.get("jump", false)
	return _key("jump") or _joy_btn(JOY_BUTTON_A) or _joy_btn(JOY_BUTTON_RIGHT_SHOULDER) \
		or (joy >= 0 and Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.5)


# --- Update ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active:
		return
	var course = main.course
	if course == null:
		return
	if remote:
		global_position = global_position.lerp(net_target, 1.0 - exp(-20.0 * delta))
		_animate(delta, (global_position - last_pos).length() / maxf(delta, 0.001), false)
		last_pos = global_position
		pivot.rotation.y = face
		return
	if finished:
		_celebrate(delta)
		main.net.send_state(global_position, face, cam_yaw, index)
		return
	if respawn_t > 0.0:
		respawn_t -= delta
		main.net.send_state(global_position, face, cam_yaw, index)
		return
	if main.state == "play" or main.state == "intro":
		_move(delta)
	main.net.send_state(global_position, face, cam_yaw, index)


func _move(delta: float) -> void:
	var course = main.course
	var move := read_move(delta)
	var pos := global_position
	var feet := pos.y
	var gust: Vector3 = course.gust_at(pos + Vector3.UP * 0.4, main.level_time)
	var vel := move * SPEED + gust
	# Horizontal: one axis at a time so you slide along walls.
	var already_stuck := _blocked(pos, feet)
	for axis in 2:
		var cand := pos
		if axis == 0:
			cand.x += vel.x * delta
		else:
			cand.z += vel.z * delta
		if already_stuck or not _blocked(cand, feet):
			pos = cand
	# Ground under us (anything we could step onto).
	var support := -INF
	var support_kind := ""
	for s in course.spans_at(pos.x, pos.z, BODY_R * 0.7):
		var top: float = s[1]
		if top <= feet + STEP and top > support:
			support = top
			support_kind = s[2]
	# Jumping (with a little coyote time and an input buffer, for small hands).
	var j := jump_held()
	if j and not jump_was:
		jump_buf = JUMP_BUFFER
	jump_was = j
	jump_buf -= delta
	air_t = 0.0 if on_ground else air_t + delta
	if jump_buf > 0.0 and air_t < COYOTE and vy <= 0.5:
		vy = JUMP_V
		on_ground = false
		air_t = COYOTE
		jump_buf = 0.0
		main.local_sound("jump", -10.0, 1.0 + index * 0.06)
	var hover: float = course.fan_hover(Vector3(pos.x, feet, pos.z))
	if hover > -INF:
		# Updraft: float up to the hover height.
		var want := clampf((hover - feet) * 2.5, -1.0, 6.0)
		vy = lerpf(vy, want, 1.0 - exp(-5.0 * delta))
		feet += vy * delta
		if feet < support:
			feet = support
		on_ground = false
		if not has_meta("fan_snd") or float(get_meta("fan_snd")) < Time.get_ticks_msec() / 1000.0:
			set_meta("fan_snd", Time.get_ticks_msec() / 1000.0 + 0.6)
			main.local_sound("whoosh", -12.0, 1.2)
	elif vy > 0.0 or feet > support + 0.02:
		vy -= GRAVITY * delta
		var nf := feet + vy * delta
		# Bonk on ceilings.
		if vy > 0.0:
			for s in course.spans_at(pos.x, pos.z, BODY_R * 0.6):
				var bottom: float = s[0]
				if bottom >= feet + HEIGHT - 0.05 and bottom < nf + HEIGHT:
					vy = 0.0
					nf = minf(nf, bottom - HEIGHT)
		if nf <= support and vy <= 0.0:
			nf = support
			if vy < -9.0:
				main.local_sound("land", -12.0, 1.0)
			vy = 0.0
			on_ground = true
		else:
			on_ground = false
		feet = nf
	else:
		feet = support
		vy = 0.0
		on_ground = true
	if on_ground and support_kind == "spring":
		vy = SPRING_V
		on_ground = false
		air_t = COYOTE
		main.runner_fx(index, "boing", Vector3(pos.x, feet, pos.z))
	pos.y = feet
	global_position = pos
	# Hazards.
	if on_ground and support_kind == "lava":
		_respawn("lava")
		return
	if feet < main.water_y - 0.15:
		_respawn("water")
		return
	if feet < course.KILL_Y:
		_respawn("fall")
		return
	if on_ground and support_kind != "lava":
		safe_t -= delta
		if safe_t <= 0.0:
			safe_t = 0.3
			if _is_safe_spot(pos):
				safe_pos = pos
	# The flag.
	var fp: Vector3 = course.flag_pos
	if not flag_sent and main.state == "play" and Vector2(pos.x - fp.x, pos.z - fp.z).length() < 1.0 and absf(feet - fp.y) < 1.2:
		flag_sent = true
		main.runner_at_flag(self)
	# Facing and a bit of bounce.
	if move.length() > 0.1:
		face = lerp_angle(face, atan2(-move.x, -move.z), 1.0 - exp(-14.0 * delta))
		if bot_input.is_empty() and absf(_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15).x) < 0.01 and mouse_dx == 0.0:
			cam_yaw = lerp_angle(cam_yaw, face, 1.0 - exp(-0.8 * delta))
	_animate(delta, move.length() * SPEED, not on_ground)
	pivot.rotation.y = face


## Solid in the way of our body (taller than a step)?
func _blocked(p: Vector3, feet: float) -> bool:
	for s in main.course.spans_at(p.x, p.z, BODY_R):
		var top: float = s[1]
		var bottom: float = s[0]
		if top > feet + STEP and bottom < feet + HEIGHT:
			return true
	return false


## A safe spot: on solid ground with ground also a little way around it (not right at an edge).
func _is_safe_spot(p: Vector3) -> bool:
	if p.y < main.water_y + 0.3:
		return false
	for d in [Vector2(0.45, 0), Vector2(-0.45, 0), Vector2(0, 0.45), Vector2(0, -0.45)]:
		var s: float = main.course.surface_below(p.x + d.x, p.z + d.y, p.y + 0.1, 0.05)
		if s < p.y - 0.3:
			return false
	return true


func _respawn(why: String) -> void:
	main.runner_fx(index, why, global_position)
	var course = main.course
	var at: Vector3 = start_spot()
	# Back to the last safe spot if it's still there (blocks can be moved, water rises).
	var still: float = course.surface_below(safe_pos.x, safe_pos.z, safe_pos.y + 0.1, 0.1)
	if absf(still - safe_pos.y) < 0.05 and safe_pos.y > main.water_y + 0.3 and why != "lava":
		at = safe_pos
	global_position = at + Vector3.UP * 0.02
	vy = 0.0
	on_ground = true
	respawn_t = 0.5
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.6, 0.8, 0.25)


func start_spot() -> Vector3:
	var s: Vector3 = main.course.start
	var k := index - 1
	return s + Vector3((k % 3 - 1) * 0.7, 0.0, (k / 3) * 0.7 - 0.35)


## New level (or retry): back to the start.
func reset_to_start() -> void:
	finished = false
	flag_sent = false
	global_position = start_spot()
	safe_pos = global_position
	net_target = global_position
	net_started = false
	vy = 0.0
	on_ground = true
	respawn_t = 0.0
	face = -PI * 0.5
	cam_yaw = -PI * 0.5
	pivot.rotation = Vector3(0, face, 0)
	if camera:
		_update_camera(1.0)


func _celebrate(delta: float) -> void:
	var fp: Vector3 = main.course.flag_pos
	var a := TAU * float(index) / 6.0
	var spot := fp + Vector3(cos(a) * 0.8, 0.0, sin(a) * 0.8)
	var p := global_position
	p.x = lerpf(p.x, spot.x, 1.0 - exp(-4.0 * delta))
	p.z = lerpf(p.z, spot.z, 1.0 - exp(-4.0 * delta))
	bob_t += delta
	p.y = fp.y + absf(sin(bob_t * 5.0 + index)) * 0.45
	global_position = p
	pivot.rotation.y += delta * 4.0
	face = pivot.rotation.y


func _animate(delta: float, speed: float, airborne: bool) -> void:
	if airborne:
		for i in legs.size():
			var leg: MeshInstance3D = legs[i]
			leg.rotation.x = 0.6 if i == 0 else -0.4
		pivot.position.y = 0.0
		return
	if speed > 0.5:
		bob_t += delta * 13.0
		for i in legs.size():
			var leg: MeshInstance3D = legs[i]
			leg.rotation.x = sin(bob_t + i * PI) * 0.7
		pivot.position.y = absf(sin(bob_t)) * 0.06
	else:
		for leg in legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
		pivot.position.y = 0.0


func _process(delta: float) -> void:
	_update_camera(delta)
	if hud_label:
		hud_label.text = "P%d" % (index + 1)
	if hint_label:
		var h := ""
		if finished:
			h = "YOU MADE IT!\nCheer on your friends!"
		elif respawn_t > 0.0:
			h = "Whoops! Try again!"
		hint_label.text = h


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target := global_position + Basis(Vector3.UP, cam_yaw) * Vector3(0.0, CAM_HEIGHT, CAM_DIST)
	var k := 1.0 - exp(-8.0 * delta)
	camera.global_position = camera.global_position.lerp(target, k) if delta < 0.5 else target
	var look := global_position + Vector3.UP * 0.9
	if camera.global_position.distance_to(look) > 0.1:
		camera.look_at(look, Vector3.UP)


# --- Network ---------------------------------------------------------------------

## Host: the TV says where this runner is.
func apply_remote_state(pos: Vector3, new_face: float, new_cam_yaw: float) -> void:
	net_target = pos
	face = new_face
	cam_yaw = new_cam_yaw
	if not net_started:
		net_started = true
		global_position = pos


func net_state() -> Array:
	if not active:
		return [false]
	return [global_position, face, active, finished]


## TV: the host's view of this runner (we drive our own position).
func apply_net_state(st: Array) -> void:
	if st.size() < 4:
		if active:
			set_active(false)
			main.on_player_activity_changed(self)
		return
	var act: bool = st[2]
	if act != active:
		set_active(act)
		if act:
			reset_to_start()
		main.on_player_activity_changed(self)
	var fin: bool = st[3]
	if fin and not finished:
		finished = true
	elif not fin and finished and not flag_sent:
		finished = false
