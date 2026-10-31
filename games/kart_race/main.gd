extends Node3D
## KART RACE - friendly kart racing for the whole living room.
## The VR player (players[0]) sits in a kart and drives it with a steering wheel held in both hands
## (right trigger = go, A = item / boost). TV players (1-6) drive their own karts in split screen
## chase cams. Five themed tracks (meadow, candy, dino desert, moonlight, snowy peaks) with ramps,
## boost arrows, item boxes, cheering crowds and start lights. GRAND PRIX: cups of 3 races, points
## for every place, trophies and fun awards at the end. Items are all harmless: banana slip, bubble
## shield, speed mushroom, triple mushroom, rainbow star and the silly honk (wobbles karts nearby).
## Drift round bends for sparks and a mini-turbo; press go on the last red light for a rocket start.
## Rubber-band catch-up keeps everyone close; bumps never wreck. CPU buddies fill the grid up to
## 4 karts. Modes, networking and drop-in join follow docs/GAME_DEV_GUIDE.md and games/marble_maze.
##
## SIMPLE_MODE (the family found the games too complicated and too wordy): just race round a colourful
## track. Before the first race a PRACTICE moment: three glowing rings on the road, one at a time
## (drive through it, it pops, the next one appears); in VR ghost mittens turn the wheel to show how.
## Then 3-2-1 GO, 2 laps, and a finish party (trophies over the top three, confetti, cheering). The
## next race starts by itself on the next track. Race 1 is just driving (ramps, jumps, boost arrows);
## from race 2 the ? boxes come out and give an instant ZOOM (no button); from race 3 some give a
## rainbow STAR. Off: drifting / mini-turbos, the boost meter, rocket starts, held items (bananas,
## shields, honks, triples), cups, points, awards, results tables, the minimap and every how-to text.
## Text: VR gets one short headline at a time (3-2-1 GO!, LAP 2, FINISH!); TV views show place + lap.
## No how-to words at all: the TV views show picture cues (a glowing pad button + an icon, CUES: A + up
## arrow = go, swaying left/right arrows = steer, a big red arrow = wrong way, turn this way) that fade
## after the kid has done the move twice; the VR wheel gets two shared Cannon Cove ghost hands that turn
## it and squeeze the trigger, and a glowing arrow over the wheel when going the wrong way.
##
## THE GRAND TOUR (story.gd, trackgen.gd): every track is generated from a seed (the host sends a few numbers,
## each machine builds the same track). The session starts on TODAY'S TRACK (the same all day, with a see-
## through GHOST of the day's best run); then BOLT the robot's tour: six places x three new tracks, each place's
## CHAMP races in CPU slot 0 wearing the hat you win by finishing the place; won hats are worn by the drivers
## (saved). Split lanes round flower-bed islands have a shorter shortcut lane with a boost arrow. Picture story
## cards (TV + VR), a row of place pictures on the results, and one RUN telemetry line per race.

const VrText := preload("res://core/vr_text.gd")
const Who := preload("res://core/who.gd")  # who joined / left (names, not "TV player")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const ClassicSeats := preload("res://core/classic_seats.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const TrackScript := preload("res://games/kart_race/track.gd")
const KartScript := preload("res://games/kart_race/kart.gd")
const CockpitScript := preload("res://games/kart_race/cockpit.gd")
const JoinListenerScript := preload("res://games/kart_race/join_listener.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const TrackGen := preload("res://games/kart_race/trackgen.gd")
const Story := preload("res://games/kart_race/story.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Telemetry := preload("res://core/telemetry.gd")
const SaveScript := preload("res://core/save.gd")
const Cups := preload("res://games/kart_race/cups.gd")
const Items := preload("res://games/kart_race/items.gd")
const PitScript := preload("res://games/kart_race/pit.gd")
const Shelf := preload("res://games/kart_race/shelf.gd")

## Simple mode picture cues on the TV views (no words): [pad button, icons, icon colour].
## The "go" button follows the player's controls (A on a pad, W / up on a keyboard), see _cue_button.
const CUES := {
	"go": ["A", ["arrow_up"], Color(0.45, 1.0, 0.5)],
	"steer": ["", ["arrow_left", "arrow_right"], Color(1.0, 0.92, 0.45)],
	"wrong_l": ["", ["arrow_left"], Color(1.0, 0.35, 0.3)],
	"wrong_r": ["", ["arrow_right"], Color(1.0, 0.35, 0.3)],
	"wrong_go": ["A", ["arrow_up"], Color(1.0, 0.35, 0.3)],
}

## Everything cut for the simple game is behind this flag (false = the full Grand Prix game).
const SIMPLE_MODE := true
const SIMPLE_LAPS := 2
const PRACTICE_GATES: Array[float] = [22.0, 44.0, 66.0]  # metres past the start line
const PRACTICE_MAX := 75.0  # seconds: the race starts anyway
const SIMPLE_NEXT := 9.0  # seconds of finish party before the next race starts by itself
const MAX_PLAYERS := 7  # VR player + 6 TV karts
const MAX_LOCAL_VIEWS := 6
## Any number of TV machines (TV, Steam Decks) may join, and a flat host (no VR) works (docs/MULTI_MACHINE.md).
var multi_machine := true
## Which machine drives which seat (core/net.gd checks it too).
var seats: ClassicSeats
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
const STAR_TIME := 5.0
const HONK_RANGE := 16.0
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.75, 0.2), Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0),
	Color(0.35, 0.9, 0.35), Color(0.85, 0.4, 1.0), Color(1.0, 0.55, 0.15), Color(0.3, 0.95, 0.9)]
const CPU_NAMES: Array[String] = ["BUNNY", "DINO", "ROBO"]
const CPU_COLORS: Array[Color] = [Color(1.0, 0.7, 0.85), Color(0.55, 0.8, 0.3), Color(0.7, 0.75, 0.85)]
const ITEM_NAMES := {"banana": "BANANA", "shield": "BUBBLE SHIELD", "mushroom": "SPEED MUSHROOM",
	"triple": "TRIPLE MUSHROOM", "star": "RAINBOW STAR", "honk": "SILLY HONK"}
const CUPS := [
	{"name": "SUNFLOWER CUP", "tracks": [0, 1, 2]},
	{"name": "SNOWFLAKE CUP", "tracks": [4, 3, 1]},
	{"name": "RAINBOW CUP", "tracks": [2, 4, 0]},
	{"name": "STARLIGHT CUP", "tracks": [3, 0, 4]},
]
const POINTS: Array[int] = [10, 8, 6, 5, 4, 3, 2, 1, 1, 1]
const TROPHY_COLORS: Array[Color] = [Color(1.0, 0.82, 0.2), Color(0.85, 0.88, 0.95), Color(0.85, 0.5, 0.25)]
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
	"honk": [0.45, 330.0, 310.0, 0.4, "square", 0.05],
	"star": [0.9, 523.0, 1568.0, 0.3, "square", 0.0],
	"spark": [0.12, 1300.0, 1700.0, 0.16, "square", 0.2],
	"turbo": [0.45, 260.0, 1300.0, 0.32, "saw", 0.35],
	"rocket": [0.7, 180.0, 1500.0, 0.35, "saw", 0.3],
	"cheer": [1.3, 700.0, 500.0, 0.22, "sine", 0.95],
	"trophy": [1.4, 523.0, 2093.0, 0.4, "tri", 0.0],
	"wobble": [0.5, 600.0, 300.0, 0.3, "sine", 0.0],
	"squelch": [0.35, 220.0, 120.0, 0.3, "sine", 0.5],
	"tinkle": [0.4, 1600.0, 2400.0, 0.18, "tri", 0.1],
	"boing": [0.5, 300.0, 900.0, 0.3, "sine", 0.0],
	"bonk": [0.18, 160.0, 90.0, 0.4, "square", 0.4],
	"pick": [0.3, 700.0, 1400.0, 0.3, "tri", 0.0],
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
var cup_i := 0
var cup_race := 0
var cup_pts: Array[int] = []  # per kart (same order as karts)
var lights := 0
var trophy_nodes: Array[Node3D] = []
var trophy_karts: Array[int] = []
var map_rect := Rect2()
var map_track := -1
var tips_shown := {}
var vr_results := ""
var practice_gate := -1  # simple mode: index of the glowing practice ring (-1: none)
var practice_t := 0.0
var gate_node: Node3D
var gate_mat: StandardMaterial3D
var gate_shown := -2
var gate_track := -1
var items_given := {}  # simple mode: which instant box effects happened (for the bot)
# The Grand Tour story (story.gd): generated tracks, champs, hats, today's track and its ghost.
var save: Node  # host / local only (core/save.gd)
var track_desc: Array = []  # story.gd description of the generated track (empty: a hand-made track)
var hats_won := 0
var race_logged := false  # telemetry written for this race
var ghost_rec: Array = []  # today's track: the best human's path this race (5 a second)
var ghost_rec_t := 0.0
var ghost_path: Array = []  # the ghost to race (today's best), [Vector3 ...] 5 a second
var ghost_node: Node3D
var story_count := 0  # story cards shown (bot)
var bolt_hello := false  # host: Bolt said hello this session (the first TODAY'S TRACK card)
const BOLT_COLOR := "8cb4ff"  # Bolt, the friendly robot who builds the tracks (his picture: story_pictures.gd boltbot)
var tour_strips: Array = []  # results: a row of place pictures on each TV view
# Bolt's cups (cups.gd), the pit stop (pit.gd), items (items.gd), Bolt's trophy shelf (shelf.gd), the best-lap ghost.
const TRIAL_LAPS := 3
var speed_mode := "gentle"  # cups.gd MODES: gentle / zoom / trial (synced in the snapshot)
var base_laps := SIMPLE_LAPS  # laps of a normal race (bots shorten it); a time trial has one more
var series := {}  # host: what is being raced {"kind": "daily" / "tour" / "cup", "cup": i, "pts": {kart index: points}}
var pit: PitScript  # pit.gd: the picture gates
var pit_rows: Array = []  # what the gates show (synced)
var shelf: Dictionary = {}  # Bolt's trophy shelf: "candy:gentle" -> medal 1..3 (synced)
var shelf_node: Node3D
var shelf_key := ""
var lap_ghost: Array = []  # the best lap on this track (5 a second), raced when there's no day ghost
var lap_ghost_t0 := -1.0  # race time the leading person started their lap (the lap ghost starts with them)
var lap_rec := {}  # host: kart index -> {"t0", "n", "path"} for the lap being driven
var lap_tick := 0.0
var last_medal := 0
var pits_done := 0

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
	seats = ClassicSeats.new(self, {
		"no_keys": KartScript.NO_KEYS,
		"free_actions": ["continue", "pause"],
		"deactivate": _seat_gone,
		"ghost": func(p, _on: bool) -> void: p.target_pos = p.position; p.target_yaw = p.yaw,
		"full": func() -> void: _show_center("All karts are taken!", 1.5, false),
	})
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
	pit = PitScript.new()
	pit.name = "Pit"
	pit.main = self
	add_child(pit)
	if mode != "client":
		_load_story()
	if SIMPLE_MODE and mode != "client":
		track_desc = Story.daily_desc()  # every session starts on TODAY'S TRACK (the practice too)
		series = {"kind": "daily"}
		_build_desc()
	else:
		track.build(0)
	_build_players(mode)
	_load_garage()
	_apply_looks()
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	if seats.deck_alone():
		seats.deck_solo(0)
	ready_to_play = true
	_ensure_join_listener()
	if mode == "client":
		players[1].set_meta("want_join", true)  # ask the host for a kart (it may hand out another one)
	_restore_party()
	if SIMPLE_MODE:
		laps = base_laps
	if mode == "host":
		state = "wait"
		var p: Array = track.grid_point(0)
		players[0].place_at(p[0], p[1], p[3])
		if SIMPLE_MODE:
			_start_practice()
		else:
			_show_center("KART RACE\nWaiting for the TV players… (warm up: drive around!)", 0.0)
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED", 1.5, false)
	elif SIMPLE_MODE:
		state = "wait"
		var slot := 0
		for k in players:
			if k.active:
				k.grid_slot = slot
				var g: Array = track.grid_point(slot)
				k.place_at(g[0], g[1], g[3])
				slot += 1
		_start_practice()
	else:
		_start_race(0)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0
	if net != null and net.mode != "client" and state == "race" and not race_logged and race_t > 5.0:
		_race_telemetry("quit", [])


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


# --- Mesh kit: merged vertex-coloured meshes (one draw call for a whole kart body) ---------------

## A box (optionally rotated) into a SurfaceTool, with flat normals.
func add_box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, b: Basis = Basis()) -> void:
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var fa: Array = f
		var nrm: Vector3 = fa[0]
		var u: Vector3 = fa[1]
		var v: Vector3 = fa[2]
		var center := nrm * h
		var du := u * h
		var dv := v * h
		var q: Array[Vector3] = [center - du - dv, center - du + dv, center + du + dv, center + du - dv]
		var wn := (b * nrm).normalized()
		var order: Array[int] = [0, 1, 2, 0, 2, 3]
		# Clockwise from the front (Godot's front face): flip if this winding faces inwards.
		if (q[1] - q[0]).cross(q[2] - q[0]).dot(nrm) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k in order:
			st.set_color(col)
			st.set_normal(wn)
			st.add_vertex(c + b * q[k])


## One triangle, wound so its front faces along `out` (Godot: clockwise seen from the front).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, out: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_color(col)
	st.set_normal(na)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(nc)
	st.add_vertex(c)


## An ellipsoid (lat-long sphere) into a SurfaceTool.
func add_ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, seg: int = 10, rings: int = 6) -> void:
	for i in rings:
		var v0 := PI * float(i) / rings
		var v1 := PI * float(i + 1) / rings
		for j in seg:
			var u0 := TAU * float(j) / seg
			var u1 := TAU * float(j + 1) / seg
			var us: Array[Vector3] = [_sph(v0, u0), _sph(v1, u0), _sph(v1, u1), _sph(v0, u1)]
			var ps: Array[Vector3] = []
			var ns: Array[Vector3] = []
			for un in us:
				ps.append(c + un * r)
				ns.append(Vector3(un.x / maxf(r.x, 0.001), un.y / maxf(r.y, 0.001), un.z / maxf(r.z, 0.001)).normalized())
			var out := (us[0] + us[1] + us[2] + us[3]).normalized()
			_tri(st, ps[0], ps[1], ps[2], ns[0], ns[1], ns[2], out, col)
			_tri(st, ps[0], ps[2], ps[3], ns[0], ns[2], ns[3], out, col)


func _sph(v: float, u: float) -> Vector3:
	return Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))


