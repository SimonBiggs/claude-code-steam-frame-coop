extends RefCounted
## SNOWBALL BLITZ surprises (third pass): every siege has one to three WARNED SURPRISES, made from the siege's seed
## (its own stream: the waves stay exactly as siegegen.gd makes them), so TODAY'S BLIZZARD has the same ones on every
## machine. Each one is TOLD first by a steady warn ring on the snow (core/warn_rings.gd) and a picture card, then goes:
##   "slide"   SNOW SLIDE: a big snowball rolls off the hills along a told LINE across the square (outside the fort)
##             and bowls over every snowman in its path (the boss just wobbles).
##   "icicles" ICICLES: two or three told CIRCLES on the fort walls; icicles drop out of the clouds, squash a little
##             snow off those walls (never the last of it) and splat anyone standing in a circle (a harmless cold
##             splat). Nobody's start spot is ever inside one: a child who never moves is never hit.
##   var plan := Tricks.plan(siege)           # {wave (int): {kind, at, tell, ...}}
##   Tricks.check(plan, mode) -> problems     # the validator (tests/snowball_blitz_deep3_test.gd)
## Never in waves 1-2, never in a boss wave, at most one per wave; told for at least MIN_TELL[mode] seconds
## (gentle longest); fired AT seconds into the wave (after the first snowmen are out, before the wave can be over).

const Seeded := preload("res://core/seeded.gd")
const WarnRings := preload("res://core/warn_rings.gd")

const ARENA_RADIUS := 20.0  # == main.gd
const FORT_RADIUS := 6.0  # == main.gd
const SEGMENTS := 8  # == main.gd
const FIRST_WAVE := 3
const LAST_WAVE := 9  # (the yeti's wave 10 and the king's 7 are boss waves: never)
const BOSS_WAVES: Array[int] = [7, 10]  # == SiegeGen.KING_WAVE, FINALE
const KINDS: Array[String] = ["slide", "icicles"]
const NAMES := {"slide": "SNOW SLIDE!", "icicles": "ICICLES!"}
const PICS := {"slide": "snowslide", "icicles": "icicles"}
## Warn colours (on the snow: deep, not pale; palette.gd checks them): a deep orange line, a deep violet-blue circle.
const COLORS := {"slide": Color(0.95, 0.42, 0.08), "icicles": Color(0.42, 0.25, 0.95)}
const TELL := {"gentle": 4.0, "brave": 3.0, "hard": 2.5}
const MIN_TELL := {"gentle": 3.5, "brave": 2.5, "hard": 2.0}
const AT_MIN := 6.0  # s into the wave
const AT_MAX := 13.0
## Snow slide: the line's nearest point to the fort's middle is SLIDE_D away (outside the walls with room to spare),
## it starts and ends beyond the arena's edge; the ball is SLIDE_R big and rolls SLIDE_SPEED m/s.
const SLIDE_D := Vector2(8.5, 14.0)
const SLIDE_END := ARENA_RADIUS + 3.0
const SLIDE_W := 3.0
const SLIDE_R := 1.3
const SLIDE_SPEED := 13.0
## Icicles: circles this big on the wall segments, this much snow off a wall (a wall keeps at least ICICLE_KEEP).
const ICICLE_R := 1.2
const ICICLE_HIT := {"gentle": 15.0, "brave": 25.0, "hard": 32.0}
const ICICLE_KEEP := 30.0
const ICICLE_N := Vector2i(2, 3)
## Every start spot (main.gd _spawn_spot: networked VR at the middle + TV spots, local split screen P1 / P2): a
## told circle keeps CLEAR from each (the test checks these against main.gd).
const START_SPOTS: Array[Vector3] = [Vector3.ZERO, Vector3(-2.2, 0, 2.6), Vector3(2.2, 0, 2.6), Vector3(0, 0, 3.6),
	Vector3(-3.6, 0, 0.8), Vector3(3.6, 0, 0.8), Vector3(0, 0, -2.8), Vector3(-2.0, 0, 2.6), Vector3(2.0, 0, 2.6)]
const CLEAR := 0.8  # metres between a told circle's edge and a start spot (a player's body + a little)


static func seg_center(i: int) -> Vector3:  # == main.seg_center
	var a := TAU * float(i) / float(SEGMENTS)
	return Vector3(cos(a), 0.0, sin(a)) * FORT_RADIUS


## The siege's surprises: {wave: {kind, at, tell, ...}}. slide: from, dir, len; icicles: segs (wall indices).
static func plan(s: Dictionary) -> Dictionary:
	var mode := String(s.get("mode", "brave"))
	if not TELL.has(mode):
		mode = "brave"
	var r := Seeded.rng(int(s.get("seed", 0)), "tricks")
	var waves: Array[int] = []
	for n in range(FIRST_WAVE, LAST_WAVE + 1):
		if not BOSS_WAVES.has(n):
			waves.append(n)
	var order: Array = Seeded.shuffled(r, waves)
	var count := r.randi_range(1, 3)
	var out := {}
	var kinds: Array = Seeded.shuffled(r, KINDS.duplicate())
	for k in count:
		var n: int = order[k]
		var kind: String = kinds[k % kinds.size()]
		var t := one(r, kind, mode)
		out[n] = t
	return out


