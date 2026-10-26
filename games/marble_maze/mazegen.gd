extends RefCounted
## MARBLE MAZE generator: seeded 12 x 10 mazes in the same tile alphabet as levels.gd, so the board,
## the marbles, the bots and the network all treat them like the hand-made levels.
##   const MazeGen := preload("res://games/marble_maze/mazegen.gd")
##   var lv := MazeGen.generate(seed, spec)   # {"name", "theme", "tip", "time", "new", "map", "seed"}
##   var why := MazeGen.check(lv)             # [] when the maze is fair (see below)
## How a maze is made: the 10 x 8 inside is cut into a grid of ROOMS (column / row widths 1-3 cells
## with a wall line between), a seeded depth-first walk joins the rooms into a tree, a few extra doors
## make loops (easier), the start is the top-left corner (far from the VR giant) and the goal sits in
## the room furthest along the tree. Then the spec's features go in, each checked as it is placed:
## ice rooms, zoom-arrow runs ALONG the way to the goal, a teleporter pair (a shortcut, never across a
## team gate), bumpers, holes (never in clusters, never next to the start, the goal or a bumper), two
## team pads before a gate that cuts the maze in two, and one SHINY marble ('*') in the room furthest
## off the way (a detour: grab it or not).
## check() is physics-aware: zoom arrows are one-way (a marble can't roll against one, BOOST beats the
## tilt), rolling onto a teleporter puts you on its twin, shut gates are walls; it proves the start
## reaches every team pad with the gates shut and NOT the goal, that the goal is reached once they
## open, and that no cell you can reach is a trap (from everywhere you can still get to the pads /
## the goal). Plus: the shiny can be reached, arrows never fling you at a hole, the goal is at least a
## few steps away. Pure functions (no nodes): host, TV machine and tests all make the same maze.

const Seeded := preload("res://core/seeded.gd")

const W := 12
const H := 10
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const ARROWS := {">": Vector2i(1, 0), "<": Vector2i(-1, 0), "^": Vector2i(0, -1), "v": Vector2i(0, 1)}
const ALPHABET := "#.SGO*BIPD><^vT"
const MIN_GOAL_STEPS := 7
const TRIES := 40

## The default spec (every key optional): how many of each feature, and room sizes.
const SPEC := {"name": "MAZE", "theme": "garden", "new": "", "holes": 0, "bumpers": 0, "ice": 0, "arrows": 0,
	"tp": false, "pads": false, "shiny": true, "loops": 2, "minw": 2, "maxw": 3, "door": 0.5}


## A fair maze for (seed, spec). Tries several streams; if none passes check() (very rare) it returns
## a plain safe maze with "fallback": true (the generator test keeps that rate at zero).
static func generate(seed_value: int, spec_in: Dictionary) -> Dictionary:
	var spec := SPEC.duplicate()
	spec.merge(spec_in, true)
	for attempt in TRIES:
		var r := Seeded.rng(seed_value, "maze%d" % attempt)
		var rows := _try(r, spec)
		if rows.is_empty():
			continue
		var lv := _level(seed_value, spec, rows)
		if check(lv).is_empty():
			return lv
	var lv2 := _level(seed_value, spec, _plain())
	lv2["fallback"] = true
	return lv2


static func _level(seed_value: int, spec: Dictionary, rows: Array) -> Dictionary:
	return {"name": str(spec.name), "theme": str(spec.theme), "tip": "", "time": 0, "new": str(spec.new),
		"map": rows, "seed": seed_value}


## A wide, plain maze (the first lesson's shape): the safety net.
static func _plain() -> Array:
	return ["############", "#S.........#", "#..........#", "#######....#", "#..........#", "#....*.....#",
		"#....#######", "#..........#", "#.........G#", "############"]


# --- Building ----------------------------------------------------------------------------

