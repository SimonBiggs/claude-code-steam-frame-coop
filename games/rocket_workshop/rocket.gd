extends Node3D
## The little cartoon rocket on the launch pad. Its look and launch are driven purely by
## (rocket number, phase, launch time), so the host and the TV draw the same thing without extra events.
## Launch timeline: 0-3 s countdown (rumble from 1.5 s), lift-off at 3 s with flames, smoke and confetti.

const BODY_COLORS: Array[Color] = [Color(0.95, 0.95, 0.98), Color(1.0, 0.85, 0.4), Color(0.6, 0.85, 1.0),
	Color(1.0, 0.7, 0.8), Color(0.75, 0.95, 0.6), Color(0.85, 0.75, 1.0)]
const TRIM_COLORS: Array[Color] = [Color(0.95, 0.25, 0.25), Color(0.25, 0.5, 1.0), Color(1.0, 0.5, 0.15),
	Color(0.55, 0.3, 0.9), Color(0.2, 0.7, 0.45), Color(1.0, 0.75, 0.1)]
const LIFTOFF := 3.0

var main
var parts: Node3D
var body_mat: StandardMaterial3D
var trim_mat: StandardMaterial3D
var flame: CPUParticles3D
var smoke: CPUParticles3D
var shown_n := -1
var confetti_n := -1
var pop := 1.0
var wobble := 0.0
var wobble_t := 0.0


func _ready() -> void:
	position = main.PAD_POS + Vector3(0, 0.3, 0)
	parts = Node3D.new()
	add_child(parts)
	body_mat = main.make_material(BODY_COLORS[0], 0.0)
	body_mat.roughness = 0.4
	trim_mat = main.make_material(TRIM_COLORS[0], 0.1)
	_part(main.cyl_mesh(0.62, 0.62, 3.0, 20), body_mat, Vector3(0, 2.0, 0))
	_part(main.cyl_mesh(0.0, 0.62, 1.4, 20), trim_mat, Vector3(0, 4.2, 0))
	_part(main.cyl_mesh(0.64, 0.64, 0.3, 20), trim_mat, Vector3(0, 1.2, 0))
	_part(main.cyl_mesh(0.35, 0.5, 0.45, 14), main.make_material(Color(0.35, 0.35, 0.4), 0.0), Vector3(0, 0.3, 0))
	# Round window facing the workshop.
	var win := _part(main.cyl_mesh(0.3, 0.3, 0.06, 18), main.make_material(Color(0.5, 0.85, 1.0), 0.6), Vector3(0, 2.7, 0.6))
	win.rotation.x = PI / 2.0
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.38
	tm.rings = 18
	tm.ring_segments = 6
	rim.mesh = tm
	rim.material_override = trim_mat
	rim.rotation.x = PI / 2.0
	rim.position = Vector3(0, 2.7, 0.6)
	parts.add_child(rim)
	for i in 3:
		var a := TAU * i / 3.0 + PI / 3.0
		var fin := _part(main.box_mesh(Vector3(0.1, 1.1, 0.75)), trim_mat, Vector3(sin(a) * 0.75, 0.75, cos(a) * 0.75))
		fin.rotation.y = a
	flame = _particles(40, 0.5, Color(1.0, 0.75, 0.2), 0.16)
	flame.direction = Vector3.DOWN
	flame.spread = 12.0
	flame.initial_velocity_min = 7.0
	flame.initial_velocity_max = 10.0
	flame.gravity = Vector3.ZERO
	flame.scale_amount_min = 0.6
	flame.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.5, 1.0))
	g.set_color(1, Color(1.0, 0.25, 0.1, 0.0))
	flame.color_ramp = g
	parts.add_child(flame)
	flame.position = Vector3(0, 0.05, 0)
	smoke = _particles(36, 2.6, Color(0.95, 0.95, 0.95), 0.5)
	smoke.direction = Vector3.UP
	smoke.spread = 80.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 5.0
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.damping_min = 1.5
	smoke.damping_max = 2.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 1.0
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 0.8))
	sg.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	smoke.color_ramp = sg
	add_child(smoke)
	smoke.position = Vector3(0, 0.3, 0)


func _part(mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parts.add_child(mi)
	return mi


func _particles(amount: int, lifetime: float, color: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.color = color
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = m
	p.mesh = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Called every frame on both machines.
func update_visual(n: int, phase: String, launch_t: float, delta: float) -> void:
	if not is_inside_tree():
		return
	if n != shown_n and phase != "launch":
		shown_n = n
		var k := maxi(n - 1, 0)
		body_mat.albedo_color = BODY_COLORS[k % BODY_COLORS.size()]
		trim_mat.albedo_color = TRIM_COLORS[k % TRIM_COLORS.size()]
		trim_mat.emission = trim_mat.albedo_color
		pop = 0.0
		if n > 0:
			main.puff(position + Vector3.UP * 2.0, Color(1, 1, 1), 18, 0.25)
	pop = minf(1.0, pop + delta * 1.6)
	var s := 1.0 + sin(pop * PI * 1.5) * (1.0 - pop) * 0.4 if pop < 1.0 else 1.0
	parts.scale = Vector3.ONE * clampf(pop * 3.0, 0.0, 1.0) * s
	var y := 0.0
	var shake := 0.0
	if phase == "launch":
		var t := launch_t - LIFTOFF
		if t > 0.0:
			y = 0.5 * 7.0 * t * t + 1.0 * t
		if launch_t > 1.5:
			shake = 0.04 if t < 0.0 else 0.015
		flame.emitting = launch_t > LIFTOFF - 0.4
		smoke.emitting = launch_t > LIFTOFF - 0.6 and launch_t < LIFTOFF + 2.5
		if launch_t >= LIFTOFF and confetti_n != n:
			confetti_n = n
			_confetti(position + Vector3.UP * 5.0, 90)
			_confetti(Vector3(0, 3.2, -2.0), 60)
	else:
		flame.emitting = false
		smoke.emitting = false
	wobble = maxf(0.0, wobble - delta * 0.8)
	wobble_t += delta
	parts.position = Vector3(randf_range(-shake, shake), y, randf_range(-shake, shake))
	parts.rotation.z = sin(wobble_t * 18.0) * wobble * 0.12
	parts.rotation.x = cos(wobble_t * 14.0) * wobble * 0.06
	# Squash a little when burping.
	if wobble > 0.0:
		parts.scale *= Vector3(1.0 + wobble * 0.1, 1.0 - wobble * 0.08, 1.0 + wobble * 0.1)


## Oops! A wrong answer makes the rocket wobble and burp a green cloud.
func burp() -> void:
	wobble = 1.0
	main.puff(position + Vector3(0, 0.4, 0.8), Color(0.55, 0.9, 0.35), 22, 0.22)
	main.puff(position + Vector3(0, 5.0, 0.3), Color(0.55, 0.9, 0.35), 10, 0.18)


func _confetti(at: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 3.0
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -5.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.particle_flag_rotate_y = true
	p.color = Color(1.0, 0.3, 0.3)
	p.hue_variation_min = -1.0
	p.hue_variation_max = 1.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.015, 0.13)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(0.3, 0.3, 0.3)
	bm.material = m
	p.mesh = bm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(3.5).timeout.connect(p.queue_free)
