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
const JoinInputScript := preload("res://games/ghost_lantern/join_input.gd")
const DirectorScript := preload("res://games/ghost_lantern/director.gd")

## Survive night 6 to see the sunrise (then bonus nights). Nights 3 and 6 bring the GHOST KING.
const FINAL_NIGHT := 6
const EXTRA_SOUNDS := {
	"thunder": [1.3, 90.0, 28.0, 0.6, "saw", 0.92],
	"puff": [0.35, 900.0, 200.0, 0.3, "sine", 0.85],
	"giggle": [0.25, 900.0, 1400.0, 0.2, "tri", 0.1],
	"fanfare": [1.6, 392.0, 1568.0, 0.4, "tri", 0.0],
	"crown": [0.5, 1200.0, 300.0, 0.3, "square", 0.2],
}

## P1 (lantern) + up to six TV ghost hunters P2..P7.
const MAX_PLAYERS := 7
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.82, 0.4), Color(0.45, 1.0, 0.7), Color(1.0, 0.55, 0.9),
	Color(0.45, 0.8, 1.0), Color(1.0, 0.6, 0.3), Color(0.8, 1.0, 0.35), Color(0.75, 0.6, 1.0)]
const SPAWNS: Array[Vector3] = [Vector3(0, 0, 3.0), Vector3(-1.8, 0, 4.2), Vector3(1.8, 0, 4.2),
	Vector3(-3.4, 0, 5.2), Vector3(3.4, 0, 5.2), Vector3(-1.2, 0, 6.0), Vector3(1.2, 0, 6.0)]
const PAD_WAIT_TIME := 20.0  # a player whose controller unplugs waits this long before leaving
const PARTY_META := "ghost_lantern_party"  # Engine meta: who was playing, kept across a restart
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
uniform float focus_on = 0.0;
uniform float flash_all = 0.0;
instance uniform float shy = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 to = wpos - lantern_pos;
	float d = max(length(to), 0.001);
	float c = dot(to / d, lantern_dir);
	float r = smoothstep(cos_outer, cos_inner, c) * (1.0 - smoothstep(range * 0.75, range, d)) * lantern_on;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = color * (1.0 + flash) + vec3(0.5, 0.8, 0.6) * rim * 0.5;
	float lit = r * (0.8 + 0.3 * rim) * mix(1.0, focus_on, shy);
	ALPHA = clamp(max(lit, flash_all * 0.85), 0.0, 1.0);
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
var storm_flash := 0.0  # lightning: every ghost shows for a moment (0..1)
var dir_node: Node
var world_refs := {}
var king_t := -1.0  # host: seconds until the Ghost King arrives tonight

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
var join_label: Label

# Split screen & drop-in players.
var view_grid: GridContainer
var view_count := 0
var bubble: TextureRect
var pad_wait := {}  # player index -> seconds left to plug their controller back in
var pending_join := {}  # client: player index -> seconds until we may ask the host again


func _ready() -> void:
	randomize()
	var built: Dictionary = WorldScript.build(self)
	candles = built.candles
	anims = built.anim
	world_refs = built
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
	_restore_party()
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
	if not sfx.has_meta("gl_sounds") and sfx.has_method("add_sound"):
		sfx.set_meta("gl_sounds", true)
		for k in EXTRA_SOUNDS:
			sfx.add_sound(k, EXTRA_SOUNDS[k])
	sfx.play(sound_name, volume_db, pitch)


func director() -> Node:
	if dir_node == null or not is_instance_valid(dir_node):
		dir_node = DirectorScript.new()
		dir_node.main = self
		add_child(dir_node)
	return dir_node


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
	l.no_depth_test = false
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

## Player node for slot i (0 = lantern/VR, 1..6 = TV vacuums P2..P7). Slots 2+ start out waiting to join.
func _make_player(i: int, mode: String) -> void:
	var p := PlayerScript.new()
	p.index = i
	p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
	p.main = self
	p.role = "lantern" if i == 0 else "vacuum"
	p.remote = mode == "host" and i >= 1
	p.ghost = mode == "client" and i == 0
	if mode == "client" and i == 2:
		p.key_set = 0  # P3 on the TV: WASD + mouse (as before)
		p.mouse_look = true
	elif mode != "client" and i == 0:
		p.mouse_look = true
	elif i >= 2:
		p.key_set = 2  # extra players are controller-only
	p.position = SPAWNS[i % SPAWNS.size()]
	add_child(p)
	players.append(p)
	if i >= 2:
		p.set_active(false)


