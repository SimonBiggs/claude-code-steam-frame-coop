extends Node3D
## A TV player: a marble rolling around the tilting board, seen from a third-person chase camera.
## Lives under the board node, so `lp` (board-local position, y up from the floor) is its transform.
## Local marbles simulate themselves (also on the TV machine: instant response); on the host, the
## TV machine's marbles are "remote" and just follow the positions it sends.

const R := 0.028
const STEER := 0.45  # own push (m/s^2); the board's tilt gives up to ~0.9
const DAMP := 1.2
const MAX_SPEED := 0.9
const NO_KEYS := 99

var index := 1
var main
var board
var color := Color.WHITE
var remote := false
var ghost := false
var vr := false
var active := false
var joy := -1
var key_set := NO_KEYS  # 0: arrows (local P2), 1: WASD/arrows + mouse (TV machine P2)
var mouse_look := false
var camera: Camera3D
var hud: Control
var hud_label: Label
var pad_lost_t := -1.0

var lp := Vector3(0, R, 0)
var v := Vector2.ZERO
var yaw := 0.0
var pitch := 0.0
var falling := false
var fall_t := 0.0
var vy := 0.0
var home := false
var checkpoint := -1
var spawn := Vector2.ZERO
var falls := 0
var bot_steer := Vector2.ZERO
var bot := false
var cam_idle_t := 0.0
var mouse_dx := 0.0
var target_lp := Vector3(0, R, 0)
var net_started := false
var last_lp := Vector3.ZERO
var est_v := Vector2.ZERO
var wall_click_t := 0.0

var ball: MeshInstance3D
var shine: MeshInstance3D


func _ready() -> void:
	ball = MeshInstance3D.new()
	ball.mesh = main.sphere_mesh(R)
	var m: StandardMaterial3D = main.make_material(color, 0.25)
	m.roughness = 0.2
	m.metallic = 0.1
	ball.material_override = m
	add_child(ball)
	# A white band so you can see it roll.
	shine = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = R * 0.93
	tm.outer_radius = R * 1.06
	tm.rings = 12
	tm.ring_segments = 4
	shine.mesh = tm
	shine.material_override = main.make_material(Color(1, 1, 1), 0.3)
	ball.add_child(shine)
	visible = active
	position = lp


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		home = false


func is_local() -> bool:
	return not remote and not ghost


## Back to the level's start cell (spread out a bit so marbles don't spawn inside each other).
func reset_to_start() -> void:
	checkpoint = -1
	home = false
	falling = false
	var n: int = board.starts.size()
	var s: Vector2 = board.starts[index % n]
	var off := Vector2(((index - 1) % 3 - 1) * 0.022, (((index - 1) / 3) % 2) * 0.02 - 0.01)
	spawn = s + off
	_place(spawn)
	yaw = 0.0


func _place(p: Vector2) -> void:
	lp = Vector3(p.x, R, p.y)
	target_lp = lp
	v = Vector2.ZERO
	vy = 0.0
	position = lp


func respawn() -> void:
	falling = false
	fall_t = 0.0
	var p := spawn
	if checkpoint >= 0 and checkpoint < board.checkpoints.size():
		p = board.checkpoints[checkpoint]
	_place(p)
	main.on_marble_respawn(self)


# --- Input -----------------------------------------------------------------------

func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func move_input() -> Vector2:
	var s := Vector2.ZERO
	if key_set == 0:
		s = Vector2(_key(KEY_RIGHT) - _key(KEY_LEFT), _key(KEY_DOWN) - _key(KEY_UP))
	elif key_set == 1:
		s = Vector2(maxf(_key(KEY_D), _key(KEY_RIGHT)) - maxf(_key(KEY_A), _key(KEY_LEFT)),
			maxf(_key(KEY_S), _key(KEY_DOWN)) - maxf(_key(KEY_W), _key(KEY_UP)))
	if joy >= 0:
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() > 0.15:
			s += st
	return s.limit_length(1.0)


func cam_input() -> float:
	var c := 0.0
	if key_set == 1:
		c += _key(KEY_E) - _key(KEY_Q)
	if joy >= 0:
		var rx := Input.get_joy_axis(joy, JOY_AXIS_RIGHT_X)
		if absf(rx) > 0.2:
			c += rx
	return c


func action_pressed() -> bool:
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set == 1 and Input.is_physical_key_pressed(KEY_SPACE)


func _input(event: InputEvent) -> void:
	if not mouse_look or not active:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_dx += mm.relative.x


# --- Simulation --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active or board == null:
		return
	if remote or ghost:
		return
	if main.state != "play":
		if main.state == "intro" and not home:
			_place(spawn if checkpoint < 0 else board.checkpoints[checkpoint])
		return
	sim(delta)
	if main.net.mode == "client":
		main.net.send_state(lp, yaw, pitch, index)


