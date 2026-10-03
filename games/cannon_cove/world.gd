extends RefCounted
## Builds the pirate world: sunset sky, animated sea, islands and our ship. Also the deck geometry
## helpers (walkable area, obstacles) shared by players, boarders and leaks.

const SEA_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep : source_color = vec3(0.02, 0.3, 0.52);
uniform vec3 shallow : source_color = vec3(0.08, 0.72, 0.78);
uniform vec3 foam : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 sunset : source_color = vec3(1.0, 0.55, 0.32);
varying float wave_h;
varying vec3 wpos;

float waves(vec2 p, float t) {
	float h = sin(p.x * 0.18 + t * 1.1) * 0.35;
	h += sin(p.y * 0.23 - t * 0.9 + p.x * 0.05) * 0.3;
	h += sin((p.x + p.y) * 0.5 + t * 1.7) * 0.08;
	return h;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float calm = mix(0.25, 1.0, smoothstep(5.0, 16.0, length(w.xz * vec2(1.6, 0.7))));
	float h = waves(w.xz, TIME) * calm;
	VERTEX.y += h;
	wave_h = h;
	wpos = w;
	float e = 0.6;
	float hx = waves(w.xz + vec2(e, 0.0), TIME) - waves(w.xz - vec2(e, 0.0), TIME);
	float hz = waves(w.xz + vec2(0.0, e), TIME) - waves(w.xz - vec2(0.0, e), TIME);
	NORMAL = normalize(vec3(-hx * calm, 2.0 * e, -hz * calm));
}

