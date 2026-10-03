extends RefCounted
## Builds the haunted mansion: library (west), hall (middle), ballroom (east), all procedural.
## Rooms span x -21..21, z -8..8; interior walls at x = ±7 with a doorway at |z| < 1.6.

const HALF_X := 21.0
const HALF_Z := 8.0
const WALL_H := 4.2
const DOOR_HALF := 1.6

const WALL_SHADER := """
shader_type spatial;
uniform vec3 paper_a : source_color = vec3(0.30, 0.17, 0.40);
uniform vec3 paper_b : source_color = vec3(0.24, 0.13, 0.33);
uniform vec3 wood : source_color = vec3(0.17, 0.09, 0.12);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float along = wpos.x + wpos.z;
	float s = step(0.5, fract(along * 1.2));
	vec3 c = mix(paper_a, paper_b, s);
	vec2 g = fract(vec2(along * 1.2 + 0.25, wpos.y * 1.2)) - 0.5;
	float d = 1.0 - smoothstep(0.07, 0.1, abs(g.x) + abs(g.y));
	c = mix(c, vec3(0.38, 0.75, 0.5), d * 0.45);
	float wain = 1.0 - step(1.0, wpos.y);
	float rail = smoothstep(0.96, 1.0, wpos.y) * (1.0 - smoothstep(1.06, 1.1, wpos.y));
	c = mix(c, wood, max(wain, rail));
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""

const FLOOR_SHADER := """
shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c;
	float rough = 0.8;
	if (wpos.x > 7.0) {
		vec2 g = floor(wpos.xz / 1.2);
		float k = mod(g.x + g.y, 2.0);
		c = mix(vec3(0.05, 0.03, 0.08), vec3(0.33, 0.24, 0.42), k);
		rough = 0.25;
	} else if (wpos.x < -7.0) {
		vec2 g = fract(wpos.xz * 0.8) - 0.5;
		float diamond = 1.0 - smoothstep(0.3, 0.33, abs(g.x) + abs(g.y));
		c = mix(vec3(0.06, 0.16, 0.10), vec3(0.10, 0.25, 0.15), diamond);
	} else {
		float plank = floor(wpos.z / 0.35);
		float offs = fract(sin(plank * 12.9898) * 43758.5453);
		float seam = smoothstep(0.0, 0.03, fract(wpos.z / 0.35)) * smoothstep(0.0, 0.01, fract(wpos.x / 2.4 + offs));
		c = mix(vec3(0.10, 0.06, 0.07), vec3(0.22, 0.13, 0.13) * (0.85 + 0.3 * offs), seam);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(0.45, 0.55, 1.0);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float shimmer = 0.85 + 0.15 * sin(TIME * 0.7 + wpos.x * 2.0);
	ALBEDO = color * 0.10 * smoothstep(0.0, 3.0, wpos.y) * shimmer;
}
"""


static func mat(color: Color, glow: float = 0.0, rough: float = 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, collide: bool = true, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


static func cyl(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, material: Material, segments: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func ball(parent: Node3D, radius: float, pos: Vector3, material: Material, squash: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0 * squash
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func shader_mat(code: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = code
	return sm


## Builds everything. Returns {"candles": [OmniLight3D], "anim": [[Node3D, kind]]}.
static func build(main: Node3D) -> Dictionary:
	var out := {"candles": [], "anim": []}
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.01, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.32, 0.6)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.08
	e.fog_enabled = true
	e.fog_light_color = Color(0.16, 0.1, 0.24)
	e.fog_density = 0.018
	env.environment = e
	main.add_child(env)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40, 20, 0)
	moon.light_color = Color(0.55, 0.62, 1.0)
	moon.light_energy = 0.22
	moon.shadow_enabled = false
	main.add_child(moon)

	var root := Node3D.new()
	root.name = "Mansion"
	main.add_child(root)

	# Floor, ceiling, walls.
	var floor_mi := box(root, Vector3(HALF_X * 2.0 + 1.0, 0.2, HALF_Z * 2.0 + 1.0), Vector3(0, -0.1, 0), shader_mat(FLOOR_SHADER))
	floor_mi.name = "Floor"
	box(root, Vector3(HALF_X * 2.0 + 1.0, 0.2, HALF_Z * 2.0 + 1.0), Vector3(0, WALL_H + 0.1, 0), mat(Color(0.09, 0.05, 0.11)), false)
	var wall := shader_mat(WALL_SHADER)
	box(root, Vector3(HALF_X * 2.0 + 0.6, WALL_H, 0.3), Vector3(0, WALL_H / 2.0, -HALF_Z - 0.15), wall)
	box(root, Vector3(HALF_X * 2.0 + 0.6, WALL_H, 0.3), Vector3(0, WALL_H / 2.0, HALF_Z + 0.15), wall)
	box(root, Vector3(0.3, WALL_H, HALF_Z * 2.0), Vector3(-HALF_X - 0.15, WALL_H / 2.0, 0), wall)
	box(root, Vector3(0.3, WALL_H, HALF_Z * 2.0), Vector3(HALF_X + 0.15, WALL_H / 2.0, 0), wall)
	var seg := HALF_Z - DOOR_HALF
	var dark_wood := mat(Color(0.2, 0.1, 0.12))
	for x in [-7.0, 7.0]:
		for zs in [-1.0, 1.0]:
			box(root, Vector3(0.3, WALL_H, seg), Vector3(x, WALL_H / 2.0, zs * (DOOR_HALF + seg / 2.0)), wall)
		box(root, Vector3(0.3, WALL_H - 2.7, DOOR_HALF * 2.0), Vector3(x, 2.7 + (WALL_H - 2.7) / 2.0, 0), wall, false)
		# Door frame.
		for zs in [-1.0, 1.0]:
			box(root, Vector3(0.45, 2.7, 0.15), Vector3(x, 1.35, zs * DOOR_HALF), dark_wood, false)
		box(root, Vector3(0.45, 0.18, DOOR_HALF * 2.0 + 0.3), Vector3(x, 2.75, 0), dark_wood, false)

	_windows(root)
	_hall(root, out)
	_library(root, out)
	_ballroom(root, out)
	return out


static func _windows(root: Node3D) -> void:
	var pane := mat(Color(0.55, 0.65, 1.0), 1.6)
	var bar := mat(Color(0.08, 0.05, 0.1))
	var beam := shader_mat(BEAM_SHADER)
	for x in [-17.0, -11.0, -3.5, 3.5, 11.0, 17.0]:
		box(root, Vector3(1.4, 2.0, 0.06), Vector3(x, 2.2, -HALF_Z + 0.02), pane, false)
		box(root, Vector3(0.1, 2.1, 0.12), Vector3(x, 2.2, -HALF_Z + 0.06), bar, false)
		box(root, Vector3(1.5, 0.1, 0.12), Vector3(x, 2.4, -HALF_Z + 0.06), bar, false)
		box(root, Vector3(1.7, 0.12, 0.3), Vector3(x, 1.15, -HALF_Z + 0.12), bar, false)
		# A soft shaft of moonlight slanting down into the room.
		var shaft := box(root, Vector3(1.3, 1.0, 6.0), Vector3(x, 1.3, -HALF_Z + 2.6), beam, false)
		shaft.rotation.x = -0.45
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _candle(root: Node3D, pos: Vector3, out: Dictionary, light: bool, flame_color: Color = Color(1.0, 0.7, 0.3)) -> void:
	cyl(root, 0.04, 0.045, 0.22, pos + Vector3(0, 0.11, 0), mat(Color(0.95, 0.9, 0.8)), 8)
	var flame := ball(root, 0.035, pos + Vector3(0, 0.27, 0), mat(flame_color, 6.0), 1.6)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if light:
		var l := OmniLight3D.new()
		l.light_color = flame_color
		l.light_energy = 1.4
		l.omni_range = 5.5
		l.shadow_enabled = false
		l.position = pos + Vector3(0, 0.45, 0)
		l.set_meta("base", 1.4)
		root.add_child(l)
		out.candles.append(l)


static func _table(root: Node3D, pos: Vector3, size: Vector3, wood: Material) -> void:
	box(root, Vector3(size.x, 0.08, size.z), pos + Vector3(0, size.y, 0), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(root, Vector3(0.08, size.y, 0.08), pos + Vector3(sx * (size.x / 2.0 - 0.08), size.y / 2.0, sz * (size.z / 2.0 - 0.08)), wood, false)


static func _pumpkin(root: Node3D, pos: Vector3) -> void:
	ball(root, 0.28, pos + Vector3(0, 0.22, 0), mat(Color(1.0, 0.45, 0.08), 0.4), 0.75)
	cyl(root, 0.03, 0.04, 0.12, pos + Vector3(0, 0.48, 0), mat(Color(0.2, 0.5, 0.15)), 6)
	var face := box(root, Vector3(0.22, 0.08, 0.05), pos + Vector3(0, 0.2, 0.24), mat(Color(1.0, 0.85, 0.2), 4.0), false)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-0.07, 0.07]:
		box(root, Vector3(0.06, 0.06, 0.05), pos + Vector3(sx, 0.32, 0.23), mat(Color(1.0, 0.85, 0.2), 4.0), false)


static func _hall(root: Node3D, out: Dictionary) -> void:
	var wood := mat(Color(0.28, 0.15, 0.12))
	# Big round rug.
	cyl(root, 3.2, 3.2, 0.02, Vector3(0, 0.01, 0.5), mat(Color(0.35, 0.12, 0.3)), 24)
	cyl(root, 2.4, 2.4, 0.025, Vector3(0, 0.012, 0.5), mat(Color(0.15, 0.4, 0.28)), 24)
	# Sofa against the south wall.
	var plush := mat(Color(0.45, 0.2, 0.5))
	box(root, Vector3(2.8, 0.45, 0.9), Vector3(0, 0.22, 6.9), plush)
	box(root, Vector3(2.8, 0.9, 0.25), Vector3(0, 0.75, 7.45), plush)
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.25, 0.7, 0.9), Vector3(sx * 1.4, 0.35, 6.9), plush)
	# Side tables with candles.
	for x in [-4.8, 4.8]:
		_table(root, Vector3(x, 0, 6.6), Vector3(0.8, 0.75, 0.8), wood)
		_candle(root, Vector3(x, 0.79, 6.6), out, true)
	# Grandfather clock with a swinging pendulum.
	box(root, Vector3(0.7, 2.5, 0.45), Vector3(-6.3, 1.25, -6.5), wood)
	var clock_face := ball(root, 0.22, Vector3(-6.3, 2.05, -6.25), mat(Color(0.95, 0.9, 0.7), 1.2), 0.15)
	clock_face.rotation.x = PI / 2.0
	var pend := Node3D.new()
	pend.position = Vector3(-6.3, 1.7, -6.24)
	root.add_child(pend)
	cyl(pend, 0.015, 0.015, 0.7, Vector3(0, -0.35, 0), mat(Color(0.8, 0.65, 0.25), 0.5), 6)
	ball(pend, 0.08, Vector3(0, -0.72, 0), mat(Color(0.9, 0.75, 0.3), 0.8))
	out.anim.append([pend, "pendulum"])
	# Front door (decoration).
	box(root, Vector3(1.6, 2.6, 0.1), Vector3(0, 1.3, HALF_Z - 0.02), mat(Color(0.18, 0.08, 0.1)), false)
	# Coat stand and pumpkins.
	cyl(root, 0.04, 0.05, 1.8, Vector3(6.2, 0.9, 6.9), wood, 8)
	ball(root, 0.2, Vector3(6.2, 1.75, 6.9), mat(Color(0.25, 0.1, 0.3)), 0.6)
	_pumpkin(root, Vector3(-2.2, 0, -7.2))
	_pumpkin(root, Vector3(2.2, 0, -7.2))


static func _library(root: Node3D, out: Dictionary) -> void:
	var wood := mat(Color(0.24, 0.13, 0.1))
	var book_colors := [Color(0.5, 0.15, 0.2), Color(0.18, 0.4, 0.3), Color(0.35, 0.2, 0.5), Color(0.6, 0.45, 0.2)]
	# Tall bookshelves on the west wall, either side of the fireplace.
	for z in [-5.0, 5.0]:
		box(root, Vector3(0.55, 3.2, 3.2), Vector3(-HALF_X + 0.3, 1.6, z), wood)
		for shelf in 4:
			var bc: Color = book_colors[(shelf + absi(int(z))) % book_colors.size()]
			box(root, Vector3(0.45, 0.5, 2.9), Vector3(-HALF_X + 0.35, 0.45 + shelf * 0.75, z), mat(bc), false)
	# Fireplace with ghostly green flames.
	var stone := mat(Color(0.25, 0.22, 0.28))
	box(root, Vector3(0.6, 1.6, 2.4), Vector3(-HALF_X + 0.3, 0.8, 0), stone)
	box(root, Vector3(0.1, 1.0, 1.4), Vector3(-HALF_X + 0.62, 0.55, 0), mat(Color(0.02, 0.02, 0.03)), false)
	var fire := ball(root, 0.35, Vector3(-HALF_X + 0.75, 0.35, 0), mat(Color(0.35, 1.0, 0.5), 5.0), 1.4)
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out.anim.append([fire, "flame"])
	var fl := OmniLight3D.new()
	fl.light_color = Color(0.35, 1.0, 0.5)
	fl.light_energy = 2.0
	fl.omni_range = 7.0
	fl.position = Vector3(-HALF_X + 1.3, 0.8, 0)
	fl.set_meta("base", 2.0)
	root.add_child(fl)
	out.candles.append(fl)
	# Reading table, armchair and a rocking chair that rocks all by itself.
	_table(root, Vector3(-14.0, 0, -2.0), Vector3(2.2, 0.78, 1.2), wood)
	_candle(root, Vector3(-14.4, 0.82, -2.0), out, true)
	box(root, Vector3(0.5, 0.15, 0.4), Vector3(-13.6, 0.9, -2.1), mat(Color(0.5, 0.15, 0.2)), false)
	var arm := mat(Color(0.18, 0.38, 0.3))
	box(root, Vector3(1.0, 0.5, 1.0), Vector3(-17.0, 0.25, 3.0), arm)
	box(root, Vector3(1.0, 1.0, 0.25), Vector3(-17.0, 0.75, 3.45), arm)
	var rocker := Node3D.new()
	rocker.position = Vector3(-11.0, 0, 4.5)
	root.add_child(rocker)
	box(rocker, Vector3(0.7, 0.08, 0.7), Vector3(0, 0.5, 0), wood, false)
	box(rocker, Vector3(0.7, 0.9, 0.08), Vector3(0, 0.95, 0.33), wood, false)
	for sx in [-0.3, 0.3]:
		box(rocker, Vector3(0.06, 0.06, 1.0), Vector3(sx, 0.05, 0), wood, false)
		box(rocker, Vector3(0.06, 0.45, 0.06), Vector3(sx, 0.27, 0), wood, false)
	out.anim.append([rocker, "rock"])
	# Globe.
	cyl(root, 0.05, 0.25, 0.8, Vector3(-9.0, 0.4, -6.0), wood, 8)
	ball(root, 0.32, Vector3(-9.0, 1.15, -6.0), mat(Color(0.25, 0.45, 0.6), 0.2))
	_pumpkin(root, Vector3(-8.0, 0, 6.8))


static func _ballroom(root: Node3D, out: Dictionary) -> void:
	var gold := mat(Color(0.85, 0.65, 0.25), 0.3, 0.4)
	# Grand piano.
	var black := mat(Color(0.05, 0.04, 0.07), 0.0, 0.3)
	box(root, Vector3(2.0, 0.45, 1.5), Vector3(14.0, 0.95, -5.6), black)
	var lid := box(root, Vector3(2.0, 0.06, 1.5), Vector3(14.0, 1.6, -5.9), black, false)
	lid.rotation.x = -0.6
	box(root, Vector3(1.6, 0.06, 0.25), Vector3(14.0, 1.2, -4.75), mat(Color(0.95, 0.95, 0.9)), false)
	for p in [Vector3(13.2, 0.36, -6.1), Vector3(14.8, 0.36, -6.1), Vector3(14.0, 0.36, -5.0)]:
		box(root, Vector3(0.12, 0.72, 0.12), p, black, false)
	_candle(root, Vector3(13.3, 1.18, -5.4), out, true, Color(0.55, 1.0, 0.6))
	# Chandelier with a ring of candles.
	var ch := Node3D.new()
	ch.position = Vector3(14.0, 3.3, 0.5)
	root.add_child(ch)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 0.9
	tm.rings = 16
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = gold
	ch.add_child(ring)
	cyl(ch, 0.02, 0.02, 0.9, Vector3(0, 0.45, 0), gold, 6)
	for i in 6:
		var a := TAU * i / 6.0
		var flame := ball(ch, 0.04, Vector3(cos(a) * 0.85, 0.12, sin(a) * 0.85), mat(Color(1.0, 0.75, 0.35), 6.0), 1.6)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cl := OmniLight3D.new()
	cl.light_color = Color(1.0, 0.72, 0.4)
	cl.light_energy = 2.2
	cl.omni_range = 9.0
	cl.position = Vector3(0, -0.2, 0)
	cl.set_meta("base", 2.2)
	ch.add_child(cl)
	out.candles.append(cl)
	out.anim.append([ch, "sway"])
	# Pillars, chairs along the wall, a table with punch.
	for p in [Vector3(9.0, 0, -5.5), Vector3(19.0, 0, -5.5), Vector3(9.0, 0, 5.5), Vector3(19.0, 0, 5.5)]:
		var pillar := cyl(root, 0.3, 0.35, WALL_H, p + Vector3(0, WALL_H / 2.0, 0), mat(Color(0.42, 0.34, 0.5)), 12)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.35
		shape.height = WALL_H
		cs.shape = shape
		body.add_child(cs)
		pillar.add_child(body)
	var seat := mat(Color(0.5, 0.2, 0.45))
	for x in [11.0, 12.5, 15.5, 17.0]:
		box(root, Vector3(0.5, 0.5, 0.5), Vector3(x, 0.25, 7.3), seat)
		box(root, Vector3(0.5, 0.6, 0.08), Vector3(x, 0.8, 7.55), seat, false)
	_table(root, Vector3(19.5, 0, 0.0), Vector3(0.9, 0.8, 2.0), mat(Color(0.3, 0.16, 0.14)))
	cyl(root, 0.25, 0.18, 0.3, Vector3(19.5, 0.98, 0.0), mat(Color(0.4, 1.0, 0.6), 1.5), 12)
	_candle(root, Vector3(19.5, 0.84, -0.7), out, false)
	_candle(root, Vector3(19.5, 0.84, 0.7), out, false)
	_pumpkin(root, Vector3(8.0, 0, -7.2))
	_pumpkin(root, Vector3(20.0, 0, 7.0))
