extends RefCounted
## CRYSTAL SAGA maps: builds each area's static scenery (one merged ground heightfield, merged
## buildings, MultiMesh trees / rocks / crystals) and describes everything that lives in it as plain
## data (walkable shapes, spawn points, exits, NPCs, chests, signs, save crystals, puzzle pieces and
## the visible monsters). world.gd turns the data into live objects. Only the area you are in exists:
## entering another area frees this one (streaming), so the Frame only ever draws one map.
## Coordinates: every area runs from its south entrance (+Z) to its north exit (-Z); y = 0 is the
## walking floor everywhere. Creatures face +Z, so a yaw of 0 looks south and PI looks north.

const Nav := preload("res://games/crystal_saga/nav.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const ResCache := preload("res://core/res_cache.gd")
const SkyKit := preload("res://core/sky_kit.gd")

const STONE := Color(0.62, 0.6, 0.58)
const DARK_STONE := Color(0.36, 0.35, 0.4)
const WOOD := Color(0.55, 0.36, 0.22)
const GRASS := Color(0.42, 0.7, 0.32)
const GRASS2 := Color(0.5, 0.78, 0.36)
const DIRT := Color(0.72, 0.58, 0.4)


## Build area `id`. Returns {id, root, nav, spawns, exits, things, encounters, wind, lights}.
static func build(id: String, vr: bool) -> Dictionary:
	match id:
		"forest":
			return _forest(vr)
		"caverns":
			return _caverns(vr)
		"skybridge":
			return _skybridge(vr)
		"castle":
			return _castle(vr)
	return _village(vr)


static func _new_def(id: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Area_" + id
	return {"id": id, "root": root, "nav": Nav.new(), "spawns": {}, "exits": [], "things": [], "encounters": [],
		"wind": [], "lights": 0}


static func _npc(def: Dictionary, id: String, npc_name: String, pos: Vector3, yaw: float, look: Dictionary, color: Variant = "accent",
		extra: Dictionary = {}) -> void:
	var t := {"id": id, "kind": "npc", "name": npc_name, "pos": pos, "yaw": yaw, "look": look, "color": color}
	t.merge(extra, true)
	(def["things"] as Array).append(t)


static func _thing(def: Dictionary, t: Dictionary) -> void:
	(def["things"] as Array).append(t)


static func _enc(def: Dictionary, pos: Vector3, formation: int, roam: float = 2.5) -> void:
	var list: Array = def["encounters"]
	list.append({"i": list.size(), "pos": pos, "f": formation, "roam": roam})


# =================================================================================================
# WILLOWBROOK

static func _village(vr: bool) -> Dictionary:
	var d := _new_def("village")
	var nav: Nav = d["nav"]
	nav.circle(Vector3.ZERO, 20.0)
	nav.circle(Vector3(0, 0, -15), 6.0)
	nav.capsule(Vector3(0, 0, -17), Vector3(0, 0, -27.5), 3.0)
	nav.capsule(Vector3(0, 0, 17), Vector3(0, 0, 24), 3.0)
	nav.circle(Vector3(-16, 0, -2), 6.0)
	# Blockers: fountain, houses, counters, pedestal, trees.
	nav.block(Vector3.ZERO, 2.2)
	var houses := [
		[Vector3(-11, 0, 4), PI * 0.5, Vector3(6.0, 3.0, 5.0), Color(0.95, 0.88, 0.72), Color(0.75, 0.3, 0.25)],  # inn (door east)
		[Vector3(11, 0, 4), -PI * 0.5, Vector3(6.0, 3.0, 5.0), Color(0.88, 0.92, 0.98), Color(0.28, 0.45, 0.78)],  # shop (door west)
		[Vector3(-9.5, 0, -9.5), PI * 0.5, Vector3(5.0, 2.8, 4.6), Color(0.92, 0.85, 0.7), Color(0.45, 0.6, 0.32)],  # elder
		[Vector3(9.5, 0, -9.5), -PI * 0.5, Vector3(5.0, 2.6, 4.4), Color(1.0, 0.9, 0.82), Color(0.82, 0.5, 0.3)],  # Lina
		[Vector3(-11.5, 0, 13.5), PI * 0.5, Vector3(4.6, 2.6, 4.2), Color(0.9, 0.8, 0.68), Color(0.6, 0.35, 0.6)],
		[Vector3(11.5, 0, 13.5), -PI * 0.5, Vector3(4.6, 2.6, 4.2), Color(0.85, 0.9, 0.82), Color(0.8, 0.62, 0.25)],
	]
	for h in houses:
		var hp: Vector3 = h[0]
		var hs: Vector3 = h[2]
		nav.block_box(hp, Vector2(hs.z, hs.x) + Vector2(0.4, 0.4))  # rotated 90 degrees: x and z swap
	nav.block_box(Vector3(-7.0, 0, 4), Vector2(0.9, 3.0))  # inn counter
	nav.block_box(Vector3(7.0, 0, 4), Vector2(0.9, 3.0))  # shop counter
	nav.block(Vector3(0, 0, -16.2), 1.3)  # crystal pedestal
	var town_trees: Array[Vector3] = [Vector3(-5, 0, 14), Vector3(5.5, 0, 15), Vector3(-15, 0, 7), Vector3(15, 0, -2),
		Vector3(-5.5, 0, -18), Vector3(5.5, 0, -18.5)]
	for tp in town_trees:
		nav.block(tp, 0.7)
	var root: Node3D = d["root"]
	_add_ground(d, {"seed": 3, "margin": 16.0, "wall_h": 3.0, "wall_w": 12.0, "floor_a": GRASS, "floor_b": GRASS2,
		"wall_a": Color(0.36, 0.62, 0.3), "wall_b": Color(0.46, 0.66, 0.3), "paths": [
			[Vector3(0, 0, 24), Vector3(0, 0, -27), 1.6], [Vector3(-8, 0, 4), Vector3(8, 0, 4), 1.3], [Vector3(0, 0, 0), Vector3(0, 0, 0), 4.0],
			[Vector3(-7, 0, -8), Vector3(7, 0, -8), 1.1], [Vector3(0, 0, -15), Vector3(0, 0, -15), 4.2]],
		"path_c": Color(0.83, 0.74, 0.56)})
	# Buildings, fountain, shrine, gate, counters: one merged mesh (+1 glow surface).
	var b := MeshKit.Builder.new()
	for h in houses:
		_house(b, h[0], h[1], h[2], h[3], h[4])
	_fountain(b, Vector3.ZERO)
	_shrine(b, Vector3(0, 0, -16))
	_gate(b, Vector3(0, 0, -25.5), 0.0)
	_gate(b, Vector3(0, 0, 22.5), 0.0)
	b.box(Vector3(2.8, 0.25, 4.0), MeshKit.at(Vector3(0, 1.4, 23.6)), WOOD)  # closed south gate
	for side in [-1.0, 1.0]:
		var cx: float = 7.0 * side
		b.rounded_box(Vector3(0.8, 1.0, 3.0), 0.08, MeshKit.at(Vector3(cx, 0.5, 4)), WOOD)
		b.box(Vector3(1.0, 0.08, 3.2), MeshKit.at(Vector3(cx, 1.04, 4)), WOOD.lightened(0.15))
		# awnings
		b.wedge(Vector3(1.6, 0.5, 3.6), MeshKit.at(Vector3(cx + 0.9 * side, 2.7, 4), Vector3.ONE, Vector3(0, -PI * 0.5 * side, 0)),
			Color(0.95, 0.4, 0.35) if side > 0 else Color(0.35, 0.55, 0.95))
	# Shop goods on the counter: potions (glowing) and an inn bed sign.
	for k in 3:
		b.capsule(0.08, 0.26, MeshKit.at(Vector3(7.0, 1.2, 3.0 + k * 0.9)), Color(0.3, 0.9, 0.5), 8, true)
	b.box(Vector3(0.1, 0.6, 1.2), MeshKit.at(Vector3(-12.6 + 4.4, 2.2, 4)), Color(0.98, 0.95, 0.85))
	# farm fence + hay
	for k in 6:
		b.box(Vector3(0.12, 0.9, 0.12), MeshKit.at(Vector3(-21.0 + k * 1.8, 0.45, 3.5)), WOOD)
	b.box(Vector3(9.2, 0.1, 0.08), MeshKit.at(Vector3(-16.5, 0.75, 3.5)), WOOD)
	b.box(Vector3(9.2, 0.1, 0.08), MeshKit.at(Vector3(-16.5, 0.4, 3.5)), WOOD)
	b.cylinder(0.7, 0.7, 1.0, MeshKit.at(Vector3(-19, 0.5, -6), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.82, 0.4), 12)
	root.add_child(MeshKit.instance(b.build()))
	# Trees in town (blocked above) and the countryside around it, bushes, flowers.
	root.add_child(MeshKit.scatter(MeshKit.prop("tree", 0), _xforms(town_trees, 1.1, 5)))
	root.add_child(_scatter_outside(nav, MeshKit.prop("tree", 1), 70, 1.5, 14.0, 11, 0.9, 1.5, d))
	root.add_child(_scatter_outside(nav, MeshKit.prop("pine"), 40, 4.0, 16.0, 12, 0.9, 1.4, d))
	root.add_child(_scatter_outside(nav, MeshKit.prop("bush"), 40, 0.3, 4.0, 13, 0.8, 1.3, d))
	root.add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 70, Vector3(0, 0, 0), 19.0, 3.0, 0.8, 1.2,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0), Color(1, 1, 1)]), 14))
	var lamps: Array[Vector3] = [Vector3(-2.5, 0, 10), Vector3(2.5, 0, 10), Vector3(-2.6, 0, -20), Vector3(2.6, 0, -20)]
	root.add_child(MeshKit.scatter(MeshKit.prop("lamp_post"), _xforms(lamps, 1.0, 0)))
	d["spawns"] = {"start": [Vector3(0, 0, 9), 0.0], "from_forest": [Vector3(0, 0, -23.5), PI], "shrine": [Vector3(0, 0, -10.5), 0.0],
		"inn": [Vector3(-5.2, 0, 6.5), 0.0]}
	d["exits"] = [{"id": "north", "pos": Vector3(0, 0, -27.0), "r": 2.6, "to": "forest", "spawn": "from_village", "need": "quest",
		"block": "Captain Rook: Talk to Elder Oak by the shrine first!"}]
	# People of Willowbrook.
	_npc(d, "elder", "ELDER OAK", Vector3(-2.4, 0, -12.6), 0.25, {"class": "villager", "beard": "long", "hair_style": "bald",
		"hair": Color(0.92, 0.92, 0.95), "outfit": Color(0.35, 0.55, 0.35), "outfit2": Color(0.9, 0.8, 0.4), "weapon": "staff", "seed": 101},
		"good")
	_npc(d, "pip", "PIP THE SHOPKEEPER", Vector3(7.9, 0, 4.0), -PI * 0.5, {"class": "chef", "hat": "beret", "weapon": "none",
		"outfit": Color(0.98, 0.95, 0.9), "outfit2": Color(0.35, 0.55, 0.95), "seed": 102}, "info")
	_npc(d, "rosa", "ROSA THE INNKEEPER", Vector3(-7.9, 0, 4.0), PI * 0.5, {"class": "villager", "hair_style": "bun",
		"hair": Color(0.58, 0.37, 0.2), "outfit": Color(0.95, 0.55, 0.55), "seed": 103}, "bad")
	_npc(d, "lina", "LINA", Vector3(6.6, 0, -7.6), -PI * 0.6, {"class": "villager", "hair_style": "long", "hair": Color(0.88, 0.42, 0.2),
		"outfit": Color(0.6, 0.45, 0.85), "seed": 104}, "magic")
	_npc(d, "rook", "CAPTAIN ROOK", Vector3(3.0, 0, -24.0), -PI * 0.5, {"class": "knight", "hat": "helmet", "seed": 105}, "info")
	_npc(d, "hal", "FARMER HAL", Vector3(-15.0, 0, -1.0), PI * 0.5, {"class": "farmer", "seed": 106}, "good")
	_npc(d, "pell", "PELL", Vector3(-3.2, 0, 5.0), 0.6, {"class": "villager", "scale": 0.75, "hair_style": "spiky", "seed": 107}, "accent",
		{"wander": 2.0})
	_npc(d, "dot", "DOT", Vector3(3.4, 0, -3.4), -2.4, {"class": "princess", "scale": 0.72, "weapon": "none", "seed": 108}, "accent",
		{"wander": 2.0})
	_npc(d, "tobi", "TOBI", Vector3(8.4, 0, -6.0), -PI * 0.6, {"class": "villager", "scale": 0.72, "hair_style": "curly",
		"hair": Color(0.88, 0.42, 0.2), "hat": "cap", "seed": 109}, "accent", {"if": "tobi_saved"})
	_thing(d, {"id": "v_cat", "kind": "pet", "model": "cat", "pos": Vector3(2.6, 0, 2.2), "yaw": 2.0, "color": Color(1.0, 0.7, 0.35)})
	_thing(d, {"id": "v_sheep1", "kind": "pet", "model": "sheep", "pos": Vector3(-17.5, 0, -3.5), "yaw": 1.0, "wander": 2.0})
	_thing(d, {"id": "v_sheep2", "kind": "pet", "model": "sheep", "pos": Vector3(-14.0, 0, -5.0), "yaw": -0.5, "wander": 2.0})
	_thing(d, {"id": "v_save", "kind": "save", "pos": Vector3(-4.6, 0, 8.0)})
	_thing(d, {"id": "v_sign1", "kind": "sign", "pos": Vector3(2.7, 0, 15.5), "yaw": 0.0, "title": "WILLOWBROOK",
		"text": "Welcome to Willowbrook! Home of the Crystal of Light. Please don't feed the slimes."})
	_thing(d, {"id": "v_sign2", "kind": "sign", "pos": Vector3(-2.8, 0, -21.0), "yaw": 0.0, "title": "NORTH GATE",
		"text": "North: the Whispering Forest. Stay on the path, little ones!"})
	_thing(d, {"id": "v_chest1", "kind": "chest", "pos": Vector3(-13.0, 0, -5.6), "yaw": PI * 0.5, "loot": [["potion", 2]]})
	_thing(d, {"id": "v_chest2", "kind": "chest", "pos": Vector3(-19.5, 0, -1.0), "yaw": PI * 0.5, "loot": [["gil", 60]]})
	_thing(d, {"id": "v_pedestal", "kind": "pedestal", "pos": Vector3(0, 0, -16.2)})
	return d


