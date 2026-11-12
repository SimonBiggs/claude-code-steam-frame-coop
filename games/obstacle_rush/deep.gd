extends RefCounted
## OBSTACLE RUSH second pass (pure data + small functions; tests/obstacle_rush_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked on the pick orbs once a session before the first
##             seeded course: the course tier (one down / up; TODAY'S COURSE keeps its own), how many of Coach Jelly's
##             warned surprises a course has, how long each is told first, how big it is and what it does to a runner
##             it catches (GENTLE: a little hop and slow wading; BRAVE / HARD: a comical tumble back, deeper water).
##   GIFTS     COACH JELLY'S GIFTS for the runners, three offered on the pick orbs before every course from a show's
##             second: SPRING SHOES (big jumps), GLIDE CAPE (float down slowly), STAR MAGNET (grab stars from far
##             away), then BUBBLE (the first bonk just pops it) and ZOOM SHOES (run faster) as medals come in.
##   SURPRISES warned by steady core/warn_rings.gd bands across the course (each kind its own colour), never on the
##             lessons, never on a show's first course, one at a time, each on plain floor away from every obstacle,
##             the start and the flag. Coach Jelly starts the tell when a runner comes near:
##               LOG     an orange band: a big log on ropes swings through it.
##               WATER   a blue band: water rises there for a moment (runners wade slowly; BRAVE / HARD splash back).
##             hazards(c, spec) is the same list on every machine for a course; problems() proves it fair (told long
##             enough for a small kid standing in its middle to run out either way, on solid floor, no obstacle in it).
##   SEASONS   seasonal courses (Seeded.season): BLOSSOM RUN, SUNNY RUN (more water), LEAFY RUN (more logs), SNOWY RUN;
##             core/season_kit.gd props round the table and drifting petals / leaves / snow (season.gd).
##   MEDALS    every show finished hangs a medal (its mode's colour) in COACH JELLY'S MEDAL HALL beside the course for
##             good (hall.gd; saved: medals). Gifts open as it fills.
##   PICK ROW  with runners on the course: three big orbs float over the start, across the course just in front of
##             the start line, and a runner STANDS under one for TV_DWELL s (running past never picks; nobody can run
##             on into the course while the orbs are up: FENCE). With nobody running but the VR giant (CPU runners
##             fill in): three small orbs float an arm's reach in front of the giant and a hand moves into one and
##             stays DWELL s. Nobody in time = the middle (it glows).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const CourseGen := preload("res://games/obstacle_rush/coursegen.gd")
const Runner := preload("res://games/obstacle_rush/runner.gd")
const RunnerLook := preload("res://games/obstacle_rush/runner_look.gd")

