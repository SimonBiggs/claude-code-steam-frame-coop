extends RefCounted
## STARSHIP CREW: every mesh, built in code from core/mesh_kit.gd primitives and cached in
## core/res_cache.gd (one draw call per mesh, plus one for its glowing parts).
## The ship flies towards -Z; its cockpit seat floor is the origin; the pilot's eyes are about y = 1.2.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const VERSION := "v1"
const HULL := Color(0.95, 0.96, 1.0)
const TRIM := Color(1.0, 0.5, 0.25)
const DARK := Color(0.22, 0.24, 0.32)
## Where the crew's lasers come from (the wing-tip turrets).
const TURRETS: Array[Vector3] = [Vector3(-3.6, 0.15, -1.2), Vector3(3.6, 0.15, -1.2)]


static func _cached(key: String, maker: Callable) -> ArrayMesh:
	return ResCache.get_or_make("sc_%s_%s" % [key, VERSION], maker) as ArrayMesh


## The outside of the little starship: belly, nose, wings with turrets, tail fins, glowing engines.
static func ship() -> ArrayMesh:
	return _cached("ship", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.ellipsoid(Vector3(1.7, 1.0, 4.2), MeshKit.at(Vector3(0, -0.35, 0.8)), HULL, 20)
		b.ellipsoid(Vector3(1.2, 0.6, 2.2), MeshKit.at(Vector3(0, -0.25, -2.6)), HULL, 16)
		b.ellipsoid(Vector3(0.55, 0.35, 0.8), MeshKit.at(Vector3(0, -0.15, -4.5)), TRIM, 12)
		b.torus(1.55, 0.14, MeshKit.at(Vector3(0, 0.02, -0.2)), TRIM, 24, 6)
		for sx in [-1.0, 1.0]:
			var s: float = sx
			b.box(Vector3(2.6, 0.18, 1.6), MeshKit.at(Vector3(s * 2.4, -0.3, 0.2), Vector3.ONE, Vector3(0, -s * 0.25, s * 0.08)), HULL)
			b.box(Vector3(2.2, 0.1, 0.35), MeshKit.at(Vector3(s * 2.5, -0.18, 0.75), Vector3.ONE, Vector3(0, -s * 0.25, s * 0.08)), TRIM)
			b.capsule_between(Vector3(s * 3.6, 0.15, 0.4), Vector3(s * 3.6, 0.15, -1.6), 0.24, DARK, 10)
			b.sphere(0.13, MeshKit.at(Vector3(s * 3.6, 0.15, -1.75)), Color(0.5, 1.0, 1.0), 8, true)
			b.box(Vector3(0.15, 1.1, 1.2), MeshKit.at(Vector3(s * 0.9, 0.6, 3.9), Vector3.ONE, Vector3(-0.3, 0, s * 0.25)), TRIM)
			b.cylinder(0.42, 0.5, 0.8, MeshKit.at(Vector3(s * 1.0, -0.4, 4.6), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), DARK, 14)
			b.disc(0.34, MeshKit.at(Vector3(s * 1.0, -0.4, 5.02), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.4, 0.9, 1.0), 14, true)
		b.box(Vector3(2.2, 0.06, 2.4), MeshKit.at(Vector3(0, -0.02, 0.0)), DARK)  # cockpit floor
		return b.build())


## The see-through canopy bubble (drawn with a culled transparent material, so the pilot doesn't
## see it from inside).
static func canopy() -> ArrayMesh:
	return _cached("canopy", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.dome(1.55, MeshKit.at(Vector3(0, 0.02, -0.2), Vector3(1.0, 1.15, 1.25)), Color(0.6, 0.9, 1.0), 20, false, false)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.6, 0.9, 1.0, 0.18)
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.metallic_specular = 1.0
		m.roughness = 0.1
		return b.build(m))


## The dashboard in front of the pilot and the seat behind.
static func dash() -> ArrayMesh:
	return _cached("dash", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(1.5, 0.5, 0.42), 0.08, MeshKit.at(Vector3(0, 0.48, -0.78), Vector3.ONE, Vector3(-0.35, 0, 0)), DARK, 2)
		b.rounded_box(Vector3(1.4, 0.06, 0.34), 0.03, MeshKit.at(Vector3(0, 0.76, -0.72), Vector3.ONE, Vector3(-0.35, 0, 0)), Color(0.32, 0.36, 0.48), 2)
		b.box(Vector3(0.22, 0.3, 0.22), MeshKit.at(Vector3(0.36, 0.45, -0.32)), DARK)  # stick pedestal
		b.cylinder(0.07, 0.09, 0.04, MeshKit.at(Vector3(0.36, 0.62, -0.32)), Color(0.4, 0.42, 0.5), 14)
		b.rounded_box(Vector3(0.7, 0.14, 0.6), 0.06, MeshKit.at(Vector3(0, 0.38, 0.38)), TRIM, 2)  # seat
		b.rounded_box(Vector3(0.7, 0.8, 0.14), 0.06, MeshKit.at(Vector3(0, 0.8, 0.72), Vector3.ONE, Vector3(0.15, 0, 0)), TRIM, 2)
		return b.build())


