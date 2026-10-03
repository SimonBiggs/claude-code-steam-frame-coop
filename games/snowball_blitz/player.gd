extends CharacterBody3D
## One co-op player in a cosy winter coat.
## TV / split screen (first person): hold throw to charge a lobbed snowball, release to throw; hold
## repair next to a damaged fort wall to pack it back up.
## VR (player 1 on the host): squeeze grip/trigger low down to scoop snow, keep squeezing to pack it
## harder, then throw for real and let go. The left hand holds a pan-lid shield.
## Controller: left stick move, right stick look, RT/RB throw, X/LB/LT repair.
## Keyboard P1: WASD + mouse, click / Space throw, E / right-click repair.
## Keyboard P2: arrows (turn), Enter throw, Ctrl repair.

const SPEED := 5.5
const MAX_HP := 100.0
const REVIVE_TIME := 2.5
const REVIVE_RANGE := 2.4
const EYE_HEIGHT := 1.5
const STICK_YAW_SPEED := 3.0
const STICK_PITCH_SPEED := 2.0
const KEY_TURN_SPEED := 2.4
const MOUSE_SENS := 0.0028
const CHARGE_TIME := 0.9
const THROW_COOLDOWN := 0.3
const REPAIR_RATE := 24.0
const PACK_TIME := 1.3
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "throw": KEY_SPACE, "repair": KEY_E},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "throw": KEY_ENTER, "repair": KEY_CTRL},
]

var index := 0
var joy := -1
var color := Color.WHITE
var main
var camera: Camera3D
var hud

var hp := MAX_HP
var is_down := false
var revive_progress := 0.0
var invuln_t := 0.0
var yaw := 0.0
var pitch := 0.0
var shake := 0.0
var bob_t := 0.0
var flash_t := 0.0
var hurt_sound_t := 0.0

# Throwing / repairing (TV players).
var charging := false
var charge_t := 0.0
var throw_cd := 0.0
var throw_anim := 0.0
var repair_seg := -1
var repairing := false
var repair_acc := 0.0
var repair_send := 0.0
var puff_t := 0.0
# Bot / test hooks (also handy for scripted demos).
var bot_throw := false
var bot_repair := false
var bot_move := Vector3.ZERO

# Visuals.
var pivot: Node3D
var head_parts: Node3D
var body_mat: StandardMaterial3D
var ice_block: MeshInstance3D
var revive_ring: MeshInstance3D
var revive_fill: MeshInstance3D
var tag: Label3D
var view_hand: Node3D  # first-person mitten + snowball
var view_ball: MeshInstance3D
var marker: MeshInstance3D  # predicted landing spot while charging

# VR.
var vr := false
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var wrist_label: Label3D
var snap_ready := true
var vr_velocity := Vector3.ZERO
var holding := false
var pack := 0.0
var squeeze_was := false
var hand_hist: Array = []  # [seconds, position] of the throwing hand
var pack_pulse := 0.0
var hint_t := 0.0
var lid: Node3D
var hand_ball: MeshInstance3D

# Networked co-op.
var remote := false
var ghost := false
var active := true
var key_set := -1  # -1: by index (P1 WASD, P2 arrows), -2: no keyboard (extra controller players)
var mouse_look := false
var net_target := Vector3.ZERO
var net_started := false
var net_head := Transform3D()
var net_hand := Transform3D()
var net_lhand := Transform3D()
var net_held := -1.0
var ghost_head: Node3D
var ghost_hand: Node3D


## Render layers: bit 0 world, bits 1-7 the bodies of players 0-6, bits 8-14 their first-person viewmodels.
func body_layer() -> int:
	return 2 << index


func viewmodel_layer() -> int:
	return 256 << index


func camera_cull_mask() -> int:
	return 1 | (0xFE & ~body_layer()) | viewmodel_layer()


