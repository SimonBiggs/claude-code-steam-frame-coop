extends XROrigin3D
## VrRig: the standard VR player rig (host only). XROrigin3D + XRCamera3D + two XRController3D
## ("aim" pose) wearing cute mitten gloves, plus everything the games kept re-writing:
## - Height fit on start, and a re-fit when the head height changes a lot for a few seconds (the
##   headset was handed to a kid, or someone sat down). Signal `refitted(head_height)`.
## - Optional smooth left-stick locomotion (head-relative) and right-stick snap / smooth turn.
## - Trigger and A with edge detection and a GUARD: a trigger still held from the arcade, the pause
##   menu or the wrist MENU button never fires; it has to be released first.
## - Haptics, per-hand velocity / speed (swings, throws), touching(hand, point, radius) helpers.
## - Keeps clear of core/net.gd's wrist MENU button (beside the left wrist): a pull that starts on it
##   is the menu's, and in_wrist_zone() tells games where not to put grab targets.
## - world_scale support that always resets XRServer.world_scale to 1.0 when the rig leaves.
## - A small gdev_capture mirror SubViewport (rig.mirror) so people can watch the VR view; use it
##   for core/split_view.gd's VR bubble. On the TV machine use VrRig.Avatar + VrRig.build_mirror().
## - Mobile-renderer-safe VR settings: no SSAO / SSIL / SSR / SDFGI / fog / directional shadows,
##   MSAA 2x, 90 physics ticks.
## Steam Frame: ONLY the thumbsticks, the RIGHT trigger, the A button and the controller positions
## reach the game. The left trigger, grips, menu, X and Y do not: give the left hand touch jobs.
## Without a headset (bots: BOT_VR=1) the rig runs in `fake` mode: tests move camera / hands by hand
## and set fake_trigger, fake_a, fake_stick_l, fake_stick_r (tests/bot_kit.gd has a driver).
## Usage (host / local only, never on the TV machine):
##   const VrRig := preload("res://core/vr_rig.gd")
##   if VrRig.wanted(net.mode): vr_rig = VrRig.new(); add_child(vr_rig); vr_rig.place(Vector3(0, 0, 3), 0.0)
##   if vr_rig.trigger_pressed(): ...   if vr_rig.touching(VrRig.LEFT, bell.global_position, 0.12): ...
## Name the member `vr_rig` on main: core/net.gd finds the hands there for the wrist MENU.

## The fit changed: head_height is the real head height (metres above the floor) it fitted to.
signal refitted(head_height: float)

const LEFT := 0
const RIGHT := 1
## Must match core/net.gd's wrist MENU button (local to the left controller, times world scale).
const WRIST_MENU_OFFSET := Vector3(-0.08, 0.03, 0.1)
const TRIGGER_ON := 0.6
const TRIGGER_OFF := 0.35
## Render layer 20: the VR player's avatar on the TV machine. Mirror cameras leave it out.
const AVATAR_LAYER := 1 << 19
## Where a glove "is" (palm centre), local to the controller, times world scale.
const PALM_OFFSET := Vector3(0.0, -0.015, 0.03)
const _VEL_SAMPLES := 6

## Smooth movement with the left stick, relative to where the head looks.
var locomotion := true
var move_speed := 2.0
## "snap", "smooth" or "none" (right stick x).
var turn_mode := "snap"
var snap_degrees := 30.0
var smooth_turn_speed := 2.4
## Keep the head inside this XZ rectangle while moving (size zero = anywhere).
var bounds := Rect2()
## Optional func(from: Vector3, to: Vector3) -> Vector3: where the head may move (your own rules).
var move_filter: Callable
## Physics layers that block stick movement (0 = walk through everything). The player is a sphere
## of body_radius at knee height that slides along walls. Walking in real life is never blocked.
var collision_mask := 0
var body_radius := 0.25
## "eye": lift / lower the player so their eyes are at `eye_height` (kids and sitting players see
## like a standing grown-up); "none": real height (still re-fits and emits `refitted`).
var fit_mode := "eye"
var eye_height := 1.55
## Lift limits (metres): don't shrink tall players much, don't raise tiny ones absurdly.
var fit_limits := Vector2(-0.25, 0.6)
var refit_threshold := 0.28
var refit_time := 2.5
## A pull that starts on the wrist MENU button belongs to the menu.
var respect_wrist_menu := true
var glove_color := Color(1.0, 0.86, 0.6)
var cuff_color := Color(1.0, 1.0, 1.0)
var make_mirror := true
## Feet height the game wants (place() sets it); the rig's y = floor_height + fit lift.
var floor_height := 0.0
## Once tracking starts, put the player back on the place() spot (they may stand anywhere in
## their room when the game starts).
var recenter_on_first_fit := true