## The flight stick (pivot at its base, handle up +Y, the top about 0.24 m up).
static func stick() -> ArrayMesh:
	return _cached("stick", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.02, 0.026, 0.16, MeshKit.at(Vector3(0, 0.08, 0)), Color(0.75, 0.78, 0.85), 10)
		b.capsule(0.045, 0.13, MeshKit.at(Vector3(0, 0.19, 0)), Color(1.0, 0.35, 0.35), 12)
		b.sphere(0.025, MeshKit.at(Vector3(0, 0.27, 0)), Color(1.0, 0.95, 0.5), 8, true)
		return b.build())


## A big round push button (top at y = 0.04); the colour goes on the glowing cap.
static func button(col: Color) -> ArrayMesh:
	return _cached("button_" + col.to_html(false), func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.065, 0.07, 0.025, MeshKit.at(Vector3(0, 0.0125, 0)), Color(0.85, 0.87, 0.92), 16)
		b.cylinder(0.05, 0.052, 0.03, MeshKit.at(Vector3(0, 0.035, 0)), col, 16, true)
		return b.build())


## The wobbly alien bobble-head on the dashboard (pivot at its spring).
static func bobble() -> ArrayMesh:
	return _cached("bobble", func() -> Resource:
		var b := MeshKit.Builder.new()
		var g := Color(0.45, 0.95, 0.5)
		b.sphere(0.06, MeshKit.at(Vector3(0, 0.08, 0)), g, 14)
		for sx in [-1.0, 1.0]:
			var s: float = sx
			b.sphere(0.018, MeshKit.at(Vector3(s * 0.025, 0.1, 0.05)), Color.WHITE, 8)
			b.sphere(0.009, MeshKit.at(Vector3(s * 0.025, 0.1, 0.066)), Color(0.05, 0.05, 0.1), 6)
			b.capsule_between(Vector3(s * 0.03, 0.13, 0), Vector3(s * 0.06, 0.2, 0), 0.006, g, 6)
			b.sphere(0.015, MeshKit.at(Vector3(s * 0.06, 0.2, 0)), Color(1.0, 0.5, 0.8), 8, true)
		b.capsule_between(Vector3(-0.02, 0.055, 0.055), Vector3(0.02, 0.055, 0.055), 0.006, Color(0.1, 0.2, 0.1), 6)
		b.cylinder(0.008, 0.008, 0.03, MeshKit.at(Vector3(0, 0.015, 0)), Color(0.8, 0.8, 0.8), 6)
		return b.build())


## A little five-point star (lamps on the dashboard, flying stars).
static func star() -> ArrayMesh:
	return _cached("star", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.star(5, 1.0, 0.45, 0.35, MeshKit.at(Vector3.ZERO), Color.WHITE)
		return b.build(MeshKit.vertex_material(true)))


## A flying ring to steer through (radius 2.6, facing +Z). Glows.
static func ring() -> ArrayMesh:
	return _cached("ring", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.torus(2.6, 0.16, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color.WHITE, 28, 6, true)
		for k in 8:
			var a := k * TAU / 8.0
			b.sphere(0.24, MeshKit.at(Vector3(cos(a) * 2.6, sin(a) * 2.6, 0)), Color(1.0, 0.95, 0.6), 8, true)
		return b.build())


## A lumpy space rock (about 2 m across; scale it). variant 0..2.
static func rock(variant: int) -> ArrayMesh:
	return _cached("rock_%d" % variant, func() -> Resource:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		var arrays := sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base: Color = [Color(0.62, 0.52, 0.45), Color(0.55, 0.5, 0.62), Color(0.68, 0.58, 0.42)][variant % 3]
		for i in range(0, idx.size(), 3):
			var tri: Array[Vector3] = []
			for k in 3:
				var v := verts[idx[i + k]]
				var h := sin(v.x * 4.1 + variant * 1.7) * cos(v.y * 3.3 - variant) * sin(v.z * 3.7 + 0.5)
				tri.append(v * (0.82 + 0.28 * h))
			var n := (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			var shade := base.darkened(0.15 * absf(sin(float(i) * 0.37)))
			for k in 3:
				st.set_color(shade)
				st.set_normal(-n)
				st.add_vertex(tri[k])
		var m := st.commit()
		m.surface_set_material(0, MeshKit.vertex_material(false, false))
		return m)


## A silly wobbly alien saucer (about 3 m across) with a googly-eyed alien in the bubble.
static func ufo() -> ArrayMesh:
	return _cached("ufo", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.ellipsoid(Vector3(1.6, 0.4, 1.6), MeshKit.at(Vector3.ZERO), Color(0.75, 0.45, 1.0), 18)
		b.torus(1.5, 0.12, MeshKit.at(Vector3(0, -0.05, 0)), Color(1.0, 0.85, 0.3), 20, 5)
		b.dome(0.8, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.55, 0.9, 1.0), 14)
		b.sphere(0.32, MeshKit.at(Vector3(0, 0.55, 0.15)), Color(0.5, 1.0, 0.5), 12)
		for sx in [-1.0, 1.0]:
			var s: float = sx
			b.sphere(0.12, MeshKit.at(Vector3(s * 0.13, 0.65, 0.4)), Color.WHITE, 8)
			b.sphere(0.06, MeshKit.at(Vector3(s * 0.13, 0.65, 0.5)), Color(0.05, 0.05, 0.1), 6)
		for k in 6:
			var a := k * TAU / 6.0
			b.sphere(0.13, MeshKit.at(Vector3(cos(a) * 1.25, -0.15, sin(a) * 1.25)), [Color(1, 0.4, 0.4), Color(0.4, 1, 0.5), Color(0.4, 0.7, 1)][k % 3], 6, true)
		return b.build())


