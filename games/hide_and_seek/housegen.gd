extends RefCounted
## THE HOUSE from a seed (Hide and Seek's map 0 is new every visit). Pure data, no nodes: map_house.gd
## builds it, tests/hide_and_seek_gen_test.gd proves it over many seeds, tests/hide_and_seek_bot.gd
## cross-checks sample houses with real physics.
##
## Layout: a grid of rooms, 3 (or 4 from house 5 on: Story.columns) across and 2 deep, x centred on 0,
## z -7..7. Column widths and the north/south split vary. One south room is the HALL (the seeker counts
## facing the front door, the jail cage sits in a corner, hiders start behind the seeker); the others are
## a living room, kitchen, bedroom, playroom, bathroom (+ bunk room and study in big houses), shuffled.
## Doorways: a random spanning tree over the rooms (everything connected) plus a few extra doors (loops
## to run round). The BACK GARDEN (8 m, fenced) is on the west or east, through a garden door.
## Furniture comes from a small catalog (KINDS: local boxes against a wall or free-standing), placed with
## walkways between pieces and never in front of a doorway; HIDING SPOTS are the catalog's nooks (in the
## wardrobe, the play fort, under the table, in the shed, behind a hedge...) and quiet corners. Decoy
## props (lamp, pot plant, box, teddy, beach ball) fit each room. Every solid box the builder makes a
## collider for is in g.solids, so the validator checks exactly what the physics will have.
##
## check() is the validator: on a 20 cm grid, flood-fill from the counting spot for a hider (r 0.3,
## 0.9 tall) and for the seeker (r 0.32, 1.6 tall): every room, doorway, spawn, star spot and the jail
## bell is walkable; every hiding spot is reachable by a hider AND close enough for the seeker to touch
## (so every hider can be found); no walled-off pockets. generate() retries (new salt) until check passes.
## Same (seed, spec) -> same house on every machine (the host sends [seed, level, theme, daily]).

const Seeded := preload("res://core/seeded.gd")
const Story := preload("res://games/hide_and_seek/story.gd")

const TITLE := "THE HOUSE"
const HALF_Z := 7.0
const WALL_T := 0.16
const WALL_H := 2.6
const DOOR_W := 1.5
const DOOR_H := 2.15
const GARDEN_W := 8.0
const FENCE_T := 0.2
const JAIL_HALF := 0.65
const CELL := 0.2
const HIDER := [0.3, 0.9]  ## radius, height (player.gd)
const SEEKER := [0.32, 1.6]
const TOUCH := 0.95  ## main.gd BODY_TOUCH: a flat seeker this close to a hider finds them
const GAP := 0.9  ## walkway kept between furniture pieces
const MIN_SPOTS := 10
const MIN_STARS := 12
const ATTEMPTS := 12
## Decoy footprint half-size and height per prop kind (world.gd _bake_prop colliders).
const PROP_R: Array = [0.22, 0.3, 0.33, 0.3, 0.33]
const PROP_H: Array = [1.2, 1.2, 0.66, 0.9, 0.66]

const NAMES := {"hall": "hall", "living": "living room", "kitchen": "kitchen", "bedroom": "bedroom", "playroom": "playroom",
	"bathroom": "bathroom", "bunkroom": "bunk room", "study": "study", "garden": "garden"}
## What goes in each room: [kind, chance], biggest first.
const ROOM_KIT := {
	"hall": [["bench", 0.8], ["coatstand", 0.8], ["bookcase", 0.3]],
	"living": [["sofa", 1.0], ["tv", 1.0], ["armchair", 0.8], ["bookcase", 0.6], ["coffee", 0.6]],
	"kitchen": [["counter", 1.0], ["table", 1.0], ["fridge", 1.0], ["stove", 0.6]],
	"bedroom": [["bed", 1.0], ["wardrobe", 1.0], ["dresser", 0.7]],
	"playroom": [["fort", 1.0], ["ballpit", 0.9], ["beanbag", 0.8], ["beanbag", 0.5], ["toychest", 0.6]],
	"bathroom": [["bathtub", 1.0], ["toilet", 1.0], ["sink", 1.0]],
	"bunkroom": [["bunk", 1.0], ["wardrobe", 0.8], ["toychest", 0.8]],
	"study": [["desk", 1.0], ["bookcase", 1.0], ["bookcase", 0.7], ["armchair", 0.8]],
	"garden": [["shed", 1.0], ["hedge", 1.0], ["tree", 1.0], ["tree", 1.0], ["slide", 0.8], ["hedge", 0.6], ["sandpit", 0.7],
		["washline", 0.6], ["tree", 0.5]],
}
## Decoy kinds that fit each room (0 lamp, 1 pot plant, 2 box, 3 teddy, 4 beach ball).
const DECOY_KIT := {"hall": [0, 1, 2], "living": [0, 1, 3], "kitchen": [1, 2], "bedroom": [3, 0, 2], "playroom": [4, 3, 2],
	"bathroom": [1, 2], "bunkroom": [3, 4, 2], "study": [0, 1, 2], "garden": [1, 4, 2]}

static var _cache := {}


## Tests: forget remembered houses (so "same seed -> same house" is really rebuilt).
static func clear_cache() -> void:
	_cache.clear()


