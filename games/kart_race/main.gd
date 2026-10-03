extends Node3D
## KART RACE - friendly kart racing for the whole living room.
## The VR player (players[0]) sits in a kart and drives it with a steering wheel held in both hands
## (right trigger = go, A = item / boost). TV players (1-6) drive their own karts in split screen
## chase cams. Colourful looping tracks with ramps, boost arrows and item boxes (banana slip, bubble
## shield, speed mushroom); 3 laps; rubber-band catch-up keeps everyone close; bumps never wreck.
## CPU buddies fill the grid up to 4 karts. Modes, networking and drop-in join follow
## docs/GAME_DEV_GUIDE.md and games/marble_maze.

const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const TrackScript := preload("res://games/kart_race/track.gd")
const KartScript := preload("res://games/kart_race/kart.gd")
const CockpitScript := preload("res://games/kart_race/cockpit.gd")
const JoinListenerScript := preload("res://games/kart_race/join_listener.gd")

const MAX_PLAYERS := 7  # VR player + 6 TV karts
const MAX_LOCAL_VIEWS := 6
const MAX_CPU := 3
const GRID_FILL := 4  # CPU buddies fill the grid up to this many karts
const CPU_BASE := 10  # CPU karts' index
const PAD_LEAVE_TIME := 20.0
const FIRST_INTRO_TIME := 9.0
const INTRO_TIME := 4.0
const FINISH_GRACE := 25.0
const RACE_TIMEOUT := 420.0
const SOLO_WAIT := 8.0  # host: start with CPU buddies if no TV joins
const SHIELD_TIME := 8.0
const MUSHROOM_TIME := 1.8
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.75, 0.2), Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0),
	Color(0.35, 0.9, 0.35), Color(0.85, 0.4, 1.0), Color(1.0, 0.55, 0.15), Color(0.3, 0.95, 0.9)]
const CPU_NAMES: Array[String] = ["BUNNY", "DINO", "ROBO"]
const CPU_COLORS: Array[Color] = [Color(1.0, 0.7, 0.85), Color(0.55, 0.8, 0.3), Color(0.7, 0.75, 0.85)]
const ITEM_NAMES := {"banana": "BANANA", "shield": "BUBBLE SHIELD", "mushroom": "SPEED MUSHROOM"}
const SOUNDS := {
	"box": [0.22, 600.0, 1500.0, 0.3, "square", 0.0],
	"boost": [0.45, 200.0, 900.0, 0.3, "saw", 0.3],
	"slip": [0.6, 900.0, 200.0, 0.35, "sine", 0.0],
	"bump": [0.12, 180.0, 90.0, 0.4, "square", 0.3],
	"wall": [0.1, 140.0, 70.0, 0.35, "saw", 0.6],
	"land": [0.12, 120.0, 60.0, 0.35, "sine", 0.4],
	"count": [0.18, 440.0, 440.0, 0.3, "square", 0.0],
	"go": [0.5, 880.0, 880.0, 0.35, "square", 0.0],
	"lap": [0.4, 660.0, 1320.0, 0.3, "tri", 0.0],
	"finish": [1.0, 523.0, 1568.0, 0.4, "tri", 0.0],
	"pop": [0.15, 1200.0, 300.0, 0.3, "sine", 0.4],
	"shield": [0.4, 300.0, 1200.0, 0.3, "sine", 0.0],
	"drop": [0.15, 500.0, 250.0, 0.3, "tri", 0.0],
}

var players: Array = []
var cpus: Array = []
var karts: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var track: TrackScript
var cockpit
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var join_listener: Node
var joy_owner := {}
var views_root: Control
var last_view_area := Vector2.ZERO
var mats := {}
var meshes := {}
var env: Environment
var sun: DirectionalLight3D

var state := "wait"  # wait, countdown, race, results
var state_t := 0.0
var race_t := 0.0
var track_i := 0
var round_n := 0
var laps := 3
var finish_frac := 1.0  # tests: finish part-way round the last lap
var intro_override := -1.0
var first_human_finish := -1.0
var all_done_t := -1.0
var last_count := -1
var cont_was := false
var bananas: Array = []  # [position, age, owner index]
var banana_nodes: Array[Node3D] = []
var synced := false
var solo_t := 0.0
var results_text := ""

var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D


func _ready() -> void:
	randomize()
	_build_world()
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
		_show_center("Connecting to the VR player…", 0.0, false)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	track.build(0)
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		state = "wait"
		var p: Array = track.grid_point(0)
		players[0].place_at(p[0], p[1], p[3])
		_show_center("KART RACE\nWaiting for the TV players… (warm up: drive around!)", 0.0)
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED", 1.5, false)
	else:
		_start_race(0)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0


# --- Helpers ----------------------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mats[key] = m
	return m


func bubble_material() -> StandardMaterial3D:
	if mats.has("bubble"):
		return mats["bubble"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.9, 1.0, 0.3)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.4, 0.8, 1.0)
	m.emission_energy_multiplier = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["bubble"] = m
	return m


func sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.4f" % r
	if meshes.has(key):
		return meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 7
	meshes[key] = m
	return m


func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if meshes.has(key):
		return meshes[key]
	var m := BoxMesh.new()
	m.size = size
	meshes[key] = m
	return m


func cyl_mesh(r_top: float, r_bottom: float, h: float, seg: int) -> CylinderMesh:
	var key := "c%.3f/%.3f/%.3f/%d" % [r_top, r_bottom, h, seg]
	if meshes.has(key):
		return meshes[key]
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	meshes[key] = m
	return m


func capsule_mesh(r: float, h: float) -> CapsuleMesh:
	var key := "cap%.3f/%.3f" % [r, h]
	if meshes.has(key):
		return meshes[key]
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	meshes[key] = m
	return m