# =================================================================================================
# WHISPERING FOREST

static func _forest(vr: bool) -> Dictionary:
	var d := _new_def("forest")
	var nav: Nav = d["nav"]
	var trail: Array = [Vector3(0, 0, 34), Vector3(-5, 0, 18), Vector3(4, 0, 4), Vector3(-3, 0, -10), Vector3(5, 0, -24), Vector3(0, 0, -40)]
	nav.path(trail, 4.2)
	nav.capsule(Vector3(-3, 0, 3), Vector3(-11, 0, 1), 2.8)
	nav.circle(Vector3(-16, 0, 0), 6.5)
	nav.capsule(Vector3(4, 0, -18), Vector3(11, 0, -16), 2.4)
	nav.circle(Vector3(14, 0, -16), 3.6)
	nav.block(Vector3(-19.5, 0, -2.5), 1.6)  # the big old tree
	var inner_trees: Array[Vector3] = [Vector3(-2, 0, 25), Vector3(1.5, 0, 12), Vector3(-1, 0, -2), Vector3(3, 0, -15), Vector3(-13, 0, 4.5)]
	for tp in inner_trees:
		nav.block(tp, 0.6)
	var root: Node3D = d["root"]
	_add_ground(d, {"seed": 5, "margin": 14.0, "wall_h": 2.6, "wall_w": 8.0, "floor_a": Color(0.36, 0.6, 0.3),
		"floor_b": Color(0.44, 0.66, 0.32), "wall_a": Color(0.25, 0.45, 0.24), "wall_b": Color(0.32, 0.5, 0.26),
		"paths": _trail_caps(trail, 1.5), "path_c": Color(0.66, 0.54, 0.38)})
	var b := MeshKit.Builder.new()
	# The big old tree in Tobi's clearing.
	b.cylinder(0.9, 1.4, 4.5, MeshKit.at(Vector3(-19.5, 2.25, -2.5)), WOOD.darkened(0.1), 12)
	for k in 6:
		var a := k * TAU / 6.0
		b.sphere(2.4, MeshKit.at(Vector3(-19.5 + cos(a) * 2.2, 5.6 + sin(a * 2.0) * 0.4, -2.5 + sin(a) * 2.2)), Color(0.3, 0.6, 0.3).lerp(Color(0.45, 0.72, 0.35), float(k % 2)), 12)
	b.sphere(2.8, MeshKit.at(Vector3(-19.5, 7.0, -2.5)), Color(0.36, 0.66, 0.32), 12)
	# Cave mouth at the north end: a rocky arch with darkness inside.
	_rock_arch(b, Vector3(0, 0, -42.5), Color(0.5, 0.48, 0.5))
	# Little mushroom ring around the clearing and a log bench.
	b.cylinder(0.35, 0.35, 2.6, MeshKit.at(Vector3(-13.5, 0.35, -3.5), Vector3.ONE, Vector3(0, 0.4, PI * 0.5)), WOOD, 10)
	root.add_child(MeshKit.instance(b.build()))
	root.add_child(MeshKit.scatter(MeshKit.prop("tree", 2), _xforms(inner_trees, 1.15, 21)))
	root.add_child(_scatter_outside(nav, MeshKit.prop("tree", 1), 110, 0.8, 12.0, 22, 0.9, 1.6, d))
	root.add_child(_scatter_outside(nav, MeshKit.prop("pine"), 90, 1.5, 14.0, 23, 1.0, 1.7, d))
	root.add_child(_scatter_outside(nav, MeshKit.prop("bush"), 60, 0.1, 3.0, 24, 0.8, 1.4, d))
	root.add_child(_scatter_inside(nav, MeshKit.prop("mushroom"), 40, 25, 0.6, 1.2, d, PackedColorArray([Color(1, 0.45, 0.4), Color(0.95, 0.85, 0.5), Color(0.7, 0.55, 1.0)])))
	root.add_child(_scatter_inside(nav, MeshKit.prop("flower"), 70, 26, 0.7, 1.1, d, PackedColorArray([Color(1.0, 0.6, 0.8), Color(1.0, 1.0, 0.6), Color(0.6, 0.8, 1.0)])))
	root.add_child(_scatter_inside(nav, MeshKit.prop("grass"), 90, 27, 0.8, 1.4, d, PackedColorArray()))
	d["spawns"] = {"from_village": [Vector3(0, 0, 30), 0.0], "from_caverns": [Vector3(0, 0, -35.5), PI], "save": [Vector3(5.5, 0, 6.5), 0.0]}
	d["exits"] = [{"id": "south", "pos": Vector3(0, 0, 34.5), "r": 3.0, "to": "village", "spawn": "from_forest"},
		{"id": "north", "pos": Vector3(0, 0, -40.5), "r": 3.0, "to": "caverns", "spawn": "from_forest"}]
	_thing(d, {"id": "f_save", "kind": "save", "pos": Vector3(7.6, 0, 5.0)})
	_thing(d, {"id": "f_sign", "kind": "sign", "pos": Vector3(3.4, 0, 27.0), "yaw": -0.3, "title": "WHISPERING FOREST",
		"text": "Little footprints lead to the WEST... someone went exploring! The caves are to the north."})
	_thing(d, {"id": "f_chest1", "kind": "chest", "pos": Vector3(15.2, 0, -16.6), "yaw": -PI * 0.5, "loot": [["hi_potion", 1], ["gil", 40]]})
	_thing(d, {"id": "f_chest2", "kind": "chest", "pos": Vector3(-18.6, 0, 2.6), "yaw": PI * 0.75, "loot": [["phoenix", 1]]})
	_thing(d, {"id": "f_chest3", "kind": "chest", "pos": Vector3(-6.6, 0, 17.0), "yaw": PI * 0.5, "loot": [["leather", 1]]})
	_npc(d, "tobi_lost", "TOBI", Vector3(-16.5, 0, -1.0), 0.6, {"class": "villager", "scale": 0.72, "hair_style": "curly",
		"hair": Color(0.88, 0.42, 0.2), "hat": "cap", "seed": 109}, "accent", {"if": "!tobi_saved", "trigger": 6.0})
	_enc(d, Vector3(-3.5, 0, 21), 0)
	_enc(d, Vector3(3.0, 0, 9), 1)
	_enc(d, Vector3(-2.0, 0, -6), 2)
	_enc(d, Vector3(2.0, 0, -17), 3)
	_enc(d, Vector3(13.5, 0, -14.5), 4, 1.5)
	_enc(d, Vector3(2.5, 0, -31), 6)
	return d


