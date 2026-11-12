extends RefCounted
## SOFT DODGEBALL second pass (pure data + small functions; tests/dodge_ball_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first round: the park's level (one up or down; TODAY'S PARK keeps its own), how often TumTum plays a
##             warned trick, how long it is told first, how big it is and what a trick hit costs (GENTLE: nothing but
##             a boing; BRAVE / HARD: out for a moment, never as long as a ball hit).
##   GIFTS     TUMTUM'S BALL GIFTS for the runners, three offered on the pick orbs before every round from the second:
##             SQUISHY BALL (big balls, a belly hit counts one more), CURVE BALL (throws curve straight to the belly),
##             BUBBLE SHIELD (every runner's first hit just pops a bubble), SPEEDY SHOES (run faster) and BALL MAGNET
##             (grab balls from further, loose balls roll to you) - the last two open as TumTum's park gets toys.
##   TRICKS    warned by steady core/warn_rings.gd shapes on the court (each kind its own colour), never in the first
##             round, never in a round's first seconds, never two at once, the CPU giant never throws during one:
##               STOMP   a red band across the court: TumTum stomps and a wobbly wave rolls along it.
##               SHOWER  a purple circle: soft balls rain down in it for a moment.
##             Run out of it! tricks(rd, spec) is the same list on every machine for a round; problems() proves it fair
##             (told long enough for a runner in its middle to get out round the cushions, always room outside on the
##             court, a runner hit by every trick still plays most of the round).
##   SEASONS   TumTum's seasonal parks (Seeded.season): BLOSSOM PARK, SUNNY PARK (more showers), LEAFY PARK (more
##             stomps), SNOWY PARK; seasonal props behind the stage and drifting petals / leaves / snow (season.gd).
##   TOYS      every TOY_EVERY finished rounds a big toy appears in TumTum's park for good (toys.gd): a slide, a
##             swing, a seesaw, a trampoline, a roundabout, a bouncy castle (saved: rounds).
##   PICK ROW  with runners on the court: three big orbs float over the front of the court and a runner STANDS under
##             one for TV_DWELL s (running past never picks). With nobody on the court but the VR giant (CPU runners
##             fill in): three small orbs float an arm's reach in front of the giant and a hand moves into one and
##             stays DWELL s. Something already in an orb when they pop up must leave and come back. Nobody in time =
##             the middle (it glows).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const CourtGen := preload("res://games/dodge_ball/courtgen.gd")

