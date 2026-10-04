extends Node
## CameraRig: drives one TV Camera3D (e.g. core/split_view.gd's camera(slot) or shared_camera()).
## Modes, switchable any time with a smooth blend between them:
## - "follow": third person behind a target. Orbit with the slot's right stick / mouse (give it a
##   core/party.gd `party` and `slot`) or orbit(); smoothing; never clips into walls (sphere cast in
##   _physics_process, pulls in fast, eases back out slowly); optional swing behind a moving target.
## - "group": top-down / isometric view of a group of targets, auto-zooming to fit them all (party
##   games, board games, RPG battles).
## - "shot": a fixed / cinematic camera (optionally drifting slowly) for intros, cut-scenes, quizzes.
## - "free": the rig leaves the camera alone (your code drives it).
## Plus gentle trauma-based shake on top of any mode.
## Usage:
##   const CameraRig := preload("res://core/camera_rig.gd")
##   var rig := CameraRig.new(); rig.camera = split.camera(slot); rig.party = party; rig.slot = slot
##   add_child(rig); rig.follow(avatar)            # or rig.follow_group(avatars) / rig.shot_look(a, b)
##   rig.shake(0.4)                                # on a big hit
## Call it from anywhere; it updates in _process (cameras move per rendered frame, no judder).

## Which mode is running: "follow", "group", "shot" or "free".
var mode := "free"
var camera: Camera3D

## Follow mode.
var target: Node3D
var distance := 5.0
var min_distance := 0.8
## Height of the orbit pivot above the target's origin.
var pivot_height := 1.4
## Orbit angles (radians). yaw 0 = camera on the target's +Z side looking towards -Z;
## pitch < 0 = camera above, looking down.
var yaw := 0.0
var pitch := -0.3
var pitch_min := -1.25
var pitch_max := 0.45
var follow_smoothing := 12.0
## Radians per second to swing behind a moving target (its -Z is "forward"); 0 = off.
var auto_behind := 0.0
var avoid_walls := true
var collision_mask := 1
var wall_margin := 0.25
## Extra bodies the wall check ignores (the target itself is always ignored if it is a body).
var exclude: Array[RID] = []

## Orbit input: read party.look(slot) in follow mode (right stick, or the keyboard player's mouse).
var party: Node
var slot := -1
var orbit_speed := 2.6
var invert_y := false

## Group mode.
var targets: Array[Node3D] = []
var group_pitch := deg_to_rad(-55.0)
var group_yaw := 0.0
var group_margin := 2.5
var group_min_distance := 6.0
var group_max_distance := 45.0
var group_smoothing := 3.0

## Shot mode: slow drift in world units per second (cinematic dolly).
var shot_drift := Vector3.ZERO

## Seconds to blend between modes / shots (when a call doesn't say).
var blend_time := 0.6

## Shake: trauma 0..1 decays at shake_decay per second; offset ~ trauma^2.
var trauma := 0.0
var shake_decay := 1.6
var max_shake_offset := 0.16
var max_shake_angle := 0.03

var _pivot := Vector3.ZERO
var _pivot_ok := false
var _cur_dist := 5.0
var _clear := INF
var _last_target_pos := Vector3.ZERO
var _group_center := Vector3.ZERO
var _group_dist := 12.0
var _group_ok := false
var _shot := Transform3D()
var _blend_from := Transform3D()
var _blend_t := 1.0
var _blend_dur := 0.6
var _last := Transform3D()
var _has_last := false
var _shake_time := 0.0
var _sphere: SphereShape3D


# --- Mode switches ------------------------------------------------------------------------

## Third person behind `who`. distance < 0 keeps the current distance; blend < 0 uses blend_time.
func follow(who: Node3D, dist: float = -1.0, blend: float = -1.0) -> void:
	target = who
	if dist > 0.0:
		distance = dist
	if who != null:
		_pivot = who.global_position + Vector3.UP * pivot_height
		_pivot_ok = true
		_last_target_pos = who.global_position
	_cur_dist = distance
	_clear = INF
	_switch("follow", blend)


## Look down on a group, zooming to fit everyone. Angles in degrees.
func follow_group(who: Array, pitch_deg: float = -55.0, yaw_deg: float = 0.0, blend: float = -1.0) -> void:
	set_targets(who)
	group_pitch = deg_to_rad(pitch_deg)
	group_yaw = deg_to_rad(yaw_deg)
	_group_ok = false
	_switch("group", blend)


## Change the group without a blend (players joining / leaving).
func set_targets(who: Array) -> void:
	targets.clear()
	for n in who:
		if n is Node3D:
			targets.append(n)


## A fixed camera transform (smoothly blended to).
func shot(xf: Transform3D, blend: float = -1.0, drift: Vector3 = Vector3.ZERO) -> void:
	_shot = xf
	shot_drift = drift
	_switch("shot", blend)


## A fixed camera at `from` looking at `at`.
func shot_look(from: Vector3, at: Vector3, blend: float = -1.0, drift: Vector3 = Vector3.ZERO) -> void:
	var up := Vector3.UP if absf((at - from).normalized().y) < 0.98 else Vector3.FORWARD
	shot(Transform3D(Basis(), from).looking_at(at, up), blend, drift)


## Stop driving the camera (your code moves it).
func release() -> void:
	mode = "free"


## Manual orbit (radians): x turns around the target, y tilts up / down.
func orbit(delta_angles: Vector2) -> void:
	yaw -= delta_angles.x
	pitch = clampf(pitch - delta_angles.y * (-1.0 if invert_y else 1.0), pitch_min, pitch_max)


