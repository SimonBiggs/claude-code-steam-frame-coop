extends Node3D
## A NEIGHBOUR FRIEND from PIP'S STREET (street.gd FRIENDS): a little animal made of spheres (bunny, kitten,
## hedgehog, owl, tortoise, frog, squirrel, hamster), sitting like Pip. Hiding in a house (main.gd: found like
## Pip, by the torch, a touch or a hider), or sitting at PIP'S GARDEN PARTY (party = true: a happy bob).
## In a DARK room (set_dark) the body goes dim and only the eyes glow. A SNEAKY friend pops away in a puff
## (main.gd moves them). Same on every machine: main.gd sets everything from the host's snapshot.

const Street := preload("res://games/hide_and_seek/street.gd")

var fid := 0
var body: Node3D
var ears: Array[Node3D] = []
var eye_mats: Array[StandardMaterial3D] = []
var mats: Array[StandardMaterial3D] = []
var t := 0.0
var excite := 0.0
var hop_t := -1.0
var party := false
var dark := false


## Build friend `id` (call once, before or after adding to the tree).
func setup(id: int) -> Node3D:
	fid = id
	name = "Friend%d" % id
	body = Node3D.new()
	add_child(body)
	var f := Street.friend(id)
	var fur: Color = f.fur
	var light: Color = f.light
	var dark_c := fur.darkened(0.45)
	t = float(id) * 0.7
	match String(f.kind):
		"bunny":
			_ball(body, Vector3(0, 0.2, 0), Vector3(0.2, 0.2, 0.22), fur)
			_ball(body, Vector3(0, 0.42, -0.08), Vector3(0.15, 0.14, 0.14), fur)
			_ball(body, Vector3(0, 0.2, 0.22), Vector3(0.07, 0.07, 0.07), Color(1, 1, 1))  # tail
			for s in [-1.0, 1.0]:
				_ear(Vector3(0.06 * s, 0.52, -0.06), Vector3(0.04, 0.16, 0.03), fur, light, 0.18 * s)
		"kitten":
			_ball(body, Vector3(0, 0.2, 0), Vector3(0.18, 0.2, 0.22), fur)
			_ball(body, Vector3(0, 0.42, -0.08), Vector3(0.15, 0.13, 0.13), fur)
			for s in [-1.0, 1.0]:
				_ear(Vector3(0.09 * s, 0.53, -0.07), Vector3(0.05, 0.07, 0.03), fur, light, 0.3 * s)
			_ball(body, Vector3(0.12, 0.12, 0.2), Vector3(0.03, 0.03, 0.14), fur)  # tail
		"hedgehog":
			_ball(body, Vector3(0, 0.17, 0.02), Vector3(0.22, 0.17, 0.25), dark_c)
			for k in 10:  # spikes
				var a := TAU * k / 10.0
				_ball(body, Vector3(cos(a) * 0.16, 0.22 + sin(a * 2.0) * 0.03, 0.06 + sin(a) * 0.14), Vector3(0.06, 0.08, 0.06), dark_c.darkened(0.2))
			_ball(body, Vector3(0, 0.22, -0.17), Vector3(0.11, 0.1, 0.12), light)
		"owl":
			_ball(body, Vector3(0, 0.28, 0), Vector3(0.18, 0.26, 0.17), fur)
			_ball(body, Vector3(0, 0.25, -0.1), Vector3(0.12, 0.17, 0.08), light)
			for s in [-1.0, 1.0]:
				_ear(Vector3(0.1 * s, 0.52, -0.02), Vector3(0.035, 0.07, 0.03), fur, fur, 0.35 * s)
				_ball(body, Vector3(0.18 * s, 0.28, 0.02), Vector3(0.05, 0.16, 0.12), fur.darkened(0.15))  # wings
			_ball(body, Vector3(0, 0.36, -0.17), Vector3(0.025, 0.03, 0.03), Color(1.0, 0.7, 0.2))  # beak
		"tortoise":
			_ball(body, Vector3(0, 0.15, 0.04), Vector3(0.26, 0.15, 0.28), fur.darkened(0.2))  # shell
			_ball(body, Vector3(0, 0.22, 0.04), Vector3(0.17, 0.08, 0.19), fur)
			_ball(body, Vector3(0, 0.18, -0.26), Vector3(0.09, 0.08, 0.1), light)  # head
			for s in [-1.0, 1.0]:
				_ball(body, Vector3(0.17 * s, 0.05, -0.13), Vector3(0.05, 0.05, 0.05), light)
				_ball(body, Vector3(0.17 * s, 0.05, 0.2), Vector3(0.05, 0.05, 0.05), light)
		"frog":
			_ball(body, Vector3(0, 0.15, 0), Vector3(0.22, 0.15, 0.22), fur)
			_ball(body, Vector3(0, 0.12, -0.12), Vector3(0.16, 0.08, 0.1), light)
			for s in [-1.0, 1.0]:
				_ball(body, Vector3(0.18 * s, 0.06, 0.08), Vector3(0.08, 0.06, 0.12), fur.darkened(0.1))
		"squirrel":
			_ball(body, Vector3(0, 0.2, 0), Vector3(0.15, 0.19, 0.17), fur)
			_ball(body, Vector3(0, 0.18, -0.1), Vector3(0.09, 0.13, 0.07), light)
			_ball(body, Vector3(0, 0.4, -0.06), Vector3(0.12, 0.11, 0.11), fur)
			for s in [-1.0, 1.0]:
				_ear(Vector3(0.07 * s, 0.5, -0.05), Vector3(0.03, 0.06, 0.02), fur, fur, 0.2 * s)
			_ball(body, Vector3(0, 0.36, 0.2), Vector3(0.1, 0.24, 0.1), fur.lightened(0.1))  # big tail
		_:  # hamster
			_ball(body, Vector3(0, 0.17, 0), Vector3(0.2, 0.17, 0.2), fur)
			_ball(body, Vector3(0, 0.15, -0.12), Vector3(0.14, 0.11, 0.1), light)
			for s in [-1.0, 1.0]:
				_ear(Vector3(0.1 * s, 0.33, -0.04), Vector3(0.04, 0.04, 0.02), fur, light, 0.0)
	var eye_y := {"bunny": 0.46, "kitten": 0.45, "hedgehog": 0.25, "owl": 0.42, "tortoise": 0.21, "frog": 0.3, "squirrel": 0.43, "hamster": 0.24}
	var eye_z := {"bunny": -0.2, "kitten": -0.19, "hedgehog": -0.26, "owl": -0.15, "tortoise": -0.33, "frog": -0.08, "squirrel": -0.16, "hamster": -0.2}
	var ey: float = eye_y.get(String(f.kind), 0.4)
	var ez: float = eye_z.get(String(f.kind), -0.2)
	var big := 0.05 if f.kind == "owl" or f.kind == "frog" else 0.028
	for s in [-1.0, 1.0]:
		if f.kind == "owl" or f.kind == "frog":
			_ball(body, Vector3(0.06 * s, ey, ez + 0.01), Vector3(big, big, big * 0.6), Color(1, 1, 1))
		var e := _ball(body, Vector3(0.055 * s, ey, ez - (big * 0.4 if big > 0.03 else 0.0)), Vector3(0.024, 0.028, 0.018), Color(0.08, 0.06, 0.06))
		eye_mats.append(e.material_override)
	return self


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.set_meta("base", c)
	mats.append(m)
	return m


