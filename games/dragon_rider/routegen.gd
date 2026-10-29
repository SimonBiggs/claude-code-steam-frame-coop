extends RefCounted
## DRAGON RIDER generator: one level's sky ROUTE as plain data from a seed, so the host and every TV machine
## build exactly the same thing (course.gd only turns it into nodes), and tests/dragon_rider_gen_test.gd proves
## over many seeds that every route is flyable, comfy and fair.
##   var r := RouteGen.route(seed, origin, yaw, level, mission, simple)
##   r = {seed, level, mission, rings: [{pos, normal, radius, final}], stars: [pos], arc: [pos] (the rainbow leg),
##        balloons: [[pos, colour index]], golden: pos or null, critters: [pos], islands: [[pos, r, trees, near, deco]],
##        end: pos (the finish island)}
## Story: SUNNY the dragon flies the family through the sky; every stage finished hangs a CHARM on the gunners'
## deck rail (a bell for rings, a bunny for rescues, a ribbon for races, a crown for the Storm King: saved), and a
## flower garland along the rail grows a blossom each play-day. TODAY'S FLIGHT: the first flight each day uses the
## day's seed on every machine (all its stages), and its charms are golden.
## check(r) is the validator: rings stay in the height band, each leg turns and climbs gently enough for a
## comfy VR flight at the stage's cruise speed (well inside the dragon's turn rate), legs are long enough to line
## up, no sky island sits on the flight path or hides a ring, balloons stay in the gunners' reach and clear of
## the islands and the route, rescue bunnies are close enough to scoop, and the golden balloon is there once
## it's been met.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "dragon_rider"
const SPACING := 74.0  # == course.gd
const FIRST := 95.0  # == course.gd
const RING_R := 6.5  # == course.gd
const RESCUE_R := 9.5  # == course.gd
const MIN_Y := 22.0
const MAX_Y := 85.0
const MAX_YAW_RATE := 0.55  # == dragon.gd
const CLIMB_SPEED := 7.0  # == dragon.gd
const COMFY_TURN := 0.45  # share of the dragon's full turn a leg may need (VR comfort + time to line up)
const COMFY_CLIMB := 0.5  # share of its climb speed
const ISLAND_CLEAR := 10.0  # metres between an island's edge and the flight path
const GUNNER_REACH := 30.0  # balloons within this of the path (bubbles fly 36 m/s; the assist reaches ~40 m)
const BALLOON_CLEAR := 4.0  # balloons at least this far from the path (the dragon pops ones it flies into)
const SCOOP := 13.3  # == RESCUE_R * 1.4 (main.gd's simple-mode scoop distance)
const BALLOON_COLORS := 5
const MAX_STAGE := 12
const TRIES := 6

## Charms (one per stage finished): the kind by the stage's mission.
const CHARMS := {"rings": "bell", "rescue": "bunny", "race": "ribbon", "boss": "crown"}
const CHARM_SLOTS := 22  # 11 under each side of the deck rail
const CHARM_KEEP := 22
const GARLAND_MAX := 20  # blossoms (one per play-day)


## The day's flight seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## Stage n's seed in a flight (a session): every machine derives the same one.
static func stage_seed(flight_seed: int, n: int) -> int:
	return Seeded.derive(flight_seed, "stage%d" % n)


## simple mode's cruise speed (== main.simple_cruise)
static func cruise(n: int) -> float:
	return minf(9.5 + (n - 1) * 0.6, 13.0)


static func ring_count(lv: int, simple: bool) -> int:
	if simple:
		return [4, 5, 6][lv - 1] if lv <= 3 else mini(5 + lv / 2, 9)
	return mini(6 + (lv - 1) * 2, 14)


## The route for a seed. A try check() finds unfair is thrown away and the next (a sub-seed) used, so every
## machine still builds the same route; later tries are gentler.
static func route(seed_value: int, origin: Vector3, yaw: float, lv: int, mission: String, simple: bool = true) -> Dictionary:
	var r := {}
	for attempt in TRIES:
		r = _make(seed_value if attempt == 0 else Seeded.derive(seed_value, "try%d" % attempt), origin, yaw, lv, mission, simple, attempt)
		if check(r).is_empty():
			break
	r.seed = seed_value
	return r


