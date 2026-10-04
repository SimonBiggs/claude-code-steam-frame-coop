extends Node3D
## PAINT AND GUESS - a cosy drawing-and-guessing party game in an art studio.
## The VR player (players[0]) is the ARTIST: they see a secret word and paint it in glowing strokes on
## a big easel (hold the right trigger; touch the board or point at it; RAINBOW and SPARKLE paint,
## UNDO, CLEAR). The TV players (1-6) watch the easel live in their own split-screen views and each pick
## from their OWN four answers (one right, three decoys). First right answer scores most (+FIRST bonus),
## guessing several rounds in a row builds a STREAK, a wrong pick locks you out for a moment, hint
## letters appear over time, and X / Y / B cheer the artist on (critters on the easel jump about).
## A game is 5 rounds, each with its own THEME (animals, food, ...):
##   1-2 PAINT · 3 TEAM PAINT (roles swap: the TV players paint the word together with their stick
##   brushes and the VR player guesses by touching one of four balloons) · 4 SPEED ROUND (35 s, x2)
##   · 5 GOLDEN FINAL (x2).
## Every finished picture flies onto the gallery wall; at the end everyone VOTES for the best one (gold
## frame, MASTERPIECE), then the final scores and fun awards.
##
## Files: canvas.gd (easel, strokes, pots, bubbles, critters, balloons, vote grid), room.gd (the studio,
## gallery, cat, lights), artist.gd (players[0]), guesser.gd (players 1-6), words.gd (themed packs),
## mesh_kit.gd (merged one-draw-call meshes), join_listener.gd. Modes and networking follow
## docs/GAME_DEV_GUIDE.md: the host simulates; strokes travel as small incremental events ("sb" begin,
## "pts" batches, "se" end, "undo", "clr"), never in snapshots. TEAM PAINT brushes travel as player
## state (send_state) to the host, which turns them into strokes like the artist's.

const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const CanvasScript := preload("res://games/paint_and_guess/canvas.gd")
const RoomScript := preload("res://games/paint_and_guess/room.gd")
const ArtistScript := preload("res://games/paint_and_guess/artist.gd")
const GuesserScript := preload("res://games/paint_and_guess/guesser.gd")
const WordsScript := preload("res://games/paint_and_guess/words.gd")
const JoinListenerScript := preload("res://games/paint_and_guess/join_listener.gd")

const MAX_PLAYERS := 7  # artist + 6 guessers
const MAX_LOCAL_VIEWS := 6
const PAD_LEAVE_TIME := 20.0
const ROUND_PLAN: Array[String] = ["paint", "paint", "team", "speed", "final"]
const ROUNDS := 5
const FIRST_INTRO_TIME := 8.0
const INTRO_TIME := 4.0
const TEAM_INTRO_TIME := 7.0
const REVEAL_TIME := 5.5
const VOTE_TIME := 20.0
const LOCKOUT := 3.0
const VR_LOCKOUT := 2.0
const HINT_EVERY := 15.0
const SKIP_WINDOW := 15.0
const FLUSH_INTERVAL := 0.05
const TEAM_BRUSH_W := 0.024
const HINT_LAYER := 4  # visual layer bit for things only the guessers see (the hint over the easel)
const VR_LAYER := 8  # visual layer bit for the VR player's floating text (never on the TV)
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.35, 0.35), Color(0.3, 0.65, 1.0),
	Color(0.4, 0.9, 0.4), Color(1.0, 0.8, 0.15), Color(0.8, 0.45, 1.0), Color(1.0, 0.55, 0.2)]
const SOUNDS := {
	"pick": [0.04, 900.0, 900.0, 0.12, "square", 0.0],
	"right": [0.5, 523.0, 1568.0, 0.35, "tri", 0.0],
	"wrong": [0.32, 200.0, 110.0, 0.32, "square", 0.25],
	"nope": [0.08, 300.0, 250.0, 0.2, "square", 0.1],
	"swish": [0.35, 2400.0, 500.0, 0.16, "sine", 0.9],
	"color": [0.12, 700.0, 1150.0, 0.22, "sine", 0.0],
	"sparkle": [0.22, 1800.0, 2900.0, 0.16, "sine", 0.15],
	"tick": [0.05, 1300.0, 1300.0, 0.14, "square", 0.0],
	"reveal": [0.7, 392.0, 784.0, 0.35, "tri", 0.0],
	"fanfare": [1.2, 523.0, 1046.0, 0.4, "square", 0.0],
	"go": [0.4, 440.0, 880.0, 0.35, "square", 0.0],
	"hint": [0.3, 1200.0, 1700.0, 0.2, "sine", 0.0],
	"join": [0.45, 330.0, 1320.0, 0.3, "sine", 0.0],
	"newword": [0.4, 880.0, 440.0, 0.25, "tri", 0.0],
	"cheer": [0.22, 700.0, 1500.0, 0.2, "sine", 0.05],
	"pop": [0.14, 900.0, 180.0, 0.35, "square", 0.6],
	"streak": [0.45, 660.0, 1320.0, 0.28, "square", 0.0],
	"first": [0.3, 990.0, 1980.0, 0.26, "tri", 0.0],
	"whoosh": [0.7, 260.0, 1300.0, 0.16, "sine", 0.7],
	"vote": [0.15, 800.0, 1250.0, 0.24, "tri", 0.0],
	"masterpiece": [1.5, 392.0, 1568.0, 0.4, "tri", 0.0],
	"undo": [0.18, 760.0, 360.0, 0.2, "tri", 0.0],
	"team": [0.9, 262.0, 784.0, 0.32, "saw", 0.1],
	"speed": [0.6, 500.0, 1500.0, 0.3, "square", 0.0],
}

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var canvas: Node3D
var room: Node3D
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var join_listener: Node
var joy_owner := {}  # joypad device id -> player index
var views_root: Control
var last_view_area := Vector2.ZERO
var mats := {}
var meshes := {}

var state := "wait"  # wait, intro, draw, reveal, vote, over
var state_t := 0.0
var round_n := 0
var round_id := 0
var round_type := "paint"  # paint, team, speed, final
var theme := ""
var theme_order: Array[int] = []
var time_left := 60.0
var word := ""  # host only (the client learns it at the reveal, or at the start of a TEAM PAINT round)
var team_word := ""  # TEAM PAINT: the word the TV players paint (sent to the TV machine)
var reveal_word := ""
var opts: Array = []  # opts[i] = the four answers player i sees (opts[0]: the VR player's balloons)
var opts_round := -1
var hint_text := ""
var hint_order: Array[int] = []
var hints_shown := 0
var correct_count := 0
var skips_left := 2
var used_words: Array[String] = []
var end_t := -1.0
var last_tick := -1
var cont_was := false
var next_stroke_id := 1
var pending := {}  # stroke id -> PackedVector2Array not sent yet
var sent_points := 0
var flush_t := 0.0
var synced := false
var ask_t := 0.0
var sync_bad_t := 0.0
var net_sent_points := 0
var net_rev := 0
var vr_lock := 0.0  # TEAM PAINT: the VR player's wrong-balloon lockout
var vr_wrong_mask := 0
var applause := 0  # cheers turned into artist points this round
var hung_count := 0
var vote_slots: Array[int] = []
var vote_words: Array[String] = []
var votes := {}  # voter index -> vote_slots index (host)
var artist_vote_k := -1
var vote_done_t := -1.0
var everyone_rounds := 0
var masterpiece := ""
var winner_idx := -1

var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_status: Label3D
var vr_msg := ""
var vr_msg_t := 0.0


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
		_show_center("Connecting to the VR artist…", 0.0, false)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	opts = []
	for i in MAX_PLAYERS:
		opts.append([])
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		state = "wait"
		_show_center("PAINT AND GUESS\nWaiting for the TV players to join…", 0.0)
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED!", 1.5, false)
	else:
		_start_game()


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave another game's scale behind


func is_host_side() -> bool:
	return net == null or net.mode != "client"


# --- Helpers -------------------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mats[key] = m
	return m


