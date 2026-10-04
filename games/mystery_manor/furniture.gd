extends RefCounted
## MYSTERY MANOR: furnishes every room of the manor (manor.gd ManorNode) with merged, vertex-coloured
## props: bookshelves, a grand piano, a dining table with candelabras, an oven, trunks, jam shelves,
## hedges and a fountain... Every piece that you can bump into gets a collision box (and a nav-grid
## footprint) through m.solid(). Positions match the spots / surfaces / paintings / scenes tables
## in manor.gd. Front of a piece = +Z before its yaw.

const MeshKit := preload("res://core/mesh_kit.gd")

const LEVEL_Y: Array[float] = [0.0, 6.0, -6.0]
const WOOD_D := Color(0.33, 0.2, 0.12)
const WOOD_M := Color(0.52, 0.33, 0.19)
const WOOD_L := Color(0.72, 0.52, 0.32)
const BRASS := Color(0.95, 0.75, 0.32)
const CREAM := Color(0.95, 0.91, 0.8)
const IRON := Color(0.22, 0.22, 0.26)
const LEAF := Color(0.25, 0.55, 0.28)
const BOOK_COLS: Array[Color] = [Color(0.7, 0.18, 0.18), Color(0.18, 0.36, 0.62), Color(0.2, 0.5, 0.3),
	Color(0.85, 0.65, 0.25), Color(0.45, 0.22, 0.5), Color(0.9, 0.85, 0.75), Color(0.3, 0.2, 0.15)]

static var _rng := RandomNumberGenerator.new()


static func furnish(m: Node3D) -> void:
	_rng.seed = 4242
	_hall(m)
	_library(m)
	_music(m)
	_conservatory(m)
	_study(m)
	_dining(m)
	_kitchen(m)
	_garden(m)
	_attic(m)
	_cellar(m)


# --- Helpers ------------------------------------------------------------------------------------

static func _lv(r: int) -> int:
	return 1 if r == 8 else (2 if r == 9 else 0)


## A transform for a piece standing at floor point `pos` (y = height above the room's floor) facing yaw.
static func _t(r: int, pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, LEVEL_Y[_lv(r)], 0))


## Collision box for a piece of `size` (local x, y, z) standing at `pos` with a yaw of n * 90 deg.
static func _solid(m: Node3D, r: int, pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var s := size
	if absf(sin(yaw)) > 0.7:
		s = Vector3(size.z, size.y, size.x)
	m.solid(_lv(r), pos + Vector3(0, LEVEL_Y[_lv(r)] + size.y * 0.5, 0), s)


static func _box(b: MeshKit.Builder, t: Transform3D, c: Vector3, size: Vector3, col: Color, glow: bool = false) -> void:
	b.box(size, t * MeshKit.at(c), col, glow)


static func _rbox(b: MeshKit.Builder, t: Transform3D, c: Vector3, size: Vector3, rad: float, col: Color, glow: bool = false) -> void:
	b.rounded_box(size, rad, t * MeshKit.at(c), col, 2, glow)


static func _cyl(b: MeshKit.Builder, t: Transform3D, c: Vector3, r_top: float, r_bot: float, h: float, col: Color, segs: int = 12, glow: bool = false) -> void:
	b.cylinder(r_top, r_bot, h, t * MeshKit.at(c), col, segs, glow)


static func _sph(b: MeshKit.Builder, t: Transform3D, c: Vector3, rad: float, col: Color, segs: int = 10, glow: bool = false) -> void:
	b.sphere(rad, t * MeshKit.at(c), col, segs, glow)


# --- Furniture pieces (local: origin = floor centre, front = +Z) --------------------------------------

static func bookshelf(b: MeshKit.Builder, t: Transform3D, size: Vector3) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	_box(b, t, Vector3(0, h * 0.5, -d * 0.45), Vector3(w, h, 0.05), WOOD_D)
	_box(b, t, Vector3(-w * 0.5 + 0.04, h * 0.5, 0), Vector3(0.08, h, d), WOOD_M)
	_box(b, t, Vector3(w * 0.5 - 0.04, h * 0.5, 0), Vector3(0.08, h, d), WOOD_M)
	_box(b, t, Vector3(0, h - 0.05, 0.02), Vector3(w + 0.12, 0.1, d + 0.06), WOOD_M)
	var shelves := int(h / 0.5)
	for i in shelves:
		var y := 0.08 + i * (h - 0.15) / float(shelves)
		_box(b, t, Vector3(0, y, 0), Vector3(w - 0.12, 0.04, d - 0.02), WOOD_M)
		var x := -w * 0.5 + 0.12
		while x < w * 0.5 - 0.16:
			var bw := _rng.randf_range(0.05, 0.09)
			var bh := _rng.randf_range(0.24, 0.36)
			var col: Color = BOOK_COLS[_rng.randi() % BOOK_COLS.size()]
			if _rng.randf() < 0.08:
				x += 0.1  # a gap
				continue
			var lean := 0.0 if _rng.randf() < 0.85 else 0.25
			b.box(Vector3(bw, bh, d * 0.75), t * MeshKit.at(Vector3(x + bw * 0.5, y + 0.02 + bh * 0.5, 0.0), Vector3.ONE, Vector3(0, 0, lean)), col)
			x += bw + 0.008


static func table(b: MeshKit.Builder, t: Transform3D, size: Vector3, top: Color = WOOD_M, cloth: Color = Color(0, 0, 0, 0)) -> void:
	_rbox(b, t, Vector3(0, size.y - 0.03, 0), Vector3(size.x, 0.06, size.z), 0.02, top)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var fx: float = sx
			var fz: float = sz
			_cyl(b, t, Vector3(fx * (size.x * 0.5 - 0.08), (size.y - 0.06) * 0.5, fz * (size.z * 0.5 - 0.08)), 0.035, 0.025, size.y - 0.06, WOOD_D, 8)
	if cloth.a > 0.0:
		_box(b, t, Vector3(0, size.y + 0.005, 0), Vector3(size.x + 0.1, 0.012, size.z + 0.1), cloth)
		_box(b, t, Vector3(0, size.y - 0.12, size.z * 0.5 + 0.05), Vector3(size.x + 0.1, 0.25, 0.012), cloth)
		_box(b, t, Vector3(0, size.y - 0.12, -size.z * 0.5 - 0.05), Vector3(size.x + 0.1, 0.25, 0.012), cloth)


static func chair(b: MeshKit.Builder, t: Transform3D, col: Color = WOOD_M, seat: Color = Color(0.6, 0.16, 0.2)) -> void:
	_box(b, t, Vector3(0, 0.45, 0), Vector3(0.45, 0.06, 0.45), col)
	_rbox(b, t, Vector3(0, 0.5, 0), Vector3(0.4, 0.06, 0.4), 0.02, seat)
	_box(b, t, Vector3(0, 0.8, -0.2), Vector3(0.45, 0.6, 0.05), col)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var fx: float = sx
			var fz: float = sz
			_box(b, t, Vector3(fx * 0.19, 0.22, fz * 0.19), Vector3(0.05, 0.44, 0.05), col)


static func armchair(b: MeshKit.Builder, t: Transform3D, col: Color) -> void:
	_rbox(b, t, Vector3(0, 0.25, 0), Vector3(0.9, 0.35, 0.85), 0.08, col)
	_rbox(b, t, Vector3(0, 0.75, -0.33), Vector3(0.9, 0.75, 0.22), 0.1, col)
	_rbox(b, t, Vector3(-0.38, 0.55, 0.02), Vector3(0.16, 0.35, 0.8), 0.07, col.darkened(0.1))
	_rbox(b, t, Vector3(0.38, 0.55, 0.02), Vector3(0.16, 0.35, 0.8), 0.07, col.darkened(0.1))
	_rbox(b, t, Vector3(0, 0.47, 0.06), Vector3(0.6, 0.12, 0.62), 0.05, col.lightened(0.12))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var fx: float = sx
			var fz: float = sz
			_cyl(b, t, Vector3(fx * 0.36, 0.04, fz * 0.32), 0.04, 0.03, 0.08, WOOD_D, 6)


static func sofa(b: MeshKit.Builder, t: Transform3D, size: Vector3, col: Color) -> void:
	_rbox(b, t, Vector3(0, 0.25, 0.05), Vector3(size.x, 0.32, size.z - 0.1), 0.08, col)
	_rbox(b, t, Vector3(0, 0.65, -size.z * 0.5 + 0.12), Vector3(size.x, 0.7, 0.24), 0.1, col)
	_rbox(b, t, Vector3(-size.x * 0.5 + 0.1, 0.5, 0.05), Vector3(0.2, 0.35, size.z - 0.1), 0.08, col.darkened(0.1))
	_rbox(b, t, Vector3(size.x * 0.5 - 0.1, 0.5, 0.05), Vector3(0.2, 0.35, size.z - 0.1), 0.08, col.darkened(0.1))
	var n := int(size.x / 0.7)
	for i in n:
		var x := -size.x * 0.5 + 0.25 + (size.x - 0.5) * (float(i) + 0.5) / float(n)
		_rbox(b, t, Vector3(x, 0.46, 0.08), Vector3((size.x - 0.5) / float(n) - 0.04, 0.12, size.z - 0.35), 0.05, col.lightened(0.12))
	_rbox(b, t, Vector3(-size.x * 0.3, 0.68, -0.05), Vector3(0.3, 0.3, 0.12), 0.06, Color(0.95, 0.8, 0.4))


static func cabinet(b: MeshKit.Builder, t: Transform3D, size: Vector3, col: Color, glass: bool = false, top_items: bool = true) -> void:
	_rbox(b, t, Vector3(0, size.y * 0.5, 0), size, 0.03, col)
	_box(b, t, Vector3(0, size.y + 0.02, 0), Vector3(size.x + 0.06, 0.04, size.z + 0.06), col.darkened(0.2))
	var doors := maxi(1, int(size.x / 0.5))
	for i in doors:
		var x := -size.x * 0.5 + size.x * (float(i) + 0.5) / float(doors)
		var dw := size.x / float(doors) - 0.06
		if glass:
			_box(b, t, Vector3(x, size.y * 0.55, size.z * 0.5 + 0.005), Vector3(dw, size.y * 0.75, 0.01), Color(0.55, 0.7, 0.8))
			# plates and cups behind the glass
			for k in 3:
				var py := size.y * 0.25 + k * size.y * 0.22
				_sph(b, t, Vector3(x - dw * 0.2, py, size.z * 0.2), 0.06, Color(0.95, 0.95, 1.0), 8)
				_sph(b, t, Vector3(x + dw * 0.2, py, size.z * 0.2), 0.05, Color(0.5, 0.75, 0.95), 8)
		else:
			_box(b, t, Vector3(x, size.y * 0.5, size.z * 0.5 + 0.01), Vector3(dw, size.y - 0.12, 0.02), col.lightened(0.08))
			_box(b, t, Vector3(x, size.y * 0.5, size.z * 0.5 + 0.02), Vector3(dw - 0.1, size.y - 0.25, 0.02), col.darkened(0.06))
		_sph(b, t, Vector3(x + dw * 0.35, size.y * 0.5, size.z * 0.5 + 0.04), 0.025, BRASS, 6)
	if top_items and size.y < 1.3:
		_cyl(b, t, Vector3(-size.x * 0.3, size.y + 0.15, 0), 0.08, 0.1, 0.26, Color(0.3, 0.55, 0.8), 10)
		_sph(b, t, Vector3(size.x * 0.25, size.y + 0.1, 0), 0.1, Color(0.85, 0.3, 0.3), 10)


static func desk(b: MeshKit.Builder, t: Transform3D, size: Vector3) -> void:
	_rbox(b, t, Vector3(0, size.y - 0.03, 0), Vector3(size.x, 0.06, size.z), 0.02, WOOD_M)
	_box(b, t, Vector3(0, size.y - 0.005, 0), Vector3(size.x - 0.2, 0.01, size.z - 0.2), Color(0.2, 0.42, 0.28))
	for sx in [-1.0, 1.0]:
		var fx: float = sx
		_box(b, t, Vector3(fx * (size.x * 0.5 - 0.22), (size.y - 0.06) * 0.5, 0), Vector3(0.42, size.y - 0.06, size.z - 0.06), WOOD_D)
		for k in 3:
			var y := 0.15 + k * (size.y - 0.25) / 3.0
			_box(b, t, Vector3(fx * (size.x * 0.5 - 0.22), y + 0.1, size.z * 0.5 - 0.02), Vector3(0.36, 0.18, 0.02), WOOD_L)
			_sph(b, t, Vector3(fx * (size.x * 0.5 - 0.22), y + 0.1, size.z * 0.5 + 0.01), 0.02, BRASS, 6)
	# a green banker's lamp and some papers
	_cyl(b, t, Vector3(size.x * 0.35, size.y + 0.02, -size.z * 0.25), 0.07, 0.08, 0.03, BRASS, 8)
	_cyl(b, t, Vector3(size.x * 0.35, size.y + 0.15, -size.z * 0.25), 0.012, 0.012, 0.25, BRASS, 6)
	b.cylinder(0.05, 0.08, 0.12, t * MeshKit.at(Vector3(size.x * 0.35, size.y + 0.3, -size.z * 0.18), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.3, 0.9, 0.5), 10, true)
	_box(b, t, Vector3(-size.x * 0.2, size.y + 0.01, 0.05), Vector3(0.3, 0.01, 0.22), CREAM)
	_cyl(b, t, Vector3(-size.x * 0.35, size.y + 0.06, -0.15), 0.04, 0.04, 0.1, Color(0.15, 0.15, 0.2), 8)


static func piano(b: MeshKit.Builder, t: Transform3D) -> void:
	var black := Color(0.08, 0.07, 0.09)
	_rbox(b, t, Vector3(0, 0.82, 0), Vector3(1.5, 0.3, 1.8), 0.12, black)
	_rbox(b, t, Vector3(0.25, 0.82, -0.45), Vector3(1.0, 0.3, 0.9), 0.3, black)
	# the lid propped open
	b.box(Vector3(1.4, 0.03, 1.6), t * MeshKit.at(Vector3(-0.1, 1.25, -0.05), Vector3.ONE, Vector3(0, 0, 0.55)), black)
	_cyl(b, t, Vector3(0.55, 1.12, 0.1), 0.012, 0.012, 0.6, BRASS, 6)
	# keyboard
	_box(b, t, Vector3(0, 0.74, 0.98), Vector3(1.4, 0.06, 0.22), black)
	_box(b, t, Vector3(0, 0.78, 0.98), Vector3(1.3, 0.03, 0.17), Color(0.98, 0.97, 0.92))
	for i in 18:
		if i % 7 == 2 or i % 7 == 6:
			continue
		_box(b, t, Vector3(-0.62 + i * 0.072, 0.8, 0.94), Vector3(0.035, 0.03, 0.1), black)
	for lx in [-0.6, 0.6, 0.2]:
		var fx: float = lx
		_cyl(b, t, Vector3(fx, 0.34, 0.6 if fx != 0.2 else -1.0), 0.06, 0.05, 0.68, black, 8)
	_box(b, t, Vector3(0, 1.0, 0.82), Vector3(0.6, 0.3, 0.02), Color(0.98, 0.97, 0.92))
	# a stool
	_rbox(b, t, Vector3(0, 0.45, 1.45), Vector3(0.7, 0.1, 0.35), 0.04, Color(0.4, 0.12, 0.15))
	_box(b, t, Vector3(0, 0.2, 1.45), Vector3(0.6, 0.4, 0.3), black)


static func harp(b: MeshKit.Builder, t: Transform3D) -> void:
	var gold := Color(0.95, 0.78, 0.35)
	b.tube(t * Vector3(0, 0.1, 0), t * Vector3(0, 1.75, -0.15), 0.06, 0.04, gold, 8)
	b.tube(t * Vector3(0, 1.75, -0.15), t * Vector3(0, 1.5, 0.75), 0.04, 0.04, gold, 8)
	b.tube(t * Vector3(0, 0.1, 0), t * Vector3(0, 1.5, 0.75), 0.07, 0.05, WOOD_L, 8)
	for i in 9:
		var f := float(i + 1) / 10.0
		b.tube(t * Vector3(0, 0.15 + f * 1.3, f * 0.7), t * Vector3(0, 1.72 - f * 0.25, -0.12 + f * 0.85), 0.004, 0.004, Color(1, 1, 0.9), 3)
	_cyl(b, t, Vector3(0, 0.05, 0.1), 0.25, 0.28, 0.1, gold, 12)


static func clock(b: MeshKit.Builder, t: Transform3D) -> void:
	_rbox(b, t, Vector3(0, 0.9, 0), Vector3(0.5, 1.8, 0.4), 0.04, WOOD_D)
	_rbox(b, t, Vector3(0, 1.95, 0), Vector3(0.6, 0.55, 0.44), 0.06, WOOD_M)
	_cyl(b, t * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), Vector3(0, 0.23, -1.95), 0.21, 0.21, 0.02, CREAM, 16)
	b.disc(0.2, t * MeshKit.at(Vector3(0, 1.95, 0.235), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.95, 0.75), 16, true)
	_box(b, t, Vector3(0, 2.0, 0.25), Vector3(0.02, 0.15, 0.01), Color(0.1, 0.1, 0.1))
	_box(b, t, Vector3(0.05, 1.95, 0.25), Vector3(0.11, 0.02, 0.01), Color(0.1, 0.1, 0.1))
	_box(b, t, Vector3(0, 1.0, 0.205), Vector3(0.3, 0.9, 0.01), Color(0.2, 0.15, 0.1))
	_sph(b, t, Vector3(0, 0.7, 0.21), 0.07, BRASS, 10)
	_box(b, t, Vector3(0, 1.0, 0.21), Vector3(0.015, 0.6, 0.01), BRASS)
	b.cone(0.22, 0.2, t * MeshKit.at(Vector3(0, 2.32, 0)), WOOD_M, 4)


