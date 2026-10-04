extends Node3D
## The concert: a stage with a disco floor, an LED equalizer wall, chase lights along the stage lip,
## swinging light beams, speaker stacks, amps and monitors, a big waving crowd and the guitarists'
## avatars. The drummer stands at the back on a riser (DRUM_SPOT, facing -Z towards the crowd); the
## guitarists stand in front of them; the TV cameras are in the crowd.
## Cheap on the Steam Frame: the static set is ONE merged mesh; the crowd (120 fans with waving arms
## and glow sticks), the LED wall and the chase lights are MultiMeshes animated in shaders from a few
## uniforms (beat, energy, star power) - no per-frame CPU work per fan or bulb.

const MeshKit := preload("res://games/rhythm_band/mesh_kit.gd")

const STAGE_Y := 0.8
const DRUM_SPOT := Vector3(0.0, 0.8, 1.2)
const AVATAR_X: Array[float] = [-1.15, 1.15, -2.3, 2.3, -3.3, 3.3]
const CROWD_COLS := 24
const CROWD_ROWS := 5
const TILE_COLS := 9
const TILE_ROWS := 4
const LED_COLS := 26
const LED_ROWS := 7
const LIP_BULBS := 34
const BEAM_COLORS: Array[Color] = [Color(1.0, 0.3, 0.5), Color(0.3, 0.7, 1.0), Color(1.0, 0.85, 0.2),
	Color(0.4, 1.0, 0.5), Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.2)]
const HAIR: Array[Color] = [Color(0.95, 0.8, 0.3), Color(0.35, 0.2, 0.1), Color(0.1, 0.08, 0.08), Color(0.9, 0.4, 0.15),
	Color(0.55, 0.3, 0.75), Color(0.2, 0.55, 0.9)]
const CROWD_SHADER := """
shader_type spatial;
uniform float beat = 0.0;
uniform float energy = 0.5;
uniform float star = 0.0;
varying vec3 shirt;
varying float glow;
void vertex() {
	float ph = INSTANCE_CUSTOM.a;
	shirt = INSTANCE_CUSTOM.rgb;
	float together = clamp(energy * 0.85 + star, 0.0, 1.0);
	float hop = pow(abs(sin(3.14159 * (beat + ph * (1.0 - together)))), 2.0) * (0.02 + 0.3 * energy * energy + 0.15 * star);
	if (UV.x > 0.5) {
		float side = UV.x > 1.5 ? 1.0 : -1.0;
		float raise = clamp(energy * 1.5 - 0.25 + star, 0.0, 1.0);
		float a = -side * 2.6 * (1.0 - raise);
		a += side * 0.45 * raise * sin(TIME * (2.0 + 3.0 * energy) + ph * 6.28 + side);
		vec3 sh = vec3(0.19 * side, 0.92, 0.0);
		vec3 p = VERTEX - sh;
		VERTEX = sh + vec3(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a), p.z);
	}
	VERTEX.y += hop;
	glow = (COLOR.a > 0.25 && COLOR.a < 0.75) ? 1.0 : 0.0;
}
void fragment() {
	vec3 c = COLOR.a < 0.25 ? shirt : COLOR.rgb;
	ALBEDO = c * (1.0 - glow);
	EMISSION = COLOR.rgb * glow * 2.5;
	ROUGHNESS = 0.85;
}
"""
const LED_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float beat = 0.0;
uniform float energy = 0.5;
uniform float star = 0.0;
varying vec4 cell;
void vertex() {
	cell = INSTANCE_CUSTOM;
}
vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
void fragment() {
	float b = fract(beat);
	float pulse = exp(-b * 4.0);
	float wave = 0.5 + 0.5 * sin(cell.x * 19.0 + floor(beat) * 1.7) * cos(cell.x * 7.0 - floor(beat * 0.5) * 2.3);
	float h = 0.12 + (0.25 + 0.6 * energy) * wave * (0.55 + 0.45 * pulse) + 0.3 * star;
	float on = step(cell.y, h);
	vec3 c = mix(hue(fract(cell.x * 0.8 + beat * 0.03)), vec3(1.0, 0.8, 0.25), star);
	float border = step(0.1, UV.x) * step(UV.x, 0.9) * step(0.1, UV.y) * step(UV.y, 0.9);
	ALBEDO = c * (0.06 + on * (0.8 + 0.6 * pulse)) * border;
}
"""
const LIP_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float beat = 0.0;
uniform float star = 0.0;
uniform float count = 34.0;
varying float k;
void vertex() {
	k = float(INSTANCE_ID) / count;
}
vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
void fragment() {
	float chase = fract(beat * 0.5 - k * 4.0);
	float on = 0.25 + 0.75 * step(chase, 0.3);
	ALBEDO = mix(hue(fract(k + beat * 0.0625)), vec3(1.0, 0.85, 0.3), star) * on * 1.4;
}
"""