## Unshaded: paint, pots and the canvas glow evenly whatever the lighting.
func flat_material(color: Color) -> StandardMaterial3D:
	var key := "flat/%s" % color.to_html()
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	var key := "b%s" % size
	if meshes.has(key):
		return meshes[key]
	var m := BoxMesh.new()
	m.size = size
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


## Multi-coloured confetti bursting out of a point (in front of the easel).
func confetti(pos: Vector3, amount: int = 40, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.6
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 60.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -2.2, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.mesh = box_mesh(Vector3(0.025, 0.012, 0.002))
	p.material_override = _confetti_material()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 0.3, 0.3), Color(1, 0.8, 0.2), Color(0.3, 1, 0.4), Color(0.3, 0.7, 1),
		Color(0.8, 0.4, 1), Color(1, 0.5, 0.8)])
	p.color_initial_ramp = g
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(2.2).timeout.connect(p.queue_free)
	if broadcast and net != null:
		net.event("confetti", [pos, amount])


func _confetti_material() -> StandardMaterial3D:
	if mats.has("confetti"):
		return mats["confetti"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["confetti"] = m
	return m


## A small one-colour puff (balloon pops, cheers).
func puff(pos: Vector3, col: Color, amount: int = 16) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0.3)
	p.spread = 180.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, -1.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = sphere_mesh(0.008)
	p.material_override = flat_material(col)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true, rise: float = 0.12) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.0016
	l.outline_size = 18
	l.modulate = color
	l.render_priority = 5
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # faces the room (the artist and the TV cameras)
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "global_position", pos + Vector3(0, rise, 0), 1.6)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.0).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)
	if broadcast and net != null:
		net.event("popup", [pos, text, color])


# --- World ---------------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.16, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.9, 0.8)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(25.0), 0.0)
	sun.light_energy = 0.8
	sun.light_color = Color(1.0, 0.92, 0.8)
	add_child(sun)
	room = RoomScript.new()
	room.name = "Studio"
	room.main = self
	add_child(room)
	room.build()
	canvas = CanvasScript.new()
	canvas.name = "Easel"
	canvas.main = self
	add_child(canvas)
	canvas.ensure_audience(MAX_PLAYERS - 1, PLAYER_COLORS)


# --- Players and views -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	var a := ArtistScript.new()
	a.main = self
	a.ghost = mode == "client"
	a.key_set = 0
	add_child(a)
	players.append(a)
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		var g := GuesserScript.new()
		g.index = i
		g.main = self
		g.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		g.remote = mode == "host"
		if i == 1:
			g.key_set = 1 if mode == "client" else 0
		add_child(g)
		players.append(g)
		g.set_active(i == 1)


