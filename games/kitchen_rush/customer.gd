extends Node3D
## A cute blobby customer at the serving window, with an order bubble and a patience bar.
## Host: walks in, waits (patience drains), leaves happy or angry. Client: a ghost from snapshots.

const L := preload("res://games/kitchen_rush/layout.gd")
const ItemScript := preload("res://games/kitchen_rush/item.gd")
const COLORS: Array[Color] = [Color(1.0, 0.55, 0.75), Color(0.55, 0.75, 1.0), Color(0.7, 0.55, 1.0),
	Color(1.0, 0.7, 0.35), Color(0.45, 0.9, 0.7), Color(1.0, 0.9, 0.4)]

var main
var net_id := 0
var recipe := "SALAD"
var slot := 0
var color_index := 0
var patience := 60.0
var max_patience := 60.0
var state := "walk_in"  # walk_in, wait, happy, angry
var state_t := 0.0
var ghost := false
var net_target := Vector3.ZERO
var net_started := false
var frac := 1.0

var body: MeshInstance3D
var body_mat: StandardMaterial3D
var bubble: Label3D
var bar_fill: MeshInstance3D
var bar_mat: StandardMaterial3D
var mouth: MeshInstance3D
var bob_t := 0.0
var shown_state := ""


func _ready() -> void:
	add_to_group("kr_customers")
	bob_t = randf() * TAU
	net_target = position
	var col := COLORS[color_index % COLORS.size()]
	body = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 18
	s.rings = 9
	body.mesh = s
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = col
	body_mat.roughness = 0.35
	body_mat.rim_enabled = true
	body_mat.rim = 0.6
	body.material_override = body_mat
	body.scale = Vector3(1.0, 1.15, 1.0)
	body.position.y = 1.15
	add_child(body)
	# Big friendly eyes looking into the kitchen (-X).
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.12
		em.height = 0.24
		em.radial_segments = 12
		em.rings = 6
		eye.mesh = em
		eye.material_override = main.mat(Color.WHITE)
		eye.position = Vector3(-0.4, 0.18, side * 0.17)
		body.add_child(eye)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.06
		pm.height = 0.12
		pm.radial_segments = 10
		pm.rings = 5
		pupil.mesh = pm
		pupil.material_override = main.mat(Color(0.08, 0.08, 0.12))
		pupil.position = Vector3(-0.09, 0.0, 0.0)
		eye.add_child(pupil)
	mouth = MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.05, 0.05, 0.2)
	mouth.mesh = mm
	mouth.material_override = main.mat(Color(0.4, 0.08, 0.12))
	mouth.position = Vector3(-0.46, -0.08, 0.0)
	body.add_child(mouth)
	# Order bubble.
	bubble = Label3D.new()
	bubble.font_size = 56
	bubble.outline_size = 18
	bubble.pixel_size = 0.0055
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.modulate = Color.WHITE
	bubble.position.y = 2.55
	add_child(bubble)
	_set_bubble()
	# Patience bar (faces into the kitchen).
	var bar_bg := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.04, 0.1, 0.9)
	bar_bg.mesh = bb
	bar_bg.material_override = main.mat(Color(0.15, 0.15, 0.2))
	bar_bg.position = Vector3(0.0, 2.15, 0.0)
	add_child(bar_bg)
	bar_fill = MeshInstance3D.new()
	var bf := BoxMesh.new()
	bf.size = Vector3(0.05, 0.08, 0.88)
	bar_fill.mesh = bf
	bar_mat = StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.3, 1.0, 0.4)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(0.3, 1.0, 0.4)
	bar_mat.emission_energy_multiplier = 0.8
	bar_fill.material_override = bar_mat
	bar_fill.position = Vector3(-0.01, 2.15, 0.0)
	add_child(bar_fill)


func _set_bubble() -> void:
	var parts: Array[String] = []
	for k in main.recipe_items(recipe):
		parts.append(ItemScript.display_name(k))
	bubble.text = "%s\n%s" % [recipe, " + ".join(parts)]
	bubble.font_size = 56
	bubble.modulate = Color.WHITE


func slot_pos() -> Vector3:
	return Vector3(L.CUSTOMER_X, 0.0, L.CUSTOMER_Z[slot])


## Where a runner stands to serve this customer.
func serve_point() -> Vector3:
	return Vector3(L.SERVE_X, 0.0, L.CUSTOMER_Z[slot])


func waiting() -> bool:
	return state == "wait" or state == "walk_in"


func _process(delta: float) -> void:
	bob_t += delta * (9.0 if state == "happy" else 3.0)
	state_t += delta
	if not ghost:
		_simulate(delta)
	else:
		if not net_started:
			net_started = true
			global_position = net_target
		global_position = global_position.lerp(net_target, 1.0 - exp(-10.0 * delta))
	# Looks: bounce, colour of the patience bar, mood.
	var hop := absf(sin(bob_t)) * (0.35 if state == "happy" else 0.04)
	body.position.y = 1.15 + hop
	var shake := sin(bob_t * 7.0) * 0.06 if (state == "angry" or (state == "wait" and frac < 0.25)) else 0.0
	body.position.z = shake
	bar_fill.scale.z = maxf(frac, 0.001)
	bar_fill.position.z = -0.44 * (1.0 - frac)
	var bar_col := Color(1.0, 0.25, 0.2).lerp(Color(0.3, 1.0, 0.4), clampf(frac * 1.6 - 0.2, 0.0, 1.0))
	bar_mat.albedo_color = bar_col
	bar_mat.emission = bar_col
	bar_fill.visible = waiting()
	if state != shown_state:
		shown_state = state
		match state:
			"happy":
				bubble.text = "YUM!\nThank you!"
				bubble.modulate = Color(1.0, 0.95, 0.4)
				mouth.scale = Vector3(1.0, 2.0, 1.4)
			"angry":
				bubble.text = "HMPH!"
				bubble.modulate = Color(1.0, 0.4, 0.3)
				body_mat.albedo_color = Color(0.95, 0.3, 0.25)
				mouth.scale = Vector3(1.0, 0.6, 0.6)
			_:
				_set_bubble()


func _simulate(delta: float) -> void:
	match state:
		"walk_in":
			var target := slot_pos()
			global_position = global_position.move_toward(target, delta * 2.5)
			if global_position.distance_to(target) < 0.05:
				state = "wait"
		"wait":
			if not main.in_break:
				patience -= delta * (1.35 if main.fire_on else 1.0)
			frac = clampf(patience / max_patience, 0.0, 1.0)
			if patience <= 0.0:
				state = "angry"
				state_t = 0.0
				main.on_customer_angry(self)
		"happy", "angry":
			if state_t > 1.2:
				var away := Vector3(10.5, 0.0, global_position.z + (3.0 if slot >= 2 else -3.0))
				global_position = global_position.move_toward(away, delta * 3.0)
				if global_position.distance_to(away) < 0.1:
					queue_free()


## Host: the order was delivered.
func serve() -> void:
	state = "happy"
	state_t = 0.0


const STATES := ["walk_in", "wait", "happy", "angry"]


## Snapshot entry, packed as floats: [id, recipe, x, y, z, patience fraction, state, colour, slot]
func net_state() -> PackedFloat32Array:
	var p := global_position
	return PackedFloat32Array([net_id, ItemScript.RECIPE_NAMES.find(recipe), p.x, p.y, p.z, frac, STATES.find(state), color_index, slot])


func apply_net(st: PackedFloat32Array) -> void:
	net_target = Vector3(st[2], st[3], st[4])
	frac = st[5]
	state = STATES[clampi(int(st[6]), 0, STATES.size() - 1)]
	slot = int(st[8])
