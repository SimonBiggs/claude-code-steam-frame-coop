extends Node3D
## A tiny knight on the tabletop (TV players 2 to 7), seen in third person.
## Controller: left stick move, right stick turn the camera, RT/RB/B sword, LT/LB/X crossbow, A jump.
## Keyboard set 0: W/S move, A/D turn, Space sword, F crossbow, Shift jump.
## Keyboard set 1: arrows (left/right turn), Enter sword, Right Ctrl / . crossbow, / jump.
## Players 4-7 have no keyboard set (key_set = -1): one controller each, picked by device id.
## Their own movement is local (instant); the host decides hits, damage, embers and reviving.

const W := preload("res://games/giants_table/world.gd")
const BoltScript := preload("res://games/giants_table/bolt.gd")

const SPEED := 4.6
const WATER_SLOW := 0.4
const JUMP_V := 9.5
const KNIGHT_GRAVITY := 30.0
const STEP_UP := 0.8
const CLIMB := 1.3  # knights can scramble up onto a boulder (stepping stones in the river)
const BODY_R := 0.3
const SWORD_CD := 0.42
const BOW_CD := 0.55
const MAX_HP := 100.0
const REVIVE_TIME := 2.5
const REVIVE_RANGE := 1.8
const CAM_DIST := 3.6
const CAM_HEIGHT := 1.9
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "sword": KEY_SPACE, "bow": KEY_F, "bow2": KEY_E, "jump": KEY_SHIFT},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "sword": KEY_ENTER, "bow": KEY_CTRL, "bow2": KEY_PERIOD, "jump": KEY_SLASH},
]

var main
var index := 1
var color := Color.WHITE
var joy := -1
var key_set := 0
var remote := false   # host: driven by the TV machine
var active := true    # players 3+ sleep until they press attack / A
var claimed := false  # a controller or keyboard set belongs to this knight (they can press to join)
var vr := false
var ghost := false

var hp := MAX_HP
var is_down := false
var revive_progress := 0.0
var carrying := false   # holding an ember
var carried := false    # in the giant's hand, or falling after being let go
var held := false       # host: in the giant's hand right now
var fall_vel := Vector3.ZERO
var face := 0.0         # body facing (yaw)
var cam_yaw := 0.0
var vy := 0.0
var on_ground := true
var jump_was_held := false
var sword_cd := 0.0
var bow_cd := 0.0
var swing_t := 0.0
var flash_t := 0.0
var bob_t := 0.0
var net_target := Vector3.ZERO
var net_started := false
var bot_input := {}  # tests: {"move": Vector3, "sword": bool, "bow": bool, "jump": bool}
var radius := 0.35
var center_h := 0.5

var camera: Camera3D
var hud_label: Label
var hint_label: Label
var pivot: Node3D
var body_mat: StandardMaterial3D
var sword_pivot: Node3D
var ember_orb: MeshInstance3D
var revive_ring: MeshInstance3D
var tag: Label3D


