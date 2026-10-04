extends RefCounted
## MeshKit: bake many vertex-coloured primitives into ONE ArrayMesh, so a detailed prop, building or
## character costs a single draw call (two if some parts glow), plus MultiMesh helpers for crowds,
## props and foliage, and a set of ready-made props.
##
##   const MeshKit := preload("res://core/mesh_kit.gd")
##   var b := MeshKit.Builder.new()
##   b.box(Vector3(1, 0.2, 1), MeshKit.at(Vector3(0, 0.1, 0)), Color(0.6, 0.4, 0.25))
##   b.sphere(0.3, MeshKit.at(Vector3(0, 0.6, 0)), Color(1.0, 0.5, 0.4))
##   b.sphere(0.08, MeshKit.at(Vector3(0, 1.0, 0)), Color(1.0, 0.9, 0.4), 10, true)   # glows
##   add_child(MeshKit.instance(b.build()))
##
## Every primitive is centred on its local origin (like Godot's PrimitiveMeshes) unless noted; the
## part transform places, rotates and (non-uniformly) scales it, with correct normals and winding
## (mirrored transforms are handled). Parts flagged `emissive` go to a second surface drawn with an
## unshaded, slightly over-bright material: +1 draw call per mesh, so group glowing bits together.
## Build meshes once and cache them (ResCache.get_or_make) rather than rebuilding per instance.

const ResCache := preload("res://core/res_cache.gd")
const Me := preload("res://core/mesh_kit.gd")

## Default segment count for round shapes (keep <= 20 for the Steam Frame's phone-class GPU).
const SEGMENTS := 12
## Glowing parts are drawn this much brighter than their vertex colour (so TV glow catches them).
const GLOW_BOOST := 1.35
## Ready-made props (see prop()).
const PROPS: Array[String] = ["tree", "pine", "palm", "bush", "rock", "grass", "flower", "mushroom", "crate",
	"barrel", "chest", "lamp_post", "torch", "fence", "sign", "cloud", "coin", "gem", "heart", "star", "table",
	"chair", "bookshelf", "candle", "pot"]


# --- Transforms ---------------------------------------------------------------------------------

## Part transform: position, scale and Euler rotation (radians, YXZ order like Node3D.rotation).
static func at(pos: Vector3, scale: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale), pos)


## Part transform that points a primitive's +Y axis along `dir` (horns, spikes, limbs, beams).
static func aim(pos: Vector3, dir: Vector3, scale: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Lib.basis_y_to(dir) * Basis.from_scale(scale), pos)


## A new, empty Builder (same as MeshKit.Builder.new()).
static func builder() -> Builder:
	return Builder.new()


# --- Materials ------------------------------------------------------------------------------------

## Shared material that shows baked vertex colours. unshaded: flat, evenly lit (signs, screens);
## transparent: honours vertex-colour alpha (ghosts, glass), drawn with a depth pre-pass.
static func vertex_material(unshaded: bool = false, transparent: bool = false) -> StandardMaterial3D:
	return Lib.vertex_material(unshaded, transparent)


## Shared unshaded material for glowing parts (vertex colour x GLOW_BOOST).
static func glow_material() -> StandardMaterial3D:
	return Lib.glow_material()


## Shared additive material (light shafts, sparkles, halos): vertex colour brightness = intensity.
static func additive_material() -> StandardMaterial3D:
	return Lib.additive_material()


## Shared plain material for one colour (glow > 0 adds emission of the same colour).
static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := "mk_mat_%s_%.2f" % [color.to_html(true), glow]
	var cached := ResCache.fetch(key) as StandardMaterial3D
	if cached != null:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	ResCache.put(key, m)
	return m


## A MeshInstance3D for `mesh` (shadows: cast shadows on the TV; VR scenes switch the sun's off anyway).
static func instance(mesh: Mesh, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Merging existing meshes ----------------------------------------------------------------------

## Merge parts in the games' older mesh_kit format into one ArrayMesh:
## [[Mesh, Transform3D, Color], [Mesh, Transform3D, Color, flag], ...] (flag goes to UV.x for shaders).
static func merge(parts: Array) -> ArrayMesh:
	var b := Builder.new()
	for part in parts:
		var a: Array = part
		var m: Mesh = a[0]
		var xf: Transform3D = a[1]
		var c: Color = a[2]
		b.flag = float(a[3]) if a.size() > 3 else 0.0
		b.add_mesh(m, xf, c)
	return b.build()


# --- MultiMesh ------------------------------------------------------------------------------------

## One MultiMeshInstance3D drawing `mesh` at every transform (ONE draw call for the lot).
## colors: per-instance tint multiplied with the vertex colours (empty = untinted);
## custom: per-instance custom data (INSTANCE_CUSTOM in shaders; empty = none).
static func scatter(mesh: Mesh, transforms: Array, colors: PackedColorArray = PackedColorArray(),
		custom: PackedColorArray = PackedColorArray(), shadows: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		mm.set_instance_transform(i, t)
		if mm.use_colors:
			mm.set_instance_color(i, colors[i % colors.size()])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom[i % custom.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Scatter `count` copies of `mesh` on the ground (y = 0) in a ring between min_r and max_r around
## `center`, with random yaw, scale in [scale_min, scale_max] and a tint picked from `palette`.
## Deterministic for a given seed. Returns ONE MultiMeshInstance3D (one draw call).
static func scatter_random(mesh: Mesh, count: int, center: Vector3, max_r: float, min_r: float = 0.0,
		scale_min: float = 0.8, scale_max: float = 1.2, palette: PackedColorArray = PackedColorArray(),
		seed_value: int = 1) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var xfs: Array = []
	var cols := PackedColorArray()
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(min_r * min_r, max_r * max_r))
		var s := rng.randf_range(scale_min, scale_max)
		var pos := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos))
		if not palette.is_empty():
			var c: Color = palette[rng.randi() % palette.size()]
			cols.append(c.lerp(Color.WHITE, rng.randf_range(0.0, 0.12)))
	return scatter(mesh, xfs, cols)


# --- Ready-made props -------------------------------------------------------------------------------