func _ready() -> void:
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.5
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.75
	add_child(cs)
	yaw = rotation.y
	rotation.y = 0.0
	net_target = position

	pivot = Node3D.new()
	add_child(pivot)
	body_mat = main.make_material(color, 0.15)
	body_mat.roughness = 0.9
	var coat := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.36
	cap.height = 1.3
	cap.radial_segments = 14
	cap.rings = 4
	coat.mesh = cap
	coat.material_override = body_mat
	coat.position.y = 0.65
	pivot.add_child(coat)
	head_parts = Node3D.new()
	pivot.add_child(head_parts)
	_add_head(head_parts, Vector3(0, 1.45, 0))
	var scarf := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.28
	tm.rings = 12
	tm.ring_segments = 6
	scarf.mesh = tm
	scarf.material_override = main.mat("scarf%d" % ((index + 2) % 5))
	scarf.position.y = 1.25
	pivot.add_child(scarf)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.5
	rm.outer_radius = 0.6
	rm.rings = 20
	rm.ring_segments = 4
	ring.mesh = rm
	ring.material_override = main.make_material(color, 1.5)
	ring.position.y = 0.03
	pivot.add_child(ring)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = color
	tag.position.y = 2.2
	pivot.add_child(tag)
	_set_layers(pivot, body_layer())
	if ghost:
		head_parts.visible = false  # the VR player's real head is drawn from the snapshot

	# Frozen solid: a translucent ice block, with a thaw ring that fills while a friend is near.
	ice_block = MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(1.0, 1.8, 1.0)
	ice_block.mesh = ib
	ice_block.material_override = main.mat("ice")
	ice_block.position.y = 0.9
	ice_block.visible = false
	ice_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ice_block)
	revive_ring = MeshInstance3D.new()
	var rr := TorusMesh.new()
	rr.inner_radius = REVIVE_RANGE - 0.08
	rr.outer_radius = REVIVE_RANGE
	rr.rings = 32
	rr.ring_segments = 4
	revive_ring.mesh = rr
	revive_ring.material_override = main.make_material(Color(1.0, 0.7, 0.35), 1.5)
	revive_ring.position.y = 0.04
	revive_ring.visible = false
	add_child(revive_ring)
	revive_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = REVIVE_RANGE
	disc.bottom_radius = REVIVE_RANGE
	disc.height = 0.02
	disc.radial_segments = 24
	revive_fill.mesh = disc
	revive_fill.material_override = main.mat("thaw")
	revive_fill.position.y = 0.03
	revive_fill.visible = false
	add_child(revive_fill)


func _add_head(parent: Node3D, at: Vector3) -> void:
	var head := MeshInstance3D.new()
	head.mesh = main.sphere_mesh(0.2)
	head.material_override = main.mat("skin")
	head.position = at
	parent.add_child(head)
	var hat := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.21
	cone.height = 0.32
	cone.radial_segments = 10
	cone.rings = 1
	hat.mesh = cone
	hat.material_override = body_mat
	hat.position = at + Vector3(0, 0.2, 0.02)
	hat.rotation.x = 0.25
	parent.add_child(hat)
	var pom := MeshInstance3D.new()
	pom.mesh = main.sphere_mesh(0.07)
	pom.material_override = main.mat("snow")
	pom.position = at + Vector3(0, 0.38, 0.07)
	parent.add_child(pom)


## Split-screen / TV camera with a first-person mitten that holds the snowball.
func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 78.0
	camera.near = 0.05
	view_hand = Node3D.new()
	camera.add_child(view_hand)
	view_hand.position = Vector3(0.26, -0.24, -0.5)
	var mitten := MeshInstance3D.new()
	mitten.mesh = main.sphere_mesh(0.07)
	mitten.material_override = body_mat
	mitten.scale = Vector3(1.0, 0.8, 1.3)
	mitten.position = Vector3(0.02, -0.06, 0.04)
	view_hand.add_child(mitten)
	view_ball = MeshInstance3D.new()
	view_ball.mesh = main.sphere_mesh(0.08)
	view_ball.material_override = main.mat("snowball")
	view_hand.add_child(view_ball)
	_set_layers(view_hand, viewmodel_layer())
	marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.42
	tm.rings = 20
	tm.ring_segments = 4
	marker.mesh = tm
	marker.material_override = main.make_material(color.lightened(0.3), 2.5)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	main.add_child(marker)
	_set_layers(marker, viewmodel_layer())
	_update_camera(0.0)


