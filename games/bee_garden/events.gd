extends Node3D
## Visuals for the garden's surprise events, drawn from main's (snapshotted) state on every machine:
##  - RAIN: a grey cloud over the bed and falling drops (the plants drink, everything grows faster);
##  - RAINBOW: after the rain, a rainbow arches over the garden (pollen makes DOUBLE honey);
##  - QUEEN BEE: a big friendly bee with a crown visits and asks for one kind of pollen;
##  - GOLDEN FLOWER: sparkles over the flower that gives golden pollen.
## Wasp raids reuse the normal wasps (pest.gd). No fighting: pests just get shooed away.

const W := preload("res://games/bee_garden/world.gd")
const QUEEN_HOME := Vector3(-3.4, 1.5, -2.5)

var main
var cloud: Node3D
var rain: CPUParticles3D
var rainbow: MeshInstance3D
var queen: Node3D
var queen_wings: Array[MeshInstance3D] = []
var queen_want: MeshInstance3D
var sparkle: CPUParticles3D
var t := 0.0


func _ready() -> void:
	name = "Events"
	# Rain cloud (one merged mesh) + rain drops.
	cloud = Node3D.new()
	add_child(cloud)
	var st := W._st()
	for k in 9:
		var a := TAU * k / 9.0
		W.vsphere(st, Vector3(cos(a) * 2.6, 0.3 * sin(a * 2.0), sin(a) * 1.2), Vector3(1.6, 1.0, 1.3), Color(0.72, 0.75, 0.85), 10, 6)
	W.vsphere(st, Vector3(0, 0.4, 0), Vector3(2.4, 1.3, 1.6), Color(0.78, 0.8, 0.9), 12, 6)
	var cm := W._mesh_of(W.vmesh(st))
	cloud.add_child(cm)
	cloud.position = Vector3(0, 5.2, -0.2)
	cloud.visible = false
	rain = CPUParticles3D.new()
	rain.amount = 80
	rain.lifetime = 0.7
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(3.8, 0.1, 1.6)
	rain.direction = Vector3.DOWN
	rain.spread = 3.0
	rain.initial_velocity_min = 7.0
	rain.initial_velocity_max = 8.0
	rain.gravity = Vector3(0, -4.0, 0)
	var dm := W.box(Vector3(0.025, 0.22, 0.025))
	var dmat := W.mat(Color(0.6, 0.8, 1.0, 0.7), 0.6)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.material = dmat
	rain.mesh = dm
	rain.emitting = false
	rain.position = Vector3(0, 4.6, -0.2)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	# Rainbow arch behind the garden.
	var rs := SurfaceTool.new()
	rs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.7, 0.25), Color(1.0, 0.95, 0.35), Color(0.4, 0.9, 0.45),
		Color(0.4, 0.65, 1.0), Color(0.75, 0.45, 1.0)]
	for b in cols.size():
		var r0 := 16.0 - b * 0.9
		var r1 := r0 - 0.9
		for i in 24:
			var a0 := PI * i / 24.0
			var a1 := PI * (i + 1) / 24.0
			var q: Array[Vector3] = [Vector3(cos(a0) * r0, sin(a0) * r0, 0), Vector3(cos(a1) * r0, sin(a1) * r0, 0),
				Vector3(cos(a1) * r1, sin(a1) * r1, 0), Vector3(cos(a0) * r1, sin(a0) * r1, 0)]
			for idx in [0, 1, 2, 0, 2, 3]:
				rs.set_color(cols[b])
				rs.set_normal(Vector3.BACK)
				rs.add_vertex(q[idx])
	var rm := rs.commit()
	var rmat := StandardMaterial3D.new()
	rmat.vertex_color_use_as_albedo = true
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1, 1, 1, 0.65)
	rm.surface_set_material(0, rmat)
	rainbow = W._mesh_of(rm)
	rainbow.position = Vector3(0, -3.0, -14.0)
	rainbow.visible = false
	add_child(rainbow)
	_build_queen()
	sparkle = CPUParticles3D.new()
	sparkle.amount = 14
	sparkle.lifetime = 1.0
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkle.emission_sphere_radius = 0.35
	sparkle.direction = Vector3.UP
	sparkle.spread = 60.0
	sparkle.initial_velocity_min = 0.3
	sparkle.initial_velocity_max = 0.8
	sparkle.gravity = Vector3.ZERO
	var sm := W.sphere(0.035, 6)
	sm.material = W.cmat(Color(1.0, 0.9, 0.4), 2.5)
	sparkle.mesh = sm
	sparkle.emitting = false
	sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparkle)


