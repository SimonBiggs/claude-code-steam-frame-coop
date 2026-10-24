extends Node3D
## Where the rockets go. Every rocket flies to the next planet on the SPACE MAP:
## - the destination planet hangs huge in the sky (everyone sees it, the pilot included) and the
##   rocket curves off towards it after lift-off;
## - the SPACE MAP board (left of the launch doorway) shows the route, visited planets get a flag;
## - the LAUNCH LOG board (right of the doorway) lists every rocket that flew, with its stars;
## - the TV crew get a launch camera: a low shot of the countdown, a chase up into the sky, then a
##   little space scene (crew-only layer, far below the world) where the rocket lands on the planet.
## Everything is driven by (rocket number, phase, launch time), so host and TV agree without events,
## except the log lines (event "logged").

const P := preload("res://games/rocket_workshop/puzzles.gd")
const SKY_PLANET := Vector3(28.0, 190.0, -240.0)  # high enough to clear the roof beams from the desk
const SKY_RADIUS := 32.0
const DIORAMA := Vector3(0.0, -2000.0, 0.0)
const D_PLANET := Vector3(0.0, -6.0, -95.0)  # relative to DIORAMA
const D_RADIUS := 20.0
const SPACE_FROM := 6.0  # launch time when the TV crew's camera cuts to space
const ARRIVE_AT := 10.0
const MAP_POS := Vector3(-7.65, 2.25, -5.94)
const LOG_POS := Vector3(7.65, 2.25, -5.94)

var main
var t := 0.0
var shown_dest := -1
var sky_root: Node3D
var sky_mat: StandardMaterial3D
var sky_ring: MeshInstance3D
var sky_moon: MeshInstance3D
var map_planets: MultiMesh
var map_marker: Node3D
var map_flags: MultiMesh
var map_halo: MeshInstance3D
var log_label: Label3D
var log_stars: MultiMesh
var log_lines: Array = []  # [name, planet index, stars]
var dio: Node3D
var dio_planet_mat: StandardMaterial3D
var dio_ring: MeshInstance3D
var dio_rocket: Node3D
var dio_trim: StandardMaterial3D
var dio_flame: CPUParticles3D
var dio_flag: Node3D
var dio_label: Label3D
var dio_burst_n := -1
var space_env: Environment


func _ready() -> void:
	_build_sky_planet()
	_build_map()
	_build_log()
	_build_diorama()


# --- The planet in the sky -------------------------------------------------------

func _build_sky_planet() -> void:
	sky_root = Node3D.new()
	sky_root.position = SKY_PLANET
	add_child(sky_root)
	var ball := MeshInstance3D.new()
	ball.mesh = main.sphere_mesh(SKY_RADIUS)
	sky_mat = StandardMaterial3D.new()
	sky_mat.albedo_color = P.PLANET_COLORS[0]
	sky_mat.emission_enabled = true
	sky_mat.emission = P.PLANET_COLORS[0]
	sky_mat.emission_energy_multiplier = 0.35
	sky_mat.disable_fog = true
	sky_mat.roughness = 1.0
	ball.material_override = sky_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(ball)
	sky_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = SKY_RADIUS * 1.35
	tm.outer_radius = SKY_RADIUS * 1.9
	tm.rings = 24
	tm.ring_segments = 3
	sky_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.95, 0.8)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.9, 0.7)
	rm.emission_energy_multiplier = 0.4
	rm.disable_fog = true
	sky_ring.material_override = rm
	sky_ring.scale = Vector3(1, 0.06, 1)
	sky_ring.rotation = Vector3(0.35, 0, 0.25)
	sky_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(sky_ring)
	sky_moon = MeshInstance3D.new()
	sky_moon.mesh = main.sphere_mesh(SKY_RADIUS * 0.22)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.9, 0.9, 0.95)
	mm.emission_enabled = true
	mm.emission = Color(0.8, 0.8, 0.9)
	mm.emission_energy_multiplier = 0.3
	mm.disable_fog = true
	sky_moon.material_override = mm
	sky_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(sky_moon)


