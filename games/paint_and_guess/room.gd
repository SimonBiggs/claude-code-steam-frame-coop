extends Node3D
## The cosy art studio around the easel. Nearly everything static is merged into TWO meshes (one lit,
## one glowing), so the whole room costs a handful of draw calls on the Steam Frame:
## planked floor, rug and paint splats, walls with a window (sunny sky), shelves of paint jars and
## books, plants, a toy pile, paper lanterns, bunting, a gallery wall of empty frames.
## Moving bits: twinkling string lights (one MultiMesh + shader), a sleeping cat that breathes and
## swishes its tail (and jumps up when everyone guesses right), drifting dust motes, and the gallery:
## every finished drawing flies from the easel into a frame; the vote's winner gets a gold frame.

const MeshKit := preload("res://games/paint_and_guess/mesh_kit.gd")

const BACK_Z := -3.2
const SIDE_X := 4.2
const FRONT_Z := 4.6
const CEIL_Y := 3.5
const PIC_SCALE := 0.42
const SLOTS: Array[Vector3] = [Vector3(-2.05, 1.95, 0.0), Vector3(2.05, 1.95, 0.0), Vector3(-3.1, 1.95, 0.0),
	Vector3(3.1, 1.95, 0.0), Vector3(-2.55, 1.25, 0.0), Vector3(2.55, 1.25, 0.0)]
