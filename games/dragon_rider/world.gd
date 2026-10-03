extends Node3D
## The sky: a procedural sky with a low sun, a soft sea of clouds far below and big cloud puffs that
## drift past the dragon (recycled ahead of it, so the sky never ends). Each level has its own palette
## (sunset, morning, golden afternoon, storm, night with stars and a moon, dawn), plus a flock of
## birds and hot-air balloons far off. Puffs and birds are MultiMeshes (one draw call each).

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
const BIRDS := 9
const HOT_AIR := 3
## Palettes: sky top / horizon / ground, sun colour + energy + pitch, sea colours, cloud tint, ambient.
const PALETTES := {
	"sunset": {"top": Color(0.28, 0.3, 0.62), "hor": Color(1.0, 0.62, 0.42), "gh": Color(1.0, 0.6, 0.45), "gb": Color(0.45, 0.32, 0.55),
		"sun": Color(1.0, 0.78, 0.55), "sun_e": 1.25, "sun_x": -14.0, "sea_top": Color(1.0, 0.8, 0.72), "sea_deep": Color(0.6, 0.44, 0.68),
		"sea_far": Color(1.0, 0.64, 0.48), "cloud": Color(1.0, 0.84, 0.8), "amb": 1.0, "fog": Color(1.0, 0.72, 0.6)},
	"morning": {"top": Color(0.3, 0.52, 0.95), "hor": Color(0.82, 0.9, 1.0), "gh": Color(0.8, 0.86, 0.96), "gb": Color(0.5, 0.56, 0.78),
		"sun": Color(1.0, 0.97, 0.9), "sun_e": 1.2, "sun_x": -38.0, "sea_top": Color(0.97, 0.98, 1.0), "sea_deep": Color(0.62, 0.7, 0.9),
		"sea_far": Color(0.85, 0.9, 1.0), "cloud": Color(1.0, 1.0, 1.0), "amb": 1.0, "fog": Color(0.85, 0.9, 1.0)},
	"golden": {"top": Color(0.38, 0.48, 0.9), "hor": Color(1.0, 0.84, 0.55), "gh": Color(1.0, 0.82, 0.6), "gb": Color(0.6, 0.5, 0.55),
		"sun": Color(1.0, 0.86, 0.6), "sun_e": 1.3, "sun_x": -24.0, "sea_top": Color(1.0, 0.93, 0.76), "sea_deep": Color(0.76, 0.6, 0.6),
		"sea_far": Color(1.0, 0.86, 0.6), "cloud": Color(1.0, 0.94, 0.82), "amb": 1.0, "fog": Color(1.0, 0.86, 0.66)},
	"storm": {"top": Color(0.14, 0.12, 0.26), "hor": Color(0.5, 0.36, 0.56), "gh": Color(0.45, 0.35, 0.5), "gb": Color(0.15, 0.12, 0.2),
		"sun": Color(0.85, 0.75, 1.0), "sun_e": 0.95, "sun_x": -30.0, "sea_top": Color(0.56, 0.5, 0.66), "sea_deep": Color(0.24, 0.2, 0.34),
		"sea_far": Color(0.45, 0.38, 0.56), "cloud": Color(0.62, 0.58, 0.72), "amb": 0.85, "fog": Color(0.45, 0.38, 0.55)},
	"night": {"top": Color(0.02, 0.03, 0.1), "hor": Color(0.16, 0.16, 0.36), "gh": Color(0.12, 0.12, 0.28), "gb": Color(0.03, 0.03, 0.08),
		"sun": Color(0.7, 0.8, 1.0), "sun_e": 0.7, "sun_x": -40.0, "sea_top": Color(0.36, 0.4, 0.6), "sea_deep": Color(0.1, 0.12, 0.25),
		"sea_far": Color(0.2, 0.22, 0.42), "cloud": Color(0.55, 0.6, 0.82), "amb": 1.1, "fog": Color(0.18, 0.2, 0.4), "stars": true},
	"dawn": {"top": Color(0.34, 0.34, 0.7), "hor": Color(1.0, 0.7, 0.76), "gh": Color(1.0, 0.72, 0.78), "gb": Color(0.45, 0.38, 0.6),
		"sun": Color(1.0, 0.82, 0.8), "sun_e": 1.15, "sun_x": -10.0, "sea_top": Color(1.0, 0.86, 0.9), "sea_deep": Color(0.6, 0.5, 0.72),
		"sea_far": Color(1.0, 0.76, 0.8), "cloud": Color(1.0, 0.88, 0.92), "amb": 1.0, "fog": Color(1.0, 0.75, 0.78)},
}

