extends RefCounted
## SNOWBALL BLITZ generator: every game is a SIEGE made from a seed, so the same seed gives the same
## waves (the host spawns them; TV machines only need the story), and tests/snowball_blitz_gen_test.gd
## proves over many seeds that every siege is fair for small kids and rises gently.
##   var s := SiegeGen.siege(seed, level, daily)
##   s = {seed, level, daily, want, new: {wave: kind}, waves: [wave plan, ...]}   (waves 1..FINALE)
##   var w := SiegeGen.wave_plan(s, n)     # any wave, endless ones too (made from the seed on demand)
##   w = {n, gates: [angle, ...], boss: "" | "king" | "yeti", spawns: [[delay, kind, gate, jitter], ...]}
## Story: BOBO the polar bear cub lives in the snowy village. The mischievous snowmen want to pinch
## something of Bobo's (the siege's WANT: cocoa, scarf, mittens or fish). Defend the fort and every game
## builds a new IGLOO in Bobo's village round the square (saved; igloos grow a stage each play-day).
## TODAY'S BLIZZARD: the first game each day is the same siege on every machine, and its igloo is golden.
## Waves: the snowmen march in from a few GATES (directions round the square: one in front to start,
## more later), one new kind per wave (waves 3, 4 and 6 bring sleds / bunnies / balloons in a seeded
## order, wave 5 the giants), the SNOW KING at KING_WAVE and the YETI at FINALE, then endless.
## spawns: in order; `delay` seconds after the one before, a `kind` walks in at gate angle + `jitter`.
## MODES (picked on the pick orbs after the practice, core/pick_orbs.gd): GENTLE (fewer, slower snowmen, softer hits,
## longer gaps: for little ones), BRAVE (as before), HARD (more and quicker). Every spawn draws from its own seeded
## stream, so a gentle wave is the brave one with fewer snowmen and a hard one adds a few: check_modes() proves gentle
## <= brave <= hard wave by wave and that no wave is a cliff after the one before (threat()).
## check(s) is the validator: gates are spread out (and in front at first), every wave brings its new
## kind (and nothing not yet met), the gaps are never too short, no wall gets swamped by snowmen from one
## gate at once, and a small child alone keeps the fort standing through the first waves (a simulation).

const Seeded := preload("res://core/seeded.gd")
const KINDS: Dictionary = preload("res://games/snowball_blitz/snowman.gd").KINDS

