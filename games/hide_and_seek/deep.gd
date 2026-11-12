extends RefCounted
## HIDE AND SEEK, second deepening pass (data + generators; deep_play.gd runs them in the game):
## - MODES: before the first round everybody picks GENTLE / BRAVE / HARD on pick orbs in the counting room
##   (core/pick_orbs.gd: hiders walk under one, the seeker walks under one or reaches in with a VR hand).
##   GENTLE: longer warnings, more seeking time, one surprise; HARD: a faster count, three surprises.
## - PIP'S GIFTS: before every later round the side that LOST the last round picks one of three gifts for this
##   round (a seeker gift: BIG TORCH, SUPER NOSE, BIG HANDS, ZOOMY SHOES; a hiders' gift: ZOOMY SHOES, EXTRA BELL,
##   BUBBLE, HANKY). Alone, the seeker picks.
## - RUMBLE'S SURPRISES (never in round 1, never alone): Rumble the robot hoover rolls along a band through a hider's
##   room (bumps hiders out of their disguise), and the PEPPER POT puffs round a hider (everyone in it sneezes ACHOO).
##   Each is TOLD first by a steady warn ring on the floor (core/warn_rings.gd) for MODES.tell seconds, so a hider
##   who sees it can step out. plan() makes a round's surprises from the house seed; check_plan() proves them fair.
## - SEASONS (core/seeded.gd season, core/season_kit.gd props + drift) dress the garden, the courtyard, the mess hall.
## - PIP'S KENNEL grows: every finished round adds to the family's count and KENNEL_STEPS build a flag, a bowl ...
##   up to a golden roof (saved; the Trophy Hall counts it).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")

const MODES := {
	"gentle": {"count": 20.0, "seek_add": 20.0, "surprises": 1, "tell": 4.5, "sniff_cd": 10.0},
	"brave": {"count": 20.0, "seek_add": 0.0, "surprises": 2, "tell": 3.5, "sniff_cd": 15.0},
	"hard": {"count": 15.0, "seek_add": -10.0, "surprises": 3, "tell": 3.0, "sniff_cd": 18.0},
}
const GIFTS: Array[Dictionary] = [
	{"id": "torch", "name": "BIG TORCH", "pic": "biglight", "color": Color(1.0, 0.86, 0.3), "side": "seeker"},
	{"id": "nose", "name": "SUPER NOSE", "pic": "nose", "color": Color(1.0, 0.55, 0.78), "side": "seeker"},
	{"id": "reach", "name": "BIG HANDS", "pic": "foamhand", "color": Color(0.5, 0.82, 1.0), "side": "seeker"},
	{"id": "zoomy", "name": "ZOOMY SHOES", "pic": "springshoes", "color": Color(0.45, 1.0, 0.55), "side": "both"},
	{"id": "bell", "name": "EXTRA BELL", "pic": "bell", "color": Color(1.0, 0.75, 0.3), "side": "hider"},
	{"id": "bubble", "name": "BUBBLE", "pic": "shieldbubble", "color": Color(0.6, 0.9, 1.0), "side": "hider"},
	{"id": "hanky", "name": "HANKY", "pic": "hanky", "color": Color(0.85, 0.7, 1.0), "side": "hider"},
]
const GIFT_CHOICES := 3
## Gift numbers (main.gd reads them through deep_play.gd).
const TORCH_RANGE := 4.6  # BIG TORCH (main.gd TAG_RANGE is 3)
const TORCH_ANGLE := 26.0
const NOSE_RANGE := 7.0  # SUPER NOSE (SNIFF_RANGE 4.5) ...
const NOSE_CD := 6.0  # ... and a short cooldown
const REACH_K := 1.6  # BIG HANDS: touch ranges this much bigger
const ZOOMY_K := 1.3  # ZOOMY SHOES: run this much faster
const BUBBLE_GRACE := 2.5  # BUBBLE: a popped bubble gives this long to run before anyone can tag you

