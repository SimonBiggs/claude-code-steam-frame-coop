extends Node3D
const VrText := preload("res://core/vr_text.gd")
## Hide and Seek: a playful round game in a cosy cartoon house.
## Player 1 (VR, or keyboard+mouse / controller in split screen) is the SEEKER: counts to 20 with eyes
## covered, then searches with a torch. Touch a hider with either hand, or point the torch at one within 3 m
## and pull the trigger. TV players (P2..P7) are HIDERS: run, hide, disguise as a lamp / pot plant / box, and
## squeak for bonus points. Found hiders spectate. Hiders score for every second hidden; the seeker for finds.

const PlayerScript := preload("res://games/hide_and_seek/player.gd")
const WorldScript := preload("res://games/hide_and_seek/world.gd")
const HudScript := preload("res://games/hide_and_seek/hud.gd")
const SfxScript := preload("res://core/sfx.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const NetScript := preload("res://core/net.gd")
const MusicScript := preload("res://core/music.gd")
const JoinInputScript := preload("res://games/hide_and_seek/join_input.gd")

## P1 (seeker) + up to six TV hiders P2..P7.
const MAX_PLAYERS := 7
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.45), Color(0.5, 0.85, 1.0), Color(1.0, 0.55, 0.75),
	Color(0.55, 0.95, 0.55), Color(1.0, 0.65, 0.35), Color(0.75, 0.6, 1.0), Color(0.4, 0.95, 0.9)]
## Round start: the seeker faces the front door in the hall; the hiders stand behind them.
const SEEKER_SPAWN := Vector3(0.0, 0.0, 5.7)
const SPAWNS: Array[Vector3] = [Vector3(0, 0, 5.7), Vector3(-1.4, 0, 2.3), Vector3(1.4, 0, 2.3), Vector3(0, 0, 2.0),
	Vector3(-2.0, 0, 3.4), Vector3(2.0, 0, 3.4), Vector3(-0.7, 0, 3.2), Vector3(0.7, 0, 3.2)]
const PAD_WAIT_TIME := 20.0
const PARTY_META := "hide_and_seek_party"
const MUSIC_TRACK := 0
const TAG_RANGE := 3.0
const TAG_ANGLE := 18.0
const HAND_TOUCH := 0.5  # VR: a hand this close to a hider's middle finds them
const BODY_TOUCH := 0.95  # flat seeker: bumping into a hider finds them
const TAUNT_COOLDOWN := 6.0
const TAUNT_POINTS := 10
const FIND_POINTS := 100
const SURVIVE_BONUS := 50
const BEST_FILE := "user://hide_and_seek_best.cfg"

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
var vr_status: Label3D
var sfx: Node
var music: AudioStreamPlayer
var decoys: Array = []
var _beam_shader: Shader

# Round state (host decides; mirrored to the TV by snapshots).
var phase := "wait"  # wait, intro, count, seek, over
var phase_t := 0.0
var round_no := 0
var count_time := 20.0  # the bot shortens these
var intro_time := 7.0
var seek_override := -1.0
var seek_len := 150.0
var round_scores: Array[int] = [0, 0, 0, 0, 0, 0, 0]
var totals: Array[int] = [0, 0, 0, 0, 0, 0, 0]
var survive_acc: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var finds := 0
var last_tick := -1
var over_t := 0.0
var results_text := ""

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
var join_t := 0.0


