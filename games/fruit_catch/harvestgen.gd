extends RefCounted
## FRUIT CATCH generator: every round is a HARVEST made from a seed, so the same seed gives the same
## round on every machine (the host sends [seed, level, daily, secs]; TV machines rebuild it), and
## tests/fruit_catch_gen_test.gd proves over many seeds that every harvest is catchable and fair.
##   var h := HarvestGen.harvest(seed, level, daily, secs)
##   h = {seed, level, daily, secs, dishes, drops, wind, storm_at, rotten}
## Story: NUTMEG the squirrel cooks for the forest friends. Each round she asks for DISH_COUNT DISHES in
## turn (three to finish, then bonus feasts) (apple pie, orange juice, pear crumble, plum jam, fruit salad); each dish is a recipe of fruit
## counts. Every finished round plants a little tree in the ORCHARD around the park (saved): trees grow
## a stage each day the family plays. TODAY'S HARVEST: the first round each day is the same gold
## harvest on every machine, and its tree is golden.
## dishes: [[dish index, [apples, oranges, pears, plums]], ...] (in order; the challenge rises dish by dish)
## drops: [[t, branch, kind, x, z], ...] by time: the tree drops fruit `kind` (0-3, ROTTEN = 4) at (x, z)
##   under the leaves `t` seconds into the round. With a VR giant (who shakes extra fruit down) every
##   odd drop is skipped (vr_skips()).
## wind: a breeze (m/s) the falling fruit drifts with (later levels). storm_at: the FRUIT STORM begins.
## check(h) is the validator: every fruit lands in the park (not in the trunk or the bowl), a rotten
## apple never lands right by a good fruit at the same moment, each recipe has enough of its fruit, and
## a small child alone (at KID_SHARE of full speed, going round the trunk) can finish the first dish
## early with or without a giant, and a quick player alone can finish all three dishes.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "fruit_catch"
const ARENA := 8.5  # == main.gd (the test checks)
const SPEED := 4.8  # == main.gd
const TRUNK_R := 0.9  # == main.gd
const BRANCHES := 5  # == main.gd
const DROP_HEIGHT := 4.1  # == main.gd
const FALL_G := 2.6  # == main.gd
const HANG_TIME := 0.45  # == main.gd
const BOWL_POS := Vector3(1.25, 0.0, 2.4)  # == main.gd
const BOWL_R := 0.75  # == main.gd
const CATCH_Y := 1.5  # about where a basket on a head catches (the avatars are 1.3-1.6 m)
const CATCH_R := 0.45  # how close under a fruit a basket must be (main.gd allows 0.6)
const START := Vector2(0.62, 3.53)  # where slot 0 starts (main.gd _ensure_avatar)
const ROUND_SECS := 120.0
const KID_SHARE := 0.55  # a small child runs at about this share of full speed (and wanders)
const MAX_LEVEL := 6
const DAILY_LEVEL := 3
const MAX_WIND := 0.8
const DISH_COUNT := 5  # dishes per round: 3 to finish, then 2 bonus feasts for quick teams
const TRIES := 6

const APPLE := 0
const ORANGE := 1
const PEAR := 2
const PLUM := 3
const ROTTEN := 4
const GOOD := 4  # kinds 0..3 are good fruit
const KIND_NAMES: Array[String] = ["APPLE", "ORANGE", "PEAR", "PLUM"]
const KIND_PICS: Array[String] = ["apple", "orange", "pear", "plum"]
const DISHES: Array[String] = ["pie", "juice", "crumble", "jam", "salad"]
const DISH_NAMES: Array[String] = ["APPLE PIE", "ORANGE JUICE", "PEAR CRUMBLE", "PLUM JAM", "FRUIT SALAD"]
const DISH_PICS: Array[String] = ["pie", "juice", "crumble", "jamjar", "fruitbowl"]
const DISH_MAIN: Array[int] = [APPLE, ORANGE, PEAR, PLUM, -1]
const SALAD := 4

const ORCHARD_SLOTS := 36
const ORCHARD_R: Array[float] = [10.0, 11.4]  # two staggered rows behind the park
const ORCHARD_A0 := PI * 1.06  # the arc behind the big tree (z < 0), seen past it from the TV and VR
const ORCHARD_A1 := PI * 1.94
const ORCHARD_KEEP := 36  # saved trees (the oldest make room after this)


## Seconds to fall from height a to height b (no air drag reaches MAX speed over these heights).
static func fall_time(a: float, b: float) -> float:
	return sqrt(2.0 * maxf(a - b, 0.0) / FALL_G)


## The day's harvest seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## Round n's seed in a session.
static func round_seed(session_seed: int, round_n: int) -> int:
	return Seeded.derive(session_seed, "round%d" % round_n)


