extends Node3D
## WREN'S NEIGHBOURS ON THE VILLAGE GREEN (Tower Stack, third pass): every tower the family finishes, a new
## neighbour moves into Wren's town - a seeded animal with its own name (neighbour(i): the i-th tower ever built
## always brings the same friend, on every machine) - and comes to live on the VILLAGE GREEN.
## The green grows as the town does: every few neighbours it gets something new (a fountain, bunting, flower beds,
## lamps, a picnic table, a maypole, a kite tree, Wren's statue: GROWS). The newest neighbours stand round the green
## and jump for joy when a tower is finished. The green lies inside the park at the back left, where the TV camera
## and the giant both see it and the builders can walk over to say hello (blocks never drop on it and Rolo's lanes
## miss it). All from the saved number of towers ever built (main.gd "made" state),
## so no new save data: every machine shows the same green.
##   Green.neighbour(i) -> {kind, pic, name}   Green.grown(built) -> pieces open   Green.piece_at(built) -> {} or new piece
##   node.set_made(built) (new neighbours / pieces pop in)   node.cheer()

const Seeded := preload("res://core/seeded.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Creatures := preload("res://core/creatures.gd")

const CENTER := Vector3(-6.0, 0.0, -4.4)  # inside the park, back left (main.gd ARENA 9)
const FACE := 0.63  # radians: the way the neighbours look (towards the stage)
const RADIUS := 2.1
const SHOW := 10  # the newest neighbours standing on the green
## [creature kind, story picture]
const KINDS: Array = [["bunny", "bunny"], ["fox", "fox"], ["frog", "frog"], ["cat", "kitten"], ["dog", "puppy"],
	["sheep", "sheep"], ["penguin", "penguin"], ["bird", "bird"], ["bee", "bumblebee"]]
const NAMES: Array[String] = ["Pip", "Moss", "Bean", "Fern", "Tilly", "Bo", "Nutmeg", "Pebble", "Clover", "Ziggy",
	"Maple", "Dot", "Juno", "Sprout", "Hazel", "Toffee", "Basil", "Poppy", "Biscuit", "Mo", "Sunny", "Wiggles"]
## What the green gets, and after how many towers ever built.
const GROWS: Array[Dictionary] = [
	{"id": "fountain", "at": 2, "pic": "fountain", "line": "A fountain!"},
	{"id": "bunting", "at": 5, "pic": "bunting", "line": "Bunting!"},
	{"id": "flowers", "at": 8, "pic": "flowerpot", "line": "Flower beds!"},
	{"id": "lamps", "at": 12, "pic": "lantern", "line": "Lamps!"},
	{"id": "picnic", "at": 16, "pic": "picnic", "line": "A picnic table!"},
	{"id": "maypole", "at": 21, "pic": "ribbon", "line": "A maypole!"},
	{"id": "kites", "at": 27, "pic": "kite", "line": "A kite tree!"},
	{"id": "statue", "at": 35, "pic": "wren", "line": "Wren's statue!"},
]

var made := -1
var _folk: Array[Node3D] = []  # newest last
var _pieces: Array[Node3D] = []
var _pop := {}


func _ready() -> void:
	name = "Green"
	position = CENTER
	add_child(MeshKit.instance(base_mesh(), false))


## The friend the i-th finished tower (0 = the first ever) brings.
static func neighbour(i: int) -> Dictionary:
	var r := Seeded.rng(Seeded.derive(4242, "folk%d" % i))
	# Steps of 3-5 kinds and 3-7 names: never the same friend twice in a row, every kind and name comes round.
	var k: Array = KINDS[(i * 4 + r.randi() % 2) % KINDS.size()]
	return {"kind": String(k[0]), "pic": String(k[1]), "name": NAMES[(i * 5 + r.randi() % 3) % NAMES.size()], "seed": r.randi() % 1000}


## How many green pieces are there after `built` towers.
static func grown(built: int) -> int:
	var n := 0
	for g in GROWS:
		if built >= int(g.at):
			n += 1
	return n


## The piece exactly `built` towers bring ({} if none).
static func piece_at(built: int) -> Dictionary:
	for g in GROWS:
		if int(g.at) == built:
			return g
	return {}


## Where neighbour slot k (0 = the oldest shown) stands, on the green's edge facing the park.
static func folk_spot(k: int) -> Vector3:
	var a := FACE - 0.9 + k * (1.8 / float(SHOW - 1))  # an arc on the stage's side
	return Vector3(cos(a), 0.0, sin(a)) * (RADIUS - 0.35)


## Every machine: show the green after `built` towers (newly arrived ones pop in).
func set_made(built: int) -> void:
	built = maxi(0, built)
	var grow := made >= 0 and built > made
	made = built
	for k in range(_pieces.size(), grown(built)):
		var p := MeshKit.instance(piece_mesh(k))
		p.position = piece_spot(k)
		add_child(p)
		_pieces.append(p)
		if grow:
			_start_pop(p)
	var first := maxi(0, built - SHOW)
	var want: Array[int] = []
	for i in range(first, built):
		want.append(i)
	var have := {}
	for f in _folk:
		have[int(f.get_meta("i"))] = f
	for f in _folk.duplicate():
		if not want.has(int(f.get_meta("i"))):
			_folk.erase(f)
			f.queue_free()
	for i in want:
		if have.has(i):
			continue
		var d := neighbour(i)
		var c := Creatures.monster(String(d.kind), {"seed": int(d.seed), "scale": 0.75, "lod": "auto"})
		c.set_meta("i", i)
		add_child(c)
		_folk.append(c)
		if grow:
			_start_pop(c)
			Creatures.anim(c).play("jump")
	for k in _folk.size():
		var f: Node3D = _folk[k]
		f.position = folk_spot(k + SHOW - _folk.size())
		Creatures.face_now(f, Vector3(cos(FACE), 0.0, sin(FACE)))


func folk_count() -> int:
	return _folk.size()


func piece_count() -> int:
	return _pieces.size()


## Every machine: the neighbours jump for joy (a tower is finished).
func cheer() -> void:
	for f in _folk:
		if is_instance_valid(f):
			Creatures.anim(f).play("cheer", 1.0)


func _start_pop(n: Node3D) -> void:
	_pop[n] = 0.0
	n.scale = Vector3.ONE * 0.01


func _process(delta: float) -> void:
	for n in _pop.keys():
		if not is_instance_valid(n):
			_pop.erase(n)
			continue
		var t: float = float(_pop[n]) + delta
		_pop[n] = t
		var k := clampf(t / 0.8, 0.0, 1.0)
		var e := 1.0 + 2.2 * pow(k - 1.0, 3.0) + 1.2 * pow(k - 1.0, 2.0)  # ease-out-back
		(n as Node3D).scale = Vector3.ONE * maxf(0.01, e)
		if k >= 1.0:
			_pop.erase(n)


## Where green piece k stands (inside the ring of neighbours).
static func piece_spot(k: int) -> Vector3:
	if k == 0:
		return Vector3(-0.3, 0.0, 0.0)  # the fountain in the middle
	var a := FACE + PI - 1.9 + (k - 1) * (3.8 / float(GROWS.size() - 2))  # round the back, behind the neighbours
	return Vector3(cos(a), 0.0, sin(a)) * 1.45


## The green itself: a round lawn with a cobbled edge and a little sign with a house on it.
static func base_mesh() -> Mesh:
	return ResCache.get_or_make("tower_stack_green_base_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(RADIUS, RADIUS, 0.04, MeshKit.at(Vector3(0, 0.02, 0)), Color(0.4, 0.72, 0.36), 24)
		for k in 22:
			var a := k * TAU / 22.0
			b.box(Vector3(0.32, 0.08, 0.2), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0.04, sin(a)) * RADIUS), Color(0.7, 0.68, 0.64) if k % 2 == 0 else Color(0.6, 0.58, 0.55))
		var post := Transform3D(Basis(Vector3.UP, -FACE + 0.9), Vector3.ZERO)  # the sign post stands beside the neighbours
		b.cylinder(0.04, 0.04, 1.3, post * MeshKit.at(Vector3(RADIUS + 0.2, 0.65, 0)), Color(0.5, 0.35, 0.22), 6)
		b.box(Vector3(0.05, 0.4, 0.6), post * MeshKit.at(Vector3(RADIUS + 0.22, 1.2, 0)), Color(0.95, 0.85, 0.55))
		b.cone(0.18, 0.14, post * MeshKit.at(Vector3(RADIUS + 0.26, 1.27, 0)), Color(0.9, 0.3, 0.3))
		b.box(Vector3(0.02, 0.12, 0.16), post * MeshKit.at(Vector3(RADIUS + 0.26, 1.14, 0)), Color(0.95, 0.95, 1.0))
		return b.build())