var main
var t := 0.0
var beat_flash := 0.0
var bar_n := 0
var beat_n := 0
var star_k := 0.0
var tiles_mm: MultiMesh
var crowd_mats: Array[ShaderMaterial] = []
var led_mat: ShaderMaterial
var lip_mat: ShaderMaterial
var beam_pivots: Array[Node3D] = []
var beam_mats: Array[StandardMaterial3D] = []
var speakers: Array[MeshInstance3D] = []
var key_light: OmniLight3D
var avatars: Array[Node3D] = []
var guitars: Array[Node3D] = []
var guitar_mats: Array[StandardMaterial3D] = []
var strum_arms: Array[Node3D] = []
var heads: Array[Node3D] = []
var tags: Array[Label3D] = []
var strum_t := PackedFloat32Array()
var song_label: Label3D
var stars_root: Node3D
var star_meshes: Array[MeshInstance3D] = []
var stars_shown := 0
var star_anim := 0.0


func build() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.04, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.65, 0.9)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(160.0), 0.0)
	sun.light_energy = 0.55
	sun.shadow_enabled = false
	add_child(sun)
	key_light = OmniLight3D.new()
	key_light.position = Vector3(0.0, 4.0, -1.5)
	key_light.omni_range = 9.0
	key_light.light_energy = 1.2
	add_child(key_light)
	_build_set()
	var sign_l := Label3D.new()
	sign_l.text = "RHYTHM BAND"
	sign_l.font_size = 200
	sign_l.pixel_size = 0.004
	sign_l.outline_size = 30
	sign_l.modulate = Color(1.0, 0.85, 0.3)
	sign_l.position = Vector3(0.0, 4.6, 3.18)
	sign_l.rotation.y = PI
	add_child(sign_l)
	song_label = Label3D.new()
	song_label.font_size = 96
	song_label.pixel_size = 0.004
	song_label.outline_size = 20
	song_label.modulate = Color(0.6, 0.9, 1.0)
	song_label.position = Vector3(0.0, 3.85, 3.18)
	song_label.rotation.y = PI
	add_child(song_label)
	_build_floor()
	_build_led_wall()
	_build_lip_lights()
	_build_beams()
	_build_crowd()
	for i in AVATAR_X.size():
		_build_avatar(i + 1)
	strum_t.resize(7)
	_build_stars()


