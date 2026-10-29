extends RefCounted
## OBSTACLE RUSH: a CPU runner's brain (also drives the test bots' pads).
## Follows course.route: run to each point with a little personal lane offset; "jump" points are
## gap edges (jump when close), "spin" points hop when the spinner bar sweeps near, "door" points
## pick a door and line up in front of it (a pretend one bonks you back: main / the bot call
## bonked_door() with the door that did it, so the next try picks another), "pad" points are
## bounce pads (just keep running forward in the air).
## Output each tick: out_move (world direction, length <= 1) and out_jump (a press).

var rng := RandomNumberGenerator.new()
var lane := 0.0
var wp := 0
var out_move := Vector3.ZERO
var out_jump := false
var door_z := {}  ## wall x (int) -> chosen door z
var tried := {}  ## "x:z" -> true for doors that bonked us
var _jump_cool := 0.0
var _best_x := -INF
var _stuck := 0.0


func reset(seed_value: int) -> void:
	rng.seed = seed_value
	lane = rng.randf_range(-0.7, 0.7)
	wp = 0
	door_z.clear()
	tried.clear()
	_best_x = -INF
	_stuck = 0.0


## The runner bumped a pretend door: try another one next time.
func bonked_door(x: float, z: float) -> void:
	tried["%d:%d" % [roundi(x), roundi(z)]] = true
	door_z.erase(roundi(x))


func think(r: Node3D, course: Node, delta: float) -> void:
	out_jump = false
	_jump_cool -= delta
	var p := r.position
	var route: Array = course.route
	if route.is_empty():
		out_move = Vector3.ZERO
		return
	wp = route_index(route, p)
	var goal: Vector3 = route[wp][0]
	var what: String = route[wp][1]
	var off := lane * (float(course.half_w) - 0.8)
	var lining_up := false
	if what == "door":
		goal.z = _door_for(goal.x - 0.6, course)
		if p.x < goal.x - 1.2 and absf(p.z - goal.z) > 0.3:
			goal.x -= 2.0  # line up in front of the door first (cutting across would bump a neighbour)
			lining_up = true
	elif what == "spin":
		goal.z = goal.z * signf(lane + 0.01)
	else:
		goal.z = off * 0.6 if what == "" else goal.z + off * 0.2
	var to := goal - p
	to.y = 0.0
	if to.length() < 0.6 and not lining_up:  # there: carry on along the course (a door or spinner point too, or we'd dither there)
		to = Vector3(1.0, 0.0, 0.0)
	out_move = to.normalized() if to.length() > 0.05 else Vector3.ZERO
	if what == "pad" and p.y > goal.y + 0.8:
		out_move = Vector3(1.0, 0.0, -p.z * 0.2).normalized()  # flying: keep heading on
	if what == "jump" and to.length() < 0.9 and _jump_cool <= 0.0:
		_jump()
	if what == "spin" and course.spinner != null and _jump_cool <= 0.0:
		# Hop just before the bar sweeps past (it has two arms, so look half a turn ahead).
		var sv: float = course.spin_vel
		if absf(sv) > 0.2:
			var sc: Vector3 = course.spin_c
			var mine := atan2(-(p.z - sc.z), p.x - sc.x)
			var ahead := fposmod((mine - float(course.spin_angle)) * signf(sv), PI)
			var eta := ahead / absf(sv)
			if eta > 0.08 and eta < 0.3 and rng.randf() < 0.85:
				_jump()
	# Stuck against something? Hop.
	if p.x > _best_x + 0.3:
		_best_x = p.x
		_stuck = 0.0
	else:
		_stuck += delta
		if _stuck > 1.5 and _jump_cool <= 0.0:
			_jump()
			lane = rng.randf_range(-0.7, 0.7)
			_stuck = 0.0
			_best_x = p.x


## Which route point a runner at p is heading for: the first one not passed yet. Passing is by x only
## (after a pop-back we head back to the right point; after a big drop the points up top count as
## passed), except a bounce pad, which only counts once it threw us up (or we're past its step).
## (coursegen.gd's simulated bean uses this too.)
static func route_index(route: Array, p: Vector3) -> int:
	var wp := 0
	for k in route.size():
		var pt: Vector3 = route[k][0]
		if p.x > pt.x + 0.4 and (String(route[k][1]) != "pad" or p.y > pt.y + 2.0 or p.x > pt.x + 2.5):
			wp = k + 1
	return mini(wp, route.size() - 1)


func _jump() -> void:
	out_jump = true
	_jump_cool = 0.5


func _door_for(x: float, course: Node) -> float:
	var key := roundi(x)
	if door_z.has(key):
		return float(door_z[key])
	var options: Array[float] = []
	for d in course.doors:
		if absf(float(d["x"]) - x) < 0.5 and not tried.has("%d:%d" % [roundi(float(d["x"])), roundi(float(d["z"]))]):
			options.append(float(d["z"]))
	if options.is_empty():  # (every door tried? the giant may have shuffled things: start again)
		for d in course.doors:
			if absf(float(d["x"]) - x) < 0.5:
				tried.erase("%d:%d" % [roundi(float(d["x"])), roundi(float(d["z"]))])
				options.append(float(d["z"]))
	var z := 0.0 if options.is_empty() else options[rng.randi() % options.size()]
	door_z[key] = z
	return z
