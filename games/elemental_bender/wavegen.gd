extends RefCounted
## ELEMENTAL BENDER wave generator: every wave's SHADOW PORTALS (where the raiders step out on the island), which
## elements come and in what order, who throws from afar and how fast they come, as plain data from a seed, so the
## host and every TV machine see the same portals from [temple seed, wave] and tests/elemental_bender_gen_test.gd
## proves over many seeds that every wave is fair for small kids.
##   var plan := WaveGen.plan(temple_seed, wave, fighters)
##   plan = {n, players, boss, gates: [Vector3...], palette: [element...], boss_order: [element...],
##           spawns: [[element, gate index, ranged, gap seconds before it, jitter x, jitter z], ...] (in order)}
##   WaveGen.gates(temple_seed, wave) = just the portals (the same for every party size: every machine builds them).
## Story: KIKO, the little temple fox, sits in the middle of the temple and tells the story on picture cards.
## Waves teach the elements one at a time: waves 1 and 2 bring ONE element each (a different one; Kiko shows the
## element that beats it), then two, then three, all four from wave 8. Clearing waves grows the SPIRIT TREE beside
## the temple (saved, over days), every Shadow General beaten hangs a glowing fruit on it, a stone LANTERN joins the
## temple ring every play-day, and with CROWN_GENERALS Generals beaten Kiko wears a crown.
## TODAY'S RAIDERS: the first game each day uses the day's seed on every machine.
## check(plan) is the validator: one portal for waves 1-2 (in FRONT of the temple, where everyone faces), two from
## wave 3, two or three from wave 6; portals spread apart on open grass (never on a tree, rock, training platform,
## the temple steps or the beach), far enough out that a raider needs MIN_WALK seconds to reach the temple; the
## elements per wave as above; nobody throws from afar before wave 3; the General only every 5th wave and first;
## the first raider of a normal wave comes from the front portal; and a slow small-kid team (KID_DPS each, one raider
## at a time) never faces more than kid_cap() raiders at once (kid_sim), with the spawning done inside MAX_SPAWN_SECS.

const Seeded := preload("res://core/seeded.gd")
const World := preload("res://games/elemental_bender/world.gd")

const GAME_ID := "elemental_bender"
const FRONT := 1.5 * PI  # (cos a, 0, sin a) = -z: where the temple faces (the practice dummy, the VR master's view)
const FRONT_SIDE := deg_to_rad(35.0)
const GATE_R := Vector2(22.0, 31.0)
const GATE_CLEAR := 2.6  # metres of open grass round a portal (raiders step out up to JITTER from it)
const GATE_GAP := deg_to_rad(60.0)
const JITTER := 1.2
const MIN_WALK := 4.0  # seconds a raider needs from its portal to the temple in waves 1-2 (MIN_WALK_LATER after)
const MIN_WALK_LATER := 3.0
const TEMPLE_R := 3.0  # where the benders stand (World.temple_spot)
const KID_DPS := 9.0  # a small kid's damage per second in wave 1 (misses, the wrong element now and then) ...
const KID_DPS_GROWTH := 1.2  # ... getting better by this much every wave (a kid who got to wave 10 can bend)
const KID_REACH := 1.0  # seconds before a kid starts on a raider that just came out
const MAX_ALIVE := 14  # == main.gd
const MAX_SPAWN_SECS := 120.0
const MAX_WAVE := 15  # the validator's reach
const MAX_PLAYERS := 7
const STRETCH := 1.08
const STRETCH_TRIES := 50
const BOSS_EVERY := 5

## Keepsakes: the Spirit Tree's stages (waves cleared over all days) and its glowing fruit (one per General).
const TREE_STAGES: Array[int] = [0, 2, 5, 10, 18, 30]
const FRUIT_MAX := 12
const LANTERNS_MAX := 12
const LANTERN_R := 9.6
const CROWN_GENERALS := 5
const TREE_AT := Vector3(-12.5, 0.0, -5.0)  # beside the temple, in front-left (seen from the temple and the TV cameras)
const TREE_CLEAR := 1.8


## The day's temple seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


static func wave_seed(temple_seed: int, n: int) -> int:
	return Seeded.derive(temple_seed, "wave%d" % n)


static func is_boss(n: int) -> bool:
	return n > 0 and n % BOSS_EVERY == 0


