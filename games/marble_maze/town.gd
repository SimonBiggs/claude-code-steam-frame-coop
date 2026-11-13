extends Node3D
## MARBLE TOWN round the table (story.gd): seven little places in an arc behind the maze, grey and
## asleep until the team finishes that place's mazes, then bright with a glowing lamp (saved, so the
## town grows over days). Beside the table, Bobo's big glass JAR holds every shiny marble the family
## has found (each in its own colour). Both are pictures, no words: the VR giant sees the town all
## round; TV views see it past the board. The host owns the numbers and sends them ("town" event /
## snapshot); every machine just draws them. Cheap: one merged mesh per place (lit or asleep), one lamp
## each, the jar's marbles are one MultiMesh.

const Story := preload("res://games/marble_maze/story.gd")
const Worlds := preload("res://games/marble_maze/worlds.gd")
const UiKit := preload("res://core/ui_kit.gd")

const RADIUS := 1.85
const JAR_POS := Vector3(-1.2, 0.0, -0.35)
const JAR_R := 0.12
const JAR_H := 0.3
const STOOL_H := 0.55
const JAR_MAX := 80
const BALL_R := 0.017
## Second pass: BOBO'S MARBLE RUN on the other side of the table: a wooden zig-zag of ramps where every gift marble
## the team has rolled home with (save "rack") rolls round and round (down the ramps, up the lift) - it grows.
const RUN_POS := Vector3(1.02, 0.0, -0.2)
const RUN_TOP := 1.0
const RUN_W := 0.42
const RUN_STEP := 0.16
const RUN_RAMPS := 4
const RACK_MAX := 40
const RUN_SPEED := 0.12

var main
var places: Array = []  # [lit mesh, asleep mesh, lamp, base position]
var lit := 0
var jar_mm: MultiMesh
var jar_list: Array = []
var pop_t: Array[float] = []
var t := 0.0
var cheer_i := -1
var cheer_t := 0.0
var run_mm: MultiMesh
var run_path: Array[Vector3] = []
var run_len := 0.0
var rack_list: Array = []


func _ready() -> void:
	for i in Story.PLACES.size():
		_build_place(i)
	_build_jar()
	_build_run()
	set_lit(0, true)


func place_pos(i: int) -> Vector3:
	var n := Story.PLACES.size()
	var a := deg_to_rad(lerpf(-68.0, 68.0, float(i) / float(n - 1)))
	return Vector3(sin(a) * RADIUS, 0.0, -cos(a) * RADIUS + 0.1)


## How many places are lit (0..7); a newly lit one cheers unless `quiet` (loading a save).
func set_lit(n: int, quiet: bool = false) -> void:
	var was := lit
	lit = clampi(n, 0, places.size())
	for i in places.size():
		var on := i < lit
		(places[i][0] as Node3D).visible = on
		(places[i][1] as Node3D).visible = not on
		(places[i][2] as Node3D).visible = on
	if lit > was and not quiet:
		cheer(lit - 1)


## The newest place bounces and fireworks pop over it.
func cheer(i: int) -> void:
	cheer_i = i
	cheer_t = 0.0
	if main != null and i >= 0 and i < places.size():
		var top: Vector3 = places[i][3] + Vector3(0, 0.45, 0)
		for c in [Color(1.0, 0.9, 0.3), Story.PLACES[i].color, Color(1, 1, 1)]:
			main.burst(top, c, 22, false)


## The jar's marbles: an Array of shiny indices (story.gd SHINIES; -1 = golden).
func set_jar(list: Array, quiet: bool = false) -> void:
	var grew := list.size() > jar_list.size() and not quiet
	jar_list = list.duplicate()
	var n := mini(jar_list.size(), JAR_MAX)
	for i in n:
		var col: Color = Story.shiny_of(int(jar_list[i]))[1]
		jar_mm.set_instance_color(i, col)
		jar_mm.set_instance_transform(i, Transform3D(Basis(), _jar_spot(i)))
	jar_mm.visible_instance_count = n
	if grew and n > 0 and main != null:
		main.burst(JAR_POS + Vector3(0, STOOL_H + JAR_H, 0), Story.shiny_of(int(jar_list[n - 1]))[1], 16, false)


