extends Node3D
const VrText := preload("res://core/vr_text.gd")
## GIANT'S TABLE: a cosy village on a big wooden table. Waves of goblins climb up the table edges
## to steal the embers of the village campfire.
##  - Player 1 (VR, host) is the GIANT: grab goblins and boulders with your hands and throw them.
##  - Players 2 to 7 (TV) are tiny KNIGHTS: sword, crossbow, carry embers home, revive each other.
##    P2 is keyboard set 0 + the 1st controller, P3 keyboard set 1 + the 2nd controller; any other
##    controller presses A (or attack) to drop in as the next free knight (up to P7). Each controller
##    drives exactly one knight (by device id); unplugging it makes that knight leave, plugging it
##    back in rejoins them.
##  - Armoured goblins: knights only (too spiky for the giant). Ogres: giant only (too big for knights).
## Modes (see docs/GAME_DEV_GUIDE.md): DUO_JOIN=<host> client, VR or DUO_HOST=1 host, else local split screen.

const W := preload("res://games/giants_table/world.gd")
const GiantScript := preload("res://games/giants_table/giant.gd")
const KnightScript := preload("res://games/giants_table/knight.gd")
const GoblinScript := preload("res://games/giants_table/goblin.gd")
const BoulderScript := preload("res://games/giants_table/boulder.gd")
const EmberScript := preload("res://games/giants_table/ember.gd")
const BoltScript := preload("res://games/giants_table/bolt.gd")
const VillageScript := preload("res://games/giants_table/village.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")

const MAX_EMBERS := 10
const BOULDER_COUNT := 8
const DOWN_GRACE := 20.0  # seconds the giant has to carry a knight to the fire when all knights are down
const FIRE_HOME := 2.6    # drop an ember this close to the fire and it goes home
const MAX_KNIGHTS := 6     # TV players 2..7 (player indices 1..6)
const KING_EVERY := 5     # the Goblin King comes every 5th wave
const RAIN_TIME := 16.0
## Extra sounds made with core/sfx.gd: [seconds, start Hz, end Hz, volume, wave, noise]
const EXTRA_SOUNDS := {
	"pop": [0.12, 900.0, 300.0, 0.35, "square", 0.6],
	"smack": [0.14, 300.0, 70.0, 0.55, "square", 0.7],
	"rain": [1.5, 2000.0, 1800.0, 0.12, "sine", 1.0],
	"build": [0.6, 220.0, 660.0, 0.3, "tri", 0.2],
	"cheer": [0.8, 520.0, 1250.0, 0.26, "tri", 0.45],
	"fanfare": [1.0, 392.0, 784.0, 0.35, "square", 0.0],
	"roar": [1.2, 160.0, 60.0, 0.6, "saw", 0.4],
	"sizzle": [0.6, 3000.0, 2500.0, 0.12, "square", 0.95],
}
const PLAYER_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(1.0, 0.72, 0.2), Color(1.0, 0.45, 0.75),
	Color(0.95, 0.3, 0.28), Color(0.68, 0.45, 1.0), Color(0.3, 0.92, 0.95), Color(0.96, 0.96, 0.92)]

var max_embers := MAX_EMBERS
var players: Array = []
var giant
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

var wave := 0
var score := 0
var embers := MAX_EMBERS
var spawn_queue: Array = []
var spawn_timer := 0.0
var break_timer := 4.0
var in_break := true
var game_over := false
var game_over_time := 0.0
var down_t := 0.0
var boulder_t := 0.0
var kills := {}  # how goblins were beaten (stats for tests)

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var fire_light: OmniLight3D
var flames: Array = []
var ember_orbs: Array = []
var fire_t := 0.0

# Split-screen views (a grid of SubViewports, laid out by _layout_views)
var view_root: Control
var views_dirty := true
var last_view_size := Vector2.ZERO
var view_count := 0
var lamp: DirectionalLight3D

# The growing village, weather, combos and stats.
var village: Node3D
var built := 0  # how many growth buildings stand (one per cleared wave)
var growth_root: Node3D
var growth_new: Node3D
var growth_sails: Node3D
var rain_t := 0.0
var rain_at := -1.0  # seconds into this wave when the rain cloud comes (-1 = not this wave)
var rain_drain := 0.0
var shield := false
var shield_said := false
var rain_node: Node3D
var wave_t := 0.0
var combo := 0
var last_kill_t := -10.0
var clock := 0.0
var stats: Array = []
var stats_label: Label
var stats_text := ""
var vr_hint: Label3D
var giant_tip := ""
var giant_tip_t := 0.0
var tips_said := {}
var help_panel: PanelContainer


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	vr_on = xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	if OS.has_environment("GT_FAKE_VR") and not OS.has_environment("DUO_JOIN"):
		vr_on = true  # tests: run the VR code paths headless, without a headset
	W.build(self, vr_on)
	village = VillageScript.new()
	village.main = self
	add_child(village)
	for i in MAX_KNIGHTS + 1:
		stats.append({"thrown": 0, "squashed": 0, "carried": 0, "caught": 0, "shield": 0.0, "kills": 0, "embers": 0, "revives": 0, "king": 0})
	_build_fire()
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
		_show_center("Connecting to the Giant…", 0.0)
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
		for i in BOULDER_COUNT:
			var a := TAU * (i + 0.5) / BOULDER_COUNT
			_spawn_boulder(Vector3(cos(a) * (W.R - 0.2), 0.0, sin(a) * (W.R - 0.2)), false)
	ready_to_play = true
	print("Giant's Table: %s mode" % mode)
	var knight_help := "KNIGHTS: left stick / W S move · right stick / A D turn · RT / Space sword · LT / F crossbow · A / Shift jump\n"
	if mode == "local":
		help_label.text = knight_help \
			+ "GIANT (left screen): mouse or 2nd controller moves the hand · hold left click / RT to grab · flick and let go to throw\n" \
			+ "More knights: press A on another controller (or Enter / arrow keys) to join, up to 6 knights\n" \
			+ "Armoured goblins: KNIGHTS only · Big ogres: GIANT only · Bring dropped embers home · The Giant can carry knights!\n" \
			+ "Balloon goblins: pop them with the crossbow · Goblin King: knights break his armour, then the Giant throws him · Rain: Giant, cover the fire!"
	else:
		help_label.text = knight_help \
			+ "More knights: press A or attack on any other controller (or Enter / arrow keys) to join, up to 6 knights  ·  The GIANT in VR grabs and throws goblins and boulders\n" \
			+ "Armoured goblins: KNIGHTS only · Big ogres: GIANT only · Bring dropped embers home · Stand by a fallen friend to revive them\n" \
			+ "Balloon goblins: pop them with the crossbow · Goblin King: knights break his armour, then the Giant throws him · Every wave the village grows!"
	if mode == "host":
		_show_center("Waiting for the knights to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED\nDefend the campfire!", 2.0)
	else:
		_show_center("GIANT'S TABLE\nDefend the campfire!", 2.5)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


func knights() -> Array:
	return players.slice(1)


# --- Players and views -------------------------------------------------------

func _build_players(mode: String) -> void:
	giant = GiantScript.new()
	giant.main = self
	giant.color = PLAYER_COLORS[0]
	add_child(giant)
	players.append(giant)
	_ensure_knights(mode)


## Every machine keeps a knight node for each TV slot (indices 1..MAX_KNIGHTS) so indices line up
## with net.gd and the snapshots. Slots 3+ sleep until someone joins. Called again from _process
## so a hot reload into an older session (fewer slots) grows the list lazily.
func _ensure_knights(mode: String) -> void:
	if giant == null:
		return
	while players.size() <= MAX_KNIGHTS:
		var i := players.size()
		var k := KnightScript.new()
		k.main = self
		k.index = i
		k.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		k.remote = mode == "host"
		k.key_set = i - 1 if i <= 2 else -1  # P2: WASD set, P3: arrows set, P4+: controller only
		k.claimed = i <= 2
		k.position = spawn_pos(i)
		add_child(k)
		players.append(k)
		if i >= 2:
			k.set_active(false)