## level: park level added; every: seconds between tricks; warn: seconds told first; stomp_w: half a stomp band's
## depth; shower_r: a shower's radius; out: seconds a trick hit puts a runner out (0: just a boing).
const MODES := {
	"gentle": {"level": -1, "every": 26.0, "warn": 3.4, "stomp_w": 1.0, "shower_r": 1.5, "out": 0.0},
	"brave": {"level": 0, "every": 19.0, "warn": 2.8, "stomp_w": 1.25, "shower_r": 1.8, "out": 1.5},
	"hard": {"level": 1, "every": 14.0, "warn": 2.4, "stomp_w": 1.5, "shower_r": 2.1, "out": 2.0},
}
const MIN_WARN := 2.0
const REACT := 0.8  # seconds a runner takes to notice a tell and start running
const RUN_SPEED := 4.8 * 0.7  # m/s a small kid really runs (main.gd SPEED, a wobbly stick)
const FIRST_T := 14.0  # no trick in a round's first seconds
const SHORT_FIRST := 3.0  # (bots: DB_TRICKS_NOW)
const MIN_GAP := 10.0  # seconds between two tricks' tells
const END_PAD := 3.0  # every trick is over this long before the round ends
const AFTER := {"stomp": 0.8, "shower": 2.2}  # seconds a trick lasts after its tell
const HIT_PAD := 0.25  # a runner's middle this near a zone's edge is still hit
const ESCAPE_PAD := 0.3  # ... and an escape lands this far outside that
const MAX_OUT_SHARE := 0.12  # hit by every trick, a runner is out at most this share of the round
const COURT_X := CourtGen.COURT_X
const COURT_Z := CourtGen.COURT_Z
const STOMP_COLOR := Color(1.0, 0.2, 0.35)  # stomp red
const SHOWER_COLOR := Color(0.55, 0.3, 1.0)  # shower purple
const KINDS: Array[String] = ["stomp", "shower"]
const KIND_PICS := {"stomp": "stomp", "shower": "ballshower"}
const KIND_NAMES := {"stomp": "STOMP!", "shower": "BALL SHOWER!"}
## Season -> park: name, trick weights (stomp, shower), drift colour, picture, TumTum's line.
const SEASONS := {
	"spring": {"name": "BLOSSOM PARK", "weights": [1.0, 1.0], "drift": Color(1.0, 0.7, 0.85), "pic": "daisy", "line": "Blossom time!"},
	"summer": {"name": "SUNNY PARK", "weights": [0.6, 1.6], "drift": Color(1.0, 0.95, 0.6), "pic": "sun", "line": "A sunny park day!"},
	"autumn": {"name": "LEAFY PARK", "weights": [1.6, 0.6], "drift": Color(0.95, 0.5, 0.15), "pic": "pumpkin", "line": "Leafy park!"},
	"winter": {"name": "SNOWY PARK", "weights": [1.0, 1.0], "drift": Color(0.97, 0.98, 1.0), "pic": "snowflake", "line": "Snowy park!"},
}
## Ball gifts: id, name, picture, a short line, a colour, toys needed.
const GIFTS: Array[Dictionary] = [
	{"id": "squishy", "name": "SQUISHY BALL", "pic": "squishball", "line": "Big squishy balls!", "color": Color(1.0, 0.5, 0.75), "unlock": 0},
	{"id": "curve", "name": "CURVE BALL", "pic": "curveball", "line": "Curvy throws!", "color": Color(0.4, 0.85, 1.0), "unlock": 0},
	{"id": "shield", "name": "BUBBLE SHIELD", "pic": "shieldbubble", "line": "Bubbles keep you safe!", "color": Color(0.6, 1.0, 0.95), "unlock": 0},
	{"id": "shoes", "name": "SPEEDY SHOES", "pic": "speedup", "line": "Zoom zoom!", "color": Color(1.0, 0.65, 0.2), "unlock": 2},
	{"id": "magnet", "name": "BALL MAGNET", "pic": "ballmagnet", "line": "Balls come to you!", "color": Color(1.0, 0.35, 0.35), "unlock": 4},
]
const SQUISHY_SCALE := 1.4  # SQUISHY BALL: balls look this much bigger ...
const SQUISHY_PTS := 1  # ... and a runner's belly hit counts this much more
const BELLY_R := 0.42  # a ball this near the belly target hits it (main.gd) ...
const CURVE_BELLY_R := 0.6  # ... with the CURVE BALL
const SHOES := 1.3  # SPEEDY SHOES: running speed x this
const PICKUP_R := 0.8  # a runner grabs a ball this near ...
const MAGNET_R := 1.6  # ... with the BALL MAGNET
const MAGNET_PULL := 1.2  # m/s loose balls roll towards the nearest runner (BALL MAGNET, within MAGNET_FAR)
const MAGNET_FAR := 4.0
## Toys: one every TOY_EVERY finished rounds (name, picture).
const TOY_EVERY := 3
const TOYS: Array[Dictionary] = [
	{"id": "slide", "name": "SLIDE", "pic": "slide"},
	{"id": "swing", "name": "SWING", "pic": "swing"},
	{"id": "seesaw", "name": "SEESAW", "pic": "seesaw"},
	{"id": "trampoline", "name": "TRAMPOLINE", "pic": "trampoline"},
	{"id": "roundabout", "name": "ROUNDABOUT", "pic": "roundabout"},
	{"id": "castle", "name": "BOUNCY CASTLE", "pic": "bouncycastle"},
]
## Where the toys stand (x, z): on the lawn beyond the side fences, past the park's things (courtgen.gd park_slot
## x = +-8.35) and inside the ring of trees and bushes (world.gd: 11.4 m and more from (0, -1)).
const TOY_SPOTS: Array[Vector2] = [Vector2(-9.8, -1.0), Vector2(9.8, -1.0), Vector2(-9.8, 2.6), Vector2(9.8, 2.6),
	Vector2(-9.8, -4.6), Vector2(9.8, -4.6)]