## A cached, ready-made prop mesh (ONE mesh; +1 surface when it has glowing bits like lamps/torches).
## names: see PROPS. variant: a small number that changes colours/shape a little. Origin at the base
## (y = 0), front towards +Z. Sizes are real-world-ish metres (a tree ~3 m, a crate 0.8 m).
static func prop(prop_name: String, variant: int = 0) -> ArrayMesh:
	var key := "mk_prop_%s_%d_v1" % [prop_name, variant]
	var cached := ResCache.fetch(key) as ArrayMesh
	if cached != null:
		return cached
	var m := Props.build(prop_name, variant)
	ResCache.put(key, m)
	return m


## The list of prop names prop() understands.
static func prop_names() -> Array[String]:
	return PROPS.duplicate()


# =================================================================================================

class Lib:
	## Internal helpers shared by the outer script and the inner classes.

	static func basis_y_to(dir: Vector3) -> Basis:
		var d := dir.normalized()
		if d.length_squared() < 0.5:
			return Basis()
		var dot := Vector3.UP.dot(d)
		if dot > 0.9999:
			return Basis()
		if dot < -0.9999:
			return Basis(Vector3.RIGHT, PI)
		var axis := Vector3.UP.cross(d).normalized()
		return Basis(axis, acos(clampf(dot, -1.0, 1.0)))

	static func vertex_material(unshaded: bool, transparent: bool) -> StandardMaterial3D:
		var key := "mk_vmat_%s_%s" % [unshaded, transparent]
		var cached := ResCache.fetch(key) as StandardMaterial3D
		if cached != null:
			return cached
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.82
		m.metallic_specular = 0.3
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if transparent:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		ResCache.put(key, m)
		return m

	static func glow_material() -> StandardMaterial3D:
		var cached := ResCache.fetch("mk_glowmat_v1") as StandardMaterial3D
		if cached != null:
			return cached
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(Me.GLOW_BOOST, Me.GLOW_BOOST, Me.GLOW_BOOST)
		ResCache.put("mk_glowmat_v1", m)
		return m

	static func additive_material() -> StandardMaterial3D:
		var cached := ResCache.fetch("mk_addmat_v1") as StandardMaterial3D
		if cached != null:
			return cached
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.disable_fog = true
		ResCache.put("mk_addmat_v1", m)
		return m


class Surf:
	## One surface's arrays while building.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func arrays(with_uv: bool) -> Array:
		var a: Array = []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = cols
		if with_uv:
			a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_INDEX] = idx
		return a


