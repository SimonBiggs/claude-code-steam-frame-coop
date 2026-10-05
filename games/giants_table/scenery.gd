extends Node3D
## Simple mode: everything on the table reacts when the Giant touches it (Simon's rule).
##  - Trees sway and rustle when a hand brushes them; squeeze near one to pull it out and throw it
##    (prop.gd). A new tree grows back in its spot a few seconds later.
##  - Cottages wobble like jelly (boing!) when you poke them.
##  - Sheep, villagers and ducks hop and squeak (village.gd poke()); a hand in the river splashes.
## Cheap on the Frame: trees are 2 MultiMeshes and the cottages 1 (4 draw calls each kind, as when
## they were baked); only the instances that are moving get new transforms. Every machine runs the
## touch reactions itself from the giant's hand positions (the TV from the ghost hands), so nothing
## extra goes over the network except which trees are pulled up.

const W := preload("res://games/giants_table/world.gd")
const PropScript := preload("res://games/giants_table/prop.gd")
const TOUCH_SPEED := 3.0  # world units/s: a resting hand doesn't keep shaking things

var main
var trees: Array = []
var tree_mm: Array = []        # MultiMesh per tree kind
var tree_slot: PackedInt32Array = PackedInt32Array()  # instance index inside its kind's MultiMesh
var tree_base: Array = []      # Transform3D per tree
var sway_t: PackedFloat32Array = PackedFloat32Array()
var sway_dir: Array = []
var grow_t: PackedFloat32Array = PackedFloat32Array()  # 0..1 while a new tree grows back, else 1
var gone := {}                 # tree index -> true while pulled up
var house_mm: MultiMesh
var house_base: Array = []
var wob_t: PackedFloat32Array = PackedFloat32Array()
var cool := {}                 # key -> seconds until it can react again
var last_hand: Array = []
var splash_cd := 0.0
var touches := 0               # for the bot


func _ready() -> void:
	trees = W.trees()
	var trunk := W.cyl(0.12, 0.18, 0.9, 6)
	var trunk_mat := W.mat(Color(0.45, 0.28, 0.15))
	var pine_mat := W.mat(Color(0.18, 0.5, 0.3))
	var leaf_mat := W.mat(Color(0.35, 0.68, 0.25))
	var up := func(v: Vector3) -> Transform3D: return Transform3D(Basis(), v)
	var pine := _mesh([[[[trunk, up.call(Vector3(0, 0.45, 0))]], trunk_mat],
		[[[W.cyl(0.0, 0.75, 1.3, 8), up.call(Vector3(0, 1.3, 0))], [W.cyl(0.0, 0.55, 1.0, 8), up.call(Vector3(0, 1.95, 0))]], pine_mat]])
	var round_tree := _mesh([[[[trunk, up.call(Vector3(0, 0.45, 0))]], trunk_mat],
		[[[W.sphere(0.75, 10), up.call(Vector3(0, 1.5, 0))], [W.sphere(0.5, 8), up.call(Vector3(0.3, 2.05, 0.1))]], leaf_mat]])
	var counts := [0, 0]
	for t in trees:
		var k: int = t[2]
		tree_slot.append(counts[k])
		counts[k] += 1
		var x: float = t[0]
		var z: float = t[1]
		tree_base.append(Transform3D(Basis().scaled(Vector3.ONE * float(t[3])), Vector3(x, W.height(x, z), z)))
		sway_t.append(99.0)
		sway_dir.append(Vector3.RIGHT)
		grow_t.append(1.0)
	for k in 2:
		var mm := _multi([pine, round_tree][k], counts[k])
		tree_mm.append(mm)
	for i in trees.size():
		_set_tree(i, tree_base[i])
	# Cottages: one mesh with walls, roof, door and glowing windows, drawn 6 times.
	var roof := PrismMesh.new()
	roof.size = Vector3(2.0, 0.85, 1.6)
	var win: Array = []
	for wx in [-0.55, 0.55]:
		win.append([W.box(Vector3(0.3, 0.28, 0.06)), up.call(Vector3(wx, 0.68, 0.68))])
	for wz in [-0.3, 0.3]:
		win.append([W.box(Vector3(0.06, 0.28, 0.3)), up.call(Vector3(0.86, 0.68, wz))])
	var house := _mesh([
		[[[W.box(Vector3(1.7, 1.15, 1.35)), up.call(Vector3(0, 0.575, 0))], [W.box(Vector3(0.22, 0.6, 0.22)), up.call(Vector3(0.5, 1.75, 0.2))]], W.mat(Color(0.98, 0.9, 0.74))],
		[[[roof, up.call(Vector3(0, 1.57, 0))]], W.mat(Color(0.85, 0.35, 0.22))],
		[[[W.box(Vector3(0.38, 0.62, 0.06)), up.call(Vector3(0, 0.31, 0.68))]], W.mat(Color(0.4, 0.24, 0.13))],
		[win, W.mat(Color(1.0, 0.8, 0.4), 2.2)]])
	house_mm = _multi(house, W.COTTAGES.size())
	for c in W.COTTAGES:
		var x: float = c[0]
		var z: float = c[1]
		var xf := Transform3D(Basis(Vector3.UP, c[2]), Vector3(x, W.height(x, z), z))
		house_mm.set_instance_transform(house_base.size(), xf)
		house_base.append(xf)
		wob_t.append(99.0)


