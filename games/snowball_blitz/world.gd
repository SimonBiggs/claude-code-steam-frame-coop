extends RefCounted
## Builds the snowy village square at dusk: sky, warm lamps, pine trees, cottages, fairy lights
## and falling snow. Everything is procedural and batched (MultiMesh) to keep draw calls low.

const BULB_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
varying float twinkle;
void vertex() {
	twinkle = 0.55 + 0.45 * sin(TIME * 2.6 + float(INSTANCE_ID) * 1.93);
}
void fragment() {
	ALBEDO = COLOR.rgb * (1.2 + 1.8 * twinkle);
}
"""

const SNOW_GROUND_SHADER := """
shader_type spatial;
uniform vec3 snow : source_color = vec3(0.86, 0.9, 1.0);
uniform vec3 shade : source_color = vec3(0.62, 0.68, 0.86);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = noise(world.xz * 0.35) * 0.6 + noise(world.xz * 1.7) * 0.4;
	ALBEDO = mix(shade, snow, 0.55 + 0.45 * n);
	ROUGHNESS = 0.85;
	// Tiny sparkles in the snow.
	float s = step(0.985, hash(floor(world.xz * 18.0)));
	EMISSION = vec3(0.7, 0.8, 1.0) * s * 0.6;
}
"""

const BULB_COLORS := [Color(1.0, 0.25, 0.2), Color(1.0, 0.8, 0.25), Color(0.3, 0.9, 0.45), Color(0.35, 0.6, 1.0), Color(1.0, 0.5, 0.85)]


static func build(main: Node3D, radius: float, vr: bool) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.12, 0.32)
	sky_mat.sky_horizon_color = Color(0.95, 0.55, 0.45)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.55, 0.45, 0.6)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.3)
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.9
	if not vr:
		e.fog_enabled = true
		e.fog_light_color = Color(0.55, 0.45, 0.65)
		e.fog_density = 0.008
		e.fog_sky_affect = 0.15
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	env.environment = e
	main.add_child(env)

	# Low dusk sun (warm) and a cool moon fill.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-16, -40, 0)
	sun.light_color = Color(1.0, 0.7, 0.5)
	sun.light_energy = 0.55
	sun.shadow_enabled = not vr
	sun.directional_shadow_max_distance = 45.0
	main.add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-60, 140, 0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.3
	main.add_child(moon)

	# Snowy ground.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	ground.mesh = pm
	var gmat := ShaderMaterial.new()
	gmat.shader = Shader.new()
	gmat.shader.code = SNOW_GROUND_SHADER
	ground.material_override = gmat
	main.add_child(ground)

	# Cobbled plaza ring edge so the play area reads clearly.
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius + 0.2
	tm.outer_radius = radius + 0.7
	tm.rings = 64
	tm.ring_segments = 6
	edge.mesh = tm
	edge.material_override = main.make_material(Color(0.45, 0.4, 0.45), 0.0)
	edge.scale.y = 0.25
	main.add_child(edge)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	_add_trees(main, radius, rng)
	_add_cottages(main, radius, rng)
	var posts := _add_lamps(main, radius, vr)
	_add_fairy_lights(main, posts, rng)
	_add_snowfall(main, vr)


static func _add_trees(main: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	var spots: Array[Transform3D] = []
	for i in 46:
		var a := rng.randf() * TAU
		var d := rng.randf_range(radius + 2.5, radius + 16.0)
		var s := rng.randf_range(0.8, 1.6)
		spots.append(Transform3D(Basis().scaled(Vector3.ONE * s).rotated(Vector3.UP, rng.randf() * TAU), Vector3(cos(a) * d, 0, sin(a) * d)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.6
	cone.radial_segments = 10
	cone.rings = 1
	var tiers := _multimesh(main, cone, spots.size() * 3, main.make_material(Color(0.12, 0.32, 0.22), 0.0))
	var caps := _multimesh(main, cone, spots.size(), main.make_material(Color(0.92, 0.95, 1.0), 0.0))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.22
	trunk.height = 0.9
	trunk.radial_segments = 6
	var trunks := _multimesh(main, trunk, spots.size(), main.make_material(Color(0.35, 0.22, 0.14), 0.0))
	for i in spots.size():
		var t: Transform3D = spots[i]
		trunks.set_instance_transform(i, t * Transform3D(Basis(), Vector3(0, 0.45, 0)))
		for k in 3:
			var w := 1.5 - k * 0.38
			tiers.set_instance_transform(i * 3 + k, t * Transform3D(Basis().scaled(Vector3(w, 1.0, w)), Vector3(0, 1.4 + k * 0.95, 0)))
		caps.set_instance_transform(i, t * Transform3D(Basis().scaled(Vector3(0.45, 0.45, 0.45)), Vector3(0, 3.9, 0)))


static func _add_cottages(main: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	var wall_colors := [Color(0.75, 0.3, 0.25), Color(0.92, 0.85, 0.7), Color(0.4, 0.55, 0.75), Color(0.6, 0.45, 0.3)]
	var window_mat: StandardMaterial3D = main.make_material(Color(1.0, 0.72, 0.35), 3.0)
	var roof_mat: StandardMaterial3D = main.make_material(Color(0.95, 0.97, 1.0), 0.0)
	var count := 9
	for i in count:
		var a := TAU * (i + 0.5) / count + rng.randf_range(-0.12, 0.12)
		var d := radius + rng.randf_range(9.0, 13.0)
		var house := Node3D.new()
		house.position = Vector3(cos(a) * d, 0, sin(a) * d)
		main.add_child(house)
		house.look_at(Vector3(0, 0, 0), Vector3.UP)
		var w := rng.randf_range(4.0, 6.0)
		var h := rng.randf_range(2.8, 3.8)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, 4.0)
		body.mesh = bm
		body.material_override = main.make_material(wall_colors[i % wall_colors.size()], 0.0)
		body.position.y = h / 2.0
		house.add_child(body)
		var roof := MeshInstance3D.new()
		var rm := PrismMesh.new()
		rm.size = Vector3(w + 0.6, 1.8, 4.6)
		roof.mesh = rm
		roof.material_override = roof_mat
		roof.position.y = h + 0.9
		house.add_child(roof)
		var win := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(w * 0.7, 0.8, 0.1)
		win.mesh = wm
		win.material_override = window_mat
		win.position = Vector3(0, h * 0.55, -2.0)
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		house.add_child(win)
		var chimney := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.6, 1.4, 0.6)
		chimney.mesh = cm
		chimney.material_override = main.make_material(Color(0.5, 0.3, 0.25), 0.0)
		chimney.position = Vector3(w * 0.28, h + 1.4, 0.8)
		house.add_child(chimney)


static func _add_lamps(main: Node3D, radius: float, vr: bool) -> Array[Vector3]:
	var tops: Array[Vector3] = []
	var post_mat: StandardMaterial3D = main.make_material(Color(0.15, 0.15, 0.18), 0.0)
	var lamp_mat: StandardMaterial3D = main.make_material(Color(1.0, 0.75, 0.4), 4.0)
	var count := 8
	for i in count:
		var a := TAU * i / count + PI / count
		var pos := Vector3(cos(a), 0, sin(a)) * (radius + 1.4)
		var post := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.07
		pc.bottom_radius = 0.1
		pc.height = 3.6
		pc.radial_segments = 6
		post.mesh = pc
		post.material_override = post_mat
		post.position = pos + Vector3.UP * 1.8
		main.add_child(post)
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.22
		lm.height = 0.44
		lm.radial_segments = 10
		lm.rings = 5
		lamp.mesh = lm
		lamp.material_override = lamp_mat
		lamp.position = pos + Vector3.UP * 3.7
		main.add_child(lamp)
		tops.append(pos + Vector3.UP * 3.6)
		# Only every other lamp casts real light (the mobile renderer has a per-object light budget).
		if i % 2 == 0 and not (vr and i % 4 != 0):
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.7, 0.4)
			light.light_energy = 2.2
			light.omni_range = 11.0
			light.position = pos + Vector3.UP * 3.4
			main.add_child(light)
	# A warm glow in the middle of the fort, like a little campfire lantern.
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.6, 0.35)
	fire.light_energy = 1.4
	fire.omni_range = 9.0
	fire.position = Vector3(0, 2.6, 0)
	main.add_child(fire)
	return tops


## Strings of twinkling bulbs sagging between the lamp posts (one MultiMesh, one draw call).
static func _add_fairy_lights(main: Node3D, tops: Array[Vector3], rng: RandomNumberGenerator) -> void:
	var per := 22
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	bulb.radial_segments = 6
	bulb.rings = 3
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = BULB_SHADER
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bulb
	mm.instance_count = tops.size() * per
	for i in tops.size():
		var a: Vector3 = tops[i]
		var b: Vector3 = tops[(i + 1) % tops.size()]
		for k in per:
			var t := (k + 0.5) / per
			var p := a.lerp(b, t)
			p.y -= sin(t * PI) * 1.4  # sag
			var idx := i * per + k
			mm.set_instance_transform(idx, Transform3D(Basis(), p))
			var c: Color = BULB_COLORS[(idx + rng.randi() % 2) % BULB_COLORS.size()]
			mm.set_instance_color(idx, c)
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(inst)


static func _add_snowfall(main: Node3D, vr: bool) -> void:
	var p := CPUParticles3D.new()
	p.amount = 300 if vr else 700
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(28, 0.5, 28)
	p.direction = Vector3(0.2, -1, 0.1)
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -0.25, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	p.position = Vector3(0, 14, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(p)
	p.emitting = true


static func _multimesh(main: Node3D, mesh: Mesh, count: int, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	main.add_child(inst)
	return mm
