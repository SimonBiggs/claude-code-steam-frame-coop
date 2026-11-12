extends RefCounted
## COASTER CREW second pass (pure data + small functions; tests/roller_coaster_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs after the practice
##             ride: from which ride warned park weather comes, how often, how many at once, how long a gust blows and
##             how long a sleepy cart naps before it wakes by itself.
##   GIFTS     BUTTONS' TRACK GIFTS, offered on the pick orbs before every ride from the third: BOOSTER (green arrows on a
##             straight bit: the train shoots off faster), CORKSCREW (rainbow hoops: the cars barrel-roll through),
##             SPLASH (water arches: a splash and a star for every rider), RAINBOW (a rainbow train for one ride) and,
##             once Buttons' toy fair has grown, BIG STARS (one ride of big easy stars). Track gifts stay on this coaster.
##   WEATHER   warned stretches of the ride, told by steady core/warn_rings.gd discs glowing along the track from the
##             moment the lever is pulled (and a picture card):
##               GUST    sky-blue discs: the wind blows there. Riders who keep their hands DOWN hold on: a star each.
##               SLEEPY  one lavender disc: the cart stops there for a nap (zzz). Hands UP wakes it (a star); it wakes
##                       by itself after `nap` seconds anyway - nobody is ever stuck.
##             weather(seed, ride, tr, mode, season, avoid) is the same list on every machine; problems() proves it fair
##             (never in the station, a loop or a splash, never on a track gift, never two touching, told long enough
##             before the train gets there, a sleepy stop only on a flat bit).
##   SEASONS   the table park is dressed for the season (Seeded.season): blossom / sunflowers / leaves / snow, the grass
##             tinted, things drifting down; autumn is windier, winter sleepier.
##   TOY FAIR  every FAIR_EVERY rides Buttons' toy fair grows on the living-room floor round the table: teacups, a swing
##             ride, a helter-skelter ... (saved for good; fair.gd). The VR builder sees it round their feet.
##   PICK ROW  three orbs float over the near edge of the table, at the VR builder's arm's reach (giant-sized). The VR
##             builder REACHES into one on purpose (a hand moves in and stays a moment); the pad builder and the riders
##             press X / A / B (their screen shows the pictures over the buttons). Nobody in time = the middle one.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const SeasonKit := preload("res://core/season_kit.gd")

## from: the first ride (1 = the practice ride) with weather; every: then every this many rides; most: weather stretches
## in one ride; gust: a gust's length (m of track); nap: seconds a sleepy cart naps before it wakes by itself; kinds.
const MODES := {
	"gentle": {"from": 4, "every": 2, "most": 1, "gust": 5.0, "nap": 2.0, "kinds": ["gust"]},
	"brave": {"from": 3, "every": 1, "most": 1, "gust": 6.5, "nap": 3.0, "kinds": ["gust", "sleepy"]},
	"hard": {"from": 3, "every": 1, "most": 2, "gust": 8.0, "nap": 4.0, "kinds": ["gust", "sleepy"]},
}
const KINDS: Array[String] = ["gust", "sleepy"]
const GUST_COLOR := Color(0.4, 0.82, 1.0)  # sky blue
const SLEEPY_COLOR := Color(0.72, 0.5, 1.0)  # lavender
const SLEEPY_LEN := 2.4  # the sleepy stretch (the cart stops in its middle)
const LEAD := 16.0  # weather starts at least this far past the station (told >= MIN_WARN s before the train is there)
const MIN_WARN := 2.0
const END_CLEAR := 6.0  # ... and ends this far before the lap ends
const GAP := 4.0  # plain track between two weather stretches (and round a loop, a splash or a gift)
const FLAT := 0.16  # a sleepy stop: the track's slope there (|forward.y|) at most this
const DISC_STEP := 1.6  # the gust discs' spacing along the track
const DISC_R := 0.75
const WAKE_V := 6.0  # a woken cart: off it goes
const BOOST_V := 12.5  # BOOSTER: the train leaves the booster at least this fast
const BIG_REACH := 1.8  # BIG STARS: the stars' reach (main.gd STAR_REACH 1.1)
const MAX_EXTRAS := 6  # track gifts on one coaster
const FIRST_GIFT_RIDE := 3  # gifts before rides 3, 4, ... (ride 2 follows the mode pick)
## Buttons' gifts: id, name, picture, a short line, colour, piece (stays on a bit of track), the toy fair needed.
const GIFTS: Array[Dictionary] = [
	{"id": "booster", "name": "BOOSTER", "pic": "speedup", "line": "Zoom!", "color": Color(0.35, 0.95, 0.45), "piece": true, "unlock": 0},
	{"id": "corkscrew", "name": "CORKSCREW", "pic": "corkscrew", "line": "Twisty!", "color": Color(1.0, 0.5, 0.85), "piece": true, "unlock": 0},
	{"id": "splash", "name": "SPLASH", "pic": "splashpool", "line": "Splash!", "color": Color(0.35, 0.7, 1.0), "piece": true, "unlock": 0},
	{"id": "rainbow", "name": "RAINBOW", "pic": "rainbow", "line": "Rainbow ride!", "color": Color(1.0, 0.75, 0.3), "piece": false, "unlock": 0},
	{"id": "bigstars", "name": "BIG STARS", "pic": "star", "line": "Big stars!", "color": Color(1.0, 0.9, 0.35), "piece": false, "unlock": 2},
]
## Which piece types each track gift sits on.
const GIFT_ON := {"booster": ["straight", "down"], "corkscrew": ["straight"], "splash": ["straight", "down", "up"]}
## Seasons: weather weights, the drift colour, the grass tint, a picture, Buttons' line.
const SEASONS := {
	"spring": {"weights": {"gust": 1.0, "sleepy": 1.0}, "drift": Color(1.0, 0.72, 0.85), "grass": Color(0.48, 0.76, 0.38), "pic": "daisy", "line": "Spring park!"},
	"summer": {"weights": {"gust": 0.8, "sleepy": 1.2}, "drift": Color(1.0, 0.93, 0.5), "grass": Color(0.56, 0.78, 0.3), "pic": "sunflower", "line": "Summer park!"},
	"autumn": {"weights": {"gust": 1.7, "sleepy": 0.8}, "drift": Color(0.95, 0.5, 0.15), "grass": Color(0.66, 0.66, 0.3), "pic": "acorn", "line": "Windy autumn!"},
	"winter": {"weights": {"gust": 1.0, "sleepy": 1.6}, "drift": Color(1.0, 1.0, 1.0), "grass": Color(0.8, 0.88, 0.92), "pic": "snowflake", "line": "Snowy park!"},
}
## Buttons' toy fair on the living-room floor: one ride every FAIR_EVERY coaster rides.
const FAIR_EVERY := 3
const FAIR: Array[String] = ["teacups", "swings", "helter", "droptower", "pirate", "bumper", "rocketride", "bigtop"]
const FAIR_PICS := {"teacups": "teacup", "swings": "carousel", "helter": "helter", "droptower": "droptower", "pirate": "boat",
	"bumper": "boat", "rocketride": "rocket", "bigtop": "tent"}
