extends CharacterBody3D
## A TV player: a first-person runner who fetches ingredients and carries finished plates to customers.
## Controller: left stick move, right stick look, A / RT / X interact.
## Keyboard set 0: WASD + mouse, E / Space / click interact.  Set 1: arrows (left/right turn), Enter interact.

const L := preload("res://games/kitchen_rush/layout.gd")

const SPEED := 5.2
const EYE_HEIGHT := 1.5
const STICK_YAW_SPEED := 3.0
const STICK_PITCH_SPEED := 2.0
const KEY_TURN_SPEED := 2.6
const MOUSE_SENS := 0.0028
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "use": KEY_E, "use2": KEY_SPACE},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "use": KEY_ENTER, "use2": KEY_KP_ENTER},
]

var index := 1
var joy := -1
var color := Color.WHITE
var main
var camera: Camera3D
var hud
var yaw := PI
var pitch := -0.15
var remote := false  # host: driven by the TV machine
var ghost := false
var vr := false
var active := true
var key_set := -1  # -1: no keyboard (controller only)
var lost_joy := -1  # the controller that disconnected from this player (to rejoin on reconnect)
var lost_t := 0.0
var mouse_look := false
var carry_kind := ""  # "", an ingredient kind, "plate:<RECIPE>" or "extinguisher"
var carry = null  # host: the carried item node
var net_target := Vector3.ZERO
var net_started := false
var use_was_held := false
var bob_t := 0.0
var pivot: Node3D
var tag: Label3D
var bot_move := Vector3.ZERO  # tests: a movement wish in world space


## Render layer for this runner's body (hidden from its own camera). Layer 7 (value 64) is the chef's
## viewmodel, so runners 5 and 6 skip ahead to layers 9 and 10.
func body_layer() -> int:
	return 2 << index if index <= 4 else 2 << (index + 2)


## Every player body layer: the chef (2) and runners 1..6.
const ALL_BODIES := 2 | 4 | 8 | 16 | 32 | 256 | 512


func camera_cull_mask() -> int:
	return ((1 | ALL_BODIES) & ~body_layer()) | guide_layer()


## This runner's own guide arrow lives on its own layer (layers 11-16), so only their camera sees it.
func guide_layer() -> int:
	return 1024 << (index - 1)


func _ready() -> void:
	add_to_group("kr_runners")
	collision_layer = 2
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.8
	add_child(cs)
	net_target = position
	pivot = Node3D.new()
	add_child(pivot)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.32
	cap.height = 1.35
	cap.radial_segments = 16
	cap.rings = 4
	body.mesh = cap
	body.material_override = main.mat(color)
	body.position.y = 0.68
	pivot.add_child(body)
	var apron := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.42, 0.55, 0.06)
	apron.mesh = am
	apron.material_override = main.mat(Color.WHITE)
	apron.position = Vector3(0, 0.6, -0.3)
	pivot.add_child(apron)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.22
	hm.height = 0.44
	hm.radial_segments = 14
	hm.rings = 7
	head.mesh = hm
	head.material_override = main.mat(Color(1.0, 0.82, 0.68))
	head.position.y = 1.5
	pivot.add_child(head)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.035
		em.height = 0.07
		em.radial_segments = 8
		em.rings = 4
		eye.mesh = em
		eye.material_override = main.mat(Color(0.1, 0.1, 0.15))
		eye.position = Vector3(side * 0.08, 1.54, -0.2)
		pivot.add_child(eye)
	main.add_chef_hat(pivot, Vector3(0, 1.68, 0), 0.75)
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
	main.set_layers(pivot, body_layer())


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 75.0
	camera.near = 0.05
	_update_camera()


func set_active(on: bool) -> void:
	active = on
	visible = on
	collision_layer = 2 if on else 0
	use_was_held = true  # the button that made us join must be released before it does anything
	if not on:
		velocity = Vector3.ZERO
		bot_move = Vector3.ZERO


## Where a carried thing is held: in front of the chest, low in the view.
func carry_point() -> Vector3:
	return global_position + Basis(Vector3.UP, yaw) * Vector3(0.12, 1.12, -0.5)


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused and not remote:
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.3)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if remote:
		global_position = global_position.lerp(net_target, 1.0 - exp(-20.0 * delta))
		pivot.rotation.y = yaw
		return
	_read_look(delta)
	var move := _read_move() + bot_move
	velocity = move.limit_length(1.0) * SPEED
	move_and_slide()
	position.y = 0.0
	bob_t += velocity.length() * delta * 1.8
	_update_camera()
	main.net.send_state(global_position, yaw, pitch, index)
	var use := _use_held()
	if use and not use_was_held:
		press_use()
	use_was_held = use


## Interact: pick up / drop / serve / spray. The host decides what actually happens.
func press_use() -> void:
	if main.net.mode == "client":
		main.net.send_action("use", [], index)
		main.sfx_local("pickup", -14.0, 1.6)
	else:
		main.runner_use(self)


func _update_camera() -> void:
	pivot.rotation.y = yaw
	if camera == null:
		return
	var bob := sin(bob_t) * 0.04
	camera.global_position = global_position + Vector3(0, EYE_HEIGHT + bob, 0)
	camera.rotation = Vector3(pitch, yaw, 0.0)


func apply_remote_state(pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	net_target = Vector3(pos.x, 0.0, pos.z)
	yaw = new_yaw
	pitch = new_pitch
	if not net_started:
		net_started = true
		global_position = net_target


## Client: the host's view of this runner: [pos, yaw, active, carry_kind]
func apply_net_state(st: Array) -> void:
	carry_kind = st[3]
	var on: bool = st[2]
	if on != active:
		set_active(on)
		main.on_player_activity_changed(self)


func net_state() -> Array:
	return [global_position, yaw, active, carry_kind]


# --- Input -------------------------------------------------------------------

func keys() -> int:
	return key_set


func _key(action: String) -> bool:
	if key_set < 0 or key_set >= KEYS.size():
		return false
	return Input.is_physical_key_pressed(KEYS[key_set][action])


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
	var v := Vector2.ZERO
	if keys() == 0:
		v = Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	elif keys() == 1:
		v.y = float(_key("down")) - float(_key("up"))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)))
	return Basis(Vector3.UP, yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)


func _use_held() -> bool:
	if _key("use") or _key("use2"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_A) or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	return false


## Any input from this player's controls (used to wake up a waiting player).
func any_input() -> bool:
	return _use_held()