## How hard round n is, given how many trees the orchard already has (more trees, a bit harder start).
static func level(round_n: int, trees: int) -> int:
	return clampi(1 + mini(2, trees / 6) + maxi(0, round_n - 1), 1, MAX_LEVEL)


## The harvest for a seed. A try that check() finds unfair is thrown away and the next try (a sub-seed) is
## used, so every machine still gets the same harvest; the gentlest try is the last resort.
static func harvest(seed_value: int, lv: int, daily: bool = false, secs: float = ROUND_SECS) -> Dictionary:
	var h := {}
	for attempt in TRIES:
		h = _make(seed_value if attempt == 0 else Seeded.derive(seed_value, "try%d" % attempt), lv, daily, secs, attempt)
		if check(h).is_empty():
			break
	h.seed = seed_value
	return h


static func _make(seed_value: int, lv: int, daily: bool, secs: float, attempt: int) -> Dictionary:
	lv = clampi(lv, 1, MAX_LEVEL)
	var lf := float(lv - 1) / float(MAX_LEVEL - 1)
	var scale := clampf(secs / ROUND_SECS, 0.08, 1.5) * (1.0 - 0.1 * attempt)
	var r := Seeded.rng(seed_value, "dishes")
	# Three dishes, the third the biggest. A salad needs several kinds (later levels / today's feast).
	var order := Seeded.shuffled(r, [0, 1, 2, 3])
	var dishes: Array = []
	for d in DISH_COUNT:
		var dish: int = order[mini(d, 3)]
		if (d == 2 and (lv >= 4 or daily)) or d == 4:
			dish = SALAD
		var need := [0, 0, 0, 0]
		var size := lerpf(3.0, 6.0, lf) * (1.0 + 0.3 * d) * (1.25 if d >= 3 else 1.0)
		if dish == SALAD:
			var kinds := Seeded.shuffled(r, [0, 1, 2, 3]).slice(0, 3 if lv < 6 else 4)
			for k in kinds:
				need[k] = maxi(1, roundi(size * scale / kinds.size() + r.randf_range(-0.4, 0.6)))
		else:
			var main_k: int = DISH_MAIN[dish]
			need[main_k] = maxi(1, roundi(size * scale * (0.75 if lv >= 3 and d >= 1 else 1.0)))
			if lv >= 3 and d >= 1:  # a pinch of something else
				var other: int = Seeded.pick(r, [0, 1, 2, 3].filter(func(k: int) -> bool: return k != main_k))
				need[other] = maxi(1, roundi(size * scale * 0.25))
		dishes.append([dish, need])
	var wind := Vector2.ZERO
	var rw := Seeded.rng(seed_value, "wind")
	if daily:
		wind = Vector2.from_angle(rw.randf() * TAU) * 0.3
	elif lv >= 3:
		wind = Vector2.from_angle(rw.randf() * TAU) * lerpf(0.25, MAX_WIND, float(lv - 3) / 3.0)
	var storm_at := secs - minf(20.0, secs * 0.25)
	var rotten := lerpf(0.08, 0.2, lf)
	# How much of each good kind the round needs in all: the tree favours those.
	var want := [0.0, 0.0, 0.0, 0.0]
	for dd in dishes:
		for k in GOOD:
			want[k] += float((dd[1] as Array)[k])
	var drops := _drops(Seeded.rng(seed_value, "drops"), lf, secs, storm_at, rotten, want, wind)
	return {"seed": seed_value, "level": lv, "daily": daily, "secs": secs, "dishes": dishes, "drops": drops,
		"wind": wind, "storm_at": storm_at, "rotten": rotten}


static func _drops(r: RandomNumberGenerator, lf: float, secs: float, storm_at: float, rotten: float, want: Array, wind: Vector2) -> Array:
	var out: Array = []
	var t := 1.5
	var gap := lerpf(0.95, 0.72, lf)
	var total := 0.0
	for w in want:
		total += float(w)
	while t < secs - 0.5:
		var kind := ROTTEN if r.randf() < rotten else -1
		if kind < 0:
			kind = Seeded.weighted(r, want) if r.randf() < 0.6 and total > 0.0 else r.randi() % GOOD
		var placed := false
		var d := []
		for attempt in 12:
			var k := r.randi() % BRANCHES
			var a := PI * 0.5 + k * TAU / BRANCHES + r.randf_range(-0.7, 0.7)
			var home := Vector2(cos(a), sin(a)) * r.randf_range(1.3, 4.6)
			d = [snappedf(t, 0.01), k, kind, snappedf(home.x, 0.01), snappedf(home.y, 0.01)]
			if _drop_problem(d, wind, out).is_empty():
				placed = true
				break
		if placed:
			out.append(d)
		t += gap * (0.55 if t >= storm_at else 1.0) * r.randf_range(0.85, 1.15)
	return out


