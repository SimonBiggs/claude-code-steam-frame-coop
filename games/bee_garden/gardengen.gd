extends RefCounted
## BEE GARDEN generator: a seeded garden bed (where the 12 planting spots sit, a little pond, stepping
## stones, rocks and toadstools between them, which flowers already bloom, the practice ring) and a
## seeded plan for each round of it ("day": weather, Queen Bea's favourite flower, aphid visits, a golden
## flower, the honey goal). Pure data, no nodes: the host and every TV build the same garden from the seed.
##   var g := GardenGen.generate(seed, {"kinds": 2, "level": 5})       # the bed (same seed -> same bed)
##   var d := GardenGen.day_plan(g, round_n, {"kinds": 2, "level": 5, "bees": 3})
##   GardenGen.check(g) / GardenGen.check_day(g, d)                   # [] when fair, else reasons
## Everything is checked by tests/bee_garden_gen_test.gd over many seeds: every spot is in the soil,
## clear of the pond / stones / rocks and far enough from its neighbours that a tossed seed lands in the
## right one (plantable by the gardener), every flower head is reachable by a bee flying straight from the
## hive (nothing in the way), the practice ring is near the gardener and empty, and the honey goal can be
## filled in good time by the bees (a small flight simulation of real bee speeds, pollen regrowing, loads
## of three) even if the gardener plants nothing, and by the two helper bees when the gardener plays alone.

const Seeded := preload("res://core/seeded.gd")

const SPOTS := 12
const X_MAX := 3.35          # spots stay this far from the bed's middle (soil half-width 4.0)
const Z_MIN := -1.35         # back of the bed (the gardener reaches over / tosses seeds this far)
const Z_MAX := 1.3           # front of the bed (by the ledge)
const MIN_GAP := 1.1         # between spots: plants never touch and a seed lands in the right one
const CLEAR := 0.32          # extra room between a spot and a feature (the plant's mound and leaves)
const SEED_SNAP := 1.4       # main.gd: a seed lands in the nearest empty spot within this
const PLANS: Array[String] = ["rows", "pond", "path", "rockery", "meadow"]
const FEATURE_KINDS: Array[String] = ["pond", "stone", "rock", "toadstool"]
## Feature heights above the soil (bees must fly over them).
const FEATURE_H := {"pond": 0.02, "stone": 0.05, "rock": 0.3, "toadstool": 0.32}
## Bee and flower facts (kept in step with bee.gd, helpers.gd, main.gd and world.gd; the test checks).
const HIVE_ENTRY := Vector3(-5.0, 0.32, -0.5)
const KIND_H: Array[float] = [0.75, 1.15, 0.9]     # world.gd KINDS h (flower head = h + 0.06)
const KIND_HONEY: Array[int] = [1, 2, 3]
const BEE_SPEED := 3.1 * 0.55   # a child flying a bee wanders: a bit over half the real top speed
const BEE_LOAD := 3
const HELPER_SPEED := 1.6
const POLLEN_REGROW := 4.0
## Things bees must not fly through: [centre, half size] boxes (the jar row, the jar shelf, the hive).
const OBSTACLES := [
	[Vector3(0.0, 0.45, -2.15), Vector3(3.3, 0.45, 0.3)],
	[Vector3(-5.5, -1.0, -2.35), Vector3(1.05, 2.2, 0.3)],
	[Vector3(-5.5, 0.6, -0.5), Vector3(0.45, 0.6, 0.45)],
]
const WEATHERS: Array[String] = ["sun", "showers", "hot", "drizzle"]
const MAX_FILL_S := 150.0     # the goal fills within this with the expected flowers
const MAX_BARE_S := 330.0     # ... and within this even if the gardener never plants (no fail, just slow)


