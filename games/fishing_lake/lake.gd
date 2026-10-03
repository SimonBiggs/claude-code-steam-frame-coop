extends Node3D
## The scenery: a round lake with a cheap wavy water shader, a wooden jetty, grassy banks with
## trees and reeds, distant hills, a gradient sky dome that turns to sunset, the trophy board and
## the aquarium on the jetty. Everything is procedural and kept to a handful of draw calls.

const LAKE_C := Vector3(0.0, 0.0, -10.0)  # centre of the round lake (water level y = 0)
const LAKE_R := 22.0
const DECK := 0.7  # jetty deck / shore height
const JETTY_END_Z := 4.0  # the jetty runs from the shore (SHORE_Z) out to here
const SHORE_Z := 12.0
const JETTY_HALF := 0.85  # walkable half width of the jetty

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec3 deep_col = vec3(0.05, 0.3, 0.42);
uniform vec3 sky_col = vec3(0.7, 0.85, 1.0);
uniform vec3 glint_col = vec3(1.0, 1.0, 0.9);
varying vec3 wpos;

float wave(vec2 p, float t) {
	return sin(p.x * 0.55 + t * 1.1) * 0.035 + sin(p.y * 0.8 - t * 0.9) * 0.028
		+ sin((p.x + p.y) * 1.7 + t * 2.0) * 0.01;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = wave(w.xz, TIME);
	float hx = wave(w.xz + vec2(0.2, 0.0), TIME);
	float hz = wave(w.xz + vec2(0.0, 0.2), TIME);
	VERTEX.y += h;
	NORMAL = normalize(vec3(-(hx - h) / 0.2, 1.0, -(hz - h) / 0.2));
	wpos = w;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	float ripple = sin(wpos.x * 3.1 + TIME * 1.3) * sin(wpos.z * 2.7 - TIME * 1.1);
	vec3 col = mix(deep_col, sky_col, clamp(fres * 0.85 + 0.08, 0.0, 1.0));
	col += glint_col * smoothstep(0.9, 1.0, ripple) * 0.18;
	ALBEDO = col;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	ALPHA = mix(0.66, 0.95, fres);
}
"""

const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;
uniform vec3 top_col = vec3(0.3, 0.55, 0.95);
uniform vec3 horizon_col = vec3(0.78, 0.9, 1.0);
uniform vec3 sun_col = vec3(1.0, 0.95, 0.8);
uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);
varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_col, top_col, pow(up, 0.55));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_col * (pow(s, 600.0) * 3.0 + pow(s, 12.0) * 0.35);
	ALBEDO = col;
}
"""

var main
var water_mat: ShaderMaterial
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var env: Environment
var board_label: Label3D
var tank_root: Node3D
var tank_fish: Array[MeshInstance3D] = []
var lantern_mat: StandardMaterial3D
var t := 0.0


func build() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.9, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.95, 1.0)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)
	_build_sky()
	_build_water()
	_build_terrain()
	_build_jetty()
	_build_plants()
	_build_board()
	_build_tank()


func _build_sky() -> void:
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 140.0
	sm.height = 280.0
	sm.radial_segments = 20
	sm.rings = 10
	dome.mesh = sm
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = SKY_SHADER
	sky_mat.render_priority = -100
	dome.material_override = sky_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)


func _build_water() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var r: float = LAKE_R + 3.0
	pm.size = Vector2(r * 2.0, r * 2.0)
	pm.subdivide_width = 36
	pm.subdivide_depth = 36
	w.mesh = pm
	water_mat = ShaderMaterial.new()
	water_mat.shader = Shader.new()
	water_mat.shader.code = WATER_SHADER
	w.material_override = water_mat
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.position = LAKE_C
	add_child(w)
	# A dark lake bed, so the water reads as deep in the middle.
	var bed := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = LAKE_R + 1.0
	cm.bottom_radius = LAKE_R - 4.0
	cm.height = 1.6
	cm.radial_segments = 32
	cm.rings = 1
	bed.mesh = cm
	bed.material_override = main.make_material(Color(0.12, 0.22, 0.2), 0.0)
	bed.position = LAKE_C + Vector3(0, -2.1, 0)
	add_child(bed)