## The marble run's marbles: an Array of worlds.gd MARBLES indices (the newest last).
func set_rack(list: Array, quiet: bool = false) -> void:
	var grew := list.size() > rack_list.size() and not quiet
	rack_list = list.duplicate()
	var n := mini(rack_list.size(), RACK_MAX)
	for i in n:
		var k := int(rack_list[rack_list.size() - n + i])
		var col: Color = Worlds.MARBLES[clampi(k, 0, Worlds.MARBLES.size() - 1)].color
		run_mm.set_instance_color(i, col)
	run_mm.visible_instance_count = n
	if grew and n > 0 and main != null:
		main.burst(RUN_POS + Vector3(0, RUN_TOP + 0.05, 0), run_mm.get_instance_color(n - 1), 16, false)
		main.sound("ring", -6.0, 1.3)


func _run_point(d: float) -> Vector3:
	d = fposmod(d, run_len)
	for i in range(1, run_path.size()):
		var seg := run_path[i - 1].distance_to(run_path[i])
		if d <= seg:
			return run_path[i - 1].lerp(run_path[i], d / maxf(seg, 0.0001))
		d -= seg
	return run_path[0]


func jar_top() -> Vector3:
	return JAR_POS + Vector3(0, STOOL_H + JAR_H + 0.03, 0)


func _jar_spot(i: int) -> Vector3:
	# Loose layers of marbles, settling from the bottom.
	var per := 9
	var layer := i / per
	var k := i % per
	var a := k * TAU / 8.0 + layer * 0.7
	var r := 0.0 if k == 8 else JAR_R * 0.62
	return JAR_POS + Vector3(cos(a) * r, STOOL_H + 0.012 + BALL_R + layer * BALL_R * 1.7, sin(a) * r)


func _process(delta: float) -> void:
	t += delta
	var n := run_mm.visible_instance_count if run_mm != null else 0
	for i in n:
		var p := _run_point(t * RUN_SPEED + run_len * float(i) / float(n))
		run_mm.set_instance_transform(i, Transform3D(Basis(), p))
	for i in places.size():
		var lamp: MeshInstance3D = places[i][2]
		if lamp.visible:
			lamp.scale = Vector3.ONE * (1.0 + sin(t * 3.0 + i) * 0.15)
	if cheer_i >= 0 and cheer_i < places.size():
		cheer_t += delta
		var s := 1.0 + sin(cheer_t * 12.0) * 0.12 * maxf(0.0, 1.0 - cheer_t / 1.5)
		(places[cheer_i][0] as Node3D).scale = Vector3(1.0, s, 1.0)
		if cheer_t > 1.5:
			(places[cheer_i][0] as Node3D).scale = Vector3.ONE
			cheer_i = -1


func _build_place(i: int) -> void:
	var base := place_pos(i)
	var root := Node3D.new()
	root.position = base
	root.rotation.y = atan2(-base.x, -base.z) + PI  # face the table
	add_child(root)
	var parts := _parts(i)
	var lit_mesh := MeshInstance3D.new()
	lit_mesh.mesh = main.merged_mesh("town_%d" % i, parts)
	lit_mesh.material_override = main.vertex_mat()
	root.add_child(lit_mesh)
	var grey: Array = []
	for p in parts:
		var c: Color = p[2]
		var v := c.get_luminance()
		grey.append([p[0], p[1], Color(v, v, v).lerp(Color(0.55, 0.57, 0.62), 0.5)])
	var sleep := MeshInstance3D.new()
	sleep.mesh = main.merged_mesh("town_%d_asleep" % i, grey)
	sleep.material_override = main.vertex_mat()
	root.add_child(sleep)
	var lamp := MeshInstance3D.new()
	lamp.mesh = main.sphere_mesh(0.035)
	lamp.material_override = main.make_material(Color(1.0, 0.9, 0.5), 2.0)
	lamp.position = _lamp_spot(i)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lamp)
	places.append([lit_mesh, sleep, lamp, base])


