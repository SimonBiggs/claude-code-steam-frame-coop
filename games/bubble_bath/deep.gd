extends RefCounted
## BUBBLE BATH second pass (pure data + small functions; tests/bubble_bath_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first round: Mama Duck's goal (a duck less / more), how often a warned surprise comes, how long it is
##             told first, how big it is and how hard it pushes.
##   GIFTS     MAMA DUCK'S GIFTS, three offered on the pick orbs before every round from the second: BIG TRAIN (tow 8
##             ducks), ZOOMY BOATS, BIG PLUG, DUCK MAGNET (ducks paddle to boats), then BUBBLE SHIELD (surprises can't
##             scatter your train) and GOLDEN TAP (two more golden ducks) as Mama's pond grows. A gift lasts the round.
##   SURPRISES warned by steady core/warn_rings.gd shapes on the water (each kind its own colour), never on a session's
##             first round, never in a round's first seconds, never two at once:
##               WALLY     a purple circle: Wally the squirty whale pops up there - big waves push every boat out and
##                         scatter a train caught inside (sail out of the circle!).
##               SHOWER    an orange band across the tub: the shower sprays along it and pushes boats and ducks.
##             hazards(p, spec) is the same list on every machine for a round; problems() proves it fair (told long
##             enough for a small kid sailing slowly to get out, the plug-hole never covered, inside the tub, and the
##             slow kid still reaches Mama Duck's goal even losing time to every surprise).
##   SEASONS   the bathroom is dressed for the season (SeasonKit props on the floor + drifting blossom / leaves / snow
##             through the open window); summer has more showers, autumn and winter more Wally.
##   POND      every POND_EVERY goals MAMA'S POND behind the tub gets a new piece (lily pads, a frog, a duck house, a
##             fountain ...: saved, for good). Pieces open new gifts.
##   PICK ROW  three orbs float just over the near rim, an arm's reach in front of the VR splasher; TV boats sail under
##             one, the splasher reaches into one on purpose (a hand moves in and stays a moment). Nobody in time = the
##             middle (it glows). With no splasher (flat host / local) bigger orbs stand over the open water (FLAT_*).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const BathGen := preload("res://games/bubble_bath/bathgen.gd")

const HX := BathGen.HX
const HZ := BathGen.HZ
const BOAT_R := BathGen.BOAT_R
const DRAIN_R := BathGen.DRAIN_R
const KID_SPEED := BathGen.KID_SPEED

