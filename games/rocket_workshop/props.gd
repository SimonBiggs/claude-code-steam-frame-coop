extends Node3D
## Simple mode: everything around the pilot reacts to touch (Simon's rule). Two little side tables stand
## where the cockpit wings used to be, within arm's reach of the pilot (who stands at (0, 0, 0.12)
## facing the desk, -Z):
##  left:  a TOY ALIEN (jumps and spins, "zorp"), a RUBBER CHICKEN (squash and squeak) and a little
##         WINDOW with a roller SHUTTER (it rolls up: a starry sky and a bird that tweets; touch again
##         to roll it down).
##  right: a spinning GLOBE (touch it to spin it), a desk FAN (on / off) and two BOBBLEHEADS (wobble).
## VR hands touch them; a split-screen pilot clicks them with the pointer. The host (or local game)
## checks the touches and sends a "prop" event so the TV plays the same thing. Cheap: about 30 meshes,
## mostly merged, no lights, no physics.

const TOUCH := {
	# name: [touch point, radius]
	"alien": [Vector3(-1.05, 0.95, -0.05), 0.12],
	"chicken": [Vector3(-1.02, 0.87, 0.36), 0.11],
	"shutter": [Vector3(-1.17, 1.32, -0.2), 0.16],
	"globe": [Vector3(1.05, 1.0, -0.05), 0.13],
	"fan": [Vector3(1.15, 1.3, -0.22), 0.15],
	"bobble_a": [Vector3(0.95, 1.02, 0.36), 0.09],
	"bobble_b": [Vector3(1.17, 1.02, 0.36), 0.09],
}
const TABLE_TOP := 0.82

var main
var t := 0.0
var cool := {}
var touched := {}  # name -> count (the bot reads it)
var played := {}  # name -> count, on both machines (the bot reads it on the TV)
var alien: Node3D
var alien_t := 0.0
var chicken: Node3D
var chicken_t := 0.0
var shutter: Node3D
var shutter_open := false
var shutter_k := 0.0
var bird: Node3D
var bird_t := 0.0
var globe: Node3D
var globe_spin := 0.4
var fan_blades: Node3D
var fan_on := false
var fan_speed := 0.0
var heads: Array[Node3D] = []
var head_ang: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var head_vel: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var was_pointer := false


func _ready() -> void:
	name = "Props"
	var wood: StandardMaterial3D = main.make_material(Color(0.62, 0.42, 0.28), 0.0)
	for side in [-1.0, 1.0]:
		_mesh(self, main.box_mesh(Vector3(0.44, 0.06, 0.78)), Vector3(side * 1.07, TABLE_TOP - 0.03, 0.15), wood)
		_mesh(self, main.box_mesh(Vector3(0.36, TABLE_TOP - 0.06, 0.66)), Vector3(side * 1.07, (TABLE_TOP - 0.06) / 2.0, 0.15),
			main.make_material(Color(0.5, 0.33, 0.2), 0.0))
	_build_alien()
	_build_chicken()
	_build_window()
	_build_globe()
	_build_fan()
	_build_bobbles()


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _merged(parent: Node3D, key: String, parts: Array, pos: Vector3) -> MeshInstance3D:
	return _mesh(parent, main.merged_mesh("prop_" + key, parts), pos, main.vertex_mat())


func _build_alien() -> void:
	alien = Node3D.new()
	alien.position = Vector3(-1.05, TABLE_TOP, -0.05)
	alien.rotation.y = PI / 2.0  # faces the pilot
	add_child(alien)
	alien.add_child(main.alien_node(0, 3, 0, 0.13))


func _build_chicken() -> void:
	chicken = Node3D.new()
	chicken.position = Vector3(-1.02, TABLE_TOP, 0.36)
	chicken.rotation.y = 0.4
	add_child(chicken)
	var yellow := Color(1.0, 0.85, 0.2)
	_merged(chicken, "chicken", [
		[main.capsule_mesh(0.035, 0.2), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0, 0.035, 0)), yellow],
		[main.sphere_mesh(0.035), Transform3D(Basis(), Vector3(0.11, 0.07, 0)), yellow],
		[main.cyl_mesh(0.0, 0.015, 0.04, 6), Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.155, 0.07, 0)), Color(1.0, 0.55, 0.15)],
		[main.box_mesh(Vector3(0.04, 0.03, 0.01)), Transform3D(Basis(), Vector3(0.105, 0.11, 0)), Color(0.95, 0.2, 0.2)],
		[main.sphere_mesh(0.008), Transform3D(Basis(), Vector3(0.125, 0.08, 0.03)), Color(0.05, 0.05, 0.05)],
		[main.sphere_mesh(0.008), Transform3D(Basis(), Vector3(0.125, 0.08, -0.03)), Color(0.05, 0.05, 0.05)],
		[main.cyl_mesh(0.006, 0.006, 0.06, 5), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.13, 0.02, 0.015)), Color(1.0, 0.55, 0.15)],
		[main.cyl_mesh(0.006, 0.006, 0.06, 5), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-0.13, 0.02, -0.015)), Color(1.0, 0.55, 0.15)],
	], Vector3.ZERO)


