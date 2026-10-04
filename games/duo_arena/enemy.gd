extends CharacterBody3D
## Chases the nearest standing player and hurts them on contact.
## Orbs (grunt, runner, brute, spitter, splitter, the ORB OVERLORD boss and the golden OMEGA finale boss),
## dinos (dino, raptor packs, the KING REX boss), flying pterodactyls (ptero) that circle and swoop,
## and armoured ankylos (ankylo): bullets bounce off the shell until the VR sword (or dashes) crack it.

const EnemyShotScript := preload("res://games/duo_arena/enemy_shot.gd")
const KINDS := {
	"grunt": {"hp": 3.0, "speed": 3.6, "radius": 0.55, "color": Color(0.95, 0.25, 0.3), "dps": 30.0, "points": 100, "drop": 0.06},
	"runner": {"hp": 1.0, "speed": 6.8, "radius": 0.4, "color": Color(1.0, 0.55, 0.1), "dps": 20.0, "points": 150, "drop": 0.05},
	"brute": {"hp": 14.0, "speed": 2.3, "radius": 1.0, "color": Color(0.65, 0.3, 1.0), "dps": 50.0, "points": 500, "drop": 0.35},
	"spitter": {"hp": 2.5, "speed": 3.2, "radius": 0.5, "color": Color(0.4, 1.0, 0.3), "dps": 15.0, "points": 250, "drop": 0.1, "ranged": true},
	"splitter": {"hp": 6.0, "speed": 3.0, "radius": 0.75, "color": Color(0.2, 0.95, 0.85), "dps": 30.0, "points": 300, "drop": 0.15, "splits": 3},
	"dino": {"hp": 9.0, "speed": 2.6, "radius": 0.9, "color": Color(0.35, 0.85, 0.3), "dps": 35.0, "points": 400, "drop": 0.2, "dino": true},
	"raptor": {"hp": 1.6, "speed": 6.0, "radius": 0.5, "color": Color(1.0, 0.55, 0.15), "dps": 18.0, "points": 150, "drop": 0.05, "dino": true, "scale": 0.55},
	"ptero": {"hp": 2.5, "speed": 4.6, "radius": 0.6, "color": Color(0.85, 0.45, 1.0), "dps": 18.0, "points": 250, "drop": 0.12, "dino": true, "flying": true},
	"ankylo": {"hp": 9.0, "speed": 2.0, "radius": 0.95, "color": Color(0.9, 0.65, 0.3), "dps": 30.0, "points": 600, "drop": 0.4, "dino": true, "armor": 3},
	"rex": {"hp": 110.0, "speed": 2.2, "radius": 2.0, "color": Color(0.95, 0.2, 0.3), "dps": 60.0, "points": 5000, "drop": 1.0, "dino": true, "scale": 2.3, "boss": true},
	"boss": {"hp": 80.0, "speed": 2.0, "radius": 1.8, "color": Color(1.0, 0.15, 0.6), "dps": 70.0, "points": 3000, "drop": 1.0, "boss": true},
	"omega": {"hp": 130.0, "speed": 2.2, "radius": 2.0, "color": Color(1.0, 0.78, 0.2), "dps": 70.0, "points": 8000, "drop": 1.0, "boss": true},
}
const BOSS_NAMES := {"boss": "ORB OVERLORD", "rex": "KING REX", "omega": "OMEGA OVERLORD"}
const GOLD := Color(1.0, 0.82, 0.25)
const PTERO_CRUISE := 3.4

