extends Node3D
## The TV crew's hands-on jobs: carry the fuel canister to the hatch by the rocket, hold ACTION next
## to the leaky, sparking pipe to fix it, pick up three LOOSE BOLTS, fetch the PAINT pot the pilot asks
## for, and catch the SPACE CAT that sneaks in (it runs away, but gets tired) and pop it in its basket.
## Drawn on both machines from the module dictionaries; the host decides pick-ups, deliveries and
## repairs (see main.gd). Paint pots and bolts are MultiMeshes (one draw call each).

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
var bolt_mm: MultiMesh
var bolt_heads: MultiMeshInstance3D
var bolt_beams: MultiMeshInstance3D
var bolt_beam_mm: MultiMesh
var pot_mm: MultiMesh
var lid_mm: MultiMesh
var pot_pos: Array = []  # current (smoothed) pot positions
var paint_label: Label3D
var cat: Node3D
var cat_tail: Node3D
var cat_label: Label3D
var cat_pos := Vector3.ZERO
var cat_face := 0.0
var basket_glow: MeshInstance3D
var blink_t := 2.0
var cat_eyes: Array = []


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
	pipe_label = _tag(self, "LEAKY PIPE!\nHold A here to fix", 0.0)
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
	_build_bolts()
	_build_paint()
	_build_cat()
	main.set_layers(self, 1)
	main.set_layers(can_label, main.MANUAL_LAYER)  # crew-only tags (billboarded), hidden from the pilot
	main.set_layers(pipe_label, main.MANUAL_LAYER)
	main.set_layers(paint_label, main.MANUAL_LAYER)
	main.set_layers(cat_label, main.MANUAL_LAYER)


func _beam_material(color: Color) -> StandardMaterial3D:
	var bm: StandardMaterial3D = main.make_material(color, 1.0)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return bm


## Three chunky golden bolts (a hex head on a short shaft), each with a thin light beam.
func _build_bolts() -> void:
	var head := CylinderMesh.new()
	head.top_radius = 0.16
	head.bottom_radius = 0.16
	head.height = 0.1
	head.radial_segments = 6
	head.rings = 1
	bolt_mm = MultiMesh.new()
	bolt_mm.transform_format = MultiMesh.TRANSFORM_3D
	bolt_mm.mesh = head
	bolt_mm.instance_count = 6  # 3 heads + 3 shafts (scaled)
	bolt_heads = MultiMeshInstance3D.new()
	bolt_heads.multimesh = bolt_mm
	var gold: StandardMaterial3D = main.make_material(Color(1.0, 0.8, 0.3), 0.6)
	gold.metallic = 0.7
	gold.roughness = 0.3
	bolt_heads.material_override = gold
	bolt_heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bolt_heads)
	bolt_beam_mm = MultiMesh.new()
	bolt_beam_mm.transform_format = MultiMesh.TRANSFORM_3D
	bolt_beam_mm.mesh = main.cyl_mesh(0.12, 0.12, 4.0, 8)
	bolt_beam_mm.instance_count = 3
	bolt_beams = MultiMeshInstance3D.new()
	bolt_beams.multimesh = bolt_beam_mm
	bolt_beams.material_override = _beam_material(Color(1.0, 0.85, 0.3, 0.2))
	bolt_beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bolt_beams)
	_hide_bolts()


func _hide_bolts() -> void:
	var gone := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0))
	for i in bolt_mm.instance_count:
		bolt_mm.set_instance_transform(i, gone)
	for i in 3:
		bolt_beam_mm.set_instance_transform(i, gone)


## The paint shop outside: a low bench with four paint pots (red, blue, yellow, green).
func _build_paint() -> void:
	var pot := CylinderMesh.new()
	pot.top_radius = 0.2
	pot.bottom_radius = 0.18
	pot.height = 0.38
	pot.radial_segments = 14
	pot.rings = 1
	pot_mm = MultiMesh.new()
	pot_mm.transform_format = MultiMesh.TRANSFORM_3D
	pot_mm.use_colors = true
	pot_mm.mesh = pot
	pot_mm.instance_count = 4
	lid_mm = MultiMesh.new()
	lid_mm.transform_format = MultiMesh.TRANSFORM_3D
	lid_mm.use_colors = true
	lid_mm.mesh = main.sphere_mesh(0.19)
	lid_mm.instance_count = 4
	for i in 4:
		pot_mm.set_instance_color(i, Color(0.85, 0.85, 0.9))
		lid_mm.set_instance_color(i, P.COLORS[i])
		pot_pos.append(P.PAINT_SPOTS[i] + Vector3(0, 0.45, 0))
	var a := MultiMeshInstance3D.new()
	a.multimesh = pot_mm
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.metallic = 0.5
	pm.roughness = 0.4
	a.material_override = pm
	add_child(a)
	var b := MultiMeshInstance3D.new()
	b.multimesh = lid_mm
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.emission_enabled = true
	lm.emission = Color(0.25, 0.25, 0.25)
	b.material_override = lm
	add_child(b)
	var bench := MeshInstance3D.new()
	var first: Vector3 = P.PAINT_SPOTS[0]
	var last: Vector3 = P.PAINT_SPOTS[3]
	bench.mesh = main.box_mesh(Vector3(0.75, 0.45, absf(last.z - first.z) + 1.0))
	bench.material_override = main.make_material(Color(0.55, 0.36, 0.22), 0.0)
	bench.position = (first + last) / 2.0 + Vector3(-0.1, 0.225, 0)
	add_child(bench)
	_place_pots(-1, -1, 1.0)
	paint_label = _tag(self, "PAINT SHOP\nAsk the pilot which colour!", 0.0)
	paint_label.position = P.PAINT_SPOTS[1].lerp(P.PAINT_SPOTS[2], 0.5) + Vector3(0, 1.7, 0)
	paint_label.visible = false


