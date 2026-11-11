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
const Arenas := preload("res://games/elemental_bender/arenas.gd")

const ISLAND_R := 36.0
const DAIS_TOP := 1.0
const PILLAR_R := 4.6

var arena_id := "temple"
## This island's layout (arenas.gd): props, far scenery, hazard vents.
var lay := {}
var spawn_points: Array[Vector3] = []
## Where each pillar's orb glows (the VR player sees them high above).
var pillar_orbs: Array[Vector3] = []
var orb_nodes: Array[MeshInstance3D] = []
var _t := 0.0


func build(vr: bool, arena: String = "temple", temple_seed: int = 0) -> void:
	arena_id = arena
	var info := Arenas.info(arena)
	lay = Arenas.layout(arena, Arenas.layout_seed(temple_seed, arena))
	var ground: Color = info.ground
	var stone: Color = info.stone
	var b := MeshKit.Builder.new()
	# Island, beach, sea floor.
	b.cylinder(ISLAND_R, ISLAND_R + 1.5, 2.0, MeshKit.at(Vector3(0, -1, 0)), ground, 40)
	_col_cyl(ISLAND_R + 1.5, 2.0, Vector3(0, -1, 0))
	b.cylinder(ISLAND_R + 2.5, ISLAND_R + 4.0, 2.0, MeshKit.at(Vector3(0, -1.35, 0)), info.shore, 40)
	_col_cyl(ISLAND_R + 4.0, 2.0, Vector3(0, -1.35, 0))
	# The temple dais and its four element pillars.
	b.cylinder(8.0, 8.5, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), stone, 32)
	_col_cyl(8.5, 0.5, Vector3(0, 0.25, 0))
	b.cylinder(5.5, 6.0, 0.5, MeshKit.at(Vector3(0, 0.75, 0)), stone.lightened(0.05), 32)
	_col_cyl(6.0, 0.5, Vector3(0, 0.75, 0))
	# A glowing four-colour mosaic in the middle of the dais.
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * PILLAR_R
		b.cylinder(0.55, 0.65, 5.0, MeshKit.at(p + Vector3(0, 3.5, 0)), stone.lightened(0.1), 12)
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
		b.box(Vector3(5, h, 5), MeshKit.at(p + Vector3(0, h / 2.0, 0), Vector3.ONE, Vector3(0, a, 0)), stone.darkened(0.3))
		_col_box(Vector3(5, h, 5), p + Vector3(0, h / 2.0, 0), Vector3(0, a, 0))
		var sp := p - Vector3(cos(a), 0, sin(a)) * 4.0 + Vector3(0, h * 0.25, 0)
		b.box(Vector3(2, h * 0.5, 2), MeshKit.at(sp, Vector3.ONE, Vector3(0, a, 0)), stone.darkened(0.35))
		_col_box(Vector3(2, h * 0.5, 2), sp, Vector3(0, a, 0))
		b.sphere(0.4, MeshKit.at(p + Vector3(0, h + 0.6, 0)), E.COLORS[i], 10, true)
		var step_dir := Vector3(cos(a + 0.5), 0, sin(a + 0.5))
		spawn_points.append(p + step_dir * 9.0)
	# The island's props (arenas.gd layout: the wave generator keeps the portals clear of them) and the far scenery.
	for pr in lay.props:
		_prop(b, pr, arena)
	for m in lay.mountains:
		var a: float = m[0]
		var d: float = m[1]
		var h: float = m[2]
		var at := Vector3(cos(a) * d, h / 2.0 - 2.0, sin(a) * d)
		match arena:
			"volcano":  # dark volcanoes with glowing tops
				b.cylinder(h * 0.12, h * 0.8, h, MeshKit.at(at), Color(0.22, 0.18, 0.18), 7)
				b.cylinder(h * 0.1, h * 0.12, 1.0, MeshKit.at(Vector3(at.x, h - 2.0, at.z)), Color(1.0, 0.45, 0.1), 7, true)
			"sky":  # floating rocks in the sky
				var fy := 10.0 + fmod(h, 30.0)
				b.cylinder(h * 0.25, 0.0, h * 0.35, MeshKit.at(Vector3(at.x, fy, at.z)), Color(0.55, 0.5, 0.45), 7)
				b.cylinder(h * 0.26, h * 0.25, 1.5, MeshKit.at(Vector3(at.x, fy + h * 0.175 + 0.75, at.z)), Color(0.45, 0.7, 0.4), 7)
			_:
				b.cylinder(0.0, h * 0.8, h, MeshKit.at(at), Color(0.45, 0.5, 0.6) if arena != "ice" else Color(0.7, 0.78, 0.88), 7)
				b.cylinder(0.0, h * 0.2, h * 0.25, MeshKit.at(Vector3(cos(a) * d, h - 2.0 - h * 0.125 + 0.5, sin(a) * d)), Color(0.95, 0.95, 1.0), 7)
	var mesh: ArrayMesh = ResCache.get_or_make("eb_world_%s_%d_v2" % [arena, int(lay.seed)], b.build)
	var mi := MeshKit.instance(mesh, not vr)
	mi.name = "Island"
	add_child(mi)
	# The sea: one big plane (opaque in VR: transparency is costly on the Frame).
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	var sea_c: Color = info.sea
	sm.albedo_color = Color(sea_c.r, sea_c.g, sea_c.b, 1.0 if vr or float(info.sea_glow) > 0.0 else 0.85)
	if float(info.sea_glow) > 0.0:
		sm.emission_enabled = true
		sm.emission = sea_c
		sm.emission_energy_multiplier = float(info.sea_glow)
		sm.roughness = 0.9
		sm.metallic = 0.0
	elif not vr:
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.render_priority = preload("res://core/ui_kit.gd").VR_PRIO_UNDER_UI  # under VR cards (core/vr_view_check.gd "washed out")
	if float(info.sea_glow) <= 0.0:
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


