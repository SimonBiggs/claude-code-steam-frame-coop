extends RefCounted
## BALLOON POP rounds from a seed: the exact list of balloons a round lets go (when, where in the park,
## what kind, what colour, how fast it rises), made of little WAVES with shapes kids can read: a RING of
## one colour, a LINE sweeping across, a RAINBOW arc in colour order, a HEART, a STACK rising one after
## another at one spot, a mirrored PAIR, plain SCATTER. Rings, lines, rainbows and hearts are SETS: pop
## every balloon of a set before one floats away for a bonus. Later rounds (level = fair rides built)
## bring busier waves and more shapes; the ride being built (story.gd) brings its SPECIAL balloons.
## Same (seed, spec) -> same round on every machine (only the host uses it; clients see snapshots).
##
## FAIR + REACHABLE (check() is the validator; tests/balloon_pop_gen_test.gd runs it over many seeds):
## every balloon can be reached in time by the VR player walking from their spot (VR_HOME, VR_SPEED,
## arm's reach, a standing reach of VR_TOP) AND by a TV player running from the middle of the park
## (SPEED, jump reach TV_TOP), with a reaction time on top (a giant needs time for 3 hits too); grumpy
## balloons never float so close to a good one that you can't pop it without the grumpy; balloons never
## overlap; never too many reachable at once; never a long empty gap; only the spec's kinds; a fair star
## goal. Pure data, no nodes; a round is a few hundred tiny steps (well under a millisecond).

const Seeded := preload("res://core/seeded.gd")

## Balloon kinds (main.gd / balloon.gd draw and score them; one byte in the snapshot).
const NORMAL := 0
const GOLD := 1  ## 3 points
const GRUMPY := 2  ## DON'T pop: -1
const ROCKET := 3  ## zooms up: 2 points
const ICE := 4  ## pop it: every balloon slows right down for a few seconds
const TWINS := 5  ## pops into three little balloons
const MINI := 6  ## (from twins, not in rounds)
const GIANT := 7  ## three hits, 6 points
const CHOICE := 8  ## (a ride to build next, in the pick phase; not in rounds)
const KIND_NAMES: Array[String] = ["BALLOON", "GOLD", "GRUMPY", "ROCKET", "ICE", "TWINS", "MINI", "GIANT", "CHOICE"]
const POINTS: Array[int] = [1, 3, -1, 2, 1, 1, 1, 6, 0]
const HITS: Array[int] = [1, 1, 1, 1, 1, 1, 1, 3, 1]
const RISE_MULT: Array[float] = [1.0, 1.0, 0.9, 2.0, 0.9, 0.85, 0.7, 0.6, 0.0]
const RADIUS: Array[float] = [0.3, 0.3, 0.3, 0.28, 0.3, 0.36, 0.2, 0.55, 0.4]
const TWIN_MINIS := 3
const SET_BONUS := 3
const COLORS := 7  ## colour indexes 0..6 (balloon.gd COLORS)

## The park and the players (main.gd uses the same numbers).
const ARENA := 7.0
const SPAWN_Y := 0.35
const GIANT_Y := 0.7
const VR_HOME := Vector2(0.0, 2.0)  ## where the VR player starts (x, z)
const VR_SPEED := 2.0  ## core/vr_rig.gd move_speed
const VR_ARM := 0.7
const VR_TOP := 2.2  ## a balloon centre a standing VR player can reach
const TV_HOME := Vector2(0.0, 0.0)
const TV_SPEED := 5.0
const TV_TOP := 3.1  ## jump peak (1.56) + body (1.75) - a bit
const REACT := 0.8  ## seconds to notice a balloon
const GIANT_EXTRA := 1.5  ## seconds for three hits
const MIN_RISE := 0.16
const GRUMPY_GAP := 1.5  ## a grumpy's centre stays this far from every good balloon (drift included)
const MAX_GAP := 3.0
const CAP := 14  ## most balloons within reach at once
## Wave shapes and the level they start at.
const SHAPES := {"scatter": 0, "pair": 0, "line": 1, "ring": 1, "stack": 2, "rainbow": 2, "heart": 3}
const SETS: Array[String] = ["line", "ring", "rainbow", "heart"]