## Green piece k (GROWS order), base at y = 0.
static func piece_mesh(k: int) -> Mesh:
	return ResCache.get_or_make("tower_stack_green_piece_v1_%d" % k, func() -> Resource:
		var b := MeshKit.Builder.new()
		match String(GROWS[clampi(k, 0, GROWS.size() - 1)].id):
			"fountain":
				b.cylinder(0.6, 0.65, 0.3, MeshKit.at(Vector3(0, 0.15, 0)), Color(0.75, 0.75, 0.8), 16)
				b.cylinder(0.52, 0.52, 0.04, MeshKit.at(Vector3(0, 0.29, 0)), Color(0.35, 0.65, 1.0), 16)
				b.cylinder(0.08, 0.1, 0.7, MeshKit.at(Vector3(0, 0.6, 0)), Color(0.75, 0.75, 0.8), 8)
				b.sphere(0.16, MeshKit.at(Vector3(0, 1.0, 0)), Color(0.55, 0.8, 1.0), 10)
			"bunting":
				for sx in [-1.0, 1.0]:
					b.cylinder(0.03, 0.03, 1.8, MeshKit.at(Vector3(0, 0.9, sx * 0.6)), Color(0.9, 0.9, 0.92), 6)
				for f in 7:
					var z := -0.48 + f * 0.16
					var sag := 1.65 - 0.2 * (1.0 - pow(z / 0.6, 2.0))
					b.cone(0.1, 0.22, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, sag, z)), [Color(1, 0.3, 0.35), Color(1, 0.85, 0.2), Color(0.3, 0.6, 1.0), Color(0.4, 0.85, 0.4)][f % 4], 4)
			"flowers":
				b.cylinder(0.45, 0.45, 0.12, MeshKit.at(Vector3(0, 0.06, 0)), Color(0.45, 0.3, 0.2), 12)
				for f in 9:
					var a := f * TAU / 9.0
					var p := Vector3(cos(a) * 0.3, 0.3, sin(a) * 0.3)
					b.cylinder(0.015, 0.015, 0.2, MeshKit.at(p - Vector3(0, 0.1, 0)), Color(0.3, 0.6, 0.25), 4)
					b.sphere(0.08, MeshKit.at(p), [Color(1.0, 0.4, 0.6), Color(1.0, 0.9, 0.3), Color(0.7, 0.5, 1.0)][f % 3], 8)
			"lamps":
				for sz in [-0.6, 0.6]:
					b.cylinder(0.035, 0.05, 1.5, MeshKit.at(Vector3(0, 0.75, sz)), Color(0.25, 0.25, 0.3), 6)
					b.sphere(0.13, MeshKit.at(Vector3(0, 1.55, sz)), Color(1.0, 0.92, 0.6), 10)
			"picnic":
				b.box(Vector3(0.9, 0.06, 0.5), MeshKit.at(Vector3(0, 0.5, 0)), Color(0.65, 0.45, 0.28))
				b.box(Vector3(0.88, 0.02, 0.48), MeshKit.at(Vector3(0, 0.54, 0)), Color(0.95, 0.4, 0.4))
				for sx in [-0.35, 0.35]:
					b.box(Vector3(0.06, 0.5, 0.4), MeshKit.at(Vector3(sx, 0.25, 0)), Color(0.55, 0.38, 0.24))
				b.sphere(0.08, MeshKit.at(Vector3(0.15, 0.62, 0.05)), Color(0.9, 0.2, 0.2), 8)
			"maypole":
				b.cylinder(0.05, 0.06, 2.2, MeshKit.at(Vector3(0, 1.1, 0)), Color(0.95, 0.95, 0.95), 8)
				b.sphere(0.12, MeshKit.at(Vector3(0, 2.25, 0)), Color(1.0, 0.85, 0.2), 8)
				for f in 4:
					var a := f * TAU / 4.0
					b.cylinder(0.02, 0.02, 1.6, Transform3D(Basis(Vector3(sin(a), 0, -cos(a)), 0.45), Vector3(cos(a) * 0.35, 1.45, sin(a) * 0.35)), [Color(1, 0.3, 0.4), Color(0.3, 0.6, 1.0), Color(0.4, 0.85, 0.4), Color(1, 0.8, 0.2)][f], 4)
			"kites":
				b.cylinder(0.1, 0.14, 1.3, MeshKit.at(Vector3(0, 0.65, 0)), Color(0.5, 0.35, 0.22), 8)
				b.sphere(0.6, MeshKit.at(Vector3(0, 1.6, 0)), Color(0.3, 0.68, 0.3), 12)
				for f in 3:
					var p := Vector3(-0.3 + f * 0.3, 2.4 + 0.2 * (f % 2), 0.2 * f - 0.2)
					b.box(Vector3(0.04, 0.32, 0.32), Transform3D(Basis(Vector3.RIGHT, PI * 0.25), p), [Color(1, 0.3, 0.4), Color(1, 0.85, 0.2), Color(0.3, 0.6, 1.0)][f])
			_:  # Wren's statue: a stone plinth with a golden Wren on it
				b.box(Vector3(0.6, 0.6, 0.6), MeshKit.at(Vector3(0, 0.3, 0)), Color(0.75, 0.75, 0.78))
				b.sphere(0.28, MeshKit.at(Vector3(0, 0.85, 0)), Color(1.0, 0.8, 0.3), 12)
				b.sphere(0.16, MeshKit.at(Vector3(0.14, 1.08, 0)), Color(1.0, 0.85, 0.4), 10)
				b.cone(0.05, 0.14, Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(0.32, 1.08, 0)), Color(1.0, 0.65, 0.2), 6)
		return b.build())
