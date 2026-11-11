extends RefCounted
## PENALTY SHOOTOUT second pass (pure data + small functions; tests/penalty_shootout_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs after practice:
##             how fast the kicks fly (a share of the match plan's speeds), how big Leo's star is to aim at, how often
##             a kick has warned weather, how long it is told first and how far a gust blows the ball.
##   GIFTS     LEO'S BOOT AND GLOVE GIFTS, three offered on the pick orbs before every match from the second: BIG GLOVES
##             (the keeper's gloves grow), SLOW-MO (every kick flies slower), CURVE BOOTS (banana kicks, a little
##             faster), GOLDEN BALL (every star sent to Leo counts twice) and BIG STAR (Leo's star is easier to hit) -
##             the last two open as Leo's trophy corner grows. A gift lasts the whole match.
##   WEATHER   some kicks have warned weather, told by steady core/warn_rings.gd shapes on the pitch from the start of
##             the turn (nobody can kick before it has been told for `warn` seconds):
##               GUST  a pale blue band across the pitch with big arrows: the ball is blown sideways (and bends) the
##                     way the arrows point. The keeper reads it; the striker aims into the wind.
##               MUD   a brown patch round the penalty spot: this kick is slow and heavy.
##             hazards(cup_seed, n, spec) is the same list on every machine; problems() proves it fair (never in a
##             match's first kicks or on match 1, never two kicks in a row, a gust never blows a star kick out of the
##             goal, a lone keeper can still reach enough of the computer's kicks, told long enough).
##   SEASONS   the pitch is dressed for the season (Seeded.season): spring blossom, summer sun, autumn leaves, winter
##             snow drift down over the stands and the touchlines; autumn is gusty, spring muddy.
##   CORNER    every CORNER_EVERY star goals (prizes) Leo's TROPHY CORNER behind the left post gets a new piece (flags, a
##             cup cabinet, a fountain, a rainbow arch ...: saved, for good), far from every kick's path.
##   PICK ROW  three big orbs float in the goal mouth. A striker KICKS the ball through one (strikers take turns), or the
##             keeper REACHES into one on purpose (a glove has to move in and stay a moment: never a resting hand;
##             a flat keeper shuffles away and back in). Missed by everyone = the middle (it glows).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const MatchGen := preload("res://games/penalty_shootout/matchgen.gd")

## speed: share of the plan's kick speeds; star_r: share of Leo's star radius (bigger = easier to hit); every: one
## weather kick in this many; warn: seconds told before anyone can kick; drift: metres a gust blows the ball at the goal.
const MODES := {
	"gentle": {"speed": 0.85, "star_r": 1.25, "every": 6, "warn": 3.2, "drift": 0.6},
	"brave": {"speed": 1.0, "star_r": 1.0, "every": 4, "warn": 2.7, "drift": 0.9},
	"hard": {"speed": 1.08, "star_r": 0.85, "every": 3, "warn": 2.2, "drift": 1.2},
}
const MIN_WARN := 2.0
const MIN_SPEED := 5.5  # no kick slower than this (m/s): a slow kick still flies, it never lobs
const FIRST_MATCH := 2  # no weather on match 1 (one new thing at a time)
const FIRST_KICK := 3  # ... nor on a match's first kicks
const MUD_SLOW := 0.8  # MUD: the kick's speed share
const GUST_CURVE := 0.9  # GUST: how hard the ball bends with the wind (ball.gd curve units)
const GUST_Z := 5.5  # the gust band's middle (between the goal and the spot)
const GUST_LEN := 7.0  # its depth along the pitch
const GUST_W := 9.0  # its width across
const MUD_R := 1.4  # the mud patch round the spot
const GUST_COLOR := Color(0.6, 0.92, 1.0)  # pale wind blue
const MUD_COLOR := Color(0.62, 0.36, 0.16)  # muddy brown
const KINDS: Array[String] = ["gust", "mud"]
## Season -> weather weights (gust, mud), the drifting things' colour, a picture, Leo's line.
const SEASONS := {
	"spring": {"weights": [0.8, 1.4], "drift": Color(1.0, 0.72, 0.85), "pic": "daisy", "line": "Spring football!", "name": "spring"},
	"summer": {"weights": [0.8, 0.6], "drift": Color(1.0, 0.93, 0.5), "pic": "sunflower", "line": "Summer football!", "name": "summer"},
	"autumn": {"weights": [1.6, 1.0], "drift": Color(0.95, 0.5, 0.15), "pic": "acorn", "line": "Windy autumn!", "name": "autumn"},
	"winter": {"weights": [1.2, 1.0], "drift": Color(1.0, 1.0, 1.0), "pic": "snowflake", "line": "Snowy football!", "name": "winter"},
}
## Leo's gifts: id, name, picture, a short line, a colour, corner pieces needed.
const GIFTS: Array[Dictionary] = [
	{"id": "big", "name": "BIG GLOVES", "pic": "biggloves", "line": "Huge hands!", "color": Color(0.3, 1.0, 0.5), "unlock": 0},
	{"id": "slow", "name": "SLOW-MO", "pic": "snail", "line": "Sloooow kicks!", "color": Color(0.45, 0.75, 1.0), "unlock": 0},
	{"id": "curve", "name": "CURVE BOOTS", "pic": "curveboots", "line": "Banana kicks!", "color": Color(1.0, 0.5, 0.85), "unlock": 0},
	{"id": "golden", "name": "GOLDEN BALL", "pic": "goldball", "line": "Double stars!", "color": Color(1.0, 0.85, 0.25), "unlock": 2},
	{"id": "bigstar", "name": "BIG STAR", "pic": "star", "line": "A giant star!", "color": Color(1.0, 0.65, 0.2), "unlock": 4},
]
const SLOW := 0.78  # SLOW-MO: kick speed share
const CURVE := 0.7  # CURVE BOOTS: banana bend
const CURVE_FAST := 1.08  # ... and a little faster
const BIGSTAR := 1.4  # BIG STAR: star radius share
## Leo's trophy corner: one piece every CORNER_EVERY star goals.
const CORNER_EVERY := 2
const CORNER: Array[String] = ["flags", "cabinet", "fountain", "arch", "bell", "lights", "disco", "statue"]
const CORNER_PICS := {"flags": "bunting", "cabinet": "trophy", "fountain": "fountain", "arch": "rainbow", "bell": "bell",
	"lights": "lantern", "disco": "discoball", "statue": "lion"}
