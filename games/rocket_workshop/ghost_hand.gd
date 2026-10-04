extends Node3D
## Simple mode: a see-through glowing hand that SHOWS the pilot what to do (instead of text).
## main calls play(points, delta) every frame with a path of [world position, grip] points
## (from panel.demo_path()): the hand fades in, follows the path (pressing a button, or grabbing a plug,
## the dial or the lever and moving it), fades out, waits a moment and starts again.
## An empty path hides it. Only the pilot sees it (main puts it on PANEL_LAYER).
## Cheap: six small unshaded meshes, one material.

const MOVE := 0.55  # seconds per path step
const HOLD := 0.2
const REST := 0.9  # pause between loops

var hand: Node3D
var index_finger: Node3D
var curled: Array[Node3D] = []
var mat: StandardMaterial3D
var t := 0.0


func _ready() -> void:
	top_level = true
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 1.0, 1.0, 0.5)
	mat.no_depth_test = false
	hand = Node3D.new()
	add_child(hand)
	# The fingertip is the hand's origin; the palm sits above it (+Y) and the finger points down (-Y).
	_part(hand, _sphere(0.045), Vector3(0, 0.1, 0.01), Vector3(1.0, 0.8, 1.2))  # palm
	index_finger = Node3D.new()
	index_finger.position = Vector3(0, 0.07, 0)
	hand.add_child(index_finger)
	_part(index_finger, _sphere(0.015), Vector3(0, -0.035, 0), Vector3(1.0, 2.4, 1.0))
	for i in 3:
		var f := Node3D.new()
		f.position = Vector3(-0.02 + i * 0.02, 0.07, 0.03)
		hand.add_child(f)
		_part(f, _sphere(0.014), Vector3(0, -0.012, 0), Vector3(1.0, 1.6, 1.0))
		curled.append(f)
	_part(hand, _sphere(0.016), Vector3(0.045, 0.09, -0.01), Vector3(1.0, 1.8, 1.0)).rotation.z = 0.7  # thumb
	visible = false


func _sphere(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	return sm


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func play(points: Array, delta: float) -> void:
	if points.is_empty():
		visible = false
		t = 0.0
		return
	visible = true
	var steps := points.size()
	var loop := steps * (MOVE + HOLD) + REST
	t = fmod(t + delta, loop)
	var k := t / (MOVE + HOLD)
	var i := mini(int(k), steps - 1)
	var f := clampf((k - i) * (MOVE + HOLD) / MOVE, 0.0, 1.0)
	var to: Array = points[i]
	var from: Array = points[maxi(i - 1, 0)]
	var a: Vector3 = from[0]
	var b: Vector3 = to[0]
	var pos := a.lerp(b, ease(f, -1.8)) if i > 0 else b
	var grip: bool = bool(to[1]) if f > 0.5 or i == 0 else bool(from[1])
	var alpha := 0.55
	if t < 0.25:
		alpha *= t / 0.25
	var end := steps * (MOVE + HOLD)
	if t > end:
		alpha *= maxf(0.0, 1.0 - (t - end) / 0.4)
	mat.albedo_color.a = alpha
	# Finger points down and a little away from the pilot, like reaching over the desk.
	hand.global_transform = Transform3D(Basis(Vector3.RIGHT, 0.5), pos)
	index_finger.scale = Vector3.ONE * (0.55 if grip else 1.0)
	for c in curled:
		c.rotation.x = -1.2 if grip else -0.4
