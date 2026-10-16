extends Node3D
## ELEMENTAL BENDER: the island temple (built the same on every machine).
## A grassy island with a sandy beach in a calm sea; in the middle a stepped stone dais with four
## pillars, each crowned with a glowing element orb; four raised training platforms with stepping
## stones (Shadow Raiders come from there); trees, blossom trees and rocks; snowy mountains far away.
## Every visible static part is baked into ONE mesh (a lit and a glow surface) with MeshKit; the
## collision shapes are separate static bodies on layer 1. No lights of its own: the pillar orbs are
## emissive (the source game's four OmniLights were too much for the Steam Frame).

const E := preload("res://games/elemental_bender/elem.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const ISLAND_R := 36.0
const DAIS_TOP := 1.0
const PILLAR_R := 4.6

var spawn_points: Array[Vector3] = []
## Where each pillar's orb glows (the VR player sees them high above).
var pillar_orbs: Array[Vector3] = []
var orb_nodes: Array[MeshInstance3D] = []
var _t := 0.0


func build(vr: bool) -> void:
	var b := MeshKit.Builder.new()
	# Island, beach, sea floor.
	b.cylinder(ISLAND_R, ISLAND_R + 1.5, 2.0, MeshKit.at(Vector3(0, -1, 0)), Color(0.36, 0.6, 0.28), 40)
	_col_cyl(ISLAND_R + 1.5, 2.0, Vector3(0, -1, 0))
	b.cylinder(ISLAND_R + 2.5, ISLAND_R + 4.0, 2.0, MeshKit.at(Vector3(0, -1.35, 0)), Color(0.9, 0.82, 0.6), 40)
	_col_cyl(ISLAND_R + 4.0, 2.0, Vector3(0, -1.35, 0))
	# The temple dais and its four element pillars.
	b.cylinder(8.0, 8.5, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.75, 0.72, 0.65), 32)
	_col_cyl(8.5, 0.5, Vector3(0, 0.25, 0))
	b.cylinder(5.5, 6.0, 0.5, MeshKit.at(Vector3(0, 0.75, 0)), Color(0.8, 0.77, 0.7), 32)
	_col_cyl(6.0, 0.5, Vector3(0, 0.75, 0))
	# A glowing four-colour mosaic in the middle of the dais.
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * PILLAR_R
		b.cylinder(0.55, 0.65, 5.0, MeshKit.at(p + Vector3(0, 3.5, 0)), Color(0.85, 0.82, 0.75), 12)
		_col_cyl(0.65, 5.0, p + Vector3(0, 3.5, 0))
		b.cylinder(0.85, 0.85, 0.3, MeshKit.at(p + Vector3(0, 6.1, 0)), Color(0.6, 0.25, 0.15), 12)
		pillar_orbs.append(p + Vector3(0, 6.8, 0))
		var tile := Vector3(cos(a), 0, sin(a)) * 1.3 + Vector3(0, DAIS_TOP + 0.01, 0)
		b.cylinder(0.7, 0.7, 0.02, MeshKit.at(tile), E.COLORS[i].darkened(0.1), 6, true)
	# Training platforms with stepping stones and a glowing banner orb.
	for i in 4:
		var a := i * TAU / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * 19.0
		var h := 2.0 + (i % 2) * 1.5
		b.box(Vector3(5, h, 5), MeshKit.at(p + Vector3(0, h / 2.0, 0), Vector3.ONE, Vector3(0, a, 0)), Color(0.55, 0.52, 0.48))
		_col_box(Vector3(5, h, 5), p + Vector3(0, h / 2.0, 0), Vector3(0, a, 0))
		var sp := p - Vector3(cos(a), 0, sin(a)) * 4.0 + Vector3(0, h * 0.25, 0)
		b.box(Vector3(2, h * 0.5, 2), MeshKit.at(sp, Vector3.ONE, Vector3(0, a, 0)), Color(0.5, 0.47, 0.43))
		_col_box(Vector3(2, h * 0.5, 2), sp, Vector3(0, a, 0))
		b.sphere(0.4, MeshKit.at(p + Vector3(0, h + 0.6, 0)), E.COLORS[i], 10, true)
		var step_dir := Vector3(cos(a + 0.5), 0, sin(a + 0.5))
		spawn_points.append(p + step_dir * 9.0)
	# Trees and rocks scattered around (same seed as the source game).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := 0
	while placed < 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(11.0, ISLAND_R - 2.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var clear := true
		for i in 4:
			var q := Vector3(cos(i * TAU / 4.0), 0, sin(i * TAU / 4.0)) * 19.0
			if p.distance_to(q) < 6.0:
				clear = false
		if not clear:
			continue
		placed += 1
		if rng.randf() < 0.7:
			_tree(b, p, rng)
		else:
			var size := rng.randf_range(0.8, 1.8)
			var rot := Vector3(rng.randf(), rng.randf() * 3.0, rng.randf())
			b.box(Vector3.ONE * size, MeshKit.at(p + Vector3(0, 0.3, 0), Vector3(1, 0.7, 1), rot), Color(0.5, 0.5, 0.52))
			_col_box(Vector3(size, size * 0.7, size), p + Vector3(0, 0.3, 0), Vector3(0, rot.y, 0))
	# Distant mountains with snowy caps.
	for i in 14:
		var a := i * TAU / 14.0 + rng.randf() * 0.3
		var d := rng.randf_range(140.0, 200.0)
		var h := rng.randf_range(40.0, 90.0)
		b.cylinder(0.0, h * 0.8, h, MeshKit.at(Vector3(cos(a) * d, h / 2.0 - 2.0, sin(a) * d)), Color(0.45, 0.5, 0.6), 7)
		b.cylinder(0.0, h * 0.2, h * 0.25, MeshKit.at(Vector3(cos(a) * d, h - 2.0 - h * 0.125 + 0.5, sin(a) * d)), Color(0.95, 0.95, 1.0), 7)
	var mesh: ArrayMesh = ResCache.get_or_make("eb_world_v1", b.build)
	var mi := MeshKit.instance(mesh, not vr)
	mi.name = "Island"
	add_child(mi)
	# The sea: one big plane (opaque in VR: transparency is costly on the Frame).
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.4, 0.65, 1.0 if vr else 0.85)
	if not vr:
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 0.08
	sm.metallic = 0.3
	sea.material_override = sm
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = Vector3(0, -1.0, 0)
	sea.name = "Sea"
	add_child(sea)
	# The four pillar orbs bob and pulse (separate so they can animate; 4 cheap draws).
	for i in 4:
		var orb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.45
		s.height = 0.9
		s.radial_segments = 14
		s.rings = 7
		orb.mesh = s
		orb.material_override = E.mat(E.COLORS[i], 4.0)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb.position = pillar_orbs[i]
		add_child(orb)
		orb_nodes.append(orb)


