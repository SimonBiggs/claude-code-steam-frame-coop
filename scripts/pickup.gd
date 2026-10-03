extends Area3D
## Health or spread-shot pickup dropped by enemies.

var kind := "health"
var main
var life := 12.0
var t := 0.0
var color := Color.WHITE
var mesh: MeshInstance3D
var ghost := false  # Steam Machine copy: visual only, the host handles collection
var net_id := 0


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 0
	collision_mask = 0 if ghost else 2
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.9
	cs.shape = s
	cs.position.y = 0.8
	add_child(cs)

	mesh = MeshInstance3D.new()
	if kind == "health":
		color = Color(0.3, 1.0, 0.45)
		var b := BoxMesh.new()
		b.size = Vector3(0.5, 0.5, 0.5)
		mesh.mesh = b
	else:
		color = Color(0.3, 0.9, 1.0)
		var p := PrismMesh.new()
		p.size = Vector3(0.6, 0.6, 0.3)
		mesh.mesh = p
	mesh.material_override = main.make_material(color, 2.0)
	mesh.position.y = 0.8
	add_child(mesh)
	# Tall light beam so it can be spotted across the arena.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.18
	cyl.height = 6.0
	beam.mesh = cyl
	var bm: StandardMaterial3D = main.make_material(color, 2.0)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color.a = 0.35
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 3.0
	add_child(beam)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	t += delta
	life -= delta
	mesh.rotation.y = t * 2.0
	mesh.position.y = 0.8 + sin(t * 3.0) * 0.15
	if life < 3.0:
		mesh.visible = fmod(life, 0.3) > 0.12
	if life <= 0.0:
		queue_free()
		return
	# VR: reach out and touch a pickup with either hand to grab it.
	if not ghost:
		for p in main.players:
			if p.vr and not p.is_down:
				var at: Vector3 = mesh.global_position
				if p.hand_l.global_position.distance_to(at) < 0.45 or p.hand_r.global_position.distance_to(at) < 0.45:
					p.hand_l.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.08, 0.0)
					_on_body_entered(p)
					return


func apply_net(item: Array) -> void:
	position = item[2]


func _on_body_entered(body: Node3D) -> void:
	if body.get("is_down") != false:
		return
	main.achievements().on_pickup()
	if kind == "health":
		body.heal(40.0)
	else:
		body.spread_t = 10.0
	main.burst(global_position + Vector3.UP * 0.8, color, 16)
	main.sound("pickup")
	queue_free()
