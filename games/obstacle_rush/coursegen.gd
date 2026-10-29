extends RefCounted
## OBSTACLE RUSH courses as DESCRIPTIONS (plain Dictionaries): the four lesson courses (HOP HOP, SPINNER,
## BOING, DOORS) and seeded courses that string the same pieces together along +X:
##   gap      a hole to jump (a star may float over it)
##   spinner  a round platform with the spinning bar (a star sits on the far side of the disc)
##   boing    a bounce pad up a big step (a star hangs high in the pad's flight)
##   doors    a wall of three doors, one or two pretend (a star waits behind one door)
##   drop     a big step down (only after a boing)
## Rising challenge by TIER (story.gd picks it from how many shows the family has done): more pieces,
## wider gaps, more pretend doors, a faster spinner, more stars. Same (seed, tier, attempt) -> the same
## course on every machine: the host sends {k, s, tier, a} and every machine calls make().
## check() is the validator (tests/obstacle_rush_gen_test.gd): the geometry is sane, every checkpoint is
## safe and comes right after its obstacle (a ball bonk or a fall never costs more than one obstacle), a
## real door in every wall, every star is reachable, and a simulated jelly bean (runner.gd's physics,
## cpu_brain.gd's route rules) runs every course from the start to the flag at CPU speed and at full speed,
## jumping early and late, without ever falling off.

const Seeded := preload("res://core/seeded.gd")
const Runner := preload("res://games/obstacle_rush/runner.gd")
const RunnerLook := preload("res://games/obstacle_rush/runner_look.gd")
const CpuBrain := preload("res://games/obstacle_rush/cpu_brain.gd")

const KINDS: Array[String] = ["gap", "spinner", "boing", "doors", "drop"]
const LESSONS: Array[String] = ["HOP HOP", "SPINNER", "BOING", "DOORS"]
const NAMES: Array[String] = ["JELLY JUMBLE", "BOUNCE ALLEY", "WOBBLE WAY", "CANDY CANYON", "SPRINKLE SPRINT",
	"GUMDROP GO", "LOLLY LOOP", "FIZZY FALLS", "TOFFEE TRAIL", "MARSHMALLOW MILE", "SHERBET SHUFFLE",
	"BONBON BRIDGE", "JELLY JUNGLE", "SUGAR STEPS", "CUPCAKE CLIMB", "WIGGLE WALK"]
const X_MIN := -19.0  ## the table is 42 wide (main.gd TABLE_W)
const X_MAX := 19.0
const GEN_START_X := -16.8
const STEP := 3.0  ## a boing step up / a drop down
const TOP := 6.0
const HALF_W := 3.0  ## generated courses (three doors fit across)
const SPIN_R := 4.6  ## the spinner's disc
const BAR_R := 4.2
const PAD_V := Vector3(4.2, 15.0, 0.0)  ## a bounce pad's kick (course.gd pad_launch)
const PAD_R := 0.85
const DOOR_W := 2.0
const GIANT_X := 20.0  ## the giant walks x -17..17 (giant.gd WALK_X) and reaches ~3 further
const MAX_CP_GAP := 18.0  ## a pop-back never costs more than ~3 s of running
const STAR_R := 1.0  ## how close a runner's middle must come to a star

## Per tier: pieces, gap widths, pretend doors per wall, spinner speed, stars.
const TIERS: Array[Dictionary] = [
	{"n": 2, "gap": [1.5, 2.0], "fakes": [1, 1], "spin": 1.0, "stars": 1},
	{"n": 3, "gap": [1.6, 2.2], "fakes": [1, 1], "spin": 1.1, "stars": 2},
	{"n": 3, "gap": [1.8, 2.4], "fakes": [1, 2], "spin": 1.25, "stars": 2},
	{"n": 4, "gap": [1.9, 2.5], "fakes": [2, 2], "spin": 1.35, "stars": 3},
	{"n": 4, "gap": [2.0, 2.5], "fakes": [2, 2], "spin": 1.5, "stars": 3},
]
## Room on the floor before each kind of obstacle (from where the last one let you land).
const ROOM := {"gap": 1.4, "spinner": 1.2, "boing": 2.2, "doors": 1.2, "drop": 1.5}
const ATTEMPTS := 60


