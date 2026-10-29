extends RefCounted
## STARSHIP CREW seeded missions: the same seed gives the same mission on every machine.
## A mission is a KIND (rings, rocks, aliens, mixed, home) at a TIER (0 = the gentle lessons, up to
## TIERS - 1) and plays as "laps" of LAP seconds: a timeline of things that come at the ship.
##   var m := MissionGen.generate(seed, "rocks", tier, lap)
##   m = {"seed", "kind", "tier", "lap", "speed", "len", "events": [[t, what, x, y, dz, vx, vy, vz, sway], ...]}
## what: Space.RING (x, y are ABSOLUTE: the ring path the pilot steers along), Space.ROCK or Space.UFO
## (x, y are RELATIVE to the ship when it appears: they come at the crew wherever the ship is).
## dz: extra distance ahead of Space.SPAWN_Z. v: a rock's drift. sway: how far an alien wiggles sideways.
## check(m) is the validator (tests/starship_crew_gen_test.gd runs it over many seeds and tiers):
## every ring is in bounds and reachable from the one before (and laps join up), every rock and alien
## shows on the TV screen long enough to zap, waves don't overlap, never too many at once, enough
## stars for the crew to finish, targets on both sides of the screen (every gunner gets a fair go).

const Seeded := preload("res://core/seeded.gd")
const Space := preload("res://games/starship_crew/space.gd")
const UiKit := preload("res://core/ui_kit.gd")

const KINDS: Array[String] = ["rings", "rocks", "aliens", "mixed", "home"]
const TIERS := 5
const LAP := 40.0  ## seconds per lap of a mission's timeline
const NEED := 8  ## stars per mission
const STEER := 5.0  ## the ship's sideways speed (main.gd STEER_SPEED)
const REACT := 0.8  ## seconds a pilot needs to see a ring and start steering
const REACH_SHARE := 0.5  ## a ring is never further from the one before than half the most the ship can slide
const END_ZONE := 2.0  ## the first and last ring of a lap are this close to the middle (laps join up)
const RING_BOX := Vector2(7.0, 3.4)  ## rings stay inside this (Space.LIMIT is 8 x 4)
const MAX_AT_ONCE := 22  ## most rocks + aliens zappable at once (before any are zapped)
const ON_SCREEN := 1.5  ## seconds every target must be zappable and on the TV screen
const SAME_WAVE := 2.6  ## metres between targets arriving together
## The TV camera never moves (the ship stays at the origin): main.gd uses these too.
const CAM_POS := Vector3(0.0, 3.4, 10.5)
const CAM_LOOK := Vector3(0.0, 0.6, -30.0)
const CAM_FOV := 60.0
const ASPECT := 16.0 / 9.0

## Seconds between rings / rock waves / alien waves for each kind at tier 0 (0 = none).
const GAPS := {
	"rings": [3.6, 3.2, 0.0],
	"rocks": [5.5, 1.4, 0.0],
	"aliens": [5.5, 3.0, 3.6],
	"mixed": [4.5, 2.2, 5.0],
	"home": [4.5, 2.0, 6.5],
}
const ROCK_WAVES: Array[String] = ["single", "pair", "line", "vee", "rain"]
const UFO_WAVES: Array[String] = ["single", "wide", "trio"]


static func speed_for(tier: int) -> float:
	return 10.0 + 0.5 * clampi(tier, 0, TIERS - 1)


## How far apart (m) two rings `dt` seconds apart may be, and still be easy.
static func reach(dt: float) -> float:
	return REACH_SHARE * STEER * maxf(0.0, dt - REACT)


