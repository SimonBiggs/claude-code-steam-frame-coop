extends Node3D
## RHYTHM BAND - co-op music game. The VR player is the DRUMMER, hitting floating drums with their
## hands as glowing balls fly into them; the TV players (1-6) play a 3-lane note highway each
## (Guitar-Hero style). Every song is generated in code: the backing loop is synthesized and the players
## make the melody and the beat themselves. Hits fill the shared CROWD meter and the band combo;
## stars at the end of each song; a tour is 3 songs, each one faster.
## Modes, networking and party join follow docs/GAME_DEV_GUIDE.md and games/marble_maze.
## The song clock: the host owns it (snapshots carry it); every machine plays the same backing
## locally and judges its own players against the clock it hears, then reports hits to the host.

const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SongScript := preload("res://games/rhythm_band/song.gd")
const InstrumentsScript := preload("res://games/rhythm_band/instruments.gd")
const StageScript := preload("res://games/rhythm_band/stage.gd")
const DrummerScript := preload("res://games/rhythm_band/drummer.gd")
const GuitaristScript := preload("res://games/rhythm_band/guitarist.gd")
const HighwayScript := preload("res://games/rhythm_band/highway.gd")
const JoinListenerScript := preload("res://games/rhythm_band/join_listener.gd")

const MAX_PLAYERS := 7  # VR drummer + 6 guitarists
const MAX_LOCAL_VIEWS := 6
const PAD_LEAVE_TIME := 20.0
const PERFECT := 0.085  # seconds either side
const GOOD := 0.17
const NOTE_BARS := 24
const INTRO_TIME := 3.5
const FIRST_INTRO_TIME := 7.0
const RESULTS_AUTO := 12.0
const SONGS_PER_TOUR := 3
const START_LEAD := 0.6
const DRUM_SPOT := Vector3(0.0, 0.8, 1.2)
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0),
	Color(0.35, 0.9, 0.35), Color(1.0, 0.8, 0.1), Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.15)]
const SOUNDS := {
	"go": [0.4, 440.0, 880.0, 0.35, "square", 0.0],
	"join": [0.45, 523.0, 1318.0, 0.3, "tri", 0.0],
	"tour": [1.0, 392.0, 1568.0, 0.35, "tri", 0.0],
}

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var inst: InstrumentsScript
var stage: StageScript
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var synced := false
var join_listener: Node
var joy_owner := {}
var views_root: Control
var last_view_area := Vector2.ZERO
var mats := {}
var meshes := {}
var headless := false

var state := "wait"  # wait, intro, play, results, tour
var state_t := 0.0
var song = null
var song_idx := 0
var song_bars := NOTE_BARS
var song_serial := 0
var song_t := -1.0
var crowd := 0.5
var combo := 0
var best_combo := 0
var score := 0
var best := 0
var band_hits := 0
var band_misses := 0
var last_stars := 0
var tour_stars := 0
var d_judged := PackedByteArray()
var d_next := 0
var last_beat := -999
var last_pluck := -1
var cheer_cd := 0.0
var cont_was := false
var vr_start_was := false

var backing: AudioStreamPlayer
var backing_serial := -1
var synth_task := -1
var synth_obj = null
var seek_cd := 0.0

var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D


func _ready() -> void:
	randomize()
	headless = DisplayServer.get_name() == "headless"
	stage = StageScript.new()
	stage.name = "Stage"
	stage.main = self
	add_child(stage)
	stage.build()
	inst = InstrumentsScript.new()
	inst.name = "Instruments"
	add_child(inst)
	backing = AudioStreamPlayer.new()
	backing.name = "Backing"
	backing.volume_db = -9.0
	add_child(backing)
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
		_show_center("Connecting to the VR drummer…", 0.0, false)
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
	stage.set_tags_for_vr(players[0].vr)
	if mode == "host":
		state = "wait"
		_load_song(0, song_bars)
		_show_center("RHYTHM BAND\nWaiting for the TV band to join…\nDrum along while you wait! Pull the trigger to start the first song now.", 0.0)
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED", 1.5, false)
	else:
		_start_song(0)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave a scale behind for the next game
	if synth_task >= 0:
		WorkerThreadPool.wait_for_task_completion(synth_task)
		synth_task = -1


