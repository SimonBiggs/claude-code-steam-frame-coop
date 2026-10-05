extends Node3D
## The stadium: a striped night-time pitch with markings, a full-size goal (7.32 x 2.44 m) with a net,
## four roofed stands packed with a crowd that bounces and waves (one MultiMesh per stand, animated in
## a shader), waving flags, camera flashes, floodlights, glowing advertising boards, a dancing lion
## MASCOT by the goal, confetti cannons, the CUP trophy and two big scoreboards (one facing the keeper,
## one facing the strikers).
## Cheap on the Steam Frame: all static geometry is merged into a few meshes (mesh_kit.gd); the crowd,
## flags and flashes are animated on the GPU from one "excite" value.
## Goal line at z = 0, the pitch runs towards +z, penalty spot at z = 11.

const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")

const CROWD_SHADER := """
shader_type spatial;
uniform float excite = 0.0;
varying vec3 shirt;
void vertex() {
	float ph = INSTANCE_CUSTOM.a;
	shirt = INSTANCE_CUSTOM.rgb;
	float hop = excite * max(0.0, sin(TIME * 10.0 + ph * 31.0)) * 0.5 + 0.05 * sin(TIME * 2.0 + ph * 9.0);
	if (UV.x > 0.5) {
		float side = UV.x > 1.5 ? 1.0 : -1.0;
		float raise = clamp(excite * 1.6 - 0.2, 0.0, 1.0);
		float a = -side * 2.5 * (1.0 - raise) + side * 0.4 * raise * sin(TIME * 7.0 + ph * 20.0);
		vec3 sh = vec3(0.24 * side, 0.85, 0.0);
		vec3 p = VERTEX - sh;
		VERTEX = sh + vec3(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a), p.z);
	}
	VERTEX.y += hop;
}
void fragment() {
	ALBEDO = COLOR.a < 0.5 ? shirt : COLOR.rgb;
	ROUGHNESS = 0.9;
}
"""

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float excite = 0.0;
varying vec3 col;
void vertex() {
	col = INSTANCE_CUSTOM.rgb;
	float ph = INSTANCE_CUSTOM.a * 6.28;
	float k = (VERTEX.x + 0.6) / 1.2;
	VERTEX.z += sin(TIME * (3.0 + 6.0 * excite) + VERTEX.x * 5.0 + ph) * 0.12 * k;
	VERTEX.y += sin(TIME * (2.0 + 4.0 * excite) + ph) * 0.05 * k;
}
void fragment() {
	float stripe = step(0.5, fract(UV.y * 1.5));
	ALBEDO = mix(col, col * 0.35 + vec3(0.6), stripe * 0.5);
	ROUGHNESS = 0.8;
}
"""

const FLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float excite = 0.0;
varying float fid;
void vertex() {
	fid = INSTANCE_CUSTOM.r;
}
void fragment() {
	float id = fid;
	float slot = floor(TIME * 9.0);
	float rnd = fract(sin(id * 91.7 + slot * 12.9898) * 43758.5453);
	float on = step(1.0 - 0.06 * excite * excite, rnd);
	if (on < 0.5) {
		discard;
	}
	float d = length(UV - vec2(0.5));
	if (d > 0.5) {
		discard;
	}
	ALBEDO = vec3(1.0, 1.0, 0.95) * (1.5 - d * 2.0);
}
"""