static func fireplace(b: MeshKit.Builder, t: Transform3D, size: Vector3) -> void:
	var stone := Color(0.78, 0.74, 0.7)
	_box(b, t, Vector3(0, size.y * 0.5, 0), size, stone)
	_box(b, t, Vector3(0, 0.45, size.z * 0.5 - 0.05), Vector3(size.x * 0.55, 0.9, 0.12), Color(0.06, 0.05, 0.05))
	_box(b, t, Vector3(0, size.y + 0.05, 0.06), Vector3(size.x + 0.3, 0.1, size.z + 0.15), Color(0.55, 0.36, 0.22))
	_box(b, t, Vector3(0, 0.03, size.z * 0.5 + 0.35), Vector3(size.x * 0.8, 0.06, 0.6), Color(0.5, 0.2, 0.15))
	# logs and flames (glow)
	b.capsule_between(t * Vector3(-0.3, 0.12, size.z * 0.5 - 0.05), t * Vector3(0.3, 0.12, size.z * 0.5 - 0.15), 0.07, WOOD_D)
	b.capsule_between(t * Vector3(-0.25, 0.12, size.z * 0.5 - 0.2), t * Vector3(0.28, 0.12, size.z * 0.5 + 0.0), 0.07, WOOD_M)
	b.cone(0.18, 0.45, t * MeshKit.at(Vector3(0, 0.35, size.z * 0.5 - 0.08)), Color(1.0, 0.55, 0.15), 8, true)
	b.cone(0.11, 0.32, t * MeshKit.at(Vector3(-0.17, 0.3, size.z * 0.5 - 0.06)), Color(1.0, 0.8, 0.3), 8, true)
	b.cone(0.1, 0.3, t * MeshKit.at(Vector3(0.18, 0.28, size.z * 0.5 - 0.1)), Color(1.0, 0.7, 0.25), 8, true)
	# chimney breast to the ceiling
	_box(b, t, Vector3(0, size.y + 1.0, -0.05), Vector3(size.x - 0.2, 2.0, size.z - 0.1), Color(0.6, 0.2, 0.22))
	# candlesticks on the mantel
	for sx in [-1.0, 1.0]:
		var fx: float = sx
		_cyl(b, t, Vector3(fx * size.x * 0.38, size.y + 0.2, 0.1), 0.025, 0.04, 0.3, BRASS, 8)
		_cyl(b, t, Vector3(fx * size.x * 0.38, size.y + 0.42, 0.1), 0.018, 0.018, 0.14, CREAM, 8)
		b.sphere(0.025, t * MeshKit.at(Vector3(fx * size.x * 0.38, size.y + 0.52, 0.1), Vector3(1, 1.6, 1)), Color(1.0, 0.8, 0.35), 6, true)


static func plant(b: MeshKit.Builder, t: Transform3D, pot: Color = Color(0.78, 0.42, 0.28), big: float = 1.0) -> void:
	_cyl(b, t, Vector3(0, 0.22 * big, 0), 0.22 * big, 0.16 * big, 0.44 * big, pot, 10)
	_cyl(b, t, Vector3(0, 0.43 * big, 0), 0.2 * big, 0.2 * big, 0.03, Color(0.3, 0.2, 0.12), 10)
	for i in 7:
		var a := i * TAU / 7.0
		var r := 0.12 * big
		b.ellipsoid(Vector3(0.12, 0.28, 0.06) * big, t * MeshKit.at(Vector3(cos(a) * r, 0.7 * big, sin(a) * r), Vector3.ONE, Vector3(sin(a) * 0.6, -a, cos(a) * 0.6)), LEAF.lightened(_rng.randf() * 0.2), 8)
	_sph(b, t, Vector3(0, 0.75 * big, 0), 0.14 * big, LEAF.darkened(0.1), 8)


static func lamp(b: MeshKit.Builder, t: Transform3D, shade: Color = Color(1.0, 0.82, 0.55)) -> void:
	_cyl(b, t, Vector3(0, 0.03, 0), 0.18, 0.2, 0.06, BRASS, 10)
	_cyl(b, t, Vector3(0, 0.8, 0), 0.018, 0.018, 1.5, BRASS, 6)
	b.cylinder(0.14, 0.24, 0.3, t * MeshKit.at(Vector3(0, 1.6, 0)), shade, 12, true)


static func candelabra(b: MeshKit.Builder, t: Transform3D) -> void:
	_cyl(b, t, Vector3(0, 0.02, 0), 0.07, 0.09, 0.04, BRASS, 8)
	_cyl(b, t, Vector3(0, 0.18, 0), 0.015, 0.015, 0.3, BRASS, 6)
	b.tube(t * Vector3(-0.15, 0.3, 0), t * Vector3(0.15, 0.3, 0), 0.012, 0.012, BRASS, 6)
	for x in [-0.15, 0.0, 0.15]:
		var fx: float = x
		var top := 0.36 if fx != 0.0 else 0.42
		_cyl(b, t, Vector3(fx, top, 0), 0.016, 0.016, 0.12, CREAM, 6)
		b.sphere(0.02, t * MeshKit.at(Vector3(fx, top + 0.09, 0), Vector3(1, 1.7, 1)), Color(1.0, 0.82, 0.4), 6, true)


