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
uniform float chop = 1.0;
uniform float night = 0.0;
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
	calm *= chop;
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
	col *= mix(1.0, 0.45, night);
	col += vec3(0.6, 0.8, 1.0) * sparkle * night * 0.35;
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
	[Vector2(-3.05, 8.75), 0.75],  # barrels by the stern
	[Vector2(3.05, 8.75), 0.75],
	[Vector2(-1.7, 9.15), 0.55],  # the treasure chest
	[Vector2(0.0, -12.2), 0.6],  # barrels at the bow
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




## Many copies of one mesh in a single draw call. xforms: Array of Transform3D.
static func multi(parent: Node, mesh: Mesh, m: Material, xforms: Array, shadows: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		mm.set_instance_transform(i, xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


static func sphere_mesh(r: float, segs: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(3, segs / 2)
	return s


static func xf(pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


## A thin rope (unit box) stretched from a to b, as a MultiMesh transform.
static func rope_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var mid := (a + b) * 0.5
	var dir := (b - a)
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	return Transform3D(basis.scaled(Vector3(thick, thick, dir.length())), mid)


## Sky moods for the voyage: the sun sets as the waves get tougher, a storm rolls in and the
## Kraken comes at night; dawn breaks when it's beaten.
const MOODS := {
	"sunset": {"top": Color(0.22, 0.36, 0.78), "horizon": Color(1.0, 0.62, 0.42), "ground": Color(0.95, 0.55, 0.38),
		"sun": Color(1.0, 0.82, 0.62), "sun_e": 1.25, "amb": 0.8, "night": 0.0, "chop": 1.0, "fog": Color(1.0, 0.7, 0.55), "cloud": Color(1.0, 0.85, 0.75)},
	"dusk": {"top": Color(0.17, 0.16, 0.45), "horizon": Color(0.98, 0.42, 0.42), "ground": Color(0.75, 0.35, 0.42),
		"sun": Color(1.0, 0.62, 0.52), "sun_e": 0.95, "amb": 0.7, "night": 0.3, "chop": 1.15, "fog": Color(0.8, 0.45, 0.5), "cloud": Color(1.0, 0.6, 0.65)},
	"storm": {"top": Color(0.13, 0.15, 0.22), "horizon": Color(0.38, 0.42, 0.5), "ground": Color(0.25, 0.3, 0.36),
		"sun": Color(0.75, 0.8, 0.9), "sun_e": 0.7, "amb": 0.65, "night": 0.35, "chop": 1.9, "fog": Color(0.4, 0.45, 0.52), "cloud": Color(0.45, 0.48, 0.55)},
	"night": {"top": Color(0.03, 0.05, 0.16), "horizon": Color(0.14, 0.24, 0.4), "ground": Color(0.08, 0.15, 0.24),
		"sun": Color(0.65, 0.75, 1.0), "sun_e": 0.6, "amb": 0.6, "night": 1.0, "chop": 1.3, "fog": Color(0.15, 0.22, 0.35), "cloud": Color(0.35, 0.4, 0.6)},
	"dawn": {"top": Color(0.38, 0.6, 0.95), "horizon": Color(1.0, 0.82, 0.58), "ground": Color(0.9, 0.72, 0.52),
		"sun": Color(1.0, 0.92, 0.78), "sun_e": 1.35, "amb": 0.95, "night": 0.0, "chop": 0.8, "fog": Color(1.0, 0.85, 0.7), "cloud": Color(1.0, 0.95, 0.88)},
}


## Returns the pieces main.gd animates: {"sea", "env", "sun", "sky", "sea_mat", "clouds_mat", "stars_mat",
## "moon_mat", "sails", "flags", "lantern_mat", "wheel", "beam", "gold_pile", "golden_ball", "parrot_perches"}.
static func build(main: Node3D) -> Dictionary:
	var out := {}
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
	out["env"] = e
	out["sky"] = sky_mat

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18, 150, 0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	main.add_child(sun)
	out["sun"] = sun

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
	out["sea"] = sea
	out["sea_mat"] = sea_mat
	out["far_mat"] = far_mat

	_add_islands(main, out)
	_add_sky_dressing(main, out)
	_build_ship(main, out)
	return out


## Islands (palms and rocks share MultiMeshes, so five islands cost a handful of draw calls),
## a lighthouse with a sweeping beam and an old shipwreck.
static func _add_islands(main: Node3D, out: Dictionary) -> void:
	var sand := mat(Color(0.98, 0.85, 0.55))
	var grass := mat(Color(0.3, 0.75, 0.3))
	var trunk := mat(Color(0.55, 0.38, 0.2))
	var leaf := mat(Color(0.15, 0.65, 0.25))
	var rock := mat(Color(0.55, 0.5, 0.5))
	var spots := [[Vector3(-120, 0, -90), 22.0], [Vector3(140, 0, -40), 16.0], [Vector3(60, 0, 150), 26.0],
		[Vector3(-150, 0, 80), 18.0], [Vector3(10, 0, -170), 14.0]]
	var sand_x: Array = []
	var hill_x: Array = []
	var trunk_x: Array = []
	var leaf_x: Array = []
	var rock_x: Array = []
	var y0 := BASE_SEA - 0.3
	for s in spots:
		var c: Vector3 = s[0]
		var r: float = s[1]
		var base := c + Vector3(0, y0, 0)
		sand_x.append(xf(base, Vector3(r, r * 0.16, r)))
		hill_x.append(xf(base + Vector3(r * 0.1, 0, -r * 0.05), Vector3(r * 0.6, r * 0.38, r * 0.55)))
		if r > 20.0:
			var peak := cyl(main, 0.5, r * 0.3, r * 0.6, base + Vector3(-r * 0.15, r * 0.35, r * 0.1), rock, 10)
			peak.rotation.y = 0.3
		for i in 3:
			var a := float(i) * 2.1 + r
			var p := base + Vector3(cos(a) * r * 0.75, r * 0.12, sin(a) * r * 0.75)
			trunk_x.append(xf(p + Vector3(0, 3.4, 0), Vector3.ONE, Vector3(0, 0, 0.15 * sin(a))))
			for k in 5:
				var ry := k * TAU / 5.0 + a
				var lp := p + Vector3(0, 6.9, 0) + Basis(Vector3.UP, ry) * Vector3(1.6, -0.4, 0)
				leaf_x.append(Transform3D(Basis(Vector3.UP, ry) * Basis(Vector3.BACK, -0.35), lp))
		for k in 5:
			var a := float(k) * 1.3 + r * 0.7
			var rs := randf_range(1.2, 3.2)
			rock_x.append(xf(base + Vector3(cos(a) * r * 1.02, 0.2, sin(a) * r * 1.02), Vector3(rs, rs * 0.8, rs * 1.1), Vector3(0, a, 0)))
	# A few lonely sea stacks far out, where no ship sails.
	for k in 7:
		var a := float(k) * 0.9 + 0.4
		var d := randf_range(115.0, 160.0)
		var h := randf_range(3.0, 7.0)
		rock_x.append(xf(Vector3(cos(a) * d, y0 + h * 0.3, sin(a) * d), Vector3(h * 0.5, h, h * 0.45), Vector3(0, a, 0)))
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.25
	trunk_mesh.bottom_radius = 0.4
	trunk_mesh.height = 7.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var leaf_mesh := BoxMesh.new()
	leaf_mesh.size = Vector3(4.2, 0.12, 1.0)
	multi(main, sphere_mesh(1.0, 20), sand, sand_x)
	multi(main, sphere_mesh(1.0, 16), grass, hill_x)
	multi(main, trunk_mesh, trunk, trunk_x)
	multi(main, leaf_mesh, leaf, leaf_x)
	multi(main, sphere_mesh(1.0, 7), rock, rock_x)
	# Lighthouse on the east island: striped tower, glowing lamp and a slowly sweeping beam.
	var lh := Node3D.new()
	lh.position = Vector3(140, y0 + 3.0, -40) + Vector3(-4.0, 0, 3.0)
	main.add_child(lh)
	cyl(lh, 1.1, 1.6, 12.0, Vector3(0, 6.0, 0), mat(Color(0.97, 0.95, 0.9)))
	for k in 2:
		cyl(lh, 1.35 - k * 0.15, 1.45 - k * 0.15, 1.6, Vector3(0, 3.0 + k * 4.0, 0), mat(Color(0.85, 0.15, 0.12)))
	sphere(lh, 1.0, Vector3(0, 12.8, 0), mat(Color(1.0, 0.9, 0.55), 4.0), 10)
	cyl(lh, 0.2, 1.4, 1.0, Vector3(0, 14.0, 0), mat(Color(0.85, 0.15, 0.12)), 10)
	var beam := Node3D.new()
	beam.position = Vector3(0, 12.8, 0)
	lh.add_child(beam)
	var beam_mat := mat(Color(1.0, 0.95, 0.7, 0.18), 1.5)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.disable_fog = true
	var bm := cyl(beam, 3.5, 0.4, 70.0, Vector3(0, 0, -35.0), beam_mat, 8)
	bm.rotation.x = -PI / 2.0
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out["beam"] = beam
	out["beam_mat"] = beam_mat
	# An old shipwreck on the west beach (a tilted hull and a broken mast).
	var wreck := Node3D.new()
	wreck.position = Vector3(-120, y0, -90) + Vector3(20.0, 0.5, 14.0)
	wreck.rotation = Vector3(0.25, 0.7, 0.35)
	main.add_child(wreck)
	box(wreck, Vector3(3.5, 2.2, 9.0), Vector3.ZERO, mat(Color(0.32, 0.22, 0.15)))
	var wm := cyl(wreck, 0.2, 0.25, 6.0, Vector3(0.3, 3.0, -1.0), mat(Color(0.25, 0.17, 0.1)), 6)
	wm.rotation.z = 0.5


## Clouds, stars and a moon (the stars and moon fade in as night falls).
static func _add_sky_dressing(main: Node3D, out: Dictionary) -> void:
	var cloud_mat := mat(Color(1.0, 0.85, 0.75), 0.35)
	cloud_mat.disable_fog = true
	var cx: Array = []
	for k in 16:
		var a := float(k) / 16.0 * TAU + randf_range(-0.15, 0.15)
		var d := randf_range(170.0, 300.0)
		var c := Vector3(cos(a) * d, randf_range(45.0, 85.0), sin(a) * d)
		for j in 3:
			var off := Vector3(randf_range(-14, 14), randf_range(-2, 3), randf_range(-8, 8))
			var sz := randf_range(10.0, 18.0)
			cx.append(xf(c + off, Vector3(sz * 1.6, sz * 0.45, sz)))
	out["clouds_mat"] = cloud_mat
	multi(main, sphere_mesh(1.0, 8), cloud_mat, cx)
	var star_mat := mat(Color(1.0, 1.0, 0.9, 0.0), 3.0)
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.disable_fog = true
	var sx: Array = []
	for k in 150:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.12, 1.0), randf_range(-1, 1)).normalized()
		var s := randf_range(0.6, 1.5)
		sx.append(xf(dir * 420.0, Vector3.ONE * s))
	var stars := multi(main, sphere_mesh(1.0, 4), star_mat, sx)
	stars.visible = false
	out["stars"] = stars
	out["stars_mat"] = star_mat
	var moon_mat := mat(Color(0.95, 0.95, 1.0, 0.0), 2.0)
	moon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.disable_fog = true
	var moon := sphere(main, 16.0, Vector3(-150, 160, -330), moon_mat, 16)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.visible = false
	out["moon"] = moon
	out["moon_mat"] = moon_mat


## Our ship: hull, planked deck, rails, masts, rigging and sails, the cannonball pile, the wheel,
## barrels, a figurehead and the treasure chest that fills up with the crew's gold.
static func _build_ship(main: Node3D, out: Dictionary) -> void:
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
	# Glowing portholes along both sides of the hull.
	var port_x: Array = []
	for sx in [-1.0, 1.0]:
		for k in 7:
			var z := -8.5 + k * 2.6
			port_x.append(xf(Vector3(sx * (hw + 0.02), -1.35, z), Vector3.ONE, Vector3(0, 0, PI / 2.0)))
	var port_mesh := CylinderMesh.new()
	port_mesh.top_radius = 0.22
	port_mesh.bottom_radius = 0.22
	port_mesh.height = 0.08
	port_mesh.radial_segments = 10
	port_mesh.rings = 1
	multi(ship, port_mesh, mat(Color(1.0, 0.75, 0.35), 2.0), port_x)
	# Deck surface.
	box(ship, Vector3(hw * 2.0 - 0.1, 0.1, 20.4), Vector3(0, -0.05, -0.6), deck_mat)
	box(ship, Vector3(side - 0.1, 0.1, side - 0.1), Vector3(0, -0.05, DECK_BOW), deck_mat, Vector3(0, PI / 4.0, 0))
	# Stern castle wall with windows (behind the wheel).
	box(ship, Vector3(hw * 2.0, 2.2, 0.6), Vector3(0, 1.1, 10.0), hull_mat)
	box(ship, Vector3(hw * 2.0 + 0.1, 0.18, 0.7), Vector3(0, 2.2, 10.0), gold)
	var lantern_mat := mat(Color(1.0, 0.7, 0.3), 3.0)
	out["lantern_mat"] = lantern_mat
	var window_mat := mat(Color(1.0, 0.85, 0.4), 1.5)
	out["window_mat"] = window_mat
	for wx in [-2.5, 0.0, 2.5]:
		box(ship, Vector3(1.0, 0.8, 0.1), Vector3(wx, 1.3, 9.68), window_mat)
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
	# Masts, yards and sails (red and white stripes that billow in the wind).
	var sails: Array = []
	var flags: Array = []
	var rope_x: Array = []
	for m in [[Vector3(0, 0, -1.0), 13.0, 7.5], [Vector3(0, 0, -10.0), 10.0, 5.0]]:
		var base: Vector3 = m[0]
		var h: float = m[1]
		var w: float = m[2]
		cyl(ship, 0.22, 0.32, h, base + Vector3(0, h * 0.5, 0), dark, 8)
		var yard := cyl(ship, 0.1, 0.1, w + 0.6, base + Vector3(0, h * 0.82, 0), dark, 6)
		yard.rotation.z = PI / 2.0
		var sail_h := h * 0.48
		var sail := Node3D.new()
		sail.position = base + Vector3(0, h * 0.82, 0)
		ship.add_child(sail)
		for k in 4:
			var stripe := box(sail, Vector3(w, sail_h / 4.0, 0.08), Vector3(0, -sail_h / 8.0 - k * sail_h / 4.0, 0.25 + 0.12 * sin(k * 0.8)),
				red if k % 2 == 0 else white)
			stripe.rotation.x = -0.08
		sails.append(sail)
		# Crow's nest and a flag on top.
		cyl(ship, 0.7, 0.55, 0.7, base + Vector3(0, h * 0.9, 0), hull_mat, 10)
		var flag_root := Node3D.new()
		flag_root.position = base + Vector3(0, h + 0.45, 0.0)
		ship.add_child(flag_root)
		box(flag_root, Vector3(0.05, 0.9, 1.5), Vector3(0, 0, 0.75), mat(Color(1.0, 0.85, 0.1), 0.4))
		flags.append(flag_root)
		# Rigging: shrouds from the mast top down to both rails, and stays fore and aft.
		var top := base + Vector3(0, h * 0.88, 0)
		for sx in [-1.0, 1.0]:
			for k in 3:
				rope_x.append(rope_xf(top, Vector3(sx * (hw - 0.05), 0.95, base.z - 1.0 + k * 1.0), 0.045))
	rope_x.append(rope_xf(Vector3(0, 12.0, -1.0), Vector3(0, 9.0, -10.0), 0.05))
	rope_x.append(rope_xf(Vector3(0, 9.0, -10.0), Vector3(0, 0.9, BOW_TIP + 0.4), 0.05))
	rope_x.append(rope_xf(Vector3(0, 12.0, -1.0), Vector3(0, 2.25, 9.9), 0.05))
	var unit := BoxMesh.new()
	multi(ship, unit, mat(Color(0.72, 0.6, 0.4)), rope_x)
	out["sails"] = sails
	out["flags"] = flags
	# The hold: hatch, crates and a pyramid of cannonballs (plus a spot for a golden one).
	box(ship, Vector3(2.4, 0.2, 2.4), HOLD_POS + Vector3(0, 0.1, 0), dark)
	var ball_mat := mat(Color(0.12, 0.12, 0.14), 0.0, 0.35)
	ball_mat.metallic = 0.6
	var pile_x: Array = []
	var layer_off := [[3, 0.0], [2, 0.3], [1, 0.6]]
	for lo in layer_off:
		var n: int = lo[0]
		var y: float = lo[1]
		for i in n:
			for j in n:
				pile_x.append(xf(HOLD_POS + Vector3((i - (n - 1) * 0.5) * 0.42, 0.42 + y, (j - (n - 1) * 0.5) * 0.42)))
	multi(ship, sphere_mesh(0.2, 10), ball_mat, pile_x, true)
	var golden := sphere(ship, 0.24, HOLD_POS + Vector3(0, 1.32, 0), mat(Color(1.0, 0.8, 0.2), 2.5, 0.2), 12)
	golden.visible = false
	out["golden_ball"] = golden
	var crate_mat := mat(Color(0.7, 0.5, 0.25))
	box(ship, Vector3(0.9, 0.9, 0.9), HOLD_POS + Vector3(1.6, 0.45, 0.6), crate_mat)
	box(ship, Vector3(0.7, 0.7, 0.7), HOLD_POS + Vector3(-1.5, 0.35, -0.5), crate_mat)
	var pile_sign := Label3D.new()
	pile_sign.text = "CANNONBALLS"
	pile_sign.font_size = 72
	pile_sign.outline_size = 20
	pile_sign.pixel_size = 0.005
	pile_sign.modulate = Color(1.0, 0.9, 0.4)
	pile_sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	pile_sign.position = HOLD_POS + Vector3(0, 2.0, 0)
	ship.add_child(pile_sign)
	out["pile_sign"] = pile_sign
	# Barrels (stern corners and bow) and coils of rope by the masts.
	var barrel_x: Array = []
	for bp in [Vector3(-3.25, 0, 8.55), Vector3(-2.75, 0, 9.15), Vector3(-3.3, 0.8, 8.85), Vector3(3.25, 0, 8.55),
			Vector3(2.75, 0, 9.15), Vector3(-0.35, 0, -12.0), Vector3(0.4, 0, -12.35), Vector3(0.05, 0.8, -12.2)]:
		var p: Vector3 = bp
		barrel_x.append(xf(p + Vector3(0, 0.4, 0), Vector3.ONE, Vector3(0, p.x + p.z, 0)))
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.28
	barrel_mesh.bottom_radius = 0.28
	barrel_mesh.height = 0.8
	barrel_mesh.radial_segments = 10
	barrel_mesh.rings = 2
	multi(ship, barrel_mesh, mat(Color(0.6, 0.38, 0.18)), barrel_x, true)
	var hoop_x: Array = []
	for bx in barrel_x:
		var t: Transform3D = bx
		hoop_x.append(Transform3D(t.basis, t.origin + Vector3(0, 0.22, 0)))
		hoop_x.append(Transform3D(t.basis, t.origin - Vector3(0, 0.22, 0)))
	var hoop := CylinderMesh.new()
	hoop.top_radius = 0.295
	hoop.bottom_radius = 0.295
	hoop.height = 0.06
	hoop.radial_segments = 10
	hoop.rings = 1
	multi(ship, hoop, mat(Color(0.25, 0.22, 0.2), 0.0, 0.4), hoop_x)
	var coil := TorusMesh.new()
	coil.inner_radius = 0.18
	coil.outer_radius = 0.34
	coil.rings = 12
	coil.ring_segments = 5
	multi(ship, coil, mat(Color(0.75, 0.62, 0.4)), [xf(Vector3(0.75, 0.06, -0.3)), xf(Vector3(-0.8, 0.06, -1.6)),
		xf(Vector3(0.6, 0.06, -9.3)), xf(Vector3(-1.2, 0.06, 7.4))])
	# Figurehead: a golden sea-dragon on the bow.
	var fig := Node3D.new()
	fig.position = Vector3(0, 0.6, BOW_TIP - 0.3)
	ship.add_child(fig)
	var fneck := cyl(fig, 0.2, 0.32, 1.4, Vector3(0, 0.2, -0.3), gold, 8)
	fneck.rotation.x = -0.9
	var fhead := sphere(fig, 0.36, Vector3(0, 0.75, -0.85), gold, 10)
	fhead.scale = Vector3(0.9, 0.8, 1.3)
	for ex in [-0.18, 0.18]:
		sphere(fig, 0.08, Vector3(ex, 0.88, -1.08), mat(Color(0.2, 1.0, 0.6), 3.0), 6)
	# Ship's wheel (turns a little as we sail).
	cyl(ship, 0.12, 0.15, 1.1, Vector3(0, 0.55, 8.4), dark, 6)
	var wheel := Node3D.new()
	wheel.position = Vector3(0, 1.2, 8.3)
	ship.add_child(wheel)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.52
	tm.rings = 16
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = gold
	ring.rotation.x = PI / 2.0
	wheel.add_child(ring)
	for k in 4:
		var spoke := box(wheel, Vector3(1.3, 0.07, 0.07), Vector3.ZERO, dark)
		spoke.rotation.z = k * PI / 4.0
	out["wheel"] = wheel
	# The treasure chest by the stern: its pile of gold grows with the crew's haul.
	var chest := Node3D.new()
	chest.position = Vector3(-1.7, 0, 9.15)
	ship.add_child(chest)
	box(chest, Vector3(1.0, 0.55, 0.65), Vector3(0, 0.28, 0), mat(Color(0.5, 0.26, 0.1)))
	box(chest, Vector3(1.04, 0.08, 0.69), Vector3(0, 0.5, 0), gold)
	var lid := box(chest, Vector3(1.0, 0.12, 0.65), Vector3(0, 0.82, 0.38), mat(Color(0.5, 0.26, 0.1)))
	lid.rotation.x = -1.2
	var gpile := sphere(chest, 0.45, Vector3(0, 0.55, 0), mat(Color(1.0, 0.78, 0.15), 1.2, 0.3), 12)
	gpile.scale = Vector3(1.0, 0.05, 0.62)
	out["gold_pile"] = gpile
	# Lanterns.
	for lp in [Vector3(-3.8, 1.3, 9.6), Vector3(3.8, 1.3, 9.6), Vector3(0, 2.2, -1.5)]:
		sphere(ship, 0.16, lp, lantern_mat, 8)
	# Spots on the rail where the parrot perches next to each cannon.
	out["parrot_perches"] = [Vector3(-3.8, 0.97, -0.6), Vector3(-3.8, 0.97, 7.6), Vector3(3.8, 0.97, -0.6), Vector3(3.8, 0.97, 7.6)]
