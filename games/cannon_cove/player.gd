extends Node3D
## A crew member.
## Player 1 (index 0) is the GUNNER. In VR they grab a cannon's glowing handle (grip or trigger),
## swing it to aim and fire with the trigger; A/B (or a left-stick flick) hops between the four
## cannons; a spyglass in the left hand zooms when held up to the eye. Flat (split screen / no
## headset) the gunner aims with the sticks, mouse or keys.
## Players 2 to 7 are DECKHANDS in first person: carry cannonballs from the pile to the cannons,
## hold "use" next to a leak to patch it, and shoot boarding pirates with a musket.

const World := preload("res://games/cannon_cove/world.gd")

const SPEED := 5.5
const EYE := 1.6
const STICK_YAW := 3.0
const STICK_PITCH := 2.0
const KEY_TURN := 2.4
const MOUSE_SENS := 0.0028
const MUSKET_CD := 0.55
const GUN_AIM_SPEED := 0.9
const GRAB_RANGE := 0.3
const HAND_KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "fire": KEY_F, "use": KEY_E, "use2": KEY_SPACE},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "fire": KEY_ENTER, "use": KEY_SHIFT, "use2": KEY_SLASH},
]
const GUN_KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "fire": KEY_SPACE, "prev": KEY_Q, "next": KEY_E},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "fire": KEY_ENTER, "prev": KEY_COMMA, "next": KEY_PERIOD},
]
const SPY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
uniform sampler2D view : source_color, filter_linear;
void fragment() {
	float r = length(UV - 0.5);
	if (r > 0.5) { discard; }
	vec3 c = texture(view, vec2(UV.x, UV.y)).rgb;
	float vig = smoothstep(0.5, 0.36, r);
	ALBEDO = mix(vec3(0.25, 0.15, 0.05), c, vig);
}
"""

var index := 0
var joy := -1
var color := Color.WHITE
var main
var camera: Camera3D
var hud
var key_set := 0
var mouse_look := false
var gunner := false
var yaw := 0.0
var pitch := 0.0

# Networking: on the host, deckhands are `remote` (driven by the TV machine); on the TV machine
# the gunner is a `ghost` placed from snapshots.
var remote := false
var ghost := false
var active := true
var net_target := Vector3.ZERO
var net_started := false
var net_head := Transform3D()
var net_hand_r := Transform3D()
var net_hand_l := Transform3D()

# Deckhand.
var carrying := false
var use_held := false  # host: holding the use button (patching)
var use_was_held := false
var patching := false
var musket_cd := 0.0
var recoil := 0.0
var bob_t := 0.0
var shake := 0.0
var hands_full_t := 0.0

# Gunner.
var station := 1
var fire_was_held := false
var prev_was := false
var next_was := false
var mouse_aim := Vector2.ZERO
var vr := false
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var wrist_label: Label3D
var grab_hand: XRController3D
var grab_offset := Vector3.ZERO
var grab_by_trigger := false
var trig_was := {}
var grip_was := {}
var ax_was := false
var by_was := false
var flick_ready := true
var snap_ready := true
var spyglass: Node3D
var spy_vp: SubViewport
var spy_cam: Camera3D
var spy_lens: MeshInstance3D
var spy_zoom := false
var station_placed := -1

# Visuals.
var pivot: Node3D
var held_ball: MeshInstance3D  # carried cannonball, seen by the others
var view_ball: MeshInstance3D  # carried cannonball in our own view
var musket: Node3D
var ghost_head: Node3D
var ghost_hands: Array[Node3D] = []

# Test hooks (tests/cannon_cove_bot.gd drives players through these).
var bot_move := Vector3.ZERO
var bot_use := false
var bot_fire := false
var bot_aim_on := false
var bot_aim := Vector2.ZERO  # gunner: (yaw relative to the cannon, pitch)
var bot_station := -1


## Render layers: bit 0 is the world, bits 1-7 the crew's bodies, bits 8-14 their first-person
## view models (musket, carried ball), so each camera hides its own body and the others' view models.
const ALL_BODIES := 254


func body_layer() -> int:
	return 2 << index


func viewmodel_layer() -> int:
	return 256 << index


func camera_cull_mask() -> int:
	return 1 | (ALL_BODIES & ~body_layer()) | viewmodel_layer()


func _ready() -> void:
	add_to_group("players")
	gunner = index == 0
	pivot = Node3D.new()
	add_child(pivot)
	var coat := World.mat(color)
	var skin := World.mat(Color(1.0, 0.8, 0.62))
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.33
	cap.height = 1.25
	cap.radial_segments = 10
	cap.rings = 3
	torso.mesh = cap
	torso.material_override = coat
	torso.position.y = 0.65
	pivot.add_child(torso)
	if gunner:
		# The captain-gunner: coat, gold buttons and a tricorn hat (the head follows the headset).
		for i in 3:
			World.sphere(pivot, 0.04, Vector3(0, 0.5 + i * 0.2, -0.32), World.mat(Color(1.0, 0.8, 0.2), 0.5), 6)
	else:
		World.sphere(pivot, 0.24, Vector3(0, 1.5, 0), skin, 10)
		World.cyl(pivot, 0.26, 0.26, 0.12, Vector3(0, 1.72, 0), World.mat(Color(0.97, 0.97, 0.97)), 10)
		World.cyl(pivot, 0.27, 0.27, 0.05, Vector3(0, 1.68, 0), World.mat(color.darkened(0.3)), 10)
		World.box(pivot, Vector3(0.08, 0.05, 0.05), Vector3(0.1, 1.55, -0.22), World.mat(Color.BLACK))
		World.box(pivot, Vector3(0.08, 0.05, 0.05), Vector3(-0.1, 1.55, -0.22), World.mat(Color.BLACK))
		held_ball = World.sphere(pivot, 0.24, Vector3(0, 1.0, -0.45), World.mat(Color(0.1, 0.1, 0.12), 0.0, 0.3), 10)
		held_ball.visible = false
		var body_musket := World.box(pivot, Vector3(0.07, 0.07, 1.0), Vector3(0.35, 1.0, -0.3), World.mat(Color(0.45, 0.28, 0.12)))
		body_musket.rotation.x = 0.3
	var tag := Label3D.new()
	tag.text = "P%d" % (index + 1) if not gunner else "P1 GUNNER"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 28
	tag.outline_size = 8
	tag.modulate = color
	tag.position.y = 2.3
	pivot.add_child(tag)
	if gunner:
		ghost_head = _make_captain_head()
		add_child(ghost_head)
		ghost_head.top_level = true
		ghost_head.visible = false
		for i in 2:
			var h := Node3D.new()
			World.sphere(h, 0.06, Vector3.ZERO, World.mat(Color(0.95, 0.95, 0.9)), 8)
			h.top_level = true
			h.visible = false
			add_child(h)
			ghost_hands.append(h)
	_set_layers(self, body_layer())
	net_target = position


func _make_captain_head() -> Node3D:
	var head := Node3D.new()
	World.sphere(head, 0.15, Vector3.ZERO, World.mat(Color(1.0, 0.8, 0.62)), 10)
	var hat_mat := World.mat(Color(0.12, 0.1, 0.14))
	var brim := World.cyl(head, 0.3, 0.3, 0.04, Vector3(0, 0.1, 0), hat_mat, 3)
	brim.rotation.y = PI
	World.cyl(head, 0.13, 0.16, 0.16, Vector3(0, 0.18, 0), hat_mat, 10)
	var trim := World.cyl(head, 0.31, 0.31, 0.02, Vector3(0, 0.1, 0), World.mat(Color(1.0, 0.8, 0.2), 0.5), 3)
	trim.rotation.y = PI
	World.box(head, Vector3(0.06, 0.04, 0.03), Vector3(0.06, 0.02, -0.14), World.mat(Color.BLACK))
	World.box(head, Vector3(0.06, 0.04, 0.03), Vector3(-0.06, 0.02, -0.14), World.mat(Color.BLACK))
	return head


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


## Flat camera (split screen or the TV): deckhands get a musket and a carried ball in view.
func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.cull_mask = camera_cull_mask()
	camera.fov = 78.0
	camera.near = 0.05
	if gunner:
		return
	musket = Node3D.new()
	camera.add_child(musket)
	musket.position = Vector3(0.22, -0.2, -0.45)
	var wood := World.mat(Color(0.5, 0.3, 0.14))
	var iron := World.mat(Color(0.2, 0.2, 0.24), 0.0, 0.3)
	World.box(musket, Vector3(0.07, 0.09, 0.6), Vector3(0, -0.02, 0.05), wood)
	var barrel := World.cyl(musket, 0.022, 0.026, 0.75, Vector3(0, 0.03, -0.35), iron, 8)
	barrel.rotation.x = PI / 2.0
	World.box(musket, Vector3(0.03, 0.05, 0.04), Vector3(0, 0.07, 0.05), World.mat(Color(1.0, 0.78, 0.2)))
	view_ball = World.sphere(camera, 0.2, Vector3(0, -0.3, -0.55), World.mat(Color(0.1, 0.1, 0.12), 0.0, 0.3), 12)
	view_ball.visible = false
	for n in [musket, view_ball]:
		_set_layers(n, viewmodel_layer())
	_set_shadows_off(musket)
	_set_shadows_off(view_ball)


func _set_shadows_off(n: Node) -> void:
	if n is GeometryInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_shadows_off(c)


## VR gunner: gloves on both hands, a spyglass in the left hand and a wrist display.
func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	camera = cam
	cam.cull_mask = camera_cull_mask()
	cam.near = 0.05
	var glove := World.mat(Color(0.95, 0.93, 0.85))
	for h in [hand_l, hand_r]:
		var g := World.sphere(h, 0.05, Vector3(0, 0, 0.02), glove, 10)
		g.scale = Vector3(1.0, 0.8, 1.4)
		_set_layers(g, viewmodel_layer())
	# Spyglass: a brass and leather tube pointing forward from the left hand.
	spyglass = Node3D.new()
	hand_l.add_child(spyglass)
	var brass := World.mat(Color(0.95, 0.72, 0.25), 0.2, 0.3)
	brass.metallic = 0.8
	var leather := World.mat(Color(0.4, 0.22, 0.1))
	var t1 := World.cyl(spyglass, 0.022, 0.026, 0.16, Vector3(0, 0, -0.03), leather, 10)
	t1.rotation.x = PI / 2.0
	var t2 := World.cyl(spyglass, 0.03, 0.03, 0.14, Vector3(0, 0, -0.17), brass, 10)
	t2.rotation.x = PI / 2.0
	var t3 := World.cyl(spyglass, 0.036, 0.036, 0.1, Vector3(0, 0, -0.28), brass, 10)
	t3.rotation.x = PI / 2.0
	_set_layers(spyglass, viewmodel_layer())
	_set_shadows_off(spyglass)
	wrist_label = Label3D.new()
	wrist_label.pixel_size = 0.0005
	wrist_label.font_size = 48
	wrist_label.outline_size = 12
	wrist_label.modulate = Color(1.0, 0.9, 0.6)
	wrist_label.position = Vector3(0.0, 0.06, 0.12)
	wrist_label.rotation_degrees = Vector3(-55, 0, 0)
	wrist_label.no_depth_test = true
	hand_r.add_child(wrist_label)
	_set_layers(wrist_label, viewmodel_layer())
	set_station(station)


func _ensure_spy_view() -> void:
	if spy_vp != null:
		return
	spy_vp = SubViewport.new()
	spy_vp.size = Vector2i(512, 512)
	spy_vp.world_3d = main.get_world_3d()
	spy_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(spy_vp)
	spy_cam = Camera3D.new()
	spy_cam.fov = 14.0
	spy_cam.far = 600.0
	spy_cam.cull_mask = 1 | (ALL_BODIES & ~body_layer())
	spy_vp.add_child(spy_cam)
	spy_cam.current = true
	spy_lens = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	spy_lens.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SPY_SHADER
	sm.set_shader_parameter("view", spy_vp.get_texture())
	sm.render_priority = 20
	spy_lens.material_override = sm
	spy_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spy_lens.position = Vector3(0, 0, -0.16)
	spy_lens.visible = false
	xr_camera.add_child(spy_lens)
	_set_layers(spy_lens, viewmodel_layer())


# --- Per-frame -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or not mouse_look or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or get_tree().paused:
		return
	if gunner:
		mouse_aim += motion.relative
	else:
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, -1.3, 1.3)


func _physics_process(delta: float) -> void:
	musket_cd -= delta
	hands_full_t -= delta
	recoil = maxf(0.0, recoil - delta * 6.0)
	shake = maxf(0.0, shake - delta * 3.0)
	if held_ball:
		held_ball.visible = carrying
	if view_ball:
		view_ball.visible = carrying
		musket.visible = not carrying
	if not active:
		return
	if ghost:
		_ghost_update(delta)
		return
	if remote:
		_remote_update(delta)
		return
	if gunner:
		if not vr:
			_flat_gunner_update(delta)
		return
	_deckhand_update(delta)


func _process(delta: float) -> void:
	if vr and active:
		_vr_gunner_update(delta)


# --- Deckhand --------------------------------------------------------------------

func _deckhand_update(delta: float) -> void:
	_read_look(delta)
	var move := _read_move()
	position = World.constrain(position + move * SPEED * delta, 0.35, main.cannon_obstacles())
	bob_t += move.length() * delta * 9.0
	_update_camera()
	main.net.send_state(position, yaw, pitch, index)
	var held := _use_held()
	if held != use_was_held:
		use_was_held = held
		if main.net.mode == "client":
			main.net.send_action("use", [held], index)
		else:
			main.set_use(self, held)
	if _fire_held() and musket_cd <= 0.0:
		if carrying:
			hands_full_t = 1.2
			musket_cd = 0.3
		else:
			_fire_musket()


func _update_camera() -> void:
	pivot.rotation.y = yaw
	if camera == null or vr or gunner:
		return
	var bob := sin(bob_t) * 0.04
	camera.global_position = global_position + Vector3(0, EYE + bob, 0)
	camera.rotation = Vector3(pitch + recoil * 0.05 + randf_range(-1, 1) * shake * 0.02,
		yaw + randf_range(-1, 1) * shake * 0.02, 0.0)
	if musket:
		musket.position = Vector3(0.22 + cos(bob_t * 0.5) * 0.008, -0.2 + absf(sin(bob_t * 0.5)) * 0.01, -0.45 + recoil * 0.08)
		musket.rotation.x = recoil * 0.25


func _fire_musket() -> void:
	musket_cd = MUSKET_CD
	recoil = 1.0
	var origin := camera.global_position if camera else global_position + Vector3.UP * EYE
	var look := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0, 0, -1)
	var dir: Vector3 = main.musket_aim(origin, look)
	if joy >= 0:
		Input.start_joy_vibration(joy, 0.2, 0.4, 0.08)
	if main.net.mode == "client":
		var tr: Array = main.musket_trace(origin, dir)
		main.musket_fx(index, origin, tr[1])
		main.net.send_action("musket", [origin, dir], index)
	else:
		main.musket_shot(self, origin, dir)


# --- Gunner (flat) -----------------------------------------------------------------

func _flat_gunner_update(delta: float) -> void:
	_station_input()
	var c = main.cannons[station]
	var look := Vector2.ZERO
	look += _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 0.15) + _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 0.2)
	look += Vector2(float(_key("right")) - float(_key("left")), float(_key("down")) - float(_key("up")))
	var new_yaw: float = c.aim_yaw - look.x * GUN_AIM_SPEED * delta - mouse_aim.x * MOUSE_SENS * 0.6
	var new_pitch: float = c.aim_pitch - look.y * GUN_AIM_SPEED * 0.6 * delta - mouse_aim.y * MOUSE_SENS * 0.6
	mouse_aim = Vector2.ZERO
	if bot_aim_on:
		var k := 1.0 - exp(-6.0 * delta)
		new_yaw = lerpf(c.aim_yaw, bot_aim.x, k)
		new_pitch = lerpf(c.aim_pitch, bot_aim.y, k)
	c.set_aim(new_yaw, new_pitch)
	position = c.stand_pos()
	yaw = c.base_yaw() + c.aim_yaw
	pivot.rotation.y = yaw
	ghost_head.visible = true
	ghost_head.global_transform = Transform3D(Basis(Vector3.UP, yaw), position + Vector3.UP * 1.6)
	var fire := _fire_held()
	if fire and not fire_was_held:
		main.gunner_fire(self)
	fire_was_held = fire
	if camera:
		var dir: Vector3 = c.aim_dir()
		var flat := Vector3(dir.x, 0.0, dir.z).normalized()
		camera.global_position = c.global_position - flat * 2.4 + Vector3.UP * (1.05 + shake * randf_range(-0.05, 0.05))
		camera.look_at(c.muzzle_pos() + dir * 14.0 + Vector3.UP * 1.0)


func _station_input() -> void:
	if bot_station >= 0 and bot_station != station:
		set_station(bot_station)
	var prev := _key("prev")
	var next := _key("next")
	if joy >= 0:
		prev = prev or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT)
		next = next or Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT)
	if prev and not prev_was:
		set_station((station + 3) % 4)
	if next and not next_was:
		set_station((station + 1) % 4)
	prev_was = prev
	next_was = next


## Man another cannon. In VR this teleports the gunner behind it, facing out to sea.
func set_station(i: int) -> void:
	station = clampi(i, 0, 3)
	grab_hand = null
	main.update_manned()
	var c = main.cannons[station]
	main.sound("load", -8.0, 1.4)
	if vr and xr_origin:
		var head_yaw := xr_camera.global_rotation.y
		var turn: float = wrapf(c.base_yaw() - head_yaw, -PI, PI)
		var rot := Basis(Vector3.UP, turn)
		var head := xr_camera.global_position
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
		var stand: Vector3 = c.stand_pos()
		var head_now := xr_camera.global_position
		xr_origin.global_position += Vector3(stand.x - head_now.x, 0.0, stand.z - head_now.z)
		station_placed = station


# --- Gunner (VR) -------------------------------------------------------------------

func _vr_gunner_update(delta: float) -> void:
	if station_placed != station:
		set_station(station)
	var head := xr_camera.global_position
	position = Vector3(head.x, 0.0, head.z)
	yaw = xr_camera.global_rotation.y
	pivot.rotation.y = yaw
	var c = main.cannons[station]
	# Hop between cannons: A = next, B = previous, or flick the left stick.
	var ax := hand_r.is_button_pressed("ax_button") or hand_l.is_button_pressed("ax_button")
	var by := hand_r.is_button_pressed("by_button") or hand_l.is_button_pressed("by_button")
	var flick := hand_l.get_vector2("primary").x
	if not main.game_over:
		if ax and not ax_was:
			set_station((station + 1) % 4)
		elif by and not by_was:
			set_station((station + 3) % 4)
		elif absf(flick) > 0.7 and flick_ready:
			flick_ready = false
			set_station((station + (1 if flick > 0.0 else 3)) % 4)
	if absf(flick) < 0.3:
		flick_ready = true
	ax_was = ax
	by_was = by
	# Snap turn on the right stick (comfortable when sitting down).
	var turn := hand_r.get_vector2("primary").x
	if absf(turn) > 0.7 and snap_ready:
		snap_ready = false
		var rot := Basis(Vector3.UP, -signf(turn) * deg_to_rad(30.0))
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
	elif absf(turn) < 0.3:
		snap_ready = true
	c = main.cannons[station]
	_vr_grab(c, delta)
	_vr_spyglass()
	var ammo_text: String = "EMPTY - deckhands, bring balls!" if c.ammo <= 0 else "AMMO %d / %d" % [c.ammo, c.MAX_AMMO]
	wrist_label.text = "%s CANNON  ·  %s\nWAVE %d   GOLD %d\nWATER IN HOLD %d%%" % [c.side_name(), ammo_text, main.wave, main.gold, int(main.water)]
	if main.net.mode == "host" and not main.net.connected:
		wrist_label.text += "\nWaiting for the TV crew to join…"


func _trig(h: XRController3D) -> bool:
	return h.get_float("trigger") > 0.6


func _grip(h: XRController3D) -> bool:
	return h.get_float("grip") > 0.6


## Grab the handle with grip (then trigger fires) or with the trigger (aim, let go to fire).
func _vr_grab(c, delta: float) -> void:
	var handle: Vector3 = c.handle_world()
	var trig_edge := {}
	var grip_edge := {}
	for h in [hand_l, hand_r]:
		var t := _trig(h)
		var g := _grip(h)
		var tw: bool = trig_was.get(h.tracker, false)
		var gw: bool = grip_was.get(h.tracker, false)
		trig_edge[h.tracker] = t and not tw
		grip_edge[h.tracker] = g and not gw
		trig_was[h.tracker] = t
		grip_was[h.tracker] = g
	c.hover = false
	if grab_hand == null:
		for h in [hand_r, hand_l]:
			var near: bool = h.global_position.distance_to(handle) < GRAB_RANGE
			if near:
				c.hover = true
			if near and (grip_edge[h.tracker] or trig_edge[h.tracker]):
				grab_hand = h
				grab_by_trigger = not _grip(h)
				grab_offset = handle - h.global_position
				h.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.06, 0.0)
				if not has_meta("grabbed_once"):
					set_meta("grabbed_once", true)
					print("VR gunner grabbed a cannon")
				break
	c.grabbed = grab_hand != null
	if grab_hand == null:
		return
	c.aim_from_handle(grab_hand.global_position + grab_offset, delta)
	if grab_by_trigger:
		if not _trig(grab_hand):
			_vr_fire()  # let go of the trigger: BOOM
			grab_hand = null
	else:
		if not _grip(grab_hand):
			grab_hand = null
		elif trig_edge[hand_l.tracker] or trig_edge[hand_r.tracker]:
			_vr_fire()


func _vr_fire() -> void:
	var fired: bool = main.gunner_fire(self)
	for h in [hand_l, hand_r]:
		if fired:
			h.trigger_haptic_pulse("haptic", 0.0, 1.0, 0.3, 0.0)
		else:
			h.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.05, 0.0)


## Hold the spyglass up to your eye to zoom in on the horizon.
func _vr_spyglass() -> void:
	var holding := grab_hand == hand_l
	spyglass.visible = not holding
	var near := not holding and hand_l.global_position.distance_to(xr_camera.global_position) < 0.17
	if near != spy_zoom:
		spy_zoom = near
		_ensure_spy_view()
		spy_lens.visible = near
		spy_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
		if near:
			hand_l.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.04, 0.0)
	if spy_zoom:
		spy_cam.global_transform = xr_camera.global_transform


# --- Input -----------------------------------------------------------------------

func _keys() -> Dictionary:
	if key_set < 0:
		return {}  # a drop-in player on a controller only
	var sets: Array = GUN_KEYS if gunner else HAND_KEYS
	return sets[clampi(key_set, 0, sets.size() - 1)]


func _key(action: String) -> bool:
	var k: Dictionary = _keys()
	return k.has(action) and Input.is_physical_key_pressed(k[action])


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
	yaw -= look.x * STICK_YAW * delta
	pitch = clampf(pitch - look.y * STICK_PITCH * delta, -1.3, 1.3)
	if key_set == 1:
		yaw -= (float(_key("right")) - float(_key("left"))) * KEY_TURN * delta


func _read_move() -> Vector3:
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
	var world := Basis(Vector3.UP, yaw) * Vector3(v.x, 0.0, v.y).limit_length(1.0)
	return (world + bot_move).limit_length(1.0)


func _fire_held() -> bool:
	if bot_fire:
		return true
	if vr:
		return false
	if _key("fire"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if joy >= 0:
		if Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.4:
			return true
		if gunner:
			return Input.is_joy_button_pressed(joy, JOY_BUTTON_A)
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_RIGHT_SHOULDER)
	return false


func _use_held() -> bool:
	if bot_use:
		return true
	if _key("use") or _key("use2"):
		return true
	if mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	if joy >= 0:
		return Input.is_joy_button_pressed(joy, JOY_BUTTON_A) or Input.is_joy_button_pressed(joy, JOY_BUTTON_X) \
			or Input.is_joy_button_pressed(joy, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT) > 0.4
	return false


## Name of the use button for on-screen prompts.
func use_name() -> String:
	if joy >= 0 or key_set < 0:
		return "A"
	return "E" if key_set == 0 else "SHIFT"


func fire_name() -> String:
	if joy >= 0 or key_set < 0:
		return "RT"
	return "CLICK" if key_set == 0 else "ENTER"


# --- Networking ----------------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	if camera:
		return camera.global_transform
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), global_position + Vector3.UP * EYE)


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		reset_crew_state()


## Leaving (or a controller unplugged): put the ball back and stop patching.
func reset_crew_state() -> void:
	carrying = false
	use_held = false
	use_was_held = false
	patching = false
	bot_move = Vector3.ZERO
	bot_fire = false
	bot_use = false


## Snapshot: [pos, yaw, pitch, carrying, head, hand_r, hand_l, active, station, patching]
func net_state() -> Array:
	var hr := hand_r.global_transform if vr else Transform3D()
	var hl := hand_l.global_transform if vr else Transform3D()
	return [global_position, yaw, pitch, carrying, head_transform(), hr, hl, active, station, patching]


func apply_net_state(st: Array) -> void:
	carrying = st[3]
	patching = st[9]
	var on: bool = st[7]
	if on != active:
		set_active(on)
		main.on_player_activity_changed(self)
	if ghost:
		net_target = st[0]
		yaw = st[1]
		pitch = st[2]
		net_head = st[4]
		net_hand_r = st[5]
		net_hand_l = st[6]
		station = st[8]
		if not net_started:
			net_started = true
			position = net_target


## Host: a TV deckhand moved.
func apply_remote_state(pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	net_target = Vector3(pos.x, 0.0, pos.z)
	yaw = new_yaw
	pitch = new_pitch
	if not net_started:
		net_started = true
		position = net_target


func _remote_update(_delta: float) -> void:
	position = net_target
	pivot.rotation.y = yaw


## Client: the gunner's body, head and hands follow the host's snapshots.
func _ghost_update(delta: float) -> void:
	position = position.lerp(net_target, 1.0 - exp(-15.0 * delta))
	pivot.rotation.y = yaw
	if ghost_head == null:
		return
	if net_head != Transform3D():
		ghost_head.visible = true
		var target := net_head.orthonormalized()
		ghost_head.global_transform = ghost_head.global_transform.interpolate_with(target, 1.0 - exp(-20.0 * delta))
		pivot.visible = true
	else:
		ghost_head.visible = true
		ghost_head.global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.6)
	var hands := [net_hand_r, net_hand_l]
	for i in 2:
		var t: Transform3D = hands[i]
		ghost_hands[i].visible = t != Transform3D()
		if t != Transform3D():
			ghost_hands[i].global_position = ghost_hands[i].global_position.lerp(t.origin, 1.0 - exp(-20.0 * delta))