## goal: ducks added to Mama Duck's goal; every: seconds between surprises; warn: seconds told first; whale_r: Wally's
## circle; spray_w: half the shower band's width; push: how hard waves and the shower push.
const MODES := {
	"gentle": {"goal": -1, "every": 30.0, "warn": 3.4, "whale_r": 0.9, "spray_w": 0.4, "push": 0.8},
	"brave": {"goal": 0, "every": 22.0, "warn": 2.9, "whale_r": 1.0, "spray_w": 0.5, "push": 1.0},
	"hard": {"goal": 1, "every": 16.0, "warn": 2.4, "whale_r": 1.15, "spray_w": 0.6, "push": 1.25},
}
const MIN_WARN := 2.0
const REACT := 0.6  # seconds a small kid takes to notice a tell and start sailing
const FIRST_ROUND := 2  # no surprises on a session's first round (one new thing at a time)
const FIRST_T := 15.0  # ... nor in a round's first seconds
const SHORT_FIRST := 3.0  # (bot rounds of 16 s: from 3 s)
const MIN_GAP := 8.0  # seconds between two surprises' tells
const WHALE_SECS := 1.6  # Wally splashes this long after the tell
const SPRAY_SECS := 2.4  # the shower sprays this long after the tell
const END_CALM := 5.0  # no surprise in a full round's last seconds
const LOST := 7.0  # seconds a surprise may cost a small kid (sailing out, picking ducks up again)
const KID_SHARE := 0.9  # the slow kid must still reach the goal in this share of the round, surprises and all
const WHALE_COLOR := Color(0.62, 0.32, 0.9)  # Wally purple
const SPRAY_COLOR := Color(1.0, 0.5, 0.18)  # shower orange
const KINDS: Array[String] = ["whale", "spray"]
const KIND_PICS := {"whale": "whale", "spray": "shower"}
const KIND_NAMES := {"whale": "WALLY!", "spray": "SHOWER!"}
const KIND_LINES := {"whale": "Wally's coming! Sail out!", "spray": "Shower! Sail out!"}
## Season -> surprise weights (whale, spray), the drifting things' colour, a picture, Mama Duck's line.
const SEASONS := {
	"spring": {"weights": [1.0, 1.0], "drift": Color(1.0, 0.75, 0.88), "pic": "daisy", "line": "A spring bath!"},
	"summer": {"weights": [0.7, 1.5], "drift": Color(1.0, 0.93, 0.5), "pic": "sunflower", "line": "A summer splash!"},
	"autumn": {"weights": [1.5, 0.7], "drift": Color(0.95, 0.5, 0.15), "pic": "acorn", "line": "Autumn leaves!"},
	"winter": {"weights": [1.3, 0.6], "drift": Color(1.0, 1.0, 1.0), "pic": "snowflake", "line": "A warm winter bath!"},
}
## Mama Duck's gifts: id, name, picture, a short line, a colour, pond pieces needed.
const GIFTS: Array[Dictionary] = [
	{"id": "train", "name": "BIG TRAIN", "pic": "ducktrain", "line": "Tow lots of ducks!", "color": Color(1.0, 0.86, 0.2), "unlock": 0},
	{"id": "zoomy", "name": "ZOOMY BOATS", "pic": "speedup", "line": "Zoom zoom!", "color": Color(0.35, 0.95, 0.55), "unlock": 0},
	{"id": "plug", "name": "BIG PLUG", "pic": "bigplug", "line": "A giant plug-hole!", "color": Color(0.45, 0.75, 1.0), "unlock": 0},
	{"id": "magnet", "name": "DUCK MAGNET", "pic": "duckmagnet", "line": "Ducks come to you!", "color": Color(1.0, 0.45, 0.75), "unlock": 0},
	{"id": "shield", "name": "BUBBLE SHIELD", "pic": "shieldbubble", "line": "Nothing can splash you!", "color": Color(0.7, 0.55, 1.0), "unlock": 2},
	{"id": "goldtap", "name": "GOLDEN TAP", "pic": "goldtap", "line": "More golden ducks!", "color": Color(1.0, 0.75, 0.1), "unlock": 4},
]
const BIG_TRAIN := 8  # BIG TRAIN: ducks a boat tows (plain: main.gd MAX_TRAIN 5)
const ZOOM_MAX := 3.6  # ZOOMY BOATS: top speed (plain 2.8)
const ZOOM_ACCEL := 9.5  # ... and pick-up (plain 7)
const BIG_PLUG_R := 0.8  # BIG PLUG: the plug-hole's radius (plain 0.55)
const MAGNET_R := 1.5  # DUCK MAGNET: floating ducks this near a boat with room paddle to it
const MAGNET_PULL := 1.1  # m/s
const GOLD_TAP := [0.08, 0.45]  # GOLDEN TAP: two more golden ducks at these shares of the round
## Mama's pond: one piece every POND_EVERY goals (every piece is also a story picture).
const POND_EVERY := 2
const POND: Array[String] = ["lily", "frog", "house", "fountain", "boat", "lighthouse", "butterfly", "rainbow"]
const POND_LINES := {"lily": "Lily pads!", "frog": "A froggy friend!", "house": "A duck house!", "fountain": "A fountain!",
	"boat": "A little sailboat!", "lighthouse": "A lighthouse!", "butterfly": "Butterflies!", "rainbow": "A rainbow!"}
const POND_AT := Vector3(2.9, 0.0, -5.6)  # behind the far rim, right of Mama Duck: seen over the tub from the TV and VR
const POND_HALF := Vector2(1.6, 1.0)  # the pond's water (an oval)
## Each piece's place from the pond's middle (POND order): in the water or on the bank round it.
const POND_SPOTS: Array[Vector2] = [Vector2(-0.6, 0.35), Vector2(1.9, 0.55), Vector2(-2.2, -0.3), Vector2(0.25, -0.2),
	Vector2(0.85, 0.4), Vector2(2.0, -0.85), Vector2(-1.6, 1.0), Vector2(0.0, -1.35)]
const POND_IN := {"lily": true, "fountain": true, "boat": true}  # pieces that float in the water
## The pick row: three orbs just over the near rim, an arm's reach in front of the splasher (clear of the tap at x -1.1).
const ROW_X: Array[float] = [-0.45, 0.05, 0.55]
const ROW_Y := 1.25
const ROW_Z := 2.35  # (a resting VR hand, 0.3 m ahead of the eyes, sits well behind the row: picks are on purpose)
const ORB_SCALE := 0.3
const HAND_R := 0.1  # a glove this near an orb's edge is in it
const DWELL := 0.3  # seconds a glove must stay in an orb (a hand sweeping past never picks)
const TV_R := 0.34  # a boat this near an orb's middle (across) sails under it
const TV_DWELL := 0.15
const FLAT_X: Array[float] = [-2.4, 0.0, 2.4]  # no splasher: big orbs over the open water, easy to see on a TV / Deck
const FLAT_Y := 1.6
const FLAT_Z := 0.4
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