## VR player: the headset is the camera, the right hand throws, the left hand holds a pan lid.
func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	camera = cam
	cam.cull_mask = camera_cull_mask()
	cam.near = 0.05
	var mitten := MeshInstance3D.new()
	mitten.mesh = main.sphere_mesh(0.05)
	mitten.material_override = body_mat
	mitten.scale = Vector3(1.0, 0.8, 1.4)
	hand_r.add_child(mitten)
	hand_ball = MeshInstance3D.new()
	hand_ball.mesh = main.sphere_mesh(1.0)
	hand_ball.material_override = main.mat("snowball")
	hand_ball.position = Vector3(0, 0.02, -0.08)
	hand_ball.visible = false
	hand_r.add_child(hand_ball)
	_set_layers(mitten, viewmodel_layer())
	_set_layers(hand_ball, viewmodel_layer())
	lid = _make_lid()
	hand_l.add_child(lid)
	lid.position = Vector3(0, 0, -0.08)
	_set_layers(lid, viewmodel_layer())
	wrist_label = Label3D.new()
	wrist_label.pixel_size = 0.0005
	wrist_label.font_size = 48
	wrist_label.outline_size = 14
	wrist_label.modulate = Color(1.0, 0.92, 0.75)
	wrist_label.position = Vector3(0.0, 0.1, 0.12)
	wrist_label.rotation_degrees = Vector3(-55, 0, 0)
	wrist_label.no_depth_test = true
	hand_l.add_child(wrist_label)
	_set_layers(wrist_label, viewmodel_layer())


## A shiny saucepan lid with a red knob: blocks the snowmen's icy snowballs.
func _make_lid() -> Node3D:
	var n := Node3D.new()
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.17
	cyl.bottom_radius = 0.24
	cyl.height = 0.05
	cyl.radial_segments = 20
	cyl.rings = 1
	disc.mesh = cyl
	disc.material_override = main.mat("lid")
	disc.rotation.x = PI / 2.0  # dome faces forward along the hand
	n.add_child(disc)
	var knob := MeshInstance3D.new()
	knob.mesh = main.sphere_mesh(0.035)
	knob.material_override = main.mat("hat_band")
	knob.position = Vector3(0, 0, -0.05)
	n.add_child(knob)
	for c in n.get_children():
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


func aim_dir() -> Vector3:
	if vr:
		return -hand_r.global_basis.z
	return -camera.global_basis.z if camera else Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0, 0, -1)


func head_pos() -> Vector3:
	if vr:
		return xr_camera.global_position
	if ghost and net_head != Transform3D():
		return net_head.origin
	return global_position + Vector3.UP * (EYE_HEIGHT if not is_down else 0.5)


## Where snowmen aim: the chest.
func aim_point() -> Vector3:
	var h := head_pos()
	return Vector3(h.x, maxf(0.6, h.y - 0.45), h.z)


## Does a snowball at p (radius r) hit this player's body (a capsule from the snow to the head)?
func hit_test(p: Vector3, r: float) -> bool:
	var top := head_pos()
	var bottom := Vector3(top.x, global_position.y + 0.2, top.z)
	var cp := Geometry3D.get_closest_point_to_segment(p, bottom, top)
	return cp.distance_to(p) < 0.38 + r


## Does the VR pan lid (real, or the ghost copy on the TV) catch a snowball at p?
func lid_blocks(p: Vector3, r: float) -> bool:
	if lid == null or not lid.is_inside_tree() or not lid.visible:
		return false
	return lid.global_position.distance_to(p) < 0.25 + r


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.3)


