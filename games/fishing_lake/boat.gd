extends Node3D
## A TV player: a little rowing boat on the lake, seen from a third-person chase camera.
## Row with the left stick (relative to the camera), turn the camera with the right stick.
## A: swing the net (scoops up floating treasure, or splashes to scare fish the other way).
## X / Y: call out the nearest fish - it gets a big icon and swims to the angler's bobber.
## Local boats move themselves (also on the TV machine, so it feels instant); on the host the TV's
## boats are "remote" and follow the positions it sends.
## Upgrades: scooping treasure and helping the angler earns coins; at 3 / 7 / 12 coins the boat gets a
## SAIL (faster), a BIG NET (scoops from further) and a LANTERN MOTOR (fastest, sparkly wake). The host
## decides the level and sends it in the snapshots.

const Lake := preload("res://games/fishing_lake/lake.gd")
const NO_KEYS := 99
const MAX_SPEED := 3.6
const ACCEL := 3.4
const TURN := 2.4
const LEVEL_COINS: Array[int] = [3, 7, 12]
const LEVEL_NAMES: Array[String] = ["ROWING BOAT", "SAILING BOAT", "BIG NET BOAT", "LANTERN MOTORBOAT"]
const SPEED_MULT: Array[float] = [1.0, 1.25, 1.3, 1.5]

var index := 1
var main
var color := Color.WHITE
var remote := false
var ghost := false
var vr := false
var active := false
var joy := -1
var key_set := NO_KEYS  # 0: arrows + Enter (net) and / (call) (local P2), 1: WASD/arrows + mouse + Space/F (TV machine P2)
var mouse_look := false
var camera: Camera3D
var hud: Control
var hud_label: Label
var tip_label: Label
var pad_lost_t := -1.0
var level := 0
var coins := 0
var built_level := 0
var wake: CPUParticles3D
var sparkle: CPUParticles3D
var ring: MeshInstance3D

var vel := Vector3.ZERO
var yaw := 0.0
var cam_yaw := 0.0
var cam_idle_t := 0.0
var mouse_dx := 0.0
var row_phase := 0.0
var row_amount := 0.0
var net_anim := 0.0
var net_cool := 0.0
var call_cool := 0.0
var a_was := false
var x_was := false
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var net_started := false
var scooped := 0
var calls := 0

var bot := false
var bot_dir := Vector3.ZERO
var bot_net := false
var bot_call := false

var hull: Node3D
var oars: Array[Node3D] = []
var net_pivot: Node3D
var tag: Label3D


