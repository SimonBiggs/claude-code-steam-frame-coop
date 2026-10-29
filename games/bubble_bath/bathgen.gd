extends RefCounted
## BUBBLE BATH generator: every round's bath (where the plug-hole is, the sponge islands boats sail round, where the
## ducks pop up, where each boat starts, when golden ducks come and the team's duck goal) as plain data from a seed,
## so the host and every TV machine build the same bath from [bath seed, round] and tests/bubble_bath_gen_test.gd
## proves over many seeds that every round is fair and finishable by one small kid sailing slowly on their own.
##   var plan := BathGen.plan(bath_seed, round_n)
##   plan = {n, drain: Vector2 (x, z), islands: [Vector3(x, z, r)...], spots: [Vector2...] (duck spots, used in order),
##           starts: [Vector2...] (boat start per slot % 8), golden: [Vector2(when 0..1 of the round, spot index)...],
##           goal: ducks for a 2-minute round, tint: bubble colour index}
## Story: MAMA DUCK sits on the far rim. Every round the team reaches the goal puts a bath TOY on the side rim (saved),
## a duckling joins her family on the rim each play-day, and with ten toys she wears a crown. TODAY'S BATH: the first
## bath each day uses the day's seed on every machine and its toys get a gold star.
## check(plan) is the validator: round 1 is the plain old bath (plug in the middle, no islands, no golden ducks), one
## new thing at a time (2: a sponge island, 3: the plug moves and a golden duck comes, 4+: more islands), the plug is
## inside the VR splasher's throw and away from the walls and the tap, islands never pinch a channel too narrow for a
## boat or sit on the plug's whirlpool, duck spots and boat starts are clear of everything and spread round the tub,
## every spot, start and the plug are reachable by boat (grid search round the islands), and one small kid sailing at
## KID_SPEED bringing one duck at a time reaches the goal in well under the round's time.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "bubble_bath"
const HX := 4.2  # == main.gd
const HZ := 2.7  # == main.gd
const DRAIN_R := 0.55  # == main.gd
const BOAT_R := 0.3  # == main.gd
const DUCK_R := 0.17  # == main.gd
const TAP := Vector3(-1.1, 0.0, 2.85)  # == main.gd (the spout drops ducks just inside the near wall)
const ROUND_SECS := 120.0  # == main.gd round_time
const DRAIN_BOX := Rect2(-2.4, -1.2, 4.8, 2.1)  # x, z: inside the VR splasher's throw, a metre+ from every wall
const ISLAND_R := Vector2(0.32, 0.55)
const WHIRL := 1.4  # the plug's whirlpool: no islands, spots or starts this close
const SPOTS := 16
const STARTS := 8
const CELL := 0.15  # path grid
const KID_SPEED := 0.9  # m/s: a small kid sailing slowly (boats go up to 2.8)
const KID_FUMBLE := 1.5  # s lost per duck (turning, bumping, missing it)
const GOAL_SHARE := 0.75  # the slow solo kid (one duck a trip, no golden ducks) must manage the goal in this share of the round
const MAX_ROUND := 12  # the validator's reach (later rounds repeat round 12's rules)
const TINTS := 5

## Bath toys (one per round the goal is reached), in order, then round and round.
const TOYS: Array[String] = ["boat", "beachball", "starfish", "whale", "soapbar", "fish"]
const TOY_KEEP := 12  # toys on the side rim (the oldest makes room)
const DUCKLINGS_MAX := 12  # one per play-day, beside Mama Duck
const CROWN_TOYS := 10  # Mama Duck's crown


## The day's bath seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


static func round_seed(bath_seed: int, n: int) -> int:
	return Seeded.derive(bath_seed, "round%d" % n)


## How many sponge islands round n has.
static func island_count(n: int, rng: RandomNumberGenerator = null) -> int:
	if n <= 1:
		return 0
	if n <= 3:
		return 1
	if n == 4:
		return 2
	return 2 + (1 if rng != null and rng.randf() < 0.5 else 0) if n < 7 else 3


## How many golden ducks come in round n.
static func golden_count(n: int) -> int:
	return 0 if n <= 2 else (1 if n <= 5 else 2)


## The team's duck goal for a full 2-minute round (main.gd scales it for shorter rounds).
static func goal_for(n: int) -> int:
	return mini(3 + n, 8)


## The toy the k-th goal (0-based, over all days) puts on the rim.
static func toy_for(k: int) -> String:
	return TOYS[posmod(k, TOYS.size())]


