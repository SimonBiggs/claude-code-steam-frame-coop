extends Node3D
## A bumblebee (TV players 2 to 7), flown in third person.
## Controller: left stick fly, right stick turn the camera, RT / RB rise, LT / LB sink, A zoom (once joined).
## Keyboard set 0: W/S fly, A/D turn, Space rise, Shift sink, E zoom.
## Keyboard set 1: arrows, Ctrl rise, "." sink, "/" zoom.
## Players 4-7 have no keyboard set (key_set = -1): one controller each, picked by device id.
## Flying is local (instant). The host decides pollen, pollination and honey from the bee's position.

const W := preload("res://games/bee_garden/world.gd")

const SPEED := 3.1
const VSPEED := 2.3
const BOOST := 1.8
const CAM_DIST := 2.1
const CAM_HEIGHT := 0.8
const MAX_POLLEN := 3
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "rise": KEY_SPACE, "sink": KEY_SHIFT, "zoom": KEY_E},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "rise": KEY_CTRL, "sink": KEY_PERIOD, "zoom": KEY_SLASH},
]

var main
var index := 1
var color := Color.WHITE
var joy := -1
var key_set := 0
var remote := false   # host: flown from the TV machine
var active := true
var claimed := false  # a controller or keyboard set belongs to this bee
var vr := false
var ghost := false

var pollen := 0         # host-authoritative, mirrored to the TV
var pollen_value := 0   # honey it will make
var gold := false       # carrying sun lily pollen
var last_flower := -1
var honey_made := 0
var gather_cd := 0.0
var vel := Vector3.ZERO
var face := 0.0
var cam_yaw := 0.0
var boost_t := 0.0
var boost_cd := 0.0
var zoom_was := false
var net_target := Vector3.ZERO
var net_started := false
var bot_input := {}  # tests: {"move": Vector3 (world, includes up/down), "zoom": bool}
var t := 0.0

var camera: Camera3D
var hud_label: Label
var hint_label: Label
var pivot: Node3D
var wings: Array[MeshInstance3D] = []
var balls: Array[MeshInstance3D] = []
var arrow: MeshInstance3D
var tag: Label3D


func _ready() -> void:
	add_to_group("bees")
	net_target = global_position
	pivot = Node3D.new()
	add_child(pivot)
	var yellow := W.cmat(Color(1.0, 0.8, 0.15))
	var black := W.cmat(Color(0.12, 0.1, 0.08))
	W.mesh_node(pivot, W.sphere(0.14, 14), yellow, Vector3(0, 0, 0.04), Vector3(0.95, 0.9, 1.25))
	for z in [0.0, 0.1]:
		var band := W.mesh_node(pivot, W.cyl(0.135, 0.135, 0.04, 12), black, Vector3(0, 0, z + 0.02))
		band.rotation.x = PI / 2.0
	W.mesh_node(pivot, W.sphere(0.09, 12), black, Vector3(0, 0.02, -0.15))
	for s in [-1.0, 1.0]:
		W.mesh_node(pivot, W.sphere(0.03, 6), W.cmat(Color.WHITE, 0.3), Vector3(s * 0.045, 0.05, -0.22))
	var scarf := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.11
	tm.rings = 12
	tm.ring_segments = 6
	scarf.mesh = tm
	scarf.material_override = W.cmat(color, 0.4)
	scarf.rotation.x = PI / 2.0
	scarf.position = Vector3(0, 0, -0.09)
	pivot.add_child(scarf)
	var wing_mat := W.mat(Color(0.92, 0.97, 1.0, 0.55), 0.2)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for s in [-1.0, 1.0]:
		var wm := W.mesh_node(pivot, W.sphere(0.12, 10), wing_mat, Vector3(s * 0.13, 0.12, 0.0), Vector3(1.2, 0.12, 0.7))
		wm.set_meta("side", s)
		wings.append(wm)
	for s in [-1.0, 1.0]:
		var b := W.mesh_node(pivot, W.sphere(0.045, 8), W.cmat(Color(1.0, 0.6, 0.1), 0.6), Vector3(s * 0.09, -0.12, 0.03))
		balls.append(b)
	arrow = MeshInstance3D.new()
	arrow.mesh = W.cyl(0.0, 0.06, 0.2, 8)
	arrow.material_override = W.cmat(Color(1.0, 0.75, 0.2), 1.0)
	arrow.layers = W.TV_LAYER
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arrow)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 10
	tag.modulate = color
	tag.position.y = 0.42
	tag.layers = W.TV_LAYER
	add_child(tag)


