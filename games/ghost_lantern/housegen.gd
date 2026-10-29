extends RefCounted
## GHOST LANTERN: the seeded haunted house of the day (no nodes, pure data, fast).
##   var house := HouseGen.generate(seed, {"level": houses_played, "daily": false})
##   var plan := HouseGen.night_plan(house, night, crew)   # [{"kind": "snoozy", "hide": 2}, ...]
## A house is Granny Boo's mansion with this visit's HIDING PLACES: wardrobes, trunks, big vases,
## laundry baskets and curtains placed along the walls and on the floor of the library, hall and
## ballroom (plus the grandfather clock, the piano and the fireplace, which are always there), a tint
## for the wallpaper, and which room each night's hiding ghosts like best.
## Ghost kinds, each with one readable behaviour (ghost.gd):
##   plain   WOBBLE: drifts about near the players.
##   snoozy  SNOOZE (nightcap): sleeps in a hiding place (it wobbles and blows bubbles) until the lantern
##           finds it or a TV player bumps it - or it wakes up by itself after a while.
##   sprite  ZIP (bow): zooms about, then stops for a dizzy rest: catch it while it rests.
##   spooker PEEKABOO (witch hat): hides, peeks, pops out with a giggle, floats about, hides again.
##   golden  GOLDIE: shy and quick, flies away from people.
##   king    the GHOST KING (crown): big and slow, vacuum him together (night 5, 10, ...).
## check(house) lists what's wrong (empty = fair): every hiding place inside its room, off the doorways,
## the start corner and the furniture, every floor cell still reachable from the start (no closed-off
## pockets), every hiding place reachable on foot (a TV player can bump it) and in sight of the lantern
## from somewhere reachable, and every night plan (crews 1..7) fair: known kinds, each hiding ghost in
## its own valid hiding place, everyone comes out by themselves in time, every ghost catchable alone
## (lantern slurp) and with vacuums, more hunters never means fewer ghosts, and night 1 stays gentle.
## Network: the host sends [seed, level, daily]; every machine rebuilds the same house.

const Seeded := preload("res://core/seeded.gd")

const HALF_X := 21.0
const HALF_Z := 8.0
const ROOMS := {"library": [-21.0, -7.0], "hall": [-7.0, 7.0], "ballroom": [7.0, 21.0]}
const ROOM_ORDER: Array[String] = ["library", "hall", "ballroom"]
const START := Vector3(0.0, 0.0, 3.0)
const CELL := 0.5
const BODY_R := 0.35  # player capsule radius (player.gd)
const NX := 84
const NZ := 32