static func tier_count() -> int:
	return TIERS.size()


## The course for a compact description {k: "lesson" | "gen" | "daily", i (lesson), s (seed), tier, a
## (attempt; -1 = search)}. Every machine calls this with the host's description.
static func make(d: Dictionary) -> Dictionary:
	var k := String(d.get("k", "lesson"))
	if k == "lesson":
		return lesson(int(d.get("i", 0)), int(d.get("s", 1)))
	var c := generate(int(d.get("s", 1)), int(d.get("tier", 0)), int(d.get("a", -1)))
	c["kind"] = k
	if k == "daily":
		c["name"] = "TODAY'S COURSE"
	return c


## The compact description of a generated course (with the attempt that passed, so other machines
## rebuild exactly it without re-running the search).
static func describe(kind: String, seed_value: int, tier: int) -> Dictionary:
	var c := generate(seed_value, tier)
	return {"k": kind, "s": seed_value, "tier": clampi(tier, 0, TIERS.size() - 1), "a": int(c.get("attempt", -1))}


static func _blank() -> Dictionary:
	return {"name": "", "kind": "gen", "seed": 0, "tier": 0, "index": -1, "half_w": HALF_W, "start_x": GEN_START_X,
		"finish_x": 9.3, "finish_y": 0.0, "low_y": 0.0, "floors": [], "discs": [], "spinner": {}, "pads": [],
		"walls": [], "checkpoints": [], "route": [], "stars": [], "obstacles": [], "pieces": [],
		"ring": Vector3.INF, "target": Vector3.INF, "crown": false, "palette": 0}


# --- The four lessons ------------------------------------------------------------------------------