## The garden bed for `seed`. spec: kinds (seed kinds unlocked, 1..3), level (rounds ever finished).
static func generate(seed_value: int, spec: Dictionary = {}) -> Dictionary:
	var kinds := clampi(int(spec.get("kinds", 1)), 1, 3)
	var level := int(spec.get("level", 0))
	var r := Seeded.rng(seed_value, "bed")
	var plan: String = PLANS[r.randi() % PLANS.size()]
	var feats: Array = []
	var spots: Array = []
	for attempt in 8:
		var fr := Seeded.rng(seed_value, "bed%d" % attempt)
		feats = _features(fr, plan)
		spots = _rows(fr) if plan == "rows" else _scatter(fr, feats)
		if spots.size() == SPOTS:
			if plan == "rows":
				feats = _features_between(fr, spots)
			break
	if spots.size() < SPOTS:
		plan = "rows"
		spots = [[-2.7, -1.2], [-0.9, -1.2], [0.9, -1.2], [2.7, -1.2], [-2.7, 0.0], [-0.9, 0.0], [0.9, 0.0], [2.7, 0.0],
			[-2.7, 1.2], [-0.9, 1.2], [0.9, 1.2], [2.7, 1.2]]
		feats = []
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] - 0.3 or (absf(a[1] - b[1]) <= 0.3 and a[0] < b[0]))
	# The practice ring: the spot nearest the front middle (the ghost glove's demo, right by the gardener).
	var practice := 0
	var best := INF
	for i in spots.size():
		var d := Vector2(spots[i][0] * 0.6, spots[i][1] - Z_MAX - 0.6).length()
		if d < best:
			best = d
			practice = i
	# Flowers already blooming: the bees' first (haloed) flower is the one nearest the hive, plus a few more.
	var others: Array = []
	for i in spots.size():
		if i != practice:
			others.append(i)
	var halo: int = others[0]
	for i in others:
		if _dist2(spots[i], HIVE_ENTRY) < _dist2(spots[halo], HIVE_ENTRY):
			halo = i
	var n_bloom := 2 + (1 if level >= 3 else 0) + (1 if level >= 10 else 0)
	var blooms: Array = [[halo, 0]]
	var pool: Array = Seeded.shuffled(r, others)
	for i in pool:
		if blooms.size() >= n_bloom:
			break
		if int(i) == halo or _touches(spots, int(i), practice):
			continue
		blooms.append([int(i), r.randi() % mini(kinds, 2) if blooms.size() == 1 else r.randi() % kinds])
	return {"seed": seed_value, "plan": plan, "spots": spots, "features": feats, "practice": practice, "halo": halo,
		"blooms": blooms, "kinds": kinds, "level": level}


## One round ("day") in garden g. spec: kinds, level (rounds ever finished), bees (TV bees now; 0 = the
## gardener alone with the helper bees).
static func day_plan(g: Dictionary, round_n: int, spec: Dictionary = {}) -> Dictionary:
	var r := Seeded.rng(Seeded.derive(int(g.seed), round_n), "day")
	var kinds := clampi(int(spec.get("kinds", g.get("kinds", 1))), 1, 3)
	var level := int(spec.get("level", g.get("level", 0)))
	var bees := clampi(int(spec.get("bees", 1)), 0, 6)
	var weather := "sun"
	if round_n >= 2:
		weather = WEATHERS[Seeded.weighted(r, [3, 3, 2 if round_n >= 3 else 0, 1 if round_n >= 3 else 0])]
	var rains: Array = []
	match weather:
		"showers":
			rains = [snappedf(r.randf_range(20.0, 50.0), 0.5)]
		"drizzle":
			var a := snappedf(r.randf_range(15.0, 30.0), 0.5)
			rains = [a, snappedf(a + r.randf_range(35.0, 55.0), 0.5)]
	# Queen Bea's favourite flower today (its pollen makes a drop of extra honey); round 1 = the daisy.
	var fav := 0 if round_n <= 1 else r.randi() % kinds
	var aphids: Array = []
	if round_n >= 3 and level >= 4:
		var n := Seeded.weighted(r, [2, 3, 2])
		var at := r.randf_range(28.0, 45.0)
		for k in n:
			aphids.append(snappedf(at, 0.5))
			at += r.randf_range(26.0, 40.0)
	var golden := -1.0
	if round_n >= 4 and r.randf() < 0.5:
		golden = snappedf(r.randf_range(25.0, 70.0), 0.5)
	# The honey goal: grows round by round, a little more with more bees (they share the flowers).
	var base := mini(14 + 6 * (round_n - 1), 36)
	var target := int(round(base * (1.0 + 0.25 * maxf(0.0, bees - 1))))
	target = mini(target, 48)
	# The flowers we can count on: today's blooms grow by about two a round (the gardener plants).
	var expect := mini(SPOTS - 1, (g.blooms as Array).size() + 2 * (round_n - 1))
	return {"round": round_n, "weather": weather, "rains": rains, "fav": fav, "aphids": aphids, "golden": golden,
		"target": target, "bees": bees, "expect": expect, "kinds": kinds}


