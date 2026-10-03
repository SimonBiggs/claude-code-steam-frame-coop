extends CharacterBody3D
## Chases the nearest standing player and hurts them on contact.

const EnemyShotScript := preload("res://games/duo_arena/enemy_shot.gd")
const KINDS := {
	"grunt": {"hp": 3.0, "speed": 3.6, "radius": 0.55, "color": Color(0.95, 0.25, 0.3), "dps": 30.0, "points": 100, "drop": 0.06},
	"runner": {"hp": 1.0, "speed": 6.8, "radius": 0.4, "color": Color(1.0, 0.55, 0.1), "dps": 20.0, "points": 150, "drop": 0.05},
	"brute": {"hp": 14.0, "speed": 2.3, "radius": 1.0, "color": Color(0.65, 0.3, 1.0), "dps": 50.0, "points": 500, "drop": 0.35},
	"spitter": {"hp": 2.5, "speed": 3.2, "radius": 0.5, "color": Color(0.4, 1.0, 0.3), "dps": 15.0, "points": 250, "drop": 0.1, "ranged": true},
	"splitter": {"hp": 6.0, "speed": 3.0, "radius": 0.75, "color": Color(0.2, 0.95, 0.85), "dps": 30.0, "points": 300, "drop": 0.15, "splits": 3},
	"dino": {"hp": 9.0, "speed": 2.6, "radius": 0.9, "color": Color(0.35, 0.85, 0.3), "dps": 35.0, "points": 400, "drop": 0.2, "dino": true},
	"boss": {"hp": 80.0, "speed": 2.0, "radius": 1.8, "color": Color(1.0, 0.15, 0.6), "dps": 70.0, "points": 3000, "drop": 1.0},
}

var main
var kind := "grunt"
var hp := 3.0
var speed := 3.0
var radius := 0.5
var dps := 20.0
var points := 100
var drop := 0.05
var color := Color.RED
var mat: StandardMaterial3D
var mesh: MeshInstance3D
var knockback := Vector3.ZERO
var spawn_grace := 0.6
var dead := false
var bob := 0.0
var ranged := false
var shot_cd := 2.5
var bite_cd := 0.0
var halo: Node3D
var body_albedo := Color.RED
var last_hitter  # player who hit this enemy last: gets the XP
var slam_t := 5.0  # boss: time until the next ground slam
var slam_count := 0
var speed_scale := 1.0
var charge_t := 0.0  # dino: charging time left
var charge_cd := 3.0
var jaw: Node3D
var tail: Node3D
var age := 0.0  # boss: lives longer -> enrages (slams more often)
# Networked co-op: on the Steam Machine enemies are visual ghosts placed from host snapshots.
var ghost := false
var net_id := 0
var net_target := Vector3.ZERO
var net_rot := 0.0


func setup(k: String, wave: int, main_node) -> void:
	kind = k
	main = main_node
	var d: Dictionary = KINDS[k]
	hp = d.hp * (1.0 + (wave - 1) * 0.12)
	speed = d.speed * 0.9 * (1.0 + minf(wave, 12) * 0.03)
	radius = d.radius
	dps = d.dps
	points = d.points
	drop = d.drop
	color = d.color
	ranged = d.get("ranged", false)
	shot_cd = randf_range(1.5, 2.5)