static func lesson(i: int, seed_value: int = 1) -> Dictionary:
	var c := _blank()
	i = clampi(i, 0, LESSONS.size() - 1)
	c.name = LESSONS[i]
	c.kind = "lesson"
	c.index = i
	c.seed = seed_value
	c.half_w = 3.0 if i == 3 else 2.0
	c.start_x = -11.0
	c.finish_x = 9.3
	match i:
		0:
			c.floors = [[-13.0, -4.0, 0.0, 0], [-1.5, 3.5, 0.0, 1], [6.0, 13.0, 0.0, 2]]
			c.checkpoints = [Vector3(-11, 0, 0), Vector3(-0.5, 0, 0), Vector3(7.0, 0, 0)]
			c.route = [[Vector3(-4.4, 0, 0), "jump"], [Vector3(-0.5, 0, 0), ""], [Vector3(3.1, 0, 0), "jump"], [Vector3(11.5, 0, 0), ""]]
			c.obstacles = [[-4.0, -1.5, "gap"], [3.5, 6.0, "gap"]]
			c.pieces = ["gap", "gap"]
			c.ring = Vector3(-2.75, 1.25, 0.0)
			c.target = Vector3(1.0, 0.03, 0.0)
			c.stars = [Vector3(4.75, 1.7, 0.0)]
		1:
			c.floors = [[-13.0, -4.2, 0.0, 0], [4.2, 13.0, 0.0, 2]]
			c.discs = [[0.0, 0.0, SPIN_R, 1]]
			c.spinner = {"x": 0.0, "y": 0.0, "speed": 1.1}
			c.checkpoints = [Vector3(-11, 0, 0), Vector3(6.0, 0, 0)]
			c.route = [[Vector3(-4.6, 0, 0), ""], [Vector3(-2.6, 0, 1.7), "spin"], [Vector3(2.6, 0, 1.7), "spin"],
				[Vector3(4.8, 0, 0), ""], [Vector3(11.5, 0, 0), ""]]
			c.obstacles = [[-4.6, 4.6, "spinner"]]
			c.pieces = ["spinner"]
			c.stars = [Vector3(0.0, 0.9, -1.5)]
		2:
			c.floors = [[-13.0, -1.0, 0.0, 0], [-1.0, 4.0, 3.0, 1], [4.0, 13.0, 6.0, 2]]
			c.pads = [Vector3(-3.0, 0, 0), Vector3(2.0, 3.0, 0)]
			c.finish_y = 6.0
			c.checkpoints = [Vector3(-11, 0, 0), Vector3(0.0, 3, 0), Vector3(6.0, 6, 0)]
			c.route = [[Vector3(-3.0, 0, 0), "pad"], [Vector3(0.5, 3, 0), ""], [Vector3(2.0, 3, 0), "pad"], [Vector3(11.5, 6, 0), ""]]
			c.obstacles = [[-3.85, -1.0, "boing"], [1.15, 4.0, "boing"]]
			c.pieces = ["boing", "boing"]
			c.stars = [_pad_star(Vector3(2.0, 3.0, 0))]
		_:
			c.floors = [[-13.0, 13.0, 0.0, 0]]
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var walls: Array[float] = [-3.0, 4.0]
			var fakes: Array[int] = [1, 2]
			for w in 2:
				var order: Array[int] = [0, 1, 2]
				for k in 3:  # shuffle (same on every machine: the seed is shared)
					var j := rng.randi_range(k, 2)
					var tmp := order[k]
					order[k] = order[j]
					order[j] = tmp
				var f: Array = []
				for k in 3:
					f.append(order.find(k) < fakes[w])
				c.walls.append({"x": walls[w], "y": 0.0, "fakes": f})
			c.checkpoints = [Vector3(-11, 0, 0), Vector3(0.5, 0, 0), Vector3(7.0, 0, 0)]
			c.route = [[Vector3(-2.4, 0, 0), "door"], [Vector3(-0.5, 0, 0), ""], [Vector3(4.6, 0, 0), "door"], [Vector3(11.5, 0, 0), ""]]
			c.obstacles = [[-3.3, -2.7, "doors"], [3.7, 4.3, "doors"]]
			c.pieces = ["doors", "doors"]
			c.crown = true
			var real := 0
			while bool(c.walls[0].fakes[real]):
				real += 1
			c.stars = [Vector3(-1.7, 0.8, -2.0 + real * 2.0)]
	c.finish_y = float(c.floors[-1][2])
	return c


# --- Seeded courses ----------------------------------------------------------------------------------

## A seeded course of the tier's pieces. attempt >= 0 rebuilds exactly that attempt (other machines);
## -1 searches attempts until one passes check() (falls back to a small safe course, never expected).
static func generate(seed_value: int, tier: int, attempt: int = -1) -> Dictionary:
	tier = clampi(tier, 0, TIERS.size() - 1)
	if attempt >= 0:
		var c := _try(Seeded.rng(seed_value, "course%d" % attempt), tier, _pieces_for(tier, attempt))
		if not c.is_empty():
			return _finish_desc(c, seed_value, tier, attempt)
	for a in ATTEMPTS:
		var c2 := _try(Seeded.rng(seed_value, "course%d" % a), tier, _pieces_for(tier, a))
		if c2.is_empty():
			continue
		_finish_desc(c2, seed_value, tier, a)
		if check(c2).is_empty():
			return c2
	var easy := lesson(0, seed_value)
	easy["fallback"] = true
	easy["kind"] = "gen"
	easy["tier"] = tier
	easy["attempt"] = -1
	return easy


static func _pieces_for(tier: int, attempt: int) -> int:
	return maxi(2, int(TIERS[tier].n) - attempt / 25)  # (later attempts try one piece fewer)


static func _finish_desc(c: Dictionary, seed_value: int, tier: int, attempt: int) -> Dictionary:
	c["seed"] = seed_value
	c["tier"] = tier
	c["attempt"] = attempt
	return c


