extends RefCounted
## KITCHEN RUSH: Gran's café that fills up. The THANK-YOU SHELF on the back wall (right of the door)
## holds the gifts parties leave (saved, newest 15 shown); little guest heads for the invitations; a
## golden crown for star guests. Everything is plain meshes with main.mat() materials (no textures).
##   Cafe.build_shelf(main) -> Node3D        Cafe.show_gifts(shelf, main, gifts, pop_last)
##   Cafe.gift_model(main, kind, golden)     Cafe.guest_head(main, party)     Cafe.crown(main)

const GIFTS := ["teapot", "balloon", "treasure", "robot", "ufo", "shield"]
const SHELF_X := 3.0
const SHELF_Z := -5.72
const ROWS: Array = [1.35, 1.75, 2.15]
const COLS := 5
const GOLD := Color(1.0, 0.8, 0.22)
const PARTY_COLORS := {"granny": Color(0.92, 0.75, 0.9), "kid": Color(1.0, 0.6, 0.4), "pirate": Color(0.95, 0.75, 0.55),
	"robot": Color(0.72, 0.76, 0.82), "alien": Color(0.45, 0.95, 0.4), "knight": Color(0.75, 0.77, 0.82)}


static func slot_count() -> int:
	return ROWS.size() * COLS


static func slot_pos(i: int) -> Vector3:
	var row := i / COLS
	var col := i % COLS
	return Vector3(SHELF_X - 0.8 + col * 0.4, float(ROWS[row]) + 0.025, SHELF_Z)


static func build_shelf(main: Node3D) -> Node3D:
	var shelf := Node3D.new()
	shelf.name = "GiftShelf"
	main.add_child(shelf)
	for y in ROWS:
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.1, 0.05, 0.3)
		board.mesh = bm
		board.material_override = main.mat(Color(0.8, 0.55, 0.32))
		board.position = Vector3(SHELF_X, float(y), SHELF_Z)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shelf.add_child(board)
	var gifts := Node3D.new()
	gifts.name = "Gifts"
	shelf.add_child(gifts)
	return shelf