func _physics_process(delta: float) -> void:
	throw_cd -= delta
	invuln_t -= delta
	flash_t -= delta
	body_mat.emission_energy_multiplier = 2.5 if flash_t > 0.0 else 0.15
	if not active:
		return
	if ghost:
		_ghost_update(delta)
		return
	if remote:
		_remote_update(delta)
		return
	if vr:
		_vr_update(delta)
	else:
		_read_look(delta)
	if is_down:
		vr_velocity = Vector3.ZERO
		charging = false
		repairing = false
		_drop_held()
		if main.net.mode == "client":
			var fill := maxf(revive_progress, 0.01)
			revive_fill.scale = Vector3(fill, 1, fill)
		else:
			_update_revive(delta)
		_update_camera(delta)
		_update_viewmodel(delta)
		main.net.send_state(global_position, yaw, pitch, index)
		return

	var move := _read_move()
	velocity = move * SPEED * (0.55 if repairing else 1.0)
	if vr:
		vr_velocity = velocity
	else:
		move_and_slide()
		position.y = 0.0
		var flat := Vector2(position.x, position.z)
		var limit: float = main.arena_radius - 0.6
		if flat.length() > limit:
			flat = flat.normalized() * limit
			position.x = flat.x
			position.z = flat.y
	bob_t += velocity.length() * delta * 1.8
	_update_camera(delta)
	main.net.send_state(global_position, yaw, pitch, index)
	if vr:
		_vr_hands(delta)
	else:
		_update_throw(delta)
		_update_repair(delta)
	_update_viewmodel(delta)


func _update_camera(delta: float) -> void:
	pivot.rotation.y = yaw
	if camera == null or vr:
		return
	shake = maxf(0.0, shake - delta * 3.0)
	var eye := EYE_HEIGHT if not is_down else 0.6
	var bob := sin(bob_t) * 0.04 if not is_down else 0.0
	camera.global_position = global_position + Vector3(0, eye + bob, 0)
	camera.rotation = Vector3(pitch + randf_range(-1, 1) * shake * 0.02, yaw + randf_range(-1, 1) * shake * 0.02, 0.25 if is_down else 0.0)


# --- TV players: charge-and-lob, and packing walls ----------------------------

func charge() -> float:
	return clampf(charge_t / CHARGE_TIME, 0.0, 1.0) if charging else 0.0


func _throw_velocity(c: float) -> Vector3:
	return aim_dir() * (10.0 + 14.0 * c) + Vector3.UP * 1.5


func _throw_origin() -> Vector3:
	return camera.global_position + aim_dir() * 0.5 + camera.global_basis.x * 0.15 - camera.global_basis.y * 0.08


func _update_throw(delta: float) -> void:
	var held := _throw_held()
	if held and not charging and throw_cd <= 0.0:
		charging = true
		charge_t = 0.0
	if charging:
		charge_t += delta
		if not held:
			var c := charge()
			charging = false
			throw_cd = THROW_COOLDOWN
			throw_anim = 1.0
			main.player_throw(self, _throw_origin(), _throw_velocity(c), 0.11 + 0.05 * c, 1.0 + c)
			main.sound("dash", -6.0, 0.8 + c * 0.3)
	_update_marker()


## Shows where a snowball thrown now would land (only on this player's own screen).
func _update_marker() -> void:
	if marker == null:
		return
	marker.visible = charging
	if not charging:
		return
	var p := _throw_origin()
	var v := _throw_velocity(charge())
	var g: float = main.gravity
	for i in 120:
		v.y -= g * 0.025
		p += v * 0.025
		if p.y <= 0.05:
			break
	marker.global_position = Vector3(p.x, 0.06, p.z)
	var pulse := 1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.012)
	marker.scale = Vector3(pulse, 1.0, pulse) * (0.8 + charge() * 0.6)


