extends RefCounted
## Builds ONE ArrayMesh out of many coloured primitive parts (colours baked into the vertices), so a
## detailed prop or character costs a single draw call. Draw it with vertex_material().
## parts: Array of [Mesh, Transform3D, Color].


static func merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for part in parts:
		var a: Array = part
		var m: Mesh = a[0]
		var xf: Transform3D = a[1]
		var c: Color = a[2]
		var nb := xf.basis.inverse().transposed()
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var base := verts.size()
			for k in v.size():
				verts.append(xf * v[k])
				norms.append((nb * n[k]).normalized() if k < n.size() else Vector3.UP)
				cols.append(c)
			var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if ii.is_empty():
				for k in v.size():
					idx.append(base + k)
			else:
				for k in ii:
					idx.append(base + k)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func sphere(r: float, seg: int = 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(4, seg / 2)
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(top: float, bottom: float, h: float, seg: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func at(pos: Vector3, scale: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale), pos)


## Material that shows the baked vertex colours (lit, or unshaded for things that should glow evenly).
## cache: a per-scene Dictionary (not Engine metadata: materials must not outlive the renderer).
static func vertex_material(cache: Dictionary, unshaded: bool = false) -> StandardMaterial3D:
	var key := "pg_vmat_%s" % unshaded
	if cache.has(key):
		var cached: StandardMaterial3D = cache[key]
		return cached
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.75
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cache[key] = m
	return m