func _ready() -> void:
	hull = Node3D.new()
	add_child(hull)
	var wood: StandardMaterial3D = main.make_material(color.lerp(Color(0.6, 0.42, 0.25), 0.55), 0.0)
	var h := MeshInstance3D.new()
	h.mesh = main.sphere_mesh(0.5)
	h.scale = Vector3(1.05, 0.55, 2.0)
	h.material_override = wood
	h.position = Vector3(0, 0.05, 0)
	hull.add_child(h)
	var floor_m := MeshInstance3D.new()
	floor_m.mesh = main.box_mesh(Vector3(0.7, 0.04, 1.3))
	floor_m.material_override = main.make_material(Color(0.35, 0.25, 0.16), 0.0)
	floor_m.position = Vector3(0, 0.2, 0)
	hull.add_child(floor_m)
	var seat := MeshInstance3D.new()
	seat.mesh = main.box_mesh(Vector3(0.9, 0.06, 0.25))
	seat.material_override = wood
	seat.position = Vector3(0, 0.32, 0.15)
	hull.add_child(seat)
	# The rower: body in the player's colour, a face and a sun hat.
	var bodym := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.17
	cap.height = 0.55
	cap.radial_segments = 10
	cap.rings = 2
	bodym.mesh = cap
	bodym.material_override = main.make_material(color, 0.15)
	bodym.position = Vector3(0, 0.6, 0.15)
	hull.add_child(bodym)
	var head := MeshInstance3D.new()
	head.mesh = main.sphere_mesh(0.14)
	head.material_override = main.make_material(Color(1.0, 0.82, 0.65), 0.0)
	head.position = Vector3(0, 0.98, 0.15)
	hull.add_child(head)
	var hat := MeshInstance3D.new()
	hat.mesh = main.cyl_mesh(0.1, 0.24, 0.12, 12)
	hat.material_override = main.make_material(color.lightened(0.3), 0.1)
	hat.position = Vector3(0, 1.1, 0.15)
	hull.add_child(hat)
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(s * 0.45, 0.4, 0.1)
		hull.add_child(pivot)
		var oar := MeshInstance3D.new()
		oar.mesh = main.box_mesh(Vector3(1.1, 0.04, 0.05))
		oar.material_override = main.make_material(Color(0.75, 0.6, 0.4), 0.0)
		oar.position = Vector3(s * 0.45, -0.1, 0)
		oar.rotation.z = s * -0.35
		pivot.add_child(oar)
		var blade := MeshInstance3D.new()
		blade.mesh = main.box_mesh(Vector3(0.28, 0.02, 0.16))
		blade.material_override = oar.material_override
		blade.position = Vector3(s * 0.95, -0.28, 0)
		pivot.add_child(blade)
		oars.append(pivot)
	# The net on a long pole at the front.
	net_pivot = Node3D.new()
	net_pivot.position = Vector3(0.3, 0.6, -0.4)
	hull.add_child(net_pivot)
	var pole := MeshInstance3D.new()
	pole.mesh = main.cyl_mesh(0.025, 0.025, 1.4, 6)
	pole.material_override = main.make_material(Color(0.75, 0.6, 0.4), 0.0)
	pole.rotation.x = deg_to_rad(90.0)
	pole.position = Vector3(0, 0, -0.7)
	net_pivot.add_child(pole)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.24
	tm.outer_radius = 0.28
	tm.rings = 12
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = main.make_material(color, 0.3)
	ring.position = Vector3(0, 0, -1.6)
	net_pivot.add_child(ring)
	var mesh_bag := MeshInstance3D.new()
	mesh_bag.mesh = main.sphere_mesh(0.25)
	mesh_bag.scale = Vector3(1.0, 1.0, 0.9)
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(1, 1, 1, 0.35)
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_bag.material_override = nm
	mesh_bag.position = Vector3(0, -0.15, -1.6)
	net_pivot.add_child(mesh_bag)
	net_pivot.rotation.x = deg_to_rad(25.0)
	# A little pennant in the player's colour at the stern, so you can spot your boat.
	var stick := MeshInstance3D.new()
	stick.mesh = main.cyl_mesh(0.015, 0.015, 0.9, 5)
	stick.material_override = pole.material_override
	stick.position = Vector3(0, 0.7, 0.85)
	hull.add_child(stick)
	var pennant := MeshInstance3D.new()
	var pp := PrismMesh.new()
	pp.size = Vector3(0.3, 0.4, 0.01)
	pennant.mesh = pp
	pennant.material_override = main.make_material(color, 0.4)
	pennant.rotation.z = deg_to_rad(-90.0)
	pennant.position = Vector3(0, 1.0, 1.05)
	pennant.rotation.y = deg_to_rad(90.0)
	hull.add_child(pennant)
	# Wake: a few white bubbles behind the boat while it moves.
	wake = CPUParticles3D.new()
	wake.amount = 12
	wake.lifetime = 1.2
	wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wake.emission_box_extents = Vector3(0.35, 0.02, 0.1)
	wake.direction = Vector3.UP
	wake.spread = 60.0
	wake.gravity = Vector3(0, -0.6, 0)
	wake.initial_velocity_min = 0.1
	wake.initial_velocity_max = 0.4
	wake.scale_amount_min = 0.7
	wake.scale_amount_max = 1.6
	wake.mesh = main.sphere_mesh(0.06)
	wake.material_override = main.make_material(Color(0.92, 0.97, 1.0), 0.3)
	wake.local_coords = false
	wake.emitting = false
	wake.position = Vector3(0, 0.05, 1.05)
	add_child(wake)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.font_size = 72
	tag.pixel_size = 0.008
	tag.outline_size = 18
	tag.modulate = color.lightened(0.3)
	tag.position = Vector3(0, 1.75, 0)
	add_child(tag)
	visible = active