const CORNER_AT := Vector3(-10.5, 0.0, 0.5)  # the corner's middle (behind Leo's prizes, left of the goal)
## The pick row: three orbs in the goal mouth.
const ROW_X: Array[float] = [-2.2, 0.0, 2.2]
const ROW_Y := 1.25
const ROW_Z := 1.0
const ORB_SCALE := 0.75
const CATCH := 0.3  # a ball this near an orb's edge takes it
const HAND_R := 0.12  # a glove this near an orb's edge is in it
const DWELL := 0.25  # seconds a glove must stay in an orb (a hand sweeping past never picks)
const FLAT_R := 0.55  # a flat keeper this near an orb's middle (across) is under it
const ROW_WAIT := {"mode": 22.0, "gift": 18.0}  # nobody took one: the middle
const SOLO_WAIT := 14.0  # nobody to kick (a lone keeper): sooner


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, solo: bool) -> float:
	return SOLO_WAIT if solo else float(ROW_WAIT.get(stage, 18.0))


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["speed", "drift"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["star_r", "every", "warn"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if int(h.every) < 2:
		out.append("hard: weather on every kick")
	return out


## A kick's real top speed: the plan's speed for kick k, the mode's share, the gift and the mud.
static func top_speed(plan_top: float, mode: String, gift_id: String, hz: Dictionary) -> float:
	var s := plan_top * float(mode_data(mode).speed)
	if gift_id == "slow":
		s *= SLOW
	elif gift_id == "curve":
		s *= CURVE_FAST
	if String(hz.get("kind", "")) == "mud":
		s *= MUD_SLOW
	return maxf(MIN_SPEED + 1.0, s)


## The radius an aim must be within to take Leo's star.
static func star_r(mode: String, gift_id: String) -> float:
	return MatchGen.STAR_R * float(mode_data(mode).star_r) * (BIGSTAR if gift_id == "bigstar" else 1.0)


# --- Weather --------------------------------------------------------------------------------------------------

## The weather of every kick of match n: an Array of MatchGen.MAX_TURNS entries, {} (none) or {kind, sign, drift}.
## sign: the way a gust blows (world x). spec: {mode, season, from (bots: an earlier match), first (bots: an earlier
## kick)}.
static func hazards(cup_seed: int, n: int, spec: Dictionary) -> Array:
	var out: Array = []
	out.resize(MatchGen.MAX_TURNS)
	for k in out.size():
		out[k] = {}
	if n < int(spec.get("from", FIRST_MATCH)):
		return out
	var md := mode_data(String(spec.get("mode", "brave")))
	var plan := MatchGen.plan(cup_seed, n)
	var r := Seeded.rng(MatchGen.match_seed(cup_seed, n), "weather")
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var every := int(md.every)
	var k0 := int(spec.get("first", FIRST_KICK))
	var last := -9
	var block := k0
	while block < out.size():
		var k := block + r.randi_range(0, every - 1)
		if k <= last + 1:
			k = last + 2
		if k >= out.size():
			break
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		var e := {"kind": kind, "sign": 1 if r.randf() < 0.5 else -1, "drift": float(md.drift) if kind == "gust" else 0.0}
		if kind == "gust":
			e.sign = gust_sign(plan, k, int(e.sign))
		out[k] = e
		last = k
		block += every
	return out


## A gust blows towards the middle of a star kick (it never blows the star out of the goal) and of a computer kick
## (a lone keeper is never pushed out of reach); otherwise the seeded way.
static func gust_sign(plan: Dictionary, k: int, fallback: int) -> int:
	var st := MatchGen.star_at(plan, k)
	if st != Vector2.INF and absf(st.x) > 0.01:
		return -1 if st.x > 0.0 else 1
	if k < MatchGen.CPU_TURNS:
		var c: Vector3 = plan.cpu[k]
		if absf(c.x) > 0.01:
			return -1 if c.x > 0.0 else 1
	return fallback


## Where a kick aimed at `aim` really ends up (the gust's drift).
static func blown(aim: Vector2, hz: Dictionary) -> Vector2:
	if String(hz.get("kind", "")) != "gust":
		return aim
	return aim + Vector2(float(hz.sign) * float(hz.drift), 0.0)


## Reasons match n's weather is unfair (empty = fine).
static func problems(cup_seed: int, n: int, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var mode := String(spec.get("mode", "brave"))
	var md := mode_data(mode)
	var plan := MatchGen.plan(cup_seed, n)
	if float(md.warn) < MIN_WARN:
		why.append("told only %.1f s early" % float(md.warn))
	var first := int(spec.get("first", FIRST_KICK))
	var prev := -9
	for k in list.size():
		var e: Dictionary = list[k]
		if e.is_empty():
			continue
		if n < int(spec.get("from", FIRST_MATCH)):
			why.append("weather on match %d" % n)
		if k < first:
			why.append("weather on kick %d" % k)
		if k == prev + 1:
			why.append("weather on two kicks in a row (%d)" % k)
		prev = k
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown weather %s" % str(e))
			continue
		if String(e.kind) == "gust":
			if absf(float(e.drift)) > 1.5:
				why.append("a gust blows %.1f m" % float(e.drift))
			var st := MatchGen.star_at(plan, k)
			if st != Vector2.INF:
				var to := blown(st, e)
				if absf(to.x) > MatchGen.GOAL_HALF - 0.5:
					why.append("kick %d: a gust blows the star kick out of the goal" % k)
		for g in ["", "slow", "curve"]:
			if top_speed(MatchGen.speed_at(plan, k), mode, g, e) < MIN_SPEED:
				why.append("kick %d flies too slowly" % k)
	# A keeper alone vs the computer striker, with this mode's speeds and the weather.
	var reachable := 0
	for k in MatchGen.CPU_TURNS:
		var c: Vector3 = plan.cpu[k]
		var e2: Dictionary = list[k] if k < list.size() else {}
		var top := top_speed(MatchGen.speed_at(plan, k), mode, "", e2)
		var x := c.x
		if String(e2.get("kind", "")) == "gust":
			x += float(e2.sign) * float(e2.drift)
		var reach := MatchGen.kid_reach(MatchGen.kick_speed(top, c.z))
		if bool(plan.cpu_star[k]):
			continue  # (a computer kick at the star is gentle and aimed off the middle: the star is the point)
		if absf(x) <= reach + 0.001:
			reachable += 1
		elif k < MatchGen.CPU_EASY:
			why.append("computer kick %d is out of a small keeper's reach (%s)" % [k, mode])
	var plain := 0
	for k in MatchGen.CPU_TURNS:
		if not bool(plan.cpu_star[k]):
			plain += 1
	if reachable < int(ceil(plain * MatchGen.CPU_SAVE_SHARE)) - 1:
		why.append("a lone keeper reaches only %d of %d computer kicks (%s)" % [reachable, plain, mode])
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), int(e.sign), float(e.drift)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 3 else {"kind": String(a[0]), "sign": int(a[1]), "drift": float(a[2])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(pieces: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if pieces >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are others
## (the same on every machine for a seed).
static func gift_choices(pieces: int, last: String, seed_value: int) -> Array:
	var un := unlocked(pieces)
	var newest: String = un[un.size() - 1]
	var pool: Array = []
	for id in un:
		if id != newest and (id != last or un.size() <= 3):
			pool.append(id)
	pool = Seeded.shuffled(Seeded.rng(seed_value, "gifts"), pool)
	var out: Array = [newest] if newest != last or un.size() <= 3 else []
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	if out.size() < 3:
		for id in un:
			if out.size() < 3 and not out.has(id):
				out.append(id)
	return Seeded.shuffled(Seeded.rng(seed_value, "gift order"), out)


# --- Leo's trophy corner --------------------------------------------------------------------------------------

static func corner(goals: int) -> int:
	return mini(CORNER.size(), maxi(0, goals) / CORNER_EVERY)


## Where corner piece i stands (world, on the grass): two rows behind Leo's prizes, left of the goal.
static func corner_spot(i: int) -> Vector3:
	return CORNER_AT + Vector3(-1.6 * (i % 4), 0.0, -2.0 * float(i / 4))


# --- The pick row ---------------------------------------------------------------------------------------------

static func row_spots(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = ROW_X[i] if n == 3 else (i - (n - 1) * 0.5) * 2.2
		out.append(Vector3(x, ROW_Y, ROW_Z))
	return out


## How near a ball's middle must come to an orb's middle to take it.
static func catch_r() -> float:
	return PickOrbs.HIT_R * ORB_SCALE + CATCH