func _lamp_spot(i: int) -> Vector3:
	return [Vector3(0, 0.42, 0), Vector3(0, 0.56, 0), Vector3(0.12, 0.36, 0), Vector3(0, 0.3, 0),
		Vector3(0, 0.62, 0), Vector3(0, 0.5, 0), Vector3(0, 0.42, 0)][i]


## Each place in a handful of shapes: [mesh, transform, colour].
func _parts(i: int) -> Array:
	var p: Array = []
	var m = main
	# A round grassy base for every place.
	p.append([m.cyl_mesh(0.3, 0.32, 0.03, 20), Transform3D(Basis(), Vector3(0, 0.015, 0)), Color(0.5, 0.78, 0.4)])
	match i:
		0:  # FLOWER PARK: a tree and flowers
			p.append([m.cyl_mesh(0.025, 0.035, 0.25, 8), Transform3D(Basis(), Vector3(0, 0.15, 0)), Color(0.55, 0.36, 0.2)])
			p.append([m.sphere_mesh(0.13), Transform3D(Basis(), Vector3(0, 0.33, 0)), Color(0.35, 0.75, 0.3)])
			for k in 5:
				var a := k * TAU / 5.0
				var at := Vector3(cos(a) * 0.2, 0.0, sin(a) * 0.2)
				p.append([m.cyl_mesh(0.006, 0.006, 0.09, 6), Transform3D(Basis(), at + Vector3(0, 0.07, 0)), Color(0.3, 0.6, 0.25)])
				p.append([m.sphere_mesh(0.03), Transform3D(Basis(), at + Vector3(0, 0.12, 0)), [Color(1, 0.4, 0.5), Color(1, 0.85, 0.2), Color(0.7, 0.5, 1.0)][k % 3]])
		1:  # SEASIDE: water and a striped lighthouse
			p.append([m.cyl_mesh(0.28, 0.28, 0.035, 20), Transform3D(Basis(), Vector3(0.05, 0.02, 0.05)), Color(0.35, 0.7, 1.0)])
			for k in 4:
				var r0 := 0.07 - k * 0.008
				p.append([m.cyl_mesh(r0 - 0.008, r0, 0.11, 12), Transform3D(Basis(), Vector3(0, 0.09 + k * 0.11, 0)), Color(1, 0.3, 0.3) if k % 2 == 0 else Color(1, 1, 1)])
			p.append([m.cyl_mesh(0.0, 0.06, 0.08, 12), Transform3D(Basis(), Vector3(0, 0.6, 0)), Color(1, 0.3, 0.3)])
		2:  # CANDY SHOP: a pink house and a giant lollipop
			p.append([m.box_mesh(Vector3(0.26, 0.2, 0.2)), Transform3D(Basis(), Vector3(-0.04, 0.13, 0)), Color(1.0, 0.7, 0.85)])
			var roof := PrismMesh.new()
			roof.size = Vector3(0.3, 0.12, 0.22)
			p.append([roof, Transform3D(Basis(), Vector3(-0.04, 0.29, 0)), Color(0.95, 0.35, 0.55)])
			p.append([m.box_mesh(Vector3(0.06, 0.09, 0.01)), Transform3D(Basis(), Vector3(-0.04, 0.075, 0.1)), Color(0.6, 0.35, 0.25)])
			p.append([m.cyl_mesh(0.008, 0.008, 0.3, 6), Transform3D(Basis(), Vector3(0.18, 0.18, 0.05)), Color(1, 1, 1)])
			p.append([m.cyl_mesh(0.08, 0.08, 0.02, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.18, 0.36, 0.05)), Color(1.0, 0.45, 0.75)])
		3:  # ICE CAVE: a snowy dome and icicles
			p.append([m.sphere_mesh(0.22), Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), Vector3(0, 0.03, 0)), Color(0.88, 0.95, 1.0)])
			p.append([m.sphere_mesh(0.08), Transform3D(Basis.from_scale(Vector3(1.0, 1.2, 0.5)), Vector3(0, 0.06, 0.18)), Color(0.35, 0.5, 0.75)])
			for k in 4:
				var a := -0.9 + k * 0.6
				p.append([m.cyl_mesh(0.0, 0.025, 0.12, 6), Transform3D(Basis(Vector3.RIGHT, PI), Vector3(sin(a) * 0.24, 0.15, cos(a) * 0.12 - 0.05)), Color(0.7, 0.88, 1.0)])
		4:  # CASTLE: a keep, two towers, a flag
			p.append([m.box_mesh(Vector3(0.3, 0.22, 0.18)), Transform3D(Basis(), Vector3(0, 0.14, 0)), Color(0.78, 0.78, 0.82)])
			for sx in [-0.17, 0.17]:
				p.append([m.cyl_mesh(0.06, 0.06, 0.34, 12), Transform3D(Basis(), Vector3(sx, 0.2, 0)), Color(0.72, 0.72, 0.78)])
				p.append([m.cyl_mesh(0.0, 0.075, 0.12, 12), Transform3D(Basis(), Vector3(sx, 0.43, 0)), Color(0.4, 0.5, 1.0)])
			p.append([m.box_mesh(Vector3(0.08, 0.12, 0.012)), Transform3D(Basis(), Vector3(0, 0.08, 0.092)), Color(0.5, 0.35, 0.2)])
			p.append([m.cyl_mesh(0.004, 0.004, 0.2, 6), Transform3D(Basis(), Vector3(0, 0.35, 0)), Color(0.3, 0.3, 0.3)])
			p.append([m.box_mesh(Vector3(0.09, 0.05, 0.005)), Transform3D(Basis(), Vector3(0.045, 0.42, 0)), Color(1.0, 0.35, 0.35)])
		5:  # STAR PARK: a little rocket and a star
			p.append([m.cyl_mesh(0.05, 0.05, 0.3, 12), Transform3D(Basis(), Vector3(-0.07, 0.18, 0)), Color(0.95, 0.95, 1.0)])
			p.append([m.cyl_mesh(0.0, 0.05, 0.1, 12), Transform3D(Basis(), Vector3(-0.07, 0.38, 0)), Color(1.0, 0.35, 0.35)])
			for k in 3:
				var a := k * TAU / 3.0
				p.append([m.box_mesh(Vector3(0.012, 0.08, 0.06)), Transform3D(Basis(Vector3.UP, a), Vector3(-0.07, 0.07, 0) + Vector3(cos(a), 0, sin(a)) * 0.05), Color(1.0, 0.35, 0.35)])
			p.append([m.star_mesh(), Transform3D(Basis.from_scale(Vector3.ONE * 0.12), Vector3(0.14, 0.3, 0)), Color(1.0, 0.85, 0.3)])
			p.append([m.cyl_mesh(0.006, 0.006, 0.26, 6), Transform3D(Basis(), Vector3(0.14, 0.15, 0)), Color(0.5, 0.5, 0.6)])
		6:  # RAINBOW HILL: a green hill under a rainbow
			p.append([m.sphere_mesh(0.22), Transform3D(Basis.from_scale(Vector3(1.2, 0.5, 1.0)), Vector3(0, 0.02, 0)), Color(0.45, 0.8, 0.4)])
			var bands: Array[Color] = [Color(1, 0.3, 0.3), Color(1, 0.6, 0.2), Color(1, 0.9, 0.3), Color(0.4, 0.85, 0.4), Color(0.35, 0.6, 1.0), Color(0.6, 0.4, 1.0)]
			for k in bands.size():
				var tm := TorusMesh.new()
				tm.inner_radius = 0.26 - k * 0.022
				tm.outer_radius = 0.28 - k * 0.022
				tm.rings = 24
				tm.ring_segments = 6
				p.append([tm, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.0, -0.05)), bands[k]])
	return p


