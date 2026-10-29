extends RefCounted
## Soft Dodgeball's seeded rounds: TUMTUM the friendly giant's park. Every round is built from one code
## (seed, level, daily) so the host sends a single number and every machine rebuilds the same round.
## A round has: a name ("Puffy Meadow"), puffy CUSHIONS on the court to hide behind (balls bounce off
## them), the CPU giant's pace / flight time / aim wobble, the safe-blink time after a hit, a fair
## target order, and GOLD STAR windows (TumTum's belly shines: belly hits count 2).
## Level = the round in the session (1 = gentle warm-up .. MAX_LEVEL); TODAY'S PARK is one gold round a
## day, the same on every machine (Seeded.daily_seed), at DAILY_LEVEL.
## FAIR AND GENTLE (check()): the CPU giant shares its throws out evenly (pick_target: whoever has had
## the fewest, never the one blinking), a runner hit twice in a short while gets a longer bubble
## (safe_time), and a simulated small kid who never dodges still plays most of the round
## (simulate(): out share, throws per 10 s, gap between throws at one runner) for 1..6 runners.
## tests/dodge_ball_gen_test.gd proves it over many seeds.
## The park (park.gd) grows a thing per finished round; park_kind / park_slot / park_stage are here so the
## test can check every spot.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "dodge_ball"
const MAX_LEVEL := 6
const DAILY_LEVEL := 2

# Must match main.gd (the test checks).
const OUT_TIME := 3.0
const COURT_X := 6.3
const COURT_Z := Vector2(-3.9, 6.3)
const GIANT_POS := Vector2(0.0, -6.4)  # (x, z) of the giant on the stage
const SPAWNS: Array[Vector2] = [Vector2(-3.0, 3.0), Vector2(-1.5, 3.0), Vector2(0.0, 3.0), Vector2(1.5, 3.0), Vector2(3.0, 3.0)]
const ROUND_TIME := 120.0
const REACH := 0.5  # CPU giant: reach for a ball (at most), then wind up, then throw
const WINDUP := 0.7

# Cushions: where they may go and how big they are.
const CUSHION_AREA := Rect2(-5.0, -2.6, 10.0, 7.2)  # x, z, w, d (keeps the court's edges and the stage front free)
const CUSHION_R := Vector2(0.55, 0.8)
const CUSHION_H := 0.85
const RUNNER_R := 0.35
const GAP := 1.3  # room between two cushions (and a cushion and the fence) for a runner to run through
const SPAWN_CLEAR := 1.3

# Gentle rules.
const GENTLE_WINDOW := 15.0  # hit twice inside this many seconds ...
const GENTLE_EXTRA := 2.0  # ... and the bubble lasts this much longer
const MAX_OUT_SHARE := 0.45  # a kid who never dodges is out at most this share of the round
const MAX_PER_10S := 4  # throws at one runner in any 10 s
const MIN_GAP := 2.0  # seconds between two throws at the same runner
const MAX_SPREAD := 2  # throws per runner differ by at most this (everyone gets a fair share)

const ADJ: Array[String] = ["SUNNY", "PUFFY", "BOUNCY", "HAPPY", "BREEZY", "GIGGLY", "SPARKLY", "COSY", "JOLLY", "WIGGLY"]
const NOUN: Array[String] = ["PARK", "MEADOW", "GARDEN", "GREEN", "FIELD", "HILL", "DELL"]
const CUSHION_COLORS: Array[Color] = [Color(1.0, 0.62, 0.75), Color(0.6, 0.8, 1.0), Color(0.75, 0.65, 1.0),
	Color(0.6, 0.92, 0.7), Color(1.0, 0.85, 0.5), Color(1.0, 0.7, 0.55)]
const GOLD := Color(1.0, 0.82, 0.25)

# The park that grows (park.gd).
const PARK_KINDS: Array[String] = ["daisy", "sunflower", "sapling", "balloon", "bunny", "toadstool", "duckling"]
const PARK_STAGES := 4  # a thing grows a stage each play-day after it came
const ORDER_N := 16  # target order covers party slots 0..6 and CPU runners 10, 11