var main
var kind := "grunt"
var hp := 3.0
var max_hp := 3.0
var speed := 3.0
var radius := 0.5
var dps := 20.0
var points := 100
var drop := 0.05
var color := Color.RED
var mat: StandardMaterial3D
var mesh: Node3D
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
# Newer kinds and polish.
var golden := false  # gold rush: worth triple points
var model_scale := 1.0
var base_y := 0.5
var bob_amp := 0.12
var lift := 0.0  # pterodactyl: flying height above the floor
var swoop_t := 0.0
var swoop_cd := 3.0
var circle_sign := 1.0
var armor := 0  # ankylo: shell hits left (bullets mostly bounce off while > 0)
var shell: Node3D
var wings: Array[Node3D] = []
var eyes: Array[Node3D] = []
var blink_t := 2.0
var squash := 0.0
var grown := false
var shape_node: CollisionShape3D
var shadow: MeshInstance3D
var tag: Label3D
var ping_t := 0.0
# Networked co-op: on the Steam Machine enemies are visual ghosts placed from host snapshots.
var ghost := false
var net_id := 0
var net_target := Vector3.ZERO
var net_rot := 0.0
var net_aux := 0.0


func setup(k: String, wave: int, main_node) -> void:
	kind = k if KINDS.has(k) else "grunt"
	main = main_node
	var d: Dictionary = KINDS[kind]
	hp = d.hp * (1.0 + (wave - 1) * 0.12)
	speed = d.speed * 0.9 * (1.0 + minf(wave, 12) * 0.03)
	radius = d.radius
	dps = d.dps
	points = d.points
	drop = d.drop
	color = d.color
	ranged = d.get("ranged", false)
	model_scale = d.get("scale", 1.0)
	armor = d.get("armor", 0)
	shot_cd = randf_range(1.5, 2.5)
	circle_sign = 1.0 if randf() < 0.5 else -1.0
	if d.get("flying", false):
		lift = PTERO_CRUISE


func is_boss() -> bool:
	return KINDS[kind].get("boss", false)


func is_dino() -> bool:
	return KINDS[kind].get("dino", false)


func boss_name() -> String:
	return BOSS_NAMES.get(kind, "BOSS")


## Where to aim: the middle of the body (pterodactyls fly high).
func center() -> Vector3:
	return global_position + Vector3.UP * (radius + lift)


func _ready() -> void:
	add_to_group("enemies")
	net_target = position
	if golden:
		color = GOLD
		points *= 3
		drop = minf(1.0, drop * 3.0)
	if not ghost:
		max_hp = hp
	if ghost:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = 4
		collision_mask = 0 if kind == "ptero" else (1 | 4)  # flyers soar over pillars and the crowd
		shape_node = CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = radius
		shape_node.shape = s
		shape_node.position.y = radius + lift
		add_child(shape_node)

	match kind:
		"ptero":
			_build_ptero()
		"ankylo":
			_build_ankylo()
		_:
			if is_dino():
				_build_dino()
			else:
				_build_orb()
	if is_boss():
		tag = Label3D.new()
		tag.font_size = 64
		tag.outline_size = 16
		tag.pixel_size = 0.012
		tag.modulate = color.lightened(0.3)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position.y = radius * 2.0 + 1.6 + (1.5 if kind == "rex" else 0.0)
		add_child(tag)
	mesh.scale = Vector3.ONE * 0.05 * model_scale
	var grow := create_tween()
	grow.tween_property(mesh, "scale", Vector3.ONE * model_scale, spawn_grace) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow.tween_callback(func() -> void: grown = true)
	blink_t = randf_range(1.0, 4.0)


func _build_orb() -> void:
	base_y = radius
	bob_amp = radius * 0.25
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	orb.mesh = sm
	body_albedo = color.darkened(0.45)
	mat = main.make_material(color, 0.35)
	mat.albedo_color = body_albedo
	mat.metallic = 0.6
	mat.roughness = 0.3
	mat.rim_enabled = true
	mat.rim = 1.0
	mat.rim_tint = 0.2
	if golden:
		mat.metallic = 1.0
		mat.emission_energy_multiplier = 0.8
	orb.material_override = mat
	orb.position.y = radius
	add_child(orb)
	mesh = orb

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
	if kind in ["grunt", "brute", "boss", "omega"]:
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
		mm.radial_segments = 10
		mm.rings = 5
		mouth.mesh = mm
		mouth.material_override = main.make_material(Color(0.6, 1.0, 0.3), 5.0)
		mouth.position = Vector3(0, -radius * 0.2, -radius * 0.85)
		mesh.add_child(mouth)
	if kind == "omega":
		_crown(mesh, Vector3(0, radius * 0.95, 0), radius * 0.7)
	var eye_mat: StandardMaterial3D = main.make_material(Color(1.0, 1.0, 0.8), 4.0)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = radius * 0.18
		em.height = radius * 0.36
		em.radial_segments = 8
		em.rings = 4
		eye.mesh = em
		eye.material_override = eye_mat
		eye.position = Vector3(side * radius * 0.4, radius * 0.25, -radius * 0.85)
		mesh.add_child(eye)
		eyes.append(eye)


