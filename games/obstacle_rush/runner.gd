extends CharacterBody3D
## OBSTACLE RUSH: one wobbly jelly-bean runner.
## control:
##   "local"  simulated on this machine from the inp_* fields (a TV player's pad, or a CPU brain on
##            the host). Movement is instant; the host is told where we are.
##   "puppet" drawn from network updates (a TV player seen on the host, a CPU runner on the TV).
## Moves: run, jump (coyote time, jump buffer, short hop on a tap), DIVE (lunge + belly slide),
## automatic ledge grab and climb, tumbles when hit (spin, comical bounce, quick pop-up and a moment
## of invulnerability: never punishing), soft bumps with other runners, conveyors, bounce pads,
## speed strips and slippery tilting floors.
## The course and main decide what hits us (course.hazard_hit, main.dynamic_hit), what happens when we
## fall (main.on_runner_fell) and where we respawn (checkpoint).

const RunnerLook := preload("res://games/obstacle_rush/runner_look.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const S_RUN := 0
const S_DIVE := 1
const S_TUMBLE := 2
const S_LEDGE := 3
const S_RESPAWN := 4
const S_DONE := 5
const S_FROZEN := 6
const S_HIDDEN := 7
const STATE_NAMES: Array[String] = ["run", "dive", "tumble", "ledge", "respawn", "done", "frozen", "hidden"]

const RUN_SPEED := 6.4
const GROUND_ACCEL := 48.0
const AIR_ACCEL := 17.0
const JUMP_V := 8.6
const GRAVITY := 25.0
const FALL_MULT := 1.22
const MAX_FALL := 30.0
const COYOTE := 0.13
const JUMP_BUFFER := 0.16
const DIVE_SPEED := 9.6
const DIVE_UP := 3.4
const BOUNCE_V := 15.5
const BOOST_MULT := 1.5
const RADIUS := 0.36
const HEIGHT := 1.12
const TUMBLE_MIN := 0.75
const INVULN_AFTER := 0.9
## Render layers: TV-only bits (name tags) and VR-only bits (booth markers).
const LAYER_TV := 1 << 1
const LAYER_VR := 1 << 2

var main: Node
var runner_id := 0  # runner id: slot 0..6 for people, 10+ for CPU runners
var look := {}
var control := "local"
var is_cpu := false

# --- Input (set every physics tick by main / the CPU brain) ---
var inp_move := Vector3.ZERO  ## world direction, length 0..1
var inp_jump := false  ## held
var inp_jump_pressed := false  ## went down (consumed here)
var inp_dive_pressed := false  ## went down (consumed here)

# --- State ---
var state := S_RUN
var face_yaw := 0.0  ## radians, 0 = facing -Z
var boost_t := 0.0
var invuln_t := 0.0
var checkpoint := Vector3.ZERO
var checkpoint_yaw := 0.0
var speed_scale := 1.0
var tumbles := 0
var jumps := 0
var dives := 0
var team := -1
var has_tail := false
var tail_immune_t := 0.0
var finished := false

var _ctl := Vector3.ZERO  # controlled horizontal velocity
var _push := Vector3.ZERO  # external horizontal momentum (knocks, pads, dives)
var _belt := Vector3.ZERO
var _air_t := 0.0
var _jump_buf := 0.0
var _jump_age := 99.0
var _cut := false
var _state_t := 0.0
var _ground_t := 0.0
var _was_floor := true
var _prev_vy := 0.0
var _ledge_from := Vector3.ZERO
var _ledge_to := Vector3.ZERO
var _ledge_hang := Vector3.ZERO
var _spin_axis := Vector3.RIGHT
var _spin_rate := 10.0
var _bounces := 0
var _pad_cool := 0.0
var _door_cool := 0.0
var _land_cool := 0.0

# --- Puppet ---
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_state := 0
var _net_has := false
var est_vel := Vector3.ZERO
var _last_pos := Vector3.ZERO

# --- Visuals ---
var pivot: Node3D
var body_mi: MeshInstance3D
var arms: Array[Node3D] = []
var feet: Array[Node3D] = []
var shadow: MeshInstance3D
var tag: Label3D
var marker: MeshInstance3D
var crown: MeshInstance3D
var tail: MeshInstance3D
var band: MeshInstance3D
var boost_fx: CPUParticles3D
var puff: CPUParticles3D
var _sq := 0.0
var _sq_v := 0.0
var _lean := Vector2.ZERO
var _lean_v := Vector2.ZERO
var _walk := 0.0
var _vis_yaw := 0.0
var _celebrate := 0.0
var _blink_t := 0.0
var _anim_state := 0


func _ready() -> void:
	collision_layer = 0  # runners don't collide with each other (soft bumps instead)
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(52.0)
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	safe_margin = 0.02
	max_slides = 5
	process_physics_priority = 10  # after main has set this tick's input
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT * 0.5
	add_child(cs)
	_build_visuals()
	_last_pos = global_position
	net_pos = global_position


func _build_visuals() -> void:
	var col: Color = look.get("color", Color.WHITE)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	var inner := Node3D.new()  # the bean squashes round its middle
	inner.name = "Bean"
	pivot.add_child(inner)
	body_mi = MeshInstance3D.new()
	body_mi.mesh = RunnerLook.body_mesh(col, String(look.get("costume", "party_hat")), String(look.get("pattern", "plain")))
	inner.add_child(body_mi)
	for side in [-1.0, 1.0]:
		var sx: float = side
		var sh := Node3D.new()
		sh.position = Vector3(sx * (RADIUS + 0.02), 0.6, 0.0)
		inner.add_child(sh)
		var am := MeshInstance3D.new()
		am.mesh = RunnerLook.arm_mesh(col)
		am.visibility_range_end = 30.0
		sh.add_child(am)
		arms.append(sh)
		var ft := Node3D.new()
		ft.position = Vector3(sx * 0.15, 0.0, 0.0)
		pivot.add_child(ft)
		var fm := MeshInstance3D.new()
		fm.mesh = RunnerLook.foot_mesh(col)
		fm.visibility_range_end = 30.0
		ft.add_child(fm)
		feet.append(ft)
	crown = MeshInstance3D.new()
	crown.mesh = RunnerLook.crown_mesh()
	crown.position = Vector3(0, HEIGHT + 0.02, 0)
	crown.scale = Vector3.ONE * 0.75
	crown.visible = false
	inner.add_child(crown)
	tail = MeshInstance3D.new()
	tail.mesh = RunnerLook.tail_mesh()
	tail.position = Vector3(0, 0.35, RADIUS * 0.85)
	tail.visible = false
	inner.add_child(tail)
	band = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RADIUS * 0.96
	tm.outer_radius = RADIUS * 1.12
	tm.rings = 16
	tm.ring_segments = 6
	band.mesh = tm
	band.position.y = 0.46
	band.visible = false
	inner.add_child(band)
	# soft round shadow on whatever is below (also tells you where you'll land)
	shadow = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.9, 0.9)
	qm.orientation = PlaneMesh.FACE_Y
	shadow.mesh = qm
	shadow.material_override = _shadow_material()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.top_level = true
	add_child(shadow)
	boost_fx = CPUParticles3D.new()
	boost_fx.amount = 16
	boost_fx.lifetime = 0.45
	boost_fx.emitting = false
	boost_fx.local_coords = false
	boost_fx.direction = Vector3.UP
	boost_fx.spread = 30.0
	boost_fx.initial_velocity_min = 0.5
	boost_fx.initial_velocity_max = 1.5
	boost_fx.gravity = Vector3.ZERO
	boost_fx.scale_amount_min = 0.6
	boost_fx.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = MeshKit.material(Color(0.4, 0.95, 1.0), 2.0)
	boost_fx.mesh = sm
	boost_fx.position.y = 0.3
	add_child(boost_fx)
	puff = CPUParticles3D.new()
	puff.amount = 10
	puff.lifetime = 0.45
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.emitting = false
	puff.local_coords = false
	puff.direction = Vector3.UP
	puff.spread = 80.0
	puff.initial_velocity_min = 1.2
	puff.initial_velocity_max = 2.4
	puff.gravity = Vector3(0, -3, 0)
	puff.scale_amount_min = 0.7
	puff.scale_amount_max = 1.4
	var pm := SphereMesh.new()
	pm.radius = 0.1
	pm.height = 0.2
	pm.radial_segments = 6
	pm.rings = 3
	pm.material = MeshKit.material(Color(1, 1, 1, 0.85))
	puff.mesh = pm
	puff.position.y = 0.08
	add_child(puff)