static func armour(b: MeshKit.Builder, t: Transform3D) -> void:
	var steel := Color(0.72, 0.75, 0.82)
	_box(b, t, Vector3(0, 0.08, 0), Vector3(0.6, 0.16, 0.5), Color(0.35, 0.3, 0.3))
	b.capsule(0.12, 0.7, t * MeshKit.at(Vector3(-0.1, 0.5, 0)), steel, 8)
	b.capsule(0.12, 0.7, t * MeshKit.at(Vector3(0.1, 0.5, 0)), steel, 8)
	_rbox(b, t, Vector3(0, 1.1, 0), Vector3(0.48, 0.55, 0.32), 0.12, steel)
	_sph(b, t, Vector3(0, 1.55, 0), 0.19, steel, 12)
	_box(b, t, Vector3(0, 1.55, 0.17), Vector3(0.2, 0.04, 0.04), Color(0.1, 0.1, 0.12))
	b.ellipsoid(Vector3(0.05, 0.2, 0.1), t * MeshKit.at(Vector3(0, 1.82, 0)), Color(0.9, 0.2, 0.25), 8)
	b.capsule(0.08, 0.55, t * MeshKit.at(Vector3(-0.32, 1.0, 0.05)), steel, 8)
	b.capsule(0.08, 0.55, t * MeshKit.at(Vector3(0.32, 1.0, 0.05)), steel, 8)
	b.tube(t * Vector3(0.38, 0.4, 0.15), t * Vector3(0.38, 2.0, 0.15), 0.02, 0.02, WOOD_D, 6)
	b.cone(0.05, 0.2, t * MeshKit.at(Vector3(0.38, 2.1, 0.15)), steel, 6)


static func coat_stand(b: MeshKit.Builder, t: Transform3D) -> void:
	_cyl(b, t, Vector3(0, 0.03, 0), 0.22, 0.25, 0.06, WOOD_D, 10)
	_cyl(b, t, Vector3(0, 0.95, 0), 0.03, 0.035, 1.8, WOOD_M, 8)
	for i in 4:
		var a := i * TAU / 4.0
		b.tube(t * Vector3(0, 1.75, 0), t * Vector3(cos(a) * 0.2, 1.85, sin(a) * 0.2), 0.015, 0.015, WOOD_M, 6)
	_rbox(b, t, Vector3(0.12, 1.3, 0.05), Vector3(0.38, 0.9, 0.2), 0.08, Color(0.45, 0.28, 0.5))
	b.cylinder(0.12, 0.14, 0.12, t * MeshKit.at(Vector3(-0.12, 1.9, 0)), Color(0.2, 0.2, 0.25), 10)
	b.cylinder(0.2, 0.2, 0.02, t * MeshKit.at(Vector3(-0.12, 1.84, 0)), Color(0.2, 0.2, 0.25), 12)
	_cyl(b, t, Vector3(0.25, 0.3, 0.2), 0.1, 0.09, 0.55, Color(0.3, 0.3, 0.35), 10)
	b.tube(t * Vector3(0.27, 0.3, 0.2), t * Vector3(0.3, 0.9, 0.22), 0.015, 0.015, Color(0.15, 0.2, 0.5), 6)


static func globe(b: MeshKit.Builder, t: Transform3D) -> void:
	_cyl(b, t, Vector3(0, 0.03, 0), 0.25, 0.28, 0.06, WOOD_D, 10)
	_cyl(b, t, Vector3(0, 0.35, 0), 0.04, 0.05, 0.6, WOOD_M, 8)
	b.torus(0.32, 0.015, t * MeshKit.at(Vector3(0, 0.95, 0), Vector3.ONE, Vector3(PI * 0.5, 0.4, 0)), BRASS, 16)
	_sph(b, t, Vector3(0, 0.95, 0), 0.3, Color(0.3, 0.55, 0.85), 16)
	for i in 5:
		b.ellipsoid(Vector3(0.1, 0.08, 0.05), t * MeshKit.at(Vector3(cos(i * 1.3) * 0.25, 0.95 + sin(i * 2.1) * 0.15, sin(i * 1.3) * 0.25)), Color(0.35, 0.7, 0.35), 8)


static func easel(b: MeshKit.Builder, t: Transform3D) -> void:
	b.tube(t * Vector3(-0.3, 0, 0.15), t * Vector3(-0.05, 1.8, 0), 0.025, 0.02, WOOD_L, 6)
	b.tube(t * Vector3(0.3, 0, 0.15), t * Vector3(0.05, 1.8, 0), 0.025, 0.02, WOOD_L, 6)
	b.tube(t * Vector3(0, 0, -0.4), t * Vector3(0, 1.7, 0), 0.025, 0.02, WOOD_L, 6)
	_box(b, t, Vector3(0, 0.75, 0.12), Vector3(0.75, 0.04, 0.08), WOOD_L)
	# the EMPTY frame (the painting is gone!)
	var gold := Color(0.92, 0.72, 0.3)
	_box(b, t, Vector3(0, 1.35, 0.12), Vector3(0.8, 0.08, 0.05), gold)
	_box(b, t, Vector3(0, 0.82, 0.12), Vector3(0.8, 0.08, 0.05), gold)
	_box(b, t, Vector3(-0.36, 1.08, 0.12), Vector3(0.08, 0.6, 0.05), gold)
	_box(b, t, Vector3(0.36, 1.08, 0.12), Vector3(0.08, 0.6, 0.05), gold)


static func pedestal(b: MeshKit.Builder, t: Transform3D, h: float = 0.95, col: Color = Color(0.88, 0.86, 0.82)) -> void:
	_box(b, t, Vector3(0, 0.05, 0), Vector3(0.55, 0.1, 0.55), col.darkened(0.1))
	_cyl(b, t, Vector3(0, h * 0.5, 0), 0.17, 0.2, h - 0.15, col, 12)
	_box(b, t, Vector3(0, h - 0.04, 0), Vector3(0.5, 0.08, 0.5), col.darkened(0.1))
	_rbox(b, t, Vector3(0, h + 0.04, 0), Vector3(0.36, 0.08, 0.36), 0.03, Color(0.6, 0.12, 0.2))


static func birdcage(b: MeshKit.Builder, t: Transform3D) -> void:
	pedestal(b, t, 0.9, WOOD_L)
	var gold := Color(0.95, 0.78, 0.35)
	_cyl(b, t, Vector3(0, 0.98, 0), 0.26, 0.26, 0.04, gold, 14)
	for i in 12:
		var a := i * TAU / 12.0
		b.tube(t * Vector3(cos(a) * 0.25, 0.98, sin(a) * 0.25), t * Vector3(cos(a) * 0.25, 1.45, sin(a) * 0.25), 0.008, 0.008, gold, 4)
	b.dome(0.26, t * MeshKit.at(Vector3(0, 1.45, 0), Vector3(1, 0.6, 1)), gold, 12)
	b.torus(0.06, 0.012, t * MeshKit.at(Vector3(0, 1.66, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), gold, 10)
	b.tube(t * Vector3(-0.2, 1.2, 0), t * Vector3(0.2, 1.2, 0), 0.01, 0.01, WOOD_M, 4)
	# the little door hangs OPEN
	_box(b, t, Vector3(0.3, 1.15, 0.12), Vector3(0.02, 0.22, 0.18), gold)


static func trunk(b: MeshKit.Builder, t: Transform3D, size: Vector3, col: Color) -> void:
	_rbox(b, t, Vector3(0, size.y * 0.4, 0), Vector3(size.x, size.y * 0.8, size.z), 0.04, col)
	b.cylinder(size.z * 0.5, size.z * 0.5, size.x, t * MeshKit.at(Vector3(0, size.y * 0.8, 0), Vector3(0.45, 1, 1), Vector3(0, 0, PI * 0.5)), col.lightened(0.08), 12)
	for x in [-0.32, 0.32]:
		var fx: float = x
		_box(b, t, Vector3(fx * size.x, size.y * 0.5, 0), Vector3(0.06, size.y * 0.95, size.z + 0.02), BRASS)
	_box(b, t, Vector3(0, size.y * 0.7, size.z * 0.5 + 0.01), Vector3(0.1, 0.12, 0.03), BRASS)


static func wardrobe(b: MeshKit.Builder, t: Transform3D, size: Vector3) -> void:
	_rbox(b, t, Vector3(0, size.y * 0.5, 0), size, 0.04, WOOD_M)
	_box(b, t, Vector3(0, size.y + 0.04, 0), Vector3(size.x + 0.1, 0.08, size.z + 0.08), WOOD_D)
	for sx in [-1.0, 1.0]:
		var fx: float = sx
		_box(b, t, Vector3(fx * size.x * 0.25, size.y * 0.55, size.z * 0.5 + 0.01), Vector3(size.x * 0.46, size.y * 0.78, 0.02), WOOD_L)
		_sph(b, t, Vector3(fx * 0.06, size.y * 0.55, size.z * 0.5 + 0.03), 0.03, BRASS, 6)
	_box(b, t, Vector3(0, size.y * 0.08, size.z * 0.5 + 0.01), Vector3(size.x - 0.1, size.y * 0.1, 0.02), WOOD_D)


static func jar_shelf(b: MeshKit.Builder, t: Transform3D, size: Vector3) -> void:
	_box(b, t, Vector3(-size.x * 0.48, size.y * 0.5, 0), Vector3(0.05, size.y, size.z), WOOD_M)
	_box(b, t, Vector3(size.x * 0.48, size.y * 0.5, 0), Vector3(0.05, size.y, size.z), WOOD_M)
	var jams: Array[Color] = [Color(0.85, 0.15, 0.2), Color(0.95, 0.6, 0.15), Color(0.5, 0.2, 0.55), Color(0.4, 0.7, 0.25), Color(0.95, 0.85, 0.3)]
	for k in 4:
		var y := 0.1 + k * size.y / 4.2
		_box(b, t, Vector3(0, y, 0), Vector3(size.x, 0.04, size.z), WOOD_M)
		var x := -size.x * 0.42
		while x < size.x * 0.42:
			var c: Color = jams[_rng.randi() % jams.size()]
			_cyl(b, t, Vector3(x, y + 0.11, 0.0), 0.06, 0.065, 0.18, c, 8)
			_cyl(b, t, Vector3(x, y + 0.21, 0.0), 0.062, 0.062, 0.03, Color(0.95, 0.95, 0.95) if _rng.randf() < 0.5 else Color(0.85, 0.3, 0.3), 8)
			x += 0.16


static func stove(b: MeshKit.Builder, t: Transform3D) -> void:
	var enamel := Color(0.2, 0.35, 0.45)
	_rbox(b, t, Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 0.6), 0.04, enamel)
	_box(b, t, Vector3(0, 0.4, 0.305), Vector3(0.7, 0.5, 0.02), Color(0.12, 0.12, 0.14))
	_box(b, t, Vector3(0, 0.4, 0.315), Vector3(0.45, 0.25, 0.01), Color(1.0, 0.55, 0.2), true)
	_box(b, t, Vector3(0, 0.7, 0.33), Vector3(0.6, 0.03, 0.04), Color(0.85, 0.85, 0.88))
	for x in [-0.25, 0.25]:
		var fx: float = x
		b.torus(0.1, 0.02, t * MeshKit.at(Vector3(fx, 0.91, -0.05)), IRON, 10)
	_cyl(b, t, Vector3(0.25, 1.0, -0.05), 0.12, 0.13, 0.16, Color(0.75, 0.3, 0.25), 12)
	_cyl(b, t, Vector3(-0.25, 1.02, -0.05), 0.1, 0.12, 0.2, Color(0.8, 0.8, 0.82), 12)
	_box(b, t, Vector3(0, 1.75, -0.2), Vector3(0.8, 0.5, 0.25), Color(0.75, 0.75, 0.78))


