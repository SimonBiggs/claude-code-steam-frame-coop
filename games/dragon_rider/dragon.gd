extends Node3D
## The big friendly dragon. This node is the level "cockpit" frame: it only moves and turns (yaw), it
## never pitches or rolls, so the rider's saddle, its two horns and the gunners' deck stay steady in
## VR. The body, wings and tail (child "body") bank and pitch a little underneath for the look.
## Dragon-local space: forward is -Z, the saddle is at the origin, the gunners' deck is behind it.
## The host flies it (fly); the TV machine follows the host's snapshots (net_follow).

const MAX_YAW_RATE := 0.55  # rad/s at full rein: gentle, wide turns
const BASE_SPEED := 13.0
const MAX_SPEED := 21.0
const CLIMB_SPEED := 7.0
const MIN_Y := 6.0
const MAX_Y := 115.0
const EYE := Vector3(0.0, 0.85, 0.12)  # the rider's eyes (dragon-local)
const REINS_RING := Vector3(0.0, -0.32, -1.45)
const LANTERNS: Array[Vector3] = [Vector3(-1.5, 0.02, 1.15), Vector3(1.5, 0.02, 1.15),
	Vector3(-1.5, 0.02, 4.05), Vector3(1.5, 0.02, 4.05)]

var main
var yaw := 0.0
var speed := BASE_SPEED
var vy := 0.0
var yaw_rate := 0.0
var steer := 0.0
var climb := 0.0
var flap_phase := 0.0
var flap_power := 0.0
var flap_cd := 0.0
var velocity := Vector3.ZERO
var lit: Array[bool] = [true, true, true, true]

var body: Node3D
var wing_l: Node3D
var wing_r: Node3D
var tail: Array[Node3D] = []
var lantern_meshes: Array[MeshInstance3D] = []
var lit_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var eyes: Array[MeshInstance3D] = []
var blink_t := 3.0
var smoke: CPUParticles3D
var head_pivot: Node3D

# TV machine: the host's latest state, extrapolated between snapshots.
var net_pos := Vector3.ZERO
var net_vel := Vector3.ZERO
var net_yaw := 0.0
var net_yaw_rate := 0.0
var net_has := false


func _ready() -> void:
	_build()


# --- Model -------------------------------------------------------------------

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.position = pos
	m.scale = scl
	return m


## A tapered cylinder from a (radius ra) to b (radius rb).
func limb(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, mat: Material, seg: int = 10) -> MeshInstance3D:
	var d := b - a
	var m := _mi(parent, main.cyl_mesh(rb, ra, d.length(), seg), mat, (a + b) * 0.5)
	m.basis = main.basis_y_to(d.normalized())
	return m


