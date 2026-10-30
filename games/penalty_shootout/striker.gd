extends Node3D
## A TV player: a STRIKER. Players take turns at the penalty spot, seen from behind the ball.
## Your turn: move the reticle over the goal mouth with the left stick (or WASD / arrows / mouse),
## then HOLD a shot button to power up - the meter swings up and back down, so let go at the right
## moment - and release to shoot. Triggers (Q / E) bend the shot.
##   A (Space / left mouse; Enter for split-screen P2): a normal shot
##   X (C / right mouse; / for P2): a CHIP - slow and high, floats over a diving keeper
##   Y (F; ' for P2): a FIREBALL - the fastest shot there is, once per match
## Simple mode (main.simple): only A (hold, let go); no curving or chips. From round 3 a FIREBALL (Y,
## once) - a flame icon with a "Y" next to the power bar shows you have it.
## Simple mode picture cues (no how-to words, main.show_cue): on your turn a pulsing glowing button in
## your own controls sits above the power bar - A / ENTER / SPACE with a down arrow (press and hold),
## then with an up arrow while the meter swings (let go); in practice, while the reticle is far from the
## ring, STICK / an arrow key / W A S D with an arrow towards it. Each goes once you've done it twice.
## The FIREBALL button is your own Y / F / ' with a flame. Your own name tag is on a layer only the
## other views draw (main.tag_layer).
## Score and you celebrate (jump-spin, aeroplane or a little dance); win the cup and you lift it.
## Local strikers run their own aim (also on the TV machine, so it's instant); the host decides the
## shot. On the host, the TV machine's strikers are "remote": their aim arrives via apply_remote_state.

const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const NO_KEYS := 99
const AIM_SPEED := 3.4
const AIM_X := 4.4
const AIM_Y_MIN := 0.12
const AIM_Y_MAX := 3.0
const CHARGE_TIME := 1.1
const HAIR: Array[Color] = [Color(0.35, 0.2, 0.1), Color(0.95, 0.8, 0.35), Color(0.1, 0.08, 0.08), Color(0.85, 0.4, 0.15),
	Color(0.5, 0.3, 0.2), Color(0.15, 0.12, 0.1)]

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
var fire_icon: Control
var fire_sig := ""
var aim_hit := false  # practice: the reticle reached the ring this turn (counts towards the aim cue)
var pad_lost_t := -1.0

var aim := Vector2(0.0, 1.0)
var power := 0.0
var charging := false
var charge_t := 0.0
var curve := 0.0
var shot := "normal"  # normal, chip, fire
var fire_left := 1
var held_was := true
var x_was := true
var y_was := true
var mouse_d := Vector2.ZERO
var mouse_held := false
var mouse_right := false
var goals := 0
var shots := 0
var fastest := 0.0  # km/h
var trick_goals := 0
var net_started := false
var stand_at := Vector3.ZERO
var run := 0.0
var idle_aim_t := 0.0
var celebrate_kind := -1
var celebrate_t := 0.0
var hold_cup := false

# Bot hooks (tests).
var bot := false
var bot_stick := Vector2.ZERO
var bot_hold := false
var bot_curve := 0.0
var bot_shot := "normal"

var avatar: Node3D
var tag: Label3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []


func _ready() -> void:
	avatar = Node3D.new()
	add_child(avatar)
	var skin: Color = [Color(1.0, 0.8, 0.62), Color(0.85, 0.62, 0.45), Color(0.6, 0.4, 0.28)][index % 3]
	var hair := HAIR[(index - 1) % HAIR.size()]
	var shorts := Color(0.95, 0.95, 0.95)
	var vm: StandardMaterial3D = MeshKit.vertex_material(main.mats)
	# Torso, shorts, number and head in one mesh (the striker faces -z, the goal).
	var parts: Array = [
		[MeshKit.cyl(0.19, 0.21, 0.62, 12), MeshKit.at(Vector3(0, 1.22, 0)), color],
		[MeshKit.cyl(0.09, 0.11, 0.05, 10), MeshKit.at(Vector3(0, 1.54, 0)), color.darkened(0.4)],
		[MeshKit.box(Vector3(0.18, 0.2, 0.02)), MeshKit.at(Vector3(0, 1.26, 0.205)), Color(1, 1, 1)],
		[MeshKit.box(Vector3(0.44, 0.24, 0.3)), MeshKit.at(Vector3(0, 0.86, 0)), shorts],
		[MeshKit.cyl(0.055, 0.055, 0.1, 8), MeshKit.at(Vector3(0, 1.58, 0)), skin],
		[MeshKit.sphere(0.13, 14), MeshKit.at(Vector3(0, 1.72, 0)), skin],
		[MeshKit.sphere(0.135, 12), MeshKit.at(Vector3(0, 1.77, 0.02), Vector3(1.0, 0.65, 1.0)), hair],
		[MeshKit.sphere(0.02, 6), MeshKit.at(Vector3(-0.045, 1.73, -0.115)), Color(1, 1, 1)],
		[MeshKit.sphere(0.02, 6), MeshKit.at(Vector3(0.045, 1.73, -0.115)), Color(1, 1, 1)],
		[MeshKit.sphere(0.01, 6), MeshKit.at(Vector3(-0.045, 1.73, -0.132)), Color(0.05, 0.05, 0.1)],
		[MeshKit.sphere(0.01, 6), MeshKit.at(Vector3(0.045, 1.73, -0.132)), Color(0.05, 0.05, 0.1)],
		[MeshKit.box(Vector3(0.06, 0.012, 0.01)), MeshKit.at(Vector3(0, 1.66, -0.12)), Color(0.6, 0.2, 0.2)],
	]
	var torso := MeshInstance3D.new()
	torso.mesh = MeshKit.merge(parts)
	torso.material_override = vm
	avatar.add_child(torso)
	var leg_mesh := MeshKit.merge([
		[MeshKit.cyl(0.07, 0.06, 0.45, 8), MeshKit.at(Vector3(0, -0.22, 0)), skin],
		[MeshKit.cyl(0.065, 0.06, 0.28, 8), MeshKit.at(Vector3(0, -0.52, 0)), color.lightened(0.35)],
		[MeshKit.box(Vector3(0.12, 0.08, 0.24)), MeshKit.at(Vector3(0, -0.69, -0.04)), Color(0.12, 0.12, 0.14)],
	])
	for s in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(float(s) * 0.1, 0.74, 0)
		avatar.add_child(leg)
		var lm := MeshInstance3D.new()
		lm.mesh = leg_mesh
		lm.material_override = vm
		leg.add_child(lm)
		legs.append(leg)
	var arm_mesh := MeshKit.merge([
		[MeshKit.cyl(0.055, 0.05, 0.3, 8), MeshKit.at(Vector3(0, -0.15, 0)), color],
		[MeshKit.cyl(0.045, 0.045, 0.25, 8), MeshKit.at(Vector3(0, -0.42, 0)), skin],
		[MeshKit.sphere(0.055, 8), MeshKit.at(Vector3(0, -0.56, 0)), skin],
	])
	for s in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(float(s) * 0.25, 1.48, 0)
		avatar.add_child(arm)
		var am := MeshInstance3D.new()
		am.mesh = arm_mesh
		am.material_override = vm
		arm.add_child(am)
		arms.append(arm)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # faces every camera (seen from behind it read mirrored)
	tag.font_size = 48
	tag.pixel_size = 0.006
	tag.outline_size = 12
	tag.modulate = color.lightened(0.3)
	tag.position = Vector3(0, 2.2, 0)
	tag.layers = main.tag_layer(index)  # your own camera leaves it out (main._ensure_view)
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
	idle_aim_t = 0.0
	aim_hit = false
	shot = "normal"
	held_was = true  # a button still held from before doesn't start charging
	x_was = true
	y_was = true


func reset_match() -> void:
	goals = 0
	shots = 0
	fire_left = 1
	fastest = 0.0
	trick_goals = 0
	hold_cup = false