## Unit direction the rocket heads off in after it clears the gantry.
func flight_dir() -> Vector3:
	return (SKY_PLANET - main.PAD_POS).normalized()


# --- Space map and launch log boards ------------------------------------------------

func _board(at: Vector3, size: Vector2, title: String) -> Node3D:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var back := MeshInstance3D.new()
	back.mesh = main.box_mesh(Vector3(size.x, size.y, 0.06))
	back.material_override = main.make_material(Color(0.07, 0.08, 0.2), 0.15)
	back.position.z = 0.03
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(back)
	var l := Label3D.new()
	l.text = title
	l.font_size = 80
	l.pixel_size = 0.004
	l.outline_size = 18
	l.modulate = Color(1.0, 0.85, 0.4)
	l.outline_modulate = Color(0.25, 0.12, 0.05)
	l.position = Vector3(0, size.y / 2.0 - 0.22, 0.08)
	l.visible = not main.simple  # simple mode: pictures only
	root.add_child(l)
	return root


func _map_spot(i: int) -> Vector3:
	# A winding route: two rows of five, left to right then back.
	var row := i / 5
	var col := i % 5
	if row == 1:
		col = 4 - col
	return Vector3(-2.3 + col * 1.15, 0.3 - row * 1.0 + (0.12 if col % 2 == 1 else 0.0), 0.1)


func _build_map() -> void:
	var root := _board(MAP_POS, Vector2(6.2, 2.7), "SPACE MAP")
	map_planets = MultiMesh.new()
	map_planets.transform_format = MultiMesh.TRANSFORM_3D
	map_planets.use_colors = true
	map_planets.mesh = main.sphere_mesh(0.2)
	map_planets.instance_count = P.PLANETS.size()
	# Rings round the ringed planets and the dotted route: one baked mesh (one draw call).
	var parts: Array = []
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.34
	tm.rings = 16
	tm.ring_segments = 3
	var dot: Mesh = main.sphere_mesh(0.035)
	var home := Vector3(-3.0, 0.0, 0.1)
	for k in 3:
		parts.append([dot, Transform3D(Basis(), home.lerp(_map_spot(0), (k + 1) / 4.0)), Color(0.9, 0.9, 1.0)])
	for i in P.PLANETS.size():
		var at := _map_spot(i)
		map_planets.set_instance_transform(i, Transform3D(Basis(), at))
		map_planets.set_instance_color(i, P.PLANET_COLORS[i])
		if P.PLANET_RINGS[i]:
			parts.append([tm, Transform3D(Basis(Vector3.RIGHT, 1.2), at), Color(1.0, 0.92, 0.7)])
		if i + 1 < P.PLANETS.size():
			for k in 3:
				parts.append([dot, Transform3D(Basis(), at.lerp(_map_spot(i + 1), (k + 1) / 4.0)), Color(0.9, 0.9, 1.0)])
		var name_l := Label3D.new()
		name_l.text = P.PLANETS[i]
		name_l.font_size = 30
		name_l.pixel_size = 0.004
		name_l.outline_size = 8
		name_l.modulate = Color(0.95, 0.95, 1.0)
		name_l.position = at + Vector3(0, -0.34, 0.02)
		name_l.visible = not main.simple
		root.add_child(name_l)
		main.set_layers(name_l, main.MANUAL_LAYER)  # names for the crew; the pilot's desk says where they're going
	var a := MultiMeshInstance3D.new()
	a.multimesh = map_planets
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.emission_enabled = true
	pm.emission = Color(0.3, 0.3, 0.3)
	a.material_override = pm
	root.add_child(a)
	var deco := MeshInstance3D.new()
	deco.mesh = main.merged_mesh("space_map_deco", parts)
	deco.material_override = main.vertex_mat()
	root.add_child(deco)
	# Little flags on visited planets (instances hidden until visited).
	map_flags = MultiMesh.new()
	map_flags.transform_format = MultiMesh.TRANSFORM_3D
	var fm := PrismMesh.new()
	fm.size = Vector3(0.16, 0.14, 0.02)
	map_flags.mesh = fm
	map_flags.instance_count = P.PLANETS.size()
	for i in P.PLANETS.size():
		map_flags.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
	var f := MultiMeshInstance3D.new()
	f.multimesh = map_flags
	f.material_override = main.make_material(Color(1.0, 0.35, 0.3), 0.6)
	root.add_child(f)
	# The pulsing halo round the next stop, and a tiny rocket marker.
	map_halo = MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.27
	hm.outer_radius = 0.33
	hm.rings = 20
	hm.ring_segments = 3
	map_halo.mesh = hm
	map_halo.material_override = main.make_material(Color(1.0, 0.75, 0.2), 2.0)
	map_halo.rotation.x = PI / 2.0
	root.add_child(map_halo)
	map_marker = Node3D.new()
	root.add_child(map_marker)
	var mb := MeshInstance3D.new()
	mb.mesh = main.cyl_mesh(0.0, 0.07, 0.22, 8)
	mb.material_override = main.make_material(Color(1.0, 1.0, 1.0), 0.6)
	map_marker.add_child(mb)
	map_marker.position = home
	for n in root.get_children():
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_log() -> void:
	var root := _board(LOG_POS, Vector2(6.2, 2.7), "LAUNCH LOG")
	root.visible = not main.simple  # simple mode: no log of names and stars
	log_label = Label3D.new()
	log_label.font_size = 40
	log_label.pixel_size = 0.004
	log_label.outline_size = 8
	log_label.modulate = Color(0.95, 0.97, 1.0)
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	log_label.position = Vector3(-2.9, 0.95, 0.08)
	log_label.text = "No rockets yet - let's build one!"
	root.add_child(log_label)
	log_stars = MultiMesh.new()
	log_stars.transform_format = MultiMesh.TRANSFORM_3D
	log_stars.mesh = main.star_mesh()
	log_stars.instance_count = 8 * 3
	for i in log_stars.instance_count:
		log_stars.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
	var s := MultiMeshInstance3D.new()
	s.multimesh = log_stars
	s.material_override = main.make_material(Color(1.0, 0.85, 0.2), 1.2)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)


