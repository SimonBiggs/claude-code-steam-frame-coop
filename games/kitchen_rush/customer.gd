extends Node3D
## A cute blobby customer at the serving window, with an order bubble, a little 3D picture of the dish
## they want and a patience bar. Each one has a personality (kid, granny, robot, pirate, alien, knight,
## or the VIP food critic) with its own look, patience, tips and things to say.
## Host: walks in, waits (patience drains), leaves happy or angry. Client: a ghost from snapshots.

const L := preload("res://games/kitchen_rush/layout.gd")
const ItemScript := preload("res://games/kitchen_rush/item.gd")
const COLORS: Array[Color] = [Color(1.0, 0.55, 0.75), Color(0.55, 0.75, 1.0), Color(0.7, 0.55, 1.0),
	Color(1.0, 0.7, 0.35), Color(0.45, 0.9, 0.7), Color(1.0, 0.9, 0.4)]
const TYPE_NAMES := ["kid", "granny", "robot", "pirate", "alien", "knight", "critic"]
## patience x, tips x, size, voice pitch, hello lines, happy lines
const TYPES := {
	"kid": [0.85, 1.0, 0.78, 1.5, ["I'm SO hungry!", "Can I have…", "Yummy time!"], ["YAY! Thank you!", "Best. Dinner. Ever!"]],
	"granny": [1.45, 1.5, 0.95, 0.85, ["Take your time, dear", "Hello, sweetie!"], ["Lovely, dear!", "Just like I make it!"]],
	"robot": [1.0, 1.2, 1.0, 2.0, ["BEEP. FOOD. REQUIRED.", "ORDER PROTOCOL: GO"], ["DELICIOUS.EXE", "BEEP BOOP YUM"]],
	"pirate": [0.9, 1.3, 1.0, 0.75, ["Arr, I be starvin'!", "Ahoy, cook!"], ["Shiver me timbers!", "Arr, tasty!"]],
	"alien": [1.1, 1.2, 0.9, 1.8, ["Zorp! Feed me!", "Take me to your SALAD"], ["ZORP ZORP! Yum!", "10 out of 10 planets!"]],
	"knight": [1.0, 1.2, 1.05, 0.9, ["A feast, good cook!", "Huzzah! I'm hungry!"], ["Huzzah!", "A feast fit for a king!"]],
	"critic": [0.75, 3.0, 1.0, 1.1, ["Hmm… impress me.", "I am THE food critic."], ["MAGNIFIQUE!", "Five stars!"]],
}

var main
var net_id := 0
var recipe := "SALAD"
var slot := 0
var color_index := 0
var ctype := "kid"
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
var eyes: Array[MeshInstance3D] = []
var spinner: Node3D
var blinker: MeshInstance3D
var order_vis: Node3D
var cloud: Node3D
var bob_t := 0.0
var blink_t := 2.0
var hello_t := 0.0
var shown_state := ""


static func type_index(t: String) -> int:
	return maxi(0, TYPE_NAMES.find(t))


static func type_from(i: int) -> String:
	return TYPE_NAMES[clampi(i, 0, TYPE_NAMES.size() - 1)]


func info() -> Array:
	return TYPES.get(ctype, TYPES["kid"])


