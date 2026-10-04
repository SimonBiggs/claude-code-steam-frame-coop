extends RefCounted
## Procedural art for TINY TOWN TYCOON, all built with core/mesh_kit.gd (vertex colours, one mesh
## per look, cached in core/res_cache.gd). Buildings, road and rail tiles, lamps and vehicles are
## designed in CELL UNITS (1.0 = one grid cell, origin on the ground, door / front towards +Z) and
## scaled by Defs.CELL when drawn; the table, garden and terrain are built in metres.
## Windows and street lamps use two shared materials (window_mat / lamp_mat) whose colour the day /
## night cycle changes, so the whole town lights up at dusk with no real lights.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Creatures := preload("res://core/creatures.gd")
const VER := "v3"

const WALLS: Array[Color] = [Color(1.0, 0.93, 0.8), Color(1.0, 0.8, 0.68), Color(0.76, 0.93, 0.82), Color(0.76, 0.86, 1.0),
	Color(0.9, 0.82, 0.98)]
const ROOFS: Array[Color] = [Color(0.86, 0.36, 0.3), Color(0.36, 0.5, 0.82), Color(0.88, 0.52, 0.3), Color(0.4, 0.66, 0.42),
	Color(0.62, 0.36, 0.52)]
const WOOD := Color(0.6, 0.4, 0.24)
const STONE := Color(0.78, 0.76, 0.72)
const DARK := Color(0.25, 0.22, 0.22)
const GLASS := Color(1.0, 0.96, 0.85)  # emissive parts: the window material tints them
const GARDEN := Color(0.52, 0.78, 0.4)
const SNOW := Color(0.97, 0.98, 1.0)


static func at(p: Vector3, s: Vector3 = Vector3.ONE, r: Vector3 = Vector3.ZERO) -> Transform3D:
	return MeshKit.at(p, s, r)


# --- Shared materials --------------------------------------------------------------------------------

## Windows: vertex colour x albedo. Day = soft glassy blue, night = warm glow (set by the day cycle).
static func window_mat() -> StandardMaterial3D:
	return ResCache.get_or_make("ttt_window_mat_" + VER, func() -> Resource:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.55, 0.68, 0.8)
		return m) as StandardMaterial3D


## Street lamp heads (same idea as the windows).
static func lamp_mat() -> StandardMaterial3D:
	return ResCache.get_or_make("ttt_lamp_mat_" + VER, func() -> Resource:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.8, 0.8, 0.75)
		return m) as StandardMaterial3D


## Glowing bits that always glow (sirens, clock faces at night, fire, beacons).
static func glow_mat() -> StandardMaterial3D:
	return MeshKit.glow_material()


## See-through blueprint / ghost material (vertex colours ignored: one flat colour).
static func ghost_mat(c: Color) -> StandardMaterial3D:
	var key := "ttt_ghost_%s_%s" % [c.to_html(true), VER]
	return ResCache.get_or_make(key, func() -> Resource:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = c
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.no_depth_test = false
		m.disable_receive_shadows = true
		return m) as StandardMaterial3D


## Set the day / night look: night 0 (noon) .. 1 (midnight).
static func set_night(night: float) -> void:
	var w := window_mat()
	w.albedo_color = Color(0.55, 0.68, 0.8).lerp(Color(1.45, 1.15, 0.55), clampf(night * 1.4, 0.0, 1.0))
	var l := lamp_mat()
	l.albedo_color = Color(0.8, 0.8, 0.75).lerp(Color(1.7, 1.4, 0.75), clampf(night * 1.6, 0.0, 1.0))


static func _build(b: MeshKit.Builder) -> ArrayMesh:
	return b.build(null, window_mat())


static func cached(key: String, maker: Callable) -> ArrayMesh:
	return ResCache.get_or_make("ttt_" + key + "_" + VER, maker) as ArrayMesh


# --- Little helpers (cell units) ---------------------------------------------------------------------

## A gable roof along X: ridge at height `y + h` over z = cz, eaves at y. w: width (x), d: depth (z).
static func gable(b: MeshKit.Builder, w: float, d: float, h: float, y: float, cz: float, col: Color, snow: bool) -> void:
	var half := d * 0.5
	b.wedge(Vector3(w, h, half), at(Vector3(0.0, y + h * 0.5, cz + half * 0.5)), col)
	b.wedge(Vector3(w, h, half), at(Vector3(0.0, y + h * 0.5, cz - half * 0.5), Vector3.ONE, Vector3(0.0, PI, 0.0)), col.darkened(0.1))
	if snow:
		b.wedge(Vector3(w * 0.98, h * 0.35, half * 0.6), at(Vector3(0.0, y + h * 0.85, cz + half * 0.3)), SNOW)
		b.wedge(Vector3(w * 0.98, h * 0.35, half * 0.6), at(Vector3(0.0, y + h * 0.85, cz - half * 0.3), Vector3.ONE, Vector3(0.0, PI, 0.0)), SNOW)


static func window(b: MeshKit.Builder, p: Vector3, w: float = 0.1, h: float = 0.09, side: bool = false) -> void:
	var s := Vector3(0.015, h, w) if side else Vector3(w, h, 0.015)
	b.box(s, at(p), GLASS, true)
	# a little white frame under the glass
	var f := Vector3(0.012, 0.012, w + 0.03) if side else Vector3(w + 0.03, 0.012, 0.012)
	b.box(f, at(p + Vector3(0.0, -h * 0.5 - 0.006, 0.0)), Color(1, 1, 1))


static func tree_ball(b: MeshKit.Builder, p: Vector3, r: float, leaf: Color) -> void:
	b.cylinder(r * 0.18, r * 0.25, r * 1.2, at(p + Vector3(0.0, r * 0.6, 0.0)), WOOD, 6)
	b.sphere(r, at(p + Vector3(0.0, r * 1.6, 0.0)), leaf, 8)
	b.sphere(r * 0.65, at(p + Vector3(r * 0.5, r * 1.35, r * 0.2)), leaf.lightened(0.1), 7)