## The pick row (main.gd space, giant-sized: builder.gd WS = 18 park m per real m): over the near table edge at the VR
## builder's arm's reach.
const WS := 18.0
const ROW_AT := Vector3(0.0, 9.4, 6.6)
const ROW_GAP := 0.27 * WS  # (a hand is never in two orbs at once: tests/roller_coaster_deep_test.gd)
const ORB_SCALE := 0.11 * WS  # (a modest 13 cm glass ball in the builder's hands)
const HAND_R := 0.05 * WS
const DWELL := 0.35
const WAIT := {"mode": 12.0, "gift": 9.0}
const WAIT_SOLO := 6.0


static func mode_of(id: String) -> Dictionary:
	var m := String(PickOrbs.mode(id).get("id", id))
	return MODES.get(m, MODES.brave)


static func mode_id(id: String) -> String:
	var m := String(PickOrbs.mode(id).get("id", id))
	return m if MODES.has(m) else "brave"


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


static func fair_count(rides: int) -> int:
	return clampi(rides / FAIR_EVERY, 0, FAIR.size())


## Seconds to pick.
static func wait_for(stage: String, solo: bool) -> float:
	return WAIT_SOLO if solo else float(WAIT.get(stage, 9.0))


## The pick row's spots (main.gd space).
static func row(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(ROW_AT + Vector3((i - (n - 1) * 0.5) * ROW_GAP, 0.0, 0.0))
	return out


# --- Track gifts ------------------------------------------------------------------------------------------------

## The piece a track gift goes on (-1: nowhere): the newest piece of the right type with no gift yet.
static func gift_spot(pieces: Array, extras: Array, kind: String) -> int:
	if not GIFT_ON.has(kind) or extras.size() >= MAX_EXTRAS:
		return -1
	var used := {}
	for e in extras:
		used[int(e[0])] = true
	for i in range(pieces.size() - 1, 2, -1):  # (never on the practice pieces: the station's run-out)
		if not used.has(i) and (GIFT_ON[kind] as Array).has(String((pieces[i] as Array)[0])):
			return i
	return -1


## Up to three gifts to offer before ride `ride` (seeded; only gifts that fit somewhere on this track).
static func offer(seed_value: int, ride: int, pieces: Array, extras: Array, fair: int) -> Array:
	var r := Seeded.rng(seed_value, "gifts%d" % ride)
	var can: Array = []
	for g in GIFTS:
		if int(g.unlock) > fair:
			continue
		if bool(g.piece) and gift_spot(pieces, extras, String(g.id)) < 0:
			continue
		can.append(String(g.id))
	var out: Array = []
	while out.size() < 3 and not can.is_empty():
		out.append(can.pop_at(r.randi() % can.size()))
	return out


## The track's gift stretches: [[s0, s1, kind], ...] (polyline distances).
static func gift_ranges(tr: Dictionary, extras: Array) -> Array:
	var out: Array = []
	var ps: Array = tr.get("piece_s", [])
	for e in extras:
		var i := int(e[0])
		if i < 0 or i >= ps.size():
			continue
		var s0 := float(ps[i - 1]) if i > 0 else Track.STATION_LEN
		out.append([s0, float(ps[i]), String(e[1])])
	return out


# --- Weather ----------------------------------------------------------------------------------------------------

## Ride `ride`'s (1 = the practice ride) warned weather: [{kind, s0, s1}] in lap distance, the same on every machine.
## avoid: [[s0, s1, ...]] stretches to keep clear of (the track gifts).
static func weather(seed_value: int, ride: int, tr: Dictionary, mode: String, season: String, avoid: Array = []) -> Array:
	var m := mode_of(mode)
	if tr.is_empty() or ride < int(m.from) or (ride - int(m.from)) % int(m.every) != 0:
		return []
	var r := Seeded.rng(seed_value, "weather%d" % ride)
	var w: Dictionary = season_data(season).weights
	var length: float = tr.length
	var lo := LEAD
	var hi := length - END_CLEAR
	var out: Array = []
	var want := 1 + (r.randi() % int(m.most))
	for n in want:
		var kinds: Array = m.kinds
		var total := 0.0
		for k in kinds:
			total += float(w.get(k, 1.0))
		var pickv := r.randf() * total
		var kind := String(kinds[0])
		for k in kinds:
			pickv -= float(w.get(k, 1.0))
			if pickv <= 0.0:
				kind = String(k)
				break
		var len_k := float(m.gust) if kind == "gust" else SLEEPY_LEN
		for attempt in 24:
			var s0 := r.randf_range(lo, maxf(lo, hi - len_k))
			var e := {"kind": kind, "s0": snappedf(s0, 0.01), "s1": snappedf(s0 + len_k, 0.01)}
			if _fits(e, tr, out, avoid):
				out.append(e)
				break
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.s0) < float(b.s0))
	return out


