extends Node3D
## RHYTHM BAND - co-op music game. The VR player is the DRUMMER, hitting floating drums with their
## hands as glowing balls fly into them; the TV players (1-6) play a 3-lane note highway each
## (Guitar-Hero style). Every song is generated in code: the backing loop is synthesized and the players
## make the melody and the beat themselves. Hits fill the shared CROWD meter and the band combo.
## A TOUR: the SETLIST menu (everyone picks their own level - EASY / NORMAL / ROCK; the VR drummer
## picks by hitting a drum, the CRASH starts the show), then 3 songs from slow to fast (picked from 6
## songs in different styles), stars after each song, and awards at the end.
## Gold STAR notes charge the band's STAR POWER; when it's full the drummer hits the CRASH or any TV
## player presses Y: double points, a wild crowd, gold lights and fireworks. Hitting the same beat
## together scores IN SYNC bonuses; band combos set off pyro and fireworks.
## Modes, networking and party join follow docs/GAME_DEV_GUIDE.md and games/marble_maze.
## The song clock: the host owns it (snapshots carry it); every machine plays the same backing
## locally and judges its own players against the clock it hears, then reports hits to the host.
##
## SIMPLE_MODE (the family: "all of the games have become too complicated", "simple games are the fun
## games", "everything's being driven by text"). The core stays: the VR drummer hits floating drums as
## glowing balls fly into them, the TV players play a note highway, and together it's music.
##  - No SETLIST menu, no levels to pick: a short PRACTICE (one ball floats into one drum at a time and
##    waits, a see-through stick shows the swing; TV: one slow note per lane waits on its ring), then
##    the songs just keep coming, gently harder: song 1 is slow and short with EASY drums and only two
##    lanes (X and B) on the TV, song 2 adds the middle lane, song 3 on gets NORMAL drums and is longer.
##  - Off: gold STAR notes and STAR POWER, IN SYNC bonuses, combo / score / star meters and readouts,
##    PERFECT / GOOD / MISS words, result stars, the awards and tour screens, stats. Hits make sparks,
##    rings burst, the crowd jumps and cheers, combos still set off pyro and fireworks (no words).
##  - Everything interactable: stage toys around the kit (props.gd) - cowbell, splash cymbal,
##    microphone, amp, spotlight, maracas to pick up and shake.
##  - Text: one short headline at a time (RHYTHM BAND!, SONG 2!, 3-2-1, PLAY!, HOORAY!, PLAYER 3!).
##  - Kept: networking, VR comfort (kit fit, walking, snap turn), the wrist MENU, split screen.
##  - No how-to words (visual teaching): each TV guitarist gets a pulsing glowing pad button and a
##    glowing arrow pointing at the ring to hit (X / A / B, or an arrow key cap for keyboard players)
##    in practice and whenever a lane is new (song 2's middle lane); the flat drummer gets the drum's
##    button (X A B Y / A S D F) floating over the glowing drum. A glowing 3D arrow bobs over the
##    practice drum on every screen (VR: next to the see-through stick). Each cue fades once that
##    player has hit that lane / drum twice. Between songs the VR drummer sees the shared ghost hand
##    (games/cannon_cove/ghost_hand.gd) reach for a maraca, squeeze and shake it, until they have
##    picked one up twice. The start headline is VR only (the TV sees the RHYTHM BAND sign), PAUSED
##    has no sentence, and no view shows its own player's name tag.
##
## STORY + DEPTH (games/rhythm_band/songgen.gd, fans.gd, story_pictures.gd): every song is generated from a
## seed (name, tempo, key, chords, style, charts), the show gets gently harder song by song, and
## tests/rhythm_band_gen_test.gd proves every song is playable by small kids. DOODLE the frog sings on top of the
## RHYTHM BAND sign and tells the story on picture cards; each finished song brings a new animal fan
## to the FAN CLUB ledge over the LED wall (saved, user://saves/rhythm_band; fans grow each day played).
## TODAY'S SONG: the second song of the day's first show is the same gold song on every machine. One
## telemetry RUN line per song and on quit. Networked: the host sends one int song code per song (the
## snapshot's song + setlist) and the fan club as replicated state ("fans", "days"); story cards are
## "story" events.

const VrText := preload("res://core/vr_text.gd")
const Who := preload("res://core/who.gd")  # who joined / left (names, not "TV player")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const SfxScript := preload("res://core/sfx.gd")
const NetScript := preload("res://core/net.gd")
const ClassicSeats := preload("res://core/classic_seats.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SongScript := preload("res://games/rhythm_band/song.gd")
const InstrumentsScript := preload("res://games/rhythm_band/instruments.gd")
const StageScript := preload("res://games/rhythm_band/stage.gd")
const DrummerScript := preload("res://games/rhythm_band/drummer.gd")
const GuitaristScript := preload("res://games/rhythm_band/guitarist.gd")
const HighwayScript := preload("res://games/rhythm_band/highway.gd")
const JoinListenerScript := preload("res://games/rhythm_band/join_listener.gd")
const SongGen := preload("res://games/rhythm_band/songgen.gd")
const FanClubScript := preload("res://games/rhythm_band/fans.gd")
const Seeded := preload("res://core/seeded.gd")
const Save := preload("res://core/save.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")

const MAX_PLAYERS := 7  # VR drummer + 6 guitarists
const MAX_LOCAL_VIEWS := 6
## Any number of TV machines (TV, Steam Decks) may join, and a flat host (no VR) works (docs/MULTI_MACHINE.md).
var multi_machine := true
## Which machine drives which seat (core/net.gd checks it too).
var seats: ClassicSeats
const PAD_LEAVE_TIME := 20.0
const PERFECT := 0.085  # seconds either side (NORMAL)
const GOOD := 0.17
const WINDOWS: Array[Vector2] = [Vector2(0.13, 0.27), Vector2(0.085, 0.17), Vector2(0.07, 0.145)]  # EASY, NORMAL, ROCK
const LEVEL_NAMES: Array[String] = ["EASY", "NORMAL", "ROCK"]
const NOTE_BARS := 24
const INTRO_TIME := 3.5
const FIRST_INTRO_TIME := 6.0
const RESULTS_AUTO := 12.0
const MENU_AUTO := 25.0
const SONGS_PER_TOUR := 3
const START_LEAD := 0.6
const STAR_BEATS := 16.0
const DRUM_SPOT := Vector3(0.0, 0.8, 1.2)
const SIMPLE_MODE := true
const PRACTICE_PADS: Array[int] = [1, 2, 0, 3]  # snare, tom, hi-hat, then the big crash
const PRACTICE_LANES: Array[int] = [0, 2, 0, 2]  # song 1 has only the outer lanes
const PRACTICE_MAX := 45.0  # practice never holds the show up longer than this
const PRACTICE_WAIT := 12.0  # once someone has finished, the others get this long
const CELEBRATE_TIME := 5.0
const SIMPLE_BARS: Array[int] = [12, 16, 20, 24]  # bars of notes for songs 1, 2, 3, 4+
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0),
	Color(0.35, 0.9, 0.35), Color(1.0, 0.8, 0.1), Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.15)]