func set_active(on: bool) -> void:
	active = on
	visible = on


## Upgrade parts appear as the level goes up (built lazily, so hot reloads and the TV machine agree).
func set_level(l: int) -> void:
	level = clampi(l, 0, LEVEL_NAMES.size() - 1)
	if level == built_level:
		return
	built_level = level
	var old := hull.get_node_or_null("Upgrades")
	if old != null:
		old.free()
	var up := Node3D.new()
	up.name = "Upgrades"
	hull.add_child(up)
	if level >= 1:
		var mast := MeshInstance3D.new()
		mast.mesh = main.cyl_mesh(0.03, 0.035, 1.9, 6)
		mast.material_override = main.make_material(Color(0.75, 0.6, 0.4), 0.0)
		mast.position = Vector3(0, 1.15, -0.35)
		up.add_child(mast)
		var sail := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.left_to_right = 0.0
		pm.size = Vector3(0.9, 1.4, 0.02)
		sail.mesh = pm
		var sm := main.make_material(color.lightened(0.45), 0.2).duplicate() as StandardMaterial3D
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sail.material_override = sm
		sail.rotation.y = deg_to_rad(90.0)
		sail.position = Vector3(0, 1.3, -0.35 + 0.47)
		up.add_child(sail)
	if level >= 2:
		ring.scale = Vector3.ONE * 1.45
	else:
		ring.scale = Vector3.ONE
	if level >= 3:
		var lpole := MeshInstance3D.new()
		lpole.mesh = main.cyl_mesh(0.02, 0.02, 0.8, 5)
		lpole.material_override = main.make_material(Color(0.3, 0.3, 0.3), 0.0)
		lpole.position = Vector3(-0.3, 0.75, 0.75)
		up.add_child(lpole)
		var lamp := MeshInstance3D.new()
		lamp.mesh = main.sphere_mesh(0.09)
		lamp.material_override = main.make_material(Color(1.0, 0.85, 0.4), 2.5)
		lamp.position = Vector3(-0.3, 1.18, 0.75)
		up.add_child(lamp)
		var motor := MeshInstance3D.new()
		motor.mesh = main.box_mesh(Vector3(0.22, 0.3, 0.22))
		motor.material_override = main.make_material(Color(0.2, 0.2, 0.25), 0.0)
		motor.position = Vector3(0, 0.3, 1.0)
		up.add_child(motor)
		sparkle = CPUParticles3D.new()
		sparkle.amount = 10
		sparkle.lifetime = 0.9
		sparkle.direction = Vector3.UP
		sparkle.spread = 50.0
		sparkle.gravity = Vector3(0, -1.5, 0)
		sparkle.initial_velocity_min = 0.6
		sparkle.initial_velocity_max = 1.4
		sparkle.mesh = main.box_mesh(Vector3.ONE * 0.05)
		sparkle.material_override = main.make_material(color.lightened(0.5), 2.0)
		sparkle.local_coords = false
		sparkle.position = Vector3(0, 0.15, 1.15)
		up.add_child(sparkle)
	else:
		sparkle = null


func max_speed() -> float:
	return MAX_SPEED * SPEED_MULT[clampi(level, 0, SPEED_MULT.size() - 1)]


func net_reach() -> float:
	return 2.9 if level >= 2 else 2.0


func next_level_coins() -> int:
	return LEVEL_COINS[level] if level < LEVEL_COINS.size() else -1


func is_local() -> bool:
	return not remote and not ghost


