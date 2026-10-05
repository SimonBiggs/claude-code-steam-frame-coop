extends Node3D
## A golf ball. The host (or local game) rolls it with a tiny deterministic 2D roller on the
## course's XZ plane: rolling friction, slopes, bounces off rails and bumpers, a gentle pull into
## the cup when it is slow and close, and the scripted loop-the-loop. The TV machine only draws it,
## gliding to the host's positions. The look (player-coloured ball with a white band) rolls with it.

const Course := preload("res://games/mini_golf_party/course.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const ROLL_DECEL := 0.9
const DRAG := 0.22
const WALL_BOUNCE := 0.7
const BUMPER_BOUNCE := 1.15
const STOP_SPEED := 0.06
const CAPTURE_SPEED := 1.6
const ASSIST_R := 0.3
const ASSIST := 0.9
const LOOP_MIN := 2.2
const MAX_SPEED := 4.4
const MAX_ROLL := 14.0

var slot := 0
var color := Color.WHITE
var course: Course
## "rest", "roll", "loop", "cup"
var state := "rest"
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var last_rest := Vector2.ZERO
var strokes := 0
var roll_t := 0.0
var loop_a := 0.0
var loop_v := 0.0
var loop_x := 0.0
var sink_t := 0.0
## Things that happened this tick (for sounds): ["wall", strength], ["bump"], ["loop"], ["cup"], ["back"]
var events: Array = []

var visual: Node3D
var spin: MeshInstance3D
var target := Vector3.ZERO  # TV machine: where the host says it is
var _last_vis := Vector3.ZERO


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	var b := MeshKit.Builder.new()
	b.sphere(Course.BALL_R, MeshKit.at(Vector3.ZERO), color.lightened(0.15), 14)
	b.torus(Course.BALL_R * 0.98, 0.012, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.0, 0.0, PI * 0.5)), Color.WHITE, 14, 4)
	spin = MeshKit.instance(b.build())
	visual.add_child(spin)
	var shadow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	shadow.position.y = -Course.BALL_R + 0.004
	shadow.material_override = MeshKit.material(Color(0.0, 0.0, 0.0, 0.3))
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.name = "Shadow"
	visual.add_child(shadow)


func place(p: Vector2) -> void:
	pos = p
	vel = Vector2.ZERO
	last_rest = p
	state = "rest"
	roll_t = 0.0
	if course != null:
		position = course.world(p)
		target = position
		_last_vis = position


func putt(v: Vector2) -> void:
	if state != "rest":
		return
	last_rest = pos
	vel = v.limit_length(MAX_SPEED)
	state = "roll"
	roll_t = 0.0
	strokes += 1


func resting() -> bool:
	return state == "rest"


# --- Simulation (host / local) ------------------------------------------------------------

func step(dt: float) -> void:
	if state == "loop":
		_loop_step(dt)
		return
	if state == "cup":
		sink_t += dt
		position = course.world(course.cup, -minf(sink_t, 0.12))
		visual.visible = sink_t < 0.4
		return
	if state != "roll":
		position = course.world(pos)
		return
	roll_t += dt
	var n := 4
	var h := dt / n
	for _k in n:
		var g := course.grad(pos)
		vel -= g * 9.8 * (5.0 / 7.0) * h
		var sp := vel.length()
		if sp > 0.0:
			vel = vel / sp * maxf(0.0, sp - (ROLL_DECEL + DRAG * sp) * h)
			sp = vel.length()
		var to_cup := course.cup - pos
		var dc := to_cup.length()
		if dc < ASSIST_R and sp < 1.0 and dc > 0.001:
			vel += to_cup / dc * ASSIST * h
		var prev := pos
		pos += vel * h
		if course.gimmick == "loop" and prev.y > course.loop_z and pos.y <= course.loop_z and absf(pos.x) < Course.LOOP_GAP:
			if vel.length() >= LOOP_MIN:
				state = "loop"
				loop_a = 0.0
				loop_v = vel.length()
				loop_x = pos.x
				events.append(["loop"])
				return
			pos.y = course.loop_z + 0.01
			vel = -vel * 0.45
			events.append(["back"])
		_collide()
		if dc < Course.CUP_R - 0.015 and vel.length() < CAPTURE_SPEED:
			state = "cup"
			sink_t = 0.0
			vel = Vector2.ZERO
			events.append(["cup"])
			return
	if not course.inside(pos):  # escaped somehow: back to where it was putted from
		place(last_rest)
		events.append(["reset"])
		return
	var still := vel.length() < STOP_SPEED and course.grad(pos).length() < 0.05
	if still or roll_t > MAX_ROLL:
		vel = Vector2.ZERO
		state = "rest"
		last_rest = pos
	position = course.world(pos)