static func flowers(b: MeshKit.Builder, p: Vector3, n: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cols: Array[Color] = [Color(1.0, 0.45, 0.55), Color(1.0, 0.85, 0.3), Color(0.75, 0.55, 1.0), Color(1.0, 1.0, 1.0)]
	b.sphere(0.06, at(p + Vector3(0, 0.03, 0), Vector3(1.6, 0.6, 1.0)), Color(0.32, 0.6, 0.3), 6)
	for i in n:
		var o := Vector3(rng.randf_range(-0.07, 0.07), 0.06, rng.randf_range(-0.04, 0.04))
		b.sphere(0.022, at(p + o), cols[rng.randi() % cols.size()], 5)


# --- Buildings ------------------------------------------------------------------------------------------

## Mesh key for a building record (look variant from its id).
static func building_key(kind: String, id: int, lvl: int, snow: bool) -> String:
	var variant := 0
	if kind == "house" or kind == "shop":
		variant = id % 5
	return "%s_%d_%d_%s" % [kind, variant, lvl, "s" if snow else "n"]


static func building_mesh(kind: String, id: int, lvl: int, snow: bool) -> ArrayMesh:
	var key := "b_" + building_key(kind, id, lvl, snow)
	var variant := id % 5 if kind == "house" or kind == "shop" else 0
	return cached(key, func() -> Resource: return _make_building(kind, variant, lvl, snow))


static func _make_building(kind: String, v: int, lvl: int, snow: bool) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match kind:
		"house":
			_house(b, v, lvl, snow)
		"farm":
			_farm(b, snow)
		"shop":
			_shop(b, v, snow)
		"bakery":
			_bakery(b, snow)
		"sawmill":
			_sawmill(b, snow)
		"windmill":
			_windmill(b, snow)
		"water":
			_water_tower(b)
		"school":
			_school(b, snow)
		"park":
			_park(b, snow)
		"fire_station":
			_fire_station(b, snow)
		"station":
			_station(b, snow)
		"landmark":
			_clock_tower(b, snow)
		"ferris":
			_ferris_base(b)
		"hall":
			_town_hall(b, snow)
		_:
			b.box(Vector3(0.6, 0.4, 0.6), at(Vector3(0, 0.2, 0)), Color(1, 0, 1))
	return _build(b)


static func _yard(b: MeshKit.Builder, s: float, col: Color = GARDEN) -> void:
	b.box(Vector3(s - 0.04, 0.02, s - 0.04), at(Vector3(0, 0.01, 0)), col)


static func _house(b: MeshKit.Builder, v: int, lvl: int, snow: bool) -> void:
	var wall: Color = WALLS[v % WALLS.size()]
	var roof: Color = ROOFS[(v * 2 + 1) % ROOFS.size()]
	_yard(b, 1.0)
	b.box(Vector3(0.14, 0.024, 0.26), at(Vector3(0, 0.013, 0.37)), Color(0.9, 0.82, 0.66))
	match lvl:
		1:
			b.box(Vector3(0.56, 0.36, 0.46), at(Vector3(0, 0.2, -0.04)), wall)
			gable(b, 0.66, 0.56, 0.22, 0.38, -0.04, roof, snow)
			b.box(Vector3(0.08, 0.18, 0.08), at(Vector3(0.16, 0.56, -0.14)), Color(0.72, 0.36, 0.3))
			b.box(Vector3(0.1, 0.17, 0.02), at(Vector3(0, 0.105, 0.195)), WOOD)
			window(b, Vector3(-0.17, 0.23, 0.195))
			window(b, Vector3(0.17, 0.23, 0.195))
			window(b, Vector3(0.285, 0.23, -0.04), 0.1, 0.09, true)
			window(b, Vector3(-0.285, 0.23, -0.04), 0.1, 0.09, true)
			flowers(b, Vector3(0.33, 0.0, 0.33), 4, v + 3)
			flowers(b, Vector3(-0.33, 0.0, 0.33), 3, v + 7)
		2:
			b.box(Vector3(0.62, 0.62, 0.52), at(Vector3(0, 0.33, -0.06)), wall)
			gable(b, 0.72, 0.62, 0.24, 0.64, -0.06, roof, snow)
			b.box(Vector3(0.08, 0.2, 0.08), at(Vector3(-0.18, 0.84, -0.16)), Color(0.72, 0.36, 0.3))
			b.box(Vector3(0.12, 0.19, 0.02), at(Vector3(0, 0.115, 0.205)), WOOD)
			for y in [0.25, 0.5]:
				var py: float = y
				window(b, Vector3(-0.19, py, 0.205))
				window(b, Vector3(0.19, py, 0.205))
				window(b, Vector3(0.315, py, -0.06), 0.12, 0.09, true)
				window(b, Vector3(-0.315, py, -0.06), 0.12, 0.09, true)
			window(b, Vector3(0, 0.5, 0.205))
			b.box(Vector3(0.3, 0.025, 0.08), at(Vector3(0, 0.41, 0.24)), Color(1, 1, 1))  # balcony
			flowers(b, Vector3(0.35, 0.0, 0.36), 4, v + 11)
		_:
			b.box(Vector3(0.74, 0.98, 0.7), at(Vector3(0, 0.5, -0.05)), wall)
			b.box(Vector3(0.8, 0.05, 0.76), at(Vector3(0, 1.0, -0.05)), roof)
			b.cylinder(0.09, 0.09, 0.14, at(Vector3(0.2, 1.1, -0.15)), Color(0.6, 0.62, 0.66), 8)
			b.cone(0.1, 0.06, at(Vector3(0.2, 1.2, -0.15)), roof.darkened(0.2), 8)
			if snow:
				b.box(Vector3(0.78, 0.03, 0.74), at(Vector3(0, 1.04, -0.05)), SNOW)
			b.box(Vector3(0.22, 0.2, 0.02), at(Vector3(0, 0.11, 0.305)), WOOD.darkened(0.2))
			b.box(Vector3(0.32, 0.03, 0.12), at(Vector3(0, 0.23, 0.35)), roof)
			for y in [0.38, 0.6, 0.82]:
				var py2: float = y
				for x in [-0.22, 0.0, 0.22]:
					var px: float = x
					window(b, Vector3(px, py2, 0.305), 0.11, 0.1)
				window(b, Vector3(0.375, py2, -0.05), 0.14, 0.1, true)
				window(b, Vector3(-0.375, py2, -0.05), 0.14, 0.1, true)


static func _farm(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(1.96, 0.02, 1.96), at(Vector3(0, 0.01, 0)), Color(0.5, 0.72, 0.36))
	# fields
	b.box(Vector3(0.9, 0.03, 1.7), at(Vector3(0.48, 0.02, 0.0)), Color(0.55, 0.38, 0.24))
	for i in 5:
		var z := -0.68 + i * 0.34
		var col := Color(0.55, 0.85, 0.3) if i % 2 == 0 else Color(0.98, 0.82, 0.3)
		b.rounded_box(Vector3(0.78, 0.07, 0.15), 0.03, at(Vector3(0.48, 0.07, z)), col, 1)
		if i % 2 == 1:
			for k in 4:
				b.sphere(0.035, at(Vector3(0.18 + k * 0.2, 0.12, z)), Color(1.0, 0.55, 0.15), 5)
	# barn
	b.box(Vector3(0.74, 0.5, 0.66), at(Vector3(-0.5, 0.26, -0.3)), Color(0.82, 0.25, 0.22))
	gable(b, 0.84, 0.76, 0.3, 0.51, -0.3, Color(0.42, 0.36, 0.36), snow)
	b.box(Vector3(0.3, 0.32, 0.02), at(Vector3(-0.5, 0.17, 0.035)), Color(0.95, 0.92, 0.85))
	b.box(Vector3(0.26, 0.28, 0.02), at(Vector3(-0.5, 0.17, 0.045)), Color(0.7, 0.2, 0.18))
	b.box(Vector3(0.36, 0.025, 0.025), at(Vector3(-0.5, 0.17, 0.06), Vector3.ONE, Vector3(0, 0, 0.75)), Color(0.95, 0.92, 0.85))
	b.box(Vector3(0.36, 0.025, 0.025), at(Vector3(-0.5, 0.17, 0.06), Vector3.ONE, Vector3(0, 0, -0.75)), Color(0.95, 0.92, 0.85))
	window(b, Vector3(-0.5, 0.42, 0.035), 0.12, 0.08)
	# silo
	b.cylinder(0.16, 0.16, 0.72, at(Vector3(-0.55, 0.36, 0.55)), Color(0.82, 0.84, 0.88), 10)
	b.dome(0.16, at(Vector3(-0.55, 0.72, 0.55)), Color(0.55, 0.6, 0.7), 10)
	# hay bales + fence
	b.cylinder(0.09, 0.09, 0.14, at(Vector3(-0.15, 0.09, 0.55), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.95, 0.82, 0.4), 8)
	b.cylinder(0.09, 0.09, 0.14, at(Vector3(-0.15, 0.09, 0.78), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.92, 0.78, 0.38), 8)
	for i in 6:
		b.box(Vector3(0.03, 0.12, 0.03), at(Vector3(-0.95, 0.06, -0.85 + i * 0.34)), Color(0.95, 0.93, 0.88))
	b.box(Vector3(0.02, 0.025, 1.72), at(Vector3(-0.95, 0.09, 0.0)), Color(0.95, 0.93, 0.88))
	cow_parts(b, Vector3(-0.3, 0.0, 0.55), 0.4, 0.6)


static func _shop(b: MeshKit.Builder, v: int, snow: bool) -> void:
	var cols: Array[Color] = [Color(0.4, 0.78, 0.76), Color(1.0, 0.62, 0.68), Color(1.0, 0.85, 0.42), Color(0.6, 0.72, 1.0), Color(0.72, 0.9, 0.5)]
	var col: Color = cols[v % cols.size()]
	b.box(Vector3(0.96, 0.02, 0.96), at(Vector3(0, 0.01, 0)), Color(0.82, 0.8, 0.76))
	b.box(Vector3(0.72, 0.46, 0.5), at(Vector3(0, 0.25, -0.13)), col)
	b.box(Vector3(0.76, 0.05, 0.54), at(Vector3(0, 0.5, -0.13)), col.darkened(0.25))
	if snow:
		b.box(Vector3(0.74, 0.03, 0.52), at(Vector3(0, 0.54, -0.13)), SNOW)
	b.box(Vector3(0.52, 0.16, 0.02), at(Vector3(0, 0.2, 0.125)), GLASS, true)
	b.box(Vector3(0.12, 0.2, 0.025), at(Vector3(0.27, 0.12, 0.125)), WOOD)
	for i in 6:
		var c := Color(0.95, 0.3, 0.3) if i % 2 == 0 else Color(1, 1, 1)
		b.box(Vector3(0.125, 0.02, 0.2), at(Vector3(-0.31 + i * 0.124, 0.36, 0.2), Vector3.ONE, Vector3(0.38, 0, 0)), c)
	b.rounded_box(Vector3(0.5, 0.11, 0.03), 0.02, at(Vector3(0, 0.6, -0.02)), Color(1, 1, 1), 1)
	b.box(Vector3(0.42, 0.05, 0.01), at(Vector3(0, 0.6, 0.0)), col.darkened(0.3))
	for i in 3:
		b.box(Vector3(0.12, 0.06, 0.1), at(Vector3(-0.25 + i * 0.16, 0.05, 0.36)), WOOD.lightened(0.1))
		var fc: Array[Color] = [Color(0.95, 0.25, 0.2), Color(1.0, 0.8, 0.2), Color(0.45, 0.85, 0.3)]
		for k in 3:
			b.sphere(0.028, at(Vector3(-0.28 + i * 0.16 + k * 0.03, 0.095, 0.36)), fc[i], 5)


static func _bakery(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(0.96, 0.02, 0.96), at(Vector3(0, 0.01, 0)), Color(0.86, 0.82, 0.74))
	b.box(Vector3(0.66, 0.44, 0.54), at(Vector3(0, 0.23, -0.1)), Color(1.0, 0.94, 0.82))
	gable(b, 0.76, 0.64, 0.24, 0.45, -0.1, Color(0.6, 0.38, 0.26), snow)
	b.box(Vector3(0.09, 0.22, 0.09), at(Vector3(-0.18, 0.66, -0.22)), Color(0.72, 0.36, 0.3))
	b.box(Vector3(0.46, 0.15, 0.02), at(Vector3(0.05, 0.2, 0.175)), GLASS, true)
	b.box(Vector3(0.12, 0.2, 0.025), at(Vector3(-0.24, 0.11, 0.175)), WOOD)
	for i in 5:
		var c := Color(0.6, 0.38, 0.24) if i % 2 == 0 else Color(1.0, 0.9, 0.75)
		b.box(Vector3(0.14, 0.02, 0.18), at(Vector3(-0.28 + i * 0.14, 0.35, 0.24), Vector3.ONE, Vector3(0.4, 0, 0)), c)
	# the big golden loaf sign
	b.capsule(0.08, 0.32, at(Vector3(0.0, 0.66, 0.16), Vector3(1, 1, 0.8), Vector3(0, 0, PI * 0.5)), Color(0.95, 0.68, 0.3), 10)
	for k in 3:
		b.box(Vector3(0.02, 0.05, 0.1), at(Vector3(-0.08 + k * 0.08, 0.735, 0.16), Vector3.ONE, Vector3(0, 0, 0.4)), Color(0.85, 0.55, 0.22))


static func _sawmill(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(1.96, 0.02, 1.96), at(Vector3(0, 0.01, 0)), Color(0.62, 0.55, 0.4))
	# open shed
	for p in [Vector2(-0.8, -0.8), Vector2(0.2, -0.8), Vector2(-0.8, 0.05), Vector2(0.2, 0.05)]:
		var pp: Vector2 = p
		b.box(Vector3(0.06, 0.5, 0.06), at(Vector3(pp.x, 0.25, pp.y)), WOOD.darkened(0.2))
	b.box(Vector3(1.15, 0.06, 1.0), at(Vector3(-0.3, 0.53, -0.38), Vector3.ONE, Vector3(0.12, 0, 0)), Color(0.5, 0.35, 0.25))
	if snow:
		b.box(Vector3(1.1, 0.03, 0.95), at(Vector3(-0.3, 0.57, -0.38), Vector3.ONE, Vector3(0.12, 0, 0)), SNOW)
	b.box(Vector3(0.7, 0.14, 0.2), at(Vector3(-0.3, 0.17, -0.38)), WOOD)
	b.cylinder(0.14, 0.14, 0.015, at(Vector3(-0.3, 0.28, -0.38), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.82, 0.85, 0.9), 14)
	# log piles
	for row in 3:
		for k in 4 - row:
			b.cylinder(0.07, 0.07, 0.6, at(Vector3(0.55, 0.08 + row * 0.12, 0.3 + (k - (3 - row) * 0.5) * 0.15), Vector3.ONE, Vector3(0, 0, PI * 0.5)),
				Color(0.62, 0.42, 0.26), 8)
	# planks + office
	for k in 4:
		b.box(Vector3(0.5, 0.03, 0.1), at(Vector3(-0.4, 0.03 + k * 0.035, 0.6)), Color(0.86, 0.7, 0.48))
	b.box(Vector3(0.4, 0.34, 0.34), at(Vector3(0.6, 0.17, -0.55)), Color(0.75, 0.55, 0.36))
	gable(b, 0.48, 0.42, 0.14, 0.34, -0.55, Color(0.45, 0.32, 0.25), snow)
	window(b, Vector3(0.6, 0.2, -0.375))
	b.cylinder(0.05, 0.08, 0.1, at(Vector3(0.2, 0.05, 0.75)), Color(0.55, 0.38, 0.22), 7)


static func _windmill(b: MeshKit.Builder, snow: bool) -> void:
	_yard(b, 1.0)
	b.cylinder(0.17, 0.26, 0.7, at(Vector3(0, 0.37, -0.05)), Color(0.96, 0.94, 0.88), 12)
	b.cone(0.23, 0.22, at(Vector3(0, 0.83, -0.05)), Color(0.75, 0.32, 0.25), 12)
	if snow:
		b.cone(0.18, 0.12, at(Vector3(0, 0.89, -0.05)), SNOW, 12)
	b.box(Vector3(0.1, 0.16, 0.02), at(Vector3(0, 0.1, 0.19)), WOOD)
	window(b, Vector3(0, 0.45, 0.13), 0.07, 0.07)
	b.box(Vector3(0.06, 0.06, 0.12), at(Vector3(0, 0.62, 0.15)), DARK)
	flowers(b, Vector3(0.32, 0.0, 0.3), 4, 21)


## The four sails (origin = hub, they spin around local Z).
static func windmill_sails() -> ArrayMesh:
	return cached("sails", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.sphere(0.05, at(Vector3.ZERO), DARK, 8)
		for k in 4:
			var a := k * PI * 0.5
			var dir := Vector3(cos(a), sin(a), 0.0)
			var rot := Vector3(0, 0, a - PI * 0.5)
			b.box(Vector3(0.025, 0.42, 0.02), at(dir * 0.23, Vector3.ONE, rot), WOOD)
			b.box(Vector3(0.1, 0.32, 0.008), at(dir * 0.27 + Vector3(0, 0, -0.005), Vector3.ONE, rot), Color(1.0, 0.98, 0.94))
		return b.build())


static func _water_tower(b: MeshKit.Builder) -> void:
	_yard(b, 1.0)
	for p in [Vector2(-0.17, -0.17), Vector2(0.17, -0.17), Vector2(-0.17, 0.17), Vector2(0.17, 0.17)]:
		var pp: Vector2 = p
		b.tube(Vector3(pp.x * 1.2, 0.0, pp.y * 1.2), Vector3(pp.x, 0.48, pp.y), 0.025, 0.02, Color(0.55, 0.58, 0.64), 6)
	b.box(Vector3(0.44, 0.025, 0.025), at(Vector3(0, 0.25, 0.19)), Color(0.55, 0.58, 0.64))
	b.cylinder(0.25, 0.25, 0.28, at(Vector3(0, 0.62, 0)), Color(0.5, 0.75, 0.95), 14)
	b.dome(0.25, at(Vector3(0, 0.76, 0), Vector3(1, 0.5, 1)), Color(0.4, 0.62, 0.86), 14)
	b.torus(0.255, 0.012, at(Vector3(0, 0.5, 0)), Color(1, 1, 1), 16, 4)
	b.sphere(0.06, at(Vector3(0, 0.6, 0.245), Vector3(1, 1, 0.4)), Color(1, 1, 1), 8)
	b.cone(0.06, 0.08, at(Vector3(0, 0.67, 0.245), Vector3(1, 1, 0.4)), Color(1, 1, 1), 8)


static func _school(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(1.96, 0.02, 1.96), at(Vector3(0, 0.01, 0)), Color(0.55, 0.78, 0.42))
	var brick := Color(0.9, 0.52, 0.36)
	b.box(Vector3(1.5, 0.55, 0.7), at(Vector3(0, 0.29, -0.45)), brick)
	gable(b, 1.6, 0.8, 0.2, 0.56, -0.45, Color(0.35, 0.42, 0.55), snow)
	b.box(Vector3(1.52, 0.04, 0.72), at(Vector3(0, 0.03, -0.45)), Color(0.95, 0.95, 0.92))
	for x in [-0.55, -0.3, 0.3, 0.55]:
		var px: float = x
		window(b, Vector3(px, 0.2, -0.095), 0.14, 0.1)
		window(b, Vector3(px, 0.42, -0.095), 0.14, 0.1)
	b.box(Vector3(0.22, 0.26, 0.03), at(Vector3(0, 0.14, -0.09)), Color(0.35, 0.55, 0.85))
	# bell tower + clock
	b.box(Vector3(0.3, 0.32, 0.3), at(Vector3(0, 0.88, -0.45)), Color(0.96, 0.94, 0.88))
	b.cone(0.24, 0.24, at(Vector3(0, 1.16, -0.45)), Color(0.35, 0.42, 0.55), 4)
	b.sphere(0.06, at(Vector3(0, 0.84, -0.45)), Color(1.0, 0.82, 0.3), 8)
	b.disc(0.08, at(Vector3(0, 0.95, -0.295), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1, 1, 1), 12, false, true)
	b.box(Vector3(0.012, 0.06, 0.01), at(Vector3(0, 0.97, -0.29)), DARK)
	b.box(Vector3(0.045, 0.012, 0.01), at(Vector3(0.02, 0.95, -0.29)), DARK)
	# playground: slide, swings, sandpit, flag
	b.wedge(Vector3(0.18, 0.2, 0.42), at(Vector3(0.6, 0.1, 0.45)), Color(1.0, 0.4, 0.4))
	b.box(Vector3(0.2, 0.22, 0.12), at(Vector3(0.6, 0.11, 0.2)), Color(0.4, 0.7, 1.0))
	b.tube(Vector3(-0.75, 0, 0.3), Vector3(-0.65, 0.3, 0.3), 0.015, 0.015, Color(1.0, 0.75, 0.2), 5)
	b.tube(Vector3(-0.25, 0, 0.3), Vector3(-0.35, 0.3, 0.3), 0.015, 0.015, Color(1.0, 0.75, 0.2), 5)
	b.box(Vector3(0.35, 0.02, 0.02), at(Vector3(-0.5, 0.3, 0.3)), Color(1.0, 0.75, 0.2))
	for x in [-0.58, -0.42]:
		var sx: float = x
		b.box(Vector3(0.008, 0.18, 0.008), at(Vector3(sx, 0.2, 0.3)), DARK)
		b.box(Vector3(0.07, 0.015, 0.05), at(Vector3(sx, 0.11, 0.3)), Color(0.4, 0.8, 0.4))
	b.box(Vector3(0.4, 0.03, 0.3), at(Vector3(0.0, 0.025, 0.65)), Color(0.98, 0.9, 0.6))
	b.cylinder(0.012, 0.012, 0.8, at(Vector3(0.9, 0.4, -0.05)), Color(0.85, 0.85, 0.88), 5)
	b.box(Vector3(0.18, 0.12, 0.01), at(Vector3(0.81, 0.72, -0.05)), Color(0.3, 0.6, 1.0))
	tree_ball(b, Vector3(-0.85, 0, 0.8), 0.12, Color(0.38, 0.7, 0.32))


static func _park(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(0.98, 0.025, 0.98), at(Vector3(0, 0.0125, 0)), SNOW.lerp(GARDEN, 0.3) if snow else Color(0.45, 0.8, 0.38))
	b.cylinder(0.2, 0.22, 0.06, at(Vector3(0, 0.05, 0.05)), STONE, 14)
	b.cylinder(0.17, 0.17, 0.01, at(Vector3(0, 0.08, 0.05)), Color(0.4, 0.75, 1.0), 14)
	b.cylinder(0.03, 0.04, 0.12, at(Vector3(0, 0.12, 0.05)), STONE, 8)
	b.sphere(0.04, at(Vector3(0, 0.2, 0.05)), Color(0.55, 0.85, 1.0), 8)
	var leaf := Color(0.95, 0.97, 1.0) if snow else Color(0.35, 0.7, 0.32)
	tree_ball(b, Vector3(-0.3, 0, -0.3), 0.14, leaf)
	tree_ball(b, Vector3(0.32, 0, -0.28), 0.12, leaf.lightened(0.08) if not snow else leaf)
	b.box(Vector3(0.2, 0.025, 0.06), at(Vector3(0.3, 0.07, 0.34)), WOOD)
	b.box(Vector3(0.2, 0.06, 0.015), at(Vector3(0.3, 0.1, 0.37)), WOOD)
	b.box(Vector3(0.02, 0.06, 0.05), at(Vector3(0.22, 0.035, 0.34)), DARK)
	b.box(Vector3(0.02, 0.06, 0.05), at(Vector3(0.38, 0.035, 0.34)), DARK)
	flowers(b, Vector3(-0.32, 0.0, 0.33), 5, 77)
	flowers(b, Vector3(0.05, 0.0, -0.4), 4, 78)


static func _fire_station(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(0.96, 0.02, 0.96), at(Vector3(0, 0.01, 0)), Color(0.8, 0.78, 0.76))
	var red := Color(0.85, 0.22, 0.2)
	b.box(Vector3(0.66, 0.46, 0.56), at(Vector3(0.06, 0.24, -0.1)), red)
	b.box(Vector3(0.7, 0.05, 0.6), at(Vector3(0.06, 0.49, -0.1)), Color(0.3, 0.3, 0.32))
	if snow:
		b.box(Vector3(0.68, 0.03, 0.58), at(Vector3(0.06, 0.53, -0.1)), SNOW)
	b.box(Vector3(0.36, 0.3, 0.02), at(Vector3(0.12, 0.16, 0.185)), Color(0.92, 0.92, 0.95))
	for k in 4:
		b.box(Vector3(0.36, 0.012, 0.01), at(Vector3(0.12, 0.05 + k * 0.07, 0.197)), Color(0.7, 0.72, 0.78))
	window(b, Vector3(-0.17, 0.38, 0.185), 0.1, 0.07)
	window(b, Vector3(0.12, 0.4, 0.185), 0.2, 0.06)
	b.box(Vector3(0.2, 0.78, 0.2), at(Vector3(-0.32, 0.39, -0.3)), red.darkened(0.12))
	b.box(Vector3(0.24, 0.04, 0.24), at(Vector3(-0.32, 0.8, -0.3)), Color(0.3, 0.3, 0.32))
	b.sphere(0.05, at(Vector3(-0.32, 0.86, -0.3)), Color(1.0, 0.3, 0.2), 8)
	b.disc(0.06, at(Vector3(-0.32, 0.65, -0.195), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.85, 0.3), 10)


static func _station(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(1.96, 0.02, 1.96), at(Vector3(0, 0.01, 0)), Color(0.78, 0.76, 0.72))
	b.box(Vector3(1.9, 0.07, 0.5), at(Vector3(0, 0.035, -0.7)), Color(0.86, 0.82, 0.74))
	b.box(Vector3(1.9, 0.02, 0.05), at(Vector3(0, 0.075, -0.93)), Color(1.0, 0.85, 0.2))
	for x in [-0.75, -0.25, 0.25, 0.75]:
		var px: float = x
		b.cylinder(0.02, 0.02, 0.36, at(Vector3(px, 0.25, -0.6)), Color(0.35, 0.45, 0.5), 6)
	b.box(Vector3(1.8, 0.04, 0.42), at(Vector3(0, 0.45, -0.68), Vector3.ONE, Vector3(-0.1, 0, 0)), Color(0.3, 0.55, 0.45))
	if snow:
		b.box(Vector3(1.76, 0.025, 0.4), at(Vector3(0, 0.48, -0.68), Vector3.ONE, Vector3(-0.1, 0, 0)), SNOW)
	b.box(Vector3(0.9, 0.42, 0.55), at(Vector3(0, 0.22, 0.05)), Color(0.95, 0.85, 0.7))
	gable(b, 1.0, 0.65, 0.22, 0.43, 0.05, Color(0.3, 0.55, 0.45), snow)
	b.box(Vector3(0.18, 0.24, 0.02), at(Vector3(0, 0.13, 0.33)), WOOD.darkened(0.2))
	window(b, Vector3(-0.3, 0.22, 0.33), 0.14, 0.12)
	window(b, Vector3(0.3, 0.22, 0.33), 0.14, 0.12)
	b.disc(0.09, at(Vector3(0, 0.52, 0.31), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1, 1, 1), 12, false, true)
	b.box(Vector3(0.012, 0.07, 0.01), at(Vector3(0, 0.54, 0.32)), DARK)
	for x in [-0.5, 0.5]:
		var bx: float = x
		b.box(Vector3(0.22, 0.03, 0.07), at(Vector3(bx, 0.11, -0.75)), WOOD)


static func _clock_tower(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(1.96, 0.03, 1.96), at(Vector3(0, 0.015, 0)), Color(0.86, 0.84, 0.78))
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		flowers(b, Vector3(cos(a) * 0.72, 0.0, sin(a) * 0.72), 6, 90 + k)
	b.box(Vector3(0.75, 0.18, 0.75), at(Vector3(0, 0.12, 0)), STONE.darkened(0.1))
	b.box(Vector3(0.55, 1.5, 0.55), at(Vector3(0, 0.95, 0)), Color(0.94, 0.88, 0.74))
	b.box(Vector3(0.62, 0.06, 0.62), at(Vector3(0, 1.7, 0)), STONE)
	for k in 4:
		var rot := Vector3(0, k * PI * 0.5, 0)
		var dir := Vector3(sin(k * PI * 0.5), 0, cos(k * PI * 0.5))
		b.disc(0.19, Transform3D(Basis.from_euler(rot) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.42, 0) + dir * 0.28), Color(1.0, 0.97, 0.88), 16, false, true)
		b.box(Vector3(0.02, 0.13, 0.01), Transform3D(Basis.from_euler(rot), Vector3(0, 1.47, 0) + dir * 0.285), DARK)
		b.box(Vector3(0.1, 0.02, 0.01), Transform3D(Basis.from_euler(rot), Vector3(0.03, 1.42, 0) + dir * 0.285), DARK)
		window(b, Vector3(0, 0.75, 0) + dir * 0.28, 0.12, 0.2, k % 2 == 1)
	b.cone(0.45, 0.6, at(Vector3(0, 2.03, 0), Vector3.ONE, Vector3(0, PI * 0.25, 0)), Color(0.35, 0.7, 0.6), 4)
	if snow:
		b.cone(0.3, 0.3, at(Vector3(0, 2.13, 0), Vector3.ONE, Vector3(0, PI * 0.25, 0)), SNOW, 4)
	b.sphere(0.07, at(Vector3(0, 2.38, 0)), Color(1.0, 0.82, 0.3), 8)


