extends RefCounted
## MINI GOLF PARTY hole generator: Gus the gopher's garden course. A course is HOLES holes from one
## course seed (TODAY'S COURSE: the daily seed, the same on every machine all day). Hole 1 is always a
## short straight practice putt; holes 2-5 each get one gimmick (bumper, windmill, hill, loop, and from
## level 2 the pinball garden), shuffled per course, on a fairway shaped by the seed: straight, an L, or a
## dogleg (two bends), corridor walls from a centre line of right-angle turns.
## The level (1..MAX_LEVEL) grows with the family's play-days: level 2 brings doglegs and the pinball
## hole, level 3 bumpers in the bends of the gimmick holes, level 4 taller hills.
## Everything is plain data (a Dictionary course.gd builds), so the host only sends
## [course seed, hole, level, try] and every machine rebuilds the same hole without re-checking.
##   var d := HoleGen.hole(seed, i, level)        # checked: the first try that passes check()
##   HoleGen.check(d)  -> [] or reasons           # geometry: fits, the toys and board are off it, the aim path is clear
##   HoleGen.sim(d)    -> {"sunk", "putts"}       # proof: an aiming putter (the bots' speed rule) sinks it
## tests/mini_golf_party_gen_test.gd runs both over many seeds and levels.

const Seeded := preload("res://core/seeded.gd")
const Course := preload("res://games/mini_golf_party/course.gd")
const Ball := preload("res://games/mini_golf_party/ball.gd")
const Props := preload("res://games/mini_golf_party/props.gd")

const GAME_ID := "mini_golf_party"
const HOLES := Course.HOLES
const MAX_LEVEL := 4
const MAX_PUTTS := 6  ## after this many putts the ball hops in by itself (main.MAX_STROKES)
const BASE_GIMMICKS: Array[String] = ["bumper", "windmill", "hill", "loop"]
const MAX_SIZE := Vector2(4.2, 6.4)  ## metres: the whole hole fits the TV camera and the lawn's flower ring
const TEE_IN := 0.45
const BOARD_BACK := 0.9  ## the flag board stands this far beyond the cup (main.gd)
const GUS_SIDE := 1.1  ## Gus's molehill: beside the board
const TRIES := 16


## The course level for this many play-days.
static func level_for(days: int) -> int:
	return clampi(days, 1, MAX_LEVEL)


## TODAY'S COURSE: the same seed on every machine all day.
static func daily_seed(date: String = "") -> int:
	return maxi(1, Seeded.daily_seed(GAME_ID, date))


static func hole_seed(course_seed: int, i: int) -> int:
	return Seeded.derive(course_seed, "hole%d" % i)


## The gimmick of each hole of a course ("" = the practice putt).
static func plan(course_seed: int, level: int) -> Array:
	var pool: Array = BASE_GIMMICKS.duplicate()
	if level >= 2:
		pool.append("pinball")
	var out: Array = [""]
	out.append_array(Seeded.shuffled(Seeded.rng(course_seed, "plan"), pool).slice(0, HOLES - 1))
	return out


## Hole i of a course: the first try that passes check() and that sim() sinks (the classic hole of that gimmick if
## none does; the test proves the classic ones too). A few ms on the host; TV machines rebuild with hole_try().
static func hole(course_seed: int, i: int, level: int) -> Dictionary:
	for t in TRIES:
		var d := hole_try(course_seed, i, level, t)
		if check(d).is_empty() and proven(d):
			return d
	return hole_try(course_seed, i, level, -1)


## One try (t = -1: the classic fallback). TV machines rebuild the host's hole with this, no checking.
static func hole_try(course_seed: int, i: int, level: int, t: int) -> Dictionary:
	i = clampi(i, 0, HOLES - 1)
	level = clampi(level, 1, MAX_LEVEL)
	var g: String = plan(course_seed, level)[i]
	var s := hole_seed(course_seed, i)
	var d := _make(Seeded.derive(s, t) if t > 0 else s, i, level, g, t < 0)
	d["course_seed"] = course_seed
	d["index"] = i
	d["level"] = level
	d["try"] = t
	return d


