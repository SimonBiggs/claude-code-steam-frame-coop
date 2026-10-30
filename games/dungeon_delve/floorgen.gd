extends RefCounted
## DUNGEON DELVE deep floors (BRAVE / HEROIC): a seeded floor generator. Pure data, so every machine
## builds the same floor from [seed, zone, floor] and the bot test can check thousands of them.
## A floor is a few square rooms on a grid, joined by doors in the middle of the shared walls:
##  - start room (no monsters), fight rooms (the doors shut until every monster is gone), trap rooms
##    (spikes, rolling boulders, crumbly floor), a treasure room now and then;
##  - the EXIT (stairs down) is the deepest room, behind a LOCKED door; its KEY lies in another dead end;
##  - one door may be a PUZZLE door: two switches (floor plates or wall levers) in the room before it
##    must be on at the same time (a friend helps; alone, a switch stays on long enough to run);
##  - a SECRET room hides behind a cracked wall (hit it three times, or one bomb);
##  - floor 4 of each zone ends in the BOSS room, behind the locked boss door.
## Rooms may have pillars (obstacles); walkable() and clamp() keep bodies out of walls and pillars.

const CELL := 12.0  ## room pitch (11 m rooms + 1 m walls)
const HALF := 5.5  ## room interior half size
const DOOR := 1.2  ## door half width
const WALL_T := 1.0
const TILE := 2.0 * HALF / 7.0  ## floor tiles: 7 x 7 per room (spikes and crumbly tiles sit on them)
const GRID := 5
const ORIGIN := Vector3(80.0, 0.0, 0.0)  ## far away from the GENTLE dungeon
const FLOORS_PER_ZONE := 4
const ZONE_COUNT := 4  ## biomes: Slime Caves, Bone Crypt, Crystal Caves, Lava Forge (then the endless depths)

enum { OPEN, LOCKED, SECRET, PUZZLE, BOSS }
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  ## N E S W

## Foe kinds (games/dungeon_delve/foes.gd uses the same numbers).
enum { F_SLIME, F_SPITTER, F_SHIELD, F_SWARM, F_HEALER, F_MIMIC, F_CHARGER, F_BOMBER,
	B_SLIME, B_BONE, B_FORGE, B_CRYSTAL }
const FOE_COST := {F_SLIME: 1.0, F_SPITTER: 2.0, F_SHIELD: 2.5, F_SWARM: 2.0, F_HEALER: 2.0, F_CHARGER: 3.0, F_BOMBER: 2.0}

## The biomes, top to bottom. "id" picks looks (foes.gd, floor_view.gd); "feature" is the biome's own
## hazard in its fight rooms: CRYSTAL CAVES grow crystal clusters that burst a lane of shards, the LAVA
## FORGE has lava vents that glow, then blast fire up (both always glow on the floor first).
const ZONES: Array[Dictionary] = [
	{"id": "caves", "name": "SLIME CAVES", "short": "CAVES", "boss": B_SLIME, "traps": ["spikes", "collapse"], "feature": "",
		"foes": {F_SLIME: 5.0, F_SPITTER: 2.0, F_SWARM: 2.0, F_HEALER: 1.0, F_CHARGER: 1.0},
		"floor": [Color(0.3, 0.42, 0.36), Color(0.36, 0.5, 0.42)], "wall": Color(0.33, 0.45, 0.42), "glow": Color(0.45, 1.0, 0.6)},
	{"id": "crypt", "name": "BONE CRYPT", "short": "CRYPT", "boss": B_BONE, "traps": ["spikes", "boulder"], "feature": "",
		"foes": {F_SHIELD: 3.0, F_SPITTER: 2.0, F_SWARM: 2.0, F_HEALER: 2.0, F_SLIME: 1.0, F_BOMBER: 1.0},
		"floor": [Color(0.36, 0.34, 0.44), Color(0.44, 0.42, 0.52)], "wall": Color(0.42, 0.4, 0.52), "glow": Color(0.6, 0.75, 1.0)},
	{"id": "crystal", "name": "CRYSTAL CAVES", "short": "CRYSTAL", "boss": B_CRYSTAL, "traps": ["spikes", "collapse"], "feature": "shards",
		"foes": {F_SPITTER: 3.0, F_CHARGER: 2.0, F_SWARM: 2.0, F_SHIELD: 1.5, F_HEALER: 1.0, F_SLIME: 1.0},
		"floor": [Color(0.24, 0.3, 0.42), Color(0.3, 0.38, 0.52)], "wall": Color(0.3, 0.36, 0.5), "glow": Color(0.5, 0.95, 1.0)},
	{"id": "forge", "name": "LAVA FORGE", "short": "FORGE", "boss": B_FORGE, "traps": ["boulder", "collapse", "spikes"], "feature": "vents",
		"foes": {F_SHIELD: 2.0, F_CHARGER: 2.0, F_BOMBER: 2.0, F_SPITTER: 2.0, F_SWARM: 2.0, F_HEALER: 1.0, F_SLIME: 1.0},
		"floor": [Color(0.3, 0.24, 0.24), Color(0.38, 0.3, 0.28)], "wall": Color(0.36, 0.28, 0.27), "glow": Color(1.0, 0.5, 0.2)},
]
## Biome hazards: seconds of glowing warning before they go off (tests check every one is readable), the
## cycle, and how big they are.
const FEATURE := {"shards": {"warn": 1.4, "period": 5.5, "len": 6.0, "width": 1.1},
	"vents": {"warn": 1.3, "period": 4.6, "radius": 1.05}}
