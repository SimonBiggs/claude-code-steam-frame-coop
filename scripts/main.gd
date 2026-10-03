extends Node3D
## Game controller: builds the arena, runs waves, camera and HUD.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const WorldScript := preload("res://scripts/world.gd")
const HudScript := preload("res://scripts/hud.gd")
const NetScript := preload("res://scripts/net.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const EnemyShotScript := preload("res://scripts/enemy_shot.gd")
const MusicScript := preload("res://scripts/music.gd")

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
const PLAYER_COLORS: Array[Color] = [Color(0.3, 0.7, 1.0), Color(1.0, 0.75, 0.25)]

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
# Messages from Claude: written to res://.dev/say.txt on the host, shown in VR and on the TV.
var say_t := 0.0
var claude_label: Label
var claude_3d: Label3D
var claude_tween: Tween
var synced := false  # client: received at least one snapshot

var wave := 0
var score := 0
var to_spawn := 0
var spawn_timer := 0.0
var break_timer := 3.0
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
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	sfx.play(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Pushes enemies away from pos with an expanding ring.
func shockwave(pos: Vector3, radius: float, force: float, damage: float, color: Color) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = e.global_position - pos
		to.y = 0.0
		var d := to.length()
		if d > radius:
			continue
		var dir := to / d if d > 0.01 else Vector3.RIGHT
		e.knockback += dir * force * (1.0 - d / (radius * 1.5)) / maxf(e.radius, 0.5)
		e.hit(damage, dir, 0.0)
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
	l.no_depth_test = true
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
	for i in 2:
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i]
		p.main = self
		p.remote = mode == "host" and i == 1  # host: player 2 is driven by the Steam Machine
		p.ghost = mode == "client" and i == 0  # client: player 1 is the VR player, shown from snapshots
		p.position = Vector3(-2.5 + 5.0 * i, 0, 4)
		add_child(p)
		players.append(p)


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
	else:
		print("No VR headset: split screen")
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
	if mode == "client":
		_add_bubble(players[1].hud, _build_ghost_mirror(), PLAYER_COLORS[0])


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
	# Player 1 is keyboard + mouse; the first controller goes to player 2, a second one to player 1.
	var pads := Input.get_connected_joypads()
	players[1].joy = pads[0] if pads.size() > 0 else -1
	players[0].joy = pads[1] if pads.size() > 1 and not players[0].vr else -1
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


func _on_joy_changed(_device: int, _connected: bool) -> void:
	_assign_joypads()


func nearest_player(pos: Vector3):
	var best = null
	var best_d := INF
	for p in players:
		if p.is_down:
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
		var to: Vector3 = e.global_position + Vector3.UP * e.radius - from
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
	_check_say(delta)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	if net.mode == "client":
		# The host simulates; we only draw the beam and can ask for a restart.
		_update_tether(delta)
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
		return  # hold the waves until player 2 joins
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
	elif to_spawn > 0:
		spawn_timer -= delta
		var alive := get_tree().get_nodes_in_group("enemies").size()
		if spawn_timer <= 0.0 and alive < 8 + wave:
			_spawn_enemy(_pick_kind())
			to_spawn -= 1
			spawn_timer = maxf(0.25, 1.1 - wave * 0.07)
	elif get_tree().get_nodes_in_group("enemies").is_empty():
		_end_wave()

	var all_down := true
	for p in players:
		if not p.is_down:
			all_down = false
	if all_down:
		_on_game_over()


func _start_wave() -> void:
	wave += 1
	in_break = false
	print("Wave %d started" % wave)
	to_spawn = 4 + wave * 3
	spawn_timer = 0.5
	sound("wave")
	if wave == 2:
		create_tween().tween_property(help_label, "modulate:a", 0.0, 1.0)
	if wave % 5 == 0:
		to_spawn /= 2
		_spawn_enemy("boss")
		_show_center("WAVE %d\nBOSS INCOMING" % wave, 1.5)
	else:
		_show_center("WAVE %d" % wave, 1.2)


func _end_wave() -> void:
	in_break = true
	break_timer = 3.0
	var upgrade_text := _grant_upgrade()
	for p in players:
		if p.is_down:
			p.revive(0.5)
		else:
			p.heal(30.0)
	_show_center("WAVE %d CLEARED\n\nUPGRADE: %s" % [wave, upgrade_text], 2.6)
	sound("clear")


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
	if wave >= 2 and r < 0.45:
		return "runner"
	if wave >= 4 and r < 0.62:
		return "spitter"
	if wave >= 6 and r < 0.74:
		return "splitter"
	return "grunt"


func _spawn_enemy(kind: String) -> void:
	var e := EnemyScript.new()
	e.setup(kind, wave, self)
	e.net_id = next_net_id()
	# Try a few edge points and keep the one farthest from both players.
	var best_pos := Vector3.ZERO
	var best_d := -1.0
	for attempt in 4:
		var angle := randf() * TAU
		var pos := Vector3(cos(angle), 0, sin(angle)) * (ARENA_RADIUS - 1.5)
		var d := INF
		for p in players:
			d = minf(d, pos.distance_to(p.global_position))
		if d > best_d:
			best_d = d
			best_pos = pos
	e.position = best_pos
	add_child(e)


## A splitter burst: spawn fast runners around where it died.
func split_enemy(pos: Vector3, count: int) -> void:
	for i in count:
		var e := EnemyScript.new()
		e.setup("runner", wave, self)
		e.net_id = next_net_id()
		e.spawn_grace = 0.25
		var a := TAU * i / count
		e.position = Vector3(pos.x + cos(a) * 0.9, 0.0, pos.z + sin(a) * 0.9)
		add_child(e)


func on_enemy_killed(pos: Vector3, color: Color, points: int, drop_chance: float, radius: float) -> void:
	score += points
	if radius >= 1.0:
		sound("big_kill", 0.0, 1.4 / radius)
	else:
		sound("kill", -4.0)
	explosion(pos + Vector3.UP * radius, color, radius)
	popup(pos + Vector3.UP * (radius * 2.0 + 0.3), "+%d" % points, color.lightened(0.3))
	add_shake(pos, 0.1 + radius * 0.25)
	if randf() < drop_chance:
		_drop_pickup.call_deferred(pos)


func _drop_pickup(pos: Vector3) -> void:
	var pk := PickupScript.new()
	pk.kind = "health" if randf() < 0.6 else "spread"
	pk.main = self
	pk.net_id = next_net_id()
	pk.position = Vector3(pos.x, 0, pos.z)
	add_child(pk)


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
	_show_center("YOU BOTH WENT DOWN\nWave %d  ·  Score %d\n%s\n\nPress A or Enter to try again  ·  Start / Esc for menu" % [wave, score, best_line], 0.0)


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
	if tether == null:
		tether = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 1.0
		cyl.radial_segments = 8
		tether.mesh = cyl
		tether_mat = make_material(Color(0.7, 1.0, 0.95), 4.0)
		tether.material_override = tether_mat
		tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tether)
	var a = players[0]
	var b = players[1]
	var pa: Vector3 = a.global_position + Vector3.UP * 0.6
	var pb: Vector3 = b.global_position + Vector3.UP * 0.6
	var length := pa.distance_to(pb)
	var tether_range: float = upg.tether_range
	tether.visible = not a.is_down and not b.is_down and length <= tether_range and length > 0.5
	if not tether.visible:
		return
	if not tether_announced:
		tether_announced = true
		_show_center("NEW: CO-OP BEAM\nStay close and the beam between you zaps enemies", 2.5)
	var dir := (pb - pa) / length
	if not tether.material_override is ShaderMaterial:
		var sm := ShaderMaterial.new()
		sm.shader = Shader.new()
		sm.shader.code = TETHER_SHADER
		tether.material_override = sm
	var beam_mat: ShaderMaterial = tether.material_override
	beam_mat.set_shader_parameter("length_m", length)
	tether.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(1.0, length, 1.0)), (pa + pb) * 0.5)
	# Flicker, and fade as the players near the range limit.
	var strength := 1.0 - smoothstep(tether_range * 0.7, tether_range, length)
	beam_mat.set_shader_parameter("energy", (1.5 + randf() * 2.0) * maxf(strength, 0.3))
	if net.mode == "client":
		return  # zapping is simulated on the host
	zap_t -= delta
	for e in get_tree().get_nodes_in_group("enemies"):
		var ep: Vector3 = e.global_position + Vector3.UP * 0.6
		var cp := Geometry3D.get_closest_point_to_segment(ep, pa, pb)
		if Vector2(cp.x - ep.x, cp.z - ep.z).length() < e.radius + 0.25:
			e.hit(upg.tether_dps * delta, Vector3.ZERO, 0.0)
			if zap_t <= 0.0:
				zap_t = 0.12
				sound("zap", -6.0)
				burst(cp, Color(0.7, 1.0, 0.95), 4, 0.08)


