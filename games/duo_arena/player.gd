extends CharacterBody3D
## One first-person co-op player with its own camera (shown in its half of the split screen).
## Controller: left stick move, right stick look, RT/RB shoot, A/LB/LT dash.
## Keyboard P1: WASD move, mouse look, click or Space shoot, Shift dash.
## Keyboard P2: arrows forward/back + turn, Enter shoot, Ctrl dash.

const BulletScript := preload("res://games/duo_arena/bullet.gd")

const SPEED := 7.0
const DASH_SPEED := 22.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 0.7
const FIRE_INTERVAL := 0.12
const MAX_HP := 100.0
const REVIVE_TIME := 2.5
const REVIVE_RANGE := 2.6
const EYE_HEIGHT := 1.55
const STICK_YAW_SPEED := 3.2
const STICK_PITCH_SPEED := 2.2
const KEY_TURN_SPEED := 2.6
const MOUSE_SENS := 0.0028
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "fire": KEY_SPACE, "dash": KEY_SHIFT},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "fire": KEY_ENTER, "dash": KEY_CTRL},
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
var spread_t := 0.0
var yaw := 0.0
var pitch := 0.0
var fire_cd := 0.0
var dash_cd := 0.0
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var invuln_t := 0.0
var flash_t := 0.0
var dash_was_held := false
var hurt_sound_t := 0.0
var pulse_t := 0.0
var shake := 0.0
var bob_t := 0.0
var recoil := 0.0

var pivot: Node3D
var body_mat: StandardMaterial3D
var revive_ring: MeshInstance3D
var revive_fill: MeshInstance3D
var gun: Node3D
var muzzle_mat: StandardMaterial3D
var tag: Label3D

# VR (Steam Frame / any OpenXR headset): set by attach_xr().
var vr := false
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var wrist_label: Label3D
var snap_ready := true
var vr_velocity := Vector3.ZERO

# Networked co-op: on the host, player 2 is `remote` (driven by the Steam Machine);
# on the Steam Machine, player 1 is a `ghost` of the VR player, placed from snapshots.
var remote := false
var active := true  # player 3 sleeps (invisible, untargetable) until someone joins with a second input
var key_set := -1  # which KEYS layout this player uses (-1: by index)
var mouse_look := false
# Personal progression (skill map): own XP, purchased skill tiers and stat modifiers.
var xp := 0
var skills := {}
var personal := {"fire_rate": 1.0, "damage": 1.0, "dash_cd": 1.0, "speed": 1.0, "max_hp": 0.0, "armor": 1.0, "shield": 1.0}
var ghost := false
var net_target := Vector3.ZERO
var net_started := false
var net_head := Transform3D()
var net_hand := Transform3D()
var net_lhand := Transform3D()
var ghost_gun: Node3D
var vr_hurt_mat: StandardMaterial3D  # red glow around the VR player's head when hit
var vr_hurt := 0.0
var shield: Node3D  # VR left-hand energy shield: reflects spitter orbs
var shield_announced := false
var wrist_radar: MeshInstance3D
var ghost_head: Node3D  # follows the VR player's real head on the TV
var force_fire := false  # test bots: hold the trigger
var rapid_t := 0.0  # RAPID FIRE pickup: shoots twice as fast while > 0
var bubble_t := 0.0  # SHIELD BUBBLE pickup: can't be hurt while > 0
var bubble: MeshInstance3D
var revive_helper  # who is reviving us (gets the credit)
var slice_streak := 0
var slice_streak_t := 0.0
var pad_lost_t := -1.0  # seconds since this player's controller disconnected (-1: not lost)


## Bodies: visual layers 2-4 for P1-P3, 17-20 for P4-P7 (hidden from this player's own camera).
const ALL_BODIES := 14 | (15 << 16)
const NO_KEYS := 99  # key_set for controller-only drop-in players


func body_layer() -> int:
	return 2 << index if index < 3 else 1 << (13 + index)


## Viewmodel: visual layers 7-9 for P1-P3, 13-16 for P4-P7 (only this player's camera sees it).
func viewmodel_layer() -> int:
	return 64 << index if index < 3 else 1 << (9 + index)


func camera_cull_mask() -> int:
	return 1 | (ALL_BODIES & ~body_layer()) | viewmodel_layer()  # world + other players' bodies + own gun