## Show the newest gifts ([kind, golden] entries). pop_last: the newest one pops in with sparkles.
static func show_gifts(shelf: Node3D, main: Node3D, gifts: Array, pop_last: bool = false) -> void:
	if shelf == null:
		return
	var holder: Node3D = shelf.get_node("Gifts")
	for c in holder.get_children():
		c.queue_free()
	var start := maxi(0, gifts.size() - slot_count())
	for i in range(start, gifts.size()):
		var g: Array = gifts[i]
		var m := gift_model(main, String(g[0]), bool(g[1]) if g.size() > 1 else false)
		m.position = slot_pos(i - start)
		m.rotation.y = 0.25 * sin(float(i) * 1.7)
		holder.add_child(m)
		if pop_last and i == gifts.size() - 1:
			m.scale = Vector3.ONE * 0.05
			var tw := m.create_tween()
			tw.tween_property(m, "scale", Vector3.ONE * 1.3, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(m, "scale", Vector3.ONE, 0.25)
			if main.has_method("burst"):
				main.burst(m.position + Vector3.UP * 0.12, GOLD, 24, 0.05)


static func _mi(main: Node3D, mesh: Mesh, color: Color, pos: Vector3, parent: Node3D, glow: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = main.mat(color, glow)
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


static func _sph(r: float, h: float = -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0.0 else r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _cyl(rt: float, rb: float, h: float, segs: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


## A thank-you gift about 25 cm tall standing on y = 0. Golden ones shine.
static func gift_model(main: Node3D, kind: String, golden: bool = false) -> Node3D:
	var root := Node3D.new()
	var glow := 0.6 if golden else 0.0
	match kind:
		"teapot":
			var c := GOLD if golden else Color(0.6, 0.8, 1.0)
			_mi(main, _sph(0.09, 0.15), c, Vector3(0, 0.08, 0), root, glow)
			var spout := _mi(main, _cyl(0.015, 0.025, 0.12, 8), c, Vector3(0.1, 0.1, 0), root, glow)
			spout.rotation.z = -0.8
			var handle := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.035
			tm.outer_radius = 0.05
			tm.rings = 10
			tm.ring_segments = 4
			handle.mesh = tm
			handle.material_override = main.mat(c, glow)
			handle.position = Vector3(-0.09, 0.09, 0)
			handle.rotation.x = PI / 2.0
			root.add_child(handle)
			_mi(main, _sph(0.02), Color(1.0, 0.5, 0.6), Vector3(0, 0.165, 0), root)
			for k in 3:
				_mi(main, _sph(0.018), Color(1.0, 0.55, 0.7), Vector3(-0.03 + k * 0.03, 0.09, 0.085), root)
		"balloon":
			var c2 := GOLD if golden else Color(1.0, 0.35, 0.45)
			_mi(main, _sph(0.08, 0.19), c2, Vector3(0, 0.2, 0), root, glow + 0.2)
			_mi(main, _cyl(0.003, 0.003, 0.14, 4), Color(0.9, 0.9, 0.9), Vector3(0, 0.07, 0), root)
			_mi(main, _cyl(0.04, 0.05, 0.02), Color(0.5, 0.35, 0.2), Vector3(0, 0.01, 0), root)
			_mi(main, _sph(0.06, 0.15), Color(0.4, 0.75, 1.0), Vector3(0.08, 0.15, 0.02), root, 0.2)
		"treasure":
			var wood := Color(0.6, 0.38, 0.2)
			_mi(main, _box(Vector3(0.22, 0.11, 0.14)), GOLD if golden else wood, Vector3(0, 0.055, 0), root, glow)
			var lid := _mi(main, _cyl(0.07, 0.07, 0.22, 10), GOLD if golden else wood.lightened(0.1), Vector3(0, 0.11, -0.01), root, glow)
			lid.rotation.z = PI / 2.0
			lid.scale = Vector3(1.0, 1.0, 0.95)
			_mi(main, _box(Vector3(0.03, 0.125, 0.145)), GOLD, Vector3(0.0, 0.07, 0), root, 0.4)
			for k in 3:
				_mi(main, _cyl(0.025, 0.025, 0.008), GOLD, Vector3(-0.05 + k * 0.05, 0.19 + k * 0.004, 0.03), root, 0.8)
		"robot":
			var c3 := GOLD if golden else Color(0.72, 0.76, 0.82)
			_mi(main, _box(Vector3(0.12, 0.12, 0.09)), c3, Vector3(0, 0.07, 0), root, glow)
			_mi(main, _box(Vector3(0.1, 0.08, 0.08)), c3.lightened(0.15), Vector3(0, 0.18, 0), root, glow)
			for x in [-0.025, 0.025]:
				_mi(main, _sph(0.014), Color(0.4, 0.9, 1.0), Vector3(x, 0.19, 0.041), root, 1.5)
			_mi(main, _cyl(0.005, 0.005, 0.06, 4), Color(0.4, 0.4, 0.45), Vector3(0, 0.25, 0), root)
			_mi(main, _sph(0.016), Color(1.0, 0.25, 0.25), Vector3(0, 0.285, 0), root, 2.0)
			for x2 in [-0.08, 0.08]:
				_mi(main, _box(Vector3(0.03, 0.09, 0.03)), c3.darkened(0.15), Vector3(x2, 0.08, 0), root, glow)
		"ufo":
			var c4 := GOLD if golden else Color(0.75, 0.8, 0.9)
			var disc := _mi(main, _sph(0.12, 0.06), c4, Vector3(0, 0.1, 0), root, glow)
			disc.scale = Vector3(1.0, 1.0, 1.0)
			_mi(main, _sph(0.06), Color(0.55, 1.0, 0.6, 1.0), Vector3(0, 0.13, 0), root, 0.6)
			for k in 6:
				var a := TAU * k / 6.0
				_mi(main, _sph(0.012), [Color(1.0, 0.4, 0.8), Color(1.0, 0.9, 0.3), Color(0.4, 0.9, 1.0)][k % 3], Vector3(cos(a) * 0.1, 0.095, sin(a) * 0.1), root, 2.0)
			_mi(main, _cyl(0.008, 0.03, 0.07, 6), Color(0.4, 0.4, 0.45), Vector3(0, 0.035, 0), root)
		"shield":
			var face := _mi(main, _cyl(0.11, 0.11, 0.025, 16), GOLD if golden else Color(0.9, 0.25, 0.3), Vector3(0, 0.12, 0.02), root, glow)
			face.rotation.x = PI / 2.0
			var bar := _mi(main, _box(Vector3(0.04, 0.18, 0.01)), GOLD if not golden else Color(0.9, 0.25, 0.3), Vector3(0, 0.12, 0.036), root, 0.4)
			bar.rotation.z = 0.0
			_mi(main, _box(Vector3(0.18, 0.04, 0.01)), GOLD if not golden else Color(0.9, 0.25, 0.3), Vector3(0, 0.12, 0.036), root, 0.4)
			_mi(main, _box(Vector3(0.05, 0.02, 0.05)), Color(0.5, 0.35, 0.2), Vector3(0, 0.01, 0.0), root)
		_:
			_mi(main, _box(Vector3(0.14, 0.14, 0.14)), GOLD if golden else Color(1.0, 0.45, 0.6), Vector3(0, 0.07, 0), root, glow)
	if golden:
		var sp := _mi(main, _sph(0.02), Color(1.0, 1.0, 0.8), Vector3(0.1, 0.24, 0.05), root, 3.0)
		sp.name = "Sparkle"
	return root


## A little guest head (about 20 cm) for the invitations: the party's colour plus its hat.
static func guest_head(main: Node3D, party: String) -> Node3D:
	var root := Node3D.new()
	var col: Color = PARTY_COLORS.get(party, Color(1.0, 0.7, 0.5))
	_mi(main, _sph(0.09), col, Vector3(0, 0.09, 0), root, 0.15)
	for z in [-0.032, 0.032]:
		var eye := _mi(main, _sph(0.022), Color.WHITE if party != "robot" else Color(0.4, 0.9, 1.0), Vector3(z, 0.11, 0.075), root, 0.0 if party != "robot" else 1.5)
		if party != "robot":
			_mi(main, _sph(0.011), Color(0.08, 0.08, 0.12), Vector3(0, 0, 0.014), eye)
	_mi(main, _box(Vector3(0.04, 0.012, 0.01)), Color(0.4, 0.08, 0.12), Vector3(0, 0.06, 0.086), root)
	match party:
		"granny":
			_mi(main, _sph(0.045), Color(0.9, 0.9, 0.92), Vector3(0, 0.19, -0.02), root)
			var hair := _mi(main, _sph(0.095), Color(0.9, 0.9, 0.92), Vector3(0, 0.13, -0.02), root)
			hair.scale = Vector3(1.0, 0.55, 1.0)
		"kid":
			var cap := _mi(main, _sph(0.07), Color(0.3, 0.6, 1.0), Vector3(0, 0.16, 0), root)
			cap.scale = Vector3(1.0, 0.5, 1.0)
			_mi(main, _box(Vector3(0.16, 0.006, 0.025)), Color(1.0, 0.3, 0.3), Vector3(0, 0.2, 0), root)
		"pirate":
			_mi(main, _cyl(0.1, 0.1, 0.02, 3), Color(0.1, 0.08, 0.1), Vector3(0, 0.165, 0), root)
			_mi(main, _cyl(0.055, 0.065, 0.06, 8), Color(0.1, 0.08, 0.1), Vector3(0, 0.19, 0), root)
			_mi(main, _box(Vector3(0.03, 0.03, 0.01)), Color(0.05, 0.05, 0.05), Vector3(0.032, 0.11, 0.096), root)
		"robot":
			_mi(main, _cyl(0.005, 0.005, 0.08, 4), Color(0.4, 0.4, 0.45), Vector3(0, 0.2, 0), root)
			_mi(main, _sph(0.02), Color(1.0, 0.2, 0.2), Vector3(0, 0.245, 0), root, 2.5)
		"alien":
			for x in [-0.04, 0.04]:
				var ant := _mi(main, _cyl(0.004, 0.004, 0.09, 4), Color(0.3, 0.75, 0.3), Vector3(x, 0.2, 0), root)
				ant.rotation.z = -x * 6.0
				_mi(main, _sph(0.018), Color(1.0, 0.4, 0.9), Vector3(x * 1.6, 0.245, 0), root, 2.0)
		"knight":
			var helm := _mi(main, _sph(0.1), Color(0.75, 0.77, 0.82), Vector3(0, 0.12, -0.01), root)
			helm.scale = Vector3(1.05, 0.8, 1.0)
			var plume := _mi(main, _sph(0.04), Color(0.95, 0.2, 0.25), Vector3(0, 0.215, -0.02), root)
			plume.scale = Vector3(0.6, 1.0, 1.6)
	return root


## A little golden crown (star guests), about 30 cm across, base on y = 0.
static func crown(main: Node3D) -> Node3D:
	var root := Node3D.new()
	_mi(main, _cyl(0.17, 0.17, 0.08, 14), GOLD, Vector3(0, 0.04, 0), root, 0.8)
	for k in 5:
		var a := TAU * k / 5.0
		var spike := _mi(main, _cyl(0.0, 0.04, 0.1, 4), GOLD, Vector3(cos(a) * 0.15, 0.12, sin(a) * 0.15), root, 0.8)
		spike.name = "Spike%d" % k
		_mi(main, _sph(0.022), [Color(1.0, 0.3, 0.4), Color(0.3, 0.6, 1.0), Color(0.4, 1.0, 0.5)][k % 3], Vector3(cos(a) * 0.17, 0.05, sin(a) * 0.17), root, 1.2)
	return root