static func _make(seed_value: int, i: int, level: int, g: String, classic: bool) -> Dictionary:
	var r := Seeded.rng(seed_value, "hole")
	if classic:
		r = Seeded.rng(1, "classic")
	var side := -1.0 if r.randf() < 0.5 else 1.0
	var hw := r.randf_range(0.5, 0.6)
	var pts: Array[Vector2] = [Vector2.ZERO]  # the centre line, from the tee's end wall (+Z) towards the cup (-Z)
	var shape := "straight"
	var bend_p := 0.0 if classic else (0.3 + 0.15 * (level - 1) + (0.2 if i >= 3 else 0.0))
	match g:
		"":
			hw = 0.5
			pts.append(Vector2(0.0, -r.randf_range(3.0, 3.6)))
		"bumper":
			if level >= 2 and r.randf() < bend_p:
				shape = "dogleg"
				var a := r.randf_range(2.2, 2.6)
				var b := r.randf_range(1.3, 2.0)
				pts.append(Vector2(0.0, -a))
				pts.append(Vector2(side * b, -a))
				pts.append(Vector2(side * b, -a - r.randf_range(1.8, 2.4)))
			else:
				shape = "L"
				var a := r.randf_range(2.3, 3.2)
				pts.append(Vector2(0.0, -a))
				pts.append(Vector2(side * r.randf_range(1.8, 2.4), -a))
		"pinball":
			hw = r.randf_range(0.66, 0.7)
			pts.append(Vector2(0.0, -r.randf_range(4.4, 5.2)))
		_:  # windmill / hill / loop, on the last straight
			hw = r.randf_range(0.55, 0.62)
			if r.randf() < bend_p and (level >= 2 or i >= 3):
				shape = "bend"
				var a := r.randf_range(2.2, 2.4)
				var b := r.randf_range(1.2, 1.8)
				pts.append(Vector2(0.0, -a))
				pts.append(Vector2(side * b, -a))
				pts.append(Vector2(side * b, -a - r.randf_range(3.65, 3.9)))
			else:
				pts.append(Vector2(0.0, -r.randf_range(4.6, 5.6)))
	var d := _assemble(pts, hw)
	var n := pts.size() - 1
	var dn := (pts[n] - pts[n - 1]).normalized()
	var lat := Vector2(-dn.y, dn.x)
	d["gimmick"] = g
	d["shape"] = shape
	d["hw"] = hw
	d["seed"] = seed_value
	d["tee"] = pts[0] + Vector2(0.0, -TEE_IN)
	var cup := pts[n] - dn * r.randf_range(0.5, 0.65) + lat * r.randf_range(-0.15, 0.15) * (hw / 0.55)
	d["cup"] = cup
	var path: Array = []
	for k in range(1, n):
		path.append(pts[k])
	var bumpers: Array = []
	# Where the last straight starts (its gimmick sits between there and the cup).
	var start := (pts[n - 1].y - hw - 0.05) if n > 1 else (d["tee"] as Vector2).y - 0.3
	var x := pts[n].x
	match g:
		"bumper":
			for k in range(1, n):
				bumpers.append(_corner_bumper(pts, k, hw, r.randf_range(0.17, 0.2)))
		"windmill":
			var mz := _between(r, cup.y + 1.3, start - 0.6)
			d["mill_x"] = x
			d["mill_z"] = mz
			path.append(Vector2(x, mz + 0.3))
		"loop":
			var lz := _between(r, maxf(cup.y + 1.4, start - 1.8), start - 0.9)
			d["loop_x"] = x
			d["loop_z"] = lz
			path.append(Vector2(x, lz + 0.4))
		"hill":
			var w := r.randf_range(0.6, 0.8)
			d["hill_x"] = x
			d["hill_w"] = w
			d["hill_h"] = r.randf_range(0.12, 0.15) + (0.03 if level >= 4 else 0.0)
			d["hill_z"] = _between(r, cup.y + 0.5 + w, start - 0.2 - w)
		"pinball":
			var z1 := _between(r, cup.y + 1.9, (d["tee"] as Vector2).y - 1.3)
			var jx := r.randf_range(-0.05, 0.05)
			var br := r.randf_range(0.12, 0.14)
			bumpers.append([Vector2(-0.33 + jx, z1), br])
			bumpers.append([Vector2(0.33 + jx, z1), br])
			bumpers.append([Vector2(jx, z1 - 0.75), br])
			path.append(Vector2(jx, z1 + 0.4))  # between the front pair...
			path.append(Vector2(jx, z1 - 0.35))
			path.append(Vector2(jx + side * 0.45, z1 - 0.75))  # ...and round the back one
	if level >= 3 and shape == "bend":
		bumpers.append(_corner_bumper(pts, 1, hw, 0.17))
	d["bumpers"] = bumpers
	path.append(cup)
	d["path"] = path
	var par := 2 + (n - 1) + (1 if g in ["windmill", "loop", "hill", "pinball"] else 0)
	d["par"] = 2 if g == "" else clampi(par, 2, 4)
	_center(d)
	return d


