extends RefCounted
## Paper Planes: the few meshes the game builds in code (paper plane, hoops, the paper stack).
## Cached through core/res_cache.gd so hot reloads and many planes share one mesh each.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const HOOP_R := 0.85  ## inner radius of a hoop (metres)
const HOOP_COLORS: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.62, 0.15), Color(0.3, 0.85, 0.4),
	Color(0.3, 0.6, 1.0), Color(1.0, 0.45, 0.8), Color(0.65, 0.45, 1.0)]
const RAINBOW: Array[Color] = [Color(1.0, 0.25, 0.25), Color(1.0, 0.6, 0.1), Color(1.0, 0.92, 0.2),
	Color(0.3, 0.9, 0.35), Color(0.25, 0.6, 1.0), Color(0.7, 0.4, 1.0)]


## A folded paper plane, 1 m long, nose at -Z, wings up a little. White: tint it with the material.
static func plane() -> ArrayMesh:
	return ResCache.get_or_make("pp_plane_v2", func() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var nose := Vector3(0.0, 0.0, -0.5)
		var mid := Vector3(0.0, 0.0, 0.5)
		var lt := Vector3(-0.46, 0.09, 0.5)
		var rt := Vector3(0.46, 0.09, 0.5)
		var lf := Vector3(-0.2, 0.03, 0.5)  # the fold line on each wing (two shades read as "folded")
		var rf := Vector3(0.2, 0.03, 0.5)
		var keel := Vector3(0.0, -0.14, 0.45)
		var light := Color(1.0, 1.0, 1.0)
		var shade := Color(0.86, 0.88, 0.92)
		var dark := Color(0.72, 0.74, 0.8)
		for tri: Array in [[nose, mid, lf, light], [nose, lf, lt, shade], [nose, rf, mid, light], [nose, rt, rf, shade],
				[nose, keel, mid, dark]]:
			var c: Color = tri[3]
			for k in 3:
				st.set_color(c)
				st.add_vertex(tri[k])
		st.generate_normals()
		return st.commit()) as ArrayMesh


## Material for a plane of one colour (double-sided paper).
static func plane_material(tint: Color) -> StandardMaterial3D:
	return ResCache.get_or_make("pp_plane_mat_%s" % tint.to_html(false), func() -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = tint
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.9
		return m) as StandardMaterial3D


## A hoop facing +Z (fly along Z through it). kind 0 = plain colour `ci`, 1 = rainbow (glows).
static func hoop(kind: int, ci: int) -> ArrayMesh:
	return ResCache.get_or_make("pp_hoop_%d_%d" % [kind, ci], func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var face := Basis(Vector3.RIGHT, PI * 0.5)  # torus axis Y -> Z
		if kind == 1:
			for i in RAINBOW.size():
				b.torus(HOOP_R + 0.04 + i * 0.065, 0.04, Transform3D(face, Vector3.ZERO), RAINBOW[i], 28, 6, true)
		else:
			var c: Color = HOOP_COLORS[ci % HOOP_COLORS.size()]
			b.torus(HOOP_R + 0.1, 0.1, Transform3D(face, Vector3.ZERO), c, 28, 8)
			b.torus(HOOP_R + 0.02, 0.04, Transform3D(face, Vector3.ZERO), c.lightened(0.55), 28, 4, true)
		return b.build()) as ArrayMesh


## The stack of paper on its little stand (origin at the floor; top sheet at y = 0.95).
static func stack() -> ArrayMesh:
	return ResCache.get_or_make("pp_stack_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var wood := Color(0.75, 0.5, 0.3)
		b.cylinder(0.04, 0.05, 0.82, MeshKit.at(Vector3(0.0, 0.41, 0.0)), wood, 10)
		b.cylinder(0.2, 0.2, 0.03, MeshKit.at(Vector3(0.0, 0.015, 0.0)), wood.darkened(0.2), 14)
		b.rounded_box(Vector3(0.36, 0.04, 0.3), 0.015, MeshKit.at(Vector3(0.0, 0.84, 0.0)), Color(1.0, 0.45, 0.4))
		var sheet_cols: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.0, 0.95, 0.6), Color(0.75, 0.9, 1.0), Color(1.0, 0.8, 0.9)]
		for i in 7:
			var rot := Vector3(0.0, sin(i * 1.7) * 0.12, 0.0)
			b.box(Vector3(0.3, 0.012, 0.22), MeshKit.at(Vector3(0.0, 0.866 + i * 0.013, 0.0), Vector3.ONE, rot), sheet_cols[i % 4])
		return b.build()) as ArrayMesh
