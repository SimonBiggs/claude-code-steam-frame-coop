extends Node3D
## The floating obstacle course: static islands, lava, wind gusts, rising water, the flag, and the
## blocks the builder has placed. Also the collision queries the runners use (simple column spans,
## no physics engine): every solid is a vertical span [bottom, top] over an area of the XZ plane.
## Built the same way on the host and on the TV (deterministic from the level index); blocks arrive
## in snapshots on the TV.

const Art := preload("res://games/block_builders/art.gd")
const Levels := preload("res://games/block_builders/levels.gd")

const MIN_X := -13
const MAX_X := 12
const MIN_Z := -5
const MAX_Z := 3
const MIN_Y := -4
const MAX_Y := 8
const KILL_Y := -7.0
const FAN_LIFT := 5.5
const SPRING_TOP := 0.55
const FAN_TOP := 0.45

var main
var level_index := -1
var data: Dictionary = {}
var grounds: Array = []   # [x0, x1, z0, z1, top, bottom]
var lavas: Array = []     # [x0, x1, z0, z1, top]
var gusts: Array = []
var water: Array = []
var start := Vector3.ZERO
var flag_pos := Vector3.ZERO
var blocks := {}          # Vector3i -> [kind, rot, node]
var columns := {}         # Vector2i -> Array of cy
var level_root: Node3D
var water_node: MeshInstance3D
var water_mat: StandardMaterial3D
var gust_fx: Array = []
var flag_cloth: MeshInstance3D
var flag_ring: MeshInstance3D
var anim_t := 0.0
var lava_mat: StandardMaterial3D


func _ready() -> void:
	name = "Course"
	_build_decor()


## (Re)build the static part of level i and clear all blocks.
func load_level(i: int) -> void:
	level_index = i
	data = Levels.get_level(i)
	for key in blocks.keys():
		var b: Array = blocks[key]
		var n: Node3D = b[2]
		if is_instance_valid(n):
			n.queue_free()
	blocks.clear()
	columns.clear()
	if level_root != null and is_instance_valid(level_root):
		level_root.queue_free()
	level_root = Node3D.new()
	level_root.name = "Level"
	add_child(level_root)
	gust_fx.clear()
	grounds.clear()
	lavas.clear()
	start = data.start
	flag_pos = data.flag
	gusts = data.gusts
	water = data.water
	var grass_cols: Array[Color] = [Color(0.45, 0.85, 0.35), Color(0.5, 0.9, 0.45), Color(0.4, 0.8, 0.4)]
	var gi := 0
	for g in data.ground:
		var x0: float = g[0]
		var x1: float = g[1]
		var z0: float = g[2]
		var z1: float = g[3]
		var top: float = g[4]
		var bottom := top - 1.0
		grounds.append([x0, x1, z0, z1, top, bottom])
		var mi := MeshInstance3D.new()
		mi.mesh = Art.island_mesh(x0, x1, z0, z1, top, bottom, grass_cols[gi % grass_cols.size()])
		level_root.add_child(mi)
		gi += 1
	if lava_mat == null:
		lava_mat = Art.mat(Color(1.0, 0.4, 0.05), 2.2, 0.4)
	for l in data.lava:
		var x0: float = l[0]
		var x1: float = l[1]
		var z0: float = l[2]
		var z1: float = l[3]
		var top: float = l[4]
		lavas.append([x0, x1, z0, z1, top])
		var mi := MeshInstance3D.new()
		mi.mesh = Art.lava_mesh(x0, x1, z0, z1, top)
		mi.material_override = lava_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level_root.add_child(mi)
		var bubbles := CPUParticles3D.new()
		bubbles.amount = 10
		bubbles.lifetime = 1.0
		bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		bubbles.emission_box_extents = Vector3((x1 - x0) * 0.5, 0.05, (z1 - z0) * 0.5)
		bubbles.direction = Vector3.UP
		bubbles.spread = 15.0
		bubbles.initial_velocity_min = 0.6
		bubbles.initial_velocity_max = 1.4
		bubbles.gravity = Vector3(0, -1.0, 0)
		bubbles.scale_amount_min = 0.5
		bubbles.scale_amount_max = 1.0
		var bm := Art.sphere(0.09, 6)
		bm.material = Art.mat(Color(1.0, 0.75, 0.2), 3.0)
		bubbles.mesh = bm
		bubbles.position = Vector3((x0 + x1) * 0.5, top + 0.05, (z0 + z1) * 0.5)
		level_root.add_child(bubbles)
	for g in gusts:
		var fx := CPUParticles3D.new()
		var x0: float = g[0]
		var x1: float = g[1]
		var z0: float = g[2]
		var z1: float = g[3]
		var y0: float = g[4]
		var y1: float = g[5]
		var push := Vector3(g[6], 0.0, g[7])
		fx.amount = 36
		fx.lifetime = 0.9
		fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		fx.emission_box_extents = Vector3((x1 - x0) * 0.5, (y1 - y0) * 0.5, 0.3)
		fx.direction = push.normalized()
		fx.spread = 4.0
		fx.initial_velocity_min = 8.0
		fx.initial_velocity_max = 11.0
		fx.gravity = Vector3.ZERO
		var sm := Art.box(Vector3(0.05, 0.05, 0.9))
		var wm := Art.mat(Color(0.9, 0.97, 1.0, 0.7), 1.0)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.material = wm
		fx.mesh = sm
		fx.particle_flag_align_y = false
		var upwind := z0 if push.z > 0.0 else z1
		fx.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, upwind)
		fx.emitting = false
		level_root.add_child(fx)
		gust_fx.append(fx)
	_build_flag()
	_build_start_pad()
	_build_water()