const MIN_WARN := 0.9  ## nothing that hurts may glow for less than this (tests: features, boss tells)

## Pillar layouts (local rects: [cx, cz, half_x, half_z]).
const LAYOUTS: Array = [
	[],
	[[-2.6, -2.6, 0.45, 0.45], [2.6, -2.6, 0.45, 0.45], [-2.6, 2.6, 0.45, 0.45], [2.6, 2.6, 0.45, 0.45]],
	[[0.0, 0.0, 0.9, 0.9]],
	[[-2.7, 0.0, 0.35, 1.8], [2.7, 0.0, 0.35, 1.8]],
	[[0.0, -2.4, 1.6, 0.35], [0.0, 2.4, 1.6, 0.35]],
]


## ENDLESS: after the last biome's boss the zones go round again (deeper = tougher) and every floor gets a
## twist: SWIFT (monsters faster), SWARM (more of them), ELITES (lots of gold-ringed ones), STONE
## (tougher hides). "" for the first three zones.
const MODS: Array[String] = ["SWIFT", "SWARM", "ELITES", "STONE"]


static func modifier(seed_value: int, zone: int, floor_i: int) -> String:
	if zone < ZONE_COUNT:
		return ""
	return MODS[absi(hash([seed_value, zone, floor_i, "mod"])) % MODS.size()]


## A zone's look and monsters (the endless depths go round the biomes again). Always use this,
## never ZONES[zone] directly (zone 4+ is past the end of the list).
static func zone_data(zone: int) -> Dictionary:
	return ZONES[posmod(zone, ZONES.size())]


static func global_floor(zone: int, floor_i: int) -> int:
	return zone * FLOORS_PER_ZONE + floor_i


static func is_boss_floor(floor_i: int) -> bool:
	return floor_i == FLOORS_PER_ZONE - 1


static func cell_center(cell: Vector2i) -> Vector3:
	return ORIGIN + Vector3(cell.x * CELL, 0.0, cell.y * CELL)