## Where knight i (re)appears: P2/P3 in front of the fire as before, the others in a ring.
func spawn_pos(i: int) -> Vector3:
	match i:
		1:
			return Vector3(-1.2, 0.0, 3.2)
		2:
			return Vector3(1.2, 0.0, 3.2)
	var angles: Array[float] = [-0.85, 0.85, -1.6, 1.6]
	var a: float = angles[clampi(i - 3, 0, angles.size() - 1)]
	return Vector3(sin(a) * 3.4, 0.0, cos(a) * 3.4)


func active_knight_count() -> int:
	var n := 0
	for k in knights():
		if k.active:
			n += 1
	return maxi(n, 1)


func _build_views(mode: String) -> void:
	if vr_on and mode != "client":
		xr_interface = XRServer.find_interface("OpenXR")
		print("VR headset found: player 1 is the Giant")
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
		giant.setup_vr(origin, cam, left, right)
		_build_vr_mirror(cam)
	elif mode == "client":
		giant.setup_ghost()
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_root = Control.new()
	view_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(view_root)
	view_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not giant.vr and not giant.ghost:
		var vp := _add_view(giant)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		giant.setup_flat(cam, true)
	for k in knights():
		if not k.remote and k.active:
			_ensure_view(k)
	views_dirty = true
	_layout_views()


## A knight's own split-screen view + HUD, made the first time they're active on this machine.
func _ensure_view(k) -> void:
	if k.remote or k.has_meta("view") or view_root == null:
		return
	var vp := _add_view(k)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	k.attach_camera(cam)
	var hud := CanvasLayer.new()
	vp.add_child(hud)
	k.hud_label = _make_label(30)
	k.hud_label.add_theme_color_override("font_color", k.color.lightened(0.3))
	hud.add_child(k.hud_label)
	k.hint_label = _make_label(34)
	k.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(k.hint_label)
	_scale_hud(k, 1.0)
	views_dirty = true


## Per-view HUD, shrunk for small grid cells (s = 1 is the original 2-player layout).
func _scale_hud(k, s: float) -> void:
	if k.hud_label == null or k.hint_label == null:
		return
	if k.has_meta("hud_scale") and is_equal_approx(float(k.get_meta("hud_scale")), s):
		return
	k.set_meta("hud_scale", s)
	var fs := maxi(12, int(30 * s))
	var hl: Label = k.hud_label
	hl.add_theme_font_size_override("font_size", fs)
	hl.add_theme_constant_override("outline_size", maxi(4, int(fs / 4.0)))
	hl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hl.offset_top = -110.0 * s
	hl.offset_left = 30.0 * s
	var fs2 := maxi(12, int(34 * s))
	var hn: Label = k.hint_label
	hn.add_theme_font_size_override("font_size", fs2)
	hn.add_theme_constant_override("outline_size", maxi(4, int(fs2 / 4.0)))
	hn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hn.offset_left = -500.0 * s
	hn.offset_right = 500.0 * s
	hn.offset_top = -330.0 * s
	hn.offset_bottom = -200.0 * s


## Split-screen grid: 1 view full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (7 as 4x2: local mode
## with the flat giant plus six knights). More views = lower 3D resolution and cheaper shadows.
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
	if n > 2:
		hud_s = clampf(minf(cell.x / 958.0, cell.y / 1080.0) * 1.2, 0.45, 1.0)
	for i in n:
		var p = list[i]
		var c: SubViewportContainer = p.get_meta("view")
		var row := floori(float(i) / cols)
		var col := i - row * cols
		var in_row := mini(cols, n - row * cols)  # centre a short last row (3 views: 2 + 1)
		var x0 := (area.x - (cell.x * in_row + gap * (in_row - 1))) * 0.5
		c.position = Vector2(x0 + col * (cell.x + gap), row * (cell.y + gap))
		c.size = cell
		var vp := c.get_child(0) as SubViewport
		if vp:
			vp.scaling_3d_scale = scale3d
			vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
		if p != giant:
			_scale_hud(p, hud_s)
	_tune_shadows(n)


func _tune_shadows(n: int) -> void:
	if lamp == null:
		for c in get_children():
			if c is DirectionalLight3D:
				lamp = c
				break
	if lamp == null:
		return
	lamp.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if n <= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	lamp.directional_shadow_max_distance = 50.0 if n <= 4 else 30.0


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


## Low-res copy of the giant's VR view for gdev / people watching.
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
	cam.near = 0.4
	cam.far = 2000.0
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


## Players that get a controller automatically, in order (as in the 2-player game): client P2, P3;
## local P2 then the flat giant; a flat host's giant. Other controllers drop in by pressing A.
func _reserved_slots() -> Array:
	var slots: Array = []
	if players.size() > 1 and not players[1].remote:
		slots.append(players[1])
	if net.mode == "client" and players.size() > 2:
		slots.append(players[2])
	if giant.flat:
		slots.append(giant)
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
			request_leave(who)  # no keyboard to fall back on: the knight leaves until it's back
		return
	if pad_owner(device) >= 0:
		return
	print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
	# The same controller coming back: give it to its knight again (and rejoin them).
	for k in knights():
		if k.joy < 0 and int(k.get_meta("lost_pad", -1)) == device:
			k.joy = device
			k.remove_meta("lost_pad")
			if k.get_meta("rejoin", false):
				k.remove_meta("rejoin")
				request_join(k.index)
			return
	for p in _reserved_slots():
		if p.joy < 0:
			p.joy = device
			return
	# Otherwise it's a spare: pressing A on it joins the next free knight (see _input).


## Drop-in: a button on a controller nobody owns yet claims the next free knight slot.
func _input(event: InputEvent) -> void:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or not ready_to_play or game_over or net == null or net.mode == "host":
		return
	if b.button_index not in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER]:
		return
	if pad_owner(b.device) >= 0:
		return
	var k = _free_knight()
	if k == null:
		return
	k.joy = b.device
	k.claimed = true
	k.remove_meta("rejoin")
	k.remove_meta("lost_pad")
	print("Joypad %d drops in as P%d" % [b.device, k.index + 1])
	join_t = 1.0
	request_join(k.index)


func _free_knight():
	for k in knights():
		if not k.remote and not k.active and k.joy < 0 and not k.has_meta("lost_pad"):
			return k
	for k in knights():
		if not k.remote and not k.active and k.joy < 0:
			return k
	return null


func request_join(i: int) -> void:
	if i < 1 or i >= players.size():
		return
	var k = players[i]
	if not k.remote and not k.active:
		k.global_position = spawn_pos(i)
		k.face = 0.0
		k.cam_yaw = 0.0
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
	_ensure_knights(net.mode)
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


# --- Effects -----------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	return W.mat(color, glow)


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.12) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -16, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = W.mat(color, 1.5)
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
		for k in EXTRA_SOUNDS:
			var d: Array = EXTRA_SOUNDS[k]
			sfx.add_sound(k, d)
	sfx.play(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Floating 3D text, readable by the knights up close and by the giant from their seat.
func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 64
	l.outline_size = 18
	l.pixel_size = 0.009
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.2, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.7)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


## Something heavy hit the table: dust, a thump, and a buzz in the giant's nearest hand.
func add_thud(pos: Vector3, impact: float) -> void:
	if impact < 3.0:
		return
	burst(pos + Vector3.UP * 0.2, Color(0.85, 0.75, 0.55), int(clampf(impact, 6.0, 20.0)), 0.1)
	sound("hit", clampf(-14.0 + impact * 0.4, -14.0, 0.0), clampf(1.4 - impact * 0.02, 0.5, 1.4))
	if giant and giant.vr:
		giant.thud_haptic(pos, impact / 30.0)


