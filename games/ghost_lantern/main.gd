extends Node3D
const VrText := preload("res://core/vr_text.gd")
## Ghost Lantern: a spooky-but-cute co-op ghost hunt in a haunted mansion.
## Player 1 (VR, or keyboard+mouse in split screen) carries the spirit lantern: ghosts are only visible
## in its light cone, and ghosts held in the beam get stunned. TV players vacuum up revealed ghosts.
## Ghosts steal the family photos and spook players. Survive the nights!

const PlayerScript := preload("res://games/ghost_lantern/player.gd")
const GhostScript := preload("res://games/ghost_lantern/ghost.gd")
const WorldScript := preload("res://games/ghost_lantern/world.gd")
const HudScript := preload("res://games/ghost_lantern/hud.gd")
const SfxScript := preload("res://core/sfx.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const NetScript := preload("res://core/net.gd")
const MusicScript := preload("res://core/music.gd")

const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.82, 0.4), Color(0.45, 1.0, 0.7), Color(1.0, 0.55, 0.9)]
const MUSIC_TRACK := 2  # "Night City", the slowest track
const LANTERN_ANGLE := 22.0
const FOCUS_ANGLE := 14.0
const LANTERN_RANGE := 11.0
const FOCUS_RANGE := 15.0
const VAC_RANGE := 7.5
const VAC_ANGLE := 16.0
const CAPTURE_RATE := 0.6
const BELL_RADIUS := 9.0
const SPOOK_AMOUNT := 34.0
const BEST_FILE := "user://ghost_lantern_best.cfg"
## Family photos on the walls: [position, yaw (picture faces local +Z)].
const PHOTO_SPOTS := [
	[Vector3(-18.0, 2.0, 7.82), PI], [Vector3(-14.0, 2.0, 7.82), PI], [Vector3(-10.0, 2.1, 7.82), PI],
	[Vector3(-7.18, 2.0, 5.0), -PI / 2.0],
	[Vector3(0.0, 2.3, -7.82), 0.0], [Vector3(-4.2, 2.0, 7.82), PI], [Vector3(4.2, 2.0, 7.82), PI],
	[Vector3(10.0, 2.0, 7.82), PI], [Vector3(14.0, 2.2, 7.82), PI], [Vector3(18.0, 2.0, 7.82), PI],
	[Vector3(20.82, 2.0, -3.0), -PI / 2.0], [Vector3(20.82, 2.0, 3.0), -PI / 2.0],
]
const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
instance uniform vec3 color : source_color = vec3(0.6, 1.0, 0.7);
instance uniform float flash = 0.0;
uniform vec3 lantern_pos = vec3(0.0, -100.0, 0.0);
uniform vec3 lantern_dir = vec3(0.0, 0.0, -1.0);
uniform float cos_outer = 0.93;
uniform float cos_inner = 0.95;
uniform float range = 11.0;
uniform float lantern_on = 1.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 to = wpos - lantern_pos;
	float d = max(length(to), 0.001);
	float c = dot(to / d, lantern_dir);
	float r = smoothstep(cos_outer, cos_inner, c) * (1.0 - smoothstep(range * 0.75, range, d)) * lantern_on;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = color * (1.0 + flash) + vec3(0.5, 0.8, 0.6) * rim * 0.5;
	ALPHA = clamp(r * (0.8 + 0.3 * rim), 0.0, 1.0);
}
"""
const PHOTO_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 bg : source_color = vec3(0.5, 0.7, 0.9);
uniform float seed = 1.0;
float blob(vec2 p, vec2 c, vec2 r) { return 1.0 - smoothstep(0.9, 1.0, length((p - c) / r)); }
void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec3 col = bg * (0.55 + 0.45 * uv.y);
	float n = 2.0 + mod(seed, 3.0);
	for (int i = 0; i < 4; i++) {
		if (float(i) >= n) { break; }
		float fi = float(i);
		float x = (fi + 0.5) / n;
		float h = 0.28 + 0.14 * fract(sin(seed * 7.13 + fi * 3.31) * 43758.5);
		vec3 shirt = 0.5 + 0.45 * cos(6.2832 * (fract(seed * 0.37 + fi * 0.29) + vec3(0.0, 0.33, 0.67)));
		col = mix(col, shirt, blob(uv, vec2(x, 0.0), vec2(0.13, h)));
		col = mix(col, vec3(1.0, 0.82, 0.68), blob(uv, vec2(x, h + 0.08), vec2(0.075, 0.1)));
	}
	ALBEDO = col * 0.75;
}
"""

