extends RefCounted
## ROCKET WORKSHOP second pass (pure data + small functions; tests/rocket_workshop_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs after the
##             practice rocket: how many meteors a rocket, how long they are told first, how big they are, how long a
##             bumped crew member is dizzy, how long Sprocket's ghost hand waits before it helps, and (HARD) one more
##             desk puzzle on the bigger rockets.
##   GIFTS     SPROCKET'S PART GIFTS, offered on the pick orbs before every rocket from rocket 3 (the pilot touches
##             one at the desk, a crew member walks up to the desk under one): BOOSTERS (one puzzle fewer, and the
##             rocket wears boosters), FINS (calm skies: fewer meteors, told longer; swept fins), PARACHUTE (Sprocket
##             helps sooner, on every rocket; a parachute pack on the nose), then SHIELD (meteors bounce off a bubble)
##             opens when the family has launched enough rockets. The gift's part stays on the model on Rocket Row.
##   METEORS   told first by core/warn_rings.gd on the workshop floor (hazards.gd), steady, never flashing:
##               METEOR  one big pink ring: a space rock lands in it (a crew member inside gets bumped and dizzy).
##               SHOWER  three small blue rings at once: three little rocks.
##             events(seed, spec) is the same list on every machine; problems() proves it fair (on the workshop floor,
##             never at the desk or where the crew spawn, never in the first seconds of a rocket, never two at once,
##             always time to walk out while told, room to walk between a shower's rings).
##   SEASONS   Seeded.season() dresses the launch site: the yard's ground, drifting blossom / seeds / leaves / snow,
##             and leans the meteors (autumn is shooting-star season).
##   SOLO      a lone pilot (solo VR, a lone Deck, a flat host) still picks the mode and the gifts at the desk, and
##             every gift and mode changes the pilot's own rockets; meteors only fall when there is crew on the floor.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Crew := preload("res://games/rocket_workshop/player.gd")
const P := preload("res://games/rocket_workshop/puzzles.gd")
const G := preload("res://games/rocket_workshop/rocketgen.gd")

## events: meteor tells a rocket; warn: seconds told first; size: a meteor's ring (m); dizzy: seconds a bumped crew
## member wobbles; push: how hard they are bumped out (m/s); help: seconds the pilot waits before Sprocket's ghost
## hand shows a teaching control; late: 1 = the ghost hand still helps after the teaching rockets; extra: more desk
## puzzles on the bigger rockets.
const MODES := {
	"gentle": {"events": 1, "warn": 5.0, "size": 1.25, "dizzy": 0.6, "push": 2.5, "help": 3.0, "late": 1, "extra": 0},
	"brave": {"events": 2, "warn": 4.2, "size": 1.45, "dizzy": 1.0, "push": 3.2, "help": 4.5, "late": 0, "extra": 0},
	"hard": {"events": 3, "warn": 3.4, "size": 1.65, "dizzy": 1.4, "push": 4.0, "help": 6.0, "late": 0, "extra": 1},
}
const MIN_WARN := 3.0
const REACT := 1.0  # seconds a little one needs to see a tell and start walking
const SLOW := 0.6  # share of full speed a little one walks at (steering, turning round)
const BODY_R := 0.35  # a crew member's size
const FIRST_N := 3  # meteors from this rocket on (the practice and TODAY'S ROCKET stay calm)
const FIRST_T := 9.0  # seconds into a rocket's work before the first tell
const SPACING := 13.0
const JITTER := 5.0
const GAP := 3.0
const HORIZON := 150.0  # tells are planned this far ahead (a rocket's work has no clock in simple mode)
const STAY := 0.8  # seconds a landing lasts (the bump)
const SHOWER_N := 3
const SHOWER_R := 0.85
const SHOWER_GAP := 1.2  # walking room between a shower's rings
const EXTRA_FROM := 4  # HARD's extra puzzle from this rocket
const MAX_PUZZLES := 3
const FINS_LESS := 1  # FINS: this many fewer meteors
const FINS_WARN := 1.0  # ... told this much longer
const CHUTE_HELP := 1.5  # PARACHUTE: Sprocket's ghost hand helps after this many idle seconds
const KINDS: Array[String] = ["meteor", "shower"]
const METEOR_COLOR := Color(1.0, 0.2, 0.6)  # hot pink: "look out!" (never the planks' orange)
const SHOWER_COLOR := Color(0.25, 0.6, 1.0)  # bright blue: little rocks
const ROCK := Color(0.42, 0.36, 0.5)  # the space rock (a glowing orange crack)
const ROCK_GLOW := Color(1.0, 0.55, 0.15)

