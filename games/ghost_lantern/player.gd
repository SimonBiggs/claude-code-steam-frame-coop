extends CharacterBody3D
## One Ghost Lantern player.
## Player 1 (role "lantern"): carries the spirit lantern. In VR it's the right hand (trigger focuses the
## beam) and the left hand holds a bell (shake it, or pull the left trigger, to scare ghosts away).
## On a flat screen the lantern is held in front of the camera: Space / left click focus, E rings the bell.
## TV players (role "vacuum"): first-person ghost vacuums. Hold fire (RT / Space / click / Enter) to suck
## in a ghost that the lantern is lighting up.

const SPEED := 4.6
const MAX_COURAGE := 100.0
const REVIVE_TIME := 2.5
const REVIVE_RANGE := 2.4
const EYE_HEIGHT := 1.5
const STICK_YAW_SPEED := 2.8
const STICK_PITCH_SPEED := 2.0
const KEY_TURN_SPEED := 2.4
const MOUSE_SENS := 0.0028
const BELL_COOLDOWN := 6.0
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "fire": KEY_SPACE, "alt": KEY_E},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "fire": KEY_ENTER, "alt": KEY_CTRL},
]
const CONE_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(0.8, 1.0, 0.75);
uniform float energy = 0.3;
void fragment() {
	float along = UV.y;
	float edge = abs(dot(NORMAL, VIEW));
	float a = smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.45, 1.0, along));
	float motes = 0.85 + 0.15 * sin(along * 40.0 - TIME * 2.0 + UV.x * 30.0);
	ALBEDO = color * energy * a * (0.25 + 0.75 * edge) * motes;
}
"""
const SUCK_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(0.5, 1.0, 0.7);
void fragment() {
	float swirl = 0.5 + 0.5 * sin(UV.x * 37.7 + UV.y * 14.0 + TIME * 16.0);
	float fade = (1.0 - UV.y) * smoothstep(0.0, 0.1, UV.y);
	ALBEDO = color * swirl * fade * 0.6;
}
"""

var index := 0
var joy := -1
var color := Color.WHITE
var main
var camera: Camera3D
var hud
var role := "vacuum"

var courage := MAX_COURAGE
var is_down := false
var revive_progress := 0.0
var yaw := 0.0
var pitch := 0.0
var invuln_t := 0.0
var flash_t := 0.0
var shake := 0.0
var bob_t := 0.0
var shiver_t := 0.0

var pivot: Node3D
var body_mat: StandardMaterial3D
var revive_ring: MeshInstance3D
var revive_fill: MeshInstance3D
var tag: Label3D

# VR (set by attach_xr()).
var vr := false
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var wrist_label: Label3D
var snap_ready := true
var vr_velocity := Vector3.ZERO

# Networking.
var remote := false
var ghost := false
var active := true
var key_set := -1  # -1 auto (P1 WASD, others arrows), 0 WASD, 1 arrows, 2 no keyboard (controller only)
var bot_fire := false  # test hook: the headless bot holds fire for this player
var mouse_look := false
var net_target := Vector3.ZERO
var net_started := false
var net_head := Transform3D()
var net_hand := Transform3D()
var net_lhand := Transform3D()
var ghost_head: Node3D

# Lantern (player 1).
var lantern: Node3D
var lantern_light: SpotLight3D
var beam_cone: MeshInstance3D
var lantern_glow: StandardMaterial3D
var focus := false
var bell: Node3D
var bell_cd := 0.0
var alt_was_held := false
var shake_meter := 0.0
var last_lhand := Vector3.ZERO
var snuff_t := 0.0  # a snuffer blew the lantern out: dark while > 0
var lantern_label: Label3D
var cheer_helper  # who is cheering us up (gets the credit)

# Vacuum (TV players).
var vac_on := false
var vac_sent := false
var vac_view: Node3D
var suck_view: MeshInstance3D
var suck_body: MeshInstance3D
var vac_sound_t := 0.0
var flashlight: SpotLight3D


## Render layers: bit 0 = world, bits 1..7 = player bodies (index 0..6), bits 8..14 = first-person viewmodels.
const BODY_BITS := 0xFE


func body_layer() -> int:
	return 2 << index


func viewmodel_layer() -> int:
	return 256 << index


func camera_cull_mask() -> int:
	return 1 | (BODY_BITS & ~body_layer()) | viewmodel_layer()


