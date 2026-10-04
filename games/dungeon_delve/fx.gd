extends Node3D
## DUNGEON DELVE effects (both machines draw them; the host sends them as events): poofs and
## sparkles, sword/axe slash arcs, expanding rings (novas, shockwaves, heal circles), hit sparks,
## light pillars, and ground telegraphs (red warning circles / cones / lines before big attacks).
## Everything is short-lived, unshaded and cheap; materials are cached.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

var _decals: Array = []  # [node, t, life]


func _add_mat(col: Color, alpha: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	return m


func _particle_mesh(size: float) -> Mesh:
	return ResCache.get_or_make("dd_fx_pmesh_%.2f" % size, func() -> Resource:
		var m := BoxMesh.new()
		m.size = Vector3.ONE * size
		return m) as Mesh


## A burst of glowing bits (defeated monsters poof into sparkles; pots shatter; coins sparkle).
func poof(pos: Vector3, col: Color, amount: int = 18, size: float = 1.0, up: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0, -4.0 * up, 0)
	p.initial_velocity_min = 1.5 * size
	p.initial_velocity_max = 4.0 * size
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh := _particle_mesh(0.09 * size)
	p.mesh = mesh
	p.material_override = MeshKit.material(col, 2.5)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2, false).timeout.connect(p.queue_free)


## A soft round puff (smoke / dust) plus sparkles: the "poof" when a monster is defeated.
func defeat_poof(pos: Vector3, col: Color, big: bool = false) -> void:
	poof(pos + Vector3.UP * 0.5, Color(1, 1, 1), 14 if not big else 30, 1.0 if not big else 1.6, 0.3)
	poof(pos + Vector3.UP * 0.5, col, 12 if not big else 28, 1.2 if not big else 2.0)
	var s := MeshInstance3D.new()
	var sm: Mesh = ResCache.get_or_make("dd_fx_puff", func() -> Resource:
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 12
		m.rings = 6
		return m) as Mesh
	s.mesh = sm
	s.material_override = _add_mat(Color(1, 1, 1), 0.5)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	s.global_position = pos + Vector3.UP * 0.5
	s.scale = Vector3.ONE * 0.3
	var tw := s.create_tween().set_parallel()
	tw.tween_property(s, "scale", Vector3.ONE * (1.6 if not big else 3.5), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s.material_override, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(s.queue_free)


## A crescent slash in front of `pos` facing `dir` (melee swings). arc in degrees, reach in m.
func slash(pos: Vector3, dir: Vector3, col: Color, arc: float = 120.0, reach: float = 2.2) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	d = d.normalized()
	var key := "dd_fx_arc_%d" % int(arc)
	var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 14
		var half := deg_to_rad(arc) * 0.5
		for i in segs:
			var a0 := -half + (2.0 * half) * float(i) / segs
			var a1 := -half + (2.0 * half) * float(i + 1) / segs
			var o0 := Vector3(sin(a0), 0, cos(a0))
			var o1 := Vector3(sin(a1), 0, cos(a1))
			var i0 := o0 * 0.55
			var i1 := o1 * 0.55
			var f0 := 1.0 - absf(a0) / half
			var f1 := 1.0 - absf(a1) / half
			for v in [[i0, 0.0], [o0, f0], [o1, f1], [i0, 0.0], [o1, f1], [i1, 0.0]]:
				var va: Array = v
				st.set_color(Color(1, 1, 1, float(va[1])))
				st.add_vertex(va[0])
		return st.commit()) as ArrayMesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _add_mat(col, 1.0)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.7
	mi.global_basis = Basis(Vector3.UP, atan2(d.x, d.z)).scaled(Vector3(reach, 1.0, reach))
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "rotation:y", mi.rotation.y + 0.5, 0.18)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.2).set_delay(0.06)
	tw.chain().tween_callback(mi.queue_free)


## An expanding ring on the floor: novas, shockwaves, heals.
func ring(pos: Vector3, radius: float, col: Color, time: float = 0.45, thick: float = 0.22) -> void:
	var mi := MeshInstance3D.new()
	var tm: Mesh = ResCache.get_or_make("dd_fx_ring", func() -> Resource:
		var m := TorusMesh.new()
		m.inner_radius = 0.88
		m.outer_radius = 1.0
		m.rings = 28
		m.ring_segments = 6
		return m) as Mesh
	mi.mesh = tm
	var m := _add_mat(col, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.15
	mi.scale = Vector3(0.2, thick * 4.0, 0.2)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, thick * 4.0, radius), time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, time * 0.6).set_delay(time * 0.4)
	tw.chain().tween_callback(mi.queue_free)