var players: Array = []
var cameras: Array[Camera3D] = []
var net: Node
var ready_to_play := false
var synced := false
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var ghost_cam: Camera3D
var vr_center: Label3D
var sfx: Node
var music: AudioStreamPlayer
var net_ids := 0
var ghost_by_id := {}  # net_id -> ghost node (host: real ghosts, client: puppets)
var photos: Array = []  # [{home, yaw, node, state}] state: -1 home, -2 lost, else carried by ghost id
var candles: Array = []
var anims: Array = []
var anim_t := 0.0
var _ghost_mat: ShaderMaterial

var night := 0
var score := 0
var caught := 0
var saved := 0
var to_spawn: Array = []
var spawn_timer := 0.0
var break_timer := 4.0
var in_break := true
var game_over := false
var game_over_time := 0.0

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween


func _ready() -> void:
	randomize()
	var built: Dictionary = WorldScript.build(self)
	candles = built.candles
	anims = built.anim
	_build_photos()
	_build_hud()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.has_environment("DUO_JOIN"):
		_show_center("Connecting to the lantern-bearer…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	if mode == "host":
		_show_center("GHOST LANTERN\nWaiting for the TV players to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED", 1.5)
	else:
		_show_center("GHOST LANTERN\nGet ready, ghost hunters!", 3.0)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


# --- Effects (shown on both machines) ----------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func ghost_material() -> ShaderMaterial:
	if _ghost_mat == null:
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = Shader.new()
		_ghost_mat.shader.code = GHOST_SHADER
	return _ghost_mat


func local_sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	sfx.play(sound_name, volume_db, pitch)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	local_sound(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.12) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, 2.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = make_material(color, 3.0)
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	if net:
		net.event("burst", [pos, color, amount, size])


func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.0, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.5)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.5)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


func ring_fx(pos: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	var mat := make_material(color, 3.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3.ONE * 0.3
	var t := ring.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	t.chain().tween_callback(ring.queue_free)


## A captured ghost swirls into the vacuum nozzle.
func capture_fx(pos: Vector3, nozzle: Vector3, color: Color) -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	sm.radial_segments = 12
	sm.rings = 6
	orb.mesh = sm
	var mat := make_material(color, 4.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	orb.global_position = pos
	var t := orb.create_tween().set_parallel()
	t.tween_property(orb, "global_position", nozzle, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	t.tween_property(orb, "scale", Vector3.ONE * 0.05, 0.35).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(orb.queue_free)


# --- Players & views ---------------------------------------------------------

func _build_players(mode: String) -> void:
	var count := 3 if mode != "local" else 2
	for i in count:
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i]
		p.main = self
		p.role = "lantern" if i == 0 else "vacuum"
		p.remote = mode == "host" and i >= 1
		p.ghost = mode == "client" and i == 0
		if i == 2:
			p.key_set = 0
			p.mouse_look = true
		elif mode != "client" and i == 0:
			p.mouse_look = true
		p.position = [Vector3(0, 0, 3.0), Vector3(-1.8, 0, 4.2), Vector3(1.8, 0, 4.2)][i]
		add_child(p)
		players.append(p)


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.6


## Low-res copy of the VR player's view, recorded by gdev so it can be watched on a desktop.
func _build_vr_mirror(xr_cam: XRCamera3D) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	vp.add_to_group("gdev_capture")
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)
	return vp


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 carries the lantern in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		left.pose = "aim"
		origin.add_child(left)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		right.pose = "aim"
		origin.add_child(right)
		players[0].attach_xr(origin, cam, left, right)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: split screen (player 1 holds the lantern)")
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	layer.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for p in players:
		if p.vr or p.remote or p.ghost:
			continue
		var container := SubViewportContainer.new()
		p.set_meta("view", container)
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(container)
		var vp := SubViewport.new()
		vp.world_3d = get_world_3d()
		vp.msaa_3d = Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		container.add_child(vp)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		cameras.append(cam)
		p.attach_camera(cam)
		var hud_layer := CanvasLayer.new()
		vp.add_child(hud_layer)
		var hud := HudScript.new()
		hud.player = p
		hud.main = self
		hud_layer.add_child(hud)
		p.hud = hud
	for p in players:
		if p.index == 2:
			p.set_active(false)
			if p.has_meta("view"):
				p.get_meta("view").visible = false
	if mode == "client":
		_build_ghost_mirror()


## Client: a camera following the VR player's head, shown as a little bubble on the TV.
func _build_ghost_mirror() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 360)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	add_child(vp)
	ghost_cam = Camera3D.new()
	ghost_cam.fov = 90.0
	ghost_cam.cull_mask = players[0].camera_cull_mask()
	vp.add_child(ghost_cam)
	ghost_cam.current = true
	var hud = players[1].hud
	if hud == null:
		return
	var bubble := TextureRect.new()
	bubble.texture = vp.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bubble)
	bubble.size = Vector2(240, 240)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	var tag := Label.new()
	tag.text = "P1 LANTERN (VR)"
	tag.add_theme_font_size_override("font_size", 20)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_color_override("font_color", PLAYER_COLORS[0])
	bubble.add_child(tag)
	tag.position = Vector2(40, 240)