## spec: {time (s), level (0..), players (1..), kinds {kind: chance}, gold (chance), grumpy (chance),
## giants (how many, 0..2), rainbow (extra weight for rainbows), name}
## Returns {seed, time, level, spawns: [[t, kind, x, z, y0, rise, colour, set], ...] by time (set -1 =
## none), sets: [[first t, shape, count], ...], max (all points), goal [1, 2, 3 stars], kinds, cap, name}.
static func generate(seed_value: int, spec: Dictionary) -> Dictionary:
	var rng := Seeded.rng(seed_value, "waves")
	var krng := Seeded.rng(seed_value, "kinds")
	var time := maxf(8.0, float(spec.get("time", 120.0)))
	var level := maxi(0, int(spec.get("level", 0)))
	var players := clampi(int(spec.get("players", 1)), 1, 8)
	var d := clampf(level / 8.0, 0.0, 1.0)
	var kinds: Dictionary = spec.get("kinds", {})
	var gold_p := float(spec.get("gold", 0.08))
	var grumpy_p := float(spec.get("grumpy", 0.0))
	var spawns: Array = []
	var sets: Array = []
	var waves: Array = []
	var open: Array = []
	for k in SHAPES:
		if level >= int(SHAPES[k]):
			open.append(k)
	var giants: Array = []
	var ng := clampi(int(spec.get("giants", 0)), 0, 2) if time >= 30.0 else 0
	for i in ng:
		giants.append(snappedf(time * (0.35 + 0.35 * i) + rng.randf_range(-2.0, 2.0), 0.01))
	var end_t := time - 2.0
	var t := 1.0
	var last := ""
	var last_at := 0.0
	while t < end_t:
		var p := t / time
		var shape := "scatter"
		if t > 3.0:
			var w: Array = []
			for k in open:
				var wt := 2.5 if k == "scatter" else 1.0
				if k == "rainbow":
					wt += float(spec.get("rainbow", 0.0))
				if k == last:
					wt *= 0.3
				w.append(wt)
			shape = open[Seeded.weighted(rng, w)]
		last = shape
		var gap := lerpf(0.95, 0.45, p) * lerpf(1.35, 0.7, d) * lerpf(1.0, 0.8, clampf((players - 1) / 4.0, 0.0, 1.0))
		var base_rise := lerpf(0.34, 0.5, p) * lerpf(1.0, 1.25, d)
		var set_id := -1
		if SETS.has(shape):
			set_id = sets.size()
		var plan := _wave(shape, rng, gap)  # [[dt, x, z, colour or -1], ...]
		var made := 0
		var wave_end := t
		for step in plan:
			var at := snappedf(t + float(step[0]), 0.01)
			if at > end_t:
				break
			var kind := NORMAL
			if set_id < 0:
				kind = _kind(krng, kinds, gold_p, grumpy_p, p)
			if not giants.is_empty() and at >= float(giants[0]) and set_id < 0:
				giants.pop_front()
				kind = GIANT
			last_at = _fill_gap(last_at, at, base_rise, spawns, rng, krng)
			var col := int(step[3]) if int(step[3]) >= 0 else krng.randi() % COLORS
			var s := _place(kind, at, Vector2(float(step[1]), float(step[2])), base_rise, col, set_id, spawns, rng)
			if s.is_empty():
				continue
			spawns.append(s)
			last_at = at
			made += 1
			wave_end = maxf(wave_end, at)
		if set_id >= 0:
			if made == plan.size():
				sets.append([snappedf(t, 0.01), shape, made])
			else:  # part of the set didn't fit: its balloons are just balloons
				for s in spawns:
					if int(s[7]) == set_id:
						s[7] = -1
		if made == 0:  # nothing fitted (the sky is full): try again a moment later
			t += 0.5
			continue
		waves.append([snappedf(t, 0.01), shape])
		t = maxf(wave_end + gap * rng.randf_range(1.4, 2.2), t + 0.8)
	spawns.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var mx := 0
	var used := {}
	for s in spawns:
		var k := int(s[1])
		mx += maxi(0, POINTS[k]) + (TWIN_MINIS * POINTS[MINI] if k == TWINS else 0)
		used[k] = true
	mx += SET_BONUS * sets.size()
	var used_list: Array = used.keys()
	used_list.sort()
	return {"seed": seed_value, "time": time, "level": level, "spawns": spawns, "sets": sets, "waves": waves, "max": mx,
		"goal": goal(mx, players), "kinds": used_list, "cap": CAP, "name": str(spec.get("name", ""))}