static func _try(r: RandomNumberGenerator, tier: int, n: int) -> Dictionary:
	var T: Dictionary = TIERS[tier]
	var c := _blank()
	c.name = NAMES[r.randi() % NAMES.size()]
	c.palette = r.randi() % 4
	var floors: Array = [[X_MIN, X_MAX, 0.0, 0]]
	var y := 0.0
	var x := GEN_START_X + 1.6 + r.randf_range(0.0, 0.8)  # where the room for the first obstacle starts
	var picks: Array = []
	var cands: Array = []  # star candidates
	c.checkpoints = [Vector3(GEN_START_X, 0, 0)]
	for i in n:
		var pool: Array = []
		var w: Array = []
		for k in KINDS:
			if k == "spinner" and picks.has("spinner"):
				continue
			if k == "boing" and y + STEP > TOP:
				continue
			if k == "drop" and (y < STEP or (picks.size() > 0 and String(picks[-1]) == "drop")):
				continue
			if k == "doors" and picks.count("doors") >= 2:
				continue
			if picks.size() > 0 and String(picks[-1]) == k and k != "gap":
				continue
			pool.append(k)
			w.append({"gap": 3.0, "spinner": 1.5, "boing": 2.0, "doors": 1.5, "drop": 2.5}[k])
		var k: String = pool[Seeded.weighted(r, w)]
		picks.append(k)
		var a: float = x + float(ROOM[k]) + r.randf_range(0.0, 1.4 if tier < 3 else 0.9)
		var col := (floors.size() + int(c.palette)) % 4
		match k:
			"gap":
				var g: float = snappedf(r.randf_range(float(T.gap[0]), float(T.gap[1])), 0.05)
				floors[-1][1] = a
				floors.append([a + g, X_MAX, y, col])
				c.route.append([Vector3(a - 0.3, y, 0), "jump"])
				c.route.append([Vector3(a + g + 1.2, y, 0), ""])
				c.obstacles.append([a, a + g, "gap"])
				c.checkpoints.append(Vector3(a + g + 1.0, y, 0))
				cands.append(Vector3(a + g * 0.5, y + 1.7, 0.0))
				x = a + g + 1.5
			"spinner":
				var cx := a + BAR_R
				floors[-1][1] = a
				c.discs.append([cx, y, SPIN_R, col])
				floors.append([cx + BAR_R, X_MAX, y, (col + 1) % 4])
				c.spinner = {"x": cx, "y": y, "speed": float(T.spin)}
				c.route.append([Vector3(a - 0.4, y, 0), ""])
				c.route.append([Vector3(cx - 2.6, y, 1.7), "spin"])
				c.route.append([Vector3(cx + 2.6, y, 1.7), "spin"])
				c.route.append([Vector3(cx + BAR_R + 0.6, y, 0), ""])
				c.obstacles.append([cx - SPIN_R, cx + SPIN_R, "spinner"])
				c.checkpoints.append(Vector3(cx + BAR_R + 1.8, y, 0))
				cands.append(Vector3(cx, y + 0.9, 2.4 if r.randf() < 0.5 else -2.4))
				x = cx + BAR_R + 1.6
			"boing":
				var pad := Vector3(a, y, 0)
				var wall := a + 2.0
				floors[-1][1] = wall
				floors.append([wall, X_MAX, y + STEP, col])
				c.pads.append(pad)
				c.route.append([pad, "pad"])
				c.route.append([Vector3(wall + 1.5, y + STEP, 0), ""])
				c.obstacles.append([a - PAD_R, wall, "boing"])
				c.checkpoints.append(Vector3(wall + 2.0, y + STEP, 0))
				cands.append(_pad_star(pad))
				y += STEP
				x = wall + 1.5
			"doors":
				var wx := a + 0.3
				var fk := r.randi_range(int(T.fakes[0]), int(T.fakes[1]))
				var order := Seeded.shuffled(r, [0, 1, 2])
				var f: Array = []
				for d in 3:
					f.append(order.find(d) < fk)
				c.walls.append({"x": wx, "y": y, "fakes": f})
				c.route.append([Vector3(wx + 0.6, y, 0), "door"])
				c.route.append([Vector3(wx + 2.2, y, 0), ""])
				c.obstacles.append([wx - 0.3, wx + 0.3, "doors"])
				c.checkpoints.append(Vector3(wx + 1.6, y, 0))
				cands.append(Vector3(wx + 1.3, y + 0.8, -2.0 + 2.0 * float(r.randi_range(0, 2))))
				x = wx + 1.5
			"drop":
				floors[-1][1] = a
				floors.append([a, X_MAX, y - STEP, col])
				y -= STEP
				c.route.append([Vector3(a + 1.4, y, 0), ""])
				c.obstacles.append([a - 0.2, a + 0.6, "drop"])
				c.checkpoints.append(Vector3(a + 2.0, y, 0))
				x = a + 1.5
	# The finish: the arch, then room for the flag and the crown.
	var fx := snappedf(x + r.randf_range(2.5, 3.5), 0.1)
	if fx + 3.8 > X_MAX:
		return {}
	c.route.append([Vector3(fx + 2.2, y, 0), ""])
	c.start_x = GEN_START_X
	c.finish_x = fx
	c.finish_y = y
	c.floors = floors
	c.pieces = picks
	# Stars: some of the candidates (a star needs a little detour or a bold jump: the team's choice).
	var want := mini(int(T.stars), cands.size())
	for s in Seeded.shuffled(r, cands):
		if (c.stars as Array).size() >= want:
			break
		c.stars.append(s)
	# Trim the ends and centre the course on the table (a short one too: the giant's walk and the TV
	# view stay balanced, and no long empty floor runs on past the flag).
	floors[0][0] = GEN_START_X - 2.2
	floors[-1][1] = fx + 3.8
	_shift(c, -snappedf((float(floors[0][0]) + float(floors[-1][1])) * 0.5, 0.1))
	return c