static func counter(b: MeshKit.Builder, t: Transform3D, size: Vector3, sink_x: float = 999.0) -> void:
	_box(b, t, Vector3(0, size.y * 0.5 - 0.03, 0), Vector3(size.x, size.y - 0.06, size.z - 0.04), Color(0.55, 0.75, 0.68))
	_box(b, t, Vector3(0, size.y - 0.02, 0), Vector3(size.x + 0.04, 0.05, size.z), WOOD_L)
	var n := int(size.x / 0.6)
	for i in n:
		var x := -size.x * 0.5 + (float(i) + 0.5) * size.x / float(n)
		_box(b, t, Vector3(x, size.y * 0.45, size.z * 0.5 - 0.01), Vector3(size.x / float(n) - 0.06, size.y * 0.7, 0.02), Color(0.62, 0.82, 0.75))
		_sph(b, t, Vector3(x, size.y * 0.7, size.z * 0.5 + 0.01), 0.02, BRASS, 6)
	if sink_x < 100.0:
		_box(b, t, Vector3(sink_x, size.y + 0.0, 0), Vector3(0.55, 0.04, 0.4), Color(0.85, 0.88, 0.9))
		b.tube(t * Vector3(sink_x, size.y, -0.22), t * Vector3(sink_x, size.y + 0.3, -0.22), 0.015, 0.015, Color(0.8, 0.8, 0.85), 6)
		b.tube(t * Vector3(sink_x, size.y + 0.3, -0.22), t * Vector3(sink_x, size.y + 0.3, -0.05), 0.015, 0.015, Color(0.8, 0.8, 0.85), 6)


static func sack(b: MeshKit.Builder, t: Transform3D, c: Vector3, s: float) -> void:
	b.ellipsoid(Vector3(0.25, 0.3, 0.2) * s, t * MeshKit.at(c + Vector3(0, 0.28 * s, 0)), Color(0.88, 0.8, 0.62), 10)
	b.cone(0.1 * s, 0.12 * s, t * MeshKit.at(c + Vector3(0, 0.62 * s, 0)), Color(0.85, 0.76, 0.58), 6)


static func painting(b: MeshKit.Builder, pos: Vector3, normal: Vector3, pic: int, w: float = 1.0, h: float = 0.8) -> void:
	var basis := Basis.looking_at(-normal, Vector3.UP)  # -Z towards the wall, +Z out of it
	var t := Transform3D(basis, pos)
	var gold := Color(0.92, 0.72, 0.3)
	_box(b, t, Vector3(0, 0, -0.01), Vector3(w + 0.16, h + 0.16, 0.05), gold)
	_box(b, t, Vector3(0, 0, 0.01), Vector3(w, h, 0.02), Color(0.2, 0.25, 0.3))
	var z := 0.025
	match pic:
		0:  # a portrait: a round face with a big moustache
			_box(b, t, Vector3(0, 0, z), Vector3(w, h, 0.005), Color(0.35, 0.2, 0.3))
			b.ellipsoid(Vector3(0.18, 0.22, 0.01), t * MeshKit.at(Vector3(0, 0.06, z + 0.005)), Color(1.0, 0.82, 0.68), 12)
			b.ellipsoid(Vector3(0.12, 0.03, 0.01), t * MeshKit.at(Vector3(0, -0.02, z + 0.01)), Color(0.4, 0.25, 0.15), 8)
			_box(b, t, Vector3(0, -0.3, z + 0.005), Vector3(0.5, 0.25, 0.005), Color(0.15, 0.15, 0.3))
			_box(b, t, Vector3(0, 0.28, z + 0.008), Vector3(0.3, 0.06, 0.005), Color(0.15, 0.12, 0.1))
		1:  # a ship on waves
			_box(b, t, Vector3(0, 0.1, z), Vector3(w, h * 0.75, 0.005), Color(0.35, 0.45, 0.6))
			_box(b, t, Vector3(0, -h * 0.35, z), Vector3(w, h * 0.3, 0.005), Color(0.15, 0.3, 0.5))
			_box(b, t, Vector3(0, -0.12, z + 0.01), Vector3(0.4, 0.1, 0.005), Color(0.45, 0.28, 0.15))
			b.polygon(PackedVector2Array([Vector2(0, 0), Vector2(0.18, 0), Vector2(0, 0.3)]), 0.005, t * MeshKit.at(Vector3(-0.02, -0.07, z + 0.012)), CREAM)
		2:  # dancing cats
			_box(b, t, Vector3(0, 0, z), Vector3(w, h, 0.005), Color(0.95, 0.75, 0.55))
			for i in 3:
				var x := -0.3 + i * 0.3
				b.ellipsoid(Vector3(0.08, 0.12, 0.01), t * MeshKit.at(Vector3(x, -0.08, z + 0.006)), Color(0.2, 0.2, 0.25), 8)
				_sph(b, t, Vector3(x, 0.08, z + 0.008), 0.06, Color(0.2, 0.2, 0.25), 8)
				b.cone(0.025, 0.05, t * MeshKit.at(Vector3(x - 0.035, 0.15, z + 0.008)), Color(0.2, 0.2, 0.25), 4)
				b.cone(0.025, 0.05, t * MeshKit.at(Vector3(x + 0.035, 0.15, z + 0.008)), Color(0.2, 0.2, 0.25), 4)
		3:  # mountains at sunset
			_box(b, t, Vector3(0, 0, z), Vector3(w, h, 0.005), Color(0.95, 0.55, 0.4))
			_sph(b, t, Vector3(0.2, 0.1, z + 0.004), 0.1, Color(1.0, 0.85, 0.4), 10)
			b.polygon(PackedVector2Array([Vector2(-0.5, -0.4), Vector2(-0.1, 0.15), Vector2(0.2, -0.4)]), 0.005, t * MeshKit.at(Vector3(0, 0, z + 0.008)), Color(0.35, 0.3, 0.45))
			b.polygon(PackedVector2Array([Vector2(-0.1, -0.4), Vector2(0.25, 0.05), Vector2(0.5, -0.4)]), 0.005, t * MeshKit.at(Vector3(0, 0, z + 0.01)), Color(0.45, 0.35, 0.5))
		4:  # fruit bowl
			_box(b, t, Vector3(0, 0, z), Vector3(w, h, 0.005), Color(0.3, 0.4, 0.3))
			b.dome(0.2, t * MeshKit.at(Vector3(0, -0.15, z + 0.005), Vector3(1, -0.6, 0.05)), Color(0.85, 0.85, 0.9), 10)
			_sph(b, t, Vector3(-0.1, -0.1, z + 0.01), 0.07, Color(0.9, 0.2, 0.2), 8)
			_sph(b, t, Vector3(0.05, -0.08, z + 0.012), 0.07, Color(0.95, 0.65, 0.15), 8)
			_sph(b, t, Vector3(0.12, -0.11, z + 0.01), 0.05, Color(0.5, 0.2, 0.5), 8)
		_:  # a prize carrot
			_box(b, t, Vector3(0, 0, z), Vector3(w, h, 0.005), Color(0.6, 0.8, 0.9))
			b.cone(0.07, 0.4, t * MeshKit.at(Vector3(0, -0.05, z + 0.01), Vector3(1, 1, 0.1), Vector3(0, 0, PI)), Color(1.0, 0.55, 0.15), 8)
			b.ellipsoid(Vector3(0.05, 0.1, 0.01), t * MeshKit.at(Vector3(0, 0.22, z + 0.01)), LEAF, 6)
			b.star(5, 0.08, 0.035, 0.005, t * MeshKit.at(Vector3(0.28, 0.22, z + 0.01)), Color(1.0, 0.82, 0.3))


static func rug(b: MeshKit.Builder, t: Transform3D, size: Vector2, col: Color, edge: Color) -> void:
	_box(b, t, Vector3(0, 0.006, 0), Vector3(size.x, 0.012, size.y), edge)
	_box(b, t, Vector3(0, 0.013, 0), Vector3(size.x - 0.3, 0.012, size.y - 0.3), col)
	_box(b, t, Vector3(0, 0.02, 0), Vector3(size.x * 0.4, 0.004, size.y * 0.4), edge.lightened(0.2))


static func chandelier(b: MeshKit.Builder, t: Transform3D) -> void:
	b.tube(t * Vector3(0, 0.0, 0), t * Vector3(0, 0.6, 0), 0.015, 0.015, BRASS, 6)
	b.torus(0.55, 0.03, t * MeshKit.at(Vector3(0, 0, 0)), BRASS, 18)
	b.torus(0.3, 0.025, t * MeshKit.at(Vector3(0, -0.15, 0)), BRASS, 14)
	for i in 8:
		var a := i * TAU / 8.0
		var p := Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55)
		_cyl(b, t, p + Vector3(0, 0.08, 0), 0.02, 0.02, 0.14, CREAM, 6)
		b.sphere(0.03, t * MeshKit.at(p + Vector3(0, 0.2, 0), Vector3(1, 1.6, 1)), Color(1.0, 0.85, 0.45), 6, true)
	b.sphere(0.12, t * MeshKit.at(Vector3(0, -0.3, 0), Vector3(1, 1.4, 1)), Color(0.9, 0.95, 1.0), 10, true)


static func hedge(m: Node3D, r: int, a: Vector2, bb: Vector2, h: float = 2.0) -> void:
	var b: MeshKit.Builder = m.fb(r)
	var c := (a + bb) * 0.5
	var size := Vector3(absf(bb.x - a.x), h, absf(bb.y - a.y))
	var t := Transform3D(Basis(), Vector3(c.x, 0, c.y))
	_rbox(b, t, Vector3(0, h * 0.5, 0), size, 0.25, Color(0.16, 0.38, 0.18))
	# leafy bumps on top
	var n := int(maxf(size.x, size.z) / 0.9)
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		var p := Vector3(lerpf(-size.x * 0.5, size.x * 0.5, f) if size.x > size.z else 0.0, h, lerpf(-size.z * 0.5, size.z * 0.5, f) if size.z >= size.x else 0.0)
		_sph(b, t, p, 0.4, Color(0.2, 0.45, 0.2).lightened(_rng.randf() * 0.1), 8)
	m.solid(0, Vector3(c.x, h * 0.5, c.y), size)


static func board_frame(b: MeshKit.Builder, t: Transform3D, size: Vector2) -> void:
	# the case board: cork on a dark wooden frame, a brass plaque at the top
	_box(b, t, Vector3(0, 0, -0.02), Vector3(size.x + 0.2, size.y + 0.2, 0.05), WOOD_D)
	_box(b, t, Vector3(0, 0, 0.0), Vector3(size.x, size.y, 0.03), Color(0.72, 0.52, 0.34))
	_box(b, t, Vector3(0, size.y * 0.5 + 0.18, 0.0), Vector3(1.4, 0.2, 0.04), BRASS)


# --- Rooms --------------------------------------------------------------------------------------