static func generate(seed_value: int, kind: String, tier: int, lap: int = 0) -> Dictionary:
	tier = clampi(tier, 0, TIERS - 1)
	if not GAPS.has(kind):
		kind = "mixed"
	var r := Seeded.rng(seed_value, "%s/%d/%d" % [kind, tier, lap])
	var gaps: Array = GAPS[kind]
	var ev: Array = []
	# Rings: a path that wanders, each ring within easy reach of the last, starting and ending near the middle.
	var rg := float(gaps[0]) * (1.0 - 0.05 * tier)
	if rg > 0.0:
		var t := r.randf_range(1.0, 2.0)
		var at := Vector2(r.randf_range(-1.5, 1.5), r.randf_range(-1.0, 1.0))
		var share := 0.4 + 0.12 * tier  # how much of the easy reach a step uses
		while t < LAP - 2.0:
			ev.append([snappedf(t, 0.01), Space.RING, snappedf(at.x, 0.01), snappedf(at.y, 0.01), 0.0, 0.0, 0.0, 0.0, 0.0])
			var dt := rg * r.randf_range(0.9, 1.15)
			var nt := t + dt
			var step := reach(dt) * share * r.randf_range(0.5, 1.0)
			var dir := Vector2.from_angle(r.randf_range(0.0, TAU))
			var nxt := at + dir * step
			if nt > LAP - 12.0:  # near the end of the lap the path heads back to the middle
				nxt = at.move_toward(Vector2.ZERO, reach(dt) * maxf(share, 0.6))
			if nt + rg * 1.15 >= LAP - 2.0:  # ... and the last ring is right there
				nxt = at.move_toward(Vector2.ZERO, reach(dt) * 0.95)
			if absf(nxt.x) > RING_BOX.x or absf(nxt.y) > RING_BOX.y:  # bounce off the edge of space
				nxt = (at - dir * step).clamp(-RING_BOX * 0.95, RING_BOX * 0.95)
			at = nxt
			t = nt
	# Rock waves: left and right in turn (every gunner gets a go), never on top of the wave before.
	var kg := float(gaps[1]) * (1.0 - 0.06 * tier)
	if kg > 0.0:
		var t := r.randf_range(0.5, 1.5)
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var placed: Array = []
		while t < LAP - 0.5:
			var wave: String = ROCK_WAVES[0] if kind != "rocks" and r.randf() < 0.6 - 0.08 * tier else Seeded.pick(r, ROCK_WAVES)
			side = -side
			for attempt in 6:
				var c := Vector2(side * r.randf_range(0.5, 5.5), r.randf_range(-2.5, 3.5))
				var w := _rock_wave(wave, c, r)
				for k in w:
					k[0] = snappedf(t + float(k[0]), 0.01)
				if _clear_of(w, placed, speed_for(tier)):
					placed.append_array(w)
					ev.append_array(w)
					break
			t += kg * r.randf_range(0.8, 1.2) * (1.6 if wave in ["line", "vee", "rain"] else 1.0)
	# Alien waves.
	var ug := float(gaps[2]) * (1.0 - 0.05 * tier)
	if ug > 0.0:
		var t := r.randf_range(1.0, 2.5)
		var side := 1.0 if r.randf() < 0.5 else -1.0
		while t < LAP - 0.5:
			var wave: String = Seeded.pick(r, UFO_WAVES)
			side = -side
			var sway := 3.0 + 0.3 * tier
			if wave == "trio":
				for i in 3:
					ev.append([snappedf(t + i * 0.4, 0.01), Space.UFO, float(i - 1) * 5.0, snappedf(r.randf_range(0.8, 2.2), 0.01), 0.0, 0.0, 0.0, 0.0, 1.4])
				t += ug * 2.2
				continue
			if wave == "wide":
				sway = 4.5 + 0.2 * tier
			var x := side * r.randf_range(0.5, 3.5)
			ev.append([snappedf(t, 0.01), Space.UFO, snappedf(x, 0.01), snappedf(r.randf_range(0.5, 2.5), 0.01), 0.0, 0.0, 0.0, 0.0, snappedf(sway, 0.01)])
			t += ug * r.randf_range(0.85, 1.2)
	ev = ev.filter(func(e: Array) -> bool: return float(e[0]) < LAP - 0.05)
	ev.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	return {"seed": seed_value, "kind": kind, "tier": tier, "lap": lap, "speed": speed_for(tier), "len": LAP, "events": ev}


## True when none of the rocks in `wave` would be on top of one already placed.
static func _clear_of(wave: Array, placed: Array, speed: float) -> bool:
	for b in wave:
		for i in range(placed.size() - 1, -1, -1):
			var a: Array = placed[i]
			var dt := float(b[0]) - float(a[0])
			if dt > 1.6:
				break
			if dt >= 0.0 and target_at(a, dt, speed).distance_to(target_at(b, 0.0, speed)) < SAME_WAVE + 0.2:
				return false
	return true


