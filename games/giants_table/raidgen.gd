extends RefCounted
## GIANT'S TABLE raid generator: every wave's goblin LADDERS (where they climb up the table edge), what comes up
## them in what order and how fast, and where balloon goblins float down, as plain data from a seed, so the host
## and every TV machine see the same ladders from [raid seed, wave] and tests/giants_table_gen_test.gd proves over
## many seeds that every wave is fair and finishable by one small kid playing the Giant alone (or with knights).
##   var plan := RaidGen.plan(raid_seed, wave, extra_knights, solo)
##   plan = {n, extra, solo, ladders: [angle...] (radians; dir = (cos a, 0, sin a); the Giant sits at PI/2),
##           spawns: [[kind, angle, gap seconds before it, balloon landing radius (0 for walkers)], ...] (in order)}
##   RaidGen.ladders(raid_seed, wave) = just the ladders (the same for every party size: the TV builds them).
## Story: SPARKY, the campfire's little flame, lives in the middle of the village. Clearing NIGHT_WAVES waves (the
## Goblin King's wave) saves the village for the night: the villagers leave the Giant a GIFT on the far rim (saved,
## a gold star on TODAY'S RAID), a LANTERN joins the rim each play-day, and with CROWN_NIGHTS saved nights Sparky
## wears a crown. TODAY'S RAID: the first game each day uses the day's seed on every machine.
## check(plan) is the validator: one ladder for waves 1-2 (on the Giant's side), two from wave 3, two or three from
## wave 6; the first ladder always on the Giant's side; ladders spread apart, never where the river leaves the
## table or on a boulder's spot, with a walkable path to the campfire for small and big goblins that takes long
## enough to react to; new kinds of goblin only from their wave (balloons 4, ogre 5, king 6 and every 3rd, spiky 7
## and only with knights), the first one up always a plain goblin; balloons land on dry open ground near the fire;
## and a small kid (KID_CATCH seconds per goblin, knights KNIGHT_CATCH) loses no ember in waves 1-2, at most one a
## wave in the night and never lets the fire drop below NIGHT_MIN_EMBERS (kid_sim).
## (main.gd also sends the next goblin early when the table is empty: that only helps a kid who is waiting.)

const Seeded := preload("res://core/seeded.gd")
const W := preload("res://games/giants_table/world.gd")

const GAME_ID := "giants_table"
const GIANT_A := PI / 2.0  # the Giant's seat (recenter(0) puts the eyes at +z)
const GIANT_SIDE := deg_to_rad(50.0)  # "on the Giant's side": this close to GIANT_A
const LADDER_GAP := deg_to_rad(60.0)  # ladders at least this far apart
const LAND_R := 13.8  # where a climbing goblin starts walking (a little inside, to be safe)
const JITTER := 0.06  # radians: goblins on one ladder don't all climb the same rung
const BOULDERS := 8  # == main.gd BOULDER_COUNT (their first spots: TAU * (i + 0.5) / 8 at W.R - 0.2)
const BOULDER_CLEAR := deg_to_rad(6.0)
const BALLOON_R := Vector2(3.0, 4.5)
const BALLOON_H := 13.0  # == main.gd: balloons start this high
const BALLOON_FALL := 1.1  # == goblin.gd BALLOON_FALL
const SPEED := {"goblin": 2.2, "armored": 1.7, "ogre": 1.15, "balloon": 2.4, "king": 1.0}  # == goblin.gd KINDS
const CARRY_SLOW := 0.85  # == goblin.gd (a goblin with an ember walks at 85 %)
const HOP_T := 0.2  # climbing up onto the table
const MIN_WALK := 4.0  # seconds: the quickest goblin needs at least this long from the ladder to the fire
## A small kid playing the Giant: seconds to notice, reach, grab and throw (or squash) one goblin.
const KID_CATCH := {"goblin": 4.0, "balloon": 4.0, "ogre": 6.0, "king": 6.0}  # (spiky ones: knights only)
## A small kid playing a knight: seconds to run over and bonk one (ogres and the King: the Giant only).
const KNIGHT_CATCH := {"goblin": 6.0, "balloon": 6.0, "armored": 9.0}
const BALLOON_EARLY := 3.0  # the Giant can pluck a balloon goblin this long before it lands
const MIN_GAP := 0.5
const MAX_SPAWN_SECS := 120.0  # a wave's goblins are all up within this (it stays lively)
const NIGHT_WAVES := 6  # clear the Goblin King's wave: the village is saved for the night
const NIGHT_MIN_EMBERS := 6  # == the fire never drops below this for the slow kid over a night (of MAX_EMBERS)
const MAX_EMBERS := 10  # == main.gd
const MAX_WAVE := 14  # the validator's reach (later waves have wave 14's numbers; only the King's turn moves)
const STRETCH := 1.07
const STRETCH_TRIES := 40

