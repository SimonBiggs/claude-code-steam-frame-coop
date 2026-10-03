extends Node3D
## Player 1: the angler on the jetty, with a fishing rod.
## VR (Steam Frame): the rod is in your RIGHT hand. FLICK it forward to cast (faster flick = further),
## or press A for an easy cast. Wait for the bobber to dip (you feel it), then REEL: hold the right
## trigger, or wind your LEFT hand in circles next to the reel. When the fish stops pulling, YANK the
## rod back (up / towards you) to haul it in. The tension meter on the rod shows how hard the line is
## pulling: red means ease off, or the line snaps. Left stick walks along the jetty and shore, right
## stick snap-turns. Everything is measured from the rod itself or from your head, never a rest pose.
## Flat (split screen / non-VR host): WASD / left stick walk, mouse / right stick aim, hold Space / LMB /
## A / RT to charge a cast and release, then hold it to reel; RMB / Shift / B / X yanks the rod back.
## On the TV machine this is a ghost drawn from the host's snapshots.

const Lake := preload("res://games/fishing_lake/lake.gd")
const FishScript := preload("res://games/fishing_lake/fish.gd")
const BUTT_LEN := 0.95
const TIP_LEN := 0.8
const BITE_WINDOW := 2.4
const SNAP_TIME := 1.3
const REEL_SPEED := 2.5
const MAX_LINE := 24.0
const CAST_SPEED := 3.5  # rod tip m/s forward needed for a flick cast
const RECAST_SPEED := 5.5  # a harder flick re-casts while the bobber is already out

var index := 0
var main
var vr := false
var fake_vr := false  # bot test: VR code path driven by plain Node3D "hands"
var ghost := false
var remote := false
var active := true
var joy := -1
var key_set := 0
var camera: Camera3D
var hud: Control
var hud_label: Label
var pad_lost_t := -1.0
var color := Color(1.0, 0.85, 0.55)
var yaw := 0.0

var xr_origin: Node3D
var xr_camera: Node3D
var hand_l: Node3D
var hand_r: Node3D
var fitted := false
var fit_t := 0.8
var fit_head := 0.0
var refit_t := 0.0
var turn_was := false
var vr_hands: Array[MeshInstance3D] = []

var body_pos := Vector3(0.0, Lake.DECK, Lake.JETTY_END_Z + 0.9)
var aim_yaw := 0.0
var avatar: Node3D
var rod_root: Node3D
var rod_bend: Node3D
var reel_crank: Node3D
var meter_fill: MeshInstance3D
var meter_mats: Array[StandardMaterial3D] = []
var rod_label: Label3D
var rod_pitch := 0.55
var rod_kick := 0.0
var bobber: Node3D
var line_mesh: ImmediateMesh
var line_inst: MeshInstance3D

# Fishing (simulated on the host / local game; mirrored on the TV machine).
var line_state := "ready"  # ready, flying, waiting, bite, fight, landing
var line_t := 0.0
var lure_pos := Vector3.ZERO
var lure_vel := Vector3.ZERO
var bob := 0.0
var nibbling := false
var tension := 0.0
var over_t := 0.0
var hooked = null
var fight_dist := 0.0
var fight_dir := Vector3.FORWARD
var surge := false
var phase_t := 0.0
var sway := 0.0
var wait_t := 0.0
var twitch_t := 0.0
var cast_cool := 0.0
var yank_cool := 0.0
var charge := 0.0
var charging := false
var hint := ""
var hint_col := Color.WHITE
var bend := 0.0
var haptic_t := 0.0
var casts := 0
var catches := 0
var snaps := 0

# Per-frame input.
var reel := 0.0
var yank := false
var cast_req := false
var cast_dir := Vector3.FORWARD
var cast_dist := 10.0
var a_was := false
var yank_btn_was := false
var mouse_dx := 0.0
var last_tip_local := Vector3.ZERO
var has_last_tip := false
var tip_vel := Vector3.ZERO
var crank := 0.0
var crank_speed := 0.0
var crank_on := false
var last_crank_ang := 0.0
var crank_rel := Vector3.ZERO
var reel_spin := 0.0

# Bot hooks.
var bot := false
var bot_cast_dist := 0.0
var bot_cast_dir := Vector3.FORWARD
var bot_reel := 0.0
var bot_yank := false
var fake_trigger := 0.0
var fake_a := false

# Ghost (TV machine).
var net_body := Vector3.ZERO
var net_yaw := 0.0
var net_head := Transform3D()
var net_rod := Transform3D()
var net_vr := false
var net_lure := Vector3.ZERO


func _ready() -> void:
	_build_avatar()
	_build_tackle()
	lure_pos = body_pos + Vector3(0, 1.0, -1.5)


func set_active(on: bool) -> void:
	active = on


func is_local() -> bool:
	return not ghost and not remote


func vr_like() -> bool:
	return vr or fake_vr


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