func is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost and not (p.index == 0 and p.fake_vr)


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
		print("VR headset found: player 1 is the artist in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = Vector3(0, 0, ArtistScript.STAND_Z)
		var cam := XRCamera3D.new()
		cam.cull_mask = 0xFFFFF & ~HINT_LAYER
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
	elif mode != "client" and OS.has_environment("BOT_VR"):
		print("Fake VR: the bot drives the artist's VR hand")
		players[0].attach_fake_vr()
	else:
		print("No VR headset: %s" % ("TV guessers" if mode == "client" else "split screen, player 1 paints with mouse / controller"))
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
	cam.cull_mask = 0xFFFFF & ~HINT_LAYER
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
	bg.color = Color(0.12, 0.1, 0.16)
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
	cam.far = 30.0
	cam.fov = 50.0
	# The secret word is only for the artist; the hint letters only for the guessers.
	cam.cull_mask = 0xFFFFF & ~(HINT_LAYER if p.index == 0 else CanvasScript.SECRET_LAYER) & ~VR_LAYER
	vp.add_child(cam)
	cam.current = true
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if p.index == 0:
		p.attach_camera(cam)
		p.hud = hud
		var l := _make_label(30)
		hud.add_child(l)
		l.position = Vector2(16, 10)
		p.hud_label = l
	else:
		p.camera = cam
		p.build_hud(hud)


## Point a view's camera square-on at the easel. Guessers keep the bottom third for their answers.
func _frame_camera(cam: Camera3D, aspect: float, guesser: bool) -> void:
	var hn: float = canvas.H + 0.55
	var wn: float = canvas.W + 0.5
	var center: Vector3 = canvas.canvas_to_world(Vector2(0.0, 0.08), 0.0)
	var hh := 0.0
	var cam_y := center.y
	if guesser:
		hh = maxf(hn / 1.3, wn * 0.53 / maxf(aspect, 0.1))
		cam_y = center.y - 0.35 * hh
	else:
		hh = maxf(hn * 0.53, wn * 0.53 / maxf(aspect, 0.1))
	var d := hh / tan(deg_to_rad(cam.fov * 0.5))
	var n: Vector3 = canvas.normal()
	var pos := center + n * d
	pos.y = cam_y
	cam.global_transform = Transform3D(canvas.board_root.global_basis, pos)


func _frame_views() -> void:
	for p in players:
		if not p.has_meta("view") or p.camera == null:
			continue
		var c: SubViewportContainer = p.get_meta("view")
		if not c.visible:
			continue
		var sz := c.size
		_frame_camera(p.camera, sz.x / maxf(sz.y, 1.0), p.index > 0)


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
		var ui := clampf(minf(cell.x / 940.0, cell.y / 760.0), 0.5, 1.0)
		if p.index > 0:
			p.ui_scale = ui
		elif p.hud_label != null:
			p.hud_label.add_theme_font_size_override("font_size", int(30.0 * ui))


# --- Controllers and drop-in join ----------------------------------------------------

func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	joy_owner.clear()
	if net.mode == "host":
		if not players[0].vr and pads.size() > 0:
			players[0].joy = pads[0]
		return
	players[1].joy = pads[0] if pads.size() > 0 else -1
	if net.mode == "local" and not players[0].fake_vr:
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


## Called by the join listener for every input event: A on a controller nobody owns joins a guesser.
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
		_show_center("All %d guesser seats are taken!" % (players.size() - 1), 1.5, false)
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
	p.reset_round()
	p.reset_stats()
	p.score = 0
	_show_center("PLAYER %d JOINS THE GUESSING!" % (p.index + 1), 1.5)
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
	Engine.set_meta("paint_and_guess_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("paint_and_guess_party"):
		return
	var saved: Dictionary = Engine.get_meta("paint_and_guess_party")
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


## Test hook: join a guesser without a controller (index -1: the next free seat).
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


func active_guessers() -> Array:
	var out: Array = []
	for i in range(1, players.size()):
		if players[i].active:
			out.append(players[i])
	return out


# --- Strokes (the artist and the TEAM PAINT brushes call these; host / local only) -------------

func can_draw() -> bool:
	return is_host_side() and ((state == "draw" and round_type != "team") or state == "wait")


func can_team_paint() -> bool:
	return is_host_side() and state == "draw" and round_type == "team"


## What the artist's hand does right now: "paint", "guess" (TEAM PAINT balloons), "vote" or "idle".
func artist_mode() -> String:
	if state == "wait" or (state == "draw" and round_type != "team"):
		return "paint"
	if state == "draw":
		return "guess"
	if state == "vote" and vote_done_t < 0.0:
		return "vote"
	return "idle"


## What a TV player's buttons do right now: "guess", "paint" (TEAM PAINT) or "vote".
func guesser_mode() -> String:
	if state == "draw" and round_type == "team":
		return "paint"
	if state == "vote":
		return "vote"
	return "guess"


func stroke_begin(col: int, w: float, p: Vector2, owner: int = 0) -> int:
	var id := next_stroke_id
	next_stroke_id += 1
	_flush_points()
	canvas.begin_stroke(id, col, w, p, owner)
	sent_points += 1
	net.event("sb", [id, col, w, p, owner])
	return id


func stroke_add(id: int, p: Vector2) -> void:
	var one := PackedVector2Array()
	one.append(p)
	canvas.add_points(id, one)
	var arr: PackedVector2Array = pending.get(id, PackedVector2Array())
	arr.append(p)
	pending[id] = arr


## A painter lifted the brush: bake their stroke (both machines).
func stroke_end(owner: int) -> void:
	if not canvas.lives.has(owner):
		return
	_flush_points()
	canvas.end_stroke(owner)
	net.event("se", [owner])


func stroke_len(id: int) -> int:
	return canvas.stroke_len(id)


func _flush_points() -> void:
	for id in pending.keys():
		var arr: PackedVector2Array = pending[id]
		if arr.size() > 0 and canvas.by_id.has(id):
			sent_points += arr.size()
			net.event("pts", [int(id), arr])
	pending.clear()


func _clear_canvas(fx: bool) -> void:
	pending.clear()
	canvas.clear_all()
	canvas.rev += 1
	sent_points = 0
	players[0].cur_id = -1
	for i in range(1, players.size()):
		players[i].tv_cur_id = -1
	net.event("clr", [canvas.rev])
	if fx:
		sound("swish", -2.0, 1.0, true)


func artist_clear() -> void:
	if not is_host_side() or artist_mode() != "paint":
		return
	if canvas.point_count == 0:
		return
	_clear_canvas(true)
	print("Artist cleared the canvas")


func artist_undo() -> void:
	if not is_host_side() or artist_mode() != "paint":
		return
	_flush_points()
	var id: int = canvas.last_stroke_id(0)
	if id < 0:
		sound("nope", -8.0)
		return
	if players[0].cur_id == id:
		players[0].cur_id = -1
	var n: int = canvas.remove_stroke(id)
	sent_points -= n
	net.event("undo", [id])
	sound("undo", -4.0, 1.0, true)
	print("Artist undid a stroke (%d points)" % n)


func artist_skip() -> void:
	if not is_host_side() or state != "draw" or round_type == "team":
		return
	if skips_left <= 0 or state_t > SKIP_WINDOW:
		_show_center("No new words now - keep drawing!", 1.5, false, "No new words now - keep drawing!")
		sound("nope", -6.0)
		return
	skips_left -= 1
	_clear_canvas(false)
	_pick_word()
	time_left = round_time()
	state_t = 0.0
	_send_round()
	sound("newword", 0.0, 1.0, true)
	_show_center("NEW WORD!", 1.2)
	print("Artist asked for a new word: %s" % word)


## Host: a TV painter's brush turns into strokes (TEAM PAINT), like the artist's.
func _tv_paint(g) -> void:
	var owner: int = g.index
	if not (g.active and g.tv_down and can_team_paint()):
		if g.tv_cur_id >= 0:
			stroke_end(owner)
		g.tv_cur_id = -1
		return
	var col: int = CanvasScript.TEAM_BASE + g.index
	var p: Vector2 = canvas.clamp_point(g.tv_cursor)
	if g.tv_cur_id < 0 or p.distance_to(g.tv_last) > 0.3:
		if canvas.is_full():
			return
		g.tv_cur_id = stroke_begin(col, TEAM_BRUSH_W, p, owner)
		g.tv_last = p
		g.tv_smooth = p
		g.team_ink += 1
		return
	g.tv_smooth = g.tv_smooth.lerp(p, 0.6)
	if g.tv_smooth.distance_to(g.tv_last) < 0.006:
		return
	if canvas.stroke_len(g.tv_cur_id) >= ArtistScript.SEG_POINTS:
		g.tv_cur_id = stroke_begin(col, TEAM_BRUSH_W, g.tv_last, owner)
	stroke_add(g.tv_cur_id, g.tv_smooth)
	g.tv_last = g.tv_smooth
	g.team_ink += 1


# --- Game flow -----------------------------------------------------------------------

func round_time() -> float:
	match round_type:
		"team":
			return 50.0
		"speed":
			return 35.0
	return 60.0


func round_mult() -> int:
	return 2 if round_type == "speed" or round_type == "final" else 1


func time_frac() -> float:
	if state == "vote":
		return time_left / VOTE_TIME
	return time_left / maxf(1.0, round_time())


func round_title() -> String:
	match round_type:
		"team":
			return "TEAM PAINT"
		"speed":
			return "SPEED ROUND  x2"
		"final":
			return "GOLDEN FINAL  x2"
	return "ROUND %d" % round_n


## One line under the TV players' top bar: theme and round type.
func banner_text() -> String:
	if round_n <= 0 or state == "wait":
		return ""
	if state == "vote":
		return "THE GALLERY VOTE"
	if state == "over":
		return "THE END!"
	return "THEME: %s   ·   %s" % [theme, round_title()]


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -19.0
	music.play_track(_music_track())
	_ensure_join_listener()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	_frame_views()
	_update_easel_text()
	_update_vr_text(delta)
	var a = players[0]
	if is_host_side():
		canvas.set_cursor(a.cursor, a.cursor_on and state != "over", canvas.ui_color(a.color_idx) if artist_mode() == "paint" else Color(1, 1, 1), a.drawing())
	var cont := _continue_pressed()
	var cont_edge := cont and not cont_was
	cont_was = cont
	if net.mode == "client":
		_client_update(delta, cont_edge)
		return
	_update_lost_pads(delta)
	for i in range(1, players.size()):
		_tv_paint(players[i])
	flush_t -= delta
	if flush_t <= 0.0:
		flush_t = FLUSH_INTERVAL
		_flush_points()
	state_t += delta
	vr_lock = maxf(0.0, vr_lock - delta)
	for g in active_guessers():
		g.lock_left = maxf(0.0, g.lock_left - delta)
	match state:
		"intro":
			var dur := FIRST_INTRO_TIME if round_n == 1 else (TEAM_INTRO_TIME if round_type == "team" else INTRO_TIME)
			if state_t >= dur:
				state = "draw"
				state_t = 0.0
				players[0].trig_block = players[0].trig_block or round_type == "team"
				_show_center("GO!" if round_type != "team" else "TEAM - PAINT!", 0.8, true, "GO!" if round_type != "team" else "GUESS - touch a balloon!")
				sound("go", 0.0, 1.0, true)
				print("Round %d (%s, %s): draw! (%d guessers)" % [round_n, round_type, theme, active_guessers().size()])
		"draw":
			time_left -= delta
			var secs := int(ceilf(time_left))
			if secs <= 10 and secs != last_tick and secs > 0:
				last_tick = secs
				sound("tick", -4.0, 1.0 + (10 - secs) * 0.05, true)
			if round_type != "team":
				var want_hints := mini(int((round_time() - time_left) / HINT_EVERY), _max_hints())
				if round_type == "speed":
					want_hints = mini(int((round_time() - time_left) / 9.0), _max_hints())
				if want_hints > hints_shown:
					hints_shown = want_hints
					_update_hint()
					sound("hint", -6.0, 1.0, true)
			if end_t >= 0.0:
				end_t -= delta
				if end_t < 0.0:
					_reveal(true)
			elif time_left <= 0.0:
				time_left = 0.0
				_reveal(false)
		"reveal":
			if state_t > REVEAL_TIME or (state_t > 2.0 and cont_edge):
				_next_round()
		"vote":
			if vote_done_t >= 0.0:
				vote_done_t -= delta
				if vote_done_t < 0.0:
					_game_over()
			else:
				time_left = maxf(0.0, time_left - delta)
				if time_left <= 0.0 or (_all_voted() and state_t > 2.0):
					_finish_vote()
		"over":
			if state_t > 1.5 and cont_edge:
				_start_game()


func _music_track() -> int:
	match state:
		"vote", "over":
			return 2
	match round_type:
		"speed", "final":
			return 1
		"team":
			return 0
	return 0 if round_n <= 1 else 2


func _client_update(delta: float, cont_edge: bool) -> void:
	_check_join(delta)
	_update_lost_pads(delta)
	state_t += delta
	if state == "draw" or (state == "vote" and vote_done_t < 0.0):
		time_left = maxf(0.0, time_left - delta)
	if cont_edge and ((state == "reveal" and state_t > 2.0) or (state == "over" and state_t > 1.5)):
		net.send_action("continue", [])


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


## A / Enter on this machine (VR: the trigger or A) moves on from the reveal / game-over screens.
func _continue_pressed() -> bool:
	if state != "reveal" and state != "over":
		return false
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for p in players:
		if (is_local(p) or (p.index == 0 and p.fake_vr)) and p.active and p.action_pressed():
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
	if state == "reveal" and state_t > 1.0:
		_next_round()
	elif state == "over" and state_t > 1.0:
		_start_game()


func _start_game() -> void:
	round_n = 0
	players[0].score = 0
	players[0].colors_used.clear()
	for i in range(1, players.size()):
		players[i].score = 0
		players[i].reset_stats()
	used_words.clear()
	everyone_rounds = 0
	masterpiece = ""
	winner_idx = -1
	hung_count = 0
	theme_order.clear()
	for i in WordsScript.pack_count():
		theme_order.append(i)
	theme_order.shuffle()
	room.clear_gallery()
	canvas.hide_vote()
	canvas.set_crown(-1)
	net.event("gallery_clear", [])
	_next_round()


func _next_round() -> void:
	_hang_current()
	if round_n >= ROUNDS:
		if hung_count >= 2 and not active_guessers().is_empty():
			_start_vote()
		else:
			_game_over()
		return
	round_n += 1
	round_type = ROUND_PLAN[(round_n - 1) % ROUND_PLAN.size()]
	theme = WordsScript.pack_name(theme_order[(round_n - 1) % theme_order.size()])
	_clear_canvas(false)
	_pick_word()
	skips_left = 2
	time_left = round_time()
	vr_lock = 0.0
	vr_wrong_mask = 0
	applause = 0
	state = "intro"
	state_t = 0.0
	reveal_word = ""
	players[0].reset_round()
	_send_round()
	_set_mood("final" if round_type == "final" else ("speed" if round_type == "speed" else "normal"))
	match round_type:
		"team":
			_show_center("TEAM PAINT!\nRoles swap: TV players, PAINT the word together!\nLeft stick / D-pad moves your brush ring · HOLD A to paint.\n" \
				+ "The VR player guesses with the balloons.\n\nTHEME: %s" % theme, TEAM_INTRO_TIME, true,
				"TEAM PAINT!  You GUESS this time\nTheme: %s" % theme)
			sound("team", -2.0, 1.0, true)
		"speed":
			_show_center("SPEED ROUND!\n35 seconds · points x2\nTHEME: %s" % theme, INTRO_TIME, true, "SPEED ROUND!  35 s · points x2\nTheme: %s" % theme)
			sound("speed", -2.0, 1.0, true)
		"final":
			_show_center("GOLDEN FINAL!\nPoints x2 - make it count!\nTHEME: %s" % theme, INTRO_TIME, true, "GOLDEN FINAL!  Points x2\nTheme: %s" % theme)
			sound("fanfare", -4.0, 1.2, true)
		_:
			if round_n == 1:
				_show_center("PAINT AND GUESS!\nThe VR player paints a secret word - TV players guess it!\n" \
					+ "TV: D-pad / stick picks an answer, A to guess. First right answer scores most!\n" \
					+ "Wrong guesses freeze you for a moment. Hint letters appear over time.\nX / Y / B: cheer the artist!\n\n" \
					+ "ROUND 1 of %d  ·  THEME: %s" % [ROUNDS, theme], FIRST_INTRO_TIME, true, "ROUND 1 of %d\nTheme: %s" % [ROUNDS, theme])
			else:
				_show_center("ROUND %d of %d\nTHEME: %s\nGet ready to guess!" % [round_n, ROUNDS, theme], INTRO_TIME, true,
					"ROUND %d of %d\nTheme: %s" % [round_n, ROUNDS, theme])
			sound("reveal", -4.0, 1.0, true)
	print("Round %d (%s, theme %s): the word is '%s'" % [round_n, round_type, theme, word])


func _set_mood(mood: String) -> void:
	room.set_mood(mood)
	net.event("mood", [mood])


## Choose a fresh word from this round's theme, everyone's answers (one right + three decoys, more of
## them from the same theme as the game goes on) and the order the hint letters appear in.
func _pick_word() -> void:
	var pack: Array = WordsScript.pack_words(theme_order[(round_n - 1) % theme_order.size()] if not theme_order.is_empty() else 0)
	var all: Array = WordsScript.all_words()
	var tries := 0
	word = str(pack[randi() % pack.size()])
	while used_words.has(word) and tries < 60:
		word = str(pack[randi() % pack.size()])
		tries += 1
	used_words.append(word)
	team_word = word if round_type == "team" else ""
	round_id += 1
	correct_count = 0
	remove_meta("first")
	end_t = -1.0
	last_tick = -1
	hints_shown = 0
	hint_order.clear()
	for i in word.length():
		if word[i] != " " and word[i] != "-":
			hint_order.append(i)
	hint_order.shuffle()
	_update_hint()
	var same_theme := 1 if round_n <= 2 else 2
	opts = []
	for i in MAX_PLAYERS:
		var o: Array = [word]
		var guard := 0
		while o.size() < 1 + same_theme and guard < 40:
			guard += 1
			var w: String = str(pack[randi() % pack.size()])
			if not o.has(w):
				o.append(w)
		while o.size() < 4:
			var w2: String = str(all[randi() % all.size()])
			if not o.has(w2):
				o.append(w2)
		o.shuffle()
		opts.append(o)
	opts_round = round_id
	for i in range(1, players.size()):
		players[i].reset_round()


func _max_hints() -> int:
	var letters := word.replace(" ", "").length()
	return maxi(1, letters / 2)


func _update_hint() -> void:
	var shown: Array[int] = []
	for k in mini(hints_shown, hint_order.size()):
		shown.append(hint_order[k])
	var parts: PackedStringArray = []
	for i in word.length():
		if word[i] == " " or word[i] == "-":
			parts.append(word[i])
		elif shown.has(i):
			parts.append(word[i].to_upper())
		else:
			parts.append("_")
	hint_text = " ".join(parts)


func _send_round() -> void:
	net.event("round", [round_n, round_id, opts, state, time_left, round_type, theme, team_word])


func options_for(i: int) -> Array:
	if i < 0 or i >= opts.size():
		return []
	var o: Array = opts[i]
	return o


## A local guesser picked answer `choice` (on the TV machine: ask the host).
func submit_guess(p, choice: int) -> void:
	var o: Array = options_for(p.index)
	if choice < 0 or choice >= o.size():
		return
	var w: String = o[choice]
	if net.mode == "client":
		net.send_action("guess", [opts_round, w], p.index)
	else:
		_try_guess(p.index, w, round_id)


## Host / local: judge a guess.
func _try_guess(idx: int, w: String, rid: int) -> void:
	if state != "draw" or round_type == "team" or rid != round_id or idx <= 0 or idx >= players.size():
		return
	var p = players[idx]
	if not p.active or p.got or p.lock_left > 0.0:
		return
	var o: Array = options_for(idx)
	var choice := o.find(w)
	var top: Vector3 = canvas.canvas_to_world(Vector2(0.0, canvas.H * 0.5 - 0.22), 0.06)
	if w == word:
		var n := active_guessers().size()
		var step := 20 if n <= 2 else 12
		var mult := round_mult()
		var pts := maxi(30, 100 - correct_count * step) + int(time_left * 0.5)
		var extra := ""
		if correct_count == 0:
			pts += 15
			p.firsts += 1
			extra = "FIRST! "
			set_meta("first", [idx, state_t])
		p.streak += 1
		p.best_streak = maxi(p.best_streak, p.streak)
		if p.streak >= 2:
			pts += 10 * (p.streak - 1)
		pts *= mult
		correct_count += 1
		p.got = true
		p.rights += 1
		p.fastest = minf(p.fastest, state_t)
		p.score += pts
		players[0].score += 25 * mult
		var everyone := true
		for g in active_guessers():
			if not g.got:
				everyone = false
		if everyone:
			players[0].score += 25 * mult
			end_t = 1.2
		_guess_fx(idx, true, pts)
		net.event("guess", [idx, true, pts, choice])
		popup(top, "%sP%d +%d" % [extra, idx + 1, pts], p.color)
		_vr_say("P%d GOT IT!%s" % [idx + 1, "  (everyone!)" if everyone else ""], 1.8)
		if p.streak >= 2:
			sound("streak", -4.0, 0.9 + 0.1 * p.streak, true)
			_flash_to(idx, "STREAK x%d!  +%d bonus" % [p.streak, 10 * (p.streak - 1) * mult], Color(1.0, 0.65, 0.2))
		elif extra != "":
			sound("first", -4.0, 1.0, true)
		print("P%d guessed '%s' (+%d%s, streak %d)" % [idx + 1, w, pts, ", first" if extra != "" else "", p.streak])
	else:
		p.lock_left = LOCKOUT
		p.wrongs += 1
		if choice >= 0:
			p.wrong_mask |= 1 << choice
		_guess_fx(idx, false, 0)
		net.event("guess", [idx, false, 0, choice])
		print("P%d guessed '%s' - wrong" % [idx + 1, w])


## Sound, confetti and the audience critter hopping (both machines).
func _guess_fx(idx: int, ok: bool, pts: int) -> void:
	var p = players[idx]
	if ok:
		sound("right", 0.0, 1.0 + 0.06 * correct_count)
		var side := -1.0 if idx % 2 == 1 else 1.0
		confetti(canvas.canvas_to_world(Vector2(side * canvas.W * 0.4, canvas.H * 0.3), 0.08), 40, false)
		canvas.hop(idx - 1, true)
		if players[0].vr:
			players[0].hand_r.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.15, 0.0)
	else:
		sound("wrong", -4.0)
		canvas.hop(idx - 1, false)
	if is_local(p):
		p.on_result(ok, pts)


## A message on one TV player's own screen (both machines; the TV machine gets it as an event).
func _flash_to(idx: int, text: String, col: Color) -> void:
	if idx <= 0 or idx >= players.size():
		return
	if is_local(players[idx]):
		players[idx].flash(text, col, 2.2)
	net.event("flash", [idx, text, col])


# --- TEAM PAINT: the VR player guesses with the balloons -----------------------------------

func artist_guess(i: int) -> void:
	if not is_host_side() or state != "draw" or round_type != "team" or i < 0 or i > 3:
		return
	if vr_lock > 0.0 or (vr_wrong_mask >> i) & 1 == 1:
		sound("nope", -8.0)
		return
	var o: Array = options_for(0)
	if i >= o.size():
		return
	var pos: Vector3 = canvas.balloon_world(i)
	if str(o[i]) == word:
		var pts := 60 + int(time_left)
		players[0].score += pts
		var share := pts / 2
		for g in active_guessers():
			g.score += share + (10 if g.team_ink > 20 else 0)
		correct_count = 1
		popup(pos + Vector3(0, 0.15, 0), "YES! +%d" % pts, Color(0.5, 1.0, 0.5))
		_balloon_fx(i, true)
		net.event("balloon", [i, true])
		print("VR guessed the team's '%s' (+%d, team +%d each)" % [word, pts, share])
		_reveal(true)
	else:
		vr_wrong_mask |= 1 << i
		vr_lock = VR_LOCKOUT
		_balloon_fx(i, false)
		net.event("balloon", [i, false])
		print("VR guessed '%s' - wrong" % str(o[i]))


func _balloon_fx(i: int, ok: bool) -> void:
	var pos: Vector3 = canvas.balloon_world(i)
	if ok:
		sound("right", 0.0, 1.1)
		confetti(pos, 40, false)
		if players[0].vr:
			players[0].hand_r.trigger_haptic_pulse("haptic", 0.0, 0.7, 0.2, 0.0)
	else:
		sound("pop", -2.0)
		puff(pos, CanvasScript.BALLOON_COLS[i], 18)
		vr_wrong_mask |= 1 << i
		if players[0].vr:
			players[0].hand_r.trigger_haptic_pulse("haptic", 0.0, 0.9, 0.08, 0.0)


# --- Cheers ---------------------------------------------------------------------------------

func submit_cheer(g, kind: int) -> void:
	if net.mode == "client":
		net.send_action("cheer", [kind], g.index)
	else:
		_do_cheer(g.index, kind)


func _do_cheer(idx: int, kind: int) -> void:
	if idx <= 0 or idx >= players.size() or not players[idx].active:
		return
	var g = players[idx]
	g.cheers += 1
	if (state == "draw" or state == "reveal") and applause < 20:
		applause += 2
		players[0].score += 2
	_cheer_fx(idx, kind)
	net.event("cheer", [idx, kind])


func _cheer_fx(idx: int, kind: int) -> void:
	kind = clampi(kind, 0, GuesserScript.CHEERS.size() - 1)
	canvas.wiggle(idx - 1)
	var b: Node3D = canvas.audience[idx - 1] if idx - 1 < canvas.audience.size() else null
	if b == null:
		return
	popup(b.global_position + Vector3(0, 0.08, 0.05), GuesserScript.CHEERS[kind], PLAYER_COLORS[idx % PLAYER_COLORS.size()], false, 0.2)
	sound("cheer", -9.0, 1.0 + kind * 0.15)


# --- Reveal, gallery, vote, game over -------------------------------------------------------

func _reveal(all_got: bool) -> void:
	state = "reveal"
	state_t = 0.0
	reveal_word = word
	_lift_all()
	var line := ""
	if round_type == "team":
		line = "The VR player guessed it - TEAM BONUS!" if correct_count > 0 else "TIME'S UP!"
	else:
		line = "EVERYONE GOT IT!" if all_got else ("TIME'S UP!" if correct_count == 0 else "%d got it!" % correct_count)
		var first: Array = get_meta("first", [])
		if correct_count > 0 and first.size() == 2:
			line += "   P%d was first (%d s)!" % [int(first[0]) + 1, maxi(1, int(ceilf(float(first[1]))))]
		for g in active_guessers():
			if not g.got:
				g.streak = 0
	if all_got and round_type != "team" and active_guessers().size() > 0:
		everyone_rounds += 1
		room.cat_cheer()
		net.event("cat", [])
	_show_center("It was %s!\n%s" % [_article(word).to_upper(), line], REVEAL_TIME, true, "It was %s!\n%s" % [_article(word).to_upper(), line])
	sound("fanfare" if correct_count > 0 else "reveal", -2.0, 1.0, true)
	if correct_count > 0:
		confetti(canvas.canvas_to_world(Vector2(0.0, 0.0), 0.1), 60)
	net.event("reveal", [word])
	print("Round %d over: '%s', %d of %d guessed it" % [round_n, word, correct_count, active_guessers().size()])


## Every painter lets go: their strokes get baked (both machines), ready to be hung.
func _lift_all() -> void:
	if players[0].cur_id >= 0:
		stroke_end(0)
		players[0].cur_id = -1
	for i in range(1, players.size()):
		var g = players[i]
		if g.tv_cur_id >= 0:
			stroke_end(g.index)
			g.tv_cur_id = -1
		g.tv_down = false


func _article(w: String) -> String:
	var v := "aeiou"
	return ("an " if v.contains(w[0]) else "a ") + w


## The finished picture flies off the easel into the next gallery frame (both machines build it from
## their own copy of the strokes).
func _hang_current() -> void:
	if reveal_word == "" or canvas.point_count < 8:
		return
	var slot := hung_count % RoomScript.SLOTS.size()
	hung_count += 1
	var team := round_type == "team"
	_hang(slot, reveal_word, team)
	net.event("hang", [slot, reveal_word, team])
	sound("whoosh", -6.0, 1.0, true)


func _hang(slot: int, w: String, team: bool) -> void:
	room.hang(slot, canvas.build_picture(), w, team, canvas.stroke_root.global_transform, canvas.paint_material())


func _start_vote() -> void:
	state = "vote"
	state_t = 0.0
	time_left = VOTE_TIME
	vote_done_t = -1.0
	votes.clear()
	artist_vote_k = -1
	reveal_word = ""
	_clear_canvas(false)
	var slots: Array = room.pictures.keys()
	slots.sort()
	vote_slots.clear()
	vote_words.clear()
	for sv in slots:
		var slot: int = sv
		vote_slots.append(slot)
		vote_words.append(str(room.pictures[slot]["word"]))
	_show_vote_grid()
	players[0].trig_block = true
	for i in range(1, players.size()):
		players[i].vote = -1
		players[i].vote_cursor = 0
	net.event("vote_show", [vote_slots, vote_words])
	_show_center("THE GALLERY VOTE!\nWhich picture is the best? Pick one and press A!", 4.0, true,
		"THE GALLERY VOTE!\nTouch your favourite picture")
	sound("reveal", -2.0, 1.2, true)
	_set_mood("party")
	print("Vote: %d pictures %s" % [vote_slots.size(), str(vote_words)])


func _show_vote_grid() -> void:
	var pics: Array = []
	for k in vote_slots.size():
		var slot: int = vote_slots[k]
		var mesh: ArrayMesh = null
		if room.pictures.has(slot):
			mesh = room.pictures[slot]["mesh"]
		pics.append([mesh, vote_words[k]])
	canvas.show_vote(pics)


func vote_count() -> int:
	return vote_slots.size()


func vote_word(k: int) -> String:
	return vote_words[k] if k >= 0 and k < vote_words.size() else ""


func submit_vote(g, k: int) -> void:
	if net.mode == "client":
		net.send_action("vote", [k], g.index)
	else:
		_cast_vote(g.index, k)


func artist_vote(k: int) -> void:
	if is_host_side() and k >= 0:
		_cast_vote(0, k)


func _cast_vote(voter: int, k: int) -> void:
	if state != "vote" or vote_done_t >= 0.0 or k < 0 or k >= vote_slots.size():
		return
	if voter > 0 and (voter >= players.size() or not players[voter].active):
		return
	votes[voter] = k
	if voter > 0:
		players[voter].vote = k
	else:
		artist_vote_k = k
		players[0].buzz(0.5, 0.08)
	sound("vote", -4.0, 1.0 + 0.05 * k, true)
	print("Vote: %s picks #%d (%s)" % ["artist" if voter == 0 else "P%d" % (voter + 1), k + 1, vote_words[k]])


func _all_voted() -> bool:
	if not votes.has(0):
		return false
	for g in active_guessers():
		if not votes.has(g.index):
			return false
	return true


func _finish_vote() -> void:
	var counts: Array[int] = []
	counts.resize(vote_slots.size())
	counts.fill(0)
	for v in votes.values():
		var k: int = v
		if k >= 0 and k < counts.size():
			counts[k] += 1
	var best := 0
	for c in counts:
		best = maxi(best, c)
	var win: Array = []
	var names: PackedStringArray = []
	if best > 0:
		for k in counts.size():
			if counts[k] == best:
				win.append(vote_slots[k])
				names.append(vote_words[k].to_upper())
	# Every vote is worth points for whoever painted that picture.
	for v in votes.values():
		var k2: int = v
		if k2 < 0 or k2 >= vote_slots.size():
			continue
		var slot: int = vote_slots[k2]
		var team: bool = room.pictures.has(slot) and room.pictures[slot]["team"]
		if team:
			for g in active_guessers():
				g.score += 10
		else:
			players[0].score += 10
	masterpiece = " & ".join(names)
	vote_done_t = 4.5
	room.set_gold(win)
	canvas.hide_vote()
	net.event("vote_result", [win])
	if win.is_empty():
		_show_center("Nobody voted - every picture is a winner!", 3.0)
	else:
		_show_center("MASTERPIECE!\nThe %s picture wins with %d vote%s!" % [masterpiece, best, "" if best == 1 else "s"], 4.0, true,
			"MASTERPIECE!\nThe %s picture wins!" % masterpiece)
		sound("masterpiece", 0.0, 1.0, true)
		for sv in win:
			var slot2: int = sv
			confetti(room.slot_pos(slot2) + Vector3(0, 0, 0.2), 50)
	print("Vote result: %s (%d votes)" % [masterpiece if masterpiece != "" else "none", best])


func _game_over() -> void:
	state = "over"
	state_t = 0.0
	reveal_word = ""
	vote_done_t = -1.0
	canvas.hide_vote()
	var board := _scoreboard()
	var best = null
	for g in active_guessers():
		if best == null or g.score > best.score:
			best = g
	var top := "WHAT A GALLERY!"
	winner_idx = -1
	if best != null and best.score > 0:
		top = "PLAYER %d WINS THE GUESSING!" % (best.index + 1)
		winner_idx = best.index
	var awards := _awards()
	canvas.set_crown(winner_idx - 1 if winner_idx > 0 else -1)
	net.event("over", [winner_idx, awards])
	set_meta("awards", awards)
	_show_center("%s\n%s\n\n%s\n\nA / Enter (VR: trigger) to play again" % [top, board, awards], 0.0, true, top)
	sound("fanfare", 0.0, 1.0, true)
	_set_mood("party")
	confetti(canvas.canvas_to_world(Vector2(-0.4, 0.2), 0.1), 60)
	confetti(canvas.canvas_to_world(Vector2(0.4, 0.2), 0.1), 60)
	print("Game over: %s | awards: %s" % [board.replace("\n", " | "), awards.replace("\n", " | ")])


## Fun end-of-game awards from everybody's stats (a few lines, kid-friendly).
func _awards() -> String:
	var out: PackedStringArray = []
	if masterpiece != "":
		out.append("MASTERPIECE: the %s picture" % masterpiece)
	var gs := active_guessers()
	var quick = null
	var firsts = null
	var streaky = null
	var sharp = null
	var cheery = null
	var inky = null
	for g in gs:
		if g.fastest < 999.0 and (quick == null or g.fastest < quick.fastest):
			quick = g
		if g.firsts >= 2 and (firsts == null or g.firsts > firsts.firsts):
			firsts = g
		if g.best_streak >= 3 and (streaky == null or g.best_streak > streaky.best_streak):
			streaky = g
		if g.rights >= 2 and g.wrongs == 0 and (sharp == null or g.rights > sharp.rights):
			sharp = g
		if g.cheers >= 3 and (cheery == null or g.cheers > cheery.cheers):
			cheery = g
		if g.team_ink > 30 and (inky == null or g.team_ink > inky.team_ink):
			inky = g
	if quick != null:
		out.append("QUICKEST EYES: P%d (%d s)" % [quick.index + 1, maxi(1, int(ceilf(quick.fastest)))])
	if firsts != null:
		out.append("FIRST EVERY TIME: P%d (%d firsts)" % [firsts.index + 1, firsts.firsts])
	if streaky != null:
		out.append("HOT STREAK: P%d (%d in a row)" % [streaky.index + 1, streaky.best_streak])
	if sharp != null:
		out.append("SHARP EYES: P%d (no wrong guesses)" % (sharp.index + 1))
	if cheery != null:
		out.append("BEST CHEERLEADER: P%d (%d cheers)" % [cheery.index + 1, cheery.cheers])
	if inky != null:
		out.append("BUSIEST TEAM BRUSH: P%d" % (inky.index + 1))
	var cols: int = players[0].colors_used.size()
	if everyone_rounds >= 2:
		out.append("CROWD PLEASER: everyone guessed %d pictures" % everyone_rounds)
	elif cols >= 5:
		out.append("RAINBOW ARTIST: %d colours" % cols)
	if out.is_empty():
		out.append("EVERYONE: brilliant painting and guessing!")
	return "\n".join(out.slice(0, 5))


func _scoreboard() -> String:
	var parts: PackedStringArray = []
	parts.append("ARTIST %d" % players[0].score)
	for g in active_guessers():
		parts.append("P%d %d" % [g.index + 1, g.score])
	return "   ".join(parts)


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ------------------------------------

func on_client_joined() -> void:
	_show_center("THE TV PLAYERS JOINED!", 1.5)
	_send_sync()
	if state == "wait" or state == "over":
		_start_game()
	else:
		_send_round()


func on_client_left() -> void:
	for i in range(2, players.size()):
		if players[i].active:
			players[i].set_active(false)
	state = "wait"
	canvas.hide_vote()
	_show_center("The TV players left - waiting for them to come back…", 0.0)


func _send_sync() -> void:
	_flush_points()
	net.event("sync", [canvas.rev, canvas.export_strokes()])


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
		"guess":
			if args.size() >= 2:
				_try_guess(index, str(args[1]), int(args[0]))
		"cheer":
			if args.size() >= 1:
				_do_cheer(index, int(args[0]))
		"vote":
			if args.size() >= 1:
				_cast_vote(index, int(args[0]))
		"need_round":
			_send_round()
		"need_sync":
			_send_sync()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused
			if not paused:
				players[0].trig_block = true


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false, ("PAUSED\n" + who) if paused else "")
	if vr_center != null and paused:
		VrText.snap(vr_center)
		VrText.snap(vr_status)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	players[0].trig_block = true  # the trigger that resumed must not paint or pick anything
	cont_was = true
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHold the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var gs: Array = []
	for i in range(1, players.size()):
		var g = players[i]
		gs.append([g.active, g.score, g.got, g.lock_left, g.wrong_mask, g.streak, g.vote])
	var a = players[0]
	return [state, round_n, time_left, state_t, round_id, hint_text, a.score, gs, a.cursor, a.cursor_on,
		a.drawing(), a.color_idx, canvas.rev, sent_points, canvas.cy, reveal_word, round_type, theme,
		vr_wrong_mask, vote_done_t, artist_vote_k]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 21:
		return
	synced = true
	var new_state: String = s[0]
	if new_state != state:
		state = new_state
		state_t = float(s[3])
	round_n = s[1]
	var tl: float = s[2]
	if absf(tl - time_left) > 0.3:
		time_left = tl
	hint_text = s[5]
	var a = players[0]
	a.score = s[6]
	var gs: Array = s[7]
	for i in gs.size():
		var idx := i + 1
		if idx >= players.size():
			break
		var st: Array = gs[i]
		var g = players[idx]
		var act: bool = st[0]
		if act != g.active:
			g.set_active(act)
			on_player_activity_changed(g)
		g.score = st[1]
		g.got = st[2]
		g.lock_left = st[3]
		g.wrong_mask = st[4]
		g.streak = st[5]
		g.vote = st[6]
	a.net_cursor = s[8]
	a.net_on = s[9]
	var drawing: bool = s[10]
	a.color_idx = s[11]
	canvas.set_cursor(s[8], s[9], canvas.ui_color(a.color_idx) if artist_mode() == "paint" else Color(1, 1, 1), drawing)
	var cy: float = s[14]
	if absf(cy - canvas.cy) > 0.001:
		canvas.set_height(cy)
	reveal_word = s[15]
	round_type = s[16]
	theme = s[17]
	vr_wrong_mask = s[18]
	vote_done_t = s[19]
	artist_vote_k = s[20]
	net_rev = s[12]
	net_sent_points = s[13]
	_client_checks(int(s[4]))