var main
var vr := false
var sea: MeshInstance3D
var sea_mat: ShaderMaterial
var puff_mm: MultiMesh
var puff_xf: Array = []       # per puff: Transform3D (local scale + position in world)
var rng := RandomNumberGenerator.new()
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var puff_mat: StandardMaterial3D
var bird_mm: MultiMesh
var bird_base: Vector3 = Vector3.ZERO
var bird_t := 0.0
var star_field: MultiMeshInstance3D
var moon: MeshInstance3D
var hot_air: Array = []       # Node3D balloons far off
var palette_name := ""


func build(vr_mode: bool) -> void:
	vr = vr_mode
	rng.randomize()
	var wenv := WorldEnvironment.new()
	var e := Environment.new()
	env = e
	sky_mat = ProceduralSkyMaterial.new()
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
	wenv.environment = e
	main.add_child(wenv)

	sun = DirectionalLight3D.new()
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
	sea_mat = sm
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	sea.position = Vector3(0, -6.0, 0)

	# Cloud puffs: one MultiMesh (instance colours tint them).
	puff_mat = StandardMaterial3D.new()
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.roughness = 1.0
	puff_mat.emission_enabled = true
	puff_mat.emission = Color(1.0, 0.86, 0.82)
	puff_mat.emission_energy_multiplier = 0.22
	var pm2 := SphereMesh.new()
	pm2.radius = 1.0
	pm2.height = 2.0
	pm2.radial_segments = 14
	pm2.rings = 7
	pm2.material = puff_mat
	puff_mm = MultiMesh.new()
	puff_mm.transform_format = MultiMesh.TRANSFORM_3D
	puff_mm.use_colors = true
	puff_mm.mesh = pm2
	puff_mm.instance_count = PUFFS
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = puff_mm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pmi)
	for i in PUFFS:
		puff_xf.append(Transform3D())
		_place_puff(i, Vector3(0, 40, 0), Vector3.FORWARD, true)
	_build_birds()
	_build_hot_air()
	set_palette("sunset")


## Switch the sky's mood (both machines, from the level number).
func set_palette(pname: String) -> void:
	if pname == palette_name or not PALETTES.has(pname):
		return
	palette_name = pname
	var p: Dictionary = PALETTES[pname]
	sky_mat.sky_top_color = p.top
	sky_mat.sky_horizon_color = p.hor
	sky_mat.ground_horizon_color = p.gh
	sky_mat.ground_bottom_color = p.gb
	sun.light_color = p.sun
	sun.light_energy = float(p.sun_e)
	sun.rotation_degrees = Vector3(float(p.sun_x), 160.0, 0.0)
	env.ambient_light_energy = float(p.amb)
	if env.fog_enabled:
		env.fog_light_color = p.fog
	sea_mat.set_shader_parameter("top_col", p.sea_top)
	sea_mat.set_shader_parameter("deep_col", p.sea_deep)
	sea_mat.set_shader_parameter("far_col", p.sea_far)
	var cc: Color = p.cloud
	puff_mat.emission = cc
	for i in PUFFS:
		puff_mm.set_instance_color(i, cc.lerp(Color(1, 1, 1), rng.randf_range(0.0, 0.25)).darkened(rng.randf_range(0.0, 0.12)))
	var night: bool = p.get("stars", false)
	if night:
		_ensure_night()
	if star_field != null:
		star_field.visible = night
		moon.visible = night


func _ensure_night() -> void:
	if star_field != null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bx := BoxMesh.new()
	bx.size = Vector3.ONE * 2.4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.97, 0.88)
	bx.material = m
	mm.mesh = bx
	mm.instance_count = 220
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for i in 220:
		var a := r.randf() * TAU
		var el := r.randf_range(0.06, 1.4)
		var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * r.randf_range(0.5, 1.5)), dir * 1100.0))
	star_field = MultiMeshInstance3D.new()
	star_field.multimesh = mm
	star_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(star_field)
	moon = MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 42.0
	ms.height = 84.0
	ms.radial_segments = 20
	ms.rings = 10
	moon.mesh = ms
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(1.0, 0.97, 0.85)
	moon.material_override = mmat
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)


## A V-shaped flock that circles near the route (recycled ahead of the dragon).
func _build_birds() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var pts := [Vector3(0, 0, -0.2), Vector3(side * 1.1, 0.25, 0.25), Vector3(0, 0, 0.35)]
		for v in pts:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var bm := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.3)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.surface_set_material(0, mat)
	bird_mm = MultiMesh.new()
	bird_mm.transform_format = MultiMesh.TRANSFORM_3D
	bird_mm.mesh = bm
	bird_mm.instance_count = BIRDS
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bird_mm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)