func _ready() -> void:
	add_to_group("knights")
	net_target = global_position
	pivot = Node3D.new()
	add_child(pivot)
	body_mat = W.mat(color, 0.0, 0.6)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 0.7
	cap.radial_segments = 10
	cap.rings = 3
	body.mesh = cap
	body.material_override = body_mat
	body.position.y = 0.35
	pivot.add_child(body)
	var steel := W.mat(Color(0.82, 0.84, 0.9), 0.0, 0.3)
	steel.metallic = 0.7
	var head := MeshInstance3D.new()
	head.mesh = W.sphere(0.17, 10)
	head.material_override = W.mat(Color(1.0, 0.8, 0.65))
	head.position.y = 0.8
	pivot.add_child(head)
	var helm := MeshInstance3D.new()
	helm.mesh = W.sphere(0.19, 10)
	helm.material_override = steel
	helm.position.y = 0.86
	helm.scale = Vector3(1.0, 0.8, 1.0)
	pivot.add_child(helm)
	var plume := MeshInstance3D.new()
	plume.mesh = W.cyl(0.03, 0.07, 0.3, 6)
	plume.material_override = W.mat(color.lightened(0.2), 0.6)
	plume.position = Vector3(0, 1.08, 0.05)
	plume.rotation.x = 0.4
	pivot.add_child(plume)
	var shield := MeshInstance3D.new()
	shield.mesh = W.cyl(0.2, 0.2, 0.05, 12)
	shield.material_override = W.mat(color.darkened(0.2))
	shield.rotation = Vector3(PI / 2.0, 0.0, 0.3)
	shield.position = Vector3(-0.26, 0.42, -0.05)
	pivot.add_child(shield)
	var crest := MeshInstance3D.new()
	crest.mesh = W.sphere(0.07, 6)
	crest.material_override = W.mat(Color(1.0, 0.85, 0.3), 1.0)
	crest.position = Vector3(-0.29, 0.42, -0.12)
	pivot.add_child(crest)
	sword_pivot = Node3D.new()
	sword_pivot.position = Vector3(0.26, 0.42, -0.05)
	pivot.add_child(sword_pivot)
	var blade := MeshInstance3D.new()
	blade.mesh = W.box(Vector3(0.06, 0.03, 0.62))
	blade.material_override = steel
	blade.position = Vector3(0, 0, -0.38)
	sword_pivot.add_child(blade)
	var guard := MeshInstance3D.new()
	guard.mesh = W.box(Vector3(0.2, 0.05, 0.05))
	guard.material_override = W.mat(Color(1.0, 0.8, 0.3), 0.5)
	guard.position = Vector3(0, 0, -0.06)
	sword_pivot.add_child(guard)
	sword_pivot.rotation = Vector3(0.5, 0.0, 0.0)
	ember_orb = MeshInstance3D.new()
	ember_orb.mesh = W.sphere(0.17, 8)
	ember_orb.material_override = W.mat(Color(1.0, 0.55, 0.15), 4.0)
	ember_orb.position.y = 1.4
	ember_orb.visible = false
	ember_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(ember_orb)
	revive_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = REVIVE_RANGE - 0.08
	tm.outer_radius = REVIVE_RANGE
	tm.rings = 24
	tm.ring_segments = 6
	revive_ring.mesh = tm
	revive_ring.material_override = W.mat(color, 1.5)
	revive_ring.position.y = 0.05
	revive_ring.visible = false
	add_child(revive_ring)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 30
	tag.outline_size = 10
	tag.modulate = color
	tag.position.y = 1.7
	add_child(tag)


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 600.0
	cam_yaw = face
	_update_camera(1.0)


func set_active(on: bool) -> void:
	active = on
	visible = on


# --- Input -------------------------------------------------------------------

func _key(action: String) -> bool:
	if key_set < 0 or key_set >= KEYS.size():
		return false
	var keys: Dictionary = KEYS[clampi(key_set, 0, KEYS.size() - 1)]
	if action == "bow" and Input.is_physical_key_pressed(keys["bow2"]):
		return true
	return Input.is_physical_key_pressed(keys[action])


func _stick(ax: JoyAxis, ay: JoyAxis, dead: float) -> Vector2:
	if joy < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(joy, ax), Input.get_joy_axis(joy, ay))
	var l := v.length()
	if l < dead:
		return Vector2.ZERO
	return v / l * ((minf(l, 1.0) - dead) / (1.0 - dead))


func _joy_btn(b: JoyButton) -> bool:
	return joy >= 0 and Input.is_joy_button_pressed(joy, b)


func _joy_axis(a: JoyAxis) -> float:
	return Input.get_joy_axis(joy, a) if joy >= 0 else 0.0


func read_move(delta: float) -> Vector3:
	if not bot_input.is_empty():
		var bm: Vector3 = bot_input.get("move", Vector3.ZERO)
		return bm.limit_length(1.0)
	var turn := float(_key("right")) - float(_key("left"))
	cam_yaw -= turn * 2.4 * delta
	var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15)
	cam_yaw -= look.x * absf(look.x) * 3.0 * delta
	var v := Vector2(0.0, float(_key("down")) - float(_key("up")))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(float(_joy_btn(JOY_BUTTON_DPAD_RIGHT)) - float(_joy_btn(JOY_BUTTON_DPAD_LEFT)),
			float(_joy_btn(JOY_BUTTON_DPAD_DOWN)) - float(_joy_btn(JOY_BUTTON_DPAD_UP)))
	return Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)


func sword_held() -> bool:
	if not bot_input.is_empty():
		return bot_input.get("sword", false)
	return _key("sword") or _joy_btn(JOY_BUTTON_RIGHT_SHOULDER) or _joy_btn(JOY_BUTTON_B) \
		or _joy_axis(JOY_AXIS_TRIGGER_RIGHT) > 0.4


func bow_held() -> bool:
	if not bot_input.is_empty():
		return bot_input.get("bow", false)
	return _key("bow") or _joy_btn(JOY_BUTTON_LEFT_SHOULDER) or _joy_btn(JOY_BUTTON_X) \
		or _joy_axis(JOY_AXIS_TRIGGER_LEFT) > 0.4


