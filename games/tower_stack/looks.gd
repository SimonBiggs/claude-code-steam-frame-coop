extends RefCounted
## Tower Stack meshes: smiley jelly blocks, the bouncy pickup pad, the tower base, the crane claw.
## Each is one merged, vertex-coloured mesh (one draw call), cached with core/res_cache.gd.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const BLOCK := 0.6
const COLORS: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.75, 0.2), Color(0.35, 0.85, 0.4),
	Color(0.3, 0.65, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.5, 0.8)]


const STONE := Color(0.62, 0.63, 0.68)
const SIZES: Array[Vector3] = [Vector3(1, 1, 1), Vector3(2, 0.5, 1), Vector3(1, 0.5, 1), Vector3(1, 1, 1)]  # == towergen SIZE
const K_STONE := 3


static func block_color(ci: int, kind: int = 0) -> Color:
	return STONE if kind == K_STONE else COLORS[posmod(ci, COLORS.size())]


## A rounded jelly block (kind: cube, plank, slab, stone; see towergen.gd) with a happy face on its two
## long sides. Stones are grey and a bit sleepy (they're heavy).
static func block_mesh(kind: int, ci: int) -> Mesh:
	kind = clampi(kind, 0, SIZES.size() - 1)
	ci = posmod(ci, COLORS.size())
	return ResCache.get_or_make("tower_stack_block_%d_%d" % [kind, ci], func() -> Resource:
		var b := MeshKit.Builder.new()
		var c := block_color(ci, kind)
		var size := SIZES[kind] * BLOCK
		b.rounded_box(size, 0.12 if size.y > BLOCK * 0.6 else 0.07, Transform3D.IDENTITY, c, 2)
		var k := minf(size.y / BLOCK, 1.0) * 0.5 + 0.5  # smaller faces on flat blocks
		var h := size.z * 0.5
		var sleepy := kind == K_STONE
		for side in [1.0, -1.0]:
			var s: float = side
			var rot := Vector3(0.0, 0.0 if s > 0.0 else PI, 0.0)
			var face := Basis.from_euler(rot)
			var fy := 0.0 if size.y > BLOCK * 0.6 else 0.02
			for ex in [-0.12, 0.12]:
				var x: float = ex * k
				if sleepy:
					b.box(Vector3(0.12, 0.03, 0.02) * k, Transform3D(face, face * Vector3(x, fy + 0.06 * k, h + 0.005)), Color(0.15, 0.15, 0.2))
				else:
					b.sphere(0.075 * k, Transform3D(face, face * Vector3(x, fy + 0.07 * k, h + 0.005)), Color(1, 1, 1), 10)
					b.sphere(0.04 * k, Transform3D(face, face * Vector3(x, fy + 0.06 * k, h + 0.06 * k)), Color(0.05, 0.05, 0.1), 8)
			b.box(Vector3(0.16, 0.035, 0.03) * k, Transform3D(face, face * Vector3(0.0, fy - 0.1 * k, h + 0.005)), c.darkened(0.55))
			b.sphere(0.04 * k, Transform3D(face, face * Vector3(-0.19 * k, fy - 0.05 * k, h)), c.lightened(0.35), 8)
			b.sphere(0.04 * k, Transform3D(face, face * Vector3(0.19 * k, fy - 0.05 * k, h)), c.lightened(0.35), 8)
		return b.build())