## True with a real headset, false in fake (bot) mode.
var is_xr := false
var fake := false
var fake_trigger := 0.0
var fake_a := false
var fake_stick_l := Vector2.ZERO
var fake_stick_r := Vector2.ZERO
## Fake mode: how many haptic pulses were requested (tests check it).
var pulses_sent := 0

var camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var gloves: Array[MeshInstance3D] = []
var mirror: SubViewport

var lift := 0.0
var fit_lift := 0.0
var head_height := 0.0
var fitted := false

var _fit_wait := 0.5
var _place_feet := Vector3.ZERO
var _place_yaw := NAN
var _has_place := false
var _refit_t := 0.0
var _trig_raw := false
var _trig_guard := true
var _trig_now: Array[bool] = [false, false]
var _trig_prev: Array[bool] = [false, false]
var _a_raw := false
var _a_guard := true
var _a_now: Array[bool] = [false, false]
var _a_prev: Array[bool] = [false, false]
var _snap_ready := true
var _last_frame := -1
var _was_paused := false
var _vel_pos: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _vel_time: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
var _pulse_msec := PackedInt64Array([0, 0])
var _clock := 0.0  # game time, for velocities (deterministic under --fixed-fps)
var _perf_t := 0.0
var _perf_scans := 0
var _body_shape: SphereShape3D


## True when an OpenXR headset is running on this machine.
static func headset_available() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and xr.is_initialized()


## Should this machine have a VR rig? Host / local with a headset, or a bot with BOT_VR set.
static func wanted(net_mode: String) -> bool:
	return net_mode != "client" and (headset_available() or OS.has_environment("BOT_VR"))


func _ready() -> void:
	name = "VrRig" if name == "" or name.begins_with("@") else name
	process_priority = -100  # inputs, locomotion and fit update before the game's _process
	process_physics_priority = -100
	is_xr = headset_available()
	fake = not is_xr
	camera = XRCamera3D.new()
	camera.name = "Head"
	camera.near = 0.02
	add_child(camera)
	hand_l = _make_hand("left_hand", true)
	hand_r = _make_hand("right_hand", false)
	if fake:
		camera.position = Vector3(0.0, 1.6, 0.0)
		hand_l.position = Vector3(-0.25, 1.1, -0.3)
		hand_r.position = Vector3(0.25, 1.1, -0.3)
	if is_xr:
		print("VrRig: headset found, VR on the main viewport")
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		Engine.physics_ticks_per_second = 90
		apply_vr_performance(get_parent())
	else:
		print("VrRig: no headset, fake VR (bot mode)")
	if make_mirror:
		mirror = build_mirror(self, camera, true)
	global_position.y = floor_height
	guard_trigger()


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave another game (or the arcade) scaled


func _make_hand(tracker_name: String, left: bool) -> XRController3D:
	var h := XRController3D.new()
	h.name = "LeftHand" if left else "RightHand"
	h.tracker = tracker_name
	h.pose = "aim"
	add_child(h)
	var g := MeshInstance3D.new()
	g.name = "Glove"
	g.mesh = glove_mesh(left, glove_color, cuff_color)
	g.material_override = vertex_color_material()
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(g)
	gloves.append(g)
	return h


# --- Placement and height fit -------------------------------------------------------------

## Put the player's feet at `feet` (head above it), facing `yaw` (radians, 0 = -Z) unless NAN.
## Remembered for recenter() and for the first fit.
func place(feet: Vector3, yaw: float = NAN) -> void:
	_place_feet = feet
	_place_yaw = yaw
	_has_place = true
	_apply_place(feet, yaw)