## Move a whole course along x by dx.
static func _shift(c: Dictionary, dx: float) -> void:
	if absf(dx) < 0.001:
		return
	var v := Vector3(dx, 0, 0)
	for f in c.floors:
		f[0] = float(f[0]) + dx
		f[1] = float(f[1]) + dx
	for d in c.discs:
		d[0] = float(d[0]) + dx
	if not (c.spinner as Dictionary).is_empty():
		c.spinner.x = float(c.spinner.x) + dx
	for i in (c.pads as Array).size():
		c.pads[i] = (c.pads[i] as Vector3) + v
	for w in c.walls:
		w.x = float(w.x) + dx
	for i in (c.checkpoints as Array).size():
		c.checkpoints[i] = (c.checkpoints[i] as Vector3) + v
	for p in c.route:
		p[0] = (p[0] as Vector3) + v
	for i in (c.stars as Array).size():
		c.stars[i] = (c.stars[i] as Vector3) + v
	for o in c.obstacles:
		o[0] = float(o[0]) + dx
		o[1] = float(o[1]) + dx
	c.start_x = float(c.start_x) + dx
	c.finish_x = float(c.finish_x) + dx


## Where a pad's star hangs: in the bean's flight a little after the kick (CPU speed).
static func _pad_star(pad: Vector3) -> Vector3:
	var vx := PAD_V.x
	var px := pad.x
	var py := pad.y
	var vy := PAD_V.y
	var dt := 1.0 / 60.0
	for k in 26:
		vx = move_toward(vx, Runner.RUN_SPEED * Runner.CPU_SPEED, Runner.AIR_ACCEL * dt)
		vy -= Runner.GRAVITY * dt
		px += vx * dt
		py += vy * dt
	return Vector3(snappedf(px, 0.05), snappedf(py + 0.6, 0.05), 0.0)


# --- Geometry helpers (shared by the validator and the course) ------------------------------------

