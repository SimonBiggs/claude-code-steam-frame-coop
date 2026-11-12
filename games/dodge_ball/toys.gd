extends Node3D
## SOFT DODGEBALL: TUMTUM'S PARK TOYS (deep.gd TOYS): every deep.gd TOY_EVERY finished rounds a big toy appears on the
## lawn beyond a side fence for good - a slide, a swing, a seesaw, a trampoline, a roundabout, a bouncy castle. Saved
## on the host (rounds) and sent as the "toys" state, so every machine draws the same park. The newest one bounces
## in. The swing swings, the seesaw rocks and the roundabout turns. One merged mesh per toy part: cheap.
##   set_count(n)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/dodge_ball/deep.gd")

const RED := Color(0.95, 0.3, 0.3)
const BLUE := Color(0.3, 0.55, 1.0)
const YELLOW := Color(1.0, 0.82, 0.25)
const GREEN := Color(0.35, 0.8, 0.4)
const METAL := Color(0.78, 0.8, 0.85)

var count := -1
var toys: Array[Node3D] = []
var movers: Array = []  # [node, kind]
var pop := 0.0
var _t := 0.0


func set_count(n: int) -> void:
	n = clampi(n, 0, Deep.TOYS.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	for t in toys:
		t.queue_free()
	toys.clear()
	movers.clear()
	for i in n:
		var p: Vector2 = Deep.TOY_SPOTS[i]
		var root := Node3D.new()
		root.name = "Toy%d" % i
		root.position = Vector3(p.x, 0.0, p.y)
		root.rotation.y = atan2(-p.x, 0.0)  # faces the court
		root.scale = Vector3.ONE * Deep.TOY_SCALE
		add_child(root)
		_build(root, String(Deep.TOYS[i].id))
		toys.append(root)
	if grew and not toys.is_empty():
		pop = 1.0


func _process(delta: float) -> void:
	_t += delta
	for m in movers:
		var n: Node3D = m[0]
		if not is_instance_valid(n):
			continue
		match String(m[1]):
			"swing":
				n.rotation.x = 0.45 * sin(_t * 1.8)
			"seesaw":
				n.rotation.x = 0.22 * sin(_t * 1.4)
			"roundabout":
				n.rotation.y += delta * 0.8
	if pop > 0.0 and not toys.is_empty():
		pop = move_toward(pop, 0.0, delta * 0.7)
		var s := 1.0 + absf(sin(pop * 10.0)) * 0.25 * pop
		toys[toys.size() - 1].scale = Vector3(s, 2.0 - s, s) * Deep.TOY_SCALE


func _part(parent: Node3D, b: MeshKit.Builder, at: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.add_child(MeshKit.instance(b.build(), false))
	parent.add_child(n)
	return n


## A toy, its front facing +Z (the court).
func _build(root: Node3D, kind: String) -> void:
	var b := MeshKit.Builder.new()
	match kind:
		"slide":
			b.box(Vector3(0.7, 0.08, 0.7), MeshKit.at(Vector3(0, 1.4, -0.6)), BLUE)  # the top
			for x in [-0.32, 0.32]:
				for z in [-0.92, -0.28]:
					b.cylinder(0.04, 0.04, 1.4, MeshKit.at(Vector3(x, 0.7, z)), METAL, 6)
			for k in 5:  # the ladder's steps
				b.box(Vector3(0.6, 0.04, 0.06), MeshKit.at(Vector3(0, 0.25 + 0.27 * k, -0.95)), METAL)
			b.box(Vector3(0.6, 0.06, 1.9), MeshKit.at(Vector3(0, 0.75, 0.5), Vector3.ONE, Vector3(-0.72, 0, 0)), YELLOW)  # the slide
			for x in [-0.31, 0.31]:
				b.box(Vector3(0.05, 0.14, 1.9), MeshKit.at(Vector3(x, 0.82, 0.5), Vector3.ONE, Vector3(-0.72, 0, 0)), RED)
			_part(root, b)
		"swing":
			for x in [-0.9, 0.9]:
				b.cylinder(0.05, 0.05, 2.0, MeshKit.at(Vector3(x, 1.0, -0.35), Vector3.ONE, Vector3(0.18, 0, 0)), RED, 6)
				b.cylinder(0.05, 0.05, 2.0, MeshKit.at(Vector3(x, 1.0, 0.35), Vector3.ONE, Vector3(-0.18, 0, 0)), RED, 6)
			b.cylinder(0.05, 0.05, 1.9, MeshKit.at(Vector3(0, 1.95, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), METAL, 8)
			_part(root, b)
			var seat := MeshKit.Builder.new()
			for x in [-0.22, 0.22]:
				seat.cylinder(0.012, 0.012, 1.45, MeshKit.at(Vector3(x, -0.72, 0)), METAL, 4)
			seat.box(Vector3(0.55, 0.06, 0.25), MeshKit.at(Vector3(0, -1.45, 0)), YELLOW)
			movers.append([_part(root, seat, Vector3(0, 1.95, 0)), "swing"])
		"seesaw":
			b.cylinder(0.18, 0.22, 0.4, MeshKit.at(Vector3(0, 0.2, 0)), RED, 10)
			_part(root, b)
			var plank := MeshKit.Builder.new()
			plank.box(Vector3(0.3, 0.07, 2.4), MeshKit.at(Vector3.ZERO), BLUE)
			for z in [-1.0, 1.0]:
				plank.box(Vector3(0.36, 0.1, 0.32), MeshKit.at(Vector3(0, 0.06, z)), YELLOW)
				plank.cylinder(0.025, 0.025, 0.4, MeshKit.at(Vector3(0, 0.25, z * 0.85), Vector3.ONE, Vector3(0, 0, PI * 0.5)), METAL, 6)
			movers.append([_part(root, plank, Vector3(0, 0.42, 0)), "seesaw"])
		"trampoline":
			b.torus(0.95, 0.08, MeshKit.at(Vector3(0, 0.55, 0)), BLUE, 24, 6)
			b.cylinder(0.92, 0.92, 0.03, MeshKit.at(Vector3(0, 0.55, 0)), Color(0.2, 0.22, 0.28), 24)
			for k in 6:
				var a := TAU * k / 6.0
				b.cylinder(0.04, 0.04, 0.55, MeshKit.at(Vector3(cos(a) * 0.9, 0.27, sin(a) * 0.9)), METAL, 6)
			_part(root, b)
		"roundabout":
			b.cylinder(0.15, 0.2, 0.25, MeshKit.at(Vector3(0, 0.12, 0)), METAL, 10)
			_part(root, b)
			var top := MeshKit.Builder.new()
			top.cylinder(1.0, 1.0, 0.1, MeshKit.at(Vector3.ZERO), YELLOW, 24)
			for k in 4:
				var a := TAU * k / 4.0
				var col: Color = [RED, BLUE, GREEN, RED][k]
				top.box(Vector3(0.9, 0.04, 0.12), MeshKit.at(Vector3(cos(a) * 0.45, 0.07, sin(a) * 0.45), Vector3.ONE, Vector3(0, -a, 0)), col)
				top.cylinder(0.03, 0.03, 0.6, MeshKit.at(Vector3(cos(a) * 0.8, 0.35, sin(a) * 0.8)), METAL, 6)
			top.torus(0.8, 0.03, MeshKit.at(Vector3(0, 0.65, 0)), METAL, 20, 4)
			movers.append([_part(root, top, Vector3(0, 0.3, 0)), "roundabout"])
		"castle":
			b.rounded_box(Vector3(1.9, 0.4, 1.9), 0.15, MeshKit.at(Vector3(0, 0.2, 0)), RED)
			for s in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
				var p := Vector3(0.85 * s[0], 0.0, 0.85 * s[1])
				b.cylinder(0.22, 0.25, 1.5, MeshKit.at(p + Vector3(0, 0.75, 0)), YELLOW, 12)
				b.cone(0.28, 0.4, MeshKit.at(p + Vector3(0, 1.7, 0)), BLUE, 12)
			b.rounded_box(Vector3(1.7, 0.9, 0.18), 0.08, MeshKit.at(Vector3(0, 0.85, -0.85)), BLUE)
			for x in [-0.85, 0.85]:
				b.rounded_box(Vector3(0.18, 0.9, 1.5), 0.08, MeshKit.at(Vector3(x, 0.85, 0)), GREEN)
			_part(root, b)
