extends RefCounted
## FRUIT CATCH second pass (pure data + small functions; tests/fruit_catch_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first round: how hard the harvests are (a level up or down), how often Nutmeg's orchard has a warned
##             surprise, how long it is told first, how big it is and how long a bump makes you dizzy.
##   GIFTS     NUTMEG'S BASKET GIFTS, three offered on the pick orbs before every round from the second: BIG BASKET
##             (catch from further away), MAGNET (good fruit drifts into baskets), SLOW FALL (fruit floats down),
##             UMBRELLA (rotten apples bounce off) and GOLDEN DISH (every dish is worth double) - the last two open
##             as Nutmeg's pantry fills. A gift lasts the whole round.
##   SURPRISES warned by steady core/warn_rings.gd shapes on the grass (each kind its own colour), never on a round's
##             first seconds, never two at once:
##               WINDFALL  a brown circle: a shower of rotten apples lands there - step out of it!
##               WASP      a yellow band across the park: a wasp buzzes along it and bumps anyone in its way (dizzy).
##             hazards(h, spec) is the same list on every machine for a harvest; problems() proves it fair (told long
##             enough for a small child to walk out, never over the bowl, the trunk, Nutmeg or the giant's spot, a
##             windfall never lands where a good fruit is falling, and a small child keeping clear of every surprise
##             still finishes Nutmeg's first dish).
##   SEASONS   the orchard is dressed for the season (Seeded.season): spring blossom, summer sunflowers, autumn leaves,
##             and in winter Nutmeg's MAGIC SNOW GLOBE (snow drifts down on the orchard). Summer has more wasps,
##             autumn more windfalls, winter's wasps are sleepy.
##   PANTRY    every PANTRY_EVERY finished dishes Nutmeg's PANTRY beside the park gets a new piece (jam shelf, pie
##             table, juice barrel, honey pots ...: saved, for good).
##   PICK ROW  three orbs float just in front of the giant's spot (an arm's reach away). A TV player walks under one
##             to catch it in their basket; the giant reaches into one on purpose (a hand moves in and stays a
##             moment: never a resting hand). Nobody in time = the middle (it glows). With no giant (a flat host or
##             local play) the orbs are bigger and stand out on the open grass in front of the tree (FLAT_*).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const G := preload("res://games/fruit_catch/harvestgen.gd")

const NUTMEG_POS := Vector3(2.35, 0.0, 2.1)  # == main.gd (the test checks)
const SIGN_POS := Vector3(-1.6, 0.0, 1.6)  # == main.gd
const VR_START := Vector3(0.0, 0.0, 3.05)  # == main.gd
const STUMP_R := 0.35  # == art.gd

