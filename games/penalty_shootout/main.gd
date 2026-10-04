extends Node3D
## PENALTY SHOOTOUT - football fun. The VR player is the GOALKEEPER in a full-size goal: touch the ball
## with a glove (or block it with your body) to save it; left stick shuffles along the goal line.
## The TV players (1-6) are STRIKERS who take turns from the penalty spot: aim the reticle with the
## stick, HOLD A to power up, release to shoot (X: a floating CHIP, Y: a FIREBALL once per match),
## triggers curve it. Shots get faster every round.
## It's a CUP: a GROUP STAGE, then THE FINAL between the two top strikers (with sudden death), then the
## TROPHY ceremony - with one striker it's striker vs keeper for the cup. Now and then a POWER-UP
## bubble floats in front of the keeper (BIG GLOVES, SLOW-MO, DOUBLE SAVE): touch it to take it.
## Goals bring celebrations, confetti cannons, the dancing lion mascot and a slow-motion REPLAY on the
## TV; the end screen hands out awards (golden boot, golden glove, fastest shot...).
## Split screen fallback: the keeper is a flat player who shuffles and dives.
## Modes, networking and party join follow docs/GAME_DEV_GUIDE.md and games/duo_arena.

const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const WorldScript := preload("res://games/penalty_shootout/world.gd")
const BallScript := preload("res://games/penalty_shootout/ball.gd")
const KeeperScript := preload("res://games/penalty_shootout/keeper.gd")
const StrikerScript := preload("res://games/penalty_shootout/striker.gd")
const JoinListenerScript := preload("res://games/penalty_shootout/join_listener.gd")

const MAX_PLAYERS := 7  # VR keeper + 6 strikers
const MAX_LOCAL_VIEWS := 6
const PAD_LEAVE_TIME := 20.0
const FIRST_INTRO_TIME := 9.0
const INTRO_TIME := 3.5
const FINAL_INTRO_TIME := 4.5
const TROPHY_TIME := 7.0
const READY_TIME := 1.0
const AIM_TIME := 15.0
const RUNUP_TIME := 0.5
const SPD_MIN := 6.5
const FIRE_SPEED := 22.0
const REPLAY_DELAY := 0.7
const REPLAY_CAM := Vector3(6.6, 1.35, 5.2)
const POWERS: Array[String] = ["big", "slow", "double"]
const PLAYER_COLORS: Array[Color] = [Color(0.2, 1.0, 0.45), Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0),
	Color(1.0, 0.85, 0.15), Color(0.85, 0.45, 1.0), Color(1.0, 0.55, 0.15), Color(0.3, 0.95, 0.95)]
const SOUNDS := {
	"kick": [0.14, 170.0, 55.0, 0.7, "sine", 0.35],
	"save": [0.2, 150.0, 60.0, 0.7, "sine", 0.55],
	"post": [0.6, 1480.0, 1400.0, 0.35, "tri", 0.05],
	"whistle": [0.4, 2350.0, 2500.0, 0.25, "sine", 0.12],
	"cheer": [1.8, 420.0, 300.0, 0.32, "saw", 0.93],
	"groan": [1.3, 260.0, 110.0, 0.28, "saw", 0.75],
	"net": [0.45, 600.0, 180.0, 0.3, "sine", 0.9],
	"charge": [0.06, 600.0, 900.0, 0.12, "square", 0.0],
	"bounce": [0.08, 150.0, 90.0, 0.35, "sine", 0.2],
	"dive": [0.25, 900.0, 300.0, 0.18, "sine", 0.8],
	"join": [0.45, 523.0, 1046.0, 0.3, "tri", 0.0],
	"power": [0.5, 400.0, 1600.0, 0.3, "sine", 0.0],
	"fire": [0.5, 900.0, 120.0, 0.4, "saw", 0.8],
	"boom": [0.7, 110.0, 30.0, 0.5, "saw", 0.7],
	"fanfare": [1.4, 392.0, 1568.0, 0.4, "square", 0.0],
	"replay": [0.3, 700.0, 500.0, 0.2, "tri", 0.0],
}

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var world: WorldScript
var ball: BallScript
var keeper: KeeperScript
var xr_interface: XRInterface
var fake_vr := false
var mirror_vp: SubViewport
var mirror_t := 0.0
var synced := false
var join_listener: Node
var joy_owner := {}  # joypad device id -> player index
var views_root: Control
var last_view_area := Vector2.ZERO
var mats := {}
var meshes := {}
var spot := Vector3(0.0, BallScript.R, 11.0)

var state := "wait"  # wait, intro, aim, runup, flight, result, final_intro, trophy, over
var state_t := 0.0
var intro_dur := FIRST_INTRO_TIME
var shooter := -1
var round_i := 0
var rounds_total := 5
var order: Array[int] = []
var turn_k := 0
var turn_count := 0
var saves := 0
var goals_total := 0
var shots_total := 0
var matches := 0
var pending := {}
var cur_max_speed := 9.5
var last_result := ""
var last_kmh := 0
var result_len := 2.5
var excite := 0.0
var shake := 0.0
var cont_was := false
# The cup.
var cup_stage := "group"  # group, final
var finalists: Array[int] = []
var final_goals := {}
var final_shots := 3
var sudden := 0
var champion := -1  # 0 = the keeper, 1-6 a striker
var save_streak := 0
var best_save_streak := 0
var last_shot := "normal"
var wild_t := 0.0
# Replays (TV views only).
var rec: Array = []  # [t, ball pos, head, down, glove l, glove r]
var rec_t := 0.0
var replay_on := false
var replay_t := 0.0
var replay_len := 0.0
var replay_ball: MeshInstance3D
var replay_pos := Vector3.ZERO

var reticle: MeshInstance3D
var dots: Array[MeshInstance3D] = []
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_msg := ""
var vr_msg_t := 0.0


func _ready() -> void:
	randomize()
	fake_vr = OS.has_environment("PS_FAKE_VR") and not OS.has_environment("DUO_JOIN")
	var xr := XRServer.find_interface("OpenXR")
	var vr_on: bool = (xr != null and xr.is_initialized()) or fake_vr
	world = WorldScript.new()
	world.name = "World"
	world.main = self
	add_child(world)
	world.build(vr_on and not OS.has_environment("DUO_JOIN"))
	ball = BallScript.new()
	ball.name = "Ball"
	ball.main = self
	add_child(ball)
	ball.place(spot)
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
		_show_center("Connecting to the keeper…", 0.0, false)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	ball.ghost = mode == "client"
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		state = "wait"
		_show_center("PENALTY SHOOTOUT\nYou're the KEEPER!\nWaiting for the strikers on the TV…", 0.0, true,
			"You're the KEEPER!\nWaiting for the strikers…")
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED", 1.5, false)
	else:
		_begin_match()


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave our keeper scale behind


# --- Helpers -------------------------------------------------------------------------------

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
	m.radial_segments = 14
	m.rings = 7
	meshes[key] = m
	return m


func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % str(size)
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