func _ready() -> void:
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.5
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.75
	add_child(cs)
	net_target = position

	pivot = Node3D.new()
	add_child(pivot)
	body_mat = main.make_material(color, 0.35)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.2
	cap.radial_segments = 14
	cap.rings = 4
	body.mesh = cap
	body.material_override = body_mat
	body.position.y = 0.6
	pivot.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.28
	hs.height = 0.56
	hs.radial_segments = 14
	hs.rings = 7
	head.mesh = hs
	head.material_override = main.make_material(Color(1.0, 0.85, 0.72), 0.15)
	head.position.y = 1.42
	pivot.add_child(head)
	for sx in [-0.1, 0.1]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.045
		es.height = 0.09
		es.radial_segments = 8
		es.rings = 4
		eye.mesh = es
		eye.material_override = main.make_material(Color(0.05, 0.03, 0.08), 0.0)
		eye.position = Vector3(sx, 1.46, -0.25)
		pivot.add_child(eye)
	if role == "vacuum":
		var tank := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.18
		tm.bottom_radius = 0.18
		tm.height = 0.6
		tm.radial_segments = 10
		tank.mesh = tm
		tank.material_override = main.make_material(color.darkened(0.3), 0.6)
		tank.position = Vector3(0, 0.95, 0.38)
		pivot.add_child(tank)
		var nozzle := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.07
		nm.bottom_radius = 0.1
		nm.height = 0.8
		nm.radial_segments = 8
		nozzle.mesh = nm
		nozzle.material_override = main.make_material(Color(0.3, 0.3, 0.38), 0.0)
		nozzle.position = Vector3(0.3, 0.95, -0.4)
		nozzle.rotation.x = -PI / 2.0
		pivot.add_child(nozzle)
		suck_body = _make_suck_cone()
		pivot.add_child(suck_body)
		suck_body.position = Vector3(0.3, 0.95, -0.8)
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = color
	tag.position.y = 2.1
	pivot.add_child(tag)
	_set_layers(pivot, body_layer())
	if role == "vacuum":
		suck_body.layers = body_layer()

	revive_ring = MeshInstance3D.new()
	var rr := TorusMesh.new()
	rr.inner_radius = REVIVE_RANGE - 0.08
	rr.outer_radius = REVIVE_RANGE
	revive_ring.mesh = rr
	revive_ring.material_override = main.make_material(color, 1.5)
	revive_ring.position.y = 0.04
	revive_ring.visible = false
	add_child(revive_ring)
	revive_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = REVIVE_RANGE
	disc.bottom_radius = REVIVE_RANGE
	disc.height = 0.02
	revive_fill.mesh = disc
	var fm: StandardMaterial3D = main.make_material(color, 1.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color.a = 0.35
	revive_fill.material_override = fm
	revive_fill.position.y = 0.03
	revive_fill.visible = false
	add_child(revive_fill)

	if role == "lantern":
		lantern = _make_lantern()
		add_child(lantern)
		lantern.top_level = true
		lantern.global_transform = head_transform()
		if ghost:
			bell = _make_bell()
			add_child(bell)
			bell.top_level = true


## Called by main once the split-screen camera exists.
func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 78.0
	camera.near = 0.05
	if role == "vacuum":
		vac_view = _make_vacuum()
		camera.add_child(vac_view)
		vac_view.position = Vector3(0.24, -0.22, -0.45)
		suck_view = _make_suck_cone()
		vac_view.add_child(suck_view)
		suck_view.position = Vector3(0, 0, -0.75)
		_set_layers(vac_view, viewmodel_layer())
		# A weak torch: helps see the furniture, but only the lantern reveals ghosts.
		flashlight = SpotLight3D.new()
		flashlight.light_color = Color(1.0, 0.92, 0.75)
		flashlight.light_energy = 0.7
		flashlight.spot_range = 8.0
		flashlight.spot_angle = 26.0
		flashlight.shadow_enabled = false
		camera.add_child(flashlight)
	_update_camera(0.0)


## VR player: the headset is the camera, the right hand holds the lantern, the left the bell.
func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	camera = cam
	cam.cull_mask = camera_cull_mask()
	cam.near = 0.05
	if lantern:
		lantern.queue_free()
	lantern = _make_lantern()
	hand_r.add_child(lantern)
	lantern.position = Vector3(0.0, -0.02, -0.06)
	bell = _make_bell()
	hand_l.add_child(bell)
	bell.position = Vector3(0.0, -0.05, -0.04)
	wrist_label = Label3D.new()
	wrist_label.pixel_size = 0.0005
	wrist_label.font_size = 48
	wrist_label.outline_size = 24
	wrist_label.outline_modulate = Color.BLACK
	wrist_label.modulate = color.lightened(0.3)
	wrist_label.position = Vector3(0.0, 0.07, 0.12)
	wrist_label.rotation_degrees = Vector3(-55, 0, 0)
	wrist_label.no_depth_test = true
	hand_l.add_child(wrist_label)
	_set_layers(wrist_label, viewmodel_layer())


func _make_lantern() -> Node3D:
	var l := Node3D.new()
	var metal: StandardMaterial3D = main.make_material(Color(0.22, 0.16, 0.12), 0.0)
	metal.metallic = 0.6
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.05
	bm.bottom_radius = 0.06
	bm.height = 0.03
	bm.radial_segments = 8
	base.mesh = bm
	base.material_override = metal
	base.position = Vector3(0, -0.08, 0)
	l.add_child(base)
	var glass := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.05
	gm.height = 0.12
	gm.radial_segments = 10
	gm.rings = 5
	glass.mesh = gm
	lantern_glow = main.make_material(Color(0.75, 1.0, 0.7), 4.0)
	glass.material_override = lantern_glow
	glass.position = Vector3(0, -0.02, 0)
	l.add_child(glass)
	var handle := MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.035
	hm.outer_radius = 0.045
	hm.rings = 10
	hm.ring_segments = 4
	handle.mesh = hm
	handle.material_override = metal
	handle.position = Vector3(0, 0.06, 0)
	handle.rotation.x = PI / 2.0
	l.add_child(handle)
	for mi in [base, glass, handle]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern_light = SpotLight3D.new()
	lantern_light.light_color = Color(0.78, 1.0, 0.72)
	lantern_light.light_energy = 4.0
	lantern_light.spot_angle = 22.0
	lantern_light.spot_range = 11.0
	lantern_light.spot_attenuation = 0.6
	lantern_light.shadow_enabled = false
	l.add_child(lantern_light)
	# The visible cone of spirit light, pointing along -Z.
	var beam_pivot := Node3D.new()
	beam_pivot.rotation.x = PI / 2.0
	l.add_child(beam_pivot)
	beam_cone = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam_cone.mesh = cm
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = CONE_SHADER
	beam_cone.material_override = sm
	beam_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_pivot.add_child(beam_cone)
	return l


func _make_bell() -> Node3D:
	var b := Node3D.new()
	var brass: StandardMaterial3D = main.make_material(Color(0.95, 0.75, 0.3), 0.4)
	brass.metallic = 0.8
	brass.roughness = 0.3
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.06
	cm.height = 0.08
	cm.radial_segments = 10
	cup.mesh = cm
	cup.material_override = brass
	b.add_child(cup)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.02
	km.height = 0.04
	km.radial_segments = 8
	km.rings = 4
	knob.mesh = km
	knob.material_override = brass
	knob.position.y = 0.05
	b.add_child(knob)
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.012
	gm.bottom_radius = 0.012
	gm.height = 0.1
	gm.radial_segments = 6
	grip.mesh = gm
	grip.material_override = main.make_material(Color(0.3, 0.15, 0.1), 0.0)
	grip.position.y = 0.11
	b.add_child(grip)
	return b


func _make_vacuum() -> Node3D:
	var v := Node3D.new()
	var body_m: StandardMaterial3D = main.make_material(color.darkened(0.2), 0.5)
	var tube := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.045
	tm.bottom_radius = 0.07
	tm.height = 0.6
	tm.radial_segments = 10
	tube.mesh = tm
	tube.material_override = main.make_material(Color(0.3, 0.3, 0.38), 0.0)
	tube.rotation.x = -PI / 2.0
	tube.position.z = -0.3
	v.add_child(tube)
	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.14, 0.16, 0.22)
	housing.mesh = hm
	housing.material_override = body_m
	housing.position = Vector3(0, -0.02, 0.05)
	v.add_child(housing)
	var mouth := MeshInstance3D.new()
	var mm := TorusMesh.new()
	mm.inner_radius = 0.05
	mm.outer_radius = 0.08
	mm.rings = 12
	mm.ring_segments = 4
	mouth.mesh = mm
	mouth.material_override = main.make_material(color, 2.0)
	mouth.rotation.x = PI / 2.0
	mouth.position.z = -0.6
	v.add_child(mouth)
	for mi in [tube, housing, mouth]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return v


