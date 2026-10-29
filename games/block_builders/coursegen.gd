extends RefCounted
## BLOCK BUILDERS sky adventures from a seed (SIMPLE_MODE, after the eight lesson levels): a course of
## 2-3 CHALLENGES strung along the sky, each one a shape the lessons taught - a GAP to bridge with planks,
## a cliff to climb with STAIRS or CRATES, a high wall to BOING up with a SPRING, a ledge to float up to
## with a FAN, a long gap to fly over with a LAUNCH PAD. Every piece is built exactly like its lesson
## level (same cells, same bot path), only placed, stacked and mixed differently, so every course can be
## solved the way the lessons taught. Rising: from adventure 3 three challenges, wider gaps, no spare.
## One LOST CLOUD FRIEND (story: Puff's friends) waits on a little side island off the path: two planks
## reach it. Rescuing it is the team's choice (it costs blocks and a detour; the flag clears the level
## either way). Output is a level Dictionary in levels.gd's format (+ "friend", "side"), so course.gd,
## the buddy runner and the bot play it like any lesson. check() is the validator
## (tests/block_builders_gen_test.gd); same (seed, adventure) -> same course on every machine.

const Seeded := preload("res://core/seeded.gd")

const X_MIN := -12
const X_MAX := 12
const TOP_MAX := 7
const KINDS: Array[String] = ["gap", "stairs", "crates", "spring", "fan", "launcher"]
const RISE := {"gap": 0, "stairs": 3, "crates": 3, "spring": 4, "fan": 4, "launcher": 0}
## Cells of the island the challenge needs at the island's end (stairs / crates / spring / launcher stand there).
const END_CELLS := {"gap": 0, "stairs": 3, "crates": 3, "spring": 1, "fan": 0, "launcher": 1}
const THEMES: Array[String] = ["meadow", "beach", "autumn", "canyon", "candy", "snow", "night", "rainbow", "castle", "volcano"]
const SIDE_Z := [-7, -4]  ## the friend's side island (z), reached by planks at cz -4 and -3


## The course for adventure `adv` (0, 1, 2...) from a seed. Returns a levels.gd level Dictionary.
static func generate(seed_value: int, adv: int, name: String = "") -> Dictionary:
	for attempt in 100:  # later attempts lay the islands out tighter (three long challenges can overrun the table)
		var lv := _try(Seeded.rng(seed_value, "course%d" % attempt), adv, name, attempt >= 40)
		if not lv.is_empty():
			lv["seed"] = seed_value
			return lv
	for k in 200:  # (the tests check this never happens: a small safe course)
		var easy := _try(Seeded.rng(seed_value, "easy%d" % k), 0, name)
		if not easy.is_empty():
			easy["seed"] = seed_value
			easy["fallback"] = true
			return easy
	return {}


