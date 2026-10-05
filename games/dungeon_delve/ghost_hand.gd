extends Node3D
## DUNGEON DELVE practice for the VR knight: SHOWS the move instead of text. A see-through glowing
## glove holding a see-through sword swings right through the target (the practice dummy, or later
## the nearest monster if the knight hasn't hit anything for a while), on a loop. Host only.

const VrRig := preload("res://core/vr_rig.gd")
const VrHands := preload("res://games/dungeon_delve/vr_hands.gd")
const CYCLE := 2.4

var hand: Node3D
var mat: StandardMaterial3D
var t := 0.0
var shown := false  ## bots: the demo has been on screen


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.95, 0.5)
	hand = Node3D.new()
	add_child(hand)
	for m: Mesh in [VrRig.glove_mesh(false, Color.WHITE, Color.WHITE), VrHands.sword_mesh()]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(mi)
	visible = false


## target: the point to slice through; from: where the knight's head is (the swing comes from there).
func show_demo(on: bool, target: Vector3, from: Vector3, delta: float) -> void:
	if not on:
		visible = false
		t = 0.0
		return
	visible = true
	shown = true
	t = fmod(t + delta, CYCLE)
	var to_t := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var yaw := atan2(-to_t.x, -to_t.z) if to_t.length() > 0.1 else 0.0
	var b := Basis(Vector3.UP, yaw)
	# The hand stays ~0.55 m in front of the target's near side so the blade passes through it.
	var near := target + b * Vector3(0.0, 0.0, 0.6)
	var start := near + b * Vector3(0.5, 0.3, 0.0)
	var end := near + b * Vector3(-0.5, -0.15, 0.0)
	var p: Vector3
	var sweep := 0.0
	if t < 0.8:  # raise the sword
		p = start
		sweep = 0.7
	elif t < 1.15:  # SWING
		var k := ease((t - 0.8) / 0.35, 0.4)
		p = start.lerp(end, k)
		sweep = lerpf(0.7, -0.7, k)
	elif t < 1.6:
		p = end
		sweep = -0.7
	else:  # back up
		var k2 := (t - 1.6) / (CYCLE - 1.6)
		p = end.lerp(start, k2)
		sweep = lerpf(-0.7, 0.7, k2)
	var a := 0.55 * minf(1.0, t / 0.3)
	if t > CYCLE - 0.3:
		a *= maxf(0.0, (CYCLE - t) / 0.3)
	mat.albedo_color.a = a
	hand.global_transform = Transform3D(b * Basis(Vector3.UP, sweep) * Basis(Vector3.RIGHT, -0.15), p)