func _build() -> void:
	var skin: StandardMaterial3D = main.color_mat(Color(0.22, 0.62, 0.58), 0.0)
	var belly: StandardMaterial3D = main.color_mat(Color(0.95, 0.78, 0.45), 0.0)
	var membrane: StandardMaterial3D = main.color_mat(Color(0.95, 0.45, 0.4), 0.15)
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gold: StandardMaterial3D = main.color_mat(Color(1.0, 0.8, 0.35), 0.2)
	var ivory: StandardMaterial3D = main.color_mat(Color(1.0, 0.94, 0.8), 0.05)
	var leather: StandardMaterial3D = main.color_mat(Color(0.62, 0.18, 0.16), 0.0)
	var wood: StandardMaterial3D = main.color_mat(Color(0.55, 0.36, 0.22), 0.0)
	var eye_mat: StandardMaterial3D = main.color_mat(Color(1.0, 0.95, 0.6), 1.5)
	var dark: StandardMaterial3D = main.color_mat(Color(0.1, 0.08, 0.12), 0.0)

	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	# Torso (a long capsule lying along Z), lighter belly underneath.
	var torso := _mi(body, main.capsule_mesh(1.35, 8.6), skin, Vector3(0, -1.4, 2.0))
	torso.rotation.x = PI / 2.0
	var bel := _mi(body, main.capsule_mesh(1.05, 7.4), belly, Vector3(0, -1.95, 2.0))
	bel.rotation.x = PI / 2.0
	# Neck and head, low enough that the rider sees over it.
	limb(body, Vector3(0, -1.0, -1.6), Vector3(0, -0.15, -4.9), 0.8, 0.5, skin)
	# The head nods gently on its own pivot (blinking eyes, rosy cheeks, smoke puffs from the nose).
	head_pivot = Node3D.new()
	body.add_child(head_pivot)
	head_pivot.position = Vector3(0, -0.1, -5.0)
	var hp := head_pivot
	var o := Vector3(0, 0.1, 5.0)
	_mi(hp, main.box_mesh(Vector3(1.0, 0.8, 1.35)), skin, Vector3(0, 0.0, -5.55) + o)
	_mi(hp, main.box_mesh(Vector3(0.72, 0.5, 0.95)), skin, Vector3(0, -0.14, -6.5) + o)
	_mi(hp, main.box_mesh(Vector3(0.6, 0.12, 0.8)), belly, Vector3(0, -0.42, -6.3) + o)
	var cheek: StandardMaterial3D = main.color_mat(Color(1.0, 0.55, 0.6), 0.2)
	for s in [-1.0, 1.0]:
		eyes.append(_mi(hp, main.sphere_mesh(0.13), eye_mat, Vector3(0.45 * s, 0.18, -5.75) + o))
		eyes.append(_mi(hp, main.sphere_mesh(0.06), dark, Vector3(0.52 * s, 0.19, -5.8) + o))
		_mi(hp, main.sphere_mesh(0.1), cheek, Vector3(0.5 * s, -0.12, -5.95) + o, Vector3(1.0, 0.6, 1.0))
		limb(hp, Vector3(0.3 * s, 0.35, -5.2) + o, Vector3(0.55 * s, 0.85, -4.55) + o, 0.13, 0.02, gold, 8)
		limb(hp, Vector3(0.0, 0.3, -5.0) + o, Vector3(0.0, 0.55, -4.6) + o, 0.1, 0.02, gold, 6)
	smoke = CPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 1.1
	smoke.emitting = false
	smoke.direction = Vector3(0, 0.4, -1)
	smoke.spread = 25.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 2.2
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.95, 0.92, 0.95, 0.6)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	smoke.mesh = sm
	smoke.local_coords = true  # rides along with the dragon, drifting forward (never into the rider's face)
	smoke.one_shot = true
	smoke.explosiveness = 0.6
	smoke.position = Vector3(0, 0.0, -7.0) + o
	hp.add_child(smoke)
	# Back spikes behind the deck and down the tail.
	for k in 3:
		limb(body, Vector3(0, -0.2, 5.7 + k * 0.9), Vector3(0, 0.45 - k * 0.12, 6.0 + k * 0.9), 0.2, 0.0, gold, 6)
	# Tail: three swaying segments.
	var parent: Node3D = body
	var start := Vector3(0, -1.5, 6.2)
	var radii: Array[float] = [0.95, 0.6, 0.32, 0.05]
	for k in 3:
		var pivot := Node3D.new()
		parent.add_child(pivot)
		pivot.position = start
		limb(pivot, Vector3.ZERO, Vector3(0, -0.15, 3.2), radii[k], radii[k + 1], skin)
		tail.append(pivot)
		parent = pivot
		start = Vector3(0, -0.15, 3.2)
	limb(parent, Vector3(0, -0.15, 3.0), Vector3(0, 0.5, 3.6), 0.3, 0.0, membrane, 6)
	# Wings: hinged at the shoulders behind the rider.
	for s in [-1.0, 1.0]:
		var w := Node3D.new()
		body.add_child(w)
		w.position = Vector3(1.15 * s, -0.55, 2.3)
		limb(w, Vector3.ZERO, Vector3(6.8 * s, 0.25, -0.6), 0.22, 0.06, skin, 8)
		var mem := _mi(w, main.prism_mesh(Vector3(6.6, 3.4, 0.06)), membrane, Vector3(3.4 * s, 0.1, 0.9))
		mem.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		mem.scale = Vector3(-s, 1.0, 1.0)
		# Finger bones spreading through the wing, and a little claw at the wrist.
		limb(w, Vector3(3.6 * s, 0.17, -0.35), Vector3(4.6 * s, 0.1, 2.3), 0.08, 0.03, skin, 6)
		limb(w, Vector3(2.0 * s, 0.13, -0.25), Vector3(2.2 * s, 0.1, 2.4), 0.08, 0.03, skin, 6)
		limb(w, Vector3(6.8 * s, 0.25, -0.6), Vector3(7.2 * s, 0.35, -0.95), 0.06, 0.0, gold, 6)
		if s < 0.0:
			wing_l = w
		else:
			wing_r = w

	# --- The level part (never rolls): saddle, horns, deck, lantern posts ---
	_mi(self, main.box_mesh(Vector3(0.78, 0.2, 0.95)), leather, Vector3(0, -0.12, 0.18))
	_mi(self, main.box_mesh(Vector3(0.7, 0.42, 0.14)), leather, Vector3(0, 0.1, 0.66))
	_mi(self, main.box_mesh(Vector3(1.1, 0.06, 1.4)), gold, Vector3(0, -0.24, 0.2))
	limb(self, Vector3(0, -0.1, -0.32), Vector3(0, 0.12, -0.4), 0.09, 0.07, leather, 8)
	# The two saddle horns: a steady frame of reference right in front of the rider's hands.
	for s in [-1.0, 1.0]:
		limb(self, Vector3(0.3 * s, -0.12, -0.45), Vector3(0.44 * s, 0.28, -0.74), 0.075, 0.045, ivory, 8)
		limb(self, Vector3(0.44 * s, 0.28, -0.74), Vector3(0.4 * s, 0.4, -0.92), 0.045, 0.012, ivory, 8)
	_mi(self, main.sphere_mesh(0.07), gold, REINS_RING)
	# Gunners' deck with a little rail.
	_mi(self, main.box_mesh(Vector3(2.3, 0.14, 4.7)), wood, Vector3(0, -0.12, 3.05))
	for s in [-1.0, 1.0]:
		_mi(self, main.box_mesh(Vector3(0.06, 0.06, 4.6)), gold, Vector3(1.12 * s, 0.32, 3.05))
		for z in [0.9, 2.3, 3.7, 5.2]:
			_mi(self, main.box_mesh(Vector3(0.05, 0.45, 0.05)), wood, Vector3(1.12 * s, 0.1, z))
	# Lanterns on posts sticking out from the deck: the sprites want to pop them.
	lit_mat = main.color_mat(Color(1.0, 0.7, 0.3), 3.0)
	dark_mat = main.color_mat(Color(0.25, 0.2, 0.22), 0.0)
	for p in LANTERNS:
		var s := signf(p.x)
		limb(self, Vector3(1.1 * s, 0.0, p.z), Vector3(p.x, 0.5, p.z), 0.04, 0.03, wood, 6)
		limb(self, Vector3(p.x, 0.5, p.z), Vector3(p.x, 0.22, p.z), 0.01, 0.01, dark, 4)
		_mi(self, main.cyl_mesh(0.12, 0.2, 0.1, 10), gold, p + Vector3(0, 0.22, 0))
		var lm := _mi(self, main.sphere_mesh(0.2), lit_mat, p, Vector3(1.0, 1.15, 1.0))
		lantern_meshes.append(lm)