func _place_pots(carry_color: int, carrier: int, k: float) -> void:
	for i in 4:
		var target: Vector3 = P.PAINT_SPOTS[i] + Vector3(0, 0.45 + 0.19, 0)
		if i == carry_color and carrier >= 0 and carrier < main.players.size():
			var p = main.players[carrier]
			target = p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(0.0, 0.75, -0.6)
		var cur: Vector3 = pot_pos[i]
		cur = cur.lerp(target, k)
		pot_pos[i] = cur
		pot_mm.set_instance_transform(i, Transform3D(Basis(), cur))
		lid_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, 0.35, 1.0)), cur + Vector3(0, 0.19, 0)))


## A fluffy orange space cat with a waving tail, and its basket by the doorway. The cat's body and
## the basket are each baked into one vertex-coloured mesh (one draw call each).
func _build_cat() -> void:
	var fur := Color(1.0, 0.62, 0.25)
	var cream := Color(1.0, 0.9, 0.75)
	var parts: Array = [
		[main.capsule_mesh(0.17, 0.62), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.3, 0)), fur],
		[main.sphere_mesh(0.17), Transform3D(Basis(), Vector3(0, 0.5, -0.33)), fur],
		[main.sphere_mesh(0.08), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 0.8)), Vector3(0, 0.45, -0.47)), cream],
		[main.sphere_mesh(0.03), Transform3D(Basis(), Vector3(0, 0.47, -0.54)), Color(1.0, 0.5, 0.6)],
	]
	for side in [-1.0, 1.0]:
		parts.append([main.cyl_mesh(0.0, 0.07, 0.13, 4), Transform3D(Basis(Vector3.BACK, -side * 0.3), Vector3(side * 0.09, 0.66, -0.33)), fur])
		parts.append([main.capsule_mesh(0.045, 0.2), Transform3D(Basis(), Vector3(side * 0.1, 0.1, -0.22)), cream])
		parts.append([main.capsule_mesh(0.045, 0.2), Transform3D(Basis(), Vector3(side * 0.1, 0.1, 0.22)), fur])
	cat = Node3D.new()
	add_child(cat)
	var body := MeshInstance3D.new()
	body.mesh = main.merged_mesh("space_cat", parts)
	body.material_override = main.vertex_mat()
	cat.add_child(body)
	var eye_mesh: ArrayMesh = main.merged_mesh("cat_eyes", [
		[main.sphere_mesh(0.035), Transform3D(Basis(), Vector3(-0.07, 0, 0)), Color(0.4, 1.0, 0.5)],
		[main.sphere_mesh(0.035), Transform3D(Basis(), Vector3(0.07, 0, 0)), Color(0.4, 1.0, 0.5)]])
	var eyes := MeshInstance3D.new()
	eyes.mesh = eye_mesh
	var em := StandardMaterial3D.new()
	em.vertex_color_use_as_albedo = true
	em.vertex_color_is_srgb = true
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eyes.material_override = em
	eyes.position = Vector3(0, 0.54, -0.47)
	cat.add_child(eyes)
	cat_eyes.append(eyes)
	cat_tail = Node3D.new()
	cat_tail.position = Vector3(0, 0.35, 0.36)
	cat.add_child(cat_tail)
	var tail := MeshInstance3D.new()
	tail.mesh = main.cyl_mesh(0.035, 0.05, 0.45, 8)
	tail.material_override = main.make_material(fur, 0.05)
	tail.position = Vector3(0, 0.2, 0.05)
	tail.rotation.x = 0.4
	cat_tail.add_child(tail)
	cat_label = _tag(cat, "SPACE CAT!\nWalk into it to catch it", 1.1)
	cat.visible = false
	# Basket: a woven ring round a pink cushion.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.38
	tm.outer_radius = 0.55
	tm.rings = 16
	tm.ring_segments = 6
	var basket := MeshInstance3D.new()
	basket.mesh = main.merged_mesh("cat_basket", [
		[tm, Transform3D(Basis.from_scale(Vector3(1, 1.6, 1)), Vector3(0, 0.12, 0)), Color(0.7, 0.5, 0.3)],
		[main.cyl_mesh(0.42, 0.42, 0.1, 14), Transform3D(Basis(), Vector3(0, 0.06, 0)), Color(0.95, 0.4, 0.5)]])
	basket.material_override = main.vertex_mat()
	basket.position = P.CAT_BASKET
	add_child(basket)
	basket_glow = MeshInstance3D.new()
	basket_glow.mesh = main.cyl_mesh(0.7, 0.7, 2.0, 14)
	basket_glow.material_override = _beam_material(Color(1.0, 0.5, 0.7, 0.2))
	basket_glow.position = P.CAT_BASKET + Vector3(0, 1.0, 0)
	basket_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	basket_glow.visible = false
	add_child(basket_glow)


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
	var bolts := {}
	var paint := {}
	var cat_m := {}
	for m in modules:
		match str(m.type):
			"canister":
				can = m
			"pipe":
				pipe = m
			"bolts":
				bolts = m
			"paint":
				paint = m
			"cat":
				cat_m = m
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
	_update_bolts(bolts)
	_update_paint(paint, delta)
	_update_cat(cat_m, delta)


