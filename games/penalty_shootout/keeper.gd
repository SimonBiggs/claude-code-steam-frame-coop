extends Node3D
## Player 1: the GOALKEEPER.
## VR (Steam Frame): big padded gloves on both hands - touch the ball with either glove (or block it
## with your body / head) to save it. Left stick shuffles you around the goal mouth, and you can step
## physically too. Right stick left/right: snap turn. Right trigger or A: continue on the end screens.
## The keeper is auto-fitted on start (and again when a shorter / taller / seated kid takes over):
## the world is scaled so everyone can reach the crossbar.
## Flat (split screen / non-VR host): A-D / left stick / mouse shuffle, Space / A / left click / RB dives
## the way you are pushing (W or stick up = high), or flick the right stick to dive that way.
## On the TV machine it is a ghost: a keeper body posed from the host's head + glove positions.
## POWER-UPS: now and then a glowing bubble floats in front of the keeper's chest (never at the face)
## while a striker lines up - touch it with a glove (flat keeper: it is collected automatically) for
## BIG GLOVES, SLOW-MO or DOUBLE SAVE on the next shot.
## Replays (TV views) pose the body from a recording (replay_pose).

const GLOVE_R := 0.12  # visual glove radius (VR, metres before world scale)
const VR_FORGIVE := 0.05  # extra save radius in VR
const FLAT_GLOVE_R := 0.19
const MOVE_SPEED := 2.6
const FLAT_SPEED := 3.6
const FLAT_X := 3.1
const DIVE_TIME := 0.95
const KEEPER_Z := 0.35
const TARGET_HEAD := 1.7  # world-scaled head height we fit to
const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")
const BIG_GLOVES := 1.6
const POWER_NAMES := {"big": "BIG GLOVES", "slow": "SLOW-MO", "double": "DOUBLE SAVE"}
const POWER_COLORS := {"big": Color(0.3, 1.0, 0.5), "slow": Color(0.4, 0.75, 1.0), "double": Color(1.0, 0.8, 0.25)}

var index := 0
var main
var vr := false
var ghost := false
var remote := false
var active := true
var joy := -1
var key_set := 0
var color := Color(0.2, 1.0, 0.45)
var camera: Camera3D
var hud: Control
var hud_label: Label
var pad_lost_t := -1.0
var yaw := 0.0
var pitch := 0.0

var hand_l: XRController3D
var hand_r: XRController3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var gloves: Array[MeshInstance3D] = []
var glove_label: Label3D
var fit_t := 0.8
var fitted := false
var fit_real := 0.0
var refit_t := 0.0
var place_frames := 0
var snap_was := false
var a_was := false
var trig_block := false  # after unpausing: the trigger must be let go before it does anything

# Power-ups: power = active for the next shot, bubble = offered (floating in front of the keeper).
var power := ""
var bubble := ""
var bubble_pos := Vector3.ZERO
var bubble_t := 0.0
var bubble_node: Node3D
var bubble_mat: StandardMaterial3D
var bubble_label: Label3D
var cheer_t := 0.0
var replay_pose: Array = []  # [head, down, glove_l, glove_r] while a TV replay plays

# Flat keeper.
var kx := 0.0
var dive_t := -1.0
var dive_dir := Vector3.ZERO
var mouse_dx := 0.0
var dive_click := false
var dive_was := false
var flick_was := false

# Bot hooks (tests).
var bot := false
var bot_move := 0.0  # flat: world x direction to shuffle
var bot_dive := Vector3.ZERO  # flat: dive direction (set once to dive)
var bot_stick := Vector2.ZERO  # VR: left stick

# Body (flat keeper and the ghost on the TV machine).
var body: Node3D
var b_head: MeshInstance3D
var b_torso: MeshInstance3D
var b_legs: MeshInstance3D
var b_arms: Array[MeshInstance3D] = []
var b_gloves: Array[MeshInstance3D] = []

# Pose shared over the network (world space).
var head_pos := Vector3(0, 1.72, KEEPER_Z)
var down_dir := Vector3.DOWN
var glove_l := Vector3(0.42, 1.3, 0.6)
var glove_r := Vector3(-0.42, 1.3, 0.6)
var last_gl := Vector3.ZERO
var last_gr := Vector3.ZERO
var last_head := Vector3.ZERO
var net_head := Vector3(0, 1.72, KEEPER_Z)
var net_down := Vector3.DOWN
var net_gl := Vector3(0.42, 1.3, 0.6)
var net_gr := Vector3(-0.42, 1.3, 0.6)