const GAME_ID := "snowball_blitz"
const ARENA_RADIUS := 20.0  # == main.gd (the test checks)
const FORT_RADIUS := 6.0  # == main.gd
const SEGMENTS := 8  # == main.gd
const SEG_MAX := 100.0  # == main.gd
const SPAWN_R := ARENA_RADIUS - 1.0  # where snowmen walk in (main.gd)
const FINALE := 10  # == main.SIMPLE_FINALE (the YETI)
const KING_WAVE := 7  # == main.SIMPLE_KING
const MAX_LEVEL := 4
const DAILY_LEVEL := 2
const TRIES := 6
const FRONT := -PI / 2.0  # the players face -Z (the big tree): gate angle for "straight ahead"
const FRONT_ARC := 0.6  # waves 1-2 come from within this of straight ahead (radians)
const MIN_GATE_SEP := 0.9  # gates at least this far apart (radians), so each is its own direction
const MAX_JITTER := 0.38
const MIN_GAP := 0.45  # == main.gd's shortest spawn gap
const GIANT_WAVE := 5
const NEW_WAVES: Array[int] = [3, 4, 6]  # the other new kinds arrive in these waves (seeded order)
const NEW_KINDS: Array[String] = ["sled", "bunny", "balloon"]
const WANTS: Array[String] = ["cocoamug", "scarf", "mittens", "fish"]  # what the snowmen try to pinch (pictures)
const WANT_NAMES: Array[String] = ["COCOA", "SCARF", "MITTENS", "FISH"]
const WANT_COLORS: Array[Color] = [Color(0.6, 0.35, 0.2), Color(0.9, 0.2, 0.25), Color(0.3, 0.6, 1.0), Color(1.0, 0.6, 0.2)]
## A small child alone: about this many snowball hits per second once a snowman is in sight, and a
## couple of seconds to spot each one. (A VR player or a grown-up is far quicker; the real game is
## kinder still: walls regrow, the VR player helps. Calibrated so ~95% of first tries pass: the
## validator throws away the unlucky few, it doesn't reshape the game.)
const KID_RATE := 0.75
const KID_SPOT := 1.5
const KID_WAVES := 2  # waves a lone small child must hold (the fort ends above KID_KEEP everywhere)
const KID_KEEP := 0.1
const TEAM_RATE := 2.4  # a VR player + a TV kid together hold the fort through these waves
const TEAM_WAVES := 4
const SWAMP_WINDOW := 6.0  # seconds: snowmen reaching one wall within this of each other count together
const SWAMP_MAX: Array[int] = [3, 3, 4, 4, 4, 4, 4, 5, 5, 5]  # most at one wall at once, by wave (then the last)
## Mode numbers: count (snowmen per wave), gap (time between them; wave 1 is never quicker than brave), speed (walking),
## hit (their snowballs and bashing on the walls). brave is the game as it was.
## Who the validator promises each mode to: kid (a lone thrower's hits per second who holds the first kid_waves),
## team (a VR player + a TV kid hold waves up to TEAM_WAVES), swamp (SWAMP_MAX scaled). Gentle promises more (a slower
## little one holds three waves), hard is for big kids and grown-ups.
const MODE_NUM := {
	"gentle": {"count": 0.7, "gap": 1.3, "speed": 0.85, "hit": 0.6, "kid": 0.75, "kid_waves": 3, "team": 2.0, "swamp": 1.0},
	"brave": {"count": 1.0, "gap": 1.0, "speed": 1.0, "hit": 1.0, "kid": KID_RATE, "kid_waves": KID_WAVES, "team": TEAM_RATE, "swamp": 1.0},
	"hard": {"count": 1.25, "gap": 0.85, "speed": 1.12, "hit": 1.25, "kid": 1.2, "kid_waves": KID_WAVES, "team": 3.2, "swamp": 1.25},
}
const MODES: Array[String] = ["gentle", "brave", "hard"]
const CLIFF := 1.6  # a wave's threat is at most this times the last plain wave's (bosses: their own fight)
const ORDER_SLACK := 1.05  # gentle <= brave <= hard wave by wave (a seeded mix can differ a little)
const CALM := 0.8  # a wave under this threat (snowballs needed per second) is calm whatever came before
const JUMP := 2.0  # one siege's wave (from 3 on) is at most this times the last plain wave's threat (else rerolled)
const TV_HIT := 1.6  # == player.gd's simple throw damage
const CLIFF_START := 2.5  # wave 2 after wave 1 (wave 1 is a slow practice trickle by design)

## Village: igloos round the square in front of the fort (two staggered rows, either side of the big tree).
const VILLAGE_SLOTS := 24
const VILLAGE_R: Array[float] = [25.0, 27.0]
const VILLAGE_ARC := 1.2  # radians either side of straight ahead
const TREE_GAP := 0.3  # radians kept clear round the big tree straight ahead
const VILLAGE_KEEP := 24


## The day's siege seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## How hard a new game is, given the village (more igloos, a bit more snowmen) — never above MAX_LEVEL.
static func level(igloos: int) -> int:
	return clampi(1 + igloos / 5, 1, MAX_LEVEL)


static func mode_num(mode: String) -> Dictionary:
	return MODE_NUM.get(mode, MODE_NUM["brave"])