const SOUNDS := {
	"go": [0.4, 440.0, 880.0, 0.35, "square", 0.0],
	"join": [0.45, 523.0, 1318.0, 0.3, "tri", 0.0],
	"tour": [1.0, 392.0, 1568.0, 0.35, "tri", 0.0],
	"star": [1.0, 330.0, 1980.0, 0.38, "square", 0.05],
	"ready": [0.5, 660.0, 1320.0, 0.25, "tri", 0.0],
	"boom": [0.6, 120.0, 30.0, 0.5, "saw", 0.7],
	"fw": [0.9, 1600.0, 200.0, 0.22, "sine", 0.8],
	"sync": [0.25, 880.0, 1760.0, 0.2, "tri", 0.0],
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

var state := "wait"  # wait, menu, intro, play, results, tour
var state_t := 0.0
var song = null
var song_idx := 0  # the song's code (songgen.gd: seed, level, daily)
var tour_pos := 0  # 0..2: which song of the tour
var setlist: Array[int] = [SongGen.code_of(1, 1, false), SongGen.code_of(2, 3, false), SongGen.code_of(3, 5, false)]
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
var drum_level := 1
var star_meter := 0.0
var star_until := -1.0  # song time when STAR POWER ends
var star_uses := 0
var sync_map := {}  # note time bucket -> bitmask of players who hit it
var sync_count := 0
var tour_sync := 0
var tour_star_uses := 0
var d_judged := PackedByteArray()
var d_next := 0
var last_beat := -999
var last_pluck := -1
var cheer_cd := 0.0
var cont_was := false
var vr_start_was := false
var simple := SIMPLE_MODE  # other scripts may read main.simple
var bars_cap := NOTE_BARS
var prac_d := 0  # PRACTICE: the drummer's next practice drum (index into PRACTICE_PADS)
var prac_t := 0.0  # time since the drummer's practice ball set off
var prac_first_done := -1.0

var backing: AudioStreamPlayer
var backing_serial := -1
var synth_task := -1
var synth_obj = null
var seek_cd := 0.0

var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_msg := ""
var vr_msg_t := 0.0
var save: Save
var fan_club: FanClubScript
var session_seed := 0
var story_queue: Array = []  # [line, pic, color] waiting to show
var story_t := 0.0
var song_live := false  # host: a song is being played (a RUN line is due)
var songs_played := 0  # this session
var story_shown: Array[String] = []  # pictures of the story cards shown (bots check them)


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
	bars_cap = song_bars
	session_seed = Seeded.fresh_seed()
	save = Save.new()
	save.game_id = SongGen.GAME_ID
	# fans: [[kind, play-day joined, golden], ...] (oldest first); songs: songs finished in all; days: days
	# played; daily: the date TODAY'S SONG was played.
	save.defaults = {"best": 0, "fans": [], "fans_total": 0, "songs": 0, "days": 0, "last_day": "", "daily": "", "sessions": 0}
	add_child(save)
	fan_club = FanClubScript.new()
	fan_club.name = "FanClub"
	fan_club.main = self
	add_child(fan_club)
	fan_club.build()
	_build_hud()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	seats = ClassicSeats.new(self, {
		"no_keys": GuitaristScript.NO_KEYS,
		"free_actions": ["continue", "pause"],
		"deactivate": _seat_gone,
		"full": func() -> void: _show_center("The band is full!", 1.5, false),
	})
	Input.joy_connection_changed.connect(_on_joy_changed)
	best = maxi(_load_best(), int(save.data.best))
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
	if seats.deck_alone():
		seats.deck_solo(0)
	ready_to_play = true
	_ensure_join_listener()
	if mode == "client":
		players[1].set_meta("want_join", true)  # ask the host for a band spot (it may hand out another one)
	_restore_party()
	stage.set_tags_for_vr(players[0].vr)
	if mode != "client":
		_start_fan_club()
	if mode == "host" and SIMPLE_MODE:
		_start_practice()
	elif mode == "host":
		state = "wait"
		_load_song(setlist[0], song_bars)
		_show_center("RHYTHM BAND\nWaiting for the TV band to join…\nDrum along while you wait! Pull the trigger to pick the songs now.", 0.0, true,
			"Waiting for the TV band…\nDrum along! Trigger: start")
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED", 1.5, false)
	else:
		_enter_menu()


func _exit_tree() -> void:
	_run_line("quit")
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
	HudKit.popup(self, pos, text, {"color": color, "size": 0.178 * size, "lift": 0.12, "time": 0.9, "outline": Color(0, 0, 0, 0.9)})


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
	UiKit.pin(bg, Control.PRESET_FULL_RECT, false)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	UiKit.pin(views_root, Control.PRESET_FULL_RECT, false)


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
		cam.cull_mask &= ~stage.tag_layer(p.index)  # your own name tag never sits in your own view
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hw: Control = HighwayScript.new()
	hw.main = self
	hw.p = p
	hud_layer.add_child(hw)
	UiKit.pin(hw, Control.PRESET_FULL_RECT, false)
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
		c.visible = p.active and is_local(p)
		if c.visible:
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
		UiKit.pin(c, Control.PRESET_TOP_LEFT)
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
	if not ready_to_play:
		return
	if net.mode == "host":
		if connected and not players[0].vr and players[0].joy < 0:
			players[0].joy = device  # flat host (no VR): P1 drums with this controller
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
		if pick == null and players[1].joy < 0 and is_local(players[1]):
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


func _join_slot(device: int):
	var idx := seats.free_index()
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


## Local: join now. TV machine: ask the host (retried by seats.request_joins until it agrees).
func _request_join(p) -> void:
	p.remove_meta("left_by_pad")
	p.pad_lost_t = -1.0
	if net.mode == "client":
		p.set_meta("want_join", true)
		seats.ask_soon()
	elif not p.active:
		_activate(p)
	_save_party()


func _activate(p) -> void:
	p.set_active(true)
	if p.index > 0:
		p.reset_for_song()
	_show_center(("PLAYER %d!" % (p.index + 1)) if SIMPLE_MODE else Who.joined(Who.seat(self, p.index), "the band"), 1.5)
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
		_show_center(Who.left(Who.seat(self, p.index)), 1.5, true, "" if SIMPLE_MODE else "\u0001")
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


func on_player_activity_changed(p) -> void:
	if p.active and is_local(p):
		_ensure_view(p)
	if seats.joined(p):
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
	if SIMPLE_MODE:
		drum_level = SongGen.drum_level_for(tour_pos)
		for p in players:
			if p.index > 0:
				p.level = 0
	song = SongGen.build(i, tour_pos, bars, SIMPLE_MODE)
	d_judged = PackedByteArray()
	d_judged.resize(song.d_t.size())
	_apply_drum_level()
	d_next = 0
	last_beat = -999
	last_pluck = -1
	sync_map.clear()
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


## Drum notes above the drummer's level are skipped (4) - not shown, never missed.
func _apply_drum_level() -> void:
	if song == null:
		return
	for i in d_judged.size():
		if d_judged[i] == 0 or d_judged[i] == 4:
			d_judged[i] = 4 if int(song.d_lvl[i]) > drum_level else 0


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
		if tour_pos + 1 < setlist.size():
			_prefetch(setlist[tour_pos + 1])
	elif synth_task < 0:
		synth_obj = song
		synth_task = WorkerThreadPool.add_task(Callable(song, "synth_loop"))


func _prefetch(i: int) -> void:
	if synth_task >= 0:
		return
	var s = SongGen.build(i, 1, 2, false)
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
	print("Music: synthesized the backing for '%s'" % str(synth_obj.title))
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


## The SETLIST: everyone picks their level, the drummer starts the show.
func _enter_menu() -> void:
	if SIMPLE_MODE:
		_start_practice()
		return
	state = "menu"
	state_t = 0.0
	setlist = SongGen.make_setlist(randi() % Seeded.SEED_MAX)
	tour_pos = 0
	score = 0
	tour_stars = 0
	tour_sync = 0
	tour_star_uses = 0
	star_meter = 0.0
	star_until = -1.0
	players[0].reset_tour()
	players[0].trig_block = true
	for p in players:
		if p.index > 0:
			p.menu_ready = false
			p.reset_tour()
	stage.hide_stars()
	net.event("stars", [-1])
	_load_song(setlist[0], song_bars)
	var names: PackedStringArray = []
	for s in setlist:
		names.append(SongGen.song_name(s))
	_show_center("TONIGHT'S SETLIST\n%s\n\nTV: LEFT / RIGHT picks EASY · NORMAL · ROCK, A = READY!\nVR drummer: hit a drum to pick your level, the CRASH starts the show" % \
		"  ·  ".join(names), 0.0, true, "SETLIST: hit a drum for your level\nCRASH = START!")
	sound("ready", -4.0, 1.0, true)
	print("Menu: setlist %s" % str(names))


## Simple mode: the PRACTICE moment before song 1 (see the top of this file).
func _start_practice() -> void:
	state = "practice"
	state_t = 0.0
	prac_d = 0
	prac_t = 0.0
	prac_first_done = -1.0
	setlist = SongGen.setlist(session_seed, daily_due())
	tour_pos = 0
	score = 0
	players[0].reset_tour()
	for p in players:
		if p.index > 0:
			p.prac_step = 0
			p.prac_t = 0.0
			p.reset_tour()
	stage.hide_stars()
	_load_song(setlist[0], mini(bars_cap, SIMPLE_BARS[0]))
	# TV: no headline (the stage's RHYTHM BAND sign is right there: no duplicate title); VR: the title.
	_show_center("", 2.5, true, "RHYTHM BAND!")
	sound("ready", -4.0, 1.0, true)
	print("Practice: drums %s, lanes %s, then setlist %s (%s), session seed %d" % [str(PRACTICE_PADS), str(PRACTICE_LANES), str(setlist),
		", ".join(setlist.map(func(c: int) -> String: return SongGen.song_name(c))), session_seed])


## Practice is over when everyone has done theirs, or a while after the first one finished.
func _check_practice() -> void:
	var all_done := prac_d >= PRACTICE_PADS.size()
	var any_done := all_done
	for g in active_guitarists():
		if int(g.prac_step) >= PRACTICE_LANES.size():
			any_done = true
		else:
			all_done = false
	if any_done and prac_first_done < 0.0:
		prac_first_done = state_t
	if state_t < 2.5:
		return
	var waited := state_t - prac_first_done if prac_first_done >= 0.0 else 0.0
	if (all_done and waited > 1.5) or (any_done and waited > PRACTICE_WAIT) or state_t > PRACTICE_MAX:
		print("Practice done (drums %d/%d) after %.1f s" % [prac_d, PRACTICE_PADS.size(), state_t])
		_start_song(0)


## The drummer hit the glowing practice drum: sparks, a rising chime, the next ball sets off.
func _practice_drum(pad: int) -> void:
	prac_d += 1
	cue_did(players[0], "pad%d" % pad)
	prac_t = 0.0
	_drum_fx(pad, 0, false)
	net.event("djudge", [pad, 0, false])
	inst.chime(0.9 + 0.15 * prac_d)
	if prac_d >= PRACTICE_PADS.size():
		inst.cheer(-4.0)
		net.event("cheer", [-4.0])
		burst(players[0].pads[pad].global_position + Vector3(0, 0.2, 0), Color(1.0, 0.85, 0.3), 30)
	print("Practice: the drummer hit drum %d (%d/%d)" % [pad, prac_d, PRACTICE_PADS.size()])


## Any machine: one of its own guitarists hit their waiting practice note.
func guitar_practice_hit(p, lane: int) -> void:
	if song != null:
		inst.pluck(song.lane_pitch_at(0.0, lane), -3.0)
	stage.strum(p.index, true)
	if int(p.prac_step) >= PRACTICE_LANES.size():
		inst.chime(1.4)
	if net.mode == "client":
		net.send_action("prac", [p.prac_step], p.index)


func _start_tour() -> void:
	tour_pos = 0
	_start_song(0)


func _start_song(pos: int) -> void:
	tour_pos = pos
	song_serial += 1
	if SIMPLE_MODE:
		# The songs keep coming: after the slow / middle / fast three, random ones (encores get faster).
		while setlist.size() <= pos:
			setlist.append(SongGen.code_at(session_seed, setlist.size(), false))
		_load_song(setlist[pos], mini(bars_cap, SIMPLE_BARS[mini(pos, SIMPLE_BARS.size() - 1)]))
	else:
		_load_song(setlist[clampi(pos, 0, setlist.size() - 1)], song_bars)
	state = "intro"
	state_t = 0.0
	song_t = -START_LEAD
	crowd = 0.5
	combo = 0
	best_combo = 0
	band_hits = 0
	band_misses = 0
	star_meter = 0.0
	star_until = -1.0
	star_uses = 0
	sync_count = 0
	players[0].reset_stats()
	stage.hide_stars()
	net.event("stars", [-1])
	var head := "SONG %d of %d: %s  (%d BPM)" % [pos + 1, SONGS_PER_TOUR, song.title, int(song.bpm)]
	if SIMPLE_MODE:
		_show_center("SONG %d!" % (pos + 1), INTRO_TIME, true, "SONG %d!" % (pos + 1))
	elif pos == 0:
		_show_center("RHYTHM BAND!\nPlay the song together and keep the crowd happy!\n" \
			+ "TV: press X / A / B (or D-pad left / down / right) when a ball reaches its ring\n" \
			+ "GOLD balls charge STAR POWER - then press Y (drummer: hit the CRASH)!\n" \
			+ "VR DRUMMER: swing a hand into each drum as its ball arrives\n\n" + head, FIRST_INTRO_TIME, true,
			"SONG 1: %s\nSwing into the drums as the balls land!" % song.title)
	else:
		_show_center(head + "\n" + ["Nice and easy!", "A bit faster…", "FULL SPEED - rock out!"][mini(pos, 2)], INTRO_TIME, true,
			"SONG %d: %s" % [pos + 1, song.title])
	sound("go", -6.0, 0.8, true)
	song_live = true
	if song.daily:
		_story("TODAY'S SONG!", "goldrecord", Color(1.0, 0.8, 0.2))
	_story("%s!" % song.title, str(SongGen.STYLE_PICS.get(song.style, "musicnote")), SongGen.STYLE_COLORS.get(song.style, Color(1.0, 0.7, 0.4)))
	print("Song %d started: %s (%s, level %d, seed %d%s), %d BPM, %d bars, %d guitar notes (easy %d), %d drum notes, drum level %s" % [pos + 1, song.title,
		song.style, song.level, song.seed_v, ", TODAY'S SONG" if song.daily else "", int(song.bpm), song.total_bars, song.g_t.size(), song.guitar_count(0), song.d_t.size(), LEVEL_NAMES[drum_level]])


## Beat-synced effects on every machine (lights, count-in sticks and numbers, star-power fireworks).
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
		if b == 0 and not SIMPLE_MODE:
			_show_center("Get ready…", 0.0, false, "Get ready…")
		elif b >= count_beats - 3:
			_show_center(str(count_beats - b), 0.4, false, str(count_beats - b))
	elif b == count_beats:
		_show_center("PLAY!", 0.5, false, "PLAY!")
	if star_active() and b % 4 == 0:
		stage.fireworks(1)


func multiplier() -> int:
	return 1 + mini(3, combo / 15)


func window(level: int) -> Vector2:
	return WINDOWS[clampi(level, 0, 2)]


func drum_travel_beats() -> float:
	return 4.0 if drum_level == 0 else 3.0


func star_active() -> bool:
	return state == "play" and song_t < star_until


func star_ready() -> bool:
	return star_meter >= 1.0 and not star_active()


func star_meter_value() -> float:
	if star_active() and song != null:
		return clampf((star_until - song_t) / (STAR_BEATS * float(song.spb)), 0.0, 1.0)
	return clampf(star_meter, 0.0, 1.0)


## Authority: one judged note (guitar or drum). q: 0 perfect, 1 good, 2 miss. src: player index,
## tn: the note's time (for IN SYNC), star: a gold note.
func _band_result(q: int, star: bool = false, src: int = -1, tn: float = -1.0) -> void:
	var n := 1 + active_guitarists().size()
	if q < 2:
		band_hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		var pts := (100 if q == 0 else 60) * multiplier()
		if star_active():
			pts *= 2
			crowd = minf(1.0, crowd + 0.01)
		score += pts
		crowd = minf(1.0, crowd + 0.035 / sqrt(float(n)) * (1.0 if q == 0 else 0.75))
		if star and not star_active() and star_meter < 1.0:
			star_meter = minf(1.0, star_meter + 1.0 / (8.0 + 4.0 * active_guitarists().size()))
			if star_meter >= 1.0:
				_show_center("STAR POWER READY!\nTV: press Y  ·  Drummer: hit the CRASH!", 2.5, true, "STAR POWER READY!\nHit the CRASH!")
				sound("ready", -2.0, 1.3, true)
		if src >= 0 and tn >= 0.0 and not SIMPLE_MODE:
			_sync_check(src, tn)
		_combo_fx()
	else:
		band_misses += 1
		combo = combo / 2  # kind: a miss halves the combo instead of wiping it
		crowd = maxf(0.0, crowd - 0.03 / sqrt(float(n)))


## Two or more players hitting the same beat: IN SYNC bonus (the drummer and the guitars together!).
func _sync_check(src: int, tn: float) -> void:
	var key := int(roundf(tn * 50.0))
	var mask: int = sync_map.get(key, 0)
	var bit := 1 << src
	if mask & bit:
		return
	mask |= bit
	sync_map[key] = mask
	var count := 0
	for k in MAX_PLAYERS:
		if mask & (1 << k):
			count += 1
	if count >= 2:
		sync_count += 1
		tour_sync += 1
		score += 25 * count
		_sync_fx(count)
		net.event("sync", [count])
	if sync_map.size() > 64:
		for k2 in sync_map.keys():
			if int(k2) < int(roundf((song_t - 2.0) * 50.0)):
				sync_map.erase(k2)


func _sync_fx(count: int) -> void:
	sound("sync", -10.0, 0.9 + 0.1 * count)
	for p in players:
		if p.index > 0 and is_local(p) and p.active:
			p.judge_text = "IN SYNC x%d!" % count
			p.judge_col = Color(0.5, 0.9, 1.0)
			p.judge_t = 0.8
	if players[0].vr or players[0].fake_vr:
		_vr_say("IN SYNC x%d!" % count, 0.7)


## Band combo milestones: pyro, fireworks and a cheer.
func _combo_fx() -> void:
	var c := combo
	var name := ""
	match c:
		10:
			name = "NICE!"
		25:
			name = "ON FIRE!"
		50:
			name = "ROCKSTARS!"
		100:
			name = "LEGENDARY!"
		_:
			if c > 100 and c % 50 == 0:
				name = "UNSTOPPABLE!"
	if name == "":
		return
	if not SIMPLE_MODE:
		_show_center("%d COMBO - %s" % [c, name], 1.2, true, "%d COMBO!  %s" % [c, name])
	_milestone_fx(c)
	net.event("milestone", [c])


func _milestone_fx(c: int) -> void:
	inst.cheer(-2.0)
	if c >= 25:
		stage.pyro()
		sound("boom", -6.0, 1.0)
	if c >= 50:
		stage.fireworks(3)
		sound("fw", -8.0, 1.0)
	burst(Vector3(0.0, 3.0, -1.5), PLAYER_COLORS[(c / 25) % PLAYER_COLORS.size()], 40, false)


## Y on a TV pad, or the drummer's CRASH: set off STAR POWER when it's full.
func request_star(p) -> void:
	if SIMPLE_MODE:
		return
	if net.mode == "client":
		net.send_action("star", [], p.index)
	else:
		_activate_star(p.index)


func _activate_star(who: int) -> void:
	if not star_ready() or state != "play" or song == null:
		return
	star_meter = 0.0
	star_until = song_t + STAR_BEATS * float(song.spb)
	star_uses += 1
	tour_star_uses += 1
	var by := "the DRUMMER" if who == 0 else "P%d" % (who + 1)
	_show_center("STAR POWER!  (%s)\nDouble points - the crowd goes wild!" % by, 2.0, true, "STAR POWER!\nDouble points!")
	_star_fx()
	net.event("star_on", [])
	print("STAR POWER by %s" % by)


func _star_fx() -> void:
	sound("star", -2.0, 1.0)
	inst.cheer(0.0)
	stage.fireworks(3)
	stage.pyro()
	if players[0].vr:
		players[0].hand_l.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.3, 0.0)
		players[0].hand_r.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.3, 0.0)


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
		_band_result(q, song.g_star[id] == 1, p.index, float(song.g_t[id]))


