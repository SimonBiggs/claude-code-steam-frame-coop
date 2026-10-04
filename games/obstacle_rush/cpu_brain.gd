extends RefCounted
## OBSTACLE RUSH: a CPU runner's brain (also drives the test bots' virtual pads).
## Follows the course route (with a personal lane offset), jumps gaps, steps and low bars, waits for
## hammers, hops ledges, gets unstuck, and lets arena courses pick targets (course.cpu_target()).
## Output each tick: out_move (world direction, length <= 1), out_jump (held), out_jump_pressed,
## out_dive.

const RunnerScript := preload("res://games/obstacle_rush/runner.gd")

var rng := RandomNumberGenerator.new()
var skill := 0.8  ## 0..1: how often it reads hazards right (CPU runners tumble a bit, bots don't)
var lane := 0.0  ## -1..1: where in the lane it likes to run
var wp := 1
var pts: Array[Vector3] = []
var widths: Array[float] = []
var jumps: Array[bool] = []
var memo := {}  ## per-course scratch (doors tried, target tile, chase target...)
var target := Vector3.ZERO
var out_move := Vector3.ZERO
var out_jump := false
var out_jump_pressed := false
var out_dive := false
var stuck_long := false
var _jump_hold := 0.0
var _jump_cool := 0.0
var _best := -INF
var _stuck_t := 0.0
var _wait_t := 0.0
var _wander_t := 0.0
var _side_kick := 0.0


func reset(course: Node, seed_v: int, route_pick: int = -1) -> void:
	rng.seed = seed_v
	lane = rng.randf_range(-0.8, 0.8)
	memo.clear()
	_best = -INF
	_stuck_t = 0.0
	_wait_t = 0.0
	stuck_long = false
	pts.clear()
	widths.clear()
	jumps.clear()
	var alts: Array = course.get("alt_routes")
	var pick := route_pick
	if pick < 0:
		pick = rng.randi_range(0, alts.size()) if not alts.is_empty() else 0
	if pick > 0 and pick <= alts.size():
		var alt: Array = alts[pick - 1]
		for p in alt[0]:
			pts.append(p)
		for w in alt[1]:
			widths.append(float(w))
		for j in alt[2]:
			jumps.append(bool(j))
	else:
		var r: Array[Vector3] = course.get("route")
		pts.append_array(r)
		var rw: Array[float] = course.get("route_w")
		widths.append_array(rw)
		var rj: Array[bool] = course.get("route_jump")
		jumps.append_array(rj)
	wp = 1 if pts.size() > 1 else 0


## After a respawn / teleport: continue from the route point nearest to `pos`.
func resync(pos: Vector3) -> void:
	if pts.size() < 2:
		return
	var best := INF
	var bi := 0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * t).distance_to(pos)
		if d < best:
			best = d
			bi = i
	wp = clampi(bi + 1, 1, pts.size() - 1)
	_best = -INF
	_stuck_t = 0.0


## One decision (call every physics tick).
func think(r: Node3D, course: Node, delta: float) -> void:
	out_jump_pressed = false
	out_dive = false
	_jump_hold = maxf(0.0, _jump_hold - delta)
	_jump_cool = maxf(0.0, _jump_cool - delta)
	out_jump = _jump_hold > 0.0
	var st: int = r.get("state")
	if st == RunnerScript.S_TUMBLE or st == RunnerScript.S_HIDDEN or st == RunnerScript.S_RESPAWN:
		out_move = Vector3.ZERO
		return
	var pos := r.global_position
	var tgt: Vector3 = course.cpu_target(r, self)
	var arena := tgt != Vector3.INF
	if not arena:
		tgt = _follow_route(pos, course)
	target = tgt
	var to := tgt - pos
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.25 else Vector3.ZERO
	var move := dir
	var on_floor: bool = (r as CharacterBody3D).is_on_floor()
	var spd := RunnerScript.RUN_SPEED
	# hazards ahead (hammers, sweepers)
	var danger_ahead := 0
	for t in [0.18, 0.32, 0.46]:
		var tt: float = t
		var th: int = course.threat(pos + dir * spd * tt * 0.8, tt)
		danger_ahead = maxi(danger_ahead, th)
		if th == 1 and on_floor and _jump_cool <= 0.0 and rng.randf() < 0.35 + skill * 0.65:
			_jump()
			break
	if danger_ahead == 2:
		var here_safe := true
		for t2 in [0.2, 0.45, 0.7]:
			if course.threat(pos, float(t2)) == 2:
				here_safe = false
		if here_safe and rng.randf() < 0.2 + skill * 0.8:
			move = Vector3.ZERO  # wait for it to swing past
			_wait_t += delta
			if _wait_t > 4.0:
				move = dir  # waited long enough: go for it
		else:
			_wait_t = 0.0
	else:
		_wait_t = 0.0
	if on_floor and move != Vector3.ZERO and _jump_cool <= 0.0:
		# a gap ahead, a step or a ledge, or a route jump point
		if _gap_ahead(r, dir) or _step_ahead(r, dir) or _route_jump_due(pos):
			_jump()
	# unstuck
	var prog: float = course.progress(pos) if not arena else float(Time.get_ticks_msec()) * 0.0
	if not arena:
		if prog > _best + 0.6:
			_best = prog
			_stuck_t = 0.0
		else:
			_stuck_t += delta
		if _stuck_t > 2.6 and on_floor and _jump_cool <= 0.0:
			_jump()
			lane = rng.randf_range(-1.0, 1.0)
			_side_kick = 0.8
		stuck_long = _stuck_t > 9.0
	if _side_kick > 0.0:
		_side_kick -= delta
		move = (move + Vector3(-dir.z, 0.0, dir.x) * signf(lane)).normalized()
	out_move = move


