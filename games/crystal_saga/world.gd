extends Node3D
## CRYSTAL SAGA: the world. One short journey along a path heading north (-Z), five zones in a row:
##   0 Willowbrook village (practice), 1 the forest, 2 the crystal cave, 3 the Stone Giant's glade,
##   4 the shrine of the Crystal of Light.
## A magic barrier closes the end of each zone (village gate, thorny vines, a crystal wall, dark mist);
## it sinks into the ground with sparkles when the zone is done.
## Everything in reach can be touched (sword, glove, or a TV hero's A) and does something: the well
## splashes, chickens hop, flowers puff petals, signposts spin, houses wobble, trees sway, giant
## mushrooms bounce, crystals chime, chests pop open, villagers wave and point north.
## Every machine builds the same world; the host decides (main.gd) and the visuals follow the
## replicated state ("used" bits, "open" barriers) and "prop" events.
## Cheap for the Frame: the scenery is a few merged meshes, the trees one MultiMesh, the props a few
## small meshes each, one OmniLight (only in the cave).

const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const Classes := preload("res://games/crystal_saga/classes.gd")
const Realm := preload("res://games/crystal_saga/realm.gd")

const ZONES := 5
## The cave's arches: the VR hero walks under them, but the TV camera high above and behind the party looked
## straight into one (a dark wall filling the whole TV / Deck screen in the cave): main.gd hides them from it.
const ARCH_LAYER := 1 << 9
const ZL := 16.0  ## zone length along Z
const HALF_L := 8.0
const HALF_W := 5.0  ## the path's half width (walkable)

enum { WELL, CHICKEN, FLOWER, SIGN, CHEST, CRYSTAL, MUSHROOM, HOUSE, TREE, VILLAGER, DUMMY, TARGET, STONE, ORB, BIG, FRIEND, ROCK, CHOICE,
	QUEST, GIVER, STATUE, BANNER, MAP }
## The glade's giants (sagagen.gd GIANTS: name, body, glow), here so the world needn't load the generator.
const SAGA_GIANTS: Array = [["STONE", Color(0.5, 0.45, 0.6), Color(0.8, 0.4, 1.0)], ["MOSS", Color(0.4, 0.55, 0.38), Color(0.6, 1.0, 0.4)],
	["SNOW", Color(0.8, 0.85, 0.95), Color(0.5, 0.8, 1.0)], ["SAND", Color(0.78, 0.66, 0.45), Color(1.0, 0.75, 0.3)],
	["ROSE", Color(0.7, 0.45, 0.55), Color(1.0, 0.5, 0.75)], ["CLAY", Color(0.7, 0.42, 0.32), Color(1.0, 0.55, 0.35)]]
const KIND_NAMES: Array[String] = ["well", "chicken", "flower", "sign", "chest", "crystal", "mushroom", "house", "tree",
	"villager", "dummy", "target", "stone", "orb", "crystal of light", "friend", "rock", "level-up stone", "quest thing",
	"quest giver", "hero statue", "brave flag", "map table"]
## Quest things that are picked up (they hop away); the others (lanterns, bells) light up and stay.
const QUEST_LIGHTS: Array[String] = ["lantern", "bell"]
## The hero statues behind the spawn (classes.gd ORDER), the brave flag and the realm's map table.
const STATUE_X: Array[float] = [-3.2, -1.6, 0.0, 1.6, 3.2]
const STATUE_Z := 7.15
const BANNER_AT := Vector3(-4.4, 0.0, 2.9)
const MAP_AT := Vector3(3.2, 0.0, -4.0)
## Where the region stones stand in the village (map phase), by the gate.
const MAP_SPOTS: Array[Vector2] = [Vector2(-1.9, -6.5), Vector2(0.0, -6.8), Vector2(1.9, -6.5)]
## Kinds the sword passes through without poking (only spells hit the target).
const SPELL_ONLY: Array[int] = [TARGET]

## id -> {"kind", "zone", "home": Vector3, "node": Node3D, "r": touch radius, "c": centre offset,
##        "anim"/"lid"/"board"/"bubble": extra nodes}
var props: Array[Dictionary] = []
## The journey's plan (sagagen.gd generate()): the forest, cave and glade come from it.
var plan := {}
var choice_ids: Array[int] = []  ## the two level-up stones (hidden until an offer)
var offer: Array = []  ## skill ids on the stones right now
var places: Array[Node3D] = []  ## Willowbrook's places (restored ones visible)
var ruins: Array[Node3D] = []  ## ...and the rubble where they will be
var village := 0
var barriers: Array[Node3D] = []
var open_count := 0
var used_bits := 0
var dummy_id := -1
var target_id := -1
var stone_id := -1
var orb_id := -1
var big_id := -1
var friend_id := -1
var giver_id := -1
var quest_ids: Array[int] = []
var statue_ids: Array[int] = []  ## classes.gd ORDER
var banner_id := -1
var map_id := -1
var used_hi := 0  ## used bits of props 62.. (the second int, net state "used2")
var offer_kind := "skill"  ## the stones show skills ("skill") or realm regions ("region")
var map_marks: Node3D  ## the map table's region discs
var _flag: Node3D
var blockers: Array = []  ## [Vector2 centre, radius]
var cave_light: OmniLight3D
var shards: Node3D  ## the broken Crystal of Light (floating pieces)
var restored := 0.0  ## 0 = broken, 1 = whole again (animated)
var _wobble := {}  ## id -> seconds left
var _spin := {}  ## id -> seconds left
var _t := 0.0


static func center(zone: int) -> Vector3:
	return Vector3(0.0, 0.0, -zone * ZL)


## z of the barrier between zone k and k + 1.
static func wall_z(k: int) -> float:
	return -k * ZL - HALF_L


static func zone_of(p: Vector3) -> int:
	return clampi(int(floor((-p.z + HALF_L) / ZL)), 0, ZONES - 1)


## Where players come into a zone.
static func entrance(zone: int) -> Vector3:
	if zone == 0:
		return Vector3(0.0, 0.0, 5.6)
	return center(zone) + Vector3(0.0, 0.0, HALF_L - 1.5)


## Keep a walker on the path, out of the well and pedestals, and behind closed barriers.
func walk_clamp(from: Vector3, to: Vector3, r: float) -> Vector3:
	var p := to
	p.x = clampf(p.x, -HALF_W + r, HALF_W - r)
	p.z = clampf(p.z, wall_z(ZONES - 1) + r, HALF_L - r)
	for k in range(open_count, ZONES - 1):
		var wz := wall_z(k)
		if from.z > wz:
			p.z = maxf(p.z, wz + r + 0.25)
			break
	for b in blockers:
		var c: Vector2 = b[0]
		var br: float = b[1]
		var d := Vector2(p.x - c.x, p.z - c.y)
		if d.length() < br + r:
			var n := d.normalized() if d.length() > 0.001 else Vector2(1.0, 0.0)
			var q := c + n * (br + r)
			p.x = q.x
			p.z = q.y
	return p


# --- Building ------------------------------------------------------------------------------------

func build(p: Dictionary, village_places: int = 0) -> void:
	plan = p
	_scenery()
	_trees()
	_barriers()
	_props()
	_village()
	set_village(village_places, false)
	cave_light = OmniLight3D.new()
	cave_light.omni_range = 14.0
	cave_light.light_energy = 1.4
	cave_light.light_color = Color(0.6, 0.85, 1.0)
	cave_light.shadow_enabled = false
	cave_light.position = center(2) + Vector3(0.0, 4.0, 0.0)
	cave_light.visible = false
	add_child(cave_light)