## Add camera shake (0..1; 0.2 = a bump, 0.5 = an explosion nearby, 1 = an earthquake).
func shake(amount: float = 0.4) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Jump straight to where the camera wants to be (no smoothing, no blend), e.g. after a teleport.
func snap() -> void:
	_blend_t = 1.0
	_pivot_ok = false
	_group_ok = false
	_cur_dist = distance
	_has_last = false


func _switch(new_mode: String, blend: float) -> void:
	var dur := blend_time if blend < 0.0 else blend
	if camera != null and is_instance_valid(camera) and dur > 0.0 and (_has_last or camera.is_inside_tree()):
		_blend_from = _last if _has_last else camera.global_transform
		_blend_t = 0.0
		_blend_dur = dur
	else:
		_blend_t = 1.0
	mode = new_mode


## True while a mode change or shot is still blending in.
func is_blending() -> bool:
	return _blend_t < 1.0


# --- Per-frame ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree() or mode == "free":
		return
	if mode == "follow" and party != null and slot >= 0 and is_instance_valid(party):
		var l: Vector2 = party.look(slot, delta, orbit_speed)
		if l != Vector2.ZERO:
			orbit(l)
	var want := _last
	match mode:
		"follow":
			want = _follow_xf(delta)
		"group":
			want = _group_xf(delta)
		"shot":
			_shot.origin += shot_drift * delta
			want = _shot
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / maxf(_blend_dur, 0.01))
		want = _blend_from.interpolate_with(want, smoothstep(0.0, 1.0, _blend_t))
	_last = want
	_has_last = true
	camera.global_transform = _shaken(want, delta)


func _physics_process(_delta: float) -> void:
	if mode != "follow" or not avoid_walls or target == null or not is_instance_valid(target) \
			or camera == null or not camera.is_inside_tree():
		_clear = INF
		return
	var pivot := target.global_position + Vector3.UP * pivot_height
	var to := pivot + _orbit_dir() * distance
	if _sphere == null:
		_sphere = SphereShape3D.new()
	_sphere.radius = wall_margin
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis(), pivot)
	q.motion = to - pivot
	q.collision_mask = collision_mask
	var ex: Array[RID] = exclude.duplicate()
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())
	q.exclude = ex
	var r := camera.get_world_3d().direct_space_state.cast_motion(q)
	_clear = INF if r.size() < 1 or r[0] >= 1.0 else maxf(distance * r[0], min_distance)


func _orbit_dir() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, 1.0)


func _follow_xf(delta: float) -> Transform3D:
	if target == null or not is_instance_valid(target):
		return _last
	var tp := target.global_position
	if auto_behind > 0.0 and delta > 0.0:
		var moved := tp - _last_target_pos
		moved.y = 0.0
		if moved.length() / delta > 0.5:
			var f := -target.global_basis.z
			var behind := atan2(-f.x, -f.z)
			yaw = rotate_toward(yaw, behind, auto_behind * delta)
	_last_target_pos = tp
	var pivot := tp + Vector3.UP * pivot_height
	if not _pivot_ok:
		_pivot = pivot
		_pivot_ok = true
	_pivot = _pivot.lerp(pivot, 1.0 - exp(-follow_smoothing * delta))
	var want_d := minf(distance, _clear)
	# Pull in quickly when a wall gets in the way, ease back out slowly.
	var rate := 25.0 if want_d < _cur_dist else 3.0
	_cur_dist = lerpf(_cur_dist, want_d, 1.0 - exp(-rate * delta))
	var pos := _pivot + _orbit_dir() * maxf(_cur_dist, min_distance)
	return _look_xf(pos, _pivot)


func _group_xf(delta: float) -> Transform3D:
	var pts: Array[Vector3] = []
	for n in targets:
		if n != null and is_instance_valid(n) and n.is_inside_tree():
			pts.append(n.global_position)
	if pts.is_empty():
		pts.append(_group_center)  # nobody yet: keep looking at the last centre (the origin at first)
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var r := 0.0
	for p in pts:
		r = maxf(r, Vector2(p.x - c.x, p.z - c.z).length())
	r += group_margin
	var vfov := deg_to_rad(camera.fov)
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * aspect)
	var need := clampf(r / sin(minf(vfov, hfov) * 0.5), group_min_distance, group_max_distance)
	if not _group_ok:
		_group_ok = true
		_group_center = c
		_group_dist = need
	var k := 1.0 - exp(-group_smoothing * delta)
	_group_center = _group_center.lerp(c, k)
	_group_dist = lerpf(_group_dist, need, k)
	var dir := Basis.from_euler(Vector3(group_pitch, group_yaw, 0.0)) * Vector3(0.0, 0.0, 1.0)
	return _look_xf(_group_center + dir * _group_dist, _group_center)


## The distance group mode is zooming to right now.
func group_distance() -> float:
	return _group_dist


func _look_xf(from: Vector3, at: Vector3) -> Transform3D:
	if from.distance_to(at) < 0.001:
		return Transform3D(Basis(), from)
	var up := Vector3.UP if absf((at - from).normalized().y) < 0.98 else Vector3.FORWARD
	return Transform3D(Basis(), from).looking_at(at, up)


func _shaken(xf: Transform3D, delta: float) -> Transform3D:
	if trauma <= 0.0:
		return xf
	_shake_time += delta
	trauma = maxf(0.0, trauma - shake_decay * delta)
	var s := trauma * trauma
	var t := _shake_time
	var off := Vector3(sin(t * 37.0) + sin(t * 21.3 + 1.7), sin(t * 31.0 + 0.6) + sin(t * 17.9), 0.0) * 0.5 * max_shake_offset * s
	var roll := (sin(t * 27.0 + 2.1) + sin(t * 13.3)) * 0.5 * max_shake_angle * s
	var out := xf
	out.origin += xf.basis * off
	out.basis = out.basis * Basis(Vector3.BACK, roll)
	return out