## TV machine: ask the host again for anything we missed (joined late, or events arrived before we
## were ready): this round's answers, or the whole canvas.
func _client_checks(rid: int) -> void:
	var dt := get_process_delta_time()
	ask_t -= dt
	var need_round := rid != opts_round and state != "wait" and state != "over" and state != "vote"
	if net_rev != canvas.rev or net_sent_points != canvas.point_count:
		sync_bad_t += dt
	else:
		sync_bad_t = 0.0
	if ask_t > 0.0:
		return
	if need_round:
		ask_t = 1.0
		net.send_action("need_round", [], 1)
	if sync_bad_t > 1.5:
		ask_t = 2.0
		sync_bad_t = 0.0
		net.send_action("need_sync", [], 1)
		print("Net: canvas out of step (rev %d/%d, points %d/%d) - asking for a sync" % [canvas.rev, net_rev, canvas.point_count, net_sent_points])


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"confetti":
			confetti(args[0], args[1], false)
		"popup":
			popup(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false, str(args[2]) if args.size() > 2 else "\u0001")
		"flash":
			var fi: int = args[0]
			if fi > 0 and fi < players.size() and is_local(players[fi]):
				players[fi].flash(str(args[1]), args[2], 2.2)
		"sb":
			canvas.begin_stroke(int(args[0]), int(args[1]), float(args[2]), args[3], int(args[4]) if args.size() > 4 else 0)
		"pts":
			var pts: PackedVector2Array = args[1]
			canvas.add_points(int(args[0]), pts)
		"se":
			canvas.end_stroke(int(args[0]))
		"undo":
			canvas.remove_stroke(int(args[0]))
		"clr":
			canvas.clear_all()
			canvas.rev = int(args[0])
		"sync":
			canvas.import_strokes(args[1])
			canvas.rev = int(args[0])
			print("Net: canvas synced (%d strokes, %d points)" % [canvas.strokes.size(), canvas.point_count])
		"round":
			var rn: int = args[0]
			var rid: int = args[1]
			var new_opts: Array = args[2]
			if rid != opts_round:
				correct_count = 0
				for i in range(1, players.size()):
					players[i].reset_round()
			round_n = rn
			opts_round = rid
			opts = new_opts
			var st: String = args[3]
			if st != state:
				state = st
				state_t = 0.0
			time_left = args[4]
			reveal_word = ""
			if args.size() > 7:
				round_type = args[5]
				theme = args[6]
				team_word = args[7]
		"guess":
			var idx: int = args[0]
			var ok: bool = args[1]
			if idx > 0 and idx < players.size():
				var choice: int = args[3]
				if ok:
					players[idx].got = true
					correct_count += 1
				elif choice >= 0:
					players[idx].wrong_mask |= 1 << choice
					players[idx].lock_left = LOCKOUT
				_guess_fx(idx, ok, int(args[2]))
		"balloon":
			_balloon_fx(int(args[0]), bool(args[1]))
		"cheer":
			_cheer_fx(int(args[0]), int(args[1]))
		"cat":
			room.cat_cheer()
		"reveal":
			reveal_word = args[0]
			state = "reveal"
			state_t = 0.0
			correct_count = 0
		"hang":
			_hang(int(args[0]), str(args[1]), bool(args[2]))
		"gallery_clear":
			room.clear_gallery()
			canvas.set_crown(-1)
			canvas.hide_vote()
		"vote_show":
			vote_slots.clear()
			vote_words.clear()
			for sv in args[0]:
				vote_slots.append(int(sv))
			for wv in args[1]:
				vote_words.append(str(wv))
			state = "vote"
			state_t = 0.0
			time_left = VOTE_TIME
			vote_done_t = -1.0
			_show_vote_grid()
			for i in range(1, players.size()):
				players[i].vote_cursor = 0
		"vote_result":
			room.set_gold(args[0])
			canvas.hide_vote()
		"over":
			canvas.set_crown(int(args[0]) - 1 if int(args[0]) > 0 else -1)
			set_meta("awards", str(args[1]))
		"mood":
			room.set_mood(str(args[0]))
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR artist paused the game")


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
	center_label.offset_bottom = -200
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -40
	help_label.offset_bottom = -6
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Guess: D-pad / stick (arrows) + A (Enter)  ·  cheer: X / Y / B  ·  more players: press A on another controller  ·  Start / Esc menu"