static func _try(r: RandomNumberGenerator, spec: Dictionary) -> Array:
	var g: Array = []
	for y in H:
		var row: Array = []
		row.resize(W)
		row.fill("#")
		g.append(row)
	var cw := _partition(r, W - 2, int(spec.minw), int(spec.maxw))
	var rh := _partition(r, H - 2, int(spec.minw), maxi(int(spec.minw), int(spec.maxw) - 1))
	var xs: Array[int] = []
	var x := 1
	for w in cw:
		xs.append(x)
		x += w + 1
	var ys: Array[int] = []
	var y0 := 1
	for h in rh:
		ys.append(y0)
		y0 += h + 1
	var nx := cw.size()
	var ny := rh.size()
	if nx * ny < 4:
		return []
	for j in ny:
		for i in nx:
			for yy in rh[j]:
				for xx in cw[i]:
					g[ys[j] + yy][xs[i] + xx] = "."
	# Room tree: a seeded depth-first walk from the start room.
	var visited := {Vector2i(0, 0): true}
	var parent := {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	var tree: Array = []
	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var opts: Array = []
		for d in DIRS:
			var nb: Vector2i = cur + d
			if nb.x >= 0 and nb.y >= 0 and nb.x < nx and nb.y < ny and not visited.has(nb):
				opts.append(nb)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nxt: Vector2i = opts[r.randi() % opts.size()]
		visited[nxt] = true
		parent[nxt] = cur
		tree.append([cur, nxt])
		stack.append(nxt)
	# Goal room: the furthest along the tree (ties: nearest the VR giant, then rightmost).
	var depth := {Vector2i(0, 0): 0}
	var far := Vector2i(0, 0)
	var order: Array[Vector2i] = [Vector2i(0, 0)]
	var qi := 0
	while qi < order.size():
		var c: Vector2i = order[qi]
		qi += 1
		for e in tree:
			var o: Vector2i = Vector2i(-1, -1)
			if e[0] == c:
				o = e[1]
			elif e[1] == c:
				o = e[0]
			if o.x >= 0 and not depth.has(o):
				depth[o] = int(depth[c]) + 1
				order.append(o)
				var dv: int = depth[o]
				var df: int = depth[far]
				if dv > df or (dv == df and (o.y > far.y or (o.y == far.y and o.x > far.x))):
					far = o
	# The way through the rooms (start room -> goal room).
	var room_path: Array[Vector2i] = [far]
	while room_path[0] != Vector2i(0, 0):
		room_path.insert(0, parent[room_path[0]])
	# Team gate: one door on that way, splitting the rooms into the start side and the goal side.
	var side := {}
	var gate_edge: Array = []
	if bool(spec.pads) and room_path.size() >= 3:
		var k := r.randi_range(1, room_path.size() - 2) if room_path.size() > 3 else 1
		gate_edge = [room_path[k - 1], room_path[k]] if r.randf() < 0.5 or k + 1 >= room_path.size() else [room_path[k], room_path[k + 1]]
		var q: Array[Vector2i] = [Vector2i(0, 0)]
		side[Vector2i(0, 0)] = true
		while not q.is_empty():
			var c: Vector2i = q.pop_front()
			for e in tree:
				if _same_edge(e, gate_edge):
					continue
				var o: Vector2i = e[1] if e[0] == c else (e[0] if e[1] == c else Vector2i(-1, -1))
				if o.x >= 0 and not side.has(o):
					side[o] = true
					q.append(o)
	elif bool(spec.pads):
		return []
	# Extra doors (loops), never across the gate's cut.
	var extra: Array = []
	var cands: Array = []
	for j in ny:
		for i in nx:
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(i, j)
				var b: Vector2i = a + d
				if b.x >= nx or b.y >= ny:
					continue
				var in_tree := false
				for e in tree:
					if _same_edge(e, [a, b]):
						in_tree = true
						break
				if in_tree:
					continue
				if not gate_edge.is_empty() and side.has(a) != side.has(b):
					continue
				cands.append([a, b])
	cands = Seeded.shuffled(r, cands)
	for i in mini(int(spec.loops), cands.size()):
		extra.append(cands[i])
	for e in tree + extra:
		_carve_door(r, g, e, xs, ys, cw, rh, float(spec.door), "D" if _same_edge(e, gate_edge) else ".")
	# Start and goal.
	g[1][1] = "S"
	var gx0: int = xs[far.x]
	var gy0: int = ys[far.y]
	var dist := _walk(g, Vector2i(1, 1), true)
	var best := Vector2i(-1, -1)
	var bd := -1
	for yy in rh[far.y]:
		for xx in cw[far.x]:
			var c := Vector2i(gx0 + xx, gy0 + yy)
			if dist.has(c) and int(dist[c]) > bd:
				bd = int(dist[c])
				best = c
	if best.x < 0 or bd < MIN_GOAL_STEPS:
		return []
	g[best.y][best.x] = "G"
	# The rooms (as cell lists) for placing features.
	var rooms: Array = []
	for j in ny:
		for i in nx:
			var cells: Array[Vector2i] = []
			for yy in rh[j]:
				for xx in cw[i]:
					cells.append(Vector2i(xs[i] + xx, ys[j] + yy))
			rooms.append({"id": Vector2i(i, j), "cells": cells, "start_side": gate_edge.is_empty() or side.has(Vector2i(i, j))})
	if not _place_ice(r, g, rooms, int(spec.ice)):
		return []
	_place_arrows(r, g, int(spec.arrows))
	if bool(spec.tp) and not _place_teleporters(r, g, rooms):
		return []
	if int(spec.bumpers) > 0:
		_scatter(r, g, "B", int(spec.bumpers), bool(spec.get("ice_holes", false)))
	if int(spec.holes) > 0:
		_scatter(r, g, "O", int(spec.holes), bool(spec.get("ice_holes", false)))
	if bool(spec.pads) and not _place_pads(r, g, rooms):
		return []
	if bool(spec.shiny):
		_place_shiny(g)
	var out: Array = []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	return out


static func _same_edge(e: Array, f: Array) -> bool:
	if f.is_empty():
		return false
	return (e[0] == f[0] and e[1] == f[1]) or (e[0] == f[1] and e[1] == f[0])


## Column (or row) widths in [minw, maxw] that, with one wall cell between each, fill `total` exactly.
static func _partition(r: RandomNumberGenerator, total: int, minw: int, maxw: int) -> Array[int]:
	for i in 80:
		var ws: Array[int] = []
		var s := 0
		while true:
			var w := r.randi_range(minw, maxw)
			var need := s + (1 if ws.size() > 0 else 0) + w
			if need == total:
				ws.append(w)
				return ws
			if need > total:
				break
			ws.append(w)
			s = need
	var out: Array[int] = []
	var left := total
	while left > 0:
		var w2 := mini(left, 2)
		out.append(w2)
		left -= w2 + 1
	return out


## Open the wall between two neighbouring rooms: a door `door` (0..1) of the shared side wide (at
## least one cell), at a random place along it.
static func _carve_door(r: RandomNumberGenerator, g: Array, e: Array, xs: Array[int], ys: Array[int], cw: Array[int],
		rh: Array[int], door: float, ch: String) -> void:
	var a: Vector2i = e[0]
	var b: Vector2i = e[1]
	if a.x > b.x or a.y > b.y:
		var t := a
		a = b
		b = t
	var length: int
	var cells: Array[Vector2i] = []
	if a.y == b.y:
		var sx: int = xs[a.x] + cw[a.x]
		length = rh[a.y]
		for k in length:
			cells.append(Vector2i(sx, ys[a.y] + k))
	else:
		var sy: int = ys[a.y] + rh[a.y]
		length = cw[a.x]
		for k in length:
			cells.append(Vector2i(xs[a.x] + k, sy))
	var n := clampi(int(round(length * door)), 1, length)
	if ch == "D":
		n = mini(n, 2)
	var off := r.randi_range(0, length - n)
	for k in n:
		var c: Vector2i = cells[off + k]
		g[c.y][c.x] = ch


static func _place_ice(r: RandomNumberGenerator, g: Array, rooms: Array, count: int) -> bool:
	if count <= 0:
		return true
	var pool: Array = []
	for rm in rooms:
		var has_sg := false
		for c in rm.cells:
			if g[c.y][c.x] != ".":
				has_sg = true
		if not has_sg and (rm.cells as Array).size() >= 2:
			pool.append(rm)
	pool = Seeded.shuffled(r, pool)
	var done := 0
	for rm in pool:
		if done >= count:
			break
		for c in rm.cells:
			g[c.y][c.x] = "I"
		done += 1
	return done > 0


## Zoom arrows on straight stretches of the way to the goal, pointing along it.
static func _place_arrows(r: RandomNumberGenerator, g: Array, runs: int) -> void:
	if runs <= 0:
		return
	var path := _path(g)
	if path.size() < 4:
		return
	var segs: Array = []  # [start index, length, dir]
	var i := 1
	while i < path.size() - 1:
		var d: Vector2i = path[i + 1] - path[i]
		var j := i
		while j + 1 < path.size() and path[j + 1] - path[j] == d:
			j += 1
		if j - i >= 2:
			segs.append([i, j - i, d])
		i = maxi(j, i + 1)
	segs = Seeded.shuffled(r, segs)
	var placed := 0
	for s in segs:
		if placed >= runs:
			break
		var st: int = s[0]
		var n: int = mini(int(s[1]), r.randi_range(2, 4))
		var d2: Vector2i = s[2]
		var ch := ""
		for k in ARROWS:
			if ARROWS[k] == d2:
				ch = k
		var backup := _copy(g)
		var ok := true
		for k in n:
			var c: Vector2i = path[st + k]
			if g[c.y][c.x] != "." and g[c.y][c.x] != "I":
				ok = false
				break
			g[c.y][c.x] = ch
		if ok and _fair(g):
			placed += 1
		else:
			_restore(g, backup)


## A teleporter pair: one early off the way (or on it), its twin later on, both on the start side
## of any team gate.
static func _place_teleporters(r: RandomNumberGenerator, g: Array, rooms: Array) -> bool:
	var path := _path(g)
	if path.size() < 8:
		return false
	var on_side := {}
	for rm in rooms:
		if rm.start_side:
			for c in rm.cells:
				on_side[c] = true
	var early: Array[Vector2i] = []
	var late: Array = []  # [goal steps, cell]
	var reach := _walk(g, Vector2i(1, 1), false)
	for c in reach:
		var cc: Vector2i = c
		if g[cc.y][cc.x] != "." or not on_side.has(cc) or _near(g, cc, "SG", false):
			continue
		var pi := path.find(cc)
		var gd := _goal_steps(g, cc)
		if gd < 0:
			continue
		if int(reach[cc]) <= 5 and gd >= 8:
			early.append(cc)
		elif gd >= 2 and pi < 0:
			late.append([gd, cc])
	if early.is_empty() or late.is_empty():
		return false
	late.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and (a[1] as Vector2i) < (b[1] as Vector2i)))  # nearest the goal first; keep the closest third
	late = late.slice(0, maxi(1, late.size() / 3))
	for tries in 12:
		var a: Vector2i = early[r.randi() % early.size()]
		var b: Vector2i = late[r.randi() % late.size()][1]
		if absi(a.x - b.x) + absi(a.y - b.y) < 4:
			continue
		g[a.y][a.x] = "T"
		g[b.y][b.x] = "T"
		if _fair(g):
			return true
		g[a.y][a.x] = "."
		g[b.y][b.x] = "."
	return false