# --- Building ------------------------------------------------------------------------

func _build_avatar() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	var b := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 1.1
	cap.radial_segments = 12
	cap.rings = 2
	b.mesh = cap
	b.material_override = main.make_material(Color(0.25, 0.5, 0.75), 0.0)
	b.position = Vector3(0, 0.55, 0)
	avatar.add_child(b)
	var vest := MeshInstance3D.new()
	vest.mesh = main.box_mesh(Vector3(0.46, 0.4, 0.3))
	vest.material_override = main.make_material(Color(0.4, 0.55, 0.3), 0.0)
	vest.position = Vector3(0, 0.8, 0)
	avatar.add_child(vest)
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = main.sphere_mesh(0.17)
	head.material_override = main.make_material(Color(1.0, 0.82, 0.65), 0.0)
	head.position = Vector3(0, 1.32, 0)
	avatar.add_child(head)
	var hat := MeshInstance3D.new()
	hat.mesh = main.cyl_mesh(0.14, 0.3, 0.14, 12)
	hat.material_override = main.make_material(Color(0.9, 0.8, 0.45), 0.0)
	hat.position = Vector3(0, 0.15, 0)
	head.add_child(hat)


func _build_rod(parent: Node3D) -> void:
	if rod_root != null:
		rod_root.queue_free()
	rod_root = Node3D.new()
	parent.add_child(rod_root)
	var cork: StandardMaterial3D = main.make_material(Color(0.75, 0.55, 0.35), 0.0)
	var blank: StandardMaterial3D = main.make_material(Color(0.15, 0.3, 0.6), 0.15)
	var grip := MeshInstance3D.new()
	grip.mesh = main.cyl_mesh(0.02, 0.022, 0.34, 8)
	grip.material_override = cork
	grip.rotation.x = deg_to_rad(90.0)
	grip.position = Vector3(0, 0, -0.03)
	rod_root.add_child(grip)
	var butt := MeshInstance3D.new()
	butt.mesh = main.cyl_mesh(0.008, 0.013, BUTT_LEN, 6)
	butt.material_override = blank
	butt.rotation.x = deg_to_rad(90.0)
	butt.position = Vector3(0, 0, -0.2 - BUTT_LEN * 0.5)
	rod_root.add_child(butt)
	rod_bend = Node3D.new()
	rod_bend.position = Vector3(0, 0, -0.2 - BUTT_LEN)
	rod_root.add_child(rod_bend)
	var tipm := MeshInstance3D.new()
	tipm.mesh = main.cyl_mesh(0.003, 0.008, TIP_LEN, 6)
	tipm.material_override = blank
	tipm.rotation.x = deg_to_rad(90.0)
	tipm.position = Vector3(0, 0, -TIP_LEN * 0.5)
	rod_bend.add_child(tipm)
	var tip_ball := MeshInstance3D.new()
	tip_ball.mesh = main.sphere_mesh(0.012)
	tip_ball.material_override = main.make_material(Color(1.0, 0.3, 0.2), 1.0)
	tip_ball.position = Vector3(0, 0, -TIP_LEN)
	rod_bend.add_child(tip_ball)
	# The reel under the grip, with a crank that spins as you reel.
	var reel_body := MeshInstance3D.new()
	reel_body.mesh = main.cyl_mesh(0.04, 0.04, 0.035, 12)
	reel_body.material_override = main.make_material(Color(0.75, 0.75, 0.8), 0.1)
	reel_body.rotation.z = deg_to_rad(90.0)
	reel_body.position = Vector3(0, -0.055, -0.08)
	rod_root.add_child(reel_body)
	reel_crank = Node3D.new()
	reel_crank.position = Vector3(-0.025, -0.055, -0.08)
	rod_root.add_child(reel_crank)
	var arm := MeshInstance3D.new()
	arm.mesh = main.box_mesh(Vector3(0.008, 0.07, 0.012))
	arm.material_override = main.make_material(Color(0.6, 0.6, 0.65), 0.0)
	arm.position = Vector3(0, 0.035, 0)
	reel_crank.add_child(arm)
	var knob := MeshInstance3D.new()
	knob.mesh = main.sphere_mesh(0.014)
	knob.material_override = main.make_material(Color(1.0, 0.85, 0.2), 0.3)
	knob.position = Vector3(-0.012, 0.07, 0)
	reel_crank.add_child(knob)
	# Tension meter along the top of the rod: always in view while you fish.
	var meter_bg := MeshInstance3D.new()
	meter_bg.mesh = main.box_mesh(Vector3(0.022, 0.012, 0.34))
	meter_bg.material_override = main.make_material(Color(0.1, 0.1, 0.12), 0.0)
	meter_bg.position = Vector3(0, 0.026, -0.42)
	rod_root.add_child(meter_bg)
	meter_fill = MeshInstance3D.new()
	meter_fill.mesh = main.box_mesh(Vector3(0.026, 0.014, 0.34))
	meter_fill.position = Vector3(0, 0.03, -0.42)
	rod_root.add_child(meter_fill)
	meter_mats.clear()
	for c in [Color(0.3, 1.0, 0.4), Color(1.0, 0.85, 0.2), Color(1.0, 0.25, 0.2)]:
		var cc: Color = c
		var m := StandardMaterial3D.new()
		m.albedo_color = cc
		m.emission_enabled = true
		m.emission = cc
		m.emission_energy_multiplier = 1.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		meter_mats.append(m)
	meter_fill.material_override = meter_mats[0]
	rod_label = Label3D.new()
	rod_label.font_size = 44
	rod_label.pixel_size = 0.0011
	rod_label.outline_size = 14
	rod_label.width = 520.0
	rod_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rod_label.position = Vector3(0, 0.1, -0.5)
	rod_label.rotation.x = deg_to_rad(-50.0)
	rod_root.add_child(rod_label)
	rod_label.visible = vr_like()