func _ball(parent: Node3D, at: Vector3, radii: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = _mat(c)
	mi.position = at
	mi.scale = radii
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _ear(at: Vector3, radii: Vector3, c: Color, inner: Color, tilt: float) -> void:
	var ear := Node3D.new()
	ear.position = at
	ear.rotation.z = -tilt
	body.add_child(ear)
	_ball(ear, Vector3(0, radii.y * 0.8, 0), radii, c)
	if inner != c:
		_ball(ear, Vector3(0, radii.y * 0.8, -radii.z * 0.6), radii * Vector3(0.55, 0.75, 0.5), inner)
	ears.append(ear)


static var _vc_mat: StandardMaterial3D


## At the party: bake every sphere into ONE vertex-coloured mesh (one draw call per friend; 8 friends sit there).
func merge() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts: Array = []
	_collect(body, Transform3D(), parts)
	for pt in parts:
		var mi: MeshInstance3D = pt[0]
		var xf: Transform3D = pt[1]
		var col: Color = (mi.material_override as StandardMaterial3D).albedo_color
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		st.set_color(col)
		for i in idx:
			st.set_normal((nb * n[i]).normalized())
			st.add_vertex(xf * v[i])
	for c in body.get_children():
		c.queue_free()
	ears.clear()
	mats.clear()
	eye_mats.clear()
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.roughness = 0.8
	var one := MeshInstance3D.new()
	one.mesh = st.commit()
	one.material_override = _vc_mat
	one.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(one)


func _collect(n: Node3D, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D:
			var cx: Transform3D = xf * (c as Node3D).transform
			if c is MeshInstance3D:
				out.append([c, cx])
			_collect(c, cx, out)


## In a dark room: a dim body and glowing eyes (only the torch shows the rest).
func set_dark(on: bool) -> void:
	dark = on
	for m in mats:
		var base: Color = m.get_meta("base")
		m.albedo_color = base.darkened(0.75) if on else base
	for m in eye_mats:
		m.emission_enabled = on
		m.albedo_color = Color(1.0, 0.95, 0.5) if on else Color(0.08, 0.06, 0.06)
		m.emission = Color(1.0, 0.9, 0.4)
		m.emission_energy_multiplier = 2.5


## Hide at a spot facing `yaw` (or sit at the party).
func hide_at(spot: Vector3, yaw: float) -> void:
	position = spot
	rotation = Vector3(0, yaw, 0)
	hop_t = -1.0
	visible = true
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.scale = Vector3.ONE


func found() -> void:
	if hop_t < 0.0 and visible:
		hop_t = 0.0


func center() -> Vector3:
	return global_position + Vector3.UP * 0.25


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	for i in ears.size():
		ears[i].rotation.x = 0.35 * maxf(0.0, sin(t * 1.1 + i * 0.9) - 0.8) * 5.0
	if party:
		body.position.y = absf(sin(t * 2.2)) * 0.05
		body.rotation.y = sin(t * 0.8) * 0.3
		return
	body.position.y = absf(sin(t * 3.0)) * 0.012 * (1.0 + 3.0 * excite)
	if hop_t >= 0.0:
		hop_t += delta
		body.position.y = absf(sin(hop_t * 9.0)) * 0.3
		body.rotation.y = hop_t * 10.0
		if hop_t > 1.0:
			body.scale = Vector3.ONE * maxf(0.01, 1.0 - (hop_t - 1.0) * 4.0)
		if hop_t > 1.25:
			visible = false