static func _ferris_base(b: MeshKit.Builder) -> void:
	b.box(Vector3(1.96, 0.03, 1.96), at(Vector3(0, 0.015, 0)), Color(0.85, 0.8, 0.9))
	var steel := Color(0.85, 0.85, 0.92)
	for x in [-0.22, 0.22]:
		var px: float = x
		b.tube(Vector3(px, 0.0, -0.55), Vector3(px, 1.0, 0.0), 0.03, 0.025, steel, 6)
		b.tube(Vector3(px, 0.0, 0.55), Vector3(px, 1.0, 0.0), 0.03, 0.025, steel, 6)
	b.box(Vector3(0.6, 0.12, 0.3), at(Vector3(0.0, 0.06, 0.75)), Color(1.0, 0.45, 0.55))
	b.box(Vector3(0.6, 0.03, 0.32), at(Vector3(0.0, 0.14, 0.75)), Color(1.0, 0.9, 0.4))
	for k in 6:
		b.sphere(0.02, at(Vector3(-0.25 + k * 0.1, 0.17, 0.92)), Color(1.0, 0.95, 0.6), 5, true)


## The big wheel (spins around local X at its hub, 1.0 above the ground).
static func ferris_wheel() -> ArrayMesh:
	return cached("wheel", func() -> Resource:
		var b := MeshKit.Builder.new()
		var ring := Color(1.0, 0.5, 0.6)
		b.torus(0.78, 0.025, at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI * 0.5)), ring, 24, 5)
		b.cylinder(0.06, 0.06, 0.5, at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.9, 0.9, 0.95), 8)
		var cars: Array[Color] = [Color(0.4, 0.7, 1.0), Color(1.0, 0.8, 0.3), Color(0.5, 0.9, 0.5), Color(0.8, 0.5, 1.0)]
		for k in 8:
			var a := k * TAU / 8.0
			var p := Vector3(0.0, sin(a), cos(a)) * 0.78
			b.tube(Vector3.ZERO, p, 0.012, 0.012, Color(1, 1, 1), 4)
			b.rounded_box(Vector3(0.14, 0.12, 0.14), 0.03, at(p + Vector3(0, -0.08, 0)), cars[k % 4], 1)
			b.sphere(0.018, at(p), Color(1.0, 0.95, 0.6), 5, true)
		return b.build(null, lamp_mat()))