## Pressing a lane with no note near: a soft chord tone, no penalty (and the avatar strums).
func free_strum(p, lane: int) -> void:
	if song != null:
		inst.pluck(song.lane_pitch_at(maxf(0.0, song_t), lane), -12.0)
	stage.strum(p.index, false)
	if net.mode == "client":
		net.send_action("press", [lane], p.index)


## Authority (host / local): the drummer hit a drum. In the SETLIST menu the drums pick the level
## (hi-hat EASY, snare NORMAL, tom ROCK) and the CRASH starts the show.
func drum_hit(pad: int, speed: float) -> void:
	var vol := lerpf(-8.0, 0.0, clampf((speed - 0.4) / 2.0, 0.0, 1.0))
	inst.drum(pad, vol)
	players[0].flash_pad(pad)
	if state == "menu":
		_menu_drum(pad)
		net.event("drum", [pad, -1, -1, vol])
		return
	if state == "practice":
		if prac_d < PRACTICE_PADS.size() and pad == PRACTICE_PADS[prac_d] and prac_t > 0.3:
			_practice_drum(pad)
		net.event("drum", [pad, -1, -1, vol])
		return
	var id := -1
	var q := -1
	if state == "play" and song != null:
		var win := window(drum_level)
		var bdt := 99.0
		var i := maxi(0, d_next - 4)
		var n: int = song.d_t.size()
		while i < n:
			var t: float = song.d_t[i]
			if t > song_t + win.y:
				break
			if d_judged[i] == 0 and int(song.d_pad[i]) == pad:
				var dt := absf(t - song_t)
				if dt <= win.y and dt < bdt:
					bdt = dt
					id = i
			i += 1
		if id >= 0:
			q = 0 if bdt <= win.x else 1
			_drum_result(id, q)
		if pad == 3 and star_ready():
			_activate_star(0)
	net.event("drum", [pad, id, q, vol])