## The mansion's own furniture, as floor rectangles [x0, z0, x1, z1, top height, solid].
## solid: players bump into it (world.gd box(..., collide = true)); otherwise it's only something a
## hiding place must not stand in. The bot checks world.gd's collision boxes all sit inside these.
const FIXED: Array = [
	[6.85, -8.0, 7.15, -1.6, 4.2, true], [6.85, 1.6, 7.15, 8.0, 4.2, true],  # walls between the rooms
	[-7.15, -8.0, -6.85, -1.6, 4.2, true], [-7.15, 1.6, -6.85, 8.0, 4.2, true],
	[-1.55, 6.45, 1.55, 7.6, 1.2, true],  # hall: the sofa
	[-5.2, 6.2, -4.4, 7.0, 0.8, true], [4.4, 6.2, 5.2, 7.0, 0.8, true],  # side tables
	[-6.65, -6.75, -5.95, -6.25, 2.5, true],  # grandfather clock
	[-2.5, -8.0, 2.5, -7.35, 2.5, true],  # Granny Boo's jar shelf (museum.gd)
	[-21.0, -6.6, -20.4, -3.4, 3.2, true], [-21.0, 3.4, -20.4, 6.6, 3.2, true],  # library: bookshelves
	[-21.0, -1.2, -20.4, 1.2, 1.6, true],  # fireplace
	[-15.1, -2.6, -12.9, -1.4, 0.82, true],  # reading table
	[-17.5, 2.5, -16.5, 3.6, 1.25, true],  # armchair
	[13.0, -6.4, 15.0, -4.8, 1.6, true],  # ballroom: the piano
	[10.75, 7.05, 11.25, 7.6, 0.5, true], [12.25, 7.05, 12.75, 7.6, 0.5, true],  # seats
	[15.25, 7.05, 15.75, 7.6, 0.5, true], [16.75, 7.05, 17.25, 7.6, 0.5, true],
	[19.05, -1.0, 19.95, 1.0, 0.84, true],  # punch table
	# Not solid (walk-through decorations), but no hiding place stands on them:
	[8.6, -5.9, 9.4, -5.1, 4.2, false], [18.6, -5.9, 19.4, -5.1, 4.2, false],  # pillars
	[8.6, 5.1, 9.4, 5.9, 4.2, false], [18.6, 5.1, 19.4, 5.9, 4.2, false],
	[-11.5, 3.9, -10.5, 5.1, 1.4, false],  # rocking chair
	[-9.4, -6.4, -8.6, -5.6, 1.5, false],  # globe
	[5.9, 6.6, 6.5, 7.2, 1.9, false],  # coat stand
	[-3.7, -7.7, -2.3, -5.9, 2.2, false],  # Granny Boo floats here, by her shelf (museum.gd GRANNY_AT)
	[-4.4, 1.0, 4.4, 7.2, 2.0, false],  # the start corner: the touchable props and the players
	[-8.8, -2.4, -5.2, 2.4, 2.7, false], [5.2, -2.4, 8.8, 2.4, 2.7, false],  # keep the doorways clear
]

## Hiding places: size (width along the wall, depth), height, where the ghost peeks out (height), whether
## it stands against a wall, solid (players bump into it), top (the ghost peeks over the rim, not out of the front).
const KINDS := {
	"wardrobe": {"w": 1.3, "d": 0.65, "h": 2.2, "peek": 1.3, "wall": true, "solid": true},
	"trunk": {"w": 1.1, "d": 0.65, "h": 0.65, "peek": 0.8, "wall": false, "solid": true, "top": true},
	"vase": {"w": 0.6, "d": 0.6, "h": 1.1, "peek": 1.3, "wall": false, "solid": true, "top": true},
	"basket": {"w": 0.8, "d": 0.8, "h": 0.7, "peek": 0.9, "wall": false, "solid": true, "top": true},
	"curtain": {"w": 1.7, "d": 0.3, "h": 3.0, "peek": 1.4, "wall": true, "solid": false},
	# Always there (world.gd): the grandfather clock, the piano and the fireplace.
	"clock": {"w": 0.7, "d": 0.45, "h": 2.5, "peek": 1.6, "wall": true, "solid": true, "fixed": true},
	"piano": {"w": 2.0, "d": 1.5, "h": 1.6, "peek": 1.2, "wall": true, "solid": true, "fixed": true},
	"fireplace": {"w": 2.4, "d": 0.6, "h": 1.6, "peek": 0.7, "wall": true, "solid": true, "fixed": true},
}
const PLACED: Array[String] = ["wardrobe", "trunk", "vase", "basket", "curtain"]
const FIXED_SPOTS: Array = [
	{"kind": "clock", "room": "hall", "pos": Vector3(-6.3, 0.0, -6.5), "yaw": 0.0},
	{"kind": "piano", "room": "ballroom", "pos": Vector3(14.0, 0.0, -5.6), "yaw": 0.0},
	{"kind": "fireplace", "room": "library", "pos": Vector3(-20.7, 0.0, 0.0), "yaw": PI / 2.0},
]
const WINDOWS: Array[float] = [-17.0, -11.0, -3.5, 3.5, 11.0, 17.0]

