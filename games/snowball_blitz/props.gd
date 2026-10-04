extends Node3D
## Simple mode: everything the VR thrower can reach does something (Simon's rule).
##  - SNOW PILES on the mound at your feet: touch them - crunch and a puff; squeeze down there to scoop
##    a big snowball (the pile shrinks, then snows back).
##  - ICICLES on a little wooden rack: touch them - they tinkle and wobble; squeeze one to snap it off
##    and throw it like a snowball. They grow back.
##  - a snow-covered PINE TREE: touch it - it sways and dumps its snow (WHUMP). The snow comes back.
##  - a SLED: give it a shove - it slides off and glides back home a bit later.
##  - a BELL on a post: touch it - DING! It swings.
##  - the FORT WALL: pat it - puffs of snow, and a crumbling wall packs up a little.
## TV players bump the tree and the sled when they walk into them.
## The host (or local game) checks the hands; the TV gets each touch as a "prop" event and the icicles /
## tree snow / sled / piles in the snapshot. Cheap: ~20 small unshaded-ish meshes, no shadows, no physics.

const BELL_POST := Vector3(-0.72, 0.0, -0.52)
const BELL_AT := Vector3(-0.72, 1.18, -0.52)
const RACK := Vector3(0.78, 0.0, -0.32)
const ICICLE_Z: Array[float] = [-0.22, -0.07, 0.08, 0.23]
const ICICLE_Y := 1.28
const TREE := Vector3(-0.88, 0.0, 0.58)
const SLED_HOME := Vector3(0.82, 0.3, 0.62)
const PILES: Array[Vector3] = [Vector3(0.0, 0.22, -0.82), Vector3(0.6, 0.22, 0.12), Vector3(-0.52, 0.22, -0.02)]
const TOUCH_R := 0.13

var main
var bell_pivot: Node3D
var bell_ang := 0.0
var bell_vel := 0.0
var icicles: Array = []  # {node, present, regrow, wob, wob_v}
var tree: Node3D
var tree_snow: Node3D
var snow_amt := 1.0
var tree_sway := Vector2.ZERO
var tree_sway_v := Vector2.ZERO
var sled: Node3D
var sled_pos := SLED_HOME
var sled_vel := Vector3.ZERO
var sled_idle := 0.0
var piles: Array = []  # {node, size}
var prev_hand: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var cool := {}  # touch key -> seconds until it can fire again
var touched := {}  # kind -> count (the bot reads it)
var t := 0.0