## Where a drop is when it reaches basket height / the ground (it drifts with the wind while falling).
static func catch_point(d: Array, wind: Vector2) -> Vector2:
	return Vector2(float(d[3]), float(d[4])) + wind * fall_time(DROP_HEIGHT, CATCH_Y)


static func land_point(d: Array, wind: Vector2) -> Vector2:
	return Vector2(float(d[3]), float(d[4])) + wind * fall_time(DROP_HEIGHT, 0.0)


static func catch_time(d: Array) -> float:
	return float(d[0]) + HANG_TIME + fall_time(DROP_HEIGHT, CATCH_Y)


## Why a drop is unfair here (empty = fine): it must land in the park, clear of the trunk and the bowl,
## and a rotten apple never comes down right by a good fruit at the same moment (or the other way round).
static func _drop_problem(d: Array, wind: Vector2, earlier: Array) -> String:
	var home := Vector2(float(d[3]), float(d[4]))
	if home.length() < TRUNK_R + 0.3 or home.length() > 4.9:
		return "fruit appears outside the leaves"
	for p in [catch_point(d, wind), land_point(d, wind)]:
		var q: Vector2 = p
		if q.length() > ARENA - 0.6:
			return "fruit lands outside the park"
		if q.length() < TRUNK_R + 0.35:
			return "fruit lands in the trunk"
		if q.distance_to(Vector2(BOWL_POS.x, BOWL_POS.z)) < BOWL_R + 0.35:
			return "fruit lands in the bowl"
	var rot := int(d[2]) == ROTTEN
	for i in range(earlier.size() - 1, -1, -1):
		var e: Array = earlier[i]
		if float(d[0]) - float(e[0]) > 0.8:
			break
		if (int(e[2]) == ROTTEN) != rot and catch_point(e, wind).distance_to(catch_point(d, wind)) < 1.2:
			return "a rotten apple falls right by a good fruit"
	return ""


## Drops the game skips when a VR giant shakes the branches (the tree drops half as often by itself).
static func vr_skips(i: int) -> bool:
	return i % 2 == 1


## What a branch the giant shakes drops: mostly fruit the current dish still needs.
static func shake_kind(r: RandomNumberGenerator, need_left: Array, rotten: float) -> int:
	if r.randf() < rotten * 0.6:
		return ROTTEN
	var w := []
	var any := false
	for k in GOOD:
		w.append(maxf(0.0, float(need_left[k]) if k < need_left.size() else 0.0))
		any = any or float(w[k]) > 0.0
	if any and r.randf() < 0.75:
		return Seeded.weighted(r, w)
	return r.randi() % GOOD


