extends Node3D
## Simple mode: a see-through glowing hand holding a little lantern that SHOWS the VR lantern-bearer what
## to do (instead of text): it rests where the right hand is, then sweeps its beam across until it
## points at the sleepy practice ghost, holds the light on it for a moment, and starts again.
## Only the lantern-bearer sees it (main puts it on the VR viewmodel layer). main calls show_demo()
## every frame; it fades in when the practice ghost hasn't been lit for a moment.

var hand: Node3D
var fingers: Array[Node3D] = []
var cone: MeshInstance3D
var mat: StandardMaterial3D
var cone_mat: StandardMaterial3D
var t := 0.0
var idle_t := 0.0


func _ready() -> void:
	top_level = true
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.85, 0.5)
	mat.no_depth_test = false
	cone_mat = mat.duplicate()
	cone_mat.albedo_color = Color(0.8, 1.0, 0.7, 0.12)
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hand = Node3D.new()
	add_child(hand)
	# A fist around the lantern handle; the lantern hangs below and points its light along -Z.
	_part(_sphere(0.05), Vector3(0, 0.04, 0.03), Vector3(1.0, 0.8, 1.3))
	for i in 3:
		var f := Node3D.new()
		f.position = Vector3(-0.025 + i * 0.025, 0.05, -0.03)
		hand.add_child(f)
		fingers.append(f)
		var m := _part(_sphere(0.016), Vector3(0, 0, -0.02), Vector3(1.0, 1.0, 2.2))
		m.reparent(f, false)
	_part(_sphere(0.045), Vector3(0, -0.03, 0), Vector3(1.0, 1.25, 1.0))  # the lantern glass
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.55
	cm.height = 2.2
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone = MeshInstance3D.new()
	cone.mesh = cm
	cone.material_override = cone_mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.rotation.x = PI / 2.0
	cone.position = Vector3(0, -0.03, -1.12)
	hand.add_child(cone)
	visible = false


func _sphere(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	return sm


func _part(mesh: Mesh, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.add_child(mi)
	return mi


## on: there is a practice ghost to light. head: the VR camera. target: the ghost. lit: the player's
## real beam is on it right now (the demo hides and waits).
func show_demo(on: bool, head: Transform3D, target: Vector3, lit: bool, delta: float) -> void:
	if not on or lit:
		visible = false
		idle_t = 0.0 if lit else idle_t
		t = 0.0
		return
	idle_t += delta
	if idle_t < 1.2:
		visible = false
		return
	visible = true
	t = fmod(t + delta, 3.0)
	var yaw_basis := Basis(Vector3.UP, head.basis.get_euler().y)
	var rest := head.origin + yaw_basis * Vector3(0.24, -0.4, -0.4)
	var to := (target - rest).normalized()
	# Start pointing well off to the side, sweep onto the ghost, hold, fade.
	var off := to.rotated(Vector3.UP, 1.0 if to.cross(yaw_basis * Vector3.FORWARD).y < 0.0 else -1.0)
	var k := ease(clampf((t - 0.3) / 1.4, 0.0, 1.0), -1.8)
	var dir := off.slerp(to, k).normalized()
	var alpha := 0.5 * minf(1.0, t / 0.3)
	if t > 2.5:
		alpha *= maxf(0.0, 1.0 - (t - 2.5) / 0.5)
	mat.albedo_color.a = alpha
	cone_mat.albedo_color.a = alpha * (0.16 if t > 1.7 else 0.1)
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK
	hand.global_transform = Transform3D(Basis.looking_at(dir, up), rest + Vector3(0, sin(t * 3.0) * 0.01, 0))
	for f in fingers:
		f.rotation.x = -1.0
