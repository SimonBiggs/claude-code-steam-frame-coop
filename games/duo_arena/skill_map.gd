extends Node3D
## Simon's skill map v2: a glowing star on the arena floor. Six branches, three tiers each.
## Each player earns their own XP from their kills and buys nodes for themselves by shooting them.
## Only the first ring is visible at first; buying a node reveals the next one on that branch.

const BRANCHES := [
	# key, name, colour, effect per tier: [stat, "mul"/"add", amount]
	["rapid", "RAPID FIRE", Color(1.0, 0.9, 0.3), [["fire_rate", "mul", 0.88]]],
	["power", "POWER", Color(1.0, 0.35, 0.3), [["damage", "mul", 1.25]]],
	["vital", "VITALITY", Color(0.35, 1.0, 0.45), [["max_hp", "add", 20.0]]],
	["shield", "SHIELD", Color(0.5, 0.75, 1.0), [["armor", "mul", 0.88], ["shield", "mul", 1.2]]],
	["dash", "DASH", Color(0.75, 0.5, 1.0), [["dash_cd", "mul", 0.8]]],
	["speed", "SPEED", Color(1.0, 0.6, 0.2), [["speed", "mul", 1.07]]],
]
const COSTS := [40, 90, 160]
const RADII := [2.6, 4.2, 5.8]
const ROMAN := ["I", "II", "III"]
const TURRET_COST := 100

var main
var nodes := {}  # "key:tier" -> {area, mat, label, line, owners}
var pulse := 0.0


func _ready() -> void:
	set_meta("map", true)
	set_meta("map_v3", true)
	for b in BRANCHES.size():
		var key: String = BRANCHES[b][0]
		var angle := TAU * b / BRANCHES.size() + PI / 6.0
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		var prev := dir * 1.0
		for tier in 3:
			var pos: Vector3 = dir * float(RADII[tier])
			_make_node(key, tier + 1, BRANCHES[b][1], BRANCHES[b][2], pos, prev)
			prev = pos
	_make_turret_hub()


func _make_node(key: String, tier: int, title: String, color: Color, pos: Vector3, from: Vector3) -> void:
	var area := Area3D.new()
	area.collision_layer = 4  # player bullets hit layer 4
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("skill", key)
	area.set_meta("tier", tier)
	area.position = pos + Vector3.UP * 0.3
	add_child(area)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 0.7, 1.3)
	cs.shape = shape
	area.add_child(cs)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.6
	cyl.height = 0.08
	cyl.radial_segments = 24
	disc.mesh = cyl
	var mat: StandardMaterial3D = main.make_material(color, 2.0)
	disc.material_override = mat
	disc.position.y = -0.25
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(disc)
	var label := Label3D.new()
	label.font_size = 40
	label.outline_size = 12
	label.pixel_size = 0.006
	label.modulate = color.lightened(0.35)
	label.double_sided = true
	area.add_child(label)
	# Lie flat just outside the disc, text "up" pointing away from the centre.
	var out := Vector3(pos.x, 0.0, pos.z).normalized()
	label.basis = Basis(out.cross(Vector3.UP), out, Vector3.UP)
	label.position = out * 1.05 + Vector3(0, -0.27, 0)
	# Glowing line on the floor back towards the centre / previous tier.
	var line := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.02, from.distance_to(pos))
	line.mesh = bm
	line.material_override = main.make_material(color, 1.5)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	line.position = (from + pos) * 0.5 + Vector3.UP * 0.03
	line.look_at(pos + Vector3.UP * 0.03, Vector3.UP)
	# Owner pips: a small ring in each owner's colour.
	var pips: Array = []
	for i in 3:
		_add_pip(area, pips)
	nodes["%s:%d" % [key, tier]] = {"area": area, "mat": mat, "label": label, "line": line, "pips": pips,
		"title": title, "key": key, "tier": tier}


