extends Node3D
## CRYSTAL SAGA practice for the VR hero: SHOWS the move instead of text, on a loop. A see-through
## glowing glove does it in front of you:
##   "swing"   - holding a see-through sword, it slices through the target (the training dummy, or
##               later the nearest monster if the hero hasn't hit anything for a while);
##   "fire"    - the LEFT glove with its little flame rises from shoulder height to above the head;
##   "thunder" - the RIGHT glove with the sword rises above the head, the blade pointing at the sky.
## The raise demos float ~0.8 m in front of the hero's eyes so they're easy to see. Host only.

const VrRig := preload("res://core/vr_rig.gd")
const VrHands := preload("res://games/crystal_saga/vr_hands.gd")
const CYCLE := 2.4

var right: Node3D  ## glove + sword
var left: Node3D  ## glove + flame
var mat: StandardMaterial3D
var t := 0.0
var shown := {}  ## bots: mode -> true once on screen


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.95, 0.5)
	right = _part([VrRig.glove_mesh(false, Color.WHITE, Color.WHITE), VrHands.sword_mesh()])
	left = _part([VrRig.glove_mesh(true, Color.WHITE, Color.WHITE), VrHands.flame_mesh()])
	visible = false


func _part(meshes: Array) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	for m: Mesh in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	return n


## mode: "" (hidden), "swing", "fire" or "thunder". target: what to slice (swing). head/yaw: the hero.
func show_demo(mode: String, target: Vector3, head: Vector3, yaw: float, delta: float) -> void:
	if mode == "":
		visible = false
		t = 0.0
		return
	visible = true
	shown[mode] = true
	t = fmod(t + delta, CYCLE)
	var a := 0.55 * minf(1.0, t / 0.3)
	if t > CYCLE - 0.3:
		a *= maxf(0.0, (CYCLE - t) / 0.3)
	mat.albedo_color.a = a
	right.visible = mode != "fire"
	left.visible = mode == "fire"
	if mode == "swing":
		_swing(target, head)
		return
	# Raise: from shoulder height up above the head, in front of the hero.
	var b := Basis(Vector3.UP, yaw)
	var side := -0.25 if mode == "fire" else 0.25
	var low := head + b * Vector3(side, -0.45, -0.85)
	var high := head + b * Vector3(side * 1.2, 0.3, -0.95)
	var k := 0.0
	if t < 0.5:
		k = 0.0
	elif t < 1.1:
		k = ease((t - 0.5) / 0.6, -2.0)
	elif t < 1.9:
		k = 1.0
	else:
		k = 1.0 - (t - 1.9) / (CYCLE - 1.9)
	var p := low.lerp(high, k)
	var n := left if mode == "fire" else right
	# Point the glove forward when low and up at the sky when raised.
	n.global_transform = Transform3D(b * Basis(Vector3.RIGHT, lerpf(0.0, PI * 0.5, k)), p)


func _swing(target: Vector3, from: Vector3) -> void:
	var to_t := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var yaw := atan2(-to_t.x, -to_t.z) if to_t.length() > 0.1 else 0.0
	var b := Basis(Vector3.UP, yaw)
	var near := target + b * Vector3(0.0, 0.0, 0.6)
	var start := near + b * Vector3(0.5, 0.3, 0.0)
	var end := near + b * Vector3(-0.5, -0.15, 0.0)
	var p: Vector3
	var sweep := 0.0
	if t < 0.8:
		p = start
		sweep = 0.7
	elif t < 1.15:
		var k := ease((t - 0.8) / 0.35, 0.4)
		p = start.lerp(end, k)
		sweep = lerpf(0.7, -0.7, k)
	elif t < 1.6:
		p = end
		sweep = -0.7
	else:
		var k2 := (t - 1.6) / (CYCLE - 1.6)
		p = end.lerp(start, k2)
		sweep = lerpf(-0.7, 0.7, k2)
	right.global_transform = Transform3D(b * Basis(Vector3.UP, sweep) * Basis(Vector3.RIGHT, -0.15), p)