static func plan(bath_seed: int, n: int) -> Dictionary:
	n = maxi(1, n)
	var rng := Seeded.rng(round_seed(bath_seed, n), "bath")
	var p := {"n": n, "goal": goal_for(n), "tint": rng.randi() % TINTS}
	# The plug: in the middle for rounds 1-2, then anywhere in the drain box.
	var drain := Vector2.ZERO
	if n >= 3:
		drain = Vector2(snappedf(rng.randf_range(DRAIN_BOX.position.x, DRAIN_BOX.end.x), 0.01), snappedf(rng.randf_range(DRAIN_BOX.position.y, DRAIN_BOX.end.y), 0.01))
		if drain.distance_to(Vector2(TAP.x, TAP.z)) < 2.0:
			drain.y = DRAIN_BOX.position.y  # away from the tap's spout
	p.drain = drain
	var islands: Array = []
	var want := island_count(n, rng)
	var tries := 0
	while islands.size() < want and tries < 400:
		tries += 1
		var big := lerpf(ISLAND_R.y, ISLAND_R.x, minf(1.0, tries / 200.0))  # a crowded bath gets smaller islands
		var o := Vector3(snappedf(rng.randf_range(-HX + 1.0, HX - 1.0), 0.01), snappedf(rng.randf_range(-HZ + 0.9, HZ - 0.9), 0.01),
			snappedf(rng.randf_range(ISLAND_R.x, big), 0.01))
		if _island_ok(Vector2(o.x, o.y), o.z, p.drain, islands).is_empty():  # (checked as stored, like check() sees it)
			islands.append(o)
	p.islands = islands
	# Duck spots: one from each quarter of the tub in turn, so ducks come everywhere.
	var spots: Array = []
	tries = 0
	while spots.size() < SPOTS and tries < 400:
		tries += 1
		var q := spots.size() % 4
		var sx := -1.0 if q % 2 == 0 else 1.0
		var sz := -1.0 if q < 2 else 1.0
		var s := Vector2(sx * rng.randf_range(0.2, HX - 0.45), sz * rng.randf_range(0.2, HZ - 0.45))
		s = Vector2(snappedf(s.x, 0.01), snappedf(s.y, 0.01))
		if _spot_ok(s, p.drain, islands).is_empty():
			spots.append(s)
	p.spots = spots
	# Boat starts: round the plug, one direction per slot.
	var starts: Array = []
	for k in STARTS:
		var a := k * TAU / STARTS + rng.randf_range(-0.3, 0.3)
		var placed := false
		for r in [1.9, 2.2, 1.6, 2.5, 1.45, 2.8, 3.2]:
			var s: Vector2 = p.drain + Vector2(cos(a) * r * 1.3, sin(a) * r * 0.8)
			s = Vector2(snappedf(clampf(s.x, -HX + 0.5, HX - 0.5), 0.01), snappedf(clampf(s.y, -HZ + 0.5, HZ - 0.5), 0.01))
			if _start_ok(s, p.drain, islands, starts).is_empty():
				starts.append(s)
				placed = true
				break
		if not placed:
			for _i in 60:
				var s := Vector2(snappedf(rng.randf_range(-HX + 0.5, HX - 0.5), 0.01), snappedf(rng.randf_range(-HZ + 0.5, HZ - 0.5), 0.01))
				if _start_ok(s, p.drain, islands, starts).is_empty():
					starts.append(s)
					break
	p.starts = starts
	var golden: Array = []
	for i in golden_count(n):
		var when := snappedf(rng.randf_range(0.15, 0.35) + i * 0.3, 0.01)
		golden.append(Vector2(when, rng.randi() % maxi(1, spots.size())))
	p.golden = golden
	return p


static func _island_ok(c: Vector2, r: float, drain: Vector2, islands: Array) -> Array[String]:
	var why: Array[String] = []
	var gap := BOAT_R * 2.0 + 0.2  # a boat fits through every channel with room to spare
	if absf(c.x) + r > HX - gap or absf(c.y) + r > HZ - gap:
		why.append("an island at (%.1f, %.1f) pinches the channel by the wall" % [c.x, c.y])
	if c.distance_to(drain) < r + WHIRL:
		why.append("an island sits on the plug's whirlpool")
	if c.distance_to(Vector2(TAP.x, TAP.z - 0.8)) < r + 0.6:
		why.append("an island sits under the tap")
	for o in islands:
		var oc := Vector2(o.x, o.y)
		if c.distance_to(oc) < r + float(o.z) + gap:
			why.append("two islands pinch the channel between them")
	return why


static func _spot_ok(s: Vector2, drain: Vector2, islands: Array) -> Array[String]:
	var why: Array[String] = []
	if absf(s.x) > HX - 0.4 or absf(s.y) > HZ - 0.4:
		why.append("a duck spot hugs the wall (%.1f, %.1f)" % [s.x, s.y])
	if s.distance_to(drain) < WHIRL:
		why.append("a duck spot is in the plug's whirlpool")
	for o in islands:
		if s.distance_to(Vector2(o.x, o.y)) < float(o.z) + DUCK_R + 0.2:
			why.append("a duck spot is on an island")
	return why