func _menu_drum(pad: int) -> void:
	if state_t < 0.6:
		return
	if pad < 3:
		if drum_level != pad:
			drum_level = pad
			_apply_drum_level()
			inst.chime(0.8 + 0.25 * pad)
			_vr_say("Drums: %s" % LEVEL_NAMES[pad], 1.5)
			print("Menu: drummer picks %s" % LEVEL_NAMES[pad])
	else:
		print("Menu: the drummer starts the show")
		_start_tour()


func _drum_result(id: int, q: int) -> void:
	d_judged[id] = q + 1
	var d = players[0]
	var star: bool = song.d_star[id] == 1
	d.record(q, star)
	_band_result(q, star, 0, float(song.d_t[id]))
	var pad: int = song.d_pad[id]
	if q < 2:
		cue_did(d, "pad%d" % pad)
	_drum_fx(pad, q, star)
	net.event("djudge", [pad, q, star])


## Judgement at a drum: sparks (VR - no text right in front of your face) or a popup (TV / flat).
func _drum_fx(pad: int, q: int, star: bool) -> void:
	var d = players[0]
	var pos: Vector3 = d.pads[pad].global_position + Vector3(0.0, 0.12, 0.0)
	if d.vr or SIMPLE_MODE:
		if q < 2:
			_sparks(d.pads[pad].global_position + Vector3(0, 0.04, 0), Color(1.0, 0.82, 0.25) if star or q == 0 else Color(0.5, 1.0, 0.6))
		return
	if q == 0:
		popup(pos, "STAR!" if star else "PERFECT!", Color(1.0, 0.9, 0.3), 0.8)
	elif q == 1:
		popup(pos, "GOOD", Color(0.5, 1.0, 0.6), 0.7)
	else:
		popup(pos, "MISS", Color(1.0, 0.45, 0.45), 0.6)