func _scenery() -> void:
	var b := MeshKit.Builder.new()
	var end_z := wall_z(ZONES - 1)
	# Ground: meadow everywhere, a sandy path, the cave floor, the shrine's marble.
	b.box(Vector3(70.0, 0.2, 110.0), MeshKit.at(Vector3(0.0, -0.12, -32.0)), Color(0.42, 0.7, 0.32))
	var paths: Array = plan.get("path", [Color(0.6, 0.5, 0.34), Color(0.38, 0.36, 0.48)])
	if plan.has("ground"):
		b.box(Vector3(70.0, 0.2, ZL * 3.0 + 20.0), MeshKit.at(Vector3(0.0, -0.1, center(2).z - 4.0)), plan.ground)
	for k in ZONES:
		var c := center(k)
		var path := [Color(0.82, 0.7, 0.48), paths[0], paths[1], Color(0.62, 0.62, 0.5), Color(0.9, 0.9, 0.95)][k] as Color
		b.box(Vector3(HALF_W * 2.0 + 0.6, 0.06, ZL), MeshKit.at(c + Vector3(0.0, -0.02, 0.0)), path)
	# Distant mountains all round (the big sky needs a horizon).
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 16:
		var a := TAU * i / 16.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(70.0, 85.0)
		var h := rng.randf_range(18.0, 34.0)
		var pos := Vector3(cos(a) * r, h * 0.5 - 1.0, -32.0 + sin(a) * r)
		b.cone(rng.randf_range(14.0, 20.0), h, MeshKit.at(pos), Color(0.45, 0.55, 0.75).lerp(Color(0.6, 0.5, 0.7), rng.randf()), 8)
		b.cone(5.0, h * 0.28, MeshKit.at(pos + Vector3(0.0, h * 0.37, 0.0)), Color(0.95, 0.97, 1.0), 8)
	# Village: fences along the path, a little bridge-like gate frame, lamp posts.
	for sx in [-1.0, 1.0]:
		for i in 7:
			var z := 7.0 - i * 2.3
			if absf(z - 4.0) < 1.6 or absf(z + 3.0) < 1.6:
				continue
			b.box(Vector3(0.08, 0.6, 2.2), MeshKit.at(Vector3(sx * 5.9, 0.45, z)), Color(0.7, 0.5, 0.3))
			b.box(Vector3(0.14, 0.9, 0.14), MeshKit.at(Vector3(sx * 5.9, 0.45, z + 1.1)), Color(0.6, 0.42, 0.25))
	b.box(Vector3(14.0, 0.8, 0.3), MeshKit.at(Vector3(0.0, 0.4, HALF_L + 0.2)), Color(0.66, 0.48, 0.3))
	for sx in [-1.0, 1.0]:
		b.cylinder(0.25, 0.3, 3.6, MeshKit.at(Vector3(sx * 5.4, 1.8, wall_z(0))), Color(0.6, 0.42, 0.25), 8)
	b.box(Vector3(11.4, 0.4, 0.5), MeshKit.at(Vector3(0.0, 3.5, wall_z(0))), Color(0.6, 0.42, 0.25))
	# Back houses (not touchable, they fill the village).
	for hp in [Vector3(-11.0, 0.0, 1.0), Vector3(11.0, 0.0, -1.0), Vector3(-10.0, 0.0, 7.0), Vector3(10.5, 0.0, 6.0)]:
		_house(b, hp, Color(0.95, 0.88, 0.72), Color(0.75, 0.3, 0.25), signf(-hp.x))
	# Cave: high rock walls with arches and glowing crystals in them.
	var c2 := center(2)
	for sx in [-1.0, 1.0]:
		for i in 6:
			var z2 := c2.z + HALF_L - 1.4 - i * 2.7
			b.rounded_box(Vector3(2.6, 5.5 + (i % 2) * 1.2, 3.2), 0.6, MeshKit.at(Vector3(sx * 6.9, 2.6, z2), Vector3.ONE, Vector3(0.0, 0.2 * (i % 3), 0.0)), Color(0.36, 0.33, 0.46))
			_crystal_bits(b, Vector3(sx * 5.75, 3.2 + (i % 2) * 0.7, z2 + 0.6), (plan.get("gem", Color(0.5, 0.85, 1.0)) as Color) if i % 2 == 0 else Color(0.85, 0.55, 1.0), 0.7)
	var ab := MeshKit.Builder.new()
	for i in 3:
		var za := c2.z + 5.0 - i * 5.0
		ab.torus(6.6, 0.9, MeshKit.at(Vector3(0.0, 0.0, za), Vector3(1.0, 1.0, 1.0), Vector3(PI * 0.5, 0.0, 0.0)), Color(0.33, 0.3, 0.42), 20, 6)
	var arches := MeshKit.instance(ab.build(), false)
	arches.name = "CaveArches"
	arches.layers = ARCH_LAYER
	add_child(arches)
	# Glade: a ring of standing stones.
	var c3 := center(3)
	for i in 10:
		var a2 := TAU * i / 10.0
		var sp := c3 + Vector3(cos(a2) * 7.4, 0.0, sin(a2) * 7.4)
		if absf(sp.x) < 3.0:
			continue
		b.rounded_box(Vector3(1.0, 2.6, 0.7), 0.2, MeshKit.at(sp + Vector3(0.0, 1.2, 0.0), Vector3.ONE, Vector3(0.0, -a2, 0.05)), Color(0.6, 0.6, 0.62))
	# Shrine: marble steps, pillars, the pedestal.
	var c4 := center(4)
	b.cylinder(4.2, 4.4, 0.25, MeshKit.at(c4 + Vector3(0.0, 0.1, -2.0)), Color(0.95, 0.95, 1.0), 24)
	b.cylinder(1.0, 1.2, 0.8, MeshKit.at(c4 + Vector3(0.0, 0.4, -2.0)), Color(0.85, 0.85, 0.95), 16)
	for i in 6:
		var a3 := TAU * i / 6.0 + 0.5
		var pp := c4 + Vector3(cos(a3) * 5.8, 0.0, -2.0 + sin(a3) * 5.8)
		b.cylinder(0.35, 0.4, 4.2, MeshKit.at(pp + Vector3(0.0, 2.1, 0.0)), Color(0.96, 0.95, 0.9), 10)
		b.box(Vector3(1.0, 0.3, 1.0), MeshKit.at(pp + Vector3(0.0, 4.3, 0.0)), Color(0.96, 0.95, 0.9))
	b.box(Vector3(14.0, 1.2, 0.6), MeshKit.at(Vector3(0.0, 0.6, end_z - 0.3)), Color(0.9, 0.9, 0.95))
	var m := MeshKit.instance(b.build(), false)
	add_child(m)


## A cottage at p; its door and window face side (+1 = +X, -1 = -X).
static func _house(b: MeshKit.Builder, p: Vector3, wall: Color, roof: Color, side: float) -> void:
	b.rounded_box(Vector3(3.0, 2.4, 3.0), 0.1, MeshKit.at(p + Vector3(0.0, 1.2, 0.0)), wall)
	b.prism(4, 2.5, 1.6, MeshKit.at(p + Vector3(0.0, 3.2, 0.0), Vector3(1.0, 1.0, 1.0), Vector3(0.0, PI * 0.25, 0.0)), roof)
	b.box(Vector3(0.1, 1.4, 0.8), MeshKit.at(p + Vector3(side * 1.52, 0.7, 0.0)), Color(0.5, 0.32, 0.2))
	b.box(Vector3(0.1, 0.6, 0.6), MeshKit.at(p + Vector3(side * 1.52, 1.6, 0.9)), Color(1.0, 0.9, 0.5), true)


static func _crystal_bits(b: MeshKit.Builder, p: Vector3, col: Color, s: float) -> void:
	b.prism(6, 0.16 * s, 0.9 * s, MeshKit.at(p, Vector3.ONE, Vector3(0.0, 0.0, 0.3)), col, true)
	b.prism(6, 0.12 * s, 0.6 * s, MeshKit.at(p + Vector3(0.18 * s, -0.15 * s, 0.1), Vector3.ONE, Vector3(0.2, 0.0, -0.4)), col.lightened(0.2), true)
	b.prism(6, 0.1 * s, 0.5 * s, MeshKit.at(p + Vector3(-0.2 * s, -0.2 * s, -0.1), Vector3.ONE, Vector3(-0.2, 0.0, 0.5)), col, true)


func _trees() -> void:
	var xfs: Array = []
	var cols := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan.get("seed", 7)) + 7
	var leaf: Color = plan.get("leaf", Color(0.8, 1.0, 0.8))
	# Forest zone: thick on both sides; a few around the village and the glade.
	for i in 70:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := rng.randf_range(wall_z(0) - 0.5, wall_z(1) + 0.5)
		var x := side * rng.randf_range(6.8, 16.0)
		xfs.append(MeshKit.at(Vector3(x, 0.0, z), Vector3.ONE * rng.randf_range(1.6, 2.6), Vector3(0.0, rng.randf() * TAU, 0.0)))
		cols.append(leaf.lerp(Color(1.0, 0.95, 0.75), rng.randf() * 0.5))
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(15.0, 26.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r * 0.6 + (2.0 if i < 11 else -48.0))
		if absf(p.x) < 8.0:
			p.x = signf(p.x + 0.01) * 9.0
		xfs.append(MeshKit.at(p, Vector3.ONE * rng.randf_range(1.8, 2.8), Vector3(0.0, rng.randf() * TAU, 0.0)))
		cols.append(Color(1.0, 1.0, 1.0))
	add_child(MeshKit.scatter(MeshKit.prop("tree"), xfs, cols))


func _barriers() -> void:
	for k in ZONES - 1:
		var g := Node3D.new()
		g.position = Vector3(0.0, 0.0, wall_z(k))
		var b := MeshKit.Builder.new()
		match k:
			0:  # the village gate: two wooden doors
				for sx in [-1.0, 1.0]:
					b.rounded_box(Vector3(4.9, 2.6, 0.18), 0.05, MeshKit.at(Vector3(sx * 2.55, 1.3, 0.0)), Color(0.62, 0.42, 0.24))
					for j in 4:
						b.box(Vector3(0.08, 2.5, 0.22), MeshKit.at(Vector3(sx * (0.8 + j * 1.15), 1.3, 0.0)), Color(0.48, 0.32, 0.18))
					b.sphere(0.12, MeshKit.at(Vector3(sx * 0.35, 1.3, 0.14)), Color(1.0, 0.8, 0.3), 8)
			1:  # thorny vines with flowers
				for j in 9:
					var x := -4.6 + j * 1.15
					b.tube(Vector3(x, 0.0, 0.0), Vector3(x + 0.6, 2.6, 0.2 * (j % 2)), 0.18, 0.08, Color(0.25, 0.5, 0.2), 6)
					b.tube(Vector3(x + 0.8, 0.0, 0.0), Vector3(x - 0.3, 2.3, -0.2), 0.16, 0.07, Color(0.3, 0.55, 0.22), 6)
					b.sphere(0.16, MeshKit.at(Vector3(x + 0.3, 1.2 + 0.4 * (j % 3), 0.25)), Color(1.0, 0.5, 0.7), 8, true)
			2:  # a wall of crystal
				for j in 8:
					b.prism(6, 0.55, 2.4 + 0.6 * (j % 3), MeshKit.at(Vector3(-4.4 + j * 1.25, 1.3, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.08 * (j % 2 * 2 - 1))), (plan.get("gem", Color(0.55, 0.85, 1.0)) as Color) if j % 2 == 0 else Color(0.8, 0.6, 1.0), true)
			_:  # dark mist (the Stone Giant's grumpiness)
				for j in 10:
					b.sphere(0.9 + 0.3 * (j % 3), MeshKit.at(Vector3(-4.5 + j * 1.0, 0.8 + 0.6 * (j % 2), 0.0)), Color(0.32, 0.18, 0.45), 10, j % 3 == 0)
		g.add_child(MeshKit.instance(b.build(), false))
		add_child(g)
		barriers.append(g)


# --- Props ---------------------------------------------------------------------------------------

func _add(kind: int, pos: Vector3, node: Node3D, r: float, c: Vector3) -> int:
	add_child(node)
	node.position = pos
	props.append({"kind": kind, "zone": zone_of(pos), "home": pos, "node": node, "r": r, "c": c})
	return props.size() - 1


func _mesh_prop(kind: int, pos: Vector3, mesh: Mesh, r: float, c: Vector3, yaw: float = 0.0) -> int:
	var n := Node3D.new()
	var mi := MeshKit.instance(mesh, false)
	mi.rotation.y = yaw
	n.add_child(mi)
	return _add(kind, pos, n, r, c)