func _build_window() -> void:
	var root := Node3D.new()
	root.position = Vector3(-1.22, 1.32, -0.2)
	root.rotation.y = PI / 2.0  # the window faces the pilot (+X)
	add_child(root)
	_mesh(self, main.box_mesh(Vector3(0.05, 1.32 - 0.15 - TABLE_TOP, 0.05)), Vector3(-1.22, (1.32 - 0.15 + TABLE_TOP) / 2.0, -0.2),
		main.make_material(Color(0.55, 0.36, 0.22), 0.0))
	# Frame and the starry sky behind the shutter (one merged mesh).
	var parts: Array = [
		[main.box_mesh(Vector3(0.4, 0.32, 0.03)), Transform3D(Basis(), Vector3(0, 0, -0.01)), Color(0.12, 0.15, 0.4)],
		[main.box_mesh(Vector3(0.46, 0.04, 0.05)), Transform3D(Basis(), Vector3(0, 0.18, 0)), Color(0.95, 0.6, 0.2)],
		[main.box_mesh(Vector3(0.46, 0.04, 0.05)), Transform3D(Basis(), Vector3(0, -0.18, 0)), Color(0.95, 0.6, 0.2)],
		[main.box_mesh(Vector3(0.04, 0.4, 0.05)), Transform3D(Basis(), Vector3(-0.21, 0, 0)), Color(0.95, 0.6, 0.2)],
		[main.box_mesh(Vector3(0.04, 0.4, 0.05)), Transform3D(Basis(), Vector3(0.21, 0, 0)), Color(0.95, 0.6, 0.2)],
		[main.sphere_mesh(0.045), Transform3D(Basis(), Vector3(0.1, 0.07, 0.01)), Color(1.0, 0.95, 0.7)],
	]
	for st in [Vector3(-0.12, 0.08, 0.01), Vector3(-0.05, -0.06, 0.01), Vector3(0.04, 0.1, 0.01), Vector3(0.15, -0.08, 0.01), Vector3(-0.15, -0.1, 0.01)]:
		parts.append([main.sphere_mesh(0.012), Transform3D(Basis(), st), Color(1.0, 0.95, 0.5)])
	_merged(root, "window", parts, Vector3.ZERO)
	bird = Node3D.new()
	bird.position = Vector3(-0.08, -0.12, 0.03)
	root.add_child(bird)
	_merged(bird, "bird", [
		[main.sphere_mesh(0.035), Transform3D(Basis(), Vector3(0, 0.03, 0)), Color(0.3, 0.7, 1.0)],
		[main.cyl_mesh(0.0, 0.012, 0.03, 5), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.035, 0.045)), Color(1.0, 0.7, 0.2)],
		[main.sphere_mesh(0.007), Transform3D(Basis(), Vector3(-0.015, 0.05, 0.03)), Color(0.05, 0.05, 0.05)],
		[main.sphere_mesh(0.007), Transform3D(Basis(), Vector3(0.015, 0.05, 0.03)), Color(0.05, 0.05, 0.05)],
	], Vector3.ZERO)
	bird.scale = Vector3.ONE * 0.01
	# The roller shutter: wooden slats hanging from the top of the frame.
	shutter = Node3D.new()
	shutter.position = Vector3(0, 0.16, 0.03)
	root.add_child(shutter)
	var slats: Array = []
	for i in 5:
		slats.append([main.box_mesh(Vector3(0.4, 0.058, 0.015)), Transform3D(Basis(), Vector3(0, -0.032 - i * 0.064, 0)),
			Color(0.75, 0.5, 0.3) if i % 2 == 0 else Color(0.68, 0.44, 0.26)])
	_merged(shutter, "shutter", slats, Vector3.ZERO)