# --- Campfire ----------------------------------------------------------------

func _build_fire() -> void:
	var logs := MeshInstance3D.new()
	var lm := W.cyl(0.13, 0.13, 1.3, 8)
	logs.mesh = lm
	logs.material_override = W.mat(Color(0.42, 0.25, 0.12))
	logs.rotation = Vector3(PI / 2.0, 0.6, 0.0)
	logs.position.y = 0.15
	add_child(logs)
	var logs2 := MeshInstance3D.new()
	logs2.mesh = lm
	logs2.material_override = logs.material_override
	logs2.rotation = Vector3(PI / 2.0, -0.6, 0.0)
	logs2.position.y = 0.22
	add_child(logs2)
	for spec in [[Color(1.0, 0.4, 0.1), 0.5, 1.4], [Color(1.0, 0.7, 0.2), 0.32, 1.0], [Color(1.0, 0.95, 0.6), 0.16, 0.6]]:
		var f := MeshInstance3D.new()
		f.mesh = W.cyl(0.0, spec[1], spec[2], 10)
		var m := W.mat(spec[0], 4.0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		f.material_override = m
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position.y = 0.25 + spec[2] * 0.5
		add_child(f)
		flames.append(f)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.6, 0.3)
	fire_light.light_energy = 2.5
	fire_light.omni_range = 9.0
	fire_light.position.y = 1.2
	add_child(fire_light)
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.4
	sparks.direction = Vector3.UP
	sparks.spread = 20.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.2
	sparks.gravity = Vector3(0, 0.5, 0)
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE * 0.05
	sm.material = W.mat(Color(1.0, 0.7, 0.3), 4.0)
	sparks.mesh = sm
	sparks.position.y = 0.8
	add_child(sparks)
	for i in MAX_EMBERS:
		var o := MeshInstance3D.new()
		o.mesh = W.sphere(0.13, 8)
		o.material_override = W.mat(Color(1.0, 0.6, 0.2), 4.0)
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(o)
		ember_orbs.append(o)


func _update_fire(delta: float) -> void:
	fire_t += delta
	var strength := clampf(float(embers) / MAX_EMBERS, 0.0, 1.0)
	for i in flames.size():
		var f: MeshInstance3D = flames[i]
		var flick := 1.0 + sin(fire_t * (9.0 + i * 3.0)) * 0.08 + sin(fire_t * 23.0 + i) * 0.05
		var s := (0.35 + 0.65 * strength) * flick
		f.scale = Vector3(s, s * (1.0 + 0.1 * sin(fire_t * 13.0 + i)), s)
		f.visible = embers > 0
	fire_light.light_energy = (0.6 + 2.2 * strength) * (1.0 + sin(fire_t * 17.0) * 0.08)
	for i in ember_orbs.size():
		var o: MeshInstance3D = ember_orbs[i]
		o.visible = i < embers
		var a := fire_t * 0.8 + TAU * i / MAX_EMBERS
		o.position = Vector3(cos(a) * 1.45, 1.3 + sin(fire_t * 2.0 + i) * 0.15, sin(a) * 1.45)


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(1 if _king_alive() else maxi(wave - 1, 0) / 2)
	clock += delta
	_update_fire(delta)
	_update_growth()
	_update_rain_visuals(delta)
	_update_knight_hints()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ensure_knights(net.mode)
	_layout_views()
	_update_hud()
	_update_vr_center()
	if net.mode == "local":
		_check_join()
	if net.mode == "client":
		_check_join()
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		if game_over_time > 1.5 and (_restart_pressed() or giant.restart_held()):
			get_tree().reload_current_scene()
		return
	if net.mode == "host" and not net.connected:
		return  # hold the waves until the knights join
	_host_knights(delta)
	_update_boulders(delta)
	_update_rain(delta)
	_update_giant_tips(delta)
	if not in_break:
		wave_t += delta
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
	elif not spawn_queue.is_empty():
		spawn_timer -= delta
		var alive := get_tree().get_nodes_in_group("goblins").size()
		var extra := _extra_knights()
		if spawn_timer <= 0.0 and alive < mini(6 + wave * 2, 18) + extra * 3:
			_spawn_goblin(spawn_queue.pop_back())
			spawn_timer = maxf(0.5, 1.6 - wave * 0.08) / (1.0 + 0.15 * extra)
	elif get_tree().get_nodes_in_group("goblins").is_empty():
		_end_wave()
	_check_lose(delta)


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for k in knights():
		if not k.remote and k.active and k.any_attack_held():
			return true
	return false


## TV / split screen: a sleeping knight whose controller (or keyboard set) presses attack or A joins.
## P3 = 2nd controller or arrows + Enter, as before; P4-P7 are claimed by spare controllers in _input.
var join_t := 0.0
func _check_join() -> void:
	join_t -= get_process_delta_time()
	if join_t > 0.0 or game_over:
		return
	for k in knights():
		if k.active or k.remote or not k.claimed:
			continue
		if k.any_attack_held() or (k.joy >= 0 and k.jump_held()):
			join_t = 1.0
			request_join(k.index)
			return


## Knights beyond the original two: used to scale the waves up a little for a big party.
func _extra_knights() -> int:
	return maxi(0, active_knight_count() - 2)


# --- Waves -------------------------------------------------------------------

func _start_wave() -> void:
	wave += 1
	in_break = false
	wave_t = 0.0
	rain_at = randf_range(10.0, 22.0) if wave >= 3 and (wave % 2 == 1 or randf() < 0.4) else -1.0
	print("Wave %d started" % wave)
	spawn_queue.clear()
	# 1-2 knights: the original waves. Each extra knight adds ~30% goblins and ~35% armoured ones
	# (knight work); ogres are the giant's job, so only a big party gets one more.
	var party := _extra_knights()
	for i in roundi((3 + wave * 2) * (1.0 + 0.3 * party)):
		spawn_queue.append("goblin")
	if wave >= 2:
		for i in roundi(mini(wave - 1, 6) * (1.0 + 0.35 * party)):
			spawn_queue.append("armored")
	if wave >= 3:
		for i in 1 + (wave - 3) / 3 + (1 if party >= 3 and wave >= 4 else 0):
			spawn_queue.append("ogre")
	if wave >= 4:
		for i in roundi((2 + mini(wave - 4, 4)) * (1.0 + 0.3 * party)):
			spawn_queue.append("balloon")
	spawn_queue.shuffle()
	if wave % KING_EVERY == 0:
		spawn_queue.insert(0, "king")  # pop_back: the king comes last, after his army
	spawn_queue.append("goblin")  # the first one out is always an easy one
	spawn_timer = 0.5
	sound("wave")
	var extra := ""
	if wave == 2:
		extra = "\nArmoured goblins! Only KNIGHTS can beat them"
	elif wave == 3:
		extra = "\nAn OGRE! Only the GIANT can lift it - throw it off the table!"
	elif wave == 4:
		extra = "\nBALLOON GOBLINS from the sky!\nGiant: pluck them out of the air  ·  Knights: pop the balloons!"
	elif wave % KING_EVERY == 0:
		extra = "\nTHE GOBLIN KING IS COMING!\nKnights break his armour, then the Giant throws him!"
	_show_center("WAVE %d%s" % [wave, extra], 3.0 if extra != "" else 1.4)
	if wave == 2:
		create_tween().tween_property(help_label, "modulate:a", 0.0, 1.0)


