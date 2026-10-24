extends Node3D
## Simple mode, VR practice: a see-through glowing hand that shows the chef what to do, instead of
## hint text. Two loops:
##  - "chop": a ghost knife hand hovers over the ingredient and swings DOWN through it, twice.
##  - "stack": the hand reaches the ingredient, closes, carries it over to the plate and lets go.
## Only the chef's headset sees it (main puts it on the chef's view-model layer). main calls show_demo()
## every frame; it fades in after the chef has been idle for a moment.

const CHOP_LOOP := 2.2
const STACK_LOOP := 2.8

var hand: Node3D
var knife: Node3D
var fingers: Array[Node3D] = []
var thumb: Node3D
var mat: StandardMaterial3D
var t := 0.0
var idle_t := 0.0
var mode := ""


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
	# The ghost knife (same place as the chef's real one: the blade sticks out 7-29 cm in front).
	knife = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.008, 0.05, 0.22)
	knife.mesh = bm
	knife.material_override = mat
	knife.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	knife.position = Vector3(0, -0.012, -0.18)
	hand.add_child(knife)
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


## want_mode: "chop" (a = the ingredient), "stack" (a = the ingredient, b = the plate) or "" to hide.
## busy: the chef just did something (the demo waits until they've been idle a moment).
func show_demo(want_mode: String, a: Vector3, b: Vector3, busy: bool, delta: float) -> void:
	if want_mode == "" or busy:
		visible = false
		idle_t = 0.0 if busy or want_mode == "" else idle_t
		t = 0.0
		mode = want_mode
		return
	if want_mode != mode:
		mode = want_mode
		t = 0.0
	idle_t += delta
	if idle_t < 1.2:
		visible = false
		return
	var p := a
	var grip := 0.0
	var alpha := 0.55
	var tilt := 0.0
	if mode == "chop":
		t = fmod(t + delta, CHOP_LOOP)
		knife.visible = true
		var top := a + Vector3(0, 0.3, 0.18)
		var low := a + Vector3(0, -0.02, 0.18)
		var k := fmod(t, 1.1)
		if k < 0.6:
			p = low.lerp(top, ease(k / 0.6, -1.6))  # lift up
			tilt = -0.5 * (k / 0.6)
		else:
			p = top.lerp(low, ease((k - 0.6) / 0.25, 2.5) if k < 0.85 else 1.0)  # CHOP!
			tilt = -0.5 + 0.8 * minf(1.0, (k - 0.6) / 0.25)
		grip = 1.0
		alpha = 0.55 * minf(1.0, t / 0.3)
	else:
		t = fmod(t + delta, STACK_LOOP)
		knife.visible = false
		var start := a + Vector3(0, 0.25, 0.15)
		var at_item := a + Vector3(0, 0.06, 0.06)
		var at_plate := b + Vector3(0, 0.1, 0.06)
		if t < 0.7:
			p = start.lerp(at_item, ease(t / 0.7, -1.8))
			alpha = 0.55 * minf(1.0, t / 0.3)
		elif t < 0.95:
			p = at_item
			grip = (t - 0.7) / 0.25
		elif t < 1.9:
			var k2 := ease((t - 0.95) / 0.95, -1.8)
			p = at_item.lerp(at_plate, k2) + Vector3.UP * sin(k2 * PI) * 0.15
			grip = 1.0
		elif t < 2.2:
			p = at_plate
			grip = 1.0 - (t - 1.9) / 0.3  # let go
		else:
			p = at_plate
			alpha = 0.55 * maxf(0.0, 1.0 - (t - 2.2) / 0.5)
	visible = alpha > 0.01
	mat.albedo_color.a = alpha
	hand.global_transform = Transform3D(Basis(Vector3.RIGHT, tilt), p)
	for f in fingers:
		f.rotation.x = -grip * 1.3
	thumb.rotation.x = -grip * 0.7