## A rocket flew: add a line to the log (both machines; the host sends event "logged").
func add_log(rocket_name: String, planet_i: int, stars: int, number: int) -> void:
	log_lines.append([rocket_name, planet_i, stars, number])
	while log_lines.size() > 7:
		log_lines.pop_front()
	var lines: Array[String] = []
	for line in log_lines:
		var l: Array = line
		lines.append("#%d %s  to  %s" % [int(l[3]), str(l[0]), P.PLANETS[int(l[1])]])
	log_label.text = "\n".join(lines)
	for i in log_stars.instance_count:
		log_stars.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
	var line_h := 40.0 * 0.004 * 1.45
	for k in log_lines.size():
		var l: Array = log_lines[k]
		for j in int(l[2]):
			var at := Vector3(2.15 + j * 0.27, 0.95 - line_h * (k + 0.5), 0.09)
			log_stars.set_instance_transform(k * 3 + j, Transform3D(Basis.from_scale(Vector3.ONE * 0.11), at))


# --- The TV crew's space scene ---------------------------------------------------

func _build_diorama() -> void:
	dio = Node3D.new()
	dio.position = DIORAMA
	add_child(dio)
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 160.0
	dm.height = 320.0
	dm.radial_segments = 16
	dm.rings = 8
	dm.flip_faces = true
	dome.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.03, 0.03, 0.12)
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.disable_fog = true
	dome.material_override = dmat
	dio.add_child(dome)
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.use_colors = true
	stars.mesh = main.sphere_mesh(0.5)
	stars.instance_count = 260
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in stars.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if d.length() < 0.05:
			d = Vector3.UP
		var at := d.normalized() * rng.randf_range(120.0, 150.0)
		stars.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.4, 1.4)), at))
		stars.set_instance_color(i, Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.85, 0.5), rng.randf()))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = stars
	var stm := StandardMaterial3D.new()
	stm.vertex_color_use_as_albedo = true
	stm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stm.disable_fog = true
	smi.material_override = stm
	dio.add_child(smi)
	var planet := MeshInstance3D.new()
	planet.mesh = main.sphere_mesh(D_RADIUS)
	dio_planet_mat = StandardMaterial3D.new()
	dio_planet_mat.albedo_color = P.PLANET_COLORS[0]
	dio_planet_mat.emission_enabled = true
	dio_planet_mat.emission = P.PLANET_COLORS[0]
	dio_planet_mat.emission_energy_multiplier = 0.25
	dio_planet_mat.disable_fog = true
	planet.material_override = dio_planet_mat
	planet.position = D_PLANET
	dio.add_child(planet)
	dio_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = D_RADIUS * 1.35
	tm.outer_radius = D_RADIUS * 1.9
	tm.rings = 28
	tm.ring_segments = 3
	dio_ring.mesh = tm
	dio_ring.material_override = main.make_material(Color(1.0, 0.92, 0.7), 0.5)
	dio_ring.scale = Vector3(1, 0.05, 1)
	dio_ring.rotation = Vector3(0.3, 0, 0.2)
	dio_ring.position = D_PLANET
	dio.add_child(dio_ring)
	# The little rocket, a flag for when it lands, and a big hello.
	dio_rocket = Node3D.new()
	dio.add_child(dio_rocket)
	var white: StandardMaterial3D = main.make_material(Color(0.95, 0.95, 0.98), 0.1)
	dio_trim = StandardMaterial3D.new()
	dio_trim.albedo_color = Color(0.95, 0.3, 0.3)
	var parts: Array = [[main.cyl_mesh(0.62, 0.62, 3.0, 16), white, Vector3(0, 2.0, 0)],
		[main.cyl_mesh(0.0, 0.62, 1.4, 16), dio_trim, Vector3(0, 4.2, 0)],
		[main.cyl_mesh(0.35, 0.5, 0.45, 12), main.make_material(Color(0.35, 0.35, 0.4), 0.0), Vector3(0, 0.3, 0)]]
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		mi.position = part[2]
		dio_rocket.add_child(mi)
	for i in 3:
		var a := TAU * i / 3.0
		var fin := MeshInstance3D.new()
		fin.mesh = main.box_mesh(Vector3(0.1, 1.1, 0.75))
		fin.material_override = dio_trim
		fin.position = Vector3(sin(a) * 0.75, 0.75, cos(a) * 0.75)
		fin.rotation.y = a
		dio_rocket.add_child(fin)
	var win := MeshInstance3D.new()
	win.mesh = main.sphere_mesh(0.28)
	win.material_override = main.make_material(Color(0.5, 0.85, 1.0), 0.8)
	win.scale = Vector3(1, 1, 0.3)
	win.position = Vector3(0, 2.7, 0.6)
	dio_rocket.add_child(win)
	dio_flame = CPUParticles3D.new()
	dio_flame.amount = 40
	dio_flame.lifetime = 0.5
	dio_flame.direction = Vector3.DOWN
	dio_flame.spread = 14.0
	dio_flame.initial_velocity_min = 6.0
	dio_flame.initial_velocity_max = 9.0
	dio_flame.gravity = Vector3.ZERO
	dio_flame.scale_amount_min = 0.6
	dio_flame.scale_amount_max = 1.5
	var fsm := SphereMesh.new()
	fsm.radius = 0.18
	fsm.height = 0.36
	fsm.radial_segments = 6
	fsm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fsm.material = fmat
	dio_flame.mesh = fsm
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.5, 1.0))
	g.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	dio_flame.color_ramp = g
	dio_flame.emitting = false
	dio_rocket.add_child(dio_flame)
	dio_flag = Node3D.new()
	dio.add_child(dio_flag)
	var pole := MeshInstance3D.new()
	pole.mesh = main.cyl_mesh(0.05, 0.05, 2.4, 6)
	pole.material_override = main.make_material(Color(0.9, 0.9, 0.95), 0.0)
	pole.position.y = 1.2
	dio_flag.add_child(pole)
	var cloth := MeshInstance3D.new()
	cloth.mesh = main.box_mesh(Vector3(1.0, 0.6, 0.04))
	cloth.material_override = main.make_material(Color(1.0, 0.3, 0.3), 0.5)
	cloth.position = Vector3(0.52, 2.05, 0)
	dio_flag.add_child(cloth)
	dio_label = Label3D.new()
	dio_label.font_size = 96
	dio_label.pixel_size = 0.03
	dio_label.outline_size = 24
	dio_label.modulate = Color(1.0, 0.9, 0.4)
	dio_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dio_label.no_depth_test = false
	dio.add_child(dio_label)
	main.set_layers(dio, main.MANUAL_LAYER)
	space_env = Environment.new()
	space_env.background_mode = Environment.BG_COLOR
	space_env.background_color = Color(0.02, 0.02, 0.08)
	space_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	space_env.ambient_light_color = Color(0.6, 0.6, 0.8)
	space_env.ambient_light_energy = 0.8
	space_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	space_env.glow_enabled = true
	space_env.glow_intensity = 0.9
	dio.visible = false