## tier: course tier added; per_span: most surprises on one stretch of plain floor; count: most surprises a course; warn: seconds told first; log_w / water_w: half a band's
## width; hit: how hard a surprise knocks a runner back (0: just a hop); wade: running speed in the water (x).
const MODES := {
	"gentle": {"tier": -1, "per_span": 1, "count": 1, "warn": 3.4, "log_w": 0.55, "water_w": 0.7, "hit": 0.0, "wade": 0.65},
	"brave": {"tier": 0, "per_span": 1, "count": 2, "warn": 2.8, "log_w": 0.65, "water_w": 0.8, "hit": 0.7, "wade": 0.5},
	"hard": {"tier": 1, "per_span": 2, "count": 3, "warn": 2.4, "log_w": 0.65, "water_w": 0.8, "hit": 1.0, "wade": 0.4},
}
const MIN_WARN := 2.0
const REACT := 0.8  # seconds a runner takes to notice a tell and start running
const KID_SPEED := Runner.RUN_SPEED * 0.7  # m/s a small kid really runs
const HIT_PAD := 0.25  # a runner's middle this near a band's edge is still caught (their body)
const ESCAPE_PAD := 0.3  # ... and an escape lands this far outside that
const AFTER := {"log": 1.6, "water": 2.6}  # seconds a surprise lasts after its tell
const TRIGGER := 6.0  # the tell starts when a runner comes this near the band ...
const FIRST_T := 2.5  # ... never in a course's first seconds (the whistle, the gift's card)
const WAIT_GAP := 1.5  # seconds between one surprise ending and the next tell
const START_CLEAR := 3.4  # no band this near the start line (the pick row, the start)
const FINISH_CLEAR := 1.6  # ... or the flag
const OBSTACLE_PAD := 0.5  # ... or an obstacle
const BAND_ROOM := 0.4  # solid floor beyond each side of a band
const Y_REACH := 1.3  # a runner this far above a band's floor (a hop) is still in it
const WAIT_NEAR := 0.6  # CPU runners and bots wait this far before a told band ...
const WAIT_FAR := 2.4  # ... when they are no further than this
const LOG_COLOR := Color(1.0, 0.5, 0.1)  # log orange
const WATER_COLOR := Color(0.12, 0.32, 1.0)  # water blue
const KINDS: Array[String] = ["log", "water"]
const KIND_PICS := {"log": "swinglog", "water": "risingwater"}
const KIND_NAMES := {"log": "SWINGING LOG!", "water": "RISING WATER!"}
## Season -> course: name, surprise weights (log, water), drift colour, picture, Coach Jelly's line.
const SEASONS := {
	"spring": {"name": "BLOSSOM RUN", "weights": [1.0, 1.0], "drift": Color(1.0, 0.7, 0.85), "pic": "daisy", "line": "Blossom run!"},
	"summer": {"name": "SUNNY RUN", "weights": [0.6, 1.6], "drift": Color(1.0, 0.95, 0.6), "pic": "sun", "line": "A sunny run!"},
	"autumn": {"name": "LEAFY RUN", "weights": [1.6, 0.6], "drift": Color(0.95, 0.5, 0.15), "pic": "pumpkin", "line": "Leafy run!"},
	"winter": {"name": "SNOWY RUN", "weights": [1.0, 1.0], "drift": Color(0.97, 0.98, 1.0), "pic": "snowflake", "line": "Snowy run!"},
}
## Runner gifts: id, name, picture, a short line, a colour, medals needed.
const GIFTS: Array[Dictionary] = [
	{"id": "springs", "name": "SPRING SHOES", "pic": "springshoes", "line": "Big bouncy jumps!", "color": Color(0.4, 0.9, 0.5), "unlock": 0},
	{"id": "cape", "name": "GLIDE CAPE", "pic": "glidecape", "line": "Float like a leaf!", "color": Color(0.75, 0.45, 1.0), "unlock": 0},
	{"id": "magnet", "name": "STAR MAGNET", "pic": "starmagnet", "line": "Stars come to you!", "color": Color(1.0, 0.35, 0.35), "unlock": 0},
	{"id": "bubble", "name": "BUBBLE", "pic": "shieldbubble", "line": "A bubble keeps you safe!", "color": Color(0.6, 1.0, 0.95), "unlock": 2},
	{"id": "zoom", "name": "ZOOM SHOES", "pic": "speedup", "line": "Zoom zoom!", "color": Color(1.0, 0.65, 0.2), "unlock": 4},
]
const SPRING_JUMP := 1.2  # SPRING SHOES: jump speed x this ...
const SPRING_AIR := 0.82  # ... and a little slower through the air (a high jump, not a longer one)
const GLIDE_FALL := 0.45  # GLIDE CAPE: gravity x this while falling ...
const GLIDE_MAX_FALL := 6.0  # ... and never falling faster than this ...
const GLIDE_AIR := 0.78  # ... and a little slower through the air (floaty, not further)
const STAR_R := CourseGen.STAR_R  # a runner grabs a star this near ...
const MAGNET_R := 2.4  # ... with the STAR MAGNET
const ZOOM := 1.2  # ZOOM SHOES: running speed x this
## The medal hall: one medal per show finished; a trophy on top every TROPHY_EVERY medals.
const HALL_SHOWN := 48  # medals hung (the newest; the count keeps going): two boards of HALL_ROW x 3 (hall.gd)
const HALL_ROW := 8
const TROPHY_EVERY := 8
const MEDAL_METAL := {"gentle": "bronze", "brave": "silver", "hard": "gold"}  # (the ribbon is the mode's own colour)
const METALS := {"bronze": Color(0.85, 0.55, 0.3), "silver": Color(0.82, 0.86, 0.92), "gold": Color(1.0, 0.82, 0.25)}
## The start pick row: three big orbs across the course (z), AHEAD m past the start line, ORB_Y over the start floor.
const ROW_Z: Array[float] = [-2.0, 0.0, 2.0]
const ROW_AHEAD := 1.1
const ORB_Y := 2.3
const ORB_SCALE := 0.75
const FENCE := 1.8  # runners stay this near the start line while the orbs are up
const TV_R := 0.7  # a runner's middle this near an orb's spot (across the floor) is under it ...
const TV_DWELL := 0.8  # ... for this long to pick it (running past never picks)
## The VR pick row: three small orbs an arm's reach in front of the giant's head (real metres x VR_S, the giant's world
## scale: giant.gd S; the giant faces -Z, so its left is -X: GENTLE on the left as on the TV), just under eye level.
const VR_S := 10.0
const VR_X: Array[float] = [-0.3, 0.0, 0.3]
const VR_AHEAD := 0.42
const VR_BELOW := 0.14
const VR_SCALE := 0.14 * VR_S
const VR_CLEAR := 0.02  # (m) the orbs stay this far in front of the course's near edge
const HAND_R := 0.05 * VR_S  # a VR grab point this near an orb's ball touches it ...
const DWELL := 0.35  # ... for this long (deliberate: a hand sweeping past never picks)
const ROW_WAIT := {"mode": 20.0, "gift": 14.0}  # nobody took one: the middle
const EMPTY_WAIT := 7.0  # nobody here who could pick at all: sooner


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 14.0))


