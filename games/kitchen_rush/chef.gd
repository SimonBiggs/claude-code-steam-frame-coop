extends Node3D
## Player 1: the CHEF behind the counter.
## VR: grab with either hand (grip or trigger), the right hand holds a knife: swing it down through an
##     ingredient to chop it. Drop ingredients onto a plate to build the dish. X / A recenters you at the counter.
## Buttons (no headset): move a hand cursor between the counter spots, grab/place, chop.
##     Keyboard: WASD move cursor, Space grab / place, Shift (or F) chop.  Controller: d-pad / stick, A grab, X / RT chop.
## On the TV machine the chef is a ghost drawn from the host's snapshots.

const L := preload("res://games/kitchen_rush/layout.gd")

var index := 0
var color := Color(1.0, 0.45, 0.35)
var main
var joy := -1
var vr := false
var ghost := false
var remote := false
var active := true
var yaw := 0.0

# VR
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var recentered := false
var ax_was := false
var grip_was := [false, false]
var held: Array = [null, null]  # [left, right]; the button chef uses the left slot
var last_mid := Vector3.ZERO
var wrist_label: Label3D

# Button chef
var camera: Camera3D
var hud
var cursor := 6
var cursor_t := 0.0
var keys_was := {}
var chop_anim := 0.0
var cam_x := 0.0

# Visuals: shown to the TV players (and the hands to the chef as well).
var head_t := Transform3D()
var body_root: Node3D
var head_vis: Node3D
var lhand_vis: Node3D
var rhand_vis: Node3D
var knife: Node3D
var cursor_vis: Node3D
var cursor_ring: MeshInstance3D

# Ghost
var net_head := Transform3D()
var net_l := Transform3D()
var net_r := Transform3D()
var net_vr := false
var net_cursor := 6
var net_knife := true
var net_started := false


func body_layer() -> int:
	return 2 << index


func viewmodel_layer() -> int:
	return 64 << index


func camera_cull_mask() -> int:
	return (1 | 2 | 4 | 8 | 16 | viewmodel_layer()) & ~body_layer()


func _ready() -> void:
	position = L.CHEF_POS
	head_t = Transform3D(Basis(Vector3.RIGHT, -0.5), L.CHEF_POS + Vector3.UP * L.CHEF_HEAD_HEIGHT)
	body_root = Node3D.new()
	body_root.top_level = true
	add_child(body_root)
	var coat := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.3
	cap.radial_segments = 16
	cap.rings = 4
	coat.mesh = cap
	coat.material_override = main.mat(Color(0.97, 0.97, 1.0))
	coat.position.y = 0.72
	body_root.add_child(coat)
	var scarf := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.27
	tm.rings = 14
	tm.ring_segments = 6
	scarf.mesh = tm
	scarf.material_override = main.mat(color)
	scarf.position.y = 1.3
	body_root.add_child(scarf)
	head_vis = Node3D.new()
	head_vis.top_level = true
	add_child(head_vis)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.2
	hm.height = 0.4
	hm.radial_segments = 14
	hm.rings = 7
	head.mesh = hm
	head.material_override = main.mat(Color(1.0, 0.82, 0.68))
	head_vis.add_child(head)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.035
		em.height = 0.07
		em.radial_segments = 8
		em.rings = 4
		eye.mesh = em
		eye.material_override = main.mat(Color(0.1, 0.1, 0.15))
		eye.position = Vector3(side * 0.075, 0.04, -0.18)
		head_vis.add_child(eye)
	var stache := MeshInstance3D.new()
	var sm := CapsuleMesh.new()
	sm.radius = 0.03
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 2
	stache.mesh = sm
	stache.material_override = main.mat(Color(0.35, 0.2, 0.1))
	stache.rotation.z = PI / 2.0
	stache.position = Vector3(0, -0.05, -0.19)
	head_vis.add_child(stache)
	main.add_chef_hat(head_vis, Vector3(0, 0.16, 0), 1.0)
	var tag := Label3D.new()
	tag.text = "CHEF"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = color
	tag.position.y = 0.75
	head_vis.add_child(tag)
	main.set_layers(body_root, body_layer())
	main.set_layers(head_vis, body_layer())
	lhand_vis = _make_hand()
	rhand_vis = _make_hand()
	knife = _make_knife()
	rhand_vis.add_child(knife)