static func _try(r: RandomNumberGenerator, adv: int, name: String, tight: bool = false) -> Dictionary:
	var n := 2 if adv < 3 else 3
	var picks: Array = []
	var top := 0
	var last := ""
	for i in n:
		var pool: Array = []
		var w: Array = []
		for k in KINDS:
			if k == last or top + int(RISE[k]) > TOP_MAX:
				continue
			pool.append(k)
			w.append(2.0 if k == "gap" else 1.0)
		var k: String = pool[Seeded.weighted(r, w)]
		picks.append(k)
		top += int(RISE[k])
		last = k
	# Lay the islands out along +X: each one long enough to stand on and for the next challenge's blocks.
	var islands: Array = []  # [x0, x1, top]
	var x := X_MIN + 1
	top = 0
	var gaps: Array = []
	for i in n + 1:
		var nxt: String = picks[i] if i < n else ""
		var room := 3 + int(END_CELLS.get(nxt, 0)) + (r.randi_range(0, 0 if tight else 2) if i > 0 else 1)
		if i == n:
			room = 4
		islands.append([x, x + room, top])
		x += room
		if i < n:
			match nxt:
				"gap":
					var g := r.randi_range(2, 3) if adv < 3 else r.randi_range(3, 4)
					gaps.append(g)
					x += g
				"fan":
					gaps.append(2)
					x += 2
				"launcher":
					gaps.append(7)
					x += 7
				_:
					gaps.append(0)
			top += int(RISE[nxt])
	if x > X_MAX:
		return {}
	# Centre the course on the table.
	var shift := (X_MIN + X_MAX - x - (X_MIN + 1)) / 2
	for isl in islands:
		isl[0] += shift
		isl[1] += shift
	var ground: Array = []
	for isl in islands:
		ground.append([isl[0], isl[1], -2, 3, isl[2]])
	var sol: Array = []
	var path: Array = []
	for i in n:
		var a: int = islands[i][1]
		var t: int = islands[i][2]
		match String(picks[i]):
			"gap":
				for c in int(gaps[i]):
					sol.append(["plank", Vector3i(a + c, t - 1, 0), 0])
				path.append([Vector3(a - 0.6, t, 0.5), ""])
				path.append([Vector3(a + gaps[i] + 1.5, t, 0.5), ""])
			"stairs":
				for c in 3:
					sol.append(["stairs", Vector3i(a - 3 + c, t + c, 0), 0])
				path.append([Vector3(a - 3.6, t, 0.5), ""])
				path.append([Vector3(a + 1.0, t + 3, 0.5), ""])
			"crates":
				for cell in [Vector3i(a - 3, t, 0), Vector3i(a - 2, t, 0), Vector3i(a - 2, t + 1, 0), Vector3i(a - 1, t, 0),
						Vector3i(a - 1, t + 1, 0), Vector3i(a - 1, t + 2, 0)]:
					sol.append(["crate", cell, 0])
				path.append([Vector3(a - 3.8, t, 0.5), ""])
				path.append([Vector3(a - 2.5, t + 1, 0.5), "jump"])
				path.append([Vector3(a - 1.5, t + 2, 0.5), "jump"])
				path.append([Vector3(a - 0.5, t + 3, 0.5), "jump"])
			"spring":
				sol.append(["spring", Vector3i(a - 1, t, 0), 0])
				path.append([Vector3(a - 2.0, t, 0.5), ""])
				path.append([Vector3(a - 0.5, t, 0.5), ""])
				path.append([Vector3(a + 2.0, t + 4, 0.5), ""])
			"fan":
				sol.append(["plank", Vector3i(a, t - 1, 0), 0])
				sol.append(["fan", Vector3i(a + 1, t - 1, 0), 0])
				path.append([Vector3(a + 0.5, t, 0.5), ""])
				path.append([Vector3(a + 1.5, t + 5, 0.5), "rise"])
				path.append([Vector3(a + 4.0, t + 4, 0.5), ""])
			"launcher":
				sol.append(["launcher", Vector3i(a - 1, t, 0), 0])
				path.append([Vector3(a - 2.2, t, 0.5), ""])
				path.append([Vector3(a + 9.5, t, 0.5), ""])
	# The lost friend: a little side island next to one of the later islands, clear of that island's
	# challenge blocks (its end cells), two planks across.
	var fi := r.randi_range(1, n - 1)  # (not the flag island: walking to the friend would touch the flag first)
	var isl: Array = islands[fi]
	var need_end := int(END_CELLS.get(String(picks[fi]) if fi < n else "", 0))
	var lo: int = int(isl[0]) + 1
	var hi: int = int(isl[1]) - need_end - 2
	if hi < lo:
		return {}
	var sx := r.randi_range(lo, hi)
	var ft: int = isl[2]
	ground.append([sx, sx + 2, SIDE_Z[0], SIDE_Z[1], ft])
	var side: Array = [["plank", Vector3i(sx, ft - 1, -4), 0], ["plank", Vector3i(sx, ft - 1, -3), 0]]
	var friend := Vector3(sx + 1.0, ft, -5.5)
	# The detour goes in the bot path right after arriving on that island.
	var arrive := -1
	var want_y := float(ft)
	for k in path.size():
		var p: Vector3 = path[k][0]
		if is_equal_approx(p.y, want_y) and p.x >= float(isl[0]) and p.x <= float(isl[1]):
			arrive = k
			break
	if arrive < 0:
		return {}
	var detour: Array = [[Vector3(sx + 0.5, ft, 0.5), ""], [Vector3(sx + 0.5, ft, -5.5), ""], [Vector3(sx + 0.5, ft, 0.5), ""]]
	for k in detour.size():
		path.insert(arrive + 1 + k, detour[k])
	var start := Vector3(float(islands[0][0]) + 1.5, 0.0, 0.5)
	var last_isl: Array = islands[n]
	var flag := Vector3(float(last_isl[1]) - 2.0, float(last_isl[2]), 0.5)
	path.append([flag, ""])
	var budget := {}
	for s in sol + side:
		budget[s[0]] = int(budget.get(s[0], 0)) + 1
	if adv < 3:
		budget["plank"] = int(budget.get("plank", 0)) + 1  # a spare plank while the team is new to adventures
	return {"name": name if name != "" else "SKY %d" % (adv + 1), "theme": THEMES[r.randi() % THEMES.size()],
		"tip": "", "btip": "", "rtip": "", "time": 999.0, "budget": budget, "ground": ground, "lava": [], "gusts": [],
		"water": [], "start": start, "flag": flag, "solution": side + sol, "bot_path": path, "friend": friend,
		"side": side.size(), "challenges": picks, "adv": adv}


