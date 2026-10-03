extends RefCounted
## Builds the arena: sky, lighting, glowing grid floor, force-field wall, pillars and a distant skyline.

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 base_color = vec3(0.07, 0.08, 0.11);
uniform vec3 line_color = vec3(0.15, 0.75, 1.0);
uniform float radius = 18.0;

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = world.xz / 2.0;
	vec2 grid = abs(fract(g - 0.5) - 0.5) / fwidth(g);
	float line = 1.0 - min(min(grid.x, grid.y) / 1.5, 1.0);
	float d = length(world.xz);
	float fade = 1.0 - smoothstep(radius * 0.4, radius, d);
	float pulse = 0.5 + 0.5 * sin(d * 0.8 - TIME * 2.0);
	ALBEDO = base_color;
	ROUGHNESS = 0.35;
	METALLIC = 0.6;
	EMISSION = line_color * line * (0.25 + 0.5 * fade) * (0.7 + 0.3 * pulse);
}
"""

const WALL_SHADER := """
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;
uniform vec3 color = vec3(0.2, 0.9, 1.0);

void fragment() {
	float h = UV.y;
	float bands = 0.5 + 0.5 * sin(UV.x * 600.0 + TIME * 3.0);
	float fade = pow(1.0 - h, 2.0);
	ALBEDO = color * (0.05 + 0.12 * bands) * fade;
}
"""


static func build(main: Node3D, radius: float) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.02, 0.07)
	sky_mat.sky_horizon_color = Color(0.25, 0.1, 0.3)
	sky_mat.ground_horizon_color = Color(0.12, 0.05, 0.15)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.05
	e.ssao_enabled = true
	e.ssao_radius = 1.5
	e.ssao_intensity = 1.5
	e.fog_enabled = true
	e.fog_light_color = Color(0.18, 0.1, 0.3)
	e.fog_density = 0.012
	e.fog_sky_affect = 0.3
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	env.environment = e
	main.add_child(env)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, 30, 0)
	moon.light_color = Color(0.7, 0.75, 1.0)
	moon.light_energy = 0.7
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	main.add_child(moon)

	# Floor with an animated glowing grid.
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = radius + 1.0
	floor_mesh.bottom_radius = radius + 1.0
	floor_mesh.height = 1.0
	floor_mesh.radial_segments = 96
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = Shader.new()
	floor_mat.shader.code = FLOOR_SHADER
	floor_mat.set_shader_parameter("radius", radius)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = floor_mat
	floor_inst.position.y = -0.5
	main.add_child(floor_inst)

	# Invisible floor collision (layer 4) so bullets aimed down stop at the ground.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 8
	floor_body.collision_mask = 0
	var fcs := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(radius * 3.0, 1.0, radius * 3.0)
	fcs.shape = fshape
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	main.add_child(floor_body)

	# Edge ring and a shimmering force-field wall.
	var edge := TorusMesh.new()
	edge.inner_radius = radius - 0.15
	edge.outer_radius = radius + 0.15
	edge.rings = 96
	var edge_inst := MeshInstance3D.new()
	edge_inst.mesh = edge
	edge_inst.material_override = main.make_material(Color(0.2, 0.9, 1.0), 3.0)
	edge_inst.position.y = 0.05
	main.add_child(edge_inst)

	var wall := CylinderMesh.new()
	wall.top_radius = radius
	wall.bottom_radius = radius
	wall.height = 3.0
	wall.cap_top = false
	wall.cap_bottom = false
	wall.radial_segments = 96
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = Shader.new()
	wall_mat.shader.code = WALL_SHADER
	var wall_inst := MeshInstance3D.new()
	wall_inst.mesh = wall
	wall_inst.material_override = wall_mat
	wall_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall_inst.position.y = 1.5
	main.add_child(wall_inst)

	var pillar_colors := [Color(1.0, 0.3, 0.6), Color(0.3, 1.0, 0.6), Color(1.0, 0.6, 0.2), Color(0.6, 0.4, 1.0)]
	var spots := [Vector3(-7, 0, -6), Vector3(7, 0, -6), Vector3(-7, 0, 6), Vector3(7, 0, 6)]
	for i in spots.size():
		_add_pillar(main, spots[i], pillar_colors[i])

	_add_skyline(main, radius)


static func _add_pillar(main: Node3D, pos: Vector3, accent: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxMesh.new()
	box.size = Vector3(2, 3, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	var mat: StandardMaterial3D = main.make_material(Color(0.22, 0.24, 0.32), 0.0)
	mat.metallic = 0.5
	mat.roughness = 0.4
	mi.material_override = mat
	mi.position.y = 1.5
	body.add_child(mi)
	# Glowing trim bands.
	for y in [0.15, 2.9]:
		var trim := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(2.08, 0.12, 2.08)
		trim.mesh = tb
		trim.material_override = main.make_material(accent, 4.0)
		trim.position.y = y
		body.add_child(trim)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	cs.shape = shape
	cs.position.y = 1.5
	body.add_child(cs)
	var light := OmniLight3D.new()
	light.light_color = accent
	light.light_energy = 1.5
	light.omni_range = 7.0
	light.position.y = 3.4
	body.add_child(light)
	body.position = pos
	main.add_child(body)


static func _add_skyline(main: Node3D, radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dark: StandardMaterial3D = main.make_material(Color(0.05, 0.05, 0.08), 0.0)
	var window_colors := [Color(0.3, 0.8, 1.0), Color(1.0, 0.4, 0.7), Color(0.9, 0.7, 0.3)]
	for i in 46:
		var angle := TAU * i / 46.0 + rng.randf_range(-0.05, 0.05)
		var dist := rng.randf_range(radius + 14.0, radius + 40.0)
		var h := rng.randf_range(6.0, 28.0)
		var w := rng.randf_range(3.0, 7.0)
		var tower := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, w)
		tower.mesh = bm
		tower.material_override = dark
		tower.position = Vector3(cos(angle) * dist, h / 2.0 - 0.5, sin(angle) * dist)
		tower.rotation.y = rng.randf() * TAU
		tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(tower)
		# A couple of glowing stripes per tower.
		for k in rng.randi_range(1, 3):
			var stripe := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(w + 0.05, 0.25, w + 0.05)
			stripe.mesh = sm
			stripe.material_override = main.make_material(window_colors[rng.randi() % window_colors.size()], 3.0)
			stripe.position = Vector3(0, rng.randf_range(-h * 0.4, h * 0.45), 0)
			stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tower.add_child(stripe)