## A random value in [lo, hi] (NAN when there's no room: check() turns it down).
static func _between(r: RandomNumberGenerator, lo: float, hi: float) -> float:
	return r.randf_range(lo, hi) if hi >= lo else NAN


## A springy bumper near the outer corner of bend k (it bounces the ball round the bend).
static func _corner_bumper(pts: Array[Vector2], k: int, hw: float, radius: float) -> Array:
	var din := (pts[k] - pts[k - 1]).normalized()
	var dout := (pts[k + 1] - pts[k]).normalized()
	return [pts[k] + (din - dout) * hw * 0.5, radius]


static func _nrm(v: Vector2) -> Vector2:
	var u := v.normalized()
	return Vector2(-u.y, u.x)


## Walls (outline) and floor (rects) of a corridor along a centre line of right-angle turns.
static func _assemble(pts: Array[Vector2], hw: float) -> Dictionary:
	var n := pts.size()
	var left: Array = []
	var right: Array = []
	for k in n:
		var m: Vector2
		if k == 0:
			m = _nrm(pts[1] - pts[0])
		elif k == n - 1:
			m = _nrm(pts[k] - pts[k - 1])
		else:
			m = _nrm(pts[k] - pts[k - 1]) + _nrm(pts[k + 1] - pts[k])
		left.append(pts[k] + m * hw)
		right.append(pts[k] - m * hw)
	right.reverse()
	var outline: Array = left + right
	var rects: Array = []
	for k in n - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var u := (b - a).normalized()
		var a2 := a - (u * hw if k > 0 else Vector2.ZERO)
		var b2 := b + (u * hw if k < n - 2 else Vector2.ZERO)
		var rc := Rect2(a2, Vector2.ZERO).expand(b2).grow_individual(
			hw if absf(u.y) > 0.5 else 0.0, hw if absf(u.x) > 0.5 else 0.0, hw if absf(u.y) > 0.5 else 0.0, hw if absf(u.x) > 0.5 else 0.0)
		rects.append([rc.position.x, rc.position.y, rc.end.x, rc.end.y])
	return {"outline": outline, "rects": rects}


## Move the hole so its middle is at the lawn's middle.
static func _center(d: Dictionary) -> void:
	var r := Rect2(d["outline"][0], Vector2.ZERO)
	for p in d["outline"]:
		r = r.expand(p)
	var o := -r.get_center()
	for key in ["outline", "path"]:
		var arr: Array = d[key]
		for k in arr.size():
			arr[k] = (arr[k] as Vector2) + o
	for rc in d["rects"]:
		rc[0] += o.x
		rc[1] += o.y
		rc[2] += o.x
		rc[3] += o.y
	for bm in d["bumpers"]:
		bm[0] = (bm[0] as Vector2) + o
	d["tee"] = (d["tee"] as Vector2) + o
	d["cup"] = (d["cup"] as Vector2) + o
	for key in ["mill_x", "loop_x", "hill_x"]:
		if d.has(key):
			d[key] = float(d[key]) + o.x
	for key in ["mill_z", "loop_z", "hill_z"]:
		if d.has(key):
			d[key] = float(d[key]) + o.y