func _make_suck_cone() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.75
	cm.height = 1.6
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SUCK_SHADER
	sm.set_shader_parameter("color", Vector3(color.r, color.g, color.b).lerp(Vector3.ONE, 0.3))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Narrow end at the nozzle, opening forward (-Z).
	mi.rotation.x = PI / 2.0
	mi.visible = false
	return mi


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


func aim_dir() -> Vector3:
	if vr:
		return -hand_r.global_basis.z
	if camera:
		return -camera.global_basis.z
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0, 0, -1)


func eye_pos() -> Vector3:
	if camera:
		return camera.global_position
	return global_position + Vector3.UP * EYE_HEIGHT


## Where the vacuum sucks from.
func nozzle_pos() -> Vector3:
	return eye_pos() + aim_dir() * 0.6 - Vector3.UP * 0.15


func lantern_lit() -> bool:
	return active and not is_down and lantern != null and snuff_t <= 0.0


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.3)


func _physics_process(delta: float) -> void:
	invuln_t -= delta
	flash_t -= delta
	bell_cd -= delta
	snuff_t = maxf(0.0, snuff_t - delta)
	body_mat.emission_energy_multiplier = 3.0 if flash_t > 0.0 else 0.35
	if not active:
		return
	if ghost:
		_ghost_update(delta)
		return
	if remote:
		_remote_update(delta)
		return
	if vr:
		_vr_update(delta)
	else:
		_read_look(delta)
	if is_down:
		vr_velocity = Vector3.ZERO
		focus = false
		_set_vac(false)
		if main.net.mode == "client":
			revive_fill.scale = Vector3(maxf(revive_progress, 0.01), 1, maxf(revive_progress, 0.01))
		else:
			_update_revive(delta)
		_update_camera(delta)
		main.net.send_state(global_position, yaw, pitch, index)
		return

	var move := _read_move()
	velocity = move * SPEED
	if vr:
		vr_velocity = velocity
	else:
		move_and_slide()
		position.y = 0.0
	bob_t += velocity.length() * delta * 1.8
	_update_camera(delta)
	main.net.send_state(global_position, yaw, pitch, index)

	if role == "lantern":
		focus = hand_r.get_float("trigger") > 0.4 if vr else _fire_held()
		var alt := _alt_held()
		if alt and not alt_was_held:
			try_ring_bell()
		alt_was_held = alt
	else:
		_set_vac(_fire_held())


