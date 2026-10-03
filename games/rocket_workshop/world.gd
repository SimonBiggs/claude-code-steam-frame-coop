extends RefCounted
## Builds the cosy open-air rocket workshop: plank floor, cream walls with roof beams and bunting,
## workbenches and crates, and the launch yard with its pad, gantry tower, trees and hills.
## Everything is procedural; bunting and trees are MultiMeshes to keep draw calls low.

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 wood_a : source_color = vec3(0.72, 0.5, 0.32);
uniform vec3 wood_b : source_color = vec3(0.58, 0.38, 0.22);
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float plank = floor(w.x * 1.6);
	float row = floor(w.z * 0.35 + fract(plank * 0.37) * 3.0);
	float n = fract(sin(plank * 12.9898 + row * 78.233) * 43758.5453);
	float seam = step(0.95, fract(w.x * 1.6)) + step(0.985, fract(w.z * 0.35 + fract(plank * 0.37) * 3.0));
	ALBEDO = mix(wood_a, wood_b, n * 0.7) * (1.0 - clamp(seam, 0.0, 1.0) * 0.4);
	ROUGHNESS = 0.8;
}
"""

const BUNTING_COLORS: Array[Color] = [Color(1.0, 0.35, 0.3), Color(1.0, 0.8, 0.25), Color(0.35, 0.75, 1.0), Color(0.45, 0.85, 0.4), Color(0.9, 0.5, 0.9)]


static func build(main: Node3D, vr: bool) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.6, 0.95)
	sky_mat.sky_horizon_color = Color(0.95, 0.85, 0.75)
	sky_mat.ground_horizon_color = Color(0.75, 0.8, 0.6)
	sky_mat.ground_bottom_color = Color(0.3, 0.45, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.6 if vr else 0.8
	e.glow_hdr_threshold = 1.0
	if not vr:
		e.fog_enabled = true
		e.fog_light_color = Color(0.85, 0.85, 0.95)
		e.fog_density = 0.004
		e.fog_sky_affect = 0.0
	env.environment = e
	main.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.1
	sun.shadow_enabled = not vr
	sun.directional_shadow_max_distance = 40.0
	main.add_child(sun)

	# Plank floor of the workshop and grass outside.
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = Shader.new()
	floor_mat.shader.code = FLOOR_SHADER
	_box(main, Vector3(22.4, 0.1, 14.4), Vector3(0, -0.05, 1.0), floor_mat)
	var grass := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	grass.mesh = pm
	grass.material_override = main.make_material(Color(0.45, 0.72, 0.35), 0.0)
	grass.position = Vector3(0, -0.02, 0)
	main.add_child(grass)

	# Walls: west, east, south, and two stubs either side of the big open launch doorway.
	var wall: StandardMaterial3D = main.make_material(Color(0.98, 0.9, 0.78), 0.0)
	var trim: StandardMaterial3D = main.make_material(Color(0.55, 0.75, 0.85), 0.0)
	_box(main, Vector3(0.3, 4.0, 14.4), Vector3(-11.15, 2.0, 1.0), wall)
	_box(main, Vector3(0.3, 4.0, 14.4), Vector3(11.15, 2.0, 1.0), wall)
	_box(main, Vector3(22.6, 4.0, 0.3), Vector3(0, 2.0, 8.15), wall)
	_box(main, Vector3(7.0, 4.0, 0.3), Vector3(-7.65, 2.0, -6.15), wall)
	_box(main, Vector3(7.0, 4.0, 0.3), Vector3(7.65, 2.0, -6.15), wall)
	_box(main, Vector3(22.2, 0.7, 0.05), Vector3(0, 0.35, 7.98), trim)
	_box(main, Vector3(0.05, 0.7, 14.0), Vector3(-10.98, 0.35, 1.0), trim)
	_box(main, Vector3(0.05, 0.7, 14.0), Vector3(10.98, 0.35, 1.0), trim)
	# Roof beams (no roof, so everyone can watch the rockets fly).
	var beam: StandardMaterial3D = main.make_material(Color(0.55, 0.36, 0.22), 0.0)
	for z in [-5.0, -1.0, 3.0, 7.0]:
		_box(main, Vector3(22.6, 0.3, 0.3), Vector3(0, 4.15, z), beam)
	_bunting(main)

	# The pilot's booth: a striped mat around the control desk.
	_box(main, Vector3(2.6, 0.03, 2.2), Vector3(0, 0.015, -0.1), main.make_material(Color(0.95, 0.75, 0.2), 0.0))
	_box(main, Vector3(2.3, 0.04, 1.9), Vector3(0, 0.02, -0.1), main.make_material(Color(0.3, 0.32, 0.4), 0.0))

	# Workbenches, crates and shelves (the canister spots sit on these).
	var bench: StandardMaterial3D = main.make_material(Color(0.7, 0.45, 0.28), 0.0)
	var crate: StandardMaterial3D = main.make_material(Color(0.8, 0.6, 0.35), 0.0)
	var tool_red: StandardMaterial3D = main.make_material(Color(0.9, 0.25, 0.2), 0.0)
	for spot in [Vector3(-9.0, 0, 6.5), Vector3(9.0, 0, 6.5), Vector3(-9.0, 0, -4.5), Vector3(9.0, 0, -4.5)]:
		_box(main, Vector3(2.0, 0.08, 1.0), spot + Vector3(0, 0.9, 0), bench)
		_box(main, Vector3(1.8, 0.86, 0.8), spot + Vector3(0, 0.43, 0), main.make_material(Color(0.5, 0.33, 0.2), 0.0))
	for c in [Vector3(-6.5, 0.4, 7.2), Vector3(6.8, 0.4, -5.2), Vector3(-7.4, 0.4, -5.4), Vector3(7.5, 0.4, 7.3)]:
		_box(main, Vector3(0.8, 0.8, 0.8), c, crate)
	_box(main, Vector3(0.6, 0.35, 0.3), Vector3(-6.5, 0.98, 7.2), tool_red)
	_box(main, Vector3(0.6, 0.35, 0.3), Vector3(6.8, 0.98, -5.2), tool_red)

	# Launch yard: pad, hazard ring, gantry tower and a few trees and hills.
	var pad_pos: Vector3 = main.PAD_POS
	var pad := MeshInstance3D.new()
	pad.mesh = main.cyl_mesh(2.4, 2.6, 0.3, 24)
	pad.material_override = main.make_material(Color(0.62, 0.62, 0.66), 0.0)
	pad.position = pad_pos + Vector3(0, 0.15, 0)
	main.add_child(pad)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.9
	tm.outer_radius = 2.15
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = main.make_material(Color(1.0, 0.8, 0.15), 0.4)
	ring.scale = Vector3(1, 0.2, 1)
	ring.position = pad_pos + Vector3(0, 0.31, 0)
	main.add_child(ring)
	var steel: StandardMaterial3D = main.make_material(Color(0.85, 0.3, 0.25), 0.0)
	_box(main, Vector3(0.35, 7.0, 0.35), pad_pos + Vector3(-3.2, 3.5, -0.5), steel)
	_box(main, Vector3(0.35, 7.0, 0.35), pad_pos + Vector3(-3.2, 3.5, 0.5), steel)
	for y in [1.5, 3.2, 4.9, 6.6]:
		_box(main, Vector3(0.25, 0.2, 1.3), pad_pos + Vector3(-3.2, y, 0), steel)
		_box(main, Vector3(1.4, 0.15, 0.2), pad_pos + Vector3(-2.5, y, 0), steel)
	# Hatch marker where fuel canisters go.
	var hatch := MeshInstance3D.new()
	hatch.mesh = main.cyl_mesh(0.9, 0.9, 0.04, 20)
	hatch.material_override = main.make_material(Color(0.95, 0.55, 0.2), 0.5)
	hatch.position = main.HATCH_POS + Vector3(0, 0.02, 0)
	main.add_child(hatch)
	_trees(main)
	var hill: StandardMaterial3D = main.make_material(Color(0.4, 0.66, 0.35), 0.0)
	for h in [Vector3(-30, -6, -45), Vector3(10, -9, -55), Vector3(40, -7, -35), Vector3(-45, -8, -15)]:
		var mi := MeshInstance3D.new()
		mi.mesh = main.sphere_mesh(1.0)
		mi.material_override = hill
		mi.position = h
		mi.scale = Vector3(22, 14, 18)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(mi)


static func _box(main: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	main.add_child(mi)
	return mi


## Little triangle flags strung between the roof beams.
static func _bunting(main: Node3D) -> void:
	var flag := PrismMesh.new()
	flag.size = Vector3(0.35, 0.4, 0.02)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = flag
	var lines: Array = [[Vector3(-10.8, 3.6, -5.0), Vector3(10.8, 3.6, -1.0)], [Vector3(-10.8, 3.6, 3.0), Vector3(10.8, 3.6, -1.0)],
		[Vector3(-10.8, 3.6, 3.0), Vector3(10.8, 3.6, 7.0)]]
	var per := 28
	mm.instance_count = lines.size() * per
	var i := 0
	for line in lines:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var dir := (b - a).normalized()
		var yaw := atan2(-dir.z, dir.x)
		for k in per:
			var t := (k + 0.5) / per
			var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * 0.6
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI), p))
			mm.set_instance_color(i, BUNTING_COLORS[k % BUNTING_COLORS.size()])
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mmi)


static func _trees(main: Node3D) -> void:
	var spots: Array[Vector3] = [Vector3(-9, 0, -12), Vector3(-12, 0, -16), Vector3(8, 0, -14), Vector3(12, 0, -10),
		Vector3(-15, 0, -8), Vector3(15, 0, -17), Vector3(3, 0, -20), Vector3(-6, 0, -21)]
	var leaves := MultiMesh.new()
	leaves.transform_format = MultiMesh.TRANSFORM_3D
	leaves.mesh = main.sphere_mesh(1.0)
	leaves.instance_count = spots.size()
	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = main.cyl_mesh(0.18, 0.25, 1.6, 8)
	trunks.instance_count = spots.size()
	for i in spots.size():
		var s := 0.9 + fmod(i * 0.37, 0.6)
		trunks.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), spots[i] + Vector3(0, 0.8 * s, 0)))
		leaves.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.3, 1.5, 1.3) * s), spots[i] + Vector3(0, 2.4 * s, 0)))
	var a := MultiMeshInstance3D.new()
	a.multimesh = leaves
	a.material_override = main.make_material(Color(0.3, 0.62, 0.3), 0.0)
	main.add_child(a)
	var b := MultiMeshInstance3D.new()
	b.multimesh = trunks
	b.material_override = main.make_material(Color(0.5, 0.33, 0.2), 0.0)
	main.add_child(b)
