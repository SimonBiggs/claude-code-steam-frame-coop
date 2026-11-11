extends RefCounted
## CANNON COVE second pass (pure data + small functions; tests/cannon_cove_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs: how many warned
##             deck events a wave, how long they are told first, how big a Kraken arm's slam is, whether a slam knocks
##             a hole in the deck and makes a deckhand drop their cannonball, how hard a squall pushes and for how
##             long, how often the pirates shoot, how fast Polly reloads when nobody else is aboard.
##   GIFTS     POLLY'S CANNON GIFTS, three offered on the pick orbs before every wave (the gunner shoots one, or a deckhand
##             muskets one): BOUNCY BALLS (a ball that misses skips off the sea and flies on), NET SHOT (a ship we hit is
##             tangled in a net: slow, and it can't shoot for a while), BIG BARREL (fat cannonballs that hit from further
##             off), GOLDEN BALL (a golden cannonball every wave) and QUICK LOAD (the cannons reload twice as fast) -
##             the last two open as Polly's harbour grows.
##   EVENTS    told first by core/warn_rings.gd on our deck (hazards.gd), then they happen:
##               ARM     red rings on the deck: a Kraken arm rises over the rail and slams down there. Step out of the
##                       rings! (BRAVE / HARD: a deckhand caught drops their cannonball and the slam makes a leak.)
##               SQUALL  a blue band across the deck with rain: a gust blows anyone in it along the deck.
##             events(seed, wave, spec) is the same list on every machine; problems() proves it fair (rings on the
##             deck, clear of the cannons, the gunner and the cannonball pile; a squall never covers a cannon row or
##             the pile; time to step out while it is told; never two at once; none on wave 1).
##   SEASONS   Polly's voyages sail through the season's seas (Seeded.season): spring blossom, summer sun, autumn
##             leaves, winter snow drift past the ship; the season leans the events (winter and autumn squalls).
##   HARBOUR   every HARBOUR_EVERY treasures won, Polly's harbour on the island off the bow gets a new piece (a jetty, a
##             hut, a beacon, a boat ...: saved, for good). Pieces stand far out of every pirate's lane.
##   SOLO      nobody else aboard (the Frame alone, one Deck): Polly reloads the gunner's cannon herself, holes are
##             patched by Polly and no boarders come.
##   PICK ROW  three big orbs bob on the sea off the gunner's cannon, inside its swing and reach; shooting one picks it
##             (a ball has to be aimed and fired: never a resting hand); missed by everyone = the middle (it glows).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const World := preload("res://games/cannon_cove/world.gd")
const VoyageGen := preload("res://games/cannon_cove/voyagegen.gd")