func _collide() -> void:
	var r := Course.BALL_R
	for w in course.active_walls():
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var q := Geometry2D.get_closest_point_to_segment(pos, a, b)
		var d := pos - q
		var dist := d.length()
		if dist < r and dist > 0.00001:
			var nrm := d / dist
			pos = q + nrm * r
			var vn := vel.dot(nrm)
			if vn < 0.0:
				vel -= (1.0 + WALL_BOUNCE) * vn * nrm
				if -vn > 0.25:
					events.append(["wall", -vn])
	for bm in course.bumpers:
		var c: Vector2 = bm[0]
		var rr: float = bm[1] + r
		var d := pos - c
		if d.length() < rr and d.length() > 0.00001:
			var nrm := d.normalized()
			pos = c + nrm * rr
			var vn := vel.dot(nrm)
			if vn < 0.0:
				vel -= (1.0 + BUMPER_BOUNCE) * vn * nrm
				vel = vel.limit_length(MAX_SPEED)
				events.append(["bump"])


func _loop_step(dt: float) -> void:
	# Round the hoop, a little slower at the top, then out the other side.
	var hgt := (1.0 - cos(loop_a)) * Course.LOOP_R
	var sp := maxf(1.2, sqrt(maxf(0.0, loop_v * loop_v - 2.0 * 9.8 * (5.0 / 7.0) * hgt)))
	loop_a += sp / Course.LOOP_R * dt
	if loop_a >= TAU:
		state = "roll"
		var exit_x := loop_x + 0.06
		pos = Vector2(exit_x, course.loop_z - 0.03)
		vel = Vector2(0.0, -loop_v * 0.8)
		position = course.world(pos)
		return
	position = course.loop_ball(loop_a, loop_x)


## Two balls touching: push apart and share the push (gentle knocks).
static func knock(a, b) -> bool:
	var d: Vector2 = b.pos - a.pos
	var dist := d.length()
	var r2 := Course.BALL_R * 2.0
	if dist >= r2 or dist < 0.00001:
		return false
	var nrm := d / dist
	var push := (r2 - dist) * 0.5
	a.pos -= nrm * push
	b.pos += nrm * push
	var rel: float = (a.vel - b.vel).dot(nrm)
	if rel > 0.0:
		var j := rel * 0.9
		a.vel -= nrm * j
		b.vel += nrm * j
		for o in [a, b]:
			if o.state == "rest" and o.vel.length() > STOP_SPEED:
				o.state = "roll"
				o.roll_t = 0.0
	return rel > 0.15


# --- Look (every machine) -----------------------------------------------------------------

func _process(delta: float) -> void:
	if course == null:
		return
	if slot >= 0 and get_meta("mirror", false):
		if position.distance_to(target) > 1.0:
			position = target
		else:
			position = position.lerp(target, 1.0 - exp(-18.0 * delta))
		visual.visible = position.y > -0.05
	var mv := position - _last_vis
	mv.y = 0.0
	var dist := mv.length()
	if dist > 0.0001 and dist < 0.5:
		var axis := Vector3(mv.z, 0.0, -mv.x).normalized()
		spin.rotate(axis, dist / Course.BALL_R)
	_last_vis = position
