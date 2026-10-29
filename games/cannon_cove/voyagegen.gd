extends RefCounted
## CANNON COVE generator: every wave's plan (which ships, tentacles and the Kraken come, in what order, from which
## side and angle, how far out they circle) as plain data from a seed, so the host builds the same voyage for the
## same seed, and tests/cannon_cove_gen_test.gd proves over many seeds that every wave is fair and reachable.
##   var plan := VoyageGen.wave_plan(voyage_seed, wave, simple, crew_extra)
##   plan = [{k: "raider"|"galleon"|"fireship"|"treasure"|"tentacle"|"kraken"|"wait", side: -1/0/1 (0 = the side the
##            gunner's cannon faces), a: approach angle, orbit: extra orbit metres, dir: +-1 (orbit direction),
##            fire: first shot after s, z: tentacle spot along the hull}, ...]
## Story: POLLY the parrot sails with the crew. Every wave cleared puts a TREASURE on the stern castle's shelf (a gold
## coin for ship waves, a pearl for the leak wave, an anchor for the boarders, a starfish for the sea monster, the
## Kraken's crown: saved), and a string of flags in the rigging grows a flag each play-day. Once the crew has beaten
## the Kraken, Polly wears a little gold crown. TODAY'S VOYAGE: the first voyage each day uses the day's seed on
## every machine, and its treasures are golden.
## check(plan, wave, simple) is the validator: simple mode brings one new thing per wave (1-3 raiders only, 4 adds a
## galleon, 5 the tentacles, 6 the Kraken first, fire ships only from the second bonus sea), wave sizes stay in their
## bands, every wave opens with a ship to shoot, wave 1 comes on the gunner's side, no side gets more than two ships
## in a row early on, every ship approaches inside the cannons' swing and circles inside their range (and outside our
## hull), ships on the same side never come in on top of each other, and tentacles grab the hull where the deck is.
## threat() sums a plan; waves 1-5 must not get easier, and bonus seas are at least as busy as wave 5.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "cannon_cove"
const BOSS_WAVE := 6  # == main.gd
const MAX_WAVE := 16  # the validator's reach (bonus seas go on; plans past this repeat the same rules)
const APPROACH := 0.9  # == main.gd: ships come in at angles inside +-this (cannon YAW_LIMIT is 1.2)
const YAW_LIMIT := 1.2  # == cannon.gd
const MUZZLE_SPEED := 30.0  # == cannon.gd
const PITCH_MAX := 0.7  # == cannon.gd
const GRAVITY := 9.8  # == main.gd
const ORBIT := {"raider": 17.0, "galleon": 42.0, "fireship": 0.0, "treasure": 28.0}  # == enemy_ship.gd KINDS
const ORBIT_JITTER := Vector2(-2.0, 6.0)  # == enemy_ship.gd setup()
const HULL_CLEAR := 12.0  # ships circle at least this far out
const SAME_SIDE_GAP := 0.35  # radians between two ships in a row on the same side
const TENTACLE_Z := Vector2(-7.0, 7.0)  # along the hull (the deck runs -11..9.4)
const THREAT := {"raider": 1.0, "galleon": 2.0, "fireship": 1.5, "treasure": 0.5, "tentacle": 2.0, "kraken": 10.0, "wait": 0.0}
const SHIPS := ["raider", "galleon", "fireship", "treasure"]

## Treasures (one per wave cleared) and where they sit: a shelf on top of the stern castle wall.
const TREASURE_SLOTS := 13
const TREASURE_KEEP := 13
const FLAGS_MAX := 20  # flags in the rigging (one per play-day)
const BONUS_TREASURES := ["doubloon", "pearl", "starfish", "anchor"]


## The day's voyage seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## Wave n's seed in a voyage.
static func wave_seed(voyage_seed: int, n: int) -> int:
	return Seeded.derive(voyage_seed, "wave%d" % n)


## The treasure a cleared wave puts on the shelf.
static func treasure_for(w: int) -> String:
	if w <= 2:
		return "doubloon"
	match w:
		3:
			return "pearl"
		4:
			return "anchor"
		5:
			return "starfish"
		BOSS_WAVE:
			return "crown"
	return BONUS_TREASURES[(w - BOSS_WAVE - 1) % BONUS_TREASURES.size()]