func _assign_joypads() -> void:
	if players.size() < 2:
		return
	var pads := Input.get_connected_joypads()
	players[1].joy = pads[0] if pads.size() > 0 else -1
	if players.size() > 2:
		players[2].joy = pads[1] if pads.size() > 1 else -1
	elif not players[0].vr:
		players[0].joy = pads[1] if pads.size() > 1 else -1


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_assign_joypads()


func nearest_player(pos: Vector3):
	var best = null
	var best_d := INF
	for p in players:
		if p.is_down or not p.active:
			continue
		var d: float = pos.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func on_player_activity_changed(p) -> void:
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


# --- Lantern -----------------------------------------------------------------

func lantern_angle() -> float:
	return FOCUS_ANGLE if players.size() > 0 and players[0].focus else LANTERN_ANGLE


func lantern_range() -> float:
	return FOCUS_RANGE if players.size() > 0 and players[0].focus else LANTERN_RANGE


func lantern_xform() -> Transform3D:
	if players.is_empty() or players[0].lantern == null:
		return Transform3D(Basis(), Vector3(0, -100, 0))
	return players[0].lantern.global_transform


## Host: how much the lantern lights a ghost of `radius` at `pos` (0..1). Matches the ghost shader.
func lantern_reveal(pos: Vector3, radius: float) -> float:
	if players.is_empty() or not players[0].lantern_lit():
		return 0.0
	var xf := lantern_xform()
	var to := pos - xf.origin
	var d := to.length()
	var rng := lantern_range()
	if d > rng or d < 0.01:
		return 0.0 if d > rng else 1.0
	var dir := -xf.basis.z.normalized()
	var ang := rad_to_deg(acos(clampf(dir.dot(to / d), -1.0, 1.0)) - atan(radius / d) * 0.7)
	var cone := clampf((lantern_angle() - ang) / 5.0, 0.0, 1.0)
	return cone * (1.0 - smoothstep(rng * 0.75, rng, d))


func _update_ghost_material() -> void:
	var m := ghost_material()
	var xf := lantern_xform()
	var ang := lantern_angle()
	m.set_shader_parameter("lantern_pos", xf.origin)
	m.set_shader_parameter("lantern_dir", -xf.basis.z.normalized())
	m.set_shader_parameter("cos_outer", cos(deg_to_rad(ang)))
	m.set_shader_parameter("cos_inner", cos(deg_to_rad(ang - 5.0)))
	m.set_shader_parameter("range", lantern_range())
	m.set_shader_parameter("lantern_on", 1.0 if players.size() > 0 and players[0].lantern_lit() else 0.0)


## Host: the lantern-bearer rang the hand bell: nearby ghosts flee and drop their photos.
func ring_bell(p, pos: Vector3) -> void:
	if net.mode == "client":
		return
	_bell_fx(pos)
	net.event("bell", [pos])
	var scared := 0
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g.global_position.distance_to(pos) < BELL_RADIUS:
			g.scare(pos)
			scared += 1
	print("Bell rung by P%d: %d ghosts scared" % [p.index + 1, scared])