func _ready() -> void:
	name = "Props"
	var wood: StandardMaterial3D = main.mat("stick")
	var ice: StandardMaterial3D = main.make_material(Color(0.75, 0.92, 1.0), 0.6)
	ice.roughness = 0.15
	ice.metallic = 0.3
	# Bell post with a little roof beam, and a golden bell hanging from it.
	_box(self, Vector3(0.07, 1.4, 0.07), BELL_POST + Vector3(0, 0.7, 0), wood)
	_box(self, Vector3(0.07, 0.07, 0.3), BELL_POST + Vector3(0, 1.38, 0.1), wood)
	bell_pivot = Node3D.new()
	bell_pivot.position = BELL_AT + Vector3(0, 0.2, 0.18)
	add_child(bell_pivot)
	var bell := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.04
	bm.bottom_radius = 0.1
	bm.height = 0.16
	bm.radial_segments = 12
	bm.rings = 1
	bell.mesh = bm
	bell.material_override = main.mat("crown")
	bell.position = Vector3(0, -0.13, 0)
	bell_pivot.add_child(bell)
	# Icicle rack: two posts and a snowy crossbar along Z.
	for z in [-0.34, 0.34]:
		_box(self, Vector3(0.06, 1.45, 0.06), RACK + Vector3(0, 0.72, z), wood)
	_box(self, Vector3(0.08, 0.07, 0.78), RACK + Vector3(0, 1.44, 0), main.mat("snow"))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.028
	cone.bottom_radius = 0.0
	cone.height = 0.24
	cone.radial_segments = 6
	cone.rings = 1
	for z in ICICLE_Z:
		var n := MeshInstance3D.new()
		n.mesh = cone
		n.material_override = ice
		n.position = Vector3(RACK.x, ICICLE_Y, RACK.z + z)
		add_child(n)
		icicles.append({"node": n, "present": true, "regrow": 0.0, "wob": 0.0, "wob_v": 0.0})
	# A small snowy pine.
	tree = Node3D.new()
	tree.position = TREE
	add_child(tree)
	_box(tree, Vector3(0.1, 0.4, 0.1), Vector3(0, 0.2, 0), wood)
	var pine := main.make_material(Color(0.16, 0.42, 0.26), 0.0) as StandardMaterial3D
	for k in 2:
		var tc := CylinderMesh.new()
		tc.top_radius = 0.0
		tc.bottom_radius = 0.42 - k * 0.12
		tc.height = 0.6
		tc.radial_segments = 10
		tc.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = tc
		mi.material_override = pine
		mi.position.y = 0.6 + k * 0.38
		tree.add_child(mi)
	tree_snow = Node3D.new()
	tree.add_child(tree_snow)
	for k in 2:
		var sc := CylinderMesh.new()
		sc.top_radius = 0.0
		sc.bottom_radius = 0.34 - k * 0.1
		sc.height = 0.3
		sc.radial_segments = 10
		sc.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = sc
		mi.material_override = main.mat("snow")
		mi.position.y = 0.78 + k * 0.38
		tree_snow.add_child(mi)
	# A red sled.
	sled = Node3D.new()
	add_child(sled)
	_box(sled, Vector3(0.36, 0.06, 0.7), Vector3(0, 0.08, 0), main.mat("sled"))
	for x in [-0.15, 0.15]:
		_box(sled, Vector3(0.03, 0.03, 0.8), Vector3(x, 0.02, -0.03), wood)
	sled.position = SLED_HOME
	# Snow piles on the mound.
	for at in PILES:
		var mi := MeshInstance3D.new()
		mi.mesh = main.sphere_mesh(0.2)
		mi.material_override = main.mat("snow")
		mi.position = at
		mi.scale = Vector3(1.0, 0.6, 1.0)
		add_child(mi)
		piles.append({"node": mi, "size": 1.0})
	_no_shadows(self)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


## Every frame on both machines: springs and regrowth; the host / local game also checks touches.
func tick(delta: float) -> void:
	t += delta
	for k in cool.keys():
		cool[k] -= delta
	_animate(delta)
	if main.net.mode == "client" or main.players.is_empty():
		return
	var p = main.players[0]
	if p.vr and p.active:
		var hands: Array = [p.hand_l, p.hand_r]
		for h in 2:
			var pos: Vector3 = hands[h].global_position
			if delta > 0.0 and prev_hand[h] != Vector3.ZERO:
				hand_vel[h] = hand_vel[h].lerp((pos - prev_hand[h]) / delta, 0.5)
			prev_hand[h] = pos
			_touch(h, pos, hands[h])
	for q in main.players:
		if q.active and not q.vr and not q.ghost:
			_bump(q.global_position)
	_host_tick(delta)


func _ready_key(key: String, wait: float) -> bool:
	if float(cool.get(key, 0.0)) > 0.0:
		return false
	cool[key] = wait
	return true


func _count(kind: String) -> void:
	touched[kind] = int(touched.get(kind, 0)) + 1


func _buzz(hand: XRController3D, amount: float) -> void:
	if hand:
		hand.trigger_haptic_pulse("haptic", 0.0, amount, 0.06, 0.0)


