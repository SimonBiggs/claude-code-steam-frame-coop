extends Node3D
## A mischievous storm sprite: a little purple thundercloud with glowing eyes. It catches up with the
## dragon and sneaks in to pop one of its lanterns. One or two bubbles pop it.
## Host: simulated here (host_update). TV machine: a ghost that follows the host's snapshots.

var main
var net_id := 0
var vel := Vector3.ZERO
var hp := 1
var target := 0
var life := 0.0
var ghost := false
var net_pos := Vector3.ZERO
var net_vel := Vector3.ZERO
var look: Node3D
var flash := 0.0
var body_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("dr_sprites")
	add_to_group("dr_targets")
	set_meta("kind", "sprite")
	set_meta("radius", 1.4)
	look = Node3D.new()
	add_child(look)
	body_mat = main.make_material(Color(0.42, 0.25, 0.7), 0.6)
	var cloud: StandardMaterial3D = main.color_mat(Color(0.35, 0.32, 0.45), 0.1)
	var eye: StandardMaterial3D = main.color_mat(Color(1.0, 0.95, 0.3), 3.0)
	_part(main.sphere_mesh(0.6), body_mat, Vector3.ZERO, Vector3(1.0, 0.85, 1.0))
	_part(main.sphere_mesh(0.42), cloud, Vector3(-0.5, 0.15, 0.1), Vector3.ONE)
	_part(main.sphere_mesh(0.42), cloud, Vector3(0.5, 0.2, 0.05), Vector3.ONE)
	_part(main.sphere_mesh(0.11), eye, Vector3(-0.2, 0.1, -0.52), Vector3(1.0, 1.3, 0.6))
	_part(main.sphere_mesh(0.11), eye, Vector3(0.2, 0.1, -0.52), Vector3(1.0, 1.3, 0.6))
	var bolt := _part(main.prism_mesh(Vector3(0.3, 0.9, 0.08)), eye, Vector3(0, -0.85, 0), Vector3.ONE)
	bolt.rotation.z = PI


func _part(mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.scale = scl
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	look.add_child(m)
	return m


func hit() -> void:
	flash = 1.0


func host_update(delta: float) -> void:
	life += delta
	var d: Node3D = main.dragon
	if not d.lit[target]:
		target = d.random_lit()
		if target < 0:
			target = 0
	var tp: Vector3 = d.lantern_world(target)
	var to := tp - global_position
	var dist := to.length()
	var approach: float = main.sprite_speed()
	# Match the dragon's speed and drift in towards the lantern (slower near it: a sneaky creep).
	var desired: Vector3 = d.velocity + to / maxf(dist, 0.01) * minf(approach, 1.2 + dist * 0.6)
	desired += Vector3(sin(life * 1.7 + net_id), cos(life * 1.3 + net_id * 2.0) * 0.6, 0.0) * minf(2.5, dist * 0.2)
	vel = vel.lerp(desired, 1.0 - exp(-2.6 * delta))
	global_position += vel * delta
	_animate(delta, tp)
	if dist < 1.1:
		main.on_sprite_reached(self)


func ghost_update(delta: float) -> void:
	net_pos += net_vel * delta
	global_position += net_vel * delta
	global_position = global_position.lerp(net_pos, 1.0 - exp(-6.0 * delta))
	life += delta
	_animate(delta, main.dragon.global_position)


func _animate(delta: float, face: Vector3) -> void:
	flash = maxf(0.0, flash - delta * 5.0)
	body_mat.emission_energy_multiplier = 0.6 + flash * 4.0
	look.position = Vector3(0, sin(life * 3.0 + net_id) * 0.2, 0)
	look.rotation.z = sin(life * 2.3 + net_id) * 0.25
	var to := face - global_position
	to.y = 0.0
	if to.length() > 0.1:
		look.rotation.y = atan2(-to.x, -to.z)
