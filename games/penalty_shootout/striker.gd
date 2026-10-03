extends Node3D
## A TV player: a STRIKER. Players take turns at the penalty spot, seen from behind the ball.
## Your turn: move the reticle over the goal mouth with the left stick (or WASD / arrows / mouse),
## HOLD A (Space / left mouse; Enter for split-screen P2) to power up - the meter swings up and back
## down, so let go at the right moment - and release to shoot. Triggers (Q / E) bend the shot.
## Local strikers run their own aim (also on the TV machine, so it's instant); the host decides the
## shot. On the host, the TV machine's strikers are "remote": their aim arrives via apply_remote_state.

const NO_KEYS := 99
const AIM_SPEED := 3.4
const AIM_X := 4.4
const AIM_Y_MIN := 0.12
const AIM_Y_MAX := 3.0
const CHARGE_TIME := 1.1

var index := 1
var main
var color := Color.WHITE
var remote := false
var ghost := false
var vr := false
var active := false
var joy := -1
var key_set := NO_KEYS  # 0: arrows + Enter (local P2), 1: WASD/arrows + mouse + Space (TV machine P2)
var mouse_look := false
var camera: Camera3D
var hud: Control
var hud_label: Label
var power_bg: ColorRect
var power_fill: ColorRect
var pad_lost_t := -1.0

var aim := Vector2(0.0, 1.0)
var power := 0.0
var charging := false
var charge_t := 0.0
var curve := 0.0
var held_was := true
var mouse_d := Vector2.ZERO
var mouse_held := false
var goals := 0
var shots := 0
var net_started := false
var stand_at := Vector3.ZERO
var run := 0.0

# Bot hooks (tests).
var bot := false
var bot_stick := Vector2.ZERO
var bot_hold := false
var bot_curve := 0.0

var avatar: Node3D
var tag: Label3D
var legs: Array[MeshInstance3D] = []


func _ready() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	var shirt: StandardMaterial3D = main.make_material(color, 0.15)
	var torso := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.2
	cm.height = 0.72
	cm.radial_segments = 12
	cm.rings = 4
	torso.mesh = cm
	torso.material_override = shirt
	torso.position = Vector3(0, 1.2, 0)
	avatar.add_child(torso)
	var head := MeshInstance3D.new()
	head.mesh = main.sphere_mesh(0.13)
	head.material_override = main.make_material(Color(1.0, 0.8, 0.62), 0.0)
	head.position = Vector3(0, 1.68, 0)
	avatar.add_child(head)
	var hair := MeshInstance3D.new()
	hair.mesh = main.sphere_mesh(0.135)
	hair.material_override = main.make_material(color.darkened(0.5), 0.0)
	hair.scale = Vector3(1, 0.6, 1)
	hair.position = Vector3(0, 0.05, 0.01)
	head.add_child(hair)
	for s in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = main.box_mesh(Vector3(0.14, 0.85, 0.16))
		leg.material_override = main.make_material(Color(0.95, 0.95, 0.95), 0.0)
		leg.position = Vector3(s * 0.1, 0.43, 0)
		avatar.add_child(leg)
		legs.append(leg)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.font_size = 48
	tag.pixel_size = 0.006
	tag.outline_size = 12
	tag.modulate = color.lightened(0.3)
	tag.position = Vector3(0, 2.15, 0)
	avatar.add_child(tag)
	visible = active


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		charging = false
		power = 0.0


func is_local() -> bool:
	return not remote and not ghost


func prepare_turn() -> void:
	aim = Vector2(0.0, 1.0)
	power = 0.0
	charging = false
	charge_t = 0.0
	curve = 0.0
	held_was = true  # a button still held from before doesn't start charging


# --- Input -------------------------------------------------------------------------------

func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


## Aim stick in goal space: x right (as seen by the striker, = world +x), y up.
func aim_input() -> Vector2:
	if bot:
		return bot_stick
	var s := Vector2.ZERO
	if key_set == 0:
		s = Vector2(_key(KEY_RIGHT) - _key(KEY_LEFT), _key(KEY_UP) - _key(KEY_DOWN))
	elif key_set == 1:
		s = Vector2(maxf(_key(KEY_D), _key(KEY_RIGHT)) - maxf(_key(KEY_A), _key(KEY_LEFT)),
			maxf(_key(KEY_W), _key(KEY_UP)) - maxf(_key(KEY_S), _key(KEY_DOWN)))
	if joy >= 0:
		var st := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), -Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
		if st.length() > 0.15:
			s += st
		var dp := Vector2(float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)))
		s += dp
	return s.limit_length(1.0)


func charge_held() -> bool:
	if bot:
		return bot_hold
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	if key_set == 0:
		return Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER) \
			or Input.is_physical_key_pressed(KEY_CTRL)
	if key_set == 1:
		return Input.is_physical_key_pressed(KEY_SPACE) or mouse_held
	return false


func curve_input() -> float:
	if bot:
		return bot_curve
	var c := 0.0
	if key_set == 1:
		c += _key(KEY_E) - _key(KEY_Q)
	elif key_set == 0:
		c += _key(KEY_PERIOD) - _key(KEY_COMMA)
	if joy >= 0:
		c += Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT)
	return clampf(c, -1.0, 1.0)