## Surprises.
const KINDS: Array[String] = ["hoover", "pepper"]
const KIND_PICS := {"hoover": "hoover", "pepper": "pepper"}
const KIND_NAMES := {"hoover": "RUMBLE!", "pepper": "PEPPER!"}
const HOOVER_COLOR := Color(0.25, 0.85, 1.0)  # Rumble's band: sky blue
const PEPPER_COLOR := Color(1.0, 0.45, 0.2)  # the pepper ring: orange
const SURPRISE_FROM := 2  # no surprise in round 1
const FIRST_AT := 18.0  # seconds into the seek before the first tell
const END_GAP := 12.0  # nothing goes off in the last seconds
const MIN_GAP := 14.0  # between two tells
const MIN_TELL := 3.0  # every surprise shows its ring at least this long before it goes off
const HOOVER_W := 1.4  # the band's width
const HOOVER_REACH := 3.2  # each way from the hider
const HOOVER_MIN := 2.2  # shorter (walls close round): the pepper pot comes instead
const HOOVER_ROLL := 1.8  # seconds Rumble takes along the band
const HOOVER_PUSH := 3.4  # m/s sideways for KNOCK_T
const KNOCK_T := 0.35
const PEPPER_R := 1.6
const PEPPER_OFF := 0.6  # the ring's middle is up to this far from the hider (not a bullseye on someone)

## Pick orbs over the counting room's floor: a row this far in front of the counting spot (houses), or the map's own.
const PICK_ROWS: Array[float] = [1.3, 1.6, 1.15, 1.9]  # houses: the first row (and shift away from the jail) that's clear
const PICK_SHIFTS: Array[float] = [0.0, 0.6, 1.2]
const PICK_GAP := 1.3
const PICK_Y := 1.25  # the ball's middle over the floor
const PICK_TOUCH := 0.6  # standing this close under one (feet)
const HAND_R := 0.32  # a VR hand this close to a ball ...
const DWELL := 0.5  # ... or feet under one this long: deliberate (running past never picks)
const PICK_WAIT := {"mode": 15.0, "gift": 10.0}
const EMPTY_WAIT := 3.0
const SPAWN_CLEAR := 0.9  # no spawn under an orb
const JAIL_CLEAR := 1.0

## PIP'S KENNEL: [finished rounds, piece]. deep_play.gd builds each piece beside the kennel.
const KENNEL_STEPS: Array = [[1, "flag"], [3, "bowl"], [5, "flowers"], [8, "bone"], [12, "porch"], [16, "lights"],
	[21, "tower"], [27, "gold"]]
const KENNEL_NAMES := {"flag": "A FLAG!", "bowl": "A BIG BOWL!", "flowers": "FLOWERS!", "bone": "A BONE SIGN!",
	"porch": "A PORCH!", "lights": "LIGHTS!", "tower": "A TOWER!", "gold": "A GOLD ROOF!"}

## Seasons: the story card and the drift colour (core/season_kit.gd draws the props and the drift).
const SEASONS := {
	"spring": {"name": "SPRING STREET", "pic": "sweetflower", "drift": Color(1.0, 0.78, 0.88), "line": "Blossom time!"},
	"summer": {"name": "SUMMER STREET", "pic": "sunflower", "drift": Color(1.0, 0.95, 0.6), "line": "Sunny days!"},
	"autumn": {"name": "AUTUMN STREET", "pic": "pumpkin", "drift": Color(0.95, 0.5, 0.18), "line": "Crunchy leaves!"},
	"winter": {"name": "WINTER STREET", "pic": "snowflake", "drift": Color(0.95, 0.97, 1.0), "line": "Snowy days!"},
}


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


static func gift_for(id: String, side: String) -> bool:
	var s := String(gift(id).get("side", ""))
	return s == side or s == "both"


## The three gifts offered to `side` ("seeker" / "hider") before round `round_n` (same seed: same three).
static func gift_choices(seed_value: int, round_n: int, side: String) -> Array:
	var pool: Array = []
	for g in GIFTS:
		if String(g.side) == side or String(g.side) == "both":
			pool.append(String(g.id))
	return Seeded.shuffled(Seeded.rng(seed_value, "gifts%d%s" % [round_n, side]), pool).slice(0, GIFT_CHOICES)


## A round's surprises: [{t (seconds into the seek the tell starts), kind, k (which hider: an index into the hiders
## still hiding then, mod their count), a (0..1: the hoover's axis, the pepper's offset angle)}].
static func plan(seed_value: int, round_n: int, mode: String, seek_len: float, solo: bool) -> Array:
	var out: Array = []
	if round_n < SURPRISE_FROM or solo:
		return out
	var md := mode_data(mode)
	var tell := float(md.tell)
	var n := int(md.surprises)
	var last := seek_len - END_GAP - tell
	if last < FIRST_AT:
		return out
	n = mini(n, 1 + int((last - FIRST_AT) / MIN_GAP))
	var r := Seeded.rng(seed_value, "surprise%d" % round_n)
	var slot := (last - FIRST_AT) / float(n)
	var first_kind := r.randi() % KINDS.size()
	for i in n:
		var room := maxf(0.0, slot - MIN_GAP)
		var t := FIRST_AT + slot * i + r.randf() * room
		out.append({"t": snappedf(t, 0.1), "kind": KINDS[(first_kind + i) % KINDS.size()], "k": r.randi() % 6, "a": snappedf(r.randf(), 0.01)})
	return out


