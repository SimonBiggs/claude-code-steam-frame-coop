extends Node3D
## The tilting maze board. Everything on it lives in board-local coordinates (metres): x to the right,
## z towards the VR player, y up from the floor tiles. The board pivots around its centre.
## Owns the level geometry (one merged mesh for tiles, walls, the wooden rim and the theme's little
## decorations) and the physics queries the marbles use: walls, holes, bumpers, sliding blocks, team
## gates, ice, mud, zoom arrows, team pads and teleporters.
## Animated bits are MultiMeshes (pad lights, gates, teleporter rings): one draw call each.

const Levels := preload("res://games/marble_maze/levels.gd")

const CELL := 0.1
const WALL_H := 0.045
const TILE_T := 0.025
const HOLE_R := 0.36  # in cells: closer than this to a hole's centre and you drop in
const GOAL_R := 0.34
const BUMPER_R := 0.26
const BLOCK_HALF := 0.45
const MAX_TILT := 0.22  # radians (~12.6 degrees)
const GRAV := 4.0  # board-plane acceleration per radian-ish of tilt (a toy-sized, gentle gravity)
const DAMP := 1.2
const ICE_DAMP := 0.12
const MUD_DAMP := 5.0
const PAD_DAMP := 2.0
const BOOST := 2.2
const PAD_R := 0.45  # in cells
const TP_R := 0.32  # in cells
const GROUP_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(0.75, 0.4, 1.0)]

var main
var rows: Array[String] = []
var W := 12
var H := 10
var level_n := 0
var hazard_speed := 1.0
var theme := "garden"
var starts: Array[Vector2] = []
var goal := Vector2.ZERO
var gems: Array[Vector2] = []
var gem_taken: Array[bool] = []
var checkpoints: Array[Vector2] = []
var bumpers: Array[Vector2] = []
var blocks: Array = []  # [centre: Vector2, axis: Vector2, phase: float]
var pads: Array = []  # [centre: Vector2, group: int]
var pad_on: Array[bool] = []
var gate_cells: Array = []  # [cell: Vector2i, group: int]
var gate_open: Array[bool] = [false, false]
var gate_h: Array[float] = [1.0, 1.0]  # 1 = up (closed), 0 = sunk into the floor
var teleports: Array[Vector2] = []
var tp_dest := {}  # Vector2i cell -> Vector2 partner centre
var goal_dist := {}  # Vector2i -> cells to the goal (for "furthest checkpoint")
var t := 0.0  # level clock (drives the sliding blocks; mirrored on the TV machine)
var tilt := Vector2.ZERO  # -1..1 each: where the marbles are pushed (x right, y towards the VR player)

var level_root: Node3D
var gem_nodes: Array[Node3D] = []
var bumper_nodes: Array[Node3D] = []
var block_nodes: Array[Node3D] = []
var goal_ring: MeshInstance3D
var handles: Array[MeshInstance3D] = []
var handle_mats: Array[StandardMaterial3D] = []
var pad_mm: MultiMesh
var gate_mm: MultiMesh
var tp_mm: MultiMesh


func _ready() -> void:
	_build_frame()


## Level n (1-based): map (n-1) % count, mirrored and faster on every second lap.
func load_level(n: int) -> void:
	level_n = n
	var count: int = Levels.LEVELS.size()
	var idx := (n - 1) % count
	var lap := (n - 1) / count
	hazard_speed = 1.0 + 0.3 * lap
	var lv: Dictionary = Levels.LEVELS[idx]
	theme = str(lv.get("theme", "garden"))
	var src: Array = lv["map"]
	rows.clear()
	for line in src:
		var s: String = line
		if lap % 2 == 1:
			s = s.reverse().replace(">", "{").replace("<", ">").replace("{", "<")
		rows.append(s)
	H = rows.size()
	W = rows[0].length()
	t = 0.0
	starts.clear()
	gems.clear()
	gem_taken.clear()
	checkpoints.clear()
	bumpers.clear()
	blocks.clear()
	pads.clear()
	pad_on.clear()
	gate_cells.clear()
	gate_open = [false, false]
	gate_h = [1.0, 1.0]
	teleports.clear()
	tp_dest.clear()
	for r in H:
		for c in W:
			var k := rows[r][c]
			var p := center(c, r)
			match k:
				"S":
					starts.append(p)
				"G":
					goal = p
				"*":
					gems.append(p)
					gem_taken.append(false)
				"C":
					checkpoints.append(p)
				"B":
					bumpers.append(p)
				"H":
					blocks.append([p, Vector2(1, 0), float(c + r) * 0.9])
				"V":
					blocks.append([p, Vector2(0, 1), float(c * 2 + r) * 0.7])
				"P", "Q":
					pads.append([p, 0 if k == "P" else 1])
					pad_on.append(false)
				"D", "E":
					gate_cells.append([Vector2i(c, r), 0 if k == "D" else 1])
				"T":
					teleports.append(p)
	for i in range(0, teleports.size() - 1, 2):
		tp_dest[cell_of(teleports[i])] = teleports[i + 1]
		tp_dest[cell_of(teleports[i + 1])] = teleports[i]
	if starts.is_empty():
		starts.append(center(1, 1))
	_goal_bfs()
	_build_level(idx)


