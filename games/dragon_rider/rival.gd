extends Node3D
## GOLDIE, the cheeky golden rival dragon on race levels. She flies the same rings a little faster than
## a dragon that never flaps, so the rider has to flap (trigger) to win. The gunners can slow her down:
## three bubbles wrap her in a big bubble and she floats along slowly for a few seconds.
## Host: simulated here (host_update). TV machine: a ghost following the host's snapshots.

const Course := preload("res://games/dragon_rider/course.gd")
const HITS_TO_WRAP := 3
const WRAP_TIME := 3.0

var main
var ghost := false
var ring_i := 0
var speed := 14.2
var yaw := 0.0
var vel := Vector3.ZERO
var bubbled_t := 0.0
var hits := 0
var finished := false
var flap_phase := 0.0
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_has := false

var model: Node3D
var wing_l: Node3D
var wing_r: Node3D
var wrap: MeshInstance3D


func _ready() -> void:
	add_to_group("dr_targets")
	set_meta("kind", "rival")
	set_meta("radius", 2.4)
	model = Node3D.new()
	add_child(model)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gold := Color(1.0, 0.78, 0.25)
	var belly := Color(1.0, 0.93, 0.65)
	Course._vsphere(st, Vector3(0, 0, 0.3), Vector3(0.9, 0.8, 2.2), gold)
	Course._vsphere(st, Vector3(0, -0.3, 0.3), Vector3(0.7, 0.55, 1.8), belly)
	Course._vsphere(st, Vector3(0, 0.55, -2.0), Vector3(0.6, 0.55, 0.75), gold)
	Course._vsphere(st, Vector3(0, 0.45, -2.65), Vector3(0.4, 0.32, 0.4), gold.lightened(0.1))
	Course._vsphere(st, Vector3(0, 0.1, 2.9), Vector3(0.35, 0.3, 1.4), gold)
	for s in [-1.0, 1.0]:
		Course._vsphere(st, Vector3(0.3 * s, 0.75, -2.35), Vector3(0.13, 0.15, 0.1), Color(1, 1, 1))
		Course._vsphere(st, Vector3(0.32 * s, 0.76, -2.43), Vector3(0.07, 0.09, 0.05), Color(0.1, 0.08, 0.12))
		Course._vsphere(st, Vector3(0.25 * s, 1.15, -1.85), Vector3(0.08, 0.3, 0.08), Color(1.0, 0.45, 0.3))
	var m := st.commit()
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 0.4
	mt.metallic = 0.3
	mt.emission_enabled = true
	mt.emission = Color(0.5, 0.35, 0.05)
	m.surface_set_material(0, mt)
	var body := MeshInstance3D.new()
	body.mesh = m
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(body)
	var wmat: StandardMaterial3D = main.color_mat(Color(1.0, 0.55, 0.3), 0.3)
	for s in [-1.0, 1.0]:
		var w := Node3D.new()
		model.add_child(w)
		w.position = Vector3(0.7 * s, 0.4, 0.0)
		var wm := MeshInstance3D.new()
		wm.mesh = main.box_mesh(Vector3(3.2, 0.08, 1.6))
		wm.material_override = wmat
		wm.position = Vector3(1.6 * s, 0, 0.3)
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(wm)
		if s < 0.0:
			wing_l = w
		else:
			wing_r = w
	wrap = MeshInstance3D.new()
	wrap.mesh = main.sphere_mesh(1.0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.7, 0.95, 1.0, 0.35)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.emission_enabled = true
	bm.emission = Color(0.5, 0.85, 1.0)
	bm.emission_energy_multiplier = 0.7
	wrap.material_override = bm
	wrap.scale = Vector3.ONE * 4.2
	wrap.visible = false
	wrap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wrap)


func get_vel() -> Vector3:
	return vel


## Host: three bubbles wrap her up for a while.
func hit() -> bool:
	if bubbled_t > 0.0:
		return false
	hits += 1
	if hits >= HITS_TO_WRAP:
		hits = 0
		bubbled_t = WRAP_TIME
		return true
	return false


func host_update(delta: float, rings: Array) -> void:
	bubbled_t = maxf(0.0, bubbled_t - delta)
	var spd := speed if bubbled_t <= 0.0 else 4.0
	var target := global_position + Basis(Vector3.UP, yaw) * Vector3.FORWARD * 50.0
	if ring_i < rings.size():
		var r: Dictionary = rings[ring_i]
		var rp: Vector3 = r.pos
		var rn: Vector3 = r.normal
		target = rp + rn.cross(Vector3.UP).normalized() * 2.5
		var rel := global_position - rp
		if rel.dot(rn) > 0.0 and (rel - rn * rel.dot(rn)).length() < 20.0:
			ring_i += 1
			if ring_i >= rings.size():
				finished = true
		elif rel.dot(rn) > 25.0:
			ring_i += 1  # overshot it somehow: carry on
	var to := target - global_position
	var want := atan2(-to.x, -to.z)
	yaw = lerp_angle(yaw, want, 1.0 - exp(-1.6 * delta))
	vel = Basis(Vector3.UP, yaw) * Vector3.FORWARD * spd + Vector3.UP * clampf(to.y * 0.6, -6.0, 6.0)
	global_position += vel * delta
	_animate(delta)


func ghost_update(delta: float) -> void:
	if not net_has:
		return
	net_pos += vel * delta
	global_position = global_position.lerp(net_pos, 1.0 - exp(-6.0 * delta))
	if global_position.distance_to(net_pos) > 15.0:
		global_position = net_pos
	yaw = lerp_angle(yaw, net_yaw, 1.0 - exp(-6.0 * delta))
	_animate(delta)


func _animate(delta: float) -> void:
	flap_phase += delta * (5.0 if bubbled_t <= 0.0 else 1.5)
	var beat := sin(flap_phase) * 0.55
	if wing_l != null:
		wing_l.rotation.z = beat
		wing_r.rotation.z = -beat
	rotation = Vector3(0.0, yaw, 0.0)
	model.position.y = sin(flap_phase) * 0.15
	wrap.visible = bubbled_t > 0.0
	if wrap.visible:
		wrap.scale = Vector3.ONE * (4.2 + sin(flap_phase * 3.0) * 0.15)


func net_state() -> Array:
	return [global_position, yaw, vel, bubbled_t, ring_i, finished]


func apply_net_state(a: Array) -> void:
	if a.size() < 6:
		return
	net_pos = a[0]
	net_yaw = a[1]
	vel = a[2]
	bubbled_t = a[3]
	ring_i = a[4]
	finished = a[5]
	if not net_has:
		net_has = true
		global_position = net_pos
		yaw = net_yaw
