extends Node3D
## MARBLE MAZE - physics co-op. The VR player is a giant at a tabletop maze, tilting the whole board by
## its two side handles; the TV players (1-6) are marbles rolling through it in chase cams.
## Get EVERY marble into the goal before the clock runs out. Gems give points and extra time; holes
## drop you back to your last checkpoint. Shared score, levels get trickier (bumpers, sliding blocks,
## planks over thin air), and after the last maze they come back mirrored and faster.
## Modes, networking and party join follow docs/GAME_DEV_GUIDE.md and games/duo_arena.

const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const BoardScript := preload("res://games/marble_maze/board.gd")
const MarbleScript := preload("res://games/marble_maze/marble.gd")
const TilterScript := preload("res://games/marble_maze/tilter.gd")
const JoinListenerScript := preload("res://games/marble_maze/join_listener.gd")

const MAX_PLAYERS := 7  # VR player + 6 marbles
const MAX_LOCAL_VIEWS := 6
const PAD_LEAVE_TIME := 20.0
const INTRO_TIME := 3.5
const FIRST_INTRO_TIME := 7.0
const CLEAR_TIME := 5.0
const EXTRA_TIME_PER_PLAYER := 8.0
const GEM_TIME := 3.0
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0),
	Color(0.35, 0.9, 0.35), Color(1.0, 0.8, 0.1), Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.15)]
const SOUNDS := {
	"gem": [0.25, 880.0, 1760.0, 0.3, "sine", 0.0],
	"bump": [0.14, 260.0, 720.0, 0.4, "square", 0.05],
	"clack": [0.04, 1100.0, 500.0, 0.18, "square", 0.6],
	"fall": [0.8, 760.0, 80.0, 0.35, "tri", 0.0],
	"home": [0.55, 523.0, 1568.0, 0.35, "tri", 0.0],
	"grab": [0.06, 300.0, 200.0, 0.25, "sine", 0.3],
	"tick": [0.05, 1300.0, 1300.0, 0.14, "square", 0.0],
	"checkpoint": [0.3, 660.0, 990.0, 0.25, "square", 0.0],
	"go": [0.4, 440.0, 880.0, 0.35, "square", 0.0],
}

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var board: BoardScript
var board_y := 0.85
var pedestal: MeshInstance3D
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var synced := false
var join_listener: Node
var joy_owner := {}  # joypad device id -> player index
var views_root: Control
var last_view_area := Vector2.ZERO
var mats := {}
var meshes := {}

var state := "wait"  # wait, intro, play, clear, over
var state_t := 0.0
var level := 1
var score := 0
var best := 0
var time_left := 90.0
var levels_cleared := 0
var last_tick := -1
var cont_was := false
var net_tilt := Vector2.ZERO
var net_t := 0.0

var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_board: Label3D


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
	best = _load_best()
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
	board.load_level(1)
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		state = "wait"
		_show_center("MARBLE MAZE\nWaiting for the TV players to join…", 0.0)
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED", 1.5, false)
	else:
		_start_level(1)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave another game's scale behind


# --- Helpers -------------------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mats[key] = m
	return m


func sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.4f" % r
	if meshes.has(key):
		return meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	meshes[key] = m
	return m