const NET_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;
uniform vec2 cells = vec2(20.0, 8.0);
void fragment() {
	vec2 g = fract(UV * cells);
	float line = step(g.x, 0.07) + step(g.y, 0.07);
	ALBEDO = vec3(0.95);
	ALPHA = clamp(line, 0.0, 1.0) * 0.8;
}
"""

const SHIRTS: Array[Color] = [Color(0.9, 0.15, 0.15), Color(1, 1, 1), Color(0.15, 0.35, 0.95), Color(1.0, 0.85, 0.1),
	Color(0.95, 0.5, 0.1), Color(0.2, 0.8, 0.3), Color(0.6, 0.3, 0.9), Color(0.1, 0.1, 0.15)]

var main
var crowd_mat: ShaderMaterial
var flag_mat: ShaderMaterial
var flash_mat: ShaderMaterial
var net_back: MeshInstance3D
var board_keeper: Label3D  # far end, faces the keeper
var board_tv: Label3D  # behind the goal, faces the strikers' cameras
var net_bulge := 0.0
var t := 0.0
var mascot: Node3D
var mascot_arms: Array[Node3D] = []
var mascot_mode := ""
var mascot_t := 0.0
var mascot_home_yaw := 0.5
var trophy: Node3D
var trophy_spin := 0.0


func build(vr: bool) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.07, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.95, 1.0)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = not vr
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(150.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = not vr
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var lit: Array = []
	var glow: Array = []
	_build_pitch(lit)
	_build_goal()
	_build_stands(lit, glow)
	_build_lights_and_boards(lit, glow)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.merge(lit)
	mi.material_override = MeshKit.vertex_material(main.mats)
	add_child(mi)
	var gi := MeshInstance3D.new()
	gi.mesh = MeshKit.merge(glow)
	gi.material_override = MeshKit.vertex_material(main.mats, true)
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	_build_scoreboards()
	_build_mascot()


func _build_pitch(lit: Array) -> void:
	# Base grass plus mown stripes across the pitch.
	lit.append([MeshKit.box(Vector3(80, 0.02, 90)), MeshKit.at(Vector3(0, -0.011, 25)), Color(0.16, 0.42, 0.16)])
	for i in 8:
		lit.append([MeshKit.box(Vector3(70, 0.002, 4.0)), MeshKit.at(Vector3(0, 0.0, -6.0 + i * 8.0 + 2.0)), Color(0.2, 0.5, 0.2)])
	var w := Color(0.95, 0.97, 0.95)
	var lw := 0.12
	var lines: Array = [
		[Vector3(70, 0.006, lw), Vector3(0, 0.004, 0)],  # goal line
		[Vector3(18.32, 0.006, lw), Vector3(0, 0.004, 5.5)],
		[Vector3(lw, 0.006, 5.5), Vector3(-9.16, 0.004, 2.75)],
		[Vector3(lw, 0.006, 5.5), Vector3(9.16, 0.004, 2.75)],
		[Vector3(40.32, 0.006, lw), Vector3(0, 0.004, 16.5)],
		[Vector3(lw, 0.006, 16.5), Vector3(-20.16, 0.004, 8.25)],
		[Vector3(lw, 0.006, 16.5), Vector3(20.16, 0.004, 8.25)],
		[Vector3(70, 0.006, lw), Vector3(0, 0.004, 52.5)],
	]
	for ln in lines:
		var la: Array = ln
		lit.append([MeshKit.box(la[0]), MeshKit.at(la[1]), w])
	# Penalty arc ("the D") as a few segments.
	for i in 7:
		var a := deg_to_rad(-52.0 + i * 17.3)
		lit.append([MeshKit.box(Vector3(2.7, 0.006, lw)), MeshKit.at(Vector3(sin(a) * 9.15, 0.004, 11.0 + cos(a) * 9.15), Vector3.ONE, Vector3(0, -a, 0)), w])
	lit.append([MeshKit.cyl(0.12, 0.12, 0.006, 12), MeshKit.at(Vector3(0, 0.005, 11.0)), w])
	# Corner flags at the goal end and a dugout on each side.
	for sx in [-1.0, 1.0]:
		var x: float = sx * 30.0
		lit.append([MeshKit.cyl(0.03, 0.03, 1.5, 6), MeshKit.at(Vector3(x, 0.75, 0.3)), Color(1, 1, 1)])
		lit.append([MeshKit.box(Vector3(0.02, 0.35, 0.45)), MeshKit.at(Vector3(x, 1.33, 0.55)), Color(1.0, 0.85, 0.1)])
		lit.append([MeshKit.box(Vector3(0.6, 1.4, 6.0)), MeshKit.at(Vector3(sx * 28.5, 0.7, 26.0)), Color(0.15, 0.17, 0.22)])
		lit.append([MeshKit.box(Vector3(1.4, 0.08, 6.2)), MeshKit.at(Vector3(sx * 28.2, 1.45, 26.0)), Color(0.6, 0.8, 0.95)])
		lit.append([MeshKit.box(Vector3(0.5, 0.45, 5.6)), MeshKit.at(Vector3(sx * 28.0, 0.25, 26.0)), Color(0.85, 0.2, 0.2)])


func _build_goal() -> void:
	var parts: Array = []
	for sx in [-1.0, 1.0]:
		var x: float = sx * 3.72
		parts.append([MeshKit.cyl(0.06, 0.06, 2.50, 12), MeshKit.at(Vector3(x, 1.25, 0)), Color(1, 1, 1)])
		parts.append([MeshKit.cyl(0.025, 0.025, 2.0, 6), MeshKit.at(Vector3(x, 2.44, -1.0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.8, 0.8, 0.85)])
		parts.append([MeshKit.cyl(0.025, 0.025, 2.44, 6), MeshKit.at(Vector3(x, 1.22, -2.0)), Color(0.8, 0.8, 0.85)])
	parts.append([MeshKit.cyl(0.06, 0.06, 7.56, 12), MeshKit.at(Vector3(0, 2.50, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(1, 1, 1)])
	var frame := MeshInstance3D.new()
	frame.mesh = MeshKit.merge(parts)
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.emission_enabled = true
	fm.emission = Color(1, 1, 1)
	fm.emission_energy_multiplier = 0.25
	frame.material_override = fm
	add_child(frame)
	var shader := Shader.new()
	shader.code = NET_SHADER
	# back, top, left, right
	var panels: Array = [
		[Vector2(7.44, 2.44), Vector3(0, 1.22, -2.0), Vector3.ZERO, Vector2(30, 10)],
		[Vector2(7.44, 2.0), Vector3(0, 2.44, -1.0), Vector3(PI * 0.5, 0, 0), Vector2(30, 8)],
		[Vector2(2.0, 2.44), Vector3(-3.72, 1.22, -1.0), Vector3(0, PI * 0.5, 0), Vector2(8, 10)],
		[Vector2(2.0, 2.44), Vector3(3.72, 1.22, -1.0), Vector3(0, PI * 0.5, 0), Vector2(8, 10)],
	]
	for i in panels.size():
		var pa: Array = panels[i]
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = pa[0]
		m.mesh = q
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("cells", pa[3])
		m.material_override = sm
		m.position = pa[1]
		m.rotation = pa[2]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		if i == 0:
			net_back = m


## A low-poly fan (body, head, arms): about 100 vertices, so 1000 of them stay cheap. Arms are
## flagged (UV.x 1 left / 2 right) for the shader; vertex alpha 0 = the fan's own shirt colour.
func _fan_mesh() -> ArrayMesh:
	var shirt := Color(1, 1, 1, 0.0)
	var skin := Color(1.0, 0.8, 0.62)
	var parts: Array = [
		[MeshKit.box(Vector3(0.5, 0.62, 0.36)), MeshKit.at(Vector3(0, 0.5, 0)), shirt],
		[MeshKit.box(Vector3(0.26, 0.28, 0.26)), MeshKit.at(Vector3(0, 0.98, 0)), skin],
		[MeshKit.box(Vector3(0.12, 0.45, 0.12)), Transform3D(Basis(Vector3.BACK, 0.35), Vector3(-0.31, 1.05, 0)), shirt, 1.0],
		[MeshKit.box(Vector3(0.12, 0.45, 0.12)), Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0.31, 1.05, 0)), shirt, 2.0],
	]
	return MeshKit.merge(parts)


func _build_stands(lit: Array, glow: Array) -> void:
	var shader := Shader.new()
	shader.code = CROWD_SHADER
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = shader
	var fshader := Shader.new()
	fshader.code = FLAG_SHADER
	flag_mat = ShaderMaterial.new()
	flag_mat.shader = fshader
	var xshader := Shader.new()
	xshader.code = FLASH_SHADER
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = xshader
	# [centre, length along the stand, yaw so rows climb away from the pitch]
	var stands: Array = [
		[Vector3(0, 0, 62), 70.0, 0.0],  # far end behind the strikers (faces the keeper)
		[Vector3(-34, 0, 22), 56.0, -PI * 0.5],
		[Vector3(34, 0, 22), 56.0, PI * 0.5],
		[Vector3(0, 0, -12), 70.0, PI],  # behind the goal
	]
	var fan := _fan_mesh()
	var flag := QuadMesh.new()
	flag.size = Vector2(1.2, 0.8)
	flag.subdivide_width = 6
	var flash := QuadMesh.new()
	flash.size = Vector2(0.35, 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var fid := 0
	for si in stands.size():
		var sa: Array = stands[si]
		var center: Vector3 = sa[0]
		var length: float = sa[1]
		var yaw: float = sa[2]
		var xf := Transform3D(Basis(Vector3.UP, yaw), center)
		for row in 4:
			var h := 1.2 + row * 1.2
			lit.append([MeshKit.box(Vector3(length, h, 1.6)), xf * MeshKit.at(Vector3(0, h * 0.5, row * 1.6)), Color(0.25, 0.27, 0.33) if row % 2 == 0 else Color(0.32, 0.34, 0.4)])
		# Roof canopy on posts, with a strip of lights under it.
		lit.append([MeshKit.box(Vector3(length + 2.0, 0.3, 8.5)), xf * MeshKit.at(Vector3(0, 9.0, 3.4), Vector3.ONE, Vector3(-0.12, 0, 0)), Color(0.55, 0.58, 0.65)])
		for k in 5:
			lit.append([MeshKit.box(Vector3(0.3, 4.2, 0.3)), xf * MeshKit.at(Vector3(-length * 0.5 + k * length / 4.0, 6.9, 6.6)), Color(0.4, 0.42, 0.48)])
		glow.append([MeshKit.box(Vector3(length, 0.12, 0.25)), xf * MeshKit.at(Vector3(0, 8.6, -0.4)), Color(1.0, 1.0, 0.85)])
		var stand := Node3D.new()
		stand.transform = xf
		add_child(stand)
		# The crowd: home colours on one half of each stand, away colours on the other, a few randoms.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = fan
		var cols := int(length / 1.0)
		mm.instance_count = cols * 4
		var k2 := 0
		for row in 4:
			for c in cols:
				var x := -length * 0.5 + 0.5 + c * 1.0 + rng.randf_range(-0.15, 0.15)
				var y := 1.2 + row * 1.2
				var s := rng.randf_range(0.85, 1.1)
				mm.set_instance_transform(k2, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(x, y, row * 1.6)))
				var team := SHIRTS[0] if x < 0.0 else SHIRTS[2]
				if rng.randf() < 0.35:
					team = SHIRTS[rng.randi_range(0, SHIRTS.size() - 1)]
				mm.set_instance_custom_data(k2, Color(team.r, team.g, team.b, rng.randf()))
				k2 += 1
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = crowd_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.add_child(mi)
		# Waving flags along the front row.
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.use_custom_data = true
		fm.mesh = flag
		var nflags := int(length / 7.0)
		fm.instance_count = nflags
		for f in nflags:
			var fx := -length * 0.5 + 3.5 + f * 7.0
			fm.set_instance_transform(f, Transform3D(Basis(), Vector3(fx, 3.1, -0.3)))
			var fc := SHIRTS[(f + si) % 4]
			fm.set_instance_custom_data(f, Color(fc.r, fc.g, fc.b, rng.randf()))
			lit.append([MeshKit.cyl(0.02, 0.02, 1.6, 4), xf * MeshKit.at(Vector3(fx - 0.6, 2.6, -0.3)), Color(0.85, 0.85, 0.85)])
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fm
		fmi.material_override = flag_mat
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.add_child(fmi)
		# Camera flashes scattered over the crowd (they pop when the crowd is excited).
		var xm := MultiMesh.new()
		xm.transform_format = MultiMesh.TRANSFORM_3D
		xm.use_custom_data = true
		xm.mesh = flash
		xm.instance_count = 30
		for k3 in 30:
			var px := rng.randf_range(-length * 0.45, length * 0.45)
			var row2 := rng.randi_range(0, 3)
			xm.set_instance_transform(k3, Transform3D(Basis(Vector3.UP, PI), Vector3(px, 2.2 + row2 * 1.2, row2 * 1.6 - 0.3)))
			xm.set_instance_custom_data(k3, Color(float(fid), 0, 0, 0))
			fid += 1
		var xmi := MultiMeshInstance3D.new()
		xmi.multimesh = xm
		xmi.material_override = flash_mat
		xmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.add_child(xmi)


func _build_lights_and_boards(lit: Array, glow: Array) -> void:
	for p in [Vector3(-32, 0, -8), Vector3(32, 0, -8), Vector3(-32, 0, 56), Vector3(32, 0, 56)]:
		var pos: Vector3 = p
		lit.append([MeshKit.cyl(0.35, 0.5, 22.0, 8), MeshKit.at(pos + Vector3(0, 11, 0)), Color(0.4, 0.42, 0.48)])
		var look := Transform3D(Basis(), pos + Vector3(0, 22.5, 0)).looking_at(Vector3(0, 0, 20), Vector3.UP)
		glow.append([MeshKit.box(Vector3(5, 3, 0.5)), look, Color(1.0, 1.0, 0.85)])
		lit.append([MeshKit.box(Vector3(5.4, 3.4, 0.4)), look * MeshKit.at(Vector3(0, 0, 0.3)), Color(0.3, 0.3, 0.35)])
	# Advertising boards around the pitch (glowing).
	var ad_cols: Array[Color] = [Color(1.0, 0.3, 0.2), Color(0.2, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.3, 0.9, 0.4)]
	for i in 6:
		glow.append([MeshKit.box(Vector3(10, 0.9, 0.2)), MeshKit.at(Vector3(-27.5 + i * 11.0, 0.45, -4.0)), ad_cols[i % 4] * 0.85])
		glow.append([MeshKit.box(Vector3(10, 0.9, 0.2)), MeshKit.at(Vector3(-27.5 + i * 11.0, 0.45, 57.0)), ad_cols[(i + 2) % 4] * 0.85])
	for i in 5:
		glow.append([MeshKit.box(Vector3(0.2, 0.9, 10)), MeshKit.at(Vector3(-31.0, 0.45, 2.0 + i * 11.0)), ad_cols[(i + 1) % 4] * 0.85])
		glow.append([MeshKit.box(Vector3(0.2, 0.9, 10)), MeshKit.at(Vector3(31.0, 0.45, 2.0 + i * 11.0)), ad_cols[(i + 3) % 4] * 0.85])
	# Scoreboard backs.
	lit.append([MeshKit.box(Vector3(22, 9, 0.6)), MeshKit.at(Vector3(0, 14, 66)), Color(0.05, 0.05, 0.08)])
	lit.append([MeshKit.box(Vector3(18, 7, 0.6)), MeshKit.at(Vector3(0, 12, -16)), Color(0.05, 0.05, 0.08)])
	for sx in [-1.0, 1.0]:
		lit.append([MeshKit.box(Vector3(0.5, 10, 0.5)), MeshKit.at(Vector3(sx * 9.0, 5.0, 66.3)), Color(0.3, 0.3, 0.35)])
		lit.append([MeshKit.box(Vector3(0.5, 9, 0.5)), MeshKit.at(Vector3(sx * 7.0, 4.5, -16.3)), Color(0.3, 0.3, 0.35)])


func _build_scoreboards() -> void:
	board_keeper = _make_board_label()
	board_keeper.position = Vector3(0, 14, 65.6)
	board_keeper.rotation.y = PI  # faces -z, towards the goal
	board_tv = _make_board_label()
	board_tv.position = Vector3(0, 12, -15.6)
	board_tv.pixel_size = 0.028


func _make_board_label() -> Label3D:
	var l := Label3D.new()
	l.font_size = 64
	l.pixel_size = 0.034
	l.outline_size = 12
	l.modulate = Color(1.0, 0.9, 0.4)
	l.outline_modulate = Color(0, 0, 0)
	l.width = 1000.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func set_scoreboard(text: String) -> void:
	board_keeper.text = text
	board_tv.text = text


func set_excite(e: float) -> void:
	crowd_mat.set_shader_parameter("excite", e)
	flag_mat.set_shader_parameter("excite", e)
	flash_mat.set_shader_parameter("excite", e)


func bulge() -> void:
	net_bulge = 1.0


## A glove pushed into the net: a small ripple.
func poke_net() -> void:
	net_bulge = maxf(net_bulge, 0.3)


# --- The mascot: a big friendly lion beside the goal ----------------------------------------------

func _build_mascot() -> void:
	mascot = Node3D.new()
	mascot.position = Vector3(-6.2, 0, 2.2)
	mascot.rotation.y = 0.5
	add_child(mascot)
	var fur := Color(1.0, 0.72, 0.25)
	var mane := Color(0.85, 0.42, 0.1)
	var shirt := Color(0.15, 0.35, 0.95)
	var parts: Array = [
		[MeshKit.cyl(0.12, 0.1, 0.6, 8), MeshKit.at(Vector3(-0.15, 0.3, 0)), fur],
		[MeshKit.cyl(0.12, 0.1, 0.6, 8), MeshKit.at(Vector3(0.15, 0.3, 0)), fur],
		[MeshKit.sphere(0.13, 8), MeshKit.at(Vector3(-0.15, 0.06, 0.08), Vector3(1.0, 0.6, 1.5)), mane],
		[MeshKit.sphere(0.13, 8), MeshKit.at(Vector3(0.15, 0.06, 0.08), Vector3(1.0, 0.6, 1.5)), mane],
		[MeshKit.sphere(0.36, 12), MeshKit.at(Vector3(0, 0.95, 0), Vector3(1.0, 1.15, 0.85)), shirt],
		[MeshKit.box(Vector3(0.3, 0.2, 0.05)), MeshKit.at(Vector3(0, 1.0, 0.31)), Color(1, 1, 1)],
		[MeshKit.sphere(0.42, 14), MeshKit.at(Vector3(0, 1.62, -0.04)), mane],
		[MeshKit.sphere(0.3, 14), MeshKit.at(Vector3(0, 1.62, 0.12)), fur],
		[MeshKit.sphere(0.13, 10), MeshKit.at(Vector3(0, 1.52, 0.36), Vector3(1.2, 0.8, 0.8)), Color(1.0, 0.9, 0.7)],
		[MeshKit.sphere(0.05, 8), MeshKit.at(Vector3(0, 1.58, 0.45)), Color(0.3, 0.15, 0.1)],
		[MeshKit.sphere(0.055, 8), MeshKit.at(Vector3(-0.11, 1.72, 0.36)), Color(1, 1, 1)],
		[MeshKit.sphere(0.055, 8), MeshKit.at(Vector3(0.11, 1.72, 0.36)), Color(1, 1, 1)],
		[MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(-0.11, 1.72, 0.41)), Color(0.05, 0.05, 0.1)],
		[MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(0.11, 1.72, 0.41)), Color(0.05, 0.05, 0.1)],
		[MeshKit.sphere(0.09, 8), MeshKit.at(Vector3(-0.24, 1.88, 0.0)), fur],
		[MeshKit.sphere(0.09, 8), MeshKit.at(Vector3(0.24, 1.88, 0.0)), fur],
		[MeshKit.cyl(0.03, 0.03, 0.5, 6), MeshKit.at(Vector3(0, 0.6, -0.4), Vector3.ONE, Vector3(-0.9, 0, 0)), fur],
		[MeshKit.sphere(0.07, 8), MeshKit.at(Vector3(0, 0.45, -0.62)), mane],
	]
	var body := MeshInstance3D.new()
	body.mesh = MeshKit.merge(parts)
	body.material_override = MeshKit.vertex_material(main.mats)
	mascot.add_child(body)
	var arm_parts: Array = [
		[MeshKit.cyl(0.07, 0.07, 0.5, 8), MeshKit.at(Vector3(0, -0.25, 0)), fur],
		[MeshKit.sphere(0.1, 8), MeshKit.at(Vector3(0, -0.52, 0)), Color(1.0, 0.9, 0.7)],
	]
	var arm_mesh := MeshKit.merge(arm_parts)
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(float(sx) * 0.38, 1.25, 0)
		mascot.add_child(arm)
		var am := MeshInstance3D.new()
		am.mesh = arm_mesh
		am.material_override = MeshKit.vertex_material(main.mats)
		arm.add_child(am)
		mascot_arms.append(arm)


## "goal": jump and spin with the arms up · "save": clap · "cup": dance.
func mascot_cheer(kind: String) -> void:
	mascot_mode = kind
	mascot_t = 0.0


func _animate_mascot(delta: float) -> void:
	if mascot == null:
		return
	mascot_t += delta
	var y := 0.0
	var spin := 0.0
	var arm_a := 0.25 + 0.1 * sin(t * 2.0)
	var arm_swing := 0.0
	match mascot_mode:
		"goal":
			y = absf(sin(mascot_t * 7.0)) * 0.45
			spin = mascot_t * 6.0
			arm_a = 2.7
			if mascot_t > 2.2:
				mascot_mode = ""
		"save":
			arm_a = 1.3
			arm_swing = 0.5 * sin(mascot_t * 16.0)
			y = absf(sin(mascot_t * 5.0)) * 0.12
			if mascot_t > 2.0:
				mascot_mode = ""
		"cup":
			y = absf(sin(mascot_t * 6.0)) * 0.3
			spin = sin(mascot_t * 2.0) * 0.8
			arm_a = 2.5 + 0.4 * sin(mascot_t * 8.0)
		_:
			y = absf(sin(t * 2.4)) * 0.04
			spin = sin(t * 0.7) * 0.25
	mascot.position.y = y
	mascot.rotation.y = mascot_home_yaw + spin
	for i in mascot_arms.size():
		var sd := -1.0 if i == 0 else 1.0
		mascot_arms[i].rotation = Vector3(-arm_swing * 1.2, 0.0, sd * (arm_a + arm_swing))


# --- The CUP ---------------------------------------------------------------------------------

func _build_trophy() -> void:
	var gold := Color(1.0, 0.8, 0.22)
	var parts: Array = [
		[MeshKit.box(Vector3(0.3, 0.1, 0.3)), MeshKit.at(Vector3(0, 0.05, 0)), Color(0.25, 0.15, 0.08)],
		[MeshKit.cyl(0.1, 0.13, 0.06, 14), MeshKit.at(Vector3(0, 0.13, 0)), gold],
		[MeshKit.cyl(0.03, 0.05, 0.22, 10), MeshKit.at(Vector3(0, 0.27, 0)), gold],
		[MeshKit.cyl(0.19, 0.06, 0.3, 16), MeshKit.at(Vector3(0, 0.53, 0)), gold],
		[MeshKit.cyl(0.2, 0.2, 0.03, 16), MeshKit.at(Vector3(0, 0.69, 0)), gold.lightened(0.2)],
		[MeshKit.cyl(0.035, 0.035, 0.22, 8), MeshKit.at(Vector3(-0.22, 0.56, 0), Vector3.ONE, Vector3(0, 0, 0.35)), gold],
		[MeshKit.cyl(0.035, 0.035, 0.22, 8), MeshKit.at(Vector3(0.22, 0.56, 0), Vector3.ONE, Vector3(0, 0, -0.35)), gold],
		[MeshKit.sphere(0.06, 8), MeshKit.at(Vector3(0, 0.5, 0.17)), Color(1.0, 0.3, 0.35)],
	]
	trophy = Node3D.new()
	add_child(trophy)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.merge(parts)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.6
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.2)
	m.emission_energy_multiplier = 0.4
	mi.material_override = m
	trophy.add_child(mi)
	var sparkle := CPUParticles3D.new()
	sparkle.amount = 16
	sparkle.lifetime = 1.0
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkle.emission_sphere_radius = 0.3
	sparkle.gravity = Vector3(0, 0.3, 0)
	sparkle.initial_velocity_min = 0.0
	sparkle.initial_velocity_max = 0.2
	sparkle.mesh = main.sphere_mesh(0.012)
	sparkle.material_override = main.make_material(Color(1.0, 0.95, 0.6), 3.0)
	sparkle.position = Vector3(0, 0.5, 0)
	trophy.add_child(sparkle)
	trophy.visible = false


## The cup floats at `pos` (world), size s; pos == Vector3.INF hides it.
func show_trophy(pos: Vector3, s: float = 1.0) -> void:
	if trophy == null:
		_build_trophy()
	trophy.visible = pos != Vector3.INF
	if trophy.visible:
		trophy.global_position = pos
		trophy.scale = Vector3.ONE * s


## Confetti from both sides of the goal (goals and the cup ceremony).
func confetti_cannons() -> void:
	for sx in [-1.0, 1.0]:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 50
		p.lifetime = 2.2
		p.explosiveness = 0.85
		p.direction = Vector3(-float(sx) * 0.4, 1.0, 0.5)
		p.spread = 25.0
		p.initial_velocity_min = 7.0
		p.initial_velocity_max = 10.0
		p.gravity = Vector3(0, -3.0, 0)
		p.damping_min = 1.5
		p.damping_max = 2.5
		p.angular_velocity_min = -400.0
		p.angular_velocity_max = 400.0
		p.mesh = main.box_mesh(Vector3(0.06, 0.03, 0.005))
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		p.material_override = m
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1, 0.3, 0.3), Color(1, 0.85, 0.2), Color(0.3, 1, 0.4), Color(0.3, 0.6, 1), Color(0.9, 0.4, 1)])
		p.color_initial_ramp = g
		add_child(p)
		p.position = Vector3(float(sx) * 5.0, 0.3, 1.0)
		p.emitting = true
		get_tree().create_timer(2.8).timeout.connect(p.queue_free)


## Fireworks high over the far stand (seen by the keeper) and over the goal (seen by the TV).
func fireworks(count: int = 3) -> void:
	var cols: Array[Color] = [Color(1.0, 0.4, 0.3), Color(1.0, 0.85, 0.3), Color(0.4, 0.8, 1.0), Color(0.5, 1.0, 0.5), Color(0.9, 0.5, 1.0)]
	for k in count:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 60
		p.lifetime = 1.8
		p.explosiveness = 1.0
		p.spread = 180.0
		p.initial_velocity_min = 5.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, -2.0, 0)
		p.damping_min = 1.2
		p.damping_max = 2.0
		p.scale_amount_min = 1.5
		p.scale_amount_max = 2.5
		p.mesh = main.sphere_mesh(0.08)
		p.material_override = main.make_material(cols[(k + int(t * 3.0)) % cols.size()], 3.0)
		add_child(p)
		var far := k % 2 == 0
		p.position = Vector3(randf_range(-14.0, 14.0), randf_range(14.0, 20.0), randf_range(35.0, 50.0) if far else randf_range(-14.0, -6.0))
		get_tree().create_timer(0.3 * k).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.emitting = true)
		get_tree().create_timer(2.6 + 0.3 * k).timeout.connect(p.queue_free)


func _process(delta: float) -> void:
	t += delta
	if net_back != null:
		net_bulge = maxf(0.0, net_bulge - delta * 1.8)
		var b := sin(net_bulge * PI) * 0.6 if net_bulge > 0.0 else 0.0
		net_back.position.z = -2.0 - b
	_animate_mascot(delta)
	if trophy != null and trophy.visible:
		trophy_spin += delta
		trophy.rotation.y = trophy_spin * 1.2