func _bell_fx(pos: Vector3) -> void:
	local_sound("pickup", -2.0, 2.2)
	local_sound("clear", -6.0, 2.0)
	ring_fx(Vector3(pos.x, 0.1, pos.z), BELL_RADIUS, Color(1.0, 0.85, 0.35))
	ring_fx(pos, 3.0, Color(1.0, 0.95, 0.6))


# --- Vacuums -----------------------------------------------------------------

## The revealed ghost a vacuum player is aiming at, or null. Works on both machines.
func vac_target(p):
	var origin: Vector3 = p.nozzle_pos()
	var dir: Vector3 = p.aim_dir()
	var best = null
	var best_ang := INF
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g.reveal < 0.35:
			continue
		var to: Vector3 = g.global_position - origin
		var d := to.length()
		if d > VAC_RANGE or d < 0.05:
			continue
		var ang := rad_to_deg(acos(clampf(dir.dot(to / d), -1.0, 1.0)) - atan(g.radius / d))
		if ang < VAC_ANGLE and ang < best_ang:
			best_ang = ang
			best = g
	return best


## HUD: capture progress of the ghost this player is vacuuming (-1 if none).
func vac_progress(p) -> float:
	if p.role != "vacuum" or not p.vac_on:
		return -1.0
	var g = vac_target(p)
	return g.capture if g != null else -1.0


func _update_vacuums(delta: float) -> void:
	for p in players:
		if p.role != "vacuum" or not p.vac_on or not p.active or p.is_down:
			continue
		var g = vac_target(p)
		if g != null:
			g.suck(p.nozzle_pos(), delta * CAPTURE_RATE, p)


func capture_ghost(g, by) -> void:
	if g.is_queued_for_deletion():
		return
	caught += 1
	score += g.points
	g.drop_photo()
	var nozzle: Vector3 = by.nozzle_pos() if by != null else g.global_position
	capture_fx(g.global_position, nozzle, g.color)
	net.event("capture", [g.global_position, nozzle, g.color])
	burst(g.global_position, g.color, 18)
	popup(g.global_position + Vector3.UP * 0.8, "GOTCHA! +%d" % g.points, g.color.lightened(0.3))
	sound("kill", -3.0, 1.6)
	print("Ghost captured by P%d (%d caught, score %d)" % [by.index + 1 if by != null else 0, caught, score])
	_remove_ghost(g)


func _remove_ghost(g) -> void:
	ghost_by_id.erase(g.net_id)
	g.remove_from_group("ghosts")
	g.queue_free()


# --- Ghosts & photos (host) --------------------------------------------------

func _spawn_ghost(kind: String) -> void:
	var g := GhostScript.new()
	g.setup(kind, night, self)
	g.net_id = next_net_id()
	var pos := Vector3.ZERO
	var best := -1.0
	for attempt in 4:
		var c: Vector3
		if randf() < 0.3:
			c = Vector3(randf_range(-19.0, 19.0), 5.0, randf_range(-6.0, 6.0))  # through the ceiling
		else:
			c = Vector3(randf_range(-19.0, 19.0), 1.5, 9.5 * (1.0 if randf() < 0.5 else -1.0))
		var d := INF
		for p in players:
			if p.active:
				d = minf(d, c.distance_to(p.global_position))
		if d > best:
			best = d
			pos = c
	g.position = pos
	add_child(g)
	ghost_by_id[g.net_id] = g


func photos_left() -> int:
	var n := 0
	for ph in photos:
		if ph.state != -2:
			n += 1
	return n


func photo_available(i: int, g) -> bool:
	return photos[i].state == -1 and not photos[i].node.has_meta("returning") and _photo_claimer(i, g) == null


func _photo_claimer(i: int, except):
	for o in get_tree().get_nodes_in_group("ghosts"):
		if o != except and o.kind == "thief" and o.target_photo == i and o.carrying < 0:
			return o
	return null


func pick_photo(g) -> int:
	var best := -1
	var best_d := INF
	for i in photos.size():
		if not photo_available(i, g):
			continue
		var d: float = g.global_position.distance_to(photos[i].home) + randf() * 4.0
		if d < best_d:
			best_d = d
			best = i
	return best


func photo_grab_point(i: int) -> Vector3:
	var ph: Dictionary = photos[i]
	return ph.home + Basis(Vector3.UP, ph.yaw) * Vector3(0, -0.2, 0.55)