func _process(delta: float) -> void:
	pulse += delta
	for id in nodes:
		var n: Dictionary = nodes[id]
		var key: String = n.key
		var tier: int = n.tier
		var revealed := tier == 1
		var affordable := false
		var pips: Array = n.pips
		while pips.size() < mini(main.players.size(), main.PLAYER_COLORS.size()):
			_add_pip(n.area, pips)  # more players joined: one more ring per player
		for i in mini(main.players.size(), n.pips.size()):
			var p = main.players[i]
			var owned: int = p.skills.get(key, 0)
			n.pips[i].visible = owned >= tier
			if owned >= tier - 1:
				revealed = true
			if owned == tier - 1 and p.xp >= COSTS[tier - 1]:
				affordable = true
		n.area.visible = revealed
		n.line.visible = revealed
		n.area.collision_layer = 4 if revealed else 0
		n.label.text = "%s %s\n%d XP" % [n.title, ROMAN[tier - 1], COSTS[tier - 1]]
		n.mat.emission_energy_multiplier = (3.0 + sin(pulse * 6.0) * 1.5) if affordable else 0.7


## A ring in a player's colour around a node they own (first three as before, then thinner).
func _add_pip(area: Area3D, pips: Array) -> void:
	var i := pips.size()
	var pip := MeshInstance3D.new()
	var tm := TorusMesh.new()
	var r := 0.66 + i * 0.12 if i < 3 else 1.02 + (i - 3) * 0.07
	tm.inner_radius = r
	tm.outer_radius = r + (0.06 if i < 3 else 0.04)
	if i >= 3:
		tm.rings = 24
		tm.ring_segments = 6
	pip.mesh = tm
	pip.material_override = main.make_material(main.PLAYER_COLORS[i % main.PLAYER_COLORS.size()], 3.0)
	pip.position.y = -0.24
	pip.visible = false
	pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(pip)
	pips.append(pip)


## Centre hub: shoot it to build an auto-turret where you stand.
func _make_turret_hub() -> void:
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("turret", true)
	area.position = Vector3(0, 0.3, 0)
	add_child(area)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 0.7, 1.6)
	cs.shape = shape
	area.add_child(cs)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.85
	cyl.height = 0.1
	cyl.radial_segments = 6  # hexagon
	disc.mesh = cyl
	disc.material_override = main.make_material(Color(0.9, 0.95, 1.0), 2.5)
	disc.position.y = -0.25
	area.add_child(disc)
	var label := Label3D.new()
	label.text = "BUILD TURRET\n%d XP" % TURRET_COST
	label.font_size = 40
	label.outline_size = 12
	label.pixel_size = 0.006
	label.double_sided = true
	label.modulate = Color(0.9, 0.95, 1.0)
	label.basis = Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	label.position = Vector3(0, -0.18, 0)
	area.add_child(label)


## Host: a player bullet hit a node; the shooter buys it for themselves.
func bullet_hit_area(area: Area3D, _damage: float, shooter) -> void:
	if main.net.mode == "client" or shooter == null:
		return
	if area.has_meta("turret"):
		var at := area.global_position + Vector3.UP * 0.9
		var mine := get_tree().get_nodes_in_group("turrets").filter(func(t) -> bool: return t.builder == shooter)
		if mine.size() >= 2:
			main.popup(at, "max 2 turrets", Color(0.7, 0.7, 0.8))
		elif shooter.xp < TURRET_COST:
			main.popup(at, "need %d XP" % TURRET_COST, Color(0.7, 0.7, 0.8))
		else:
			shooter.xp -= TURRET_COST
			main.build_turret(shooter)
		return
	if not area.has_meta("skill"):
		return
	var key: String = area.get_meta("skill")
	var tier: int = area.get_meta("tier")
	var owned: int = shooter.skills.get(key, 0)
	var at := area.global_position + Vector3.UP * 0.9
	if owned >= tier:
		return
	if owned < tier - 1:
		main.popup(at, "locked", Color(0.7, 0.7, 0.8))
		return
	var cost: int = COSTS[tier - 1]
	if shooter.xp < cost:
		main.popup(at, "need %d XP" % cost, Color(0.7, 0.7, 0.8))
		return
	shooter.xp -= cost
	shooter.skills[key] = tier
	for b in BRANCHES:
		if b[0] == key:
			for eff in b[3]:
				shooter.add_personal(eff[0], eff[1], eff[2])
			main.popup(at, "%s %s!" % [b[1], ROMAN[tier - 1]], b[2])
	main.explosion(area.global_position, Color(0.6, 1.0, 1.0), 0.4)
	main.sound("clear", -2.0, 1.4)