## The furniture catalog. Local frame: u along the wall (x), v into the room (z), y up. Wall pieces sit
## with v = 0 on the wall's face; free pieces are centred on 0. solids: [centre, size] boxes (colliders);
## nooks: hiding spots [u, v]; w/d: the footprint kept clear of other pieces.
static func kind_def(k: String) -> Dictionary:
	match k:
		"sofa":
			return {"w": 2.4, "d": 0.95, "solids": [[Vector3(0, 0.475, 0.475), Vector3(2.4, 0.95, 0.95)]], "nooks": [Vector2(1.65, 0.5), Vector2(-1.65, 0.5)]}
		"armchair":
			return {"w": 0.95, "d": 0.95, "solids": [[Vector3(0, 0.5, 0.475), Vector3(0.95, 1.0, 0.95)]], "nooks": [Vector2(0.95, 0.45)]}
		"tv":
			return {"w": 1.7, "d": 0.45, "solids": [[Vector3(0, 0.25, 0.225), Vector3(1.7, 0.5, 0.45)]]}
		"bookcase":
			return {"w": 1.4, "d": 0.35, "solids": [[Vector3(0, 1.0, 0.175), Vector3(1.4, 2.0, 0.35)]], "tall": true}
		"coffee":
			return {"free": true, "w": 1.2, "d": 0.7, "solids": [[Vector3(0, 0.2, 0), Vector3(1.2, 0.4, 0.7)]]}
		"counter":
			return {"w": 3.0, "d": 0.7, "solids": [[Vector3(0, 0.45, 0.35), Vector3(3.0, 0.9, 0.7)]], "nooks": [Vector2(1.95, 0.45)]}
		"fridge":
			return {"w": 0.8, "d": 0.75, "solids": [[Vector3(0, 1.0, 0.375), Vector3(0.8, 2.0, 0.75)]], "tall": true}
		"stove":
			return {"w": 0.8, "d": 0.7, "solids": [[Vector3(0, 0.45, 0.35), Vector3(0.8, 0.9, 0.7)]]}
		"table":  # tall enough to crawl under (the top's underside is above a hider)
			var s: Array = [[Vector3(0, 1.0, 0), Vector3(2.0, 0.08, 1.2)], [Vector3(1.35, 0.25, 0), Vector3(0.5, 0.5, 0.5)],
				[Vector3(-1.35, 0.25, 0), Vector3(0.5, 0.5, 0.5)]]
			for lu in [-0.9, 0.9]:
				for lv in [-0.5, 0.5]:
					s.append([Vector3(lu, 0.48, lv), Vector3(0.1, 0.96, 0.1)])
			return {"free": true, "w": 3.2, "d": 1.2, "solids": s, "nooks": [Vector2(0, 0.25)]}
		"bed":
			return {"w": 2.0, "d": 2.4, "solids": [[Vector3(0, 0.3, 1.2), Vector3(2.0, 0.6, 2.4)], [Vector3(0, 0.55, 0.06), Vector3(2.0, 1.1, 0.12)]],
				"nooks": [Vector2(1.45, 1.7), Vector2(-1.45, 1.7)]}
		"wardrobe":  # open front: step inside
			return {"w": 1.56, "d": 0.8, "tall": true, "solids": [[Vector3(0, 1.05, 0.04), Vector3(1.56, 2.1, 0.08)],
				[Vector3(0.74, 1.05, 0.4), Vector3(0.08, 2.1, 0.8)], [Vector3(-0.74, 1.05, 0.4), Vector3(0.08, 2.1, 0.8)],
				[Vector3(0, 2.13, 0.4), Vector3(1.56, 0.06, 0.8)]], "nooks": [Vector2(0, 0.45)]}
		"dresser":
			return {"w": 1.0, "d": 0.5, "solids": [[Vector3(0, 0.3, 0.25), Vector3(1.0, 0.6, 0.5)]]}
		"fort":  # three walls and a roof: hiders fit, the seeker reaches in
			return {"w": 2.0, "d": 1.1, "solids": [[Vector3(0, 0.6, 0.06), Vector3(2.0, 1.2, 0.12)], [Vector3(0.94, 0.6, 0.55), Vector3(0.12, 1.2, 1.1)],
				[Vector3(-0.94, 0.6, 0.55), Vector3(0.12, 1.2, 1.1)], [Vector3(0, 1.25, 0.55), Vector3(2.3, 0.1, 1.2)]], "nooks": [Vector2(0, 0.75)]}
		"ballpit":  # low walls with a gap on one side
			return {"free": true, "w": 2.2, "d": 2.2, "solids": [[Vector3(0, 0.25, -1.04), Vector3(2.2, 0.5, 0.12)],
				[Vector3(0, 0.25, 1.04), Vector3(2.2, 0.5, 0.12)], [Vector3(-1.04, 0.25, 0), Vector3(0.12, 0.5, 2.2)],
				[Vector3(1.04, 0.25, -0.85), Vector3(0.12, 0.5, 0.5)], [Vector3(1.04, 0.25, 0.85), Vector3(0.12, 0.5, 0.5)]],
				"nooks": [Vector2(-0.35, 0)]}
		"beanbag":
			return {"free": true, "w": 0.8, "d": 0.8, "solids": [[Vector3(0, 0.25, 0), Vector3(0.8, 0.5, 0.8)]]}
		"toychest":
			return {"w": 1.0, "d": 0.5, "solids": [[Vector3(0, 0.25, 0.25), Vector3(1.0, 0.5, 0.5)]]}
		"bathtub":
			return {"w": 2.0, "d": 0.95, "solids": [[Vector3(0, 0.3, 0.475), Vector3(2.0, 0.6, 0.95)]], "nooks": [Vector2(1.45, 0.45)]}
		"toilet":
			return {"w": 0.5, "d": 0.75, "solids": [[Vector3(0, 0.4, 0.375), Vector3(0.5, 0.8, 0.75)]]}
		"sink":
			return {"w": 0.6, "d": 0.45, "solids": [[Vector3(0, 0.425, 0.225), Vector3(0.6, 0.85, 0.45)]]}
		"bunk":
			return {"w": 2.0, "d": 1.0, "tall": true, "solids": [[Vector3(0, 0.25, 0.5), Vector3(2.0, 0.5, 1.0)], [Vector3(0, 1.4, 0.5), Vector3(2.0, 0.15, 1.0)]],
				"nooks": [Vector2(1.45, 0.5)]}
		"desk":
			return {"w": 1.4, "d": 0.7, "solids": [[Vector3(0, 0.39, 0.35), Vector3(1.4, 0.78, 0.7)]]}
		"bench":
			return {"w": 1.2, "d": 0.4, "solids": [[Vector3(0, 0.225, 0.2), Vector3(1.2, 0.45, 0.4)]]}
		"coatstand":
			return {"w": 0.5, "d": 0.5, "solids": [[Vector3(0, 0.9, 0.25), Vector3(0.1, 1.8, 0.1)]]}
		"shed":  # against the far fence, the doorway facing the house: step inside
			return {"w": 2.2, "d": 2.2, "fence": true, "solids": [[Vector3(0, 1.0, 0.05), Vector3(2.2, 2.0, 0.1)],
				[Vector3(1.1, 1.0, 1.1), Vector3(0.1, 2.0, 2.2)], [Vector3(-1.1, 1.0, 1.1), Vector3(0.1, 2.0, 2.2)],
				[Vector3(0.85, 1.0, 2.15), Vector3(0.5, 2.0, 0.1)], [Vector3(-0.85, 1.0, 2.15), Vector3(0.5, 2.0, 0.1)],
				[Vector3(-0.55, 0.4, 0.55), Vector3(0.8, 0.8, 0.6)]], "nooks": [Vector2(0.45, 0.8)]}
		"hedge":  # a metre off the fence: crouch behind it
			return {"w": 2.2, "d": 1.6, "fence": true, "solids": [[Vector3(0, 0.5, 1.3), Vector3(2.2, 1.0, 0.6)]], "nooks": [Vector2(0, 0.5)]}
		"tree":
			return {"free": true, "w": 1.2, "d": 1.2, "solids": [[Vector3(0, 1.1, 0), Vector3(0.5, 2.2, 0.5)]], "nooks": [Vector2(0, 0.75)]}
		"slide":
			return {"free": true, "w": 0.9, "d": 3.0, "solids": [[Vector3(0, 0.6, 1.1), Vector3(0.7, 1.2, 0.7)]]}
		"sandpit":
			return {"free": true, "w": 1.9, "d": 1.9, "solids": []}
		"washline":
			return {"free": true, "w": 0.6, "d": 4.4, "solids": [[Vector3(0, 0.95, -2.0), Vector3(0.08, 1.9, 0.08)], [Vector3(0, 0.95, 2.0), Vector3(0.08, 1.9, 0.08)]]}
		"kennel":  # Pip's kennel against the house's garden wall; his toys lie in front of it
			return {"w": 1.1, "d": 2.0, "solids": [[Vector3(0, 0.5, 0.5), Vector3(1.1, 1.0, 1.0)]], "nooks": [Vector2(0.95, 0.5)]}
	return {"w": 0.5, "d": 0.5, "solids": []}


