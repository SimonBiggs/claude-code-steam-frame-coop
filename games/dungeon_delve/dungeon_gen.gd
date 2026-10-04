extends RefCounted
## DUNGEON DELVE floor generator: pure data, deterministic from (stage, seed), so the host and the TV
## machine build the same floor without sending it over the network.
##
## Layout: rooms are placed in a jittered 4x4 grid of cells (a connected cluster grown from the start
## cell), joined by a random spanning tree of neighbouring cells plus a couple of loops, and carved
## with 2-tile-wide corridors found by A* (with a turn penalty, so corridors are straight / L / Z
## shaped) that keep one tile away from every room except where they enter through a door.
## The exit room is a leaf behind a LOCKED gate; its key is in the deepest other room (a gold chest or
## a Key Goblin). An optional SECRET room hangs off a room behind a CRACKED wall. Pillars, pots,
## chests, decorations, torches, spike traps, a rolling boulder, a shrine and enemy spawns are placed
## too. validate() checks every floor (all rooms reachable, the gate really locks the exit, the key is
## reachable without it, no overlapping rooms); the bot runs it over hundreds of seeds.
## Boss floors are an antechamber and a big arena.
##
## The Layout also answers the game's spatial questions: tile <-> world, circle movement against
## walls (no physics engine needed, identical on both machines), line of sight and A* paths.

const Data := preload("res://games/dungeon_delve/data.gd")

const TILE := 1.5
const SOLID := 0
const ROOM := 1
const HALL := 2
const MAP := 52
const CELLS := 4
const CELL := 13
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


class Layout extends RefCounted:
	var w := MAP
	var h := MAP
	var stage := 1
	var seed_value := 0
	var theme := 0
	var kind := "floor"  # "floor" | "boss"
	var tiles := PackedByteArray()
	var room_of := PackedInt32Array()
	var block := PackedByteArray()  # dynamic blockers: locked gates, cracked walls (1 = blocked)
	## {id, rect: Rect2i, kind: "start"|"normal"|"exit"|"secret"|"shrine"|"arena"|"ante", cell, depth, pillars: Array[Vector2i]}
	var rooms: Array[Dictionary] = []
	## {id, room, side (0 E, 1 S, 2 W, 3 N), a, b (the two stub tiles just outside the room), kind:
	##  "open"|"locked"|"cracked", pos (Vector3 on the room boundary), out (outward normal), gate (Vector3
	##  where a gate is drawn), edge}
	var doors: Array[Dictionary] = []
	var edges: Array = []  # [room_a, room_b, door_a, door_b, path (Array[Vector2i] brush nodes)]
	var start_room := 0
	var exit_room := -1
	var secret_room := -1
	var shrine_room := -1
	var key_room := -1
	var key_mode := "chest"
	var chests: Array[Dictionary] = []  # {id, tile, pos (Vector3), room, kind: normal|gold|key|mimic, yaw}
	var pots := PackedVector3Array()
	var deco: Array = []  # [name, Vector3 pos, yaw, scale]
	var torches: Array = []  # [Vector3 wall point (y 0), Vector3 outward normal (into the room)]
	var lights: Array = []  # [Vector3 pos, Color, intensity, radius] baked light sources besides torches
	var traps: Array[Dictionary] = []  # {id, kind: "spikes"|"boulder", tiles | a, b, period, offset}
	var spawns := {}  # room id -> Array of [enemy id, Vector3]
	var stairs := Vector3.ZERO
	var start_pos := Vector3.ZERO
	var boss_pos := Vector3.ZERO
	var nav: AStarGrid2D

	# --- Tiles and world ----------------------------------------------------------------------

	func idx(x: int, y: int) -> int:
		return y * w + x

	func in_bounds(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h

	## Floor (room or corridor), ignoring dynamic blockers.
	func floor_at(x: int, y: int) -> bool:
		return in_bounds(x, y) and tiles[idx(x, y)] != SOLID

	## Walkable right now (floor and not blocked by a gate / cracked wall).
	func open(x: int, y: int) -> bool:
		if not in_bounds(x, y):
			return false
		var i := idx(x, y)
		return tiles[i] != SOLID and block[i] == 0

	func tile_of(p: Vector3) -> Vector2i:
		return Vector2i(int(floor(p.x / TILE)), int(floor(p.z / TILE)))

	func center(t: Vector2i) -> Vector3:
		return Vector3((t.x + 0.5) * TILE, 0.0, (t.y + 0.5) * TILE)

	func walkable_at(p: Vector3) -> bool:
		var t := tile_of(p)
		return open(t.x, t.y)

	## Room id at a world point (-1 = corridor or wall).
	func room_at(p: Vector3) -> int:
		var t := tile_of(p)
		if not in_bounds(t.x, t.y):
			return -1
		return room_of[idx(t.x, t.y)]

	## Room centre in world space.
	func room_center(r: int) -> Vector3:
		var rect: Rect2i = rooms[r]["rect"]
		return Vector3((rect.position.x + rect.size.x * 0.5) * TILE, 0.0, (rect.position.y + rect.size.y * 0.5) * TILE)

	## Room rectangle in world space (x/z).
	func room_rect_world(r: int) -> Rect2:
		var rect: Rect2i = rooms[r]["rect"]
		return Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE)

	## Is p inside room r, at least `inset` metres from its walls?
	func in_room(r: int, p: Vector3, inset: float = 0.0) -> bool:
		var rr := room_rect_world(r).grow(-inset)
		return rr.has_point(Vector2(p.x, p.z))

	# --- Movement against walls (circle vs solid tiles) -------------------------------------------

	## Move a circle of radius r from pos by motion, sliding along walls. y is kept.
	func move(pos: Vector3, motion: Vector3, r: float) -> Vector3:
		var steps := maxi(1, int(ceil(Vector2(motion.x, motion.z).length() / 0.3)))
		var p := pos
		var m := motion / float(steps)
		for s in steps:
			p.x += m.x
			p.z += m.z
			p = _push_out(p, r)
			p = _push_out(p, r)
		return p

	func _push_out(p: Vector3, r: float) -> Vector3:
		var t := tile_of(p)
		var out := p
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var tx := t.x + dx
				var ty := t.y + dy
				if open(tx, ty):
					continue
				var x0 := tx * TILE
				var z0 := ty * TILE
				var cx := clampf(out.x, x0, x0 + TILE)
				var cz := clampf(out.z, z0, z0 + TILE)
				var d := Vector2(out.x - cx, out.z - cz)
				var dl := d.length()
				if dl >= r:
					continue
				if dl > 0.0001:
					var push := d / dl * (r - dl)
					out.x += push.x
					out.z += push.y
				else:
					# centre inside the solid tile: leave by the nearest edge
					var exits: Array[float] = [out.x - x0, x0 + TILE - out.x, out.z - z0, z0 + TILE - out.z]
					var best := 0
					for k in 4:
						if exits[k] < exits[best]:
							best = k
					match best:
						0:
							out.x = x0 - r
						1:
							out.x = x0 + TILE + r
						2:
							out.z = z0 - r
						3:
							out.z = z0 + TILE + r
		return out

	## Can a circle of radius r stand at p?
	func fits(p: Vector3, r: float) -> bool:
		return _push_out(p, r).distance_squared_to(p) < 0.0001 and walkable_at(p)

	## Straight line of sight on the ground (sampled every 0.4 m).
	func los(a: Vector3, b: Vector3) -> bool:
		var d := Vector2(b.x - a.x, b.z - a.z)
		var n := maxi(1, int(d.length() / 0.4))
		for i in n + 1:
			var t := float(i) / float(n)
			var p := Vector3(a.x + d.x * t, 0.0, a.z + d.y * t)
			if not walkable_at(p):
				return false
		return true

	# --- Paths ---------------------------------------------------------------------------------

	## (Re)build the A* grid from the tiles and blockers.
	func build_nav() -> void:
		nav = AStarGrid2D.new()
		nav.region = Rect2i(0, 0, w, h)
		nav.cell_size = Vector2(TILE, TILE)
		nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		nav.update()
		for y in h:
			for x in w:
				nav.set_point_solid(Vector2i(x, y), not open(x, y))

	## A walking path (world points at tile centres) from a to b; empty if there is none.
	func path(a: Vector3, b: Vector3) -> PackedVector3Array:
		var out := PackedVector3Array()
		if nav == null:
			build_nav()
		var ta := tile_of(a)
		var tb := tile_of(b)
		if not open(ta.x, ta.y) or not open(tb.x, tb.y):
			return out
		var ids := nav.get_id_path(ta, tb)
		for t in ids:
			out.append(center(t))
		return out

	## Open or close the blockers of a door (gates, cracked walls).
	func set_door_blocked(door_id: int, on: bool) -> void:
		if door_id < 0 or door_id >= doors.size():
			return
		var d: Dictionary = doors[door_id]
		for k in ["a", "b"]:
			var t: Vector2i = d[k]
			block[idx(t.x, t.y)] = 1 if on else 0
			if nav != null:
				nav.set_point_solid(t, on or tiles[idx(t.x, t.y)] == SOLID)

	## Random walkable point inside room r (at least `inset` tiles from its walls), deterministic.
	func random_point_in_room(r: int, rng: RandomNumberGenerator, inset: int = 1) -> Vector3:
		var rect: Rect2i = rooms[r]["rect"]
		for i in 30:
			var t := Vector2i(rng.randi_range(rect.position.x + inset, rect.end.x - 1 - inset),
				rng.randi_range(rect.position.y + inset, rect.end.y - 1 - inset))
			if open(t.x, t.y):
				return center(t)
		return room_center(r)


