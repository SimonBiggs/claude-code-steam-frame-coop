extends Node3D
## A steaming mug of hot cocoa: walk over it (or grab it in VR) to warm up.

var main
var ghost := false
var net_id := 0
var life := 25.0
var t := 0.0
var mug: Node3D


func _ready() -> void:
	add_to_group("cocoa")
	t = randf() * 5.0
	mug = Node3D.new()
	add_child(mug)
	var cup := CylinderMesh.new()
	cup.top_radius = 0.17
	cup.bottom_radius = 0.14
	cup.height = 0.3
	cup.radial_segments = 12
	_part(cup, main.mat("mug"), Vector3(0, 0.15, 0))
	var drink := CylinderMesh.new()
	drink.top_radius = 0.15
	drink.bottom_radius = 0.15
	drink.height = 0.02
	drink.radial_segments = 12
	_part(drink, main.mat("cocoa"), Vector3(0, 0.29, 0))
	var handle := TorusMesh.new()
	handle.inner_radius = 0.05
	handle.outer_radius = 0.09
	handle.rings = 10
	handle.ring_segments = 5
	var h := _part(handle, main.mat("mug"), Vector3(0.18, 0.16, 0))
	h.rotation.x = PI / 2.0
	var marsh := BoxMesh.new()
	marsh.size = Vector3(0.07, 0.07, 0.07)
	_part(marsh, main.mat("snow"), Vector3(0.04, 0.32, 0.02))
	_part(marsh, main.mat("snow"), Vector3(-0.05, 0.31, -0.03))
	# Glowing ring on the snow so it's easy to spot.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.55
	ring.rings = 20
	ring.ring_segments = 4
	var r := MeshInstance3D.new()
	r.mesh = ring
	r.material_override = main.mat("cocoa_ring")
	r.position.y = 0.03
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(r)
	# Steam.
	var steam := CPUParticles3D.new()
	steam.amount = 8
	steam.lifetime = 1.4
	steam.direction = Vector3.UP
	steam.spread = 12.0
	steam.initial_velocity_min = 0.3
	steam.initial_velocity_max = 0.5
	steam.gravity = Vector3(0, 0.1, 0)
	steam.scale_amount_min = 0.6
	steam.scale_amount_max = 1.2
	var q := SphereMesh.new()
	q.radius = 0.05
	q.height = 0.1
	q.radial_segments = 6
	q.rings = 3
	q.material = main.mat("steam")
	steam.mesh = q
	steam.position.y = 0.32
	mug.add_child(steam)
	mug.scale = Vector3.ONE * 0.1
	create_tween().tween_property(mug, "scale", Vector3.ONE * 1.6, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mug.add_child(mi)
	return mi


func grab_point() -> Vector3:
	return mug.global_position + Vector3.UP * 0.3


func apply_net(item: Array) -> void:
	position = item[1]


func _process(delta: float) -> void:
	t += delta
	mug.rotation.y = t * 1.2
	mug.position.y = 0.35 + sin(t * 2.5) * 0.1
	if ghost:
		return
	life -= delta
	if life < 4.0:
		mug.visible = fmod(life, 0.4) > 0.15
	if life <= 0.0:
		queue_free()