# --- Networked co-op -------------------------------------------------------

func spawn_bullet(origin: Vector3, dir: Vector3, color: Color, owner_player, visual_only: bool) -> void:
	var b := BulletScript.new()
	b.direction = dir
	b.color = color
	b.damage = upg.damage
	b.owner_player = owner_player
	b.visual_only = visual_only
	add_child(b)
	b.global_position = origin
	if not visual_only and owner_player != null and not owner_player.remote:
		net.event("bullet", [origin, dir, color])


func on_client_joined() -> void:
	_show_center("PLAYER 2 JOINED", 1.5)


func on_client_left() -> void:
	_show_center("Player 2 left - waiting for them to rejoin…", 0.0)


## Host: player 2 did something on the Steam Machine.
func on_p2_action(action: String, args: Array) -> void:
	var p2 = players[1]
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
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			if paused:
				_show_center("PAUSED\nPlayer 2 opened the menu", 0.0, false)
				_update_vr_center()
			else:
				_show_center("", 0.0, false)
				_update_vr_center()
			get_tree().paused = paused


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		ps.append([p.global_position, p.yaw, p.pitch, p.hp, p.is_down, p.revive_progress, p.spread_t,
			p.head_transform(), p.hand_transform(), p.left_hand_transform()])
	var es := []
	for e in get_tree().get_nodes_in_group("enemies"):
		es.append([e.net_id, e.kind, e.global_position, e.rotation.y, e.hp])
	var pk := []
	for k in get_tree().get_nodes_in_group("pickups"):
		pk.append([k.net_id, k.kind, k.global_position])
	var sh := []
	for s in get_tree().get_nodes_in_group("enemy_shots"):
		sh.append([s.net_id, s.global_position, s.friendly])
	return [wave, score, upg, upg_names, game_over, ps, es, pk, sh]


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
	for i in mini(2, ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_ghosts(s[6], "enemy")
	_sync_ghosts(s[7], "pickup")
	_sync_ghosts(s[8], "shot")


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
			add_child(e)
			return e
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
		"boom":
			explosion(args[0], args[1], args[2])
		"say":
			claude_say(args[0])
		"center":
			_show_center(args[0], args[1])
		"bullet":
			spawn_bullet(args[0], args[1], args[2], null, true)
		"hurt":
			players[1].on_remote_hurt(args[0])
		"hitmark":
			if players[1].hud:
				players[1].hud.hit_marker()


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
	help_label.text = "Controller: left stick move · right stick look · RT shoot · A / LB dash · Start menu\n" \
		+ "Keyboard: P1 WASD + mouse, click / Space shoot, Shift dash  ·  P2 arrows (turn), Enter shoot, Ctrl dash\n" \
		+ "Stay close: the beam between you zaps enemies  ·  Stand next to a downed partner to revive them!"


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
	if claude_label == null:
		claude_label = _make_label(30)
		claude_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
		claude_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		claude_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		center_label.get_parent().add_child(claude_label)
		claude_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		claude_label.offset_left = -700
		claude_label.offset_right = 700
		claude_label.offset_top = -240
		claude_label.offset_bottom = -140
	claude_label.text = line
	if players.size() > 0 and players[0].vr:
		if claude_3d == null:
			claude_3d = Label3D.new()
			claude_3d.font_size = 40
			claude_3d.outline_size = 12
			claude_3d.pixel_size = 0.0022
			claude_3d.no_depth_test = true
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
	var hold := 3.0 + text.length() * 0.06
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
		vr_center.no_depth_test = true
		vr_center.fixed_size = false
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		players[0].xr_camera.add_child(vr_center)
		players[0]._set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.pixel_size = 0.0026
	vr_center.position = Vector3(0.0, -0.1, -1.8)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = center_label.modulate.a


func _update_hud() -> void:
	if wave >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time())
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the VR player…"
		return
	info_label.text = "WAVE %d        SCORE %d" % [wave, score]
	if not upg_names.is_empty():
		var counts := {}
		for n in upg_names:
			counts[n] = counts.get(n, 0) + 1
		var parts: Array[String] = []
		for n in counts:
			parts.append(n if counts[n] == 1 else "%s x%d" % [n, counts[n]])
		info_label.text += "\n" + "  ·  ".join(parts)