func burst(pos: Vector3, color: Color, amount: int = 20, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.1
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = box_mesh(Vector3.ONE * 0.08)
	p.material_override = make_material(color, 1.5)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	if broadcast and net != null:
		net.event("burst", [pos, color, amount])


## Big floating words. VR: world-locked facing the keeper, kept at least 3.5 m away and drawn with
## normal depth (nothing nearer sits in front of them by then: the ball has stopped).
func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.006
	l.outline_size = 18
	l.modulate = color
	l.render_priority = 5
	if keeper_in_vr():
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # VR: world-locked, facing the keeper
		l.rotation.y = PI
		l.pixel_size = 0.004 * keeper.ws()
		pos = Vector3(clampf(pos.x, -3.0, 3.0), maxf(pos.y, 1.2) + 0.6, maxf(pos.z, 4.0))  # never close to the eyes
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "global_position", pos + Vector3(0, 0.8, 0), 1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.6)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.0).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)
	if broadcast and net != null:
		net.event("popup", [pos, text, color])


func keeper_in_vr() -> bool:
	return players.size() > 0 and players[0].vr


# --- Players and views ---------------------------------------------------------------------

func _build_players(mode: String) -> void:
	keeper = KeeperScript.new()
	keeper.main = self
	keeper.ghost = mode == "client"
	keeper.key_set = 0
	keeper.color = PLAYER_COLORS[0]
	add_child(keeper)
	players.append(keeper)
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		var s := StrikerScript.new()
		s.index = i
		s.main = self
		s.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		s.remote = mode == "host"
		if i == 1:
			s.key_set = 1 if mode == "client" else 0
			s.mouse_look = mode == "client"
		add_child(s)
		players.append(s)
		s.position = _queue_pos(i - 1)
		s.stand_at = s.position
		s.set_active(i == 1)


func is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	var real_vr: bool = xr != null and xr.is_initialized() and mode != "client"
	if real_vr or (fake_vr and mode != "client"):
		Engine.physics_ticks_per_second = 90
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
		if real_vr:
			xr_interface = xr
			print("VR headset found: player 1 is the keeper in VR")
			get_viewport().use_xr = true
			get_viewport().msaa_3d = Viewport.MSAA_2X
		else:
			print("PS_FAKE_VR: the keeper's VR code runs without a headset (bot-driven hands)")
			cam.position = Vector3(0, 1.5, 0)
			left.position = Vector3(0.3, 1.2, -0.35)
			right.position = Vector3(-0.3, 1.2, -0.35)
		players[0].attach_xr(origin, cam, left, right)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: %s" % ("TV strikers" if mode == "client" else "split screen, player 1 is the keeper"))
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
	cam.near = 0.03
	cam.cull_mask &= ~2
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
	bg.color = Color(0.05, 0.07, 0.16)
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
	cam.near = 0.05
	cam.far = 200.0
	cam.fov = 62.0
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
	tag.color = p.color
	tag.size = Vector2(14, 14)
	tag.position = Vector2(14, 22)
	hud.add_child(tag)
	var l := _make_label(28)
	hud.add_child(l)
	l.position = Vector2(36, 10)
	p.hud = hud
	p.hud_label = l
	var rl := _make_label(26)
	rl.text = "● REPLAY"
	rl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	hud.add_child(rl)
	rl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rl.offset_left = -220
	rl.offset_right = -16
	rl.offset_top = 12
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rl.visible = false
	p.set_meta("replay_label", rl)
	if p.index > 0:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.6)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(bg)
		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
		var red := ColorRect.new()  # the wild zone at the top of the meter
		red.color = Color(1.0, 0.2, 0.2, 0.35)
		red.mouse_filter = Control.MOUSE_FILTER_IGNORE
		red.anchor_left = 0.85
		red.anchor_right = 1.0
		red.anchor_bottom = 1.0
		bg.add_child(red)
		bg.visible = false
		p.power_bg = bg
		p.power_fill = fill


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
	if not keeper_in_vr():
		for node in world.get_children():
			if node is DirectionalLight3D:
				node.shadow_enabled = n <= 2


# --- Controllers and drop-in join ------------------------------------------------------------

func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	joy_owner.clear()
	if net.mode == "host":
		if not players[0].vr and pads.size() > 0:
			players[0].joy = pads[0]
		return
	players[1].joy = pads[0] if pads.size() > 0 else -1
	if net.mode == "local" and not players[0].vr:
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