## How far a cannonball flies on flat water (the cannons' reach).
static func cannon_range() -> float:
	return MUZZLE_SPEED * MUZZLE_SPEED * sin(2.0 * PITCH_MAX) / GRAVITY


## Wave w's plan. crew_extra (deckhands beyond two) adds raiders, like before.
static func wave_plan(voyage_seed: int, w: int, simple: bool = true, crew_extra: int = 0) -> Array:
	var rng := Seeded.rng(wave_seed(voyage_seed, w), "plan")
	var kinds: Array = _kinds(rng, w, simple)
	# Raiders sometimes come as a galleon from wave 4 - never the opening ship.
	var upgrade_from := 4
	for i in range(1, kinds.size()):
		if kinds[i] == "raider" and w >= upgrade_from and w != BOSS_WAVE and rng.randf() < 0.15 + w * 0.03:
			kinds[i] = "galleon"
	# A bigger crew (more than two deckhands) faces a few more raiders (plain ones) and, in the classic game, a tentacle.
	for i in crew_extra / 2:
		kinds.append("raider")
	if not simple and crew_extra >= 3 and w >= 3:
		kinds.append("tentacle")
	var out: Array = []
	var last_side := 0.0
	var streak := 0
	var last_a := {-1.0: INF, 1.0: INF}
	var last_ship_side := 0.0
	for k in kinds:
		var e := {"k": k}
		match k:
			"wait":
				pass
			"kraken":
				e.side = -1.0 if rng.randf() < 0.5 else 1.0
				e.z = snappedf(rng.randf_range(-3.0, 4.0), 0.01)
			"tentacle":
				e.side = -1.0 if rng.randf() < 0.5 else 1.0
				e.z = snappedf(rng.randf_range(TENTACLE_Z.x, TENTACLE_Z.y), 0.01)
			_:
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				if simple and w == 1:
					side = 0.0  # wave 1: on the gunner's side, so there's no hopping yet
				elif streak >= 2 and side == last_side and w <= BOSS_WAVE:
					side = -side  # no more than two in a row on one side early on
				streak = streak + 1 if side == last_side else 1
				last_side = side
				var key := side if side != 0.0 else -1.0
				var a := rng.randf_range(-APPROACH, APPROACH)
				var prev: float = last_a[key]
				if prev != INF and last_ship_side == side and absf(a - prev) < SAME_SIDE_GAP:
					a = prev + SAME_SIDE_GAP * (1.0 if prev < 0.0 else -1.0) * 1.2  # move it along the horizon
				last_a[key] = a
				last_ship_side = side
				e.side = side
				e.a = snappedf(a, 0.001)
				e.orbit = snappedf(rng.randf_range(ORBIT_JITTER.x, ORBIT_JITTER.y), 0.01)
				e.dir = -1.0 if rng.randf() < 0.5 else 1.0
				e.fire = snappedf(rng.randf_range(2.0, 4.0), 0.01)
		out.append(e)
	return out


