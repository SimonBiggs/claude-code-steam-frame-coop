extends RefCounted
## DRAGON RIDER second pass (pure data + small functions; tests/dragon_rider_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs: how many
##             warned sky events a stage, how long they are told first, how big a storm cloud is, how dizzy a bump
##             makes Sunny (GENTLE: just a giggle), how hard a crosswind pushes and for how long.
##   GIFTS     SUNNY'S GIFTS, three offered on the pick orbs before every stage (the dragon flies into one, or a gunner
##             bubbles one): FIRE BREATH (Sunny's fire pops balloons and sprites further off and burns storm clouds
##             away), SHIELD BUBBLE (storm clouds bounce off, crosswinds push half as hard), BUNNY MAGNET (stars and sky
##             bunnies are scooped from much further), BUBBLE STORM (triple bubbles all stage), ZOOM WINGS (flaps go
##             further). The last two hatch with the baby dragons.
##   EVENTS    told first by core/warn_rings.gd standing up in the sky (hazards.gd), then they happen:
##               STORM  red rings across the route: a grumpy storm cloud puffs up there. Fly round it (or over / under);
##                      flying through it makes Sunny dizzy (slower for a moment).
##               WIND   a teal band across the route with streaks blowing sideways: a crosswind pushes Sunny that way.
##             events(seed, route, spec) is the same list on every machine; problems() proves it fair against the
##             stage's own route (clear of rings, stars, bunnies and balloons; time to dodge a cloud while it is told;
##             time to steer back to the next ring after a gust; never two at once).
##   SEASONS   Sunny's sky route flies through the season's lands (Seeded.season): spring blossom isles, summer sunny
##             isles, autumn maple isles, winter snowy isles, each with its own drifting petals / pollen / leaves / snow;
##             the season leans the events (summer storms, autumn winds).
##   ROOST     every HATCH_EVERY stages finished, an egg in Sunny's roost hatches: a BABY DRAGON (saved, for good)
##             flies beside Sunny on every flight after. The flock only grows.
##   PICK ROW  three big orbs float across the sky ahead, above the flight line (flying straight passes under them all,
##             so a pick is always a deliberate climb and turn, never a resting hand); missed by everyone = the middle.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const RouteGen := preload("res://games/dragon_rider/routegen.gd")
const Dragon := preload("res://games/dragon_rider/dragon.gd")

