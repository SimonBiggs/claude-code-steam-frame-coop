extends Node3D
## A giant neon flying fish that swoops around the sky above the arena (Abigail's request).

const ORBIT := 34.0
const HEIGHT := 16.0
const SPEED := 0.55  # radians per second

var main
var t := 0.0
var tail: Node3D
var body: Node3D
var wings: Array = []
var mouth_mat: StandardMaterial3D
var fire_t := 10.0  # host: seconds until the next fireball
var charging := false


func _ready() -> void:
	# Shared clock so the fish is in the same place on the Frame and the TV.
	t = fmod(Time.get_unix_time_from_system(), 3600.0)
	body = Node3D.new()
	add_child(body)
	var skin: StandardMaterial3D = main.make_material(Color(1.0, 0.45, 0.15), 1.6)
	var belly: StandardMaterial3D = main.make_material(Color(1.0, 0.85, 0.4), 2.5)
	_part(SphereMesh.new(), skin, Vector3.ZERO, Vector3(1.4, 1.6, 4.0))  # body
	_part(SphereMesh.new(), belly, Vector3(0, -0.45, 0.2), Vector3(1.0, 0.8, 3.0))
	var fin := PrismMesh.new()
	_part(fin, skin, Vector3(0, 1.3, 0.6), Vector3(0.2, 1.4, 1.6))  # dorsal fin
	for side in [-1.0, 1.0]:
		var eye := _part(SphereMesh.new(), main.make_material(Color.WHITE, 4.0), Vector3(side * 0.62, 0.35, -1.45), Vector3.ONE * 0.38)
		_part(SphereMesh.new(), main.make_material(Color(0.05, 0.05, 0.1), 0.0), Vector3(side * 0.76, 0.38, -1.55), Vector3.ONE * 0.2)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Big see-through "wing" fins, like a real flying fish.
		var wing_mat: StandardMaterial3D = main.make_material(Color(0.5, 0.9, 1.0), 2.0)
		wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wing_mat.albedo_color.a = 0.6
		wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var wing := _part(PrismMesh.new(), wing_mat, Vector3(side * 2.2, 0.1, -0.3), Vector3(4.0, 0.1, 2.6))
		wing.set_meta("side", side)
		wings.append(wing)
	mouth_mat = main.make_material(Color(1.0, 0.3, 0.05), 0.5)
	_part(SphereMesh.new(), mouth_mat, Vector3(0, -0.2, -1.95), Vector3(0.7, 0.5, 0.4))
	tail = Node3D.new()
	tail.position = Vector3(0, 0, 1.9)
	body.add_child(tail)
	var tm := MeshInstance3D.new()
	var tp := PrismMesh.new()
	tm.mesh = tp
	tm.material_override = skin
	tm.scale = Vector3(0.2, 2.4, 1.8)
	tm.position = Vector3(0, 0, 0.9)
	tm.rotation.x = -PI / 2.0
	tail.add_child(tm)
	# Speed streaks behind it.
	var trail := CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.6
	trail.local_coords = false
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 10.0
	trail.initial_velocity_min = 2.0
	trail.initial_velocity_max = 4.0
	trail.gravity = Vector3.ZERO
	var streak := BoxMesh.new()
	streak.size = Vector3(0.12, 0.12, 0.9)
	streak.material = main.make_material(Color(1.0, 0.7, 0.3), 3.0)
	trail.mesh = streak
	trail.position = Vector3(0, 0, 2.5)
	body.add_child(trail)


func _part(mesh: PrimitiveMesh, mat: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	if mesh is SphereMesh:
		mesh.radial_segments = 16
		mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl * 0.5
	body.add_child(mi)
	return mi


func _process(delta: float) -> void:
	t = fmod(Time.get_unix_time_from_system(), 3600.0)
	_fireballs(delta)
	var a := t * SPEED
	# A swoopy loop: orbit the arena while bobbing up and down.
	var pos := Vector3(cos(a) * ORBIT, HEIGHT + sin(a * 2.0) * 4.0, sin(a) * ORBIT)
	var ahead := Vector3(cos(a + 0.05) * ORBIT, HEIGHT + sin((a + 0.05) * 2.0) * 4.0, sin(a + 0.05) * ORBIT)
	global_position = pos
	look_at(ahead, Vector3.UP)
	rotation.z = 0.35  # bank into the turn
	tail.rotation.y = sin(t * 12.0) * 0.6
	for w in wings:
		w.rotation.z = w.get_meta("side") * sin(t * 6.0) * 0.25  # gentle wing flap
	body.rotation.y = sin(t * 18.0 + 1.0) * 0.08


## Host: every so often the fish's mouth glows (warning) and it spits a fireball at a random player.
func _fireballs(delta: float) -> void:
	if mouth_mat == null:  # fish created before the fireball update: add the mouth now
		mouth_mat = main.make_material(Color(1.0, 0.3, 0.05), 0.5)
		_part(SphereMesh.new(), mouth_mat, Vector3(0, -0.2, -1.95), Vector3(0.7, 0.5, 0.4))
	mouth_mat.emission_energy_multiplier = lerpf(mouth_mat.emission_energy_multiplier, 8.0 if charging else 0.5, delta * 6.0)
	if main.net.mode == "client" or not main.ready_to_play or main.game_over or main.wave < 1:
		return
	if main.net.mode == "host" and not main.net.connected:
		return
	fire_t -= delta
	if fire_t <= 1.0 and not charging:
		charging = true
		main.sound("big_kill", -4.0, 2.0)  # roar
	if fire_t > 0.0:
		return
	charging = false
	fire_t = randf_range(8.0, 14.0)
	print("Fish fireball")
	var targets: Array = main.players.filter(func(p) -> bool: return not p.is_down)
	if targets.is_empty():
		return
	var target = targets.pick_random()
	var from := global_position + -global_basis.z * 2.0
	var aim: Vector3 = target.global_position + Vector3.UP * 1.0 - from
	var ball := preload("res://scripts/enemy_shot.gd").new()
	ball.main = main
	ball.net_id = main.next_net_id()
	ball.fireball = true
	ball.color = Color(1.0, 0.45, 0.1)
	ball.size = 2.2
	ball.speed = 11.0
	ball.damage = 12.0
	ball.life = 6.0
	ball.direction = aim.normalized()
	main.add_child(ball)
	ball.global_position = from
