extends RefCounted
## WHACK-A-MOLE rounds from a seed: the exact list of moles a round brings (when, which hole, what kind,
## how long they stay), made of little WAVES with shapes kids can read (a line popping left to right, a
## ring round the edge, two mirrored moles, a hopping snake, a RUSH of many at once, plain scatter).
## Rising: later rounds (level = garden beds grown) have quicker moles, more of them and more shapes;
## the round's own crop (story.gd) brings its VISITOR moles (speedy, helmet, bunny, king...).
## Same (seed, spec) -> same round on every machine. check(round) is the validator (tests/
## whack_a_mole_gen_test.gd runs it over many seeds): holes never overlap, never too many moles up,
## never a long empty gap, only the crop's kinds, a fair star goal, a king only when there's time.
## Pure data, no nodes. Generation is a few hundred tiny steps (well under a millisecond).

const Seeded := preload("res://core/seeded.gd")

const COLS := 4
const ROWS := 3
const HOLES := COLS * ROWS
## Mole kinds (main.gd draws and scores them; 3 bits in the snapshot).
const NORMAL := 0
const GOLD := 1
const HELMET := 2  ## two bonks (the helmet pops off first)
const SPEEDY := 3  ## quick: in and out
const BUNNY := 4  ## a friend: DON'T bonk; left alone it leaves a carrot (+2)
const KING := 5  ## the big crowned mole near the end: five bonks from anyone
const SEED := 6  ## a seed packet in the pick phase (not in rounds)
const BARE := 7  ## a helmet mole whose helmet popped off (not in rounds: main.gd turns HELMET into it)
const KIND_NAMES: Array[String] = ["MOLE", "GOLDEN", "HELMET", "SPEEDY", "BUNNY", "KING", "SEEDS", "BARE"]
const POINTS: Array[int] = [1, 5, 3, 2, 2, 14, 0, 3]  ## a bunny's 2 is its carrot (left alone); the king: 1 per bonk + 10
const HITS: Array[int] = [1, 1, 2, 1, 1, 5, 1, 1]
const STAY_MULT: Array[float] = [1.0, 0.75, 1.4, 0.6, 1.25, 1.0, 1.0, 1.0]
## Seconds a hole needs after a mole's stay before the next one (rise, bonk / fall, rest).
const HOLE_REST := 1.0
const KING_STAY := 9.0
const KING_HOLES: Array[int] = [5, 6]
const MAX_GAP := 3.5  ## never longer than this with no mole popping
## Wave shapes and the level they start at.
const PATTERNS := {"scatter": 0, "line": 1, "pair": 1, "ring": 2, "rush": 2, "snake": 3}


static func hole_of(c: int, r: int) -> int:
	return r * COLS + c