func _ready() -> void:
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.8
	add_child(cs)
	yaw = rotation.y
	rotation.y = 0.0
	net_target = position

	# Body, seen by the partner only.
	pivot = Node3D.new()
	add_child(pivot)
	body_mat = main.make_material(color, 0.4)
	body_mat.metallic = 0.3
	body_mat.roughness = 0.35
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.6
	body.mesh = cap
	body.material_override = body_mat
	body.position.y = 0.8
	pivot.add_child(body)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.6, 0.18, 0.2)
	visor.mesh = vm
	visor.material_override = main.make_material(Color(0.9, 1.0, 1.0), 3.0)
	visor.position = Vector3(0, 1.3, -0.38)
	pivot.add_child(visor)
	var body_gun := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.18, 0.18, 0.7)
	body_gun.mesh = gm
	body_gun.material_override = main.make_material(Color(0.15, 0.15, 0.2), 0.0)
	body_gun.position = Vector3(0.35, 1.0, -0.45)
	pivot.add_child(body_gun)
	var marker := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 0.75
	marker.mesh = tm
	marker.material_override = main.make_material(color, 2.0)
	marker.position.y = 0.03
	pivot.add_child(marker)
	# Floating name tag so the partner can always find you, even through walls.
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = false
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = color
	tag.position.y = 2.3
	pivot.add_child(tag)
	_set_layers(pivot, body_layer())

	revive_ring = MeshInstance3D.new()
	var rr := TorusMesh.new()
	rr.inner_radius = REVIVE_RANGE - 0.08
	rr.outer_radius = REVIVE_RANGE
	revive_ring.mesh = rr
	revive_ring.material_override = main.make_material(color, 1.5)
	revive_ring.position.y = 0.04
	revive_ring.visible = false
	add_child(revive_ring)

	revive_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = REVIVE_RANGE
	disc.bottom_radius = REVIVE_RANGE
	disc.height = 0.02
	revive_fill.mesh = disc
	var fm: StandardMaterial3D = main.make_material(color, 1.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color.a = 0.35
	revive_fill.material_override = fm
	revive_fill.position.y = 0.03
	revive_fill.visible = false
	add_child(revive_fill)

	if ghost and index == 0:
		ghost_gun = _make_gun()
		add_child(ghost_gun)
		_set_layers(ghost_gun, body_layer())


## SHIELD BUBBLE pickup: a shimmering ball around the body (others see it; you see the HUD tint).
func _update_bubble() -> void:
	if bubble == null:
		if bubble_t <= 0.0 or pivot == null:
			return
		bubble = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.05
		sm.height = 2.1
		sm.radial_segments = 16
		sm.rings = 8
		bubble.mesh = sm
		var m: StandardMaterial3D = main.make_material(Color(0.45, 0.65, 1.0), 1.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.25
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.rim_enabled = true
		m.rim = 1.0
		bubble.material_override = m
		bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bubble.position.y = 0.9
		pivot.add_child(bubble)
		_set_layers(bubble, body_layer())
	var on := bubble_t > 0.0 and active and not is_down
	bubble.visible = on and (bubble_t > 1.5 or int(bubble_t * 8.0) % 2 == 0)
	if on:
		bubble.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.04)


## Called by main once the split-screen camera exists.
func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 80.0
	camera.near = 0.05
	gun = _make_gun()
	camera.add_child(gun)
	gun.position = Vector3(0.2, -0.17, -0.42)
	gun.scale = Vector3.ONE * 0.55
	_update_camera(0.0)


## VR player: the headset is the camera, the right controller is the gun.
func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	camera = cam
	cam.cull_mask = camera_cull_mask()
	cam.near = 0.05
	gun = _make_gun()
	hand_r.add_child(gun)
	gun.position = Vector3(0.0, -0.03, -0.1)
	gun.scale = Vector3.ONE * 0.7
	# Laser sight.
	var laser := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.004, 0.004, 12.0)
	laser.mesh = lm
	var laser_mat: StandardMaterial3D = main.make_material(color, 2.0)
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.albedo_color.a = 0.35
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser.material_override = laser_mat
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.position = Vector3(0, 0, -6.2)
	hand_r.add_child(laser)
	_set_layers(laser, viewmodel_layer())
	# Wrist display on the left hand.
	wrist_label = Label3D.new()
	wrist_label.pixel_size = 0.0005
	wrist_label.font_size = 48
	wrist_label.outline_size = 10
	wrist_label.modulate = color.lightened(0.4)
	wrist_label.position = Vector3(0.0, 0.05, 0.08)
	wrist_label.rotation_degrees = Vector3(-55, 0, 0)
	wrist_label.no_depth_test = false
	hand_l.add_child(wrist_label)
	_set_layers(wrist_label, viewmodel_layer())


func _make_gun() -> Node3D:
	var g := Node3D.new()
	var barrel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.11, 0.55)
	barrel.mesh = bm
	var gun_mat: StandardMaterial3D = main.make_material(Color(0.12, 0.13, 0.17), 0.0)
	gun_mat.metallic = 0.8
	gun_mat.roughness = 0.3
	barrel.material_override = gun_mat
	g.add_child(barrel)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.095, 0.025, 0.4)
	stripe.mesh = sm
	stripe.material_override = main.make_material(color, 1.2)
	stripe.position = Vector3(0, 0.06, 0.02)
	g.add_child(stripe)
	var muzzle := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.06
	mm.height = 0.12
	muzzle.mesh = mm
	muzzle_mat = main.make_material(color.lightened(0.5), 0.0)
	muzzle.material_override = muzzle_mat
	muzzle.position = Vector3(0, 0, -0.3)
	g.add_child(muzzle)
	_set_layers(g, viewmodel_layer())
	for mi in [barrel, stripe, muzzle]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


func aim_dir() -> Vector3:
	if vr:
		return -hand_r.global_basis.z
	return -camera.global_basis.z if camera else Vector3(0, 0, -1)


func _input(event: InputEvent) -> void:
	# Mouse look for player 1 while the mouse is captured.
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.3)