func _build_flag() -> void:
	var base := MeshInstance3D.new()
	base.mesh = Art.cyl(0.55, 0.6, 0.08, 16)
	base.material_override = Art.mat(Color(1.0, 1.0, 1.0))
	base.position = flag_pos + Vector3(0, 0.04, 0)
	level_root.add_child(base)
	var pole := MeshInstance3D.new()
	pole.mesh = Art.cyl(0.05, 0.05, 2.2, 8)
	pole.material_override = Art.mat(Color(0.95, 0.95, 0.95), 0.0, 0.3)
	pole.position = flag_pos + Vector3(0, 1.1, 0)
	level_root.add_child(pole)
	var ball := MeshInstance3D.new()
	ball.mesh = Art.sphere(0.12, 10)
	ball.material_override = Art.mat(Color(1.0, 0.85, 0.2), 2.0)
	ball.position = flag_pos + Vector3(0, 2.25, 0)
	level_root.add_child(ball)
	flag_cloth = MeshInstance3D.new()
	flag_cloth.mesh = Art.box(Vector3(0.9, 0.55, 0.04))
	flag_cloth.material_override = Art.mat(Color(1.0, 0.25, 0.3), 0.6)
	flag_cloth.position = flag_pos + Vector3(0.47, 1.9, 0)
	level_root.add_child(flag_cloth)
	flag_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.1
	tm.rings = 24
	tm.ring_segments = 6
	flag_ring.mesh = tm
	flag_ring.material_override = Art.mat(Color(1.0, 0.9, 0.3), 2.0)
	flag_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flag_ring.position = flag_pos + Vector3(0, 0.1, 0)
	level_root.add_child(flag_ring)


func _build_start_pad() -> void:
	var pad := MeshInstance3D.new()
	pad.mesh = Art.cyl(0.9, 0.9, 0.05, 16)
	pad.material_override = Art.mat(Color(0.4, 0.9, 1.0), 0.8)
	pad.position = start + Vector3(0, 0.03, 0)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level_root.add_child(pad)