const LIGHTS_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float speed = 2.2;
uniform float gold = 0.0;
varying float tw;
void vertex() {
	tw = 0.6 + 0.4 * sin(TIME * speed + float(INSTANCE_ID) * 1.9);
}
void fragment() {
	ALBEDO = mix(COLOR.rgb, vec3(1.0, 0.8, 0.3), gold) * (0.55 + 0.6 * tw);
}
"""

var main
var t := 0.0
var cat: Node3D
var cat_body: MeshInstance3D
var cat_tail: Node3D
var cat_hop := 0.0
var lights_mm: MultiMeshInstance3D
var light_mat: ShaderMaterial
var pictures := {}  # slot -> {mi, label}
var gold_root: Node3D


func build() -> void:
	var lit: Array = []
	var glow: Array = []
	var cream := Color(0.96, 0.88, 0.7)
	var wood := Color(0.62, 0.42, 0.25)
	var dark := Color(0.42, 0.28, 0.16)
	# Floor, planks and walls.
	lit.append([MeshKit.box(Vector3(SIDE_X * 2.0, 0.02, FRONT_Z - BACK_Z)), MeshKit.at(Vector3(0, -0.01, (FRONT_Z + BACK_Z) * 0.5)), Color(0.66, 0.46, 0.3)])
	var z := BACK_Z + 0.25
	while z < FRONT_Z:
		lit.append([MeshKit.box(Vector3(SIDE_X * 2.0, 0.004, 0.012)), MeshKit.at(Vector3(0, 0.001, z)), Color(0.5, 0.33, 0.2)])
		z += 0.26
	lit.append([MeshKit.box(Vector3(SIDE_X * 2.0, CEIL_Y, 0.1)), MeshKit.at(Vector3(0, CEIL_Y * 0.5, BACK_Z)), cream])
	lit.append([MeshKit.box(Vector3(SIDE_X * 2.0, 0.95, 0.04)), MeshKit.at(Vector3(0, 0.475, BACK_Z + 0.07)), Color(0.55, 0.75, 0.65)])
	lit.append([MeshKit.box(Vector3(SIDE_X * 2.0, 0.05, 0.07)), MeshKit.at(Vector3(0, 0.96, BACK_Z + 0.08)), Color(1, 1, 1)])
	for sx in [-1.0, 1.0]:
		lit.append([MeshKit.box(Vector3(0.1, CEIL_Y, FRONT_Z - BACK_Z)), MeshKit.at(Vector3(sx * SIDE_X, CEIL_Y * 0.5, (FRONT_Z + BACK_Z) * 0.5)), Color(0.98, 0.82, 0.72) if sx < 0 else Color(0.8, 0.88, 0.98)])
		lit.append([MeshKit.box(Vector3(0.04, 0.95, FRONT_Z - BACK_Z)), MeshKit.at(Vector3(sx * (SIDE_X - 0.07), 0.475, (FRONT_Z + BACK_Z) * 0.5)), Color(0.55, 0.75, 0.65)])
	lit.append([MeshKit.box(Vector3(SIDE_X * 2.0, CEIL_Y, 0.1)), MeshKit.at(Vector3(0, CEIL_Y * 0.5, FRONT_Z)), cream])
	lit.append([MeshKit.box(Vector3(SIDE_X * 2.0, 0.08, FRONT_Z - BACK_Z)), MeshKit.at(Vector3(0, CEIL_Y, (FRONT_Z + BACK_Z) * 0.5)), Color(1.0, 0.96, 0.9)])
	for k in 5:
		lit.append([MeshKit.box(Vector3(0.12, 0.08, FRONT_Z - BACK_Z)), MeshKit.at(Vector3(-3.4 + k * 1.7, CEIL_Y - 0.08, (FRONT_Z + BACK_Z) * 0.5)), wood])
	# Rug and paint splats around the easel.
	var rug_cols: Array[Color] = [Color(0.9, 0.45, 0.4), Color(1.0, 0.85, 0.55), Color(0.35, 0.7, 0.75), Color(1.0, 0.9, 0.6)]
	for k in 4:
		lit.append([MeshKit.cyl(1.75 - k * 0.38, 1.75 - k * 0.38, 0.008 + k * 0.002, 28), MeshKit.at(Vector3(0, 0.004 + k * 0.001, 0.75)), rug_cols[k]])
	var splat_cols: Array[Color] = [Color(1.0, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.9, 0.4), Color(0.8, 0.45, 1.0)]
	for k in 9:
		var a := float(k) * 2.4
		var rr := 1.0 + fmod(k * 0.37, 0.8)
		lit.append([MeshKit.cyl(0.06 + fmod(k * 0.07, 0.08), 0.06 + fmod(k * 0.07, 0.08), 0.004, 10),
			MeshKit.at(Vector3(cos(a) * rr * 1.2, 0.017 + k * 0.0002, -0.4 + sin(a) * rr * 0.5), Vector3(1.0, 1.0, 0.7)), splat_cols[k % splat_cols.size()]])
	# Window on the left wall with a sunny sky behind it.
	var wz := -0.6
	var wy := 1.85
	var wx := -SIDE_X + 0.06
	glow.append([MeshKit.box(Vector3(0.01, 0.42, 1.6)), MeshKit.at(Vector3(wx, wy + 0.34, wz)), Color(0.35, 0.65, 1.0)])
	glow.append([MeshKit.box(Vector3(0.01, 0.38, 1.6)), MeshKit.at(Vector3(wx, wy - 0.04, wz)), Color(0.55, 0.8, 1.0)])
	glow.append([MeshKit.box(Vector3(0.01, 0.3, 1.6)), MeshKit.at(Vector3(wx, wy - 0.38, wz)), Color(0.45, 0.8, 0.45)])
	glow.append([MeshKit.sphere(0.13, 14), MeshKit.at(Vector3(wx + 0.012, wy + 0.28, wz + 0.45), Vector3(0.2, 1, 1)), Color(1.0, 0.9, 0.4)])
	for k in 3:
		var cz := wz - 0.5 + k * 0.45
		var cyv := wy + 0.12 + 0.1 * (k % 2)
		for j in 3:
			glow.append([MeshKit.sphere(0.06 + 0.02 * (j % 2), 10), MeshKit.at(Vector3(wx + 0.016, cyv + 0.02 * (j % 2), cz + j * 0.07), Vector3(0.2, 0.8, 1.2)), Color(1, 1, 1)])
	for k in 3:
		lit.append([MeshKit.box(Vector3(0.08, 1.2, 0.06)), MeshKit.at(Vector3(wx + 0.04, wy, wz - 0.8 + k * 0.8)), Color(1, 1, 1)])
		lit.append([MeshKit.box(Vector3(0.08, 0.06, 1.66)), MeshKit.at(Vector3(wx + 0.04, wy - 0.58 + k * 0.58, wz)), Color(1, 1, 1)])
	lit.append([MeshKit.box(Vector3(0.2, 0.05, 1.8)), MeshKit.at(Vector3(wx + 0.08, wy - 0.62, wz)), Color(1, 1, 1)])
	# A potted flower on the window sill.
	lit.append([MeshKit.cyl(0.07, 0.05, 0.12, 10), MeshKit.at(Vector3(wx + 0.1, wy - 0.53, wz + 0.5)), Color(0.85, 0.45, 0.3)])
	for k in 5:
		var fa := TAU * k / 5.0
		lit.append([MeshKit.sphere(0.03, 8), MeshKit.at(Vector3(wx + 0.1 + cos(fa) * 0.035, wy - 0.33, wz + 0.5 + sin(fa) * 0.035)), Color(1.0, 0.5, 0.7)])
	lit.append([MeshKit.sphere(0.022, 8), MeshKit.at(Vector3(wx + 0.1, wy - 0.33, wz + 0.5)), Color(1.0, 0.85, 0.2)])
	lit.append([MeshKit.cyl(0.006, 0.006, 0.16, 6), MeshKit.at(Vector3(wx + 0.1, wy - 0.42, wz + 0.5)), Color(0.3, 0.6, 0.3)])
	# Shelves of paint jars and books on the right wall.
	var shx := SIDE_X - 0.2
	var jar_cols: Array[Color] = [Color(1.0, 0.3, 0.3), Color(1.0, 0.6, 0.15), Color(1.0, 0.9, 0.2), Color(0.3, 0.9, 0.35),
		Color(0.25, 0.75, 1.0), Color(0.6, 0.4, 1.0), Color(1.0, 0.45, 0.8), Color(1, 1, 1)]
	for row in 2:
		var y := 1.25 + row * 0.5
		lit.append([MeshKit.box(Vector3(0.3, 0.04, 1.8)), MeshKit.at(Vector3(shx, y, -0.9)), wood])
		for k in 7:
			var jz := -1.65 + k * 0.2
			if row == 1 and k > 3:
				var bh := 0.2 + fmod(k * 0.07, 0.08)
				lit.append([MeshKit.box(Vector3(0.18, bh, 0.05)), MeshKit.at(Vector3(shx, y + 0.02 + bh * 0.5, jz)), jar_cols[(k * 3) % jar_cols.size()].darkened(0.2)])
				continue
			var jc := jar_cols[(k + row * 3) % jar_cols.size()]
			lit.append([MeshKit.cyl(0.055, 0.055, 0.13, 10), MeshKit.at(Vector3(shx, y + 0.085, jz)), jc])
			lit.append([MeshKit.cyl(0.058, 0.058, 0.03, 10), MeshKit.at(Vector3(shx, y + 0.16, jz)), Color(0.9, 0.9, 0.92)])
	# Plants in the back corners.
	for sx in [-1.0, 1.0]:
		var px: float = sx * (SIDE_X - 0.55)
		var pz := BACK_Z + 0.5
		lit.append([MeshKit.cyl(0.24, 0.18, 0.42, 12), MeshKit.at(Vector3(px, 0.21, pz)), Color(0.85, 0.5, 0.35)])
		for k in 6:
			var la := TAU * k / 6.0
			lit.append([MeshKit.sphere(0.24, 10), MeshKit.at(Vector3(px + cos(la) * 0.16, 0.75 + 0.12 * (k % 2), pz + sin(la) * 0.16), Vector3(1.0, 1.3, 1.0)),
				Color(0.3, 0.65 + 0.05 * (k % 3), 0.32)])
		lit.append([MeshKit.sphere(0.2, 10), MeshKit.at(Vector3(px, 1.05, pz)), Color(0.38, 0.75, 0.38)])
	# Toy pile: building blocks and a ball.
	var toy_pos: Array[Vector3] = [Vector3(-2.2, 0.12, 0.6), Vector3(-2.45, 0.1, 0.9), Vector3(-2.3, 0.33, 0.68), Vector3(2.5, 0.12, 1.4), Vector3(2.75, 0.1, 1.1)]
	for k in toy_pos.size():
		var s := toy_pos[k].y * 2.0
		lit.append([MeshKit.box(Vector3(s, s, s)), MeshKit.at(toy_pos[k], Vector3.ONE, Vector3(0, k * 0.6, 0)), jar_cols[(k * 2 + 1) % jar_cols.size()]])
	lit.append([MeshKit.sphere(0.16, 14), MeshKit.at(Vector3(-1.8, 0.16, 1.5)), Color(1.0, 0.35, 0.35)])
	lit.append([MeshKit.sphere(0.162, 14), MeshKit.at(Vector3(-1.8, 0.16, 1.5), Vector3(1.0, 0.3, 1.0)), Color(1, 1, 1)])
	# Cat cushion.
	lit.append([MeshKit.cyl(0.36, 0.38, 0.1, 18), MeshKit.at(Vector3(1.55, 0.05, -0.35), Vector3(1.0, 1.0, 0.8)), Color(0.6, 0.45, 0.85)])
	# Gallery frames on the back wall (pictures get hung in them during the game).
	for k in SLOTS.size():
		var fp := slot_pos(k)
		lit.append([MeshKit.box(Vector3(0.68, 0.5, 0.04)), MeshKit.at(fp + Vector3(0, 0, -0.03)), wood if k % 2 == 0 else dark])
		lit.append([MeshKit.box(Vector3(0.6, 0.42, 0.01)), MeshKit.at(fp + Vector3(0, 0, -0.008)), Color(0.07, 0.08, 0.15)])
		lit.append([MeshKit.box(Vector3(0.012, 0.05, 0.012)), MeshKit.at(fp + Vector3(0, 0.3, -0.04)), Color(0.3, 0.3, 0.3)])
	# Bunting strings along the side walls and lantern cords.
	for sx in [-1.0, 1.0]:
		lit.append([MeshKit.box(Vector3(0.01, 0.01, 6.6)), MeshKit.at(Vector3(sx * 2.4, 3.05, 0.4)), Color(0.9, 0.9, 0.9)])
	var lanterns: Array[Vector3] = [Vector3(-2.4, 2.85, 1.4), Vector3(2.4, 2.85, 1.4), Vector3(0.0, 3.0, 2.9), Vector3(-1.6, 3.0, -1.9), Vector3(1.6, 3.0, -1.9)]
	var lan_cols: Array[Color] = [Color(1.0, 0.75, 0.5), Color(1.0, 0.6, 0.75), Color(0.75, 0.9, 1.0), Color(1.0, 0.9, 0.55), Color(0.8, 1.0, 0.7)]
	for k in lanterns.size():
		var lp := lanterns[k]
		lit.append([MeshKit.cyl(0.004, 0.004, CEIL_Y - lp.y, 4), MeshKit.at(Vector3(lp.x, (CEIL_Y + lp.y) * 0.5, lp.z)), Color(0.2, 0.2, 0.2)])
		glow.append([MeshKit.sphere(0.2, 14), MeshKit.at(lp, Vector3(1.0, 0.85, 1.0)), lan_cols[k]])
		lit.append([MeshKit.cyl(0.08, 0.08, 0.04, 10), MeshKit.at(lp + Vector3(0, 0.18, 0)), Color(0.3, 0.25, 0.2)])
	var static_lit := MeshInstance3D.new()
	static_lit.mesh = MeshKit.merge(lit)
	static_lit.material_override = MeshKit.vertex_material(main.mats)
	add_child(static_lit)
	var static_glow := MeshInstance3D.new()
	static_glow.mesh = MeshKit.merge(glow)
	static_glow.material_override = MeshKit.vertex_material(main.mats, true)
	static_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(static_glow)
	_build_bunting()
	_build_lights()
	_build_cat()
	_build_dust()
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 0.7
	lamp.omni_range = 6.5
	lamp.position = Vector3(0, 2.9, 0.8)
	add_child(lamp)


func slot_pos(k: int) -> Vector3:
	var s := SLOTS[k % SLOTS.size()]
	return Vector3(s.x, s.y, BACK_Z + 0.1)


func _build_bunting() -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var pm := PrismMesh.new()
	pm.size = Vector3(0.16, 0.2, 0.01)
	mm.mesh = pm
	var n := 22
	mm.instance_count = n * 2
	var cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.8, 0.2), Color(0.35, 0.75, 1.0), Color(0.45, 0.9, 0.45), Color(0.85, 0.5, 1.0)]
	for side in 2:
		var sx := -2.4 if side == 0 else 2.4
		for k in n:
			var zz := -2.8 + 6.6 * float(k) / float(n - 1)
			var xf := Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI), Vector3(sx, 2.95, zz))
			mm.set_instance_transform(side * n + k, xf)
			mm.set_instance_color(side * n + k, cols[(k + side) % cols.size()])
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = mat
	add_child(mmi)


## Fairy lights: along the top of all three walls, twinkling in a shader (no per-frame CPU work).
func _build_lights() -> void:
	lights_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshKit.sphere(0.03, 8)
	var pts: Array[Vector3] = []
	for k in 26:
		var u := float(k) / 25.0
		pts.append(Vector3(-SIDE_X + 0.15 + u * (SIDE_X * 2.0 - 0.3), 3.3 - 0.12 * sin(u * PI * 3.0) * sin(u * PI * 3.0), BACK_Z + 0.12))
	for sx in [-1.0, 1.0]:
		for k in 16:
			var u := float(k) / 15.0
			pts.append(Vector3(sx * (SIDE_X - 0.12), 3.3 - 0.1 * absf(sin(u * PI * 2.5)), BACK_Z + 0.3 + u * 6.5))
	mm.instance_count = pts.size()
	var cols: Array[Color] = [Color(1.0, 0.4, 0.4), Color(1.0, 0.85, 0.3), Color(0.4, 0.8, 1.0), Color(0.5, 1.0, 0.5), Color(1.0, 0.5, 0.9)]
	for k in pts.size():
		mm.set_instance_transform(k, Transform3D(Basis(), pts[k]))
		mm.set_instance_color(k, cols[k % cols.size()])
	lights_mm.multimesh = mm
	var sh := Shader.new()
	sh.code = LIGHTS_SHADER
	light_mat = ShaderMaterial.new()
	light_mat.shader = sh
	lights_mm.material_override = light_mat
	lights_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights_mm)


## "normal", "speed" (fast twinkle), "final" (golden), "party" (game over).
func set_mood(mood: String) -> void:
	if light_mat == null:
		return
	match mood:
		"speed":
			light_mat.set_shader_parameter("speed", 9.0)
			light_mat.set_shader_parameter("gold", 0.0)
		"final":
			light_mat.set_shader_parameter("speed", 3.0)
			light_mat.set_shader_parameter("gold", 0.85)
		"party":
			light_mat.set_shader_parameter("speed", 14.0)
			light_mat.set_shader_parameter("gold", 0.0)
		_:
			light_mat.set_shader_parameter("speed", 2.2)
			light_mat.set_shader_parameter("gold", 0.0)


func _build_cat() -> void:
	cat = Node3D.new()
	cat.position = Vector3(1.55, 0.1, -0.35)
	cat.rotation.y = -0.5
	add_child(cat)
	var fur := Color(1.0, 0.62, 0.3)
	var light := Color(1.0, 0.88, 0.7)
	var stripe := Color(0.85, 0.45, 0.2)
	var parts: Array = [
		[MeshKit.sphere(0.16, 14), MeshKit.at(Vector3(0, 0.1, 0), Vector3(1.25, 0.7, 0.9)), fur],
		[MeshKit.sphere(0.11, 12), MeshKit.at(Vector3(0.0, 0.07, 0.07), Vector3(1.2, 0.6, 0.8)), light],
		[MeshKit.sphere(0.1, 14), MeshKit.at(Vector3(0.2, 0.12, 0.05)), fur],
		[MeshKit.sphere(0.045, 10), MeshKit.at(Vector3(0.27, 0.1, 0.1), Vector3(1.0, 0.7, 0.8)), light],
		[MeshKit.sphere(0.012, 6), MeshKit.at(Vector3(0.3, 0.115, 0.13)), Color(1.0, 0.5, 0.55)],
		[MeshKit.box(Vector3(0.035, 0.006, 0.01)), MeshKit.at(Vector3(0.245, 0.15, 0.13), Vector3.ONE, Vector3(0, 0.6, 0.15)), Color(0.15, 0.1, 0.08)],
		[MeshKit.box(Vector3(0.035, 0.006, 0.01)), MeshKit.at(Vector3(0.3, 0.15, 0.06), Vector3.ONE, Vector3(0, 0.6, -0.15)), Color(0.15, 0.1, 0.08)],
		[MeshKit.cyl(0.0, 0.035, 0.06, 6), MeshKit.at(Vector3(0.17, 0.21, 0.0), Vector3.ONE, Vector3(0, 0, 0.25)), fur],
		[MeshKit.cyl(0.0, 0.035, 0.06, 6), MeshKit.at(Vector3(0.23, 0.21, 0.09), Vector3.ONE, Vector3(0.3, 0, -0.1)), fur],
		[MeshKit.sphere(0.04, 8), MeshKit.at(Vector3(0.18, 0.025, 0.12), Vector3(1.3, 0.6, 1.0)), light],
		[MeshKit.sphere(0.04, 8), MeshKit.at(Vector3(0.05, 0.025, 0.14), Vector3(1.3, 0.6, 1.0)), light],
	]
	for k in 3:
		parts.append([MeshKit.box(Vector3(0.025, 0.11, 0.18)), MeshKit.at(Vector3(-0.08 + k * 0.07, 0.16, 0.0), Vector3.ONE, Vector3(0, 0, 0.1)), stripe])
	cat_body = MeshInstance3D.new()
	cat_body.mesh = MeshKit.merge(parts)
	cat_body.material_override = MeshKit.vertex_material(main.mats)
	cat.add_child(cat_body)
	cat_tail = Node3D.new()
	cat_tail.position = Vector3(-0.19, 0.06, 0.0)
	cat.add_child(cat_tail)
	var tparts: Array = []
	for k in 5:
		tparts.append([MeshKit.sphere(0.03 - k * 0.002, 8), MeshKit.at(Vector3(-0.04 - k * 0.045, 0.0, 0.03 * k * k * 0.25)), fur if k < 4 else light])
	var tail := MeshInstance3D.new()
	tail.mesh = MeshKit.merge(tparts)
	tail.material_override = MeshKit.vertex_material(main.mats)
	cat_tail.add_child(tail)


func cat_cheer() -> void:
	cat_hop = 1.4


func _build_dust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.2, 1.1, 2.6)
	p.position = Vector3(0, 1.6, 0.2)
	p.direction = Vector3(0.2, 1, 0)
	p.spread = 180.0
	p.gravity = Vector3(0, 0.005, 0)
	p.initial_velocity_min = 0.01
	p.initial_velocity_max = 0.05
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var qm := QuadMesh.new()
	qm.size = Vector2(0.008, 0.008)
	p.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.95, 0.75, 0.55)
	p.material_override = m
	add_child(p)


func _process(delta: float) -> void:
	t += delta
	if cat == null:
		return
	var breathe := 1.0 + 0.035 * sin(t * 1.6)
	cat_body.scale = Vector3(1.0, breathe, 1.0 + (breathe - 1.0) * 0.5)
	cat_tail.rotation.y = 0.35 * sin(t * 0.9) + (0.8 * sin(t * 9.0) if cat_hop > 0.0 else 0.0)
	if cat_hop > 0.0:
		cat_hop = maxf(0.0, cat_hop - delta)
		cat.position.y = 0.1 + absf(sin(cat_hop * 6.0)) * 0.18 * minf(1.0, cat_hop)
	else:
		cat.position.y = 0.1


# --- Gallery -----------------------------------------------------------------------------

## Hang a finished picture: it flies from the easel (from_xf) into its frame.
func hang(slot: int, mesh: ArrayMesh, word: String, team: bool, from_xf: Transform3D, mat: Material) -> void:
	unhang(slot)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = from_xf
	var dest := Transform3D(Basis().scaled(Vector3(PIC_SCALE, PIC_SCALE, 0.2)), slot_pos(slot))
	var tw := mi.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(mi, "global_transform", dest, 1.3)
	var l := Label3D.new()
	l.text = word.to_upper() + ("\nby the TV team" if team else "")
	l.font_size = 36
	l.outline_size = 10
	l.pixel_size = 0.0013
	l.modulate = Color(1.0, 0.95, 0.8)
	l.position = slot_pos(slot) + Vector3(0, -0.34, 0.01)
	add_child(l)
	pictures[slot] = {"mi": mi, "label": l, "mesh": mesh, "word": word, "team": team}


func unhang(slot: int) -> void:
	if not pictures.has(slot):
		return
	var e: Dictionary = pictures[slot]
	for k in ["mi", "label"]:
		var n = e[k]
		if n != null and is_instance_valid(n):
			n.queue_free()
	pictures.erase(slot)


func clear_gallery() -> void:
	for slot in pictures.keys():
		unhang(slot)
	set_gold([])


## Gold frames (and a MASTERPIECE ribbon) round the winning pictures.
func set_gold(slots: Array) -> void:
	if gold_root != null and is_instance_valid(gold_root):
		gold_root.queue_free()
	gold_root = null
	if slots.is_empty():
		return
	gold_root = Node3D.new()
	add_child(gold_root)
	var gold := Color(1.0, 0.8, 0.25)
	for sv in slots:
		var slot: int = sv
		var fp := slot_pos(slot)
		var parts: Array = [
			[MeshKit.box(Vector3(0.78, 0.06, 0.05)), MeshKit.at(Vector3(0, 0.27, 0.0)), gold],
			[MeshKit.box(Vector3(0.78, 0.06, 0.05)), MeshKit.at(Vector3(0, -0.27, 0.0)), gold],
			[MeshKit.box(Vector3(0.06, 0.6, 0.05)), MeshKit.at(Vector3(-0.36, 0, 0.0)), gold],
			[MeshKit.box(Vector3(0.06, 0.6, 0.05)), MeshKit.at(Vector3(0.36, 0, 0.0)), gold],
		]
		for k in 4:
			parts.append([MeshKit.sphere(0.035, 8), MeshKit.at(Vector3(-0.36 + 0.72 * (k % 2), -0.27 + 0.54 * (k / 2), 0.02)), Color(1.0, 0.95, 0.6)])
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.merge(parts)
		mi.material_override = MeshKit.vertex_material(main.mats, true)
		mi.position = fp
		gold_root.add_child(mi)
		var l := Label3D.new()
		l.text = "MASTERPIECE!"
		l.font_size = 40
		l.outline_size = 12
		l.pixel_size = 0.0014
		l.modulate = Color(1.0, 0.85, 0.3)
		l.position = fp + Vector3(0, 0.38, 0.03)
		gold_root.add_child(l)
		var tw := mi.create_tween().set_loops(4)
		tw.tween_property(mi, "scale", Vector3(1.06, 1.06, 1.0), 0.25)
		tw.tween_property(mi, "scale", Vector3.ONE, 0.25)