## Inward normal -> the along-wall axis (a x up = n, so the piece's basis is right-handed).
static func along(n: Vector3) -> Vector3:
	return Vector3(n.z, 0.0, -n.x)


## A piece's local point -> world.
static func to_world(pc: Dictionary, local: Vector3) -> Vector3:
	var n: Vector3 = pc.n
	return (pc.o as Vector3) + along(n) * local.x + n * local.z + Vector3.UP * local.y


static func size_world(n: Vector3, s: Vector3) -> Vector3:
	return s if absf(n.z) > 0.5 else Vector3(s.z, s.y, s.x)


## A piece's footprint (world rect on the floor).
static func footprint(pc: Dictionary) -> Rect2:
	var d := kind_def(String(pc.k))
	var w := float(d.w)
	var dd := float(d.d)
	var v0 := -dd / 2.0 if d.get("free", false) else 0.0
	var a := to_world(pc, Vector3(-w / 2.0, 0, v0))
	var b := to_world(pc, Vector3(w / 2.0, 0, v0 + dd))
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


static func _r(v: float) -> float:
	return snappedf(v, 0.01)


static func _v(x: float, z: float) -> Vector3:
	return Vector3(snappedf(x, 0.01), 0.0, snappedf(z, 0.01))


## spec: {level, theme, daily}. Returns the house (see the keys at the end of _try), or the last try with
## ok = false if no try passed (the gen test makes sure that never happens).
static func generate(seed_value: int, spec: Dictionary = {}) -> Dictionary:
	var key := "%d|%d|%d|%s" % [seed_value, int(spec.get("level", 0)), int(spec.get("theme", 0)), str(bool(spec.get("daily", false)))]
	if _cache.has(key):
		return _cache[key]
	var g := {}
	for attempt in ATTEMPTS:
		g = _try(seed_value, spec, attempt)
		if check(g).is_empty():
			g["ok"] = true
			break
	if _cache.size() > 6:
		_cache.clear()
	_cache[key] = g
	return g