# --- Flight (host) -------------------------------------------------------------

## inp.x: rein left (-1) .. right (+1). inp.y: dive (-1) .. climb (+1). Everything is eased so the
## headset view never jerks.
func fly(delta: float, inp: Vector2, flap: bool) -> void:
	steer = move_toward(steer, clampf(inp.x, -1.0, 1.0), delta * 2.2)
	climb = move_toward(climb, clampf(inp.y, -1.0, 1.0), delta * 2.2)
	yaw_rate = lerpf(yaw_rate, -steer * MAX_YAW_RATE, 1.0 - exp(-2.5 * delta))
	yaw = wrapf(yaw + yaw_rate * delta, -PI, PI)
	vy = lerpf(vy, climb * CLIMB_SPEED, 1.0 - exp(-2.0 * delta))
	flap_cd -= delta
	if flap and flap_cd <= 0.0:
		flap_cd = 0.6
		speed = minf(MAX_SPEED, speed + 2.4)
		flap_power = 1.0
		main.sound("flap", -6.0, randf_range(0.9, 1.1))
		puff_smoke()
	speed = move_toward(speed, BASE_SPEED, delta * 1.4)
	velocity = Basis(Vector3.UP, yaw) * Vector3.FORWARD * speed + Vector3.UP * vy
	var p := position + velocity * delta
	if p.y < MIN_Y:
		p.y = MIN_Y
		vy = maxf(vy, 0.0)
	elif p.y > MAX_Y:
		p.y = MAX_Y
		vy = minf(vy, 0.0)
	velocity.y = (p.y - position.y) / maxf(delta, 0.0001)
	position = p
	basis = Basis(Vector3.UP, yaw)