func _props() -> void:
	# --- Zone 0: the village ---
	dummy_id = _mesh_prop(DUMMY, Vector3(-0.9, 0.0, 3.2), _dummy_mesh(), 0.45, Vector3(0.0, 1.1, 0.0))
	target_id = _mesh_prop(TARGET, Vector3(1.4, 1.7, -1.5), _target_mesh(), 0.6, Vector3.ZERO)
	stone_id = _mesh_prop(STONE, Vector3(2.6, 0.0, 3.0), _stone_mesh(), 0.55, Vector3(0.0, 0.5, 0.0))
	_mesh_prop(WELL, Vector3(-3.2, 0.0, 0.6), _well_mesh(), 0.9, Vector3(0.0, 0.9, 0.0))
	blockers.append([Vector2(-3.2, 0.6), 0.85])
	for hp in [Vector3(-7.4, 0.0, 4.0), Vector3(7.4, 0.0, -3.0)]:
		var hb := MeshKit.Builder.new()
		_house(hb, Vector3.ZERO, Color(1.0, 0.9, 0.75), Color(0.35, 0.5, 0.85) if hp.x > 0 else Color(0.8, 0.35, 0.3), signf(-hp.x))
		_mesh_prop(HOUSE, hp, hb.build(), 1.0, Vector3(signf(-hp.x) * 1.55, 1.2, 0.0))
	for cp in [Vector3(2.2, 0.0, 1.6), Vector3(3.6, 0.0, 0.2), Vector3(-1.8, 0.0, -2.6)]:
		var ch := Creatures.monster("bird", {"color": Color(1.0, 1.0, 0.96), "color2": Color(1.0, 0.6, 0.2), "seed": int(cp.x * 10)})
		var holder := Node3D.new()
		holder.add_child(ch)
		ch.scale = Vector3.ONE * 0.45
		var id := _add(CHICKEN, cp, holder, 0.35, Vector3(0.0, 0.3, 0.0))
		props[id]["anim"] = Creatures.anim(ch)
	for fp in [Vector3(-4.5, 0.0, 5.6), Vector3(4.5, 0.0, 5.2), Vector3(-4.5, 0.0, -1.8), Vector3(4.5, 0.0, 1.8)]:
		_mesh_prop(FLOWER, fp, _planter_mesh(int(fp.z * 3.0)), 0.5, Vector3(0.0, 0.75, 0.0))
	_sign(Vector3(4.3, 0.0, -6.4))
	_villager(Vector3(-2.6, 0.0, -5.0), 0, Color(0.9, 0.4, 0.3))
	_villager(Vector3(3.9, 0.0, 5.9), 1, Color(0.3, 0.6, 0.9))
	_chest(Vector3(-4.3, 0.0, -6.4))
	# The hero statues (classes.gd ORDER: bonk one to become that hero), the brave flag, the realm's map table.
	for i in STATUE_X.size():
		statue_ids.append(_statue(Vector3(STATUE_X[i], 0.0, STATUE_Z), i))
	banner_id = _banner(BANNER_AT)
	map_id = _map_table(MAP_AT)
	# --- Zones 1-3: the forest, the cave, the glade: from the journey's plan (sagagen.gd) ---
	var gem: Color = plan.get("gem", Color(0.5, 0.85, 1.0))
	for q in plan.get("props", []):
		var kind := int(q[0])
		var pos := Vector3(float(q[1]), 0.0, float(q[2]))
		var r: float = q[3]
		var z := zone_of(pos)
		match kind:
			TREE:
				_mesh_prop(TREE, pos, MeshKit.prop("tree"), r, Vector3(signf(-pos.x) * 0.3, 1.4, 0.0))
			MUSHROOM:
				_mesh_prop(MUSHROOM, pos, _mushroom_mesh(), r, Vector3(0.0, 1.15, 0.0))
			FLOWER:
				_mesh_prop(FLOWER, pos, _planter_mesh(int(absf(pos.z) * 3.0 + pos.x)), r, Vector3(0.0, 0.75, 0.0))
			SIGN:
				_sign(pos)
			CHEST:
				_chest(pos)
			CRYSTAL:
				var cb := MeshKit.Builder.new()
				var col := gem.lerp(Color(0.85, 0.55, 1.0), 0.35 * float(props.size() % 3))
				_crystal_bits(cb, Vector3(0.0, 0.55, 0.0), col, 1.4)
				cb.rounded_box(Vector3(0.7, 0.5, 0.7), 0.1, MeshKit.at(Vector3(0.0, 0.25, 0.0)), Color(0.4, 0.37, 0.5))
				_mesh_prop(CRYSTAL, pos, cb.build(), r, Vector3(0.0, 1.0, 0.0))
			ROCK:
				_mesh_prop(ROCK, pos, _rock_mesh(z, r, gem, props.size()), r, Vector3(0.0, r * 0.8, 0.0), float(props.size()) * 1.7)
				blockers.append([Vector2(pos.x, pos.z), r])
			GIVER:
				_giver(pos)
			QUEST:
				_quest_thing(pos, quest_ids.size())
	var c2 := center(2)
	orb_id = _mesh_prop(ORB, c2 + Vector3(0.0, 0.0, -1.0), _orb_mesh(), 0.5, Vector3(0.0, 1.35, 0.0))
	blockers.append([Vector2(0.0, c2.z - 1.0), 0.45])
	var c3 := center(3)
	var gl: Array = SAGA_GIANTS[clampi(int(plan.get("giant", 0)), 0, SAGA_GIANTS.size() - 1)]
	if plan.has("giant_look"):
		gl = ["", plan.giant_look[0], plan.giant_look[1]]
	var giant := Creatures.monster("golem", {"color": (gl[1] as Color).lightened(0.15), "color2": (gl[2] as Color).lerp(Color(0.5, 0.85, 0.5), 0.4)})
	var gh := Node3D.new()
	gh.add_child(giant)
	giant.scale = Vector3.ONE * 2.2
	giant.rotation.y = -0.6
	friend_id = _add(FRIEND, c3 + Vector3(3.6, 0.0, -5.2), gh, 1.2, Vector3(-0.6, 1.4, 0.4))
	props[friend_id]["anim"] = Creatures.anim(giant)
	gh.visible = false
	# The level-up stones (main.gd shows them in a cleared zone with a spell and a sword trick on top).
	for i in CHOICE_SPOTS.size():
		var sn := Node3D.new()
		sn.add_child(MeshKit.instance(_choice_base_mesh(i), false))
		var icon := Node3D.new()
		icon.position.y = 1.35
		sn.add_child(icon)
		var cid := _add(CHOICE, Vector3(0.0, 0.0, 30.0 + i * 3.0), sn, 0.55, Vector3(0.0, 1.0, 0.0))
		props[cid]["icon"] = icon
		sn.visible = false
		choice_ids.append(cid)
	# --- Zone 4: the shrine ---
	var c4 := center(4)
	big_id = _mesh_prop(BIG, c4 + Vector3(0.0, 0.0, -2.0), _big_base_mesh(), 1.0, Vector3(0.0, 1.9, 0.0))
	blockers.append([Vector2(0.0, c4.z - 2.0), 1.15])
	shards = Node3D.new()
	(props[big_id]["node"] as Node3D).add_child(shards)
	shards.position = Vector3(0.0, 1.9, 0.0)
	var sm := _shard_mesh()
	for i in 5:
		var s := MeshKit.instance(sm, false)
		shards.add_child(s)
	for sp in [Vector3(-3.2, 0.0, 1.2), Vector3(3.2, 0.0, 1.2), Vector3(-3.2, 0.0, -5.2), Vector3(3.2, 0.0, -5.2)]:
		var cb2 := MeshKit.Builder.new()
		_crystal_bits(cb2, Vector3(0.0, 0.9, 0.0), Color(1.0, 0.95, 0.6), 1.3)
		cb2.cylinder(0.35, 0.4, 0.7, MeshKit.at(Vector3(0.0, 0.35, 0.0)), Color(0.9, 0.9, 0.95), 10)
		_mesh_prop(CRYSTAL, c4 + sp, cb2.build(), 0.6, Vector3(0.0, 1.2, 0.0))


func _sign(p: Vector3) -> void:
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.cylinder(0.06, 0.07, 1.6, MeshKit.at(Vector3(0.0, 0.8, 0.0)), Color(0.55, 0.38, 0.22), 6)
	n.add_child(MeshKit.instance(b.build(), false))
	var board := Node3D.new()
	board.position.y = 1.4
	var bb := MeshKit.Builder.new()
	bb.rounded_box(Vector3(0.12, 0.3, 0.9), 0.04, MeshKit.at(Vector3(0.0, 0.0, -0.25)), Color(0.8, 0.6, 0.35))
	bb.cone(0.22, 0.25, MeshKit.at(Vector3(0.0, 0.0, -0.82), Vector3(1.0, 1.0, 0.4), Vector3(-PI * 0.5, 0.0, 0.0)), Color(0.8, 0.6, 0.35), 4)
	bb.box(Vector3(0.14, 0.08, 0.5), MeshKit.at(Vector3(0.0, 0.0, -0.3)), Color(0.3, 0.6, 0.3))
	board.add_child(MeshKit.instance(bb.build(), false))
	n.add_child(board)
	var id := _add(SIGN, p, n, 0.5, Vector3(0.0, 1.4, -0.2))
	props[id]["board"] = board


func _villager(p: Vector3, i: int, col: Color) -> void:
	var v := Creatures.humanoid({"class": "villager" if i == 0 else "farmer", "outfit": col, "seed": 40 + i * 9,
		"hair_style": "bun" if i == 0 else "short"})
	var holder := Node3D.new()
	holder.add_child(v)
	v.scale = Vector3.ONE * 1.25
	v.rotation.y = atan2(-p.x, 5.0 - p.z) if p.z < 0.0 else PI * 0.8
	var bubble := Node3D.new()
	bubble.position = Vector3(0.0, 2.1, 0.0)
	var bb := MeshKit.Builder.new()
	bb.sphere(0.26, MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.0, 0.45)), Color(1.0, 1.0, 1.0))
	_crystal_bits(bb, Vector3(0.0, -0.1, 0.1), Color(0.6, 0.9, 1.0), 0.45)
	bubble.add_child(MeshKit.instance(bb.build(), false))
	var ab := MeshKit.Builder.new()  # an arrow pointing north
	ab.box(Vector3(0.1, 0.06, 0.4), MeshKit.at(Vector3(0.0, 0.0, 0.2)), Color(1.0, 0.85, 0.3), true)
	ab.cone(0.16, 0.25, MeshKit.at(Vector3(0.0, 0.0, -0.1), Vector3(1.0, 1.0, 0.4), Vector3(-PI * 0.5, 0.0, 0.0)), Color(1.0, 0.85, 0.3), 3, true)
	var arrow := MeshKit.instance(ab.build(), false)
	arrow.position = Vector3(0.0, -0.45, -0.1)
	bubble.add_child(arrow)
	bubble.visible = false
	holder.add_child(bubble)
	var id := _add(VILLAGER, p, holder, 0.55, Vector3(0.0, 1.1, 0.0))
	props[id]["anim"] = Creatures.anim(v)
	props[id]["bubble"] = bubble
	props[id]["body"] = v
	blockers.append([Vector2(p.x, p.z), 0.35])


