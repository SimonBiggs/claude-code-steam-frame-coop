extends Node3D
## Simon's skill tree: kills earn team XP, each level gives a skill point, and you spend points
## by shooting the glowing fruit on the tree. The host decides; levels are replicated.

const SKILLS := [
	# key, label, stat, "mul"/"add", amount, colour
	["rapid", "RAPID FIRE", "fire_rate", "mul", 0.9, Color(1.0, 0.9, 0.3)],
	["power", "POWER", "damage", "mul", 1.25, Color(1.0, 0.35, 0.3)],
	["vital", "VITALITY", "max_hp", "add", 20.0, Color(0.35, 1.0, 0.45)],
	["beam", "BEAM", "tether_dps", "mul", 1.4, Color(0.6, 1.0, 1.0)],
	["dash", "DASH", "dash_cd", "mul", 0.8, Color(0.75, 0.5, 1.0)],
	["speed", "SPEED", "speed", "mul", 1.08, Color(1.0, 0.6, 0.2)],
]
const MAX_LEVEL := 5
const SPOT := Vector3(0.0, 0.0, -15.0)

var main
var levels := {}
var fruits := {}  # key -> {area, mat, label}
var pulse := 0.0


func _ready() -> void:
	set_meta("v1", true)
	position = SPOT
	var bark: StandardMaterial3D = main.make_material(Color(0.25, 0.15, 0.35), 0.4)
	var glow: StandardMaterial3D = main.make_material(Color(0.4, 0.95, 1.0), 2.5)
	_branch(Vector3(0, 0, 0), Vector3(0, 3.2, 0), 0.35, bark)
	for i in SKILLS.size():
		var key: String = SKILLS[i][0]
		levels[key] = 0
		var a := lerpf(-2.4, 2.4, float(i) / (SKILLS.size() - 1))
		var tip := Vector3(a * 1.3, 3.6 + (1.4 - absf(a)) * 0.9, -absf(a) * 0.4)
		_branch(Vector3(0, 2.6 + absf(a) * 0.2, 0), tip, 0.12, glow)
		_fruit(key, SKILLS[i][1], SKILLS[i][5], tip)
	var sign := Label3D.new()
	sign.text = "SKILL TREE\nshoot a fruit to spend a skill point"
	sign.font_size = 44
	sign.outline_size = 14
	sign.pixel_size = 0.01
	sign.modulate = Color(0.6, 1.0, 1.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = Vector3(0, 1.4, 0.6)
	add_child(sign)


func _branch(from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.6
	cyl.bottom_radius = radius
	cyl.height = from.distance_to(to)
	cyl.radial_segments = 8
	mi.mesh = cyl
	mi.material_override = mat
	add_child(mi)
	var dir := (to - from).normalized()
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), (from + to) * 0.5)


func _fruit(key: String, title: String, color: Color, pos: Vector3) -> void:
	var area := Area3D.new()
	area.collision_layer = 4  # player bullets hit layer 4
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("skill", key)
	area.position = pos
	add_child(area)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	cs.shape = shape
	area.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.84
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var mat: StandardMaterial3D = main.make_material(color, 2.0)
	mi.material_override = mat
	area.add_child(mi)
	var label := Label3D.new()
	label.font_size = 40
	label.outline_size = 12
	label.pixel_size = 0.007
	label.modulate = color.lightened(0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0.75, 0)
	area.add_child(label)
	fruits[key] = {"mat": mat, "label": label, "title": title}
	_refresh(key)


func _refresh(key: String) -> void:
	var f: Dictionary = fruits[key]
	var lv: int = levels[key]
	f.label.text = "%s\n%s" % [f.title, "MAX" if lv >= MAX_LEVEL else "Lv %d" % lv]


func _process(delta: float) -> void:
	pulse += delta
	var can_buy: bool = main.skill_points > 0
	for key in fruits:
		var f: Dictionary = fruits[key]
		var open: bool = can_buy and levels[key] < MAX_LEVEL
		f.mat.emission_energy_multiplier = (3.0 + sin(pulse * 6.0) * 1.5) if open else 0.6


## Host: a player bullet hit a fruit.
func bullet_hit_area(area: Area3D, _damage: float, _owner) -> void:
	if main.net.mode == "client" or not area.has_meta("skill"):
		return
	var key: String = area.get_meta("skill")
	if levels[key] >= MAX_LEVEL:
		return
	if main.skill_points <= 0:
		main.popup(area.global_position + Vector3.UP * 0.6, "need XP", Color(0.7, 0.7, 0.8))
		return
	main.skill_points -= 1
	levels[key] += 1
	for s in SKILLS:
		if s[0] == key:
			if s[3] == "mul":
				main.upg[s[2]] *= s[4]
			else:
				main.upg[s[2]] += s[4]
				if s[2] == "max_hp":
					for p in main.players:
						if not p.is_down:
							p.hp += s[4]
			main.popup(area.global_position + Vector3.UP * 0.8, "%s Lv %d!" % [s[1], levels[key]], s[5])
	main.explosion(area.global_position, Color(0.6, 1.0, 1.0), 0.4)
	main.sound("pickup", 0.0, 1.2)
	_refresh(key)


## Client: levels from the host.
func apply_net(new_levels: Dictionary) -> void:
	for key in new_levels:
		if levels.get(key, -1) != new_levels[key]:
			levels[key] = new_levels[key]
			if fruits.has(key):
				_refresh(key)