## events: warned events a stage; warn: seconds told first; cloud_r: a storm cloud's radius (m); dizzy: seconds Sunny is
## dizzy after flying through one (0 = just a giggle); slow: her speed while dizzy (share of cruise); push: a crosswind's
## sideways push (m/s); gust: seconds it blows.
const MODES := {
	"gentle": {"events": 1, "warn": 4.4, "cloud_r": 4.5, "dizzy": 0.0, "slow": 1.0, "push": 2.0, "gust": 1.8},
	"brave": {"events": 2, "warn": 3.6, "cloud_r": 5.2, "dizzy": 1.5, "slow": 0.75, "push": 3.0, "gust": 2.4},
	"hard": {"events": 3, "warn": 3.1, "cloud_r": 5.8, "dizzy": 2.5, "slow": 0.6, "push": 4.2, "gust": 3.0},
}
const MIN_WARN := 2.4
const REACT := 0.8  # seconds a rider needs to see a tell and start steering
const DODGE_REIN := 0.7  # how far the reins are pulled to dodge (the full turn is never needed)
const CORE_R := 2.2  # Sunny's body round her core (main.dragon.core_position): a cloud this near her middle bumps
const FAST := 1.35  # a flapping dragon flies up to this times cruise for a while
const STAY := 4.0  # seconds a storm cloud / crosswind band stays after its tell
const BAND_LEN := 44.0  # a crosswind band across the route (m)
const BAND_H := 18.0  # its height
const CLEAR := 6.0  # metres between a storm cloud and a ring's edge / a bunny / the golden balloon
const STAR_CLEAR := 1.5  # metres between a storm cloud and a star
const RECOVER_FRAC := 0.55  # after a gust, the ring must still be reachable inside this share of its radius
const MAX_DRIFT := 14.0  # a crosswind never pushes further than this
const FIRST_STAGE := 2  # no events on stage 1 (the first real stage stays calm)
const STORM_COLOR := Color(1.0, 0.2, 0.42)  # red-pink: "fly round me" (never the gold of a ring)
const WIND_COLOR := Color(0.1, 0.85, 0.72)  # teal: the crosswind band
const CLOUD_COLOR := Color(0.36, 0.33, 0.48)
const KINDS: Array[String] = ["storm", "wind"]
## Season -> event weights (storm, wind), the lands' colours, drift particles, a picture and Sunny's line.
## grass / crown / rock: island top, tree crowns, island rock; drift: falling things round the dragon (or none).
const SEASONS := {
	"spring": {"weights": [1.0, 1.0], "grass": Color(0.5, 0.8, 0.42), "crown": Color(1.0, 0.62, 0.78), "rock": Color(0.56, 0.44, 0.5),
		"drift": Color(1.0, 0.75, 0.85), "pic": "daisy", "line": "Blossom isles!", "name": "spring"},
	"summer": {"weights": [1.5, 0.8], "grass": Color(0.42, 0.78, 0.3), "crown": Color(0.3, 0.7, 0.3), "rock": Color(0.75, 0.62, 0.45),
		"drift": Color(1.0, 0.92, 0.45), "pic": "sunflower", "line": "Sunny isles!", "name": "summer"},
	"autumn": {"weights": [0.8, 1.6], "grass": Color(0.62, 0.62, 0.32), "crown": Color(0.95, 0.5, 0.15), "rock": Color(0.5, 0.4, 0.38),
		"drift": Color(0.95, 0.45, 0.15), "pic": "acorn", "line": "Maple isles!", "name": "autumn"},
	"winter": {"weights": [1.3, 1.0], "grass": Color(0.92, 0.95, 1.0), "crown": Color(0.85, 0.93, 1.0), "rock": Color(0.5, 0.52, 0.62),
		"drift": Color(1.0, 1.0, 1.0), "pic": "snowflake", "line": "Snowy isles!", "name": "winter"},
}
## Sunny's gifts: id, name, picture, a short line, a colour, baby dragons needed.
const GIFTS: Array[Dictionary] = [
	{"id": "fire", "name": "FIRE BREATH", "pic": "firebreath", "line": "Fire breath!", "color": Color(1.0, 0.5, 0.2), "unlock": 0},
	{"id": "shield", "name": "SHIELD BUBBLE", "pic": "shieldbubble", "line": "Bubble shield!", "color": Color(0.5, 0.85, 1.0), "unlock": 0},
	{"id": "magnet", "name": "BUNNY MAGNET", "pic": "bunnymagnet", "line": "Magnet on!", "color": Color(1.0, 0.45, 0.6), "unlock": 0},
	{"id": "bubbles", "name": "BUBBLE STORM", "pic": "bubblestorm", "line": "Bubbles galore!", "color": Color(0.6, 0.95, 1.0), "unlock": 2},
	{"id": "zoom", "name": "ZOOM WINGS", "pic": "zoomwings", "line": "Zoom zoom!", "color": Color(1.0, 0.85, 0.3), "unlock": 4},
]
const FIRE_R := 10.0  # FIRE BREATH: balloons and sprites this near Sunny's nose pop (4.5 without)
const MAGNET_X := 2.3  # BUNNY MAGNET: stars / bunnies scooped from this many times further
const SHIELD_PUSH := 0.5  # SHIELD BUBBLE: crosswinds push this much
const ZOOM_FLAP := 1.6  # ZOOM WINGS: a flap gives this much more speed
const HATCH_EVERY := 3  # stages finished for each baby dragon
const MAX_BABIES := 12
const BABY_COLORS: Array[Color] = [Color(0.55, 0.85, 1.0), Color(0.6, 0.95, 0.5), Color(1.0, 0.7, 0.85), Color(0.8, 0.65, 1.0),
	Color(1.0, 0.85, 0.4), Color(1.0, 0.6, 0.45)]
