extends CharacterBody3D
## SKY BOTS: one little tin robot with a propeller cap. Run (stick), jump (A), hold A while falling to hover on the
## propeller, punch (X). In the air X is a DASH punch (once a jump) and B a GROUND POUND (straight down: a thump that
## pops grumbles and opens bot boxes). Springs throw it up, belts carry it, fans float it. It may wear a costume HAT
## (hats.gd, unlocked by rescuing little bots).
## owned = true: simulated on this machine (a TV / Deck player's pad, or a CPU buddy on the host); inp_* drive it and
## movement is instant. owned = false: a puppet drawn from network updates.
## Never punishing: a bump (a grumble, a zap, the crab's stomp) is a short comical tumble, and falling off pops you
## back at your last checkpoint flag with a boing.

const G := preload("res://games/sky_bots/levelgen.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Contrast := preload("res://core/contrast.gd")
const Hats := preload("res://games/sky_bots/hats.gd")

const COYOTE := 0.12
const JUMP_BUFFER := 0.15
const BUMP_TIME := 0.55
const SAFE_AFTER := 1.0
const PUNCH_TIME := 0.25
const PUNCH_COOL := 0.4
const PUNCH_REACH := 1.25  ## a punch hits things this far in front of the robot's middle
const METAL := Color(0.86, 0.89, 0.93)
const SCREEN := Color(0.1, 0.14, 0.22)
const EYE := Color(0.45, 1.0, 0.95)
const OUTLINE := Contrast.OUTLINE
## CPU buddies (solo VR: the giant plays with BIP and BOP).
const CPU_NAMES: Array[String] = ["BIP", "BOP", "BEEP"]
const CPU_COLORS: Array[Color] = [Color(0.55, 0.95, 0.45), Color(1.0, 0.55, 0.3), Color(0.75, 0.6, 1.0)]

var main: Node
var rid := 0  ## slot 0..6 for people, 10+ for CPU buddies
var color := Color.WHITE
var owned := true
var is_cpu := false

var inp_move := Vector3.ZERO  ## world direction, length 0..1
var inp_jump := false  ## A went down (consumed)
var inp_hold := false  ## A held (hover)
var inp_punch := false  ## X went down (consumed): a punch; in the air a DASH (once a jump)
var inp_pound := false  ## B went down (consumed): in the air a GROUND POUND
var hat := 0  ## the costume hat this robot wears (Hats.LIST index; 0 none)

var checkpoint := 0
var bump_t := 0.0
var safe_t := 0.0
var punch_t := 0.0
var punch_cd := 0.0
var hover_t := 0.0
var hovering := false
var dashed := false  ## used this jump's dash
var pounding := false
var dash_t := 0.0
var jumps := 0
var punches := 0
var dashes := 0
var pounds := 0
var events: Array = []  ## ["jump"] ["land"] ["fell"] ["bump"] ["punch", point] ["hover"] ["spring"] ["dash"] ["pound", point]
## (main plays sounds / hits)
var hat_node: Node3D
var _hat_shown := -1

var _air_t := 0.0
var _jump_buf := 0.0
var _was_floor := true
var _knock := Vector3.ZERO
var _spin := 0.0
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _anim_t := 0.0
var _squash := 0.0
var _prop_a := 0.0
var _remote_state := 0
var body: Node3D
var prop: Node3D
var arms: Array[Node3D] = []
var feet: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = G.ROBOT_R
	cap.height = G.ROBOT_H
	shape.shape = cap
	shape.position.y = G.ROBOT_H * 0.5
	add_child(shape)
	body = Node3D.new()
	add_child(body)
	var mat := MeshKit.vertex_material()
	var mi := MeshKit.instance(body_mesh(color), false)
	mi.material_override = null
	Contrast.outline(mi, OUTLINE)
	body.add_child(mi)
	prop = Node3D.new()
	prop.position = Vector3(0.0, 1.16, 0.0)
	body.add_child(prop)
	var pb := MeshKit.Builder.new()
	pb.cylinder(0.03, 0.03, 0.12, MeshKit.at(Vector3(0, -0.06, 0)), METAL.darkened(0.3), 6)
	for k in 3:
		var a := TAU * k / 3.0
		pb.box(Vector3(0.36, 0.025, 0.09), MeshKit.at(Vector3(cos(a) * 0.18, 0.0, sin(a) * 0.18), Vector3.ONE, Vector3(0, -a, 0.25)), color.lightened(0.25))
	pb.sphere(0.05, MeshKit.at(Vector3(0, 0.02, 0)), Color(1.0, 0.85, 0.3), 8)
	var pm := MeshKit.instance(pb.build(), false)
	prop.add_child(pm)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var arm := Node3D.new()
		arm.position = Vector3(s * 0.33, 0.6, 0.0)
		body.add_child(arm)
		var ab := MeshKit.Builder.new()
		ab.capsule(0.06, 0.3, MeshKit.at(Vector3(0, -0.12, 0)), METAL.darkened(0.15), 8)
		ab.sphere(0.1, MeshKit.at(Vector3(0, -0.28, 0)), color, 10)
		var am := MeshKit.instance(ab.build(), false)
		Contrast.outline(am, OUTLINE)
		arm.add_child(am)
		arms.append(arm)
		var foot := MeshKit.instance(_foot_mesh(), false)
		foot.position = Vector3(s * 0.14, 0.0, 0.0)
		add_child(foot)
		feet.append(foot)
	hat_node = Node3D.new()
	hat_node.position = Vector3(0.0, 1.05, 0.0)
	body.add_child(hat_node)
	show_hat(hat)
	_target = position
	if mat == null:
		pass


## Put on hat h (Hats.LIST index; 0 = none: the propeller cap shows).
func show_hat(h: int) -> void:
	hat = h
	if hat_node == null or h == _hat_shown:
		return
	_hat_shown = h
	for c in hat_node.get_children():
		c.queue_free()
	if h > 0:
		var mi := MeshKit.instance(Hats.mesh(h), false)
		Contrast.outline(mi, OUTLINE)
		hat_node.add_child(mi)
	if prop != null:
		prop.position.y = 1.16 + Hats.lift(h)


## The robot's body and head in one mesh (front = +Z): a rounded tin body in the player's colour, a silver head with
## a dark screen face and two glowing eyes, an antenna with a bulb.
static func body_mesh(col: Color) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.56, 0.48, 0.46), 0.12, MeshKit.at(Vector3(0, 0.42, 0)), col)
	b.rounded_box(Vector3(0.3, 0.2, 0.05), 0.05, MeshKit.at(Vector3(0, 0.42, 0.23)), col.lightened(0.45))
	b.sphere(0.035, MeshKit.at(Vector3(-0.07, 0.44, 0.26)), Color(1.0, 0.35, 0.4), 6)
	b.sphere(0.035, MeshKit.at(Vector3(0.07, 0.44, 0.26)), Color(1.0, 0.85, 0.3), 6)
	b.rounded_box(Vector3(0.52, 0.38, 0.44), 0.12, MeshKit.at(Vector3(0, 0.86, 0)), METAL)
	b.rounded_box(Vector3(0.4, 0.24, 0.04), 0.06, MeshKit.at(Vector3(0, 0.87, 0.215)), SCREEN)
	b.sphere(0.05, MeshKit.at(Vector3(-0.09, 0.89, 0.235)), EYE, 8, true)
	b.sphere(0.05, MeshKit.at(Vector3(0.09, 0.89, 0.235)), EYE, 8, true)
	b.box(Vector3(0.12, 0.025, 0.02), MeshKit.at(Vector3(0, 0.8, 0.236)), EYE)
	for s in [-1.0, 1.0]:
		b.cylinder(0.05, 0.05, 0.06, MeshKit.at(Vector3(s * 0.28, 0.86, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), col, 8)
	b.cylinder(0.02, 0.02, 0.1, MeshKit.at(Vector3(0, 1.08, 0)), METAL.darkened(0.3), 6)
	return b.build()


static func _foot_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.16, 0.12, 0.24), 0.05, MeshKit.at(Vector3(0, 0.06, 0.03)), METAL.darkened(0.35))
	return b.build()


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