static func _hall(m: Node3D) -> void:
	var r := 0
	var b: MeshKit.Builder = m.fb(r)
	# staircase up (north-west corner): steps rising to a little door near the ceiling
	var st := _t(r, Vector3(-3.45, 0, -3.2))
	for i in 14:
		var y := 0.11 + i * 0.22
		_box(b, st, Vector3(0, y * 0.5, -0.06 - i * 0.12), Vector3(2.7, y, 0.14), WOOD_M.lightened(0.05 if i % 2 == 0 else 0.0))
		_box(b, st, Vector3(0, y + 0.01, -0.06 - i * 0.12), Vector3(1.6, 0.02, 0.14), Color(0.6, 0.12, 0.18))
	b.tube(st * Vector3(1.35, 1.0, 0.0), st * Vector3(1.35, 3.6, -1.6), 0.04, 0.04, WOOD_D, 6)
	for i in 6:
		var f := float(i) / 5.0
		b.tube(st * Vector3(1.35, f * 2.6 + 0.05, -f * 1.6), st * Vector3(1.35, f * 2.6 + 1.0, -f * 1.6), 0.02, 0.02, WOOD_L, 5)
	_box(b, st, Vector3(0, 2.9, -1.68), Vector3(1.1, 1.0, 0.04), Color(0.05, 0.04, 0.06))
	m.solid(0, Vector3(-3.45, 1.7, -4.05), Vector3(2.9, 3.4, 1.7))
	# cellar door (north-east): a little doorway with steps going down into darkness
	var cd := _t(r, Vector3(3.45, 0, -4.82))
	_box(b, cd, Vector3(0, 1.1, 0), Vector3(1.3, 2.2, 0.06), Color(0.04, 0.03, 0.05))
	_box(b, cd, Vector3(-0.72, 1.15, 0.05), Vector3(0.14, 2.3, 0.12), WOOD_D)
	_box(b, cd, Vector3(0.72, 1.15, 0.05), Vector3(0.14, 2.3, 0.12), WOOD_D)
	_box(b, cd, Vector3(0, 2.3, 0.05), Vector3(1.58, 0.16, 0.12), WOOD_D)
	for i in 3:
		_box(b, cd, Vector3(0, 0.25 - i * 0.12, 0.05 - i * 0.05), Vector3(1.2, 0.04, 0.2), WOOD_M.darkened(0.2 * i))
	# the door leaf swung open against the wall
	b.box(Vector3(1.2, 2.1, 0.06), cd * MeshKit.at(Vector3(-1.25, 1.07, 0.55), Vector3.ONE, Vector3(0, -1.35, 0)), WOOD_M)
	m.solid(0, Vector3(3.45, 1.2, -4.9), Vector3(1.9, 2.4, 0.2))
	# the case board on the west wall + the detective's evidence table
	board_frame(b, _t(r, Vector3(-4.87, 1.75, 1.0), PI * 0.5), Vector2(3.2, 1.8))
	table(b, _t(r, Vector3(-3.75, 0, 1.0), PI * 0.5), Vector3(2.0, 0.85, 0.9), WOOD_M, Color(0.15, 0.32, 0.22))
	_solid(m, r, Vector3(-3.75, 0, 1.0), Vector3(2.0, 0.85, 0.9), PI * 0.5)
	# fireplace + portrait above it
	fireplace(b, _t(r, Vector3(4.62, 0, 0.75), -PI * 0.5), Vector3(2.2, 1.3, 0.55))
	_solid(m, r, Vector3(4.62, 0, 0.75), Vector3(2.2, 1.3, 0.55), -PI * 0.5)
	painting(b, Vector3(4.86, 2.35, 0.75), Vector3(-1, 0, 0), 0, 1.0, 0.9)
	# grandfather clock, coat stand, suits of armour, hall table
	clock(b, _t(r, Vector3(-4.5, 0, 6.45), PI * 0.5))
	_solid(m, r, Vector3(-4.5, 0, 6.45), Vector3(0.6, 2.4, 0.5), PI * 0.5)
	coat_stand(b, _t(r, Vector3(4.4, 0, 6.4), -PI * 0.5))
	_solid(m, r, Vector3(4.4, 0, 6.4), Vector3(0.5, 1.9, 0.5))
	armour(b, _t(r, Vector3(-1.6, 0, 6.5), PI))
	_solid(m, r, Vector3(-1.6, 0, 6.5), Vector3(0.6, 1.9, 0.5))
	armour(b, _t(r, Vector3(1.6, 0, 6.5), PI))
	_solid(m, r, Vector3(1.6, 0, 6.5), Vector3(0.6, 1.9, 0.5))
	table(b, _t(r, Vector3(3.3, 0, 6.55), PI), Vector3(1.0, 0.82, 0.5), WOOD_M)
	_solid(m, r, Vector3(3.3, 0, 6.55), Vector3(1.0, 0.82, 0.5))
	candelabra(b, _t(r, Vector3(3.6, 0.82, 6.6)))
	# the (locked) front door
	var fd := _t(r, Vector3(0, 0, 6.88), PI)
	_box(b, fd, Vector3(0, 1.3, 0), Vector3(1.9, 2.6, 0.1), WOOD_D)
	_box(b, fd, Vector3(-0.47, 1.25, 0.06), Vector3(0.85, 2.4, 0.04), WOOD_M)
	_box(b, fd, Vector3(0.47, 1.25, 0.06), Vector3(0.85, 2.4, 0.04), WOOD_M)
	_sph(b, fd, Vector3(-0.12, 1.2, 0.1), 0.05, BRASS, 8)
	_sph(b, fd, Vector3(0.12, 1.2, 0.1), 0.05, BRASS, 8)
	b.dome(0.5, fd * MeshKit.at(Vector3(0, 2.6, 0.05), Vector3(1.6, 1.0, 0.1)), Color(1.0, 0.8, 0.45), 12, true)
	# rug, plants, chandelier, wall sconces
	rug(b, _t(r, Vector3(0.3, 0, 1.6)), Vector2(4.6, 6.4), Color(0.55, 0.12, 0.18), Color(0.85, 0.65, 0.3))
	plant(b, _t(r, Vector3(-4.45, 0, 3.4)))
	_solid(m, r, Vector3(-4.45, 0, 3.4), Vector3(0.5, 1.0, 0.5))
	plant(b, _t(r, Vector3(4.45, 0, 2.45)), Color(0.3, 0.45, 0.7))
	_solid(m, r, Vector3(4.45, 0, 2.45), Vector3(0.5, 1.0, 0.5))
	chandelier(b, _t(r, Vector3(0.3, 2.75, 1.6)))
	for z in [-3.5, 5.5]:
		var fz: float = z
		b.sphere(0.07, MeshKit.at(Vector3(4.85, 2.2, fz), Vector3(0.6, 1.3, 1)), Color(1.0, 0.8, 0.45), 8, true)
		b.sphere(0.07, MeshKit.at(Vector3(-4.85, 2.2, fz + 0.5), Vector3(0.6, 1.3, 1)), Color(1.0, 0.8, 0.45), 8, true)


static func _library(m: Node3D) -> void:
	var r := 1
	var b: MeshKit.Builder = m.fb(r)
	for x in [-13.4, -10.6]:
		var fx: float = x
		bookshelf(b, _t(r, Vector3(fx, 0, -12.77)), Vector3(2.4, 2.7, 0.45))
		_solid(m, r, Vector3(fx, 0, -12.77), Vector3(2.4, 2.7, 0.45))
	# a rolling ladder
	b.tube(Vector3(-11.5, 0, -12.1), Vector3(-11.7, 2.6, -12.5), 0.03, 0.03, WOOD_L, 6)
	b.tube(Vector3(-11.0, 0, -12.1), Vector3(-11.2, 2.6, -12.5), 0.03, 0.03, WOOD_L, 6)
	for i in 7:
		var f := float(i + 1) / 8.0
		b.tube(Vector3(-11.5 - f * 0.2, f * 2.6, -12.1 - f * 0.4), Vector3(-11.0 - f * 0.2, f * 2.6, -12.1 - f * 0.4), 0.02, 0.02, WOOD_L, 4)
	globe(b, _t(r, Vector3(-6.2, 0, -12.3)))
	_solid(m, r, Vector3(-6.2, 0, -12.3), Vector3(0.7, 1.3, 0.7))
	desk(b, _t(r, Vector3(-12.6, 0, -9.0), PI * 0.5), Vector3(1.6, 0.8, 0.9))
	_solid(m, r, Vector3(-12.6, 0, -9.0), Vector3(1.6, 0.8, 0.9), PI * 0.5)
	chair(b, _t(r, Vector3(-13.6, 0, -9.0), PI * 0.5))
	armchair(b, _t(r, Vector3(-13.9, 0, -6.2), PI * 0.5), Color(0.25, 0.45, 0.3))
	_solid(m, r, Vector3(-13.9, 0, -6.2), Vector3(0.9, 1.0, 0.9))
	table(b, _t(r, Vector3(-7.5, 0, -5.6)), Vector3(0.6, 0.64, 0.6), WOOD_M)
	_solid(m, r, Vector3(-7.5, 0, -5.6), Vector3(0.6, 0.64, 0.6))
	lamp(b, _t(r, Vector3(-5.6, 0, -5.6)))
	_solid(m, r, Vector3(-5.6, 0, -5.6), Vector3(0.4, 1.8, 0.4))
	rug(b, _t(r, Vector3(-9.6, 0, -8.8)), Vector2(4.2, 3.0), Color(0.2, 0.3, 0.55), Color(0.85, 0.7, 0.4))
	painting(b, Vector3(-14.86, 2.0, -9.3), Vector3(1, 0, 0), 1)
	# piles of books on the floor
	for i in 4:
		_box(b, _t(r, Vector3(-14.4, 0, -11.7)), Vector3(0, 0.05 + i * 0.09, 0), Vector3(0.4, 0.09, 0.3), BOOK_COLS[i])
	_solid(m, r, Vector3(-14.4, 0, -11.7), Vector3(0.45, 0.4, 0.35))


static func _music(m: Node3D) -> void:
	var r := 2
	var b: MeshKit.Builder = m.fb(r)
	piano(b, _t(r, Vector3(-2.4, 0, -11.2)))
	m.solid(0, Vector3(-2.4, 0.6, -11.3), Vector3(1.6, 1.2, 2.0))
	harp(b, _t(r, Vector3(3.6, 0, -12.2), -0.5))
	_solid(m, r, Vector3(3.6, 0, -12.2), Vector3(0.7, 1.8, 0.7))
	# cello case leaning on the wall
	b.ellipsoid(Vector3(0.28, 0.65, 0.16), _t(r, Vector3(4.55, 0.65, -11.0), -PI * 0.5) * MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.12, 0, 0)), Color(0.15, 0.25, 0.4), 12)
	_solid(m, r, Vector3(4.55, 0, -11.0), Vector3(0.45, 1.4, 0.6))
	cabinet(b, _t(r, Vector3(4.62, 0, -6.0), -PI * 0.5), Vector3(1.2, 1.5, 0.5), WOOD_M)
	_solid(m, r, Vector3(4.62, 0, -6.0), Vector3(1.2, 1.5, 0.5), -PI * 0.5)
	sofa(b, _t(r, Vector3(-3.6, 0, -5.55), PI), Vector3(2.2, 0.9, 0.8), Color(0.5, 0.2, 0.45))
	_solid(m, r, Vector3(-3.6, 0, -5.55), Vector3(2.2, 0.9, 0.8))
	table(b, _t(r, Vector3(2.45, 0, -5.5)), Vector3(0.6, 0.74, 0.6), WOOD_D)
	_solid(m, r, Vector3(2.45, 0, -5.5), Vector3(0.6, 0.74, 0.6))
	# gramophone horn
	var g := _t(r, Vector3(2.75, 0.74, -5.5))
	_box(b, g, Vector3(0, 0.06, 0), Vector3(0.22, 0.12, 0.22), WOOD_L)
	b.cone(0.16, 0.35, g * MeshKit.at(Vector3(0.0, 0.35, -0.05), Vector3.ONE, Vector3(-0.6, 0, 0)), BRASS, 12)
	# music stands and chairs
	for i in 3:
		var p := Vector3(0.4 + i * 1.1, 0, -7.4)
		b.tube(_t(r, p) * Vector3(0, 0, 0), _t(r, p) * Vector3(0, 1.1, 0), 0.015, 0.015, IRON, 6)
		b.box(Vector3(0.4, 0.3, 0.02), _t(r, p) * MeshKit.at(Vector3(0, 1.2, 0), Vector3.ONE, Vector3(-0.3, 0, 0)), CREAM)
	rug(b, _t(r, Vector3(0, 0, -9.0)), Vector2(5.0, 3.2), Color(0.25, 0.25, 0.55), Color(0.9, 0.75, 0.35))
	painting(b, Vector3(0.0, 2.1, -12.86), Vector3(0, 0, 1), 2)
	lamp(b, _t(r, Vector3(-4.5, 0, -12.5)), Color(0.75, 0.85, 1.0))
	_solid(m, r, Vector3(-4.5, 0, -12.5), Vector3(0.4, 1.8, 0.4))


