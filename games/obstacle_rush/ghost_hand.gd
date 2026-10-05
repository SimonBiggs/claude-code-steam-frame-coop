extends Node3D
## OBSTACLE RUSH practice for the VR giant: SHOWS the move instead of text. A see-through glowing
## glove dips into the ball bucket, picks up a ball, swings and throws it in an arc onto the glowing
## target on the course. It loops on the first course until the giant throws a ball, and comes back
## whenever they haven't thrown anything for a while. Host only (the VR player is the one who needs it).

const VrRig := preload("res://core/vr_rig.gd")
const CYCLE := 3.6

var giant: Node
var glove: MeshInstance3D
var ball: MeshInstance3D
var mat: StandardMaterial3D
var ball_mat: StandardMaterial3D
var t := 0.0
var shown := false  ## bots: the demo has been on screen


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.95, 0.5)
	glove = MeshInstance3D.new()
	glove.mesh = VrRig.glove_mesh(false, Color.WHITE, Color.WHITE)
	glove.material_override = mat
	glove.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glove)
	ball_mat = mat.duplicate()
	ball_mat.albedo_color = Color(1.0, 0.95, 0.5, 0.6)
	ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	ball.mesh = sm
	ball.material_override = ball_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	visible = false


## from: the ball in the bucket; to: where it should land.
func show_demo(on: bool, from: Vector3, to: Vector3, delta: float) -> void:
	if not on:
		visible = false
		t = 0.0
		return
	visible = true
	shown = true
	t = fmod(t + delta, CYCLE)
	var s: float = giant.S
	var above := from + Vector3(0.0, 2.5, 0.0)
	var wind := from + Vector3(0.0, 3.0, 2.0)  # back towards you
	var rel := from.lerp(to, 0.25) + Vector3(0.0, 4.0, 0.0)
	var p: Vector3
	var carry := true
	var bp := from
	if t < 0.6:  # reach down into the bucket
		p = above.lerp(from, ease(t / 0.6, 0.5))
		carry = false
	elif t < 0.9:  # grab
		p = from
		carry = t > 0.75
	elif t < 1.5:  # lift and wind back
		p = from.lerp(wind, ease((t - 0.9) / 0.6, -2.0))
	elif t < 1.9:  # swing forward
		p = wind.lerp(rel, ease((t - 1.5) / 0.4, 2.0))
	else:  # let go: the ball flies to the target
		p = rel + Vector3(0.0, 0.3, 0.0) * (t - 1.9)
		carry = false
		var k := clampf((t - 1.9) / 1.0, 0.0, 1.0)
		bp = rel.lerp(to, k) + Vector3(0.0, sin(k * PI) * 2.0, 0.0)
	if carry:
		bp = p + Vector3(0.0, -0.1 * s * 0.05, 0.0)
	var a := 0.55 * minf(1.0, t / 0.3)
	if t > CYCLE - 0.5:
		a *= maxf(0.0, (CYCLE - t) / 0.5)
	mat.albedo_color.a = a
	ball_mat.albedo_color.a = a * 1.1
	var dir := to - from
	dir.y = 0.0
	var yaw := atan2(-dir.x, -dir.z) if dir.length() > 0.01 else 0.0
	glove.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), p + Vector3(0.0, 0.2, 0.0))
	ball.visible = t > 0.75 or t < 0.6
	ball.global_position = bp if t >= 0.6 else from
