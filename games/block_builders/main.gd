extends Node3D
const VrText := preload("res://core/vr_text.gd")
## BLOCK BUILDERS: a co-op platformer on a floating obstacle course.
##  - Player 1 (VR, host) is the giant BUILDER: the course is a tabletop diorama (world_scale 8).
##    Grab colourful blocks (planks, stairs, springs, fans) from the tray with the right trigger and
##    snap them into the course to build bridges and paths. Blocks are limited: it's a puzzle!
##  - Players 2 to 7 (TV) are tiny RUNNERS: run and jump to the flag. Gaps, lava, gusts and rising
##    water send you back. A level clears when every active runner is at the flag.
##    P2: keyboard (WASD + Space) and the first controller. Any other controller presses A to drop in
##    as the next free runner (up to P7). Each controller drives exactly one runner (by device id).
## Modes (docs/GAME_DEV_GUIDE.md): DUO_JOIN=<host> client, VR or DUO_HOST=1 host, else local split screen
## (flat builder on the left with mouse / 2nd controller, runners beside it).
## BB_FAKE_VR=1 (tests): run the VR builder code without a headset.

const Art := preload("res://games/block_builders/art.gd")
const Levels := preload("res://games/block_builders/levels.gd")
const CourseScript := preload("res://games/block_builders/course.gd")
const BuilderScript := preload("res://games/block_builders/builder.gd")
const RunnerScript := preload("res://games/block_builders/runner.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")

const MAX_RUNNERS := 6  # TV players 2..7 (player indices 1..6)
const INTRO_TIME := 9.0
const CLEAR_TIME := 9.0
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.82, 0.25), Color(1.0, 0.45, 0.3), Color(0.3, 0.75, 1.0),
	Color(0.45, 0.95, 0.4), Color(1.0, 0.5, 0.85), Color(0.7, 0.5, 1.0), Color(0.3, 0.95, 0.9)]
const SOUNDS := {
	"jump": [0.12, 300.0, 720.0, 0.22, "square", 0.0],
	"land": [0.06, 180.0, 90.0, 0.25, "sine", 0.3],
	"boing": [0.4, 160.0, 900.0, 0.45, "sine", 0.0],
	"whoosh": [0.4, 600.0, 200.0, 0.18, "sine", 0.9],
	"place": [0.12, 620.0, 260.0, 0.4, "square", 0.1],
	"click": [0.03, 1200.0, 900.0, 0.2, "square", 0.0],
	"splash": [0.45, 400.0, 100.0, 0.35, "sine", 0.85],
	"sizzle": [0.5, 900.0, 300.0, 0.3, "saw", 0.9],
	"fall": [0.6, 700.0, 120.0, 0.3, "tri", 0.0],
	"flag": [0.5, 523.0, 1568.0, 0.35, "tri", 0.0],
	"fanfare": [1.0, 392.0, 1568.0, 0.4, "square", 0.0],
	"poof": [0.2, 300.0, 150.0, 0.25, "sine", 0.7],
	"tick": [0.05, 1500.0, 1500.0, 0.15, "square", 0.0],
}

var players: Array = []
var builder
var course: Node3D
var net: Node
var ready_to_play := false
var xr_interface: XRInterface
var vr_on := false
var mirror_vp: SubViewport
var mirror_t := 0.0
var synced := false
var sfx: Node
var music: AudioStreamPlayer

# Game state (host simulates; the TV mirrors it from snapshots)
var state := "intro"   # intro, play, clear, failed, won
var state_t := 0.0
var level := 0
var level_seq := 0
var level_time := 0.0
var time_left := 0.0
var score := 0
var water_y := -100.0
var budget := {}
var levels_cleared := 0
var tick_last := -1

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_info: Label3D