static func _conservatory(m: Node3D) -> void:
	var r := 3
	var b: MeshKit.Builder = m.fb(r)
	# potting bench with seed trays and pots
	var pb := _t(r, Vector3(6.9, 0, -12.6))
	table(b, pb, Vector3(2.0, 0.85, 0.7), WOOD_L)
	for i in 4:
		_cyl(b, pb, Vector3(-0.7 + i * 0.45, 0.95, 0.0), 0.12, 0.09, 0.2, Color(0.78, 0.42, 0.28), 8)
		_sph(b, pb, Vector3(-0.7 + i * 0.45, 1.1, 0.0), 0.1, LEAF.lightened(0.1 * i), 8)
	_solid(m, r, Vector3(6.9, 0, -12.6), Vector3(2.0, 0.9, 0.7))
	# giant plant pot with a palm
	_cyl(b, _t(r, Vector3(13.9, 0, -12.0)), Vector3(0, 0.35, 0), 0.45, 0.35, 0.7, Color(0.75, 0.45, 0.3), 12)
	b.add_mesh(MeshKit.prop("palm"), _t(r, Vector3(13.9, 0.65, -12.0)) * MeshKit.at(Vector3.ZERO, Vector3.ONE * 0.55))
	_solid(m, r, Vector3(13.9, 0, -12.0), Vector3(0.9, 1.2, 0.9))
	# wicker basket of balls of wool
	_cyl(b, _t(r, Vector3(6.0, 0, -5.6)), Vector3(0, 0.2, 0), 0.32, 0.26, 0.4, Color(0.8, 0.62, 0.35), 12)
	for i in 3:
		_sph(b, _t(r, Vector3(6.0, 0, -5.6)), Vector3(-0.1 + i * 0.1, 0.42, 0.05 * i), 0.1, [Color(0.9, 0.3, 0.4), Color(0.3, 0.6, 0.9), Color(0.95, 0.85, 0.3)][i], 8)
	_solid(m, r, Vector3(6.0, 0, -5.6), Vector3(0.65, 0.5, 0.65))
	# wicker table and chairs
	var wt := _t(r, Vector3(12.3, 0, -9.0))
	_cyl(b, wt, Vector3(0, 0.3, 0), 0.08, 0.2, 0.6, Color(0.8, 0.62, 0.35), 10)
	_cyl(b, wt, Vector3(0, 0.61, 0), 0.38, 0.38, 0.03, Color(0.85, 0.7, 0.45), 14)
	_solid(m, r, Vector3(12.3, 0, -9.0), Vector3(0.75, 0.62, 0.75))
	for sx in [-1.0, 1.0]:
		var fx: float = sx
		armchair(b, _t(r, Vector3(12.3 + fx * 0.95, 0, -9.0), -fx * PI * 0.5) * MeshKit.at(Vector3.ZERO, Vector3.ONE * 0.8), Color(0.82, 0.65, 0.4))
		_solid(m, r, Vector3(12.3 + fx * 0.95, 0, -9.0), Vector3(0.7, 0.8, 0.7))
	# flower bed along the glass
	var fb := _t(r, Vector3(14.5, 0, -9.0))
	_box(b, fb, Vector3(0, 0.25, 0), Vector3(0.8, 0.5, 3.6), Color(0.6, 0.35, 0.25))
	_box(b, fb, Vector3(0, 0.5, 0), Vector3(0.7, 0.04, 3.5), Color(0.3, 0.2, 0.12))
	for i in 9:
		var z := -1.6 + i * 0.4
		b.add_mesh(MeshKit.prop("flower", i % 3), fb * MeshKit.at(Vector3(0.0, 0.5, z), Vector3.ONE * 1.6))
	_solid(m, r, Vector3(14.5, 0, -9.0), Vector3(0.8, 0.5, 3.6))
	plant(b, _t(r, Vector3(5.8, 0, -11.4)), Color(0.75, 0.45, 0.3), 1.3)
	_solid(m, r, Vector3(5.8, 0, -11.4), Vector3(0.6, 1.2, 0.6))
	plant(b, _t(r, Vector3(14.3, 0, -5.7)), Color(0.4, 0.55, 0.75), 1.2)
	_solid(m, r, Vector3(14.3, 0, -5.7), Vector3(0.6, 1.2, 0.6))
	# hanging pots
	for x in [7.5, 12.5]:
		var fx: float = x
		b.tube(Vector3(fx, 3.4, -8.0), Vector3(fx, 2.4, -8.0), 0.01, 0.01, IRON, 4)
		_cyl(b, Transform3D(), Vector3(fx, 2.3, -8.0), 0.18, 0.12, 0.22, Color(0.75, 0.45, 0.3), 10)
		for k in 5:
			b.capsule_between(Vector3(fx, 2.4, -8.0), Vector3(fx + cos(k * 1.3) * 0.3, 1.9, -8.0 + sin(k * 1.3) * 0.3), 0.03, LEAF, 6)


static func _study(m: Node3D) -> void:
	var r := 4
	var b: MeshKit.Builder = m.fb(r)
	desk(b, _t(r, Vector3(-12.0, 0, 0.5), PI * 0.5), Vector3(2.0, 0.8, 1.0))
	_solid(m, r, Vector3(-12.0, 0, 0.5), Vector3(2.0, 0.8, 1.0), PI * 0.5)
	armchair(b, _t(r, Vector3(-13.1, 0, 0.5), PI * 0.5) * MeshKit.at(Vector3.ZERO, Vector3.ONE * 0.85), Color(0.5, 0.25, 0.15))
	_solid(m, r, Vector3(-13.15, 0, 0.5), Vector3(0.75, 0.9, 0.75))
	cabinet(b, _t(r, Vector3(-14.5, 0, -4.3), PI * 0.5), Vector3(0.6, 1.3, 0.6), Color(0.45, 0.48, 0.42), false, true)
	_solid(m, r, Vector3(-14.5, 0, -4.3), Vector3(0.6, 1.3, 0.6))
	cabinet(b, _t(r, Vector3(-8.0, 0, 6.62), PI), Vector3(2.0, 1.6, 0.6), WOOD_D, true, false)
	_solid(m, r, Vector3(-8.0, 0, 6.62), Vector3(2.0, 1.6, 0.6))
	# trophies on top
	for i in 3:
		var tp := _t(r, Vector3(-8.6 + i * 0.6, 1.62, 6.62))
		_cyl(b, tp, Vector3(0, 0.05, 0), 0.06, 0.08, 0.1, WOOD_D, 8)
		b.cone(0.1, -0.2, tp * MeshKit.at(Vector3(0, 0.3, 0)), Color(1.0, 0.8, 0.3), 10)
	bookshelf(b, _t(r, Vector3(-14.77, 0, 3.0), PI * 0.5), Vector3(2.4, 2.6, 0.45))
	_solid(m, r, Vector3(-14.77, 0, 3.0), Vector3(2.4, 2.6, 0.45), PI * 0.5)
	armchair(b, _t(r, Vector3(-6.2, 0, 1.0), -PI * 0.5), Color(0.55, 0.15, 0.18))
	_solid(m, r, Vector3(-6.2, 0, 1.0), Vector3(0.9, 1.0, 0.9))
	table(b, _t(r, Vector3(-6.4, 0, 2.3)), Vector3(0.5, 0.6, 0.5), WOOD_M)
	_solid(m, r, Vector3(-6.4, 0, 2.3), Vector3(0.5, 0.6, 0.5))
	plant(b, _t(r, Vector3(-5.6, 0, -4.4)))
	_solid(m, r, Vector3(-5.6, 0, -4.4), Vector3(0.5, 1.0, 0.5))
	rug(b, _t(r, Vector3(-10.0, 0, 1.5)), Vector2(4.0, 5.0), Color(0.85, 0.72, 0.4), Color(0.4, 0.12, 0.12))
	painting(b, Vector3(-13.0, 2.0, -4.86), Vector3(0, 0, 1), 3)
	lamp(b, _t(r, Vector3(-14.4, 0, 6.4)))
	_solid(m, r, Vector3(-14.4, 0, 6.4), Vector3(0.4, 1.8, 0.4))


static func _dining(m: Node3D) -> void:
	var r := 5
	var b: MeshKit.Builder = m.fb(r)
	var tt := _t(r, Vector3(10.3, 0, -2.2))
	table(b, tt, Vector3(4.6, 0.8, 1.2), WOOD_D, Color(0.95, 0.94, 0.9))
	for i in 5:
		var x := -1.8 + i * 0.9
		chair(b, tt * Transform3D(Basis(Vector3.UP, 0.0), Vector3(x, 0, -0.85)))
		chair(b, tt * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, 0.85)))
		_cyl(b, tt, Vector3(x, 0.81, -0.35), 0.13, 0.13, 0.01, Color(1, 1, 1), 12)
		_cyl(b, tt, Vector3(x, 0.81, 0.35), 0.13, 0.13, 0.01, Color(1, 1, 1), 12)
	candelabra(b, tt * Transform3D(Basis(), Vector3(-0.9, 0.81, 0)))
	candelabra(b, tt * Transform3D(Basis(), Vector3(0.9, 0.81, 0)))
	_cyl(b, tt, Vector3(0, 0.9, 0), 0.18, 0.12, 0.16, Color(0.9, 0.9, 0.95), 12)
	for i in 4:
		_sph(b, tt, Vector3(-0.06 + (i % 2) * 0.12, 1.0 + (i / 2) * 0.06, 0.04 * (i - 1.5)), 0.06, [Color(0.9, 0.2, 0.2), Color(0.95, 0.7, 0.2), Color(0.4, 0.8, 0.3), Color(0.6, 0.2, 0.5)][i], 8)
	m.solid(0, Vector3(10.3, 0.5, -2.2), Vector3(4.6, 1.0, 2.1))
	cabinet(b, _t(r, Vector3(10.0, 0, -4.7)), Vector3(2.4, 0.9, 0.5), WOOD_M)
	_solid(m, r, Vector3(10.0, 0, -4.7), Vector3(2.4, 0.9, 0.5))
	cabinet(b, _t(r, Vector3(14.62, 0, -3.6), -PI * 0.5), Vector3(1.6, 2.0, 0.55), WOOD_D, true, false)
	_solid(m, r, Vector3(14.62, 0, -3.6), Vector3(1.6, 2.0, 0.55), -PI * 0.5)
	plant(b, _t(r, Vector3(5.6, 0, 0.4)))
	_solid(m, r, Vector3(5.6, 0, 0.4), Vector3(0.5, 1.0, 0.5))
	painting(b, Vector3(6.9, 2.1, -4.86), Vector3(0, 0, 1), 4)
	chandelier(b, _t(r, Vector3(10.3, 2.8, -2.2)) * MeshKit.at(Vector3.ZERO, Vector3.ONE * 0.8))


