extends Node3D
## The sunset sky: a procedural sky with a low golden sun, a soft sea of clouds far below and a few
## big cloud puffs that drift past the dragon (they are recycled ahead of it, so the sky never ends).

const SEA_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 top_col : source_color = vec3(1.0, 0.8, 0.72);
uniform vec3 deep_col : source_color = vec3(0.6, 0.44, 0.68);
uniform vec3 far_col : source_color = vec3(1.0, 0.64, 0.48);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = sin(wp.x * 0.031 + sin(wp.z * 0.017) * 2.0) * sin(wp.z * 0.027 + sin(wp.x * 0.013) * 2.0);
	n = n * 0.5 + 0.5;
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	vec3 c = mix(deep_col, top_col, smoothstep(0.25, 0.85, n));
	c = mix(c, far_col, smoothstep(120.0, 520.0, d));
	ALBEDO = c;
}
"""

const PUFFS := 16
const PUFF_RANGE := 260.0

var main
var vr := false
var sea: MeshInstance3D
var puffs: Array[MeshInstance3D] = []
var rng := RandomNumberGenerator.new()


func build(vr_mode: bool) -> void:
	vr = vr_mode
	rng.randomize()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.3, 0.62)
	sky_mat.sky_horizon_color = Color(1.0, 0.62, 0.42)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(1.0, 0.6, 0.45)
	sky_mat.ground_bottom_color = Color(0.45, 0.32, 0.55)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = not vr
	e.glow_intensity = 0.6
	e.glow_hdr_threshold = 1.1
	e.ssao_enabled = false
	if not vr:
		e.fog_enabled = true
		e.fog_light_color = Color(1.0, 0.72, 0.6)
		e.fog_density = 0.0012
		e.fog_sky_affect = 0.0
	env.environment = e
	main.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-14.0, 160.0, 0.0)  # low evening sun, ahead-left of the start
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	main.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60.0, -20.0, 0.0)
	fill.light_color = Color(0.6, 0.55, 0.95)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	main.add_child(fill)

	sea = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	sea.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SEA_SHADER
	sea.material_override = sm
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	sea.position = Vector3(0, -6.0, 0)

	var puff_mesh: SphereMesh = main.sphere_mesh(1.0)
	var puff_mats: Array[StandardMaterial3D] = []
	for c in [Color(1.0, 0.86, 0.82), Color(1.0, 0.75, 0.68), Color(0.92, 0.78, 0.95)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.25
		puff_mats.append(m)
	for i in PUFFS:
		var p := MeshInstance3D.new()
		p.mesh = puff_mesh
		p.material_override = puff_mats[i % puff_mats.size()]
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_place_puff(p, Vector3(0, 40, 0), Vector3.FORWARD, true)
		puffs.append(p)


func _place_puff(p: MeshInstance3D, center: Vector3, fwd: Vector3, anywhere: bool) -> void:
	var s := rng.randf_range(9.0, 26.0)
	p.scale = Vector3(s * rng.randf_range(1.3, 2.2), s * 0.55, s * rng.randf_range(1.0, 1.6))
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.01:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var side := flat.cross(Vector3.UP)
	var along := rng.randf_range(-PUFF_RANGE, PUFF_RANGE) if anywhere else rng.randf_range(PUFF_RANGE * 0.6, PUFF_RANGE)
	var off := flat * along + side * rng.randf_range(-PUFF_RANGE, PUFF_RANGE)
	# Keep them out of the dragon's way: mostly well below or well beside the flight path.
	var y := rng.randf_range(-4.0, 22.0) if rng.randf() < 0.7 else center.y + rng.randf_range(-30.0, 30.0)
	if absf(off.dot(side)) < 45.0 and y > center.y - 25.0:
		y = center.y - rng.randf_range(28.0, 45.0)
	p.position = Vector3(center.x + off.x, maxf(y, -2.0), center.z + off.z)


## Called every frame with the dragon's position and velocity.
func follow(center: Vector3, vel: Vector3) -> void:
	sea.position = Vector3(snappedf(center.x, 50.0), -6.0, snappedf(center.z, 50.0))
	for p in puffs:
		var d := Vector2(p.position.x - center.x, p.position.z - center.z)
		if d.length() > PUFF_RANGE * 1.15:
			_place_puff(p, center, vel, false)
