extends Node3D
## Pooled visual effects (every machine): particle bursts, chunky building debris (one MultiMesh, CPU
## simulated), expanding shock rings, gun tracers, danger markers for telegraphed kaiju attacks, and
## dizzy-star halos. Nothing here affects gameplay; the host sends events and every machine plays them.
##
##   fx.burst("boom", pos, 2.0)            # kinds: boom, sparks, dust, foam, repair, stars, smoke, splash, zap, goo, fire
##   fx.debris(pos, Vector3(8, 10, 8), [wall, roof], 24)
##   fx.ring(pos, 12.0, Color(1, 0.6, 0.2), 0.6)
##   fx.tracer(from, to, Color(1, 0.9, 0.4))
##   var m := fx.marker(pos, 8.0, Color(1, 0.3, 0.2), 1.2)   # telegraph circle (frees itself)

const MeshKit := preload("res://core/mesh_kit.gd")

const POOL := 6
const DEBRIS_MAX := 180

var _pools := {}  # kind -> Array[CPUParticles3D]
var _next := {}  # kind -> int
var _debris_mm: MultiMesh
var _debris: Array[Dictionary] = []  # {p, v, r, w, s, t}
var _debris_next := 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_t: Array[float] = []
var _tracer_next := 0
var _rings: Array[Dictionary] = []  # {node, t, dur, r}
var _markers: Array[Dictionary] = []  # {node, t, dur}
var _mats := {}


func _ready() -> void:
	name = "Fx"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	box.material = mat
	_debris_mm = MultiMesh.new()
	_debris_mm.transform_format = MultiMesh.TRANSFORM_3D
	_debris_mm.use_colors = true
	_debris_mm.mesh = box
	_debris_mm.instance_count = DEBRIS_MAX
	_debris_mm.visible_instance_count = DEBRIS_MAX
	for i in DEBRIS_MAX:
		_debris_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
		_debris_mm.set_instance_color(i, Color.WHITE)
		_debris.append({"p": Vector3(0, -50, 0), "v": Vector3.ZERO, "r": Vector3.ZERO, "w": Vector3.ZERO, "s": Vector3.ONE, "t": -1.0})
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Debris"
	mmi.multimesh = _debris_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in 16:
		var t := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 1.0
		cm.radial_segments = 4
		cm.rings = 1
		t.mesh = cm
		t.material_override = _glow_mat(Color(1.0, 0.9, 0.4))
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(t)
		_tracers.append(t)
		_tracer_t.append(0.0)


func _glow_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html(true)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


# --- Particle bursts ------------------------------------------------------------------------------

## One-shot burst of `kind` at pos. scale ~ size in metres / 2.
func burst(kind: String, pos: Vector3, scale: float = 1.0, color: Color = Color(0, 0, 0, 0)) -> void:
	if not is_inside_tree():
		return
	var list: Array = _pools.get(kind, [])
	if list.is_empty():
		for i in POOL:
			var p := _make(kind)
			add_child(p)
			list.append(p)
		_pools[kind] = list
		_next[kind] = 0
	var i2: int = _next[kind]
	_next[kind] = (i2 + 1) % list.size()
	var part: CPUParticles3D = list[i2]
	part.global_position = pos
	part.scale = Vector3.ONE * maxf(scale, 0.05)
	if color.a > 0.0:
		part.color = color
	else:
		part.color = Color.WHITE
	part.restart()
	part.emitting = true