func _build_tackle() -> void:
	bobber = Node3D.new()
	bobber.top_level = true
	add_child(bobber)
	var top := MeshInstance3D.new()
	top.mesh = main.sphere_mesh(0.07)
	top.material_override = main.make_material(Color(1.0, 0.15, 0.1), 0.5)
	top.position = Vector3(0, 0.03, 0)
	bobber.add_child(top)
	var bottom := MeshInstance3D.new()
	bottom.mesh = main.sphere_mesh(0.065)
	bottom.material_override = main.make_material(Color(1.0, 1.0, 1.0), 0.2)
	bottom.position = Vector3(0, -0.035, 0)
	bobber.add_child(bottom)
	var stick := MeshInstance3D.new()
	stick.mesh = main.cyl_mesh(0.008, 0.008, 0.12, 6)
	stick.material_override = top.material_override
	stick.position = Vector3(0, 0.12, 0)
	bobber.add_child(stick)
	line_mesh = ImmediateMesh.new()
	line_inst = MeshInstance3D.new()
	line_inst.mesh = line_mesh
	line_inst.top_level = true
	line_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.95, 0.95, 1.0)
	line_inst.material_override = lm
	add_child(line_inst)
	_build_rod(avatar)
	rod_root.position = Vector3(0.3, 1.0, -0.2)


# --- VR ------------------------------------------------------------------------------

func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	cam.near = 0.03
	_attach_hands(origin, cam, left, right)


## Bot test: the same VR code, driven by plain nodes the bot moves around.
func attach_fake_vr() -> void:
	fake_vr = true
	var origin := Node3D.new()
	main.add_child(origin)
	var cam := Node3D.new()
	origin.add_child(cam)
	cam.position = Vector3(0, 1.5, 0)
	var left := Node3D.new()
	origin.add_child(left)
	left.position = Vector3(-0.25, 1.1, -0.3)
	var right := Node3D.new()
	origin.add_child(right)
	right.position = Vector3(0.25, 1.1, -0.3)
	_attach_hands(origin, cam, left, right)


func _attach_hands(origin: Node3D, cam: Node3D, left: Node3D, right: Node3D) -> void:
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	origin.global_position = Vector3(0.0, Lake.DECK, Lake.JETTY_END_Z + 0.9)
	avatar.visible = false
	_build_rod(right)
	rod_root.rotation.x = deg_to_rad(20.0)  # rod points along the aim, tilted up a little
	for h in [left]:
		var hh: Node3D = h
		var mitten := MeshInstance3D.new()
		mitten.mesh = main.sphere_mesh(0.035)
		mitten.material_override = main.make_material(Color(1.0, 0.85, 0.55), 0.1)
		mitten.scale = Vector3(0.9, 0.7, 1.25)
		mitten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hh.add_child(mitten)
		vr_hands.append(mitten)


func _trigger() -> float:
	if vr:
		return (hand_r as XRController3D).get_float("trigger")
	return fake_trigger


func _a_button() -> bool:
	if vr:
		return (hand_r as XRController3D).is_button_pressed("ax_button")
	return fake_a


func vr_trigger() -> bool:
	return vr_like() and _trigger() > 0.6


func haptic(amp: float, dur: float) -> void:
	if vr:
		(hand_r as XRController3D).trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)
	elif joy >= 0:
		Input.start_joy_vibration(joy, amp * 0.6, amp, dur)


func _fit(delta: float) -> void:
	if fake_vr:
		fitted = true
		return
	var head_local := xr_camera.position
	if not fitted:
		fit_t -= delta
		if fit_t <= 0.0 and head_local != Vector3.ZERO:
			_do_fit(true)
		return
	if absf(head_local.y - fit_head) > 0.25:
		refit_t += delta
		if refit_t > 2.5:
			_do_fit(false)
	else:
		refit_t = 0.0


