extends Node3D
## The scenery: a round lake with a cheap wavy water shader (rain rings when it rains), a wooden jetty
## with a bait bucket and tackle box, grassy banks with trees, bushes, flowers, rocks and reeds, a
## lighthouse and a windmill on the far shore, ducks paddling about, clouds drifting across a sky dome
## that goes from morning to sunset to a starry night with a moon, rain and fireflies, the trophy board,
## the fish journal board and the aquarium on the jetty, plus the frenzy bubbles and treasure-map
## markers. Repeated props are MultiMeshes, so it stays a few dozen draw calls.

const FishScript := preload("res://games/fishing_lake/fish.gd")

const LAKE_C := Vector3(0.0, 0.0, -10.0)  # centre of the round lake (water level y = 0)
const LAKE_R := 22.0
const DECK := 0.7  # jetty deck / shore height
const JETTY_END_Z := 4.0  # the jetty runs from the shore (SHORE_Z) out to here
const SHORE_Z := 12.0
const JETTY_HALF := 0.85  # walkable half width of the jetty
const LIGHTHOUSE := Vector3(16.0, 0.5, -34.0)
const WINDMILL := Vector3(-26.0, 0.6, -36.0)
const BOARD_L := Vector3(-3.6, 0.0, JETTY_END_Z - 1.2)
const BOARD_R := Vector3(3.6, 0.0, JETTY_END_Z - 1.2)

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec3 deep_col = vec3(0.05, 0.3, 0.42);
uniform vec3 sky_col = vec3(0.7, 0.85, 1.0);
uniform vec3 glint_col = vec3(1.0, 1.0, 0.9);
uniform float rain = 0.0;
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
	if (rain > 0.01) {
		// Raindrop rings: one per grid cell, each on its own timer.
		vec2 cell = floor(wpos.xz * 1.4);
		vec2 local = fract(wpos.xz * 1.4) - 0.5;
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		float t = fract(TIME * 0.9 + h);
		float ring = 1.0 - smoothstep(0.0, 0.05, abs(length(local) - t * 0.45));
		col += vec3(0.6, 0.7, 0.8) * ring * (1.0 - t) * rain * 0.5;
	}
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
uniform vec3 moon_dir = vec3(-0.35, 0.45, -0.82);
uniform float stars = 0.0;
uniform float sun_vis = 1.0;
varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_col, top_col, pow(up, 0.55));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_col * (pow(s, 600.0) * 3.0 + pow(s, 12.0) * 0.35) * sun_vis;
	if (stars > 0.01) {
		vec3 q = floor(d * 160.0);
		float h = fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + h * 40.0);
		col += vec3(1.0, 0.97, 0.9) * step(0.9965, h) * stars * tw * smoothstep(0.02, 0.2, d.y);
		float m = max(dot(d, normalize(moon_dir)), 0.0);
		col += vec3(1.0, 0.97, 0.85) * (smoothstep(0.9993, 0.9996, m) * 1.4 + pow(m, 40.0) * 0.25) * stars;
	}
	ALBEDO = col;
}
"""

var main
var water_mat: ShaderMaterial
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var env: Environment
var board_label: Label3D
var journal_label: Label3D
var tank_root: Node3D
var tank_fish: Array[MeshInstance3D] = []
var lantern_mat: StandardMaterial3D
var window_mat: StandardMaterial3D
var lighthouse_lamp: StandardMaterial3D
var beam_root: Node3D
var beam_mat: StandardMaterial3D
var blades: Node3D
var clouds_root: Node3D
var cloud_mat: StandardMaterial3D
var rain_far: CPUParticles3D
var rain_near: CPUParticles3D
var rain_mat: StandardMaterial3D
var fireflies: CPUParticles3D
var fireflies2: CPUParticles3D
var ducks: Array[Node3D] = []
var frenzy_root: Node3D
var frenzy_ring: MeshInstance3D
var frenzy_bubbles: CPUParticles3D
var map_root: Node3D
var map_x: Node3D
var map_buoy: Node3D
var map_beam: MeshInstance3D
var map_beam_mat: StandardMaterial3D
var t := 0.0
var night := 0.0
var terrain_bumps: Array[float] = []


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
	_build_landmarks()
	_build_plants()
	_build_board()
	_build_journal_board()
	_build_tank()
	_build_weather()
	_build_ducks()
	_build_markers()


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
	# Puffy clouds: three squashed spheres each, all in one MultiMesh that slowly turns.
	clouds_root = Node3D.new()
	add_child(clouds_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var xf: Array[Transform3D] = []
	for i in 15:
		var a := rng.randf() * TAU
		var r := rng.randf_range(60.0, 100.0)
		var c := Vector3(sin(a) * r, rng.randf_range(24.0, 40.0), cos(a) * r)
		var s := rng.randf_range(0.8, 1.4)
		var along := Vector3(cos(a), 0.0, -sin(a))
		for j in 3:
			var off := along * (float(j) - 1.0) * 6.0 * s + Vector3(0, (1.0 if j == 1 else 0.0) * 1.5 * s, 0)
			var sc := Vector3(7.0, 2.6 + (1.0 if j == 1 else 0.0), 5.0) * s
			xf.append(Transform3D(Basis(Vector3.UP, a).scaled(sc), c + off))
	var cm := SphereMesh.new()
	cm.radius = 1.0
	cm.height = 2.0
	cm.radial_segments = 10
	cm.rings = 5
	cloud_mat = StandardMaterial3D.new()
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.albedo_color = Color(1, 1, 1)
	cloud_mat.disable_fog = true
	_multimesh(cm, cloud_mat, xf, [], clouds_root)


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
	terrain_bumps = bumps
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


## Bank height at a point, following the same rings and bumps as the terrain mesh (for placing props).
func ground_y(p: Vector3) -> float:
	var off := Vector2(p.x - LAKE_C.x, p.z - LAKE_C.z)
	var r := off.length()
	var radii: Array[float] = [LAKE_R - 2.0, LAKE_R + 0.4, LAKE_R + 2.5, LAKE_R + 10.0, 50.0, 75.0, 110.0]
	var heights: Array[float] = [-1.2, 0.45, 0.62, 0.66, 1.6, 7.0, 16.0]
	if r <= radii[0]:
		return heights[0]
	var seg := terrain_bumps.size()
	var a := fposmod(atan2(off.x, off.y), TAU)
	var fi := a / TAU * seg
	var i0 := int(fi) % seg
	var i1 := (i0 + 1) % seg
	var fa := fi - floorf(fi)
	for ri in radii.size() - 1:
		if r <= radii[ri + 1]:
			var h0 := lerpf(_ring_h(heights[ri], ri, terrain_bumps[i0]), _ring_h(heights[ri], ri, terrain_bumps[i1]), fa)
			var h1 := lerpf(_ring_h(heights[ri + 1], ri + 1, terrain_bumps[i0]), _ring_h(heights[ri + 1], ri + 1, terrain_bumps[i1]), fa)
			return lerpf(h0, h1, (r - radii[ri]) / (radii[ri + 1] - radii[ri]))
	return heights[heights.size() - 1]


func _ring_h(h: float, ri: int, bump: float) -> float:
	if ri >= 4:
		return h + bump * h * 0.35
	if ri == 3:
		return h + bump * 0.15
	return h


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
	# Plank gaps across the deck (one MultiMesh) and the edge beams.
	var gaps: Array[Transform3D] = []
	var gz := z0 + 0.25
	while gz < z1:
		gaps.append(Transform3D(Basis(), Vector3(0, deck + 0.002, gz)))
		gz += 0.32
	_multimesh(main.box_mesh(Vector3(1.9, 0.004, 0.025)), dark, gaps)
	for s in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		edge.mesh = main.box_mesh(Vector3(0.12, 0.14, z1 - z0))
		edge.material_override = dark
		edge.position = Vector3(s * 0.96, deck - 0.04, (z0 + z1) * 0.5)
		add_child(edge)
	var posts: Array[Transform3D] = []
	var z := z0 + 0.2
	while z < SHORE_Z:
		for s in [-1.0, 1.0]:
			posts.append(Transform3D(Basis(), Vector3(s * 0.95, (deck - 1.2) * 0.5 + 0.05, z)))
		z += 2.6
	# Two taller mooring posts with rope rings at the very end.
	for s in [-1.0, 1.0]:
		posts.append(Transform3D(Basis().scaled(Vector3(1.0, 1.3, 1.0)), Vector3(s * 0.95, (deck - 1.2) * 0.5 + 0.35, z0 + 0.12)))
	_multimesh(main.cyl_mesh(0.09, 0.09, deck + 1.2, 8), dark, posts)
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
	# Bait bucket and tackle box beside the angler (nice to look down at in VR).
	var bucket := MeshInstance3D.new()
	bucket.mesh = main.cyl_mesh(0.14, 0.11, 0.26, 12)
	bucket.material_override = main.make_material(Color(0.3, 0.55, 0.85), 0.0)
	bucket.position = Vector3(0.62, deck + 0.13, z0 + 1.35)
	add_child(bucket)
	var water_in := MeshInstance3D.new()
	water_in.mesh = main.cyl_mesh(0.125, 0.125, 0.01, 12)
	water_in.material_override = main.make_material(Color(0.2, 0.45, 0.55), 0.2)
	water_in.position = Vector3(0.62, deck + 0.22, z0 + 1.35)
	add_child(water_in)
	var box := MeshInstance3D.new()
	box.mesh = main.box_mesh(Vector3(0.36, 0.16, 0.22))
	box.material_override = main.make_material(Color(0.85, 0.25, 0.2), 0.0)
	box.position = Vector3(0.55, deck + 0.08, z0 + 2.0)
	box.rotation.y = 0.3
	add_child(box)
	var lid := MeshInstance3D.new()
	lid.mesh = main.box_mesh(Vector3(0.38, 0.04, 0.24))
	lid.material_override = main.make_material(Color(0.95, 0.85, 0.3), 0.0)
	lid.position = Vector3(0.55, deck + 0.18, z0 + 2.0)
	lid.rotation.y = 0.3
	add_child(lid)
	# A little boathouse on the shore, with windows that glow at night.
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
	window_mat = StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.35, 0.4, 0.5)
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.8, 0.4)
	window_mat.emission_energy_multiplier = 0.0
	var wins: Array[Transform3D] = []
	for wx in [-0.7, 0.7]:
		wins.append(Transform3D(Basis(), Vector3(-6.5 + float(wx), deck + 1.2, SHORE_Z + 3.4 - 1.21)))
	_multimesh(main.box_mesh(Vector3(0.6, 0.55, 0.02)), window_mat, wins)


## A lighthouse and a windmill on the far shore: something to look at while you wait for a bite.
func _build_landmarks() -> void:
	var white: StandardMaterial3D = main.make_material(Color(0.95, 0.95, 0.92), 0.0)
	var red: StandardMaterial3D = main.make_material(Color(0.85, 0.2, 0.18), 0.0)
	var lh := Node3D.new()
	lh.position = Vector3(LIGHTHOUSE.x, ground_y(LIGHTHOUSE) - 0.3, LIGHTHOUSE.z)
	add_child(lh)
	var tower := MeshInstance3D.new()
	tower.mesh = main.cyl_mesh(0.9, 1.4, 8.0, 14)
	tower.material_override = white
	tower.position = Vector3(0, 3.0, 0)
	lh.add_child(tower)
	var stripes: Array[Transform3D] = []
	for y in [1.2, 3.6]:
		var yy: float = y
		var rr := lerpf(1.4, 0.9, (yy + 1.0) / 8.0) + 0.03
		stripes.append(Transform3D(Basis().scaled(Vector3(rr, 1.0, rr)), Vector3(0, yy, 0)))
	stripes.append(Transform3D(Basis().scaled(Vector3(1.1, 1.0, 1.1)), Vector3(0, 7.9, 0)))
	_multimesh(main.cyl_mesh(1.0, 1.0, 0.9, 14), red, stripes, [], lh)
	var room := MeshInstance3D.new()
	room.mesh = main.cyl_mesh(0.7, 0.7, 1.0, 12)
	lighthouse_lamp = StandardMaterial3D.new()
	lighthouse_lamp.albedo_color = Color(1.0, 0.95, 0.7)
	lighthouse_lamp.emission_enabled = true
	lighthouse_lamp.emission = Color(1.0, 0.85, 0.45)
	lighthouse_lamp.emission_energy_multiplier = 0.3
	room.material_override = lighthouse_lamp
	room.position = Vector3(0, 8.8, 0)
	lh.add_child(room)
	var cap := MeshInstance3D.new()
	cap.mesh = main.cyl_mesh(0.0, 1.0, 1.0, 12)
	cap.material_override = red
	cap.position = Vector3(0, 9.8, 0)
	lh.add_child(cap)
	beam_root = Node3D.new()
	beam_root.position = Vector3(0, 8.8, 0)
	lh.add_child(beam_root)
	var beam := MeshInstance3D.new()
	beam.mesh = main.cyl_mesh(0.25, 2.2, 16.0, 10)
	beam_mat = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.albedo_color = Color(1.0, 0.9, 0.55, 0.0)
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.rotation.z = deg_to_rad(90.0)
	beam.position = Vector3(8.0, 0, 0)
	beam_root.add_child(beam)
	# Windmill: stone tower, a cap and four sails that turn (one merged mesh).
	var wm := Node3D.new()
	wm.position = Vector3(WINDMILL.x, ground_y(WINDMILL) - 0.3, WINDMILL.z)
	add_child(wm)
	var wt := MeshInstance3D.new()
	wt.mesh = main.cyl_mesh(1.1, 1.7, 6.0, 10)
	wt.material_override = main.make_material(Color(0.8, 0.75, 0.65), 0.0)
	wt.position = Vector3(0, 2.4, 0)
	wm.add_child(wt)
	var wcap := MeshInstance3D.new()
	wcap.mesh = main.cyl_mesh(0.0, 1.4, 1.6, 10)
	wcap.material_override = main.make_material(Color(0.45, 0.3, 0.25), 0.0)
	wcap.position = Vector3(0, 6.2, 0)
	wm.add_child(wcap)
	blades = Node3D.new()
	blades.position = Vector3(0, 5.3, 0)
	var face := (Vector3(0, 0, JETTY_END_Z) - WINDMILL)
	face.y = 0.0
	blades.rotation.y = atan2(face.x, face.z)
	wm.add_child(blades)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var b := Basis(Vector3.BACK, TAU * i / 4.0)
		var arm := [Vector3(-0.12, 0.2, 1.2), Vector3(0.12, 0.2, 1.2), Vector3(0.12, 4.0, 1.2), Vector3(-0.12, 4.0, 1.2)]
		var sail := [Vector3(0.12, 1.0, 1.2), Vector3(1.0, 1.0, 1.2), Vector3(1.0, 3.9, 1.2), Vector3(0.12, 3.9, 1.2)]
		for quad in [[arm, Color(0.4, 0.28, 0.2)], [sail, Color(0.95, 0.92, 0.85)]]:
			var qq: Array = quad
			var q: Array = qq[0]
			var col: Color = qq[1]
			for k in [0, 1, 2, 0, 2, 3]:
				var vk: Vector3 = q[int(k)]
				st.set_color(col)
				st.set_normal(b * Vector3.BACK)
				st.add_vertex(b * vk)
	var bm := MeshInstance3D.new()
	bm.mesh = st.commit()
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.material_override = bmat
	blades.add_child(bm)


func _multimesh(mesh: Mesh, mat: Material, xforms: Array[Transform3D], colors: Array[Color] = [], parent: Node3D = null) -> MultiMeshInstance3D:
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
	(parent if parent != null else self).add_child(mi)
	return mi


func _clear_of_landmarks(p: Vector3, r: float) -> bool:
	for lm in [LIGHTHOUSE, WINDMILL]:
		var l: Vector3 = lm
		if Vector2(p.x - l.x, p.z - l.z).length() < r:
			return false
	return true


func _build_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var c: Vector3 = LAKE_C
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var crown_cols: Array[Color] = []
	var n := 0
	while n < 52:
		var a := rng.randf() * TAU
		var r := rng.randf_range(LAKE_R + 4.0, 46.0)
		var p := c + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if p.z > SHORE_Z - 2.0 and absf(p.x) < 9.0:
			continue  # keep the walkable shore by the jetty clear
		if not _clear_of_landmarks(p, 5.0):
			continue
		var h := rng.randf_range(2.5, 5.5)
		p.y = ground_y(p) - 0.1
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
	# Round bushes and flowers on the banks, rocks along the water's edge.
	var bushes: Array[Transform3D] = []
	var bush_cols: Array[Color] = []
	var flowers: Array[Transform3D] = []
	var flower_cols: Array[Color] = []
	var petal: Array[Color] = [Color(1.0, 0.35, 0.45), Color(1.0, 0.85, 0.2), Color(0.85, 0.5, 1.0), Color(1.0, 1.0, 1.0), Color(1.0, 0.6, 0.2)]
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(LAKE_R + 1.5, 34.0)
		var p := c + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if p.z > SHORE_Z - 1.0 and absf(p.x) < 2.5:
			continue
		p.y = ground_y(p)
		var s := rng.randf_range(0.5, 1.1)
		bushes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.8, s)), p + Vector3(0, s * 0.3, 0)))
		bush_cols.append(Color(0.2, 0.5, 0.2).lerp(Color(0.35, 0.6, 0.25), rng.randf()))
	for i in 150:
		var a := rng.randf() * TAU
		var r := rng.randf_range(LAKE_R + 0.8, 30.0)
		var p := c + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if p.z > SHORE_Z - 1.0 and absf(p.x) < 1.3:
			continue
		p.y = ground_y(p) + 0.12
		var s := rng.randf_range(0.06, 0.1)
		flowers.append(Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), p))
		flower_cols.append(petal[rng.randi() % petal.size()])
	var round_m: Mesh = main.sphere_mesh(1.0)
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.roughness = 0.9
	_multimesh(round_m, vc, bushes, bush_cols)
	var vcg := StandardMaterial3D.new()
	vcg.vertex_color_use_as_albedo = true
	vcg.emission_enabled = true
	vcg.emission = Color(0.15, 0.12, 0.1)
	_multimesh(main.sphere_mesh(1.0), vcg, flowers, flower_cols)
	var rocks: Array[Transform3D] = []
	for i in 34:
		var a := rng.randf() * TAU
		var p := c + Vector3(sin(a), 0.0, cos(a)) * (LAKE_R + rng.randf_range(-0.6, 1.2))
		if p.z > SHORE_Z - 3.0 and absf(p.x) < 2.5:
			continue
		p.y = ground_y(p) - 0.05
		var s := rng.randf_range(0.25, 0.7)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.4, s * 0.7, s)), p))
	_multimesh(main.sphere_mesh(1.0), main.make_material(Color(0.55, 0.53, 0.5), 0.0), rocks)
	# Reeds along the shoreline (some with brown cattail heads) and lily pads on the water.
	var reeds: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for i in 80:
		var a := rng.randf() * TAU
		var p := c + Vector3(sin(a), 0.0, cos(a)) * (LAKE_R - rng.randf_range(0.2, 1.4))
		if p.z > SHORE_Z - 3.0 and absf(p.x) < 2.5:
			continue
		var h := rng.randf_range(0.6, 1.3)
		var b := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(1, 0, 0), rng.randf_range(-0.15, 0.15))
		reeds.append(Transform3D(b.scaled(Vector3(1.0, h, 1.0)), p + Vector3(0, h * 0.5 - 0.1, 0)))
		if i % 3 == 0:
			heads.append(Transform3D(b.scaled(Vector3(0.05, 0.14, 0.05)), p + b * Vector3(0, h - 0.1, 0) + Vector3(0, -0.02, 0)))
	_multimesh(main.box_mesh(Vector3(0.04, 1.0, 0.04)), main.make_material(Color(0.45, 0.6, 0.25), 0.0), reeds)
	_multimesh(main.sphere_mesh(1.0), main.make_material(Color(0.45, 0.28, 0.15), 0.0), heads)
	var pads: Array[Transform3D] = []
	var lilies: Array[Transform3D] = []
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, LAKE_R - 2.0)
		var p := c + Vector3(sin(a) * r, 0.03, cos(a) * r)
		if p.z > JETTY_END_Z - 3.0 and absf(p.x) < 4.0:
			continue
		var s := rng.randf_range(0.25, 0.45)
		pads.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s)), p))
		if i % 3 == 0:
			lilies.append(Transform3D(Basis().scaled(Vector3(0.09, 0.06, 0.09)), p + Vector3(s * 0.2, 0.05, 0)))
	_multimesh(main.cyl_mesh(1.0, 1.0, 0.02, 10), main.make_material(Color(0.25, 0.55, 0.25), 0.0), pads)
	_multimesh(main.sphere_mesh(1.0), main.make_material(Color(1.0, 0.6, 0.85), 0.4), lilies)


func _board(pos: Vector3, panel_size: Vector2, wood: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var face := Vector3(0.0, 0.0, JETTY_END_Z + 1.0) - root.position
	root.rotation.y = atan2(face.x, face.z)
	var dark: StandardMaterial3D = main.make_material(Color(0.4, 0.28, 0.18), 0.0)
	var posts: Array[Transform3D] = []
	for s in [-1.0, 1.0]:
		posts.append(Transform3D(Basis().scaled(Vector3(1.0, (panel_size.y + 1.7) / 3.6, 1.0)), Vector3(s * (panel_size.x * 0.5 - 0.15), (panel_size.y + 1.7) * 0.5 - 0.5, -0.05)))
	_multimesh(main.cyl_mesh(0.08, 0.08, 3.6, 8), dark, posts, [], root)
	var panel := MeshInstance3D.new()
	panel.mesh = main.box_mesh(Vector3(panel_size.x, panel_size.y, 0.08))
	panel.material_override = main.make_material(wood, 0.0)
	panel.position = Vector3(0, 1.25 + panel_size.y * 0.5, -0.1)
	root.add_child(panel)
	return root


## The trophy board stands in the shallows to the left of the jetty end, facing the angler.
func _build_board() -> void:
	var root := _board(BOARD_L, Vector2(2.9, 1.9), Color(0.55, 0.38, 0.22))
	board_label = Label3D.new()
	board_label.font_size = 64
	board_label.pixel_size = 0.0036
	board_label.outline_size = 14
	board_label.modulate = Color(1.0, 0.97, 0.85)
	board_label.width = 760.0
	board_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_label.position = Vector3(0, 2.2, -0.04)
	root.add_child(board_label)


## The fish journal: every species you have ever caught (it remembers between games).
func _build_journal_board() -> void:
	var root := _board(BOARD_R, Vector2(2.9, 2.5), Color(0.3, 0.42, 0.5))
	journal_label = Label3D.new()
	journal_label.font_size = 54
	journal_label.pixel_size = 0.0026
	journal_label.outline_size = 12
	journal_label.modulate = Color(0.95, 1.0, 1.0)
	journal_label.width = 1080.0
	journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journal_label.position = Vector3(0, 2.5, -0.04)
	root.add_child(journal_label)


## A small glass aquarium beside the angler where every catch of the day swims around.
func _build_tank() -> void:
	tank_root = Node3D.new()
	add_child(tank_root)
	tank_root.position = Vector3(-0.6, DECK, JETTY_END_Z + 0.75)
	tank_root.rotation.y = deg_to_rad(-25.0)
	var stand := MeshInstance3D.new()
	stand.mesh = main.box_mesh(Vector3(0.6, 0.5, 0.4))
	stand.material_override = main.make_material(Color(0.4, 0.28, 0.18), 0.0)
	stand.position = Vector3(0, 0.25, 0)
	tank_root.add_child(stand)
	var sand := MeshInstance3D.new()
	sand.mesh = main.box_mesh(Vector3(0.58, 0.05, 0.38))
	sand.material_override = main.make_material(Color(0.9, 0.8, 0.55), 0.1)
	sand.position = Vector3(0, 0.53, 0)
	tank_root.add_child(sand)
	var glass := MeshInstance3D.new()
	glass.mesh = main.box_mesh(Vector3(0.62, 0.4, 0.42))
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.85, 1.0, 0.3)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.1
	gm.emission_enabled = true
	gm.emission = Color(0.2, 0.45, 0.6)
	gm.emission_energy_multiplier = 0.3
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
	var shown: Array[int] = []
	for k in catches:
		var ki: int = k
		if FishScript.is_species(ki) or ki == FishScript.CHEST:
			shown.append(ki)
	while shown.size() > 10:
		shown.pop_front()
	for i in shown.size():
		if i >= tank_fish.size():
			var m := MeshInstance3D.new()
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tank_root.add_child(m)
			tank_fish.append(m)
		var f := tank_fish[i]
		var kind: int = shown[i]
		if int(f.get_meta("kind", -1)) != kind:
			f.set_meta("kind", kind)
			var d: Dictionary = FishScript.TYPES[kind]
			if kind == FishScript.CHEST:
				f.mesh = main.box_mesh(Vector3(1.0, 0.7, 0.8))
				f.material_override = main.make_material(d["col"], 0.2)
				f.scale = Vector3.ONE * 0.08
			else:
				f.mesh = main.fish_mesh(kind)
				f.material_override = main.fish_material(kind)
				f.scale = Vector3.ONE * (0.15 / float(d["len"]))
		f.visible = true
		var a := t * (0.6 + 0.07 * i) + i * 1.9
		if kind == FishScript.CHEST:
			f.position = Vector3(-0.15 + 0.1 * (i % 3), 0.58, 0.05)
			f.rotation.y = 0.4
		else:
			f.position = Vector3(sin(a) * 0.2, 0.62 + 0.05 * sin(t * 1.3 + i) + (i % 3) * 0.06, cos(a) * 0.12)
			f.rotation.y = a + PI * 0.5
	for i in range(shown.size(), tank_fish.size()):
		tank_fish[i].visible = false


func _build_weather() -> void:
	rain_mat = StandardMaterial3D.new()
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.albedo_color = Color(0.8, 0.88, 1.0, 0.0)
	var drop: Mesh = main.box_mesh(Vector3(0.012, 0.32, 0.012))
	rain_far = _rain_emitter(drop, 260, Vector3(24.0, 0.5, 24.0), 1.15)
	rain_far.position = LAKE_C + Vector3(0, 14.0, 0)
	rain_near = _rain_emitter(drop, 110, Vector3(5.0, 0.5, 5.0), 0.7)
	rain_near.position = Vector3(0, 9.0, JETTY_END_Z + 1.0)
	fireflies = CPUParticles3D.new()
	fireflies.amount = 36
	fireflies.lifetime = 5.0
	fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fireflies.emission_box_extents = Vector3(9.0, 0.8, 5.0)
	fireflies.direction = Vector3.UP
	fireflies.spread = 180.0
	fireflies.gravity = Vector3.ZERO
	fireflies.initial_velocity_min = 0.1
	fireflies.initial_velocity_max = 0.4
	fireflies.scale_amount_min = 0.6
	fireflies.scale_amount_max = 1.2
	fireflies.mesh = main.sphere_mesh(0.03)
	var ff := StandardMaterial3D.new()
	ff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ff.albedo_color = Color(0.85, 1.0, 0.4)
	fireflies.material_override = ff
	fireflies.emitting = false
	fireflies.position = Vector3(0, DECK + 1.3, SHORE_Z + 1.5)
	add_child(fireflies)
	# A second swarm over the reeds in front of the jetty.
	fireflies2 = fireflies.duplicate() as CPUParticles3D
	fireflies2.emission_box_extents = Vector3(7.0, 0.6, 2.0)
	fireflies2.position = Vector3(0, 1.0, JETTY_END_Z - 4.0)
	add_child(fireflies2)


func _rain_emitter(drop: Mesh, amount: int, box: Vector3, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3.DOWN
	p.spread = 4.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 14.0
	p.mesh = drop
	p.material_override = rain_mat
	p.emitting = false
	p.local_coords = false
	add_child(p)
	return p


## Ducks: a mum with two ducklings and a lone drake, paddling lazy loops (purely for looks, so each
## machine animates its own; they shy away from boats).
func _build_ducks() -> void:
	for i in 4:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var baby := i == 1 or i == 2
		var body_c := Color(1.0, 0.88, 0.3) if baby else (Color(0.55, 0.42, 0.3) if i == 0 else Color(0.85, 0.85, 0.8))
		var head_c := body_c if baby or i == 0 else Color(0.1, 0.45, 0.25)
		FishScript._ellipsoid(st, Vector3(0, 0.1, 0), Vector3(0.14, 0.11, 0.22), -1, 10, 5, body_c)
		FishScript._ellipsoid(st, Vector3(0, 0.27, 0.15), Vector3(0.08, 0.08, 0.08), -1, 8, 4, head_c)
		FishScript._ellipsoid(st, Vector3(0, 0.25, 0.25), Vector3(0.035, 0.018, 0.06), -1, 6, 3, Color(1.0, 0.55, 0.1))
		FishScript._ellipsoid(st, Vector3(0, 0.16, -0.2), Vector3(0.05, 0.04, 0.07), -1, 6, 3, body_c.darkened(0.2))
		for s in [-1.0, 1.0]:
			FishScript._ellipsoid(st, Vector3(float(s) * 0.06, 0.29, 0.21), Vector3(0.012, 0.014, 0.012), -1, 5, 3, Color(0.05, 0.05, 0.05))
		var m := MeshInstance3D.new()
		m.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var d := Node3D.new()
		d.add_child(m)
		if baby:
			d.scale = Vector3.ONE * 0.6
		add_child(d)
		ducks.append(d)


func _update_ducks(delta: float) -> void:
	for i in ducks.size():
		var d := ducks[i]
		var family := i < 3
		var lag := 0.0 if i == 0 else float(i) * 0.09
		var a := t * (0.05 if family else -0.04) - lag + (0.0 if family else 2.6)
		var r := LAKE_R - (3.2 if family else 5.0) + sin(t * 0.13 + i) * 0.8
		var want := LAKE_C + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if want.z > JETTY_END_Z - 2.5 and absf(want.x) < 3.0:
			want.x = signf(want.x if want.x != 0.0 else 1.0) * 3.0
		# Shy away from boats.
		var push := Vector3.ZERO
		for b in main.active_boats():
			var off: Vector3 = want - b.global_position
			off.y = 0.0
			if off.length() < 3.0 and off.length() > 0.01:
				push += off.normalized() * (3.0 - off.length())
		var cur: Vector3 = d.get_meta("off", Vector3.ZERO)
		cur = cur.lerp(push, 1.0 - exp(-2.0 * delta))
		d.set_meta("off", cur)
		var p := want + cur
		var prev := d.position
		d.position = Vector3(p.x, sin(t * 2.0 + i) * 0.015, p.z)
		var mv := d.position - prev
		mv.y = 0.0
		if mv.length() > 0.0005:
			d.rotation.y = lerp_angle(d.rotation.y, atan2(mv.x, mv.z), 1.0 - exp(-5.0 * delta))


func _build_markers() -> void:
	# Fish frenzy: a glowing ring of bubbles on the water.
	frenzy_root = Node3D.new()
	add_child(frenzy_root)
	frenzy_root.visible = false
	frenzy_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	tm.rings = 28
	tm.ring_segments = 4
	frenzy_ring.mesh = tm
	frenzy_ring.material_override = main.make_material(Color(0.5, 1.0, 0.95), 2.0)
	frenzy_ring.scale = Vector3(3.5, 1.0, 3.5)
	frenzy_ring.position.y = 0.06
	frenzy_root.add_child(frenzy_ring)
	frenzy_bubbles = CPUParticles3D.new()
	frenzy_bubbles.amount = 40
	frenzy_bubbles.lifetime = 1.3
	frenzy_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	frenzy_bubbles.emission_sphere_radius = 3.0
	frenzy_bubbles.direction = Vector3.UP
	frenzy_bubbles.spread = 20.0
	frenzy_bubbles.gravity = Vector3(0, -1.0, 0)
	frenzy_bubbles.initial_velocity_min = 0.6
	frenzy_bubbles.initial_velocity_max = 1.6
	frenzy_bubbles.scale_amount_min = 0.5
	frenzy_bubbles.scale_amount_max = 1.4
	frenzy_bubbles.mesh = main.sphere_mesh(0.07)
	frenzy_bubbles.material_override = main.make_material(Color(0.85, 1.0, 1.0), 0.8)
	frenzy_bubbles.scale = Vector3(1.0, 0.05, 1.0)
	frenzy_bubbles.emitting = false
	frenzy_root.add_child(frenzy_bubbles)
	# Treasure map: a big red X floating on the water, a light beam so it can be found from anywhere,
	# and the yellow buoy a boat drops there for the angler to cast at.
	map_root = Node3D.new()
	add_child(map_root)
	map_root.visible = false
	map_x = Node3D.new()
	map_root.add_child(map_x)
	var xm: StandardMaterial3D = main.make_material(Color(1.0, 0.15, 0.1), 1.2)
	for s in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		bar.mesh = main.box_mesh(Vector3(1.8, 0.06, 0.3))
		bar.material_override = xm
		bar.rotation.y = float(s) * PI * 0.25
		bar.position.y = 0.08
		map_x.add_child(bar)
	map_beam = MeshInstance3D.new()
	map_beam.mesh = main.cyl_mesh(0.18, 0.3, 12.0, 8)
	map_beam_mat = StandardMaterial3D.new()
	map_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	map_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	map_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	map_beam_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.45)
	map_beam.material_override = map_beam_mat
	map_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_beam.position.y = 6.0
	map_root.add_child(map_beam)
	map_buoy = Node3D.new()
	map_root.add_child(map_buoy)
	var ball := MeshInstance3D.new()
	ball.mesh = main.sphere_mesh(0.32)
	ball.material_override = main.make_material(Color(1.0, 0.85, 0.1), 0.6)
	ball.scale = Vector3(1.0, 0.75, 1.0)
	map_buoy.add_child(ball)
	var mast := MeshInstance3D.new()
	mast.mesh = main.cyl_mesh(0.03, 0.03, 1.2, 6)
	mast.material_override = main.make_material(Color(0.3, 0.3, 0.3), 0.0)
	mast.position.y = 0.7
	map_buoy.add_child(mast)
	var flag := MeshInstance3D.new()
	flag.mesh = main.box_mesh(Vector3(0.5, 0.32, 0.02))
	flag.material_override = main.make_material(Color(1.0, 0.2, 0.15), 0.8)
	flag.position = Vector3(0.26, 1.15, 0)
	map_buoy.add_child(flag)


func set_frenzy(on: bool, pos: Vector3) -> void:
	frenzy_root.visible = on
	frenzy_bubbles.emitting = on
	if on:
		frenzy_root.position = Vector3(pos.x, 0.0, pos.z)


## state: 0 none, 1 X marks the spot (a boat must find it), 2 buoy dropped (the angler casts at it).
func set_map(state: int, pos: Vector3) -> void:
	map_root.visible = state > 0
	if state <= 0:
		return
	map_root.position = Vector3(pos.x, 0.0, pos.z)
	map_x.visible = state == 1
	map_buoy.visible = state == 2
	map_beam_mat.albedo_color = Color(1.0, 0.3, 0.2, 0.45) if state == 1 else Color(1.0, 0.9, 0.2, 0.4)


## Per-frame animation: ducks, windmill, lighthouse beam, clouds, markers.
func update(delta: float) -> void:
	t += delta
	_update_ducks(delta)
	blades.rotation.z += delta * 0.6
	beam_root.rotation.y += delta * 0.7
	clouds_root.rotation.y += delta * 0.004
	if frenzy_root.visible:
		var s := 3.5 + 0.35 * sin(t * 4.0)
		frenzy_ring.scale = Vector3(s, 1.0, s)
	if map_root.visible:
		map_x.rotation.y += delta * 0.4
		map_buoy.position.y = sin(t * 1.8) * 0.06
		map_buoy.rotation.z = sin(t * 1.3) * 0.12


## Sky phase p: 0 morning -> 1 sunset -> 1.45 starry night; rain 0..1 greys everything out.
func set_daylight(p: float, rain: float, vr: bool) -> void:
	var dp := clampf(p, 0.0, 1.0)
	night = smoothstep(1.0, 1.4, p)
	var top := Color(0.3, 0.55, 0.95).lerp(Color(0.3, 0.25, 0.55), dp)
	var hor := Color(0.78, 0.9, 1.0).lerp(Color(1.0, 0.55, 0.32), smoothstep(0.3, 1.0, dp))
	var sun_c := Color(1.0, 0.97, 0.88).lerp(Color(1.0, 0.55, 0.25), smoothstep(0.4, 1.0, dp))
	top = top.lerp(Color(0.03, 0.05, 0.15), night)
	hor = hor.lerp(Color(0.13, 0.11, 0.26), night)
	top = top.lerp(Color(0.42, 0.46, 0.52) * (1.0 - night * 0.7), rain * 0.75)
	hor = hor.lerp(Color(0.62, 0.66, 0.7) * (1.0 - night * 0.7), rain * 0.7)
	var elev := lerpf(deg_to_rad(55.0), deg_to_rad(5.0), dp)
	var az := deg_to_rad(200.0)
	var sun_dir := Vector3(sin(az) * cos(elev), sin(elev), cos(az) * cos(elev))
	sky_mat.set_shader_parameter("top_col", Vector3(top.r, top.g, top.b))
	sky_mat.set_shader_parameter("horizon_col", Vector3(hor.r, hor.g, hor.b))
	sky_mat.set_shader_parameter("sun_col", Vector3(sun_c.r, sun_c.g, sun_c.b))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_vis", (1.0 - night) * (1.0 - rain * 0.9))
	sky_mat.set_shader_parameter("stars", night * (1.0 - rain))
	water_mat.set_shader_parameter("sky_col", Vector3(hor.r, hor.g, hor.b).lerp(Vector3(top.r, top.g, top.b), 0.3))
	var deep := Color(0.05, 0.3, 0.42).lerp(Color(0.12, 0.12, 0.3), dp).lerp(Color(0.03, 0.06, 0.14), night)
	water_mat.set_shader_parameter("deep_col", Vector3(deep.r, deep.g, deep.b))
	var glint := sun_c.lerp(Color(0.8, 0.85, 1.0), night)
	water_mat.set_shader_parameter("glint_col", Vector3(glint.r, glint.g, glint.b))
	water_mat.set_shader_parameter("rain", rain)
	env.background_color = hor
	# Kids still need to see the fish at night: moonlight stays fairly bright.
	env.ambient_light_color = Color(0.9, 0.95, 1.0).lerp(Color(1.0, 0.7, 0.6), dp).lerp(Color(0.5, 0.6, 0.95), night)
	env.ambient_light_energy = lerpf(lerpf(0.6, 0.45, dp), 0.4, night) + rain * 0.1
	if night > 0.5:
		var moon := Vector3(-0.35, 0.45, -0.82).normalized()
		sun.look_at_from_position(Vector3.ZERO, -moon, Vector3.UP)
	else:
		sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = sun_c.lerp(Color(0.6, 0.7, 1.0), night)
	sun.light_energy = lerpf(lerpf(1.1, 0.7, dp), 0.35, night) * (1.0 - rain * 0.4)
	var dusk := maxf(smoothstep(0.55, 0.9, p), rain * 0.5)
	lantern_mat.emission_energy_multiplier = dusk * 3.0
	window_mat.emission_energy_multiplier = dusk * 2.0
	lighthouse_lamp.emission_energy_multiplier = 0.3 + dusk * 3.0
	beam_mat.albedo_color.a = maxf(night, rain * 0.6) * 0.22
	beam_root.visible = beam_mat.albedo_color.a > 0.01
	var cc := Color(1, 1, 1).lerp(Color(1.0, 0.75, 0.6), smoothstep(0.5, 1.0, dp)).lerp(Color(0.12, 0.14, 0.25), night)
	cloud_mat.albedo_color = cc.lerp(Color(0.55, 0.58, 0.62) * (1.0 - night * 0.6), rain * 0.8)
	var raining := rain > 0.05
	rain_far.emitting = raining
	rain_near.emitting = raining
	rain_mat.albedo_color.a = 0.45 * rain
	var ff_on := night > 0.3 and rain < 0.3
	fireflies.emitting = ff_on
	fireflies2.emitting = ff_on
	if vr:
		sun.shadow_enabled = false
