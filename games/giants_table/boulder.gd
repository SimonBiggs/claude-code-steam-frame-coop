extends "res://games/giants_table/toss.gd"
## A boulder: throw it to squash goblins, or set it down as a barricade (goblins walk around it)
## or as a stepping stone across the river (knights can climb onto it).

var bounced := false
var spin := Vector3.ZERO
var mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("boulders")
	radius = 0.65
	center_h = radius * 0.9
	mesh = MeshInstance3D.new()
	mesh.mesh = W.sphere(radius, 12)
	var tint := float(net_id % 7) / 7.0
	mesh.material_override = W.mat(Color(0.6, 0.58, 0.55).lerp(Color(0.72, 0.62, 0.5), tint))
	mesh.scale = Vector3(1.05, 0.9, 0.95)
	mesh.position.y = center_h
	add_child(mesh)
	var moss := MeshInstance3D.new()
	moss.mesh = W.sphere(radius * 0.55, 8)
	moss.material_override = W.mat(Color(0.4, 0.62, 0.3))
	moss.position = Vector3(0.15, radius * 0.85, 0.1)
	moss.scale = Vector3(1.0, 0.35, 1.0)
	mesh.add_child(moss)


func on_released(v: Vector3) -> void:
	super.on_released(v)
	bounced = false
	spin = Vector3(-v.z, 0.0, v.x) * 0.3


func _physics_process(delta: float) -> void:
	if ghost:
		ghost_update(delta)
		return
	if not flying:
		return
	mesh.rotation += spin * delta
	var before := vel
	fly(delta)
	if before.length() > 7.0 and flying:
		for g in get_tree().get_nodes_in_group("goblins"):
			if g.held or g.is_queued_for_deletion():
				continue
			if g.grab_center().distance_to(grab_center()) < radius + g.radius + 0.1:
				g.hit_by_object(before, self)
				vel *= 0.7
				main.add_thud(global_position, before.length() * 0.6)


func _landed(impact: float) -> void:
	if impact > 9.0 and not bounced:
		bounced = true
		vel = Vector3(vel.x * 0.45, -vel.y * 0.28, vel.z * 0.45)
		global_position.y += 0.02
		main.add_thud(global_position, impact)
		return
	super._landed(impact)
	spin = Vector3.ZERO
	if not bounced:
		main.add_thud(global_position, impact)
	var p := W.push_out(global_position, radius * 0.8)
	p.y = support_height(p)
	global_position = p


func _fell_off() -> void:
	main.boulder_lost(self)


func apply_net(item: Array) -> void:
	super.apply_net(item)
	var rot: Vector3 = item[4]
	mesh.rotation = rot


func net_item() -> Array:
	return [net_id, "boulder", global_position, rotation.y, mesh.rotation]