## Seconds to fill `target` honey with `n_flowers` blooming flowers (the first n of the bed, all of
## kind `kind`; the bees' halo flower first) - a small flight simulation (bees: real speed x 0.55, loads
## of three, pollen regrows; helpers: two at their own speed, loads of two). INF when it never fills.
static func fill_time(g: Dictionary, n_flowers: int, kind: int, target: int, bees: int, fav: int = -1, limit: float = 600.0) -> float:
	var heads: Array = []
	var order: Array = [int(g.halo)]
	for b in g.blooms:
		if not order.has(int(b[0])):
			order.append(int(b[0]))
	for i in SPOTS:
		if not order.has(i) and i != int(g.practice):
			order.append(i)
	order.append(int(g.practice))
	var kinds_of: Array = []
	for j in mini(n_flowers, order.size()):
		var i: int = order[j]
		var k := kind
		for b in g.blooms:
			if int(b[0]) == i:
				k = int(b[1])
		heads.append(head_pos(g, i, k))
		kinds_of.append(k)
	if heads.is_empty():
		return INF
	var helpers := bees <= 0
	var n := 2 if helpers else bees
	var speed := HELPER_SPEED if helpers else BEE_SPEED
	var cap := 2 if helpers else BEE_LOAD
	var ready_at: Array = []
	ready_at.resize(heads.size())
	ready_at.fill(0.0)
	var pos: Array = []
	var load: Array = []
	var val: Array = []
	var wait: Array = []
	var goal: Array = []
	var got_fav: Array = []
	for b in n:
		pos.append(HIVE_ENTRY)
		load.append(0)
		val.append(0)
		wait.append(b * 1.5 if helpers else b * 0.5)
		goal.append(-1)
		got_fav.append(false)
	var honey := 0
	var t := 0.0
	var dt := 0.25
	while t < limit:
		t += dt
		for b in n:
			if float(wait[b]) > 0.0:
				wait[b] = float(wait[b]) - dt
				continue
			var to: Vector3
			if int(load[b]) >= cap:
				to = HIVE_ENTRY
			else:
				if int(goal[b]) < 0:
					# The nearest flower that will have pollen when we get there (helpers don't wait for it).
					var bi := -1
					var bt := INF
					for i in heads.size():
						var arrive: float = t + (pos[b] as Vector3).distance_to(heads[i]) / speed
						var tt := arrive if helpers else maxf(arrive, float(ready_at[i]))
						for o in n:
							if o != b and int(goal[o]) == i:
								tt += 2.0  # someone's already on their way
						if tt < bt:
							bt = tt
							bi = i
					goal[b] = bi
				to = heads[int(goal[b])]
			var p: Vector3 = pos[b]
			var step := speed * dt
			if p.distance_to(to) > step:
				pos[b] = p + (to - p).normalized() * step
				continue
			pos[b] = to
			if int(load[b]) >= cap:
				var v: int = int(load[b]) if helpers else int(val[b]) + (1 if bool(got_fav[b]) else 0)
				honey += v
				load[b] = 0
				val[b] = 0
				got_fav[b] = false
				wait[b] = 1.5 if helpers else 0.4
				if honey >= target:
					return t
				continue
			var gi: int = goal[b]
			if helpers or t >= float(ready_at[gi]):
				load[b] = int(load[b]) + 1
				val[b] = int(val[b]) + KIND_HONEY[int(kinds_of[gi])]
				got_fav[b] = bool(got_fav[b]) or int(kinds_of[gi]) == fav
				ready_at[gi] = t + POLLEN_REGROW
				goal[b] = -1
				wait[b] = 1.2 if helpers else 0.35
				# A bee that has picked up some pollen and finds nothing ready nearby goes home with it.
				if not helpers and int(load[b]) < cap:
					var any_soon := false
					for i in heads.size():
						if float(ready_at[i]) <= t + 3.0:
							any_soon = true
					if not any_soon:
						load[b] = cap
	return INF


