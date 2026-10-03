extends Node3D
## THE STORM KING: a big grumpy thundercloud with a face, on boss levels. It stays ahead of the dragon
## (never in the way, so the rider doesn't need sharp turns), throws storm sprites and is guarded by
## glowing orbs circling it. Co-op finish: the gunners pop every orb, the cloud gets dizzy and opens a
## golden ring in its middle, and the RIDER flies through the ring to blow the storm away.
## Host: simulated here. TV machine: a ghost following the snapshots (orb hp, ring, defeat).

const Course := preload("res://games/dragon_rider/course.gd")
const AHEAD := 52.0
const ORBIT := 9.0
const RING_R := 9.5

var main
var ghost := false
var orb_hp: Array = []        # ints; 0 = popped
var orbs: Array = []          # MeshInstance3D targets
var ring_open := false
var ring_normal := Vector3.FORWARD
var defeated := false
var t := 0.0
var hold_t := 0.0
var yaw := 0.0
var thunder_t := 6.0
var net_pos := Vector3.ZERO
var net_has := false

var puffs: MeshInstance3D
var puff_mat: StandardMaterial3D
var core: Node3D
var ring: MeshInstance3D
var bolts: Array = []


func setup(n_orbs: int, hp: int) -> void:
	orb_hp.clear()
	for i in n_orbs:
		orb_hp.append(hp)


func _ready() -> void:
	# A donut of storm puffs (one vertex-coloured mesh) with the grumpy face in the hole.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a := TAU * i / 10.0
		var r := 8.5 + (i % 2) * 1.2
		var c := Color(0.42, 0.36, 0.58).lerp(Color(0.3, 0.26, 0.42), float(i % 3) / 2.0)
		Course._vsphere(st, Vector3(cos(a) * r, sin(a) * r, 0.0), Vector3(4.2, 4.0, 3.4) * (0.9 + (i % 3) * 0.12), c, 12, 7)
	var pm := st.commit()
	puff_mat = StandardMaterial3D.new()
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.roughness = 1.0
	puff_mat.emission_enabled = true
	puff_mat.emission = Color(0.35, 0.2, 0.55)
	puff_mat.emission_energy_multiplier = 0.5
	pm.surface_set_material(0, puff_mat)
	puffs = MeshInstance3D.new()
	puffs.mesh = pm
	add_child(puffs)
	core = Node3D.new()
	add_child(core)
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	Course._vsphere(fst, Vector3.ZERO, Vector3(6.0, 5.4, 4.6), Color(0.3, 0.22, 0.45), 14, 8)
	for s in [-1.0, 1.0]:
		Course._vsphere(fst, Vector3(2.0 * s, 1.0, -4.1), Vector3(1.1, 1.3, 0.6), Color(1.0, 0.95, 0.4))
		Course._vsphere(fst, Vector3(1.85 * s, 0.85, -4.6), Vector3(0.5, 0.6, 0.3), Color(0.12, 0.05, 0.15))
		Course._vbox(fst, Vector3(2.0 * s, 2.6, -4.3), Vector3(2.4, 0.5, 0.5), Color(0.15, 0.1, 0.2))
	Course._vbox(fst, Vector3(0, -1.9, -4.3), Vector3(3.2, 0.5, 0.4), Color(0.12, 0.05, 0.15))
	var fm := fst.commit()
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.emission_enabled = true
	fmat.emission = Color(0.5, 0.4, 0.3)
	fmat.emission_energy_multiplier = 0.6
	fm.surface_set_material(0, fmat)
	var face := MeshInstance3D.new()
	face.mesh = fm
	core.add_child(face)
	var bolt_mat: StandardMaterial3D = main.color_mat(Color(1.0, 0.95, 0.4), 3.0)
	for s in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		b.mesh = main.prism_mesh(Vector3(1.4, 6.0, 0.3))
		b.material_override = bolt_mat
		b.position = Vector3(6.0 * s, -9.0, 0)
		b.rotation.z = PI + 0.3 * s
		b.visible = false
		add_child(b)
		bolts.append(b)
	var orb_mat: StandardMaterial3D = main.color_mat(Color(1.0, 0.85, 0.3), 2.5)
	for i in orb_hp.size():
		var o := MeshInstance3D.new()
		o.mesh = main.sphere_mesh(1.3)
		o.material_override = orb_mat
		o.set_meta("kind", "orb")
		o.set_meta("orb", i)
		o.set_meta("radius", 2.4)
		o.add_to_group("dr_targets")
		add_child(o)
		orbs.append(o)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RING_R - 0.6
	tm.outer_radius = RING_R + 0.6
	tm.rings = 32
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = main.color_mat(Color(1.0, 0.85, 0.3), 2.6)
	ring.rotation.x = PI / 2.0
	ring.visible = false
	add_child(ring)
	for c in get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sync_orbs()


func get_vel() -> Vector3:
	return main.dragon.velocity


func orbs_left() -> int:
	var n := 0
	for h in orb_hp:
		if int(h) > 0:
			n += 1
	return n


