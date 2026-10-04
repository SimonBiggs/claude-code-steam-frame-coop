extends Node3D
## Village life on the table (pure scenery, each machine animates its own):
##  - villagers stroll between their cottages, the well and the campfire; when goblins climb onto
##    the table they hurry indoors, and between waves they come out and cheer (jumping up and down)
##  - sheep graze in the north meadow, ducks paddle up and down the river
##  - smoke curls up from every chimney
## Everything repeated is a MultiMesh, so the whole village costs a handful of draw calls.

const W := preload("res://games/giants_table/world.gd")

const VILLAGERS := 8
const SHEEP := 5
const DUCKS := 4
const SHIRTS: Array[Color] = [Color(0.9, 0.35, 0.3), Color(0.3, 0.55, 0.9), Color(0.95, 0.75, 0.25), Color(0.5, 0.8, 0.4),
	Color(0.8, 0.45, 0.85), Color(0.95, 0.55, 0.2), Color(0.35, 0.8, 0.85), Color(0.95, 0.95, 0.9)]

var main
var t := 0.0
var bodies: MultiMeshInstance3D
var heads: MultiMeshInstance3D
var hats: MultiMeshInstance3D
var sheep_body: MultiMeshInstance3D
var sheep_head: MultiMeshInstance3D
var duck_body: MultiMeshInstance3D
var duck_head: MultiMeshInstance3D
var smoke: CPUParticles3D
var folk: Array = []  # per villager: {pos, goal, home, out (0..1), wait, speed}
var flock: Array = []  # per sheep: {pos, goal, wait}
var cheer_t := 0.0
var hide := false


func _ready() -> void:
	bodies = _multi(_capsule(0.16, 0.5), VILLAGERS, true, W.mat(Color.WHITE))
	heads = _multi(W.sphere(0.13, 8), VILLAGERS, false, W.mat(Color(1.0, 0.8, 0.65)))
	hats = _multi(W.cyl(0.0, 0.15, 0.22, 6), VILLAGERS, true, W.mat(Color.WHITE))
	sheep_body = _multi(W.sphere(0.32, 8), SHEEP, false, W.mat(Color(0.97, 0.96, 0.92)))
	sheep_head = _multi(W.sphere(0.13, 6), SHEEP, false, W.mat(Color(0.2, 0.18, 0.18)))
	duck_body = _multi(W.sphere(0.16, 6), DUCKS, false, W.mat(Color(0.98, 0.95, 0.85)))
	duck_head = _multi(W.sphere(0.09, 6), DUCKS, false, W.mat(Color(0.25, 0.6, 0.3)))
	for i in VILLAGERS:
		var home := i % W.COTTAGES.size()
		var door := W.cottage_door(home)
		folk.append({"pos": door, "goal": door, "home": home, "out": 1.0, "wait": randf_range(0.0, 3.0), "speed": randf_range(0.9, 1.4), "bob": randf() * TAU})
		bodies.multimesh.set_instance_color(i, SHIRTS[i % SHIRTS.size()])
		hats.multimesh.set_instance_color(i, SHIRTS[(i + 3) % SHIRTS.size()].lightened(0.2))
	for i in SHEEP:
		var p := _meadow_point()
		flock.append({"pos": p, "goal": p, "wait": randf_range(0.0, 4.0)})
	# Chimney smoke: one particle system puffing from every chimney top.
	smoke = CPUParticles3D.new()
	smoke.amount = 30
	smoke.lifetime = 3.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	smoke.emission_points = W.chimney_tops()
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.35
	smoke.initial_velocity_max = 0.6
	smoke.gravity = Vector3(0.12, 0.08, 0.05)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	smoke.scale_amount_curve = curve
	var sm := W.sphere(0.16, 6)
	var smat := W.mat(Color(0.85, 0.82, 0.8, 0.45))
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	smoke.mesh = sm
	add_child(smoke)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 2
	return c