## The villagers' gifts (one per saved night, in order, then round and round). Pictures: pie (Fruit Catch), cake,
## teddy (this game), scarf (Snowball Blitz), bunting (Cannon Cove), daisy (Bee Garden).
const GIFTS: Array[String] = ["pie", "cake", "teddy", "scarf", "bunting", "daisy"]
const GIFT_KEEP := 12  # gifts on the far rim (the oldest makes room)
const GIFT_STEP := deg_to_rad(8.5)
const LANTERNS_MAX := 16  # one per play-day round the rim
const LANTERN_FIRST := deg_to_rad(330.0)
const LANTERN_STEP := deg_to_rad(14.0)
const CROWN_NIGHTS := 5


## The day's raid seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


static func wave_seed(raid_seed: int, n: int) -> int:
	return Seeded.derive(raid_seed, "wave%d" % n)


## How many ladders wave n has (rng only past wave 5).
static func ladder_count(n: int, rng: RandomNumberGenerator = null) -> int:
	if n <= 2:
		return 1
	if n <= 5:
		return 2
	return 3 if rng != null and rng.randf() < 0.5 else 2


## The ladders of wave n: a list of angles (the first on the Giant's side). Every machine builds these.
static func ladders(raid_seed: int, n: int) -> Array:
	n = maxi(1, n)
	var rng := Seeded.rng(wave_seed(raid_seed, n), "ladders")
	var want := ladder_count(n, rng)
	var out: Array = []
	var tries := 0
	while out.size() < want and tries < 300:
		tries += 1
		var a: float
		if out.is_empty() or n <= 2:
			a = GIANT_A + rng.randf_range(-GIANT_SIDE, GIANT_SIDE) * 0.95
		else:
			a = rng.randf() * TAU
		a = snappedf(fposmod(a, TAU), 0.001)
		if _ladder_ok(a, out).is_empty():
			out.append(a)
	return out