static func _kitchen(m: Node3D) -> void:
	var r := 6
	var b: MeshKit.Builder = m.fb(r)
	stove(b, _t(r, Vector3(7.0, 0, 6.62), PI))
	_solid(m, r, Vector3(7.0, 0, 6.62), Vector3(1.0, 1.0, 0.6))
	counter(b, _t(r, Vector3(10.1, 0, 6.62), PI), Vector3(5.0, 0.92, 0.6), 0.6)
	_solid(m, r, Vector3(10.1, 0, 6.62), Vector3(5.0, 0.92, 0.6))
	# icebox
	var ib := _t(r, Vector3(14.55, 0, 6.3), -PI * 0.5)
	_rbox(b, ib, Vector3(0, 0.95, 0), Vector3(1.0, 1.9, 0.75), 0.08, Color(0.9, 0.92, 0.95))
	_box(b, ib, Vector3(0, 1.3, 0.38), Vector3(0.85, 0.02, 0.02), Color(0.6, 0.65, 0.7))
	_box(b, ib, Vector3(0.38, 1.0, 0.4), Vector3(0.04, 0.3, 0.04), Color(0.7, 0.7, 0.75))
	_solid(m, r, Vector3(14.55, 0, 6.3), Vector3(1.0, 1.9, 0.75), -PI * 0.5)
	# pantry cupboard
	cabinet(b, _t(r, Vector3(14.62, 0, 3.0), -PI * 0.5), Vector3(1.6, 2.1, 0.55), Color(0.62, 0.82, 0.75), false, false)
	_solid(m, r, Vector3(14.62, 0, 3.0), Vector3(1.6, 2.1, 0.55), -PI * 0.5)
	# flour sacks
	var fs := _t(r, Vector3(5.7, 0, 1.7))
	sack(b, fs, Vector3(-0.1, 0, -0.1), 1.0)
	sack(b, fs, Vector3(0.15, 0, 0.12), 0.9)
	sack(b, fs, Vector3(0.0, 0.5, 0.0), 0.75)
	_solid(m, r, Vector3(5.7, 0, 1.7), Vector3(0.7, 0.9, 0.7))
	# kitchen table with bowls
	var kt := _t(r, Vector3(10.3, 0, 4.2))
	table(b, kt, Vector3(1.8, 0.8, 1.0), WOOD_L, Color(0.85, 0.35, 0.35))
	b.dome(0.18, kt * MeshKit.at(Vector3(-0.4, 0.98, 0), Vector3(1, -0.8, 1)), Color(0.95, 0.95, 0.9), 12)
	_cyl(b, kt, Vector3(0.45, 0.88, 0.15), 0.1, 0.12, 0.14, Color(0.4, 0.6, 0.85), 10)
	chair(b, kt * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.2, 0, 0)), WOOD_L, Color(0.85, 0.35, 0.35))
	m.solid(0, Vector3(10.3, 0.45, 4.2), Vector3(2.6, 0.9, 1.0))
	# pots and pans hanging on the wall
	for i in 5:
		var p := Vector3(6.2 + i * 0.4, 2.2, 1.12)
		b.tube(p + Vector3(0, 0.2, 0), p, 0.008, 0.008, IRON, 4)
		_cyl(b, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), Vector3(p.x, p.z + 0.05, -p.y + 0.12), 0.12 - i * 0.01, 0.12 - i * 0.01, 0.06, Color(0.75, 0.45, 0.25) if i % 2 == 0 else IRON, 12)
	painting(b, Vector3(13.0, 2.1, 1.14), Vector3(0, 0, 1), 5, 0.8, 0.7)
	_box(b, Transform3D(), Vector3(8.5, 1.6, 1.15), Vector3(2.2, 0.04, 0.3), WOOD_M)
	for i in 6:
		_cyl(b, Transform3D(), Vector3(7.6 + i * 0.36, 1.72, 1.15), 0.06, 0.06, 0.2, [Color(0.9, 0.3, 0.2), Color(0.95, 0.85, 0.3), Color(0.4, 0.7, 0.3)][i % 3], 8)


static func _garden(m: Node3D) -> void:
	var r := 7
	var b: MeshKit.Builder = m.fb(r)
	# boundary hedges (the manor's north wall closes x 0..15 at z -13)
	hedge(m, r, Vector2(-0.6, -27.4), Vector2(0.4, -13.0), 2.2)
	hedge(m, r, Vector2(19.6, -27.4), Vector2(20.6, -13.0), 2.2)
	hedge(m, r, Vector2(0.4, -27.6), Vector2(19.6, -26.6), 2.2)
	hedge(m, r, Vector2(15.0, -13.6), Vector2(19.6, -12.6), 2.2)
	# the maze
	hedge(m, r, Vector2(0.4, -16.6), Vector2(8.0, -15.8))
	hedge(m, r, Vector2(12.0, -16.6), Vector2(19.6, -15.8))
	hedge(m, r, Vector2(3.0, -19.8), Vector2(8.6, -19.0))
	hedge(m, r, Vector2(11.4, -19.8), Vector2(17.0, -19.0))
	hedge(m, r, Vector2(2.6, -23.6), Vector2(3.4, -19.8))
	hedge(m, r, Vector2(16.6, -23.6), Vector2(17.4, -19.8))
	hedge(m, r, Vector2(3.0, -24.0), Vector2(7.6, -23.2))
	hedge(m, r, Vector2(12.4, -24.0), Vector2(17.0, -23.2))
	# fountain in the middle of the court
	var ft := _t(r, Vector3(10.0, 0, -21.5))
	_cyl(b, ft, Vector3(0, 0.25, 0), 1.0, 1.05, 0.5, Color(0.75, 0.75, 0.8), 18)
	b.cylinder(0.9, 0.9, 0.02, ft * MeshKit.at(Vector3(0, 0.45, 0)), Color(0.35, 0.6, 0.95), 18, true)
	_cyl(b, ft, Vector3(0, 0.8, 0), 0.12, 0.16, 0.8, Color(0.75, 0.75, 0.8), 10)
	b.dome(0.4, ft * MeshKit.at(Vector3(0, 1.2, 0), Vector3(1, -0.5, 1)), Color(0.75, 0.75, 0.8), 12)
	b.sphere(0.12, ft * MeshKit.at(Vector3(0, 1.45, 0)), Color(0.6, 0.85, 1.0), 10, true)
	m.solid(0, Vector3(10.0, 0.4, -21.5), Vector3(2.0, 0.8, 2.0))
	# garden shed (south-west corner)
	var sh := _t(r, Vector3(1.9, 0, -25.4))
	_box(b, sh, Vector3(0, 0.9, 0), Vector3(2.0, 1.8, 1.6), Color(0.45, 0.6, 0.45))
	b.wedge(Vector3(2.2, 0.6, 0.95), sh * MeshKit.at(Vector3(0, 2.1, 0.45)), Color(0.55, 0.25, 0.2))
	b.wedge(Vector3(2.2, 0.6, 0.95), sh * MeshKit.at(Vector3(0, 2.1, -0.45), Vector3.ONE, Vector3(0, PI, 0)), Color(0.55, 0.25, 0.2))
	_box(b, sh, Vector3(0, 0.8, 0.81), Vector3(0.8, 1.5, 0.04), Color(0.35, 0.45, 0.35))
	_sph(b, sh, Vector3(0.28, 0.8, 0.85), 0.04, BRASS, 6)
	m.solid(0, Vector3(1.9, 1.2, -25.4), Vector3(2.0, 2.4, 1.6))
	# gazebo (south-east corner) with a bench
	var gz := _t(r, Vector3(17.9, 0, -25.2))
	_cyl(b, gz, Vector3(0, 0.08, 0), 1.3, 1.35, 0.16, Color(0.85, 0.85, 0.82), 8)
	for i in 6:
		var a := i * TAU / 6.0 + 0.5
		if i == 1:
			continue  # the way in
		_cyl(b, gz, Vector3(cos(a) * 1.15, 1.25, sin(a) * 1.15), 0.06, 0.06, 2.3, CREAM, 6)
	b.cone(1.6, 0.9, gz * MeshKit.at(Vector3(0, 2.8, 0)), Color(0.55, 0.3, 0.5), 8)
	_box(b, gz, Vector3(0, 0.45, -0.6), Vector3(1.4, 0.1, 0.45), WOOD_L)
	m.solid(0, Vector3(17.9, 0.4, -25.85), Vector3(1.6, 0.8, 0.6))
	b.sphere(0.12, gz * MeshKit.at(Vector3(0, 2.3, 0)), Color(1.0, 0.8, 0.45), 8, true)
	# wheelbarrow full of pumpkins
	var wb := _t(r, Vector3(17.2, 0, -14.5), -PI * 0.5)
	b.cylinder(0.18, 0.18, 0.08, wb * MeshKit.at(Vector3(0, 0.18, 0.55), Vector3.ONE, Vector3(0, 0, PI * 0.5)), IRON, 10)
	_box(b, wb, Vector3(0, 0.45, 0), Vector3(0.7, 0.3, 0.9), Color(0.35, 0.55, 0.75))
	_sph(b, wb, Vector3(-0.1, 0.62, 0.1), 0.18, Color(1.0, 0.55, 0.15), 10)
	_sph(b, wb, Vector3(0.15, 0.6, -0.15), 0.14, Color(1.0, 0.6, 0.2), 10)
	b.tube(wb * Vector3(-0.3, 0.45, -0.4), wb * Vector3(-0.35, 0.6, -1.0), 0.025, 0.025, WOOD_L, 6)
	b.tube(wb * Vector3(0.3, 0.45, -0.4), wb * Vector3(0.35, 0.6, -1.0), 0.025, 0.025, WOOD_L, 6)
	m.solid(0, Vector3(17.2, 0.4, -14.5), Vector3(1.6, 0.8, 0.8))
	# bench by the fountain, statues, lanterns, flowers
	var bn := _t(r, Vector3(13.0, 0, -22.0), PI)
	_box(b, bn, Vector3(0, 0.45, 0), Vector3(1.4, 0.08, 0.45), WOOD_L)
	_box(b, bn, Vector3(0, 0.75, 0.2), Vector3(1.4, 0.4, 0.05), WOOD_L)
	_box(b, bn, Vector3(-0.6, 0.22, 0), Vector3(0.08, 0.45, 0.4), IRON)
	_box(b, bn, Vector3(0.6, 0.22, 0), Vector3(0.08, 0.45, 0.4), IRON)
	m.solid(0, Vector3(13.0, 0.4, -22.05), Vector3(1.4, 0.8, 0.5))
	var cat := _t(r, Vector3(6.4, 0, -21.5), PI * 0.5)
	_box(b, cat, Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), Color(0.75, 0.75, 0.78))
	b.ellipsoid(Vector3(0.18, 0.25, 0.22), cat * MeshKit.at(Vector3(0, 0.82, 0)), Color(0.8, 0.8, 0.84), 10)
	_sph(b, cat, Vector3(0, 1.12, 0.05), 0.14, Color(0.8, 0.8, 0.84), 10)
	b.cone(0.05, 0.1, cat * MeshKit.at(Vector3(-0.07, 1.25, 0.05)), Color(0.8, 0.8, 0.84), 4)
	b.cone(0.05, 0.1, cat * MeshKit.at(Vector3(0.07, 1.25, 0.05)), Color(0.8, 0.8, 0.84), 4)
	m.solid(0, Vector3(6.4, 0.6, -21.5), Vector3(0.7, 1.2, 0.7))
	for p in [Vector3(1.0, 0, -14.0), Vector3(9.0, 0, -14.0), Vector3(11.0, 0, -14.0), Vector3(19.0, 0, -17.5),
			Vector3(1.0, 0, -22.0), Vector3(8.4, 0, -18.4), Vector3(11.6, 0, -18.4)]:
		var lp: Vector3 = p
		var lt := _t(r, lp)
		_cyl(b, lt, Vector3(0, 0.6, 0), 0.03, 0.04, 1.2, IRON, 6)
		b.sphere(0.11, lt * MeshKit.at(Vector3(0, 1.3, 0)), Color(1.0, 0.75, 0.4), 8, true)
		b.cone(0.13, 0.12, lt * MeshKit.at(Vector3(0, 1.45, 0)), IRON, 6)
	for i in 30:
		var fp := Vector3(_rng.randf_range(1.0, 19.0), 0, _rng.randf_range(-26.0, -13.6))
		if absf(fp.x - 10.0) < 1.5 and fp.z > -16.0:
			continue
		b.add_mesh(MeshKit.prop("flower", i % 3), _t(r, fp) * MeshKit.at(Vector3.ZERO, Vector3.ONE * 1.4))
	# a garden path from the conservatory door to the fountain
	_box(b, _t(r, Vector3(10.0, 0, -16.6)), Vector3(0, 0.01, 0), Vector3(1.6, 0.02, 7.0), Color(0.62, 0.55, 0.45))