static func _try(seed_value: int, spec: Dictionary, attempt: int) -> Dictionary:
	var r := Seeded.rng(seed_value, "house%d" % attempt)
	var level := maxi(0, int(spec.get("level", 0)))
	var cols := Story.columns(level)
	# Columns and the north/south split.
	var widths: Array = []
	var total := 0.0
	for c in cols:
		var w := _r(r.randf_range(5.3, 7.0))
		widths.append(w)
		total += w
	var xs: Array = [_r(-total / 2.0)]
	for c in cols:
		xs.append(_r(float(xs[-1]) + float(widths[c])))
	var zs := _r(r.randf_range(-0.5, 1.5))
	var gside := -1 if r.randf() < 0.5 else 1
	# Rooms: cell (c, row) -> index c * 2 + row (row 0 north, 1 south). The hall is a south room.
	var hall_c := r.randi() % cols
	var types: Array = ["living", "kitchen", "bedroom", "playroom", "bathroom"]
	if cols >= 4:
		types.append_array(["bunkroom", "study"])
	types = Seeded.shuffled(r, types)
	var rooms: Array = []
	var ti := 0
	for c in cols:
		for row in 2:
			var t := "hall" if (c == hall_c and row == 1) else String(types[ti])
			if t != "hall":
				ti += 1
			var z0 := -HALF_Z if row == 0 else zs
			var z1 := zs if row == 0 else HALF_Z
			var rect := Rect2(Vector2(float(xs[c]), z0), Vector2(float(xs[c + 1]) - float(xs[c]), z1 - z0))
			rooms.append({"type": t, "rect": rect, "inner": rect.grow(-WALL_T / 2.0), "c": c, "row": row})
	var hx0: float = xs[0]
	var hx1: float = xs[-1]
	var gx_far := hx0 - GARDEN_W if gside < 0 else hx1 + GARDEN_W
	var gx_near := hx0 if gside < 0 else hx1
	var garden_rect := Rect2(Vector2(minf(gx_far, gx_near), -HALF_Z), Vector2(GARDEN_W, HALF_Z * 2.0))
	var garden_inner := Rect2(Vector2(minf(gx_far, gx_near) + (FENCE_T / 2.0 if gside < 0 else WALL_T / 2.0), -HALF_Z + FENCE_T / 2.0),
		Vector2(GARDEN_W - FENCE_T / 2.0 - WALL_T / 2.0, HALF_Z * 2.0 - FENCE_T))
	rooms.append({"type": "garden", "rect": garden_rect, "inner": garden_inner, "c": -1, "row": -1})
	var gi := rooms.size() - 1
	# Doorways: a spanning tree over the rooms + a few loops.
	var edges: Array = []
	for c in cols:
		edges.append([c * 2, c * 2 + 1])
		if c + 1 < cols:
			edges.append([c * 2, (c + 1) * 2])
			edges.append([c * 2 + 1, (c + 1) * 2 + 1])
	edges = Seeded.shuffled(r, edges)
	var parent: Array = range(cols * 2)
	var door_edges: Array = []
	for e in edges:
		var a := _root(parent, int(e[0]))
		var b := _root(parent, int(e[1]))
		if a != b:
			parent[a] = b
			door_edges.append(e)
		elif r.randf() < 0.3:
			door_edges.append(e)
	# Walls: one segment per room edge. axis 0: along x at z = at; axis 1: along z at x = at.
	var walls: Array = []
	for c in cols:
		var x0: float = xs[c]
		var x1: float = xs[c + 1]
		walls.append({"axis": 0, "at": -HALF_Z, "a": x0, "b": x1, "doors": [], "sides": [-1, c * 2]})
		walls.append({"axis": 0, "at": zs, "a": x0, "b": x1, "doors": [], "sides": [c * 2, c * 2 + 1]})
		walls.append({"axis": 0, "at": HALF_Z, "a": x0, "b": x1, "doors": [], "sides": [c * 2 + 1, -1]})
		for row in 2:
			var z0 := -HALF_Z if row == 0 else zs
			var z1 := zs if row == 0 else HALF_Z
			var left := (c - 1) * 2 + row if c > 0 else (gi if gside < 0 else -1)
			walls.append({"axis": 1, "at": x0, "a": z0, "b": z1, "doors": [], "sides": [left, c * 2 + row]})
			if c == cols - 1:
				walls.append({"axis": 1, "at": x1, "a": z0, "b": z1, "doors": [], "sides": [c * 2 + row, gi if gside > 0 else -1]})
	var doors: Array = []
	for e in door_edges:
		var w := _wall_between(walls, int(e[0]), int(e[1]))
		var at := _r(r.randf_range(float(w.a) + 1.35, float(w.b) - 1.35))
		(w.doors as Array).append(at)
		doors.append(["%s-%s" % [NAMES[rooms[int(e[0])].type], NAMES[rooms[int(e[1])].type]], _door_pos(w, at)])
	# The garden door: from one of the two rooms on the garden side (not the bathroom if it can help it).
	var edge_c := 0 if gside < 0 else cols - 1
	var grow := r.randi() % 2
	if rooms[edge_c * 2 + grow].type == "bathroom":
		grow = 1 - grow
	var gw := _wall_between(walls, edge_c * 2 + grow, gi)
	var gat := _r(r.randf_range(float(gw.a) + 1.35, float(gw.b) - 1.35))
	(gw.doors as Array).append(gat)
	doors.append(["%s-garden" % NAMES[rooms[edge_c * 2 + grow].type], _door_pos(gw, gat)])
	# Keep-clear zones: both sides of every doorway.
	var reserved: Array = []
	for w in walls:
		for at in w.doors:
			var p := _door_pos(w, float(at))
			reserved.append(Rect2(Vector2(p.x, p.z), Vector2.ZERO).grow_individual(
				1.3 if int(w.axis) == 1 else DOOR_W / 2.0 + 0.3, DOOR_W / 2.0 + 0.3 if int(w.axis) == 1 else 1.3,
				1.3 if int(w.axis) == 1 else DOOR_W / 2.0 + 0.3, DOOR_W / 2.0 + 0.3 if int(w.axis) == 1 else 1.3))
	# The hall: the seeker counts facing the front door, the jail in a corner, hiders behind.
	var hall: Dictionary = rooms[hall_c * 2 + 1]
	var hin: Rect2 = hall.inner
	var hcx := hin.get_center().x
	var js := -1 if r.randf() < 0.5 else 1
	var jail := _v((hin.end.x if js > 0 else hin.position.x) - js * (JAIL_HALF + 0.28), HALF_Z - WALL_T / 2.0 - JAIL_HALF - 0.2)
	var bell := _v(jail.x - js * 0.9, jail.z - 0.6)
	var seeker := _v(hcx - js * 0.5, HALF_Z - 1.2)
	var spawns: Array = [seeker]
	for o in [[-1.4, 3.4], [1.4, 3.4], [0.0, 3.7], [-1.8, 2.4], [1.8, 2.4], [-0.7, 2.6], [0.7, 2.6]]:
		spawns.append(_v(hcx + float(o[0]), seeker.z - float(o[1])))
	reserved.append(Rect2(Vector2(jail.x, jail.z), Vector2.ZERO).grow(JAIL_HALF + 0.45))
	reserved.append(Rect2(Vector2(bell.x, bell.z), Vector2.ZERO).grow(0.9))
	for sp in spawns:
		reserved.append(Rect2(Vector2(sp.x, sp.z), Vector2.ZERO).grow(0.55))
	# Pip's kennel first (on the house wall in the garden, clear of the garden door), then furniture.
	var pieces: Array = []
	var foot: Array = []
	var gdoor: Vector3 = doors[-1][1]
	for t in 40:
		var kz := r.randf_range(-HALF_Z + 1.2, HALF_Z - 1.2)
		if absf(kz - gdoor.z) < 2.2:
			continue
		var pc := {"k": "kennel", "o": _v(gx_near + gside * WALL_T / 2.0, kz), "n": Vector3(gside, 0, 0), "room": gi}
		pieces.append(pc)
		foot.append(footprint(pc))
		break
	for ri in rooms.size():
		var rm: Dictionary = rooms[ri]
		for item in ROOM_KIT[rm.type]:
			if r.randf() > float(item[1]):
				continue
			var pc := _place(r, String(item[0]), rm, ri, gside, reserved, foot)
			if not pc.is_empty():
				pieces.append(pc)
				foot.append(footprint(pc))
	# Hiding spots: the pieces' nooks and quiet corners.
	var nooks: Array = []
	for pc in pieces:
		for nk in kind_def(String(pc.k)).get("nooks", []):
			var p := to_world(pc, Vector3((nk as Vector2).x, 0, (nk as Vector2).y))
			nooks.append(_v(p.x, p.z))
	for rm in rooms:
		if rm.type == "hall":
			continue
		var inn: Rect2 = rm.inner
		for cz in [inn.position.y + 0.45, inn.end.y - 0.45]:
			for cx in [inn.position.x + 0.45, inn.end.x - 0.45]:
				var p := Vector2(cx, cz)
				if not _hits(Rect2(p, Vector2.ZERO).grow(0.35), reserved) and not _hits(Rect2(p, Vector2.ZERO).grow(0.35), foot):
					nooks.append(_v(cx, cz))
	# Decoys: props that fit each room, against the walls, never on a hiding spot.
	var decoys: Array = []
	var drects: Array = []
	var per := Story.decoys_per_room(level)
	for ri in rooms.size():
		var rm: Dictionary = rooms[ri]
		var want := per + (1 if rm.type == "garden" else 0) - (1 if rm.type == "bathroom" else 0)
		var kit: Array = DECOY_KIT[rm.type]
		var got := 0
		for t in 30:
			if got >= want:
				break
			var kind: int = kit[r.randi() % kit.size()]
			var pr: float = PROP_R[kind]
			var side := r.randi() % 4
			var inn: Rect2 = rm.inner
			var p := Vector2.ZERO
			var u := r.randf()
			var m := pr + GAP + 0.06  # far enough from the corner to walk round (no corner pockets)
			match side:
				0:
					p = Vector2(lerpf(inn.position.x + m, inn.end.x - m, u), inn.position.y + pr + 0.06)
				1:
					p = Vector2(lerpf(inn.position.x + m, inn.end.x - m, u), inn.end.y - pr - 0.06)
				2:
					p = Vector2(inn.position.x + pr + 0.06, lerpf(inn.position.y + m, inn.end.y - m, u))
				_:
					p = Vector2(inn.end.x - pr - 0.06, lerpf(inn.position.y + m, inn.end.y - m, u))
			var fr := Rect2(p, Vector2.ZERO).grow(pr)
			if _hits(fr, reserved) or _hits(fr.grow(GAP), foot):
				continue  # a walkway or touching nothing: never a corner pocket between a decoy and a piece
			var clash := _hits(fr.grow(GAP), drects)  # boxes, not circles: square corners can close a gap diagonally
			for nk in nooks:
				if Vector2((nk as Vector3).x, (nk as Vector3).z).distance_to(p) < pr + 0.6:
					clash = true
			if clash:
				continue
			decoys.append([kind, _v(p.x, p.y), _r(r.randf() * TAU)])
			drects.append(fr)
			got += 1
	# Windows on the outer walls (where nothing tall stands in front).
	var windows: Array = []
	for w in walls:
		if int(w.sides[0]) != -1 and int(w.sides[1]) != -1:
			continue
		var mid := (float(w.a) + float(w.b)) / 2.0 + r.randf_range(-0.8, 0.8)
		var ok := true
		for at in w.doors:
			ok = ok and absf(float(at) - mid) > 1.6
		var wp := _door_pos(w, mid)
		var probe := Rect2(Vector2(wp.x, wp.z), Vector2.ZERO).grow(0.9)
		for i in pieces.size():
			if kind_def(String(pieces[i].k)).get("tall", false) and (foot[i] as Rect2).intersects(probe):
				ok = false
		if ok:
			windows.append([Vector3(_r(wp.x), 1.55, _r(wp.z)), int(w.axis) == 1])
	var solids: Array = _wall_solids(walls, gside, gx_far, garden_rect)
	for pc in pieces:
		for s in kind_def(String(pc.k)).solids:
			var c := to_world(pc, s[0])
			solids.append([Vector3(_r(c.x), _r(c.y), _r(c.z)), size_world(pc.n, s[1])])
	for d in decoys:
		var kind: int = d[0]
		var p: Vector3 = d[1]
		solids.append([p + Vector3(0, float(PROP_H[kind]) / 2.0, 0), Vector3(PROP_R[kind] * 2.0, PROP_H[kind], PROP_R[kind] * 2.0)])
	var g := {"seed": seed_value, "level": level, "theme": int(spec.get("theme", 0)), "daily": bool(spec.get("daily", false)),
		"attempt": attempt, "title": TITLE, "cols": cols, "xs": xs, "zs": zs, "gside": gside, "gx_far": gx_far,
		"rooms_info": rooms, "walls": walls, "pieces": pieces, "decoys": decoys, "windows": windows, "solids": solids,
		"jail": jail, "bell": bell, "spawns": spawns, "front_door": _v(seeker.x, HALF_Z), "garden_door": gdoor,
		"bounds": [minf(gx_far, hx0), maxf(gx_far, hx1), -HALF_Z, HALF_Z], "ok": false}
	# Keep the hiding spots a hider can reach and the seeker can touch; then the star spots.
	var hg := raster(g, HIDER[0], HIDER[1])
	var sg := raster(g, SEEKER[0], SEEKER[1])
	var spots: Array = []
	for nk in nooks:
		var good := near(hg, nk, 0.25) and near(sg, nk, TOUCH)
		for o in spots:
			good = good and (o as Vector3).distance_to(nk) > 1.0
		if good:
			spots.append(nk)
	g["hide_spots"] = Seeded.shuffled(r, spots)
	var stars: Array = []
	for ri in rooms.size():
		var inn: Rect2 = rooms[ri].inner
		var want := 4 if rooms[ri].type == "garden" else 2
		for t in 12:
			if want <= 0:
				break
			var p := _v(r.randf_range(inn.position.x + 0.6, inn.end.x - 0.6), r.randf_range(inn.position.y + 0.6, inn.end.y - 0.6))
			if near(hg, p, 0.2) and not _hits(Rect2(Vector2(p.x, p.z), Vector2.ZERO).grow(0.5), [Rect2(Vector2(jail.x, jail.z), Vector2.ZERO).grow(1.0)]):
				stars.append(p)
				want -= 1
	g["star_spots"] = stars
	var names: Array = []
	var counts := {}
	for rm in rooms:
		var nm: String = NAMES[rm.type]
		counts[nm] = int(counts.get(nm, 0)) + 1
		var c2: Vector2 = (rm.rect as Rect2).get_center()
		names.append([nm if int(counts[nm]) == 1 else "%s %d" % [nm, int(counts[nm])], _v(c2.x, c2.y)])
	for pc in pieces:
		if pc.k == "shed":
			var sc := to_world(pc, Vector3(0, 0, 1.1))
			names.append(["garden shed", _v(sc.x, sc.z)])
	g["rooms"] = names
	g["doors"] = doors
	return g