static func gate_count(n: int, rng: RandomNumberGenerator = null) -> int:
	if n <= 2:
		return 1
	if n <= 5:
		return 2
	return 3 if rng != null and rng.randf() < 0.5 else 2


## How many different elements wave n brings.
static func palette_size(n: int) -> int:
	if n <= 2:
		return 1
	if n <= 5:
		return 2
	if n <= 7:
		return 3
	return 4


## Raider numbers, the same as main.gd uses (party of `players` fighters).
static func raider_hp(n: int, players: int, boss: bool) -> float:
	var s := 1.0 + 0.15 * (maxi(1, players) - 1)
	return ((300.0 + n * 50.0) if boss else (22.0 + n * 5.0)) * s


static func raider_speed(n: int, boss: bool) -> float:
	return 2.6 if boss else 3.2 + minf(n * 0.15, 2.0)


static func raider_count(n: int, players: int) -> int:
	players = maxi(1, players)
	if is_boss(n):
		return n + players - 1  # (+ the General)
	return 3 + n * 2 + (players - 1) * 2


## The most raiders a slow small-kid team should ever face at once.
static func kid_cap(n: int, players: int) -> int:
	var base := 2 if n <= 2 else (3 if n <= 5 else 4)
	return mini(MAX_ALIVE, base + (maxi(1, players) - 1) * 2 + int(n / 5))


## The portals of wave n (the first one in front for waves 1-2). Every machine builds these.
static func gates(temple_seed: int, n: int) -> Array:
	n = maxi(1, n)
	var rng := Seeded.rng(wave_seed(temple_seed, n), "gates")
	var want := gate_count(n, rng)
	var out: Array = []
	var tries := 0
	while out.size() < want and tries < 400:
		tries += 1
		var a: float
		if out.is_empty() and n <= 2:
			a = FRONT + rng.randf_range(-FRONT_SIDE, FRONT_SIDE) * 0.95
		else:
			a = rng.randf() * TAU
		var r := rng.randf_range(GATE_R.x, GATE_R.y)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		p = Vector3(snappedf(p.x, 0.01), 0.0, snappedf(p.z, 0.01))
		if _gate_ok(p, out).is_empty():
			out.append(p)
	return out


## The whole wave plan for a party of `players` fighters. `fast`: the short test waves (EB_FAST).
static func plan(temple_seed: int, n: int, players: int = 1, fast: bool = false) -> Dictionary:
	n = maxi(1, n)
	players = clampi(players, 1, MAX_PLAYERS)
	var boss := is_boss(n)
	var p := {"n": n, "players": players, "boss": boss, "gates": gates(temple_seed, n)}
	var rng := Seeded.rng(wave_seed(temple_seed, n), "raiders%d" % players)
	# The elements: a fixed teaching order per temple (the first two waves bring two different ones).
	var order := Seeded.shuffled(Seeded.rng(temple_seed, "elements"), [0, 1, 2, 3])
	var palette: Array = []
	if n <= 2:
		palette = [order[n - 1]]
	else:
		palette = Seeded.shuffled(rng, [0, 1, 2, 3]).slice(0, palette_size(n))
		palette.sort()
	p.palette = palette
	var bo: Array = [Seeded.pick(rng, [0, 1, 2, 3])]
	for i in 11:
		var e: int = (int(bo[-1]) + 1 + rng.randi() % 3) % 4
		bo.append(e)
	p.boss_order = bo if boss else []
	var count := raider_count(n, players)
	if fast:
		count = ((2 if boss else 2 + int(n / 2.0)) + players - 1)
	var ranged_p := 0.0 if n <= 2 else minf(0.25 + n * 0.04, 0.6)
	var gl: Array = p.gates
	var base := maxf(0.6, 1.6 - n * 0.06)
	var spawns: Array = []
	for i in count:
		var e: int = palette[rng.randi() % palette.size()]
		var gi := 0 if i == 0 else rng.randi() % gl.size()
		var ranged := rng.randf() < ranged_p
		var gap := 0.4 if i == 0 else snappedf(base * rng.randf_range(0.8, 1.25), 0.01)
		if i == 0 and boss:
			gap = 2.5  # (the General's own entrance comes first)
		var j := Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER)).limit_length(JITTER)
		spawns.append([e, gi, ranged, gap, snappedf(j.x, 0.01), snappedf(j.y, 0.01)])
	p.spawns = spawns
	if fast:
		for s in spawns:
			s[3] = minf(float(s[3]), 0.5)
		return p
	# Too quick for small kids? Spread them out until it isn't.
	for _t in STRETCH_TRIES:
		if _kid_fails(p).is_empty():
			break
		for i in range(1, spawns.size()):
			spawns[i][3] = snappedf(float(spawns[i][3]) * STRETCH, 0.01)
	return p


