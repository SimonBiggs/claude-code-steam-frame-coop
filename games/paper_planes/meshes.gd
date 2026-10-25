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


## Inner radius of a hoop of `kind` (skygen.gd kinds: 0 plain, 1 rainbow, 2 chain, 3 tiny, 4 gate, 5 gold).
static func radius(kind: int) -> float:
	match kind:
		3:
			return 0.55
		4:
			return 1.25
	return HOOP_R


const CHAIN_COLOR := Color(0.2, 0.85, 0.85)
const TINY_COLOR := Color(1.0, 0.45, 0.75)
const GATE_COLOR := Color(1.0, 0.95, 0.85)
const GOLD_COLOR := Color(1.0, 0.8, 0.2)


## A hoop facing +Z (fly along Z through it). kind 0 = plain colour `ci`, 1 = rainbow (glows),
## 2 = chain (teal, numbered by main.gd), 3 = tiny (pink), 4 = gate (big, white, tinted by its breeze),
## 5 = Gust's gold hoop (glows).
static func hoop(kind: int, ci: int) -> ArrayMesh:
	var key := "pp_hoop_%d_%d" % [kind, ci if kind == 0 else 0]
	return ResCache.get_or_make(key, func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var face := Basis(Vector3.RIGHT, PI * 0.5)  # torus axis Y -> Z
		var r := radius(kind)
		match kind:
			1:
				for i in RAINBOW.size():
					b.torus(r + 0.04 + i * 0.065, 0.04, Transform3D(face, Vector3.ZERO), RAINBOW[i], 28, 6, true)
			2:
				b.torus(r + 0.1, 0.1, Transform3D(face, Vector3.ZERO), CHAIN_COLOR, 28, 8)
				for k in 8:  # little beads: reads as "a chain"
					var a := TAU * k / 8.0
					b.sphere(0.13, MeshKit.at(Vector3(cos(a), sin(a), 0.0) * (r + 0.1)), CHAIN_COLOR.lightened(0.5), 6)
			3:
				b.torus(r + 0.07, 0.07, Transform3D(face, Vector3.ZERO), TINY_COLOR, 24, 6)
				b.torus(r + 0.01, 0.03, Transform3D(face, Vector3.ZERO), TINY_COLOR.lightened(0.6), 24, 4, true)
			4:
				b.torus(r + 0.12, 0.12, Transform3D(face, Vector3.ZERO), GATE_COLOR, 32, 8)
				b.torus(r + 0.02, 0.04, Transform3D(face, Vector3.ZERO), GATE_COLOR, 32, 4, true)
			5:
				b.torus(r + 0.1, 0.1, Transform3D(face, Vector3.ZERO), GOLD_COLOR, 28, 8, true)
				for k in 6:
					var a := TAU * k / 6.0
					b.star(5, 0.16, 0.07, 0.04, MeshKit.at(Vector3(cos(a), sin(a), 0.0) * (r + 0.1)), Color(1.0, 0.95, 0.6), true)
			_:
				var c: Color = HOOP_COLORS[ci % HOOP_COLORS.size()]
				b.torus(r + 0.1, 0.1, Transform3D(face, Vector3.ZERO), c, 28, 8)
				b.torus(r + 0.02, 0.04, Transform3D(face, Vector3.ZERO), c.lightened(0.55), 28, 4, true)
		return b.build()) as ArrayMesh


## A grumpy storm cloud (about 1.3 m radius) with a cross little face looking along +Z.
static func storm_cloud() -> ArrayMesh:
	return ResCache.get_or_make("pp_storm_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var grey := Color(0.48, 0.5, 0.62)
		for q in [[Vector3(0, 0, 0), 0.95], [Vector3(-0.8, -0.2, 0.1), 0.7], [Vector3(0.85, -0.15, 0.0), 0.72],
				[Vector3(0.3, 0.5, -0.1), 0.65], [Vector3(-0.35, 0.45, 0.1), 0.6], [Vector3(0.0, -0.35, -0.4), 0.7]]:
			b.sphere(q[1], MeshKit.at(q[0]), grey, 12)
		for side in [-1.0, 1.0]:
			b.sphere(0.17, MeshKit.at(Vector3(side * 0.3, 0.12, 0.86)), Color.WHITE, 8)
			b.sphere(0.09, MeshKit.at(Vector3(side * 0.28, 0.1, 1.0)), Color(0.08, 0.08, 0.12), 6)
			b.box(Vector3(0.32, 0.06, 0.06), MeshKit.at(Vector3(side * 0.3, 0.36, 0.9), Vector3.ONE, Vector3(0, 0, side * 0.35)), Color(0.2, 0.2, 0.28))
		b.box(Vector3(0.36, 0.06, 0.06), MeshKit.at(Vector3(0.0, -0.22, 0.92)), Color(0.2, 0.2, 0.28))
		return b.build()) as ArrayMesh