## TEMPLE ISLAND's trees and rocks and the far mountains (arenas.gd: the classic seed 7, cached).
static func layout() -> Dictionary:
	return Arenas.layout("temple", Arenas.CLASSIC_SEED)


## The four training platforms' centres (5 x 5 m boxes, the stepping stone 4 m further in).
static func platforms() -> Array[Vector3]:
	return Arenas.platforms()


## Why a spot is not free (arenas.gd blocked; lay = an island's layout, {} = TEMPLE ISLAND).
static func blocked(p: Vector3, clear: float, island: Dictionary = {}) -> String:
	return Arenas.blocked(p, clear, island)


## One prop of an island into the baked mesh (+ its collision).
func _prop(b: MeshKit.Builder, pr: Dictionary, arena: String) -> void:
	var p: Vector3 = pr.p
	match String(pr.kind):
		"tree":
			var h: float = pr.h
			b.cylinder(0.18, 0.28, h, MeshKit.at(p + Vector3(0, h / 2.0, 0)), Color(0.4, 0.27, 0.15), 6)
			_col_cyl(0.28, h, p + Vector3(0, h / 2.0, 0))
			if pr.cones:
				for j in 3:
					var cone_h := 2.2 - j * 0.5
					b.cylinder(0.0, 1.6 - j * 0.4, cone_h, MeshKit.at(p + Vector3(0, h - 0.4 + j * 0.9, 0)), Color(0.15, 0.42, 0.2), 8)
			else:
				b.sphere(1.6, MeshKit.at(p + Vector3(0, h + 0.6, 0)), pr.color, 10)
		"rock":
			var size: float = pr.size
			var rot: Vector3 = pr.rot
			var rc := {"ice": Color(0.75, 0.9, 1.0), "volcano": Color(0.18, 0.15, 0.16), "sky": Color(0.7, 0.68, 0.62)}.get(arena, Color(0.5, 0.5, 0.52)) as Color
			b.box(Vector3.ONE * size, MeshKit.at(p + Vector3(0, 0.3, 0), Vector3(1, 0.7, 1), rot), rc)
			_col_box(Vector3(size, size * 0.7, size), p + Vector3(0, 0.3, 0), Vector3(0, rot.y, 0))
		"spike", "crystal":  # ice spikes / glowing lava crystals: a cluster of three
			var h: float = pr.h
			var c := Color(0.75, 0.92, 1.0) if pr.kind == "spike" else Color(1.0, 0.5, 0.15)
			for k in 3:
				var a := float(pr.rot) + k * TAU / 3.0
				var hk := h * (1.0 - k * 0.25)
				var off := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else 0.35)
				b.cylinder(0.0, 0.32 - k * 0.05, hk, MeshKit.at(p + off + Vector3(0, hk / 2.0, 0), Vector3.ONE, Vector3(sin(a) * 0.15 * k, 0, cos(a) * 0.15 * k)), c, 5, pr.kind == "crystal")
			_col_cyl(0.5, h, p + Vector3(0, h / 2.0, 0))
		"pine":  # a snowy pine
			var h: float = pr.h
			b.cylinder(0.15, 0.22, h * 0.5, MeshKit.at(p + Vector3(0, h * 0.25, 0)), Color(0.4, 0.27, 0.15), 6)
			for j in 3:
				b.cylinder(0.0, 1.3 - j * 0.35, 1.6 - j * 0.35, MeshKit.at(p + Vector3(0, h * 0.4 + j * 0.75, 0)), Color(0.15, 0.4, 0.25) if j < 2 else Color(0.95, 0.97, 1.0), 8)
			_col_cyl(0.22, h, p + Vector3(0, h / 2.0, 0))
		"column":  # a broken white column
			var h: float = pr.h
			b.cylinder(0.75, 0.75, 0.3, MeshKit.at(p + Vector3(0, 0.15, 0)), Color(0.82, 0.8, 0.74), 8)
			b.cylinder(0.45, 0.5, h, MeshKit.at(p + Vector3(0, h / 2.0 + 0.3, 0)), Color(0.93, 0.91, 0.86), 10)
			_col_cyl(0.55, h + 0.3, p + Vector3(0, (h + 0.3) / 2.0, 0))
		_:  # deadtree: a bare black trunk with two branches
			var h: float = pr.h
			var dc := Color(0.12, 0.1, 0.1)
			b.cylinder(0.12, 0.24, h, MeshKit.at(p + Vector3(0, h / 2.0, 0)), dc, 6)
			for k in 2:
				var a := float(pr.rot) + k * PI
				b.cylinder(0.04, 0.09, 1.2, MeshKit.at(p + Vector3(cos(a) * 0.4, h * 0.7, sin(a) * 0.4), Vector3.ONE, Vector3(sin(a) * 0.8, 0, -cos(a) * 0.8)), dc, 5)
			_col_cyl(0.24, h, p + Vector3(0, h / 2.0, 0))