## A capped cylinder (along the basis' Y axis) into a SurfaceTool.
func add_cyl(st: SurfaceTool, c: Vector3, r: float, h: float, col: Color, b: Basis = Basis(), seg: int = 10) -> void:
	var top := Vector3(0, h * 0.5, 0)
	for j in seg:
		var a0 := TAU * float(j) / seg
		var a1 := TAU * float(j + 1) / seg
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var n0 := b * Vector3(cos(a0), 0, sin(a0))
		var n1 := b * Vector3(cos(a1), 0, sin(a1))
		var side := b * Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		_tri(st, c + b * (p0 - top), c + b * (p1 - top), c + b * (p1 + top), n0, n1, n1, side, col)
		_tri(st, c + b * (p0 - top), c + b * (p1 + top), c + b * (p0 + top), n0, n1, n0, side, col)
		var up := b * Vector3.UP
		_tri(st, c + b * top, c + b * (p0 + top), c + b * (p1 + top), up, up, up, up, col)
		_tri(st, c - b * top, c + b * (p0 - top), c + b * (p1 - top), -up, -up, -up, -up, col)


func _commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


## The kart body in one mesh: chassis, nose, bumper, side pods, seat, spoiler, engine, exhausts,
## headlights and a number plate.
func kart_body_mesh(col: Color) -> ArrayMesh:
	var key := "kartbody/" + col.to_html()
	if meshes.has(key):
		return meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light := col.lightened(0.3)
	var dark := Color(0.12, 0.12, 0.16)
	var white := Color(0.97, 0.97, 1.0)
	add_box(st, Vector3(0, 0.38, 0), Vector3(1.3, 0.32, 1.9), col)
	add_box(st, Vector3(0, 0.42, -1.15), Vector3(1.0, 0.24, 0.7), col, Basis(Vector3.RIGHT, -0.25))
	add_box(st, Vector3(0, 0.3, -1.45), Vector3(1.5, 0.12, 0.35), white)  # bumper
	add_box(st, Vector3(0, 0.56, -0.7), Vector3(0.7, 0.06, 0.5), light)  # bonnet stripe
	for x in [-1.0, 1.0]:
		add_box(st, Vector3(float(x) * 0.72, 0.36, 0.05), Vector3(0.18, 0.22, 0.8), light)  # side pods
		add_box(st, Vector3(float(x) * 0.33, 0.47, -1.47), Vector3(0.2, 0.1, 0.06), Color(1.0, 1.0, 0.75))  # headlights
		add_cyl(st, Vector3(float(x) * 0.28, 0.5, 1.05), 0.07, 0.35, Color(0.6, 0.62, 0.68), Basis(Vector3.RIGHT, PI * 0.5), 8)  # exhausts
	add_box(st, Vector3(0, 0.75, 0.62), Vector3(0.8, 0.5, 0.15), dark)  # seat back
	add_box(st, Vector3(0, 0.55, 0.85), Vector3(0.7, 0.3, 0.35), Color(0.3, 0.3, 0.35))  # engine
	add_box(st, Vector3(0, 1.0, 1.0), Vector3(1.5, 0.12, 0.3), light)  # spoiler
	for x in [-0.55, 0.55]:
		add_box(st, Vector3(float(x), 0.82, 1.0), Vector3(0.06, 0.32, 0.12), dark)  # spoiler struts
	add_box(st, Vector3(0, 0.36, -1.63), Vector3(0.42, 0.14, 0.02), white)  # number plate
	add_box(st, Vector3(0, 0.36, -1.645), Vector3(0.3, 0.05, 0.01), col.darkened(0.3))
	var m := _commit(st)
	meshes[key] = m
	return m


