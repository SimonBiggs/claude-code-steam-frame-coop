extends Node3D
## SIMPLE_MODE practice for the VR pilot: SHOWS the move instead of text. A see-through glowing hand
## in the cockpit (in front of the pilot's own shoulder, sized to their head height):
## - "punch": a fist pulls back, then jabs fast towards the glowing practice target, again and again;
## - "beam": an open hand points at the far target, the trigger finger squeezes and a ghost beam pulses.
## main.gd calls show_move(kind, target) every frame while missions.gd has a practice target up, and
## show_move("", ...) to hide it. Only made on the VR pilot's machine.

const Data := preload("res://games/mech_titans/data.gd")
const CYCLE := 1.7

var main: Node
var hand: Node3D
var fingers: Array[Node3D] = []
var index_f: Node3D
var beam: MeshInstance3D
var mat: StandardMaterial3D
var beam_mat: StandardMaterial3D
var t := 0.0
var shown := false  ## bots: the demo has been on screen


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.95, 1.0, 0.5)
	hand = Node3D.new()
	add_child(hand)
	_part(hand, Vector3(0, 0, 0.01), Vector3(0.045, 0.022, 0.055))  # palm
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.03 + i * 0.02, 0.0, -0.045)
		hand.add_child(f)
		_part(f, Vector3(0, 0, -0.025), Vector3(0.009, 0.009, 0.028))
		fingers.append(f)
	index_f = fingers[0]
	var thumb := Node3D.new()
	thumb.position = Vector3(-0.045, 0.0, 0.0)
	thumb.rotation.y = 0.7
	hand.add_child(thumb)
	_part(thumb, Vector3(0, 0, -0.02), Vector3(0.01, 0.01, 0.024))
	beam_mat = mat.duplicate()
	beam_mat.albedo_color = Color(0.5, 0.95, 1.0, 0.4)
	beam = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.012
	c.bottom_radius = 0.012
	c.height = 1.0
	c.radial_segments = 6
	c.rings = 1
	beam.mesh = c
	beam.material_override = beam_mat
	beam.layers = Data.LAYER_VR_ONLY
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	visible = false


func _part(parent: Node3D, pos: Vector3, radii: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 10
	s.rings = 5
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	mi.layers = Data.LAYER_VR_ONLY
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## kind: "punch" / "beam" / "" (hide). target: world point of the practice target.
func show_move(kind: String, target: Vector3, delta: float) -> void:
	if kind == "" or main.vr_rig == null:
		visible = false
		t = 0.0
		return
	visible = true
	shown = true
	t = fmod(t + delta, CYCLE)
	var ck: Node3D = main.mech.cockpit
	var head: Vector3 = ck.to_local(main.vr_rig.camera.global_position)
	var tl := ck.to_local(target)
	var dir := (tl - head).normalized()
	var sx := -1.0 if tl.x < 0.0 else 1.0
	var a := 0.55 * minf(1.0, t / 0.25)
	if t > CYCLE - 0.3:
		a *= maxf(0.0, (CYCLE - t) / 0.3)
	mat.albedo_color.a = a
	var shoulder := head + Vector3(sx * 0.2, -0.3, 0.0)
	var p: Vector3
	var aim := dir
	if kind == "punch":
		var reach := 0.0
		if t < 0.55:
			reach = -0.06 * (t / 0.55)  # pull back
		elif t < 0.75:
			reach = lerpf(-0.06, 0.5, ease((t - 0.55) / 0.2, 0.4))  # fast jab
		elif t < 1.15:
			reach = 0.5
		else:
			reach = lerpf(0.5, 0.0, (t - 1.15) / (CYCLE - 1.15))
		p = shoulder + Vector3(0, 0.05, -0.12) + dir * reach
		for f in fingers:
			f.rotation.x = -1.5  # a fist
		beam.visible = false
	else:
		p = shoulder + Vector3(0, 0.08, -0.3)
		aim = (tl - p).normalized()
		for i in fingers.size():
			fingers[i].rotation.x = 0.0 if i == 0 else -1.5  # pointing with the first finger
		var squeeze := t > 0.5 and t < 1.3
		index_f.rotation.x = -0.35 if squeeze else 0.0
		beam.visible = squeeze
		if squeeze:
			var blen := 2.5
			beam.global_transform = ck.global_transform * Transform3D(_basis_y(aim).scaled_local(Vector3(1.0, blen, 1.0)), p + aim * (0.08 + blen * 0.5))
			beam_mat.albedo_color.a = 0.25 + 0.2 * sin(t * 30.0)
	var b := Basis.looking_at(aim, Vector3.UP) if absf(aim.y) < 0.98 else Basis()
	hand.global_transform = ck.global_transform * Transform3D(b, p)


static func _basis_y(up: Vector3) -> Basis:
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	return Basis(side, up, side.cross(up))