## A whole floor. kind "floor" or "shop" (the little camp between floors: one room).
static func generate(seed_value: int, zone: int, floor_i: int, heroic: bool, kind: String = "floor") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, zone, floor_i, kind])
	var f := {"seed": seed_value, "zone": zone, "floor": floor_i, "kind": kind, "rooms": [], "doors": [],
		"switches": [], "traps": [], "start": 0, "exit": -1, "boss": -1, "key_rooms": [], "secret": -1}
	if kind == "shop":
		f["rooms"] = [_room(Vector2i(2, 2), "shop", 0)]
		f["exit"] = 0
		(f["rooms"][0] as Dictionary)["stairs"] = Vector2(0.0, -3.6)
		return f
	var boss_floor := is_boss_floor(floor_i)
	var g := global_floor(zone, floor_i)
	var n := 5 + (g + 1) / 3 + (1 if heroic else 0)  # more rooms the deeper you go (never fewer than the floor before)
	if boss_floor:
		n = 5 + zone
	n = mini(n, 10)
	# Grow a tree of rooms from the bottom middle, leaning north (up the TV screen).
	var at := {}  # Vector2i -> room index
	var rooms: Array = []
	var doors: Array = []
	var start := Vector2i(2, GRID - 1)
	rooms.append(_room(start, "start", 0))
	at[start] = 0
	var tries := 0
	while rooms.size() < n and tries < 400:
		tries += 1
		var ri := rng.randi_range(0, rooms.size() - 1)
		var c: Vector2i = (rooms[ri] as Dictionary)["cell"]
		var d := _pick_dir(rng)
		var nc: Vector2i = c + DIRS[d]
		if not _in_grid(nc) or at.has(nc):
			continue
		var ni := rooms.size()
		rooms.append(_room(nc, "fight", int((rooms[ri] as Dictionary)["depth"]) + 1))
		(rooms[ni] as Dictionary)["parent"] = ri
		at[nc] = ni
		_add_door(rooms, doors, ri, ni, d, OPEN)
	# The exit: the deepest room (a leaf). On boss floors the boss room hangs off it.
	var exit := 0
	for i in rooms.size():
		if int((rooms[i] as Dictionary)["depth"]) > int((rooms[exit] as Dictionary)["depth"]) or (int((rooms[i] as Dictionary)["depth"]) == int((rooms[exit] as Dictionary)["depth"]) and rng.randf() < 0.5):
			exit = i
	var lock_room := exit
	if boss_floor:
		var bi := -1
		var order: Array = range(rooms.size())
		order.sort_custom(func(a: int, b: int) -> bool: return int((rooms[a] as Dictionary)["depth"]) > int((rooms[b] as Dictionary)["depth"]))
		for ri2 in order:
			if int(ri2) == 0:
				continue
			var c2: Vector2i = (rooms[ri2] as Dictionary)["cell"]
			for d2 in [0, 1, 3, 2]:
				var nc2: Vector2i = c2 + DIRS[d2]
				if _in_grid(nc2) and not at.has(nc2):
					bi = rooms.size()
					rooms.append(_room(nc2, "boss", int((rooms[ri2] as Dictionary)["depth"]) + 1))
					(rooms[bi] as Dictionary)["parent"] = ri2
					at[nc2] = bi
					_add_door(rooms, doors, int(ri2), bi, d2, BOSS)
					break
			if bi >= 0:
				break
		if bi < 0:  # no room for a boss room anywhere (can't really happen on a 5x5 grid): the exit fights
			bi = exit
			(rooms[bi] as Dictionary)["role"] = "boss"
		f["boss"] = bi
		lock_room = bi
		exit = bi
	else:
		(rooms[exit] as Dictionary)["role"] = "exit"
		(rooms[exit] as Dictionary)["stairs"] = Vector2(0.0, 0.0)
		var pd := _door_between(rooms, int((rooms[exit] as Dictionary)["parent"]), exit)
		(doors[pd] as Dictionary)["type"] = LOCKED
	f["exit"] = exit
	# The key: in the deepest other dead end (never behind the locked door).
	var key_room := -1
	var best := -1
	for i in rooms.size():
		if i == 0 or i == lock_room or i == exit:
			continue
		var dead := _child_count(rooms, i) == 0
		var score := int((rooms[i] as Dictionary)["depth"]) * 2 + (3 if dead else 0)
		if score > best:
			best = score
			key_room = i
	if key_room < 0:
		key_room = 0
	(rooms[key_room] as Dictionary)["key"] = true
	f["key_rooms"] = [key_room]
	# A couple of loops (never into the exit / boss room).
	var loops := rng.randi_range(0, 2 if n >= 7 else 1)
	for k in 30:
		if loops <= 0:
			break
		var a := rng.randi_range(1, rooms.size() - 1)
		var d3 := rng.randi_range(0, 3)
		var nb: Vector2i = (rooms[a] as Dictionary)["cell"] + DIRS[d3]
		if not at.has(nb):
			continue
		var b: int = at[nb]
		if b == exit or a == exit or b == lock_room or a == lock_room or _door_between(rooms, a, b) >= 0:
			continue
		_add_door(rooms, doors, a, b, d3, OPEN)
		loops -= 1
	# A puzzle door on a bridge (so it can't be walked round), not the locked/boss door.
	if g >= 1:
		var cands: Array = []
		for di in doors.size():
			var dd: Dictionary = doors[di]
			if int(dd["type"]) != OPEN or int(dd["b"]) == key_room and rng.randf() < 0.5:
				continue
			if _is_bridge(rooms, doors, di):
				cands.append(di)
		if not cands.is_empty():
			var pdi: int = cands[rng.randi_range(0, cands.size() - 1)]
			(doors[pdi] as Dictionary)["type"] = PUZZLE
	# Pillars, roles, monsters, traps, chests.
	var zd: Dictionary = zone_data(zone)
	var mod := modifier(seed_value, zone, floor_i)
	f["mod"] = mod
	var trap_left := 0 if g == 0 else (1 if g < 4 else 2)
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var role: String = r["role"]
		if role in ["fight"] and i != key_room and rng.randf() < 0.12 and g >= 1:
			role = "treasure"
		elif role == "fight" and trap_left > 0 and i != 0 and rng.randf() < 0.45:
			role = "trap"
			trap_left -= 1
		r["role"] = role
		if role in ["fight", "trap"]:
			r["layout"] = rng.randi_range(0, LAYOUTS.size() - 1)
		elif role == "exit":
			r["layout"] = [0, 1, 3, 4][rng.randi_range(0, 3)]  # the stairs sit in the middle
		if role == "boss":
			r["layout"] = 0
	# Puzzle switches go into the room on the near (start) side of the puzzle door.
	for di in doors.size():
		var dd: Dictionary = doors[di]
		if int(dd["type"]) == PUZZLE:
			_make_switches(f, rooms, dd, di, rng)
	f["rooms"] = rooms
	f["doors"] = doors
	# The secret room: a free cell next to a middle room.
	var secret_tries: Array = range(1, rooms.size())
	_shuffle(secret_tries, rng)
	for ri3 in secret_tries:
		var r3: Dictionary = rooms[ri3]
		if String(r3["role"]) in ["boss", "exit"]:
			continue
		var found := false
		for d4 in [0, 1, 3, 2]:
			var nc3: Vector2i = (r3["cell"] as Vector2i) + DIRS[d4]
			if _in_grid(nc3) and not at.has(nc3):
				var si := rooms.size()
				rooms.append(_room(nc3, "secret", int(r3["depth"]) + 1))
				(rooms[si] as Dictionary)["parent"] = ri3
				at[nc3] = si
				_add_door(rooms, doors, int(ri3), si, d4, SECRET)
				f["secret"] = si
				found = true
				break
		if found:
			break
	for i in rooms.size():
		_fill_room(f, i, rng, zd, g, heroic, mod)
	return f


static func _room(cell: Vector2i, role: String, depth: int) -> Dictionary:
	return {"cell": cell, "role": role, "depth": depth, "doors": {}, "parent": -1, "layout": 0, "foes": [],
		"chests": [], "pots": [], "key": false, "traps": [], "switches": []}