func _update_repair(delta: float) -> void:
	repair_seg = main.repair_target(global_position)
	repairing = _repair_held() and repair_seg >= 0
	if not repairing:
		return
	var amount := REPAIR_RATE * delta
	puff_t -= delta
	if puff_t <= 0.0:
		puff_t = 0.18
		main.pack_puff(repair_seg, color)
	if joy >= 0 and puff_t > 0.16:
		Input.start_joy_vibration(joy, 0.15, 0.0, 0.05)
	if main.net.mode == "client":
		repair_acc += amount
		repair_send -= delta
		if repair_send <= 0.0:
			repair_send = 0.12
			main.net.send_action("repair", [repair_seg, repair_acc], index)
			repair_acc = 0.0
	else:
		main.repair_segment(repair_seg, amount, index)


func _update_viewmodel(delta: float) -> void:
	if view_hand == null:
		return
	throw_anim = maxf(0.0, throw_anim - delta * 5.0)
	view_hand.visible = not is_down
	var c := charge()
	view_ball.visible = throw_anim <= 0.3
	view_ball.scale = Vector3.ONE * (1.0 + c * 0.45)
	# Wind up while charging, snap forward on release, bob while packing walls.
	var wind := Vector3(0.04, -0.02, 0.18) * c
	var fling := Vector3(-0.08, 0.1, -0.25) * throw_anim
	var pack_bob := Vector3(0, -0.06 + 0.05 * sin(Time.get_ticks_msec() * 0.03), -0.05) if repairing else Vector3.ZERO
	view_hand.position = Vector3(0.26, -0.24 + absf(sin(bob_t * 0.5)) * 0.01, -0.5) + wind + fling + pack_bob


func _drop_held() -> void:
	if holding:
		holding = false
		pack = 0.0
		if hand_ball:
			hand_ball.visible = false
	if marker:
		marker.visible = false


# --- VR: scoop, pack and throw for real ----------------------------------------

func _squeeze(hand: XRController3D) -> float:
	return maxf(hand.get_float("trigger"), hand.get_float("grip"))


func _hand_low(hand: XRController3D) -> bool:
	var y := hand.global_position.y
	return y < xr_camera.global_position.y - 0.55 or y < xr_origin.global_position.y + 0.5


func _vr_hands(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	hand_hist.append([now, hand_r.global_position])
	while hand_hist.size() > 2 and now - float(hand_hist[0][0]) > 0.25:
		hand_hist.pop_front()
	var sq := _squeeze(hand_r)
	var down := sq > 0.55 or (squeeze_was and sq > 0.35)
	if not holding:
		if down and not squeeze_was:
			if _hand_low(hand_r):
				holding = true
				pack = 0.0
				hand_r.trigger_haptic_pulse("haptic", 0.0, 0.45, 0.08, 0.0)
				main.sound("spit", -8.0, 1.4)
				main.puff(hand_r.global_position, Color(1, 1, 1), 8, 0.05)
			else:
				hint_t = 2.5
	else:
		if down:
			pack = minf(1.0, pack + delta / PACK_TIME)
			pack_pulse -= delta
			if pack_pulse <= 0.0 and pack < 1.0:
				pack_pulse = 0.22
				hand_r.trigger_haptic_pulse("haptic", 0.0, 0.12 + pack * 0.25, 0.03, 0.0)
		else:
			_vr_throw(now)
	squeeze_was = down
	hint_t -= delta
	hand_ball.visible = holding
	var r := 0.07 + 0.06 * pack
	hand_ball.scale = Vector3.ONE * r


func _vr_throw(now: float) -> void:
	holding = false
	var p_now := hand_r.global_position
	var v := Vector3.ZERO
	# Hand velocity over the last ~0.08 s.
	for i in range(hand_hist.size() - 1, -1, -1):
		var age := now - float(hand_hist[i][0])
		if age >= 0.08 or i == 0:
			if age > 0.01:
				v = (p_now - (hand_hist[i][1] as Vector3)) / age
			break
	v = (v * 1.6).limit_length(34.0)
	if v.length() > 4.0:
		v = main.assist_aim(p_now, v)
	var r := 0.09 + 0.07 * pack
	main.player_throw(self, p_now + v.normalized() * 0.12, v, r, 1.5 + 2.5 * pack)
	hand_r.trigger_haptic_pulse("haptic", 0.0, 0.7, 0.06, 0.0)
	main.sound("dash", -4.0, 0.7 + v.length() * 0.015)
	pack = 0.0


## The host says one of our snowballs landed a hit.
func on_ball_hit() -> void:
	if vr:
		hand_r.trigger_haptic_pulse("haptic", 0.0, 0.9, 0.1, 0.0)
	elif hud:
		hud.hit_marker()
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.2, 0.0, 0.06)