## TV banner text; vr: the short version for the VR player ("\u0001" = the first two lines).
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
	vr_msg = vr
	vr_msg_t = duration if duration > 0.0 else 9999.0


## A short message for the VR player only (the TV banner is left alone).
func _vr_say(text: String, duration: float) -> void:
	vr_msg = text
	vr_msg_t = duration


func _rank(p) -> int:
	var r := 1
	for g in active_guessers():
		if g != p and g.score > p.score:
			r += 1
	return r


func hud_text(p) -> String:
	if net.mode == "client" and not synced:
		return "Syncing with the VR artist…"
	if p.index == 0:
		var t := "YOU'RE THE ARTIST!   score %d" % p.score
		match artist_mode():
			"guess":
				t += "\nTEAM PAINT: guess what they paint - click a balloon!"
			"vote":
				t += "\nVOTE: click your favourite picture"
			_:
				if state == "draw" or state == "intro":
					t += "\nDRAW:  %s" % word.to_upper()
					if state == "draw":
						t += "   ·   %d s" % int(ceilf(time_left))
		t += "\nColour: %s  ·  Mouse/WASD/stick move · Left click/Space/A paint" % canvas.COLOR_NAMES[p.color_idx]
		t += "\nC/RMB/X colour · Z/LB undo · Backspace/Y clear · N/B new word"
		return t
	var line := "P%d   %d pts" % [p.index + 1, p.score]
	if active_guessers().size() > 1:
		line += "   #%d" % _rank(p)
	if round_n > 0:
		line += "\nROUND %d/%d" % [round_n, ROUNDS]
	return line