## A little lightning zigzag (glows), hung under a storm cloud.
static func zap() -> ArrayMesh:
	return ResCache.get_or_make("pp_zap_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var y := Color(1.0, 0.92, 0.35)
		b.tube(Vector3(0.0, 0.0, 0.0), Vector3(-0.2, -0.45, 0.0), 0.05, 0.05, y, 5, true)
		b.tube(Vector3(-0.2, -0.45, 0.0), Vector3(0.12, -0.6, 0.0), 0.05, 0.05, y, 5, true)
		b.tube(Vector3(0.12, -0.6, 0.0), Vector3(-0.08, -1.05, 0.0), 0.05, 0.02, y, 5, true)
		return b.build()) as ArrayMesh


## Gust the wind sprite: a pale blue puff with a happy face (faces +Z), ~0.6 m.
static func gust() -> ArrayMesh:
	return ResCache.get_or_make("pp_gust_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var c := Color(0.75, 0.9, 1.0)
		b.sphere(0.42, MeshKit.at(Vector3.ZERO), c, 14)
		b.sphere(0.25, MeshKit.at(Vector3(-0.4, -0.12, -0.1)), c, 10)
		b.sphere(0.22, MeshKit.at(Vector3(0.42, -0.1, -0.1)), c, 10)
		b.cone(0.18, 0.5, MeshKit.at(Vector3(0.0, 0.0, -0.55), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), c, 8)
		for side in [-1.0, 1.0]:
			b.sphere(0.1, MeshKit.at(Vector3(side * 0.15, 0.08, 0.37)), Color(0.1, 0.12, 0.25), 6)
			b.sphere(0.07, MeshKit.at(Vector3(side * 0.27, -0.06, 0.34)), Color(1.0, 0.6, 0.7), 6)
		b.box(Vector3(0.14, 0.04, 0.04), MeshKit.at(Vector3(0.0, -0.08, 0.41)), Color(0.1, 0.12, 0.25))
		return b.build()) as ArrayMesh