func _build_water() -> void:
	water_node = null
	if water.is_empty():
		return
	water_node = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 14)
	water_node.mesh = pm
	water_mat = Art.mat(Color(0.2, 0.55, 1.0, 0.6), 0.3, 0.1)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_node.material_override = water_mat
	water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_node.position = Vector3(-1.0, -50.0, 0.0)
	level_root.add_child(water_node)


## Clouds drifting around and below the course, for the "floating in the sky" feel. Built once.
func _build_decor() -> void:
	var cloud_mat := Art.mat(Color(1.0, 1.0, 1.0), 0.15, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 7:
		var c := Node3D.new()
		c.position = Vector3(rng.randf_range(-16, 16), rng.randf_range(-9, -4), rng.randf_range(-12, -4) if i % 2 == 0 else rng.randf_range(-12, 2))
		add_child(c)
		for j in 3:
			var puff := MeshInstance3D.new()
			puff.mesh = Art.sphere(rng.randf_range(1.0, 1.8), 12)
			puff.material_override = cloud_mat
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			puff.position = Vector3(j * 1.6 - 1.6, rng.randf_range(-0.3, 0.3), rng.randf_range(-0.5, 0.5))
			puff.scale = Vector3(1.0, 0.65, 1.0)
			c.add_child(puff)


# --- Blocks --------------------------------------------------------------------

func has_block(cell: Vector3i) -> bool:
	return blocks.has(cell)


func block_kind(cell: Vector3i) -> String:
	if not blocks.has(cell):
		return ""
	var b: Array = blocks[cell]
	return b[0]


func block_rot(cell: Vector3i) -> int:
	if not blocks.has(cell):
		return 0
	var b: Array = blocks[cell]
	return int(b[1])


func add_block(kind: String, cell: Vector3i, rot: int, pop: bool = true) -> void:
	if blocks.has(cell):
		remove_block(cell)
	var n := Node3D.new()
	n.position = Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)
	n.rotation.y = -rot * PI * 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = Art.block_mesh(kind)
	n.add_child(mi)
	if kind == "fan":
		var blades := MeshInstance3D.new()
		blades.name = "Blades"
		blades.mesh = Art.fan_blades_mesh()
		blades.position.y = FAN_TOP + 0.02
		n.add_child(blades)
		var air := CPUParticles3D.new()
		air.amount = 10
		air.lifetime = 1.2
		air.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		air.emission_box_extents = Vector3(0.35, 0.05, 0.35)
		air.direction = Vector3.UP
		air.spread = 5.0
		air.initial_velocity_min = 3.5
		air.initial_velocity_max = 5.0
		air.gravity = Vector3.ZERO
		var am := Art.box(Vector3(0.04, 0.4, 0.04))
		var amat := Art.mat(Color(0.85, 0.9, 1.0, 0.6), 1.2)
		amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		am.material = amat
		air.mesh = am
		air.position.y = FAN_TOP + 0.1
		n.add_child(air)
	add_child(n)
	if pop:
		n.scale = Vector3.ONE * 0.3
		var t := n.create_tween()
		t.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	blocks[cell] = [kind, rot, n]
	var col := Vector2i(cell.x, cell.z)
	var layers: Array = columns.get(col, [])
	if not layers.has(cell.y):
		layers.append(cell.y)
	columns[col] = layers


func remove_block(cell: Vector3i) -> void:
	if not blocks.has(cell):
		return
	var b: Array = blocks[cell]
	var n: Node3D = b[2]
	if is_instance_valid(n):
		n.queue_free()
	blocks.erase(cell)
	var col := Vector2i(cell.x, cell.z)
	var layers: Array = columns.get(col, [])
	layers.erase(cell.y)
	if layers.is_empty():
		columns.erase(col)


func clear_blocks() -> void:
	for key in blocks.keys():
		remove_block(key)