func box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func cyl_mesh(r_top: float, r_bottom: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
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


func burst(pos: Vector3, color: Color, amount: int = 14, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -1.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.mesh = box_mesh(Vector3.ONE * 0.012)
	p.material_override = make_material(color, 1.5)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	if broadcast and net != null:
		net.event("burst", [pos, color, amount])


func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.0009
	l.outline_size = 14
	l.modulate = color
	l.no_depth_test = true
	l.render_priority = 5
	if players.size() > 0 and players[0].vr:
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # VR text faces the player but never follows the head
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "global_position", pos + Vector3(0, 0.12, 0), 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)
	if broadcast and net != null:
		net.event("popup", [pos, text, color])


func board_world(p: Vector2, h: float = 0.03) -> Vector3:
	return board.to_global(Vector3(p.x, h, p.y))


# --- World ---------------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.82, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.97, 0.92)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-60.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 6.0
	add_child(sun)
	# Play-room floor, a rug and a few giant toy blocks around the table.
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	fl.mesh = pm
	fl.material_override = make_material(Color(0.85, 0.72, 0.55), 0.0)
	add_child(fl)
	var rug := MeshInstance3D.new()
	rug.mesh = cyl_mesh(2.0, 2.0, 0.01, 24)
	rug.material_override = make_material(Color(0.55, 0.8, 1.0), 0.0)
	rug.position = Vector3(0, 0.005, 0)
	add_child(rug)
	var toy_cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.9, 0.45), Color(0.85, 0.45, 1.0)]
	var toy_pos: Array[Vector3] = [Vector3(-2.6, 0.3, -2.4), Vector3(2.8, 0.25, -2.0), Vector3(-3.2, 0.2, 1.5), Vector3(3.0, 0.35, 2.2), Vector3(0.5, 0.3, -4.0)]
	for i in toy_pos.size():
		var b := MeshInstance3D.new()
		var s: float = toy_pos[i].y * 2.0
		b.mesh = box_mesh(Vector3(s, s, s))
		b.material_override = make_material(toy_cols[i], 0.0)
		b.position = toy_pos[i]
		b.rotation.y = i * 0.7
		add_child(b)
	pedestal = MeshInstance3D.new()
	pedestal.material_override = make_material(Color(0.95, 0.95, 1.0), 0.0)
	add_child(pedestal)
	board = BoardScript.new()
	board.name = "Board"
	board.main = self
	add_child(board)
	set_board_height(board_y)


func set_board_height(y: float) -> void:
	board_y = clampf(y, 0.4, 1.3)
	board.position = Vector3(0, board_y, 0)
	var h := board_y - 0.08
	pedestal.mesh = cyl_mesh(0.12, 0.3, h, 16)
	pedestal.position = Vector3(0, h * 0.5, 0)


# --- Players and views -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	var t := TilterScript.new()
	t.main = self
	t.ghost = mode == "client"
	t.key_set = 0
	add_child(t)
	players.append(t)
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		var m := MarbleScript.new()
		m.index = i
		m.main = self
		m.board = board
		m.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		m.remote = mode == "host"
		if i == 1:
			m.key_set = 1 if mode == "client" else 0
			m.mouse_look = mode == "client"
		board.add_child(m)
		players.append(m)
		m.reset_to_start()
		m.set_active(i == 1)


func is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_enabled = false
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 tilts the maze in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = Vector3(0, 0, 0.66)
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
		print("No VR headset: %s" % ("TV marbles" if mode == "client" else "split screen, player 1 tilts the board"))
	_ensure_views_root()
	for p in players:
		if is_local(p) and p.active:
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
	cam.near = 0.02
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


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


## One split-screen view (SubViewport + camera + HUD) per local player, created when they first play.
func _ensure_view(p) -> void:
	if p.has_meta("view") or not is_local(p):
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
	cam.near = 0.01
	cam.far = 40.0
	cam.fov = 70.0
	vp.add_child(cam)
	cam.current = true
	if p.index == 0:
		p.attach_camera(cam)
	else:
		p.camera = cam
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tag := ColorRect.new()
	tag.color = p.color if p.index > 0 else Color(1.0, 0.85, 0.55)
	tag.size = Vector2(14, 14)
	tag.position = Vector2(14, 22)
	hud.add_child(tag)
	var l := _make_label(28)
	hud.add_child(l)
	l.position = Vector2(36, 10)
	p.hud = hud
	p.hud_label = l


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
		if p.hud_label != null:
			var ui := clampf(minf(cell.x / 940.0, cell.y / 900.0), 0.5, 1.0)
			p.hud_label.add_theme_font_size_override("font_size", int(30.0 * ui))
	if players.size() > 0 and not players[0].vr:
		for node in get_children():
			if node is DirectionalLight3D:
				node.shadow_enabled = n <= 2


# --- Controllers and drop-in join ----------------------------------------------------

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
		if p.joy >= 0 and is_local(p):
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
			if is_local(p) and p.joy < 0 and int(p.get_meta("last_joy", -2)) == device:
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


