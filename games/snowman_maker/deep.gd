extends RefCounted
## SNOWMAN MAKER second pass (pure data + small functions; tests/snowman_maker_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first snow day: how many points the stars ask for, how often Tumble's garden has a warned surprise,
##             how long it is told first, how big it is, how fast a sunbeam melts and how long a bump makes you dizzy.
##   GIFTS     TUMBLE'S SNOWMAN GIFTS, three offered on the pick orbs before every day from the second: COSY SCARF
##             (snowballs grow fast and never melt), CARROT NOSE (every snowman gets its nose by itself), MAGIC HAT
##             (the wished-for hat hops on by itself), SPARKLE BUTTONS (every snowman counts double) and SNOW BOOTS
##             (rollers run faster and snow slides can't bump them) - the last two open as Tumble's snow town grows.
##             A gift lasts the whole day.
##   SURPRISES warned by steady core/warn_rings.gd shapes on the snow (each kind its own colour), never on a session's
##             first day or a day's first seconds, never two at once:
##               SUNBEAM  a warm orange circle: the sun peeks through and snowballs in it melt smaller - roll them out!
##               SLIDE    a violet band across the garden: a giant snowball rolls along it, knocks loose snowballs
##                        aside and makes anyone in its way dizzy for a moment.
##             hazards(g, secs, spec) is the same list on every machine for a garden; problems() proves it fair (told
##             long enough for a small child to get out, never on the build circle, a box, the visitor, the sign or
##             the VR builder, a sunbeam always leaves plenty of snowball spots, a slide never through a pine, and a
##             lone builder keeping clear still earns the day's first star - TODAY'S GARDEN on every date too).
##   SEASONS   winter is a real snowy garden (more snow slides); out of season (Seeded.season spring / summer /
##             autumn) the garden is Tumble's MAGIC SNOW GLOBE: a glass dome on a golden stand, the season outside
##             (blossom, sunflowers, autumn leaves) and more sunbeams when it's sunny.
##   TOWN      every TOWN_EVERY snowmen the family makes, Tumble's SNOW TOWN beside the garden gets a new piece (an
##             igloo house, a snow dog, a lit snowy tree, a snow bear, a sled, a tower ...: saved, for good).
##   PICK ROW  three orbs: with a VR builder an arm's reach in front of them (they reach into one on purpose: a hand
##             moves in and stays a moment) and TV players walk under one; with no VR builder (a flat host, local
##             play, a lone Deck) bigger orbs stand in the middle of the build circle. Nobody in time = the middle.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const G := preload("res://games/snowman_maker/gardengen.gd")
const Story := preload("res://games/snowman_maker/story.gd")

const SPEED := 4.2  # == main.gd (the test checks)
const BALL_MIN := 0.16  # == main.gd
const GROW := 0.03  # == main.gd