## The whole wave plan for this party (extra = knights beyond two, solo = no knights at all).
static func plan(raid_seed: int, n: int, extra: int = 0, solo: bool = true) -> Dictionary:
	n = maxi(1, n)
	extra = clampi(extra, 0, 4)
	if solo:
		extra = 0
	var p := {"n": n, "extra": extra, "solo": solo, "ladders": ladders(raid_seed, n)}
	var rng := Seeded.rng(wave_seed(raid_seed, n), "spawns%d%s" % [extra, "s" if solo else ""])
	# What comes (as simple mode always had it: plain goblins, then one new thing per wave).
	var more := 1.0 + 0.3 * extra
	var kinds: Array = []
	for i in roundi((3 + mini(n, 8)) * more):  # (capped: a small kid can't throw goblins all evening)
		kinds.append("goblin")
	if n >= 4:
		for i in roundi(mini(n - 2, 4) * more):
			kinds.append("balloon")
	if n >= 5:
		for i in mini(1 + (n - 5) / 3, 3):
			kinds.append("ogre")
	if n >= 7 and not solo:
		for i in roundi(mini(n - 6, 4) * more):
			kinds.append("armored")
	kinds = Seeded.shuffled(rng, kinds)
	kinds.push_front("goblin")  # the first one up is always an easy one
	if n >= 6 and n % 3 == 0:
		kinds.append("king")  # the King comes last, after his army
	var lad: Array = p.ladders
	var base := maxf(1.0, 2.0 - n * 0.08) / (1.0 + 0.15 * extra)
	var spawns: Array = []
	for i in kinds.size():
		var kind: String = kinds[i]
		var gap := 0.5 if i == 0 else snappedf(base * rng.randf_range(0.8, 1.25), 0.01)
		if kind == "king":
			gap = maxf(gap, 3.0)  # a breath before the King
		if kind == "balloon":
			var a := snappedf(rng.randf() * TAU, 0.001)
			var r := snappedf(rng.randf_range(BALLOON_R.x, BALLOON_R.y), 0.01)
			for _t in 60:
				if _balloon_ok(a, r).is_empty():
					break
				a = snappedf(rng.randf() * TAU, 0.001)
				r = snappedf(rng.randf_range(BALLOON_R.x, BALLOON_R.y), 0.01)
			if not _balloon_ok(a, r).is_empty():
				a = GIANT_A  # (a known dry, open spot in front of the Giant)
				r = 3.5
			spawns.append([kind, a, gap, r])
		else:
			var li := 0 if i == 0 else rng.randi() % lad.size()
			spawns.append([kind, snappedf(fposmod(float(lad[li]) + rng.randf_range(-JITTER, JITTER), TAU), 0.001), gap, 0.0])
	p.spawns = spawns
	# Too quick for a small kid? Spread the goblins out until it isn't; if that makes the wave drag, one plain
	# goblin fewer (never the first) and try again from the first gaps.
	var first: Array = spawns.duplicate(true)
	while true:
		for _t in STRETCH_TRIES:
			if _kid_fails(p).is_empty():
				break
			for i in range(1, spawns.size()):
				spawns[i][2] = snappedf(float(spawns[i][2]) * STRETCH, 0.01)
		var total := 0.0
		for sp in spawns:
			total += float(sp[2])
		var drop := -1
		for i in range(first.size() - 1, 0, -1):
			if String(first[i][0]) == "goblin":
				drop = i
				break
		if total <= MAX_SPAWN_SECS or drop < 0 or first.size() <= 4:
			break
		first.remove_at(drop)
		spawns = first.duplicate(true)
		p.spawns = spawns
	return p