func level_name(n: int) -> String:
	var lv: Dictionary = Levels.LEVELS[(n - 1) % Levels.LEVELS.size()]
	return str(lv["name"])


func level_tip(n: int) -> String:
	var lv: Dictionary = Levels.LEVELS[(n - 1) % Levels.LEVELS.size()]
	return str(lv["tip"])


## A one-time "NEW: ..." line for a level that brings a new idea ("" if none).
func level_new(n: int) -> String:
	var lv: Dictionary = Levels.LEVELS[(n - 1) % Levels.LEVELS.size()]
	return str(lv.get("new", ""))


func level_time(n: int) -> float:
	var lv: Dictionary = Levels.LEVELS[(n - 1) % Levels.LEVELS.size()]
	return float(lv["time"])


func theme_color(i: int) -> Color:
	var th: Array = Levels.THEMES.get(theme, Levels.THEMES["garden"])
	return th[i]


func has_gates() -> bool:
	return not gate_cells.is_empty()


func group_has_pads(g: int) -> bool:
	for pd in pads:
		if int(pd[1]) == g:
			return true
	return false


# --- Grid helpers --------------------------------------------------------------

func center(c: int, r: int) -> Vector2:
	return Vector2((c - (W - 1) * 0.5) * CELL, (r - (H - 1) * 0.5) * CELL)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floorf(p.x / CELL + W * 0.5)), int(floorf(p.y / CELL + H * 0.5)))


func ch(c: int, r: int) -> String:
	if r < 0 or r >= H or c < 0 or c >= W:
		return "_"
	return rows[r][c]


func half_size() -> Vector2:
	return Vector2(W, H) * CELL * 0.5


## Is this cell a wall right now (walls, and team gates that are still shut)?
func solid(c: int, r: int) -> bool:
	var k := ch(c, r)
	if k == "#":
		return true
	if k == "D":
		return not gate_open[0]
	if k == "E":
		return not gate_open[1]
	return false


## Acceleration along the board from gravity (board-local x/z).
func gravity_local() -> Vector2:
	var g: Vector3 = basis.inverse() * Vector3(0.0, -GRAV, 0.0)
	return Vector2(g.x, g.z)


func tilt_basis(tl: Vector2) -> Basis:
	return Basis.from_euler(Vector3(tl.y * MAX_TILT, 0.0, -tl.x * MAX_TILT))


func block_pos(i: int) -> Vector2:
	var b: Array = blocks[i]
	var c: Vector2 = b[0]
	var axis: Vector2 = b[1]
	var ph: float = b[2]
	return c + axis * sin(t * 1.9 * hazard_speed + ph) * CELL


func block_vel(i: int) -> Vector2:
	var b: Array = blocks[i]
	var axis: Vector2 = b[1]
	var ph: float = b[2]
	return axis * cos(t * 1.9 * hazard_speed + ph) * CELL * 1.9 * hazard_speed


## Is there floor under this point?
func supported(p: Vector2) -> bool:
	var cc := cell_of(p)
	var k := ch(cc.x, cc.y)
	var d := p - center(cc.x, cc.y)
	match k:
		"_":
			return false
		"O":
			return d.length() > HOLE_R * CELL
		"-":
			return absf(d.y) < 0.32 * CELL
		"|":
			return absf(d.x) < 0.32 * CELL
	return true


## Holes (and the goal) gently suck in a marble rolling over their lip; team pads gently hold a
## marble on them so it can wait for its friends.
func hole_pull(p: Vector2) -> Vector2:
	var cc := cell_of(p)
	var k := ch(cc.x, cc.y)
	if k != "O" and k != "G" and k != "P" and k != "Q":
		return Vector2.ZERO
	var d := center(cc.x, cc.y) - p
	var l := d.length()
	if l < 0.001 or l > 0.55 * CELL:
		return Vector2.ZERO
	if k == "P" or k == "Q":
		# Gentle (weaker than a marble's own push, so you can always roll off), and only while the gate is shut.
		if gate_open[0 if k == "P" else 1]:
			return Vector2.ZERO
		return d / l * minf(0.3, l / (0.25 * CELL))
	return d / l * (0.5 if k == "O" else 0.9)


