extends Node3D
## GRAN'S CAFE DRESSING (second pass, nights.gd), built the same on every machine:
##  - the café grows: Nights.CAFE_STEPS decorations by parties served (fairy lights, fish tank, piano, lanterns, cake
##    stand, a fountain outside the window, a gold star over the back door, a chandelier);
##  - tonight's theme: a picture board by the back door (a pizza, a pancake stack, a picnic basket) and bunting in
##    the theme's colours over the pass;
##  - the chef gifts: the BIG POT of soup on the window ledge (steaming) and the HELPER MOUSE on the counter's end
##    (it hops to the pass with a missing ingredient).
##   decor.show_cafe(level, pop)   decor.show_theme(theme)   decor.show_perks(list)   decor.mouse_hop(to)

const Nights := preload("res://games/kitchen_rush/nights.gd")

const MOUSE_HOME := Vector3(-1.17, 0.95, 0.24)
const POT_AT := Vector3(6.32, 1.01, 3.05)

var main: Node
var cafe_root: Node3D
var theme_root: Node3D
var perk_root: Node3D
var level := -1
var theme := ""
var perks: Array = []
var mouse: Node3D
var pot: Node3D
var _t := 0.0
var _hop: Tween


func _ready() -> void:
	name = "Decor"
	cafe_root = Node3D.new()
	add_child(cafe_root)
	theme_root = Node3D.new()
	add_child(theme_root)
	perk_root = Node3D.new()
	add_child(perk_root)