## The top of whatever stands under (x, z) at or below `below` (or -INF): floors, discs.
static func support_y(c: Dictionary, x: float, z: float = 0.0, below: float = INF, tol: float = 0.0) -> float:
	var best := -INF
	var hw: float = c.half_w
	for f in c.floors:
		if x >= float(f[0]) - tol and x <= float(f[1]) + tol and absf(z) <= hw + 0.01 and float(f[2]) <= below + 0.05:
			best = maxf(best, float(f[2]))
	for d in c.discs:
		if Vector2(x - float(d[0]), z).length() <= float(d[2]) + tol and float(d[1]) <= below + 0.05:
			best = maxf(best, float(d[1]))
	return best


## Is the point (x, z) at height y standing on something (within 0.05)?
static func stands(c: Dictionary, p: Vector3) -> bool:
	return absf(support_y(c, p.x, p.z, p.y) - p.y) < 0.06


## Solid top at x (floors and the candy blocks under raised floors reach down to the table).
static func solid_top(c: Dictionary, x: float) -> float:
	var best := -INF
	for f in c.floors:
		if x > float(f[0]) + 0.01 and x < float(f[1]) - 0.01:
			best = maxf(best, float(f[2]))
	return best


# --- The simulated jelly bean -------------------------------------------------------------------------

## Run a bean along the course in x/y with runner.gd's physics and cpu_brain.gd's route rules.
## speed: 1.0 = a person at full stick, Runner.CPU_SPEED = a CPU runner. early: jump as soon as the brain
## would (0.9 before the jump point), else at the last moment. Returns {ok, t, why, path (mid-body points)}.
static func simulate(c: Dictionary, speed: float, early: bool) -> Dictionary:
	var dt := 1.0 / 60.0
	var x: float = float(c.start_x)
	var y: float = support_y(c, x)
	var vx := 0.0
	var vy := 0.0
	var on_floor := true
	var air_t := 0.0
	var route: Array = c.route
	var path: Array = []
	var rad := RunnerLook.RADIUS
	var tol := rad * 0.6
	var best_x := x
	var stuck := 0.0
	for step in 40 * 60:
		var t := step * dt
		# The brain: the first route point not passed yet.
		var wp := CpuBrain.route_index(route, Vector3(x, y, 0.0))
		var goal: Vector3 = route[wp][0]
		var what := String(route[wp][1])
		var dir := signf(goal.x - x)
		if absf(goal.x - x) < 0.6:
			dir = 1.0
		if what == "pad" and y > goal.y + 0.8:
			dir = 1.0
		var want := dir * Runner.RUN_SPEED * speed
		var jump := false
		if what == "jump" and absf(goal.x - x) < (0.9 if early else 0.15):
			jump = true
		if x > best_x + 0.3:
			best_x = x
			stuck = 0.0
		else:
			stuck += dt
			if stuck > 1.5:
				jump = true
				stuck = 0.0
				best_x = x
		vx = move_toward(vx, want, (Runner.ACCEL if on_floor else Runner.AIR_ACCEL) * dt)
		vy -= Runner.GRAVITY * dt
		if jump and air_t < Runner.COYOTE:
			vy = Runner.JUMP_V
			air_t = Runner.COYOTE
		if on_floor:
			for p in c.pads:
				var pp: Vector3 = p
				if absf(y - (pp.y + 0.35)) < 0.5 and absf(x - pp.x) < PAD_R:
					vx = PAD_V.x
					vy = PAD_V.y
		vy = maxf(vy, -30.0)
		var nx := x + vx * dt
		var ny := y + vy * dt
		# Walls: a raised floor (and its candy block) in front of the feet.
		for f in c.floors:
			var fy := float(f[2])
			if fy > ny + 0.05 and nx + rad > float(f[0]) and x + rad <= float(f[0]) + 0.02:
				nx = float(f[0]) - rad
				vx = 0.0
		# Land on (or stay on) whatever is under the feet.
		var s := support_y(c, nx, 0.0, maxf(y, ny), tol)
		if vy <= 0.0 and s > -INF and ny <= s + 0.001 and s <= y + 0.06:
			ny = s
			vy = 0.0
			on_floor = true
		else:
			on_floor = false
		air_t = 0.0 if on_floor else air_t + dt
		x = nx
		y = ny
		if step % 3 == 0:
			path.append(Vector3(x, y + 0.6, 0.0))
		if y < float(c.low_y) + Runner.FALL_Y:
			return {"ok": false, "t": t, "why": "fell at x %.1f (speed %.2f, %s)" % [x, speed, "early" if early else "late"], "path": path}
		if x > float(c.finish_x) + 0.3 and y > float(c.finish_y) - 0.6:
			return {"ok": true, "t": t, "why": "", "path": path}
	return {"ok": false, "t": 40.0, "why": "never reached the flag (stuck at x %.1f y %.1f, speed %.2f)" % [x, y, speed], "path": path}