func set_net(pos: Vector3, new_yaw: float, vel: Vector3, rate: float, st: float, cl: float, fp: float) -> void:
	net_pos = pos
	net_vel = vel
	net_yaw = new_yaw
	net_yaw_rate = rate
	steer = st
	climb = cl
	if fp > flap_power + 0.3:
		flap_power = fp
		puff_smoke()
	if not net_has:
		net_has = true
		position = pos
		yaw = new_yaw


## TV machine: glide along with the host's dragon between snapshots.
func net_follow(delta: float) -> void:
	if not net_has:
		return
	net_pos += net_vel * delta
	net_yaw += net_yaw_rate * delta
	velocity = net_vel
	position += net_vel * delta
	position = position.lerp(net_pos, 1.0 - exp(-5.0 * delta))
	if position.distance_to(net_pos) > 12.0:
		position = net_pos
	yaw = lerp_angle(yaw + net_yaw_rate * delta, net_yaw, 1.0 - exp(-6.0 * delta))
	basis = Basis(Vector3.UP, yaw)


func puff_smoke() -> void:
	if smoke != null:
		smoke.restart()
		smoke.emitting = true


## Wing beats, tail sway, a little bank and pitch of the body, blinking and a nodding head (both machines).
func animate(delta: float) -> void:
	blink_t -= delta
	if blink_t <= 0.0:
		blink_t = randf_range(2.5, 5.0)
	var eye_y := 0.15 if blink_t < 0.14 else 1.0
	for e in eyes:
		e.scale.y = eye_y
	if head_pivot != null:
		head_pivot.rotation.x = sin(flap_phase * 0.5) * 0.05 - climb * 0.08
		head_pivot.rotation.y = steer * -0.15
	flap_power = maxf(0.0, flap_power - delta * 0.9)
	flap_phase += delta * (1.6 + flap_power * 4.5)
	var beat := sin(flap_phase) * (0.18 + flap_power * 0.45)
	if wing_l:
		wing_l.rotation.z = -(0.12 + beat)
		wing_r.rotation.z = 0.12 + beat
	body.rotation.x = lerpf(body.rotation.x, climb * 0.1, 1.0 - exp(-3.0 * delta))
	body.rotation.z = lerpf(body.rotation.z, -steer * 0.13, 1.0 - exp(-3.0 * delta))
	body.position.y = sin(flap_phase) * 0.05 * (0.3 + flap_power)
	for k in tail.size():
		tail[k].rotation.y = sin(flap_phase * 0.5 - k * 0.8) * 0.12 + steer * 0.12
		tail[k].rotation.x = climb * -0.06
	for i in lantern_meshes.size():
		var lm := lantern_meshes[i]
		lm.material_override = lit_mat if lit[i] else dark_mat
		lm.position = LANTERNS[i] + Vector3(0, sin(flap_phase * 0.7 + i) * 0.03, 0)


# --- Helpers -------------------------------------------------------------------

func lantern_world(i: int) -> Vector3:
	return global_transform * LANTERNS[clampi(i, 0, LANTERNS.size() - 1)]


func lit_count() -> int:
	var n := 0
	for l in lit:
		if l:
			n += 1
	return n


func random_lit() -> int:
	var opts: Array[int] = []
	for i in lit.size():
		if lit[i]:
			opts.append(i)
	if opts.is_empty():
		return -1
	return opts[randi() % opts.size()]


func lit_mask() -> int:
	var m := 0
	for i in lit.size():
		if lit[i]:
			m |= 1 << i
	return m


func set_lit_mask(m: int) -> void:
	for i in lit.size():
		lit[i] = (m & (1 << i)) != 0


## Where the body is (for stars and rings): a little below and behind the saddle.
func core_position() -> Vector3:
	return global_transform * Vector3(0, -1.0, 1.0)