# Split-screen views
var view_root: Control
var views_dirty := true
var last_view_size := Vector2.ZERO
var view_count := 0
var lamp: DirectionalLight3D
var join_t := 0.0


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	vr_on = xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	if OS.has_environment("BB_FAKE_VR") and not OS.has_environment("DUO_JOIN"):
		vr_on = true  # tests: run the VR code paths headless, without a headset
	_build_world()
	course = CourseScript.new()
	course.main = self
	add_child(course)
	course.load_level(0)
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
		_show_center("Connecting to the Builder…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if vr_on or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	_build_players(mode)
	_build_views(mode)
	_assign_joypads()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_reset_budget()
	ready_to_play = true
	state = "intro"
	state_t = 0.0
	print("Block Builders: %s mode" % mode)
	var runner_help := "RUNNERS: left stick / WASD move · A / Space jump · right stick / arrows turn the camera · " \
		+ "press A on a spare controller to join (up to 6)"
	if mode == "local":
		help_label.text = runner_help + "\nBUILDER (left screen): mouse / left stick moves · click / A places · right click / B removes · " \
			+ "Q E / LB RB pick a block · wheel / D-pad raises · R / Y turns"
	else:
		help_label.text = runner_help + "\nThe BUILDER in VR grabs blocks from the tray and builds your path"
	if mode == "host":
		_show_center("BLOCK BUILDERS\nWaiting for the runners to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED!", 1.5, false)
	else:
		_show_intro()


func _show_intro() -> void:
	_show_center("BLOCK BUILDERS\n\nBUILDER: grab blocks from the tray and snap them\ninto the course to build a path (A turns a block)\n" \
		+ "RUNNERS: run and jump to the FLAG - everyone has to make it!\nBlocks are limited, so plan together!\n\n" \
		+ "Pull the trigger / press A to start", 0.0)


# --- World -----------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.76, 0.98)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 1.0)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.4 if vr_on else 0.7
	e.glow_bloom = 0.03
	e.ssao_enabled = false
	e.fog_enabled = false
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	env.environment = e
	add_child(env)
	lamp = DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-55, 30, 0)
	lamp.light_color = Color(1.0, 0.96, 0.88)
	lamp.light_energy = 1.15
	lamp.shadow_enabled = not vr_on
	lamp.directional_shadow_max_distance = 40.0
	add_child(lamp)


# --- Players and views -------------------------------------------------------------

func _build_players(mode: String) -> void:
	builder = BuilderScript.new()
	builder.main = self
	builder.color = PLAYER_COLORS[0]
	add_child(builder)
	players.append(builder)
	_ensure_runners(mode)


## Every machine keeps a runner node for each TV slot (indices 1..MAX_RUNNERS) so indices line up
## with net.gd and the snapshots. Slots 3+ sleep until someone joins.
func _ensure_runners(mode: String) -> void:
	if builder == null:
		return
	while players.size() <= MAX_RUNNERS:
		var i := players.size()
		var r := RunnerScript.new()
		r.main = self
		r.index = i
		r.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		r.remote = mode == "host"
		r.key_set = 0 if i == 1 else -1
		r.mouse_on = i == 1 and mode == "client"
		r.claimed = i == 1
		add_child(r)
		r.global_position = r.start_spot()
		r.reset_to_start()
		players.append(r)
		if i >= 2:
			r.set_active(false)


func runners() -> Array:
	return players.slice(1)


func active_runner_count() -> int:
	var n := 0
	for r in runners():
		if r.active:
			n += 1
	return n


func _build_views(mode: String) -> void:
	if vr_on and mode != "client":
		xr_interface = XRServer.find_interface("OpenXR")
		print("VR headset found: player 1 is the Builder")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = xr_interface != null and xr_interface.is_initialized()
		get_viewport().msaa_3d = Viewport.MSAA_2X
		var origin := XROrigin3D.new()
		add_child(origin)
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
		builder.setup_vr(origin, cam, left, right)
		_build_vr_mirror(cam)
	elif mode == "client":
		builder.setup_ghost()
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_root = Control.new()
	view_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(view_root)
	view_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not builder.vr and not builder.ghost:
		var vp := _add_view(builder)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		builder.setup_flat(cam, true)
		_add_view_hud(builder, vp)
	for r in runners():
		if not r.remote and r.active:
			_ensure_view(r)
	views_dirty = true
	_layout_views()


func _add_view(p) -> SubViewport:
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_root.add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(vp)
	return vp


func _add_view_hud(p, vp: SubViewport) -> void:
	var hud := CanvasLayer.new()
	vp.add_child(hud)
	p.hud_label = _make_label(30)
	p.hud_label.add_theme_color_override("font_color", p.color.lightened(0.3))
	hud.add_child(p.hud_label)
	p.hint_label = _make_label(34)
	p.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(p.hint_label)
	_scale_hud(p, 1.0)