## Floor friction here: ice is slippery, mud is gloopy, pads are a little sticky.
func damp_at(p: Vector2) -> float:
	var cc := cell_of(p)
	match ch(cc.x, cc.y):
		"I":
			return ICE_DAMP
		"M":
			return MUD_DAMP
		"P":
			return DAMP if gate_open[0] else PAD_DAMP
		"Q":
			return DAMP if gate_open[1] else PAD_DAMP
	return DAMP


## How much a marble can steer itself here (hard on ice).
func grip_at(p: Vector2) -> float:
	var cc := cell_of(p)
	var k := ch(cc.x, cc.y)
	if k == "I":
		return 0.35
	if k == "M":
		return 0.8
	return 1.0


## Zoom arrows: a push the way they point.
func boost_at(p: Vector2) -> Vector2:
	var cc := cell_of(p)
	match ch(cc.x, cc.y):
		">":
			return Vector2(BOOST, 0)
		"<":
			return Vector2(-BOOST, 0)
		"^":
			return Vector2(0, -BOOST)
		"v":
			return Vector2(0, BOOST)
	return Vector2.ZERO


func is_mud(p: Vector2) -> bool:
	var cc := cell_of(p)
	return ch(cc.x, cc.y) == "M"


## Standing on a teleporter: where its twin is (Vector2.INF if not on one).
func teleport_dest(p: Vector2) -> Vector2:
	var cc := cell_of(p)
	if not tp_dest.has(cc):
		return Vector2.INF
	if p.distance_to(center(cc.x, cc.y)) > TP_R * CELL:
		return Vector2.INF
	return tp_dest[cc]


func in_goal(p: Vector2) -> bool:
	return p.distance_to(goal) < GOAL_R * CELL


func checkpoint_at(p: Vector2) -> int:
	for i in checkpoints.size():
		if p.distance_to(checkpoints[i]) < 0.45 * CELL:
			return i
	return -1


## Which pad (index into pads) this point sits on, or -1.
func pad_at(p: Vector2) -> int:
	for i in pads.size():
		var pd: Array = pads[i]
		var c: Vector2 = pd[0]
		if p.distance_to(c) < PAD_R * CELL:
			return i
	return -1


## Cells from a checkpoint to the goal (smaller = further along the level).
func checkpoint_dist(i: int) -> int:
	if i < 0 or i >= checkpoints.size():
		return 9999
	return int(goal_dist.get(cell_of(checkpoints[i]), 9999))


func _goal_bfs() -> void:
	goal_dist.clear()
	var g := cell_of(goal)
	goal_dist[g] = 0
	var q: Array[Vector2i] = [g]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var nbs: Array[Vector2i] = [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]
		for nb in nbs:
			var k := ch(nb.x, nb.y)
			if k == "#" or k == "O" or k == "_" or k == "B":
				continue
			if tp_dest.has(nb):
				# Rolling onto a teleporter puts you on its twin: the twin's entry is 2 steps from here.
				var twin := cell_of(tp_dest[nb])
				if not goal_dist.has(twin):
					goal_dist[twin] = int(goal_dist[c]) + 2
					q.append(twin)
				continue
			if goal_dist.has(nb):
				continue
			goal_dist[nb] = int(goal_dist[c]) + 1
			q.append(nb)


## Push a marble (radius r) out of walls, closed gates, bumpers and sliding blocks.
## Returns [pos, vel, impact speed, bumper index or -1].
func collide(p: Vector2, v: Vector2, r: float) -> Array:
	var impact := 0.0
	var bumped := -1
	var cc := cell_of(p)
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var c := cc.x + dc
			var rr := cc.y + dr
			var inside := rr >= 0 and rr < H and c >= 0 and c < W
			if inside and not solid(c, rr):
				continue
			var o := center(c, rr)
			var res := _push_box(p, v, r, o, Vector2(0.5, 0.5) * CELL, Vector2.ZERO, 0.35)
			p = res[0]
			v = res[1]
			impact = maxf(impact, float(res[2]))
	for i in blocks.size():
		var res := _push_box(p, v, r, block_pos(i), Vector2(BLOCK_HALF, BLOCK_HALF) * CELL, block_vel(i), 0.3)
		p = res[0]
		v = res[1]
		impact = maxf(impact, float(res[2]))
	for i in bumpers.size():
		var d := p - bumpers[i]
		var min_d := r + BUMPER_R * CELL
		if d.length() < min_d and d.length() > 0.0001:
			var n := d.normalized()
			p = bumpers[i] + n * min_d
			var vn := v.dot(n)
			if vn < 0.0:
				v -= n * vn * 2.2
			v += n * 0.35
			impact = maxf(impact, 0.6)
			bumped = i
	return [p, v, impact, bumped]