## Banks: rings of vertices rising from the shoreline sand to grass and far hills.
func _build_terrain() -> void:
	var radii: Array[float] = [LAKE_R - 2.0, LAKE_R + 0.4, LAKE_R + 2.5, LAKE_R + 10.0, 50.0, 75.0, 110.0]
	var heights: Array[float] = [-1.2, 0.45, 0.62, 0.66, 1.6, 7.0, 16.0]
	var cols: Array[Color] = [Color(0.55, 0.5, 0.35), Color(0.85, 0.78, 0.55), Color(0.42, 0.68, 0.3),
		Color(0.38, 0.65, 0.28), Color(0.32, 0.55, 0.26), Color(0.3, 0.45, 0.3), Color(0.45, 0.5, 0.6)]
	var seg := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector3 = LAKE_C
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bumps: Array[float] = []
	for i in seg:
		bumps.append(rng.randf_range(-1.0, 1.0))
	for ri in radii.size() - 1:
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var b0 := bumps[i]
			var b1 := bumps[(i + 1) % seg]
			var p00 := _ring_point(c, a0, radii[ri], heights[ri], b0, ri)
			var p01 := _ring_point(c, a1, radii[ri], heights[ri], b1, ri)
			var p10 := _ring_point(c, a0, radii[ri + 1], heights[ri + 1], b0, ri + 1)
			var p11 := _ring_point(c, a1, radii[ri + 1], heights[ri + 1], b1, ri + 1)
			# Clockwise seen from above (Godot's front face), with normals tilted by the slope.
			var slope := (heights[ri + 1] - heights[ri]) / (radii[ri + 1] - radii[ri])
			var n0 := (Vector3.UP - Vector3(sin(a0), 0.0, cos(a0)) * slope).normalized()
			var n1 := (Vector3.UP - Vector3(sin(a1), 0.0, cos(a1)) * slope).normalized()
			for v in [[p00, cols[ri], n0], [p11, cols[ri + 1], n1], [p10, cols[ri + 1], n0],
					[p00, cols[ri], n0], [p01, cols[ri], n1], [p11, cols[ri + 1], n1]]:
				var vv: Array = v
				st.set_color(vv[1])
				st.set_normal(vv[2])
				st.add_vertex(vv[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)


func _ring_point(c: Vector3, a: float, r: float, h: float, bump: float, ri: int) -> Vector3:
	var hh := h
	if ri >= 4:
		hh += bump * h * 0.35
	elif ri == 3:
		hh += bump * 0.15
	return c + Vector3(sin(a) * r, hh, cos(a) * r)


func _build_jetty() -> void:
	var deck: float = DECK
	var z0: float = JETTY_END_Z
	var z1: float = SHORE_Z + 1.0
	var wood: StandardMaterial3D = main.make_material(Color(0.62, 0.45, 0.28), 0.0)
	var dark: StandardMaterial3D = main.make_material(Color(0.4, 0.28, 0.18), 0.0)
	var d := MeshInstance3D.new()
	d.mesh = main.box_mesh(Vector3(2.0, 0.1, z1 - z0))
	d.material_override = wood
	d.position = Vector3(0, deck - 0.05, (z0 + z1) * 0.5)
	add_child(d)
	# Plank lines, as one thin strip mesh per side.
	for s in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		edge.mesh = main.box_mesh(Vector3(0.12, 0.14, z1 - z0))
		edge.material_override = dark
		edge.position = Vector3(s * 0.96, deck - 0.04, (z0 + z1) * 0.5)
		add_child(edge)
	var z := z0 + 0.2
	while z < SHORE_Z:
		for s in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = main.cyl_mesh(0.09, 0.09, deck + 1.2, 8)
			post.material_override = dark
			post.position = Vector3(s * 0.95, (deck - 1.2) * 0.5 + 0.05, z)
			add_child(post)
		z += 2.6
	# A lantern on a pole at the end of the jetty that lights up at sunset.
	var pole := MeshInstance3D.new()
	pole.mesh = main.cyl_mesh(0.04, 0.05, 1.7, 8)
	pole.material_override = dark
	pole.position = Vector3(0.9, deck + 0.85, z0 + 0.3)
	add_child(pole)
	var lamp := MeshInstance3D.new()
	lamp.mesh = main.sphere_mesh(0.11)
	lantern_mat = StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(1.0, 0.85, 0.5)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = Color(1.0, 0.7, 0.3)
	lantern_mat.emission_energy_multiplier = 0.0
	lamp.material_override = lantern_mat
	lamp.position = Vector3(0.9, deck + 1.75, z0 + 0.3)
	add_child(lamp)
	# A little boathouse on the shore.
	var hut := MeshInstance3D.new()
	hut.mesh = main.box_mesh(Vector3(3.0, 2.0, 2.4))
	hut.material_override = main.make_material(Color(0.75, 0.35, 0.3), 0.0)
	hut.position = Vector3(-6.5, deck + 1.0, SHORE_Z + 3.4)
	add_child(hut)
	var roof := MeshInstance3D.new()
	var pr := PrismMesh.new()
	pr.size = Vector3(3.4, 1.1, 2.8)
	roof.mesh = pr
	roof.material_override = main.make_material(Color(0.35, 0.3, 0.32), 0.0)
	roof.position = Vector3(-6.5, deck + 2.55, SHORE_Z + 3.4)
	add_child(roof)


func _multimesh(mesh: Mesh, mat: Material, xforms: Array[Transform3D], colors: Array[Color] = []) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i % colors.size()])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var c: Vector3 = LAKE_C
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var crown_cols: Array[Color] = []
	var n := 0
	while n < 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(LAKE_R + 4.0, 44.0)
		var p := c + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if p.z > SHORE_Z - 2.0 and absf(p.x) < 9.0:
			continue  # keep the walkable shore by the jetty clear
		var h := rng.randf_range(2.5, 5.5)
		p.y = 0.6 + clampf((r - LAKE_R - 10.0) / 30.0, 0.0, 1.0) * 1.0
		trunks.append(Transform3D(Basis().scaled(Vector3(1.0, h * 0.4, 1.0)), p + Vector3(0, h * 0.2, 0)))
		crowns.append(Transform3D(Basis().scaled(Vector3(h * 0.35, h * 0.75, h * 0.35)), p + Vector3(0, h * 0.4 + h * 0.37, 0)))
		crown_cols.append(Color(0.18, 0.45, 0.22).lerp(Color(0.3, 0.55, 0.2), rng.randf()))
		n += 1
	var trunk_mesh: Mesh = main.cyl_mesh(0.15, 0.2, 1.0, 6)
	_multimesh(trunk_mesh, main.make_material(Color(0.4, 0.28, 0.18), 0.0), trunks)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1
	var leaf := StandardMaterial3D.new()
	leaf.vertex_color_use_as_albedo = true
	leaf.roughness = 0.9
	_multimesh(cone, leaf, crowns, crown_cols)
	# Reeds along the shoreline and lily pads on the water.
	var reeds: Array[Transform3D] = []
	for i in 70:
		var a := rng.randf() * TAU
		var p := c + Vector3(sin(a), 0.0, cos(a)) * (LAKE_R - rng.randf_range(0.2, 1.4))
		if p.z > SHORE_Z - 3.0 and absf(p.x) < 2.5:
			continue
		var h := rng.randf_range(0.6, 1.3)
		var b := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(1, 0, 0), rng.randf_range(-0.15, 0.15))
		reeds.append(Transform3D(b.scaled(Vector3(1.0, h, 1.0)), p + Vector3(0, h * 0.5 - 0.1, 0)))
	_multimesh(main.box_mesh(Vector3(0.04, 1.0, 0.04)), main.make_material(Color(0.45, 0.6, 0.25), 0.0), reeds)
	var pads: Array[Transform3D] = []
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, LAKE_R - 2.0)
		var p := c + Vector3(sin(a) * r, 0.03, cos(a) * r)
		if p.z > JETTY_END_Z - 3.0 and absf(p.x) < 4.0:
			continue
		var s := rng.randf_range(0.25, 0.45)
		pads.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s)), p))
	_multimesh(main.cyl_mesh(1.0, 1.0, 0.02, 10), main.make_material(Color(0.25, 0.55, 0.25), 0.0), pads)