func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 400.0
	camera.cull_mask = 0xFFFFF
	cam_yaw = face
	_update_camera(1.0)


func set_active(on: bool) -> void:
	active = on
	visible = on


# --- Input -------------------------------------------------------------------

func _key(action: String) -> bool:
	if key_set < 0 or key_set >= KEYS.size():
		return false
	var keys: Dictionary = KEYS[key_set]
	return Input.is_physical_key_pressed(keys[action])


func _stick(ax: JoyAxis, ay: JoyAxis, dead: float) -> Vector2:
	if joy < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(joy, ax), Input.get_joy_axis(joy, ay))
	var l := v.length()
	if l < dead:
		return Vector2.ZERO
	return v / l * ((minf(l, 1.0) - dead) / (1.0 - dead))


func _joy_btn(b: JoyButton) -> bool:
	return joy >= 0 and Input.is_joy_button_pressed(joy, b)


func _joy_axis(a: JoyAxis) -> float:
	return Input.get_joy_axis(joy, a) if joy >= 0 else 0.0


## World-space wish direction (x/z from the stick, y from the triggers).
func read_move(delta: float) -> Vector3:
	if not bot_input.is_empty():
		var bm: Vector3 = bot_input.get("move", Vector3.ZERO)
		return bm.limit_length(1.0)
	var turn := float(_key("right")) - float(_key("left"))
	cam_yaw -= turn * 2.4 * delta
	var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15)
	cam_yaw -= look.x * absf(look.x) * 3.0 * delta
	var v := Vector2(0.0, float(_key("down")) - float(_key("up")))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(float(_joy_btn(JOY_BUTTON_DPAD_RIGHT)) - float(_joy_btn(JOY_BUTTON_DPAD_LEFT)),
			float(_joy_btn(JOY_BUTTON_DPAD_DOWN)) - float(_joy_btn(JOY_BUTTON_DPAD_UP)))
	var up := float(_key("rise")) - float(_key("sink"))
	up += _joy_axis(JOY_AXIS_TRIGGER_RIGHT) - _joy_axis(JOY_AXIS_TRIGGER_LEFT)
	up += float(_joy_btn(JOY_BUTTON_RIGHT_SHOULDER)) - float(_joy_btn(JOY_BUTTON_LEFT_SHOULDER))
	var flat := Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)
	return Vector3(flat.x, clampf(up, -1.0, 1.0), flat.z)


func zoom_held() -> bool:
	if not bot_input.is_empty():
		return bot_input.get("zoom", false)
	return _key("zoom") or _joy_btn(JOY_BUTTON_A)


## Any button that wakes a sleeping (claimed) bee up.
func wake_held() -> bool:
	if not bot_input.is_empty():
		return bot_input.get("zoom", false)
	return _key("zoom") or _key("rise") or _joy_btn(JOY_BUTTON_A) or _joy_axis(JOY_AXIS_TRIGGER_RIGHT) > 0.5


# --- Update ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active:
		return
	if remote:
		global_position = global_position.lerp(net_target, 1.0 - exp(-18.0 * delta))
		pivot.rotation.y = face
		return
	_move(delta)
	main.net.send_state(global_position, face, cam_yaw, index)


