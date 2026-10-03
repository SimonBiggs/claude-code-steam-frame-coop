extends RefCounted
## Arena decoration, built once: bleachers full of cheering neon spectators, stars, a ringed planet,
## slowly turning holo rings and drifting sparks. Repeated props are MultiMeshes (one draw call each).
## The crowd's ShaderMaterials are kept as main metas ("crowd_mats") so the director can make them cheer.

const CROWD_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_back;
uniform float cheer = 0.0;
uniform float glow = 0.5;
varying vec3 tint;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float sp = 2.0 + INSTANCE_CUSTOM.y * 2.5 + cheer * 5.0;
	float hop = abs(sin(TIME * sp + ph)) * (0.04 + cheer * 0.5);
	float sq = 1.0 + 0.08 * cos(TIME * sp * 2.0 + ph * 2.0) * (0.5 + cheer);
	vec3 rel = VERTEX - origin;
	rel.y *= sq;
	rel.xz /= sqrt(sq);
	VERTEX = origin + rel + vec3(0.0, hop, 0.0);
	tint = COLOR.rgb;
}
void fragment() {
	ALBEDO = tint * 0.6;
	ROUGHNESS = 0.5;
	EMISSION = tint * (glow + cheer * 1.5);
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float energy = 2.5;
void fragment() {
	ALBEDO = COLOR.rgb * energy;
}
"""

const CROWD_COLORS: Array[Color] = [Color(1.0, 0.35, 0.6), Color(0.3, 0.8, 1.0), Color(1.0, 0.75, 0.25),
	Color(0.55, 1.0, 0.35), Color(0.75, 0.45, 1.0), Color(0.3, 1.0, 0.85), Color(1.0, 0.5, 0.2)]


## One MultiMeshInstance3D for many copies of a mesh (optional per-instance colours).
static func multimesh(mesh: Mesh, mat: Material, xforms: Array[Transform3D], colors: Array[Color],
		custom: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Unshaded glow that takes its colour from the MultiMesh instance colours.
static func glow_material(energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = GLOW_SHADER
	m.set_shader_parameter("energy", energy)
	return m


static func build(main: Node3D, radius: float) -> void:
	_add_stands(main, radius)
	_add_sky(main)
	_add_holo_rings(main)
	_add_sparks(main, radius)


## Three tiers of bleachers just outside the force field, packed with bouncing neon fans.
static func _add_stands(main: Node3D, radius: float) -> void:
	var dark: StandardMaterial3D = main.make_material(Color(0.08, 0.08, 0.12), 0.0)
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	dark.metallic = 0.4
	var tiers := [[radius + 2.0, 0.6], [radius + 4.5, 1.6], [radius + 7.0, 2.6]]
	var trim_cols: Array[Color] = [Color(1.0, 0.3, 0.7), Color(0.3, 0.85, 1.0), Color(1.0, 0.7, 0.25)]
	var prev_h := 0.0
	for i in tiers.size():
		var r: float = tiers[i][0]
		var h: float = tiers[i][1]
		# Riser (open cylinder wall) from the previous tread up to this one.
		var riser := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = h - prev_h
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 48
		cyl.rings = 1
		riser.mesh = cyl
		riser.material_override = dark
		riser.position.y = (h + prev_h) * 0.5
		riser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(riser)
		# Tread: a flattened torus makes a flat ring to sit on.
		var tread := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r
		tm.outer_radius = r + 2.5
		tm.rings = 48
		tm.ring_segments = 4
		tread.mesh = tm
		tread.material_override = dark
		tread.scale = Vector3(1.0, 0.06, 1.0)
		tread.position.y = h
		tread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(tread)
		# Neon trim along the front edge.
		var trim := MeshInstance3D.new()
		var tt := TorusMesh.new()
		tt.inner_radius = r - 0.06
		tt.outer_radius = r + 0.06
		tt.rings = 64
		tt.ring_segments = 4
		trim.mesh = tt
		trim.material_override = main.make_material(trim_cols[i], 3.0)
		trim.position.y = h + 0.05
		trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(trim)
		prev_h = h
	# The fans: egg-shaped blobs with glowing eyes, facing the arena. Gaps keep it from looking tiled.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bodies: Array[Transform3D] = []
	var body_cols: Array[Color] = []
	var body_custom: Array[Color] = []
	var eyes: Array[Transform3D] = []
	var eye_cols: Array[Color] = []
	var eye_custom: Array[Color] = []
	for i in tiers.size():
		var r: float = tiers[i][0] + 1.0
		var h: float = tiers[i][1]
		var count := int(TAU * r / 1.6)
		for k in count:
			if rng.randf() < 0.3:
				continue
			var a := TAU * k / count + rng.randf_range(-0.03, 0.03)
			var s := rng.randf_range(0.8, 1.2)
			var at := Vector3(cos(a) * r, h + 0.42 * s, sin(a) * r)
			var face := Vector3(-cos(a), 0.0, -sin(a))  # towards the arena
			var basis := Basis.looking_at(face, Vector3.UP)
			bodies.append(Transform3D(basis.scaled(Vector3.ONE * s), at))
			body_cols.append(CROWD_COLORS[rng.randi() % CROWD_COLORS.size()])
			var custom := Color(rng.randf(), rng.randf(), 0.0, 0.0)
			body_custom.append(custom)
			var side := basis.x
			for e in [-1.0, 1.0]:
				var eye_at: Vector3 = at + side * (e * 0.12 * s) + Vector3.UP * 0.14 * s + face * 0.3 * s
				eyes.append(Transform3D(basis.scaled(Vector3.ONE * s), eye_at))
				eye_cols.append(Color(1.0, 1.0, 0.95))
				eye_custom.append(custom)
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 0.85
	body_mesh.radial_segments = 10
	body_mesh.rings = 6
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.065
	eye_mesh.height = 0.13
	eye_mesh.radial_segments = 6
	eye_mesh.rings = 3
	var body_mat := _crowd_material(0.45)
	var eye_mat := _crowd_material(2.5)
	main.add_child(multimesh(body_mesh, body_mat, bodies, body_cols, body_custom))
	main.add_child(multimesh(eye_mesh, eye_mat, eyes, eye_cols, eye_custom))
	main.set_meta("crowd_mats", [body_mat, eye_mat])


static func _crowd_material(glow: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = CROWD_SHADER
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("cheer", 0.0)
	return m


## Stars and a big ringed planet above the skyline.
static func _add_sky(main: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var stars: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in 260:
		var az := rng.randf() * TAU
		var el := deg_to_rad(rng.randf_range(12.0, 85.0))
		var d := rng.randf_range(150.0, 180.0)
		var dir := Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
		var s := rng.randf_range(0.5, 1.3)
		stars.append(Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf(), 0.0)).scaled(Vector3.ONE * s), dir * d))
		var tint := rng.randf()
		cols.append(Color(0.9, 0.95, 1.0) if tint < 0.6 else (Color(1.0, 0.8, 0.9) if tint < 0.8 else Color(0.7, 0.9, 1.0)))
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.vertex_color_use_as_albedo = true
	star_mat.set("disable_fog", true)
	main.add_child(multimesh(BoxMesh.new(), star_mat, stars, cols))
	var planet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 14.0
	sm.height = 28.0
	sm.radial_segments = 20
	sm.rings = 10
	planet.mesh = sm
	var pm: StandardMaterial3D = main.make_material(Color(0.55, 0.25, 0.75), 0.9)
	pm.rim_enabled = true
	pm.rim = 1.0
	pm.set("disable_fog", true)
	planet.material_override = pm
	planet.position = Vector3(-60.0, 52.0, -115.0)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(planet)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 19.0
	tm.outer_radius = 25.0
	tm.rings = 48
	tm.ring_segments = 4
	ring.mesh = tm
	var rm: StandardMaterial3D = main.make_material(Color(1.0, 0.55, 0.8), 1.6)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color.a = 0.55
	rm.set("disable_fog", true)
	ring.material_override = rm
	ring.scale = Vector3(1.0, 0.04, 1.0)
	ring.rotation = Vector3(0.45, 0.0, 0.3)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(ring)


## Two thin glowing rings slowly turning high above the arena.
static func _add_holo_rings(main: Node3D) -> void:
	var specs := [[7.0, 9.5, Color(0.3, 0.9, 1.0), 50.0], [10.0, 11.0, Color(1.0, 0.35, 0.75), -70.0]]
	for spec in specs:
		var pivot := Node3D.new()
		pivot.position.y = spec[1]
		main.add_child(pivot)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = spec[0]
		tm.outer_radius = float(spec[0]) + 0.12
		tm.rings = 64
		tm.ring_segments = 4
		ring.mesh = tm
		var mat: StandardMaterial3D = main.make_material(spec[2], 2.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.6
		ring.material_override = mat
		ring.rotation.x = 0.12
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(ring)
		var t := pivot.create_tween().set_loops()
		var secs: float = absf(spec[3])
		t.tween_property(pivot, "rotation:y", TAU * signf(spec[3]), secs).from(0.0)


## Slow neon sparks drifting up through the arena (one particle system).
static func _add_sparks(main: Node3D, radius: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(radius * 0.8, 0.5, radius * 0.8)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.05
	var mat: StandardMaterial3D = main.make_material(Color(0.5, 0.9, 1.0), 4.0)
	m.material = mat
	p.mesh = m
	p.position.y = 0.3
	main.add_child(p)
