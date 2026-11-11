extends Node3D
## WREN'S TOWN DISTRICTS (Tower Stack, second pass): the town of finished towers (skyline.gd) grows into DISTRICTS
## over the days. Every few towers the family builds a new district opens behind the town with its own landmark
## (a flag in its colour and a big model: a bouncy castle, a beehive, a balloon arch, ...), Wren cheers its name, and
## some districts open a SPECIAL BLOCK for the jobs from then on (towergen.gd: bouncy, sticky honey, balloon).
## All from the saved number of towers ever built (save "built"), so every machine shows the same town: main.gd
## keeps it in the "made" state. Static helpers are used by towergen-side tests and main.gd; the node draws.
##   Districts.reached(built) -> how many districts are open      Districts.open_mask(built) -> special blocks open
##   Districts.spot(k) -> where district k's landmark stands      node.set_made(built) (new ones pop in)

const G := preload("res://games/tower_stack/towergen.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

## at: towers built (all days) that open it. opens: the special block it brings (-1: none).
const LIST: Array[Dictionary] = [
	{"id": "meadow", "name": "MEADOW ROW", "pic": "house", "at": 0, "opens": -1, "color": Color(0.45, 0.85, 0.4)},
	{"id": "bounce", "name": "BOUNCE STREET", "pic": "bouncyblock", "at": 3, "opens": G.K_BOUNCY, "color": Color(1.0, 0.4, 0.85)},
	{"id": "honey", "name": "HONEY LANE", "pic": "honeyblock", "at": 7, "opens": G.K_STICKY, "color": Color(1.0, 0.72, 0.12)},
	{"id": "balloon", "name": "BALLOON PARK", "pic": "balloonblock", "at": 12, "opens": G.K_BALLOON, "color": Color(0.55, 0.85, 1.0)},
	{"id": "harbor", "name": "HARBOR", "pic": "lighthouse", "at": 20, "opens": -1, "color": Color(0.3, 0.55, 0.95)},
	{"id": "castle", "name": "CASTLE HILL", "pic": "castle", "at": 30, "opens": -1, "color": Color(0.75, 0.45, 1.0)},
	{"id": "sky", "name": "SKY TOWN", "pic": "cloud", "at": 45, "opens": -1, "color": Color(0.95, 0.95, 1.0)},
]
const RING := 13.3  # landmarks stand on this ring behind the town rows (towergen TOWN_R), among the first trees
const ARC := 2.3  # radians, centred behind the stage

var made := -1
var _models: Array[Node3D] = []
var _pop := {}


func _ready() -> void:
	name = "Districts"


## How many districts are open after `built` towers.
static func reached(built: int) -> int:
	var n := 0
	for d in LIST:
		if built >= int(d.at):
			n += 1
	return n


## The special blocks open after `built` towers (towergen site()'s `open` bitmask).
static func open_mask(built: int) -> int:
	var m := 0
	for i in reached(built):
		var k := int(LIST[i].opens)
		if k >= 0:
			m |= 1 << G.SPECIALS.find(k)
	return m


## The district opened by exactly `built` towers ({} if none opens there).
static func opened_at(built: int) -> Dictionary:
	for d in LIST:
		if int(d.at) == built and built > 0:
			return d
	return {}


## Where district k's landmark stands: the first right behind the stage, then out to alternating sides.
static func spot(k: int) -> Vector3:
	var step := ARC / float(LIST.size() - 1)
	var off := (k + 1) / 2 * (1 if k % 2 == 1 else -1)
	var a := -PI * 0.5 + off * step
	return Vector3(cos(a), 0.0, sin(a)) * RING


## Every machine: show the districts open after `built` towers (newly opened ones pop in).
func set_made(built: int) -> void:
	var n := reached(maxi(0, built))
	var grow := made >= 0
	made = built
	for k in range(_models.size(), n):
		var m := _landmark(k)
		_models.append(m)
		if grow:
			_pop[m] = 0.0
			m.scale = Vector3.ONE * 0.01


func _landmark(k: int) -> Node3D:
	var root := Node3D.new()
	root.name = "District%d" % k
	var at := spot(k)
	root.position = at
	root.rotation.y = atan2(-at.x, -at.z)  # faces the park
	root.add_child(MeshKit.instance(landmark_mesh(k)))
	add_child(root)
	return root


## One landmark (base at y = 0, front towards +Z): a paved patch and a flag in the district's colour, plus its model.
static func landmark_mesh(k: int) -> Mesh:
	return ResCache.get_or_make("tower_stack_district_v1_%d" % k, func() -> Resource:
		var d: Dictionary = LIST[clampi(k, 0, LIST.size() - 1)]
		var col: Color = d.color
		var b := MeshKit.Builder.new()
		b.cylinder(1.3, 1.35, 0.06, MeshKit.at(Vector3(0, 0.03, 0)), col.lerp(Color(0.85, 0.82, 0.75), 0.6), 20)
		b.cylinder(0.04, 0.04, 3.2, MeshKit.at(Vector3(-1.0, 1.6, 0.3)), Color(0.9, 0.9, 0.92), 6)
		b.box(Vector3(0.7, 0.42, 0.03), MeshKit.at(Vector3(-0.63, 2.9, 0.3)), col)
		match String(d.id):
			"meadow":  # a round tree and a bench
				b.cylinder(0.12, 0.15, 1.2, MeshKit.at(Vector3(0.2, 0.6, -0.2)), Color(0.5, 0.35, 0.22), 8)
				b.sphere(0.75, MeshKit.at(Vector3(0.2, 1.7, -0.2)), Color(0.3, 0.7, 0.3), 12)
				b.box(Vector3(0.9, 0.08, 0.3), MeshKit.at(Vector3(0.3, 0.4, 0.6)), Color(0.6, 0.4, 0.25))
			"bounce":  # a trampoline with a pink mat
				for a in 4:
					var p := Vector3(cos(a * TAU / 4.0 + 0.78), 0.0, sin(a * TAU / 4.0 + 0.78)) * 0.7
					b.cylinder(0.04, 0.04, 0.5, MeshKit.at(p + Vector3(0.3, 0.25, 0)), Color(0.3, 0.3, 0.35), 6)
				b.cylinder(0.85, 0.85, 0.08, MeshKit.at(Vector3(0.3, 0.52, 0)), col, 20)
				b.torus(0.85, 0.06, MeshKit.at(Vector3(0.3, 0.55, 0)), Color(0.3, 0.6, 1.0), 20, 6)
			"honey":  # a striped beehive on a stump
				b.cylinder(0.3, 0.35, 0.5, MeshKit.at(Vector3(0.3, 0.25, 0)), Color(0.55, 0.38, 0.22), 10)
				for i in 4:
					var r := 0.5 - i * 0.09
					b.ellipsoid(Vector3(r, 0.2, r), MeshKit.at(Vector3(0.3, 0.7 + i * 0.28, 0)), col if i % 2 == 0 else col.darkened(0.3), 12)
				b.sphere(0.1, MeshKit.at(Vector3(0.3, 0.8, 0.45)), Color(0.2, 0.12, 0.05), 8)
			"balloon":  # a balloon arch
				for i in 9:
					var a := PI * i / 8.0
					var p := Vector3(cos(a) * 1.0 + 0.3, sin(a) * 1.6 + 0.3, 0)
					b.sphere(0.24, MeshKit.at(p), [Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.25), col, Color(0.6, 0.95, 0.5)][i % 4], 10)
			"harbor":  # a little boat on a pond
				b.cylinder(1.0, 1.0, 0.04, MeshKit.at(Vector3(0.3, 0.08, 0)), Color(0.3, 0.6, 0.95), 20)
				b.ellipsoid(Vector3(0.55, 0.18, 0.25), MeshKit.at(Vector3(0.3, 0.2, 0)), Color(0.85, 0.3, 0.25), 12)
				b.cylinder(0.025, 0.025, 0.9, MeshKit.at(Vector3(0.3, 0.7, 0)), Color(0.5, 0.35, 0.2), 6)
				b.box(Vector3(0.02, 0.5, 0.4), MeshKit.at(Vector3(0.32, 0.8, 0)), Color(1, 1, 0.95))
			"castle":  # a castle gate with two turrets
				for sx in [-0.3, 0.9]:
					b.cylinder(0.28, 0.3, 1.8, MeshKit.at(Vector3(sx, 0.9, 0)), Color(0.75, 0.75, 0.8), 10)
					b.cone(0.34, 0.5, MeshKit.at(Vector3(sx, 2.05, 0)), col)
				b.box(Vector3(0.9, 1.2, 0.4), MeshKit.at(Vector3(0.3, 0.6, 0)), Color(0.7, 0.7, 0.75))
				b.box(Vector3(0.4, 0.7, 0.05), MeshKit.at(Vector3(0.3, 0.35, 0.21)), Color(0.45, 0.3, 0.2))
			_:  # sky: fluffy clouds on poles with a rainbow
				for i in 3:
					b.sphere(0.4, MeshKit.at(Vector3(-0.1 + i * 0.4, 2.2 + (0.15 if i == 1 else 0.0), 0)), col, 10)
				var rb := [Color(1, 0.3, 0.3), Color(1, 0.8, 0.2), Color(0.4, 0.85, 0.4), Color(0.35, 0.6, 1.0)]
				for i in rb.size():
					b.torus(1.1 - i * 0.1, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.3, 0.2, -0.3)), rb[i], 24, 4)
		return b.build())


func _process(delta: float) -> void:
	for m in _pop.keys():
		if not is_instance_valid(m):
			_pop.erase(m)
			continue
		var t: float = float(_pop[m]) + delta
		_pop[m] = t
		var k := clampf(t / 0.8, 0.0, 1.0)
		var e := 1.0 + 2.2 * pow(k - 1.0, 3.0) + 1.2 * pow(k - 1.0, 2.0)  # ease-out-back
		(m as Node3D).scale = Vector3.ONE * maxf(0.01, e)
		if k >= 1.0:
			_pop.erase(m)