func _push_box(p: Vector2, v: Vector2, r: float, o: Vector2, half: Vector2, box_v: Vector2, bounce: float) -> Array:
	var q := Vector2(clampf(p.x, o.x - half.x, o.x + half.x), clampf(p.y, o.y - half.y, o.y + half.y))
	var d := p - q
	var l := d.length()
	if l >= r:
		return [p, v, 0.0]
	var n := Vector2.ZERO
	if l > 0.00001:
		n = d / l
	else:
		# Centre inside the box: out through the nearest side.
		var e := (p - o) / half
		n = Vector2(signf(e.x), 0.0) if absf(e.x) > absf(e.y) else Vector2(0.0, signf(e.y))
		if n == Vector2.ZERO:
			n = Vector2(0, 1)
		l = 0.0
		q = p
	p = q + n * r if l <= 0.0 else p + n * (r - l)
	var rel := v - box_v
	var vn := rel.dot(n)
	var impact := 0.0
	if vn < 0.0:
		impact = -vn
		rel -= n * vn * (1.0 + bounce)
	v = rel + box_v
	return [p, v, impact]


# --- Visuals -------------------------------------------------------------------

func _process(delta: float) -> void:
	for i in gem_nodes.size():
		var g := gem_nodes[i]
		if not is_instance_valid(g):
			continue
		g.visible = i < gem_taken.size() and not gem_taken[i]
		g.rotation.y += delta * 2.5
		g.position.y = 0.035 + sin(t * 3.0 + i) * 0.008
	for i in mini(block_nodes.size(), blocks.size()):
		var bp := block_pos(i)
		block_nodes[i].position = Vector3(bp.x, WALL_H * 0.5, bp.y)
	for b in bumper_nodes:
		b.scale = b.scale.lerp(Vector3.ONE, 1.0 - exp(-10.0 * delta))
	if goal_ring:
		goal_ring.rotation.y += delta * 1.5
		var s := 1.0 + sin(t * 4.0) * 0.08
		goal_ring.scale = Vector3(s, 1.0, s)
	_update_team_bits(delta)


## Pad lights glow when a marble sits on them; gates sink into the floor once opened; teleporter
## rings spin.
func _update_team_bits(delta: float) -> void:
	if pad_mm != null:
		for i in pads.size():
			var pd: Array = pads[i]
			var c: Vector2 = pd[0]
			var col: Color = GROUP_COLORS[int(pd[1])]
			var on: bool = i < pad_on.size() and pad_on[i]
			var pulse := 1.0 + (0.25 * sin(t * 8.0) if on else 0.0)
			pad_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(pulse, 1.0, pulse)), Vector3(c.x, 0.002, c.y)))
			pad_mm.set_instance_color(i, col.lightened(0.55) if on else col.darkened(0.15))
	if gate_mm != null:
		for g in 2:
			gate_h[g] = move_toward(gate_h[g], 0.0 if gate_open[g] else 1.0, delta * 1.5)
		for i in gate_cells.size():
			var gc: Array = gate_cells[i]
			var cell: Vector2i = gc[0]
			var g: int = gc[1]
			var o := center(cell.x, cell.y)
			var h: float = gate_h[g]
			var y := (WALL_H + TILE_T) * 0.5 - TILE_T - (1.0 - h) * (WALL_H + 0.01)
			gate_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, maxf(h, 0.05), 1.0)), Vector3(o.x, y, o.y)))
	if tp_mm != null:
		for i in teleports.size():
			var c: Vector2 = teleports[i]
			var b := Basis(Vector3.UP, t * 3.0 + i) * Basis.from_scale(Vector3.ONE * (1.0 + 0.12 * sin(t * 5.0 + i)))
			tp_mm.set_instance_transform(i, Transform3D(b, Vector3(c.x, 0.006 + 0.004 * sin(t * 4.0 + i * 2.0), c.y)))


func bump_fx(i: int) -> void:
	if i >= 0 and i < bumper_nodes.size():
		bumper_nodes[i].scale = Vector3(1.4, 0.8, 1.4)


func set_handle_glow(i: int, on: bool) -> void:
	if i < handle_mats.size():
		handle_mats[i].emission_energy_multiplier = 1.6 if on else 0.15


## World positions of the two side handles (0 = left, 1 = right).
func handle_world(i: int) -> Vector3:
	var x := (half_size().x + 0.075) * (-1.0 if i == 0 else 1.0)
	return global_transform * Vector3(x, 0.0, 0.0)