func _physics_process(delta: float) -> void:
	fire_cd -= delta
	dash_cd -= delta
	invuln_t -= delta
	spread_t -= delta
	flash_t -= delta
	rapid_t = maxf(0.0, rapid_t - delta)
	bubble_t = maxf(0.0, bubble_t - delta)
	_update_bubble()
	body_mat.emission_energy_multiplier = 3.0 if flash_t > 0.0 else 0.4
	if muzzle_mat:
		muzzle_mat.emission_energy_multiplier = maxf(0.0, muzzle_mat.emission_energy_multiplier - delta * 60.0)

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
		if main.net.mode == "client":
			var fill := maxf(revive_progress, 0.01)
			revive_fill.scale = Vector3(fill, 1, fill)  # revives are decided by the host
		else:
			_update_revive(delta)
		_update_camera(delta)
		main.net.send_state(global_position, yaw, pitch, index)
		return

	var move := _read_move()
	var dash_held := _dash_held()
	if dash_held and not dash_was_held and dash_cd <= 0.0:
		dash_t = DASH_TIME
		dash_cd = DASH_COOLDOWN * stat("dash_cd")
		dash_dir = move.normalized() if move.length() > 0.2 else Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
		invuln_t = maxf(invuln_t, DASH_TIME + 0.1)
		main.burst(global_position + Vector3.UP * 0.3, color, 8, 0.1)
		main.sound("dash", -4.0)
		main.net.send_action("dash", [], index)
		main.director().on_dash(self)
	dash_was_held = dash_held

	if dash_t > 0.0:
		dash_t -= delta
		velocity = dash_dir * DASH_SPEED
	else:
		velocity = move * SPEED * stat("speed")
	if vr:
		# Applied every rendered frame in _process so locomotion is smooth in the headset.
		vr_velocity = velocity
	else:
		move_and_slide()
		position.y = 0.0
		var flat := Vector2(position.x, position.z)
		var limit: float = main.arena_radius - 0.8
		if flat.length() > limit:
			flat = flat.normalized() * limit
			position.x = flat.x
			position.z = flat.y
	bob_t += velocity.length() * delta * 1.6
	_update_camera(delta)
	main.net.send_state(global_position, yaw, pitch, index)

	if _fire_held() and fire_cd <= 0.0:
		_shoot()


func _update_camera(delta: float) -> void:
	pivot.rotation.y = yaw
	if camera == null or vr:
		return
	shake = maxf(0.0, shake - delta * 3.0)
	recoil = maxf(0.0, recoil - delta * 8.0)
	var eye := EYE_HEIGHT if not is_down else 0.45
	var bob := sin(bob_t) * 0.05 if not is_down else 0.0
	camera.global_position = global_position + Vector3(0, eye + bob, 0)
	camera.rotation = Vector3(pitch + recoil * 0.008 + randf_range(-1, 1) * shake * 0.02,
		yaw + randf_range(-1, 1) * shake * 0.02, 0.35 if is_down else 0.0)
	if gun:
		gun.visible = not is_down
		gun.position = Vector3(0.2 + cos(bob_t * 0.5) * 0.006, -0.17 + absf(sin(bob_t * 0.5)) * 0.008, -0.42 + recoil * 0.015)


func _shoot() -> void:
	fire_cd = FIRE_INTERVAL * stat("fire_rate") * (0.5 if rapid_t > 0.0 else 1.0)
	main.sound("shoot", -12.0, 1.0 + (index % 3) * 0.25 + floorf(index / 3.0) * 0.1)
	recoil = 1.0
	if muzzle_mat:
		muzzle_mat.emission_energy_multiplier = 6.0
	var origin := camera.global_position
	if vr:
		origin = hand_r.global_position + aim_dir() * 0.2
		hand_r.trigger_haptic_pulse("haptic", 0.0, 0.25, 0.04, 0.0)
	var dir: Vector3 = main.auto_aim(origin, aim_dir())
	var angles := [0.0]
	if spread_t > 0.0:
		angles = [-0.12, 0.0, 0.12]
	var client: bool = main.net.mode == "client"
	var starts := []
	var dirs := []
	for a in angles:
		var d := dir.rotated(Vector3.UP, a)
		var start := origin + d * 0.9  # far enough from the hand that the glow doesn't dazzle in VR
		if not vr:
			start = origin + d * 1.3 + camera.global_basis.x * 0.08 - camera.global_basis.y * 0.08
		# On the Steam Machine our bullets are just for show; the host fires the real ones.
		main.spawn_bullet(start, d, color, self, client)
		starts.append(start)
		dirs.append(d)
	if client:
		main.net.send_action("fire", [starts, dirs], index)


# --- Input -------------------------------------------------------------------

func keys() -> int:
	return key_set if key_set >= 0 else mini(index, KEYS.size() - 1)


func _key(action: String) -> bool:
	if keys() >= KEYS.size():
		return false
	return Input.is_physical_key_pressed(KEYS[keys()][action])


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
	# Squared response for fine aiming, full speed at the edge.
	look = look * look.length()
	yaw -= look.x * STICK_YAW_SPEED * delta
	pitch = clampf(pitch - look.y * STICK_PITCH_SPEED * delta, -1.3, 1.3)
	if keys() == 1:
		# The arrow-key layout turns with left/right.
		yaw -= (float(_key("right")) - float(_key("left"))) * KEY_TURN_SPEED * delta


func _read_move() -> Vector3:
	var v := Vector2.ZERO
	if vr:
		var s := hand_l.get_vector2("primary")
		if s.length() < 0.15:
			return Vector3.ZERO
		return Basis(Vector3.UP, yaw) * Vector3(s.x, 0.0, -s.y).limit_length(1.0)
	if keys() == 0:
		v = Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	else:
		v.y = float(_key("down")) - float(_key("up"))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)))
	var local := Vector3(v.x, 0.0, v.y).limit_length(1.0)
	return Basis(Vector3.UP, yaw) * local


func _fire_held() -> bool:
	if vr:
		return hand_r.get_float("trigger") > 0.5 or force_fire
	if force_fire:
		return true
	if _key("fire"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		return Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	return false


func _dash_held() -> bool:
	if vr:
		return hand_r.is_button_pressed("ax_button") or hand_l.is_button_pressed("ax_button") \
			or hand_l.get_float("trigger") > 0.5
	if _key("dash"):
		return true
	if joy >= 0:
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_A) \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT) > 0.4
	return false