func _build_players(mode: String) -> void:
	_ensure_players(mode)


## Lazily tops the player list up to MAX_PLAYERS (also after a hot reload of an older version).
func _ensure_players(mode: String) -> void:
	while players.size() < MAX_PLAYERS:
		_make_player(players.size(), mode)


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
	elif OS.has_environment("BOT_VR") and mode != "client":
		# Test bots: the real VR code with XR nodes the bot moves by hand (no headset).
		print("BOT_VR: fake VR lantern-bearer")
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		cam.position = Vector3(0.0, 1.5, 0.0)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		origin.add_child(left)
		left.position = Vector3(-0.25, 1.1, -0.3)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		origin.add_child(right)
		right.position = Vector3(0.25, 1.2, -0.35)
		players[0].attach_xr(origin, cam, left, right)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: split screen (player 1 holds the lantern)")
	for p in players:
		if p.active and _has_local_view(p):
			_ensure_view(p)
	if mode == "client":
		_build_ghost_mirror()
	_layout_views()


## Players drawn on this machine's screen (flat, driven here).
func _has_local_view(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _ensure_view_grid() -> GridContainer:
	if view_grid != null and is_instance_valid(view_grid):
		return view_grid
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_grid = GridContainer.new()
	view_grid.add_theme_constant_override("h_separation", 4)
	view_grid.add_theme_constant_override("v_separation", 4)
	layer.add_child(view_grid)
	view_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return view_grid


## Lazily builds a split-screen view (SubViewport + camera + HUD) for a local player.
func _ensure_view(p) -> void:
	if p.has_meta("view") and is_instance_valid(p.get_meta("view")):
		return
	var grid := _ensure_view_grid()
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(container)
	# Keep the views in player order, whoever joined first.
	var at := 0
	for c in grid.get_children():
		if c == container:
			break
		var owner_i: int = c.get_meta("player_index", 0)
		if owner_i < p.index:
			at += 1
	container.set_meta("player_index", p.index)
	grid.move_child(container, at)
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


## Split-screen grid: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (7-8 as 4x2). Fewer pixels per view
## when the screen is shared by many players.
func _layout_views() -> void:
	if view_grid == null or not is_instance_valid(view_grid):
		return
	var n := 0
	for c in view_grid.get_children():
		var idx: int = c.get_meta("player_index", 0)
		var on: bool = idx < players.size() and players[idx].active
		c.visible = on
		if on:
			n += 1
	view_grid.columns = 1 if n <= 1 else (2 if n <= 4 else (3 if n <= 6 else 4))
	var scale_3d := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for c in view_grid.get_children():
		for vp in c.get_children():
			if vp is SubViewport:
				vp.scaling_3d_scale = scale_3d
				vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
	if bubble != null and is_instance_valid(bubble):
		var b := 240.0 if n <= 2 else (190.0 if n <= 4 else 150.0)
		bubble.size = Vector2(b, b)
		bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
		var tag: Label = bubble.get_child(0)
		tag.position = Vector2(b / 6.0, b)
	view_count = n


## Client: a camera following the VR player's head, shown as a little bubble in the top right of the TV.
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
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	bubble = TextureRect.new()
	bubble.texture = vp.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bubble)
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


# --- Controllers & drop-in join ----------------------------------------------

## Initial controller assignment (same as before for the first two pads): P2 gets the first pad;
## the second pad goes to P3 on the TV (client) or to P1 in local split screen. Extra pads press A to join.
func _assign_joypads() -> void:
	for dev in Input.get_connected_joypads():
		_auto_bind_pad(dev)


## The local player driven by joypad `device`, or -1.
func pad_owner(device: int) -> int:
	for p in players:
		if p.joy == device and _has_local_view(p):
			return p.index
	return -1