## Put the robot somewhere (start, checkpoint), facing +X (the island's way).
func place(p: Vector3) -> void:
	position = p
	_target = p
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	bump_t = 0.0
	hover_t = 0.0
	pounding = false
	dash_t = 0.0
	rotation.y = PI * 0.5
	_target_yaw = rotation.y


## A spring pad throws the robot up (owned robots; main calls it when its feet are on one).
func spring() -> void:
	if not owned or velocity.y > G.JUMP_V:
		return
	velocity.y = G.SPRING_V
	pounding = false
	dashed = false
	hover_t = 0.0
	_air_t = COYOTE
	_squash = 1.0
	events.append(["spring"])


## A comical bump: hop up and tumble away along `dir` (owned robots only).
func bump(dir: Vector3, strength: float = 1.0) -> void:
	if not owned or safe_t > 0.0:
		return
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.LEFT
	_knock = dir * 5.0 * strength
	velocity.y = 5.5 * strength
	pounding = false
	dash_t = 0.0
	bump_t = BUMP_TIME
	safe_t = SAFE_AFTER + BUMP_TIME
	events.append(["bump"])


## A little hop (a giant's finger, a stomp on a grumble).
func hop(v: float = 5.0) -> void:
	if owned:
		velocity.y = maxf(velocity.y, v)
		_squash = 1.0
		hover_t = 0.0