func _chest(p: Vector3) -> void:
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.8, 0.5, 0.5), 0.05, MeshKit.at(Vector3(0.0, 0.25, 0.0)), Color(0.65, 0.4, 0.2))
	b.box(Vector3(0.84, 0.08, 0.54), MeshKit.at(Vector3(0.0, 0.45, 0.0)), Color(1.0, 0.8, 0.3))
	b.box(Vector3(0.7, 0.05, 0.4), MeshKit.at(Vector3(0.0, 0.5, 0.0)), Color(1.0, 0.85, 0.3), true)
	n.add_child(MeshKit.instance(b.build(), false))
	var lid := Node3D.new()
	lid.position = Vector3(0.0, 0.5, -0.25)
	var lb := MeshKit.Builder.new()
	lb.rounded_box(Vector3(0.82, 0.2, 0.52), 0.08, MeshKit.at(Vector3(0.0, 0.08, 0.25)), Color(0.72, 0.45, 0.22))
	lb.box(Vector3(0.12, 0.16, 0.06), MeshKit.at(Vector3(0.0, 0.0, 0.52)), Color(1.0, 0.8, 0.3))
	lid.add_child(MeshKit.instance(lb.build(), false))
	n.add_child(lid)
	n.rotation.y = PI * 0.5 * signf(p.x)
	var id := _add(CHEST, p, n, 0.55, Vector3(0.0, 0.5, 0.0))
	props[id]["lid"] = lid


# --- Generated rocks, the level-up stones ---------------------------------------------------------

## A rock in the way: a mossy boulder and log (forest), a crystal cluster (cave), a standing stone (glade).
static func _rock_mesh(zone: int, r: float, gem: Color, salt: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match zone:
		2:
			b.rounded_box(Vector3(r * 1.6, r * 0.6, r * 1.6), 0.1, MeshKit.at(Vector3(0.0, r * 0.3, 0.0)), Color(0.38, 0.35, 0.48))
			_crystal_bits(b, Vector3(0.0, r * 0.9, 0.0), gem, r * 2.0)
		3:
			b.rounded_box(Vector3(r * 1.4, r * 3.4, r * 1.0), 0.15, MeshKit.at(Vector3(0.0, r * 1.6, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.06)), Color(0.6, 0.6, 0.63))
			b.star(5, r * 0.35, r * 0.15, 0.03, MeshKit.at(Vector3(0.0, r * 2.2, r * 0.5)), Color(0.6, 1.0, 0.8), true)
		_:
			if salt % 2 == 0:
				b.ellipsoid(Vector3(r, r * 0.75, r * 0.9), MeshKit.at(Vector3(0.0, r * 0.6, 0.0)), Color(0.55, 0.56, 0.58), 10)
				b.dome(r * 0.7, MeshKit.at(Vector3(0.1, r * 1.2, 0.0), Vector3(1.0, 0.35, 1.0)), Color(0.35, 0.65, 0.3), 10)
			else:
				b.cylinder(r * 0.55, r * 0.55, r * 2.4, MeshKit.at(Vector3(0.0, r * 0.55, 0.0), Vector3.ONE, Vector3(0.0, 0.0, PI * 0.5)), Color(0.55, 0.38, 0.22), 10)
				b.cylinder(r * 0.42, r * 0.42, 0.04, MeshKit.at(Vector3(r * 1.21, r * 0.55, 0.0), Vector3.ONE, Vector3(0.0, 0.0, PI * 0.5)), Color(0.85, 0.7, 0.45), 10)
				b.sphere(r * 0.18, MeshKit.at(Vector3(-r * 0.4, r * 1.1, 0.0)), Color(0.95, 0.3, 0.35), 6)
	return b.build()


## A rune stone with a glowing ring (0 = the spell stone, 1 = the sword-trick stone).
static func _choice_base_mesh(i: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var glow := Color(0.85, 0.55, 1.0) if i == 0 else Color(0.6, 0.9, 1.0)
	b.cylinder(0.38, 0.48, 0.9, MeshKit.at(Vector3(0.0, 0.45, 0.0)), Color(0.55, 0.52, 0.62), 8)
	b.cylinder(0.45, 0.4, 0.1, MeshKit.at(Vector3(0.0, 0.92, 0.0)), Color(0.65, 0.62, 0.72), 8)
	b.torus(0.62, 0.05, MeshKit.at(Vector3(0.0, 0.05, 0.0)), glow, 24, 4, true)
	b.star(4, 0.14, 0.06, 0.03, MeshKit.at(Vector3(0.0, 0.5, 0.44)), glow, true)
	return b.build()


## The picture on top of a level-up stone, in 3D: a big fireball, a snowflake, twin sparks, a long sword,
## a sword in a spinning ring, a big golden sword.
static func skill_mesh(id: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var up := Vector3(0.0, 0.0, 0.0)
	match id:
		"splash":
			b.sphere(0.24, MeshKit.at(Vector3.ZERO), Color(1.0, 0.55, 0.15), 12, true)
			b.cone(0.2, 0.35, MeshKit.at(Vector3(0.0, 0.3, 0.0)), Color(1.0, 0.85, 0.3), 8, true)
			b.sphere(0.12, MeshKit.at(Vector3(0.0, 0.0, 0.16)), Color(1.0, 0.95, 0.6), 8, true)
		"ice":
			for k in 3:
				b.box(Vector3(0.06, 0.62, 0.06), MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.0, 0.0, k * PI / 3.0)), Color(0.75, 0.95, 1.0), true)
			b.sphere(0.09, MeshKit.at(Vector3.ZERO), Color(1.0, 1.0, 1.0), 8, true)
		"twin":
			b.star(4, 0.17, 0.07, 0.05, MeshKit.at(Vector3(-0.17, 0.05, 0.0)), Color(0.85, 0.6, 1.0), true)
			b.star(4, 0.17, 0.07, 0.05, MeshKit.at(Vector3(0.17, -0.05, 0.0)), Color(0.6, 0.85, 1.0), true)
		"long", "spin", "mighty":
			var col := Color(0.85, 0.92, 1.0) if id != "mighty" else Color(1.0, 0.85, 0.35)
			var ln := 0.95 if id == "long" else 0.7
			var s := 1.4 if id == "mighty" else 1.0
			b.box(Vector3(0.08 * s, ln, 0.03 * s), MeshKit.at(Vector3(0.0, 0.08 + ln * 0.5 - 0.3, 0.0)), col, id == "mighty")
			b.box(Vector3(0.3 * s, 0.05, 0.06), MeshKit.at(Vector3(0.0, -0.24, 0.0)), Color(1.0, 0.8, 0.3))
			b.cylinder(0.03, 0.03, 0.18, MeshKit.at(Vector3(0.0, -0.35, 0.0)), Color(0.35, 0.25, 0.5), 6)
			if id == "spin":
				b.torus(0.38, 0.03, MeshKit.at(Vector3(0.0, 0.05, 0.0), Vector3.ONE, up), Color(0.5, 1.0, 0.8), 20, 4, true)
			if id == "mighty":
				b.star(5, 0.12, 0.05, 0.03, MeshKit.at(Vector3(0.0, 0.25, 0.05)), Color(1.0, 1.0, 0.7), true)
	return b.build()


## Main: show the level-up stones in `zone` with these skills (spell, trick, one more), or hide them (empty).
## In the village (zone 0) they are the MAP stones: ids are realm slots, region_biomes their biomes.
func set_offer(zone: int, ids: Array, region_biomes: Array = []) -> void:
	offer = ids.duplicate()
	offer_kind = "region" if zone == 0 and not ids.is_empty() else "skill"
	for i in choice_ids.size():
		var p: Dictionary = props[choice_ids[i]]
		var n: Node3D = p["node"]
		var icon: Node3D = p["icon"]
		for ch in icon.get_children():
			ch.queue_free()
		if i >= ids.size():
			n.visible = false
			continue
		if offer_kind == "region":
			icon.add_child(MeshKit.instance(region_mesh(int(region_biomes[i]) if i < region_biomes.size() else 0), false))
		else:
			icon.add_child(MeshKit.instance(skill_mesh(String(ids[i])), false))
		var at: Vector2 = MAP_SPOTS[i] if offer_kind == "region" else CHOICE_SPOTS[i]
		var pos := center(zone) + Vector3(at.x, 0.0, at.y)
		n.position = pos
		p["home"] = pos
		p["zone"] = zone
		if not n.visible and is_inside_tree():
			n.scale = Vector3.ONE * 0.1
			n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK)
		n.visible = true


## The skill on level-up stone `id` ("" if it isn't one, or nothing is offered).
func skill_on(id: int) -> String:
	var i := choice_ids.find(id)
	return String(offer[i]) if i >= 0 and i < offer.size() and offer_kind == "skill" else ""


## The realm slot on map stone `id` (-1 if it isn't one, or the stones aren't the map).
func region_on(id: int) -> int:
	var i := choice_ids.find(id)
	return int(offer[i]) if i >= 0 and i < offer.size() and offer_kind == "region" else -1


# --- Willowbrook's places (crystal shards bring them back; saga.gd PLACES order) ----------------------

## Where each place stands (x, z) and which way it faces the path.
const PLACE_AT: Array[Vector2] = [Vector2(-9.2, -5.0), Vector2(8.8, 2.2), Vector2(-7.9, -1.4), Vector2(0.0, 0.0),
	Vector2(12.6, -4.6), Vector2(-14.6, -1.8), Vector2(9.4, -7.0), Vector2(-13.4, -7.2), Vector2(7.6, 6.4), Vector2(0.0, -4.6)]
const CHOICE_SPOTS: Array[Vector2] = [Vector2(-2.0, -4.2), Vector2(0.0, -4.9), Vector2(2.0, -4.2)]  ## = sagagen.gd CHOICE_AT

var _blades: Node3D


func _village() -> void:
	for i in PLACE_AT.size():
		var at := Vector3(PLACE_AT[i].x, 0.0, PLACE_AT[i].y)
		var n := Node3D.new()
		n.position = at
		n.add_child(MeshKit.instance(_place_mesh(i), false))
		if i == 0:
			_blades = Node3D.new()
			_blades.position = Vector3(1.05, 4.6, 0.0)
			_blades.rotation.y = PI * 0.5
			var bb := MeshKit.Builder.new()
			for k in 4:
				var a := k * PI * 0.5
				bb.box(Vector3(0.5, 2.6, 0.05), MeshKit.at(Vector3(-sin(a) * 1.4, cos(a) * 1.4, 0.0), Vector3.ONE, Vector3(0.0, 0.0, a)), Color(0.95, 0.92, 0.85))
			bb.sphere(0.22, MeshKit.at(Vector3.ZERO), Color(0.75, 0.3, 0.25), 8)
			_blades.add_child(MeshKit.instance(bb.build(), false))
			n.add_child(_blades)
		n.visible = false
		add_child(n)
		places.append(n)
		var ru := Node3D.new()
		ru.position = at
		if i != 3 and i != 9:  # the lanterns and the rainbow leave no rubble
			ru.add_child(MeshKit.instance(_ruin_mesh(i), false))
		add_child(ru)
		ruins.append(ru)


