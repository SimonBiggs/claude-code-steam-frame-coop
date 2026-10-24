extends Node3D
## SIMPLE_MODE practice: SHOWS how to play instead of text. A pair of see-through glowing hands come
## down onto the board's two handles, curl their fingers round them (grip) and tilt the board the way
## the practice ring is (one hand up, one down / both pushed), while a glowing ghost marble rolls from
## the start into the ring. Loops every few seconds until the giant grabs a handle.
## The hands only show for a VR giant; the ghost marble shows on every screen (it teaches the TV players
## too). main calls show_demo() every frame.

const CYCLE := 3.6

var main
var hands: Array[Node3D] = []
var fingers: Array = [[], []]
var mat: StandardMaterial3D
var marble: MeshInstance3D
var marble_mat: StandardMaterial3D
var t := 0.0
var idle_t := 0.0
var shown_hands := false  # bots: the hands have been on screen


func _ready() -> void:
	top_level = true
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.9, 0.5)
	for side in 2:
		var h := Node3D.new()
		add_child(h)
		hands.append(h)
		_part(h, _sphere(0.042), Vector3(0, 0.03, 0), Vector3(1.0, 0.55, 1.25))  # palm, resting on top
		for i in 4:
			var f := Node3D.new()
			f.position = Vector3(0.0, 0.03, -0.045 + i * 0.03)
			# Fingers hang off the outer side of the handle and curl under it.
			f.rotation.z = 0.0
			h.add_child(f)
			fingers[side].append(f)
			var m := _part(f, _sphere(0.011), Vector3(0.03 * (1.0 if side == 1 else -1.0), 0, 0), Vector3(2.4, 1.0, 1.0))
			m.name = "Finger"
		var thumb := _part(h, _sphere(0.012), Vector3(-0.03 * (1.0 if side == 1 else -1.0), 0.02, 0.05), Vector3(2.0, 1.0, 1.0))
		thumb.name = "Thumb"
	marble_mat = mat.duplicate()
	marble_mat.albedo_color = Color(1.0, 1.0, 0.6, 0.6)
	marble = MeshInstance3D.new()
	marble.mesh = _sphere(0.028)
	marble.material_override = marble_mat
	marble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.board.add_child(marble)
	visible = false
	marble.visible = false


func _sphere(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	return sm


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## on: practice is running. vr: the giant is in a headset. busy: they're holding a handle right now
## (the demo hides and waits). from / to: the start and the practice ring (board-local).
func show_demo(on: bool, vr: bool, busy: bool, from: Vector2, to: Vector2, delta: float) -> void:
	if not on or busy:
		visible = false
		marble.visible = false
		idle_t = 0.0
		t = 0.0
		return
	idle_t += delta
	if idle_t < 1.0:
		visible = false
		marble.visible = false
		return
	t = fmod(t + delta, CYCLE)
	var alpha := 0.55 * minf(1.0, t / 0.4)
	if t > CYCLE - 0.5:
		alpha *= maxf(0.0, (CYCLE - t) / 0.5)
	mat.albedo_color.a = alpha
	# The ghost marble rolls from the start to the ring while the hands tilt.
	var k := ease(clampf((t - 1.1) / 1.8, 0.0, 1.0), -1.6)
	var p := from.lerp(to, k)
	marble.visible = true
	marble.position = Vector3(p.x, 0.03, p.y)
	marble_mat.albedo_color.a = 0.7 * minf(1.0, t / 0.4) * (1.0 if t < CYCLE - 0.5 else maxf(0.0, (CYCLE - t) / 0.5))
	visible = vr
	if not vr:
		return
	shown_hands = true
	# Tilt: to roll marbles +x, the right hand goes down and the left hand up; to roll them towards the
	# giant (+z), both hands pull back (see tilter.gd).
	var dir := (to - from).normalized()
	var tilt_k := ease(clampf((t - 0.9) / 0.8, 0.0, 1.0), -1.6)
	var grip := clampf((t - 0.45) / 0.4, 0.0, 1.0)
	var down := 1.0 - clampf(t / 0.45, 0.0, 1.0)  # hands come down onto the handles
	var board: Node3D = main.board
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var base: Vector3 = board.handle_world(side)
		var off := Vector3(0, 0.012 + down * 0.1, down * 0.08)
		off.y += -s * dir.x * 0.05 * tilt_k
		off.z += dir.y * 0.05 * tilt_k
		var h := hands[side]
		h.global_transform = Transform3D(board.global_basis, base + off)
		for f in fingers[side]:
			var fn: Node3D = f
			fn.rotation.z = s * -1.3 * grip