func celebrate(kind: int) -> void:
	celebrate_kind = kind
	celebrate_t = 0.0


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
		return bot_hold and bot_shot == "normal"
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	if key_set == 0:
		return Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER) \
			or Input.is_physical_key_pressed(KEY_CTRL)
	if key_set == 1:
		return Input.is_physical_key_pressed(KEY_SPACE) or mouse_held
	return false


func chip_held() -> bool:
	if main.simple:
		return false
	if bot:
		return bot_hold and bot_shot == "chip"
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_X):
		return true
	if key_set == 0:
		return Input.is_physical_key_pressed(KEY_SLASH)
	if key_set == 1:
		return Input.is_physical_key_pressed(KEY_C) or mouse_right
	return false


func fire_held() -> bool:
	if main.simple and not main.fire_on:
		return false
	if bot:
		return bot_hold and bot_shot == "fire"
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_Y):
		return true
	if key_set == 0:
		return Input.is_physical_key_pressed(KEY_APOSTROPHE)
	if key_set == 1:
		return Input.is_physical_key_pressed(KEY_F)
	return false


func curve_input() -> float:
	if main.simple:
		return 0.0
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
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT:
		mouse_right = mb.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


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
	if main.simple and hud != null:
		_update_cue(delta)


func _local_turn(delta: float) -> void:
	var held_a := charge_held()
	var held_x := chip_held()
	var held_y := fire_held()
	if not main.is_turn_of(self):
		charging = false
		power = 0.0
		held_was = held_a
		x_was = held_x
		y_was = held_y
		return
	var s := aim_input()
	aim += s * AIM_SPEED * delta
	if mouse_d != Vector2.ZERO:
		aim += Vector2(mouse_d.x, -mouse_d.y) * 0.006
		mouse_d = Vector2.ZERO
	aim.x = clampf(aim.x, -AIM_X, AIM_X)
	aim.y = clampf(aim.y, AIM_Y_MIN, AIM_Y_MAX)
	curve = lerpf(curve, curve_input(), 1.0 - exp(-10.0 * delta))
	var can: bool = main.can_shoot()
	if not charging:
		idle_aim_t += delta
	if not charging and can:
		var start := ""
		if held_a and not held_was:
			start = "normal"
		elif held_x and not x_was:
			start = "chip"
		elif held_y and not y_was:
			if fire_left > 0:
				start = "fire"
			else:
				main.sound("groan", -16.0, 2.0)
		if start != "":
			shot = start
			charging = true
			charge_t = 0.0
			main.sound("charge", -10.0, 1.4 if start == "fire" else (0.8 if start == "chip" else 1.0))
	if charging:
		var held := (shot == "normal" and held_a) or (shot == "chip" and held_x) or (shot == "fire" and held_y)
		if held:
			charge_t += delta
			var x := charge_t / CHARGE_TIME
			power = 1.0 - absf(1.0 - fmod(x, 2.0))
		else:
			charging = false
			var shot_power := maxf(power, 0.15)
			main.request_shot(self, aim, shot_power, curve, shot)
			main.cue_did(self, "kick")
			if joy >= 0:
				Input.start_joy_vibration(joy, 0.5, 0.7, 0.15)
	held_was = held_a
	x_was = held_x
	y_was = held_y
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
	var t := Time.get_ticks_msec() * 0.001
	var swing := sin(t * 14.0) * 0.6 if moving else 0.0
	for i in legs.size():
		legs[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	avatar.position = Vector3(0, absf(sin(t * 14.0)) * 0.06 if moving else 0.0, 0)
	avatar.rotation = Vector3.ZERO
	var arm_a := [0.15, 0.15]
	var arm_x := [-swing * 0.8, swing * 0.8]
	if celebrate_kind >= 0:
		celebrate_t += delta
		var c := celebrate_t
		match celebrate_kind:
			0:  # jump and spin with both arms up
				avatar.position.y = absf(sin(c * 6.0)) * 0.45
				avatar.rotation.y = c * 7.0
				arm_a = [2.8, 2.8]
				arm_x = [0.0, 0.0]
			1:  # aeroplane: arms out, swooping round in a circle
				avatar.position = Vector3(cos(c * 3.0) - 1.0, 0.0, sin(c * 3.0)) * 0.9
				avatar.rotation = Vector3(0, -c * 3.0, sin(c * 6.0) * 0.25)
				arm_a = [1.55, 1.55]
				arm_x = [0.0, 0.0]
				for i in legs.size():
					legs[i].rotation.x = sin(t * 16.0) * 0.6 * (1.0 if i == 0 else -1.0)
			_:  # a little dance
				avatar.position.y = absf(sin(c * 8.0)) * 0.12
				avatar.rotation.y = sin(c * 4.0) * 0.6
				arm_a = [1.2 + 0.8 * sin(c * 8.0), 1.2 - 0.8 * sin(c * 8.0)]
				arm_x = [0.0, 0.0]
		if celebrate_t > 2.4:
			celebrate_kind = -1
			avatar.position = Vector3.ZERO
	if hold_cup:
		arm_a = [2.75, 2.75]
		arm_x = [0.0, 0.0]
		avatar.position.y = absf(sin(t * 5.0)) * 0.1
	for i in arms.size():
		var sd := -1.0 if i == 0 else 1.0
		arms[i].rotation = Vector3(float(arm_x[i]), 0.0, sd * float(arm_a[i]))
	if tag != null:
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED if main.keeper_in_vr() else BaseMaterial3D.BILLBOARD_ENABLED
		tag.rotation.y = PI if main.keeper_in_vr() else 0.0  # VR: face the keeper


func _update_camera(delta: float) -> void:
	var spot: Vector3 = main.spot
	var want_pos: Vector3
	var look: Vector3
	if main.replay_on:
		want_pos = main.REPLAY_CAM
		look = main.replay_look()
		camera.global_position = want_pos
		UiKit.look(camera, look, Vector3.UP)
		return
	if main.state == "trophy":
		var ct: Array = main.ceremony_camera()
		want_pos = ct[0]
		look = ct[1]
	elif main.shooter == index and main.state in ["aim", "runup", "flight", "result"]:
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
	UiKit.look(camera, look, Vector3.UP)
	var sh: float = main.shake
	if sh > 0.0:
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * sh * 0.12


func _update_power_bar() -> void:
	if power_bg == null:
		return
	var mine: bool = main.shooter == index and (main.state == "aim" or main.state == "runup") and not main.replay_on
	power_bg.visible = mine
	_update_fire_icon(mine)
	if not mine:
		return
	var vp_size := power_bg.get_parent_control().size if power_bg.get_parent_control() != null else Vector2(800, 600)
	var w := clampf(vp_size.x * 0.4, 160.0, 520.0)
	var h := clampf(vp_size.y * 0.035, 12.0, 30.0)
	power_bg.size = Vector2(w, h)
	power_bg.position = Vector2((vp_size.x - w) * 0.5, vp_size.y - h - vp_size.y * 0.08)
	power_fill.size = Vector2(w * power, h)
	power_fill.color = Color(0.3, 1.0, 0.3).lerp(Color(1.0, 0.85, 0.1), clampf(power * 1.2, 0.0, 1.0))
	if shot == "fire" and charging:
		power_fill.color = Color(1.0, 0.5, 0.1)
	elif shot == "chip" and charging:
		power_fill.color = Color(0.5, 0.8, 1.0)
	if power > 0.85 and not main.simple:
		power_fill.color = Color(1.0, 0.3, 0.2)


## Simple mode: your own FIREBALL button (Y / F / ') with a flame, left of the power bar, while you have it.
func _update_fire_icon(mine: bool) -> void:
	var show: bool = main.simple and main.fire_on and fire_left > 0 and mine
	if fire_icon == null and not show:
		return
	var h := clampf(power_bg.size.y * 2.2, 40.0, 66.0)
	var s := h / 34.0
	var sig := "%s/%.2f" % [_btn_name("fire"), s]
	if fire_icon == null or sig != fire_sig:
		if fire_icon != null:
			fire_icon.queue_free()
		fire_sig = sig
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)
		var flame := UiKit.icon("fire", Color(1.0, 0.55, 0.15), h * 0.9)
		flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(flame)
		var btn := _button("fire", s)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
		fire_icon = row
		power_bg.get_parent().add_child(fire_icon)
	fire_icon.visible = show
	if not show:
		return
	fire_icon.size = fire_icon.get_combined_minimum_size()
	fire_icon.position = power_bg.position + Vector2(-fire_icon.size.x - 14.0, (power_bg.size.y - fire_icon.size.y) * 0.5)
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.01)
	fire_icon.pivot_offset = fire_icon.size * 0.5
	fire_icon.scale = Vector2(pulse, pulse) * (1.25 if charging and shot == "fire" else 1.0)