class Builder:
	## Collects coloured primitives and bakes them into one ArrayMesh with build().
	## Every add method takes (shape sizes..., xf, color, [segments], [emissive]).

	var lit: Surf = Surf.new()
	var glow: Surf = Surf.new()
	## Value written to UV.x of the following parts (for custom shaders; 0 = none).
	var flag := 0.0
	var _has_flags := false

	## Number of vertices so far (both surfaces).
	func vertex_count() -> int:
		return lit.verts.size() + glow.verts.size()

	## Number of triangles so far (both surfaces).
	func triangle_count() -> int:
		return (lit.idx.size() + glow.idx.size()) / 3

	## True when nothing was added yet.
	func is_empty() -> bool:
		return vertex_count() == 0

	## Bake into an ArrayMesh: surface "lit" (vertex_material) and, if any part glowed, surface "glow"
	## (glow_material). Pass materials to override them (e.g. a transparent one for ghosts).
	func build(lit_material: Material = null, glow_material: Material = null) -> ArrayMesh:
		var m := ArrayMesh.new()
		if not lit.verts.is_empty():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lit.arrays(_has_flags))
			var s := m.get_surface_count() - 1
			m.surface_set_name(s, "lit")
			m.surface_set_material(s, lit_material if lit_material != null else Lib.vertex_material(false, false))
		if not glow.verts.is_empty():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glow.arrays(_has_flags))
			var s2 := m.get_surface_count() - 1
			m.surface_set_name(s2, "glow")
			m.surface_set_material(s2, glow_material if glow_material != null else Lib.glow_material())
		return m

	# --- Primitives ----------------------------------------------------------------------------

	## Box of `size`, flat-shaded.
	func box(size: Vector3, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE, emissive: bool = false) -> void:
		var h := size * 0.5
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
		for nrm in axes:
			var u := Vector3(nrm.y, nrm.z, nrm.x)  # a perpendicular axis
			var w := nrm.cross(u)
			var c := nrm * h
			var su := u * absf(u.dot(h))
			var sw := w * absf(w.dot(h))
			var base := v.size()
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var cc: Vector2 = corner
				v.append(c + su * cc.x + sw * cc.y)
				n.append(nrm)
			t.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		_emit(v, n, t, xf, color, emissive)

	## Box with rounded edges and corners (radius clamped to half the smallest side). segs: steps per
	## rounded edge (1-4). Smooth, toy-like; ~6 * (2*segs+2)^2 vertices.
	func rounded_box(size: Vector3, radius: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = 2, emissive: bool = false) -> void:
		var hh := size * 0.5
		var r := minf(radius, minf(hh.x, minf(hh.y, hh.z)))
		if r <= 0.0005:
			box(size, xf, color, emissive)
			return
		segs = clampi(segs, 1, 6)
		var inner := hh - Vector3(r, r, r)
		var coords: Array[PackedFloat32Array] = []
		for ax in 3:
			var e: float = inner[ax]
			var list := PackedFloat32Array()
			for j in segs + 1:
				list.append(-e - r * tan(PI * 0.25 * (1.0 - float(j) / segs)))
			for j in segs + 1:
				list.append(e + r * tan(PI * 0.25 * float(j) / segs))
			coords.append(list)
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		for ax in 3:
			for sgn in [-1.0, 1.0]:
				var s: float = sgn
				var au := (ax + 1) % 3
				var av := (ax + 2) % 3
				var cu: PackedFloat32Array = coords[au]
				var cv: PackedFloat32Array = coords[av]
				var base := v.size()
				for j in cv.size():
					for i in cu.size():
						var q := Vector3.ZERO
						q[ax] = s * (inner[ax] + r)
						q[au] = cu[i]
						q[av] = cv[j]
						var cl := q.clamp(-inner, inner)
						var d := q - cl
						var nrm := d.normalized() if d.length_squared() > 1e-12 else Vector3.ZERO
						if nrm == Vector3.ZERO:
							nrm[ax] = s
						v.append(cl + nrm * r)
						n.append(nrm)
				var row := cu.size()
				for j in cv.size() - 1:
					for i in row - 1:
						var a := base + j * row + i
						t.append_array(PackedInt32Array([a, a + 1, a + row + 1, a, a + row + 1, a + row]))
		_emit(v, n, t, xf, color, emissive)

	## Sphere of `radius` (scale the transform for an ellipsoid).
	func sphere(radius: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = Me.SEGMENTS, emissive: bool = false) -> void:
		_lathe_sphere(radius, 0.0, PI, xf, color, segs, emissive, false)

	## Ellipsoid with the given radii.
	func ellipsoid(radii: Vector3, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = Me.SEGMENTS, emissive: bool = false) -> void:
		_lathe_sphere(1.0, 0.0, PI, xf * Transform3D(Basis.from_scale(radii), Vector3.ZERO), color, segs, emissive, false)

	## Upper half of a sphere, its flat base on y = 0 (cap: close the base).
	func dome(radius: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = Me.SEGMENTS, emissive: bool = false, cap: bool = true) -> void:
		_lathe_sphere(radius, 0.0, PI * 0.5, xf, color, segs, emissive, cap)

	## Cylinder from y = -height/2 to +height/2 with (possibly different) top/bottom radii.
	func cylinder(r_top: float, r_bottom: float, height: float, xf: Transform3D = Transform3D.IDENTITY,
			color: Color = Color.WHITE, segs: int = Me.SEGMENTS, emissive: bool = false, caps: bool = true) -> void:
		segs = maxi(3, segs)
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		var hy := height * 0.5
		var slope := (r_bottom - r_top) / maxf(height, 0.0001)
		for i in segs + 1:
			var a := TAU * float(i) / segs
			var cs := Vector2(cos(a), sin(a))
			var nrm := Vector3(cs.x, slope, cs.y).normalized()
			v.append(Vector3(cs.x * r_top, hy, cs.y * r_top))
			n.append(nrm)
			v.append(Vector3(cs.x * r_bottom, -hy, cs.y * r_bottom))
			n.append(nrm)
		for i in segs:
			var a0 := i * 2
			t.append_array(PackedInt32Array([a0, a0 + 2, a0 + 3, a0, a0 + 3, a0 + 1]))
		if caps:
			for side in [1.0, -1.0]:
				var sd: float = side
				var r := r_top if sd > 0.0 else r_bottom
				if r <= 0.0001:
					continue
				var c := v.size()
				v.append(Vector3(0.0, hy * sd, 0.0))
				n.append(Vector3(0.0, sd, 0.0))
				for i in segs + 1:
					var a := TAU * float(i) / segs
					v.append(Vector3(cos(a) * r, hy * sd, sin(a) * r))
					n.append(Vector3(0.0, sd, 0.0))
				for i in segs:
					t.append_array(PackedInt32Array([c, c + 1 + i, c + 2 + i]))
		_emit(v, n, t, xf, color, emissive)

	## Cone: base radius at y = -height/2, tip at +height/2.
	func cone(radius: float, height: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = Me.SEGMENTS, emissive: bool = false) -> void:
		cylinder(0.0, radius, height, xf, color, segs, emissive, true)

	## Capsule of total `height` (including the round ends), like Godot's CapsuleMesh.
	func capsule(radius: float, height: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = Me.SEGMENTS, emissive: bool = false) -> void:
		segs = maxi(4, segs)
		var half_rings := maxi(2, segs / 4)
		var c := maxf(0.0, height * 0.5 - radius)
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		var rows := 0
		for hemi in 2:
			for j in half_rings + 1:
				var phi := PI * 0.5 * float(j) / half_rings + PI * 0.5 * hemi
				var y_off := c if hemi == 0 else -c
				for i in segs + 1:
					var th := TAU * float(i) / segs
					var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
					v.append(d * radius + Vector3(0.0, y_off, 0.0))
					n.append(d)
				rows += 1
		var row := segs + 1
		for j in rows - 1:
			for i in segs:
				var a := j * row + i
				t.append_array(PackedInt32Array([a, a + 1, a + row + 1, a, a + row + 1, a + row]))
		_emit(v, n, t, xf, color, emissive)

	## Torus lying in the XZ plane (hole along Y): ring_radius to the tube centre, tube_radius thick.
	func torus(ring_radius: float, tube_radius: float, xf: Transform3D = Transform3D.IDENTITY,
			color: Color = Color.WHITE, segs: int = 16, tube_segs: int = 8, emissive: bool = false) -> void:
		segs = maxi(3, segs)
		tube_segs = maxi(3, tube_segs)
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		for i in segs + 1:
			var th := TAU * float(i) / segs
			for j in tube_segs + 1:
				var ph := TAU * float(j) / tube_segs
				var d := Vector3(cos(th) * cos(ph), sin(ph), sin(th) * cos(ph))
				v.append(Vector3(cos(th), 0.0, sin(th)) * ring_radius + d * tube_radius)
				n.append(d)
		var row := tube_segs + 1
		for i in segs:
			for j in tube_segs:
				var a := i * row + j
				t.append_array(PackedInt32Array([a, a + 1, a + row + 1, a, a + row + 1, a + row]))
		_emit(v, n, t, xf, color, emissive)

	## Wedge / ramp filling `size`: full-height back face at -Z sloping down to the front edge at +Z.
	func wedge(size: Vector3, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE, emissive: bool = false) -> void:
		var h := size * 0.5
		var bl := Vector3(-h.x, -h.y, -h.z)
		var br := Vector3(h.x, -h.y, -h.z)
		var fl := Vector3(-h.x, -h.y, h.z)
		var fr := Vector3(h.x, -h.y, h.z)
		var tl := Vector3(-h.x, h.y, -h.z)
		var tr := Vector3(h.x, h.y, -h.z)
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		var slope_n := Vector3(0.0, size.z, size.y).normalized()
		var quads: Array = [[bl, br, fr, fl, Vector3.DOWN], [bl, tl, tr, br, Vector3.FORWARD], [fl, fr, tr, tl, slope_n]]
		for q in quads:
			var qa: Array = q
			var base := v.size()
			for k in 4:
				var p: Vector3 = qa[k]
				v.append(p)
				var nq: Vector3 = qa[4]
				n.append(nq)
			t.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		for tri in [[bl, fl, tl, Vector3.LEFT], [br, fr, tr, Vector3.RIGHT]]:
			var ta: Array = tri
			var base := v.size()
			for k in 3:
				var p: Vector3 = ta[k]
				v.append(p)
				var nt: Vector3 = ta[3]
				n.append(nt)
			t.append_array(PackedInt32Array([base, base + 1, base + 2]))
		_emit(v, n, t, xf, color, emissive)

	## Flat-shaded n-sided prism (sides >= 3) standing on Y, centred; first corner on +X.
	func prism(sides: int, radius: float, height: float, xf: Transform3D = Transform3D.IDENTITY,
			color: Color = Color.WHITE, emissive: bool = false) -> void:
		sides = maxi(3, sides)
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		var hy := height * 0.5
		for i in sides:
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var am := (a0 + a1) * 0.5
			var nrm := Vector3(cos(am), 0.0, sin(am))
			var p0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
			var p1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
			var base := v.size()
			v.append_array(PackedVector3Array([p0 + Vector3.UP * hy, p1 + Vector3.UP * hy, p1 - Vector3.UP * hy, p0 - Vector3.UP * hy]))
			n.append_array(PackedVector3Array([nrm, nrm, nrm, nrm]))
			t.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		for sd in [1.0, -1.0]:
			var s: float = sd
			var c := v.size()
			v.append(Vector3(0.0, hy * s, 0.0))
			n.append(Vector3(0.0, s, 0.0))
			for i in sides + 1:
				var a := TAU * float(i) / sides
				v.append(Vector3(cos(a) * radius, hy * s, sin(a) * radius))
				n.append(Vector3(0.0, s, 0.0))
			for i in sides:
				t.append_array(PackedInt32Array([c, c + 1 + i, c + 2 + i]))
		_emit(v, n, t, xf, color, emissive)

	## Flat disc in the XZ plane facing +Y (double_sided: also visible from below).
	func disc(radius: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = Me.SEGMENTS, emissive: bool = false, double_sided: bool = false) -> void:
		var pts := PackedVector2Array()
		for i in maxi(3, segs):
			var a := TAU * float(i) / maxi(3, segs)
			pts.append(Vector2(cos(a), sin(a)) * radius)
		_flat_polygon(pts, Basis(Vector3.RIGHT, -PI * 0.5), xf, color, emissive, double_sided)

	## Flat rounded rectangle in the XY plane facing +Z (signs, cards, screens, UI panels in 3D).
	func panel(size: Vector2, radius: float, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE,
			segs: int = 4, emissive: bool = false, double_sided: bool = false) -> void:
		var h := size * 0.5
		var r := clampf(radius, 0.0, minf(h.x, h.y))
		var pts := PackedVector2Array()
		var corners: Array[Vector2] = [Vector2(h.x - r, h.y - r), Vector2(-h.x + r, h.y - r), Vector2(-h.x + r, -h.y + r), Vector2(h.x - r, -h.y + r)]
		for k in 4:
			for i in segs + 1:
				var a := PI * 0.5 * (k + float(i) / segs)
				pts.append(corners[k] + Vector2(cos(a), sin(a)) * r)
				if r <= 0.0:
					break
		_flat_polygon(pts, Basis(), xf, color, emissive, double_sided)

	## Five-or-more pointed star in the XY plane facing +Z, extruded `depth` along Z.
	func star(points: int, outer: float, inner: float, depth: float, xf: Transform3D = Transform3D.IDENTITY,
			color: Color = Color.WHITE, emissive: bool = false) -> void:
		points = maxi(3, points)
		var outline := PackedVector2Array()
		for i in points * 2:
			var a := PI * 0.5 + PI * float(i) / points
			var r := outer if i % 2 == 0 else inner
			outline.append(Vector2(cos(a), sin(a)) * r)
		_extrude(outline, depth, xf, color, emissive)

	## Any flat outline (XY, star-shaped around its centroid: wings, fins, signs, leaves) extruded
	## `depth` along Z and centred on it, so it is visible from both sides.
	func polygon(outline: PackedVector2Array, depth: float, xf: Transform3D = Transform3D.IDENTITY,
			color: Color = Color.WHITE, emissive: bool = false) -> void:
		if outline.size() < 3:
			return
		var c0 := Vector2.ZERO
		for p in outline:
			c0 += p
		c0 /= float(outline.size())
		var shifted := PackedVector2Array()
		for p in outline:
			shifted.append(p - c0)
		_extrude(shifted, maxf(depth, 0.0005), xf * Transform3D(Basis(), Vector3(c0.x, c0.y, 0.0)), color, emissive)

	## Cylinder/cone spanning two points (r_a at `a`, r_b at `b`): limbs, branches, beams, bones.
	func tube(a: Vector3, b: Vector3, r_a: float, r_b: float, color: Color = Color.WHITE, segs: int = 8,
			emissive: bool = false, caps: bool = true) -> void:
		var d := b - a
		if d.length() < 0.00001:
			return
		cylinder(r_b, r_a, d.length(), Transform3D(Lib.basis_y_to(d), (a + b) * 0.5), color, segs, emissive, caps)

	## Capsule spanning two points (centres of the round ends) with `radius`.
	func capsule_between(a: Vector3, b: Vector3, radius: float, color: Color = Color.WHITE, segs: int = 10,
			emissive: bool = false) -> void:
		var d := b - a
		capsule(radius, d.length() + radius * 2.0, Transform3D(Lib.basis_y_to(d if d.length() > 0.00001 else Vector3.UP), (a + b) * 0.5),
			color, segs, emissive)

	## Add every surface of an existing Mesh (PrimitiveMesh, ArrayMesh, another kit mesh...) tinted by
	## `color` (multiplied with its own vertex colours if it has any). Kit meshes keep their glow surface.
	func add_mesh(mesh: Mesh, xf: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE, emissive: bool = false) -> void:
		if mesh == null:
			return
		for s in mesh.get_surface_count():
			var am := mesh as ArrayMesh
			if am != null and am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mesh.surface_get_arrays(s)
			var glow_surface := emissive
			if am != null and am.surface_get_name(s) == "glow":
				glow_surface = true
			_emit_raw(arr, xf, color, glow_surface)

	# --- Internals -----------------------------------------------------------------------------

	func _lathe_sphere(radius: float, phi0: float, phi1: float, xf: Transform3D, color: Color, segs: int,
			emissive: bool, cap: bool) -> void:
		segs = maxi(4, segs)
		var rings := maxi(2, int(round(float(segs) * (phi1 - phi0) / TAU)))
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		for j in rings + 1:
			var phi := lerpf(phi0, phi1, float(j) / rings)
			for i in segs + 1:
				var th := TAU * float(i) / segs
				var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				v.append(d * radius)
				n.append(d)
		var row := segs + 1
		for j in rings:
			for i in segs:
				var a := j * row + i
				t.append_array(PackedInt32Array([a, a + 1, a + row + 1, a, a + row + 1, a + row]))
		if cap:
			var c := v.size()
			v.append(Vector3.ZERO)
			n.append(Vector3.DOWN)
			var y := cos(phi1) * radius
			var rr := sin(phi1) * radius
			for i in segs + 1:
				var th := TAU * float(i) / segs
				v.append(Vector3(cos(th) * rr, y, sin(th) * rr))
				n.append(Vector3.DOWN)
			for i in segs:
				t.append_array(PackedInt32Array([c, c + 1 + i, c + 2 + i]))
		_emit(v, n, t, xf, color, emissive)

	## Convex-or-star-shaped polygon (fan from its centroid) in a plane given by `plane` (identity = XY facing +Z).
	func _flat_polygon(pts: PackedVector2Array, plane: Basis, xf: Transform3D, color: Color, emissive: bool,
			double_sided: bool) -> void:
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		var sides: Array = [1.0, -1.0] if double_sided else [1.0]
		for side in sides:
			var sd: float = side
			var c := v.size()
			var nrm := plane * Vector3(0.0, 0.0, sd)
			v.append(Vector3.ZERO)
			n.append(nrm)
			for p in pts:
				v.append(plane * Vector3(p.x, p.y, 0.0))
				n.append(nrm)
			var cnt := pts.size()
			for i in cnt:
				t.append_array(PackedInt32Array([c, c + 1 + i, c + 1 + (i + 1) % cnt]))
		_emit(v, n, t, xf, color, emissive)

	## Extrude a star-shaped outline (XY) along Z by depth: front (+Z), back and flat sides.
	func _extrude(outline: PackedVector2Array, depth: float, xf: Transform3D, color: Color, emissive: bool) -> void:
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var t := PackedInt32Array()
		var hz := depth * 0.5
		var cnt := outline.size()
		for sd in [1.0, -1.0]:
			var s: float = sd
			var c := v.size()
			v.append(Vector3(0.0, 0.0, hz * s))
			n.append(Vector3(0.0, 0.0, s))
			for p in outline:
				v.append(Vector3(p.x, p.y, hz * s))
				n.append(Vector3(0.0, 0.0, s))
			for i in cnt:
				t.append_array(PackedInt32Array([c, c + 1 + i, c + 1 + (i + 1) % cnt]))
		for i in cnt:
			var p0 := outline[i]
			var p1 := outline[(i + 1) % cnt]
			var e := p1 - p0
			var nrm := Vector3(e.y, -e.x, 0.0).normalized()
			if nrm.dot(Vector3((p0 + p1).x, (p0 + p1).y, 0.0)) < 0.0:
				nrm = -nrm
			var base := v.size()
			v.append_array(PackedVector3Array([Vector3(p0.x, p0.y, hz), Vector3(p1.x, p1.y, hz), Vector3(p1.x, p1.y, -hz), Vector3(p0.x, p0.y, -hz)]))
			n.append_array(PackedVector3Array([nrm, nrm, nrm, nrm]))
			t.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		_emit(v, n, t, xf, color, emissive)

	## Append local geometry. Triangles may come in either order: each one is turned so its front
	## (Godot: clockwise seen from the front) faces the way its vertex normals point. Zero-area
	## triangles (sphere poles, cone tips) are dropped.
	func _emit(lv: PackedVector3Array, ln: PackedVector3Array, tris: PackedInt32Array, xf: Transform3D,
			color: Color, emissive: bool) -> void:
		var det := xf.basis.determinant()
		if absf(det) < 1e-12:
			return
		var s: Surf = glow if emissive else lit
		var base := s.verts.size()
		var nb := xf.basis.inverse().transposed()
		var uv := Vector2(flag, 0.0)
		if flag != 0.0:
			_has_flags = true
		for k in lv.size():
			s.verts.append(xf * lv[k])
			var nn := nb * ln[k]
			s.norms.append(nn.normalized() if nn.length_squared() > 1e-16 else Vector3.UP)
			s.cols.append(color)
			s.uvs.append(uv)
		var mirrored := det < 0.0
		for i in range(0, tris.size(), 3):
			var ia := tris[i]
			var ib := tris[i + 1]
			var ic := tris[i + 2]
			var a := lv[ia]
			var b := lv[ib]
			var c := lv[ic]
			var g := (c - a).cross(b - a)  # Godot front-face normal for order (a, b, c)
			if g.length_squared() < 1e-20:
				continue
			var want := ln[ia] + ln[ib] + ln[ic]
			var flip := g.dot(want) < 0.0
			if mirrored:
				flip = not flip
			if flip:
				s.idx.append_array(PackedInt32Array([base + ia, base + ic, base + ib]))
			else:
				s.idx.append_array(PackedInt32Array([base + ia, base + ib, base + ic]))

	## Append a mesh surface's arrays as they are (winding kept; mirrored transforms flip it).
	func _emit_raw(arr: Array, xf: Transform3D, color: Color, emissive: bool) -> void:
		var det := xf.basis.determinant()
		if absf(det) < 1e-12:
			return
		var s: Surf = glow if emissive else lit
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n := PackedVector3Array()
		if arr[Mesh.ARRAY_NORMAL] != null:
			n = arr[Mesh.ARRAY_NORMAL]
		var cin := PackedColorArray()
		if arr[Mesh.ARRAY_COLOR] != null:
			cin = arr[Mesh.ARRAY_COLOR]
		var ii := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			ii = arr[Mesh.ARRAY_INDEX]
		var base := s.verts.size()
		var nb := xf.basis.inverse().transposed()
		var uv := Vector2(flag, 0.0)
		if flag != 0.0:
			_has_flags = true
		for k in v.size():
			s.verts.append(xf * v[k])
			var nn := nb * n[k] if k < n.size() else Vector3.UP
			s.norms.append(nn.normalized() if nn.length_squared() > 1e-16 else Vector3.UP)
			s.cols.append(cin[k] * color if k < cin.size() else color)
			s.uvs.append(uv)
		if ii.is_empty():
			ii.resize(v.size())
			for k in v.size():
				ii[k] = k
		var mirrored := det < 0.0
		for i in range(0, ii.size() - 2, 3):
			if mirrored:
				s.idx.append_array(PackedInt32Array([base + ii[i], base + ii[i + 2], base + ii[i + 1]]))
			else:
				s.idx.append_array(PackedInt32Array([base + ii[i], base + ii[i + 1], base + ii[i + 2]]))


