extends Node3D
## SIMPLE_MODE teaching for the VR giant: a see-through glowing hand SHOWS the move instead of text
## (world space, metres; only made where the VR player is, nobody else needs it).
##  - show_throw(from, to): the hand comes down on the waiting dice, curls its fingers round it, swings
##    it towards the island and lets go: a ghost die flies off and bounces. Loops.
##  - show_tap(at): the hand reaches to a spot and taps it twice (minigame demos). Loops.
##  - hide_demo(): fades away.
## Cheap: six low-poly spheres and one box, one unshaded material.

const CYCLE := 3.2

var mode := ""  # "", "throw", "tap"
var from := Vector3.ZERO
var to := Vector3.ZERO
var t := 0.0
var shown := false  ## bots: the demo has been on screen
var hand: Node3D
var fingers: Array[Node3D] = []
var mat: StandardMaterial3D
var die: MeshInstance3D
var die_mat: StandardMaterial3D


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.95, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	hand = Node3D.new()
	add_child(hand)
	_part(hand, sm, Vector3(0, 0.0, 0.01), Vector3(0.05, 0.022, 0.06))  # palm
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.033 + i * 0.022, 0.0, -0.045)
		hand.add_child(f)
		fingers.append(f)
		_part(f, sm, Vector3(0, 0, -0.025), Vector3(0.009, 0.009, 0.03))
	var thumb := Node3D.new()
	thumb.position = Vector3(0.05, 0.0, 0.0)
	thumb.rotation.y = -0.7
	hand.add_child(thumb)
	fingers.append(thumb)
	_part(thumb, sm, Vector3(0, 0, -0.02), Vector3(0.01, 0.01, 0.025))
	die_mat = mat.duplicate()
	die_mat.albedo_color = Color(1.0, 0.95, 0.55, 0.55)
	die = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.085
	die.mesh = bm
	die.material_override = die_mat
	die.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(die)
	visible = false


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, radii: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func show_throw(p_from: Vector3, p_to: Vector3) -> void:
	if mode != "throw":
		t = 0.0
	mode = "throw"
	from = p_from
	to = p_to


func show_tap(at: Vector3) -> void:
	if mode != "tap":
		t = 0.0
	mode = "tap"
	from = at


func hide_demo() -> void:
	mode = ""
	visible = false


func _process(delta: float) -> void:
	if mode == "":
		return
	visible = true
	shown = true
	t = fmod(t + delta, CYCLE)
	var a := 0.55 * minf(1.0, t / 0.3)
	if t > CYCLE - 0.5:
		a *= maxf(0.0, (CYCLE - t) / 0.5)
	mat.albedo_color.a = a
	die_mat.albedo_color.a = a
	if mode == "throw":
		_throw_pose()
	else:
		_tap_pose()


## Down onto the dice, grab, swing towards the island, let go: the ghost die flies on.
func _throw_pose() -> void:
	var over := from + Vector3(0, 0.25, 0)
	var swing_to := from.lerp(to, 0.35) + Vector3(0, 0.22, 0)
	var p: Vector3
	var grip := 0.0
	var die_p := from
	if t < 0.6:
		p = over.lerp(from + Vector3(0, 0.04, 0), ease(t / 0.6, 0.5))
	elif t < 0.9:
		p = from + Vector3(0, 0.04, 0)
		grip = (t - 0.6) / 0.3
	elif t < 1.7:
		var k := ease((t - 0.9) / 0.8, -1.6)
		p = (from + Vector3(0, 0.04, 0)).lerp(swing_to, k)
		grip = 1.0
		die_p = p - Vector3(0, 0.04, 0)
	else:
		var k2 := clampf((t - 1.7) / 1.0, 0.0, 1.0)
		p = swing_to + Vector3(0, 0.02, 0) * k2
		grip = maxf(0.0, 1.0 - (t - 1.7) / 0.2)
		# The die flies on in an arc and lands near `to`.
		die_p = (swing_to - Vector3(0, 0.04, 0)).lerp(to, k2) + Vector3(0, sin(k2 * PI) * 0.12, 0)
	var dir := to - from
	dir.y = 0.0
	var yaw := atan2(-dir.x, -dir.z) if dir.length() > 0.01 else 0.0
	hand.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	for f in fingers:
		f.rotation.x = -1.4 * grip
	die.visible = true
	die.global_position = die_p
	die.rotation = Vector3(t * 3.0, t * 4.0, 0) if t > 1.7 else Vector3.ZERO


## Reach to the spot and tap it twice.
func _tap_pose() -> void:
	var cam := get_viewport().get_camera_3d()
	var head := cam.global_position if cam != null else from + Vector3(0, 0.5, 0.6)
	var start := from.lerp(head, 0.35)
	var p: Vector3
	if t < 0.8:
		p = start.lerp(from + Vector3(0, 0.06, 0), ease(t / 0.8, 0.5))
	else:
		var k := fmod((t - 0.8) / 0.6, 1.0)
		p = from + Vector3(0, 0.02 + 0.07 * absf(sin(k * PI)), 0)
	var dir := from - head
	dir.y = 0.0
	var yaw := atan2(-dir.x, -dir.z) if dir.length() > 0.01 else 0.0
	hand.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.5), p)
	for i in fingers.size():
		fingers[i].rotation.x = 0.0 if i == 1 else -1.2  # pointing finger out
	die.visible = false