## A light pillar (revive, level up, blessing).
func pillar(pos: Vector3, col: Color, time: float = 1.0, height: float = 4.0) -> void:
	var mi := MeshInstance3D.new()
	var cm: Mesh = ResCache.get_or_make("dd_fx_pillar", func() -> Resource:
		var m := CylinderMesh.new()
		m.top_radius = 0.6
		m.bottom_radius = 0.6
		m.height = 1.0
		m.radial_segments = 12
		m.rings = 1
		m.cap_top = false
		m.cap_bottom = false
		return m) as Mesh
	mi.mesh = cm
	var m := _add_mat(col, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * height * 0.5
	mi.scale = Vector3(0.2, height, 0.2)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(1.0, height, 1.0), time * 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, time * 0.7).set_delay(time * 0.3)
	tw.chain().tween_callback(mi.queue_free)
	poof(pos + Vector3.UP * 0.5, col, 16, 1.0, -0.4)


## Small hit spark at the impact point.
func spark(pos: Vector3, col: Color, big: bool = false) -> void:
	poof(pos, col, 8 if not big else 16, 0.7 if not big else 1.1, 1.0)


## Ground telegraph: shape "circle" (radius), "ring" (radius), "cone" (radius, angle deg, dir),
## "line" (length, width, dir). Pulses red and fades after `life` s.
func telegraph(shape: String, pos: Vector3, radius: float, life: float, dir: Vector3 = Vector3.FORWARD, angle: float = 60.0, width: float = 1.5) -> void:
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	match shape:
		"cone":
			mesh = _cone_mesh(angle)
			mi.scale = Vector3(radius, 1.0, radius)
		"line":
			mesh = _quad_mesh()
			mi.scale = Vector3(width, 1.0, radius)
		"ring":
			mesh = ResCache.get_or_make("dd_fx_tele_ring", func() -> Resource:
				var m := TorusMesh.new()
				m.inner_radius = 0.82
				m.outer_radius = 1.0
				m.rings = 32
				m.ring_segments = 4
				return m) as Mesh
			mi.scale = Vector3(radius, 0.05, radius)
		_:
			mesh = ResCache.get_or_make("dd_fx_tele_disc", func() -> Resource:
				var m := CylinderMesh.new()
				m.top_radius = 1.0
				m.bottom_radius = 1.0
				m.height = 0.01
				m.radial_segments = 28
				m.rings = 1
				return m) as Mesh
			mi.scale = Vector3(radius, 1.0, radius)
	mi.mesh = mesh
	var m := _add_mat(Color(1.0, 0.25, 0.15), 0.35)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	mi.global_position = pos + Vector3.UP * 0.05
	mi.rotation.y = atan2(d.x, d.z)
	_decals.append([mi, 0.0, life, m])


func _cone_mesh(angle: float) -> Mesh:
	return ResCache.get_or_make("dd_fx_cone_%d" % int(angle), func() -> Resource:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 12
		var half := deg_to_rad(angle) * 0.5
		for i in segs:
			var a0 := -half + 2.0 * half * float(i) / segs
			var a1 := -half + 2.0 * half * float(i + 1) / segs
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(Vector3(sin(a1), 0, cos(a1)))
			st.add_vertex(Vector3(sin(a0), 0, cos(a0)))
		return st.commit()) as Mesh


func _quad_mesh() -> Mesh:
	return ResCache.get_or_make("dd_fx_line", func() -> Resource:
		var m := BoxMesh.new()
		m.size = Vector3(1.0, 0.01, 1.0)
		return m) as Mesh


func _process(delta: float) -> void:
	var i := 0
	while i < _decals.size():
		var d: Array = _decals[i]
		var node: MeshInstance3D = d[0]
		d[1] = float(d[1]) + delta
		var t: float = d[1]
		var life: float = d[2]
		if not is_instance_valid(node) or t >= life:
			if is_instance_valid(node):
				node.queue_free()
			_decals.remove_at(i)
			continue
		var m: StandardMaterial3D = d[3]
		var k := t / life
		m.albedo_color.a = 0.22 + 0.25 * (0.5 + 0.5 * sin(t * (10.0 + 14.0 * k))) + 0.2 * k
		if node.mesh is CylinderMesh or node.mesh is TorusMesh:
			pass
		i += 1


## Remove every telegraph (floor change).
func clear_decals() -> void:
	for d in _decals:
		var da: Array = d
		var n: Node = da[0]
		if is_instance_valid(n):
			n.queue_free()
	_decals.clear()