static func _root(parent: Array, i: int) -> int:
	while int(parent[i]) != i:
		i = int(parent[i])
	return i


static func _wall_between(walls: Array, a: int, b: int) -> Dictionary:
	for w in walls:
		var s: Array = w.sides
		if (int(s[0]) == a and int(s[1]) == b) or (int(s[0]) == b and int(s[1]) == a):
			return w
	push_error("housegen: no wall between %d and %d" % [a, b])
	return walls[0]


static func _door_pos(w: Dictionary, at: float) -> Vector3:
	return _v(at, float(w.at)) if int(w.axis) == 0 else _v(float(w.at), at)


static func _hits(rect: Rect2, rects: Array) -> bool:
	for o in rects:
		if rect.intersects(o as Rect2):
			return true
	return false


## Place one piece in a room: against a wall (a fence for garden pieces) or free-standing, clear of the
## keep-clear zones and GAP away from every other piece. Returns {} if it doesn't fit.
static func _place(r: RandomNumberGenerator, k: String, rm: Dictionary, ri: int, gside: int, reserved: Array, foot: Array) -> Dictionary:
	var d := kind_def(k)
	var inn: Rect2 = rm.inner
	var w := float(d.w)
	for t in 30:
		var pc := {"k": k, "room": ri}
		if d.get("free", false):
			var n: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][r.randi() % 4]
			pc["n"] = n
			var half := size_world(n, Vector3(w, 0, float(d.d))) / 2.0
			var m := 0.95
			if inn.size.x < 2.0 * (half.x + m) or inn.size.y < 2.0 * (half.z + m):
				return {}
			pc["o"] = _v(r.randf_range(inn.position.x + half.x + m, inn.end.x - half.x - m), r.randf_range(inn.position.y + half.z + m, inn.end.y - half.z - m))
		else:
			var sides: Array = [0, 1, 2, 3]
			if rm.type == "garden":
				sides = [2 if gside < 0 else 3] if d.get("fence", false) and k == "shed" else ([0, 1, 2 if gside < 0 else 3] if d.get("fence", false) else [])
			if sides.is_empty():
				return {}
			var side: int = sides[r.randi() % sides.size()]
			var n: Vector3 = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)][side]
			pc["n"] = n
			var span := inn.size.x if side < 2 else inn.size.y
			if span < w + 0.2:
				continue
			var u := r.randf_range(w / 2.0 + 0.05, span - w / 2.0 - 0.05)
			match side:
				0:
					pc["o"] = _v(inn.position.x + u, inn.position.y)
				1:
					pc["o"] = _v(inn.position.x + u, inn.end.y)
				2:
					pc["o"] = _v(inn.position.x, inn.position.y + u)
				_:
					pc["o"] = _v(inn.end.x, inn.position.y + u)
		var fr := footprint(pc)
		if _hits(fr, reserved) or _hits(fr.grow(GAP), foot):
			continue
		if not inn.grow(0.01).encloses(fr):
			continue
		return pc
	return {}


