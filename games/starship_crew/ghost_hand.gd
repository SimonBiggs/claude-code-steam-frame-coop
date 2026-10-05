extends Node3D
## STARSHIP CREW practice for the VR pilot: SHOWS the move instead of text. A see-through glowing
## glove reaches for the flight stick, takes it and pushes it towards the glowing ring, then lets go,
## on a loop. It plays while the practice ring waits, and again whenever the pilot hasn't touched the
## stick for a long while. Host only (the VR player is the one who needs it).

const VrRig := preload("res://core/vr_rig.gd")
const CYCLE := 3.0

var glove: MeshInstance3D
var mat: StandardMaterial3D
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
	visible = false


## handle: the stick's handle; dir: which way to push (x right, y up), unit length or less.
## Returns the demo's stick tilt so the stick can move along with the glove.
func show_demo(on: bool, handle: Vector3, dir: Vector2, delta: float) -> Vector2:
	if not on:
		visible = false
		t = 0.0
		return Vector2.ZERO
	visible = true
	shown = true
	t = fmod(t + delta, CYCLE)
	var rest := handle + Vector3(0.06, -0.12, 0.2)
	var push := handle + Vector3(dir.x, dir.y, 0.0) * 0.09
	var p: Vector3
	var tilt := Vector2.ZERO
	if t < 0.7:  # reach for the stick
		p = rest.lerp(handle, ease(t / 0.7, 0.5))
	elif t < 1.0:  # hold it
		p = handle
	elif t < 1.8:  # push it towards the ring
		var k := ease((t - 1.0) / 0.8, -2.0)
		p = handle.lerp(push, k)
		tilt = dir * k
	elif t < 2.4:
		p = push
		tilt = dir
	else:  # let go
		p = push.lerp(rest, (t - 2.4) / 0.6)
	var a := 0.55 * minf(1.0, t / 0.3)
	if t > CYCLE - 0.4:
		a *= maxf(0.0, (CYCLE - t) / 0.4)
	mat.albedo_color.a = a
	glove.global_transform = Transform3D(Basis(Vector3.RIGHT, -0.5), p + Vector3(0.0, -0.02, 0.03))
	return tilt