## A blocky T-rex: big head with a snapping jaw, teeth, swinging tail, tiny arms. Raptors are small,
## striped and fast; KING REX is huge and wears a crown.
func _build_dino() -> void:
	base_y = 1.1 * model_scale
	bob_amp = 0.12 * model_scale
	body_albedo = color.darkened(0.25)
	mat = main.make_material(color, 0.3)
	mat.albedo_color = body_albedo
	mat.roughness = 0.6
	if golden:
		mat.metallic = 1.0
		mat.emission_energy_multiplier = 0.8
	var dark: StandardMaterial3D = main.make_material(color.darkened(0.5), 0.0)
	mesh = _box(self, Vector3(0.9, 0.95, 1.5), Vector3(0, base_y, 0), mat)
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
		eyes.append(_box(head, Vector3(0.12, 0.12, 0.12), Vector3(side * 0.38, 0.12, -0.15), eye_mat))
		_box(mesh, Vector3(0.3, 0.85, 0.35), Vector3(side * 0.35, -0.75, 0.15), dark)  # leg
		_box(mesh, Vector3(0.1, 0.3, 0.1), Vector3(side * 0.42, 0.0, -0.65), dark)  # tiny arm
	tail = Node3D.new()
	mesh.add_child(tail)
	tail.position = Vector3(0, 0.1, 0.7)
	_box(tail, Vector3(0.45, 0.4, 0.9), Vector3(0, -0.05, 0.45), mat)
	_box(tail, Vector3(0.28, 0.25, 0.8), Vector3(0, -0.15, 1.2), mat)
	for x in range(3):
		_box(mesh, Vector3(0.1, 0.22, 0.25), Vector3(0, 0.55, -0.3 + x * 0.4), dark)  # back spikes
	if kind == "raptor":
		var stripe: StandardMaterial3D = main.make_material(Color(0.25, 0.1, 0.05), 0.0)
		for z in [-0.35, 0.05, 0.45]:
			_box(mesh, Vector3(0.94, 0.12, 0.14), Vector3(0, 0.38, z), stripe)
	elif kind == "rex":
		_crown(head, Vector3(0, 0.36, -0.05), 0.42)


## A little golden crown of glowing prisms (bosses).
func _crown(parent: Node3D, at: Vector3, size: float) -> void:
	var gold: StandardMaterial3D = main.make_material(Color(1.0, 0.82, 0.2), 3.0)
	gold.metallic = 1.0
	var band := _box(parent, Vector3(size * 1.6, size * 0.25, size * 1.6), at, gold)
	for i in 5:
		var a := TAU * i / 5.0
		var p := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(size * 0.45, size * 0.6, size * 0.12)
		p.mesh = pm
		p.material_override = gold
		p.position = Vector3(cos(a) * size * 0.7, size * 0.4, sin(a) * size * 0.7)
		p.rotation.y = -a + PI / 2.0
		band.add_child(p)