## Called by the join listener for every input event: A on a controller nobody owns joins a striker.
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
		_show_center("All %d striker spots are taken!" % (players.size() - 1), 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


## Local: step up now. TV machine: ask the host (retried by _check_join until it agrees).
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
	p.reset_match()
	if state in ["aim", "runup", "flight", "result", "intro"] and not order.has(p.index):
		order.append(p.index)  # gets a shot at the end of this round
	_show_center("PLAYER %d JOINS THE SHOOTOUT!" % (p.index + 1), 1.5)
	sound("join", -4.0, 1.2, true)
	on_player_activity_changed(p)
	if state == "wait" and net.mode == "host" and net.connected:
		_begin_match()


func _deactivate(p) -> void:
	if not p.active:
		return
	p.set_active(false)
	on_player_activity_changed(p)
	if p.index == shooter and state == "aim":
		_advance()


func _leave(p) -> void:
	p.pad_lost_t = -1.0
	p.remove_meta("want_join")
	p.set_meta("left_by_pad", true)
	if net.mode == "client":
		net.send_action("leave", [], p.index)
	elif p.active:
		_deactivate(p)
		_show_center("PLAYER %d LEFT" % (p.index + 1), 1.5)
	_save_party()


func _save_party() -> void:
	var party: Array = []
	for p in players:
		if p.index >= 2 and is_local(p) and (p.active or p.has_meta("want_join")) and not p.has_meta("left_by_pad"):
			party.append([p.index, p.joy])
	Engine.set_meta("penalty_shootout_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("penalty_shootout_party"):
		return
	var saved: Dictionary = Engine.get_meta("penalty_shootout_party")
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


## Test hook: join a striker without a controller (index -1: the next free spot).
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


func active_strikers() -> Array:
	var out: Array = []
	for p in players:
		if p.index > 0 and p.active:
			out.append(p)
	return out


# --- Queries used by the players ---------------------------------------------------------------

func is_turn_of(p) -> bool:
	return state == "aim" and shooter == p.index


func can_shoot() -> bool:
	return state == "aim" and state_t >= READY_TIME


func keeper_can_move() -> bool:
	return state != "wait" and state != "over" and state != "trophy"


# --- Game flow -------------------------------------------------------------------------------

func _rounds_for(n: int) -> int:
	return clampi(int(ceil(10.0 / maxf(1.0, float(n)))), 3, 5)


func _max_speed() -> float:
	var progress := clampf(float(round_i) / maxf(1.0, float(rounds_total - 1)), 0.0, 1.0)
	if cup_stage == "final":
		progress = 1.0
	var n := maxi(1, active_strikers().size())
	return (9.5 + 8.0 * progress) * (1.0 - 0.025 * (n - 1))


func _result_time() -> float:
	return maxf(1.9, 2.7 - 0.15 * (active_strikers().size() - 1))


func _begin_match() -> void:
	saves = 0
	goals_total = 0
	shots_total = 0
	round_i = 0
	turn_count = 0
	shooter = -1
	order.clear()
	cup_stage = "group"
	finalists.clear()
	final_goals.clear()
	sudden = 0
	champion = -1
	save_streak = 0
	best_save_streak = 0
	keeper.power = ""
	keeper.bubble = ""
	for p in players:
		if p.index > 0:
			p.reset_match()
	world.show_trophy(Vector3.INF)
	world.mascot_cheer("")
	rounds_total = _rounds_for(active_strikers().size())
	cur_max_speed = _max_speed()
	ball.place(spot)
	state = "intro"
	state_t = 0.0
	intro_dur = FIRST_INTRO_TIME if matches == 0 else INTRO_TIME
	matches += 1
	if intro_dur > INTRO_TIME:
		_show_center("PENALTY CUP!\n" \
			+ "KEEPER: stop the ball with your gloves! (VR: just reach out and touch it · left stick shuffles)\n" \
			+ "STRIKERS: take turns · aim with the stick · HOLD A to power up, let go to shoot · triggers bend it\n" \
			+ "X: a floating CHIP · Y: a FIREBALL (once a match) · too much power (red) = wild shot!\n" \
			+ "Group stage, then THE FINAL for the cup!\n\nA / Enter (VR: trigger) to kick off", intro_dur, true,
			"PENALTY CUP! You're the KEEPER\nTouch the ball with your gloves!")
	else:
		_show_center("NEW CUP!  Group stage: %d rounds\nGet ready…" % rounds_total, intro_dur, true, "NEW CUP!\nGet ready…")
	sound("whistle", 0.0, 1.0, true)
	print("Match started: %d strikers, %d rounds" % [active_strikers().size(), rounds_total])


func _begin_round() -> void:
	order.clear()
	if cup_stage == "final":
		for f in finalists:
			if players[f].active:
				order.append(f)
	else:
		for p in active_strikers():
			order.append(p.index)
	turn_k = 0
	if order.is_empty():
		state = "wait"
		shooter = -1
		_show_center("Waiting for strikers…", 0.0)
		return
	_start_turn()


func _start_turn() -> void:
	while turn_k < order.size() and not players[order[turn_k]].active:
		turn_k += 1
	if turn_k >= order.size():
		round_i += 1
		if cup_stage == "final":
			_final_round_done()
		elif round_i >= rounds_total:
			_group_done()
		else:
			_begin_round()
		return
	shooter = order[turn_k]
	state = "aim"
	state_t = 0.0
	turn_count += 1
	cur_max_speed = _max_speed()
	ball.place(spot)
	var p = players[shooter]
	if is_local(p):
		p.prepare_turn()
	# Now and then the keeper gets a power-up bubble (more often when the strikers are well ahead).
	if keeper.bubble == "" and keeper.power == "" and (turn_count % 3 == 0 or goals_total - saves >= 3):
		var kind: String = POWERS[randi() % POWERS.size()]
		keeper.offer(kind)
		_vr_say("POWER-UP!  Touch the bubble!", 2.5)
		print("Power-up offered: %s" % kind)
	var tip := ""
	if matches <= 1 and round_i == 0 and cup_stage == "group":
		tip = "\nKEEPER: touch the ball with a glove to save it!  Strikers: aim, HOLD A, let go!"
	var head := "THE FINAL" if cup_stage == "final" else "ROUND %d of %d" % [round_i + 1, rounds_total]
	if cup_stage == "final" and sudden > 0:
		head = "SUDDEN DEATH"
	_show_center("%s  ·  P%d TO SHOOT%s" % [head, shooter + 1, tip], 1.6 if tip == "" else 2.6, true, "P%d to shoot - get ready!" % (shooter + 1))
	sound("whistle", -6.0, 1.15, true)
	print("Turn: %s round %d/%d, P%d shoots (max speed %.1f)" % [cup_stage, round_i + 1, rounds_total, shooter + 1, cur_max_speed])


func _advance() -> void:
	keeper.power = ""
	keeper.bubble = ""
	turn_k += 1
	_start_turn()


## The group stage is over: the two top strikers meet in THE FINAL (one striker: it's them against the
## keeper for the cup).
func _group_done() -> void:
	var gs := active_strikers()
	if gs.is_empty():
		_match_over()
		return
	if gs.size() == 1:
		var s = gs[0]
		champion = s.index if s.goals * 2 > s.shots else 0
		_start_trophy()
		return
	gs.sort_custom(func(a, b) -> bool: return a.goals > b.goals or (a.goals == b.goals and a.shots < b.shots))
	finalists.clear()
	finalists.append(int(gs[0].index))
	finalists.append(int(gs[1].index))
	final_goals = {finalists[0]: 0, finalists[1]: 0}
	cup_stage = "final"
	sudden = 0
	round_i = 0
	state = "final_intro"
	state_t = 0.0
	keeper.power = ""
	keeper.bubble = ""
	_show_center("THE FINAL!\nP%d  vs  P%d\n%d shots each - most goals lifts the CUP!" % [finalists[0] + 1, finalists[1] + 1, final_shots],
		FINAL_INTRO_TIME, true, "THE FINAL!\nP%d vs P%d" % [finalists[0] + 1, finalists[1] + 1])
	sound("fanfare", -2.0, 1.0, true)
	world.fireworks(2)
	net.event("fx", ["fireworks"])
	print("Group stage done: final P%d vs P%d" % [finalists[0] + 1, finalists[1] + 1])


## After each pair of final shots: decided? (or sudden death, up to three extra pairs).
func _final_round_done() -> void:
	var a: int = finalists[0]
	var b: int = finalists[1]
	var ga: int = final_goals.get(a, 0)
	var gb: int = final_goals.get(b, 0)
	if round_i < final_shots:
		_begin_round()
		return
	if ga != gb:
		champion = a if ga > gb else b
		_start_trophy()
		return
	if sudden < 3:
		sudden += 1
		_show_center("SUDDEN DEATH!\nP%d %d - %d P%d" % [a + 1, ga, gb, b + 1], 2.0, true, "SUDDEN DEATH!")
		_begin_round()
		return
	champion = a if players[a].goals >= players[b].goals else b
	_start_trophy()


func _start_trophy() -> void:
	state = "trophy"
	state_t = 0.0
	shooter = -1
	ball.place(spot)
	var who := "THE KEEPER" if champion == 0 else "P%d" % (champion + 1)
	_show_center("%s WINS THE CUP!" % who, TROPHY_TIME, true, ("YOU WIN THE CUP!" if champion == 0 else "%s WINS THE CUP!" % who))
	_trophy_fx()
	net.event("trophy", [champion])
	print("Cup winner: %s" % who)


func _trophy_fx() -> void:
	sound("fanfare", 0.0, 1.0)
	sound("cheer", 0.0, 0.9)
	world.fireworks(5)
	world.confetti_cannons()
	world.mascot_cheer("cup")
	excite = 1.0
	if champion > 0 and champion < players.size():
		players[champion].hold_cup = true


## Where the TV cameras look during the trophy ceremony: [camera position, look-at point].
func ceremony_camera() -> Array:
	if champion > 0 and champion < players.size():
		var p = players[champion]
		return [Vector3(p.position.x, 1.75, p.position.z - 3.6), p.position + Vector3(0, 1.7, 0)]
	return [Vector3(keeper.head_pos.x * 0.6, 1.9, 5.5), keeper.head_pos + Vector3(0, -0.2, 0)]


func _update_trophy() -> void:
	if state != "trophy":
		return
	if champion > 0 and champion < players.size():
		var p = players[champion]
		world.show_trophy(p.global_position + Vector3(0, 2.25, -0.05), 1.0)
	elif champion == 0:
		var w: float = keeper.ws()
		if keeper_in_vr():
			world.show_trophy(keeper.head_pos + Vector3(0.0, -0.45, 0.5) * w, w)  # chest height, in front
		else:
			world.show_trophy(keeper.head_pos + Vector3(0, 0.25, 0.05), 1.0)


func request_shot(p, aim: Vector2, power: float, curve: float, shot: String = "normal") -> void:
	if net.mode == "client":
		net.send_action("shoot", [aim, power, curve, shot], p.index)
	else:
		_on_shoot(p.index, aim, power, curve, shot)


func _on_shoot(index: int, aim: Vector2, power: float, curve: float, shot: String = "normal") -> void:
	if state != "aim" or index != shooter or state_t < READY_TIME - 0.3:
		return
	var p = players[index]
	if shot == "fire" and p.fire_left <= 0:
		shot = "normal"
	pending = {"aim": aim, "power": clampf(power, 0.0, 1.0), "curve": clampf(curve, -1.0, 1.0), "shot": shot}
	p.shots += 1
	shots_total += 1
	state = "runup"
	state_t = 0.0


func _launch() -> void:
	var aim: Vector2 = pending.get("aim", Vector2(0, 1))
	var power: float = pending.get("power", 0.5)
	var curve: float = pending.get("curve", 0.0)
	var shot: String = pending.get("shot", "normal")
	var target := Vector3(clampf(aim.x, -StrikerScript.AIM_X, StrikerScript.AIM_X), aim.y, 0.0)
	if power > 0.85:
		var err := (power - 0.85) / 0.15 * 0.9
		target += Vector3(randf_range(-err, err), randf_range(-err * 0.4, err), 0.0)
	target.y = clampf(target.y, BallScript.R, StrikerScript.AIM_Y_MAX + 0.5)
	var speed := lerpf(SPD_MIN, cur_max_speed, power)
	match shot:
		"chip":
			speed = lerpf(SPD_MIN * 0.75, cur_max_speed * 0.6, power)  # slow = a high, floating arc
		"fire":
			speed = minf(FIRE_SPEED, cur_max_speed * 1.25 + 2.0)
			var p = players[shooter]
			p.fire_left = maxi(0, int(p.fire_left) - 1)
	if keeper.power == "slow":
		speed *= 0.65
	last_shot = shot
	keeper.bubble = ""  # an offer not taken expires with the kick (never in front of the incoming ball)
	ball.place(spot)
	ball.kick(target, speed, curve)
	ball.set_fire(shot == "fire")
	last_kmh = int(roundf(ball.vel.length() * 3.6))
	var sp = players[shooter]
	sp.fastest = maxf(float(sp.fastest), float(last_kmh))
	state = "flight"
	state_t = 0.0
	excite = maxf(excite, 0.5 if shot == "fire" else 0.35)
	sound("kick", 0.0, 1.0, true)
	if shot == "fire":
		sound("fire", -2.0, 1.0, true)
	if power > 0.85:
		wild_t = 6.0
	print("Shot by P%d: %s power %.2f curve %.2f speed %.1f (%d km/h)%s -> (%.1f, %.1f)" % [shooter + 1, shot, power, curve, speed,
		last_kmh, " SLOW-MO" if keeper.power == "slow" else "", target.x, target.y])


func _on_save(kind: String) -> void:
	var worth := 2 if keeper.power == "double" else 1
	saves += worth
	save_streak += 1
	best_save_streak = maxi(best_save_streak, save_streak)
	state = "result"
	state_t = 0.0
	var fast := ball.vel.length() > 12.0
	var text := "SAVED!"
	match kind:
		"head":
			text = "HEADER SAVE!"
		"body":
			text = "BLOCKED!"
		"dive":
			text = "DIVING SAVE!"
		_:
			text = "SUPER SAVE!" if fast or absf(ball.position.x) > 2.4 or ball.position.y > 1.9 or last_shot == "fire" else "SAVED!"
	if worth == 2:
		text += " x2"
	last_result = text
	keeper.haptic(kind)
	keeper.cheer_t = 1.6
	sound("save", 0.0, 1.0, true)
	sound("cheer", -2.0, 1.1, true)
	excite = 1.0
	popup(ball.position + Vector3(0, 0.5, 0.4), text, Color(0.3, 1.0, 0.5))
	burst(ball.position, Color(0.3, 1.0, 0.5), 24)
	world.mascot_cheer("save")
	net.event("fx", ["save"])
	var streak_line := ("  ·  %d SAVES IN A ROW!" % save_streak) if save_streak >= 3 else ""
	_show_center("%s  (%d km/h)\n%s%s" % [text, last_kmh, _score_line(), streak_line], 1.8, true, text + streak_line)
	result_len = _result_time() + _replay_extra(text)
	print("Result: %s (%s) - saves %d goals %d" % [text, kind, saves, goals_total])


func _on_goal() -> void:
	goals_total += 1
	save_streak = 0
	var p = players[shooter] if shooter > 0 and shooter < players.size() else null
	if p != null:
		p.goals += 1
		if last_shot != "normal" or absf(float(pending.get("curve", 0.0))) > 0.5:
			p.trick_goals += 1
		if cup_stage == "final":
			final_goals[shooter] = int(final_goals.get(shooter, 0)) + 1
		if is_local(p) and p.joy >= 0:
			Input.start_joy_vibration(p.joy, 0.7, 0.9, 0.4)
	state = "result"
	state_t = 0.0
	var label := "GOAL!"
	match last_shot:
		"chip":
			label = "CHIP GOAL!"
		"fire":
			label = "FIREBALL GOAL!"
	last_result = label
	world.bulge()
	net.event("bulge", [])
	sound("net", 0.0, 1.0, true)
	sound("cheer", 0.0, 1.0, true)
	excite = 1.0
	shake = 0.5
	var col: Color = p.color if p != null else Color(1, 1, 0)
	popup(ball.position + Vector3(0, 0.6, 0.6), label, col)
	burst(Vector3(-3.0, 2.6, 0.0), col, 26)
	burst(Vector3(3.0, 2.6, 0.0), Color(1, 1, 1), 26)
	var kind := randi() % 3
	_goal_fx(shooter, kind)
	net.event("goal_fx", [shooter, kind])
	_show_center("%s  P%d  (%d km/h)\n%s" % [label, shooter + 1, last_kmh, _score_line()], 1.8, true, "%s  P%d" % [label, shooter + 1])
	result_len = _result_time() + _replay_extra(label)
	print("Result: %s by P%d - saves %d goals %d" % [label, shooter + 1, saves, goals_total])


## Celebration on every machine: the scorer's dance, confetti cannons and the mascot.
func _goal_fx(idx: int, kind: int) -> void:
	if idx > 0 and idx < players.size():
		players[idx].celebrate(kind)
	world.confetti_cannons()
	world.mascot_cheer("goal")
	if cup_stage == "final" or last_shot == "fire":
		world.fireworks(2)


func _on_miss(reason: String) -> void:
	state = "result"
	state_t = 0.0
	last_result = reason
	save_streak = 0
	sound("groan", -2.0, 1.0, true)
	excite = 0.3
	popup(ball.position + Vector3(0, 0.6, 0), reason, Color(1.0, 0.75, 0.3))
	_show_center("%s\n%s" % [reason, _score_line()], 1.8, true, reason)
	result_len = _result_time()
	print("Result: %s - saves %d goals %d" % [reason, saves, goals_total])


func _score_line() -> String:
	if cup_stage == "final" and finalists.size() == 2:
		return "THE FINAL:  P%d %d - %d P%d" % [finalists[0] + 1, int(final_goals.get(finalists[0], 0)),
			int(final_goals.get(finalists[1], 0)), finalists[1] + 1]
	return "KEEPER %d saves  ·  STRIKERS %d goals" % [saves, goals_total]


func _match_over() -> void:
	state = "over"
	state_t = 0.0
	shooter = -1
	for p in players:
		if p.index > 0:
			p.hold_cup = false
	world.show_trophy(Vector3.INF)
	world.mascot_cheer("")
	var verdict := "IT'S A DRAW!"
	var kept := shots_total - goals_total
	if champion == 0:
		verdict = "THE KEEPER WINS THE CUP!"
	elif champion > 0:
		verdict = "P%d WINS THE CUP!" % (champion + 1)
	elif goals_total * 2 > shots_total:
		verdict = "THE STRIKERS WIN!"
	elif goals_total * 2 < shots_total:
		verdict = "THE KEEPER WINS!"
	var awards := _awards()
	set_meta("awards", awards)
	_show_center("FULL TIME!  %s\nThe keeper kept out %d of %d shots (%d saves)\n\n%s\n\nA / Enter (VR: trigger) to play again" \
		% [verdict, kept, shots_total, saves, awards], 0.0, true, "FULL TIME!\n" + verdict)
	sound("whistle", 0.0, 0.9, true)
	sound("cheer", 0.0, 0.9, true)
	excite = 1.0
	print("Match over: %s saves %d goals %d shots %d | awards: %s" % [verdict, saves, goals_total, shots_total, awards.replace("\n", " | ")])


## Fun end-of-cup awards (a few lines).
func _awards() -> String:
	var out: PackedStringArray = []
	var boot = null
	var rocket = null
	var trick = null
	var sharp = null
	for p in active_strikers():
		if p.goals > 0 and (boot == null or p.goals > boot.goals):
			boot = p
		if p.fastest > 0.0 and (rocket == null or p.fastest > rocket.fastest):
			rocket = p
		if p.trick_goals > 0 and (trick == null or p.trick_goals > trick.trick_goals):
			trick = p
		if p.shots >= 3 and p.goals == p.shots and (sharp == null or p.goals > sharp.goals):
			sharp = p
	if boot != null:
		out.append("GOLDEN BOOT: P%d (%d goal%s)" % [boot.index + 1, boot.goals, "" if boot.goals == 1 else "s"])
	if shots_total >= 3 and float(shots_total - goals_total) / float(shots_total) >= 0.4:
		out.append("GOLDEN GLOVE: the KEEPER (%d%% kept out)" % int(100.0 * float(shots_total - goals_total) / float(shots_total)))
	if best_save_streak >= 3:
		out.append("THE WALL: %d saves in a row!" % best_save_streak)
	if rocket != null:
		out.append("ROCKET SHOT: P%d (%d km/h)" % [rocket.index + 1, int(rocket.fastest)])
	if trick != null:
		out.append("TRICK SHOT: P%d (%d chip / curl / fireball goals)" % [trick.index + 1, trick.trick_goals])
	if sharp != null:
		out.append("PERFECT AIM: P%d scored every shot" % (sharp.index + 1))
	if out.is_empty():
		out.append("EVERYONE: what a match!")
	return "\n".join(out.slice(0, 5))


# --- Power-ups (host / local) ---------------------------------------------------------------------

func keeper_collect(kind: String) -> void:
	if keeper.bubble == "" or not is_host_side():
		return
	keeper.bubble = ""
	keeper.power = kind
	_power_fx(kind)
	net.event("power", [kind])
	var name: String = keeper.POWER_NAMES.get(kind, kind)
	_show_center("KEEPER POWER-UP: %s!" % name, 1.6, true, "%s!" % name)
	print("Keeper took the power-up: %s" % kind)


func _power_fx(kind: String) -> void:
	sound("power", -2.0, 1.0 + 0.1 * POWERS.find(kind))
	var c: Color = keeper.POWER_COLORS.get(kind, Color.WHITE)
	burst(keeper.head_pos + Vector3(0, -0.4, 0.4), c, 20, false)
	if keeper_in_vr():
		keeper.hand_l.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.15, 0.0)
		keeper.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.15, 0.0)