func _process(delta: float) -> void:
	if not vr or xr_origin == null or vr_velocity == Vector3.ZERO:
		return
	var step := vr_velocity * delta
	# Don't walk through pillars (slide along them instead); the arena edge is handled in _vr_update.
	# If the player has physically walked into a pillar, let the stick move them out freely.
	if test_move(global_transform, step):
		var inside := test_move(global_transform, Vector3(0.0, 0.001, 0.0))
		if not inside:
			var along_x := Vector3(step.x, 0.0, 0.0)
			var along_z := Vector3(0.0, 0.0, step.z)
			if not test_move(global_transform, along_x):
				step = along_x
			elif not test_move(global_transform, along_z):
				step = along_z
			else:
				return
	xr_origin.global_position += step
	global_position += step


## Headset drives facing and body position; right stick snap-turns; wrist shows status.
func _vr_update(_delta: float) -> void:
	_update_vr_hurt(_delta)
	_ensure_shield()
	_update_sword(_delta)
	_update_gun_hp()
	_ensure_wrist_radar()
	yaw = xr_camera.global_rotation.y
	# Keep the body under the headset when the player walks around the room.
	var head := xr_camera.global_position
	var target := Vector3(head.x, 0.0, head.z)
	var flat := Vector2(target.x, target.z)
	var limit: float = main.arena_radius - 0.8
	if flat.length() > limit:
		var fix := flat.normalized() * limit - flat
		xr_origin.global_position += Vector3(fix.x, 0.0, fix.y)
		target += Vector3(fix.x, 0.0, fix.y)
	global_position = target
	var turn := hand_r.get_vector2("primary").x
	if absf(turn) > 0.7 and snap_ready:
		snap_ready = false
		if not has_meta("turned"):
			set_meta("turned", true)
			print("VR snap turn works")
		var angle := -signf(turn) * deg_to_rad(30.0)
		var rot := Basis(Vector3.UP, angle)
		var pivot_pt := xr_camera.global_position
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, pivot_pt + rot * (xr_origin.global_position - pivot_pt))
	elif absf(turn) < 0.3:
		snap_ready = true
	var status := "DOWN - partner, revive me!" if is_down else ("SPREAD SHOT" if spread_t > 0.0 else "")
	var d = main.director()
	if d.boss_name != "" and d.boss_frac >= 0.0:
		status += ("   " if status != "" else "") + "%s %d%%" % [d.boss_name, int(ceil(d.boss_frac * 100.0))]
	elif d.event_name != "":
		status += ("   " if status != "" else "") + str(d.EVENTS[d.event_name][0])
	if main.net.mode == "host" and not main.net.connected:
		status = "Waiting for the TV player to join…"
	if main.SIMPLE_MODE:  # one short line on the wrist: which wave
		wrist_label.text = "WAVE %d" % main.wave if main.wave > 0 else ""
		_update_sword_demo(_delta)
		return
	wrist_label.text = "HP %d / %d   XP %d\nWAVE %d   SCORE %d\n%s" % [maxi(0, int(hp)), int(stat("max_hp")), xp, main.wave, main.score, status]


# --- Health & reviving -------------------------------------------------------

func take_damage(amount: float, from_pos = null) -> void:
	if is_down or invuln_t > 0.0 or not active:
		return
	if bubble_t > 0.0:
		var now := Time.get_ticks_msec()
		if now > int(get_meta("bubble_snd", 0)):
			set_meta("bubble_snd", now + 300)
			main.sound("bubble", -8.0, 1.6)
		return
	amount *= personal.get("armor", 1.0)
	if remote:
		main.net.event("hurt", [index, from_pos if from_pos != null else global_position])
	main.achievements().on_damage(amount)
	if hud and from_pos != null:
		hud.damage_from(from_pos)
	hp -= amount
	flash_t = 0.08
	shake = maxf(shake, 0.3)
	if hud:
		hud.hurt()
	hurt_sound_t -= get_physics_process_delta_time()
	if hurt_sound_t <= 0.0:
		hurt_sound_t = 0.2
		main.sound("hurt", -4.0, 1.0 + (index % 3) * 0.2)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.3, 0.5, 0.1)
	if vr:
		vr_hurt = 1.0
		hand_l.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.1, 0.0)
		hand_r.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.1, 0.0)
	if hp <= 0.0:
		_go_down()


func heal(amount: float) -> void:
	if not is_down:
		hp = minf(stat("max_hp"), hp + amount)


func _go_down() -> void:
	hp = 0.0
	is_down = true
	revive_progress = 0.0
	dash_t = 0.0
	_apply_down_pose(true)
	main.burst(global_position + Vector3.UP, color, 24)
	shake = 1.0
	main.sound("down")
	main.shockwave(global_position, 6.0, 30.0, 2.0, color)
	main.director().on_down(self)
	pulse_t = 3.5
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.8, 1.0, 0.4)


func _update_revive(delta: float) -> void:
	var helper_near := false
	for p in main.players:
		if p != self and p.active and not p.is_down and p.global_position.distance_to(global_position) <= REVIVE_RANGE:
			if not helper_near:
				revive_helper = p
			helper_near = true
	if helper_near:
		revive_progress += delta / (REVIVE_TIME * main.upg.revive)
	else:
		revive_progress = maxf(0.0, revive_progress - delta * 0.25)
	pulse_t -= delta
	if pulse_t <= 0.0:
		pulse_t = 3.5
		main.shockwave(global_position, 4.0, 18.0, 0.0, color)
		main.sound("dash", -6.0, 0.6)
	var s := maxf(revive_progress, 0.01)
	revive_fill.scale = Vector3(s, 1, s)
	if revive_progress >= 1.0:
		main.achievements().unlock("teamwork")
		main.director().on_revive(revive_helper, self)
		revive(0.5)


func revive(fraction: float) -> void:
	is_down = false
	hp = stat("max_hp") * fraction
	invuln_t = 2.0
	_apply_down_pose(false)
	main.burst(global_position + Vector3.UP, Color(0.5, 1.0, 0.6), 24)
	main.sound("revive")
	main.shockwave(global_position, 6.0, 30.0, 2.0, Color(0.5, 1.0, 0.6))