## Problems with one wave plan (empty = fair).
static func check(p: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var n := int(p.n)
	var gl: Array = p.gates
	var want_min := 1 if n <= 2 else 2
	var want_max := 1 if n <= 2 else (2 if n <= 5 else 3)
	if gl.size() < want_min or gl.size() > want_max:
		why.append("wave %d has %d portals (wants %d-%d)" % [n, gl.size(), want_min, want_max])
	for i in gl.size():
		var g: Vector3 = gl[i]
		for w in _gate_ok(g, gl.slice(0, i)):
			why.append("wave %d: %s" % [n, w])
		if i == 0 and n <= 2 and absf(angle_difference(atan2(g.z, g.x), FRONT)) > FRONT_SIDE + 0.001:
			why.append("wave %d: the portal at (%.0f, %.0f) is not in front of the temple" % [n, g.x, g.z])
		var walk := (Vector2(g.x, g.z).length() - JITTER - TEMPLE_R) / raider_speed(n, false)
		if walk < (MIN_WALK if n <= 2 else MIN_WALK_LATER):
			why.append("wave %d: a portal only %.1f s from the temple" % [n, walk])
	var pal: Array = p.palette
	if pal.size() != palette_size(n):
		why.append("wave %d brings %d elements (wants %d)" % [n, pal.size(), palette_size(n)])
	var spawns: Array = p.spawns
	if spawns.is_empty():
		why.append("wave %d has no raiders" % n)
		return why
	var total := 0.0
	var seen := {}
	for i in spawns.size():
		var s: Array = spawns[i]
		var e := int(s[0])
		seen[e] = true
		total += float(s[3])
		if not pal.has(e):
			why.append("wave %d: raider %d is %d, not one of the wave's elements %s" % [n, i, e, str(pal)])
		if int(s[1]) < 0 or int(s[1]) >= gl.size():
			why.append("wave %d: raider %d comes from no portal" % [n, i])
		if bool(s[2]) and n <= 2:
			why.append("wave %d: a raider throws from afar before wave 3" % n)
		if Vector2(float(s[4]), float(s[5])).length() > JITTER + 0.02:
			why.append("wave %d: raider %d steps out too far from its portal" % [n, i])
		if i > 0 and float(s[3]) < 0.3:
			why.append("wave %d: raider %d comes only %.2f s after the last" % [n, i, s[3]])
	if int(spawns[0][1]) != 0:
		why.append("wave %d: the first raider isn't from the front portal" % n)
	if n <= 2 and seen.size() != 1:
		why.append("wave %d mixes elements" % n)
	if bool(p.boss) != is_boss(n):
		why.append("wave %d: the General comes at the wrong time" % n)
	if bool(p.boss):
		var bo: Array = p.boss_order
		if bo.size() < 2:
			why.append("wave %d: the General has no element order" % n)
		for i in range(1, bo.size()):
			if int(bo[i]) == int(bo[i - 1]):
				why.append("wave %d: the General 'swaps' to the same element" % n)
	if total > MAX_SPAWN_SECS:
		why.append("wave %d takes %.0f s to send its raiders (too slow to be fun)" % [n, total])
	why.append_array(_kid_fails(p))
	return why


## The slow-kid model: each fighter takes on one raider at a time (KID_REACH to get going, then hp / KID_DPS), the
## raiders in the order they came out. Returns {most: the most raiders out at once, end: when the last one fell}.
static func kid_sim(p: Dictionary) -> Dictionary:
	var n := int(p.n)
	var players := int(p.players)
	var free: Array = []
	free.resize(players)
	free.fill(0.0)
	var t := 0.0
	var ends: Array = []  # when each raider falls
	var outs: Array = []  # when each came out
	for i in (p.spawns as Array).size():
		var s: Array = p.spawns[i]
		t += float(s[3])
		var boss := bool(p.boss) and i == 0
		var hp := raider_hp(n, players, boss)
		var best := 0
		for h in players:
			if float(free[h]) < float(free[best]):
				best = h
		var dps := kid_dps(n)
		var fin := maxf(float(free[best]), t + KID_REACH) + hp / dps
		if boss:  # the whole team on the General (he doesn't count against the crowd)
			fin = t + KID_REACH + hp / (dps * players)
			for h in players:
				free[h] = maxf(float(free[h]), t)  # (the others still deal with the crowd)
		else:
			free[best] = fin
		outs.append(t)
		ends.append(fin)
	var most := 0
	for i in outs.size():
		var at: float = outs[i]
		var alive := 0
		for j in outs.size():
			if bool(p.boss) and j == 0:
				continue
			if float(outs[j]) <= at + 0.001 and float(ends[j]) > at + 0.001:
				alive += 1
		most = maxi(most, alive)
	var end := 0.0
	for e in ends:
		end = maxf(end, float(e))
	return {"most": most, "end": end}


static func kid_dps(n: int) -> float:
	return KID_DPS + KID_DPS_GROWTH * (maxi(1, n) - 1)


static func _kid_fails(p: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var n := int(p.n)
	var most := int(kid_sim(p).most)
	var cap := kid_cap(n, int(p.players))
	if most > cap:
		why.append("wave %d is too busy for small kids (%d raiders at once, %d players; wants <= %d)" % [n, most, int(p.players), cap])
	return why


static func _gate_ok(g: Vector3, others: Array) -> Array[String]:
	var why: Array[String] = []
	var r := Vector2(g.x, g.z).length()
	if r < GATE_R.x - 0.02 or r > GATE_R.y + 0.02:
		why.append("a portal %.1f m from the temple" % r)
	var b := World.blocked(g, GATE_CLEAR)
	if b != "":
		why.append("a portal at (%.0f, %.0f) is %s" % [g.x, g.z, b])
	var a := atan2(g.z, g.x)
	for o in others:
		var q: Vector3 = o
		if absf(angle_difference(a, atan2(q.z, q.x))) < GATE_GAP - 0.001:
			why.append("portals at (%.0f, %.0f) and (%.0f, %.0f) are too close" % [g.x, g.z, q.x, q.z])
	return why


# --- Keepsakes ----------------------------------------------------------------------------------

## The Spirit Tree's stage (0 = a seed in the ground .. TREE_STAGES.size() - 1 = the great tree).
static func tree_stage(waves_cleared: int) -> int:
	var s := 0
	for i in TREE_STAGES.size():
		if waves_cleared >= TREE_STAGES[i]:
			s = i
	return s


static func lanterns(days: int) -> int:
	return clampi(days, 0, LANTERNS_MAX)


## Lantern i in the ring round the temple steps (Vector3.INF past the last).
static func lantern_slot(i: int) -> Vector3:
	if i < 0 or i >= LANTERNS_MAX:
		return Vector3.INF
	var a := FRONT + PI / LANTERNS_MAX + i * TAU / LANTERNS_MAX
	return Vector3(cos(a), 0.0, sin(a)) * LANTERN_R


## Where fruit i hangs on the tree (relative to TREE_AT): on the outside of the crown at stage `stage`.
static func fruit_slot(i: int, stage: int) -> Vector3:
	var a := i * 2.399  # (the golden angle: fruit spread round the crown)
	var el := -0.35 + 0.8 * float((i * 5) % 7) / 6.0
	var d := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
	return Vector3(0.0, tree_height(stage), 0.0) + d * crown_r(stage) * 1.03


## How many fruit fit on the tree at `stage` (the newest ones show).
static func fruit_cap(stage: int) -> int:
	return [0, 3, 6, 9, 12, 12][clampi(stage, 0, 5)]


static func tree_height(stage: int) -> float:
	return [0.35, 1.2, 2.2, 3.3, 4.3, 5.4][clampi(stage, 0, 5)]


static func crown_r(stage: int) -> float:
	return [0.15, 0.45, 0.9, 1.35, 1.75, 2.2][clampi(stage, 0, 5)]
