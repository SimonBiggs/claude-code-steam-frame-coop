extends Node3D
## The stadium: a striped night-time pitch with markings, a full-size goal (7.32 x 2.44 m) with a net,
## four stands packed with a bouncing crowd (one MultiMesh each, animated in a shader), floodlights,
## advertising boards and two big scoreboards (one facing the keeper, one facing the strikers).
## Goal line at z = 0, the pitch runs towards +z, penalty spot at z = 11.

const CROWD_SHADER := """
shader_type spatial;
uniform float excite = 0.0;
varying vec3 col;
void vertex() {
	float ph = float(INSTANCE_ID) * 1.618;
	float hop = excite * max(0.0, sin(TIME * 10.0 + ph * 5.0)) * 0.5 + 0.05 * sin(TIME * 2.0 + ph);
	VERTEX.y += hop;
	col = COLOR.rgb;
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.9;
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

var main
var crowd_mat: ShaderMaterial
var net_back: MeshInstance3D
var board_keeper: Label3D  # far end, faces the keeper
var board_tv: Label3D  # behind the goal, faces the strikers' cameras
var net_bulge := 0.0


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
	_build_pitch()
	_build_goal()
	_build_stands()
	_build_lights_and_boards()


func _box(size: Vector3, pos: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	b.mesh = main.box_mesh(size)
	b.material_override = main.make_material(color, glow)
	b.position = pos
	add_child(b)
	return b


func _build_pitch() -> void:
	# Base grass plus mown stripes across the pitch.
	_box(Vector3(80, 0.02, 90), Vector3(0, -0.011, 25), Color(0.16, 0.42, 0.16))
	for i in 8:
		_box(Vector3(70, 0.002, 4.0), Vector3(0, 0.0, -6.0 + i * 8.0 + 2.0), Color(0.2, 0.5, 0.2))
	var w := Color(0.95, 0.97, 0.95)
	var lw := 0.12
	_box(Vector3(70, 0.006, lw), Vector3(0, 0.004, 0), w)  # goal line
	# Goal area (5.5 m) and penalty area (16.5 m).
	_box(Vector3(18.32, 0.006, lw), Vector3(0, 0.004, 5.5), w)
	_box(Vector3(lw, 0.006, 5.5), Vector3(-9.16, 0.004, 2.75), w)
	_box(Vector3(lw, 0.006, 5.5), Vector3(9.16, 0.004, 2.75), w)
	_box(Vector3(40.32, 0.006, lw), Vector3(0, 0.004, 16.5), w)
	_box(Vector3(lw, 0.006, 16.5), Vector3(-20.16, 0.004, 8.25), w)
	_box(Vector3(lw, 0.006, 16.5), Vector3(20.16, 0.004, 8.25), w)
	# Penalty arc ("the D") as a few segments.
	for i in 7:
		var a := deg_to_rad(-52.0 + i * 17.3)
		var seg := _box(Vector3(2.7, 0.006, lw), Vector3(sin(a) * 9.15, 0.004, 11.0 + cos(a) * 9.15), w)
		seg.rotation.y = -a
	# Halfway line far away.
	_box(Vector3(70, 0.006, lw), Vector3(0, 0.004, 52.5), w)
	var spot := MeshInstance3D.new()
	spot.mesh = main.cyl_mesh(0.12, 0.12, 0.006, 12)
	spot.material_override = main.make_material(w, 0.0)
	spot.position = Vector3(0, 0.005, 11.0)
	add_child(spot)


func _build_goal() -> void:
	var white: StandardMaterial3D = main.make_material(Color(1, 1, 1), 0.25)
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = main.cyl_mesh(0.06, 0.06, 2.50, 12)
		post.material_override = white
		post.position = Vector3(sx * 3.72, 1.25, 0)
		add_child(post)
		# Back stanchions.
		var st := MeshInstance3D.new()
		st.mesh = main.cyl_mesh(0.025, 0.025, 2.0, 6)
		st.material_override = main.make_material(Color(0.8, 0.8, 0.85), 0.0)
		st.position = Vector3(sx * 3.72, 2.44, -1.0)
		st.rotation.x = PI * 0.5
		add_child(st)
		var st2 := MeshInstance3D.new()
		st2.mesh = main.cyl_mesh(0.025, 0.025, 2.44, 6)
		st2.material_override = st.material_override
		st2.position = Vector3(sx * 3.72, 1.22, -2.0)
		add_child(st2)
	var bar := MeshInstance3D.new()
	bar.mesh = main.cyl_mesh(0.06, 0.06, 7.56, 12)
	bar.material_override = white
	bar.position = Vector3(0, 2.50, 0)
	bar.rotation.z = PI * 0.5
	add_child(bar)
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


func _build_stands() -> void:
	var shader := Shader.new()
	shader.code = CROWD_SHADER
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = shader
	# [centre, length along the stand, yaw so rows climb away from the pitch]
	var stands: Array = [
		[Vector3(0, 0, 62), 70.0, 0.0],  # far end behind the strikers (faces the keeper)
		[Vector3(-34, 0, 22), 56.0, -PI * 0.5],
		[Vector3(34, 0, 22), 56.0, PI * 0.5],
		[Vector3(0, 0, -12), 70.0, PI],  # behind the goal
	]
	var shirts: Array[Color] = [Color(0.9, 0.15, 0.15), Color(1, 1, 1), Color(0.15, 0.35, 0.95), Color(1.0, 0.85, 0.1),
		Color(0.95, 0.5, 0.1), Color(0.2, 0.8, 0.3), Color(0.6, 0.3, 0.9), Color(0.1, 0.1, 0.15)]
	var person := BoxMesh.new()
	person.size = Vector3(0.6, 0.9, 0.45)
	for s in stands:
		var sa: Array = s
		var center: Vector3 = sa[0]
		var length: float = sa[1]
		var yaw: float = sa[2]
		var stand := Node3D.new()
		stand.position = center
		stand.rotation.y = yaw
		add_child(stand)
		for row in 4:
			var tier := MeshInstance3D.new()
			tier.mesh = main.box_mesh(Vector3(length, 1.2 + row * 1.2, 1.6))
			tier.material_override = main.make_material(Color(0.25, 0.27, 0.33) if row % 2 == 0 else Color(0.32, 0.34, 0.4), 0.0)
			tier.position = Vector3(0, (1.2 + row * 1.2) * 0.5, row * 1.6)
			stand.add_child(tier)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = person
		var cols := int(length / 1.0)
		mm.instance_count = cols * 4
		var k := 0
		for row in 4:
			for c in cols:
				var x := -length * 0.5 + 0.5 + c * 1.0 + randf_range(-0.15, 0.15)
				var y := 1.2 + row * 1.2 + 0.45
				mm.set_instance_transform(k, Transform3D(Basis(), Vector3(x, y, row * 1.6)))
				mm.set_instance_color(k, shirts[randi() % shirts.size()])
				k += 1
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = crowd_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.add_child(mi)


func _build_lights_and_boards() -> void:
	for p in [Vector3(-32, 0, -8), Vector3(32, 0, -8), Vector3(-32, 0, 56), Vector3(32, 0, 56)]:
		var pos: Vector3 = p
		var pole := MeshInstance3D.new()
		pole.mesh = main.cyl_mesh(0.35, 0.5, 22.0, 8)
		pole.material_override = main.make_material(Color(0.4, 0.42, 0.48), 0.0)
		pole.position = pos + Vector3(0, 11, 0)
		add_child(pole)
		var lamp := _box(Vector3(5, 3, 0.5), pos + Vector3(0, 22.5, 0), Color(1.0, 1.0, 0.85), 3.0)
		lamp.look_at(Vector3(0, 0, 20), Vector3.UP)
	# Advertising boards around the pitch.
	var ad_cols: Array[Color] = [Color(1.0, 0.3, 0.2), Color(0.2, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.3, 0.9, 0.4)]
	for i in 6:
		_box(Vector3(10, 0.9, 0.2), Vector3(-27.5 + i * 11.0, 0.45, -4.0), ad_cols[i % 4], 0.8)
		_box(Vector3(10, 0.9, 0.2), Vector3(-27.5 + i * 11.0, 0.45, 57.0), ad_cols[(i + 2) % 4], 0.8)
	for i in 5:
		_box(Vector3(0.2, 0.9, 10), Vector3(-31.0, 0.45, 2.0 + i * 11.0), ad_cols[(i + 1) % 4], 0.8)
		_box(Vector3(0.2, 0.9, 10), Vector3(31.0, 0.45, 2.0 + i * 11.0), ad_cols[(i + 3) % 4], 0.8)
	# Scoreboards.
	_box(Vector3(22, 9, 0.6), Vector3(0, 14, 66), Color(0.05, 0.05, 0.08))
	board_keeper = _make_board_label()
	board_keeper.position = Vector3(0, 14, 65.6)
	board_keeper.rotation.y = PI  # faces -z, towards the goal
	_box(Vector3(18, 7, 0.6), Vector3(0, 12, -16), Color(0.05, 0.05, 0.08))
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


func bulge() -> void:
	net_bulge = 1.0


func _process(delta: float) -> void:
	if net_back != null:
		net_bulge = maxf(0.0, net_bulge - delta * 1.8)
		var b := sin(net_bulge * PI) * 0.6 if net_bulge > 0.0 else 0.0
		net_back.position.z = -2.0 - b