## A newly seen pad: give it back to a player who lost theirs, else the default slots. Returns the index or -1.
func _auto_bind_pad(device: int) -> int:
	if pad_owner(device) >= 0 or net == null or net.mode == "host" or players.size() < 2:
		return pad_owner(device)
	var keys: Array = pad_wait.keys()
	keys.sort()
	for i in keys:
		var w: int = i
		if w < players.size() and players[w].joy < 0:
			players[w].joy = device
			pad_wait.erase(w)
			print("Pad %d reconnected: P%d is back" % [device, w + 1])
			_show_center("P%d IS BACK!" % (w + 1), 1.2, false)
			return w
	if players[1].joy < 0:
		players[1].joy = device
		return 1
	if net.mode == "local" and not players[0].vr and players[0].joy < 0:
		players[0].joy = device
		return 0
	if net.mode == "client" and players[2].joy < 0 and not players[2].active and players[2].uses_keyboard():
		players[2].joy = device
		return 2
	return -1


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play:
		return
	if connected:
		_auto_bind_pad(device)
		return
	var i := pad_owner(device)
	if i < 0:
		return
	var p = players[i]
	p.joy = -1
	p.vac_on = false
	if p.active and not p.uses_keyboard() and not p.mouse_look:
		pad_wait[i] = PAD_WAIT_TIME
		print("Pad %d disconnected: P%d waits %d s for it" % [device, i + 1, int(PAD_WAIT_TIME)])
		_show_center("P%d's controller disconnected!\nPlug it back in to keep playing" % (i + 1), 2.5, false)


## First free TV slot: one with no controls bound, else a waiting keyboard slot (the pad takes it over).
func _free_slot() -> int:
	for p in players:
		if p.index >= 1 and not p.active and _has_local_view(p) and p.joy < 0 and not p.uses_keyboard():
			return p.index
	for p in players:
		if p.index >= 1 and not p.active and _has_local_view(p) and p.joy < 0:
			return p.index
	return -1


## Called by the join_input node (before the pause menu sees it). Returns true if the event was used.
func on_join_input(event: InputEvent) -> bool:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or not ready_to_play or net == null or net.mode == "host":
		return false
	if b.button_index != JOY_BUTTON_A and b.button_index != JOY_BUTTON_START:
		return false
	var owner_i := pad_owner(b.device)
	if owner_i >= 0:
		if players[owner_i].active:
			return false  # A / Start of a playing pad keep their usual job
		if not pending_join.has(owner_i):
			request_join(owner_i)
		return true
	var slot := _free_slot()
	if slot < 0:
		return false
	var p = players[slot]
	if p.uses_keyboard() and slot >= 2:
		p.key_set = 2
		p.mouse_look = false
	p.joy = b.device
	request_join(slot)
	return true


## Drop a player into the hunt (client: ask the host; it switches them on in the next snapshot).
func request_join(i: int) -> void:
	if i <= 0 or i >= players.size() or players[i].active:
		return
	if net.mode == "client":
		pending_join[i] = 2.0
		net.send_action("join", [], i)
		print("Asking the host to let P%d join" % (i + 1))
	else:
		_activate_player(i)


## Test hooks: spawn a ghost kind, start an event, jump to a night, lose every photo on the walls.
func debug_spawn(kind: String):
	if net.mode == "client":
		return null
	return ensure_king() if kind == "king" else _spawn_ghost(kind)


func debug_event(ev: String) -> void:
	director().start_event(ev)


func debug_skip_to_night(n: int) -> void:
	if net.mode == "client":
		return
	for g in get_tree().get_nodes_in_group("ghosts"):
		_remove_ghost(g)
	to_spawn = []
	king_t = -1.0
	night = n - 1
	in_break = true
	break_timer = 0.5


func debug_lose_photos() -> void:
	for g in get_tree().get_nodes_in_group("ghosts"):
		g.carrying = -1
		g.carried.clear()
	for i in photos.size():
		_set_photo_state(i, -2)


## Test hook: join TV player `index` programmatically (the bot drives it directly).
func debug_join(index: int) -> void:
	if index <= 0 or index >= players.size():
		return
	request_join(index)