## events: warned events a wave; warn: seconds told first; arm_r: a slam's radius (m); leak: 1 = a slam knocks a hole;
## drop: 1 = caught deckhands drop their ball; push: a squall's push (m/s); gust: seconds it blows; fire: pirates' time
## between shots (share of normal: more = gentler); reload: seconds for Polly to bring one ball when nobody else is aboard.
const MODES := {
	"gentle": {"events": 1, "warn": 4.5, "arm_r": 1.2, "leak": 0, "drop": 0, "push": 1.0, "gust": 1.5, "fire": 1.4, "reload": 2.6},
	"brave": {"events": 2, "warn": 3.6, "arm_r": 1.4, "leak": 1, "drop": 1, "push": 1.5, "gust": 2.0, "fire": 1.0, "reload": 3.4},
	"hard": {"events": 3, "warn": 3.0, "arm_r": 1.6, "leak": 1, "drop": 1, "push": 1.9, "gust": 2.4, "fire": 0.8, "reload": 4.2},
}
const MIN_WARN := 2.4
const REACT := 0.8  # seconds a deckhand needs to see a tell and start walking
const WALK := 5.5  # == player.gd SPEED
const BODY_R := 0.35  # a deckhand (player.gd: World.constrain radius)
const STAY := 1.2  # seconds a slam / squall goes off after its tell
const FIRST_WAVE := 2  # no events on wave 1 (the first real wave stays calm)
const FIRST_T := 12.0  # seconds into a wave before the first tell
const SPACING := 15.0  # seconds between tells (plus up to JITTER)
const JITTER := 5.0
const GAP := 4.0  # at least this between one going off and the next tell
const CANNON_CLEAR := 1.2  # metres between a slam's edge and a cannon (the gunner stands there)
const PILE_CLEAR := 1.4  # metres between a slam's edge and the cannonball pile
const ROOT_CLEAR := 1.6  # metres along the rail between an arm's root and a cannon
const MAST_CLEAR := 0.3
const SQUALL_W := 2.4  # a squall band's width along the deck
const SQUALL_ROW_CLEAR := 0.8  # metres between a squall band and a cannon row
const MAX_DRIFT := 5.0  # a squall never pushes further than this
const ARM_COLOR := Color(1.0, 0.18, 0.4)  # red-pink: "step out!" (never the gold of a pick)
const SQUALL_COLOR := Color(0.25, 0.55, 1.0)  # rain blue
const ARM_SKIN := Color(0.55, 0.3, 0.75)
const KINDS: Array[String] = ["arm", "squall"]
## Season -> event weights (arm, squall), the drifting things' colour, a picture, Polly's line.
const SEASONS := {
	"spring": {"weights": [1.0, 1.0], "drift": Color(1.0, 0.72, 0.85), "tree": Color(1.0, 0.62, 0.8), "pic": "daisy", "line": "Blossom seas!", "name": "spring"},
	"summer": {"weights": [1.4, 0.7], "drift": Color(1.0, 0.93, 0.5), "tree": Color(0.25, 0.7, 0.3), "pic": "sunflower", "line": "Sunny seas!", "name": "summer"},
	"autumn": {"weights": [0.8, 1.5], "drift": Color(0.95, 0.5, 0.15), "tree": Color(0.95, 0.5, 0.15), "pic": "acorn", "line": "Windy autumn seas!", "name": "autumn"},
	"winter": {"weights": [0.9, 1.5], "drift": Color(1.0, 1.0, 1.0), "tree": Color(0.92, 0.96, 1.0), "pic": "snowflake", "line": "Snowy seas!", "name": "winter"},
}
## Polly's cannon gifts: id, name, picture, a short line, a colour, harbour pieces needed.
const GIFTS: Array[Dictionary] = [
	{"id": "bouncy", "name": "BOUNCY BALLS", "pic": "bouncyball", "line": "Boing boing!", "color": Color(1.0, 0.45, 0.7), "unlock": 0},
	{"id": "net", "name": "NET SHOT", "pic": "netshot", "line": "Tangle them up!", "color": Color(0.55, 0.9, 0.5), "unlock": 0},
	{"id": "big", "name": "BIG BARREL", "pic": "bigbarrel", "line": "Big balls!", "color": Color(1.0, 0.6, 0.2), "unlock": 0},
	{"id": "golden", "name": "GOLDEN BALL", "pic": "goldball", "line": "A golden one!", "color": Color(1.0, 0.85, 0.25), "unlock": 2},
	{"id": "quick", "name": "QUICK LOAD", "pic": "quickload", "line": "Zoom loading!", "color": Color(0.45, 0.85, 1.0), "unlock": 4},
]
const BOUNCE_KEEP := 0.6  # BOUNCY BALLS: a skip keeps this much of the ball's speed
const NET_SECS := 6.0  # NET SHOT: a hit ship is tangled this long
const NET_SLOW := 0.3  # ... and sails this fast
const BIG_SLACK := 1.0  # BIG BARREL: metres more a ball can miss by and still hit
const BIG_SCALE := 1.7
const QUICK := 0.5  # QUICK LOAD: reload time share
## Polly's harbour: one piece every HARBOUR_EVERY treasures, on the island off the bow.
const HARBOUR_EVERY := 3
const HARBOUR: Array[String] = ["jetty", "hut", "beacon", "boat", "tree", "crane", "market", "windmill", "bell", "flags"]
const HARBOUR_AT := Vector3(0.0, 0.0, -78.0)  # the harbour island's middle (world, sea level)
const HARBOUR_R := 13.0
const HARBOUR_CLEAR := 8.0  # metres between the harbour and the furthest pirate's circle
## The pick row: three orbs on the sea off the gunner's cannon.
const ROW_DIST := 19.0
const ROW_ANGLE := 0.42  # radians between orbs (seen from the cannon)
const ROW_UP := 2.6  # orb middle above the sea (its name floats over it)
const ORB_SCALE := 3.0
const CATCH := 0.6  # a cannonball this near an orb's edge takes it
const ROW_WAIT := 20.0  # nobody shot one: the middle after this
const SOLO_WAIT := 25.0  # nobody else aboard: practice ends after the hits and this long (TV players still drop in)
const SOLO_MAX := 2  # Polly fills a lonely cannon up to this many balls


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
	for k in ["events", "arm_r", "leak", "drop", "push", "gust", "reload"]:  # more of these is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["warn", "fire"]:  # more of these is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if int(g.leak) != 0 or int(g.drop) != 0:
		out.append("gentle slams knock holes or balls")
	for m in MODES:
		if float(MODES[m].push) * float(MODES[m].gust) > MAX_DRIFT:
			out.append("%s: a squall pushes too far" % m)
	return out