## Bumpers or holes, one at a time, each kept only if the maze stays fair.
static func _scatter(r: RandomNumberGenerator, g: Array, ch: String, count: int, on_ice: bool) -> void:
	var cells: Array = []
	for y in H:
		for x in W:
			var k: String = g[y][x]
			if k == "." or (on_ice and k == "I" and ch == "O"):
				cells.append(Vector2i(x, y))
	cells = Seeded.shuffled(r, cells)
	var placed := 0
	for c in cells:
		if placed >= count:
			break
		var cc: Vector2i = c
		if _near(g, cc, "SGTOB", true) or _arrow_lands(g, cc):
			continue
		if ch == "B" and _near(g, cc, "D", false):
			continue
		var old: String = g[cc.y][cc.x]
		g[cc.y][cc.x] = ch
		if _fair(g):
			placed += 1
		else:
			g[cc.y][cc.x] = old


## Two team pads on the start side, apart from each other, not by holes.
static func _place_pads(r: RandomNumberGenerator, g: Array, rooms: Array) -> bool:
	var reach := _walk(g, Vector2i(1, 1), false)
	var cells: Array = []
	for c in reach:
		var cc: Vector2i = c
		if g[cc.y][cc.x] == "." and not _near(g, cc, "SOBTD", true):
			cells.append(cc)
	cells = Seeded.shuffled(r, cells)
	for a in cells:
		for b in cells:
			var ca: Vector2i = a
			var cb: Vector2i = b
			if absi(ca.x - cb.x) + absi(ca.y - cb.y) < 3:
				continue
			g[ca.y][ca.x] = "P"
			g[cb.y][cb.x] = "P"
			if check({"map": _rows(g)}).is_empty():
				return true
			g[ca.y][ca.x] = "."
			g[cb.y][cb.x] = "."
	return false