func is_host_side() -> bool:
	return net == null or net.mode != "client"


# --- Replays (TV views: slow motion from the side, after goals and great saves) ------------------

func _has_tv_views() -> bool:
	for p in players:
		if p.has_meta("view"):
			return true
	return false


## Host: extra result time for a replay (the TV machine plays it; the VR keeper just waits a moment).
func _replay_extra(result: String) -> float:
	if not _replay_worthy(result):
		return 0.0
	if net.mode == "local" or (net.mode == "host" and net.connected):
		return REPLAY_DELAY + 1.9
	return 0.0


func _replay_worthy(result: String) -> bool:
	return result.contains("GOAL") or result.begins_with("SUPER") or result.begins_with("DIVING") or result.begins_with("HEADER")


func _record(delta: float) -> void:
	if state == "runup":
		rec.clear()
		rec_t = 0.0
		return
	if state != "flight" and not (state == "result" and state_t < 0.5):
		return
	if rec.size() > 300:
		return
	rec_t += delta
	rec.append([rec_t, ball.global_position, keeper.head_pos, keeper.down_dir, keeper.glove_l, keeper.glove_r])


func _start_replay() -> void:
	if rec.size() < 6 or not _has_tv_views():
		return
	replay_on = true
	replay_t = 0.0
	replay_len = minf(float(rec[rec.size() - 1][0]) / 0.45, 1.8)
	if replay_ball == null:
		replay_ball = MeshInstance3D.new()
		replay_ball.mesh = sphere_mesh(BallScript.R)
		replay_ball.material_override = make_material(Color(1.0, 0.95, 0.8), 0.6)
		add_child(replay_ball)
	replay_ball.visible = true
	ball.hide_for_replay = true
	sound("replay", -10.0)