# =================================================================================================
# Generation
# =================================================================================================

## Build the floor for `stage_n` (1-based, see data.gd) from the run seed.
static func generate(stage_n: int, seed_value: int) -> Layout:
	var st := Data.stage(stage_n)
	for attempt in 60:
		var lay: Layout = null
		if String(st["kind"]) == "boss":
			lay = _boss_floor(stage_n, seed_value, attempt, st)
		else:
			lay = _floor(stage_n, seed_value, attempt, st)
		if lay != null and validate(lay) == "":
			lay.build_nav()
			return lay
	push_warning("DungeonGen: stage %d seed %d needed the fallback layout" % [stage_n, seed_value])
	var fb := _boss_floor(stage_n, seed_value, 0, st)
	fb.build_nav()
	return fb


static func _rng_for(stage_n: int, seed_value: int, attempt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value * 1000003 + stage_n * 91711 + attempt * 7919 + 17) & 0x7FFFFFFFFFFF
	return rng


static func _new_layout(stage_n: int, seed_value: int, st: Dictionary) -> Layout:
	var lay := Layout.new()
	lay.stage = stage_n
	lay.seed_value = seed_value
	lay.theme = int(st["theme"])
	lay.tiles.resize(MAP * MAP)
	lay.tiles.fill(SOLID)
	lay.block.resize(MAP * MAP)
	lay.block.fill(0)
	lay.room_of.resize(MAP * MAP)
	lay.room_of.fill(-1)
	return lay


static func _add_room(lay: Layout, rect: Rect2i, kind: String, cell: Vector2i) -> int:
	var id := lay.rooms.size()
	lay.rooms.append({"id": id, "rect": rect, "kind": kind, "cell": cell, "depth": 0, "pillars": []})
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			lay.tiles[lay.idx(x, y)] = ROOM
			lay.room_of[lay.idx(x, y)] = id
	return id