## lv: harvest level added (recipes, rotten apples, wind); every: seconds between surprises; warn: seconds told first;
## wf_r / wf_n: a windfall's radius and rotten apples; wasp_w: half the wasp band's width; dizzy: seconds a bump slows.
const MODES := {
	"gentle": {"lv": -1, "every": 26.0, "warn": 3.2, "wf_r": 1.3, "wf_n": 4, "wasp_w": 0.7, "dizzy": 1.0},
	"brave": {"lv": 0, "every": 18.0, "warn": 2.7, "wf_r": 1.5, "wf_n": 6, "wasp_w": 0.8, "dizzy": 1.4},
	"hard": {"lv": 1, "every": 13.0, "warn": 2.2, "wf_r": 1.7, "wf_n": 8, "wasp_w": 0.9, "dizzy": 1.8},
}
const MIN_WARN := 2.0
const REACT := 0.6  # seconds a child takes to notice a tell and start walking
const FIRST_ROUND := 2  # no surprises on a session's first round (one new thing at a time)
const FIRST_T := 20.0  # ... nor in a round's first seconds
const SHORT_FIRST := 3.0  # (bot rounds of 16 s: from 3 s)
const MIN_GAP := 8.0  # seconds between two surprises' tells
const AFTER := 3.2  # seconds a surprise lasts after its tell (apples land / the wasp flies by)
const WASP_SPEED := 6.0
const WASP_Y := 1.25
const WASP_HIT := 0.3  # a basket this much past the band's edge is still bumped
const WINDFALL_COLOR := Color(0.55, 0.3, 0.12)  # rotten-apple brown
const WASP_COLOR := Color(1.0, 0.82, 0.1)  # wasp yellow
const KINDS: Array[String] = ["windfall", "wasp"]
const KIND_PICS := {"windfall": "windfall", "wasp": "wasp"}
const KIND_NAMES := {"windfall": "WINDFALL!", "wasp": "WASP!"}
## Season -> surprise weights (windfall, wasp), the drifting things' colour, a picture, Nutmeg's line.
const SEASONS := {
	"spring": {"weights": [1.0, 1.0], "drift": Color(1.0, 0.75, 0.88), "pic": "daisy", "line": "Spring orchard!"},
	"summer": {"weights": [0.6, 1.6], "drift": Color(1.0, 0.93, 0.5), "pic": "sunflower", "line": "Sunny orchard!"},
	"autumn": {"weights": [1.7, 0.6], "drift": Color(0.95, 0.5, 0.15), "pic": "acorn", "line": "Windy autumn!"},
	"winter": {"weights": [1.3, 0.4], "drift": Color(1.0, 1.0, 1.0), "pic": "snowglobe", "line": "A magic snow globe!"},
}
## Nutmeg's gifts: id, name, picture, a short line, a colour, pantry pieces needed.
const GIFTS: Array[Dictionary] = [
	{"id": "big", "name": "BIG BASKET", "pic": "bigbasket", "line": "A huge basket!", "color": Color(0.3, 0.95, 0.5), "unlock": 0},
	{"id": "magnet", "name": "MAGNET", "pic": "fruitmagnet", "line": "Fruit comes to you!", "color": Color(1.0, 0.45, 0.75), "unlock": 0},
	{"id": "slow", "name": "SLOW FALL", "pic": "parachute", "line": "Floaty fruit!", "color": Color(0.45, 0.75, 1.0), "unlock": 0},
	{"id": "umbrella", "name": "UMBRELLA", "pic": "umbrella", "line": "Yucky apples bounce!", "color": Color(0.7, 0.5, 1.0), "unlock": 2},
	{"id": "golden", "name": "GOLDEN DISH", "pic": "goldapple", "line": "Double dishes!", "color": Color(1.0, 0.85, 0.25), "unlock": 4},
]
const BIG_CATCH := 0.95  # BIG BASKET: catch radius (plain baskets 0.6)
const BIG_SCALE := 1.45  # ... and how big it looks
const PLAIN_CATCH := 0.6
const MAGNET_R := 1.8  # MAGNET: good fruit this near a basket (across) drifts in
const MAGNET_PULL := 2.2  # m/s
const MAGNET_Y := 3.2  # ... once it has fallen below this
const SLOW := 0.6  # SLOW FALL: the fall's pull (the wind drifts sqrt(SLOW) as fast: every fruit lands where it would)
const DISH_BONUS := 5
const GOLDEN_BONUS := 10
## Nutmeg's pantry: one piece every PANTRY_EVERY dishes.
const PANTRY_EVERY := 3
const PANTRY: Array[String] = ["jam", "pies", "juice", "honey", "cake", "crates", "lanterns", "cart"]
const PANTRY_PICS := {"jam": "jamjar", "pies": "pie", "juice": "juice", "honey": "honeyjar", "cake": "cake",
	"crates": "fruitbowl", "lanterns": "lantern", "cart": "pantry"}
const PANTRY_AT := Vector3(10.2, 0.0, 2.6)  # the pantry's middle: beside the park, right of the giant
## The pick row: three orbs just in front of the giant (an arm's reach), between the sign and the bowl.
const ROW_X: Array[float] = [-0.95, -0.3, 0.35]
const ROW_Y := 1.1  # (under the front branch's leaves: the branches can't be grabbed while the orbs are up)
const ROW_Z := 2.6
const ORB_SCALE := 0.3
const HAND_R := 0.1  # a glove this near an orb's edge is in it
const DWELL := 0.3  # seconds a glove must stay in an orb (a hand sweeping past never picks)
const TV_R := 0.32  # a basket this near an orb's middle (across) catches it
const TV_DWELL := 0.15
const FLAT_X: Array[float] = [-2.3, 0.0, 2.3]  # no giant: big orbs on the open grass, easy to see on a TV / Deck
const FLAT_Y := 1.6
const FLAT_Z := 4.7
const FLAT_SCALE := 0.55
const FLAT_TV_R := 0.55
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