func _shadow_material() -> StandardMaterial3D:
	var key := "or_shadow_mat"
	if main != null and main.has_meta(key):
		return main.get_meta(key)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.05, 0.02, 0.12, 0.38)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	if main != null:
		main.set_meta(key, m)
	return m


## A floating name tag (TV cameras; Y-billboard) and a marker for the VR booth (faces the booth).
func make_tags(tv: bool, vr: bool, booth_pos: Vector3) -> void:
	var col: Color = look.get("color", Color.WHITE)
	if tv and tag == null:
		tag = Label3D.new()
		tag.text = String(look.get("name", "?"))
		tag.font_size = 44
		tag.pixel_size = 0.006
		tag.outline_size = 12
		tag.modulate = col.lightened(0.25)
		tag.outline_modulate = Color(0.02, 0.02, 0.08)
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		tag.no_depth_test = false
		tag.fixed_size = false
		tag.position.y = HEIGHT + 0.55
		tag.layers = LAYER_TV
		add_child(tag)
	if vr and marker == null:
		marker = MeshInstance3D.new()
		marker.mesh = RunnerLook.marker_mesh(col)
		marker.layers = LAYER_VR
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position.y = HEIGHT + 1.3
		add_child(marker)
		var l := Label3D.new()
		l.text = String(look.get("name", "?"))
		l.font_size = 64
		l.pixel_size = 0.012
		l.outline_size = 18
		l.modulate = col.lightened(0.3)
		l.outline_modulate = Color(0.02, 0.02, 0.08)
		l.layers = LAYER_VR
		l.name = "MarkerLabel"
		l.position = Vector3(0, HEIGHT + 1.85, 0)
		l.no_depth_test = false
		add_child(l)
		marker.set_meta("booth", booth_pos)