func _stop_replay() -> void:
	if not replay_on:
		return
	replay_on = false
	keeper.replay_pose = []
	ball.hide_for_replay = false
	if replay_ball != null:
		replay_ball.visible = false


func _update_replay(delta: float) -> void:
	if state == "result" and not replay_on and state_t >= REPLAY_DELAY and state_t - delta < REPLAY_DELAY and _replay_worthy(last_result):
		_start_replay()
	if not replay_on:
		return
	if state != "result":
		_stop_replay()
		return
	replay_t += delta
	var total: float = rec[rec.size() - 1][0]
	var tt := clampf(replay_t / maxf(replay_len, 0.1), 0.0, 1.0) * total
	var k := 0
	while k < rec.size() - 2 and float(rec[k + 1][0]) < tt:
		k += 1
	var a: Array = rec[k]
	var b: Array = rec[mini(k + 1, rec.size() - 1)]
	var span := maxf(0.0001, float(b[0]) - float(a[0]))
	var f := clampf((tt - float(a[0])) / span, 0.0, 1.0)
	replay_pos = (a[1] as Vector3).lerp(b[1], f)
	replay_ball.global_position = replay_pos
	keeper.replay_pose = [(a[2] as Vector3).lerp(b[2], f), (a[3] as Vector3).lerp(b[3], f).normalized(),
		(a[4] as Vector3).lerp(b[4], f), (a[5] as Vector3).lerp(b[5], f)]
	if replay_t > replay_len + 0.3:
		_stop_replay()