func _build_frame() -> void:
	# Two chunky side handles the VR player grabs (they tilt with the board).
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var col := Color(1.0, 0.35, 0.3) if i == 0 else Color(0.3, 0.55, 1.0)
		var m: StandardMaterial3D = main.make_material(col, 0.15)
		handle_mats.append(m)
		var bar := MeshInstance3D.new()
		bar.mesh = main.cyl_mesh(0.022, 0.022, 0.2, 10)
		bar.material_override = m
		bar.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		bar.position = Vector3(side * (0.6 + 0.075), 0.0, 0.0)
		add_child(bar)
		handles.append(bar)
		for k in 2:
			var arm := MeshInstance3D.new()
			arm.mesh = main.box_mesh(Vector3(0.07, 0.022, 0.022))
			arm.material_override = m
			arm.position = Vector3(side * 0.635, 0.0, -0.08 + 0.16 * k)
			add_child(arm)


## Deterministic little hash for decoration placement (same on both machines).
func _hash(c: int, r: int, salt: int) -> int:
	return absi((c * 73856093) ^ (r * 19349663) ^ (salt * 83492791) ^ level_n * 7919) % 1000


func _build_level(_idx: int) -> void:
	if level_root != null:
		level_root.queue_free()
	level_root = Node3D.new()
	add_child(level_root)
	gem_nodes.clear()
	bumper_nodes.clear()
	block_nodes.clear()
	pad_mm = null
	gate_mm = null
	tp_mm = null
	var c_a := theme_color(0)
	var c_b := theme_color(1)
	var c_wall := theme_color(2)
	var deco: String = Levels.THEMES.get(theme, Levels.THEMES["garden"])[3]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hole_w := 0.72 * CELL
	# A chunky wooden rim round the whole board, under the outer walls.
	var hs := half_size()
	_box(st, Vector3(0, -TILE_T - 0.012, 0), Vector3(hs.x * 2.0 + 0.03, 0.024, hs.y * 2.0 + 0.03), Color(0.62, 0.42, 0.26))
	for r in H:
		for c in W:
			var k := ch(c, r)
			var o := center(c, r)
			var floor_col := c_a if (c + r) % 2 == 0 else c_b
			match k:
				"#":
					var shade := 0.88 + 0.12 * float((c * 7 + r * 3) % 4) / 3.0
					var wc := c_wall * shade
					if deco == "rainbow":
						wc = Color.from_hsv(fmod(float(c + r) * 0.08, 1.0), 0.55, 0.95)
					_box(st, Vector3(o.x, (WALL_H - TILE_T) * 0.5, o.y), Vector3(CELL, WALL_H + TILE_T, CELL), wc)
					var top_col := wc.lightened(0.35)
					if deco == "race":
						top_col = Color(0.95, 0.95, 0.95) if (c + r) % 2 == 0 else Color(0.12, 0.12, 0.14)
					elif deco == "snow":
						top_col = Color(1, 1, 1)
					elif deco == "lava":
						top_col = Color(1.0, 0.45, 0.1) if _hash(c, r, 1) < 300 else wc.lightened(0.2)
					_box(st, Vector3(o.x, WALL_H + 0.003, o.y), Vector3(CELL * 0.98, 0.006, CELL * 0.98), top_col)
					_decorate(st, deco, c, r, o)
				"_":
					pass
				"-":
					_box(st, Vector3(o.x, -0.006, o.y), Vector3(CELL, 0.012, CELL * 0.64), Color(0.72, 0.5, 0.3))
				"|":
					_box(st, Vector3(o.x, -0.006, o.y), Vector3(CELL * 0.64, 0.012, CELL), Color(0.72, 0.5, 0.3))
				"O", "G":
					var rim := (CELL - hole_w) * 0.5
					var tile_col := floor_col if k == "O" else Color(0.55, 1.0, 0.6)
					for s in [-1.0, 1.0]:
						var off: float = s * (hole_w * 0.5 + rim * 0.5)
						_box(st, Vector3(o.x + off, -TILE_T * 0.5, o.y), Vector3(rim, TILE_T, CELL), tile_col)
						_box(st, Vector3(o.x, -TILE_T * 0.5, o.y + off), Vector3(hole_w, TILE_T, rim), tile_col)
					var pit_col := Color(0.05, 0.04, 0.08) if k == "O" else Color(0.2, 0.9, 0.35)
					_box(st, Vector3(o.x, -TILE_T - 0.03, o.y), Vector3(hole_w, 0.01, hole_w), pit_col)
				"D", "E":
					_box(st, Vector3(o.x, -TILE_T * 0.5, o.y), Vector3(CELL, TILE_T, CELL), floor_col.lerp(GROUP_COLORS[0 if k == "D" else 1], 0.3))
				_:
					var fc := floor_col
					match k:
						"I":
							fc = Color(0.8, 0.93, 1.0) if (c + r) % 2 == 0 else Color(0.72, 0.88, 0.98)
						"M":
							fc = Color(0.5, 0.36, 0.22) if (c + r) % 2 == 0 else Color(0.46, 0.33, 0.2)
						">", "<", "^", "v":
							fc = Color(1.0, 0.62, 0.2)
						"P", "Q":
							fc = GROUP_COLORS[0 if k == "P" else 1].darkened(0.35)
						"T":
							fc = Color(0.25, 0.15, 0.4)
					_box(st, Vector3(o.x, -TILE_T * 0.5, o.y), Vector3(CELL, TILE_T, CELL), fc)
					match k:
						"C":
							_box(st, Vector3(o.x, 0.001, o.y), Vector3(CELL * 0.7, 0.002, CELL * 0.7), Color(0.4, 0.85, 1.0))
						"S":
							_box(st, Vector3(o.x, 0.001, o.y), Vector3(CELL * 0.7, 0.002, CELL * 0.7), Color(1.0, 0.85, 0.3))
						"I":
							if _hash(c, r, 2) < 500:
								_box(st, Vector3(o.x + 0.02, 0.001, o.y - 0.015), Vector3(0.025, 0.002, 0.006), Color(1, 1, 1))
						"M":
							_box(st, Vector3(o.x - 0.02, 0.001, o.y + 0.01), Vector3(0.03, 0.002, 0.025), Color(0.36, 0.25, 0.15))
							_box(st, Vector3(o.x + 0.022, 0.001, o.y - 0.02), Vector3(0.02, 0.002, 0.018), Color(0.36, 0.25, 0.15))
						">", "<", "^", "v":
							_chevron(st, k, o)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.55
	mi.material_override = mat
	level_root.add_child(mi)

	var gem_mat: StandardMaterial3D = main.make_material(Color(0.3, 0.95, 1.0), 1.2)
	for g in gems:
		var gn := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.03, 0.035, 0.03)
		gn.mesh = pm
		gn.material_override = gem_mat
		gn.position = Vector3(g.x, 0.035, g.y)
		gn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level_root.add_child(gn)
		gem_nodes.append(gn)
	var bump_mat: StandardMaterial3D = main.make_material(Color(1.0, 0.3, 0.6), 0.6)
	for b in bumpers:
		var bn := MeshInstance3D.new()
		bn.mesh = main.cyl_mesh(BUMPER_R * CELL, BUMPER_R * CELL * 1.1, WALL_H, 14)
		bn.material_override = bump_mat
		var holder := Node3D.new()
		holder.position = Vector3(b.x, 0.0, b.y)
		bn.position = Vector3(0, WALL_H * 0.5, 0)
		holder.add_child(bn)
		var cap := MeshInstance3D.new()
		cap.mesh = main.sphere_mesh(BUMPER_R * CELL * 0.6)
		cap.material_override = main.make_material(Color(1.0, 0.95, 0.4), 1.0)
		cap.position = Vector3(0, WALL_H, 0)
		holder.add_child(cap)
		level_root.add_child(holder)
		bumper_nodes.append(holder)
	var block_mat: StandardMaterial3D = main.make_material(Color(1.0, 0.55, 0.1), 0.3)
	for i in blocks.size():
		var kn := MeshInstance3D.new()
		kn.mesh = main.box_mesh(Vector3(BLOCK_HALF * 2.0 * CELL, WALL_H, BLOCK_HALF * 2.0 * CELL))
		kn.material_override = block_mat
		level_root.add_child(kn)
		block_nodes.append(kn)
	_build_team_bits()
	goal_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.03
	tm.outer_radius = 0.042
	tm.rings = 16
	tm.ring_segments = 6
	goal_ring.mesh = tm
	goal_ring.material_override = main.make_material(Color(0.4, 1.0, 0.5), 2.0)
	goal_ring.position = Vector3(goal.x, 0.006, goal.y)
	goal_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level_root.add_child(goal_ring)
	var flag := MeshInstance3D.new()
	flag.mesh = main.cyl_mesh(0.003, 0.003, 0.12, 6)
	flag.material_override = main.make_material(Color(1, 1, 1), 0.0)
	flag.position = Vector3(goal.x + 0.04, 0.06, goal.y - 0.04)
	level_root.add_child(flag)
	var cloth := MeshInstance3D.new()
	cloth.mesh = main.box_mesh(Vector3(0.05, 0.03, 0.003))
	cloth.material_override = main.make_material(Color(0.3, 1.0, 0.45), 0.8)
	cloth.position = Vector3(goal.x + 0.065, 0.105, goal.y - 0.04)
	level_root.add_child(cloth)


