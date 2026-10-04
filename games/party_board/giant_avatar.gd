extends Node3D
## The VR player as the TV sees them: a GIANT leaning over Party Island. The host sends the head and
## both hands in board units (main.make_snapshot: 3 x [x, y, z, qx, qy, qz, qw]); this node lives
## under main's stage (board units) and shows a big friendly head with a visor and a party hat plus two
## huge gloves (core/vr_rig.gd's meshes, scaled from metres to board units), smoothly following.
## `head` is what the TV's VR bubble camera rides on.

const VrRig := preload("res://core/vr_rig.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

var main: Node
var head: Node3D
var hands: Array[Node3D] = []
var smoothing := 14.0
var _scale := 1.0
var _target: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D()]
var _has_pose := false


func _ready() -> void:
	name = "Giant"
	_scale = 1.0 / float(main.S_VR)
	var mat := VrRig.vertex_color_material()
	head = Node3D.new()
	head.name = "GiantHead"
	add_child(head)
	var face := MeshInstance3D.new()
	face.mesh = VrRig.VrRigStatics.head_mesh(Color(0.3, 0.7, 1.0))
	face.material_override = mat
	face.layers = VrRig.AVATAR_LAYER
	head.add_child(face)
	var b := MeshKit.Builder.new()
	b.cone(0.075, 0.17, MeshKit.at(Vector3(0, 0.2, 0.0), Vector3.ONE, Vector3(-0.25, 0, 0)), Color(1.0, 0.45, 0.6), 12)
	b.sphere(0.025, MeshKit.at(Vector3(0, 0.29, 0.03)), Color(1.0, 0.95, 0.5), 8, true)
	var hat := MeshKit.instance(b.build(), false)
	hat.layers = VrRig.AVATAR_LAYER
	head.add_child(hat)
	for i in 2:
		var h := Node3D.new()
		h.name = "GiantHand%d" % i
		add_child(h)
		var g := MeshInstance3D.new()
		g.mesh = VrRig.glove_mesh(i == 0, Color(1.0, 0.86, 0.6), Color.WHITE)
		g.material_override = mat
		h.add_child(g)
		hands.append(h)
	visible = false


## Feed the pose from the host's snapshot (board units).
func apply_pose(p: PackedFloat32Array) -> void:
	if p.size() < 21:
		visible = false
		_has_pose = false
		return
	for i in 3:
		var o := i * 7
		var q := Quaternion(p[o + 3], p[o + 4], p[o + 5], p[o + 6]).normalized()
		_target[i] = Transform3D(Basis(q).scaled(Vector3.ONE * _scale), Vector3(p[o], p[o + 1], p[o + 2]))
	if not _has_pose:
		_has_pose = true
		visible = true
		head.transform = _target[0]
		for i in 2:
			hands[i].transform = _target[i + 1]


## A glove's position in board units (minigames on the TV machine use it for effects).
func hand_pos(which: int) -> Vector3:
	return hands[clampi(which, 0, 1)].position


func _process(delta: float) -> void:
	if not _has_pose:
		return
	var k := 1.0 - exp(-smoothing * delta)
	head.transform = head.transform.interpolate_with(_target[0], k)
	for i in 2:
		hands[i].transform = hands[i].transform.interpolate_with(_target[i + 1], k)