static func _start_ok(s: Vector2, drain: Vector2, islands: Array, others: Array) -> Array[String]:
	var why: Array[String] = []
	if absf(s.x) > HX - BOAT_R - 0.1 or absf(s.y) > HZ - BOAT_R - 0.1:
		why.append("a boat starts in the wall")
	if s.distance_to(drain) < 1.2:
		why.append("a boat starts on the plug")
	for o in islands:
		if s.distance_to(Vector2(o.x, o.y)) < float(o.z) + BOAT_R + 0.15:
			why.append("a boat starts on an island")
	for o in others:
		if s.distance_to(o) < 0.75:
			why.append("two boats start on top of each other")
	return why


## Path distances (metres, 4-way grid: never shorter than the real path) from the plug's edge to every free cell.
## Returns {"w": cols, "h": rows, "d": PackedFloat32Array (INF = can't get there)}.
static func path_field(p: Dictionary) -> Dictionary:
	var w := int(ceil(HX * 2.0 / CELL))
	var h := int(ceil(HZ * 2.0 / CELL))
	var free := PackedByteArray()
	free.resize(w * h)
	var d := PackedFloat32Array()
	d.resize(w * h)
	var queue := PackedInt32Array()
	var drain: Vector2 = p.drain
	for j in h:
		for i in w:
			var c := _cell_pos(i, j)
			var ok := absf(c.x) <= HX - BOAT_R and absf(c.y) <= HZ - BOAT_R
			if ok:
				for o in p.islands:
					if c.distance_to(Vector2(o.x, o.y)) < float(o.z) + BOAT_R:
						ok = false
						break
			free[j * w + i] = 1 if ok else 0
			d[j * w + i] = INF
			if ok and c.distance_to(drain) < DRAIN_R + BOAT_R + 0.1:  # the boat empties its train here
				d[j * w + i] = 0.0
				queue.append(j * w + i)
	var head := 0
	while head < queue.size():
		var k := queue[head]
		head += 1
		var i := k % w
		var j := k / w
		for st in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ni: int = i + st[0]
			var nj: int = j + st[1]
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var nk := nj * w + ni
			if free[nk] == 1 and d[nk] == INF:
				d[nk] = d[k] + CELL
				queue.append(nk)
	return {"w": w, "h": h, "d": d}


static func _cell_pos(i: int, j: int) -> Vector2:
	return Vector2(-HX + (i + 0.5) * CELL, -HZ + (j + 0.5) * CELL)


## Path distance from the plug to point s (the nearest reachable cell within `near` metres), INF if none.
static func path_to(field: Dictionary, s: Vector2, near: float) -> float:
	var w: int = field.w
	var h: int = field.h
	var d: PackedFloat32Array = field.d
	var ci := int((s.x + HX) / CELL)
	var cj := int((s.y + HZ) / CELL)
	var reach := int(ceil(near / CELL)) + 1
	var best := INF
	for j in range(maxi(0, cj - reach), mini(h, cj + reach + 1)):
		for i in range(maxi(0, ci - reach), mini(w, ci + reach + 1)):
			var v := d[j * w + i]
			if v == INF:
				continue
			var gap := _cell_pos(i, j).distance_to(s)
			if gap <= near:
				best = minf(best, v + gap)
	return best


## Seconds one small kid alone needs for the round's goal: one duck at a time, there and back, through the spots
## in the order ducks appear there.
static func kid_seconds(p: Dictionary, field: Dictionary = {}) -> float:
	if field.is_empty():
		field = path_field(p)
	var secs := 0.0
	var spots: Array = p.spots
	if spots.is_empty():
		return INF
	for i in int(p.goal):
		var dist := path_to(field, spots[i % spots.size()], BOAT_R + DUCK_R + 0.1)
		secs += dist * 2.0 / KID_SPEED + KID_FUMBLE
	return secs