## Problems with one wave plan (empty = fair).
static func check(p: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var n := int(p.n)
	var lad: Array = p.ladders
	var want_min := 1 if n <= 2 else 2
	var want_max := 1 if n <= 2 else (2 if n <= 5 else 3)
	if lad.size() < want_min or lad.size() > want_max:
		why.append("wave %d has %d ladders (wants %d-%d)" % [n, lad.size(), want_min, want_max])
	for i in lad.size():
		var a := float(lad[i])
		for w in _ladder_ok(a, lad.slice(0, i)):
			why.append(w)
		if (i == 0 or n <= 2) and _side_dist(a) > GIANT_SIDE + 0.001:
			why.append("wave %d: ladder %d at %.0f deg is not on the Giant's side" % [n, i, rad_to_deg(a)])
	var spawns: Array = p.spawns
	if spawns.is_empty():
		why.append("wave %d has no goblins" % n)
		return why
	if String(spawns[0][0]) != "goblin":
		why.append("wave %d: the first one up is a %s, not a plain goblin" % [n, spawns[0][0]])
	elif not lad.is_empty() and absf(angle_difference(float(spawns[0][1]), float(lad[0]))) > JITTER + 0.002:
		why.append("wave %d: the first goblin isn't on the Giant's-side ladder" % n)
	var total := 0.0
	for i in spawns.size():
		var s: Array = spawns[i]
		var kind := String(s[0])
		total += float(s[2])
		if float(s[2]) < MIN_GAP - 0.001 and i > 0:
			why.append("wave %d: goblin %d comes only %.2f s after the last" % [n, i, s[2]])
		match kind:
			"balloon":
				if n < 4:
					why.append("wave %d: a balloon goblin before wave 4" % n)
				for w in _balloon_ok(float(s[1]), float(s[3])):
					why.append("wave %d: %s" % [n, w])
			"ogre":
				if n < 5:
					why.append("wave %d: an ogre before wave 5" % n)
			"king":
				if n < 6 or n % 3 != 0 or i != spawns.size() - 1:
					why.append("wave %d: the King comes at the wrong time" % n)
			"armored":
				if n < 7 or bool(p.solo):
					why.append("wave %d: a spiky goblin %s" % [n, "with no knights" if bool(p.solo) else "before wave 7"])
		if kind != "balloon":
			var near := false
			for a in lad:
				if absf(angle_difference(float(s[1]), float(a))) <= JITTER + 0.002:
					near = true
			if not near:
				why.append("wave %d: goblin %d doesn't come up a ladder" % [n, i])
	if total > MAX_SPAWN_SECS:
		why.append("wave %d takes %.0f s to send its goblins (too slow to be fun)" % [n, total])
	why.append_array(_kid_fails(p))
	return why


## A night (waves 1..NIGHT_WAVES) for one party: every wave is fair and the slow kid's fire never runs low.
static func check_night(raid_seed: int, extra: int, solo: bool) -> Array[String]:
	var why: Array[String] = []
	var e := MAX_EMBERS
	for n in range(1, NIGHT_WAVES + 1):
		var p := plan(raid_seed, n, extra, solo)
		for w in check(p):
			why.append(w)
		e -= int(kid_sim(p).lost)
		if e < NIGHT_MIN_EMBERS:
			why.append("the slow kid's fire is down to %d embers by wave %d" % [e, n])
		e = mini(e + 1, MAX_EMBERS)  # +1 ember for every cleared wave (main.gd _end_wave)
	return why


## The slow-kid model: the Giant (and each knight) deals with one goblin at a time, KID_CATCH / KNIGHT_CATCH
## seconds each, in order of who would get away first. A goblin gets away with an ember when it has walked in
## (the quickest path, no slowing in the river), stolen and walked out before anybody got to it.
## Returns {lost: embers that got away, end: when the last goblin was dealt with, knights: helpers}.
static func kid_sim(p: Dictionary) -> Dictionary:
	var knights := 0 if bool(p.solo) else (1 if int(p.extra) == 0 else 2 + int(p.extra))
	var free: Array = []
	free.resize(1 + knights)
	free.fill(0.0)
	var jobs: Array = []
	var t := 0.0
	for s in p.spawns:
		t += float(s[2])
		var kind := String(s[0])
		var spd: float = SPEED[kind]
		var a := float(s[1])
		var big := kind == "ogre" or kind == "king"
		var job := {"kind": kind}
		if kind == "balloon":
			var land := t + BALLOON_H / BALLOON_FALL
			var walk := float(s[3]) / spd
			job.giant_from = land - BALLOON_EARLY
			job.knight_from = land
			job.deadline = land + walk + walk_secs(a, false) / CARRY_SLOW / spd * SPEED.goblin
		else:
			var w := walk_secs(a, big) * SPEED.goblin / spd
			job.giant_from = t + HOP_T
			job.knight_from = t + HOP_T + 1.0  # (knights stand nearer the fire: a moment to get there)
			job.deadline = t + HOP_T + w + w / CARRY_SLOW
		jobs.append(job)
	jobs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.deadline < y.deadline)
	var lost := 0
	var end := 0.0
	for j in jobs:
		var best := INF
		var who := -1
		for h in free.size():
			var dur: float = KID_CATCH.get(j.kind, INF) if h == 0 else KNIGHT_CATCH.get(j.kind, INF)
			if dur == INF:
				continue
			var fin := maxf(float(free[h]), float(j.giant_from if h == 0 else j.knight_from)) + dur
			if fin < best:
				best = fin
				who = h
		if who < 0 or best > float(j.deadline):
			lost += 1
			continue
		free[who] = best
		end = maxf(end, best)
	return {"lost": lost, "end": end, "knights": knights}


## Seconds the quickest plain goblin needs from a ladder at angle a to the campfire (flow-field steps, straight).
static func walk_secs(a: float, big: bool) -> float:
	var steps := _steps(Vector3(cos(a), 0.0, sin(a)) * LAND_R, big)
	return INF if steps < 0 else steps * W._cell() / SPEED.goblin


