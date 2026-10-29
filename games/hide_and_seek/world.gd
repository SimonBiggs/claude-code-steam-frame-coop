extends RefCounted
## Shared building kit for Hide and Seek's maps (map_house.gd, map_castle.gd, map_ship.gd): batched
## meshes (everything that doesn't glow goes into ONE vertex-coloured mesh per map, few draw calls on the
## Frame's phone-class GPU), one StaticBody3D for every collision box (layer 1, "world"), walls with
## doorways, lights, windows, the jail cage, and the household props hiders turn into (decoys and
## disguises look exactly the same). The house itself is generated (housegen.gd) and built by map_house.gd.

const Seeded := preload("res://core/seeded.gd")
const WALL_H := 2.6
const WALL_T := 0.16
const DOOR_W := 1.5
const DOOR_H := 2.15

## Household objects a hider can turn into. Matching decoys stand all over every map.
const PROP_NAMES: Array[String] = ["lamp", "pot plant", "box", "teddy", "beach ball"]

## The jail cage's half size (jail_at; main.gd in_jail).
const JAIL_HALF := 0.65

# --- Batching ------------------------------------------------------------------

static func mat(color: Color, glow: float = 0.0, rough: float = 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


static func _tool(ctx: Dictionary, key: String, material: Material) -> SurfaceTool:
	var tools: Dictionary = ctx["tools"]
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
		var mats: Dictionary = ctx["mats"]
		mats[key] = material
	return tools[key]


## Non-glowing parts all go into ONE vertex-coloured mesh (one draw call for the whole house's furniture);
## glowing parts are grouped per colour (they need their own emissive material).
static func _add_mesh(ctx: Dictionary, mesh: Mesh, xf: Transform3D, color: Color, glow: float = 0.0) -> void:
	if glow <= 0.0:
		var vc := _tool(ctx, "vc", _vertex_material())
		var arr: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var raw = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		vc.set_color(color)
		if raw is PackedInt32Array and not (raw as PackedInt32Array).is_empty():
			for i in (raw as PackedInt32Array):
				vc.set_normal((nb * n[i]).normalized())
				vc.add_vertex(xf * v[i])
		else:
			for i in v.size():
				vc.set_normal((nb * n[i]).normalized())
				vc.add_vertex(xf * v[i])
		return
	var key := color.to_html() + ("g%.1f" % glow)
	var st := _tool(ctx, key, mat(color, glow))
	st.append_from(mesh, 0, xf)


static func _vertex_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.75
	return m


static func _collide_box(ctx: Dictionary, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	var body: StaticBody3D = ctx["body"]
	body.add_child(cs)


## A box: `pos` is its centre.
static func box(ctx: Dictionary, size: Vector3, pos: Vector3, color: Color, collide: bool = true, yaw: float = 0.0, glow: float = 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	_add_mesh(ctx, bm, xf, color, glow)
	if collide:
		_collide_box(ctx, size, xf)


static func cyl(ctx: Dictionary, r_top: float, r_bot: float, h: float, pos: Vector3, color: Color, collide: bool = true, glow: float = 0.0) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	_add_mesh(ctx, cm, Transform3D(Basis(), pos), color, glow)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(r_top, r_bot)
		shape.height = h
		cs.shape = shape
		cs.position = pos
		var body: StaticBody3D = ctx["body"]
		body.add_child(cs)


static func ball(ctx: Dictionary, r: float, pos: Vector3, color: Color, squash: float = 1.0, glow: float = 0.0) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	_add_mesh(ctx, sm, Transform3D(Basis().scaled(Vector3(1.0, squash, 1.0)), pos), color, glow)


static func _commit(ctx: Dictionary) -> void:
	var main: Node3D = ctx["main"]
	var tools: Dictionary = ctx["tools"]
	var mats: Dictionary = ctx["mats"]
	for key in tools.keys():
		var st: SurfaceTool = tools[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(mi)


# --- Props (decoys and disguises look exactly the same) -----------------------

## A household object as separate meshes (for a disguised hider). Its origin is on the floor.
static func make_prop(kind: int, cache: Node) -> Node3D:
	var root := Node3D.new()
	for part in _prop_parts(kind, cache):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		var c: Color = part[2]
		var g: float = part[3]
		mi.material_override = _prop_mat(c, g, cache)
		mi.transform = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Shared materials / meshes are cached as metadata on `cache` (the Main node), so they go away with the scene.
static func _prop_mat(c: Color, g: float, cache: Node) -> StandardMaterial3D:
	var key := "hs_prop_mat_%s_%d" % [c.to_html(), int(g * 10.0)]
	if not cache.has_meta(key):
		cache.set_meta(key, mat(c, g))
	return cache.get_meta(key)


static func _bake_prop(ctx: Dictionary, kind: int, xf: Transform3D) -> void:
	for part in _prop_parts(kind, ctx["main"]):
		var m: Mesh = part[0]
		var local: Transform3D = part[1]
		_add_mesh(ctx, m, xf * local, part[2], part[3])
	if kind == 2:
		_collide_box(ctx, Vector3(0.66, 0.66, 0.66), xf * Transform3D(Basis(), Vector3(0, 0.33, 0)))
	else:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = [0.22, 0.3, 0.3, 0.3, 0.33][kind]
		shape.height = [1.2, 1.2, 1.2, 0.9, 0.66][kind]
		cs.shape = shape
		cs.position = xf.origin + Vector3(0, shape.height / 2.0, 0)
		var body: StaticBody3D = ctx["body"]
		body.add_child(cs)


## [mesh, transform, colour, glow] for each part. Cached meshes (shared by every copy).
static func _prop_parts(kind: int, cache: Node) -> Array:
	var key := "hs_prop_parts_%d" % kind
	if cache.has_meta(key):
		return cache.get_meta(key)
	var parts: Array = []
	match kind:
		0:  # floor lamp with a cream shade
			parts.append([_cyl_mesh(0.18, 0.2, 0.05), Transform3D(Basis(), Vector3(0, 0.025, 0)), Color(0.35, 0.24, 0.16), 0.0])
			parts.append([_cyl_mesh(0.025, 0.025, 1.2), Transform3D(Basis(), Vector3(0, 0.6, 0)), Color(0.75, 0.6, 0.3), 0.0])
			parts.append([_cyl_mesh(0.17, 0.3, 0.36), Transform3D(Basis(), Vector3(0, 1.32, 0)), Color(1.0, 0.92, 0.7), 0.6])
		1:  # pot plant
			parts.append([_cyl_mesh(0.25, 0.18, 0.4), Transform3D(Basis(), Vector3(0, 0.2, 0)), Color(0.85, 0.45, 0.28), 0.0])
			parts.append([_sphere_mesh(0.38), Transform3D(Basis(), Vector3(0, 0.72, 0)), Color(0.3, 0.68, 0.32), 0.0])
			parts.append([_sphere_mesh(0.24), Transform3D(Basis(), Vector3(0.14, 1.0, 0.05)), Color(0.42, 0.8, 0.38), 0.0])
		3:  # a big friendly teddy bear, sitting
			var fur := Color(0.72, 0.48, 0.3)
			var muzzle := Color(0.95, 0.8, 0.62)
			parts.append([_sphere_mesh(0.3), Transform3D(Basis.from_scale(Vector3(1.0, 1.05, 0.9)), Vector3(0, 0.3, 0)), fur, 0.0])
			parts.append([_sphere_mesh(0.22), Transform3D(Basis(), Vector3(0, 0.72, -0.02)), fur, 0.0])
			parts.append([_sphere_mesh(0.09), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.8)), Vector3(0, 0.68, -0.2)), muzzle, 0.0])
			parts.append([_sphere_mesh(0.08), Transform3D(Basis(), Vector3(-0.16, 0.9, 0.0)), fur, 0.0])
			parts.append([_sphere_mesh(0.08), Transform3D(Basis(), Vector3(0.16, 0.9, 0.0)), fur, 0.0])
			parts.append([_sphere_mesh(0.11), Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 1.3)), Vector3(-0.17, 0.09, -0.2)), muzzle, 0.0])
			parts.append([_sphere_mesh(0.11), Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 1.3)), Vector3(0.17, 0.09, -0.2)), muzzle, 0.0])
			parts.append([_sphere_mesh(0.035), Transform3D(Basis(), Vector3(0, 0.74, -0.27)), Color(0.15, 0.1, 0.08), 0.0])
		4:  # a big stripy beach ball
			parts.append([_sphere_mesh(0.33), Transform3D(Basis(), Vector3(0, 0.33, 0)), Color(1.0, 0.95, 0.9), 0.0])
			var band := _sphere_mesh(0.335)
			parts.append([band, Transform3D(Basis.from_scale(Vector3(0.35, 1.0, 1.0)), Vector3(0, 0.33, 0)), Color(1.0, 0.35, 0.3), 0.0])
			parts.append([band, Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3(0.35, 1.0, 1.0)), Vector3(0, 0.33, 0)), Color(0.3, 0.6, 1.0), 0.0])
			parts.append([_sphere_mesh(0.07), Transform3D(Basis(), Vector3(0, 0.66, 0)), Color(1.0, 0.85, 0.2), 0.0])
		_:  # cardboard box with tape
			var bm := BoxMesh.new()
			bm.size = Vector3(0.66, 0.66, 0.66)
			parts.append([bm, Transform3D(Basis(), Vector3(0, 0.33, 0)), Color(0.78, 0.6, 0.38), 0.0])
			var tm := BoxMesh.new()
			tm.size = Vector3(0.68, 0.02, 0.14)
			parts.append([tm, Transform3D(Basis(), Vector3(0, 0.665, 0)), Color(0.92, 0.82, 0.6), 0.0])
	cache.set_meta(key, parts)
	return parts