## A round's code: seed, level and daily packed in one int (what the host sends).
static func code_of(seed_v: int, level: int, daily: bool) -> int:
	return seed_v * 100 + clampi(level, 1, MAX_LEVEL) * 2 + (1 if daily else 0)


static func seed_of(code: int) -> int:
	return code / 100


static func level_of(code: int) -> int:
	return (code % 100) / 2


static func daily_of(code: int) -> bool:
	return code % 2 == 1


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## The code of round `round_no` (1-based) of a session: TODAY'S PARK first when it's due today, then
## rounds from the session seed, one level up each round.
static func code_at(session_seed: int, round_no: int, daily_due: bool, date: String = "") -> int:
	if daily_due and round_no == 1:
		return code_of(daily_seed(date), DAILY_LEVEL, true)
	var lv := round_no - (1 if daily_due else 0)
	return code_of(Seeded.derive(session_seed, round_no), clampi(lv, 1, MAX_LEVEL), false)


## The round for a code (plain Dictionary; deterministic).
static func build(code: int) -> Dictionary:
	var s := seed_of(code)
	var lv := level_of(code)
	var daily := daily_of(code)
	var k := float(lv - 1) / float(MAX_LEVEL - 1)  # 0 = warm-up .. 1 = top
	var r := Seeded.rng(s, "round")
	var d := {"code": code, "seed": s, "level": lv, "daily": daily}
	d["name"] = "%s %s" % [Seeded.pick(r, ADJ), Seeded.pick(r, NOUN)]
	d["color"] = GOLD if daily else CUSHION_COLORS[r.randi() % CUSHION_COLORS.size()]
	d["pace"] = snappedf(lerpf(2.3, 1.25, k) + r.randf_range(0.0, 0.2), 0.01)  # CPU giant's wait between throws ...
	d["jitter"] = snappedf(lerpf(0.5, 0.3, k), 0.01)  # ... plus up to this
	d["flight"] = snappedf(lerpf(1.15, 0.9, k) + r.randf_range(-0.03, 0.03), 0.01)  # seconds a lob flies (time to dodge)
	d["wobble"] = snappedf(lerpf(0.75, 0.35, k) + r.randf_range(-0.05, 0.05), 0.01)  # aim wobble (m)
	d["safe"] = snappedf(lerpf(2.2, 1.6, k), 0.01)  # blinking after popping back
	d["order"] = Seeded.shuffled(Seeded.rng(s, "order"), range(ORDER_N))
	d["cushions"] = _cushions(Seeded.rng(s, "cushions"), lv)
	# Gold star windows: [start, end] as shares of the round.
	var sr := Seeded.rng(s, "stars")
	var n := 1 + (1 if lv >= 3 else 0) + (1 if lv >= 5 and sr.randf() < 0.5 else 0)
	if daily:
		n = 2
	var stars: Array = []
	var span := 0.8 / float(n)
	for i in n:
		var a := 0.12 + span * float(i) + sr.randf_range(0.0, span - 0.14)
		stars.append([snappedf(a, 0.001), snappedf(a + 0.1, 0.001)])
	d["stars"] = stars
	return d


static func _cushions(r: RandomNumberGenerator, lv: int) -> Array:
	var want := clampi(1 + (lv + 1) / 2 + (1 if r.randf() < 0.4 else 0), 1, 4)
	var out: Array = []
	var tries := 0
	while out.size() < want and tries < 200:
		tries += 1
		var rad := r.randf_range(CUSHION_R.x, CUSHION_R.y)
		var p := Vector2(r.randf_range(CUSHION_AREA.position.x + rad, CUSHION_AREA.end.x - rad),
			r.randf_range(CUSHION_AREA.position.y + rad, CUSHION_AREA.end.y - rad))
		if _cushion_ok(p, rad, out):
			out.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(rad, 0.01)])
	return out