func _apply_down_pose(down: bool) -> void:
	_down_arrow().visible = down
	pivot.rotation.x = -PI / 2.0 if down else 0.0
	pivot.position.y = 0.45 if down else 0.0
	revive_ring.visible = down
	revive_fill.visible = down
	if down:
		revive_fill.scale = Vector3(0.01, 1, 0.01)


# --- Networked co-op ---------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if camera:
		return camera.global_transform
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), global_position + Vector3.UP * EYE_HEIGHT)


## Wake up (or put to sleep) a player slot: visible, collidable and targetable only when active.
func set_active(on: bool) -> void:
	active = on
	visible = on
	collision_layer = 2 if on else 0
	if not on and is_down:  # leaving while down: come back standing
		is_down = false
		revive_progress = 0.0
		_apply_down_pose(false)
	if not on and main != null:
		hp = stat("max_hp")


## A stat for this player: team upgrades combined with their own skill-map upgrades.
func stat(name: String) -> float:
	if name == "max_hp":
		return main.upg.max_hp + personal.get("max_hp", 0.0)
	return main.upg.get(name, 1.0) * personal.get(name, 1.0)


const PERSONAL_KEYS := ["fire_rate", "damage", "dash_cd", "speed", "max_hp", "armor", "shield"]


## Personal stats as a small packed array for snapshots.
func pack_personal() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in PERSONAL_KEYS:
		out.append(float(personal.get(k, 0.0 if k == "max_hp" else 1.0)))
	return out


func unpack_personal(packed: PackedFloat32Array) -> void:
	for i in mini(packed.size(), PERSONAL_KEYS.size()):
		personal[PERSONAL_KEYS[i]] = packed[i]


func add_personal(name: String, mode: String, amount: float) -> void:
	if mode == "mul":
		personal[name] = personal.get(name, 1.0) * amount
	else:
		personal[name] = personal.get(name, 0.0) + amount
		if name == "max_hp" and not is_down:
			hp += amount


func left_hand_transform() -> Transform3D:
	return hand_l.global_transform if vr else Transform3D()


func hand_transform() -> Transform3D:
	if vr:
		return hand_r.global_transform
	return head_transform()


## Host: latest position and view of player 2 from the Steam Machine.
func apply_remote_state(pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	net_target = Vector3(pos.x, 0.0, pos.z)
	yaw = new_yaw
	pitch = new_pitch
	if not net_started:
		net_started = true
		global_position = net_target


## Client: authoritative state from the host's snapshot.
## [pos, yaw, pitch, hp, is_down, revive_progress, spread_t, head, hand, lhand, personal, xp, skills]
func apply_net_state(st: Array) -> void:
	hp = st[3]
	if st.size() > 12:
		if st[10] is PackedFloat32Array:
			unpack_personal(st[10])
		elif st[10] is Dictionary:
			personal = st[10]
		xp = st[11]
		skills = st[12]
	if st.size() > 13 and st[13] != active:
		set_active(st[13])
		main.on_player_activity_changed(self)
	revive_progress = st[5]
	spread_t = st[6]
	if st.size() > 15:
		rapid_t = st[14]
		bubble_t = st[15]
	elif st.size() > 13:
		rapid_t = 0.0
		bubble_t = 0.0
	if ghost:
		net_target = st[0]
		yaw = st[1]
		pitch = st[2]
		if st[7] is Transform3D:
			net_head = st[7]
		if st[8] is Transform3D:
			net_hand = st[8]
		if st.size() > 9 and st[9] is Transform3D:
			net_lhand = st[9]
		if not net_started:
			net_started = true
			global_position = net_target
	var down: bool = st[4]
	if down != is_down:
		is_down = down
		_apply_down_pose(down)
		if down:
			dash_t = 0.0
			shake = 1.0
		else:
			invuln_t = 2.0


## Client: the host says our player 2 got hit from `from_pos`.
func on_remote_hurt(from_pos: Vector3) -> void:
	flash_t = 0.08
	shake = maxf(shake, 0.3)
	if hud:
		hud.hurt()
		hud.damage_from(from_pos)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.3, 0.5, 0.1)


func _ghost_update(delta: float) -> void:
	global_position = global_position.lerp(net_target, 1.0 - exp(-15.0 * delta))
	pivot.rotation.y = yaw
	if ghost_head == null and index == 0:
		ghost_head = Node3D.new()
		add_child(ghost_head)
		var helmet := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.16
		hs.height = 0.3
		helmet.mesh = hs
		helmet.material_override = body_mat
		ghost_head.add_child(helmet)
		var visor := MeshInstance3D.new()
		var vb := BoxMesh.new()
		vb.size = Vector3(0.24, 0.07, 0.08)
		visor.mesh = vb
		visor.material_override = main.make_material(Color(0.9, 1.0, 1.0), 3.0)
		visor.position = Vector3(0, 0.01, -0.14)
		ghost_head.add_child(visor)
		_set_layers(ghost_head, body_layer())
	if net_lhand != Transform3D() and index == 0:
		_ensure_shield()
		shield.global_transform = net_lhand.orthonormalized() * Transform3D(Basis(), Vector3(0.0, 0.0, -0.06))
	if net_head != Transform3D() and ghost_head != null:
		var target := net_head.orthonormalized()
		ghost_head.global_transform = ghost_head.global_transform.interpolate_with(target, 1.0 - exp(-20.0 * delta))
		ghost_head.visible = not is_down
	if ghost_gun:
		ghost_gun.global_transform = net_hand.scaled_local(Vector3.ONE * 0.8)
		ghost_gun.visible = not is_down
	if is_down:
		var fill := maxf(revive_progress, 0.01)
		revive_fill.scale = Vector3(fill, 1, fill)