## The shiny marble: the reachable plain cell furthest off the way to the goal (a detour).
static func _place_shiny(g: Array) -> void:
	var path := _path(g)
	if path.is_empty():
		return
	var from_path := _walk_multi(g, path, true)
	var best := Vector2i(-1, -1)
	var bd := -1
	for c in from_path:
		var cc: Vector2i = c
		if g[cc.y][cc.x] != "." or _near(g, cc, "SGT", false):
			continue
		var d: int = from_path[cc]
		if d > bd or (d == bd and (cc.y < best.y or (cc.y == best.y and cc.x < best.x))):
			bd = d
			best = cc
	if best.x >= 0:
		g[best.y][best.x] = "*"


# --- Grid helpers --------------------------------------------------------------------------

static func _copy(g: Array) -> Array:
	var out: Array = []
	for row in g:
		out.append((row as Array).duplicate())
	return out


static func _restore(g: Array, from: Array) -> void:
	for y in H:
		g[y] = (from[y] as Array).duplicate()


static func _rows(g: Array) -> Array:
	var out: Array = []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	return out


static func _at(g: Array, c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return "#"
	return str(g[c.y][c.x])


## Is any of `chars` next to c (4 neighbours, or all 8 when `diag`)?
static func _near(g: Array, c: Vector2i, chars: String, diag: bool) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx == 0 and dy == 0) or (not diag and dx != 0 and dy != 0):
				continue
			if chars.contains(_at(g, c + Vector2i(dx, dy))):
				return true
	return false