# --- Events ------------------------------------------------------------------------------------------------

## This wave's events: [{kind, t, pos, dir, size, sign}] in time order. t: seconds into the wave its tell starts;
## pos: an arm's slam middle / a squall band's middle (deck, y 0); dir: a squall blows along +z * sign; size: an arm's
## radius / Vector2(band length, SQUALL_W). spec: {mode, season, wave, scale (bots: more), from (bots: wave 1),
## first (bots: an earlier first tell)}.
static func events(seed_value: int, spec: Dictionary) -> Array:
	var out: Array = []
	var w := int(spec.get("wave", 1))
	if w < int(spec.get("from", FIRST_WAVE)):
		return out
	var r := Seeded.rng(seed_value, "deck events")
	var md := mode_data(String(spec.get("mode", "brave")))
	var want := maxi(1, roundi(float(md.events) * float(spec.get("scale", 1.0))))
	if w == VoyageGen.BOSS_WAVE:
		want += 1  # the Kraken's own wave: its arms come over the rail
	var weights: Array = season_data(String(spec.get("season", "spring"))).weights
	var t := float(spec.get("first", FIRST_T)) + r.randf() * JITTER
	for i in want:
		var kind: String = "arm" if w == VoyageGen.BOSS_WAVE else KINDS[Seeded.weighted(r, weights)]
		var e := _place(r, kind, md)
		if e.is_empty() and kind == "squall":
			e = _place(r, "arm", md)
		if e.is_empty():
			continue
		e.t = snappedf(t, 0.01)
		out.append(e)
		t += maxf(SPACING, float(md.warn) + STAY + GAP) + r.randf() * JITTER
	return out


## One event, or {} when none fits (a few tries).
static func _place(r: RandomNumberGenerator, kind: String, md: Dictionary) -> Dictionary:
	for attempt in 12:
		var e := {}
		if kind == "arm":
			var rad := float(md.arm_r)
			var z := r.randf_range(World.DECK_BOW + rad, World.DECK_STERN - rad - 0.6)
			var hw := World.deck_half_width(z) - rad - 0.2
			if hw <= 0.0:
				continue
			var x := r.randf_range(-hw, hw)
			e = {"kind": "arm", "t": 0.0, "pos": Vector3(snappedf(x, 0.01), 0.0, snappedf(z, 0.01)), "dir": Vector3.BACK,
				"size": Vector2(rad, 0.0), "sign": 1 if x >= 0.0 else -1}
		else:
			var z2 := r.randf_range(World.DECK_BOW + SQUALL_W * 0.5, World.DECK_STERN - SQUALL_W * 0.5 - 0.5)
			e = {"kind": "squall", "t": 0.0, "pos": Vector3(0.0, 0.0, snappedf(z2, 0.01)), "dir": Vector3.BACK,
				"size": Vector2(World.HULL_HALF_W * 2.0, SQUALL_W), "sign": -1 if r.randf() < 0.5 else 1}
		if _event_problems(e, md).is_empty():
			return e
	return {}


## Where an arm comes up over the rail (deck height, at the slam's own side and z).
static func arm_root(e: Dictionary) -> Vector3:
	var p: Vector3 = e.pos
	return Vector3(float(e.sign) * World.HULL_HALF_W, 0.0, p.z)