## The roof a finished tower wears, by building (towergen BUILDINGS); its base sits at y = 0.
## gold: TODAY'S TOWER (a gold star on top).
static func topper_mesh(building: String, color: Color, gold: bool) -> Mesh:
	return ResCache.get_or_make("tower_stack_top_%s_%s_%d" % [building, color.to_html(false), int(gold)], func() -> Resource:
		var b := MeshKit.Builder.new()
		var red := Color(0.92, 0.3, 0.3)
		var top := 0.0
		match building:
			"lighthouse":
				b.cylinder(0.2, 0.22, 0.28, MeshKit.at(Vector3(0, 0.14, 0)), Color(1.0, 0.95, 0.6), 12, true)
				b.cone(0.3, 0.3, MeshKit.at(Vector3(0, 0.43, 0)), red)
				top = 0.58
			"castle":
				for k in 4:
					var a := k * TAU / 4.0 + PI / 4.0
					b.box(Vector3(0.14, 0.18, 0.14), MeshKit.at(Vector3(cos(a), 0.0, sin(a)) * 0.24 + Vector3(0, 0.09, 0)), color.lightened(0.3))
				b.cylinder(0.02, 0.02, 0.6, MeshKit.at(Vector3(0, 0.3, 0)), Color(0.4, 0.3, 0.25), 6)
				b.box(Vector3(0.28, 0.17, 0.02), MeshKit.at(Vector3(0.15, 0.5, 0)), color if not gold else Color(1.0, 0.8, 0.2))
				top = 0.62
			"clock":
				var blue := Color(0.35, 0.45, 0.85)
				b.box(Vector3(0.44, 0.36, 0.44), MeshKit.at(Vector3(0, 0.18, 0)), color.lightened(0.4))
				for sgn in [1.0, -1.0]:
					var face := Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))
					var z: float = 0.225 * float(sgn)
					b.cylinder(0.14, 0.14, 0.02, Transform3D(face, Vector3(0, 0.18, z)), Color(1, 1, 0.95), 16)
					b.box(Vector3(0.02, 0.1, 0.02), MeshKit.at(Vector3(0, 0.22, z * 1.07)), Color(0.1, 0.1, 0.15))
					b.box(Vector3(0.07, 0.02, 0.02), MeshKit.at(Vector3(0.03, 0.18, z * 1.07)), Color(0.1, 0.1, 0.15))
				b.cone(0.34, 0.36, MeshKit.at(Vector3(0, 0.54, 0)), blue)
				top = 0.72
			"windmill":
				b.cone(0.3, 0.32, MeshKit.at(Vector3(0, 0.16, 0)), red)
				for k in 4:
					var a := k * TAU / 4.0 + 0.4
					b.box(Vector3(0.08, 0.55, 0.02), Transform3D(Basis(Vector3.BACK, a), Vector3(0, 0.2, 0.32) + Vector3(-sin(a), cos(a), 0) * 0.28), Color(1, 0.97, 0.9))
				b.sphere(0.06, MeshKit.at(Vector3(0, 0.2, 0.33)), Color(0.5, 0.35, 0.25), 8)
				top = 0.5
			_:  # nest: a twiggy bowl with three eggs
				b.torus(0.24, 0.07, MeshKit.at(Vector3(0, 0.07, 0)), Color(0.6, 0.42, 0.25), 16, 6)
				b.cylinder(0.22, 0.18, 0.06, MeshKit.at(Vector3(0, 0.03, 0)), Color(0.5, 0.35, 0.2), 14)
				for k in 3:
					var a := k * TAU / 3.0
					b.ellipsoid(Vector3(0.06, 0.08, 0.06), MeshKit.at(Vector3(cos(a), 0, sin(a)) * 0.08 + Vector3(0, 0.12, 0)), Color(0.75, 0.9, 1.0), 8)
				top = 0.2
		if gold:
			b.star(5, 0.13, 0.06, 0.04, Transform3D(Basis.IDENTITY, Vector3(0, top + 0.15, 0)), Color(1.0, 0.82, 0.2), true)
		return b.build())


## A finished tower as one mesh (blocks in the job's palette + its roof), for the town. plan as towergen.
static func tower_model(plan: Array, palette: Array, building: String, gold: bool) -> Mesh:
	var key := "tower_stack_model_%s_%s_%s_%d" % [str(plan).md5_text(), str(palette), building, int(gold)]
	return ResCache.get_or_make(key, func() -> Resource:
		var b := MeshKit.Builder.new()
		var top := Vector3.ZERO
		for i in plan.size():
			var p: Array = plan[i]
			var kind := int(p[0])
			var size := SIZES[kind] * BLOCK
			var c := block_color(int(palette[i % palette.size()]), kind)
			var xf := Transform3D(Basis(Vector3.UP, PI * 0.5 * int(p[4])), Vector3(float(p[1]), float(p[2]), float(p[3])))
			b.rounded_box(size, 0.06, xf, c, 1)
			var t := Vector3(float(p[1]), float(p[2]) + size.y * 0.5, float(p[3]))
			if t.y >= top.y:
				top = t
		b.add_mesh(topper_mesh(building, block_color(int(palette[0])), gold), Transform3D(Basis.IDENTITY, top))
		return b.build())