# --- Commands -------------------------------------------------------------------------------------

## Put the runner at a spot (round start / respawn), standing, facing `yaw`.
func place(at: Vector3, yaw: float, new_state: int = S_FROZEN) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_ctl = Vector3.ZERO
	_push = Vector3.ZERO
	_belt = Vector3.ZERO
	face_yaw = yaw
	_vis_yaw = yaw
	checkpoint = at
	checkpoint_yaw = yaw
	net_pos = at
	_last_pos = at
	_set_state(new_state)
	pivot.rotation = Vector3(0, yaw, 0)
	pivot.position = Vector3.ZERO
	visible = new_state != S_HIDDEN
	finished = false
	boost_t = 0.0
	invuln_t = 0.0


func set_hidden(on: bool) -> void:
	if on:
		_set_state(S_HIDDEN)
		visible = false
	elif state == S_HIDDEN:
		_set_state(S_RUN)
		visible = true


## Go! (after the countdown)
func release() -> void:
	if state == S_FROZEN:
		_set_state(S_RUN)


func _set_state(s: int) -> void:
	state = s
	_state_t = 0.0


## Knocked by something (impulse = velocity to fly off with). Returns true if it took.
func knock(impulse: Vector3, soft: bool = false) -> bool:
	if invuln_t > 0.0 or state in [S_HIDDEN, S_RESPAWN, S_DONE, S_FROZEN, S_TUMBLE]:
		return false
	if soft:
		_push += Vector3(impulse.x, 0.0, impulse.z)
		velocity.y = maxf(velocity.y, impulse.y)
		invuln_t = 0.35
		return true
	_set_state(S_TUMBLE)
	_push = Vector3(impulse.x, 0.0, impulse.z)
	_ctl = Vector3.ZERO
	velocity = impulse
	_bounces = 0
	_ground_t = 0.0
	var flat := Vector3(impulse.x, 0.0, impulse.z)
	_spin_axis = Vector3.UP.cross(flat.normalized()) if flat.length() > 0.1 else Vector3.RIGHT
	_spin_axis = (_spin_axis + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3))).normalized()
	_spin_rate = randf_range(9.0, 14.0)
	tumbles += 1
	_sq_v -= 5.0
	if main != null:
		main.on_runner_tumble(self)
	return true


## A helper's speed boost (or a speed strip).
func give_boost(seconds: float = 2.5) -> void:
	boost_t = maxf(boost_t, seconds)


## Respawn at the checkpoint (after a fall in a race).
func respawn() -> void:
	_set_state(S_RESPAWN)
	velocity = Vector3.ZERO
	_ctl = Vector3.ZERO
	_push = Vector3.ZERO
	visible = false