void fragment() {
	float crest = smoothstep(0.3, 0.6, wave_h);
	vec3 col = mix(deep, shallow, smoothstep(-0.55, 0.6, wave_h));
	float sparkle = pow(max(0.0, sin(wpos.x * 1.3 + TIME * 2.0) * sin(wpos.z * 1.1 - TIME * 1.6)), 14.0);
	col = mix(col, foam, clamp(crest * 0.55 + sparkle * 0.6, 0.0, 1.0));
	float far = smoothstep(50.0, 140.0, length(wpos.xz));
	col = mix(col, mix(deep, sunset, 0.35), far * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
"""

const DECK_SHADER := """
shader_type spatial;
uniform vec3 wood : source_color = vec3(0.78, 0.55, 0.3);
uniform vec3 dark : source_color = vec3(0.55, 0.36, 0.18);
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float plank = fract(w.x / 0.42);
	float seam = smoothstep(0.0, 0.05, plank) * smoothstep(1.0, 0.95, plank);
	float row = floor(w.x / 0.42);
	float joint = step(0.985, fract(w.z / 3.1 + row * 0.37));
	float grain = 0.9 + 0.1 * sin(w.z * 9.0 + row * 4.0);
	ALBEDO = mix(dark, wood * grain, seam * (1.0 - joint));
	ROUGHNESS = 0.8;
}
"""

# Deck geometry (world space, our ship sits at the origin, bow towards -Z).
const DECK_HALF_W := 3.9
const DECK_BOW := -11.0  # the bow starts narrowing here
const BOW_TIP := -15.0
const DECK_STERN := 9.4
const HOLD_POS := Vector3(0.0, 0.0, -6.0)  # the cannonball pile
const HULL_HALF_W := 4.3
const BASE_SEA := -1.7  # sea height relative to the deck when the hold is dry
const SUNK_SEA := 0.35  # sea height when the ship is lost

static var obstacles: Array = [
	[Vector2(0.0, -1.0), 0.55],  # main mast
	[Vector2(0.0, -10.0), 0.45],  # fore mast
	[Vector2(0.0, -6.0), 1.05],  # cannonball pile
	[Vector2(0.0, 8.4), 0.6],  # ship's wheel
]


static func deck_half_width(z: float) -> float:
	if z < DECK_BOW:
		return maxf(0.0, DECK_HALF_W * (z - BOW_TIP) / (DECK_BOW - BOW_TIP))
	return DECK_HALF_W


static func on_deck(p: Vector3, margin: float = 0.0) -> bool:
	if p.z < BOW_TIP + margin or p.z > DECK_STERN + 0.5 - margin:
		return false
	return absf(p.x) <= deck_half_width(p.z) + 0.3 - margin


## Keeps a walker on the deck and out of the masts, the pile, the wheel and the cannons.
static func constrain(p: Vector3, radius: float, extra: Array = []) -> Vector3:
	p.z = clampf(p.z, BOW_TIP + 2.0, DECK_STERN - radius)
	var hw := maxf(0.2, deck_half_width(p.z) - radius)
	p.x = clampf(p.x, -hw, hw)
	for o in obstacles + extra:
		var c: Vector2 = o[0]
		var r: float = o[1] + radius
		var d := Vector2(p.x - c.x, p.z - c.y)
		var l := d.length()
		if l < r:
			d = d / l * r if l > 0.001 else Vector2(r, 0.0)
			p.x = c.x + d.x
			p.z = c.y + d.y
	p.y = 0.0
	return p


static func random_deck_point() -> Vector3:
	for attempt in 30:
		var p := Vector3(randf_range(-3.3, 3.3), 0.0, randf_range(-10.0, 8.5))
		if not on_deck(p, 0.6):
			continue
		var clear := true
		for o in obstacles:
			var c: Vector2 = o[0]
			if Vector2(p.x, p.z).distance_to(c) < float(o[1]) + 0.9:
				clear = false
				break
		if clear:
			return p
	return Vector3(2.0, 0.0, 3.5)


static func mat(color: Color, glow: float = 0.0, rough: float = 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cyl(parent: Node, r_top: float, r_bottom: float, h: float, pos: Vector3, m: Material, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, r: float, pos: Vector3, m: Material, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(4, segs / 2)
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Returns {"sea": Node3D} (the sea moves up as the hold floods).
static func build(main: Node3D) -> Dictionary:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.36, 0.78)
	sky_mat.sky_horizon_color = Color(1.0, 0.62, 0.42)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.95, 0.55, 0.38)
	sky_mat.ground_bottom_color = Color(0.05, 0.25, 0.42)
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.fog_enabled = true
	e.fog_light_color = Color(1.0, 0.7, 0.55)
	e.fog_density = 0.0035
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.2
	env.environment = e
	main.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18, 150, 0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	main.add_child(sun)

	# The sea: a detailed wave plane around the ship and a flat one out to the horizon.
	var sea := Node3D.new()
	sea.name = "Sea"
	main.add_child(sea)
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	plane.subdivide_width = 90
	plane.subdivide_depth = 90
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = Shader.new()
	sea_mat.shader.code = SEA_SHADER
	var waves := MeshInstance3D.new()
	waves.mesh = plane
	waves.material_override = sea_mat
	waves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.add_child(waves)
	var far := MeshInstance3D.new()
	var far_plane := PlaneMesh.new()
	far_plane.size = Vector2(3000, 3000)
	far.mesh = far_plane
	var far_mat := mat(Color(0.25, 0.42, 0.55), 0.0, 0.2)
	far.material_override = far_mat
	far.position.y = -0.6
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.add_child(far)
	sea.position.y = BASE_SEA

	_add_islands(main)
	_build_ship(main)
	return {"sea": sea}


static func _add_islands(main: Node3D) -> void:
	var sand := mat(Color(0.98, 0.85, 0.55))
	var grass := mat(Color(0.3, 0.75, 0.3))
	var trunk := mat(Color(0.55, 0.38, 0.2))
	var leaf := mat(Color(0.15, 0.65, 0.25))
	var rock := mat(Color(0.55, 0.5, 0.5))
	var spots := [[Vector3(-120, 0, -90), 22.0], [Vector3(140, 0, -40), 16.0], [Vector3(60, 0, 150), 26.0],
		[Vector3(-150, 0, 80), 18.0], [Vector3(10, 0, -170), 14.0]]
	for s in spots:
		var root := Node3D.new()
		main.add_child(root)
		var c: Vector3 = s[0]
		var r: float = s[1]
		root.position = c + Vector3(0, BASE_SEA - 0.3, 0)
		var beach := sphere(root, 1.0, Vector3.ZERO, sand, 20)
		beach.scale = Vector3(r, r * 0.16, r)
		var hill := sphere(root, 1.0, Vector3(r * 0.1, 0, -r * 0.05), grass, 16)
		hill.scale = Vector3(r * 0.6, r * 0.38, r * 0.55)
		if r > 20.0:
			var peak := cyl(root, 0.5, r * 0.3, r * 0.6, Vector3(-r * 0.15, r * 0.35, r * 0.1), rock, 10)
			peak.rotation.y = 0.3
		for i in 3:
			var a := float(i) * 2.1 + r
			var p := Vector3(cos(a) * r * 0.75, r * 0.12, sin(a) * r * 0.75)
			var t := cyl(root, 0.25, 0.4, 7.0, p + Vector3(0, 3.4, 0), trunk, 6)
			t.rotation.z = 0.15 * sin(a)
			for k in 5:
				var lf := box(root, Vector3(4.2, 0.12, 1.0), p + Vector3(0, 6.9, 0), leaf)
				lf.rotation = Vector3(0, k * TAU / 5.0, -0.35)
				lf.position += Basis(Vector3.UP, k * TAU / 5.0) * Vector3(1.6, -0.4, 0)


## Our ship: hull, planked deck, rails, masts and sails, the cannonball pile and the wheel.
static func _build_ship(main: Node3D) -> void:
	var ship := Node3D.new()
	ship.name = "Ship"
	main.add_child(ship)
	var hull_mat := mat(Color(0.5, 0.28, 0.14))
	var red := mat(Color(0.85, 0.15, 0.12))
	var gold := mat(Color(1.0, 0.78, 0.2), 0.3, 0.4)
	var dark := mat(Color(0.3, 0.18, 0.09))
	var white := mat(Color(0.97, 0.95, 0.88))
	var deck_mat := ShaderMaterial.new()
	deck_mat.shader = Shader.new()
	deck_mat.shader.code = DECK_SHADER
	var hw := HULL_HALF_W
	# Hull: a long box plus a diamond-shaped bow, with a red stripe and gold trim.
	box(ship, Vector3(hw * 2.0, 3.2, 20.6), Vector3(0, -1.65, -0.6), hull_mat)
	var side := hw * sqrt(2.0)
	box(ship, Vector3(side, 3.2, side), Vector3(0, -1.65, DECK_BOW), hull_mat, Vector3(0, PI / 4.0, 0))
	box(ship, Vector3(hw * 2.0 + 0.06, 0.45, 20.6), Vector3(0, -0.75, -0.6), red)
	box(ship, Vector3(hw * 2.0 + 0.08, 0.12, 20.62), Vector3(0, -0.45, -0.6), gold)
	box(ship, Vector3(side + 0.06, 0.45, side + 0.06), Vector3(0, -0.75, DECK_BOW), red, Vector3(0, PI / 4.0, 0))
	# Deck surface.
	box(ship, Vector3(hw * 2.0 - 0.1, 0.1, 20.4), Vector3(0, -0.05, -0.6), deck_mat)
	box(ship, Vector3(side - 0.1, 0.1, side - 0.1), Vector3(0, -0.05, DECK_BOW), deck_mat, Vector3(0, PI / 4.0, 0))
	# Stern castle wall with windows (behind the wheel).
	box(ship, Vector3(hw * 2.0, 2.2, 0.6), Vector3(0, 1.1, 10.0), hull_mat)
	box(ship, Vector3(hw * 2.0 + 0.1, 0.18, 0.7), Vector3(0, 2.2, 10.0), gold)
	for wx in [-2.5, 0.0, 2.5]:
		box(ship, Vector3(1.0, 0.8, 0.1), Vector3(wx, 1.3, 9.68), mat(Color(1.0, 0.85, 0.4), 1.5))
	# Rails, with gaps where the cannons poke out (z = 1 and 6).
	for sx in [-1.0, 1.0]:
		for seg in [[-10.6, -0.2], [1.8, 4.6], [7.4, 9.7]]:
			var z0: float = seg[0]
			var z1: float = seg[1]
			box(ship, Vector3(0.18, 0.9, z1 - z0), Vector3(sx * (hw - 0.05), 0.45, (z0 + z1) * 0.5), dark)
			box(ship, Vector3(0.26, 0.1, z1 - z0), Vector3(sx * (hw - 0.05), 0.92, (z0 + z1) * 0.5), gold)
		# Bow rails along the diamond.
		var bow_rail := box(ship, Vector3(0.18, 0.9, side - 0.2), Vector3(sx * hw * 0.5, 0.45, DECK_BOW - hw * 0.5), dark)
		bow_rail.rotation.y = -sx * PI / 4.0
	# Masts, yards and sails (red and white stripes).
	for m in [[Vector3(0, 0, -1.0), 13.0, 7.5], [Vector3(0, 0, -10.0), 10.0, 5.0]]:
		var base: Vector3 = m[0]
		var h: float = m[1]
		var w: float = m[2]
		cyl(ship, 0.22, 0.32, h, base + Vector3(0, h * 0.5, 0), dark, 8)
		var yard := cyl(ship, 0.1, 0.1, w + 0.6, base + Vector3(0, h * 0.82, 0), dark, 6)
		yard.rotation.z = PI / 2.0
		var sail_h := h * 0.48
		for k in 4:
			var stripe := box(ship, Vector3(w, sail_h / 4.0, 0.08), base + Vector3(0, h * 0.82 - sail_h / 8.0 - k * sail_h / 4.0, 0.25 + 0.12 * sin(k * 0.8)),
				red if k % 2 == 0 else white)
			stripe.rotation.x = -0.08
		# Crow's nest and a flag on top.
		cyl(ship, 0.7, 0.55, 0.7, base + Vector3(0, h * 0.9, 0), hull_mat, 10)
		var flag := box(ship, Vector3(0.05, 0.9, 1.5), base + Vector3(0, h + 0.45, 0.75), mat(Color(1.0, 0.85, 0.1), 0.4))
		flag.rotation.y = 0.0
	# The hold: hatch, crates and a pyramid of cannonballs.
	box(ship, Vector3(2.4, 0.2, 2.4), HOLD_POS + Vector3(0, 0.1, 0), dark)
	var ball_mat := mat(Color(0.12, 0.12, 0.14), 0.0, 0.35)
	ball_mat.metallic = 0.6
	var layer_off := [[3, 0.0], [2, 0.3], [1, 0.6]]
	for lo in layer_off:
		var n: int = lo[0]
		var y: float = lo[1]
		for i in n:
			for j in n:
				sphere(ship, 0.2, HOLD_POS + Vector3((i - (n - 1) * 0.5) * 0.42, 0.42 + y, (j - (n - 1) * 0.5) * 0.42), ball_mat, 10)
	box(ship, Vector3(0.9, 0.9, 0.9), HOLD_POS + Vector3(1.6, 0.45, 0.6), mat(Color(0.7, 0.5, 0.25)))
	box(ship, Vector3(0.7, 0.7, 0.7), HOLD_POS + Vector3(-1.5, 0.35, -0.5), mat(Color(0.7, 0.5, 0.25)))
	var pile_sign := Label3D.new()
	pile_sign.text = "CANNONBALLS"
	pile_sign.font_size = 72
	pile_sign.outline_size = 20
	pile_sign.pixel_size = 0.005
	pile_sign.modulate = Color(1.0, 0.9, 0.4)
	pile_sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	pile_sign.position = HOLD_POS + Vector3(0, 2.0, 0)
	ship.add_child(pile_sign)
	# Ship's wheel.
	cyl(ship, 0.12, 0.15, 1.1, Vector3(0, 0.55, 8.4), dark, 6)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.52
	tm.rings = 16
	tm.ring_segments = 6
	wheel.mesh = tm
	wheel.material_override = gold
	wheel.position = Vector3(0, 1.2, 8.3)
	wheel.rotation.x = PI / 2.0
	ship.add_child(wheel)
	# Lanterns.
	for lp in [Vector3(-3.8, 1.3, 9.6), Vector3(3.8, 1.3, 9.6), Vector3(0, 2.2, -1.5)]:
		sphere(ship, 0.16, lp, mat(Color(1.0, 0.7, 0.3), 3.0), 8)