## A wheel: dark tyre plus a coloured hub on the +X side (axle along X).
func wheel_mesh() -> ArrayMesh:
	if meshes.has("kartwheel"):
		return meshes["kartwheel"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := Basis(Vector3.FORWARD, PI * 0.5)
	add_cyl(st, Vector3.ZERO, 0.3, 0.26, Color(0.1, 0.1, 0.12), side, 12)
	add_cyl(st, Vector3(0.12, 0, 0), 0.16, 0.04, Color(0.85, 0.85, 0.9), side, 10)
	add_box(st, Vector3(0.14, 0, 0), Vector3(0.02, 0.24, 0.05), Color(0.95, 0.75, 0.2))
	var m := _commit(st)
	meshes["kartwheel"] = m
	return m


## The driver's body and arms reaching for the wheel.
func driver_mesh(col: Color) -> ArrayMesh:
	var key := "driver/" + col.to_html()
	if meshes.has(key):
		return meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_ellipsoid(st, Vector3(0, 0.78, 0.35), Vector3(0.27, 0.36, 0.22), col)
	for x in [-1.0, 1.0]:
		add_ellipsoid(st, Vector3(float(x) * 0.24, 0.85, 0.08), Vector3(0.08, 0.08, 0.26), col.darkened(0.1), 8, 4)
		add_ellipsoid(st, Vector3(float(x) * 0.16, 0.92, -0.16), Vector3(0.07, 0.07, 0.07), Color(1.0, 1.0, 1.0), 6, 3)  # gloves
	var m := _commit(st)
	meshes[key] = m
	return m


## Helmet with a visor and a stripe in the kart's colour.
func helmet_mesh(col: Color) -> ArrayMesh:
	var key := "helmet/" + col.to_html()
	if meshes.has(key):
		return meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_ellipsoid(st, Vector3.ZERO, Vector3(0.24, 0.24, 0.24), Color(0.97, 0.97, 1.0), 12, 7)
	add_box(st, Vector3(0, 0.0, -0.21), Vector3(0.36, 0.12, 0.08), Color(0.2, 0.6, 1.0))
	add_box(st, Vector3(0, 0.12, 0.0), Vector3(0.06, 0.3, 0.44), col)
	var m := _commit(st)
	meshes[key] = m
	return m


## A hat (story.gd HATS) to sit on a helmet (the helmet's centre is the origin, radius 0.24).
func hat_model(h: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Hat"
	var col: Color = Story.HATS[posmod(h, Story.HATS.size())][2]
	var add := func(mesh: Mesh, c: Color, pos: Vector3, glow: float = 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = make_material(c, glow)
		mi.position = pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		return mi
	match posmod(h, Story.HATS.size()):
		0:  # party hat
			add.call(cyl_mesh(0.0, 0.15, 0.42, 12), col, Vector3(0, 0.4, 0))
			add.call(cyl_mesh(0.105, 0.125, 0.06, 12), Color(1.0, 0.95, 0.4), Vector3(0, 0.3, 0))
			add.call(sphere_mesh(0.06), Color(1, 1, 1), Vector3(0, 0.62, 0))
		1:  # top hat
			add.call(cyl_mesh(0.28, 0.28, 0.03, 16), col, Vector3(0, 0.2, 0))
			add.call(cyl_mesh(0.17, 0.16, 0.32, 16), col, Vector3(0, 0.36, 0))
			add.call(cyl_mesh(0.165, 0.165, 0.06, 16), Color(0.95, 0.2, 0.25), Vector3(0, 0.25, 0))
		2:  # cowboy hat
			add.call(cyl_mesh(0.36, 0.36, 0.03, 18), col.darkened(0.1), Vector3(0, 0.18, 0))
			add.call(cyl_mesh(0.16, 0.19, 0.2, 14), col, Vector3(0, 0.28, 0))
			add.call(cyl_mesh(0.19, 0.19, 0.04, 14), Color(0.95, 0.3, 0.3), Vector3(0, 0.2, 0))
		3:  # wizard hat
			add.call(cyl_mesh(0.32, 0.32, 0.03, 18), col.darkened(0.2), Vector3(0, 0.18, 0))
			add.call(cyl_mesh(0.0, 0.17, 0.4, 14), col, Vector3(0, 0.39, 0))
			add.call(sphere_mesh(0.05), Color(1.0, 0.92, 0.35), Vector3(0.0, 0.42, -0.14), 1.5)
		4:  # woolly hat
			add.call(sphere_mesh(0.255), col, Vector3(0, 0.05, 0))
			add.call(cyl_mesh(0.26, 0.26, 0.08, 16), Color(1, 1, 1), Vector3(0, 0.04, 0))
			add.call(sphere_mesh(0.08), Color(1, 1, 1), Vector3(0, 0.32, 0))
		_:  # crown
			add.call(cyl_mesh(0.2, 0.18, 0.14, 16), col, Vector3(0, 0.27, 0), 0.3)
			for k in 5:
				var a := TAU * k / 5.0
				add.call(sphere_mesh(0.045), col.lightened(0.2), Vector3(cos(a) * 0.19, 0.37, sin(a) * 0.19), 0.3)
			add.call(sphere_mesh(0.045), Color(0.95, 0.2, 0.3), Vector3(0, 0.27, -0.19), 0.8)
	return root


## A spectator: body + head + arms (vertex colour R = skin, G = arm, so the crowd shader can wave).
func person_mesh() -> ArrayMesh:
	if meshes.has("person"):
		return meshes["person"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_ellipsoid(st, Vector3(0, 0.45, 0), Vector3(0.22, 0.32, 0.16), Color(0, 0, 0), 8, 5)
	add_ellipsoid(st, Vector3(0, 0.95, 0), Vector3(0.15, 0.16, 0.15), Color(1, 0, 0), 8, 5)
	for x in [-1.0, 1.0]:
		add_ellipsoid(st, Vector3(float(x) * 0.25, 0.75, 0), Vector3(0.06, 0.2, 0.06), Color(0, 1, 0), 6, 3)
	var m := _commit(st)
	meshes["person"] = m
	return m


func snowman_mesh() -> ArrayMesh:
	if meshes.has("snowman"):
		return meshes["snowman"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color(0.97, 0.98, 1.0)
	add_ellipsoid(st, Vector3(0, 0.55, 0), Vector3(0.6, 0.55, 0.6), w)
	add_ellipsoid(st, Vector3(0, 1.35, 0), Vector3(0.42, 0.4, 0.42), w)
	add_ellipsoid(st, Vector3(0, 1.95, 0), Vector3(0.3, 0.3, 0.3), w)
	add_cyl(st, Vector3(0, 2.3, 0), 0.22, 0.32, Color(0.1, 0.1, 0.12))
	add_cyl(st, Vector3(0, 2.16, 0), 0.34, 0.04, Color(0.1, 0.1, 0.12))
	add_cyl(st, Vector3(0, 1.95, -0.38), 0.05, 0.25, Color(1.0, 0.5, 0.1), Basis(Vector3.RIGHT, PI * 0.5), 6)  # carrot
	for x in [-0.1, 0.1]:
		add_ellipsoid(st, Vector3(float(x), 2.05, -0.27), Vector3(0.04, 0.04, 0.04), Color(0.05, 0.05, 0.05), 5, 3)
	add_box(st, Vector3(0, 1.66, 0), Vector3(0.9, 0.12, 0.9), Color(0.85, 0.2, 0.2))  # scarf
	var m := _commit(st)
	meshes["snowman"] = m
	return m


## A little model of an item (for the VR dash and the banana peels on the track).
func build_item_model(parent: Node3D, it: String, sc: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := 0.4
	match it:
		"banana":
			for i in 5:
				var a := -0.9 + i * 0.45
				add_ellipsoid(st, Vector3(sin(a) * 0.6, cos(a) * 0.6 - 0.5, 0), Vector3(0.22, 0.22, 0.22), Color(1.0, 0.88, 0.2), 8, 4)
			add_ellipsoid(st, Vector3(sin(1.05) * 0.6, cos(1.05) * 0.6 - 0.5, 0), Vector3(0.1, 0.1, 0.1), Color(0.35, 0.25, 0.1), 6, 3)
		"shield":
			add_ellipsoid(st, Vector3.ZERO, Vector3(0.6, 0.6, 0.6), Color(0.5, 0.9, 1.0), 12, 6)
			glow = 0.8
		"mushroom", "triple":
			var n := 3 if it == "triple" else 1
			for i in n:
				var o := Vector3((i - (n - 1) * 0.5) * 0.8, 0, 0) * (1.0 if n > 1 else 0.0)
				var k := 0.7 if n > 1 else 1.0
				add_cyl(st, o + Vector3(0, -0.2, 0) * k, 0.2 * k, 0.5 * k, Color(1, 0.95, 0.85), Basis(), 8)
				add_ellipsoid(st, o + Vector3(0, 0.15, 0) * k, Vector3(0.5, 0.3, 0.5) * k, Color(1.0, 0.25, 0.2), 10, 5)
				add_ellipsoid(st, o + Vector3(0.18, 0.38, 0.1) * k, Vector3(0.1, 0.06, 0.1) * k, Color(1, 1, 1), 6, 3)
		"star":
			for i in 5:
				var a := TAU * i / 5.0
				add_box(st, Vector3(sin(a) * 0.32, cos(a) * 0.32, 0), Vector3(0.22, 0.55, 0.18), Color(1.0, 0.9, 0.2), Basis(Vector3.BACK, -a))
			add_ellipsoid(st, Vector3.ZERO, Vector3(0.3, 0.3, 0.2), Color(1.0, 0.95, 0.4), 8, 4)
			glow = 1.0
		"honk":
			add_cyl(st, Vector3(0, 0, 0.2), 0.35, 0.2, Color(1.0, 0.4, 0.6), Basis(Vector3.RIGHT, PI * 0.5), 10)
			add_cyl(st, Vector3(0, 0, -0.15), 0.12, 0.6, Color(0.95, 0.85, 0.3), Basis(Vector3.RIGHT, PI * 0.5), 8)
			add_ellipsoid(st, Vector3(0, 0, -0.5), Vector3(0.25, 0.25, 0.25), Color(1.0, 0.3, 0.3), 8, 4)
	var mi := MeshInstance3D.new()
	mi.mesh = _commit(st)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.emission_enabled = true
	mat.emission = Color(glow, glow, glow) * 0.5
	mi.material_override = mat
	mi.scale = Vector3.ONE * sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


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
	# A fake headset camera (never current) at the driver's eyes: VR cards, VR text and the bots' VR view (vrShot)
	# work as with a headset. The driver's own body is on the TV-only avatar layer, so it doesn't fill that view.
	var cam := XRCamera3D.new()
	cam.name = "FakeHead"
	cam.near = 0.03
	cam.far = 600.0
	players[0].add_child(cam)  # rides in the kart, like a headset's rig
	cam.current = false
	cam.cull_mask = 0xFFFFF & ~preload("res://core/vr_rig.gd").AVATAR_LAYER
	for v in players[0].driver.find_children("*", "VisualInstance3D", true, false):
		(v as VisualInstance3D).layers = preload("res://core/vr_rig.gd").AVATAR_LAYER
	cockpit.xr_camera = cam
	print("Fake VR cockpit on P1")
	return cockpit


## Test hook: shorter races (laps, and optionally finish part-way round the last lap).
func debug_fast(n_laps: int, frac: float = 1.0) -> void:
	laps = n_laps
	base_laps = n_laps
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
	UiKit.pin(bg, Control.PRESET_FULL_RECT, false)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	UiKit.pin(views_root, Control.PRESET_FULL_RECT, false)


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
	# Your own name tag floats right in front of your chase camera (a giant "P3" over the road at the
	# start): each view hides its own kart's tag; everyone else still sees it.
	if p.index < 8 and p.tag != null:
		p.tag.layers = 1 << (10 + p.index)
		cam.cull_mask &= ~(1 << (10 + p.index))
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)
	UiKit.pin(hud, Control.PRESET_FULL_RECT, false)
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
	UiKit.pin(p.place_label, Control.PRESET_TOP_RIGHT, false)
	p.place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.item_label = _make_label(28)
	hud.add_child(p.item_label)
	UiKit.pin(p.item_label, Control.PRESET_BOTTOM_LEFT, false)
	p.hint_label = _make_label(40)
	hud.add_child(p.hint_label)
	UiKit.pin(p.hint_label, Control.PRESET_CENTER, false)
	p.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.hint_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.55)
	bar_bg.name = "BarBg"
	hud.add_child(bar_bg)
	p.boost_fill = ColorRect.new()
	p.boost_fill.color = Color(0.3, 0.8, 1.0)
	bar_bg.add_child(p.boost_fill)
	var drift_bg := ColorRect.new()
	drift_bg.color = Color(0, 0, 0, 0.55)
	drift_bg.name = "DriftBg"
	hud.add_child(drift_bg)
	p.drift_fill = ColorRect.new()
	drift_bg.add_child(p.drift_fill)
	# Minimap: the track outline with a dot for every kart.
	var mm := Control.new()
	mm.name = "Minimap"
	mm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(mm)
	var line := Line2D.new()
	line.name = "Line"
	line.width = 5.0
	line.default_color = Color(1, 1, 1, 0.75)
	line.closed = true
	mm.add_child(line)
	for i in karts.size():
		var dot := ColorRect.new()
		dot.color = karts[i].color
		dot.size = Vector2(10, 10)
		dot.visible = false
		mm.add_child(dot)
	p.minimap = mm


## TV grid: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2; smaller views render at lower resolution.
func _layout_views() -> void:
	if views_root == null or not is_instance_valid(views_root):
		return
	var shown: Array = []
	for p in players:
		if not p.has_meta("view"):
			continue
		var c: SubViewportContainer = p.get_meta("view")
		c.visible = p.active and p.is_local()
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
		var drift_bg: ColorRect = p.hud.get_node("DriftBg")
		drift_bg.size = Vector2(260.0 * ui, 12.0 * ui)
		drift_bg.position = Vector2(16.0, cell.y - 62.0 * ui)
		p.drift_fill.size = Vector2(0, 12.0 * ui)
		p.item_label.position = Vector2(16.0, cell.y - 120.0 * ui)
		var msz := 190.0 * ui
		p.minimap.position = Vector2(cell.x - msz - 16.0, cell.y - msz - 16.0)
		p.minimap.size = Vector2(msz, msz)
		p.minimap.set_meta("track", -1)
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
	if not ready_to_play:
		return
	if net.mode == "host":
		if connected and not players[0].vr and players[0].joy < 0:
			players[0].joy = device  # flat host (no VR): P1 drives with this controller
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
		if pick == null and players[1].joy < 0 and players[1].is_local():
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


func _join_slot(device: int):
	var idx := seats.free_index()
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
		seats.ask_soon()
	elif not p.active:
		_activate(p)
	_save_party()


## A kart joins: onto the grid before the start, at the back of the pack during a race.
func _activate(p) -> void:
	p.set_active(true)
	p.reset_race()
	_place_new(p)
	if not SIMPLE_MODE:
		_show_center(Who.joined(Who.seat(self, p.index), "the race"), 1.5)
	burst(p.position + Vector3(0, 1.5, 0), p.color, 16)
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
		_show_center(Who.left(Who.seat(self, p.index)), 1.5)
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


func on_player_activity_changed(p) -> void:
	if p.active and p.is_local():
		_ensure_view(p)
	if seats.joined(p):
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
	_follow_weather()
	_update_trophies(dt)
	_record_laps(dt)
	_update_ghost(dt)
	_update_shelf()
	if net.mode == "client":
		pit.show_rows(pit_rows)
	_update_bananas_visual()
	track.boxes_on = boxes_live()
	_update_gate(dt)
	if cockpit != null:
		cockpit.place(dt)
	for p in players:
		if p.camera != null:
			p.update_camera(dt)
		if SIMPLE_MODE and p.active and p.is_local():
			_track_cues(p, dt)
		if p.hud != null:
			_update_hud(p, dt)
	_update_vr_text(dt)


func _host_update(dt: float, cont_edge: bool) -> void:
	_update_lost_pads(dt)
	state_t += dt
	match state:
		"wait":
			if SIMPLE_MODE and practice_gate >= 0:
				_practice_update(dt)
			elif net.mode == "host":
				solo_t += dt
				if solo_t > SOLO_WAIT and not net.connected:
					print("No TV players yet: racing the CPU buddies (TV players can join any time)")
					_start_race(cup_track())
		"countdown":
			var dur := _intro_time()
			var left := int(ceilf(dur - state_t))
			if left <= 3 and left >= 1 and left != last_count:
				last_count = left
				_show_center(str(left), 0.8)
				sound("count", 0.0, 1.0, true)
				set_lights(4 - left)
			if state_t >= dur:
				state = "race"
				state_t = 0.0
				race_t = 0.0
				for k in karts:
					k.hold_still = false
				_show_center("GO!", 0.8)
				sound("go", 0.0, 1.0, true)
				set_lights(4)
				track.excite(1.0)
				net.event("go", [])
				for k in karts:
					if k.active and k.is_sim():
						_rocket(k)
		"race":
			race_t += dt
		"pit":
			var humans: Array = []
			for p in players:
				if p.active:
					humans.append(p)
			if pit.update(dt, humans):
				_pit_done()
		"results":
			if (state_t > 2.0 and cont_edge) or state_t > (SIMPLE_NEXT if SIMPLE_MODE else 45.0 if cup_race >= 2 else 30.0):
				_next_race()
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
	seats.sync()
	seats.request_joins(dt)
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
	if SIMPLE_MODE:
		return INTRO_TIME
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
		_next_race()


## The next race of the Grand Prix (after the third race, a new cup on new tracks).
func _next_race() -> void:
	if SIMPLE_MODE:  # the next race of the cup / tour place, or the PIT STOP to pick the next one
		var nxt := _series_next()
		if nxt.is_empty():
			_start_pit()
			return
		track_desc = nxt
		_start_race(track_i + 1)
		return
	if cup_race >= 2:
		cup_i += 1
		cup_race = 0
		cup_pts.clear()
	else:
		cup_race += 1
	_start_race(cup_track())


func cup_info() -> Dictionary:
	return CUPS[posmod(cup_i, CUPS.size())]


func cup_track() -> int:
	var tr: Array = cup_info()["tracks"]
	return int(tr[clampi(cup_race, 0, tr.size() - 1)])


func cup_points(k) -> int:
	var i := karts.find(k)
	return cup_pts[i] if i >= 0 and i < cup_pts.size() else 0


func set_lights(k: int) -> void:
	lights = k
	track.set_lights(k)
	if net.mode == "host":
		net.event("lights", [k])


## At GO: a boost for anyone who pressed go at the right moment.
func _rocket(k) -> void:
	if SIMPLE_MODE:
		return
	if k.try_rocket_start():
		print("%s: rocket start!" % k.kart_name)
		if not k.cpu:
			notify(k, "ROCKET START!")
			kart_sound(k, "rocket", -2.0)
			burst(k.position + Vector3(0, 0.6, 0) - k.forward() * 1.4, Color(1.0, 0.7, 0.2), 14)


func finish_distance() -> float:
	return (laps - 1 + finish_frac) * track.length


func _start_race(ti: int) -> void:
	if SIMPLE_MODE and not track_desc.is_empty():
		_build_desc()
	else:
		track_i = posmod(ti, TrackScript.count())
		track.build(track_i)
		_apply_track_look()
	round_n += 1
	race_logged = false
	ghost_rec.clear()
	ghost_rec_t = 0.0
	_clear_trophies()
	_clear_tour_strips()
	set_lights(0)
	if cup_pts.size() != karts.size():
		cup_pts.resize(karts.size())
	bananas.clear()
	for i in track.box_t.size():
		track.box_t[i] = 0.0
	net.event("race", [track_i, laps, round_n, finish_frac, track_desc, hats_won])  # before the teleports: the TV builds the track first
	_race_story_start()
	# CPU buddies fill the grid (fewer as more people play).
	var humans := human_count()
	var want_cpu := clampi(GRID_FILL - humans, 0, MAX_CPU) if bool(mode_info().cpus) else 0
	for j in cpus.size():
		cpus[j].set_active(j < want_cpu)
		cpus[j].cpu_skill = float(mode_info().cpu_skill) * (1.0 - 0.02 * j)
		cpus[j].set_kart("medium", "")  # CPUs always drive the middle kart (fair)
	if SIMPLE_MODE:
		laps = base_laps + (1 if speed_mode == "trial" else 0)
	pit.stop()
	pit_rows = []
	lap_rec.clear()
	lap_ghost_t0 = -1.0
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
	if SIMPLE_MODE:
		_show_center("", 0.0)
		print("Race %d on %s: %d karts (%d human), %d laps, %.0f m to go%s" % [round_n, str(track.info["name"]), racer_count(), humans, laps,
			finish_distance(), (" [%s, %d ramps, %d split lanes]" % [str(track_desc), track.ramps.size(), track.splits.size()]) if not track_desc.is_empty() else ""])
		return
	var title := "%s - RACE %d of 3\n%s · %d LAP%s" % [str(cup_info()["name"]), cup_race + 1, TrackScript.track_name(track_i), laps, "S" if laps > 1 else ""]
	if round_n == 1:
		_show_center("KART RACE GRAND PRIX!  " + title + "\n" \
			+ "VR: hold the wheel with both hands · trigger = GO · A = item / boost\n" \
			+ "TV: stick steers · A = go · X = item · Y = boost · B in a turn = DRIFT\n" \
			+ "Press GO on the last red light for a ROCKET START!", _intro_time() - 3.2)
	else:
		_show_center(title + "\nPress GO on the last red light for a rocket start!", _intro_time() - 3.2)
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
				if SIMPLE_MODE:
					notify(k, "LAP %d" % lap)
				else:
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
	notify(k, "FINISH!" if SIMPLE_MODE else "FINISHED %s!" % ordinal(pl).to_upper())  # simple: the place label shows the place
	burst(k.position + Vector3(0, 1.5, 0), k.color, 24)
	if not k.cpu:
		for c in [Color(1.0, 0.3, 0.4), Color(0.3, 0.8, 1.0), Color(1.0, 0.9, 0.3)]:
			burst(k.position + Vector3(0, 2.0, 0), c, 14)
		track.excite(1.0)
		net.event("excite", [1.0])
		sound("cheer", -8.0, 1.0, true)
	if not k.cpu and not SIMPLE_MODE:
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
	if SIMPLE_MODE:
		_simple_results(order)
		return
	if cup_pts.size() != karts.size():
		cup_pts.resize(karts.size())
	var lines: Array[String] = ["RACE %d of 3 OVER!  -  %s" % [cup_race + 1, TrackScript.track_name(track_i)]]
	var row: Array[String] = []
	var gained := {}
	for k in order:
		var pts := POINTS[clampi(k.place - 1, 0, POINTS.size() - 1)]
		var i := karts.find(k)
		cup_pts[i] += pts
		gained[k] = pts
		row.append("%s %s +%d%s" % [ordinal(k.place), k.kart_name, pts, " WINNER!" if k.place == 1 else ""])
	lines.append("   ·   ".join(row))
	var final := cup_race >= 2
	# Cup standings (or the trophies after the third race).
	var standing: Array = order.duplicate()
	standing.sort_custom(func(a, b) -> bool: return cup_points(a) > cup_points(b) or (cup_points(a) == cup_points(b) and a.place < b.place))
	var headline := "RACE %d of 3 OVER!  Winner: %s" % [cup_race + 1, order[0].kart_name if not order.is_empty() else "-"]
	if final:
		var names: Array[String] = ["GOLD", "SILVER", "BRONZE"]
		var tl: Array[String] = []
		trophy_karts.clear()
		for j in mini(3, standing.size()):
			var w = standing[j]
			tl.append("%s %s (%d pts)" % [names[j], w.kart_name, cup_points(w)])
			trophy_karts.append(karts.find(w))
		lines.append("%s - FINAL!  %s" % [str(cup_info()["name"]), "  ·  ".join(tl)])
		headline = "%s DONE!\n%s" % [str(cup_info()["name"]), "  ".join(tl)]
		_show_trophies(trophy_karts)
		net.event("trophies", [trophy_karts])
	else:
		var parts: Array[String] = []
		for k in standing:
			parts.append("%s %d" % [k.kart_name, cup_points(k)])
		lines.append("CUP POINTS: " + "  ·  ".join(parts))
	var aw: Dictionary = _awards(order)
	if not aw.is_empty():
		var al: Array[String] = []
		for k in aw:
			al.append("%s %s" % [k.kart_name, str(aw[k])])
		lines.append("AWARDS: " + "  ·  ".join(al))
	var next_line := ""
	if final:
		var nxt: Dictionary = CUPS[posmod(cup_i + 1, CUPS.size())]
		next_line = "Next: the %s!  A / Enter (VR: trigger)" % str(nxt["name"])
	else:
		var tr: Array = cup_info()["tracks"]
		next_line = "Next: %s  ·  A / Enter (VR: trigger)" % TrackScript.track_name(int(tr[cup_race + 1]))
	lines.append(next_line)
	# The VR rider gets a short, personal version (a long list would be a huge panel in VR).
	var me = players[0]
	vr_results = headline
	if me.active:
		vr_results += "\nYou: %s  (+%d pts, cup %d)" % [ordinal(me.place), int(gained.get(me, 0)), cup_points(me)]
		if aw.has(me):
			vr_results += "\n" + str(aw[me])
	vr_results += "\n" + next_line.replace("A / Enter (VR: trigger)", "pull the trigger")
	results_text = "\n".join(lines)
	_show_center(results_text, 0.0)
	sound("finish", 0.0, 1.2, true)
	if final:
		sound("trophy", 0.0, 1.0, true)
	track.excite(1.0)
	net.event("excite", [1.0])
	print("Results: " + " | ".join(lines))


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
		if state == "race" and race_t > 4.0 and not racers[i].finished:
			racers[i].worst_place = maxi(racers[i].worst_place, i + 1)


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
	var md := mode_info()
	var f := 1.0 + clampf((lead - k.total) / 70.0, 0.0, 1.0) * float(md.catch)
	if k.cpu:
		f *= k.cpu_skill
		if bool(md.cpu_ease) and best_h > -INF and k.total > best_h + 12.0:
			f *= 0.85
	elif bool(md.cpu_ease) and best_h - last_h > 50.0 and k.total >= best_h - 1.0:
		f *= 0.95
	return f


# --- The Grand Tour (story.gd): generated tracks, champs, hats, today's track and its ghost -----------

## Host / local: the save (story progress, hats, today's best ghost).
func _load_story() -> void:
	save = SaveScript.new()
	save.game_id = Story.GAME_ID
	save.defaults = Story.save_defaults()
	add_child(save)
	var d: Dictionary = save.data
	if int(d["world"]) < 0:
		d["world"] = Seeded.fresh_seed()
		save.mark_dirty()
	if OS.has_environment("KART_WORLD"):  # tests: a known tour
		d["world"] = int(OS.get_environment("KART_WORLD"))
	if OS.has_environment("KART_STORY"):
		d["story_i"] = int(OS.get_environment("KART_STORY"))
		d["hats"] = mini(Story.HATS.size(), int(d["story_i"]) / Story.RACES_PER_PLACE)
	hats_won = int(d["hats"])
	print("Grand Tour: world %d, race %d (%s), %d hats, %d golds" % [int(d["world"]), int(d["story_i"]),
		str(Story.place(int(Story.where(int(d["story_i"]))[0])).name), hats_won, int(d["golds"])])


## Build the generated track track_desc describes (every machine makes the same one from the numbers).
func _build_desc() -> void:
	if track.key == Story.key_for(track_desc) and track.built != null:
		_apply_looks()
		return
	var t0 := Time.get_ticks_msec()
	var r: Array = Story.track_for(track_desc)
	var info: Dictionary = r[0]
	track.build_info(info, String(r[1]))
	track_i = track.track_i
	_apply_track_look()
	_apply_looks()
	if info.has("fallback"):
		print("SCRIPT ERROR: KART TRACK fell back to a hand-made track for %s" % str(track_desc))
	print("Generated %s in %d ms (attempt %d)" % [str(info["name"]), Time.get_ticks_msec() - t0, int(info.get("attempt", -1))])


## The place's champ drives CPU slot 0 (wearing the hat you can win there); won hats on the drivers.
func _apply_looks() -> void:
	if karts.is_empty():
		return
	var pl_i := Story.desc_place(track_desc) if not track_desc.is_empty() and not Story.is_daily(track_desc) else -1
	var champ := String(Story.place(pl_i).champ) if pl_i >= 0 else ""
	var cupn := int(track_desc[2]) if Story.is_cup(track_desc) else -1
	if cupn >= 0:
		champ = String(Cups.cup(cupn).champ)
	for j in cpus.size():
		var c = cpus[j]
		if j == 0 and cupn >= 0:
			c.set_look(champ, Cups.cup(cupn).champ_color)
			c.set_hat(-1)
		elif j == 0 and pl_i >= 0:
			c.set_look(champ, Story.place(pl_i).champ_color)
			c.set_hat(pl_i)
		else:
			var nm: String = CPU_NAMES[j] if CPU_NAMES[j] != champ else CPU_NAMES[0]
			c.set_look(nm, CPU_COLORS[j])
			c.set_hat(-1)
	for p in players:
		p.set_hat(Story.hat_for(p.index, hats_won))


## Host: a picture card on every machine (a word or two and one short line: no how-to text).
func story(beat: Dictionary) -> void:
	show_story(beat)
	if net.mode == "host":
		net.event("story", [beat])


func show_story(beat: Dictionary) -> void:
	story_count += 1
	var opts := beat.duplicate()
	opts["color"] = Color.html(String(beat.get("color", "ffd25a")))
	if state == "wait" or state == "countdown":
		opts["y"] = 0.6  # before GO the top of the view is the start gantry and its lights: the card goes under them
	var huds: Array = []
	for p in players:
		if p.active and p.is_local() and p.hud != null and is_instance_valid(p.hud) and p.hud.is_visible_in_tree():
			huds.append(p.hud)
	if not huds.is_empty():
		StoryCard.show(huds, opts)
	if cockpit != null and cockpit.xr_camera != null:  # (fake cockpits have a fake head too: the VR bots see it)
		StoryCard.show_vr(self, cockpit.xr_camera, opts)
	print("Story card: %s - %s" % [String(beat.get("who", "")), String(beat.get("line", ""))])


## Host / local at the countdown: tell the place's story, set up today's ghost.
func _race_story_start() -> void:
	if track_desc.is_empty():
		return
	_set_ghost([])
	_race_story_cards()
	_start_lap_ghost()


func _race_story_cards() -> void:
	if Story.is_cup(track_desc):
		var cp := Cups.cup(int(track_desc[2]))
		var r := int(track_desc[3])
		if r == 0:
			story({"who": String(cp.name), "line": String(cp.intro), "pic": String(cp.pic), "color": (cp.color as Color).to_html(false), "duration": 4.0})
		elif r == Cups.RACES - 1 and cpus[0].active:
			story({"who": String(cp.champ), "line": "The last race! Go!", "pic": String(cp.pic), "color": (cp.champ_color as Color).to_html(false),
				"duration": 3.5})
		return
	if Story.is_daily(track_desc):
		var dd: Dictionary = save.data["daily"] if save != null else {}
		var has_ghost := String(dd.get("date", "")) == Seeded.today() and int(dd.get("laps", 0)) == laps \
			and absf(float(dd.get("frac", 1.0)) - finish_frac) < 0.01 and not (dd.get("ghost", []) as Array).is_empty()
		if has_ghost:
			_set_ghost(dd["ghost"])
			net.event("ghost", [dd["ghost"]])
		if not bolt_hello:  # Bolt says hello once a session: he built TODAY'S TRACK
			bolt_hello = true
			story({"who": "HI! I'M BOLT!", "line": "Race your ghost!" if has_ghost else "I built a new track!", "pic": "boltbot",
				"color": BOLT_COLOR, "duration": 4.0})
		else:
			story({"who": "TODAY'S TRACK", "line": "Race your ghost!" if has_ghost else "A new track today!", "pic": "boltbot",
				"color": "ffd25a", "duration": 4.0})
		return
	var w := Story.where(int(track_desc[2]))
	var pl := Story.place(int(w[0]))
	if int(w[1]) == 0:
		story({"who": String(pl.name), "line": String(pl.intro) if int(w[2]) == 0 else "Bonus tour! Go go go!",
			"pic": String(pl.pic), "color": (pl.color as Color).to_html(false), "duration": 4.0})
	elif int(w[1]) == Story.RACES_PER_PLACE - 1 and cpus[0].active:
		story({"who": String(pl.champ), "line": "Win my hat if you can!", "pic": String(Story.HATS[int(w[0])][1]),
			"color": (pl.champ_color as Color).to_html(false), "duration": 3.5})


## Host / local after each race: story progress (hats, champs), today's best and ghost, telemetry, cards.
func _story_after_race(order: Array, cup_beats: Array = []) -> void:
	if save == null or track_desc.is_empty():
		return
	var d: Dictionary = save.data
	var best = null
	for k in order:
		if not k.cpu:
			best = k
			break
	d["races"] = int(d["races"]) + 1
	if best != null and best.place == 1:
		d["golds"] = int(d["golds"]) + 1
	var beats: Array = []
	if Story.is_daily(track_desc):
		var dd: Dictionary = d["daily"]
		var today := Seeded.today()
		var same := String(dd.get("date", "")) == today and int(dd.get("laps", 0)) == laps and absf(float(dd.get("frac", 1.0)) - finish_frac) < 0.01
		if best != null and best.finished and (not same or best.finish_time < float(dd.get("time", 0.0))):
			d["daily"] = {"date": today, "time": best.finish_time, "ghost": ghost_rec.duplicate(), "laps": laps, "frac": finish_frac}
			beats.append({"who": "BEST TODAY!", "line": "Your ghost will race you!", "pic": "trophy", "color": "ffd25a", "duration": 3.5})
	elif Story.is_cup(track_desc):
		beats.append_array(cup_beats)
	else:
		var i := int(track_desc[2])
		var w := Story.where(i)
		var pl := Story.place(int(w[0]))
		var last := int(w[1]) == Story.RACES_PER_PLACE - 1
		d["story_i"] = maxi(int(d["story_i"]), i + 1)
		var champ = cpus[0]
		if last and champ.active and best != null and best.place < champ.place:
			d["champs"] = int(d["champs"]) + 1
			beats.append({"who": "YOU BEAT %s!" % String(pl.champ), "line": "What a race!", "pic": "trophy",
				"color": (pl.champ_color as Color).to_html(false), "duration": 3.0})
		if last:
			var won := Story.hats_after(i)
			if won > hats_won:
				var h: Array = Story.HATS[won - 1]
				beats.append({"who": "NEW HAT!", "line": "A %s for you!" % String(h[0]).to_lower(), "pic": String(h[1]),
					"color": (h[2] as Color).to_html(false), "duration": 3.5})
				hats_won = won
				d["hats"] = hats_won
				_apply_looks()
			beats.append({"who": String(pl.name), "line": String(pl.done), "pic": String(pl.pic),
				"color": (pl.color as Color).to_html(false), "duration": 3.0})
			if int(w[0]) == Story.PLACES.size() - 1:
				d["tours"] = int(d["tours"]) + 1
				beats.append({"who": "BOLT", "line": "The whole tour! WOW!", "pic": "boltbot", "color": BOLT_COLOR, "duration": 3.5})
			else:
				beats.append({"who": "BOLT", "line": "I'll build the next one!", "pic": "boltbot", "color": BOLT_COLOR, "duration": 3.0})
	save.mark_dirty()
	_race_telemetry("finish", order)
	net.event("race_hats", [hats_won])
	for j in beats.size():
		var b: Dictionary = beats[j]
		if j == 0:
			story(b)
		else:
			get_tree().create_timer(3.2 * j).timeout.connect(func() -> void:
				if state == "results":
					story(b))


## One RUN line per race (core/telemetry.gd) for balancing from real play.
func _race_telemetry(how: String, order: Array) -> void:
	if race_logged or track_desc.is_empty():
		return
	race_logged = true
	var humans := 0
	var best_place := 99
	var first_t := -1.0
	var last_t := 0.0
	var walls := 0
	var air := 0
	var short := 0
	var items := 0
	for k in karts:
		if not k.active or k.cpu:
			continue
		humans += 1
		best_place = mini(best_place, k.place)
		walls += k.st_walls
		air += k.st_air
		short += k.st_short
		items += k.st_items
		if k.finished:
			first_t = k.finish_time if first_t < 0.0 else minf(first_t, k.finish_time)
			last_t = maxf(last_t, k.finish_time)
	var cpu_n := 0
	for c in cpus:
		if c.active:
			cpu_n += 1
	var daily := Story.is_daily(track_desc)
	var w := Story.where(int(track_desc[2])) if not daily else [Story.desc_place(track_desc), -1, -1]
	var classes: Array[String] = []
	var hz := 0
	for k in players:
		if k.active:
			classes.append(String(k.kart_class))
			hz += k.st_hazards
	var cup := Story.is_cup(track_desc)
	if cup:
		w = [-1, int(track_desc[3]), -1]
	Telemetry.run(Story.GAME_ID, {"race": round_n, "daily": daily, "kind": "cup" if cup else ("daily" if daily else "tour"),
		"cup": String(Cups.cup(int(track_desc[2])).id) if cup else "", "speed": speed_mode, "karts": ",".join(classes), "hazards": hz,
		"hz_n": track.hazards.size(), "medal": last_medal if cup and int(track_desc[3]) == Cups.RACES - 1 else -1,
		"items_kinds": ",".join(PackedStringArray(items_given.keys())), "story_i": int(track_desc[2]) if not cup else -1, "place": int(w[0]),
		"step": int(w[1]), "tour": int(w[2]), "seed": int(track_desc[1]), "len": int(track.length), "laps": laps, "frac": finish_frac,
		"ramps": track.ramps.size(), "splits": track.splits.size(), "humans": humans, "cpus": cpu_n, "best_place": best_place,
		"first_t": snappedf(first_t, 0.1), "last_t": snappedf(last_t, 0.1), "race_t": snappedf(race_t, 0.1), "walls": walls,
		"air": air, "shortcut": short, "items": items, "hats": hats_won, "vr": cockpit != null and not cockpit.fake,
		"net": net.mode, "solo": humans == 1, "end": how})


## Today's ghost: a see-through kart that drives the day's best run (path sampled 5 times a second).
func _set_ghost(path: Array) -> void:
	ghost_path = path
	if ghost_node == null:
		ghost_node = Node3D.new()
		ghost_node.name = "Ghost"
		add_child(ghost_node)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.9, 1.0, 0.38)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.7, 1.0)
		mat.emission_energy_multiplier = 0.6
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for m in [kart_body_mesh(Color(0.8, 0.9, 1.0)), driver_mesh(Color(0.8, 0.9, 1.0)), helmet_mesh(Color(0.8, 0.9, 1.0))]:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost_node.add_child(mi)
		(ghost_node.get_child(2) as Node3D).position = Vector3(0, 1.25, 0.32)
	ghost_node.visible = false


func _update_ghost(dt: float) -> void:
	# Host / local on today's track: record the leading human's run.
	if net.mode != "client" and state == "race" and Story.is_daily(track_desc):
		ghost_rec_t -= dt
		if ghost_rec_t <= 0.0:
			ghost_rec_t += 0.2
			var who = null
			for p in players:
				if p.active and not p.finished and (who == null or p.total > who.total):
					who = p
			if who != null and ghost_rec.size() < 3000:
				ghost_rec.append(who.position)
	var path := ghost_path
	var f := (race_t if state == "race" else 0.0) * 5.0
	if path.is_empty() and not lap_ghost.is_empty() and state == "race" and lap_ghost_t0 >= 0.0:
		path = lap_ghost  # the best lap on this track, starting with the leading person's lap
		f = (race_t - lap_ghost_t0) * 5.0
	if not path.is_empty() and ghost_node == null:
		_set_ghost(ghost_path)
	if ghost_node == null:
		return
	var show := not path.is_empty() and (state == "race" or (state == "countdown" and path == ghost_path))
	ghost_node.visible = show
	if not show:
		return
	var i := clampi(int(f), 0, path.size() - 1)
	var j := mini(i + 1, path.size() - 1)
	var a: Vector3 = path[i]
	var b: Vector3 = path[j]
	ghost_node.position = a.lerp(b, clampf(f - i, 0.0, 1.0))
	var dir := b - a
	if Vector2(dir.x, dir.z).length() > 0.05:
		ghost_node.rotation.y = lerp_angle(ghost_node.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-10.0 * dt))
	if i >= path.size() - 1:
		ghost_node.visible = false


## Results: a row of the tour's place pictures on every TV view (done ones bright, this one bouncing,
## dots for its three races). Pictures only.
func _show_tour_strips() -> void:
	_clear_tour_strips()
	if track_desc.is_empty() or Story.is_daily(track_desc):
		return
	if Story.is_cup(track_desc):
		_show_cup_strips()
		return
	var w := Story.where(int(track_desc[2]))
	var cur := int(w[0])
	var step := int(w[1])
	var tour := int(w[2])
	for p in players:
		if not (p.active and p.is_local() and p.hud != null and is_instance_valid(p.hud)):
			continue
		var row := HBoxContainer.new()
		row.name = "TourStrip"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var sc := clampf(p.hud.size.y / 540.0, 0.5, 1.4)
		row.add_theme_constant_override("separation", int(14 * sc))
		for i in Story.PLACES.size():
			var pl := Story.place(i)
			var col := VBoxContainer.new()
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.alignment = BoxContainer.ALIGNMENT_CENTER
			var done := tour > 0 or i < cur or (i == cur and step == Story.RACES_PER_PLACE - 1)
			var pic := StoryCard.picture(String(pl.pic), (84.0 if i == cur else 60.0) * sc, pl.color)
			pic.modulate = Color(1, 1, 1) if done or i == cur else Color(0.35, 0.35, 0.4, 0.8)
			col.add_child(pic)
			if i == cur:
				var dots := HBoxContainer.new()
				dots.alignment = BoxContainer.ALIGNMENT_CENTER
				dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
				for k in Story.RACES_PER_PLACE:
					var dot := UiKit.icon("dot", Color(1.0, 0.85, 0.3) if k <= step else Color(1, 1, 1, 0.3), 20.0 * sc)
					dots.add_child(dot)
				col.add_child(dots)
			elif i < Story.HATS.size() and i < hats_won:
				col.add_child(StoryCard.picture(String(Story.HATS[i][1]), 34.0 * sc, Story.HATS[i][2]))
			row.add_child(col)
		p.hud.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		row.position.y -= 24.0 * sc
		row.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tour_strips.append(row)


## Results in a cup: the four cups' pictures (a medal-coloured cup under the ones won at this speed), this one big
## with a dot for each of its three races. Pictures only.
func _show_cup_strips() -> void:
	var cur := int(track_desc[2])
	var r := int(track_desc[3])
	for p in players:
		if not (p.active and p.is_local() and p.hud != null and is_instance_valid(p.hud)):
			continue
		var row := HBoxContainer.new()
		row.name = "TourStrip"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var sc := clampf(p.hud.size.y / 540.0, 0.5, 1.4)
		row.add_theme_constant_override("separation", int(18 * sc))
		for i in Cups.CUPS.size():
			var cp := Cups.cup(i)
			var col := VBoxContainer.new()
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.alignment = BoxContainer.ALIGNMENT_CENTER
			var md := int(shelf.get(Cups.shelf_key(i, speed_mode), 0))
			var pic := StoryCard.picture(String(cp.pic), (84.0 if i == cur else 60.0) * sc, cp.color)
			pic.modulate = Color(1, 1, 1) if md > 0 or i == cur else Color(0.35, 0.35, 0.4, 0.8)
			col.add_child(pic)
			if i == cur:
				var dots := HBoxContainer.new()
				dots.alignment = BoxContainer.ALIGNMENT_CENTER
				dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
				for k in Cups.RACES:
					dots.add_child(UiKit.icon("dot", Color(1.0, 0.85, 0.3) if k <= r else Color(1, 1, 1, 0.3), 20.0 * sc))
				col.add_child(dots)
			elif md > 0:
				col.add_child(UiKit.icon("trophy", Cups.MEDAL_COLORS[md], 30.0 * sc))
			row.add_child(col)
		p.hud.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		row.position.y -= 24.0 * sc
		row.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tour_strips.append(row)


func _clear_tour_strips() -> void:
	for r in tour_strips:
		if is_instance_valid(r):
			r.queue_free()
	tour_strips.clear()


# --- Bolt's cups, the pit stop, the garage, Bolt's trophy shelf and the best-lap ghost ------------------

func mode_info() -> Dictionary:
	return Cups.mode(speed_mode)


func _world() -> int:
	return int(save.data["world"]) if save != null else 0


## Host: what comes after the race just run ([] = the pit stop): the next race of the cup / tour place.
func _series_next() -> Array:
	if save == null or track_desc.is_empty() or Story.is_daily(track_desc):
		return []
	if Story.is_cup(track_desc):
		var r := int(track_desc[3])
		return Cups.desc(_world(), int(track_desc[2]), r + 1, speed_mode) if r < Cups.RACES - 1 else []
	var w := Story.where(int(track_desc[2]))
	if int(w[1]) >= Story.RACES_PER_PLACE - 1:
		return []
	return Story.story_desc(_world(), int(save.data["story_i"]))


## The gates' rows (pit.gd): karts (+ the spanner once a part is unlocked), speeds, then the tour and the cups.
func _pit_rows() -> Array:
	var karts_row: Array = [["light", "kartsmall", Color(0.45, 0.85, 1.0)], ["medium", "kart", Color(1.0, 0.75, 0.3)],
		["heavy", "kartbig", Color(1.0, 0.45, 0.35)]]
	if not Cups.parts_unlocked(shelf).is_empty():
		karts_row.append(["part", "spanner", Color(0.75, 0.6, 1.0)])
	var speeds: Array = [["gentle", "snail", Color(0.55, 0.9, 0.5)], ["zoom", "rocket", Color(1.0, 0.4, 0.3)], ["trial", "clock", Color(0.5, 0.75, 1.0)]]
	var cups_row: Array = [["tour", "boltbot", Color(0.55, 0.75, 1.0)]]
	for c in Cups.CUPS.size():
		cups_row.append([str(c), String(Cups.cup(c).pic), Cups.cup(c).color])
	return [{"kind": "kart", "lanes": karts_row}, {"kind": "speed", "lanes": speeds}, {"kind": "cup", "lanes": cups_row}]


## Host: the PIT STOP on the track just raced: everyone back on the grid, the CPUs step aside, drive through gates.
func _start_pit() -> void:
	state = "pit"
	state_t = 0.0
	race_t = 0.0
	_clear_trophies()
	_clear_tour_strips()
	_set_ghost([])
	set_lights(0)
	_show_center("", 0.0)
	for c in cpus:
		c.set_active(false)
	var slot := 0
	for k in players:
		if not k.active:
			continue
		k.reset_race()
		k.grid_slot = slot
		var g: Array = track.grid_point(slot)
		_teleport(k, g[0], g[1], g[3])
		k.hold_still = false
		slot += 1
	pit_rows = _pit_rows()
	pit.start(pit_rows)
	pits_done += 1
	story({"who": "PIT STOP!", "line": "Drive through a picture!", "pic": "spanner", "color": BOLT_COLOR, "duration": 3.5})
	print("Pit stop %d: %d people pick karts, speed and a cup at the picture gates" % [pits_done, slot])


## Host: someone drove through a gate.
func pit_pick(k, kind: String, id: String, ri: int, lane: int) -> void:
	pit.flash(ri, lane)
	net.event("pit_flash", [ri, lane])
	kart_sound(k, "pick", -3.0, 1.0 + 0.1 * ri)
	burst(k.position + Vector3(0, 1.6, 0), (pit_rows[ri].lanes[lane][2] as Color), 14)
	if kind == "kart":
		var cls: String = k.kart_class
		var part: String = k.part
		if id == "part":
			part = Cups.next_part(part, shelf)
		else:
			cls = id
		k.set_kart(cls, part)
		_save_garage(k)
	print("Pit: %s picks %s %s" % [k.kart_name, kind, id])


## Host: the pit stop is over: the votes decide the speed and the cup (nobody voted: same speed, the next cup).
func _pit_done() -> void:
	var m := pit.winner("speed")
	if m != "":
		speed_mode = m
	var c := pit.winner("cup")
	if c == "":
		var after := int(series.get("cup", -1))
		c = str(Cups.next_cup(shelf, speed_mode if speed_mode != "trial" else "gentle", after))
	if save != null:
		save.data["mode"] = speed_mode
		save.mark_dirty()
	if c == "tour":
		series = {"kind": "tour"}
		track_desc = Story.story_desc(_world(), int(save.data["story_i"]) if save != null else 0)
	else:
		series = {"kind": "cup", "cup": int(c), "pts": {}}
		track_desc = Cups.desc(_world(), int(c), 0, speed_mode)
	print("Pit stop done: %s at %s speed" % ["the tour" if c == "tour" else String(Cups.cup(int(c)).name), speed_mode])
	_start_race(track_i + 1)


# --- The garage: each seat's kart and part, saved ---

func _load_garage() -> void:
	if save == null:
		return
	var g: Dictionary = save.data.get("garage", {})
	for p in players:
		var e: Variant = g.get(str(p.index), {})
		if e is Dictionary:
			p.set_kart(String((e as Dictionary).get("cls", "medium")), String((e as Dictionary).get("part", "")))
	shelf = (save.data.get("shelf", {}) as Dictionary).duplicate()
	speed_mode = String(save.data.get("mode", "gentle"))
	if not Cups.MODES.has(speed_mode):
		speed_mode = "gentle"
	if OS.has_environment("KART_MODE"):
		speed_mode = OS.get_environment("KART_MODE")


func _save_garage(k) -> void:
	if save == null:
		return
	var g: Dictionary = save.data.get("garage", {})
	g[str(k.index)] = {"cls": k.kart_class, "part": k.part}
	save.data["garage"] = g
	save.mark_dirty()


## A cosmetic kart part (cups.gd PARTS), built in the kart body's space (-Z forward, +Z back, y up).
func part_model(part: String, col: Color) -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match part:
		"spoiler":
			add_box(st, Vector3(0, 1.05, 1.0), Vector3(1.5, 0.08, 0.35), col.darkened(0.3))
			for x in [-0.45, 0.45]:
				add_box(st, Vector3(x, 0.82, 0.95), Vector3(0.08, 0.4, 0.12), Color(0.25, 0.25, 0.3))
		"flag":
			add_cyl(st, Vector3(-0.6, 1.3, 0.85), 0.03, 1.6, Color(0.85, 0.85, 0.9))
			for i in 6:
				var c := Color(0.1, 0.1, 0.12) if (i % 2 == int(i / 3.0) % 2) else Color(1, 1, 1)
				add_box(st, Vector3(-0.6 - 0.12 - (i % 3) * 0.2, 1.95 - int(i / 3.0) * 0.2, 0.85), Vector3(0.2, 0.2, 0.02), c)
		"duck":
			add_ellipsoid(st, Vector3(0, 0.7, -1.05), Vector3(0.22, 0.17, 0.26), Color(1.0, 0.88, 0.2), 8, 5)
			add_ellipsoid(st, Vector3(0, 0.92, -1.18), Vector3(0.14, 0.14, 0.14), Color(1.0, 0.88, 0.2), 8, 5)
			add_ellipsoid(st, Vector3(0, 0.9, -1.33), Vector3(0.07, 0.04, 0.08), Color(1.0, 0.55, 0.15), 6, 3)
		"crown":
			add_cyl(st, Vector3(0, 0.72, -0.95), 0.2, 0.14, Color(1.0, 0.82, 0.2))
			for i in 5:
				var a := TAU * i / 5.0
				add_ellipsoid(st, Vector3(cos(a) * 0.18, 0.86, -0.95 + sin(a) * 0.18), Vector3(0.05, 0.1, 0.05), Color(1.0, 0.82, 0.2), 5, 3)
		"flames":
			for side in [-1.0, 1.0]:
				for i in 3:
					var z := -0.5 + i * 0.35
					add_box(st, Vector3(0.82 * side, 0.45, z), Vector3(0.03, 0.16, 0.42 - i * 0.1), [Color(1.0, 0.3, 0.15), Color(1.0, 0.6, 0.15), Color(1.0, 0.9, 0.3)][i])
		"balloon":
			add_cyl(st, Vector3(0.5, 1.4, 0.9), 0.01, 1.4, Color(0.9, 0.9, 0.9))
			add_ellipsoid(st, Vector3(0.5, 2.35, 0.9), Vector3(0.32, 0.38, 0.32), col.lightened(0.2), 10, 6)
	var mi := MeshInstance3D.new()
	mi.name = "Part_" + part
	mi.mesh = _commit(st)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.4
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Hazards (track.gd / kart.gd call these on the machine that drives the kart) ---

func on_hazard(k, kind: String) -> void:
	if k.cpu:
		return
	match kind:
		"slow":
			sound("squelch", -4.0, randf_range(0.9, 1.1))
			rumble(k, 0.3, 0.2)
		"ice":
			sound("tinkle", -6.0, randf_range(0.9, 1.2))
		"float":
			sound("boing", -3.0, 1.0)
			burst(k.position + Vector3(0, 0.3, 0), Color(0.8, 0.5, 1.0), 10, false)
		"bump":
			sound("bonk", -3.0, randf_range(0.9, 1.15))
			rumble(k, 0.5, 0.15)
		"smash":
			sound("pop", -2.0, 0.8)
			burst(k.position + k.forward() * 1.5 + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.4), 16, false)
		"tough":
			sound("shield", -8.0, 1.4)
	if net.mode == "client" and k.is_local() and kind != "tough" and kind != "smash":
		net.send_action("stat", ["hazard"], k.index)