static func _pick_dir(rng: RandomNumberGenerator) -> int:
	var x := rng.randf() * 5.0
	if x < 2.0:
		return 0
	if x < 3.3:
		return 1
	if x < 4.6:
		return 3
	return 2


static func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GRID and c.y < GRID


static func _add_door(rooms: Array, doors: Array, a: int, b: int, dir_from_a: int, type: int) -> int:
	var id := doors.size()
	doors.append({"a": a, "b": b, "dir": dir_from_a, "type": type, "switches": []})
	((rooms[a] as Dictionary)["doors"] as Dictionary)[dir_from_a] = id
	((rooms[b] as Dictionary)["doors"] as Dictionary)[(dir_from_a + 2) % 4] = id
	return id


static func _door_between(rooms: Array, a: int, b: int) -> int:
	if a < 0 or b < 0:
		return -1
	var ds: Dictionary = (rooms[a] as Dictionary)["doors"]
	for d in ds:
		var id: int = ds[d]
		var bd: Dictionary = (rooms[b] as Dictionary)["doors"]
		for d2 in bd:
			if int(bd[d2]) == id:
				return id
	return -1


static func _child_count(rooms: Array, i: int) -> int:
	var n := 0
	for r in rooms:
		if int((r as Dictionary)["parent"]) == i:
			n += 1
	return n


## True if removing door di splits the rooms into two groups.
static func _is_bridge(rooms: Array, doors: Array, di: int) -> bool:
	var seen := {0: true}
	var stack: Array = [0]
	while not stack.is_empty():
		var r: int = stack.pop_back()
		var ds: Dictionary = (rooms[r] as Dictionary)["doors"]
		for d in ds:
			var id: int = ds[d]
			if id == di:
				continue
			var o: int = other_side(doors[id], r)
			if not seen.has(o):
				seen[o] = true
				stack.append(o)
	return seen.size() < rooms.size()


static func other_side(door: Dictionary, r: int) -> int:
	return int(door["b"]) if int(door["a"]) == r else int(door["a"])


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


static func _make_switches(f: Dictionary, rooms: Array, dd: Dictionary, di: int, rng: RandomNumberGenerator) -> void:
	var near := int(dd["a"])
	var r: Dictionary = rooms[near]
	r["layout"] = 0  # keep the floor clear for the plates
	var spots: Array = [Vector2(-3.6, -3.6), Vector2(3.6, 3.6), Vector2(3.6, -3.6), Vector2(-3.6, 3.6)]
	var pick := rng.randi_range(0, 1) * 2
	var pair: Array = [spots[pick], spots[pick + 1]]
	for k in 2:
		var kind := "plate"
		var p: Vector2 = pair[k]
		if k == 1 and rng.randf() < 0.5:
			kind = "lever"
			# On a wall without a door, near the plate's corner.
			var wall_dir := 1 if p.x > 0.0 else 3
			if (r["doors"] as Dictionary).has(wall_dir):
				wall_dir = 2 if p.y > 0.0 else 0
			if (r["doors"] as Dictionary).has(wall_dir):
				kind = "plate"
			else:
				p = _wall_spot(wall_dir, p)
		var sid := (f["switches"] as Array).size()
		(f["switches"] as Array).append({"room": near, "kind": kind, "p": p, "door": di, "wall": _wall_of(p)})
		(dd["switches"] as Array).append(sid)
		(r["switches"] as Array).append(sid)


static func _wall_spot(dir: int, p: Vector2) -> Vector2:
	match dir:
		0:
			return Vector2(p.x, -HALF + 0.15)
		1:
			return Vector2(HALF - 0.15, p.y)
		2:
			return Vector2(p.x, HALF - 0.15)
	return Vector2(-HALF + 0.15, p.y)


static func _wall_of(p: Vector2) -> int:
	if p.y <= -HALF + 0.3:
		return 0
	if p.x >= HALF - 0.3:
		return 1
	if p.y >= HALF - 0.3:
		return 2
	if p.x <= -HALF + 0.3:
		return 3
	return -1


## A free spot in a room (local x, z) away from doors, pillars and other things.
static func free_spot(f: Dictionary, ri: int, rng: RandomNumberGenerator, taken: Array, margin: float = 0.8, extent: float = 4.4) -> Vector2:
	var r: Dictionary = (f["rooms"] as Array)[ri]
	for k in 40:
		var p := Vector2(rng.randf_range(-extent, extent), rng.randf_range(-extent, extent))
		if not _spot_ok(r, p, margin):
			continue
		var ok := true
		for t in taken:
			if (t as Vector2).distance_to(p) < 1.2:
				ok = false
				break
		if ok:
			taken.append(p)
			return p
	for p2 in [Vector2(0.0, 1.5), Vector2(1.5, 0.0), Vector2(-1.5, 0.0), Vector2(0.0, -1.5), Vector2(1.5, 1.5), Vector2(-1.5, -1.5)]:
		if _spot_ok(r, p2, 0.4):
			return p2
	return Vector2(4.0, 0.0)


static func _spot_ok(r: Dictionary, p: Vector2, margin: float) -> bool:
	for rect in LAYOUTS[int(r["layout"])]:
		var a: Array = rect
		if absf(p.x - float(a[0])) < float(a[2]) + margin and absf(p.y - float(a[1])) < float(a[3]) + margin:
			return false
	for d in (r["doors"] as Dictionary):
		var dp := door_local(int(d))
		if dp.distance_to(p) < 2.2:
			return false
	return true