## A purple pterodactyl: long beak, crest, big flapping wings and a shadow on the floor to aim by.
func _build_ptero() -> void:
	base_y = radius + lift
	bob_amp = 0.15
	body_albedo = color.darkened(0.3)
	mat = main.make_material(color, 0.4)
	mat.albedo_color = body_albedo
	if golden:
		mat.metallic = 1.0
		mat.emission_energy_multiplier = 0.8
	var dark: StandardMaterial3D = main.make_material(color.darkened(0.55), 0.3)
	mesh = _box(self, Vector3(0.45, 0.4, 1.0), Vector3(0, base_y, 0), mat)
	var head := _box(mesh, Vector3(0.32, 0.32, 0.45), Vector3(0, 0.18, -0.6), mat)
	var beak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.11
	cone.height = 0.7
	cone.radial_segments = 6
	beak.mesh = cone
	beak.material_override = main.make_material(Color(1.0, 0.85, 0.3), 0.6)
	beak.rotation.x = -PI / 2.0
	beak.position = Vector3(0, -0.04, -0.5)
	head.add_child(beak)
	var crest := _box(head, Vector3(0.06, 0.3, 0.5), Vector3(0, 0.2, 0.25), dark)
	crest.rotation.x = -0.6
	var eye_mat: StandardMaterial3D = main.make_material(Color(1.0, 1.0, 0.6), 4.0)
	for side in [-1.0, 1.0]:
		eyes.append(_box(head, Vector3(0.08, 0.08, 0.08), Vector3(side * 0.17, 0.06, -0.08), eye_mat))
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.2, 0.1, -0.05)
		mesh.add_child(pivot)
		var wing_mat: StandardMaterial3D = main.make_material(color.lightened(0.2), 1.2)
		wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_box(pivot, Vector3(1.4, 0.04, 0.75), Vector3(side * 0.7, 0, 0.05), wing_mat)
		_box(pivot, Vector3(0.6, 0.05, 0.4), Vector3(side * 1.55, 0, -0.1), dark)  # wing tip
		pivot.set_meta("side", side)
		wings.append(pivot)
	_box(mesh, Vector3(0.12, 0.1, 0.6), Vector3(0, 0.0, 0.75), dark)  # tail
	shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.02
	disc.radial_segments = 16
	shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position.y = 0.04
	add_child(shadow)


## An ankylosaurus: low body, stubby legs, club tail and a crystal shell with spikes.
func _build_ankylo() -> void:
	base_y = 0.7
	bob_amp = 0.06
	body_albedo = color.darkened(0.3)
	mat = main.make_material(color, 0.3)
	mat.albedo_color = body_albedo
	if golden:
		mat.metallic = 1.0
		mat.emission_energy_multiplier = 0.8
	var dark: StandardMaterial3D = main.make_material(color.darkened(0.55), 0.0)
	mesh = _box(self, Vector3(1.2, 0.6, 1.7), Vector3(0, base_y, 0), mat)
	var head := _box(mesh, Vector3(0.6, 0.45, 0.55), Vector3(0, 0.0, -1.05), mat)
	var eye_mat: StandardMaterial3D = main.make_material(Color(1.0, 0.95, 0.4), 4.0)
	for side in [-1.0, 1.0]:
		eyes.append(_box(head, Vector3(0.1, 0.1, 0.1), Vector3(side * 0.28, 0.1, -0.18), eye_mat))
		for z in [-0.55, 0.55]:
			_box(mesh, Vector3(0.28, 0.5, 0.3), Vector3(side * 0.45, -0.45, z), dark)  # legs
	tail = Node3D.new()
	mesh.add_child(tail)
	tail.position = Vector3(0, 0.0, 0.85)
	_box(tail, Vector3(0.25, 0.22, 1.0), Vector3(0, 0, 0.5), mat)
	var club := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.28
	cm.height = 0.5
	cm.radial_segments = 10
	cm.rings = 5
	club.mesh = cm
	club.material_override = dark
	club.position = Vector3(0, 0, 1.05)
	tail.add_child(club)
	# The shell: a glowing crystal dome with spikes. Cracking it hides the whole node.
	shell = Node3D.new()
	mesh.add_child(shell)
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.85
	dm.height = 0.85
	dm.is_hemisphere = true
	dm.radial_segments = 16
	dm.rings = 6
	dome.mesh = dm
	var shell_mat: StandardMaterial3D = main.make_material(Color(0.45, 0.8, 1.0), 1.4)
	shell_mat.metallic = 0.8
	shell_mat.roughness = 0.2
	dome.material_override = shell_mat
	dome.scale = Vector3(0.85, 0.75, 1.15)
	dome.position.y = 0.22
	shell.add_child(dome)
	var spike_mat: StandardMaterial3D = main.make_material(Color(0.8, 0.95, 1.0), 2.5)
	for i in 6:
		var spike := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.0
		sc.bottom_radius = 0.1
		sc.height = 0.35
		sc.radial_segments = 5
		spike.mesh = sc
		spike.material_override = spike_mat
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -0.55 + floorf(i / 2.0) * 0.55
		spike.position = Vector3(side * 0.55, 0.55, z)
		spike.rotation.z = -side * 0.6
		shell.add_child(spike)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Dino: plods towards you, then roars and charges when close. King Rex charges from further away.