# --- Cups: points over three races, a medal for Bolt's shelf ---

## Host, after each race of a cup: points; after the third, the cup's trophies (by points) and the medal.
## Returns the karts in cup order after the third race ([] otherwise).
func _cup_after_race(order: Array) -> Array:
	if not Story.is_cup(track_desc):
		return []
	var pts: Dictionary = series.get("pts", {})
	for k in order:
		pts[k.index] = int(pts.get(k.index, 0)) + (Cups.points(k.place) if k.finished or k.cpu else 1)
	series["pts"] = pts
	if int(track_desc[3]) < Cups.RACES - 1:
		return []
	var standing: Array = order.duplicate()
	standing.sort_custom(func(a, b) -> bool:
		var pa := int(pts.get(a.index, 0))
		var pb := int(pts.get(b.index, 0))
		return pa > pb or (pa == pb and a.place < b.place))
	return standing


## Host: the cup is won: the best person's cup place gives the medal; the shelf keeps the best one, and every new
## medal unlocks the next kart part. Returns the story beats.
func _cup_medal(standing: Array) -> Array:
	var beats: Array = []
	var c := int(track_desc[2])
	var cp := Cups.cup(c)
	var best_place := 99
	for i in standing.size():
		if not standing[i].cpu:
			best_place = i + 1
			break
	var md := Cups.medal_for(best_place, speed_mode)
	last_medal = md
	if md <= 0:
		beats.append({"who": String(cp.name), "line": "Try again!", "pic": String(cp.pic), "color": (cp.color as Color).to_html(false), "duration": 3.0})
		return beats
	var key := Cups.shelf_key(c, speed_mode)
	var parts_before := Cups.parts_unlocked(shelf).size()
	var had := int(shelf.get(key, 0))
	beats.append({"who": "%s CUP!" % Cups.MEDALS[md], "line": String(cp.done), "pic": "trophy", "color": Cups.MEDAL_COLORS[md].to_html(false),
		"duration": 3.5})
	if md > had:
		shelf[key] = md
		if save != null:
			save.data["shelf"] = shelf.duplicate()
			save.mark_dirty()
		beats.append({"who": "BOLT", "line": "On my shelf it goes!", "pic": "shelf", "color": BOLT_COLOR, "duration": 3.0})
		var un := Cups.parts_unlocked(shelf)
		if un.size() > parts_before:
			var part: String = un[-1]
			beats.append({"who": "NEW PART!", "line": "Drive through the spanner!", "pic": String(Cups.PART_PICS[part]), "color": "c39bff",
				"duration": 3.5})
	if save != null:
		save.data["cups"] = int(save.data.get("cups", 0)) + 1
		save.mark_dirty()
	return beats