func _set_vac(on: bool) -> void:
	vac_on = on
	if main.net.mode == "client" and vac_on != vac_sent:
		vac_sent = vac_on
		main.net.send_action("vac", [vac_on], index)


func try_ring_bell() -> void:
	if bell_cd > 0.0 or is_down:
		return
	bell_cd = BELL_COOLDOWN
	if bell:
		var tw := bell.create_tween()
		tw.tween_property(bell, "rotation:z", 0.6, 0.06)
		tw.tween_property(bell, "rotation:z", -0.6, 0.12)
		tw.tween_property(bell, "rotation:z", 0.0, 0.08)
	if vr:
		hand_l.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.25, 0.0)
	var pos: Vector3 = bell.global_position if bell else eye_pos()
	main.ring_bell(self, pos)


func _process(delta: float) -> void:
	_update_tools(delta)
	if not vr or xr_origin == null or vr_velocity == Vector3.ZERO:
		return
	var step := vr_velocity * delta
	if test_move(global_transform, step):
		var inside := test_move(global_transform, Vector3(0.0, 0.001, 0.0))
		if not inside:
			var along_x := Vector3(step.x, 0.0, 0.0)
			var along_z := Vector3(0.0, 0.0, step.z)
			if not test_move(global_transform, along_x):
				step = along_x
			elif not test_move(global_transform, along_z):
				step = along_z
			else:
				return
	xr_origin.global_position += step
	global_position += step