# --- Simulation (control == "local") -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if control != "local" or main == null or main.course == null:
		return
	if state == S_HIDDEN:
		inp_jump_pressed = false
		inp_dive_pressed = false
		return
	var course: Node = main.course
	_state_t += delta
	invuln_t = maxf(0.0, invuln_t - delta)
	boost_t = maxf(0.0, boost_t - delta)
	tail_immune_t = maxf(0.0, tail_immune_t - delta)
	_pad_cool = maxf(0.0, _pad_cool - delta)
	_door_cool = maxf(0.0, _door_cool - delta)
	_land_cool = maxf(0.0, _land_cool - delta)
	_jump_age += delta
	_prev_vy = velocity.y
	match state:
		S_RESPAWN:
			if _state_t > 0.45:
				global_position = checkpoint
				face_yaw = checkpoint_yaw
				_vis_yaw = face_yaw
				velocity = Vector3.ZERO
				visible = true
				invuln_t = 1.6
				_set_state(S_RUN)
				main.on_runner_respawned(self)
			inp_jump_pressed = false
			inp_dive_pressed = false
			return
		S_LEDGE:
			_move_ledge(delta)
			inp_jump_pressed = false
			inp_dive_pressed = false
			return
		S_FROZEN:
			_move_frozen(delta)
		S_TUMBLE:
			_move_tumble(delta)
		S_DIVE:
			_move_dive(delta)
		S_DONE:
			_move_done(delta)
		_:
			_move_run(delta)
	inp_jump_pressed = false
	inp_dive_pressed = false
	var vy_before := velocity.y
	move_and_slide()
	_after_move(delta, vy_before, course)


func _gravity(delta: float) -> void:
	var g := GRAVITY * (FALL_MULT if velocity.y < 0.0 else 1.0)
	velocity.y = maxf(velocity.y - g * delta, -MAX_FALL)


func _decay_push(delta: float, on_floor: bool) -> void:
	_push *= exp(-(8.0 if on_floor else 0.9) * delta)
	if _push.length() < 0.05:
		_push = Vector3.ZERO


func _move_frozen(delta: float) -> void:
	_ctl = Vector3.ZERO
	_decay_push(delta, true)
	_gravity(delta)
	velocity.x = _push.x
	velocity.z = _push.z


func _move_run(delta: float) -> void:
	var on_floor := is_on_floor()
	_air_t = 0.0 if on_floor else _air_t + delta
	if inp_jump_pressed:
		_jump_buf = JUMP_BUFFER
	_jump_buf -= delta
	var spd := RUN_SPEED * speed_scale * (BOOST_MULT if boost_t > 0.0 else 1.0)
	var want := inp_move.limit_length(1.0) * spd
	want.y = 0.0
	var acc := GROUND_ACCEL if on_floor else AIR_ACCEL
	if not on_floor and want.length() < 0.1:
		acc = 3.0  # keep momentum in the air
	_ctl = _ctl.move_toward(want, acc * delta)
	_decay_push(delta, on_floor)
	# jump (coyote time + buffer)
	if _jump_buf > 0.0 and _air_t <= COYOTE and velocity.y <= 4.0:
		velocity.y = JUMP_V
		_air_t = COYOTE + 1.0
		_jump_buf = 0.0
		_jump_age = 0.0
		_cut = false
		jumps += 1
		_sq_v -= 7.0
		_puff()
		if main != null:
			main.runner_sound(self, "jump", -12.0, 1.0 + randf() * 0.15)
	elif velocity.y > 0.0 and not inp_jump and not _cut and _jump_age > 0.09 and _jump_age < 0.4:
		velocity.y *= 0.62  # tap = a shorter hop
		_cut = true
	if not on_floor or velocity.y > 0.0:
		_gravity(delta)
	# dive
	if inp_dive_pressed and _state_t > 0.1:
		_start_dive(on_floor)
		return
	# facing
	if _ctl.length() > 0.6:
		face_yaw = lerp_angle(face_yaw, atan2(-_ctl.x, -_ctl.z), 1.0 - exp(-16.0 * delta))
	velocity.x = _ctl.x + _push.x + _belt.x
	velocity.z = _ctl.z + _push.z + _belt.z
	# ledge grab when falling against a ledge
	if not on_floor and velocity.y < 2.5 and want.length() > 1.0:
		_try_ledge()


func _start_dive(on_floor: bool) -> void:
	_set_state(S_DIVE)
	dives += 1
	var fwd := Basis(Vector3.UP, face_yaw) * Vector3.FORWARD
	if inp_move.length() > 0.3:
		fwd = Vector3(inp_move.x, 0.0, inp_move.z).normalized()
		face_yaw = atan2(-fwd.x, -fwd.z)
	var cur := Vector3(velocity.x, 0.0, velocity.z)
	var spd := maxf(DIVE_SPEED, cur.dot(fwd) + 2.5)
	_push = fwd * spd
	_ctl = Vector3.ZERO
	velocity.y = DIVE_UP if on_floor else maxf(velocity.y + 1.5, 2.0)
	_sq_v += 4.0
	if main != null:
		main.runner_sound(self, "whoosh", -10.0, 1.3)
		main.on_runner_dive(self)