func _build_globe() -> void:
	_merged(self, "globe_stand", [
		[main.cyl_mesh(0.06, 0.07, 0.03, 12), Transform3D(Basis(), Vector3(0, 0.015, 0)), Color(0.55, 0.36, 0.22)],
		[main.cyl_mesh(0.01, 0.01, 0.1, 6), Transform3D(Basis(), Vector3(0, 0.07, 0)), Color(0.85, 0.7, 0.3)],
	], Vector3(1.05, TABLE_TOP, -0.05))
	globe = Node3D.new()
	globe.position = Vector3(1.05, 1.0, -0.05)
	globe.rotation.z = 0.4
	add_child(globe)
	var parts: Array = [[main.sphere_mesh(0.1), Transform3D(), Color(0.25, 0.5, 0.95)]]
	for c in [Vector3(0.6, 0.4, 0.5), Vector3(-0.7, 0.1, 0.6), Vector3(0.1, -0.5, -0.8), Vector3(-0.3, 0.6, -0.7), Vector3(0.8, -0.3, -0.4)]:
		var d: Vector3 = c.normalized()
		parts.append([main.sphere_mesh(0.045), Transform3D(Basis.looking_at(d) * Basis.from_scale(Vector3(1.0, 1.0, 0.35)), d * 0.088), Color(0.35, 0.8, 0.3)])
	_merged(globe, "globe", parts, Vector3.ZERO)


func _build_fan() -> void:
	var root := Node3D.new()
	root.position = Vector3(1.2, 1.3, -0.22)
	root.rotation.y = -PI / 2.0  # faces the pilot (-X)
	add_child(root)
	_mesh(self, main.box_mesh(Vector3(0.04, 1.3 - TABLE_TOP, 0.04)), Vector3(1.2, (1.3 + TABLE_TOP) / 2.0, -0.22),
		main.make_material(Color(0.7, 0.72, 0.78), 0.0))
	_merged(root, "fan_body", [
		[main.cyl_mesh(0.05, 0.05, 0.08, 12), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, -0.04)), Color(0.35, 0.75, 0.85)],
	], Vector3.ZERO)
	fan_blades = Node3D.new()
	fan_blades.position = Vector3(0, 0, 0.02)
	root.add_child(fan_blades)
	var parts: Array = [[main.sphere_mesh(0.025), Transform3D(), Color(0.95, 0.4, 0.3)]]
	for i in 3:
		var b := Basis(Vector3.BACK, i * TAU / 3.0)
		parts.append([main.box_mesh(Vector3(0.05, 0.12, 0.01)), Transform3D(b, b * Vector3(0, 0.07, 0)), Color(0.98, 0.95, 0.85)])
	_merged(fan_blades, "fan_blades", parts, Vector3.ZERO)


func _build_bobbles() -> void:
	var looks: Array = [[Color(1.0, 0.55, 0.25), Color(1.0, 0.85, 0.7)], [Color(0.55, 0.85, 0.35), Color(0.55, 0.9, 0.4)]]
	for i in 2:
		var at := Vector3(0.95 if i == 0 else 1.17, TABLE_TOP, 0.36)
		var body: Color = looks[i][0]
		var face: Color = looks[i][1]
		_merged(self, "bobble_body%d" % i, [
			[main.cyl_mesh(0.035, 0.04, 0.012, 12), Transform3D(Basis(), Vector3(0, 0.006, 0)), Color(0.2, 0.2, 0.25)],
			[main.cyl_mesh(0.022, 0.03, 0.08, 10), Transform3D(Basis(), Vector3(0, 0.05, 0)), body],
		], at)
		var head := Node3D.new()
		head.position = at + Vector3(0, 0.1, 0)
		head.rotation.y = -PI / 2.0  # faces the pilot
		add_child(head)
		var hp: Array = [
			[main.sphere_mesh(0.05), Transform3D(Basis(), Vector3(0, 0.05, 0)), face],
			[main.sphere_mesh(0.01), Transform3D(Basis(), Vector3(-0.018, 0.06, 0.045)), Color(0.05, 0.05, 0.05)],
			[main.sphere_mesh(0.01), Transform3D(Basis(), Vector3(0.018, 0.06, 0.045)), Color(0.05, 0.05, 0.05)],
		]
		if i == 0:  # a little astronaut helmet ring
			hp.append([main.cyl_mesh(0.052, 0.052, 0.02, 12), Transform3D(Basis(), Vector3(0, 0.01, 0)), Color(0.9, 0.9, 0.95)])
		else:  # an alien antenna
			hp.append([main.cyl_mesh(0.004, 0.004, 0.05, 4), Transform3D(Basis(), Vector3(0, 0.12, 0)), Color(0.1, 0.1, 0.1)])
			hp.append([main.sphere_mesh(0.012), Transform3D(Basis(), Vector3(0, 0.15, 0)), Color(1.0, 0.95, 0.4)])
		_merged(head, "bobble_head%d" % i, hp, Vector3.ZERO)
		heads.append(head)


# --- Touches -------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	for k in cool.keys():
		cool[k] = float(cool[k]) - delta
	if main != null and main.ready_to_play and main.net.mode != "client" and not get_tree().paused and not main.players.is_empty():
		_check_touches()
	_animate(delta)