## Back to the last place() spot and facing (a "recentre" button, or a new round).
func recenter() -> void:
	if _has_place:
		_apply_place(_place_feet, _place_yaw)


func _apply_place(feet: Vector3, yaw: float) -> void:
	if not is_nan(yaw):
		_turn_about_head(yaw - head_yaw())
	var head := camera.global_position
	global_position.x += feet.x - head.x
	global_position.z += feet.z - head.z
	floor_height = feet.y
	global_position.y = floor_height + lift


## Fit again now (e.g. a "recentre" button), snapping the lift instead of gliding.
func refit() -> void:
	_do_fit(true)


func head_position() -> Vector3:
	return camera.global_position


## The head's yaw (radians, 0 = looking down -Z).
func head_yaw() -> float:
	var f := -camera.global_basis.z
	return atan2(-f.x, -f.z)


## Horizontal unit vector the head looks along.
func head_forward() -> Vector3:
	var f := -camera.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


## Real head height above the floor in metres (tracking, before the fit lift).
func real_head_height() -> float:
	return camera.position.y / maxf(world_scale, 0.001)


## Scale the world (XRServer.world_scale: 2 = the player is twice as big). Reset on exit.
func set_scale_of_world(ws: float) -> void:
	world_scale = ws


func _fit(delta: float) -> void:
	var h := real_head_height()
	if not fitted:
		if h > 0.3:
			_fit_wait -= delta
			if _fit_wait <= 0.0:
				_do_fit(true)
		return
	if absf(h - head_height) > refit_threshold:
		_refit_t += delta
		if _refit_t > refit_time:
			_do_fit(false)
	else:
		_refit_t = 0.0
	lift = lerpf(lift, fit_lift, 1.0 - exp(-3.0 * delta))
	global_position.y = floor_height + lift


func _do_fit(snap: bool) -> void:
	var h := real_head_height()
	var first := not fitted
	fitted = true
	_refit_t = 0.0
	head_height = h
	fit_lift = 0.0
	if fit_mode == "eye":
		fit_lift = clampf(eye_height - h, fit_limits.x, fit_limits.y) * world_scale
	if snap:
		lift = fit_lift
		global_position.y = floor_height + lift
	if first and recenter_on_first_fit:
		recenter()
	print("VrRig: fitted to head height %.2f m (lift %.2f)" % [h, fit_lift])
	refitted.emit(h)


# --- Inputs -------------------------------------------------------------------------------

## Right trigger 0..1 (the only trigger the Steam Frame passes through).
func trigger_value() -> float:
	if fake:
		return fake_trigger
	return hand_r.get_float("trigger") if hand_r != null else 0.0


## Trigger held (after a release since the rig started / unpaused / guard_trigger()).
func trigger_down() -> bool:
	return _trig_now[_ctx()]


## Trigger pulled this frame (fresh pull only: never one held over from another screen, and never
## a pull that started on the wrist MENU). Works in _process and _physics_process.
func trigger_pressed() -> bool:
	var c := _ctx()
	return _trig_now[c] and not _trig_prev[c]


## A counted trigger pull was let go this frame (e.g. throw on release).
func trigger_released() -> bool:
	var c := _ctx()
	return _trig_prev[c] and not _trig_now[c]


## A button (right controller) held / pressed this frame, with the same guard as the trigger.
func a_down() -> bool:
	return _a_now[_ctx()]


func a_pressed() -> bool:
	var c := _ctx()
	return _a_now[c] and not _a_prev[c]


## Left / right thumbstick (x right, y UP as OpenXR reports it), dead zone applied.
func stick_left() -> Vector2:
	return _dead(fake_stick_l if fake else hand_l.get_vector2("primary"))


func stick_right() -> Vector2:
	return _dead(fake_stick_r if fake else hand_r.get_vector2("primary"))


## Ignore the trigger and A until they are released (call when the screen changes under the player).
func guard_trigger() -> void:
	_trig_guard = true
	_a_guard = true
	for c in 2:
		_trig_now[c] = false
		_trig_prev[c] = false
		_a_now[c] = false
		_a_prev[c] = false