## The pan lid blocked a snowball.
func on_block() -> void:
	if vr:
		hand_l.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.12, 0.0)


# --- Input -------------------------------------------------------------------

func keys() -> int:
	if key_set == -2:
		return -1
	return key_set if key_set >= 0 else mini(index, KEYS.size() - 1)


func _key(action: String) -> bool:
	var k := keys()
	if k < 0:
		return false
	return Input.is_physical_key_pressed(KEYS[k][action])


## Has a keyboard (and maybe the mouse) of its own, so it never "leaves" when its controller unplugs.
func has_keyboard() -> bool:
	return keys() >= 0 or mouse_look


func _stick(axis_x: JoyAxis, axis_y: JoyAxis, deadzone: float) -> Vector2:
	if joy < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(joy, axis_x), Input.get_joy_axis(joy, axis_y))
	var l := v.length()
	if l < deadzone:
		return Vector2.ZERO
	return v / l * ((minf(l, 1.0) - deadzone) / (1.0 - deadzone))


func _read_look(delta: float) -> void:
	var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15)
	look = look * look.length()
	yaw -= look.x * STICK_YAW_SPEED * delta
	pitch = clampf(pitch - look.y * STICK_PITCH_SPEED * delta, -1.3, 1.3)
	if keys() == 1:
		yaw -= (float(_key("right")) - float(_key("left"))) * KEY_TURN_SPEED * delta


func _read_move() -> Vector3:
	if bot_move != Vector3.ZERO:
		return bot_move.limit_length(1.0)
	if vr:
		var s := hand_l.get_vector2("primary")
		if s.length() < 0.15:
			return Vector3.ZERO
		return Basis(Vector3.UP, yaw) * Vector3(s.x, 0.0, -s.y).limit_length(1.0)
	var v := Vector2.ZERO
	if keys() == 0:
		v = Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	else:
		v.y = float(_key("down")) - float(_key("up"))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)))
	return Basis(Vector3.UP, yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)


func _throw_held() -> bool:
	if bot_throw:
		return true
	if vr:
		return _squeeze(hand_r) > 0.5
	if _key("throw"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		return Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	return false


func _repair_held() -> bool:
	if bot_repair:
		return true
	if _key("repair"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	if joy >= 0:
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_X) or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT) > 0.4
	return false


## VR: right trigger (used to restart after game over).
func vr_trigger_held() -> bool:
	return vr and _squeeze(hand_r) > 0.5


func _process(delta: float) -> void:
	if not vr or xr_origin == null or vr_velocity == Vector3.ZERO:
		return
	xr_origin.global_position += vr_velocity * delta
	global_position += vr_velocity * delta