func _move_dive(delta: float) -> void:
	var on_floor := is_on_floor() and _state_t > 0.12
	if on_floor:
		_ground_t += delta
		_push *= exp(-4.5 * delta)
	else:
		_ground_t = 0.0
		_push *= exp(-0.4 * delta)
	_gravity(delta)
	# a little steering while sliding
	if inp_move.length() > 0.3 and _push.length() > 0.5:
		var want := Vector3(inp_move.x, 0.0, inp_move.z).normalized() * _push.length()
		_push = _push.move_toward(want, 6.0 * delta)
	velocity.x = _push.x + _belt.x
	velocity.z = _push.z + _belt.z
	if (on_floor and (_ground_t > 0.42 or inp_jump_pressed)) or _state_t > 2.5:
		_set_state(S_RUN)
		_ctl = Vector3(_push.x, 0.0, _push.z).limit_length(RUN_SPEED * 0.6)
		_push = Vector3.ZERO
		_sq_v -= 4.0
		_puff()


func _move_tumble(delta: float) -> void:
	var on_floor := is_on_floor()
	_gravity(delta)
	if on_floor and _state_t > 0.08:
		_ground_t += delta
		_push *= exp(-5.0 * delta)
	else:
		_push *= exp(-0.5 * delta)
	velocity.x = _push.x + _belt.x
	velocity.z = _push.z + _belt.z
	var can_get_up := _state_t > TUMBLE_MIN and _ground_t > 0.12
	if can_get_up or (_state_t > 0.45 and on_floor and inp_jump_pressed) or _state_t > 3.0:
		_set_state(S_RUN)
		_ctl = Vector3.ZERO
		invuln_t = INVULN_AFTER
		_sq_v -= 8.0
		_puff()
		if main != null:
			main.runner_sound(self, "boing", -8.0, 1.25)


func _move_done(delta: float) -> void:
	# celebrate on the finish platform: hop now and then, keep a gentle walk
	var on_floor := is_on_floor()
	_ctl = _ctl.move_toward(inp_move.limit_length(1.0) * RUN_SPEED * 0.5, GROUND_ACCEL * delta)
	_decay_push(delta, on_floor)
	if on_floor and fmod(_state_t, 1.6) < delta * 1.5 and _state_t > 0.5:
		velocity.y = JUMP_V * 0.6
		_sq_v -= 5.0
	if not on_floor or velocity.y > 0.0:
		_gravity(delta)
	velocity.x = _ctl.x + _push.x + _belt.x
	velocity.z = _ctl.z + _push.z + _belt.z
	if _ctl.length() > 0.6:
		face_yaw = lerp_angle(face_yaw, atan2(-_ctl.x, -_ctl.z), 1.0 - exp(-10.0 * delta))


func _try_ledge() -> void:
	var fwd := Basis(Vector3.UP, face_yaw) * Vector3.FORWARD
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3.UP * 0.85
	var q := PhysicsRayQueryParameters3D.create(chest, chest + fwd * (RADIUS + 0.45), 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.35:
		return
	var hp: Vector3 = hit["position"]
	var from := Vector3(hp.x, global_position.y + 2.1, hp.z) - Vector3(n.x, 0.0, n.z).normalized() * 0.35
	var q2 := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1)
	q2.exclude = [get_rid()]
	var hit2 := space.intersect_ray(q2)
	if hit2.is_empty():
		return
	var top_n: Vector3 = hit2["normal"]
	var top: Vector3 = hit2["position"]
	var rel := top.y - global_position.y
	if top_n.y < 0.75 or rel < 0.5 or rel > 1.8:
		return
	# room to stand on top?
	var q3 := PhysicsRayQueryParameters3D.create(top + Vector3.UP * 0.05, top + Vector3.UP * (HEIGHT + 0.1), 1)
	q3.exclude = [get_rid()]
	if not space.intersect_ray(q3).is_empty():
		return
	var nn := Vector3(n.x, 0.0, n.z).normalized()
	_ledge_hang = Vector3(hp.x, top.y - 1.0, hp.z) + nn * (RADIUS + 0.05)
	_ledge_from = global_position
	_ledge_to = top + Vector3.UP * 0.08 - nn * 0.35
	face_yaw = atan2(nn.x, nn.z)
	_set_state(S_LEDGE)
	velocity = Vector3.ZERO
	_ctl = Vector3.ZERO
	_push = Vector3.ZERO
	if main != null:
		main.runner_sound(self, "pop", -10.0, 0.9)