## Show the first `n` places (animate: they pop up with a bounce).
func set_village(n: int, animate: bool) -> void:
	village = n
	for i in places.size():
		var on := i < n
		var pl: Node3D = places[i]
		if on and not pl.visible and animate and is_inside_tree():
			pl.scale = Vector3(1.0, 0.05, 1.0)
			pl.create_tween().tween_property(pl, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK)
		pl.visible = on
		ruins[i].visible = not on


func place_center(i: int) -> Vector3:
	return Vector3(PLACE_AT[i].x, 1.5, PLACE_AT[i].y)


static func _ruin_mesh(i: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	for k in 4:
		var a := TAU * k / 4.0 + i
		b.rounded_box(Vector3(0.7, 0.35 + 0.15 * (k % 2), 0.55), 0.08, MeshKit.at(Vector3(cos(a) * 0.7, 0.18, sin(a) * 0.6), Vector3.ONE, Vector3(0.0, a, 0.1 * k)), Color(0.55, 0.53, 0.56))
	_crystal_bits(b, Vector3(0.0, 0.9, 0.0), Color(0.45, 0.3, 0.6), 0.6)
	return b.build()


static func _place_mesh(i: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match i:
		0:  # the windmill (blades are their own node)
			b.cylinder(0.9, 1.3, 4.6, MeshKit.at(Vector3(0.0, 2.3, 0.0)), Color(0.96, 0.92, 0.82), 10)
			b.cone(1.25, 1.5, MeshKit.at(Vector3(0.0, 5.3, 0.0)), Color(0.8, 0.35, 0.28), 10)
			b.box(Vector3(0.1, 1.2, 0.7), MeshKit.at(Vector3(1.2, 0.6, 0.0)), Color(0.5, 0.32, 0.2))
		1:  # the fountain
			b.cylinder(1.3, 1.4, 0.5, MeshKit.at(Vector3(0.0, 0.25, 0.0)), Color(0.82, 0.82, 0.86), 16)
			b.cylinder(1.15, 1.15, 0.06, MeshKit.at(Vector3(0.0, 0.48, 0.0)), Color(0.4, 0.7, 1.0), 16, true)
			b.cylinder(0.16, 0.22, 1.3, MeshKit.at(Vector3(0.0, 0.9, 0.0)), Color(0.85, 0.85, 0.9), 8)
			b.cylinder(0.5, 0.35, 0.18, MeshKit.at(Vector3(0.0, 1.55, 0.0)), Color(0.85, 0.85, 0.9), 12)
			b.sphere(0.28, MeshKit.at(Vector3(0.0, 1.85, 0.0), Vector3(1.0, 1.4, 1.0)), Color(0.55, 0.85, 1.0), 10, true)
		2:  # the flower garden: beds of flowers
			for k in 3:
				var z := -1.0 + k * 1.0
				b.box(Vector3(2.4, 0.25, 0.7), MeshKit.at(Vector3(0.0, 0.12, z)), Color(0.45, 0.3, 0.18))
				for f in 6:
					var x := -1.0 + f * 0.4
					var col: Color = [Color(1.0, 0.45, 0.6), Color(1.0, 0.85, 0.3), Color(0.6, 0.5, 1.0), Color(1.0, 0.55, 0.3)][(f + k) % 4]
					b.cylinder(0.02, 0.02, 0.4, MeshKit.at(Vector3(x, 0.4, z)), Color(0.3, 0.6, 0.25), 4)
					b.sphere(0.11, MeshKit.at(Vector3(x, 0.62, z), Vector3(1.0, 0.6, 1.0)), col, 6)
		3:  # lanterns down both sides of the path
			for sx in [-1.0, 1.0]:
				for k in 4:
					var z2 := 6.0 - k * 4.0
					b.cylinder(0.05, 0.07, 2.2, MeshKit.at(Vector3(sx * 5.45, 1.1, z2)), Color(0.3, 0.28, 0.35), 6)
					b.box(Vector3(0.3, 0.06, 0.06), MeshKit.at(Vector3(sx * 5.35, 2.15, z2)), Color(0.3, 0.28, 0.35))
					b.sphere(0.16, MeshKit.at(Vector3(sx * 5.25, 1.98, z2)), Color(1.0, 0.85, 0.45), 8, true)
		4:  # the bakery: a cottage with a chimney and a big golden loaf on the roof
			_house(b, Vector3.ZERO, Color(1.0, 0.85, 0.65), Color(0.6, 0.38, 0.25), -1.0)
			b.box(Vector3(0.4, 1.2, 0.4), MeshKit.at(Vector3(0.6, 3.8, 0.6)), Color(0.6, 0.35, 0.3))
			b.capsule(0.3, 1.1, MeshKit.at(Vector3(-1.7, 2.1, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.9, 0.65, 0.3))
		5:  # the duck pond
			b.cylinder(2.2, 2.2, 0.05, MeshKit.at(Vector3(0.0, 0.03, 0.0), Vector3(1.0, 1.0, 0.7)), Color(0.35, 0.65, 1.0), 20, true)
			for k in 3:
				var dp := Vector3(-0.8 + k * 0.8, 0.15, -0.3 + 0.3 * (k % 2))
				b.ellipsoid(Vector3(0.22, 0.14, 0.15), MeshKit.at(dp), Color(1.0, 0.95, 0.5), 8)
				b.sphere(0.1, MeshKit.at(dp + Vector3(0.18, 0.15, 0.0)), Color(1.0, 0.95, 0.5), 6)
				b.cone(0.04, 0.1, MeshKit.at(dp + Vector3(0.3, 0.14, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -PI * 0.5)), Color(1.0, 0.55, 0.15), 4)
		6:  # the market stall: a striped awning and fruit
			b.box(Vector3(2.0, 0.9, 0.9), MeshKit.at(Vector3(0.0, 0.45, 0.0)), Color(0.65, 0.45, 0.28))
			for sx2 in [-0.95, 0.95]:
				b.cylinder(0.05, 0.05, 2.2, MeshKit.at(Vector3(sx2, 1.1, -0.4)), Color(0.55, 0.38, 0.22), 6)
			for k2 in 5:
				b.box(Vector3(0.42, 0.08, 1.2), MeshKit.at(Vector3(-0.84 + k2 * 0.42, 2.2, 0.1), Vector3.ONE, Vector3(-0.3, 0.0, 0.0)), Color(1.0, 0.35, 0.35) if k2 % 2 == 0 else Color(1.0, 1.0, 0.95))
			for f2 in 6:
				b.sphere(0.13, MeshKit.at(Vector3(-0.7 + f2 * 0.28, 1.0, 0.1 * (f2 % 2))), [Color(1.0, 0.3, 0.3), Color(1.0, 0.65, 0.2), Color(0.5, 0.9, 0.3)][f2 % 3], 6)
		7:  # the tall tower with a flag
			b.cylinder(1.2, 1.4, 7.0, MeshKit.at(Vector3(0.0, 3.5, 0.0)), Color(0.8, 0.78, 0.74), 10)
			b.cone(1.6, 2.4, MeshKit.at(Vector3(0.0, 8.2, 0.0)), Color(0.35, 0.45, 0.85), 10)
			b.cylinder(0.04, 0.04, 1.4, MeshKit.at(Vector3(0.0, 10.0, 0.0)), Color(0.4, 0.3, 0.2), 4)
			b.box(Vector3(0.9, 0.5, 0.04), MeshKit.at(Vector3(0.45, 10.4, 0.0)), Color(1.0, 0.85, 0.3))
			for k3 in 3:
				b.box(Vector3(0.1, 0.6, 0.45), MeshKit.at(Vector3(1.27, 2.0 + k3 * 1.8, 0.0)), Color(1.0, 0.9, 0.5), true)
		8:  # a statue of the hero, sword up
			b.box(Vector3(1.2, 0.8, 1.2), MeshKit.at(Vector3(0.0, 0.4, 0.0)), Color(0.8, 0.8, 0.84))
			b.capsule(0.32, 1.3, MeshKit.at(Vector3(0.0, 1.45, 0.0)), Color(0.85, 0.85, 0.9))
			b.sphere(0.26, MeshKit.at(Vector3(0.0, 2.3, 0.0)), Color(0.85, 0.85, 0.9), 10)
			b.box(Vector3(0.08, 1.2, 0.04), MeshKit.at(Vector3(0.35, 2.7, 0.0)), Color(0.75, 0.9, 1.0), true)
			b.box(Vector3(0.3, 0.06, 0.06), MeshKit.at(Vector3(0.35, 2.1, 0.0)), Color(1.0, 0.8, 0.3))
		9:  # a crystal rainbow over the village
			var cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.65, 0.25), Color(1.0, 0.95, 0.35), Color(0.4, 0.9, 0.4),
				Color(0.4, 0.65, 1.0), Color(0.7, 0.45, 1.0)]
			for k4 in 6:
				b.torus(9.0 - k4 * 0.3, 0.14, MeshKit.at(Vector3(0.0, -2.0, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), cols[k4], 40, 4, true)
	return b.build()


# --- Prop meshes ---

static func _dummy_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.06, 0.06, 1.0, MeshKit.at(Vector3(0.0, 0.5, 0.0)), Color(0.5, 0.35, 0.2), 6)
	b.capsule(0.25, 0.8, MeshKit.at(Vector3(0.0, 1.1, 0.0)), Color(0.9, 0.78, 0.45))
	b.sphere(0.2, MeshKit.at(Vector3(0.0, 1.65, 0.0)), Color(0.92, 0.8, 0.5), 10)
	b.box(Vector3(0.9, 0.1, 0.1), MeshKit.at(Vector3(0.0, 1.3, 0.0)), Color(0.5, 0.35, 0.2))
	b.torus(0.5, 0.04, MeshKit.at(Vector3(0.0, 0.04, 0.0)), Color(0.4, 1.0, 0.8), 20, 4, true)
	return b.build()


static func _target_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var up := Vector3(PI * 0.5, 0.0, 0.0)
	b.torus(0.5, 0.06, MeshKit.at(Vector3.ZERO, Vector3.ONE, up), Color(1.0, 0.6, 0.2), 24, 6, true)
	b.torus(0.3, 0.05, MeshKit.at(Vector3.ZERO, Vector3.ONE, up), Color(1.0, 0.95, 0.5), 20, 6, true)
	b.sphere(0.12, MeshKit.at(Vector3.ZERO), Color(1.0, 0.5, 0.2), 10, true)
	return b.build()


static func _stone_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.45, 0.5, 0.4), MeshKit.at(Vector3(0.0, 0.45, 0.0)), Color(0.6, 0.62, 0.66), 12)
	b.star(5, 0.2, 0.09, 0.04, MeshKit.at(Vector3(0.0, 0.55, 0.38)), Color(0.4, 1.0, 0.8), true)
	b.torus(0.6, 0.04, MeshKit.at(Vector3(0.0, 0.04, 0.0)), Color(0.4, 1.0, 0.8), 20, 4, true)
	return b.build()