## Keep the sky busy: if nothing would be let go for too long (a wave's balloons didn't fit), let a
## plain balloon go near the middle in between. Returns the time of the last balloon let go.
static func _fill_gap(last_at: float, at: float, base_rise: float, spawns: Array, rng: RandomNumberGenerator,
		krng: RandomNumberGenerator) -> float:
	while last_at > 0.0 and at - last_at > MAX_GAP - 0.4:
		var placed := -1.0
		var ft := snappedf(last_at + MAX_GAP * 0.5, 0.01)
		while placed < 0.0 and ft < last_at + MAX_GAP - 0.1:
			for attempt in 10:
				var q := Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 3.0))
				var s := _place(NORMAL, ft, q, base_rise, krng.randi() % COLORS, -1, spawns, rng)
				if not s.is_empty():
					spawns.append(s)
					placed = ft
					break
			ft = snappedf(ft + 0.3, 0.01)
		if placed < 0.0:
			break  # the sky is full: plenty to pop
		last_at = placed
	return last_at


## The star goal: points for 1, 2 and 3 stars, a share of every point the round holds (more players pop
## more), never above 85% of everything.
static func goal(mx: int, players: int) -> Array:
	var f: float = [0.22, 0.3, 0.36, 0.4, 0.44][clampi(players, 1, 5) - 1]
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


## Seconds a balloon is within reach of the VR player / a TV player (from when it appears).
static func vr_window(kind: int, y0: float, rise: float) -> float:
	return (VR_TOP - y0) / maxf(rise, 0.001)


static func tv_window(kind: int, y0: float, rise: float) -> float:
	return (TV_TOP - y0) / maxf(rise, 0.001)


## Seconds to get there: the VR player walks from VR_HOME (an arm's length short), a TV player runs from
## the middle. Both notice it first (REACT); a giant needs time for its three hits.
static func vr_need(kind: int, pos: Vector2) -> float:
	return maxf(0.0, pos.distance_to(VR_HOME) - VR_ARM) / VR_SPEED + REACT + (GIANT_EXTRA if kind == GIANT else 0.0)


static func tv_need(kind: int, pos: Vector2) -> float:
	return pos.distance_to(TV_HOME) / TV_SPEED + REACT + (GIANT_EXTRA if kind == GIANT else 0.0)


## The fastest a balloon here may rise and still be fair to everyone.
static func max_rise(kind: int, pos: Vector2, y0: float) -> float:
	return minf((VR_TOP - y0) / vr_need(kind, pos), (TV_TOP - y0) / tv_need(kind, pos))


## Seconds a planned balloon counts as "up" (reachable by someone): until it floats above TV_TOP.
static func up_time(s: Array) -> float:
	return (TV_TOP - float(s[4])) / maxf(float(s[5]), 0.001)


## Place one balloon fairly (nudging it towards the middle if it can't rise slowly enough from there and
## away from grumpies), or [] if it can't fit.
static func _place(kind: int, at: float, want: Vector2, base_rise: float, col: int, set_id: int, spawns: Array,
		rng: RandomNumberGenerator) -> Array:
	var y0 := GIANT_Y if kind == GIANT else SPAWN_Y
	var pos := want.limit_length(ARENA - 0.6)
	for attempt in 6:
		var mr := max_rise(kind, pos, y0) * 0.92
		var rise := minf(base_rise * RISE_MULT[kind], mr)
		if rise >= MIN_RISE:
			var s := [at, kind, snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), y0, snappedf(rise, 0.001), col, set_id]
			if _fits(s, spawns, true):
				return s
		if set_id >= 0 and attempt >= 1:
			return []  # a shape keeps its shape (or isn't a set)
		pos = pos.lerp(Vector2(0.0, 1.0), 0.35) + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
	return []


## True when `s` overlaps no balloon up at the same time, keeps grumpies clear of good balloons, and the
## reachable count stays under CAP. gen = true adds a little slack on top of check()'s numbers.
static func _fits(s: Array, spawns: Array, gen: bool) -> bool:
	var at := float(s[0])
	var end := at + up_time(s)
	var n := 1
	for i in range(spawns.size() - 1, -1, -1):
		var o: Array = spawns[i]
		var o_at := float(o[0])
		if o_at + up_time(o) <= at or o_at >= end:
			continue
		n += 1
		var k1 := int(s[1])
		var k2 := int(o[1])
		var near := RADIUS[k1] + RADIUS[k2] + (0.1 if gen else 0.0)
		if (k1 == GRUMPY) != (k2 == GRUMPY):
			near = GRUMPY_GAP + (0.05 if gen else 0.0)
		if closest(s, o) < near:
			return false
	return n <= CAP


