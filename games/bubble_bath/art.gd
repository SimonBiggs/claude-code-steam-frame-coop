extends RefCounted
## Bubble Bath art: baked, vertex-coloured meshes (one draw call each) and the water shader.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 rip[8];
uniform float now;
uniform vec3 deep : source_color = vec3(0.30, 0.78, 0.98);
uniform vec3 crest : source_color = vec3(0.92, 0.98, 1.0);
varying float h;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float y = sin(w.x * 1.7 + now * 1.3) * 0.015 + sin(w.z * 2.3 - now * 1.1) * 0.015;
	for (int i = 0; i < 8; i++) {
		float age = now - rip[i].z;
		if (age > 0.0 && age < 3.0) {
			float d = distance(w.xz, rip[i].xy);
			float front = age * 2.0;
			float env = exp(-age * 1.3) * smoothstep(0.7, 0.0, abs(d - front));
			y += rip[i].w * 0.08 * env * sin((d - front) * 9.0);
		}
	}
	VERTEX.y += y;
	h = y;
}
void fragment() {
	ALBEDO = mix(deep, crest, clamp(h * 9.0 + 0.15, 0.0, 1.0));
	ROUGHNESS = 0.2;
	SPECULAR = 0.7;
}
"""


static func water(hx: float, hz: float) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(hx * 2.0, hz * 2.0)
	pm.subdivide_width = 40
	pm.subdivide_depth = 26
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var rips: Array[Vector4] = []
	for i in 8:
		rips.append(Vector4(0.0, 0.0, -100.0, 0.0))
	mat.set_shader_parameter("rip", rips)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The bathroom floor, the tub (rim, claw feet, foam piles) and the tap. Origin = floor centre.
static func bathroom(hx: float, hz: float, water_y: float, rim_y: float, tap: Vector3) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	# Checkered floor tiles.
	for ix in range(-7, 7):
		for iz in range(-5, 5):
			var c := Color(0.98, 0.86, 0.9) if (ix + iz) % 2 == 0 else Color(0.82, 0.93, 1.0)
			b.box(Vector3(1.98, 0.04, 1.98), MeshKit.at(Vector3(ix * 2.0 + 1.0, -0.02, iz * 2.0 + 1.0)), c)
	var white := Color(0.98, 0.98, 1.0)
	var t := 0.3
	# Walls of the tub (rounded, white), floor inside.
	b.rounded_box(Vector3(hx * 2.0 + t * 2.0, rim_y, t), 0.12, MeshKit.at(Vector3(0.0, rim_y * 0.5, hz + t * 0.5)), white)
	b.rounded_box(Vector3(hx * 2.0 + t * 2.0, rim_y, t), 0.12, MeshKit.at(Vector3(0.0, rim_y * 0.5, -hz - t * 0.5)), white)
	b.rounded_box(Vector3(t, rim_y, hz * 2.0 + t * 2.0), 0.12, MeshKit.at(Vector3(hx + t * 0.5, rim_y * 0.5, 0.0)), white)
	b.rounded_box(Vector3(t, rim_y, hz * 2.0 + t * 2.0), 0.12, MeshKit.at(Vector3(-hx - t * 0.5, rim_y * 0.5, 0.0)), white)
	b.box(Vector3(hx * 2.0, 0.1, hz * 2.0), MeshKit.at(Vector3(0.0, 0.05, 0.0)), Color(0.85, 0.95, 1.0))
	# Gold claw feet.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.sphere(0.22, MeshKit.at(Vector3(sx * (hx + 0.05), 0.12, sz * (hz + 0.05)), Vector3(1.0, 0.6, 1.0)), Color(1.0, 0.8, 0.3))
	# Foam piles hugging the inside of the rim.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 70:
		var p := Vector3.ZERO
		var side := i % 4
		if side < 2:
			p = Vector3(rng.randf_range(-hx, hx), 0.0, (hz - 0.12) * (1.0 if side == 0 else -1.0))
		else:
			p = Vector3((hx - 0.12) * (1.0 if side == 2 else -1.0), 0.0, rng.randf_range(-hz, hz))
		p.y = water_y + rng.randf_range(0.0, 0.12)
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.85, 0.95), rng.randf() * 0.5)
		b.sphere(rng.randf_range(0.14, 0.3), MeshKit.at(p), tint, 10)
	# Bath mat where the VR player stands.
	b.rounded_box(Vector3(1.6, 0.03, 0.9), 0.1, MeshKit.at(Vector3(0.0, 0.015, hz + 0.7)), Color(0.55, 0.85, 0.6))
	# The tap: pipe up the outside wall, spout over the water, a big red handle to touch.
	var chrome := Color(0.8, 0.85, 0.92)
	b.cylinder(0.06, 0.06, 0.4, MeshKit.at(Vector3(tap.x, rim_y + 0.2, tap.z)), chrome)
	b.cylinder(0.05, 0.05, 0.45, MeshKit.at(Vector3(tap.x, rim_y + 0.38, tap.z - 0.2), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), chrome)
	b.cylinder(0.07, 0.05, 0.08, MeshKit.at(Vector3(tap.x, rim_y + 0.33, tap.z - 0.42)), chrome)
	return b.build()


## The tap's handle (separate so it can spin when touched).
static func tap_handle() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.03, 0.03, 0.1, MeshKit.at(Vector3(0.0, 0.05, 0.0)), Color(0.8, 0.85, 0.92))
	for k in 4:
		var a := k * PI * 0.5
		b.sphere(0.055, MeshKit.at(Vector3(cos(a) * 0.09, 0.1, sin(a) * 0.09)), Color(1.0, 0.3, 0.35))
	b.sphere(0.06, MeshKit.at(Vector3(0.0, 0.11, 0.0)), Color(1.0, 0.3, 0.35))
	return b.build()


## The plug-hole: a dark hole, a chrome ring and swirly stripes (spun by the game).
static func drain(r: float) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(r, r, 0.04, MeshKit.at(Vector3(0.0, 0.0, 0.0)), Color(0.12, 0.2, 0.35))
	b.torus(r, 0.06, MeshKit.at(Vector3(0.0, 0.02, 0.0)), Color(0.85, 0.9, 1.0))
	for k in 6:
		var a := k * TAU / 6.0
		var p := Vector3(cos(a), 0.0, sin(a)) * r * 0.55
		b.box(Vector3(r * 0.7, 0.02, 0.06), MeshKit.at(p + Vector3.UP * 0.03, Vector3.ONE, Vector3(0.0, -a + 0.9, 0.0)), Color(0.45, 0.85, 1.0), true)
	return b.build()


## A big gold arrow bobbing over the plug-hole (points down).
static func arrow() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cone(0.22, 0.32, MeshKit.at(Vector3(0.0, 0.16, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), Color(1.0, 0.85, 0.2), 12, true)
	b.cylinder(0.08, 0.08, 0.3, MeshKit.at(Vector3(0.0, 0.47, 0.0)), Color(1.0, 0.85, 0.2), 12, true)
	return b.build()


## A rubber duck, origin at the waterline, facing +Z.
static func duck() -> ArrayMesh:
	var cached := ResCache.fetch("bb_duck_v1") as ArrayMesh
	if cached != null:
		return cached
	var b := MeshKit.Builder.new()
	var yellow := Color(1.0, 0.86, 0.15)
	b.ellipsoid(Vector3(0.15, 0.11, 0.19), MeshKit.at(Vector3(0.0, 0.05, -0.02)), yellow)
	b.ellipsoid(Vector3(0.05, 0.06, 0.06), MeshKit.at(Vector3(0.0, 0.13, -0.18), Vector3.ONE, Vector3(0.6, 0.0, 0.0)), yellow)
	b.sphere(0.1, MeshKit.at(Vector3(0.0, 0.2, 0.08)), yellow)
	b.ellipsoid(Vector3(0.06, 0.025, 0.07), MeshKit.at(Vector3(0.0, 0.18, 0.2)), Color(1.0, 0.5, 0.1))
	for sx in [-1.0, 1.0]:
		b.sphere(0.022, MeshKit.at(Vector3(sx * 0.05, 0.24, 0.16)), Color(0.05, 0.05, 0.1))
		b.ellipsoid(Vector3(0.03, 0.06, 0.1), MeshKit.at(Vector3(sx * 0.13, 0.07, -0.02)), Color(1.0, 0.75, 0.1))
	var m := b.build()
	ResCache.put("bb_duck_v1", m)
	return m


## A little toy boat in the player's colour, origin at the waterline, facing +Z.
static func boat(col: Color) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.42, 0.2, 0.7), 0.09, MeshKit.at(Vector3(0.0, 0.04, 0.0)), col)
	b.wedge(Vector3(0.42, 0.2, 0.22), MeshKit.at(Vector3(0.0, 0.04, 0.42)), col)
	b.box(Vector3(0.44, 0.04, 0.72), MeshKit.at(Vector3(0.0, 0.12, 0.0)), Color(1.0, 1.0, 1.0))
	b.rounded_box(Vector3(0.28, 0.16, 0.26), 0.05, MeshKit.at(Vector3(0.0, 0.22, -0.12)), Color(1.0, 1.0, 1.0))
	b.cylinder(0.05, 0.06, 0.2, MeshKit.at(Vector3(0.0, 0.38, -0.12)), col.lightened(0.3))
	b.sphere(0.04, MeshKit.at(Vector3(-0.08, 0.24, 0.015)), Color(0.4, 0.8, 1.0))
	b.sphere(0.04, MeshKit.at(Vector3(0.08, 0.24, 0.015)), Color(0.4, 0.8, 1.0))
	return b.build()


## One soap bubble for the floating MultiMesh.
static func bubble_mesh() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 12
	s.rings = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.97, 1.0)
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = Color(0.55, 0.45, 0.7)
	m.emission_energy_multiplier = 0.25
	s.material = m
	return s


## A golden rubber duck (worth three), origin at the waterline, facing +Z.
static func golden_duck() -> ArrayMesh:
	var cached := ResCache.fetch("bb_gold_duck_v1") as ArrayMesh
	if cached != null:
		return cached
	var b := MeshKit.Builder.new()
	var gold := Color(1.0, 0.75, 0.1)
	b.ellipsoid(Vector3(0.15, 0.11, 0.19), MeshKit.at(Vector3(0.0, 0.05, -0.02)), gold, 12, true)
	b.ellipsoid(Vector3(0.05, 0.06, 0.06), MeshKit.at(Vector3(0.0, 0.13, -0.18), Vector3.ONE, Vector3(0.6, 0.0, 0.0)), gold, 8, true)
	b.sphere(0.1, MeshKit.at(Vector3(0.0, 0.2, 0.08)), gold, 12, true)
	b.ellipsoid(Vector3(0.06, 0.025, 0.07), MeshKit.at(Vector3(0.0, 0.18, 0.2)), Color(1.0, 0.45, 0.1))
	for sx in [-1.0, 1.0]:
		b.sphere(0.022, MeshKit.at(Vector3(sx * 0.05, 0.24, 0.16)), Color(0.05, 0.05, 0.1))
	b.star(5, 0.07, 0.03, 0.02, MeshKit.at(Vector3(0.0, 0.36, 0.08)), Color(1.0, 0.95, 0.5), true)
	var m := b.build()
	ResCache.put("bb_gold_duck_v1", m)
	return m


## A sponge island (radius r), origin at the waterline: a squishy yellow sponge with a green scrubby top.
static func sponge(r: float) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(r, r * 1.05, 0.22, MeshKit.at(Vector3(0.0, 0.0, 0.0)), Color(0.98, 0.86, 0.32), 14)
	b.cylinder(r * 0.98, r, 0.07, MeshKit.at(Vector3(0.0, 0.14, 0.0)), Color(0.3, 0.75, 0.4), 14)
	for k in 7:
		var a := k * TAU / 7.0 + 0.4
		b.sphere(0.035, MeshKit.at(Vector3(cos(a) * r * 1.0, 0.0, sin(a) * r * 1.0), Vector3(1.0, 1.0, 0.5)), Color(0.82, 0.68, 0.2), 6)
	return b.build()


## Mama Duck: a big rubber duck with a pink bow (crowned: a gold crown instead), origin at her seat, facing +Z.
static func mama_duck(crowned: bool) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var yellow := Color(1.0, 0.86, 0.15)
	b.ellipsoid(Vector3(0.15, 0.11, 0.19), MeshKit.at(Vector3(0.0, 0.05, -0.02)), yellow)
	b.ellipsoid(Vector3(0.05, 0.06, 0.06), MeshKit.at(Vector3(0.0, 0.13, -0.18), Vector3.ONE, Vector3(0.6, 0.0, 0.0)), yellow)
	b.sphere(0.1, MeshKit.at(Vector3(0.0, 0.2, 0.08)), yellow)
	b.ellipsoid(Vector3(0.06, 0.025, 0.07), MeshKit.at(Vector3(0.0, 0.18, 0.2)), Color(1.0, 0.5, 0.1))
	for sx in [-1.0, 1.0]:
		b.sphere(0.022, MeshKit.at(Vector3(sx * 0.05, 0.24, 0.16)), Color(0.05, 0.05, 0.1))
		b.ellipsoid(Vector3(0.03, 0.06, 0.1), MeshKit.at(Vector3(sx * 0.13, 0.07, -0.02)), Color(1.0, 0.75, 0.1))
	if crowned:
		var gold := Color(1.0, 0.8, 0.2)
		b.cylinder(0.06, 0.055, 0.04, MeshKit.at(Vector3(0.0, 0.31, 0.07)), gold, 10, true)
		for k in 5:
			var a := k * TAU / 5.0
			b.cone(0.017, 0.05, MeshKit.at(Vector3(cos(a) * 0.05, 0.35, 0.07 + sin(a) * 0.05)), gold, 4, true)
	else:
		var pink := Color(1.0, 0.55, 0.75)
		for sx in [-1.0, 1.0]:
			b.ellipsoid(Vector3(0.045, 0.03, 0.02), MeshKit.at(Vector3(sx * 0.045, 0.3, 0.05)), pink)
		b.sphere(0.02, MeshKit.at(Vector3(0.0, 0.3, 0.05)), pink.darkened(0.2))
	return b.build()


## One bath toy on the rim, origin at its base: boat, beachball, starfish, whale, soapbar or fish. golden: TODAY'S BATH (gold star on top).
static func toy(kind: String, golden: bool) -> ArrayMesh:
	var key := "bb_toy_%s_%s" % [kind, golden]
	var cached := ResCache.fetch(key) as ArrayMesh
	if cached != null:
		return cached
	var b := MeshKit.Builder.new()
	match kind:
		"boat":
			b.rounded_box(Vector3(0.12, 0.06, 0.22), 0.03, MeshKit.at(Vector3(0.0, 0.03, 0.0)), Color(0.95, 0.3, 0.25))
			b.cylinder(0.008, 0.008, 0.2, MeshKit.at(Vector3(0.0, 0.15, 0.0)), Color(0.6, 0.45, 0.3))
			b.wedge(Vector3(0.01, 0.14, 0.12), MeshKit.at(Vector3(0.0, 0.15, -0.06)), Color(0.98, 0.98, 1.0))
		"beachball":
			var cols := [Color(0.95, 0.25, 0.25), Color(0.98, 0.98, 1.0), Color(0.35, 0.65, 1.0), Color(1.0, 0.86, 0.15)]
			b.sphere(0.1, MeshKit.at(Vector3(0.0, 0.1, 0.0)), Color(0.98, 0.98, 1.0), 12)
			for k in 4:
				b.ellipsoid(Vector3(0.035, 0.1, 0.1), MeshKit.at(Vector3(0.0, 0.1, 0.0), Vector3(1.03, 1.01, 1.01), Vector3(0.0, k * PI / 4.0, 0.0)), cols[k], 10)
		"starfish":
			b.star(5, 0.11, 0.045, 0.04, MeshKit.at(Vector3(0.0, 0.12, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(1.0, 0.55, 0.25))
		"whale":
			b.ellipsoid(Vector3(0.09, 0.07, 0.14), MeshKit.at(Vector3(0.0, 0.07, 0.0)), Color(0.35, 0.65, 1.0))
			b.wedge(Vector3(0.12, 0.02, 0.06), MeshKit.at(Vector3(0.0, 0.1, -0.15)), Color(0.35, 0.65, 1.0))
			b.cylinder(0.012, 0.02, 0.08, MeshKit.at(Vector3(0.0, 0.17, 0.04)), Color(0.6, 0.85, 1.0))
			for sx in [-1.0, 1.0]:
				b.sphere(0.015, MeshKit.at(Vector3(sx * 0.07, 0.09, 0.09)), Color(0.05, 0.05, 0.1))
		"soapbar":
			b.rounded_box(Vector3(0.18, 0.06, 0.11), 0.025, MeshKit.at(Vector3(0.0, 0.03, 0.0)), Color(1.0, 0.6, 0.8))
			for k in 3:
				b.sphere(0.025 + k * 0.01, MeshKit.at(Vector3(-0.04 + k * 0.04, 0.1 + k * 0.03, 0.0)), Color(0.9, 0.95, 1.0), 8)
		_:  # fish
			b.ellipsoid(Vector3(0.05, 0.07, 0.12), MeshKit.at(Vector3(0.0, 0.08, 0.0)), Color(1.0, 0.55, 0.15))
			b.wedge(Vector3(0.02, 0.1, 0.06), MeshKit.at(Vector3(0.0, 0.08, -0.14)), Color(1.0, 0.75, 0.2))
			for sx in [-1.0, 1.0]:
				b.sphere(0.014, MeshKit.at(Vector3(sx * 0.04, 0.1, 0.07)), Color(0.05, 0.05, 0.1))
	if golden:
		b.star(5, 0.05, 0.022, 0.015, MeshKit.at(Vector3(0.0, 0.3, 0.0)), Color(1.0, 0.85, 0.25), true)
	var m := b.build()
	ResCache.put(key, m)
	return m