func _activate_player(i: int) -> void:
	var p = players[i]
	if p.active:
		return
	p.set_active(true)
	p.courage = p.MAX_COURAGE
	if p.is_down:
		p.revive(1.0)
	if not p.remote:
		p.global_position = _spawn_near_team(i)
	_show_center("PLAYER %d JOINED THE HUNT!" % (i + 1), 1.5)
	print("Player %d joined the game (%d players)" % [i + 1, active_count()])
	on_player_activity_changed(p)


func _spawn_near_team(i: int) -> Vector3:
	var anchor: Vector3 = players[0].global_position if players[0].active else Vector3.ZERO
	var off: Vector3 = SPAWNS[i % SPAWNS.size()] - SPAWNS[0]
	return Vector3(clampf(anchor.x + off.x, -19.0, 19.0), 0.0, clampf(anchor.z + off.z, -7.0, 7.0))


## A TV player leaves (controller gone too long). Index 1 (P2) never leaves: it's the keyboard/first pad.
func leave_player(i: int) -> void:
	if i <= 1 or i >= players.size():
		return
	var p = players[i]
	pad_wait.erase(i)
	if _has_local_view(p):
		p.joy = -1
	if net.mode == "client":
		net.send_action("leave", [], i)
		return
	if not p.active:
		return
	p.set_active(false)
	p.vac_on = false
	_show_center("P%d left the hunt" % (i + 1), 1.5)
	print("Player %d left the game (%d players)" % [i + 1, active_count()])
	on_player_activity_changed(p)


func active_count() -> int:
	var n := 0
	for p in players:
		if p.active:
			n += 1
	return n


## TV slots: keyboard / pad joins, pad timeouts and the "press A to join" hint.
func _update_party(delta: float) -> void:
	if not has_meta("join_input"):
		var j := JoinInputScript.new()
		j.main = self
		add_child(j)
		set_meta("join_input", j)
	for k in pending_join.keys():
		var left: float = pending_join[k] - delta
		if left <= 0.0 or players[k].active:
			pending_join.erase(k)
		else:
			pending_join[k] = left
	for k in pad_wait.keys():
		var w: float = pad_wait[k] - delta
		if w <= 0.0:
			leave_player(k)
		else:
			pad_wait[k] = w
	_check_join(delta)
	_update_join_hint()


func _update_join_hint() -> void:
	if join_label == null:
		join_label = _make_label(22)
		join_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		center_label.get_parent().add_child(join_label)
		join_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		join_label.offset_top = -40
		join_label.offset_bottom = -8
		join_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var spare := false
	if net.mode != "host" and _free_slot() >= 0:
		for dev in Input.get_connected_joypads():
			if pad_owner(dev) < 0:
				spare = true
	join_label.visible = spare and not game_over
	join_label.text = "More ghost hunters? Press A on a spare controller to join!"


func on_player_activity_changed(p) -> void:
	if p.active and _has_local_view(p) and ready_to_play:
		if net.mode == "client" and not p.has_meta("view"):
			p.global_position = _spawn_near_team(p.index)
		_ensure_view(p)
	if p.has_meta("view") and is_instance_valid(p.get_meta("view")):
		p.get_meta("view").visible = p.active
	_layout_views()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


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
	m.set_shader_parameter("focus_on", 1.0 if players.size() > 0 and players[0].focus else 0.0)
	m.set_shader_parameter("flash_all", storm_flash)


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
	if scared > 0:
		director().add_stat(p, "bells", 1)
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
	director().add_stat(by, "caught", 1)
	g.drop_photo(by)
	if g.kind == "king":
		director().on_king_caught()
		_show_center("YOU CAUGHT THE GHOST KING!", 2.5)
		sound("fanfare", 0.0)
		burst(g.global_position, Color(1.0, 0.85, 0.3), 40, 0.1)
	elif g.kind == "golden":
		burst(g.global_position, Color(1.0, 0.85, 0.3), 30, 0.08)
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

func _spawn_ghost(kind: String):
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
	director().on_ghost_spawned(kind)
	return g