func _ready() -> void:
	randomize()
	var built: Dictionary = WorldScript.build(self)
	decoys = built.decoys
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
		_show_center("Connecting to the seeker…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	_ensure_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_restore_party()
	if mode == "host":
		_show_center("HIDE AND SEEK\nWaiting for the hiders on the TV…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED", 1.5)


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


func beam_shader() -> Shader:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = PlayerScript.BEAM_SHADER
	return _beam_shader


func _sfx() -> Node:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
		sfx.add_sound("squeak", [0.22, 1100.0, 1750.0, 0.38, "sine", 0.0])
		sfx.add_sound("poof", [0.25, 500.0, 1400.0, 0.28, "tri", 0.5])
		sfx.add_sound("tick", [0.05, 900.0, 900.0, 0.22, "tri", 0.0])
		sfx.add_sound("found", [0.5, 520.0, 1560.0, 0.36, "square", 0.0])
		sfx.add_sound("click", [0.04, 2400.0, 1800.0, 0.2, "square", 0.3])
		sfx.add_sound("boing", [0.35, 180.0, 520.0, 0.4, "sine", 0.0])
		sfx.add_sound("ready", [0.8, 392.0, 1175.0, 0.35, "tri", 0.0])
	return sfx


func local_sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_sfx().play(sound_name, volume_db, pitch)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	local_sound(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.08) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -6.0, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	var m := BoxMesh.new()
	m.size = Vector3(size, size * 0.3, size * 1.4)
	m.material = make_material(color, 1.5)
	p.mesh = m
	p.color_ramp = null
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)
	if net:
		net.event("burst", [pos, color, amount, size])


func popup(pos: Vector3, text: String, color: Color, through_walls: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = through_walls
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 0.8, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.6)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.6)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color, through_walls])