func _unshaded_vertex_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Pad lights, gate blocks and teleporter rings (only built when the level has them).
func _build_team_bits() -> void:
	if not pads.is_empty():
		pad_mm = MultiMesh.new()
		pad_mm.transform_format = MultiMesh.TRANSFORM_3D
		pad_mm.use_colors = true
		var ring := TorusMesh.new()
		ring.inner_radius = 0.026
		ring.outer_radius = 0.038
		ring.rings = 16
		ring.ring_segments = 4
		pad_mm.mesh = ring
		pad_mm.instance_count = pads.size()
		var a := MultiMeshInstance3D.new()
		a.multimesh = pad_mm
		a.material_override = _unshaded_vertex_mat()
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level_root.add_child(a)
	if not gate_cells.is_empty():
		gate_mm = MultiMesh.new()
		gate_mm.transform_format = MultiMesh.TRANSFORM_3D
		gate_mm.use_colors = true
		gate_mm.mesh = main.box_mesh(Vector3(CELL * 0.96, WALL_H + TILE_T, CELL * 0.96))
		gate_mm.instance_count = gate_cells.size()
		for i in gate_cells.size():
			var gc: Array = gate_cells[i]
			gate_mm.set_instance_color(i, GROUP_COLORS[int(gc[1])])
		var b := MultiMeshInstance3D.new()
		b.multimesh = gate_mm
		var gm := StandardMaterial3D.new()
		gm.vertex_color_use_as_albedo = true
		gm.emission_enabled = true
		gm.emission = Color(0.2, 0.2, 0.3)
		b.material_override = gm
		level_root.add_child(b)
	if not teleports.is_empty():
		tp_mm = MultiMesh.new()
		tp_mm.transform_format = MultiMesh.TRANSFORM_3D
		tp_mm.use_colors = true
		var swirl := TorusMesh.new()
		swirl.inner_radius = 0.022
		swirl.outer_radius = 0.034
		swirl.rings = 12
		swirl.ring_segments = 4
		tp_mm.mesh = swirl
		tp_mm.instance_count = teleports.size()
		for i in teleports.size():
			tp_mm.set_instance_color(i, Color(0.85, 0.5, 1.0) if (i / 2) % 2 == 0 else Color(0.4, 1.0, 0.9))
		var c := MultiMeshInstance3D.new()
		c.multimesh = tp_mm
		c.material_override = _unshaded_vertex_mat()
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level_root.add_child(c)
	_update_team_bits(0.0)