## Reasons one event is unfair (empty = fine).
static func _event_problems(e: Dictionary, md: Dictionary) -> Array:
	var why: Array = []
	var p: Vector3 = e.pos
	var warn := float(md.warn)
	match String(e.kind):
		"arm":
			var rad := float((e.size as Vector2).x)
			if not World.on_deck(p, rad + 0.1):
				why.append("an arm slams off the deck (%.1f, %.1f)" % [p.x, p.z])
			for c in World.CANNON_SPOTS:
				var cp: Vector3 = c[0]
				if Vector2(cp.x - p.x, cp.z - p.z).length() < rad + CANNON_CLEAR:
					why.append("an arm slams by a cannon")
				var root := arm_root(e)
				if signf(cp.x) == signf(root.x) and absf(cp.z - root.z) < ROOT_CLEAR:
					why.append("an arm comes over the rail at a cannon")
			if Vector2(p.x - World.HOLD_POS.x, p.z - World.HOLD_POS.z).length() < rad + PILE_CLEAR:
				why.append("an arm slams on the cannonball pile")
			for o in World.obstacles:
				var oc: Vector2 = o[0]
				if Vector2(p.x, p.z).distance_to(oc) < rad + float(o[1]) * 0.5 + MAST_CLEAR and float(o[1]) < 0.7:
					why.append("an arm slams on a mast")
			# A lane past it is always open, and a deckhand standing in the middle can step out in time.
			if 2.0 * rad > 2.0 * World.deck_half_width(p.z) - 1.6:
				why.append("an arm's slam fills the deck")
			if (rad + BODY_R) / WALK > warn - REACT:
				why.append("no time to step out of a slam")
		"squall":
			var hw := float((e.size as Vector2).y) * 0.5
			for c in World.CANNON_SPOTS:
				if absf((c[0] as Vector3).z - p.z) < hw + SQUALL_ROW_CLEAR:
					why.append("a squall over a cannon row")
			if absf(World.HOLD_POS.z - p.z) < hw + PILE_CLEAR + 1.05:
				why.append("a squall over the cannonball pile")
			if p.z - hw < World.DECK_BOW - 0.01 or p.z + hw > World.DECK_STERN:
				why.append("a squall off the deck")
			if float(md.push) * float(md.gust) > MAX_DRIFT:
				why.append("a squall pushes %.1f m" % (float(md.push) * float(md.gust)))
			if (hw + BODY_R) / WALK > warn - REACT:
				why.append("no time to step out of a squall")
		_:
			why.append("an unknown event %s" % str(e.kind))
	if warn < MIN_WARN:
		why.append("told only %.1f s early" % warn)
	return why


## Reasons this wave's events are unfair (empty = fine).
static func problems(list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var w := int(spec.get("wave", 1))
	var last_end := -INF
	for e in list:
		if float(e.t) < float(spec.get("first", FIRST_T)) - 0.01:
			why.append("a tell %.1f s into the wave" % float(e.t))
		if float(e.t) < last_end + GAP - 0.01:
			why.append("two events at once (%.1f s)" % float(e.t))
		last_end = float(e.t) + float(md.warn) + STAY
		if w == VoyageGen.BOSS_WAVE and String(e.kind) != "arm":
			why.append("a squall on the Kraken's wave")
		for x in _event_problems(e, md):
			why.append(x)
	if w < int(spec.get("from", FIRST_WAVE)) and not list.is_empty():
		why.append("events on wave %d" % w)
	return why


## Is a deckhand at p caught by event e going off?
static func caught(e: Dictionary, p: Vector3) -> bool:
	var c: Vector3 = e.pos
	if String(e.kind) == "arm":
		return Vector2(p.x - c.x, p.z - c.z).length() <= float((e.size as Vector2).x) + BODY_R * 0.5
	return absf(p.z - c.z) <= float((e.size as Vector2).y) * 0.5 + BODY_R * 0.5


## An event as plain values for the network (and back).
static func pack(e: Dictionary) -> Array:
	return [String(e.kind), float(e.t), e.pos, e.dir, e.size, int(e.sign)]


static func unpack(a: Array) -> Dictionary:
	return {"kind": String(a[0]), "t": float(a[1]), "pos": a[2], "dir": a[3], "size": a[4], "sign": int(a[5])}


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
	return GIFTS[0]


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


# --- Polly's harbour -------------------------------------------------------------------------------------------

static func harbour(treasures_total: int) -> int:
	return mini(HARBOUR.size(), maxi(0, treasures_total) / HARBOUR_EVERY)


## Where harbour piece i stands (world, sea level): round the island, the jetty towards our ship.
static func harbour_spot(i: int) -> Vector3:
	if i == 0:
		return HARBOUR_AT + Vector3(0.0, 0.0, HARBOUR_R * 0.75)
	var a := PI * 0.5 + 0.7 + (i - 1) * (TAU - 1.4) / float(HARBOUR.size() - 2)  # round the island, leaving the jetty's front clear
	var r := HARBOUR_R * (0.45 if i % 2 == 0 else 0.65)
	return HARBOUR_AT + Vector3(cos(a) * r, 0.0, sin(a) * r)


# --- The pick row ---------------------------------------------------------------------------------------------

## Where the row's n orbs bob (world) off a cannon at `cannon` facing `outboard`, the sea at sea_y.
static func row_spots(cannon: Vector3, outboard: Vector3, sea_y: float, n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var d := Basis(Vector3.UP, (i - (n - 1) * 0.5) * ROW_ANGLE) * outboard
		var p := Vector3(cannon.x, 0.0, cannon.z) + d * ROW_DIST
		out.append(Vector3(p.x, sea_y + ROW_UP, p.z))
	return out


## How near a cannonball's middle must come to an orb's middle to take it.
static func catch_r() -> float:
	return PickOrbs.HIT_R * ORB_SCALE + CATCH