## A hider squeaked: positional sound (so a VR seeker can hear where), a few musical sparkles.
func squeak_fx(pos: Vector3, pitch: float) -> void:
	var s := _sfx()
	var sp := AudioStreamPlayer3D.new()
	sp.stream = s.streams["squeak"]
	sp.unit_size = 5.0
	sp.max_db = 4.0
	sp.pitch_scale = pitch
	add_child(sp)
	sp.global_position = pos
	sp.play()
	sp.finished.connect(sp.queue_free)
	var sp2 := AudioStreamPlayer3D.new()
	sp2.stream = s.streams["squeak"]
	sp2.unit_size = 5.0
	sp2.pitch_scale = pitch * 1.3
	add_child(sp2)
	sp2.global_position = pos
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(sp2):
			sp2.play())
	get_tree().create_timer(1.0).timeout.connect(sp2.queue_free)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 6
	p.lifetime = 1.0
	p.explosiveness = 0.8
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.5, 0)
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	m.radial_segments = 6
	m.rings = 3
	m.material = make_material(Color(1.0, 0.85, 0.3), 3.0)
	p.mesh = m
	add_child(p)
	p.global_position = pos + Vector3.UP * 0.9
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func ring_fx(pos: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 20
	tm.ring_segments = 4
	ring.mesh = tm
	var mat := make_material(color, 3.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3.ONE * 0.2
	var t := ring.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	t.chain().tween_callback(ring.queue_free)


## Physics ray against the house (layer 1). Empty if nothing is in the way.
func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


# --- Players & views ---------------------------------------------------------

## Player node for slot i (0 = seeker, 1..6 = TV hiders P2..P7). Slots 2+ start out waiting to join.
func _make_player(i: int, mode: String) -> void:
	var p := PlayerScript.new()
	p.index = i
	p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
	p.main = self
	p.role = "seeker" if i == 0 else "hider"
	p.remote = mode == "host" and i >= 1
	p.ghost = mode == "client" and i == 0
	if mode == "client" and i == 2:
		p.key_set = 0  # P3 on the TV: WASD + mouse
		p.mouse_look = true
	elif mode != "client" and i == 0:
		p.mouse_look = true
	elif i >= 2:
		p.key_set = 2  # extra players are controller-only
	p.position = SPAWNS[i % SPAWNS.size()]
	p.yaw = PI if i == 0 else 0.0
	add_child(p)
	players.append(p)
	if i >= 2:
		p.set_active(false)


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
			e.glow_intensity = 0.4
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


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
		print("VR headset found: player 1 is the seeker in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		origin.world_scale = 1.0
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
		players[0].teleport(SEEKER_SPAWN, PI)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: split screen (player 1 is the seeker)")
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


## Split-screen grid: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (7 as 4x2). Fewer pixels per view
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


## Client: what the seeker sees, as a little bubble in the top right of the TV (dark while counting).
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
	tag.text = "SEEKER'S VIEW"
	tag.add_theme_font_size_override("font_size", 20)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_color_override("font_color", PLAYER_COLORS[0])
	bubble.add_child(tag)
	tag.position = Vector2(40, 240)


# --- Controllers & drop-in join ----------------------------------------------

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


## Called by the join_input node (before the pause menu sees it). Only A joins: Start opens the menu.
func on_join_input(event: InputEvent) -> bool:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or not ready_to_play or net == null or net.mode == "host":
		return false
	if b.button_index != JOY_BUTTON_A:
		return false
	var owner_i := pad_owner(b.device)
	if owner_i >= 0:
		if players[owner_i].active:
			return false  # A of a playing pad keeps its usual job
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


## Drop a hider into the game (client: ask the host; it switches them on in the next snapshot).
func request_join(i: int) -> void:
	if i <= 0 or i >= players.size() or players[i].active:
		return
	if net.mode == "client":
		pending_join[i] = 2.0
		net.send_action("join", [], i)
		print("Asking the host to let P%d join" % (i + 1))
	else:
		_activate_player(i)


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
	p.set_prop(-1)
	if phase == "seek":
		p.set_found(true, true)  # no sneaking in mid-round: spectate, hide next round
	else:
		p.set_found(false)
		_place_player(p, SPAWNS[i % SPAWNS.size()], 0.0)
	_show_center("PLAYER %d JOINED!" % (i + 1), 1.5)
	print("Player %d joined the game (%d players)" % [i + 1, active_count()])
	on_player_activity_changed(p)


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
	p.set_prop(-1)
	_show_center("P%d left the game" % (i + 1), 1.5)
	print("Player %d left the game (%d players)" % [i + 1, active_count()])
	on_player_activity_changed(p)


func active_count() -> int:
	var n := 0
	for p in players:
		if p.active:
			n += 1
	return n


## Hiders taking part in this round (not counting late joiners).
func hider_count() -> int:
	var n := 0
	for p in players:
		if p.active and p.role == "hider" and not p.late:
			n += 1
	return n


func hiders_left() -> int:
	var n := 0
	for p in players:
		if p.is_hiding():
			n += 1
	return n


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
	join_label.visible = spare
	join_label.text = "More hiders? Press A on a spare controller to join!"


func on_player_activity_changed(p) -> void:
	if p.active and _has_local_view(p) and ready_to_play:
		_ensure_view(p)
	if p.has_meta("view") and is_instance_valid(p.get_meta("view")):
		p.get_meta("view").visible = p.active
	_layout_views()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


## Waiting TV players with controls bound (P3 on WASD + mouse, or a pad) join by pressing their button.
func _check_join(delta: float) -> void:
	join_t -= delta
	if join_t > 0.0 or net.mode == "host":
		return
	for p in players:
		if p.index < 2 or p.active or not _has_local_view(p) or pending_join.has(p.index):
			continue
		if (p.joy >= 0 or p.uses_keyboard()) and p._fire_held():
			join_t = 1.0
			request_join(p.index)
			return


## Host: move a player (TV players are moved on their own machine, so tell it).
func _place_player(p, pos: Vector3, yaw: float) -> void:
	p.teleport(pos, yaw)
	if p.remote:
		net.event("teleport", [p.index, pos, yaw])


# --- Rounds (host) -------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_ensure_players(net.mode)
	_seek_hints(delta)
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -18.0
	if music.has_method("play_track"):
		music.play_track(MUSIC_TRACK)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head if players[0].net_head != Transform3D() else players[0].head_transform()
		if bubble:
			bubble.modulate = Color(0.05, 0.05, 0.08) if phase == "count" else Color.WHITE
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_party(delta)
	_update_hud()
	_update_vr_text()
	if net.mode == "client":
		if phase == "over":
			over_t += delta
			if over_t > 2.0 and _restart_pressed():
				over_t = -1.0
				net.send_action("restart", [])
		return
	if net.mode == "host" and not net.connected:
		if phase != "wait":
			phase = "wait"
			_show_center("HIDE AND SEEK\nWaiting for the hiders on the TV…", 0.0)
		return
	match phase:
		"wait":
			if hider_count() > 0:
				_start_round()
		"intro":
			phase_t -= delta
			if phase_t <= 0.0:
				_begin_count()
		"count":
			phase_t -= delta
			var n := ceili(phase_t)
			if n != last_tick and n > 0:
				last_tick = n
				sound("tick", -8.0 if n > 3 else -2.0, 1.0 if n > 3 else 1.5)
			if phase_t <= 0.0:
				_begin_seek()
		"seek":
			_update_seek(delta)
		"over":
			over_t += delta
			if over_t > 2.0 and (_restart_pressed() or players[0].vr_button_held()):
				_start_round()


func _start_round() -> void:
	round_no += 1
	finds = 0
	results_text = ""
	for i in round_scores.size():
		round_scores[i] = 0
		survive_acc[i] = 0.0
	for p in players:
		p.set_prop(-1)
		p.set_found(false)
		p.taunt_cd = 0.0
		if p.active:
			_place_player(p, SPAWNS[p.index % SPAWNS.size()], PI if p.index == 0 else 0.0)
	phase = "intro"
	phase_t = intro_time if round_no == 1 else 3.5
	print("Round %d: %d hiders" % [round_no, hider_count()])
	sound("ready", -4.0, 1.0)
	if round_no == 1:
		_show_center("HIDE AND SEEK!\nSEEKER: count with your eyes covered, then find everyone with your torch!\n"
			+ "HIDERS: hide! Turn into a lamp, plant or box. Squeak for bonus points!", intro_time)
	else:
		_show_center("ROUND %d\nGet ready…" % round_no, 3.0)


func _begin_count() -> void:
	phase = "count"
	phase_t = count_time
	last_tick = -1
	_show_center("SEEKER: COUNT TO %d!\nHIDERS: RUN AND HIDE!" % int(count_time), 2.0)
	print("Round %d: counting (%d s)" % [round_no, int(count_time)])


## Gentle balance: more hiders, a bit more seeking time (1 hider 130 s, 3 hiders 150 s, 6 hiders 180 s).
func _seek_time() -> float:
	if seek_override > 0.0:
		return seek_override
	return clampf(120.0 + 10.0 * hider_count(), 130.0, 180.0)


func _begin_seek() -> void:
	phase = "seek"
	seek_len = _seek_time()
	phase_t = seek_len
	last_tick = -1
	sound("ready", -2.0, 1.3)
	_show_center("READY OR NOT,\nHERE I COME!", 2.0)
	print("Round %d: seeking (%d s, %d hiders)" % [round_no, int(seek_len), hiders_left()])


func _update_seek(delta: float) -> void:
	phase_t -= delta
	for p in players:
		if p.is_hiding():
			survive_acc[p.index] += delta
			while survive_acc[p.index] >= 1.0:
				survive_acc[p.index] -= 1.0
				round_scores[p.index] += 1
	_check_touch()
	var n := ceili(phase_t)
	if n <= 10 and n != last_tick and n > 0:
		last_tick = n
		sound("tick", -4.0, 1.2)
	if hiders_left() == 0 and hider_count() > 0:
		_end_round(true)
	elif phase_t <= 0.0:
		_end_round(false)
	elif hider_count() == 0:
		phase = "wait"


## Seeker hands (VR) or body (flat) touching a hider.
func _check_touch() -> void:
	var s = players[0]
	if not s.active:
		return
	for h in players:
		if not h.is_hiding():
			continue
		var c: Vector3 = h.center()
		if s.vr:
			if s.hand_l.global_position.distance_to(c) < HAND_TOUCH or s.hand_r.global_position.distance_to(c) < HAND_TOUCH:
				find_hider(h, "touch")
		elif Vector2(s.global_position.x - c.x, s.global_position.z - c.z).length() < BODY_TOUCH:
			find_hider(h, "touch")


## The seeker's aim: the torch in VR, the crosshair on a flat screen.
func _seeker_aim(s) -> Transform3D:
	if s.vr:
		return s.torch_xform()
	return s.head_transform()


## The hider the seeker's torch would tag right now (within TAG_RANGE and TAG_ANGLE, not behind walls).
func torch_target(s):
	var xf := _seeker_aim(s)
	var origin := xf.origin
	var dir := -xf.basis.z.normalized()
	var best = null
	var best_ang := INF
	for h in players:
		if not h.is_hiding():
			continue
		var c: Vector3 = h.center()
		var to := c - origin
		var d := to.length()
		if d > TAG_RANGE + 0.3 or d < 0.01:
			continue
		var ang := rad_to_deg(acos(clampf(dir.dot(to / d), -1.0, 1.0)) - atan(0.35 / d))
		if ang > TAG_ANGLE or ang >= best_ang:
			continue
		if ray(origin, c).is_empty() or ray(origin, c + Vector3.UP * 0.35).is_empty():
			best_ang = ang
			best = h
	return best


func _decoy_target(s) -> int:
	var xf := _seeker_aim(s)
	var dir := -xf.basis.z.normalized()
	for i in decoys.size():
		var c: Vector3 = decoys[i].pos + Vector3.UP * 0.55
		var to := c - xf.origin
		var d := to.length()
		if d > TAG_RANGE + 0.3 or d < 0.01:
			continue
		var ang := rad_to_deg(acos(clampf(dir.dot(to / d), -1.0, 1.0)) - atan(0.35 / d))
		if ang < TAG_ANGLE:
			return i
	return -1


## The seeker pulled the trigger / clicked.
func torch_click(s) -> void:
	if net.mode == "client" or phase != "seek":
		return
	var h = torch_target(s)
	if h != null:
		find_hider(h, "torch")
		return
	var di := _decoy_target(s)
	if di >= 0:
		var kind: int = decoys[di].kind
		var pos: Vector3 = decoys[di].pos
		popup(pos + Vector3.UP * 1.5, "Just a %s!" % WorldScript.PROP_NAMES[kind], Color(0.8, 0.9, 1.0))
		sound("boing", -4.0, 1.0)
		return
	sound("click", -8.0, 1.0)


func find_hider(h, how: String) -> void:
	if not h.is_hiding() or phase != "seek":
		return
	var was: int = h.prop_kind
	h.set_found(true)
	finds += 1
	round_scores[0] += FIND_POINTS
	var c: Vector3 = h.center()
	burst(c, h.color, 22)
	burst(c, Color(1.0, 0.9, 0.4), 14)
	ring_fx(Vector3(c.x, 0.05, c.z), 2.0, h.color)
	net.event("ring", [Vector3(c.x, 0.05, c.z), 2.0, h.color])
	var what := "FOUND P%d!" % (h.index + 1)
	if was >= 0:
		what = "FOUND P%d!\n(that %s was a hider!)" % [h.index + 1, WorldScript.PROP_NAMES[was]]
	popup(c + Vector3.UP * 1.0, what, h.color.lightened(0.3))
	popup(c + Vector3.UP * 0.4, "+%d" % FIND_POINTS, PLAYER_COLORS[0])
	sound("found", -2.0, 1.0)
	_show_center("P%d FOUND!  %d to go" % [h.index + 1, hiders_left()] if hiders_left() > 0 else "P%d FOUND!" % (h.index + 1), 1.5)
	if players[0].vr:
		players[0].hand_r.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.25, 0.0)
		players[0].hand_l.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.25, 0.0)
	_on_found_local(h.index)
	net.event("found", [h.index])
	print("Round %d: P%d found by %s (%d left)" % [round_no, h.index + 1, how, hiders_left()])


func _on_found_local(i: int) -> void:
	if i < players.size():
		var p = players[i]
		if p.hud != null:
			p.hud.flash_found()
		if p.joy >= 0:
			Input.start_joy_vibration(p.joy, 0.5, 0.8, 0.3)


func set_disguise(p, kind: int) -> void:
	if not p.is_hiding() or (phase != "count" and phase != "seek"):
		return
	if kind == p.prop_kind:
		return
	p.set_prop(kind)
	var pos: Vector3 = p.global_position + Vector3.UP * 0.5
	burst(pos, Color(0.95, 0.95, 1.0), 12, 0.07)
	sound("poof", -6.0, 1.0 if kind >= 0 else 1.3)


func do_taunt(p) -> void:
	if not p.is_hiding() or phase != "seek":
		return
	p.taunt_cd = TAUNT_COOLDOWN
	round_scores[p.index] += TAUNT_POINTS
	var pos: Vector3 = p.global_position + Vector3.UP * 0.6
	var pitch: float = 0.9 + 0.08 * p.index
	squeak_fx(pos, pitch)
	net.event("squeak", [pos, pitch])
	popup(pos + Vector3.UP * 0.7, "SQUEAK! +%d" % TAUNT_POINTS, p.color.lightened(0.3), false)
	print("P%d squeaked" % (p.index + 1))


func _end_round(seeker_won: bool) -> void:
	phase = "over"
	over_t = 0.0
	var lines: Array[String] = []
	if seeker_won:
		var bonus := int(phase_t) * 2
		round_scores[0] += bonus
		lines.append("THE SEEKER FOUND EVERYONE!")
		lines.append("P1 seeker: %d found  +%d  (speedy bonus %d)" % [finds, round_scores[0], bonus])
		sound("clear", -2.0, 1.0)
	else:
		lines.append("TIME'S UP! THE HIDERS WIN!" if hiders_left() > 0 else "TIME'S UP!")
		lines.append("P1 seeker: %d found  +%d" % [finds, round_scores[0]])
		sound("clear", -2.0, 1.25)
	for p in players:
		if p.role != "hider" or not p.active or p.late:
			continue
		if p.is_hiding():
			round_scores[p.index] += SURVIVE_BONUS
		lines.append("P%d: %s  +%d" % [p.index + 1, "found" if p.found else "NEVER FOUND!", round_scores[p.index]])
	var best := -1
	for i in totals.size():
		totals[i] += round_scores[i]
		if players[i].active and (best < 0 or totals[i] > totals[best]):
			best = i
	if best >= 0:
		lines.append("Leader after %d round%s: P%d with %d" % [round_no, "" if round_no == 1 else "s", best + 1, totals[best]])
	lines.append("A / Enter (TV) or trigger (VR): play again")
	results_text = "\n".join(lines)
	_show_center(results_text, 0.0)
	_save_best()
	print("Round %d over: %s, scores %s, totals %s" % [round_no, "seeker wins" if seeker_won else "hiders win", round_scores, totals])


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(BEST_FILE)
	var b: int = cfg.get_value("best", "seeker_round", 0)
	if round_scores[0] > b:
		cfg.set_value("best", "seeker_round", round_scores[0])
		cfg.save(BEST_FILE)


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			return true
	return false


func round_score(i: int) -> int:
	return round_scores[i] if i < round_scores.size() else 0


func total_score(i: int) -> int:
	return totals[i] if i < totals.size() else 0


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
	_show_center("THE HIDERS ARE HERE!", 1.5)


func on_client_left() -> void:
	_show_center("The TV players left - waiting for them to come back…", 0.0)
	for p in players:
		if p.index >= 2 and p.active:
			p.set_active(false)


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


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leak a changed scale into other games
	if ready_to_play:
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
	_assign_joypads()
	var actives: Array = party.get("active", [])
	for k in actives:
		var i: int = k
		if i < players.size() and not players[i].active:
			request_join(i)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index <= 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"prop":
			var kind: int = args[0]
			set_disguise(p, kind)
		"taunt":
			if p.is_hiding() and phase == "seek":
				do_taunt(p)
		"join":
			if not p.active:
				print("Net: player %d joined the game" % (index + 1))
				_activate_player(index)
		"leave":
			if p.active and index >= 2:
				print("Net: player %d left the game" % (index + 1))
				leave_player(index)
		"restart":
			if phase == "over" and over_t > 1.0:
				_start_round()
		"pause":
			var paused: bool = args[0]
			_show_center("PAUSED\nA TV player opened the menu" if paused else "", 0.0, false)
			get_tree().paused = paused


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_show_center("PAUSED\nTap MENU again to resume · trigger elsewhere: back to the arcade" if paused else "", 0.0, false)
	if vr_center:
		VrText.snap(vr_center)
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		ps.append(p.net_state())
	return [phase, phase_t, round_no, seek_len, ps, round_scores, totals, count_time]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	var new_phase: String = s[0]
	if new_phase != phase:
		over_t = 0.0
	phase = new_phase
	phase_t = s[1]
	round_no = s[2]
	seek_len = s[3]
	round_scores.assign(s[5])
	totals.assign(s[6])
	count_time = s[7]
	var ps: Array = s[4]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			local_sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2], args[3])
		"ring":
			ring_fx(args[0], args[1], args[2])
		"squeak":
			squeak_fx(args[0], args[1])
		"center":
			_show_center(args[0], args[1])
		"found":
			_on_found_local(args[0])
		"teleport":
			var i: int = args[0]
			if i < players.size() and _has_local_view(players[i]):
				players[i].teleport(args[1], args[2])
		"remote_pause":
			get_tree().paused = args[0]
			_show_center("PAUSED\nThe seeker paused the game" if args[0] else "", 0.0, false)


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
	info_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 12
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(46)
	center_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 52
	help_label.offset_bottom = 120
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Seeker (P1): WASD + mouse · click / Space / RT: torch tag (3 m) · or bump into hiders\n" \
		+ "Hiders: stick / arrows move · A / Enter / Space: disguise · X / B / Ctrl / E: squeak (+%d)  ·  Start / Esc: menu  ·  spare pad: A to join" % TAUNT_POINTS


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