## Snapshot form: flat ints [x, y, z, kind, rot, ...].
func pack_blocks() -> PackedInt32Array:
	var out := PackedInt32Array()
	for key in blocks.keys():
		var c: Vector3i = key
		var b: Array = blocks[key]
		out.append_array([c.x, c.y, c.z, Art.kind_index(b[0]), int(b[1])])
	return out


func apply_packed(p: PackedInt32Array) -> void:
	var seen := {}
	var i := 0
	while i + 4 < p.size():
		var c := Vector3i(p[i], p[i + 1], p[i + 2])
		var kind: String = Art.KINDS[clampi(p[i + 3], 0, Art.KINDS.size() - 1)]
		var rot := p[i + 4]
		seen[c] = true
		if not blocks.has(c) or block_kind(c) != kind or int(blocks[c][1]) != rot:
			add_block(kind, c, rot)
		i += 5
	for key in blocks.keys():
		if not seen.has(key):
			remove_block(key)


# --- Collision queries -----------------------------------------------------------

## Vertical extent of a block at a point (the point is clamped into the cell for ramps).
func block_span(kind: String, rot: int, c: Vector3i, px: float, pz: float) -> Vector2:
	var y := float(c.y)
	match kind:
		"plank":
			return Vector2(y + 0.7, y + 1.0)
		"spring":
			return Vector2(y, y + SPRING_TOP)
		"fan":
			return Vector2(y, y + FAN_TOP)
		"stairs":
			var lx := clampf(px - c.x, 0.0, 1.0)
			var lz := clampf(pz - c.z, 0.0, 1.0)
			var t := lx
			match rot % 4:
				1:
					t = lz
				2:
					t = 1.0 - lx
				3:
					t = 1.0 - lz
			return Vector2(y, y + minf(1.0, t + 0.15))
	return Vector2(y, y + 1.0)


## All solids overlapping the square [px±r] x [pz±r]: each is [bottom, top, kind].
func spans_at(px: float, pz: float, r: float) -> Array:
	var out: Array = []
	for g in grounds:
		if px > g[0] - r and px < g[1] + r and pz > g[2] - r and pz < g[3] + r:
			out.append([g[5], g[4], "ground"])
	for l in lavas:
		if px > l[0] - r and px < l[1] + r and pz > l[2] - r and pz < l[3] + r:
			out.append([l[4] - 1.0, l[4], "lava"])
	if columns.is_empty():
		return out
	for cx in range(floori(px - r), floori(px + r) + 1):
		for cz in range(floori(pz - r), floori(pz + r) + 1):
			var col := Vector2i(cx, cz)
			if not columns.has(col):
				continue
			var layers: Array = columns[col]
			for cy in layers:
				var c := Vector3i(cx, cy, cz)
				var b: Array = blocks[c]
				var kind: String = b[0]
				var sp := block_span(kind, int(b[1]), c, px, pz)
				out.append([sp.x, sp.y, kind])
	return out


## Wind push at a point right now (zero when calm).
func gust_at(p: Vector3, t: float) -> Vector3:
	for g in gusts:
		if p.x < g[0] or p.x > g[1] or p.z < g[2] or p.z > g[3] or p.y < g[4] or p.y > g[5]:
			continue
		if gust_on(g, t):
			return Vector3(g[6], 0.0, g[7])
	return Vector3.ZERO


func gust_on(g: Array, t: float) -> bool:
	var period: float = g[8]
	var duty: float = g[9]
	return fmod(t, period) > period * (1.0 - duty)


## Is there an updraft here? Returns the hover height (or -INF).
func fan_hover(p: Vector3) -> float:
	var col := Vector2i(floori(p.x), floori(p.z))
	if not columns.has(col):
		return -INF
	var best := -INF
	for cy in columns[col]:
		var c := Vector3i(col.x, cy, col.y)
		if block_kind(c) != "fan":
			continue
		var top := float(cy) + FAN_TOP
		if p.y >= top - 0.2 and p.y <= top + FAN_LIFT + 0.6:
			best = maxf(best, top + FAN_LIFT)
	return best