## A runner's own split-screen view + HUD, made the first time they're active on this machine.
func _ensure_view(r) -> void:
	if r.remote or r.has_meta("view") or view_root == null:
		return
	var vp := _add_view(r)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	r.attach_camera(cam)
	_add_view_hud(r, vp)
	views_dirty = true


## Per-view HUD, shrunk for small grid cells.
func _scale_hud(p, s: float) -> void:
	if p.hud_label == null or p.hint_label == null:
		return
	if p.has_meta("hud_scale") and is_equal_approx(float(p.get_meta("hud_scale")), s):
		return
	p.set_meta("hud_scale", s)
	var fs := maxi(12, int(28 * s))
	var hl: Label = p.hud_label
	hl.add_theme_font_size_override("font_size", fs)
	hl.add_theme_constant_override("outline_size", maxi(4, int(fs / 4.0)))
	hl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hl.offset_top = 14.0 * s
	hl.offset_left = 20.0 * s
	var fs2 := maxi(12, int(34 * s))
	var hn: Label = p.hint_label
	hn.add_theme_font_size_override("font_size", fs2)
	hn.add_theme_constant_override("outline_size", maxi(4, int(fs2 / 4.0)))
	hn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hn.offset_left = -500.0 * s
	hn.offset_right = 500.0 * s
	hn.offset_top = -200.0 * s
	hn.offset_bottom = -80.0 * s


## Split-screen grid: 1 view full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (7 as 4x2: local mode
## with the flat builder plus six runners). More views = lower 3D resolution, no MSAA, fewer shadows.
func _layout_views() -> void:
	if view_root == null:
		return
	var area := view_root.size
	if not views_dirty and area == last_view_size:
		return
	views_dirty = false
	last_view_size = area
	var list: Array = []
	for p in players:
		if p.has_meta("view"):
			var c: SubViewportContainer = p.get_meta("view")
			c.visible = p.active and not p.remote
			if c.visible:
				list.append(p)
	var n := list.size()
	view_count = n
	if n == 0:
		return
	var cols := 1
	var rows := 1
	if n == 2:
		cols = 2
	elif n > 2 and n <= 4:
		cols = 2
		rows = 2
	elif n > 4 and n <= 6:
		cols = 3
		rows = 2
	elif n > 6:
		cols = 4
		rows = 2
	var gap := 4.0
	var cell := Vector2((area.x - gap * (cols - 1)) / cols, (area.y - gap * (rows - 1)) / rows)
	var scale3d := 1.0
	if n > 4:
		scale3d = 0.55
	elif n > 2:
		scale3d = 0.7
	var hud_s := 1.0
	if n > 1:
		hud_s = clampf(minf(cell.x / 958.0, cell.y / 1080.0) * 1.25, 0.45, 1.0)
	for i in n:
		var p = list[i]
		var c: SubViewportContainer = p.get_meta("view")
		var row := floori(float(i) / cols)
		var col := i - row * cols
		var in_row := mini(cols, n - row * cols)  # centre a short last row
		var x0 := (area.x - (cell.x * in_row + gap * (in_row - 1))) * 0.5
		c.position = Vector2(x0 + col * (cell.x + gap), row * (cell.y + gap))
		c.size = cell
		var vp := c.get_child(0) as SubViewport
		if vp:
			vp.scaling_3d_scale = scale3d
			vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
		_scale_hud(p, hud_s)
	if lamp != null and not vr_on:
		lamp.shadow_enabled = n <= 4
		lamp.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if n <= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL


## Low-res copy of the builder's VR view for gdev / people watching.
func _build_vr_mirror(xr_cam: XRCamera3D) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	vp.add_to_group("gdev_capture")
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.05 * BuilderScript.S
	cam.far = 120.0 * BuilderScript.S
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


# --- Controllers and drop-in ---------------------------------------------------------

## Players that get a controller automatically: P2 (on the TV / split screen), then the flat builder.
## Any other controller drops in by pressing A.
func _reserved_slots() -> Array:
	var slots: Array = []
	if players.size() > 1 and not players[1].remote:
		slots.append(players[1])
	if builder.flat:
		slots.append(builder)
	return slots


