extends Node3D
## Auto-turret a player builds from the skill map (Simon's idea). Host: aims and fires at the nearest
## enemy, kills credit the builder. Client: a ghost that copies position and aim from snapshots.

const RANGE := 15.0
const FIRE_INTERVAL := 0.4
const LIFETIME := 60.0

var main
var builder  # player who built it
var color := Color.WHITE
var ghost := false
var net_id := 0
var life := LIFETIME
var fire_t := 0.0
var head: Node3D
var barrel_tip: Node3D
var net_yaw := 0.0


func _ready() -> void:
	add_to_group("turrets")
	var dark: StandardMaterial3D = main.make_material(Color(0.12, 0.13, 0.18), 0.0)
	dark.metallic = 0.7
	var glow: StandardMaterial3D = main.make_material(color, 3.0)
	_mesh(self, CylinderMesh.new(), dark, Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.9))
	_mesh(self, TorusMesh.new(), glow, Vector3(0, 0.05, 0), Vector3(1.3, 1.0, 1.3))
	head = Node3D.new()
	head.position = Vector3(0, 0.95, 0)
	add_child(head)
	_mesh(head, SphereMesh.new(), dark, Vector3.ZERO, Vector3.ONE * 0.75)
	_mesh(head, BoxMesh.new(), dark, Vector3(0, 0, -0.55), Vector3(0.16, 0.16, 0.8))
	_mesh(head, BoxMesh.new(), glow, Vector3(0, 0.1, -0.2), Vector3(0.3, 0.06, 0.3))
	barrel_tip = Node3D.new()
	barrel_tip.position = Vector3(0, 0, -1.0)
	head.add_child(barrel_tip)
	scale = Vector3.ONE * 0.05
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _mesh(parent: Node3D, mesh: PrimitiveMesh, mat: Material, pos: Vector3, scl: Vector3) -> void:
	if mesh is SphereMesh:
		mesh.radial_segments = 12
		mesh.rings = 6
	if mesh is CylinderMesh:
		mesh.radial_segments = 12
	if mesh is TorusMesh:
		mesh.inner_radius = 0.4
		mesh.outer_radius = 0.48
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)


func _process(delta: float) -> void:
	if ghost:
		head.rotation.y = lerp_angle(head.rotation.y, net_yaw, 1.0 - exp(-15.0 * delta))
		return
	life -= delta
	if life <= 0.0:
		main.explosion(global_position + Vector3.UP * 0.6, color, 0.5)
		queue_free()
		return
	var target = null
	var best := RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = e.global_position.distance_to(global_position)
		if d < best:
			best = d
			target = e
	if target == null:
		head.rotate_y(delta * 0.6)  # idle scan
		return
	var to: Vector3 = target.global_position + Vector3.UP * target.radius - head.global_position
	var want := atan2(-to.x, -to.z)
	head.rotation.y = lerp_angle(head.rotation.y, want, 1.0 - exp(-12.0 * delta))
	fire_t -= delta
	if fire_t <= 0.0 and absf(angle_difference(head.rotation.y, want)) < 0.2:
		fire_t = FIRE_INTERVAL
		main.spawn_bullet(barrel_tip.global_position, to.normalized(), color, builder, false, true)
		main.sound("shoot", -16.0, 0.8)


## Client: [id, pos, yaw, colour]
func apply_net(item: Array) -> void:
	global_position = item[1]
	net_yaw = item[2]