# =================================================================================================
# CRYSTAL CAVERNS

static func _caverns(vr: bool) -> Dictionary:
	var d := _new_def("caverns")
	var nav: Nav = d["nav"]
	nav.capsule(Vector3(0, 0, 28), Vector3(0, 0, 8), 2.7)
	nav.circle(Vector3(0, 0, 0), 9.0)
	nav.capsule(Vector3(8, 0, 1), Vector3(14, 0, 2), 2.2)
	nav.circle(Vector3(15.5, 0, 2.5), 3.2)
	nav.capsule(Vector3(0, 0, -8), Vector3(0, 0, -20), 2.5)
	nav.circle(Vector3(0, 0, -28), 9.0)
	nav.capsule(Vector3(0, 0, -36), Vector3(0, 0, -48), 2.5)
	nav.set_gate("seal", true, Vector3(0, 0, -9.6), Vector2(5.4, 1.0))
	nav.set_gate("barrier", true, Vector3(0, 0, -37.5), Vector2(5.4, 1.0))
	var spires: Array[Vector3] = [Vector3(-6.5, 0, 4.5), Vector3(5.5, 0, 6.0), Vector3(-6.5, 0, -24), Vector3(6.5, 0, -32)]
	for sp in spires:
		nav.block(sp, 0.8)
	var root: Node3D = d["root"]
	_add_ground(d, {"seed": 7, "margin": 9.0, "wall_h": 8.0, "wall_w": 3.0, "bump": 0.8, "floor_a": Color(0.3, 0.3, 0.4),
		"floor_b": Color(0.36, 0.36, 0.46), "wall_a": Color(0.34, 0.32, 0.42), "wall_b": Color(0.24, 0.23, 0.32),
		"paths": [], "path_c": Color(0.4, 0.4, 0.5)})
	var b := MeshKit.Builder.new()
	for sp in spires:
		b.cone(0.9, 3.2, MeshKit.at(sp + Vector3(0, 1.6, 0)), Color(0.38, 0.36, 0.46), 9)
		b.cone(0.45, 1.6, MeshKit.at(sp + Vector3(0.6, 0.8, 0.3)), Color(0.42, 0.4, 0.5), 8)
	# The mural beside the sealed door: four coloured gems show the lighting order.
	b.rounded_box(Vector3(2.4, 2.2, 0.3), 0.1, MeshKit.at(Vector3(-4.0, 1.4, -8.8)), Color(0.5, 0.48, 0.56))
	var order_cols: Array[Color] = [Color(1.0, 0.35, 0.3), Color(0.3, 0.6, 1.0), Color(0.35, 0.95, 0.45), Color(1.0, 0.85, 0.3)]
	for k in 4:
		b.sphere(0.17, MeshKit.at(Vector3(-4.75 + k * 0.5, 1.6, -8.6)), order_cols[k], 10, true)
	b.box(Vector3(1.8, 0.06, 0.05), MeshKit.at(Vector3(-4.0, 1.25, -8.62)), Color(0.85, 0.8, 0.6), true)
	# Crystal formations on the walls (glow).
	_crystal_cluster(b, Vector3(-8.4, 0, -2.5), Color(0.45, 0.8, 1.0), 1.4)
	_crystal_cluster(b, Vector3(8.6, 0, -3.0), Color(0.75, 0.5, 1.0), 1.3)
	_crystal_cluster(b, Vector3(-8.2, 0, -30), Color(0.5, 0.95, 0.95), 1.8)
	_crystal_cluster(b, Vector3(8.4, 0, -25), Color(0.85, 0.55, 1.0), 1.6)
	_crystal_cluster(b, Vector3(2.8, 0, 22), Color(0.45, 0.8, 1.0), 0.9)
	_crystal_cluster(b, Vector3(-2.8, 0, 14), Color(0.75, 0.5, 1.0), 0.9)
	_rock_arch(b, Vector3(0, 0, 29.5), Color(0.42, 0.4, 0.48))
	_rock_arch(b, Vector3(0, 0, -49.5), Color(0.42, 0.4, 0.48))
	root.add_child(MeshKit.instance(b.build()))
	root.add_child(_scatter_outside(nav, _crystal_mesh(Color(0.5, 0.85, 1.0)), 50, 0.3, 2.6, 31, 0.6, 1.4, d))
	root.add_child(_scatter_outside(nav, _crystal_mesh(Color(0.8, 0.55, 1.0)), 40, 0.3, 2.6, 32, 0.5, 1.2, d))
	root.add_child(_scatter_outside(nav, MeshKit.prop("rock"), 60, 0.0, 3.0, 33, 0.7, 1.5, d))
	root.add_child(_scatter_inside(nav, MeshKit.prop("rock", 1), 25, 34, 0.3, 0.6, d, PackedColorArray()))
	# Two lights only: the puzzle chamber and the Wyrm's lair.
	var l1 := SkyKit.flicker_light(Color(0.55, 0.75, 1.0), 2.2, 16.0)
	l1.position = Vector3(0, 5.0, 0)
	root.add_child(l1)
	var l2 := SkyKit.flicker_light(Color(0.7, 0.6, 1.0), 2.2, 16.0)
	l2.position = Vector3(0, 6.0, -28)
	root.add_child(l2)
	d["lights"] = 2
	d["spawns"] = {"from_forest": [Vector3(0, 0, 24), 0.0], "from_skybridge": [Vector3(0, 0, -44), PI], "save": [Vector3(-2.0, 0, 7.5), 0.0],
		"lair": [Vector3(0, 0, -19), 0.0]}
	d["exits"] = [{"id": "south", "pos": Vector3(0, 0, 28.5), "r": 2.6, "to": "forest", "spawn": "from_caverns"},
		{"id": "north", "pos": Vector3(0, 0, -48.0), "r": 2.6, "to": "skybridge", "spawn": "from_caverns"}]
	_thing(d, {"id": "c_save", "kind": "save", "pos": Vector3(-3.8, 0, 6.2)})
	_thing(d, {"id": "c_mural", "kind": "sign", "pos": Vector3(-4.0, 0, -8.2), "yaw": 0.0, "title": "OLD MURAL", "no_post": true,
		"text": "Light the crystals as the sky wakes: first the RED sun, then the BLUE sea, then the GREEN leaf, and last the GOLD star."})
	var pc: Array[Vector3] = [Vector3(5.8, 0, -3.5), Vector3(-6.2, 0, -2.0), Vector3(2.8, 0, 3.6), Vector3(-2.6, 0, -5.8)]
	var pcol: Array[int] = [0, 1, 2, 3]
	for k in 4:
		_thing(d, {"id": "c_pc%d" % k, "kind": "pcrystal", "pos": pc[k], "order": pcol[k], "color": order_cols[pcol[k]]})
	_thing(d, {"id": "c_door", "kind": "door", "pos": Vector3(0, 0, -9.6), "gate": "seal", "flag": "seal_open"})
	_thing(d, {"id": "c_barrier", "kind": "barrier", "pos": Vector3(0, 0, -37.5), "gate": "barrier", "flag": "wyrm_done"})
	_thing(d, {"id": "c_chest1", "kind": "chest", "pos": Vector3(16.6, 0, 3.4), "yaw": -PI * 0.5, "loot": [["mythril_sword", 1], ["ether", 1]]})
	_thing(d, {"id": "c_chest2", "kind": "chest", "pos": Vector3(-6.0, 0, -33.0), "yaw": PI * 0.3, "loot": [["star_rod", 1], ["gil", 120]]})
	_thing(d, {"id": "c_chest3", "kind": "chest", "pos": Vector3(1.6, 0, 18.0), "yaw": -PI * 0.5, "loot": [["chain", 1]]})
	_thing(d, {"id": "c_lair", "kind": "trigger", "pos": Vector3(0, 0, -26.0), "r": 7.5, "story": "wyrm", "if": "!wyrm_done"})
	_thing(d, {"id": "c_shard", "kind": "shard", "pos": Vector3(0, 0, -31.0), "summon": "titan", "if": "wyrm_done", "color": Color(0.85, 0.6, 0.3)})
	_enc(d, Vector3(0.5, 0, 17), 0, 1.5)
	_enc(d, Vector3(-4.5, 0, 2.0), 1, 1.5)
	_enc(d, Vector3(12.0, 0, 1.5), 2, 1.0)
	_enc(d, Vector3(0, 0, -15), 3, 1.0)
	_enc(d, Vector3(0, 0, -43), 4, 1.0)
	return d