func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	var slots := _reserved_slots()
	for p in players:
		p.joy = -1
	for i in slots.size():
		slots[i].joy = pads[i] if pads.size() > i else -1
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


## Which player (index) a controller belongs to, or -1.
func pad_owner(device: int) -> int:
	for p in players:
		if p.joy == device:
			return p.index
	return -1


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or players.is_empty():
		return
	if not connected:
		var who := pad_owner(device)
		if who < 0:
			return
		var p = players[who]
		p.joy = -1
		print("Joypad %d disconnected (P%d)" % [device, who + 1])
		if who == 0:
			return
		p.set_meta("lost_pad", device)
		if p.key_set < 0 and p.active:
			p.set_meta("rejoin", true)
			request_leave(who)  # no keyboard to fall back on: the runner leaves until it's back
		return
	if pad_owner(device) >= 0:
		return
	print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
	# The same controller coming back: give it to its runner again (and rejoin them).
	for r in runners():
		if r.joy < 0 and int(r.get_meta("lost_pad", -1)) == device:
			r.joy = device
			r.remove_meta("lost_pad")
			if r.get_meta("rejoin", false):
				r.remove_meta("rejoin")
				request_join(r.index)
			return
	for p in _reserved_slots():
		if p.joy < 0:
			p.joy = device
			return
	# Otherwise it's a spare: pressing A on it joins the next free runner (see _input).


## Drop-in: A on a controller nobody owns yet claims the next free runner (Start is the pause menu).
func _input(event: InputEvent) -> void:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or not ready_to_play or net == null or net.mode == "host":
		return
	if b.button_index != JOY_BUTTON_A:
		return
	if pad_owner(b.device) >= 0 or get_tree().paused:
		return
	var r = _free_runner()
	if r == null:
		_show_center("All 6 runner spots are taken!", 1.5, false)
		return
	r.joy = b.device
	r.claimed = true
	r.remove_meta("rejoin")
	r.remove_meta("lost_pad")
	print("Joypad %d drops in as P%d" % [b.device, r.index + 1])
	request_join(r.index)
	get_viewport().set_input_as_handled()


func _free_runner():
	for r in runners():
		if not r.remote and not r.active and r.joy < 0 and not r.has_meta("lost_pad") and not r.has_meta("want_join"):
			return r
	for r in runners():
		if not r.remote and not r.active and r.joy < 0 and not r.has_meta("want_join"):
			return r
	return null


func request_join(i: int) -> void:
	if i < 1 or i >= players.size():
		return
	var r = players[i]
	if net.mode == "client":
		r.set_meta("want_join", true)
		join_t = 0.0
		_check_join(0.0)
	else:
		on_p2_action("join", [], i)


func request_leave(i: int) -> void:
	if i < 1 or i >= players.size():
		return
	players[i].remove_meta("want_join")
	if net.mode == "client":
		net.send_action("leave", [], i)
	else:
		on_p2_action("leave", [], i)


## TV: keep asking the host until our new runners show up as active in the snapshots.
func _check_join(delta: float) -> void:
	join_t -= delta
	if join_t > 0.0:
		return
	for r in runners():
		if not r.has_meta("want_join"):
			continue
		if r.active:
			r.remove_meta("want_join")
			continue
		join_t = 1.0
		net.send_action("join", [], r.index)


## Tests: join TV player `index` (1..6) as if a new controller had pressed A.
func debug_join(index: int) -> void:
	_ensure_runners(net.mode)
	if index < 1 or index >= players.size() or players[index].remote:
		return
	players[index].claimed = true
	request_join(index)


func on_player_activity_changed(p) -> void:
	if p.active and not p.remote:
		_ensure_view(p)
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active
	if p.active:
		p.remove_meta("want_join")
	views_dirty = true


# --- Effects ---------------------------------------------------------------------------

func _ensure_sfx() -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
		for k in SOUNDS:
			sfx.add_sound(k, SOUNDS[k])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	local_sound(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Sound on this machine only (your own jump, the builder's tray clicks).
func local_sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_ensure_sfx()
	sfx.play(sound_name, volume_db, pitch)


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.12) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := Art.box(Vector3.ONE * size)
	m.material = Art.mat(color, 1.5)
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.1).timeout.connect(p.queue_free)
	if net:
		net.event("burst", [pos, color, amount, size])