static func _floor(stage_n: int, seed_value: int, attempt: int, st: Dictionary) -> Layout:
	var rng := _rng_for(stage_n, seed_value, attempt)
	var lay := _new_layout(stage_n, seed_value, st)
	var fl := int(st["floor"])
	var target := 7 + fl  # 8, 9, 10 rooms
	# 1. Grow a connected cluster of cells from a border cell.
	var start_cell := Vector2i(rng.randi_range(0, CELLS - 1), CELLS - 1 if rng.randf() < 0.5 else 0)
	var cells: Array[Vector2i] = [start_cell]
	var guard := 0
	while cells.size() < target and guard < 500:
		guard += 1
		var from: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var d: Vector2i = DIRS[rng.randi_range(0, 3)]
		var c := from + d
		if c.x < 0 or c.y < 0 or c.x >= CELLS or c.y >= CELLS or cells.has(c):
			continue
		cells.append(c)
	if cells.size() < target:
		return null
	# 2. Spanning tree over neighbouring cells (randomised Kruskal).
	var pairs: Array = []
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			var dd: Vector2i = cells[i] - cells[j]
			if absi(dd.x) + absi(dd.y) == 1:
				pairs.append([i, j, rng.randi()])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
	var parent: Array[int] = []
	for i in cells.size():
		parent.append(i)
	var tree: Array = []
	var spare: Array = []
	for p in pairs:
		var pa: Array = p
		var ra := _find(parent, int(pa[0]))
		var rb := _find(parent, int(pa[1]))
		if ra != rb:
			parent[ra] = rb
			tree.append([int(pa[0]), int(pa[1])])
		else:
			spare.append([int(pa[0]), int(pa[1])])
	# 3. Exit = the cell farthest from the start in the tree (always a leaf).
	var adj: Array = []
	for i in cells.size():
		adj.append([])
	for e in tree:
		var ea: Array = e
		(adj[int(ea[0])] as Array).append(int(ea[1]))
		(adj[int(ea[1])] as Array).append(int(ea[0]))
	var depth := _bfs_depth(adj, 0)
	var exit_i := 0
	for i in cells.size():
		if depth[i] > depth[exit_i]:
			exit_i = i
	if exit_i == 0 or (adj[exit_i] as Array).size() != 1:
		return null
	# 4. Rooms inside their cells.
	for i in cells.size():
		var c: Vector2i = cells[i]
		var rw := 7 if i == 0 else rng.randi_range(6, 9)
		var rh := 7 if i == 0 else rng.randi_range(6, 9)
		if i == exit_i:
			rw = rng.randi_range(6, 7)
			rh = rng.randi_range(6, 7)
		var x := c.x * CELL + rng.randi_range(2, CELL - rw - 2)
		var y := c.y * CELL + rng.randi_range(2, CELL - rh - 2)
		var kind := "start" if i == 0 else ("exit" if i == exit_i else "normal")
		_add_room(lay, Rect2i(x, y, rw, rh), kind, c)
		lay.rooms[i]["depth"] = depth[i]
	lay.start_room = 0
	lay.exit_room = exit_i
	# 5. Loops: up to 2 spare neighbour pairs that don't touch the exit.
	var loops := 0
	for p in spare:
		var pa: Array = p
		if loops >= 2 or int(pa[0]) == exit_i or int(pa[1]) == exit_i:
			continue
		if rng.randf() < 0.45:
			tree.append(pa)
			loops += 1
	# 6. Secret room in a free neighbouring cell of a normal room (not start / exit).
	var secret_parent := -1
	var secret_cell := Vector2i(-1, -1)
	if rng.randf() < 0.7:
		var order: Array[int] = []
		for i in cells.size():
			order.append(i)
		_shuffle(order, rng)
		for i in order:
			if i == 0 or i == exit_i or secret_parent >= 0:
				continue
			var dirs: Array[Vector2i] = DIRS.duplicate()
			_shuffle_v(dirs, rng)
			for d in dirs:
				var c: Vector2i = cells[i] + d
				if c.x >= 0 and c.y >= 0 and c.x < CELLS and c.y < CELLS and not cells.has(c):
					secret_parent = i
					secret_cell = c
					break
	if secret_parent >= 0:
		var sw := 5
		var sh := 5
		var sx := secret_cell.x * CELL + rng.randi_range(3, CELL - sw - 3)
		var sy := secret_cell.y * CELL + rng.randi_range(3, CELL - sh - 3)
		lay.secret_room = _add_room(lay, Rect2i(sx, sy, sw, sh), "secret", secret_cell)
		tree.append([secret_parent, lay.secret_room])
	# 7. Corridors.
	var reserved := _reserved(lay)
	for e in tree:
		var ea: Array = e
		if not _connect(lay, int(ea[0]), int(ea[1]), reserved, rng):
			return null
	# Door kinds.
	for d in lay.doors:
		var dd: Dictionary = d
		if int(dd["room"]) == lay.exit_room:
			dd["kind"] = "locked"
		if lay.secret_room >= 0:
			var e: Array = lay.edges[int(dd["edge"])]
			if int(e[1]) == lay.secret_room and int(dd["room"]) == int(e[0]):
				dd["kind"] = "cracked"
	for d in lay.doors:
		var dd: Dictionary = d
		if String(dd["kind"]) != "open":
			lay.set_door_blocked(int(dd["id"]), true)
	# 8. Room roles.
	var normals: Array[int] = []
	for r in lay.rooms:
		if String(r["kind"]) == "normal":
			normals.append(int(r["id"]))
	if normals.size() < 3:
		return null
	# Key: the deepest normal room.
	var key_room := normals[0]
	for r in normals:
		if int(lay.rooms[r]["depth"]) > int(lay.rooms[key_room]["depth"]):
			key_room = r
	lay.key_room = key_room
	lay.key_mode = "keeper" if rng.randf() < 0.45 else "chest"
	# Shrine: always on the second floor of a theme, sometimes elsewhere.
	if fl == 2 or rng.randf() < 0.3:
		var cands: Array[int] = []
		for r in normals:
			if r != key_room:
				cands.append(r)
		if not cands.is_empty():
			lay.shrine_room = cands[rng.randi_range(0, cands.size() - 1)]
			lay.rooms[lay.shrine_room]["kind"] = "shrine"
	# 9. Pillars in big normal rooms.
	for r in normals:
		var rect: Rect2i = lay.rooms[r]["rect"]
		if r == lay.shrine_room or rect.size.x < 8 or rect.size.y < 8 or rng.randf() < 0.45:
			continue
		var pil: Array = []
		for p in [Vector2i(2, 2), Vector2i(rect.size.x - 3, 2), Vector2i(2, rect.size.y - 3), Vector2i(rect.size.x - 3, rect.size.y - 3)]:
			var pv: Vector2i = p
			var t := rect.position + pv
			lay.tiles[lay.idx(t.x, t.y)] = SOLID
			lay.room_of[lay.idx(t.x, t.y)] = -1
			pil.append(t)
		lay.rooms[r]["pillars"] = pil
	_place_contents(lay, rng, st)
	return lay