static func _cyl_mesh(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	return cm


static func _sphere_mesh(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return sm


# --- Shared builders for the maps ----------------------------------------------------

## A fresh build context: one StaticBody3D for every collision box, batched meshes under `root`.
static func new_ctx(root: Node3D) -> Dictionary:
	var ctx := {"tools": {}, "mats": {}, "main": root}
	var body := StaticBody3D.new()
	body.name = "MapBody"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	ctx["body"] = body
	return ctx


## Sky colour, ambient light and a soft sun (no shadows: phone-class GPU).
static func environment_for(root: Node3D, bg: Color, ambient: Color, amb_energy: float, sun_energy: float) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = amb_energy
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.05
	env.environment = e
	env.set_meta("day_bg", bg)
	env.set_meta("day_ambient", amb_energy)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = sun_energy
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-60, 30, 0)
	root.add_child(sun)


## A floor plane with its own shader (one draw call) plus a solid slab to stand on.
static func shader_floor(ctx: Dictionary, size: Vector2, center: Vector3, code: String) -> void:
	var root: Node3D = ctx["main"]
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	mi.material_override = m
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_collide_box(ctx, Vector3(size.x + 2.0, 0.2, size.y + 2.0), Transform3D(Basis(), center + Vector3(0, -0.1, 0)))


## A vertex-coloured wall along x at `z` from x0 to x1 with doorways centred at `doors` (all in the one merged mesh).
static func wall_x(ctx: Dictionary, z: float, x0: float, x1: float, doors: Array, color: Color, h: float, dw: float = DOOR_W, dh: float = DOOR_H) -> void:
	var a := x0 - WALL_T / 2.0
	var cuts: Array = doors.duplicate()
	cuts.sort()
	for d in cuts:
		var dx: float = d
		var b := dx - dw / 2.0
		if b > a:
			box(ctx, Vector3(b - a, h, WALL_T), Vector3((a + b) / 2.0, h / 2.0, z), color)
		box(ctx, Vector3(dw, h - dh, WALL_T), Vector3(dx, (h + dh) / 2.0, z), color.darkened(0.08))
		a = dx + dw / 2.0
	var e := x1 + WALL_T / 2.0
	box(ctx, Vector3(e - a, h, WALL_T), Vector3((a + e) / 2.0, h / 2.0, z), color)


static func wall_z(ctx: Dictionary, x: float, z0: float, z1: float, doors: Array, color: Color, h: float, dw: float = DOOR_W, dh: float = DOOR_H) -> void:
	var a := z0
	var cuts: Array = doors.duplicate()
	cuts.sort()
	for d in cuts:
		var dz: float = d
		var b := dz - dw / 2.0
		if b > a:
			box(ctx, Vector3(WALL_T, h, b - a), Vector3(x, h / 2.0, (a + b) / 2.0), color)
		box(ctx, Vector3(WALL_T, h - dh, dw), Vector3(x, (h + dh) / 2.0, dz), color.darkened(0.08))
		a = dz + dw / 2.0
	box(ctx, Vector3(WALL_T, h, z1 - a), Vector3(x, h / 2.0, (a + z1) / 2.0), color)


static func omni_lights(root: Node3D, positions: Array, color: Color, energy: float, light_range: float) -> Array:
	var out: Array = []
	for p in positions:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = energy
		l.omni_range = light_range
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		root.add_child(l)
		l.position = p
		l.set_meta("day_energy", energy)
		out.append(l)
	return out


## Bake the decoy props and commit every batched mesh. Returns the decoy list for main.gd.
static func finish(ctx: Dictionary, decoy_list: Array) -> Array:
	var out: Array = []
	for d in decoy_list:
		var kind: int = d[0]
		var pos: Vector3 = d[1]
		var yaw: float = d[2]
		_bake_prop(ctx, kind, Transform3D(Basis(Vector3.UP, yaw), pos))
		out.append({"kind": kind, "pos": pos})
	_commit(ctx)
	return out


## The jail cage + bell, at any position (used by the other maps).
static func jail_at(ctx: Dictionary, c: Vector3, bell: Vector3, bar: Color, roof: Color) -> void:
	var h := JAIL_HALF
	for i in 8:
		var t := (i + 0.5) / 8.0
		for p in [c + Vector3(-h + t * 2.0 * h, 0.75, -h), c + Vector3(-h + t * 2.0 * h, 0.75, h),
				c + Vector3(-h, 0.75, -h + t * 2.0 * h), c + Vector3(h, 0.75, -h + t * 2.0 * h)]:
			cyl(ctx, 0.025, 0.025, 1.5, p, bar, false)
	box(ctx, Vector3(h * 2.0 + 0.1, 0.08, h * 2.0 + 0.1), c + Vector3(0, 1.52, 0), roof, false)
	box(ctx, Vector3(h * 2.0 + 0.1, 0.05, h * 2.0 + 0.1), c + Vector3(0, 0.025, 0), Color(0.45, 0.4, 0.38), false)
	for side in 4:
		var horiz := side < 2
		var off := (-h if side % 2 == 0 else h)
		var size := Vector3(h * 2.0, 1.5, 0.06) if horiz else Vector3(0.06, 1.5, h * 2.0)
		var at := c + (Vector3(0, 0.75, off) if horiz else Vector3(off, 0.75, 0))
		_collide_box(ctx, size, Transform3D(Basis(), at))
	cyl(ctx, 0.04, 0.05, 1.1, bell + Vector3(0, 0.55, 0), Color(0.45, 0.32, 0.22))
	cyl(ctx, 0.06, 0.16, 0.2, bell + Vector3(0, 1.15, 0), Color(1.0, 0.85, 0.2), false, 0.6)
	ball(ctx, 0.04, bell + Vector3(0, 1.03, 0), Color(0.5, 0.35, 0.2))


## A glowing window pane in an outer wall (`side` = wall runs along z). Shares the night-dimmed window material.
static func window_at(ctx: Dictionary, p: Vector3, side: bool, frame: Color, size: Vector2 = Vector2(1.3, 1.0)) -> void:
	var glass := Vector3(0.05, size.y, size.x) if side else Vector3(size.x, size.y, 0.05)
	var rim := Vector3(0.03, size.y + 0.14, size.x + 0.14) if side else Vector3(size.x + 0.14, size.y + 0.14, 0.03)
	box(ctx, rim, p, frame, false)
	box(ctx, glass, p, Color(0.6, 0.72, 1.0), false, 0.0, 1.4)


## The night-dimmed window material (if this map has windows).
static func window_mat(ctx: Dictionary) -> Material:
	var wkey := Color(0.6, 0.72, 1.0).to_html() + ("g%.1f" % 1.4)
	return ctx["mats"].get(wkey)


## Hand-made maps' decoys, shuffled for a round: most of them stand (a different few are gone each time)
## and each one turns a little. Positions are the hand-checked ones, so every hiding route stays open.
static func round_decoys(list: Array, seed_value: int) -> Array:
	if seed_value == 0:
		return list
	var r := Seeded.rng(seed_value, "decoys")
	var out: Array = []
	for d in list:
		if r.randf() < 0.8:
			out.append([d[0], d[1], float(d[2]) + r.randf_range(-0.8, 0.8)])
	return out