## The workshop floor meteors land on (inside the walls, in front of the launch doorway) and what stays clear.
## The pilot's desk block is main.gd clamp_walk's (DESK_LO / DESK_HI, the crew walk round it).
const FLOOR_MIN := Vector2(-9.8, -5.3)
const FLOOR_MAX := Vector2(9.8, 7.2)
const DESK_LO := Vector2(-1.4, -1.3)
const DESK_HI := Vector2(1.4, 1.05)
const DESK_CLEAR := 1.4  # nothing lands this near the desk (the crew stand there to talk, the pick orbs are there)
const CREW_SPOTS: Array[Vector3] = [Vector3(-2.2, 0, 4.5), Vector3(2.2, 0, 4.5), Vector3(-4.4, 0, 5.6), Vector3(4.4, 0, 5.6),
	Vector3(-6.4, 0, 4.0), Vector3(6.4, 0, 4.0)]

## Season -> meteor weights (meteor, shower), the extra meteors, the yard's ground, the drifting things, a picture,
## Sprocket's line.
const SEASONS := {
	"spring": {"weights": [1.2, 0.8], "more": 0, "ground": Color(0.45, 0.72, 0.35), "drift": Color(1.0, 0.72, 0.85),
		"pic": "daisy", "line": "Blossom launch day!"},
	"summer": {"weights": [1.0, 1.0], "more": 0, "ground": Color(0.55, 0.74, 0.3), "drift": Color(1.0, 0.95, 0.75),
		"pic": "sunflower", "line": "Sunny launch day!"},
	"autumn": {"weights": [0.7, 1.5], "more": 1, "ground": Color(0.56, 0.62, 0.28), "drift": Color(0.95, 0.5, 0.15),
		"pic": "acorn", "line": "Shooting star season!"},
	"winter": {"weights": [1.0, 1.0], "more": 0, "ground": Color(0.86, 0.9, 0.96), "drift": Color(1.0, 1.0, 1.0),
		"pic": "snowflake", "line": "Snowy launch day!"},
}

## Sprocket's gifts: id, name, picture, line, colour, launches needed, the look part it puts on the rocket.
const GIFTS: Array[Dictionary] = [
	{"id": "boosters", "name": "BOOSTERS", "pic": "boosters", "line": "Boosters! Quick build!", "color": Color(1.0, 0.55, 0.2),
		"unlock": 0, "part": [G.L_EXTRA, 2]},
	{"id": "fins", "name": "FINS", "pic": "rocketfins", "line": "Steady fins!", "color": Color(0.45, 0.8, 1.0),
		"unlock": 0, "part": [G.L_FINS, 1]},
	{"id": "parachute", "name": "PARACHUTE", "pic": "parachute", "line": "I'll help you!", "color": Color(1.0, 0.45, 0.55),
		"unlock": 0, "part": []},
	{"id": "shield", "name": "SHIELD", "pic": "shieldbubble", "line": "Meteors bounce off!", "color": Color(0.55, 1.0, 0.85),
		"unlock": 8, "part": [G.L_EXTRA, 3]},
]

## The pick row floats over the far half of the desk (panel.gd at PANEL_Z): the VR pilot reaches it, a crew member
## walks up to the desk's far side under one, a flat pilot / a Deck clicks one.
const PANEL_Z := -0.5  # == panel.gd position.z
const ROW_Z := -0.5
const ROW_UP := 0.3  # above the desk top
const ROW_GAP := 0.62
const ORB_SCALE := 0.3
const CREW_R := 0.7  # + the orb's hit radius: how near (flat) a crew member must come
const HAND_R := 0.08
const POINTER_R := 0.06  # a pointer ray this near an orb's edge takes it
const PILOT_AT := Vector3(0.0, 1.5, 0.12)  # the VR pilot's head (operator.gd recentre)
const REACH := 0.95  # a VR hand reaches this far from the head
const WAIT := {"mode": 16.0, "gift": 14.0}


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["events", "size", "dizzy", "push", "help", "extra"]:  # more of these is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["warn", "late"]:  # more of these is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if int(g.extra) != 0:
		out.append("gentle has extra puzzles")
	return out


# --- The rocket: mode + gift ---------------------------------------------------------------------------------

## The rocket's puzzle count changes: {extra (HARD, bigger rockets), fewer (BOOSTERS)} for rocketgen.gd.
static func puzzle_opts(mode_id: String, gift_id: String, n: int) -> Dictionary:
	var md := mode_data(mode_id)
	var extra := int(md.extra) if n >= EXTRA_FROM else 0
	var fewer := 1 if gift_id == "boosters" and n > 1 else 0
	return {"extra": extra, "fewer": fewer}