## Problems with one round's bath (empty = fair and finishable).
static func check(p: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var n: int = p.n
	var drain: Vector2 = p.drain
	var islands: Array = p.islands
	var spots: Array = p.spots
	var starts: Array = p.starts
	# One new thing at a time.
	if n == 1 and (drain != Vector2.ZERO or not islands.is_empty() or not (p.golden as Array).is_empty()):
		why.append("round 1 isn't the plain bath")
	if n <= 2 and drain != Vector2.ZERO:
		why.append("the plug moves before round 3")
	if islands.size() != island_count(n) and not (n >= 5 and n < 7 and islands.size() == 3):
		why.append("round %d has %d islands (wants %d)" % [n, islands.size(), island_count(n)])
	if (p.golden as Array).size() != golden_count(n):
		why.append("round %d has %d golden ducks (wants %d)" % [n, (p.golden as Array).size(), golden_count(n)])
	if int(p.goal) != goal_for(n):
		why.append("round %d's goal is %d (wants %d)" % [n, int(p.goal), goal_for(n)])
	if int(p.tint) < 0 or int(p.tint) >= TINTS:
		why.append("a bubble tint that doesn't exist")
	# The plug.
	if not DRAIN_BOX.grow(0.001).has_point(drain):
		why.append("the plug (%.1f, %.1f) is out of the VR splasher's throw or near a wall" % [drain.x, drain.y])
	if n >= 3 and drain.distance_to(Vector2(TAP.x, TAP.z)) < 2.0 and drain.y > DRAIN_BOX.position.y + 0.001:
		why.append("the plug is under the tap")
	# Islands, spots, starts.
	for i in islands.size():
		var o: Vector3 = islands[i]
		if o.z < ISLAND_R.x - 0.001 or o.z > ISLAND_R.y + 0.001:
			why.append("an island of size %.2f" % o.z)
		for r in _island_ok(Vector2(o.x, o.y), o.z, drain, islands.slice(0, i)):
			why.append(r)
	if spots.size() < SPOTS:
		why.append("only %d duck spots" % spots.size())
	var quarters := {}
	for s in spots:
		for r in _spot_ok(s, drain, islands):
			why.append(r)
		quarters[Vector2i(signi(int(signf(s.x))), signi(int(signf(s.y))))] = true
	if quarters.size() < 4:
		why.append("ducks only come in %d quarters of the tub" % quarters.size())
	if starts.size() < STARTS:
		why.append("only %d boat starts" % starts.size())
	for i in starts.size():
		for r in _start_ok(starts[i], drain, islands, starts.slice(0, i)):
			why.append(r)
	# Everything reachable by boat.
	var field := path_field(p)
	if path_to(field, drain, DRAIN_R + BOAT_R + 0.2) == INF:
		why.append("no boat can reach the plug")
	for s in spots:
		if path_to(field, s, BOAT_R + DUCK_R + 0.1) == INF:
			why.append("a duck spot (%.1f, %.1f) can't be reached" % [s.x, s.y])
	for s in starts:
		if path_to(field, s, CELL) == INF:
			why.append("a boat start (%.1f, %.1f) is cut off" % [s.x, s.y])
	for g in p.golden:
		if g.x < 0.1 or g.x > 0.8:
			why.append("a golden duck comes at %.0f%% of the round" % (g.x * 100.0))
		if int(g.y) < 0 or int(g.y) >= spots.size():
			why.append("a golden duck at a spot that doesn't exist")
	# Finishable by one small kid alone.
	var secs := kid_seconds(p, field)
	if secs > ROUND_SECS * GOAL_SHARE:
		why.append("one small kid needs %.0f s for %d ducks (the round is %.0f s)" % [secs, int(p.goal), ROUND_SECS])
	return why


## Problems with a whole bath (rounds 1..last): every round fair, and the challenge rises readably: goals and islands
## never go down.
static func check_bath(bath_seed: int, last: int = MAX_ROUND) -> Array[String]:
	var why: Array[String] = []
	var prev_goal := 0
	var prev_isl := 0
	for n in range(1, last + 1):
		var p := plan(bath_seed, n)
		for r in check(p):
			why.append("round %d: %s" % [n, r])
		if int(p.goal) < prev_goal:
			why.append("round %d's goal (%d) is smaller than round %d's" % [n, int(p.goal), n - 1])
		if n <= 4 and (p.islands as Array).size() < prev_isl:
			why.append("round %d has fewer islands than round %d" % [n, n - 1])
		prev_goal = int(p.goal)
		prev_isl = (p.islands as Array).size()
	return why


## Where toy i sits on the right-hand rim (world), Vector3.INF past the end.
static func toy_slot(i: int, rim_y: float) -> Vector3:
	if i < 0 or i >= TOY_KEEP:
		return Vector3.INF
	return Vector3(HX + 0.15, rim_y, -HZ + 0.4 + i * (HZ * 2.0 - 0.8) / float(TOY_KEEP - 1))


## Ducklings beside Mama Duck: one per play-day.
static func ducklings(days: int) -> int:
	return clampi(days, 0, DUCKLINGS_MAX)


## Where duckling i sits on the far rim (world): a line to Mama Duck's right.
static func duckling_slot(i: int, rim_y: float) -> Vector3:
	return Vector3(-1.9 + 0.42 * (i + 1), rim_y, -HZ - 0.15)


## Where Mama Duck sits (world).
static func mama_slot(rim_y: float) -> Vector3:
	return Vector3(-1.9, rim_y, -HZ - 0.15)
