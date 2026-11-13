extends Node3D
## ROLO'S ROLLERS (Tower Stack, third pass): Rolo the hedgehog, Wren's playful neighbour, rolls a big seasonal ball
## across the park now and then (spring: a rainbow ball, summer: a beach ball, autumn: a pumpkin, winter: a
## snowball). Every roll is TOLD first: for WARN seconds a glowing lane lies across the grass from where the ball
## waits (wiggling at the park's edge) to where it goes, and stays lit while it rolls. A TV builder in the lane gets
## bowled over (a big hop sideways: never hurt), unless they step out or JUMP right over the ball; loose blocks in
## the lane get knocked aside. The lanes never cross the tower stage, the pad or the village green (green.gd).
## Seeded per job (plan(): the same job gives the same rolls), never during a gust / quake (one tell at a time),
## and check() proves every lane is fair (tests/tower_stack_rollers_test.gd, every seed, level, mode, season and
## 400+ days of TODAY'S TOWER).
##   Rollers.plan(seed, level, mode, events, eager) -> [[t, ax, az, bx, bz, speed], ...]   Rollers.check(...) -> problems
##   host: node.reset(rolls); node.due(job_t) -> rolls whose tell starts now      every machine: node.start(roll, season)
##   node.balls() -> [{pos, live}] (hit tests on the machine where a player is local)

const G := preload("res://games/tower_stack/towergen.gd")
const Seeded := preload("res://core/seeded.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Contrast := preload("res://core/contrast.gd")

const R := 0.55  # the ball's radius (a jump clears it: main.gd JUMP peaks ~1.4 m)
const WARN := 3.0  # the lane glows this long before the ball rolls
const MIN_WARN := 2.5  # check(): never less
const EDGE := 8.6  # lanes start and end on this circle (inside the walk edge, main.gd ARENA 9)
const STAGE_CLEAR := G.BASE_R + 1.1  # a lane's middle line stays this far from the stage's centre
const PAD := Vector2(1.7, 1.5)  # == main.gd PAD (x, z)
const PAD_CLEAR := 0.9 + R + 0.45  # ... and this far from the pad's centre (PAD_R + ball + room)
const GREEN := Vector2(-6.0, -4.4)  # == green.gd CENTER (x, z): Wren's neighbours live there (the test checks)
const GREEN_CLEAR := 2.1 + R + 0.2  # green.gd RADIUS + the ball + room
const LANE_W := 2.0 * R + 0.5  # the told lane's width (the ball plus a little)
const FIRST := 10.0  # no roll before this many seconds into a job
const EAGER_FIRST := 6.0  # TS_TRY=rollers / bots: the first roll this early in every job
const GAP := 14.0  # at least this between two rolls' tells
const WEATHER_ROOM := 1.5  # seconds kept clear around a gust / quake (its tell + itself)
const SPEED := {"gentle": 2.6, "brave": 3.8, "hard": 4.8}  # m/s
const MAX_SPEED := 5.0
## Rolls per job by level (brave), shifted by mode: gentle only from level 3 (one slow ball), hard one more from level 2.
const ROLLS_AT: Array[int] = [0, 1, 1, 1, 2, 2]
const MAX_ROLLS := 3
const COLOR := Color(1.0, 0.35, 0.75)  # the lane: pink (not the gust's blue or the quake's orange)
## The ball by season: [picture, body colour, stripe colour].
const BALLS := {
	"spring": ["rainbowball", Color(0.55, 0.45, 1.0), Color(1.0, 0.85, 0.25)],
	"summer": ["beachball", Color(1.0, 0.3, 0.3), Color(0.25, 0.55, 1.0)],
	"autumn": ["pumpkin", Color(1.0, 0.55, 0.1), Color(0.85, 0.4, 0.05)],
	"winter": ["bigsnowball", Color(0.97, 0.98, 1.0), Color(0.75, 0.85, 1.0)],
}
const NAMES := {"spring": "Rolling ball!", "summer": "Beach ball!", "autumn": "Rolling pumpkin!", "winter": "Snowball!"}

var rings: WarnRings
var rolls: Array = []  # host: this job's plan
var told := {}  # host: roll index -> true
var fired := 0  # host: rolls told this job
var _live: Array[Dictionary] = []  # every machine: {node, a, b, speed, t, warn, secs}


func _ready() -> void:
	name = "Rollers"
	rings = WarnRings.new()
	add_child(rings)


## The rolls of one job (seeded; events: the job's weather [t, kind, strength] to keep clear of).
static func plan(seed_value: int, lv: int, mode: String, events: Array = [], eager: bool = false) -> Array:
	var r := Seeded.rng(seed_value, "rolo")
	var n := count(lv, mode)
	if eager:
		n = maxi(n, 1)
	var speed := float(SPEED.get(mode, SPEED["brave"]))
	var out: Array = []
	var at := (EAGER_FIRST if eager else FIRST) + r.randf_range(0.0, 4.0)
	var tries := 0
	while out.size() < n and tries < 40:
		tries += 1
		at = ceilf(at * 10.0 - 0.001) / 10.0  # (kept as it is sent: a rounded time never slips back into a gust)
		var lane := _lane(r)
		if lane.is_empty():
			continue
		var secs := Vector2(lane[2] - lane[0], lane[3] - lane[1]).length() / speed
		var clash := _weather_clash(at, secs, events)
		if clash > 0.0:
			at = clash
			continue
		if at + secs > G.JOB_MAX - 5.0:
			break
		out.append([at, lane[0], lane[1], lane[2], lane[3], speed])
		at += GAP + secs + r.randf_range(0.0, 10.0)
	return out


static func count(lv: int, mode: String) -> int:
	var n: int = ROLLS_AT[clampi(lv, 1, ROLLS_AT.size()) - 1]
	match mode:
		"gentle":
			n = 1 if lv >= 3 else 0
		"hard":
			n += 1 if lv >= 2 else 0
	return mini(n, MAX_ROLLS)


## A lane across the park: [ax, az, bx, bz] on the EDGE circle, clear of the stage and the pad ([] if none fits).
static func _lane(r: RandomNumberGenerator) -> Array:
	for k in 12:
		var phi := r.randf() * TAU
		var d := r.randf_range(STAGE_CLEAR + 0.3, 6.5)
		var nrm := Vector2(cos(phi), sin(phi))
		var tan := Vector2(-nrm.y, nrm.x) * sqrt(EDGE * EDGE - d * d)
		var a := nrm * d - tan
		var b := nrm * d + tan
		if r.randf() < 0.5:
			var sw := a
			a = b
			b = sw
		if _seg_dist(a, b, PAD) < PAD_CLEAR or _seg_dist(a, b, GREEN) < GREEN_CLEAR:
			continue
		return [snappedf(a.x, 0.01), snappedf(a.y, 0.01), snappedf(b.x, 0.01), snappedf(b.y, 0.01)]
	return []


## The time a roll starting its tell at `at` (lasting WARN + secs) must move to so it misses every weather event
## (0: no clash).
static func _weather_clash(at: float, secs: float, events: Array) -> float:
	for e in events:
		var e0 := float(e[0]) - G.WARN_SECS - WEATHER_ROOM
		var e1 := float(e[0]) + G.EVENT_SECS + WEATHER_ROOM
		if at < e1 and at + WARN + secs > e0:
			return e1
	return 0.0


static func _seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var k := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * k).distance_to(p)