## Stand at the end of the jetty facing the lake; a sitting or short player is lifted a bit so they
## can see over the jetty edge. Re-run (height only) when the headset is handed to someone else.
func _do_fit(recenter: bool) -> void:
	fitted = true
	refit_t = 0.0
	var head_local := xr_camera.position
	fit_head = head_local.y
	var lift := clampf(1.45 - head_local.y, 0.0, 0.5)
	if recenter:
		var head := xr_camera.global_position
		var rot := Basis(Vector3.UP, -xr_camera.global_rotation.y)
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
		head = xr_camera.global_position
		xr_origin.global_position += Vector3(-head.x, 0.0, Lake.JETTY_END_Z + 0.9 - head.z)
	xr_origin.global_position.y = Lake.DECK + lift
	print("VR: fitted to head height %.2f m (lift %.2f m)" % [head_local.y, lift])


func _vr_move(delta: float) -> void:
	if fake_vr:
		return
	var hl := hand_l as XRController3D
	var hr := hand_r as XRController3D
	var s := hl.get_vector2("primary")
	if s.length() > 0.2:
		var f := -xr_camera.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		xr_origin.global_position += (f * s.y + r * s.x) * 1.6 * delta
	var rs := hr.get_vector2("primary")
	var turn := absf(rs.x) > 0.6
	if turn and not turn_was:
		var head := xr_camera.global_position
		var rot := Basis(Vector3.UP, -signf(rs.x) * deg_to_rad(30.0))
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
	turn_was = turn
	# Keep the head over the jetty or the shore (also if they physically walk off the end).
	var hp := xr_camera.global_position
	var ok := walk_clamp(hp)
	xr_origin.global_position += Vector3(ok.x - hp.x, 0.0, ok.z - hp.z)


## Nearest point on the jetty or the strip of shore behind it.
static func walk_clamp(p: Vector3) -> Vector3:
	var j := Vector3(clampf(p.x, -Lake.JETTY_HALF, Lake.JETTY_HALF), p.y, clampf(p.z, Lake.JETTY_END_Z + 0.25, Lake.SHORE_Z + 1.0))
	var s := Vector3(clampf(p.x, -12.0, 12.0), p.y, clampf(p.z, Lake.SHORE_Z, Lake.SHORE_Z + 4.5))
	return j if p.distance_squared_to(j) <= p.distance_squared_to(s) else s


func tip_pos() -> Vector3:
	if rod_bend == null:
		return body_pos + Vector3(0, 1.5, -1.5)
	return rod_bend.to_global(Vector3(0, 0, -TIP_LEN))


func reel_world() -> Vector3:
	return rod_root.to_global(Vector3(0, -0.055, -0.08))


func _rod_forward_flat() -> Vector3:
	var f := -rod_root.global_basis.z
	f.y = 0.0
	if f.length() < 0.15 and xr_camera != null:
		f = -xr_camera.global_basis.z
		f.y = 0.0
	if f.length() < 0.01:
		f = Vector3.FORWARD
	return f.normalized()


func _vr_input(delta: float) -> void:
	var tip := tip_pos()
	var tl := xr_origin.to_local(tip)
	if has_last_tip and delta > 0.0:
		var v: Vector3 = xr_origin.global_basis * ((tl - last_tip_local) / delta)
		tip_vel = tip_vel.lerp(v, 0.6)
	last_tip_local = tl
	has_last_tip = true
	var fh := _rod_forward_flat()
	var vh := Vector3(tip_vel.x, 0.0, tip_vel.z)
	var fwd_speed := vh.dot(fh)
	var can_cast := line_state == "ready" or (line_state == "waiting" and not nibbling)
	var need := CAST_SPEED if line_state == "ready" else RECAST_SPEED
	if can_cast and cast_cool <= 0.0 and fwd_speed > need and tip_vel.y < 2.5:
		cast_req = true
		cast_dir = (vh.normalized() * 0.5 + fh * 0.5).normalized()
		cast_dist = clampf(5.0 + (fwd_speed - CAST_SPEED) * 2.2, 5.0, 19.0)
	var a := _a_button()
	if a and not a_was and can_cast and cast_cool <= 0.0 and main.state != "over":
		cast_req = true
		cast_dir = fh
		cast_dist = 10.0
	a_was = a
	var back := (Vector3.UP * 0.8 - fh * 0.6).normalized()
	if tip_vel.dot(back) > 2.6 and yank_cool <= 0.0:
		yank = true
	# Winding the reel: the left hand going round near the reel (any circle, measured on the rod).
	var rel := hand_l.global_position - reel_world()
	var bx := rod_root.global_basis
	if rel.length() < 0.3:
		crank_rel = crank_rel.lerp(rel, 0.5)
		var py := crank_rel.dot(bx.y.normalized())
		var pz := crank_rel.dot(bx.z.normalized())
		var px := crank_rel.dot(bx.x.normalized())
		var r2 := Vector2(py, pz)
		if r2.length() < 0.035:
			r2 = Vector2(px, pz)  # circling in the other plane counts too
		if r2.length() > 0.035:
			var ang := atan2(r2.x, r2.y)
			if crank_on and delta > 0.0:
				var da := absf(wrapf(ang - last_crank_ang, -PI, PI))
				crank_speed = lerpf(crank_speed, da / delta, 0.25)
			last_crank_ang = ang
			crank_on = true
		else:
			crank_on = false
	else:
		crank_on = false
		crank_rel = rel
	if not crank_on:
		crank_speed = lerpf(crank_speed, 0.0, 1.0 - exp(-6.0 * delta))
	crank = clampf((crank_speed - 1.5) / 6.0, 0.0, 1.0)
	reel = maxf(_trigger(), crank)
	if reel < 0.08:
		reel = 0.0
	var head := xr_camera.global_position
	body_pos = Vector3(head.x, Lake.DECK, head.z)
	yaw = xr_camera.global_rotation.y
	aim_yaw = yaw