## The Ghost King (one at a time): arrives through the ceiling of a random room.
func ensure_king():
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g.kind == "king":
			return g
	var g = _spawn_ghost("king")
	g.position = Vector3([-14.0, 0.0, 14.0].pick_random(), 4.5, randf_range(-3.0, 3.0))
	_show_center("THE GHOST KING IS HERE!", 2.2)
	sound("crown", 0.0, 0.8)
	sound("gameover", -8.0, 1.6)
	print("Ghost King arrives")
	return g


## Lost photos go to the Ghost King: catch him to win them back.
func give_king_lost_photos(king) -> void:
	var n := 0
	for i in photos.size():
		if photos[i].state == -2:
			king.carried.append(i)
			_set_photo_state(i, king.net_id)
			n += 1
	if n > 0:
		popup(king.global_position + Vector3.UP * 1.5, "HE HAS %d PHOTO%s!" % [n, "" if n == 1 else "S"], Color(1.0, 0.85, 0.4))


## The king calls two little thieves to help him.
func king_summon(king) -> void:
	if ghost_by_id.size() >= 10:
		return
	for i in 2:
		var g = _spawn_ghost("thief")
		g.position = king.global_position + Vector3(randf_range(-1.5, 1.5), 0.3, randf_range(-1.5, 1.5))
	popup(king.global_position + Vector3.UP * 2.2, "MY FRIENDS, HELP!", Color(0.8, 0.9, 1.0))
	sound("giggle", -2.0, 0.8)


## A snuffer reached the lantern: it goes dark for a few seconds.
func snuff_lantern(g) -> void:
	var p = players[0]
	p.snuff_t = 4.0
	popup(p.global_position + Vector3.UP * 2.2, "PFFF! LANTERN OUT!", Color(1.0, 0.7, 0.4))
	burst(p.global_position + Vector3.UP * 1.4, Color(0.6, 0.6, 0.7), 14, 0.1)
	sound("puff", 0.0)
	director().hint("A SNUFFER blew out the lantern! TV players: vacuum the floating brass hats before they reach it!", 5.0, "snuffed")
	if p.vr:
		p.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.7, 0.2, 0.0)
	print("Lantern snuffed by ghost %d" % g.net_id)


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
		if o != except and o.kind in GhostScript.STEALERS and o.target_photo == i and o.carrying < 0:
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
func return_photo(i: int, rescued: bool, by = null) -> void:
	if i < 0 or i >= photos.size() or photos[i].state < 0:
		return
	_set_photo_state(i, -1)
	if rescued:
		saved += 1
		director().add_stat(by, "saved", 1)
		score += 50
		popup(photos[i].node.global_position + Vector3.UP * 0.5, "PHOTO SAVED!", Color(1.0, 0.9, 0.5))
		sound("pickup", -4.0, 1.0)


func ghost_escaped(g) -> void:
	var i: int = g.carrying
	if g.kind == "golden":
		_show_center("The golden ghost got away!", 1.5)
	if i >= 0:
		_set_photo_state(i, -2)
		sound("gameover", -10.0, 2.2)
		var left := photos_left()
		_show_center("A ghost escaped with a photo!\n%d photos left" % left, 2.0)
		if left <= 3 and left > 0:
			director().hint("Only %d photos left! The GHOST KING keeps lost photos - catch him to get them back!" % left, 5.0, "low_photos")
		print("Photo %d lost (%d left)" % [i, left])
	_remove_ghost(g)


func spook_player(p, g) -> void:
	if p.invuln_t <= 0.0 and not p.is_down:
		director().add_stat(p, "spooked", 1)
	p.spook(SPOOK_AMOUNT * (1.3 if g.get("kind") == "king" else 1.0), g.global_position)
	popup(p.global_position + Vector3.UP * 2.0, "BOO!", g.color)
	sound("spit", -2.0, 0.7)


func on_ghost_stunned(g) -> void:
	director().add_stat(players[0], "stuns", 1)
	popup(g.global_position + Vector3.UP * 0.8, "STUNNED!", Color(1.0, 0.95, 0.4))
	sound("hit", -2.0, 0.5)
	if players[0].vr:
		players[0].hand_r.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.1, 0.0)