const TOY_SCALE := 0.7  # toys.gd builds them a bit big, then shrinks them to fit between the park and the bushes
const TOY_HALF := 0.85  # a toy's footprint half-width (at TOY_SCALE)
## The court pick row: three big orbs over the front of the court (x, z), ORB_Y above the ground.
const ROW_X: Array[float] = [-3.4, 0.0, 3.4]
const ROW_Z := -3.45
const ORB_Y := 2.1
const ORB_SCALE := 0.75
const TV_R := 0.9  # a runner's middle this near an orb's spot (across the ground) is under it ...
const TV_DWELL := 0.8  # ... for this long to pick it (running past never picks)
## The VR pick row: three small orbs an arm's reach in front of the giant's head (metres; the giant faces +Z).
const VR_X: Array[float] = [-0.3, 0.0, 0.3]
const VR_AHEAD := 0.42
const VR_BELOW := 0.3
const VR_SCALE := 0.14
const HAND_R := 0.05  # a VR grab point this near an orb's ball touches it ...
const DWELL := 0.35  # ... for this long (deliberate: a hand sweeping past never picks)
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const EMPTY_WAIT := 8.0  # nobody here who could pick at all: sooner


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 16.0))


## A round's code in a mode: its level a step up or down (TODAY'S PARK keeps its own: the same on every machine).
static func mode_code(code: int, mode: String) -> int:
	if CourtGen.daily_of(code):
		return code
	var lv := clampi(CourtGen.level_of(code) + int(mode_data(mode).level), 1, CourtGen.MAX_LEVEL)
	return CourtGen.code_of(CourtGen.seed_of(code), lv, false)


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["level", "stomp_w", "shower_r", "out"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["every", "warn"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(h.every) < MIN_GAP:
		out.append("hard: tricks closer than %.0f s" % MIN_GAP)
	if float(g.out) != 0.0:
		out.append("gentle trick hits put runners out")
	if float(h.out) >= CourtGen.OUT_TIME:
		out.append("a trick hit is as long as a ball hit")
	return out


# --- Tricks ---------------------------------------------------------------------------------------------------

## The tricks of a round rd (CourtGen.build): [{t, kind, x, z, w, warn}] by time. t: when the tell starts (round
## seconds); it goes off at t + warn and lasts AFTER[kind]. stomp: a band across the whole court at z = z of
## half-depth w. shower: a circle at (x, z) of radius w. spec: {mode, season, round (none in round 1), len (round
## seconds), first (bots: earlier, and in round 1 too)}.
static func tricks(rd: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	var first := float(spec.get("first", FIRST_T))
	if int(spec.get("round", 2)) < 2 and first >= FIRST_T:
		return out
	var mode := mode_of(String(spec.get("mode", "brave")))
	var md := mode_data(mode)
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var rlen := float(spec.get("len", CourtGen.ROUND_TIME))
	var r := Seeded.rng(int(rd.seed), "tricks %s %d %d" % [mode, int(rd.level), int(rlen)])
	var every := float(md.every)
	var t := first + (r.randf_range(0.0, every * 0.3) if first >= FIRST_T else 0.0)
	while t + float(md.warn) + 2.2 <= rlen - END_PAD:
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		if float(md.out) * (out.size() + 1) > MAX_OUT_SHARE * rlen:
			break  # (hit by every trick, a runner still plays most of the round)
		var e := {}
		for attempt in 24:
			e = _make(r, kind, t, md)
			if _where_problem(rd, e, out).is_empty():
				break
			e = {}
		if not e.is_empty():
			out.append(e)
		t += every * r.randf_range(0.85, 1.2)
	return out


static func _make(r: RandomNumberGenerator, kind: String, t: float, md: Dictionary) -> Dictionary:
	var e := {"t": snappedf(t, 0.01), "kind": kind, "warn": float(md.warn)}
	if kind == "stomp":
		var w := float(md.stomp_w)
		e.merge({"x": 0.0, "z": snappedf(r.randf_range(COURT_Z.x + w + 0.8, COURT_Z.y - w - 0.8), 0.01), "w": w}, true)
	else:
		var rad := float(md.shower_r)
		e.merge({"x": snappedf(r.randf_range(-COURT_X + rad, COURT_X - rad), 0.01),
			"z": snappedf(r.randf_range(COURT_Z.x + rad, COURT_Z.y - rad), 0.01), "w": rad}, true)
	return e


static func after(e: Dictionary) -> float:
	return float(AFTER.get(String(e.get("kind", "stomp")), 1.0))


static func span(e: Dictionary) -> float:
	return float(e.warn) + after(e)


## How far a runner's middle p (x, z) is inside trick e's zone: > 0 inside (metres past the edge), < 0 outside.
static func depth(e: Dictionary, p: Vector2) -> float:
	if String(e.kind) == "shower":
		return float(e.w) - p.distance_to(Vector2(float(e.x), float(e.z)))
	return float(e.w) - absf(p.y - float(e.z))


## Is a runner at p hit by e (HIT_PAD: their body)?
static func inside(e: Dictionary, p: Vector2, pad: float = HIT_PAD) -> bool:
	return depth(e, p) > -pad


## Can a runner stand at p (on the court, not inside a cushion)?
static func standable(rd: Dictionary, p: Vector2) -> bool:
	if absf(p.x) > COURT_X - 0.05 or p.y < COURT_Z.x + 0.05 or p.y > COURT_Z.y - 0.05:
		return false
	var q := CourtGen.push_out(rd, Vector3(p.x, 0.0, p.y))
	return Vector2(q.x, q.z).distance_to(p) < 0.01


## The nearest safe place for a runner at p (on the court, out of the cushions, ESCAPE_PAD outside the zone); p itself
## when already safe, Vector2.INF when there is none.
static func escape(rd: Dictionary, e: Dictionary, p: Vector2) -> Vector2:
	if not inside(e, p, HIT_PAD + ESCAPE_PAD):
		return p
	var need := float(e.w) + HIT_PAD + ESCAPE_PAD + 0.05
	var cands: Array = []
	if String(e.kind) == "shower":
		var c := Vector2(float(e.x), float(e.z))
		var away := (p - c).normalized() if p.distance_to(c) > 0.05 else Vector2.RIGHT
		for k in 16:
			cands.append(c + away.rotated(k * TAU / 16.0) * need)
	else:
		for dx in [0.0, -1.0, 1.0, -2.0, 2.0]:  # straight out, or a step along to get past a cushion
			cands.append(Vector2(p.x + float(dx), float(e.z) - need))
			cands.append(Vector2(p.x + float(dx), float(e.z) + need))
	var best := Vector2.INF
	for q in cands:
		var qq: Vector2 = q
		if not standable(rd, qq):
			continue
		if best == Vector2.INF or p.distance_to(qq) < p.distance_to(best):
			best = qq
	return best


## Seconds a runner needs from p to the safe place (REACT + running; a cushion in the way adds the way round it),
## INF when there is none.
static func escape_time(rd: Dictionary, e: Dictionary, p: Vector2) -> float:
	var q := escape(rd, e, p)
	if q == Vector2.INF:
		return INF
	if q == p:
		return 0.0
	return REACT + _path_len(rd, p, q) / RUN_SPEED


## A straight run, or round a cushion that sits on the line (half its circumference).
static func _path_len(rd: Dictionary, a: Vector2, b: Vector2) -> float:
	var d := a.distance_to(b)
	for c in rd.get("cushions", []):
		var cc := Vector2(float(c[0]), float(c[1]))
		var rr := float(c[2]) + CourtGen.RUNNER_R
		var ab := b - a
		var k := clampf((cc - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * k).distance_to(cc) < rr:
			d += rr * (PI - 2.0)  # (going round a circle instead of through it)
	return d


## The worst places to be when a tell starts: in its middle (for a stomp, all along it), on the court and not
## inside a cushion.
static func worst_spots(rd: Dictionary, e: Dictionary) -> Array:
	var raw: Array = []
	if String(e.kind) == "shower":
		var c := Vector2(float(e.x), float(e.z))
		raw = [c, c + Vector2(0.5, 0.0), c - Vector2(0.5, 0.0), c + Vector2(0.0, 0.5), c - Vector2(0.0, 0.5)]
	else:
		for x in [-6.0, -4.5, -3.0, -1.5, 0.0, 1.5, 3.0, 4.5, 6.0]:
			raw.append(Vector2(float(x), float(e.z)))
	return raw.filter(func(p: Vector2) -> bool: return standable(rd, p))


static func _where_problem(rd: Dictionary, e: Dictionary, earlier: Array) -> String:
	if not earlier.is_empty() and float(e.t) - float((earlier[earlier.size() - 1] as Dictionary).t) < MIN_GAP:
		return "two tricks too close together"
	var spots := worst_spots(rd, e)
	if spots.is_empty():
		return "nowhere to stand in it (all cushions)"
	for p in spots:
		if escape_time(rd, e, p) > float(e.warn):
			return "no way out in time from %s" % str(p)
	return ""


## Reasons a round's tricks are unfair (empty = fine).
static func problems(rd: Dictionary, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var first := float(spec.get("first", FIRST_T))
	var rlen := float(spec.get("len", CourtGen.ROUND_TIME))
	if int(spec.get("round", 2)) < 2 and first >= FIRST_T and not list.is_empty():
		why.append("tricks in the first round")
	var prev: Array = []
	for e in list:
		var tag := "%s at %.1f s" % [e.get("kind", "?"), float(e.get("t", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown trick %s" % str(e))
			continue
		if float(e.t) < first - 0.001:
			why.append("%s: too early in the round" % tag)
		if float(e.t) + span(e) > rlen - END_PAD + 0.001:
			why.append("%s: runs past the round's end" % tag)
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		var where := _where_problem(rd, e, prev)
		if where != "":
			why.append("%s: %s" % [tag, where])
		if String(e.kind) == "shower":  # a shower stays on the court; a stomp never fills it
			if absf(float(e.x)) + float(e.w) > COURT_X + 0.01 or float(e.z) - float(e.w) < COURT_Z.x - 0.01 or float(e.z) + float(e.w) > COURT_Z.y + 0.01:
				why.append("%s: off the court" % tag)
		elif float(e.w) * 2.0 > (COURT_Z.y - COURT_Z.x) * 0.4:
			why.append("%s: a stomp band too deep" % tag)
		prev.append(e)
	if float(md.out) * list.size() > MAX_OUT_SHARE * rlen:
		why.append("hit by every trick a runner is out %.0f s of %.0f" % [float(md.out) * list.size(), rlen])
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.z), float(e.w), float(e.warn), float(e.t)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 6 else {"kind": String(a[0]), "x": float(a[1]), "z": float(a[2]), "w": float(a[3]),
		"warn": float(a[4]), "t": float(a[5])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(toys_n: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if toys_n >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are
## others (the same on every machine for a seed).
static func gift_choices(toys_n: int, last: String, seed_value: int) -> Array:
	var un := unlocked(toys_n)
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


static func run_speed(gift_id: String) -> float:
	return SHOES if gift_id == "shoes" else 1.0


static func pickup_r(gift_id: String) -> float:
	return MAGNET_R if gift_id == "magnet" else PICKUP_R


static func belly_r(gift_id: String, runner_throw: bool) -> float:
	return CURVE_BELLY_R if gift_id == "curve" and runner_throw else BELLY_R


static func belly_bonus(gift_id: String) -> int:
	return SQUISHY_PTS if gift_id == "squishy" else 0


static func ball_scale(gift_id: String) -> float:
	return SQUISHY_SCALE if gift_id == "squishy" else 1.0


## Seconds a trick hit puts a runner out (a BUBBLE SHIELD pops instead: main.gd).
static func trick_out(mode: String) -> float:
	return float(mode_data(mode).out)


# --- Toys -----------------------------------------------------------------------------------------------------

static func toys(rounds: int) -> int:
	return mini(TOYS.size(), maxi(0, rounds) / TOY_EVERY)


# --- The pick rows --------------------------------------------------------------------------------------------

## The court orbs' places in the world (their middles), for n orbs.
static func row_spots(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = ROW_X[i] if n == 3 else lerpf(ROW_X[0], ROW_X[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, ORB_Y, ROW_Z))
	return out


## The VR orbs' places: an arm's reach in front of the giant's head (the giant faces +Z on the stage).
static func vr_spots(head: Vector3, n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = VR_X[i] if n == 3 else lerpf(VR_X[0], VR_X[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(head.x + x, head.y - VR_BELOW, head.z + VR_AHEAD))
	return out


## Which court orb a runner at p stands under (-1 none).
static func under(spots: Array, p: Vector3) -> int:
	var best := -1
	var bd := TV_R
	for i in spots.size():
		var s: Vector3 = spots[i]
		var d := Vector2(s.x - p.x, s.z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## A court orb's radius in the world.
static func orb_r(vr: bool) -> float:
	return PickOrbs.BALL_R * (VR_SCALE if vr else ORB_SCALE)