func _end_wave() -> void:
	in_break = true
	break_timer = 6.0
	rain_t = 0.0
	embers = mini(embers + 1, MAX_EMBERS)
	for k in knights():
		if not k.active:
			continue
		if k.is_down:
			_revive(k, 0.6)
		else:
			k.hp = minf(KnightScript.MAX_HP, k.hp + 30.0)
	var grew := ""
	if built < W.GROWTH.size():
		var g: Array = W.GROWTH[built]
		grew = "\nThe village grows: %s!" % W.GROWTH_NAMES[g[0]]
		built += 1
		sound("build", -2.0)
		net.event("grow", [built])
		_grow_fx(built)
	_show_center("WAVE %d CLEARED!\nThe campfire grows: +1 ember%s" % [wave, grew], 3.2)
	sound("clear")
	sound("cheer", -4.0)
	village.cheer()
	net.event("cheer", [])


func _spawn_goblin(kind: String) -> void:
	var a := randf() * TAU
	var dir := Vector3(cos(a), 0.0, sin(a))
	var g := GoblinScript.new()
	g.setup(kind, self)
	g.net_id = next_net_id()
	if kind == "balloon":
		# Floats in from the sky and drifts down towards the village.
		var start := dir * randf_range(7.0, 11.0) + Vector3.UP * 13.0
		var land := dir * randf_range(3.0, 4.5)
		land.y = W.height(land.x, land.z)
		g.floating = true
		g.position = start
		var fall_time := (start.y - land.y) / GoblinScript.BALLOON_FALL
		g.drift = Vector3(land.x - start.x, 0.0, land.z - start.z) / fall_time
		add_child(g)
		g.rotation.y = atan2(dir.x, dir.z)
		if not tips_said.has("balloon"):
			tips_said["balloon"] = true
			_giant_tip("BALLOON GOBLINS! Grab them out of the air (right trigger)!")
		return
	if kind == "king":
		g.max_armor = 8.0 + 2.0 * _extra_knights()
		g.armor = g.max_armor
	g.position = dir * (W.EDGE - 0.3) + Vector3.DOWN * 1.0
	add_child(g)
	g.rotation.y = atan2(dir.x, dir.z)
	g.flying = true
	g.hop = true
	g.vel = -dir * 2.5 + Vector3.UP * 11.0
	if kind == "king":
		sound("roar", 0.0, 0.8)
		sound("fanfare", -4.0, 0.7)
		_show_center("THE GOBLIN KING!\nKnights: hit him to break his armour!", 2.5)
		_giant_tip("THE GOBLIN KING! His armour is too spiky - let the knights break it first")


func _check_lose(delta: float) -> void:
	# The fire goes out when no embers are left anywhere to win back.
	if embers <= 0:
		var recoverable := not get_tree().get_nodes_in_group("embers").is_empty()
		for g in get_tree().get_nodes_in_group("goblins"):
			if g.carrying:
				recoverable = true
		for k in knights():
			if k.carrying:
				recoverable = true
		if not recoverable:
			_on_game_over("The goblins stole the campfire!")
			return
	var any_active := false
	var any_up := false
	for k in knights():
		if k.active:
			any_active = true
			if not k.is_down:
				any_up = true
	if any_active and not any_up:
		var before := int(DOWN_GRACE - down_t)
		down_t += delta
		var left := int(DOWN_GRACE - down_t)
		if left != before:
			_show_center("ALL KNIGHTS ARE DOWN!\nGiant: carry a knight to the campfire!  %d" % maxi(left, 0), 0.0)
		if down_t >= DOWN_GRACE:
			_on_game_over("All the knights fell asleep!")
	elif down_t > 0.0:
		down_t = 0.0
		_show_center("", 0.0)


func _on_game_over(reason: String) -> void:
	if game_over:
		return
	game_over = true
	game_over_time = 0.0
	giant.release_all()
	print("Game over: %s wave=%d score=%d" % [reason, wave, score])
	sound("gameover")
	var how := "Press A / X (VR) or attack (knights) to play again"
	_show_center("GAME OVER\n%s\nWave %d   ·   Score %d   ·   Village %d/%d\n%s" % [reason, wave, score, built, W.GROWTH.size(), how], 0.0)
	_show_stats("HEROES OF THE VILLAGE")


# --- Goblins -----------------------------------------------------------------

func goblin_steals(g) -> void:
	if embers <= 0 or g.carrying:
		return
	embers -= 1
	g.carrying = true
	var away := Vector3(g.global_position.x, 0.0, g.global_position.z)
	if away.length() < 0.1:
		away = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	g.flee_target = away.normalized() * (W.EDGE + 3.0)
	sound("spit", -2.0, 0.9)
	popup(g.grab_center() + Vector3.UP * 0.8, "Ember stolen!", Color(1.0, 0.55, 0.3))


func goblin_takes_loose_ember(g, e) -> void:
	if g.carrying:
		return
	e.queue_free()
	g.carrying = true
	var away := Vector3(g.global_position.x, 0.0, g.global_position.z)
	g.flee_target = away.normalized() * (W.EDGE + 3.0)
	sound("spit", -4.0, 1.1)


func goblin_escaped(g) -> void:
	if g.has_meta("dead"):
		return
	g.set_meta("dead", true)
	popup(g.grab_center() + Vector3.UP * 0.8, "An ember got away!", Color(1.0, 0.4, 0.3))
	sound("hurt", -2.0, 0.6)
	g.queue_free()


func goblin_defeated(g, how: String, by) -> void:
	if g.has_meta("dead"):
		return
	g.set_meta("dead", true)
	var points: int = GoblinScript.KINDS[g.kind].points
	score += points
	var stat_key := "%s:%s" % [g.kind, how]
	kills[stat_key] = kills.get(stat_key, 0) + 1
	# Who gets the credit (for the end-of-game awards).
	if by != null and by is Node and by.is_in_group("knights"):
		stats[by.index].kills += 1
	elif how == "fell":
		stats[0].thrown += 1
	elif how in ["squash", "slam", "boulder", "smack"]:
		stats[0].squashed += 1
	# Quick knock-outs in a row make a combo.
	if clock - last_kill_t < 2.5:
		combo += 1
	else:
		combo = 1
	last_kill_t = clock
	if combo >= 3:
		var bonus := combo * 5
		score += bonus
		popup(g.grab_center() + Vector3.UP * 1.6, "COMBO x%d!  +%d" % [combo, bonus], Color(1.0, 0.55, 0.9))
		if combo == 3 or combo % 5 == 0:
			sound("cheer", -6.0, 1.0 + combo * 0.03)
	var pos: Vector3 = g.global_position
	var center: Vector3 = g.grab_center()
	var c: Color = g.color
	burst(center, c, 18 if g.kind != "ogre" else 34, 0.12 if g.kind != "ogre" else 0.22)
	burst(center, Color(1.0, 0.95, 0.7), 8, 0.08)
	if g.kind == "ogre":
		sound("big_kill", -2.0, 1.2)
	else:
		sound("kill", -6.0, randf_range(1.1, 1.4))
	var words := {"squash": "SQUASH!", "fell": "BYE BYE!", "slam": "BOOM!", "boulder": "BONK!", "knight": "POW!", "smack": "SMACK!"}
	popup(center + Vector3.UP * 0.5, "%s +%d" % [words.get(how, "POW!"), points], c.lightened(0.4))
	if how in ["squash", "slam", "boulder"]:
		add_thud(pos, 12.0)
	if g.carrying:
		if how != "fell" and Vector2(pos.x, pos.z).length() < W.EDGE and pos.y > -2.0:
			var gh := W.height(pos.x, pos.z)
			_spawn_ember(Vector3(pos.x, maxf(gh, 0.0), pos.z))
		else:
			embers = mini(embers + 1, MAX_EMBERS)
			popup(Vector3(0.0, 2.6, 0.0), "The ember flew home!", Color(1.0, 0.75, 0.35))
	if g.kind == "king":
		score += 100
		sound("fanfare", 0.0, 1.0)
		sound("cheer", 0.0)
		_show_center("THE GOBLIN KING IS BEATEN!\n+300  ·  The village is saved!", 3.0)
		for i in 5:
			var p := Vector3(randf_range(-6.0, 6.0), randf_range(4.0, 7.0), randf_range(-6.0, 6.0))
			get_tree().create_timer(0.3 + i * 0.4).timeout.connect(func() -> void:
				burst(p, Color.from_hsv(randf(), 0.7, 1.0), 26, 0.16)
				sound("pop", -6.0, randf_range(0.8, 1.3)))
		village.cheer()
		net.event("cheer", [])
		print("The Goblin King is beaten")
	g.queue_free()