func _remote_update(delta: float) -> void:
	global_position = net_target
	pivot.rotation.y = yaw
	if is_down:
		_update_revive(delta)


func _update_vr_hurt(delta: float) -> void:
	if vr_hurt_mat == null:
		var shell := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		sphere.radial_segments = 16
		sphere.rings = 8
		shell.mesh = sphere
		vr_hurt_mat = StandardMaterial3D.new()
		vr_hurt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vr_hurt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vr_hurt_mat.cull_mode = BaseMaterial3D.CULL_FRONT  # seen from inside
		vr_hurt_mat.no_depth_test = false
		vr_hurt_mat.render_priority = 20
		vr_hurt_mat.albedo_color = Color(1.0, 0.05, 0.05, 0.0)
		shell.material_override = vr_hurt_mat
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		xr_camera.add_child(shell)
		_set_layers(shell, viewmodel_layer())
	vr_hurt = maxf(0.0, vr_hurt - delta * 4.0)
	var low := 0.08 if hp < stat("max_hp") * 0.3 and not is_down else 0.0
	vr_hurt_mat.albedo_color.a = maxf(vr_hurt * 0.3, low)


func _ensure_shield() -> void:
	if shield != null:
		shield.visible = not is_down
		shield.scale = Vector3.ONE * personal.get("shield", 1.0)
		return
	shield = Node3D.new()
	if ghost:
		add_child(shield)  # placed from the replicated left hand each frame
	else:
		hand_l.add_child(shield)
		shield.position = Vector3(0.0, 0.0, -0.06)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.2
	cyl.height = 0.015
	cyl.radial_segments = 24
	disc.mesh = cyl
	var mat: StandardMaterial3D = main.make_material(color, 1.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = mat
	disc.rotation.x = PI / 2.0  # face forward along the hand
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.add_child(disc)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.19
	tm.outer_radius = 0.215
	rim.mesh = tm
	rim.material_override = main.make_material(color, 3.0)
	rim.rotation.x = PI / 2.0
	shield.add_child(rim)
	if ghost:
		_set_layers(shield, body_layer())


## Health readout on top of the gun, where the VR player is always looking.
func _update_gun_hp() -> void:
	var l: Label3D = get_meta("gun_hp") if has_meta("gun_hp") else null
	if l == null:
		l = Label3D.new()
		l.font_size = 48
		l.outline_size = 14
		l.pixel_size = 0.0007
		l.no_depth_test = false
		l.render_priority = 6
		hand_r.add_child(l)
		l.position = Vector3(0.0, 0.07, 0.02)
		l.rotation_degrees = Vector3(-30, 0, 0)
		set_meta("gun_hp", l)
	var frac := clampf(hp / maxf(stat("max_hp"), 1.0), 0.0, 1.0)
	l.text = "HP %d" % int(ceil(hp))
	var dir_node = main.director()
	if main.SIMPLE_MODE:
		pass  # just the health number
	elif dir_node.combo >= 2:
		l.text += "\nCOMBO x%d" % dir_node.combo
	if main.SIMPLE_MODE:
		pass
	elif bubble_t > 0.0:
		l.text += "\nBUBBLE %d" % int(ceil(bubble_t))
	elif rapid_t > 0.0:
		l.text += "\nRAPID %d" % int(ceil(rapid_t))
	l.modulate = Color(1.0, 0.3, 0.3) if frac < 0.3 else (Color(1.0, 0.85, 0.3) if frac < 0.6 else Color(0.4, 1.0, 0.5))


## David's idea: the left hand swaps between the shield and a glowing sword. Swap with the left
## trigger, or (since the Frame's left trigger may not reach the game) reach over your left shoulder
## like drawing a sword from your back. Swing the sword through enemies to slice them.
func _update_sword(delta: float) -> void:
	var sword: Node3D = get_meta("sword") if has_meta("sword") else null
	if sword == null:
		sword = Node3D.new()
		hand_l.add_child(sword)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.012, 0.9)
		blade.mesh = bm
		blade.position = Vector3(0.0, 0.0, -0.5)
		blade.material_override = main.make_material(Color(0.6, 0.95, 1.0), 4.0)
		set_meta("blade_mat", blade.material_override)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sword.add_child(blade)
		var guard := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.18, 0.03, 0.03)
		guard.mesh = gm
		guard.position = Vector3(0.0, 0.0, -0.05)
		guard.material_override = main.make_material(color, 2.0)
		sword.add_child(guard)
		sword.visible = false
		set_meta("sword", sword)
	# Swap: left trigger, or the over-the-shoulder draw gesture.
	var trig := hand_l.get_float("trigger") > 0.6 or hand_l.is_button_pressed("trigger_click")
	var head := xr_camera.global_transform
	var rel := head.affine_inverse() * hand_l.global_position  # hand in head space (+Y up, +Z behind)
	# Beside/behind the ear (kids couldn't reach "above the eyes and behind the head"), held for 0.2 s
	# so a fast sword swing passing through doesn't swap by accident.
	var near_shoulder := rel.y > -0.2 and rel.z > -0.06 and Vector2(rel.x, rel.z).length() < 0.35
	set_meta("shoulder_t", float(get_meta("shoulder_t", 0.0)) + delta if near_shoulder else 0.0)
	var over_shoulder := float(get_meta("shoulder_t", 0.0)) > 0.2
	var want := trig or over_shoulder
	if want and not get_meta("swap_was", false) and Time.get_ticks_msec() > int(get_meta("swap_ok", 0)):
		set_meta("swap_ok", Time.get_ticks_msec() + 600)
		var to_sword := not sword.visible
		sword.visible = to_sword
		main.sound("dash", -6.0, 1.6 if to_sword else 0.8)
		hand_l.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.1, 0.0)
		set_meta("swapped", int(get_meta("swapped", 0)) + 1)  # the ghost-hand demo stops once they've done it
		if to_sword and not has_meta("sword_told") and not main.SIMPLE_MODE:
			set_meta("sword_told", true)
			main._show_center("SWORD!\nSwing it through enemies. Reach over your shoulder again for the shield", 3.0)
	set_meta("swap_was", want)
	if shield:
		shield.visible = not sword.visible and not is_down
	if not sword.visible or is_down or main.net.mode == "client":
		set_meta("sword_prev", hand_l.global_position)
		return
	# Slice: only a real swing hurts (hand speed), each enemy at most every 0.35 s.
	var prev: Vector3 = get_meta("sword_prev", hand_l.global_position)
	var speed := hand_l.global_position.distance_to(prev) / maxf(delta, 0.001)
	set_meta("sword_prev", hand_l.global_position)
	var blade_mat: StandardMaterial3D = get_meta("blade_mat", null)
	if blade_mat != null:
		blade_mat.emission_energy_multiplier = lerpf(blade_mat.emission_energy_multiplier, 3.0 + minf(speed, 6.0), 0.3)
	if speed < 1.2:
		return
	var fwd := -hand_l.global_basis.z
	var now := Time.get_ticks_msec()
	slice_streak_t -= delta
	if slice_streak_t <= 0.0:
		slice_streak = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if now < int(e.get_meta("sliced_until", 0)):
			continue
		var c: Vector3 = e.center()
		for t in [0.25, 0.55, 0.9]:
			var p: Vector3 = hand_l.global_position + fwd * float(t)
			var flat := Vector2(p.x - c.x, p.z - c.z)
			if flat.length() < float(e.radius) + 0.15 and absf(p.y - c.y) < float(e.radius) + 0.6:
				e.set_meta("sliced_until", now + 350)
				var dir := Vector3(e.global_position.x - global_position.x, 0.0, e.global_position.z - global_position.z).normalized()
				e.sword_hit(4.0 * stat("damage") * (1.0 + 0.25 * mini(slice_streak, 4)), dir, self)
				slice_streak += 1
				slice_streak_t = 1.3
				if e.dead:
					main.director().add_stat(self, "slices", 1)
				if slice_streak >= 3 and not main.SIMPLE_MODE:
					main.popup(c + Vector3.UP * (float(e.radius) + 0.8), "SLICE x%d!" % slice_streak, Color(0.6, 0.95, 1.0))
				main.burst(p, Color(0.6, 0.95, 1.0), 10, 0.08)
				main.sound("slice", -2.0, 1.0 + 0.08 * mini(slice_streak, 6))
				hand_l.trigger_haptic_pulse("haptic", 0.0, 0.9, 0.08, 0.0)
				break
	# The blade also cuts fireballs in half and bats spit orbs back.
	var tip := hand_l.global_position + fwd * 0.95
	for s in get_tree().get_nodes_in_group("enemy_shots"):
		if s.friendly or s.spent:
			continue
		var cp := Geometry3D.get_closest_point_to_segment(s.global_position, hand_l.global_position, tip)
		if cp.distance_to(s.global_position) < 0.3 * float(s.size) + 0.2:
			hand_l.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.1, 0.0)
			if s.fireball:
				s.shot_down()
				if not main.SIMPLE_MODE:
					main.popup(cp + Vector3.UP * 0.6, "SLICED!", Color(1.0, 0.7, 0.3))
			else:
				s._reflect(fwd)
				main.achievements().unlock("parry")
	if main.sky_fish != null and main.sky_fish.has_method("sword_check"):
		if main.sky_fish.sword_check(hand_l.global_position, tip, self):
			hand_l.trigger_haptic_pulse("haptic", 0.0, 1.0, 0.15, 0.0)