func jump_held() -> bool:
	if not bot_input.is_empty():
		return bot_input.get("jump", false)
	return _key("jump") or _joy_btn(JOY_BUTTON_A)


func any_attack_held() -> bool:
	return sword_held() or bow_held()


# --- Update ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	sword_cd -= delta
	bow_cd -= delta
	flash_t -= delta
	body_mat.emission_enabled = flash_t > 0.0
	body_mat.emission = Color(1.0, 0.3, 0.3)
	body_mat.emission_energy_multiplier = 2.0
	ember_orb.visible = carrying
	if carrying:
		ember_orb.position.y = 1.4 + sin(bob_t * 0.5 + Time.get_ticks_msec() * 0.005) * 0.05
	_animate_sword(delta)
	if not active:
		return
	if remote:
		if not carried:
			global_position = global_position.lerp(net_target, 1.0 - exp(-20.0 * delta))
		pivot.rotation.y = face
		return
	if carried:
		if main.net.mode == "client":
			global_position = global_position.lerp(net_target, 1.0 - exp(-18.0 * delta))
		vy = 0.0
		main.net.send_state(global_position, face, cam_yaw, index)
		return
	if is_down:
		main.net.send_state(global_position, face, cam_yaw, index)
		return
	_move(delta)
	main.net.send_state(global_position, face, cam_yaw, index)
	if sword_held() and sword_cd <= 0.0:
		_swing()
	elif bow_held() and bow_cd <= 0.0 and sword_cd <= 0.1:
		_shoot()


func _move(delta: float) -> void:
	var move := read_move(delta)
	var pos := global_position
	var spd := SPEED
	if W.in_water(pos.x, pos.z) and pos.y < 0.0:
		spd *= WATER_SLOW
	var np := pos + move * spd * delta
	np = W.push_out(np, BODY_R)
	# Boulders: stand on top if we're high enough, otherwise walk around them.
	var support := W.height(np.x, np.z)
	for b in get_tree().get_nodes_in_group("boulders"):
		if b.held or b.flying:
			continue
		var bp: Vector3 = b.global_position
		var off := Vector2(np.x - bp.x, np.z - bp.z)
		var reach: float = b.radius + BODY_R * 0.6
		if off.length() >= reach:
			continue
		var top: float = bp.y + b.radius * 1.8
		if pos.y >= top - CLIMB:
			support = maxf(support, top)
		elif off.length() > 0.001:
			off = off.normalized() * reach
			np.x = bp.x + off.x
			np.z = bp.z + off.y
	var flat := Vector2(np.x, np.z)
	if flat.length() > W.EDGE - 0.4:
		flat = flat.normalized() * (W.EDGE - 0.4)
		np.x = flat.x
		np.z = flat.y
	support = maxf(support, W.height(np.x, np.z))
	# Jumping and falling.
	var jump := jump_held()
	if jump and not jump_was_held and on_ground:
		vy = JUMP_V
		on_ground = false
		main.sound("dash", -10.0, 1.8)
	jump_was_held = jump
	if vy > 0.0 or np.y > support + 0.05:
		vy -= KNIGHT_GRAVITY * delta
		np.y += vy * delta
		if np.y <= support:
			np.y = support
			vy = 0.0
			on_ground = true
		else:
			on_ground = false
	else:
		np.y = support
		vy = 0.0
		on_ground = true
	global_position = np
	if move.length() > 0.1:
		face = lerp_angle(face, atan2(-move.x, -move.z), 1.0 - exp(-14.0 * delta))
		bob_t += delta * 14.0
		pivot.position.y = absf(sin(bob_t)) * 0.07
		pivot.rotation.z = sin(bob_t) * 0.08
		# Gentle camera follow so kids don't need the right stick.
		if bot_input.is_empty() and absf(_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15).x) < 0.01:
			cam_yaw = lerp_angle(cam_yaw, face, 1.0 - exp(-0.9 * delta))
	else:
		pivot.position.y = 0.0
		pivot.rotation.z = 0.0
	pivot.rotation.y = face