## The trophy board stands in the shallows to the left of the jetty end, facing the angler.
func _build_board() -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(-3.6, 0.0, JETTY_END_Z - 1.2)
	var face := Vector3(0.0, 0.0, JETTY_END_Z + 1.0) - root.position
	root.rotation.y = atan2(face.x, face.z)
	var dark: StandardMaterial3D = main.make_material(Color(0.4, 0.28, 0.18), 0.0)
	for s in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = main.cyl_mesh(0.08, 0.08, 3.6, 8)
		post.material_override = dark
		post.position = Vector3(s * 1.3, 1.3, -0.05)
		root.add_child(post)
	var panel := MeshInstance3D.new()
	panel.mesh = main.box_mesh(Vector3(2.9, 1.9, 0.08))
	panel.material_override = main.make_material(Color(0.55, 0.38, 0.22), 0.0)
	panel.position = Vector3(0, 2.2, -0.1)
	root.add_child(panel)
	board_label = Label3D.new()
	board_label.font_size = 64
	board_label.pixel_size = 0.0042
	board_label.outline_size = 14
	board_label.modulate = Color(1.0, 0.97, 0.85)
	board_label.width = 640.0
	board_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_label.position = Vector3(0, 2.2, -0.04)
	root.add_child(board_label)


## A small glass aquarium on the jetty where every catch of the day swims around.
func _build_tank() -> void:
	tank_root = Node3D.new()
	add_child(tank_root)
	tank_root.position = Vector3(-0.62, DECK, JETTY_END_Z + 1.6)
	var stand := MeshInstance3D.new()
	stand.mesh = main.box_mesh(Vector3(0.6, 0.5, 0.4))
	stand.material_override = main.make_material(Color(0.4, 0.28, 0.18), 0.0)
	stand.position = Vector3(0, 0.25, 0)
	tank_root.add_child(stand)
	var glass := MeshInstance3D.new()
	glass.mesh = main.box_mesh(Vector3(0.62, 0.4, 0.42))
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.85, 1.0, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.1
	glass.material_override = gm
	glass.position = Vector3(0, 0.7, 0)
	tank_root.add_child(glass)
	var l := Label3D.new()
	l.text = "AQUARIUM"
	l.font_size = 40
	l.pixel_size = 0.0018
	l.outline_size = 10
	l.position = Vector3(0, 0.3, 0.205)
	tank_root.add_child(l)