## The siege for a seed. A try that check() finds unfair is thrown away and the next try (a sub-seed) is
## used, so every machine still gets the same siege; the gentlest try is the last resort.
static func siege(seed_value: int, lv: int, daily: bool = false, mode: String = "brave") -> Dictionary:
	var s := {}
	if not MODE_NUM.has(mode):
		mode = "brave"
	for attempt in TRIES:
		s = _make(seed_value if attempt == 0 else Seeded.derive(seed_value, "try%d" % attempt), lv, daily, attempt, mode)
		if check(s).is_empty():
			break
	s.seed = seed_value
	return s


static func _make(seed_value: int, lv: int, daily: bool, attempt: int, mode: String) -> Dictionary:
	lv = clampi(lv, 1, MAX_LEVEL)
	var r := Seeded.rng(seed_value, "siege")
	var order := Seeded.shuffled(r, NEW_KINDS.duplicate())
	var news := {GIANT_WAVE: "giant"}
	for i in NEW_WAVES.size():
		news[NEW_WAVES[i]] = order[i]
	var s := {"seed": seed_value, "level": lv, "daily": daily, "want": r.randi_range(0, WANTS.size() - 1),
		"new": news, "gentle": attempt, "mode": mode, "waves": []}
	if daily:
		s.want = Seeded.derive(seed_value, "want") % WANTS.size()
	for n in range(1, FINALE + 1):
		(s.waves as Array).append(_make_wave(s, n))
	return s


## Wave n's plan (waves past the planned ones are made from the seed on demand: the endless mode).
static func wave_plan(s: Dictionary, n: int) -> Dictionary:
	var waves: Array = s.get("waves", [])
	if n >= 1 and n <= waves.size():
		return waves[n - 1]
	return _make_wave(s, n)


## The kind wave n brings for the first time ("" when none).
static func new_kind(s: Dictionary, n: int) -> String:
	return String((s.new as Dictionary).get(n, ""))


## Wave n's step on the rising curve: boss waves are their own fight, so the plain wave after one carries on from the
## plain wave before it (no double step).
static func curve_n(n: int) -> int:
	var c := n
	for m in range(1, n):
		if boss_for(m) != "":
			c -= 1
	return c


static func boss_for(n: int) -> String:
	if n == FINALE:
		return "yeti"
	if n == KING_WAVE or (n > FINALE and n % 4 == 2):
		return "king"
	return ""


## How many snowmen wave n sends (before the party-size bonus main.gd adds).
static func wave_count(n: int, lv: int, boss: String, mode: String = "brave") -> int:
	var cn := curve_n(n)
	var base: int = [3, 5, 6, 8][n - 1] if n <= 4 else 5 + cn - (3 if n == GIANT_WAVE else 0)  # (the giants' wave: fewer, bigger)
	var c := roundi(base * (1.0 + 0.1 * (clampi(lv, 1, MAX_LEVEL) - 1) * clampf((n - 2) * 0.5, 0.0, 1.0)))  # always a gentle start
	c = maxi(3, roundi(c * float(mode_num(mode).count)))
	return maxi(1, c / 2 if boss != "" else c)