func _make_hand() -> Node3D:
	var h := Node3D.new()
	h.top_level = true
	add_child(h)
	var mitt := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.045
	s.height = 0.08
	s.radial_segments = 12
	s.rings = 6
	mitt.mesh = s
	mitt.material_override = main.mat(Color(1.0, 0.82, 0.68))
	mitt.scale = Vector3(1.0, 0.8, 1.25)
	mitt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(mitt)
	var cuff := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.045
	c.bottom_radius = 0.05
	c.height = 0.05
	c.radial_segments = 12
	c.rings = 1
	cuff.mesh = c
	cuff.material_override = main.mat(Color.WHITE)
	cuff.rotation.x = PI / 2.0
	cuff.position.z = 0.06
	h.add_child(cuff)
	return h


func _make_knife() -> Node3D:
	var k := Node3D.new()
	var handle := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.026, 0.032, 0.11)
	handle.mesh = hb
	handle.material_override = main.mat(Color(0.75, 0.35, 0.2))
	handle.position = Vector3(0, 0, -0.01)
	k.add_child(handle)
	var blade := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.007, 0.05, 0.22)
	blade.mesh = bb
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.85, 0.9, 0.95)
	steel.metallic = 0.9
	steel.roughness = 0.2
	blade.material_override = steel
	blade.position = Vector3(0, -0.012, -0.175)
	k.add_child(blade)
	for m in [handle, blade]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return k


## VR: the headset is the camera, the controllers are the hands.
func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	cam.cull_mask = camera_cull_mask()
	cam.near = 0.03
	wrist_label = Label3D.new()
	wrist_label.pixel_size = 0.0005
	wrist_label.font_size = 48
	wrist_label.outline_size = 26
	wrist_label.outline_modulate = Color.BLACK
	wrist_label.modulate = Color(1.0, 0.95, 0.7)
	wrist_label.position = Vector3(0.0, 0.07, 0.1)
	wrist_label.rotation_degrees = Vector3(-55, 0, 0)
	wrist_label.no_depth_test = true
	hand_l.add_child(wrist_label)
	main.set_layers(wrist_label, viewmodel_layer())


## Button chef: a fixed camera looking down at the counter.
func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 72.0
	camera.near = 0.05
	_update_camera(1.0)
	_build_cursor()


func _build_cursor() -> void:
	cursor_vis = Node3D.new()
	cursor_vis.top_level = true
	add_child(cursor_vis)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.0
	cm.height = 0.1
	cm.radial_segments = 10
	cm.rings = 1
	cone.mesh = cm
	cone.material_override = main.mat(Color(1.0, 0.85, 0.2), 1.5)
	cursor_vis.add_child(cone)
	cursor_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.14
	tm.outer_radius = 0.16
	tm.rings = 16
	tm.ring_segments = 6
	cursor_ring.mesh = tm
	cursor_ring.material_override = main.mat(Color(1.0, 0.85, 0.2), 1.5)
	cursor_ring.top_level = true
	add_child(cursor_ring)


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
		return
	if vr:
		_vr_update(delta)
	else:
		_button_update(delta)
	_place_body()


func _place_body() -> void:
	head_vis.global_transform = head_t
	var fwd := -head_t.basis.z
	body_root.global_position = Vector3(head_t.origin.x, 0.0, head_t.origin.z + 0.05)
	body_root.rotation.y = atan2(-fwd.x, -fwd.z)
	if cursor_vis and not vr:
		var sp := L.spot_pos(cursor)
		cursor_vis.global_position = sp + Vector3.UP * (0.42 + absf(sin(Time.get_ticks_msec() * 0.006)) * 0.05)
		cursor_ring.global_position = sp + Vector3.UP * 0.01


# --- VR ------------------------------------------------------------------------