func replay_look() -> Vector3:
	return Vector3(0, 1.1, 1.5).lerp(replay_pos, 0.45)


# --- Main loop -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -19.0
	music.play_track(1 if cup_stage == "final" or state == "trophy" else round_i % 3)
	_ensure_join_listener()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	excite = maxf(0.05, excite - delta * 0.35)
	if state == "trophy":
		excite = maxf(excite, 0.8)
	shake = maxf(0.0, shake - delta * 1.2)
	wild_t = maxf(0.0, wild_t - delta)
	world.set_excite(excite)
	_place_strikers()
	_update_aim_visuals()
	_update_vr_text(delta)
	_record(delta)
	_update_replay(delta)
	_update_trophy()
	for p in players:
		if p.has_meta("replay_label"):
			(p.get_meta("replay_label") as Label).visible = replay_on
	world.set_scoreboard(_scoreboard_text())
	var cont := _continue_pressed()
	var cont_edge := cont and not cont_was
	cont_was = cont
	if net.mode == "client":
		_client_update(delta, cont_edge)
		return
	_update_lost_pads(delta)
	state_t += delta
	match state:
		"intro":
			if state_t >= intro_dur or (state_t > 1.5 and cont_edge):
				_begin_round()
		"final_intro":
			if state_t >= FINAL_INTRO_TIME:
				_begin_round()
		"aim":
			var p = players[shooter] if shooter > 0 and shooter < players.size() else null
			if p == null or not p.active:
				_advance()
			elif state_t >= AIM_TIME:
				var a: Vector2 = p.aim
				_show_center("SHOT CLOCK!", 1.0)
				_on_shoot(shooter, a, 0.55, 0.0)
		"runup":
			if state_t >= RUNUP_TIME:
				_launch()
		"result":
			if state_t >= result_len:
				_advance()
		"trophy":
			if state_t >= TROPHY_TIME:
				_match_over()
		"over":
			if state_t > 1.5 and cont_edge:
				_begin_match()


func _physics_process(delta: float) -> void:
	if not ready_to_play or net.mode == "client" or keeper == null:
		return
	var spheres: Array = keeper.save_spheres(delta)
	if state != "flight" and state != "result":
		return
	var res: String = ball.sim(delta, spheres if state == "flight" else [])
	if res == "":
		return
	if res == "post":
		sound("post", -2.0, 1.0, true)
		excite = maxf(excite, 0.7)
		if state == "flight":
			popup(ball.position + Vector3(0, 0.5, 0.3), "POST!", Color(1, 1, 1))
	elif res == "bounce":
		sound("bounce", -8.0, 1.0, true)
	elif state != "flight":
		return
	elif res.begins_with("save:"):
		_on_save(res.substr(5))
	elif res == "goal":
		_on_goal()
	elif res.begins_with("miss:"):
		_on_miss(res.substr(5))


func _client_update(delta: float, cont_edge: bool) -> void:
	_check_join(delta)
	_update_lost_pads(delta)
	state_t += delta
	if cont_edge and ((state == "over" or state == "intro") and state_t > 1.5):
		net.send_action("continue", [])


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


## A / Enter on this machine (VR: the trigger or A) skips the intro and plays again after full time.
func _continue_pressed() -> bool:
	if state != "intro" and state != "over":
		return false
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for p in players:
		if is_local(p) and p.active and p.action_pressed():
			return true
	if keeper_in_vr() and players[0].action_pressed():
		return true
	return false


## Bot hook: same as pressing A on the intro / full-time screens.
func debug_continue() -> void:
	if net.mode == "client":
		net.send_action("continue", [])
	else:
		_on_continue()


func _on_continue() -> void:
	if state == "intro" and state_t > 1.0:
		_begin_round()
	elif state == "over" and state_t > 1.0:
		_begin_match()


## Where everyone stands: the shooter behind the ball (running up when kicking), the rest queue at the D.
## Cup ceremony: the champion steps forward to lift the trophy, the others line up behind.
func _queue_pos(k: int) -> Vector3:
	return Vector3(-3.0 + (k % 6) * 1.2, 0.0, 18.8 + (k / 6) * 1.2)


func _place_strikers() -> void:
	var k := 0
	for i in range(1, players.size()):
		var p = players[i]
		if not p.active:
			continue
		if state == "trophy" and i == champion:
			p.run = 0.0
			p.stand_at = Vector3(0.0, 0.0, 8.5)
		elif i == shooter and state in ["aim", "runup", "flight", "result"]:
			p.run = 1.0
			if state == "aim":
				p.stand_at = spot + Vector3(0.25, 0.0, 1.9)
			else:
				p.stand_at = spot + Vector3(0.22, 0.0, 0.35)
		else:
			p.run = 0.0
			p.stand_at = _queue_pos(k) if state != "trophy" else Vector3(-3.0 + k * 1.2, 0.0, 12.5)
			k += 1


