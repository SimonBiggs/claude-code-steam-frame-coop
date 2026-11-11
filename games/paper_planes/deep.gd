extends RefCounted
## PAPER PLANES second pass (pure data + small functions; tests/paper_planes_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs: how many warned
##             sky events a flight, how long they are told first, how hard a gust pushes and for how long, whether a
##             goose bump costs the combo, and how many points the stars ask for.
##   FOLDS     PIP'S PAPER FOLDS, offered on the pick orbs before every flight (fly into one, or throw a plane at it),
##             with TODAY'S SKY as the fourth orb: GLIDER (slow and floaty: hoops drift less, VR planes glide further),
##             DART (fast, and a strong pull to the next hoop), STUNT (loop-de-loops and a long combo), then RAINBOW
##             (more rainbow hoops), SWALLOW (big hoops) and COMET (more time) open as Pip's hangar grows. Each fold
##             is one of the first pass's breezes underneath (main.gd _breeze()), plus its own speed and shape.
##   EVENTS    told first by core/warn_rings.gd STANDING UP in the sky (hazards.gd), facing the VR deck and the TV:
##               GUST   white rings round a patch of sky with streaks blowing sideways: then the wind blows any plane
##                      in it that way for a moment.
##               GEESE  a long band across the sky: then a line of geese flies along it. A plane in the band bumps
##                      (a loop-de-loop; BRAVE / HARD: the combo is lost too).
##             events(seed, spec) is the same list on every machine; problems() proves it fair (inside the sky the
##             planes fly in, never at the VR deck, never at the start of a flight, never two at once, always time
##             to fly out while told, a gust never pushes a plane out of the sky).
##   SEASONS   Seeded.season(): blossom, sunny seeds, leaves or snow drift over the valley; the season leans the events
##             (geese come back in spring, autumn and winter are windy).
##   HANGAR    every HANGAR_EVERY stamps (stars ever won), Pip's hangar beyond the valley gets a new piece (the shed,
##             then paper planes parked in front, a windsock, then planes circling high overhead: a sky trail).
##             Saved for good (it is counted from the stamps). Every piece stands out of the sky the planes fly in.
##   PICK ROW  three or four big orbs in an arc in the sky in front of the VR deck (row_spots): a TV plane flies into
##             one, a VR plane is thrown into one (never a resting hand); nobody by the wait: the middle one.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const SkyGen := preload("res://games/paper_planes/skygen.gd")