## The giant plucked a balloon goblin out of the sky.
func on_balloon_caught(g) -> void:
	stats[0].caught += 1
	score += 5
	popup(g.grab_center() + Vector3.UP * 1.0, "GOTCHA! +5", Color(0.6, 0.9, 1.0))
	sound("pop", 0.0, 1.0)


## A knight's bolt popped a balloon: down he goes!
func on_balloon_popped(g, knight) -> void:
	score += 5
	sound("pop", 0.0, 1.2)
	if knight != null and knight is Node and knight.is_in_group("knights"):
		stats[knight.index].kills += 1


## A knight dented the Goblin King's armour.
func king_hit(g, knight) -> void:
	if knight != null and knight is Node and knight.is_in_group("knights"):
		stats[knight.index].king += 1
	if g.armor <= 0.0:
		burst(g.grab_center() + Vector3.UP * 0.4, Color(0.8, 0.82, 0.9), 30, 0.14)
		sound("big_kill", -2.0, 1.4)
		_show_center("THE KING'S ARMOUR IS BROKEN!\nGIANT: grab him and throw him off the table!", 2.5)
		_giant_tip("His armour is broken! GRAB the Goblin King and THROW him off the table!")
		print("The Goblin King's armour is broken")
	else:
		popup(g.grab_center() + Vector3.UP * 1.4, "CLANG!  armour %d" % ceili(g.armor), Color(0.85, 0.9, 1.0))


## An open giant hand came down fast on a goblin.
func giant_smack(g, at: Vector3) -> void:
	var spiky: bool = g.kind == "armored" or (g.kind == "king" and g.armor > 0.0)
	if spiky:
		popup(g.grab_center() + Vector3.UP * 0.9, "OUCH! Too spiky!\nKnights, get this one!", Color(1.0, 0.6, 0.5))
		sound("hurt", -6.0, 0.7)
		g.dizzy_t = 1.0
		return
	burst(at, Color(0.85, 0.75, 0.55), 10, 0.1)
	sound("smack", 0.0, randf_range(0.9, 1.1))
	if g.is_big():
		g.dizzy_t = 2.5
		popup(g.grab_center() + Vector3.UP * 1.4, "OOF! Now THROW me!", Color(1.0, 0.8, 0.4))
		return
	goblin_defeated(g, "smack", giant)


func _king_alive() -> bool:
	for g in get_tree().get_nodes_in_group("goblins"):
		if g.kind == "king":
			return true
	return false


# --- Weather: a rain cloud over the campfire -------------------------------------

## Host: the rain puts embers out unless the giant holds a hand over the fire like an umbrella.
func _update_rain(delta: float) -> void:
	if not in_break and rain_at > 0.0 and wave_t >= rain_at and rain_t <= 0.0:
		rain_at = -1.0
		rain_t = RAIN_TIME
		rain_drain = 0.0
		shield_said = false
		sound("rain", -4.0, 1.0)
		_show_center("A RAIN CLOUD!\nGiant: hold your hand over the campfire to keep it dry!", 2.5)
		_giant_tip("RAIN! Hold your open hand over the campfire, like an umbrella!")
		print("Rain cloud over the campfire")
	shield = false
	if rain_t <= 0.0:
		return
	rain_t -= delta
	for h in giant.hands:
		if Vector2(h.pos.x, h.pos.z).length() < 2.6 and h.pos.y > 0.8 and h.pos.y < 10.0:
			shield = true
	if shield:
		stats[0].shield += delta
		if not shield_said:
			shield_said = true
			popup(Vector3(0.0, 3.2, 0.0), "Nice umbrella, Giant!", Color(0.7, 0.9, 1.0))
	else:
		rain_drain += delta
		if rain_drain >= 5.0:
			rain_drain = 0.0
			if embers > 1:
				embers -= 1
				sound("sizzle", 0.0, 1.0)
				popup(Vector3(0.0, 2.8, 0.0), "HISS! The rain put out an ember!", Color(0.6, 0.8, 1.0))
	if rain_t <= 0.0:
		_show_center("The rain stopped. Phew!", 1.5)