## Where flower i's head is when it blooms (plant.gd head_pos at full growth).
static func head_pos(g: Dictionary, i: int, kind: int) -> Vector3:
	var s: Array = g.spots[i]
	return Vector3(float(s[0]), KIND_H[kind] + 0.06, float(s[1]))


## Why garden g isn't fair ([] when it is).
static func check(g: Dictionary) -> Array:
	var why: Array = []
	var spots: Array = g.spots
	if spots.size() != SPOTS:
		why.append("%d spots, not %d" % [spots.size(), SPOTS])
		return why
	for i in spots.size():
		var s: Array = spots[i]
		if absf(s[0]) > X_MAX + 0.001 or s[1] < Z_MIN - 0.001 or s[1] > Z_MAX + 0.001:
			why.append("spot %d out of the gardener's reach (%.2f, %.2f)" % [i, s[0], s[1]])
		for j in range(i + 1, spots.size()):
			var d := Vector2(s[0] - spots[j][0], s[1] - spots[j][1]).length()
			if d < MIN_GAP - 0.001:
				why.append("spots %d and %d too close (%.2f): seeds land in the wrong one" % [i, j, d])
		for f in g.features:
			var fd := Vector2(s[0] - f[1], s[1] - f[2]).length()
			if fd < float(f[3]) + CLEAR - 0.001:
				why.append("spot %d on a %s (%.2f)" % [i, f[0], fd])
		# Plantable: a seed tossed right at it lands in it, not in a neighbour.
		var nearest := -1
		var nd := INF
		for j in spots.size():
			var d2 := Vector2(s[0] - spots[j][0], s[1] - spots[j][1]).length()
			if d2 < nd:
				nd = d2
				nearest = j
		if nearest != i:
			why.append("a seed tossed at spot %d lands elsewhere" % i)
		# Bees: every kind's flower head is reachable straight from the hive with nothing in the way.
		for k in 3:
			var hp := head_pos(g, i, k)
			if hp.y < 0.18 + 0.3:
				why.append("spot %d's flower is too low for the bees" % i)
			var blocked := _blocked(HIVE_ENTRY + Vector3(0.6, 0.3, 0.0), hp, g.features)
			if blocked != "":
				why.append("bees can't reach spot %d's %s: %s in the way" % [i, ["daisy", "sunflower", "lily"][k], blocked])
	for f in g.features:
		if not FEATURE_KINDS.has(String(f[0])):
			why.append("unknown feature %s" % f[0])
		if absf(f[1]) + float(f[3]) > 4.0 - 0.05 or absf(f[2]) + float(f[3]) > 1.8 - 0.05:
			why.append("a %s sticks out of the bed" % f[0])
	var pr := int(g.practice)
	if pr < 0 or pr >= SPOTS:
		why.append("no practice ring")
	else:
		if float(spots[pr][1]) < 0.0 or absf(float(spots[pr][0])) > 2.6:
			why.append("the practice ring is far from the gardener (%.2f, %.2f)" % [spots[pr][0], spots[pr][1]])
	var blooms: Array = g.blooms
	if blooms.size() < 2:
		why.append("only %d flowers bloom at the start" % blooms.size())
	var seen := {}
	for b in blooms:
		if int(b[0]) == pr:
			why.append("a flower blooms in the practice ring")
		if seen.has(int(b[0])):
			why.append("spot %d blooms twice" % int(b[0]))
		seen[int(b[0])] = true
		if int(b[1]) < 0 or int(b[1]) >= int(g.kinds):
			why.append("a %d flower blooms with only %d kinds unlocked" % [int(b[1]), int(g.kinds)])
	if blooms.is_empty() or int(blooms[0][0]) != int(g.halo) or int(blooms[0][1]) != 0:
		why.append("the bees' first flower isn't a blooming daisy")
	return why


