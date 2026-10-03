extends Node3D
const VrText := preload("res://core/vr_text.gd")
## BEE GARDEN: a cosy co-op growing game (no fighting, just a sunny garden).
##  - Player 1 (VR, host) is the GARDENER at a big waist-high garden bed: plants seeds from the seed
##    tray, waters the plants with the watering can, picks ripe fruit and shoos greedy pests.
##  - Players 2 to 7 (TV) are BEES: fly into blooming flowers to collect pollen, take it to the hive to
##    make honey. A bee that visits a DIFFERENT flower with pollen pollinates it, and it grows fruit.
##  - Golden sun lilies only open when the gardener has watered them a LOT, and then give the bees
##    golden pollen (3x honey) and the gardener a golden fruit.
##  - Each day: fill the honey jars before the sun sets. Seasons change from day to day.
## P2 is keyboard set 0 + the 1st controller, P3 keyboard set 1 + the 2nd controller; any other
## controller presses A to drop in as the next free bee (up to P7). Each controller drives one bee.
## Modes (docs/GAME_DEV_GUIDE.md): DUO_JOIN=<host> client, VR or DUO_HOST=1 host, else local split screen.

const W := preload("res://games/bee_garden/world.gd")
const GardenerScript := preload("res://games/bee_garden/gardener.gd")
const BeeScript := preload("res://games/bee_garden/bee.gd")
const PlantScript := preload("res://games/bee_garden/plant.gd")
const PestScript := preload("res://games/bee_garden/pest.gd")
const JoinListenerScript := preload("res://games/bee_garden/join_listener.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")

const MAX_BEES := 6          # TV players 2..7 (player indices 1..6)
const VR_LAYER := 1024       # the gardener's floating banner: drawn in VR only
const INTRO_TIME := 6.0
const DUSK_TIME := 6.0
const DAY_LEN := 170.0
const POLLEN_REGROW := 4.0
const FRUIT_TIME := 9.0
const HARVESTS_PER_PLANT := 2
const PLAYER_COLORS: Array[Color] = [Color(0.4, 0.75, 0.35), Color(1.0, 0.45, 0.6), Color(0.35, 0.65, 1.0),
	Color(0.7, 0.45, 1.0), Color(1.0, 0.55, 0.2), Color(0.3, 0.9, 0.8), Color(0.95, 0.95, 0.95)]
const SOUNDS := {
	"pollen": [0.12, 900.0, 1500.0, 0.25, "sine", 0.0],
	"honey": [0.45, 523.0, 1046.0, 0.35, "tri", 0.0],
	"jar": [0.8, 392.0, 1568.0, 0.4, "tri", 0.0],
	"plant": [0.18, 220.0, 120.0, 0.4, "sine", 0.5],
	"pick": [0.08, 700.0, 1000.0, 0.25, "sine", 0.0],
	"water": [0.3, 1800.0, 1200.0, 0.12, "sine", 0.9],
	"shoo": [0.3, 300.0, 900.0, 0.3, "saw", 0.6],
	"bloom": [0.5, 660.0, 1320.0, 0.3, "tri", 0.0],
	"ripe": [0.25, 880.0, 1320.0, 0.3, "sine", 0.0],
	"harvest": [0.35, 600.0, 1600.0, 0.35, "sine", 0.0],
	"pollinate": [0.3, 1000.0, 2000.0, 0.25, "tri", 0.0],
	"steal": [0.25, 500.0, 250.0, 0.25, "square", 0.2],
	"daydone": [1.2, 392.0, 1568.0, 0.4, "tri", 0.0],
	"sunset": [1.6, 440.0, 110.0, 0.4, "sine", 0.0],
	"zoom": [0.25, 200.0, 500.0, 0.2, "saw", 0.3],
	"buzz": [0.4, 160.0, 190.0, 0.25, "saw", 0.2],
	"miss": [0.25, 300.0, 150.0, 0.25, "sine", 0.3],
}

var players: Array = []
var gardener
var net: Node
var ready_to_play := false
var xr_interface: XRInterface
var vr_on := false
var mirror_vp: SubViewport
var mirror_t := 0.0
var net_ids := 0
var ghost_nodes := {}
var synced := false
var sfx: Node
var music: AudioStreamPlayer
var join_listener: Node

var phase := "wait"   # wait, intro, day, dusk, over
var phase_t := 0.0
var day := 0
var day_t := DAY_LEN
var honey := 0
var target := 40
var total_honey := 0
var days_done := 0
var day_bees := 1
var pest_t := 20.0
var basket_count := 0
var game_over := false
var game_over_time := 0.0
var best_days := 0
var spots: Array = []         # one Dictionary per planting spot (see plant.gd)
var plant_nodes: Array = []
var seeds_flying: Array = []  # [{node, pos, vel, kind, real}]
var jar_nodes: Array = []
var basket_fruit: Array[MeshInstance3D] = []
var splash_t := {}
var stats := {"planted": 0, "harvested": 0, "shooed": 0, "pollinated": 0, "pollen": 0}

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var sign_label: Label3D
var sun: DirectionalLight3D
var sun_ball: MeshInstance3D
var env: Environment
var season_shown := -1

var view_root: Control
var views_dirty := true
var last_view_size := Vector2.ZERO
var view_count := 0


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	vr_on = xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	W.build(self, vr_on)
	sun = get_node("Sun")
	sun_ball = get_node("SunBall")
	sign_label = get_node("Sign")
	env = (get_node("Env") as WorldEnvironment).environment
	_build_plants()
	_build_jars()
	_build_hud()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	best_days = _load_best()
	if OS.has_environment("DUO_JOIN"):
		_show_center("Connecting to the gardener…", 0.0)
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
	if mode != "client":
		_reset_garden()
	ready_to_play = true
	_ensure_join_listener()
	print("Bee Garden: %s mode" % mode)
	var bee_help := "BEES: left stick / WASD fly · right stick / A D turn · RT / Space up · LT / Shift down · A / E zoom\n" \
		+ "Fly into glowing flowers for pollen, bring it to the HIVE for honey · visit a different flower to grow fruit\n"
	if mode == "local":
		help_label.text = bee_help + "GARDENER (left screen): mouse or 2nd controller moves the glove · hold click / RT: grab seeds, the can, fruit, pests\n" \
			+ "More bees: press A on another controller (or arrows + Ctrl) to join, up to 6 bees"
	else:
		help_label.text = bee_help + "More bees: press A on any other controller (or arrows + Ctrl) to join, up to 6 bees  ·  The GARDENER in VR plants, waters and picks fruit"
	if mode == "host":
		_show_center("BEE GARDEN\nWaiting for the bees to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED\nBuzz buzz!", 2.0)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


