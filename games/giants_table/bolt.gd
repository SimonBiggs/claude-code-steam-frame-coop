extends Node3D
## A little crossbow bolt. On the host it hits goblins; on the TV it's just for show.

const W := preload("res://games/giants_table/world.gd")
const SPEED := 24.0

var main
var vel := Vector3.ZERO
var life := 1.1
var visual_only := false
var shooter


func _ready() -> void:
	var m := MeshInstance3D.new()
	m.mesh = W.box(Vector3(0.05, 0.05, 0.45))
	m.material_override = W.mat(Color(1.0, 0.85, 0.5), 2.5)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func launch(dir: Vector3) -> void:
	vel = dir.normalized() * SPEED


func _physics_process(delta: float) -> void:
	life -= delta
	vel.y -= 5.0 * delta
	global_position += vel * delta
	if vel.length() > 0.1 and absf(vel.normalized().y) < 0.99:
		look_at(global_position + vel, Vector3.UP)
	var p := global_position
	if life <= 0.0 or p.y < W.height(p.x, p.z) or p.y < -5.0:
		queue_free()
		return
	for g in get_tree().get_nodes_in_group("goblins"):
		if g.held or g.is_queued_for_deletion():
			continue
		if g.grab_center().distance_to(p) < g.radius + 0.25:
			if not visual_only:
				g.hit_by_knight(1.0, Vector3(vel.x, 0.0, vel.z).normalized(), shooter)
				main.burst(p, Color(1.0, 0.85, 0.5), 6, 0.06)
			queue_free()
			return