func _vr_label(font: int, width: float) -> Label3D:
	var l := Label3D.new()
	l.font_size = font
	l.outline_size = 26
	l.outline_modulate = Color.BLACK
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.width = width
	l.pixel_size = 0.0024
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1.0, 0.95, 0.75)
	add_child(l)
	players[0]._set_layers(l, players[0].viewmodel_layer())
	return l


## VR: world-locked banner (also the countdown while the seeker's eyes are covered) and a small status line.
func _update_vr_text() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = _vr_label(48, 900.0)
		vr_status = _vr_label(36, 1100.0)
		vr_status.modulate = Color(0.85, 0.95, 1.0)
	var cam: XRCamera3D = players[0].xr_camera
	if phase == "count":
		vr_center.text = "Eyes covered… counting!\n%d" % ceili(phase_t)
		vr_center.modulate.a = 1.0
	else:
		vr_center.text = center_label.text
		vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = vr_center.modulate.a
	VrText.follow(vr_center, cam, self, -0.12, 1.7)
	vr_status.visible = phase == "seek"
	if vr_status.visible:
		vr_status.text = "%d:%02d   ·   %d hiding   ·   %d pts   ·   trigger: torch tag" % [int(phase_t) / 60, int(phase_t) % 60, hiders_left(), round_scores[0]]
		VrText.follow(vr_status, cam, self, 0.55, 1.7)