func grab_photo(g, i: int) -> void:
	_set_photo_state(i, g.net_id)
	sound("spit", -4.0, 1.4)
	popup(photos[i].home + Vector3.UP * 0.6, "PHOTO STOLEN!", Color(1.0, 0.6, 0.8))
	print("A ghost grabbed photo %d" % i)


## A photo was knocked out of a ghost's hands: it floats back to its wall.
func return_photo(i: int, rescued: bool) -> void:
	if photos[i].state < 0:
		return
	_set_photo_state(i, -1)
	if rescued:
		saved += 1
		score += 50
		popup(photos[i].node.global_position + Vector3.UP * 0.5, "PHOTO SAVED!", Color(1.0, 0.9, 0.5))
		sound("pickup", -4.0, 1.0)


func ghost_escaped(g) -> void:
	var i: int = g.carrying
	if i >= 0:
		_set_photo_state(i, -2)
		sound("gameover", -10.0, 2.2)
		var left := photos_left()
		_show_center("A ghost escaped with a photo!\n%d photos left" % left, 2.0)
		print("Photo %d lost (%d left)" % [i, left])
	_remove_ghost(g)


func spook_player(p, g) -> void:
	p.spook(SPOOK_AMOUNT, g.global_position)
	popup(p.global_position + Vector3.UP * 2.0, "BOO!", g.color)
	sound("spit", -2.0, 0.7)


func on_ghost_stunned(g) -> void:
	popup(g.global_position + Vector3.UP * 0.8, "STUNNED!", Color(1.0, 0.95, 0.4))
	sound("hit", -2.0, 0.5)
	if players[0].vr:
		players[0].hand_r.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.1, 0.0)


func _set_photo_state(i: int, s: int) -> void:
	var ph: Dictionary = photos[i]
	var old: int = ph.state
	ph.state = s
	var node: Node3D = ph.node
	if s == -2:
		node.visible = false
	elif s == -1 and old >= 0:
		node.visible = true
		node.set_meta("returning", true)
		var t := node.create_tween().set_parallel()
		t.tween_property(node, "global_position", ph.home, 0.9).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(node, "rotation", Vector3(0, ph.yaw, 0), 0.9)
		t.chain().tween_callback(func() -> void: node.remove_meta("returning"))
	elif s == -1:
		node.visible = true


func _build_photos() -> void:
	var frame_mat := make_material(Color(0.75, 0.55, 0.22), 0.3)
	frame_mat.metallic = 0.6
	for i in PHOTO_SPOTS.size():
		var spot: Array = PHOTO_SPOTS[i]
		var node := Node3D.new()
		add_child(node)
		node.position = spot[0]
		node.rotation.y = spot[1]
		var frame := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.75, 0.6, 0.05)
		frame.mesh = bm
		frame.material_override = frame_mat
		node.add_child(frame)
		var pic := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.6, 0.45)
		pic.mesh = qm
		var sm := ShaderMaterial.new()
		sm.shader = _photo_shader()
		sm.set_shader_parameter("seed", float(i) * 1.7 + 1.0)
		sm.set_shader_parameter("bg", Color.from_hsv(fmod(i * 0.17, 1.0), 0.35, 0.95))
		pic.material_override = sm
		pic.position.z = 0.03
		node.add_child(pic)
		photos.append({"home": spot[0], "yaw": spot[1], "node": node, "state": -1})


func _photo_shader() -> Shader:
	if not has_meta("photo_shader"):
		var s := Shader.new()
		s.code = PHOTO_SHADER
		set_meta("photo_shader", s)
	return get_meta("photo_shader")


## Carried photos follow their ghost (always visible: a floating photo gives the ghost away!).
func _update_photos(delta: float) -> void:
	for ph in photos:
		var s: int = ph.state
		if s < 0:
			continue
		var g = ghost_by_id.get(s)
		if g == null or not is_instance_valid(g):
			continue
		var node: Node3D = ph.node
		var target: Vector3 = g.global_position + Vector3(0, -0.45, 0) + g.body.global_basis.z * -0.3
		node.global_position = node.global_position.lerp(target, 1.0 - exp(-10.0 * delta))
		node.rotation.y += delta * 1.5
		node.rotation.z = sin(anim_t * 4.0) * 0.2