func _multi(mesh: Mesh, n: int, colors: bool, m: StandardMaterial3D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = n
	if colors:
		m.vertex_color_use_as_albedo = true
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _meadow_point() -> Vector3:
	var p := Vector3(2.6 + randf_range(-1.2, 1.2), 0.0, 8.6 + randf_range(-0.9, 0.9))
	p.y = W.height(p.x, p.z)
	return p


## Somewhere nice to stroll to: the campfire, the well, the market, a friend's door.
func _stroll_goal(home: int) -> Vector3:
	var spots: Array = [Vector3(0.0, 0.0, 2.2), Vector3(-1.9, 0.0, 1.0), Vector3(1.8, 0.0, -0.4), Vector3(-2.2, 0.0, -1.2),
		Vector3(1.4, 0.0, 2.0), W.cottage_door((home + 1 + randi() % 3) % W.COTTAGES.size())]
	var p: Vector3 = spots[randi() % spots.size()] + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
	p = W.push_out(p, 0.3)
	p.y = W.height(p.x, p.z)
	return p


## Villagers jump for joy (a wave was cleared, the village grew).
func cheer() -> void:
	cheer_t = 4.0


func _process(delta: float) -> void:
	t += delta
	cheer_t = maxf(0.0, cheer_t - delta)
	hide = main != null and not get_tree().get_nodes_in_group("goblins").is_empty()
	_update_folk(delta)
	_update_sheep(delta)
	_update_ducks()
	var sails = main.get("growth_sails") if main != null else null
	if sails != null and is_instance_valid(sails):
		sails.rotate_object_local(Vector3.BACK, delta * 0.8)


func _update_folk(delta: float) -> void:
	for i in folk.size():
		var f: Dictionary = folk[i]
		var pos: Vector3 = f.pos
		var door := W.cottage_door(f.home)
		var goal: Vector3 = door if hide else f.goal
		var to := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
		var dist := to.length()
		var moving := false
		if dist > 0.15:
			var spd: float = f.speed * (2.2 if hide else 1.0)
			var np := pos + to / dist * minf(dist, spd * delta)
			np = W.push_out(np, 0.25)
			np.y = W.height(np.x, np.z)
			f.pos = np
			moving = true
		elif not hide:
			f.wait = float(f.wait) - delta
			if float(f.wait) <= 0.0:
				f.wait = randf_range(2.0, 6.0)
				f.goal = _stroll_goal(f.home)
		# Indoors (safe from goblins) = shrink away at the door; come back out between waves.
		var inside: bool = hide and pos.distance_to(door) < 0.3
		f.out = move_toward(float(f.out), 0.0 if inside else 1.0, delta * 3.0)
		f.bob = float(f.bob) + delta * (12.0 if moving else 3.0)
		var hop := absf(sin(float(f.bob))) * (0.06 if moving else 0.0)
		if cheer_t > 0.0 and not hide:
			hop = absf(sin(t * 9.0 + i)) * 0.35
		var yaw := atan2(-to.x, -to.z) if dist > 0.15 else float(f.get("yaw", 0.0))
		f.yaw = yaw
		var s := maxf(float(f.out), 0.001)
		var p: Vector3 = f.pos
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
		bodies.multimesh.set_instance_transform(i, Transform3D(basis, p + Vector3.UP * (0.4 + hop) * s))
		heads.multimesh.set_instance_transform(i, Transform3D(basis, p + Vector3.UP * (0.8 + hop) * s))
		hats.multimesh.set_instance_transform(i, Transform3D(basis, p + Vector3.UP * (0.98 + hop) * s))


func _update_sheep(delta: float) -> void:
	for i in flock.size():
		var sh: Dictionary = flock[i]
		var pos: Vector3 = sh.pos
		var to := Vector3(sh.goal.x - pos.x, 0.0, sh.goal.z - pos.z)
		var dist := to.length()
		var grazing := true
		if dist > 0.1:
			var np := pos + to / dist * minf(dist, 0.35 * delta)
			np.y = W.height(np.x, np.z)
			sh.pos = np
			grazing = false
			sh.yaw = atan2(-to.x, -to.z)
		else:
			sh.wait = float(sh.wait) - delta
			if float(sh.wait) <= 0.0:
				sh.wait = randf_range(3.0, 8.0)
				sh.goal = _meadow_point()
		var yaw: float = sh.get("yaw", 0.0)
		var basis := Basis(Vector3.UP, yaw)
		var p: Vector3 = sh.pos
		var nod := (sin(t * 3.0 + i) * 0.06 - 0.1) if grazing else 0.0
		sheep_body.multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3(0.9, 0.8, 1.2)), p + Vector3.UP * 0.32))
		sheep_head.multimesh.set_instance_transform(i, Transform3D(basis, p + basis * Vector3(0, 0.42 + nod, -0.4)))


func _update_ducks() -> void:
	for i in DUCKS:
		var x := sin(t * 0.08 + i * 1.7) * 9.0 + (i - 1.5) * 0.6
		var dx := cos(t * 0.08 + i * 1.7)
		var z := W.river_z(x) + (0.25 if i % 2 == 0 else -0.25)
		var yaw := -PI / 2.0 if dx > 0.0 else PI / 2.0  # beak (-Z) points the way it paddles
		var basis := Basis(Vector3.UP, yaw)
		var p := Vector3(x, W.WATER_Y + 0.05 + sin(t * 2.0 + i) * 0.02, z)
		duck_body.multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3(0.85, 0.7, 1.2)), p + Vector3.UP * 0.08))
		duck_head.multimesh.set_instance_transform(i, Transform3D(basis, p + basis * Vector3(0, 0.26, -0.15)))