func _check_touches() -> void:
	var op = main.players[0]
	var hands: Array[Vector3] = []
	if not op.bot_hand.is_empty():
		hands.append(op.bot_hand.pos)
	elif op.vr:
		hands.append(op.hand_l.global_position)
		hands.append(op.hand_r.global_position)
	var ray_from := Vector3.INF
	var ray_dir := Vector3.ZERO
	if op.bot_hand.is_empty() and not op.vr and op.camera != null:
		var click: bool = op.pointer_held and not was_pointer
		was_pointer = op.pointer_held
		if click:
			ray_from = op.camera.project_ray_origin(op.cursor)
			ray_dir = op.camera.project_ray_normal(op.cursor)
	for n in TOUCH:
		if float(cool.get(n, 0.0)) > 0.0:
			continue
		var d: Array = TOUCH[n]
		var at: Vector3 = d[0]
		var r: float = d[1]
		var hit := false
		for h in hands:
			if h.distance_to(at) < r + 0.04:
				hit = true
		if ray_from != Vector3.INF:
			var along := (at - ray_from).dot(ray_dir)
			if along > 0.0 and (ray_from + ray_dir * along).distance_to(at) < r:
				hit = true
		if hit:
			touch(n)


## Host / local: the pilot touched prop `n`.
func touch(n: String) -> void:
	cool[n] = 1.2
	touched[n] = int(touched.get(n, 0)) + 1
	play(n)
	main.net.event("prop", [n])
	var op = main.players[0]
	if op.vr:
		op.haptic("l", 0.3)
		op.haptic("r", 0.3)


## Both machines: what the prop does.
func play(n: String) -> void:
	played[n] = int(played.get(n, 0)) + 1
	match n:
		"alien":
			alien_t = 1.0
			main.local_sound("zorp", -4.0, 1.2)
		"chicken":
			chicken_t = 0.6
			main.local_sound("squeak", -2.0, randf_range(0.9, 1.15))
		"shutter":
			shutter_open = not shutter_open
			main.local_sound("click", -6.0, 0.7)
			if shutter_open:
				bird_t = 2.0
		"globe":
			globe_spin = 14.0
			main.local_sound("whoosh", -8.0, 1.6)
		"fan":
			fan_on = not fan_on
			main.local_sound("whirr", -8.0, 1.0 if fan_on else 0.7)
		"bobble_a", "bobble_b":
			var i := 0 if n == "bobble_a" else 1
			head_vel[i] += Vector2(randf_range(-1.0, 1.0), 1.0).normalized() * 9.0
			main.local_sound("boing", -6.0, 1.0 + 0.25 * i)


func _animate(delta: float) -> void:
	# Toy alien: hops and spins round once.
	alien_t = maxf(0.0, alien_t - delta)
	alien.position.y = TABLE_TOP + sin(alien_t * PI) * 0.12
	alien.rotation.y = PI / 2.0 + (1.0 - alien_t) * TAU if alien_t > 0.0 else PI / 2.0
	# Rubber chicken: squash and stretch.
	chicken_t = maxf(0.0, chicken_t - delta)
	var sq := sin(chicken_t / 0.6 * PI * 3.0) * chicken_t
	chicken.scale = Vector3(1.0 + sq * 0.4, 1.0 - sq * 0.6, 1.0 + sq * 0.4)
	# Shutter rolls up (and the bird pops up to tweet) or down.
	shutter_k = move_toward(shutter_k, 1.0 if shutter_open else 0.0, delta * 2.5)
	shutter.scale = Vector3(1.0, maxf(1.0 - shutter_k * 0.88, 0.01), 1.0)
	if bird_t > 0.0:
		var before := bird_t
		bird_t = maxf(0.0, bird_t - delta)
		for at in [1.4, 1.1]:
			if before > at and bird_t <= at:
				main.local_sound("tweet", -6.0, 1.0 + randf() * 0.2)
	var show_bird := shutter_k > 0.8 and bird_t > 0.0
	bird.scale = bird.scale.lerp(Vector3.ONE if show_bird else Vector3.ONE * 0.01, 1.0 - exp(-10.0 * delta))
	bird.rotation.z = sin(t * 12.0) * 0.2 if show_bird else 0.0
	# Globe: spins down to a gentle turn.
	globe_spin = move_toward(globe_spin, 0.4, delta * 4.0)
	globe.rotate_object_local(Vector3.UP, globe_spin * delta)
	# Fan.
	fan_speed = move_toward(fan_speed, 22.0 if fan_on else 0.0, delta * 15.0)
	fan_blades.rotation.z += fan_speed * delta
	# Bobbleheads: heads on springs.
	for i in heads.size():
		head_vel[i] += (-head_ang[i] * 80.0 - head_vel[i] * 3.0) * delta
		head_ang[i] += head_vel[i] * delta
		var h: Node3D = heads[i]
		h.rotation.x = head_ang[i].y * 0.08
		h.rotation.z = head_ang[i].x * 0.08