## Called by the join listener for every input event: A on a controller nobody owns joins a marble.
func handle_join_input(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed or pad.button_index != JOY_BUTTON_A:
		return false
	if not ready_to_play or net.mode == "host" or get_tree().paused:
		return false
	var device := pad.device
	if joy_owner.has(device):
		var idx: int = joy_owner[device]
		if idx > 0 and not players[idx].active and is_local(players[idx]):
			_request_join(players[idx])
			return true
		return false
	return _join_slot(device) != null


func _next_free_index() -> int:
	for i in range(1, players.size()):
		var p = players[i]
		if not is_local(p) or p.active or p.has_meta("want_join") or p.joy >= 0 or p.pad_lost_t >= 0.0:
			continue
		return i
	return -1


func _join_slot(device: int):
	var idx := _next_free_index()
	if idx < 0:
		_show_center("All %d marbles are taken!" % (players.size() - 1), 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


## Local: roll in now. TV machine: ask the host (retried by _check_join until it agrees).
func _request_join(p) -> void:
	p.remove_meta("left_by_pad")
	p.pad_lost_t = -1.0
	if net.mode == "client":
		p.set_meta("want_join", true)
		join_t = 0.0
	elif not p.active:
		_activate(p)
	_save_party()


func _activate(p) -> void:
	p.set_active(true)
	p.reset_to_start()
	if state == "play" or state == "intro":
		time_left += EXTRA_TIME_PER_PLAYER
	_show_center("PLAYER %d ROLLS IN!" % (p.index + 1), 1.5)
	sound("home", -4.0, 1.2, true)
	on_player_activity_changed(p)


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


func _save_party() -> void:
	var party: Array = []
	for p in players:
		if p.index >= 2 and is_local(p) and (p.active or p.has_meta("want_join")) and not p.has_meta("left_by_pad"):
			party.append([p.index, p.joy])
	Engine.set_meta("marble_maze_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("marble_maze_party"):
		return
	var saved: Dictionary = Engine.get_meta("marble_maze_party")
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
		if p.active or not is_local(p):
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


## Test hook: join a marble without a controller (index -1: the next free seat).
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
		if not p.has_meta("want_join") or not is_local(p):
			continue
		if p.active:
			p.remove_meta("want_join")
			continue
		join_t = 1.0
		net.send_action("join", [p.index], 1)  # sent as P2, like duo_arena's drop-in seats


func on_player_activity_changed(p) -> void:
	if p.active and is_local(p):
		_ensure_view(p)
	if p.active:
		p.remove_meta("want_join")
	_layout_views()
	print("Player %d is now %s" % [p.index + 1, "playing" if p.active else "waiting"])


func has_local_marble_keys() -> bool:
	for p in players:
		if p.index > 0 and is_local(p) and p.active and p.key_set != MarbleScript.NO_KEYS:
			return true
	return false


func active_marbles() -> Array:
	var out: Array = []
	for p in players:
		if p.index > 0 and p.active:
			out.append(p)
	return out


func home_count() -> int:
	var n := 0
	for p in active_marbles():
		if p.home:
			n += 1
	return n


# --- Game flow -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track((level - 1) % 3)
	_ensure_join_listener()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	_update_vr_text()
	var cont := _continue_pressed()
	var cont_edge := cont and not cont_was
	cont_was = cont
	if net.mode == "client":
		_client_update(delta, cont_edge)
		return
	_update_lost_pads(delta)
	state_t += delta
	board.t += delta
	var target := Vector2.ZERO
	if state == "play":
		target = players[0].want_tilt
	board.tilt = board.tilt.lerp(target, 1.0 - exp(-7.0 * delta))
	board.basis = board.tilt_basis(board.tilt)
	match state:
		"wait":
			board.tilt = Vector2.ZERO
		"intro":
			var dur := FIRST_INTRO_TIME if level == 1 else INTRO_TIME
			if state_t >= dur:
				state = "play"
				state_t = 0.0
				_show_center("GO!", 0.8)
				sound("go", 0.0, 1.0, true)
		"play":
			time_left -= delta
			var secs := int(ceilf(time_left))
			if secs <= 10 and secs != last_tick and secs > 0:
				last_tick = secs
				sound("tick", -2.0, 1.0 + (10 - secs) * 0.05, true)
			_authority_checks()
			if time_left <= 0.0:
				time_left = 0.0
				_game_over()
		"clear":
			if state_t > CLEAR_TIME or (state_t > 1.5 and cont_edge):
				_start_level(level + 1)
		"over":
			if state_t > 1.5 and cont_edge:
				_restart()


func _client_update(delta: float, cont_edge: bool) -> void:
	_check_join(delta)
	_update_lost_pads(delta)
	state_t += delta
	board.t += delta
	board.t = lerpf(board.t, net_t, 1.0 - exp(-2.0 * delta))
	net_t += delta
	board.tilt = board.tilt.lerp(net_tilt, 1.0 - exp(-14.0 * delta))
	board.basis = board.tilt_basis(board.tilt)
	if cont_edge and ((state == "clear" and state_t > 1.5) or (state == "over" and state_t > 1.5)):
		net.send_action("continue", [])


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


## A / Enter on this machine (VR: the trigger or A) moves on from the level-clear / game-over screens.
func _continue_pressed() -> bool:
	if state != "clear" and state != "over":
		return false
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for p in players:
		if is_local(p) and p.active and p.action_pressed():
			return true
	if players.size() > 0 and players[0].vr and players[0].action_pressed():
		return true
	return false


## Bot hook: same as pressing A on the end screens.
func debug_continue() -> void:
	if net.mode == "client":
		net.send_action("continue", [])
	else:
		_on_continue()


func _on_continue() -> void:
	if state == "clear" and state_t > 1.0:
		_start_level(level + 1)
	elif state == "over" and state_t > 1.0:
		_restart()


func _start_level(n: int) -> void:
	level = n
	board.load_level(n)
	board.tilt = Vector2.ZERO
	players[0].want_tilt = Vector2.ZERO
	players[0].grab_tilt = Vector2.ZERO
	for p in players:
		if p.index > 0:
			p.reset_to_start()
	var count := maxi(1, active_marbles().size())
	time_left = board.level_time(n) + EXTRA_TIME_PER_PLAYER * (count - 1)
	last_tick = -1
	state = "intro"
	state_t = 0.0
	var lap := (n - 1) / 6
	var title := "LEVEL %d: %s%s" % [n, board.level_name(n), "  (MIRRORED!)" if lap % 2 == 1 else ""]
	if n == 1:
		_show_center("MARBLE MAZE\nGet EVERY marble into the glowing goal before time runs out!\n" \
			+ "VR: grab a side handle (right trigger) and tilt the board · left stick tilts too · A levels it\n" \
			+ "TV: left stick rolls your marble · right stick turns the camera · A joins\n" \
			+ "Gems = points + time · holes drop you back to a checkpoint\n\n" + title, FIRST_INTRO_TIME)
	else:
		_show_center(title + "\n" + board.level_tip(n), INTRO_TIME)
	sound("clear", -4.0, 1.0, true)
	net.event("level", [n])
	print("Level %d started: %s (%d marbles, %.0f s)" % [n, board.level_name(n), count, time_left])


func _restart() -> void:
	score = 0
	levels_cleared = 0
	_start_level(1)


## Host / local: gems, marbles reaching the goal (for marbles driven by the TV machine) and level clear.
func _authority_checks() -> void:
	var marbles := active_marbles()
	for p in marbles:
		if p.home or p.falling:
			continue
		var pos := Vector2(p.lp.x, p.lp.z)
		for i in board.gems.size():
			if board.gem_taken[i]:
				continue
			if pos.distance_to(board.gems[i]) < 0.5 * board.CELL:
				board.gem_taken[i] = true
				score += 10
				time_left += GEM_TIME
				var wp := board_world(board.gems[i], 0.04)
				popup(wp + Vector3(0, 0.03, 0), "+10  +%ds" % int(GEM_TIME), Color(0.4, 1.0, 1.0))
				burst(wp, Color(0.4, 1.0, 1.0), 14)
				sound("gem", -2.0, 1.0 + randf() * 0.2, true)
		if p.remote and board.in_goal(pos):
			p.home = true
			on_marble_home(p)
	if marbles.is_empty():
		return
	for p in marbles:
		if not p.home:
			return
	_level_clear()


func _level_clear() -> void:
	state = "clear"
	state_t = 0.0
	levels_cleared += 1
	var bonus := int(time_left) * 2
	score += bonus
	if score > best:
		best = score
		_save_best(best)
	var next_name := board.level_name(level + 1)
	_show_center("LEVEL CLEAR!\nTime bonus +%d   ·   Score %d\nNext: %s\n\nA / Enter (VR: trigger) to roll on" % [bonus, score, next_name], CLEAR_TIME)
	sound("clear", 0.0, 1.2, true)
	burst(board_world(board.goal, 0.08), Color(1.0, 0.9, 0.3), 30)
	burst(board_world(board.goal, 0.08), Color(0.4, 1.0, 0.5), 30)
	print("Level %d cleared! score %d" % [level, score])


func _game_over() -> void:
	state = "over"
	state_t = 0.0
	var line := "Best: %d" % best
	if score > best:
		line = "NEW BEST SCORE!  (previous %d)" % best
		best = score
		_save_best(best)
	_show_center("TIME'S UP!\n%d of %d marbles made it home\nScore %d  ·  reached level %d\n%s\n\nA / Enter (VR: trigger) to play again" \
		% [home_count(), active_marbles().size(), score, level, line], 0.0)
	sound("gameover", 0.0, 1.0, true)
	print("Game over: level %d, score %d" % [level, score])


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://marble_maze_best.cfg")
	return int(cfg.get_value("best", "score", 0))


func _save_best(s: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "score", s)
	cfg.save("user://marble_maze_best.cfg")


# --- Marble callbacks (from whichever machine simulates the marble) -------------------

func _forward_fx(kind: String, args: Array, p) -> void:
	if net.mode == "client":
		net.send_action("fx", [kind] + args, p.index)


func on_bump(p, i: int) -> void:
	board.bump_fx(i)
	sound("bump", -4.0, randf_range(0.9, 1.2))
	if p.joy >= 0:
		Input.start_joy_vibration(p.joy, 0.4, 0.6, 0.12)
	_forward_fx("bump", [i], p)


func on_wall_hit(p, impact: float) -> void:
	sound("clack", linear_to_db(clampf(impact * 2.0, 0.1, 1.0)) - 4.0, randf_range(0.8, 1.3))
	if p.joy >= 0 and impact > 0.4:
		Input.start_joy_vibration(p.joy, 0.2, 0.3, 0.06)


func on_marble_fell(p) -> void:
	var wp: Vector3 = board.to_global(p.lp)
	sound("fall", -2.0)
	burst(wp, p.color, 10, false)
	popup(wp + Vector3(0, 0.05, 0), "OOPS!", p.color, false)
	if p.joy >= 0:
		Input.start_joy_vibration(p.joy, 0.6, 0.4, 0.3)
	_forward_fx("fall", [wp], p)


func on_marble_respawn(p) -> void:
	burst(board.to_global(p.lp), Color(1, 1, 1), 8, false)


func on_checkpoint(p) -> void:
	var wp: Vector3 = board.to_global(p.lp)
	sound("checkpoint", -4.0)
	popup(wp + Vector3(0, 0.05, 0), "CHECKPOINT", Color(0.4, 0.85, 1.0), false)
	_forward_fx("cp", [wp], p)


## A marble dropped into the goal. Scored by the host (or local game); the TV machine only freezes it.
func on_marble_home(p) -> void:
	if net.mode == "client":
		net.send_action("home", [], p.index)  # the host scores it (it may not have seen the last frames)
		return
	score += 25
	var wp := board_world(board.goal, 0.06)
	popup(wp + Vector3(0, 0.05, 0), "P%d HOME! +25" % (p.index + 1), p.color)
	burst(wp, p.color, 20)
	sound("home", 0.0, 1.0 + 0.1 * home_count(), true)
	print("P%d reached the goal (%d/%d)" % [p.index + 1, home_count(), active_marbles().size()])


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ------------------------------------

func on_client_joined() -> void:
	_show_center("THE TV PLAYERS JOINED!", 1.5)
	_start_level(level if state != "over" else 1)


func on_client_left() -> void:
	for i in range(2, players.size()):
		if players[i].active:
			players[i].set_active(false)
	state = "wait"
	_show_center("The TV players left - waiting for them to come back…", 0.0)


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
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			if p.active:
				p.set_active(false)
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
		"continue":
			_on_continue()
		"home":
			if state == "play" and p.active and not p.home and Vector2(p.lp.x, p.lp.z).distance_to(board.goal) < 0.2:
				p.home = true
				on_marble_home(p)
		"fx":
			if args.is_empty():
				return
			match str(args[0]):
				"bump":
					board.bump_fx(int(args[1]))
					sound("bump", -6.0)
				"fall":
					var wp: Vector3 = args[1]
					sound("fall", -4.0)
					burst(wp, p.color, 10, false)
					popup(wp + Vector3(0, 0.05, 0), "OOPS!", p.color, false)
				"cp":
					sound("checkpoint", -6.0)
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	if vr_center != null and paused:
		VrText.snap(vr_center)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nPull the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ms: Array = []
	for i in range(1, players.size()):
		var p = players[i]
		ms.append([p.lp, p.active, p.home])
	var t = players[0]
	return [state, level, board.t, score, time_left, board.tilt, board_y, board.gem_taken.duplicate(), ms,
		t.head_transform(), t.hand_l_transform(), t.hand_r_transform(), state_t, best]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 14:
		return
	var lv: int = s[1]
	if lv != board.level_n or not synced:
		synced = true
		level = lv
		board.load_level(lv)
		for p in players:
			if p.index > 0:
				p.reset_to_start()
	var new_state: String = s[0]
	if new_state != state:
		state = new_state
		state_t = float(s[12])
	net_t = s[2]
	if absf(board.t - net_t) > 0.5:
		board.t = net_t
	score = s[3]
	time_left = s[4]
	net_tilt = s[5]
	var by: float = s[6]
	if absf(by - board_y) > 0.001:
		set_board_height(by)
	var gt: Array = s[7]
	for i in mini(gt.size(), board.gem_taken.size()):
		board.gem_taken[i] = bool(gt[i])
	var ms: Array = s[8]
	for i in ms.size():
		var idx := i + 1
		if idx >= players.size():
			break
		var st: Array = ms[i]
		var p = players[idx]
		var act: bool = st[1]
		if act != p.active:
			p.set_active(act)
			if act:
				p.reset_to_start()
			on_player_activity_changed(p)
		if act and bool(st[2]) and not p.home and state == "play":
			p.home = true
		if not is_local(p):
			p.target_lp = st[0]
	var t = players[0]
	t.net_head = s[9]
	t.net_hand_l = s[10]
	t.net_hand_r = s[11]
	best = s[13]


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], false)
		"popup":
			popup(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false)
		"level":
			var lv: int = args[0]
			if lv != board.level_n:
				level = lv
				board.load_level(lv)
			for p in players:
				if p.index > 0:
					p.reset_to_start()
			state = "intro"
			state_t = 0.0
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR player paused the game")


# --- HUD -----------------------------------------------------------------------------

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
	center_label = _make_label(46)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -64
	help_label.offset_bottom = -12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Marble: left stick / arrows roll · right stick (Q/E, mouse on the TV) turns the camera · Start / Esc menu\n" \
		+ "Split screen P1 tilts the board: WASD / mouse / left stick, Space or A levels it  ·  More marbles: press A on another controller"


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


func hud_text(p) -> String:
	if net.mode == "client" and not synced:
		return "Syncing with the VR player…"
	var gems := 0
	for g in board.gem_taken:
		if g:
			gems += 1
	var line := "LEVEL %d  ·  %s\nTIME %d   SCORE %d\nHOME %d/%d   GEMS %d/%d" % [level, board.level_name(level),
		int(ceilf(time_left)), score, home_count(), active_marbles().size(), gems, board.gem_taken.size()]
	if p.index == 0:
		line += "\nYOU TILT THE BOARD!"
	elif p.home:
		line += "\nYOU'RE HOME! Cheer the others on"
	elif p.falling:
		line += "\nWHOOPS!"
	return line


func _update_vr_text() -> void:
	if help_label.modulate.a > 0.0 and level >= 2:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if players.is_empty() or not players[0].vr:
		return
	var cam: XRCamera3D = players[0].xr_camera
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 44
		vr_center.outline_size = 26
		vr_center.pixel_size = 0.0022
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 1100.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_center)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, cam, self, -0.05, 1.8)
	# Scoreboard hanging high above the far side of the table (world-locked, ~2.4 m away, above the banner).
	if vr_board == null:
		vr_board = Label3D.new()
		vr_board.font_size = 56
		vr_board.outline_size = 22
		vr_board.pixel_size = 0.0028
		vr_board.modulate = Color(1.0, 0.95, 0.7)
		vr_board.outline_modulate = Color(0, 0, 0)
		add_child(vr_board)
	vr_board.position = Vector3(0.0, board_y + 1.4, -1.6)
	var gems := 0
	for g in board.gem_taken:
		if g:
			gems += 1
	vr_board.text = "LEVEL %d · %s\nTIME %d    SCORE %d\nHOME %d/%d    GEMS %d/%d" % [level, board.level_name(level),
		int(ceilf(time_left)), score, home_count(), active_marbles().size(), gems, board.gem_taken.size()]
