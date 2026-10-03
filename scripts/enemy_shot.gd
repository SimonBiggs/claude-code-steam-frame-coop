extends Area3D
## Slow glowing orb fired by spitter enemies. Dash through it or step aside.

var direction := Vector3(0, 0, -1)
var speed := 9.0
var damage := 15.0
var life := 3.0
var color := Color(0.4, 1.0, 0.3)
var main
var spent := false
var ghost := false  # Steam Machine copy: visual only, placed from host snapshots
var net_id := 0
var net_target := Vector3.ZERO
var fireball := false  # from the sky fish: bigger, and players can shoot it down
var size := 1.0
var friendly := false  # reflected by the VR shield: now hurts enemies


func _ready() -> void:
	add_to_group("enemy_shots")
	net_target = position
	collision_layer = 4 if fireball and not ghost else 0  # layer 4 lets player bullets hit fireballs
	collision_mask = 0 if ghost else (1 | 2 | 8)
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.35 * size
	cs.shape = s
	add_child(cs)
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.3 * size
	m.height = 0.6 * size
	m.radial_segments = 12
	m.rings = 6
	mi.mesh = m
	mi.material_override = main.make_material(color, 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if ghost:
		global_position = global_position.lerp(net_target, 1.0 - exp(-20.0 * delta))
		return
	global_position += direction * speed * delta
	if not friendly:
		for p in main.players:
			if p.has_method("shield_reflect"):
				var out: Vector3 = p.shield_reflect(global_position)
				if out != Vector3.ZERO:
					_reflect(out)
					break
	life -= delta
	if life <= 0.0:
		queue_free()


func apply_net(item: Array) -> void:
	net_target = item[1]
	if item.size() > 2 and item[2] and not friendly:
		friendly = true
		color = Color(0.4, 0.9, 1.0)
		for c in get_children():
			if c is MeshInstance3D:
				c.material_override = main.make_material(color, 5.0)


func _reflect(dir: Vector3) -> void:
	friendly = true
	direction = dir.normalized()
	speed = 22.0
	life = 2.5
	collision_mask = 1 | 4 | 8
	color = Color(0.4, 0.9, 1.0)
	for c in get_children():
		if c is MeshInstance3D:
			c.material_override = main.make_material(color, 5.0)
	main.burst(global_position, color, 10, 0.08)
	main.sound("pickup", -2.0, 1.4)


func _on_body_entered(body: Node3D) -> void:
	if spent:
		return
	if friendly:
		if body.has_method("hit"):
			body.hit(4.0, Vector3(direction.x, 0.0, direction.z).normalized())
		elif body.has_method("take_damage"):
			return  # reflected orbs pass through players
		spent = true
		main.burst(global_position, color, 10, 0.1)
		queue_free()
		return
	if body.has_method("take_damage"):
		if body.is_down:
			return
		body.take_damage(damage, global_position - direction * 2.0)
	spent = true
	main.burst(global_position, color, 8, 0.1)
	queue_free()


## Player bullets can shoot fireballs out of the sky.
func shot_down() -> void:
	if spent or not fireball:
		return
	spent = true
	main.score += 50
	main.explosion(global_position, color, 0.8)
	main.popup(global_position + Vector3.UP * 0.5, "+50", color.lightened(0.3))
	queue_free()
