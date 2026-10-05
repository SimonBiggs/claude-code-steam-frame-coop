extends Node3D
## The VR player's putter (host only). It hangs from the right glove along where the controller
## points, and its head always glides on the grass, so it fits any kid's height without calibration:
## the head goes where the pointing ray meets the ground (capped to a sensible reach). Its velocity
## at impact becomes the ball's velocity (generous sweet spot, gentle aim assist in main.gd).

const MeshKit := preload("res://core/mesh_kit.gd")
const Course := preload("res://games/mini_golf_party/course.gd")

const MAX_REACH := 0.9
const MIN_REACH := 0.08

var color := Color(0.35, 0.6, 1.0)
var head_pos := Vector3.ZERO
var head_vel := Vector3.ZERO
var flat_fwd := Vector3.FORWARD
var _shaft: MeshInstance3D
var _head: MeshInstance3D
var _prev := Vector3.INF


func _ready() -> void:
	top_level = true
	var sb := MeshKit.Builder.new()
	sb.cylinder(0.012, 0.012, 1.0, MeshKit.at(Vector3(0.0, 0.5, 0.0)), Color(0.85, 0.87, 0.9), 6)
	sb.cylinder(0.02, 0.02, 0.16, MeshKit.at(Vector3(0.0, 0.92, 0.0)), color.darkened(0.2), 8)
	_shaft = MeshKit.instance(sb.build(), false)
	add_child(_shaft)
	var hb := MeshKit.Builder.new()
	hb.rounded_box(Vector3(0.14, 0.05, 0.05), 0.015, MeshKit.at(Vector3.ZERO), color)
	hb.box(Vector3(0.012, 0.052, 0.052), MeshKit.at(Vector3.ZERO), Color.WHITE)
	_head = MeshKit.instance(hb.build(), false)
	add_child(_head)


## Every physics tick: follow the hand. floor_y: the ground under the head.
func follow(hand: Node3D, floor_y: float, delta: float) -> void:
	var hp := hand.global_position
	var dir := -hand.global_basis.z.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.05:
		flat = Vector3(-hand.global_basis.y.x, 0.0, -hand.global_basis.y.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	flat_fwd = flat
	var dy := maxf(0.0, hp.y - floor_y)
	var reach := clampf(dy * Vector2(dir.x, dir.z).length() / maxf(-dir.y, 0.2), MIN_REACH, MAX_REACH)
	var head := Vector3(hp.x, floor_y + Course.BALL_R, hp.z) + flat * reach
	if _prev != Vector3.INF and delta > 0.0:
		head_vel = head_vel.lerp((head - _prev) / delta, 0.6)
	_prev = head
	head_pos = head
	draw(hp, head)


## Draw the club from the grip to the head (also used on the TV machine from the snapshot).
func draw(grip: Vector3, head: Vector3) -> void:
	var d := head + Vector3.UP * 0.02 - grip
	var flat := Vector3(d.x, 0.0, d.z)
	flat = flat.normalized() if flat.length() > 0.01 else flat_fwd
	var basis := Basis()
	if d.length() > 0.01:
		var y := -d.normalized()
		var x := y.cross(flat).normalized() if absf(y.dot(flat)) < 0.99 else Vector3.RIGHT
		basis = Basis(x, y, x.cross(y)).orthonormalized()
	_shaft.global_transform = Transform3D(basis.scaled_local(Vector3(1.0, d.length(), 1.0)), head + Vector3.UP * 0.02)
	_head.global_transform = Transform3D(Basis(Vector3.UP, atan2(flat.x, flat.z)), head)


func hide_now(h: bool) -> void:
	visible = not h
	_prev = Vector3.INF
	head_vel = Vector3.ZERO
