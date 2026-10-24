extends Node3D
## DUNGEON DELVE: floor warnings ("telegraphs") for big attacks, drawn the same on every machine.
## Before a boss slams, breathes fire or a bomb goes off, its danger area glows on the floor and
## flashes faster and faster; then it goes off. Shapes: "circle" (size.x = radius), "ring" (an
## expanding shockwave ring, size.x = final radius), "line" (size.x = length, size.y = width, from pos
## along dir), "sector" (size.x = radius, size.y = half angle in radians, from pos along dir).
## Lava pools stay after going off ("stay" seconds, glowing).
## Few draw calls: a pool of MeshInstance3Ds reusing four unit meshes and two materials.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

var items: Array[Dictionary] = []  ## {"node", "shape", "pos", "dir", "size", "warn", "t", "stay"}
var _pool: Array[MeshInstance3D] = []
var _mat_warn: StandardMaterial3D
var _mat_hot: StandardMaterial3D


func _ready() -> void:
	_mat_warn = StandardMaterial3D.new()
	_mat_warn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_warn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_warn.albedo_color = Color(1.0, 0.35, 0.2, 0.45)
	_mat_warn.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_hot = _mat_warn.duplicate()
	_mat_hot.albedo_color = Color(1.0, 0.55, 0.15, 0.75)


static func _mesh(shape: String) -> Mesh:
	return ResCache.get_or_make("dd_tele_%s_v1" % shape, func() -> Resource:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		match shape:
			"circle":
				for i in 32:
					var a0 := TAU * i / 32.0
					var a1 := TAU * (i + 1) / 32.0
					st.add_vertex(Vector3.ZERO)
					st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)))
					st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)))
			"ring":
				for i in 32:
					var a0 := TAU * i / 32.0
					var a1 := TAU * (i + 1) / 32.0
					var o0 := Vector3(cos(a0), 0.0, sin(a0))
					var o1 := Vector3(cos(a1), 0.0, sin(a1))
					st.add_vertex(o0 * 0.82)
					st.add_vertex(o1)
					st.add_vertex(o0)
					st.add_vertex(o0 * 0.82)
					st.add_vertex(o1 * 0.82)
					st.add_vertex(o1)
			"line":  # from z = 0 forward to z = 1 (+Z), width 1
				st.add_vertex(Vector3(-0.5, 0.0, 0.0))
				st.add_vertex(Vector3(0.5, 0.0, 1.0))
				st.add_vertex(Vector3(0.5, 0.0, 0.0))
				st.add_vertex(Vector3(-0.5, 0.0, 0.0))
				st.add_vertex(Vector3(-0.5, 0.0, 1.0))
				st.add_vertex(Vector3(0.5, 0.0, 1.0))
			"sector":  # a fan of +-1 radian around +Z (scaled in x for other angles)
				for i in 16:
					var a0 := -1.0 + 2.0 * i / 16.0
					var a1 := -1.0 + 2.0 * (i + 1) / 16.0
					st.add_vertex(Vector3.ZERO)
					st.add_vertex(Vector3(sin(a0), 0.0, cos(a0)))
					st.add_vertex(Vector3(sin(a1), 0.0, cos(a1)))
		st.generate_normals()
		return st.commit())


## Show a warning. warn = seconds until it goes off; stay = seconds it keeps glowing after.
func add(shape: String, pos: Vector3, dir: Vector3, size: Vector2, warn: float, stay: float = 0.25) -> void:
	var mi: MeshInstance3D
	if _pool.is_empty():
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		mi = _pool.pop_back()
	mi.mesh = _mesh(shape)
	mi.material_override = _mat_warn
	mi.visible = true
	var yaw := atan2(dir.x, dir.z) if dir.length() > 0.01 else 0.0
	mi.position = Vector3(pos.x, 0.03 + items.size() * 0.002, pos.z)
	mi.rotation = Vector3(0.0, yaw, 0.0)
	match shape:
		"circle", "ring":
			mi.scale = Vector3(size.x, 1.0, size.x)
		"line":
			mi.scale = Vector3(size.y, 1.0, size.x)
		"sector":
			# The unit fan spans +-1 rad; squeeze x for a narrower cone (approximately).
			mi.scale = Vector3(size.x * sin(minf(size.y, 1.5)) / sin(1.0), 1.0, size.x)
	items.append({"node": mi, "shape": shape, "pos": pos, "dir": dir, "size": size, "warn": warn, "t": 0.0, "stay": stay})


func clear() -> void:
	for it in items:
		_release(it["node"])
	items.clear()


func _release(mi: MeshInstance3D) -> void:
	mi.visible = false
	_pool.append(mi)


func animate(delta: float) -> void:
	var i := 0
	while i < items.size():
		var it: Dictionary = items[i]
		it["t"] = float(it["t"]) + delta
		var t: float = it["t"]
		var warn: float = it["warn"]
		var mi: MeshInstance3D = it["node"]
		if t < warn:
			# Flash faster as it gets close.
			var k := t / maxf(warn, 0.01)
			var rate := lerpf(4.0, 16.0, k)
			mi.visible = fmod(t * rate, 1.0) < 0.65 or k < 0.3
			if String(it["shape"]) == "ring":
				var s: Vector2 = it["size"]
				mi.scale = Vector3.ONE * maxf(0.3, s.x * 0.25)
		elif t < warn + float(it["stay"]):
			mi.visible = true
			mi.material_override = _mat_hot
			if String(it["shape"]) == "ring":
				var s2: Vector2 = it["size"]
				var k2 := clampf((t - warn) / maxf(float(it["stay"]), 0.01), 0.0, 1.0)
				mi.scale = Vector3(s2.x * k2, 1.0, s2.x * k2)
		else:
			_release(mi)
			items.remove_at(i)
			continue
		i += 1


## Is point p inside a shape? (host: who gets hit; bots: where not to stand)
static func inside(shape: String, pos: Vector3, dir: Vector3, size: Vector2, p: Vector3, pad: float = 0.0) -> bool:
	var d := Vector2(p.x - pos.x, p.z - pos.z)
	match shape:
		"circle":
			return d.length() <= size.x + pad
		"ring":
			return d.length() <= size.x + pad
		"line":
			var fwd := Vector2(dir.x, dir.z).normalized()
			var along := d.dot(fwd)
			var across := absf(d.dot(Vector2(-fwd.y, fwd.x)))
			return along >= -pad and along <= size.x + pad and across <= size.y * 0.5 + pad
		"sector":
			if d.length() > size.x + pad:
				return false
			if d.length() < 0.3:
				return true
			var fwd2 := Vector2(dir.x, dir.z).normalized()
			return absf(fwd2.angle_to(d.normalized())) <= size.y + 0.1
	return false