func _update_bolts(m: Dictionary) -> void:
	if m.is_empty() or m.done:
		if bolt_beams.visible:
			_hide_bolts()
			bolt_beams.visible = false
			bolt_heads.visible = false
		return
	bolt_beams.visible = true
	bolt_heads.visible = true
	var spots: Array = m.spots
	var got: Array = m.got
	var gone := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0))
	for i in 3:
		if bool(got[i]):
			bolt_mm.set_instance_transform(i, gone)
			bolt_mm.set_instance_transform(i + 3, gone)
			bolt_beam_mm.set_instance_transform(i, gone)
			continue
		var at: Vector3 = P.BOLT_SPOTS[int(spots[i])] + Vector3(0, 0.35 + sin(t * 3.0 + i) * 0.08, 0)
		var spin := Basis(Vector3.UP, t * 2.5 + i) * Basis(Vector3.RIGHT, 0.5)
		bolt_mm.set_instance_transform(i, Transform3D(spin, at))
		bolt_mm.set_instance_transform(i + 3, Transform3D(spin * Basis.from_scale(Vector3(0.45, 2.6, 0.45)), at + spin * Vector3(0, -0.16, 0)))
		bolt_beam_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(at.x, 2.0, at.z)))


func _update_paint(m: Dictionary, delta: float) -> void:
	var active: bool = not m.is_empty() and not m.done
	paint_label.visible = active and int(m.carrier) < 0
	var carry := -1
	var carrier := -1
	if active:
		carrier = int(m.carrier)
		carry = int(m.carry)
	_place_pots(carry, carrier, 1.0 - exp(-18.0 * delta))
	if active and carrier >= 0:
		hatch_glow.visible = true


func _update_cat(m: Dictionary, delta: float) -> void:
	var active: bool = not m.is_empty() and not m.done
	basket_glow.visible = active and int(m.carrier) >= 0
	if not active:
		cat.visible = false
		return
	var target: Vector3 = m.pos
	var carrier := int(m.carrier)
	var carried: bool = carrier >= 0 and carrier < main.players.size()
	if carried:
		var p = main.players[carrier]
		target = p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(0.0, 0.7, -0.55)
	if not cat.visible:
		cat.visible = true
		cat_pos = target
	var prev := cat_pos
	cat_pos = cat_pos.lerp(target, 1.0 - exp(-12.0 * delta))
	var step := cat_pos - prev
	step.y = 0.0
	var moving := step.length() > 0.002
	if moving:
		cat_face = lerp_angle(cat_face, atan2(-step.x, -step.z), 1.0 - exp(-10.0 * delta))
	if carried:
		cat_face = main.players[carrier].yaw
	cat.global_position = cat_pos
	cat.rotation.y = cat_face
	# Scampering bounce, a swishy tail and slow blinks.
	var hop := absf(sin(t * 14.0)) * 0.08 if moving and not carried else 0.0
	cat.position.y = cat_pos.y + hop
	cat.scale = Vector3(1.0, 1.0 - hop * 0.8, 1.0 + hop * 0.6)
	cat_tail.rotation.z = sin(t * (9.0 if moving else 3.0)) * 0.5
	blink_t -= delta
	var closed := blink_t < 0.12
	if blink_t <= 0.0:
		blink_t = randf_range(2.0, 4.5)
	for e in cat_eyes:
		(e as Node3D).scale = Vector3(1.0, 0.15 if closed else 1.0, 1.0)
	cat_label.visible = not carried


func _on_bench(pos: Vector3) -> bool:
	return absf(absf(pos.x) - 9.0) < 0.1