## events: warned events a flight (100 s); warn: seconds told first; push: a gust's push (m/s); gust: seconds it blows;
## bump: 1 = a goose bump loses the combo; goals: share of the star goals (points).
const MODES := {
	"gentle": {"events": 2, "warn": 4.5, "push": 1.6, "gust": 1.6, "bump": 0, "goals": 0.8},
	"brave": {"events": 3, "warn": 3.6, "push": 2.2, "gust": 2.0, "bump": 1, "goals": 1.0},
	"hard": {"events": 4, "warn": 3.0, "push": 2.6, "gust": 2.3, "bump": 1, "goals": 1.2},
}
const MIN_WARN := 2.4
const REACT := 0.8  # seconds a pilot needs to see a tell and steer
const FLY_SPEED := 6.5  # == main.gd FLY_SPEED (the slowest fold flies at SLOWEST of it)
const SLOWEST := 0.85
const CLIMB := 0.6  # sin(main.gd PITCH_MAX): share of the speed a plane can climb / dive at
const PLANE_R := 0.3  # a plane's size for bumps
const STAY := 2.4  # seconds a gust blows / the geese fly after the tell (gust: the mode's own secs)
const FIRST_T := 12.0  # seconds into a flight before the first tell
const SPACING := 14.0  # seconds between tells (plus up to JITTER)
const JITTER := 5.0
const GAP := 3.0  # at least this between one finishing and the next tell
const END_CLEAR := 3.0  # every event is over this long before the flight ends
const GUST_R := 2.4  # a gust's patch of sky (radius)
const GEESE_W := 1.6  # a geese band's height
const GEESE_DEPTH := 1.4  # ... and how deep (along z) the geese fly
const GEESE_N := 6
const DECK_CLEAR := 4.0  # metres between any event and the VR player's head (planes leave the hand there)
const MAX_DRIFT := 6.0  # a gust never pushes a plane further than this
const GUST_COLOR := Color(0.8, 0.95, 0.2)  # lime: "wind!" (never the gold of a pick or a hoop)
const GEESE_COLOR := Color(0.9, 0.1, 0.15)  # deep red: "look out!"
const GOOSE_BODY := Color(0.42, 0.33, 0.27)  # a brown goose (the white geese vanished on winter skies)
const GOOSE_NECK := Color(0.12, 0.12, 0.14)
const KINDS: Array[String] = ["gust", "geese"]
## Season -> event weights (gust, geese), the drifting things' colour, a picture, Pip's line.
const SEASONS := {
	"spring": {"weights": [0.8, 1.4], "drift": Color(1.0, 0.72, 0.85), "pic": "daisy", "line": "Blossom skies! Geese are back!", "name": "spring"},
	"summer": {"weights": [1.0, 1.0], "drift": Color(1.0, 0.95, 0.75), "pic": "sunflower", "line": "Sunny skies!", "name": "summer"},
	"autumn": {"weights": [1.5, 0.8], "drift": Color(0.95, 0.5, 0.15), "pic": "acorn", "line": "Windy autumn skies!", "name": "autumn"},
	"winter": {"weights": [1.4, 0.6], "drift": Color(1.0, 1.0, 1.0), "pic": "snowflake", "line": "Snowy skies!", "name": "winter"},
}
## Pip's folds: id, name, picture, line, colour, hangar pieces needed, the breeze underneath (main.gd), speed, the
## plane's shape (x: wingspan, z: length), how a VR plane falls (share of the usual gravity).
const FOLDS: Array[Dictionary] = [
	{"id": "glider", "name": "GLIDER", "pic": "glider", "line": "Float and glide!", "color": Color(0.5, 0.85, 1.0), "unlock": 0,
		"breeze": "slow", "speed": 0.85, "shape": Vector3(1.4, 1.0, 0.9), "fall": 0.7},
	{"id": "dart", "name": "DART", "pic": "paperdart", "line": "Zoom zoom!", "color": Color(1.0, 0.55, 0.3), "unlock": 0,
		"breeze": "magnet", "speed": 1.2, "shape": Vector3(0.75, 1.0, 1.3), "fall": 1.0},
	{"id": "stunt", "name": "STUNT", "pic": "stuntplane", "line": "Loop the loop!", "color": Color(0.75, 0.55, 1.0), "unlock": 0,
		"breeze": "streak", "speed": 1.0, "shape": Vector3(1.1, 1.0, 1.0), "fall": 1.0},
	{"id": "rainbow", "name": "RAINBOW", "pic": "rainbow", "line": "Rainbows everywhere!", "color": Color(1.0, 0.8, 0.3), "unlock": 2,
		"breeze": "lucky", "speed": 1.0, "shape": Vector3(1.0, 1.0, 1.0), "fall": 1.0},
	{"id": "swallow", "name": "SWALLOW", "pic": "swallowplane", "line": "Big hoops!", "color": Color(0.45, 0.9, 0.5), "unlock": 4,
		"breeze": "big", "speed": 1.0, "shape": Vector3(1.25, 1.0, 1.1), "fall": 0.9},
	{"id": "comet", "name": "COMET", "pic": "starrain", "line": "More time!", "color": Color(1.0, 0.6, 0.75), "unlock": 6,
		"breeze": "tail", "speed": 1.1, "shape": Vector3(0.9, 1.0, 1.15), "fall": 1.0},
]
const DAILY := "daily"
const DAILY_ENTRY := {"id": "daily", "name": "TODAY'S SKY", "pic": "sun", "color": Color(0.45, 0.85, 1.0)}
## Pip's hangar: one piece every HANGAR_EVERY stamps.
const HANGAR_EVERY := 3
const HANGAR: Array[String] = ["shed", "plane", "plane", "windsock", "plane", "plane", "flag", "plane", "trail", "trail",
	"plane", "trail", "trail", "plane", "trail", "trail"]