func _sparks(pos: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -3.0, 0)
	p.mesh = sphere_mesh(0.008)
	p.material_override = make_material(col, 2.0)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func _song_done() -> void:
	state = "results"
	state_t = 0.0
	var acc := float(band_hits) / maxf(1.0, float(band_hits + band_misses))
	_new_fan()
	_run_line("song")
	if SIMPLE_MODE:
		# No stars, no numbers: everyone cheers.
		_show_center("HOORAY!", 3.0, true, "HOORAY!")
		inst.cheer(0.0)
		net.event("cheer", [0.0])
		burst(Vector3(-2.0, 2.5, -1.5), Color(1.0, 0.85, 0.2), 40)
		burst(Vector3(2.0, 2.5, -1.5), Color(0.4, 0.8, 1.0), 40)
		_milestone_fx(50 if acc >= 0.5 else 25)
		net.event("milestone", [50 if acc >= 0.5 else 25])
		print("Song %d complete: '%s' hits %d, misses %d (%d%%), best combo %d" % [tour_pos + 1, song.title, band_hits, band_misses,
			int(acc * 100.0), best_combo])
		return
	last_stars = clampi(1 + int(acc * 4.0 + 0.15), 1, 5)
	tour_stars += last_stars
	var d = players[0]
	var lines := "Drums (%s) %d%%" % [LEVEL_NAMES[drum_level], int(100.0 * d.hits / maxf(1.0, float(d.hits + d.misses)))]
	for p in active_guitarists():
		var tot: int = p.hits + p.misses
		lines += "   P%d (%s) %d%%" % [p.index + 1, LEVEL_NAMES[p.level], int(100.0 * p.hits / maxf(1.0, float(tot)))]
	var extras := ""
	if sync_count > 0:
		extras += "IN SYNC x%d" % sync_count
	if star_uses > 0:
		extras += ("  ·  " if extras != "" else "") + "STAR POWER x%d" % star_uses
	var last := tour_pos + 1 >= SONGS_PER_TOUR
	var praise: String = ["Good try!", "Nice!", "Great job!", "Awesome!", "SUPERSTARS!"][last_stars - 1]
	_show_center("SONG COMPLETE: %s\n%d STARS - %s\nHits %d%%  ·  Best combo %d  ·  Score %d\n%s\n%s\n\n%s" % [song.title, last_stars,
		praise, int(acc * 100.0), best_combo, score, lines, extras,
		"A / Enter (VR: trigger): the tour results" if last else "A / Enter (VR: trigger): next song"], 0.0, true,
		"%d STARS - %s\nTrigger: %s" % [last_stars, praise, "tour results" if last else "next song"])
	stage.show_stars(last_stars)
	net.event("stars", [last_stars])
	inst.cheer(0.0)
	net.event("cheer", [0.0])
	burst(Vector3(-2.0, 2.5, -1.5), Color(1.0, 0.85, 0.2), 40)
	burst(Vector3(2.0, 2.5, -1.5), Color(0.4, 0.8, 1.0), 40)
	if last_stars >= 4:
		_milestone_fx(50)
		net.event("milestone", [50])
	if score > best:
		best = score
		_save_best(best)
	print("Song %d complete: %d stars (hits %d, misses %d, best combo %d, score %d, sync %d, star power %d) %s" % [tour_pos + 1, last_stars,
		band_hits, band_misses, best_combo, score, sync_count, star_uses, lines])