# --- Bolt's trophy shelf: by the start line on every track ---

func _update_shelf() -> void:
	var key := "%d/%s" % [track.build_n, var_to_str(shelf)]
	if key == shelf_key and shelf_node != null:
		Shelf.wave(shelf_node)
		return
	shelf_key = key
	if shelf_node != null:
		shelf_node.queue_free()
	shelf_node = Shelf.build(self, shelf)
	add_child(shelf_node)
	var p: Array = track.point_at(9.0, -(track.wall_at(9.0) + 2.8))
	shelf_node.position = p[0]
	shelf_node.rotation.y = float(p[1]) + PI * 0.5  # faces the road


# --- The best-lap ghost (every track, saved per track) ---

## Host: record each person's lap from the line; a lap faster than the saved best becomes the new ghost.
func _record_laps(dt: float) -> void:
	if net.mode == "client" or state != "race" or track_desc.is_empty():
		return
	lap_tick -= dt
	var sample := lap_tick <= 0.0
	if sample:
		lap_tick += 0.2
	var L: float = track.length
	for k in players:
		if not k.active or k.finished or k.total < 0.0:
			continue
		var n := int(floorf(k.total / L))
		var rec: Dictionary = lap_rec.get(k.index, {})
		if rec.is_empty() or n != int(rec.n):
			if not rec.is_empty() and n == int(rec.n) + 1:
				_lap_done(k, race_t - float(rec.t0), rec.path)
			rec = {"t0": race_t, "n": n, "path": []}
			lap_rec[k.index] = rec
		if sample and (rec.path as Array).size() < 900:
			(rec.path as Array).append(k.position)
	# The lap ghost runs with the leading person's lap.
	var lead = null
	for k in players:
		if k.active and not k.finished and lap_rec.has(k.index) and (lead == null or k.total > lead.total):
			lead = k
	var t0 := float(lap_rec[lead.index].t0) if lead != null else -1.0
	if t0 != lap_ghost_t0:
		lap_ghost_t0 = t0