# =================================================================================================
# SKY BRIDGE

static func _skybridge(vr: bool) -> Dictionary:
	var d := _new_def("skybridge")
	var nav: Nav = d["nav"]
	nav.circle(Vector3(0, 0, 30), 7.0)
	nav.capsule(Vector3(0, 0, 24), Vector3(0, 0, -31), 1.75)
	nav.circle(Vector3(0, 0, 9), 4.6)
	nav.circle(Vector3(0, 0, -12), 4.6)
	nav.circle(Vector3(0, 0, -38), 8.5)
	nav.capsule(Vector3(0, 0, -45), Vector3(0, 0, -54), 2.0)
	nav.set_gate("roc_exit", true, Vector3(0, 0, -46.5), Vector2(5.0, 1.0))
	nav.block(Vector3(0, 0, -43.0), 1.6)  # Phoenix nest
	var root: Node3D = d["root"]
	var b := MeshKit.Builder.new()
	_island(b, Vector3(0, 0, 30), 7.6, 9.0)
	_island(b, Vector3(0, 0, 9), 5.2, 6.0)
	_island(b, Vector3(0, 0, -12), 5.2, 6.0)
	_island(b, Vector3(0, 0, -38), 9.2, 10.0)
	_island(b, Vector3(0, 0, -52), 3.2, 4.0)
	# Bridge planks with posts and rope rails between the islands.
	var spans: Array = [[23.4, 13.8], [4.4, -7.4], [-16.6, -29.6], [-46.0, -49.0]]
	for sp in spans:
		var z0: float = sp[0]
		var z1: float = sp[1]
		var n := int(absf(z0 - z1) / 0.55)
		for k in n + 1:
			var z := lerpf(z0, z1, float(k) / maxf(1.0, n))
			b.box(Vector3(3.6, 0.12, 0.48), MeshKit.at(Vector3(0, -0.06, z), Vector3.ONE, Vector3(0, (k % 3 - 1) * 0.02, 0)),
				WOOD.lerp(Color(0.7, 0.5, 0.32), float(k % 2) * 0.4))
		var posts := int(absf(z0 - z1) / 2.4)
		for k in posts + 1:
			var z2 := lerpf(z0, z1, float(k) / maxf(1.0, posts))
			for side in [-1.0, 1.0]:
				b.cylinder(0.06, 0.07, 1.1, MeshKit.at(Vector3(1.85 * side, 0.5, z2)), WOOD.darkened(0.2), 6)
		for side in [-1.0, 1.0]:
			b.tube(Vector3(1.85 * side, 0.95, z0), Vector3(1.85 * side, 0.85, z1), 0.035, 0.035, Color(0.85, 0.75, 0.55), 6)
	# The Phoenix nest on the far island and a little stair up to the castle.
	b.torus(1.3, 0.45, MeshKit.at(Vector3(0, 0.4, -43.0)), Color(0.6, 0.42, 0.25), 16, 6)
	for k in 6:
		b.box(Vector3(3.0, 0.3, 0.9), MeshKit.at(Vector3(0, 0.15 + k * 0.0, -47.2 - k * 1.0)), STONE)
	# Floating rocks far away.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for k in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(25.0, 60.0)
		var p := Vector3(cos(a) * r, rng.randf_range(-12.0, 10.0), sin(a) * r - 6.0)
		var s := rng.randf_range(1.0, 3.2)
		b.cone(s, s * 1.8, MeshKit.at(p + Vector3(0, -s * 0.6, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.55, 0.45, 0.5), 7)
		b.cylinder(s, s, 0.4, MeshKit.at(p + Vector3(0, 0.1, 0)), Color(0.5, 0.75, 0.42), 7)
	root.add_child(MeshKit.instance(b.build()))
	# Clouds below and around: one draw call.
	var cl: Array = []
	for k in 40:
		var a2 := rng.randf() * TAU
		var r2 := rng.randf_range(8.0, 70.0)
		cl.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(2.5, 6.0)),
			Vector3(cos(a2) * r2, rng.randf_range(-22.0, -9.0), sin(a2) * r2 - 8.0)))
	root.add_child(MeshKit.scatter(MeshKit.prop("cloud"), cl, PackedColorArray([Color(1.0, 0.86, 0.82), Color(1.0, 0.95, 0.9)]), PackedColorArray(), false))
	root.add_child(_scatter_inside(nav, MeshKit.prop("flower"), 50, 42, 0.7, 1.1, d, PackedColorArray([Color(1.0, 0.7, 0.4), Color(1.0, 1.0, 0.7)])))
	root.add_child(_scatter_inside(nav, MeshKit.prop("grass"), 60, 43, 0.8, 1.3, d, PackedColorArray()))
	d["wind"] = [Vector2(13.6, 23.6), Vector2(-7.6, 4.6), Vector2(-29.8, -16.4)]
	d["spawns"] = {"from_caverns": [Vector3(0, 0, 32), 0.0], "from_castle": [Vector3(0, 0, -50), PI], "save": [Vector3(2.0, 0, 26.5), 0.0]}
	d["exits"] = [{"id": "south", "pos": Vector3(0, 0, 36.5), "r": 2.4, "to": "caverns", "spawn": "from_skybridge"},
		{"id": "north", "pos": Vector3(0, 0, -53.5), "r": 2.2, "to": "castle", "spawn": "from_skybridge"}]
	_npc(d, "hopper", "HOPPER", Vector3(-3.8, 0, 28.6), PI * 0.4, {}, "gold", {"model": "bunny", "mcolor": Color(1.0, 0.95, 0.95)})
	_thing(d, {"id": "s_save", "kind": "save", "pos": Vector3(3.8, 0, 27.2)})
	_thing(d, {"id": "s_sign", "kind": "sign", "pos": Vector3(2.4, 0, 24.6), "yaw": 0.0, "title": "SKY BRIDGE",
		"text": "Strong winds! When the wind howls, hold on and wait. Cross when it is calm."})
	_thing(d, {"id": "s_chest1", "kind": "chest", "pos": Vector3(-3.0, 0, 8.4), "yaw": PI * 0.5, "loot": [["ether", 2]]})
	_thing(d, {"id": "s_chest2", "kind": "chest", "pos": Vector3(3.0, 0, -12.6), "yaw": -PI * 0.5, "loot": [["elven_bow", 1], ["mythril_dagger", 1]]})
	_thing(d, {"id": "s_chest3", "kind": "chest", "pos": Vector3(-5.5, 0, -37.0), "yaw": PI * 0.5, "loot": [["mythril_mail", 1], ["golden_harp", 1]]})
	_thing(d, {"id": "s_roc", "kind": "trigger", "pos": Vector3(0, 0, -36.0), "r": 5.5, "story": "roc", "if": "!roc_done"})
	_thing(d, {"id": "s_shard", "kind": "shard", "pos": Vector3(0, 0, -41.0), "summon": "phoenix", "if": "roc_done", "color": Color(1.0, 0.55, 0.25)})
	_thing(d, {"id": "s_barrier", "kind": "barrier", "pos": Vector3(0, 0, -46.5), "gate": "roc_exit", "flag": "roc_done"})
	_enc(d, Vector3(1.0, 0, 9), 0, 1.5)
	_enc(d, Vector3(-1.0, 0, -12), 2, 1.5)
	_enc(d, Vector3(0, 0, 19.0), 3, 0.6)
	_enc(d, Vector3(0, 0, -23.0), 4, 0.6)
	return d


