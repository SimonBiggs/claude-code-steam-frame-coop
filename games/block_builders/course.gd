extends Node3D
## The floating obstacle course: static islands, lava, wind gusts, rising water, the flag, and the
## blocks the builder has placed. Also the collision queries the runners use (simple column spans,
## no physics engine): every solid is a vertical span [bottom, top] over an area of the XZ plane.
## Built the same way on the host and on the TV (deterministic from the level index); blocks arrive
## in snapshots on the TV.

const Art := preload("res://games/block_builders/art.gd")
const Levels := preload("res://games/block_builders/levels.gd")
const Themes := preload("res://games/block_builders/themes.gd")

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
const BOOSTER_TOP := 0.15
const LAUNCH_TOP := 0.36
## Background islands: [x, y, z, width, depth] (decoration far behind and beside the course).
const BG_ISLANDS := [[-24.0, -3.0, -18.0, 7.0, 5.0], [20.0, 1.0, -22.0, 8.0, 6.0], [2.0, -9.0, -30.0, 10.0, 7.0],
	[-34.0, 2.0, -2.0, 6.0, 5.0], [32.0, -5.0, -8.0, 7.0, 5.0], [-12.0, 6.0, -34.0, 6.0, 4.0]]

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
var theme: Dictionary = {}
var theme_name := ""
var stars: Array = []         # Vector3 star centres for this level
var star_nodes: Array = []
var stars_taken := 0          # bitmask (host decides; snapshots tell the TV)
var decor_root: Node3D
var cloud_mm: MultiMesh
var cloud_mat: StandardMaterial3D
var cloud_data: Array = []    # [base position, scale]
var bird_mm: MultiMesh
var sky_stars: MultiMeshInstance3D
var rainbow: MeshInstance3D
var balloon: Node3D
var balloon_vis := 0.0
var hint_node: MeshInstance3D
var hint_mat: StandardMaterial3D
var hint_key := ""


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
	_apply_theme(str(data.get("theme", "meadow")))
	var grass_cols: Array = theme.grass
	var gi := 0
	# Islands are solid cliffs down to below the lowest island, so a high ledge is a wall you can't
	# walk under (runners used to slip beneath high ledges and fall).
	var min_top := INF
	for g in data.ground:
		min_top = minf(min_top, float(g[4]))
	for g in data.ground:
		var x0: float = g[0]
		var x1: float = g[1]
		var z0: float = g[2]
		var z1: float = g[3]
		var top: float = g[4]
		var bottom := minf(top - 1.0, min_top - 1.0)
		grounds.append([x0, x1, z0, z1, top, bottom])
		var mi := MeshInstance3D.new()
		var gc: Color = grass_cols[gi % grass_cols.size()]
		mi.mesh = Art.island_mesh(x0, x1, z0, z1, top, bottom, gc, theme.dirt, theme.rock)
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
	_build_props()
	_build_stars()
	hint_node = null
	hint_key = ""


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


## Clouds drifting around and below the course, a flock of birds and (per theme) a starry sky and a
## rainbow. Clouds and birds are MultiMeshes (one draw call each), built once.
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	cloud_mat = Art.mat(Color(1.0, 1.0, 1.0), 0.15, 1.0)
	var puff := Art.sphere(1.0, 12)
	puff.material = cloud_mat
	cloud_mm = MultiMesh.new()
	cloud_mm.transform_format = MultiMesh.TRANSFORM_3D
	cloud_mm.mesh = puff
	cloud_mm.instance_count = 36
	cloud_data.clear()
	for i in 12:
		var c := Vector3(rng.randf_range(-40, 40), rng.randf_range(-10, -3) if i % 3 != 0 else rng.randf_range(4, 9),
			rng.randf_range(-26, -6) if i % 2 == 0 else rng.randf_range(-14, 4))
		for j in 3:
			var sc := rng.randf_range(1.0, 1.9)
			cloud_data.append([c + Vector3(j * 1.6 - 1.6, rng.randf_range(-0.3, 0.3), rng.randf_range(-0.5, 0.5)), sc])
	var cmi := MultiMeshInstance3D.new()
	cmi.multimesh = cloud_mm
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cmi)
	_update_clouds()
	bird_mm = MultiMesh.new()
	bird_mm.transform_format = MultiMesh.TRANSFORM_3D
	bird_mm.mesh = Art.bird_mesh()
	bird_mm.instance_count = 7
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bird_mm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)