func _move_ledge(_delta: float) -> void:
	var t := _state_t
	if t < 0.12:
		global_position = _ledge_from.lerp(_ledge_hang, t / 0.12)
	elif t < 0.3:
		global_position = _ledge_hang
	elif t < 0.55:
		var k := (t - 0.3) / 0.25
		var p := _ledge_hang.lerp(_ledge_to, k)
		p.y = lerpf(_ledge_hang.y, _ledge_to.y, minf(1.0, k * 1.6))
		global_position = p
	else:
		global_position = _ledge_to
		velocity = Vector3.ZERO
		_set_state(S_RUN)
		_sq_v -= 5.0
		_puff()


func _after_move(delta: float, vy_before: float, course: Node) -> void:
	var on_floor := is_on_floor()
	# landing
	if on_floor and not _was_floor:
		var impact := -_prev_vy
		if state == S_TUMBLE and impact > 4.0 and _bounces < 2:
			velocity.y = impact * 0.42  # comical bounce
			_bounces += 1
			_sq_v += impact * 0.9
			if main != null:
				main.runner_sound(self, "bounce", -8.0, 1.3 + _bounces * 0.15)
		elif impact > 3.0:
			_sq_v += minf(impact, 16.0) * 0.55
			if impact > 9.0 and _land_cool <= 0.0:
				_land_cool = 0.3
				_puff()
				if main != null:
					main.runner_sound(self, "land", -14.0, 1.1)
	_was_floor = on_floor
	# what are we standing on / bumping into?
	_belt = Vector3.ZERO
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider() as Node
		if col == null:
			continue
		var n := c.get_normal()
		var kind := String(col.get_meta("kind", "")) if col.has_meta("kind") else ""
		if n.y > 0.6:
			match kind:
				"belt":
					var bo: Node = col.get_meta("belt_obj", null)
					if bo != null and bo.has_method("velocity"):
						_belt = bo.call("velocity")
				"bounce":
					if _pad_cool <= 0.0 and state != S_DONE:
						_pad_cool = 0.4
						velocity.y = BOUNCE_V
						var pad: Node3D = col.get_meta("pad", null)
						if pad != null:
							_push += (pad.global_basis * Vector3.FORWARD) * 3.5
						_sq_v -= 10.0
						if state == S_DIVE or state == S_TUMBLE:
							_set_state(S_RUN)
						if main != null:
							main.on_runner_pad(self, pad, "bounce")
				"boost":
					if boost_t < 2.0 and main != null:
						main.on_runner_pad(self, col.get_meta("pad", null), "boost")
					give_boost(2.6)
				"goo":
					main.on_runner_fell(self)
					return
			if col.has_meta("slippery") and bool(col.get_meta("slippery")):
				var fn := get_floor_normal()
				_push += Vector3(fn.x, 0.0, fn.z) * 22.0 * delta
		elif absf(n.y) < 0.5:
			match kind:
				"fake_door":
					if _door_cool <= 0.0:
						_door_cool = 0.5
						_push = Vector3(n.x, 0.0, n.z).normalized() * 7.5
						velocity.y = 4.0
						_ctl = Vector3.ZERO
						_sq_v += 6.0
						if main != null:
							main.on_runner_door(self, col, false)
				"door":
					if _door_cool <= 0.0:
						_door_cool = 0.3
						if main != null:
							main.on_runner_door(self, col, true)
				"bumper":
					if _door_cool <= 0.0 and state == S_RUN:
						_door_cool = 0.35
						_push += Vector3(n.x, 0.0, n.z).normalized() * 5.5
						velocity.y = maxf(velocity.y, 2.5)
						_sq_v += 4.0
						if main != null:
							main.runner_sound(self, "boing", -10.0, 1.4)
	# hazards: sweepers, hammers, balls, foam
	if invuln_t <= 0.0 and state != S_TUMBLE and state != S_DONE:
		var imp: Vector3 = course.hazard_hit(self)
		if imp == Vector3.ZERO and main != null:
			imp = main.dynamic_hit(self)
		if imp != Vector3.ZERO:
			knock(imp)
	# soft bumps with other runners
	if main != null and state != S_LEDGE:
		var b: Vector3 = main.bump_push(self)
		if b != Vector3.ZERO:
			_push += b * delta
	# fell off?
	if global_position.y < float(course.get("kill_y")):
		main.on_runner_fell(self)
		return
	if vy_before > 0.0 and is_on_ceiling():
		velocity.y = minf(velocity.y, 0.0)
	main.on_runner_moved(self, delta)


func _puff() -> void:
	if puff != null and visible:
		puff.restart()
		puff.emitting = true


# --- Puppet (control == "puppet") ----------------------------------------------------------------