## Local position of the middle of a room's doorway in direction d.
static func door_local(d: int) -> Vector2:
	var v := DIRS[d]
	return Vector2(v.x * HALF, v.y * HALF)


static func _fill_room(f: Dictionary, i: int, rng: RandomNumberGenerator, zd: Dictionary, g: int, heroic: bool, mod: String = "") -> void:
	var r: Dictionary = (f["rooms"] as Array)[i]
	var role: String = r["role"]
	var taken: Array = []
	for sid in r["switches"]:
		taken.append(((f["switches"] as Array)[sid] as Dictionary)["p"])
	if role == "start":
		taken.append(Vector2.ZERO)
	if r.has("stairs"):
		taken.append(r["stairs"])
		taken.append(Vector2(0.0, 0.9))
	# Monsters.
	var budget := 0.0
	match role:
		"fight":
			budget = 4.0 + g * 0.9 + (1.5 if heroic else 0.0)
		"trap":
			budget = 2.0 + g * 0.5  # traps AND monsters
		"exit":
			budget = 3.5 + g * 0.8
	if mod == "SWARM":
		budget *= 1.5
	budget = minf(budget, 16.0)  # endless depths: a full room, not a wall of monsters
	if budget > 0.0:
		var table: Dictionary = zd["foes"]
		var elite_p := minf(0.1 + g * 0.03 + (0.12 if heroic else 0.0) + (0.3 if mod == "ELITES" else 0.0), 0.6)
		var guard := 0
		while budget > 0.5 and guard < 20:
			guard += 1
			var kind := _weighted(table, rng)
			var cost: float = FOE_COST[kind]
			if cost > budget + 0.6:
				kind = F_SLIME
				cost = 1.0
			budget -= cost
			var p := free_spot(f, i, rng, taken, 0.7, 4.0)
			var elite := (g >= 1 or heroic) and rng.randf() < elite_p
			if kind == F_SWARM:
				for s in 3:
					var sp := p + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8))
					(r["foes"] as Array).append([kind, sp if _spot_ok(r, sp, 0.3) else p, false])
			else:
				(r["foes"] as Array).append([kind, p, elite])
	if role == "boss":
		(r["foes"] as Array).append([int(zd["boss"]), Vector2(0.0, -2.0), false])
	# Traps.
	if role == "trap":
		var kinds: Array = zd["traps"]
		var tk: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		_make_trap(f, i, tk, rng, taken)
		if g >= 6 and rng.randf() < 0.5:
			var tk2: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			if tk2 != tk:
				_make_trap(f, i, tk2, rng, taken)
	# The biome's own hazard (crystal shards, lava vents) in rooms you fight in; never the start, boss or camp.
	r["features"] = []
	var feat := String(zd.get("feature", ""))
	if feat != "" and role in ["fight", "trap", "exit"]:
		var count := 1 + (1 if g >= 13 else 0) + (1 if role == "exit" and g >= 14 else 0)
		for k in count:
			var phase := rng.randf_range(0.0, float(FEATURE[feat]["period"]))
			if feat == "vents":
				var vp := Vector2.INF
				for t in 6:
					var cand := free_spot(f, i, rng, taken, 0.9, 3.8)
					if not r.has("stairs") or (r["stairs"] as Vector2).distance_to(cand) >= 2.0:
						vp = cand
						break
				if vp != Vector2.INF:
					taken.append(vp + Vector2(0.01, 0.0))  # (a second marker: the key keeps further off)
					(r["features"] as Array).append({"kind": feat, "p": vp, "dir": 0, "phase": phase})
			else:
				var walls: Array = []
				for d in 4:
					if not (r["doors"] as Dictionary).has(d):
						walls.append(d)
				if walls.is_empty():
					continue
				var wd: int = walls[rng.randi_range(0, walls.size() - 1)]
				var along := rng.randf_range(-3.0, 3.0)
				var dv := Vector2(DIRS[wd])
				var cp := dv * (HALF - 0.35) + Vector2(-dv.y, dv.x) * along
				(r["features"] as Array).append({"kind": feat, "p": cp, "dir": (wd + 2) % 4, "phase": phase})
	# Chests (some are mimics) and pots.
	var chest_p := 0.0
	match role:
		"fight":
			chest_p = 0.3
		"trap":
			chest_p = 0.5
		"treasure":
			chest_p = 1.0
		"secret":
			chest_p = 1.0
	if rng.randf() < chest_p:
		var mimic := g >= 2 and role != "secret" and rng.randf() < 0.3 + (0.15 if heroic else 0.0)
		(r["chests"] as Array).append([free_spot(f, i, rng, taken, 0.9, 3.6), mimic])
	if role in ["treasure", "secret"]:
		(r["chests"] as Array).append([free_spot(f, i, rng, taken, 0.9, 3.6), role == "treasure" and g >= 3 and rng.randf() < 0.35])
	if role == "secret":
		r["heart"] = true  # a heart container (more hearts for the finder)
	var pots := rng.randi_range(1, 3) if role != "boss" else 0
	for k in pots:
		var corner := Vector2(rng.randf_range(3.6, 4.8) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf_range(-4.8, 4.8))
		if rng.randf() < 0.5:
			corner = Vector2(corner.y, corner.x)
		if _spot_ok(r, corner, 0.4):
			(r["pots"] as Array).append(corner)
	if r["key"]:
		r["key_at"] = free_spot(f, i, rng, taken, 0.8, 2.5)
		for t2 in 8:  # never on a lava vent
			var clear := true
			for fe in r["features"]:
				if String((fe as Dictionary)["kind"]) == "vents" and ((fe as Dictionary)["p"] as Vector2).distance_to(r["key_at"]) < 1.6:
					clear = false
			if clear:
				break
			r["key_at"] = free_spot(f, i, rng, taken, 0.8, 3.5)