func _sample(c: int) -> void:
	var raw := trigger_value() > (TRIGGER_OFF if _trig_raw else TRIGGER_ON)
	if raw and not _trig_raw and respect_wrist_menu and on_wrist_menu():
		_trig_guard = true  # this pull is for the wrist MENU
	_trig_raw = raw
	if not raw:
		_trig_guard = false
	_trig_prev[c] = _trig_now[c]
	_trig_now[c] = raw and not _trig_guard
	var a := fake_a if fake else (hand_r.is_button_pressed("ax_button") or hand_l.is_button_pressed("ax_button"))
	_a_raw = a
	if not a:
		_a_guard = false
	_a_prev[c] = _a_now[c]
	_a_now[c] = a and not _a_guard


func _ctx() -> int:
	return 1 if Engine.is_in_physics_frame() else 0


func _dead(v: Vector2) -> Vector2:
	var l := v.length()
	if l < 0.18:
		return Vector2.ZERO
	return v / l * minf(1.0, (l - 0.18) / 0.82)


## Buzz a controller (rate-limited so it can be called every frame).
func pulse(which: int, amplitude: float = 0.4, duration: float = 0.06) -> void:
	var now := Time.get_ticks_msec()
	if now - _pulse_msec[which] < 30:
		return
	_pulse_msec[which] = now
	if fake:
		pulses_sent += 1
		return
	var h := hand_l if which == LEFT else hand_r
	h.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)


# --- Hands --------------------------------------------------------------------------------

func hand(which: int) -> XRController3D:
	return hand_l if which == LEFT else hand_r


## World position of a glove's palm.
func hand_point(which: int) -> Vector3:
	return hand(which).global_transform * (PALM_OFFSET * world_scale)


## Is the glove within `radius` (world units) of `point`?
func touching(which: int, point: Vector3, radius: float) -> bool:
	return hand_point(which).distance_to(point) < radius


## Which glove touches `point` (LEFT, RIGHT), or -1. Prefers the closer one.
func touching_any(point: Vector3, radius: float) -> int:
	var dl := hand_point(LEFT).distance_to(point)
	var dr := hand_point(RIGHT).distance_to(point)
	if minf(dl, dr) >= radius:
		return -1
	return LEFT if dl < dr else RIGHT


## Hand velocity from tracking (world orientation; the player's own stick movement is left out),
## averaged over the last few frames: use it for swings and throws.
func hand_velocity(which: int) -> Vector3:
	var ps: PackedVector3Array = _vel_pos[which]
	var ts: PackedFloat64Array = _vel_time[which]
	if ps.size() < 2:
		return Vector3.ZERO
	var dt := ts[ts.size() - 1] - ts[0]
	if dt <= 0.0001:
		return Vector3.ZERO
	return global_basis * ((ps[ps.size() - 1] - ps[0]) / dt)


func hand_speed(which: int) -> float:
	return hand_velocity(which).length()


## World position of core/net.gd's wrist MENU button.
func wrist_menu_position() -> Vector3:
	return hand_l.global_transform * (WRIST_MENU_OFFSET * world_scale)


## Is the right hand on (or pointing at) the wrist MENU button? Same test as core/net.gd.
func on_wrist_menu() -> bool:
	var to := wrist_menu_position() - hand_r.global_position
	var fwd := -hand_r.global_basis.z
	var along := to.dot(fwd)
	return to.length() < 0.08 * world_scale or (along > 0.0 and (to - fwd * along).length() < 0.07 * world_scale)


## Is `point` in the safe zone around the wrist MENU (don't put grab targets there)?
func in_wrist_zone(point: Vector3, margin: float = 0.12) -> bool:
	return point.distance_to(wrist_menu_position()) < margin * world_scale


func _track_velocity() -> void:
	var t := _clock
	for w in 2:
		var ps: PackedVector3Array = _vel_pos[w]
		var ts: PackedFloat64Array = _vel_time[w]
		ps.append(hand(w).position)
		ts.append(t)
		if ps.size() > _VEL_SAMPLES:
			ps.remove_at(0)
			ts.remove_at(0)
		_vel_pos[w] = ps
		_vel_time[w] = ts


# --- Locomotion ---------------------------------------------------------------------------