## Big colourful confetti shower.
func confetti(pos: Vector3, amount: int = 90, power: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 2.8
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 6.0 * power
	p.initial_velocity_max = 12.0 * power
	p.gravity = Vector3(0, -6.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	g.colors = PackedColorArray([Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.2), Color(0.35, 0.9, 0.4),
		Color(0.3, 0.7, 1.0), Color(0.85, 0.45, 1.0)])
	p.color_initial_ramp = g
	var m := Art.box(Vector3(0.2, 0.02, 0.13))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(3.4).timeout.connect(p.queue_free)
	if net:
		net.event("confetti", [pos, amount, power])


## Floating text for the TV players (billboarded, so it's hidden from the VR camera).
func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.layers = Art.TV_LAYER
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.2, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.7)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


# --- Blocks (host) -----------------------------------------------------------------------

func _reset_budget() -> void:
	var d: Dictionary = Levels.get_level(level)
	var b: Dictionary = d.budget
	budget = {}
	for k in Art.KINDS:
		budget[k] = int(b.get(k, 0))
	if active_runner_count() >= 4 and budget["plank"] > 0:
		budget["plank"] += 1  # a big party gets a spare plank


## Builder takes a block out of the tray (it's now in their hand).
func take(kind: String) -> bool:
	if net.mode == "client" or state != "play":
		return false
	if int(budget.get(kind, 0)) <= 0:
		return false
	budget[kind] = int(budget[kind]) - 1
	return true


## A block from the builder's hand goes back to the tray.
func refund(kind: String, at: Vector3) -> void:
	if not budget.has(kind):
		return
	budget[kind] = int(budget[kind]) + 1
	sound("poof", -8.0, 1.2)
	burst(at, Art.kind_color(kind), 6, 0.08)


## Is this cell free for a block (course and runners)?
func can_place(kind: String, c: Vector3i) -> bool:
	if not course.can_place(kind, c):
		return false
	var lo := float(c.y) + (0.7 if kind == "plank" else 0.0)
	var hi := float(c.y) + 1.0
	for r in runners():
		if not r.active:
			continue
		var p: Vector3 = r.global_position
		if p.x + 0.25 > c.x and p.x - 0.25 < c.x + 1 and p.z + 0.25 > c.z and p.z - 0.25 < c.z + 1 \
				and p.y + 0.9 > lo and p.y < hi:
			return false
	return true


## The builder sets a block from their hand into the course.
func put(kind: String, c: Vector3i, rot: int) -> void:
	if not can_place(kind, c):
		refund(kind, Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5))
		return
	course.add_block(kind, c, rot)
	sound("place", -2.0, randf_range(0.9, 1.15))
	burst(Vector3(c.x + 0.5, c.y + 1.0, c.z + 0.5), Art.kind_color(kind), 10, 0.1)


## Take a placed block back into the hand. Returns its kind ("" if none).
func pick_up(c: Vector3i) -> String:
	if net.mode == "client" or state != "play":
		return ""
	var kind: String = course.block_kind(c)
	if kind == "":
		return ""
	course.remove_block(c)
	sound("pickup", -8.0, 0.9)
	return kind


# --- Game flow (host) ---------------------------------------------------------------------

func _start_level(i: int) -> void:
	level = clampi(i, 0, Levels.count() - 1)
	level_seq += 1
	var d: Dictionary = Levels.get_level(level)
	course.load_level(level)
	if builder != null:
		builder.held_kind = ""
	_reset_budget()
	var party := maxi(0, active_runner_count() - 2)
	time_left = float(d.time) * (1.0 + 0.08 * party)
	level_time = 0.0
	water_y = course.water_level(0.0)
	tick_last = -1
	state = "play"
	state_t = 0.0
	for r in runners():
		r.reset_to_start()
	_show_center("LEVEL %d: %s\n%s" % [level + 1, d.name, d.tip], 4.5)
	sound("wave", -2.0)
	print("Level %d (%s) started" % [level + 1, d.name])
	if level >= 2:
		create_tween().tween_property(help_label, "modulate:a", 0.0, 1.0)