## Things beside the hole that must stay off the fairway: [centre, radius] (the VR golfer's toys round
## the tee, the flag board, Gus's molehill). The garden's ornaments keep away from these too.
static func keep_clear(d: Dictionary) -> Array:
	var tee: Vector2 = d["tee"]
	var out: Array = [[tee + Vector2(Props.BUCKET.x, Props.BUCKET.z), 0.14], [tee + Vector2(Props.POND.x, Props.POND.z), 0.5]]
	for b in Props.BUSHES:
		out.append([tee + Vector2(b.x, b.z), 0.4])
	var bp := board_pos(d)
	for k in 5:
		out.append([bp + Vector2(-0.8 + k * 0.4, 0.0), 0.12])
	out.append([gus_pos(d), 0.18])
	return out


## The flag board (main.gd) and Gus's molehill beside it.
static func board_pos(d: Dictionary) -> Vector2:
	return (d["cup"] as Vector2) + Vector2(0.0, -BOARD_BACK)


static func gus_pos(d: Dictionary) -> Vector2:
	return board_pos(d) + Vector2(GUS_SIDE, 0.05)


## Distance from p to the nearest wall of the outline.
static func wall_dist(outline: Array, p: Vector2) -> float:
	var best := INF
	for k in outline.size():
		var q := Geometry2D.get_closest_point_to_segment(p, outline[k], outline[(k + 1) % outline.size()])
		best = minf(best, q.distance_to(p))
	return best


## Problems with a generated hole (empty = fine).
static func check(d: Dictionary) -> Array:
	var why: Array = []
	for key in ["mill_z", "loop_z", "hill_z"]:
		if d.has(key) and is_nan(float(d[key])):
			return ["no room for the %s" % String(d["gimmick"])]
	var ol: Array = d["outline"]
	var poly := PackedVector2Array(ol)
	var n := ol.size()
	for a in n:
		for b in range(a + 2, n):
			if a == 0 and b == n - 1:
				continue
			if Geometry2D.segment_intersects_segment(ol[a], ol[(a + 1) % n], ol[b], ol[(b + 1) % n]) != null:
				why.append("the walls cross")
	var r := Rect2(ol[0], Vector2.ZERO)
	for p in ol:
		r = r.expand(p)
	if r.size.x > MAX_SIZE.x + 0.01 or r.size.y > MAX_SIZE.y + 0.01:
		why.append("too big %s" % str(r.size))
	if r.get_center().length() > 0.05:
		why.append("not in the middle of the lawn")
	var tee: Vector2 = d["tee"]
	var cup: Vector2 = d["cup"]
	var hw := float(d["hw"])
	for k in 7:  # every ball's tee spot (main._tee_spot: up to 7 players)
		var p := tee + Vector2((k - 3) * 0.12, 0.0)
		if not Geometry2D.is_point_in_polygon(p, poly) or wall_dist(ol, p) < Course.BALL_R + 0.02:
			why.append("a tee spot is in a wall")
			break
	if not Geometry2D.is_point_in_polygon(cup, poly) or wall_dist(ol, cup) < Course.CUP_R + 0.1:
		why.append("the cup is too close to a wall")
	if tee.distance_to(cup) < 2.0:
		why.append("the cup is too close to the tee")
	var c := Course.new()
	c.setup(d)
	var chain: Array = [tee]
	chain.append_array(d["path"])
	for k in chain.size():
		var p: Vector2 = chain[k]
		if not Geometry2D.is_point_in_polygon(p, poly) or wall_dist(ol, p) < Course.BALL_R + 0.05:
			why.append("aim point %d is off the green" % k)
		for bm in c.bumpers:
			if p.distance_to(bm[0]) < float(bm[1]) + Course.BALL_R + 0.03:
				why.append("aim point %d is on a bumper" % k)
		if k > 0 and not c.clear_line(chain[k - 1], p):
			why.append("aim point %d can't be seen from the one before" % k)
	if (chain[chain.size() - 1] as Vector2) != cup:
		why.append("the aim path doesn't end at the cup")
	for bm in c.bumpers:
		if not Geometry2D.is_point_in_polygon(bm[0], poly):
			why.append("a bumper is off the green")
		if (bm[0] as Vector2).distance_to(cup) < float(bm[1]) + Course.CUP_R + 0.15:
			why.append("a bumper is on the cup")
	match String(d["gimmick"]):
		"windmill":
			for p in [Vector2(c.mill_x, c.mill_z + 0.3), Vector2(c.mill_x - hw + 0.05, c.mill_z - 0.4), Vector2(c.mill_x + hw - 0.05, c.mill_z - 0.4)]:
				if not Geometry2D.is_point_in_polygon(p, poly):
					why.append("the windmill isn't on a straight")
			if cup.y > c.mill_z - 0.36 - 0.7:
				why.append("the cup is too close behind the windmill")
		"loop":
			for p in [Vector2(c.loop_x, c.loop_z + 0.85), Vector2(c.loop_x - hw + 0.05, c.loop_z - 0.5), Vector2(c.loop_x + hw - 0.05, c.loop_z - 0.5)]:
				if not Geometry2D.is_point_in_polygon(p, poly):
					why.append("the loop isn't on a straight")
			if cup.y > c.loop_z - 1.1:
				why.append("the cup is too close behind the loop")
		"hill":
			for p in [Vector2(c.hill_x - hw + 0.05, c.hill_z - c.hill_w), Vector2(c.hill_x + hw - 0.05, c.hill_z + c.hill_w)]:
				if not Geometry2D.is_point_in_polygon(p, poly):
					why.append("the hill isn't on a straight")
			if c.grad(cup).length() > 0.0 or c.height(cup) > 0.0 or c.grad(tee).length() > 0.0:
				why.append("the tee or cup is on the hill")
	for kc in keep_clear(d):
		var p: Vector2 = kc[0]
		if Geometry2D.is_point_in_polygon(p, poly) or wall_dist(ol, p) < float(kc[1]) + 0.08:
			why.append("something beside the hole is on the green at %s" % str(p))
	var par := int(d["par"])
	if par < 2 or par > 4:
		why.append("par %d" % par)
	c.free()
	return why