func _tour_done() -> void:
	state = "tour"
	state_t = 0.0
	stage.hide_stars()
	net.event("stars", [-1])
	var awards := _awards()
	set_meta("awards", awards)
	_show_center("TOUR COMPLETE!\n%d of %d stars  ·  Score %d  ·  Best %d\n\n%s\n\nA / Enter (VR: trigger): a new setlist" % [
		tour_stars, SONGS_PER_TOUR * 5, score, best, awards], 0.0, true, "TOUR COMPLETE!\n%d of %d stars" % [tour_stars, SONGS_PER_TOUR * 5])
	sound("tour", -2.0, 1.0, true)
	inst.cheer(0.0)
	net.event("cheer", [0.0])
	net.event("milestone", [100])
	_milestone_fx(100)
	for k in 3:
		burst(Vector3(-3.0 + k * 3.0, 2.0, -1.5), PLAYER_COLORS[k + 1], 40)
	print("Tour complete: %d stars, score %d | awards: %s" % [tour_stars, score, awards.replace("\n", " | ")])


## Fun awards from the whole tour (a few lines, kid-friendly).
func _awards() -> String:
	var out: PackedStringArray = []
	var all: Array = [players[0]]
	all.append_array(active_guitarists())
	var steady = null
	var steady_acc := 0.0
	var perfect = null
	var streaky = null
	var starry = null
	for p in all:
		var t: Dictionary = p.tour
		var tot: int = int(t["hits"]) + int(t["misses"])
		if tot >= 8:
			var acc := float(t["hits"]) / float(tot)
			if steady == null or acc > steady_acc:
				steady = p
				steady_acc = acc
		if int(t["perfects"]) > 0 and (perfect == null or int(t["perfects"]) > int(perfect.tour["perfects"])):
			perfect = p
		if int(t["best_streak"]) >= 8 and (streaky == null or int(t["best_streak"]) > int(streaky.tour["best_streak"])):
			streaky = p
		if int(t["stars"]) > 0 and (starry == null or int(t["stars"]) > int(starry.tour["stars"])):
			starry = p
	if steady != null:
		out.append("STEADY HANDS: %s (%d%%)" % [_who(steady), int(steady_acc * 100.0)])
	if perfect != null:
		out.append("PERFECT MACHINE: %s (%d perfects)" % [_who(perfect), int(perfect.tour["perfects"])])
	if streaky != null:
		out.append("LONGEST STREAK: %s (%d in a row)" % [_who(streaky), int(streaky.tour["best_streak"])])
	if starry != null:
		out.append("STAR CATCHER: %s (%d gold notes)" % [_who(starry), int(starry.tour["stars"])])
	if tour_sync > 0:
		out.append("BAND IN SYNC: %d beats hit together!" % tour_sync)
	for p in active_guitarists():
		if p.level == 2:
			out.append("BRAVE ROCKER: %s played on ROCK" % _who(p))
			break
	if out.is_empty():
		out.append("THE WHOLE BAND: what a show!")
	return "\n".join(out.slice(0, 5))


func _who(p) -> String:
	return "the DRUMMER" if p.index == 0 else "P%d" % (p.index + 1)


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
	prac_t += delta
	if state == "play":
		song_t += delta
	_sync_audio(delta)
	_beat_fx()
	var beat_pos: float = song_t / float(song.spb) if song != null and state == "play" else state_t * 1.6
	stage.update(delta, beat_pos, crowd, state == "play", 1.0 if star_active() else 0.0)
	fan_club.update(delta, beat_pos, crowd if state == "play" else 0.35, song != null and song.daily)
	_update_story(delta)
	_update_vr_text(delta)
	if net.mode == "client":
		_client_update(delta, cont_edge)
		return
	_update_lost_pads(delta)
	match state:
		"wait":
			var vs: bool = players[0].vr and players[0].vr_trigger()
			if vs and not vr_start_was:
				_enter_menu()
			vr_start_was = vs
		"practice":
			_check_practice()
		"menu":
			var gs := active_guitarists()
			var all_ready := not gs.is_empty()
			for g in gs:
				if not g.menu_ready:
					all_ready = false
			var vs2: bool = players[0].vr and players[0].vr_trigger()
			if (all_ready and state_t > 2.0 and not players[0].vr) or state_t > MENU_AUTO or (vs2 and not vr_start_was and state_t > 1.0):
				_start_tour()
			vr_start_was = vs2
		"intro":
			var dur := FIRST_INTRO_TIME if tour_pos == 0 and not SIMPLE_MODE else INTRO_TIME
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
			if (state_t > 1.5 and cont_edge) or state_t > (CELEBRATE_TIME if SIMPLE_MODE else RESULTS_AUTO):
				_on_continue(true)
		"tour":
			if state_t > 1.5 and cont_edge:
				_enter_menu()


func _check_drum_misses() -> void:
	var n: int = song.d_t.size()
	var win := window(drum_level)
	while d_next < n and float(song.d_t[d_next]) < song_t - win.y - 0.02:
		if d_judged[d_next] == 0:
			_drum_result(d_next, 2)
			net.event("drum", [-1, d_next, 2, 0.0])
		d_next += 1


func _client_update(delta: float, cont_edge: bool) -> void:
	seats.sync()
	seats.request_joins(delta)
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
	if players.size() > 0 and players[0].vr and players[0].action_pressed() and not SIMPLE_MODE:
		return true  # (simple mode: the trigger picks up maracas; the songs move on by themselves)
	return false


## Bot hook: same as pressing A on the end screens.
func debug_continue() -> void:
	if net.mode == "client":
		net.send_action("continue", [])
	else:
		_on_continue(false)


## Bot hook: the drummer starts the show from the SETLIST menu.
func debug_start() -> void:
	if net.mode != "client" and state == "menu":
		_start_tour()


func _on_continue(_auto: bool) -> void:
	if state == "results" and state_t > 1.0:
		if tour_pos + 1 >= SONGS_PER_TOUR and not SIMPLE_MODE:
			_tour_done()
		else:
			_start_song(tour_pos + 1)
	elif state == "tour" and state_t > 1.0:
		_enter_menu()


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://rhythm_band_best.cfg")
	return int(cfg.get_value("best", "score", 0))


func _save_best(s: int) -> void:
	save.data.best = maxi(int(save.data.best), s)
	save.mark_dirty()


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ------------------------------------

func on_client_joined() -> void:
	# Each machine asks for its own guitarists ("join"); the first one opens the setlist menu.
	# (no "they joined" line: each seat's join says WHO, core/who.gd)
	if state == "wait":
		_enter_menu()


## Host: a machine joined: it gets the setlist (only it).
func on_machine_joined(peer: int, _kind: String) -> void:
	if state != "wait":
		net.event_to(peer, "setlist", [setlist])


## Host: one machine left: only its guitarists leave (and their spots become free).
func on_machine_left(peer: int) -> void:
	seats.machine_left(peer)