func _make(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.local_coords = false
	var sm := SphereMesh.new()
	sm.radial_segments = 8
	sm.rings = 4
	sm.radius = 0.5
	sm.height = 1.0
	var col := Color(1, 1, 1)
	var glow := 0.0
	p.mesh = sm
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	match kind:
		"boom":
			p.amount = 22
			p.lifetime = 0.9
			p.spread = 180.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 9.0
			p.gravity = Vector3(0, 2.0, 0)
			p.scale_amount_min = 1.2
			p.scale_amount_max = 2.6
			col = Color(1.0, 0.65, 0.25)
			glow = 2.5
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.95, 0.6))
			g.set_color(1, Color(0.5, 0.45, 0.45))
			p.color_ramp = g
		"sparks":
			p.amount = 18
			p.lifetime = 0.45
			p.spread = 180.0
			p.initial_velocity_min = 6.0
			p.initial_velocity_max = 14.0
			p.gravity = Vector3(0, -18.0, 0)
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.5
			col = Color(1.0, 0.85, 0.35)
			glow = 3.0
			var bm := BoxMesh.new()
			bm.size = Vector3(0.4, 0.4, 0.4)
			p.mesh = bm
		"dust":
			p.amount = 16
			p.lifetime = 1.4
			p.spread = 90.0
			p.direction = Vector3.UP
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.0
			p.gravity = Vector3(0, -0.5, 0)
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = 2.0
			p.emission_ring_inner_radius = 0.5
			p.emission_ring_height = 0.2
			p.scale_amount_min = 1.6
			p.scale_amount_max = 3.2
			var c2 := Curve.new()
			c2.add_point(Vector2(0, 0.5))
			c2.add_point(Vector2(0.3, 1.0))
			c2.add_point(Vector2(1, 0.0))
			p.scale_amount_curve = c2
			col = Color(0.82, 0.78, 0.7, 0.8)
		"foam":
			p.amount = 14
			p.lifetime = 1.2
			p.spread = 70.0
			p.direction = Vector3.UP
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.0
			p.gravity = Vector3(0, -6.0, 0)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.2
			col = Color(0.97, 0.98, 1.0)
		"repair":
			p.amount = 12
			p.lifetime = 0.5
			p.spread = 180.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 7.0
			p.gravity = Vector3(0, -10.0, 0)
			p.scale_amount_min = 0.2
			p.scale_amount_max = 0.4
			col = Color(0.5, 1.0, 0.6)
			glow = 3.0
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.35, 0.35, 0.35)
			p.mesh = bm2
		"stars":
			p.amount = 10
			p.lifetime = 0.9
			p.spread = 180.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 6.0
			p.gravity = Vector3(0, -4.0, 0)
			p.scale_amount_min = 1.2
			p.scale_amount_max = 2.0
			p.mesh = MeshKit.prop("star")
			col = Color(1.0, 0.9, 0.35)
			glow = 2.0
		"smoke":
			p.amount = 10
			p.lifetime = 1.6
			p.spread = 40.0
			p.direction = Vector3.UP
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 3.0
			p.gravity = Vector3(0, 0.6, 0)
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.0
			col = Color(0.35, 0.33, 0.35, 0.7)
		"splash":
			p.amount = 18
			p.lifetime = 1.0
			p.spread = 35.0
			p.direction = Vector3.UP
			p.initial_velocity_min = 6.0
			p.initial_velocity_max = 12.0
			p.gravity = Vector3(0, -16.0, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.1
			col = Color(0.65, 0.85, 1.0)
		"zap":
			p.amount = 16
			p.lifetime = 0.35
			p.spread = 180.0
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 16.0
			p.gravity = Vector3.ZERO
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.6
			col = Color(0.6, 0.85, 1.0)
			glow = 4.0
			var bm3 := BoxMesh.new()
			bm3.size = Vector3(0.2, 0.2, 1.6)
			p.mesh = bm3
			p.particle_flag_align_y = false
		"goo":
			p.amount = 12
			p.lifetime = 0.8
			p.spread = 180.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 7.0
			p.gravity = Vector3(0, -14.0, 0)
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.6
			col = Color(0.95, 0.5, 0.9)
			glow = 0.5
		"fire":
			p.amount = 14
			p.lifetime = 0.7
			p.spread = 25.0
			p.direction = Vector3.UP
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 6.0
			p.gravity = Vector3(0, 3.0, 0)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.0
			col = Color(1.0, 0.55, 0.15)
			glow = 2.5
		_:
			p.amount = 10
			p.lifetime = 0.6
			p.spread = 180.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.0
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = col
	if col.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, col.a)
	mat.roughness = 1.0
	p.material_override = mat
	return p


# --- Debris ---------------------------------------------------------------------------------------

## Chunky pieces flying out of a collapsing building (pos = its base centre, size = its size).
func debris(pos: Vector3, size: Vector3, colors: Array, count: int = 24) -> void:
	for k in count:
		var i := _debris_next
		_debris_next = (_debris_next + 1) % DEBRIS_MAX
		var d: Dictionary = _debris[i]
		var start := pos + Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(0.3, 1.0) * size.y, randf_range(-0.5, 0.5) * size.z)
		var out := (start - pos)
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
		d["p"] = start
		d["v"] = out * randf_range(3.0, 9.0) + Vector3(0, randf_range(3.0, 9.0), 0)
		d["r"] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		d["w"] = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		var s := randf_range(0.7, 2.0)
		d["s"] = Vector3(s, s * randf_range(0.6, 1.2), s * randf_range(0.7, 1.3))
		d["t"] = 0.0
		var c: Color = colors[k % colors.size()] if not colors.is_empty() else Color(0.7, 0.7, 0.7)
		_debris_mm.set_instance_color(i, c.darkened(randf() * 0.2))