func bees() -> Array:
	return players.slice(1)


func active_bee_count() -> int:
	var n := 0
	for b in bees():
		if b.active:
			n += 1
	return maxi(n, 1)


func head_pos(i: int) -> Vector3:
	if i < 0 or i >= spots.size():
		return Vector3.ZERO
	return PlantScript.head_pos(i, spots[i])


# --- Players and views -------------------------------------------------------

func _build_players(mode: String) -> void:
	gardener = GardenerScript.new()
	gardener.main = self
	gardener.color = PLAYER_COLORS[0]
	add_child(gardener)
	players.append(gardener)
	_ensure_bees(mode)


## Every machine keeps a bee for each TV seat (indices 1..MAX_BEES) so indices line up with net.gd
## and the snapshots (the host has all seats from the start). Seats 3+ sleep until someone joins.
func _ensure_bees(mode: String) -> void:
	if gardener == null:
		return
	while players.size() <= MAX_BEES:
		var i := players.size()
		var b := BeeScript.new()
		b.main = self
		b.index = i
		b.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		b.remote = mode == "host"
		b.key_set = i - 1 if i <= 2 else -1
		b.claimed = i <= 2
		b.position = spawn_pos(i)
		b.face = -PI * 0.5
		b.cam_yaw = -PI * 0.5
		add_child(b)
		players.append(b)
		if i >= 2:
			b.set_active(false)


func spawn_pos(i: int) -> Vector3:
	var k := i - 1
	return Vector3(-4.3 + (k % 3) * 0.55, 1.1 + float(k / 3) * 0.5, 0.9 + (k % 2) * 0.3)


func _build_views(mode: String) -> void:
	if vr_on and mode != "client":
		xr_interface = XRServer.find_interface("OpenXR")
		print("VR headset found: player 1 is the gardener")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		sun.shadow_enabled = false
		env.ssao_enabled = false
		env.fog_enabled = false
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
		gardener.setup_vr(origin, cam, left, right)
		_build_vr_mirror(cam)
	elif mode == "client":
		gardener.setup_ghost()
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.15, 0.1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_root = Control.new()
	view_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(view_root)
	view_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not gardener.vr and not gardener.ghost:
		var vp := _add_view(gardener)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		gardener.setup_flat(cam, true)
	for b in bees():
		if not b.remote and b.active:
			_ensure_view(b)
	views_dirty = true
	_layout_views()


func _ensure_view(b) -> void:
	if b.remote or b.has_meta("view") or view_root == null:
		return
	var vp := _add_view(b)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	b.attach_camera(cam)
	cam.cull_mask = 0xFFFFF & ~VR_LAYER
	var hud := CanvasLayer.new()
	vp.add_child(hud)
	b.hud_label = _make_label(28)
	b.hud_label.add_theme_color_override("font_color", b.color.lightened(0.35))
	hud.add_child(b.hud_label)
	b.hint_label = _make_label(30)
	b.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(b.hint_label)
	_scale_hud(b, 1.0)
	views_dirty = true


## Per-view HUD, shrunk for small grid cells.
func _scale_hud(b, s: float) -> void:
	if b.hud_label == null or b.hint_label == null:
		return
	if b.has_meta("hud_scale") and is_equal_approx(float(b.get_meta("hud_scale")), s):
		return
	b.set_meta("hud_scale", s)
	var fs := maxi(12, int(28 * s))
	var hl: Label = b.hud_label
	hl.add_theme_font_size_override("font_size", fs)
	hl.add_theme_constant_override("outline_size", maxi(4, int(fs / 4.0)))
	hl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hl.offset_top = -70.0 * s
	hl.offset_left = 26.0 * s
	var fs2 := maxi(12, int(30 * s))
	var hn: Label = b.hint_label
	hn.add_theme_font_size_override("font_size", fs2)
	hn.add_theme_constant_override("outline_size", maxi(4, int(fs2 / 4.0)))
	hn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hn.offset_left = -520.0 * s
	hn.offset_right = 520.0 * s
	hn.offset_top = -190.0 * s
	hn.offset_bottom = -80.0 * s


## Split-screen grid: 1 view full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (7 as 4x2: local mode with
## the flat gardener plus six bees). More views = lower 3D resolution and cheaper shadows.
func _layout_views() -> void:
	if view_root == null:
		return
	var area := view_root.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
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
	if n > 2:
		hud_s = clampf(minf(cell.x / 958.0, cell.y / 1080.0) * 1.2, 0.45, 1.0)
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
		if p != gardener:
			_scale_hud(p, hud_s)
	if not vr_on:
		sun.shadow_enabled = n <= 4
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if n <= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL


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


## Low-res copy of the gardener's VR view for gdev / people watching.
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
	cam.near = 0.1
	cam.far = 600.0
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


# --- Controllers and drop-in join --------------------------------------------

