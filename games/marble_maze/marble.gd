extends Node3D
## A TV player: a marble rolling around the tilting board, seen from a third-person chase camera.
## Lives under the board node, so `lp` (board-local position, y up from the floor) is its transform.
## Local marbles simulate themselves (also on the TV machine: instant response); on the host, the
## TV machine's marbles are "remote" and just follow the positions it sends.
## Teamwork: marbles bump softly (a friend can never be shoved hard, and never over an edge or into a
## hole), and once you're HOME you steer a GUIDE STAR: touch a friend's marble with it to tow them
## along. Every marble has a little face that looks where it's rolling (and blinks).

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
var face: Node3D
var eyes: MeshInstance3D
var face_yaw := 0.0
var blink_t := 2.0
var squash := 0.0
var tp_lock := Vector2i(-99, -99)
var guide := Vector2.ZERO  # home marbles: the guide star's board position
var guide_on := false
var guide_star: MeshInstance3D
var boop_t := 0.0
var towing := 0.0
var tilt_only := false  # SIMPLE_MODE solo VR: the giant's own marble, rolled only by tilting the board
var safe := Vector2.ZERO  # SIMPLE_MODE: the last safe floor cell centre (a fall pops you back here)


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
	# A little face (doesn't roll: it turns to look where the marble is going).
	face = Node3D.new()
	add_child(face)
	eyes = MeshInstance3D.new()
	eyes.mesh = main.eyes_mesh()
	eyes.material_override = main.vertex_mat()
	eyes.position = Vector3(0, R * 0.32, -R * 0.9)
	face.add_child(eyes)
	visible = active
	position = lp


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		home = false
		guide_on = false


func is_local() -> bool:
	return not remote and not ghost


## Back to the level's start cell (spread out a bit so marbles don't spawn inside each other).
func reset_to_start() -> void:
	checkpoint = -1
	home = false
	falling = false
	guide_on = false
	towing = 0.0
	tp_lock = Vector2i(-99, -99)
	var n: int = board.starts.size()
	var s: Vector2 = board.starts[index % n]
	var off := Vector2(((index - 1) % 3 - 1) * 0.022, (((index - 1) / 3) % 2) * 0.02 - 0.01)
	spawn = s + off
	safe = spawn
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
	if main.simple:
		_place(safe)  # just back nearby, with a boing (main.on_marble_respawn)
		lp.y = R + 0.04
		vy = 0.4
		position = lp
		main.on_marble_respawn(self)
		return
	var p := spawn
	checkpoint = main.best_checkpoint(checkpoint)  # the team's furthest checkpoint: nobody gets left behind
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
	if main.state != "play" and main.state != "practice":
		if main.state == "intro" and not home:
			_place(spawn if checkpoint < 0 else board.checkpoints[checkpoint])
		return
	sim(delta)
	if main.net.mode == "client":
		if home and guide_on:
			main.net.send_state(Vector3(guide.x, 5.0, guide.y), yaw, pitch, index)  # y = 5: "this is my guide star"
		else:
			main.net.send_state(lp, yaw, pitch, index)


func sim(delta: float) -> void:
	if home:
		_sit_in_goal(delta)
		if not main.simple:
			_steer_guide(delta)
		return
	if lp.y > R:  # SIMPLE_MODE: the little hop after popping back up
		vy -= 2.5 * delta
		lp.y = maxf(R, lp.y + vy * delta)
	if falling:
		fall_t += delta
		vy -= 2.5 * delta
		lp.y += vy * delta
		var hp := Vector2(lp.x, lp.z) + v * delta * 0.4
		lp.x = hp.x
		lp.z = hp.y
		position = lp
		if fall_t > (0.55 if main.simple else 1.1):
			respawn()
		return
	var steer := bot_steer if bot else _steer_dir()
	if tilt_only:
		steer = Vector2.ZERO
	var here := Vector2(lp.x, lp.z)
	var a: Vector2 = board.gravity_local() + steer * STEER * board.grip_at(here) + board.hole_pull(here) + board.boost_at(here)
	a += main.guide_pull(self, here)
	v += a * delta
	v *= exp(-board.damp_at(here) * delta)
	v = v.limit_length(0.3 if board.is_mud(here) else MAX_SPEED)
	boop_t -= delta
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
	lp = Vector3(p.x, lp.y, p.y)
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
	# Teleporters: pop out of the twin (and not straight back until you've rolled off it).
	var cell: Vector2i = board.cell_of(p)
	if cell != tp_lock:
		tp_lock = Vector2i(-99, -99)
		var dest: Vector2 = board.teleport_dest(p)
		if dest != Vector2.INF:
			var from := p
			p = dest
			lp = Vector3(p.x, R, p.y)
			position = lp
			tp_lock = board.cell_of(dest)
			main.on_teleport(self, from, dest)
	if main.simple:
		_remember_safe(p)
	var cp: int = board.checkpoint_at(p)
	if cp >= 0 and cp != checkpoint:
		checkpoint = cp
		main.on_checkpoint(self)
	if board.in_goal(p):
		home = true
		main.on_marble_home(self)