func _jump() -> void:
	out_jump_pressed = true
	_jump_hold = 0.4
	out_jump = true
	_jump_cool = 0.55


func _follow_route(pos: Vector3, course: Node) -> Vector3:
	if pts.is_empty():
		return pos
	while wp < pts.size() - 1:
		var p: Vector3 = course.route_point(wp, pts[wp], self)
		var flat := Vector2(p.x - pos.x, p.z - pos.z)
		var nxt := pts[wp + 1]
		var seg := Vector2(nxt.x - pts[wp].x, nxt.z - pts[wp].z).normalized()
		var passed := Vector2(pos.x - p.x, pos.z - p.z).dot(seg) > 0.0 and flat.length() < widths[wp] + 1.8
		var near := flat.length() < 1.1
		if absf(pos.y - p.y) > 2.6:
			passed = false
			near = false
		if near or passed:
			wp += 1
		else:
			break
	var cur: Vector3 = course.route_point(wp, pts[wp], self)
	var prev: Vector3 = pts[maxi(0, wp - 1)]
	var d := cur - prev
	d.y = 0.0
	if d.length() < 0.01:
		return cur
	d = d.normalized()
	var side := Vector3(-d.z, 0.0, d.x)
	return cur + side * lane * widths[wp]


func _route_jump_due(pos: Vector3) -> bool:
	if wp >= jumps.size() or not jumps[wp]:
		return false
	var p := pts[wp]
	return Vector2(p.x - pos.x, p.z - pos.z).length() < 1.5


## No floor a little way ahead (and something to land on further on)?
func _gap_ahead(r: Node3D, dir: Vector3) -> bool:
	if dir == Vector3.ZERO:
		return false
	var space := r.get_world_3d().direct_space_state
	var pos := r.global_position
	var probe := pos + dir * 1.0 + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * 2.4, 1)
	q.exclude = [(r as CollisionObject3D).get_rid()]
	if not space.intersect_ray(q).is_empty():
		return false
	return true


## A low wall / step ahead that a jump (or a ledge grab) gets over?
func _step_ahead(r: Node3D, dir: Vector3) -> bool:
	if dir == Vector3.ZERO:
		return false
	var space := r.get_world_3d().direct_space_state
	var pos := r.global_position + Vector3.UP * 0.35
	var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * 0.95, 1)
	q.exclude = [(r as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.5:
		return false
	var col: Object = hit["collider"]
	if col is StaticBody3D and String((col as Node).get_meta("kind", "")) in ["fake_door", "door", "bumper"]:
		return false
	# how high is it?
	var hp: Vector3 = hit["position"]
	var top_from := Vector3(hp.x, r.global_position.y + 2.4, hp.z) + dir * 0.25
	var q2 := PhysicsRayQueryParameters3D.create(top_from, top_from + Vector3.DOWN * 2.4, 1)
	var hit2 := space.intersect_ray(q2)
	if hit2.is_empty():
		return false
	var top: Vector3 = hit2["position"]
	var rise := top.y - r.global_position.y
	return rise > 0.2 and rise < 2.2