## The pick row: big orbs this far ahead (seconds of flight), GAP apart, ROW_UP above Sunny.
const ROW_SECS := 7.0
const ROW_GAP := 15.0
const ROW_UP := 9.5
const ORB_SCALE := 3.5
const CATCH := 2.0  # Sunny's core this near an orb's edge takes it
const ROW_WAIT := 14.0  # nobody reached the row (turned away): the middle one after this


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
	for k in ["events", "cloud_r", "dizzy", "push", "gust"]:  # more of these is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["warn", "slow"]:  # more of these is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(g.dizzy) > 0.0:
		out.append("gentle makes Sunny dizzy")
	for m in MODES:
		if float(MODES[m].push) * float(MODES[m].gust) > MAX_DRIFT:
			out.append("%s: a crosswind pushes too far" % m)
	return out


# --- How far Sunny can move (the same flight as dragon.gd fly()) -------------------------------------------

## Sideways metres Sunny moves in `secs` with the reins pulled `rein` of the way, at speed v (starting straight).
static func lateral(secs: float, v: float, rein: float = DODGE_REIN) -> float:
	var steer := 0.0
	var rate := 0.0
	var yaw := 0.0
	var x := 0.0
	var dt := 1.0 / 30.0
	var t := 0.0
	while t < secs:
		steer = move_toward(steer, rein, dt * 2.2)
		rate = lerpf(rate, steer * Dragon.MAX_YAW_RATE, 1.0 - exp(-2.5 * dt))
		yaw = minf(yaw + rate * dt, PI * 0.5)  # (turning past side-on moves no further sideways)
		x += sin(yaw) * v * dt
		t += dt
	return x


## Metres Sunny climbs in `secs` (the reins raised `rein`).
static func climb(secs: float, rein: float = DODGE_REIN) -> float:
	var c := 0.0
	var vy := 0.0
	var y := 0.0
	var dt := 1.0 / 30.0
	var t := 0.0
	while t < secs:
		c = move_toward(c, rein, dt * 2.2)
		vy = lerpf(vy, c * Dragon.CLIMB_SPEED, 1.0 - exp(-2.0 * dt))
		y += vy * dt
		t += dt
	return y


# --- Events ------------------------------------------------------------------------------------------------

## This stage's events: [{kind, leg, pos, normal, side, size, sign}] in route order. pos: the cloud's middle / the
## band's middle; normal: the way Sunny flies there; side: sideways (right); size: a cloud's radius / Vector2(BAND_LEN,
## BAND_H); sign: the wind blows along side * sign. spec: {mode, season, level, scale (bots: more)}.
static func events(seed_value: int, route: Dictionary, spec: Dictionary) -> Array:
	var out: Array = []
	var lv := int(spec.get("level", route.get("level", 1)))
	var mission := String(route.get("mission", "rings"))
	if mission == "boss" or lv < int(spec.get("from", FIRST_STAGE)):
		return out
	var r := Seeded.rng(seed_value, "sky events")
	var md := mode_data(String(spec.get("mode", "brave")))
	var pts: Array = route.points
	var legs := pts.size() - 1  # leg k: pts[k] -> pts[k + 1] (it ends at ring k)
	var free: Array = []
	for k in range(1, legs - 1):
		free.append(k)
	var want := mini(roundi(float(md.events) * float(spec.get("scale", 1.0))), (free.size() + 1) / 2)
	free = Seeded.shuffled(r, free)
	var used: Array = []
	var w: Array = season_data(String(spec.get("season", "spring"))).weights
	for k in free:
		if out.size() >= want:
			break
		var near := false
		for u in used:
			near = near or absi(int(u) - int(k)) < 2  # one leg between events: never two at once
		if near:
			continue
		var kind: String = KINDS[Seeded.weighted(r, w)]
		var e := _place(r, route, int(k), kind, md)
		if e.is_empty() and kind == "storm":
			e = _place(r, route, int(k), "wind", md)  # a storm wouldn't fit on this leg: a crosswind instead
		if e.is_empty():
			continue
		used.append(k)
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.leg) < int(b.leg))
	return out