## The kinds in a wave, before the crew's extras.
static func _kinds(rng: RandomNumberGenerator, w: int, simple: bool) -> Array:
	var q: Array = []
	if simple:
		match w:
			1:
				q = ["raider", "raider"]
			2:
				q = ["raider", "raider", "raider"]
			3:
				q = ["raider", "raider", "raider"]
				if rng.randf() < 0.5:
					q.append("raider")
			4:
				q = ["raider", "raider", "raider"]
				q.insert(2 + rng.randi() % 2, "galleon")  # never first
			5:
				# A raider first, then two tentacles (never side by side) and a galleon among more raiders.
				var rest: Array = ["raider", "galleon"]
				if rng.randf() < 0.5:
					rest.append("raider")
				rest = Seeded.shuffled(rng, rest)
				q = ["raider"]
				q.append("tentacle")
				q.append(rest[0])
				q.append("tentacle")
				q.append_array(rest.slice(1))
			BOSS_WAVE:
				q = ["kraken", "wait", "raider"]
			_:
				var n := mini(3 + (w - BOSS_WAVE), 8)
				var mix: Array = ["raider", "galleon", "raider", "fireship"] if w > BOSS_WAVE + 1 else ["raider"]
				q.append("raider")  # open with something to shoot
				for i in n - 1:
					q.append(Seeded.pick(rng, mix))
				for i in 1 + (w - BOSS_WAVE) / 3:
					q.insert(mini(q.size(), 2 + i * 3 + rng.randi() % 2), "tentacle")
		return q
	match w:
		1:
			q = ["raider", "raider"]
		2:
			q = ["raider", "raider", "raider"]
		3:
			q = ["raider"] + Seeded.shuffled(rng, ["fireship", "galleon", "fireship", "raider"])
		4:
			q = ["raider"] + Seeded.shuffled(rng, ["tentacle", "treasure", "galleon", "raider", "tentacle"])
		5:
			q = ["raider"] + Seeded.shuffled(rng, ["fireship", "galleon", "tentacle", "raider", "fireship", "galleon"])
		BOSS_WAVE:
			q = ["kraken", "wait", "raider"]
		_:
			var n := mini(3 + (w - BOSS_WAVE), 9)
			q.append("raider")
			for i in n - 1:
				q.append(Seeded.pick(rng, ["raider", "galleon", "raider", "fireship"]))
			for i in 1 + (w - BOSS_WAVE) / 2:
				q.insert(mini(q.size(), 2 + i * 2), "tentacle")
			if w % 2 == 0:
				q.insert(2, "treasure")
	return q


## How busy a plan is (bigger = harder).
static func threat(plan: Array) -> float:
	var s := 0.0
	for e in plan:
		s += float(THREAT.get(e.k, 1.0))
	return s


## The kinds simple mode allows in a wave (one new thing per wave).
static func allowed(w: int, simple: bool) -> Array:
	if not simple:
		return ["raider", "galleon", "fireship", "treasure", "tentacle", "kraken", "wait"] if w >= 3 else ["raider", "galleon"]
	if w <= 3:
		return ["raider"]
	if w == 4:
		return ["raider", "galleon"]
	if w == 5:
		return ["raider", "galleon", "tentacle"]
	if w == BOSS_WAVE:
		return ["kraken", "wait", "raider"]
	if w == BOSS_WAVE + 1:
		return ["raider", "galleon", "tentacle"]
	return ["raider", "galleon", "fireship", "tentacle"]


## The size band [min, max] of a simple wave before the crew's extras.
static func size_band(w: int) -> Vector2i:
	match w:
		1:
			return Vector2i(2, 2)
		2:
			return Vector2i(3, 3)
		3:
			return Vector2i(3, 4)
		4:
			return Vector2i(4, 4)
		5:
			return Vector2i(5, 6)
		BOSS_WAVE:
			return Vector2i(3, 3)
	return Vector2i(3, 14)


