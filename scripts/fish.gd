extends Node3D
## A giant neon flying fish that swoops around the sky above the arena (Abigail's request).
## It spits fireballs, can be shot down (host decides), and comes back after a while.

const ORBIT := 22.0
const HEIGHT := 11.0
const SPEED := 0.5  # radians per second
const RESPAWN := 45.0

var main
var t := 0.0
var tail: Node3D
var body: Node3D
var segments: Array[Node3D] = []
var wings: Array = []
var skin: StandardMaterial3D
var mouth_mat: StandardMaterial3D
var fire_t := 10.0  # host: seconds until the next fireball
var charging := false
var max_hp := 60.0
var hp := 60.0
var alive := true
var respawn_t := 0.0


func _ready() -> void:
	set_meta("v2", true)
	t = fmod(Time.get_unix_time_from_system(), 3600.0)  # shared clock: same place on every screen
	body = Node3D.new()
	add_child(body)
	skin = main.make_material(Color(0.25, 0.55, 1.0), 1.2)
	skin.metallic = 0.7
	skin.roughness = 0.25
	var belly: StandardMaterial3D = main.make_material(Color(0.85, 0.92, 1.0), 1.5)
	var neon: StandardMaterial3D = main.make_material(Color(0.3, 1.0, 1.0), 4.0)
	# Tapered body: head, chest, belly and tail sections that wiggle in a wave.
	var sizes := [Vector3(1.5, 1.4, 1.6), Vector3(1.6, 1.5, 1.6), Vector3(1.3, 1.2, 1.5), Vector3(0.9, 0.8, 1.4), Vector3(0.55, 0.5, 1.2)]
	for i in sizes.size():
		var seg := Node3D.new()
		seg.position = Vector3(0, 0, -1.6) if i == 0 else Vector3(0, 0, sizes[i - 1].z * 0.55)
		(body if i == 0 else segments[i - 1]).add_child(seg)
		segments.append(seg)
		_part(seg, SphereMesh.new(), skin, Vector3.ZERO, sizes[i])
		_part(seg, SphereMesh.new(), belly, Vector3(0, -sizes[i].y * 0.18, 0), sizes[i] * Vector3(0.8, 0.6, 0.9))
		if i >= 1 and i <= 3:  # dorsal spines
			_part(seg, PrismMesh.new(), neon, Vector3(0, sizes[i].y * 0.55, 0), Vector3(0.08, 0.6, 0.5))
	var head := segments[0]
	# Eyes, gills and the glowing mouth.
	for side in [-1.0, 1.0]:
		_part(head, SphereMesh.new(), main.make_material(Color.WHITE, 3.0), Vector3(side * 0.6, 0.25, -0.35), Vector3.ONE * 0.42)
		_part(head, SphereMesh.new(), main.make_material(Color(0.02, 0.02, 0.05), 0.0), Vector3(side * 0.74, 0.27, -0.42), Vector3.ONE * 0.24)
		for g in 3:
			_part(head, BoxMesh.new(), neon, Vector3(side * 0.7, -0.05, 0.25 + g * 0.18), Vector3(0.04, 0.6, 0.05))
		# Big see-through wing fins, like a real flying fish.
		var wing_mat: StandardMaterial3D = main.make_material(Color(0.5, 0.9, 1.0), 2.0)
		wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wing_mat.albedo_color.a = 0.55
		wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var wing := _part(segments[1], PrismMesh.new(), wing_mat, Vector3(side * 2.3, 0.15, 0.1), Vector3(3.6, 0.08, 2.4))
		wing.set_meta("side", side)
		wings.append(wing)
	mouth_mat = main.make_material(Color(1.0, 0.3, 0.05), 0.5)
	_part(head, SphereMesh.new(), mouth_mat, Vector3(0, -0.15, -0.8), Vector3(0.6, 0.4, 0.3))
	# Forked tail fin.
	tail = Node3D.new()
	tail.position = Vector3(0, 0, 0.7)
	segments[-1].add_child(tail)
	for side in [-1.0, 1.0]:
		var fin := _part(tail, PrismMesh.new(), skin, Vector3(0, side * 0.6, 0.6), Vector3(0.1, 1.4, 1.2))
		fin.rotation.x = side * 0.9
	# Hit box for player bullets (layer 4, like enemies).
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 1.3
	shape.height = 6.0
	cs.shape = shape
	cs.rotation.x = PI / 2.0
	area.add_child(cs)
	add_child(area)