## A round's harvest level in a mode (TODAY'S HARVEST keeps its own level: the same on every machine).
static func level(round_n: int, trees: int, mode: String) -> int:
	return clampi(G.level(round_n, trees) + int(mode_data(mode).lv), 1, G.MAX_LEVEL)


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["lv", "wf_r", "wf_n", "wasp_w", "dizzy"]:  # more is harder
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

## The surprises of a harvest h: [{t, kind, x, z, dx, dz, warn, r, n}] by time. t: when the tell starts (round seconds);
## it goes off at t + warn. windfall: a circle at (x, z) of radius r, n rotten apples. wasp: a band through (x, z)
## along (dx, dz), r = half its width. spec: {mode, season, round (none before FIRST_ROUND), first (bots: earlier)}.
static func hazards(h: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	if int(spec.get("round", FIRST_ROUND)) < FIRST_ROUND:
		return out
	var md := mode_data(String(spec.get("mode", "brave")))
	var secs := float(h.secs)
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var r := Seeded.rng(int(h.seed), "surprises %s" % mode_of(String(spec.get("mode", "brave"))))
	var every := float(md.every)
	var t := float(spec.get("first", FIRST_T if secs >= 60.0 else SHORT_FIRST)) + (r.randf_range(0.0, every * 0.4) if secs >= 60.0 else 0.0)
	var last_end := float(h.storm_at) - 1.0  # (calm for the fruit storm at the end)
	while t + float(md.warn) + AFTER <= last_end:
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		var e := {}
		for attempt in 16:
			e = _make(r, kind, t, md)
			if _where_problem(h, e, out).is_empty() and _kid_problems(h, out + [e]).is_empty():
				break
			e = {}
		if not e.is_empty():
			out.append(e)
		t += every * r.randf_range(0.85, 1.2)
	return out


static func _make(r: RandomNumberGenerator, kind: String, t: float, md: Dictionary) -> Dictionary:
	var e := {"t": snappedf(t, 0.01), "kind": kind, "warn": float(md.warn), "n": 0}
	if kind == "windfall":
		var rad := float(md.wf_r)
		var a := r.randf() * TAU
		var d := r.randf_range(G.TRUNK_R + rad + 0.5, G.ARENA - rad - 0.8)
		e.merge({"x": snappedf(cos(a) * d, 0.01), "z": snappedf(sin(a) * d, 0.01), "dx": 0.0, "dz": 1.0, "r": rad, "n": int(md.wf_n)}, true)
	else:
		var a := r.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var off := Vector2(-dir.y, dir.x) * r.randf_range(1.6, 5.5) * (1.0 if r.randf() < 0.5 else -1.0)
		e.merge({"x": snappedf(off.x, 0.01), "z": snappedf(off.y, 0.01), "dx": snappedf(dir.x, 0.0001), "dz": snappedf(dir.y, 0.0001),
			"r": float(md.wasp_w)}, true)
	return e


## How far point p is from a wasp's line (across it).
static func line_dist(e: Dictionary, p: Vector2) -> float:
	var dir := Vector2(float(e.dx), float(e.dz)).normalized()
	var q := p - Vector2(float(e.x), float(e.z))
	return absf(q.x * -dir.y + q.y * dir.x)


## Is point p (on the ground) inside surprise e's zone (pad: extra margin)?
static func inside(e: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	if String(e.kind) == "windfall":
		return p.distance_to(Vector2(float(e.x), float(e.z))) < float(e.r) + pad
	return line_dist(e, p) < float(e.r) + pad


## Seconds after its tell starts that a surprise is over.
static func span(e: Dictionary) -> float:
	return float(e.warn) + AFTER


## The wasp's place `s` seconds after it set off (it flies the whole band, edge to edge of the park).
static func wasp_at(e: Dictionary, s: float) -> Vector3:
	var dir := Vector2(float(e.dx), float(e.dz)).normalized()
	var mid := Vector2(float(e.x), float(e.z))
	var half := wasp_half(e)
	var p := mid + dir * (-half + s * WASP_SPEED)
	return Vector3(p.x, WASP_Y, p.y)


## Half the wasp's flight (the band's half-length inside the park + a little).
static func wasp_half(e: Dictionary) -> float:
	var mid := Vector2(float(e.x), float(e.z))
	return sqrt(maxf(0.0, (G.ARENA + 1.0) * (G.ARENA + 1.0) - mid.length_squared()))


## The wasp's flight time.
static func wasp_secs(e: Dictionary) -> float:
	return wasp_half(e) * 2.0 / WASP_SPEED


## Where windfall e's rotten apple k lands (spread over the circle, inside it).
static func windfall_spot(e: Dictionary, k: int) -> Vector2:
	var n := maxi(1, int(e.n))
	var a := float(k) * TAU / n + 0.4 * float(k % 2)
	var rr := float(e.r) * (0.25 + 0.55 * float((k * 7) % 5) / 4.0)
	return Vector2(float(e.x), float(e.z)) + Vector2(cos(a), sin(a)) * rr


static func _where_problem(h: Dictionary, e: Dictionary, earlier: Array) -> String:
	var at := Vector2(float(e.x), float(e.z))
	var rad := float(e.r)
	var bowl := Vector2(G.BOWL_POS.x, G.BOWL_POS.z)
	var nut := Vector2(NUTMEG_POS.x, NUTMEG_POS.z)
	var vr := Vector2(VR_START.x, VR_START.z)
	if not earlier.is_empty() and float(e.t) - float((earlier[earlier.size() - 1] as Dictionary).t) < MIN_GAP:
		return "two surprises too close together"
	if String(e.kind) == "windfall":
		if at.length() + rad > G.ARENA - 0.6:
			return "a windfall outside the park"
		if at.length() - rad < G.TRUNK_R + 0.3:
			return "a windfall on the trunk"
		if at.distance_to(bowl) < G.BOWL_R + rad + 0.3:
			return "a windfall on the bowl"
		if at.distance_to(nut) < STUMP_R + rad + 0.5:
			return "a windfall on Nutmeg"
		if at.distance_to(Vector2(SIGN_POS.x, SIGN_POS.z)) < rad + 0.5:
			return "a windfall on the sign"
		if at.distance_to(vr) < rad + 0.7:
			return "a windfall on the giant"
		var t0 := float(e.t)
		var t1 := t0 + span(e)
		for d in h.drops:
			if int(d[2]) == G.ROTTEN:
				continue
			var ct := G.catch_time(d)
			if ct >= t0 and ct <= t1 and G.catch_point(d, h.wind).distance_to(at) < rad + 0.5:
				return "a windfall where a good fruit is falling"
	else:
		if line_dist(e, vr) < 1.6:
			return "a wasp through the giant's spot"
		if line_dist(e, Vector2.ZERO) < G.TRUNK_R + 0.6:
			return "a wasp through the trunk"
		if line_dist(e, nut) < STUMP_R + rad + 0.4:
			return "a wasp through Nutmeg"
		if at.length() > G.ARENA - 2.0:
			return "a wasp along the edge"
	return ""


## Is drop d (index i) one a careful child keeps away from: it comes down inside a surprise's zone while it is told
## or going off?
static func blocked(d: Array, h: Dictionary, list: Array) -> bool:
	var ct := G.catch_time(d)
	var p := G.catch_point(d, h.wind)
	for e in list:
		var t0 := float(e.t)
		if ct >= t0 and ct <= t0 + span(e) and inside(e, p, 0.6):
			return true
	return false


## Reasons harvest h's surprises are unfair (empty = fine).
static func problems(h: Dictionary, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var secs := float(h.secs)
	var first := float(spec.get("first", FIRST_T if secs >= 60.0 else SHORT_FIRST))
	if int(spec.get("round", FIRST_ROUND)) < FIRST_ROUND and not list.is_empty():
		why.append("surprises on the first round")
	var kid := G.SPEED * G.KID_SHARE
	var prev: Array = []
	for e in list:
		var tag := "%s at %.1f s" % [e.get("kind", "?"), float(e.get("t", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown surprise %s" % str(e))
			continue
		if float(e.t) < first - 0.001:
			why.append("%s: too early in the round" % tag)
		if float(e.t) + span(e) > float(h.storm_at) + 0.001:
			why.append("%s: runs into the fruit storm" % tag)
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		var where := _where_problem(h, e, prev)
		if where != "":
			why.append("%s: %s" % [tag, where])
		# A small child standing in the middle of it walks out in time (a windfall's apples still have to fall).
		var walk := (float(e.r) + (WASP_HIT if String(e.kind) == "wasp" else 0.0)) / kid + REACT
		var have := float(e.warn) + (G.fall_time(G.DROP_HEIGHT, G.CATCH_Y) if String(e.kind) == "windfall" else 0.0)
		if walk > have:
			why.append("%s: a small child can't get out in time (%.1f s for %.1f s)" % [tag, walk, have])
		if String(e.kind) == "windfall":
			for k in int(e.n):
				if windfall_spot(e, k).distance_to(Vector2(float(e.x), float(e.z))) > float(e.r) - 0.1:
					why.append("%s: an apple lands outside its circle" % tag)
			if int(e.n) < 1 or int(e.n) > 10:
				why.append("%s: %d apples" % [tag, int(e.n)])
		elif wasp_secs(e) > AFTER + 0.5:
			why.append("%s: the wasp takes %.1f s to fly by" % [tag, wasp_secs(e)])
		prev.append(e)
	why.append_array(_kid_problems(h, list))
	return why


## A small child keeping clear of every surprise still finishes Nutmeg's first dish (with and without a giant).
## hazards() places each surprise only where this still holds (2026-11-12: after the branches turned, two HARD seeds'
## windfalls blocked too much early fruit), so it is fair by construction; problems() proves it.
static func _kid_problems(h: Dictionary, list: Array) -> Array:
	var why: Array = []
	var secs := float(h.secs)
	var skip := func(_i: int, d: Array) -> bool: return blocked(d, h, list)
	var long := secs >= 60.0
	var k1 := G.solo(h, G.KID_SHARE, false, skip)
	if k1.is_empty() or float(k1[0]) > secs * (0.7 if long else 0.9):
		why.append("keeping clear of the surprises, a small child can't finish the first dish (%s)" % str(k1))
	var k2 := G.solo(h, G.KID_SHARE, true, skip)
	if k2.is_empty() or float(k2[0]) > secs * (0.88 if long else 0.95):  # (the giant shakes plenty down too)
		why.append("with a giant, keeping clear, a small child can't finish the first dish (%s)" % str(k2))
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.z), float(e.dx), float(e.dz), float(e.warn), float(e.r),
		int(e.n), float(e.t)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 9 else {"kind": String(a[0]), "x": float(a[1]), "z": float(a[2]), "dx": float(a[3]), "dz": float(a[4]),
		"warn": float(a[5]), "r": float(a[6]), "n": int(a[7]), "t": float(a[8])}


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
	return PickOrbs.gift_choices(unlocked(pieces), last, seed_value)  # (the shared gift pick)


static func catch_r(gift_id: String) -> float:
	return BIG_CATCH if gift_id == "big" else PLAIN_CATCH


static func dish_bonus(gift_id: String) -> int:
	return GOLDEN_BONUS if gift_id == "golden" else DISH_BONUS


## The fall's pull and the wind's share with a gift (SLOW FALL lands every fruit where it would have).
static func fall_share(gift_id: String) -> float:
	return SLOW if gift_id == "slow" else 1.0


static func wind_share(gift_id: String) -> float:
	return sqrt(fall_share(gift_id))


# --- Nutmeg's pantry ------------------------------------------------------------------------------------------

static func pantry(dishes: int) -> int:
	return mini(PANTRY.size(), maxi(0, dishes) / PANTRY_EVERY)


## Where pantry piece i stands (world, on the grass): two rows of four beside the park, right of the giant.
static func pantry_spot(i: int) -> Vector3:
	return PANTRY_AT + Vector3(1.5 * float(i / 4), 0.0, (float(i % 4) - 1.5) * 1.5)


# --- The pick row ---------------------------------------------------------------------------------------------

## The orbs' places: by the giant (vr) or out on the grass (no giant).
static func row_spots(n: int = 3, vr: bool = true) -> Array:
	var xs: Array[float] = ROW_X if vr else FLAT_X
	var out: Array = []
	for i in n:
		var x: float = xs[i] if n == 3 else lerpf(xs[0], xs[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, ROW_Y if vr else FLAT_Y, ROW_Z if vr else FLAT_Z))
	return out


static func orb_scale(vr: bool) -> float:
	return ORB_SCALE if vr else FLAT_SCALE


## How near (across) a basket must come to an orb's middle.
static func tv_r(vr: bool) -> float:
	return TV_R if vr else FLAT_TV_R


## An orb's radius in the world.
static func orb_r(vr: bool = true) -> float:
	return PickOrbs.HIT_R * orb_scale(vr)
