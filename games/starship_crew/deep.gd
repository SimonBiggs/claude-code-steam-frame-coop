extends RefCounted
## STARSHIP CREW second pass (pure data + small functions; tests/starship_crew_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first seeded trip's first mission: how hard the missions are (a tier up or down), how often a warned
##             space surprise comes, how long it is told first, how big it is, and what a hit costs (GENTLE: nothing
##             but a wobble; BRAVE / HARD: one star off the dashboard and a dizzy ship for a moment).
##   GIFTS     CAPTAIN WHISKERS' SHIP MODULES, three offered on the pick orbs before every mission from the second of a
##             seeded trip: BUBBLE SHIELD (surprises and rocks bounce off), TRACTOR BEAM (rings pull the ship in from
##             further), TURBO (the ship slides faster), MEGA LASER (much easier zaps) and STAR BOOST (rings and zaps
##             give an extra star) - the last two open as the space station grows. A module lasts the whole mission.
##   SURPRISES warned by steady core/warn_rings.gd shapes STANDING UP in space ahead of the ship (each kind its own
##             colour), never on the lessons trip, never in a lap's first seconds, never two at once:
##               ROCK STREAM  an orange band (up-and-down or side-to-side): a stream of space rocks pours through it.
##               SOLAR FLARE  a pink circle: a hot flash of sunlight blasts through it.
##             Steer the ship out of it! hazards(plan, spec) is the same list on every machine for a mission lap;
##             problems() proves it fair (told long enough for the ship to slide out from its middle, always room to
##             escape inside space, never over a ring the pilot is flying for, and a pilot who is hit by every surprise
##             still fills the dashboard from the rings alone).
##   SEASONS   seasonal STAR SECTORS (Seeded.season): the spring NEBULA GARDEN, the summer SUN SECTOR (more flares),
##             the autumn COMET SECTOR (more rock streams) and the winter ICE SECTOR; each has its own drifting space
##             dust and floating sector islands with seasonal props (core/season_kit.gd).
##   CREW      every CREW_EVERY finished missions a new CREW FRIEND (a puppy, a robot, an alien ...) joins and flies in
##             a little pod beside the ship for good (saved, crew.gd).
##   PICK ROW  three big orbs float in space just ahead of the ship, above it. The pilot STEERS the ship until one sits
##             straight ahead and holds it there a moment (a ship already lined up with one when they open must move off
##             and come back); a gunner ZAPS one with their crosshair. Nobody in time = the middle (it glows).
## Space coordinates as space.gd: x/y absolute (the ship's sideways place is `off`), z ahead (negative).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const MissionGen := preload("res://games/starship_crew/missiongen.gd")
const Space := preload("res://games/starship_crew/space.gd")