func _ready() -> void:
	add_to_group("kr_customers")
	bob_t = randf() * TAU
	blink_t = randf_range(1.0, 3.0)
	net_target = position
	var col := COLORS[color_index % COLORS.size()]
	match ctype:
		"robot":
			col = Color(0.72, 0.76, 0.82)
		"alien":
			col = Color(0.45, 0.95, 0.4)
		"critic":
			col = Color(0.55, 0.3, 0.75)
	body = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 18
	s.rings = 9
	body.mesh = s
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = col
	body_mat.roughness = 0.35 if ctype != "robot" else 0.25
	body_mat.metallic = 0.6 if ctype == "robot" else 0.0
	body_mat.rim_enabled = true
	body_mat.rim = 0.6
	body.material_override = body_mat
	body.scale = Vector3(1.0, 1.15, 1.0) * float(info()[2])
	body.position.y = 1.15
	add_child(body)
	# Big friendly eyes looking into the kitchen (-X).
	var eye_spots: Array = [Vector3(-0.4, 0.18, -0.17), Vector3(-0.4, 0.18, 0.17)]
	if ctype == "alien":
		eye_spots.append(Vector3(-0.38, 0.36, 0.0))
	for ep in eye_spots:
		var eye := MeshInstance3D.new()
		if ctype == "robot":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, 0.16, 0.16)
			eye.mesh = bm
			eye.material_override = main.mat(Color(0.4, 0.9, 1.0), 1.5)
		else:
			var em := SphereMesh.new()
			em.radius = 0.12
			em.height = 0.24
			em.radial_segments = 12
			em.rings = 6
			eye.mesh = em
			eye.material_override = main.mat(Color.WHITE)
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
		eye.position = ep
		body.add_child(eye)
		eyes.append(eye)
	mouth = MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.05, 0.05, 0.2)
	mouth.mesh = mm
	mouth.material_override = main.mat(Color(0.4, 0.08, 0.12))
	mouth.position = Vector3(-0.46, -0.08, 0.0)
	body.add_child(mouth)
	_accessories()
	# Order bubble.
	bubble = Label3D.new()
	bubble.font_size = 56
	bubble.outline_size = 18
	bubble.pixel_size = 0.0055
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = false
	bubble.modulate = Color.WHITE
	bubble.position.y = 2.95
	add_child(bubble)
	_set_bubble()
	# A little picture of the dish they want, turning slowly above them.
	order_vis = Node3D.new()
	order_vis.position = Vector3(-0.2, 2.45, 0.0)
	add_child(order_vis)
	_build_order_vis()
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
	for c in get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D = null, glow: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = main.mat(color, glow)
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else body).add_child(m)
	return m


func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 5
	return s