## Lantern beam, bell and vacuum visuals (every machine, every frame).
func _update_tools(delta: float) -> void:
	if lantern:
		if not vr and not ghost:
			# Flat screen: held low and to the right, aimed where the crosshair points.
			var head := head_transform()
			var hold := head.origin + head.basis * Vector3(0.22, -0.2, -0.35)
			var aim_at := head.origin + head.basis * Vector3(0, 0, -8.0)
			lantern.global_transform = Transform3D(Basis.looking_at(aim_at - hold, Vector3.UP), hold)
		var lit := lantern_lit()
		var ang: float = main.lantern_angle()
		var rng: float = main.lantern_range()
		lantern_light.visible = lit
		lantern_light.spot_angle = ang
		lantern_light.spot_range = rng
		lantern_light.light_energy = (5.0 if focus else 3.5) * (0.92 + randf() * 0.08)
		beam_cone.visible = lit
		var r := tan(deg_to_rad(ang)) * rng
		beam_cone.scale = Vector3(r, rng, r)
		beam_cone.position = Vector3(0, -rng / 2.0, 0)
		var bm: ShaderMaterial = beam_cone.material_override
		bm.set_shader_parameter("energy", 0.42 if focus else 0.28)
		lantern_glow.emission_energy_multiplier = (6.0 if focus else 4.0) if lit else 0.3
	if role == "vacuum":
		var on := vac_on and active and not is_down
		if suck_body:
			suck_body.visible = on
		if suck_view:
			suck_view.visible = on
			suck_view.rotation.y += delta * 6.0
		if vac_view:
			vac_view.position = Vector3(0.24 + randf_range(-1, 1) * 0.004 * float(on), -0.22 + sin(bob_t * 0.5) * 0.008, -0.45)
		if on and not remote:
			vac_sound_t -= delta
			if vac_sound_t <= 0.0:
				vac_sound_t = 0.14
				main.local_sound("zap", -18.0, 0.55)


func _update_camera(delta: float) -> void:
	pivot.rotation.y = yaw
	if camera == null or vr:
		return
	shake = maxf(0.0, shake - delta * 3.0)
	var eye := EYE_HEIGHT if not is_down else 0.5
	var bob := sin(bob_t) * 0.04 if not is_down else 0.0
	var shiver := sin(Time.get_ticks_msec() * 0.05) * 0.01 if is_down else 0.0
	camera.global_position = global_position + Vector3(shiver, eye + bob, 0)
	camera.rotation = Vector3(pitch + randf_range(-1, 1) * shake * 0.02,
		yaw + randf_range(-1, 1) * shake * 0.02, 0.3 if is_down else 0.0)
	if vac_view:
		vac_view.visible = not is_down


# --- Input -------------------------------------------------------------------

func keys() -> int:
	return key_set if key_set >= 0 else mini(index, KEYS.size() - 1)


func _key(action: String) -> bool:
	var k := keys()
	if k >= KEYS.size():
		return false
	return Input.is_physical_key_pressed(KEYS[k][action])


func uses_keyboard() -> bool:
	return keys() < KEYS.size()


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
	if vr:
		var s := hand_l.get_vector2("primary")
		if s.length() < 0.15:
			return Vector3.ZERO
		return Basis(Vector3.UP, yaw) * Vector3(s.x, 0.0, -s.y).limit_length(1.0)
	if keys() == 0:
		v = Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	else:
		v.y = float(_key("down")) - float(_key("up"))
	v += _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.18)
	if joy >= 0:
		v += Vector2(
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP)))
	return Basis(Vector3.UP, yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)


func _fire_held() -> bool:
	if vr:
		return hand_r.get_float("trigger") > 0.5
	if bot_fire or _key("fire"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		return Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	return false


## Bell (lantern player) / unused for vacuums.
func _alt_held() -> bool:
	if vr:
		return hand_l.get_float("trigger") > 0.5 or hand_l.is_button_pressed("ax_button")
	if _key("alt"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	if joy >= 0:
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_A) \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT) > 0.4
	return false


## VR restart button on the game-over screen.
func vr_button_held() -> bool:
	return vr and (hand_r.is_button_pressed("ax_button") or hand_l.is_button_pressed("ax_button"))