static func _town_hall(b: MeshKit.Builder, snow: bool) -> void:
	b.box(Vector3(1.96, 0.025, 1.96), at(Vector3(0, 0.0125, 0)), Color(0.86, 0.84, 0.8))
	var cream := Color(0.98, 0.94, 0.84)
	b.box(Vector3(1.3, 0.6, 0.85), at(Vector3(0, 0.33, -0.3)), cream)
	b.box(Vector3(1.38, 0.06, 0.93), at(Vector3(0, 0.65, -0.3)), Color(0.85, 0.8, 0.7))
	for k in 3:
		b.box(Vector3(0.7 - k * 0.04, 0.03, 0.1), at(Vector3(0, 0.015 + k * 0.03, 0.23 - k * 0.05)), STONE.lightened(0.1))
	for x in [-0.28, -0.1, 0.1, 0.28]:
		var px: float = x
		b.cylinder(0.035, 0.04, 0.5, at(Vector3(px, 0.34, 0.1)), Color(1, 1, 1), 8)
	b.wedge(Vector3(0.75, 0.16, 0.18), at(Vector3(0, 0.68, 0.06), Vector3.ONE, Vector3(0, PI, 0)), Color(0.95, 0.9, 0.8))
	b.box(Vector3(0.76, 0.06, 0.24), at(Vector3(0, 0.62, 0.06)), Color(0.95, 0.9, 0.8))
	b.cylinder(0.24, 0.26, 0.16, at(Vector3(0, 0.76, -0.3)), cream, 14)
	b.dome(0.24, at(Vector3(0, 0.84, -0.3)), Color(0.35, 0.65, 0.75) if not snow else SNOW, 14)
	b.cylinder(0.01, 0.01, 0.3, at(Vector3(0, 1.2, -0.3)), Color(0.9, 0.9, 0.9), 5)
	b.box(Vector3(0.16, 0.1, 0.01), at(Vector3(0.08, 1.3, -0.3)), Color(0.3, 0.6, 1.0))
	b.box(Vector3(0.18, 0.24, 0.02), at(Vector3(0, 0.2, 0.13)), WOOD.darkened(0.25))
	for x in [-0.5, -0.38, 0.38, 0.5]:
		var wx: float = x
		window(b, Vector3(wx, 0.25, 0.13), 0.09, 0.12)
		window(b, Vector3(wx, 0.48, 0.13), 0.09, 0.1)
	b.disc(0.08, at(Vector3(0, 0.78, -0.055), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1, 1, 1), 12, false, true)
	# builders' yard with brick pallets
	for k in 3:
		b.box(Vector3(0.22, 0.03, 0.22), at(Vector3(-0.7 + k * 0.26, 0.04, 0.72)), WOOD)
		for h in 3 - k % 2:
			b.box(Vector3(0.18, 0.05, 0.18), at(Vector3(-0.7 + k * 0.26, 0.08 + h * 0.055, 0.72)), Color(0.85, 0.42, 0.32))
	flowers(b, Vector3(0.6, 0.0, 0.6), 6, 55)
	flowers(b, Vector3(0.85, 0.0, 0.3), 5, 56)