func step(delta: float) -> void:
	if not owned:
		return
	bump_t = maxf(0.0, bump_t - delta)
	safe_t = maxf(0.0, safe_t - delta)
	punch_t = maxf(0.0, punch_t - delta)
	punch_cd = maxf(0.0, punch_cd - delta)
	var mv := inp_move if bump_t <= 0.0 else Vector3.ZERO
	if inp_jump:
		_jump_buf = JUMP_BUFFER
	inp_jump = false
	_jump_buf -= delta
	var on_floor := is_on_floor()
	_air_t = 0.0 if on_floor else _air_t + delta
	dash_t = maxf(0.0, dash_t - delta)
	if on_floor:
		hover_t = 0.0
		dashed = false
	# Gadgets under / around the robot (main asks the island): a belt's push (x, z), a fan's updraft (y).
	var push: Vector3 = main.gadget_push(self, on_floor) if main != null and main.has_method("gadget_push") else Vector3.ZERO
	var want := mv.limit_length(1.0) * G.RUN
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if bump_t > 0.0:
		h = h.move_toward(_knock, 30.0 * delta)
	elif pounding:
		h = Vector3.ZERO
	elif dash_t > 0.0:
		pass  # (a dash keeps its burst)
	else:
		h = h.move_toward(want, (G.ACCEL if on_floor else G.AIR_ACCEL) * delta)
	if punch_t > PUNCH_TIME - 0.08 and dash_t <= 0.0:
		h += forward() * 26.0 * delta  # a little lunge with the punch
	# B in the air: GROUND POUND (straight down, a thump on landing).
	if inp_pound and not on_floor and not pounding and bump_t <= 0.0 and _air_t > 0.08:
		pounding = true
		pounds += 1
		h = Vector3.ZERO
		dash_t = 0.0
		events.append(["pound_start"])
	inp_pound = false
	velocity.x = h.x
	velocity.z = h.z
	velocity.y -= G.GRAVITY * delta
	if pounding:
		velocity.y = -G.POUND_V
	elif push.y > 0.0 and bump_t <= 0.0:  # a fan's updraft lifts you
		velocity.y = move_toward(velocity.y, push.y, 30.0 * delta) if velocity.y < push.y else velocity.y
		hover_t = 0.0
		dashed = false
	hovering = false
	if not on_floor and inp_hold and velocity.y < 0.0 and hover_t < G.HOVER_TIME and bump_t <= 0.0 and not pounding:
		if hover_t == 0.0:
			events.append(["hover"])
		velocity.y = maxf(velocity.y, -G.HOVER_FALL)
		hover_t += delta
		hovering = true
	if _jump_buf > 0.0 and _air_t < COYOTE and bump_t <= 0.0:
		velocity.y = G.JUMP_V
		_jump_buf = 0.0
		_air_t = COYOTE
		jumps += 1
		_squash = 0.6
		events.append(["jump"])
	if inp_punch and punch_cd <= 0.0 and bump_t <= 0.0 and not pounding:
		punch_t = PUNCH_TIME
		punch_cd = PUNCH_COOL
		punches += 1
		if not on_floor and not dashed and _air_t > 0.05:  # X in the air: a DASH punch (once a jump)
			dashed = true
			dashes += 1
			dash_t = 0.24
			var f := mv.normalized() if mv.length() > 0.2 else forward()
			rotation.y = atan2(f.x, f.z)
			velocity.x = f.x * G.DASH_V
			velocity.z = f.z * G.DASH_V
			velocity.y = maxf(velocity.y, 2.5)
			events.append(["dash"])
		events.append(["punch", position + Vector3.UP * 0.5 + forward() * PUNCH_REACH * 0.6])
	inp_punch = false
	velocity.y = maxf(velocity.y, -30.0)
	var belt := Vector3(push.x, 0.0, push.z)
	velocity += belt  # (a belt carries you only while you stand on it)
	move_and_slide()
	velocity -= belt
	if is_on_floor() and not _was_floor:
		_squash = 0.5
		events.append(["land"])
		if pounding:
			pounding = false
			_squash = 1.0
			events.append(["pound", position])
	if is_on_floor() and pounding:
		pounding = false
		events.append(["pound", position])
	_was_floor = is_on_floor()
	if Vector2(h.x, h.z).length() > 0.5 and bump_t <= 0.0:
		rotation.y = lerp_angle(rotation.y, atan2(h.x, h.z), 1.0 - exp(-14.0 * delta))
	if main != null and position.y < float(main.fall_y()):
		place(main.respawn_point(self))
		safe_t = SAFE_AFTER
		_squash = 1.0
		events.append(["fell"])


