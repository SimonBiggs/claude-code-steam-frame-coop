extends Node3D
## Simple mode, VR practice: a see-through glowing pair of hands holding ghost reins that shows the
## rider what to do instead of hint text: "left" (both hands move left, the left one dips a little),
## "right", or "up" (both hands rise). It sits just in front of the rider's real hands (measured from
## their head, never from a calibrated rest pose), loops the move, and hides while the rider steers.
## A child of the dragon (dragon-local, the steady saddle frame). Only the rider's headset builds it.

const LOOP := 2.4

var main
var hands: Array[Node3D] = []
var reins: Array[MeshInstance3D] = []
var mat: StandardMaterial3D
var t := 0.0
var mode := ""
var alpha := 0.0


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.95, 1.0, 0.5)
	mat.no_depth_test = false
	for s in [-1.0, 1.0]:
		var h := Node3D.new()
		add_child(h)
		# A mitten: palm, thumb, and a fist round the reins.
		var palm := _part(h, main.sphere_mesh(0.05))
		palm.scale = Vector3(0.9, 0.75, 1.3)
		var thumb := _part(h, main.sphere_mesh(0.022))
		thumb.position = Vector3(-0.035 * s, 0.025, -0.02)
		hands.append(h)
		var r := _part(self, main.cyl_mesh(0.01, 0.01, 1.0, 4))
		reins.append(r)
	visible = false


func _part(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


## want: "left", "right", "up" or "" to hide. head: the rider's eyes (dragon-local).
## busy: the rider is steering right now (the demo fades out).
func show_demo(want: String, head: Vector3, busy: bool, delta: float) -> void:
	if want != mode:
		mode = want
		t = 0.0
	var target_a := 0.0 if want == "" or busy else 0.5
	alpha = move_toward(alpha, target_a, delta * 1.5)
	visible = alpha > 0.01
	if not visible:
		return
	t = fmod(t + delta, LOOP)
	# 0-0.3 s rest, 0.3-1.1 s move, hold to 1.8 s, back by 2.4 s.
	var k := 0.0
	if t > 0.3 and t < 1.1:
		k = ease((t - 0.3) / 0.8, -1.8)
	elif t >= 1.1 and t < 1.8:
		k = 1.0
	elif t >= 1.8:
		k = 1.0 - ease((t - 1.8) / 0.6, -1.8)
	var move := Vector3.ZERO
	var tilt := 0.0
	match mode:
		"left":
			move = Vector3(-0.22, 0.0, 0.0)
			tilt = 1.0
		"right":
			move = Vector3(0.22, 0.0, 0.0)
			tilt = -1.0
		"up":
			move = Vector3(0.0, 0.3, 0.0)
	mat.albedo_color.a = alpha
	var ring: Vector3 = main.dragon.REINS_RING
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		# Slightly further forward than real hands so the ghost never sits inside them.
		var rest := head + Vector3(0.2 * s, -0.42, -0.5)
		var p := rest + move * k + Vector3(0, 0.05 * tilt * s * k, 0)
		hands[i].position = p
		var d := p - ring
		var len := d.length()
		if len > 0.01:
			reins[i].transform = Transform3D(main.basis_y_to(d / len) * Basis.from_scale(Vector3(1.0, len, 1.0)), (p + ring) * 0.5)