# --- Simple mode picture cues ---------------------------------------------------------------

## This player's own button for an action: "kick", "fire", "aim" (with dir "left" / "right" / "up" / "down").
func _btn_name(action: String, dir: String = "") -> String:
	if joy >= 0 or key_set == NO_KEYS:
		return {"kick": "A", "fire": "Y", "aim": "STICK"}.get(action, "A")
	if key_set == 0:
		return {"kick": "ENTER", "fire": "'", "aim": "arrow_" + dir}.get(action, "ENTER")
	return {"kick": "SPACE", "fire": "F", "aim": {"left": "A", "right": "D", "up": "W", "down": "S"}.get(dir, "W")}.get(action, "SPACE")


func _button(action: String, s: float, dir: String = "") -> Control:
	var b := _btn_name(action, dir)
	if b.begins_with("arrow_"):
		return main.keycap("", b, s)  # an arrow key
	if b.length() == 1 and not (joy >= 0 or key_set == NO_KEYS):
		return main.keycap(b, "", s)  # a letter key (never a green pad A)
	return UiKit.glyph(b, s)


func _update_cue(delta: float) -> void:
	var key := ""
	var dir := ""
	var mine: bool = active and is_local() and main.is_turn_of(self) and main.can_shoot() and not main.replay_on \
		and not get_tree().paused and (main.net.mode != "client" or main.synced)
	if mine and main.practice == "striker":
		var to := Vector2(main.ptarget.x, main.ptarget.y) - aim
		if to.length() < 0.6 and not aim_hit:
			aim_hit = true
			main.cue_did(self, "aim")
		if not charging and to.length() >= 0.6 and not main.cue_learned(self, "aim"):
			key = "aim"
			if absf(to.x) >= absf(to.y):
				dir = "right" if to.x > 0.0 else "left"
			else:
				dir = "up" if to.y > 0.0 else "down"
	if mine and key == "" and not main.cue_learned(self, "kick"):
		key = "letgo" if charging else "kick"
	var vs: Vector2 = hud.size
	var ui := clampf(minf(vs.x / 960.0, vs.y / 540.0), 0.45, 1.3)
	var s := 1.7 * ui
	var at := Vector2(vs.x * 0.5, vs.y * 0.8)
	if power_bg != null and power_bg.visible:
		at = Vector2(vs.x * 0.5, power_bg.position.y - 12.0 * ui)
	var sig := "%s/%s/%.2f" % [dir, _btn_name("kick" if key != "aim" else "aim", dir), s]
	var make := func() -> Array:
		var gold := Color(1.0, 0.9, 0.4)
		if key == "aim":
			var items: Array = [_button("aim", s, dir)]
			if _btn_name("aim", dir) == "STICK" or key_set == 1:
				items.append(UiKit.icon("arrow_" + dir, gold, 34.0 * s))
			return items
		return [_button("kick", s), UiKit.icon("arrow_down" if key == "kick" else "arrow_up", gold, 34.0 * s)]
	main.show_cue(self, key, sig, make, at, delta)