static func _weighted(table: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var x := rng.randf() * total
	for k in table:
		x -= float(table[k])
		if x <= 0.0:
			return int(k)
	return int(table.keys()[0])


static func _make_trap(f: Dictionary, i: int, kind: String, rng: RandomNumberGenerator, taken: Array) -> void:
	var r: Dictionary = (f["rooms"] as Array)[i]
	var t := {"room": i, "kind": kind, "phase": rng.randf_range(0.0, 3.0)}
	match kind:
		"spikes":
			# A band of spike tiles two tiles wide right across the room: time your run.
			var horizontal := rng.randf() < 0.5
			var tiles: Array = []
			var off_i := rng.randi_range(-1, 1)
			for k in 7:
				var along := (k - 3) * TILE
				for w in 2:
					var across := (off_i + w) * TILE
					tiles.append(Vector2(along, across) if horizontal else Vector2(across, along))
			t["tiles"] = tiles
			t["period"] = rng.randf_range(4.0, 5.0)  # down long enough to walk across (2.3 s+)
		"boulder":
			var along_x := rng.randf() < 0.5
			var lane := rng.randf_range(-2.8, 2.8)
			t["axis"] = 0 if along_x else 1
			t["lane"] = lane
			t["period"] = rng.randf_range(4.5, 6.5)
		"collapse":
			var tiles2: Array = []
			var cx := rng.randi_range(-1, 1)
			var cz := rng.randi_range(-1, 1)
			for k in 9:
				var ix := clampi(cx + rng.randi_range(-2, 2), -2, 2)
				var iz := clampi(cz + rng.randi_range(-2, 2), -2, 2)
				var p := Vector2(ix * TILE, iz * TILE)
				if _spot_ok(r, p, 0.3) and not tiles2.has(p):
					tiles2.append(p)
			t["tiles"] = tiles2
	var ti := (f["traps"] as Array).size()
	(f["traps"] as Array).append(t)
	(r["traps"] as Array).append(ti)


# --- Geometry (every machine; clamps bodies, plans bot routes) ------------------------------------

## The room a world point is in (-1 = in a wall / outside).
static func room_at(f: Dictionary, p: Vector3) -> int:
	var rooms: Array = f["rooms"]
	for i in rooms.size():
		var c := cell_center((rooms[i] as Dictionary)["cell"])
		if absf(p.x - c.x) <= HALF + 0.5 and absf(p.z - c.z) <= HALF + 0.5:
			return i
	return -1


static func room_center(f: Dictionary, ri: int) -> Vector3:
	return cell_center(((f["rooms"] as Array)[ri] as Dictionary)["cell"])


static func to_world(f: Dictionary, ri: int, local: Vector2) -> Vector3:
	return room_center(f, ri) + Vector3(local.x, 0.0, local.y)


## World position of a doorway's middle (in the wall).
static func door_world(f: Dictionary, di: int) -> Vector3:
	var d: Dictionary = (f["doors"] as Array)[di]
	var c := room_center(f, int(d["a"]))
	var v: Vector2i = DIRS[int(d["dir"])]
	return c + Vector3(v.x, 0.0, v.y) * (HALF + WALL_T * 0.5)


## Just inside room ri next to door di (where bots aim, where stragglers pop in).
static func door_inside(f: Dictionary, di: int, ri: int, depth: float = 1.0) -> Vector3:
	var d: Dictionary = (f["doors"] as Array)[di]
	var dir: int = int(d["dir"]) if int(d["a"]) == ri else (int(d["dir"]) + 2) % 4
	var v: Vector2i = DIRS[dir]
	return room_center(f, ri) + Vector3(v.x, 0.0, v.y) * (HALF - depth)


## Walkable rectangles: room interiors and open doorways ([min_x, min_z, max_x, max_z, kind], world;
## kind 0 room, 1 a north/south doorway (narrow in x), 2 an east/west one (narrow in z)).
static func walk_rects(f: Dictionary, open_bits: int) -> Array:
	var out: Array = []
	for r in f["rooms"]:
		var c := cell_center((r as Dictionary)["cell"])
		out.append([c.x - HALF, c.z - HALF, c.x + HALF, c.z + HALF, 0])
	var doors: Array = f["doors"]
	for di in doors.size():
		if open_bits & (1 << di) == 0:
			continue
		var m := door_world(f, di)
		var dir: int = int((doors[di] as Dictionary)["dir"])
		var reach := WALL_T * 0.5 + 1.0
		if dir % 2 == 0:
			out.append([m.x - DOOR, m.z - reach, m.x + DOOR, m.z + reach, 1])  # narrow in x
		else:
			out.append([m.x - reach, m.z - DOOR, m.x + reach, m.z + DOOR, 2])  # narrow in z
	return out


## Pillars (world rects) of every room.
static func obstacle_rects(f: Dictionary) -> Array:
	var out: Array = []
	for r in f["rooms"]:
		var c := cell_center((r as Dictionary)["cell"])
		for rect in LAYOUTS[int((r as Dictionary)["layout"])]:
			var a: Array = rect
			out.append([c.x + float(a[0]) - float(a[2]), c.z + float(a[1]) - float(a[3]), c.x + float(a[0]) + float(a[2]), c.z + float(a[1]) + float(a[3])])
	return out


## Can a body of radius rad stand at p? Rooms shrink by the radius on every side; doorways only across.
static func walkable(rects: Array, obstacles: Array, p: Vector3, rad: float) -> bool:
	var inside := false
	for a in rects:
		var q: Array = a
		var k: int = q[4]
		var sx := rad if k != 2 else 0.0
		var sz := rad if k != 1 else 0.0
		if p.x >= float(q[0]) + sx and p.x <= float(q[2]) - sx and p.z >= float(q[1]) + sz and p.z <= float(q[3]) - sz:
			inside = true
			break
	if not inside:
		return false
	for o in obstacles:
		var b: Array = o
		if p.x > float(b[0]) - rad and p.x < float(b[2]) + rad and p.z > float(b[1]) - rad and p.z < float(b[3]) + rad:
			return false
	return true


## Move from -> to as far as walls and pillars allow (slides along them).
static func clamp_move(rects: Array, obstacles: Array, from: Vector3, to: Vector3, rad: float) -> Vector3:
	if walkable(rects, obstacles, to, rad):
		return to
	var a := Vector3(to.x, to.y, from.z)
	if walkable(rects, obstacles, a, rad):
		return a
	var b := Vector3(from.x, to.y, to.z)
	if walkable(rects, obstacles, b, rad):
		return b
	if not walkable(rects, obstacles, from, rad):
		return _nearest_walkable(rects, obstacles, from, rad)
	return Vector3(from.x, to.y, from.z)


## Something got stuck in a wall (a door shut on it): push it to the nearest walkable spot.
static func _nearest_walkable(rects: Array, obstacles: Array, p: Vector3, rad: float) -> Vector3:
	for ring in range(1, 14):
		var d := ring * 0.25
		for k in 8:
			var a := TAU * k / 8.0
			var q := p + Vector3(cos(a), 0.0, sin(a)) * d
			if walkable(rects, obstacles, q, rad):
				return q
	return p


## Keep a monster in its room.
static func room_clamp(f: Dictionary, ri: int, p: Vector3, rad: float) -> Vector3:
	var c := room_center(f, ri)
	p.x = clampf(p.x, c.x - HALF + rad, c.x + HALF - rad)
	p.z = clampf(p.z, c.z - HALF + rad, c.z + HALF - rad)
	return p


## Rooms reachable from the start through passable doors (open_bits), plus a route (list of door ids)
## from room a to room b (empty if none).
static func route(f: Dictionary, a: int, b: int, open_bits: int) -> Array:
	if a == b:
		return []
	var prev := {a: [-1, -1]}
	var q: Array = [a]
	var doors: Array = f["doors"]
	while not q.is_empty():
		var r: int = q.pop_front()
		var ds: Dictionary = ((f["rooms"] as Array)[r] as Dictionary)["doors"]
		for d in ds:
			var id: int = ds[d]
			if open_bits & (1 << id) == 0:
				continue
			var o: int = other_side(doors[id], r)
			if prev.has(o):
				continue
			prev[o] = [r, id]
			if o == b:
				var out: Array = []
				var cur := b
				while cur != a:
					var pr: Array = prev[cur]
					out.push_front(int(pr[1]))
					cur = int(pr[0])
				return out
			q.append(o)
	return []


## Logical solvability: starting with no keys, walking only through doors you can open (locked doors
## take a key found on the way, puzzle doors need their switches' room, secret walls get broken),
## which rooms can be reached? Returns the set (Dictionary room -> true).
static func solve(f: Dictionary) -> Dictionary:
	var doors: Array = f["doors"]
	var rooms: Array = f["rooms"]
	var have := {0: true}
	var keys := 0
	var used := {}
	var changed := true
	var got_key := {}
	while changed:
		changed = false
		for ri in have.keys():
			if bool((rooms[ri] as Dictionary)["key"]) and not got_key.has(ri):
				got_key[ri] = true
				keys += 1
				changed = true
		for di in doors.size():
			var d: Dictionary = doors[di]
			var a := int(d["a"])
			var b := int(d["b"])
			if have.has(a) == have.has(b):
				continue
			var t := int(d["type"])
			var ok := false
			match t:
				OPEN, SECRET:
					ok = true
				PUZZLE:
					ok = true
					for sid in d["switches"]:
						if not have.has(int(((f["switches"] as Array)[sid] as Dictionary)["room"])):
							ok = false
				LOCKED, BOSS:
					if used.has(di):
						ok = true
					elif keys > 0:
						keys -= 1
						used[di] = true
						ok = true
			if ok:
				have[a] = true
				have[b] = true
				changed = true
	return have


## Every real chest on the floor, in a fixed order: [room, local Vector2] (mimics are monsters instead).
static func chest_list(f: Dictionary) -> Array:
	var out: Array = []
	var rooms: Array = f["rooms"]
	for i in rooms.size():
		for ch in (rooms[i] as Dictionary)["chests"]:
			if not bool((ch as Array)[1]):
				out.append([i, (ch as Array)[0]])
	return out


## Every mimic: [room, local Vector2].
static func mimic_list(f: Dictionary) -> Array:
	var out: Array = []
	var rooms: Array = f["rooms"]
	for i in rooms.size():
		for ch in (rooms[i] as Dictionary)["chests"]:
			if bool((ch as Array)[1]):
				out.append([i, (ch as Array)[0]])
	return out


## Every pot: [room, local Vector2].
static func pot_list(f: Dictionary) -> Array:
	var out: Array = []
	var rooms: Array = f["rooms"]
	for i in rooms.size():
		for p in (rooms[i] as Dictionary)["pots"]:
			out.append([i, p])
	return out


## Doors that start open (plain doors); the others open by key, switches or a broken wall.
static func start_open_bits(f: Dictionary) -> int:
	var bits := 0
	var doors: Array = f["doors"]
	for di in doors.size():
		if int((doors[di] as Dictionary)["type"]) == OPEN:
			bits |= 1 << di
	return bits


## Doors of room ri (bits).
static func room_door_bits(f: Dictionary, ri: int) -> int:
	var bits := 0
	if ri < 0 or ri >= (f.get("rooms", []) as Array).size():
		return 0  # (a lock from the previous floor can arrive before the new one: TV/test 26 Oct)
	for d in (((f["rooms"] as Array)[ri] as Dictionary)["doors"] as Dictionary).values():
		bits |= 1 << int(d)
	return bits


# --- Difficulty and fairness (deep.gd uses these; tests/dungeon_delve_floors_test.gd proves them) ---------

## How tough monsters are on a floor. base_hp / base_spd: the difficulty's (deep.gd DIFF), players: how many.
## Everything climbs a little every floor, never in a jump: health and speed grow evenly, and harder hits
## come in gradually (dmg + a chance dmg_p that a monster hits one heart harder). Past the last biome's boss
## (the endless depths) health keeps climbing a bit faster; STONE / SWIFT twists add on top.
static func scaling(base_hp: float, base_spd: float, heroic: bool, zone: int, floor_i: int, players: int, mod: String = "") -> Dictionary:
	var g := float(global_floor(zone, floor_i))
	var past := maxf(0.0, g - float(ZONE_COUNT * FLOORS_PER_ZONE - 1))
	var n := maxi(1, players)
	var e := 0.0
	if heroic:
		e = clampf((g - 1.0) / 8.0, 0.0, 1.0) + clampf((g - 10.0) / 8.0, 0.0, 1.5)
	else:
		e = clampf((g - 6.0) / 10.0, 0.0, 1.0) + clampf((g - 16.0) / 12.0, 0.0, 1.0)
	return {"hp": base_hp * (1.0 + 0.1 * g) * (1.0 + 0.06 * past) * (1.3 if mod == "STONE" else 1.0) * (1.0 + 0.25 * (n - 1)),
		"boss_hp": base_hp * (1.0 + 0.45 * (n - 1)) * (1.0 + 0.12 * minf(float(zone), 8.0)),
		"dmg": int(floor(e)), "dmg_p": e - floor(e),
		"spd": base_spd * (1.0 + 0.03 * minf(g, 16.0)) * (1.2 if mod == "SWIFT" else 1.0)}


## One number for "how hard is a monster here" (health x speed x hits), for the smooth-climb check.
static func strength(s: Dictionary) -> float:
	return float(s["hp"]) * float(s["spd"]) * (1.0 + 0.35 * (float(s["dmg"]) + float(s["dmg_p"])))


## "" if the boss room of floor f is fair, else what's wrong: an open arena (no pillars, traps or biome
## hazards), one boss of the biome, the boss starting well away from the door you come in by, the boss
## door the only way in, and reachable (solve).
static func boss_room_problem(f: Dictionary) -> String:
	var bi := int(f["boss"])
	if bi < 0:
		return "no boss room"
	var r: Dictionary = (f["rooms"] as Array)[bi]
	if int(r["layout"]) != 0:
		return "pillars in the boss room"
	if not (r["traps"] as Array).is_empty() or not (r.get("features", []) as Array).is_empty():
		return "traps in the boss room"
	var fl: Array = r["foes"]
	if fl.size() != 1 or int((fl[0] as Array)[0]) != int(zone_data(int(f["zone"]))["boss"]):
		return "the boss room should hold just the biome's boss"
	var ds: Dictionary = r["doors"]
	if ds.size() != 1:
		return "the boss room has %d doors" % ds.size()
	for d in ds:
		if int(((f["doors"] as Array)[int(ds[d])] as Dictionary)["type"]) != BOSS:
			return "the way into the boss room isn't the boss door"
		if door_local(int(d)).distance_to((fl[0] as Array)[1]) < 3.0:
			return "the boss starts right by the door"
	if not solve(f).has(bi):
		return "the boss room can't be reached"
	return ""