func set_active(on: bool) -> void:
	active = on


func is_local() -> bool:
	return not ghost and not remote


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func ws() -> float:
	return xr_origin.world_scale if xr_origin != null else 1.0


# --- VR ----------------------------------------------------------------------------------

func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	cam.near = 0.03
	cam.cull_mask &= ~2  # never show the strikers' aim reticle to the keeper
	for h in [left, right]:
		var hh: XRController3D = h
		var g := MeshInstance3D.new()
		g.mesh = main.sphere_mesh(GLOVE_R)
		g.material_override = main.make_material(Color(1.0, 1.0, 1.0), 0.15)
		g.scale = Vector3(1.0, 1.15, 0.6)
		g.position = Vector3(0, 0, -0.02)  # forward of the wrist: net.gd's MENU button sits beside the left wrist
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hh.add_child(g)
		# Bright padded palm strip and a coloured cuff.
		var pad := MeshInstance3D.new()
		pad.mesh = main.box_mesh(Vector3(0.17, 0.05, 0.03))
		pad.material_override = main.make_material(color, 0.6)
		pad.position = Vector3(0, -0.03, -0.05)
		g.add_child(pad)
		if hh == right:
			var cuff := MeshInstance3D.new()
			cuff.mesh = main.cyl_mesh(0.065, 0.065, 0.08, 10)
			cuff.material_override = main.make_material(Color(0.1, 0.1, 0.12), 0.0)
			cuff.position = Vector3(0, 0, 0.17)
			cuff.rotation.x = PI * 0.5
			g.add_child(cuff)
		gloves.append(g)
	# Score on the back of the right glove: always in view when you look at your hands.
	glove_label = Label3D.new()
	glove_label.font_size = 40
	glove_label.pixel_size = 0.0007
	glove_label.outline_size = 12
	glove_label.modulate = Color(1.0, 0.95, 0.5)
	glove_label.position = Vector3(0, 0.11, 0.06)
	glove_label.rotation.x = deg_to_rad(-55.0)
	glove_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	gloves[1].add_child(glove_label)


func vr_trigger() -> bool:
	return vr and hand_r.get_float("trigger") > 0.6 and not trig_block


func vr_a() -> bool:
	return vr and hand_r.is_button_pressed("ax_button")


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
	elif vr:
		_vr_update(delta)
	else:
		_flat_update(delta)
	cheer_t = maxf(0.0, cheer_t - delta)
	if replay_pose.size() == 4 and body != null:
		_pose_body(replay_pose[0], replay_pose[1], replay_pose[2], replay_pose[3])
	_update_bubble(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)


# --- Power-ups -------------------------------------------------------------------------------

## Host / local: offer a power-up bubble in front of the keeper's chest.
func offer(kind: String) -> void:
	bubble = kind
	bubble_t = 0.0


func glove_scale() -> float:
	return BIG_GLOVES if power == "big" else 1.0


## Where the bubble floats: chest height, a little to one side, an arm's length towards the pitch.
func bubble_spot() -> Vector3:
	var w := ws()
	var side := 0.32 if int(main.shots_total) % 2 == 0 else -0.32
	return head_pos + Vector3(side, -0.48, 0.42) * w


func _update_bubble(delta: float) -> void:
	var show := bubble != ""
	if show and bubble_node == null:
		bubble_node = Node3D.new()
		bubble_node.top_level = true
		add_child(bubble_node)
		var mi := MeshInstance3D.new()
		mi.mesh = main.sphere_mesh(0.13)
		bubble_mat = StandardMaterial3D.new()
		bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = bubble_mat
		bubble_node.add_child(mi)
		var core := MeshInstance3D.new()
		core.mesh = main.sphere_mesh(0.05)
		core.material_override = main.make_material(Color(1, 1, 1), 2.0)
		bubble_node.add_child(core)
		bubble_label = Label3D.new()
		bubble_label.font_size = 40
		bubble_label.pixel_size = 0.0016
		bubble_label.outline_size = 12
		bubble_label.position = Vector3(0, 0.2, 0)
		bubble_node.add_child(bubble_label)
	if bubble_node == null:
		return
	bubble_node.visible = show
	if not show:
		return
	bubble_t += delta
	if is_local():
		bubble_pos = bubble_spot()
	var w := ws()
	bubble_node.global_position = bubble_pos + Vector3(0, 0.03 * sin(bubble_t * 3.0), 0) * w
	bubble_node.scale = Vector3.ONE * w * (1.0 + 0.08 * sin(bubble_t * 6.0))
	var c: Color = POWER_COLORS.get(bubble, Color.WHITE)
	bubble_mat.albedo_color = Color(c.r, c.g, c.b, 0.55)
	bubble_label.text = str(POWER_NAMES.get(bubble, ""))
	bubble_label.modulate = c.lightened(0.3)
	# Face the label towards the keeper (who looks down the pitch, +z).
	bubble_label.global_basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * w)
	if not is_local() or main.net.mode == "client":
		return
	# Touch it with a glove (VR), or it is taken automatically (flat keeper, after a moment).
	var got := false
	if vr:
		var r := 0.17 * w
		got = glove_l.distance_to(bubble_pos) < r or glove_r.distance_to(bubble_pos) < r
	else:
		got = bubble_t > 1.2
	if got:
		main.keeper_collect(bubble)