func _locomote(delta: float) -> void:
	if locomotion:
		var v := stick_left()
		if v != Vector2.ZERO:
			var f := head_forward()
			var r := Vector3(-f.z, 0.0, f.x)
			var from := camera.global_position
			var to := from + (r * v.x + f * v.y) * move_speed * delta
			if bounds.size != Vector2.ZERO:
				to.x = clampf(to.x, bounds.position.x, bounds.end.x)
				to.z = clampf(to.z, bounds.position.y, bounds.end.y)
			if collision_mask != 0:
				to = _collide_move(from, to)
			if move_filter.is_valid():
				to = move_filter.call(from, to)
			global_position.x += to.x - from.x
			global_position.z += to.z - from.z
	var x := stick_right().x
	match turn_mode:
		"snap":
			if absf(x) < 0.3:
				_snap_ready = true
			elif absf(x) > 0.7 and _snap_ready:
				_snap_ready = false
				_turn_about_head(-signf(x) * deg_to_rad(snap_degrees))
		"smooth":
			if absf(x) > 0.15:
				_turn_about_head(-x * smooth_turn_speed * delta)


## Stick movement against walls: cast a knee-high sphere, stop a skin short of what it hits and
## slide along it. (Casts ignore bodies they start inside, so never end a move touching a wall;
## if the player already stands in one for real, the stick may only move them out of it.)
func _collide_move(from: Vector3, to: Vector3) -> Vector3:
	const SKIN := 0.02
	if _body_shape == null:
		_body_shape = SphereShape3D.new()
	_body_shape.radius = body_radius * world_scale
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _body_shape
	q.collision_mask = collision_mask
	var at := Vector3(from.x, floor_height + (0.35 + body_radius) * world_scale, from.z)
	var motion := Vector3(to.x - from.x, 0.0, to.z - from.z)
	for attempt in 3:
		if motion.length_squared() < 0.00000001:
			break
		q.transform = Transform3D(Basis(), at)
		q.motion = Vector3.ZERO
		var inside := space.get_rest_info(q)
		if not inside.is_empty():
			var n0 := _flat_normal(inside)
			motion -= n0 * minf(motion.dot(n0), 0.0)
			at += motion
			break
		q.motion = motion
		var r := space.cast_motion(q)
		if r[0] >= 1.0:
			at += motion
			break
		var safe := maxf(0.0, r[0] - SKIN / motion.length())
		at += motion * safe
		q.transform = Transform3D(Basis(), at + motion * (r[1] - safe))
		q.motion = Vector3.ZERO
		var info := space.get_rest_info(q)
		if info.is_empty():
			break
		var n := _flat_normal(info)
		motion *= 1.0 - safe
		motion -= n * minf(motion.dot(n), 0.0)  # keep only the part along the wall
	return Vector3(at.x, to.y, at.z)


func _flat_normal(info: Dictionary) -> Vector3:
	var n: Vector3 = info.get("normal", Vector3.ZERO)
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.000001 else Vector3.ZERO


func _turn_about_head(angle: float) -> void:
	var head := camera.global_position
	var t := global_transform
	t.origin -= head
	t = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * t
	t.origin += head
	global_transform = t


# --- Frame upkeep -------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Paused (we stopped processing for a while, or we process always and saw the flag flip):
	# whatever is held now belongs to the pause menu.
	var frame := Engine.get_process_frames()
	var paused := get_tree().paused
	if (_last_frame >= 0 and frame - _last_frame > 1) or paused != _was_paused:
		guard_trigger()
	_last_frame = frame
	_was_paused = paused
	_clock += delta
	_sample(0)
	_track_velocity()
	if not paused:
		_fit(delta)
		_locomote(delta)
	if is_xr:
		_perf_t -= delta
		if _perf_t <= 0.0:
			_perf_t = 2.0
			_perf_scans += 1
			apply_vr_performance(get_parent(), _perf_scans <= 3)


func _physics_process(_delta: float) -> void:
	_sample(1)


## The game's own guard for screens it builds itself: true while the trigger is guarded.
func trigger_guarded() -> bool:
	return _trig_guard