## Trigger (VR), A / Enter (TV), click: start, next level, try again.
func confirm() -> void:
	if net.mode == "client":
		net.send_action("confirm", [], 1)
		return
	if state_t < 1.2:
		return
	match state:
		"intro":
			if net.mode == "host" and not net.connected:
				return
			_start_level(0)
		"clear":
			_start_level(level + 1)
		"failed":
			_start_level(level)
		"won":
			score = 0
			levels_cleared = 0
			_start_level(0)


func runner_at_flag(r) -> void:
	if net.mode == "client":
		net.send_action("flag", [level_seq], r.index)
	else:
		_mark_finished(r.index)


func _mark_finished(i: int) -> void:
	if state != "play" or i < 1 or i >= players.size():
		return
	var r = players[i]
	if r.finished or not r.active:
		return
	r.finished = true
	r.flag_sent = true
	sound("flag", -2.0, 1.0 + 0.08 * i)
	popup(course.flag_pos + Vector3.UP * 2.6, "P%d MADE IT!" % (i + 1), r.color.lightened(0.3))
	confetti(course.flag_pos + Vector3.UP * 0.5, 40, 0.7)
	print("P%d reached the flag" % (i + 1))
	var waiting := 0
	for o in runners():
		if o.active and not o.finished:
			waiting += 1
	if waiting > 0:
		_show_center("P%d MADE IT!  %d to go" % [i + 1, waiting], 1.6)


## A runner fell / got burnt / splashed / bounced (reported by whichever machine drives it).
func runner_fx(i: int, kind: String, pos: Vector3) -> void:
	if net.mode == "client":
		net.send_action("fx", [kind, pos], i)
		return
	if i < 1 or i >= players.size():
		return
	var r = players[i]
	match kind:
		"boing":
			sound("boing", -3.0, randf_range(0.95, 1.1))
			burst(pos + Vector3.UP * 0.3, Art.kind_color("spring"), 8, 0.08)
		"lava":
			sound("sizzle", -3.0)
			burst(pos + Vector3.UP * 0.2, Color(1.0, 0.5, 0.1), 18, 0.12)
			popup(pos + Vector3.UP * 1.4, "HOT HOT HOT!", Color(1.0, 0.6, 0.2))
		"water":
			sound("splash", -3.0)
			burst(Vector3(pos.x, water_y + 0.1, pos.z), Color(0.5, 0.8, 1.0), 18, 0.12)
			popup(Vector3(pos.x, water_y + 1.4, pos.z), "SPLASH!", Color(0.6, 0.85, 1.0))
		"fall":
			sound("fall", -4.0, 1.0 + 0.05 * i)
			popup(Vector3(pos.x, -2.0, pos.z), "WHOOOPS!", r.color.lightened(0.3))


func _level_clear() -> void:
	state = "clear"
	state_t = 0.0
	levels_cleared = level + 1
	var left := 0
	for k in budget:
		left += int(budget[k])
	var bonus := 100 + 2 * int(maxf(time_left, 0.0)) + 10 * left
	score += bonus
	sound("fanfare", 0.0)
	sound("clear", -2.0, 1.2)
	var fp: Vector3 = course.flag_pos
	confetti(fp + Vector3.UP * 0.5, 160, 1.2)
	for x in [-8.0, -3.0, 2.0]:
		var xx: float = x
		confetti(Vector3(xx, 1.0, 0.5), 70, 1.0)
	if builder != null and builder.vr:
		var cam: Vector3 = builder.xr_camera.global_position
		var fwd: Vector3 = -builder.xr_camera.global_basis.z
		fwd.y = 0.0
		confetti(cam + fwd.normalized() * 6.0 + Vector3.DOWN * 3.0, 120, 1.4)
	print("Level %d cleared: +%d (score %d)" % [level + 1, bonus, score])
	if level + 1 >= Levels.count():
		state = "won"
		var best := _save_best(score)
		_show_center("YOU BUILT IT ALL!\nEvery level cleared!\nScore %d   %s\n\nPull the trigger / press A to play again" % [score, best], 0.0)
	else:
		_show_center("LEVEL %d CLEAR!\n+%d points  (%d blocks spare)\nScore %d\n\nPull the trigger / press A for the next level" % [level + 1, bonus, left, score], 0.0)