func _move(delta: float) -> void:
	boost_t -= delta
	boost_cd -= delta
	var z := zoom_held()
	if z and not zoom_was and boost_cd <= 0.0:
		boost_t = 0.6
		boost_cd = 1.4
		main.local_sound("zoom", -8.0, 1.0 + index * 0.05)
		if joy >= 0:
			Input.start_joy_vibration(joy, 0.2, 0.1, 0.1)
	zoom_was = z
	var wish := read_move(delta)
	var spd := SPEED * (BOOST if boost_t > 0.0 else 1.0)
	var want := Vector3(wish.x * spd, wish.y * VSPEED * (BOOST if boost_t > 0.0 else 1.0), wish.z * spd)
	vel = vel.lerp(want, 1.0 - exp(-5.0 * delta))
	var np := global_position + vel * delta
	np.x = clampf(np.x, -9.0, 9.0)
	np.z = clampf(np.z, -6.5, 6.5)
	var fl := W.floor_y(np.x, np.z)
	if np.y < fl:
		# Bump up over the bed edge / hive instead of passing through it.
		np.y = move_toward(np.y, fl, 6.0 * delta) if global_position.y < fl - 0.05 else fl
		vel.y = maxf(vel.y, 0.0)
	np.y = clampf(np.y, W.LAWN_Y + 0.3, 6.5)
	global_position = np
	var hv := Vector2(vel.x, vel.z)
	if hv.length() > 0.2:
		face = lerp_angle(face, atan2(-vel.x, -vel.z), 1.0 - exp(-10.0 * delta))
		if bot_input.is_empty() and absf(_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15).x) < 0.01 \
				and not _key("left") and not _key("right"):
			cam_yaw = lerp_angle(cam_yaw, face, 1.0 - exp(-0.8 * delta))
	pivot.rotation.y = face


func _process(delta: float) -> void:
	t += delta
	for wm in wings:
		var side: float = wm.get_meta("side")
		wm.rotation.z = side * (0.25 + sin(t * 60.0 + index) * 0.55)
	pivot.position.y = sin(t * 5.0 + index) * 0.03
	pivot.rotation.x = clampf(-vel.y * 0.12, -0.4, 0.4)
	var b_on := pollen > 0
	for i in balls.size():
		var b: MeshInstance3D = balls[i]
		b.visible = b_on
		b.scale = Vector3.ONE * (0.7 + 0.3 * pollen)
		b.material_override = W.cmat(Color(1.0, 0.85, 0.2) if gold else Color(1.0, 0.6, 0.1), 0.8 if gold else 0.5)
	arrow.visible = active and pollen > 0 and global_position.distance_to(W.HIVE_ENTRY) > 2.0
	if arrow.visible:
		arrow.position = Vector3(0, 0.3, 0)
		var to := W.HIVE_ENTRY - global_position
		var dir := to.normalized()
		# The cone's tip is +Y: point it at the hive.
		var axis := Vector3.UP.cross(dir)
		if axis.length() > 0.001:
			arrow.basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
		else:
			arrow.basis = Basis()
	_update_camera(delta)
	_update_hud()


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target := global_position + Basis(Vector3.UP, cam_yaw) * Vector3(0.0, CAM_HEIGHT, CAM_DIST)
	var k := 1.0 - exp(-8.0 * delta)
	var cp := camera.global_position.lerp(target, k) if delta < 0.5 else target
	cp.y = maxf(cp.y, W.floor_y(cp.x, cp.z) + 0.15)
	camera.global_position = cp
	var look := global_position + Vector3.UP * 0.2
	if camera.global_position.distance_to(look) > 0.05:
		camera.look_at(look, Vector3.UP)


func _update_hud() -> void:
	if hud_label:
		hud_label.text = "P%d  BEE   POLLEN %d / %d   HONEY MADE %d" % [index + 1, pollen, MAX_POLLEN, honey_made]
	if hint_label:
		var h := ""
		if main.game_over:
			h = ""
		elif pollen >= MAX_POLLEN:
			h = "Full of pollen! Follow the arrow to the HIVE"
		elif pollen > 0:
			h = "Visit a DIFFERENT flower to grow fruit,\nor follow the arrow to the HIVE to make honey"
		else:
			h = "Fly into a glowing flower to collect pollen"
		hint_label.text = h


# --- Network -----------------------------------------------------------------

## Host: the TV says where this bee is.
func apply_remote_state(pos: Vector3, new_face: float, new_cam_yaw: float) -> void:
	net_target = pos
	face = new_face
	cam_yaw = new_cam_yaw
	if not net_started:
		net_started = true
		global_position = pos


func net_state() -> Array:
	if not active:
		return [false]
	return [global_position, face, pollen, honey_made, active, gold]


## TV: authoritative pollen / honey / seat state from the host.
func apply_net_state(st: Array) -> void:
	if st.size() < 6:
		if active:
			set_active(false)
			main.on_player_activity_changed(self)
		return
	pollen = st[2]
	honey_made = st[3]
	gold = st[5]
	var act: bool = st[4]
	if act != active:
		set_active(act)
		main.on_player_activity_changed(self)