## spec: {time (s), level (0..), players (1..), kinds {kind: weight}, gold (chance), king (bool), name}
## Returns {seed, time, level, spawns: [[t, hole, kind, stay], ...] by time, waves: [[t, shape], ...],
## max (all points), goal [1 star, 2 stars, 3 stars], kinds [kinds used], cap (most moles up at once)}.
static func generate(seed_value: int, spec: Dictionary) -> Dictionary:
	var rng := Seeded.rng(seed_value, "moles")
	var krng := Seeded.rng(seed_value, "kinds")
	var time := maxf(8.0, float(spec.get("time", 120.0)))
	var level := maxi(0, int(spec.get("level", 0)))
	var players := clampi(int(spec.get("players", 1)), 1, 8)
	var d := clampf(level / 10.0, 0.0, 1.0)  # how far along the garden is (0 first bed .. 1 ten beds)
	var cap := 5 + (1 if players >= 4 else 0)
	var kinds: Dictionary = spec.get("kinds", {})
	var gold_p := float(spec.get("gold", 0.06))
	var free_at := PackedFloat32Array()
	free_at.resize(HOLES)
	var up_until: Array = []  # [end time] of every spawn so far (for the cap)
	var spawns: Array = []
	var waves: Array = []
	var end_t := time - 1.5
	var king_t := -1.0
	if bool(spec.get("king", false)) and time >= 30.0:
		king_t = snappedf(time * 0.82, 0.01)
		var kh: int = KING_HOLES[rng.randi() % KING_HOLES.size()]
		spawns.append([snappedf(king_t, 0.01), kh, KING, KING_STAY])
		free_at[kh] = king_t + KING_STAY + HOLE_REST
		up_until.append([king_t, king_t + KING_STAY])
	var t := 1.0
	var open: Array = []
	for k in PATTERNS:
		if level >= int(PATTERNS[k]):
			open.append(k)
	var rushes := 0
	var last := ""
	while t < end_t - 1.0:
		var p := t / time
		var shape := "scatter"
		if t > 4.0:
			var w: Array = []
			for k in open:
				var wt := 3.0 if k == "scatter" else 1.0
				if k == last:
					wt *= 0.3
				if k == "rush" and (rushes >= 1 + int(time / 60.0) or p < 0.3):
					wt = 0.0
				w.append(wt)
			shape = open[Seeded.weighted(rng, w)]
		last = shape
		if shape == "rush":
			rushes += 1
		waves.append([snappedf(t, 0.01), shape])
		var gap := lerpf(1.1, 0.45, p) * lerpf(1.0, 0.75, d)
		var stay := maxf(0.7, lerpf(2.0, 0.9, p) * lerpf(1.0, 0.8, d))
		var plan := _wave(shape, rng, gap)  # [[dt, hole or -1 (any free)], ...]
		var wave_end := t
		for step in plan:
			var at := snappedf(t + float(step[0]), 0.01)
			if at > end_t:
				break
			var kind := _kind(krng, kinds, gold_p, p)
			if kind == GOLD and _gold_up(spawns, at):
				kind = NORMAL
			var s := snappedf(maxf(0.6, stay * STAY_MULT[kind]), 0.01)
			var hole: int = step[1]
			if hole < 0 or free_at[hole] > at:
				hole = _free_hole(rng, free_at, at)
			if hole < 0 or _up_at(up_until, at, at + s) >= cap:
				continue
			spawns.append([at, hole, kind, s])
			free_at[hole] = at + s + HOLE_REST
			up_until.append([at, at + s])
			wave_end = maxf(wave_end, at)
		t = maxf(wave_end + gap * rng.randf_range(1.2, 2.0), t + 1.0)
	spawns.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var mx := 0
	var used := {}
	for s in spawns:
		mx += POINTS[int(s[2])]
		used[int(s[2])] = true
	var used_list: Array = used.keys()
	used_list.sort()
	return {"seed": seed_value, "time": time, "level": level, "spawns": spawns, "waves": waves, "max": mx,
		"goal": goal(mx, players), "kinds": used_list, "cap": cap, "name": str(spec.get("name", ""))}


## The star goal: points for 1, 2 and 3 stars. A share of every point the round holds, a bit higher with
## more players (each one bonks some), never above 85% of everything.
static func goal(mx: int, players: int) -> Array:
	var f: float = [0.15, 0.24, 0.3, 0.35, 0.4][clampi(players, 1, 5) - 1]
	var one := maxi(1, roundi(mx * f))
	var two := maxi(one + 1, roundi(mx * f * 1.6))
	var three := maxi(two + 1, mini(roundi(mx * f * 2.2), roundi(mx * 0.85)))
	return [one, two, three]


static func stars(score: int, g: Array) -> int:
	var n := 0
	for v in g:
		if score >= int(v):
			n += 1
	return n


## One wave's plan: [[seconds after the wave starts, hole (-1 = any free)], ...].
static func _wave(shape: String, rng: RandomNumberGenerator, gap: float) -> Array:
	var out: Array = []
	match shape:
		"line":  # a row pops one after another, left to right or right to left
			var r := rng.randi() % ROWS
			var rev := rng.randf() < 0.5
			for c in COLS:
				out.append([c * gap * 0.55, hole_of(COLS - 1 - c if rev else c, r)])
		"pair":  # two moles at once, mirrored left / right
			for k in 2:
				var c := rng.randi() % (COLS / 2)
				var r := rng.randi() % ROWS
				out.append([k * gap * 1.6, hole_of(c, r)])
				out.append([k * gap * 1.6, hole_of(COLS - 1 - c, r)])
		"ring":  # round the edge
			var ring: Array[int] = [0, 1, 2, 3, 7, 11, 10, 9, 8, 4]
			var start := rng.randi() % ring.size()
			for k in 6:
				out.append([k * gap * 0.5, ring[(start + k) % ring.size()]])
		"rush":  # lots at once!
			for k in 5:
				out.append([k * 0.12, -1])
		"snake":  # one mole hopping to a neighbour hole
			var c := rng.randi() % COLS
			var r := rng.randi() % ROWS
			for k in 5:
				out.append([k * gap * 0.9, hole_of(c, r)])
				if rng.randf() < 0.5:
					c = clampi(c + (1 if rng.randf() < 0.5 else -1), 0, COLS - 1)
				else:
					r = clampi(r + (1 if rng.randf() < 0.5 else -1), 0, ROWS - 1)
		_:  # scatter
			for k in 3:
				out.append([k * gap, -1])
	return out