static func _make_wave(s: Dictionary, n: int) -> Dictionary:
	var lv: int = int(s.level)
	var gentle: int = int(s.get("gentle", 0))
	var r := Seeded.rng(int(s.seed), "wave%d" % n)
	var boss := boss_for(n)
	var gate_n := 1 if n <= 2 else (2 if n <= 4 else (3 if n <= 7 else 3 + int(r.randf() < 0.3 + 0.1 * lv)))
	var gates: Array = []
	var tries := 0
	while gates.size() < gate_n and tries < 60:
		tries += 1
		var a := FRONT + r.randf_range(-FRONT_ARC, FRONT_ARC) if n <= 2 else r.randf() * TAU
		var ok := true
		for g in gates:
			if _ang(a, float(g)) < MIN_GATE_SEP:
				ok = false
		if ok:
			gates.append(wrapf(a, -PI, PI))
	var nk := new_kind(s, n)
	var pool: Array[String] = []
	for w in (s.new as Dictionary):
		if n > int(w):
			pool.append(String(s.new[w]))
	pool.sort()
	var mode := String(s.get("mode", "brave"))
	var count := wave_count(n, lv, boss, mode)
	var need := 0
	if nk != "":
		need = mini(count - 1, new_count(nk, mode))
	# Where in the wave the new kind's arrivals go: spread out, never first (a plain one leads the way).
	var new_at := {}
	for k in need:
		new_at[1 + int(float(k) * float(count - 1) / float(need))] = true
	var spawns: Array = []
	var first_gate := r.randi_range(0, gates.size() - 1)
	var base_gap := maxf(MIN_GAP, (0.6 + 2.4 * pow(0.8, curve_n(n) - 1)) * (1.0 - 0.05 * (lv - 1) * (0.0 if n <= 2 else 1.0)))  # 3 s, 2.5, 2.1, ... 0.8 at wave 12
	base_gap *= 1.0 + 0.12 * gentle
	var gap_k := float(mode_num(mode).gap)
	base_gap *= maxf(1.0, gap_k) if n <= 1 else gap_k  # (wave 1 is a gentle trickle in every mode)
	if n == GIANT_WAVE:
		base_gap *= 1.3  # the giants' wave: room round the big ones
	for i in count:
		var ri := Seeded.rng(int(s.seed), "wave%d spawn%d" % [n, i])  # each spawn its own stream: modes share them
		var kind := "snowman"
		var roll := ri.randf()
		if new_at.has(i):
			kind = nk
		elif not pool.is_empty() and roll >= 0.55:
			kind = String(Seeded.pick(ri, pool))
		var gap := maxf(MIN_GAP, base_gap * ri.randf_range(0.85, 1.2))
		if i > 0 and i % 5 == 0:
			gap += 1.5  # a breather
		if i == 0:
			gap = 0.5
		# Gates take turns (now and then one goes twice), so no wall gets every snowman.
		var gate := (i + first_gate) % gates.size()
		if ri.randf() < 0.25 - 0.08 * gentle:
			gate = ri.randi_range(0, gates.size() - 1)
		spawns.append([snappedf(gap, 0.01), kind, gate, snappedf(ri.randf_range(-MAX_JITTER, MAX_JITTER), 0.001)])
	return {"n": n, "gates": gates, "boss": boss, "spawns": spawns, "boss_gate": r.randi_range(0, gates.size() - 1)}


## Where a spawn walks in.
static func spawn_pos(w: Dictionary, sp: Array) -> Vector3:
	var a: float = float((w.gates as Array)[int(sp[2])]) + float(sp[3])
	return Vector3(cos(a), 0.0, sin(a)) * SPAWN_R


static func boss_pos(w: Dictionary) -> Vector3:
	var a: float = float((w.gates as Array)[int(w.get("boss_gate", 0))])
	return Vector3(cos(a), 0.0, sin(a)) * SPAWN_R


## main.gd's wall segment for a spot (== main._nearest_seg).
static func seg_of(pos: Vector3) -> int:
	return posmod(roundi(atan2(pos.z, pos.x) / (TAU / SEGMENTS)), SEGMENTS)


## A snowman's walking speed in wave n (== snowman.gd setup + main._spawn_snowman's gentle start).
static func speed_of(kind: String, n: int, mode: String = "brave") -> float:
	var v := float(KINDS[kind].speed) * (1.0 + minf(n, 12) * 0.025) * float(mode_num(mode).speed)
	if kind == "snowman" and n <= 2:
		v *= 0.55 if n <= 1 else 0.8
	return v


static func hp_of(kind: String, n: int) -> float:
	return float(KINDS[kind].hp) * (1.0 + (n - 1) * 0.1) * (3.0 if kind == "bunny" else 1.0)  # bunnies come in threes