func _update_hud() -> void:
	if round_no >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.3)
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the seeker…"
		return
	match phase:
		"wait":
			info_label.text = "HIDE AND SEEK"
		"intro":
			info_label.text = "ROUND %d  ·  GET READY" % round_no
		"count":
			info_label.text = "ROUND %d  ·  HIDE! %d" % [round_no, ceili(phase_t)]
		"seek":
			info_label.text = "ROUND %d  ·  %d:%02d LEFT  ·  %d STILL HIDING" % [round_no, int(phase_t) / 60, int(phase_t) % 60, hiders_left()]
		"over":
			info_label.text = "ROUND %d OVER" % round_no


## Hints for the seeker (David's idea): after 30 s of seeking, every 15 s a gold sparkle and a
## chime pop up where one of the remaining hiders is.
func _seek_hints(delta: float) -> void:
	if net.mode == "client" or phase != "seek":
		set_meta("hint_t", 30.0)
		return
	var t: float = float(get_meta("hint_t", 30.0)) - delta
	if t > 0.0:
		set_meta("hint_t", t)
		return
	set_meta("hint_t", 15.0)
	var hiding: Array = []
	for p in players:
		if p.active and p.role == "hider" and p.is_hiding():
			hiding.append(p)
	if hiding.is_empty():
		return
	var h = hiding[randi() % hiding.size()]
	var at: Vector3 = h.global_position + Vector3.UP * 1.2
	burst(at, Color(1.0, 0.85, 0.2), 40, 0.1)
	popup(at + Vector3.UP * 0.4, "HINT!", Color(1.0, 0.85, 0.2), true)
	sound("pickup", 0.0, 1.4)