func _part(parent: Node3D, mesh: PrimitiveMesh, mat: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	if mesh is SphereMesh:
		mesh.radial_segments = 16
		mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _process(delta: float) -> void:
	if not has_meta("named"):
		set_meta("named", true)
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.font_size = 64
		tag.outline_size = 16
		tag.pixel_size = 0.02
		tag.modulate = Color(0.6, 0.9, 1.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.4, 0)
		add_child(tag)
	var name_tag: Label3D = get_node("NameTag")
	name_tag.text = "FISHWORT  %d%%" % int(100.0 * hp / max_hp)
	t = fmod(Time.get_unix_time_from_system(), 3600.0)
	var a := t * SPEED
	var pos := Vector3(cos(a) * ORBIT, HEIGHT + sin(a * 2.0) * 3.0, sin(a) * ORBIT)
	var ahead := Vector3(cos(a + 0.05) * ORBIT, HEIGHT + sin((a + 0.05) * 2.0) * 3.0, sin(a + 0.05) * ORBIT)
	global_position = pos
	look_at(ahead, Vector3.UP)
	rotation.z = 0.35  # bank into the turn
	for i in segments.size():
		segments[i].rotation.y = sin(t * 7.0 - i * 0.9) * (0.05 + i * 0.07)  # swimming wave
	tail.rotation.y = sin(t * 7.0 - 5.0) * 0.5
	for w in wings:
		w.rotation.z = w.get_meta("side") * sin(t * 5.0) * 0.25
	skin.emission_energy_multiplier = lerpf(skin.emission_energy_multiplier, 1.2, delta * 8.0)
	_respawn(delta)
	_fireballs(delta)


## Host: a player bullet hit the fish.
func fish_hit(damage: float) -> void:
	if not alive or main.net.mode == "client":
		return
	hp -= damage
	skin.emission_energy_multiplier = 6.0
	main.sound("hit", -4.0, 0.5)
	if hp <= 0.0:
		_die()


func _die() -> void:
	alive = false
	visible = false
	respawn_t = RESPAWN
	main.score += 1500
	main.explosion(global_position, Color(0.4, 0.8, 1.0), 3.0)
	main.popup(global_position + Vector3.UP * 2.0, "+1500", Color(0.6, 0.9, 1.0))
	main._show_center("THE FLYING FISH IS DOWN!\nIt'll be back…", 2.0)
	main.achievements().unlock("big_catch")


func _respawn(delta: float) -> void:
	if alive or main.net.mode == "client":
		return
	respawn_t -= delta
	if respawn_t <= 0.0:
		alive = true
		visible = true
		max_hp = 60.0 + main.wave * 8.0
		hp = max_hp
		main._show_center("THE FLYING FISH IS BACK!", 1.5)


## Client: alive/health from the host's snapshot.
func apply_net(state: Array) -> void:
	alive = state[0]
	visible = alive
	var new_hp: float = state[1]
	if new_hp < hp - 0.01:
		skin.emission_energy_multiplier = 6.0
	hp = new_hp


## Host: every so often the fish's mouth glows (warning) and it spits a fireball at a random player.
func _fireballs(delta: float) -> void:
	mouth_mat.emission_energy_multiplier = lerpf(mouth_mat.emission_energy_multiplier, 8.0 if charging else 0.5, delta * 6.0)
	if not alive or main.net.mode == "client" or not main.ready_to_play or main.game_over or main.wave < 1:
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
	var from := global_position + -global_basis.z * 2.5
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