func _tick_debris(delta: float) -> void:
	for i in DEBRIS_MAX:
		var d: Dictionary = _debris[i]
		var t: float = d["t"]
		if t < 0.0:
			continue
		t += delta
		d["t"] = t
		var p: Vector3 = d["p"]
		var v: Vector3 = d["v"]
		var r: Vector3 = d["r"]
		var w: Vector3 = d["w"]
		v.y -= 22.0 * delta
		p += v * delta
		if p.y < 0.4:
			p.y = 0.4
			v.y = absf(v.y) * 0.3
			v.x *= 0.6
			v.z *= 0.6
			w *= 0.6
		r += w * delta
		d["p"] = p
		d["v"] = v
		d["r"] = r
		d["w"] = w
		var s: Vector3 = d["s"]
		var fade := clampf((5.0 - t) / 1.2, 0.0, 1.0)
		if t > 5.0:
			d["t"] = -1.0
			_debris_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
			continue
		_debris_mm.set_instance_transform(i, Transform3D(Basis.from_euler(r).scaled(s * fade), p))


# --- Rings, tracers, markers ------------------------------------------------------------------------

## An expanding flat ring (shockwave) from radius 1 to `radius` over `dur` seconds.
func ring(pos: Vector3, radius: float, color: Color, dur: float = 0.6) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	mi.mesh = tm
	mi.material_override = _glow_mat(Color(color.r, color.g, color.b, 0.7))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3(0, 0.3, 0)
	mi.scale = Vector3(1.0, 0.3, 1.0)
	_rings.append({"node": mi, "t": 0.0, "dur": dur, "r": radius})


## A short glowing line (gun shot) that fades in 0.12 s.
func tracer(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.9, 0.4)) -> void:
	var t := _tracers[_tracer_next]
	_tracer_t[_tracer_next] = 0.12
	_tracer_next = (_tracer_next + 1) % _tracers.size()
	var d := to - from
	var l := d.length()
	if l < 0.05:
		return
	t.material_override = _glow_mat(color)
	t.visible = true
	t.global_transform = Transform3D(_basis_y_to(d / l).scaled(Vector3(1.0, l, 1.0)), from + d * 0.5)


## A pulsing danger circle on the ground for a telegraphed attack (frees itself after `dur`).
func marker(pos: Vector3, radius: float, color: Color, dur: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.05
	cm.radial_segments = 28
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _glow_mat(Color(color.r, color.g, color.b, 0.35))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(pos.x, 0.25, pos.z)
	mi.scale = Vector3(radius, 1.0, radius)
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	tm.rings = 28
	tm.ring_segments = 4
	edge.mesh = tm
	edge.material_override = _glow_mat(Color(color.r, color.g, color.b, 0.9))
	edge.scale = Vector3(1.0, 2.0, 1.0)
	mi.add_child(edge)
	_markers.append({"node": mi, "t": 0.0, "dur": dur})
	return mi


## A glowing line on the ground from a to b (eye-laser sweep, charge path) that frees itself.
func line_marker(a: Vector3, b: Vector3, width: float, color: Color, dur: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 0.05, 1)
	mi.mesh = bm
	mi.material_override = _glow_mat(Color(color.r, color.g, color.b, 0.45))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var mid := (a + b) * 0.5
	mi.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)).scaled(Vector3(width, 1.0, d.length())), Vector3(mid.x, 0.25, mid.z))
	_markers.append({"node": mi, "t": 0.0, "dur": dur})
	return mi


static func _basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _process(delta: float) -> void:
	_tick_debris(delta)
	for i in _tracers.size():
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			if _tracer_t[i] <= 0.0:
				_tracers[i].visible = false
	for k in range(_rings.size() - 1, -1, -1):
		var r: Dictionary = _rings[k]
		var n: MeshInstance3D = r["node"]
		var t: float = float(r["t"]) + delta
		r["t"] = t
		var dur: float = r["dur"]
		if t >= dur or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_rings.remove_at(k)
			continue
		var s := lerpf(1.0, float(r["r"]), t / dur)
		n.scale = Vector3(s, 0.3 + s * 0.05, s)
		n.transparency = t / dur
	for k in range(_markers.size() - 1, -1, -1):
		var m: Dictionary = _markers[k]
		var n2: Node3D = m["node"]
		var t2: float = float(m["t"]) + delta
		m["t"] = t2
		if t2 >= float(m["dur"]) or not is_instance_valid(n2):
			if is_instance_valid(n2):
				n2.queue_free()
			_markers.remove_at(k)
			continue
		var g := n2 as GeometryInstance3D
		if g != null:
			g.transparency = 0.35 + 0.35 * sin(t2 * 14.0)