# --- The validator ---------------------------------------------------------------------------------------

## Reasons this course is broken or unfair (empty when fine).
static func check(c: Dictionary) -> Array:
	var why: Array = []
	for key in ["floors", "route", "checkpoints", "finish_x", "start_x", "obstacles"]:
		if not c.has(key):
			return ["no course (missing %s)" % key]
	if c.has("fallback"):
		why.append("fell back to the practice course")
	var floors: Array = c.floors
	var hw: float = c.half_w
	if floors.is_empty():
		return ["no floors"]
	for i in floors.size():
		var f: Array = floors[i]
		if float(f[0]) < X_MIN - 0.01 or float(f[1]) > X_MAX + 0.01:
			why.append("floor %d off the table %s" % [i, str(f)])
		if float(f[1]) - float(f[0]) < 1.5:
			why.append("floor %d is a sliver %s" % [i, str(f)])
		if float(f[2]) < -0.01 or float(f[2]) > TOP + 0.01:
			why.append("floor %d too high or low %s" % [i, str(f)])
		if i > 0 and float(f[0]) < float(floors[i - 1][1]) - 0.01:
			why.append("floors %d and %d overlap" % [i - 1, i])
	if not (c.spinner as Dictionary).is_empty():
		var sp: Dictionary = c.spinner
		if absf(float(sp.speed)) > 1.6:
			why.append("spinner too fast %.2f" % float(sp.speed))
		if (c.discs as Array).size() != 1:
			why.append("a spinner needs exactly one disc")
	var walls: Array = c.walls
	for w in walls:
		var wd: Dictionary = w
		var real := 0
		for fk in wd.fakes:
			real += 0 if bool(fk) else 1
		if real < 1:
			why.append("door wall at x %.1f has no real door" % float(wd.x))
		if hw < 2.99:
			why.append("door wall on a narrow course")
		if not stands(c, Vector3(float(wd.x), float(wd.y), 0)) or not stands(c, Vector3(float(wd.x) + 1.2, float(wd.y), 0)) \
				or not stands(c, Vector3(float(wd.x) - 1.2, float(wd.y), 0)):
			why.append("door wall at x %.1f doesn't stand on a floor with room round it" % float(wd.x))
	for p in c.pads:
		if not stands(c, p):
			why.append("pad %s floats" % str(p))
	# The start line and the finish.
	for n in 8:
		var sp2 := start_spot(c, n, 8)
		if support_y(c, sp2.x, sp2.z, 1.0) < -0.01:
			why.append("start spot %d off the floor %s" % [n, str(sp2)])
	var fx: float = c.finish_x
	var fy: float = c.finish_y
	for dx in [-1.0, 0.0, 2.5, 3.4]:
		if not stands(c, Vector3(fx + float(dx), fy, 0)):
			why.append("finish area at x %.1f isn't solid" % (fx + float(dx)))
	# Checkpoints: one before every obstacle and one right after it, each safe to pop back to.
	var cps: Array = c.checkpoints
	var obs: Array = c.obstacles
	if cps.size() != obs.size() + 1:
		why.append("%d checkpoints for %d obstacles" % [cps.size(), obs.size()])
	for k in cps.size():
		var cp: Vector3 = cps[k]
		for dz in [-hw + 0.6, 0.0, hw - 0.6]:
			for dx in [-0.6, 0.6]:
				if not stands(c, Vector3(cp.x + float(dx), cp.y, float(dz))):
					why.append("checkpoint %d %s has no room to stand" % [k, str(cp)])
		if k > 0 and cp.x - (cps[k - 1] as Vector3).x > MAX_CP_GAP:
			why.append("checkpoints %d and %d too far apart" % [k - 1, k])
		if k < obs.size() and cp.x > float(obs[k][0]):
			why.append("checkpoint %d is past obstacle %d" % [k, k])
		if k > 0 and k - 1 < obs.size() and cp.x < float(obs[k - 1][1]):
			why.append("checkpoint %d is before the end of obstacle %d" % [k, k - 1])
		for d in c.discs:
			if Vector2(cp.x - float(d[0]), 0.0).length() < float(d[2]) + 0.4:
				why.append("checkpoint %d on the spinner" % k)
		for p in c.pads:
			if absf(cp.x - (p as Vector3).x) < PAD_R + 0.8:
				why.append("checkpoint %d on a bounce pad" % k)
		for w in walls:
			if absf(cp.x - float(w.x)) < 0.9:
				why.append("checkpoint %d in a door wall" % k)
	# The route: CPU runners' waypoints stand on something; the last one is past the flag.
	var route: Array = c.route
	for k in route.size():
		var p: Vector3 = route[k][0]
		if not stands(c, p):
			why.append("route point %d %s stands on nothing" % [k, str(p)])
		if absf(p.x) > GIANT_X:
			why.append("route point %d out of the giant's reach" % k)
	if route.is_empty() or (route[-1][0] as Vector3).x < fx + 0.3:
		why.append("the route doesn't reach the flag")
	# The simulated bean, at CPU speed and full speed, jumping early and late.
	var paths: Array = []
	for speed in [Runner.CPU_SPEED, 1.0]:
		for early in [true, false]:
			var sim := simulate(c, float(speed), bool(early))
			if not bool(sim.ok):
				why.append("sim: " + String(sim.why))
			elif float(sim.t) > 25.0:
				why.append("sim: too long a run (%.0f s)" % float(sim.t))
			paths.append(sim.path)
	# Stars: inside the course, not in a wall, reachable by a jump from the floor or on a bean's flight.
	var stars: Array = c.stars
	for i in stars.size():
		var s: Vector3 = stars[i]
		if absf(s.z) > hw - 0.4 or s.x < X_MIN or s.x > X_MAX:
			why.append("star %d off the course %s" % [i, str(s)])
		var top := solid_top(c, s.x)
		if top > -INF and s.y < top + 0.2:
			why.append("star %d inside a wall %s" % [i, str(s)])
		var under := support_y(c, s.x, s.z, s.y)
		var ok := under > -INF and s.y - under >= 0.2 and s.y - under <= 2.6
		if not ok and absf(s.z) < hw - 0.5:
			for path in paths:
				for q in path:
					if Vector2((q as Vector3).x - s.x, (q as Vector3).y - s.y).length() < STAR_R * 0.9:
						ok = true
						break
				if ok:
					break
		if not ok:
			why.append("star %d can't be reached %s" % [i, str(s)])
		for j in range(i + 1, stars.size()):
			if s.distance_to(stars[j]) < 2.0:
				why.append("stars %d and %d on top of each other" % [i, j])
	# The giant: every bit of the course in reach, and nothing roofs a runner over (balls can always land).
	for f in floors:
		if absf(float(f[0])) > GIANT_X or absf(float(f[1])) > GIANT_X:
			why.append("floor %s out of the giant's reach" % str(f))
	return why


## Where runner n of count starts (spread across the start line, a second row behind).
static func start_spot(c: Dictionary, n: int, count: int) -> Vector3:
	var hw: float = c.half_w
	var row := n % 4
	var col := n / 4
	var spread := (float(row) - float(mini(count, 4) - 1) * 0.5) * 0.95
	return Vector3(float(c.start_x) - col * 1.2, 0.3, clampf(spread, -hw + 0.5, hw - 0.5))