## One event on leg k, or {} when none fits there (a few tries).
static func _place(r: RandomNumberGenerator, route: Dictionary, k: int, kind: String, md: Dictionary) -> Dictionary:
	var pts: Array = route.points
	var a: Vector3 = pts[k]
	var b: Vector3 = pts[k + 1]
	var n := (b - a).normalized()
	var side := n.cross(Vector3.UP).normalized()
	for attempt in 4:
		var e := {}
		if kind == "storm":
			var f := r.randf_range(0.47, 0.53)
			var p := a.lerp(b, f) + side * r.randf_range(-2.0, 2.0) + Vector3.UP * r.randf_range(-1.0, 1.0)
			e = {"kind": "storm", "leg": k, "pos": p, "normal": n, "side": side, "size": Vector2(float(md.cloud_r), 0.0), "sign": 1}
		else:
			var f2 := r.randf_range(0.2, 0.32)
			e = {"kind": "wind", "leg": k, "pos": a.lerp(b, f2), "normal": n, "side": side, "size": Vector2(BAND_LEN, BAND_H),
				"sign": -1 if r.randf() < 0.5 else 1}
		if _event_problems(e, route, md).is_empty():
			return e
	return {}


## Reasons one event is unfair against its route (empty = fine).
static func _event_problems(e: Dictionary, route: Dictionary, md: Dictionary) -> Array:
	var why: Array = []
	var p: Vector3 = e.pos
	var k := int(e.leg)
	var pts: Array = route.points
	var v: float = float(route.get("cruise", RouteGen.cruise(int(route.get("level", 1)))))
	var warn := float(md.warn)
	if k < 1 or k >= pts.size() - 2:
		why.append("an event on the first or last leg")
		return why
	var rings: Array = route.rings
	match String(e.kind):
		"storm":
			var cr := float((e.size as Vector2).x)
			# Time to fly round it (or over / under) while it is told: Sunny's middle must get clear of the cloud.
			var off := RouteGen._seg_dist(p, pts[k], pts[k + 1])
			var need := cr + CORE_R - off
			var can := maxf(lateral(warn - REACT, v), climb(warn - REACT))
			if can < need:
				why.append("a storm cloud too big to dodge in %.1f s (%.1f of %.1f m)" % [warn, can, need])
			for ring in rings:
				if (ring.pos as Vector3).distance_to(p) < cr + float(ring.radius) + CLEAR:
					why.append("a storm cloud by a ring")
			for c in route.critters:
				if (c as Vector3).distance_to(p) < cr + CORE_R + CLEAR:  # (flying to the bunny never means flying through it)
					why.append("a storm cloud by a sky bunny")
			if route.golden != null and (route.golden as Vector3).distance_to(p) < cr + 2.0:
				why.append("a storm cloud on the golden balloon")
			for s in route.stars:
				if (s as Vector3).distance_to(p) < cr + STAR_CLEAR:
					why.append("a storm cloud on a star")
			for bl in route.balloons:
				if (bl[0] as Vector3).distance_to(p) < cr + 1.5:
					why.append("a storm cloud on a balloon")
		"wind":
			var drift := float(md.push) * float(md.gust)
			if drift > MAX_DRIFT:
				why.append("a crosswind pushes %.0f m" % drift)
			# After the gust there's time to steer back into the next ring (even flapping fast).
			var ring_at: Vector3 = pts[k + 1]
			var ring_r := float(rings[k].radius) if k < rings.size() else RouteGen.RING_R
			var secs := p.distance_to(ring_at) / (v * FAST) - REACT
			if lateral(secs, v) < drift - ring_r * RECOVER_FRAC:
				why.append("no time to steer back after a crosswind (%.1f s)" % secs)
			if p.distance_to(ring_at) < float(BAND_H) * 0.5 + ring_r:
				why.append("a crosswind band over a ring")
			if k > 0 and p.distance_to(pts[k]) < ring_r + 4.0:
				why.append("a crosswind band on the ring before")
	if warn < MIN_WARN:
		why.append("told only %.1f s early" % warn)
	return why