static func _kind(r: RandomNumberGenerator, kinds: Dictionary, gold_p: float, p: float) -> int:
	if p > 0.05 and r.randf() < gold_p:
		return GOLD
	if p < 0.08 or kinds.is_empty():
		return NORMAL
	var keys: Array = kinds.keys()
	keys.sort()
	var w: Array = []
	var total := 0.0
	for k in keys:
		w.append(float(kinds[k]))
		total += float(kinds[k])
	if r.randf() >= total:  # weights are chances (sum < 1): the rest are plain moles
		return NORMAL
	return int(keys[Seeded.weighted(r, w)])


static func _gold_up(spawns: Array, at: float) -> bool:
	for s in spawns:
		if int(s[2]) == GOLD and float(s[0]) <= at + 0.05 and float(s[0]) + float(s[3]) + 0.5 > at:
			return true
	return false


static func _free_hole(r: RandomNumberGenerator, free_at: PackedFloat32Array, at: float) -> int:
	var free: Array[int] = []
	for h in HOLES:
		if free_at[h] <= at:
			free.append(h)
	return -1 if free.is_empty() else free[r.randi() % free.size()]


## Moles up at any moment of [from, to] (counted loosely: a mole planned later, like the king, counts too).
static func _up_at(up_until: Array, from: float, to: float) -> int:
	var n := 0
	for u in up_until:
		if float(u[0]) <= to + 0.05 and float(u[1]) + 0.05 > from:
			n += 1
	return n


## The validator: an Array of reasons this round is unfair or broken (empty when fine).
## allowed: the kinds this round may hold (its spec's kinds + plain + golden + king when asked).
static func check(rd: Dictionary, allowed: Array = []) -> Array:
	var why: Array = []
	var spawns: Array = rd.get("spawns", [])
	var time := float(rd.get("time", 0.0))
	if spawns.size() < int(time * 0.45):
		why.append("too few moles (%d in %d s)" % [spawns.size(), int(time)])
	var busy := {}
	var prev_t := 0.0
	var first := true
	var last_pop := 0.0
	var ends: Array = []
	var golds: Array = []
	var kings := 0
	for s in spawns:
		var at := float(s[0])
		var hole := int(s[1])
		var kind := int(s[2])
		var stay := float(s[3])
		if at < prev_t:
			why.append("not in time order at %.2f" % at)
		prev_t = at
		if at < 0.5 or at + 0.5 > time:
			why.append("a mole at %.2f is outside the round" % at)
		if hole < 0 or hole >= HOLES:
			why.append("bad hole %d" % hole)
			continue
		if kind < 0 or kind > KING:
			why.append("bad kind %d" % kind)
		elif not allowed.is_empty() and not allowed.has(kind):
			why.append("kind %s not allowed here" % KIND_NAMES[kind])
		if stay < 0.55:
			why.append("a mole too quick to bonk (%.2f s)" % stay)
		if busy.has(hole) and float(busy[hole]) > at + 0.001:
			why.append("hole %d used again too soon at %.2f" % [hole, at])
		busy[hole] = at + stay + HOLE_REST
		if not first and at - last_pop > MAX_GAP and kind != KING:
			why.append("a long empty gap before %.2f" % at)
		if kind != KING:
			last_pop = at
		first = false
		var n := 1
		for e in ends:
			if float(e[0]) <= at and float(e[1]) > at:
				n += 1
		if n > int(rd.get("cap", 5)):
			why.append("%d moles up at %.2f (cap %d)" % [n, at, int(rd.get("cap", 5))])
		ends.append([at, at + stay])
		if kind == GOLD:
			for g in golds:
				if float(g) > at:
					why.append("two golden moles at once at %.2f" % at)
			golds.append(at + stay + 0.4)
		if kind == KING:
			kings += 1
	if kings > 1:
		why.append("%d kings" % kings)
	if time < 30.0 and kings > 0:
		why.append("a king in a short round")
	if not spawns.is_empty() and time - last_pop > MAX_GAP + 2.5:
		why.append("the end of the round is empty (last mole at %.2f of %d)" % [last_pop, int(time)])
	var g: Array = rd.get("goal", [])
	var mx := int(rd.get("max", 0))
	if g.size() != 3 or int(g[0]) < 1 or int(g[0]) >= int(g[1]) or int(g[1]) >= int(g[2]) or int(g[2]) > mx:
		why.append("bad star goal %s (max %d)" % [str(g), mx])
	return why