## A zoom-arrow chevron painted on the tile.
func _chevron(st: SurfaceTool, k: String, o: Vector2) -> void:
	var dir := Vector2(1, 0)
	match k:
		"<":
			dir = Vector2(-1, 0)
		"^":
			dir = Vector2(0, -1)
		"v":
			dir = Vector2(0, 1)
	var ang := atan2(-dir.y, dir.x)
	for side in [-1.0, 1.0]:
		var b := Basis(Vector3.UP, ang) * Basis(Vector3.UP, side * 0.75)
		var at := Vector3(o.x, 0.002, o.y) + Basis(Vector3.UP, ang) * Vector3(-0.008, 0, side * 0.014)
		_prim(st, main.box_mesh(Vector3(0.045, 0.003, 0.011)), Transform3D(b, at), Color(1.0, 0.97, 0.6))


## Little theme decorations on top of some walls (baked into the level mesh: no extra draw calls).
func _decorate(st: SurfaceTool, deco: String, c: int, r: int, o: Vector2) -> void:
	var h := _hash(c, r, 7)
	var top := WALL_H + 0.006
	var base := Vector3(o.x + (float(h % 7) - 3.0) * 0.004, top, o.y + (float(h % 5) - 2.0) * 0.004)
	var bright: Array[Color] = [Color(1.0, 0.4, 0.45), Color(1.0, 0.85, 0.3), Color(0.5, 0.75, 1.0), Color(0.95, 0.55, 1.0), Color(1.0, 0.6, 0.25)]
	var col: Color = bright[h % bright.size()]
	match deco:
		"flowers":
			if h < 380:
				_prim(st, main.cyl_mesh(0.002, 0.002, 0.02, 4), Transform3D(Basis(), base + Vector3(0, 0.01, 0)), Color(0.3, 0.65, 0.25))
				_prim(st, _small_sphere(), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0) * 0.011), base + Vector3(0, 0.022, 0)), col)
		"shells":
			if h < 260:
				_prim(st, _small_sphere(), Transform3D(Basis.from_scale(Vector3(0.012, 0.005, 0.009)), base), Color(1.0, 0.8, 0.82) if h % 2 == 0 else Color(1.0, 0.96, 0.9))
		"flags":
			if (c + r) % 2 == 0:
				_prim(st, main.box_mesh(Vector3(0.03, 0.012, 0.03)), Transform3D(Basis(), Vector3(o.x, top + 0.006, o.y)), theme_color(2).lightened(0.15))
			if h < 90:
				_prim(st, main.cyl_mesh(0.0015, 0.0015, 0.05, 4), Transform3D(Basis(), base + Vector3(0, 0.025, 0)), Color(0.9, 0.9, 0.9))
				_prim(st, main.box_mesh(Vector3(0.022, 0.014, 0.002)), Transform3D(Basis(), base + Vector3(0.012, 0.043, 0)), col)
		"lollipops":
			if h < 220:
				_prim(st, main.cyl_mesh(0.0015, 0.0015, 0.03, 4), Transform3D(Basis(), base + Vector3(0, 0.015, 0)), Color(1, 1, 1))
				_prim(st, main.cyl_mesh(0.011, 0.011, 0.004, 10), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), base + Vector3(0, 0.036, 0)), col)
		"snow":
			_prim(st, _small_sphere(), Transform3D(Basis.from_scale(Vector3(0.05, 0.008, 0.05)), Vector3(o.x, top, o.y)), Color(1, 1, 1))
		"blocks":
			if h < 300:
				_prim(st, main.box_mesh(Vector3(0.018, 0.018, 0.018)), Transform3D(Basis(Vector3.UP, h * 0.01), base + Vector3(0, 0.009, 0)), col)
				if h < 120:
					_prim(st, main.box_mesh(Vector3(0.014, 0.014, 0.014)), Transform3D(Basis(Vector3.UP, h * 0.03), base + Vector3(0, 0.025, 0)), bright[(h + 1) % bright.size()])
		"cones":
			if h < 150:
				_prim(st, main.cyl_mesh(0.0, 0.009, 0.022, 8), Transform3D(Basis(), base + Vector3(0, 0.011, 0)), Color(1.0, 0.5, 0.1))
		"leaves":
			if h < 420:
				_prim(st, _small_sphere(), Transform3D(Basis.from_scale(Vector3(0.022, 0.014, 0.022)), base + Vector3(0, 0.004, 0)), Color(0.25, 0.55, 0.22) if h % 2 == 0 else Color(0.35, 0.68, 0.28))
		"crystals":
			if h < 260:
				_prim(st, main.cyl_mesh(0.0, 0.007, 0.03, 5), Transform3D(Basis(Vector3.BACK, (h % 5 - 2) * 0.15), base + Vector3(0, 0.015, 0)), Color(0.55, 0.95, 1.0) if h % 2 == 0 else Color(0.95, 0.55, 1.0))
		"grass":
			if h < 400:
				for k in 3:
					_prim(st, main.cyl_mesh(0.0, 0.003, 0.018, 4), Transform3D(Basis(Vector3.BACK, (k - 1) * 0.35), base + Vector3((k - 1) * 0.005, 0.009, 0)), Color(0.4, 0.75, 0.3))
		"lava":
			if h < 120:
				_prim(st, _small_sphere(), Transform3D(Basis.from_scale(Vector3.ONE * 0.008), base + Vector3(0, 0.004, 0)), Color(1.0, 0.75, 0.2))
		"rainbow":
			if h < 160:
				_prim(st, _small_sphere(), Transform3D(Basis.from_scale(Vector3(0.016, 0.01, 0.012)), base + Vector3(0, 0.005, 0)), Color(1, 1, 1))