## What other machines need: bit 0 bumped, bit 1 hovering, bit 2 punching, bit 3 pounding.
func state_bits() -> int:
	return (1 if bump_t > 0.0 else 0) | (2 if hovering else 0) | (4 if punch_t > 0.0 else 0) | (8 if pounding else 0)


## Puppets: glide towards the last network position.
func set_remote(p: Vector3, yaw: float, bits: int) -> void:
	_target = p
	_target_yaw = yaw
	_remote_state = bits
	bump_t = BUMP_TIME if bits & 1 else 0.0
	hovering = bits & 2 != 0
	pounding = bits & 8 != 0
	if bits & 4 and punch_t <= 0.0:
		punch_t = PUNCH_TIME
	if position.distance_to(p) > 4.0:
		position = p


## Every machine: bob, run cycle, squash, tumble spin, propeller, punch.
func animate(delta: float) -> void:
	if not owned:
		var prev := position
		position = position.lerp(_target, 1.0 - exp(-16.0 * delta))
		rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-12.0 * delta))
		velocity = (position - prev) / maxf(delta, 0.001)
		punch_t = maxf(0.0, punch_t - delta)
	var speed := Vector2(velocity.x, velocity.z).length()
	var run := clampf(speed / G.RUN, 0.0, 1.0)
	_anim_t += delta * (4.0 + speed * 1.8)
	_squash = maxf(0.0, _squash - delta * 3.0)
	var sq := sin(_squash * PI) * 0.16 * _squash
	if bump_t > 0.0:
		_spin += delta * 13.0
	else:
		_spin = lerpf(_spin, roundf(_spin / TAU) * TAU, 1.0 - exp(-10.0 * delta))
	body.position.y = absf(sin(_anim_t)) * 0.05 * run
	body.rotation = Vector3(0.0, _spin, sin(_anim_t * 0.5) * 0.07 * run)
	body.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq)
	_prop_a += delta * (30.0 if hovering else 4.0 + speed)
	prop.rotation.y = _prop_a
	var swing := sin(_anim_t) * 0.9 * run
	arms[0].rotation = Vector3(swing, 0.0, -0.2)
	arms[1].rotation = Vector3(-swing, 0.0, 0.2)
	if hovering:  # arms out like wings
		arms[0].rotation = Vector3(0.0, 0.0, -1.3)
		arms[1].rotation = Vector3(0.0, 0.0, 1.3)
	if punch_t > 0.0:  # the right fist shoots forward
		var k := sin(punch_t / PUNCH_TIME * PI)
		arms[1].rotation = Vector3(-1.6 * k - 0.2, 0.0, 0.1)
	if pounding:  # curled up like a cannonball, arms up
		arms[0].rotation = Vector3(0.0, 0.0, -2.6)
		arms[1].rotation = Vector3(0.0, 0.0, 2.6)
		body.scale = Vector3(1.12, 0.85, 1.12)
	feet[0].position.z = sin(_anim_t) * 0.16 * run
	feet[1].position.z = -feet[0].position.z
