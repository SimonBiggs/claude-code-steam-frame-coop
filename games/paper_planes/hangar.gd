extends Node3D
## PIP'S HANGAR beyond the valley (deep.gd HANGAR): a round-roofed paper shed, paper planes parked in rows in front,
## a windsock and a flag, then a sky trail of paper planes circling high over the valley. It grows one piece every
## Deep.HANGAR_EVERY stamps (from net state "hangar": every machine builds the same); a new piece pops in.

const MeshKit := preload("res://core/mesh_kit.gd")
const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/paper_planes/deep.gd")
const Meshes := preload("res://games/paper_planes/meshes.gd")

const SHED_COLOR := Color(0.95, 0.55, 0.3)
const TRAIL_SPEED := 0.12  # rad/s round the sky trail

var main
var shown := -1
var pieces: Array = []  # [Node3D]
var trail: Array = []  # [[node, start angle, height]]
var clock := 0.0


func _ready() -> void:
	name = "Hangar"


## Every machine: build up to n pieces (the ones beyond what's shown pop in, with a burst when it grew just now).
func show_pieces(n: int) -> void:
	n = clampi(n, 0, Deep.HANGAR.size())
	if n == shown:
		return
	var grew := shown >= 0 and n > shown
	for p in pieces:
		if is_instance_valid(p):
			(p as Node).queue_free()
	pieces.clear()
	trail.clear()
	for i in n:
		var node := _piece(i)
		add_child(node)
		pieces.append(node)
		if grew and i >= shown:
			var target := node.scale
			node.scale = target * 0.2
			var tw := node.create_tween()
			tw.tween_property(node, "scale", target, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if grew and main != null:
		var at := Deep.hangar_spot(n - 1)
		main.burst(at + Vector3.UP * 2.0, Meshes.RAINBOW, 40, 1.0)
		main.sfx.play_at("achievement", at, 0.0)
	shown = n


func _piece(i: int) -> Node3D:
	var kind := Deep.HANGAR[i]
	var at := Deep.hangar_spot(i)
	var root := Node3D.new()
	root.name = "Hangar_%s_%d" % [kind, i]
	root.position = at
	root.rotation.y = Deep.HANGAR_YAW
	match kind:
		"shed":
			var b := MeshKit.Builder.new()
			b.box(Vector3(6.0, 2.2, 4.0), MeshKit.at(Vector3(0.0, 1.1, 0.0)), SHED_COLOR)
			b.cylinder(3.0, 3.0, 4.0, MeshKit.at(Vector3(0.0, 2.2, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), SHED_COLOR.lightened(0.15), 16)
			b.box(Vector3(3.0, 2.0, 0.1), MeshKit.at(Vector3(0.0, 1.0, 2.02)), Color(0.25, 0.22, 0.3))
			b.box(Vector3(6.2, 0.15, 4.2), MeshKit.at(Vector3(0.0, 0.07, 0.0)), Color(0.75, 0.7, 0.62))
			root.add_child(MeshKit.instance(b.build(), true))
			var big := _plane_mesh(Color(1.0, 0.95, 0.6), 2.2)  # the big sign plane on the roof
			big.position = Vector3(0.0, 5.4, 0.6)
			big.rotation = Vector3(0.0, PI, 0.0)
			root.add_child(big)
		"windsock":
			var b2 := MeshKit.Builder.new()
			b2.cylinder(0.06, 0.06, 3.6, MeshKit.at(Vector3(0.0, 1.8, 0.0)), Color(0.85, 0.85, 0.88), 8)
			b2.cone(0.3, 1.4, MeshKit.at(Vector3(0.7, 3.4, 0.0), Vector3.ONE, Vector3(0.0, 0.0, PI * 0.5)), Color(1.0, 0.5, 0.2), 10)
			root.add_child(MeshKit.instance(b2.build(), false))
		"flag":
			var b3 := MeshKit.Builder.new()
			b3.cylinder(0.06, 0.06, 4.0, MeshKit.at(Vector3(0.0, 2.0, 0.0)), Color(0.85, 0.85, 0.88), 8)
			b3.box(Vector3(1.2, 0.8, 0.04), MeshKit.at(Vector3(0.65, 3.5, 0.0)), Color(0.35, 0.6, 1.0))
			b3.star(5, 0.3, 0.13, 0.05, MeshKit.at(Vector3(0.65, 3.5, 0.04)), Color(1.0, 0.85, 0.25))
			root.add_child(MeshKit.instance(b3.build(), false))
		"trail":
			var k := trail.size()
			var pl := _plane_mesh(Meshes.HOOP_COLORS[(k * 2 + 1) % Meshes.HOOP_COLORS.size()].lerp(Color.WHITE, 0.3), 1.4)
			root.add_child(pl)
			var a := atan2(at.z - Deep.TRAIL_AT.z, at.x - Deep.TRAIL_AT.x)
			trail.append([root, a, at.y])
		_:  # a parked paper plane on a little stand
			var n := pieces.size()
			var pl2 := _plane_mesh(Meshes.HOOP_COLORS[n % Meshes.HOOP_COLORS.size()].lerp(Color.WHITE, 0.25), 1.3)
			pl2.position = Vector3(0.0, 0.55, 0.0)
			pl2.rotation = Vector3(0.12, PI, 0.0)
			root.add_child(pl2)
			var b4 := MeshKit.Builder.new()
			b4.cylinder(0.05, 0.08, 0.5, MeshKit.at(Vector3(0.0, 0.25, 0.0)), Color(0.6, 0.45, 0.3), 6)
			root.add_child(MeshKit.instance(b4.build(), false))
	return root


func _plane_mesh(col: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.plane()
	mi.material_override = Meshes.plane_material(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	Contrast.outline(mi, Meshes.OUTLINE)
	return mi


func _process(delta: float) -> void:
	clock += delta
	for tr in trail:
		var node: Node3D = tr[0]
		if not is_instance_valid(node):
			continue
		var a := float(tr[1]) + clock * TRAIL_SPEED
		node.position = Deep.TRAIL_AT + Vector3(cos(a) * Deep.TRAIL_R, float(tr[2]) - Deep.TRAIL_AT.y + sin(clock + a) * 0.3, sin(a) * Deep.TRAIL_R)
		node.rotation = Vector3(0.0, -a + PI, 0.25)  # nose along the circle, banking in