## Headset drives facing and body position; right stick snap-turns; shaking the left hand rings the bell.
func _vr_update(delta: float) -> void:
	yaw = xr_camera.global_rotation.y
	var head := xr_camera.global_position
	global_position = Vector3(head.x, 0.0, head.z)
	var turn := hand_r.get_vector2("primary").x
	if absf(turn) > 0.7 and snap_ready:
		snap_ready = false
		var rot := Basis(Vector3.UP, -signf(turn) * deg_to_rad(30.0))
		var pivot_pt := xr_camera.global_position
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, pivot_pt + rot * (xr_origin.global_position - pivot_pt))
	elif absf(turn) < 0.3:
		snap_ready = true
	# Shake detection, in the play-space so walking with the stick doesn't count.
	var lp := hand_l.position
	var hand_speed := (lp - last_lhand).length() / maxf(delta, 0.001)
	last_lhand = lp
	if hand_speed > 1.6:
		shake_meter += delta * 3.0
	shake_meter = maxf(0.0, shake_meter - delta * 1.2)
	if shake_meter > 0.45:
		shake_meter = 0.0
		try_ring_bell()
	var status := "SPOOKED! Friends, come cheer me up!" if is_down else ("Bell ready: shake it!" if bell_cd <= 0.0 else "Bell: %d s" % ceili(bell_cd))
	if main.net.mode == "host" and not main.net.connected:
		status = "Waiting for the TV players…"
	wrist_label.text = "COURAGE %d\nNIGHT %d   PHOTOS %d/%d\n%s" % [maxi(0, int(courage)), main.night, main.photos_left(), main.photos.size(), status]
	_update_lantern_label()


## VR: photos, courage and bell right above the lantern, where the lantern-bearer always looks.
func _update_lantern_label() -> void:
	if lantern_label == null:
		lantern_label = Label3D.new()
		lantern_label.font_size = 44
		lantern_label.outline_size = 14
		lantern_label.pixel_size = 0.0007
		lantern_label.no_depth_test = true
		lantern_label.render_priority = 6
		hand_r.add_child(lantern_label)
		lantern_label.position = Vector3(0.0, 0.1, 0.02)
		lantern_label.rotation_degrees = Vector3(-30, 0, 0)
		_set_layers(lantern_label, viewmodel_layer())
	var lines: Array[String] = ["PHOTOS %d/%d   ♥ %d" % [main.photos_left(), main.photos.size(), maxi(0, int(courage))]]
	if snuff_t > 0.0:
		lines.append("LANTERN OUT! %d" % ceili(snuff_t))
	elif bell_cd <= 0.0:
		lines.append("BELL READY - shake left hand")
	var d = main.director()
	if d.last_chance_t > 0.0:
		lines.append("CATCH THE KING: %d s" % ceili(d.last_chance_t))
	lantern_label.text = "\n".join(lines)
	var frac := clampf(float(main.photos_left()) / maxf(main.photos.size(), 1.0), 0.0, 1.0)
	lantern_label.modulate = Color(1.0, 0.45, 0.4) if frac <= 0.25 or snuff_t > 0.0 else Color(1.0, 0.92, 0.6)


# --- Courage & cheering up ---------------------------------------------------

func spook(amount: float, from_pos: Vector3) -> void:
	if is_down or invuln_t > 0.0:
		return
	if remote:
		main.net.event("hurt", [index, from_pos])
	courage -= amount
	invuln_t = 1.2
	flash_t = 0.12
	shake = maxf(shake, 0.4)
	if hud:
		hud.hurt()
	main.sound("hurt", -4.0, 1.3 + index * 0.15)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.4, 0.6, 0.2)
	if vr:
		hand_l.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.15, 0.0)
		hand_r.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.15, 0.0)
	if courage <= 0.0:
		_go_down()


func _go_down() -> void:
	courage = 0.0
	is_down = true
	revive_progress = 0.0
	_apply_down_pose(true)
	main.burst(global_position + Vector3.UP, Color(0.6, 1.0, 0.7), 20)
	main.sound("down", -2.0, 1.2)
	print("Player %d is spooked" % (index + 1))


func _update_revive(delta: float) -> void:
	var helper_near := false
	for p in main.players:
		if p != self and p.active and not p.is_down and p.global_position.distance_to(global_position) <= REVIVE_RANGE:
			if not helper_near:
				cheer_helper = p
			helper_near = true
	if helper_near:
		revive_progress += delta / REVIVE_TIME
	else:
		revive_progress = maxf(0.0, revive_progress - delta * 0.25)
	var s := maxf(revive_progress, 0.01)
	revive_fill.scale = Vector3(s, 1, s)
	if revive_progress >= 1.0:
		if cheer_helper != null and is_instance_valid(cheer_helper):
			main.director().add_stat(cheer_helper, "cheers", 1)
			main.popup(global_position + Vector3.UP * 2.6, "P%d CHEERED UP P%d!" % [cheer_helper.index + 1, index + 1], cheer_helper.color)
		revive(0.6)