## The validator: every problem with one job's rolls (empty = fair).
static func check(rolls: Array, events: Array, lv: int, mode: String, eager: bool = false) -> Array:
	var out: Array = []
	var want := count(lv, mode)
	if rolls.size() > maxi(want, 1 if eager else 0):
		out.append("%d rolls, at most %d at level %d %s" % [rolls.size(), want, lv, mode])
	if mode == "gentle" and lv < 3 and not eager and not rolls.is_empty():
		out.append("gentle level %d has rolls" % lv)
	var prev_end := -INF
	for ro in rolls:
		var t := float(ro[0])
		var a := Vector2(float(ro[1]), float(ro[2]))
		var b := Vector2(float(ro[3]), float(ro[4]))
		var sp := float(ro[5])
		var secs := a.distance_to(b) / maxf(sp, 0.01)
		if a.length() > EDGE + 0.02 or b.length() > EDGE + 0.02:
			out.append("lane leaves the park %s" % str(ro))
		if a.distance_to(b) < 6.0:
			out.append("lane too short to see %s" % str(ro))
		if _seg_dist(a, b, Vector2.ZERO) < STAGE_CLEAR:
			out.append("lane crosses the tower stage %s" % str(ro))
		if _seg_dist(a, b, PAD) < PAD_CLEAR:
			out.append("lane crosses the pad %s" % str(ro))
		if _seg_dist(a, b, GREEN) < GREEN_CLEAR:
			out.append("lane crosses the village green %s" % str(ro))
		if sp > MAX_SPEED or sp <= 0.0:
			out.append("ball too fast %s" % str(ro))
		if WARN < MIN_WARN:
			out.append("tell too short")
		if t < (EAGER_FIRST if eager else FIRST) - 0.01:
			out.append("roll too early in the job %s" % str(ro))
		if t + WARN + secs > G.JOB_MAX:
			out.append("roll after the job's time %s" % str(ro))
		if t < prev_end + GAP - WARN - 0.01:
			out.append("rolls too close together %s" % str(ro))
		prev_end = t + WARN + secs
		if _weather_clash(t, secs, events) > 0.0:
			out.append("roll during a gust / quake %s" % str(ro))
		# Anyone in the lane can step out in time: half the lane plus a body at a walk (main.gd SPEED 4.5).
		if (LANE_W * 0.5 + 0.3) / 4.5 > WARN * 0.5:
			out.append("no time to step out")
	return out


