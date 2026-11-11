extends Node3D
## DOODLE'S FESTIVAL (deep.gd FESTIVAL): the fan club grows into a festival round the stage - every FEST_EVERY songs
## the band finishes (saved: save.data.songs) a new piece stands on the grass either side of the stage front:
## bunting, an ice-cream cart, a balloon arch, a striped tent, a string of lights, a carousel, a big wheel and a
## fireworks tower (it pops fireworks when the crowd is wild). Everything faces the crowd; the carousel and the big
## wheel turn slowly. Seen from every TV view and by the drummer looking out.
## Cheap: each piece is one merged mesh (core/mesh_kit.gd), the turning parts one more each.
##   set_pieces(n, pop)   (host: save.data.songs; every machine: the "fest" replicated state)
##   update(delta, energy)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/rhythm_band/deep.gd")

const STRIPES: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.95, 0.9)]
const BRIGHT: Array[Color] = [Color(1.0, 0.35, 0.4), Color(0.35, 0.75, 1.0), Color(1.0, 0.85, 0.25), Color(0.45, 0.95, 0.45),
	Color(0.85, 0.5, 1.0)]

var main
var pieces := 0
var nodes: Array[Node3D] = []
var spinners: Array[Node3D] = []  # [carousel top, wheel]
var t := 0.0
var pop_t := 0.0