## Everything that never moves, merged into one mesh: ground, stage, riser, backdrop, truss towers,
## speaker stacks, amps, monitor wedges, mic stands and cables.
func _build_set() -> void:
	var parts: Array = []
	var dark := Color(0.08, 0.08, 0.1)
	var metal := Color(0.35, 0.35, 0.4)
	parts.append([MeshKit.box(Vector3(30, 0.02, 30)), MeshKit.at(Vector3(0, -0.01, 0)), Color(0.12, 0.1, 0.16)])
	parts.append([MeshKit.box(Vector3(9.4, STAGE_Y, 5.6)), MeshKit.at(Vector3(0.0, STAGE_Y * 0.5, 0.45)), Color(0.18, 0.16, 0.24)])
	for k in 5:
		parts.append([MeshKit.box(Vector3(9.4, 0.02, 0.03)), MeshKit.at(Vector3(0.0, STAGE_Y * (0.2 + k * 0.15), -2.34)), Color(0.24, 0.2, 0.32)])
	parts.append([MeshKit.box(Vector3(2.2, 0.3, 1.8)), MeshKit.at(Vector3(DRUM_SPOT.x, STAGE_Y + 0.15, DRUM_SPOT.z + 0.1)), Color(0.22, 0.14, 0.3)])
	parts.append([MeshKit.box(Vector3(2.0, 0.02, 1.6)), MeshKit.at(Vector3(DRUM_SPOT.x, STAGE_Y + 0.31, DRUM_SPOT.z + 0.1)), Color(0.5, 0.15, 0.2)])
	parts.append([MeshKit.box(Vector3(10.0, 5.0, 0.2)), MeshKit.at(Vector3(0.0, 3.3, 3.3)), Color(0.12, 0.08, 0.22)])
	# Truss: a top beam over the stage and towers at the sides.
	parts.append([MeshKit.box(Vector3(10.0, 0.18, 0.18)), MeshKit.at(Vector3(0.0, 5.2, -0.6)), metal])
	parts.append([MeshKit.box(Vector3(10.0, 0.08, 0.08)), MeshKit.at(Vector3(0.0, 5.42, -0.6)), metal])
	for sx in [-4.9, 4.9]:
		var sxf: float = sx
		parts.append([MeshKit.box(Vector3(0.2, 5.3, 0.2)), MeshKit.at(Vector3(sxf, 2.65, -0.6)), metal])
		for k in 8:
			parts.append([MeshKit.box(Vector3(0.04, 0.7, 0.04)), MeshKit.at(Vector3(sxf, 0.5 + k * 0.62, -0.6), Vector3.ONE, Vector3(0, 0, 0.7 if k % 2 == 0 else -0.7)), metal])
	# Speaker stacks (cones are separate: they pump on the beat).
	for sx in [-4.3, 4.3]:
		var sxf2: float = sx
		parts.append([MeshKit.box(Vector3(0.9, 2.2, 0.8)), MeshKit.at(Vector3(sxf2, STAGE_Y + 1.1, -1.6)), dark])
		parts.append([MeshKit.box(Vector3(0.95, 0.05, 0.85)), MeshKit.at(Vector3(sxf2, STAGE_Y + 2.22, -1.6)), metal])
	# Amps behind the guitarists, monitor wedges at the front, mic stands and cables.
	for i in AVATAR_X.size():
		var x := AVATAR_X[i]
		var z := -0.7 - absf(x) * 0.1
		parts.append([MeshKit.box(Vector3(0.6, 0.5, 0.3)), MeshKit.at(Vector3(x * 1.05, STAGE_Y + 0.25, z + 0.75)), Color(0.15, 0.12, 0.1)])
		parts.append([MeshKit.box(Vector3(0.5, 0.32, 0.02)), MeshKit.at(Vector3(x * 1.05, STAGE_Y + 0.27, z + 0.59)), Color(0.3, 0.28, 0.25)])
		parts.append([MeshKit.box(Vector3(0.62, 0.08, 0.32)), MeshKit.at(Vector3(x * 1.05, STAGE_Y + 0.54, z + 0.75)), Color(0.85, 0.75, 0.5)])
		parts.append([MeshKit.box(Vector3(0.55, 0.22, 0.35)), MeshKit.at(Vector3(x, STAGE_Y + 0.1, z - 0.75), Vector3.ONE, Vector3(-0.5, 0, 0)), dark])
		parts.append([MeshKit.cyl(0.012, 0.012, 1.25, 6), MeshKit.at(Vector3(x + 0.05, STAGE_Y + 0.62, z - 0.42)), metal])
		parts.append([MeshKit.cyl(0.12, 0.14, 0.02, 10), MeshKit.at(Vector3(x + 0.05, STAGE_Y + 0.01, z - 0.42)), metal])
		parts.append([MeshKit.sphere(0.03, 8), MeshKit.at(Vector3(x + 0.05, STAGE_Y + 1.26, z - 0.42), Vector3(1, 1.4, 1)), Color(0.2, 0.2, 0.22)])
		parts.append([MeshKit.box(Vector3(0.02, 0.01, 1.2)), MeshKit.at(Vector3(x * 1.03, STAGE_Y + 0.005, z + 0.1), Vector3.ONE, Vector3(0, 0.3, 0)), Color(0.05, 0.05, 0.05)])
	# The band's bass drum, standing on the riser floor well in front of the drummer: at eye height it
	# blocked a seated player's view of the notes (Simon).
	var kick := Vector3(DRUM_SPOT.x, STAGE_Y + 0.32, DRUM_SPOT.z - 1.0)
	parts.append([MeshKit.cyl(0.32, 0.32, 0.36, 18), MeshKit.at(kick, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.85, 0.2, 0.3)])
	parts.append([MeshKit.cyl(0.28, 0.28, 0.37, 18), MeshKit.at(kick, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.92, 0.85)])
	parts.append([MeshKit.sphere(0.1, 10), MeshKit.at(kick + Vector3(0, 0, -0.19), Vector3(1, 1, 0.1)), Color(1.0, 0.8, 0.2)])
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.merge(parts)
	mi.material_override = MeshKit.vertex_material(main.mats)
	add_child(mi)
	# Glowing stage lip.
	var lip := MeshInstance3D.new()
	lip.mesh = main.box_mesh(Vector3(9.5, 0.06, 0.1))
	lip.material_override = main.make_material(Color(1.0, 0.4, 0.8), 1.5)
	lip.position = Vector3(0.0, STAGE_Y - 0.02, -2.36)
	add_child(lip)
	for sx in [-4.3, 4.3]:
		var sxf3: float = sx
		for k in 2:
			var cone := MeshInstance3D.new()
			cone.mesh = main.cyl_mesh(0.3 - k * 0.1, 0.3 - k * 0.1, 0.05, 16)
			cone.material_override = main.make_material(Color(0.25, 0.25, 0.3), 0.0)
			cone.rotation.x = PI * 0.5
			cone.position = Vector3(sxf3, STAGE_Y + 0.6 + k * 0.95, -2.02)
			add_child(cone)
			speakers.append(cone)