## The rocket's look with the gift's part on it (Rocket Row keeps it).
static func gift_look(look: Array, gift_id: String) -> Array:
	var lk := look.duplicate()
	var part: Array = gift(gift_id).get("part", [])
	if part.size() == 2 and lk.size() == 6:
		lk[int(part[0])] = int(part[1])
	return lk


## Seconds the pilot waits before the ghost hand shows how (INF: no help on this rocket).
static func help_after(mode_id: String, gift_id: String, n: int) -> float:
	var md := mode_data(mode_id)
	var teach := n <= P.SIMPLE_ORDER.size()
	if gift_id == "parachute":
		return CHUTE_HELP
	if teach or int(md.late) == 1:
		return float(md.help) + (0.0 if teach else 3.0)
	return INF


# --- Meteors ---------------------------------------------------------------------------------------------------

## The rocket's meteor spec: {mode, season, gift, n, scale (bots: more), first (bots: earlier)}.
static func warn_of(spec: Dictionary) -> float:
	var w := float(mode_data(String(spec.get("mode", "brave"))).warn)
	if String(spec.get("gift", "")) == "fins":
		w += FINS_WARN
	return w


static func size_of(spec: Dictionary) -> float:
	return float(mode_data(String(spec.get("mode", "brave"))).size)


static func want_of(spec: Dictionary) -> int:
	if int(spec.get("n", FIRST_N)) < FIRST_N:
		return 0
	var md := mode_data(String(spec.get("mode", "brave")))
	var n := int(md.events) + int(season_data(String(spec.get("season", "spring"))).more)
	if String(spec.get("gift", "")) == "fins":
		n -= FINS_LESS
	return maxi(0, roundi(n * float(spec.get("scale", 1.0))))


## This rocket's meteors: [{kind, t, spots: [Vector3], r}] in time order. t: seconds into the work its tell starts.
static func events(seed_value: int, spec: Dictionary) -> Array:
	var out: Array = []
	var want := want_of(spec)
	if want <= 0:
		return out
	var r := Seeded.rng(seed_value, "meteors")
	var warn := warn_of(spec)
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var t := float(spec.get("first", FIRST_T)) + r.randf() * JITTER
	for i in want:
		if t + warn + STAY > HORIZON:
			break
		var kind: String = KINDS[Seeded.weighted(r, weights)]
		var e := _place(r, kind, spec)
		if e.is_empty():
			e = _place(r, "shower" if kind == "meteor" else "meteor", spec)
		if e.is_empty():
			continue
		e.t = snappedf(t, 0.01)
		out.append(e)
		t += maxf(SPACING, warn + STAY + GAP) + r.randf() * JITTER
	return out


static func _place(r: RandomNumberGenerator, kind: String, spec: Dictionary) -> Dictionary:
	var rad := size_of(spec) if kind == "meteor" else SHOWER_R
	for attempt in 16:
		var spots: Array = []
		var count := 1 if kind == "meteor" else SHOWER_N
		var c := Vector3(r.randf_range(FLOOR_MIN.x + rad, FLOOR_MAX.x - rad), 0.0, r.randf_range(FLOOR_MIN.y + rad, FLOOR_MAX.y - rad))
		for k in count:
			if k == 0:
				spots.append(_snap(c))
			else:
				var a := r.randf() * TAU
				var d := 2.0 * rad + SHOWER_GAP + r.randf() * 1.2
				spots.append(_snap(c + Vector3(cos(a) * d, 0.0, sin(a) * d)))
		var e := {"kind": kind, "t": 0.0, "spots": spots, "r": rad}
		if _event_problems(e, spec).is_empty():
			return e
	return {}


static func _snap(p: Vector3) -> Vector3:
	return Vector3(snappedf(p.x, 0.01), 0.0, snappedf(p.z, 0.01))


## How far (flat) p is from the desk block (0 inside it).
static func desk_dist(p: Vector3) -> float:
	var dx := maxf(maxf(DESK_LO.x - p.x, p.x - DESK_HI.x), 0.0)
	var dz := maxf(maxf(DESK_LO.y - p.z, p.z - DESK_HI.y), 0.0)
	return Vector2(dx, dz).length()