## One ArrayMesh with a surface per material: parts = [[[mesh, xform], ...], material], ...
func _mesh(parts: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	for part in parts:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mx in part[0]:
			st.append_from(mx[0], 0, mx[1])
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, part[1])
	return am


func _multi(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	return mm


func _set_tree(i: int, xf: Transform3D) -> void:
	var mm: MultiMesh = tree_mm[int(trees[i][2])]
	mm.set_instance_transform(tree_slot[i], xf)


func _process(delta: float) -> void:
	if main == null or main.giant == null:
		return
	splash_cd -= delta
	for key in cool.keys():
		cool[key] = float(cool[key]) - delta
		if float(cool[key]) <= 0.0:
			cool.erase(key)
	_touch(delta)
	_animate(delta)


## Each giant hand that moves through something makes it react.
func _touch(delta: float) -> void:
	var hands: Array = main.giant.hands
	while last_hand.size() < hands.size():
		last_hand.append(Vector3.ZERO)
	for hi in hands.size():
		var h = hands[hi]
		var p: Vector3 = h.pos
		var speed := p.distance_to(last_hand[hi]) / maxf(delta, 0.001)
		last_hand[hi] = p
		if p == Vector3.ZERO or speed < TOUCH_SPEED or speed > 400.0 or (h.root != null and not h.root.visible):
			continue
		var g := W.height(p.x, p.z)
		if g < -50.0 or p.y > g + 3.2:
			continue
		for i in trees.size():
			if gone.has(i) or grow_t[i] < 1.0:
				continue
			var b: Transform3D = tree_base[i]
			var s: float = trees[i][3]
			var off := Vector2(b.origin.x - p.x, b.origin.z - p.z)
			if off.length() < 0.95 * s + 0.35 and p.y < b.origin.y + 2.6 * s and _ready_to("t%d" % i, 0.7):
				sway_t[i] = 0.0
				var dir := Vector3(off.x, 0.0, off.y)
				sway_dir[i] = dir.normalized() if dir.length() > 0.05 else Vector3.RIGHT
				_react("rustle", b.origin + Vector3.UP * 1.6 * s, Color(0.4, 0.75, 0.3), 1.0)
		for i in house_base.size():
			var hb: Transform3D = house_base[i]
			if Vector2(hb.origin.x - p.x, hb.origin.z - p.z).length() < 1.35 and p.y < hb.origin.y + 2.3 and _ready_to("h%d" % i, 0.6):
				wob_t[i] = 0.0
				_react("boing", hb.origin + Vector3.UP * 2.0, Color(1.0, 0.85, 0.5), randf_range(0.9, 1.2))
		var animals: int = main.village.poke(p, 0.9) if main.village != null else 0
		if animals > 0 and _ready_to("animal%d" % hi, 0.35):
			_react("baa" if animals == 1 else "squeak", p, Color(1, 1, 1), randf_range(0.9, 1.3))
		if W.in_water(p.x, p.z) and p.y < W.WATER_Y + 0.6 and splash_cd <= 0.0:
			splash_cd = 0.4
			_react("splash", Vector3(p.x, W.WATER_Y, p.z), Color(0.6, 0.85, 1.0), randf_range(0.9, 1.2))


func _ready_to(key: String, cd: float) -> bool:
	if cool.has(key):
		return false
	cool[key] = cd
	touches += 1
	return true


## Sound and a little puff, on this machine only (the TV works out its own touches).
func _react(snd: String, at: Vector3, col: Color, pitch: float) -> void:
	main.sound(snd, -6.0, pitch, false)
	main.burst(at, col, 8, 0.08, false)
	if main.giant.vr:
		main.giant.thud_haptic(at, 0.25)


func _animate(delta: float) -> void:
	for i in trees.size():
		if gone.has(i):
			continue
		var b: Transform3D = tree_base[i]
		if grow_t[i] < 1.0:
			grow_t[i] = minf(1.0, grow_t[i] + delta * 0.8)
			var e := ease(grow_t[i], -2.4) * (1.0 + 0.15 * sin(grow_t[i] * PI))
			_set_tree(i, Transform3D(b.basis.scaled(Vector3.ONE * maxf(e, 0.01)), b.origin))
			continue
		if sway_t[i] > 3.0:
			continue
		sway_t[i] += delta
		var t: float = sway_t[i]
		var lean := 0.32 * exp(-t * 2.2) * cos(t * 11.0)
		var axis: Vector3 = Vector3.UP.cross(sway_dir[i]).normalized()
		_set_tree(i, Transform3D(Basis(axis, lean) * b.basis, b.origin) if t <= 3.0 else b)
	for i in house_base.size():
		if wob_t[i] > 2.0:
			continue
		wob_t[i] += delta
		var t: float = wob_t[i]
		var hb: Transform3D = house_base[i]
		var w := 0.0 if t > 2.0 else exp(-t * 3.0) * sin(t * 18.0)
		var sq := Vector3(1.0 + 0.08 * w, 1.0 - 0.14 * w, 1.0 + 0.08 * w)
		house_mm.set_instance_transform(i, Transform3D(hb.basis * Basis.from_scale(sq), hb.origin))


# --- Pulling trees up (host) ---------------------------------------------------------

## The giant squeezed near a tree with nothing else to grab: pull it up and hand it over.
func grab_tree(hp: Vector3, reach: float, flat: bool):
	var best := -1
	var best_d := INF
	for i in trees.size():
		if gone.has(i) or grow_t[i] < 1.0:
			continue
		var b: Transform3D = tree_base[i]
		var s: float = trees[i][3]
		var c := b.origin + Vector3.UP * 1.3 * s
		var d := Vector2(c.x - hp.x, c.z - hp.z).length() if flat else c.distance_to(hp)
		d -= 0.7 * s
		if d < reach and d < best_d:
			best_d = d
			best = i
	if best < 0:
		return null
	_set_gone(best, true)
	var p := PropScript.new()
	p.main = main
	p.net_id = main.next_net_id()
	p.setup(int(trees[best][2]), best, float(trees[best][3]))
	p.position = (tree_base[best] as Transform3D).origin
	main.add_child(p)
	main.burst(p.position + Vector3.UP * 0.2, Color(0.55, 0.4, 0.25), 14, 0.1)
	main.sound("rustle", -2.0, 1.1)
	print("Giant pulled up a tree (%d)" % best)
	return p


func _set_gone(i: int, on: bool) -> void:
	if on:
		gone[i] = true
		_set_tree(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), (tree_base[i] as Transform3D).origin))
	else:
		gone.erase(i)
		grow_t[i] = 0.0
		sway_t[i] = 99.0


## A thrown tree has had its moment: a new one grows back in its old spot.
func regrow(i: int) -> void:
	if i < 0 or not gone.has(i):
		return
	_set_gone(i, false)
	var b: Transform3D = tree_base[i]
	main.burst(b.origin + Vector3.UP * 0.5, Color(0.6, 1.0, 0.5), 10, 0.08)


## TV: which trees are pulled up right now (from the snapshot).
func gone_list() -> Array:
	return gone.keys()


func apply_gone(list: Array) -> void:
	var now := {}
	for v in list:
		now[int(v)] = true
	for i in now:
		if not gone.has(i):
			_set_gone(i, true)
	for i in gone.keys():
		if not now.has(i):
			_set_gone(i, false)