# =================================================================================================
# SHADOW CASTLE

static func _castle(vr: bool) -> Dictionary:
	var d := _new_def("castle")
	var nav: Nav = d["nav"]
	nav.capsule(Vector3(0, 0, 36), Vector3(0, 0, 24), 2.4)
	nav.circle(Vector3(0, 0, 15), 10.0)
	nav.rect(Vector3(-6, 0, 6), Vector3(6, 0, -23))
	nav.rect(Vector3(-10.5, 0, -5), Vector3(-6, 0, -12))
	nav.rect(Vector3(6, 0, -5), Vector3(10.5, 0, -12))
	nav.capsule(Vector3(0, 0, -22), Vector3(0, 0, -28), 3.0)
	nav.circle(Vector3(0, 0, -35), 9.5)
	var pillars: Array[Vector3] = []
	for z in [1.0, -5.0, -11.0, -17.0]:
		for x in [-3.8, 3.8]:
			pillars.append(Vector3(x, 0, z))
			nav.block(Vector3(x, 0, z), 0.65)
	nav.block(Vector3(7.5, 0, 15), 1.7)  # the water-shard fountain
	nav.block_box(Vector3(0, 0, -42.2), Vector2(5.0, 2.6))  # throne dais
	var root: Node3D = d["root"]
	_add_ground(d, {"seed": 9, "margin": 8.0, "cell": 0.75, "wall_h": 6.5, "wall_w": 0.9, "bump": 0.15,
		"floor_a": Color(0.5, 0.48, 0.52), "floor_b": Color(0.42, 0.4, 0.46), "wall_a": Color(0.45, 0.43, 0.5),
		"wall_b": Color(0.36, 0.34, 0.42), "checker": 2.0, "paths": [[Vector3(0, 0, 6), Vector3(0, 0, -40), 1.2]],
		"path_c": Color(0.55, 0.18, 0.32)})
	var b := MeshKit.Builder.new()
	for p in pillars:
		b.cylinder(0.55, 0.62, 6.0, MeshKit.at(p + Vector3(0, 3.0, 0)), Color(0.55, 0.52, 0.6), 10)
		b.box(Vector3(1.4, 0.3, 1.4), MeshKit.at(p + Vector3(0, 0.15, 0)), Color(0.45, 0.43, 0.5))
	# Towers and battlements around the courtyard.
	for k in 6:
		var a := k * TAU / 6.0 + 0.3
		var tp := Vector3(cos(a) * 13.0, 0, 15.0 + sin(a) * 13.0)
		b.cylinder(1.8, 2.0, 10.0, MeshKit.at(tp + Vector3(0, 5.0, 0)), Color(0.42, 0.4, 0.48), 10)
		b.cone(2.4, 3.6, MeshKit.at(tp + Vector3(0, 11.8, 0)), Color(0.35, 0.22, 0.45), 10)
		b.box(Vector3(0.5, 0.9, 0.12), MeshKit.at(tp + Vector3(0, 6.5, 0) + Vector3(-cos(a), 0, -sin(a)) * 1.85, Vector3.ONE, Vector3(0, -a + PI * 0.5, 0)),
			Color(1.0, 0.75, 0.35), true)
	# Gate and drawbridge.
	b.box(Vector3(4.6, 0.25, 9.0), MeshKit.at(Vector3(0, -0.12, 30.0)), WOOD.darkened(0.2))
	_gate(b, Vector3(0, 0, 25.0), 0.0, Color(0.4, 0.38, 0.46), 6.0)
	# The water-shard fountain.
	b.cylinder(1.6, 1.8, 0.7, MeshKit.at(Vector3(7.5, 0.35, 15)), Color(0.5, 0.5, 0.6), 16)
	b.disc(1.45, MeshKit.at(Vector3(7.5, 0.66, 15)), Color(0.25, 0.5, 0.9), 16, true)
	# Throne room: dais, throne, purple banners, stained windows.
	b.box(Vector3(5.0, 0.6, 2.6), MeshKit.at(Vector3(0, 0.3, -42.2)), Color(0.32, 0.28, 0.38))
	b.rounded_box(Vector3(1.8, 3.6, 0.6), 0.15, MeshKit.at(Vector3(0, 2.4, -43.0)), Color(0.25, 0.18, 0.3))
	b.rounded_box(Vector3(1.4, 0.4, 1.2), 0.1, MeshKit.at(Vector3(0, 1.0, -42.5)), Color(0.5, 0.15, 0.3))
	for x in [-2.0, -1.0, 0.0, 1.0, 2.0]:
		b.sphere(0.12, MeshKit.at(Vector3(x * 0.4, 4.3, -43.0)), Color(0.9, 0.3, 0.8), 8, true)
	for k in 6:
		var a2 := PI + (k - 2.5) * 0.36
		var bp := Vector3(0, 0, -35) + Vector3(sin(a2), 0, cos(a2)) * 9.6
		b.box(Vector3(1.0, 3.2, 0.06), MeshKit.at(bp + Vector3(0, 4.2, 0), Vector3.ONE, Vector3(0, a2, 0)), Color(0.45, 0.15, 0.55))
		b.box(Vector3(0.8, 1.6, 0.05), MeshKit.at(bp + Vector3(0, 7.0, 0), Vector3.ONE, Vector3(0, a2, 0)), Color(0.55, 0.35, 0.95), true)
	for z in [3.0, -3.0, -9.0, -15.0, -21.0]:
		for x in [-6.3, 6.3]:
			b.box(Vector3(0.06, 1.8, 0.9), MeshKit.at(Vector3(x, 4.6, z)), Color(0.5, 0.4, 0.95) if int(z) % 2 == 0 else Color(0.9, 0.4, 0.6), true)
	root.add_child(MeshKit.instance(b.build()))
	var torches: Array[Vector3] = [Vector3(-5.6, 1.6, -21), Vector3(5.6, 1.6, -21), Vector3(-2.4, 0, 23.5), Vector3(2.4, 0, 23.5)]
	root.add_child(MeshKit.scatter(MeshKit.prop("torch"), _xforms(torches, 1.0, 0)))
	var l1 := SkyKit.flicker_light(Color(1.0, 0.65, 0.35), 2.0, 14.0)
	l1.position = Vector3(0, 4.0, -9)
	root.add_child(l1)
	var l2 := SkyKit.flicker_light(Color(0.85, 0.5, 1.0), 2.6, 18.0)
	l2.position = Vector3(0, 6.0, -36)
	root.add_child(l2)
	d["lights"] = 2
	root.add_child(_scatter_outside(nav, MeshKit.prop("rock", 2), 30, 0.2, 2.0, 51, 0.6, 1.2, d))
	d["spawns"] = {"from_skybridge": [Vector3(0, 0, 32), 0.0], "save": [Vector3(-1.5, 0, -18.5), 0.0], "throne": [Vector3(0, 0, -24.0), 0.0]}
	d["exits"] = [{"id": "south", "pos": Vector3(0, 0, 36.5), "r": 2.4, "to": "skybridge", "spawn": "from_castle"}]
	_thing(d, {"id": "k_save", "kind": "save", "pos": Vector3(-3.6, 0, -19.6)})
	_thing(d, {"id": "k_sign", "kind": "sign", "pos": Vector3(3.0, 0, 27.0), "yaw": 0.0, "title": "SHADOW CASTLE",
		"text": "KEEP OUT! (This means you, hero.) - The Shadow King"})
	_thing(d, {"id": "k_shard", "kind": "shard", "pos": Vector3(7.5, 0, 15.0), "summon": "leviathan", "color": Color(0.3, 0.6, 1.0), "touch": true})
	_thing(d, {"id": "k_chest1", "kind": "chest", "pos": Vector3(-9.2, 0, -8.5), "yaw": PI * 0.5, "loot": [["crystal_blade", 1], ["elixir", 1]]})
	_thing(d, {"id": "k_chest2", "kind": "chest", "pos": Vector3(9.2, 0, -8.5), "yaw": -PI * 0.5, "loot": [["elixir", 1]], "mimic": true})
	_thing(d, {"id": "k_chest3", "kind": "chest", "pos": Vector3(-7.5, 0, 20.0), "yaw": PI * 0.6, "loot": [["crystal_mail", 1], ["hi_potion", 2]]})
	_thing(d, {"id": "k_throne", "kind": "trigger", "pos": Vector3(0, 0, -30.0), "r": 6.0, "story": "king", "if": "!king_done"})
	_enc(d, Vector3(-4.0, 0, 12), 0, 2.0)
	_enc(d, Vector3(4.0, 0, 19), 2, 2.0)
	_enc(d, Vector3(0, 0, -3), 1, 1.2)
	_enc(d, Vector3(0, 0, -14), 4, 1.2)
	return d


