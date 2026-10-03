extends RefCounted
## Procedural meshes and materials for Block Builders. Blocks are single merged ArrayMeshes (one
## draw call each) built from coloured boxes, cached on the Engine so restarts don't rebuild them.

const KINDS: Array[String] = ["plank", "stairs", "spring", "fan", "crate", "booster", "launcher"]
const KIND_NAMES: Array[String] = ["PLANK", "STAIRS", "SPRING", "FAN", "CRATE", "SPEED PAD", "LAUNCH PAD"]
const KIND_COLORS: Array[Color] = [Color(1.0, 0.66, 0.28), Color(0.3, 0.72, 1.0), Color(1.0, 0.36, 0.62), Color(0.66, 0.48, 1.0),
	Color(0.8, 0.56, 0.32), Color(0.4, 0.95, 0.35), Color(1.0, 0.3, 0.22)]
const MESH_VERSION := "v4"
## Visual layer for things only the TV players should see (billboarded popups, name tags).
const TV_LAYER := 8
## The builder's own head: hidden from the builder's camera.
const BODY_LAYER := 2


static func mat(color: Color, glow: float = 0.0, rough: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


static func vcol_mat(rough: float = 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m


static func sphere(radius: float, segs: int = 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = maxi(4, segs / 2)
	return s


static func cyl(top: float, bottom: float, h: float, segs: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func kind_index(kind: String) -> int:
	return KINDS.find(kind)


static func kind_color(kind: String) -> Color:
	var i := KINDS.find(kind)
	return KIND_COLORS[i] if i >= 0 else Color.WHITE


## Appends an axis-aligned box (centre, size) with a flat colour to a SurfaceTool.
static func add_box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.DOWN, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3.RIGHT, [Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3.LEFT, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.BACK, [Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3.FORWARD, [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var v: Array = f[1]
		# Light baked shading per face so the blocks read well even in flat light.
		var shade := 1.0
		if n == Vector3.DOWN:
			shade = 0.6
		elif n.x != 0.0:
			shade = 0.86
		elif n.z != 0.0:
			shade = 0.93
		var cc := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(cc)
			st.set_normal(n)
			var p: Vector3 = v[idx]
			st.add_vertex(c + p)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _finish(st: SurfaceTool) -> ArrayMesh:
	var m := st.commit()
	m.surface_set_material(0, vcol_mat())
	return m


## Block mesh for a kind. Origin at the centre of the cell's bottom face; "up the stairs" is +X.
static func block_mesh(kind: String) -> ArrayMesh:
	if not KINDS.has(kind):
		kind = "plank"
	var key := "bb_block_%s_%s" % [MESH_VERSION, kind]
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var st := _begin()
	var c := kind_color(kind)
	match kind:
		"plank":
			add_box(st, Vector3(0, 0.85, 0), Vector3(0.98, 0.3, 0.98), c)
			for i in 3:
				add_box(st, Vector3(-0.33 + i * 0.33, 1.005, 0), Vector3(0.05, 0.02, 0.96), c.darkened(0.3))
		"stairs":
			for i in 4:
				var x0 := -0.5 + i * 0.25
				add_box(st, Vector3((x0 + 0.5) * 0.5, i * 0.25 + 0.125, 0), Vector3(0.5 - x0 + 0.0, 0.25, 0.98),
					c.lightened(0.08 * i))
		"spring":
			add_box(st, Vector3(0, 0.08, 0), Vector3(0.9, 0.16, 0.9), Color(0.35, 0.35, 0.42))
			for i in 3:
				add_box(st, Vector3(0, 0.2 + i * 0.1, 0), Vector3(0.5 - i * 0.04, 0.05, 0.5 - i * 0.04), Color(0.85, 0.85, 0.9))
			add_box(st, Vector3(0, 0.5, 0), Vector3(0.84, 0.1, 0.84), c)
		"fan":
			add_box(st, Vector3(0, 0.2, 0), Vector3(0.96, 0.4, 0.96), c)
			add_box(st, Vector3(0, 0.425, 0), Vector3(0.8, 0.05, 0.8), Color(0.15, 0.12, 0.25))
		"crate":
			# A full wooden box with a darker frame: stack them into towers, walls and staircases.
			add_box(st, Vector3(0, 0.5, 0), Vector3(0.94, 0.94, 0.94), c)
			var fr := c.darkened(0.35)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					add_box(st, Vector3(sx * 0.44, 0.5, sz * 0.44), Vector3(0.12, 0.99, 0.12), fr)
			for sy in [0.05, 0.95]:
				add_box(st, Vector3(0, sy, -0.44), Vector3(0.99, 0.11, 0.12), fr)
				add_box(st, Vector3(0, sy, 0.44), Vector3(0.99, 0.11, 0.12), fr)
				add_box(st, Vector3(-0.44, sy, 0), Vector3(0.12, 0.11, 0.99), fr)
				add_box(st, Vector3(0.44, sy, 0), Vector3(0.12, 0.11, 0.99), fr)
			add_box(st, Vector3(0, 0.5, 0), Vector3(0.1, 0.8, 0.97), fr.lightened(0.1))
		"booster":
			# A low pad with two bright chevrons pointing the way it pushes (+X before turning).
			add_box(st, Vector3(0, 0.06, 0), Vector3(0.96, 0.12, 0.96), Color(0.22, 0.24, 0.3))
			add_box(st, Vector3(0, 0.125, 0), Vector3(0.88, 0.02, 0.88), c)
			for k in 2:
				_chevron(st, Vector3(-0.22 + k * 0.32, 0.14, 0), 0.06, Color(1.0, 0.95, 0.3))
		"launcher":
			# A catapult plate: springs under a red plate with a raised lip and an arrow.
			add_box(st, Vector3(0, 0.08, 0), Vector3(0.94, 0.16, 0.94), Color(0.3, 0.3, 0.36))
			for sx in [-0.25, 0.25]:
				add_box(st, Vector3(sx, 0.2, 0), Vector3(0.14, 0.1, 0.5), Color(0.85, 0.85, 0.9))
			add_box(st, Vector3(0, 0.3, 0), Vector3(0.88, 0.1, 0.88), c)
			add_box(st, Vector3(0.4, 0.4, 0), Vector3(0.1, 0.12, 0.88), c.darkened(0.25))
			_chevron(st, Vector3(-0.05, 0.36, 0), 0.07, Color(1.0, 0.95, 0.3))
	var m := _finish(st)
	Engine.set_meta(key, m)
	return m


## A "pixel" chevron pointing +X made of small boxes (arrows on speed and launch pads).
static func _chevron(st: SurfaceTool, c: Vector3, px: float, col: Color) -> void:
	for i in 4:
		var x := c.x + i * px * 0.9
		var z := (3 - i) * px
		add_box(st, Vector3(x, c.y, c.z + z), Vector3(px, 0.02, px), col)
		if z > 0.0:
			add_box(st, Vector3(x, c.y, c.z - z), Vector3(px, 0.02, px), col)


## The spinning blades on top of a fan block.
static func fan_blades_mesh() -> ArrayMesh:
	var key := "bb_blades_" + MESH_VERSION
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var st := _begin()
	add_box(st, Vector3.ZERO, Vector3(0.7, 0.03, 0.14), Color(0.95, 0.95, 1.0))
	add_box(st, Vector3.ZERO, Vector3(0.14, 0.03, 0.7), Color(0.95, 0.95, 1.0))
	add_box(st, Vector3(0, 0.02, 0), Vector3(0.16, 0.05, 0.16), Color(1.0, 0.85, 0.3))
	var m := _finish(st)
	Engine.set_meta(key, m)
	return m


## A floating island chunk: grass slab on top, dirt below, tapering rock underneath, with a few
## hanging rocks and roots so it reads as a floating island from the builder's view.
static func island_mesh(x0: float, x1: float, z0: float, z1: float, top: float, bottom: float, grass: Color,
		dirt: Color = Color(0.55, 0.38, 0.24), rock: Color = Color(0.45, 0.32, 0.22)) -> ArrayMesh:
	var st := _begin()
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	add_box(st, Vector3(cx, top - 0.12, cz), Vector3(w, 0.24, d), grass)
	# A slightly darker grass lip hanging over the edge.
	add_box(st, Vector3(cx, top - 0.3, cz), Vector3(w + 0.06, 0.14, d + 0.06), grass.darkened(0.18))
	var body_h := maxf(0.1, top - 0.24 - bottom)
	add_box(st, Vector3(cx, top - 0.24 - body_h * 0.5, cz), Vector3(w - 0.04, body_h, d - 0.04), dirt)
	# Rock strata on tall cliffs.
	var sy := top - 1.4
	while sy > bottom + 0.3:
		add_box(st, Vector3(cx, sy, cz), Vector3(w + 0.02, 0.18, d + 0.02), dirt.darkened(0.15))
		sy -= 1.3
	# Rocky underside (visual only).
	add_box(st, Vector3(cx, bottom - 0.5, cz), Vector3(w * 0.7, 1.0, d * 0.7), rock)
	add_box(st, Vector3(cx, bottom - 1.4, cz), Vector3(w * 0.35, 0.8, d * 0.35), rock.darkened(0.15))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(x0 * 13.0 + z0 * 7.0 + top * 31.0)) + 5
	for i in int(clampf(w * 0.8, 2.0, 7.0)):
		var hx := rng.randf_range(x0 + 0.4, x1 - 0.4)
		var hz := rng.randf_range(z0 + 0.4, z1 - 0.4)
		var hh := rng.randf_range(0.4, 1.3)
		add_box(st, Vector3(hx, bottom - 0.2 - hh * 0.5, hz), Vector3(0.35, hh, 0.35), rock.lightened(rng.randf_range(-0.1, 0.1)))
	for i in int(clampf(w * 0.5, 1.0, 5.0)):
		var rx := rng.randf_range(x0 + 0.3, x1 - 0.3)
		add_box(st, Vector3(rx, top - 0.55, z1 + 0.02), Vector3(0.06, rng.randf_range(0.3, 0.8), 0.04), grass.darkened(0.3))
	return _finish(st)


## A grid-cell checker on top of a platform is too many vertices; instead a few darker stripes.
static func lava_mesh(x0: float, x1: float, z0: float, z1: float, top: float) -> ArrayMesh:
	var st := _begin()
	add_box(st, Vector3((x0 + x1) * 0.5, top - 0.6, (z0 + z1) * 0.5), Vector3(x1 - x0, 1.2, z1 - z0), Color(1.0, 0.42, 0.08))
	return st.commit()


## The builder's glove (seen by the runners, and by the builder as their own hand).
static func glove_mesh(color: Color) -> ArrayMesh:
	var st := _begin()
	var skin := Color(1.0, 0.85, 0.3)
	add_box(st, Vector3(0, 0, 0.12), Vector3(0.62, 0.22, 0.6), skin)
	for i in 4:
		add_box(st, Vector3(-0.22 + i * 0.147, 0, -0.32), Vector3(0.12, 0.16, 0.36), skin)
	add_box(st, Vector3(0.38, 0, 0.1), Vector3(0.14, 0.15, 0.32), skin)
	add_box(st, Vector3(0, 0, 0.5), Vector3(0.66, 0.28, 0.24), color)
	return _finish(st)


## A chunky five-pointed star (collectable), flat-shaded, one surface.
static func star_mesh() -> ArrayMesh:
	var key := "bb_star_" + MESH_VERSION
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in 10:
		var a := PI * 0.5 + TAU * i / 10.0
		var r := 0.42 if i % 2 == 0 else 0.18
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	var depth := 0.09
	for side in [1.0, -1.0]:
		var n := Vector3(0, 0, side)
		for i in 10:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % 10]
			var ctr := Vector3(0, 0, depth * side)
			var tri: Array = [ctr, a, b] if side > 0.0 else [ctr, b, a]
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	for i in 10:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 10]
		var n := (a + b).normalized()
		for v in [a, b, b + Vector3(0, 0, depth), a, b + Vector3(0, 0, depth), a + Vector3(0, 0, depth)]:
			st.set_normal(n)
			st.add_vertex(v - Vector3(0, 0, depth * 0.5))
	var m := st.commit()
	Engine.set_meta(key, m)
	return m


## The gift box hanging from a balloon (vertex coloured).
static func gift_mesh() -> ArrayMesh:
	var key := "bb_gift_" + MESH_VERSION
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var st := _begin()
	add_box(st, Vector3(0, 0, 0), Vector3(0.5, 0.42, 0.5), Color(0.3, 0.75, 1.0))
	add_box(st, Vector3(0, 0, 0), Vector3(0.52, 0.44, 0.1), Color(1.0, 0.9, 0.3))
	add_box(st, Vector3(0, 0, 0), Vector3(0.1, 0.44, 0.52), Color(1.0, 0.9, 0.3))
	add_box(st, Vector3(-0.08, 0.27, 0), Vector3(0.14, 0.1, 0.08), Color(1.0, 0.85, 0.25))
	add_box(st, Vector3(0.08, 0.27, 0), Vector3(0.14, 0.1, 0.08), Color(1.0, 0.85, 0.25))
	var m := _finish(st)
	Engine.set_meta(key, m)
	return m


## A big rainbow arch (5 bands) in the XY plane, centred on the origin, for the finale.
static func rainbow_mesh(radius: float, band: float) -> ArrayMesh:
	var key := "bb_rainbow_%s_%d" % [MESH_VERSION, int(radius)]
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array[Color] = [Color(1.0, 0.3, 0.3), Color(1.0, 0.65, 0.2), Color(1.0, 0.95, 0.3), Color(0.35, 0.9, 0.4),
		Color(0.35, 0.6, 1.0), Color(0.7, 0.4, 1.0)]
	var segs := 28
	for b in cols.size():
		var r0 := radius - b * band
		var r1 := r0 - band
		for i in segs:
			var a0 := PI * i / segs
			var a1 := PI * (i + 1) / segs
			var p: Array[Vector3] = [Vector3(cos(a0) * r0, sin(a0) * r0, 0), Vector3(cos(a1) * r0, sin(a1) * r0, 0),
				Vector3(cos(a1) * r1, sin(a1) * r1, 0), Vector3(cos(a0) * r1, sin(a0) * r1, 0)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(cols[b])
				st.set_normal(Vector3.BACK)
				st.add_vertex(p[idx])
	var m := st.commit()
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(1, 1, 1, 0.75)
	m.surface_set_material(0, mt)
	Engine.set_meta(key, m)
	return m


## Decorative props for the islands (vertex coloured, one draw call per kind via MultiMesh).
## kind: tree, pine, bush, flowers, rock, cactus, mushroom, lollipop, palm, tower, lamp, crystal.
static func prop_mesh(kind: String, tint: Color) -> ArrayMesh:
	var key := "bb_prop_%s_%s_%s" % [MESH_VERSION, kind, tint.to_html()]
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var st := _begin()
	var trunk := Color(0.5, 0.33, 0.2)
	match kind:
		"tree":
			add_box(st, Vector3(0, 0.45, 0), Vector3(0.18, 0.9, 0.18), trunk)
			add_box(st, Vector3(0, 1.05, 0), Vector3(0.9, 0.55, 0.9), tint)
			add_box(st, Vector3(0.05, 1.45, -0.05), Vector3(0.6, 0.4, 0.6), tint.lightened(0.12))
			add_box(st, Vector3(-0.3, 0.95, 0.25), Vector3(0.35, 0.3, 0.35), tint.darkened(0.1))
		"pine":
			add_box(st, Vector3(0, 0.3, 0), Vector3(0.16, 0.6, 0.16), trunk)
			for i in 3:
				var w := 0.9 - i * 0.25
				add_box(st, Vector3(0, 0.65 + i * 0.4, 0), Vector3(w, 0.32, w), tint.lightened(0.06 * i))
				add_box(st, Vector3(0, 0.83 + i * 0.4, 0), Vector3(w * 0.8, 0.06, w * 0.8), Color(0.97, 0.98, 1.0))
		"bush":
			add_box(st, Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.5), tint)
			add_box(st, Vector3(0.18, 0.32, 0.05), Vector3(0.35, 0.3, 0.35), tint.lightened(0.1))
			add_box(st, Vector3(-0.1, 0.42, -0.05), Vector3(0.12, 0.08, 0.12), Color(1.0, 0.35, 0.4))
		"flowers":
			var pc: Array[Color] = [Color(1.0, 0.4, 0.55), Color(1.0, 0.9, 0.3), Color(0.6, 0.5, 1.0)]
			for i in 3:
				var o := Vector3(-0.2 + i * 0.2, 0, (i % 2) * 0.16 - 0.08)
				add_box(st, o + Vector3(0, 0.12, 0), Vector3(0.03, 0.24, 0.03), Color(0.3, 0.7, 0.3))
				add_box(st, o + Vector3(0, 0.26, 0), Vector3(0.14, 0.05, 0.14), pc[i])
				add_box(st, o + Vector3(0, 0.29, 0), Vector3(0.05, 0.03, 0.05), Color(1.0, 0.95, 0.6))
		"rock":
			add_box(st, Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.42), tint)
			add_box(st, Vector3(0.12, 0.3, 0.04), Vector3(0.3, 0.2, 0.28), tint.lightened(0.1))
		"cactus":
			var g := Color(0.35, 0.7, 0.35)
			add_box(st, Vector3(0, 0.6, 0), Vector3(0.24, 1.2, 0.24), g)
			add_box(st, Vector3(0.22, 0.6, 0), Vector3(0.22, 0.14, 0.16), g)
			add_box(st, Vector3(0.28, 0.85, 0), Vector3(0.14, 0.4, 0.14), g)
			add_box(st, Vector3(-0.2, 0.45, 0), Vector3(0.2, 0.12, 0.14), g)
			add_box(st, Vector3(-0.26, 0.62, 0), Vector3(0.12, 0.3, 0.12), g)
			add_box(st, Vector3(0, 1.24, 0), Vector3(0.12, 0.08, 0.12), Color(1.0, 0.45, 0.6))
		"mushroom":
			add_box(st, Vector3(0, 0.25, 0), Vector3(0.18, 0.5, 0.18), Color(0.98, 0.95, 0.88))
			add_box(st, Vector3(0, 0.56, 0), Vector3(0.7, 0.22, 0.7), tint)
			add_box(st, Vector3(0, 0.7, 0), Vector3(0.44, 0.1, 0.44), tint)
			for d in [Vector3(0.2, 0.68, 0.2), Vector3(-0.18, 0.68, 0.05), Vector3(0.05, 0.76, -0.12)]:
				var dv: Vector3 = d
				add_box(st, dv, Vector3(0.1, 0.06, 0.1), Color(1, 1, 1))
		"lollipop":
			add_box(st, Vector3(0, 0.55, 0), Vector3(0.07, 1.1, 0.07), Color(0.98, 0.98, 0.98))
			add_box(st, Vector3(0, 1.25, 0), Vector3(0.6, 0.6, 0.12), tint)
			add_box(st, Vector3(0, 1.25, 0), Vector3(0.36, 0.36, 0.14), Color(1, 1, 1))
			add_box(st, Vector3(0, 1.25, 0), Vector3(0.16, 0.16, 0.16), tint.lightened(0.2))
		"palm":
			for i in 5:
				add_box(st, Vector3(i * 0.05, 0.2 + i * 0.32, 0), Vector3(0.18, 0.34, 0.18), trunk.lightened(0.05 * (i % 2)))
			var lf := Color(0.3, 0.75, 0.3)
			add_box(st, Vector3(0.45, 1.68, 0), Vector3(0.7, 0.06, 0.24), lf)
			add_box(st, Vector3(-0.2, 1.68, 0), Vector3(0.7, 0.06, 0.24), lf)
			add_box(st, Vector3(0.12, 1.68, 0.35), Vector3(0.24, 0.06, 0.7), lf)
			add_box(st, Vector3(0.12, 1.68, -0.35), Vector3(0.24, 0.06, 0.7), lf)
			add_box(st, Vector3(0.2, 1.6, 0.05), Vector3(0.14, 0.14, 0.14), Color(0.5, 0.35, 0.2))
		"tower":
			var stone := Color(0.72, 0.72, 0.78)
			add_box(st, Vector3(0, 0.9, 0), Vector3(0.7, 1.8, 0.7), stone)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					add_box(st, Vector3(sx * 0.27, 1.92, sz * 0.27), Vector3(0.18, 0.24, 0.18), stone.lightened(0.1))
			add_box(st, Vector3(0, 1.05, 0.36), Vector3(0.2, 0.32, 0.04), Color(0.15, 0.12, 0.2))
			add_box(st, Vector3(0, 2.3, 0), Vector3(0.04, 0.8, 0.04), Color(0.9, 0.9, 0.9))
			add_box(st, Vector3(0.17, 2.55, 0), Vector3(0.3, 0.2, 0.03), tint)
		"lamp":
			add_box(st, Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), Color(0.25, 0.25, 0.32))
			add_box(st, Vector3(0, 1.12, 0), Vector3(0.2, 0.05, 0.2), Color(0.25, 0.25, 0.32))
		"crystal", "bulb":
			pass
	if kind == "crystal":
		add_box(st, Vector3(0, 0.45, 0), Vector3(0.22, 0.9, 0.22), tint)
		add_box(st, Vector3(0.17, 0.3, 0.05), Vector3(0.14, 0.6, 0.14), tint.lightened(0.15))
		add_box(st, Vector3(-0.14, 0.22, -0.06), Vector3(0.12, 0.44, 0.12), tint.darkened(0.1))
	elif kind == "bulb":
		add_box(st, Vector3(0, 1.26, 0), Vector3(0.22, 0.24, 0.22), tint)
	var m := st.commit()
	if kind == "crystal" or kind == "bulb":
		var gm := StandardMaterial3D.new()
		gm.vertex_color_use_as_albedo = true
		gm.emission_enabled = true
		gm.emission = tint
		gm.emission_energy_multiplier = 1.6
		m.surface_set_material(0, gm)
	else:
		m.surface_set_material(0, vcol_mat())
	Engine.set_meta(key, m)
	return m


## A small V-shaped bird (wings along X), for the flock circling the course.
static func bird_mesh() -> ArrayMesh:
	var key := "bb_bird_" + MESH_VERSION
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var st := _begin()
	add_box(st, Vector3(0, 0, 0), Vector3(0.14, 0.12, 0.4), Color(0.95, 0.95, 1.0))
	add_box(st, Vector3(-0.32, 0.06, 0.02), Vector3(0.5, 0.04, 0.2), Color(0.9, 0.92, 1.0))
	add_box(st, Vector3(0.32, 0.06, 0.02), Vector3(0.5, 0.04, 0.2), Color(0.9, 0.92, 1.0))
	add_box(st, Vector3(0, 0.02, -0.24), Vector3(0.06, 0.05, 0.1), Color(1.0, 0.7, 0.2))
	var m := _finish(st)
	Engine.set_meta(key, m)
	return m