func _update_aim_visuals() -> void:
	if reticle == null:
		reticle = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.2
		tm.outer_radius = 0.28
		tm.rings = 16
		tm.ring_segments = 6
		reticle.mesh = tm
		reticle.rotation.x = PI * 0.5
		reticle.layers = 2  # the keeper's cameras skip layer 2
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1, 1, 0.3)
		rm.no_depth_test = true
		reticle.material_override = rm
		add_child(reticle)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.albedo_color = Color(1, 1, 1, 0.7)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for i in 9:
			var d := MeshInstance3D.new()
			d.mesh = sphere_mesh(0.045)
			d.material_override = dm
			d.layers = 2
			add_child(d)
			dots.append(d)
	var p = players[shooter] if shooter > 0 and shooter < players.size() else null
	var show: bool = p != null and is_local(p) and (state == "aim" or state == "runup")
	reticle.visible = show
	for d in dots:
		d.visible = show
	ball.glow = 0.0
	if p != null and state == "aim" and p.charging:
		ball.glow = p.power
	if not show:
		return
	var aim: Vector2 = p.aim
	var target := Vector3(aim.x, aim.y, 0.05)
	reticle.global_position = target
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.08
	reticle.scale = Vector3.ONE * pulse * (1.0 + maxf(0.0, p.power - 0.85) * 4.0)
	var rm2: StandardMaterial3D = reticle.material_override
	rm2.albedo_color = Color(1.0, 0.3, 0.2) if p.power > 0.85 else p.color.lightened(0.4)
	var pw: float = maxf(p.power, 0.3)
	var spd := lerpf(SPD_MIN, cur_max_speed, pw)
	if p.charging and p.shot == "chip":
		spd = lerpf(SPD_MIN * 0.75, cur_max_speed * 0.6, pw)
	elif p.charging and p.shot == "fire":
		spd = minf(FIRE_SPEED, cur_max_speed * 1.25 + 2.0)
	var pl: Array = BallScript.plan(spot, Vector3(aim.x, aim.y, 0.0), spd, p.curve)
	var v0: Vector3 = pl[0]
	var acc: Vector3 = pl[1]
	var tf: float = pl[2]
	for i in dots.size():
		var t := tf * float(i + 1) / float(dots.size() + 1)
		dots[i].global_position = BallScript.point_at(spot, v0, acc, t)


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) --------------------------------------------

func on_client_joined() -> void:
	_show_center("THE STRIKERS ARE HERE!", 1.5)
	if state == "wait" or state == "over":
		_begin_match()


func on_client_left() -> void:
	for i in range(2, players.size()):
		if players[i].active:
			players[i].set_active(false)
	state = "wait"
	shooter = -1
	ball.place(spot)
	world.show_trophy(Vector3.INF)
	_show_center("The strikers left - waiting for them to come back…", 0.0)


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
				_deactivate(p)
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
		"continue":
			_on_continue()
		"shoot":
			if args.size() >= 3:
				var a: Vector2 = args[0]
				var pw: float = args[1]
				var cv: float = args[2]
				var shot: String = str(args[3]) if args.size() > 3 else "normal"
				_on_shoot(index, a, pw, cv, shot)
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused
			if not paused:
				keeper.trig_block = true


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false, ("PAUSED\n" + who) if paused else "")
	if vr_center != null and paused:
		VrText.snap(vr_center)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	keeper.trig_block = true  # the trigger that resumed must not kick off or restart anything
	cont_was = true
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHold the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ss: Array = []
	for i in range(1, players.size()):
		var p = players[i]
		ss.append([p.active, p.goals, p.shots, p.power, p.charging, p.fire_left, p.hold_cup])
	return [state, state_t, shooter, round_i, rounds_total, ball.position, ball.vel, ball.visible,
		[keeper.head_pos, keeper.down_dir, keeper.glove_l, keeper.glove_r], saves, goals_total, ss,
		cur_max_speed, shots_total, last_result, cup_stage, finalists, [final_goals.get(finalists[0], 0) if finalists.size() == 2 else 0,
		final_goals.get(finalists[1], 0) if finalists.size() == 2 else 0], champion, keeper.power, keeper.bubble, keeper.bubble_pos,
		ball.fire, last_kmh, sudden, last_shot]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 26:
		return
	synced = true
	var new_state: String = s[0]
	var new_shooter: int = s[2]
	if new_state != state or new_shooter != shooter:
		if new_state == "aim" and new_shooter > 0 and new_shooter < players.size() and is_local(players[new_shooter]):
			players[new_shooter].prepare_turn()
		state = new_state
		shooter = new_shooter
		state_t = float(s[1])
	round_i = s[3]
	rounds_total = s[4]
	ball.net_pos = s[5]
	ball.net_vel = s[6]
	ball.visible = s[7]
	var kd: Array = s[8]
	keeper.net_head = kd[0]
	keeper.net_down = kd[1]
	keeper.net_gl = kd[2]
	keeper.net_gr = kd[3]
	saves = s[9]
	goals_total = s[10]
	var ss: Array = s[11]
	for i in ss.size():
		var idx := i + 1
		if idx >= players.size():
			break
		var st: Array = ss[i]
		var p = players[idx]
		var act: bool = st[0]
		if act != p.active:
			p.set_active(act)
			on_player_activity_changed(p)
		p.goals = st[1]
		p.shots = st[2]
		if not is_local(p):
			p.power = st[3]
			p.charging = st[4]
		p.fire_left = st[5]
		p.hold_cup = st[6]
	cur_max_speed = s[12]
	shots_total = s[13]
	last_result = s[14]
	cup_stage = s[15]
	finalists.clear()
	for f in s[16]:
		finalists.append(int(f))
	var fg: Array = s[17]
	final_goals.clear()
	if finalists.size() == 2:
		final_goals[finalists[0]] = int(fg[0])
		final_goals[finalists[1]] = int(fg[1])
	champion = s[18]
	keeper.power = s[19]
	keeper.bubble = s[20]
	keeper.bubble_pos = s[21]
	if bool(s[22]) != ball.fire:
		ball.set_fire(s[22])
	last_kmh = s[23]
	sudden = s[24]
	last_shot = s[25]


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
			if str(args[0]) == "cheer":
				excite = 1.0
		"burst":
			burst(args[0], args[1], args[2], false)
		"popup":
			popup(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false, str(args[2]) if args.size() > 2 else "\u0001")
		"bulge":
			world.bulge()
			shake = 0.5
		"goal_fx":
			_goal_fx(int(args[0]), int(args[1]))
		"fx":
			match str(args[0]):
				"save":
					world.mascot_cheer("save")
				"fireworks":
					world.fireworks(2)
		"power":
			_power_fx(str(args[0]))
		"trophy":
			champion = int(args[0])
			_trophy_fx()
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The keeper paused the game")


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
	help_label = _make_label(19)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -64
	help_label.offset_bottom = -12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if OS.has_environment("DUO_JOIN"):
		help_label.text = "STRIKERS: stick / WASD / mouse aims · HOLD A / Space / click to power up, let go to shoot · X / C: chip · Y / F: FIREBALL · triggers or Q/E bend it\n" \
			+ "More strikers: press A on another controller · Start / Esc menu"
	else:
		help_label.text = "STRIKER: stick / arrows aim · HOLD A (Enter) to power up, let go to shoot · X (/): chip · Y ('): FIREBALL · triggers (, .) bend it\n" \
			+ "KEEPER: A-D / stick / mouse shuffle · Space / A / click dives (hold W = high) · more strikers: press A on a controller"