# --- Nights ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	anim_t += delta
	_animate_world(delta)
	_update_ghost_material()
	_update_vr_center()
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -16.0
	if music.has_method("play_track"):
		music.play_track(MUSIC_TRACK)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_photos(delta)
	_update_hud()
	if net.mode == "client":
		_check_join(delta)
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		if game_over_time > 1.5 and (_restart_pressed() or players[0].vr_button_held()):
			get_tree().reload_current_scene()
		return
	if net.mode == "host" and not net.connected:
		return  # hold the nights until a TV player joins
	_update_vacuums(delta)
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_night()
	elif not to_spawn.is_empty():
		spawn_timer -= delta
		if spawn_timer <= 0.0 and ghost_by_id.size() < 3 + night:
			_spawn_ghost(to_spawn.pop_back())
			spawn_timer = maxf(1.0, 3.0 - night * 0.25)
	elif ghost_by_id.is_empty():
		_end_night()
	var all_down := true
	for p in players:
		if p.active and not p.is_down:
			all_down = false
	if all_down:
		_on_game_over("Everyone got too spooked!")
	elif photos_left() == 0:
		_on_game_over("The ghosts took every photo!")


func _animate_world(_delta: float) -> void:
	for l in candles:
		if is_instance_valid(l):
			var base: float = l.get_meta("base", 1.4)
			l.light_energy = base * (0.85 + 0.1 * sin(anim_t * 11.0 + l.position.x) + randf() * 0.08)
	for a in anims:
		var n: Node3D = a[0]
		if not is_instance_valid(n):
			continue
		match a[1]:
			"pendulum":
				n.rotation.z = sin(anim_t * 2.4) * 0.35
			"rock":
				n.rotation.x = sin(anim_t * 1.6) * 0.18
			"sway":
				n.rotation.z = sin(anim_t * 0.7) * 0.04
			"flame":
				n.scale = Vector3(1.0, 1.0 + 0.25 * sin(anim_t * 9.0), 1.0)


func _start_night() -> void:
	night += 1
	in_break = false
	to_spawn = []
	for i in 2 + night:
		to_spawn.append("thief")
	for i in (night + 1) / 2:
		to_spawn.append("spooker")
	for i in maxi(0, night - 2):
		to_spawn.append("sprite")
	to_spawn.shuffle()
	spawn_timer = 1.0
	sound("wave", -2.0, 0.7)
	print("Night %d started (%d ghosts)" % [night, to_spawn.size()])
	if night == 1:
		_show_center("NIGHT 1\nThe ghosts are coming for the family photos!", 2.5)
	else:
		_show_center("NIGHT %d\n%d ghosts tonight" % [night, to_spawn.size()], 2.0)


func _end_night() -> void:
	in_break = true
	break_timer = 5.0
	score += 100 * night
	for p in players:
		if p.is_down:
			p.revive(0.6)
		else:
			p.courage = minf(p.MAX_COURAGE, p.courage + 30.0)
	sound("clear", -2.0, 0.8)
	print("Night %d survived (score %d, caught %d, saved %d)" % [night, score, caught, saved])
	_show_center("NIGHT %d SURVIVED!\n+%d bonus  ·  %d photos still safe" % [night, 100 * night, photos_left()], 3.0)


func _on_game_over(reason: String) -> void:
	game_over = true
	game_over_time = 0.0
	sound("gameover", -2.0, 0.8)
	print("Game over: night %d, score %d, caught %d, saved %d (%s)" % [night, score, caught, saved, reason])
	var cfg := ConfigFile.new()
	cfg.load(BEST_FILE)
	var best_score: int = cfg.get_value("best", "score", 0)
	var best_line := "Best: night %d  ·  score %d" % [cfg.get_value("best", "night", 0), best_score]
	if score > best_score:
		best_line = "NEW BEST SCORE!"
		cfg.set_value("best", "score", score)
		cfg.set_value("best", "night", night)
		cfg.save(BEST_FILE)
	_show_center("%s\nNight %d  ·  Score %d\nGhosts caught %d  ·  Photos saved %d\n%s\n\nPress A or Enter to play again" % [reason, night, score, caught, saved, best_line], 0.0)


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# --- Networked co-op ---------------------------------------------------------

func on_client_joined() -> void:
	_show_center("GHOST HUNTERS JOINED!", 1.5)