## Why round d of garden g isn't fair ([] when it is).
static func check_day(g: Dictionary, d: Dictionary) -> Array:
	var why: Array = []
	var target := int(d.target)
	if target < 10 or target > 48:
		why.append("honey goal %d" % target)
	if not WEATHERS.has(String(d.weather)):
		why.append("weather %s" % d.weather)
	if int(d.round) <= 1 and (String(d.weather) != "sun" or not (d.aphids as Array).is_empty() or float(d.golden) >= 0.0):
		why.append("the first round (practice) isn't calm")
	var last := -100.0
	for a in d.rains:
		if float(a) < 10.0 or float(a) - last < 30.0:
			why.append("rain at %.0f s" % float(a))
		last = float(a)
	last = -100.0
	for a in d.aphids:
		if float(a) < 25.0 or float(a) - last < 20.0:
			why.append("an aphid at %.0f s" % float(a))
		last = float(a)
	if (d.aphids as Array).size() > 2:
		why.append("%d aphids" % (d.aphids as Array).size())
	if int(d.fav) < 0 or int(d.fav) >= int(d.kinds):
		why.append("Queen Bea's favourite isn't growable")
	# Fair goal: the bees fill it in good time with the flowers we expect, and eventually with only the
	# flowers that bloomed at the start (the gardener never has to do anything); helpers alone too.
	var bees := int(d.bees)
	var t_exp := fill_time(g, int(d.expect), 0, target, bees, int(d.fav))
	if t_exp > MAX_FILL_S:
		why.append("round %d: %d honey takes %.0f s with %d bees and %d flowers" % [int(d.round), target, t_exp, bees, int(d.expect)])
	var t_bare := fill_time(g, (g.blooms as Array).size(), 0, target, bees, -1, MAX_BARE_S + 10.0)
	if t_bare > MAX_BARE_S:
		why.append("round %d: %d honey with only the first %d flowers takes %.0f s (%d bees)" % [int(d.round), target, (g.blooms as Array).size(), t_bare, bees])
	if t_exp < 10.0:
		why.append("round %d: done in %.0f s (too quick)" % [int(d.round), t_exp])
	return why


# --- generation helpers -------------------------------------------------------

## Three rows of four, gaps shuffled (each row its own rhythm, so the bed never looks like a grid).
static func _rows(r: RandomNumberGenerator) -> Array:
	var out: Array = []
	for row in 3:
		var z := -1.2 + row * 1.2 + r.randf_range(-0.05, 0.05)
		z = clampf(z, Z_MIN, Z_MAX)
		var gaps: Array = []
		var total := 0.0
		for k in 5:
			var w := r.randf_range(0.2, 1.0)
			gaps.append(w)
			total += w
		var slack := X_MAX * 2.0 - 3.0 * 1.5
		var x := -X_MAX + slack * float(gaps[0]) / total
		for k in 4:
			out.append([snappedf(x, 0.01), snappedf(z, 0.01)])
			if k < 3:
				x += 1.5 + slack * float(gaps[k + 1]) / total
	return out


## Spots scattered round the features (random, never too close, never on a feature).
static func _scatter(r: RandomNumberGenerator, feats: Array) -> Array:
	var cands: Array = []
	var x := -X_MAX
	while x <= X_MAX + 0.001:
		var z := Z_MIN
		while z <= Z_MAX + 0.001:
			cands.append([snappedf(x, 0.01), snappedf(z, 0.01)])
			z += 0.15
		x += 0.15
	cands = Seeded.shuffled(r, cands)
	var out: Array = []
	for c in cands:
		if out.size() >= SPOTS:
			break
		if _free(c, out, feats):
			out.append(c)
	return out


static func _free(c: Array, spots: Array, feats: Array) -> bool:
	for s in spots:
		if Vector2(c[0] - s[0], c[1] - s[1]).length() < MIN_GAP:
			return false
	for f in feats:
		if Vector2(c[0] - f[1], c[1] - f[2]).length() < float(f[3]) + CLEAR:
			return false
	return true


