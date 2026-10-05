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

const ZONES := 5
const ZL := 16.0  ## zone length along Z
const HALF_L := 8.0
const HALF_W := 5.0  ## the path's half width (walkable)

enum { WELL, CHICKEN, FLOWER, SIGN, CHEST, CRYSTAL, MUSHROOM, HOUSE, TREE, VILLAGER, DUMMY, TARGET, STONE, ORB, BIG, FRIEND }
## Kinds the sword passes through without poking (only spells hit the target).
const SPELL_ONLY: Array[int] = [TARGET]

## id -> {"kind", "zone", "home": Vector3, "node": Node3D, "r": touch radius, "c": centre offset,
##        "anim"/"lid"/"board"/"bubble": extra nodes}
var props: Array[Dictionary] = []
var barriers: Array[Node3D] = []
var open_count := 0
var used_bits := 0
var dummy_id := -1
var target_id := -1
var stone_id := -1
var orb_id := -1
var big_id := -1
var friend_id := -1
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

func build() -> void:
	_scenery()
	_trees()
	_barriers()
	_props()
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
	for k in ZONES:
		var c := center(k)
		var path := [Color(0.82, 0.7, 0.48), Color(0.6, 0.5, 0.34), Color(0.38, 0.36, 0.48), Color(0.62, 0.62, 0.5), Color(0.9, 0.9, 0.95)][k] as Color
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
			_crystal_bits(b, Vector3(sx * 5.75, 3.2 + (i % 2) * 0.7, z2 + 0.6), Color(0.5, 0.85, 1.0) if i % 2 == 0 else Color(0.85, 0.55, 1.0), 0.7)
	for i in 3:
		var za := c2.z + 5.0 - i * 5.0
		b.torus(6.6, 0.9, MeshKit.at(Vector3(0.0, 0.0, za), Vector3(1.0, 1.0, 1.0), Vector3(PI * 0.5, 0.0, 0.0)), Color(0.33, 0.3, 0.42), 20, 6)
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
	rng.seed = 7
	# Forest zone: thick on both sides; a few around the village and the glade.
	for i in 70:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := rng.randf_range(wall_z(0) - 0.5, wall_z(1) + 0.5)
		var x := side * rng.randf_range(6.8, 16.0)
		xfs.append(MeshKit.at(Vector3(x, 0.0, z), Vector3.ONE * rng.randf_range(1.6, 2.6), Vector3(0.0, rng.randf() * TAU, 0.0)))
		cols.append(Color(0.8, 1.0, 0.8).lerp(Color(1.0, 0.95, 0.75), rng.randf()))
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
					b.prism(6, 0.55, 2.4 + 0.6 * (j % 3), MeshKit.at(Vector3(-4.4 + j * 1.25, 1.3, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.08 * (j % 2 * 2 - 1))), Color(0.55, 0.85, 1.0) if j % 2 == 0 else Color(0.8, 0.6, 1.0), true)
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
	_sign(Vector3(2.4, 0.0, -6.2))
	_villager(Vector3(-2.6, 0.0, -5.0), 0, Color(0.9, 0.4, 0.3))
	_villager(Vector3(3.9, 0.0, 5.9), 1, Color(0.3, 0.6, 0.9))
	_chest(Vector3(-4.3, 0.0, -6.4))
	# --- Zone 1: the forest ---
	var c1 := center(1)
	for tp in [Vector3(-5.6, 0.0, -11.0), Vector3(5.6, 0.0, -15.5), Vector3(-5.6, 0.0, -20.5)]:
		_mesh_prop(TREE, tp, MeshKit.prop("tree"), 0.8, Vector3(signf(-tp.x) * 0.3, 1.4, 0.0))
	for mp in [Vector3(4.3, 0.0, -11.5), Vector3(-4.3, 0.0, -16.0), Vector3(4.2, 0.0, -21.5)]:
		_mesh_prop(MUSHROOM, mp, _mushroom_mesh(), 0.7, Vector3(0.0, 1.15, 0.0))
	for fp2 in [Vector3(-4.6, 0.0, -13.5), Vector3(4.6, 0.0, -18.5)]:
		_mesh_prop(FLOWER, fp2, _planter_mesh(int(-fp2.z)), 0.5, Vector3(0.0, 0.75, 0.0))
	_sign(c1 + Vector3(-2.6, 0.0, 6.2))
	_chest(c1 + Vector3(-4.3, 0.0, -6.0))
	# --- Zone 2: the crystal cave ---
	var c2 := center(2)
	var zs: Array[float] = [5.0, 1.5, -2.0, -5.5]
	for k in 4:
		var sx := -1.0 if k % 2 == 0 else 1.0
		var col := [Color(0.5, 0.85, 1.0), Color(0.85, 0.55, 1.0), Color(0.5, 1.0, 0.75), Color(1.0, 0.75, 0.45)][k] as Color
		var cb := MeshKit.Builder.new()
		_crystal_bits(cb, Vector3(0.0, 0.55, 0.0), col, 1.4)
		cb.rounded_box(Vector3(0.7, 0.5, 0.7), 0.1, MeshKit.at(Vector3(0.0, 0.25, 0.0)), Color(0.4, 0.37, 0.5))
		_mesh_prop(CRYSTAL, c2 + Vector3(sx * 4.6, 0.0, zs[k]), cb.build(), 0.6, Vector3(0.0, 1.0, 0.0))
	orb_id = _mesh_prop(ORB, c2 + Vector3(0.0, 0.0, -1.0), _orb_mesh(), 0.5, Vector3(0.0, 1.35, 0.0))
	blockers.append([Vector2(0.0, c2.z - 1.0), 0.45])
	_chest(c2 + Vector3(4.3, 0.0, -6.2))
	# --- Zone 3: the Stone Giant's glade ---
	var c3 := center(3)
	for fp3 in [Vector3(-4.5, 0.0, 4.5), Vector3(4.5, 0.0, 3.5)]:
		_mesh_prop(FLOWER, c3 + fp3, _planter_mesh(5 + int(fp3.x)), 0.5, Vector3(0.0, 0.75, 0.0))
	var giant := Creatures.monster("golem", {"color": Color(0.65, 0.68, 0.6), "color2": Color(0.5, 0.85, 0.5)})
	var gh := Node3D.new()
	gh.add_child(giant)
	giant.scale = Vector3.ONE * 2.2
	giant.rotation.y = -0.6
	friend_id = _add(FRIEND, c3 + Vector3(3.6, 0.0, -5.2), gh, 1.2, Vector3(-0.6, 1.4, 0.4))
	props[friend_id]["anim"] = Creatures.anim(giant)
	gh.visible = false
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


func is_used(id: int) -> bool:
	return id >= 0 and (used_bits >> id) & 1 == 1


func set_used(bits: int) -> void:
	var was := used_bits
	used_bits = bits
	for id in props.size():
		var now := is_used(id)
		if now == (((was >> id) & 1) == 1):
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