static func _cushion_ok(p: Vector2, rad: float, others: Array) -> bool:
	for sp in SPAWNS:
		if p.distance_to(sp) < rad + SPAWN_CLEAR:
			return false
	for o in others:
		if p.distance_to(Vector2(o[0], o[1])) < rad + float(o[2]) + GAP:
			return false
	return true


## Is the star shining at this share of the round?
static func star_on(d: Dictionary, share: float) -> bool:
	for w in d["stars"]:
		if share >= float(w[0]) and share < float(w[1]):
			return true
	return false


## Push a point (x, z) out of the cushions (runners and the court clamp use it on every machine).
static func push_out(d: Dictionary, p: Vector3, radius: float = RUNNER_R) -> Vector3:
	for c in d.get("cushions", []):
		var cc := Vector2(c[0], c[1])
		var v := Vector2(p.x, p.z) - cc
		var need := float(c[2]) + radius
		if v.length() < need:
			var n := v.normalized() if v.length() > 0.001 else Vector2(0.0, 1.0)
			var q := cc + n * need
			p.x = q.x
			p.z = q.y
	return p


## FAIR TARGETS: of the runners free to aim at (not out, not blinking), whoever has had the fewest throws
## this round; ties go by the round's seeded order, turned by k (the throw number) so nobody is always first.
static func pick_target(d: Dictionary, counts: Dictionary, ids: Array, k: int) -> int:
	var best := -1
	var best_c := 1 << 30
	var best_r := 1 << 30
	var order: Array = d["order"]
	for id in ids:
		var c := int(counts.get(id, 0))
		var rank := (order.find(int(id) % ORDER_N) + k) % ORDER_N
		if c < best_c or (c == best_c and rank < best_r):
			best = int(id)
			best_c = c
			best_r = rank
	return best


## GENTLE: how long a runner blinks after popping back. Hit again soon after the last hit = a longer bubble.
static func safe_time(d: Dictionary, hit_times: Array, now: float) -> float:
	var base := float(d["safe"])
	for t in hit_times:
		if now - float(t) < GENTLE_WINDOW and now - float(t) > 0.001:
			return base + GENTLE_EXTRA
	return base


## The CPU giant's wait before its next throw.
static func wait_time(d: Dictionary, x: float) -> float:
	return float(d["pace"]) + float(d["jitter"]) * clampf(x, 0.0, 1.0)


## A model of the round with `n` small runners who never dodge (every throw at them hits with `hit_chance`),
## following the game's CPU giant (wait, reach, wind up, lob, pick_target, out, safe_time). Returns per-runner
## numbers: out share, throws, most throws in 10 s, shortest gap between throws at them.
static func simulate(d: Dictionary, n: int, hit_chance: float, sim_seed: int, round_time: float = ROUND_TIME) -> Dictionary:
	var r := Seeded.rng(sim_seed, "sim")
	var ids: Array = range(n)
	var out_until := {}
	var safe_until := {}
	var hits := {}
	var throws := {}
	var out_total := {}
	var counts := {}
	for id in ids:
		hits[id] = []
		throws[id] = []
		out_total[id] = 0.0
	var dt := 0.05
	var t := 0.0
	var next_try := 2.5  # the CPU giant's first wait (main.gd cpu_g.t)
	var flying: Array = []  # [land_time, id]
	var k := 0
	while t < round_time:
		for id in ids:
			if t < float(out_until.get(id, -1.0)):
				out_total[id] = float(out_total[id]) + dt
		for f in flying.duplicate():
			if t >= float(f[0]):
				flying.erase(f)
				var id: int = f[1]
				var free: bool = t >= float(out_until.get(id, -1.0)) and t >= float(safe_until.get(id, -1.0))
				if free and r.randf() < hit_chance:
					out_until[id] = t + OUT_TIME
					safe_until[id] = t + OUT_TIME + safe_time(d, hits[id], t)
					(hits[id] as Array).append(t)
		if t >= next_try:
			var cands: Array = []
			for id in ids:
				if t >= float(out_until.get(id, -1.0)) and t >= float(safe_until.get(id, -1.0)):
					cands.append(id)
			if cands.is_empty():
				next_try = t + 0.5
			else:
				var aim := pick_target(d, counts, cands, k)
				k += 1
				counts[aim] = int(counts.get(aim, 0)) + 1
				var release := t + REACH + WINDUP
				(throws[aim] as Array).append(release)
				flying.append([release + float(d["flight"]), aim])
				next_try = release + wait_time(d, r.randf())
		t += dt
	var res := {"out_share": {}, "throws": {}, "per10": {}, "gap": {}}
	for id in ids:
		var th: Array = throws[id]
		var most := 0
		var gap := INF
		for i in th.size():
			var c := 0
			for j in range(i, th.size()):
				if float(th[j]) - float(th[i]) < 10.0:
					c += 1
			most = maxi(most, c)
			if i > 0:
				gap = minf(gap, float(th[i]) - float(th[i - 1]))
		res["out_share"][id] = float(out_total[id]) / round_time
		res["throws"][id] = th.size()
		res["per10"][id] = most
		res["gap"][id] = gap
	return res