## tier: mission tier added; every: seconds between surprises; warn: seconds told first; stream_w: half a rock stream's
## width; flare_r: a flare's radius; lose: stars a hit knocks off; dizzy: seconds a hit slows the steering.
const MODES := {
	"gentle": {"tier": -1, "every": 24.0, "warn": 3.4, "stream_w": 1.3, "flare_r": 1.9, "lose": 0, "dizzy": 0.8},
	"brave": {"tier": 0, "every": 17.0, "warn": 2.8, "stream_w": 1.6, "flare_r": 2.3, "lose": 1, "dizzy": 1.2},
	"hard": {"tier": 1, "every": 13.0, "warn": 2.4, "stream_w": 1.9, "flare_r": 2.7, "lose": 1, "dizzy": 1.6},
}
const MIN_WARN := 2.0
const REACT := 0.8  # seconds a pilot takes to notice a tell and start steering
const STEER := MissionGen.STEER  # m/s sideways (main.gd STEER_SPEED)
const ACCEL := 9.0  # m/s/s (main.gd: vel.move_toward(..., 9.0 * delta))
const FIRST_T := 12.0  # no surprise in a lap's first seconds (last lap's rings are still arriving)
const SHORT_FIRST := 3.0  # (bots: SC_SURPRISES_NOW)
const MIN_GAP := 9.0  # seconds between two surprises' tells
const AFTER := 2.5  # seconds a surprise lasts after its tell (the rocks pour / the flare blasts)
const SHIP_PAD := 0.6  # the ship's middle this near a zone's edge is still hit
const ESCAPE_PAD := 0.3  # ... and an escape lands this far outside that
const RING_CLEAR := 0.5  # a ring arriving during a surprise has its middle at least this far outside the zone (+ pad)
const TELL_Z := -22.0  # where a tell stands ahead of the ship (world z)
const STREAM_COLOR := Color(1.0, 0.55, 0.12)  # rock-stream orange
const FLARE_COLOR := Color(1.0, 0.3, 0.6)  # solar-flare pink
const INK := Color(0.06, 0.05, 0.12)  # the tells' dark edges (they read on a bright planet too: palette.gd rim)
const INK_W := 0.22
const KINDS: Array[String] = ["stream", "flare"]
const KIND_PICS := {"stream": "meteor", "flare": "solarflare"}
const KIND_NAMES := {"stream": "ROCK STREAM!", "flare": "SOLAR FLARE!"}
## Season -> sector: name, surprise weights (stream, flare), dust colour, picture, Captain Whiskers' line.
const SEASONS := {
	"spring": {"name": "NEBULA GARDEN", "weights": [1.0, 1.0], "drift": Color(1.0, 0.6, 0.85), "pic": "daisy", "line": "The nebula garden!"},
	"summer": {"name": "SUN SECTOR", "weights": [0.6, 1.6], "drift": Color(1.0, 0.85, 0.4), "pic": "sun", "line": "The hot sun sector!"},
	"autumn": {"name": "COMET SECTOR", "weights": [1.7, 0.6], "drift": Color(1.0, 0.55, 0.2), "pic": "meteor", "line": "The comet sector!"},
	"winter": {"name": "ICE SECTOR", "weights": [1.3, 0.5], "drift": Color(0.85, 0.95, 1.0), "pic": "snowflake", "line": "The icy star sector!"},
}
## Ship modules: id, name, picture, a short line, a colour, station parts needed.
const GIFTS: Array[Dictionary] = [
	{"id": "shield", "name": "BUBBLE SHIELD", "pic": "shieldbubble", "line": "Bonk-proof bubble!", "color": Color(0.55, 0.95, 1.0), "unlock": 0},
	{"id": "tractor", "name": "TRACTOR BEAM", "pic": "tractorbeam", "line": "Rings come to us!", "color": Color(0.45, 1.0, 0.5), "unlock": 0},
	{"id": "turbo", "name": "TURBO", "pic": "boosters", "line": "Zoom zoom!", "color": Color(1.0, 0.6, 0.2), "unlock": 0},
	{"id": "mega", "name": "MEGA LASER", "pic": "megalaser", "line": "Giant zaps!", "color": Color(1.0, 0.4, 0.7), "unlock": 2},
	{"id": "boost", "name": "STAR BOOST", "pic": "star", "line": "Extra stars!", "color": Color(1.0, 0.85, 0.25), "unlock": 4},
]
const PULL_R := 4.5  # rings pull the ship in from this near (across) ...
const PULL := 0.9  # ... this fast (share a second)
const PULL_Z := -25.0  # ... once this close
const TRACTOR_R := 7.0  # TRACTOR BEAM
const TRACTOR_PULL := 1.7
const TRACTOR_Z := -40.0
const TURBO := 1.5  # TURBO: steering speed and grip x this
const ZAP_TOL := 0.14  # a zap this near a target (screen) hits ...
const MEGA_TOL := 0.26  # ... with the MEGA LASER
## Crew friends: one every CREW_EVERY finished missions (name, picture, colour of their pod).
const CREW_EVERY := 3
const CREW: Array[Dictionary] = [
	{"id": "puppy", "name": "PUPPY", "pic": "puppy", "color": Color(0.85, 0.6, 0.35)},
	{"id": "robot", "name": "ROBOT", "pic": "robot", "color": Color(0.7, 0.78, 0.9)},
	{"id": "alien", "name": "ALIEN", "pic": "alien", "color": Color(0.45, 0.95, 0.45)},
	{"id": "penguin", "name": "PENGUIN", "pic": "penguin", "color": Color(0.25, 0.3, 0.4)},
	{"id": "owl", "name": "OWL", "pic": "owl", "color": Color(0.7, 0.5, 0.3)},
	{"id": "frog", "name": "FROG", "pic": "frog", "color": Color(0.35, 0.8, 0.3)},
	{"id": "bunny", "name": "BUNNY", "pic": "bunny", "color": Color(0.95, 0.92, 0.95)},
	{"id": "kitten", "name": "KITTEN", "pic": "kitten", "color": Color(0.6, 0.6, 0.65)},
]
## Where the crew pods fly (world, beside the ship; the ship never moves): left and right in turn, clear of the wing
## turrets, the TV camera's edges (a Deck is narrower than a TV) and the pilot's view ahead.
const CREW_SPOTS: Array[Vector3] = [Vector3(-5.4, 1.5, -2.6), Vector3(5.4, 1.5, -2.6), Vector3(-5.0, -0.6, 0.6), Vector3(5.0, -0.6, 0.6),
	Vector3(-7.6, 4.2, -7.5), Vector3(7.6, 4.2, -7.5), Vector3(-9.0, 0.4, -10.0), Vector3(9.0, 0.4, -10.0)]
