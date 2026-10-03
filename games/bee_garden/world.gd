extends RefCounted
## BEE GARDEN world: a sunny back garden with a big raised garden bed at waist height.
## World units: the VR gardener sees everything at XR world_scale S (4 units = 1 real metre), so the
## bed (8 x 3.6 units) is a 2 m x 0.9 m bed, and a bee (about 0.3 units) is a fat 7 cm bumblebee.
## The soil top is y = 0; the lawn is 0.8 m lower. Everything is deterministic (same on both machines).

const S := 4.0                     # XR world scale
const BED_X := 4.0                 # soil half-width
const BED_Z := 1.8                 # soil half-depth
const LEDGE_Z := 2.75              # the front ledge (tools) runs from BED_Z to here
const LAWN_Y := -3.2               # 0.8 m below the soil
const SPOT_X: Array[float] = [-2.7, -0.9, 0.9, 2.7]
const SPOT_Z: Array[float] = [-1.1, 0.0, 1.1]
const SPOTS := 12
const HIVE_POS := Vector3(-5.5, 0.0, -0.5)
const HIVE_ENTRY := Vector3(-5.0, 0.32, -0.5)
const TRAY_POS := Vector3(2.7, 0.0, 2.3)
const TRAY_DX := 0.42              # spacing between the three seed compartments
const CAN_HOME := Vector3(-2.7, 0.0, 2.3)
const BASKET_POS := Vector3(0.0, 0.0, 2.3)
const SIGN_POS := Vector3(0.0, 3.1, -6.2)
const JAR_Z := -2.15
const MAX_JARS := 8
const TV_LAYER := 512               # labels only the TV players see (billboards)

## Flower kinds: daisy (quick), sunflower (tall, more honey), sun lily (needs LOTS of water first).
const KINDS: Array[Dictionary] = [
	{"name": "Daisy", "petal": Color(1.0, 0.55, 0.75), "center": Color(1.0, 0.85, 0.25), "grow": 6.0, "h": 0.75, "honey": 1, "fruit": 3, "fruit_color": Color(0.95, 0.2, 0.25), "thirst": 0.2},
	{"name": "Sunflower", "petal": Color(1.0, 0.82, 0.1), "center": Color(0.45, 0.25, 0.1), "grow": 9.0, "h": 1.15, "honey": 2, "fruit": 4, "fruit_color": Color(1.0, 0.55, 0.1), "thirst": 0.2},
	{"name": "Sun lily", "petal": Color(1.0, 0.95, 0.55), "center": Color(1.0, 0.6, 0.1), "grow": 7.0, "h": 0.9, "honey": 3, "fruit": 6, "fruit_color": Color(1.0, 0.85, 0.2), "thirst": 0.85},
]
const SEASONS: Array[String] = ["SPRING", "SUMMER", "AUTUMN", "HARVEST MOON"]
const SEASON_LAWN: Array[Color] = [Color(0.45, 0.78, 0.32), Color(0.55, 0.78, 0.25), Color(0.72, 0.66, 0.28), Color(0.6, 0.6, 0.3)]
const SEASON_LEAF: Array[Color] = [Color(0.4, 0.75, 0.3), Color(0.3, 0.62, 0.22), Color(0.95, 0.55, 0.2), Color(0.85, 0.35, 0.2)]


static func spot_pos(i: int) -> Vector3:
	return Vector3(SPOT_X[i % 4], 0.0, SPOT_Z[clampi(i / 4, 0, 2)])


static func jar_pos(i: int, n: int) -> Vector3:
	var gap := 0.78
	return Vector3((i - (n - 1) * 0.5) * gap, 0.15, JAR_Z)


static func tray_slot(k: int) -> Vector3:
	return TRAY_POS + Vector3((k - 1) * TRAY_DX, 0.12, 0.0)


static func over_bed(x: float, z: float) -> bool:
	return absf(x) < BED_X + 0.35 and z > -BED_Z - 0.35 and z < LEDGE_Z


static func in_soil(x: float, z: float) -> bool:
	return absf(x) < BED_X and absf(z) < BED_Z


## Lowest height a bee may fly at.
static func floor_y(x: float, z: float) -> float:
	if over_bed(x, z):
		return 0.18
	if absf(x - HIVE_POS.x) < 0.45 and absf(z - HIVE_POS.z) < 0.45:
		return 1.2
	return LAWN_Y + 0.3


