extends Area3D
## Pickups dropped by enemies: health, spread shot, rapid fire, shield bubble and the mega bomb.

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
	match kind:
		"health":
			color = Color(0.3, 1.0, 0.45)
			var b := BoxMesh.new()
			b.size = Vector3(0.5, 0.5, 0.5)
			mesh.mesh = b
		"rapid":
			color = Color(1.0, 0.6, 0.15)
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.28
			c.height = 0.7
			c.radial_segments = 6
			mesh.mesh = c
		"bubble":
			color = Color(0.45, 0.65, 1.0)
			var sp := SphereMesh.new()
			sp.radius = 0.32
			sp.height = 0.64
			sp.radial_segments = 14
			sp.rings = 7
			mesh.mesh = sp
		"bomb":
			color = Color(1.0, 0.25, 0.35)
			var bs := SphereMesh.new()
			bs.radius = 0.3
			bs.height = 0.6
			bs.radial_segments = 12
			bs.rings = 6
			mesh.mesh = bs
			var fuse := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.36
			tm.outer_radius = 0.44
			tm.rings = 16
			tm.ring_segments = 6
			fuse.mesh = tm
			fuse.material_override = main.make_material(Color(1.0, 0.85, 0.3), 4.0)
			fuse.rotation.x = PI / 2.0
			mesh.add_child(fuse)
		_:
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
	var pulse := 1.0 + sin(t * 6.0) * 0.08
	mesh.scale = Vector3.ONE * pulse
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
	main.director().add_stat(body, "pickups", 1)
	main.director().on_pickup(kind)
	var label := ""
	match kind:
		"health":
			body.heal(40.0)
			label = "+HEALTH"
		"rapid":
			body.rapid_t = 8.0
			label = "RAPID FIRE!"
		"bubble":
			body.bubble_t = 6.0
			label = "SHIELD BUBBLE!"
			main.sound("bubble", -2.0)
		"bomb":
			label = "MEGA BOMB!"
			main.mega_bomb(global_position, body)
		_:
			body.spread_t = 10.0
			label = "SPREAD SHOT!"
	if not main.SIMPLE_MODE:  # simple mode: the burst, the sound and the effect say it
		main.popup(global_position + Vector3.UP * 1.6, label, color.lightened(0.3))
	main.burst(global_position + Vector3.UP * 0.8, color, 16)
	main.sound("pickup")
	queue_free()