func _mi(mesh: Mesh, col: Color, pos: Vector3, parent: Node3D, glow: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = main.mat(col, glow)
	m.position = pos
	parent.add_child(m)
	return m


static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func _sph(r: float, h: float = -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = 12
	s.rings = 6
	return s


static func _cyl(rt: float, rb: float, h: float, segs: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


## The café's decorations for `lvl` steps (pop: the newest one pops in with sparkles).
func show_cafe(lvl: int, pop: bool) -> void:
	if lvl == level:
		return
	var old := level
	level = lvl
	for c in cafe_root.get_children():
		c.queue_free()
	for i in mini(lvl, Nights.CAFE_STEPS.size()):
		var n := _cafe_piece(String(Nights.CAFE_STEPS[i][1]))
		cafe_root.add_child(n)
		if pop and old >= 0 and i == lvl - 1:
			n.scale = Vector3.ONE * 0.05
			create_tween().tween_property(n, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			main.burst(n.position + Vector3.UP * 1.0, Color(1.0, 0.85, 0.3), 24, 0.06)


func _cafe_piece(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	match kind:
		"fairylights":  # two strings of warm bulbs across the room
			for zz in [-3.6, 3.4]:
				for i in 15:
					var x := -6.5 + i * 0.92
					var sag := 0.25 * sin(PI * fmod(float(i), 5.0) / 5.0)
					var col: Color = [Color(1.0, 0.85, 0.4), Color(1.0, 0.5, 0.6), Color(0.5, 0.85, 1.0)][i % 3]
					_mi(_sph(0.05), col, Vector3(x, 2.5 - sag, zz), n, 3.0)
		"fishtank":
			n.position = Vector3(-4.9, 0.0, 5.45)
			_mi(_box(Vector3(1.3, 0.75, 0.5)), Color(0.55, 0.35, 0.2), Vector3(0, 0.375, 0), n)
			var glass := _mi(_box(Vector3(1.2, 0.7, 0.45)), Color(0.4, 0.8, 1.0), Vector3(0, 1.1, 0), n, 0.4)
			glass.set_meta("tank", true)
			for i in 3:
				var fish := _mi(_sph(0.06, 0.08), [Color(1.0, 0.55, 0.1), Color(1.0, 0.9, 0.2), Color(1.0, 0.4, 0.6)][i], Vector3(-0.3 + 0.3 * i, 1.0 + 0.12 * i, -0.25), n, 0.6)
				fish.name = "Fish%d" % i
				fish.scale = Vector3(1.6, 1.0, 0.7)
		"piano":
			n.position = Vector3(4.3, 0.0, 5.45)
			_mi(_box(Vector3(1.5, 1.25, 0.55)), Color(0.15, 0.1, 0.12), Vector3(0, 0.625, 0), n)
			_mi(_box(Vector3(1.4, 0.05, 0.3)), Color(0.97, 0.97, 0.95), Vector3(0, 0.78, -0.4), n)
			for i in 9:
				_mi(_box(Vector3(0.06, 0.04, 0.16)), Color(0.08, 0.08, 0.1), Vector3(-0.6 + i * 0.15, 0.815, -0.46), n)
			_mi(_box(Vector3(0.6, 0.5, 0.35)), Color(0.75, 0.2, 0.25), Vector3(0, 0.25, -0.95), n)  # the stool
		"lantern":  # round paper lanterns hanging over the room
			for i in 6:
				var col2: Color = [Color(1.0, 0.4, 0.4), Color(1.0, 0.8, 0.3), Color(0.5, 0.8, 1.0)][i % 3]
				var lp := Vector3(-5.0 + i * 2.0, 2.15, -4.3)
				_mi(_sph(0.2, 0.32), col2, lp, n, 1.6)
				_mi(_cyl(0.005, 0.005, 0.4), Color(0.2, 0.2, 0.2), lp + Vector3(0, 0.36, 0), n)
		"cake":
			n.position = Vector3(-3.1, 0.0, 5.3)
			_mi(_cyl(0.35, 0.35, 0.05), Color(0.95, 0.95, 1.0), Vector3(0, 0.8, 0), n)
			_mi(_cyl(0.04, 0.06, 0.78), Color(0.6, 0.4, 0.25), Vector3(0, 0.39, 0), n)
			var y := 0.83
			for i in 3:
				var rr := 0.27 - 0.07 * i
				_mi(_cyl(rr, rr, 0.16), [Color(1.0, 0.75, 0.85), Color(1.0, 0.95, 0.8), Color(0.7, 0.45, 0.3)][i], Vector3(0, y + 0.08, 0), n)
				y += 0.16
			_mi(_sph(0.05), Color(0.95, 0.15, 0.2), Vector3(0, y + 0.04, 0), n, 0.6)
		"fountain":  # outside the serving window
			n.position = Vector3(12.0, 0.0, 0.0)
			_mi(_cyl(1.2, 1.3, 0.45), Color(0.82, 0.82, 0.88), Vector3(0, 0.225, 0), n)
			_mi(_cyl(1.05, 1.05, 0.05), Color(0.4, 0.75, 1.0), Vector3(0, 0.44, 0), n, 0.5)
			_mi(_cyl(0.12, 0.18, 1.1), Color(0.82, 0.82, 0.88), Vector3(0, 0.95, 0), n)
			_mi(_cyl(0.5, 0.35, 0.15), Color(0.82, 0.82, 0.88), Vector3(0, 1.5, 0), n)
			var spray := _mi(_sph(0.25, 0.5), Color(0.6, 0.85, 1.0), Vector3(0, 1.8, 0), n, 1.0)
			spray.name = "Spray"
		"cafestar":  # a big gold star over the back door
			var st := _star(0.34, 0.15)
			st.position = Vector3(0.0, 2.33, -5.82)
			n.add_child(st)
		"chandelier":
			n.position = Vector3(3.2, 2.25, -2.6)
			_mi(_cyl(0.01, 0.01, 0.5), Color(0.8, 0.65, 0.25), Vector3(0, 0.25, 0), n)
			_mi(_cyl(0.45, 0.3, 0.06), Color(1.0, 0.8, 0.3), Vector3.ZERO, n, 0.5)
			for i in 8:
				var a := TAU * i / 8.0
				_mi(_sph(0.055, 0.12), Color(1.0, 0.95, 0.75), Vector3(cos(a) * 0.4, 0.08, sin(a) * 0.4), n, 3.0)
	return n


func _star(r: float, depth: float) -> MeshInstance3D:
	var st := MeshInstance3D.new()
	var am := ArrayMesh.new()
	var verts := PackedVector3Array()
	var pts: Array = []
	for i in 10:
		var a := PI / 2.0 + TAU * i / 10.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(Vector3(cos(a) * rr, sin(a) * rr, 0.0))
	for i in 10:
		var a2: Vector3 = pts[i]
		var b2: Vector3 = pts[(i + 1) % 10]
		verts.append_array([Vector3(0, 0, depth * 0.5), b2, a2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.mesh = am
	var m: StandardMaterial3D = main.mat(Color(1.0, 0.8, 0.2), 1.5).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.material_override = m
	return st


## Tonight's theme: the picture board left of the back door and the bunting over the pass.
func show_theme(th: String) -> void:
	if th == theme or not Nights.THEMES.has(th):
		return
	theme = th
	for c in theme_root.get_children():
		c.queue_free()
	var cols: Array = Nights.THEMES[th]["colors"]
	var board := Node3D.new()
	board.position = Vector3(-1.85, 1.75, -5.8)
	theme_root.add_child(board)
	_mi(_box(Vector3(0.72, 0.72, 0.04)), (cols[1] as Color).lerp(Color.WHITE, 0.3), Vector3.ZERO, board)
	_mi(_box(Vector3(0.78, 0.78, 0.03)), cols[0], Vector3(0, 0, -0.01), board)
	var pic := Node3D.new()
	pic.position = Vector3(0, -0.02, 0.06)
	pic.rotation.x = PI / 2.0
	board.add_child(pic)
	match th:
		"pizza":
			_mi(_cyl(0.28, 0.28, 0.03), Color(0.95, 0.75, 0.4), Vector3.ZERO, pic)
			_mi(_cyl(0.24, 0.24, 0.035), Color(0.95, 0.3, 0.2), Vector3(0, 0.003, 0), pic)
			for i in 6:
				var a := TAU * i / 6.0
				_mi(_cyl(0.045, 0.045, 0.04), Color(0.7, 0.12, 0.1), Vector3(cos(a) * 0.14, 0.006, sin(a) * 0.14), pic)
			_mi(_cyl(0.05, 0.05, 0.04), Color(1.0, 0.9, 0.4), Vector3(0, 0.006, 0), pic)
		"pancake":
			pic.rotation.x = 0.0
			for i in 4:
				_mi(_cyl(0.22, 0.22, 0.06), Color(0.95, 0.72, 0.4), Vector3(0, -0.2 + i * 0.07, 0), pic)
			_mi(_cyl(0.2, 0.18, 0.03), Color(0.55, 0.3, 0.1), Vector3(0, 0.1, 0), pic, 0.3)
			_mi(_box(Vector3(0.09, 0.06, 0.09)), Color(1.0, 0.95, 0.6), Vector3(0, 0.14, 0), pic)
			for i in 3:
				_mi(_sph(0.035), Color(0.4, 0.2, 0.7), Vector3(-0.1 + i * 0.1, 0.15, 0.08), pic)
		"picnic":
			pic.rotation.x = 0.0
			_mi(_box(Vector3(0.44, 0.26, 0.22)), Color(0.75, 0.5, 0.25), Vector3(0, -0.08, 0), pic)
			for i in 4:
				_mi(_box(Vector3(0.11, 0.04, 0.23)), Color(0.95, 0.3, 0.35) if i % 2 == 0 else Color.WHITE, Vector3(-0.165 + i * 0.11, 0.07, 0), pic)
			var handle := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.16
			tm.outer_radius = 0.19
			handle.mesh = tm
			handle.material_override = main.mat(Color(0.6, 0.4, 0.2))
			handle.rotation.x = PI / 2.0
			handle.position = Vector3(0, 0.08, 0)
			pic.add_child(handle)
	# Bunting in the theme's colours over the pass (high, so it never hides the pass or the window).
	for i in 22:
		var x := -6.4 + i * 0.6
		var flag := _mi(_box(Vector3(0.2, 0.2, 0.02)), cols[i % cols.size()], Vector3(x, 2.42 - 0.08 * sin(PI * fmod(float(i), 11.0) / 11.0), -1.4), theme_root, 0.2)
		flag.rotation.z = PI / 4.0


## The chef gifts that show: the BIG POT and the HELPER MOUSE.
func show_perks(list: Array) -> void:
	if list == perks:
		return
	perks = list.duplicate()
	if list.has("pot") and pot == null:
		pot = Node3D.new()
		pot.position = POT_AT
		perk_root.add_child(pot)
		_mi(_cyl(0.24, 0.2, 0.32), Color(0.85, 0.55, 0.2), Vector3(0, 0.16, 0), pot, 0.3)
		_mi(_cyl(0.22, 0.22, 0.02), Color(0.95, 0.75, 0.35), Vector3(0, 0.31, 0), pot, 0.5)
		for i in 3:
			var puff := _mi(_sph(0.07), Color(1, 1, 1), Vector3(-0.08 + 0.08 * i, 0.4, 0), pot, 0.5)
			puff.name = "Steam%d" % i
		pot.scale = Vector3.ONE * 0.05
		create_tween().tween_property(pot, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if list.has("mouse") and mouse == null:
		mouse = Node3D.new()
		mouse.position = MOUSE_HOME
		perk_root.add_child(mouse)
		var grey := Color(0.72, 0.7, 0.75)
		var body := _mi(_sph(0.05, 0.07), grey, Vector3(0, 0.035, 0), mouse)
		body.scale = Vector3(1.0, 1.0, 1.4)
		_mi(_sph(0.03), grey, Vector3(0, 0.06, -0.06), mouse)
		for s in [-1.0, 1.0]:
			_mi(_sph(0.022, 0.01), Color(1.0, 0.7, 0.75), Vector3(s * 0.025, 0.09, -0.05), mouse)
		_mi(_sph(0.008), Color(0.1, 0.1, 0.1), Vector3(0, 0.06, -0.09), mouse)
		var tail := _mi(_cyl(0.006, 0.004, 0.12), Color(1.0, 0.7, 0.75), Vector3(0, 0.02, 0.1), mouse)
		tail.rotation.x = PI / 2.4
		mouse.rotation.y = -PI / 2.0  # looking along the counter
	if not list.has("mouse") and mouse != null:
		mouse.queue_free()
		mouse = null
	if not list.has("pot") and pot != null:
		pot.queue_free()
		pot = null


## Every machine: the mouse scurries to `to` (a pass slot) and back.
func mouse_hop(to: Vector3) -> void:
	if mouse == null:
		return
	if _hop != null and _hop.is_valid():
		_hop.kill()
	mouse.position = MOUSE_HOME
	_hop = create_tween()
	_hop.tween_property(mouse, "position", to + Vector3(0, 0.0, 0.0), 0.45).set_trans(Tween.TRANS_SINE)
	_hop.tween_property(mouse, "position", to + Vector3(0, 0.12, 0), 0.12)
	_hop.tween_property(mouse, "position", to, 0.12)
	_hop.tween_property(mouse, "position", MOUSE_HOME, 0.6).set_delay(0.3)


func _process(delta: float) -> void:
	_t += delta
	if pot != null:
		for i in 3:
			var s := pot.get_node_or_null("Steam%d" % i) as Node3D
			if s != null:
				var k := fmod(_t * 0.5 + i * 0.33, 1.0)
				s.position.y = 0.38 + k * 0.4
				s.scale = Vector3.ONE * (1.0 - k * 0.7)
	if level >= 2:
		var tank := cafe_root.get_node_or_null("fishtank")
		if tank != null:
			for i in 3:
				var f := tank.get_node_or_null("Fish%d" % i) as Node3D
				if f != null:
					f.position.x = 0.4 * sin(_t * (0.6 + 0.2 * i) + i * 2.0)
					f.rotation.y = 0.0 if cos(_t * (0.6 + 0.2 * i) + i * 2.0) > 0.0 else PI
	var fo := cafe_root.get_node_or_null("fountain")
	if fo != null:
		var sp := fo.get_node_or_null("Spray") as Node3D
		if sp != null:
			sp.scale = Vector3.ONE * (1.0 + 0.15 * sin(_t * 6.0))