## One place in the valley (story.gd chapters 0-4) built up to `stage` (0 = an empty lot with a
## crate and a little flag, 1-3 = more of it). Origin at the ground, front facing +Z.
static func place(chapter: int, stage: int) -> ArrayMesh:
	return ResCache.get_or_make("pp_place_%d_%d_v1" % [chapter, stage], func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var wood := Color(0.72, 0.5, 0.3)
		if stage <= 0:
			b.box(Vector3(0.9, 0.9, 0.9), MeshKit.at(Vector3(0.6, 0.45, 0.4)), wood)
			b.cylinder(0.04, 0.04, 2.0, MeshKit.at(Vector3(-0.6, 1.0, 0.0)), wood.darkened(0.3), 6)
			b.box(Vector3(0.7, 0.45, 0.03), MeshKit.at(Vector3(-0.25, 1.75, 0.0)), Color(1.0, 0.85, 0.3))
			b.disc(2.2, MeshKit.at(Vector3(0.0, 0.02, 0.0)), Color(0.62, 0.5, 0.36), 16)
			return b.build()
		b.disc(2.6, MeshKit.at(Vector3(0.0, 0.02, 0.0)), Color(0.62, 0.5, 0.36), 18)
		match chapter:
			0:  # farmhouse: walls, then roof and door, then chimney, windows and fence
				var red := Color(0.9, 0.35, 0.3)
				b.box(Vector3(3.2, 1.0 if stage == 1 else 2.0, 2.4), MeshKit.at(Vector3(0.0, 0.5 if stage == 1 else 1.0, 0.0)), red)
				if stage >= 2:
					b.prism(3, 1.5, 3.4, MeshKit.at(Vector3(0.0, 2.6, 0.0), Vector3(1.0, 0.9, 1.0), Vector3(0.0, 0.0, PI * 0.5)), Color(0.95, 0.9, 0.8))
					b.box(Vector3(0.6, 1.1, 0.05), MeshKit.at(Vector3(0.0, 0.55, 1.22)), Color(0.45, 0.28, 0.15))
				if stage >= 3:
					b.box(Vector3(0.4, 1.0, 0.4), MeshKit.at(Vector3(0.9, 3.1, -0.3)), Color(0.6, 0.6, 0.65))
					for x in [-1.0, 1.0]:
						b.box(Vector3(0.5, 0.5, 0.05), MeshKit.at(Vector3(x, 1.3, 1.22)), Color(1.0, 0.9, 0.5), true)
					for i in 7:
						b.box(Vector3(0.08, 0.6, 0.08), MeshKit.at(Vector3(-2.4 + i * 0.8, 0.3, 2.0)), Color.WHITE)
					b.box(Vector3(5.0, 0.08, 0.06), MeshKit.at(Vector3(0.0, 0.45, 2.0)), Color.WHITE)
			1:  # apple barn
				var barn := Color(0.75, 0.25, 0.22)
				b.box(Vector3(3.0, 1.2 if stage == 1 else 2.6, 3.0), MeshKit.at(Vector3(0.0, 0.6 if stage == 1 else 1.3, 0.0)), barn)
				if stage >= 2:
					b.prism(3, 1.7, 3.2, MeshKit.at(Vector3(0.0, 3.2, 0.0), Vector3(1.0, 0.8, 1.0), Vector3(0.0, 0.0, PI * 0.5)), Color(0.4, 0.3, 0.25))
					b.box(Vector3(1.2, 1.6, 0.05), MeshKit.at(Vector3(0.0, 0.8, 1.52)), Color.WHITE)
				if stage >= 3:
					for i in 6:
						b.sphere(0.22, MeshKit.at(Vector3(-1.9 + (i % 3) * 0.3, 0.25 + (i / 3) * 0.3, 1.6)), Color(0.95, 0.2, 0.2), 8)
					b.cylinder(0.12, 0.15, 1.6, MeshKit.at(Vector3(2.2, 0.8, 0.6)), wood, 6)
					b.sphere(0.9, MeshKit.at(Vector3(2.2, 2.0, 0.6)), Color(0.35, 0.72, 0.32), 10)
			2:  # lighthouse
				var h: float = [1.6, 3.4, 4.2][stage - 1]
				for i in 4:
					var y0 := h * i / 4.0
					if y0 >= h:
						break
					b.cylinder(0.9 - i * 0.1, 1.0 - i * 0.1, h / 4.0, MeshKit.at(Vector3(0.0, y0 + h / 8.0, 0.0)), Color.WHITE if i % 2 == 0 else Color(0.9, 0.25, 0.25), 14)
				if stage >= 3:
					b.cylinder(0.6, 0.6, 0.7, MeshKit.at(Vector3(0.0, h + 0.35, 0.0)), Color(1.0, 0.95, 0.5), 12, true)
					b.cone(0.75, 0.6, MeshKit.at(Vector3(0.0, h + 1.0, 0.0)), Color(0.9, 0.25, 0.25), 12)
			3:  # mountain hut with a snowy roof
				var stone := Color(0.6, 0.58, 0.55)
				b.box(Vector3(2.6, 1.0 if stage == 1 else 1.8, 2.2), MeshKit.at(Vector3(0.0, 0.5 if stage == 1 else 0.9, 0.0)), stone)
				if stage >= 2:
					b.prism(3, 1.4, 2.8, MeshKit.at(Vector3(0.0, 2.3, 0.0), Vector3(1.0, 0.8, 1.0), Vector3(0.0, 0.0, PI * 0.5)), Color(0.95, 0.97, 1.0))
					b.box(Vector3(0.6, 1.0, 0.05), MeshKit.at(Vector3(0.0, 0.5, 1.12)), Color(0.4, 0.26, 0.15))
				if stage >= 3:
					b.box(Vector3(0.5, 0.45, 0.05), MeshKit.at(Vector3(0.8, 1.1, 1.12)), Color(1.0, 0.8, 0.4), true)
					b.cone(0.5, 1.4, MeshKit.at(Vector3(-1.8, 0.7, 0.6)), Color(0.25, 0.55, 0.3), 8)
					b.cone(0.4, 1.1, MeshKit.at(Vector3(1.9, 0.55, -0.5)), Color(0.25, 0.55, 0.3), 8)
			_:  # cloud castle (floats: main.gd lifts it into the sky)
				var wall := Color(0.92, 0.94, 1.0)
				for q in [[Vector3(-1.4, 0, 0.3), 1.1], [Vector3(0, -0.2, 0), 1.4], [Vector3(1.4, 0, 0.2), 1.1]]:
					b.sphere(q[1], MeshKit.at(q[0], Vector3(1.0, 0.5, 1.0)), Color.WHITE, 12)
				b.box(Vector3(2.4, 1.0 if stage == 1 else 1.8, 1.6), MeshKit.at(Vector3(0.0, 0.6 if stage == 1 else 1.0, 0.0)), wall)
				if stage >= 2:
					for x in [-1.3, 1.3]:
						b.cylinder(0.4, 0.4, 2.6, MeshKit.at(Vector3(x, 1.3, 0.0)), wall, 10)
						b.cone(0.5, 0.8, MeshKit.at(Vector3(x, 3.0, 0.0)), Color(0.6, 0.55, 1.0), 10)
				if stage >= 3:
					b.cylinder(0.45, 0.45, 1.4, MeshKit.at(Vector3(0.0, 2.6, 0.0)), wall, 10)
					b.cone(0.6, 1.0, MeshKit.at(Vector3(0.0, 3.8, 0.0)), Color(1.0, 0.8, 0.3), 10, true)
					b.box(Vector3(0.6, 0.9, 0.05), MeshKit.at(Vector3(0.0, 0.45 + 0.3, 0.82)), Color(0.55, 0.6, 0.95))
		if stage >= 3:  # a flag on top of every finished place
			b.cylinder(0.03, 0.03, 1.0, MeshKit.at(Vector3(-1.2, 4.6 if chapter == 2 else 3.6, 0.0)), Color(0.4, 0.3, 0.2), 5)
			b.box(Vector3(0.5, 0.3, 0.02), MeshKit.at(Vector3(-0.95, 4.95 if chapter == 2 else 3.95, 0.0)), Color(1.0, 0.85, 0.3))
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