## A network update for a puppet: position, facing and animation state.
func set_net(pos: Vector3, yaw: float, st: int) -> void:
	if not _net_has or pos.distance_to(global_position) > 6.0:
		global_position = pos
		_last_pos = pos
	net_pos = pos
	net_yaw = yaw
	_net_has = true
	if st != net_state:
		if st == S_TUMBLE:
			_spin_axis = Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)).normalized()
			_spin_rate = randf_range(9.0, 14.0)
		if st == S_RUN and net_state == S_TUMBLE:
			_sq_v -= 8.0
		net_state = st
		_state_t = 0.0
	state = st
	visible = st != S_HIDDEN and st != S_RESPAWN


# --- Every frame: animation ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if control == "puppet":
		var p := global_position
		var to := net_pos + est_vel * 0.03
		global_position = p.lerp(to, 1.0 - exp(-16.0 * delta))
		face_yaw = lerp_angle(face_yaw, net_yaw, 1.0 - exp(-14.0 * delta))
		_state_t += delta
		if state == S_DONE:
			_celebrate += delta
	var v := (global_position - _last_pos) / maxf(delta, 0.0001)
	if v.length() > 40.0:
		v = Vector3.ZERO
	est_vel = est_vel.lerp(v, 1.0 - exp(-12.0 * delta))
	_last_pos = global_position
	_animate(delta)


func _animate(delta: float) -> void:
	if pivot == null or not visible:
		if shadow != null:
			shadow.visible = false
		return
	var hv := Vector2(est_vel.x, est_vel.z)
	var spd := hv.length()
	var airborne := absf(est_vel.y) > 1.2 if control == "puppet" else not is_on_floor()
	# jelly squash spring
	_sq_v += (-_sq * 170.0 - _sq_v * 9.0) * delta
	_sq = clampf(_sq + _sq_v * delta, -0.35, 0.4)
	if airborne and est_vel.y > 1.0:
		_sq = lerpf(_sq, -0.12, 1.0 - exp(-6.0 * delta))
	var bean := pivot.get_child(0) as Node3D
	bean.scale = Vector3(1.0 + _sq * 0.55, 1.0 - _sq, 1.0 + _sq * 0.55)
	# lean into movement (spring)
	var want_lean := Vector2.ZERO
	if spd > 0.5 and state == S_RUN:
		var local_v := Basis(Vector3.UP, -_vis_yaw) * Vector3(est_vel.x, 0.0, est_vel.z)
		want_lean = Vector2(clampf(local_v.z * 0.03, -0.22, 0.22), clampf(-local_v.x * 0.02, -0.15, 0.15))
	_lean_v += ((want_lean - _lean) * 120.0 - _lean_v * 11.0) * delta
	_lean += _lean_v * delta
	_vis_yaw = lerp_angle(_vis_yaw, face_yaw, 1.0 - exp(-18.0 * delta))
	_blink_t += delta
	match state:
		S_TUMBLE:
			pivot.rotate(_spin_axis, _spin_rate * delta)
			pivot.position.y = 0.45
			_limbs_flail(delta)
		S_DIVE:
			var pitch := lerpf(pivot.rotation.x, -1.35, 1.0 - exp(-14.0 * delta))
			pivot.rotation = Vector3(pitch, _vis_yaw, 0.0)
			pivot.position.y = 0.3
			for a in arms:
				a.rotation = a.rotation.lerp(Vector3(-2.9, 0.0, 0.0), 1.0 - exp(-14.0 * delta))
		S_LEDGE:
			pivot.rotation = Vector3(0.0, _vis_yaw, 0.0)
			pivot.position.y = 0.0
			for a in arms:
				a.rotation = a.rotation.lerp(Vector3(-3.0, 0.0, 0.0), 1.0 - exp(-18.0 * delta))
		_:
			# back upright quickly after a tumble / dive
			var cur := pivot.quaternion
			var up := Quaternion(Vector3.UP, _vis_yaw) * Quaternion(Vector3.RIGHT, _lean.x) * Quaternion(Vector3.BACK, _lean.y)
			pivot.quaternion = cur.slerp(up, 1.0 - exp(-20.0 * delta))
			pivot.position.y = lerpf(pivot.position.y, 0.0, 1.0 - exp(-16.0 * delta))
			_limbs_walk(delta, spd, airborne)
	# extras
	if boost_fx != null:
		boost_fx.emitting = boost_t > 0.0 or (control == "puppet" and spd > RUN_SPEED * 1.25)
	if crown != null and crown.visible:
		crown.rotation.y += delta * 1.5
	if tail != null and tail.visible:
		tail.rotation.x = sin(_blink_t * 9.0) * 0.25
		tail.rotation.y = sin(_blink_t * 6.0) * 0.3
	if invuln_t > 0.0 and state == S_RUN:
		body_mi.visible = fmod(invuln_t * 12.0, 1.0) < 0.7
	else:
		body_mi.visible = true
	if marker != null:
		marker.rotation.y += delta * 2.0
		marker.position.y = HEIGHT + 1.3 + sin(_blink_t * 3.0) * 0.12
		var lbl := get_node_or_null("MarkerLabel") as Label3D
		if lbl != null:
			lbl.position.y = marker.position.y + 0.55
			var bp: Vector3 = marker.get_meta("booth", Vector3.ZERO)
			var to := bp - lbl.global_position
			to.y = 0.0
			if to.length() > 0.1:
				lbl.global_rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)
	_update_shadow()