## One surprise of a kind (from the plan's stream; main.gd's SB_TRICK test setting uses it too).
static func one(r: RandomNumberGenerator, kind: String, mode: String = "brave") -> Dictionary:
	var t := {"kind": kind, "at": snappedf(r.randf_range(AT_MIN, AT_MAX), 0.1), "tell": float(TELL.get(mode, TELL["brave"]))}
	if kind == "slide":
		var a := r.randf() * TAU
		var d := r.randf_range(SLIDE_D.x, SLIDE_D.y)
		var mid := Vector3(cos(a), 0.0, sin(a)) * d
		var dir := Vector3(-sin(a), 0.0, cos(a)) * (1.0 if r.randf() < 0.5 else -1.0)
		var half := sqrt(maxf(0.0, SLIDE_END * SLIDE_END - d * d))
		t.from = mid - dir * half
		t.dir = dir
		t.len = half * 2.0
	else:
		var segs: Array[int] = []
		var pool: Array = Seeded.shuffled(r, range(SEGMENTS))
		for i in r.randi_range(ICICLE_N.x, ICICLE_N.y):
			segs.append(int(pool[i]))
		t.segs = segs
	return t


## Problems with a plan ([] = fair).
static func check(p: Dictionary, mode: String = "brave") -> Array[String]:
	var bad: Array[String] = []
	if p.is_empty() or p.size() > 3:
		bad.append("a siege has 1-3 surprises (%d)" % p.size())
	for n in p:
		var t: Dictionary = p[n]
		if int(n) < FIRST_WAVE or int(n) > LAST_WAVE:
			bad.append("surprise in wave %d (only waves %d-%d)" % [int(n), FIRST_WAVE, LAST_WAVE])
		if BOSS_WAVES.has(int(n)):
			bad.append("surprise in boss wave %d" % int(n))
		if not KINDS.has(String(t.get("kind", ""))):
			bad.append("unknown surprise %s" % str(t.get("kind")))
			continue
		if float(t.tell) < float(MIN_TELL.get(mode, 2.5)):
			bad.append("wave %d: told only %.1f s (%s needs %.1f)" % [int(n), float(t.tell), mode, float(MIN_TELL.get(mode, 2.5))])
		if float(t.at) < AT_MIN or float(t.at) > AT_MAX:
			bad.append("wave %d: fires at %.1f s" % [int(n), float(t.at)])
		for z in zones(t):
			for sp in START_SPOTS:
				if WarnRings.inside(String(z.kind), z.pos, z.dir, z.size, sp, CLEAR):
					bad.append("wave %d: %s covers a start spot %s" % [int(n), t.kind, str(sp)])
		if t.kind == "slide":
			var from: Vector3 = t.from
			var to: Vector3 = from + (t.dir as Vector3) * float(t.len)
			if Vector2(from.x, from.z).length() < ARENA_RADIUS or Vector2(to.x, to.z).length() < ARENA_RADIUS:
				bad.append("wave %d: the snow slide starts or ends inside the square" % int(n))
			if _line_dist(from, t.dir, float(t.len), Vector3.ZERO) < FORT_RADIUS + SLIDE_W * 0.5 + 1.0:
				bad.append("wave %d: the snow slide runs through the fort" % int(n))
		else:
			var segs: Array = t.segs
			var seen := {}
			for i in segs:
				if int(i) < 0 or int(i) >= SEGMENTS or seen.has(int(i)):
					bad.append("wave %d: bad wall %s" % [int(n), str(i)])
				seen[int(i)] = true
			if segs.size() < ICICLE_N.x or segs.size() > ICICLE_N.y:
				bad.append("wave %d: %d icicle circles" % [int(n), segs.size()])
	return bad


## The told shapes: [{kind: "circle"|"line", pos, dir, size}] (main.gd draws exactly these; the check reads them).
static func zones(t: Dictionary) -> Array:
	if String(t.get("kind", "")) == "slide":
		return [{"kind": "line", "pos": t.from, "dir": t.dir, "size": Vector2(float(t.len), SLIDE_W)}]
	var out: Array = []
	for i in t.get("segs", []):
		out.append({"kind": "circle", "pos": seg_center(int(i)), "dir": Vector3.FORWARD, "size": Vector2(ICICLE_R, 0.0)})
	return out


static func _line_dist(from: Vector3, dir: Vector3, length: float, p: Vector3) -> float:
	var k := clampf((p - from).dot(dir), 0.0, length)
	var q := from + dir * k
	return Vector2(q.x - p.x, q.z - p.z).length()