## The closest two planned balloons come while both are up (x and z stay put; y rises at its own rate).
static func closest(a: Array, b: Array) -> float:
	var t0 := maxf(float(a[0]), float(b[0]))
	var t1 := minf(float(a[0]) + up_time(a), float(b[0]) + up_time(b))
	if t1 < t0:
		return INF
	var dxz := Vector2(float(a[2]) - float(b[2]), float(a[3]) - float(b[3])).length()
	# y_a(t) - y_b(t) = c0 + c1 * t
	var c1 := float(a[5]) - float(b[5])
	var c0 := (float(a[4]) - float(a[5]) * float(a[0])) - (float(b[4]) - float(b[5]) * float(b[0]))
	var tm := clampf(-c0 / c1, t0, t1) if absf(c1) > 0.0001 else t0
	var dy := c0 + c1 * tm
	return sqrt(dxz * dxz + dy * dy)


## One wave's plan: [[seconds after the wave starts, x, z, colour (-1 = any)], ...].
static func _wave(shape: String, rng: RandomNumberGenerator, gap: float) -> Array:
	var out: Array = []
	var c := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.5, 2.0))  # the wave's middle
	match shape:
		"pair":  # two at once, mirrored either side of the middle line, twice
			for k in 2:
				var q := Vector2(rng.randf_range(1.0, 3.5), rng.randf_range(-3.5, 2.5))
				out.append([k * gap * 2.0, -q.x, q.y, -1])
				out.append([k * gap * 2.0, q.x, q.y, -1])
		"line":  # five of one colour sweep across, one after another
			var a := rng.randf() * PI
			var dir := Vector2(cos(a), sin(a))
			var col := rng.randi() % COLORS
			for k in 5:
				var q := c + dir * (k - 2) * 1.2
				out.append([k * 0.3, q.x, q.y, col])
		"ring":  # six of one colour in a ring, all at once
			var col := rng.randi() % COLORS
			var a0 := rng.randf() * TAU
			for k in 6:
				var a := a0 + k * TAU / 6.0
				out.append([0.0, c.x + cos(a) * 1.7, c.y + sin(a) * 1.7, col])
		"rainbow":  # seven in an arc, in rainbow order
			var a0 := rng.randf() * TAU
			for k in COLORS:
				var a := a0 + (k - 3) * 0.42
				out.append([k * 0.12, c.x + cos(a) * 2.4, c.y + sin(a) * 2.4, k])
		"heart":  # eight in a heart (seen from above), pink / red
			var pts: Array[Vector2] = [Vector2(0.0, -0.6), Vector2(-0.8, -1.2), Vector2(-1.6, -0.6), Vector2(-1.2, 0.5),
				Vector2(0.0, 1.6), Vector2(1.2, 0.5), Vector2(1.6, -0.6), Vector2(0.8, -1.2)]
			for k in pts.size():
				out.append([0.0, c.x + pts[k].x, c.y + pts[k].y, 0 if k % 2 == 0 else 5])
		"stack":  # four at one spot, one after another (a column)
			for k in 4:
				out.append([k * 1.9, c.x, c.y, -1])
		_:  # scatter (the middle one comes up near the VR player: TV players run faster)
			for k in 3:
				var q := Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-4.5, 3.5))
				if k == 1:
					q = VR_HOME + Vector2(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.6, 0.4))
				out.append([k * gap, q.x, q.y, -1])
	return out


static func _kind(r: RandomNumberGenerator, kinds: Dictionary, gold_p: float, grumpy_p: float, p: float) -> int:
	if p > 0.04 and r.randf() < gold_p:
		return GOLD
	if p > 0.08 and r.randf() < grumpy_p:
		return GRUMPY
	if p < 0.06 or kinds.is_empty():
		return NORMAL
	var keys: Array = kinds.keys()
	keys.sort()
	var w: Array = []
	var total := 0.0
	for k in keys:
		w.append(float(kinds[k]))
		total += float(kinds[k])
	if r.randf() >= total:  # weights are chances (sum < 1): the rest are plain balloons
		return NORMAL
	return int(keys[Seeded.weighted(r, w)])


