extends CharacterBody3D
## OBSTACLE RUSH: one wobbly jelly-bean runner. Run (stick) and jump (A). That's it.
## owned = true: simulated on this machine (a TV player's pad, or a CPU brain on the host); the inp_*
## fields drive it and movement is instant. owned = false: a puppet drawn from network updates.
## Never punishing: a bonk (a ball, the spinner, a fake door) is a short comical tumble, and falling
## off the course pops you back at the last checkpoint with a boing.
## The course (main.course) tells us about bounce pads, the spinner and checkpoints.

const RunnerLook := preload("res://games/obstacle_rush/runner_look.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const RUN_SPEED := 6.4
const ACCEL := 40.0
const AIR_ACCEL := 16.0
const JUMP_V := 8.6
const GRAVITY := 25.0
const COYOTE := 0.14
const JUMP_BUFFER := 0.16
const FALL_Y := -2.5  ## below this (relative to the lowest floor) you pop back
const TUMBLE_TIME := 0.7
const SAFE_AFTER := 1.0

var main: Node
var rid := 0  ## slot 0..6 for people, 10+ for CPU runners
var look := {}
var owned := true
var is_cpu := false
var speed_scale := 1.0  ## CPU runners are a little slower than people

var inp_move := Vector3.ZERO  ## world direction, length 0..1
var inp_jump := false  ## went down this tick (consumed)

var done := false
var checkpoint := 0  ## index into course.checkpoints
var tumble_t := 0.0
var safe_t := 0.0
var jumps := 0
var tumbles := 0
var events: Array = []  ## ["jump"] / ["land"] / ["fell"] / ["bonk"] / ["pad"] (main plays sounds)

var _air_t := 0.0
var _jump_buf := 0.0
var _was_floor := true
var _knock := Vector3.ZERO
var _spin := 0.0
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _anim_t := 0.0
var _squash := 0.0
var body: Node3D
var arms: Array[Node3D] = []
var feet: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RunnerLook.RADIUS
	cap.height = RunnerLook.HEIGHT
	shape.shape = cap
	shape.position.y = RunnerLook.HEIGHT * 0.5
	add_child(shape)
	body = Node3D.new()
	add_child(body)
	var col: Color = look.get("color", Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.mesh = RunnerLook.body_mesh(col, String(look.get("costume", "party_hat")), String(look.get("pattern", "plain")))
	mi.material_override = _mat()
	body.add_child(mi)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var arm := MeshInstance3D.new()
		arm.mesh = RunnerLook.arm_mesh(col)
		arm.material_override = mi.material_override
		arm.position = Vector3(s * (RunnerLook.RADIUS + 0.02), 0.62, 0.0)
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(arm)
		arms.append(arm)
		var foot := MeshInstance3D.new()
		foot.mesh = RunnerLook.foot_mesh(col)
		foot.material_override = mi.material_override
		foot.position = Vector3(s * 0.15, 0.0, 0.0)
		foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(foot)
		feet.append(foot)
	_target = position


static func _mat() -> Material:
	return MeshKit.vertex_material()


## Put the runner somewhere (start, checkpoint, finish), facing +X (the course's way).
func place(p: Vector3) -> void:
	position = p
	_target = p
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	tumble_t = 0.0
	rotation.y = -PI * 0.5
	_target_yaw = rotation.y


## A comical bonk: hop up and tumble away from `dir` for a moment (owned runners only).
func bonk(dir: Vector3, strength: float = 1.0) -> void:
	if not owned or safe_t > 0.0 or done:
		return
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.LEFT
	_knock = dir * 6.0 * strength
	velocity.y = 6.5 * strength
	tumble_t = TUMBLE_TIME
	safe_t = SAFE_AFTER + TUMBLE_TIME
	tumbles += 1
	events.append(["bonk"])


## A little hop (the giant's finger boop).
func boop() -> void:
	if owned and is_on_floor() and not done:
		velocity.y = 5.0
		_squash = 1.0
		events.append(["boop"])


func step(delta: float) -> void:
	if not owned:
		return
	var c = main.course
	tumble_t = maxf(0.0, tumble_t - delta)
	safe_t = maxf(0.0, safe_t - delta)
	var mv := inp_move if tumble_t <= 0.0 and not done else Vector3.ZERO
	if inp_jump:
		_jump_buf = JUMP_BUFFER
	inp_jump = false
	_jump_buf -= delta
	var on_floor := is_on_floor()
	_air_t = 0.0 if on_floor else _air_t + delta
	var want := mv * RUN_SPEED * speed_scale
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var acc := ACCEL if on_floor else AIR_ACCEL
	if tumble_t > 0.0:
		h = h.move_toward(_knock, 30.0 * delta)
	else:
		h = h.move_toward(want, acc * delta)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y -= GRAVITY * delta
	if _jump_buf > 0.0 and _air_t < COYOTE and tumble_t <= 0.0 and not done:
		velocity.y = JUMP_V
		_jump_buf = 0.0
		_air_t = COYOTE
		jumps += 1
		_squash = 0.6
		events.append(["jump"])
	if on_floor and tumble_t <= 0.0:
		var pad: Vector3 = c.pad_launch(position)
		if pad != Vector3.ZERO:
			velocity = pad
			_squash = 1.0
			events.append(["pad"])
	velocity.y = maxf(velocity.y, -30.0)
	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var o := col.get_collider()
		if o is Node and (o as Node).has_meta("fake_door") and safe_t <= 0.0:
			bonk(Vector3.LEFT, 0.9)
			events.append(["fake", int((o as Node).get_meta("fake_door"))])
	if is_on_floor() and not _was_floor:
		_squash = 0.5
		events.append(["land"])
	_was_floor = is_on_floor()
	if tumble_t <= 0.0 and safe_t <= 0.0 and not done:
		var hit: Vector3 = c.hazard_hit(position)
		if hit != Vector3.ZERO:
			bonk(hit, 1.0)
	checkpoint = c.checkpoint_for(position, checkpoint)
	if position.y < c.low_y + FALL_Y:
		place(c.checkpoint_spot(checkpoint, rid))
		safe_t = SAFE_AFTER
		_squash = 1.0
		events.append(["fell"])
	if Vector2(h.x, h.z).length() > 0.5 and tumble_t <= 0.0:
		var yaw := atan2(-h.x, -h.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-14.0 * delta))


## Puppets: glide towards the last network position.
func set_remote(p: Vector3, yaw: float, state: int) -> void:
	_target = p
	_target_yaw = yaw
	tumble_t = TUMBLE_TIME if state == 1 else 0.0
	if position.distance_to(p) > 4.0:
		position = p


## Every machine: the wobble, run cycle, squash and tumble spin.
func animate(delta: float) -> void:
	if not owned:
		var prev := position
		position = position.lerp(_target, 1.0 - exp(-16.0 * delta))
		rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-12.0 * delta))
		velocity = (position - prev) / maxf(delta, 0.001)
	var speed := Vector2(velocity.x, velocity.z).length()
	_anim_t += delta * (4.0 + speed * 1.6)
	_squash = maxf(0.0, _squash - delta * 3.0)
	var sq := sin(_squash * PI) * 0.18 * _squash
	var bob := absf(sin(_anim_t)) * 0.06 * clampf(speed / RUN_SPEED, 0.0, 1.0)
	if tumble_t > 0.0:
		_spin += delta * 14.0
	else:
		_spin = lerpf(_spin, roundf(_spin / TAU) * TAU, 1.0 - exp(-10.0 * delta))
	body.position.y = bob
	body.rotation = Vector3(_spin, 0.0, sin(_anim_t * 0.5) * 0.08 * clampf(speed / RUN_SPEED, 0.0, 1.0))
	body.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq)
	var swing := sin(_anim_t) * 0.9 * clampf(speed / RUN_SPEED, 0.0, 1.0)
	if done:
		swing = 0.0
		body.position.y = absf(sin(_anim_t * 0.6)) * 0.35  # happy bounce at the finish
		for a in arms:
			a.rotation.z = (-2.6 if a == arms[0] else 2.6) + sin(_anim_t * 1.2) * 0.3
	else:
		arms[0].rotation = Vector3(swing, 0.0, -0.25)
		arms[1].rotation = Vector3(-swing, 0.0, 0.25)
	feet[0].position.z = sin(_anim_t) * 0.18 * clampf(speed / RUN_SPEED, 0.0, 1.0)
	feet[1].position.z = -feet[0].position.z