func _update_clouds() -> void:
	for i in cloud_data.size():
		var d: Array = cloud_data[i]
		var p: Vector3 = d[0]
		var sc: float = d[1]
		var x := fposmod(p.x + anim_t * 0.35 + 40.0, 80.0) - 40.0
		cloud_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc * 0.62, sc)), Vector3(x, p.y, p.z)))


func _update_birds() -> void:
	for i in bird_mm.instance_count:
		var a := anim_t * 0.22 + i * 0.5
		var r := 21.0 + (i % 3) * 1.6
		var pos := Vector3(cos(a) * r, 7.0 + sin(anim_t * 0.7 + i) * 0.6 + (i % 2) * 0.8, -10.0 + sin(a) * r * 0.6)
		var fwd := Vector3(-sin(a), 0.0, cos(a) * 0.6).normalized()
		var flap := 1.0 + sin(anim_t * 9.0 + i * 1.7) * 0.45
		var b := Basis.looking_at(fwd, Vector3.UP).scaled(Vector3(flap, 1.0, 1.0) * 1.4)
		bird_mm.set_instance_transform(i, Transform3D(b, pos))


## Sky, island colours, background islands, stars and rainbow for a theme (rebuilt when it changes).
func _apply_theme(tn: String) -> void:
	theme = Themes.get_theme(tn)
	if main != null and main.has_method("apply_theme"):
		main.apply_theme(theme)
	if cloud_mat != null:
		cloud_mat.albedo_color = theme.cloud
		cloud_mat.emission = theme.cloud
	if tn == theme_name and decor_root != null and is_instance_valid(decor_root):
		return
	theme_name = tn
	if decor_root != null and is_instance_valid(decor_root):
		decor_root.queue_free()
	decor_root = Node3D.new()
	decor_root.name = "ThemeDecor"
	add_child(decor_root)
	var grass_cols: Array = theme.grass
	var props: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tn)
	for i in BG_ISLANDS.size():
		var b: Array = BG_ISLANDS[i]
		var c := Vector3(b[0], b[1], b[2])
		var w: float = b[3]
		var d: float = b[4]
		var mi := MeshInstance3D.new()
		var gc: Color = grass_cols[i % grass_cols.size()]
		mi.mesh = Art.island_mesh(c.x - w * 0.5, c.x + w * 0.5, c.z - d * 0.5, c.z + d * 0.5, c.y, c.y - 2.0, gc, theme.dirt, theme.rock)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		decor_root.add_child(mi)
		var far_props: Array = theme.props_far
		for k in 3:
			var pk := rng.randi_range(0, far_props.size() - 1)
			var pp := Vector3(c.x + rng.randf_range(-w * 0.35, w * 0.35), c.y, c.z + rng.randf_range(-d * 0.3, d * 0.3))
			props.append([pk, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.5, 2.2)), pp)])
	_fill_props(decor_root, theme.props_far, props)
	if theme.get("stars", false):
		_build_sky_stars()
	if theme.get("rainbow", false):
		_ensure_rainbow()
		rainbow.visible = true
	elif rainbow != null:
		rainbow.visible = false