## Headset drives facing and body position; right stick snap-turns; the wrist shows status.
func _vr_update(_delta: float) -> void:
	yaw = xr_camera.global_rotation.y
	# Left stick walks around inside the fort (smooth, head-relative).
	var mv := hand_l.get_vector2("primary")
	if mv.length() > 0.2:
		var b := Basis(Vector3.UP, xr_camera.global_rotation.y)
		xr_origin.global_position += b * Vector3(mv.x, 0.0, -mv.y) * 2.2 * _delta
	var head := xr_camera.global_position
	var target := Vector3(head.x, 0.0, head.z)
	var flat := Vector2(target.x, target.z)
	var limit: float = main.arena_radius - 0.6  # the kids wanted to go out past the walls too
	if flat.length() > limit:
		var fix := flat.normalized() * limit - flat
		xr_origin.global_position += Vector3(fix.x, 0.0, fix.y)
		target += Vector3(fix.x, 0.0, fix.y)
	global_position = target
	var turn := hand_r.get_vector2("primary").x
	if absf(turn) > 0.7 and snap_ready:
		snap_ready = false
		var rot := Basis(Vector3.UP, -signf(turn) * deg_to_rad(30.0))
		var pivot_pt := xr_camera.global_position
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, pivot_pt + rot * (xr_origin.global_position - pivot_pt))
	elif absf(turn) < 0.3:
		snap_ready = true
	var status := ""
	if is_down:
		status = "FROZEN! A friend can thaw you"
	elif hint_t > 0.0:
		status = "Reach DOWN to the snow to scoop!"
	elif holding:
		status = "Packing… %d%%  - throw and let go!" % int(pack * 100.0)
	if main.net.mode == "host" and not main.net.connected:
		status = "Waiting for the TV players…"
	var boss: String = main.boss_text()
	wrist_label.text = "WAVE %d   SCORE %d\nWARMTH %d   FORT %d%%\n%s%s" % [main.wave, main.score, maxi(0, int(hp)), int(main.fort_fraction() * 100.0), boss + "\n" if boss != "" else "", status]


# --- Warmth, freezing and thawing --------------------------------------------

func take_damage(amount: float, from_pos = null) -> void:
	if is_down or invuln_t > 0.0 or not active:
		return
	if remote:
		main.net.event("hurt", [index, from_pos if from_pos != null else global_position])
	if hud and from_pos != null:
		hud.damage_from(from_pos)
	hp -= amount
	flash_t = 0.08
	main.stat_add(index, "hits_taken", 1)
	if amount > 3.0:
		shake = maxf(shake, 0.3)
		if hud:
			hud.hurt()
	hurt_sound_t -= get_physics_process_delta_time()
	if hurt_sound_t <= 0.0:
		hurt_sound_t = 0.25
		main.sound("hurt", -6.0, 1.2 + index * 0.15)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.3, 0.5, 0.1)
	if vr:
		hand_l.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.1, 0.0)
		hand_r.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.1, 0.0)
		main.vr_hurt_flash()
	if hp <= 0.0:
		_go_down()


func heal(amount: float) -> void:
	if not is_down:
		hp = minf(MAX_HP, hp + amount)


func _go_down() -> void:
	hp = 0.0
	is_down = true
	revive_progress = 0.0
	_apply_down_pose(true)
	main.burst(global_position + Vector3.UP, Color(0.7, 0.9, 1.0), 24, 0.12)
	shake = 1.0
	main.sound("down", -2.0, 1.3)
	main.on_player_frozen(self)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.8, 1.0, 0.4)


func _update_revive(delta: float) -> void:
	var helper_near := false
	for p in main.players:
		if p != self and p.active and not p.is_down and p.global_position.distance_to(global_position) <= REVIVE_RANGE:
			helper_near = true
	if helper_near:
		revive_progress += delta / REVIVE_TIME
	else:
		revive_progress = maxf(0.0, revive_progress - delta * 0.25)
	var s := maxf(revive_progress, 0.01)
	revive_fill.scale = Vector3(s, 1, s)
	if revive_progress >= 1.0:
		revive(0.6)
		main.popup(global_position + Vector3.UP * 2.0, "THAWED!", Color(1.0, 0.75, 0.4))


func revive(fraction: float) -> void:
	is_down = false
	hp = MAX_HP * fraction
	invuln_t = 2.0
	_apply_down_pose(false)
	main.burst(global_position + Vector3.UP, Color(1.0, 0.75, 0.4), 24, 0.12)
	main.sound("revive")


func _apply_down_pose(down: bool) -> void:
	ice_block.visible = down
	revive_ring.visible = down
	revive_fill.visible = down
	pivot.position.y = 0.0
	if down:
		revive_fill.scale = Vector3(0.01, 1, 0.01)


# --- Networked co-op ---------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if camera:
		return camera.global_transform
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), global_position + Vector3.UP * EYE_HEIGHT)


func hand_transform() -> Transform3D:
	return hand_r.global_transform if vr else Transform3D()


