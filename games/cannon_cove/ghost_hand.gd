extends Node3D
## Simple mode, VR practice: a see-through glowing hand that shows the gunner what to do, instead of
## hint text. It loops: reach to the cannon's glowing handle, squeeze, swing towards the target, let go.
## Only the gunner's headset sees it (main puts it on their view-model layer). main calls show_demo()
## every frame; it fades in after the gunner has been idle for a moment.

const LOOP := 3.0

var hand: Node3D
var fingers: Array[Node3D] = []
var thumb: Node3D
var mat: StandardMaterial3D
var t := 0.0
var idle_t := 0.0


func _ready() -> void:
	top_level = true
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.95, 1.0, 0.5)
	mat.no_depth_test = false
	hand = Node3D.new()
	add_child(hand)
	# A real-size right hand, fingers pointing -Z, palm down.
	var palm := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.085, 0.028, 0.095)
	palm.mesh = pm
	hand.add_child(palm)
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.03 + i * 0.02, 0.0, -0.047)
		hand.add_child(f)
		f.add_child(_capsule(0.009, 0.075))
		fingers.append(f)
	thumb = Node3D.new()
	thumb.position = Vector3(-0.045, -0.005, 0.015)
	thumb.rotation.y = 0.6
	hand.add_child(thumb)
	thumb.add_child(_capsule(0.011, 0.06))
	for n in [palm]:
		n.material_override = mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _capsule(r: float, h: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = h
	cap.radial_segments = 6
	cap.rings = 1
	m.mesh = cap
	m.rotation.x = PI / 2.0
	m.position.z = -h * 0.45
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## want: show the demo now. c: the gunner's cannon. aim: what to shoot (or ZERO).
func show_demo(want: bool, c, aim: Vector3, delta: float) -> void:
	if not want:
		visible = false
		idle_t = 0.0
		t = 0.0
		return
	idle_t += delta
	if idle_t < 1.5:
		visible = false
		return
	t = fmod(t + delta, LOOP)
	var handle: Vector3 = c.handle_world()
	var out: Vector3 = c.outboard
	var start := handle - out * 0.4 + Vector3.UP * 0.2
	# Swing: the handle end moves the opposite way to the muzzle (towards the target means the hand
	# goes the other way across, and down to lift the barrel).
	var swing := Vector3.DOWN * 0.06
	if aim != Vector3.ZERO:
		var to: Vector3 = aim - c.global_position
		var across: Vector3 = out.cross(Vector3.UP)
		swing += -across * clampf(to.dot(across) / maxf(1.0, to.length()), -1.0, 1.0) * 0.2
	var p := start
	var grip := 0.0
	var alpha := 0.55
	if t < 0.9:
		var k := ease(t / 0.9, -1.8)
		p = start.lerp(handle, k)
		alpha = 0.55 * minf(1.0, t / 0.3)
	elif t < 1.2:
		p = handle
		grip = (t - 0.9) / 0.3
	elif t < 2.1:
		p = handle + swing * ease((t - 1.2) / 0.9, -1.8)
		grip = 1.0
	elif t < 2.4:
		p = handle + swing
		grip = 1.0 - (t - 2.1) / 0.3  # let go: BOOM
	else:
		p = handle + swing
		alpha = 0.55 * maxf(0.0, 1.0 - (t - 2.4) / 0.5)
	visible = alpha > 0.01
	mat.albedo_color.a = alpha
	# Palm down, fingers pointing out to sea, sitting just above the handle.
	hand.global_transform = Transform3D(Basis.looking_at(out, Vector3.UP), p + Vector3.UP * 0.03)
	for f in fingers:
		f.rotation.x = -grip * 1.3
	thumb.rotation.x = -grip * 0.7