## One rock wave around centre c (relative to the ship): [dt, ROCK, x, y, dz, vx, vy, vz, 0].
static func _rock_wave(wave: String, c: Vector2, r: RandomNumberGenerator) -> Array:
	var spots: Array = []  # [dt, offset, dz]
	match wave:
		"single":
			spots = [[0.0, Vector2.ZERO, r.randf_range(0.0, 10.0)]]
		"pair":
			spots = [[0.0, Vector2(-1.5, 0.0), 0.0], [0.0, Vector2(1.5, 0.3), 3.0]]
		"line":
			spots = [[0.0, Vector2(-2.8, 0.0), 0.0], [0.0, Vector2(0.0, 0.2), 0.0], [0.0, Vector2(2.8, 0.0), 0.0]]
		"vee":
			spots = [[0.0, Vector2(-2.6, 1.0), 0.0], [0.0, Vector2(0.0, -0.4), 4.0], [0.0, Vector2(2.6, 1.0), 0.0]]
		"rain":
			spots = [[0.0, Vector2(-2.0, 1.5), 0.0], [0.6, Vector2(0.0, 0.0), 0.0], [1.2, Vector2(2.0, -1.5), 0.0]]
	# keep the whole wave in the zone the TV camera sees well
	var lo := Vector2(-7.0, -2.8)
	var hi := Vector2(7.0, 4.0)
	var minx := INF
	var maxx := -INF
	var miny := INF
	var maxy := -INF
	for s in spots:
		var o: Vector2 = c + s[1]
		minx = minf(minx, o.x)
		maxx = maxf(maxx, o.x)
		miny = minf(miny, o.y)
		maxy = maxf(maxy, o.y)
	c += Vector2(maxf(0.0, lo.x - minx) - maxf(0.0, maxx - hi.x), maxf(0.0, lo.y - miny) - maxf(0.0, maxy - hi.y))
	var out: Array = []
	var drift := r.randf_range(-0.5, 0.5) if wave == "single" else 0.0
	for s in spots:
		var o: Vector2 = c + s[1]
		out.append([float(s[0]), Space.ROCK, snappedf(o.x, 0.01), snappedf(o.y, 0.01), snappedf(float(s[2]), 0.01),
			snappedf(drift, 0.01), snappedf(r.randf_range(-0.2, 0.2) if wave == "single" else 0.0, 0.01), snappedf(r.randf_range(-1.5, 1.5) if wave == "single" else 0.0, 0.01), 0.0])
	return out


# --- Where things are (the same maths the game uses) --------------------------------------------

static func cam_xf() -> Transform3D:
	return Transform3D(UiKit.face(CAM_LOOK - CAM_POS), CAM_POS)


## Where a world point shows on the TV screen (-1..1, y up), or far off-screen behind the camera.
static func project(w: Vector3) -> Vector2:
	var q := cam_xf().affine_inverse() * w
	if q.z > -0.5:
		return Vector2(9.0, 9.0)
	var t := tan(deg_to_rad(CAM_FOV) * 0.5)
	return Vector2(q.x / (-q.z * t * ASPECT), q.y / (-q.z * t))


static func screen_ray(uv: Vector2) -> Vector3:
	var t := tan(deg_to_rad(CAM_FOV) * 0.5)
	return (cam_xf().basis * Vector3(uv.x * t * ASPECT, uv.y * t, -1.0)).normalized()


## A target's position relative to the ship `age` seconds after it appeared (ship holding still).
## Aliens: the worst-case sideways wiggle `wig` (-1..1) of their sway.
static func target_at(e: Array, age: float, speed: float, wig: float = 0.0) -> Vector3:
	if int(e[1]) == Space.UFO:
		var z := minf(-32.0, Space.UFO_Z + (speed + 6.0) * age)
		if age > Space.UFO_STAY:
			return Vector3(INF, INF, INF)
		return Vector3(float(e[2]) + wig * float(e[8]), float(e[3]) + wig * 1.2, z)
	return Vector3(float(e[2]) + float(e[5]) * age, float(e[3]) + float(e[6]) * age, Space.SPAWN_Z + float(e[4]) + (speed + float(e[7])) * age)


static func stars_of(what: int) -> int:
	return 2 if what == Space.RING or what == Space.UFO else 1


# --- The validator --------------------------------------------------------------------------------