func _set_photo_state(i: int, s: int) -> void:
	var ph: Dictionary = photos[i]
	var old: int = ph.state
	ph.state = s
	var node: Node3D = ph.node
	if s >= 0:
		node.visible = true  # carried (also: a lost photo the Ghost King brings back)
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
		if g.kind == "king":
			# The king's photos circle around him.
			var k := 0
			var n := 0
			for other in photos:
				if other.state == s:
					if other == ph:
						k = n
					n += 1
			var a := TAU * k / maxf(n, 1.0) + anim_t * 1.2
			target = g.global_position + Vector3(cos(a) * 1.5, 0.1 + sin(anim_t * 2.0 + k) * 0.2, sin(a) * 1.5)
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
		var d := director()
		music.play_track(1 if d.event_name == "party" else (0 if d.dawn > 0.5 else MUSIC_TRACK))
	director().tick(delta)
	_update_mood()
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_photos(delta)
	_update_hud()
	_ensure_players(net.mode)
	_update_party(delta)
	if net.mode == "client":
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		if game_over_time > 1.5 and (_restart_pressed() or players[0].vr_button_held()):
			_restart()
		return
	if net.mode == "host" and not net.connected:
		if night == 0:
			director().howto()  # the lantern-bearer reads how to play while waiting
		return  # hold the nights until a TV player joins
	_update_vacuums(delta)
	if king_t > 0.0:
		king_t -= delta
		if king_t <= 0.0:
			give_king_lost_photos(ensure_king())
	if in_break:
		if night == 0:
			director().howto()
		break_timer -= delta
		if break_timer <= 0.0:
			_start_night()
	elif not to_spawn.is_empty():
		spawn_timer -= delta
		if spawn_timer <= 0.0 and ghost_by_id.size() < 3 + night + (crowd_bonus() + 1) / 2:
			_spawn_ghost(to_spawn.pop_back())
			spawn_timer = maxf(0.8, 3.0 - night * 0.25 - crowd_bonus() * 0.15)
	elif ghost_by_id.is_empty() and king_t <= 0.0:
		_end_night()
	var all_down := true
	for p in players:
		if p.active and not p.is_down:
			all_down = false
	if all_down:
		if not director().try_relight():
			_on_game_over("Everyone got too spooked!")
	elif photos_left() == 0:
		if not director().try_last_chance():
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
			"float", "spider":
				if not n.has_meta("base"):
					n.set_meta("base", n.position)
				var base: Vector3 = n.get_meta("base")
				var ph: float = n.get_meta("phase", 0.0)
				if a[1] == "float":
					n.position = base + Vector3(0, sin(anim_t * 1.3 + ph) * 0.15, 0)
					n.rotation = Vector3(sin(anim_t * 0.9 + ph) * 0.25, anim_t * 0.4 + ph, cos(anim_t * 0.7 + ph) * 0.2)
				else:
					n.position = base + Vector3(0, sin(anim_t * 0.8) * 0.45 - 0.2, 0)
			"pupil":
				var who = nearest_player(n.global_position)
				if who != null:
					var par := n.get_parent() as Node3D
					var local: Vector3 = par.global_transform.affine_inverse() * (who.global_position + Vector3.UP * 1.4)
					var d2 := Vector2(local.x, local.y).limit_length(1.0) * 0.6
					var home: Vector3 = n.get_meta("home", Vector3.ZERO)
					n.position = n.position.lerp(home + Vector3(d2.x, d2.y, 0.0) * 0.04, 0.2)