func _vr_update(delta: float) -> void:
	_fit(delta)
	var s := bot_stick if bot else hand_l.get_vector2("primary")
	var w := ws()
	if trig_block and hand_r.get_float("trigger") < 0.3:
		trig_block = false
	if s.length() > 0.2:
		var right := xr_origin.global_basis.x
		var fwd := -xr_origin.global_basis.z
		right.y = 0.0
		fwd.y = 0.0
		var mv := (right.normalized() * s.x + fwd.normalized() * s.y) * MOVE_SPEED * w * delta
		xr_origin.global_position += mv
	# Stay in and around the goal mouth.
	var head := xr_camera.global_position
	var cx := clampf(head.x, -4.2, 4.2)
	var cz := clampf(head.z, -1.4, 4.0)
	xr_origin.global_position += Vector3(cx - head.x, 0.0, cz - head.z)
	var r := Vector2.ZERO if bot else hand_r.get_vector2("primary")
	var snap := absf(r.x) > 0.7
	if snap and not snap_was:
		var h := xr_camera.global_position
		var rot := Basis(Vector3.UP, -signf(r.x) * deg_to_rad(30.0))
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, h + rot * (xr_origin.global_position - h))
	snap_was = snap
	var gs := glove_scale()
	for g in gloves:
		g.scale = g.scale.lerp(Vector3(1.0, 1.15, 0.6) * w * gs, 1.0 - exp(-10.0 * delta))
	head_pos = xr_camera.global_position
	down_dir = Vector3.DOWN
	glove_l = gloves[0].global_position
	glove_r = gloves[1].global_position
	global_position = Vector3(head_pos.x, 0.0, head_pos.z)
	if glove_label != null:
		glove_label.text = main.glove_text()


## Fit a moment after starting, and again when a different-height player takes the headset.
func _fit(delta: float) -> void:
	if place_frames > 0:
		place_frames -= 1
		if place_frames == 0:
			_place_in_goal()
		return
	var real := xr_camera.position.y / ws()
	if not fitted:
		fit_t -= delta
		if fit_t <= 0.0 and xr_camera.position != Vector3.ZERO:
			_do_fit()
		return
	if absf(real - fit_real) > 0.28:
		refit_t += delta
		if refit_t > 2.5:
			_do_fit()
	else:
		refit_t = 0.0


func _do_fit() -> void:
	fitted = true
	refit_t = 0.0
	var real := maxf(0.5, xr_camera.position.y / ws())
	fit_real = real
	xr_origin.world_scale = clampf(TARGET_HEAD / real, 1.0, 1.6)
	place_frames = 2  # the scaled head position shows up on the next frames
	print("VR: keeper fitted to head height %.2f m (world scale %.2f)" % [real, xr_origin.world_scale])


func _place_in_goal() -> void:
	var head := xr_camera.global_position
	var cam_yaw := xr_camera.global_rotation.y
	var rot := Basis(Vector3.UP, PI - cam_yaw)  # face the pitch (+z)
	xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
	head = xr_camera.global_position
	xr_origin.global_position += Vector3(-head.x, 0.0, KEEPER_Z + 0.15 - head.z)


func recenter() -> void:
	if vr and fitted:
		_place_in_goal()


# --- Flat --------------------------------------------------------------------------------

func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 68.0
	camera.cull_mask &= ~2
	_ensure_body()


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _input(event: InputEvent) -> void:
	if vr or ghost or key_set != 0:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_dx += mm.relative.x
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		dive_click = true