## Mama Duck's goal for round plan p in a mode, for a full round (main.gd scales it for short test rounds).
static func goal_for(p: Dictionary, mode: String) -> int:
	return maxi(2, int(p.goal) + int(mode_data(mode).goal))


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["goal", "whale_r", "spray_w", "push"]:  # more is harder
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

## The surprises of round plan p: [{t, kind, x, z, dx, dz, warn, r}] by time. t: when the tell starts (round
## seconds); it goes off at t + warn. whale: a circle at (x, z) of radius r. spray: a band from (x, z) along (dx, dz)
## right across the tub, r = half its width. spec: {seed, mode, season, round (the session's round: none before
## FIRST_ROUND), secs (the round's length), first (bots: earlier), kid (the slow kid's seconds for the goal: the
## generator never adds a surprise that would make the goal too much for them)}.
static func hazards(p: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	if int(spec.get("round", FIRST_ROUND)) < FIRST_ROUND or p.is_empty():
		return out
	var mode := mode_of(String(spec.get("mode", "brave")))
	var md := mode_data(mode)
	var secs := float(spec.get("secs", BathGen.ROUND_SECS))
	var long := secs >= 60.0
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var r := Seeded.rng(int(spec.get("seed", 1)), "surprises %s" % mode)
	var every := float(md.every)
	var t := float(spec.get("first", FIRST_T if long else SHORT_FIRST)) + (r.randf_range(0.0, every * 0.4) if long else 0.0)
	var last_end := secs - (END_CALM if long else 1.0)
	var kid := float(spec.get("kid", 0.0))
	while t + float(md.warn) + span_after_tell("spray") <= last_end:
		if kid > 0.0 and kid + LOST * (out.size() + 1) > BathGen.ROUND_SECS * KID_SHARE:
			break  # (another surprise would make the goal too much for a slow kid)
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		for attempt in 20:
			var e := _make(r, kind, t, md)
			if _where_problem(p, e).is_empty():
				out.append(e)
				break
		t += every * r.randf_range(0.85, 1.2)
	return out


static func _make(r: RandomNumberGenerator, kind: String, t: float, md: Dictionary) -> Dictionary:
	var e := {"t": snappedf(t, 0.01), "kind": kind, "warn": float(md.warn), "push": float(md.push)}
	if kind == "whale":
		var rad := float(md.whale_r)
		e.merge({"x": snappedf(r.randf_range(-HX + rad + 0.25, HX - rad - 0.25), 0.01),
			"z": snappedf(r.randf_range(-HZ + rad + 0.25, HZ - rad - 0.25), 0.01), "dx": 0.0, "dz": 1.0, "r": rad}, true)
	else:
		var w := float(md.spray_w)
		var along_x := r.randf() < 0.6  # (the long way across the tub more often)
		var s := 1.0 if r.randf() < 0.5 else -1.0
		if along_x:
			e.merge({"x": -HX * s, "z": snappedf(r.randf_range(-HZ + w + 0.3, HZ - w - 0.3), 0.01), "dx": s, "dz": 0.0, "r": w}, true)
		else:
			e.merge({"x": snappedf(r.randf_range(-HX + w + 0.4, HX - w - 0.4), 0.01), "z": -HZ * s, "dx": 0.0, "dz": s, "r": w}, true)
	return e


## Seconds a kind lasts after its tell.
static func span_after_tell(kind: String) -> float:
	return WHALE_SECS if kind == "whale" else SPRAY_SECS


## Seconds from a surprise's tell to its end.
static func span(e: Dictionary) -> float:
	return float(e.warn) + span_after_tell(String(e.kind))


## How long a shower band is (wall to wall).
static func spray_len(e: Dictionary) -> float:
	return HX * 2.0 if absf(float(e.dx)) > 0.5 else HZ * 2.0


## Is point p (x, z) inside surprise e (pad: a boat's radius etc.)?
static func inside(e: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	if e.is_empty():
		return false
	var c := Vector2(float(e.x), float(e.z))
	if String(e.kind) == "whale":
		return p.distance_to(c) < float(e.r) + pad
	var dir := Vector2(float(e.dx), float(e.dz)).normalized()
	var q := p - c
	var along := q.dot(dir)
	return along > -pad and along < spray_len(e) + pad and absf(q.x * -dir.y + q.y * dir.x) < float(e.r) + pad


## Why surprise e is in a bad place on round plan p ("" = fine).
static func _where_problem(p: Dictionary, e: Dictionary) -> String:
	var drain: Vector2 = p.get("drain", Vector2.ZERO)
	var c := Vector2(float(e.x), float(e.z))
	if String(e.kind) == "whale":
		var rad := float(e.r)
		if absf(c.x) + rad > HX + 0.001 or absf(c.y) + rad > HZ + 0.001:
			return "Wally's circle pokes out of the tub"
		if c.distance_to(drain) < rad + DRAIN_R + BOAT_R + 0.1:
			return "Wally's circle covers the plug-hole"
		for o in p.get("islands", []):
			if c.distance_to(Vector2(o.x, o.y)) < float(o.z) + 0.25:
				return "Wally pops up inside a sponge island"
	else:
		if inside(e, drain, DRAIN_R + BOAT_R + 0.1):
			return "the shower covers the plug-hole"
		var far := c + Vector2(float(e.dx), float(e.dz)).normalized() * spray_len(e)
		if absf(far.x) > HX + 0.01 or absf(far.y) > HZ + 0.01 or absf(c.x) > HX + 0.01 or absf(c.y) > HZ + 0.01:
			return "the shower band runs outside the tub"
	return ""


## Reasons round plan p's surprises are unfair (empty = fine). spec as hazards().
static func problems(p: Dictionary, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var secs := float(spec.get("secs", BathGen.ROUND_SECS))
	var long := secs >= 60.0
	var first := float(spec.get("first", FIRST_T if long else SHORT_FIRST))
	if int(spec.get("round", FIRST_ROUND)) < FIRST_ROUND and not list.is_empty():
		why.append("surprises on the session's first round")
	var prev_end := -INF
	for e in list:
		var tag := "%s at %.1f s" % [e.get("kind", "?"), float(e.get("t", 0.0))]
		if not KINDS.has(String(e.get("kind", ""))):
			why.append("unknown surprise %s" % str(e))
			continue
		if float(e.t) < first - 0.001:
			why.append("%s: too early in the round" % tag)
		if float(e.t) + span(e) > secs - (END_CALM if long else 1.0) + 0.001:
			why.append("%s: runs into the round's end" % tag)
		if float(e.t) < prev_end:
			why.append("%s: two surprises at once" % tag)
		prev_end = float(e.t) + span(e)
		if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
			why.append("%s: told only %.1f s" % [tag, float(e.warn)])
		var where := _where_problem(p, e)
		if where != "":
			why.append("%s: %s" % [tag, where])
		# A slow kid in the very middle sails out (the whole boat) before it goes off.
		var out_secs := (float(e.r) + BOAT_R) / KID_SPEED + REACT
		if out_secs > float(e.warn):
			why.append("%s: a small kid can't sail out in time (%.1f s for %.1f s)" % [tag, out_secs, float(e.warn)])
	var kid := float(spec.get("kid", 0.0))
	if kid > 0.0 and kid + LOST * list.size() > BathGen.ROUND_SECS * KID_SHARE:
		why.append("a slow kid losing %.0f s to each of %d surprises can't reach the goal (%.0f s)" % [LOST, list.size(), kid])
	return why


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.z), float(e.dx), float(e.dz), float(e.warn), float(e.r),
		float(e.push), float(e.t)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 9 else {"kind": String(a[0]), "x": float(a[1]), "z": float(a[2]), "dx": float(a[3]), "dz": float(a[4]),
		"warn": float(a[5]), "r": float(a[6]), "push": float(a[7]), "t": float(a[8])}


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


static func gift_choices(pieces: int, last: String, seed_value: int) -> Array:
	return PickOrbs.gift_choices(unlocked(pieces), last, seed_value)  # (the shared gift pick)


static func train_max(gift_id: String, plain: int) -> int:
	return BIG_TRAIN if gift_id == "train" else plain


static func drain_r(gift_id: String) -> float:
	return BIG_PLUG_R if gift_id == "plug" else DRAIN_R


# --- Mama's pond ----------------------------------------------------------------------------------------------

static func pond(goals: int) -> int:
	return mini(POND.size(), maxi(0, goals) / POND_EVERY)


## Where pond piece i stands (world, on the bathroom floor; lily pads, the fountain and the sailboat in the water).
static func pond_spot(i: int) -> Vector3:
	if i < 0 or i >= POND_SPOTS.size():
		return Vector3.INF
	var s: Vector2 = POND_SPOTS[i]
	return POND_AT + Vector3(s.x, 0.0, s.y)


# --- The pick row ---------------------------------------------------------------------------------------------

static func row_spots(n: int = 3, vr: bool = true) -> Array:
	var xs: Array[float] = ROW_X if vr else FLAT_X
	var out: Array = []
	for i in n:
		var x: float = xs[i] if n == 3 else lerpf(xs[0], xs[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, ROW_Y if vr else FLAT_Y, ROW_Z if vr else FLAT_Z))
	return out


static func orb_scale(vr: bool) -> float:
	return ORB_SCALE if vr else FLAT_SCALE


static func tv_r(vr: bool) -> float:
	return TV_R if vr else FLAT_TV_R