## Ghost kinds and the numbers ghost.gd plays them with (seconds): how long a hiding ghost waits before
## it comes out by itself, how long a caught-alone (solo lantern) catch takes at most.
const GHOSTS: Array[String] = ["plain", "snoozy", "sprite", "spooker", "golden", "king"]
const HIDERS: Array[String] = ["snoozy", "spooker"]
const WAKE_MAX := 30.0  # a snoozy ghost nobody finds wakes up by itself
const PEEK_MAX := 12.0  # a peekaboo ghost pops out at least this often
const TOUGH := {"plain": 0.8, "snoozy": 0.7, "sprite": 0.7, "spooker": 1.4, "golden": 0.8, "king": 2.5}
const VAC_RATE := 0.6  # main.gd CAPTURE_RATE (per second, one vacuum)
const SOLO_RATE := 0.55  # ghost.gd: a dizzy ghost slurped into the lantern
const LANTERN_SEE := 9.0  # the lantern (11 m) lights a hiding place from this far for sure
const MAX_GHOSTS := 14  # never more ghosts in one night than this

## Colours for the wallpaper (world.gd WALL_SHADER tint) - a cosy palette.
const TINTS: Array[Color] = [Color(1.0, 1.0, 1.0), Color(0.85, 1.0, 0.9), Color(1.0, 0.88, 0.95), Color(0.9, 0.92, 1.1),
	Color(1.08, 0.98, 0.82), Color(0.95, 0.86, 1.08)]
const NAMES: Array[String] = ["MOONBEAM MANOR", "CREAKY HALL", "PUMPKIN HOUSE", "WHISPER LODGE", "COBWEB COTTAGE",
	"STARLIGHT MANSION", "TEAPOT TOWERS", "BUBBLE MANOR", "SLEEPY HOLLOW HOUSE", "LANTERN LODGE"]

static var _free_cache: PackedByteArray = PackedByteArray()