func torus_mesh(inner: float, outer: float) -> TorusMesh:
	var key := "t%.3f/%.3f" % [inner, outer]
	if meshes.has(key):
		return meshes[key]
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 20
	m.ring_segments = 6
	meshes[key] = m
	return m


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0, broadcast: bool = false) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
		for k in SOUNDS:
			var d: Array = SOUNDS[k]
			sfx.add_sound(k, d)
	sfx.play(sound_name, volume_db, pitch)
	if broadcast and net != null:
		net.event("sound", [sound_name, volume_db, pitch])


## Sound for one kart: played where that kart's driver is (host speakers or the TV).
func kart_sound(k, sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if k.remote:
		net.event("sound", [sound_name, volume_db, pitch])
	elif not k.cpu:
		sound(sound_name, volume_db, pitch)


func burst(pos: Vector3, color: Color, amount: int = 14, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = box_mesh(Vector3.ONE * 0.18)
	p.material_override = make_material(color, 1.5)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	if broadcast and net != null:
		net.event("burst", [pos, color, amount])


func rumble(k, amp: float, dur: float) -> void:
	if k.cockpit != null:
		k.cockpit.haptic(amp, dur)
	elif k.joy >= 0 and k.is_local():
		Input.start_joy_vibration(k.joy, amp * 0.6, amp, dur)


static func ordinal(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
	return "%dth" % n


# --- World -------------------------------------------------------------------------------

func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.8, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.92)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	track = TrackScript.new()
	track.name = "Track"
	track.main = self
	add_child(track)


func _apply_track_look() -> void:
	var sky: Color = track.info["sky"]
	env.background_color = sky
	var night := sky.v < 0.5
	env.ambient_light_energy = 0.9 if night else 0.7
	env.ambient_light_color = Color(0.7, 0.75, 1.0) if night else Color(1.0, 0.97, 0.92)
	sun.light_energy = 0.55 if night else 1.0


# --- Players and views ---------------------------------------------------------------------

func _new_kart(i: int, col: Color, nm: String) -> KartScript:
	var k := KartScript.new()
	k.index = i
	k.main = self
	k.color = col
	k.kart_name = nm
	return k


func _build_players(mode: String) -> void:
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(0, top + 1):
		var k := _new_kart(i, PLAYER_COLORS[i % PLAYER_COLORS.size()], "P%d" % (i + 1))
		if i == 0:
			k.ghost = mode == "client"
			k.key_set = KartScript.KEYS_WASD
			k.mouse_look = mode != "client"
		else:
			k.remote = mode == "host"
			if i == 1 and mode != "host":
				k.key_set = KartScript.KEYS_BOTH if mode == "client" else KartScript.KEYS_ARROWS
				k.mouse_look = mode == "client"
		add_child(k)
		players.append(k)
		k.set_active(i == 0 or (i == 1 and mode == "local"))
	for j in MAX_CPU:
		var c := _new_kart(CPU_BASE + j, CPU_COLORS[j], CPU_NAMES[j])
		c.cpu = true
		c.ghost = mode == "client"
		c.cpu_skill = 0.9 + 0.03 * j
		add_child(c)
		cpus.append(c)
		c.set_active(false)
	karts = players + cpus


func kart_by_index(i: int):
	if i >= CPU_BASE:
		return cpus[i - CPU_BASE] if i - CPU_BASE < cpus.size() else null
	return players[i] if i >= 0 and i < players.size() else null


func _apply_vr_performance() -> void:
	env.ssao_enabled = false
	env.fog_enabled = false
	env.glow_enabled = false
	sun.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 drives with the steering wheel in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
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
		var k = players[0]
		k.vr = true
		k.hand_l = left
		k.hand_r = right
		k.mouse_look = false
		cockpit = CockpitScript.new()
		cockpit.main = self
		add_child(cockpit)
		cockpit.setup(k, origin, cam, left, right)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: %s" % ("TV karts" if mode == "client" else "split screen, P1 drives the VR kart flat"))
	_ensure_views_root()
	for p in players:
		if p.is_local() and not p.vr and p.active:
			_ensure_view(p)
	_layout_views()


## Low-res copy of the VR view for gdev (group gdev_capture), refreshed at 30 fps.
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
	cam.near = 0.03
	cam.far = 600.0
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


## Test hook: drive kart 0 through the VR cockpit with fake hands (no headset needed).
func debug_fake_vr():
	if cockpit != null or players.is_empty() or net.mode == "client":
		return cockpit
	cockpit = CockpitScript.new()
	cockpit.main = self
	add_child(cockpit)
	cockpit.setup(players[0], null, null, null, null)
	print("Fake VR cockpit on P1")
	return cockpit


## Test hook: shorter races (laps, and optionally finish part-way round the last lap).
func debug_fast(n_laps: int, frac: float = 1.0) -> void:
	laps = n_laps
	intro_override = 3.0
	finish_frac = clampf(frac, 0.1, 1.0)


func _ensure_views_root() -> void:
	if views_root != null and is_instance_valid(views_root):
		return
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.2)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	views_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One split-screen view (SubViewport + chase camera + HUD) per local kart, created when it joins.
func _ensure_view(p) -> void:
	if p.has_meta("view") or not p.is_local() or p.vr:
		return
	_ensure_views_root()
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	views_root.add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	container.add_child(vp)
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 600.0
	cam.fov = 70.0
	vp.add_child(cam)
	cam.current = true
	p.camera = cam
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.hud = hud
	var tagc := ColorRect.new()
	tagc.color = p.color
	tagc.size = Vector2(16, 16)
	tagc.position = Vector2(14, 22)
	hud.add_child(tagc)
	p.hud_label = _make_label(28)
	hud.add_child(p.hud_label)
	p.hud_label.position = Vector2(40, 10)
	p.place_label = _make_label(72)
	hud.add_child(p.place_label)
	p.place_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	p.place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.item_label = _make_label(28)
	hud.add_child(p.item_label)
	p.item_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	p.hint_label = _make_label(40)
	hud.add_child(p.hint_label)
	p.hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.hint_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.55)
	bar_bg.name = "BarBg"
	hud.add_child(bar_bg)
	p.boost_fill = ColorRect.new()
	p.boost_fill.color = Color(0.3, 0.8, 1.0)
	bar_bg.add_child(p.boost_fill)