## Players that get a controller automatically, in order: P2, P3 (TV machine), the flat gardener.
func _reserved_slots() -> Array:
	var slots: Array = []
	if players.size() > 1 and not players[1].remote:
		slots.append(players[1])
	if net.mode == "client" and players.size() > 2:
		slots.append(players[2])
	if gardener.flat:
		slots.append(gardener)
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
			request_leave(who)  # no keyboard to fall back on: the bee leaves until it's back
		return
	if pad_owner(device) >= 0:
		return
	print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
	for b in bees():
		if b.joy < 0 and int(b.get_meta("lost_pad", -1)) == device:
			b.joy = device
			b.remove_meta("lost_pad")
			if b.get_meta("rejoin", false):
				b.remove_meta("rejoin")
				request_join(b.index)
			return
	for p in _reserved_slots():
		if p.joy < 0:
			p.joy = device
			return
	# Otherwise it's a spare: pressing A on it joins the next free bee (handle_join_input).


func _ensure_join_listener() -> void:
	if join_listener != null and is_instance_valid(join_listener):
		return
	join_listener = JoinListenerScript.new()
	join_listener.name = "JoinListener"
	join_listener.main = self
	add_child(join_listener)


## Called by join_listener for every input event: A on a controller nobody owns claims the next free
## bee (true = consumed). Start is left alone (it opens the pause menu).
func handle_join_input(event: InputEvent) -> bool:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or b.button_index != JOY_BUTTON_A:
		return false
	if not ready_to_play or game_over or net == null or net.mode == "host" or get_tree().paused:
		return false
	if pad_owner(b.device) >= 0:
		return false
	var bee = _free_bee()
	if bee == null:
		_show_center("All 6 bee seats are taken!", 1.5, false)
		return true
	bee.joy = b.device
	bee.claimed = true
	bee.remove_meta("rejoin")
	bee.remove_meta("lost_pad")
	print("Joypad %d drops in as P%d" % [b.device, bee.index + 1])
	join_t = 1.0
	request_join(bee.index)
	return true


func _free_bee():
	for b in bees():
		if not b.remote and not b.active and b.joy < 0 and not b.has_meta("lost_pad") and not b.claimed:
			return b
	for b in bees():
		if not b.remote and not b.active and b.joy < 0 and not b.has_meta("lost_pad"):
			return b
	for b in bees():
		if not b.remote and not b.active and b.joy < 0:
			return b
	return null


func request_join(i: int) -> void:
	if i < 1 or i >= players.size():
		return
	var b = players[i]
	if not b.remote and not b.active:
		b.global_position = spawn_pos(i)
		b.vel = Vector3.ZERO
	if net.mode == "client":
		net.send_action("join", [], i)
	else:
		on_p2_action("join", [], i)


func request_leave(i: int) -> void:
	if net.mode == "client":
		net.send_action("leave", [], i)
	else:
		on_p2_action("leave", [], i)


## Tests: join TV player `index` (1..6) as if a new controller had pressed A.
func debug_join(index: int) -> void:
	_ensure_bees(net.mode)
	if index < 1 or index >= players.size() or players[index].remote:
		return
	players[index].claimed = true
	request_join(index)


func on_player_activity_changed(p) -> void:
	if p.active and not p.remote:
		_ensure_view(p)
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active
	views_dirty = true


## TV / split screen: a sleeping bee whose controller or keyboard set presses a button wakes up.
var join_t := 0.0
func _check_join() -> void:
	join_t -= get_process_delta_time()
	if join_t > 0.0 or game_over:
		return
	for b in bees():
		if b.active or b.remote or not b.claimed:
			continue
		if b.wake_held():
			join_t = 1.0
			request_join(b.index)
			return


# --- Effects -----------------------------------------------------------------

func burst(pos: Vector3, color: Color, amount: int = 14, size: float = 0.06, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var m := W.sphere(size, 6)
	m.material = W.cmat(color, 1.0)
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.1).timeout.connect(p.queue_free)
	if broadcast and net:
		net.event("burst", [pos, color, amount, size])


func local_sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	if SOUNDS.has(sound_name):
		sfx.add_sound(sound_name, SOUNDS[sound_name])
	sfx.play(sound_name, volume_db, pitch)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	local_sound(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Floating text that rises and fades (faces the VR gardener, or billboards on the TV).
func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.06, 0.0, 0.9)
	l.font_size = 56
	l.outline_size = 16
	l.pixel_size = 0.006
	l.no_depth_test = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	if gardener != null and gardener.vr:
		var to: Vector3 = pos - gardener.xr_camera.global_position
		l.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 0.7, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.9)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.9)
	t.chain().tween_callback(l.queue_free)
	if broadcast and net:
		net.event("popup", [pos, text, color])


## A puff of mist from the gardener's hand towards a pest (point + trigger).
func mist(from: Vector3, to: Vector3) -> void:
	var mid := from.lerp(to, 0.5)
	burst(mid, Color(0.75, 0.9, 1.0), 8, 0.05)
	burst(to, Color(0.75, 0.9, 1.0), 10, 0.05)


# --- Garden state (host) -------------------------------------------------------

func _empty_spot() -> Dictionary:
	return {"kind": -1, "growth": 0.0, "water": 0.0, "bloom": false, "pollen_t": 0.0, "ready": false,
		"fruit": -1.0, "bug": false, "harvests": 0}


func _reset_garden() -> void:
	spots.clear()
	for i in W.SPOTS:
		spots.append(_empty_spot())
	# A few flowers are already blooming so the bees can start right away; the sun lily needs water.
	for e in [[1, 0], [2, 1], [5, 0], [6, 0], [10, 1]]:
		var s: Dictionary = spots[int(e[0])]
		s.kind = int(e[1])
		s.growth = 1.0
		s.water = 0.8
		s.bloom = true
	var lily: Dictionary = spots[8]
	lily.kind = 2
	lily.growth = 1.0
	lily.water = 0.3


func _build_plants() -> void:
	for i in W.SPOTS:
		var p := PlantScript.new()
		p.spot = i
		add_child(p)
		plant_nodes.append(p)
		spots.append(_empty_spot())


