extends "res://games/giants_table/toss.gd"
## Simple mode: a tree the Giant pulled out of the table. Throw it at goblins (BONK) or swing it
## like a big leafy club. It lies where it lands for a moment, then a new tree grows back in its
## old spot (scenery.gd), so the village never runs out of trees.

const REST_TIME := 3.0
const SWING_SPEED := 14.0

var kind := 0          # 0 pine, 1 round tree
var tree_index := -1
var sc := 1.0
var rest_t := 0.0
var lying := false
var spin := Vector3.ZERO
var pivot: Node3D
var last_pos := Vector3.ZERO
var swing_cd := 0.0


func setup(k: int, idx: int, s: float) -> void:
	kind = k
	tree_index = idx
	sc = s


func _ready() -> void:
	add_to_group("props")
	radius = 0.6 * sc
	center_h = 1.0 * sc
	pivot = Node3D.new()
	pivot.scale = Vector3.ONE * sc
	add_child(pivot)
	var parts: Array = [[W.cyl(0.12, 0.18, 0.9, 6), Vector3(0, 0.45, 0), Color(0.45, 0.28, 0.15)]]
	if kind == 0:
		parts.append([W.cyl(0.0, 0.75, 1.3, 8), Vector3(0, 1.3, 0), Color(0.18, 0.5, 0.3)])
		parts.append([W.cyl(0.0, 0.55, 1.0, 8), Vector3(0, 1.95, 0), Color(0.18, 0.5, 0.3)])
	else:
		parts.append([W.sphere(0.75, 10), Vector3(0, 1.5, 0), Color(0.35, 0.68, 0.25)])
		parts.append([W.sphere(0.5, 8), Vector3(0.3, 2.05, 0.1), Color(0.35, 0.68, 0.25)])
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = W.mat(p[2])
		mi.position = p[1]
		pivot.add_child(mi)
	last_pos = global_position


func on_grabbed() -> void:
	super.on_grabbed()
	lying = false
	rest_t = 0.0
	pivot.rotation = Vector3.ZERO


func on_released(v: Vector3) -> void:
	super.on_released(v)
	spin = Vector3(-v.z, 0.0, v.x) * 0.25


## Where the leafy top is (what hits goblins when you swing it).
func top() -> Vector3:
	return pivot.global_transform * Vector3(0, 1.6, 0)


func _physics_process(delta: float) -> void:
	if ghost:
		ghost_update(delta)
		return
	swing_cd -= delta
	if held:
		# Swung hard like a club: bonk the goblins the leafy top sweeps through.
		var v := (global_position - last_pos) / maxf(delta, 0.001)
		last_pos = global_position
		if v.length() > SWING_SPEED and swing_cd <= 0.0:
			_hit_goblins(top(), 1.0 * sc, v)
		return
	last_pos = global_position
	if flying:
		pivot.rotation += spin * delta
		var before := vel
		fly(delta)
		if is_instance_valid(self) and flying and before.length() > 7.0:
			_hit_goblins(global_position + Vector3.UP * 0.5, 1.3 * sc, before)
		return
	rest_t += delta
	if rest_t > REST_TIME and not is_queued_for_deletion():
		main.burst(global_position + Vector3.UP * 0.6, Color(0.4, 0.75, 0.3), 14, 0.12)
		main.sound("pop", -8.0, 0.8)
		_regrow()


func _hit_goblins(at: Vector3, r: float, v: Vector3) -> void:
	for g in get_tree().get_nodes_in_group("goblins"):
		if g.held or g.is_queued_for_deletion() or g.has_meta("dead"):
			continue
		if g.grab_center().distance_to(at) < r + g.radius:
			swing_cd = 0.3
			g.hit_by_object(v, self)
			main.add_thud(g.global_position, 12.0)
			main.sound("smack", -4.0, randf_range(0.8, 1.0))


func _landed(impact: float) -> void:
	super._landed(impact)
	main.add_thud(global_position, impact)
	if not lying:
		lying = true
		rest_t = 0.0
		var yaw := randf() * TAU
		pivot.rotation = Vector3(0.0, yaw, PI / 2.0)
		main.sound("rustle", -4.0, 0.8)


func _fell_off() -> void:
	_regrow()


func _regrow() -> void:
	if main.scenery != null:
		main.scenery.regrow(tree_index)
	queue_free()


func net_item() -> Array:
	return [net_id, "prop", global_position, rotation.y, pivot.rotation, kind, tree_index, sc]


func apply_net(item: Array) -> void:
	super.apply_net(item)
	if pivot:
		pivot.rotation = item[4]