func _start_night() -> void:
	night += 1
	in_break = false
	to_spawn = []
	var bonus := crowd_bonus()
	for i in 2 + night + (bonus + 1) / 2:
		to_spawn.append("thief")
	for i in (night + 1) / 2 + bonus / 3:
		to_spawn.append("spooker")
	for i in maxi(0, night - 2):
		to_spawn.append("sprite")
	if night >= 2:
		for i in 1 + (night - 2) / 2:
			to_spawn.append("shy")
		to_spawn.append("golden")
	if night >= 3:
		for i in 1 + (night - 3) / 3:
			to_spawn.append("snuffer")
	to_spawn.shuffle()
	spawn_timer = 1.0
	var king_night := night % 3 == 0
	king_t = 7.0 if king_night else -1.0
	director().on_night_started(night, king_night)
	sound("wave", -2.0, 0.7)
	print("Night %d started (%d ghosts%s)" % [night, to_spawn.size(), ", KING" if king_night else ""])
	var of := (" of %d" % FINAL_NIGHT) if night <= FINAL_NIGHT and not director().won else ""
	if night == 1:
		_show_center("NIGHT 1%s\nThe ghosts are coming for the family photos!" % of, 2.5)
	elif night == FINAL_NIGHT and not director().won:
		_show_center("THE LAST NIGHT!\nSurvive until sunrise!", 2.5)
	elif king_night:
		_show_center("NIGHT %d%s\nThe GHOST KING is coming…" % [night, of], 2.5)
	elif night > FINAL_NIGHT:
		_show_center("BONUS NIGHT %d\n%d ghosts tonight" % [night, to_spawn.size()], 2.0)
	else:
		_show_center("NIGHT %d%s\n%d ghosts tonight" % [night, of, to_spawn.size()], 2.0)


## Extra hunters beyond the classic three (P1 + two TV players) bring a few extra ghosts each night.
## There's still only one lantern, so this stays gentle: +1 thief per two extra players, +1 spooker per three,
## and slightly more ghosts at once / faster spawns.
func crowd_bonus() -> int:
	return maxi(0, active_count() - 3)


func _end_night() -> void:
	in_break = true
	break_timer = 5.0
	score += 100 * night
	for p in players:
		if p.is_down:
			p.revive(0.6)
		else:
			p.courage = minf(p.MAX_COURAGE, p.courage + 30.0)
	director().on_night_ended()
	print("Night %d survived (score %d, caught %d, saved %d)" % [night, score, caught, saved])
	if night == FINAL_NIGHT and not director().won:
		director().won = true
		break_timer = 14.0
		score += 1000
		sound("fanfare", 0.0)
		print("DAWN: the family survived the last night (score %d)" % score)
		_show_center("THE SUN IS UP!\nThe mansion is safe - you did it!\n+1000  ·  %d photos saved\n\n%s\n\nBonus nights next…" % [photos_left(), director().awards_text()], 13.0)
		return
	sound("clear", -2.0, 0.8)
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
	var dawn_line := "You saw the sunrise!  ·  " if director().won else ""
	_show_center("%s\nNight %d  ·  Score %d\n%sGhosts caught %d  ·  Photos saved %d\n%s\n\n%s\n\nPress A or Enter to play again" % [reason, night, score, dawn_line, caught, saved, best_line, director().awards_text()], 0.0)


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
	for p in players:
		if p.index >= 2 and p.active:
			p.set_active(false)
			p.vac_on = false


var join_t := 0.0
## Waiting TV players with controls bound (P3 on WASD + mouse, or a pad) join by holding fire.
func _check_join(delta: float) -> void:
	join_t -= delta
	if join_t > 0.0 or game_over or net.mode == "host":
		return
	for p in players:
		if p.index < 2 or p.active or not _has_local_view(p) or pending_join.has(p.index):
			continue
		if (p.joy >= 0 or p.uses_keyboard()) and p._fire_held():
			join_t = 1.0
			request_join(p.index)
			return


## Restart after game over, keeping the same party (who's playing, and which pad drives whom).
func _restart() -> void:
	_remember_party()
	get_tree().reload_current_scene()


func _remember_party() -> void:
	if net == null or players.is_empty():
		return
	var active_list: Array = []
	var ctl := {}
	for p in players:
		if p.active and p.index >= 2:
			active_list.append(p.index)
		if _has_local_view(p):
			ctl[p.index] = [p.joy, p.key_set, p.mouse_look]
	Engine.set_meta(PARTY_META, {"active": active_list, "ctl": ctl, "mode": net.mode})


## Client: the host restarts the scene after game over, which reloads ours too; keep the party.
func _exit_tree() -> void:
	if net != null and net.mode == "client" and game_over:
		_remember_party()


