extends RefCounted
## Tower Stack meshes: smiley jelly blocks, the bouncy pickup pad, the tower base, the crane claw.
## Each is one merged, vertex-coloured mesh (one draw call), cached with core/res_cache.gd.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const BLOCK := 0.6
const COLORS: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.75, 0.2), Color(0.35, 0.85, 0.4),
	Color(0.3, 0.65, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.5, 0.8)]


static func block_color(id: int) -> Color:
	return COLORS[posmod(id, COLORS.size())]


## A rounded jelly cube with a happy face on two sides.
static func block_mesh(id: int) -> Mesh:
	var ci := posmod(id, COLORS.size())
	return ResCache.get_or_make("tower_stack_block_%d" % ci, func() -> Resource:
		var b := MeshKit.Builder.new()
		var c := COLORS[ci]
		b.rounded_box(Vector3.ONE * BLOCK, 0.12, Transform3D.IDENTITY, c, 2)
		var h := BLOCK * 0.5
		for side in [1.0, -1.0]:
			var s: float = side
			var rot := Vector3(0.0, 0.0 if s > 0.0 else PI, 0.0)
			var face := Basis.from_euler(rot)
			for ex in [-0.12, 0.12]:
				var x: float = ex
				b.sphere(0.075, Transform3D(face, face * Vector3(x, 0.07, h + 0.005)), Color(1, 1, 1), 10)
				b.sphere(0.04, Transform3D(face, face * Vector3(x, 0.06, h + 0.06)), Color(0.05, 0.05, 0.1), 8)
			b.box(Vector3(0.16, 0.035, 0.03), Transform3D(face, face * Vector3(0.0, -0.1, h + 0.005)), c.darkened(0.55))
			b.sphere(0.04, Transform3D(face, face * Vector3(-0.19, -0.05, h)), c.lightened(0.35), 8)
			b.sphere(0.04, Transform3D(face, face * Vector3(0.19, -0.05, h)), c.lightened(0.35), 8)
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