static func _make(seed_value: int, origin: Vector3, yaw: float, lv: int, mission: String, simple: bool, attempt: int) -> Dictionary:
	var rng := Seeded.rng(seed_value, "route")
	var easy := simple and lv <= 2
	var has_stars := not simple or lv >= 2
	var has_golden := not simple or lv >= 3
	var count := ring_count(lv, simple)
	if mission == "rescue":
		count = maxi(5, count - 2)
	elif mission == "boss":
		count = 6
	var calm := 1.0 - 0.15 * attempt  # gentler tries
	var out := {"seed": seed_value, "level": lv, "mission": mission, "simple": simple, "origin": origin,
		"rings": [], "stars": [], "arc": [], "balloons": [], "golden": null, "critters": [], "islands": [], "end": Vector3.ZERO,
		"cruise": cruise(lv) if simple else 13.0, "has_golden": has_golden, "points": [origin]}
	var heading := yaw
	var pos := origin
	var prev := origin
	var arc_leg := count / 2 if count > 3 and has_stars else -1
	var critter_legs: Array = []
	if mission == "rescue":
		var nc := mini(3 + lv / 3, count - 1)
		for k in nc:
			critter_legs.append(1 + int(float(k) * (count - 1) / nc))
	var golden_leg := 1 + rng.randi() % maxi(1, count - 2)
	var normal := Vector3.FORWARD
	for k in count:
		var dist := FIRST if k == 0 else SPACING
		var wiggle := 0.55 * minf(1.0, 0.5 + lv * 0.15)
		var dy := 12.0
		if easy:
			dist = 60.0 if k == 0 else 62.0
			wiggle = 0.12 if lv == 1 else 0.25
			dy = 3.0 if lv == 1 else 6.0
		elif simple:
			wiggle = minf(wiggle, 0.4)
			dy = 8.0
		wiggle *= calm
		dy *= calm
		if k > 0:
			heading += rng.randf_range(-1.0, 1.0) * wiggle
		var y := clampf(pos.y + rng.randf_range(-dy, dy), MIN_Y, MAX_Y)
		pos = pos + Basis(Vector3.UP, heading) * Vector3.FORWARD * dist
		pos.y = y
		normal = (pos - prev).normalized()
		(out.points as Array).append(pos)
		var final := k == count - 1
		if mission != "boss":
			var r0 := RING_R
			if simple:
				r0 = 9.5 if lv == 1 else (8.5 if lv == 2 else 7.5)
			(out.rings as Array).append({"pos": pos, "normal": normal, "radius": r0 * (1.3 if final else 1.0), "final": final})
		var side := normal.cross(Vector3.UP).normalized()
		if has_stars:
			if k == arc_leg:
				var arc_h := 9.0 + rng.randf() * 3.0
				for j in 7:
					var f := 0.15 + j * 0.7 / 6.0
					var sp := prev.lerp(pos, f) + Vector3.UP * sin(f * PI) * arc_h
					(out.stars as Array).append(sp)
					(out.arc as Array).append(sp)
			else:
				for j in 2:
					var f := 0.35 + j * 0.3
					var sp := prev.lerp(pos, f) + side * rng.randf_range(-3.0, 3.0) + Vector3.UP * rng.randf_range(-2.0, 2.0)
					if k == 0:
						sp = origin.lerp(pos, 0.55 + j * 0.2)
					(out.stars as Array).append(sp)
		var nb := 3 if easy or lv >= 3 else 2
		for j in nb:
			var s := -1.0 if rng.randf() < 0.5 else 1.0
			var bp := prev.lerp(pos, rng.randf_range(0.2, 0.9)) + side * s * rng.randf_range(9.0, 22.0) + Vector3.UP * rng.randf_range(-5.0, 9.0)
			if easy:
				bp = prev.lerp(pos, 0.2 + 0.25 * j + rng.randf_range(0.0, 0.1)) + side * s * rng.randf_range(5.0, 9.0) + Vector3.UP * rng.randf_range(-1.0, 4.0)
			(out.balloons as Array).append([bp, rng.randi() % BALLOON_COLORS])
		if k == golden_leg and has_golden:
			var gs := -1.0 if rng.randf() < 0.5 else 1.0
			out.golden = prev.lerp(pos, 0.5) + side * gs * rng.randf_range(10.0, 15.0) + Vector3.UP * rng.randf_range(2.0, 7.0)
		if critter_legs.has(k):
			var cs := -1.0 if rng.randf() < 0.5 else 1.0
			(out.critters as Array).append(prev.lerp(pos, rng.randf_range(0.4, 0.6)) + side * cs * rng.randf_range(7.0, 11.0) + Vector3.UP * rng.randf_range(-2.0, 3.0))
		# A sky island beside the route, and (every other leg) a big one far off as scenery.
		var isl_side := -1.0 if rng.randf() < 0.5 else 1.0
		(out.islands as Array).append([prev.lerp(pos, 0.5) + side * isl_side * rng.randf_range(32.0, 55.0) + Vector3.UP * rng.randf_range(-22.0, -6.0),
			rng.randf_range(6.0, 12.0), 1 + rng.randi() % 2, true, rng.randi() % 1000000])
		var far_pos := prev.lerp(pos, 0.5) - side * isl_side * rng.randf_range(110.0, 190.0) + Vector3.UP * rng.randf_range(-40.0, 10.0)
		var far_r := rng.randf_range(18.0, 34.0)
		if k % 2 == 0:
			(out.islands as Array).append([far_pos, far_r, 0, false, rng.randi() % 1000000])
		prev = pos
	var end_n := (pos - origin).normalized() if (out.rings as Array).is_empty() else ((out.rings as Array)[-1].normal as Vector3)
	out.end = pos + end_n * 70.0 + Vector3.UP * -30.0
	(out.islands as Array).append([out.end, 22.0, 3, false, rng.randi() % 1000000])
	return out