# =================================================================================================

class Props:
	## Builders for the ready-made props (use MeshKit.prop(name), which caches them).

	static func build(prop_name: String, variant: int) -> ArrayMesh:
		var b := Builder.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(prop_name) + variant * 7919
		var wood := Color(0.55, 0.36, 0.22)
		var leaf_cols: Array[Color] = [Color(0.36, 0.7, 0.32), Color(0.45, 0.75, 0.3), Color(0.3, 0.6, 0.38), Color(0.62, 0.72, 0.28)]
		var leaf: Color = leaf_cols[variant % leaf_cols.size()]
		match prop_name:
			"tree":
				b.cylinder(0.11, 0.17, 1.3, Me.at(Vector3(0, 0.65, 0)), wood, 8)
				b.tube(Vector3(0, 0.9, 0), Vector3(0.35, 1.35, 0.05), 0.06, 0.04, wood, 6)
				var blobs: Array[Vector4] = [Vector4(0, 1.95, 0, 0.75), Vector4(0.45, 1.65, 0.15, 0.5), Vector4(-0.42, 1.7, -0.1, 0.52),
					Vector4(0.05, 1.7, 0.42, 0.48), Vector4(-0.1, 2.45, -0.05, 0.45)]
				for k in blobs.size():
					var bl := blobs[k]
					b.sphere(bl.w, Me.at(Vector3(bl.x, bl.y, bl.z)), leaf.lightened(0.06 * k) if k % 2 == 0 else leaf.darkened(0.06), 10)
			"pine":
				b.cylinder(0.1, 0.14, 0.8, Me.at(Vector3(0, 0.4, 0)), wood.darkened(0.15), 7)
				var dark := leaf.darkened(0.25).lerp(Color(0.15, 0.45, 0.35), 0.4)
				for k in 4:
					var r := 0.95 - k * 0.2
					b.cone(r, 0.95, Me.at(Vector3(0, 0.95 + k * 0.52, 0)), dark.lightened(0.05 * k), 9)
			"palm":
				var trunk := Color(0.62, 0.48, 0.32)
				var prev := Vector3.ZERO
				for k in 6:
					var p := Vector3(0.05 * k * k * 0.25, 0.42 * (k + 1), 0)
					b.tube(prev, p, 0.12 - k * 0.008, 0.11 - k * 0.008, trunk.lightened(0.06 * (k % 2)), 7)
					prev = p
				for k in 6:
					var a := TAU * k / 6.0
					var dir := Vector3(cos(a), -0.25, sin(a))
					b.ellipsoid(Vector3(0.75, 0.05, 0.2), Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -0.3), prev + dir * 0.6), leaf, 8)
				b.sphere(0.1, Me.at(prev + Vector3(0.1, -0.12, 0.05)), Color(0.45, 0.3, 0.18), 8)
				b.sphere(0.1, Me.at(prev + Vector3(-0.06, -0.14, -0.09)), Color(0.45, 0.3, 0.18), 8)
			"bush":
				for k in 5:
					var a := TAU * k / 5.0 + rng.randf() * 0.4
					var r := 0.3 + rng.randf() * 0.15
					b.sphere(r, Me.at(Vector3(cos(a) * 0.3, r * 0.8, sin(a) * 0.3)), leaf.lightened(rng.randf() * 0.12), 10)
				b.sphere(0.4, Me.at(Vector3(0, 0.45, 0)), leaf, 10)
			"rock":
				var grey := Color(0.56, 0.56, 0.6).lerp(Color(0.6, 0.52, 0.45), float(variant % 3) * 0.4)
				b.rounded_box(Vector3(0.9, 0.55, 0.75), 0.2, Me.at(Vector3(0, 0.22, 0), Vector3.ONE, Vector3(0.1, 0.4, 0.06)), grey, 1)
				b.sphere(0.32, Me.at(Vector3(0.32, 0.18, 0.2), Vector3(1, 0.7, 1)), grey.darkened(0.08), 7)
				b.sphere(0.25, Me.at(Vector3(-0.3, 0.42, -0.1), Vector3(1.1, 0.8, 1)), grey.lightened(0.06), 7)
			"grass":
				for k in 7:
					var a := TAU * k / 7.0 + rng.randf() * 0.5
					var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.02, 0.1)
					var tip := off * 3.0 + Vector3(0, rng.randf_range(0.25, 0.42), 0)
					b.tube(off, tip, 0.03, 0.002, leaf.lightened(rng.randf() * 0.15), 3, false, false)
			"flower":
				var petal_cols: Array[Color] = [Color(1.0, 0.55, 0.65), Color(1.0, 0.85, 0.3), Color(0.7, 0.6, 1.0), Color(1.0, 1.0, 1.0), Color(1.0, 0.5, 0.3)]
				var pc: Color = petal_cols[variant % petal_cols.size()]
				b.tube(Vector3.ZERO, Vector3(0, 0.32, 0), 0.015, 0.012, Color(0.35, 0.65, 0.3), 5)
				b.ellipsoid(Vector3(0.07, 0.015, 0.03), Me.at(Vector3(0.05, 0.12, 0), Vector3.ONE, Vector3(0, 0, 0.4)), Color(0.35, 0.65, 0.3), 6)
				for k in 5:
					var a := TAU * k / 5.0
					b.ellipsoid(Vector3(0.055, 0.02, 0.035), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 0.05, 0.33, sin(a) * 0.05)), pc, 8)
				b.sphere(0.03, Me.at(Vector3(0, 0.345, 0)), Color(1.0, 0.8, 0.25), 8)
			"mushroom":
				b.cylinder(0.07, 0.09, 0.22, Me.at(Vector3(0, 0.11, 0)), Color(0.96, 0.92, 0.82), 10)
				var cap := Color(0.9, 0.25, 0.22) if variant % 2 == 0 else Color(0.75, 0.5, 0.95)
				b.dome(0.2, Me.at(Vector3(0, 0.2, 0), Vector3(1, 0.75, 1)), cap, 12)
				for k in 5:
					var a := TAU * k / 5.0 + 0.3
					b.sphere(0.03, Me.at(Vector3(cos(a) * 0.12, 0.3, sin(a) * 0.12), Vector3(1, 0.5, 1)), Color(1, 1, 0.95), 6)
				b.sphere(0.035, Me.at(Vector3(0, 0.355, 0), Vector3(1, 0.5, 1)), Color(1, 1, 0.95), 6)
			"crate":
				var c := wood.lightened(0.1)
				b.box(Vector3(0.76, 0.76, 0.76), Me.at(Vector3(0, 0.4, 0)), c)
				var fr := c.darkened(0.3)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var px: float = sx
						var pz: float = sz
						b.box(Vector3(0.1, 0.8, 0.1), Me.at(Vector3(px * 0.36, 0.4, pz * 0.36)), fr)
				for sy in [0.04, 0.76]:
					var py: float = sy
					b.box(Vector3(0.8, 0.08, 0.1), Me.at(Vector3(0, py, 0.36)), fr)
					b.box(Vector3(0.8, 0.08, 0.1), Me.at(Vector3(0, py, -0.36)), fr)
					b.box(Vector3(0.1, 0.08, 0.8), Me.at(Vector3(0.36, py, 0)), fr)
					b.box(Vector3(0.1, 0.08, 0.8), Me.at(Vector3(-0.36, py, 0)), fr)
				b.box(Vector3(0.08, 0.7, 0.78), Me.at(Vector3(0, 0.4, 0), Vector3.ONE, Vector3(0, 0, 0.78)), fr.lightened(0.1))
			"barrel":
				var staves := Color(0.6, 0.4, 0.24)
				b.cylinder(0.34, 0.28, 0.45, Me.at(Vector3(0, 0.225, 0)), staves, 14, false, false)
				b.cylinder(0.28, 0.34, 0.45, Me.at(Vector3(0, 0.675, 0)), staves, 14, false, false)
				b.disc(0.28, Me.at(Vector3(0, 0.9, 0)), staves.darkened(0.15), 14)
				b.disc(0.28, Me.at(Vector3(0, 0.0, 0), Vector3.ONE, Vector3(PI, 0, 0)), staves.darkened(0.2), 14)
				for y in [0.1, 0.45, 0.8]:
					var py: float = y
					var rr := lerpf(0.29, 0.345, 1.0 - absf(py - 0.45) / 0.45)
					b.torus(rr, 0.022, Me.at(Vector3(0, py, 0)), Color(0.35, 0.35, 0.4), 14, 4)
			"chest":
				var gold := Color(1.0, 0.8, 0.3)
				b.rounded_box(Vector3(0.8, 0.42, 0.52), 0.04, Me.at(Vector3(0, 0.21, 0)), wood, 1)
				b.cylinder(0.26, 0.26, 0.8, Me.at(Vector3(0, 0.42, 0), Vector3(0.7, 1, 1), Vector3(0, 0, PI * 0.5)), wood.lightened(0.08), 12)
				for x in [-0.28, 0.28]:
					var px: float = x
					b.box(Vector3(0.07, 0.44, 0.54), Me.at(Vector3(px, 0.22, 0)), gold)
					b.torus(0.26, 0.03, Me.at(Vector3(px, 0.42, 0), Vector3(0.7, 1, 1), Vector3(0, 0, PI * 0.5)), gold, 12, 4)
				b.box(Vector3(0.14, 0.16, 0.05), Me.at(Vector3(0, 0.4, 0.27)), gold)
				b.sphere(0.025, Me.at(Vector3(0, 0.37, 0.3)), Color(0.2, 0.15, 0.1), 6)
			"lamp_post":
				var iron := Color(0.22, 0.24, 0.3)
				b.cylinder(0.12, 0.16, 0.2, Me.at(Vector3(0, 0.1, 0)), iron, 10)
				b.cylinder(0.045, 0.06, 2.4, Me.at(Vector3(0, 1.3, 0)), iron, 8)
				b.cylinder(0.2, 0.12, 0.1, Me.at(Vector3(0, 2.5, 0)), iron, 8)
				b.sphere(0.17, Me.at(Vector3(0, 2.68, 0)), Color(1.0, 0.88, 0.55), 10, true)
				b.cone(0.24, 0.18, Me.at(Vector3(0, 2.9, 0)), iron, 8)
			"torch":
				b.cylinder(0.04, 0.03, 0.55, Me.at(Vector3(0, 0.275, 0)), wood.darkened(0.2), 6)
				b.cylinder(0.065, 0.05, 0.1, Me.at(Vector3(0, 0.56, 0)), Color(0.3, 0.3, 0.32), 8)
				b.sphere(0.08, Me.at(Vector3(0, 0.66, 0), Vector3(1, 1.2, 1)), Color(1.0, 0.55, 0.15), 8, true)
				b.cone(0.06, 0.18, Me.at(Vector3(0, 0.78, 0)), Color(1.0, 0.85, 0.3), 8, true)
			"fence":
				var paint := Color(0.92, 0.88, 0.8) if variant % 2 == 0 else wood
				for x in [-0.9, 0.9]:
					var px: float = x
					b.box(Vector3(0.12, 0.9, 0.12), Me.at(Vector3(px, 0.45, 0)), paint)
					b.wedge(Vector3(0.12, 0.08, 0.12), Me.at(Vector3(px, 0.94, 0), Vector3.ONE, Vector3(0, PI * 0.5, 0)), paint)
				for y in [0.35, 0.7]:
					var py: float = y
					b.box(Vector3(1.9, 0.1, 0.05), Me.at(Vector3(0, py, 0.07)), paint.darkened(0.08))
			"sign":
				b.box(Vector3(0.08, 1.1, 0.08), Me.at(Vector3(0, 0.55, 0)), wood.darkened(0.15))
				b.rounded_box(Vector3(0.8, 0.45, 0.06), 0.04, Me.at(Vector3(0, 1.05, 0.05)), wood.lightened(0.2), 1)
			"cloud":
				var white := Color(1, 1, 1)
				for k in 6:
					var a := TAU * k / 6.0 + rng.randf() * 0.5
					var r := rng.randf_range(0.6, 0.95)
					b.sphere(r, Me.at(Vector3(cos(a) * 1.1, r * 0.35, sin(a) * 0.55), Vector3(1, 0.75, 1)), white.darkened(rng.randf() * 0.06), 10)
				b.sphere(1.2, Me.at(Vector3(0, 0.55, 0), Vector3(1.1, 0.8, 0.9)), white, 12)
			"coin":
				var gold := Color(1.0, 0.8, 0.25)
				var stand := Basis(Vector3.RIGHT, PI * 0.5)
				b.cylinder(0.2, 0.2, 0.05, Transform3D(stand, Vector3(0, 0.22, 0)), gold, 16)
				b.torus(0.15, 0.018, Transform3D(stand, Vector3(0, 0.22, 0.026)), gold.lightened(0.2), 16, 4)
				b.torus(0.15, 0.018, Transform3D(stand, Vector3(0, 0.22, -0.026)), gold.lightened(0.2), 16, 4)
			"gem":
				var gem_cols: Array[Color] = [Color(0.3, 0.85, 1.0), Color(1.0, 0.35, 0.45), Color(0.45, 1.0, 0.5), Color(0.75, 0.45, 1.0)]
				var gc: Color = gem_cols[variant % gem_cols.size()]
				b.cylinder(0.0, 0.16, 0.18, Me.at(Vector3(0, 0.36, 0)), gc.lightened(0.15), 6)
				b.cylinder(0.16, 0.0, 0.26, Me.at(Vector3(0, 0.14, 0)), gc, 6)
			"heart":
				var red := Color(1.0, 0.3, 0.4)
				b.sphere(0.13, Me.at(Vector3(-0.1, 0.33, 0), Vector3(1, 1, 0.7)), red, 12)
				b.sphere(0.13, Me.at(Vector3(0.1, 0.33, 0), Vector3(1, 1, 0.7)), red, 12)
				b.cone(0.215, 0.27, Me.at(Vector3(0, 0.16, 0), Vector3(1.08, 1, 0.6), Vector3(PI, 0, 0)), red, 12)
				b.sphere(0.035, Me.at(Vector3(-0.12, 0.38, 0.08)), Color(1, 0.85, 0.9), 6)
			"star":
				b.star(5, 0.3, 0.13, 0.1, Me.at(Vector3(0, 0.3, 0)), Color(1.0, 0.85, 0.25))
			"table":
				b.rounded_box(Vector3(1.4, 0.08, 0.8), 0.03, Me.at(Vector3(0, 0.74, 0)), wood.lightened(0.12), 1)
				for sx in [-0.6, 0.6]:
					for sz in [-0.32, 0.32]:
						var px: float = sx
						var pz: float = sz
						b.cylinder(0.035, 0.03, 0.72, Me.at(Vector3(px, 0.36, pz)), wood, 6)
			"chair":
				b.rounded_box(Vector3(0.45, 0.06, 0.45), 0.02, Me.at(Vector3(0, 0.45, 0)), wood.lightened(0.12), 1)
				for sx in [-0.19, 0.19]:
					for sz in [-0.19, 0.19]:
						var px: float = sx
						var pz: float = sz
						b.cylinder(0.025, 0.022, 0.44, Me.at(Vector3(px, 0.22, pz)), wood, 6)
				b.rounded_box(Vector3(0.45, 0.42, 0.05), 0.02, Me.at(Vector3(0, 0.7, -0.2)), wood.lightened(0.05), 1)
			"bookshelf":
				var shelf := wood.darkened(0.1)
				b.box(Vector3(1.0, 1.8, 0.05), Me.at(Vector3(0, 0.9, -0.17)), shelf.darkened(0.15))
				for x in [-0.48, 0.48]:
					var px: float = x
					b.box(Vector3(0.04, 1.8, 0.38), Me.at(Vector3(px, 0.9, 0)), shelf)
				for k in 5:
					b.box(Vector3(1.0, 0.04, 0.38), Me.at(Vector3(0, 0.02 + k * 0.44, 0)), shelf)
				var book_cols: Array[Color] = [Color(0.8, 0.25, 0.25), Color(0.25, 0.45, 0.8), Color(0.3, 0.65, 0.35), Color(0.9, 0.7, 0.25), Color(0.6, 0.35, 0.7)]
				for k in 4:
					var x := -0.44
					while x < 0.4:
						var w := rng.randf_range(0.04, 0.08)
						var hgt := rng.randf_range(0.26, 0.36)
						if rng.randf() < 0.85:
							b.box(Vector3(w, hgt, 0.26), Me.at(Vector3(x + w * 0.5, 0.04 + k * 0.44 + hgt * 0.5, 0.02)), book_cols[rng.randi() % book_cols.size()])
						x += w + 0.008
			"candle":
				b.cylinder(0.05, 0.05, 0.22, Me.at(Vector3(0, 0.11, 0)), Color(0.98, 0.95, 0.85), 8)
				b.cylinder(0.09, 0.1, 0.03, Me.at(Vector3(0, 0.015, 0)), Color(0.8, 0.65, 0.3), 10)
				b.sphere(0.03, Me.at(Vector3(0, 0.26, 0), Vector3(1, 1.6, 1)), Color(1.0, 0.75, 0.3), 6, true)
			"pot":
				var clay := Color(0.8, 0.45, 0.3)
				b.cylinder(0.2, 0.14, 0.3, Me.at(Vector3(0, 0.15, 0)), clay, 12)
				b.torus(0.2, 0.03, Me.at(Vector3(0, 0.3, 0)), clay.lightened(0.1), 12, 4)
				b.disc(0.19, Me.at(Vector3(0, 0.28, 0)), Color(0.35, 0.25, 0.18), 12)
				b.sphere(0.12, Me.at(Vector3(0, 0.38, 0)), leaf, 8)
			_:
				push_warning("MeshKit.prop: unknown prop '%s'" % prop_name)
				b.box(Vector3(0.5, 0.5, 0.5), Me.at(Vector3(0, 0.25, 0)), Color(1, 0, 1))
		return b.build()
