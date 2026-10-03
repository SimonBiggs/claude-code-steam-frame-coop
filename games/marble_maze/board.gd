extends Node3D
## The tilting maze board. Everything on it lives in board-local coordinates (metres): x to the right,
## z towards the VR player, y up from the floor tiles. The board pivots around its centre.
## Owns the level geometry (one merged mesh for tiles + walls) and the physics queries the marbles use.

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

const PALETTES: Array = [
	[Color(0.98, 0.92, 0.78), Color(0.93, 0.85, 0.68), Color(0.36, 0.62, 1.0)],
	[Color(0.85, 0.96, 0.85), Color(0.76, 0.9, 0.76), Color(1.0, 0.5, 0.35)],
	[Color(0.95, 0.86, 0.98), Color(0.88, 0.78, 0.94), Color(1.0, 0.75, 0.2)],
	[Color(0.84, 0.93, 1.0), Color(0.74, 0.86, 0.97), Color(0.95, 0.35, 0.55)],
	[Color(1.0, 0.94, 0.8), Color(0.96, 0.86, 0.66), Color(0.45, 0.8, 0.4)],
	[Color(0.9, 0.9, 0.95), Color(0.8, 0.8, 0.88), Color(0.6, 0.4, 1.0)],
]

var main
var rows: Array[String] = []
var W := 12
var H := 10
var level_n := 0
var hazard_speed := 1.0
var starts: Array[Vector2] = []
var goal := Vector2.ZERO
var gems: Array[Vector2] = []
var gem_taken: Array[bool] = []
var checkpoints: Array[Vector2] = []
var bumpers: Array[Vector2] = []
var blocks: Array = []  # [centre: Vector2, axis: Vector2, phase: float]
var t := 0.0  # level clock (drives the sliding blocks; mirrored on the TV machine)
var tilt := Vector2.ZERO  # -1..1 each: where the marbles are pushed (x right, y towards the VR player)

var level_root: Node3D
var gem_nodes: Array[Node3D] = []
var bumper_nodes: Array[Node3D] = []
var block_nodes: Array[Node3D] = []
var goal_ring: MeshInstance3D
var handles: Array[MeshInstance3D] = []
var handle_mats: Array[StandardMaterial3D] = []


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
	var src: Array = lv["map"]
	rows.clear()
	for line in src:
		var s: String = line
		if lap % 2 == 1:
			s = s.reverse()
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
	for r in H:
		for c in W:
			var ch := rows[r][c]
			var p := center(c, r)
			match ch:
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
	if starts.is_empty():
		starts.append(center(1, 1))
	_build_level(idx)


func level_name(n: int) -> String:
	var lv: Dictionary = Levels.LEVELS[(n - 1) % Levels.LEVELS.size()]
	return str(lv["name"])


func level_tip(n: int) -> String:
	var lv: Dictionary = Levels.LEVELS[(n - 1) % Levels.LEVELS.size()]
	return str(lv["tip"])


func level_time(n: int) -> float:
	var lv: Dictionary = Levels.LEVELS[(n - 1) % Levels.LEVELS.size()]
	return float(lv["time"])


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


## Holes (and the goal) gently suck in a marble rolling over their lip.
func hole_pull(p: Vector2) -> Vector2:
	var cc := cell_of(p)
	var k := ch(cc.x, cc.y)
	if k != "O" and k != "G":
		return Vector2.ZERO
	var d := center(cc.x, cc.y) - p
	var l := d.length()
	if l < 0.001 or l > 0.55 * CELL:
		return Vector2.ZERO
	return d / l * (0.5 if k == "O" else 0.9)


func in_goal(p: Vector2) -> bool:
	return p.distance_to(goal) < GOAL_R * CELL


func checkpoint_at(p: Vector2) -> int:
	for i in checkpoints.size():
		if p.distance_to(checkpoints[i]) < 0.45 * CELL:
			return i
	return -1


## Push a marble (radius r) out of walls, bumpers and sliding blocks.
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
			if inside and ch(c, rr) != "#":
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


func _build_level(idx: int) -> void:
	if level_root != null:
		level_root.queue_free()
	level_root = Node3D.new()
	add_child(level_root)
	gem_nodes.clear()
	bumper_nodes.clear()
	block_nodes.clear()
	var pal: Array = PALETTES[idx % PALETTES.size()]
	var c_a: Color = pal[0]
	var c_b: Color = pal[1]
	var c_wall: Color = pal[2]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hole_w := 0.72 * CELL
	for r in H:
		for c in W:
			var k := ch(c, r)
			var o := center(c, r)
			var floor_col := c_a if (c + r) % 2 == 0 else c_b
			match k:
				"#":
					var shade := 0.88 + 0.12 * float((c * 7 + r * 3) % 4) / 3.0
					_box(st, Vector3(o.x, (WALL_H - TILE_T) * 0.5, o.y), Vector3(CELL, WALL_H + TILE_T, CELL), c_wall * shade)
					_box(st, Vector3(o.x, WALL_H + 0.003, o.y), Vector3(CELL * 0.98, 0.006, CELL * 0.98), c_wall.lightened(0.35))
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
				_:
					_box(st, Vector3(o.x, -TILE_T * 0.5, o.y), Vector3(CELL, TILE_T, CELL), floor_col)
					if k == "C":
						_box(st, Vector3(o.x, 0.001, o.y), Vector3(CELL * 0.7, 0.002, CELL * 0.7), Color(0.4, 0.85, 1.0))
					elif k == "S":
						_box(st, Vector3(o.x, 0.001, o.y), Vector3(CELL * 0.7, 0.002, CELL * 0.7), Color(1.0, 0.85, 0.3))
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