## Both machines: the cloud and the raindrops (and a dimmer fire) while it rains.
func _update_rain_visuals(delta: float) -> void:
	if rain_node == null:
		rain_node = Node3D.new()
		add_child(rain_node)
		var puffs: Array = []
		for i in 6:
			var a := TAU * i / 6.0
			puffs.append(Transform3D(Basis().scaled(Vector3(1.0, 0.65, 1.0)), Vector3(cos(a) * 1.5, randf_range(-0.2, 0.3), sin(a) * 1.3)))
		puffs.append(Transform3D(Basis().scaled(Vector3(1.3, 0.8, 1.3)), Vector3(0, 0.4, 0)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = W.sphere(1.3, 10)
		mm.instance_count = puffs.size()
		for i in puffs.size():
			var xf: Transform3D = puffs[i]
			mm.set_instance_transform(i, xf)
		var cloud := MultiMeshInstance3D.new()
		cloud.multimesh = mm
		cloud.material_override = W.mat(Color(0.55, 0.58, 0.68))
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rain_node.add_child(cloud)
		var drops := CPUParticles3D.new()
		drops.name = "Drops"
		drops.amount = 60
		drops.lifetime = 0.55
		drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		drops.emission_box_extents = Vector3(2.0, 0.1, 2.0)
		drops.direction = Vector3.DOWN
		drops.spread = 2.0
		drops.initial_velocity_min = 14.0
		drops.initial_velocity_max = 16.0
		drops.gravity = Vector3(0, -10, 0)
		drops.position.y = -0.6
		var dm := W.box(Vector3(0.03, 0.3, 0.03))
		dm.material = W.mat(Color(0.6, 0.8, 1.0), 1.0)
		drops.mesh = dm
		rain_node.add_child(drops)
	rain_node.visible = rain_t > 0.0
	if rain_node.visible:
		rain_node.position = Vector3(sin(clock * 0.4) * 0.6, 9.5 + sin(clock * 0.9) * 0.2, cos(clock * 0.3) * 0.6)
		var drops := rain_node.get_node("Drops") as CPUParticles3D
		drops.emitting = not shield


# --- The growing village -------------------------------------------------------------

## Both machines: the growth buildings that stand (rebuilt when the count changes).
func _update_growth() -> void:
	if growth_root != null and int(growth_root.get_meta("built", -1)) == built:
		return
	if growth_root != null:
		growth_root.queue_free()
	if growth_new != null:
		growth_new.queue_free()
		growth_new = null
	growth_root = Node3D.new()
	growth_root.set_meta("built", built)
	add_child(growth_root)
	var out := {}
	var settled: int = built if not has_meta("grow_anim") else built - 1
	W.build_growth(growth_root, 0, settled, out)
	if settled < built:
		# The newest building rises out of the ground.
		growth_new = Node3D.new()
		add_child(growth_new)
		W.build_growth(growth_new, built - 1, built, out)
		growth_new.position.y = -3.5
		var tw := growth_new.create_tween()
		tw.tween_property(growth_new, "position:y", 0.0, 2.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		remove_meta("grow_anim")
	growth_sails = out.get("sails")


## The next building rises with a puff of dust and sparkles.
func _grow_fx(n: int) -> void:
	set_meta("grow_anim", true)
	var g: Array = W.GROWTH[n - 1]
	var x: float = g[1]
	var z: float = g[2]
	var p := Vector3(x, W.height(x, z), z)
	burst(p + Vector3.UP * 0.5, Color(0.85, 0.75, 0.55), 24, 0.14)
	burst(p + Vector3.UP * 2.0, Color(1.0, 0.9, 0.5), 16, 0.1)
	popup(p + Vector3.UP * 3.5, "NEW: %s!" % W.GROWTH_NAMES[g[0]].substr(2) if W.GROWTH_NAMES[g[0]].begins_with("a ") else "NEW BUILDING!", Color(1.0, 0.9, 0.55))


# --- Hints ---------------------------------------------------------------------------

## A tip for the VR giant, shown on the floating hint panel for a few seconds.
func _giant_tip(text: String) -> void:
	giant_tip = text
	giant_tip_t = 6.0


## Host: first-time tips for the giant as new things happen.
func _update_giant_tips(delta: float) -> void:
	giant_tip_t -= delta
	if giant_tip_t > 0.0:
		return
	var tip := ""
	var key := ""
	for g in get_tree().get_nodes_in_group("goblins"):
		if g.kind == "ogre" and not g.held and not tips_said.has("ogre"):
			tip = "An OGRE! Knights can't beat it: GRAB it (right trigger) and THROW it off the table!"
			key = "ogre"
		elif g.kind == "armored" and not tips_said.has("armored"):
			tip = "Armoured goblins are too spiky to hold - drop a BOULDER on them, the knights will finish them"
			key = "armored"
	for k in knights():
		if k.active and k.is_down and not k.carried and not tips_said.has("down"):
			tip = "A knight is DOWN! Pick them up and carry them to the campfire"
			key = "down"
	if wave == 1 and wave_t > 3.0 and not tips_said.has("smack"):
		tip = "Grab goblins with your RIGHT trigger and throw them off the table - or SMACK them flat with an open hand!"
		key = "smack"
	if wave == 2 and wave_t > 6.0 and not tips_said.has("boulder"):
		tip = "Set BOULDERS down to block the goblins, or as stepping stones over the river for the knights"
		key = "boulder"
	if key != "":
		tips_said[key] = true
		_giant_tip(tip)


## TV: a short contextual tip under each knight's view ("how do I…?").
func _update_knight_hints() -> void:
	for k in knights():
		if k.hint_label == null or not k.active or k.remote:
			continue
		if k.is_down or k.carried:
			continue  # knight.gd shows its own message
		var tip := ""
		var pos: Vector3 = k.global_position
		var near_d := 7.0
		for g in get_tree().get_nodes_in_group("goblins"):
			var d: float = g.global_position.distance_to(pos)
			if d > near_d:
				continue
			if g.kind == "king" and g.armor > 0.0:
				tip = "THE GOBLIN KING! Hit him with your sword to break his armour!"
				near_d = d
			elif g.kind == "king" or g.kind == "ogre":
				tip = "Too big for knights! The GIANT must throw it off the table"
				near_d = d
			elif g.kind == "armored":
				tip = "ARMOURED goblin: only knights can beat it - SWORD it (RT / Space)!"
				near_d = d
			elif g.floating:
				tip = "Pop the BALLOON with your crossbow (LT / F)!"
				near_d = d
		if tip == "" and k.carrying:
			tip = "Take the ember back to the CAMPFIRE in the middle!"
		if tip == "":
			for e in get_tree().get_nodes_in_group("embers"):
				if e.global_position.distance_to(pos) < 6.0:
					tip = "A dropped EMBER! Walk over it to pick it up"
		if tip == "" and rain_t > 0.0:
			tip = "RAIN! Keep the goblins busy while the Giant shields the fire"
		k.hint_label.text = tip


# --- Stats and awards ------------------------------------------------------------------

func _award(i: int) -> String:
	var st: Dictionary = stats[i]
	if i == 0:
		var best := "GENTLE GIANT"
		var top := 0.0
		for cat in [["thrown", "GOBLIN BOWLER", 1.0], ["squashed", "SQUISHER", 1.0], ["caught", "SKY CATCHER", 2.0],
				["carried", "KNIGHT TAXI", 3.0], ["shield", "HUMAN UMBRELLA", 0.4]]:
			var v := float(st[cat[0]]) * float(cat[2])
			if v > top:
				top = v
				best = cat[1]
		return best
	var cats := [["kills", "GOBLIN BASHER"], ["embers", "EMBER HERO"], ["revives", "LIFESAVER"], ["king", "KING BREAKER"]]
	var best2 := "BRAVE KNIGHT"
	var best_score := 0.0
	for cat in cats:
		var key: String = cat[0]
		var mine := float(st[key])
		if mine <= 0.0:
			continue
		var top2 := 0.0
		for j in range(1, players.size()):
			top2 = maxf(top2, float(stats[j][key]))
		var sc := mine / maxf(1.0, top2) + (0.4 if key != "kills" else 0.0)
		if sc > best_score:
			best_score = sc
			best2 = cat[1]
	return best2


func _stats_lines() -> String:
	var lines: Array[String] = []
	var g: Dictionary = stats[0]
	lines.append("GIANT  ·  %d thrown off  ·  %d squashed  ·  %d caught  ·  %d knights carried   -   %s!" % [g.thrown, g.squashed, g.caught, g.carried, _award(0)])
	for k in knights():
		var st: Dictionary = stats[k.index]
		if not k.active and st.kills + st.embers + st.revives == 0:
			continue
		lines.append("P%d  ·  %d goblins  ·  %d embers home  ·  %d friends revived   -   %s!" % [k.index + 1, st.kills, st.embers, st.revives, _award(k.index)])
	return "\n".join(lines)


func _show_stats(title: String) -> void:
	_apply_stats(title + "\n" + _stats_lines())
	net.event("stats", [stats_text])
	print("Stats:\n" + stats_text)


func _apply_stats(text: String) -> void:
	stats_text = text
	if stats_label:
		stats_label.text = text


# --- Knights (host side) -----------------------------------------------------

func knight_action(k, action: String, args: Array) -> void:
	if net.mode == "client":
		net.send_action(action, args, k.index)
	else:
		do_knight_action(k.index, action, args)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index < 1 or index >= players.size():
		return
	match action:
		"join":
			var k = players[index]
			if not k.active:
				k.set_active(true)
				k.hp = KnightScript.MAX_HP
				k.carrying = false
				k.carried = false
				if k.is_down:
					k.set_down(false)
				if k.remote:
					var at := Vector3(1.5, 0.0, 3.0) if index == 2 else spawn_pos(index)
					k.global_position = at
					k.net_target = at
				on_player_activity_changed(k)
				_show_center("PLAYER %d JOINED!" % (index + 1), 1.5)
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			var k = players[index]
			if k.active:
				_knight_leaves(k)
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A knight opened the menu")
			get_tree().paused = paused
		_:
			do_knight_action(index, action, args)


## A knight leaves (controller unplugged, or the TV went away): drop what they carry and sleep.
func _knight_leaves(k) -> void:
	if giant:
		for h in giant.hands:
			if h.held == k:
				giant._release(h)
	if k.carrying:
		_spawn_ember(k.global_position + Vector3.UP * 0.05)
	k.carrying = false
	k.carried = false
	k.held = false
	if k.is_down:
		k.set_down(false)
	k.hp = KnightScript.MAX_HP
	k.revive_progress = 0.0
	k.set_active(false)
	on_player_activity_changed(k)
	popup(k.global_position + Vector3.UP * 1.6, "P%d left - see you soon!" % (k.index + 1), k.color)
	print("P%d left the game" % (k.index + 1))


func do_knight_action(index: int, action: String, args: Array) -> void:
	var k = players[index]
	if not k.active or k.is_down or game_over:
		return
	match action:
		"swing":
			var pos: Vector3 = args[0]
			var f: float = args[1]
			var fwd := Basis(Vector3.UP, f) * Vector3(0, 0, -1)
			if k.remote:
				k.swing_t = 0.25
				k.sword_cd = KnightScript.SWORD_CD
			var hit := false
			for g in get_tree().get_nodes_in_group("goblins"):
				if g.held or g.has_meta("dead"):
					continue
				var to: Vector3 = g.global_position - pos
				to.y = 0.0
				var d := to.length()
				var reach: float = 1.25 + g.radius
				if d > reach or absf(g.global_position.y - pos.y) > 1.5:
					continue
				if d > 0.3 and fwd.dot(to / d) < 0.25:
					continue
				g.hit_by_knight(2.0, to / maxf(d, 0.01), k)
				hit = true
			if hit:
				burst(pos + fwd * 0.9 + Vector3.UP * 0.5, Color(1.0, 1.0, 0.85), 8, 0.06)
		"shoot":
			var origin: Vector3 = args[0]
			var dir: Vector3 = args[1]
			spawn_bolt(origin, dir, k, false)


func spawn_bolt(origin: Vector3, dir: Vector3, shooter, visual_only: bool) -> void:
	var b := BoltScript.new()
	b.main = self
	b.shooter = shooter
	b.visual_only = visual_only
	add_child(b)
	b.global_position = origin
	b.launch(dir)


## Nudges a knight's aim towards a goblin roughly in front of them.
func auto_aim(from: Vector3, dir: Vector3) -> Vector3:
	var best := dir
	var best_dot := cos(deg_to_rad(28.0))
	for g in get_tree().get_nodes_in_group("goblins"):
		var to: Vector3 = g.grab_center() - from
		var dist := to.length()
		if dist < 0.3 or dist > 16.0:
			continue
		var flat_dir := Vector3(to.x, 0.0, to.z).normalized()
		var d := dir.dot(flat_dir)
		if d > best_dot:
			best_dot = d
			best = (to + Vector3.UP * dist * dist * 0.004).normalized()
	return best


func knight_hurt(k, dmg: float, from: Vector3) -> void:
	if k.is_down or k.carried or not k.active or game_over:
		return
	k.hp -= dmg
	k.on_hurt(from)
	net.event("hurt", [k.index, from])
	sound("hurt", -6.0, 1.0 + k.index * 0.15)
	if k.hp <= 0.0:
		k.hp = 0.0
		k.set_down(true)
		k.revive_progress = 0.0
		sound("down", -2.0)
		burst(k.global_position + Vector3.UP * 0.5, k.color, 18)
		popup(k.global_position + Vector3.UP * 1.6, "P%d is down!" % (k.index + 1), k.color)
		print("P%d is down" % (k.index + 1))
		if k.carrying:
			k.carrying = false
			_spawn_ember(k.global_position + Vector3.UP * 0.05)


func _revive(k, fraction: float) -> void:
	print("P%d is back on their feet" % (k.index + 1))
	k.set_down(false)
	k.hp = KnightScript.MAX_HP * fraction
	k.revive_progress = 0.0
	burst(k.global_position + Vector3.UP * 0.6, Color(0.6, 1.0, 0.6), 18)
	sound("revive", -2.0)
	popup(k.global_position + Vector3.UP * 1.6, "Back on your feet!", Color(0.7, 1.0, 0.7))


func _host_knights(delta: float) -> void:
	for k in knights():
		if not k.active:
			continue
		var pos: Vector3 = k.global_position
		var fire_d := Vector2(pos.x, pos.z).length()
		if k.carried and not k.held:
			_fall_knight(k, delta)
			continue
		if k.carried:
			continue
		if k.is_down:
			var helper := false
			for o in knights():
				if o != k and o.active and not o.is_down and not o.carried and o.global_position.distance_to(pos) < KnightScript.REVIVE_RANGE:
					helper = true
			if helper or fire_d < 2.6:
				k.revive_progress += delta / KnightScript.REVIVE_TIME
			else:
				k.revive_progress = maxf(0.0, k.revive_progress - delta * 0.2)
			if k.revive_progress >= 1.0:
				for o in knights():
					if o != k and o.active and not o.is_down and o.global_position.distance_to(pos) < KnightScript.REVIVE_RANGE:
						stats[o.index].revives += 1
				_revive(k, 0.6)
			continue
		if fire_d < 3.0:
			k.hp = minf(KnightScript.MAX_HP, k.hp + 5.0 * delta)  # warm by the fire
		if not k.carrying:
			for e in get_tree().get_nodes_in_group("embers"):
				if e.held or e.flying or e.is_queued_for_deletion():
					continue
				if e.global_position.distance_to(pos) < 0.9:
					e.queue_free()
					k.carrying = true
					sound("pickup", -4.0)
					popup(pos + Vector3.UP * 1.8, "Got an ember!", Color(1.0, 0.75, 0.35))
					break
		elif fire_d < 2.4:
			k.carrying = false
			embers = mini(embers + 1, MAX_EMBERS)
			stats[k.index].embers += 1
			score += 5
			sound("revive", -4.0, 1.3)
			popup(Vector3(0.0, 2.4, 0.0), "Ember home! +5", Color(1.0, 0.8, 0.4))


## A knight the giant let go of floats down (knights are light: no fall damage).
func _fall_knight(k, delta: float) -> void:
	k.fall_vel.y = maxf(k.fall_vel.y - 30.0 * delta, -11.0)
	k.fall_vel.x *= 1.0 - minf(1.0, delta * 1.5)
	k.fall_vel.z *= 1.0 - minf(1.0, delta * 1.5)
	var p: Vector3 = k.global_position + k.fall_vel * delta
	var g := W.height(p.x, p.z)
	for b in get_tree().get_nodes_in_group("boulders"):
		if b.held or b.flying:
			continue
		var bp: Vector3 = b.global_position
		if Vector2(p.x - bp.x, p.z - bp.z).length() < b.radius:
			g = maxf(g, bp.y + b.radius * 1.8)
	if g < -50.0 and p.y < -4.0:
		p = Vector3(0.0, 0.0, 2.4)
		k.carried = false
		popup(p + Vector3.UP * 1.6, "Whoops! Back to the campfire", k.color)
		sound("revive", -6.0, 0.8)
	elif p.y <= g:
		p = W.push_out(Vector3(p.x, g, p.z), KnightScript.BODY_R)
		p.y = maxf(W.height(p.x, p.z), g)
		k.carried = false
		sound("dash", -8.0, 0.7)
	k.global_position = p
	k.net_target = p
	if not k.carried and k.is_down and Vector2(p.x, p.z).length() < 3.2:
		stats[0].carried += 1
		_revive(k, 0.8)


func on_grabbed(obj) -> void:
	sound("pickup", -6.0, 0.8 if obj.is_in_group("boulders") else 1.2)
	if obj.is_in_group("knights"):
		popup(obj.grab_center() + Vector3.UP * 1.2, "Wheee!", obj.color)
	elif obj.is_in_group("goblins") and randf() < 0.5:
		popup(obj.grab_center() + Vector3.UP * 0.9, ["Eek!", "Put me down!", "Help!"].pick_random(), Color(0.7, 1.0, 0.5))


func on_released(_obj, v: Vector3) -> void:
	if v.length() > 14.0:
		sound("dash", -6.0, 0.6)


# --- Boulders and embers -----------------------------------------------------

func _spawn_boulder(pos: Vector3, drop: bool) -> void:
	var b := BoulderScript.new()
	b.main = self
	b.net_id = next_net_id()
	b.position = pos
	add_child(b)
	if drop:
		b.flying = true
		b.vel = Vector3.ZERO
	else:
		b.position.y = W.height(pos.x, pos.z)


func _update_boulders(delta: float) -> void:
	boulder_t -= delta
	if boulder_t > 0.0:
		return
	boulder_t = 2.5
	if get_tree().get_nodes_in_group("boulders").size() < BOULDER_COUNT:
		var a := randf() * TAU
		_spawn_boulder(Vector3(cos(a) * (W.R - 0.4), 9.0, sin(a) * (W.R - 0.4)), true)


func boulder_lost(b) -> void:
	b.queue_free()


func _spawn_ember(pos: Vector3) -> void:
	var e := EmberScript.new()
	e.main = self
	e.net_id = next_net_id()
	e.position = pos
	add_child(e)
	e.flying = true  # pops out and lands (home, if it lands by the fire)
	e.vel = Vector3(randf_range(-2.0, 2.0), 7.0, randf_range(-2.0, 2.0))


func ember_landed(e) -> void:
	var p: Vector3 = e.global_position
	if Vector2(p.x, p.z).length() < FIRE_HOME:
		ember_home(e, "Ember home! +5")


func ember_home(e, msg: String) -> void:
	if e.has_meta("home"):
		return
	e.set_meta("home", true)
	e.queue_free()
	embers = mini(embers + 1, MAX_EMBERS)
	score += 5
	sound("revive", -4.0, 1.3)
	popup(Vector3(0.0, 2.6, 0.0), msg, Color(1.0, 0.8, 0.4))


# --- Networking --------------------------------------------------------------

func on_client_joined() -> void:
	_show_center("THE KNIGHTS HAVE ARRIVED!", 1.5)


func on_client_left() -> void:
	_show_center("The knights left - waiting for them to come back…", 0.0)
	for k in knights():
		if k.index >= 2 and k.active:
			_knight_leaves(k)  # P2 waits as before; drop-in knights rejoin when the TV is back


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Press the menu button to resume")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps: Array = []
	for p in players:
		ps.append(p.net_state())
	var gs: Array = []
	for g in get_tree().get_nodes_in_group("goblins"):
		if not g.is_queued_for_deletion():
			gs.append(g.net_item())
	var bs: Array = []
	for b in get_tree().get_nodes_in_group("boulders"):
		if not b.is_queued_for_deletion():
			bs.append(b.net_item())
	var es: Array = []
	for e in get_tree().get_nodes_in_group("embers"):
		if not e.is_queued_for_deletion():
			es.append(e.net_item())
	return [wave, score, embers, game_over, down_t, ps, gs, bs, es, built, rain_t, shield]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	wave = s[0]
	score = s[1]
	embers = s[2]
	var was_over := game_over
	game_over = s[3]
	if game_over and not was_over:
		game_over_time = 0.0
	down_t = s[4]
	var ps: Array = s[5]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_ghosts(s[6], "goblin")
	_sync_ghosts(s[7], "boulder")
	_sync_ghosts(s[8], "ember")
	if s.size() > 11:
		built = s[9]
		rain_t = s[10]
		shield = s[11]


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
	var n: Node3D
	match kind:
		"goblin":
			var g := GoblinScript.new()
			g.setup(item[1], self)
			n = g
		"boulder":
			n = BoulderScript.new()
		_:
			n = EmberScript.new()
	n.set("main", self)
	n.set("ghost", true)
	n.set("net_id", item[0])
	n.position = item[2]
	add_child(n)
	return n


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2])
		"center":
			_show_center(args[0], args[1])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The Giant paused the game")
		"hurt":
			var i: int = args[0]
			if i < players.size():
				players[i].on_hurt(args[1])
		"grow":
			set_meta("grow_anim", true)
			built = args[0]
		"cheer":
			village.cheer()
		"stats":
			_apply_stats(args[0])


# --- HUD ---------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(32)
	info_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.65))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 16
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(56)
	center_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.07, 0.04, 0.78)
	sb.border_color = Color(1.0, 0.75, 0.4, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	help_panel.add_theme_stylebox_override("panel", sb)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help_panel)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	help_panel.offset_top = 64
	help_label = _make_label(22)
	help_panel.add_child(help_label)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_panel.resized.connect(func() -> void: help_panel.position.x = (help_panel.get_parent_area_size().x - help_panel.size.x) * 0.5)
	stats_label = _make_label(28)
	stats_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	layer.add_child(stats_label)
	stats_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stats_label.offset_top = -300
	stats_label.offset_bottom = -30
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label.text = "KNIGHTS: left stick / W S move · right stick / A D turn · RT / Space sword · LT / F crossbow · A / Shift jump\n" \
		+ "GIANT: mouse moves the hand · hold left click to grab · flick and let go to throw (VR: grip or trigger)\n" \
		+ "Armoured goblins: KNIGHTS only · Big ogres: GIANT only · Bring dropped embers home · Stand by a fallen friend to revive them"


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