## The flight path: the origin, then every leg's end (the rings; boss levels have the same legs without rings).
static func path(r: Dictionary) -> Array:
	return r.points


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _path_dist(p: Vector3, pts: Array) -> float:
	var best := INF
	for i in range(1, pts.size()):
		best = minf(best, _seg_dist(p, pts[i - 1], pts[i]))
	return best


static func _flat_heading(v: Vector3) -> float:
	return atan2(-v.x, -v.z)


## Problems with a route (empty = fair).
static func check(r: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var rings: Array = r.rings
	var v: float = float(r.cruise)
	if String(r.mission) != "boss" and rings.size() < 4:
		why.append("only %d rings" % rings.size())
	var pts := path(r)
	var prev_h := INF
	for i in range(1, pts.size()):
		var p: Vector3 = pts[i]
		if p.y < MIN_Y - 0.01 or p.y > MAX_Y + 0.01:
			why.append("ring %d at height %.0f" % [i, p.y])
		var a: Vector3 = pts[i - 1]
		var leg := p - a
		var flat := Vector2(leg.x, leg.z).length()
		if flat < 50.0:
			why.append("leg %d is too short to line up (%.0f m)" % [i, flat])
		var secs := flat / v
		var h := _flat_heading(leg)
		if prev_h != INF:
			var turn := absf(wrapf(h - prev_h, -PI, PI))
			if turn > MAX_YAW_RATE * secs * COMFY_TURN:
				why.append("leg %d turns %.2f rad in %.1f s (too sharp for a comfy flight)" % [i, turn, secs])
		prev_h = h
		if absf(leg.y) > CLIMB_SPEED * secs * COMFY_CLIMB:
			why.append("leg %d climbs %.0f m in %.1f s" % [i, leg.y, secs])
	for i in rings.size():
		if not (rings[i].normal as Vector3).is_normalized():
			why.append("ring %d faces nowhere" % i)
	for isl in r.islands:
		var c: Vector3 = isl[0]
		var rad: float = isl[1]
		# An island is a disc (radius rad) with rock hanging under it (1.5 rad): treat it as a ball of 1.2 rad.
		var d := _path_dist(c, pts)
		if d < rad * 1.2 + ISLAND_CLEAR and c != r.end:
			why.append("an island (r %.0f) sits %.0f m from the flight path" % [rad, d])
		for ring in rings:
			if (ring.pos as Vector3).distance_to(c) < rad * 1.2 + float(ring.radius) + 4.0:
				why.append("an island hides a ring")
	var balls: Array = r.balloons.map(func(b: Array) -> Vector3: return b[0])
	if r.golden != null:
		balls.append(r.golden)
	elif bool(r.has_golden):
		why.append("no golden balloon")
	for bp in balls:
		var d := _path_dist(bp, pts)
		if d > GUNNER_REACH:
			why.append("a balloon is out of the gunners' reach (%.0f m)" % d)
		for isl in r.islands:
			if (bp as Vector3).distance_to(isl[0]) < float(isl[1]) * 1.2 + 2.0:
				why.append("a balloon is inside an island")
				break
	for c in r.critters:
		var d := _path_dist(c, pts)
		if d > SCOOP - 1.0:
			why.append("a sky bunny is too far to scoop (%.1f m)" % d)
	return why


## Where charm i hangs on the deck rail (dragon-local), Vector3.INF past the end.
static func charm_slot(i: int) -> Vector3:
	if i < 0 or i >= CHARM_SLOTS:
		return Vector3.INF
	var side := -1.0 if i % 2 == 0 else 1.0
	var k := i / 2  # 0..10 from the front of the deck
	return Vector3(1.2 * side, 0.0, 1.15 + k * 0.38)  # just outside the rail posts


## Blossoms on the garland: one per play-day.
static func garland(days: int) -> int:
	return clampi(days, 0, GARLAND_MAX)