## Would a hole / bumper at c be where a zoom arrow flings you (the two cells after an arrow)?
static func _arrow_lands(g: Array, c: Vector2i) -> bool:
	for k in ARROWS:
		var d: Vector2i = ARROWS[k]
		if _at(g, c - d) == k or _at(g, c - d * 2) == k:
			return true
	return false


static func _fair(g: Array) -> bool:
	return check({"map": _rows(g)}, true).is_empty()


## The shortest way from the start to the goal (gates open), as cells; [] if there is none.
static func _path(g: Array) -> Array:
	var s := _find(g, "S")
	var gl := _find(g, "G")
	if s.x < 0 or gl.x < 0:
		return []
	var prev := {s: s}
	var q: Array[Vector2i] = [s]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == gl:
			break
		for nb in _moves(g, c, true):
			if not prev.has(nb):
				prev[nb] = c
				q.append(nb)
	if not prev.has(gl):
		return []
	var out: Array = [gl]
	while out[0] != s:
		out.insert(0, prev[out[0]])
	return out


## Steps from every cell reachable from `from` (BFS over the one-way moves).
static func _walk(g: Array, from: Vector2i, open: bool) -> Dictionary:
	return _walk_multi(g, [from], open)


static func _walk_multi(g: Array, froms: Array, open: bool) -> Dictionary:
	var dist := {}
	var q: Array[Vector2i] = []
	for f in froms:
		dist[f] = 0
		q.append(f)
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for nb in _moves(g, c, open):
			if not dist.has(nb):
				dist[nb] = int(dist[c]) + 1
				q.append(nb)
	return dist


static func _goal_steps(g: Array, c: Vector2i) -> int:
	var path_d := _walk(g, c, true)
	var gl := _find(g, "G")
	return int(path_d.get(gl, -1))


static func _find(g: Array, ch: String) -> Vector2i:
	for y in H:
		for x in W:
			if g[y][x] == ch:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _passable(k: String, open: bool) -> bool:
	if k == "D":
		return open
	return not "#OB_".contains(k)