## Reasons one event is unfair (empty = fine).
static func _event_problems(e: Dictionary, spec: Dictionary) -> Array:
	var why: Array = []
	var rad := float(e.r)
	var spots: Array = e.spots
	var warn := warn_of(spec)
	if not KINDS.has(String(e.kind)):
		why.append("an unknown meteor %s" % str(e.kind))
	if spots.size() != (1 if String(e.kind) == "meteor" else SHOWER_N):
		why.append("%d rings for a %s" % [spots.size(), str(e.kind)])
	for i in spots.size():
		var p: Vector3 = spots[i]
		if p.x - rad < FLOOR_MIN.x - 0.01 or p.x + rad > FLOOR_MAX.x + 0.01 or p.z - rad < FLOOR_MIN.y - 0.01 or p.z + rad > FLOOR_MAX.y + 0.01:
			why.append("a ring off the workshop floor (%.1f, %.1f)" % [p.x, p.z])
		if desk_dist(p) < rad + DESK_CLEAR:
			why.append("a ring at the pilot's desk (%.1f, %.1f)" % [p.x, p.z])
		for s in CREW_SPOTS:
			if Vector2(p.x - s.x, p.z - s.z).length() < rad + BODY_R + 0.4:
				why.append("a ring where the crew arrive")
				break
		for j in range(i + 1, spots.size()):
			var q: Vector3 = spots[j]
			if Vector2(p.x - q.x, p.z - q.z).length() < 2.0 * rad + SHOWER_GAP - 0.01:
				why.append("no room to walk between the rings")
	# Out of the middle of a ring, walking slowly, after seeing it: in time.
	if (rad + BODY_R) / (Crew.SPEED * SLOW) > warn - REACT:
		why.append("no time to walk out of a ring")
	if warn < MIN_WARN:
		why.append("told only %.1f s early" % warn)
	return why


## Reasons this rocket's meteors are unfair (empty = fine).
static func problems(list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var warn := warn_of(spec)
	var last_end := -INF
	if list.size() > want_of(spec):
		why.append("%d meteors (want at most %d)" % [list.size(), want_of(spec)])
	for e in list:
		if float(e.t) < float(spec.get("first", FIRST_T)) - 0.01:
			why.append("a tell %.1f s into the rocket" % float(e.t))
		if float(e.t) < last_end + GAP - 0.01:
			why.append("two meteors at once (%.1f s)" % float(e.t))
		last_end = float(e.t) + warn + STAY
		for x in _event_problems(e, spec):
			why.append(x)
	return why


## Is a crew member at p under event e's rocks? pad: extra metres (bots keep clear).
static func caught(e: Dictionary, p: Vector3, pad: float = 0.0) -> bool:
	for s in e.spots:
		if Vector2(p.x - (s as Vector3).x, p.z - (s as Vector3).z).length() <= float(e.r) + BODY_R * 0.5 + pad:
			return true
	return false


## The way out of event e from p (flat, unit): away from the nearest ring's middle.
static func out_dir(e: Dictionary, p: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for s in e.spots:
		var d := Vector2(p.x - (s as Vector3).x, p.z - (s as Vector3).z).length()
		if d < bd:
			bd = d
			best = s
	var away := Vector3(p.x - best.x, 0.0, p.z - best.z)
	if away.length() < 0.05:
		away = Vector3(0.0, 0.0, 1.0)
	return away.normalized()


static func pack(e: Dictionary) -> Array:
	return [String(e.kind), float(e.t), (e.spots as Array).duplicate(), float(e.r)]


static func unpack(a: Array) -> Dictionary:
	return {"kind": String(a[0]), "t": float(a[1]), "spots": (a[2] as Array).duplicate(), "r": float(a[3])}


# --- Gifts -----------------------------------------------------------------------------------------------------

static func unlocked(launched_total: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if launched_total >= int(g.unlock):
			out.append(String(g.id))
	return out


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are
## others (the same on every machine for a seed).
static func gift_choices(launched_total: int, last: String, seed_value: int) -> Array:
	return PickOrbs.gift_choices(unlocked(launched_total), last, seed_value)  # (the shared gift pick)


# --- The pick row ----------------------------------------------------------------------------------------------

## Where the row's n orbs float (world), for a desk top at `top` (panel.gd set_top).
static func row_spots(n: int, top: float) -> Array:
	var out: Array = []
	for i in n:
		out.append(Vector3(snappedf((i - (n - 1) * 0.5) * ROW_GAP, 0.01), snappedf(top + ROW_UP, 0.01), ROW_Z))
	return out


## Where a crew member stands to take orb i (flat): the desk's far side, under it.
static func crew_spot(at: Vector3) -> Vector3:
	return Vector3(at.x, 0.0, DESK_LO.y - 0.05)


## How near a crew member's middle (flat) must come to an orb's middle.
static func crew_r() -> float:
	return CREW_R + PickOrbs.HIT_R * ORB_SCALE