## A machine's guitarist leaves the stage (its machine left).
func _seat_gone(p) -> void:
	if p.active:
		p.set_active(false)
		stage.set_avatar_visible(p.index, false)
		on_player_activity_changed(p)


## Host: the LAST machine left (multi_machine games get this only then).
func on_client_left() -> void:
	seats.all_left()
	if not SIMPLE_MODE:
		_show_center(Who.left(net.last_left_name) + " - keep drumming!", 2.0)


## A TV player changed their level / readiness in the SETLIST menu (local: nothing to send).
func player_level_changed(p) -> void:
	if net.mode == "client":
		net.send_action("level", [p.level], p.index)


func player_ready_changed(p) -> void:
	if net.mode == "client":
		net.send_action("ready", [p.menu_ready], p.index)
	if p.menu_ready:
		sound("ready", -8.0, 1.0 + 0.05 * p.index)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	index = seats.host_action(action, args, index)  # many machines: who drives which seat (core/classic_seats.gd)
	if index < 0:
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
				_show_center(Who.left(Who.seat(self, index)), 1.5)
		"continue":
			_on_continue(false)
		"level":
			if args.size() >= 1:
				p.level = clampi(int(args[0]), 0, 2)
		"ready":
			if args.size() >= 1:
				p.menu_ready = bool(args[0])
		"star":
			_activate_star(index)
		"prac":
			if args.size() >= 1:
				p.prac_step = clampi(int(args[0]), 0, PRACTICE_LANES.size())
				stage.strum(index, true)
		"hit", "miss":
			if args.size() < 2 or song == null or state != "play":
				return
			var id: int = int(args[0])
			var q: int = clampi(int(args[1]), 0, 2)
			if id < 0 or id >= song.g_t.size():
				return
			var star: bool = song.g_star[id] == 1
			p.record(q, star)
			if q < 2:
				if id != last_pluck:
					last_pluck = id
					inst.pluck(song.g_pitch[id], -4.0)
				stage.strum(index, true)
			_band_result(q, star, index, float(song.g_t[id]))
		"press":
			stage.strum(index, false)
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, Who.paused_by(net.machine_name_of(net.sender_peer())))
			get_tree().paused = paused
			if not paused:
				players[0].trig_block = true


func _set_pause_banner(paused: bool, who: String) -> void:
	if SIMPLE_MODE:
		who = ""  # no explaining sentence: just PAUSED
	var title := ("PAUSED\n" + who) if who != "" else "PAUSED"
	_show_center(title if paused else "", 0.0, false, title if paused else "")
	if vr_center != null and paused:
		VrText.snap(vr_center)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	players[0].trig_block = true  # the trigger that resumed must not start or skip anything
	cont_was = true
	vr_start_was = true
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHold the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps: Array = []
	for i in range(1, players.size()):
		var p = players[i]
		ps.append([p.active, p.streak, p.hits, p.misses, p.level, p.menu_ready])
	var d = players[0]
	return [state, song_serial, song_idx, song_bars, song_t, crowd, combo, score, best, state_t, ps,
		d.rig_transform(), d.kit_s, d.head_transform(), d.tip(0), d.tip(1), last_stars, tour_stars,
		tour_pos, setlist, drum_level, star_meter, star_until, prac_d,
		d.props.net_state() if d.props != null else [-1]]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 23:
		return
	var serial: int = s[1]
	var host_t: float = s[4]
	var new_state: String = s[0]
	tour_pos = s[18]
	var sl: Array = s[19]
	setlist.clear()
	for v in sl:
		setlist.append(int(v))
	var dl: int = s[20]
	if serial != song_serial or song == null:
		song_serial = serial
		song_t = host_t
		state = new_state
		drum_level = dl
		_load_song(int(s[2]), int(s[3]))
	if dl != drum_level:
		drum_level = dl
		_apply_drum_level()
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
	star_meter = s[21]
	star_until = s[22]
	if s.size() >= 25:
		if int(s[23]) != prac_d:
			prac_d = int(s[23])
			prac_t = 0.0
		if d.props != null:
			d.props.apply_net(s[24])


func apply_event(kind: String, args: Array) -> void:
	if seats.handle_event(kind, args):
		return
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false, str(args[2]) if args.size() > 2 else "\u0001")
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
		"djudge":
			_drum_fx(int(args[0]), int(args[1]), bool(args[2]))
		"sync":
			_sync_fx(int(args[0]))
		"milestone":
			_milestone_fx(int(args[0]))
		"star_on":
			_star_fx()
		"setlist":
			pass
		"story":
			_story(str(args[0]), str(args[1]), args[2], false)
		"prop":
			if players[0].props != null:
				players[0].props.react(int(args[0]))
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
	center_label = HudKit.split_center(_make_label(44))  # a copy in each split view, never across the line
	layer.add_child(center_label)
	UiKit.pin(center_label, Control.PRESET_FULL_RECT, false)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(18)
	layer.add_child(help_label)
	UiKit.pin(help_label, Control.PRESET_BOTTOM_WIDE, false)
	help_label.offset_top = -30
	help_label.offset_bottom = -6
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.visible = not SIMPLE_MODE  # simple mode: the rings and arrows show the buttons
	help_label.text = "Guitar: X / A / B or D-pad (keyboard: arrows) · STAR POWER: Y · more players: press A on another controller · Start / Esc: menu"


## Simple mode picture cues: a player has done `key` once more (a guitar lane "lane0".."lane2", a drum
## "pad0".."pad3"); highway.gd stops showing that cue once it is done twice.
func cue_did(p, key: String) -> void:
	var done: Dictionary = p.get_meta("cue_done", {})
	done[key] = int(done.get(key, 0)) + 1
	p.set_meta("cue_done", done)


func cue_learned(p, key: String) -> bool:
	var done: Dictionary = p.get_meta("cue_done", {})
	return int(done.get(key, 0)) >= 2


## Simple mode: the lanes on the TV highway right now (song 1: just the outer two).
func lanes_now() -> Array[int]:
	if SIMPLE_MODE and tour_pos == 0:
		return [0, 2]
	return [0, 1, 2]


## Authority (host / local): the drummer touched a stage toy (props.gd).
func prop_touched(k: int) -> void:
	players[0].props.react(k)
	net.event("prop", [k])


## TV banner; vr: the short version for the VR drummer ("\u0001" = the first two lines).
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
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.4)
	if vr == "\u0001":
		var lines := text.split("\n")
		vr = "\n".join(lines.slice(0, 2)) if lines.size() > 0 else ""
	_vr_say(vr, duration if duration > 0.0 else 9999.0)


func _vr_say(text: String, duration: float) -> void:
	vr_msg = text
	vr_msg_t = duration