## Screen-space input (x right, y up) for the flat keeper.
func _flat_stick() -> Vector2:
	var s := Vector2.ZERO
	if key_set == 0:
		s = Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_W) - _key(KEY_S))
	if joy >= 0:
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), -Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() > 0.2:
			s += st
	return s.limit_length(1.0)


func _flat_update(delta: float) -> void:
	_ensure_body()
	var s := _flat_stick()
	# Camera looks down the pitch (+z), so screen-right is world -x.
	var move := -s.x
	if bot:
		move = bot_move
	if mouse_dx != 0.0:
		kx -= mouse_dx * 0.01
		mouse_dx = 0.0
	var want_dive := Vector3.ZERO
	var dive_btn := dive_click
	dive_click = false
	if key_set == 0 and Input.is_physical_key_pressed(KEY_SPACE):
		dive_btn = true
	if joy >= 0 and (Input.is_joy_button_pressed(joy, JOY_BUTTON_A) or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.6):
		dive_btn = true
	if dive_btn and not dive_was:
		want_dive = Vector3(-s.x, maxf(s.y, -0.4), 0.0)
		if want_dive.length() < 0.2:
			want_dive = Vector3(0, 1, 0)  # straight up
	dive_was = dive_btn
	if joy >= 0:
		var r := Vector2(Input.get_joy_axis(joy, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(joy, JOY_AXIS_RIGHT_Y))
		var flick := r.length() > 0.75
		if flick and not flick_was:
			want_dive = Vector3(-r.x, maxf(r.y, -0.4), 0.0)
		flick_was = flick
	if bot and bot_dive != Vector3.ZERO:
		want_dive = bot_dive
		bot_dive = Vector3.ZERO
	if want_dive != Vector3.ZERO and dive_t < 0.0 and main.keeper_can_move():
		dive_t = 0.0
		dive_dir = want_dive.normalized()
		main.sound("dive", -6.0)
	var e := 0.0
	if dive_t >= 0.0:
		dive_t += delta
		if dive_t < 0.25:
			e = smoothstep(0.0, 0.25, dive_t)
		elif dive_t < 0.6:
			e = 1.0
		else:
			e = 1.0 - smoothstep(0.6, DIVE_TIME, dive_t)
		if dive_t >= DIVE_TIME:
			dive_t = -1.0
	elif main.keeper_can_move():
		kx += move * FLAT_SPEED * delta
	kx = clampf(kx, -FLAT_X, FLAT_X)
	var base := Vector3(kx, 1.72, KEEPER_Z)
	var d := dive_dir
	var h := base + d * 1.45 * e
	h.y = clampf(h.y, 0.45, 2.45)
	var tilt := Vector3(-d.x, -0.3, 0.0).normalized()
	down_dir = Vector3.DOWN.lerp(tilt, e * absf(d.x)).normalized()
	var perp := Vector3(-d.y, d.x, 0.0)
	var idle_l := Vector3(0.42, -0.42, 0.25)
	var idle_r := Vector3(-0.42, -0.42, 0.25)
	var dive_l := d * 0.8 + perp * 0.22 + Vector3(0, 0, 0.1)
	var dive_r := d * 0.8 - perp * 0.22 + Vector3(0, 0, 0.1)
	head_pos = h
	glove_l = h + idle_l.lerp(dive_l, e)
	glove_r = h + idle_r.lerp(dive_r, e)
	if cheer_t > 0.0 and dive_t < 0.0:
		# Fist pump after a save.
		var pump := absf(sin(cheer_t * 9.0)) * 0.25
		glove_l = h + Vector3(0.3, 0.35 + pump, 0.15)
		glove_r = h + Vector3(-0.3, 0.35 + pump, 0.15)
	position = Vector3(kx, 0, KEEPER_Z)
	_pose_body(head_pos, down_dir, glove_l, glove_r)
	if camera != null and main.replay_on:
		camera.global_position = main.REPLAY_CAM
		camera.look_at(main.replay_look(), Vector3.UP)
	elif camera != null and main.state == "trophy":
		var ct: Array = main.ceremony_camera()
		camera.global_position = camera.global_position.lerp(ct[0], 1.0 - exp(-4.0 * delta))
		camera.look_at(ct[1], Vector3.UP)
	elif camera != null:
		var cp := Vector3(kx * 0.45, 2.3, -1.7)
		if not camera.has_meta("placed"):
			camera.set_meta("placed", true)
			camera.global_position = cp
		camera.global_position = camera.global_position.lerp(cp, 1.0 - exp(-6.0 * delta))
		camera.look_at(Vector3(kx * 0.25, 0.9, 11.0), Vector3.UP)
		var sh: float = main.shake
		if sh > 0.0:
			camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * sh * 0.15


func is_diving() -> bool:
	return dive_t >= 0.0


func action_pressed() -> bool:
	if vr:
		return vr_trigger() or vr_a()
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set == 0 and Input.is_physical_key_pressed(KEY_SPACE)


# --- Saving ------------------------------------------------------------------------------

## [pos, radius, velocity, kind] spheres the ball bounces off (sampled every physics tick).
func save_spheres(delta: float) -> Array:
	var out: Array = []
	var dt := maxf(delta, 0.001)
	var vl := (glove_l - last_gl) / dt if last_gl != Vector3.ZERO else Vector3.ZERO
	var vrr := (glove_r - last_gr) / dt if last_gr != Vector3.ZERO else Vector3.ZERO
	last_gl = glove_l
	last_gr = glove_r
	last_head = head_pos
	if vr:
		var w := ws()
		var gr := (GLOVE_R * w + VR_FORGIVE) * glove_scale()
		out.append([glove_l, gr, vl.limit_length(12.0), "left"])
		out.append([glove_r, gr, vrr.limit_length(12.0), "right"])
		out.append([head_pos, 0.12 * w, Vector3.ZERO, "head"])
		out.append([head_pos + Vector3(0, -0.45, 0) * w, 0.19 * w, Vector3.ZERO, "body"])
		var hip := head_pos + Vector3(0, -0.85, 0) * w
		if hip.y > 0.15:
			out.append([hip, 0.19 * w, Vector3.ZERO, "body"])
	else:
		out.append([glove_l, FLAT_GLOVE_R * glove_scale(), vl.limit_length(12.0), "left"])
		out.append([glove_r, FLAT_GLOVE_R * glove_scale(), vrr.limit_length(12.0), "right"])
		var bk := "dive" if is_diving() else "body"
		out.append([head_pos, 0.14, Vector3.ZERO, bk if is_diving() else "head"])
		out.append([head_pos + down_dir * 0.5, 0.24, Vector3.ZERO, bk])
		out.append([head_pos + down_dir * 1.15, 0.22, Vector3.ZERO, bk])
	return out


func haptic(kind: String) -> void:
	if vr:
		if kind != "right":
			hand_l.trigger_haptic_pulse("haptic", 0.0, 0.9, 0.2, 0.0)
		if kind != "left":
			hand_r.trigger_haptic_pulse("haptic", 0.0, 0.9, 0.2, 0.0)
	elif joy >= 0:
		Input.start_joy_vibration(joy, 0.6, 0.8, 0.25)


# --- Body ----------------------------------------------------------------------------------

func _ensure_body() -> void:
	if body != null:
		return
	body = Node3D.new()
	body.name = "KeeperBody"
	main.add_child(body)
	body.top_level = true
	var jersey := color
	var skin := Color(1.0, 0.8, 0.62)
	var dark := Color(0.1, 0.1, 0.12)
	var vm: StandardMaterial3D = MeshKit.vertex_material(main.mats)
	b_head = MeshInstance3D.new()
	b_head.mesh = MeshKit.merge([
		[MeshKit.sphere(0.13, 14), MeshKit.at(Vector3.ZERO), skin],
		[MeshKit.sphere(0.135, 12), MeshKit.at(Vector3(0, 0.05, 0), Vector3(1.0, 0.55, 1.0)), dark],
		[MeshKit.box(Vector3(0.2, 0.025, 0.12)), MeshKit.at(Vector3(0, 0.06, 0.12)), dark],
		[MeshKit.sphere(0.022, 6), MeshKit.at(Vector3(-0.045, 0.01, 0.115)), Color(1, 1, 1)],
		[MeshKit.sphere(0.022, 6), MeshKit.at(Vector3(0.045, 0.01, 0.115)), Color(1, 1, 1)],
		[MeshKit.sphere(0.011, 6), MeshKit.at(Vector3(-0.045, 0.01, 0.133)), Color(0.05, 0.05, 0.1)],
		[MeshKit.sphere(0.011, 6), MeshKit.at(Vector3(0.045, 0.01, 0.133)), Color(0.05, 0.05, 0.1)],
		[MeshKit.box(Vector3(0.06, 0.012, 0.01)), MeshKit.at(Vector3(0, -0.06, 0.12)), Color(0.6, 0.2, 0.2)],
	])
	b_head.material_override = vm
	body.add_child(b_head)
	b_torso = MeshInstance3D.new()
	b_torso.mesh = MeshKit.merge([
		[MeshKit.cyl(0.2, 0.22, 0.75, 12), MeshKit.at(Vector3.ZERO), jersey],
		[MeshKit.cyl(0.1, 0.12, 0.06, 10), MeshKit.at(Vector3(0, 0.38, 0)), jersey.darkened(0.4)],
		[MeshKit.box(Vector3(0.18, 0.2, 0.02)), MeshKit.at(Vector3(0, 0.05, 0.215)), Color(1, 1, 1)],
		[MeshKit.box(Vector3(0.03, 0.14, 0.022)), MeshKit.at(Vector3(0, 0.05, 0.22)), jersey.darkened(0.5)],
		[MeshKit.box(Vector3(0.46, 0.07, 0.44)), MeshKit.at(Vector3(0, -0.36, 0)), dark],
	])
	b_torso.material_override = vm
	body.add_child(b_torso)
	b_legs = MeshInstance3D.new()
	b_legs.mesh = MeshKit.merge([
		[MeshKit.box(Vector3(0.4, 0.3, 0.24)), MeshKit.at(Vector3(0, 0.25, 0)), dark],
		[MeshKit.box(Vector3(0.14, 0.5, 0.16)), MeshKit.at(Vector3(-0.1, -0.15, 0)), jersey.lightened(0.3)],
		[MeshKit.box(Vector3(0.14, 0.5, 0.16)), MeshKit.at(Vector3(0.1, -0.15, 0)), jersey.lightened(0.3)],
		[MeshKit.box(Vector3(0.15, 0.1, 0.26)), MeshKit.at(Vector3(-0.1, -0.42, 0.05)), Color(0.95, 0.95, 0.95)],
		[MeshKit.box(Vector3(0.15, 0.1, 0.26)), MeshKit.at(Vector3(0.1, -0.42, 0.05)), Color(0.95, 0.95, 0.95)],
	])
	b_legs.material_override = vm
	body.add_child(b_legs)
	var jersey_mat: StandardMaterial3D = main.make_material(color, 0.15)
	for i in 2:
		var arm := MeshInstance3D.new()
		arm.mesh = main.cyl_mesh(0.055, 0.055, 1.0, 8)
		arm.material_override = jersey_mat
		body.add_child(arm)
		b_arms.append(arm)
		var g := MeshInstance3D.new()
		g.mesh = main.sphere_mesh(0.15)
		g.material_override = main.make_material(Color(1.0, 1.0, 1.0), 0.3)
		g.scale = Vector3(1.0, 1.15, 0.7)
		body.add_child(g)
		b_gloves.append(g)


static func _basis_up(up: Vector3) -> Basis:
	var u := up.normalized()
	if u.dot(Vector3.UP) < -0.999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, u))