func _limbs_walk(delta: float, spd: float, airborne: bool) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	if airborne:
		for i in arms.size():
			var s := -1.0 if i == 0 else 1.0
			arms[i].rotation = arms[i].rotation.lerp(Vector3(-0.4, 0.0, s * 2.2), k)
		for i2 in feet.size():
			feet[i2].position = feet[i2].position.lerp(Vector3((-1.0 if i2 == 0 else 1.0) * 0.15, 0.12, 0.05 if i2 == 0 else -0.05), k)
			feet[i2].rotation.x = lerpf(feet[i2].rotation.x, 0.4, k)
		return
	if state == S_DONE or (control == "puppet" and net_state == S_DONE):
		_celebrate += delta
		for i in arms.size():
			var s2 := -1.0 if i == 0 else 1.0
			arms[i].rotation = Vector3(0.0, 0.0, s2 * (2.4 + sin(_celebrate * 10.0 + i) * 0.4))
	if spd > 0.4:
		_walk += delta * clampf(spd * 2.4, 4.0, 18.0)
		var sw := sin(_walk)
		for i in feet.size():
			var ph := sw if i == 0 else -sw
			feet[i].position = Vector3((-1.0 if i == 0 else 1.0) * 0.15, maxf(0.0, -cos(_walk + (0.0 if i == 0 else PI))) * 0.12, ph * 0.18)
			feet[i].rotation.x = ph * 0.3
		if state != S_DONE:
			for i in arms.size():
				var ph2 := -sw if i == 0 else sw
				arms[i].rotation = Vector3(ph2 * 0.9, 0.0, (-1.0 if i == 0 else 1.0) * 0.25)
		pivot.position.y = absf(sin(_walk)) * 0.05
	else:
		for i in feet.size():
			feet[i].position = feet[i].position.lerp(Vector3((-1.0 if i == 0 else 1.0) * 0.15, 0.0, 0.0), k)
			feet[i].rotation.x = lerpf(feet[i].rotation.x, 0.0, k)
		if state != S_DONE:
			for i in arms.size():
				var idle := sin(_blink_t * 2.0 + i) * 0.08
				arms[i].rotation = arms[i].rotation.lerp(Vector3(idle, 0.0, (-1.0 if i == 0 else 1.0) * 0.18), k)


func _limbs_flail(_delta: float) -> void:
	for i in arms.size():
		arms[i].rotation = Vector3(sin(_state_t * 22.0 + i * 2.0) * 1.2, 0.0, (-1.0 if i == 0 else 1.0) * (1.8 + sin(_state_t * 17.0) * 0.6))
	for i2 in feet.size():
		feet[i2].position = Vector3((-1.0 if i2 == 0 else 1.0) * 0.15, 0.05 + absf(sin(_state_t * 19.0 + i2)) * 0.12, sin(_state_t * 21.0 + i2 * 2.0) * 0.15)


func _update_shadow() -> void:
	if shadow == null:
		return
	var p := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p + Vector3.DOWN * 12.0, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		shadow.visible = false
		return
	var hp: Vector3 = hit["position"]
	var h := p.y - hp.y
	var k := clampf(1.0 - h * 0.1, 0.35, 1.0)
	shadow.visible = true
	shadow.global_position = hp + Vector3.UP * 0.03
	shadow.scale = Vector3(k, 1.0, k)


## Encoded animation state for the network (TV -> host as the "pitch" of send_state).
func anim_code() -> int:
	return state


## Team colour band (TEAM courses), or hide it with team = -1.
func set_team(t: int, color: Color) -> void:
	team = t
	if band == null:
		return
	band.visible = t >= 0
	if t >= 0:
		band.material_override = MeshKit.material(color, 0.6)


func set_tail(on: bool) -> void:
	has_tail = on
	if tail != null:
		tail.visible = on


func set_crown(on: bool) -> void:
	if crown != null:
		crown.visible = on