# --- Helpers -------------------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var k := "%s/%.2f" % [color.to_html(), glow]
	if mats.has(k):
		return mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mats[k] = m
	return m


func sphere_mesh(r: float) -> SphereMesh:
	var k := "s%.4f" % r
	if meshes.has(k):
		return meshes[k]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 7
	meshes[k] = m
	return m


func box_mesh(size: Vector3) -> BoxMesh:
	var k := "b%s" % str(size)
	if meshes.has(k):
		return meshes[k]
	var m := BoxMesh.new()
	m.size = size
	meshes[k] = m
	return m


func cyl_mesh(r_top: float, r_bottom: float, h: float, seg: int) -> CylinderMesh:
	var k := "c%.3f/%.3f/%.3f/%d" % [r_top, r_bottom, h, seg]
	if meshes.has(k):
		return meshes[k]
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	meshes[k] = m
	return m


## A basis whose Y axis points along dir (for cylinders laid along a direction).
func basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.UP.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


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


func burst(pos: Vector3, color: Color, amount: int = 24, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.4
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -4.0, 0)
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.mesh = box_mesh(Vector3(0.07, 0.07, 0.01))
	p.material_override = make_material(color, 1.2)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	if broadcast and net != null:
		net.event("burst", [pos, color, amount])


func popup(pos: Vector3, text: String, color: Color, size: float = 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.0012 * size
	l.outline_size = 14
	l.modulate = color
	l.render_priority = 5
	if players.size() > 0 and players[0].vr:
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	l.global_position = pos
	if players.size() > 0 and players[0].vr:
		var cam: Node3D = players[0].xr_camera
		var face := pos - cam.global_position
		face.y = 0.0
		if face.length() > 0.01:
			l.global_basis = Basis(Vector3.UP, atan2(-face.x, -face.z))
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "global_position", pos + Vector3(0, 0.12, 0), 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.6).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# --- Players and views -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	var d := DrummerScript.new()
	d.main = self
	d.ghost = mode == "client"
	d.key_set = 0
	add_child(d)
	players.append(d)
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(1, MAX_PLAYERS):
		var g := GuitaristScript.new()
		g.index = i
		g.main = self
		g.color = PLAYER_COLORS[i]
		g.remote = mode == "host"
		if i == 1:
			g.key_set = 1 if mode == "client" else 0
		add_child(g)
		players.append(g)
		g.set_active(i == 1 and mode != "host")
		if i > top:
			g.set_meta("no_seat", true)  # local split screen tops out at 6 views
	for p in players:
		if p.index > 0:
			stage.set_avatar_visible(p.index, p.active)