## The fish in the tank follow the day's catches (kinds), swimming in little circles.
func update_tank(catches: Array, delta: float) -> void:
	t += delta
	var shown: Array[int] = []
	for k in catches:
		var ki: int = k
		var d: Dictionary = main.FishScript.TYPES[ki]
		if not bool(d.get("junk", false)) or ki == main.FishScript.CHEST:
			shown.append(ki)
	while shown.size() > 10:
		shown.pop_front()
	for i in shown.size():
		if i >= tank_fish.size():
			var m := MeshInstance3D.new()
			m.mesh = main.sphere_mesh(0.5)
			tank_root.add_child(m)
			tank_fish.append(m)
		var f := tank_fish[i]
		var kind: int = shown[i]
		if int(f.get_meta("kind", -1)) != kind:
			f.set_meta("kind", kind)
			var d: Dictionary = main.FishScript.TYPES[kind]
			var col: Color = d["col"]
			f.material_override = main.make_material(col, 0.6 if kind == main.FishScript.GOLDEN else 0.05)
			var s := 0.07 if kind == main.FishScript.CHEST else 0.05
			f.scale = Vector3(s * 0.5, s * 0.6, s * 1.6) if kind != main.FishScript.CHEST else Vector3(s, s * 0.8, s * 1.2)
		f.visible = true
		var a := t * (0.6 + 0.07 * i) + i * 1.9
		f.position = Vector3(sin(a) * 0.2, 0.6 + 0.05 * sin(t * 1.3 + i) + (i % 3) * 0.06, cos(a) * 0.12)
		f.rotation.y = a + PI * 0.5
	for i in range(shown.size(), tank_fish.size()):
		tank_fish[i].visible = false


## Day -> sunset (p = 0..1): sky, sun, water and lantern colours.
func set_daylight(p: float, vr: bool) -> void:
	p = clampf(p, 0.0, 1.0)
	var top := Color(0.3, 0.55, 0.95).lerp(Color(0.3, 0.25, 0.55), p)
	var hor := Color(0.78, 0.9, 1.0).lerp(Color(1.0, 0.55, 0.32), smoothstep(0.3, 1.0, p))
	var sun_c := Color(1.0, 0.97, 0.88).lerp(Color(1.0, 0.55, 0.25), smoothstep(0.4, 1.0, p))
	var elev := lerpf(deg_to_rad(55.0), deg_to_rad(5.0), p)
	var az := deg_to_rad(200.0)
	var sun_dir := Vector3(sin(az) * cos(elev), sin(elev), cos(az) * cos(elev))
	sky_mat.set_shader_parameter("top_col", Vector3(top.r, top.g, top.b))
	sky_mat.set_shader_parameter("horizon_col", Vector3(hor.r, hor.g, hor.b))
	sky_mat.set_shader_parameter("sun_col", Vector3(sun_c.r, sun_c.g, sun_c.b))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	water_mat.set_shader_parameter("sky_col", Vector3(hor.r, hor.g, hor.b).lerp(Vector3(top.r, top.g, top.b), 0.3))
	var deep := Color(0.05, 0.3, 0.42).lerp(Color(0.12, 0.12, 0.3), p)
	water_mat.set_shader_parameter("deep_col", Vector3(deep.r, deep.g, deep.b))
	water_mat.set_shader_parameter("glint_col", Vector3(sun_c.r, sun_c.g, sun_c.b))
	env.background_color = hor
	env.ambient_light_color = Color(0.9, 0.95, 1.0).lerp(Color(1.0, 0.7, 0.6), p)
	env.ambient_light_energy = lerpf(0.6, 0.45, p)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = sun_c
	sun.light_energy = lerpf(1.1, 0.7, p)
	lantern_mat.emission_energy_multiplier = smoothstep(0.55, 0.9, p) * 3.0
	if vr:
		sun.shadow_enabled = false