## Host: a bubble hit orb i. Returns true when it popped.
func hit_orb(i: int) -> bool:
	if i < 0 or i >= orb_hp.size() or int(orb_hp[i]) <= 0:
		return false
	orb_hp[i] = int(orb_hp[i]) - 1
	_sync_orbs()
	return int(orb_hp[i]) <= 0


func _sync_orbs() -> void:
	for i in orbs.size():
		var o: MeshInstance3D = orbs[i]
		var alive := int(orb_hp[i]) > 0
		o.visible = alive
		if not alive and o.is_in_group("dr_targets"):
			o.remove_from_group("dr_targets")


func open_ring() -> void:
	if ring_open:
		return
	ring_open = true
	var d: Node3D = main.dragon
	var to := global_position - d.global_position
	to.y = 0.0
	ring_normal = to.normalized() if to.length() > 0.1 else Basis(Vector3.UP, d.yaw) * Vector3.FORWARD
	yaw = atan2(ring_normal.x, ring_normal.z)


func host_update(delta: float) -> void:
	t += delta
	var d: Node3D = main.dragon
	var fwd: Vector3 = Basis(Vector3.UP, d.yaw) * Vector3.FORWARD
	if defeated:
		global_position += Vector3(0, 6.0, 0) * delta + fwd * d.speed * delta
	elif not ring_open:
		var want: Vector3 = d.global_position + fwd * AHEAD + Vector3.UP * 7.0
		want.y = clampf(want.y, 20.0, 100.0)
		global_position = global_position.lerp(want, 1.0 - exp(-0.9 * delta))
		var to := d.global_position - global_position
		yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-2.0 * delta))
	else:
		# Hold still so the rider can aim for the ring; if they flew past, float ahead again.
		var rel: Vector3 = d.core_position() - global_position
		if rel.dot(ring_normal) > 20.0 or rel.length() > 150.0:
			hold_t += delta
			if hold_t > 2.5:
				hold_t = 0.0
				global_position = d.global_position + fwd * (AHEAD + 10.0) + Vector3.UP * 4.0
				ring_normal = fwd
				yaw = atan2(fwd.x, fwd.z)
		else:
			hold_t = 0.0
	_animate(delta)


func ghost_update(delta: float) -> void:
	if not net_has:
		return
	global_position = global_position.lerp(net_pos, 1.0 - exp(-4.0 * delta))
	if global_position.distance_to(net_pos) > 30.0:
		global_position = net_pos
	t += delta
	_animate(delta)


func _animate(delta: float) -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	var n := orbs.size()
	for i in n:
		var o: MeshInstance3D = orbs[i]
		var a := t * 0.3 + TAU * i / maxf(1.0, n)
		var before := o.global_position
		o.position = Vector3(cos(a) * (ORBIT + 4.0), sin(a) * (ORBIT + 4.0), -2.0 + sin(t * 2.0 + i) * 1.0)
		o.scale = Vector3.ONE * (1.0 + sin(t * 6.0 + i) * 0.08)
		if delta > 0.0:
			o.set_meta("vel", (o.global_position - before) / delta)  # for the gunners' aim assist lead
	puffs.rotation.z = sin(t * 0.4) * 0.08
	if defeated:
		core.visible = false
		ring.visible = false
		puff_mat.emission = Color(1.0, 1.0, 1.0)
		puff_mat.emission_energy_multiplier = lerpf(puff_mat.emission_energy_multiplier, 1.2, 1.0 - exp(-2.0 * delta))
		for b in bolts:
			(b as MeshInstance3D).visible = false
		return
	ring.visible = ring_open
	if ring_open:
		# Dizzy: the face spins and shrinks away, revealing the golden ring.
		core.scale = core.scale.lerp(Vector3.ONE * 0.25, 1.0 - exp(-2.0 * delta))
		core.rotation.z += delta * 5.0
		ring.scale = Vector3.ONE * (1.0 + sin(t * 5.0) * 0.05)
	else:
		core.scale = Vector3.ONE * (1.0 + sin(t * 2.0) * 0.04)
		core.position.y = sin(t * 1.3) * 0.6
	thunder_t -= delta
	var flash := thunder_t < 0.35 and thunder_t > 0.0
	for b in bolts:
		(b as MeshInstance3D).visible = flash
	if thunder_t <= 0.0:
		thunder_t = randf_range(4.0, 8.0)


func net_state() -> Array:
	return [global_position, yaw, orb_hp, ring_open, ring_normal, defeated]


func apply_net_state(a: Array) -> void:
	if a.size() < 6:
		return
	net_pos = a[0]
	yaw = a[1]
	var hp: Array = a[2]
	var changed := hp.size() != orb_hp.size()
	for i in mini(hp.size(), orb_hp.size()):
		if int(hp[i]) != int(orb_hp[i]):
			changed = true
	orb_hp = hp.duplicate()
	if changed:
		_sync_orbs()
	ring_open = a[3]
	ring_normal = a[4]
	defeated = a[5]
	if not net_has:
		net_has = true
		global_position = net_pos