func on_client_left() -> void:
	_show_center("The TV players left - waiting for them to come back…", 0.0)


var join_t := 0.0
func _check_join(delta: float) -> void:
	join_t -= delta
	if players.size() < 3 or players[2].active or join_t > 0.0 or game_over:
		return
	if players[2]._fire_held():
		join_t = 1.0
		net.send_action("join", [], 2)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	var p = players[index]
	match action:
		"vac":
			p.vac_on = bool(args[0]) and not p.is_down
		"join":
			if not p.active:
				p.set_active(true)
				p.courage = p.MAX_COURAGE
				_show_center("PLAYER %d JOINED THE HUNT!" % (index + 1), 1.5)
				print("Net: player %d joined the game" % (index + 1))
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_show_center("PAUSED\nA TV player opened the menu" if paused else "", 0.0, false)
			get_tree().paused = paused


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_show_center("PAUSED\nPress the menu button to resume" if paused else "", 0.0, false)
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		ps.append(p.net_state())
	var gs := []
	for g in get_tree().get_nodes_in_group("ghosts"):
		gs.append(g.net_state())
	var ph := []
	for p in photos:
		ph.append(p.state)
	return [night, score, caught, saved, game_over, ps, gs, ph, in_break]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	night = s[0]
	score = s[1]
	caught = s[2]
	saved = s[3]
	game_over = s[4]
	in_break = s[8]
	var ps: Array = s[5]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_ghosts(s[6])
	var ph: Array = s[7]
	for i in mini(ph.size(), photos.size()):
		if photos[i].state != ph[i]:
			_set_photo_state(i, ph[i])


func _sync_ghosts(list: Array) -> void:
	var seen := {}
	for item in list:
		var id: int = item[0]
		seen[id] = true
		var g = ghost_by_id.get(id)
		if g == null or not is_instance_valid(g):
			g = GhostScript.new()
			g.setup(item[1], maxi(night, 1), self)
			g.puppet = true
			g.net_id = id
			g.position = item[2]
			add_child(g)
			ghost_by_id[id] = g
		g.apply_net(item)
	for id in ghost_by_id.keys():
		if not seen.has(id):
			var g = ghost_by_id[id]
			if is_instance_valid(g):
				g.remove_from_group("ghosts")
				g.queue_free()
			ghost_by_id.erase(id)


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			local_sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2])
		"capture":
			capture_fx(args[0], args[1], args[2])
		"bell":
			_bell_fx(args[0])
		"center":
			_show_center(args[0], args[1])
		"remote_pause":
			get_tree().paused = args[0]
			_show_center("PAUSED\nThe lantern-bearer paused the game" if args[0] else "", 0.0, false)
		"hurt":
			var i: int = args[0]
			if i < players.size():
				players[i].on_remote_hurt(args[1])


# --- HUD ---------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(30)
	info_label.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 16
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(56)
	center_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label = _make_label(22)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 64
	help_label.offset_bottom = 150
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Lantern (P1): WASD + mouse · Space/click focus · E/right click bell  |  " \
		+ "Vacuums: stick/WASD move · RT / Space / Enter suck  ·  Start/Esc menu\n" \
		+ "Ghosts only show up in the lantern light! Stand next to a spooked friend to cheer them up."


func _show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_label.text = text
	center_label.modulate.a = 1.0
	if center_tween:
		center_tween.kill()
	if duration > 0.0:
		center_tween = create_tween()
		center_tween.tween_interval(duration)
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.5)


## VR: the centre banner as a head-locked Label3D with a thick outline.
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 48
		vr_center.outline_size = 26
		vr_center.outline_modulate = Color.BLACK
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.pixel_size = 0.0026
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.modulate = Color(0.75, 1.0, 0.8)
		players[0].xr_camera.add_child(vr_center)
		vr_center.position = Vector3(0.0, -0.1, -1.7)
		players[0]._set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = center_label.modulate.a
	VrText.follow(vr_center, players[0].xr_camera, self, -0.1, 1.7)


func _update_hud() -> void:
	if night >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time())
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the lantern-bearer…"
		return
	info_label.text = "NIGHT %d   ·   GHOSTS CAUGHT %d   ·   PHOTOS %d/%d   ·   SCORE %d" % [night, caught, photos_left(), photos.size(), score]