static func _fits(e: Dictionary, tr: Dictionary, others: Array, avoid: Array) -> bool:
	return _why(e, tr, others, avoid) == ""


## Why a weather stretch is unfair here ("" = fine).
static func _why(e: Dictionary, tr: Dictionary, others: Array, avoid: Array) -> String:
	var s0 := float(e.s0)
	var s1 := float(e.s1)
	var length: float = tr.length
	if s0 < LEAD or s1 > length - END_CLEAR:
		return "too near the station (%.1f-%.1f of %.1f)" % [s0, s1, length]
	for rg in (tr.loops as Array) + (tr.splashes as Array) + avoid:
		if s1 + GAP > float(rg[0]) and s0 - GAP < float(rg[1]):
			return "touches a loop, a splash or a gift (%.1f-%.1f)" % [s0, s1]
	for o in others:
		if o == e:
			continue
		if s1 + GAP > float(o.s0) and s0 - GAP < float(o.s1):
			return "two weather stretches touch (%.1f, %.1f)" % [s0, float(o.s0)]
	if String(e.kind) == "sleepy":
		var xf := Track.sample(tr, stop_s(e))
		if absf(xf.basis.z.y) > FLAT:
			return "a sleepy stop on a slope (%.2f)" % xf.basis.z.y
	return ""


## Where a sleepy cart stops (the train's front car).
static func stop_s(e: Dictionary) -> float:
	return (float(e.s0) + float(e.s1)) * 0.5


## Why a ride's weather is unfair (empty = fine): every stretch fair, told long enough before the train gets there
## (the train leaves the station at 5 m/s and is never faster than 15 m/s), within the mode's count.
static func problems(list: Array, tr: Dictionary, mode: String, avoid: Array = []) -> Array:
	var out: Array = []
	var m := mode_of(mode)
	if list.size() > int(m.most):
		out.append("%d stretches (most %d)" % [list.size(), int(m.most)])
	for e in list:
		if not (m.kinds as Array).has(String(e.kind)):
			out.append("%s in %s" % [String(e.kind), mode])
		var why := _why(e, tr, list, avoid)
		if why != "":
			out.append(why)
		if float(e.s0) - Track.STATION_LEN < MIN_WARN * 5.0:  # (the train leaves the station at 5 m/s; the test rides it for real)
			out.append("told too late (%.1f m)" % float(e.s0))
	return out


## Modes get harder in order: Gentle <= Brave <= Hard (empty = fine).
static func mode_order_problems() -> Array:
	var out: Array = []
	var ids := ["gentle", "brave", "hard"]
	for i in 2:
		var a: Dictionary = MODES[ids[i]]
		var b: Dictionary = MODES[ids[i + 1]]
		if int(a.from) < int(b.from) or int(a.every) < int(b.every) or int(a.most) > int(b.most) \
				or float(a.gust) > float(b.gust) or float(a.nap) > float(b.nap):
			out.append("%s is harder than %s" % [ids[i], ids[i + 1]])
		for k in a.kinds:
			if not (b.kinds as Array).has(k):
				out.append("%s has %s but %s doesn't" % [ids[i], k, ids[i + 1]])
	return out