const HANGAR_AT := Vector3(4.0, 0.0, -27.0)  # the shed's middle (ground), beyond the valley, between the places
const HANGAR_YAW := 0.15
const TRAIL_AT := Vector3(0.0, 13.5, -12.0)  # the sky trail circles round this, over the sky the planes fly in
const TRAIL_R := 9.0
## The pick row: big orbs in an arc in the sky in front of the VR deck.
const ROW_R := 10.2  # metres from the VR head (flat)
const ROW_ANGLE := 0.52  # radians between orbs (seen from the VR deck)
const ROW_Y := 2.8  # the middle orb's height (the outer ones dip a little): under the sky scoreboard and the VR story card
const ORB_SCALE := 2.2
const CATCH := 0.35  # a plane this near an orb's edge takes it
const ROW_WAIT := 14.0  # nobody took one: the middle after this (main.gd pick_time)


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["events", "push", "gust", "bump", "goals"]:  # more of these is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	if not (float(g.warn) >= float(b.warn) and float(b.warn) >= float(h.warn)):
		out.append("warn not most on gentle")
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if int(g.bump) != 0:
		out.append("gentle geese cost the combo")
	for m in MODES:
		if float(MODES[m].push) * float(MODES[m].gust) > MAX_DRIFT:
			out.append("%s: a gust pushes too far" % m)
	return out


# --- Events ------------------------------------------------------------------------------------------------

## This flight's events: [{kind, t, pos, dir, size, sign}] in time order. t: seconds into the flight its tell starts;
## pos: a gust's middle / the geese band's middle; dir: the way it blows / they fly (+x * sign); size: a gust's
## radius / Vector2(band length, GEESE_W). spec: {mode, season, secs (the flight's length), scale (bots: more),
## first (bots: an earlier first tell)}.
static func events(seed_value: int, spec: Dictionary) -> Array:
	var out: Array = []
	var r := Seeded.rng(seed_value, "sky events")
	var md := mode_data(String(spec.get("mode", "brave")))
	var secs := float(spec.get("secs", 100.0))
	var want := maxi(1, roundi(float(md.events) * float(spec.get("scale", 1.0)) * secs / 100.0))
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var t := float(spec.get("first", FIRST_T)) + r.randf() * JITTER
	for i in want:
		if t + float(md.warn) + _stay(md) + END_CLEAR > secs:
			break
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		var e := _place(r, kind, md)
		if e.is_empty():
			e = _place(r, "gust" if kind == "geese" else "geese", md)
		if e.is_empty():
			continue
		e.t = snappedf(t, 0.01)
		out.append(e)
		t += maxf(SPACING, float(md.warn) + _stay(md) + GAP) + r.randf() * JITTER
	return out


static func _stay(md: Dictionary) -> float:
	return maxf(STAY, float(md.gust))


## One event, or {} when none fits (a few tries).
static func _place(r: RandomNumberGenerator, kind: String, md: Dictionary) -> Dictionary:
	for attempt in 12:
		var e := {}
		var sgn := -1 if r.randf() < 0.5 else 1
		if kind == "gust":
			var p := Vector3(r.randf_range(SkyGen.BOX_MIN.x + 0.5, SkyGen.BOX_MAX.x - 0.5), r.randf_range(SkyGen.BOX_MIN.y + 0.8, SkyGen.BOX_MAX.y),
				r.randf_range(SkyGen.BOX_MIN.z, SkyGen.BOX_MAX.z - 2.0))
			e = {"kind": "gust", "t": 0.0, "pos": _snap(p), "dir": Vector3.RIGHT * sgn, "size": Vector2(GUST_R, 0.0), "sign": sgn}
		else:
			var y := r.randf_range(SkyGen.FLY_MIN.y + 1.5, SkyGen.FLY_MAX.y - 2.5)
			var z := r.randf_range(SkyGen.BOX_MIN.z, SkyGen.BOX_MAX.z - 4.0)
			var length := SkyGen.FLY_MAX.x - SkyGen.FLY_MIN.x
			e = {"kind": "geese", "t": 0.0, "pos": _snap(Vector3(0.0, y, z)), "dir": Vector3.RIGHT * sgn, "size": Vector2(length, GEESE_W), "sign": sgn}
		if _event_problems(e, md).is_empty():
			return e
	return {}


