extends RefCounted
## Procedural meshes and materials for Block Builders. Blocks are single merged ArrayMeshes (one
## draw call each) built from coloured boxes, cached on the Engine so restarts don't rebuild them.

const KINDS: Array[String] = ["plank", "stairs", "spring", "fan"]
const KIND_NAMES: Array[String] = ["PLANK", "STAIRS", "SPRING", "FAN"]
const KIND_COLORS: Array[Color] = [Color(1.0, 0.66, 0.28), Color(0.3, 0.72, 1.0), Color(1.0, 0.36, 0.62), Color(0.66, 0.48, 1.0)]
const MESH_VERSION := "v3"
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
	var m := _finish(st)
	Engine.set_meta(key, m)
	return m


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


## A floating island chunk: grass slab on top, dirt below, tapering rock underneath.
static func island_mesh(x0: float, x1: float, z0: float, z1: float, top: float, bottom: float, grass: Color) -> ArrayMesh:
	var st := _begin()
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	add_box(st, Vector3(cx, top - 0.12, cz), Vector3(w, 0.24, d), grass)
	var body_h := maxf(0.1, top - 0.24 - bottom)
	add_box(st, Vector3(cx, top - 0.24 - body_h * 0.5, cz), Vector3(w - 0.04, body_h, d - 0.04), Color(0.55, 0.38, 0.24))
	# Rocky underside (visual only).
	add_box(st, Vector3(cx, bottom - 0.5, cz), Vector3(w * 0.7, 1.0, d * 0.7), Color(0.45, 0.32, 0.22))
	add_box(st, Vector3(cx, bottom - 1.4, cz), Vector3(w * 0.35, 0.8, d * 0.35), Color(0.38, 0.27, 0.2))
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