## goal: star goals times this; every: seconds between surprises; warn: seconds told first; sun_r: a sunbeam's
## radius; melt: snowball radius lost a second in a sunbeam; slide_w: half the slide band's width; dizzy: seconds a
## bump slows a roller.
const MODES := {
	"gentle": {"goal": 0.8, "every": 30.0, "warn": 3.4, "sun_r": 1.3, "melt": 0.02, "slide_w": 0.7, "dizzy": 1.0},
	"brave": {"goal": 1.0, "every": 22.0, "warn": 2.9, "sun_r": 1.5, "melt": 0.03, "slide_w": 0.8, "dizzy": 1.4},
	"hard": {"goal": 1.15, "every": 16.0, "warn": 2.4, "sun_r": 1.7, "melt": 0.04, "slide_w": 0.9, "dizzy": 1.8},
}
const MIN_WARN := 2.0
const REACT := 0.6  # seconds a child takes to notice a tell and start moving
const KID_SHARE := 0.55  # a small child's stick: this share of full speed
const FIRST_ROUND := 2  # no surprises on a session's first day (one new thing at a time)
const FIRST_T := 25.0  # ... nor in a day's first seconds
const SHORT_FIRST := 3.0  # (bot days under a minute: from 3 s)
const END_CALM := 4.0  # nothing in a day's last seconds
const MIN_GAP := 8.0  # seconds between two surprises' tells
const AFTER := 3.6  # seconds a surprise lasts after its tell (the sun shines / the big snowball rolls by)
const MAX_SHARE := 0.45  # at most this share of a day has a surprise going
const MIN_SPOTS := 6  # snowball spots a sunbeam always leaves in the shade
const SLIDE_SPEED := 6.0
const SLIDE_R := 0.55  # the big rolling snowball
const SLIDE_HIT := 0.3  # a roller this much past the band's edge is still bumped
const DIZZY_SLOW := 0.4  # a dizzy roller moves at this share of their speed
const SUN_COLOR := Color(1.0, 0.55, 0.12)  # warm sunbeam orange
const SLIDE_COLOR := Color(0.62, 0.36, 1.0)  # snow-slide violet
const KINDS: Array[String] = ["sun", "slide"]
const KIND_PICS := {"sun": "sunbeam", "slide": "snowslide"}
const KIND_NAMES := {"sun": "SUNBEAM!", "slide": "SNOW SLIDE!"}
## Season -> surprise weights (sun, slide), a snow globe out of season, the outside ground, a picture, Tumble's line.
const SEASONS := {
	"spring": {"weights": [1.4, 0.8], "globe": true, "ground": Color(0.42, 0.72, 0.32), "drift": Color(1.0, 0.75, 0.88),
		"pic": "snowglobe", "line": "A spring snow globe!"},
	"summer": {"weights": [1.8, 0.5], "globe": true, "ground": Color(0.5, 0.78, 0.3), "drift": Color(1.0, 0.93, 0.5),
		"pic": "snowglobe", "line": "A summer snow globe!"},
	"autumn": {"weights": [1.0, 1.0], "globe": true, "ground": Color(0.78, 0.45, 0.18), "drift": Color(0.95, 0.5, 0.15),
		"pic": "snowglobe", "line": "An autumn snow globe!"},
	"winter": {"weights": [0.6, 1.5], "globe": false, "ground": Color(0.93, 0.96, 1.0), "drift": Color(1.0, 1.0, 1.0),
		"pic": "snowflake", "line": "Real snow! Hooray!"},
}
## Tumble's gifts: id, name, picture, a short line, a colour, town pieces needed.
const GIFTS: Array[Dictionary] = [
	{"id": "scarf", "name": "COSY SCARF", "pic": "scarf", "line": "Snowballs grow fast!", "color": Color(0.95, 0.25, 0.35), "unlock": 0},
	{"id": "carrot", "name": "CARROT NOSE", "pic": "carrot", "line": "Noses pop on!", "color": Color(1.0, 0.55, 0.1), "unlock": 0},
	{"id": "hat", "name": "MAGIC HAT", "pic": "tophat", "line": "Hats hop on!", "color": Color(0.35, 0.55, 1.0), "unlock": 0},
	{"id": "buttons", "name": "SPARKLE BUTTONS", "pic": "sparklebuttons", "line": "Snowmen count double!", "color": Color(1.0, 0.82, 0.2), "unlock": 2},
	{"id": "boots", "name": "SNOW BOOTS", "pic": "snowboots", "line": "Run fast, no bumps!", "color": Color(0.3, 0.85, 0.55), "unlock": 4},
]
const SCARF_GROW := 1.7  # COSY SCARF: snowballs grow this much faster
const AUTO_SECS := 1.2  # CARROT NOSE / MAGIC HAT: seconds before it pops on by itself
const BOOTS_SPEED := 1.3  # SNOW BOOTS: rollers run this much faster
## Tumble's snow town: one piece every TOWN_EVERY snowmen made.
const TOWN_EVERY := 6
const TOWN: Array[String] = ["igloo", "dog", "tree", "bear", "sled", "tower", "lamp", "fountain", "cocoa", "castle"]
const TOWN_PICS := {"igloo": "igloo", "dog": "puppy", "tree": "tree", "bear": "polarbear", "sled": "sledman", "tower": "castle",
	"lamp": "lantern", "fountain": "fountain", "cocoa": "cocoamug", "castle": "snowking"}
