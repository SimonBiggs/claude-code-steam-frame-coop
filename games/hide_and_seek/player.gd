extends CharacterBody3D
## One Hide and Seek player.
## Player 1 (role "seeker"): VR, or first person with keyboard+mouse / controller in split screen. Counts with
## eyes covered, then hunts with a torch in the right hand: touch a hider with either hand, or point the torch
## at one within 3 m and pull the trigger.
## TV players (role "hider"): small round critters in third person. A / Space / Enter / click toggles the
## disguise (something that fits in with the room: lamp, pot plant, box, teddy or beach ball; no moving
## while disguised); X / Y / RB / E / right click squeaks; B jumps.
## Found hiders go to JAIL (the cage in the hall) and spectate: their camera follows the seeker. A free
## hider who rings the jail bell lets them all out.
## The seeker can SNIFF (Q / LB, or in VR put your left hand on your nose): hiders close by sneeze.

const HIDER_SPEED := 4.2
const SEEKER_SPEED := 3.8
const VR_SPEED := 2.8
const EYE_HEIGHT := 1.55
const HIDER_HEIGHT := 0.9
const SEEKER_EYE := 1.5  # VR: the seeker's eyes are fitted to this height (sitting or a short kid is fine)
const STICK_YAW_SPEED := 2.8
const STICK_PITCH_SPEED := 2.0
const KEY_TURN_SPEED := 2.4
const MOUSE_SENS := 0.0028
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "fire": KEY_SPACE, "alt": KEY_E},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "fire": KEY_ENTER, "alt": KEY_CTRL},
]
const BEAM_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.95, 0.7);
uniform float energy = 0.25;
void fragment() {
	float along = UV.y;
	float edge = abs(dot(NORMAL, VIEW));
	float a = smoothstep(0.0, 0.1, along) * (1.0 - smoothstep(0.35, 1.0, along));
	ALBEDO = color * energy * a * (0.2 + 0.8 * edge);
}
"""

var index := 0
var joy := -1
var color := Color.WHITE
var main
var camera: Camera3D
var hud
var role := "hider"

var yaw := 0.0
var pitch := 0.0
var bob_t := 0.0
var flash_t := 0.0

var pivot: Node3D
var body_mat: StandardMaterial3D
var critter: Node3D
var eyes: MeshInstance3D
var eye_mat: StandardMaterial3D
var blink_t := 2.0
var walk := 0.0
var anim_t := 0.0
var last_pos := Vector3.ZERO
var sniff_was := false
var nose_t := 0.0
var tag: Label3D
var prop_node: Node3D
var prop_shown := -1

# Round state (decided by the host, mirrored to clients).
var found := false
var late := false  # joined mid-round: spectates until the next round
var prop_kind := -1  # -1 = not disguised, else WorldScript.PROP_NAMES index
var prop_hold_t := 0.0  # client: trust our own disguise toggle for a moment over the snapshots
var taunt_cd := 0.0
var fire_was := false
var alt_was := false

# VR (set by attach_xr()).
var vr := false
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var snap_ready := true
var vr_velocity := Vector3.ZERO
var blindfold: MeshInstance3D
var mitten_l: MeshInstance3D
var calibrated := false
var calib_t := 0.0
var calib_y := 0.0
var off_t := 0.0
var trigger_was := false

# Torch (seeker).
var torch: Node3D
var torch_light: SpotLight3D
var torch_beam: MeshInstance3D
var torch_glow: StandardMaterial3D
var torch_flash := 0.0

# Networking.
var remote := false
var ghost := false
var active := true
var key_set := -1  # -1 auto (P1 WASD, others arrows), 0 WASD, 1 arrows, 2 no keyboard (controller only)
var bot_fire := false  # test hooks: the headless bot holds buttons for this player
var bot_alt := false
var mouse_look := false
var net_target := Vector3.ZERO
var net_started := false
var net_head := Transform3D()
var net_hand := Transform3D()
var net_lhand := Transform3D()
var ghost_head: Node3D
var ghost_mitten: MeshInstance3D


## Render layers: bit 0 = world, bits 1..7 = player bodies (index 0..6), bits 8..14 = first-person viewmodels,
## bit 16 = name tags (only the hiders' cameras draw them, so tags never give anyone away).
const BODY_BITS := 0xFE
const TAG_LAYER := 1 << 16


func body_layer() -> int:
	return 2 << index


func viewmodel_layer() -> int:
	return 256 << index


func camera_cull_mask() -> int:
	if role == "seeker":
		return 1 | (BODY_BITS & ~body_layer()) | viewmodel_layer()
	return 1 | BODY_BITS | viewmodel_layer() | TAG_LAYER


func _ready() -> void:
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3 if role == "hider" else 0.32
	shape.height = HIDER_HEIGHT if role == "hider" else 1.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape.height / 2.0
	add_child(cs)
	net_target = position
	pivot = Node3D.new()
	add_child(pivot)
	body_mat = main.make_material(color, 0.15)
	if role == "hider":
		_build_critter()
	else:
		_build_seeker_body()
	tag = Label3D.new()
	tag.text = "P%d" % (index + 1)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = color
	tag.position.y = 1.3 if role == "hider" else 2.0
	add_child(tag)
	_set_layers(pivot, body_layer())
	tag.layers = TAG_LAYER
	if role == "seeker":
		torch = _make_torch()
		add_child(torch)
		torch.top_level = true
		torch.global_transform = head_transform()


func _sphere(r: float, segs: int = 14) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(4, segs / 2)
	return sm


func _mesh(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A round, friendly critter with big eyes and a little party hat. The body, cheeks, hat and feet are
## baked into one vertex-coloured mesh and the eyes into another (they blink): two draw calls a critter.
func _build_critter() -> void:
	var key := "hs_critter_%s" % color.to_html()
	if not main.has_meta(key):
		var cap := CapsuleMesh.new()
		cap.radius = 0.32
		cap.height = 0.82
		cap.radial_segments = 14
		cap.rings = 4
		var hat := CylinderMesh.new()
		hat.top_radius = 0.0
		hat.bottom_radius = 0.13
		hat.height = 0.28
		hat.radial_segments = 10
		var parts: Array = [[cap, Transform3D(Basis(), Vector3(0, 0.41, 0)), color]]
		for sx in [-0.2, 0.2]:
			parts.append([_sphere(0.05, 8), Transform3D(Basis(), Vector3(sx, 0.46, -0.24)), Color(1.0, 0.55, 0.6)])
		parts.append([hat, Transform3D(Basis(Vector3.BACK, -0.2), Vector3(0.04, 0.92, 0.0)), color.lightened(0.45)])
		parts.append([_sphere(0.04, 8), Transform3D(Basis(), Vector3(0.07, 1.06, 0.0)), Color(1, 1, 1)])
		for sx in [-0.14, 0.14]:
			parts.append([_sphere(0.1, 8), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1.4)), Vector3(sx, 0.06, -0.06)), color.darkened(0.25)])
		# A tiny smile.
		var smile := TorusMesh.new()
		smile.inner_radius = 0.035
		smile.outer_radius = 0.048
		smile.rings = 8
		smile.ring_segments = 4
		parts.append([smile, Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.0, 1.0, 0.5)), Vector3(0, 0.45, -0.3)), Color(0.45, 0.15, 0.2)])
		main.set_meta(key, main.merged_mesh(parts))
		var eye_parts: Array = []
		for sx in [-0.11, 0.11]:
			eye_parts.append([_sphere(0.085, 10), Transform3D(Basis(), Vector3(sx, 0.0, 0.0)), Color(1, 1, 1)])
			eye_parts.append([_sphere(0.045, 8), Transform3D(Basis(), Vector3(sx, 0.005, -0.075)), Color(0.05, 0.05, 0.08)])
		main.set_meta("hs_critter_eyes", main.merged_mesh(eye_parts))
	critter = Node3D.new()
	pivot.add_child(critter)
	var body := MeshInstance3D.new()
	body.mesh = main.get_meta(key)
	body.material_override = main.vertex_mat()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	critter.add_child(body)
	eyes = MeshInstance3D.new()
	eyes.mesh = main.get_meta("hs_critter_eyes")
	eye_mat = StandardMaterial3D.new()
	eye_mat.vertex_color_use_as_albedo = true
	eye_mat.vertex_color_is_srgb = true
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.0, 0.0, 0.0)
	eyes.material_override = eye_mat
	eyes.position = Vector3(0, 0.58, -0.26)
	eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	critter.add_child(eyes)


## The seeker as the hiders see them: a tall friendly grown-up in a stripy jumper.
func _build_seeker_body() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.24
	cm.bottom_radius = 0.3
	cm.height = 1.15
	cm.radial_segments = 14
	_mesh(pivot, cm, body_mat, Vector3(0, 0.62, 0))
	var head := Node3D.new()
	head.name = "Head"
	pivot.add_child(head)
	head.position.y = 1.5
	_head_parts(head)


func _head_parts(head: Node3D) -> void:
	_mesh(head, _sphere(0.2, 14), main.make_material(Color(1.0, 0.84, 0.7), 0.1), Vector3.ZERO)
	var black: StandardMaterial3D = main.make_material(Color(0.05, 0.05, 0.08), 0.0)
	for sx in [-0.07, 0.07]:
		_mesh(head, _sphere(0.03, 8), black, Vector3(sx, 0.03, -0.18))
	var hair := _mesh(head, _sphere(0.21, 12), main.make_material(Color(0.45, 0.28, 0.15), 0.0), Vector3(0, 0.07, 0.03))
	hair.scale = Vector3(1.0, 0.7, 1.0)
	var smile := TorusMesh.new()
	smile.inner_radius = 0.05
	smile.outer_radius = 0.065
	smile.rings = 8
	smile.ring_segments = 4
	var sm := _mesh(head, smile, main.make_material(Color(0.7, 0.2, 0.2), 0.0), Vector3(0, -0.06, -0.17))
	sm.rotation.x = PI / 2.0
	sm.scale = Vector3(1.0, 1.0, 0.5)


func _make_torch() -> Node3D:
	var t := Node3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.022
	tube.bottom_radius = 0.022
	tube.height = 0.2
	tube.radial_segments = 10
	var body := _mesh(t, tube, main.make_material(Color(0.95, 0.35, 0.3), 0.1), Vector3(0, 0, 0.02))
	body.rotation.x = PI / 2.0
	var head := CylinderMesh.new()
	head.top_radius = 0.03
	head.bottom_radius = 0.042
	head.height = 0.06
	head.radial_segments = 10
	var hm := _mesh(t, head, main.make_material(Color(0.9, 0.9, 0.92), 0.0), Vector3(0, 0, -0.1))
	hm.rotation.x = PI / 2.0
	var lens := _mesh(t, _sphere(0.034, 10), null, Vector3(0, 0, -0.13))
	lens.scale = Vector3(1, 1, 0.3)
	torch_glow = main.make_material(Color(1.0, 0.95, 0.7), 4.0)
	lens.material_override = torch_glow
	torch_light = SpotLight3D.new()
	torch_light.light_color = Color(1.0, 0.95, 0.78)
	torch_light.light_energy = 3.0
	torch_light.spot_angle = 22.0
	torch_light.spot_range = 9.0
	torch_light.spot_attenuation = 0.8
	torch_light.shadow_enabled = false
	t.add_child(torch_light)
	torch_light.position.z = -0.14
	var beam_pivot := Node3D.new()
	beam_pivot.rotation.x = PI / 2.0
	beam_pivot.position.z = -0.14
	t.add_child(beam_pivot)
	torch_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	torch_beam.mesh = cm
	var sm := ShaderMaterial.new()
	sm.shader = main.beam_shader()
	torch_beam.material_override = sm
	torch_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_pivot.add_child(torch_beam)
	# The 3 m "tag zone" of the beam (a brighter inner cone).
	var r: float = tan(deg_to_rad(main.TAG_ANGLE)) * main.TAG_RANGE
	torch_beam.scale = Vector3(r * 2.4, 7.0, r * 2.4)
	torch_beam.position = Vector3(0, -3.5, 0)
	return t


## Called by main once the split-screen camera exists.
func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 75.0
	camera.near = 0.05
	_update_camera(0.0)


## VR seeker: the headset is the camera, the torch is in the right hand, a mitten on the left.
func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	camera = cam
	cam.cull_mask = camera_cull_mask()
	cam.near = 0.05
	if torch:
		torch.queue_free()
	torch = _make_torch()
	hand_r.add_child(torch)
	torch.position = Vector3(0.0, -0.01, -0.04)
	mitten_l = _mesh(hand_l, _sphere(0.05, 10), main.make_material(color, 0.3), Vector3(0, 0, 0.02))
	mitten_l.scale = Vector3(0.8, 0.6, 1.3)
	mitten_l.layers = viewmodel_layer()
	# Eyes covered while counting: a dark bubble round the head (the countdown text draws on top).
	blindfold = MeshInstance3D.new()
	var sm := _sphere(0.3, 12)
	sm.flip_faces = true
	blindfold.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.03, 0.02, 0.06, 0.97)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.no_depth_test = true
	bm.render_priority = -10
	blindfold.material_override = bm
	blindfold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blindfold.layers = viewmodel_layer()
	blindfold.visible = false
	cam.add_child(blindfold)


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


# --- Geometry helpers ----------------------------------------------------------

func eye_pos() -> Vector3:
	if camera and not ghost:
		return camera.global_position if role == "seeker" else global_position + Vector3.UP * 0.6
	return global_position + Vector3.UP * (EYE_HEIGHT if role == "seeker" else 0.6)


## Where a tag should aim: the middle of the critter (or of the object it's disguised as).
func center() -> Vector3:
	return global_position + Vector3.UP * (0.5 if prop_kind < 0 else 0.55)


func torch_xform() -> Transform3D:
	if torch == null:
		return head_transform()
	return torch.global_transform


func is_hiding() -> bool:
	return active and role == "hider" and not found and not late


func can_move() -> bool:
	if not active or main.phase == "intro" or main.phase == "over" or main.phase == "wait":
		return false
	if role == "seeker":
		return main.phase == "seek"
	return prop_kind < 0


# --- Update ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.3)


func _physics_process(delta: float) -> void:
	flash_t -= delta
	taunt_cd = maxf(0.0, taunt_cd - delta)
	prop_hold_t -= delta
	torch_flash = maxf(0.0, torch_flash - delta * 3.0)
	if not active:
		return
	if ghost:
		_ghost_update(delta)
		return
	if remote:
		global_position = net_target
		pivot.rotation.y = yaw
		return
	if vr:
		_vr_update(delta)
	else:
		_read_look(delta)
	var spectating := role == "hider" and (found or late)
	var move := _read_move() if can_move() else Vector3.ZERO
	var speed := HIDER_SPEED if role == "hider" else (VR_SPEED if vr else SEEKER_SPEED)
	velocity = move * speed
	if vr:
		vr_velocity = velocity
	elif spectating:
		velocity = Vector3.ZERO
	else:
		# Jump (kids asked): B on a controller, Space for keyboard hiders. Also hops over low furniture.
		var jy: float = get_meta("jump_y", 0.0)
		var jv: float = get_meta("jump_v", 0.0)
		if role == "hider" and jy <= 0.0 and can_move() and _jump_held():
			jv = 5.0
			main.sound("dash", -8.0, 1.5)
		jv -= 14.0 * delta
		jy = maxf(0.0, jy + jv * delta)
		if jy <= 0.0:
			jv = 0.0
		set_meta("jump_y", jy)
		set_meta("jump_v", jv)
		position.y = jy
		var before := global_position
		move_and_slide()
		position.y = jy
		# Unstick: pushing for 2 s without getting anywhere slides you free towards the house centre.
		if move.length() > 0.5 and before.distance_to(global_position) < 0.2 * delta:
			set_meta("stuck_t", float(get_meta("stuck_t", 0.0)) + delta)
			if float(get_meta("stuck_t", 0.0)) > 2.0:
				set_meta("stuck_t", 0.0)
				var to_c := Vector3(-global_position.x, 0.0, -global_position.z)
				global_position += to_c.normalized() * 0.8 if to_c.length() > 0.1 else Vector3(0.8, 0.0, 0.0)
				if main.in_jail(global_position):
					global_position = main.WorldScript.BELL_POS + Vector3(-0.6, 0, 0)  # never pop into the jail cage
				main.burst(global_position + Vector3.UP, Color(0.7, 0.9, 1.0), 10, 0.06)
		else:
			set_meta("stuck_t", 0.0)
	bob_t += velocity.length() * delta * 2.2
	_update_camera(delta)
	main.net.send_state(global_position, yaw, pitch, index)
	var fire := _fire_held()
	var alt := _alt_held()
	if role == "seeker":
		if fire and not fire_was:
			torch_flash = 1.0
			if vr:
				hand_r.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
			main.torch_click(self)
		var sniff := _sniff_held(delta)
		if sniff and not sniff_was:
			main.request_sniff(self)
		sniff_was = sniff
	elif not spectating:
		if fire and not fire_was:
			toggle_disguise()
		if alt and not alt_was:
			request_taunt()
	fire_was = fire
	alt_was = alt


## Hider: become a random household object, or pop back out.
func toggle_disguise() -> void:
	if role != "hider" or found or late or not active:
		return
	if main.phase != "count" and main.phase != "seek":
		return
	var kind: int = -1 if prop_kind >= 0 else main.pick_disguise(global_position)
	if main.net.mode == "client":
		prop_hold_t = 0.8
		set_prop(kind)
		main.net.send_action("prop", [kind], index)
	else:
		main.set_disguise(self, kind)


func request_taunt() -> void:
	if role != "hider" or found or late or not active or taunt_cd > 0.0:
		return
	if main.phase != "seek":
		return
	taunt_cd = main.TAUNT_COOLDOWN
	if main.net.mode == "client":
		main.net.send_action("taunt", [], index)
	else:
		main.do_taunt(self)


func set_prop(kind: int) -> void:
	if kind == prop_kind:
		return
	prop_kind = kind
	velocity = Vector3.ZERO
	_refresh_look()


## Body / disguise / hidden, from found, late and prop_kind.
func _refresh_look() -> void:
	var gone := late  # found hiders stay visible: they're in the jail cage
	pivot.visible = not gone and prop_kind < 0
	tag.visible = not gone and prop_kind < 0
	if prop_kind != prop_shown:
		if prop_node != null:
			prop_node.queue_free()
			prop_node = null
		prop_shown = prop_kind
		if prop_kind >= 0:
			prop_node = main.WorldScript.make_prop(prop_kind, main)
			add_child(prop_node)
			_set_layers(prop_node, 1)
	if prop_node != null:
		prop_node.visible = not gone


func set_found(on: bool, is_late: bool = false) -> void:
	found = on
	late = is_late
	if on:
		prop_kind = -1
	_refresh_look()
	collision_layer = 0 if (on or not active) else 2


func _process(delta: float) -> void:
	_update_torch(delta)
	_animate_critter(delta)
	if vr and blindfold:
		blindfold.visible = main.phase == "count"
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


## Waddle, bob and squash while walking; blink; sad droop in jail; glowing eyes at night.
func _animate_critter(delta: float) -> void:
	if critter == null or not active:
		return
	anim_t += delta
	var moved := (global_position - last_pos).length() / maxf(delta, 0.001)
	last_pos = global_position
	walk = lerpf(walk, clampf(moved / HIDER_SPEED, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	var step := sin(anim_t * 13.0)
	var bounce := absf(step) * 0.08 * walk
	critter.position.y = bounce
	critter.rotation.z = step * 0.12 * walk
	critter.scale = Vector3(1.0 + bounce * 0.6, 1.0 - bounce * 0.7, 1.0 + bounce * 0.6)
	if found and not late:
		critter.rotation.x = 0.25  # a sad little droop in jail
	else:
		critter.rotation.x = 0.0
	blink_t -= delta
	if blink_t <= 0.0:
		blink_t = randf_range(2.0, 5.0)
	eyes.scale = Vector3(1.0, 0.12 if blink_t < 0.12 else 1.0, 1.0)
	var night: bool = main.is_night()
	eye_mat.emission = Color(0.9, 0.95, 0.6) if night else Color(0, 0, 0)
	eye_mat.emission_energy_multiplier = 1.4 if night else 0.0


func _update_torch(_delta: float) -> void:
	if torch == null:
		return
	if not vr and not ghost:
		var head := head_transform()
		var hold := head.origin + head.basis * Vector3(0.2, -0.2, -0.3)
		var aim_at := head.origin + head.basis * Vector3(0, 0, -6.0)
		torch.global_transform = Transform3D(Basis.looking_at(aim_at - hold, Vector3.UP), hold)
	var on: bool = active and main.phase == "seek"
	torch_light.visible = on
	torch_beam.visible = on
	var night: bool = main.is_night()
	torch_light.light_energy = (4.5 if night else 3.0) + torch_flash * 5.0
	torch_light.spot_range = 12.0 if night else 9.0
	torch_glow.emission_energy_multiplier = (4.0 + torch_flash * 6.0) if on else 0.3
	var bm: ShaderMaterial = torch_beam.material_override
	bm.set_shader_parameter("energy", 0.22 + torch_flash * 0.5)


func _update_camera(delta: float) -> void:
	pivot.rotation.y = yaw
	if camera == null or vr:
		return
	if role == "seeker":
		var bob := sin(bob_t) * 0.035
		camera.global_position = global_position + Vector3(0, EYE_HEIGHT + bob, 0)
		camera.rotation = Vector3(pitch, yaw, 0.0)
		return
	var target: Vector3
	var dist := 2.6
	if found or late:
		# Spectate: orbit behind the seeker.
		var s = main.players[0]
		target = s.global_position + Vector3.UP * 1.4
		dist = 3.2
	else:
		target = global_position + Vector3.UP * 1.0
	var b := Basis.from_euler(Vector3(clampf(pitch - 0.3, -1.2, 0.5), yaw, 0.0))
	var want := target + b * Vector3(0, 0, dist)
	var hit: Dictionary = main.ray(target, want)
	if not hit.is_empty():
		var hp: Vector3 = hit.position
		want = target + (hp - target) * 0.85
	var cur := camera.global_position
	if delta > 0.0 and cur.distance_to(want) < 3.0:
		want = cur.lerp(want, 1.0 - exp(-18.0 * delta))
	camera.global_transform = Transform3D(b, want)


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


## Seeker: torch tag. Hider: disguise toggle.
func _fire_held() -> bool:
	if vr:
		return hand_r.get_float("trigger") > 0.6 or hand_r.is_button_pressed("ax_button")
	if bot_fire or _key("fire"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		if Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
			return true
		if role == "seeker":
			return Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	return false


## Hider: squeak.
func _alt_held() -> bool:
	if vr:
		return false
	if bot_alt or _key("alt"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	if joy >= 0 and role == "hider":
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_X) \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_Y) or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER) \
			or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4
	return false


## Seeker: sniff. Q / LB on a flat screen; in VR, hold your LEFT hand on your nose for a moment
## (measured from the headset, so it works sitting or standing).
func _sniff_held(delta: float) -> bool:
	if role != "seeker":
		return false
	if vr:
		var head := xr_camera.global_transform
		var nose := head.origin + head.basis * Vector3(0.0, -0.05, -0.1)
		var near := hand_l.global_position.distance_to(nose) < 0.17
		nose_t = nose_t + delta if near else 0.0
		return nose_t > 0.35
	if bot_alt:
		return true
	if Input.is_physical_key_pressed(KEY_Q) and keys() == 0:
		return true
	return joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER)


## Hider: jump (B on a controller).
func _jump_held() -> bool:
	if vr or role != "hider":
		return false
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_B):
		return true
	return false


## VR: trigger or A (play again on the results screen).
func vr_button_held() -> bool:
	return vr and (hand_r.get_float("trigger") > 0.6 or hand_r.is_button_pressed("ax_button"))


## Headset drives facing and body position; right stick snap-turns; eye height is fitted to the wearer.
func _vr_update(delta: float) -> void:
	if xr_origin.world_scale != 1.0:
		xr_origin.world_scale = 1.0  # another game may have left the (global) XR world scale changed
	calib_t += delta
	var hy := xr_camera.position.y
	if not calibrated:
		if calib_t > 0.5 and xr_camera.position != Vector3.ZERO:
			fit_height()
	elif absf(hy - calib_y) > 0.35:
		off_t += delta
		if off_t > 4.0:  # someone else (taller / shorter / sitting) put the headset on
			fit_height()
	else:
		off_t = 0.0
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


func fit_height() -> void:
	var first := not calibrated
	calibrated = true
	off_t = 0.0
	calib_y = xr_camera.position.y
	var o := xr_origin.global_position
	xr_origin.global_position = Vector3(o.x, SEEKER_EYE - calib_y, o.z)
	print("VR: fitted eye height (head %.2f m above the floor -> eyes at %.2f m)" % [calib_y, SEEKER_EYE])
	if first and main.phase != "seek":
		teleport(main.SEEKER_SPAWN, PI)  # tracking just started: stand on the counting spot


## Put the player at `pos` facing `new_yaw` (VR: moves the play space so the head lands there).
func teleport(pos: Vector3, new_yaw: float) -> void:
	yaw = new_yaw
	pitch = 0.0
	if vr and xr_origin != null:
		var head_yaw := xr_camera.global_rotation.y
		var rot := Basis(Vector3.UP, new_yaw - head_yaw)
		var pivot_pt := xr_camera.global_position
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, pivot_pt + rot * (xr_origin.global_position - pivot_pt))
		var head := xr_camera.global_position
		xr_origin.global_position += Vector3(pos.x - head.x, 0.0, pos.z - head.z)
	global_position = Vector3(pos.x, 0.0, pos.z)
	net_target = global_position
	velocity = Vector3.ZERO
	_update_camera(0.0)


# --- Networked co-op ---------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if camera and role == "seeker":
		return camera.global_transform
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), global_position + Vector3.UP * (EYE_HEIGHT if role == "seeker" else 0.6))


func hand_transform() -> Transform3D:
	if torch and not ghost:
		return torch.global_transform
	return head_transform()


func left_hand_transform() -> Transform3D:
	return hand_l.global_transform if vr else Transform3D()


func set_active(on: bool) -> void:
	active = on
	visible = on
	collision_layer = 2 if (on and not found) else 0


## [active, found, late, prop_kind, taunt_cd] (+ the seeker's [pos, yaw, pitch, head, hand, lhand, torch_flash]).
## TV hiders are driven on the TV itself, so their positions aren't sent back (keeps snapshots under the MTU).
func net_state() -> Array:
	var st: Array = [active, found, late, prop_kind, snappedf(taunt_cd, 0.1)]
	if role == "seeker":
		st.append_array([global_position, yaw, pitch, head_transform(), hand_transform(), left_hand_transform(), torch_flash])
	return st


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
	var on: bool = st[0]
	if on != active:
		set_active(on)
		main.on_player_activity_changed(self)
	var f: bool = st[1]
	var l: bool = st[2]
	if f != found or l != late:
		set_found(f, l)
	if prop_hold_t <= 0.0:
		set_prop(st[3])
	taunt_cd = float(st[4]) if ghost else maxf(taunt_cd, float(st[4]) - 0.2)
	if ghost and st.size() >= 12:
		net_target = st[5]
		yaw = st[6]
		pitch = st[7]
		net_head = st[8]
		net_hand = st[9]
		net_lhand = st[10]
		torch_flash = maxf(torch_flash, float(st[11]))
		if not net_started:
			net_started = true
			global_position = net_target


func _ghost_update(delta: float) -> void:
	global_position = global_position.lerp(net_target, 1.0 - exp(-15.0 * delta))
	pivot.rotation.y = yaw
	var head: Node3D = pivot.get_node_or_null("Head")
	if head != null and net_head != Transform3D():
		var want := net_head.orthonormalized()
		head.global_transform = head.global_transform.interpolate_with(want, 1.0 - exp(-20.0 * delta))
	if torch and net_hand != Transform3D():
		torch.global_transform = torch.global_transform.interpolate_with(net_hand.orthonormalized(), 1.0 - exp(-25.0 * delta))
	if ghost_mitten == null:
		ghost_mitten = _mesh(self, _sphere(0.06, 10), body_mat, Vector3.ZERO)
		ghost_mitten.top_level = true
		ghost_mitten.layers = body_layer()
	ghost_mitten.visible = net_lhand != Transform3D()
	if ghost_mitten.visible:
		ghost_mitten.global_position = net_lhand.origin