## Host: does the VR shield catch something at `pos`? Returns the reflect direction, or ZERO.
func shield_reflect(pos: Vector3) -> Vector3:
	if not vr or is_down or shield == null or not shield.visible:
		return Vector3.ZERO
	if shield.global_position.distance_to(pos) > 0.42 * personal.get("shield", 1.0):
		return Vector3.ZERO
	hand_l.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.12, 0.0)
	main.achievements().unlock("parry")
	if not shield_announced and not main.SIMPLE_MODE:
		shield_announced = true
		main._show_center("SHIELD PARRY!\nYour left hand reflects green orbs back at enemies", 2.5)
	return -hand_l.global_basis.z


## VR: the flat players' radar, rendered onto a small screen on the left wrist.
func _ensure_wrist_radar() -> void:
	if wrist_radar != null:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var radar := preload("res://games/duo_arena/hud.gd").new()
	radar.player = self
	radar.main = main
	radar.radar_only = true
	vp.add_child(radar)
	wrist_radar = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)
	wrist_radar.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = vp.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wrist_radar.material_override = mat
	wrist_radar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_l.add_child(wrist_radar)
	# On top of the wrist, tilted towards the eyes; the status text sits just behind it.
	wrist_radar.position = Vector3(0.0, 0.045, 0.16)
	wrist_radar.rotation_degrees = Vector3(-60, 0, 0)
	_set_layers(wrist_radar, viewmodel_layer())
	wrist_label.position = Vector3(0.0, 0.11, 0.2)