## Bobo's marble run: a post, RUN_RAMPS ramps zig-zagging down and a lift back up (one merged mesh), the marbles one
## MultiMesh rolling along run_path.
func _build_run() -> void:
	var parts: Array = []
	var wood := Color(0.75, 0.55, 0.35)
	parts.append([main.box_mesh(Vector3(0.05, RUN_TOP + 0.08, 0.05)), Transform3D(Basis(), RUN_POS + Vector3(0, (RUN_TOP + 0.08) * 0.5, -0.06)), wood])
	parts.append([main.box_mesh(Vector3(RUN_W + 0.12, 0.03, 0.2)), Transform3D(Basis(), RUN_POS + Vector3(0, 0.015, 0)), wood])
	run_path.clear()
	var half := RUN_W * 0.5
	var lift_x := -half - 0.04
	run_path.append(RUN_POS + Vector3(lift_x, RUN_TOP + 0.05, 0))
	for k in RUN_RAMPS:
		var y0 := RUN_TOP - k * RUN_STEP
		var y1 := y0 - RUN_STEP * 0.6
		var xa := -half if k % 2 == 0 else half
		var xb := -xa
		run_path.append(RUN_POS + Vector3(xa, y0 + BALL_R, 0))
		run_path.append(RUN_POS + Vector3(xb, y1 + BALL_R, 0))
		var mid := Vector3((xa + xb) * 0.5, (y0 + y1) * 0.5, 0)
		var ang := atan2(y0 - y1, xb - xa)
		parts.append([main.box_mesh(Vector3(RUN_W + 0.03, 0.012, 0.05)), Transform3D(Basis(Vector3(0, 0, 1), ang), RUN_POS + mid - Vector3(0, 0.008, 0)),
			Color(1.0, 0.7, 0.3) if k % 2 == 0 else Color(0.5, 0.8, 1.0)])
		parts.append([main.box_mesh(Vector3(RUN_W + 0.03, 0.03, 0.006)), Transform3D(Basis(Vector3(0, 0, 1), ang), RUN_POS + mid + Vector3(0, 0.008, 0.026)), wood])
	var bottom: Vector3 = run_path[run_path.size() - 1]
	run_path.append(Vector3(RUN_POS.x + lift_x, bottom.y, RUN_POS.z))
	run_path.append(run_path[0])
	parts.append([main.box_mesh(Vector3(0.02, RUN_TOP, 0.02)), Transform3D(Basis(), RUN_POS + Vector3(lift_x, RUN_TOP * 0.5 + bottom.y * 0.5, -0.03)), Story.BOBO_COLOR])
	run_len = 0.0
	for i in range(1, run_path.size()):
		run_len += run_path[i - 1].distance_to(run_path[i])
	var stand := MeshInstance3D.new()
	stand.mesh = main.merged_mesh("town_run", parts)
	stand.material_override = main.vertex_mat()
	add_child(stand)
	run_mm = MultiMesh.new()
	run_mm.transform_format = MultiMesh.TRANSFORM_3D
	run_mm.use_colors = true
	run_mm.mesh = main.sphere_mesh(BALL_R)
	run_mm.instance_count = RACK_MAX
	run_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = run_mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.15
	mat.metallic = 0.3
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## The jar on its stool: the glass, a lid, and the marbles (one MultiMesh, coloured per marble).
func _build_jar() -> void:
	var parts: Array = []
	parts.append([main.cyl_mesh(0.14, 0.17, STOOL_H, 14), Transform3D(Basis(), JAR_POS + Vector3(0, STOOL_H * 0.5, 0)), Color(0.7, 0.5, 0.32)])
	parts.append([main.cyl_mesh(JAR_R * 0.9, JAR_R * 0.9, 0.03, 16), Transform3D(Basis(), JAR_POS + Vector3(0, STOOL_H + JAR_H + 0.015, 0)), Story.BOBO_COLOR])
	var stool := MeshInstance3D.new()
	stool.mesh = main.merged_mesh("town_jar", parts)
	stool.material_override = main.vertex_mat()
	add_child(stool)
	var glass := MeshInstance3D.new()
	glass.mesh = main.cyl_mesh(JAR_R, JAR_R, JAR_H, 18)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.8, 0.95, 1.0, 0.22)
	UiKit.see_through(gm)
	gm.roughness = 0.1
	gm.metallic = 0.3
	glass.material_override = gm
	glass.position = JAR_POS + Vector3(0, STOOL_H + JAR_H * 0.5, 0)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	jar_mm = MultiMesh.new()
	jar_mm.transform_format = MultiMesh.TRANSFORM_3D
	jar_mm.use_colors = true
	jar_mm.mesh = main.sphere_mesh(BALL_R)
	jar_mm.instance_count = JAR_MAX
	jar_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = jar_mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.15
	mat.metallic = 0.2
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.25, 0.25)
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