static func mat(color: Color, glow: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## Shared material cache (Engine meta, survives hot reloads) so identical colours batch.
static func cmat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	if not Engine.has_meta("bg_mats"):
		Engine.set_meta("bg_mats", {})
	var cache: Dictionary = Engine.get_meta("bg_mats")
	var key := "%s/%.2f" % [color.to_html(), glow]
	if not cache.has(key):
		cache[key] = mat(color, glow)
	return cache[key]


static func sphere(radius: float, segs: int = 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


static func cyl(top: float, bottom: float, h: float, segs: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func mesh_node(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A batch of meshes merged into one draw call (one material).
class Batch:
	var st := SurfaceTool.new()
	var count := 0
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	func add(mesh: Mesh, xf: Transform3D) -> void:
		st.append_from(mesh, 0, xf)
		count += 1
	func build(parent: Node3D, material: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		if count > 0:
			mi.mesh = st.commit()
		mi.material_override = material
		parent.add_child(mi)
		return mi


## A watering can: spout points along -Z, the handle is at the origin's top.
static func make_can() -> Node3D:
	var n := Node3D.new()
	var green := cmat(Color(0.3, 0.7, 0.55))
	mesh_node(n, cyl(0.2, 0.22, 0.38, 14), green, Vector3(0, -0.28, 0.05))
	var spout := mesh_node(n, cyl(0.035, 0.05, 0.5, 8), green, Vector3(0, -0.22, -0.3))
	spout.rotation.x = -1.0
	var rose := mesh_node(n, cyl(0.08, 0.04, 0.08, 10), cmat(Color(0.85, 0.85, 0.75)), Vector3(0, -0.06, -0.5))
	rose.rotation.x = -1.0
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.14
	tm.rings = 12
	tm.ring_segments = 6
	handle.mesh = tm
	handle.material_override = green
	handle.rotation.z = PI / 2.0
	handle.position = Vector3(0, -0.06, 0.08)
	n.add_child(handle)
	return n


## Where the water comes out, in can space.
const SPOUT_TIP := Vector3(0.0, -0.04, -0.54)


static func build(main: Node3D, vr: bool) -> void:
	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.8, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.8)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = not vr
	e.glow_intensity = 0.4
	e.glow_bloom = 0.03
	e.ssao_enabled = false
	e.fog_enabled = false
	env.environment = e
	main.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.95, 0.82)
	sun.light_energy = 1.15
	sun.shadow_enabled = not vr
	sun.directional_shadow_max_distance = 40.0
	main.add_child(sun)

	var sun_ball := MeshInstance3D.new()
	sun_ball.name = "SunBall"
	sun_ball.mesh = sphere(4.0, 16)
	var sm := mat(Color(1.0, 0.92, 0.5), 3.0)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_ball.material_override = sm
	sun_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(sun_ball)

	# Lawn
	var lawn := MeshInstance3D.new()
	lawn.name = "Lawn"
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	lawn.mesh = pm
	lawn.material_override = mat(SEASON_LAWN[0])
	lawn.position.y = LAWN_Y
	main.add_child(lawn)

	# The raised bed: wooden box, soil, rims, and the wide front ledge for the tools.
	var wood := mat(Color(0.62, 0.42, 0.25))
	var wood_dark := mat(Color(0.5, 0.33, 0.2))
	var wb := Batch.new()
	var h := -LAWN_Y
	wb.add(box(Vector3(BED_X * 2.0 + 0.6, h, BED_Z * 2.0 + 0.6)), Transform3D(Basis(), Vector3(0, LAWN_Y + h * 0.5 - 0.06, 0)))
	wb.add(box(Vector3(BED_X * 2.0 + 0.6, h, LEDGE_Z - BED_Z)), Transform3D(Basis(), Vector3(0, LAWN_Y + h * 0.5, (LEDGE_Z + BED_Z) * 0.5 + 0.15)))
	wb.build(main, wood_dark)
	var rim := Batch.new()
	rim.add(box(Vector3(BED_X * 2.0 + 0.6, 0.22, 0.3)), Transform3D(Basis(), Vector3(0, 0.05, -BED_Z - 0.15)))
	rim.add(box(Vector3(0.3, 0.22, BED_Z * 2.0 + 0.6)), Transform3D(Basis(), Vector3(-BED_X - 0.15, 0.05, 0)))
	rim.add(box(Vector3(0.3, 0.22, BED_Z * 2.0 + 0.6)), Transform3D(Basis(), Vector3(BED_X + 0.15, 0.05, 0)))
	rim.add(box(Vector3(BED_X * 2.0 + 0.6, 0.1, LEDGE_Z - BED_Z + 0.3)), Transform3D(Basis(), Vector3(0, -0.05, (LEDGE_Z + BED_Z) * 0.5 + 0.15)))
	for i in 5:  # plank lines on the front of the box
		rim.add(box(Vector3(BED_X * 2.0 + 0.62, 0.05, 0.05)), Transform3D(Basis(), Vector3(0, LAWN_Y + 0.6 * (i + 1), LEDGE_Z + 0.31)))
	rim.build(main, wood)
	var soil := MeshInstance3D.new()
	soil.mesh = box(Vector3(BED_X * 2.0, 0.1, BED_Z * 2.0))
	soil.material_override = mat(Color(0.36, 0.24, 0.16))
	soil.position.y = -0.05
	main.add_child(soil)
	# little soil rows
	var rows := Batch.new()
	for z in SPOT_Z:
		rows.add(box(Vector3(BED_X * 2.0 - 0.3, 0.06, 0.5)), Transform3D(Basis(), Vector3(0, 0.0, z)))
	rows.build(main, mat(Color(0.42, 0.29, 0.19)))

	_build_hive(main)
	_build_tools(main)
	_build_garden(main)


static func _build_hive(main: Node3D) -> void:
	var hive := Node3D.new()
	hive.name = "Hive"
	main.add_child(hive)
	hive.position = HIVE_POS
	mesh_node(hive, cyl(0.12, 0.14, -LAWN_Y, 8), cmat(Color(0.5, 0.35, 0.22)), Vector3(0, LAWN_Y * 0.5, 0))
	mesh_node(hive, box(Vector3(1.0, 0.1, 1.0)), cmat(Color(0.55, 0.38, 0.24)), Vector3(0, 0.0, 0))
	var yellow := cmat(Color(1.0, 0.85, 0.35))
	var cream := cmat(Color(0.98, 0.95, 0.85))
	mesh_node(hive, box(Vector3(0.85, 0.42, 0.85)), yellow, Vector3(0, 0.27, 0))
	mesh_node(hive, box(Vector3(0.85, 0.36, 0.85)), cream, Vector3(0, 0.66, 0))
	var roof := mesh_node(hive, PrismMesh.new(), cmat(Color(0.85, 0.4, 0.3)), Vector3(0, 1.0, 0), Vector3(1.1, 0.35, 1.05))
	roof.rotation.y = PI / 2.0
	mesh_node(hive, box(Vector3(0.06, 0.1, 0.36)), cmat(Color(0.15, 0.1, 0.05)), Vector3(0.43, 0.14, 0))
	mesh_node(hive, box(Vector3(0.25, 0.04, 0.42)), cmat(Color(0.55, 0.38, 0.24)), Vector3(0.52, 0.07, 0))
	var tag := Label3D.new()
	tag.name = "HiveTag"
	tag.text = "HIVE"
	tag.font_size = 48
	tag.outline_size = 14
	tag.pixel_size = 0.006
	tag.modulate = Color(1.0, 0.85, 0.3)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.layers = TV_LAYER
	tag.position = Vector3(0, 1.6, 0)
	hive.add_child(tag)


static func _build_tools(main: Node3D) -> void:
	# Seed tray: three compartments, each with a tiny flower showing what grows from it.
	var tray := Node3D.new()
	tray.name = "Tray"
	main.add_child(tray)
	tray.position = TRAY_POS
	mesh_node(tray, box(Vector3(TRAY_DX * 3.0 + 0.1, 0.06, 0.5)), cmat(Color(0.75, 0.55, 0.35)), Vector3(0, 0.03, 0))
	for k in 3:
		var c := Vector3((k - 1) * TRAY_DX, 0.0, 0.0)
		var kd: Dictionary = KINDS[k]
		mesh_node(tray, box(Vector3(TRAY_DX - 0.06, 0.1, 0.42)), cmat(Color(0.82, 0.62, 0.4)), c + Vector3(0, 0.08, 0))
		mesh_node(tray, sphere(0.13, 10), cmat(Color(0.4, 0.27, 0.17)), c + Vector3(0, 0.12, 0), Vector3(1.0, 0.35, 1.2))
		for j in 4:
			mesh_node(tray, sphere(0.035, 6), cmat(Color(0.25, 0.18, 0.1)), c + Vector3(-0.06 + j * 0.04, 0.17, -0.05 + (j % 2) * 0.08))
		mesh_node(tray, cyl(0.012, 0.012, 0.3, 4), cmat(Color(0.35, 0.65, 0.3)), c + Vector3(0, 0.3, -0.14))
		var bloom := mesh_node(tray, cyl(0.1, 0.1, 0.02, 10), cmat(kd.petal, 0.2), c + Vector3(0, 0.46, -0.14))
		bloom.rotation.x = 0.9
		mesh_node(tray, sphere(0.04, 8), cmat(kd.center), c + Vector3(0, 0.47, -0.12))
	# Watering can home spot (the can itself is drawn by the gardener script) + a puddle mat.
	var mat_node := mesh_node(main, cyl(0.38, 0.38, 0.02, 16), cmat(Color(0.4, 0.6, 0.75)), CAN_HOME + Vector3(0, 0.01, 0))
	mat_node.name = "CanMat"
	# Fruit basket
	var basket := Node3D.new()
	basket.name = "Basket"
	main.add_child(basket)
	basket.position = BASKET_POS
	mesh_node(basket, cyl(0.42, 0.3, 0.3, 14), cmat(Color(0.75, 0.55, 0.3)), Vector3(0, 0.15, 0))
	mesh_node(basket, cyl(0.37, 0.37, 0.02, 14), cmat(Color(0.45, 0.3, 0.15)), Vector3(0, 0.27, 0))


static func _build_garden(main: Node3D) -> void:
	# Trees, bushes and a picket fence around the lawn (a few batched meshes).
	var trunks := Batch.new()
	var leaves := Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tree_spots: Array[Vector3] = [Vector3(-14, 0, -12), Vector3(12, 0, -14), Vector3(-20, 0, 2), Vector3(19, 0, -2),
		Vector3(-9, 0, -20), Vector3(5, 0, -22), Vector3(22, 0, 12), Vector3(-22, 0, 14)]
	for p in tree_spots:
		var th := rng.randf_range(5.0, 8.0)
		trunks.add(cyl(0.35, 0.5, th, 8), Transform3D(Basis(), Vector3(p.x, LAWN_Y + th * 0.5, p.z)))
		for j in 3:
			var r := rng.randf_range(2.0, 3.0)
			leaves.add(sphere(r, 12), Transform3D(Basis(), Vector3(p.x + rng.randf_range(-1.2, 1.2), LAWN_Y + th + rng.randf_range(-0.5, 1.2), p.z + rng.randf_range(-1.2, 1.2))))
	for i in 10:
		var a := rng.randf_range(0, TAU)
		var d := rng.randf_range(9.0, 16.0)
		leaves.add(sphere(rng.randf_range(0.8, 1.4), 10), Transform3D(Basis(), Vector3(cos(a) * d, LAWN_Y + 0.5, sin(a) * d - 3.0)))
	trunks.build(main, mat(Color(0.5, 0.33, 0.2)))
	var lm := leaves.build(main, mat(SEASON_LEAF[0]))
	lm.name = "Leaves"
	var fence := Batch.new()
	for i in 41:
		var x := -26.0 + i * 1.3
		fence.add(box(Vector3(0.25, 2.2, 0.12)), Transform3D(Basis(), Vector3(x, LAWN_Y + 1.1, -26.0)))
	fence.add(box(Vector3(53.0, 0.18, 0.08)), Transform3D(Basis(), Vector3(0, LAWN_Y + 1.5, -26.08)))
	fence.add(box(Vector3(53.0, 0.18, 0.08)), Transform3D(Basis(), Vector3(0, LAWN_Y + 0.6, -26.08)))
	fence.build(main, mat(Color(0.97, 0.96, 0.92)))
	# Wild flowers dotted on the lawn (one batch per colour).
	var cols: Array[Color] = [Color(1.0, 0.5, 0.6), Color(1.0, 0.95, 0.5), Color(0.75, 0.6, 1.0)]
	for c in cols:
		var fb := Batch.new()
		for i in 22:
			var a := rng.randf_range(0, TAU)
			var d := rng.randf_range(7.0, 18.0)
			fb.add(sphere(0.18, 6), Transform3D(Basis(), Vector3(cos(a) * d, LAWN_Y + 0.25, sin(a) * d)))
		fb.build(main, mat(c, 0.15))
	# The garden sign (the gardener reads it: day, honey, time). Text is set by main.gd.
	var post := Batch.new()
	post.add(box(Vector3(0.18, 6.4, 0.18)), Transform3D(Basis(), Vector3(-2.6, LAWN_Y + 3.2, SIGN_POS.z - 0.1)))
	post.add(box(Vector3(0.18, 6.4, 0.18)), Transform3D(Basis(), Vector3(2.6, LAWN_Y + 3.2, SIGN_POS.z - 0.1)))
	post.add(box(Vector3(6.0, 1.9, 0.1)), Transform3D(Basis(), Vector3(0, SIGN_POS.y, SIGN_POS.z - 0.12)))
	post.build(main, mat(Color(0.55, 0.37, 0.22)))
	var sign_l := Label3D.new()
	sign_l.name = "Sign"
	sign_l.font_size = 64
	sign_l.outline_size = 12
	sign_l.pixel_size = 0.0075
	sign_l.modulate = Color(1.0, 0.97, 0.85)
	sign_l.outline_modulate = Color(0.25, 0.15, 0.05)
	sign_l.width = 760.0
	sign_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sign_l.position = SIGN_POS + Vector3(0, 0, -0.05)
	sign_l.text = "BEE GARDEN"
	main.add_child(sign_l)