## TV grid: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2; smaller views render at lower resolution.
func _layout_views() -> void:
	if views_root == null or not is_instance_valid(views_root):
		return
	var shown: Array = []
	for p in players:
		if not p.has_meta("view"):
			continue
		var c: SubViewportContainer = p.get_meta("view")
		c.visible = p.active
		if p.active:
			shown.append(p)
	var n := shown.size()
	var area := views_root.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
	last_view_area = views_root.size
	if n == 0:
		return
	var cols := 1
	var rows := 1
	if n == 2:
		cols = 2
	elif n > 2 and n <= 4:
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
		var row := k / cols
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2(col * (cell.x + gap), row * (cell.y + gap))
		c.size = cell
		var vp := c.get_child(0) as SubViewport
		if vp != null:
			vp.scaling_3d_scale = res_scale
			vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
		var ui := clampf(minf(cell.x / 940.0, cell.y / 900.0), 0.5, 1.0)
		p.hud_label.add_theme_font_size_override("font_size", int(30.0 * ui))
		p.place_label.add_theme_font_size_override("font_size", int(80.0 * ui))
		p.place_label.position = Vector2(cell.x - 260.0 * ui - 16.0, 6.0)
		p.place_label.size = Vector2(260.0 * ui, 100.0 * ui)
		p.item_label.add_theme_font_size_override("font_size", int(30.0 * ui))
		p.item_label.position = Vector2(16.0, cell.y - 110.0 * ui)
		p.hint_label.add_theme_font_size_override("font_size", int(44.0 * ui))
		p.hint_label.size = Vector2(cell.x, 120.0 * ui)
		p.hint_label.position = Vector2(0.0, cell.y * 0.3)
		var bar_bg: ColorRect = p.hud.get_node("BarBg")
		bar_bg.size = Vector2(260.0 * ui, 22.0 * ui)
		bar_bg.position = Vector2(16.0, cell.y - 44.0 * ui)
		p.boost_fill.size = Vector2(0, 22.0 * ui)
	if players.size() > 0 and not players[0].vr:
		sun.shadow_enabled = n <= 2


# --- Controllers and drop-in join ------------------------------------------------------

func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	joy_owner.clear()
	if net.mode == "host":
		if not players[0].vr and pads.size() > 0:
			players[0].joy = pads[0]
		return
	players[1].joy = pads[0] if pads.size() > 0 else -1
	if net.mode == "local":
		players[0].joy = pads[1] if pads.size() > 1 else -1
	for p in players:
		if p.joy >= 0 and p.is_local():
			joy_owner[p.joy] = p.index
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or net.mode == "host":
		return
	if connected:
		print("Joypad %d connected" % device)
		if joy_owner.has(device):
			return
		var pick = null
		for p in players:
			if p.is_local() and p.joy < 0 and int(p.get_meta("last_joy", -2)) == device:
				pick = p
				break
		if pick == null and players[1].joy < 0:
			pick = players[1]
		if pick == null:
			return  # unassigned: press A to join
		pick.joy = device
		joy_owner[device] = pick.index
		pick.pad_lost_t = -1.0
		if not pick.active and pick.has_meta("left_by_pad"):
			_request_join(pick)
	else:
		print("Joypad %d disconnected" % device)
		if not joy_owner.has(device):
			return
		var idx: int = joy_owner[device]
		joy_owner.erase(device)
		var p = players[idx]
		if p.joy != device:
			return
		p.joy = -1
		p.set_meta("last_joy", device)
		if idx >= 2 and p.active:
			p.pad_lost_t = 0.0
			_show_center("P%d: controller disconnected" % (idx + 1), 2.0, false)