## One MultiMeshInstance3D per prop kind of a list ([kind, tint] entries); items = [list index, transform].
func _fill_props(parent: Node3D, kinds: Array, items: Array) -> void:
	for k in kinds.size():
		var xfs: Array = []
		for it in items:
			if int(it[0]) == k:
				xfs.append(it[1])
		if xfs.is_empty():
			continue
		var entry: Array = kinds[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Art.prop_mesh(str(entry[0]), entry[1])
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		if str(entry[0]) == "lamp":
			# Glowing bulbs on top of the lamp posts (a second MultiMesh sharing the transforms).
			var bm := MultiMesh.new()
			bm.transform_format = MultiMesh.TRANSFORM_3D
			bm.mesh = Art.prop_mesh("bulb", Color(1.0, 0.85, 0.45))
			bm.instance_count = xfs.size()
			for i in xfs.size():
				bm.set_instance_transform(i, xfs[i])
			var bmi := MultiMeshInstance3D.new()
			bmi.multimesh = bm
			bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(bmi)


## Props along the back (tall) and front (small) edges of every island of this level.
func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_index * 101 + 7
	var far_items: Array = []
	var near_items: Array = []
	var avoid: Array = [start, flag_pos]
	for st in data.get("stars", []):
		avoid.append(st)
	var sol_cols := {}
	for item in data.get("solution", []):
		var c: Vector3i = item[1]
		sol_cols[Vector2i(c.x, c.z)] = true
	var far_kinds: Array = theme.props_far
	var near_kinds: Array = theme.props_near
	for g in grounds:
		var x0: float = g[0]
		var x1: float = g[1]
		var z0: float = g[2]
		var z1: float = g[3]
		var top: float = g[4]
		if z1 - z0 < 2.5 or x1 - x0 < 1.8:
			continue
		var x := x0 + rng.randf_range(0.35, 0.8)
		while x < x1 - 0.3:
			var pf := Vector3(x, top, z0 + rng.randf_range(0.35, 0.55))
			if _prop_ok(pf, avoid, sol_cols, 1.4):
				far_items.append([rng.randi_range(0, far_kinds.size() - 1),
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), pf)])
			var pn := Vector3(x + rng.randf_range(0.2, 0.6), top, z1 - rng.randf_range(0.2, 0.35))
			if rng.randf() < 0.65 and pn.x < x1 - 0.2 and _prop_ok(pn, avoid, sol_cols, 1.2):
				near_items.append([rng.randi_range(0, near_kinds.size() - 1),
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.1)), pn)])
			x += rng.randf_range(1.1, 1.7)
	_fill_props(level_root, far_kinds, far_items)
	_fill_props(level_root, near_kinds, near_items)


func _prop_ok(p: Vector3, avoid: Array, sol_cols: Dictionary, r: float) -> bool:
	for a in avoid:
		var av: Vector3 = a
		if Vector2(p.x - av.x, p.z - av.z).length() < r:
			return false
	return not sol_cols.has(Vector2i(floori(p.x), floori(p.z)))


func _build_sky_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bx := Art.box(Vector3.ONE * 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.97, 0.85)
	bx.material = m
	mm.mesh = bx
	mm.instance_count = 160
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 160:
		var a := rng.randf() * TAU
		var el := rng.randf_range(0.08, 1.3)
		var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.4)), dir * 90.0))
	sky_stars = MultiMeshInstance3D.new()
	sky_stars.multimesh = mm
	sky_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decor_root.add_child(sky_stars)


func _ensure_rainbow() -> void:
	if rainbow != null and is_instance_valid(rainbow):
		return
	rainbow = MeshInstance3D.new()
	rainbow.mesh = Art.rainbow_mesh(28.0, 1.6)
	rainbow.position = Vector3(0.0, -8.0, -36.0)
	rainbow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rainbow)


## The finale: the rainbow appears over every theme once all levels are cleared.
func show_rainbow(on: bool) -> void:
	if on:
		_ensure_rainbow()
		rainbow.visible = true
	elif rainbow != null and is_instance_valid(rainbow):
		rainbow.visible = bool(theme.get("rainbow", false))


# --- Stars, gift balloon and build hints ------------------------------------------------

func _build_stars() -> void:
	stars = []
	star_nodes = []
	stars_taken = 0
	var sm := Art.mat(Color(1.0, 0.85, 0.2), 1.6, 0.3)
	for p in data.get("stars", []):
		var sp: Vector3 = p
		stars.append(sp)
		var mi := MeshInstance3D.new()
		mi.mesh = Art.star_mesh()
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = sp
		level_root.add_child(mi)
		star_nodes.append(mi)


func set_stars_taken(mask: int) -> void:
	stars_taken = mask
	for i in star_nodes.size():
		var n: MeshInstance3D = star_nodes[i]
		if is_instance_valid(n):
			n.visible = (mask & (1 << i)) == 0


func star_taken(i: int) -> bool:
	return (stars_taken & (1 << i)) != 0


func _ensure_balloon() -> void:
	if balloon != null and is_instance_valid(balloon):
		return
	balloon = Node3D.new()
	balloon.name = "GiftBalloon"
	add_child(balloon)
	var gift := MeshInstance3D.new()
	gift.mesh = Art.gift_mesh()
	balloon.add_child(gift)
	var string := MeshInstance3D.new()
	string.mesh = Art.cyl(0.015, 0.015, 1.0, 4)
	string.material_override = Art.mat(Color(0.95, 0.95, 0.95))
	string.position = Vector3(0, 0.7, 0)
	balloon.add_child(string)
	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	ball.mesh = Art.sphere(0.45, 14)
	ball.material_override = Art.mat(Color(1.0, 0.3, 0.4), 0.35, 0.25)
	ball.position = Vector3(0, 1.55, 0)
	ball.scale = Vector3(1.0, 1.15, 1.0)
	balloon.add_child(ball)
	balloon.visible = false