## The space station at the end: a big friendly wheel with a glowing docking ring at its centre
## (facing +Z, the dock opening about 5 m across).
static func station() -> ArrayMesh:
	return _cached("station", func() -> Resource:
		var b := MeshKit.Builder.new()
		var cream := Color(1.0, 0.95, 0.88)
		var pink := Color(1.0, 0.62, 0.78)
		var x90 := Vector3(PI * 0.5, 0, 0)
		b.torus(22.0, 3.0, MeshKit.at(Vector3(0, 0, -6.0), Vector3.ONE, x90), cream, 36, 10)
		for k in 6:
			var a := k * TAU / 6.0 + 0.26
			b.capsule_between(Vector3(cos(a) * 5.5, sin(a) * 5.5, -6.0), Vector3(cos(a) * 20.0, sin(a) * 20.0, -6.0), 1.0, pink, 8)
		b.cylinder(6.0, 6.0, 6.0, MeshKit.at(Vector3(0, 0, -6.0), Vector3.ONE, x90), Color(0.6, 0.85, 1.0), 24, false, false)
		b.torus(5.0, 0.6, MeshKit.at(Vector3(0, 0, -3.0), Vector3.ONE, x90), Color(1.0, 0.9, 0.4), 28, 6, true)
		for k in 24:
			var a2 := k * TAU / 24.0
			b.sphere(0.7, MeshKit.at(Vector3(cos(a2) * 22.0, sin(a2) * 22.0, -2.8)), [Color(1, 0.5, 0.6), Color(0.5, 0.9, 1), Color(1, 0.9, 0.4)][k % 3], 6, true)
		return b.build())


## A ringed planet (radius 1; scale it).
static func planet(col: Color, ring_col: Color) -> ArrayMesh:
	return _cached("planet_%s_%s" % [col.to_html(false), ring_col.to_html(false)], func() -> Resource:
		var b := MeshKit.Builder.new()
		b.sphere(1.0, MeshKit.at(Vector3.ZERO), col, 24)
		b.ellipsoid(Vector3(1.01, 0.35, 1.01), MeshKit.at(Vector3(0, 0.25, 0)), col.lightened(0.15), 24)
		b.ellipsoid(Vector3(1.005, 0.2, 1.005), MeshKit.at(Vector3(0, -0.4, 0)), col.darkened(0.15), 24)
		if ring_col.a > 0.0:
			b.torus(1.7, 0.18, MeshKit.at(Vector3.ZERO, Vector3(1, 0.12, 1), Vector3(0.3, 0, 0.2)), ring_col, 36, 4)
		return b.build(MeshKit.vertex_material(true)))


## Space dust streaming past (a thin streak 1 m long along Z), drawn additive.
static func streak() -> ArrayMesh:
	return _cached("streak", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.box(Vector3(0.05, 0.05, 1.0), MeshKit.at(Vector3.ZERO), Color(0.8, 0.9, 1.0))
		return b.build(MeshKit.additive_material()))


## A laser beam: a glowing rod 1 m long along -Z from the origin (scale z).
static func beam() -> ArrayMesh:
	return _cached("beam", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.box(Vector3(0.12, 0.12, 1.0), MeshKit.at(Vector3(0, 0, -0.5)), Color.WHITE, true)
		return b.build())


## The robot autopilot's head (local play without a headset sits it in the pilot's seat).
static func robot_head() -> ArrayMesh:
	return _cached("robot", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(0.36, 0.3, 0.3), 0.08, MeshKit.at(Vector3.ZERO), Color(0.8, 0.85, 0.95), 2)
		b.box(Vector3(0.28, 0.1, 0.02), MeshKit.at(Vector3(0, 0.02, -0.15)), Color(0.2, 0.9, 1.0), true)
		b.capsule_between(Vector3(0, 0.15, 0), Vector3(0, 0.3, 0), 0.012, Color(0.6, 0.6, 0.7), 6)
		b.sphere(0.035, MeshKit.at(Vector3(0, 0.31, 0)), Color(1.0, 0.4, 0.4), 8, true)
		return b.build())