## The wind sock: a striped cone on a pole (turned to the wind by main.gd).
static func sock_mesh() -> Mesh:
	return ResCache.get_or_make("tower_stack_sock", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.04, 0.05, 2.2, MeshKit.at(Vector3(0, 1.1, 0)), Color(0.85, 0.85, 0.9), 8)
		for k in 3:
			var r0 := 0.16 - k * 0.035
			var face := Basis.from_euler(Vector3(0.0, 0.0, -PI * 0.5))
			b.cylinder(r0 - 0.035, r0, 0.22, Transform3D(face, Vector3(0.11 + 0.22 * k + 0.05, 2.1, 0)),
				Color(1.0, 0.45, 0.2) if k % 2 == 0 else Color(1, 1, 1), 10)
		return b.build())


## The bouncy pickup pad: a trampoline with a glowing top.
static func pad_mesh(radius: float) -> Mesh:
	return ResCache.get_or_make("tower_stack_pad_%.2f" % radius, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(radius, radius, 0.12, MeshKit.at(Vector3(0, 0.06, 0)), Color(0.25, 0.3, 0.45), 20)
		b.torus(radius, 0.08, MeshKit.at(Vector3(0, 0.13, 0)), Color(1.0, 0.85, 0.25), 20, 8)
		b.cylinder(radius - 0.08, radius - 0.08, 0.02, MeshKit.at(Vector3(0, 0.135, 0)), Color(0.3, 0.95, 1.0), 20, true)
		for k in 3:
			var a := k * TAU / 3.0
			b.cylinder(0.05, 0.05, 0.5, MeshKit.at(Vector3(cos(a), -0.15, sin(a)) * radius), Color(0.25, 0.3, 0.45), 8)
		return b.build())


## The tower base: a striped round stage.
static func base_mesh(radius: float, height: float) -> Mesh:
	return ResCache.get_or_make("tower_stack_base_%.2f" % radius, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(radius, radius + 0.1, height, MeshKit.at(Vector3(0, height * 0.5, 0)), Color(0.95, 0.92, 0.85), 24)
		b.cylinder(radius * 0.55, radius * 0.55, 0.02, MeshKit.at(Vector3(0, height + 0.005, 0)), Color(1.0, 0.6, 0.3), 24)
		b.torus(radius, 0.05, MeshKit.at(Vector3(0, height, 0)), Color(1.0, 0.45, 0.4), 24, 6)
		return b.build())


## The record line: a glowing hoop.
static func ring_mesh(radius: float) -> Mesh:
	return ResCache.get_or_make("tower_stack_ring_%.2f" % radius, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.torus(radius, 0.04, Transform3D.IDENTITY, Color(1.0, 0.85, 0.2), 32, 6, true)
		for k in 8:
			var a := k * TAU / 8.0
			b.sphere(0.09, MeshKit.at(Vector3(cos(a), 0.0, sin(a)) * radius), Color(1.0, 1.0, 0.7), 8, true)
		return b.build())


## The helper crane's claw (used when nobody is in VR); the cable is a separate thin box.
static func claw_mesh() -> Mesh:
	return ResCache.get_or_make("tower_stack_claw", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(0.6, 0.25, 0.6), 0.08, MeshKit.at(Vector3(0, 0.15, 0)), Color(1.0, 0.75, 0.2), 2)
		for k in 4:
			var a := k * TAU / 4.0 + PI / 4.0
			var d := Vector3(cos(a), 0.0, sin(a))
			b.capsule_between(d * 0.25 + Vector3(0, 0.05, 0), d * 0.42 - Vector3(0, 0.3, 0), 0.05, Color(0.3, 0.3, 0.4), 8)
		b.sphere(0.1, MeshKit.at(Vector3(0, 0.32, 0)), Color(1.0, 0.3, 0.3), 10, true)
		return b.build())