static func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _bfs_depth(adj: Array, from: int) -> Array[int]:
	var depth: Array[int] = []
	for i in adj.size():
		depth.append(-1)
	depth[from] = 0
	var q: Array[int] = [from]
	while not q.is_empty():
		var c: int = q.pop_front()
		for n in adj[c]:
			if depth[int(n)] < 0:
				depth[int(n)] = depth[c] + 1
				q.append(int(n))
	return depth


static func _shuffle(a: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


static func _shuffle_v(a: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


## Tiles corridors may not use: every room plus a one-tile margin.
static func _reserved(lay: Layout) -> PackedByteArray:
	var res := PackedByteArray()
	res.resize(MAP * MAP)
	res.fill(0)
	for r in lay.rooms:
		var rect: Rect2i = (r["rect"] as Rect2i).grow(1)
		for y in range(maxi(0, rect.position.y), mini(MAP, rect.end.y)):
			for x in range(maxi(0, rect.position.x), mini(MAP, rect.end.x)):
				res[y * MAP + x] = 1
	return res


## Door slot on room `r` facing `toward` (a world-ish tile point). Returns [side, stub brush top-left].
static func _door_slot(lay: Layout, r: int, toward: Vector2, rng: RandomNumberGenerator) -> Array:
	var rect: Rect2i = lay.rooms[r]["rect"]
	var c := Vector2(rect.position) + Vector2(rect.size) * 0.5
	var d := toward - c
	var side := 0
	if absf(d.x) * float(rect.size.y) >= absf(d.y) * float(rect.size.x):
		side = 0 if d.x > 0.0 else 2
	else:
		side = 1 if d.y > 0.0 else 3
	var stub := Vector2i.ZERO
	match side:
		0:
			stub = Vector2i(rect.end.x, rng.randi_range(rect.position.y + 1, rect.end.y - 3))
		2:
			stub = Vector2i(rect.position.x - 2, rng.randi_range(rect.position.y + 1, rect.end.y - 3))
		1:
			stub = Vector2i(rng.randi_range(rect.position.x + 1, rect.end.x - 3), rect.end.y)
		3:
			stub = Vector2i(rng.randi_range(rect.position.x + 1, rect.end.x - 3), rect.position.y - 2)
	return [side, stub]


## Carve a corridor between rooms a and b (A* over 2x2 brush positions). Adds both doors.
static func _connect(lay: Layout, a: int, b: int, reserved: PackedByteArray, rng: RandomNumberGenerator) -> bool:
	var ra: Rect2i = lay.rooms[a]["rect"]
	var rb: Rect2i = lay.rooms[b]["rect"]
	var ca := Vector2(ra.position) + Vector2(ra.size) * 0.5
	var cb := Vector2(rb.position) + Vector2(rb.size) * 0.5
	var sa := _door_slot(lay, a, cb, rng)
	var sb := _door_slot(lay, b, ca, rng)
	var start: Vector2i = sa[1]
	var goal: Vector2i = sb[1]
	var path := _astar(lay, start, int(sa[0]), goal, reserved)
	if path.is_empty():
		return false
	var edge_i := lay.edges.size()
	for n in path:
		for dy in 2:
			for dx in 2:
				var t := n + Vector2i(dx, dy)
				if lay.tiles[lay.idx(t.x, t.y)] == SOLID:
					lay.tiles[lay.idx(t.x, t.y)] = HALL
	var da := _make_door(lay, a, int(sa[0]), start, edge_i)
	var db := _make_door(lay, b, int(sb[0]), goal, edge_i)
	lay.edges.append([a, b, da, db, path])
	return true


static func _make_door(lay: Layout, r: int, side: int, brush: Vector2i, edge_i: int) -> int:
	var rect: Rect2i = lay.rooms[r]["rect"]
	var t1 := Vector2i.ZERO
	var t2 := Vector2i.ZERO
	var pos := Vector3.ZERO
	var out := Vector3.ZERO
	match side:
		0:
			t1 = Vector2i(rect.end.x, brush.y)
			t2 = Vector2i(rect.end.x, brush.y + 1)
			pos = Vector3(rect.end.x * TILE, 0.0, (brush.y + 1) * TILE)
			out = Vector3(1, 0, 0)
		2:
			t1 = Vector2i(rect.position.x - 1, brush.y)
			t2 = Vector2i(rect.position.x - 1, brush.y + 1)
			pos = Vector3(rect.position.x * TILE, 0.0, (brush.y + 1) * TILE)
			out = Vector3(-1, 0, 0)
		1:
			t1 = Vector2i(brush.x, rect.end.y)
			t2 = Vector2i(brush.x + 1, rect.end.y)
			pos = Vector3((brush.x + 1) * TILE, 0.0, rect.end.y * TILE)
			out = Vector3(0, 0, 1)
		3:
			t1 = Vector2i(brush.x, rect.position.y - 1)
			t2 = Vector2i(brush.x + 1, rect.position.y - 1)
			pos = Vector3((brush.x + 1) * TILE, 0.0, rect.position.y * TILE)
			out = Vector3(0, 0, -1)
	var id := lay.doors.size()
	lay.doors.append({"id": id, "room": r, "side": side, "a": t1, "b": t2, "kind": "open", "pos": pos, "out": out,
		"gate": pos + out * TILE, "edge": edge_i})
	return id


## A* over brush positions with a turn penalty; corridors may reuse each other cheaply.
static func _astar(lay: Layout, start: Vector2i, start_side: int, goal: Vector2i, reserved: PackedByteArray) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := MAP - 1  # brush positions per axis
	var total := n * n * 4
	var cost := PackedInt32Array()
	cost.resize(total)
	cost.fill(0x3FFFFFFF)
	var prev := PackedInt32Array()
	prev.resize(total)
	prev.fill(-1)
	var heap := PackedInt64Array()
	var s0 := (start.y * n + start.x) * 4 + start_side
	cost[s0] = 0
	_heap_push(heap, s0)
	var found := -1
	var pops := 0
	while not heap.is_empty() and pops < 60000:
		pops += 1
		var top := _heap_pop(heap)
		var g := int(top >> 24)
		var s := int(top & 0xFFFFFF)
		if g > cost[s] + _h(s, n, goal):
			continue
		var node := s >> 2
		var dir := s & 3
		var nx := node % n
		var ny := node / n
		if nx == goal.x and ny == goal.y:
			found = s
			break
		for k in 4:
			var d: Vector2i = DIRS[k]
			var px := nx + d.x
			var py := ny + d.y
			if px < 1 or py < 1 or px >= n - 1 or py >= n - 1:
				continue
			var is_goal := px == goal.x and py == goal.y
			if not is_goal and not _brush_free(lay, px, py, reserved):
				continue
			var step := 10
			if lay.tiles[lay.idx(px, py)] == HALL and lay.tiles[lay.idx(px + 1, py + 1)] == HALL:
				step = 6
			if k != dir:
				step += 14
			var ns := (py * n + px) * 4 + k
			var ng := cost[s] + step
			if ng < cost[ns]:
				cost[ns] = ng
				prev[ns] = s
				_heap_push(heap, (int(ng + _h(ns, n, goal)) << 24) | ns)
	if found < 0:
		return out
	var cur := found
	while cur >= 0:
		var node := cur >> 2
		out.push_front(Vector2i(node % n, node / n))
		cur = prev[cur]
	return out


static func _h(s: int, n: int, goal: Vector2i) -> int:
	var node := s >> 2
	return (absi(node % n - goal.x) + absi(node / n - goal.y)) * 6


static func _brush_free(lay: Layout, x: int, y: int, reserved: PackedByteArray) -> bool:
	for dy in 2:
		for dx in 2:
			var i := (y + dy) * MAP + x + dx
			if reserved[i] != 0:
				return false
	return true


static func _heap_push(heap: PackedInt64Array, v: int) -> void:
	heap.append(v)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[p] <= heap[i]:
			break
		var t := heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p


static func _heap_pop(heap: PackedInt64Array) -> int:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var size := heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < size and heap[l] < heap[m]:
			m = l
		if r < size and heap[r] < heap[m]:
			m = r
		if m == i:
			break
		var t := heap[m]
		heap[m] = heap[i]
		heap[i] = t
		i = m
	return top


# --- Contents ------------------------------------------------------------------------------------

## Tiles just inside a room in front of its doors (kept clear of pots, chests, traps and spawns).
static func _door_approach(lay: Layout, r: int) -> Dictionary:
	var out := {}
	for d in lay.doors:
		var dd: Dictionary = d
		if int(dd["room"]) != r:
			continue
		var o: Vector3 = dd["out"]
		var inward := Vector2i(-int(o.x), -int(o.z))
		for k in ["a", "b"]:
			var t: Vector2i = dd[k]
			for step in range(1, 4):
				out[t + inward * step] = true
				out[t + inward * step + Vector2i(inward.y, inward.x)] = true
				out[t + inward * step - Vector2i(inward.y, inward.x)] = true
	return out


static func _place_contents(lay: Layout, rng: RandomNumberGenerator, st: Dictionary) -> void:
	var theme: Dictionary = Data.THEMES[lay.theme]
	var fl := int(st["floor"])
	var depth := int(st["depth"])
	lay.start_pos = lay.room_center(lay.start_room)
	lay.stairs = lay.room_center(lay.exit_room)
	var used := {}  # tiles taken by contents
	used[lay.tile_of(lay.stairs)] = true
	used[lay.tile_of(lay.stairs) + Vector2i(-1, 0)] = true
	used[lay.tile_of(lay.stairs) + Vector2i(0, -1)] = true
	used[lay.tile_of(lay.stairs) + Vector2i(-1, -1)] = true
	used[lay.tile_of(lay.start_pos)] = true
	var chest_id := 0
	# Chests: key chest, 1-2 normal (maybe a mimic), the secret room's gold chest.
	var chest_rooms: Array[int] = []
	if lay.key_mode == "chest":
		chest_rooms.append(lay.key_room)
	var normals: Array[int] = []
	for r in lay.rooms:
		var k := String(r["kind"])
		if k == "normal" or k == "shrine":
			normals.append(int(r["id"]))
	var extra := 1 + (1 if rng.randf() < 0.5 else 0)
	for i in extra:
		chest_rooms.append(normals[rng.randi_range(0, normals.size() - 1)])
	if lay.secret_room >= 0:
		chest_rooms.append(lay.secret_room)
	var mimic_done := false
	for ci in chest_rooms.size():
		var r: int = chest_rooms[ci]
		var t := _wall_tile(lay, r, rng, used)
		if t.x < 0:
			continue
		used[t] = true
		var kind := "normal"
		if r == lay.secret_room:
			kind = "gold"
		elif ci == 0 and lay.key_mode == "chest":
			kind = "key"
		elif lay.theme >= 1 and not mimic_done and rng.randf() < 0.3:
			kind = "mimic"
			mimic_done = true
		var c := lay.room_center(r)
		var p := lay.center(t)
		lay.chests.append({"id": chest_id, "tile": t, "pos": p, "room": r, "kind": kind,
			"yaw": atan2(c.x - p.x, c.z - p.z)})
		chest_id += 1
	# Pots: clusters in corners and along walls.
	for r in lay.rooms:
		var rid := int(r["id"])
		var n := 2 if String(r["kind"]) == "start" else rng.randi_range(1, 3)
		for i in n:
			var t := _wall_tile(lay, rid, rng, used)
			if t.x < 0:
				continue
			used[t] = true
			var base := lay.center(t)
			for k in rng.randi_range(2, 3):
				var jitter := Vector3(rng.randf_range(-0.45, 0.45), 0.0, rng.randf_range(-0.45, 0.45))
				lay.pots.append(base + jitter)
	# Spike traps (from the second floor) in up to two rooms.
	var trap_id := 0
	if depth >= 2:
		var tries := 0
		var count := 1 + (1 if depth >= 5 else 0)
		while trap_id < count and tries < 20:
			tries += 1
			var r: int = normals[rng.randi_range(0, normals.size() - 1)]
			if r == lay.shrine_room or r == lay.key_room:
				continue
			var rect: Rect2i = lay.rooms[r]["rect"]
			var appr := _door_approach(lay, r)
			var o := Vector2i(rng.randi_range(rect.position.x + 2, rect.end.x - 4), rng.randi_range(rect.position.y + 2, rect.end.y - 4))
			var ts: Array = []
			var ok := true
			var wide := rng.randf() < 0.5
			for dy in (1 if wide else 2):
				for dx in (3 if wide else 2):
					var t := o + Vector2i(dx, dy)
					if not lay.floor_at(t.x, t.y) or used.has(t) or appr.has(t) or lay.room_of[lay.idx(t.x, t.y)] != r:
						ok = false
					ts.append(t)
			if not ok:
				continue
			for t in ts:
				used[t] = true
			lay.traps.append({"id": trap_id, "kind": "spikes", "tiles": ts, "room": r, "period": 3.2,
				"offset": rng.randf_range(0.0, 3.2)})
			trap_id += 1
	# Rolling boulder (from the third floor): down a long straight corridor run, else across the
	# middle of a big room from wall to wall.
	if depth >= 3:
		var placed := false
		for e in lay.edges:
			var ea: Array = e
			if int(ea[1]) == lay.secret_room or int(ea[0]) == lay.exit_room or int(ea[1]) == lay.exit_room:
				continue
			var run := _longest_run(ea[4])
			if run.size() < 2:
				continue
			var a: Vector2i = run[0]
			var b: Vector2i = run[1]
			if (b - a).length() < 5:
				continue
			var pa := Vector3((a.x + 1) * TILE, 0.0, (a.y + 1) * TILE)
			var pb := Vector3((b.x + 1) * TILE, 0.0, (b.y + 1) * TILE)
			lay.traps.append({"id": trap_id, "kind": "boulder", "a": pa, "b": pb, "period": 7.0,
				"offset": rng.randf_range(0.0, 7.0)})
			trap_id += 1
			placed = true
			break
		if not placed:
			for r in normals:
				var rect: Rect2i = lay.rooms[r]["rect"]
				if r == lay.key_room or r == lay.shrine_room or maxi(rect.size.x, rect.size.y) < 8:
					continue
				var c := lay.room_center(r)
				var pa := Vector3.ZERO
				var pb := Vector3.ZERO
				if rect.size.x >= rect.size.y:
					pa = Vector3((rect.position.x + 0.9) * TILE, 0.0, c.z)
					pb = Vector3((rect.end.x - 0.9) * TILE, 0.0, c.z)
				else:
					pa = Vector3(c.x, 0.0, (rect.position.y + 0.9) * TILE)
					pb = Vector3(c.x, 0.0, (rect.end.y - 0.9) * TILE)
				lay.traps.append({"id": trap_id, "kind": "boulder", "a": pa, "b": pb, "period": 7.0,
					"offset": rng.randf_range(0.0, 7.0)})
				trap_id += 1
				break
	# Enemy spawns.
	var ids: Array = theme["enemies"]
	for r in lay.rooms:
		var rid := int(r["id"])
		var k := String(r["kind"])
		if k == "start" or k == "exit":
			continue
		var rect: Rect2i = r["rect"]
		var n := clampi(2 + (rect.size.x * rect.size.y) / 22 + (fl - 1) / 2, 2, 6)
		if k == "secret":
			n = 2
		if k == "shrine":
			n = maxi(2, n - 1)
		var appr := _door_approach(lay, rid)
		var list: Array = []
		var ranged := 0
		for i in n:
			var eid := String(ids[rng.randi_range(0, ids.size() - 1)])
			var e: Dictionary = Data.ENEMIES[eid]
			if String(e["ai"]) == "ranged":
				ranged += 1
				if ranged > maxi(1, n / 3):
					eid = String(ids[0])
			var p := Vector3.ZERO
			for attempt in 20:
				var t := Vector2i(rng.randi_range(rect.position.x + 1, rect.end.x - 2), rng.randi_range(rect.position.y + 1, rect.end.y - 2))
				if lay.open(t.x, t.y) and not appr.has(t) and not used.has(t):
					p = lay.center(t) + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
					break
			if p != Vector3.ZERO:
				list.append([eid, p])
		if rid == lay.key_room and lay.key_mode == "keeper":
			list.append(["key_goblin", lay.room_center(rid)])
		lay.spawns[rid] = list
	# Torches along room walls and some corridors, decoration.
	_place_torches(lay, rng)
	_place_deco(lay, rng, theme, used)


static func _longest_run(path: Array) -> Array:
	var best: Array = []
	var best_len := 0.0
	var i := 0
	while i < path.size() - 1:
		var a: Vector2i = path[i]
		var nxt: Vector2i = path[i + 1]
		var d: Vector2i = nxt - a
		var j := i + 1
		while j < path.size() - 1:
			var pj: Vector2i = path[j]
			var pk: Vector2i = path[j + 1]
			if pk - pj != d:
				break
			j += 1
		var b: Vector2i = path[j]
		if best.is_empty() or (b - a).length() > best_len:
			best = [a, b]
			best_len = (b - a).length()
		i = j
	# keep a tile clear of both ends (doors)
	if not best.is_empty():
		var a: Vector2i = best[0]
		var b: Vector2i = best[1]
		var d := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		best = [a + d, b - d]
	return best


## A free tile against a wall of room r (not in front of a door), or (-1, -1).
static func _wall_tile(lay: Layout, r: int, rng: RandomNumberGenerator, used: Dictionary) -> Vector2i:
	var rect: Rect2i = lay.rooms[r]["rect"]
	var appr := _door_approach(lay, r)
	for i in 40:
		var t := Vector2i.ZERO
		match rng.randi_range(0, 3):
			0:
				t = Vector2i(rect.position.x, rng.randi_range(rect.position.y, rect.end.y - 1))
			1:
				t = Vector2i(rect.end.x - 1, rng.randi_range(rect.position.y, rect.end.y - 1))
			2:
				t = Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rect.position.y)
			3:
				t = Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rect.end.y - 1)
		if lay.open(t.x, t.y) and not used.has(t) and not appr.has(t):
			return t
	return Vector2i(-1, -1)