func revive(fraction: float) -> void:
	is_down = false
	courage = MAX_COURAGE * fraction
	invuln_t = 2.0
	_apply_down_pose(false)
	main.burst(global_position + Vector3.UP, Color(1.0, 0.85, 0.4), 20)
	main.sound("revive")
	main.popup(global_position + Vector3.UP * 2.0, "BRAVE AGAIN!", Color(1.0, 0.85, 0.4))


func _apply_down_pose(down: bool) -> void:
	pivot.rotation.x = 0.0
	pivot.scale = Vector3(1.0, 0.6, 1.0) if down else Vector3.ONE
	revive_ring.visible = down
	revive_fill.visible = down
	if down:
		revive_fill.scale = Vector3(0.01, 1, 0.01)


# --- Networked co-op ---------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if camera:
		return camera.global_transform
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), global_position + Vector3.UP * EYE_HEIGHT)


func hand_transform() -> Transform3D:
	if lantern and not ghost:
		return lantern.global_transform
	if vr:
		return hand_r.global_transform
	return head_transform()


func left_hand_transform() -> Transform3D:
	return hand_l.global_transform if vr else Transform3D()


func set_active(on: bool) -> void:
	active = on
	visible = on
	collision_layer = 2 if on else 0


## [pos, yaw, pitch, courage, is_down, revive, head, hand, lhand, active, vac_on, focus, bell_cd]
func net_state() -> Array:
	return [global_position, yaw, pitch, courage, is_down, revive_progress, head_transform(),
		hand_transform(), left_hand_transform(), active, vac_on, focus, bell_cd, snuff_t]


## Host: latest position and view of a TV player.
func apply_remote_state(pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	net_target = Vector3(pos.x, 0.0, pos.z)
	yaw = new_yaw
	pitch = new_pitch
	if not net_started:
		net_started = true
		global_position = net_target


## Client: authoritative state from the host's snapshot.
func apply_net_state(st: Array) -> void:
	courage = st[3]
	revive_progress = st[5]
	if st[9] != active:
		set_active(st[9])
		main.on_player_activity_changed(self)
	if ghost:
		net_target = st[0]
		yaw = st[1]
		pitch = st[2]
		net_head = st[6]
		net_hand = st[7]
		net_lhand = st[8]
		vac_on = st[10]
		focus = st[11]
		bell_cd = st[12]
		if st.size() > 13:
			snuff_t = st[13]
		if not net_started:
			net_started = true
			global_position = net_target
	var down: bool = st[4]
	if down != is_down:
		is_down = down
		_apply_down_pose(down)
		if down:
			shake = 1.0
		else:
			invuln_t = 2.0


## Client: the host says our player got spooked from `from_pos`.
func on_remote_hurt(_from_pos: Vector3) -> void:
	flash_t = 0.12
	shake = maxf(shake, 0.4)
	if hud:
		hud.hurt()
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.4, 0.6, 0.2)


func _ghost_update(delta: float) -> void:
	global_position = global_position.lerp(net_target, 1.0 - exp(-15.0 * delta))
	pivot.rotation.y = yaw
	if ghost_head == null:
		ghost_head = Node3D.new()
		add_child(ghost_head)
		var helmet := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.16
		hs.height = 0.3
		hs.radial_segments = 12
		hs.rings = 6
		helmet.mesh = hs
		helmet.material_override = body_mat
		ghost_head.add_child(helmet)
		_set_layers(ghost_head, body_layer())
	if net_head != Transform3D():
		ghost_head.global_transform = ghost_head.global_transform.interpolate_with(net_head.orthonormalized(), 1.0 - exp(-20.0 * delta))
	if lantern and net_hand != Transform3D():
		lantern.global_transform = lantern.global_transform.interpolate_with(net_hand.orthonormalized(), 1.0 - exp(-25.0 * delta))
	if bell:
		bell.visible = net_lhand != Transform3D()
		if bell.visible:
			bell.global_transform = net_lhand.orthonormalized() * Transform3D(Basis(), Vector3(0.0, -0.05, -0.04))
	if is_down:
		var fill := maxf(revive_progress, 0.01)
		revive_fill.scale = Vector3(fill, 1, fill)


func _remote_update(delta: float) -> void:
	global_position = net_target
	pivot.rotation.y = yaw
	if is_down:
		vac_on = false
		_update_revive(delta)