## Everything wrong with a round (empty = fair and gentle).
static func check(d: Dictionary) -> Array:
	var why: Array = []
	var lv := int(d["level"])
	if lv < 1 or lv > MAX_LEVEL:
		why.append("level %d out of range" % lv)
	var words := str(d["name"]).split(" ")
	if words.size() != 2 or not (words[0] in ADJ) or not (words[1] in NOUN):
		why.append("name %s not from the word lists" % d["name"])
	if float(d["pace"]) < 1.2 or float(d["pace"]) > 2.6:
		why.append("pace %.2f" % float(d["pace"]))
	if float(d["flight"]) < 0.85:
		why.append("lobs too fast to dodge (%.2f s)" % float(d["flight"]))
	if float(d["safe"]) < 1.5:
		why.append("safe blink too short")
	if float(d["wobble"]) < 0.25 or float(d["wobble"]) > 0.85:
		why.append("wobble %.2f" % float(d["wobble"]))
	# Cushions: inside the court, room between them and to the fence, never on a spawn spot.
	var cs: Array = d["cushions"]
	if cs.is_empty() or cs.size() > 4:
		why.append("%d cushions" % cs.size())
	for i in cs.size():
		var c: Array = cs[i]
		var p := Vector2(c[0], c[1])
		var rad := float(c[2])
		if rad < CUSHION_R.x - 0.01 or rad > CUSHION_R.y + 0.01:
			why.append("cushion %d radius %.2f" % [i, rad])
		if absf(p.x) + rad > COURT_X - GAP + 0.01 or p.y - rad < COURT_Z.x + GAP - 0.01 or p.y + rad > COURT_Z.y - GAP + 0.01:
			why.append("cushion %d too near the edge (%s)" % [i, str(p)])
		for sp in SPAWNS:
			if p.distance_to(sp) < rad + SPAWN_CLEAR - 0.01:
				why.append("cushion %d on a spawn spot" % i)
		for j in range(i + 1, cs.size()):
			var o: Array = cs[j]
			if p.distance_to(Vector2(o[0], o[1])) < rad + float(o[2]) + GAP - 0.01:
				why.append("cushions %d and %d leave no room between" % [i, j])
	var g := grid_stats(d)
	if not bool(g["connected"]):
		why.append("the court is cut in two")
	if float(g["hidden"]) > 0.3:
		why.append("too much of the court hidden from the giant (%.2f)" % float(g["hidden"]))
	if float(g["hidden"]) < 0.01:
		why.append("nowhere to hide (%.3f)" % float(g["hidden"]))
	# Gold stars inside the round, apart.
	var st: Array = d["stars"]
	if st.is_empty() or st.size() > 3:
		why.append("%d star windows" % st.size())
	var last := 0.0
	for w in st:
		if float(w[0]) < 0.1 or float(w[1]) > 0.95 or float(w[1]) <= float(w[0]) or float(w[0]) < last + 0.04:
			why.append("star window %s" % str(w))
		last = float(w[1])
	# FAIR AND GENTLE for 1..6 small runners who never dodge (every throw hits, and half of them do).
	for n in range(1, 7):
		for hc in [1.0, 0.5]:
			var sim := simulate(d, n, hc, int(d["seed"]) + n)
			var lo := 1 << 30
			var hi := 0
			for id in range(n):
				var share := float(sim["out_share"][id])
				if share > MAX_OUT_SHARE:
					why.append("%d runners, hits %.1f: runner %d is out %.0f%% of the round" % [n, hc, id, share * 100.0])
				if int(sim["per10"][id]) > MAX_PER_10S:
					why.append("%d runners: runner %d gets %d throws in 10 s" % [n, id, int(sim["per10"][id])])
				if float(sim["gap"][id]) < MIN_GAP:
					why.append("%d runners: runner %d thrown at twice in %.1f s" % [n, id, float(sim["gap"][id])])
				lo = mini(lo, int(sim["throws"][id]))
				hi = maxi(hi, int(sim["throws"][id]))
			if hi - lo > MAX_SPREAD:
				why.append("%d runners, hits %.1f: unfair share of throws (%d..%d)" % [n, hc, lo, hi])
			if lo == 0:
				why.append("%d runners: somebody never gets a ball to dodge" % n)
	return why