static func _snap(p: Vector3) -> Vector3:
	return Vector3(snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01))


## Reasons one event is unfair (empty = fine).
static func _event_problems(e: Dictionary, md: Dictionary) -> Array:
	var why: Array = []
	var p: Vector3 = e.pos
	var warn := float(md.warn)
	var slow := FLY_SPEED * SLOWEST
	match String(e.kind):
		"gust":
			var rad := float((e.size as Vector2).x)
			for ax in 3:
				if p[ax] - rad < SkyGen.FLY_MIN[ax] - 0.01 or p[ax] + rad > SkyGen.FLY_MAX[ax] + 0.01:
					why.append("a gust pokes out of the sky (%.1f, %.1f, %.1f)" % [p.x, p.y, p.z])
					break
			if p.distance_to(SkyGen.VR_HEAD) < rad + DECK_CLEAR:
				why.append("a gust at the VR deck")
			# Pushed for the whole gust from anywhere in it, a plane stays inside the sky it flies in.
			var drift := float(md.push) * float(md.gust)
			if drift > MAX_DRIFT:
				why.append("a gust pushes %.1f m" % drift)
			if absf(p.x) + rad + drift > SkyGen.FLY_MAX.x + 3.0:
				why.append("a gust pushes a plane out of the sky")
			# A plane never stops: it crosses the patch in time, whichever way it flies.
			if (2.0 * rad + PLANE_R) / slow > warn - REACT + _stay(md):
				why.append("a gust too big to fly through")
		"geese":
			var sz: Vector2 = e.size
			var half := sz.y * 0.5
			if p.y - half < SkyGen.FLY_MIN.y + 0.3 or p.y + half > SkyGen.FLY_MAX.y - 0.3:
				why.append("geese at the edge of the sky (y %.1f)" % p.y)
			if p.z - GEESE_DEPTH < SkyGen.FLY_MIN.z or p.z + GEESE_DEPTH > SkyGen.FLY_MAX.z:
				why.append("geese out of the sky (z %.1f)" % p.z)
			if absf(p.z - SkyGen.VR_HEAD.z) < DECK_CLEAR + GEESE_DEPTH:
				why.append("geese over the VR deck")
			# Climbing or diving out of the band in time (a plane flying along it still has to leave it).
			if (half + PLANE_R) / (slow * CLIMB) > warn - REACT:
				why.append("no time to fly out of the geese")
			# Room above and below the band to fly.
			if (p.y - half) - SkyGen.FLY_MIN.y < 1.0 and SkyGen.FLY_MAX.y - (p.y + half) < 1.0:
				why.append("geese fill the sky")
		_:
			why.append("an unknown event %s" % str(e.kind))
	if warn < MIN_WARN:
		why.append("told only %.1f s early" % warn)
	return why