## Collider boxes for every wall (door gaps cut, lintels above) and the garden fence.
static func _wall_solids(walls: Array, gside: int, gx_far: float, garden: Rect2) -> Array:
	var out: Array = []
	for w in walls:
		var a := float(w.a) - WALL_T / 2.0
		var cuts: Array = (w.doors as Array).duplicate()
		cuts.sort()
		for dc in cuts:
			var b := float(dc) - DOOR_W / 2.0
			if b > a:
				out.append(_seg(w, a, b, 0.0, WALL_H))
			out.append(_seg(w, float(dc) - DOOR_W / 2.0, float(dc) + DOOR_W / 2.0, DOOR_H, WALL_H))
			a = float(dc) + DOOR_W / 2.0
		out.append(_seg(w, a, float(w.b) + WALL_T / 2.0, 0.0, WALL_H))
	var cx := garden.get_center().x
	out.append([Vector3(_r(gx_far), 1.0, 0.0), Vector3(FENCE_T, 2.0, HALF_Z * 2.0)])
	out.append([Vector3(_r(cx), 1.0, -HALF_Z), Vector3(GARDEN_W, 2.0, FENCE_T)])
	out.append([Vector3(_r(cx), 1.0, HALF_Z), Vector3(GARDEN_W, 2.0, FENCE_T)])
	return out


