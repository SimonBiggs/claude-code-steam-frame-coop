extends Node3D
const VrText := preload("res://core/vr_text.gd")
## Game controller: builds the arena, runs waves, camera and HUD.

const PlayerScript := preload("res://games/duo_arena/player.gd")
const EnemyScript := preload("res://games/duo_arena/enemy.gd")
const PickupScript := preload("res://games/duo_arena/pickup.gd")
const SfxScript := preload("res://core/sfx.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const WorldScript := preload("res://games/duo_arena/world.gd")
const HudScript := preload("res://games/duo_arena/hud.gd")
const NetScript := preload("res://core/net.gd")
const BulletScript := preload("res://games/duo_arena/bullet.gd")
const EnemyShotScript := preload("res://games/duo_arena/enemy_shot.gd")
const MusicScript := preload("res://core/music.gd")
const FishScript := preload("res://games/duo_arena/fish.gd")
const AchScript := preload("res://games/duo_arena/achievements.gd")
const TreeScript := preload("res://games/duo_arena/skill_map.gd")
const TurretScript := preload("res://games/duo_arena/turret.gd")
const JoinListenerScript := preload("res://games/duo_arena/join_listener.gd")
const DirectorScript := preload("res://games/duo_arena/director.gd")

## Waves 5 and 10 have bosses; wave 15 is the finale (OMEGA OVERLORD + Fishwort). Beat it to win, then
## the arena keeps going in endless mode.
const FINALE_WAVE := 15
## Game-specific sounds: [seconds, start Hz, end Hz, volume, wave, noise mix]
const EXTRA_SOUNDS := {
	"ping": [0.08, 2400.0, 1800.0, 0.16, "tri", 0.0],
	"crack": [0.3, 520.0, 70.0, 0.5, "saw", 0.7],
	"roar": [0.9, 150.0, 45.0, 0.6, "saw", 0.45],
	"screech": [0.35, 1900.0, 800.0, 0.22, "saw", 0.3],
	"combo": [0.22, 660.0, 1320.0, 0.28, "square", 0.0],
	"meteor": [0.9, 1500.0, 180.0, 0.22, "sine", 0.3],
	"cheer": [1.2, 320.0, 520.0, 0.3, "saw", 0.92],
	"bubble": [0.3, 420.0, 950.0, 0.3, "sine", 0.0],
	"slice": [0.14, 3200.0, 500.0, 0.22, "saw", 0.8],
	"victory": [1.8, 392.0, 1568.0, 0.4, "tri", 0.0],
	"bomb": [1.0, 120.0, 30.0, 0.8, "saw", 0.7],
}

const ARENA_RADIUS := 18.0
## Team upgrades granted after each cleared wave: [name, description, stat, "mul" or "add", amount]
const UPGRADES := [
	["RAPID FIRE", "Shoot 15% faster", "fire_rate", "mul", 0.85],
	["HEAVY ROUNDS", "Bullets hit 40% harder", "damage", "mul", 1.4],
	["QUICK DASH", "Dash recharges 25% faster", "dash_cd", "mul", 0.75],
	["LONG BEAM", "Co-op beam reaches 2 m further", "tether_range", "add", 2.0],
	["SHOCK BEAM", "Co-op beam zaps 60% harder", "tether_dps", "mul", 1.6],
	["TOUGH", "+25 max health", "max_hp", "add", 25.0],
	["SWIFT", "Move 10% faster", "speed", "mul", 1.1],
	["FAST REVIVE", "Revive partners 35% faster", "revive", "mul", 0.65],
]
const TETHER_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float length_m = 5.0;
uniform float energy = 2.0;
uniform vec3 color : source_color = vec3(0.7, 1.0, 0.95);
void fragment() {
	float d = UV.y * length_m;
	float fade = smoothstep(0.8, 3.2, d) * smoothstep(0.8, 3.2, length_m - d);
	ALBEDO = color * energy * fade;
}
"""
const BUBBLE_SHADER := """
shader_type canvas_item;
uniform vec4 ring_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
void fragment() {
	float r = length(UV - 0.5);
	vec4 c = texture(TEXTURE, UV);
	float inside = 1.0 - smoothstep(0.485, 0.5, r);
	float ring = smoothstep(0.45, 0.47, r);
	COLOR = vec4(mix(c.rgb, ring_color.rgb, ring), inside);
}
"""
const PLAYER_COLORS: Array[Color] = [Color(0.3, 0.7, 1.0), Color(1.0, 0.75, 0.25), Color(1.0, 0.45, 0.85),
	Color(0.55, 1.0, 0.25), Color(0.95, 0.95, 1.0), Color(0.7, 0.45, 1.0), Color(0.25, 1.0, 0.85)]
## Index 0 is the VR player (or keyboard P1 in local split screen); TV players are 1..6.
const MAX_PLAYERS := 7
const MAX_LOCAL_VIEWS := 6
## A controller-only player whose controller stays disconnected this long leaves the game.
const PAD_LEAVE_TIME := 20.0

var arena_radius := ARENA_RADIUS
var players: Array = []
var cameras: Array[Camera3D] = []
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var net: Node
var ready_to_play := false
var net_ids := 0
var ghost_nodes := {}
var ghost_cam: Camera3D
var vr_center: Label3D
var music: AudioStreamPlayer
var sky_fish: Node3D
var ach: Node
var skill_tree: Node3D
var toast_label: Label
var toast_3d: Label3D
var toast_tween: Tween
# Messages from Claude: written to res://.dev/say.txt on the host, shown in VR and on the TV.
var say_t := 0.0
var claude_label: Label
var claude_3d: Label3D
var claude_tween: Tween
var last_say := ""
var last_say_time := -100000
var synced := false  # client: received at least one snapshot
# Party mode (up to 6 TV players): which player each controller drives, and the split-screen grid.
var joy_owner := {}  # joypad device id -> player index
var views_root: Control
var view_count := 0
var last_view_area := Vector2.ZERO
var join_listener: Node

var wave := 0
var score := 0
var to_spawn := 0
var spawn_timer := 0.0
var break_timer := 7.0  # the first break is longer: time to read how to play
var in_break := true
var game_over := false
var game_over_time := 0.0

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var sfx: Node
var tether: MeshInstance3D
var tether_mat: StandardMaterial3D
var zap_t := 0.0
var tether_announced := false
var upg := {"fire_rate": 1.0, "damage": 1.0, "dash_cd": 1.0, "tether_range": 10.0, "tether_dps": 3.0,
	"max_hp": 100.0, "speed": 1.0, "revive": 1.0}
var upg_names: Array = []
var dir_node: Node
var won := false  # beat the finale (endless mode after that)
var wave_downs := 0


func _ready() -> void:
	randomize()
	WorldScript.build(self, ARENA_RADIUS)
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
		# Steam Machine: join the VR player's game as player 2, or fall back to local split screen.
		_show_center("Connecting to the VR player…", 0.0)
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
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		_show_center("Waiting for the TV player to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED", 1.5)
	else:
		_show_center("GET READY", 2.0)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


# --- World -------------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.15) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -20, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = make_material(color, 2.0)
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	if net:
		net.event("burst", [pos, color, amount, size])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx_local(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Play a sound on this machine only.
func sfx_local(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	if not sfx.has_meta("da_sounds") and sfx.has_method("add_sound"):
		sfx.set_meta("da_sounds", true)
		for k in EXTRA_SOUNDS:
			sfx.add_sound(k, EXTRA_SOUNDS[k])
	sfx.play(sound_name, volume_db, pitch)


## Pushes enemies away from pos with an expanding ring.
func shockwave(pos: Vector3, radius: float, force: float, damage: float, color: Color, source = null) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = e.global_position - pos
		to.y = 0.0
		var d := to.length()
		if d > radius:
			continue
		var dir := to / d if d > 0.01 else Vector3.RIGHT
		e.knockback += dir * force * (1.0 - d / (radius * 1.5)) / maxf(e.radius, 0.5)
		e.hit(damage, dir, 0.0, source)
	_ring(pos, radius, color)
	if net:
		net.event("ring", [pos, radius, color])


## Big juicy kill explosion: fireball + light flash + debris + floor ring, scaled by enemy size.
func explosion(pos: Vector3, color: Color, radius: float) -> void:
	var size := 0.6 + radius
	# Fireball: bright core inside a coloured shell, both swelling and fading.
	for layer in [[color, 1.0, 6.0], [color.lightened(0.7), 0.55, 10.0]]:
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 16
		sm.rings = 8
		ball.mesh = sm
		var mat := make_material(layer[0], layer[2])
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ball.material_override = mat
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ball)
		ball.global_position = pos
		ball.scale = Vector3.ONE * 0.2
		var t := ball.create_tween().set_parallel()
		t.tween_property(ball, "scale", Vector3.ONE * size * 2.4 * layer[1], 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		t.tween_property(mat, "albedo_color:a", 0.0, 0.4).set_delay(0.08)
		t.chain().tween_callback(ball.queue_free)
	# Light flash.
	var light := OmniLight3D.new()
	light.light_color = color.lightened(0.4)
	light.light_energy = 6.0 + radius * 6.0
	light.omni_range = 5.0 + radius * 6.0
	add_child(light)
	light.global_position = pos + Vector3.UP * 0.5
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.35)
	lt.tween_callback(light.queue_free)
	# Debris: lots, fast.
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 30 + int(radius * 40.0)
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 6.0 + radius * 3.0
	p.initial_velocity_max = 14.0 + radius * 6.0
	p.gravity = Vector3(0, -22, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := BoxMesh.new()
	m.size = Vector3.ONE * (0.12 + radius * 0.1)
	m.material = make_material(color, 3.0)
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)
	_ring(Vector3(pos.x, 0.0, pos.z), size * 2.0, color)
	director().cheer(0.15 + radius * 0.3)
	if net:
		net.event("boom", [pos, color, radius])


## Floating 3D text that rises and fades (score numbers); shown on both machines.
func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.font_size = 64
	l.outline_size = 12
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.4, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.9).set_delay(0.35)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


func _ring(pos: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	ring.mesh = tm
	var mat := make_material(color, 3.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = Vector3(pos.x, 0.15, pos.z)
	ring.scale = Vector3.ONE * 0.3
	var t := ring.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.chain().tween_callback(ring.queue_free)


# --- Players -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	# Networked: VR player + two TV players (player 3 joins later). Local split screen: two.
	# More players (up to MAX_PLAYERS) are created lazily when they join (_ensure_player).
	var count := 3 if mode != "local" else 2
	for i in count:
		_make_player(i, mode)


func _make_player(i: int, mode: String, as_ghost: bool = false):
	var p := PlayerScript.new()
	p.index = i
	p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
	p.main = self
	p.remote = mode == "host" and i >= 1  # host: TV players are driven by the Steam Machine
	p.ghost = (mode == "client" and i == 0) or as_ghost  # client: player 1 is the VR player, shown from snapshots
	if i == 2 and mode != "local":
		p.key_set = 0  # TV player 3: WASD + mouse (or a second controller)
		p.mouse_look = true
	elif mode == "local" and i == 0:
		p.mouse_look = true
	elif i >= 2:
		p.key_set = PlayerScript.NO_KEYS  # drop-in players: their own controller only
	if i < 3:
		p.position = Vector3(-2.5 + 5.0 * i, 0, 4)
	else:
		p.position = Vector3(-6.0 + 4.0 * (i - 3), 0, 7.5)
	add_child(p)
	players.append(p)
	return p


## Lazily create player slots up to index i (new ones start asleep until someone joins).
func _ensure_player(i: int, as_ghost: bool = false):
	while players.size() <= i:
		var ghost_slot: bool = as_ghost and players.size() == i
		var p = _make_player(players.size(), net.mode, ghost_slot)
		p.set_active(false)
		if _is_local(p) and views_root != null:
			_ensure_view(p)
	return players[i]


## A player driven by input on this machine (has its own split-screen view).
func _is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


## The headset GPU is phone-class: drop the expensive effects in VR.
func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.6
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


## Low-res copy of the VR player's view, recorded by gdev so the VR view can be watched/debugged on a desktop.
func _build_vr_mirror(xr_cam: XRCamera3D) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE  # refreshed at 30 fps in _process
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


## Round picture-in-picture of the VR player's view, top-right of the TV player's HUD.
func _add_bubble(hud: Control, source: SubViewport, color: Color) -> void:
	var bubble := TextureRect.new()
	bubble.texture = source.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = BUBBLE_SHADER
	mat.set_shader_parameter("ring_color", color)
	bubble.material = mat
	hud.add_child(bubble)
	bubble.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bubble.size = Vector2(300, 300)
	bubble.position = Vector2(hud.size.x - 330, 30)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 30)
	var tag := Label.new()
	tag.text = "P1 (VR)"
	tag.add_theme_font_size_override("font_size", 24)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_color_override("font_color", color)
	bubble.add_child(tag)
	tag.position = Vector2(110, 300)


## Player 2's view in its own OS window (needs display/window/subwindows/embed_subwindows=false).
func _build_flat_window(p) -> void:
	var win := Window.new()
	win.title = "Duo Arena - Player 2"
	win.add_to_group("p2_window")
	win.size = Vector2i(1920, 1080)
	win.world_3d = get_world_3d()
	win.msaa_3d = Viewport.MSAA_2X
	win.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	win.content_scale_size = Vector2i(1920, 1080)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.scaling_3d_scale = 0.6
	add_child(win)
	var cam := Camera3D.new()
	win.add_child(cam)
	cam.current = true
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	win.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud


## With a VR headset: player 1 in VR, player 2 full screen on the TV.
## Otherwise: side-by-side split screen, one SubViewport per player, both showing this world.
func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 is in VR")
		Engine.physics_ticks_per_second = 90
		# Valve's Godot setup: the main viewport renders to the headset.
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
		var mirror := _build_vr_mirror(cam)
		if mode == "local":
			# No Steam Machine: player 2 gets a window on this device.
			_build_flat_window(players[1])
			_add_bubble(players[1].hud, mirror, PLAYER_COLORS[0])
	elif OS.has_environment("BOT_VR") and mode != "client":
		_build_fake_vr()
	else:
		print("No VR headset: split screen")
	_ensure_views_root()
	for p in players:
		if _is_local(p):
			_ensure_view(p)
	for p in players:
		if p.index == 2:
			p.set_active(false)
	if mode == "client":
		_add_bubble(players[1].hud, _build_ghost_mirror(), PLAYER_COLORS[0])
	_layout_views()


## Test bots (BOT_VR=1): player 1 runs the real VR code with XR nodes that the bot moves by hand.
func _build_fake_vr() -> void:
	print("BOT_VR: fake VR player 1 (XR nodes, no headset)")
	var origin := XROrigin3D.new()
	add_child(origin)
	origin.global_position = players[0].global_position
	var cam := XRCamera3D.new()
	origin.add_child(cam)
	cam.position = Vector3(0.0, 1.6, 0.0)
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


## Black backdrop plus a plain Control that holds one SubViewportContainer per local player.
func _ensure_views_root() -> void:
	if views_root != null and is_instance_valid(views_root):
		return
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	views_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One split-screen view (SubViewport + camera + HUD) for a local player, created once.
func _ensure_view(p) -> void:
	if p.has_meta("view"):
		return
	_ensure_views_root()
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.visible = p.active
	views_root.add_child(container)
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
	if net.mode == "client" and mirror_vp != null and p.index != 1:
		_add_bubble(hud, mirror_vp, PLAYER_COLORS[0])  # everyone on the TV can watch the VR view


## TV split screen grid: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2. Smaller views render at a
## lower resolution, drop MSAA, and get a smaller HUD.
func _layout_views() -> void:
	if views_root == null or not is_instance_valid(views_root):
		return
	var shown: Array = []
	for p in players:
		if not p.has_meta("view"):
			continue
		var c: SubViewportContainer = p.get_meta("view")
		if c.get_parent() != views_root:
			c.reparent(views_root, false)  # from the old HBox layout (hot reload)
		c.visible = p.active
		if p.active:
			shown.append(p)
	var n := shown.size()
	var area := views_root.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
	last_view_area = views_root.size
	view_count = n
	if n == 0:
		return
	var cols := 1
	var rows := 1
	if n == 2:
		cols = 2
	elif n <= 4 and n > 2:
		cols = 2
		rows = 2
	elif n > 4:
		cols = 3
		rows = 2
	var gap := 4.0
	var cell := Vector2((area.x - gap * (cols - 1)) / cols, (area.y - gap * (rows - 1)) / rows)
	var res_scale := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for k in n:
		var p = shown[k]
		var c: SubViewportContainer = p.get_meta("view")
		var col := k % cols
		var row := int(floorf(float(k) / cols))
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2(col * (cell.x + gap), row * (cell.y + gap))
		c.size = cell
		var vp := c.get_child(0) as SubViewport
		if vp != null:
			vp.scaling_3d_scale = res_scale
			vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
		if p.hud != null:
			p.hud.ui_scale = clampf(minf(cell.x / 940.0, cell.y / 900.0), 0.5, 1.0)
	_set_view_effects(n)


## Many views share one GPU: drop SSAO beyond two views, simpler shadows beyond two, none beyond four.
func _set_view_effects(n: int) -> void:
	if players.size() > 0 and players[0].vr:
		return
	for node in get_children():
		if node is WorldEnvironment and node.environment != null:
			var e: Environment = node.environment
			if not node.has_meta("ssao0"):
				node.set_meta("ssao0", e.ssao_enabled)
			e.ssao_enabled = bool(node.get_meta("ssao0")) and n <= 2
		elif node is DirectionalLight3D:
			var l: DirectionalLight3D = node
			if not l.has_meta("shadow0"):
				l.set_meta("shadow0", l.shadow_enabled)
				l.set_meta("shadow_mode0", l.directional_shadow_mode)
			l.shadow_enabled = bool(l.get_meta("shadow0")) and n <= 4
			l.directional_shadow_mode = (DirectionalLight3D.SHADOW_ORTHOGONAL if n > 2
				else int(l.get_meta("shadow_mode0"))) as DirectionalLight3D.ShadowMode


## Client: a camera that follows the VR player's replicated head, for the bubble view.
func _build_ghost_mirror() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	add_child(vp)
	ghost_cam = Camera3D.new()
	ghost_cam.fov = 90.0
	ghost_cam.cull_mask = players[0].camera_cull_mask()
	vp.add_child(ghost_cam)
	ghost_cam.current = true
	return vp


func _assign_joypads() -> void:
	if players.size() < 2:
		return
	# Player 1 is keyboard + mouse; the first controller goes to player 2, a second one to player 1
	# (or to player 3 on the TV machine). Further controllers join with A / Start (handle_join_input).
	var pads := Input.get_connected_joypads()
	joy_owner.clear()
	players[1].joy = pads[0] if pads.size() > 0 else -1
	if players.size() > 2 and net.mode != "local":
		players[2].joy = pads[1] if pads.size() > 1 else -1
	elif not players[0].vr:
		players[0].joy = pads[1] if pads.size() > 1 else -1
	for p in players:
		if p.joy >= 0 and _is_local(p):
			joy_owner[p.joy] = p.index
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


## Controllers coming and going: each controller keeps driving its own player.
func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or players.size() < 2 or net.mode == "host":
		return
	if connected:
		_on_pad_connected(device)
	else:
		_on_pad_disconnected(device)


func _on_pad_disconnected(device: int) -> void:
	print("Joypad %d disconnected" % device)
	if not joy_owner.has(device):
		return
	var idx: int = joy_owner[device]
	joy_owner.erase(device)
	if idx >= players.size():
		return
	var p = players[idx]
	if p.joy != device:
		return
	p.joy = -1
	p.set_meta("last_joy", device)
	if p.key_set == PlayerScript.NO_KEYS and p.active:
		p.pad_lost_t = 0.0  # idles; leaves after PAD_LEAVE_TIME unless the controller comes back
		_show_center("P%d: controller disconnected" % (idx + 1), 2.0, false)


func _on_pad_connected(device: int) -> void:
	print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
	if joy_owner.has(device):
		return
	var pick = null
	# 1. The player this controller belonged to (even if they left meanwhile).
	for p in players:
		if _is_local(p) and p.joy < 0 and p.get_meta("last_joy", -2) == device:
			pick = p
			break
	# 2. Any player still waiting for their lost controller.
	if pick == null:
		for p in players:
			if _is_local(p) and p.joy < 0 and p.pad_lost_t >= 0.0:
				pick = p
				break
	# 3. The usual seats, as before: player 2, then player 1 (local) or player 3 (TV machine).
	if pick == null and players[1].joy < 0 and _is_local(players[1]):
		pick = players[1]
	if pick == null:
		var second = players[2] if net.mode != "local" and players.size() > 2 else players[0]
		if _is_local(second) and second.joy < 0:
			pick = second
	if pick == null:
		return  # unassigned: press A / Start to join as a new player
	pick.joy = device
	joy_owner[device] = pick.index
	pick.pad_lost_t = -1.0
	if not pick.active and pick.has_meta("left_by_pad"):
		_request_join(pick)  # reconnecting brings them back in
	elif pick.active:
		_show_center("P%d: controller connected" % (pick.index + 1), 1.2, false)


## Called by join_listener for every input event; true = consumed (it was a join press).
func handle_join_input(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed:
		return false
	if pad.button_index != JOY_BUTTON_A and pad.button_index != JOY_BUTTON_START:
		return false
	if not ready_to_play or net.mode == "host" or players.size() < 2 or players[0].vr or game_over \
			or get_tree().paused:
		return false
	var device := pad.device
	if joy_owner.has(device):
		var idx: int = joy_owner[device]
		if idx < players.size() and not players[idx].active and _is_local(players[idx]):
			_request_join(players[idx])  # e.g. player 3's controller on the TV machine
			return true
		return false
	return _join_slot(device) != null


## Next free TV seat: a slot nobody is using and no controller is waiting to reclaim.
func _next_free_index() -> int:
	var top := MAX_PLAYERS - 1 if net.mode == "client" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		if i >= players.size():
			return i
		var p = players[i]
		if not _is_local(p) or p.active or p.has_meta("want_join"):
			continue
		if p.joy >= 0 or p.pad_lost_t >= 0.0:
			continue
		return i
	return -1


## A new controller (or a test bot, device -1) takes the next free seat.
func _join_slot(device: int):
	var idx := _next_free_index()
	if idx < 0:
		_show_center("All %d seats are taken!" % (MAX_PLAYERS - 1 if net.mode == "client" else MAX_LOCAL_VIEWS), 1.5, false)
		return null
	var p = _ensure_player(idx)
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


## Local: wake the player up now. TV machine: ask the host (retried by _check_join until it says yes).
func _request_join(p) -> void:
	p.remove_meta("left_by_pad")
	p.pad_lost_t = -1.0
	if net.mode == "client":
		p.set_meta("want_join", true)
		join_t = 0.0
		_check_join(0.0)
	elif not p.active:
		p.set_active(true)
		p.hp = p.stat("max_hp")
		_ensure_view(p)
		on_player_activity_changed(p)
		_show_center("PLAYER %d JOINED!" % (p.index + 1), 1.5)
		sound("revive", -4.0, 1.2)
	_save_party()


## A drop-in player whose controller stayed away too long leaves (their seat frees up).
func _leave(p) -> void:
	p.pad_lost_t = -1.0
	p.remove_meta("want_join")
	p.set_meta("left_by_pad", true)
	if net.mode == "client":
		net.send_action("leave", [], p.index)
	elif p.active:
		p.set_active(false)
		on_player_activity_changed(p)
		_show_center("PLAYER %d LEFT" % (p.index + 1), 1.5)
	_save_party()


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and _is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


## Remember who joined so a restart / reconnect brings the same party back.
func _save_party() -> void:
	var party: Array = []
	for p in players:
		if p.index >= 2 and _is_local(p) and (p.active or p.has_meta("want_join")) and not p.has_meta("left_by_pad"):
			party.append([p.index, p.joy])
	Engine.set_meta("duo_arena_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("duo_arena_party") or players.size() < 2 or players[0].vr:
		return
	var saved: Dictionary = Engine.get_meta("duo_arena_party")
	if saved.get("mode", "") != net.mode:
		return
	var pads := Input.get_connected_joypads()
	var party: Array = saved.get("party", [])
	for entry in party:
		var idx: int = entry[0]
		var device: int = entry[1]
		if idx >= MAX_PLAYERS or (net.mode == "local" and idx >= MAX_LOCAL_VIEWS):
			continue
		if device >= 0 and (not pads.has(device) or (joy_owner.has(device) and joy_owner[device] != idx)):
			continue  # that controller is gone (or now drives someone else)
		var p = _ensure_player(idx)
		if p.active or not _is_local(p):
			continue
		if device >= 0:
			p.joy = device
			joy_owner[device] = idx
		_request_join(p)


func _ensure_join_listener() -> void:
	if join_listener != null and is_instance_valid(join_listener):
		return
	join_listener = JoinListenerScript.new()
	join_listener.name = "JoinListener"
	join_listener.main = self
	add_child(join_listener)


## Test hooks: spawn a kind, start an arena event, jump to a wave.
func debug_spawn(kind: String):
	if net.mode == "client":
		return null
	return spawn_enemy_at(kind, edge_point())


func debug_event(ev: String) -> void:
	director().start_event(ev)


func debug_skip_to_wave(n: int) -> void:
	if net.mode == "client":
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		e.remove_from_group("enemies")
		e.queue_free()
	to_spawn = 0
	wave = n - 1
	in_break = true
	break_timer = 0.5


## Test hook: join a TV player without a controller (index -1: the next free seat).
func debug_join(index: int = -1):
	if not ready_to_play or net.mode == "host":
		return null
	if index < 0:
		return _join_slot(-1)
	var p = _ensure_player(index)
	_request_join(p)
	return p


func active_player_count() -> int:
	var n := 0
	for p in players:
		if p.active:
			n += 1
	return n


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


## Nudges an aim direction toward an enemy that is roughly in front.
func auto_aim(from: Vector3, dir: Vector3) -> Vector3:
	var best := dir
	var best_dot := cos(deg_to_rad(4.0))
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = e.center() - from
		var dist := to.length()
		if dist < 0.5 or dist > 30.0:
			continue
		# Slightly bigger cone for close targets.
		var d := dir.dot(to / dist) + clampf((8.0 - dist) * 0.002, 0.0, 0.01)
		if d > best_dot:
			best_dot = d
			best = to / dist
	return best


## Shakes each player's view based on how close they are to pos.
func add_shake(pos: Vector3, amount: float) -> void:
	for p in players:
		var falloff := clampf(1.0 - p.global_position.distance_to(pos) / 20.0, 0.0, 1.0)
		p.shake = maxf(p.shake, amount * falloff)


# --- Waves -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_update_vr_center()
	if music == null:
		music = MusicScript.new()
		add_child(music)
	if music.has_method("play_track"):
		var boss_wave := wave > 0 and wave % 5 == 0
		music.play_track(1 if boss_wave else maxi(wave - 1, 0) / 2)  # a new track every two waves; bosses rock out
	director().tick(delta)
	if skill_tree != null and not skill_tree.has_meta("map_v3"):  # replace an older skill tree/map
		skill_tree.queue_free()
		skill_tree = null
	if skill_tree == null:
		skill_tree = TreeScript.new()
		skill_tree.main = self
		add_child(skill_tree)
	if sky_fish != null and not sky_fish.has_meta("v2"):  # replace a fish from an older version
		sky_fish.queue_free()
		sky_fish = null
	if sky_fish == null:
		sky_fish = FishScript.new()
		sky_fish.main = self
		add_child(sky_fish)
	_check_say(delta)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	_party_tick(delta)
	if net.mode == "client":
		# The host simulates; we only draw the beam and can ask for a restart (or join as player 3).
		_update_tether(delta)
		_check_join(delta)
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		var vr_restart: bool = players[0].vr and players[0]._dash_held()
		if game_over_time > 1.5 and (_restart_pressed() or vr_restart):
			get_tree().reload_current_scene()
		if tether:
			tether.visible = false
		return

	_update_tether(delta)
	if net.mode == "host" and not net.connected:
		if wave == 0:
			director().howto()  # the VR player reads how to play while waiting
		return  # hold the waves until player 2 joins
	if in_break:
		if wave == 0:
			director().howto()
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
	elif to_spawn > 0:
		spawn_timer -= delta
		var alive := get_tree().get_nodes_in_group("enemies").size()
		var extra := _extra_players()
		if spawn_timer <= 0.0 and alive < 8 + wave + 3 * extra:
			_spawn_enemy(_pick_kind())
			to_spawn -= 1
			spawn_timer = maxf(0.25, 1.1 - wave * 0.07) / (1.0 + 0.15 * extra)
	elif get_tree().get_nodes_in_group("enemies").is_empty():
		_end_wave()

	var all_down := true
	for p in players:
		if p.active and not p.is_down:
			all_down = false
	if all_down:
		_on_game_over()


## Party mode upkeep (lazy, so it also works after a hot reload).
func _party_tick(delta: float) -> void:
	_ensure_join_listener()
	if net.mode == "host":
		if net.connected and players.size() < MAX_PLAYERS:
			_ensure_player(MAX_PLAYERS - 1)  # seats for every TV player the Steam Machine may send
		return
	_update_lost_pads(delta)
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()


## Difficulty scales with the party: 1-2 players as before, each extra player adds enemies.
func _extra_players() -> int:
	return maxi(0, active_player_count() - 2)


func _start_wave() -> void:
	wave += 1
	in_break = false
	wave_downs = 0
	print("Wave %d started" % wave)
	to_spawn = int((4 + wave * 3) * (1.0 + 0.3 * _extra_players()))
	spawn_timer = 0.5
	sound("wave")
	achievements().on_wave_started(wave)
	if wave == 2:
		create_tween().tween_property(help_label, "modulate:a", 0.0, 1.0)
	var boss_kind := _boss_for_wave(wave)
	director().on_wave_started(wave, boss_kind)
	if boss_kind != "":
		to_spawn /= 2
		spawn_enemy_at(boss_kind, edge_point())
		var title: String = EnemyScript.BOSS_NAMES.get(boss_kind, "BOSS")
		if boss_kind == "omega":
			_show_center("FINAL WAVE!\n%s" % title, 2.2)
		else:
			_show_center("WAVE %d\nBOSS: %s" % [wave, title], 1.8)
		sound("roar", 0.0, 0.7)
	elif wave < FINALE_WAVE:
		_show_center("WAVE %d of %d" % [wave, FINALE_WAVE], 1.2)
	else:
		_show_center("WAVE %d\nENDLESS" % wave, 1.2)


## Which boss (if any) starts this wave: ORB OVERLORD on 5, KING REX on 10, the OMEGA OVERLORD finale
## on 15; then they take turns every 5 waves in endless mode.
func _boss_for_wave(w: int) -> String:
	if w % 5 != 0:
		return ""
	if w == FINALE_WAVE:
		return "omega"
	return "rex" if (w / 5) % 2 == 0 else "boss"


func _end_wave() -> void:
	in_break = true
	break_timer = 3.0
	achievements().on_wave_cleared()
	director().on_wave_cleared()
	var upgrade_text := _grant_upgrade()
	for p in players:
		if p.is_down:
			p.revive(0.5)
		else:
			p.heal(30.0)
	var bonus := ""
	if wave_downs == 0 and active_player_count() > 0:
		score += 500
		bonus = "\nNOBODY WENT DOWN: +500!"
	if wave == FINALE_WAVE and not won:
		_victory()
		return
	_show_center("WAVE %d CLEARED%s\n\nUPGRADE: %s" % [wave, bonus, upgrade_text], 2.6)
	sound("clear")


## Beat the finale: fireworks, awards, then endless mode.
func _victory() -> void:
	won = true
	break_timer = 14.0
	achievements().unlock("champion")
	director().victory()
	sound("victory")
	sound("cheer", 0.0)
	print("VICTORY at wave %d, score %d" % [wave, score])
	_show_center("VICTORY!\nYou beat the OMEGA OVERLORD!\nScore %d\n\n%s\n\nENDLESS MODE starts soon - how far can you go?" % [score, director().awards_text()], 13.0)


func _grant_upgrade() -> String:
	var u: Array = UPGRADES.pick_random()
	if u[3] == "mul":
		upg[u[2]] *= u[4]
	else:
		upg[u[2]] += u[4]
	if u[2] == "max_hp":
		for p in players:
			if not p.is_down:
				p.hp += u[4]
	upg_names.append(u[0])
	print("Upgrade: %s" % u[0])
	return "%s\n%s" % [u[0], u[1]]


func _pick_kind() -> String:
	var r := randf()
	if wave >= 3 and r < 0.05 + wave * 0.008:
		return "brute"
	if wave >= 2 and r < 0.36:
		return "runner"
	if wave >= 4 and r < 0.5:
		return "spitter"
	if wave >= 3 and r < 0.58:
		return "ptero"
	if wave >= 6 and r < 0.66:
		return "splitter"
	if wave >= 4 and r < 0.71:
		return "ankylo"
	if wave >= 2 and r > 0.9:
		return "dino"
	if wave >= 2 and r > 0.84:
		return "raptor"
	return "grunt"


## A random spot on the arena edge, away from the players.
func edge_point() -> Vector3:
	var best_pos := Vector3.ZERO
	var best_d := -1.0
	for attempt in 4:
		var angle := randf() * TAU
		var pos := Vector3(cos(angle), 0, sin(angle)) * (ARENA_RADIUS - 1.5)
		var d := INF
		for p in players:
			if p.active:
				d = minf(d, pos.distance_to(p.global_position))
		if d > best_d:
			best_d = d
			best_pos = pos
	return best_pos


func _spawn_enemy(kind: String) -> void:
	var at := edge_point()
	if kind == "raptor":
		# Raptors hunt in packs of three.
		var side := Vector3(at.z, 0.0, -at.x).normalized()
		for i in 3:
			spawn_enemy_at("raptor", at + side * (i - 1) * 1.3)
		return
	spawn_enemy_at(kind, at, director().take_golden())


## Host: one enemy at `pos` (bosses get tougher with a bigger party).
func spawn_enemy_at(kind: String, pos: Vector3, golden: bool = false):
	var e := EnemyScript.new()
	e.setup(kind, wave, self)
	e.net_id = next_net_id()
	e.golden = golden
	var extra := _extra_players()
	e.hp *= (1.0 + 0.25 * extra) if e.is_boss() else (1.0 + 0.08 * extra)  # everyone focuses the boss
	e.position = Vector3(pos.x, 0.0, pos.z)
	add_child(e)
	director().on_enemy_spawned(kind)
	return e


## A splitter burst (or a boss calling help): spawn small fast enemies around where it was.
func split_enemy(pos: Vector3, count: int, kind: String = "runner") -> void:
	for i in count:
		var e := EnemyScript.new()
		e.setup(kind, wave, self)
		e.net_id = next_net_id()
		e.spawn_grace = 0.25
		var a := TAU * i / count
		e.position = Vector3(pos.x + cos(a) * 0.9, 0.0, pos.z + sin(a) * 0.9)
		add_child(e)


func director() -> Node:
	if dir_node == null or not is_instance_valid(dir_node):
		dir_node = DirectorScript.new()
		dir_node.main = self
		add_child(dir_node)
	return dir_node


func achievements() -> Node:
	if ach == null:
		ach = AchScript.new()
		ach.main = self
		add_child(ach)
	return ach


## Gold "achievement unlocked" toast on the TV and in VR (and sent to the other machine).
func achievement_toast(title: String, desc: String, count: int, total: int) -> void:
	if net:
		net.event("achieve", [title, desc, count, total])
	var text := "ACHIEVEMENT UNLOCKED  (%d/%d)\n%s\n%s" % [count, total, title, desc]
	if toast_label == null:
		toast_label = _make_label(30)
		toast_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center_label.get_parent().add_child(toast_label)
		toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		toast_label.offset_top = 105
		toast_label.offset_bottom = 230
	toast_label.text = text
	if players.size() > 0 and players[0].vr:
		if toast_3d == null:
			toast_3d = _vr_text(Vector3(0.0, 0.32, -1.7), Color(1.0, 0.82, 0.3), 36)
		toast_3d.text = text
	sound("clear", -2.0, 1.3)
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween().set_parallel()
	for node in [toast_label, toast_3d]:
		if node:
			node.modulate.a = 1.0
			toast_tween.tween_property(node, "modulate:a", 0.0, 0.6).set_delay(4.0)


## A head-locked text panel for the VR player, with a dark backdrop so it's readable anywhere.
func _vr_text(pos: Vector3, color: Color, font: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = font
	l.outline_size = 12
	l.pixel_size = 0.0022
	l.no_depth_test = false
	l.render_priority = 10
	l.outline_render_priority = 9
	l.width = 1000.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = color
	players[0].xr_camera.add_child(l)
	l.position = pos
	players[0]._set_layers(l, players[0].viewmodel_layer())
	return l


## VR text panels stay put in the world so you can look around them to read; they glide back in
## front of you only when you turn well away (more than 35 degrees) or walk off.
func _lazy_follow(l: Label3D, height: float) -> void:
	if l == null or players.is_empty():
		return
	VrText.follow(l, players[0].xr_camera, self, height, 1.8)


## Thick black outline keeps VR text readable against the bright arena (and hides old backdrop cards).
func _style_vr_text(l: Label3D) -> void:
	if l == null:
		return
	l.outline_size = 26
	l.outline_modulate = Color(0, 0, 0, l.modulate.a)
	if l.has_meta("card"):
		l.get_meta("card").queue_free()
		l.remove_meta("card")


func on_enemy_killed(pos: Vector3, color: Color, points: int, drop_chance: float, radius: float, killer = null, enemy = null) -> void:
	var gained: int = director().on_kill(killer, enemy, points)
	score += gained
	achievements().on_kill(gained, radius)
	# XP goes to whoever landed the last hit; beam/shockwave kills are shared.
	var gain := maxi(1, points / 10)
	if killer != null and is_instance_valid(killer):
		killer.xp += gain
	else:
		for p in players:
			p.xp += gain / 2 + 1
	if radius >= 1.0:
		sound("big_kill", 0.0, 1.4 / radius)
	else:
		sound("kill", -4.0)
	explosion(pos + Vector3.UP * radius, color, radius)
	var label := "+%d" % gained
	if gained > points:
		label = "+%d  x%.1f" % [gained, float(gained) / maxf(points, 1.0)]
	popup(pos + Vector3.UP * (radius * 2.0 + 0.3), label, color.lightened(0.3))
	add_shake(pos, 0.1 + radius * 0.25)
	if randf() < drop_chance * (1.0 + 0.1 * _extra_players()):
		_drop_pickup.call_deferred(pos)


func _drop_pickup(pos: Vector3) -> void:
	var pk := PickupScript.new()
	var r := randf()
	pk.kind = "health" if r < 0.45 else ("spread" if r < 0.64 else ("rapid" if r < 0.8 else ("bubble" if r < 0.91 else "bomb")))
	pk.main = self
	pk.net_id = next_net_id()
	pk.position = Vector3(pos.x, 0, pos.z)
	add_child(pk)


## MEGA BOMB pickup: a huge blast that hurts every monster nearby (the picker gets the credit).
func mega_bomb(pos: Vector3, by) -> void:
	shockwave(pos, 9.0, 30.0, 8.0, Color(1.0, 0.35, 0.4), by)
	explosion(pos + Vector3.UP * 0.8, Color(1.0, 0.35, 0.4), 1.6)
	add_shake(pos, 0.8)
	sound("bomb", 0.0)


func _on_game_over() -> void:
	game_over = true
	game_over_time = 0.0
	sound("gameover")
	print("Game over: wave %d, score %d" % [wave, score])
	var best := _load_best()
	var best_line := "Best: wave %d  ·  score %d" % [best.wave, best.score]
	if score > best.score:
		best_line = "NEW BEST SCORE!  (previous %d)" % best.score
		_save_best(wave, score)
	var who := "YOU BOTH WENT DOWN" if active_player_count() <= 2 else "EVERYONE WENT DOWN"
	if won:
		who = "WHAT A RUN, CHAMPIONS!"
	_show_center(who + "\nWave %d  ·  Score %d\n%s  ·  %s\n\n%s\n\nPress A or Enter to try again  ·  Start / Esc for menu" % [wave, score, best_line, achievements().summary(), director().awards_text()], 0.0)


func _load_best() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load("user://best.cfg")
	return {"wave": cfg.get_value("best", "wave", 0), "score": cfg.get_value("best", "score", 0)}


func _save_best(best_wave: int, best_score: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "wave", best_wave)
	cfg.set_value("best", "score", best_score)
	cfg.save("user://best.cfg")


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
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


## Co-op beam: while both players stand within TETHER_RANGE, a beam links them and zaps enemies it touches.
func _update_tether(delta: float) -> void:
	var tether_range: float = upg.tether_range
	zap_t -= delta
	var used := {}
	for i in players.size():
		for j in range(i + 1, players.size()):
			var a = players[i]
			var b = players[j]
			if not a.active or not b.active or a.is_down or b.is_down:
				continue
			var pa: Vector3 = a.global_position + Vector3.UP * 0.6
			var pb: Vector3 = b.global_position + Vector3.UP * 0.6
			var length := pa.distance_to(pb)
			if length > tether_range or length < 0.5:
				continue
			var key := "%d-%d" % [i, j]
			used[key] = true
			_draw_beam(key, pa, pb, length, tether_range)
			if net.mode != "client":
				_zap_along(pa, pb, delta)
	for key in beams.keys():
		beams[key].visible = used.has(key)
	if not used.is_empty() and not tether_announced:
		tether_announced = true
		_show_center("NEW: CO-OP BEAM\nStay close and the beam between you zaps enemies", 2.5)
	if tether:
		tether.visible = false  # the old single beam from before 3 players


var beams := {}
func _draw_beam(key: String, pa: Vector3, pb: Vector3, length: float, tether_range: float) -> void:
	var beam: MeshInstance3D = beams.get(key)
	if beam == null:
		beam = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 1.0
		cyl.radial_segments = 8
		beam.mesh = cyl
		var sm := ShaderMaterial.new()
		sm.shader = Shader.new()
		sm.shader.code = TETHER_SHADER
		beam.material_override = sm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		beams[key] = beam
	var dir := (pb - pa) / length
	var beam_mat: ShaderMaterial = beam.material_override
	beam_mat.set_shader_parameter("length_m", length)
	beam.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(1.0, length, 1.0)), (pa + pb) * 0.5)
	# Flicker, and fade as the players near the range limit.
	var strength := 1.0 - smoothstep(tether_range * 0.7, tether_range, length)
	var surge: float = director().beam_mult()
	beam_mat.set_shader_parameter("energy", (1.5 + randf() * 2.0) * maxf(strength, 0.3) * (1.6 if surge > 1.0 else 1.0))
	beam_mat.set_shader_parameter("color", director().beam_color())


func _zap_along(pa: Vector3, pb: Vector3, delta: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var ep: Vector3 = e.global_position + Vector3.UP * 0.6
		var cp := Geometry3D.get_closest_point_to_segment(ep, pa, pb)
		if e.lift > 1.5:
			continue  # flying high over the beam
		if Vector2(cp.x - ep.x, cp.z - ep.z).length() < e.radius + 0.25:
			e.hit(upg.tether_dps * director().beam_mult() * delta, Vector3.ZERO, 0.0)
			if e.dead:
				achievements().unlock("beam_team")
			if zap_t <= 0.0:
				zap_t = 0.12
				sound("zap", -6.0)
				burst(cp, Color(0.7, 1.0, 0.95), 4, 0.08)


# --- Networked co-op -------------------------------------------------------

func spawn_bullet(origin: Vector3, dir: Vector3, color: Color, owner_player, visual_only: bool, show_everywhere: bool = false) -> void:
	var b := BulletScript.new()
	b.direction = dir
	b.color = color
	b.damage = owner_player.stat("damage") if owner_player != null and owner_player.has_method("stat") else upg.damage
	b.owner_player = owner_player
	b.visual_only = visual_only
	add_child(b)
	b.global_position = origin
	if not visual_only and (show_everywhere or (owner_player != null and not owner_player.remote)):
		net.event("bullet", [origin, dir, color])


## A player bought a turret: drop it just in front of them.
func build_turret(p) -> void:
	var t := TurretScript.new()
	t.main = self
	t.builder = p
	t.color = p.color
	t.net_id = next_net_id()
	var ahead: Vector3 = Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1.6)
	t.position = Vector3(p.global_position.x + ahead.x, 0.0, p.global_position.z + ahead.z)
	add_child(t)
	popup(t.position + Vector3.UP * 1.6, "TURRET!", p.color)
	sound("clear", -2.0, 0.9)


func on_client_joined() -> void:
	_ensure_player(MAX_PLAYERS - 1)
	_show_center("PLAYER 2 JOINED", 1.5)
	if last_say != "" and Time.get_ticks_msec() - last_say_time < 20000:
		net.event("say", [last_say])  # they were reconnecting when it was said


func on_client_left() -> void:
	# Extra TV players sit out until the Steam Machine is back (it re-joins its saved party).
	for i in range(2, players.size()):
		if players[i].active:
			players[i].set_active(false)
	_show_center("Player 2 left - waiting for them to rejoin…", 0.0)


## Client: player 3 joins by pressing fire on the second controller / keyboard / mouse; drop-in
## players (A / Start on a new controller) are marked "want_join". Ask the host until it agrees.
var join_t := 0.0
func _check_join(delta: float) -> void:
	join_t -= delta
	if join_t > 0.0 or game_over:
		return
	if players.size() > 2 and not players[2].active and not players[2].has_meta("want_join") \
			and players[2]._fire_held():
		players[2].set_meta("want_join", true)
		_save_party()
	for p in players:
		if not p.has_meta("want_join") or not _is_local(p):
			continue
		if p.active:
			p.remove_meta("want_join")
			continue
		join_t = 1.0
		net.send_action("join", [p.index], 1)  # sent as P2 so the host accepts it before it has the seat


## A player slot woke up or went to sleep: show/hide its split-screen view.
func on_player_activity_changed(p) -> void:
	if p.active and _is_local(p) and net.mode != "host":
		_ensure_view(p)
	if p.active:
		p.remove_meta("want_join")
	_layout_views()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


## Host: a TV player did something on the Steam Machine.
func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if action == "join" and args.size() > 0:
		index = int(args[0])  # drop-in seats ask through P2 (the host may not have their seat yet)
	if index <= 0 or index >= MAX_PLAYERS:
		return
	var p2 = _ensure_player(index)
	match action:
		"fire":
			if not has_meta("p2_fired"):
				set_meta("p2_fired", true)
				print("Net: player 2 is shooting")
			var origins: Array = args[0]
			var dirs: Array = args[1]
			for i in mini(origins.size(), dirs.size()):
				spawn_bullet(origins[i], dirs[i], p2.color, p2, false)
		"dash":
			p2.invuln_t = maxf(p2.invuln_t, PlayerScript.DASH_TIME + 0.1)
			director().on_dash(p2)
		"join":
			if not p2.active:
				p2.set_active(true)
				p2.hp = p2.stat("max_hp")
				p2.net_started = false
				_show_center("PLAYER %d JOINED!" % (index + 1), 1.5)
				sound("revive", -4.0, 1.2)
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			if p2.active:
				p2.set_active(false)
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
				print("Net: player %d left the game" % (index + 1))
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "Player 2 opened the menu")
			get_tree().paused = paused


## Shared pause: banner on this machine only (each side shows its own message).
func _set_pause_banner(paused: bool, who: String) -> void:
	if paused:
		_show_center("PAUSED\n" + who, 0.0, false)
	else:
		_show_center("", 0.0, false)
	_update_vr_center()
	if vr_center != null and paused:
		vr_center.remove_meta("placed")  # nothing moves while paused: put the banner right in front now
		_lazy_follow(vr_center, -0.1)
		vr_center.set_meta("moving", false)


## VR player pressed the menu button: pause/resume both machines.
func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHOLD the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	# Kept small for up to 7 players: trailing empty seats are left out, only the VR player needs its
	# head/hand transforms, and personal stats travel as a packed array.
	var last := 0
	for p in players:
		if p.active:
			last = p.index
	var ps := []
	for p in players:
		if p.index > maxi(last, 2):
			break
		var head: Variant = 0
		var hand: Variant = 0
		var lhand: Variant = 0
		if p.index == 0:
			head = p.head_transform()
			hand = p.hand_transform()
			lhand = p.left_hand_transform()
		var st := [p.global_position, p.yaw, p.pitch, p.hp, p.is_down, p.revive_progress, p.spread_t,
			head, hand, lhand, p.pack_personal(), p.xp, p.skills, p.active]
		if p.rapid_t > 0.0 or p.bubble_t > 0.0:
			st.append_array([p.rapid_t, p.bubble_t])  # power-up timers only while they run (small snapshots)
		ps.append(st)
	var es := []
	for e in get_tree().get_nodes_in_group("enemies"):
		var item := [e.net_id, e.kind, e.global_position, e.rotation.y, e.hp]
		var aux: float = e.net_aux_value()
		if aux != 0.0 or e.golden:
			item.append_array([aux, 1 if e.golden else 0])
		es.append(item)
	var pk := []
	for k in get_tree().get_nodes_in_group("pickups"):
		pk.append([k.net_id, k.kind, k.global_position])
	var sh := []
	for s in get_tree().get_nodes_in_group("enemy_shots"):
		sh.append([s.net_id, s.global_position, s.friendly, s.color, s.size])
	var fish_state := [true, 0.0]
	if sky_fish:
		fish_state = [sky_fish.alive, sky_fish.hp]
		if sky_fish.dive_u >= 0.0:
			fish_state.append_array([sky_fish.dive_start, sky_fish.dive_target, sky_fish.dive_u])
	var tu := []
	for t in get_tree().get_nodes_in_group("turrets"):
		tu.append([t.net_id, t.global_position, t.head.rotation.y, t.color])
	return [wave, score, upg, upg_names, game_over, ps, es, pk, sh, fish_state, tu, director().pack()]


## Client: mirror the host's world.
func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	wave = s[0]
	score = s[1]
	upg = s[2]
	upg_names = s[3]
	game_over = s[4]
	var ps: Array = s[5]
	for i in range(ps.size(), players.size()):
		if i >= 2 and players[i].active:  # seat left out of the snapshot: nobody is playing it
			players[i].set_active(false)
			on_player_activity_changed(players[i])
	for i in range(players.size(), mini(ps.size(), MAX_PLAYERS)):
		var st: Array = ps[i]
		if st.size() > 13 and st[13]:
			_ensure_player(i, true)  # a TV player we don't drive here: mirror their avatar
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_ghosts(s[6], "enemy")
	_sync_ghosts(s[7], "pickup")
	_sync_ghosts(s[8], "shot")
	if s.size() > 9 and sky_fish:
		sky_fish.apply_net(s[9])
	if s.size() > 10:
		_sync_ghosts(s[10], "turret")
	if s.size() > 11:
		director().unpack(s[11])



func _sync_ghosts(list: Array, kind: String) -> void:
	var seen := {}
	for item in list:
		var key := "%s:%d" % [kind, item[0]]
		seen[key] = true
		var g = ghost_nodes.get(key)
		if g == null or not is_instance_valid(g):
			g = _make_ghost(kind, item)
			ghost_nodes[key] = g
		g.apply_net(item)
	for key in ghost_nodes.keys():
		if key.begins_with(kind + ":") and not seen.has(key):
			var g = ghost_nodes[key]
			if is_instance_valid(g):
				g.queue_free()
			ghost_nodes.erase(key)


func _make_ghost(kind: String, item: Array) -> Node3D:
	match kind:
		"enemy":
			var e := EnemyScript.new()
			e.setup(item[1], wave, self)
			e.ghost = true
			e.net_id = item[0]
			e.position = item[2]
			if item.size() > 6:
				e.golden = (int(item[6]) & 1) == 1
				e.net_aux = item[5]
				if e.kind == "ptero":
					e.lift = item[5]
			add_child(e)
			return e
		"turret":
			var t := TurretScript.new()
			t.main = self
			t.ghost = true
			t.net_id = item[0]
			t.color = item[3]
			t.position = item[1]
			add_child(t)
			return t
		"pickup":
			var k := PickupScript.new()
			k.kind = item[1]
			k.main = self
			k.ghost = true
			k.net_id = item[0]
			k.position = item[2]
			add_child(k)
			return k
	var shot := EnemyShotScript.new()
	shot.main = self
	shot.ghost = true
	if item.size() > 4:
		shot.color = item[3]
		shot.size = item[4]
	shot.net_id = item[0]
	shot.position = item[1]
	add_child(shot)
	return shot


## Client: one-off events from the host.
func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3])
		"ring":
			_ring(args[0], args[1], args[2])
		"popup":
			popup(args[0], args[1], args[2])
		"achieve":
			achievement_toast(args[0], args[1], args[2], args[3])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR player paused the game")
		"boom":
			explosion(args[0], args[1], args[2])
		"say":
			claude_say(args[0])
		"center":
			_show_center(args[0], args[1])
		"bullet":
			spawn_bullet(args[0], args[1], args[2], null, true)
		"hurt":
			var hp_index: int = args[0] if args.size() > 1 else 1
			if hp_index < players.size():
				players[hp_index].on_remote_hurt(args[-1])
		"hint", "meteor", "fireworks":
			director().client_event(kind, args)
		"hitmark":
			var hm_index: int = args[0] if args.size() > 0 else 1
			if hm_index < players.size() and players[hm_index].hud:
				players[hm_index].hud.hit_marker()


# --- Camera & HUD ------------------------------------------------------------


func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	info_label = _make_label(30)
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 18
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	center_label = _make_label(60)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	help_label = _make_label(22)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 110
	help_label.offset_bottom = 210
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Controller: LEFT STICK move · RIGHT STICK look · RT shoot · A dash · Start menu\n" \
		+ "Keyboard: P1 WASD + mouse, click / Space shoot, Shift dash  ·  P2 arrows (turn), Enter shoot, Ctrl dash\n" \
		+ "Beat 15 waves and 3 bosses to WIN!  ·  More players: press A on another controller to join (up to 6)"


func _show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_label.text = text
	center_label.add_theme_font_size_override("font_size", 60 if text.count("\n") < 6 else 38)
	center_label.modulate.a = 1.0
	if center_tween:
		center_tween.kill()
	if duration > 0.0:
		center_tween = create_tween()
		center_tween.tween_interval(duration)
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.5)


func _check_say(delta: float) -> void:
	say_t -= delta
	if say_t > 0.0:
		return
	say_t = 0.3
	var path := ProjectSettings.globalize_path("res://.dev/say.txt")
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path).strip_edges()
	DirAccess.remove_absolute(path)
	if text != "":
		claude_say(text)


## Show a message from Claude for a few seconds (VR panel below the banner + TV caption).
func claude_say(text: String) -> void:
	if net:
		net.event("say", [text])
	var line := "Claude: " + text
	if claude_label == null or not claude_label.has_meta("plain"):
		if claude_label:
			(claude_label.get_meta("panel") if claude_label.has_meta("panel") else claude_label).queue_free()
		claude_label = _make_label(34)
		claude_label.set_meta("plain", true)
		claude_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
		claude_label.add_theme_constant_override("outline_size", 10)
		claude_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		claude_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		center_label.get_parent().add_child(claude_label)
		claude_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		claude_label.offset_left = -760
		claude_label.offset_right = 760
		claude_label.offset_top = -250
		claude_label.offset_bottom = -140
	last_say = text
	last_say_time = Time.get_ticks_msec()
	claude_label.text = line
	if players.size() > 0 and players[0].vr:
		if claude_3d == null:
			claude_3d = Label3D.new()
			claude_3d.font_size = 40
			claude_3d.outline_size = 12
			claude_3d.pixel_size = 0.0022
			claude_3d.no_depth_test = false
			claude_3d.render_priority = 10
			claude_3d.outline_render_priority = 9
			claude_3d.width = 1000.0
			claude_3d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			claude_3d.modulate = Color(1.0, 0.85, 0.55)
			players[0].xr_camera.add_child(claude_3d)
			claude_3d.position = Vector3(0.0, -0.42, -1.6)
			players[0]._set_layers(claude_3d, players[0].viewmodel_layer())
		claude_3d.text = line
	sound("pickup", -6.0, 0.8)
	var hold := 5.0 + text.length() * 0.08
	if claude_tween:
		claude_tween.kill()
	claude_tween = create_tween().set_parallel()
	for node in [claude_label, claude_3d]:
		if node:
			node.modulate.a = 1.0
			claude_tween.tween_property(node, "modulate:a", 0.0, 0.6).set_delay(hold)


## VR can't show 2D overlays: mirror the centre banner on a floating panel in front of the VR player.
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 48
		vr_center.outline_size = 14
		vr_center.no_depth_test = false
		vr_center.fixed_size = false
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		players[0].xr_camera.add_child(vr_center)
		players[0]._set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.pixel_size = 0.0026
	vr_center.text = preload("res://core/vr_text.gd").short(center_label.text)  # no walls of text in VR
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = center_label.modulate.a
	for l in [vr_center, claude_3d, toast_3d]:
		_style_vr_text(l)
	_lazy_follow(vr_center, -0.1)
	_lazy_follow(claude_3d, -0.42)
	_lazy_follow(toast_3d, 0.32)


func _update_hud() -> void:
	if wave >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time())
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the VR player…"
		return
	var wave_text := ("WAVE %d / %d" % [wave, FINALE_WAVE]) if wave <= FINALE_WAVE and not won else ("WAVE %d  ENDLESS" % wave)
	var d := director()
	if wave > 0 and d.left > 0:
		wave_text += "  ·  %d LEFT" % d.left
	info_label.text = "%s        SCORE %d" % [wave_text, score]
	var xps: Array[String] = []
	for p in players:
		if not p.vr and not p.ghost and p.active:
			xps.append("P%d XP %d" % [p.index + 1, p.xp])
	if not xps.is_empty():
		info_label.text += "        " + "  ·  ".join(xps)
	if not upg_names.is_empty():
		var counts := {}
		for n in upg_names:
			counts[n] = counts.get(n, 0) + 1
		var parts: Array[String] = []
		for n in counts:
			parts.append(n if counts[n] == 1 else "%s x%d" % [n, counts[n]])
		info_label.text += "\n" + "  ·  ".join(parts)