# =================================================================================================
# Building blocks

## Build the ground for area def `d` (remembers its options so props can sit on the hills).
static func _add_ground(d: Dictionary, o: Dictionary) -> void:
	d["ground_opts"] = o
	var noise := FastNoiseLite.new()
	noise.seed = int(o.get("seed", 1))
	noise.frequency = 0.09
	d["ground_noise"] = noise
	(d["root"] as Node3D).add_child(_ground(d["nav"], o))


## A heightfield ground over the nav bounds: flat (y = 0) where you can walk, rising into hills / rock
## walls outside. o: seed, cell, margin, wall_h, wall_w, bump, floor_a/b, wall_a/b, paths ([a, b, r]
## capsules painted path_c), checker (flagstone size).
static func _ground(nav: Nav, o: Dictionary) -> MeshInstance3D:
	var cell: float = o.get("cell", 1.0)
	var margin: float = o.get("margin", 12.0)
	var bb: Rect2 = nav.bounds.grow(margin)
	var nx := int(ceil(bb.size.x / cell)) + 1
	var nz := int(ceil(bb.size.y / cell)) + 1
	var noise := FastNoiseLite.new()
	noise.seed = int(o.get("seed", 1))
	noise.frequency = 0.09
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var cols := PackedColorArray()
	cols.resize(nx * nz)
	var floor_a: Color = o.get("floor_a", GRASS)
	var floor_b: Color = o.get("floor_b", GRASS2)
	var wall_a: Color = o.get("wall_a", GRASS)
	var wall_b: Color = o.get("wall_b", GRASS2)
	var path_c: Color = o.get("path_c", DIRT)
	var paths: Array = o.get("paths", [])
	var checker: float = o.get("checker", 0.0)
	for j in nz:
		for i in nx:
			var p := bb.position + Vector2(i * cell, j * cell)
			var n := noise.get_noise_2d(p.x, p.y)
			hs[j * nx + i] = _height_at(nav, p, o, n)
			var out := nav.outside(p)
			var c: Color
			if out <= 0.15:
				c = floor_a.lerp(floor_b, n * 0.5 + 0.5)
				if checker > 0.0:
					var cx := int(floor(p.x / checker)) + int(floor(p.y / checker))
					c = c.darkened(0.08 if cx % 2 == 0 else 0.0)
				for pc in paths:
					var pa: Vector3 = pc[0]
					var pb: Vector3 = pc[1]
					var pr: float = pc[2]
					var dd := Nav._seg_dist(p, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z))
					if dd < pr:
						c = c.lerp(path_c, clampf((pr - dd) / 0.6, 0.0, 1.0) * 0.9)
			else:
				var t := clampf(out / maxf(0.5, float(o.get("wall_w", 8.0))), 0.0, 1.0)
				c = floor_a.lerp(wall_a, clampf(t * 2.0, 0.0, 1.0)).lerp(wall_b, (n * 0.5 + 0.5) * t)
			cols[j * nx + i] = c
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			verts[k] = Vector3(bb.position.x + i * cell, hs[k], bb.position.y + j * cell)
			var hl := hs[j * nx + maxi(i - 1, 0)]
			var hr := hs[j * nx + mini(i + 1, nx - 1)]
			var hd := hs[maxi(j - 1, 0) * nx + i]
			var hu := hs[mini(j + 1, nz - 1) * nx + i]
			norms[k] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, MeshKit.vertex_material())
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _height_at(nav: Nav, p: Vector2, o: Dictionary, n: float) -> float:
	var out := nav.outside(p)
	if out <= 0.15:
		return 0.0
	var wall_h: float = o.get("wall_h", 3.0)
	var wall_w: float = o.get("wall_w", 8.0)
	var bump: float = o.get("bump", 0.5)
	var t := smoothstep(0.15, wall_w, out)
	return wall_h * t * (0.8 + 0.2 * n) + bump * n * t