func _dino_behaviour(delta: float, dist: float) -> void:
	if kind == "raptor":
		return  # raptors are fast enough already
	charge_cd -= delta
	var reach := 14.0 if kind == "rex" else 9.0
	if charge_t > 0.0:
		charge_t -= delta
		speed_scale = 3.0 if kind == "rex" else 2.8
		if charge_t <= 0.0:
			speed_scale = 1.0
	elif dist < reach and charge_cd <= 0.0 and slam_t > 1.0:
		charge_t = 1.5 if kind == "rex" else 1.3
		charge_cd = 4.0 if kind == "rex" else 5.0
		main.sound("roar", -2.0, 0.8 if kind == "rex" else 1.2)
		if not has_meta("roared"):
			set_meta("roared", true)
			print("Dino charge")


func _physics_process(delta: float) -> void:
	if dead:
		return
	_animate_common(delta)
	if ghost:
		_ghost_update(delta)
		return
	if spawn_grace > 0.0:
		spawn_grace -= delta
		_place_mesh()
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
		if dist < radius + 0.6 and bite_cd <= 0.0 and lift < 1.4:
			# Bite: one chunk of damage, then bounce back so players get a window to react.
			bite_cd = 0.7
			target.take_damage(dps * 0.7, global_position)
			knockback = -dir * 9.0
			main.sound("hit", -6.0, 0.6)
			if kind == "ptero":
				swoop_t = 0.0  # climb back up after a bite
		if kind == "boss" or kind == "omega":
			_boss_behaviour(delta)
		if kind == "rex":
			_rex_behaviour(delta)
		if is_dino() and kind != "ptero" and kind != "ankylo":
			_dino_behaviour(delta, dist)
		if kind == "ptero":
			dir = _ptero_behaviour(delta, dir, dist)
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
	if kind == "ptero":
		var flat := Vector2(position.x, position.z)
		var limit: float = main.arena_radius - 1.0
		if flat.length() > limit:
			flat = flat.normalized() * limit
			position.x = flat.x
			position.z = flat.y
		if shape_node:
			shape_node.position.y = radius + lift
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
	bob += delta * speed * 2.0
	_animate_dino(delta)
	_place_mesh()
	ping_t -= delta


## Pterodactyl: circles its target high up, then swoops down to bite and climbs again.
func _ptero_behaviour(delta: float, to_dir: Vector3, dist: float) -> Vector3:
	swoop_cd -= delta
	var want := PTERO_CRUISE
	var dir := to_dir
	if swoop_t > 0.0:
		swoop_t -= delta
		want = 0.6
		speed_scale = 1.5
	else:
		speed_scale = 1.0
		var radial := clampf((dist - 5.0) * 0.4, -1.0, 1.0)
		dir = (to_dir.cross(Vector3.UP) * circle_sign + to_dir * radial).normalized()
		if swoop_cd <= 0.0 and dist < 8.0:
			swoop_t = 1.8
			swoop_cd = randf_range(3.5, 5.5)
			main.sound("screech", -3.0)
	lift = move_toward(lift, want, delta * 3.5)
	return dir