## The court on a 0.5 m grid: is all the free court one piece, and what share is hidden behind a cushion
## from the giant (a cushion shades up to 2.5 m behind it)?
static func grid_stats(d: Dictionary) -> Dictionary:
	var step := 0.5
	var nx := int(COURT_X * 2.0 / step) + 1
	var nz := int((COURT_Z.y - COURT_Z.x) / step) + 1
	var free := {}
	var hidden := 0
	for ix in nx:
		for iz in nz:
			var p := Vector2(-COURT_X + ix * step, COURT_Z.x + iz * step)
			var blocked := false
			for c in d["cushions"]:
				if p.distance_to(Vector2(c[0], c[1])) < float(c[2]) + RUNNER_R:
					blocked = true
			if blocked:
				continue
			free[Vector2i(ix, iz)] = true
			for c in d["cushions"]:
				var cc := Vector2(c[0], c[1])
				var behind := p.distance_to(GIANT_POS) - cc.distance_to(GIANT_POS)
				if behind > 0.0 and behind < 2.5 and Geometry2D.get_closest_point_to_segment(cc, GIANT_POS, p).distance_to(cc) < float(c[2]) * 0.8:
					hidden += 1
					break
	# Flood fill from the first free cell.
	var start: Vector2i = free.keys()[0]
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var q: Vector2i = todo.pop_back()
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nq: Vector2i = q + o
			if free.has(nq) and not seen.has(nq):
				seen[nq] = true
				todo.append(nq)
	return {"connected": seen.size() == free.size(), "hidden": float(hidden) / float(free.size()), "free": free.size()}


# --- The park that grows (park.gd draws it) ---------------------------------------------------------

## The kind of the park's `n`th thing (from the round that brought it).
static func park_kind(code: int, n: int) -> int:
	return absi(hash("%d/park/%d" % [seed_of(code), n])) % PARK_KINDS.size()


## How grown a thing is (0 = just planted .. PARK_STAGES - 1).
static func park_stage(joined_day: int, days: int) -> int:
	return clampi(days - joined_day, 0, PARK_STAGES - 1)


const PARK_SLOTS := 23


## Where the park's `i`th thing stands (x, 0, z): beside the court's side fences (seen from the TV views)
## then along the back fence (seen by the giant). Vector3.INF past the end.
static func park_slot(i: int) -> Vector3:
	if i < 0 or i >= PARK_SLOTS:
		return Vector3.INF
	if i < 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var row := i / 2
		return Vector3(side * 8.35, 0.0, -3.4 + 1.5 * float(row))
	var j := i - 14
	return Vector3(-6.0 + 1.5 * float(j), 0.0, 8.35)