## A start spot near the jetty, fanned out by player index.
func reset_to_start() -> void:
	var a := (index - 3.5) * 0.45
	position = Vector3(sin(a) * 7.0, 0.0, Lake.JETTY_END_Z - 3.0 - cos(a) * 3.0)
	yaw = 0.0
	cam_yaw = 0.0
	vel = Vector3.ZERO
	target_pos = position
	target_yaw = yaw
	rotation.y = yaw


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func net_point() -> Vector3:
	return global_position + forward() * 1.6


# --- Input ---------------------------------------------------------------------------

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
		if st.length() > 0.18:
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
	if key_set == 1 and Input.is_physical_key_pressed(KEY_SPACE):
		return true
	return key_set == 0 and (Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_0))


func call_pressed() -> bool:
	if joy >= 0 and (Input.is_joy_button_pressed(joy, JOY_BUTTON_X) or Input.is_joy_button_pressed(joy, JOY_BUTTON_Y)):
		return true
	if key_set == 1 and Input.is_physical_key_pressed(KEY_F):
		return true
	return key_set == 0 and (Input.is_physical_key_pressed(KEY_SLASH) or Input.is_physical_key_pressed(KEY_KP_PERIOD))


func _input(event: InputEvent) -> void:
	if not mouse_look or not active:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_dx += mm.relative.x


# --- Simulation ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active or remote or ghost:
		return
	sim(delta)
	if main.net.mode == "client":
		main.net.send_state(position, yaw, row_amount, index)


func sim(delta: float) -> void:
	var s := move_input()
	var dir := Vector3.ZERO
	if bot:
		dir = Vector3(bot_dir.x, 0.0, bot_dir.z).limit_length(1.0)
	elif s.length() > 0.01:
		dir = Basis(Vector3.UP, cam_yaw) * Vector3(s.x, 0.0, s.y)
	var amount := dir.length()
	if amount > 0.05:
		var want := atan2(-dir.x, -dir.z)
		var diff := wrapf(want - yaw, -PI, PI)
		yaw += clampf(diff, -TURN * delta, TURN * delta)
		var push := cos(clampf(diff, -PI * 0.5, PI * 0.5))
		vel += forward() * ACCEL * SPEED_MULT[level] * amount * maxf(push, 0.0) * delta
	vel *= exp(-0.9 * delta)
	vel = vel.limit_length(max_speed())
	# Sideways drag, so it handles like a boat rather than an ice cube.
	var side := Vector3(cos(yaw), 0.0, -sin(yaw))
	vel -= side * vel.dot(side) * (1.0 - exp(-3.0 * delta))
	position += vel * delta
	_collide()
	position.y = 0.0
	rotation.y = yaw
	row_amount = lerpf(row_amount, amount, 1.0 - exp(-5.0 * delta))
	# Buttons (edge-triggered).
	var a := bot_net if bot else action_pressed()
	if a and not a_was and main.state != "over":
		swing_net()
	a_was = a
	var x := bot_call if bot else call_pressed()
	if x and not x_was:
		call_fish()
	x_was = x
	if net_cool > 0.0:
		net_cool -= delta
	if call_cool > 0.0:
		call_cool -= delta


func _collide() -> void:
	var off := Vector3(position.x - Lake.LAKE_C.x, 0.0, position.z - Lake.LAKE_C.z)
	var lim := Lake.LAKE_R - 1.4
	if off.length() > lim:
		var n := off.normalized()
		position = Lake.LAKE_C + n * lim
		var vn := vel.dot(n)
		if vn > 0.0:
			vel -= n * vn * 1.4
	# The jetty: a box from its end to the shore.
	var hw := 1.6
	if position.z > Lake.JETTY_END_Z - 1.0 and absf(position.x) < hw:
		if position.z - (Lake.JETTY_END_Z - 1.0) < hw - absf(position.x):
			position.z = Lake.JETTY_END_Z - 1.0
			vel.z = minf(vel.z, 0.0)
		else:
			position.x = signf(position.x if position.x != 0.0 else 1.0) * hw
			vel.x *= -0.3
	# The trophy and journal boards stand in the shallows.
	for ob in [Lake.BOARD_L, Lake.BOARD_R]:
		var bo: Vector3 = ob
		var d := Vector3(position.x - bo.x, 0.0, position.z - bo.z)
		if d.length() < 1.9 and d.length() > 0.001:
			position += d.normalized() * (1.9 - d.length())
			vel -= d.normalized() * minf(0.0, vel.dot(d.normalized()))
	for o in main.players:
		if o == self or o.index == 0 or not o.active:
			continue
		var d: Vector3 = position - o.position
		d.y = 0.0
		var l := d.length()
		if l < 1.7 and l > 0.001:
			position += d / l * (1.7 - l) * 0.5
			vel += d / l * 0.3