## Planned balloons still up (reachable) at time `at`.
static func _up_count(spawns: Array, at: float) -> int:
	var n := 0
	for s in spawns:
		if float(s[0]) <= at and float(s[0]) + up_time(s) > at:
			n += 1
	return n


## The validator: an Array of reasons this round is unfair or broken (empty when fine).
## allowed: the kinds this round may hold ([] = any).
static func check(rd: Dictionary, allowed: Array = []) -> Array:
	var why: Array = []
	var spawns: Array = rd.get("spawns", [])
	var time := float(rd.get("time", 0.0))
	if spawns.size() < int((time - 3.0) * 0.65):
		why.append("too few balloons (%d in %d s)" % [spawns.size(), int(time)])
	var prev_t := 0.0
	var last_t := 0.0
	var first := true
	var giants := 0
	var set_count := {}
	var done: Array = []
	for s in spawns:
		var at := float(s[0])
		var kind := int(s[1])
		var pos := Vector2(float(s[2]), float(s[3]))
		var y0 := float(s[4])
		var rise := float(s[5])
		var col := int(s[6])
		var set_id := int(s[7])
		if at < prev_t:
			why.append("not in time order at %.2f" % at)
		prev_t = at
		if at < 0.5 or at + 1.0 > time:
			why.append("a balloon at %.2f is outside the round" % at)
		if kind < 0 or kind == MINI or kind >= CHOICE:
			why.append("bad kind %d" % kind)
			continue
		if not allowed.is_empty() and not allowed.has(kind):
			why.append("kind %s not allowed here" % KIND_NAMES[kind])
		if pos.length() > ARENA - 0.5:
			why.append("a balloon outside the park at %.2f (%s)" % [at, str(pos)])
		if col < 0 or col >= COLORS:
			why.append("bad colour %d" % col)
		if rise < MIN_RISE * 0.99 or rise > 1.5:
			why.append("a balloon rising at %.2f m/s" % rise)
		if kind != GRUMPY:
			if vr_window(kind, y0, rise) < vr_need(kind, pos):
				why.append("the VR player can't reach the %s at %.2f (%s)" % [KIND_NAMES[kind], at, str(pos)])
			if tv_window(kind, y0, rise) < tv_need(kind, pos):
				why.append("a TV player can't reach the %s at %.2f (%s)" % [KIND_NAMES[kind], at, str(pos)])
		if not first and at - last_t > MAX_GAP and _up_count(done, last_t + MAX_GAP) < 4:
			why.append("a long empty gap before %.2f" % at)
		last_t = at
		first = false
		if kind == GIANT:
			giants += 1
		if set_id >= 0:
			set_count[set_id] = int(set_count.get(set_id, 0)) + 1
			if kind != NORMAL:
				why.append("a %s in a set" % KIND_NAMES[kind])
		if not _fits(s, done, false):
			why.append("crowded at %.2f (overlap, a grumpy too close, or more than %d up)" % [at, CAP])
		done.append(s)
	if giants > 2:
		why.append("%d giants" % giants)
	if time < 30.0 and giants > 0:
		why.append("a giant in a short round")
	if not spawns.is_empty() and time - last_t > MAX_GAP + 2.5:
		why.append("the end of the round is empty (last balloon at %.2f of %d)" % [last_t, int(time)])
	var sets: Array = rd.get("sets", [])
	for i in sets.size():
		if int(set_count.get(i, 0)) != int(sets[i][2]) or int(sets[i][2]) < 4:
			why.append("set %d (%s) has %d balloons, wants %d" % [i, str(sets[i][1]), int(set_count.get(i, 0)), int(sets[i][2])])
	if set_count.size() != sets.size():
		why.append("balloons in sets that aren't listed")
	var g: Array = rd.get("goal", [])
	var mx := int(rd.get("max", 0))
	if g.size() != 3 or int(g[0]) < 1 or int(g[0]) >= int(g[1]) or int(g[1]) >= int(g[2]) or int(g[2]) > mx:
		why.append("bad star goal %s (max %d)" % [str(g), mx])
	return why