static func _well_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.8, 0.85, 0.8, MeshKit.at(Vector3(0.0, 0.4, 0.0)), Color(0.65, 0.63, 0.6), 16)
	b.cylinder(0.66, 0.66, 0.05, MeshKit.at(Vector3(0.0, 0.72, 0.0)), Color(0.3, 0.55, 0.9), 16)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.12, 1.4, 0.12), MeshKit.at(Vector3(sx * 0.72, 1.3, 0.0)), Color(0.5, 0.34, 0.2))
	b.prism(4, 1.15, 0.5, MeshKit.at(Vector3(0.0, 2.15, 0.0), Vector3(1.0, 1.0, 0.7), Vector3(0.0, PI * 0.25, 0.0)), Color(0.75, 0.3, 0.25))
	b.cylinder(0.12, 0.12, 0.25, MeshKit.at(Vector3(0.0, 1.45, 0.0)), Color(0.55, 0.38, 0.22), 8)
	return b.build()


static func _planter_mesh(seed_value: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.8, 0.55, 0.8), 0.08, MeshKit.at(Vector3(0.0, 0.27, 0.0)), Color(0.6, 0.4, 0.25))
	b.box(Vector3(0.7, 0.05, 0.7), MeshKit.at(Vector3(0.0, 0.55, 0.0)), Color(0.35, 0.25, 0.15))
	var cols: Array[Color] = [Color(1.0, 0.45, 0.6), Color(1.0, 0.85, 0.3), Color(0.6, 0.5, 1.0), Color(1.0, 0.55, 0.3)]
	for i in 5:
		var a := TAU * i / 5.0 + seed_value
		var p := Vector3(cos(a) * 0.22, 0.75 + 0.06 * (i % 2), sin(a) * 0.22)
		b.cylinder(0.015, 0.015, 0.2, MeshKit.at(p - Vector3(0.0, 0.1, 0.0)), Color(0.3, 0.6, 0.25), 4)
		b.sphere(0.07, MeshKit.at(p, Vector3(1.0, 0.5, 1.0)), cols[(i + absi(seed_value)) % cols.size()], 8)
		b.sphere(0.03, MeshKit.at(p + Vector3(0.0, 0.03, 0.0)), Color(1.0, 0.95, 0.5), 6)
	return b.build()


static func _mushroom_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.18, 0.24, 0.9, MeshKit.at(Vector3(0.0, 0.45, 0.0)), Color(0.95, 0.92, 0.82), 10)
	b.dome(0.62, MeshKit.at(Vector3(0.0, 0.85, 0.0), Vector3(1.0, 0.7, 1.0)), Color(0.9, 0.25, 0.3), 14)
	for i in 6:
		var a := TAU * i / 6.0
		b.sphere(0.08, MeshKit.at(Vector3(cos(a) * 0.38, 1.12, sin(a) * 0.38), Vector3(1.0, 0.5, 1.0)), Color(1.0, 1.0, 0.95), 6)
	return b.build()


static func _orb_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.25, 0.35, 1.0, MeshKit.at(Vector3(0.0, 0.5, 0.0)), Color(0.45, 0.42, 0.55), 10)
	b.cylinder(0.32, 0.25, 0.12, MeshKit.at(Vector3(0.0, 1.06, 0.0)), Color(0.55, 0.5, 0.65), 10)
	b.sphere(0.2, MeshKit.at(Vector3(0.0, 1.35, 0.0)), Color(1.0, 0.95, 0.4), 14, true)
	return b.build()


static func _big_base_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.torus(0.9, 0.06, MeshKit.at(Vector3(0.0, 0.85, 0.0)), Color(1.0, 0.85, 0.4), 24, 4, true)
	return b.build()


static func _shard_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.prism(6, 0.16, 0.7, MeshKit.at(Vector3.ZERO), Color(0.75, 0.9, 1.0), true)
	b.cone(0.16, 0.25, MeshKit.at(Vector3(0.0, 0.47, 0.0)), Color(0.85, 0.95, 1.0), 6, true)
	return b.build()


# --- State ---------------------------------------------------------------------------------------

func prop_center(id: int) -> Vector3:
	var p: Dictionary = props[id]
	return (p["node"] as Node3D).global_position + (p["c"] as Vector3)


## Used bits: props 0..61 in "used", 62.. in "used2" (main.gd _use()).
const USED_SPLIT := 62


static func used_bit(lo: int, hi: int, id: int) -> bool:
	if id < 0:
		return false
	if id < USED_SPLIT:
		return (lo >> id) & 1 == 1
	return (hi >> (id - USED_SPLIT)) & 1 == 1


func is_used(id: int) -> bool:
	return used_bit(used_bits, used_hi, id)


func set_used(bits: int, hi: int = -1) -> void:
	var was := used_bits
	var was_hi := used_hi
	used_bits = bits
	if hi >= 0:
		used_hi = hi
	for id in props.size():
		var now := is_used(id)
		if now == used_bit(was, was_hi, id):
			continue
		var p: Dictionary = props[id]
		var n: Node3D = p["node"]
		match int(p["kind"]):
			CHEST:
				var lid: Node3D = p["lid"]
				lid.create_tween().tween_property(lid, "rotation:x", -1.9 if now else 0.0, 0.35).set_trans(Tween.TRANS_BACK)
			DUMMY, STONE, TARGET:
				n.visible = not now
			ORB:
				n.scale = Vector3(1.0, 0.75, 1.0) if now else Vector3.ONE
			FRIEND:
				n.visible = now
			QUEST:
				_quest_done_look(id, now)