static func _place_torches(lay: Layout, rng: RandomNumberGenerator) -> void:
	# Room walls: every 3rd wall tile face that looks into the room.
	for r in lay.rooms:
		var rect: Rect2i = r["rect"]
		var faces: Array = []
		for x in range(rect.position.x, rect.end.x):
			faces.append([Vector2i(x, rect.position.y), Vector2i(0, -1)])
			faces.append([Vector2i(x, rect.end.y - 1), Vector2i(0, 1)])
		for y in range(rect.position.y, rect.end.y):
			faces.append([Vector2i(rect.position.x, y), Vector2i(-1, 0)])
			faces.append([Vector2i(rect.end.x - 1, y), Vector2i(1, 0)])
		var k := rng.randi_range(0, 2)
		for f in faces:
			var fa: Array = f
			var t: Vector2i = fa[0]
			var d: Vector2i = fa[1]
			k += 1
			if k % 4 != 0:
				continue
			var behind := t + d
			if lay.floor_at(behind.x, behind.y):
				continue
			var c := lay.center(t)
			var wall := c + Vector3(d.x, 0, d.y) * TILE * 0.5
			lay.torches.append([wall, Vector3(-d.x, 0, -d.y)])
	# Corridors: a torch every ~7 brush steps where a wall is beside the path.
	for e in lay.edges:
		var ea: Array = e
		var path: Array = ea[4]
		for i in range(4, path.size() - 4, 7):
			var n: Vector2i = path[i]
			var t := n
			for d in [Vector2i(-1, 0), Vector2i(0, -1)]:
				var dv: Vector2i = d
				var behind := t + dv
				if not lay.floor_at(behind.x, behind.y) and lay.floor_at(t.x, t.y):
					var c := lay.center(t)
					lay.torches.append([c + Vector3(dv.x, 0, dv.y) * TILE * 0.5, Vector3(-dv.x, 0, -dv.y)])
					break