func _build_jars() -> void:
	var glass := W.mat(Color(0.85, 0.95, 1.0, 0.35), 0.0, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in W.MAX_JARS:
		var j := Node3D.new()
		add_child(j)
		var fill := W.mesh_node(j, W.cyl(0.2, 0.2, 1.0, 12), W.cmat(Color(1.0, 0.68, 0.1), 0.5), Vector3.ZERO)
		W.mesh_node(j, W.cyl(0.25, 0.25, 0.6, 12), glass, Vector3(0, 0.3, 0))
		W.mesh_node(j, W.cyl(0.27, 0.27, 0.08, 12), W.cmat(Color(0.9, 0.3, 0.3)), Vector3(0, 0.63, 0))
		j.set_meta("fill", fill)
		jar_nodes.append(j)
	for i in 6:
		var f := W.mesh_node(self, W.sphere(0.12, 8), W.cmat(Color.RED), W.BASKET_POS + Vector3(-0.15 + (i % 3) * 0.15, 0.32 + float(i / 3) * 0.1, -0.06 + (i % 2) * 0.12))
		f.visible = false
		basket_fruit.append(f)


func jar_count() -> int:
	return clampi(ceili(target / 6.0), 2, W.MAX_JARS)


func _target_for(d: int, n_bees: int) -> int:
	var base := 40.0 + 18.0 * (d - 1)
	return int(round(base * (1.0 + 0.3 * (n_bees - 1))))


func can_interact() -> bool:
	return ready_to_play and not game_over and phase != "wait"


func aphid_target_ok(i: int) -> bool:
	return i >= 0 and i < spots.size() and int(spots[i].kind) >= 0 and float(spots[i].growth) > 0.25


func pick_aphid_target() -> int:
	var taken := {}
	for p in get_tree().get_nodes_in_group("pests"):
		if p.kind == "aphid" and not p.is_fleeing():
			taken[p.target] = true
	var options: Array[int] = []
	for i in spots.size():
		if aphid_target_ok(i) and not taken.has(i):
			options.append(i)
			if spots[i].bloom:
				options.append(i)  # blooming flowers taste best
	if options.is_empty():
		return -1
	return options[randi() % options.size()]


func try_harvest(pos: Vector3, reach: float, flat: bool) -> bool:
	var best := -1
	var best_d := reach
	for i in spots.size():
		var s: Dictionary = spots[i]
		if int(s.kind) < 0 or float(s.fruit) < 1.0:
			continue
		var fp := head_pos(i) + Vector3(0.0, -0.1, 0.08)
		var d := Vector2(fp.x - pos.x, fp.z - pos.z).length() if flat else fp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	_harvest(best)
	return true


func _harvest(i: int) -> void:
	var s: Dictionary = spots[i]
	var k: int = s.kind
	var kd: Dictionary = W.KINDS[k]
	var from := head_pos(i)
	var value: int = kd.fruit
	s.fruit = -1.0
	s.harvests = int(s.harvests) + 1
	stats.harvested += 1
	basket_count += 1
	var spent := int(s.harvests) >= HARVESTS_PER_PLANT
	if spent:
		spots[i] = _empty_spot()
	_fly_fruit(from, k)
	net.event("fruit", [from, k])
	sound("harvest", -2.0, 1.0 + k * 0.1)
	popup(from + Vector3.UP * 0.5, "+%d honey!%s" % [value, "\n(plant something new here)" if spent else ""], Color(1.0, 0.85, 0.3))
	print("Harvested a %s fruit (+%d honey)" % [kd.name, value])
	add_honey(value, from)


## Fruit hops from the plant into the basket (visual, both machines).
func _fly_fruit(from: Vector3, k: int) -> void:
	var kd: Dictionary = W.KINDS[clampi(k, 0, 2)]
	var f := W.mesh_node(self, W.sphere(0.15, 10), W.cmat(kd.fruit_color, 0.3), from)
	var to := W.BASKET_POS + Vector3(0, 0.45, 0)
	var t := f.create_tween()
	t.tween_method(_move_fruit.bind(f, from, to), 0.0, 1.0, 0.6)
	t.tween_callback(f.queue_free)


func _move_fruit(x: float, f: Node3D, from: Vector3, to: Vector3) -> void:
	if is_instance_valid(f):
		f.global_position = from.lerp(to, x) + Vector3.UP * sin(x * PI) * 1.2


func tray_pick(pos: Vector3, reach: float, flat: bool) -> int:
	var best := -1
	var best_d := reach
	for k in 3:
		var sp := W.tray_slot(k)
		var d := Vector2(sp.x - pos.x, sp.z - pos.z).length() if flat else sp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = k
	return best


func pest_near(pos: Vector3, reach: float, flat: bool):
	var best = null
	var best_d := reach
	for p in get_tree().get_nodes_in_group("pests"):
		if p.is_fleeing() or p.is_queued_for_deletion():
			continue
		var pp: Vector3 = p.global_position
		var d := Vector2(pp.x - pos.x, pp.z - pos.z).length() if flat else pp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func pest_on_ray(origin: Vector3, dir: Vector3):
	var best = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("pests"):
		if p.is_fleeing() or p.is_queued_for_deletion():
			continue
		var to: Vector3 = p.global_position - origin
		var along := to.dot(dir)
		if along < 0.0 or along > 16.0:
			continue
		var perp := (to - dir * along).length()
		if perp < 0.4 + along * 0.04 and perp < best_d:
			best_d = perp
			best = p
	return best


func shoo(pest, from: Vector3) -> void:
	if pest == null or pest.is_fleeing():
		return
	var pos: Vector3 = pest.global_position
	pest.shoo(from)
	stats.shooed += 1
	sound("shoo", -4.0, 1.3 if pest.kind == "aphid" else 0.9)
	burst(pos, Color(0.85, 0.95, 1.0), 10, 0.05)
	popup(pos + Vector3.UP * 0.4, ["Shoo!", "Off you go!", "Bye bye!", "Shoo shoo!"][randi() % 4], Color(0.7, 1.0, 0.7))
	print("Shooed a %s" % pest.kind)


func wasp_steal(_w) -> void:
	if honey <= 0:
		return
	honey -= 1
	total_honey = maxi(0, total_honey - 1)
	sound("steal", -6.0)
	popup(W.HIVE_ENTRY + Vector3(0.4, 0.8, 0.0), "-1 honey! Gardener, shoo the wasp!", Color(1.0, 0.6, 0.4))


func drop_seed(kind: int, pos: Vector3, vel: Vector3) -> void:
	_spawn_seed(kind, pos, vel, true)
	net.event("seed", [kind, pos, vel])


func _spawn_seed(kind: int, pos: Vector3, vel: Vector3, real: bool) -> void:
	var kd: Dictionary = W.KINDS[clampi(kind, 0, 2)]
	var n := W.mesh_node(self, W.sphere(0.07, 8), W.cmat(Color(kd.petal).darkened(0.35), 0.2), pos, Vector3(1.0, 0.8, 1.3))
	seeds_flying.append({"node": n, "pos": pos, "vel": vel, "kind": kind, "real": real})


func _update_seeds(delta: float) -> void:
	for i in range(seeds_flying.size() - 1, -1, -1):
		var s: Dictionary = seeds_flying[i]
		var v: Vector3 = s.vel
		var p: Vector3 = s.pos
		v += Vector3(0, -30.0, 0) * delta
		v *= exp(-0.5 * delta)
		p += v * delta
		s.vel = v
		s.pos = p
		var n: MeshInstance3D = s.node
		n.global_position = p
		var floor_h := 0.0 if W.over_bed(p.x, p.z) else W.LAWN_Y
		if p.y > floor_h:
			continue
		n.queue_free()
		seeds_flying.remove_at(i)
		if s.real:
			_seed_landed(int(s.kind), Vector3(p.x, floor_h, p.z))


func _seed_landed(kind: int, p: Vector3) -> void:
	if not W.in_soil(p.x, p.z):
		burst(p + Vector3.UP * 0.1, Color(0.6, 0.45, 0.3), 6, 0.04)
		popup(p + Vector3.UP * 0.5, "Missed the soil!", Color(1.0, 0.8, 0.6))
		sound("miss", -6.0)
		return
	var best := -1
	var best_d := 1.4
	for i in spots.size():
		if int(spots[i].kind) >= 0:
			continue
		var sp := W.spot_pos(i)
		var d := Vector2(sp.x - p.x, sp.z - p.z).length()
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		burst(p + Vector3.UP * 0.1, Color(0.6, 0.45, 0.3), 6, 0.04)
		popup(p + Vector3.UP * 0.5, "No room here - try an empty spot", Color(1.0, 0.8, 0.6))
		sound("miss", -6.0)
		return
	var s := _empty_spot()
	s.kind = kind
	s.water = 0.3
	s.growth = 0.02
	spots[best] = s
	stats.planted += 1
	var kd: Dictionary = W.KINDS[kind]
	burst(W.spot_pos(best) + Vector3.UP * 0.1, Color(0.45, 0.3, 0.18), 12, 0.05)
	sound("plant", -2.0, 1.0 + kind * 0.15)
	var tip := "Planted a %s!" % kd.name
	if kind == 2:
		tip = "A sun lily! Water it LOTS to open it"
	popup(W.spot_pos(best) + Vector3.UP * 0.6, tip, kd.petal.lightened(0.3))
	print("Planted a %s in spot %d" % [kd.name, best])


func water_at(tip: Vector3, delta: float) -> void:
	if tip.y < -1.0 or tip.y > 5.0:
		return
	var land := Vector2(tip.x, tip.z)
	for i in spots.size():
		var s: Dictionary = spots[i]
		if int(s.kind) < 0:
			continue
		var sp := W.spot_pos(i)
		if Vector2(sp.x, sp.z).distance_to(land) > 0.8:
			continue
		var before: float = s.water
		s.water = minf(1.0, before + 0.6 * delta)
		if before < 0.12 and float(s.water) >= 0.12:
			popup(head_pos(i) + Vector3.UP * 0.4, "Ahh, water!", Color(0.6, 0.85, 1.0))
	for b in bees():
		if not b.active:
			continue
		var bp: Vector3 = b.global_position
		if bp.y < tip.y and Vector2(bp.x, bp.z).distance_to(land) < 0.45:
			var key := "b%d" % b.index
			if Time.get_ticks_msec() > int(splash_t.get(key, 0)):
				splash_t[key] = Time.get_ticks_msec() + 2500
				popup(bp + Vector3.UP * 0.35, "Splash! P%d got a shower" % (b.index + 1), Color(0.6, 0.85, 1.0))


func add_honey(value: int, _from: Vector3) -> void:
	var size := float(target) / jar_count()
	var full_before := floori(honey / size)
	honey += value
	total_honey += value
	var full_after := floori(honey / size)
	if full_after > full_before and full_after <= jar_count():
		var jp := W.jar_pos(mini(full_after, jar_count()) - 1, jar_count())
		burst(jp + Vector3.UP * 0.6, Color(1.0, 0.75, 0.2), 20, 0.06)
		popup(jp + Vector3.UP * 1.0, "JAR FULL!", Color(1.0, 0.8, 0.25))
		sound("jar", -2.0)


# --- Simulation ----------------------------------------------------------------

func _sim(delta: float) -> void:
	var season := (maxi(day, 1) - 1) % 4
	var drain := 0.02 * (1.4 if season == 1 else 1.0)
	for s in spots:
		s.bug = false
	for p in get_tree().get_nodes_in_group("pests"):
		if p.kind == "aphid" and p.state == "munch" and aphid_target_ok(p.target):
			spots[p.target].bug = true
	for i in spots.size():
		var s: Dictionary = spots[i]
		var k: int = s.kind
		if k < 0:
			s.ready = false
			continue
		var kd: Dictionary = W.KINDS[k]
		var bug: bool = s.bug
		s.water = maxf(0.0, float(s.water) - drain * (3.0 if bug else 1.0) * delta)
		var water: float = s.water
		if float(s.growth) < 1.0 and water > 0.12 and not bug:
			s.growth = minf(1.0, float(s.growth) + delta / float(kd.grow))
		if not s.bloom and float(s.growth) >= 1.0 and water >= maxf(float(kd.thirst), 0.12):
			s.bloom = true
			s.pollen_t = 0.0
			var hp := head_pos(i)
			burst(hp, kd.petal, 16, 0.06)
			sound("bloom", -4.0, 1.0 + k * 0.12)
			popup(hp + Vector3.UP * 0.4, "The sun lily opened!\nGOLDEN POLLEN, bees!" if k == 2 else "%s in bloom!" % kd.name, kd.petal.lightened(0.3))
		elif s.bloom and water <= 0.0:
			s.bloom = false
			popup(head_pos(i) + Vector3.UP * 0.4, "Thirsty! Gardener, water me!", Color(0.6, 0.8, 1.0))
		if s.bloom and not bug:
			s.pollen_t = float(s.pollen_t) - delta
		s.ready = s.bloom and float(s.pollen_t) <= 0.0 and not bug
		var fr: float = s.fruit
		if fr >= 0.0 and fr < 1.0 and water > 0.12:
			fr = minf(1.0, fr + delta / FRUIT_TIME)
			s.fruit = fr
			if fr >= 1.0:
				sound("ripe", -4.0, 1.0 + k * 0.1)
				popup(head_pos(i) + Vector3.UP * 0.4, "Ripe fruit! Gardener, pick me!", kd.fruit_color.lightened(0.3))
				gardener.buzz_right(0.3)
	_host_bees(delta)


func _host_bees(delta: float) -> void:
	for b in bees():
		if not b.active:
			continue
		b.gather_cd -= delta
		var pos: Vector3 = b.global_position
		for i in spots.size():
			var s: Dictionary = spots[i]
			if not s.bloom:
				continue
			var hp := head_pos(i)
			if pos.distance_to(hp) > 0.6:
				continue
			var kd: Dictionary = W.KINDS[int(s.kind)]
			if b.last_flower != i and b.pollen > 0 and float(s.fruit) < 0.0:
				s.fruit = 0.0
				stats.pollinated += 1
				burst(hp, Color(1.0, 0.9, 0.5), 14, 0.05)
				sound("pollinate", -4.0, 1.0)
				popup(hp + Vector3.UP * 0.5, "Pollinated! A fruit is growing", Color(1.0, 0.9, 0.5))
				print("P%d pollinated spot %d" % [b.index + 1, i])
			if s.ready and b.pollen < BeeScript.MAX_POLLEN and b.gather_cd <= 0.0:
				b.pollen += 1
				b.pollen_value += int(kd.honey)
				b.gold = b.gold or int(s.kind) == 2
				b.gather_cd = 0.35
				s.pollen_t = POLLEN_REGROW
				s.ready = false
				stats.pollen += 1
				burst(hp, Color(1.0, 0.8, 0.2), 8, 0.04)
				sound("pollen", -6.0, 0.9 + b.pollen * 0.15)
				if b.pollen >= BeeScript.MAX_POLLEN:
					popup(pos + Vector3.UP * 0.4, "FULL! To the hive!", b.color.lightened(0.3))
			b.last_flower = i
			break
		if b.pollen > 0 and pos.distance_to(W.HIVE_ENTRY) < 0.8:
			var v: int = b.pollen_value
			b.honey_made += v
			b.pollen = 0
			b.pollen_value = 0
			b.gold = false
			b.last_flower = -1
			burst(W.HIVE_ENTRY, Color(1.0, 0.7, 0.15), 16, 0.06)
			sound("honey", -2.0, 1.0 + b.index * 0.04)
			popup(W.HIVE_ENTRY + Vector3(0.3, 0.7, 0.0), "+%d honey  (P%d)" % [v, b.index + 1], b.color.lightened(0.35))
			print("P%d made %d honey (%d / %d)" % [b.index + 1, v, honey + v, target])
			add_honey(v, W.HIVE_ENTRY)


func _host_pests(delta: float) -> void:
	pest_t -= delta
	if pest_t > 0.0:
		return
	var nb := active_bee_count()
	pest_t = maxf(7.0, 17.0 - day * 2.0) * randf_range(0.8, 1.2) / (1.0 + 0.1 * (nb - 1))
	var pests := get_tree().get_nodes_in_group("pests")
	if pests.size() >= mini(1 + day, 4):
		return
	var has_wasp := false
	for p in pests:
		if p.kind == "wasp":
			has_wasp = true
	var kind := "wasp" if not has_wasp and randf() < 0.35 and honey > 2 else "aphid"
	var tgt := -1
	if kind == "aphid":
		tgt = pick_aphid_target()
		if tgt < 0:
			return
	var p := PestScript.new()
	p.kind = kind
	p.main = self
	p.target = tgt
	p.net_id = next_net_id()
	p.position = Vector3(randf_range(-7.0, 7.0), 3.5, -7.0)
	add_child(p)
	sound("buzz", -8.0, 1.4 if kind == "aphid" else 0.8)
	print("A %s arrived" % kind)


func _start_day(n: int) -> void:
	day = n
	day_t = DAY_LEN
	honey = 0
	day_bees = active_bee_count()
	target = _target_for(n, day_bees)
	phase = "intro"
	phase_t = INTRO_TIME if n == 1 else 3.5
	pest_t = 22.0 if n == 1 else 12.0
	for p in get_tree().get_nodes_in_group("pests"):
		p.queue_free()
	var season: String = W.SEASONS[(n - 1) % 4]
	print("Day %d (%s): fill %d jars = %d honey" % [n, season, jar_count(), target])
	sound("bloom", 0.0, 0.8)
	if n == 1:
		_show_center("BEE GARDEN  -  DAY 1, %s\nGardener: plant seeds, water, pick fruit, shoo pests\nBees: pollen from glowing flowers to the HIVE = honey!\nFill %d honey jars before sunset" % [season, jar_count()], INTRO_TIME + 1.0)
	else:
		_show_center("DAY %d  -  %s\nFill %d honey jars before sunset!" % [n, season, jar_count()], 3.5)


func _day_complete() -> void:
	phase = "dusk"
	phase_t = DUSK_TIME
	days_done += 1
	print("Level complete: day %d done (%d honey, %.0f s left)" % [day, honey, day_t])
	sound("daydone", 0.0)
	for i in jar_count():
		burst(W.jar_pos(i, jar_count()) + Vector3.UP * 0.7, Color(1.0, 0.78, 0.25), 14, 0.06)
	for p in get_tree().get_nodes_in_group("pests"):
		p.shoo(p.global_position + Vector3.DOWN)
	_show_center("DAY %d COMPLETE!\nAll the honey jars are full - well done, garden friends!\nNext: %s" % [day, W.SEASONS[day % 4]], DUSK_TIME)
	if gardener.vr:
		gardener.buzz_right(0.6)


func _sunset() -> void:
	phase = "over"
	game_over = true
	game_over_time = 0.0
	gardener.let_go_all()
	sound("sunset", 0.0)
	var best_line := "Best: %d days" % best_days
	if days_done > best_days:
		best_line = "NEW BEST!  (before: %d days)" % best_days
		best_days = days_done
		_save_best(days_done)
	print("Game over: sunset on day %d, %d days completed, %d honey in total" % [day, days_done, total_honey])
	_show_center("The sun has set - time for bed, little bees  zzz\nDays completed: %d   ·   Honey made: %d\n%s\n\nPress A / Enter (VR: trigger) to play again" % [days_done, total_honey, best_line], 0.0)


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://bee_garden_best.cfg")
	return int(cfg.get_value("best", "days", 0))


func _save_best(d: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "days", d)
	cfg.save("user://bee_garden_best.cfg")


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for b in bees():
		if not b.remote and b.active and b.zoom_held():
			return true
	return false


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -22.0
	music.play_track(2)
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ensure_bees(net.mode)
	_ensure_join_listener()
	_layout_views()
	_update_seeds(delta)
	for i in plant_nodes.size():
		if i < spots.size():
			plant_nodes[i].update_from(spots[i], delta)
	_update_jars(delta)
	_update_sky()
	_update_hud()
	_update_vr_center()
	if net.mode != "host":
		_check_join()
	if net.mode == "client":
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	_host_update(delta)


func _host_update(delta: float) -> void:
	match phase:
		"wait":
			if net.mode != "host" or net.connected:
				_start_day(1)
		"intro", "day", "dusk":
			if net.mode == "host" and not net.connected:
				return  # hold the day while the bees are away
			var nb := active_bee_count()
			if nb > day_bees and phase != "dusk":
				day_bees = nb
				var t2 := _target_for(day, day_bees)
				if t2 > target:
					target = t2
					popup(W.jar_pos(0, jar_count()) + Vector3.UP * 1.2, "More bees, more jars!", Color(1.0, 0.85, 0.4))
			_sim(delta)
			if phase == "intro":
				phase_t -= delta
				if phase_t <= 0.0:
					phase = "day"
			elif phase == "day":
				day_t -= delta
				_host_pests(delta)
				if day_t <= 0.0:
					day_t = 0.0
					_sunset()
					return
			else:
				phase_t -= delta
				if phase_t <= 0.0:
					_start_day(day + 1)
					return
			if phase != "dusk" and honey >= target:
				_day_complete()
		"over":
			game_over_time += delta
			if game_over_time > 1.5 and (_restart_pressed() or gardener.restart_held()):
				get_tree().reload_current_scene()


func _update_jars(_delta: float) -> void:
	var n := jar_count()
	var size := float(target) / n
	for i in jar_nodes.size():
		var j: Node3D = jar_nodes[i]
		j.visible = i < n
		if not j.visible:
			continue
		j.position = W.jar_pos(i, n)
		var f := clampf((honey - i * size) / size, 0.0, 1.0)
		var fill: MeshInstance3D = j.get_meta("fill")
		var h := maxf(f * 0.55, 0.001)
		fill.visible = f > 0.0
		fill.scale = Vector3(1.0, h, 1.0)
		fill.position.y = h * 0.5 + 0.02
	for i in basket_fruit.size():
		basket_fruit[i].visible = i < mini(basket_count, basket_fruit.size())


func _update_sky() -> void:
	var p := 0.0
	if phase == "day" or phase == "dusk":
		p = clampf(1.0 - day_t / DAY_LEN, 0.0, 1.0)
	elif phase == "over":
		p = 1.0
	var az := lerpf(-1.2, 1.2, p)
	var elev := deg_to_rad(12.0 + 55.0 * sin(clampf(p * 0.9 + 0.05, 0.0, 1.0) * PI))
	if phase == "over":
		elev = deg_to_rad(4.0)
	var dir := Vector3(-sin(az) * cos(elev), sin(elev), -cos(az) * cos(elev))
	sun_ball.global_position = dir * 120.0
	if absf(dir.y) < 0.999:
		sun.look_at_from_position(dir * 10.0, Vector3.ZERO, Vector3.UP)
	var evening := smoothstep(0.7, 1.0, p)
	var sky := Color(0.55, 0.8, 1.0).lerp(Color(1.0, 0.7, 0.5), evening)
	env.background_color = sky
	sun.light_color = Color(1.0, 0.95, 0.82).lerp(Color(1.0, 0.65, 0.4), evening)
	sun.light_energy = lerpf(1.15, 0.7, evening)
	var season := (maxi(day, 1) - 1) % 4
	if season != season_shown:
		season_shown = season
		var lawn := get_node_or_null("Lawn") as MeshInstance3D
		if lawn != null:
			(lawn.material_override as StandardMaterial3D).albedo_color = W.SEASON_LAWN[season]
		var leaves := get_node_or_null("Leaves") as MeshInstance3D
		if leaves != null:
			(leaves.material_override as StandardMaterial3D).albedo_color = W.SEASON_LEAF[season]
	var mins := maxi(0, ceili(day_t))
	var state := "%d:%02d until sunset" % [mins / 60, mins % 60]
	if phase == "dusk":
		state = "DAY COMPLETE!"
	elif phase == "over":
		state = "Good night!"
	elif phase == "wait":
		state = "Waiting for the bees…"
	sign_label.text = "BEE GARDEN  ·  DAY %d  %s\nHONEY %d / %d\n%s" % [maxi(day, 1), W.SEASONS[season], honey, target, state]


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ----------------------------

func on_client_joined() -> void:
	_show_center("THE BEES HAVE ARRIVED!  Buzz buzz!", 1.5)


func on_client_left() -> void:
	_show_center("The bees flew home - waiting for them to come back…", 0.0)
	for b in bees():
		if b.index >= 2 and b.active:
			_bee_leaves(b)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index < 1 or index >= players.size():
		return
	var b = players[index]
	match action:
		"join":
			if not b.active:
				b.set_active(true)
				b.pollen = 0
				b.pollen_value = 0
				b.gold = false
				b.last_flower = -1
				if b.remote:
					b.global_position = spawn_pos(index)
					b.net_target = b.global_position
				on_player_activity_changed(b)
				_show_center("PLAYER %d JOINED THE HIVE!" % (index + 1), 1.5)
				sound("buzz", -4.0, 1.0 + index * 0.05)
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			if b.active:
				_bee_leaves(b)
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A bee opened the menu")
			get_tree().paused = paused


func _bee_leaves(b) -> void:
	b.pollen = 0
	b.pollen_value = 0
	b.set_active(false)
	on_player_activity_changed(b)
	popup(b.global_position + Vector3.UP * 0.4, "P%d flew home - see you soon!" % (b.index + 1), b.color)
	print("P%d left the game" % (b.index + 1))


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	if vr_center != null and paused:
		VrText.snap(vr_center)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nPull the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps: Array = []
	for p in players:
		ps.append(p.net_state())
	var sp: Array = []
	for s in spots:
		sp.append([s.kind, snappedf(s.growth, 0.01), snappedf(s.water, 0.01), s.bloom, s.ready, snappedf(s.fruit, 0.01), s.bug])
	var pe: Array = []
	for p in get_tree().get_nodes_in_group("pests"):
		if not p.is_queued_for_deletion():
			pe.append(p.net_item())
	return [phase, day, day_t, honey, target, total_honey, days_done, sp, ps, pe, game_over, basket_count]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	phase = s[0]
	day = s[1]
	day_t = s[2]
	honey = s[3]
	target = s[4]
	total_honey = s[5]
	days_done = s[6]
	var sp: Array = s[7]
	while spots.size() < sp.size():
		spots.append(_empty_spot())
	for i in sp.size():
		var a: Array = sp[i]
		var d: Dictionary = spots[i]
		d.kind = a[0]
		d.growth = a[1]
		d.water = a[2]
		d.bloom = a[3]
		d.ready = a[4]
		d.fruit = a[5]
		d.bug = a[6]
	var ps: Array = s[8]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_pests(s[9])
	var was_over := game_over
	game_over = s[10]
	if game_over and not was_over:
		game_over_time = 0.0
	basket_count = s[11]


func _sync_pests(list: Array) -> void:
	var seen := {}
	for item in list:
		var key := "pest:%d" % int(item[0])
		seen[key] = true
		var g = ghost_nodes.get(key)
		if g == null or not is_instance_valid(g):
			g = PestScript.new()
			g.kind = item[1]
			g.ghost = true
			g.net_id = item[0]
			g.position = item[2]
			add_child(g)
			ghost_nodes[key] = g
		g.apply_net(item)
	for key in ghost_nodes.keys():
		if not seen.has(key):
			var g = ghost_nodes[key]
			if is_instance_valid(g):
				g.queue_free()
			ghost_nodes.erase(key)


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			local_sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3], false)
		"popup":
			popup(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false)
		"seed":
			_spawn_seed(args[0], args[1], args[2], false)
		"fruit":
			_fly_fruit(args[0], args[1])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The gardener paused the game")