## The artist's brush shows what to draw and the time left (VR text they always see).
func brush_text() -> String:
	match state:
		"draw":
			if round_type == "team":
				return "GUESS!\n%d s" % int(ceilf(time_left))
			return "%s\n%d s" % [word.to_upper(), int(ceilf(time_left))]
		"intro":
			return "get ready…" if round_type == "team" else "%s\nget ready…" % word.to_upper()
		"wait":
			return "practice!"
		"vote":
			return "VOTE!"
	return ""


## Writing on the easel itself (world-locked, where the artist is looking anyway).
func _update_easel_text() -> void:
	var a = players[0]
	var vr_like: bool = a.vr or a.fake_vr
	var team := round_type == "team"
	canvas.word_label.text = ("DRAW:  %s" % word.to_upper()) if (state == "draw" or state == "intro") and is_host_side() and not team else ""
	canvas.word_label.visible = not a.vr  # the VR player reads it in the floating header instead
	canvas.hint_label.layers = HINT_LAYER
	if state == "draw":
		canvas.hint_label.text = ("PAINT:  %s" % team_word.to_upper()) if team else hint_text
	else:
		canvas.hint_label.text = ""
	canvas.tip_label.layers = CanvasScript.SECRET_LAYER
	canvas.tip_label.text = _artist_tip(vr_like)
	var info := ""
	canvas.info_label.font_size = 40
	match state:
		"wait":
			if vr_like:
				info = "PAINT AND GUESS\nWaiting for the TV players…\nPractice! Hold the trigger to paint."
			else:
				info = "PAINT AND GUESS\nWaiting for the VR artist…"
		"intro":
			if team:
				info = "TEAM PAINT!\nThe TV players paint a secret word together.\n" + \
					("YOU guess! Touch the balloon with the right answer (or point at it + trigger)." if vr_like else "The artist guesses!")
			elif round_type == "speed":
				info = "SPEED ROUND!\n35 seconds · points x2\nDraw fast and BIG!"
			elif round_type == "final":
				info = "GOLDEN FINAL!\nPoints x2 - make it count!"
			elif vr_like and round_n == 1:
				info = "YOU ARE THE ARTIST!\nPaint the word above so the TV players can guess it.\n"
				info += "Hold the RIGHT TRIGGER to paint - touch the board or point at it.\n"
				info += "A = next colour (or touch a paint pot - try RAINBOW and SPARKLE!)\nUNDO · CLEAR · NEW WORD bubbles on the right\nLeft stick walks around"
			elif vr_like:
				info = "ROUND %d of %d\nTheme: %s\nGet ready to paint!" % [round_n, ROUNDS, theme]
			else:
				info = "ROUND %d of %d\nTheme: %s\nThe artist is getting ready…" % [round_n, ROUNDS, theme]
		"reveal":
			info = "It was %s!" % _article(reveal_word).to_upper() if reveal_word != "" else ""
		"vote":
			if vote_done_t >= 0.0:
				info = "MASTERPIECE!\n%s" % masterpiece if masterpiece != "" else "Every picture is a winner!"
		"over":
			canvas.info_label.font_size = 32
			info = "THE END!\n" + _scoreboard().replace("   ", "  ·  ") + "\n\n" + str(get_meta("awards", ""))
	canvas.info_label.text = info
	canvas.score_label.visible = round_n > 0
	var sb := "%s\n" % (round_title() if state != "over" and state != "vote" else "SCORES")
	if state == "draw":
		sb += "%d s\n" % int(ceilf(time_left))
	sb += "\nARTIST %d\n" % a.score
	var cursors: Array = []
	for i in range(1, players.size()):
		var g = players[i]
		canvas.set_audience(i - 1, g.active, g.got and (state == "draw" or state == "reveal"))
		if g.active:
			sb += "P%d  %d%s%s\n" % [i + 1, g.score, "  GOT IT" if g.got and (state == "draw" or state == "reveal") else "",
				"  x%d" % g.streak if g.streak >= 2 else ""]
			if team and state == "draw" and (is_host_side() or is_local(g)):
				cursors.append([g.tv_cursor, g.color, g.tv_down])
	canvas.score_label.text = sb
	canvas.set_tv_cursors(cursors)
	canvas.set_timer(time_frac(), state == "draw")
	canvas.show_tools(artist_mode() == "paint")
	canvas.show_balloons(options_for(0), state == "draw" and team, vr_wrong_mask)
	if state == "vote" and vote_done_t < 0.0:
		var marks: Array = []
		if artist_vote_k >= 0:
			marks.append([artist_vote_k, PLAYER_COLORS[0]])
		for i in range(1, players.size()):
			var g2 = players[i]
			if g2.active and g2.vote >= 0:
				marks.append([g2.vote, g2.color])
		canvas.set_vote_marks(marks)