func _cyl(r_top: float, r_bot: float, h: float, segs: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _box_m(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


## Hats, glasses, antennae… (positions are in the body's space: -X faces the kitchen).
func _accessories() -> void:
	match ctype:
		"kid":
			var cap := _part(_sph(0.3), COLORS[(color_index + 2) % COLORS.size()], Vector3(0, 0.38, 0))
			cap.scale = Vector3(1.0, 0.55, 1.0)
			spinner = Node3D.new()
			spinner.position = Vector3(0, 0.62, 0)
			body.add_child(spinner)
			_part(_cyl(0.015, 0.015, 0.12, 6), Color(0.3, 0.3, 0.3), Vector3(0, 0.56, 0))
			_part(_box_m(Vector3(0.42, 0.015, 0.07)), Color(1.0, 0.3, 0.3), Vector3.ZERO, spinner)
			_part(_box_m(Vector3(0.07, 0.015, 0.42)), Color(0.3, 0.6, 1.0), Vector3.ZERO, spinner)
		"granny":
			_part(_sph(0.2), Color(0.85, 0.85, 0.88), Vector3(0.12, 0.45, 0))
			var hair := _part(_sph(0.33), Color(0.85, 0.85, 0.88), Vector3(0.05, 0.25, 0))
			hair.scale = Vector3(1.0, 0.6, 1.05)
			for z in [-0.17, 0.17]:
				var tm := TorusMesh.new()
				tm.inner_radius = 0.1
				tm.outer_radius = 0.125
				tm.rings = 12
				tm.ring_segments = 4
				var g := _part(tm, Color(0.75, 0.6, 0.2), Vector3(-0.5, 0.18, z))
				g.rotation.z = PI / 2.0
			_part(_box_m(Vector3(0.03, 0.02, 0.1)), Color(0.75, 0.6, 0.2), Vector3(-0.53, 0.18, 0))
		"robot":
			_part(_cyl(0.015, 0.015, 0.3, 6), Color(0.4, 0.4, 0.45), Vector3(0, 0.6, 0))
			blinker = _part(_sph(0.06), Color(1.0, 0.2, 0.2), Vector3(0, 0.77, 0), null, 3.0)
			_part(_box_m(Vector3(0.05, 0.3, 0.12)), Color(0.5, 0.52, 0.58), Vector3(0, 0.0, 0.52))
			_part(_box_m(Vector3(0.05, 0.3, 0.12)), Color(0.5, 0.52, 0.58), Vector3(0, 0.0, -0.52))
		"pirate":
			var hat := _part(_cyl(0.32, 0.32, 0.06, 3), Color(0.1, 0.08, 0.1), Vector3(0, 0.45, 0))
			hat.rotation.y = PI
			_part(_cyl(0.18, 0.22, 0.2, 8), Color(0.1, 0.08, 0.1), Vector3(0, 0.55, 0))
			_part(_box_m(Vector3(0.04, 0.12, 0.14)), Color(0.05, 0.05, 0.05), Vector3(-0.5, 0.18, 0.17))
			_part(_sph(0.04), Color(1.0, 0.8, 0.2), Vector3(-0.1, -0.05, 0.48), null, 0.8)
		"alien":
			for z in [-0.18, 0.18]:
				var ant := _part(_cyl(0.012, 0.012, 0.3, 5), Color(0.3, 0.75, 0.3), Vector3(0, 0.58, z))
				ant.rotation.x = z * 1.5
				_part(_sph(0.05), Color(1.0, 0.4, 0.9), Vector3(0, 0.74, z * 1.4), null, 2.0)
		"knight":
			var helm := _part(_sph(0.48), Color(0.75, 0.77, 0.82), Vector3(0.0, 0.25, 0))
			helm.scale = Vector3(1.05, 0.75, 1.05)
			_part(_box_m(Vector3(0.05, 0.05, 0.42)), Color(0.1, 0.1, 0.12), Vector3(-0.47, 0.18, 0))
			var plume := _part(_sph(0.12), Color(0.95, 0.2, 0.25), Vector3(0.1, 0.62, 0))
			plume.scale = Vector3(1.6, 1.0, 0.6)
		"critic":
			_part(_cyl(0.32, 0.32, 0.04, 14), Color(0.08, 0.08, 0.1), Vector3(0, 0.46, 0))
			_part(_cyl(0.2, 0.2, 0.38, 14), Color(0.08, 0.08, 0.1), Vector3(0, 0.66, 0))
			_part(_cyl(0.205, 0.205, 0.06, 14), Color(1.0, 0.8, 0.2), Vector3(0, 0.5, 0), null, 0.8)
			var tm2 := TorusMesh.new()
			tm2.inner_radius = 0.1
			tm2.outer_radius = 0.125
			tm2.rings = 12
			tm2.ring_segments = 4
			var mono := _part(tm2, Color(1.0, 0.8, 0.2), Vector3(-0.5, 0.18, 0.17), null, 0.5)
			mono.rotation.z = PI / 2.0
			var vip := Label3D.new()
			vip.text = "VIP"
			vip.font_size = 64
			vip.outline_size = 16
			vip.pixel_size = 0.004
			vip.modulate = Color(1.0, 0.85, 0.2)
			vip.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			vip.position = Vector3(0, 1.05, 0)
			body.add_child(vip)


## The dish they want: a little plate with the ingredients in a row.
func _build_order_vis() -> void:
	for c in order_vis.get_children():
		c.queue_free()
	var plate := _part(_cyl(0.32, 0.32, 0.03, 16), Color(0.97, 0.97, 1.0), Vector3.ZERO, order_vis)
	plate.rotation.x = 0.0
	var items: Array = main.recipe_items(recipe)
	for i in items.size():
		var it := ItemScript.new()
		it.main = main
		it.kind = items[i]
		it.ghost = true
		it.position = Vector3(0.0, 0.03, (i - (items.size() - 1) * 0.5) * 0.17)
		it.scale = Vector3.ONE * 1.25
		order_vis.add_child(it)
		it.remove_from_group("kr_items")
		it.set_process(false)


func _set_bubble() -> void:
	bubble.text = recipe
	bubble.font_size = 64
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
	# Looks: bounce, blink, colour of the patience bar, mood.
	var hop := absf(sin(bob_t)) * (0.35 if state == "happy" else 0.04)
	body.position.y = 1.15 + hop
	var shake := sin(bob_t * 7.0) * 0.06 if (state == "angry" or (state == "wait" and frac < 0.25)) else 0.0
	body.position.z = shake
	body.rotation.x = sin(bob_t * 0.7) * 0.05
	blink_t -= delta
	if blink_t < -0.12:
		blink_t = randf_range(1.5, 4.0)
	for e in eyes:
		e.scale = Vector3(1.0, 0.15 if blink_t < 0.0 else 1.0, 1.0)
	if spinner:
		spinner.rotation.y += delta * (14.0 if state == "happy" else 5.0)
	if blinker:
		blinker.visible = int(bob_t * 1.5) % 2 == 0
	if order_vis:
		order_vis.rotation.x = sin(bob_t * 0.5) * 0.1
		order_vis.visible = waiting() and hello_t <= 0.0
	bar_fill.scale.z = maxf(frac, 0.001)
	bar_fill.position.z = -0.44 * (1.0 - frac)
	var bar_col := Color(1.0, 0.25, 0.2).lerp(Color(0.3, 1.0, 0.4), clampf(frac * 1.6 - 0.2, 0.0, 1.0))
	bar_mat.albedo_color = bar_col
	bar_mat.emission = bar_col
	bar_fill.visible = waiting()
	# Says hello first, then shows the order.
	if hello_t > 0.0:
		hello_t -= delta
		if hello_t <= 0.0 and waiting():
			_set_bubble()
	if state == "wait" and shown_state == "walk_in":
		var hello: Array = info()[4]
		bubble.text = hello[randi() % hello.size()]
		bubble.font_size = 44
		bubble.modulate = Color(0.85, 0.95, 1.0)
		hello_t = 2.2
		if main and not ghost:
			main.sfx_local("pickup", -10.0, float(info()[3]))
	if cloud:
		cloud.position.y = 2.6 + sin(bob_t * 2.0) * 0.05
	if state != shown_state:
		shown_state = state
		match state:
			"happy":
				var lines: Array = info()[5]
				bubble.text = lines[randi() % lines.size()]
				bubble.font_size = 56
				bubble.modulate = Color(1.0, 0.95, 0.4)
				mouth.scale = Vector3(1.0, 2.0, 1.4)
			"angry":
				bubble.text = "HMPH!"
				bubble.modulate = Color(1.0, 0.4, 0.3)
				body_mat.albedo_color = Color(0.95, 0.3, 0.25)
				mouth.scale = Vector3(1.0, 0.6, 0.6)
				_storm_cloud()
			"walk_in":
				pass
			_:
				if hello_t <= 0.0:
					_set_bubble()


## A grumpy little rain cloud over an angry customer.
func _storm_cloud() -> void:
	cloud = Node3D.new()
	add_child(cloud)
	for p in [Vector3(0, 0, -0.18), Vector3(0, 0.08, 0.05), Vector3(0, 0, 0.25)]:
		var puff := _part(_sph(0.2), Color(0.35, 0.35, 0.42), p, cloud)
		puff.scale = Vector3(1.0, 0.7, 1.0)


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
			if state_t > 1.6:
				var away := Vector3(10.5, 0.0, global_position.z + (3.0 if slot >= 2 else -3.0))
				global_position = global_position.move_toward(away, delta * 3.0)
				if global_position.distance_to(away) < 0.1:
					queue_free()


## Host: the order was delivered.
func serve() -> void:
	state = "happy"
	state_t = 0.0


const STATES := ["walk_in", "wait", "happy", "angry"]


## Snapshot entry, packed as floats: [id, recipe, x, y, z, patience fraction, state, colour, slot, type]
func net_state() -> PackedFloat32Array:
	var p := global_position
	return PackedFloat32Array([net_id, ItemScript.RECIPE_NAMES.find(recipe), p.x, p.y, p.z, frac, STATES.find(state), color_index, slot, type_index(ctype)])


func apply_net(st: PackedFloat32Array) -> void:
	net_target = Vector3(st[2], st[3], st[4])
	frac = st[5]
	state = STATES[clampi(int(st[6]), 0, STATES.size() - 1)]
	slot = int(st[8])