func _lap_done(k, t: float, path: Array) -> void:
	if save == null or path.size() < 10:
		return
	var laps_d: Dictionary = save.data.get("laps", {})
	var best: Variant = laps_d.get(track.key, {})
	var bt := float((best as Dictionary).get("t", 0.0)) if best is Dictionary else 0.0
	print("%s lap: %.1f s (best %.1f)" % [k.kart_name, t, bt])
	if bt > 0.0 and t >= bt:
		return
	laps_d[track.key] = {"t": snappedf(t, 0.01), "g": path.duplicate(), "d": Seeded.today()}
	# Keep the 30 newest tracks' best laps.
	while laps_d.size() > 30:
		var oldest := ""
		for key in laps_d:
			if oldest == "" or String((laps_d[key] as Dictionary).get("d", "")) < String((laps_d[oldest] as Dictionary).get("d", "")):
				oldest = key
		laps_d.erase(oldest)
	save.data["laps"] = laps_d
	save.mark_dirty()
	if bt > 0.0:
		story({"who": "BEST LAP!", "line": "%.1f seconds!" % t, "pic": "clock", "color": "8cd2ff", "duration": 2.5})


## Host at the countdown: this track's best lap (if any) as the ghost to race (unless today's run ghost is on).
func _start_lap_ghost() -> void:
	lap_ghost = []
	if save == null or not ghost_path.is_empty():
		net.event("lapghost", [[]])
		return
	var best: Variant = (save.data.get("laps", {}) as Dictionary).get(track.key, {})
	if best is Dictionary:
		lap_ghost = ((best as Dictionary).get("g", []) as Array).duplicate()
	net.event("lapghost", [lap_ghost])


# --- Simple mode: practice rings, instant ? boxes, the finish party -------------------------

## Race 1 is just driving; the ? boxes come out from race 2.
func boxes_live() -> bool:
	return not SIMPLE_MODE or (round_n >= 2 and bool(mode_info().boxes) and state != "pit")


func _start_practice() -> void:
	practice_gate = 0
	practice_t = 0.0
	_show_center("", 0.0)
	print("Practice: drive through %d glowing rings" % PRACTICE_GATES.size())


func gate_pos(i: int) -> Array:
	return track.point_at(PRACTICE_GATES[clampi(i, 0, PRACTICE_GATES.size() - 1)], 0.0)


## Host / local: a driver goes through the glowing ring -> it pops and the next one appears.
## After the last one everyone lines up for 3-2-1 GO.
func _practice_update(dt: float) -> void:
	practice_t += dt
	var gp: Array = gate_pos(practice_gate)
	var c: Vector3 = gp[0]
	var yaw: float = gp[1]
	var tg := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rt := Vector3(-tg.z, 0.0, tg.x)
	var hit = null
	for p in players:
		if not p.active:
			continue
		var d: Vector3 = p.position - c
		if absf(d.dot(tg)) < 2.2 and absf(d.dot(rt)) < 6.5 and absf(d.y) < 3.0:
			hit = p
			break
	if hit != null:
		for col in [Color(1.0, 0.3, 0.4), Color(0.3, 0.8, 1.0), Color(1.0, 0.9, 0.3)]:
			burst(c + Vector3(0, 3.0, 0), col, 14)
		sound("lap", -2.0, 1.0 + 0.15 * practice_gate, true)
		rumble(hit, 0.4, 0.15)
		track.excite(0.7)
		net.event("excite", [0.7])
		practice_gate += 1
		print("Practice: ring %d by %s" % [practice_gate, hit.kart_name])
	if practice_gate >= PRACTICE_GATES.size() or practice_t > PRACTICE_MAX:
		print("Practice done (%.0f s): line up for the race" % practice_t)
		practice_gate = -1
		if OS.has_environment("KART_PIT"):  # WHAT'S NEW "try" / tests: straight to the pit stop's picture gates
			_start_pit()
		else:
			_start_race(0)


## Every machine: the glowing ring (and a bouncing arrow over it) for the practice.
func _update_gate(dt: float) -> void:
	var want := practice_gate if SIMPLE_MODE and state == "wait" else -1
	if want < 0:
		if gate_node != null:
			gate_node.visible = false
		gate_shown = -1
		return
	if gate_node == null:
		gate_node = Node3D.new()
		add_child(gate_node)
		gate_mat = StandardMaterial3D.new()
		gate_mat.emission_enabled = true
		gate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 4.3
		tm.outer_radius = 5.0
		tm.rings = 32
		tm.ring_segments = 8
		ring.mesh = tm
		ring.material_override = gate_mat
		ring.rotation.x = PI * 0.5
		ring.position.y = 3.4
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gate_node.add_child(ring)
		var arrow := MeshInstance3D.new()
		arrow.name = "Arrow"
		arrow.mesh = cyl_mesh(0.9, 0.0, 1.5, 12)
		arrow.material_override = make_material(Color(1.0, 0.9, 0.2), 1.5)
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gate_node.add_child(arrow)
	if want != gate_shown or track.build_n != gate_track:
		gate_shown = want
		gate_track = track.build_n
		var gp: Array = gate_pos(want)
		gate_node.position = gp[0]
		gate_node.rotation = Vector3(0, float(gp[1]), 0)
		gate_node.scale = Vector3.ONE * 0.2  # pops in
	gate_node.visible = true
	gate_node.scale = gate_node.scale.lerp(Vector3.ONE, 1.0 - exp(-6.0 * dt))
	var ms := Time.get_ticks_msec()
	var col := Color.from_hsv(fmod(ms * 0.0002, 1.0), 0.55, 1.0)
	gate_mat.albedo_color = col
	gate_mat.emission = col
	gate_mat.emission_energy_multiplier = 1.5 + 1.5 * sin(ms * 0.008)
	var arrow := gate_node.get_node("Arrow") as Node3D
	arrow.position = Vector3(0, 9.6 + 0.6 * sin(ms * 0.006), 0)
	arrow.rotation.y = ms * 0.002


## A ? box in simple mode: an instant power-up, no buttons (items.gd: fair by place, catch-up at the back). Race 2
## only zooms and bubbles; from race 3 the whole set.
func _simple_box(k) -> void:
	var it := Items.pick(Items.weights(Items.behind_of(k.place, racer_count()), not k.cpu, speed_mode), randf())
	if round_n < 3 and it != "zoom" and it != "bubble":
		it = "zoom"
	if OS.has_environment("KART_ITEM"):  # tests: one item every time
		it = OS.get_environment("KART_ITEM")
	_apply_item(k, it)


func _apply_item(k, it: String) -> void:
	match it:
		"star":
			k.star_t = STAR_TIME
			if k.remote:
				net.event("star", [k.index, STAR_TIME])
			kart_sound(k, "star", -2.0)
			burst(k.position + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.3), 18)
		"triple":
			k.triple_left = 3
			k.triple_t = 0.0
			if k.remote:
				net.event("triple", [k.index])
		"bubble":
			k.shield_t = SHIELD_TIME
			if k.remote:
				net.event("shield", [k.index, SHIELD_TIME])
			kart_sound(k, "shield", -2.0)
		"banana":
			var p: Vector3 = k.position - k.forward() * 2.6
			p.y = k.position.y
			bananas.append([p, 0.0, k.index])
			kart_sound(k, "drop", -2.0)
		"honk":
			_honk(k)
		"rocket":
			k.rocket_t = Items.ROCKET_TIME
			if k.remote:
				net.event("rocket", [k.index])
			kart_sound(k, "rocket", -2.0)
			burst(k.position + Vector3(0, 0.6, 0) - k.forward() * 1.4, Color(1.0, 0.6, 0.2), 16)
		_:
			it = "zoom"
			if k.remote:
				net.event("boost", [k.index, MUSHROOM_TIME])
			else:
				k.boost(MUSHROOM_TIME)
			on_boost(k, "")
	items_given[it] = true
	_item_pop(k, it)
	k.st_items += 1
	k.set_meta("uses", int(k.get_meta("uses", 0)) + 1)


## A picture of the power-up pops up on that driver's view for a moment (no words).
func _item_pop(k, it: String) -> void:
	if k.cpu:
		return
	if k.remote:
		net.event("pop", [k.index, it])
		return
	k.set_meta("pop", it)
	k.set_meta("pop_t", 1.8)


## Every machine: the power-up picture on each local view (top middle, under the lap / place).
func _update_item_pop(p, dt: float) -> void:
	var pop = p.hud.get_node_or_null("ItemPop") if p.hud != null else null
	var t: float = p.get_meta("pop_t", 0.0)
	if t > 0.0:
		p.set_meta("pop_t", t - dt)
	var want := String(p.get_meta("pop", "")) if t > 0.0 else ""
	if pop != null and String(pop.get_meta("kind", "")) != want:
		pop.queue_free()
		pop = null
	if want == "" or pop != null:
		return
	var sc := clampf(p.hud.size.y / 540.0, 0.5, 1.4)
	pop = StoryCard.picture(String(Items.PICS.get(want, "star")), 96.0 * sc, Items.COLORS.get(want, Color(1, 0.8, 0.3)))
	pop.name = "ItemPop"
	pop.set_meta("kind", want)
	p.hud.add_child(pop)
	pop.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pop.position.y += 70.0 * sc


## The finish party: trophies float over the top three, confetti, one headline.
func _simple_results(order: Array) -> void:
	trophy_karts.clear()
	var standing := _cup_after_race(order)  # the cup's last race: the trophies go to the top three on points
	var cup_beats := _cup_medal(standing) if not standing.is_empty() else []
	var podium: Array = standing if not standing.is_empty() else order
	for j in mini(3, podium.size()):
		trophy_karts.append(karts.find(podium[j]))
	_show_trophies(trophy_karts)
	net.event("trophies", [trophy_karts])
	var w = podium[0] if not podium.is_empty() else null
	results_text = "%s WINS!" % w.kart_name if w != null else ""
	var me = players[0]
	vr_results = "FINISH! %s" % ordinal(me.place) if me.active else results_text
	_show_center(results_text, 0.0)
	if w != null:
		for c in [Color(1.0, 0.3, 0.4), Color(0.3, 0.8, 1.0), Color(1.0, 0.9, 0.3), w.color]:
			burst(w.position + Vector3(0, 2.5, 0), c, 16)
	sound("finish", 0.0, 1.2, true)
	sound("trophy", 0.0, 1.0, true)
	track.excite(1.0)
	net.event("excite", [1.0])
	var row: Array[String] = []
	for k in order:
		row.append("%s %s" % [ordinal(k.place), k.kart_name])
	print("Results: " + " | ".join(row))
	if not standing.is_empty():
		var cr: Array[String] = []
		for k in standing:
			cr.append("%s %d" % [k.kart_name, int((series.get("pts", {}) as Dictionary).get(k.index, 0))])
		print("Cup results (%s, %s): %s; medal %s" % [Cups.cup(int(track_desc[2])).name, speed_mode, " | ".join(cr), Cups.MEDALS[last_medal]])
	_story_after_race(order, cup_beats)
	_show_tour_strips()


## TV view in simple mode: place (big, top right) and lap (top left); short headlines only.
func _update_simple_hud(p, dt: float) -> void:
	var racing := state == "race" or state == "countdown"
	p.hud_label.text = lap_text(p) if racing else ""
	# The place: top right while racing, but never under a big centre headline (3-2-1, GO!) - in a 2x2
	# grid the screen centre is the corner of every view. On the finish party it moves to the middle
	# of the view, clear of "X WINS!".
	var headline: bool = center_label.text != "" and center_label.modulate.a > 0.05
	var res := state == "results"
	p.place_label.text = ordinal(p.place) if (state == "race" and not headline) or res else ""
	var sz: Vector2 = p.hud.size
	var ui := clampf(minf(sz.x / 940.0, sz.y / 900.0), 0.5, 1.0)
	var pw := 260.0 * ui
	p.place_label.position = Vector2((sz.x - pw) * 0.5, sz.y * 0.3) if res else Vector2(sz.x - pw - 16.0, 6.0)
	p.place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if res else HORIZONTAL_ALIGNMENT_RIGHT
	p.item_label.visible = false
	p.hud.get_node("BarBg").visible = false
	p.hud.get_node("DriftBg").visible = false
	if p.minimap != null:
		p.minimap.visible = false
	var h := _hint_for(p, dt)
	# "LAP 2": the lap counter (top left) grows and glows instead of a second copy in the middle.
	var lp := 0.0
	if h.begins_with("LAP "):
		lp = clampf(float(p.get_meta("hint_t", 0.0)) / 2.2, 0.0, 1.0)
		h = ""
	p.hud_label.pivot_offset = Vector2.ZERO
	p.hud_label.scale = Vector2.ONE * (1.0 + 0.7 * lp)
	p.hud_label.modulate = Color.WHITE.lerp(Color(1.0, 0.95, 0.4), lp)
	if p.finished and state == "race":
		h = "FINISH!"
	p.hint_label.text = h
	_update_cue(p, p.hint_label)
	_update_item_pop(p, dt)