## Short contextual tips for the artist on the bottom of the board (artist views only).
func _artist_tip(vr_like: bool) -> String:
	var a = players[0]
	match artist_mode():
		"paint":
			if state != "draw":
				return ""
			if a.painted_points == 0 and state_t > 4.0:
				return "Hold the RIGHT TRIGGER and touch the board to paint!" if vr_like else "Hold Space / left mouse / A to paint!"
			if state_t > 25.0 and correct_count == 0 and fmod(state_t, 8.0) < 5.0:
				return "Tip: draw it BIG!  A = new colour · UNDO fixes mistakes" if vr_like else "Tip: draw it BIG! C = new colour, Z = undo"
		"guess":
			if vr_lock > 0.0:
				return "Pop! Not that one - wait a moment…"
			return "Touch the balloon with the right answer!" if vr_like else "Click the balloon with the right answer!"
		"vote":
			if artist_vote_k < 0:
				return "Touch your favourite picture (or point + trigger)" if vr_like else "Click your favourite picture"
			return "You picked #%d - touch another to change" % (artist_vote_k + 1)
	return ""


## The VR player's floating text: a status line (word, time) and short messages above it, far enough
## to focus on comfortably and above the easel so nothing nearer overlaps it. VR-only layer.
func _update_vr_text(delta: float) -> void:
	help_label.visible = state != "draw"  # keep the bottom row's answers clear
	if help_label.modulate.a > 0.0 and round_n >= 2:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - delta * 0.5)
	if players.is_empty() or not players[0].vr:
		return
	var cam: XRCamera3D = players[0].xr_camera
	if vr_center == null:
		vr_center = _vr_label(44, 700.0)
		vr_center.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		vr_status = _vr_label(44, 0.0)
		vr_status.modulate = Color(1.0, 0.95, 0.6)
	vr_msg_t -= delta
	var alpha := clampf(vr_msg_t / 0.5, 0.0, 1.0)
	vr_center.text = vr_msg
	vr_center.modulate.a = alpha
	vr_center.outline_modulate = Color(0, 0, 0, alpha)
	vr_status.text = _vr_status_text()
	VrText.follow(vr_center, cam, self, 0.62, 1.8)
	VrText.follow(vr_status, cam, self, 0.42, 1.8)


func _vr_label(size: int, width: float) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.outline_size = 26
	l.pixel_size = 0.0022
	l.render_priority = 10
	l.outline_render_priority = 9
	l.layers = VR_LAYER
	if width > 0.0:
		l.width = width
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func _vr_status_text() -> String:
	match state:
		"wait":
			return "Waiting for the TV players - practise painting!"
		"intro":
			return "Get ready - TEAM PAINT" if round_type == "team" else "Get ready:  %s" % word.to_upper()
		"draw":
			var secs := int(ceilf(time_left))
			if round_type == "team":
				return "GUESS what they paint!  ·  %d" % secs
			return "%s  ·  %d" % [word.to_upper(), secs]
		"vote":
			return "VOTE  ·  %d" % int(ceilf(time_left)) if vote_done_t < 0.0 else ""
	return ""