func _touch(h: int, pos: Vector3, hand: XRController3D) -> void:
	# Bell.
	if pos.distance_to(bell_pivot.global_position + Vector3(0, -0.13, 0)) < TOUCH_R + 0.04 and _ready_key("bell", 0.5):
		ring_bell(signf(hand_vel[h].x + 0.01) * clampf(hand_vel[h].length() * 0.5, 1.5, 5.0))
		main.net.event("prop", ["bell", 0])
		_buzz(hand, 0.5)
		_count("bell")
	# Icicles.
	for i in icicles.size():
		var ic: Dictionary = icicles[i]
		if ic.present and pos.distance_to(ic.node.global_position) < TOUCH_R and _ready_key("ice%d" % i, 0.35):
			tinkle(i)
			main.net.event("prop", ["ice", i])
			_buzz(hand, 0.25)
			_count("icicle")
	# Tree.
	var rel := pos - TREE
	if Vector2(rel.x, rel.z).length() < 0.42 and pos.y > 0.35 and pos.y < 1.45 and _ready_key("tree", 0.8):
		shake_tree(Vector2(hand_vel[h].x, hand_vel[h].z))
		_buzz(hand, 0.4)
		_count("tree")
	# Sled.
	var sr := pos - sled_pos
	if Vector2(sr.x, sr.z).length() < 0.4 and pos.y < sled_pos.y + 0.35 and _ready_key("sled", 0.4):
		var push := Vector3(hand_vel[h].x, 0.0, hand_vel[h].z)
		if push.length() < 1.0:
			push = Vector3(sr.x, 0.0, sr.z).normalized() * -1.0
		_shove_sled(push)
		_buzz(hand, 0.35)
		_count("sled")
	# Snow piles.
	for i in piles.size():
		if pos.distance_to(piles[i].node.global_position) < 0.24 and _ready_key("pile%d" % i, 0.5):
			main.burst(pos, Color(1, 1, 1), 10, 0.05)
			main.sound("crunch", -6.0, randf_range(0.9, 1.2))
			_buzz(hand, 0.2)
			_count("pile")
	# The fort wall: pat it.
	var si: int = main.seg_hit(pos, 0.05)
	if si >= 0 and _ready_key("wall%d" % h, 0.3):
		main.burst(pos, Color(0.92, 0.96, 1.0), 12, 0.07)
		main.sound("whump", -8.0, 1.3)
		_buzz(hand, 0.4)
		main.seg_hp[si] = minf(main.seg_max, main.seg_hp[si] + 10.0)
		_count("wall")


## TV players walking into the tree or the sled.
func _bump(pos: Vector3) -> void:
	var rel := pos - TREE
	if Vector2(rel.x, rel.z).length() < 0.7 and _ready_key("tree_bump", 1.5):
		shake_tree(Vector2(rel.x, rel.z).normalized() * -2.0)
	var sr := pos - sled_pos
	if Vector2(sr.x, sr.z).length() < 0.75 and _ready_key("sled_bump", 0.6):
		_shove_sled(Vector3(-sr.x, 0.0, -sr.z).normalized() * 2.5)


func _host_tick(delta: float) -> void:
	for ic in icicles:
		if not ic.present:
			ic.regrow -= delta
			if ic.regrow <= 0.0:
				ic.present = true
				ic.node.scale = Vector3.ONE * 0.1
	for pl in piles:
		pl.size = minf(1.0, pl.size + delta * 0.08)
	snow_amt = minf(1.0, snow_amt + delta * 0.12)
	# The sled slides, slows down, and later glides back home.
	sled_pos += sled_vel * delta
	sled_vel = sled_vel.move_toward(Vector3.ZERO, delta * 2.2)
	var flat := Vector2(sled_pos.x, sled_pos.z)
	if flat.length() > 3.0:
		flat = flat.normalized() * 3.0
		sled_pos = Vector3(flat.x, sled_pos.y, flat.y)
		sled_vel = -sled_vel * 0.4
	if sled_vel.length() < 0.05:
		sled_idle += delta
		if sled_idle > 4.0:
			sled_pos = sled_pos.lerp(SLED_HOME, 1.0 - exp(-1.2 * delta))
	else:
		sled_idle = 0.0


func _animate(delta: float) -> void:
	bell_vel += (-bell_ang * 40.0 - bell_vel * 2.5) * delta
	bell_ang += bell_vel * delta
	bell_pivot.rotation.z = bell_ang
	for ic in icicles:
		ic.wob_v += (-ic.wob * 140.0 - ic.wob_v * 6.0) * delta
		ic.wob += ic.wob_v * delta
		var n: MeshInstance3D = ic.node
		n.visible = ic.present
		n.rotation.x = ic.wob
		if ic.present and n.scale.x < 1.0:
			n.scale = Vector3.ONE * minf(1.0, n.scale.x + delta * 1.5)
	tree_sway_v += (-tree_sway * 30.0 - tree_sway_v * 3.0) * delta
	tree_sway += tree_sway_v * delta
	tree.rotation = Vector3(tree_sway.y, 0.0, -tree_sway.x)
	tree_snow.scale = Vector3.ONE * maxf(snow_amt, 0.01)
	tree_snow.visible = snow_amt > 0.05
	sled.position = sled.position.lerp(sled_pos, 1.0 - exp(-12.0 * delta))
	if sled_vel.length() > 0.3:
		sled.rotation.y = lerp_angle(sled.rotation.y, atan2(-sled_vel.x, -sled_vel.z), 1.0 - exp(-6.0 * delta))
	for pl in piles:
		var s: float = maxf(pl.size, 0.15)
		pl.node.scale = Vector3(s, 0.6 * s, s)