## Where a marble at c can get to next: four ways, except back against a zoom arrow (leaving one or
## entering one); rolling onto a teleporter lands you on its twin.
static func _moves(g: Array, c: Vector2i, open: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var kc := _at(g, c)
	for d in DIRS:
		if ARROWS.has(kc) and ARROWS[kc] == -d:
			continue
		var b: Vector2i = c + d
		var kb := _at(g, b)
		if not _passable(kb, open):
			continue
		if ARROWS.has(kb) and ARROWS[kb] == -d:
			continue
		if kb == "T":
			var tw := _twin(g, b)
			if tw.x >= 0:
				b = tw
		out.append(b)
	return out


static func _twin(g: Array, c: Vector2i) -> Vector2i:
	var ts: Array[Vector2i] = []
	for y in H:
		for x in W:
			if g[y][x] == "T":
				ts.append(Vector2i(x, y))
	var i := ts.find(c)
	if i < 0:
		return Vector2i(-1, -1)
	var j := i + 1 if i % 2 == 0 else i - 1
	return ts[j] if j < ts.size() else Vector2i(-1, -1)


## Cells that can reach any of `targets` (reverse BFS over the one-way moves).
static func _coreach(g: Array, targets: Array, open: bool) -> Dictionary:
	var back := {}
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if not _passable(_at(g, c), open):
				continue
			for nb in _moves(g, c, open):
				if not back.has(nb):
					back[nb] = []
				(back[nb] as Array).append(c)
	var seen := {}
	var q: Array[Vector2i] = []
	for t in targets:
		seen[t] = true
		q.append(t)
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for p in back.get(c, []):
			if not seen.has(p):
				seen[p] = true
				q.append(p)
	return seen


# --- The validator --------------------------------------------------------------------------

## Reasons this maze is unfair ([] = fine). `partial`: a maze still being built (no goal-distance or
## pad-count rules yet, just "nothing breaks").
static func check(lv: Dictionary, partial: bool = false) -> Array:
	var why: Array = []
	var rows: Array = lv.get("map", [])
	if rows.size() != H:
		return ["map has %d rows" % rows.size()]
	var g: Array = []
	for y in H:
		var s := str(rows[y])
		if s.length() != W:
			return ["row %d is %d long" % [y, s.length()]]
		var row: Array = []
		for x in W:
			var k := s[x]
			if not ALPHABET.contains(k):
				why.append("unknown tile '%s' at %d,%d" % [k, x, y])
			if (x == 0 or y == 0 or x == W - 1 or y == H - 1) and k != "#":
				why.append("border open at %d,%d" % [x, y])
			row.append(k)
		g.append(row)
	var counts := {}
	for y in H:
		for x in W:
			counts[g[y][x]] = int(counts.get(g[y][x], 0)) + 1
	if int(counts.get("S", 0)) != 1 or int(counts.get("G", 0)) != 1:
		why.append("needs one start and one goal")
		return why
	if int(counts.get("T", 0)) % 2 == 1:
		why.append("teleporter without a twin")
	if int(counts.get("*", 0)) > 1:
		why.append("more than one shiny")
	var pads: Array = []
	for y in H:
		for x in W:
			if g[y][x] == "P":
				pads.append(Vector2i(x, y))
	var has_gate := int(counts.get("D", 0)) > 0
	if not partial and pads.is_empty() != (not has_gate):
		why.append("team pads and gates must come together")
	var s := _find(g, "S")
	var gl := _find(g, "G")
	var opened := _walk(g, s, true)
	if not opened.has(gl):
		why.append("the goal can't be reached")
		return why
	if not partial and int(opened[gl]) < MIN_GOAL_STEPS:
		why.append("the goal is too close (%d steps)" % int(opened[gl]))
	var co := _coreach(g, [gl], true)
	for c in opened:
		if not co.has(c):
			why.append("trap at %s: the goal can't be reached from there" % str(c))
			break
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var k: String = g[y][x]
			if k == "*" and not opened.has(c):
				why.append("the shiny can't be reached")
			if k == "O":
				if _near(g, c, "SG", false):
					why.append("hole next to the start or goal at %s" % str(c))
				if _near(g, c, "O", true):
					why.append("holes in a cluster at %s" % str(c))
				if _near(g, c, "B", false):
					why.append("bumper flings into the hole at %s" % str(c))
			if ARROWS.has(k):
				var d: Vector2i = ARROWS[k]
				if _at(g, c + d) == "O" or _at(g, c + d * 2) == "O":
					why.append("zoom arrow flings into a hole at %s" % str(c))
	if has_gate and not pads.is_empty():
		var shut := _walk(g, s, false)
		for p in pads:
			if not shut.has(p):
				why.append("team pad %s is behind its gate" % str(p))
		if shut.has(gl):
			why.append("the goal can be reached without the gate")
		var to_pads := _coreach(g, pads, false)
		for c in shut:
			if not to_pads.has(c):
				why.append("trap at %s before the gate" % str(c))
				break
	return why


## Features in a map (for tests and telemetry): tile -> count.
static func features(lv: Dictionary) -> Dictionary:
	var out := {}
	for row in lv.get("map", []):
		for k in str(row):
			if "OBIPD><^vT*".contains(k):
				out[k] = int(out.get(k, 0)) + 1
	return out