# --- Every frame (both machines) -------------------------------------------------

func update_space(n: int, phase: String, launch_t: float, delta: float) -> void:
	t += delta
	var dest := P.planet(n)
	if dest != shown_dest and phase != "launch":
		shown_dest = dest
		_set_destination(dest)
	sky_root.rotation.y = t * 0.05
	sky_moon.position = Vector3(cos(t * 0.3), 0.25, sin(t * 0.3)) * SKY_RADIUS * 1.9
	# Space map: the halo pulses round the next stop; visited planets (this lap) wear a flag.
	var visited := maxi(n - 1, 0) if phase != "launch" or launch_t < ARRIVE_AT else n
	var lap_done := visited % P.PLANETS.size() if visited > 0 else 0
	if visited > 0 and lap_done == 0:
		lap_done = P.PLANETS.size()
	for i in P.PLANETS.size():
		var on := i < lap_done
		var at := _map_spot(i) + Vector3(0.12, 0.3, 0.02)
		map_flags.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * (1.0 if on else 0.001)), at))
	var spot := _map_spot(dest)
	map_halo.position = spot
	var pulse := 1.0 + sin(t * 4.0) * 0.12
	map_halo.scale = Vector3.ONE * pulse
	map_halo.visible = n > 0
	var from := Vector3(-3.0, 0.0, 0.1) if dest == 0 else _map_spot(dest - 1)
	var travel := 0.0
	if phase == "launch":
		travel = clampf((launch_t - 3.0) / (ARRIVE_AT - 3.0), 0.0, 1.0)
	map_marker.position = from.lerp(spot, travel) + Vector3(0, 0.25 + sin(t * 3.0) * 0.03, 0.08)
	map_marker.rotation.z = -atan2(spot.x - from.x, spot.y - from.y) if travel > 0.0 else 0.0
	_update_diorama(n, phase, launch_t)