func _ready() -> void:
	add_to_group("enemies")
	net_target = position
	if ghost:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = 4
		collision_mask = 1 | 4
		var cs := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = radius
		cs.shape = s
		cs.position.y = radius
		add_child(cs)

	if KINDS[kind].get("dino", false):
		_build_dino()
	else:
		_build_orb()
	mesh.scale = Vector3.ONE * 0.05
	create_tween().tween_property(mesh, "scale", Vector3.ONE, spawn_grace) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_orb() -> void:
	mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	mesh.mesh = sm
	body_albedo = color.darkened(0.45)
	mat = main.make_material(color, 0.35)
	mat.albedo_color = body_albedo
	mat.metallic = 0.6
	mat.roughness = 0.3
	mat.rim_enabled = true
	mat.rim = 1.0
	mat.rim_tint = 0.2
	mesh.material_override = mat
	mesh.position.y = radius
	add_child(mesh)

	# Spinning energy halo.
	halo = Node3D.new()
	mesh.add_child(halo)
	halo.rotation.x = 0.35
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 1.18
	tm.outer_radius = radius * 1.28
	tm.ring_segments = 6
	tm.rings = 24
	ring.mesh = tm
	ring.material_override = main.make_material(color, 3.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.add_child(ring)

	# Spikes for the melee types.
	if kind in ["grunt", "brute", "boss"]:
		var spike_mat: StandardMaterial3D = main.make_material(color.lightened(0.2), 1.5)
		var count := 6 if kind == "grunt" else 8
		for i in count:
			var spike := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = radius * 0.16
			cone.height = radius * 0.6
			cone.radial_segments = 6
			spike.mesh = cone
			spike.material_override = spike_mat
			var a := TAU * i / count
			var out := Vector3(cos(a), 0.25 if i % 2 == 0 else -0.25, sin(a)).normalized()
			spike.position = out * radius * 1.05
			spike.basis = Basis(Quaternion(Vector3.UP, out))
			mesh.add_child(spike)
	elif kind == "spitter":
		var mouth := MeshInstance3D.new()
		var mm := SphereMesh.new()
		mm.radius = radius * 0.3
		mm.height = radius * 0.6
		mouth.mesh = mm
		mouth.material_override = main.make_material(Color(0.6, 1.0, 0.3), 5.0)
		mouth.position = Vector3(0, -radius * 0.2, -radius * 0.85)
		mesh.add_child(mouth)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = radius * 0.18
		em.height = radius * 0.36
		em.radial_segments = 8
		em.rings = 4
		eye.mesh = em
		eye.material_override = main.make_material(Color(1.0, 1.0, 0.8), 4.0)
		eye.position = Vector3(side * radius * 0.4, radius * 0.25, -radius * 0.85)
		mesh.add_child(eye)



## A blocky green T-rex: big head with a snapping jaw, teeth, swinging tail, tiny arms.
func _build_dino() -> void:
	body_albedo = color.darkened(0.25)
	mat = main.make_material(color, 0.3)
	mat.albedo_color = body_albedo
	mat.roughness = 0.6
	var dark: StandardMaterial3D = main.make_material(color.darkened(0.5), 0.0)
	mesh = _box(self, Vector3(0.9, 0.95, 1.5), Vector3(0, radius + 0.2, 0), mat)
	var head := _box(mesh, Vector3(0.75, 0.6, 0.95), Vector3(0, 0.55, -1.0), mat)
	jaw = Node3D.new()
	head.add_child(jaw)
	jaw.position = Vector3(0, -0.28, 0.25)
	_box(jaw, Vector3(0.65, 0.16, 0.85), Vector3(0, -0.05, -0.4), dark)
	var teeth: StandardMaterial3D = main.make_material(Color(1, 1, 0.9), 1.0)
	for x in [-0.22, -0.07, 0.07, 0.22]:
		_box(head, Vector3(0.06, 0.12, 0.06), Vector3(x, -0.33, -0.4), teeth)
	var eye_mat: StandardMaterial3D = main.make_material(Color(1.0, 0.9, 0.2), 4.0)
	for side in [-1.0, 1.0]:
		_box(head, Vector3(0.12, 0.12, 0.12), Vector3(side * 0.38, 0.12, -0.15), eye_mat)
		_box(mesh, Vector3(0.3, 0.85, 0.35), Vector3(side * 0.35, -0.75, 0.15), dark)  # leg
		_box(mesh, Vector3(0.1, 0.3, 0.1), Vector3(side * 0.42, 0.0, -0.65), dark)  # tiny arm
	tail = Node3D.new()
	mesh.add_child(tail)
	tail.position = Vector3(0, 0.1, 0.7)
	_box(tail, Vector3(0.45, 0.4, 0.9), Vector3(0, -0.05, 0.45), mat)
	_box(tail, Vector3(0.28, 0.25, 0.8), Vector3(0, -0.15, 1.2), mat)
	for x in range(3):
		_box(mesh, Vector3(0.1, 0.22, 0.25), Vector3(0, 0.55, -0.3 + x * 0.4), dark)  # back spikes


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Dino: plods towards you, then roars and charges when close.
func _dino_behaviour(delta: float, dist: float) -> void:
	charge_cd -= delta
	if charge_t > 0.0:
		charge_t -= delta
		speed_scale = 2.8
		if charge_t <= 0.0:
			speed_scale = 1.0
	elif dist < 9.0 and charge_cd <= 0.0:
		charge_t = 1.3
		charge_cd = 5.0
		main.sound("big_kill", -2.0, 0.55)  # roar
		if not has_meta("roared"):
			set_meta("roared", true)
			print("Dino charge")


func _physics_process(delta: float) -> void:
	if dead:
		return
	if ghost:
		_ghost_update(delta)
		return
	if spawn_grace > 0.0:
		spawn_grace -= delta
		return
	var target = main.nearest_player(global_position)
	var dir := Vector3.ZERO
	if target != null:
		var to: Vector3 = target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.01:
			dir = to / dist
		bite_cd -= delta
		if dist < radius + 0.6 and bite_cd <= 0.0:
			# Bite: one chunk of damage, then bounce back so players get a window to react.
			bite_cd = 0.7
			target.take_damage(dps * 0.7, global_position)
			knockback = -dir * 9.0
			main.sound("hit", -6.0, 0.6)
		if kind == "boss":
			_boss_behaviour(delta)
		if kind == "dino":
			_dino_behaviour(delta, dist)
		if ranged:
			_ranged_behaviour(delta, target, dist)
			if dist < 7.0:
				dir = -dir * 0.7  # back off
			elif dist < 10.0:
				dir = dir.cross(Vector3.UP) * 0.6  # circle at range
	velocity = dir * speed * speed_scale + knockback
	velocity.y = 0.0
	knockback = knockback.limit_length(30.0).move_toward(Vector3.ZERO, 25.0 * delta)
	move_and_slide()
	position.y = 0.0
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
	bob += delta * speed * 2.0
	_animate_dino(delta)
	if halo:
		halo.rotate_y(delta * 3.0)
	mesh.position.y = radius + absf(sin(bob)) * radius * 0.25


## Boss: every few seconds, telegraph (glow + red ring) then slam the ground around it.
func _boss_behaviour(delta: float) -> void:
	age += delta
	if age > 30.0 and mat.albedo_color != Color.WHITE:
		body_albedo = color.darkened(0.45).lerp(Color(1.0, 0.1, 0.1), clampf((age - 30.0) / 30.0, 0.0, 0.8))
	var before := slam_t
	slam_t -= delta
	if before > 1.0 and slam_t <= 1.0:
		main._ring(global_position, 4.5, Color(1.0, 0.1, 0.1))
		main.net.event("ring", [global_position, 4.5, Color(1.0, 0.1, 0.1)])
		main.sound("spit", 0.0, 0.5)
	if slam_t <= 1.0:
		mat.emission_energy_multiplier = 0.5 + (1.0 - slam_t) * 6.0  # charging glow
		speed_scale = 0.2
	if slam_t > 0.0:
		return
	slam_t = maxf(2.5, 6.0 - maxf(0.0, age - 20.0) / 10.0)  # enrage: faster slams the longer it lives
	slam_count += 1
	if slam_t <= 2.6 and not has_meta("enraged"):
		set_meta("enraged", true)
		main._show_center("THE BOSS IS ENRAGED!", 1.5)
	print("Boss slam %d" % slam_count)
	speed_scale = 1.0
	mat.emission_energy_multiplier = 0.35
	for p in main.players:
		if not p.is_down and p.global_position.distance_to(global_position) < 4.5:
			p.take_damage(18.0, global_position)
	main.shockwave(global_position, 4.5, 0.0, 0.0, color)
	main.add_shake(global_position, 0.5)
	main.sound("big_kill", 0.0, 0.7)
	if slam_count % 2 == 0:
		main.split_enemy.call_deferred(global_position, 2)


func _ranged_behaviour(delta: float, target, dist: float) -> void:
	shot_cd -= delta
	# Glow brighter while charging so players see the shot coming.
	mat.emission_energy_multiplier = 0.5 + maxf(0.0, 0.6 - shot_cd) * 8.0
	if shot_cd > 0.0 or dist > 16.0:
		return
	shot_cd = randf_range(2.2, 3.0)
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var shot := EnemyShotScript.new()
	shot.main = main
	shot.net_id = main.next_net_id()
	shot.direction = to.normalized()
	main.add_child(shot)
	shot.global_position = global_position + Vector3.UP * 0.6 + shot.direction * (radius + 0.4)
	main.sound("spit", -4.0)


func hit(damage: float, from_dir: Vector3, knock: float = 1.0, source = null) -> void:
	if dead:
		return
	if source != null:
		last_hitter = source
	hp -= damage
	knockback = (knockback + from_dir * (6.0 * knock / radius)).limit_length(14.0)
	if knock > 0.0:
		main.sound("hit", -8.0, 1.2 / radius)
	_flash()
	if hp <= 0.0:
		_die()


func _flash() -> void:
	mat.albedo_color = Color.WHITE
	mat.emission = Color.WHITE
	var t := create_tween()
	t.tween_property(mat, "albedo_color", body_albedo, 0.12)
	t.parallel().tween_property(mat, "emission", color, 0.12)


## Client: [id, kind, pos, rot_y, hp] from the host's snapshot.
func apply_net(item: Array) -> void:
	net_target = item[2]
	net_rot = item[3]
	var new_hp: float = item[4]
	if new_hp < hp - 0.01:
		_flash()
	hp = new_hp


func _ghost_update(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	var before := global_position
	global_position = global_position.lerp(net_target, k)
	rotation.y = lerp_angle(rotation.y, net_rot, k)
	var moved := (global_position - before).length()
	bob += moved * 2.0
	if halo:
		halo.rotate_y(delta * 3.0)
	mesh.position.y = radius + absf(sin(bob)) * radius * 0.25
	_animate_dino(delta)


func _animate_dino(_delta: float) -> void:
	if jaw:
		jaw.rotation.x = -absf(sin(bob * 1.5)) * 0.5  # chomp
	if tail:
		tail.rotation.y = sin(bob * 0.8) * 0.4


func _die() -> void:
	dead = true
	remove_from_group("enemies")
	var splits: int = KINDS[kind].get("splits", 0)
	if splits > 0:
		main.split_enemy.call_deferred(global_position, splits)
	main.on_enemy_killed(global_position, color, points, drop, radius, last_hitter)
	queue_free()