## Ground height of the area at p (for props placed on the hills).
static func ground_height(def: Dictionary, p: Vector3) -> float:
	var o: Dictionary = def.get("ground_opts", {})
	if o.is_empty():
		return 0.0
	var noise: FastNoiseLite = def["ground_noise"]
	var v := Vector2(p.x, p.z)
	return _height_at(def["nav"], v, o, noise.get_noise_2d(v.x, v.y))


## Scatter `count` copies of mesh outside the walkable area (between min_out and max_out metres out),
## sitting on the ground heightfield. One MultiMesh = one draw call.
static func _scatter_outside(nav: Nav, mesh: Mesh, count: int, min_out: float, max_out: float, seed_value: int,
		smin: float, smax: float, def: Dictionary) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bb: Rect2 = nav.bounds.grow(max_out)
	var xfs: Array = []
	var tries := 0
	var o: Dictionary = _ground_opts_of(def)
	var noise := FastNoiseLite.new()
	noise.seed = int(o.get("seed", 1))
	noise.frequency = 0.09
	while xfs.size() < count and tries < count * 30:
		tries += 1
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		var out := nav.outside(p)
		if out < min_out or out > max_out:
			continue
		var y := _height_at(nav, p, o, noise.get_noise_2d(p.x, p.y)) if not o.is_empty() else 0.0
		var s := rng.randf_range(smin, smax)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y - 0.05, p.y)))
	return MeshKit.scatter(mesh, xfs)


## Scatter small decorations inside the walkable area (flowers, grass, mushrooms), avoiding blockers.
static func _scatter_inside(nav: Nav, mesh: Mesh, count: int, seed_value: int, smin: float, smax: float, _def: Dictionary,
		palette: PackedColorArray) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bb: Rect2 = nav.bounds
	var xfs: Array = []
	var cols := PackedColorArray()
	var tries := 0
	while xfs.size() < count and tries < count * 30:
		tries += 1
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		var out := nav.outside(p)
		if out > -0.3 or nav.blocked(p, 0.4):
			continue
		var s := rng.randf_range(smin, smax)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0.0, p.y)))
		if not palette.is_empty():
			cols.append(palette[rng.randi() % palette.size()])
	return MeshKit.scatter(mesh, xfs, cols, PackedColorArray(), false)


static func _ground_opts_of(def: Dictionary) -> Dictionary:
	return def.get("ground_opts", {})


static func _xforms(points: Array, s: float, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for p in points:
		var v: Vector3 = p
		out.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s * rng.randf_range(0.9, 1.1)), v))
	return out


static func _trail_caps(points: Array, r: float) -> Array:
	var out: Array = []
	for i in range(points.size() - 1):
		out.append([points[i], points[i + 1], r])
	return out