static func _attic(m: Node3D) -> void:
	var r := 8
	var b: MeshKit.Builder = m.fb(r)
	# the stair hole (down to the hall) with a railing
	var sh := _t(r, Vector3(-3.45, 0, -4.2))
	_box(b, sh, Vector3(0, 0.005, 0), Vector3(1.6, 0.02, 1.2), Color(0.03, 0.02, 0.03))
	for i in 4:
		_box(b, sh, Vector3(0, -0.15 - i * 0.2, 0.3 - i * 0.25), Vector3(1.4, 0.05, 0.25), WOOD_M.darkened(0.15 * i))
	b.tube(sh * Vector3(0.85, 0.0, 0.65), sh * Vector3(0.85, 0.9, 0.65), 0.03, 0.03, WOOD_D, 6)
	b.tube(sh * Vector3(0.85, 0.9, 0.65), sh * Vector3(0.85, 0.9, -0.6), 0.03, 0.03, WOOD_D, 6)
	trunk(b, _t(r, Vector3(4.0, 0, 6.2), PI), Vector3(1.2, 0.75, 0.7), Color(0.5, 0.25, 0.2))
	_solid(m, r, Vector3(4.0, 0, 6.2), Vector3(1.2, 0.9, 0.7))
	wardrobe(b, _t(r, Vector3(-4.55, 0, 4.0), PI * 0.5), Vector3(1.4, 2.0, 0.7))
	_solid(m, r, Vector3(-4.55, 0, 4.0), Vector3(1.4, 2.0, 0.7), PI * 0.5)
	var hb := _t(r, Vector3(4.3, 0, -3.8))
	_cyl(b, hb, Vector3(0, 0.2, 0), 0.38, 0.38, 0.4, Color(0.85, 0.45, 0.6), 14)
	_cyl(b, hb, Vector3(0.05, 0.55, 0.0), 0.3, 0.3, 0.3, Color(0.4, 0.6, 0.85), 14)
	_cyl(b, hb, Vector3(-0.03, 0.82, 0.02), 0.22, 0.22, 0.24, Color(0.95, 0.85, 0.4), 14)
	_solid(m, r, Vector3(4.3, 0, -3.8), Vector3(0.8, 1.0, 0.8))
	trunk(b, _t(r, Vector3(1.8, 0, -4.45)), Vector3(1.0, 0.6, 0.6), Color(0.3, 0.45, 0.6))
	_solid(m, r, Vector3(1.8, 0, -4.45), Vector3(1.0, 0.75, 0.6))
	# rocking horse
	var rh := _t(r, Vector3(-1.0, 0, 5.9), PI * 0.5)
	b.torus(1.0, 0.03, rh * MeshKit.at(Vector3(0, 1.0, 0), Vector3(1, 1, 0.2), Vector3(PI * 0.5, 0, 0)), Color(0.8, 0.2, 0.2), 20)
	_rbox(b, rh, Vector3(0, 0.55, 0), Vector3(0.25, 0.3, 0.8), 0.1, Color(0.95, 0.92, 0.88))
	_rbox(b, rh, Vector3(0, 0.85, 0.42), Vector3(0.2, 0.35, 0.25), 0.08, Color(0.95, 0.92, 0.88))
	b.ellipsoid(Vector3(0.05, 0.2, 0.1), rh * MeshKit.at(Vector3(0, 0.95, 0.3)), Color(0.4, 0.25, 0.15), 6)
	_solid(m, r, Vector3(-1.0, 0, 5.9), Vector3(1.0, 1.0, 0.4))
	# dress-maker's mannequin with a feather boa
	var mq := _t(r, Vector3(3.0, 0, 1.6))
	_cyl(b, mq, Vector3(0, 0.5, 0), 0.02, 0.02, 1.0, WOOD_D, 6)
	b.ellipsoid(Vector3(0.2, 0.32, 0.15), mq * MeshKit.at(Vector3(0, 1.25, 0)), Color(0.95, 0.85, 0.75), 10)
	b.torus(0.18, 0.05, mq * MeshKit.at(Vector3(0, 1.5, 0)), Color(0.95, 0.4, 0.7), 10)
	_solid(m, r, Vector3(3.0, 0, 1.6), Vector3(0.45, 1.6, 0.45))
	table(b, _t(r, Vector3(-3.8, 0, 1.0), PI * 0.5), Vector3(1.0, 0.75, 0.7), WOOD_L)
	_solid(m, r, Vector3(-3.8, 0, 1.0), Vector3(1.0, 0.75, 0.7), PI * 0.5)
	for i in 5:
		var bp := Vector3(_rng.randf_range(-4.4, 4.4), 0, _rng.randf_range(-1.5, 3.0))
		if absf(bp.x) < 1.6 or (bp.x > 2.2 and bp.z < 2.6 and bp.z > 0.8):
			continue
		trunk(b, _t(r, bp, _rng.randf() * PI), Vector3(0.6, 0.4, 0.5), Color(0.55, 0.42, 0.3).lightened(_rng.randf() * 0.2))
	painting(b, Vector3(-0.5, 7.5, -4.86), Vector3(0, 0, 1), 0)
	# a round window in the south gable and a bare bulb
	m.win().box(Vector3(1.0, 1.0, 0.02), Transform3D(Basis(), Vector3(0, 9.0, 6.88)), Color(1, 1, 1))
	b.torus(0.55, 0.06, MeshKit.at(Vector3(0, 9.0, 6.85), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), WOOD_D, 16)
	b.tube(Vector3(0.5, 10.3, 1.0), Vector3(0.5, 9.3, 1.0), 0.008, 0.008, IRON, 4)
	b.sphere(0.08, MeshKit.at(Vector3(0.5, 9.2, 1.0)), Color(1.0, 0.85, 0.5), 8, true)


static func _cellar(m: Node3D) -> void:
	var r := 9
	var b: MeshKit.Builder = m.fb(r)
	# steps up to the hall (north-east)
	var su := _t(r, Vector3(3.45, 0, -4.6))
	for i in 6:
		_box(b, su, Vector3(0, 0.1 + i * 0.2, -i * 0.05), Vector3(1.5, 0.2 + i * 0.4, 0.3), WOOD_M.darkened(0.1 * (i % 2)))
	_box(b, su, Vector3(0, 2.6, -0.2), Vector3(1.5, 0.8, 0.05), Color(1.0, 0.85, 0.5), true)
	m.solid(0 + 2, Vector3(3.45, -6.0 + 1.3, -4.75), Vector3(1.6, 2.6, 0.5))
	jar_shelf(b, _t(r, Vector3(-4.62, 0, 0.0), PI * 0.5), Vector3(2.4, 2.0, 0.55))
	_solid(m, r, Vector3(-4.62, 0, 0.0), Vector3(2.4, 2.0, 0.55), PI * 0.5)
	for p in [Vector3(3.3, 0, 5.3), Vector3(4.2, 0, 5.4), Vector3(3.7, 0, 6.2), Vector3(4.5, 0, 6.3)]:
		var bp: Vector3 = p
		b.add_mesh(MeshKit.prop("barrel"), _t(r, bp) * MeshKit.at(Vector3.ZERO, Vector3.ONE * 0.9))
	_solid(m, r, Vector3(3.9, 0, 5.8), Vector3(1.8, 1.0, 1.6))
	for p in [Vector3(-4.2, 0, 5.6), Vector3(-3.4, 0, 6.2), Vector3(-4.0, 0.8, 6.0)]:
		var cp: Vector3 = p
		b.add_mesh(MeshKit.prop("crate"), _t(r, cp) * MeshKit.at(Vector3.ZERO, Vector3.ONE * 0.9))
	_solid(m, r, Vector3(-3.8, 0, 5.85), Vector3(1.4, 1.5, 1.2))
	# the rumbly boiler
	var bo := _t(r, Vector3(4.2, 0, 1.5), -PI * 0.5)
	_cyl(b, bo, Vector3(0, 0.75, 0), 0.5, 0.5, 1.5, Color(0.55, 0.3, 0.2), 14)
	_cyl(b, bo, Vector3(0, 1.55, 0), 0.3, 0.5, 0.2, Color(0.45, 0.25, 0.18), 14)
	b.disc(0.14, bo * MeshKit.at(Vector3(0, 0.6, 0.5), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.45, 0.15), 10, true)
	b.tube(bo * Vector3(0, 1.6, 0), bo * Vector3(0, 3.3, 0), 0.08, 0.08, IRON, 8)
	b.tube(bo * Vector3(0.4, 1.0, 0), bo * Vector3(0.4, 1.0, -1.5), 0.05, 0.05, Color(0.7, 0.45, 0.3), 8)
	_solid(m, r, Vector3(4.2, 0, 1.5), Vector3(1.1, 1.8, 1.1))
	table(b, _t(r, Vector3(-1.0, 0, -4.55)), Vector3(2.0, 0.85, 0.6), WOOD_D)
	_solid(m, r, Vector3(-1.0, 0, -4.55), Vector3(2.0, 0.85, 0.6))
	_box(b, _t(r, Vector3(-1.6, 0.85, -4.6)), Vector3(0, 0.05, 0), Vector3(0.3, 0.1, 0.15), Color(0.6, 0.6, 0.65))
	painting(b, Vector3(0.0, -4.4, 6.86), Vector3(0, 0, -1), 1)
	# bulbs, cobwebs
	for p in [Vector3(0, -2.9, 0.0), Vector3(0, -2.9, 4.5)]:
		var bp: Vector3 = p
		b.tube(bp + Vector3(0, 0.4, 0), bp, 0.008, 0.008, IRON, 4)
		b.sphere(0.08, MeshKit.at(bp - Vector3(0, 0.08, 0)), Color(1.0, 0.8, 0.45), 8, true)
	for p in [Vector3(-4.8, -2.8, -4.8), Vector3(4.8, -2.8, 6.8), Vector3(-4.8, -2.8, 6.8)]:
		var cw: Vector3 = p
		b.polygon(PackedVector2Array([Vector2(0, 0), Vector2(0.7, 0), Vector2(0, -0.7)]), 0.005, Transform3D(Basis(Vector3.UP, 0.0), cw), Color(0.85, 0.85, 0.9, 1.0))