## The town's spots: two columns each side of the garden (clear of the village places on the far side).
const TOWN_X := 12.2
const TOWN_Z: Array[float] = [-2.6, 0.0, 2.6, 5.2, 7.8]
## The globe: a glass dome on a golden stand round the garden and the village.
const GLOBE_R := 22.0
const STAND_COLOR := Color(0.95, 0.78, 0.3)
## The pick row. With a VR builder: an arm's reach in front of them, a little apart; TV players walk under one.
const ROW_AHEAD := 0.75
const ROW_GAP := 0.72
const ROW_Y := 1.1
const ORB_SCALE := 0.3
const HAND_R := 0.1  # a glove this near an orb's edge is in it
const DWELL := 0.3  # seconds a glove must stay in an orb (a hand sweeping past never picks)
const TV_R := 0.32  # a roller this near an orb's middle (across) catches it
const TV_DWELL := 0.15
const FLAT_X: Array[float] = [-1.2, 0.0, 1.2]  # no VR builder: big orbs in the build circle (always clear)
const FLAT_Y := 1.5
const FLAT_Z := 0.0
const FLAT_SCALE := 0.5
const FLAT_TV_R := 0.5
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const EMPTY_WAIT := 8.0  # nobody here who could pick at all: sooner
## Real-progress model (problems(): a lone builder with Tumble's help, keeping clear of every surprise).
const SOLO_PER_MIN := 1.6  # points a minute (Tumble rolls too)
const TEAM_SHARE := 0.6  # each extra builder adds this share


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.winter)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 16.0))