func _level_failed() -> void:
	state = "failed"
	state_t = 0.0
	sound("gameover", -2.0)
	print("Level %d failed: time's up" % (level + 1))
	_show_center("TIME'S UP!\nLevel %d: %s\nScore %d\n\nPull the trigger / press A to try again" % [level + 1, Levels.get_level(level).name, score], 0.0)


func _save_best(s: int) -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://block_builders.cfg")
	var best: int = cfg.get_value("best", "score", 0)
	if s > best:
		cfg.set_value("best", "score", s)
		cfg.save("user://block_builders.cfg")
		return "NEW BEST!"
	return "(best %d)" % best


# --- Main loop -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(level % 3)
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ensure_runners(net.mode)
	_layout_views()
	course.update_visuals(delta, level_time, water_y)
	_update_hud()
	_update_vr_text()
	_check_tv_confirm()
	if net.mode == "client":
		_check_join(delta)
		state_t += delta
		if state == "play":
			level_time += delta
		return
	state_t += delta
	match state:
		"intro":
			if net.mode == "host" and not net.connected:
				return
			if state_t > INTRO_TIME:
				_start_level(0)
		"play":
			level_time += delta
			time_left -= delta
			water_y = course.water_level(level_time)
			var secs := int(ceilf(time_left))
			if secs <= 10 and secs != tick_last and secs >= 0:
				tick_last = secs
				sound("tick", -4.0, 1.0 + (10 - secs) * 0.05)
			var act := 0
			var done := 0
			for r in runners():
				if r.active:
					act += 1
					if r.finished:
						done += 1
			if act > 0 and done == act:
				_level_clear()
			elif time_left <= 0.0:
				_level_failed()
		"clear":
			if state_t > CLEAR_TIME:
				_start_level(level + 1)


## A / Enter on the TV (or split screen): start, next level, try again.
func _check_tv_confirm() -> void:
	if state == "play":
		set_meta("confirm_was", true)
		return
	var down := Input.is_physical_key_pressed(KEY_ENTER)
	for r in runners():
		if r.active and not r.remote and r.jump_held():
			down = true
	if down and not get_meta("confirm_was", true):
		confirm()
	set_meta("confirm_was", down)


# --- Networking ----------------------------------------------------------------------------

func on_client_joined() -> void:
	_show_center("THE RUNNERS HAVE ARRIVED!", 1.5)
	if state == "intro":
		state_t = 0.0
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			if state == "intro":
				_show_intro())


func on_client_left() -> void:
	_show_center("The runners left - waiting for them to come back…", 0.0)
	for r in runners():
		if r.index >= 2 and r.active:
			r.set_active(false)
			on_player_activity_changed(r)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index < 1 or index >= players.size():
		return
	var r = players[index]
	match action:
		"join":
			if not r.active:
				r.set_active(true)
				r.reset_to_start()
				if state == "play" and level_time > 0.0:
					r.finished = false
				on_player_activity_changed(r)
				popup(course.start + Vector3.UP * 2.0, "P%d JOINED!" % (index + 1), r.color)
				_show_center("PLAYER %d JOINED!" % (index + 1), 1.5)
				sound("revive", -4.0, 1.2)
				print("Player %d joined the game" % (index + 1))
		"leave":
			if r.active:
				r.set_active(false)
				r.finished = false
				on_player_activity_changed(r)
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
				print("Player %d left the game" % (index + 1))
		"flag":
			if args.size() > 0 and int(args[0]) == level_seq:
				_mark_finished(index)
		"fx":
			if args.size() >= 2:
				runner_fx(index, str(args[0]), args[1])
		"confirm", "restart":
			confirm()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A runner opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	if paused and vr_center != null:
		VrText.snap(vr_center)
	_update_vr_text()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nPull the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var b: Array = []
	for k in Art.KINDS:
		b.append(int(budget.get(k, 0)))
	var rs: Array = []
	for r in runners():
		rs.append(r.net_state())
	return [level, level_seq, state, state_t, level_time, time_left, score, water_y, b, course.pack_blocks(),
		builder.net_state(), rs]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 12:
		return
	synced = true
	var seq: int = s[1]
	if seq != level_seq:
		level = s[0]
		level_seq = seq
		course.load_level(level)
		for r in runners():
			if not r.remote:
				r.reset_to_start()
	state = s[2]
	state_t = s[3]
	level_time = s[4]
	time_left = s[5]
	score = s[6]
	water_y = s[7]
	var b: Array = s[8]
	for i in mini(b.size(), Art.KINDS.size()):
		budget[Art.KINDS[i]] = int(b[i])
	course.apply_packed(s[9])
	builder.apply_net_state(s[10])
	var rs: Array = s[11]
	for i in mini(rs.size(), MAX_RUNNERS):
		if i + 1 < players.size():
			players[i + 1].apply_net_state(rs[i])


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			local_sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3])
		"confetti":
			confetti(args[0], args[1], args[2])
		"popup":
			popup(args[0], args[1], args[2])
		"center":
			_show_center(args[0], args[1], false)
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The Builder paused the game")


