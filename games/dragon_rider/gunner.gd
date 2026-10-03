extends Node3D
## A TV player: a gunner sitting on the dragon's deck with a bubble cannon, looking around freely
## (360 degrees) from the dragon's back. This node is a child of the dragon, so it rides along.
## Controller: right stick (or left stick) aims, RT / RB / A fires. Keyboard set 0: mouse + WASD aim,
## click / Space fires. Keyboard set 1: arrow keys aim, Enter fires.
## Aim (yaw, pitch) is relative to the dragon's heading. Host: TV players are "remote" (yaw/pitch
## arrive over the network, shots arrive as actions).

const FIRE_INTERVAL := 0.24
const STICK_YAW := 2.6
const STICK_PITCH := 1.8
const KEY_TURN := 2.0
const MOUSE_SENS := 0.0028
const NO_KEYS := 99
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "fire": KEY_SPACE},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "fire": KEY_ENTER},
]

var index := 1
var main
var color := Color.WHITE
var joy := -1
var key_set := NO_KEYS
var mouse_look := false
var remote := false
var ghost := false
var vr := false
var active := true
var yaw := 0.0
var pitch := 0.05
var fire_cd := 0.0
var pad_lost_t := -1.0
var force_fire := false  # test bots
var net_started := false
var camera: Camera3D
var hud
var shake := 0.0
var recoil := 0.0

var turret: Node3D
var muzzle: Node3D
var muzzle_mat: StandardMaterial3D


func _ready() -> void:
	var seat_mat: StandardMaterial3D = main.color_mat(Color(0.5, 0.32, 0.2), 0.0)
	var suit: StandardMaterial3D = main.color_mat(color, 0.15)
	var skin: StandardMaterial3D = main.color_mat(Color(1.0, 0.82, 0.68), 0.0)
	var brass: StandardMaterial3D = main.color_mat(Color(1.0, 0.78, 0.4), 0.25)
	_mesh(self, main.box_mesh(Vector3(0.5, 0.22, 0.5)), seat_mat, Vector3(0, 0.05, 0))
	# The avatar is on this gunner's own render layer, so their own camera doesn't see inside it.
	for m in [_mesh(self, main.capsule_mesh(0.22, 0.75), suit, Vector3(0, 0.5, 0.05)),
			_mesh(self, main.sphere_mesh(0.17), skin, Vector3(0, 0.98, 0)),
			_mesh(self, main.cyl_mesh(0.1, 0.2, 0.16, 10), suit, Vector3(0, 1.12, 0))]:
		(m as MeshInstance3D).layers = avatar_layer()
	turret = Node3D.new()
	add_child(turret)
	turret.position = Vector3(0, 0.95, 0)
	var barrel := _mesh(turret, main.cyl_mesh(0.07, 0.09, 0.75, 10), brass, Vector3(0.24, -0.3, -0.55))
	barrel.rotation.x = PI / 2.0
	_mesh(turret, main.sphere_mesh(0.14), main.color_mat(color, 0.6), Vector3(0.24, -0.3, -0.12))
	muzzle = Node3D.new()
	turret.add_child(muzzle)
	muzzle.position = Vector3(0.24, -0.3, -0.98)
	muzzle_mat = main.make_material(Color(0.7, 0.95, 1.0), 0.5)
	_mesh(muzzle, main.sphere_mesh(0.09), muzzle_mat, Vector3.ZERO)
	visible = active


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func avatar_layer() -> int:
	return 1 << (10 + index)


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		net_started = false


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 78.0
	camera.near = 0.08
	camera.far = 1500.0
	camera.cull_mask = 0xFFFFF & ~avatar_layer()


func eye_position() -> Vector3:
	return global_transform * Vector3(0, 0.95, 0)


func aim_basis(y: float, p: float) -> Basis:
	return main.dragon.global_basis * Basis.from_euler(Vector3(p, y, 0.0))


func aim_dir() -> Vector3:
	return aim_basis(yaw, pitch) * Vector3.FORWARD


func muzzle_position() -> Vector3:
	return muzzle.global_position


# --- Per frame (called by main after the dragon has moved) -----------------------

func update(delta: float) -> void:
	fire_cd -= delta
	recoil = maxf(0.0, recoil - delta * 6.0)
	shake = maxf(0.0, shake - delta * 2.5)
	muzzle_mat.emission_energy_multiplier = maxf(0.5, muzzle_mat.emission_energy_multiplier - delta * 30.0)
	var gold: bool = main.power_t > 0.0
	muzzle_mat.emission = Color(1.0, 0.85, 0.3) if gold else Color(0.7, 0.95, 1.0)
	if active and not remote and not ghost:
		_read_look(delta)
		if _fire_held() and fire_cd <= 0.0:
			_fire()
		main.net.send_state(Vector3.ZERO, yaw, pitch, index)
	turret.rotation = Vector3(pitch + recoil * 0.05, yaw, 0.0)
	if camera != null:
		var b := aim_basis(yaw + randf_range(-1.0, 1.0) * shake * 0.01, pitch + randf_range(-1.0, 1.0) * shake * 0.01)
		camera.global_transform = Transform3D(b, eye_position())


func _fire() -> void:
	fire_cd = FIRE_INTERVAL - 0.04 * float(main.cannon_level)  # beating a Storm King upgrades the cannons
	recoil = 1.0
	muzzle_mat.emission_energy_multiplier = 5.0
	main.fire_bubble(index, yaw, pitch, main.net.mode == "client")
	if main.net.mode == "client":
		main.net.send_action("fire", [yaw, pitch], index)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.15, 0.05, 0.05)


func apply_remote_state(_pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = clampf(new_pitch, -1.3, 1.35)
	net_started = true


# --- Input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		yaw = wrapf(yaw - motion.relative.x * MOUSE_SENS, -PI, PI)
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.35)


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
	var left := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.2)
	if left.length() > look.length():
		look = left
	look = look * look.length()
	var keys := Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	yaw = wrapf(yaw - (look.x * STICK_YAW + keys.x * KEY_TURN) * delta, -PI, PI)
	pitch = clampf(pitch - (look.y * STICK_PITCH + keys.y * KEY_TURN * 0.7) * delta, -1.3, 1.35)


func fire_held() -> bool:
	return _fire_held()


func _fire_held() -> bool:
	if force_fire:
		return true
	if _key("fire"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		return Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER) \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
	return false