func _set_destination(i: int) -> void:
	var c: Color = P.PLANET_COLORS[i]
	sky_mat.albedo_color = c
	sky_mat.emission = c
	sky_ring.visible = P.PLANET_RINGS[i]
	sky_moon.visible = i % 3 != 2
	sky_root.scale = Vector3.ONE * (1.6 if P.PLANETS[i] == "GIGANTO" else 1.0)
	dio_planet_mat.albedo_color = c
	dio_planet_mat.emission = c
	dio_ring.visible = P.PLANET_RINGS[i]


func _update_diorama(n: int, phase: String, launch_t: float) -> void:
	var on := phase == "launch" and launch_t >= SPACE_FROM
	dio.visible = on
	if not on:
		dio_flame.emitting = false
		return
	dio_trim.albedo_color = main.rocket.trim_mat.albedo_color
	var u := clampf((launch_t - SPACE_FROM) / (ARRIVE_AT - SPACE_FROM), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 2.0)
	var land := D_PLANET + Vector3(0, D_RADIUS - 0.2, 0)
	var start := Vector3(-14.0, -22.0, 30.0)
	var mid := Vector3(4.0, 14.0, -40.0)
	var a := start.lerp(mid, e)
	var b := mid.lerp(land, e)
	var pos := a.lerp(b, e)
	var ahead := start.lerp(mid, minf(e + 0.02, 1.0)).lerp(mid.lerp(land, minf(e + 0.02, 1.0)), minf(e + 0.02, 1.0))
	var vel := ahead - pos
	var up := Vector3.UP
	if u < 0.97 and vel.length() > 0.001:
		up = vel.normalized().lerp(Vector3.UP, smoothstep(0.75, 0.97, u)).normalized()
	dio_rocket.position = pos
	dio_rocket.basis = Basis(Quaternion(Vector3.UP, up))
	dio_flame.emitting = u < 0.98
	var arrived := launch_t >= ARRIVE_AT
	dio_flag.visible = arrived
	dio_label.visible = arrived and not main.simple
	if arrived:
		var grow := clampf((launch_t - ARRIVE_AT) * 3.0, 0.0, 1.0)
		dio_flag.position = land + Vector3(2.2, -0.3, 0.8)
		dio_flag.scale = Vector3(1, grow, 1)
		dio_label.text = "WE MADE IT TO\n%s!" % P.PLANETS[P.planet(n)]
		dio_label.position = land + Vector3(0, 11.0 + grow, 0)
		if dio_burst_n != n:
			dio_burst_n = n
			_dio_confetti(DIORAMA + land + Vector3(0, 3, 0))