func action_pressed() -> bool:
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set == 1 and Input.is_physical_key_pressed(KEY_SPACE)


func _input(event: InputEvent) -> void:
	if not mouse_look or not active:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_d += mm.relative
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		mouse_held = mb.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


# --- Turn ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if active and is_local():
		_local_turn(delta)
	_move_avatar(delta)
	if camera != null and active:
		_update_camera(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)
	_update_power_bar()


func _local_turn(delta: float) -> void:
	if not main.is_turn_of(self):
		charging = false
		power = 0.0
		held_was = charge_held()
		return
	var s := aim_input()
	aim += s * AIM_SPEED * delta
	if mouse_d != Vector2.ZERO:
		aim += Vector2(mouse_d.x, -mouse_d.y) * 0.006
		mouse_d = Vector2.ZERO
	aim.x = clampf(aim.x, -AIM_X, AIM_X)
	aim.y = clampf(aim.y, AIM_Y_MIN, AIM_Y_MAX)
	curve = lerpf(curve, curve_input(), 1.0 - exp(-10.0 * delta))
	var held := charge_held()
	var can: bool = main.can_shoot()
	if held and not held_was and can:
		charging = true
		charge_t = 0.0
		main.sound("charge", -10.0)
	if charging:
		if held:
			charge_t += delta
			var x := charge_t / CHARGE_TIME
			power = 1.0 - absf(1.0 - fmod(x, 2.0))
		else:
			charging = false
			var shot_power := maxf(power, 0.15)
			main.request_shot(self, aim, shot_power, curve)
			if joy >= 0:
				Input.start_joy_vibration(joy, 0.5, 0.7, 0.15)
	held_was = held
	if main.net.mode == "client":
		main.net.send_state(Vector3(aim.x, aim.y, power), curve, 1.0 if charging else 0.0, index)


func apply_remote_state(pos: Vector3, y: float, p: float) -> void:
	aim = Vector2(pos.x, pos.y)
	power = pos.z
	curve = y
	charging = p > 0.5
	net_started = true


func _move_avatar(delta: float) -> void:
	var to := stand_at - position
	to.y = 0.0
	var speed := 7.0 if run > 0.0 else 4.0
	var step := minf(to.length(), speed * delta)
	var moving := to.length() > 0.03
	if moving:
		position += to.normalized() * step
	position.y = 0.0
	# Face the goal (-z); a little bob and leg swing while moving.
	avatar.rotation.y = 0.0
	var t := Time.get_ticks_msec() * 0.001
	var swing := sin(t * 14.0) * 0.6 if moving else 0.0
	for i in legs.size():
		legs[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	avatar.position.y = absf(sin(t * 14.0)) * 0.06 if moving else 0.0
	if tag != null:
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED if main.keeper_in_vr() else BaseMaterial3D.BILLBOARD_ENABLED
		tag.rotation.y = PI if main.keeper_in_vr() else 0.0  # VR: face the keeper


func _update_camera(delta: float) -> void:
	var spot: Vector3 = main.spot
	var want_pos: Vector3
	var look: Vector3
	if main.shooter == index and main.state in ["aim", "runup", "flight", "result"]:
		want_pos = spot + Vector3(aim.x * 0.08, 1.45, 3.3)
		look = Vector3(aim.x * 0.3, 1.0, 0.0)
		if main.state == "flight" or main.state == "result":
			var bp: Vector3 = main.ball.global_position
			look = look.lerp(bp, 0.35)
	else:
		var side := (index - 3.5) * 0.7
		want_pos = Vector3(side, 3.2, 21.0)
		look = Vector3(side * 0.2, 1.0, 0.0)
	if not camera.has_meta("placed"):
		camera.set_meta("placed", true)
		camera.global_position = want_pos
	camera.global_position = camera.global_position.lerp(want_pos, 1.0 - exp(-5.0 * delta))
	camera.look_at(look, Vector3.UP)
	var sh: float = main.shake
	if sh > 0.0:
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * sh * 0.12


func _update_power_bar() -> void:
	if power_bg == null:
		return
	var mine: bool = main.shooter == index and (main.state == "aim" or main.state == "runup")
	power_bg.visible = mine
	if not mine:
		return
	var vp_size := power_bg.get_parent_control().size if power_bg.get_parent_control() != null else Vector2(800, 600)
	var w := clampf(vp_size.x * 0.4, 160.0, 520.0)
	var h := clampf(vp_size.y * 0.035, 12.0, 30.0)
	power_bg.size = Vector2(w, h)
	power_bg.position = Vector2((vp_size.x - w) * 0.5, vp_size.y - h - vp_size.y * 0.08)
	power_fill.size = Vector2(w * power, h)
	power_fill.color = Color(0.3, 1.0, 0.3).lerp(Color(1.0, 0.85, 0.1), clampf(power * 1.2, 0.0, 1.0))
	if power > 0.85:
		power_fill.color = Color(1.0, 0.3, 0.2)
