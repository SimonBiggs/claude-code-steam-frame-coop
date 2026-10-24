extends Node3D
## Simple mode: a see-through glowing glove that SHOWS the gardener what to do (instead of text).
## Three loops, in world units (the gardener sees the world at XR world_scale 4, so this is a real-size
## gardening glove):
##  - "seed":  reach into the seed tray, close, carry the seed to the glowing spot, PUSH it into the
##             soil, open, lift away.
##  - "water": reach for the watering can, close, carry it over the spot and TIP it (drops fall).
##  - "pick":  reach for the ripe fruit, close, carry it to the basket, let go.
## Only the gardener sees it (main puts it on the VR / gardener layer, the bees' cameras skip it).
## main calls show_demo() every frame; it fades in when the gardener has been idle for a moment.

const W := preload("res://games/bee_garden/world.gd")

var hand: Node3D
var fingers: Array[Node3D] = []
var thumb: Node3D
var seed_ball: MeshInstance3D
var can: Node3D
var drops: Array[MeshInstance3D] = []
var mat: StandardMaterial3D
var t := 0.0
var idle_t := 0.0
var mode := ""
var layer := 1


func _ready() -> void:
	top_level = true
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.85, 0.5)
	mat.no_depth_test = false
	hand = Node3D.new()
	add_child(hand)
	# Same size and shape as the gardener's glove: fingers point -Z.
	_part(hand, W.sphere(0.16, 10), Vector3(0, 0, 0.05), Vector3(1.0, 0.6, 1.3))
	for i in 3:
		var f := Node3D.new()
		f.position = Vector3(-0.07 + i * 0.07, 0.0, -0.08)
		hand.add_child(f)
		var m := _part(f, W.cyl(0.04, 0.045, 0.18, 6), Vector3(0, 0, -0.09), Vector3.ONE)
		m.rotation.x = PI / 2.0
		fingers.append(f)
	thumb = Node3D.new()
	thumb.position = Vector3(-0.12, 0.0, 0.0)
	hand.add_child(thumb)
	var tm := _part(thumb, W.cyl(0.04, 0.045, 0.14, 6), Vector3(0, 0, -0.06), Vector3.ONE)
	tm.rotation = Vector3(PI / 2.0, 0.0, 0.6)
	seed_ball = _part(self, W.sphere(0.07, 8), Vector3.ZERO, Vector3(1.0, 0.8, 1.3))
	can = W.make_can()
	add_child(can)
	_ghostify(can)
	for i in 3:
		drops.append(_part(self, W.sphere(0.04, 6), Vector3.ZERO, Vector3(0.8, 1.3, 0.8)))
	set_layer(layer)
	visible = false


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var m := W.mesh_node(parent, mesh, mat, pos, scl)
	return m


func _ghostify(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_ghostify(c)


func set_layer(l: int) -> void:
	layer = l
	_set_layers(self)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = layer
	for c in n.get_children():
		_set_layers(c)


## want_mode: "seed" / "water" (a = the tray or can, b = the glowing spot), "pick" (a = the fruit,
## b = the basket) or "" to hide. busy: the gardener is doing something (wait until they're idle).
func show_demo(want_mode: String, a: Vector3, b: Vector3, busy: bool, delta: float) -> void:
	if want_mode == "" or busy:
		visible = false
		idle_t = 0.0
		t = 0.0
		mode = want_mode
		return
	if want_mode != mode:
		mode = want_mode
		t = 0.0
	idle_t += delta
	if idle_t < 1.0:
		visible = false
		return
	visible = true
	var p := a
	var grip := 0.0
	var alpha := 0.55
	var tilt := -0.6
	var loop := 3.6 if mode == "water" else 3.0
	t = fmod(t + delta, loop)
	seed_ball.visible = false
	can.visible = false
	for d in drops:
		d.visible = false
	var start := a + Vector3(0.0, 0.9, 0.5)
	var at_a := a + Vector3(0.0, 0.25 if mode != "pick" else 0.05, 0.12)
	if mode == "water":
		at_a = a + Vector3(0.0, 0.55, 0.0)
	var over_b := b + Vector3(0.0, 0.9, 0.3)
	if t < 0.7:
		p = start.lerp(at_a, ease(t / 0.7, -1.8))
		alpha = 0.55 * minf(1.0, t / 0.3)
	elif t < 0.95:
		p = at_a
		grip = (t - 0.7) / 0.25
	elif t < 1.9:
		var k := ease((t - 0.95) / 0.95, -1.8)
		p = at_a.lerp(over_b, k) + Vector3.UP * sin(k * PI) * 0.4
		grip = 1.0
	else:
		grip = 1.0
		p = over_b
		var k2 := t - 1.9
		match mode:
			"seed":
				# Push it down into the soil, open, lift away.
				if k2 < 0.5:
					p = over_b.lerp(b + Vector3(0.0, 0.12, 0.1), ease(k2 / 0.5, -1.5))
				elif k2 < 0.75:
					p = b + Vector3(0.0, 0.12, 0.1)
					grip = 1.0 - (k2 - 0.5) / 0.25
				else:
					p = (b + Vector3(0.0, 0.12, 0.1)).lerp(over_b, (k2 - 0.75) / 0.35)
					grip = 0.0
					alpha = 0.55 * maxf(0.0, 1.0 - (k2 - 0.75) / 0.35)
			"water":
				# Tip the can: the spout goes down and water drops fall on the spot.
				tilt = -0.6 - 0.75 * minf(1.0, k2 / 0.4)
				p = over_b + Vector3(0.0, 0.0, 0.35)
				if k2 > 0.4:
					for i in drops.size():
						var dk := fmod(k2 * 1.6 + i * 0.33, 1.0)
						var d: MeshInstance3D = drops[i]
						d.visible = true
						d.global_position = b + Vector3(0.0, 0.7 * (1.0 - dk) + 0.05, 0.0)
				if k2 > 1.3:
					alpha = 0.55 * maxf(0.0, 1.0 - (k2 - 1.3) / 0.4)
			_:
				# Let go over the basket.
				grip = maxf(0.0, 1.0 - k2 / 0.3)
				alpha = 0.55 * maxf(0.0, 1.0 - (k2 - 0.4) / 0.5) if k2 > 0.4 else 0.55
	mat.albedo_color.a = alpha
	hand.global_transform = Transform3D(Basis(Vector3.RIGHT, tilt), p)
	for f in fingers:
		f.rotation.x = -grip * 1.1
	thumb.rotation.y = grip * 0.6
	var holding := t > 0.8 and grip > 0.5
	if mode == "seed" or mode == "pick":
		seed_ball.visible = holding
		seed_ball.global_position = hand.global_transform * Vector3(0, -0.12, -0.1)
		seed_ball.scale = Vector3(1.0, 0.8, 1.3) * (1.0 if mode == "seed" else 2.0)
	elif mode == "water":
		can.visible = t > 0.8
		can.global_transform = hand.global_transform * Transform3D(Basis(), Vector3(0.0, 0.0, 0.05))