func left_hand_transform() -> Transform3D:
	return hand_l.global_transform if vr else Transform3D()


func held_amount() -> float:
	if vr:
		return pack if holding else -1.0
	return charge() if charging else -1.0


func set_active(on: bool) -> void:
	active = on
	visible = on
	collision_layer = 2 if on else 0
	if marker and not on:
		marker.visible = false


## Host: latest position and view of a TV player.
func apply_remote_state(pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	net_target = Vector3(pos.x, 0.0, pos.z)
	yaw = new_yaw
	pitch = new_pitch
	if not net_started:
		net_started = true
		global_position = net_target


## Client: authoritative state from the host.
## [pos, yaw, pitch, hp, is_down, revive_progress, active, held, (player 1 only:) head, rhand, lhand]
func apply_net_state(st: Array) -> void:
	hp = st[3]
	revive_progress = st[5]
	var on: bool = st[6]
	if on != active:
		set_active(on)
		main.on_player_activity_changed(self)
	if ghost:
		net_target = st[0]
		yaw = st[1]
		pitch = st[2]
		net_held = st[7]
		if st.size() > 10:
			net_head = st[8]
			net_hand = st[9]
			net_lhand = st[10]
		if not net_started:
			net_started = true
			global_position = net_target
	var down: bool = st[4]
	if down != is_down:
		is_down = down
		_apply_down_pose(down)
		if down:
			shake = 1.0
		else:
			invuln_t = 2.0


## Client: the host says this local player got hit.
func on_remote_hurt(from_pos: Vector3) -> void:
	flash_t = 0.08
	shake = maxf(shake, 0.3)
	if hud:
		hud.hurt()
		hud.damage_from(from_pos)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.3, 0.5, 0.1)


## Client: the VR player, drawn from snapshots (head, throwing mitten with snowball, pan lid).
func _ghost_update(delta: float) -> void:
	global_position = global_position.lerp(net_target, 1.0 - exp(-15.0 * delta))
	pivot.rotation.y = yaw
	if ghost_head == null:
		ghost_head = Node3D.new()
		add_child(ghost_head)
		_add_head(ghost_head, Vector3.ZERO)
		_set_layers(ghost_head, body_layer())
		ghost_hand = Node3D.new()
		add_child(ghost_hand)
		var mitten := MeshInstance3D.new()
		mitten.mesh = main.sphere_mesh(0.06)
		mitten.material_override = body_mat
		ghost_hand.add_child(mitten)
		hand_ball = MeshInstance3D.new()
		hand_ball.mesh = main.sphere_mesh(1.0)
		hand_ball.material_override = main.mat("snowball")
		hand_ball.position = Vector3(0, 0.02, -0.08)
		ghost_hand.add_child(hand_ball)
		_set_layers(ghost_hand, body_layer())
		lid = _make_lid()
		add_child(lid)
		_set_layers(lid, body_layer())
	if net_head != Transform3D():
		ghost_head.global_transform = ghost_head.global_transform.interpolate_with(net_head.orthonormalized(), 1.0 - exp(-20.0 * delta))
		ghost_head.visible = not is_down
	ghost_hand.visible = net_hand != Transform3D() and not is_down
	if ghost_hand.visible:
		ghost_hand.global_transform = ghost_hand.global_transform.interpolate_with(net_hand.orthonormalized(), 1.0 - exp(-25.0 * delta))
	hand_ball.visible = net_held >= 0.0
	hand_ball.scale = Vector3.ONE * (0.07 + 0.06 * maxf(net_held, 0.0))
	lid.visible = net_lhand != Transform3D() and not is_down
	if lid.visible:
		lid.global_transform = net_lhand.orthonormalized() * Transform3D(Basis(), Vector3(0, 0, -0.08))
	if is_down:
		var fill := maxf(revive_progress, 0.01)
		revive_fill.scale = Vector3(fill, 1, fill)


func _remote_update(delta: float) -> void:
	global_position = net_target
	pivot.rotation.y = yaw
	if is_down:
		_update_revive(delta)