## Phone-class GPU: switch off what the Mobile renderer can't afford in VR. Safe to call often;
## `scan_lights` also turns off directional shadows in root's subtree.
static func apply_vr_performance(root: Node, scan_lights: bool = true) -> void:
	if root == null or not root.is_inside_tree():
		return
	var w := root.get_viewport().find_world_3d()
	var envs: Array[Environment] = []
	if w != null and w.environment != null:
		envs.append(w.environment)
	for n in root.get_children():
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			envs.append((n as WorldEnvironment).environment)
	for e in envs:
		e.ssao_enabled = false
		e.ssil_enabled = false
		e.ssr_enabled = false
		e.sdfgi_enabled = false
		e.fog_enabled = false
		e.volumetric_fog_enabled = false
	if scan_lights:
		_no_sun_shadows(root)


static func _no_sun_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is DirectionalLight3D:
			(c as DirectionalLight3D).shadow_enabled = false
		elif c.get_child_count() > 0 and not c is SubViewport:
			_no_sun_shadows(c)


# --- Mirror (watch the VR view on a screen / in gdev) ---------------------------------------

## A small SubViewport whose camera follows `follow` (the XR camera, or VrRig.Avatar.head on the
## TV machine), refreshed `fps` times a second. capture = join group gdev_capture (gdev records it).
static func build_mirror(parent: Node, follow: Node3D, capture: bool = true, size: int = 480, fps: float = 30.0) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = "VrMirror"
	vp.size = Vector2i(size, size)
	vp.world_3d = parent.get_viewport().find_world_3d() if parent.is_inside_tree() else follow.get_viewport().find_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.process_mode = Node.PROCESS_MODE_ALWAYS  # keeps showing the pause banner
	if capture:
		vp.add_to_group("gdev_capture")
	parent.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.02
	cam.cull_mask = 0xFFFFF & ~AVATAR_LAYER
	vp.add_child(cam)
	cam.current = true
	var tick := MirrorTicker.new()
	tick.name = "Ticker"
	tick.follow = follow
	tick.cam = cam
	tick.vp = vp
	tick.interval = 1.0 / maxf(fps, 1.0)
	vp.add_child(tick)
	return vp


## Refreshes a mirror at a low rate (UPDATE_ONCE each tick) and keeps its camera on the head.
class MirrorTicker extends Node:
	var follow: Node3D
	var cam: Camera3D
	var vp: SubViewport
	var interval := 1.0 / 30.0
	var t := 0.0

	func _process(delta: float) -> void:
		if follow == null or not is_instance_valid(follow) or not follow.is_inside_tree():
			return
		cam.global_transform = follow.global_transform.orthonormalized()
		t -= delta
		if t <= 0.0:
			t = interval
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# --- Networking: the VR player's pose for the TV machine ---------------------------------

## Head and both hands for a snapshot: 21 floats (pos + quaternion each), world space.
func pack_pose() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n: Node3D in [camera, hand_l, hand_r]:
		var t := n.global_transform.orthonormalized()
		var q := t.basis.get_rotation_quaternion()
		out.append_array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w])
	return out


## The VR player as seen on the TV machine: a head with a visor and two gloves, smoothly following
## poses from VrRig.pack_pose(). Drawn on AVATAR_LAYER so mirrors following `head` skip it.
class Avatar extends Node3D:
	var head: Node3D
	var hands: Array[MeshInstance3D] = []
	var color := Color(0.3, 0.7, 1.0)
	var glove_color := Color(1.0, 0.86, 0.6)
	var smoothing := 15.0
	var _target: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D()]
	var _has_pose := false

	func _ready() -> void:
		head = Node3D.new()
		head.name = "Head"
		add_child(head)
		var face := MeshInstance3D.new()
		face.mesh = VrRigStatics.head_mesh(color)
		face.material_override = VrRigStatics.vertex_color_material()
		face.layers = AVATAR_LAYER
		head.add_child(face)
		for i in 2:
			var g := MeshInstance3D.new()
			g.mesh = VrRigStatics.glove_mesh(i == 0, glove_color, Color.WHITE)
			g.material_override = face.material_override
			g.layers = AVATAR_LAYER
			add_child(g)
			hands.append(g)
		visible = false

	## Feed VrRig.pack_pose() output (e.g. from a snapshot).
	func apply_pose(p: PackedFloat32Array) -> void:
		if p.size() < 21:
			return
		for i in 3:
			var o := i * 7
			_target[i] = Transform3D(Basis(Quaternion(p[o + 3], p[o + 4], p[o + 5], p[o + 6]).normalized()), Vector3(p[o], p[o + 1], p[o + 2]))
		if not _has_pose:
			_has_pose = true
			visible = true
			_snap()

	func _snap() -> void:
		head.global_transform = _target[0]
		for i in 2:
			hands[i].global_transform = _target[i + 1]

	func _process(delta: float) -> void:
		if not _has_pose:
			return
		var k := 1.0 - exp(-smoothing * delta)
		head.global_transform = head.global_transform.interpolate_with(_target[0], k)
		for i in 2:
			hands[i].global_transform = hands[i].global_transform.interpolate_with(_target[i + 1], k)


