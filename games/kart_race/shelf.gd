extends RefCounted
## BOLT'S TROPHY SHELF: a wooden shelf by the start line of every track, with Bolt the robot standing beside it
## waving. One spot per cup (columns: candy, jungle, ice, space) and speed (top shelf GENTLE, bottom shelf ZOOM);
## a won cup stands there in its medal's colour (gold / silver / bronze), the empty spots wait with a little
## stand in the cup's colour. It grows with every cup won (main.gd rebuilds it when the shelf changes).
##   var node := Shelf.build(main, shelf)   # shelf: cups.gd shelf dictionary ("candy:gentle" -> 1..3)

const Cups := preload("res://games/kart_race/cups.gd")

const WOOD := Color(0.62, 0.42, 0.25)
const ROWS: Array[String] = ["gentle", "zoom"]


static func build(main, shelf: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "BoltShelf"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Cups.CUPS.size()
	var w := n * 1.3 + 0.4
	# The shelf: two uprights, three planks, a back board. Local +Z faces the road.
	for x in [-w * 0.5, w * 0.5]:
		main.add_box(st, Vector3(x, 1.4, 0), Vector3(0.18, 2.8, 0.7), WOOD.darkened(0.15))
	for y in [0.15, 1.3, 2.45]:
		main.add_box(st, Vector3(0, y, 0), Vector3(w, 0.12, 0.7), WOOD)
	main.add_box(st, Vector3(0, 1.4, -0.33), Vector3(w, 2.8, 0.06), WOOD.darkened(0.3))
	for ri in ROWS.size():
		var y := 2.51 if ri == 0 else 1.36
		for c in n:
			var x := -w * 0.5 + 0.85 + c * 1.3
			var cc: Color = Cups.cup(c).color
			var md := int(shelf.get(Cups.shelf_key(c, ROWS[ri]), 0))
			main.add_box(st, Vector3(x, y + 0.04, 0.2), Vector3(0.7, 0.06, 0.4), cc)  # the cup's colour on the plank
			if md <= 0:
				main.add_cyl(st, Vector3(x, y + 0.14, 0.05), 0.14, 0.16, cc.darkened(0.35))
				continue
			var mc: Color = Cups.MEDAL_COLORS[md]
			var big := 1.0 + 0.15 * (md - 1)
			main.add_cyl(st, Vector3(x, y + 0.12, 0.05), 0.22 * big, 0.12, Color(0.25, 0.2, 0.18))
			main.add_cyl(st, Vector3(x, y + 0.32, 0.05), 0.06 * big, 0.3, mc.darkened(0.15))
			main.add_ellipsoid(st, Vector3(x, y + 0.66 * big, 0.05), Vector3(0.26, 0.24, 0.26) * big, mc, 12, 6)
			for side in [-1.0, 1.0]:
				main.add_ellipsoid(st, Vector3(x + side * 0.27 * big, y + 0.7 * big, 0.05), Vector3(0.08, 0.13, 0.05) * big, mc, 6, 4)
			if ri == 1:  # zoom cups wear a little flame
				main.add_ellipsoid(st, Vector3(x, y + 1.0 * big, 0.05), Vector3(0.08, 0.14, 0.08), Color(1.0, 0.45, 0.2), 6, 4)
	var mi := MeshInstance3D.new()
	mi.mesh = main._commit(st)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.35
	m.metallic = 0.25
	mi.material_override = m
	root.add_child(mi)
	root.add_child(_bolt(main, Vector3(w * 0.5 + 1.0, 0, 0.3)))
	return root


## Bolt: a friendly blue robot with a chequered-flag antenna, waving at the drivers.
static func _bolt(main, at: Vector3) -> Node3D:
	var b := Node3D.new()
	b.name = "Bolt"
	b.position = at
	var metal := Color(0.55, 0.7, 0.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-0.25, 0.25]:
		main.add_ellipsoid(st, Vector3(x, 0.22, 0), Vector3(0.18, 0.22, 0.18), Color(0.2, 0.2, 0.24), 8, 4)  # wheels
	main.add_box(st, Vector3(0, 0.95, 0), Vector3(0.8, 0.9, 0.55), metal.darkened(0.15))
	main.add_ellipsoid(st, Vector3(0, 1.0, 0.29), Vector3(0.14, 0.14, 0.04), Color(1.0, 0.65, 0.25), 8, 4)
	main.add_box(st, Vector3(0, 1.75, 0), Vector3(0.9, 0.62, 0.62), metal)
	for x in [-0.2, 0.2]:
		main.add_ellipsoid(st, Vector3(x, 1.8, 0.31), Vector3(0.12, 0.12, 0.04), Color(1, 1, 1), 8, 4)
		main.add_ellipsoid(st, Vector3(x, 1.8, 0.35), Vector3(0.06, 0.06, 0.03), Color(0.1, 0.1, 0.15), 6, 3)
	main.add_box(st, Vector3(0, 1.58, 0.32), Vector3(0.3, 0.05, 0.02), Color(0.15, 0.2, 0.3))
	main.add_cyl(st, Vector3(0, 2.3, 0), 0.025, 0.5, Color(0.4, 0.45, 0.55))
	for i in 4:
		var c := Color(0.1, 0.1, 0.12) if i == 0 or i == 3 else Color(1, 1, 1)
		main.add_box(st, Vector3(0.1 + (i % 2) * 0.16, 2.47 - int(i / 2.0) * 0.14, 0), Vector3(0.16, 0.14, 0.02), c)
	main.add_ellipsoid(st, Vector3(-0.5, 1.0, 0), Vector3(0.1, 0.32, 0.1), metal, 6, 4)  # the resting arm
	var mi := MeshInstance3D.new()
	mi.mesh = main._commit(st)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.4
	m.metallic = 0.3
	mi.material_override = m
	b.add_child(mi)
	# The waving arm (a pivot at the shoulder, rocked by wave() every frame).
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.5, 1.3, 0)
	b.add_child(arm)
	var ast := SurfaceTool.new()
	ast.begin(Mesh.PRIMITIVE_TRIANGLES)
	main.add_ellipsoid(ast, Vector3(0.1, 0.32, 0), Vector3(0.1, 0.34, 0.1), metal, 6, 4)
	main.add_ellipsoid(ast, Vector3(0.14, 0.7, 0), Vector3(0.13, 0.13, 0.13), metal.lightened(0.2), 6, 4)
	var am := MeshInstance3D.new()
	am.mesh = main._commit(ast)
	am.material_override = m
	arm.add_child(am)
	arm.rotation.z = -0.3
	return b


## Every frame: Bolt waves.
static func wave(node: Node3D) -> void:
	var arm := node.get_node_or_null("Bolt/Arm") as Node3D
	if arm != null:
		arm.rotation.z = -0.45 + 0.28 * sin(Time.get_ticks_msec() * 0.007)