func _process(delta: float) -> void:
	_update_camera(delta)
	if hud_label:
		var lines := "P%d   HP %d / %d" % [index + 1, maxi(0, int(hp)), int(MAX_HP)]
		if carrying:
			lines += "\nCarrying an ember: take it to the campfire!"
		hud_label.text = lines
	if hint_label:
		if is_down:
			hint_label.text = "YOU'RE DOWN!\nA friend can stand next to you to revive you,\nor the Giant can carry you to the campfire"
		elif carried:
			hint_label.text = "Wheee! The Giant is carrying you!"
		else:
			hint_label.text = ""
	revive_ring.visible = is_down
	if is_down:
		var s := maxf(revive_progress, 0.05)
		revive_ring.scale = Vector3(s, 1.0, s)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target := global_position + Basis(Vector3.UP, cam_yaw) * Vector3(0.0, CAM_HEIGHT, CAM_DIST)
	if is_down:
		target = global_position + Basis(Vector3.UP, cam_yaw) * Vector3(0.0, 3.5, 3.0)
	var k := 1.0 - exp(-10.0 * delta)
	camera.global_position = camera.global_position.lerp(target, k) if delta < 0.5 else target
	var look := global_position + Vector3.UP * 0.8
	if camera.global_position.distance_to(look) > 0.1:
		camera.look_at(look, Vector3.UP)


func _animate_sword(delta: float) -> void:
	if swing_t > 0.0:
		swing_t -= delta
		var t := 1.0 - swing_t / 0.25
		sword_pivot.rotation = Vector3(0.1, lerpf(1.3, -1.5, t), 0.0)
	else:
		sword_pivot.rotation = sword_pivot.rotation.lerp(Vector3(0.5, 0.0, 0.0), 1.0 - exp(-10.0 * delta))


func _swing() -> void:
	sword_cd = SWORD_CD
	swing_t = 0.25
	main.sound("dash", -8.0, 1.5 + index * 0.1)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.2, 0.0, 0.05)
	main.knight_action(self, "swing", [global_position, face])


func _shoot() -> void:
	bow_cd = BOW_CD
	var fwd := Basis(Vector3.UP, face) * Vector3(0, 0, -1)
	var origin := global_position + Vector3.UP * 0.6 + fwd * 0.4
	var dir: Vector3 = main.auto_aim(origin, fwd)
	main.sound("shoot", -10.0, 0.7 + index * 0.1)
	if main.net.mode == "client":
		main.spawn_bolt(origin, dir, self, true)
	main.knight_action(self, "shoot", [origin, dir])


# --- Network -----------------------------------------------------------------

## Host: the TV says where this knight is.
func apply_remote_state(pos: Vector3, new_face: float, new_cam_yaw: float) -> void:
	if carried:
		return
	net_target = pos
	face = new_face
	cam_yaw = new_cam_yaw
	if not net_started:
		net_started = true
		global_position = pos


func net_state() -> Array:
	if not active:
		return [false]  # sleeping slot: keep the snapshot small (up to 6 knights)
	return [global_position, face, hp, is_down, revive_progress, active, carrying, carried]


## TV: authoritative state from the host.
func apply_net_state(st: Array) -> void:
	if st.size() < 8:
		if active:
			set_active(false)
			main.on_player_activity_changed(self)
		return
	hp = st[2]
	revive_progress = st[4]
	carrying = st[6]
	var was_carried := carried
	carried = st[7]
	if carried:
		net_target = st[0]
		if not was_carried:
			on_ground = false
	elif was_carried:
		global_position = st[0]  # landed: carry on from where the host put us
		vy = 0.0
	var act: bool = st[5]
	if act != active:
		set_active(act)
		main.on_player_activity_changed(self)
	var down: bool = st[3]
	if down != is_down:
		set_down(down)


func set_down(down: bool) -> void:
	is_down = down
	pivot.rotation.x = -PI / 2.0 if down else 0.0
	pivot.position.y = 0.2 if down else 0.0
	if down and joy >= 0:
		Input.start_joy_vibration(joy, 0.8, 1.0, 0.4)


## Feedback when the host says we got hit.
func on_hurt(_from: Vector3) -> void:
	flash_t = 0.12
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.4, 0.6, 0.12)


func grab_center() -> Vector3:
	return global_position + Vector3.UP * center_h


func can_grab() -> bool:
	return active


func on_grabbed() -> void:
	held = true
	carried = true
	fall_vel = Vector3.ZERO


func on_released(v: Vector3) -> void:
	held = false
	# Knights are set down gently (a little toss at most): no flinging friends across the room.
	var flat := Vector3(v.x, 0.0, v.z).limit_length(6.0)
	fall_vel = Vector3(flat.x, clampf(v.y, -4.0, 6.0), flat.z)


func hold_at(p: Vector3, _yaw: float) -> void:
	global_position = p - Vector3.UP * center_h
	net_target = global_position