# --- Actions (host decides; events replay them on the TV) ---------------------------

func ring_bell(push: float) -> void:
	bell_vel += push
	if main.net.mode != "client":
		main.sound("bell", -3.0, randf_range(0.97, 1.03))


func tinkle(i: int) -> void:
	icicles[i].wob_v += randf_range(5.0, 8.0) * (1.0 if randf() < 0.5 else -1.0)
	if main.net.mode != "client":
		main.sound("tinkle", -6.0, 1.0 + i * 0.12)


func shake_tree(dir: Vector2) -> void:
	if dir.length() < 0.5:
		dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	tree_sway_v += dir.limit_length(4.0) * 0.6
	if main.net.mode == "client":
		return
	main.net.event("prop", ["tree", 0, dir])
	if snow_amt > 0.4:
		main.burst(TREE + Vector3(0, 1.0, 0), Color(1, 1, 1), 26, 0.09)
		main.burst(TREE + Vector3(0, 0.4, 0), Color(1, 1, 1), 14, 0.07)
		main.sound("whump", -2.0, 0.8)
		snow_amt = 0.0
	else:
		main.sound("crunch", -8.0, 0.7)


func _shove_sled(push: Vector3) -> void:
	sled_vel = push.limit_length(5.0)
	sled_idle = 0.0
	main.sound("whoosh", -8.0, 1.4)


## VR: squeezing next to an icicle snaps it off into the hand. Returns true if it did.
func take_icicle(pos: Vector3) -> bool:
	for i in icicles.size():
		var ic: Dictionary = icicles[i]
		if ic.present and pos.distance_to(ic.node.global_position) < TOUCH_R + 0.03:
			ic.present = false
			ic.regrow = 8.0
			main.sound("tinkle", -2.0, 0.8)
			main.burst(ic.node.global_position, Color(0.8, 0.95, 1.0), 8, 0.04)
			_count("icicle_taken")
			return true
	return false


## VR: squeezing down at a snow pile scoops a big snowball from it. Returns true if it did.
func scoop(pos: Vector3) -> bool:
	for pl in piles:
		if pl.size > 0.3 and pos.distance_to(pl.node.global_position) < 0.32:
			pl.size -= 0.35
			main.burst(pl.node.global_position + Vector3.UP * 0.1, Color(1, 1, 1), 12, 0.06)
			main.sound("crunch", -4.0, 1.1)
			_count("scoop")
			return true
	return false


# --- Network ------------------------------------------------------------------------

func pack() -> Array:
	var bits := 0
	for i in icicles.size():
		if icicles[i].present:
			bits |= 1 << i
	var sizes: Array = []
	for pl in piles:
		sizes.append(snappedf(pl.size, 0.05))
	return [bits, snappedf(snow_amt, 0.05), sled_pos, sizes]


func unpack(a: Array) -> void:
	if a.size() < 4:
		return
	var bits: int = a[0]
	for i in icicles.size():
		var on := bits & (1 << i) != 0
		if on and not icicles[i].present:
			icicles[i].node.scale = Vector3.ONE * 0.1
		icicles[i].present = on
	snow_amt = a[1]
	sled_pos = a[2]
	var sizes: Array = a[3]
	for i in mini(sizes.size(), piles.size()):
		piles[i].size = sizes[i]


func client_event(args: Array) -> void:
	match str(args[0]):
		"bell":
			ring_bell(3.0)
		"ice":
			tinkle(int(args[1]))
		"tree":
			if args.size() > 2:
				shake_tree(args[2])