## Walking distance on the ground from a to b, going round the trunk.
static func path_len(a: Vector2, b: Vector2) -> float:
	var d := a.distance_to(b)
	var ab := b - a
	var t := clampf(-a.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var closest := (a + ab * t).length()
	var rr := TRUNK_R + 0.35
	if closest < rr:
		d += (rr - closest) * 2.0 + rr * 0.6
	return d


## One player alone, greedy: runs under the next fruit the current dish needs when they can get there in
## time. share = share of full speed; vr = a giant is here (the tree drops half as much by itself).
## Returns the times each dish was finished (fewer entries = dishes not finished).
static func solo(h: Dictionary, share: float, vr: bool) -> Array:
	var pos := START
	var free_t := 0.0
	var dish := 0
	var dishes: Array = h.dishes
	var got := [0, 0, 0, 0]
	var done: Array = []
	var drops: Array = h.drops
	for i in drops.size():
		if vr and vr_skips(i):
			continue
		var d: Array = drops[i]
		var kind := int(d[2])
		if kind == ROTTEN:
			continue
		var need: Array = (dishes[dish] as Array)[1]
		if int(got[kind]) >= int(need[kind]):
			continue
		var ct := catch_time(d)
		if ct > float(h.secs):
			break
		var p := catch_point(d, h.wind)
		var dist := maxf(0.0, path_len(pos, p) - CATCH_R)
		if free_t + dist / (SPEED * share) <= ct:
			pos = p
			free_t = ct
			got[kind] = int(got[kind]) + 1
			var finished := true
			for k in GOOD:
				if int(got[k]) < int(need[k]):
					finished = false
			if finished:
				done.append(snappedf(ct, 0.01))
				dish += 1
				got = [0, 0, 0, 0]
				if dish >= dishes.size():
					break
	return done


## Problems with a harvest (empty = fine).
static func check(h: Dictionary) -> Array:
	var out: Array = []
	var dishes: Array = h.dishes
	var secs := float(h.secs)
	if dishes.size() != DISH_COUNT:
		out.append("a harvest has %d dishes" % DISH_COUNT)
		return out
	for dd in dishes:
		var dish := int(dd[0])
		var need: Array = dd[1]
		if dish < 0 or dish >= DISHES.size() or need.size() != GOOD:
			out.append("bad dish %s" % str(dd))
			continue
		var kinds := 0
		var sum := 0
		for k in GOOD:
			if int(need[k]) < 0:
				out.append("negative fruit in a recipe")
			if int(need[k]) > 0:
				kinds += 1
			sum += int(need[k])
		if sum < 1 or sum > 20:
			out.append("recipe size %d is out of range" % sum)
		if dish == SALAD and kinds < 3:
			out.append("a fruit salad needs at least three kinds")
		if dish != SALAD and int(need[DISH_MAIN[dish]]) < 1:
			out.append("%s needs its own fruit" % DISH_NAMES[dish])
	if (h.wind as Vector2).length() > MAX_WIND + 0.001:
		out.append("too windy")
	if float(h.storm_at) < secs * 0.7 or float(h.storm_at) > secs:
		out.append("the fruit storm comes at a strange time")
	var drops: Array = h.drops
	if drops.size() < secs / 1.4:
		out.append("too few drops (%d)" % drops.size())
	var prev := -1.0
	var rotten := 0
	var have := [0, 0, 0, 0]
	var earlier: Array = []
	for d in drops:
		if float(d[0]) < prev or float(d[0]) > secs:
			out.append("drops out of order / after the round")
			break
		if float(d[0]) - prev < 0.25:
			out.append("two drops too close together")
		prev = float(d[0])
		if int(d[1]) < 0 or int(d[1]) >= BRANCHES or int(d[2]) < 0 or int(d[2]) > ROTTEN:
			out.append("bad drop %s" % str(d))
			continue
		var why := _drop_problem(d, h.wind, earlier)
		if why != "":
			out.append("%s (t %.2f)" % [why, float(d[0])])
		earlier.append(d)
		if int(d[2]) == ROTTEN:
			rotten += 1
		else:
			have[int(d[2])] += 1
	if drops.size() >= 20 and float(rotten) / drops.size() > 0.3:
		out.append("too many rotten apples")
	var want := [0, 0, 0, 0]
	for dd in dishes.slice(0, 3):
		for k in GOOD:
			want[k] += int((dd[1] as Array)[k])
	for k in GOOD:
		if int(have[k]) < int(want[k]) * (2 if secs >= 60.0 else 1):
			out.append("not enough %s fruit (%d for %d)" % [KIND_NAMES[k], int(have[k]), int(want[k])])
	# A small child alone finishes the first dish well inside the round (with and without a giant);
	# a quick player alone finishes all three.
	# (Short bot rounds only need the first dish.)
	var long := secs >= 60.0
	var kid := solo(h, KID_SHARE, false)
	if kid.is_empty() or float(kid[0]) > secs * (0.6 if long else 0.9):
		out.append("a small child can't finish the first dish early (%s)" % str(kid))
	var kid_vr := solo(h, KID_SHARE, true)
	if kid_vr.is_empty() or float(kid_vr[0]) > secs * (0.75 if long else 0.95):
		out.append("with a giant, a small child can't finish the first dish (%s)" % str(kid_vr))
	if long and solo(h, 1.0, false).size() < 3:
		out.append("a quick player alone can't finish all three dishes")
	return out


## Orchard spot i (Vector3.INF past the end): two staggered rows on an arc behind the park.
static func orchard_slot(i: int) -> Vector3:
	if i < 0 or i >= ORCHARD_SLOTS:
		return Vector3.INF
	var per_row := ORCHARD_SLOTS / 2
	var row := i % 2
	var col := i / 2
	# Fill from the middle outwards so the first trees stand right behind the big tree.
	var order := (col + 1) / 2 * (1 if col % 2 == 1 else -1)
	var f := 0.5 + (float(order) + (0.25 if row == 1 else 0.0)) / float(per_row)
	var a := lerpf(ORCHARD_A0, ORCHARD_A1, f)
	var rr: float = ORCHARD_R[row]
	return Vector3(cos(a) * rr, 0.0, sin(a) * rr)


## A tree's growth stage (1 sapling, 2 blossom, 3 fruit) from the play-day it was planted on.
static func tree_stage(planted_day: int, days: int) -> int:
	return clampi(1 + days - planted_day, 1, 3)