func _build_floor() -> void:
	tiles_mm = MultiMesh.new()
	tiles_mm.transform_format = MultiMesh.TRANSFORM_3D
	tiles_mm.use_colors = true
	tiles_mm.mesh = main.box_mesh(Vector3(0.9, 0.02, 0.5))
	tiles_mm.instance_count = TILE_COLS * TILE_ROWS
	for r in TILE_ROWS:
		for c in TILE_COLS:
			var i := r * TILE_COLS + c
			tiles_mm.set_instance_transform(i, Transform3D(Basis(), Vector3((c - 4) * 0.95, STAGE_Y + 0.012, -2.0 + r * 0.55)))
			tiles_mm.set_instance_color(i, Color(0.2, 0.2, 0.3))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = tiles_mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)


## A big LED wall behind the band: an equalizer that jumps to the beat (all in a shader).
func _build_led_wall() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.28)
	mm.mesh = qm
	mm.instance_count = LED_COLS * LED_ROWS
	for r in LED_ROWS:
		for c in LED_COLS:
			var i := r * LED_COLS + c
			var pos := Vector3((c - (LED_COLS - 1) * 0.5) * 0.31, 1.05 + r * 0.29, 3.18)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, PI), pos))
			mm.set_instance_custom_data(i, Color(float(c) / (LED_COLS - 1), (float(r) + 0.5) / LED_ROWS, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var sh := Shader.new()
	sh.code = LED_SHADER
	led_mat = ShaderMaterial.new()
	led_mat.shader = sh
	mi.material_override = led_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_lip_lights() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = main.sphere_mesh(0.045)
	mm.instance_count = LIP_BULBS
	for k in LIP_BULBS:
		mm.set_instance_transform(k, Transform3D(Basis(), Vector3(-4.6 + 9.2 * float(k) / (LIP_BULBS - 1), STAGE_Y + 0.03, -2.42)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var sh := Shader.new()
	sh.code = LIP_SHADER
	lip_mat = ShaderMaterial.new()
	lip_mat.shader = sh
	lip_mat.set_shader_parameter("count", float(LIP_BULBS))
	mi.material_override = lip_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_beams() -> void:
	var xs: Array[float] = [-3.6, -2.2, -0.8, 0.8, 2.2, 3.6]
	for i in xs.size():
		var pivot := Node3D.new()
		pivot.position = Vector3(xs[i], 5.1, -0.6)
		add_child(pivot)
		var beam := MeshInstance3D.new()
		beam.mesh = main.cyl_mesh(0.05, 0.45, 5.0, 10)
		beam.position = Vector3(0.0, -2.5, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var c := BEAM_COLORS[i]
		m.albedo_color = Color(c.r, c.g, c.b, 0.1)
		beam.material_override = m
		pivot.add_child(beam)
		var lamp := MeshInstance3D.new()
		lamp.mesh = main.sphere_mesh(0.12)
		lamp.material_override = main.make_material(c, 2.0)
		pivot.add_child(lamp)
		beam_pivots.append(pivot)
		beam_mats.append(m)


## One fan: legs, shirt (coloured per fan in the shader), head and hair, arms up with a glow stick.
## Arms are flagged (UV.x 1 = left, 2 = right) so the shader can wave them.
func _fan_mesh(skin: Color, hair: Color, glow: Color) -> ArrayMesh:
	var shirt := Color(1, 1, 1, 0.0)  # alpha 0: the shader paints the fan's own shirt colour
	var jeans := Color(0.2, 0.25, 0.45)
	var parts: Array = [
		[MeshKit.cyl(0.065, 0.06, 0.5, 6), MeshKit.at(Vector3(-0.08, 0.25, 0)), jeans],
		[MeshKit.cyl(0.065, 0.06, 0.5, 6), MeshKit.at(Vector3(0.08, 0.25, 0)), jeans],
		[MeshKit.cyl(0.15, 0.17, 0.48, 8), MeshKit.at(Vector3(0, 0.72, 0)), shirt],
		[MeshKit.sphere(0.12, 10), MeshKit.at(Vector3(0, 1.1, 0)), skin],
		[MeshKit.sphere(0.125, 8), MeshKit.at(Vector3(0, 1.15, -0.02), Vector3(1.0, 0.75, 1.0)), hair],
	]
	for side in [-1.0, 1.0]:
		var sd: float = side
		var flag := 1.0 if sd < 0.0 else 2.0
		var dir := Vector3(sd * sin(0.35), cos(0.35), 0.0)
		var sh := Vector3(0.19 * sd, 0.92, 0.0)
		parts.append([MeshKit.cyl(0.04, 0.045, 0.42, 6), Transform3D(Basis(Vector3.BACK, -sd * 0.35), sh + dir * 0.21), skin, flag])
		parts.append([MeshKit.sphere(0.05, 6), MeshKit.at(sh + dir * 0.44), skin, flag])
		if sd > 0.0:
			parts.append([MeshKit.cyl(0.018, 0.018, 0.22, 6), Transform3D(Basis(Vector3.BACK, -0.2), sh + dir * 0.52), Color(glow.r, glow.g, glow.b, 0.5), flag])
	return MeshKit.merge(parts)


## Two MultiMeshes of fans (two looks), each animated in the crowd shader: they bounce on the beat,
## more together and higher the happier they are, and wave their arms (and glow sticks) when wild.
func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var shirts: Array[Color] = [Color(1.0, 0.4, 0.4), Color(0.4, 0.7, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.5),
		Color(0.9, 0.5, 1.0), Color(1.0, 0.6, 0.3), Color(0.92, 0.92, 0.95), Color(0.3, 0.9, 0.9)]
	var looks: Array = [
		[Color(1.0, 0.82, 0.68), Color(0.45, 0.28, 0.12), Color(0.3, 1.0, 0.5)],
		[Color(0.62, 0.42, 0.3), Color(0.08, 0.06, 0.06), Color(1.0, 0.35, 0.8)],
	]
	var xfs: Array = [[], []]
	var customs: Array = [[], []]
	for r in CROWD_ROWS:
		for c in CROWD_COLS:
			var s := rng.randf_range(0.8, 1.15)
			var x := (c - (CROWD_COLS - 1) * 0.5) * 0.46 + rng.randf_range(-0.1, 0.1) + (r % 2) * 0.23
			var z := -3.0 - r * 0.6 + rng.randf_range(-0.1, 0.1) + 0.025 * x * x
			var face := Basis(Vector3.UP, -atan2(x, 6.0) * 0.6)
			var look := rng.randi_range(0, 1)
			(xfs[look] as Array).append(Transform3D(face.scaled(Vector3.ONE * s), Vector3(x, 0.0, z)))
			var sc := shirts[rng.randi_range(0, shirts.size() - 1)]
			(customs[look] as Array).append(Color(sc.r, sc.g, sc.b, rng.randf()))
	var sh := Shader.new()
	sh.code = CROWD_SHADER
	for look in 2:
		var la: Array = looks[look]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _fan_mesh(la[0], la[1], la[2])
		var xs: Array = xfs[look]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			mm.set_instance_custom_data(i, (customs[look] as Array)[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		crowd_mats.append(mat)


## A guitarist: one merged body (legs, shirt, head, hair, shades), a guitar with its own glowing
## material, and a strumming arm that swings when they hit a note.
func _build_avatar(i: int) -> void:
	var color: Color = main.PLAYER_COLORS[i]
	var skin: Color = [Color(1.0, 0.82, 0.65), Color(0.85, 0.62, 0.45), Color(0.6, 0.4, 0.28)][i % 3]
	var hair: Color = HAIR[(i - 1) % HAIR.size()]
	var root := Node3D.new()
	var x := AVATAR_X[i - 1]
	root.position = Vector3(x, STAGE_Y, -0.7 - absf(x) * 0.1)
	root.rotation.y = x * 0.06  # face the crowd, angled a little to the middle
	add_child(root)
	var dark := Color(0.15, 0.15, 0.2)
	var parts: Array = [
		[MeshKit.cyl(0.07, 0.065, 0.5, 8), MeshKit.at(Vector3(-0.09, 0.25, 0)), dark],
		[MeshKit.cyl(0.07, 0.065, 0.5, 8), MeshKit.at(Vector3(0.09, 0.25, 0)), dark],
		[MeshKit.box(Vector3(0.12, 0.07, 0.2)), MeshKit.at(Vector3(-0.09, 0.035, -0.04)), Color(0.95, 0.95, 0.95)],
		[MeshKit.box(Vector3(0.12, 0.07, 0.2)), MeshKit.at(Vector3(0.09, 0.035, -0.04)), Color(0.95, 0.95, 0.95)],
		[MeshKit.cyl(0.17, 0.2, 0.5, 10), MeshKit.at(Vector3(0, 0.74, 0)), color],
		[MeshKit.box(Vector3(0.36, 0.05, 0.36)), MeshKit.at(Vector3(0, 0.5, 0)), Color(0.12, 0.1, 0.08)],
		[MeshKit.cyl(0.05, 0.05, 0.08, 8), MeshKit.at(Vector3(0, 1.02, 0)), skin],
		[MeshKit.cyl(0.05, 0.05, 0.4, 6), Transform3D(Basis(Vector3.RIGHT, -1.1) * Basis(Vector3.BACK, 0.5), Vector3(-0.24, 0.82, -0.12)), color],
		[MeshKit.sphere(0.05, 8), MeshKit.at(Vector3(-0.38, 0.72, -0.3)), skin],
	]
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.merge(parts)
	mi.material_override = MeshKit.vertex_material(main.mats)
	root.add_child(mi)
	var head := Node3D.new()
	head.position = Vector3(0, 1.2, 0)
	root.add_child(head)
	var hparts: Array = [
		[MeshKit.sphere(0.16, 14), MeshKit.at(Vector3.ZERO), skin],
		[MeshKit.sphere(0.165, 12), MeshKit.at(Vector3(0, 0.06, 0.03), Vector3(1.05, 0.8, 1.05)), hair],
		[MeshKit.box(Vector3(0.24, 0.06, 0.04)), MeshKit.at(Vector3(0, 0.02, -0.15)), Color(0.05, 0.05, 0.08)],
		[MeshKit.box(Vector3(0.07, 0.02, 0.02)), MeshKit.at(Vector3(0, -0.07, -0.15)), Color(0.6, 0.2, 0.2)],
		[MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(-0.16, 0.0, 0)), skin],
		[MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(0.16, 0.0, 0)), skin],
	]
	if i % 2 == 0:
		hparts.append([MeshKit.cyl(0.13, 0.19, 0.1, 12), MeshKit.at(Vector3(0, 0.15, 0)), color.darkened(0.35)])
	else:
		for k in 5:
			hparts.append([MeshKit.cyl(0.0, 0.05, 0.12, 6), MeshKit.at(Vector3(-0.1 + k * 0.05, 0.16, 0.04), Vector3.ONE, Vector3(-0.3, 0, -0.2 + k * 0.1)), hair])
	var hm := MeshInstance3D.new()
	hm.mesh = MeshKit.merge(hparts)
	hm.material_override = MeshKit.vertex_material(main.mats)
	head.add_child(hm)
	var guitar := Node3D.new()
	guitar.position = Vector3(0.0, 0.62, -0.24)
	guitar.rotation.z = 0.5
	root.add_child(guitar)
	var gparts: Array = [
		[MeshKit.cyl(0.15, 0.15, 0.06, 14), MeshKit.at(Vector3(-0.04, 0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), color.lightened(0.25)],
		[MeshKit.cyl(0.11, 0.11, 0.06, 14), MeshKit.at(Vector3(0.12, 0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), color.lightened(0.25)],
		[MeshKit.cyl(0.07, 0.07, 0.062, 12), MeshKit.at(Vector3(0.02, 0.0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.95, 0.9)],
		[MeshKit.box(Vector3(0.5, 0.05, 0.04)), MeshKit.at(Vector3(0.45, 0.0, 0.0)), Color(0.4, 0.25, 0.12)],
		[MeshKit.box(Vector3(0.1, 0.08, 0.04)), MeshKit.at(Vector3(0.74, 0.0, 0.0)), Color(0.15, 0.1, 0.08)],
		[MeshKit.box(Vector3(0.62, 0.008, 0.008)), MeshKit.at(Vector3(0.38, 0.0, -0.035)), Color(0.9, 0.9, 0.9)],
	]
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.emission_enabled = true
	gm.emission = color
	gm.emission_energy_multiplier = 0.15
	var gbody := MeshInstance3D.new()
	gbody.mesh = MeshKit.merge(gparts)
	gbody.material_override = gm
	guitar.add_child(gbody)
	var arm := Node3D.new()
	arm.position = Vector3(0.22, 0.92, -0.02)
	root.add_child(arm)
	var aparts: Array = [
		[MeshKit.cyl(0.05, 0.05, 0.38, 6), Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0.0, -0.13, -0.11)), color],
		[MeshKit.sphere(0.05, 8), MeshKit.at(Vector3(-0.02, -0.25, -0.27)), skin],
	]
	var am := MeshInstance3D.new()
	am.mesh = MeshKit.merge(aparts)
	am.material_override = MeshKit.vertex_material(main.mats)
	arm.add_child(am)
	var tag := Label3D.new()
	tag.text = "P%d" % (i + 1)
	tag.font_size = 64
	tag.pixel_size = 0.0035
	tag.outline_size = 16
	tag.modulate = color
	tag.position = Vector3(0, 1.62, 0)
	root.add_child(tag)
	root.visible = false
	avatars.append(root)
	guitars.append(guitar)
	guitar_mats.append(gm)
	strum_arms.append(arm)
	heads.append(head)
	tags.append(tag)


## A flat five-pointed star (both faces), shared by the result stars.
func _star_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var r := 0.32 if k % 2 == 0 else 0.13
		pts.append(Vector3(cos(a) * r, -sin(a) * r, 0.0))
	for k in 10:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[k])
		st.add_vertex(pts[(k + 1) % 10])
	return st.commit()


func _build_stars() -> void:
	stars_root = Node3D.new()
	stars_root.position = Vector3(0.0, 3.4, -1.2)
	add_child(stars_root)
	var mesh := _star_mesh()
	for k in 5:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 0.3, 0.35)
		m.material_override = mat
		m.position = Vector3((k - 2) * 0.8, 0.0, 0.0)
		m.visible = false
		stars_root.add_child(m)
		star_meshes.append(m)


func show_stars(n: int) -> void:
	stars_shown = n
	star_anim = 0.0
	for k in 5:
		var m := star_meshes[k]
		m.visible = true
		m.scale = Vector3.ONE * 0.01
		var mat: StandardMaterial3D = m.material_override
		mat.albedo_color = Color(1.0, 0.85, 0.2) if k < n else Color(0.3, 0.3, 0.35)


func hide_stars() -> void:
	stars_shown = -1
	for m in star_meshes:
		m.visible = false


func set_song_title(text: String) -> void:
	if song_label != null:
		song_label.text = text


func set_avatar_visible(i: int, on: bool) -> void:
	if i >= 1 and i <= avatars.size():
		avatars[i - 1].visible = on


## VR: name tags face the drummer behind them. Flat views: they turn to the camera.
func set_tags_for_vr(vr: bool) -> void:
	for tag in tags:
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED if vr else BaseMaterial3D.BILLBOARD_ENABLED
		tag.rotation.y = PI if vr else 0.0


func strum(i: int, good: bool) -> void:
	if i >= 1 and i < strum_t.size():
		strum_t[i] = 1.0 if good else 0.4


## TV camera for guitarist i: in the crowd, looking up at the band with your own avatar near the middle.
func tv_camera(i: int) -> Transform3D:
	var ax := AVATAR_X[clampi(i - 1, 0, AVATAR_X.size() - 1)]
	var pos := Vector3(ax * 0.5, 1.8, -6.6)
	return Transform3D(Basis(), pos).looking_at(Vector3(ax * 0.35, 1.75, 0.5), Vector3.UP)


func on_beat(b: int, crowd: float) -> void:
	beat_n = b
	beat_flash = 1.0
	if b % 4 == 0:
		bar_n = b / 4
	# Disco floor: a different pattern every beat (gold during star power).
	var pattern := b % 4
	for r in TILE_ROWS:
		for c in TILE_COLS:
			var on := false
			match pattern:
				0:
					on = (r + c) % 2 == 0
				1:
					on = c % 3 == (b / 4) % 3
				2:
					on = (r + c) % 2 == 1
				_:
					on = r == (b / 4) % TILE_ROWS
			var col := BEAM_COLORS[(c + bar_n) % BEAM_COLORS.size()].lerp(Color(1.0, 0.8, 0.25), star_k)
			tiles_mm.set_instance_color(r * TILE_COLS + c, col * (0.5 + 0.7 * crowd) if on else Color(0.12, 0.1, 0.2))
	for sp in speakers:
		sp.scale = Vector3(1.25, 1.0, 1.25)


## star: 0..1, how much STAR POWER is on (lights go gold, the crowd goes wild).
func update(delta: float, beat_pos: float, crowd: float, playing: bool, star: float = 0.0) -> void:
	t += delta
	star_k = lerpf(star_k, star, 1.0 - exp(-5.0 * delta))
	beat_flash = maxf(0.0, beat_flash - delta * 3.5)
	var energy := clampf((crowd if playing else 0.35) + star_k * 0.3, 0.0, 1.0)
	for i in beam_pivots.size():
		var pv := beam_pivots[i]
		var k := float(i)
		var spd := 1.0 + star_k * 1.5
		pv.rotation.z = sin(t * (0.6 + k * 0.07) * spd + k * 1.3) * 0.55
		pv.rotation.x = 0.45 + sin(t * 0.5 * spd + k) * 0.25
		var c := BEAM_COLORS[(i + bar_n) % BEAM_COLORS.size()].lerp(Color(1.0, 0.8, 0.25), star_k)
		beam_mats[i].albedo_color = Color(c.r, c.g, c.b, 0.05 + 0.2 * beat_flash * (0.4 + energy))
	key_light.light_energy = 1.0 + beat_flash * 0.8 * (0.3 + energy)
	key_light.light_color = BEAM_COLORS[bar_n % BEAM_COLORS.size()].lerp(Color.WHITE, 0.6).lerp(Color(1.0, 0.85, 0.5), star_k)
	for sp in speakers:
		sp.scale = sp.scale.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
	for m in crowd_mats:
		m.set_shader_parameter("beat", beat_pos)
		m.set_shader_parameter("energy", energy)
		m.set_shader_parameter("star", star_k)
	led_mat.set_shader_parameter("beat", beat_pos)
	led_mat.set_shader_parameter("energy", energy)
	led_mat.set_shader_parameter("star", star_k)
	lip_mat.set_shader_parameter("beat", beat_pos)
	lip_mat.set_shader_parameter("star", star_k)
	# Guitarists: bob to the beat, swing the guitar and strumming arm when they hit a note, and jump
	# during STAR POWER.
	for i in avatars.size():
		var av := avatars[i]
		if not av.visible:
			continue
		var bob := absf(sin(PI * beat_pos)) * (0.05 + 0.12 * star_k)
		av.position.y = STAGE_Y + bob
		heads[i].rotation.x = -absf(sin(PI * beat_pos)) * 0.15
		var st := strum_t[i + 1]
		strum_t[i + 1] = maxf(0.0, st - delta * 4.0)
		guitars[i].rotation.x = -st * 0.4
		strum_arms[i].rotation.x = -st * 0.9 + 0.1 * sin(PI * beat_pos)
		guitar_mats[i].emission_energy_multiplier = 0.15 + st * 2.5 + star_k * 0.8
	# Result stars pop in one by one.
	if stars_shown >= 0 and not star_meshes.is_empty() and star_meshes[0].visible:
		star_anim += delta
		for k in 5:
			var sk := clampf((star_anim - k * 0.35) * 4.0, 0.0, 1.0)
			var wob := 1.0 + 0.15 * sin(t * 6.0 + k) if k < stars_shown else 1.0
			star_meshes[k].scale = Vector3.ONE * maxf(0.01, sk * wob)
			star_meshes[k].rotation.y = sin(t * 1.5 + k) * 0.4


# --- Pyro and fireworks (combo milestones, STAR POWER) -----------------------------------------

func pyro() -> void:
	for sx in [-4.3, 4.3]:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 36
		p.lifetime = 0.9
		p.explosiveness = 0.7
		p.direction = Vector3.UP
		p.spread = 12.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 6.5
		p.gravity = Vector3(0, -2.0, 0)
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.2
		p.mesh = main.sphere_mesh(0.07)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		p.material_override = m
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		g.colors = PackedColorArray([Color(1.0, 0.95, 0.6), Color(1.0, 0.55, 0.1), Color(0.6, 0.1, 0.05)])
		p.color_ramp = g
		add_child(p)
		p.position = Vector3(float(sx), STAGE_Y + 2.3, -1.6)
		p.emitting = true
		get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func fireworks(count: int = 2) -> void:
	for k in count:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 48
		p.lifetime = 1.6
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0, -1.2, 0)
		p.damping_min = 0.8
		p.damping_max = 1.4
		p.mesh = main.sphere_mesh(0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = BEAM_COLORS[(bar_n + k * 2) % BEAM_COLORS.size()].lightened(0.2)
		p.material_override = m
		add_child(p)
		p.position = Vector3(randf_range(-4.0, 4.0), randf_range(6.0, 7.5), randf_range(-5.0, -3.0))
		get_tree().create_timer(0.25 * k).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.emitting = true)
		get_tree().create_timer(2.5 + 0.25 * k).timeout.connect(p.queue_free)