# --- Flat ----------------------------------------------------------------------------

func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 70.0
	camera.far = 300.0


func _input(event: InputEvent) -> void:
	if vr or ghost or key_set != 0:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_dx += mm.relative.x


func _key(kk: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(kk) else 0.0


func _flat_input(delta: float) -> void:
	var mv := Vector2.ZERO
	var turn := 0.0
	var btn := false
	var rt := 0.0
	var yank_btn := false
	if key_set == 0:
		mv = Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
		btn = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		yank_btn = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if not main.has_local_boat_arrows():
			mv += Vector2(_key(KEY_RIGHT) - _key(KEY_LEFT), _key(KEY_DOWN) - _key(KEY_UP))
	if joy >= 0:
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() > 0.18:
			mv += st
		var rx := Input.get_joy_axis(joy, JOY_AXIS_RIGHT_X)
		if absf(rx) > 0.2:
			turn += rx
		btn = btn or Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
		rt = Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT)
		yank_btn = yank_btn or Input.is_joy_button_pressed(joy, JOY_BUTTON_B) or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(joy, JOY_AXIS_RIGHT_Y) > 0.75
	aim_yaw -= mouse_dx * 0.004 + turn * 2.0 * delta
	mouse_dx = 0.0
	mv = mv.limit_length(1.0)
	body_pos += Basis(Vector3.UP, aim_yaw) * Vector3(mv.x, 0.0, mv.y) * 2.2 * delta
	body_pos = walk_clamp(body_pos)
	body_pos.y = Lake.DECK
	if bot:
		btn = false
		rt = 0.0
		yank_btn = bot_yank
		bot_yank = false
		if bot_cast_dist > 0.0 and (line_state == "ready") and cast_cool <= 0.0:
			cast_req = true
			cast_dir = bot_cast_dir
			cast_dist = bot_cast_dist
			bot_cast_dist = 0.0
			var d := Vector3(bot_cast_dir.x, 0.0, bot_cast_dir.z)
			if d.length() > 0.01:
				aim_yaw = atan2(-d.x, -d.z)
		reel = bot_reel
	if line_state == "ready" and main.state != "over":
		if btn or rt > 0.5:
			charging = true
			charge = minf(1.0, charge + delta / 1.1)
		elif charging:
			charging = false
			cast_req = true
			cast_dir = Basis(Vector3.UP, aim_yaw) * Vector3(0, 0, -1)
			cast_dist = 5.0 + 14.0 * charge
			charge = 0.0
	else:
		charging = false
		charge = 0.0
		if not bot:
			reel = maxf(1.0 if btn else 0.0, rt)
	if yank_btn and not yank_btn_was:
		yank = true
	yank_btn_was = yank_btn
	yaw = aim_yaw


func _flat_rod(delta: float) -> void:
	avatar.position = body_pos
	avatar.rotation.y = aim_yaw
	var want := 0.55
	if charging:
		want = 0.55 + charge * 1.0
	elif line_state == "fight" or line_state == "bite":
		want = 0.8
	elif line_state == "flying":
		want = 0.15
	rod_kick = maxf(0.0, rod_kick - delta * 2.5)
	rod_pitch = lerpf(rod_pitch, want + rod_kick, 1.0 - exp(-10.0 * delta))
	rod_root.rotation.x = rod_pitch
	if camera != null:
		var b := Basis(Vector3.UP, aim_yaw)
		var want_pos := body_pos + b * Vector3(0.9, 2.3, 3.4)
		var look := body_pos + b * Vector3(0.0, 0.3, -9.0)
		if line_state == "fight" or line_state == "waiting" or line_state == "bite":
			look = look.lerp(lure_pos, 0.5)
		if not camera.has_meta("placed"):
			camera.set_meta("placed", true)
			camera.global_position = want_pos
		camera.global_position = camera.global_position.lerp(want_pos, 1.0 - exp(-8.0 * delta))
		camera.look_at(look, Vector3.UP)