static func check(m: Dictionary) -> Array:
	var why: Array = []
	var ev: Array = m.events
	var speed := float(m.speed)
	var kind := String(m.kind)
	var last_t := -1.0
	var rings: Array = []
	var targets: Array = []
	for e in ev:
		if float(e[0]) < last_t:
			why.append("events out of order at %.2f" % float(e[0]))
		last_t = float(e[0])
		if float(e[0]) < 0.0 or float(e[0]) >= float(m.len):
			why.append("event outside the lap at %.2f" % float(e[0]))
		if int(e[1]) == Space.RING:
			rings.append(e)
		else:
			targets.append(e)
	# Rings: in bounds, reachable one after another, laps join up, and the first is reachable from anywhere.
	var gaps: Array = GAPS[kind]
	if float(gaps[0]) > 0.0 and rings.size() < int(float(m.len) / (float(gaps[0]) * 1.4)):
		why.append("too few rings (%d)" % rings.size())
	for i in rings.size():
		var p := Vector2(float(rings[i][2]), float(rings[i][3]))
		if absf(p.x) > RING_BOX.x + 0.01 or absf(p.y) > RING_BOX.y + 0.01:
			why.append("ring out of bounds at %s" % str(p))
		if i > 0:
			var q := Vector2(float(rings[i - 1][2]), float(rings[i - 1][3]))
			var dt := float(rings[i][0]) - float(rings[i - 1][0])
			if p.distance_to(q) > reach(dt) + 0.01:
				why.append("ring %d can't be reached in time (%.1f m in %.1f s)" % [i, p.distance_to(q), dt])
	if not rings.is_empty():
		var first := Vector2(float(rings[0][2]), float(rings[0][3]))
		var last := Vector2(float(rings[-1][2]), float(rings[-1][3]))
		if first.length() > END_ZONE + 0.01 or last.length() > END_ZONE + 0.01:
			why.append("a lap's rings don't start and end near the middle")
		var wrap := float(m.len) - float(rings[-1][0]) + float(rings[0][0])
		if 2.0 * END_ZONE > reach(wrap) + 0.01:
			why.append("the next lap's first ring comes too soon (%.1f s)" % wrap)
		var from_edge := (Space.LIMIT.length() + END_ZONE) / STEER + REACT
		if float(rings[0][0]) + -Space.SPAWN_Z / speed < from_edge:
			why.append("the first ring comes before a ship at the edge could get there")
	# Targets: on the TV screen long enough to zap, not on top of each other, never too many at once.
	var left := 0
	var right := 0
	var gunner_stars := 0
	for e in targets:
		gunner_stars += stars_of(int(e[1]))
		var x0 := float(e[2])
		if x0 < -0.3:
			left += 1
		elif x0 > 0.3:
			right += 1
		for wig in ([-1.0, 1.0] if int(e[1]) == Space.UFO else [0.0]):
			var seen := 0.0
			var age := 0.0
			while age < 25.0:
				var rp := target_at(e, age, speed, wig)
				if rp.x == INF or rp.z > -3.0:
					break
				if rp.z > -95.0:
					var uv := project(Vector3(rp.x, rp.y + Space.SHIP_Y, rp.z))
					if absf(uv.x) < 0.88 and absf(uv.y) < 0.82:
						seen += 0.1
				age += 0.1
			if seen < ON_SCREEN:
				why.append("a target at %.1f s is on screen only %.1f s" % [float(e[0]), seen])
	for i in targets.size():
		for j in range(i + 1, targets.size()):
			var a: Array = targets[i]
			var b: Array = targets[j]
			var dt := float(b[0]) - float(a[0])
			if dt > 1.5:
				break
			if int(a[1]) == Space.UFO or int(b[1]) == Space.UFO:
				if int(a[1]) == int(b[1]) and absf(float(a[2]) - float(b[2])) < SAME_WAVE and dt < 0.5:
					why.append("two aliens on top of each other at %.1f s" % float(a[0]))
				continue
			if target_at(a, dt, speed).distance_to(target_at(b, 0.0, speed)) < SAME_WAVE:
				why.append("two rocks on top of each other at %.1f s" % float(a[0]))
	var t := 0.0
	while t < float(m.len):
		var n := 0
		for e in targets:
			var age := t - float(e[0])
			if age >= 0.0 and age < 25.0:
				var rp := target_at(e, age, speed)
				if rp.x != INF and rp.z > -95.0 and rp.z < -3.0:
					n += 1
		if n > MAX_AT_ONCE:
			why.append("%d targets at once at %.0f s" % [n, t])
			break
		t += 0.5
	# Stars: plenty for the crew (even missing half), and the gunners always have something to zap.
	var ring_stars := rings.size() * 2
	if ring_stars + gunner_stars < 3 * NEED:
		why.append("too few stars in a lap (%d)" % (ring_stars + gunner_stars))
	if gunner_stars < NEED:
		why.append("too little for the gunners (%d stars)" % gunner_stars)
	if targets.size() >= 6 and (left < targets.size() / 4 or right < targets.size() / 4):
		why.append("targets all on one side (%d left, %d right)" % [left, right])
	return why


## Rough difficulty number for the tests (more and faster things = harder).
static func busyness(m: Dictionary) -> float:
	var n := 0.0
	for e in m.events:
		n += 1.0 if int(e[1]) != Space.RING else 0.5
	return n * float(m.speed)