static func _seg(w: Dictionary, a: float, b: float, y0: float, y1: float) -> Array:
	var mid := (a + b) / 2.0
	var c := Vector3(mid, (y0 + y1) / 2.0, float(w.at)) if int(w.axis) == 0 else Vector3(float(w.at), (y0 + y1) / 2.0, mid)
	var s := Vector3(b - a, y1 - y0, WALL_T) if int(w.axis) == 0 else Vector3(WALL_T, y1 - y0, b - a)
	return [Vector3(_r(c.x), _r(c.y), _r(c.z)), Vector3(_r(s.x), _r(s.y), _r(s.z))]


# --- The validator ---------------------------------------------------------------

## Walkable cells for a body of this radius / height (a cell is blocked when its centre is inside any
## collider grown by the radius: square corners, so a little stricter than the round capsule), flood-filled
## from the counting spot. Returns {x0, z0, nx, nz, free, seen, count}.
static func raster(g: Dictionary, radius: float, height: float) -> Dictionary:
	var b: Array = g.bounds
	var x0 := float(b[0])
	var z0 := float(b[2])
	var nx := ceili((float(b[1]) - x0) / CELL)
	var nz := ceili((float(b[3]) - z0) / CELL)
	var free := PackedByteArray()
	free.resize(nx * nz)
	free.fill(1)
	var jail: Vector3 = g.jail
	var bell: Vector3 = g.bell
	var all: Array = (g.solids as Array).duplicate()
	all.append([jail + Vector3(0, 0.75, 0), Vector3(JAIL_HALF * 2.0 + 0.06, 1.5, JAIL_HALF * 2.0 + 0.06)])
	all.append([bell + Vector3(0, 0.55, 0), Vector3(0.1, 1.1, 0.1)])
	for s in all:
		var c: Vector3 = s[0]
		var sz: Vector3 = s[1]
		if c.y - sz.y / 2.0 > height + 0.02 or c.y + sz.y / 2.0 < 0.02:
			continue
		var ex := sz.x / 2.0 + radius
		var ez := sz.z / 2.0 + radius
		var ix0 := maxi(0, ceili((c.x - ex - x0) / CELL - 0.5))
		var ix1 := mini(nx - 1, floori((c.x + ex - x0) / CELL - 0.5))
		var iz0 := maxi(0, ceili((c.z - ez - z0) / CELL - 0.5))
		var iz1 := mini(nz - 1, floori((c.z + ez - z0) / CELL - 0.5))
		for iz in range(iz0, iz1 + 1):
			var row := iz * nx
			for ix in range(ix0, ix1 + 1):
				free[row + ix] = 0
	var gr := {"x0": x0, "z0": z0, "nx": nx, "nz": nz, "free": free}
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var start := _cell(gr, (g.spawns as Array)[0])
	var count := 0
	if free[start] == 1:
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var ci: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var cx := ci % nx
			if cx > 0 and free[ci - 1] == 1 and seen[ci - 1] == 0:
				seen[ci - 1] = 1
				stack.append(ci - 1)
			if cx < nx - 1 and free[ci + 1] == 1 and seen[ci + 1] == 0:
				seen[ci + 1] = 1
				stack.append(ci + 1)
			if ci >= nx and free[ci - nx] == 1 and seen[ci - nx] == 0:
				seen[ci - nx] = 1
				stack.append(ci - nx)
			if ci + nx < nx * nz and free[ci + nx] == 1 and seen[ci + nx] == 0:
				seen[ci + nx] = 1
				stack.append(ci + nx)
	gr["seen"] = seen
	gr["count"] = count
	return gr