func _tree(b: MeshKit.Builder, p: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(2.5, 4.0)
	b.cylinder(0.18, 0.28, h, MeshKit.at(p + Vector3(0, h / 2.0, 0)), Color(0.4, 0.27, 0.15), 6)
	_col_cyl(0.28, h, p + Vector3(0, h / 2.0, 0))
	if rng.randf() < 0.5:
		for j in 3:
			var cone_h := 2.2 - j * 0.5
			b.cylinder(0.0, 1.6 - j * 0.4, cone_h, MeshKit.at(p + Vector3(0, h - 0.4 + j * 0.9, 0)), Color(0.15, 0.42, 0.2), 8)
	else:
		var pink := Color(1.0, 0.65, 0.78) if rng.randf() < 0.5 else Color(0.25, 0.55, 0.25)
		b.sphere(1.6, MeshKit.at(p + Vector3(0, h + 0.6, 0)), pink, 10)


func _body(shape: Shape3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var c := CollisionShape3D.new()
	c.shape = shape
	sb.add_child(c)
	sb.position = pos
	sb.rotation = rot
	add_child(sb)


func _col_cyl(r: float, h: float, pos: Vector3) -> void:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	_body(s, pos)


func _col_box(size: Vector3, pos: Vector3, rot: Vector3) -> void:
	var s := BoxShape3D.new()
	s.size = size
	_body(s, pos, rot)


## Ground height under a point on the island (the dais steps, else the grass at 0; below the beach the sea).
static func ground_y(p: Vector3) -> float:
	var r := Vector2(p.x, p.z).length()
	if r < 6.0:
		return DAIS_TOP
	if r < 8.5:
		return 0.5
	if r < ISLAND_R + 1.0:
		return 0.0
	return -0.35


## A spot on the temple for a (re)spawning TV bender.
static func temple_spot(slot: int) -> Vector3:
	var a := slot * TAU / 7.0 + 0.4
	return Vector3(cos(a), 0, sin(a)) * 3.0 + Vector3(0, DAIS_TOP + 0.3, 0)


func animate(delta: float) -> void:
	_t += delta
	for i in orb_nodes.size():
		var o := orb_nodes[i]
		o.position = pillar_orbs[i] + Vector3(0, sin(_t * 1.6 + i) * 0.12, 0)
		o.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 3.0 + i * 1.3))
