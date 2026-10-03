extends Node3D
## Greedy garden visitors (no harm done to anyone, they just get shooed off):
##  - aphid: a little green bug that sits on a plant: it stops growing, drinks its water and hogs the pollen.
##  - wasp: hangs around the hive entrance nibbling the honey.
## Only the gardener can shoo them (flick with a hand, or point and pull the trigger).
## The host simulates; the TV draws ghosts from snapshots.

const W := preload("res://games/bee_garden/world.gd")

var main
var kind := "aphid"
var net_id := 0
var ghost := false
var state := "come"   # come, munch, flee
var target := -1      # aphid: the spot it wants
var t := 0.0
var steal_t := 3.0
var flee_dir := Vector3.UP
var net_target := Vector3.ZERO
var net_fleeing := false
var radius := 0.2
var wings: Array[MeshInstance3D] = []
var body: Node3D


func _ready() -> void:
	add_to_group("pests")
	net_target = position
	body = Node3D.new()
	add_child(body)
	if kind == "wasp":
		radius = 0.22
		W.mesh_node(body, W.sphere(0.13, 10), W.cmat(Color(1.0, 0.8, 0.1)), Vector3(0, 0, 0.08), Vector3(0.9, 0.9, 1.6))
		var stripe := W.mesh_node(body, W.cyl(0.125, 0.125, 0.05, 10), W.cmat(Color(0.1, 0.08, 0.05)), Vector3(0, 0, 0.1))
		stripe.rotation.x = PI / 2.0
		W.mesh_node(body, W.sphere(0.08, 8), W.cmat(Color(0.15, 0.12, 0.08)), Vector3(0, 0.02, -0.14))
		var sting := W.mesh_node(body, W.cyl(0.0, 0.03, 0.08, 6), W.cmat(Color(0.1, 0.08, 0.05)), Vector3(0, 0, 0.32))
		sting.rotation.x = PI / 2.0
	else:
		radius = 0.18
		W.mesh_node(body, W.sphere(0.1, 10), W.cmat(Color(0.5, 0.85, 0.25)), Vector3.ZERO, Vector3(0.9, 0.7, 1.2))
		W.mesh_node(body, W.sphere(0.055, 8), W.cmat(Color(0.35, 0.65, 0.2)), Vector3(0, 0.02, -0.12))
		for s in [-1.0, 1.0]:
			W.mesh_node(body, W.sphere(0.018, 6), W.cmat(Color(0.1, 0.1, 0.1)), Vector3(s * 0.03, 0.05, -0.16))
	var wing_mat := W.mat(Color(0.95, 0.98, 1.0, 0.6))
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for s in [-1.0, 1.0]:
		var wm := W.mesh_node(body, W.sphere(0.09, 8), wing_mat, Vector3(s * 0.1, 0.1, 0.0), Vector3(1.2, 0.15, 0.6))
		wm.set_meta("side", s)
		wings.append(wm)


func _process(delta: float) -> void:
	t += delta
	for wm in wings:
		var side: float = wm.get_meta("side")
		wm.rotation.z = side * (0.3 + sin(t * 55.0) * 0.5)
	if ghost:
		var to := net_target - global_position
		global_position = global_position.lerp(net_target, 1.0 - exp(-12.0 * delta))
		_face(to)
		return
	if main == null:
		return
	match state:
		"come":
			if kind == "aphid" and not main.aphid_target_ok(target):
				target = main.pick_aphid_target()
				if target < 0:
					shoo(global_position + Vector3.DOWN)
					return
			var goal := _goal()
			var to := goal - global_position
			var spd := 1.8 if kind == "wasp" else 1.3
			var step := to.normalized() * spd * delta if to.length() > 0.01 else Vector3.ZERO
			step += Vector3(sin(t * 3.0), cos(t * 4.3) * 0.5, cos(t * 2.6)) * 0.4 * delta
			if to.length() < 0.15:
				state = "munch"
				t = 0.0
				if kind == "wasp":
					main.popup(global_position + Vector3.UP * 0.6, "A wasp at the hive!", Color(1.0, 0.8, 0.3))
			else:
				global_position += step
				_face(step)
		"munch":
			if kind == "aphid":
				if not main.aphid_target_ok(target):
					state = "come"
					return
				global_position = _goal() + Vector3(0, sin(t * 9.0) * 0.015, 0)
			else:
				global_position = _goal() + Vector3(sin(t * 2.0) * 0.12, sin(t * 3.0) * 0.05, cos(t * 1.7) * 0.12)
				steal_t -= delta
				if steal_t <= 0.0:
					steal_t = 5.0
					main.wasp_steal(self)
		"flee":
			global_position += flee_dir * 8.0 * delta
			_face(flee_dir)
			if t > 1.4:
				queue_free()


func _goal() -> Vector3:
	if kind == "wasp":
		return W.HIVE_ENTRY + Vector3(0.35, 0.3, 0.0)
	return main.head_pos(target) + Vector3(0.1, 0.06, 0.08)


func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.001:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 0.2)


func is_fleeing() -> bool:
	return state == "flee" or net_fleeing


func shoo(from: Vector3) -> void:
	if state == "flee":
		return
	state = "flee"
	t = 0.0
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(randf_range(-1, 1), 0, -1)
	flee_dir = (away.normalized() + Vector3.UP * 0.8).normalized()


func net_item() -> Array:
	return [net_id, kind, global_position, state == "flee"]


func apply_net(item: Array) -> void:
	net_target = item[2]
	net_fleeing = item[3]