## Is (x, z) at height y standing on something (an island top or a solution block's top)?
static func _support(lv: Dictionary, p: Vector3, blocks: Dictionary) -> bool:
	for g in lv.ground:
		if p.x > float(g[0]) - 0.05 and p.x < float(g[1]) + 0.05 and p.z > float(g[2]) - 0.05 and p.z < float(g[3]) + 0.05 \
				and absf(p.y - float(g[4])) < 0.6:
			return true
	var c := Vector3i(floori(p.x), 0, floori(p.z))
	for dy in [-1, 0, 1]:
		var cy: int = floori(p.y) + int(dy)
		var k := Vector3i(c.x, cy, c.z)
		if blocks.has(k):
			var top := float(cy) + 1.0 if blocks[k] != "spring" else float(cy) + 0.4
			if absf(p.y - top) < 1.05:
				return true
	return false


## The validator: reasons this course is broken (empty when fine).
static func check(lv: Dictionary) -> Array:
	var why: Array = []
	if not lv.has("flag") or not lv.has("ground"):
		return ["no course (%s)" % str(lv.keys())]
	if lv.has("fallback"):
		why.append("fell back to a small course")
	var grounds: Array = lv.get("ground", [])
	for i in grounds.size():
		var g: Array = grounds[i]
		if int(g[0]) < X_MIN - 1 or int(g[1]) > X_MAX + 1 or int(g[4]) > TOP_MAX or int(g[0]) >= int(g[1]):
			why.append("island %d out of bounds %s" % [i, str(g)])
		for j in range(i + 1, grounds.size()):
			var h: Array = grounds[j]
			if int(g[0]) < int(h[1]) and int(h[0]) < int(g[1]) and int(g[2]) < int(h[3]) and int(h[2]) < int(g[3]):
				why.append("islands %d and %d overlap" % [i, j])
	var blocks := {}
	var counts := {}
	for s in lv.get("solution", []):
		var c: Vector3i = s[1]
		var kind := String(s[0])
		counts[kind] = int(counts.get(kind, 0)) + 1
		if blocks.has(c):
			why.append("two blocks in %s" % str(c))
		blocks[c] = kind
		if c.x < -13 or c.x > 12 or c.z < -5 or c.z > 3 or c.y < -4 or c.y > 8:
			why.append("block %s outside the build area" % str(c))
		var lo := float(c.y) + (0.7 if kind == "plank" else 0.0)
		for g in grounds:
			if c.x + 1 > float(g[0]) + 0.01 and c.x < float(g[1]) - 0.01 and c.z + 1 > float(g[2]) + 0.01 and c.z < float(g[3]) - 0.01 \
					and lo < float(g[4]) - 0.01:
				why.append("block %s %s inside an island" % [kind, str(c)])
		for p in [lv.flag, lv.start]:
			var fp: Vector3 = p
			if floori(fp.x) == c.x and floori(fp.z) == c.z and c.y >= floori(fp.y) - 1 and c.y <= floori(fp.y) + 2:
				why.append("block %s on the start / flag" % str(c))
	var budget: Dictionary = lv.get("budget", {})
	for k in counts:
		if int(budget.get(k, 0)) < int(counts[k]):
			why.append("budget %s %d < %d needed" % [k, int(budget.get(k, 0)), int(counts[k])])
	# The bot path: every waypoint stands on something, and walking between two plain waypoints never
	# crosses a hole or a wall (jumps, springs, fans and launch pads are the challenge's own moves).
	var path: Array = lv.get("bot_path", [])
	if path.is_empty():
		why.append("no bot path")
	for k in path.size():
		var p: Vector3 = path[k][0]
		var mode := String(path[k][1])
		if mode != "rise" and not _support(lv, p, blocks):
			why.append("waypoint %d %s stands on nothing" % [k, str(p)])
		if k == 0:
			continue
		var q: Vector3 = path[k - 1][0]
		var flat := absf(p.y - q.y) < 0.01 and mode == ""
		var prev_launch := false
		for s in lv.solution:
			if String(s[0]) == "launcher" and Vector3(s[1]).distance_to(Vector3(q.x, q.y, 0.0)) < 2.6:
				prev_launch = true
		if flat and not prev_launch:
			var steps := int(ceil(q.distance_to(p) / 0.25))
			for st in range(1, steps):
				var m := q.lerp(p, float(st) / float(steps))
				if not _support(lv, m, blocks):
					why.append("a hole between waypoints %d and %d at %s" % [k - 1, k, str(m)])
					break
	var last: Vector3 = path[-1][0] if not path.is_empty() else Vector3.ZERO
	if last.distance_to(lv.flag) > 0.01:
		why.append("the path doesn't end at the flag")
	if not _support(lv, lv.start, blocks):
		why.append("the start floats")
	if lv.has("friend"):
		var f: Vector3 = lv.friend
		if absf(f.y - (lv.flag as Vector3).y) < 0.01 and absf(f.x - (lv.flag as Vector3).x) < 4.0:
			why.append("the friend is by the flag (the level would clear on the way)")
		var seen := false
		for wp in path:
			seen = seen or (wp[0] as Vector3).distance_to(f) < 1.2
		if not seen:
			why.append("the path never reaches the friend")
		if not _support(lv, f, blocks):
			why.append("the friend floats")
	return why