## SIMPLE_MODE: plain floor with no hole, edge or teleporter next to it is a safe place to pop back to.
func _remember_safe(p: Vector2) -> void:
	var c: Vector2i = board.cell_of(p)
	if not (board.ch(c.x, c.y) in [".", "S", "I"]):
		return
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if board.ch(c.x + dc, c.y + dr) in ["O", "_", "-", "|", "T"]:
				return
	safe = board.center(c.x, c.y)


## Stick direction turned from camera space into board space.
func _steer_dir() -> Vector2:
	var s := move_input()
	if s.length() < 0.01:
		return Vector2.ZERO
	var w := Basis(Vector3.UP, yaw) * Vector3(s.x, 0.0, s.y)
	return Vector2(w.x, w.z).limit_length(1.0)


## Marbles bump softly: you lose your own speed rather than flinging your friend, they only get a
## gentle nudge, and never one that would roll them over an edge or into a hole.
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
				v -= n * vn * 1.05  # almost all of the closing speed is soaked up
				if o.is_local():
					var nudge := -n * minf(-vn * 0.25, 0.08)
					var ahead: Vector2 = op + (o.v + nudge) * 0.25
					if board.supported(ahead) and board.supported(op + nudge.normalized() * R * 2.0):
						o.v += nudge
				if -vn > 0.12 and boop_t <= 0.0:
					boop_t = 0.6
					main.on_marble_boop(self, o)
	return p


## Home marbles steer a guide star round the board (left stick, camera-relative).
func _steer_guide(delta: float) -> void:
	if not guide_on:
		guide_on = true
		guide = board.goal
	var s := bot_steer if bot else _steer_dir()
	guide += s * 0.3 * delta
	var hs: Vector2 = board.half_size()
	guide = Vector2(clampf(guide.x, -hs.x + 0.03, hs.x - 0.03), clampf(guide.y, -hs.y + 0.03, hs.y - 0.03))


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
	yaw = y
	pitch = p
	net_started = true
	if pos.y > 1.0:
		guide = Vector2(pos.x, pos.z)
		guide_on = home
		return
	target_lp = pos


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
	if active:
		_animate_face(delta)
		_update_guide_star(delta)
	if camera != null and active:
		_update_camera(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)


## Eyes look where we're rolling and blink; a bump squashes the ball a little.
func _animate_face(delta: float) -> void:
	var vel := est_v
	if vel.length() > 0.03:
		face_yaw = lerp_angle(face_yaw, atan2(-vel.x, -vel.y), 1.0 - exp(-8.0 * delta))
	elif home:
		face_yaw += delta * 3.0
	face.rotation.y = face_yaw
	blink_t -= delta
	if blink_t <= 0.0:
		blink_t = randf_range(1.8, 4.5)
	eyes.scale = Vector3(1.0, 0.15 if blink_t < 0.12 else 1.0, 1.0)
	squash = move_toward(squash, 0.0, delta * 4.0)
	var sq := sin(squash * PI) * 0.25
	ball.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq)
	face.visible = not falling


func bump_squash() -> void:
	squash = 1.0


## The guide star floats over the board where this (home) marble's player is pointing.
func _update_guide_star(_delta: float) -> void:
	var show: bool = home and guide_on and main.state == "play"
	if guide_star == null:
		if not show:
			return
		guide_star = MeshInstance3D.new()
		guide_star.mesh = main.star_mesh()
		guide_star.material_override = main.make_material(color.lightened(0.3), 2.0)
		guide_star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		board.add_child(guide_star)
	guide_star.visible = show
	if show:
		var bob := sin(board.t * 4.0 + index) * 0.006
		guide_star.position = Vector3(guide.x, 0.05 + bob, guide.y)
		guide_star.rotation = Vector3(0.0, board.t * 2.5 + index, 0.0)
		guide_star.scale = Vector3.ONE * (0.018 if towing <= 0.0 else 0.024)


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
	if home and guide_on:
		target = board.to_global(Vector3(guide.x, R, guide.y))
	var back := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 0.22)
	var want_pos := target + back + Vector3(0, 0.12, 0)
	if not camera.has_meta("placed"):
		camera.set_meta("placed", true)
		camera.global_position = want_pos
	camera.global_position = camera.global_position.lerp(want_pos, 1.0 - exp(-8.0 * delta))
	var look := target + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.08)
	if camera.global_position.distance_to(look) > 0.01:
		camera.look_at(look, Vector3.UP)
