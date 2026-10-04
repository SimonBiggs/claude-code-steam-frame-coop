extends MeshInstance3D
## A flying snowball (ballistic). Team "p" = thrown by the players, "e" = thrown by snowmen.
## On the host it decides hits; visual_only copies (client, or the client's own throws) just splat.

var main
var vel := Vector3.ZERO
var radius := 0.12
var damage := 1.0
var team := "p"
var owner_index := -1
var visual_only := false
var life := 5.0
var spin := Vector3.ZERO
var look := ""  # "icicle": a thrown icicle (simple mode), flies point first


func _ready() -> void:
	if look == "icicle":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.028
		cm.bottom_radius = 0.0
		cm.height = 0.24
		cm.radial_segments = 6
		cm.rings = 1
		mesh = cm
		material_override = main.mat("ice")
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mesh = sm
	material_override = main.mat("snowball" if team == "p" else "enemy_ball")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))


func _physics_process(delta: float) -> void:
	life -= delta
	vel.y -= main.gravity * delta
	# Sub-step fast throws so they can't tunnel through a snowman.
	var steps := clampi(int(vel.length() * delta / 0.15) + 1, 1, 6)
	for i in steps:
		global_position += vel * delta / steps
		if main.ball_step(self):
			queue_free()
			return
	if look == "icicle":
		if vel.length() > 0.1:
			look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT)
			rotate_object_local(Vector3.RIGHT, PI / 2.0)  # the cone's point (-Y) leads
	else:
		rotation += spin * delta
	if life <= 0.0:
		queue_free()