## Reasons this stage's events are unfair (empty = fine).
static func problems(list: Array, route: Dictionary, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var last := -9
	for e in list:
		if not KINDS.has(String(e.kind)):
			why.append("an unknown event %s" % str(e.kind))
			continue
		if int(e.leg) - last < 2:
			why.append("two events on legs %d and %d" % [last, int(e.leg)])
		last = int(e.leg)
		for x in _event_problems(e, route, md):
			why.append(x)
	if String(route.get("mission", "")) == "boss" and not list.is_empty():
		why.append("events on a Storm King stage")
	return why


## Did Sunny's middle (core, moving from `was` to `now`) fly into a storm cloud / through a band? (host)
static func crossed(e: Dictionary, was: Vector3, now: Vector3) -> bool:
	var n: Vector3 = e.normal
	var p: Vector3 = e.pos
	var d0 := (was - p).dot(n)
	var d1 := (now - p).dot(n)
	if not (d0 < 0.0 and d1 >= 0.0):
		return false
	var rel := now - p - n * d1
	if String(e.kind) == "storm":
		return rel.length() <= float((e.size as Vector2).x) + CORE_R
	var sz: Vector2 = e.size
	return absf(rel.dot(e.side)) <= sz.x * 0.5 and absf(rel.y) <= sz.y * 0.5


## An event as plain values for the network (and back).
static func pack(e: Dictionary) -> Array:
	return [String(e.kind), int(e.leg), e.pos, e.normal, e.side, e.size, int(e.sign)]


static func unpack(a: Array) -> Dictionary:
	return {"kind": String(a[0]), "leg": int(a[1]), "pos": a[2], "normal": a[3], "side": a[4], "size": a[5], "sign": int(a[6])}


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(babies: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if babies >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return GIFTS[0]


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are others
## (the same on every machine for a seed).
static func gift_choices(babies: int, last: String, seed_value: int) -> Array:
	return PickOrbs.gift_choices(unlocked(babies), last, seed_value)  # (the shared gift pick)


# --- The roost --------------------------------------------------------------------------------------------------

static func babies(stages_total: int) -> int:
	return mini(MAX_BABIES, maxi(0, stages_total) / HATCH_EVERY)


## Where baby dragon i flies (dragon-local): a wide V behind Sunny's wings, clear of the gunners' deck.
static func baby_spot(i: int) -> Vector3:
	var side := -1.0 if i % 2 == 0 else 1.0
	var k := i / 2
	return Vector3(side * (6.5 + k * 2.0), -0.5 + (k % 2) * 1.4, 9.0 + k * 3.0)  # (behind the deck: never in a gunner's face)


static func baby_color(i: int) -> Color:
	return BABY_COLORS[i % BABY_COLORS.size()]


# --- The pick row ---------------------------------------------------------------------------------------------

## Where the row's n orbs float (world) for Sunny at `at` heading `yaw` flying at speed v.
static func row_spots(at: Vector3, yaw: float, v: float, n: int = 3, secs: float = ROW_SECS) -> Array:
	var b := Basis(Vector3.UP, yaw)
	var out: Array = []
	for i in n:
		out.append(at + b * Vector3((i - (n - 1) * 0.5) * ROW_GAP, ROW_UP, -v * secs))
	return out


## How near Sunny's middle must come to an orb's middle to take it.
static func catch_r() -> float:
	return PickOrbs.HIT_R * ORB_SCALE + CATCH