# --- every machine ----------------------------------------------------------------------

func reset(new_rolls: Array) -> void:
	rolls = new_rolls.duplicate(true)
	told = {}


## Host: rolls whose tell starts now (job_t passed their time).
func due(job_t: float) -> Array:
	var out: Array = []
	for i in rolls.size():
		if not told.has(i) and job_t >= float(rolls[i][0]):
			told[i] = true
			fired += 1
			out.append(rolls[i])
	return out


## Every machine: tell a roll, then roll its ball. roll: [t, ax, az, bx, bz, speed].
func start(ro: Array, season: String) -> void:
	var a := Vector3(float(ro[1]), 0.0, float(ro[2]))
	var b := Vector3(float(ro[3]), 0.0, float(ro[4]))
	var sp := float(ro[5])
	var secs := a.distance_to(b) / maxf(sp, 0.01)
	rings.shape("line", a, b - a, Vector2(a.distance_to(b), LANE_W), COLOR, WARN, {"style": "disc", "stay": secs + 0.3, "y": 0.06})
	var ball := MeshKit.instance(ball_mesh(season))
	Contrast.outline(ball, Contrast.OUTLINE, 0.04)
	ball.position = a + Vector3(0.0, R, 0.0)
	add_child(ball)
	_live.append({"node": ball, "a": a, "b": b, "secs": secs, "t": 0.0, "warn": WARN})


## The balls rolling now: [{pos (centre), dir (flat, unit), told (seconds its lane showed before it rolled)}].
func balls() -> Array:
	var out: Array = []
	for l in _live:
		if float(l.t) >= float(l.warn) and is_instance_valid(l.node):
			out.append({"pos": (l.node as Node3D).position, "dir": ((l.b - l.a) as Vector3).normalized(), "told": float(l.warn)})
	return out


func waiting() -> int:
	return _live.size()


func clear() -> void:
	rings.clear()
	for l in _live:
		if is_instance_valid(l.node):
			(l.node as Node).queue_free()
	_live.clear()


func _process(delta: float) -> void:
	var i := 0
	while i < _live.size():
		var l: Dictionary = _live[i]
		l.t = float(l.t) + delta
		var n: Node3D = l.node
		if not is_instance_valid(n):
			_live.remove_at(i)
			continue
		var t := float(l.t) - float(l.warn)
		var dir: Vector3 = ((l.b - l.a) as Vector3).normalized()
		if t < 0.0:  # waiting at the edge: wiggles to show where it comes from
			n.rotation = Vector3(0.0, 0.0, sin(float(l.t) * 14.0) * 0.15)
		elif t <= float(l.secs):
			var k := t / float(l.secs)
			n.position = (l.a as Vector3).lerp(l.b, k) + Vector3(0.0, R, 0.0)
			var axis := Vector3.UP.cross(dir).normalized()
			n.basis = Basis(axis, t * float((l.a as Vector3).distance_to(l.b)) / float(l.secs) / R)
		else:  # off the edge: shrinks away
			n.scale = Vector3.ONE * maxf(0.01, 1.0 - (t - float(l.secs)) * 3.0)
			if t > float(l.secs) + 0.35:
				n.queue_free()
				_live.remove_at(i)
				continue
		i += 1


## The ball: a sphere in the season's colours with stripes (a pumpkin gets ribs and a stalk; a snowball a few lumps).
static func ball_mesh(season: String) -> Mesh:
	return ResCache.get_or_make("tower_stack_roller_v1_" + season, func() -> Resource:
		var d: Array = BALLS.get(season, BALLS["summer"])
		var b := MeshKit.Builder.new()
		b.sphere(R, Transform3D(), d[1], 16)
		match season:
			"autumn":
				for k in 6:
					b.ellipsoid(Vector3(R * 0.35, R * 0.98, R * 0.35), Transform3D(Basis(Vector3.UP, k * PI / 6.0), Vector3(0, 0, R * 0.68)), d[2], 10)
				b.cylinder(0.05, 0.07, 0.18, MeshKit.at(Vector3(0, R + 0.06, 0)), Color(0.3, 0.5, 0.15), 6)
			"winter":
				for k in 5:
					var p := Vector3(cos(k * 1.3), sin(k * 2.1) * 0.6, sin(k * 1.3)).normalized() * R * 0.85
					b.sphere(R * 0.3, MeshKit.at(p), d[2], 8)
			_:
				for k in 3:
					b.torus(R * 0.995, 0.06, Transform3D(Basis(Vector3.UP, k * PI / 3.0) * Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), d[2] if k != 1 else Color(1, 1, 1), 20, 4)
		return b.build())
