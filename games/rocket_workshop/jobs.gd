extends Node3D
## The TV crew's hands-on jobs: carry the fuel canister to the hatch by the rocket, and hold
## ACTION next to the leaky, sparking pipe to fix it. Drawn on both machines from the module
## dictionaries; the host decides pick-ups, deliveries and repairs (see main.gd).

const P := preload("res://games/rocket_workshop/puzzles.gd")

var main
var canister: Node3D
var can_label: Label3D
var beacon: MeshInstance3D
var hatch_glow: MeshInstance3D
var sparks: CPUParticles3D
var pipe_label: Label3D
var pipe_ring: MeshInstance3D
var pipe_spot := -1
var t := 0.0


func _ready() -> void:
	# Fuel canister: a chunky striped can with a handle.
	canister = Node3D.new()
	add_child(canister)
	var can := MeshInstance3D.new()
	can.mesh = main.cyl_mesh(0.22, 0.22, 0.55, 14)
	can.material_override = main.make_material(Color(0.95, 0.3, 0.25), 0.15)
	can.position.y = 0.28
	canister.add_child(can)
	var band := MeshInstance3D.new()
	band.mesh = main.cyl_mesh(0.225, 0.225, 0.12, 14)
	band.material_override = main.make_material(Color(1.0, 0.85, 0.2), 0.3)
	band.position.y = 0.3
	canister.add_child(band)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.08
	tm.outer_radius = 0.11
	tm.rings = 12
	tm.ring_segments = 4
	handle.mesh = tm
	handle.material_override = main.make_material(Color(0.2, 0.2, 0.25), 0.0)
	handle.rotation.x = PI / 2.0
	handle.position.y = 0.6
	canister.add_child(handle)
	can_label = _tag(canister, "FUEL!\nCarry me to the rocket", 1.25)
	beacon = MeshInstance3D.new()
	beacon.mesh = main.cyl_mesh(0.35, 0.35, 6.0, 12)
	var bm: StandardMaterial3D = main.make_material(Color(1.0, 0.7, 0.2, 0.25), 1.0)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon.material_override = bm
	beacon.position.y = 3.0
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	canister.add_child(beacon)
	canister.visible = false
	hatch_glow = MeshInstance3D.new()
	hatch_glow.mesh = main.cyl_mesh(1.0, 1.0, 3.0, 16)
	hatch_glow.material_override = bm
	hatch_glow.position = main.HATCH_POS + Vector3(0, 1.5, 0)
	hatch_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hatch_glow.visible = false
	add_child(hatch_glow)
	# Pipes along the walls; one of them springs a leak.
	var pipe_mat: StandardMaterial3D = main.make_material(Color(0.55, 0.6, 0.65), 0.0)
	pipe_mat.metallic = 0.6
	pipe_mat.roughness = 0.35
	var joint_mat: StandardMaterial3D = main.make_material(Color(0.75, 0.55, 0.25), 0.0)
	for spot in P.PIPE_SPOTS:
		var along_x := absf(spot.z) > 7.0
		var pipe := MeshInstance3D.new()
		pipe.mesh = main.cyl_mesh(0.09, 0.09, 2.6, 10)
		pipe.material_override = pipe_mat
		pipe.rotation = Vector3(0, 0, PI / 2.0) if along_x else Vector3(PI / 2.0, 0, 0)
		pipe.position = spot
		add_child(pipe)
		var joint := MeshInstance3D.new()
		joint.mesh = main.cyl_mesh(0.14, 0.14, 0.2, 10)
		joint.material_override = joint_mat
		joint.rotation = pipe.rotation
		joint.position = spot
		add_child(joint)
	sparks = CPUParticles3D.new()
	sparks.amount = 24
	sparks.lifetime = 0.5
	sparks.direction = Vector3.UP
	sparks.spread = 70.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 4.0
	sparks.gravity = Vector3(0, -9, 0)
	sparks.color = Color(1.0, 0.85, 0.3)
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = main.make_material(Color(1.0, 0.8, 0.3), 4.0)
	sparks.mesh = sm
	sparks.emitting = false
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)
	pipe_label = _tag(self, "LEAKY PIPE!\nHold ACTION here to fix", 0.0)
	pipe_label.visible = false
	pipe_ring = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.2
	rm.outer_radius = 0.27
	rm.rings = 20
	rm.ring_segments = 4
	pipe_ring.mesh = rm
	pipe_ring.material_override = main.make_material(Color(0.4, 1.0, 0.5), 2.0)
	pipe_ring.visible = false
	add_child(pipe_ring)
	main.set_layers(self, 1)
	main.set_layers(can_label, main.MANUAL_LAYER)  # crew-only tags (billboarded), hidden from the pilot
	main.set_layers(pipe_label, main.MANUAL_LAYER)


func _tag(parent: Node3D, text: String, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.004
	l.outline_size = 12
	l.modulate = Color(1.0, 0.95, 0.75)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # the TV crew walk all round these
	l.position.y = y
	parent.add_child(l)
	return l


## Called every frame on both machines.
func update_visual(modules: Array, delta: float) -> void:
	if not is_inside_tree():
		return
	t += delta
	var can := {}
	var pipe := {}
	for m in modules:
		if m.type == "canister":
			can = m
		elif m.type == "pipe":
			pipe = m
	var show_can: bool = not can.is_empty() and not can.done
	canister.visible = show_can
	hatch_glow.visible = false
	if show_can:
		var carrier: int = can.carrier
		var pos: Vector3 = can.pos
		if carrier >= 0 and carrier < main.players.size():
			var p = main.players[carrier]
			pos = p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(0.0, 0.55, -0.6)
			canister.global_position = canister.global_position.lerp(pos, 1.0 - exp(-20.0 * delta))
			hatch_glow.visible = true
		else:
			canister.global_position = pos + Vector3(0, 0.95 if pos.y < 0.1 and _on_bench(pos) else 0.0, 0)
		beacon.visible = carrier < 0
		can_label.visible = carrier < 0
		canister.rotation.y = sin(t * 2.0) * 0.2
	var show_pipe: bool = not pipe.is_empty() and not pipe.done
	sparks.emitting = show_pipe
	pipe_label.visible = show_pipe
	pipe_ring.visible = show_pipe and float(pipe.progress) > 0.0
	if show_pipe:
		var spot: Vector3 = P.PIPE_SPOTS[int(pipe.spot)]
		var inward := Vector3(-signf(spot.x), 0, 0) if absf(spot.z) < 7.0 else Vector3(0, 0, -1)
		sparks.position = spot + inward * 0.15
		pipe_label.position = spot + inward * 0.6 + Vector3(0, 1.0, 0)
		pipe_ring.position = spot + inward * 0.5 + Vector3(0, 0.5, 0)
		pipe_ring.rotation = Vector3(PI / 2.0, 0, 0)
		var prog: float = pipe.progress
		pipe_ring.scale = Vector3.ONE * (0.3 + prog * 1.2)


func _on_bench(pos: Vector3) -> bool:
	return absf(absf(pos.x) - 9.0) < 0.1