func _dio_confetti(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 70
	p.lifetime = 2.0
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -6.0, 0)
	p.color = Color(1.0, 0.4, 0.4)
	p.hue_variation_min = -1.0
	p.hue_variation_max = 1.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.04, 0.35)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(0.4, 0.4, 0.4)
	bm.material = m
	p.mesh = bm
	add_child(p)
	p.global_position = at
	p.emitting = true
	main.set_layers(p, main.MANUAL_LAYER)
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)


## The TV crew's launch camera: {} when they should see their own view, else {xf, env}.
func launch_cam(n: int, phase: String, launch_t: float) -> Dictionary:
	if phase != "launch" or launch_t < 0.4 or n <= 0:
		return {}
	if launch_t >= SPACE_FROM:
		var rp := dio_rocket.position
		var u := clampf((launch_t - SPACE_FROM) / (ARRIVE_AT - SPACE_FROM), 0.0, 1.0)
		var cam := rp + Vector3(9.0 - u * 3.0, 4.0 + u * 4.0, 16.0 - u * 2.0)
		var look := rp.lerp(D_PLANET, 0.25 + u * 0.15)
		return {"xf": Transform3D(Basis.looking_at(look - cam, Vector3.UP), DIORAMA + cam), "env": space_env}
	var rocket_pos: Vector3 = main.rocket.flight_pos(launch_t)
	var low: Vector3 = main.PAD_POS + Vector3(3.6, 0.7, 5.0)
	var cam := low
	var look := rocket_pos + Vector3(0, 3.0, 0)
	if launch_t > 3.0:
		var k := smoothstep(3.0, 5.5, launch_t)
		cam = low.lerp(rocket_pos + Vector3(7.0, -5.0, 12.0), k)
		look = rocket_pos + Vector3(0, 2.5, 0)
	return {"xf": Transform3D(Basis.looking_at(look - cam, Vector3.UP), cam), "env": null}
