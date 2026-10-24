extends RefCounted
## The town board: terrain, trees, roads / rails and buildings on the GRID x GRID island, plus the
## rules for where things may go, road shapes and path finding (AStarGrid2D) for the AI drivers.
## Every machine has one: the host changes it (sim.gd, main.gd) and publishes it through the net
## state store; the TV machine rebuilds its copy from the same keys (main.gd _on_state_changed).

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const N := Defs.GRID
## Building record field order in the packed form (net store keys "b<id>" and saves).
const PACK: Array[String] = ["kind", "x", "z", "rot", "stage", "mats", "need", "fire", "lvl", "res", "work",
	"food", "bread", "wood", "needs", "happy", "wait"]

var island := 0
var ter := PackedByteArray()  ## Defs.T_* per cell
var trees := PackedByteArray()  ## 0 = none, 1..3 = that many trees on the cell
var lay := PackedByteArray()  ## Defs.L_* per cell
var owner_id := PackedInt32Array()  ## building id covering the cell (0 = none)
var buildings := {}  ## id -> Dictionary (see PACK; "kind" is a String here)
var next_id := 1
## Bumped on every change: views compare it to know when to rebuild.
var version := 0
var lay_version := 0
var tree_version := 0

var _astar: AStarGrid2D
var _astar_version := -1


func _init() -> void:
	clear()


func clear() -> void:
	ter.resize(N * N)
	ter.fill(Defs.T_WATER)
	trees.resize(N * N)
	trees.fill(0)
	lay.resize(N * N)
	lay.fill(Defs.L_NONE)
	owner_id.resize(N * N)
	owner_id.fill(0)
	buildings.clear()
	next_id = 1
	_touch(true, true)


func _touch(layer: bool = false, tree: bool = false) -> void:
	version += 1
	if layer:
		lay_version += 1
	if tree:
		tree_version += 1


static func idx(x: int, z: int) -> int:
	return z * N + x