# --- HUD ---------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02, 0.95))
	l.add_theme_color_override("font_color", Color(1.0, 0.97, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(32)
	info_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 14
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(52)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label = _make_label(21)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 62
	help_label.offset_bottom = 180
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


## VR can't show 2D overlays: the centre banner floats far in front, above the bed, world-locked.
func _update_vr_center() -> void:
	if gardener == null or not gardener.vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 46
		vr_center.outline_size = 26
		vr_center.outline_modulate = Color.BLACK
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 1000.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.modulate = Color(1.0, 0.95, 0.8)
		vr_center.pixel_size = 0.0024 * W.S
		vr_center.layers = VR_LAYER
		add_child(vr_center)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = center_label.modulate.a
	# Far past the bed and above it (VrText adds comfort distance), so nothing nearer overlaps it.
	VrText.follow(vr_center, gardener.xr_camera, self, 0.3 * W.S, 1.9 * W.S)


func _update_hud() -> void:
	if days_done >= 1 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the gardener…"
		return
	var mins := maxi(0, ceili(day_t))
	var season: String = W.SEASONS[(maxi(day, 1) - 1) % 4]
	info_label.text = "DAY %d  %s      HONEY %d / %d      SUNSET IN %d:%02d" % [maxi(day, 1), season, honey, target, mins / 60, mins % 60]
	var n := active_bee_count()
	if n > 1:
		info_label.text += "      BEES %d" % n


func _exit_tree() -> void:
	if Engine.has_meta("bg_mats"):
		Engine.remove_meta("bg_mats")  # shared material cache: rebuilt by the next run
	XRServer.world_scale = 1.0  # XR world scale is global: don't leave other games diorama-sized
