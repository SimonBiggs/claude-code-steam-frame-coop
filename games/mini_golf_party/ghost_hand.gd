extends Node3D
## PRACTICE for the VR golfer: SHOWS the putting swing instead of telling it. A see-through glowing
## glove holding a see-through putter appears behind the player's ball, swings back slowly, then
## through the ball, again and again, while a glowing ring pulses under the ball. Shown on the first
## hole until the first putt, and again whenever the golfer hasn't putted for a while. Host only.

const MeshKit := preload("res://core/mesh_kit.gd")
const Course := preload("res://games/mini_golf_party/course.gd")
const CYCLE := 2.6

var shown := false  # bots: the demo has been on screen
var _t := 0.0
var _mat: StandardMaterial3D
var _hand: MeshInstance3D
var _club: MeshInstance3D
var _ring: MeshInstance3D


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.75, 1.0, 0.95, 0.5)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hb := MeshKit.Builder.new()
	hb.ellipsoid(Vector3(0.05, 0.025, 0.06), MeshKit.at(Vector3.ZERO), Color.WHITE, 10)
	for i in 4:
		hb.capsule(0.01, 0.07, MeshKit.at(Vector3(-0.03 + i * 0.02, -0.01, -0.06), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color.WHITE, 6)
	_hand = MeshKit.instance(hb.build(), false)
	_hand.material_override = _mat
	add_child(_hand)
	var cb := MeshKit.Builder.new()
	cb.cylinder(0.012, 0.012, 1.0, MeshKit.at(Vector3(0.0, 0.5, 0.0)), Color.WHITE, 6)
	cb.box(Vector3(0.14, 0.05, 0.05), MeshKit.at(Vector3.ZERO), Color.WHITE)
	_club = MeshKit.instance(cb.build(), false)
	_club.material_override = _mat
	add_child(_club)
	var rb := MeshKit.Builder.new()
	rb.torus(0.11, 0.015, MeshKit.at(Vector3.ZERO), Color(1.0, 0.95, 0.5), 20, 4, true)
	_ring = MeshKit.instance(rb.build(), false)
	add_child(_ring)
	visible = false


## want: show it now. ball: world position of the golfer's ball. fwd: flat direction to putt.
func show_demo(want: bool, ball: Vector3, fwd: Vector3, delta: float) -> void:
	if not want:
		visible = false
		_t = 0.0
		return
	visible = true
	shown = true
	_t = fmod(_t + delta, CYCLE)
	var ground := ball - Vector3.UP * Course.BALL_R
	_ring.global_position = ground + Vector3.UP * 0.01
	_ring.scale = Vector3.ONE * (1.0 + 0.15 * sin(_t * TAU / CYCLE * 2.0))
	# Swing: back slowly, then smoothly through the ball, then fade.
	var s := 0.0
	if _t < 1.1:
		s = -0.3 * ease(_t / 1.1, -1.6)
	elif _t < 1.6:
		s = lerpf(-0.3, 0.25, ease((_t - 1.1) / 0.5, 1.6))
	else:
		s = 0.25
	var a := 0.5
	if _t > CYCLE - 0.6:
		a *= maxf(0.0, (CYCLE - _t) / 0.6)
	_mat.albedo_color.a = a
	var head := ball + fwd * (s - 0.09)
	var grip := ball - fwd * 0.45 + Vector3.UP * 0.75 + fwd * s * 0.4
	var d := head - grip
	var y := -d.normalized()
	var x := y.cross(fwd).normalized()
	_club.global_transform = Transform3D(Basis(x, y, x.cross(y)).orthonormalized().scaled_local(Vector3(1.0, d.length(), 1.0)), head)
	# The club's head itself, turned across the swing (the box above is on the shaft's end).
	_hand.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.98 else fwd), grip)