static func _place_deco(lay: Layout, rng: RandomNumberGenerator, theme: Dictionary, used: Dictionary) -> void:
	var style := String(theme["deco"])
	var kinds: Array[String] = []
	match style:
		"moss":
			kinds = ["mushroom", "bones", "rock", "candle", "grave"]
		"crystal":
			kinds = ["crystal", "rock", "crate", "barrel", "crystal"]
		"lava":
			kinds = ["anvil", "rock", "barrel", "lava", "crate"]
		"ice":
			kinds = ["ice", "snow", "rock", "ice", "snow"]
		"gold":
			kinds = ["coins", "gem", "barrel", "coins", "crate"]
	for r in lay.rooms:
		var rid := int(r["id"])
		var n := rng.randi_range(3, 6)
		for i in n:
			var t := _wall_tile(lay, rid, rng, used)
			if t.x < 0:
				continue
			used[t] = true
			var p := lay.center(t) + Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
			var kind := kinds[rng.randi_range(0, kinds.size() - 1)]
			lay.deco.append([kind, p, rng.randf() * TAU, rng.randf_range(0.8, 1.25)])
			if kind == "crystal" or kind == "lava" or kind == "ice" or kind == "coins":
				var col: Color = theme["glow"]
				lay.lights.append([p + Vector3.UP * 0.6, col, 0.55, 5.0])
	if lay.shrine_room >= 0:
		lay.lights.append([lay.room_center(lay.shrine_room) + Vector3.UP, Color(1.0, 0.9, 0.55), 0.8, 7.0])
	lay.lights.append([lay.stairs + Vector3.UP * 0.5, Color(0.55, 0.8, 1.0), 0.6, 5.0])


