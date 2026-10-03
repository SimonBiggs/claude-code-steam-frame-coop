extends Area3D

var direction := Vector3(0, 0, -1)
var speed := 34.0
var damage := 1.0
var life := 0.9
var color := Color.WHITE
var spent := false
var owner_player
var visual_only := false  # Steam Machine copy of a shot: hits only walls


func _ready() -> void:
	collision_layer = 0
	collision_mask = (1 | 8) if visual_only else (1 | 4 | 8)
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.3
	cs.shape = s
	add_child(cs)

	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.12
	m.height = 0.24
	m.radial_segments = 8
	m.rings = 4
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.lightened(0.4)
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1, 1, 3)
	add_child(mi)
	basis = Basis.looking_at(direction)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if spent:
		return
	spent = true
	if body.has_method("hit"):
		body.hit(damage, Vector3(direction.x, 0.0, direction.z).normalized())
		if owner_player and owner_player.hud:
			owner_player.hud.hit_marker()
		elif owner_player and owner_player.remote:
			owner_player.main.net.event("hitmark", [])
	queue_free()


func _on_area_entered(area: Area3D) -> void:
	if spent or visual_only:
		return
	if area.has_method("shot_down"):
		spent = true
		area.shot_down()
		queue_free()
	elif area.get_parent() and area.get_parent().has_method("bullet_hit_area"):
		spent = true
		area.get_parent().bullet_hit_area(area, damage, owner_player)
		queue_free()
	elif area.get_parent() and area.get_parent().has_method("fish_hit"):
		spent = true
		area.get_parent().fish_hit(damage)
		if owner_player and owner_player.hud:
			owner_player.hud.hit_marker()
		queue_free()