## Reasons a plan is unfair (empty: fine).
static func check_plan(p: Array, round_n: int, mode: String, seek_len: float, solo: bool) -> Array:
	var why: Array = []
	if (round_n < SURPRISE_FROM or solo) and not p.is_empty():
		why.append("a surprise in round %d / alone" % round_n)
	var md := mode_data(mode)
	if p.size() > int(md.surprises):
		why.append("too many surprises for %s" % mode)
	if float(md.tell) < MIN_TELL:
		why.append("the %s tell is too short" % mode)
	var prev := -INF
	for s in p:
		var t := float(s.t)
		if t < FIRST_AT - 0.01:
			why.append("a surprise before the seeker set off (%.1f)" % t)
		if t + float(md.tell) > seek_len - END_GAP + 0.01:
			why.append("a surprise at the very end (%.1f of %.0f)" % [t, seek_len])
		if t - prev < MIN_GAP - 0.01:
			why.append("two surprises too close (%.1f, %.1f)" % [prev, t])
		if not KINDS.has(String(s.kind)):
			why.append("an unknown surprise %s" % str(s.kind))
		prev = t
	return why


## Rumble's band through a hider at `at`: dir is along the axis, neg / pos the free floor each way (to the walls).
## {} if there's not room (then the pepper pot comes instead). {from, dir, len}.
static func hoover_band(at: Vector3, dir: Vector3, neg: float, pos: float) -> Dictionary:
	var a := minf(neg, HOOVER_REACH)
	var b := minf(pos, HOOVER_REACH)
	if a + b < HOOVER_MIN:
		return {}
	var f := Vector3(at.x, 0.0, at.z) - dir * a
	return {"from": f, "dir": dir, "len": a + b}


## The pick-orb spots of a map (data(): its own "pick_spots", else a row in front of the house's counting spot).
## free(point) -> bool (housegen: floor both can walk to) when the spots are being chosen.
static func pick_spots(md: Dictionary, free: Callable = Callable()) -> Array:
	if not (md.get("pick_spots", []) as Array).is_empty():
		return md.pick_spots
	var sp: Array = md.spawns
	var seeker: Vector3 = sp[0]
	var mid: Vector3 = sp[3]  # the middle hider spawn (housegen: straight behind the hall's middle)
	var away := -signf((md.jail as Vector3).x - mid.x)  # away from the jail's side
	var first: Array = []
	for row in PICK_ROWS:
		for shift in PICK_SHIFTS:
			var out: Array = []
			for k in 3:
				out.append(Vector3(mid.x + away * float(shift) + (k - 1) * PICK_GAP, 0.0, seeker.z - float(row)))
			if first.is_empty():
				first = out
			if _pick_problems(md, out).is_empty() and (not free.is_valid() or out.all(func(p: Vector3) -> bool: return free.call(p))):
				return out
	return first


## Reasons a map's pick spots are bad (no spawn under one, clear of the jail and the bell, apart).
static func check_picks(md: Dictionary) -> Array:
	return _pick_problems(md, pick_spots(md))


static func _pick_problems(md: Dictionary, spots: Array) -> Array:
	var why: Array = []
	if spots.size() != 3:
		return ["%d pick spots" % spots.size()]
	for i in spots.size():
		var p: Vector3 = spots[i]
		for s in md.spawns:
			if Vector2(p.x - s.x, p.z - s.z).length() < SPAWN_CLEAR:
				why.append("a spawn under pick %d" % i)
				break
		var jl: Vector3 = md.jail
		var bl: Vector3 = md.bell
		if Vector2(p.x - jl.x, p.z - jl.z).length() < JAIL_CLEAR + 0.65 or Vector2(p.x - bl.x, p.z - bl.z).length() < JAIL_CLEAR:
			why.append("pick %d by the jail" % i)
		for j in i:
			if (spots[j] as Vector3).distance_to(p) < PICK_TOUCH * 2.0 - 0.01:
				why.append("picks %d and %d overlap" % [j, i])
	return why


## How many kennel pieces `rounds` finished rounds have built.
static func kennel_stage(rounds: int) -> int:
	var n := 0
	for s in KENNEL_STEPS:
		if rounds >= int(s[0]):
			n += 1
	return n


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)