## Reasons this flight's events are unfair (empty = fine).
static func problems(list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var secs := float(spec.get("secs", 100.0))
	var last_end := -INF
	for e in list:
		if float(e.t) < float(spec.get("first", FIRST_T)) - 0.01:
			why.append("a tell %.1f s into the flight" % float(e.t))
		if float(e.t) < last_end + GAP - 0.01:
			why.append("two events at once (%.1f s)" % float(e.t))
		last_end = float(e.t) + float(md.warn) + _stay(md)
		if last_end + END_CLEAR > secs + 0.01:
			why.append("an event still going when the flight ends")
		for x in _event_problems(e, md):
			why.append(x)
	return why


## Is a plane at p caught by event e (while it goes off)? pad: extra metres (bots keep clear).
static func caught(e: Dictionary, p: Vector3, pad: float = 0.0) -> bool:
	var c: Vector3 = e.pos
	if String(e.kind) == "gust":
		return p.distance_to(c) <= float((e.size as Vector2).x) + pad
	var sz: Vector2 = e.size
	return absf(p.y - c.y) <= sz.y * 0.5 + PLANE_R + pad and absf(p.z - c.z) <= GEESE_DEPTH + pad and absf(p.x - c.x) <= sz.x * 0.5 + pad


## Seconds an event goes off for after its tell.
static func stay_of(e: Dictionary, mode_id: String) -> float:
	var md := mode_data(mode_id)
	return float(md.gust) if String(e.kind) == "gust" else STAY


## An event as plain values for the network (and back).
static func pack(e: Dictionary) -> Array:
	return [String(e.kind), float(e.t), e.pos, e.dir, e.size, int(e.sign)]


static func unpack(a: Array) -> Dictionary:
	return {"kind": String(a[0]), "t": float(a[1]), "pos": a[2], "dir": a[3], "size": a[4], "sign": int(a[5])}


# --- Folds ----------------------------------------------------------------------------------------------------

static func unlocked(pieces: int) -> Array:
	var out: Array = []
	for f in FOLDS:
		if pieces >= int(f.unlock):
			out.append(String(f.id))
	return out


static func fold(id: String) -> Dictionary:
	for f in FOLDS:
		if String(f.id) == id:
			return f
	return {}


## The breeze a fold flies with ("" = none: TODAY'S SKY or no fold).
static func breeze_of(id: String) -> String:
	return String(fold(id).get("breeze", ""))


## Three different unlocked folds: the newest unlock always among them, not the last one again when there are others
## (the same on every machine for a seed).
static func fold_choices(pieces: int, last: String, seed_value: int) -> Array:
	var un := unlocked(pieces)
	var newest: String = un[un.size() - 1]
	var pool: Array = []
	for id in un:
		if id != newest and (id != last or un.size() <= 3):
			pool.append(id)
	pool = Seeded.shuffled(Seeded.rng(seed_value, "folds"), pool)
	var out: Array = [newest] if newest != last or un.size() <= 3 else []
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	if out.size() < 3:
		for id in un:
			if out.size() < 3 and not out.has(id):
				out.append(id)
	return Seeded.shuffled(Seeded.rng(seed_value, "fold order"), out)


# --- Pip's hangar ----------------------------------------------------------------------------------------------

static func hangar(stamps: int) -> int:
	return mini(HANGAR.size(), maxi(0, stamps) / HANGAR_EVERY)


## Where hangar piece i stands (world): the shed, parked planes in rows in front of it, a windsock and a flag beside
## it; "trail" pieces circle high over the valley (their place at time 0; main.gd turns them round TRAIL_AT).
static func hangar_spot(i: int) -> Vector3:
	var kind := HANGAR[clampi(i, 0, HANGAR.size() - 1)]
	var b := Basis(Vector3.UP, HANGAR_YAW)
	match kind:
		"shed":
			return HANGAR_AT
		"windsock":
			return HANGAR_AT + b * Vector3(-6.0, 0.0, 1.0)
		"flag":
			return HANGAR_AT + b * Vector3(6.0, 0.0, 1.0)
		"trail":
			var k := _count_before(i, "trail")
			var a := TAU * float(k) / 6.0
			return TRAIL_AT + Vector3(cos(a) * TRAIL_R, (k % 2) * 0.8, sin(a) * TRAIL_R)
	var n := _count_before(i, "plane")  # parked planes: two rows of four in front of the shed
	return HANGAR_AT + b * Vector3((n % 4 - 1.5) * 2.2, 0.0, 4.6 + (n / 4) * 2.2)


static func _count_before(i: int, kind: String) -> int:
	var n := 0
	for k in i:
		if HANGAR[k] == kind:
			n += 1
	return n


# --- The pick row ---------------------------------------------------------------------------------------------

## Where the row's n orbs float (world): an arc in front of the VR deck, inside the sky the TV planes fly in.
static func row_spots(n: int) -> Array:
	var out: Array = []
	for i in n:
		var off := (i - (n - 1) * 0.5) * ROW_ANGLE
		var p := SkyGen.VR_HEAD + Vector3(sin(off) * ROW_R, 0.0, -cos(off) * ROW_R)
		out.append(Vector3(snappedf(p.x, 0.01), ROW_Y - absf(off) * 0.6, snappedf(p.z, 0.01)))
	return out


## How near a plane's middle must come to an orb's middle to take it.
static func catch_r() -> float:
	return PickOrbs.HIT_R * ORB_SCALE + CATCH