func _vr_update(delta: float) -> void:
	var tracked := xr_camera.position != Vector3.ZERO
	var ax: bool = hand_l.is_button_pressed("ax_button") or hand_r.is_button_pressed("ax_button")
	if (tracked and not recentered) or (ax and not ax_was):
		recenter()
	ax_was = ax
	head_t = xr_camera.global_transform
	lhand_vis.global_transform = hand_l.global_transform
	rhand_vis.global_transform = hand_r.global_transform
	var hands: Array = [hand_l, hand_r]
	for h in 2:
		var hand: XRController3D = hands[h]
		var grip: bool = hand.get_float("grip") > 0.55 or hand.get_float("trigger") > 0.55
		var point := hand_point(h)
		if grip and not grip_was[h] and held[h] == null:
			var it = main.chef_pick_target(point, 0.14)
			if it != null:
				held[h] = it
				main.chef_grab(it)
				hand.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.04, 0.0)
		elif not grip and held[h] != null:
			var it2 = held[h]
			held[h] = null
			if is_instance_valid(it2):
				main.chef_release(it2, it2.global_position, false)
		grip_was[h] = grip
		if held[h] != null:
			if not is_instance_valid(held[h]) or held[h].holder != 0:
				held[h] = null
			else:
				held[h].global_position = point + Vector3.DOWN * 0.04
				held[h].rotation.y = hand.global_rotation.y
	# Highlight what a free hand would grab.
	for it in get_tree().get_nodes_in_group("kr_items"):
		it.highlight = false
	for h in 2:
		if held[h] == null:
			var near = main.chef_pick_target(hand_point(h), 0.14)
			if near != null:
				near.highlight = true
	knife.visible = held[1] == null
	_vr_chop(delta)
	wrist_label.text = main.status_text() + "\nX: recenter at the counter"


func hand_point(h: int) -> Vector3:
	var hand: XRController3D = hand_l if h == 0 else hand_r
	return hand.global_transform * Vector3(0.0, -0.02, -0.06)


## Swing the knife down through an ingredient on the counter to chop it.
func _vr_chop(delta: float) -> void:
	var a := hand_r.global_transform * Vector3(0, -0.012, -0.07)
	var b := hand_r.global_transform * Vector3(0, -0.012, -0.29)
	var mid := (a + b) * 0.5
	var vel := (mid - last_mid) / maxf(delta, 0.001)
	last_mid = mid
	if held[1] != null or vel.y > -0.6:
		return
	for it in get_tree().get_nodes_in_group("kr_items"):
		if it.holder != -1 or not it.needs_chop() or it.chop_cd > 0.0:
			continue
		var c: Vector3 = it.global_position + Vector3.UP * 0.05
		var cp := Geometry3D.get_closest_point_to_segment(c, a, b)
		if cp.distance_to(c) < 0.09:
			if main.chop(it):
				hand_r.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.09, 0.0)
			else:
				hand_r.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.05, 0.0)


## Put the player's head at the chef spot at a comfortable standing height, facing the counter.
## Works for seated players too (the kitchen is raised to meet them).
func recenter() -> void:
	recentered = true
	var head := xr_camera.global_transform
	var f := -head.basis.z
	var head_yaw := atan2(-f.x, -f.z)
	var rot := Basis(Vector3.UP, -head_yaw)
	xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head.origin + rot * (xr_origin.global_position - head.origin))
	var h := xr_camera.global_position
	xr_origin.global_position += Vector3(L.CHEF_POS.x - h.x, L.CHEF_HEAD_HEIGHT - h.y, L.CHEF_POS.z - h.z)
	main.sound("pickup", -8.0, 0.8)


# --- Button chef -----------------------------------------------------------------

func _button_update(delta: float) -> void:
	chop_anim = maxf(0.0, chop_anim - delta * 6.0)
	if not main.input_blocked():
		_read_buttons(delta)
	var sp := L.spot_pos(cursor)
	var look := (sp - (L.CHEF_POS + Vector3.UP * L.CHEF_HEAD_HEIGHT))
	var head_pos := L.CHEF_POS + Vector3.UP * L.CHEF_HEAD_HEIGHT + Vector3(sp.x * 0.3, 0, 0)
	head_t = Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), head_pos)
	var lpos := sp + Vector3(-0.09, 0.22, 0.06)
	lhand_vis.global_transform = Transform3D(Basis(Vector3.RIGHT, -0.4), lpos)
	var down := sin(chop_anim * PI)
	var rpos := sp + Vector3(0.12, 0.26 - down * 0.24, 0.12)
	rhand_vis.global_transform = Transform3D(Basis(Vector3.UP, 0.35) * Basis(Vector3.RIGHT, -0.15 - down * 0.4), rpos)
	knife.visible = true
	if held[0] != null:
		if not is_instance_valid(held[0]) or held[0].holder != 0:
			held[0] = null
		else:
			held[0].global_position = lpos + Vector3(0.0, -0.06, -0.04)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var sp := L.spot_pos(cursor)
	cam_x = lerpf(cam_x, sp.x * 0.45, 1.0 - exp(-6.0 * delta))
	camera.global_position = Vector3(cam_x, 2.05, 1.6)
	camera.look_at(Vector3(cam_x * 0.8, 0.95, -0.15), Vector3.UP)


