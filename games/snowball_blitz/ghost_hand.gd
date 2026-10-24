extends Node3D
## Simple mode, VR practice: a see-through glowing hand that shows the thrower what to do instead of
## hint text. It loops: reach down to the snow, squeeze (a snowball appears), lift it back over the
## shoulder, swing towards the glowing target and let go (the ghost snowball flies off).
## Only the VR player's headset sees it (main puts it on their view-model layer). main calls show_demo()
## every frame; it fades in after the thrower has been idle for a moment.

const LOOP := 3.2

var hand: Node3D
var fingers: Array[Node3D] = []
var thumb: Node3D
var ball: MeshInstance3D
var mat: StandardMaterial3D
var ball_mat: StandardMaterial3D
var t := 0.0
var idle_t := 0.0
var fly_from := Vector3.ZERO
var fly_vel := Vector3.ZERO


func _ready() -> void:
	top_level = true
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.95, 1.0, 0.5)
	mat.no_depth_test = false
	ball_mat = mat.duplicate()
	ball_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.6)
	hand = Node3D.new()
	add_child(hand)
	# A real-size right hand, fingers pointing -Z, palm down.
	var palm := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.085, 0.028, 0.095)
	palm.mesh = pm
	palm.material_override = mat
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 10
	sm.rings = 5
	ball.mesh = sm
	ball.material_override = ball_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.top_level = true
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


## want: show the demo now. head: the headset position. aim: what to throw at.
func show_demo(want: bool, head: Vector3, aim: Vector3, delta: float) -> void:
	if not want:
		visible = false
		ball.visible = false
		idle_t = 0.0
		t = 0.0
		return
	idle_t += delta
	if idle_t < 1.5:
		visible = false
		ball.visible = false
		return
	t = fmod(t + delta, LOOP)
	var fwd := Vector3(aim.x - head.x, 0.0, aim.z - head.z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var feet_y := maxf(head.y - 1.15, 0.25)
	var low := head + fwd * 0.4 + right * 0.2 + Vector3.UP * (feet_y - head.y)  # down at the snow
	var start := low + Vector3.UP * 0.35
	var back := head + right * 0.25 - fwd * 0.12 + Vector3.UP * 0.02  # wound up beside the ear
	var out := head + right * 0.15 + fwd * 0.55 + Vector3.UP * 0.12  # arm out towards the target
	var p := start
	var grip := 0.0
	var alpha := 0.55
	var holding := false
	if t < 0.7:
		p = start.lerp(low, ease(t / 0.7, -1.8))
		alpha = 0.55 * minf(1.0, t / 0.3)
	elif t < 1.0:
		p = low
		grip = (t - 0.7) / 0.3  # squeeze: a snowball
		holding = t > 0.85
	elif t < 1.8:
		p = low.lerp(back, ease((t - 1.0) / 0.8, -1.8))
		grip = 1.0
		holding = true
	elif t < 2.15:
		p = back.lerp(out, ease((t - 1.8) / 0.35, 0.4))  # swing!
		grip = 1.0
		holding = true
	elif t < 2.35:
		p = out
		grip = 1.0 - (t - 2.15) / 0.2  # let go
		if fly_vel == Vector3.ZERO:
			fly_from = out + fwd * 0.08
			fly_vel = (aim - fly_from).normalized() * 9.0 + Vector3.UP * 2.0
	else:
		p = out
		alpha = 0.55 * maxf(0.0, 1.0 - (t - 2.35) / 0.5)
	visible = alpha > 0.01
	mat.albedo_color.a = alpha
	# Palm down, fingers pointing at the target.
	hand.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)
	for f in fingers:
		f.rotation.x = -grip * 1.3
	thumb.rotation.x = -grip * 0.7
	if holding:
		fly_vel = Vector3.ZERO
		ball.visible = true
		ball.global_position = p + Vector3.DOWN * 0.03 - hand.global_basis.z * 0.05
	elif fly_vel != Vector3.ZERO and t >= 2.15:
		var ft := t - 2.15
		ball.visible = ft < 0.9
		ball.global_position = fly_from + fly_vel * ft + Vector3.DOWN * 4.0 * ft * ft
	else:
		ball.visible = false