## The Queen: a big round bee with a golden crown, a purple sash and a pollen basket she wants filled.
func _build_queen() -> void:
	queen = Node3D.new()
	add_child(queen)
	var st := W._st()
	W.vsphere(st, Vector3(0, 0, 0.08), Vector3(0.3, 0.28, 0.42), Color(1.0, 0.8, 0.2), 12, 8)
	for z in [0.05, 0.25]:
		W.vsphere(st, Vector3(0, 0, z), Vector3(0.305, 0.285, 0.06), Color(0.15, 0.1, 0.08), 12, 4)
	W.vsphere(st, Vector3(0, 0.05, -0.36), Vector3(0.2, 0.2, 0.2), Color(0.15, 0.1, 0.08), 12, 6)
	for s in [-1.0, 1.0]:
		W.vsphere(st, Vector3(s * 0.09, 0.1, -0.52), Vector3(0.06, 0.07, 0.04), Color(1, 1, 1))
		W.vsphere(st, Vector3(s * 0.09, 0.1, -0.555), Vector3(0.03, 0.04, 0.02), Color(0.1, 0.05, 0.1))
		W.vsphere(st, Vector3(s * 0.15, 0.0, -0.5), Vector3(0.04, 0.03, 0.02), Color(1.0, 0.55, 0.6))
		W.vcyl(st, Vector3(s * 0.08, 0.32, -0.4), 0.012, 0.012, 0.22, Color(0.15, 0.1, 0.08), 5)
		W.vsphere(st, Vector3(s * 0.08, 0.44, -0.4), Vector3(0.035, 0.035, 0.035), Color(1.0, 0.85, 0.3))
	# Crown with jewels.
	W.vcyl(st, Vector3(0, 0.3, -0.33), 0.15, 0.13, 0.12, Color(1.0, 0.85, 0.2), 10)
	for k in 5:
		var a := TAU * k / 5.0
		W.vcyl(st, Vector3(cos(a) * 0.13, 0.4, -0.33 + sin(a) * 0.13), 0.0, 0.04, 0.1, Color(1.0, 0.85, 0.2), 4)
	W.vsphere(st, Vector3(0, 0.34, -0.47), Vector3(0.03, 0.03, 0.02), Color(0.9, 0.2, 0.4))
	W.vsphere(st, Vector3(0, 0.0, -0.2), Vector3(0.31, 0.06, 0.08), Color(0.6, 0.35, 0.95))
	queen.add_child(W._mesh_of(W.vmesh(st, 0.15)))
	var wing_mat := W.mat(Color(0.92, 0.97, 1.0, 0.55), 0.3)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for s in [-1.0, 1.0]:
		var wm := W.mesh_node(queen, W.sphere(0.26, 10), wing_mat, Vector3(s * 0.28, 0.24, 0.02), Vector3(1.2, 0.12, 0.7))
		wm.set_meta("side", s)
		queen_wings.append(wm)
	# The flower she wants floats above her head.
	queen_want = W.mesh_node(queen, W.cyl(0.18, 0.18, 0.03, 10), W.cmat(Color.WHITE, 0.6), Vector3(0, 0.85, -0.2))
	queen_want.rotation.x = 1.2
	queen.visible = false
	queen.position = QUEEN_HOME + Vector3(-6, 3, -4)


func update_from(delta: float) -> void:
	t += delta
	var raining: bool = main.rain_t > 0.0
	cloud.visible = raining or cloud.scale.x > 0.05
	var cs := 1.0 if raining else 0.0
	cloud.scale = cloud.scale.lerp(Vector3.ONE * cs, 1.0 - exp(-3.0 * delta)) if cloud.visible else Vector3.ONE * 0.01
	cloud.position.x = sin(t * 0.3) * 0.6
	rain.emitting = raining
	rainbow.visible = main.rainbow_t > 0.0
	if rainbow.visible:
		var a := clampf(main.rainbow_t / 3.0, 0.0, 1.0)
		(rainbow.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = 0.65 * a
	# Queen: flies in to her spot while the event lasts, then home again.
	var here: bool = main.event == "queen"
	var want_pos := QUEEN_HOME + Vector3(sin(t * 0.7) * 0.4, sin(t * 1.3) * 0.15, cos(t * 0.5) * 0.3) if here \
		else QUEEN_HOME + Vector3(-7.0, 4.0, -5.0)
	if here and not queen.visible:
		queen.visible = true
		queen.position = QUEEN_HOME + Vector3(-7.0, 4.0, -5.0)
	if queen.visible:
		queen.position = queen.position.lerp(want_pos, 1.0 - exp(-1.5 * delta))
		var to: Vector3 = Vector3(0, 0, 3.8) - queen.position
		queen.rotation.y = lerp_angle(queen.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-3.0 * delta))
		for wm in queen_wings:
			var side: float = wm.get_meta("side")
			wm.rotation.z = side * (0.25 + sin(t * 40.0) * 0.5)
		var kd: Dictionary = W.KINDS[clampi(main.queen_kind, 0, 2)]
		queen_want.material_override = W.cmat(kd.petal, 0.6)
		queen_want.visible = here
		if not here and queen.position.distance_to(want_pos) < 1.0:
			queen.visible = false
	# Golden flower sparkles.
	var gs: int = main.golden_spot
	sparkle.emitting = gs >= 0
	if gs >= 0:
		sparkle.global_position = main.head_pos(gs) + Vector3.UP * 0.1


func queen_pos() -> Vector3:
	return queen.global_position