## Problems with one wave's plan (empty = fair).
static func check(plan: Array, w: int, simple: bool = true, crew_extra: int = 0) -> Array[String]:
	var why: Array[String] = []
	if plan.is_empty():
		return ["wave %d is empty" % w]
	var ok_kinds := allowed(w, simple)
	var ships := 0
	for e in plan:
		if not ok_kinds.has(e.k):
			why.append("wave %d brings a %s too early" % [w, e.k])
		if SHIPS.has(e.k):
			ships += 1
	if ships == 0:
		why.append("wave %d has no ships to shoot" % w)
	var first: String = plan[0].k
	if w == BOSS_WAVE:
		if first != "kraken":
			why.append("the Kraken's wave must open with the Kraken")
	elif first != "raider":
		why.append("wave %d opens with a %s, not a ship to shoot" % [w, first])
	if simple:
		var band := size_band(w)
		var n := plan.size() - crew_extra / 2
		if n < band.x or n > band.y:
			why.append("wave %d has %d things (wants %d-%d)" % [w, n, band.x, band.y])
	var last_side := 0.0
	var streak := 0
	var last_a := {}
	var prev_kind := ""
	var reach := cannon_range()
	for e in plan:
		var k: String = e.k
		if k == "tentacle" or k == "kraken":
			if absf(float(e.side)) != 1.0:
				why.append("a %s on no side" % k)
			if float(e.z) < TENTACLE_Z.x - 0.01 or float(e.z) > TENTACLE_Z.y + 0.01:
				why.append("a %s grabs the hull off the deck (z %.1f)" % [k, float(e.z)])
			if simple and k == "tentacle" and prev_kind == "tentacle":
				why.append("two tentacles side by side in wave %d" % w)
		elif SHIPS.has(k):
			var side: float = e.side
			if side == 0.0 and not (simple and w == 1):
				why.append("a ship without a side in wave %d" % w)
			if simple and w == 1 and side != 0.0:
				why.append("wave 1 must come on the gunner's side")
			if side != 0.0 and absf(side) != 1.0:
				why.append("a ship on side %.2f" % side)
			var a: float = e.a
			if absf(a) > APPROACH + 0.001 or absf(a) > YAW_LIMIT - 0.2:
				why.append("a ship comes in at %.2f rad, outside the cannons' swing" % a)
			var r: float = ORBIT[k] + float(e.orbit)
			if k != "fireship":
				if r > reach - 10.0:
					why.append("a %s circles at %.0f m (the cannons reach %.0f m)" % [k, r, reach])
				if r < HULL_CLEAR:
					why.append("a %s circles inside our hull (%.0f m)" % [k, r])
			if absf(float(e.dir)) != 1.0:
				why.append("a ship with no orbit direction")
			if float(e.fire) < 1.5:
				why.append("a ship shoots the moment it arrives")
			streak = streak + 1 if side == last_side else 1
			last_side = side
			if simple and w <= 5 and streak > 2 and side != 0.0:
				why.append("three ships in a row on one side in wave %d" % w)
			if last_a.has(side) and absf(a - float(last_a[side])) < SAME_SIDE_GAP - 0.001:
				why.append("two ships in a row come in on top of each other (%.2f, %.2f)" % [a, float(last_a[side])])
			last_a = {side: a}
		prev_kind = k
	return why


## Problems with a whole voyage (waves 1..last): every wave fair, and the challenge rises readably: waves 1-5 never
## get calmer or smaller, and each bonus sea is at least as big as the one before.
static func check_voyage(voyage_seed: int, simple: bool = true, crew_extra: int = 0, last: int = MAX_WAVE) -> Array[String]:
	var why: Array[String] = []
	var prev_th := 0.0
	var prev_n := 0
	for w in range(1, last + 1):
		var plan := wave_plan(voyage_seed, w, simple, crew_extra)
		for r in check(plan, w, simple, crew_extra):
			why.append(r)
		var th := threat(plan)
		var n := plan.filter(func(e: Dictionary) -> bool: return e.k != "treasure" and e.k != "wait").size()  # (the treasure ship is a gift)
		if w <= 5 and w > 1:
			if th + 0.001 < prev_th:
				why.append("wave %d (threat %.1f) is calmer than wave %d (%.1f)" % [w, th, w - 1, prev_th])
			if n < prev_n:
				why.append("wave %d (%d) is smaller than wave %d (%d)" % [w, n, w - 1, prev_n])
		if w > BOSS_WAVE + 1 and n < prev_n:
			why.append("bonus wave %d (%d) is smaller than the one before (%d)" % [w, n, prev_n])
		prev_th = th
		prev_n = n
	return why


## Where treasure i sits on the stern castle shelf (ship-local), Vector3.INF past the end.
static func treasure_slot(i: int) -> Vector3:
	if i < 0 or i >= TREASURE_SLOTS:
		return Vector3.INF
	# Centre out: 0 in the middle, then alternate left and right.
	var k := (i + 1) / 2
	var s := 0.0 if i == 0 else (-1.0 if i % 2 == 1 else 1.0)
	return Vector3(s * k * 0.58, 2.29, 10.0)


## Flags in the rigging: one per play-day.
static func flags(days: int) -> int:
	return clampi(days, 0, FLAGS_MAX)


## Where flag i hangs on the stay from the main mast top down to the stern castle (ship-local).
static func flag_slot(i: int) -> Vector3:
	var a := Vector3(0, 12.0, -1.0)
	var b := Vector3(0, 2.25, 9.9)
	var f := 0.2 + 0.72 * float(i) / float(FLAGS_MAX - 1)
	return a.lerp(b, f)
