extends Node3D
## A TV crew member walking round the workshop in first person: read the blueprint boards out loud
## to the pilot, carry fuel canisters (walk into one to pick it up, walk to the glowing hatch by the
## rocket to deliver it) and hold ACTION by a leaky pipe to fix it.
## Controller: left stick move, right stick look, A / X / RT action.
## Keyboard set 0: WASD + mouse (or Q / E to turn), Space / F / click action.  Set 1: arrows (turn), Enter / Ctrl action.

const SPEED := 4.2
const EYE_HEIGHT := 1.5
const STICK_YAW_SPEED := 2.6
const STICK_PITCH_SPEED := 1.8
const KEY_TURN_SPEED := 2.2
const MOUSE_SENS := 0.0028
const FIX_TIME := 2.5
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "action": KEY_SPACE, "action2": KEY_F, "turn_l": KEY_Q, "turn_r": KEY_E},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "action": KEY_ENTER, "action2": KEY_CTRL},
]

var index := 1
var joy := -1
var color := Color.WHITE
var main
var camera: Camera3D
var yaw := 0.0
var pitch := -0.1
var bob_t := 0.0
var key_set := 1
var mouse_look := false
var remote := false
var ghost := false
var vr := false
var active := true
var net_target := Vector3.ZERO
var net_started := false
var bot_move := Vector3.ZERO
var bot_action := false
var fix_send := 0.0
var fix_acc := 0.0
var spark_t := 0.0
var fixing := false
var pivot: Node3D


func body_layer() -> int:
	return 2 << index


func camera_cull_mask() -> int:
	return 0xFFFFF & ~body_layer() & ~main.PANEL_LAYER


func _ready() -> void:
	add_to_group("players")
	yaw = rotation.y
	rotation.y = 0.0
	net_target = position
	pivot = Node3D.new()
	add_child(pivot)
	var overall: StandardMaterial3D = main.make_material(color, 0.1)
	var body := MeshInstance3D.new()
	body.mesh = main.capsule_mesh(0.33, 1.25)
	body.material_override = overall
	body.position.y = 0.65
	pivot.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = main.sphere_mesh(0.2)
	head.material_override = main.make_material(Color(1.0, 0.8, 0.65), 0.0)
	head.position.y = 1.45
	pivot.add_child(head)
	var hat := MeshInstance3D.new()
	hat.mesh = main.sphere_mesh(0.22)
	hat.material_override = main.make_material(Color(1.0, 0.82, 0.15), 0.1)
	hat.scale = Vector3(1, 0.6, 1)
	hat.position.y = 1.56
	pivot.add_child(hat)
	var visor := MeshInstance3D.new()
	visor.mesh = main.box_mesh(Vector3(0.3, 0.03, 0.16))
	visor.material_override = hat.material_override
	visor.position = Vector3(0, 1.53, -0.2)
	pivot.add_child(visor)
	var tag := Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = color
	tag.position.y = 2.0
	pivot.add_child(tag)
	main.set_layers(pivot, body_layer())
	main.set_layers(tag, main.MANUAL_LAYER)  # name tags are for the crew


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 75.0
	camera.near = 0.05
	_update_camera()


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.3)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if remote:
		position = position.lerp(net_target, 1.0 - exp(-18.0 * delta))
		pivot.rotation.y = yaw
		return
	_read_look(delta)
	var move := _read_move()
	bob_t += move.length() * delta * 7.0
	position = main.clamp_walk(position + move * SPEED * delta)
	pivot.rotation.y = yaw
	_update_camera()
	main.net.send_state(position, yaw, pitch, index)
	_update_fix(delta)


func _update_camera() -> void:
	if camera == null:
		return
	camera.global_position = global_position + Vector3(0, EYE_HEIGHT + sin(bob_t) * 0.03, 0)
	camera.rotation = Vector3(pitch, yaw, 0.0)


## Hold ACTION next to the leaky pipe to fix it (the host keeps the score).
func _update_fix(delta: float) -> void:
	fixing = action_held() and main.pipe_near(global_position)
	if not fixing:
		return
	spark_t -= delta
	if spark_t <= 0.0:
		spark_t = 0.2
		main.puff(main.pipe_point() + Vector3(randf_range(-0.2, 0.2), 0.1, 0), Color(0.75, 0.85, 1.0), 4, 0.04)
		main.local_sound("fix", -14.0, randf_range(0.8, 1.2))
		if joy >= 0:
			Input.start_joy_vibration(joy, 0.2, 0.1, 0.08)
	var amount := delta / FIX_TIME
	if main.net.mode == "client":
		fix_acc += amount
		fix_send -= delta
		if fix_send <= 0.0:
			fix_send = 0.12
			main.net.send_action("fix", [fix_acc], index)
			fix_acc = 0.0
	else:
		main.fix_pipe(index, amount)


# --- Input -------------------------------------------------------------------

func _key(action: String) -> bool:
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
	if key_set == 1:
		yaw -= (float(_key("right")) - float(_key("left"))) * KEY_TURN_SPEED * delta
	else:
		yaw -= (float(_key("turn_r")) - float(_key("turn_l"))) * KEY_TURN_SPEED * delta


func _read_move() -> Vector3:
	if bot_move != Vector3.ZERO:
		return bot_move.limit_length(1.0)
	var v := Vector2.ZERO
	if key_set == 0:
		v = Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	else:
		v.y = float(_key("down")) - float(_key("up"))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)))
	return Basis(Vector3.UP, yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)


func action_held() -> bool:
	if bot_action:
		return true
	if _key("action") or _key("action2"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_A) or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	return false


# --- Networked co-op ---------------------------------------------------------

func set_active(on: bool) -> void:
	active = on
	visible = on


## Host: latest position and view of a TV player.
func apply_remote_state(pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	net_target = Vector3(pos.x, 0.0, pos.z)
	yaw = new_yaw
	pitch = new_pitch
	if not net_started:
		net_started = true
		position = net_target


## Client: [pos, yaw, pitch, active] from the host. Our own movement stays local.
func apply_net_state(st: Array) -> void:
	var on: bool = st[3]
	if on != active:
		set_active(on)
		main.on_player_activity_changed(self)