func swing_net() -> void:
	if net_cool > 0.0:
		return
	net_cool = 0.7
	net_anim = 1.0
	if main.net.mode == "client":
		main.net.send_action("net", [position, yaw], index)
	else:
		main.on_boat_net(self)


func call_fish() -> void:
	if call_cool > 0.0:
		return
	call_cool = 3.0
	if main.net.mode == "client":
		main.net.send_action("call", [position], index)
	else:
		main.on_boat_call(self)


func apply_remote_state(pos: Vector3, y: float, rowing: float) -> void:
	target_pos = pos
	target_yaw = y
	row_amount = rowing
	net_started = true


func _process(delta: float) -> void:
	if remote and active:
		if position.distance_to(target_pos) > 4.0:
			position = target_pos
		else:
			position = position.lerp(target_pos, 1.0 - exp(-14.0 * delta))
		yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-14.0 * delta))
		rotation.y = yaw
	if not active:
		return
	# Rowing and bobbing animation.
	row_phase += delta * (1.5 + row_amount * 5.0)
	var bob := sin(row_phase * 0.7 + index) * 0.03
	hull.position.y = bob
	hull.rotation.z = sin(row_phase * 0.5 + index) * 0.04
	for i in oars.size():
		var s := -1.0 if i == 0 else 1.0
		oars[i].rotation.y = s * sin(row_phase) * 0.5 * row_amount
		oars[i].rotation.z = s * (cos(row_phase) * 0.15 * row_amount)
	if net_anim > 0.0:
		net_anim = maxf(0.0, net_anim - delta * 1.8)
	var swing := sin(net_anim * PI)
	net_pivot.rotation.x = deg_to_rad(25.0 - 55.0 * swing)
	net_pivot.rotation.y = -swing * 0.6
	main.face_label(tag)
	var speed := vel.length() if not remote else row_amount * MAX_SPEED
	wake.emitting = speed > 0.6 or row_amount > 0.3
	if sparkle != null:
		sparkle.emitting = wake.emitting
	if camera != null:
		_update_camera(delta)
	if hud_label != null:
		hud_label.text = main.hud_text(self)
	if tip_label != null:
		main.update_tip(self, tip_label)


func _update_camera(delta: float) -> void:
	var turn := cam_input()
	if mouse_dx != 0.0:
		cam_yaw -= mouse_dx * 0.004
		mouse_dx = 0.0
		cam_idle_t = 0.0
	if absf(turn) > 0.01:
		cam_yaw -= turn * 2.4 * delta
		cam_idle_t = 0.0
	else:
		cam_idle_t += delta
	# Drift behind the boat when the player isn't steering the camera.
	if cam_idle_t > 1.0 and vel.length() > 0.6:
		cam_yaw = lerp_angle(cam_yaw, yaw, 1.0 - exp(-1.0 * delta))
	var back := Basis(Vector3.UP, cam_yaw) * Vector3(0.0, 0.0, 5.2)
	var want_pos := global_position + back + Vector3(0, 2.7, 0)
	if not camera.has_meta("placed"):
		camera.set_meta("placed", true)
		camera.global_position = want_pos
	camera.global_position = camera.global_position.lerp(want_pos, 1.0 - exp(-6.0 * delta))
	var look := global_position + Basis(Vector3.UP, cam_yaw) * Vector3(0, 0.6, -3.0)
	camera.look_at(look, Vector3.UP)