## A course recipe (story.gd recipe) in a mode: a seeded course's tier a step up or down (lessons and TODAY'S COURSE
## keep their own: the same on every machine).
static func moded(rec: Dictionary, mode: String) -> Dictionary:
	if String(rec.get("k", "")) != "gen":
		return rec
	var out := rec.duplicate()
	out["tier"] = clampi(int(rec.get("tier", 0)) + int(mode_data(mode).tier), 0, CourseGen.tier_count() - 1)
	return out


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["tier", "per_span", "count", "log_w", "water_w", "hit"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["warn", "wade"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(g.hit) != 0.0:
		out.append("gentle surprises knock runners over")
	if float(h.hit) > 1.0:
		out.append("a surprise knocks harder than a ball")
	if float(h.wade) < 0.3:
		out.append("hard water nearly stops a runner")
	return out


# --- Surprises ------------------------------------------------------------------------------------------------

## The plain floor where a band may go: [[x0, x1, y], ...] (away from the start, the flag, every obstacle and pad).
static func free_spans(c: Dictionary) -> Array:
	var out: Array = []
	var lo := float(c.start_x) + START_CLEAR
	var hi := float(c.finish_x) - FINISH_CLEAR
	var cuts: Array = []
	for o in c.obstacles:
		cuts.append([float(o[0]) - OBSTACLE_PAD, float(o[1]) + OBSTACLE_PAD])
	for p in c.pads:
		cuts.append([(p as Vector3).x - CourseGen.PAD_R - OBSTACLE_PAD, (p as Vector3).x + CourseGen.PAD_R + OBSTACLE_PAD])
	for d in c.discs:
		cuts.append([float(d[0]) - float(d[2]) - OBSTACLE_PAD, float(d[0]) + float(d[2]) + OBSTACLE_PAD])
	for w in c.walls:
		cuts.append([float(w.x) - 0.3 - OBSTACLE_PAD, float(w.x) + 0.3 + OBSTACLE_PAD])
	for f in c.floors:
		var spans: Array = [[maxf(float(f[0]) + 0.3, lo), minf(float(f[1]) - 0.3, hi)]]
		for cut in cuts:
			var next: Array = []
			for s in spans:
				if float(cut[1]) <= float(s[0]) or float(cut[0]) >= float(s[1]):
					next.append(s)
					continue
				if float(cut[0]) > float(s[0]):
					next.append([float(s[0]), float(cut[0])])
				if float(cut[1]) < float(s[1]):
					next.append([float(cut[1]), float(s[1])])
			spans = next
		for s in spans:
			if float(s[1]) - float(s[0]) > 0.5:
				out.append([float(s[0]), float(s[1]), float(f[2])])
	return out


## The surprises of a course c (CourseGen.make): [{kind, x, y, w, warn}] along the course. spec: {mode, season,
## course (index in the show: none on 0), first (bots / What's New: on the first course too)}. None on the lessons.
static func hazards(c: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	if String(c.get("kind", "")) == "lesson" or c.has("fallback"):
		return out
	if int(spec.get("course", 1)) < 1 and not bool(spec.get("first", false)):
		return out
	var mode := mode_of(String(spec.get("mode", "brave")))
	var md := mode_data(mode)
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var r := Seeded.rng(int(c.get("seed", 1)), "surprises %s %d %d" % [mode, int(c.get("tier", 0)), int(spec.get("course", 1))])
	var spans := Seeded.shuffled(r, free_spans(c))
	for s in spans:
		var lo := float(s[0])  # (bands on one stretch go one after another, each with its room round it)
		for n in int(md.per_span):
			if out.size() >= int(md.count):
				break
			var first: String = KINDS[Seeded.weighted(r, weights)]
			var placed := false
			for kind in [first, "log" if first == "water" else "water"]:
				var w := float(md[kind + "_w"])
				var room := float(s[1]) - lo - 2.0 * (w + BAND_ROOM)
				if room < 0.0:
					continue
				var x := snappedf(lo + w + BAND_ROOM + r.randf() * minf(room, 1.0 if int(md.per_span) > 1 else room), 0.01)
				x = clampf(x, lo + w + BAND_ROOM, float(s[1]) - w - BAND_ROOM)
				out.append({"kind": kind, "x": x, "y": float(s[2]), "w": w, "warn": float(md.warn)})
				lo = x + w + BAND_ROOM + 0.01
				placed = true
				break
			if not placed:
				break
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) < float(b.x))
	return out


static func after(e: Dictionary) -> float:
	return float(AFTER.get(String(e.get("kind", "log")), 1.5))


static func span(e: Dictionary) -> float:
	return float(e.warn) + after(e)


## Is a runner whose feet are at p caught by band e (HIT_PAD: their body)?
static func inside(e: Dictionary, p: Vector3, pad: float = HIT_PAD) -> bool:
	return absf(p.x - float(e.x)) < float(e.w) + pad and p.y > float(e.y) - 0.6 and p.y < float(e.y) + Y_REACH


## Should a runner at p wait for band e (just before it, not in it)?
static func wait_before(e: Dictionary, p: Vector3) -> bool:
	var d := float(e.x) - float(e.w) - p.x
	return d > WAIT_NEAR - 0.3 and d < WAIT_FAR and absf(p.y - float(e.y)) < Y_REACH


## Seconds a small kid in the middle of band e needs to run out of it (the nearer side that is solid floor), INF none.
static func escape_time(c: Dictionary, e: Dictionary) -> float:
	var need := float(e.w) + HIT_PAD + ESCAPE_PAD
	var best := INF
	for side in [-1.0, 1.0]:
		var q := Vector3(float(e.x) + side * need, float(e.y), 0.0)
		var ok := true
		for z in [-float(c.half_w) + 0.5, 0.0, float(c.half_w) - 0.5]:
			if not CourseGen.stands(c, Vector3(q.x, q.y, float(z))):
				ok = false
		if ok:
			best = minf(best, REACT + need / KID_SPEED)
	return best


## Reasons a course's surprises are unfair (empty = fine).
static func problems(c: Dictionary, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	if String(c.get("kind", "")) == "lesson" and not list.is_empty():
		why.append("surprises on a lesson")
	if int(spec.get("course", 1)) < 1 and not bool(spec.get("first", false)) and not list.is_empty():
		why.append("surprises on a show's first course")
	if list.size() > int(md.count):
		why.append("%d surprises (most %d)" % [list.size(), int(md.count)])
	var prev := -INF
	for e in list:
		var tag := "%s at x %.1f" % [e.get("kind", "?"), float(e.get("x", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown surprise %s" % str(e))
			continue
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		if float(e.w) > float(md[String(e.kind) + "_w"]) + 0.001:
			why.append("%s: a band too wide" % tag)
		var x0 := float(e.x) - float(e.w)
		var x1 := float(e.x) + float(e.w)
		if x0 - BAND_ROOM < prev:
			why.append("%s: on top of the one before" % tag)
		prev = x1 + BAND_ROOM
		if x0 < float(c.start_x) + START_CLEAR - 0.01 or x1 > float(c.finish_x) - FINISH_CLEAR + 0.01:
			why.append("%s: too near the start or the flag" % tag)
		# Solid floor all through it (no gap, no step, no spinner disc), and room beyond each side.
		var k := 0
		while k <= 12:
			var x := lerpf(x0 - BAND_ROOM, x1 + BAND_ROOM, k / 12.0)
			for z in [-float(c.half_w) + 0.4, 0.0, float(c.half_w) - 0.4]:
				if absf(CourseGen.support_y(c, x, float(z), float(e.y) + 0.1) - float(e.y)) > 0.01:
					why.append("%s: not on solid floor at x %.1f" % [tag, x])
					k = 99
					break
			k += 1
		for o in c.obstacles:
			if x1 + OBSTACLE_PAD - 0.01 > float(o[0]) and x0 - OBSTACLE_PAD + 0.01 < float(o[1]):
				why.append("%s: in the %s" % [tag, String(o[2])])
		for p in c.pads:
			if absf((p as Vector3).x - float(e.x)) < float(e.w) + CourseGen.PAD_R:
				why.append("%s: on a bounce pad" % tag)
		if escape_time(c, e) > float(e.warn):
			why.append("%s: no way out in time" % tag)
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.y), float(e.w), float(e.warn)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 5 else {"kind": String(a[0]), "x": float(a[1]), "y": float(a[2]), "w": float(a[3]), "warn": float(a[4])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(medals: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if medals >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are others
## (the same on every machine for a seed).
static func gift_choices(medals: int, last: String, seed_value: int) -> Array:
	var un := unlocked(medals)
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


## A runner's physics with a gift (runner.gd and coursegen.gd simulate): jump (x), fall (gravity x while falling from
## the runner's own jump: never off a ledge or on a bounce pad's flight), max_fall (m/s), speed (x), air (most speed in the air, x the runner's own running speed:
## a higher or longer jump never carries further than an ordinary one, so it never lands right at the next gap).
static func phys(gift_id: String) -> Dictionary:
	match gift_id:
		"springs":
			return {"jump": SPRING_JUMP, "fall": 1.0, "max_fall": 30.0, "speed": 1.0, "air": SPRING_AIR}
		"cape":
			return {"jump": 1.0, "fall": GLIDE_FALL, "max_fall": GLIDE_MAX_FALL, "speed": 1.0, "air": GLIDE_AIR}
		"zoom":
			return {"jump": 1.0, "fall": 1.0, "max_fall": 30.0, "speed": ZOOM, "air": 1.0}
	return {}


static func star_r(gift_id: String) -> float:
	return MAGNET_R if gift_id == "magnet" else STAR_R


# --- The medal hall -------------------------------------------------------------------------------------------

static func trophies(medals: int) -> int:
	return mini(4, maxi(0, medals) / TROPHY_EVERY)


static func medal_color(mode: String) -> Color:
	return METALS[String(MEDAL_METAL[mode_of(mode)])]


# --- The pick rows --------------------------------------------------------------------------------------------

## The start orbs' places in the world (their middles), for n orbs, on course c (its start line and start floor).
static func row_spots(c: Dictionary, n: int = 3) -> Array:
	var out: Array = []
	var x := float(c.start_x) + ROW_AHEAD
	var y := CourseGen.support_y(c, x, 0.0, 1.0)
	if y == -INF:
		y = 0.0
	for i in n:
		var z: float = ROW_Z[i] if n == 3 else lerpf(ROW_Z[0], ROW_Z[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, y + ORB_Y, z))
	return out


## The VR orbs' places: an arm's reach in front of the giant's head (the giant faces -Z), but always in front of
## course c's near edge (a spinner's disc reaches out past the floors: an orb inside it hid under the disc).
static func vr_spots(head: Vector3, n: int = 3, c: Dictionary = {}) -> Array:
	var out: Array = []
	for i in n:
		var x: float = VR_X[i] if n == 3 else lerpf(VR_X[0], VR_X[2], float(i) / maxf(1.0, n - 1))
		var p := Vector3(head.x + x * VR_S, head.y - VR_BELOW * VR_S, head.z - VR_AHEAD * VR_S)
		p.z = maxf(p.z, near_edge(c, p.x) + orb_r(true) + VR_CLEAR * VR_S)
		out.append(p)
	return out


## How far towards the giant (+Z) course c reaches at x: its floors' half width, or a spinner disc's edge.
static func near_edge(c: Dictionary, x: float) -> float:
	var z := float(c.get("half_w", 3.0))
	for dd in c.get("discs", []):
		var dx := x - float(dd[0])
		var r := float(dd[2]) + orb_r(true)  # (an orb beside the disc's edge must clear it too)
		if absf(dx) < r:
			z = maxf(z, sqrt(r * r - dx * dx))
	return z


## Which start orb a runner at p stands under (-1 none).
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


## An orb's radius in the world.
static func orb_r(vr: bool) -> float:
	return PickOrbs.BALL_R * (VR_SCALE if vr else ORB_SCALE)


## How far past the start line the first obstacle of course c begins (the pick row and the fence must stay short of it).
static func first_obstacle(c: Dictionary) -> float:
	var best := INF
	for o in c.obstacles:
		best = minf(best, float(o[0]))
	for p in c.pads:
		best = minf(best, (p as Vector3).x - CourseGen.PAD_R)
	for d in c.discs:
		best = minf(best, float(d[0]) - float(d[2]))
	for f in c.floors:  # a floor that ends (a gap, a step) counts too
		if float(f[1]) > float(c.start_x) and float(f[1]) < best:
			best = float(f[1])
	return best - float(c.start_x)