func _small_sphere() -> SphereMesh:
	if not has_meta("small_sphere"):
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 8
		sm.rings = 4
		set_meta("small_sphere", sm)
	return get_meta("small_sphere")


## Append a primitive mesh (any PrimitiveMesh) with a flat vertex colour.
func _prim(st: SurfaceTool, mesh: Mesh, xf: Transform3D, col: Color) -> void:
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var raw = arr[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	st.set_color(col)
	if raw is PackedInt32Array and not (raw as PackedInt32Array).is_empty():
		for i in (raw as PackedInt32Array):
			st.set_normal((nb * n[i]).normalized())
			st.add_vertex(xf * v[i])
	else:
		for i in v.size():
			st.set_normal((nb * n[i]).normalized())
			st.add_vertex(xf * v[i])


## Append a box (5 faces, no bottom) with a flat vertex colour.
func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces: Array = [
		[Vector3(0, 1, 0), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3(0, 0, 1), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3(0, 0, -1), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3(1, 0, 0), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3(-1, 0, 0), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var shade := 1.0 if n.y > 0.5 else 0.82
		st.set_color(col * shade)
		st.set_normal(n)
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var cc: Vector3 = f[3]
		var d: Vector3 = f[4]
		for v in [a, b, cc, a, cc, d]:
			var vv: Vector3 = v
			st.add_vertex(c + vv)