func water_level(t: float) -> float:
	if water.is_empty():
		return -100.0
	var y0: float = water[0]
	var y1: float = water[1]
	var delay: float = water[2]
	var rate: float = water[3]
	return minf(y1, y0 + maxf(0.0, t - delay) * rate)


## Highest surface top in the column at (x, z) at or below `below`, or -INF.
func surface_below(x: float, z: float, below: float, r: float = 0.2) -> float:
	var best := -INF
	for s in spans_at(x, z, r):
		var top: float = s[1]
		if top <= below + 0.01:
			best = maxf(best, top)
	return best


## Can a block of this kind go in this cell? (the host also checks runners)
func can_place(kind: String, c: Vector3i) -> bool:
	if c.x < MIN_X or c.x > MAX_X or c.z < MIN_Z or c.z > MAX_Z or c.y < MIN_Y or c.y > MAX_Y:
		return false
	if blocks.has(c):
		return false
	var lo := float(c.y)
	var hi := float(c.y) + 1.0
	if kind == "plank":
		lo += 0.7
	for g in grounds:
		if c.x + 1 > g[0] + 0.01 and c.x < g[1] - 0.01 and c.z + 1 > g[2] + 0.01 and c.z < g[3] - 0.01 \
				and hi > g[5] + 0.01 and lo < g[4] - 0.01:
			return false
	for l in lavas:
		if c.x + 1 > l[0] + 0.01 and c.x < l[1] - 0.01 and c.z + 1 > l[2] + 0.01 and c.z < l[3] - 0.01 \
				and hi > l[4] - 1.0 and lo < l[4] - 0.01:
			return false
	# Keep the flag and the start pad clear.
	for p in [flag_pos, start]:
		var fp: Vector3 = p
		if floori(fp.x) == c.x and floori(fp.z) == c.z and c.y >= floori(fp.y) - 1 and c.y <= floori(fp.y) + 2:
			return false
	return true


## Where a block "wants" to go when the flat builder points at a column: on top of whatever is there,
## or (over a gap) flush with the neighbouring ground so bridges line up.
func auto_layer(cx: int, cz: int) -> int:
	var here := surface_below(cx + 0.5, cz + 0.5, 50.0, 0.05)
	if here > -INF:
		return int(ceilf(here - 0.01))
	var best := -INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0)]:
		var s := surface_below(cx + d.x + 0.5, cz + d.y + 0.5, 50.0, 0.05)
		best = maxf(best, s)
	if best > -INF:
		return int(ceilf(best - 0.01)) - 1
	return 0


# --- Per-frame visuals -------------------------------------------------------------

func update_visuals(delta: float, level_time: float, water_y: float) -> void:
	anim_t += delta
	if flag_cloth != null and is_instance_valid(flag_cloth):
		flag_cloth.rotation.y = sin(anim_t * 3.0) * 0.25
		flag_cloth.position = flag_pos + Vector3(0.45 * cos(flag_cloth.rotation.y), 1.9, 0.45 * sin(-flag_cloth.rotation.y))
	if flag_ring != null and is_instance_valid(flag_ring):
		var s := 1.0 + sin(anim_t * 4.0) * 0.08
		flag_ring.scale = Vector3(s, 1.0, s)
	for i in mini(gust_fx.size(), gusts.size()):
		var fx: CPUParticles3D = gust_fx[i]
		fx.emitting = gust_on(gusts[i], level_time + 0.25)
	if water_node != null and is_instance_valid(water_node):
		water_node.position.y = water_y + sin(anim_t * 1.5) * 0.04
	for key in blocks:
		var b: Array = blocks[key]
		if b[0] == "fan":
			var n: Node3D = b[2]
			if is_instance_valid(n):
				var blades := n.get_node_or_null("Blades") as Node3D
				if blades:
					blades.rotation.y += delta * 14.0