## Barriers 0..count-1 are open (they sink into the ground).
func set_open(count: int) -> void:
	for k in barriers.size():
		var g: Node3D = barriers[k]
		var want := -3.2 if k < count else 0.0
		if k < count and k >= open_count and is_inside_tree():
			var tw := g.create_tween()
			tw.tween_property(g, "position:y", want, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_callback(func() -> void: g.visible = false)
		else:
			g.position.y = want
			g.visible = k >= count
	open_count = count


## Every machine: a prop was poked.
func react(id: int) -> void:
	var p: Dictionary = props[id]
	match int(p["kind"]):
		SIGN:
			_spin[id] = 1.2
		CHICKEN:
			var n: Node3D = p["node"]
			(p["anim"] as Object).call("play", "jump", 0.5)
			var home: Vector3 = p["home"]
			var to := home + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
			var tw := n.create_tween()
			tw.tween_property(n, "position", to + Vector3(0.0, 0.7, 0.0), 0.25).set_ease(Tween.EASE_OUT)
			tw.tween_property(n, "position", to, 0.25).set_ease(Tween.EASE_IN)
			n.rotation.y = randf() * TAU
		VILLAGER:
			var an: Object = p["anim"]
			an.call("play", "wave", 1.6)
			var bub: Node3D = p["bubble"]
			bub.visible = true
			bub.scale = Vector3.ONE * 0.2
			bub.create_tween().tween_property(bub, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
			_wobble[id] = 3.0
		FRIEND:
			(p["anim"] as Object).call("play", "wave" if randf() < 0.5 else "cheer", 1.5)
		GIVER, STATUE:
			(p["anim"] as Object).call("play", "cheer" if int(p["kind"]) == STATUE else "wave", 1.4)
		QUEST:
			if p.has("anim"):
				(p["anim"] as Object).call("play", "jump", 0.5)
			_wobble[id] = 0.7
		_:
			_wobble[id] = 0.7


func animate(delta: float, zone: int) -> void:
	_t += delta
	cave_light.visible = zone == 2
	for id in _wobble.keys():
		var left: float = float(_wobble[id]) - delta
		var p: Dictionary = props[id]
		var n: Node3D = p["node"]
		var kind: int = p["kind"]
		if left <= 0.0:
			_wobble.erase(id)
			n.scale = Vector3.ONE
			n.rotation.z = 0.0
			if kind == VILLAGER:
				(p["bubble"] as Node3D).visible = false
			continue
		_wobble[id] = left
		var k := left / 0.7
		match kind:
			TREE:
				n.rotation.z = sin(_t * 18.0) * 0.08 * k
			HOUSE:
				n.scale = Vector3(1.0 + sin(_t * 30.0) * 0.04 * k, 1.0 - sin(_t * 30.0) * 0.05 * k, 1.0)
			VILLAGER:
				var bub: Node3D = p["bubble"]
				bub.position.y = 2.1 + 0.06 * sin(_t * 5.0)
				var body: Node3D = p["body"]
				body.rotation.y = lerp_angle(body.rotation.y, PI, 1.0 - exp(-4.0 * delta))
			_:
				var s := 1.0 + sin(_t * 26.0) * 0.18 * k
				n.scale = Vector3(1.0 / sqrt(maxf(s, 0.3)), s, 1.0 / sqrt(maxf(s, 0.3)))
	for id in _spin.keys():
		var left2: float = float(_spin[id]) - delta
		var board: Node3D = props[id]["board"]
		if left2 <= 0.0:
			_spin.erase(id)
			board.rotation.y = 0.0
			continue
		_spin[id] = left2
		board.rotation.y += delta * 14.0 * minf(1.0, left2)
	# Gentle idle life: the practice targets bob, the orb and the crystal float.
	if not is_used(target_id):
		var tn: Node3D = props[target_id]["node"]
		tn.position.y = 1.7 + 0.08 * sin(_t * 2.0)
		tn.rotation.y = sin(_t * 0.7) * 0.3
	var on: Node3D = props[orb_id]["node"]
	on.rotation.y += delta * (0.4 if is_used(orb_id) else 1.5)
	# The broken Crystal of Light: five shards drift apart; restored = they spin together into one.
	var i := 0
	for s in shards.get_children():
		var sn := s as Node3D
		var a := TAU * i / 5.0 + _t * (0.3 + restored * 2.0)
		var spread := lerpf(0.75, 0.0, restored)
		sn.position = Vector3(cos(a) * spread, 0.15 * sin(_t * 1.3 + i) * (1.0 - restored), sin(a) * spread)
		sn.rotation = Vector3(lerpf(0.5 + 0.2 * i, 0.0, restored), a, lerpf(0.4, 0.0, restored))
		sn.scale = Vector3.ONE * lerpf(1.0, 2.2, restored)
		i += 1
	shards.position.y = 1.9 + 0.1 * sin(_t * 1.5)
	# The level-up stones' pictures spin and bob; the windmill turns.
	for cid in choice_ids:
		var ic: Node3D = props[cid]["icon"]
		ic.rotation.y += delta * 1.6
		ic.position.y = 1.35 + 0.08 * sin(_t * 2.5 + cid)
	if giver_id >= 0:
		var gb: Node3D = props[giver_id]["bubble"]
		gb.position.y = 2.25 + 0.06 * sin(_t * 2.2)
	if _flag != null:
		_flag.rotation.y = 0.15 * sin(_t * 1.7)
	if _blades != null and village > 0:
		_blades.rotate_object_local(Vector3.FORWARD, delta * 0.8)


# --- Realm, heroes and quests (saga-deep) ----------------------------------------------------------

## A hero statue on a little plinth (classes.gd ORDER[i]): bonk it to become that hero. Locked ones are dark stone.
func _statue(p: Vector3, i: int) -> int:
	var id_name: String = Classes.ORDER[i]
	var inf: Dictionary = Classes.INFO[id_name]
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.cylinder(0.42, 0.48, 0.3, MeshKit.at(Vector3(0.0, 0.15, 0.0)), Color(0.7, 0.68, 0.74), 10)
	b.torus(0.5, 0.04, MeshKit.at(Vector3(0.0, 0.31, 0.0)), inf.color, 20, 4, true)
	n.add_child(MeshKit.instance(b.build(), false))
	var hero := Creatures.humanoid({"class": String(inf.look), "weapon": String(inf.weapon), "seed": 70 + i * 5})
	hero.position.y = 0.3
	hero.rotation.y = 0.0  # facing the TV camera (south)
	n.add_child(hero)
	var lock := Node3D.new()
	var lb := MeshKit.Builder.new()
	lb.rounded_box(Vector3(0.9, 1.25, 0.9), 0.15, MeshKit.at(Vector3(0.0, 0.92, 0.0)), Color(0.45, 0.44, 0.5))
	lb.torus(0.12, 0.035, MeshKit.at(Vector3(0.0, 1.2, 0.47), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(1.0, 0.8, 0.3), 12, 4)
	lb.rounded_box(Vector3(0.26, 0.22, 0.08), 0.03, MeshKit.at(Vector3(0.0, 1.05, 0.47)), Color(1.0, 0.8, 0.3))
	lock.add_child(MeshKit.instance(lb.build(), false))
	lock.visible = false
	n.add_child(lock)
	var id := _add(STATUE, p, n, 0.45, Vector3(0.0, 0.8, 0.0))
	props[id]["hero"] = hero
	props[id]["lock"] = lock
	props[id]["anim"] = Creatures.anim(hero)
	props[id]["class"] = id_name
	blockers.append([Vector2(p.x, p.z), 0.4])
	return id


## Statues whose hero isn't unlocked yet wear a stone cover with a golden padlock.
func set_heroes_unlocked(ids: Array) -> void:
	for sid in statue_ids:
		var on := ids.has(String(props[sid]["class"]))
		(props[sid]["hero"] as Node3D).visible = on
		(props[sid]["lock"] as Node3D).visible = not on


## The BRAVE flag by the well: a white flag with a leaf (gentle) or a red one with a flame (brave). Hidden until
## brave mode is unlocked.
func _banner(p: Vector3) -> int:
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.cylinder(0.05, 0.06, 2.4, MeshKit.at(Vector3(0.0, 1.2, 0.0)), Color(0.55, 0.38, 0.22), 6)
	b.sphere(0.09, MeshKit.at(Vector3(0.0, 2.45, 0.0)), Color(1.0, 0.8, 0.3), 8)
	b.cylinder(0.3, 0.35, 0.15, MeshKit.at(Vector3(0.0, 0.07, 0.0)), Color(0.6, 0.58, 0.62), 8)
	n.add_child(MeshKit.instance(b.build(), false))
	_flag = Node3D.new()
	_flag.position = Vector3(0.0, 2.0, 0.0)
	n.add_child(_flag)
	var id := _add(BANNER, p, n, 0.45, Vector3(0.0, 1.6, 0.0))
	set_brave(false, false)
	return id


func set_brave(brave: bool, shown: bool) -> void:
	if _flag == null:
		return
	for c in _flag.get_children():
		c.queue_free()
	var b := MeshKit.Builder.new()
	var cloth := Color(0.92, 0.25, 0.22) if brave else Color(0.95, 0.95, 0.9)
	b.box(Vector3(0.04, 0.55, 0.85), MeshKit.at(Vector3(0.0, 0.0, 0.45)), cloth)
	if brave:
		b.sphere(0.13, MeshKit.at(Vector3(0.05, -0.05, 0.45)), Color(1.0, 0.6, 0.15), 8, true)
		b.cone(0.11, 0.25, MeshKit.at(Vector3(0.05, 0.12, 0.45)), Color(1.0, 0.85, 0.3), 6, true)
	else:
		b.ellipsoid(Vector3(0.03, 0.1, 0.18), MeshKit.at(Vector3(0.04, 0.0, 0.45), Vector3.ONE, Vector3(0.6, 0.0, 0.0)), Color(0.35, 0.75, 0.3), 8)
	_flag.add_child(MeshKit.instance(b.build(), false))
	if banner_id >= 0:
		(props[banner_id]["node"] as Node3D).visible = shown


## The realm's map table: a round stone table with a little disc for every region (realm.gd x, row), roads between
## them; set_realm colours them: beaten = gold with a star, open = glowing, not yet reached = dark.
func _map_table(p: Vector3) -> int:
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.cylinder(0.25, 0.35, 0.8, MeshKit.at(Vector3(0.0, 0.4, 0.0)), Color(0.55, 0.52, 0.58), 10)
	b.cylinder(0.85, 0.85, 0.1, MeshKit.at(Vector3(0.0, 0.85, 0.0)), Color(0.72, 0.6, 0.42), 20)
	b.cylinder(0.78, 0.78, 0.02, MeshKit.at(Vector3(0.0, 0.91, 0.0)), Color(0.55, 0.75, 0.45), 20)
	b.cylinder(0.09, 0.09, 0.06, MeshKit.at(Vector3(0.0, 0.94, 0.62)), Color(0.95, 0.85, 0.65), 10)  # Willowbrook
	n.add_child(MeshKit.instance(b.build(), false))
	map_marks = Node3D.new()
	map_marks.position.y = 0.93
	n.add_child(map_marks)
	var id := _add(MAP, p, n, 0.85, Vector3(0.0, 0.9, 0.0))
	blockers.append([Vector2(p.x, p.z), 0.8])
	return id


## Where a region sits on the table (local x, z): Willowbrook at the near edge, row 4 at the far edge.
static func map_spot(region: Dictionary) -> Vector3:
	return Vector3(float(region.x) * 0.6, 0.0, 0.62 - int(region.depth) * 0.3)


func set_realm(realm: Dictionary, cleared: Array, open: Array) -> void:
	if map_marks == null or realm.is_empty():
		return
	for c in map_marks.get_children():
		c.queue_free()
	var b := MeshKit.Builder.new()
	var regions: Array = realm.regions
	for i in regions.size():
		var a := map_spot(regions[i])
		for j in regions[i].links:
			if int(j) > i:
				var c2 := map_spot(regions[int(j)])
				b.tube(a + Vector3(0.0, 0.01, 0.0), c2 + Vector3(0.0, 0.01, 0.0), 0.012, 0.012, Color(0.9, 0.8, 0.55), 4)
		if int(regions[i].depth) == 1:
			b.tube(a + Vector3(0.0, 0.01, 0.0), Vector3(0.0, 0.01, 0.62), 0.012, 0.012, Color(0.9, 0.8, 0.55), 4)
	for i2 in regions.size():
		var at := map_spot(regions[i2])
		var bio: Dictionary = Realm.BIOMES[int(regions[i2].biome)]
		var done := cleared.has(i2)
		var on := open.has(i2)
		var col: Color = (bio.glow as Color) if on else Color(0.3, 0.3, 0.34)
		b.cylinder(0.07, 0.08, 0.05, MeshKit.at(at + Vector3(0.0, 0.025, 0.0)), Color(1.0, 0.85, 0.35) if done else col, 10, on and not done)
		if done:
			b.star(5, 0.06, 0.025, 0.02, MeshKit.at(at + Vector3(0.0, 0.11, 0.0)), Color(1.0, 0.95, 0.6), true)
		elif on:
			b.prism(6, 0.025, 0.12, MeshKit.at(at + Vector3(0.0, 0.11, 0.0)), (bio.gem as Color), true)
	map_marks.add_child(MeshKit.instance(b.build(), false))


## The quest giver at the region's gate: a villager in the biome's look with a bubble showing what to find
## (the quest thing, in 3D) and a dot for each one still to find.
func _giver(p: Vector3) -> void:
	var q: Dictionary = plan.get("quest", {})
	var v := Creatures.humanoid({"class": String(q.get("giver_look", "villager")), "outfit": (plan.get("gem", Color(0.5, 0.85, 1.0)) as Color),
		"seed": int(plan.get("seed", 1)) % 97})
	var holder := Node3D.new()
	holder.add_child(v)
	v.scale = Vector3.ONE * 1.25
	v.rotation.y = 0.0  # facing the heroes coming in (+Z)
	var bubble := Node3D.new()
	bubble.position = Vector3(0.0, 2.25, 0.0)
	var bb := MeshKit.Builder.new()
	bb.sphere(0.34, MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.0, 0.4)), Color(1.0, 1.0, 1.0))
	bb.cone(0.1, 0.2, MeshKit.at(Vector3(0.0, -0.36, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), Color(1.0, 1.0, 1.0), 6)
	bubble.add_child(MeshKit.instance(bb.build(), false))
	var thing := quest_mesh_node(String(q.get("item", "gem")), 0.55)
	thing.position = Vector3(0.0, -0.12, 0.15)
	bubble.add_child(thing)
	var dots := Node3D.new()
	dots.position = Vector3(0.0, 0.5, 0.0)
	bubble.add_child(dots)
	holder.add_child(bubble)
	giver_id = _add(GIVER, p, holder, 0.5, Vector3(0.0, 1.1, 0.0))
	props[giver_id]["anim"] = Creatures.anim(v)
	props[giver_id]["bubble"] = bubble
	props[giver_id]["dots"] = dots
	props[giver_id]["body"] = v
	blockers.append([Vector2(p.x, p.z), 0.35])
	set_quest_count(0)


## The giver's dots: gold for each found, dim for each still to find; a big star when the quest is done.
func set_quest_count(found: int) -> void:
	if giver_id < 0:
		return
	var dots: Node3D = props[giver_id]["dots"]
	for c in dots.get_children():
		c.queue_free()
	var need := int((plan.get("quest", {}) as Dictionary).get("need", 3))
	var b := MeshKit.Builder.new()
	if found >= need:
		b.star(5, 0.2, 0.09, 0.05, MeshKit.at(Vector3.ZERO), Color(1.0, 0.85, 0.3), true)
	else:
		for k in need:
			var x := (k - (need - 1) * 0.5) * 0.2
			b.sphere(0.06, MeshKit.at(Vector3(x, 0.0, 0.0)), Color(1.0, 0.85, 0.3) if k < found else Color(0.45, 0.45, 0.5), 8, k < found)
	dots.add_child(MeshKit.instance(b.build(), false))


## A quest thing in the region: a lost lamb / penguin chick / frog, a lantern, a gem, a starfish, a balloon, a bell.
func _quest_thing(p: Vector3, i: int) -> void:
	var item := String((plan.get("quest", {}) as Dictionary).get("item", "gem"))
	var n := quest_mesh_node(item, 1.0, i)
	var holder := Node3D.new()
	holder.add_child(n)
	var c := Vector3(0.0, 0.45, 0.0)
	var id := _add(QUEST, p, holder, 0.45, c)
	props[id]["thing"] = n
	props[id]["item"] = item
	if n.has_meta("anim"):
		props[id]["anim"] = n.get_meta("anim")
	quest_ids.append(id)


## A quest thing to look at (also drawn small in the giver's bubble). s: scale.
static func quest_mesh_node(item: String, s: float, salt: int = 0) -> Node3D:
	var root := Node3D.new()
	match item:
		"sheep", "penguin", "frog", "bunny":
			var cr := Creatures.monster(item, {"seed": 30 + salt})
			cr.scale = Vector3.ONE * 0.55 * s
			root.add_child(cr)
			root.set_meta("anim", Creatures.anim(cr))
		_:
			var b := MeshKit.Builder.new()
			match item:
				"lantern":
					b.cylinder(0.04, 0.05, 1.0, MeshKit.at(Vector3(0.0, 0.5, 0.0)), Color(0.3, 0.28, 0.32), 6)
					b.box(Vector3(0.3, 0.06, 0.3), MeshKit.at(Vector3(0.0, 1.02, 0.0)), Color(0.3, 0.28, 0.32))
					b.rounded_box(Vector3(0.26, 0.32, 0.26), 0.04, MeshKit.at(Vector3(0.0, 1.22, 0.0)), Color(0.45, 0.42, 0.5))
					b.cone(0.2, 0.14, MeshKit.at(Vector3(0.0, 1.45, 0.0)), Color(0.3, 0.28, 0.32), 4)
				"gem":
					_crystal_bits(b, Vector3(0.0, 0.25, 0.0), Color(0.6, 0.9, 1.0), 0.9)
				"star":
					b.star(5, 0.26, 0.11, 0.08, MeshKit.at(Vector3(0.0, 0.3, 0.0), Vector3.ONE, Vector3(-0.3, 0.0, 0.0)), Color(1.0, 0.6, 0.45))
				"balloon":
					b.ellipsoid(Vector3(0.22, 0.27, 0.22), MeshKit.at(Vector3(0.0, 1.1, 0.0)), Color(1.0, 0.45, 0.55), 12)
					b.cone(0.05, 0.08, MeshKit.at(Vector3(0.0, 0.8, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), Color(1.0, 0.45, 0.55), 6)
					b.cylinder(0.008, 0.008, 0.8, MeshKit.at(Vector3(0.0, 0.4, 0.0)), Color(0.9, 0.9, 0.9), 4)
				"bell":
					b.box(Vector3(0.6, 0.06, 0.06), MeshKit.at(Vector3(0.0, 1.1, 0.0)), Color(0.55, 0.38, 0.22))
					for sx in [-0.28, 0.28]:
						b.cylinder(0.035, 0.035, 1.1, MeshKit.at(Vector3(sx, 0.55, 0.0)), Color(0.55, 0.38, 0.22), 6)
					b.cone(0.17, 0.3, MeshKit.at(Vector3(0.0, 0.88, 0.0)), Color(0.75, 0.62, 0.35), 10)
					b.sphere(0.05, MeshKit.at(Vector3(0.0, 0.72, 0.0)), Color(0.6, 0.5, 0.3), 6)
				_:
					b.sphere(0.2, MeshKit.at(Vector3(0.0, 0.3, 0.0)), Color(1.0, 0.85, 0.3), 8, true)
			var mi := MeshKit.instance(b.build(), false)
			mi.scale = Vector3.ONE * s
			root.add_child(mi)
	return root


## A quest thing found: lanterns and bells light up (a glowing light appears), the rest hop away (hidden).
func _quest_done_look(id: int, now: bool) -> void:
	var p: Dictionary = props[id]
	var n: Node3D = p["node"]
	if QUEST_LIGHTS.has(String(p["item"])):
		if now and not p.has("glow"):
			var b := MeshKit.Builder.new()
			var y := 1.22 if String(p["item"]) == "lantern" else 0.85
			b.sphere(0.16, MeshKit.at(Vector3(0.0, y, 0.0)), Color(1.0, 0.85, 0.35), 10, true)
			var g := MeshKit.instance(b.build(), false)
			n.add_child(g)
			p["glow"] = g
		if p.has("glow"):
			(p["glow"] as Node3D).visible = now
		return
	if now and n.visible and is_inside_tree():
		var tw := n.create_tween()
		tw.tween_property(n, "position", n.position + Vector3(0.0, 1.2, 0.0), 0.35).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.1, 0.4)
		tw.tween_callback(func() -> void: n.visible = false)
	else:
		n.visible = not now
		if not now:
			n.position = p["home"]
			n.scale = Vector3.ONE


## The emblem on a map stone: what the region looks like (realm.gd BIOMES order).
static func region_mesh(biome: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match biome:
		0:  # meadow: a sunflower
			b.cylinder(0.03, 0.03, 0.4, MeshKit.at(Vector3(0.0, -0.15, 0.0)), Color(0.3, 0.65, 0.25), 6)
			for k in 8:
				var a := TAU * k / 8.0
				b.sphere(0.08, MeshKit.at(Vector3(cos(a) * 0.15, 0.1 + sin(a) * 0.15, 0.0), Vector3(1.0, 1.0, 0.4)), Color(1.0, 0.85, 0.2), 6)
			b.sphere(0.09, MeshKit.at(Vector3(0.0, 0.1, 0.02), Vector3(1.0, 1.0, 0.5)), Color(0.5, 0.32, 0.15), 8)
		1:  # wood: a little tree
			b.cylinder(0.04, 0.05, 0.2, MeshKit.at(Vector3(0.0, -0.2, 0.0)), Color(0.5, 0.33, 0.2), 6)
			b.cone(0.22, 0.32, MeshKit.at(Vector3(0.0, -0.02, 0.0)), Color(0.3, 0.65, 0.3), 8)
			b.cone(0.16, 0.26, MeshKit.at(Vector3(0.0, 0.15, 0.0)), Color(0.35, 0.72, 0.35), 8)
		2:  # cave: crystals
			_crystal_bits(b, Vector3(0.0, -0.05, 0.0), Color(0.6, 0.85, 1.0), 0.6)
		3:  # snow: a snowy peak
			b.cone(0.26, 0.42, MeshKit.at(Vector3(0.0, -0.1, 0.0)), Color(0.55, 0.62, 0.78), 8)
			b.cone(0.12, 0.18, MeshKit.at(Vector3(0.0, 0.03, 0.0)), Color(1.0, 1.0, 1.0), 8)
		4:  # dunes: the sun
			b.sphere(0.15, MeshKit.at(Vector3.ZERO), Color(1.0, 0.8, 0.25), 10, true)
			for k in 8:
				var a2 := TAU * k / 8.0
				b.box(Vector3(0.04, 0.1, 0.04), MeshKit.at(Vector3(cos(a2) * 0.24, sin(a2) * 0.24, 0.0), Vector3.ONE, Vector3(0.0, 0.0, a2 - PI * 0.5)), Color(1.0, 0.9, 0.4), true)
		5:  # fen: a lily pad and a frog
			b.cylinder(0.22, 0.22, 0.03, MeshKit.at(Vector3(0.0, -0.15, 0.0)), Color(0.3, 0.65, 0.3), 12)
			b.sphere(0.11, MeshKit.at(Vector3(0.0, -0.05, 0.0), Vector3(1.0, 0.8, 1.0)), Color(0.45, 0.85, 0.35), 8)
			b.sphere(0.04, MeshKit.at(Vector3(-0.05, 0.04, 0.06)), Color(1.0, 1.0, 1.0), 6)
			b.sphere(0.04, MeshKit.at(Vector3(0.05, 0.04, 0.06)), Color(1.0, 1.0, 1.0), 6)
		6:  # cloud
			for c in [[-0.12, 0.0, 0.11], [0.0, 0.05, 0.14], [0.13, 0.0, 0.1]]:
				b.sphere(float(c[2]), MeshKit.at(Vector3(float(c[0]), float(c[1]), 0.0)), Color(1.0, 1.0, 1.0), 8)
		_:  # ember: a flame on a hill
			b.cone(0.24, 0.24, MeshKit.at(Vector3(0.0, -0.15, 0.0)), Color(0.5, 0.32, 0.28), 8)
			b.cone(0.1, 0.25, MeshKit.at(Vector3(0.0, 0.07, 0.0)), Color(1.0, 0.55, 0.15), 6, true)
			b.cone(0.05, 0.14, MeshKit.at(Vector3(0.0, 0.06, 0.03)), Color(1.0, 0.9, 0.4), 6, true)
	return b.build()