## Features first (scattered plans): [kind, x, z, radius].
static func _features(r: RandomNumberGenerator, plan: String) -> Array:
	var out: Array = []
	match plan:
		"pond":
			out.append(["pond", snappedf(r.randf_range(-1.8, 1.8), 0.01), snappedf(r.randf_range(-0.6, 0.4), 0.01), snappedf(r.randf_range(0.45, 0.6), 0.01)])
			out.append(["rock", out[0][1] + 0.75, out[0][2] - 0.25, 0.18])
		"path":
			var x0 := r.randf_range(-1.6, 1.6)
			var amp := r.randf_range(0.3, 0.8)
			var ph := r.randf_range(0.0, TAU)
			var z := 1.6
			while z > -1.65:
				out.append(["stone", snappedf(x0 + sin(z * 1.4 + ph) * amp, 0.01), snappedf(z, 0.01), 0.17])
				z -= 0.42
		"rockery":
			for k in 2 + r.randi() % 2:
				out.append(["rock", snappedf(r.randf_range(-3.2, 3.2), 0.01), snappedf(r.randf_range(-1.3, 1.3), 0.01), snappedf(r.randf_range(0.2, 0.3), 0.01)])
			for k in 3:
				out.append(["toadstool", snappedf(r.randf_range(-3.4, 3.4), 0.01), snappedf(r.randf_range(-1.4, 1.4), 0.01), 0.1])
		"meadow":
			for k in 2:
				out.append(["toadstool", snappedf(r.randf_range(-3.4, 3.4), 0.01), snappedf(r.randf_range(-1.4, 1.4), 0.01), 0.1])
	# Keep features inside the bed and apart from each other.
	var kept: Array = []
	for f in out:
		f[1] = clampf(float(f[1]), -4.0 + float(f[3]) + 0.06, 4.0 - float(f[3]) - 0.06)
		f[2] = clampf(float(f[2]), -1.8 + float(f[3]) + 0.06, 1.8 - float(f[3]) - 0.06)
		var ok := true
		for k in kept:
			if Vector2(f[1] - k[1], f[2] - k[2]).length() < float(f[3]) + float(k[3]) + 0.05:
				ok = false
		if ok:
			kept.append(f)
	return kept


## Row gardens: stepping stones and a toadstool or two in the gaps the rows left.
static func _features_between(r: RandomNumberGenerator, spots: Array) -> Array:
	var out: Array = []
	for k in 14:
		var c := [snappedf(r.randf_range(-3.6, 3.6), 0.01), snappedf(r.randf_range(-1.55, 1.55), 0.01)]
		var kind := "stone" if k % 3 != 2 else "toadstool"
		var rad := 0.17 if kind == "stone" else 0.1
		var f := [kind, c[0], c[1], rad]
		if _free_feature(f, spots, out):
			out.append(f)
	return out


static func _free_feature(f: Array, spots: Array, feats: Array) -> bool:
	for s in spots:
		if Vector2(f[1] - s[0], f[2] - s[1]).length() < float(f[3]) + CLEAR:
			return false
	for k in feats:
		if Vector2(f[1] - k[1], f[2] - k[2]).length() < float(f[3]) + float(k[3]) + 0.05:
			return false
	return true


static func _touches(spots: Array, i: int, j: int) -> bool:
	return Vector2(spots[i][0] - spots[j][0], spots[i][1] - spots[j][1]).length() < MIN_GAP + 0.15


static func _dist2(s: Array, p: Vector3) -> float:
	return Vector2(float(s[0]) - p.x, float(s[1]) - p.z).length_squared()


## What blocks the straight flight a -> b ("" when clear): features (by height) and OBSTACLES boxes.
static func _blocked(a: Vector3, b: Vector3, feats: Array) -> String:
	var n := maxi(2, int(a.distance_to(b) / 0.1))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		for o in OBSTACLES:
			var c: Vector3 = o[0]
			var h: Vector3 = o[1]
			if absf(p.x - c.x) < h.x + 0.1 and absf(p.y - c.y) < h.y + 0.1 and absf(p.z - c.z) < h.z + 0.1:
				return "the %s" % ["jars", "jar shelf", "hive"][OBSTACLES.find(o)]
		for f in feats:
			if Vector2(p.x - f[1], p.z - f[2]).length() < float(f[3]) + 0.15 and p.y < float(FEATURE_H[String(f[0])]) + 0.15:
				return "a %s" % f[0]
	return ""