func _pressed(id: String, down: bool) -> bool:
	var was: bool = keys_was.get(id, false)
	keys_was[id] = down
	return down and not was


func _read_buttons(delta: float) -> void:
	var left := Input.is_physical_key_pressed(KEY_A)
	var right := Input.is_physical_key_pressed(KEY_D)
	var up := Input.is_physical_key_pressed(KEY_W)
	var dn := Input.is_physical_key_pressed(KEY_S)
	var grab := Input.is_physical_key_pressed(KEY_SPACE)
	var chop_key := Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_F)
	var stick := Vector2.ZERO
	if joy >= 0:
		stick = Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		left = left or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT) or stick.x < -0.6
		right = right or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT) or stick.x > 0.6
		up = up or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP) or stick.y < -0.6
		dn = dn or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN) or stick.y > 0.6
		grab = grab or Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
		chop_key = chop_key or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	# Cursor moves on press, and repeats while held.
	cursor_t -= delta
	var dir := Vector2i(int(right) - int(left), int(dn) - int(up))
	var moved_now := _pressed("move", dir != Vector2i.ZERO)
	if dir != Vector2i.ZERO and (moved_now or cursor_t <= 0.0):
		cursor_t = 0.28 if moved_now else 0.16
		move_cursor(dir)
	if _pressed("grab", grab):
		do_grab()
	if _pressed("chop", chop_key):
		do_chop()


func move_cursor(dir: Vector2i) -> void:
	var col := cursor % 4
	var row := cursor / 4
	col = clampi(col + dir.x, 0, 3)
	row = clampi(row + dir.y, 0, 1)
	cursor = row * 4 + col
	main.sfx_local("zap", -18.0, 1.6)


## Grab what's under the cursor, or put down what we're holding there.
func do_grab() -> void:
	var sp := L.spot_pos(cursor)
	if held[0] == null:
		var it = main.chef_pick_target(sp, 0.2)
		if it != null:
			held[0] = it
			main.chef_grab(it)
		else:
			main.sfx_local("hit", -14.0, 0.6)
	else:
		var it2 = held[0]
		if main.chef_release(it2, sp, true):
			held[0] = null


func do_chop() -> void:
	chop_anim = 1.0
	var sp := L.spot_pos(cursor)
	var best = null
	var best_d := 0.2
	for it in get_tree().get_nodes_in_group("kr_items"):
		if it.holder != -1 or not it.needs_chop():
			continue
		var d: float = Vector2(it.global_position.x - sp.x, it.global_position.z - sp.z).length()
		if d < best_d:
			best_d = d
			best = it
	if best != null:
		main.chop(best)
	else:
		main.sfx_local("dash", -12.0, 1.5)


# --- Network ---------------------------------------------------------------------

## Snapshot entry, packed as floats: head, left hand, right hand (position + quaternion each), vr, cursor, knife.
func net_state() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for t in [head_t, lhand_vis.global_transform, rhand_vis.global_transform]:
		var q: Quaternion = t.basis.get_rotation_quaternion()
		a.append_array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w])
	a.append_array([1.0 if vr else 0.0, cursor, 1.0 if knife.visible else 0.0])
	return a


func _unpack(st: PackedFloat32Array, i: int) -> Transform3D:
	var q := Quaternion(st[i + 3], st[i + 4], st[i + 5], st[i + 6]).normalized()
	return Transform3D(Basis(q), Vector3(st[i], st[i + 1], st[i + 2]))


func apply_net_state(st: PackedFloat32Array) -> void:
	net_head = _unpack(st, 0)
	net_l = _unpack(st, 7)
	net_r = _unpack(st, 14)
	net_vr = st[21] > 0.5
	net_cursor = int(st[22])
	net_knife = st[23] > 0.5


func _ghost_update(delta: float) -> void:
	if net_head == Transform3D():
		return
	var k := 1.0 - exp(-20.0 * delta)
	if not net_started:
		net_started = true
		k = 1.0
	head_t = head_t.interpolate_with(net_head.orthonormalized(), k)
	lhand_vis.global_transform = lhand_vis.global_transform.interpolate_with(net_l.orthonormalized(), k)
	rhand_vis.global_transform = rhand_vis.global_transform.interpolate_with(net_r.orthonormalized(), k)
	knife.visible = net_knife
	if not net_vr:
		if cursor_vis == null:
			_build_cursor()
		cursor = net_cursor
	_place_body()