## VR can't show 2D overlays: mirror the centre banner on a Label3D in front of the giant's eyes.
func _update_vr_center() -> void:
	if giant == null or not giant.vr:
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
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.modulate = Color(1.0, 0.95, 0.8)
		vr_center.pixel_size = 0.0026 * W.S
		vr_center.position = Vector3(0.0, -0.12, -1.7) * W.S
		giant.xr_camera.add_child(vr_center)
		giant._set_layers(vr_center, 1)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = center_label.modulate.a
	# Above the table (nothing in front of it), so your eyes don't fight the depth.
	if not has_meta("vr_center_v4"):
		set_meta("vr_center_v4", true)
		vr_center.pixel_size = 0.0026 * W.S
		VrText.snap(vr_center)
	# Past the table and above it (VrText adds extra comfort distance), so it's easy to focus on.
	VrText.follow(vr_center, giant.xr_camera, self, 0.2 * W.S, 1.7 * W.S)
	# Tips (and the end-of-game heroes) float just below it - still above the far edge of the table.
	if vr_hint == null:
		vr_hint = Label3D.new()
		vr_hint.font_size = 36
		vr_hint.outline_size = 22
		vr_hint.outline_modulate = Color.BLACK
		vr_hint.no_depth_test = false
		vr_hint.render_priority = 10
		vr_hint.outline_render_priority = 9
		vr_hint.width = 800.0
		vr_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_hint)
	var stats_mode := game_over and stats_text != ""
	if stats_mode != vr_hint.get_meta("stats_mode", false):
		vr_hint.set_meta("stats_mode", stats_mode)
		VrText.snap(vr_hint)
	var text := stats_text if stats_mode else (giant_tip if giant_tip_t > 0.0 else "")
	vr_hint.pixel_size = (0.0015 if stats_mode else 0.0019) * W.S
	vr_hint.modulate = Color(0.95, 0.97, 1.0) if stats_mode else Color(1.0, 0.93, 0.6)
	vr_hint.text = text
	vr_hint.visible = text != ""
	# (the heroes list goes above the GAME OVER banner, never in front of the table)
	VrText.follow(vr_hint, giant.xr_camera, self, (0.78 if stats_mode else -0.125) * W.S, 1.7 * W.S)


func _update_hud() -> void:
	if wave >= 2 and help_panel.modulate.a > 0.0:
		help_panel.modulate.a = maxf(0.0, help_panel.modulate.a - get_process_delta_time() * 0.5)
	help_panel.visible = help_panel.modulate.a > 0.0 and help_label.text != ""
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the Giant…"
		return
	info_label.text = "WAVE %d      SCORE %d      CAMPFIRE EMBERS %d / %d      VILLAGE %d / %d" % [wave, score, embers, MAX_EMBERS, built, W.GROWTH.size()]
	if combo >= 3 and clock - last_kill_t < 2.5:
		info_label.text += "      COMBO x%d" % combo
	if rain_t > 0.0:
		info_label.text += "      RAIN! %s" % ("(the Giant is shielding the fire)" if shield else "(Giant: shield the fire!)")
	var n := active_knight_count()
	if n > 2:
		info_label.text += "      KNIGHTS %d" % n


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # XR world scale is global: don't leave other games giant-sized