static func _ang(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## Problems with a siege (empty = fair).
static func check(s: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var waves: Array = s.get("waves", [])
	var mode := String(s.get("mode", "brave"))
	if not MODE_NUM.has(mode):
		why.append("no such mode %s" % mode)
		mode = "brave"
	if waves.size() != FINALE:
		why.append("%d waves planned (want %d)" % [waves.size(), FINALE])
		return why
	if int(s.want) < 0 or int(s.want) >= WANTS.size():
		why.append("no such want %d" % int(s.want))
	var met := {"snowman": true}
	for w in waves:
		var n: int = int(w.n)
		var gates: Array = w.gates
		if gates.is_empty():
			why.append("wave %d has no gate" % n)
			continue
		for i in gates.size():
			if not is_finite(float(gates[i])):
				why.append("wave %d gate %d is nowhere" % [n, i])
			if n <= 2 and _ang(float(gates[i]), FRONT) > FRONT_ARC + 0.001:
				why.append("wave %d comes from behind (gate %.2f)" % [n, float(gates[i])])
			for j in i:
				if _ang(float(gates[i]), float(gates[j])) < MIN_GATE_SEP - 0.001:
					why.append("wave %d gates %d and %d are too close" % [n, j, i])
		if String(w.boss) != boss_for(n):
			why.append("wave %d boss %s (want %s)" % [n, w.boss, boss_for(n)])
		var nk := new_kind(s, n)
		if nk != "":
			met[nk] = true
		var spawns: Array = w.spawns
		if spawns.is_empty():
			why.append("wave %d is empty" % n)
			continue
		var news := 0
		for i in spawns.size():
			var sp: Array = spawns[i]
			var kind := String(sp[1])
			if not met.has(kind):
				why.append("wave %d sends a %s before it's been met" % [n, kind])
			if kind == nk:
				news += 1
			if int(sp[2]) < 0 or int(sp[2]) >= gates.size():
				why.append("wave %d spawn %d uses no gate" % [n, i])
				continue
			if absf(float(sp[3])) > MAX_JITTER + 0.001:
				why.append("wave %d spawn %d wanders off its gate" % [n, i])
			if i > 0 and float(sp[0]) < MIN_GAP - 0.001:
				why.append("wave %d spawn %d follows too fast (%.2f s)" % [n, i, float(sp[0])])
			if n == 1 and i > 0 and float(sp[0]) < 2.5:
				why.append("wave 1 isn't a gentle trickle")
		if n <= 2 and news > 0:
			why.append("wave %d brings something new" % n)
		var want_new := new_count(nk, mode)
		if nk != "" and news < want_new and spawns.size() > want_new:
			why.append("wave %d brings only %d %s" % [n, news, nk])
		var swamp := _swamp(w, mode)
		var most: int = ceili(SWAMP_MAX[mini(n, SWAMP_MAX.size()) - 1] * float(mode_num(mode).swamp))
		if swamp > most:
			why.append("wave %d swamps one wall with %d snowmen (most %d)" % [n, swamp, most])
		if n <= int(mode_num(mode).kid_waves):
			var left := hold(w, float(mode_num(mode).kid), KID_SPOT, mode)
			if left < KID_KEEP:
				why.append("wave %d: a small child alone loses a wall (%.0f%% left)" % [n, left * 100.0])
		if n <= TEAM_WAVES and String(w.boss) == "":
			var left_t := hold(w, float(mode_num(mode).team), KID_SPOT, mode)
			if left_t <= 0.0:
				why.append("wave %d: a VR player + a child lose a wall" % n)
	# No cliffs: from wave 3 on, a wave is at most JUMP times the last plain wave (calm waves don't count).
	var prev := 0.0
	for n in range(1, FINALE + 1):
		var t := threat(s, n)
		if n >= 3 and prev > 0.0 and t > maxf(prev, CALM) * JUMP:
			why.append("wave %d is a cliff (%.0f%% harder than the wave before)" % [n, (t / maxf(prev, CALM) - 1.0) * 100.0])
		if boss_for(n) == "":
			prev = t
	return why


## How many of the new kind its wave brings (giants 2, others 3; gentle one fewer).
static func new_count(kind: String, mode: String) -> int:
	return (2 if kind == "giant" else 3) - (1 if mode == "gentle" else 0)


## Arrival times at the walls: [[t, kind, segment, hp], ...] (spawn time + the walk in).
static func arrivals(w: Dictionary, mode: String = "brave") -> Array:
	var out: Array = []
	var t := 0.0
	var n: int = int(w.n)
	for sp in w.spawns:
		t += float(sp[0])
		var kind := String(sp[1])
		var pos := spawn_pos(w, sp)
		var walk := (SPAWN_R - FORT_RADIUS - 0.8) / speed_of(kind, n, mode)
		out.append([t + walk, kind, seg_of(pos), hp_of(kind, n), t])
	return out


## The most snowmen reaching one wall within SWAMP_WINDOW seconds of each other.
static func _swamp(w: Dictionary, mode: String = "brave") -> int:
	var arr := arrivals(w, mode)
	var most := 0
	for a in arr:
		var c := 0
		for b in arr:
			if int(b[2]) == int(a[2]) and float(b[0]) >= float(a[0]) and float(b[0]) - float(a[0]) <= SWAMP_WINDOW:
				c += 1  # (a bunny trio counts once: they are tiny)
		most = maxi(most, c)
	return most


## Simulate one thrower (hits per second `rate`, `spot` seconds to see each snowman) knocking the
## snowmen over in the order they come in: the share of the weakest wall left at the end (<= 0: it fell).
static func hold(w: Dictionary, rate: float, spot: float, mode: String = "brave") -> float:
	var arr := arrivals(w, mode)
	var hit := float(mode_num(mode).hit)
	arr.sort_custom(func(a: Array, b: Array) -> bool: return float(a[4]) < float(b[4]))
	var seg := []
	seg.resize(SEGMENTS)
	seg.fill(SEG_MAX)
	var free_t := 0.0
	for a in arr:
		var kill_t := maxf(free_t, float(a[4]) + spot) + float(a[3]) / rate
		free_t = kill_t
		var at := float(a[0])
		if kill_t > at:
			var d: Dictionary = KINDS[String(a[1])]
			var dmg := (float(d.get("crash", 0.0)) + float(d.get("wall_dps", 0.0)) * (kill_t - at) * (3.0 if String(a[1]) == "bunny" else 1.0)) * hit
			seg[int(a[2])] = float(seg[int(a[2])]) - dmg
	var low := SEG_MAX
	for v in seg:
		low = minf(low, float(v))
	return low / SEG_MAX


## How hard wave n of a siege is: the snowballs it takes to knock its snowmen over (a TV throw does TV_HIT; balloons
## need popping first), per second of the wave (its spawns, the walk in, and a boss's fight at the team's pace), times
## how hard they hit.
static func threat(s: Dictionary, n: int) -> float:
	var w := wave_plan(s, n)
	var mode := String(s.get("mode", "brave"))
	var num := mode_num(mode)
	var throws := 0.0
	var span := 0.0
	for sp in w.spawns:
		span += float(sp[0])
		throws += throws_for(String(sp[1]), n)
	var boss := String(w.boss)
	var fight := 0.0
	if boss != "":
		throws += throws_for(boss, n)
		fight = throws_for(boss, n) / float(num.team)
	var walk := (SPAWN_R - FORT_RADIUS - 0.8) / speed_of("snowman", n, mode)
	return throws * float(num.hit) / (span + walk + fight)


## Snowballs that knock one spawn over (a bunny spawn is a trio, a balloon snowman's balloons pop first).
static func throws_for(kind: String, n: int) -> float:
	var one := ceilf(float(KINDS[kind].hp) * (1.0 + (n - 1) * 0.1) / TV_HIT)
	return one * (3.0 if kind == "bunny" else 1.0) + float(KINDS[kind].get("balloons", 0))


## Problems with the three modes of one seed (empty = fair): every wave gentle <= brave <= hard (snowmen and threat).
## (Each mode's own siege is checked by check(): no cliffs; curve() gives the average rise over many seeds.)
static func check_modes(seed_value: int, lv: int, daily: bool = false) -> Array[String]:
	var why: Array[String] = []
	var sieges := {}
	for mode in MODES:
		sieges[mode] = siege(seed_value, lv, daily, mode)
	for n in range(1, FINALE + 1):
		for k in 2:
			var a: Dictionary = sieges[MODES[k]]
			var b: Dictionary = sieges[MODES[k + 1]]
			var ca := (wave_plan(a, n).spawns as Array).size()
			var cb := (wave_plan(b, n).spawns as Array).size()
			if ca > cb:
				why.append("wave %d: %s sends %d snowmen, %s only %d" % [n, MODES[k], ca, MODES[k + 1], cb])
			if int(a.gentle) == int(b.gentle) and threat(a, n) > threat(b, n) * ORDER_SLACK:  # (a rerolled siege is another mix)
				why.append("wave %d: %s is harder than %s (%.2f > %.2f)" % [n, MODES[k], MODES[k + 1], threat(a, n), threat(b, n)])
	return why


## The average threat of waves 1..FINALE in a mode over `count` seeds at level lv (the rising curve).
static func curve(mode: String, lv: int, count: int = 60) -> Array[float]:
	var out: Array[float] = []
	out.resize(FINALE)
	out.fill(0.0)
	for k in count:
		var s := siege(1000 + k * 7919, lv, false, mode)
		for n in range(1, FINALE + 1):
			out[n - 1] += threat(s, n) / count
	return out


## Problems with a mode's average curve (empty = it rises smoothly): every plain wave at least nearly as hard as the
## plain wave before (bosses are their own fight), never more than CLIFF times it (CLIFF_START for wave 2).
static func check_curve(c: Array[float]) -> Array[String]:
	var why: Array[String] = []
	var prev := 0.0
	for n in range(1, c.size() + 1):
		var t := c[n - 1]
		if prev > 0.0 and boss_for(n) == "":
			if t < prev * 0.9:
				why.append("wave %d is easier than the wave before (%.2f < %.2f)" % [n, t, prev])
			if t > prev * (CLIFF_START if n == 2 else CLIFF):
				why.append("wave %d jumps %.0f%% harder" % [n, (t / prev - 1.0) * 100.0])
		elif prev > 0.0 and t > prev * CLIFF:
			why.append("boss wave %d is %.0f%% harder than the wave before" % [n, (t / prev - 1.0) * 100.0])
		if boss_for(n) == "":
			prev = t
	return why


# --- The village -------------------------------------------------------------------------------

## Where igloo i stands (Vector3.INF past the end).
static func village_slot(i: int) -> Vector3:
	if i < 0 or i >= VILLAGE_SLOTS:
		return Vector3.INF
	var row := i % 2
	var k := i / 2  # 0..11: alternate sides, nearest the tree first
	var side := 1.0 if k % 2 == 0 else -1.0
	var step := k / 2  # 0..5
	var span := VILLAGE_ARC - TREE_GAP
	var a := FRONT + side * (TREE_GAP + span * (float(step) + 0.5 * row + 0.25) / 6.0)
	var r: float = VILLAGE_R[row]
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## An igloo's growth stage (1 new .. 3 grown) from the play-day it was built and the play-days now.
static func igloo_stage(built_day: int, days: int) -> int:
	return clampi(1 + days - built_day, 1, 3)
