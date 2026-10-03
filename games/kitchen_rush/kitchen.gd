extends RefCounted
## Builds the kitchen: sunny sky, tiled floor, pastel walls, the big counter, fridge + pantry,
## the vegetable garden out the back door, the stove and the serving window. Returns nodes main needs.

const L := preload("res://games/kitchen_rush/layout.gd")
const ItemScript := preload("res://games/kitchen_rush/item.gd")

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 a : source_color = vec3(0.99, 0.95, 0.86);
uniform vec3 b : source_color = vec3(0.55, 0.86, 0.82);
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = floor(w.xz / 0.7);
	float c = mod(g.x + g.y, 2.0);
	ALBEDO = mix(a, b, c);
	ROUGHNESS = 0.55;
}
"""

const GRASS_SHADER := """
shader_type spatial;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = sin(w.x * 3.1) * sin(w.z * 2.7) * 0.5 + 0.5;
	ALBEDO = mix(vec3(0.35, 0.72, 0.28), vec3(0.45, 0.82, 0.32), n);
	ROUGHNESS = 0.9;
}
"""


static func build(main: Node3D) -> Dictionary:
	var out := {}
	_environment(main)
	var statics := StaticBody3D.new()
	statics.collision_layer = 1
	main.add_child(statics)
	out["statics"] = statics

	# Floors: kitchen tiles inside, grass in the garden and outside the window.
	var fl := _box(main, Vector3(0, -0.05, 0), Vector3(L.ROOM_HALF.x * 2.0, 0.1, L.ROOM_HALF.y * 2.0), Color.WHITE)
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FLOOR_SHADER
	fl.material_override = fm
	var gm := ShaderMaterial.new()
	gm.shader = Shader.new()
	gm.shader.code = GRASS_SHADER
	var grass := _box(main, Vector3(0, -0.06, -12.0), Vector3(40.0, 0.1, 12.0), Color.WHITE)
	grass.material_override = gm
	var lawn := _box(main, Vector3(12.0, -0.06, 0), Vector3(10.0, 0.1, 40.0), Color.WHITE)
	lawn.material_override = gm
	_box(main, Vector3(-12.0, -0.06, 4.0), Vector3(10.0, 0.1, 28.0), Color(0.45, 0.78, 0.32))
	_box(main, Vector3(0, -0.06, 12.0), Vector3(14.0, 0.1, 12.0), Color(0.45, 0.78, 0.32))
	_box(main, Vector3(8.6, 0.0, 0), Vector3(3.0, 0.02, 8.0), Color(0.75, 0.75, 0.8))  # pavement for customers

	# Walls (cream with a teal stripe), back door gap in the north wall.
	var wall_col := Color(1.0, 0.93, 0.72)
	var trim := Color(0.3, 0.7, 0.75)
	var hx := L.ROOM_HALF.x
	var hz := L.ROOM_HALF.y
	var h := 2.6
	_wall(main, statics, Vector3(0, h / 2, hz), Vector3(hx * 2 + 0.4, h, 0.3), wall_col, trim)  # south
	_wall(main, statics, Vector3(-hx, h / 2, 0), Vector3(0.3, h, hz * 2), wall_col, trim)  # west
	var side_len := hx - L.DOOR_HALF
	_wall(main, statics, Vector3(-(L.DOOR_HALF + side_len / 2), h / 2, -hz), Vector3(side_len + 0.2, h, 0.3), wall_col, trim)
	_wall(main, statics, Vector3(L.DOOR_HALF + side_len / 2, h / 2, -hz), Vector3(side_len + 0.2, h, 0.3), wall_col, trim)
	_box(main, Vector3(0, h - 0.25, -hz), Vector3(L.DOOR_HALF * 2, 0.5, 0.3), wall_col)  # over the door
	for s in [-1.0, 1.0]:
		_box(main, Vector3(s * (L.DOOR_HALF + 0.05), 1.05, -hz + 0.02), Vector3(0.12, 2.1, 0.36), Color(0.95, 0.45, 0.4))
	# East wall with the serving window (z -3.4..3.4, from 0.95 m to 2.2 m high).
	var wx := L.WINDOW_X
	_collider(statics, Vector3(wx, h / 2, 0), Vector3(0.3, h, hz * 2))
	_box(main, Vector3(wx, 0.475, 0), Vector3(0.3, 0.95, hz * 2), wall_col)
	_box(main, Vector3(wx, 2.4, 0), Vector3(0.3, 0.4, hz * 2), wall_col)
	for s in [-1.0, 1.0]:
		_box(main, Vector3(wx, 1.6, s * 4.7), Vector3(0.3, 1.3, 2.6), wall_col)
	_box(main, Vector3(wx - 0.05, 0.98, 0), Vector3(0.7, 0.06, 6.8), Color(0.95, 0.5, 0.3))  # ledge
	for i in 8:  # striped awning
		var stripe := _box(main, Vector3(wx + 0.55, 2.35, -3.15 + i * 0.9), Vector3(1.0, 0.06, 0.9),
			Color(1.0, 0.35, 0.4) if i % 2 == 0 else Color.WHITE)
		stripe.rotation.z = -0.35
	main.add_sign(Vector3(wx - 0.1, 2.85, 0), "SERVING WINDOW", Color(1.0, 0.45, 0.4), 90, false)

	# The big counter in the middle, and the chef's little area behind it.
	var top := L.COUNTER_TOP
	var cw := L.COUNTER_HALF.x * 2.0
	var cd := L.COUNTER_HALF.y * 2.0
	_box(main, Vector3(0, (top - 0.05) / 2, 0), Vector3(cw - 0.08, top - 0.05, cd - 0.08), Color(0.95, 0.6, 0.35))
	_box(main, Vector3(0, top - 0.025, 0), Vector3(cw, 0.05, cd), Color(0.97, 0.97, 0.95))
	_collider(statics, Vector3(0, top / 2, 0), Vector3(cw, top, cd))
	_box(main, Vector3(0, top + 0.003, -0.13), Vector3(cw - 0.2, 0.006, 0.2), Color(1.0, 0.75, 0.3))  # pass strip
	_box(main, Vector3(0, top + 0.01, L.BOARD.z), Vector3(0.34, 0.02, 0.24), Color(0.85, 0.65, 0.4))  # chopping board
	for p in L.PLATE_HOME:
		var ring := _box(main, Vector3(p.x, top + 0.003, p.z), Vector3(0.3, 0.006, 0.3), Color(0.75, 0.88, 1.0))
		ring.rotation.y = PI / 4.0
	for p in L.OUT_SLOTS:
		_box(main, Vector3(p.x, top + 0.004, p.z), Vector3(0.32, 0.008, 0.32), Color(1.0, 0.85, 0.3))
	# Trash chute: a dark hole with a red rim.
	_box(main, Vector3(L.TRASH.x, top + 0.004, L.TRASH.z), Vector3(0.24, 0.01, 0.24), Color(0.85, 0.2, 0.2))
	_box(main, Vector3(L.TRASH.x, top + 0.008, L.TRASH.z), Vector3(0.18, 0.01, 0.18), Color(0.08, 0.08, 0.1))
	var lab: Label3D = main.add_sign(Vector3(L.TRASH.x, top + 0.05, L.TRASH.z + 0.18), "BIN", Color(1.0, 0.5, 0.45), 40, false)
	lab.rotation.x = -PI / 2.6
	main.add_sign(Vector3(0, top + 0.45, -0.42), "PASS  -  drop ingredients here", Color(1.0, 0.8, 0.3), 36, true)
	# Chef area fence (low, so runners can see the chef).
	var ca := L.CHEF_AREA
	_collider(statics, Vector3(ca.get_center().x, 0.6, ca.get_center().y), Vector3(ca.size.x, 1.2, ca.size.y))
	for s in [-1.0, 1.0]:
		_box(main, Vector3(s * (ca.size.x / 2.0), 0.45, ca.get_center().y), Vector3(0.08, 0.9, ca.size.y), Color(0.95, 0.6, 0.35))
	_box(main, Vector3(0, 0.45, ca.end.y), Vector3(ca.size.x, 0.9, 0.08), Color(0.95, 0.6, 0.35))
	# Chef's floor mat.
	_box(main, Vector3(0, 0.005, 1.0), Vector3(1.6, 0.01, 1.0), Color(0.95, 0.45, 0.45))

	# Fridge (west wall) with ingredient crates in front, and the pantry shelf.
	_box(main, Vector3(-6.55, 1.1, -1.4), Vector3(0.7, 2.2, 3.6), Color(0.7, 0.9, 1.0))
	_box(main, Vector3(-6.18, 1.1, -1.4), Vector3(0.04, 2.0, 0.04), Color(0.5, 0.6, 0.7))
	_box(main, Vector3(-6.16, 1.4, -0.9), Vector3(0.05, 0.6, 0.06), Color(0.85, 0.85, 0.9))
	_box(main, Vector3(-6.16, 1.4, -1.9), Vector3(0.05, 0.6, 0.06), Color(0.85, 0.85, 0.9))
	main.add_sign(Vector3(-6.1, 2.45, -1.4), "FRIDGE", Color(0.4, 0.7, 1.0), 80, false).rotation.y = -PI / 2.0
	_collider(statics, Vector3(-6.55, 1.1, -1.4), Vector3(0.7, 2.2, 3.6))
	_box(main, Vector3(-6.6, 0.9, 2.2), Vector3(0.6, 1.8, 1.4), Color(0.75, 0.5, 0.3))
	_collider(statics, Vector3(-6.6, 0.9, 2.2), Vector3(0.6, 1.8, 1.4))
	main.add_sign(Vector3(-6.2, 2.1, 2.2), "PANTRY", Color(0.95, 0.65, 0.3), 70, false).rotation.y = -PI / 2.0
	for src in L.SOURCES:
		var kind: String = src[0]
		var pos: Vector3 = src[1]
		if pos.x < -5.0:
			_crate(main, statics, pos, kind)
		else:
			_garden_bed(main, statics, pos, kind)

	# Garden fence.
	var fence_col := Color.WHITE
	for i in 21:
		var x := -10.0 + i
		_box(main, Vector3(x, 0.45, L.GARDEN_END), Vector3(0.12, 0.9, 0.08), fence_col)
	_box(main, Vector3(0, 0.6, L.GARDEN_END), Vector3(20.0, 0.08, 0.06), fence_col)
	_collider(statics, Vector3(0, 0.6, L.GARDEN_END - 0.1), Vector3(20.0, 1.2, 0.2))
	for s in [-1.0, 1.0]:
		_collider(statics, Vector3(s * 9.0, 0.6, -8.8), Vector3(0.2, 1.2, 5.6))
		for i in 6:
			_box(main, Vector3(s * 9.0, 0.45, -6.3 - i), Vector3(0.08, 0.9, 0.12), fence_col)
	main.add_sign(Vector3(0, 2.6, -7.0), "VEGETABLE GARDEN", Color(0.45, 0.9, 0.35), 70, true)
	# A few round trees and flowers for cheer.
	for t in [Vector3(-7.5, 0, -9.5), Vector3(7.0, 0, -10.0), Vector3(-9.0, 0, 6.0), Vector3(10.5, 0, 7.0), Vector3(10.0, 0, -6.5)]:
		_tree(main, t)
	for i in 14:
		var fx := -8.0 + i * 1.2
		var flower := _sphere_mi(main, 0.09, Vector3(fx, 0.12, -10.9),
			[Color(1.0, 0.4, 0.6), Color(1.0, 0.85, 0.3), Color(0.6, 0.5, 1.0)][i % 3])
		flower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Stove with a frying pan (it catches fire sometimes!) and the fire extinguisher.
	_box(main, Vector3(L.STOVE.x, 0.45, L.STOVE.z), Vector3(1.2, 0.9, 0.8), Color(0.35, 0.37, 0.42))
	_collider(statics, Vector3(L.STOVE.x, 0.45, L.STOVE.z), Vector3(1.2, 0.9, 0.8))
	for s in [-1.0, 1.0]:
		var burner := _cyl_mi(main, 0.16, 0.02, Vector3(L.STOVE.x + s * 0.3, 0.91, L.STOVE.z), Color(0.12, 0.12, 0.14))
		burner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl_mi(main, 0.2, 0.06, Vector3(L.STOVE.x + 0.3, 0.95, L.STOVE.z), Color(0.2, 0.2, 0.22))
	_box(main, Vector3(L.STOVE.x + 0.62, 0.97, L.STOVE.z), Vector3(0.3, 0.03, 0.05), Color(0.2, 0.2, 0.22))
	main.add_sign(Vector3(L.STOVE.x, 2.0, L.STOVE.z + 0.2), "STOVE", Color(1.0, 0.55, 0.3), 60, true)
	_box(main, Vector3(L.EXT_POS.x, 0.3, L.EXT_POS.z), Vector3(0.5, 0.6, 0.4), Color(0.6, 0.6, 0.65))
	_collider(statics, Vector3(L.EXT_POS.x, 0.3, L.EXT_POS.z), Vector3(0.5, 0.6, 0.4))
	main.add_sign(Vector3(L.EXT_POS.x, 1.9, L.EXT_POS.z + 0.2), "FIRE EXTINGUISHER", Color(1.0, 0.3, 0.3), 44, true)

	# Hanging lamps over the counter for a warm look (no shadows).
	for x in [-3.0, 0.0, 3.0]:
		var lamp := _cyl_mi(main, 0.25, 0.18, Vector3(x, 2.5, 0.0), Color(1.0, 0.8, 0.3))
		lamp.material_override = main.mat(Color(1.0, 0.85, 0.4), 2.0)
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.9, 0.75)
	fill.light_energy = 1.2
	fill.omni_range = 7.0
	fill.position = Vector3(0, 2.3, 0)
	main.add_child(fill)
	return out


static func _environment(main: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.6, 1.0)
	sky_mat.sky_horizon_color = Color(0.75, 0.88, 1.0)
	sky_mat.ground_horizon_color = Color(0.7, 0.85, 0.7)
	sky_mat.ground_bottom_color = Color(0.3, 0.5, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.ssao_enabled = true
	e.ssao_intensity = 1.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	env.environment = e
	main.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	main.add_child(sun)


static func _box(main: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = main.mat(color)
	mi.position = pos
	main.add_child(mi)
	return mi


static func _collider(statics: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	statics.add_child(cs)


static func _wall(main: Node3D, statics: StaticBody3D, pos: Vector3, size: Vector3, color: Color, trim: Color) -> void:
	_box(main, pos, size, color)
	_box(main, Vector3(pos.x, 0.5, pos.z), size * Vector3(1.0, 0.0, 1.0) + Vector3(0.04, 0.14, 0.04), trim)
	_collider(statics, pos, size)


static func _sphere_mi(main: Node3D, r: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	mi.mesh = s
	mi.material_override = main.mat(color)
	mi.position = pos
	main.add_child(mi)
	return mi


static func _cyl_mi(main: Node3D, r: float, h: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	mi.mesh = c
	mi.material_override = main.mat(color)
	mi.position = pos
	main.add_child(mi)
	return mi


static func _tree(main: Node3D, pos: Vector3) -> void:
	_cyl_mi(main, 0.15, 1.4, pos + Vector3(0, 0.7, 0), Color(0.55, 0.35, 0.2))
	_sphere_mi(main, 0.9, pos + Vector3(0, 1.9, 0), Color(0.3, 0.7, 0.3))


## A crate in front of the fridge / pantry with a sample of what's inside and a big name.
static func _crate(main: Node3D, statics: StaticBody3D, pos: Vector3, kind: String) -> void:
	var c := ItemScript.color_of(kind)
	_box(main, pos + Vector3(0.1, 0.3, 0), Vector3(0.6, 0.6, 0.9), Color(0.8, 0.6, 0.35))
	_box(main, pos + Vector3(0.1, 0.61, 0), Vector3(0.5, 0.02, 0.8), c)
	_collider(statics, pos + Vector3(0.1, 0.3, 0), Vector3(0.6, 0.6, 0.9))
	for i in 3:
		var sample := ItemScript.new()
		sample.main = main
		sample.kind = kind
		sample.remove_from_group("kr_items")
		sample.position = pos + Vector3(0.1 + (i - 1) * 0.12, 0.62, (i - 1) * 0.22)
		sample.scale = Vector3.ONE * 1.6
		main.add_child(sample)
		sample.remove_from_group("kr_items")
		sample.set_process(false)
	main.add_sign(pos + Vector3(0.3, 1.2, 0), ItemScript.display_name(kind), c.lightened(0.2), 56, true)


## A raised garden bed with plants; the vegetable grows on top.
static func _garden_bed(main: Node3D, statics: StaticBody3D, pos: Vector3, kind: String) -> void:
	var c := ItemScript.color_of(kind)
	_box(main, pos + Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 1.0), Color(0.6, 0.38, 0.22))
	_box(main, pos + Vector3(0, 0.41, 0), Vector3(1.45, 0.04, 0.85), Color(0.4, 0.26, 0.15))
	_collider(statics, pos + Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 1.0))
	for i in 4:
		var x := -0.54 + i * 0.36
		var leaf := _sphere_mi(main, 0.16, pos + Vector3(x, 0.52, 0.0), Color(0.25, 0.6, 0.25))
		leaf.scale = Vector3(1.0, 0.7, 1.0)
		var sample := ItemScript.new()
		sample.main = main
		sample.kind = kind
		sample.position = pos + Vector3(x, 0.6, 0.0)
		sample.scale = Vector3.ONE * 1.5
		main.add_child(sample)
		sample.remove_from_group("kr_items")
		sample.set_process(false)
	main.add_sign(pos + Vector3(0, 1.5, 0), ItemScript.display_name(kind), c.lightened(0.25), 64, true)