## A cow made of parts (shared by the farm's paddock and the stray cow event).
static func cow_parts(b: MeshKit.Builder, p: Vector3, s: float, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), p)
	var white := Color(0.98, 0.97, 0.95)
	var black := Color(0.15, 0.13, 0.13)
	b.ellipsoid(Vector3(0.2, 0.14, 0.3), xf * at(Vector3(0, 0.28, 0)), white, 10)
	b.sphere(0.07, xf * at(Vector3(0.12, 0.33, 0.05)), black, 6)
	b.sphere(0.06, xf * at(Vector3(-0.1, 0.3, -0.12)), black, 6)
	b.rounded_box(Vector3(0.16, 0.16, 0.2), 0.05, xf * at(Vector3(0, 0.36, 0.33)), white, 1)
	b.rounded_box(Vector3(0.14, 0.08, 0.06), 0.03, xf * at(Vector3(0, 0.31, 0.44)), Color(1.0, 0.7, 0.72), 1)
	b.cone(0.025, 0.07, xf * at(Vector3(0.06, 0.47, 0.32)), Color(0.95, 0.9, 0.7), 5)
	b.cone(0.025, 0.07, xf * at(Vector3(-0.06, 0.47, 0.32)), Color(0.95, 0.9, 0.7), 5)
	for q in [Vector2(0.1, 0.17), Vector2(-0.1, 0.17), Vector2(0.1, -0.17), Vector2(-0.1, -0.17)]:
		var qq: Vector2 = q
		b.cylinder(0.035, 0.035, 0.18, xf * at(Vector3(qq.x, 0.09, qq.y)), white, 6)


static func cow_mesh() -> ArrayMesh:
	return cached("cow", func() -> Resource:
		var b := MeshKit.Builder.new()
		cow_parts(b, Vector3.ZERO, 1.0, 0.0)
		return b.build())


# --- Roads, rails, lamps --------------------------------------------------------------------------------

## Road / rail shapes for a neighbour mask: [shape name, quarter turns]. Shapes are built for one
## canonical mask: end = S, straight = N+S, curve = S+E, tee = S+E+W, cross = all, dot = none.
const CANON := {"dot": 0, "end": 4, "straight": 5, "curve": 6, "tee": 14, "cross": 15}


static func rot_mask(m: int, k: int) -> int:
	var out := m
	for i in k:
		var nm := 0
		if out & 4:
			nm |= 2  # S -> E
		if out & 2:
			nm |= 1  # E -> N
		if out & 1:
			nm |= 8  # N -> W
		if out & 8:
			nm |= 4  # W -> S
		out = nm
	return out


static func shape_for(mask: int) -> Array:
	for shape in CANON:
		var cm: int = CANON[shape]
		for k in 4:
			if rot_mask(cm, k) == mask:
				return [String(shape), k]
	return ["dot", 0]


const ASPHALT := Color(0.36, 0.37, 0.41)
const KERB := Color(0.82, 0.8, 0.75)


## Flat quad strip helper: a convex outline (x, z points) as a thin slab at height y.
static func _slab(b: MeshKit.Builder, pts: Array, y: float, h: float, col: Color) -> void:
	var outline := PackedVector2Array()
	for p in pts:
		var v: Vector2 = p
		outline.append(Vector2(v.x, -v.y))
	b.polygon(outline, h, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, y, 0.0)), col)