# --- Boss floors ---------------------------------------------------------------------------------

static func _boss_floor(stage_n: int, seed_value: int, attempt: int, st: Dictionary) -> Layout:
	var rng := _rng_for(stage_n, seed_value, attempt)
	var lay := _new_layout(stage_n, seed_value, st)
	lay.kind = "boss"
	var ante := _add_room(lay, Rect2i(22, 38, 8, 7), "ante", Vector2i(1, 3))
	var arena := _add_room(lay, Rect2i(16, 10, 20, 20), "arena", Vector2i(1, 1))
	lay.start_room = ante
	lay.exit_room = arena
	var reserved := _reserved(lay)
	if not _connect(lay, ante, arena, reserved, rng):
		return null
	lay.start_pos = lay.room_center(ante)
	lay.stairs = lay.room_center(arena) + Vector3(0.0, 0.0, -4.5)
	lay.boss_pos = lay.room_center(arena) + Vector3(0.0, 0.0, -2.0)
	var used := {}
	for r in [ante, arena]:
		for i in 3:
			var t := _wall_tile(lay, r, rng, used)
			if t.x < 0:
				continue
			used[t] = true
			for k in 2:
				lay.pots.append(lay.center(t) + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)))
	lay.spawns[arena] = []
	_place_torches(lay, rng)
	var theme: Dictionary = Data.THEMES[lay.theme]
	_place_deco(lay, rng, theme, used)
	lay.lights.append([lay.room_center(arena) + Vector3.UP * 2.0, theme["glow"], 0.5, 12.0])
	return lay