## A cosy cottage (door on its local +Z side), turned by yaw.
static func _house(b: MeshKit.Builder, pos: Vector3, yaw: float, size: Vector3, wall: Color, roof: Color) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaw), pos)
	b.rounded_box(size, 0.12, base * MeshKit.at(Vector3(0, size.y * 0.5, 0)), wall)
	b.box(Vector3(size.x + 0.3, 0.35, size.z + 0.3), base * MeshKit.at(Vector3(0, 0.17, 0)), STONE)
	var half := size.z * 0.5 + 0.35
	var rh := size.y * 0.55
	b.wedge(Vector3(size.x + 0.6, rh, half), base * MeshKit.at(Vector3(0, size.y + rh * 0.5, half * 0.5)), roof)
	b.wedge(Vector3(size.x + 0.6, rh, half), base * MeshKit.at(Vector3(0, size.y + rh * 0.5, -half * 0.5), Vector3.ONE, Vector3(0, PI, 0)), roof.darkened(0.12))
	b.box(Vector3(0.6, 1.2, 0.6), base * MeshKit.at(Vector3(size.x * 0.28, size.y + rh * 0.7, -size.z * 0.15)), STONE.darkened(0.1))
	b.rounded_box(Vector3(1.0, 1.75, 0.12), 0.05, base * MeshKit.at(Vector3(0, 0.95, size.z * 0.5 + 0.03)), WOOD.darkened(0.15))
	b.sphere(0.05, base * MeshKit.at(Vector3(0.3, 0.95, size.z * 0.5 + 0.1)), Color(1.0, 0.85, 0.3), 6)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.7, 0.7, 0.08), base * MeshKit.at(Vector3(sx * size.x * 0.3, size.y * 0.55, size.z * 0.5 + 0.02)), Color(1.0, 0.85, 0.5), true)
		b.box(Vector3(0.9, 0.1, 0.12), base * MeshKit.at(Vector3(sx * size.x * 0.3, size.y * 0.55 - 0.42, size.z * 0.5 + 0.06)), WOOD)
	b.box(Vector3(0.08, 0.7, 0.08), base * MeshKit.at(Vector3(-size.x * 0.3, size.y * 0.55, size.z * 0.5 + 0.06)), WOOD)


## Village fountain.
static func _fountain(b: MeshKit.Builder, c: Vector3) -> void:
	b.cylinder(2.1, 2.2, 0.6, MeshKit.at(c + Vector3(0, 0.3, 0)), STONE, 20)
	b.disc(1.85, MeshKit.at(c + Vector3(0, 0.56, 0)), Color(0.35, 0.7, 1.0), 20, true)
	b.cylinder(0.25, 0.32, 1.6, MeshKit.at(c + Vector3(0, 1.1, 0)), STONE, 10)
	b.cylinder(0.85, 0.5, 0.3, MeshKit.at(c + Vector3(0, 1.9, 0)), STONE, 14)
	b.disc(0.75, MeshKit.at(c + Vector3(0, 2.06, 0)), Color(0.45, 0.8, 1.0), 14, true)
	b.sphere(0.18, MeshKit.at(c + Vector3(0, 2.3, 0)), Color(0.6, 0.9, 1.0), 10, true)


## The Crystal Shrine: a round platform with pillars around the pedestal at c.
static func _shrine(b: MeshKit.Builder, c: Vector3) -> void:
	b.cylinder(4.2, 4.4, 0.25, MeshKit.at(c + Vector3(0, 0.12, 0)), Color(0.82, 0.8, 0.86), 24)
	b.torus(3.4, 0.06, MeshKit.at(c + Vector3(0, 0.26, 0)), Color(0.6, 0.85, 1.0), 32, 4, true)
	b.cylinder(0.75, 0.95, 1.1, MeshKit.at(c + Vector3(0, 0.8, 0)), Color(0.9, 0.88, 0.95), 12)
	b.cylinder(0.95, 0.8, 0.2, MeshKit.at(c + Vector3(0, 1.45, 0)), Color(0.9, 0.85, 0.6), 12)
	for k in 6:
		var a := k * TAU / 6.0 + PI / 6.0
		var p := c + Vector3(cos(a), 0, sin(a)) * 3.8
		if absf(p.z - c.z - 3.8) < 0.6 and absf(p.x - c.x) < 2.0:
			continue
		b.cylinder(0.28, 0.32, 3.4, MeshKit.at(p + Vector3(0, 1.7, 0)), Color(0.92, 0.9, 0.96), 10)
		b.box(Vector3(0.8, 0.25, 0.8), MeshKit.at(p + Vector3(0, 3.5, 0)), Color(0.9, 0.85, 0.6))


## An archway gate (opening along Z at pos).
static func _gate(b: MeshKit.Builder, pos: Vector3, yaw: float, col: Color = STONE, h: float = 4.0) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaw), pos)
	for sx in [-1.0, 1.0]:
		b.rounded_box(Vector3(0.9, h, 0.9), 0.08, base * MeshKit.at(Vector3(sx * 2.4, h * 0.5, 0)), col)
		b.cone(0.65, 0.8, base * MeshKit.at(Vector3(sx * 2.4, h + 0.4, 0)), Color(0.75, 0.3, 0.25), 8)
	b.box(Vector3(5.6, 0.6, 1.0), base * MeshKit.at(Vector3(0, h - 0.2, 0)), col.darkened(0.08))
	b.box(Vector3(2.0, 0.6, 0.1), base * MeshKit.at(Vector3(0, h - 0.2, 0.52)), Color(0.95, 0.85, 0.55))


## A rough rock arch (cave mouth) facing +Z / -Z at pos.
static func _rock_arch(b: MeshKit.Builder, pos: Vector3, col: Color) -> void:
	for k in 9:
		var a := PI * float(k) / 8.0
		var p := pos + Vector3(cos(a) * 3.4, sin(a) * 3.6, 0)
		b.sphere(1.25 + 0.2 * float(k % 3), MeshKit.at(p, Vector3(1.0, 1.0, 1.3)), col.lerp(col.darkened(0.25), float(k % 2)), 9)
	b.disc(3.0, MeshKit.at(pos + Vector3(0, 1.6, -1.0), Vector3(1.0, 1.0, 1.15), Vector3(PI * 0.5, 0, 0)), Color(0.03, 0.03, 0.05), 16, false, true)


## A cluster of glowing crystals.
static func _crystal_cluster(b: MeshKit.Builder, pos: Vector3, col: Color, s: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31.0 + pos.z * 17.0)
	for k in 6:
		var dir := Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)).normalized()
		var h := s * rng.randf_range(0.8, 1.8)
		var p := pos + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * s
		b.cylinder(0.0, 0.22 * s, h, MeshKit.aim(p + dir * h * 0.5, dir), col.lerp(Color.WHITE, rng.randf() * 0.3), 6, true)


## One crystal (for MultiMesh scatter): glowing, origin at its base.
static func _crystal_mesh(col: Color) -> ArrayMesh:
	var key := "cs_crystal_%s" % col.to_html(false)
	var cached := ResCache.fetch(key) as ArrayMesh
	if cached != null:
		return cached
	var b := MeshKit.Builder.new()
	b.cylinder(0.0, 0.2, 1.1, MeshKit.at(Vector3(0, 0.55, 0)), col, 6, true)
	b.cylinder(0.0, 0.14, 0.7, MeshKit.aim(Vector3(0.18, 0.33, 0.05), Vector3(0.5, 1, 0.2)), col.lightened(0.2), 6, true)
	b.cylinder(0.0, 0.12, 0.6, MeshKit.aim(Vector3(-0.15, 0.28, -0.08), Vector3(-0.5, 1, -0.3)), col.darkened(0.1), 6, true)
	var m := b.build()
	ResCache.put(key, m)
	return m


## A floating island: grassy top (y = 0) and a rocky cone underneath.
static func _island(b: MeshKit.Builder, c: Vector3, r: float, depth: float) -> void:
	b.cylinder(r, r, 0.6, MeshKit.at(c + Vector3(0, -0.3, 0)), Color(0.48, 0.75, 0.4), 20)
	b.cylinder(r * 1.02, r * 0.95, 0.8, MeshKit.at(c + Vector3(0, -1.0, 0)), Color(0.62, 0.5, 0.42), 20)
	b.cone(r * 0.95, depth, MeshKit.at(c + Vector3(0, -1.4 - depth * 0.5, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.55, 0.43, 0.38), 14)