## A bouncing arrow over a downed player (seen by everyone else): "go here!" without any words.
## Standing in their glowing ring revives them.
func _down_arrow() -> Node3D:
	var arrow: Node3D = get_meta("down_arrow") if has_meta("down_arrow") else null
	if arrow != null:
		return arrow
	arrow = Node3D.new()
	add_child(arrow)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.38
	cm.bottom_radius = 0.0
	cm.height = 0.6
	cm.radial_segments = 12
	cone.mesh = cm
	cone.material_override = main.make_material(color.lightened(0.3), 3.0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(cone)
	var stem := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.18, 0.45, 0.18)
	stem.mesh = sm
	stem.material_override = cone.material_override
	stem.position.y = 0.5
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(stem)
	arrow.position.y = 2.4
	_set_layers(arrow, body_layer())  # not in the downed player's own view
	var t := arrow.create_tween().set_loops()
	t.tween_property(arrow, "position:y", 1.9, 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_property(arrow, "position:y", 2.4, 0.35).set_trans(Tween.TRANS_SINE)
	arrow.visible = false
	set_meta("down_arrow", arrow)
	return arrow


## VR, simple mode: from wave 2 a see-through "mirror" figure in front of the VR player shows the
## sword move: left hand up beside the ear, hold, the sword appears, swing. It goes away once the
## player has swapped to the sword and back (or after a while; it comes back at wave 4 if never tried).
func _update_sword_demo(delta: float) -> void:
	if main.net.mode == "client" or ghost:
		return
	var demo: Node3D = get_meta("sword_demo") if has_meta("sword_demo") else null
	var w: int = main.wave
	if w >= 2 and int(get_meta("demo_wave", 0)) == 0 or (w >= 4 and int(get_meta("demo_wave", 0)) == 2 and int(get_meta("swapped", 0)) == 0):
		set_meta("demo_wave", w)
		set_meta("demo_left", 14.0 if w < 4 else 10.0)
	var left: float = float(get_meta("demo_left", 0.0)) - delta
	set_meta("demo_left", left)
	var want: bool = left > 0.0 and int(get_meta("swapped", 0)) < 2 and not is_down and not main.game_over
	if not want:
		if demo != null:
			demo.visible = false
		return
	if demo == null:
		demo = _build_sword_demo()
	demo.visible = true
	# Stand 1.6 m in front of the player's face (follows the head's turn slowly).
	var cam := xr_camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var want_pos := cam.origin + fwd * 1.6 + Vector3.DOWN * 0.15
	demo.global_position = demo.global_position.lerp(want_pos, 1.0 - exp(-3.0 * delta)) if demo.has_meta("placed") else want_pos
	demo.set_meta("placed", true)
	var face := cam.origin - demo.global_position
	face.y = 0.0
	if face.length() > 0.01:
		demo.global_basis = Basis(Vector3.UP, atan2(face.x, face.z))  # local +Z points at the player
	# Hand path in the figure's space: +X is the player's right, so -X is the mirror of their LEFT hand.
	var cyc := fmod(Time.get_ticks_msec() / 1000.0, 2.6)
	var rest := Vector3(-0.3, -0.5, 0.15)
	var ear := Vector3(-0.2, 0.0, -0.05)
	var hand: Node3D = demo.get_meta("hand")
	var sword: Node3D = demo.get_meta("sword")
	var ear_mark: Node3D = demo.get_meta("ear")
	ear_mark.scale = Vector3.ONE * (1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.012))
	if cyc < 0.8:
		hand.position = rest.lerp(ear, smoothstep(0.0, 0.8, cyc))
		sword.visible = false
	elif cyc < 1.3:
		hand.position = ear
		sword.visible = cyc > 1.1
	else:
		var u := smoothstep(1.3, 2.1, cyc)
		hand.position = ear.lerp(Vector3(0.35, -0.45, 0.35), u)
		hand.rotation.z = -1.4 * u
		sword.visible = true
	if cyc < 1.3:
		hand.rotation.z = 0.0


func _build_sword_demo() -> Node3D:
	var demo := Node3D.new()
	main.add_child(demo)
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(0.6, 0.9, 1.0, 0.25)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.3
	hm.radial_segments = 12
	hm.rings = 6
	head.mesh = hm
	head.material_override = ghost_mat
	demo.add_child(head)
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.17
	bm.height = 0.7
	bm.radial_segments = 10
	bm.rings = 4
	body.mesh = bm
	body.material_override = ghost_mat
	body.position = Vector3(0.0, -0.55, 0.0)
	demo.add_child(body)
	var ear := MeshInstance3D.new()  # a glowing dot beside the head: "put your hand here"
	var em := SphereMesh.new()
	em.radius = 0.035
	em.height = 0.07
	em.radial_segments = 8
	em.rings = 4
	ear.mesh = em
	ear.material_override = main.make_material(Color(1.0, 0.9, 0.3), 4.0)
	ear.position = Vector3(-0.2, 0.0, -0.05)
	demo.add_child(ear)
	var hand := Node3D.new()
	demo.add_child(hand)
	var palm := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.06
	pm.height = 0.12
	pm.radial_segments = 10
	pm.rings = 5
	palm.mesh = pm
	palm.material_override = main.make_material(color.lightened(0.4), 2.5)
	hand.add_child(palm)
	var sword := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.035, 0.6, 0.012)
	sword.mesh = sb
	sword.position = Vector3(0.0, 0.33, 0.0)
	sword.material_override = main.make_material(Color(0.6, 0.95, 1.0), 4.0)
	hand.add_child(sword)
	for n in [head, body, ear, palm, sword]:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	demo.set_meta("hand", hand)
	demo.set_meta("sword", sword)
	demo.set_meta("ear", ear)
	_set_layers(demo, viewmodel_layer())
	set_meta("sword_demo", demo)
	return demo