## Boss: every few seconds, telegraph (glow + red ring) then slam the ground around it.
func _boss_behaviour(delta: float) -> void:
	age += delta
	var slam_r := 5.5 if kind == "omega" else 4.5
	if age > 30.0 and mat.albedo_color != Color.WHITE:
		body_albedo = color.darkened(0.45).lerp(Color(1.0, 0.1, 0.1), clampf((age - 30.0) / 30.0, 0.0, 0.8))
	var before := slam_t
	slam_t -= delta
	if before > 1.0 and slam_t <= 1.0:
		main._ring(global_position, slam_r, Color(1.0, 0.1, 0.1))
		main.net.event("ring", [global_position, slam_r, Color(1.0, 0.1, 0.1)])
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
		if not p.is_down and p.global_position.distance_to(global_position) < slam_r:
			p.take_damage(18.0, global_position)
	main.shockwave(global_position, slam_r, 0.0, 0.0, color)
	main.add_shake(global_position, 0.5)
	main.sound("big_kill", 0.0, 0.7)
	if slam_count % 2 == 0:
		main.split_enemy.call_deferred(global_position, 2, "raptor" if kind == "omega" else "runner")


## King Rex: charges like a dino, and every few seconds rears up and STOMPS (dodge the red ring).
## Every other stomp a pair of raptors hatches. Below 40% health he gets angry and stomps faster.
func _rex_behaviour(delta: float) -> void:
	age += delta
	var angry := hp < max_hp * 0.4
	if angry and not has_meta("angry"):
		set_meta("angry", true)
		main._show_center("KING REX IS ANGRY!", 1.5)
		main.sound("roar", 2.0, 0.6)
	var before := slam_t
	slam_t -= delta
	if before > 1.0 and slam_t <= 1.0:
		main._ring(global_position, 5.5, Color(1.0, 0.1, 0.1))
		main.net.event("ring", [global_position, 5.5, Color(1.0, 0.1, 0.1)])
		main.sound("roar", 0.0, 0.7)
		charge_t = 0.0
	if slam_t <= 1.0:
		mat.emission_energy_multiplier = 0.5 + (1.0 - slam_t) * 5.0
		speed_scale = 0.15
		mesh.rotation.x = (1.0 - slam_t) * 0.35  # rear up
	if slam_t > 0.0:
		return
	slam_t = 4.5 if angry else 7.0
	slam_count += 1
	speed_scale = 1.0
	mesh.rotation.x = 0.0
	mat.emission_energy_multiplier = 0.3
	for p in main.players:
		if not p.is_down and p.global_position.distance_to(global_position) < 5.5:
			p.take_damage(16.0, global_position)
	main.shockwave(global_position, 5.5, 0.0, 0.0, color)
	main.add_shake(global_position, 0.7)
	main.sound("big_kill", 0.0, 0.5)
	if slam_count % 2 == 0:
		main.split_enemy.call_deferred(global_position, 2, "raptor")


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
	if armor > 0:
		# The shell: bullets barely scratch it (ping!). The sword or dashes crack it.
		damage *= 0.15
		knock *= 0.3
		if ping_t <= 0.0:
			ping_t = 0.15
			main.sound("ping", -6.0)
			main.burst(center() + Vector3.UP * 0.4, Color(0.6, 0.9, 1.0), 4, 0.06)
			if source != null:
				main.director().hint("Bullets bounce off the shell! VR player: SLICE it with the sword. TV: DASH into it!",
					4.0, "shell_hint")
	hp -= damage
	knockback = (knockback + from_dir * (6.0 * knock / radius)).limit_length(14.0)
	if knock > 0.0 and armor <= 0:
		main.sound("hit", -8.0, 1.2 / radius)
	_flash()
	if hp <= 0.0:
		_die()


## The VR sword: cracks an armoured shell in one swing, then hits as usual.
func sword_hit(damage: float, from_dir: Vector3, source) -> void:
	if dead:
		return
	if armor > 0:
		crack(source, true)
	hit(damage, from_dir, 1.5, source)


## A dash into an ankylo knocks one chunk off its shell.
func bash(source) -> void:
	if dead or armor <= 0:
		return
	armor -= 1
	main.sound("crack", -4.0, 1.4)
	main.burst(center() + Vector3.UP * 0.4, Color(0.6, 0.9, 1.0), 8, 0.1)
	if armor <= 0:
		crack(source, false)
	else:
		main.popup(center() + Vector3.UP * 1.2, "CRACK! (%d more)" % armor, Color(0.6, 0.9, 1.0))