func sim(delta: float) -> void:
	if home:
		_sit_in_goal(delta)
		return
	if falling:
		fall_t += delta
		vy -= 2.5 * delta
		lp.y += vy * delta
		var hp := Vector2(lp.x, lp.z) + v * delta * 0.4
		lp.x = hp.x
		lp.z = hp.y
		position = lp
		if fall_t > 1.1:
			respawn()
		return
	var steer := bot_steer if bot else _steer_dir()
	var a: Vector2 = board.gravity_local() + steer * STEER + board.hole_pull(Vector2(lp.x, lp.z))
	v += a * delta
	v *= exp(-DAMP * delta)
	v = v.limit_length(MAX_SPEED)
	var p := Vector2(lp.x, lp.z)
	var impact := 0.0
	for i in 2:
		p += v * delta * 0.5
		var res: Array = board.collide(p, v, R)
		p = res[0]
		v = res[1]
		impact = maxf(impact, float(res[2]))
		var bumped: int = res[3]
		if bumped >= 0:
			main.on_bump(self, bumped)
	p = _push_marbles(p)
	wall_click_t -= delta
	if impact > 0.25 and wall_click_t <= 0.0:
		wall_click_t = 0.15
		main.on_wall_hit(self, impact)
	lp = Vector3(p.x, R, p.y)
	# Roll the ball visually.
	var dist := v.length() * delta
	if dist > 0.00001:
		var axis := Vector3(v.y, 0.0, -v.x).normalized()
		ball.rotate(axis, dist / R)
	position = lp
	if not board.supported(p):
		falling = true
		fall_t = 0.0
		vy = -0.1
		falls += 1
		main.on_marble_fell(self)
		return
	var cp: int = board.checkpoint_at(p)
	if cp >= 0 and cp != checkpoint:
		checkpoint = cp
		main.on_checkpoint(self)
	if board.in_goal(p):
		home = true
		main.on_marble_home(self)


## Stick direction turned from camera space into board space.
func _steer_dir() -> Vector2:
	var s := move_input()
	if s.length() < 0.01:
		return Vector2.ZERO
	var w := Basis(Vector3.UP, yaw) * Vector3(s.x, 0.0, s.y)
	return Vector2(w.x, w.z).limit_length(1.0)


func _push_marbles(p: Vector2) -> Vector2:
	for o in main.players:
		if o == self or o.index == 0 or not o.active or o.home or o.falling:
			continue
		var op := Vector2(o.lp.x, o.lp.z)
		var d := p - op
		var l := d.length()
		if l < R * 2.0 and l > 0.0001:
			var n := d / l
			p = op + n * R * 2.0
			var vn := v.dot(n)
			if vn < 0.0:
				v -= n * vn * 1.1
				if o.is_local():
					o.v += n * vn * 0.9
	return p


func _sit_in_goal(delta: float) -> void:
	var k: int = 0
	for o in main.players:
		if o.index > 0 and o.index < index and o.active and o.home:
			k += 1
	var ang: float = main.board.t * 1.6 + k * TAU / 6.0
	var goal: Vector2 = board.goal
	var target := Vector3(goal.x + cos(ang) * 0.05, 0.075, goal.y + sin(ang) * 0.05)
	lp = lp.lerp(target, 1.0 - exp(-6.0 * delta))
	position = lp
	ball.rotate_y(delta * 3.0)


# --- Remote (host) / camera ---------------------------------------------------------

func apply_remote_state(pos: Vector3, y: float, p: float) -> void:
	target_lp = pos
	yaw = y
	pitch = p
	net_started = true


func _process(delta: float) -> void:
	if remote and active:
		if lp.distance_to(target_lp) > 0.15:
			lp = target_lp
		else:
			lp = lp.lerp(target_lp, 1.0 - exp(-18.0 * delta))
		falling = lp.y < R * 0.5
		var d := Vector2(lp.x - last_lp.x, lp.z - last_lp.z)
		if delta > 0.0:
			est_v = est_v.lerp(d / delta, 0.2)
			if est_v.length() > 0.001:
				var axis := Vector3(est_v.y, 0.0, -est_v.x).normalized()
				ball.rotate(axis, d.length() / R)
		last_lp = lp
		position = lp
	elif is_local():
		est_v = v
	if camera != null and active:
		_update_camera(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)


func _update_camera(delta: float) -> void:
	var turn := cam_input()
	if mouse_dx != 0.0:
		yaw -= mouse_dx * 0.004
		mouse_dx = 0.0
		cam_idle_t = 0.0
	if absf(turn) > 0.01:
		yaw -= turn * 2.4 * delta
		cam_idle_t = 0.0
	else:
		cam_idle_t += delta
	# Drift behind the marble's motion when the player isn't steering the camera.
	if cam_idle_t > 0.8 and v.length() > 0.12 and not home and not falling:
		var want := atan2(-v.x, -v.y)
		yaw = lerp_angle(yaw, want, 1.0 - exp(-1.2 * delta))
	var target: Vector3 = global_position if not falling else board.to_global(Vector3(lp.x, R, lp.z))
	var back := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 0.22)
	var want_pos := target + back + Vector3(0, 0.12, 0)
	if not camera.has_meta("placed"):
		camera.set_meta("placed", true)
		camera.global_position = want_pos
	camera.global_position = camera.global_position.lerp(want_pos, 1.0 - exp(-8.0 * delta))
	var look := target + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.08)
	if camera.global_position.distance_to(look) > 0.01:
		camera.look_at(look, Vector3.UP)