## Striped hot-air balloons drifting far away (pure scenery).
func _build_hot_air() -> void:
	var cols: Array[Color] = [Color(1.0, 0.4, 0.35), Color(0.4, 0.75, 1.0), Color(1.0, 0.85, 0.3)]
	for i in HOT_AIR:
		var n := Node3D.new()
		add_child(n)
		var env_mesh := SphereMesh.new()
		env_mesh.radius = 6.0
		env_mesh.height = 14.0
		env_mesh.radial_segments = 12
		env_mesh.rings = 6
		var b := MeshInstance3D.new()
		b.mesh = env_mesh
		b.material_override = main.color_mat(cols[i], 0.25)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(b)
		var basket := MeshInstance3D.new()
		basket.mesh = main.box_mesh(Vector3(2.2, 1.6, 2.2))
		basket.material_override = main.color_mat(Color(0.55, 0.36, 0.22), 0.0)
		basket.position = Vector3(0, -10.5, 0)
		basket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(basket)
		n.position = Vector3(rng.randf_range(-300, 300), rng.randf_range(30, 90), rng.randf_range(-300, 300))
		hot_air.append(n)


func _place_puff(i: int, center: Vector3, fwd: Vector3, anywhere: bool) -> void:
	var s := rng.randf_range(9.0, 26.0)
	var scl := Vector3(s * rng.randf_range(1.3, 2.2), s * 0.55, s * rng.randf_range(1.0, 1.6))
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
	var xf := Transform3D(Basis().scaled(scl), Vector3(center.x + off.x, maxf(y, -2.0), center.z + off.z))
	puff_xf[i] = xf
	puff_mm.set_instance_transform(i, xf)


## Called every frame with the dragon's position and velocity.
func follow(center: Vector3, vel: Vector3) -> void:
	sea.position = Vector3(snappedf(center.x, 50.0), -6.0, snappedf(center.z, 50.0))
	for i in PUFFS:
		var xf: Transform3D = puff_xf[i]
		var d := Vector2(xf.origin.x - center.x, xf.origin.z - center.z)
		if d.length() > PUFF_RANGE * 1.15:
			_place_puff(i, center, vel, false)
	var dt := get_process_delta_time()
	bird_t += dt
	# The flock: re-placed ahead and to the side whenever it falls far behind.
	if bird_base == Vector3.ZERO or Vector2(bird_base.x - center.x, bird_base.z - center.z).length() > 200.0:
		var fl := Vector3(vel.x, 0.0, vel.z)
		fl = fl.normalized() if fl.length() > 0.1 else Vector3.FORWARD
		bird_base = center + fl * 140.0 + fl.cross(Vector3.UP) * rng.randf_range(-60.0, 60.0)
		bird_base.y = center.y + rng.randf_range(8.0, 25.0)
	for i in BIRDS:
		var a := bird_t * 0.35 + i * 0.35
		var r := 16.0 + (i % 3) * 3.0
		var pos := bird_base + Vector3(cos(a) * r, sin(bird_t * 0.8 + i) * 1.5 + (i % 2) * 2.0, sin(a) * r)
		var fwd := Vector3(-sin(a), 0.0, cos(a))
		var flap := 1.0 + sin(bird_t * 8.0 + i * 1.3) * 0.5
		bird_mm.set_instance_transform(i, Transform3D(Basis.looking_at(fwd, Vector3.UP).scaled(Vector3(flap, 1.0, 1.0) * 1.6), pos))
	for n in hot_air:
		var hb: Node3D = n
		hb.position += Vector3(1.2, 0.0, 0.6) * dt
		hb.rotation.y += dt * 0.05
		var dd := Vector2(hb.position.x - center.x, hb.position.z - center.z)
		if dd.length() > 420.0:
			var fl2 := Vector3(vel.x, 0.0, vel.z)
			fl2 = fl2.normalized() if fl2.length() > 0.1 else Vector3.FORWARD
			var sd := fl2.cross(Vector3.UP) * (rng.randf_range(120.0, 260.0) * (-1.0 if rng.randf() < 0.5 else 1.0))
			hb.position = center + fl2 * rng.randf_range(250.0, 380.0) + sd
			hb.position.y = rng.randf_range(30.0, 95.0)
	if moon != null and moon.visible:
		moon.global_position = center + Vector3(-500.0, 420.0, -620.0)
		if star_field != null:
			star_field.global_position = center