func crack(source, by_sword: bool) -> void:
	armor = 0
	_shell_off()
	main.sound("crack", 0.0)
	main.popup(center() + Vector3.UP * 1.3, "SHELL CRACKED!", Color(0.6, 0.95, 1.0))
	main.explosion(center() + Vector3.UP * 0.3, Color(0.45, 0.8, 1.0), 0.35)
	if by_sword:
		main.achievements().unlock("shell_shock")
	if source != null:
		main.director().add_stat(source, "cracks", 1)


func _shell_off() -> void:
	if shell != null and shell.visible:
		shell.visible = false
		body_albedo = color.lightened(0.1)  # soft and squishy now


func _flash() -> void:
	mat.albedo_color = Color.WHITE
	mat.emission = Color.WHITE
	squash = 1.0
	var t := create_tween()
	t.tween_property(mat, "albedo_color", body_albedo, 0.12)
	t.parallel().tween_property(mat, "emission", color, 0.12)


## Host: the small extra value each kind sends in snapshots (flying height, shell, boss health).
func net_aux_value() -> float:
	if kind == "ptero":
		return lift
	if kind == "ankylo":
		return float(armor)
	if is_boss():
		return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	return 0.0


## Client: [id, kind, pos, rot_y, hp, aux, flags] from the host's snapshot.
func apply_net(item: Array) -> void:
	net_target = item[2]
	net_rot = item[3]
	var new_hp: float = item[4]
	if new_hp < hp - 0.01:
		_flash()
	hp = new_hp
	if item.size() > 5:
		net_aux = item[5]
	else:
		net_aux = 0.0  # left out when zero (small snapshots)
	if kind == "ankylo" and net_aux <= 0.0:
		_shell_off()


func _ghost_update(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	var before := global_position
	global_position = global_position.lerp(net_target, k)
	rotation.y = lerp_angle(rotation.y, net_rot, k)
	var moved := (global_position - before).length()
	bob += moved * 2.0
	if kind == "ptero":
		lift = lerpf(lift, net_aux, k)
	_place_mesh()
	_animate_dino(delta)


## Bob, squash after hits, and (for pterodactyls) the flying height.
func _place_mesh() -> void:
	if kind == "ptero":
		base_y = radius + lift
		if shadow:
			var s := clampf(1.2 - lift * 0.15, 0.4, 1.2)
			shadow.scale = Vector3(s, 1.0, s)
	mesh.position.y = base_y + absf(sin(bob)) * bob_amp
	if grown:
		var sq := squash
		mesh.scale = Vector3.ONE * model_scale * Vector3(1.0 + 0.22 * sq, 1.0 - 0.18 * sq, 1.0 + 0.22 * sq)


## Blinking, halo spin, wing flaps, squash recovery and the boss name tag (host and client).
func _animate_common(delta: float) -> void:
	squash = maxf(0.0, squash - delta * 6.0)
	blink_t -= delta
	var shut := blink_t < 0.12
	if blink_t <= 0.0:
		blink_t = randf_range(2.0, 5.0)
	for e in eyes:
		e.scale.y = 0.15 if shut else 1.0
	if halo:
		halo.rotate_y(delta * 3.0)
	for w in wings:
		var side: float = w.get_meta("side")
		var flap := sin(age * 9.0 + (0.0 if swoop_t <= 0.0 else 1.0)) * (0.7 if lift > 1.5 else 0.3)
		w.rotation.z = side * flap
	if kind == "ptero":
		age += delta
	if tag:
		var frac := net_aux if ghost else clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
		tag.text = "%s  %d%%" % [boss_name(), int(ceil(frac * 100.0))]


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
	if kind == "rex":
		main.achievements().unlock("rex_wrecker")
	main.on_enemy_killed(global_position, color, points, drop, radius, last_hitter, self)
	queue_free()