# --- Simple mode picture cues (no words) ----------------------------------------------------

## Which picture cue this TV player needs right now, or "" for nothing. "go" and "steer" go away
## after the player has done them twice; the wrong-way arrow shows whenever they're going backwards.
func _simple_cue(p) -> String:
	if not p.active or p.finished or get_tree().paused:
		return ""
	if net.mode == "client" and not synced:
		return ""
	if state == "race" and p.wrong_t > 1.5:
		return "wrong_go" if p.wrong_dir == 0.0 else ("wrong_l" if p.wrong_dir > 0.0 else "wrong_r")
	if state != "wait" and state != "countdown" and state != "race":
		return ""
	var go := _cue_if_new(p, "go")
	if go != "":
		return go
	if state != "countdown":
		return _cue_if_new(p, "steer")
	return ""


func _cue_if_new(p, key: String) -> String:
	var done: Dictionary = p.get_meta("cue_done", {})
	return key if int(done.get(key, 0)) < 2 else ""


## Every local human (TV views and the VR driver): count what they've done so the cues can go away.
## Go: two presses (or holding it down for a while). Steer: turning one way and then the other (or a
## good long turn).
func _track_cues(k, dt: float) -> void:
	if get_tree().paused or not (state == "wait" or state == "countdown" or state == "race"):
		return
	var done: Dictionary = k.get_meta("cue_done", {})
	var go_on: bool = k.throttle > 0.5
	if go_on and not bool(k.get_meta("go_was", false)):
		done["go"] = int(done.get("go", 0)) + 1
	k.set_meta("go_was", go_on)
	if go_on and state != "countdown":
		var ht: float = float(k.get_meta("go_hold", 0.0)) + dt
		k.set_meta("go_hold", ht)
		if ht > 2.5:
			done["go"] = maxi(2, int(done.get("go", 0)))
	if state != "countdown" and absf(k.speed) > 1.0:
		var sd := 0
		if k.steer > 0.5:
			sd = 1
		elif k.steer < -0.5:
			sd = -1
		if sd != 0 and sd != int(k.get_meta("steer_last", 0)):
			k.set_meta("steer_last", sd)
			done["steer"] = int(done.get("steer", 0)) + 1
		if sd != 0:
			var st: float = float(k.get_meta("steer_hold", 0.0)) + dt
			k.set_meta("steer_hold", st)
			if st > 3.0:
				done["steer"] = maxi(2, int(done.get("steer", 0)))
	k.set_meta("cue_done", done)


## The go button in the player's own controls.
func _cue_button(p, key: String) -> String:
	var b: String = CUES[key][0]
	if b == "A" and p.joy < 0:
		return "UP" if p.key_set == KartScript.KEYS_ARROWS else "W"
	return b


## The picture cue in the middle of a TV view: a glowing pad button and an icon, gently pulsing.
## Steering shows two arrows that sway in turn; wrong way a big red arrow the way to turn. It lives
## inside the hint label (hidden while that shows FINISH!), so it follows its layout.
func _update_cue(p, l: Label) -> void:
	var key := _simple_cue(p) if l.text == "" else ""
	p.set_meta("cue", key)
	# Low in the view (about two thirds down), below the road ahead, the rings and the karts' tags.
	var drop: float = maxf(0.0, p.hud.size.y * 0.66 - l.position.y)
	var box: HBoxContainer = l.get_node_or_null("Cue")
	if box == null:
		box = HBoxContainer.new()
		box.name = "Cue"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 18)
		l.add_child(box)
		UiKit.pin(box, Control.PRESET_FULL_RECT, false)
		box.set_meta("key", "")
	box.offset_top = drop
	box.offset_bottom = drop
	var s := clampf(float(l.get_theme_font_size("font_size")) / 44.0, 0.5, 1.2) * 1.6
	var btn := _cue_button(p, key) if key != "" else ""
	var sig := "%s/%s" % [key, btn]
	if str(box.get_meta("key")) != sig or absf(float(box.get_meta("s", 0.0)) - s) > 0.01:
		box.set_meta("key", sig)
		box.set_meta("s", s)
		for c in box.get_children():
			c.queue_free()
		if key != "":
			var cue: Array = CUES[key]
			if btn != "":
				box.add_child(UiKit.glyph(btn, s))
			var big := 1.8 if key.begins_with("wrong") else 1.0
			for k in cue[1]:
				box.add_child(UiKit.icon(str(k), cue[2], 40.0 * s * big))
			for c in box.get_children():
				(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER  # a round A, not a tall pill
	box.visible = key != ""
	if box.visible:
		var t := Time.get_ticks_msec() / 1000.0
		var fast := key.begins_with("wrong")
		var k := absf(sin(t * (7.0 if fast else 3.5)))
		box.modulate = Color(1, 1, 1, 0.75 + 0.25 * k)
		var i := 0
		for c in box.get_children():
			var ctl := c as Control
			ctl.pivot_offset = ctl.size * 0.5
			ctl.scale = Vector2.ONE * (1.0 + 0.15 * k)
			if key == "steer":  # the arrows wave left, then right
				ctl.scale = Vector2.ONE * (1.0 + 0.35 * maxf(0.0, sin(t * 3.0 + i * PI)))
			i += 1


# --- Items, bananas, bumps ------------------------------------------------------------------

func notify(k, text: String) -> void:
	if SIMPLE_MODE and text != "FINISH!" and not (text.begins_with("LAP ") and text.length() <= 6):
		return  # simple mode: only the short headlines (pictures say the rest)
	if k.remote:
		net.event("notify", [k.index, text])
		return
	k.set_meta("hint", text)
	k.set_meta("hint_t", 2.2)


func _check_boxes() -> void:
	if not boxes_live():
		return
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
	if SIMPLE_MODE:
		_simple_box(k)
		return
	k.charge = minf(1.0, k.charge + 0.2)
	if k.item != "":
		kart_sound(k, "box", -8.0, 0.8)
		return
	var n := maxi(1, racer_count() - 1)
	var behind := clampf(float(k.place - 1) / n, 0.0, 1.0)
	# Karts at the back get the zoomy things, the leaders get bananas and shields.
	var weights := {"mushroom": 14.0 + 36.0 * behind, "triple": 3.0 + 22.0 * behind, "star": 1.0 + 15.0 * behind,
		"banana": 40.0 - 28.0 * behind, "shield": 24.0, "honk": 14.0}
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var r := randf() * total
	var it := "banana"
	for key in weights:
		r -= float(weights[key])
		if r <= 0.0:
			it = key
			break
	k.item = it
	k.item_count = 3 if it == "triple" else 1
	k.item_hold_t = 0.0
	kart_sound(k, "box", -2.0, 1.0)
	if not k.cpu:
		var how := "press A" if k.cockpit != null else "press X"
		notify(k, "%s! %s" % [ITEM_NAMES[it], how])
		_tip(k, "item", "")


func use_item(k) -> void:
	var it: String = k.item
	if it == "":
		return
	if net.mode == "client" and k.is_local():
		if it == "mushroom" or it == "triple":
			k.boost(MUSHROOM_TIME)
			sound("boost", -2.0)
		elif it == "star":
			k.star_t = STAR_TIME
			sound("star", -2.0)
		net.send_action("use", [it], k.index)
		k.item_count -= 1
		if k.item_count <= 0:
			k.item = ""
		return
	_do_use(k, it)


func _do_use(k, it: String) -> void:
	k.item_count -= 1
	if k.item_count <= 0:
		k.item = ""
	k.st_items += 1
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
		"mushroom", "triple":
			if k.remote:
				net.event("boost", [k.index, MUSHROOM_TIME])
			else:
				k.boost(MUSHROOM_TIME)
			on_boost(k, "MUSHROOM ZOOM!" if it == "mushroom" or k.item_count <= 0 else "ZOOM! %d left" % k.item_count)
		"star":
			k.star_t = STAR_TIME
			if k.remote:
				net.event("star", [k.index, STAR_TIME])
			kart_sound(k, "star", -2.0)
			notify(k, "RAINBOW STAR! Nothing can stop you!")
			burst(k.position + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.3), 18)
		"honk":
			_honk(k)
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
	if k.star_t > 0.0:
		notify(k, "SQUISH! Stars beat bananas!")
		return
	k.st_hits += 1
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
		var holder := Node3D.new()
		holder.position = Vector3(0, 0.45, 0)
		b.add_child(holder)
		build_item_model(holder, "banana", 0.75)
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
			if o.star_t > 0.0 and a.star_t <= 0.0:
				strength = 9.0
			if a.cockpit != null:
				strength *= 0.4  # the VR rider gets nudged, not shoved
			if a.push_v.dot(nrm) < strength:
				a.push_v += nrm * (strength - maxf(0.0, a.push_v.dot(nrm)))
			if a.bump_cd <= 0.0:
				a.bump_cd = 0.5
				if a.cockpit == null:
					a.speed *= 0.92
				if o.star_t > 0.0 and a.star_t <= 0.0 and a.shield_t <= 0.0:
					a.wobble()
					o.st_bumps += 1
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
			on_boost(k, "" if SIMPLE_MODE else "BIG AIR! BOOST!")
			rumble(k, 0.5, 0.15)
			if net.mode == "client" and k.is_local():
				net.send_action("stat", ["air"], k.index)


## Drift sparks start: the first time, tell them what's going on.
func on_drift_start(k) -> void:
	if k.cpu:
		return
	_tip(k, "drift", "SPARKS! Keep turning... then straighten up for a MINI-TURBO!")


func on_drift_level(k, lvl: int) -> void:
	if k.cpu or k.remote:
		return
	sound("spark", -6.0, 0.9 + 0.25 * lvl)
	rumble(k, 0.15 + 0.1 * lvl, 0.06)


func on_mini_turbo(k, lvl: int) -> void:
	if k.cpu:
		return
	var nm: String = ["", "MINI-TURBO!", "SUPER TURBO!", "ULTRA TURBO!"][clampi(lvl, 0, 3)]
	notify(k, nm)
	if not k.remote:
		sound("turbo", -3.0, 0.9 + 0.12 * lvl)
		rumble(k, 0.3 + 0.1 * lvl, 0.15)
	burst(k.position + Vector3(0, 0.4, 0) + k.forward() * -1.2, k.SPARK_COLORS[clampi(lvl, 0, 3)], 10, net.mode != "client")
	if net.mode == "client" and k.is_local():
		net.send_action("stat", ["turbo"], k.index)


## The silly honk: every kart close by wobbles for a moment (shields and stars don't mind).
func _honk(k) -> void:
	kart_sound(k, "honk", 0.0, 1.0)
	sound("honk", -6.0, 0.8, true)
	burst(k.position + Vector3(0, 1.5, 0), Color(1.0, 0.5, 0.8), 18)
	var hit := 0
	for o in karts:
		if o == k or not o.active or o.finished:
			continue
		if o.position.distance_to(k.position) > HONK_RANGE:
			continue
		if o.shield_t > 0.0 or o.star_t > 0.0:
			continue
		hit += 1
		if o.remote:
			net.event("wobble", [o.index])
			o.wobble_t = 0.9
		else:
			o.wobble()
		if not o.cpu:
			notify(o, "HONK HONK! Wobble wobble!")
			kart_sound(o, "wobble", -2.0)
	notify(k, "HONK! %d wobbled!" % hit if hit > 0 else "HONK! (nobody close enough)")


## Show a "how to" tip to a human player once per game.
func _tip(k, key: String, text: String) -> void:
	var id := "%d/%s" % [k.index, key]
	if tips_shown.has(id):
		return
	tips_shown[id] = true
	if text != "":
		notify(k, text)


## One fun award per human for the race just finished: {kart: "NAME - why"}.
func _awards(order: Array) -> Dictionary:
	var humans: Array = []
	for k in order:
		if not k.cpu:
			humans.append(k)
	var out := {}
	var used := {}
	for k in humans:
		var got := ""
		var cands: Array = []
		if k.place == 1:
			cands.append(["SPEED DEMON", "won the race!"])
		if k.st_turbo >= 2:
			cands.append(["DRIFT STAR", "%d mini-turbos" % k.st_turbo])
		if k.st_air >= 2:
			cands.append(["SKY JUMPER", "%d big airs" % k.st_air])
		if k.worst_place - k.place >= 2:
			cands.append(["COMEBACK KID", "from %s to %s" % [ordinal(k.worst_place), ordinal(k.place)]])
		if k.st_bumps >= 1:
			cands.append(["STAR BOWLER", "bumped %d karts with a star" % k.st_bumps])
		if k.st_items >= 3:
			cands.append(["ITEM WIZARD", "used %d items" % k.st_items])
		if k.st_walls <= 1:
			cands.append(["SMOOTH DRIVER", "hardly touched a wall"])
		if k.st_hits >= 2:
			cands.append(["BANANA MAGNET", "slipped %d times (and laughed!)" % k.st_hits])
		for c in cands:
			var ca: Array = c
			if not used.has(ca[0]):
				got = "%s - %s" % [ca[0], ca[1]]
				used[ca[0]] = true
				break
		if got == "":
			got = "GOOD SPORT - raced all the way!"
		out[k] = got
	return out


## Gold, silver and bronze cups floating over the Grand Prix winners.
func _show_trophies(idx: Array) -> void:
	_clear_trophies()
	for j in idx.size():
		var root := Node3D.new()
		add_child(root)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var col: Color = TROPHY_COLORS[clampi(j, 0, 2)]
		add_cyl(st, Vector3(0, 0, 0), 0.3, 0.15, col.darkened(0.3))
		add_cyl(st, Vector3(0, 0.3, 0), 0.07, 0.45, col)
		add_ellipsoid(st, Vector3(0, 0.75, 0), Vector3(0.38, 0.32, 0.38), col)
		for x in [-1.0, 1.0]:
			add_ellipsoid(st, Vector3(float(x) * 0.4, 0.8, 0), Vector3(0.1, 0.18, 0.05), col)
		var mi := MeshInstance3D.new()
		mi.mesh = _commit(st)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.metallic = 0.6
		m.roughness = 0.25
		m.emission_enabled = true
		m.emission = col * 0.4
		mi.material_override = m
		root.add_child(mi)
		root.scale = Vector3.ONE * (1.6 - 0.2 * j)
		trophy_nodes.append(root)