# --- Fishing simulation (host / local) ------------------------------------------------

func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
		_update_visuals(delta)
		return
	cast_req = false
	yank = false
	if vr_like():
		if vr and xr_origin.get("world_scale") != null and (xr_origin as XROrigin3D).world_scale != 1.0:
			(xr_origin as XROrigin3D).world_scale = 1.0
		_fit(delta)
		_vr_move(delta)
		_vr_input(delta)
		if fake_vr and camera != null:
			camera.global_transform = xr_camera.global_transform
	else:
		_flat_input(delta)
		_flat_rod(delta)
	if yank:
		yank_cool = 0.6
		rod_kick = 0.6
	yank_cool = maxf(0.0, yank_cool - delta)
	cast_cool = maxf(0.0, cast_cool - delta)
	twitch_t = maxf(0.0, twitch_t - delta)
	if main.state == "over" or main.net.mode == "client":
		cast_req = false
	_fish(delta)
	_update_visuals(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)


func anchor() -> Vector3:
	var tip := tip_pos()
	return Vector3(tip.x, 0.0, tip.z)


func _fish(delta: float) -> void:
	line_t += delta
	var tip := tip_pos()
	if cast_req and (line_state == "ready" or (line_state == "waiting" and not nibbling)):
		_launch(tip, cast_dir, cast_dist)
	match line_state:
		"ready":
			var hang := tip + Vector3(0, -0.4, 0)
			lure_pos = lure_pos.lerp(hang, 1.0 - exp(-12.0 * delta))
			if lure_pos.distance_to(hang) > 1.5:
				lure_pos = hang
			bob = 0.0
		"flying":
			lure_vel.y -= 9.8 * delta
			lure_pos += lure_vel * delta
			if lure_pos.y <= 0.0:
				lure_pos.y = 0.0
				if main.is_water(lure_pos):
					_set_line("waiting")
					wait_t = 0.0
					nibbling = false
					main.on_lure_plop(lure_pos)
				else:
					_set_line("ready")
					cast_cool = 0.4
					main.on_lure_missed(lure_pos)
		"waiting":
			wait_t += delta
			if reel > 0.05:
				var to := anchor() - lure_pos
				to.y = 0.0
				var step := reel * REEL_SPEED * 0.8 * delta
				if to.length() < 1.2 or not main.is_water(lure_pos + to.normalized() * step):
					_set_line("ready")
					cast_cool = 0.3
					main.on_reeled_in()
				else:
					lure_pos += to.normalized() * step
					twitch_t = 2.0
					wait_t = maxf(0.0, wait_t - delta * 0.5)
			bob = 0.3 * maxf(0.0, sin(line_t * 9.0)) if nibbling else 0.0
			lure_pos.y = 0.0
		"bite":
			bob = 1.0
			if reel > 0.3 or yank:
				_hook()
			elif line_t > BITE_WINDOW:
				_set_line("waiting")
				nibbling = false
				wait_t = 0.0
				if hooked != null:
					var f = hooked
					hooked = null
					f.scare(lure_pos, -1)
					if f.is_junk():
						main.release_fish(f)
				main.on_bite_missed(lure_pos)
		"fight":
			_fight(delta)
		"landing":
			if hooked != null:
				hooked.global_position = tip + Vector3(0, -0.45, 0)
				hooked.rotation = Vector3(deg_to_rad(90.0), line_t * 2.0, 0.0)
			lure_pos = tip + Vector3(0, -0.3, 0)
			tension = maxf(0.0, tension - delta * 2.0)
			if line_t > 2.2:
				if hooked != null:
					main.release_fish(hooked)
					hooked = null
				_set_line("ready")
				cast_cool = 0.5
	if line_state != "fight":
		tension = maxf(0.0, tension - delta * 1.5)
		over_t = 0.0
	if line_state == "fight" or line_state == "landing":
		bend = lerpf(bend, tension, 1.0 - exp(-8.0 * delta))
	else:
		bend = lerpf(bend, 0.3 if line_state == "bite" else 0.0, 1.0 - exp(-8.0 * delta))
	_haptics(delta)
	_update_hint()


func _set_line(s: String) -> void:
	line_state = s
	line_t = 0.0


func _launch(from: Vector3, dir: Vector3, dist: float) -> void:
	if line_state == "waiting":
		main.on_recast()
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var flight := 0.7 + dist * 0.045
	lure_pos = from
	lure_vel = dir * (dist / flight) + Vector3(0.0, (0.5 * 9.8 * flight * flight - from.y) / flight, 0.0)
	_set_line("flying")
	nibbling = false
	casts += 1
	rod_kick = 0.0
	main.on_cast(from, dist)


## Called by main when a fish (or junk) bites the lure.
func on_bite(f) -> void:
	if line_state != "waiting":
		f.set_state("swim")
		return
	hooked = f
	nibbling = false
	_set_line("bite")
	haptic(0.9, 0.35)