func _restore_party() -> void:
	if not Engine.has_meta(PARTY_META):
		return
	var party: Dictionary = Engine.get_meta(PARTY_META)
	Engine.remove_meta(PARTY_META)
	if party.get("mode", "") != net.mode:
		return
	var ctl: Dictionary = party.get("ctl", {})
	var connected_pads := Input.get_connected_joypads()
	for p in players:
		if _has_local_view(p) and p.index >= 1:
			p.joy = -1
	for k in ctl.keys():
		var i: int = k
		var c: Array = ctl[k]
		if i >= players.size() or not _has_local_view(players[i]):
			continue
		var dev: int = c[0]
		var p = players[i]
		p.joy = dev if connected_pads.has(dev) else -1
		p.key_set = c[1]
		p.mouse_look = c[2]
	_assign_joypads()  # pads plugged in meanwhile
	var actives: Array = party.get("active", [])
	for k in actives:
		var i: int = k
		if i >= players.size() or players[i].active:
			continue
		if net.mode == "client":
			request_join(i)
		else:
			players[i].set_active(true)
			if _has_local_view(players[i]):
				players[i].global_position = _spawn_near_team(i)
			on_player_activity_changed(players[i])


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index <= 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"vac":
			p.vac_on = bool(args[0]) and not p.is_down
		"join":
			if not p.active:
				print("Net: player %d joined the game" % (index + 1))
				_activate_player(index)
		"leave":
			if p.active and index >= 2:
				print("Net: player %d left the game" % (index + 1))
				leave_player(index)
		"restart":
			if game_over:
				_restart()
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
	return [night, score, caught, saved, game_over, ps, gs, ph, in_break, director().pack()]


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
	if s.size() > 9:
		director().unpack(s[9])


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
		"hint", "lightning":
			director().client_event(kind, args)


## Lightning flashes, party lights and the sunrise (both machines).
func _update_mood() -> void:
	var d := director()
	var e: Environment = world_refs.get("env", null)
	if e != null:
		var night_bg := Color(0.02, 0.01, 0.04)
		var dawn_bg := Color(0.95, 0.6, 0.45)
		e.background_color = night_bg.lerp(dawn_bg, d.dawn)
		e.ambient_light_color = Color(0.42, 0.32, 0.6).lerp(Color(1.0, 0.82, 0.65), d.dawn)
		e.ambient_light_energy = 0.55 + d.dawn * 0.6 + storm_flash * 1.4
	var pane: StandardMaterial3D = world_refs.get("pane", null)
	if pane != null:
		var c := Color(0.55, 0.65, 1.0).lerp(Color(1.0, 0.65, 0.35), d.dawn)
		pane.albedo_color = c
		pane.emission = c.lerp(Color.WHITE, storm_flash)
		pane.emission_energy_multiplier = 1.6 + storm_flash * 8.0 + d.dawn * 1.5
	var ch: OmniLight3D = world_refs.get("chandelier", null)
	if ch != null and is_instance_valid(ch):
		ch.light_color = Color.from_hsv(fmod(anim_t * 0.5, 1.0), 0.6, 1.0) if d.event_name == "party" else Color(1.0, 0.72, 0.4)


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
		+ "Vacuums: stick/WASD move · RT / Space / Enter suck  ·  Start/Esc menu  ·  spare pad: A to join\n" \
		+ "Ghosts only show up in the lantern light! Survive %d nights to see the sunrise." % FINAL_NIGHT


func _show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_label.text = text
	center_label.add_theme_font_size_override("font_size", 56 if text.count("\n") < 6 else 36)
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
		vr_center.no_depth_test = false
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
	var night_text := ("NIGHT %d / %d" % [night, FINAL_NIGHT]) if night <= FINAL_NIGHT and not director().won else ("BONUS NIGHT %d" % night)
	info_label.text = "%s   ·   GHOSTS CAUGHT %d   ·   PHOTOS %d/%d   ·   SCORE %d" % [night_text, caught, photos_left(), photos.size(), score]
	var ev: String = director().event_name
	if ev != "":
		info_label.text += "\n" + str(director().EVENTS[ev][0])