## A day's star goals in a mode (story.gd goals, scaled; still rising 1 < 2 < 3 stars, never below 1).
static func goals(builders: int, chap: int, misses: int, laps: int, secs: float, mode: String) -> Array:
	var g: Array = Story.goals(builders, chap, misses, laps, secs)
	var f := float(mode_data(mode).goal)
	var g1 := maxi(1, int(round(float(g[0]) * f)))
	var g2 := maxi(g1 + 1, int(round(float(g[1]) * f)))
	var g3 := maxi(g2 + 1, int(round(float(g[2]) * f)))
	return [g1, g2, g3]


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["goal", "sun_r", "melt", "slide_w", "dizzy"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["every", "warn"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(h.every) < MIN_GAP:
		out.append("hard: surprises closer than %.0f s" % MIN_GAP)
	return out


# --- Surprises ------------------------------------------------------------------------------------------------

## The surprises of a snow day in garden g lasting secs: [{t, kind, x, z, dx, dz, warn, r}] by time. t: when the tell
## starts (day seconds); it goes off at t + warn. sun: a circle at (x, z) of radius r. slide: a band through (x, z)
## along (dx, dz), r = half its width. spec: {mode, season, round (none before FIRST_ROUND), first (bots: earlier)}.
static func hazards(g: Dictionary, secs: float, spec: Dictionary) -> Array:
	var out: Array = []
	if int(spec.get("round", FIRST_ROUND)) < FIRST_ROUND:
		return out
	var md := mode_data(String(spec.get("mode", "brave")))
	var weights: Array = season_data(String(spec.get("season", "winter"))).weights
	var r := Seeded.rng(int(g.get("seed", 0)), "surprises %s %d" % [mode_of(String(spec.get("mode", "brave"))), int(secs)])
	var every := float(md.every)
	var long := secs >= 60.0
	var t := float(spec.get("first", FIRST_T if long else SHORT_FIRST)) + (r.randf_range(0.0, every * 0.3) if long else 0.0)
	while t + float(md.warn) + AFTER <= secs - END_CALM:
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		var e := {}
		for attempt in 24:
			e = _make(r, kind, t, md)
			if _where_problem(g, e, out).is_empty():
				break
			e = {}
		if e.is_empty():  # the other kind may fit where this one can't
			kind = KINDS[1 - KINDS.find(kind)]
			for attempt in 24:
				e = _make(r, kind, t, md)
				if _where_problem(g, e, out).is_empty():
					break
				e = {}
		if not e.is_empty():
			out.append(e)
		t += every * r.randf_range(0.9, 1.2)
	return out


static func _make(r: RandomNumberGenerator, kind: String, t: float, md: Dictionary) -> Dictionary:
	var e := {"t": snappedf(t, 0.01), "kind": kind, "warn": float(md.warn)}
	var a := r.randf() * TAU
	if kind == "sun":
		var rad := float(md.sun_r)
		var d := r.randf_range(G.YARD_R + rad + 0.4, G.ARENA - rad - 0.4)
		e.merge({"x": snappedf(cos(a) * d, 0.01), "z": snappedf(sin(a) * d, 0.01), "dx": 0.0, "dz": 1.0, "r": rad}, true)
	else:
		var w := float(md.slide_w)
		var dir := Vector2(cos(a), sin(a))
		var off := Vector2(-dir.y, dir.x) * r.randf_range(G.YARD_R + w + 0.4, G.ARENA - 2.2) * (1.0 if r.randf() < 0.5 else -1.0)
		e.merge({"x": snappedf(off.x, 0.01), "z": snappedf(off.y, 0.01), "dx": snappedf(dir.x, 0.0001), "dz": snappedf(dir.y, 0.0001),
			"r": w}, true)
	return e


## How far point p is from a slide's line (across it).
static func line_dist(e: Dictionary, p: Vector2) -> float:
	var dir := Vector2(float(e.dx), float(e.dz)).normalized()
	var q := p - Vector2(float(e.x), float(e.z))
	return absf(q.x * -dir.y + q.y * dir.x)


## Is point p (on the ground) inside surprise e's zone (pad: extra margin)?
static func inside(e: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	if String(e.kind) == "sun":
		return p.distance_to(Vector2(float(e.x), float(e.z))) < float(e.r) + pad
	return line_dist(e, p) < float(e.r) + pad


## Seconds after its tell starts that a surprise is over.
static func span(e: Dictionary) -> float:
	return float(e.warn) + AFTER


## Half the slide's run (the band's half-length inside the garden + a little).
static func slide_half(e: Dictionary) -> float:
	var mid := Vector2(float(e.x), float(e.z))
	return sqrt(maxf(0.0, (G.ARENA + 1.0) * (G.ARENA + 1.0) - mid.length_squared()))


## The big snowball's place `s` seconds after it set off (edge to edge of the garden).
static func slide_at(e: Dictionary, s: float) -> Vector3:
	var dir := Vector2(float(e.dx), float(e.dz)).normalized()
	var p := Vector2(float(e.x), float(e.z)) + dir * (-slide_half(e) + s * SLIDE_SPEED)
	return Vector3(p.x, SLIDE_R, p.y)


static func slide_secs(e: Dictionary) -> float:
	return slide_half(e) * 2.0 / SLIDE_SPEED


## Snowball spots (garden spawns) a sunbeam leaves in the shade.
static func shade_spots(g: Dictionary, e: Dictionary) -> int:
	var n := 0
	for p in g.get("spawns", []):
		if not inside(e, Vector2((p as Vector3).x, (p as Vector3).z), 0.3):
			n += 1
	return n


static func _where_problem(g: Dictionary, e: Dictionary, earlier: Array) -> String:
	var at := Vector2(float(e.x), float(e.z))
	var rad := float(e.r)
	var vr := Vector2(G.VR_START.x, G.VR_START.z)
	var vis: Vector3 = g.get("visitor", Vector3(-2.7, 0.0, -0.9))
	var visitor := Vector2(vis.x, vis.z)
	var sign_at := Vector2(G.SIGN_POS.x, G.SIGN_POS.z)
	if not earlier.is_empty() and float(e.t) - float((earlier[earlier.size() - 1] as Dictionary).t) < MIN_GAP:
		return "two surprises too close together"
	if String(e.kind) == "sun":
		if at.length() + rad > G.ARENA - 0.3:
			return "a sunbeam outside the garden"
		if at.length() < G.YARD_R + rad + 0.3:
			return "a sunbeam on the build circle"
		if at.distance_to(vr) < rad + 1.0:
			return "a sunbeam on the VR builder"
		if at.distance_to(visitor) < rad + 0.8:
			return "a sunbeam on the visitor"
		if at.distance_to(sign_at) < rad + 0.5:
			return "a sunbeam on the sign"
		for b in g.get("boxes", []):
			var bp: Vector3 = b.pos
			if at.distance_to(Vector2(bp.x, bp.z)) < rad + G.BOX_R + 0.3:
				return "a sunbeam on a box"
		if shade_spots(g, e) < MIN_SPOTS:
			return "a sunbeam over too many snowball spots"
	else:
		if line_dist(e, Vector2.ZERO) < G.YARD_R + rad + 0.3:
			return "a slide through the build circle"
		if line_dist(e, vr) < rad + 1.6:
			return "a slide through the VR builder"
		if line_dist(e, visitor) < rad + 0.7:
			return "a slide through the visitor"
		if line_dist(e, sign_at) < rad + 0.4:
			return "a slide through the sign"
		for b in g.get("boxes", []):
			var bp: Vector3 = b.pos
			if line_dist(e, Vector2(bp.x, bp.z)) < rad + G.BOX_R + 0.2:
				return "a slide through a box"
		for tr in g.get("trees", []):
			var tp: Vector3 = tr
			if line_dist(e, Vector2(tp.x, tp.z)) < rad + G.TREE_R + 0.1:
				return "a slide through a pine"
		if at.length() > G.ARENA - 2.0:
			return "a slide along the edge"
	return ""


## Seconds of building a careful lone builder loses to surprise e (a sunbeam: rolling a ball out of it; a slide:
## stepping out of the band and back, or a dizzy moment).
static func lost(e: Dictionary, md: Dictionary) -> float:
	return AFTER * 0.5 if String(e.kind) == "sun" else float(md.dizzy) + 1.0


## Points a careful team of `builders` makes in a day of secs with these surprises (the real-progress model).
static func can_make(builders: int, secs: float, list: Array, mode: String) -> float:
	var md := mode_data(mode)
	var gone := 0.0
	for e in list:
		gone += lost(e, md)
	var rate := SOLO_PER_MIN * (1.0 + TEAM_SHARE * float(clampi(builders, 1, 8) - 1))
	return rate * maxf(0.0, secs - gone) / 60.0


## Reasons a day's surprises are unfair (empty = fine). goals: that day's [1, 2, 3 star] goals for one builder.
static func problems(g: Dictionary, secs: float, list: Array, spec: Dictionary, goals1: Array = []) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var long := secs >= 60.0
	var first := float(spec.get("first", FIRST_T if long else SHORT_FIRST))
	if int(spec.get("round", FIRST_ROUND)) < FIRST_ROUND and not list.is_empty():
		why.append("surprises on the first day")
	var kid := SPEED * KID_SHARE
	var prev: Array = []
	var busy := 0.0
	for e in list:
		var tag := "%s at %.1f s" % [e.get("kind", "?"), float(e.get("t", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown surprise %s" % str(e))
			continue
		if float(e.t) < first - 0.001:
			why.append("%s: too early in the day" % tag)
		if float(e.t) + span(e) > secs - END_CALM + 0.001:
			why.append("%s: runs into the end of the day" % tag)
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		var where := _where_problem(g, e, prev)
		if where != "":
			why.append("%s: %s" % [tag, where])
		# A small child in the middle of it gets out in time (pushing a snowball out of a sunbeam: its edge, from
		# the middle; stepping off a slide band).
		var walk := (float(e.r) + (SLIDE_HIT if String(e.kind) == "slide" else 0.0)) / kid + REACT
		if walk > float(e.warn):
			why.append("%s: a small child can't get out in time (%.1f s for %.1f s)" % [tag, walk, float(e.warn)])
		if String(e.kind) == "slide" and slide_secs(e) > AFTER + 0.01:
			why.append("%s: the big snowball takes %.1f s to roll by" % [tag, slide_secs(e)])
		if String(e.kind) == "sun" and float(md.melt) * AFTER > 0.2:
			why.append("%s: a sunbeam melts a whole snowball" % tag)
		busy += span(e)
		prev.append(e)
	if busy > secs * MAX_SHARE + 0.001:
		why.append("surprises going %.0f%% of the day" % (100.0 * busy / secs))
	# A lone builder (Tumble helps) keeping clear of every surprise still earns the first star.
	if not goals1.is_empty() and can_make(1, secs, list, String(spec.get("mode", "brave"))) < float(goals1[0]):
		why.append("keeping clear, a lone builder can't reach the first star (%.1f of %d)" % [
			can_make(1, secs, list, String(spec.get("mode", "brave"))), int(goals1[0])])
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.z), float(e.dx), float(e.dz), float(e.warn), float(e.r), float(e.t)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 8 else {"kind": String(a[0]), "x": float(a[1]), "z": float(a[2]), "dx": float(a[3]), "dz": float(a[4]),
		"warn": float(a[5]), "r": float(a[6]), "t": float(a[7])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(pieces: int) -> Array:
	var out: Array = []
	for gd in GIFTS:
		if pieces >= int(gd.unlock):
			out.append(String(gd.id))
	return out


static func gift(id: String) -> Dictionary:
	for gd in GIFTS:
		if String(gd.id) == id:
			return gd
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


## How fast snowballs grow with a gift (COSY SCARF: faster).
static func grow_share(gift_id: String) -> float:
	return SCARF_GROW if gift_id == "scarf" else 1.0


## Points for a finished snowman (SPARKLE BUTTONS: double).
static func snowman_points(base: int, gift_id: String) -> int:
	return base * 2 if gift_id == "buttons" else base


static func speed_share(gift_id: String) -> float:
	return BOOTS_SPEED if gift_id == "boots" else 1.0


static func melts(gift_id: String) -> bool:
	return gift_id != "scarf"


static func bumps(gift_id: String) -> bool:
	return gift_id != "boots"


# --- Tumble's snow town ---------------------------------------------------------------------------------------

static func town(made: int) -> int:
	return mini(TOWN.size(), maxi(0, made) / TOWN_EVERY)


## Where town piece i stands (on the snow, beside the garden): alternately left and right, front to back.
static func town_spot(i: int) -> Vector3:
	var side := -1.0 if i % 2 == 0 else 1.0
	return Vector3(TOWN_X * side, 0.0, TOWN_Z[(i / 2) % TOWN_Z.size()])


# --- The pick row ---------------------------------------------------------------------------------------------

## The orbs' places. vr: an arm's reach in front of the VR builder standing at `at` looking along `fwd` (flat);
## else the big row in the build circle.
static func row_spots(n: int = 3, vr: bool = true, at: Vector3 = G.VR_START, fwd: Vector3 = Vector3.FORWARD) -> Array:
	var out: Array = []
	var f := Vector3(fwd.x, 0.0, fwd.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var right := Vector3(-f.z, 0.0, f.x)
	for i in n:
		var k := float(i) - float(n - 1) * 0.5
		if vr:
			var p := Vector3(at.x, 0.0, at.z) + f * ROW_AHEAD + right * k * ROW_GAP
			out.append(Vector3(p.x, ROW_Y, p.z))
		else:
			var x: float = FLAT_X[i] if n == 3 else lerpf(FLAT_X[0], FLAT_X[2], float(i) / maxf(1.0, n - 1))
			out.append(Vector3(x, FLAT_Y, FLAT_Z))
	return out


static func orb_scale(vr: bool) -> float:
	return ORB_SCALE if vr else FLAT_SCALE


static func tv_r(vr: bool) -> float:
	return TV_R if vr else FLAT_TV_R


static func orb_r(vr: bool = true) -> float:
	return PickOrbs.HIT_R * orb_scale(vr)