static func _cell(gr: Dictionary, p: Vector3) -> int:
	var ix := clampi(int((p.x - float(gr.x0)) / CELL), 0, int(gr.nx) - 1)
	var iz := clampi(int((p.z - float(gr.z0)) / CELL), 0, int(gr.nz) - 1)
	return iz * int(gr.nx) + ix


## Is a reachable cell centre within `dist` of p?
static func near(gr: Dictionary, p: Vector3, dist: float) -> bool:
	var nx := int(gr.nx)
	var nz := int(gr.nz)
	var x0 := float(gr.x0)
	var z0 := float(gr.z0)
	var seen: PackedByteArray = gr.seen
	var steps := ceili(dist / CELL) + 1
	var c := _cell(gr, p)
	for dz in range(-steps, steps + 1):
		var iz := c / nx + dz
		if iz < 0 or iz >= nz:
			continue
		for dx in range(-steps, steps + 1):
			var ix := c % nx + dx
			if ix < 0 or ix >= nx or seen[iz * nx + ix] == 0:
				continue
			if Vector2(x0 + (ix + 0.5) * CELL - p.x, z0 + (iz + 0.5) * CELL - p.z).length() <= dist:
				return true
	return false


## The validator: reasons this house is unfair or broken (empty when fine).
static func check(g: Dictionary) -> Array:
	var why: Array = []
	if not g.has("hide_spots"):
		return ["not finished"]
	var hg := raster(g, HIDER[0], HIDER[1])
	var sg := raster(g, SEEKER[0], SEEKER[1])
	var spawns: Array = g.spawns
	if int(sg.count) < 200:
		why.append("the seeker can't move from the counting spot")
	for i in range(1, spawns.size()):
		if not near(hg, spawns[i], 0.15):
			why.append("hider spawn %d is cut off" % i)
	for rm in g.rooms:
		if not near(hg, rm[1], 1.6) or not near(sg, rm[1], 1.6):
			why.append("can't walk to the %s" % rm[0])
	for d in g.doors:
		if not near(hg, d[1], 0.3) or not near(sg, d[1], 0.3):
			why.append("doorway %s is blocked" % d[0])
	var spots: Array = g.hide_spots
	if spots.size() < MIN_SPOTS:
		why.append("only %d hiding spots" % spots.size())
	for sp in spots:
		if not near(hg, sp, 0.25):
			why.append("a hider can't get to the hiding spot at %s" % str(sp))
		if not near(sg, sp, TOUCH):
			why.append("the seeker can't reach the hiding spot at %s" % str(sp))
	var stars: Array = g.star_spots
	if stars.size() < MIN_STARS:
		why.append("only %d star spots" % stars.size())
	for st in stars:
		if not near(hg, st, 0.3):
			why.append("star spot %s is cut off" % str(st))
	if not near(hg, g.bell, 0.9):
		why.append("nobody can ring the jail bell")
	if (g.decoys as Array).size() < 8:
		why.append("only %d decoys" % (g.decoys as Array).size())
	# Walled-off pockets (somewhere a hider could only jump into).
	var free: PackedByteArray = hg.free
	var seen: PackedByteArray = (hg.seen as PackedByteArray).duplicate()
	var nx := int(hg.nx)
	for i in free.size():
		if free[i] == 0 or seen[i] == 1:
			continue
		var size := 0
		var stack := PackedInt32Array([i])
		seen[i] = 1
		while not stack.is_empty():
			var ci: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			size += 1
			for k in [ci - 1, ci + 1, ci - nx, ci + nx]:
				if k >= 0 and k < free.size() and absi(k % nx - ci % nx) <= 1 and free[k] == 1 and seen[k] == 0:
					seen[k] = 1
					stack.append(k)
		if size >= 3:
			why.append("a walled-off pocket (%d cells) near (%.1f, %.1f)" % [size, float(hg.x0) + (i % nx + 0.5) * CELL, float(hg.z0) + (i / nx + 0.5) * CELL])
	var b: Array = g.bounds
	for s in g.solids:
		var c: Vector3 = s[0]
		if c.x < float(b[0]) - 0.2 or c.x > float(b[1]) + 0.2 or absf(c.z) > HALF_Z + 0.2:
			why.append("a solid outside the map at %s" % str(c))
	return why


## Map data for main.gd (same keys as the hand-made maps' data()).
static func data(g: Dictionary) -> Dictionary:
	return {"title": TITLE, "rooms": g.rooms, "doors": g.doors, "hide_spots": g.hide_spots, "star_spots": g.star_spots,
		"spawns": g.spawns, "jail": g.jail, "bell": g.bell, "bounds": g.bounds}