func _clear_trophies() -> void:
	for t in trophy_nodes:
		if is_instance_valid(t):
			t.queue_free()
	trophy_nodes.clear()


func _update_trophies(dt: float) -> void:
	for j in trophy_nodes.size():
		if j >= trophy_karts.size():
			break
		var k = kart_by_index_in_karts(trophy_karts[j])
		var t := trophy_nodes[j]
		if k == null or not is_instance_valid(t):
			continue
		t.global_position = k.global_position + Vector3(0, 3.2 + 0.2 * sin(race_t * 2.0 + j), 0)
		t.rotation.y += dt * 1.5


func kart_by_index_in_karts(i: int):
	return karts[i] if i >= 0 and i < karts.size() else null


## Falling snow follows whoever this machine shows (the VR rider or the first TV kart).
func _follow_weather() -> void:
	for p in players:
		if p.active and p.is_sim():
			track.follow_weather(p.position)
			return


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
	# Each machine asks for its own karts ("join"); only the first one starts the race.
	if net.peer_count() > 1:
		return
	# (no "they joined" line: each seat's join says WHO, core/who.gd)
	if state == "wait" and SIMPLE_MODE and practice_gate >= 0:
		pass  # they join the practice rings; the race starts after the third one
	elif state == "wait":
		_start_race(cup_track())
	elif state == "results":
		_next_race()


## Host: one machine left: only its karts leave (and their seats become free).
func on_machine_left(peer: int) -> void:
	seats.machine_left(peer)


## A machine's kart leaves the race (its machine left).
func _seat_gone(p) -> void:
	if p.active:
		p.set_active(false)
		if net.peer_count() > 0 and not SIMPLE_MODE:
			_show_center(Who.left(Who.seat(self, p.index)), 1.5)


## Host: the LAST machine left (multi_machine games get this only then).
func on_client_left() -> void:
	seats.all_left()
	if not SIMPLE_MODE:
		_show_center(Who.left(net.last_left_name) + " - racing on with the CPU buddies", 2.5)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	index = seats.host_action(action, args, index)  # many machines: who drives which seat (core/classic_seats.gd)
	if index < 0:
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
				if not SIMPLE_MODE:
					_show_center(Who.left(Who.seat(self, p.index)), 1.5)
		"continue":
			_on_continue()
		"use":
			if p.active and args.size() > 0 and str(args[0]) == p.item and p.item != "":
				_do_use(p, p.item)
		"stat":
			if args.size() > 0:
				match str(args[0]):
					"air":
						p.st_air += 1
					"turbo":
						p.st_turbo += 1
					"hazard":
						p.st_hazards += 1
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, Who.paused_by(net.machine_name_of(net.sender_peer())))
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	var title := "PAUSED" if SIMPLE_MODE else "PAUSED\n" + who  # simple: no explaining sentence
	_show_center(title if paused else (results_text if state == "results" else ""), 0.0, false)
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
			k.boost_t > 0.0, k.slip_t > 0.0, k.speed, k.steer_s, k.finish_time,
			k.drift_level + 4 * (k.drift_dir + 1) + 16 * k.item_count, k.star_t > 0.0])
	var bn: Array = []
	for b in bananas:
		var ba: Array = b
		bn.append(ba[0])
	var head := Transform3D(Basis(), CockpitScript.EYE)
	if cockpit != null:
		head = cockpit.head_local()
	var looks: Array = []
	for k in karts:
		looks.append([k.kart_class, k.part])
	return [state, track_i, state_t, race_t, kd, bn, track.box_state(), head, round_n, laps, finish_frac,
		cup_i, cup_race, PackedInt32Array(cup_pts), practice_gate, track_desc, hats_won,
		speed_mode, looks, pit_rows, shelf, lap_ghost_t0]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 14:
		return
	var ti: int = s[1]
	var desc: Array = s[15] if s.size() > 15 else []
	var hw: int = int(s[16]) if s.size() > 16 else hats_won
	if desc != track_desc or not synced or (desc.is_empty() and ti != track.track_i):
		synced = true
		track_desc = desc
		hats_won = hw
		if desc.is_empty():
			track_i = ti
			track.build(ti)
			_apply_track_look()
		else:
			_build_desc()
		_relocate_local()
	elif hw != hats_won:
		hats_won = hw
		_apply_looks()
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
		var flags: int = d[13] if d.size() > 13 else 0
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
			k.net_drift = flags & 3
			k.net_drift_dir = ((flags >> 2) & 3) - 1
			k.net_star = bool(d[14]) if d.size() > 14 else false
			k.item_count = flags >> 4
		else:
			k.item = d[6]
			k.item_count = flags >> 4
			k.shield_t = 1.0 if bool(d[7]) else 0.0
	var bn: Array = s[5]
	bananas.clear()
	for p in bn:
		bananas.append([p, 0.0, -1])
	track.apply_box_state(s[6])
	var head: Transform3D = s[7]
	if players[0].ghost and players[0].head != null:
		players[0].head.transform = Transform3D(head.basis.orthonormalized(), head.origin)
	cup_i = s[11]
	cup_race = s[12]
	var cp: PackedInt32Array = s[13]
	cup_pts.resize(cp.size())
	for i in cp.size():
		cup_pts[i] = cp[i]
	practice_gate = int(s[14]) if s.size() > 14 else -1
	if s.size() > 21:  # Bolt's cups: the speed, every kart's class and part, the pit stop's gates, the shelf
		speed_mode = String(s[17])
		var looks: Array = s[18]
		for i in mini(looks.size(), karts.size()):
			var lk: Array = looks[i]
			karts[i].set_kart(String(lk[0]), String(lk[1]))
		pit_rows = s[19]
		shelf = s[20]
		lap_ghost_t0 = float(s[21])


## The track changed under the karts this machine drives: find them on the new one (keeps their distance).
func _relocate_local() -> void:
	for k in karts:
		if k.is_sim():
			k.hint = -1
			k.track_progress_reset()


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
			_show_center(args[0], args[1], false)
			if state == "results" or str(args[0]).begins_with("RACE OVER"):
				results_text = args[0]
		"race":
			track_i = args[0]
			laps = args[1]
			round_n = args[2]
			finish_frac = args[3]
			track_desc = args[4] if args.size() > 4 else []
			hats_won = int(args[5]) if args.size() > 5 else hats_won
			if track_desc.is_empty():
				track.build(track_i)
				_apply_track_look()
			else:
				_build_desc()
			_clear_tour_strips()
			_set_ghost([])
			_relocate_local()
			_clear_trophies()
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
			track.excite(1.0)
			for k in players:
				if k.active and k.is_local():
					k.hold_still = false
					_rocket(k)
		"lights":
			lights = args[0]
			track.set_lights(lights)
		"excite":
			track.excite(float(args[0]))
		"wobble":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.wobble()
		"star":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.star_t = float(args[1])
		"trophies":
			trophy_karts.clear()
			for v in args[0]:
				trophy_karts.append(int(v))
			_show_trophies(trophy_karts)
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
		"story":
			show_story(args[0])
		"ghost":
			_set_ghost(args[0])
		"race_hats":
			hats_won = int(args[0])
			_apply_looks()
			_show_tour_strips()
		"pit_flash":
			pit.flash(int(args[0]), int(args[1]))
		"lapghost":
			lap_ghost = args[0]
		"pop":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.set_meta("pop", String(args[1]))
				k.set_meta("pop_t", 1.8)
		"triple":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.triple_left = 3
				k.triple_t = 0.0
		"shield":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.shield_t = float(args[1])
		"rocket":
			var k = kart_by_index(int(args[0]))
			if k != null and k.is_local():
				k.rocket_t = Items.ROCKET_TIME
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
	center_label = HudKit.split_center(_make_label(42))  # a copy in each split view, never across the line
	layer.add_child(center_label)
	UiKit.pin(center_label, Control.PRESET_FULL_RECT, false)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	UiKit.pin(help_label, Control.PRESET_BOTTOM_WIDE, false)
	help_label.offset_top = -40
	help_label.offset_bottom = -8
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.visible = not SIMPLE_MODE  # simple mode: no controls wall
	help_label.text = "Controller: stick steer · A go · B brake (in a fast turn: DRIFT) · RB drift · X item · Y boost  ·  Keys P1: WASD (S in a turn drifts) + Space item, Shift boost  ·  P2: arrows + Ctrl item, . boost  ·  Spare controller: press A to join"


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
		if not SIMPLE_MODE:
			return "WRONG WAY! Turn around"
	if SIMPLE_MODE:  # no how-to texts: the rings, picture cues, red arrows and ghost hands show it
		return ""
	if k.cockpit != null and not k.cockpit.fake and k.cockpit.unheld_t > 2.5 and (state == "race" or state == "countdown") and not k.finished:
		return "Hold the wheel with both hands!"
	if state == "countdown" and round_n <= 2:
		return "Press GO on the last red light: ROCKET START!" if lights >= 2 else ""
	if state == "race" and race_t < 6.0 and round_n <= 1:
		return "Hold A to go!" if k.cockpit == null else "Pull the trigger to go!"
	if state == "race" and round_n <= 2 and race_t > 8.0 and race_t < 14.0:
		return "Hold B in a turn to DRIFT - sparks = turbo!" if k.cockpit == null else "Turn hard round bends for sparks = TURBO!"
	if state == "race" and k.charge >= 1.0 and k.item == "" and not k.finished and fmod(race_t, 8.0) < 2.0:
		return "BOOST READY! Press %s" % ("Y" if k.cockpit == null else "A")
	return ""


func _update_hud(p, dt: float) -> void:
	if net.mode == "client" and not synced:
		p.hud_label.text = "Syncing with the VR player…"
		return
	if not p.active:
		return
	if SIMPLE_MODE:
		_update_simple_hud(p, dt)
		return
	var st := lap_text(p) + "   " + TrackScript.track_name(track_i) + "\n%s  race %d/3  ·  %d pts" % [str(cup_info()["name"]), cup_race + 1, cup_points(p)]
	if state == "wait":
		st = "WARM-UP LAP\nWaiting for the race…"
	p.hud_label.text = st
	p.place_label.text = "%s/%d" % [ordinal(p.place), racer_count()] if state != "wait" else ""
	var it: String = p.item
	if it == "triple":
		p.item_label.text = "ITEM: TRIPLE MUSHROOM x%d  (X)" % p.item_count
	else:
		p.item_label.text = "ITEM: %s  (X)" % ITEM_NAMES[it] if it != "" else "ITEM: -  (drive through ? boxes)"
	var dl: int = p.drift_level
	var dbg: ColorRect = p.hud.get_node("DriftBg")
	dbg.visible = p.drift_t > 0.0
	if dbg.visible:
		p.drift_fill.size.x = dbg.size.x * clampf(p.drift_t / 2.4, 0.0, 1.0)
		p.drift_fill.color = p.SPARK_COLORS[clampi(dl, 0, 3)]
	_update_minimap(p)
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


## The VR driver's two text panels (about 2.4 m ahead, low left / right) and the hint in the middle.
func vr_panel_texts(k) -> Array:
	if SIMPLE_MODE:  # just your place, low on the left; one headline at a time in the middle
		var h := _hint_for(k, get_process_delta_time())
		if k.finished and state == "race":
			h = "FINISH!"  # the place is on the left panel
		if state == "results" or center_label.modulate.a > 0.05 and center_label.text != "":
			h = ""  # the big headline is showing
		var pl := ordinal(k.place) if state == "race" or state == "countdown" else ""
		return [pl, "", h]
	var left := ""
	if state == "wait":
		left = "WARM-UP\nwaiting..."
	else:
		left = "%s / %d\n%s\n%d pts" % [ordinal(k.place), racer_count(), lap_text(k), cup_points(k)]
	var right := ""
	var it: String = k.item
	if it == "triple":
		right = "MUSHROOM x%d\npress A" % k.item_count
	elif it != "":
		right = "%s\npress A" % ITEM_NAMES[it]
	elif k.charge >= 1.0:
		right = "BOOST READY\npress A!"
	else:
		right = "boost %d%%" % int(k.charge * 100.0)
	if k.drift_t > 0.0:
		right += "\n" + ["sparks...", "BLUE SPARKS", "ORANGE SPARKS!", "PINK SPARKS!!"][clampi(k.drift_level, 0, 3)]
	var h := _hint_for(k, get_process_delta_time())
	if k.finished and state == "race":
		h = "FINISHED %s!" % ordinal(k.place).to_upper()
	return [left, right, h]


## Track outline and kart dots in the corner of a TV view.
func _update_minimap(p) -> void:
	var mm: Control = p.minimap
	if mm == null:
		return
	if map_track != track.build_n:
		map_track = track.build_n
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in track.pts:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
		map_rect = Rect2(lo, hi - lo)
	var sz := mm.size
	var span := maxf(map_rect.size.x, map_rect.size.y)
	if span < 1.0 or sz.x < 4.0:
		return
	var sc := (sz.x - 16.0) / span
	var off := Vector2(8, 8) + (Vector2(span, span) - map_rect.size) * 0.5 * sc
	var line := mm.get_node("Line") as Line2D
	if int(mm.get_meta("track", -1)) != map_track:
		mm.set_meta("track", map_track)
		var arr := PackedVector2Array()
		for i in range(0, track.pts.size(), 2):
			var q: Vector3 = track.pts[i]
			arr.append(off + (Vector2(q.x, q.z) - map_rect.position) * sc)
		line.points = arr
		line.width = maxf(2.0, 5.0 * sz.x / 190.0)
	for i in karts.size():
		var dot := mm.get_child(i + 1) as ColorRect
		var k = karts[i]
		dot.visible = k.active and state != "wait"
		if dot.visible:
			var big := 16.0 if k == p else 10.0
			dot.size = Vector2(big, big)
			dot.position = off + (Vector2(k.position.x, k.position.z) - map_rect.position) * sc - Vector2(big, big) * 0.5


func _update_vr_text(_dt: float) -> void:
	if help_label.modulate.a > 0.0 and round_n >= 2:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if cockpit == null or cockpit.xr_camera == null:
		return
	var cam: XRCamera3D = cockpit.xr_camera
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 40
		vr_center.outline_size = 26
		vr_center.pixel_size = 0.0022
		vr_center.no_depth_test = false
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 1200.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(cockpit.xr_origin if cockpit.xr_origin != null else cockpit.seat).add_child(vr_center)  # rides along with the kart
	vr_center.text = vr_results if state == "results" and vr_results != "" and not get_tree().paused else preload("res://core/vr_text.gd").short(center_label.text)
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, cam, cockpit.xr_origin, 0.3, 1.8)