func _stretch(n: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := maxf(0.01, d.length())
	n.global_transform = Transform3D(_basis_up(d) * Basis.from_scale(Vector3(1.0, l, 1.0)), (a + b) * 0.5)


func _pose_body(h: Vector3, down: Vector3, gl: Vector3, gr: Vector3) -> void:
	if body == null:
		return
	var scale_k := clampf(h.y / 1.72, 0.6, 1.4) if down.y < -0.9 else 1.0
	var up := -down
	b_head.global_position = h
	b_torso.global_transform = Transform3D(_basis_up(up), h + down * 0.55 * scale_k)
	var legs_at := h + down * 1.2 * scale_k
	b_legs.global_transform = Transform3D(_basis_up(up), legs_at)
	var sh := h + down * 0.3 * scale_k
	_stretch(b_arms[0], sh + Vector3(0.18, 0, 0), gl)
	_stretch(b_arms[1], sh + Vector3(-0.18, 0, 0), gr)
	b_gloves[0].global_position = gl
	b_gloves[1].global_position = gr
	var gs := glove_scale()
	for g in b_gloves:
		g.scale = Vector3(1.0, 1.15, 0.7) * gs


## TV machine: pose the keeper body from the host's snapshot.
func _ghost_update(delta: float) -> void:
	_ensure_body()
	var k := 1.0 - exp(-18.0 * delta)
	head_pos = head_pos.lerp(net_head, k)
	down_dir = down_dir.lerp(net_down, k).normalized()
	glove_l = glove_l.lerp(net_gl, k)
	glove_r = glove_r.lerp(net_gr, k)
	_pose_body(head_pos, down_dir, glove_l, glove_r)