func set_pieces(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.FESTIVAL.size())
	if n == pieces and nodes.size() == n:
		return
	var old := nodes.size()
	for i in range(n, nodes.size()):
		nodes[i].queue_free()
	nodes.resize(mini(old, n))
	for i in range(nodes.size(), n):
		var node := _build(i)
		add_child(node)
		nodes.append(node)
		if pop and i >= old:
			node.scale = Vector3.ONE * 0.01
			create_tween().tween_property(node, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pieces = n


func _build(i: int) -> Node3D:
	var id: String = Deep.FESTIVAL[i]
	var root := Node3D.new()
	root.name = "Fest_" + id
	var at: Vector3 = Deep.FEST_SPOTS[i]
	root.position = at
	# Face the middle of the crowd field (between the stage and the TV cameras).
	var to := Vector3(0.0, 0.0, -4.0) - at
	root.rotation.y = atan2(to.x, to.z)
	var b := MeshKit.Builder.new()
	match id:
		"bunting":  # two poles and two rows of little flags
			for s in [-1.0, 1.0]:
				b.cylinder(0.05, 0.06, 3.0, MeshKit.at(Vector3(s * 1.4, 1.5, 0)), Color(0.55, 0.35, 0.2), 6)
			for row in 2:
				for k in 9:
					var x := -1.2 + k * 0.3
					var y := 2.8 - row * 0.5 - 0.25 * sin(PI * (k + 0.5) / 9.0)
					b.cone(0.12, 0.25, MeshKit.at(Vector3(x, y - 0.12, 0), Vector3(1, 1, 0.2), Vector3(PI, 0, 0)), BRIGHT[(k + row) % BRIGHT.size()], 3)
		"icecream":  # a cart with a striped umbrella and a giant cone on top
			b.box(Vector3(1.4, 0.8, 0.8), MeshKit.at(Vector3(0, 0.7, 0)), Color(0.55, 0.85, 1.0))
			for s in [-1.0, 1.0]:
				b.cylinder(0.22, 0.22, 0.08, MeshKit.at(Vector3(s * 0.5, 0.25, 0.42), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.2, 0.2, 0.25), 12)
			b.cylinder(0.03, 0.03, 1.2, MeshKit.at(Vector3(0.4, 1.7, 0)), Color(0.8, 0.8, 0.85), 6)
			for k in 8:
				b.cone(0.9, 0.35, MeshKit.at(Vector3(0.4, 2.35, 0), Vector3(1, 1, 1), Vector3(0, k * TAU / 8.0, 0)), STRIPES[k % 2], 3)
			b.cone(0.18, 0.5, MeshKit.at(Vector3(-0.4, 1.35, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.9, 0.7, 0.4), 10)
			b.sphere(0.2, MeshKit.at(Vector3(-0.4, 1.65, 0)), Color(1.0, 0.7, 0.8), 10)
		"balloons":  # an arch of balloons
			for k in 15:
				var a := PI * k / 14.0
				b.sphere(0.28, MeshKit.at(Vector3(cos(a) * 1.8, 0.3 + sin(a) * 2.4, 0), Vector3(1, 1.15, 1)), BRIGHT[k % BRIGHT.size()], 10)
		"tent":  # a striped circus tent with a flag
			for k in 10:
				b.cylinder(1.3, 1.3, 1.6, MeshKit.at(Vector3(0, 0.8, 0), Vector3(1, 1, 1), Vector3(0, k * TAU / 10.0, 0)), STRIPES[k % 2], 3, false, false)
			b.cylinder(1.31, 1.31, 1.6, MeshKit.at(Vector3(0, 0.8, 0)), Color(1.0, 0.95, 0.9), 20)
			b.cone(1.6, 1.4, MeshKit.at(Vector3(0, 2.3, 0)), Color(1.0, 0.35, 0.4), 16)
			b.cylinder(0.03, 0.03, 0.8, MeshKit.at(Vector3(0, 3.3, 0)), Color(0.8, 0.8, 0.85), 6)
			b.box(Vector3(0.4, 0.25, 0.02), MeshKit.at(Vector3(0.2, 3.55, 0)), Color(1.0, 0.85, 0.25))
			b.box(Vector3(0.7, 1.1, 0.05), MeshKit.at(Vector3(0, 0.55, 1.3)), Color(0.25, 0.12, 0.2))  # the door
		"lights":  # a string of glowing lights on three poles
			for k in 3:
				b.cylinder(0.05, 0.06, 2.6, MeshKit.at(Vector3(-1.8 + k * 1.8, 1.3, 0)), Color(0.4, 0.4, 0.45), 6)
			for k in 13:
				var x := -1.8 + k * 0.3
				var y := 2.5 - 0.35 * sin(PI * fmod(k, 6.0) / 6.0)
				b.sphere(0.09, MeshKit.at(Vector3(x, y, 0)), BRIGHT[k % BRIGHT.size()], 8, true)
		"carousel":  # a carousel: a base, a striped roof, poles with horses (the top turns)
			b.cylinder(1.6, 1.7, 0.3, MeshKit.at(Vector3(0, 0.15, 0)), Color(0.85, 0.75, 0.55), 20)
			b.cylinder(0.15, 0.15, 2.4, MeshKit.at(Vector3(0, 1.4, 0)), Color(1.0, 0.85, 0.25), 10)
		"ferris":  # a big wheel on two legs (the wheel turns)
			for s in [-1.0, 1.0]:
				b.cylinder(0.08, 0.1, 4.6, MeshKit.at(Vector3(s * 1.2, 2.0, 0), Vector3.ONE, Vector3(0, 0, s * 0.27)), Color(0.85, 0.85, 0.9), 6)
			b.box(Vector3(3.2, 0.2, 1.0), MeshKit.at(Vector3(0, 0.1, 0)), Color(0.4, 0.4, 0.45))
		"fireworks":  # a tower of rockets
			b.box(Vector3(0.9, 0.5, 0.9), MeshKit.at(Vector3(0, 0.25, 0)), Color(0.3, 0.3, 0.38))
			for k in 4:
				var p := Vector3(-0.22 + (k % 2) * 0.44, 0.85, -0.22 + (k / 2) * 0.44)
				b.cylinder(0.08, 0.08, 0.7, MeshKit.at(p), BRIGHT[k], 8)
				b.cone(0.1, 0.25, MeshKit.at(p + Vector3(0, 0.47, 0)), Color(0.95, 0.95, 1.0), 8)
	var mi := MeshKit.instance(b.build(), false)
	root.add_child(mi)
	if id == "carousel":
		var top := Node3D.new()
		top.name = "Turn"
		var bt := MeshKit.Builder.new()
		for k in 12:
			bt.cone(1.8, 0.8, MeshKit.at(Vector3(0, 2.9, 0), Vector3.ONE, Vector3(0, k * TAU / 12.0, 0)), STRIPES[k % 2], 3)
		for k in 6:
			var a := k * TAU / 6.0
			var p := Vector3(cos(a) * 1.15, 0, sin(a) * 1.15)
			bt.cylinder(0.03, 0.03, 2.2, MeshKit.at(p + Vector3(0, 1.4, 0)), Color(0.9, 0.9, 0.95), 6)
			bt.box(Vector3(0.18, 0.3, 0.55), MeshKit.at(p + Vector3(0, 1.0 + 0.15 * (k % 2), 0), Vector3.ONE, Vector3(0, -a, 0)), BRIGHT[k % BRIGHT.size()])
			bt.sphere(0.1, MeshKit.at(p + Vector3(0, 1.25 + 0.15 * (k % 2), 0)), BRIGHT[k % BRIGHT.size()].lightened(0.2), 8)
		top.add_child(MeshKit.instance(bt.build(), false))
		root.add_child(top)
		spinners.append(top)
	elif id == "ferris":
		var wheel := Node3D.new()
		wheel.name = "Turn"
		wheel.position = Vector3(0, 4.2, 0)
		var bw := MeshKit.Builder.new()
		bw.cylinder(3.0, 3.0, 0.08, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.9, 0.9, 1.0), 20, false, false)
		bw.cylinder(2.92, 2.92, 0.1, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.9, 0.9, 1.0), 20, false, false)
		for k in 8:
			var a := k * TAU / 8.0
			bw.box(Vector3(0.06, 6.0, 0.06), MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, a)), Color(0.85, 0.85, 0.9))
			bw.box(Vector3(0.45, 0.4, 0.45), MeshKit.at(Vector3(cos(a) * 3.0, sin(a) * 3.0 - 0.3, 0)), BRIGHT[k % BRIGHT.size()])
			bw.sphere(0.1, MeshKit.at(Vector3(cos(a + 0.4) * 3.0, sin(a + 0.4) * 3.0, 0)), Color(1.0, 0.9, 0.5), 6, true)
		wheel.add_child(MeshKit.instance(bw.build(), false))
		root.add_child(wheel)
		spinners.append(wheel)
	return root


## Every frame on every machine: the carousel and the big wheel turn; the fireworks tower pops when the crowd is wild.
func update(delta: float, energy: float) -> void:
	t += delta
	for s in spinners:
		if is_instance_valid(s):
			if s.get_parent().name == "Fest_ferris":
				s.rotation.z += delta * 0.25
			else:
				s.rotation.y += delta * 0.6
	if pieces >= Deep.FESTIVAL.size() and energy > 0.75:
		pop_t -= delta
		if pop_t <= 0.0:
			pop_t = 5.0
			var root: Node3D = nodes[Deep.FESTIVAL.find("fireworks")]
			main.burst(root.global_position + Vector3(0, 6.0, 0), BRIGHT[int(t) % BRIGHT.size()], 30, false)


## Bots: what stands (piece ids).
func standing() -> Array:
	var out: Array = []
	for i in nodes.size():
		out.append(Deep.FESTIVAL[i])
	return out