## Fair AND proven: a good putter sinks it within par + 2 (never a frustrating hole).
static func proven(d: Dictionary) -> bool:
	var r := sim(d)
	return bool(r["sunk"]) and int(r["putts"]) <= int(d["par"]) + 2


## How a good putter hits it: the speed for a putt from `from` to the aim point `to` (the bots use it too).
static func putt_speed(c: Course, from: Vector2, to: Vector2) -> float:
	var d := from.distance_to(to)
	var v := sqrt(2.0 * 1.15 * d) + 0.15
	if c.gimmick == "hill" and absf(from.x - c.hill_x) <= c.hw + 0.05 and from.y > c.hill_z - 0.2 and to.y < c.hill_z:
		v = sqrt(v * v + 2.0 * 9.8 * 5.0 / 7.0 * c.hill_h + 0.6)
	if c.gimmick == "loop" and from.y > c.loop_z and to.y < c.loop_z:
		v = 3.6
	if c.gimmick == "windmill" and from.y > c.mill_z and to.y < c.mill_z:
		v = maxf(v, 2.2)
	return minf(v, 3.9)


## Proof the hole can be sunk: an aiming putter (aim at course.aim_point, putt_speed) with the game's own
## ball physics and windmill. {"sunk": bool, "putts": n}.
static func sim(d: Dictionary, max_putts: int = MAX_PUTTS) -> Dictionary:
	var c := Course.new()
	c.setup(d)
	var b := Ball.new()
	b.course = c
	b.place(d["tee"])
	var putts := 0
	var sunk := false
	var dt := 1.0 / 60.0
	while putts < max_putts and not sunk:
		var to := c.aim_point(b.pos)
		var dir := (to - b.pos).normalized()
		b.putt(dir * putt_speed(c, b.pos, to))
		putts += 1
		var steps := 0
		while b.state != "rest" and steps < 60 * 16:
			c.tick(dt)
			b.step(dt)
			b.events.clear()
			steps += 1
			if b.state == "cup":
				sunk = true
				break
	b.free()
	c.free()
	return {"sunk": sunk, "putts": putts}