## TV banner; vr: the short version for the VR keeper ("\u0001" = the first two lines).
func _show_center(text: String, duration: float, broadcast: bool = true, vr: String = "\u0001") -> void:
	if net and broadcast:
		net.event("center", [text, duration, vr])
	center_label.text = text
	center_label.modulate.a = 1.0
	if center_tween:
		center_tween.kill()
	if duration > 0.0:
		center_tween = create_tween()
		center_tween.tween_interval(duration)
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.5)
	if vr == "\u0001":
		var lines := text.split("\n")
		vr = "\n".join(lines.slice(0, 2)) if lines.size() > 0 else ""
	_vr_say(vr, duration if duration > 0.0 else 9999.0)


func _vr_say(text: String, duration: float) -> void:
	vr_msg = text
	vr_msg_t = duration


func _scoreboard_text() -> String:
	var line3 := ""
	match state:
		"aim", "runup", "flight":
			line3 = "P%d TO SHOOT" % (shooter + 1)
			if keeper.power != "":
				line3 += "  ·  KEEPER: %s" % str(keeper.POWER_NAMES.get(keeper.power, ""))
		"result":
			line3 = "%s  %d km/h" % [last_result, last_kmh]
		"final_intro":
			line3 = "THE FINAL IS NEXT!"
		"trophy":
			line3 = "CUP WINNER: %s" % ("THE KEEPER" if champion == 0 else "P%d" % (champion + 1))
		"over":
			line3 = "FULL TIME"
		"intro":
			line3 = "KICK OFF SOON"
		_:
			line3 = "WAITING FOR STRIKERS"
	var line2 := "ROUND %d / %d" % [mini(round_i + 1, rounds_total), rounds_total]
	if cup_stage == "final" and finalists.size() == 2:
		line2 = "FINAL  P%d %d - %d P%d" % [finalists[0] + 1, int(final_goals.get(finalists[0], 0)), int(final_goals.get(finalists[1], 0)), finalists[1] + 1]
	return "SAVES %d   ·   GOALS %d\n%s\n%s" % [saves, goals_total, line2, line3]


func glove_text() -> String:
	var hint := ""
	match state:
		"aim":
			hint = "\nTOUCH THE BUBBLE!" if keeper.bubble != "" else "\nGET READY!"
		"runup", "flight":
			hint = "\nSAVE IT!"
		"result":
			hint = "\n" + last_result
		"over":
			hint = "\nTRIGGER: play again"
		"intro":
			hint = "\nTRIGGER: kick off"
	if keeper.power != "":
		hint += "\n" + str(keeper.POWER_NAMES.get(keeper.power, ""))
	return "SAVES %d  GOALS %d%s" % [saves, goals_total, hint]


func hud_text(p) -> String:
	if net.mode == "client" and not synced:
		return "Syncing with the keeper…"
	var head := "ROUND %d/%d   SAVES %d · GOALS %d" % [mini(round_i + 1, rounds_total), rounds_total, saves, goals_total]
	if cup_stage == "final" and finalists.size() == 2:
		head = "THE FINAL   P%d %d - %d P%d" % [finalists[0] + 1, int(final_goals.get(finalists[0], 0)), int(final_goals.get(finalists[1], 0)), finalists[1] + 1]
	if state == "trophy":
		return "CUP WINNER: %s!" % ("THE KEEPER" if champion == 0 else "P%d" % (champion + 1))
	if p.index == 0:
		match state:
			"aim", "runup":
				return head + "\nYOU'RE THE KEEPER! P%d is lining up…\nShuffle (A/D, stick) · dive (Space / A / click)" % (shooter + 1)
			"flight":
				return head + "\nSAVE IT!"
			"result":
				return head + "\n" + last_result
		return head + "\nYOU'RE THE KEEPER!"
	var line := head + "\nYOUR GOALS %d%s" % [p.goals, "   ·   FIREBALL ready (Y)" if p.fire_left > 0 else ""]
	if state == "final_intro":
		return line + ("\nYOU'RE IN THE FINAL!" if finalists.has(p.index) else "\nThe final is next - cheer them on!")
	if state == "aim" and shooter == p.index:
		if keeper.power == "slow":
			line += "\nKEEPER SLOW-MO: your shot will be slower!"
		elif keeper.power == "big":
			line += "\nKEEPER BIG GLOVES: aim for the corners!"
		if not can_shoot():
			return line + "\nYOUR SHOT! Aim with the stick…"
		if p.charging:
			if p.power > 0.85:
				return line + "\nTOO MUCH POWER - wild shot!"
			return line + "\n…let go to SHOOT!  (%s)" % {"normal": "shot", "chip": "CHIP", "fire": "FIREBALL"}.get(p.shot, "shot")
		var left := int(ceilf(AIM_TIME - state_t))
		var tip := "Aim, then HOLD A to power up (X: chip · Y: FIREBALL)"
		if wild_t > 0.0:
			tip = "Tip: let go before the meter turns RED!"
		elif p.idle_aim_t > 6.0:
			tip = "HOLD A, watch the meter, LET GO to shoot!"
		return line + "\nYOUR SHOT! %s%s" % [tip, "  (%d)" % left if left <= 5 else ""]
	if state == "runup" or state == "flight":
		return line + ("\nGO GO GO!" if shooter == p.index else "\nP%d shoots…" % (shooter + 1))
	if state == "result":
		return line + "\n%s  %d km/h" % [last_result, last_kmh]
	if state == "aim":
		var pos := order.find(p.index) - turn_k
		if pos > 0:
			return line + "\nP%d is shooting · you're up in %d" % [shooter + 1, pos]
		return line + "\nP%d is shooting" % (shooter + 1)
	return line


## Short messages for the VR keeper: far down the pitch, above the run-up line, normal depth test, and
## pushed out (and scaled up) with the keeper's world scale so they stay comfortably far in real metres.
func _update_vr_text(delta: float) -> void:
	if help_label.modulate.a > 0.0 and matches >= 1 and state != "intro" and state != "wait":
		help_label.modulate.a = maxf(0.25, help_label.modulate.a - get_process_delta_time() * 0.2)
	vr_msg_t -= delta
	if not keeper_in_vr():
		return
	var cam: XRCamera3D = players[0].xr_camera
	var w: float = keeper.ws()
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 44
		vr_center.outline_size = 26
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 700.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_center)
	vr_center.pixel_size = 0.0022 * w  # VrText scales it by its comfort factor
	var alpha := clampf(vr_msg_t / 0.5, 0.0, 1.0)
	vr_center.text = vr_msg
	vr_center.modulate.a = alpha
	vr_center.outline_modulate = Color(0, 0, 0, alpha)
	# Never cover the incoming ball: hide while a shot is coming.
	vr_center.visible = state != "runup" and state != "flight"
	VrText.follow(vr_center, cam, self, 0.35 * w, 1.8 * w)