func on_nibble() -> void:
	nibbling = true
	haptic(0.25, 0.06)


func _hook() -> void:
	if hooked == null:
		_set_line("waiting")
		return
	_set_line("fight")
	hooked.set_state("hooked")
	var a := anchor()
	fight_dir = Vector3(lure_pos.x - a.x, 0.0, lure_pos.z - a.z)
	fight_dist = fight_dir.length()
	fight_dir = fight_dir.normalized() if fight_dist > 0.01 else Vector3.FORWARD
	surge = true
	phase_t = 0.6
	sway = 0.0
	tension = 0.35
	over_t = 0.0
	haptic(0.8, 0.2)
	main.on_hooked(hooked)


func _fight(delta: float) -> void:
	if hooked == null or hooked.kind < 0:
		_set_line("ready")
		hooked = null
		return
	var d: Dictionary = hooked.info()
	var pull: float = d["pull"]
	var junk: bool = hooked.is_junk()
	phase_t -= delta
	if phase_t <= 0.0:
		if junk:
			surge = false
			phase_t = 99.0
		else:
			surge = not surge
			if surge:
				phase_t = randf_range(0.7, 1.4) * (0.6 + pull)
				main.on_fish_surge(lure_pos, hooked)
			else:
				phase_t = randf_range(1.4, 2.6)
				main.on_fish_tired(hooked)
				haptic(0.4, 0.1)
	var heavy := 0.55 if hooked.kind == FishScript.CHEST else 1.0
	var reel_in := reel * REEL_SPEED * (0.35 if surge else 1.0) * heavy
	var out := pull * 1.5 if surge else 0.0
	fight_dist = clampf(fight_dist + (out - reel_in) * delta, 0.0, MAX_LINE)
	sway += delta * (2.4 if surge else 0.7)
	var lateral := sin(sway) * 0.35 * pull
	var tt := pull * (0.62 if surge else 0.12) + reel * (0.55 if surge else 0.18)
	if fight_dist >= MAX_LINE - 0.1 and surge:
		tt += 0.35
	tension = move_toward(tension, tt, 1.6 * delta)
	if yank:
		if surge:
			tension += 0.3
			main.on_yank(lure_pos, false)
		else:
			fight_dist = maxf(0.0, fight_dist - (1.6 + (1.0 - pull)))
			main.on_yank(lure_pos, true)
	if tension > 1.0:
		over_t += delta
		if over_t > SNAP_TIME:
			_snap()
			return
	else:
		over_t = maxf(0.0, over_t - delta * 0.5)
	var a := anchor()
	lure_pos = a + Basis(Vector3.UP, lateral) * fight_dir * fight_dist
	lure_pos.y = 0.0
	if not main.is_water(lure_pos) and fight_dist > 1.5:
		fight_dist = maxf(0.0, fight_dist - 2.0 * delta)
	hooked.global_position = lure_pos + Vector3(0, -0.18 if not junk else -0.1, 0)
	var face := a - lure_pos
	if surge:
		face = -face
	hooked.rotation = Vector3(0.0, atan2(face.x, face.z), 0.0)
	if fight_dist < 1.3:
		_land()


func _snap() -> void:
	var f = hooked
	hooked = null
	snaps += 1
	_set_line("ready")
	cast_cool = 0.8
	tension = 0.0
	over_t = 0.0
	haptic(1.0, 0.25)
	main.on_line_snap(lure_pos, f)
	if f != null:
		if f.is_junk():
			main.release_fish(f)
		else:
			f.scare(lure_pos + (anchor() - lure_pos).normalized(), -1)


func _land() -> void:
	_set_line("landing")
	catches += 1
	hooked.set_state("landed")
	haptic(0.7, 0.3)
	main.on_catch(hooked)


func _haptics(delta: float) -> void:
	haptic_t -= delta
	if haptic_t > 0.0:
		return
	haptic_t = 0.12
	if line_state == "fight":
		var amp := clampf(tension * 0.6 + (0.25 if over_t > 0.0 else 0.0), 0.05, 1.0)
		haptic(amp, 0.08)
	elif line_state == "bite":
		haptic(0.6, 0.1)


func _update_hint() -> void:
	hint_col = Color(1.0, 1.0, 1.0)
	var flat := not vr_like()
	match line_state:
		"ready":
			if flat:
				hint = "Hold Space / A to swing back, let go to CAST" if charge <= 0.0 else "Power %d%% - let go to cast!" % int(charge * 100.0)
			else:
				hint = "FLICK the rod forward to CAST\n(or press A)"
			hint_col = Color(0.7, 1.0, 1.0)
		"flying":
			hint = "Wheee!"
		"waiting":
			if nibbling:
				hint = "Something's nibbling... get ready!"
				hint_col = Color(1.0, 0.9, 0.4)
			else:
				hint = "Wait for a bite...\n%s reels in" % ("Hold Space / A" if flat else "Trigger / winding")
		"bite":
			hint = "BITE! %s!" % ("REEL (Space / A)" if flat else "PULL BACK or REEL")
			hint_col = Color(1.0, 0.5, 0.3)
		"fight":
			if tension > 0.85:
				hint = "EASE OFF! The line will snap!"
				hint_col = Color(1.0, 0.3, 0.25)
			elif surge:
				hint = "It's pulling - let it run!"
				hint_col = Color(1.0, 0.85, 0.3)
			else:
				hint = "REEL! And %s now!" % ("YANK (Shift / B)" if flat else "PULL BACK")
				hint_col = Color(0.4, 1.0, 0.5)
		"landing":
			hint = "GOT IT!"
			hint_col = Color(1.0, 0.9, 0.3)