const CREW_SCALE := 0.8
## The pick row: three big orbs in space ahead of the ship, above its usual line (space x, y; world z).
const ROW_X: Array[float] = [-4.6, 0.0, 4.6]
const ROW_Y := 2.4
const ROW_Z := -12.0
const ORB_SCALE := 1.7
const LINE_R := 1.3  # the ship's middle this near an orb (across) is lined up with it
const DWELL := 0.7  # seconds it must stay lined up (sliding past never picks)
const ORB_PULL := 0.6  # a lined-up orb gently holds the ship (share a second)
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const EMPTY_WAIT := 8.0  # nobody here who could pick at all: sooner
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 16.0))


## A mission's tier in a mode (TODAY'S MISSION keeps its own tier: the same on every machine).
static func tier(base: int, mode: String, daily: bool = false) -> int:
	return base if daily else clampi(base + int(mode_data(mode).tier), 0, MissionGen.TIERS - 1)


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["tier", "stream_w", "flare_r", "lose", "dizzy"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["every", "warn"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(h.every) < MIN_GAP:
		out.append("hard: surprises closer than %.0f s" % MIN_GAP)
	if int(g.lose) != 0:
		out.append("gentle hits cost stars")
	return out


# --- Surprises ------------------------------------------------------------------------------------------------

## The surprises of a mission lap `plan` (missiongen.gd generate()): [{t, kind, x, y, w, vert, warn}] by time. t: when
## the tell starts (lap seconds); it goes off at t + warn and lasts AFTER. stream: a band through (x, y) of half-width w,
## up-and-down (vert: all y, |x - cx| < w) or side-to-side (|y - cy| < w). flare: a circle at (x, y) of radius w.
## spec: {mode, season, trip (none on the lessons trip 0), first (bots: earlier)}.
static func hazards(plan: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	if int(spec.get("trip", 1)) < 1:
		return out
	var md := mode_data(String(spec.get("mode", "brave")))
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var r := Seeded.rng(int(plan.seed), "surprises %s %d %d" % [mode_of(String(spec.get("mode", "brave"))), int(plan.tier), int(plan.lap)])
	var every := float(md.every)
	var first := float(spec.get("first", FIRST_T))
	var t := first + (r.randf_range(0.0, every * 0.3) if first >= FIRST_T else 0.0)
	var rings := ring_arrivals(plan)
	while t + float(md.warn) + AFTER <= float(plan.len) - 0.5:
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		var e := {}
		for attempt in 20:
			e = _make(r, kind, t, md)
			if _where_problem(e, out, rings).is_empty():
				break
			e = {}
		if not e.is_empty():
			out.append(e)
		t += every * r.randf_range(0.85, 1.2)
	return out


static func _make(r: RandomNumberGenerator, kind: String, t: float, md: Dictionary) -> Dictionary:
	var e := {"t": snappedf(t, 0.01), "kind": kind, "warn": float(md.warn), "vert": 0}
	if kind == "stream":
		var vert := r.randf() < 0.6
		var w := float(md.stream_w)
		var c := r.randf_range(-Space.LIMIT.x + 1.5, Space.LIMIT.x - 1.5) if vert else r.randf_range(-Space.LIMIT.y + 1.2, Space.LIMIT.y - 1.2)
		e.merge({"x": snappedf(c, 0.01) if vert else 0.0, "y": 0.0 if vert else snappedf(c, 0.01), "w": w, "vert": 1 if vert else 0}, true)
	else:
		var rad := float(md.flare_r)
		e.merge({"x": snappedf(r.randf_range(-Space.LIMIT.x + 1.0, Space.LIMIT.x - 1.0), 0.01),
			"y": snappedf(r.randf_range(-Space.LIMIT.y + 0.5, Space.LIMIT.y - 0.5), 0.01), "w": rad}, true)
	return e


## How far the ship's middle p (space x, y) is inside surprise e's zone: > 0 inside (metres past the edge), < 0 outside.
static func depth(e: Dictionary, p: Vector2) -> float:
	if String(e.kind) == "flare":
		return float(e.w) - p.distance_to(Vector2(float(e.x), float(e.y)))
	if int(e.vert) == 1:
		return float(e.w) - absf(p.x - float(e.x))
	return float(e.w) - absf(p.y - float(e.y))


## Is the ship's middle p hit by e (SHIP_PAD: its nose and wings)?
static func inside(e: Dictionary, p: Vector2, pad: float = SHIP_PAD) -> bool:
	return depth(e, p) > -pad


## The nearest safe place for a ship at p (inside space, ESCAPE_PAD outside the hit zone); p itself when already safe.
static func escape(e: Dictionary, p: Vector2) -> Vector2:
	if not inside(e, p, SHIP_PAD + ESCAPE_PAD):
		return p
	var best := Vector2.INF
	var need := float(e.w) + SHIP_PAD + ESCAPE_PAD + 0.05
	var cands: Array = []
	if String(e.kind) == "flare":
		var c := Vector2(float(e.x), float(e.y))
		var away := (p - c).normalized() if p.distance_to(c) > 0.05 else Vector2.RIGHT
		for k in 16:
			cands.append(c + away.rotated(k * TAU / 16.0) * need)
	else:
		var lim := Space.LIMIT - Vector2(0.06, 0.06)
		var along := p.clamp(-lim, lim)  # (along the band the ship stays where it is, inside space)
		if int(e.vert) == 1:
			cands = [Vector2(float(e.x) - need, along.y), Vector2(float(e.x) + need, along.y)]
		else:
			cands = [Vector2(along.x, float(e.y) - need), Vector2(along.x, float(e.y) + need)]
	for q in cands:
		var qq: Vector2 = q
		if absf(qq.x) > Space.LIMIT.x - 0.05 or absf(qq.y) > Space.LIMIT.y - 0.05:
			continue
		if best == Vector2.INF or p.distance_to(qq) < p.distance_to(best):
			best = qq
	return best


## Seconds a pilot needs from p to the safe place (REACT + a standing start), INF when there is none.
static func escape_time(e: Dictionary, p: Vector2) -> float:
	var q := escape(e, p)
	if q == Vector2.INF:
		return INF
	if q == p:
		return 0.0
	return REACT + p.distance_to(q) / STEER + STEER / (2.0 * ACCEL)


## The worst place to be when a tell starts: its middle (and, for a stream, along it at the edges of space).
static func worst_spots(e: Dictionary) -> Array:
	var c := Vector2(float(e.x), float(e.y))
	if String(e.kind) == "flare":
		return [c]
	if int(e.vert) == 1:
		return [Vector2(c.x, 0.0), Vector2(c.x, Space.LIMIT.y), Vector2(c.x, -Space.LIMIT.y)]
	return [Vector2(0.0, c.y), Vector2(Space.LIMIT.x, c.y), Vector2(-Space.LIMIT.x, c.y)]


static func span(e: Dictionary) -> float:
	return float(e.warn) + AFTER


## When each of a lap's rings reaches the ship (lap seconds) and where: [[t, Vector2]].
static func ring_arrivals(plan: Dictionary) -> Array:
	var out: Array = []
	for ev in plan.events:
		if int(ev[1]) == Space.RING:
			out.append([float(ev[0]) + -Space.SPAWN_Z / float(plan.speed), Vector2(float(ev[2]), float(ev[3]))])
	return out


static func _where_problem(e: Dictionary, earlier: Array, rings: Array) -> String:
	if not earlier.is_empty() and float(e.t) - float((earlier[earlier.size() - 1] as Dictionary).t) < MIN_GAP:
		return "two surprises too close together"
	for p in worst_spots(e):
		if escape_time(e, p) > float(e.warn):
			return "no way out in time from %s" % str(p)
	var t0 := float(e.t)
	var t1 := t0 + span(e) + 0.5
	for ra in rings:
		if float(ra[0]) >= t0 and float(ra[0]) <= t1 and inside(e, ra[1], SHIP_PAD + RING_CLEAR):
			return "over a ring arriving at %.1f s" % float(ra[0])
	return ""


## Reasons a lap's surprises are unfair (empty = fine).
static func problems(plan: Dictionary, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var first := float(spec.get("first", FIRST_T))
	if int(spec.get("trip", 1)) < 1 and not list.is_empty():
		why.append("surprises on the lessons trip")
	var rings := ring_arrivals(plan)
	var prev: Array = []
	for e in list:
		var tag := "%s at %.1f s" % [e.get("kind", "?"), float(e.get("t", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown surprise %s" % str(e))
			continue
		if float(e.t) < first - 0.001:
			why.append("%s: too early in the lap" % tag)
		if float(e.t) + span(e) > float(plan.len) - 0.5 + 0.001:
			why.append("%s: runs past the lap" % tag)
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		var where := _where_problem(e, prev, rings)
		if where != "":
			why.append("%s: %s" % [tag, where])
		# Space always has room outside it (a stream never fills the sky; a flare stays inside space).
		var c := Vector2(float(e.x), float(e.y))
		if absf(c.x) > Space.LIMIT.x or absf(c.y) > Space.LIMIT.y:
			why.append("%s: outside space" % tag)
		prev.append(e)
	# A pilot hit by every surprise still fills the dashboard from the rings of one lap.
	var lose := int(md.lose) * list.size()
	if rings.size() * 2 - lose < MissionGen.NEED:
		why.append("hit by every surprise, the rings alone can't fill the dashboard (%d rings, %d lost)" % [rings.size(), lose])
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.y), float(e.w), int(e.vert), float(e.warn), float(e.t)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 7 else {"kind": String(a[0]), "x": float(a[1]), "y": float(a[2]), "w": float(a[3]), "vert": int(a[4]),
		"warn": float(a[5]), "t": float(a[6])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(parts: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if parts >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked modules: the newest unlock always among them, not the last one again when there are
## others (the same on every machine for a seed).
static func gift_choices(parts: int, last: String, seed_value: int) -> Array:
	var un := unlocked(parts)
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


static func steer_speed(gift_id: String) -> float:
	return STEER * (TURBO if gift_id == "turbo" else 1.0)


static func accel(gift_id: String) -> float:
	return ACCEL * (TURBO if gift_id == "turbo" else 1.0)


static func pull_r(gift_id: String) -> float:
	return TRACTOR_R if gift_id == "tractor" else PULL_R


static func pull(gift_id: String) -> float:
	return TRACTOR_PULL if gift_id == "tractor" else PULL


static func pull_z(gift_id: String) -> float:
	return TRACTOR_Z if gift_id == "tractor" else PULL_Z


static func zap_tol(gift_id: String) -> float:
	return MEGA_TOL if gift_id == "mega" else ZAP_TOL


static func extra_star(gift_id: String) -> int:
	return 1 if gift_id == "boost" else 0


## Stars a hit knocks off (the BUBBLE SHIELD: none).
static func lose(mode: String, gift_id: String) -> int:
	return 0 if gift_id == "shield" else int(mode_data(mode).lose)


static func dizzy(mode: String, gift_id: String) -> float:
	return 0.0 if gift_id == "shield" else float(mode_data(mode).dizzy)


# --- Crew friends ---------------------------------------------------------------------------------------------

static func crew(missions: int) -> int:
	return mini(CREW.size(), maxi(0, missions) / CREW_EVERY)


# --- The pick row ---------------------------------------------------------------------------------------------

## The orbs' places in space (x, y) for n orbs.
static func row_spots(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = ROW_X[i] if n == 3 else lerpf(ROW_X[0], ROW_X[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector2(x, ROW_Y))
	return out


## Which orb the ship at off is lined up with (-1 none).
static func lined_up(spots: Array, off: Vector2) -> int:
	var best := -1
	var bd := LINE_R
	for i in spots.size():
		var d := off.distance_to(spots[i])
		if d < bd:
			bd = d
			best = i
	return best


## An orb's radius in the world.
static func orb_r() -> float:
	return PickOrbs.HIT_R * ORB_SCALE