# =================================================================================================
# Validation
# =================================================================================================

## "" when the floor is good, else what is wrong. Checks: rooms don't overlap; every floor tile is
## reachable from the start when gates/cracked walls are open; with them closed, the key, every
## normal room and the stairs path up to the gate are reachable, while the exit and secret rooms are
## not (the gate and the crack really guard them); contents stand on walkable floor.
static func validate(lay: Layout) -> String:
	for i in lay.rooms.size():
		for j in range(i + 1, lay.rooms.size()):
			var a: Rect2i = lay.rooms[i]["rect"]
			var b: Rect2i = lay.rooms[j]["rect"]
			if a.grow(1).intersects(b):
				return "rooms %d and %d overlap" % [i, j]
	var start := lay.tile_of(lay.start_pos)
	if not lay.floor_at(start.x, start.y):
		return "start is not on the floor"
	# Everything reachable with every door open.
	var all_open := _flood(lay, start, false)
	var floor_tiles := 0
	for y in lay.h:
		for x in lay.w:
			if lay.floor_at(x, y):
				floor_tiles += 1
				if all_open[lay.idx(x, y)] == 0:
					return "tile %d,%d (room %d) is cut off" % [x, y, lay.room_of[lay.idx(x, y)]]
	var st := lay.tile_of(lay.stairs)
	if all_open[lay.idx(st.x, st.y)] == 0:
		return "stairs unreachable"
	if lay.kind == "boss":
		return ""
	# With gates locked: key reachable, exit and secret not.
	var locked := _flood(lay, start, true)
	if locked[lay.idx(st.x, st.y)] != 0:
		return "the exit is reachable without the key"
	for r in lay.rooms:
		var rid := int(r["id"])
		var c := lay.tile_of(lay.room_center(rid))
		var reach := false
		var rect: Rect2i = r["rect"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if locked[lay.idx(x, y)] != 0:
					reach = true
		var k := String(r["kind"])
		if (k == "exit" or k == "secret") and reach:
			return "room %d (%s) is not guarded" % [rid, k]
		if k != "exit" and k != "secret" and not reach:
			return "room %d (%s) unreachable without breaking walls" % [rid, k]
		if c.x < 0:
			return "bad room"
	var key_ok := false
	if lay.key_mode == "chest":
		for ch in lay.chests:
			if String(ch["kind"]) == "key":
				var t: Vector2i = ch["tile"]
				key_ok = locked[lay.idx(t.x, t.y)] != 0
	else:
		var kc := lay.tile_of(lay.room_center(lay.key_room))
		key_ok = locked[lay.idx(kc.x, kc.y)] != 0
	if not key_ok:
		return "the key is not reachable"
	for ch in lay.chests:
		var t: Vector2i = ch["tile"]
		if not lay.floor_at(t.x, t.y):
			return "chest in a wall"
	for p in lay.pots:
		if not lay.floor_at(lay.tile_of(p).x, lay.tile_of(p).y):
			return "pot in a wall"
	for rid in lay.spawns:
		for s in lay.spawns[rid]:
			var sp: Array = s
			var p: Vector3 = sp[1]
			if not lay.floor_at(lay.tile_of(p).x, lay.tile_of(p).y):
				return "spawn in a wall"
	return ""


## Flood fill from a tile. blocked = respect gates / cracked walls.
static func _flood(lay: Layout, from: Vector2i, blocked: bool) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(lay.w * lay.h)
	seen.fill(0)
	var q: Array[Vector2i] = [from]
	seen[lay.idx(from.x, from.y)] = 1
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if not lay.in_bounds(n.x, n.y) or seen[lay.idx(n.x, n.y)] != 0:
				continue
			var ok := lay.open(n.x, n.y) if blocked else lay.floor_at(n.x, n.y)
			if ok:
				seen[lay.idx(n.x, n.y)] = 1
				q.append(n)
	return seen