## Arc band from angle a0 to a1 around centre c (x, z), radii r0..r1, as `segs` quads.
static func _arc(b: MeshKit.Builder, c: Vector2, r0: float, r1: float, a0: float, a1: float, segs: int, y: float, h: float, col: Color) -> void:
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / segs)
		var t1 := lerpf(a0, a1, float(i + 1) / segs)
		var d0 := Vector2(cos(t0), sin(t0))
		var d1 := Vector2(cos(t1), sin(t1))
		_slab(b, [c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d1 * r0], y, h, col)


static func road_mesh(shape: String) -> ArrayMesh:
	return cached("road_" + shape, func() -> Resource: return _make_road(shape))


static func _make_road(shape: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var w := 0.31  # half the asphalt width
	var y := 0.022
	b.box(Vector3(1.0, 0.02, 1.0), at(Vector3(0, 0.01, 0)), KERB)
	var dash := Color(1.0, 0.98, 0.9)
	match shape:
		"dot":
			b.cylinder(0.36, 0.36, 0.012, at(Vector3(0, y + 0.006, 0)), ASPHALT, 16)
			b.cylinder(0.12, 0.12, 0.014, at(Vector3(0, y + 0.008, 0)), Color(0.5, 0.8, 0.4), 12)
		"end":
			b.box(Vector3(w * 2.0, 0.012, 0.5), at(Vector3(0, y + 0.006, 0.25)), ASPHALT)
			b.cylinder(w, w, 0.012, at(Vector3(0, y + 0.006, 0)), ASPHALT, 14)
			b.box(Vector3(0.03, 0.004, 0.14), at(Vector3(0, y + 0.014, 0.33)), dash)
		"straight":
			b.box(Vector3(w * 2.0, 0.012, 1.0), at(Vector3(0, y + 0.006, 0)), ASPHALT)
			for k in 3:
				b.box(Vector3(0.03, 0.004, 0.14), at(Vector3(0, y + 0.014, -0.33 + k * 0.33)), dash)
		"curve":
			# S + E: an arc around the south-east corner (0.5, 0.5)
			_arc(b, Vector2(0.5, 0.5), 0.5 - w, 0.5 + w, PI, PI * 1.5, 7, y + 0.006, 0.012, ASPHALT)
			for k in 3:
				var a := PI + (k + 0.5) / 3.0 * PI * 0.5
				var p := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.5
				b.box(Vector3(0.03, 0.004, 0.11), at(Vector3(p.x, y + 0.014, p.y), Vector3.ONE, Vector3(0, -a, 0)), dash)
		"tee":
			b.box(Vector3(1.0, 0.012, w * 2.0), at(Vector3(0, y + 0.006, 0)), ASPHALT)
			b.box(Vector3(w * 2.0, 0.012, 0.5), at(Vector3(0, y + 0.006, 0.25)), ASPHALT)
			b.box(Vector3(0.6, 0.004, 0.05), at(Vector3(0, y + 0.014, -w + 0.04)), Color(1, 1, 1))
		"cross":
			b.box(Vector3(1.0, 0.012, w * 2.0), at(Vector3(0, y + 0.006, 0)), ASPHALT)
			b.box(Vector3(w * 2.0, 0.012, 1.0), at(Vector3(0, y + 0.006, 0)), ASPHALT)
			for k in 4:
				var off := -0.21 + k * 0.14
				b.box(Vector3(0.07, 0.004, 0.13), at(Vector3(off, y + 0.014, 0.4)), Color(1, 1, 1))
				b.box(Vector3(0.07, 0.004, 0.13), at(Vector3(off, y + 0.014, -0.4)), Color(1, 1, 1))
	return b.build()


static func rail_mesh(shape: String) -> ArrayMesh:
	return cached("rail_" + shape, func() -> Resource: return _make_rail(shape))


static func _make_rail(shape: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var gravel := Color(0.62, 0.58, 0.54)
	var sleeper := Color(0.45, 0.3, 0.2)
	var steel := Color(0.72, 0.74, 0.8)
	var g := 0.11  # half gauge
	match shape:
		"straight", "end", "dot":
			var z0 := -0.5 if shape == "straight" else -0.15
			var z1 := 0.5
			b.box(Vector3(0.44, 0.02, z1 - z0), at(Vector3(0, 0.01, (z0 + z1) * 0.5)), gravel)
			var n := int((z1 - z0) / 0.14)
			for k in n:
				b.box(Vector3(0.36, 0.016, 0.06), at(Vector3(0, 0.026, z0 + 0.07 + k * 0.14)), sleeper)
			for sx in [-g, g]:
				var px: float = sx
				b.box(Vector3(0.025, 0.025, z1 - z0), at(Vector3(px, 0.04, (z0 + z1) * 0.5)), steel)
			if shape != "straight":
				b.box(Vector3(0.36, 0.08, 0.05), at(Vector3(0, 0.05, z0)), Color(0.9, 0.3, 0.25))
		"curve":
			_arc(b, Vector2(0.5, 0.5), 0.28, 0.72, PI, PI * 1.5, 7, 0.01, 0.02, gravel)
			for k in 6:
				var a := PI + (k + 0.5) / 6.0 * PI * 0.5
				var p := Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.5
				b.box(Vector3(0.36, 0.016, 0.06), at(Vector3(p.x, 0.026, p.y), Vector3.ONE, Vector3(0, -a, 0)), sleeper)
			_arc(b, Vector2(0.5, 0.5), 0.5 - g - 0.0125, 0.5 - g + 0.0125, PI, PI * 1.5, 7, 0.04, 0.025, steel)
			_arc(b, Vector2(0.5, 0.5), 0.5 + g - 0.0125, 0.5 + g + 0.0125, PI, PI * 1.5, 7, 0.04, 0.025, steel)
		_:  # tee / cross: a plain junction plate
			b.box(Vector3(0.9, 0.02, 0.9), at(Vector3(0, 0.01, 0)), gravel)
			for k in 6:
				b.box(Vector3(0.36, 0.016, 0.06), at(Vector3(0, 0.026, -0.42 + k * 0.17)), sleeper)
				b.box(Vector3(0.06, 0.016, 0.36), at(Vector3(-0.42 + k * 0.17, 0.026, 0)), sleeper)
			for sx in [-g, g]:
				var px2: float = sx
				b.box(Vector3(0.025, 0.025, 1.0), at(Vector3(px2, 0.04, 0)), steel)
				b.box(Vector3(1.0, 0.025, 0.025), at(Vector3(0, 0.04, px2)), steel)
	return b.build()


## Level crossing: rails set into a road (drawn on top of the road tile).
static func crossing_mesh() -> ArrayMesh:
	return cached("crossing", func() -> Resource:
		var b := MeshKit.Builder.new()
		for sx in [-0.11, 0.11]:
			var px: float = sx
			b.box(Vector3(0.025, 0.01, 1.0), at(Vector3(px, 0.04, 0)), Color(0.75, 0.77, 0.82))
		for k in 5:
			b.box(Vector3(0.06, 0.006, 0.12), at(Vector3(-0.3 + k * 0.15, 0.038, 0.42)), Color(1, 1, 1))
		return b.build())


## A street lamp (head glows at night through lamp_mat).
static func lamp_mesh() -> ArrayMesh:
	return cached("lamp", func() -> Resource:
		var b := MeshKit.Builder.new()
		var iron := Color(0.24, 0.26, 0.32)
		b.cylinder(0.012, 0.016, 0.4, at(Vector3(0, 0.2, 0)), iron, 6)
		b.box(Vector3(0.012, 0.012, 0.08), at(Vector3(0, 0.4, 0.035)), iron)
		b.sphere(0.03, at(Vector3(0, 0.385, 0.075)), Color(1.0, 0.92, 0.65), 6, true)
		return b.build(null, lamp_mat()))


# --- Vehicles ---------------------------------------------------------------------------------------------

## A vehicle body (front +Z, cell units: about 0.8 long). `accent` = the driver's colour (flag).
static func vehicle_mesh(kind: String, accent: Color) -> ArrayMesh:
	return cached("veh_%s_%s" % [kind, accent.to_html(false)], func() -> Resource: return _make_vehicle(kind, accent))


static func _wheels(b: MeshKit.Builder, zs: Array, half_w: float) -> void:
	for z in zs:
		var pz: float = z
		for sx in [-half_w, half_w]:
			var px: float = sx
			b.cylinder(0.075, 0.075, 0.06, at(Vector3(px, 0.075, pz), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.15, 0.15, 0.17), 10)
			b.cylinder(0.035, 0.035, 0.065, at(Vector3(px, 0.075, pz), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.85, 0.85, 0.88), 8)


static func _flag(b: MeshKit.Builder, p: Vector3, accent: Color) -> void:
	b.cylinder(0.008, 0.008, 0.2, at(p + Vector3(0, 0.1, 0)), Color(0.9, 0.9, 0.9), 4)
	b.box(Vector3(0.01, 0.07, 0.1), at(p + Vector3(0, 0.17, -0.05)), accent)


static func _make_vehicle(kind: String, accent: Color) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var col: Color = Defs.V.get(kind, {}).get("color", Color(0.8, 0.8, 0.8))
	var glass := Color(0.55, 0.78, 0.95)
	match kind:
		"truck":
			b.rounded_box(Vector3(0.36, 0.26, 0.24), 0.05, at(Vector3(0, 0.2, 0.25)), col, 2)
			b.box(Vector3(0.3, 0.1, 0.02), at(Vector3(0, 0.25, 0.37)), glass)
			b.rounded_box(Vector3(0.4, 0.32, 0.46), 0.03, at(Vector3(0, 0.25, -0.12)), Color(0.97, 0.96, 0.92), 1)
			b.box(Vector3(0.41, 0.06, 0.4), at(Vector3(0, 0.25, -0.12)), col)
			b.box(Vector3(0.06, 0.03, 0.02), at(Vector3(0.12, 0.13, 0.37)), Color(1.0, 0.95, 0.7), true)
			b.box(Vector3(0.06, 0.03, 0.02), at(Vector3(-0.12, 0.13, 0.37)), Color(1.0, 0.95, 0.7), true)
			_wheels(b, [0.24, -0.24], 0.19)
			_flag(b, Vector3(0.12, 0.33, 0.25), accent)
		"bus":
			b.rounded_box(Vector3(0.4, 0.34, 0.86), 0.06, at(Vector3(0, 0.24, 0)), col, 2)
			b.box(Vector3(0.41, 0.09, 0.7), at(Vector3(0, 0.3, -0.02)), glass)
			b.box(Vector3(0.32, 0.1, 0.02), at(Vector3(0, 0.3, 0.43)), glass)
			b.box(Vector3(0.41, 0.03, 0.8), at(Vector3(0, 0.17, 0)), Color(0.95, 0.4, 0.3))
			b.box(Vector3(0.2, 0.05, 0.02), at(Vector3(0, 0.38, 0.435)), Color(1.0, 0.6, 0.2), true)
			_wheels(b, [0.28, -0.28], 0.2)
			_flag(b, Vector3(0.14, 0.41, -0.3), accent)
		"fire":
			b.rounded_box(Vector3(0.38, 0.28, 0.82), 0.05, at(Vector3(0, 0.21, 0)), col, 2)
			b.box(Vector3(0.3, 0.09, 0.02), at(Vector3(0, 0.27, 0.41)), glass)
			for sx in [-0.1, 0.1]:
				var px: float = sx
				b.box(Vector3(0.02, 0.02, 0.6), at(Vector3(px, 0.38, -0.08)), Color(0.85, 0.85, 0.9))
			for k in 6:
				b.box(Vector3(0.2, 0.015, 0.015), at(Vector3(0, 0.38, -0.34 + k * 0.1)), Color(0.85, 0.85, 0.9))
			b.box(Vector3(0.14, 0.05, 0.06), at(Vector3(0, 0.37, 0.3)), Color(0.3, 0.5, 1.0), true)
			b.box(Vector3(0.39, 0.04, 0.6), at(Vector3(0, 0.15, -0.08)), Color(1, 1, 1))
			b.cylinder(0.06, 0.06, 0.1, at(Vector3(0.0, 0.2, -0.42), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.85, 0.3), 8)
			_wheels(b, [0.27, -0.27], 0.19)
			_flag(b, Vector3(-0.14, 0.35, 0.25), accent)
		"crane":
			b.rounded_box(Vector3(0.38, 0.16, 0.8), 0.04, at(Vector3(0, 0.15, 0)), Color(0.35, 0.35, 0.38), 1)
			b.rounded_box(Vector3(0.3, 0.22, 0.2), 0.04, at(Vector3(0, 0.33, 0.26)), col, 1)
			b.box(Vector3(0.25, 0.08, 0.02), at(Vector3(0, 0.36, 0.36)), glass)
			b.box(Vector3(0.28, 0.12, 0.3), at(Vector3(0, 0.3, -0.12)), col)
			b.box(Vector3(0.06, 0.06, 0.62), at(Vector3(0.0, 0.52, -0.05), Vector3.ONE, Vector3(-0.55, 0, 0)), col.darkened(0.1))
			b.box(Vector3(0.2, 0.04, 0.2), at(Vector3(0, 0.25, -0.32)), Color(0.85, 0.42, 0.32))
			_wheels(b, [0.27, 0.0, -0.27], 0.19)
			_flag(b, Vector3(0.12, 0.44, 0.26), accent)
		"police":
			b.rounded_box(Vector3(0.36, 0.14, 0.66), 0.05, at(Vector3(0, 0.14, 0)), Color(0.96, 0.96, 0.98), 2)
			b.rounded_box(Vector3(0.3, 0.13, 0.32), 0.05, at(Vector3(0, 0.26, -0.03)), col, 2)
			b.box(Vector3(0.31, 0.07, 0.25), at(Vector3(0, 0.27, -0.03)), glass)
			b.box(Vector3(0.37, 0.04, 0.4), at(Vector3(0, 0.12, 0)), col)
			b.box(Vector3(0.08, 0.04, 0.06), at(Vector3(-0.05, 0.345, -0.03)), Color(1.0, 0.25, 0.2), true)
			b.box(Vector3(0.08, 0.04, 0.06), at(Vector3(0.05, 0.345, -0.03)), Color(0.25, 0.45, 1.0), true)
			_wheels(b, [0.2, -0.2], 0.18)
			_flag(b, Vector3(0.12, 0.33, -0.2), accent)
	return b.build()


## Cargo crates on a truck / bundle on the crane (one per resource).
static func cargo_mesh(res: String) -> ArrayMesh:
	return cached("cargo_" + res, func() -> Resource:
		var b := MeshKit.Builder.new()
		var c: Color = Defs.RES_COLORS.get(res, Color(0.8, 0.8, 0.8))
		match res:
			"wood":
				for k in 3:
					b.cylinder(0.045, 0.045, 0.32, at(Vector3(-0.05 + k * 0.05, 0.05 + (k % 2) * 0.04, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), c, 8)
			"bricks":
				for k in 4:
					b.box(Vector3(0.09, 0.05, 0.14), at(Vector3(-0.05 + (k % 2) * 0.1, 0.03 + floorf(k * 0.5) * 0.055, 0)), c)
			"people":
				for k in 3:
					b.sphere(0.04, at(Vector3(-0.1 + k * 0.1, 0.05, 0)), Color(1.0, 0.85, 0.7), 6)
			_:
				for k in 2:
					b.box(Vector3(0.14, 0.1, 0.14), at(Vector3(-0.08 + k * 0.16, 0.05, 0)), WOOD.lightened(0.15))
					b.sphere(0.04, at(Vector3(-0.08 + k * 0.16, 0.11, 0)), c, 6)
		return b.build())


# --- Tray pieces (VR) and little things ---------------------------------------------------------------------

## A tray model for a tool (road, rail, bulldozer); buildings use building_mesh.
static func tool_mesh(kind: String) -> ArrayMesh:
	return cached("tool_" + kind, func() -> Resource:
		var b := MeshKit.Builder.new()
		match kind:
			"road":
				b.add_mesh(road_mesh("curve"), at(Vector3(0, 0, 0)))
				b.box(Vector3(0.03, 0.3, 0.03), at(Vector3(-0.3, 0.15, -0.3)), Color(0.85, 0.85, 0.88))
				b.box(Vector3(0.2, 0.12, 0.02), at(Vector3(-0.3, 0.32, -0.3)), Color(0.3, 0.6, 1.0))
			"rail":
				b.add_mesh(rail_mesh("curve"), at(Vector3.ZERO))
				b.box(Vector3(0.18, 0.12, 0.3), at(Vector3(-0.2, 0.12, -0.15)), Color(0.85, 0.25, 0.25))
				b.cylinder(0.04, 0.04, 0.1, at(Vector3(-0.2, 0.22, -0.05)), DARK, 6)
			"bulldozer":
				var y := Color(1.0, 0.75, 0.15)
				b.rounded_box(Vector3(0.36, 0.16, 0.46), 0.04, at(Vector3(0, 0.12, -0.02)), y, 1)
				b.rounded_box(Vector3(0.26, 0.2, 0.2), 0.04, at(Vector3(0, 0.3, -0.08)), y.darkened(0.1), 1)
				b.box(Vector3(0.22, 0.08, 0.02), at(Vector3(0, 0.32, 0.025)), Color(0.55, 0.78, 0.95))
				b.box(Vector3(0.5, 0.16, 0.05), at(Vector3(0, 0.1, 0.3), Vector3.ONE, Vector3(-0.3, 0, 0)), Color(0.6, 0.6, 0.65))
				for sx in [-0.2, 0.2]:
					var px: float = sx
					b.rounded_box(Vector3(0.08, 0.12, 0.5), 0.04, at(Vector3(px, 0.06, -0.02)), DARK, 1)
		return b.build())


## Tray / ghost model for any kind (tools and buildings).
static func piece_mesh(kind: String, snow: bool) -> ArrayMesh:
	if Defs.is_tool_kind(kind):
		return tool_mesh(kind)
	return building_mesh(kind, 0, 1, snow)


## Scaffolding round a building site (cell units, for a footprint of `size` cells).
static func scaffold_mesh(size: int) -> ArrayMesh:
	return cached("scaffold_%d" % size, func() -> Resource:
		var b := MeshKit.Builder.new()
		var h := size * 0.5 - 0.06
		var pole := Color(0.85, 0.62, 0.25)
		for p in [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]:
			var pp: Vector2 = p
			b.box(Vector3(0.025, 0.45, 0.025), at(Vector3(pp.x, 0.225, pp.y)), pole)
		for y in [0.15, 0.32]:
			var py: float = y
			b.box(Vector3(h * 2.0, 0.02, 0.02), at(Vector3(0, py, h)), pole)
			b.box(Vector3(h * 2.0, 0.02, 0.02), at(Vector3(0, py, -h)), pole)
			b.box(Vector3(0.02, 0.02, h * 2.0), at(Vector3(h, py, 0)), pole)
			b.box(Vector3(0.02, 0.02, h * 2.0), at(Vector3(-h, py, 0)), pole)
		b.box(Vector3(0.2, 0.012, 0.08), at(Vector3(h - 0.1, 0.5, h + 0.02)), Color(1.0, 0.85, 0.2))
		return b.build())


## A marching parade person with a drum or a flag (cell units).
static func parade_mesh() -> ArrayMesh:
	return cached("parade", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.capsule(0.06, 0.2, at(Vector3(0, 0.12, 0)), Color(0.9, 0.2, 0.25), 8)
		b.sphere(0.055, at(Vector3(0, 0.27, 0)), Color(1.0, 0.85, 0.7), 8)
		b.cylinder(0.05, 0.05, 0.09, at(Vector3(0, 0.36, 0)), Color(0.15, 0.15, 0.25), 8)
		b.cylinder(0.05, 0.05, 0.05, at(Vector3(0, 0.12, 0.08), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.85, 0.3), 8)
		return b.build())


## The mayor's top hat (for the VR player's head on the TV), in metres.
static func top_hat_mesh() -> ArrayMesh:
	return cached("top_hat", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.2, 0.2, 0.02, at(Vector3(0, 0.0, 0)), Color(0.12, 0.1, 0.14), 18)
		b.cylinder(0.12, 0.13, 0.24, at(Vector3(0, 0.13, 0)), Color(0.14, 0.12, 0.17), 16)
		b.cylinder(0.132, 0.132, 0.05, at(Vector3(0, 0.04, 0)), Color(0.85, 0.2, 0.25), 16)
		return b.build())


## A tiny citizen look (one merged mesh from core/creatures.gd, far LOD). Looks are cached.
static func citizen_mesh(look: int) -> Mesh:
	return ResCache.get_or_make("ttt_citizen_%d_%s" % [look, VER], func() -> Resource:
		var classes: Array[String] = ["villager", "farmer", "chef", "scientist", "bard", "athlete", "detective", "host"]
		var o := Creatures.random_humanoid_opts(look * 31 + 5)
		o["class"] = classes[look % classes.size()]
		o["lod"] = "far"
		var node := Creatures.humanoid(o)
		var found: Mesh = null
		var stack: Array[Node] = [node]
		while not stack.is_empty() and found == null:
			var n: Node = stack.pop_back()
			var mi := n as MeshInstance3D
			if mi != null and mi.mesh != null:
				found = mi.mesh
			for c in n.get_children():
				stack.append(c)
		node.free()
		if found == null:
			var bb := MeshKit.Builder.new()
			bb.capsule(0.2, 0.8, at(Vector3(0, 0.4, 0)), Color(0.5, 0.7, 1.0), 8)
			bb.sphere(0.2, at(Vector3(0, 0.95, 0)), Color(1.0, 0.85, 0.7), 8)
			found = bb.build()
		return found) as Mesh


# --- Island, table, garden (metres) --------------------------------------------------------------------------

## The island: one block per land cell (grass / sand / rock hills), coloured for the island.
static func terrain_mesh(ter: PackedByteArray, isl: Dictionary) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var n := Defs.GRID
	var cs := Defs.CELL
	var grass: Color = isl["grass"]
	var grass2: Color = isl["grass2"]
	var sand: Color = isl["sand"]
	var rock: Color = isl["rock"]
	var snowy := bool(isl.get("snow", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(isl["seed"]) * 13
	var base_y := Defs.SEA_Y - 0.012
	for z in n:
		for x in n:
			var t := int(ter[z * n + x])
			if t == Defs.T_WATER:
				continue
			var c := Defs.cell_center(x, z)
			var top := Defs.GROUND_Y
			var col := grass if (x + z) % 2 == 0 else grass2
			col = col.lerp(Color(1, 1, 0.8), rng.randf() * 0.05)
			if t == Defs.T_SAND:
				top = Defs.GROUND_Y - 0.005
				col = sand.lerp(Color(1, 1, 1), rng.randf() * 0.06)
			var h := top - base_y
			b.box(Vector3(cs, h, cs), at(Vector3(c.x, base_y + h * 0.5, c.z)), col)
			if t == Defs.T_ROCK:
				var hh := rng.randf_range(0.03, 0.07)
				b.rounded_box(Vector3(cs * 1.05, hh, cs * 1.05), cs * 0.25, at(Vector3(c.x, top + hh * 0.5, c.z)), rock, 1)
				b.rounded_box(Vector3(cs * 0.7, hh * 0.8, cs * 0.7), cs * 0.2, at(Vector3(c.x + rng.randf_range(-0.005, 0.005), top + hh * 1.3, c.z)),
					SNOW if snowy or hh > 0.06 else rock.lightened(0.12), 1)
	return b.build()


## The sea on the table: a gently waving round pool (shader).
static func sea_mesh(radius: float) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	pm.subdivide_width = 28
	pm.subdivide_depth = 28
	return pm


const SEA_SHADER := """
shader_type spatial;
uniform vec4 shallow : source_color = vec4(0.35, 0.75, 0.9, 1.0);
uniform vec4 deep : source_color = vec4(0.15, 0.45, 0.75, 1.0);
void vertex() {
	VERTEX.y += sin(VERTEX.x * 38.0 + TIME * 1.3) * 0.0012 + cos(VERTEX.z * 31.0 + TIME * 1.1) * 0.0012;
}
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	if (r > 1.0) { discard; }
	float sparkle = pow(max(0.0, sin(UV.x * 160.0 + TIME * 2.0) * sin(UV.y * 140.0 - TIME * 1.7)), 12.0);
	ALBEDO = mix(shallow.rgb, deep.rgb, smoothstep(0.25, 0.95, r)) + vec3(sparkle * 0.25);
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
}
"""


static func sea_material(col: Color) -> ShaderMaterial:
	var key := "ttt_sea_%s_%s" % [col.to_html(false), VER]
	return ResCache.get_or_make(key, func() -> Resource:
		var sh := Shader.new()
		sh.code = SEA_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("shallow", col.lightened(0.25))
		m.set_shader_parameter("deep", col.darkened(0.2))
		return m) as ShaderMaterial


## The garden table the island sits on (metres).
static func table_mesh() -> ArrayMesh:
	return cached("table", func() -> Resource:
		var b := MeshKit.Builder.new()
		var wood := Color(0.62, 0.42, 0.26)
		b.cylinder(0.92, 0.92, 0.05, at(Vector3(0, Defs.TABLE_Y - 0.025, 0)), wood, 32)
		b.torus(0.92, 0.02, at(Vector3(0, Defs.TABLE_Y - 0.01, 0)), wood.darkened(0.15), 32, 6)
		b.cylinder(0.89, 0.89, 0.004, at(Vector3(0, Defs.TABLE_Y + 0.001, 0)), Color(0.95, 0.92, 0.85), 32)
		for k in 4:
			var a := k * PI * 0.5 + PI * 0.25
			var p := Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55)
			b.tube(p, p * 0.9 + Vector3(0, Defs.TABLE_Y - 0.05, 0), 0.04, 0.05, wood.darkened(0.1), 8)
		b.cylinder(0.12, 0.2, 0.1, at(Vector3(0, Defs.TABLE_Y - 0.1, 0)), wood.darkened(0.2), 12)
		return b.build())


## The lawn round the table, with garden chairs (metres).
static func garden_mesh() -> ArrayMesh:
	return cached("garden", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(40.0, 40.0, 0.04, at(Vector3(0, -0.02, 0)), Color(0.42, 0.66, 0.32), 40)
		b.cylinder(2.4, 2.4, 0.01, at(Vector3(0, 0.005, 0)), Color(0.82, 0.76, 0.62), 32)
		for k in 3:
			var a := k * TAU / 3.0 + 0.9
			b.add_mesh(MeshKit.prop("chair"), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * 1.25, 0.0, sin(a) * 1.25)))
		return b.build())


## Fireworks shell burst (glowing cube particles), for celebrations.
static func spark_mesh(c: Color) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.012
	bm.material = MeshKit.material(c, 3.0)
	return bm