## Balloon state: 0 gone, 1 drifting, 2 carried by the builder. pos = the gift box (the part to touch).
func update_balloon(state: int, pos: Vector3, delta: float) -> void:
	if state == 0 and (balloon == null or not balloon.visible):
		return
	_ensure_balloon()
	balloon.visible = state != 0
	if state == 0:
		return
	var k := 1.0 - exp(-12.0 * delta)
	balloon.global_position = pos if balloon_vis <= 0.0 else balloon.global_position.lerp(pos, k)
	balloon_vis = 1.0
	balloon.rotation.z = sin(anim_t * 1.7) * 0.12
	balloon.rotation.y += delta * 0.6


func hide_balloon() -> void:
	balloon_vis = 0.0
	if balloon != null and is_instance_valid(balloon):
		balloon.visible = false


## A pulsing see-through block where the solution's next block goes (shown when the builder seems stuck).
func set_hint(kind: String, cell: Vector3i, rot: int) -> void:
	var key := "" if kind == "" else "%s_%s_%d" % [kind, cell, rot]
	if key == hint_key:
		return
	hint_key = key
	if kind == "":
		if hint_node != null and is_instance_valid(hint_node):
			hint_node.visible = false
		return
	if hint_node == null or not is_instance_valid(hint_node):
		hint_node = MeshInstance3D.new()
		hint_node.name = "Hint"
		if hint_mat == null:
			hint_mat = StandardMaterial3D.new()
			hint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hint_mat.albedo_color = Color(0.4, 0.95, 1.0, 0.35)
		hint_node.material_override = hint_mat
		hint_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level_root.add_child(hint_node)
	hint_node.mesh = Art.block_mesh(kind)
	hint_node.position = Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)
	hint_node.rotation.y = -rot * PI * 0.5
	hint_node.visible = true


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
	elif kind == "booster" or kind == "launcher":
		# A glowing arrow strip so the direction reads from far away (and from the TV).
		var glow := MeshInstance3D.new()
		glow.name = "Glow"
		glow.mesh = Art.box(Vector3(0.7, 0.02, 0.12))
		glow.material_override = Art.mat(Art.kind_color(kind).lightened(0.3), 2.0)
		glow.position = Vector3(0.0, (BOOSTER_TOP if kind == "booster" else LAUNCH_TOP) + 0.02, 0.0)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(glow)
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
		"booster":
			return Vector2(y, y + BOOSTER_TOP)
		"launcher":
			return Vector2(y, y + LAUNCH_TOP)
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


## All solids overlapping the square [px±r] x [pz±r]: each is [bottom, top, kind, rot].
func spans_at(px: float, pz: float, r: float) -> Array:
	var out: Array = []
	for g in grounds:
		if px > g[0] - r and px < g[1] + r and pz > g[2] - r and pz < g[3] + r:
			out.append([g[5], g[4], "ground", 0])
	for l in lavas:
		if px > l[0] - r and px < l[1] + r and pz > l[2] - r and pz < l[3] + r:
			out.append([l[4] - 1.0, l[4], "lava", 0])
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
				out.append([sp.x, sp.y, kind, int(b[1])])
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
		elif b[0] == "booster" or b[0] == "launcher":
			var n2: Node3D = b[2]
			if is_instance_valid(n2):
				var gl := n2.get_node_or_null("Glow") as Node3D
				if gl:
					gl.position.x = -0.12 + fmod(anim_t * (1.4 if b[0] == "booster" else 0.8), 1.0) * 0.24
	for i in star_nodes.size():
		var sn: MeshInstance3D = star_nodes[i]
		if is_instance_valid(sn) and sn.visible:
			var sp: Vector3 = stars[i]
			sn.position = sp + Vector3(0, sin(anim_t * 2.5 + i) * 0.1, 0)
			sn.rotation.y = anim_t * 2.2 + i
	if hint_node != null and is_instance_valid(hint_node) and hint_node.visible and hint_mat != null:
		hint_mat.albedo_color.a = 0.22 + 0.2 * (0.5 + 0.5 * sin(anim_t * 5.0))
	if cloud_mm != null:
		_update_clouds()
	if bird_mm != null:
		_update_birds()