## The few words on the VR drummer's dashboard (far ahead, between the lanes): combo, level and a hint.
func drummer_status(d) -> String:
	var line := "COMBO %d" % combo
	if multiplier() > 1:
		line += "  x%d" % multiplier()
	if star_active():
		line = "STAR POWER!  " + line
	match state:
		"wait":
			return "Hit the drums!"
		"menu":
			return "Drums: %s" % LEVEL_NAMES[drum_level]
		"play":
			if song != null:
				var first: float = song.d_t[0] if song.d_t.size() > 0 else 0.0
				if star_ready():
					return "STAR POWER READY!\nHit the CRASH!"
				if song_t < first + 1.0:
					return line + "\nSwing into the drums!"
				if d.miss_run >= 4:
					return line + "\nHit the drum the ball flies to!"
				if d.swings == 0 and song_t > first + 3.0:
					return line + "\nSwing your hands down!"
				return line + ("\n%d IN A ROW!" % d.streak if d.streak >= 8 else "")
		"results", "tour":
			return "Trigger: carry on"
	return line


## Short messages for the VR drummer, floating above the dashboard and between the lanes (normal
## depth test: nothing nearer ever sits in front of them).
func _update_vr_text(delta: float) -> void:
	if help_label.modulate.a > 0.0 and tour_pos >= 1:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - delta * 0.5)
	vr_msg_t -= delta
	if players.is_empty() or not players[0].vr:
		return
	var cam: XRCamera3D = players[0].xr_camera
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 44
		vr_center.outline_size = 26
		vr_center.pixel_size = 0.0022
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 340.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_center)
	var alpha := clampf(vr_msg_t / 0.4, 0.0, 1.0)
	vr_center.text = vr_msg
	vr_center.modulate.a = alpha
	vr_center.outline_modulate = Color(0, 0, 0, alpha)
	VrText.follow(vr_center, cam, self, 0.34, 1.8)  # above the dashboard, between the lanes


# --- Story, the fan club and telemetry (songgen.gd, fans.gd) ------------------------------------

## Host / local: TODAY'S SONG is still to play today.
func daily_due() -> bool:
	return save != null and String(save.data.daily) != Seeded.today()


## Host / local: a new play-day grows the fans; send the fan club to every machine; Doodle says hello.
func _start_fan_club() -> void:
	var grew := false
	if String(save.data.last_day) != Seeded.today():
		var days := int(save.data.days)
		save.data.days = days + 1
		save.data.last_day = Seeded.today()
		for e in save.data.fans:
			if SongGen.fan_stage(int(e[1]), days + 1) > SongGen.fan_stage(int(e[1]), days):
				grew = true
	save.data.sessions = int(save.data.sessions) + 1
	save.mark_dirty()
	_send_fans()
	var fans: Array = save.data.fans
	if int(save.data.songs) == 0:
		_story("Let's make a band!", "frog", Color(1.0, 0.4, 0.6))
	else:
		_story("Let's play!", "frog", Color(1.0, 0.4, 0.6))
	if grew and not fans.is_empty():
		_story("Our fans grew!", SongGen.FAN_KINDS[int((fans[-1] as Array)[0]) % SongGen.FAN_KINDS.size()], Color(0.5, 0.85, 1.0))
	if daily_due():
		_story("A gold song today!", "goldrecord", Color(1.0, 0.8, 0.2))
	print("Rhythm Band fan club: %d fans (%d in all), %d songs played, day %d, today's song %s, session seed %d" % [fans.size(),
		int(save.data.fans_total), int(save.data.songs), int(save.data.days), "due" if daily_due() else "done", session_seed])


func _send_fans() -> void:
	net.state_set("days", int(save.data.days))
	net.state_set("fans", (save.data.fans as Array).duplicate(true))


## Host / local: a finished song brings a new fan (golden for TODAY'S SONG).
func _new_fan() -> void:
	if song == null or save == null:
		return
	var total := int(save.data.fans_total)
	var kind := SongGen.fan_kind(song.code, total)
	var list: Array = save.data.fans
	list.append([kind, int(save.data.days), bool(song.daily)])
	while list.size() > SongGen.FAN_KEEP:
		list.pop_front()
	save.data.fans_total = total + 1
	save.data.songs = int(save.data.songs) + 1
	if song.daily:
		save.data.daily = Seeded.today()
	save.save_now()
	_send_fans()
	fan_club.cheer()
	songs_played += 1
	var pic: String = SongGen.FAN_KINDS[kind]
	if song.daily:
		_story("A gold fan!", pic, Color(1.0, 0.8, 0.2))
	else:
		_story("A new fan!", pic, Color(0.6, 0.9, 1.0))
	if (total + 1) % 10 == 0:
		_story("%d fans!" % (total + 1), "fanclub", Color(1.0, 0.5, 0.8))


## Every machine: the fan club follows the host's replicated state.
func _on_state_changed(key: String, _value: Variant) -> void:
	if key == "fans" or key == "days":
		fan_club.set_fans(net.state_get("fans", []), int(net.state_get("days", 0)))


## Host / local: one RUN line per song (end = "song") or when the game closes mid-song (end = "quit").
func _run_line(end: String) -> void:
	if not song_live or song == null or net == null or net.mode == "client":
		return
	song_live = false
	var d = players[0]
	var gh := 0
	var gm := 0
	for p in active_guitarists():
		gh += int(p.hits)
		gm += int(p.misses)
	Telemetry.run(SongGen.GAME_ID, {"end": end, "pos": tour_pos + 1, "song": song.title, "code": song.code, "seed": song.seed_v,
		"level": song.level, "daily": song.daily, "style": song.style, "bpm": int(song.bpm), "bars": song.bars,
		"secs": snappedf(maxf(song_t, 0.0), 0.1), "length": snappedf(song.length, 0.1), "hits": band_hits, "misses": band_misses,
		"best_combo": best_combo, "drum_hits": int(d.hits), "drum_misses": int(d.misses), "drum_level": drum_level,
		"guitar_hits": gh, "guitar_misses": gm, "guitarists": active_guitarists().size(), "vr": bool(d.vr),
		"mode": str(net.mode), "fans": (save.data.fans as Array).size(), "fans_total": int(save.data.fans_total),
		"songs": int(save.data.songs), "days": int(save.data.days), "session_songs": songs_played})


## Doodle says something (host / local: every machine sees it; beats wait their turn).
func _story(line: String, pic: String, color: Color, broadcast: bool = true) -> void:
	if broadcast and net != null and net.mode == "host":
		net.event("story", [line, pic, color])
	story_queue.append([line, pic, color])


func _update_story(delta: float) -> void:
	story_t -= delta
	if story_t > 0.0 or story_queue.is_empty():
		return
	var b: Array = story_queue.pop_front()
	story_t = 2.6
	story_shown.append(str(b[1]))
	var opts := {"who": "DOODLE", "line": b[0], "pic": b[1], "color": b[2], "duration": 2.5}
	var huds: Array = []
	for p in players:
		if p.active and p.has_meta("view") and p.hud != null and is_instance_valid(p.hud):
			huds.append(p.hud)
	StoryCard.show(huds, opts)
	var d = players[0]
	if d.vr and d.xr_camera != null:
		StoryCard.show_vr(self, d.xr_camera, opts)