# --- Meshes ---------------------------------------------------------------------------------

## A cute mitten (palm, fingers, thumb, cuff) baked into one vertex-coloured mesh (1 draw call).
static func glove_mesh(left: bool, color: Color, cuff: Color) -> ArrayMesh:
	return VrRigStatics.glove_mesh(left, color, cuff)


static func vertex_color_material() -> StandardMaterial3D:
	return VrRigStatics.vertex_color_material()


## Mesh helpers shared by the rig and the avatar (an inner class so Avatar can use them too).
class VrRigStatics:
	# Built per rig / avatar (tiny meshes). Resources are NOT cached in Engine metadata: they would
	# outlive the renderer at exit and print leak errors.
	static func vertex_color_material() -> StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.8
		return mat

	static func glove_mesh(left: bool, color: Color, cuff: Color) -> ArrayMesh:
		var side := 1.0 if left else -1.0
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var palm := SphereMesh.new()
		palm.radius = 0.045
		palm.height = 0.09
		palm.radial_segments = 14
		palm.rings = 7
		_add(st, palm, Transform3D(Basis().scaled(Vector3(1.0, 0.6, 1.1)), Vector3(0.0, -0.015, 0.03)), color)
		var fingers := CapsuleMesh.new()
		fingers.radius = 0.03
		fingers.height = 0.1
		fingers.radial_segments = 12
		fingers.rings = 3
		_add(st, fingers, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.25, 1.0, 0.7)), Vector3(0.0, -0.01, -0.025)), color)
		var thumb := CapsuleMesh.new()
		thumb.radius = 0.014
		thumb.height = 0.06
		thumb.radial_segments = 8
		thumb.rings = 2
		_add(st, thumb, Transform3D(Basis(Vector3.UP, side * 0.6) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * 0.042, -0.008, 0.005)), color.darkened(0.08))
		var band := CylinderMesh.new()
		band.top_radius = 0.04
		band.bottom_radius = 0.043
		band.height = 0.035
		band.radial_segments = 14
		band.rings = 1
		_add(st, band, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 0.75)), Vector3(0.0, -0.015, 0.085)), cuff)
		return st.commit()

	static func head_mesh(color: Color) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var skull := SphereMesh.new()
		skull.radius = 0.12
		skull.height = 0.24
		skull.radial_segments = 16
		skull.rings = 8
		_add(st, skull, Transform3D(Basis(), Vector3(0.0, 0.0, 0.03)), Color(1.0, 0.82, 0.66))
		var visor := BoxMesh.new()
		visor.size = Vector3(0.2, 0.08, 0.09)
		_add(st, visor, Transform3D(Basis(), Vector3(0.0, 0.01, -0.07)), Color(0.18, 0.18, 0.24))
		var strap := CylinderMesh.new()
		strap.top_radius = 0.125
		strap.bottom_radius = 0.125
		strap.height = 0.03
		strap.radial_segments = 16
		strap.rings = 1
		_add(st, strap, Transform3D(Basis(), Vector3(0.0, 0.01, 0.03)), color)
		return st.commit()

	static func _add(st: SurfaceTool, m: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
		var arrays := m.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		for i in idx:
			st.set_color(c)
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