static func _steps(pos: Vector3, big: bool) -> int:
	var f := W.field(big, false)
	var cs := W._cell()
	var i := int((pos.x + W.EDGE) / cs)
	var j := int((pos.z + W.EDGE) / cs)
	if i < 0 or j < 0 or i >= W.GRID or j >= W.GRID:
		return -1
	return f[j * W.GRID + i]


static func _kid_fails(p: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var n := int(p.n)
	var lost := int(kid_sim(p).lost)
	var allowed := 0 if n <= 2 else (1 if n <= NIGHT_WAVES else 2)
	if lost > allowed:
		why.append("wave %d is too quick for a small kid (%d embers lost, %d knights)" % [n, lost, kid_sim(p).knights])
	return why


static func _side_dist(a: float) -> float:
	return absf(angle_difference(a, GIANT_A))


static func _ladder_ok(a: float, others: Array) -> Array[String]:
	var why: Array[String] = []
	for o in others:
		if absf(angle_difference(a, float(o))) < LADDER_GAP - 0.001:
			why.append("ladders at %.0f and %.0f deg are too close" % [rad_to_deg(a), rad_to_deg(float(o))])
	for i in BOULDERS:
		if absf(angle_difference(a, TAU * (i + 0.5) / BOULDERS)) < BOULDER_CLEAR:
			why.append("a ladder at %.0f deg is on a boulder's spot" % rad_to_deg(a))
	var d := Vector3(cos(a), 0.0, sin(a))
	var r := 12.0
	while r <= W.EDGE - 0.4:
		var q := d * r
		if W.river_dist(q.x, q.z) < W.RIVER_HALF + W.BANK + 0.3:
			why.append("a ladder at %.0f deg is in the river" % rad_to_deg(a))
			break
		r += 0.5
	for big in [false, true]:
		var steps := _steps(d * LAND_R, big)
		if steps <= 0:
			why.append("no %s path from the ladder at %.0f deg to the fire" % ["big" if big else "small", rad_to_deg(a)])
	var w := walk_secs(a, false)
	if w < MIN_WALK:
		why.append("the ladder at %.0f deg is only %.1f s from the fire" % [rad_to_deg(a), w])
	return why


static func _balloon_ok(a: float, r: float) -> Array[String]:
	var why: Array[String] = []
	if r < BALLOON_R.x - 0.001 or r > BALLOON_R.y + 0.001:
		why.append("a balloon lands %.1f from the fire" % r)
	var q := Vector3(cos(a), 0.0, sin(a)) * r
	if W.in_water(q.x, q.z) or W.river_dist(q.x, q.z) < W.RIVER_HALF + W.BANK:
		why.append("a balloon lands in the river")
	if W.push_out(q, 0.35).distance_to(q) > 0.001:
		why.append("a balloon lands on a house or tree at (%.1f, %.1f)" % [q.x, q.z])
	if _steps(q, false) <= 0:
		why.append("a balloon lands where it can't walk to the fire")
	return why


# --- Keepsakes on the rim ------------------------------------------------------------------------

## The gift the k-th saved night (0-based, over all days) brings.
static func gift_for(k: int) -> String:
	return GIFTS[posmod(k, GIFTS.size())]


## Where gift slot i sits: on the far rim, facing the Giant (Vector3.INF past the last slot).
static func gift_slot(i: int) -> Vector3:
	if i < 0 or i >= GIFT_KEEP:
		return Vector3.INF
	var a := 1.5 * PI + (i - (GIFT_KEEP - 1) * 0.5) * GIFT_STEP
	return Vector3(cos(a), 0.0, sin(a)) * (W.R + W.RIM * 0.5)


static func lanterns(days: int) -> int:
	return clampi(days, 0, LANTERNS_MAX)


## Lantern i on its post round the rim (Vector3.INF past the last).
static func lantern_slot(i: int) -> Vector3:
	if i < 0 or i >= LANTERNS_MAX:
		return Vector3.INF
	var a := LANTERN_FIRST + i * LANTERN_STEP
	return Vector3(cos(a), 0.0, sin(a)) * (W.R + W.RIM * 0.55)