## Called by the join listener: A on a controller nobody owns joins a kart (Start = pause menu).
func handle_join_input(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed or pad.button_index != JOY_BUTTON_A:
		return false
	if not ready_to_play or net.mode == "host" or get_tree().paused:
		return false
	var device := pad.device
	if joy_owner.has(device):
		var idx: int = joy_owner[device]
		if idx > 0 and not players[idx].active and players[idx].is_local():
			_request_join(players[idx])
			return true
		return false
	return _join_slot(device) != null


func _next_free_index() -> int:
	for i in range(1, players.size()):
		var p = players[i]
		if not p.is_local() or p.active or p.has_meta("want_join") or p.joy >= 0 or p.pad_lost_t >= 0.0:
			continue
		return i
	return -1


func _join_slot(device: int):
	var idx := _next_free_index()
	if idx < 0:
		_show_center("All %d karts are taken!" % (players.size() - 1), 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


func _request_join(p) -> void:
	p.remove_meta("left_by_pad")
	p.pad_lost_t = -1.0
	if net.mode == "client":
		p.set_meta("want_join", true)
		join_t = 0.0
	elif not p.active:
		_activate(p)
	_save_party()


## A kart joins: onto the grid before the start, at the back of the pack during a race.
func _activate(p) -> void:
	p.set_active(true)
	p.reset_race()
	_place_new(p)
	_show_center("%s JOINS THE RACE!" % p.kart_name, 1.5)
	sound("box", -4.0, 0.8, true)
	on_player_activity_changed(p)


func _place_new(k) -> void:
	var L: float = track.length
	if state == "race":
		var lowest := INF
		for o in karts:
			if o != k and o.active and not o.finished:
				lowest = minf(lowest, o.total)
		if lowest == INF:
			lowest = 0.0
		var t := maxf(lowest - 10.0, -5.0)
		var p: Array = track.point_at(fposmod(t, L), randf_range(-2.5, 2.5))
		_teleport(k, p[0], p[1], t)
	else:
		var used := {}
		for o in karts:
			if o != k and o.active:
				used[o.grid_slot] = true
		var slot := 0
		while used.has(slot):
			slot += 1
		k.grid_slot = slot
		var g: Array = track.grid_point(slot)
		_teleport(k, g[0], g[1], g[3])
	k.hold_still = state == "countdown"


func _teleport(k, pos: Vector3, y: float, t: float) -> void:
	k.place_at(pos, y, t)
	if k.remote:
		net.event("teleport", [k.index, pos, y, t])


func _leave(p) -> void:
	p.pad_lost_t = -1.0
	p.remove_meta("want_join")
	p.set_meta("left_by_pad", true)
	if net.mode == "client":
		net.send_action("leave", [], p.index)
	elif p.active:
		p.set_active(false)
		on_player_activity_changed(p)
		_show_center("%s LEFT" % p.kart_name, 1.5)
	_save_party()


func _save_party() -> void:
	var party: Array = []
	for p in players:
		if p.index >= 2 and p.is_local() and (p.active or p.has_meta("want_join")) and not p.has_meta("left_by_pad"):
			party.append([p.index, p.joy])
	Engine.set_meta("kart_race_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("kart_race_party"):
		return
	var saved: Dictionary = Engine.get_meta("kart_race_party")
	if str(saved.get("mode", "")) != net.mode:
		return
	var pads := Input.get_connected_joypads()
	var party: Array = saved.get("party", [])
	for entry in party:
		var e: Array = entry
		var idx: int = e[0]
		var device: int = e[1]
		if idx >= players.size():
			continue
		if device >= 0 and (not pads.has(device) or joy_owner.has(device)):
			continue
		var p = players[idx]
		if p.active or not p.is_local():
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


## Test hook: join a kart without a controller (index -1: the next free seat).
func debug_join(index: int = -1):
	if not ready_to_play or net.mode == "host":
		return null
	if index < 0:
		return _join_slot(-1)
	var p = players[index]
	_request_join(p)
	return p


var join_t := 0.0
func _check_join(delta: float) -> void:
	join_t -= delta
	if join_t > 0.0:
		return
	for p in players:
		if not p.has_meta("want_join") or not p.is_local():
			continue
		if p.active:
			p.remove_meta("want_join")
			continue
		join_t = 1.0
		net.send_action("join", [p.index], 1)


func on_player_activity_changed(p) -> void:
	if p.active and p.is_local():
		_ensure_view(p)
	if p.active:
		p.remove_meta("want_join")
	_layout_views()
	print("Player %d is now %s" % [p.index + 1, "racing" if p.active else "waiting"])


func has_local_arrow_keys() -> bool:
	for p in players:
		if p.index > 0 and p.is_local() and p.active and p.key_set != KartScript.NO_KEYS:
			return true
	return false


func human_count() -> int:
	var n := 0
	for p in players:
		if p.active:
			n += 1
	return n


func racer_count() -> int:
	var n := 0
	for k in karts:
		if k.active:
			n += 1
	return n


# --- Race flow -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(track_i)
	_ensure_join_listener()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	var dt := minf(delta, 1.0 / 30.0)
	var cont := _continue_pressed()
	var cont_edge := cont and not cont_was
	cont_was = cont
	if net.mode == "client":
		_client_update(dt, cont_edge)
	else:
		_host_update(dt, cont_edge)
	track.update(dt, net.mode != "client")
	_update_bananas_visual()
	if cockpit != null:
		cockpit.place(dt)
	for p in players:
		if p.camera != null:
			p.update_camera(dt)
		if p.hud != null:
			_update_hud(p, dt)
	_update_vr_text(dt)


func _host_update(dt: float, cont_edge: bool) -> void:
	_update_lost_pads(dt)
	state_t += dt
	match state:
		"wait":
			if net.mode == "host":
				solo_t += dt
				if solo_t > SOLO_WAIT and not net.connected:
					print("No TV players yet: racing the CPU buddies (TV players can join any time)")
					_start_race(track_i)
		"countdown":
			var dur := _intro_time()
			var left := int(ceilf(dur - state_t))
			if left <= 3 and left >= 1 and left != last_count:
				last_count = left
				_show_center(str(left), 0.8)
				sound("count", 0.0, 1.0, true)
			if state_t >= dur:
				state = "race"
				state_t = 0.0
				race_t = 0.0
				for k in karts:
					k.hold_still = false
				_show_center("GO!", 0.8)
				sound("go", 0.0, 1.0, true)
				net.event("go", [])
		"race":
			race_t += dt
		"results":
			if (state_t > 2.0 and cont_edge) or state_t > 30.0:
				_start_race(track_i + 1)
	for k in karts:
		if k.is_sim():
			k.sim(dt)
		elif k.remote:
			k.follow_remote(dt)
	_bumps(dt)
	if state == "race":
		_authority(dt)
	_update_places()


func _client_update(dt: float, cont_edge: bool) -> void:
	_check_join(dt)
	_update_lost_pads(dt)
	state_t += dt
	if state == "race":
		race_t += dt
	for k in karts:
		if k.ghost:
			k.follow_ghost(dt)
		elif k.active:
			k.hold_still = state == "countdown"
			k.sim(dt)
	_bumps(dt)
	if cont_edge and state == "results" and state_t > 2.0:
		net.send_action("continue", [])


func _intro_time() -> float:
	if intro_override > 0.0:
		return intro_override
	return FIRST_INTRO_TIME if round_n <= 1 else INTRO_TIME


func _update_lost_pads(dt: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and p.is_local():
			p.pad_lost_t += dt
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


## A / Enter on this machine (VR: trigger or A) moves on from the results.
func _continue_pressed() -> bool:
	if state != "results":
		return false
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for p in players:
		if p.active and p.is_local() and p.joy >= 0 and Input.is_joy_button_pressed(p.joy, JOY_BUTTON_A):
			return true
	if cockpit != null and not cockpit.fake:
		if cockpit.hand_r.get_float("trigger") > 0.6 or cockpit.hand_r.is_button_pressed("ax_button"):
			return true
	return false


## Bot hook: same as pressing A on the results screen.
func debug_continue() -> void:
	if net.mode == "client":
		net.send_action("continue", [])
	else:
		_on_continue()


func _on_continue() -> void:
	if state == "results" and state_t > 1.0:
		_start_race(track_i + 1)


func finish_distance() -> float:
	return (laps - 1 + finish_frac) * track.length


func _start_race(ti: int) -> void:
	track_i = posmod(ti, TrackScript.count())
	round_n += 1
	track.build(track_i)
	_apply_track_look()
	bananas.clear()
	for i in track.box_t.size():
		track.box_t[i] = 0.0
	net.event("race", [track_i, laps, round_n, finish_frac])  # before the teleports: the TV builds the track first
	# CPU buddies fill the grid (fewer as more people play).
	var humans := human_count()
	var want_cpu := clampi(GRID_FILL - humans, 0, MAX_CPU)
	for j in cpus.size():
		cpus[j].set_active(j < want_cpu)
	# Humans at the front of the grid, the CPUs behind.
	var slot := 0
	for k in players + cpus:
		if not k.active:
			continue
		k.reset_race()
		k.grid_slot = slot
		var g: Array = track.grid_point(slot)
		_teleport(k, g[0], g[1], g[3])
		k.hold_still = true
		slot += 1
	state = "countdown"
	state_t = 0.0
	race_t = 0.0
	last_count = -1
	first_human_finish = -1.0
	all_done_t = -1.0
	solo_t = 0.0
	var title := "RACE %d: %s · %d LAP%s" % [round_n, TrackScript.track_name(track_i), laps, "S" if laps > 1 else ""]
	if round_n == 1:
		_show_center("KART RACE!  " + title + "\n" \
			+ "VR: hold the wheel with both hands and turn it · right trigger = GO · A = item / boost\n" \
			+ "TV: left stick steers · A = go · B = brake / reverse · X = item · Y = boost\n" \
			+ "Drive through ? boxes for items · glowing arrows = speed · ramps = big air!\n" \
			+ "More racers: press A on a spare controller", _intro_time() - 3.2)
	else:
		_show_center(title, _intro_time() - 3.2)
	print("Race %d on %s: %d karts (%d human), %d laps, %.0f m to go" % [round_n, TrackScript.track_name(track_i), racer_count(), humans, laps, finish_distance()])


## Host / local: laps, finishing, item boxes, bananas and the end of the race.
func _authority(dt: float) -> void:
	var L: float = track.length
	var goal := finish_distance()
	for k in karts:
		if not k.active or k.finished:
			continue
		var lap := clampi(int(floorf(k.total / L)) + 1, 1, laps)
		var shown: int = k.get_meta("lap", 1)
		if lap > shown:
			k.set_meta("lap", lap)
			if not k.cpu:
				notify(k, "FINAL LAP!" if lap == laps else "LAP %d!" % lap)
				kart_sound(k, "lap", -2.0, 1.0 + 0.1 * lap)
		elif lap < shown:
			k.set_meta("lap", lap)
		if k.total >= goal:
			_finish(k)
	_check_boxes()
	_check_bananas(dt)
	# End of the race.
	var humans_left := 0
	var humans := 0
	for p in players:
		if p.active:
			humans += 1
			if not p.finished:
				humans_left += 1
	if humans > 0 and humans_left == 0:
		if all_done_t < 0.0:
			all_done_t = race_t
		if race_t - all_done_t > 2.5:
			_results()
	elif first_human_finish >= 0.0 and race_t - first_human_finish > FINISH_GRACE:
		_results()
	elif race_t > RACE_TIMEOUT:
		_results()


func _finish(k) -> void:
	k.finished = true
	k.finish_time = race_t
	_update_places()
	if not k.cpu and first_human_finish < 0.0:
		first_human_finish = race_t
	var pl: int = k.place
	notify(k, "FINISHED %s!" % ordinal(pl).to_upper())
	burst(k.position + Vector3(0, 1.5, 0), k.color, 24)
	if not k.cpu:
		_show_center("%s FINISHES %s!" % [k.kart_name, ordinal(pl).to_upper()], 2.0)
		sound("finish", -2.0, 1.0 + 0.05 * (4 - mini(pl, 4)), true)
	print("%s finished %s in %.1f s" % [k.kart_name, ordinal(pl), race_t])


func _results() -> void:
	_update_places()
	state = "results"
	state_t = 0.0
	var order: Array = []
	for k in karts:
		if k.active:
			order.append(k)
	order.sort_custom(func(a, b) -> bool: return a.place < b.place)
	var lines: Array[String] = ["RACE OVER!"]
	for k in order:
		var t := "%.1f s" % k.finish_time if k.finished else "still racing"
		var star := "   WINNER!" if k.place == 1 else ""
		lines.append("%s   %s   %s%s" % [ordinal(k.place), k.kart_name, t, star])
	lines.append("")
	lines.append("Next: %s  ·  A / Enter (VR: trigger) to race again" % TrackScript.track_name(track_i + 1))
	results_text = "\n".join(lines)
	_show_center(results_text, 0.0)
	sound("finish", 0.0, 1.2, true)
	print("Results: " + " | ".join(lines.slice(1, lines.size() - 2)))


func _update_places() -> void:
	if net.mode == "client":
		return
	var racers: Array = []
	for k in karts:
		if k.active:
			racers.append(k)
	racers.sort_custom(func(a, b) -> bool:
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			return a.finish_time < b.finish_time
		return a.total > b.total)
	for i in racers.size():
		racers[i].place = i + 1


## Catch-up: karts behind the leader go a little faster; CPUs ease off when ahead of the kids.
func rubber(k) -> float:
	var lead := -INF
	var best_h := -INF
	var last_h := INF
	for o in karts:
		if not o.active or o.finished:
			continue
		lead = maxf(lead, o.total)
		if not o.cpu:
			best_h = maxf(best_h, o.total)
			last_h = minf(last_h, o.total)
	if lead == -INF:
		return 1.0
	var f := 1.0 + clampf((lead - k.total) / 70.0, 0.0, 1.0) * 0.22
	if k.cpu:
		f *= k.cpu_skill
		if best_h > -INF and k.total > best_h + 12.0:
			f *= 0.85
	elif best_h - last_h > 50.0 and k.total >= best_h - 1.0:
		f *= 0.95
	return f


# --- Items, bananas, bumps ------------------------------------------------------------------

func notify(k, text: String) -> void:
	if k.remote:
		net.event("notify", [k.index, text])
		return
	k.set_meta("hint", text)
	k.set_meta("hint_t", 2.2)


func _check_boxes() -> void:
	for i in track.boxes.size():
		if track.box_t[i] > 0.0:
			continue
		var bp: Vector3 = track.boxes[i]
		for k in karts:
			if k.active and k.position.distance_to(bp) < 1.9:
				track.box_t[i] = TrackScript.BOX_RESPAWN
				burst(bp, Color.from_hsv(randf(), 0.6, 1.0), 12)
				give_item(k)
				break


func give_item(k) -> void:
	k.charge = minf(1.0, k.charge + 0.2)
	if k.item != "":
		kart_sound(k, "box", -8.0, 0.8)
		return
	var n := maxi(1, racer_count() - 1)
	var behind := clampf(float(k.place - 1) / n, 0.0, 1.0)
	var w_m := 15.0 + 50.0 * behind
	var w_b := 45.0 - 30.0 * behind
	var w_s := 30.0
	var r := randf() * (w_m + w_b + w_s)
	var it := "mushroom" if r < w_m else ("banana" if r < w_m + w_b else "shield")
	k.item = it
	k.item_hold_t = 0.0
	kart_sound(k, "box", -2.0, 1.0)
	if not k.cpu:
		var how := "press A" if k.cockpit != null else "press X"
		notify(k, "%s! %s" % [ITEM_NAMES[it], how])


func use_item(k) -> void:
	var it: String = k.item
	if it == "":
		return
	if net.mode == "client" and k.is_local():
		if it == "mushroom":
			k.boost(MUSHROOM_TIME)
			sound("boost", -2.0)
		net.send_action("use", [it], k.index)
		k.item = ""
		return
	_do_use(k, it)


func _do_use(k, it: String) -> void:
	k.item = ""
	match it:
		"banana":
			var p: Vector3 = k.position - k.forward() * 2.6
			p.y = k.position.y
			bananas.append([p, 0.0, k.index])
			kart_sound(k, "drop", -2.0)
		"shield":
			k.shield_t = SHIELD_TIME
			kart_sound(k, "shield", -2.0)
			notify(k, "BUBBLE SHIELD ON!")
		"mushroom":
			if k.remote:
				net.event("boost", [k.index, MUSHROOM_TIME])
			else:
				k.boost(MUSHROOM_TIME)
			on_boost(k, "MUSHROOM ZOOM!")
	if k.has_meta("uses"):
		k.set_meta("uses", int(k.get_meta("uses")) + 1)
	else:
		k.set_meta("uses", 1)


func _check_bananas(dt: float) -> void:
	var i := 0
	while i < bananas.size():
		var b: Array = bananas[i]
		b[1] = float(b[1]) + dt
		var bp: Vector3 = b[0]
		var hit = null
		for k in karts:
			if not k.active or not k.on_ground:
				continue
			if int(b[2]) == k.index and float(b[1]) < 1.0:
				continue
			var d: Vector3 = k.position - bp
			if Vector2(d.x, d.z).length() < 1.4 and absf(d.y) < 1.5:
				hit = k
				break
		if hit != null or float(b[1]) > 90.0:
			bananas.remove_at(i)
			if hit != null:
				_banana_hit(hit, bp)
			continue
		i += 1
	while bananas.size() > 14:
		bananas.remove_at(0)


func _banana_hit(k, bp: Vector3) -> void:
	burst(bp + Vector3(0, 0.4, 0), Color(1.0, 0.9, 0.2), 12)
	if k.shield_t > 0.0:
		k.shield_t = 0.0
		kart_sound(k, "pop", 0.0)
		notify(k, "YOUR BUBBLE SAVED YOU!")
		return
	if k.remote:
		net.event("slip", [k.index])
		k.slip_t = 1.1
		k.spin_vis = TAU
	else:
		k.slip()
	kart_sound(k, "slip", -1.0)
	rumble(k, 0.6, 0.3)
	if not k.cpu:
		notify(k, "WHOOPS! BANANA!")


func _update_bananas_visual() -> void:
	while banana_nodes.size() < bananas.size():
		var b := Node3D.new()
		add_child(b)
		var m := MeshInstance3D.new()
		m.mesh = capsule_mesh(0.22, 0.9)
		m.material_override = make_material(Color(1.0, 0.88, 0.2), 0.2)
		m.rotation.z = 1.2
		m.position = Vector3(0, 0.3, 0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(m)
		var tip := MeshInstance3D.new()
		tip.mesh = sphere_mesh(0.09)
		tip.material_override = make_material(Color(0.35, 0.25, 0.1), 0.0)
		tip.position = Vector3(0.4, 0.5, 0)
		b.add_child(tip)
		banana_nodes.append(b)
	for i in banana_nodes.size():
		var n := banana_nodes[i]
		n.visible = i < bananas.size()
		if n.visible:
			var b: Array = bananas[i]
			n.position = b[0]
			n.rotation.y += get_process_delta_time() * 1.5


## Karts bump each other (each machine moves only the karts it simulates).
func _bumps(dt: float) -> void:
	for a in karts:
		if not a.active or not a.is_sim() or a.hold_still:
			continue
		for o in karts:
			if o == a or not o.active:
				continue
			var d: Vector3 = a.position - o.position
			if absf(d.y) > 1.4:
				continue
			d.y = 0.0
			var dist := d.length()
			if dist >= 1.8 or dist < 0.001:
				continue
			var nrm := d / dist
			var share := 0.5 if o.is_sim() else 1.0
			a.position += nrm * (1.8 - dist) * share
			var strength := 3.5
			if o.shield_t > 0.0 and a.shield_t <= 0.0:
				strength = 8.0
			if a.push_v.dot(nrm) < strength:
				a.push_v += nrm * (strength - maxf(0.0, a.push_v.dot(nrm)))
			if a.bump_cd <= 0.0:
				a.bump_cd = 0.5
				a.speed *= 0.92
				if not a.cpu:
					sound("bump", -4.0, randf_range(0.9, 1.2))
					rumble(a, 0.4, 0.12)


func on_wall(k, impact: float) -> void:
	if k.cpu:
		return
	sound("wall", linear_to_db(clampf(impact / 10.0, 0.2, 1.0)) - 4.0, randf_range(0.85, 1.2))
	burst(k.position + k.forward() * 1.2 + Vector3(0, 0.4, 0), Color(1.0, 0.8, 0.3), 8, false)
	rumble(k, 0.35, 0.1)


func on_land(k, air: float) -> void:
	if air > 0.4:
		k.boost(0.8)
		if not k.cpu:
			sound("land", -2.0)
			on_boost(k, "BIG AIR! BOOST!")
			rumble(k, 0.5, 0.15)


func on_boost(k, text: String) -> void:
	if k.cpu:
		return
	if not k.remote:
		sound("boost", -4.0, randf_range(0.95, 1.1))
		rumble(k, 0.3, 0.2)
	if text != "":
		notify(k, text)


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ------------------------------------------

func on_client_joined() -> void:
	_show_center("THE TV PLAYERS JOINED!", 1.5)
	var p = players[1]
	if not p.active:
		_activate(p)
	if state == "wait" or state == "results":
		_start_race(track_i if state == "wait" else track_i + 1)


func on_client_left() -> void:
	for i in range(1, players.size()):
		if players[i].active:
			players[i].set_active(false)
	_show_center("The TV players left - racing on with the CPU buddies", 2.5)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if action == "join" and args.size() > 0:
		index = int(args[0])
	if index <= 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"join":
			if not p.active:
				_activate(p)
				print("Net: player %d joined the race" % (index + 1))
		"leave":
			if p.active:
				p.set_active(false)
				_show_center("%s LEFT" % p.kart_name, 1.5)
		"continue":
			_on_continue()
		"use":
			if p.active and args.size() > 0 and str(args[0]) == p.item and p.item != "":
				_do_use(p, p.item)
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else (results_text if state == "results" else ""), 0.0, false)
	if vr_center != null and paused:
		VrText.snap(vr_center)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHold the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var kd: Array = []
	for k in karts:
		kd.append([k.position, k.yaw, k.active, k.total, k.finished, k.place, k.item, k.shield_t > 0.0,
			k.boost_t > 0.0, k.slip_t > 0.0, k.speed, k.steer_s, k.finish_time])
	var bn: Array = []
	for b in bananas:
		var ba: Array = b
		bn.append(ba[0])
	var head := Transform3D(Basis(), CockpitScript.EYE)
	if cockpit != null:
		head = cockpit.head_local()
	return [state, track_i, state_t, race_t, kd, bn, track.box_state(), head, round_n, laps, finish_frac]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 11:
		return
	var ti: int = s[1]
	if ti != track.track_i or not synced:
		synced = true
		track_i = ti
		track.build(ti)
		_apply_track_look()
		_relocate_local()
	var new_state: String = s[0]
	if new_state != state:
		state = new_state
		state_t = float(s[2])
	race_t = lerpf(race_t, float(s[3]), 0.2)
	laps = s[9]
	finish_frac = s[10]
	round_n = s[8]
	var kd: Array = s[4]
	for i in mini(kd.size(), karts.size()):
		var k = karts[i]
		var d: Array = kd[i]
		var act: bool = d[2]
		if act != k.active:
			k.set_active(act)
			if k.index < CPU_BASE:
				on_player_activity_changed(k)
		k.place = d[5]
		k.finished = d[4]
		k.finish_time = d[12]
		if k.ghost:
			k.target_pos = d[0]
			k.target_yaw = d[1]
			k.total = d[3]
			k.net_shield = d[7]
			k.net_boost = d[8]
			k.net_slip = d[9]
			k.net_speed = d[10]
			k.net_steer = d[11]
			k.item = d[6]
		else:
			k.item = d[6]
			k.shield_t = 1.0 if bool(d[7]) else 0.0
	var bn: Array = s[5]
	bananas.clear()
	for p in bn:
		bananas.append([p, 0.0, -1])
	track.apply_box_state(s[6])
	var head: Transform3D = s[7]
	if players[0].ghost and players[0].head != null:
		players[0].head.transform = Transform3D(head.basis.orthonormalized(), head.origin)


## The track changed under the karts this machine drives: find them on the new one (keeps their distance).
func _relocate_local() -> void:
	for k in karts:
		if k.is_sim():
			k.hint = -1
			k.track_progress_reset()


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false)
			if state == "results" or str(args[0]).begins_with("RACE OVER"):
				results_text = args[0]
		"race":
			track_i = args[0]
			laps = args[1]
			round_n = args[2]
			finish_frac = args[3]
			track.build(track_i)
			_apply_track_look()
			_relocate_local()
			state = "countdown"
			state_t = 0.0
			race_t = 0.0
			for p in players:
				if p.is_local():
					p.reset_race()
					p.set_meta("lap", 1)
		"go":
			state = "race"
			state_t = 0.0
			race_t = 0.0
		"teleport":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.place_at(args[1], args[2], args[3])
		"notify":
			var k = kart_by_index(int(args[0]))
			if k != null:
				notify(k, args[1])
		"slip":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.slip()
				rumble(k, 0.6, 0.3)
		"boost":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.boost(float(args[1]))
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR player paused the game")


# --- HUD -------------------------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	center_label = _make_label(42)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -40
	help_label.offset_bottom = -8
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Controller: stick steer · A go · B brake · X item · Y boost  ·  Keys P1: WASD + Space item, Shift boost  ·  P2: arrows + Ctrl item, . boost  ·  Spare controller: press A to join"


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


func lap_text(k) -> String:
	var L: float = track.length
	var lap := clampi(int(floorf(k.total / L)) + 1, 1, laps)
	return "LAP %d/%d" % [lap, laps]


func _hint_for(k, dt: float) -> String:
	var t: float = k.get_meta("hint_t", 0.0)
	if t > 0.0:
		k.set_meta("hint_t", t - dt)
		return str(k.get_meta("hint", ""))
	if k.wrong_t > 1.5 and not k.finished:
		return "WRONG WAY! Turn around"
	if state == "race" and race_t < 6.0 and round_n <= 1:
		return "Hold A to go!" if k.cockpit == null else "Pull the trigger to go!"
	return ""


func _update_hud(p, dt: float) -> void:
	if net.mode == "client" and not synced:
		p.hud_label.text = "Syncing with the VR player…"
		return
	if not p.active:
		return
	var st := lap_text(p) + "\n" + TrackScript.track_name(track_i)
	if state == "wait":
		st = "WARM-UP LAP\nWaiting for the race…"
	p.hud_label.text = st
	p.place_label.text = "%s/%d" % [ordinal(p.place), racer_count()] if state != "wait" else ""
	var it: String = p.item
	p.item_label.text = "ITEM: %s  (X)" % ITEM_NAMES[it] if it != "" else "ITEM: -  (drive through ? boxes)"
	var ch: float = p.charge
	var bar_bg: ColorRect = p.hud.get_node("BarBg")
	p.boost_fill.size.x = bar_bg.size.x * ch
	p.boost_fill.color = Color(1.0, 0.85, 0.2) if ch >= 1.0 else Color(0.3, 0.8, 1.0)
	if ch >= 1.0:
		p.boost_fill.color = p.boost_fill.color.lightened(0.3 * (0.5 + 0.5 * sin(race_t * 10.0)))
	var h := _hint_for(p, dt)
	if h == "" and ch >= 1.0 and state == "race" and not p.finished:
		h = ""
	p.hint_label.text = h
	if p.finished and state == "race":
		p.hint_label.text = "FINISHED %s!" % ordinal(p.place).to_upper()


## The VR driver's dashboard (just beyond the wheel): lap, place, item / boost and hints.
func vr_dash_text(k) -> String:
	var lines: Array[String] = []
	if state == "wait":
		lines.append("WARM-UP · waiting for the race")
	else:
		lines.append("%s   ·   %s of %d" % [lap_text(k), ordinal(k.place), racer_count()])
	var it: String = k.item
	if it != "":
		lines.append("A: use %s" % ITEM_NAMES[it])
	elif k.charge >= 1.0:
		lines.append("BOOST READY - press A!")
	else:
		lines.append("boost charging…")
	var h := _hint_for(k, get_process_delta_time())
	if k.finished and state == "race":
		h = "FINISHED %s!" % ordinal(k.place).to_upper()
	if h != "":
		lines.append(h)
	return "\n".join(lines)


func _update_vr_text(_dt: float) -> void:
	if help_label.modulate.a > 0.0 and round_n >= 2:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if cockpit == null or cockpit.fake:
		return
	var cam: XRCamera3D = cockpit.xr_camera
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 40
		vr_center.outline_size = 26
		vr_center.pixel_size = 0.0022
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 1200.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cockpit.xr_origin.add_child(vr_center)  # rides along with the kart
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, cam, cockpit.xr_origin, 0.3, 1.8)