# --- Visuals (both machines) ------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	if rod_bend != null:
		rod_bend.rotation.x = -bend * 0.6
	if meter_fill != null:
		var tv := clampf(tension, 0.0, 1.2)
		meter_fill.visible = line_state == "fight" or tv > 0.05
		meter_fill.scale = Vector3(1.0, 1.0, maxf(0.02, tv / 1.2))
		meter_fill.position = Vector3(0, 0.03, -0.25 - 0.17 * meter_fill.scale.z)
		meter_fill.material_override = meter_mats[0 if tv < 0.6 else (1 if tv < 0.88 else 2)]
	var spin := reel
	if ghost:
		spin = 1.0 if line_state == "fight" and not surge else 0.0
	reel_spin += spin * delta * 14.0
	if reel_crank != null:
		reel_crank.rotation.x = -reel_spin
	if rod_label != null:
		rod_label.visible = vr_like() and not ghost
		rod_label.text = hint
		rod_label.modulate = hint_col
	# Bobber and line.
	var t := Time.get_ticks_msec() / 1000.0
	var wave := sin(t * 2.0 + lure_pos.x) * 0.02
	bobber.visible = line_state != "landing"
	var bp := lure_pos
	if line_state == "waiting" or line_state == "bite" or line_state == "fight":
		bp.y = wave - bob * 0.14
	bobber.global_position = bp
	var tip := tip_pos()
	line_mesh.clear_surfaces()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var sag := 0.0
	if line_state == "waiting" or line_state == "bite":
		sag = 0.25
	elif line_state == "fight":
		sag = 0.2 * (1.0 - clampf(tension, 0.0, 1.0))
	var n := 12
	for i in n + 1:
		var s := float(i) / n
		var p := tip.lerp(bp + Vector3(0, 0.05, 0), s)
		p.y -= sag * sin(s * PI) * minf(1.0, tip.distance_to(bp) * 0.2)
		line_mesh.surface_add_vertex(p)
	line_mesh.surface_end()


# --- Networked co-op -------------------------------------------------------------------

func head_transform() -> Transform3D:
	if vr_like():
		return xr_camera.global_transform
	return Transform3D(Basis(Vector3.UP, aim_yaw), body_pos + Vector3(0, 1.32, 0))


func rod_transform() -> Transform3D:
	return rod_root.global_transform


func action_pressed() -> bool:
	if vr_like():
		return vr_trigger() or _a_button()
	if bot:
		return false
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set == 0 and Input.is_physical_key_pressed(KEY_SPACE)


func snapshot() -> Array:
	return [body_pos, aim_yaw, head_transform(), rod_transform(), vr_like(), line_state, lure_pos, bob, tension,
		bend, surge, hint]


func apply_net(s: Array) -> void:
	if s.size() < 12:
		return
	net_body = s[0]
	net_yaw = s[1]
	net_head = s[2]
	net_rod = s[3]
	net_vr = s[4]
	var ls: String = s[5]
	if ls != line_state:
		line_state = ls
		line_t = 0.0
	net_lure = s[6]
	bob = s[7]
	tension = s[8]
	bend = s[9]
	surge = s[10]
	hint = s[11]


func _ghost_update(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	if rod_root.get_parent() != self:
		rod_root.reparent(self, false)
	body_pos = body_pos.lerp(net_body, k) if body_pos.distance_to(net_body) < 3.0 else net_body
	aim_yaw = lerp_angle(aim_yaw, net_yaw, k)
	avatar.position = body_pos
	avatar.rotation.y = aim_yaw
	var head := avatar.get_node_or_null("Head") as Node3D
	if head != null:
		if net_vr and net_head != Transform3D():
			head.global_position = head.global_position.lerp(net_head.origin, k)
			head.rotation.y = net_head.basis.get_euler().y - aim_yaw
		else:
			head.position = Vector3(0, 1.32, 0)
	if net_rod != Transform3D():
		var cur := rod_root.global_transform
		rod_root.global_transform = cur.interpolate_with(net_rod.orthonormalized(), k)
	lure_pos = lure_pos.lerp(net_lure, k) if lure_pos.distance_to(net_lure) < 4.0 else net_lure