func is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _apply_vr_performance() -> void:
	for n in stage.get_children():
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
		print("VR headset found: player 1 is the drummer in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = DRUM_SPOT
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
		print("No VR headset: %s" % ("TV guitarists" if mode == "client" else "split screen, player 1 drums with the keyboard"))
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
	bg.color = Color(0.05, 0.04, 0.1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	views_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One split-screen view (SubViewport + camera + drawn overlay) per local player, made when they join.
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
	cam.far = 60.0
	cam.fov = 62.0
	vp.add_child(cam)
	cam.current = true
	if p.index == 0:
		p.attach_camera(cam)
	else:
		p.camera = cam
		cam.global_transform = stage.tv_camera(p.index)
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hw: Control = HighwayScript.new()
	hw.main = self
	hw.p = p
	hud_layer.add_child(hw)
	hw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.hud = hw
	p.highway = hw


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


## Called by the join listener for every input event: A on a controller nobody owns joins the band.
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
		if not is_local(p) or p.active or p.has_meta("want_join") or p.joy >= 0 or p.pad_lost_t >= 0.0 or p.has_meta("no_seat"):
			continue
		return i
	return -1


func _join_slot(device: int):
	var idx := _next_free_index()
	if idx < 0:
		_show_center("The band is full!", 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


## Local: join now. TV machine: ask the host (retried by _check_join until it agrees).
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
	if p.index > 0:
		p.reset_for_song()
	_show_center("PLAYER %d JOINS THE BAND!" % (p.index + 1), 1.5)
	sound("join", -4.0, 1.0, true)
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
	Engine.set_meta("rhythm_band_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("rhythm_band_party"):
		return
	var saved: Dictionary = Engine.get_meta("rhythm_band_party")
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
		if p.active or not is_local(p) or p.has_meta("no_seat"):
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


## Test hook: join a guitarist without a controller (index -1: the next free seat).
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
		net.send_action("join", [p.index], 1)


func on_player_activity_changed(p) -> void:
	if p.active and is_local(p):
		_ensure_view(p)
	if p.active:
		p.remove_meta("want_join")
	if p.index > 0:
		stage.set_avatar_visible(p.index, p.active)
	_layout_views()
	print("Player %d is now %s" % [p.index + 1, "playing" if p.active else "waiting"])


func active_guitarists() -> Array:
	var out: Array = []
	for p in players:
		if p.index > 0 and p.active:
			out.append(p)
	return out


# --- Songs and the clock ---------------------------------------------------------------

func _loop_cache() -> Dictionary:
	if not Engine.has_meta("rhythm_band_loops"):
		Engine.set_meta("rhythm_band_loops", {})
	return Engine.get_meta("rhythm_band_loops")


func _load_song(i: int, bars: int) -> void:
	song_idx = i
	song_bars = bars
	song = SongScript.new()
	song.setup(i, bars)
	d_judged = PackedByteArray()
	d_judged.resize(song.d_t.size())
	d_next = 0
	last_beat = -999
	last_pluck = -1
	backing.stop()
	backing.stream = null
	backing_serial = -1
	stage.set_song_title(song.title)
	var pitches: Array[int] = []
	for c in 4:
		for lane in 3:
			pitches.append(song.pitch_for(c, lane))
	inst.warm(pitches)
	_ensure_audio()
	for p in players:
		if p.index > 0:
			p.reset_for_song()


## Backing audio: synthesize the song's loop on a worker thread once (cached), then tile it.
func _ensure_audio() -> void:
	if song == null:
		return
	var cache := _loop_cache()
	if cache.has(song.loop_key()):
		if backing_serial != song_serial or backing.stream == null:
			song.loop_bytes = cache[song.loop_key()]
			backing.stream = song.make_stream()
			backing_serial = song_serial
		_prefetch((song_idx + 1) % SONGS_PER_TOUR)
	elif synth_task < 0:
		synth_obj = song
		synth_task = WorkerThreadPool.add_task(Callable(song, "synth_loop"))


func _prefetch(i: int) -> void:
	if synth_task >= 0:
		return
	var s = SongScript.new()
	s.setup(i, 2)
	if _loop_cache().has(s.loop_key()):
		return
	synth_obj = s
	synth_task = WorkerThreadPool.add_task(Callable(s, "synth_loop"))


func _poll_synth() -> void:
	if synth_task < 0 or not WorkerThreadPool.is_task_completed(synth_task):
		return
	WorkerThreadPool.wait_for_task_completion(synth_task)
	synth_task = -1
	_loop_cache()[synth_obj.loop_key()] = synth_obj.loop_bytes
	print("Music: synthesized the backing for song %d" % (int(synth_obj.idx) + 1))
	synth_obj = null
	_ensure_audio()


## Keeps the backing track playing in step with the song clock.
func _sync_audio(delta: float) -> void:
	seek_cd -= delta
	if state != "play" or song == null or backing.stream == null or backing_serial != song_serial:
		if backing.playing and state != "play" and state != "results":
			backing.stop()
		return
	if song_t < 0.0 or song_t >= song.length - 0.05:
		return
	if not backing.playing:
		backing.volume_db = -9.0
		backing.play(song_t)
		return
	if headless:
		return
	var a_t := backing.get_playback_position() + AudioServer.get_time_since_last_mix()
	var diff := a_t - song_t
	if absf(diff) > 0.12 and seek_cd <= 0.0:
		seek_cd = 1.0
		backing.seek(song_t)
	elif net.mode != "client" and absf(diff) < 0.12:
		song_t += diff * 0.05  # host / local: the clock leans on what you actually hear


func _start_song(i: int) -> void:
	song_serial += 1
	_load_song(i, song_bars)
	state = "intro"
	state_t = 0.0
	song_t = -START_LEAD
	crowd = 0.5
	combo = 0
	best_combo = 0
	band_hits = 0
	band_misses = 0
	players[0].reset_stats()
	stage.hide_stars()
	net.event("stars", [-1])
	var head := "SONG %d of %d: %s  (%d BPM)" % [i + 1, SONGS_PER_TOUR, song.title, int(song.bpm)]
	if i == 0 and tour_stars == 0:
		_show_center("RHYTHM BAND!\nPlay the song together and keep the crowd happy!\n" \
			+ "TV: press X / A / B (or D-pad left / down / right) when a ball reaches its ring\n" \
			+ "VR DRUMMER: swing a hand into each drum as its ball arrives\n" \
			+ "More players: press A on another controller\n\n" + head, FIRST_INTRO_TIME)
	else:
		_show_center(head + "\n" + ["Nice and easy!", "A bit faster…", "FULL SPEED - rock out!"][mini(i, 2)], INTRO_TIME)
	sound("go", -6.0, 0.8, true)
	print("Song %d started: %s, %d BPM, %d bars, %d guitar notes, %d drum notes" % [i + 1, song.title,
		int(song.bpm), song.total_bars, song.g_t.size(), song.d_t.size()])


## Beat-synced effects on every machine (lights, count-in sticks and numbers).
func _beat_fx() -> void:
	if song == null or state != "play":
		return
	var b := int(floorf(song_t / song.spb))
	if b == last_beat:
		return
	last_beat = b
	if b < 0:
		return
	stage.on_beat(b, crowd)
	var count_beats: int = SongScript.COUNT_IN * 4
	if b < count_beats:
		inst.click(b % 4 == 0)
		if b == 0:
			_show_center("Get ready…", 0.0, false)
		elif b >= count_beats - 3:
			_show_center(str(count_beats - b), 0.4, false)
	elif b == count_beats:
		_show_center("PLAY!", 0.5, false)


func multiplier() -> int:
	return 1 + mini(3, combo / 15)


## Authority: one judged note (guitar or drum). q: 0 perfect, 1 good, 2 miss.
func _band_result(q: int) -> void:
	var n := 1 + active_guitarists().size()
	if q < 2:
		band_hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		score += (100 if q == 0 else 60) * multiplier()
		crowd = minf(1.0, crowd + 0.035 / sqrt(float(n)) * (1.0 if q == 0 else 0.75))
		if combo > 0 and combo % 25 == 0:
			_show_center("%d COMBO!" % combo, 1.0)
			inst.cheer(-2.0)
			net.event("cheer", [-2.0])
			burst(Vector3(0.0, 3.0, -1.5), PLAYER_COLORS[(combo / 25) % PLAYER_COLORS.size()], 40)
	else:
		band_misses += 1
		combo = combo / 2  # kind: a miss halves the combo instead of wiping it
		crowd = maxf(0.0, crowd - 0.03 / sqrt(float(n)))


## Any machine: one of its own guitarists judged a note.
func guitar_result(p, id: int, q: int) -> void:
	if q < 2:
		if id != last_pluck:
			last_pluck = id
			inst.pluck(song.g_pitch[id], -3.0 if q == 0 else -5.0)
		stage.strum(p.index, true)
	else:
		inst.miss()
	if net.mode == "client":
		net.send_action("hit" if q < 2 else "miss", [id, q], p.index)
	else:
		_band_result(q)


## Pressing a lane with no note near: a soft chord tone, no penalty (and the avatar strums).
func free_strum(p, lane: int) -> void:
	if song != null:
		inst.pluck(song.lane_pitch_at(maxf(0.0, song_t), lane), -12.0)
	stage.strum(p.index, false)
	if net.mode == "client":
		net.send_action("press", [lane], p.index)


## Authority (host / local): the drummer hit a drum.
func drum_hit(pad: int, speed: float) -> void:
	var vol := lerpf(-8.0, 0.0, clampf((speed - 0.4) / 2.0, 0.0, 1.0))
	inst.drum(pad, vol)
	players[0].flash_pad(pad)
	var id := -1
	var q := -1
	if state == "play" and song != null:
		var bdt := 99.0
		var i := maxi(0, d_next - 4)
		var n: int = song.d_t.size()
		while i < n:
			var t: float = song.d_t[i]
			if t > song_t + GOOD:
				break
			if d_judged[i] == 0 and int(song.d_pad[i]) == pad:
				var dt := absf(t - song_t)
				if dt <= GOOD and dt < bdt:
					bdt = dt
					id = i
			i += 1
		if id >= 0:
			q = 0 if bdt <= PERFECT else 1
			_drum_result(id, q)
	net.event("drum", [pad, id, q, vol])


func _drum_result(id: int, q: int) -> void:
	d_judged[id] = q + 1
	var d = players[0]
	d.record(q)
	_band_result(q)
	var pad: int = song.d_pad[id]
	var pos: Vector3 = d.pads[pad].global_position + Vector3(0.0, 0.12, 0.0)
	if q == 0:
		popup(pos, "PERFECT!", Color(1.0, 0.9, 0.3), 0.8)
	elif q == 1:
		popup(pos, "GOOD", Color(0.5, 1.0, 0.6), 0.7)
	else:
		popup(pos, "MISS", Color(1.0, 0.45, 0.45), 0.6)


func _song_done() -> void:
	state = "results"
	state_t = 0.0
	var acc := float(band_hits) / maxf(1.0, float(band_hits + band_misses))
	last_stars = clampi(1 + int(acc * 4.0 + 0.15), 1, 5)
	tour_stars += last_stars
	var lines := "Drums %d%%" % int(100.0 * players[0].hits / maxf(1.0, float(players[0].hits + players[0].misses)))
	for p in active_guitarists():
		var tot: int = p.hits + p.misses
		lines += "   P%d %d%%" % [p.index + 1, int(100.0 * p.hits / maxf(1.0, float(tot)))]
	var last := song_idx + 1 >= SONGS_PER_TOUR
	var praise: String = ["Good try!", "Nice!", "Great job!", "Awesome!", "SUPERSTARS!"][last_stars - 1]
	_show_center("SONG COMPLETE: %s\n%d STARS - %s\nHits %d%%  ·  Best combo %d  ·  Score %d\n%s\n\n%s" % [song.title, last_stars,
		praise, int(acc * 100.0), best_combo, score, lines,
		"A / Enter (VR: trigger): the tour results" if last else "A / Enter (VR: trigger): next song"], 0.0)
	stage.show_stars(last_stars)
	net.event("stars", [last_stars])
	inst.cheer(0.0)
	net.event("cheer", [0.0])
	burst(Vector3(-2.0, 2.5, -1.5), Color(1.0, 0.85, 0.2), 40)
	burst(Vector3(2.0, 2.5, -1.5), Color(0.4, 0.8, 1.0), 40)
	if score > best:
		best = score
		_save_best(best)
	print("Song %d complete: %d stars (hits %d, misses %d, best combo %d, score %d) %s" % [song_idx + 1, last_stars,
		band_hits, band_misses, best_combo, score, lines])


func _tour_done() -> void:
	state = "tour"
	state_t = 0.0
	stage.hide_stars()
	net.event("stars", [-1])
	_show_center("TOUR COMPLETE!\n%d of %d stars  ·  Score %d  ·  Best %d\nWhat a band!\n\nA / Enter (VR: trigger) to play again" % [
		tour_stars, SONGS_PER_TOUR * 5, score, best], 0.0)
	sound("tour", -2.0, 1.0, true)
	inst.cheer(0.0)
	net.event("cheer", [0.0])
	for k in 3:
		burst(Vector3(-3.0 + k * 3.0, 2.0, -1.5), PLAYER_COLORS[k + 1], 40)
	print("Tour complete: %d stars, score %d" % [tour_stars, score])


func _restart_tour() -> void:
	score = 0
	tour_stars = 0
	_start_song(0)


# --- Game loop -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_ensure_join_listener()
	_poll_synth()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	for p in players:
		if p.index > 0 and p.camera != null:
			p.camera.global_transform = stage.tv_camera(p.index)
	var cont := _continue_pressed()
	var cont_edge := cont and not cont_was
	cont_was = cont
	state_t += delta
	if state == "play":
		song_t += delta
	_sync_audio(delta)
	_beat_fx()
	var beat_pos: float = song_t / float(song.spb) if song != null and state == "play" else state_t * 1.6
	stage.update(delta, beat_pos, crowd, state == "play")
	_update_vr_text()
	if net.mode == "client":
		_client_update(delta, cont_edge)
		return
	_update_lost_pads(delta)
	match state:
		"wait":
			var vs: bool = players[0].vr and players[0].vr_trigger()
			if vs and not vr_start_was:
				_start_song(0)
			vr_start_was = vs
		"intro":
			var dur := FIRST_INTRO_TIME if song_idx == 0 and tour_stars == 0 else INTRO_TIME
			if state_t >= dur:
				state = "play"
				state_t = 0.0
				song_t = -START_LEAD
				net.event("play", [song_serial])
		"play":
			_check_drum_misses()
			cheer_cd -= delta
			if crowd > 0.8 and cheer_cd <= 0.0:
				cheer_cd = 8.0
				inst.cheer(-10.0)
				net.event("cheer", [-10.0])
			if song_t > song.length + 0.4:
				_song_done()
		"results":
			if backing.playing and song_t >= song.length - 0.05:
				backing.stop()
			if (state_t > 1.5 and cont_edge) or state_t > RESULTS_AUTO:
				_on_continue(true)
		"tour":
			if state_t > 1.5 and cont_edge:
				_restart_tour()


func _check_drum_misses() -> void:
	var n: int = song.d_t.size()
	while d_next < n and float(song.d_t[d_next]) < song_t - GOOD - 0.02:
		if d_judged[d_next] == 0:
			_drum_result(d_next, 2)
			net.event("drum", [-1, d_next, 2, 0.0])
		d_next += 1


func _client_update(delta: float, cont_edge: bool) -> void:
	_check_join(delta)
	_update_lost_pads(delta)
	if cont_edge and ((state == "results" or state == "tour") and state_t > 1.5):
		net.send_action("continue", [])


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


## A / Enter on this machine (VR: the trigger or A) moves on from the results screens.
func _continue_pressed() -> bool:
	if state != "results" and state != "tour":
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
		_on_continue(false)


func _on_continue(_auto: bool) -> void:
	if state == "results" and state_t > 1.0:
		if song_idx + 1 >= SONGS_PER_TOUR:
			_tour_done()
		else:
			_start_song(song_idx + 1)
	elif state == "tour" and state_t > 1.0:
		_restart_tour()


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://rhythm_band_best.cfg")
	return int(cfg.get_value("best", "score", 0))


func _save_best(s: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "score", s)
	cfg.save("user://rhythm_band_best.cfg")


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ------------------------------------

func on_client_joined() -> void:
	_show_center("THE TV BAND JOINED!", 1.5)
	if not players[1].active:
		_activate(players[1])  # the TV machine's first guitarist; more join with A over there
	if state == "wait":
		_start_song(0)


func on_client_left() -> void:
	for i in range(1, players.size()):
		if players[i].active:
			players[i].set_active(false)
			stage.set_avatar_visible(i, false)
	_show_center("The TV players left - keep drumming!", 2.0)


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
				print("Net: player %d joined the band" % (index + 1))
		"leave":
			if p.active:
				p.set_active(false)
				on_player_activity_changed(p)
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
		"continue":
			_on_continue(false)
		"hit", "miss":
			if args.size() < 2 or song == null or state != "play":
				return
			var id: int = int(args[0])
			var q: int = clampi(int(args[1]), 0, 2)
			if id < 0 or id >= song.g_t.size():
				return
			p.record(q)
			if q < 2:
				if id != last_pluck:
					last_pluck = id
					inst.pluck(song.g_pitch[id], -4.0)
				stage.strum(index, true)
			_band_result(q)
		"press":
			stage.strum(index, false)
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
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHold the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps: Array = []
	for i in range(1, players.size()):
		var p = players[i]
		ps.append([p.active, p.streak, p.hits, p.misses])
	var d = players[0]
	return [state, song_serial, song_idx, song_bars, song_t, crowd, combo, score, best, state_t, ps,
		d.rig_transform(), d.kit_s, d.head_transform(), d.tip(0), d.tip(1), last_stars, tour_stars]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 18:
		return
	var serial: int = s[1]
	var host_t: float = s[4]
	var new_state: String = s[0]
	if serial != song_serial or song == null:
		song_serial = serial
		song_t = host_t
		state = new_state
		_load_song(int(s[2]), int(s[3]))
	if not synced:
		synced = true
		_show_center("", 0.0, false)
	if new_state != state:
		state = new_state
		state_t = float(s[9])
		if state == "play":
			song_t = host_t
			last_beat = -999
	if state == "play":
		var diff := host_t + 0.02 - song_t
		if absf(diff) > 0.25:
			song_t = host_t
		else:
			song_t += diff * 0.1
	crowd = s[5]
	combo = s[6]
	score = s[7]
	best = s[8]
	var ps: Array = s[10]
	for i in ps.size():
		var idx := i + 1
		if idx >= players.size():
			break
		var st: Array = ps[i]
		var p = players[idx]
		var act: bool = st[0]
		if act != p.active:
			p.set_active(act)
			if act:
				p.reset_for_song()
			on_player_activity_changed(p)
	var d = players[0]
	d.net_rig = s[11]
	d.net_s = s[12]
	d.net_head = s[13]
	d.net_tips[0] = s[14]
	d.net_tips[1] = s[15]
	last_stars = s[16]
	tour_stars = s[17]


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
		"cheer":
			inst.cheer(float(args[0]))
		"stars":
			var n: int = args[0]
			if n < 0:
				stage.hide_stars()
			else:
				last_stars = n
				stage.show_stars(n)
		"play":
			if int(args[0]) == song_serial:
				state = "play"
				state_t = 0.0
				song_t = -START_LEAD
				last_beat = -999
		"drum":
			var pad: int = args[0]
			var id: int = args[1]
			var q: int = args[2]
			if pad >= 0:
				inst.drum(pad, float(args[3]))
				players[0].flash_pad(pad)
			if id >= 0 and id < d_judged.size():
				d_judged[id] = q + 1
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR drummer paused the game")


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
	center_label = _make_label(44)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(18)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -30
	help_label.offset_bottom = -6
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Guitar: X / A / B or D-pad (keyboard: arrows) · more players: press A on another controller · Start / Esc: menu"


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
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.4)


## The few words on the VR drummer's kit: crowd, combo and a hint when they need one.
func drummer_status(d) -> String:
	var line := "CROWD %d%%   COMBO %d" % [int(crowd * 100.0), combo]
	if multiplier() > 1:
		line += "  x%d" % multiplier()
	if state == "wait":
		return "Hit the drums with your hands!\nTrigger: start the first song"
	if state == "play" and song != null:
		var first: float = song.d_t[0] if song.d_t.size() > 0 else 0.0
		if song_t < first + 1.0:
			return line + "\nSwing a hand into each drum as its ball lands"
		if d.miss_run >= 4:
			return line + "\nWatch the balls - hit the drum they fly into!"
		if d.swings == 0 and song_t > first + 3.0:
			return line + "\nSwing your hands down onto the drums!"
		return line + ("\n%d IN A ROW!" % d.streak if d.streak >= 8 else "")
	if state == "results" or state == "tour":
		return line + "\nTrigger: carry on"
	return line + "\nA: bring the drums in front of you"


func _update_vr_text() -> void:
	if help_label.modulate.a > 0.0 and song_idx >= 1:
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
	VrText.follow(vr_center, cam, self, 0.35, 1.8)  # above the drums, so it never sits on the kit