# --- HUD -------------------------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.12, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(28)
	info_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 12
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(52)
	center_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.9))
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -70
	help_label.offset_bottom = -10
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


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


func _status_text() -> String:
	var d: Dictionary = Levels.get_level(level)
	var t := int(ceilf(maxf(time_left, 0.0)))
	var act := 0
	var done := 0
	for r in runners():
		if r.active:
			act += 1
			if r.finished:
				done += 1
	if state == "intro":
		return "BLOCK BUILDERS"
	return "LEVEL %d/%d  %s   TIME %d:%02d   FLAG %d/%d   SCORE %d" % [level + 1, Levels.count(), d.name, t / 60, t % 60, done, act, score]


func _tray_text() -> String:
	var parts: Array[String] = []
	for i in Art.KINDS.size():
		var n: int = budget.get(Art.KINDS[i], 0)
		if n > 0 or Levels.get_level(level).budget.has(Art.KINDS[i]):
			parts.append("%s %d" % [Art.KIND_NAMES[i], n])
	return "BLOCKS:  " + "   ".join(parts)


func _update_hud() -> void:
	if level >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the Builder…"
		return
	info_label.text = ""
	var status := _status_text()
	var tray := _tray_text()
	for r in runners():
		if r.hud_label != null and r.active:
			r.hud_label.text = "P%d   %s\n%s" % [r.index + 1, status, tray]
	if builder != null and builder.flat and builder.hud_label != null:
		var sel_kind: String = Art.KINDS[builder.sel]
		builder.hud_label.text = "BUILDER   %s\n%s     holding: %s  (Q/E pick, wheel height, R turn)" % [status, tray,
			Art.KIND_NAMES[builder.sel] if int(budget.get(sel_kind, 0)) > 0 else "nothing - pick another block"]
		builder.hint_label.text = ""


## VR can't show 2D overlays: the centre banner and a status line float in the world (VrText).
func _update_vr_text() -> void:
	if builder == null or not builder.vr:
		return
	var S := BuilderScript.S
	if vr_center == null:
		vr_center = _make_vr_label(48, Color(1.0, 1.0, 0.9))
		vr_center.width = 1000.0
	if vr_info == null:
		vr_info = _make_vr_label(30, Color(1.0, 0.92, 0.6))
		vr_info.width = 1600.0
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = center_label.modulate.a
	vr_center.visible = center_label.text != "" and center_label.modulate.a > 0.01
	var info := _status_text() + "\n" + _tray_text()
	if net.mode == "host" and not net.connected:
		info = "Waiting for the runners to join…"
	vr_info.text = info
	VrText.follow(vr_center, builder.xr_camera, self, 0.02 * S, 1.8 * S)
	VrText.follow(vr_info, builder.xr_camera, self, 0.62 * S, 1.8 * S)


func _make_vr_label(font: int, color: Color) -> Label3D:
	var S := BuilderScript.S
	var l := Label3D.new()
	l.font_size = font
	l.outline_size = 26
	l.outline_modulate = Color.BLACK
	l.modulate = color
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.pixel_size = 0.0024 * S
	l.layers = 1
	add_child(l)
	return l


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # XR world scale is global: don't leave other games giant-sized
	for key in Engine.get_meta_list():
		if str(key).begins_with("bb_"):
			Engine.remove_meta(key)  # cached meshes: rebuilt next time (and not leaked at exit)