## A house. opts: level (houses played: more hiding places as the family gets the hang of it), daily.
static func generate(seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var level := int(opts.get("level", 0))
	var daily := bool(opts.get("daily", false))
	if daily:
		level = 3  # TODAY'S HOUSE is the same for everyone
	var r := Seeded.rng(seed_value, "house")
	var want := clampi(3 + level, 3, 6)  # placed hiding places
	var spots: Array = []
	for f in FIXED_SPOTS:
		var s: Dictionary = f.duplicate()
		s["peek"] = _peek_point(s)
		spots.append(s)
	var tries := 0
	# One placed hiding place per room first (so every room has something to find), then anywhere.
	var rooms := Seeded.shuffled(r, ROOM_ORDER)
	var walk := walk_grid(spots)
	var reach := flood(walk)
	while spots.size() - FIXED_SPOTS.size() < want and tries < 200:
		tries += 1
		var placed := spots.size() - FIXED_SPOTS.size()
		var room: String = rooms[placed] if placed < 3 else Seeded.pick(r, ROOM_ORDER)
		var kind: String = PLACED[Seeded.weighted(r, [3, 3, 2, 2, 2])]
		var s := _candidate(r, kind, room)
		if s.is_empty() or spot_problem(s, spots) != "":
			continue
		var walk2 := walk
		var reach2 := reach
		if bool(KINDS[kind].solid):
			walk2 = walk.duplicate()
			_stamp(walk2, s)
			reach2 = flood(walk2)
			if reach2.has(1):
				continue  # it would shut some floor in
		var trial := spots.duplicate()
		trial.append(s)
		if access_problem(s, trial, reach2) != "":
			continue
		spots.append(s)
		walk = walk2
		reach = reach2
	var nr := Seeded.rng(seed_value, "nights")
	var room_cycle: Array = ["hall"] + Seeded.shuffled(nr, ["library", "ballroom"])
	return {
		"seed": seed_value, "level": level, "daily": daily,
		"name": NAMES[Seeded.rng(seed_value, "name").randi() % NAMES.size()],
		"tint": TINTS[Seeded.rng(seed_value, "tint").randi() % TINTS.size()],
		"spots": spots, "rooms": room_cycle,
	}


## Which room the hiding ghosts like best on `night` (1: the hall, near the start; then around the house).
static func room_for(house: Dictionary, night: int) -> String:
	var rc: Array = house.rooms
	return String(rc[(night - 1) % rc.size()])


## The ghosts of one night for a crew (players, lantern-bearer included), in spawn order. Hiding ghosts
## carry the index of their hiding place ("hide"); the rest float in through the ceiling (hide -1).
## More hunters bring a few more plain ghosts (appended, so the rest of the night stays the same).
static func night_plan(house: Dictionary, night: int, crew: int = 2) -> Array:
	var n := maxi(1, night)
	var counts := {}
	match n:
		1: counts = {"plain": 2, "snoozy": 1}
		2: counts = {"plain": 2, "sprite": 2, "snoozy": 1}
		3: counts = {"plain": 2, "sprite": 1, "spooker": 2, "snoozy": 1}
		4: counts = {"plain": 3, "sprite": 1, "spooker": 1, "snoozy": 1, "golden": 1}
		_:
			var k := n - 5
			counts = {"plain": mini(2 + k / 2, 4), "sprite": mini(1 + k / 3, 2), "spooker": mini(1 + k / 3, 2),
				"snoozy": mini(1 + k / 2, 3), "golden": 1 if n % 2 == 0 else 0}
	var r := Seeded.rng(int(house.seed), "night%d" % n)
	var list: Array = []
	for kind in GHOSTS:
		for i in int(counts.get(kind, 0)):
			list.append(kind)
	list = Seeded.shuffled(r, list)
	# Hiding places: the night's room first, then the others; each hiding ghost has its own.
	var fav := room_for(house, n)
	var order: Array = []
	var others: Array = []
	for i in (house.spots as Array).size():
		if String(house.spots[i].room) == fav:
			order.append(i)
		else:
			others.append(i)
	order = Seeded.shuffled(r, order) + Seeded.shuffled(r, others)
	var plan: Array = []
	var used := 0
	for kind in list:
		var hide := -1
		if kind in HIDERS and used < order.size():
			hide = int(order[used])
			used += 1
		plan.append({"kind": kind, "hide": hide})
	for i in crowd_extra(crew):
		plan.append({"kind": "plain", "hide": -1})
	if plan.size() > MAX_GHOSTS:
		plan.resize(MAX_GHOSTS)
	return plan


## Extra plain ghosts for a big crew (beyond the lantern-bearer and two vacuums: one per two hunters).
static func crowd_extra(crew: int) -> int:
	return maxi(0, crew - 3) / 2


## Is the GHOST KING visiting on `night`?
static func king_night(night: int) -> bool:
	return night % 5 == 0


## Where a ghost peeks out of hiding place `s`: in front of it, at its peek height.
static func _peek_point(s: Dictionary) -> Vector3:
	var k: Dictionary = KINDS[s.kind]
	var fwd := Vector3(sin(float(s.yaw)), 0.0, cos(float(s.yaw)))  # yaw 0 faces +z (into the room from the north wall)
	var out := float(k.d) * 0.5 + (0.35 if bool(k.solid) else 0.15)
	var p: Vector3 = Vector3(s.pos) + fwd * out
	p.y = float(k.peek)
	return p


## Where a ghost hides inside hiding place `s` (the middle of it, a little above the floor).
static func hide_point(s: Dictionary) -> Vector3:
	var k: Dictionary = KINDS[s.kind]
	return Vector3(s.pos) + Vector3.UP * clampf(float(k.h) * 0.55, 0.4, 1.3)


## Where a hiding ghost's eyes peek out: over the rim (top) or at the front, at peek height.
static func eyes_point(s: Dictionary) -> Vector3:
	var k: Dictionary = KINDS[s.kind]
	if bool(k.get("top", false)):
		return Vector3(s.pos) + Vector3.UP * (float(k.h) + 0.08)
	var fwd := Vector3(sin(float(s.yaw)), 0.0, cos(float(s.yaw)))
	return Vector3(s.pos) + fwd * (float(k.d) * 0.5 + 0.04) + Vector3.UP * minf(float(k.peek), float(k.h) - 0.2)


## A random hiding place of `kind` in `room` (empty if this try didn't work out).
static func _candidate(r: RandomNumberGenerator, kind: String, room: String) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var xr: Array = ROOMS[room]
	var x0 := float(xr[0]) + 0.6
	var x1 := float(xr[1]) - 0.6
	var pos := Vector3.ZERO
	var yaw := 0.0
	var at_wall: bool = bool(k.wall) or r.randf() < 0.6
	if kind == "curtain":
		var wins: Array = WINDOWS.filter(func(x: float) -> bool: return x > x0 and x < x1)
		pos = Vector3(float(Seeded.pick(r, wins)), 0.0, -HALF_Z + float(k.d) * 0.5)
		yaw = 0.0
	elif at_wall:
		var side := r.randi() % (3 if room != "hall" else 2)
		var half := float(k.d) * 0.5 + 0.02
		if side == 0:  # north wall, facing south
			pos = Vector3(r.randf_range(x0, x1), 0.0, -HALF_Z + half)
			yaw = 0.0
		elif side == 1:  # south wall, facing north
			pos = Vector3(r.randf_range(x0, x1), 0.0, HALF_Z - half)
			yaw = PI
		else:  # the end wall (library west, ballroom east)
			var west := room == "library"
			pos = Vector3((-HALF_X + half) if west else (HALF_X - half), 0.0, r.randf_range(-6.6, 6.6))
			yaw = PI / 2.0 if west else -PI / 2.0
	else:
		pos = Vector3(r.randf_range(x0 + 1.0, x1 - 1.0), 0.0, r.randf_range(-6.0, 6.0))
		yaw = float(r.randi() % 4) * PI / 2.0
	pos.x = snappedf(pos.x, 0.05)
	pos.z = snappedf(pos.z, 0.05)
	var s := {"kind": kind, "room": room, "pos": pos, "yaw": yaw}
	s["peek"] = _peek_point(s)
	return s


## The floor rectangle [x0, z0, x1, z1] a hiding place covers.
static func rect_of(s: Dictionary) -> Array:
	var k: Dictionary = KINDS[s.kind]
	var across := absf(cos(float(s.yaw))) > 0.5  # facing north/south: the width runs along x
	var hx := (float(k.w) if across else float(k.d)) * 0.5
	var hz := (float(k.d) if across else float(k.w)) * 0.5
	var p: Vector3 = s.pos
	return [p.x - hx, p.z - hz, p.x + hx, p.z + hz]


static func _overlap(a: Array, b: Array, pad: float = 0.0) -> bool:
	return a[0] < float(b[2]) + pad and a[2] > float(b[0]) - pad and a[1] < float(b[3]) + pad and a[3] > float(b[1]) - pad


## Why hiding place `s` can't stand there ("" = fine): outside its room, on furniture, on a doorway or
## the start corner, or too close to another hiding place.
static func spot_problem(s: Dictionary, spots: Array) -> String:
	if bool(KINDS[s.kind].get("fixed", false)):
		return ""
	var rc := rect_of(s)
	var xr: Array = ROOMS[s.room]
	var lo := float(xr[0]) + (0.17 if absf(float(xr[0])) < HALF_X - 0.1 else 0.0)
	var hi := float(xr[1]) - (0.17 if absf(float(xr[1])) < HALF_X - 0.1 else 0.0)
	if float(rc[0]) < lo or float(rc[2]) > hi:
		return "%s sticks out of the %s" % [s.kind, s.room]
	if rc[0] < -HALF_X or rc[2] > HALF_X or rc[1] < -HALF_Z or rc[3] > HALF_Z:
		return "%s goes through the outside wall" % s.kind
	for f in FIXED:
		var wall := float(f[2]) - float(f[0]) < 0.35 or float(f[3]) - float(f[1]) < 0.35
		if _overlap(rc, f, 0.15 if wall else 0.55):  # room to see it (not tucked behind a table)
			return "%s stands on furniture at %s" % [s.kind, str(Vector2(float(f[0]), float(f[1])))]
	for o in spots:
		if o == s:
			continue
		var orc := rect_of(o)
		if _overlap(rc, orc, 0.9):
			return "%s is squashed against a %s" % [s.kind, o.kind]
	if s.kind != "curtain" and float(KINDS[s.kind].h) > 1.2 and float(s.pos.z) < -HALF_Z + 1.0:
		for wx in WINDOWS:
			if absf(float(s.pos.x) - wx) < float(KINDS[s.kind].w) * 0.5 + 0.75:
				return "%s stands in front of a window" % s.kind
	var pk: Vector3 = s.peek
	if absf(pk.x) > HALF_X - 0.2 or absf(pk.z) > HALF_Z - 0.2:
		return "%s peeks out of the house" % s.kind
	return ""


## Floor cells players can stand on: 1 = free. Indexed [ix * NZ + iz], cell centres at
## (-HALF_X + (ix + 0.5) * CELL, -HALF_Z + (iz + 0.5) * CELL).
static func walk_grid(spots: Array) -> PackedByteArray:
	if _free_cache.is_empty():
		_free_cache.resize(NX * NZ)
		for ix in NX:
			for iz in NZ:
				var c := cell_pos(ix, iz)
				var ok := absf(c.x) < HALF_X - BODY_R and absf(c.y) < HALF_Z - BODY_R
				if ok:
					for f in FIXED:
						if bool(f[5]) and _in_rect(c, f, BODY_R):
							ok = false
							break
				_free_cache[ix * NZ + iz] = 1 if ok else 0
	var g := _free_cache.duplicate()
	for s in spots:
		_stamp(g, s)
	return g


## Mark the floor a solid hiding place stands on (with room for a player's body) as blocked.
static func _stamp(g: PackedByteArray, s: Dictionary) -> void:
	if not bool(KINDS[s.kind].solid) or bool(KINDS[s.kind].get("fixed", false)):
		return
	var rc := rect_of(s)
	var ix0 := maxi(0, int(floor((float(rc[0]) - BODY_R + HALF_X) / CELL)))
	var ix1 := mini(NX - 1, int(floor((float(rc[2]) + BODY_R + HALF_X) / CELL)))
	var iz0 := maxi(0, int(floor((float(rc[1]) - BODY_R + HALF_Z) / CELL)))
	var iz1 := mini(NZ - 1, int(floor((float(rc[3]) + BODY_R + HALF_Z) / CELL)))
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			if _in_rect(cell_pos(ix, iz), rc, BODY_R):
				g[ix * NZ + iz] = 0


static func cell_pos(ix: int, iz: int) -> Vector2:
	return Vector2(-HALF_X + (ix + 0.5) * CELL, -HALF_Z + (iz + 0.5) * CELL)


static func _in_rect(p: Vector2, rc: Array, pad: float) -> bool:
	return p.x > float(rc[0]) - pad and p.x < float(rc[2]) + pad and p.y > float(rc[1]) - pad and p.y < float(rc[3]) + pad


## Flood fill from the start: 2 = reachable.
static func flood(g: PackedByteArray) -> PackedByteArray:
	var out := g.duplicate()
	var start := int((START.x + HALF_X) / CELL) * NZ + int((START.z + HALF_Z) / CELL)
	if out[start] != 1:
		return out
	out[start] = 2
	var stack := PackedInt32Array([start])
	var n := 1
	while n > 0:
		n -= 1
		var i: int = stack[n]
		var iz := i % NZ
		# Neighbours: x +- 1 (i +- NZ), z +- 1 (i +- 1, same column only).
		var j := i + NZ
		if j < NX * NZ and out[j] == 1:
			out[j] = 2
			if n < stack.size():
				stack[n] = j
			else:
				stack.append(j)
			n += 1
		j = i - NZ
		if j >= 0 and out[j] == 1:
			out[j] = 2
			if n < stack.size():
				stack[n] = j
			else:
				stack.append(j)
			n += 1
		if iz + 1 < NZ and out[i + 1] == 1:
			out[i + 1] = 2
			if n < stack.size():
				stack[n] = i + 1
			else:
				stack.append(i + 1)
			n += 1
		if iz > 0 and out[i - 1] == 1:
			out[i - 1] = 2
			if n < stack.size():
				stack[n] = i - 1
			else:
				stack.append(i - 1)
			n += 1
	return out


## Why a hiding place can't be found ("" = fine): no reachable floor next to it (a TV player bumps it,
## a vacuum reaches its ghost) or nowhere reachable the lantern can light it from.
static func access_problem(s: Dictionary, spots: Array, reach: PackedByteArray = PackedByteArray()) -> String:
	var g := reach if not reach.is_empty() else flood(walk_grid(spots))
	var pk: Vector3 = s.peek
	var at := Vector2(pk.x, pk.z)
	var cx := int(floor((pk.x + HALF_X) / CELL))
	var cz := int(floor((pk.z + HALF_Z) / CELL))
	var near := false
	for o in _rings():
		var ix: int = cx + int(o[0])
		var iz: int = cz + int(o[1])
		if ix < 0 or ix >= NX or iz < 0 or iz >= NZ or g[ix * NZ + iz] != 2:
			continue
		var c := cell_pos(ix, iz)
		var d := c.distance_to(at)
		if d < 1.6:
			near = true
		if d > 0.8 and d < LANTERN_SEE and _clear_sight(c, at, s, spots):
			return "" if near else "%s in the %s can't be reached on foot" % [s.kind, s.room]
	if not near:
		return "%s in the %s can't be reached on foot" % [s.kind, s.room]
	return "%s in the %s can't be lit by the lantern" % [s.kind, s.room]


static var _ring_cache: Array = []


## Cell offsets within LANTERN_SEE, nearest first (so the search stops early).
static func _rings() -> Array:
	if _ring_cache.is_empty():
		var r := int(ceil(LANTERN_SEE / CELL)) + 1
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if Vector2(dx, dz).length() * CELL <= LANTERN_SEE + CELL:
					_ring_cache.append([dx, dz, dx * dx + dz * dz])
		_ring_cache.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
	return _ring_cache


## A lantern held at chest height sees from a to b unless a tall thing (walls, shelves, wardrobes, the
## clock) stands in between.
static func _clear_sight(a: Vector2, b: Vector2, own: Dictionary, spots: Array) -> bool:
	var steps := int(a.distance_to(b) / 0.25)
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		for f in FIXED:
			if bool(f[5]) and float(f[4]) > 1.3 and _in_rect(p, f, 0.0):
				return false
		for o in spots:
			if o != own and float(KINDS[o.kind].h) > 1.3 and _in_rect(p, rect_of(o), 0.0):
				return false
	return true


## How long (seconds) catching a ghost of `kind` takes at most: alone (the lantern slurps a dizzy ghost)
## or with one vacuum.
static func catch_time(kind: String, solo: bool) -> float:
	return float(TOUGH[kind]) / (SOLO_RATE if solo else VAC_RATE)


## Everything wrong with a house (empty = fair).
static func check(house: Dictionary) -> Array:
	var why: Array = []
	var spots: Array = house.spots
	var placed := 0
	var by_room := {}
	for s in spots:
		if not KINDS.has(s.kind):
			why.append("unknown hiding place %s" % s.kind)
			continue
		if not bool(KINDS[s.kind].get("fixed", false)):
			placed += 1
			by_room[s.room] = true
		var p := spot_problem(s, spots)
		if p != "":
			why.append(p)
	if placed < 3:
		why.append("only %d hiding places" % placed)
	if by_room.size() < 3:
		why.append("a room has no hiding place (%s)" % str(by_room.keys()))
	var walk := walk_grid(spots)
	var fl := flood(walk)
	if fl.has(1):
		why.append("%d floor cells are shut in" % fl.count(1))
	for s in spots:
		var a := access_problem(s, spots, fl)
		if a != "":
			why.append(a)
	if String(house.rooms[0]) != "hall" or (house.rooms as Array).size() != 3:
		why.append("the first night isn't in the hall")
	for night in range(1, 11):
		var last := -1
		for crew in range(1, 8):
			var plan := night_plan(house, night, crew)
			if plan.size() < last:
				why.append("night %d: %d hunters get fewer ghosts than %d" % [night, crew, crew - 1])
			last = plan.size()
			for w in plan_problems(house, night, crew, plan):
				why.append(w)
	return why


## What's unfair about one night's plan for a crew (empty = fine).
static func plan_problems(house: Dictionary, night: int, crew: int, plan: Array) -> Array:
	var why: Array = []
	var used := {}
	var hiders := 0
	for g in plan:
		var kind := String(g.kind)
		if not kind in GHOSTS or kind == "king":
			why.append("night %d: unknown ghost %s" % [night, kind])
			continue
		var hide := int(g.hide)
		if kind in HIDERS:
			hiders += 1
			if hide < 0 or hide >= (house.spots as Array).size():
				why.append("night %d: a %s has no hiding place" % [night, kind])
			elif used.has(hide):
				why.append("night %d: two ghosts in the same %s" % [night, house.spots[hide].kind])
			used[hide] = true
		elif hide != -1:
			why.append("night %d: a %s can't hide" % [night, kind])
		if catch_time(kind, true) > 6.0 or catch_time(kind, false) > 4.0:
			why.append("night %d: a %s takes too long to catch" % [night, kind])
	if king_night(night) and (catch_time("king", true) > 6.0 or catch_time("king", false) > 5.0):
		why.append("night %d: the king can't be caught alone" % night)
	if plan.size() > MAX_GHOSTS:
		why.append("night %d: %d ghosts is too many" % [night, plan.size()])
	var hunters := maxi(1, crew)
	if float(plan.size()) / float(hunters) > 6.0 and crew > 1:
		why.append("night %d: %d ghosts for %d hunters" % [night, plan.size(), crew])
	if crew == 1 and plan.size() > 12:
		why.append("night %d: too many ghosts for one lantern (%d)" % [night, plan.size()])
	if night == 1 and (plan.size() > 3 + crowd_extra(crew) or hiders > 1):
		why.append("night 1 isn't gentle (%d ghosts, %d hiding)" % [plan.size(), hiders])
	if maxf(WAKE_MAX, PEEK_MAX) > 40.0:
		why.append("hiding ghosts stay hidden too long")
	return why


## The new thing on each night (Granny Boo's story card): [picture, line].
static func night_story(night: int) -> Array:
	match night:
		1: return ["snoozy", "Shh! One is asleep."]
		2: return ["zippy", "Zip is so fast!"]
		3: return ["peekaboo", "Peekaboo likes to hide!"]
		4: return ["goldie", "Goldie is here!"]
		5: return ["kingghost", "The Ghost King!"]
		6: return ["sun", "Last night! Then sunrise."]
	return ["jar", "More jars, please!"]