func inside(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < N and z < N


func terrain(x: int, z: int) -> int:
	return int(ter[idx(x, z)]) if inside(x, z) else Defs.T_WATER


func layer(x: int, z: int) -> int:
	return int(lay[idx(x, z)]) if inside(x, z) else Defs.L_NONE


func is_land(x: int, z: int) -> bool:
	var t := terrain(x, z)
	return t == Defs.T_GRASS or t == Defs.T_SAND


func has_road(x: int, z: int) -> bool:
	var l := layer(x, z)
	return l == Defs.L_ROAD or l == Defs.L_CROSS


func has_rail(x: int, z: int) -> bool:
	var l := layer(x, z)
	return l == Defs.L_RAIL or l == Defs.L_CROSS


func building_at(x: int, z: int) -> Dictionary:
	if not inside(x, z):
		return {}
	var id := owner_id[idx(x, z)]
	return buildings.get(id, {}) if id > 0 else {}


# --- Island generation ----------------------------------------------------------------------------

## Make the island's land, beaches, rocky hills, ponds and woods (deterministic per island).
func generate(isl: int) -> void:
	clear()
	island = isl
	var d: Dictionary = Defs.island(isl)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d["seed"])
	var r0 := float(d["shape"])
	var ph: Array[float] = [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var c := Vector2(N * 0.5, N * 0.5)
	for z in N:
		for x in N:
			var p := Vector2(x + 0.5, z + 0.5) - c
			var a := atan2(p.y, p.x)
			var rr := r0 + sin(a * 3.0 + ph[0]) * 0.75 + sin(a * 5.0 + ph[1]) * 0.45 + sin(a * 2.0 + ph[2]) * 0.55
			var dist := p.length()
			if dist < rr - 1.1:
				ter[idx(x, z)] = Defs.T_GRASS
			elif dist < rr:
				ter[idx(x, z)] = Defs.T_SAND
	# Rocky hills near the coast (never in the middle, where the town starts).
	for k in int(d.get("rocks", 1)):
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(5.5, 7.0)
		var hc := c + Vector2(cos(ang), sin(ang)) * rad
		var hr := rng.randf_range(1.3, 2.0)
		for z in N:
			for x in N:
				if ter[idx(x, z)] == Defs.T_GRASS and Vector2(x + 0.5, z + 0.5).distance_to(hc) < hr:
					ter[idx(x, z)] = Defs.T_ROCK
	# Little ponds.
	for k in int(d.get("lakes", 0)):
		var ang2 := rng.randf() * TAU + 1.3
		var rad2 := rng.randf_range(4.5, 6.0)
		var lc := c + Vector2(cos(ang2), sin(ang2)) * rad2
		for z in N:
			for x in N:
				if ter[idx(x, z)] == Defs.T_GRASS and Vector2(x + 0.5, z + 0.5).distance_to(lc) < 1.25:
					ter[idx(x, z)] = Defs.T_WATER
	# Woods: clusters of trees on the grass, keeping the town centre clear.
	var centres: Array[Vector2] = []
	for k in 6:
		var ang3 := rng.randf() * TAU
		centres.append(c + Vector2(cos(ang3), sin(ang3)) * rng.randf_range(4.0, 8.0))
	for z in N:
		for x in N:
			if ter[idx(x, z)] != Defs.T_GRASS:
				continue
			var pc := Vector2(x + 0.5, z + 0.5)
			if pc.distance_to(c) < 4.2:
				continue
			var near := 99.0
			for cc in centres:
				near = minf(near, pc.distance_to(cc))
			var chance := 0.75 if near < 1.6 else (0.25 if near < 2.6 else 0.05)
			if rng.randf() < chance:
				trees[idx(x, z)] = 1 + rng.randi() % 3
	_touch(true, true)


## The town hall and the first little street (every new town starts with them).
func starter_town() -> void:
	var hx := N / 2 - 1
	var hz := N / 2 - 2
	add_building("hall", hx, hz, 0, 1)
	for x in range(hx - 3, hx + 5):
		set_layer(x, hz + 2, Defs.L_ROAD)


# --- Placement rules ------------------------------------------------------------------------------

## Cells a building of `kind` would cover with its corner at x, z.
func footprint(kind: String, x: int, z: int) -> Array[Vector2i]:
	var s := Defs.size_of(kind)
	var out: Array[Vector2i] = []
	for dz in s:
		for dx in s:
			out.append(Vector2i(x + dx, z + dz))
	return out


## "" if `kind` fits at x, z (building corner, or the painted cell for tools), else a short reason.
func can_place(kind: String, x: int, z: int) -> String:
	match kind:
		"road":
			if not inside(x, z) or not is_land(x, z):
				return "Roads go on land"
			if owner_id[idx(x, z)] > 0:
				return "A building is there"
			return ""
		"rail":
			if not inside(x, z) or not is_land(x, z):
				return "Tracks go on land"
			if owner_id[idx(x, z)] > 0:
				return "A building is there"
			return ""
		"bulldozer":
			if not inside(x, z) or layer(x, z) == Defs.L_NONE:
				return "Nothing to clear"
			return ""
	for c in footprint(kind, x, z):
		if not inside(c.x, c.y):
			return "Off the island"
		var t := terrain(c.x, c.y)
		if t == Defs.T_WATER:
			return "That's water!"
		if t == Defs.T_ROCK:
			return "Too rocky"
		if owner_id[idx(c.x, c.y)] > 0:
			return "Something is there"
		if lay[idx(c.x, c.y)] != Defs.L_NONE:
			return "A road is there"
	return ""


## Best default rotation for a building at x, z: face the first road found next to it (door side).
func auto_rot(kind: String, x: int, z: int) -> int:
	var s := Defs.size_of(kind)
	var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	for r in 4:
		var d := dirs[r]
		for k in s:
			var cx := x + (k if d.x == 0 else (s if d.x > 0 else -1))
			var cz := z + (k if d.y == 0 else (s if d.y > 0 else -1))
			if has_road(cx, cz):
				return r
	return 0


## Door direction for a rotation (0 = +Z south, 1 = +X, 2 = -Z, 3 = -X).
static func rot_dir(rot: int) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	return dirs[posmod(rot, 4)]


# --- Changes ----------------------------------------------------------------------------------------

## Paint / clear a transport cell. Roads and rails on the same cell make a level crossing.
func set_layer(x: int, z: int, value: int) -> bool:
	if not inside(x, z):
		return false
	var i := idx(x, z)
	var cur := int(lay[i])
	var nv := value
	if value == Defs.L_ROAD and (cur == Defs.L_RAIL or cur == Defs.L_CROSS):
		nv = Defs.L_CROSS
	elif value == Defs.L_RAIL and (cur == Defs.L_ROAD or cur == Defs.L_CROSS):
		nv = Defs.L_CROSS
	if nv == cur:
		return false
	lay[i] = nv
	if nv != Defs.L_NONE and trees[i] > 0:
		trees[i] = 0
		_touch(true, true)
	else:
		_touch(true)
	return true


func add_building(kind: String, x: int, z: int, rot: int, stage: int, id: int = 0) -> int:
	if id <= 0:
		id = next_id
	next_id = maxi(next_id, id + 1)
	var d := Defs.def(kind)
	var b := {"id": id, "kind": kind, "x": x, "z": z, "rot": posmod(rot, 4), "stage": stage, "mats": 0,
		"need": int(d.get("mats", 1)), "fire": 0, "lvl": 1, "res": 0, "work": 0, "food": 0, "bread": 0, "wood": 0,
		"needs": 0, "happy": 60, "wait": 0}
	buildings[id] = b
	_claim(b)
	return id


func _claim(b: Dictionary) -> void:
	var tree_gone := false
	for c in footprint(String(b["kind"]), int(b["x"]), int(b["z"])):
		if inside(c.x, c.y):
			var i := idx(c.x, c.y)
			owner_id[i] = int(b["id"])
			if trees[i] > 0:
				trees[i] = 0
				tree_gone = true
	_touch(false, tree_gone)


func remove_building(id: int) -> Dictionary:
	var b: Dictionary = buildings.get(id, {})
	if b.is_empty():
		return b
	for c in footprint(String(b["kind"]), int(b["x"]), int(b["z"])):
		if inside(c.x, c.y) and owner_id[idx(c.x, c.y)] == id:
			owner_id[idx(c.x, c.y)] = 0
	buildings.erase(id)
	_touch()
	return b


## Move an existing building (keeps everything else about it).
func move_building(id: int, x: int, z: int, rot: int) -> void:
	var b: Dictionary = buildings.get(id, {})
	if b.is_empty():
		return
	for c in footprint(String(b["kind"]), int(b["x"]), int(b["z"])):
		if inside(c.x, c.y) and owner_id[idx(c.x, c.y)] == id:
			owner_id[idx(c.x, c.y)] = 0
	b["x"] = x
	b["z"] = z
	b["rot"] = posmod(rot, 4)
	_claim(b)


## Rebuild the cell owners from the building list (after loading).
func rebuild_owners() -> void:
	owner_id.fill(0)
	for id in buildings:
		var b: Dictionary = buildings[id]
		for c in footprint(String(b["kind"]), int(b["x"]), int(b["z"])):
			if inside(c.x, c.y):
				owner_id[idx(c.x, c.y)] = int(id)
	_touch(true, true)


# --- Queries ------------------------------------------------------------------------------------------

## Road shape bits for a cell: 1 = north (z-1), 2 = east (x+1), 4 = south (z+1), 8 = west (x-1).
func road_mask(x: int, z: int) -> int:
	var m := 0
	if has_road(x, z - 1):
		m |= 1
	if has_road(x + 1, z):
		m |= 2
	if has_road(x, z + 1):
		m |= 4
	if has_road(x - 1, z):
		m |= 8
	return m


func rail_mask(x: int, z: int) -> int:
	var m := 0
	if has_rail(x, z - 1):
		m |= 1
	if has_rail(x + 1, z):
		m |= 2
	if has_rail(x, z + 1):
		m |= 4
	if has_rail(x - 1, z):
		m |= 8
	return m


## World centre of a building's footprint.
func center_of(b: Dictionary) -> Vector3:
	return Defs.foot_center(int(b["x"]), int(b["z"]), Defs.size_of(String(b["kind"])))


## Cells around a building's footprint (the ring just outside it).
func ring_cells(b: Dictionary) -> Array[Vector2i]:
	var s := Defs.size_of(String(b["kind"]))
	var x := int(b["x"])
	var z := int(b["z"])
	var out: Array[Vector2i] = []
	for k in s:
		out.append(Vector2i(x + k, z + s))
		out.append(Vector2i(x + s, z + k))
		out.append(Vector2i(x + k, z - 1))
		out.append(Vector2i(x - 1, z + k))
	return out


## True if a road touches the building.
func on_road(b: Dictionary) -> bool:
	for c in ring_cells(b):
		if has_road(c.x, c.y):
			return true
	return false


## Where a vehicle should stop for this building: the road cell by its door if there is one, else
## any road next to it, else the grass in front of the door.
func door_cell(b: Dictionary) -> Vector2i:
	var s := Defs.size_of(String(b["kind"]))
	var d := rot_dir(int(b["rot"]))
	var x := int(b["x"])
	var z := int(b["z"])
	var front: Array[Vector2i] = []
	for k in s:
		front.append(Vector2i(x + (k if d.x == 0 else (s if d.x > 0 else -1)), z + (k if d.y == 0 else (s if d.y > 0 else -1))))
	for c in front:
		if has_road(c.x, c.y):
			return c
	for c in ring_cells(b):
		if has_road(c.x, c.y):
			return c
	for c in front:
		if _drivable(c.x, c.y):
			return c
	for c in ring_cells(b):
		if _drivable(c.x, c.y):
			return c
	return Vector2i(x, z)


## Distance (metres, on the ground plane) from a point to a building's footprint edge.
func dist_to(b: Dictionary, p: Vector3) -> float:
	var s := Defs.size_of(String(b["kind"]))
	var c := center_of(b)
	var h := s * Defs.CELL * 0.5
	var dx := maxf(absf(p.x - c.x) - h, 0.0)
	var dz := maxf(absf(p.z - c.z) - h, 0.0)
	return sqrt(dx * dx + dz * dz)


## Buildings of a kind (built ones only unless `plans` is true).
func of_kind(kind: String, plans: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in buildings:
		var b: Dictionary = buildings[id]
		if String(b["kind"]) == kind and (plans or int(b["stage"]) >= 1):
			out.append(b)
	return out


func count_kind(kind: String) -> int:
	return of_kind(kind).size()


## Within `radius` cells (centre to centre) of a building of `kind`?
func near_kind(b: Dictionary, kind: String, radius: float) -> bool:
	var c := center_of(b)
	for o in of_kind(kind):
		if center_of(o).distance_to(c) <= radius * Defs.CELL + 0.001:
			return true
	return false


## Is this cell something a vehicle can drive on?
func _drivable(x: int, z: int) -> bool:
	return inside(x, z) and is_land(x, z) and owner_id[idx(x, z)] == 0


func drivable_at(p: Vector3) -> bool:
	var c := Defs.world_cell(p)
	return _drivable(c.x, c.y)


## Speed factor for a vehicle at a point: fast on roads, slower on grass, slowest in the woods.
func speed_at(p: Vector3) -> float:
	var c := Defs.world_cell(p)
	if not inside(c.x, c.y):
		return 0.5
	if has_road(c.x, c.y):
		return 1.0
	if trees[idx(c.x, c.y)] > 0:
		return 0.5
	return 0.68


# --- Path finding (AI drivers) -----------------------------------------------------------------------------

func _ensure_astar() -> void:
	if _astar != null and _astar_version == version:
		return
	if _astar == null:
		_astar = AStarGrid2D.new()
		_astar.region = Rect2i(0, 0, N, N)
		_astar.cell_size = Vector2(1, 1)
		_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		_astar.update()
	for z in N:
		for x in N:
			var p := Vector2i(x, z)
			var ok := _drivable(x, z)
			_astar.set_point_solid(p, not ok)
			if ok:
				var w := 2.6
				if has_road(x, z):
					w = 1.0
				elif has_rail(x, z):
					w = 2.0
				elif trees[idx(x, z)] > 0:
					w = 3.6
				_astar.set_point_weight_scale(p, w)
	_astar_version = version


## Nearest drivable cell to `c` (itself if it is drivable).
func nearest_drivable(c: Vector2i) -> Vector2i:
	if _drivable(c.x, c.y):
		return c
	for r in range(1, 6):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) == r and _drivable(c.x + dx, c.y + dz):
					return Vector2i(c.x + dx, c.y + dz)
	return c


## Cells from `from` to `to` (both made drivable first); empty when there is no way.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	_ensure_astar()
	var a := nearest_drivable(from)
	var b := nearest_drivable(to)
	var out: Array[Vector2i] = []
	if not inside(a.x, a.y) or not inside(b.x, b.y) or _astar.is_point_solid(a) or _astar.is_point_solid(b):
		return out
	var ids: Array[Vector2i] = _astar.get_id_path(a, b)
	for p in ids:
		out.append(p)
	return out


## The rail cells joining two stations (empty if they aren't joined): a flood fill along rails.
func rail_route(a: Dictionary, b: Dictionary) -> Array[Vector2i]:
	var starts: Array[Vector2i] = []
	for c in ring_cells(a):
		if has_rail(c.x, c.y):
			starts.append(c)
	var goals := {}
	for c in ring_cells(b):
		if has_rail(c.x, c.y):
			goals[c] = true
	var none: Array[Vector2i] = []
	if starts.is_empty() or goals.is_empty():
		return none
	var prev := {}
	var queue: Array[Vector2i] = []
	for s in starts:
		prev[s] = s
		queue.append(s)
	var head := 0
	var found := Vector2i(-1, -1)
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if goals.has(cur):
			found = cur
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var dv: Vector2i = d
			var nx := cur + dv
			if has_rail(nx.x, nx.y) and not prev.has(nx):
				prev[nx] = cur
				queue.append(nx)
	var out: Array[Vector2i] = []
	if found.x < 0:
		return out
	var c2 := found
	while true:
		out.push_front(c2)
		var p: Vector2i = prev[c2]
		if p == c2:
			break
		c2 = p
	return out


# --- Packing (net store / saves) ------------------------------------------------------------------------

static func pack_building(b: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(PACK.size())
	for i in PACK.size():
		var k := PACK[i]
		if k == "kind":
			out[i] = Defs.kind_index(String(b["kind"]))
		else:
			out[i] = int(b.get(k, 0))
	return out


static func unpack_building(id: int, a: PackedInt32Array) -> Dictionary:
	var b := {"id": id}
	for i in PACK.size():
		var k := PACK[i]
		var v: int = a[i] if i < a.size() else 0
		if k == "kind":
			b["kind"] = Defs.kind_at(v)
		else:
			b[k] = v
	return b


## Apply a packed record from the store (TV machine). Returns true if its look changed (the view
## must rebuild that building) rather than just numbers.
func apply_packed(id: int, a: PackedInt32Array) -> bool:
	var nb := unpack_building(id, a)
	var old: Dictionary = buildings.get(id, {})
	var look := old.is_empty()
	if not look:
		for k in ["kind", "x", "z", "rot", "stage", "lvl"]:
			if old.get(k) != nb.get(k):
				look = true
	if look and not old.is_empty():
		for c in footprint(String(old["kind"]), int(old["x"]), int(old["z"])):
			if inside(c.x, c.y) and owner_id[idx(c.x, c.y)] == id:
				owner_id[idx(c.x, c.y)] = 0
	if old.is_empty():
		buildings[id] = nb
	else:
		for k in nb:
			old[k] = nb[k]
		nb = old
	next_id = maxi(next_id, id + 1)
	if look:
		_claim(nb)
	return look


func serialize() -> Dictionary:
	var bl: Array = []
	for id in buildings:
		bl.append([int(id), pack_building(buildings[id])])
	return {"island": island, "ter": ter.duplicate(), "trees": trees.duplicate(), "lay": lay.duplicate(), "b": bl,
		"next_id": next_id}


func deserialize(d: Dictionary) -> void:
	clear()
	island = int(d.get("island", 0))
	var t: PackedByteArray = d.get("ter", PackedByteArray())
	var tr: PackedByteArray = d.get("trees", PackedByteArray())
	var l: PackedByteArray = d.get("lay", PackedByteArray())
	if t.size() == N * N:
		ter = t.duplicate()
	if tr.size() == N * N:
		trees = tr.duplicate()
	if l.size() == N * N:
		lay = l.duplicate()
	for e in d.get("b", []):
		var arr: Array = e
		var id := int(arr[0])
		var pk: PackedInt32Array = arr[1]
		buildings[id] = unpack_building(id, pk)
	next_id = maxi(int(d.get("next_id", 1)), next_id)
	for id in buildings:
		next_id = maxi(next_id, int(id) + 1)
	rebuild_owners()
