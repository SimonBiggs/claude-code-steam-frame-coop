extends Node3D
## FISHING LAKE - relaxing co-op fishing, no fighting. The VR player stands on a jetty with a fishing
## rod (cast, wait for a bite, reel, pull back at the right moment, don't snap the line); the TV
## players (1-6) row little boats around the lake: they herd fish towards the bobber, call fish out,
## scoop floating treasure with their nets (coins upgrade their boats) and splash next to a hooked
## fish to help land it. Fill the aquarium before the sun sets!
## Every day is different: sunny morning, rainy day, evening into a starry night (each with its own
## fish). Mini-events: FISH FRENZY (double points in the bubbles), TREASURE MAPS (a boat finds the X
## and drops a buoy, the angler fishes up the pirate chest) and OLD WHISKERS, the lake legend, who
## needs everybody to land him. A fish journal remembers every species you have ever caught.
## Modes, networking and party join follow docs/GAME_DEV_GUIDE.md and games/marble_maze.

const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const Lake := preload("res://games/fishing_lake/lake.gd")
const FishScript := preload("res://games/fishing_lake/fish.gd")
const TreasureScript := preload("res://games/fishing_lake/treasure.gd")
const BoatScript := preload("res://games/fishing_lake/boat.gd")
const AnglerScript := preload("res://games/fishing_lake/angler.gd")
const MusicScript := preload("res://games/fishing_lake/calm_music.gd")
const JoinListenerScript := preload("res://games/fishing_lake/join_listener.gd")

const MAX_PLAYERS := 7  # angler + 6 boats
const MAX_LOCAL_VIEWS := 6
const MAX_FISH := 18
const MAX_TREASURE := 8
const PAD_LEAVE_TIME := 20.0
const DAY_TIME := 240.0
const FRENZY_TIME := 25.0
const FRENZY_R := 4.5
const LAST_FISH_WAIT := 25.0
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.35, 0.35), Color(0.3, 0.6, 1.0),
	Color(0.35, 0.9, 0.4), Color(1.0, 0.8, 0.15), Color(0.8, 0.45, 1.0), Color(1.0, 0.55, 0.2)]
# p0 / p1: sky phase at the start / end of the day (0 morning, 1 sunset, 1.45 starry night).
const THEMES := [
	{"name": "SUNNY MORNING", "rain": false, "p0": 0.0, "p1": 1.05, "tip": "Sunny Bluegills love the sunshine!"},
	{"name": "RAINY DAY", "rain": true, "p0": 0.05, "p1": 1.05, "tip": "Fish bite faster in the rain - and the Wiggly Eel comes out!"},
	{"name": "EVENING UNDER THE STARS", "rain": false, "p0": 0.45, "p1": 1.45, "tip": "When the stars come out, look for the glowing Moonfish!"},
]
const SOUNDS := {
	"cast": [0.35, 1600.0, 300.0, 0.22, "sine", 0.85],
	"plop": [0.18, 520.0, 120.0, 0.45, "sine", 0.1],
	"nibble": [0.06, 700.0, 500.0, 0.18, "sine", 0.0],
	"bite": [0.3, 300.0, 900.0, 0.4, "square", 0.0],
	"hook": [0.25, 400.0, 1200.0, 0.35, "tri", 0.0],
	"reel": [0.03, 2000.0, 1800.0, 0.07, "square", 0.3],
	"splash": [0.4, 900.0, 200.0, 0.4, "sine", 0.9],
	"snap": [0.14, 2400.0, 300.0, 0.45, "saw", 0.3],
	"catch": [0.8, 523.0, 1568.0, 0.4, "tri", 0.0],
	"golden": [1.3, 523.0, 2093.0, 0.4, "square", 0.0],
	"net": [0.25, 700.0, 1400.0, 0.3, "sine", 0.3],
	"coin": [0.2, 1300.0, 2600.0, 0.3, "square", 0.0],
	"call": [0.45, 900.0, 1800.0, 0.3, "sine", 0.0],
	"heave": [0.3, 200.0, 600.0, 0.4, "tri", 0.2],
	"tick": [0.05, 1300.0, 1300.0, 0.14, "square", 0.0],
	"chirp": [0.12, 2600.0, 3800.0, 0.07, "sine", 0.0],
	"boot": [0.5, 300.0, 90.0, 0.35, "saw", 0.1],
	"day": [0.9, 392.0, 784.0, 0.3, "tri", 0.0],
	"tired": [0.15, 600.0, 900.0, 0.25, "sine", 0.0],
	"frenzy": [0.6, 300.0, 900.0, 0.3, "sine", 0.5],
	"legend": [1.4, 95.0, 45.0, 0.55, "saw", 0.3],
	"new": [0.7, 784.0, 2093.0, 0.35, "tri", 0.0],
	"upgrade": [0.6, 523.0, 1046.0, 0.35, "square", 0.0],
	"map": [0.5, 660.0, 990.0, 0.3, "tri", 0.0],
	"buoy": [0.3, 400.0, 800.0, 0.35, "sine", 0.2],
	"streak": [0.35, 880.0, 1760.0, 0.3, "square", 0.0],
	"leap": [0.25, 700.0, 250.0, 0.22, "sine", 0.7],
	"assist": [0.3, 500.0, 1000.0, 0.3, "tri", 0.3],
	"quack": [0.16, 520.0, 380.0, 0.16, "saw", 0.15],
	"owl": [0.45, 420.0, 360.0, 0.12, "sine", 0.0],
}

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var lake: Lake
var fish: Array = []
var treasures: Array = []
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var join_listener: Node
var joy_owner := {}
var views_root: Control
var last_view_area := Vector2.ZERO
var mats := {}
var meshes := {}

var state := "play"  # play, over
var state_t := 0.0
var day := 1
var round_time := DAY_TIME
var time_left := DAY_TIME
var score := 0
var best := 0
var target := 150
var goal_hit := false
var catches: Array = []  # fish kinds caught today
var biggest := ""
var biggest_kg := 0.0
var golden_bait := false
var shoal_next := 0
var fish_t := 0.0
var treasure_t := 4.0
var chirp_t := 3.0
var last_tick := -1
var cont_was := false
var scooped := 0
var synced := false
var board_text := ""
var reel_snd_t := 0.0

# Day theme, weather and events (host simulates; mirrored through the snapshot extras).
var theme := 0
var daylight := 0.0
var rain := 0.0
var was_raining := false
var was_night := false
var streak := 0
var best_streak := 0
var frenzy_t := 0.0
var frenzy_pos := Vector3.ZERO
var frenzy_at := 0.4
var frenzy_done := false
var map_state := 0  # 0 none, 1 X marked, 2 buoy dropped
var map_pos := Vector3.ZERO
var map_by := -1
var map_wait := 0.0
var legend_state := 0  # 0 not yet today, 1 in the lake, 2 caught, 3 swam off (comes back)
var legend_stamina := 1.0
var legend_t := 0.0
var legend_at := 0.6
var leap_t := 6.0
var extend_t := 0.0
var last_fish_said := false
var stats: Array = []  # per player index, this day's numbers (host)
var awards_text := ""
var journal_counts := PackedInt32Array()
var journal_best := PackedFloat32Array()
var journal_text := ""
var new_today: Array[int] = []
var frenzy_warned := false
var day_summary := ""
var summary_day := -1

var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_hint: Label3D
var bobber_label: Label3D
var rain_player: AudioStreamPlayer


func _ready() -> void:
	randomize()
	_journal_load()
	lake = Lake.new()
	lake.main = self
	add_child(lake)
	lake.build()
	_build_pools()
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
		_show_center("Connecting to the VR player...", 0.0, false)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	for f in fish:
		f.ghost = mode == "client"
	for t in treasures:
		t.ghost = mode == "client"
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "client":
		_request_join(players[1])
		_show_center("CONNECTED - rowing out to the lake!", 2.0, false)
	else:
		_start_day(1)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave a scale behind for the next game


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
	var key := "c%.4f/%.4f/%.4f/%d" % [r_top, r_bottom, h, seg]
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


## The detailed one-piece body mesh of a fish kind (built once, see fish.gd).
func fish_mesh(kind: int) -> ArrayMesh:
	var key := "fish%d" % kind
	if meshes.has(key):
		return meshes[key]
	var m := FishScript.build_mesh(kind)
	meshes[key] = m
	return m


func fish_material(kind: int) -> StandardMaterial3D:
	var glow := 0.0
	var gc := Color.WHITE
	if kind == FishScript.GOLDEN:
		glow = 0.6
		gc = Color(1.0, 0.75, 0.2)
	elif kind == FishScript.MOONFISH:
		glow = 0.9
		gc = Color(0.5, 0.8, 1.0)
	var key := "fishmat/%.2f/%s" % [glow, gc.to_html()]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = gc
		m.emission_energy_multiplier = glow
	mats[key] = m
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


## A little rising jingle for the big moments (new species, legend, upgrades).
func fanfare(broadcast: bool = true) -> void:
	var notes: Array[float] = [1.0, 1.26, 1.5, 2.0]
	for i in notes.size():
		var pitch: float = notes[i]
		get_tree().create_timer(0.13 * i).timeout.connect(func() -> void: sound("streak", -4.0, pitch))
	if broadcast and net != null:
		net.event("fanfare", [])


func burst(pos: Vector3, color: Color, amount: int = 14, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -7.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = box_mesh(Vector3.ONE * 0.06)
	p.material_override = make_material(color, 1.2)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	if broadcast and net != null:
		net.event("burst", [pos, color, amount])


## An expanding ring on the water.
func ripple(pos: Vector3, size: float, broadcast: bool = true) -> void:
	var r := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 20
	tm.ring_segments = 3
	r.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r.material_override = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(r)
	r.global_position = Vector3(pos.x, 0.04, pos.z)
	r.scale = Vector3(0.15, 0.05, 0.15) * size
	var tw := r.create_tween()
	tw.set_parallel()
	tw.tween_property(r, "scale", Vector3(1.0, 0.05, 1.0) * size, 1.2)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.2)
	tw.chain().tween_callback(r.queue_free)
	if broadcast and net != null:
		net.event("ripple", [pos, size])


## A fish jumps out of the water and back in (pure decoration, drawn on both machines).
func leap(pos: Vector3, kind: int, yaw: float, broadcast: bool = true) -> void:
	if broadcast and net != null:
		net.event("leap", [pos, kind, yaw])
	if not FishScript.is_species(kind):
		return
	var m := MeshInstance3D.new()
	m.mesh = fish_mesh(kind)
	m.material_override = fish_material(kind)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var start := Vector3(pos.x, -0.1, pos.z)
	var height := 0.8 + randf() * 0.5
	m.global_position = start
	ripple(start, 0.9, false)
	sound("leap", -14.0, randf_range(0.9, 1.2))
	var fly := func(k: float) -> void:
		if is_instance_valid(m):
			m.global_position = start + dir * 1.6 * k + Vector3(0, sin(k * PI) * height, 0)
			m.global_rotation = Vector3(-cos(k * PI) * 0.9, yaw, 0.0)
	var land := func() -> void:
		ripple(start + dir * 1.6, 1.0, false)
		sound("plop", -12.0, 1.3)
		m.queue_free()
	var tw := m.create_tween()
	tw.tween_method(fly, 0.0, 1.0, 0.9)
	tw.tween_callback(land)


## World text that faces the viewer: billboard on the TV, turned towards the VR player (never
## following their head) in VR.
func face_label(l: Label3D) -> void:
	if players.size() > 0 and players[0].vr:
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		var cam: Node3D = players[0].xr_camera
		var d := l.global_position - cam.global_position
		d.y = 0.0
		if d.length() > 0.01:
			l.global_rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)  # Label3D front is +Z: point it back at the camera
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true, size: float = 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.006 * size
	l.outline_size = 16
	l.modulate = color
	l.no_depth_test = false
	l.render_priority = 5
	add_child(l)
	l.global_position = pos
	face_label(l)
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "global_position", pos + Vector3(0, 0.8, 0), 1.8)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.9)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.0).set_delay(0.9)
	tw.chain().tween_callback(l.queue_free)
	if broadcast and net != null:
		net.event("popup", [pos, text, color, size])


func is_water(p: Vector3) -> bool:
	var off := Vector2(p.x - Lake.LAKE_C.x, p.z - Lake.LAKE_C.z)
	if off.length() > Lake.LAKE_R - 0.8:
		return false
	return not (absf(p.x) < 1.15 and p.z > Lake.JETTY_END_Z - 0.15)


func angler():
	return players[0]


func lure_position() -> Vector3:
	return players[0].lure_pos


func lure_in_water() -> bool:
	return players.size() > 0 and players[0].line_state == "waiting"


func active_boats() -> Array:
	var out: Array = []
	for p in players:
		if p.index > 0 and p.active:
			out.append(p)
	return out


func raining() -> bool:
	return rain > 0.4


func is_night() -> bool:
	return daylight > 1.15


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func in_frenzy(p: Vector3) -> bool:
	return frenzy_t > 0.0 and _flat_dist(p, frenzy_pos) < FRENZY_R + 0.5


## Fish nibble for less time in the rain and in a frenzy (quicker bites for impatient kids).
func nibble_factor() -> float:
	var f := 1.0
	if raining():
		f *= 0.7
	if players.size() > 0 and in_frenzy(players[0].lure_pos):
		f *= 0.4
	return f


func stat(i: int, key: String, add: float = 1.0) -> void:
	if i < 0 or i >= stats.size():
		return
	var d: Dictionary = stats[i]
	d[key] = float(d.get(key, 0.0)) + add


func stat_get(i: int, key: String) -> float:
	if i < 0 or i >= stats.size():
		return 0.0
	var d: Dictionary = stats[i]
	return float(d.get(key, 0.0))


# --- World ---------------------------------------------------------------------------

func _build_pools() -> void:
	for i in MAX_FISH:
		var f := FishScript.new()
		f.main = self
		f.slot = i
		f.visible = false
		add_child(f)
		fish.append(f)
	for i in MAX_TREASURE:
		var t := TreasureScript.new()
		t.main = self
		t.visible = false
		add_child(t)
		treasures.append(t)


func _random_lake_point(margin: float) -> Vector3:
	for i in 20:
		var a := randf() * TAU
		var r := sqrt(randf()) * (Lake.LAKE_R - margin)
		var p := Lake.LAKE_C + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if p.z < Lake.JETTY_END_Z - 2.0:
			return p
	return Lake.LAKE_C


## A spot the angler can comfortably cast to from the end of the jetty (for events).
func _castable_point(min_d: float, max_d: float) -> Vector3:
	var end := Vector3(0.0, 0.0, Lake.JETTY_END_Z)
	for i in 30:
		var a := randf_range(-1.1, 1.1)
		var d := randf_range(min_d, max_d)
		var p := end + Vector3(sin(a) * d, 0.0, -cos(a) * d)
		if is_water(p) and _flat_dist(p, Lake.BOARD_L) > 2.5 and _flat_dist(p, Lake.BOARD_R) > 2.5:
			return p
	return end + Vector3(0, 0, -10.0)


func _kind_allowed(d: Dictionary) -> bool:
	match int(d.get("when", 0)):
		1:
			return not raining()
		2:
			return raining()
		3:
			return is_night()
		4:
			return false
	return true


func _pick_kind() -> int:
	var total := 0
	for k in FishScript.TYPES.size():
		var d: Dictionary = FishScript.TYPES[k]
		if _kind_allowed(d):
			total += int(d["spawn"])
	var roll := randi() % maxi(total, 1)
	for k in FishScript.TYPES.size():
		var d: Dictionary = FishScript.TYPES[k]
		if not _kind_allowed(d):
			continue
		roll -= int(d["spawn"])
		if roll < 0:
			return k
	return FishScript.MINNOW


func _free_fish_slot():
	for f in fish:
		if f.kind < 0:
			return f
	return null


func fish_count() -> int:
	var n := 0
	for f in fish:
		if f.kind >= 0 and not f.is_junk():
			n += 1
	return n


func wanted_fish() -> int:
	return mini(9 + 2 * active_boats().size(), MAX_FISH - 2)


func _spawn_shoal(force_kind: int = -1, at: Vector3 = Vector3.INF) -> void:
	var golden_present := false
	for f in fish:
		if f.kind == FishScript.GOLDEN:
			golden_present = true
	var kind := _pick_kind() if force_kind < 0 else force_kind
	if force_kind < 0 and not golden_present and randf() < 0.02 + 0.005 * day:
		kind = FishScript.GOLDEN
	var d: Dictionary = FishScript.TYPES[kind]
	var n: int = d["shoal"]
	var c := _random_lake_point(4.0) if at == Vector3.INF else at
	shoal_next += 1
	for i in n:
		var f = _free_fish_slot()
		if f == null:
			return
		f.spawn(kind, c + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)), shoal_next if n > 1 else -1)


func _spawn_treasure(force_kind: int = -1, at: Vector3 = Vector3.INF) -> void:
	var count := 0
	var map_floating := false
	for t in treasures:
		if t.kind >= 0:
			count += 1
		if t.kind == TreasureScript.MAP:
			map_floating = true
	if force_kind < 0 and count >= 2 + active_boats().size():
		return
	for t in treasures:
		if t.kind < 0:
			var k := force_kind
			if k < 0:
				var roll := randf()
				k = 0 if roll < 0.3 else (1 if roll < 0.48 else (2 if roll < 0.68 else (3 if roll < 0.84 else 5)))
				if map_state == 0 and not map_floating and day_frac() > 0.15 and randf() < 0.14:
					k = TreasureScript.MAP
			t.spawn(k, _random_lake_point(3.0) if at == Vector3.INF else at)
			return


func release_fish(f) -> void:
	f.clear()


func day_frac() -> float:
	return clampf(1.0 - time_left / maxf(1.0, round_time), 0.0, 1.0)


# --- Players and views -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	var a := AnglerScript.new()
	a.main = self
	a.ghost = mode == "client"
	a.key_set = 0
	add_child(a)
	players.append(a)
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		var b := BoatScript.new()
		b.index = i
		b.main = self
		b.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		b.remote = mode == "host"
		if i == 1:
			b.key_set = 1 if mode == "client" else 0
			b.mouse_look = mode == "client"
		add_child(b)
		players.append(b)
		b.reset_to_start()
		b.set_active(i == 1 and mode == "local")
	_reset_stats()


func is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _apply_vr_performance() -> void:
	var e: Environment = lake.env
	e.ssao_enabled = false
	e.fog_enabled = false
	e.glow_enabled = false
	lake.sun.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 fishes from the jetty in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		var cam := XRCamera3D.new()
		cam.far = 300.0
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
	elif OS.has_environment("BOT_VR") and mode != "client":
		print("Fake VR (bot test): the angler's VR controls are driven by the bot")
		players[0].attach_fake_vr()
	else:
		print("No VR headset: %s" % ("TV boats" if mode == "client" else "split screen, player 1 fishes from the jetty"))
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
	cam.far = 300.0
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
	bg.color = Color(0.1, 0.18, 0.25)
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
	cam.far = 300.0
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
	tag.color = p.color
	tag.size = Vector2(14, 14)
	tag.position = Vector2(14, 22)
	hud.add_child(tag)
	var l := _make_label(28)
	hud.add_child(l)
	l.position = Vector2(36, 10)
	# Contextual "what to do now" tip, big and yellow at the bottom of each view.
	var tip := _make_label(30)
	hud.add_child(tip)
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tip.offset_top = -150
	tip.offset_bottom = -76
	tip.offset_left = 20
	tip.offset_right = -20
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	p.hud = hud
	p.hud_label = l
	p.tip_label = tip


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
		if p.hud_label != null:
			p.hud_label.add_theme_font_size_override("font_size", int(30.0 * ui))
		if p.tip_label != null:
			p.tip_label.add_theme_font_size_override("font_size", int(34.0 * ui))
			var bottom := -76.0 if row == rows - 1 else -12.0  # only the bottom row shares the screen with the help bar
			p.tip_label.offset_bottom = bottom
			p.tip_label.offset_top = bottom - 90.0 * ui


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


## Called by the join listener for every input event: A on a controller nobody owns joins a boat.
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
		_show_center("All %d boats are taken!" % (players.size() - 1), 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


## Local: row out now. TV machine: ask the host (retried by _check_join until it agrees).
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
	target = target_score()
	_show_center("PLAYER %d ROWS OUT!\nLeft stick rows - A scoops treasure - X calls a fish" % (p.index + 1), 2.5)
	sound("day", -6.0, 1.3, true)
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
	Engine.set_meta("fishing_lake_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("fishing_lake_party"):
		return
	var saved: Dictionary = Engine.get_meta("fishing_lake_party")
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


## Test hook: join a boat without a controller (index -1: the next free seat).
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
	_layout_views()
	print("Player %d is now %s" % [p.index + 1, "playing" if p.active else "waiting"])


func has_local_boat_arrows() -> bool:
	for p in players:
		if p.index > 0 and is_local(p) and p.active and p.key_set == 0:
			return true
	return false


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


# --- Game flow -----------------------------------------------------------------------

func target_score() -> int:
	return 160 + 60 * active_boats().size() + 30 * mini(day - 1, 4)


func _reset_stats() -> void:
	stats.clear()
	for i in players.size():
		stats.append({})


func _theme() -> Dictionary:
	return THEMES[theme]


func _start_day(n: int) -> void:
	day = n
	state = "play"
	state_t = 0.0
	time_left = round_time
	score = 0
	goal_hit = false
	catches.clear()
	biggest = ""
	biggest_kg = 0.0
	golden_bait = false
	last_tick = -1
	theme = (n - 1) % THEMES.size()
	var th := _theme()
	daylight = float(th["p0"])
	rain = 0.0
	was_raining = false
	was_night = daylight > 1.15
	streak = 0
	best_streak = 0
	frenzy_t = 0.0
	frenzy_done = false
	frenzy_warned = false
	frenzy_pos = Vector3.ZERO
	frenzy_at = randf_range(0.25, 0.5)
	map_state = 0
	map_by = -1
	legend_state = 0
	legend_stamina = 1.0
	legend_at = randf_range(0.55, 0.7) if n >= 2 else 2.0  # day 1: only as a reward for filling the tank
	extend_t = 0.0
	last_fish_said = false
	awards_text = ""
	new_today.clear()
	_reset_stats()
	target = target_score()
	for f in fish:
		if f != players[0].hooked:
			f.clear()
	for t in treasures:
		t.clear()
	while fish_count() < wanted_fish():
		_spawn_shoal()
	for i in 2:
		_spawn_treasure()
	for p in players:
		if p.index > 0 and p.active:
			p.reset_to_start()
	if n == 1:
		_show_center("FISHING LAKE - fill the aquarium before sunset!\n" \
			+ "VR: FLICK the rod to cast (or A)  -  trigger REELS  -  PULL BACK when it's tired\n" \
			+ "BOATS: left stick rows  -  A scoops treasure  -  X calls a fish to the bobber", 8.0)
	else:
		_show_center("DAY %d - %s\nTarget %d points\n%s" % [n, str(th["name"]), target, str(th["tip"])], 4.5)
	sound("day", -2.0, 1.0, true)
	_send_journal()
	print("Day %d started (%s, target %d, %d boats, %.0f s)" % [n, str(th["name"]), target, active_boats().size(), round_time])


func _end_day() -> void:
	state = "over"
	state_t = 0.0
	if frenzy_t > 0.0:
		frenzy_t = 0.0
	var stars := 0
	if score >= target:
		stars = 3
	elif score * 3 >= target * 2:
		stars = 2
	elif score * 3 >= target:
		stars = 1
	var line := "Best day: %d" % best
	if score > best:
		line = "NEW BEST DAY!  (previous %d)" % best
		best = score
		_save_best(best)
	_journal_save()
	var counts := {}
	for k in catches:
		var ki: int = k
		counts[ki] = int(counts.get(ki, 0)) + 1
	var parts: Array[String] = []
	for k in counts:
		var d: Dictionary = FishScript.TYPES[int(k)]
		parts.append("%s x%d" % [str(d["name"]), int(counts[k])])
	var catch_line := ", ".join(parts) if not parts.is_empty() else "nothing... the fish were shy today!"
	var star_text := "*".repeat(stars) if stars > 0 else "no stars yet"
	awards_text = _awards()
	_show_center("SUNSET!  Day %d is done   %s\nScore %d / %d    %s\n%s\n\nTrigger / A / Enter: fish another day" \
		% [day, star_text, score, target, line, awards_text], 0.0)
	day_summary = "DAY %d - %s\nScore %d / %d  %s\nCaught: %s%s\nBest streak: %d" % [day, star_text, score, target,
		line, catch_line, ("\nBiggest: " + biggest) if biggest != "" else "", best_streak]
	summary_day = day
	net.event("board", [day_summary, day])
	fanfare()
	sound("catch", 0.0, 0.8, true)
	print("Day %d over: score %d / %d, %d catches, stars %d\nAWARDS: %s" % [day, score, target, catches.size(), stars, awards_text.replace("\n", " | ")])


## Everybody gets a fun award for the day (the best thing they did).
func _awards() -> String:
	var lines: Array[String] = []
	var aw := "PATIENT ANGLER - waited and watched"
	if legend_state == 2:
		aw = "LEGEND CATCHER - landed OLD WHISKERS!"
	elif not new_today.is_empty():
		aw = "EXPLORER - %d new species in the journal" % new_today.size()
	elif stat_get(0, "catch") >= 3 and stat_get(0, "snap") == 0.0:
		aw = "STEADY HANDS - no snapped lines!"
	elif best_streak >= 3:
		aw = "HOT STREAK - %d fish in a row" % best_streak
	elif biggest != "":
		aw = "BIG FISH HUNTER - %s" % biggest
	elif stat_get(0, "catch") > 0:
		aw = "HAPPY ANGLER - %d catches" % int(stat_get(0, "catch"))
	lines.append("P1 (rod): %s" % aw)
	var boats := active_boats()
	# [stat, award, description]
	var kinds := [["whisker", "WHISKER WRANGLER", "helped land the legend"], ["map", "MAP READER", "found the treasure X"],
		["scoop", "TREASURE HUNTER", "%d treasures scooped"], ["help", "FISH WHISPERER", "helped %d catches"],
		["splash", "BIG SPLASHER", "%d splashes"]]
	for b in boats:
		var got := ""
		for k in kinds:
			var kk: Array = k
			var key: String = kk[0]
			var mine := stat_get(b.index, key)
			if mine <= 0.0:
				continue
			var top := true
			for o in boats:
				if o != b and stat_get(o.index, key) > mine:
					top = false
			if top:
				var desc: String = kk[2]
				if int(mine) == 1:
					desc = desc.replace("treasures", "treasure").replace("catches", "catch").replace("splashes", "splash")
				got = "%s - %s" % [str(kk[1]), desc % int(mine) if desc.contains("%d") else desc]
				break
		if got == "":
			got = "HAPPY ROWER - enjoyed the lake"
		lines.append("P%d: %s" % [b.index + 1, got])
	return "AWARDS\n" + "\n".join(lines)


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
	_ensure_join_listener()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	var vr: bool = players[0].vr
	lake.set_daylight(daylight, rain, vr)
	lake.set_frenzy(frenzy_t > 0.0, frenzy_pos)
	lake.set_map(map_state, map_pos)
	lake.update(delta)
	lake.update_tank(catches, delta)
	var bp: Vector3 = players[0].body_pos
	lake.rain_near.position = Vector3(bp.x, 9.0, bp.z - 1.5)
	_update_rain_sound()
	_update_board()
	_update_vr_text()
	_ambience(delta)
	var cont := _continue_pressed()
	var cont_edge := cont and not cont_was
	cont_was = cont
	state_t += delta
	if net.mode == "client":
		_check_join(delta)
		_update_lost_pads(delta)
		if cont_edge and state == "over" and state_t > 1.5:
			net.send_action("continue", [])
		return
	_update_lost_pads(delta)
	_host_update(delta, cont_edge)


func _host_update(delta: float, cont_edge: bool) -> void:
	for f in fish:
		f.sim(delta)
	for t in treasures:
		t.sim(delta)
	match state:
		"play":
			time_left -= delta
			var th := _theme()
			daylight = lerpf(float(th["p0"]), float(th["p1"]), day_frac())
			var secs := int(ceilf(time_left))
			if secs <= 10 and secs != last_tick and secs > 0:
				last_tick = secs
				sound("tick", -4.0, 1.0 + (10 - secs) * 0.04, true)
			_fish_ai(delta)
			_events(delta)
			fish_t -= delta
			if fish_t <= 0.0:
				fish_t = 1.5
				if fish_count() < wanted_fish():
					_spawn_shoal()
			treasure_t -= delta
			if treasure_t <= 0.0:
				treasure_t = maxf(4.0, 9.0 - active_boats().size() * 0.8)
				if not active_boats().is_empty():
					_spawn_treasure()
			if not goal_hit and score >= target:
				goal_hit = true
				_show_center("AQUARIUM FULL - GOAL REACHED!\nKeep fishing for a high score until sunset", 3.5)
				sound("golden", -2.0, 1.2, true)
				fanfare()
				if day == 1 and legend_state == 0:
					legend_at = day_frac() + 0.05  # a reward: the legend shows up
			if time_left <= 0.0:
				time_left = 0.0
				# The sun waits while a fish is on the line (nobody wants to lose the last fish).
				var a = players[0]
				if (a.line_state == "fight" or a.line_state == "bite" or a.line_state == "landing") and extend_t < LAST_FISH_WAIT:
					extend_t += delta
					if not last_fish_said:
						last_fish_said = true
						_show_center("ONE LAST FISH!\nThe sun waits for you...", 2.5)
				else:
					_end_day()
		"over":
			rain = move_toward(rain, 0.0, delta * 0.2)
			if state_t > 1.5 and cont_edge:
				_start_day(day + 1)
	# Reel clicks for whoever is holding the rod on this machine.
	var a = players[0]
	if a.reel > 0.1 and (a.line_state == "fight" or a.line_state == "waiting"):
		reel_snd_t -= delta * (0.5 + a.reel)
		if reel_snd_t <= 0.0:
			reel_snd_t = 0.09
			sound("reel", -10.0, 0.9 + a.reel * 0.3)


## Host: weather changes and the day's mini-events.
func _events(delta: float) -> void:
	var th := _theme()
	var frac := day_frac()
	var want_rain := 1.0 if bool(th["rain"]) and frac > 0.08 and frac < 0.8 else 0.0
	rain = move_toward(rain, want_rain, delta * 0.12)
	if raining() and not was_raining:
		was_raining = true
		_show_center("IT'S RAINING!\nFish bite faster - and the Wiggly Eel comes out to play", 3.0)
		_spawn_shoal(FishScript.EEL)
	elif not raining() and was_raining and rain < 0.1:
		was_raining = false
		_show_center("The rain stops... the sun peeks out", 2.0)
	if is_night() and not was_night:
		was_night = true
		_show_center("THE STARS ARE OUT!\nLook for the glowing MOONFISH", 3.0)
		sound("owl", -6.0, 1.0, true)
		_spawn_shoal(FishScript.MOONFISH)
	# Fish frenzy: double points inside the bubbles for a little while.
	if not frenzy_done and frac > frenzy_at - 0.04 and not frenzy_warned:
		frenzy_warned = true
		frenzy_pos = _castable_point(7.0, 14.0)
		ripple(frenzy_pos, 3.0)
	if not frenzy_done and frac > frenzy_at and legend_state != 1 and time_left > 12.0:
		_start_frenzy()
	if frenzy_t > 0.0:
		frenzy_t -= delta
		if randf() < delta * 1.5:
			ripple(frenzy_pos + Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0)), 1.0)
		if frenzy_t <= 0.0:
			frenzy_t = 0.0
			_show_center("The frenzy calms down...", 1.5)
	# The legend: from day 2 later in the day (day 1: as a reward for filling the aquarium).
	match legend_state:
		0:
			if frac > legend_at and frenzy_t <= 0.0 and time_left > 25.0:
				_spawn_legend()
		3:
			legend_t -= delta
			if legend_t <= 0.0 and time_left > 25.0:
				_spawn_legend()
	if legend_state == 1:
		var lf = _legend_fish()
		if lf == null:
			legend_state = 3
			legend_t = 20.0
		elif randf() < delta * 0.6 and lf.state != "hooked":
			ripple(lf.position, 2.2)
	# A treasure map that's been marked but never found: nudge the boats.
	if map_state == 1:
		map_wait += delta
	# Fish jumping out of the water now and then, just for fun.
	leap_t -= delta
	if leap_t <= 0.0:
		leap_t = randf_range(5.0, 10.0) * (0.5 if frenzy_t > 0.0 else 1.0)
		var pick = null
		if frenzy_t > 0.0:
			leap(frenzy_pos + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)), _pick_kind(), randf() * TAU)
		else:
			for i in 6:
				var f = fish[randi() % fish.size()]
				if f.kind >= 0 and FishScript.is_species(f.kind) and f.kind != FishScript.LEGEND and f.state == "swim":
					pick = f
					break
			if pick != null:
				leap(pick.position, pick.kind, pick.rotation.y)


func _start_frenzy() -> void:
	frenzy_done = true
	frenzy_t = FRENZY_TIME
	if frenzy_pos == Vector3.ZERO:
		frenzy_pos = _castable_point(7.0, 14.0)
	# Pull a few fish into the bubbles, and float some goodies there for the boats.
	for i in 2:
		_spawn_shoal(-1, frenzy_pos + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))
	for f in fish:
		if f.kind >= 0 and f.state == "swim" and _flat_dist(f.position, frenzy_pos) < 12.0:
			f.wander = frenzy_pos + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
	if not active_boats().is_empty():
		for i in 2:
			_spawn_treasure(5 if i == 0 else 2, frenzy_pos + Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0)))
	_show_center("FISH FRENZY!\nCast into the BUBBLES for DOUBLE points!\nBoats: herd fish into the bubbles", 3.5)
	sound("frenzy", 0.0, 1.0, true)
	sound("frenzy", -2.0, 1.4, true)
	burst(frenzy_pos + Vector3(0, 0.2, 0), Color(0.6, 1.0, 1.0), 20)
	print("Event: fish frenzy at %s" % str(frenzy_pos))


func _legend_fish():
	for f in fish:
		if f.kind == FishScript.LEGEND:
			return f
	return null


func _spawn_legend() -> void:
	var slot = _free_fish_slot()
	if slot == null:
		for f in fish:
			if f.kind == FishScript.MINNOW and f.state == "swim":
				f.clear()
				slot = f
				break
	if slot == null:
		return
	var p := _castable_point(11.0, 17.0)
	slot.spawn(FishScript.LEGEND, p, -1)
	legend_state = 1
	legend_stamina = 1.0
	ripple(p, 4.0)
	burst(p + Vector3(0, 0.3, 0), Color(0.5, 0.7, 0.9), 18)
	sound("legend", 0.0, 1.0, true)
	_show_center("A GIANT SHADOW IN THE WATER...\nOLD WHISKERS, THE LAKE LEGEND, IS HERE!\nBoats: get close and press X to call him to the bobber", 4.5)
	print("Event: OLD WHISKERS appears at %s" % str(p))


## Wear the hooked legend out (reeling, pulling back, boat splashes). by > 0: a boat helped.
func legend_tire(amount: float, by: int) -> void:
	if legend_stamina <= 0.0:
		return
	legend_stamina = maxf(0.0, legend_stamina - amount)
	if by > 0:
		stat(by, "whisker")
	if legend_stamina <= 0.0:
		var lp: Vector3 = players[0].lure_pos
		popup(lp + Vector3(0, 1.4, 0), "HE'S WORN OUT!", Color(0.4, 1.0, 0.5), true, 1.5)
		_show_center("OLD WHISKERS IS WORN OUT!\nREEL HIM IN!", 2.5)
		sound("tired", 0.0, 0.8, true)


func _ambience(delta: float) -> void:
	chirp_t -= delta
	if chirp_t <= 0.0:
		chirp_t = randf_range(4.0, 11.0)
		if is_night():
			sound("owl", -16.0, randf_range(0.95, 1.05))
			get_tree().create_timer(0.55).timeout.connect(func() -> void: sound("owl", -17.0, 0.9))
		elif randf() < 0.3:
			sound("quack", -16.0, randf_range(0.9, 1.1))
			get_tree().create_timer(0.2).timeout.connect(func() -> void: sound("quack", -17.0, 1.05))
		elif not raining():
			var p := 1.0 + randf() * 0.3
			sound("chirp", -14.0, p)
			get_tree().create_timer(0.15).timeout.connect(func() -> void: sound("chirp", -15.0, p * 1.1))


## Soft rain noise that follows the rain strength (both machines).
func _update_rain_sound() -> void:
	if rain < 0.02:
		if rain_player != null and rain_player.playing:
			rain_player.stop()
		return
	if rain_player == null:
		rain_player = AudioStreamPlayer.new()
		add_child(rain_player)
		var cache := "fishing_lake_rain"
		if Engine.has_meta(cache):
			rain_player.stream = Engine.get_meta(cache)
		else:
			var rate := 22050
			var n := rate * 2
			var data := PackedByteArray()
			data.resize(n * 2)
			var lp := 0.0
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in n:
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
				var crackle := rng.randf_range(-1.0, 1.0) * 0.6 if rng.randf() < 0.004 else 0.0
				data.encode_s16(i * 2, int(clampf(lp * 0.5 + crackle * 0.3, -1.0, 1.0) * 32767.0 * 0.6))
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = rate
			w.data = data
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = n
			Engine.set_meta(cache, w)
			rain_player.stream = w
	rain_player.volume_db = lerpf(-34.0, -17.0, rain)
	if not rain_player.playing:
		rain_player.play()


## Host: which fish goes for the lure, plus the "nothing's biting" helpers (kids shouldn't wait long).
func _fish_ai(delta: float) -> void:
	var a = players[0]
	if a.line_state != "waiting":
		return
	var engaged := false
	for f in fish:
		if f.kind >= 0 and (f.state == "approach" or f.state == "nibble" or f.state == "bite"):
			engaged = true
	var lure: Vector3 = a.lure_pos
	# Treasure map: a lure by the buoy brings up the pirate chest.
	if map_state == 2 and not engaged and _flat_dist(lure, map_pos) < 3.5 and a.wait_t > 1.2:
		var c = _free_fish_slot()
		if c != null:
			c.spawn(FishScript.CHEST, lure + Vector3(0, -1.0, 0), -1)
			c.pirate = true
			c.set_state("nibble")
			c.nibble_time = 0.9
			a.on_nibble()
			popup(lure + Vector3(0, 1.2, 0), "Something's down there...", Color(1.0, 0.85, 0.3))
			return
	if golden_bait and not engaged:
		golden_bait = false
		var g = _free_fish_slot()
		if g != null:
			var dir := Vector3(randf_range(-1.0, 1.0), 0.0, -1.0).normalized()
			g.spawn(FishScript.GOLDEN, lure + dir * 4.0, -1)
			g.called_t = 12.0
			g.set_state("approach")
			popup(lure + Vector3(0, 1.2, 0), "A GOLDEN FISH IS COMING!", Color(1.0, 0.85, 0.2), true, 1.3)
			sound("golden", -4.0, 1.0, true)
			engaged = true
	if engaged:
		return
	var frenzy := in_frenzy(lure)
	# The legend gets first go at a lure cast near him (otherwise the minnows always win).
	var lf = _legend_fish()
	if lf != null and lf.free_to_bite() and _flat_dist(lf.position, lure) < 7.0 and randf() < delta * 2.0:
		lf.set_state("approach")
		return
	for f in fish:
		if not f.free_to_bite():
			continue
		var d: Dictionary = f.info()
		var notice: float = d["notice"]
		if a.twitch_t > 0.0:
			notice *= 1.6
		if raining():
			notice *= 1.4
		var called: bool = f.called_t > 0.0
		if called:
			notice = 80.0
		var rate := 4.0 if called else 1.2
		if frenzy and _flat_dist(f.position, frenzy_pos) < FRENZY_R + 4.0:
			notice = maxf(notice, 9.0)
			rate = 5.0
		var dist := Vector2(f.position.x - lure.x, f.position.z - lure.z).length()
		if dist < notice and randf() < delta * rate:
			f.set_state("approach")
			return
	if a.wait_t > (3.0 if frenzy else 6.0):
		a.wait_t = 0.0
		var best_f = null
		var best_d := 14.0
		for f in fish:
			if not f.free_to_bite() or f.kind == FishScript.LEGEND:
				continue
			var dist := Vector2(f.position.x - lure.x, f.position.z - lure.z).length()
			if dist < best_d:
				best_d = dist
				best_f = f
		if best_f != null:
			best_f.set_state("approach")
		else:
			var j = _free_fish_slot()
			if j != null:
				j.spawn(FishScript.CHEST if randf() < 0.3 else FishScript.BOOT, lure + Vector3(0, -1.0, 0), -1)
				j.set_state("nibble")
				j.nibble_time = 0.8
				a.on_nibble()


# --- Angler callbacks (host) ----------------------------------------------------------

func on_cast(from: Vector3, dist: float) -> void:
	sound("cast", -2.0, clampf(1.3 - dist * 0.025, 0.7, 1.3), true)


func on_recast() -> void:
	for f in fish:
		if f.state == "approach" or f.state == "nibble":
			if f.is_junk():
				f.clear()
			else:
				f.set_state("swim")


func on_lure_plop(pos: Vector3) -> void:
	sound("plop", 0.0, 1.0, true)
	ripple(pos, 1.2)
	burst(pos, Color(0.8, 0.95, 1.0), 8)
	if in_frenzy(pos):
		popup(pos + Vector3(0, 1.0, 0), "IN THE BUBBLES - x2!", Color(0.5, 1.0, 1.0), true, 1.2)
	elif map_state == 2 and _flat_dist(pos, map_pos) < 3.5:
		popup(pos + Vector3(0, 1.0, 0), "Right by the buoy!", Color(1.0, 0.9, 0.3), true, 1.2)


func on_lure_missed(pos: Vector3) -> void:
	popup(pos + Vector3(0, 0.6, 0), "Oops - that's land! Cast again", Color(1.0, 0.9, 0.6))


func on_reeled_in() -> void:
	sound("tick", -8.0, 0.8)


func on_fish_nibble(_f) -> void:
	players[0].on_nibble()
	sound("nibble", -4.0, 1.0, true)
	ripple(players[0].lure_pos, 0.6)


func on_fish_bite(f) -> void:
	var a = players[0]
	if a.line_state != "waiting":
		f.set_state("swim")
		return
	a.on_bite(f)
	var lp: Vector3 = a.lure_pos
	sound("bite", 0.0, 1.0, true)
	ripple(lp, 1.6)
	burst(lp, Color(0.85, 0.95, 1.0), 10)
	popup(lp + Vector3(0, 0.9, 0), "BITE!", Color(1.0, 0.45, 0.3), true, 1.4)


func on_fish_scared(f) -> void:
	var a = players[0]
	if a.hooked == f and a.line_state == "bite":
		a.hooked = null
		a._set_line("waiting")
		a.wait_t = 0.0
	if f.state == "nibble" or f.state == "bite":
		a.nibbling = false


func _break_streak() -> void:
	if streak >= 3:
		popup(players[0].lure_pos + Vector3(0, 1.4, 0), "Streak ended at %d" % streak, Color(0.8, 0.9, 1.0))
	streak = 0


func on_bite_missed(pos: Vector3) -> void:
	popup(pos + Vector3(0, 0.8, 0), "Too slow - it swam off!", Color(0.8, 0.9, 1.0))
	sound("splash", -6.0, 1.3, true)
	_break_streak()


func on_hooked(f) -> void:
	sound("hook", 0.0, 1.0, true)
	var lp: Vector3 = players[0].lure_pos
	var text := "FISH ON!" if not f.is_junk() else "Something heavy..."
	if f.kind == FishScript.LEGEND:
		text = "OLD WHISKERS IS HOOKED!"
		sound("legend", 0.0, 1.3, true)
		if not active_boats().is_empty():
			_show_center("OLD WHISKERS IS ON THE LINE!\nBOATS: row right next to him and press A to SPLASH - tire him out!\nRod: reel when he rests, let him run when he pulls", 4.5)
		else:
			_show_center("OLD WHISKERS IS ON THE LINE!\nReel when he rests, PULL BACK hard, let him run when he pulls", 4.0)
	elif not f.is_junk() and float(f.info()["pull"]) >= 0.6 and not active_boats().is_empty():
		_show_center("A BIG ONE! Boats: row over and SPLASH (A) right next to it to help!", 2.5)
	popup(lp + Vector3(0, 1.0, 0), text, Color(1.0, 0.85, 0.3), true, 1.3)


func on_fish_surge(pos: Vector3, _f) -> void:
	sound("splash", -3.0, randf_range(0.8, 1.1), true)
	burst(pos, Color(0.85, 0.95, 1.0), 12)
	ripple(pos, 1.4)


func on_fish_tired(_f) -> void:
	var lp: Vector3 = players[0].lure_pos
	popup(lp + Vector3(0, 0.9, 0), "IT'S TIRED - PULL!", Color(0.4, 1.0, 0.5))
	sound("tired", -2.0, 1.0, true)


func on_yank(pos: Vector3, good: bool) -> void:
	if good:
		popup(pos + Vector3(0, 0.8, 0), "HEAVE!", Color(0.4, 1.0, 0.5))
		sound("heave", 0.0, 1.0, true)
		ripple(pos, 1.0)
	else:
		popup(pos + Vector3(0, 0.8, 0), "TOO HARD!", Color(1.0, 0.4, 0.3))


func on_line_snap(pos: Vector3, f) -> void:
	sound("snap", 0.0, 1.0, true)
	stat(0, "snap")
	var what := "fish"
	if f != null:
		what = "boot" if f.kind == FishScript.BOOT else ("chest" if f.kind == FishScript.CHEST else "fish")
	_break_streak()
	if f != null and f.kind == FishScript.LEGEND:
		popup(pos + Vector3(0, 1.4, 0), "SNAP! Old Whiskers got away...", Color(1.0, 0.4, 0.3), true, 1.4)
		_show_center("SNAP! OLD WHISKERS SWAM OFF...\nDon't worry - he'll be back! (Ease off while he pulls)", 3.0)
		ripple(pos, 3.0)
		f.clear()
		legend_state = 3
		legend_t = 25.0
		return
	if f != null and f.pirate:
		map_state = 2  # the buoy is still there: try again
	popup(pos + Vector3(0, 1.0, 0), "SNAP! The %s got away" % what, Color(1.0, 0.4, 0.3), true, 1.2)
	_show_center("SNAP!  Keep the meter out of the red: stop reeling while it pulls", 2.5)


func on_catch(f) -> void:
	var d: Dictionary = f.info()
	var pts: int = d["pts"]
	var helper := -1
	if f.called_by > 0:
		helper = f.called_by
	elif f.herded_by > 0:
		helper = f.herded_by
	elif not f.helpers.is_empty():
		helper = f.helpers[0]
	if f.pirate and map_by > 0:
		helper = map_by
	var bonus := 0
	if helper > 0 and (not f.is_junk() or f.pirate):
		bonus = maxi(3, pts / 2)
		stat(helper, "help")
		_add_coins(players[helper], 1)
	for h in f.helpers:
		var hi: int = h
		if hi != helper and hi > 0 and hi < players.size():
			stat(hi, "help")
			_add_coins(players[hi], 1)
	var tip: Vector3 = players[0].tip_pos()
	var lp: Vector3 = players[0].lure_pos
	var frenzy := in_frenzy(lp) or in_frenzy(f.position)
	var mult := 2 if frenzy and not f.is_junk() else 1
	var streak_bonus := 0
	if not f.is_junk():
		streak += 1
		best_streak = maxi(best_streak, streak)
		if streak >= 3:
			streak_bonus = mini(5 * (streak - 2), 25)
	if f.pirate:
		bonus += 40
		map_state = 0
	var total := pts * mult + bonus + streak_bonus
	score += total
	catches.append(f.kind)
	stat(0, "catch")
	var nm: String = d["name"]
	var kg: float = f.weight
	if not f.is_junk() and kg > biggest_kg:
		biggest_kg = kg
		biggest = "%s %.1f kg" % [nm, kg]
	var col: Color = d["col"]
	burst(tip, col.lightened(0.3), 24)
	burst(tip, Color(1, 1, 1), 12)
	var text := "%s!\n%.1f kg   +%d" % [nm.to_upper(), kg, pts * mult]
	if f.kind == FishScript.BOOT:
		text = "AN OLD BOOT...\n+%d  (yuck!)" % pts
		sound("boot", 0.0, 1.0, true)
	elif f.kind == FishScript.CHEST:
		text = "%s!\nfull of coins   +%d" % ["PIRATE TREASURE" if f.pirate else "TREASURE CHEST", pts]
		sound("golden", 0.0, 1.0, true)
		for i in 3:
			burst(tip + Vector3(0, 0.2 * i, 0), Color(1.0, 0.85, 0.2), 16)
	elif f.kind == FishScript.GOLDEN:
		text = "THE GOLDEN FISH!!\n%.1f kg   +%d" % [kg, pts * mult]
		sound("golden", 0.0, 1.0, true)
		burst(tip, Color(1.0, 0.85, 0.2), 30)
	elif f.kind == FishScript.LEGEND:
		legend_state = 2
		text = "YOU CAUGHT OLD WHISKERS!!!\nTHE LAKE LEGEND - %.1f kg   +%d" % [kg, pts * mult]
		var lpos: Vector3 = f.global_position
		for i in 4:
			burst(lpos + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)), [Color(1.0, 0.85, 0.2), Color(0.5, 0.9, 1.0), Color(1, 1, 1), Color(1.0, 0.5, 0.7)][i], 30)
		ripple(lpos, 5.0)
		sound("golden", 0.0, 0.8, true)
		fanfare()
		for b in active_boats():
			if f.helpers.has(b.index):
				_add_coins(b, 2)
	else:
		sound("catch", 0.0, 1.0 + randf() * 0.1, true)
	if mult > 1:
		text += "\nFRENZY x2!"
	if bonus > 0 and helper > 0:
		text += "\nThanks P%d!  +%d" % [helper + 1, bonus]
	if streak_bonus > 0:
		text += "\nSTREAK x%d  +%d" % [streak, streak_bonus]
		sound("streak", -3.0, 1.0 + 0.05 * streak, true)
	# The fish journal: a brand-new species is a big moment.
	if FishScript.is_species(f.kind):
		_journal_add(f.kind, kg)
	_show_center(text, 2.8)
	print("Caught %s (%.1f kg) +%d%s%s, score %d" % [nm, kg, total, (" helper P%d" % (helper + 1)) if helper > 0 else "",
		" FRENZY" if mult > 1 else "", score])


func _journal_add(kind: int, kg: float) -> void:
	if journal_counts.size() < FishScript.TYPES.size():
		journal_counts.resize(FishScript.TYPES.size())
		journal_best.resize(FishScript.TYPES.size())
	var first := journal_counts[kind] == 0
	journal_counts[kind] += 1
	var record := kg > journal_best[kind] and not first
	journal_best[kind] = maxf(journal_best[kind], kg)
	if first:
		new_today.append(kind)
		var nm: String = FishScript.TYPES[kind]["name"]
		var found := _journal_found()
		var msg := "NEW SPECIES!\n%s goes in your fish journal  (%d / %d)" % [nm.to_upper(), found, _species_total()]
		var announce := func() -> void: _show_center(msg, 2.5)
		get_tree().create_timer(2.9).timeout.connect(announce)
		var tip: Vector3 = players[0].tip_pos()
		for c in [Color(1.0, 0.4, 0.5), Color(0.4, 0.9, 1.0), Color(1.0, 0.9, 0.3)]:
			burst(tip + Vector3(0, 0.3, 0), c, 14)
		fanfare()
		sound("new", 0.0, 1.0, true)
		_journal_save()
	elif record:
		popup(players[0].lure_pos + Vector3(0, 1.6, 0), "NEW RECORD %s!" % str(FishScript.TYPES[kind]["name"]).to_upper(), Color(1.0, 0.9, 0.4), true, 1.2)
	_send_journal()


func _species_total() -> int:
	var n := 0
	for k in FishScript.TYPES.size():
		if FishScript.is_species(k):
			n += 1
	return n


func _journal_found() -> int:
	var n := 0
	for k in mini(journal_counts.size(), FishScript.TYPES.size()):
		if FishScript.is_species(k) and journal_counts[k] > 0:
			n += 1
	return n


## The bot tests keep their own journal so they never "discover" fish for the family.
func _journal_file() -> String:
	if get_parent() != get_tree().root:
		return "user://fishing_lake_journal_test.cfg"
	return "user://fishing_lake_journal.cfg"


func _journal_load() -> void:
	journal_counts = PackedInt32Array()
	journal_counts.resize(FishScript.TYPES.size())
	journal_best = PackedFloat32Array()
	journal_best.resize(FishScript.TYPES.size())
	var cfg := ConfigFile.new()
	if cfg.load(_journal_file()) != OK:
		return
	var c: PackedInt32Array = cfg.get_value("journal", "counts", PackedInt32Array())
	var b: PackedFloat32Array = cfg.get_value("journal", "best", PackedFloat32Array())
	for i in mini(c.size(), journal_counts.size()):
		journal_counts[i] = c[i]
	for i in mini(b.size(), journal_best.size()):
		journal_best[i] = b[i]


func _journal_save() -> void:
	if net != null and net.mode == "client":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("journal", "counts", journal_counts)
	cfg.set_value("journal", "best", journal_best)
	cfg.save(_journal_file())


func _send_journal() -> void:
	if net != null:
		net.event("journal", [journal_counts, journal_best])


# --- Boat callbacks (host) --------------------------------------------------------------

func _add_coins(b, n: int) -> void:
	if b == null or b.index <= 0:
		return
	b.coins += n
	stat(b.index, "coins", n)
	var need: int = b.next_level_coins()
	if need > 0 and b.coins >= need:
		b.set_level(b.level + 1)
		var nm: String = BoatScript.LEVEL_NAMES[b.level]
		var what: String = ["", "a SAIL - faster!", "a BIG NET - scoops from further!", "a LANTERN MOTOR - zoom!"][b.level]
		popup(b.global_position + Vector3(0, 2.6, 0), "UPGRADE: %s!" % nm, b.color.lightened(0.4), true, 1.3)
		_show_center("P%d's boat got %s" % [b.index + 1, what], 2.5)
		burst(b.global_position + Vector3(0, 1.0, 0), b.color.lightened(0.3), 24)
		sound("upgrade", 0.0, 1.0, true)
		fanfare()
		print("Upgrade: P%d boat level %d (%s)" % [b.index + 1, b.level, nm])


func on_boat_net(b) -> void:
	if state == "over":
		return
	var np: Vector3 = b.net_point()
	var best_t = null
	var best_d: float = b.net_reach()
	for t in treasures:
		if t.kind < 0:
			continue
		var d := Vector2(t.position.x - np.x, t.position.z - np.z).length()
		if d < best_d:
			best_d = d
			best_t = t
	if best_t != null:
		var info: Dictionary = best_t.info()
		var pts: int = info["pts"]
		score += pts
		scooped += 1
		b.scooped += 1
		stat(b.index, "scoop")
		var pos: Vector3 = best_t.position
		var nm: String = info["name"]
		var extra := ""
		var k: int = best_t.kind
		if k == 1 and not golden_bait and randf() < 0.3:
			golden_bait = true
			extra = "\nIt says: GOLDEN BAIT! Next cast brings a golden fish!"
		best_t.clear()
		popup(pos + Vector3(0, 1.0, 0), "P%d: %s +%d" % [b.index + 1, nm, pts], b.color.lightened(0.3), true, 1.1)
		burst(pos, Color(1.0, 0.9, 0.4), 16)
		sound("coin", -2.0, 1.0, true)
		if extra != "":
			_show_center("P%d found a message in a bottle!%s" % [b.index + 1, extra], 3.0)
		if k == TreasureScript.MAP:
			_start_map(b)
		_add_coins(b, 2 if k == 3 else 1)
		return
	# The treasure map's X: drop the buoy for the angler.
	if map_state == 1 and _flat_dist(np, map_pos) < 2.8 or map_state == 1 and _flat_dist(b.global_position, map_pos) < 2.5:
		_place_buoy(b)
		return
	# Nothing to scoop: a big splash that scares nearby fish away from the boat (herding!).
	splash(np, b.index)


func _start_map(b) -> void:
	map_state = 1
	map_by = -1
	map_wait = 0.0
	map_pos = _castable_point(7.0, 15.0)
	for i in 6:
		if _flat_dist(map_pos, b.global_position) > 6.0:
			break
		map_pos = _castable_point(7.0, 15.0)
	_show_center("P%d found a TREASURE MAP!\nRow to the big RED X and press A there!" % (b.index + 1), 3.5)
	sound("map", 0.0, 1.0, true)
	ripple(map_pos, 3.0)
	print("Event: treasure map, X at %s" % str(map_pos))


func _place_buoy(b) -> void:
	map_state = 2
	map_by = b.index
	stat(b.index, "map")
	_add_coins(b, 2)
	burst(map_pos + Vector3(0, 0.5, 0), Color(1.0, 0.85, 0.2), 20)
	ripple(map_pos, 2.5)
	sound("buoy", 0.0, 1.0, true)
	popup(map_pos + Vector3(0, 1.8, 0), "P%d: X MARKS THE SPOT!" % (b.index + 1), b.color.lightened(0.3), true, 1.3)
	_show_center("P%d dropped a buoy on the X!\nANGLER: cast next to the YELLOW BUOY to fish up the pirate treasure!" % (b.index + 1), 4.0)
	print("Event: buoy dropped by P%d" % (b.index + 1))


func splash(pos: Vector3, by: int) -> void:
	sound("splash", -2.0, randf_range(0.9, 1.2), true)
	burst(pos, Color(0.8, 0.95, 1.0), 14)
	ripple(pos, 2.5)
	stat(by, "splash")
	for f in fish:
		if f.kind < 0 or f.is_junk():
			continue
		if Vector2(f.position.x - pos.x, f.position.z - pos.z).length() < 5.0:
			f.scare(pos, by)
	# Splashing right next to a hooked fish helps the angler land it (co-op catch!).
	var a = players[0]
	var now := Time.get_ticks_msec() / 1000.0
	var ready: bool = by > 0 and now - float(players[by].get_meta("assist_t", -10.0)) > 1.4
	if ready and a.line_state == "fight" and a.hooked != null and _flat_dist(pos, a.lure_pos) < 4.0:
		players[by].set_meta("assist_t", now)
		var first: bool = not a.hooked.helpers.has(by)
		if a.assist(by):
			sound("assist", 0.0, 1.0, true)
			var who := "P%d" % (by + 1)
			if a.hooked.kind == FishScript.LEGEND:
				legend_tire(0.09, by)
				popup(a.lure_pos + Vector3(0, 1.6, 0), "%s SPLASH! Whiskers is tiring!" % who, players[by].color.lightened(0.3), true, 1.2)
			else:
				popup(a.lure_pos + Vector3(0, 1.4, 0), "%s HELPS! It stops pulling!" % who, players[by].color.lightened(0.3), true, 1.1)
			if first:
				_add_coins(players[by], 1)


func on_boat_call(b) -> void:
	var bp: Vector3 = b.global_position
	var pick = null
	var best_s := 1e9
	for f in fish:
		if f.kind < 0 or f.is_junk() or f.state == "hooked" or f.state == "landed":
			continue
		var d := Vector2(f.position.x - bp.x, f.position.z - bp.z).length()
		if d > (14.0 if b.level >= 3 else 11.0):
			continue
		var flen: float = f.info()["len"]
		var s := d - flen * 8.0
		if s < best_s:
			best_s = s
			pick = f
	b.calls += 1
	if pick == null:
		popup(bp + Vector3(0, 2.2, 0), "No fish near P%d..." % (b.index + 1), Color(0.8, 0.9, 1.0))
		sound("call", -8.0, 0.8, true)
		return
	pick.called_t = 12.0
	pick.called_by = b.index
	var nm: String = pick.info()["name"]
	popup(bp + Vector3(0, 2.2, 0), "P%d: %s HERE!" % [b.index + 1, nm.to_upper()], b.color.lightened(0.3), true, 1.2)
	sound("call", -2.0, 1.0, true)
	if lure_in_water() and pick.free_to_bite():
		var engaged := false
		for f in fish:
			if f.state == "approach" or f.state == "nibble" or f.state == "bite":
				engaged = true
		if not engaged:
			pick.set_state("approach")


## Bot hooks: start an event now ("frenzy", "map", "legend", "rain", "night").
func debug_event(what: String) -> void:
	if net.mode == "client" or state != "play":
		return
	match what:
		"frenzy":
			frenzy_done = false
			frenzy_pos = _castable_point(7.0, 12.0)
			_start_frenzy()
		"map":
			var boats := active_boats()
			if boats.is_empty():
				return
			var b = boats[0]
			_spawn_treasure(TreasureScript.MAP, b.global_position + b.forward() * 3.0)
		"legend":
			if legend_state != 1:
				_spawn_legend()
		"rain":
			theme = 1
		"night":
			theme = 2


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ------------------------------------

func on_client_joined() -> void:
	_show_center("THE TV PLAYERS JOINED!", 1.5)
	_send_journal()


func on_client_left() -> void:
	for i in range(1, players.size()):
		if players[i].active:
			players[i].set_active(false)
	target = target_score()
	_show_center("The TV players left - the lake is all yours", 2.0)


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
				_send_journal()
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			if p.active:
				p.set_active(false)
				target = target_score()
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
		"continue":
			_on_continue()
		"net":
			if p.active:
				if args.size() >= 2:
					p.apply_remote_state(args[0], args[1], p.row_amount)
					p.position = args[0]
					p.yaw = args[1]
				on_boat_net(p)
		"call":
			if p.active:
				on_boat_call(p)
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused
			if not paused:
				players[0].trig_lock = true


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	if vr_center != null and paused:
		VrText.snap(vr_center)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	if not paused:
		players[0].trig_lock = true  # a trigger still held from the pause must not reel or continue
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHold the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	# Packed arrays keep the 30 Hz snapshot under one network packet.
	var fs := PackedFloat32Array()
	for f in fish:
		var flags := 0
		if f.called_t > 0.0:
			flags |= 1
		if f.state == "hooked":
			flags |= 2
		if f.state == "landed":
			flags |= 4
		var fp: Vector3 = f.position
		fs.append_array([float(f.kind), fp.x, fp.y, fp.z, f.rotation.y, float(flags)])
	var ts := PackedFloat32Array()
	for t in treasures:
		var tp: Vector3 = t.position
		ts.append_array([float(t.kind), tp.x, tp.y, tp.z])
	var bs := PackedInt32Array()
	for i in range(1, players.size()):
		bs.append(1 + players[i].level + 4 * mini(players[i].coins, 9999) if players[i].active else 0)
	# Weather, sky, events: a few numbers.
	var ex := PackedFloat32Array([rain, daylight, frenzy_t, frenzy_pos.x, frenzy_pos.z, float(map_state), map_pos.x, map_pos.z,
		legend_stamina, float(streak), float(theme), float(legend_state)])
	return [state, state_t, time_left, round_time, score, target, day, best, fs, ts, bs, players[0].snapshot(),
		PackedInt32Array(catches), goal_hit, biggest, ex]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 16:
		return
	synced = true
	var st: String = s[0]
	if st != state:
		state = st
		state_t = float(s[1])
	time_left = s[2]
	round_time = s[3]
	score = s[4]
	target = s[5]
	day = s[6]
	best = s[7]
	var fs: PackedFloat32Array = s[8]
	for i in mini(fs.size() / 6, fish.size()):
		var f = fish[i]
		var k := int(fs[i * 6])
		var fp := Vector3(fs[i * 6 + 1], fs[i * 6 + 2], fs[i * 6 + 3])
		if k != f.kind:
			if k < 0:
				f.clear()
			else:
				f.kind = k
				f._rebuild()
				f.position = fp
				f.visible = true
		f.net_pos = fp
		f.net_yaw = fs[i * 6 + 4]
		f.net_flags = int(fs[i * 6 + 5])
	var ts: PackedFloat32Array = s[9]
	for i in mini(ts.size() / 4, treasures.size()):
		var t = treasures[i]
		var k := int(ts[i * 4])
		var tp := Vector3(ts[i * 4 + 1], ts[i * 4 + 2], ts[i * 4 + 3])
		if k != t.kind:
			if k < 0:
				t.clear()
			else:
				t.kind = k
				t._rebuild()
				t.position = tp
				t.visible = true
		t.net_pos = tp
	var bs: PackedInt32Array = s[10]
	for i in bs.size():
		var idx := i + 1
		if idx >= players.size():
			break
		var p = players[idx]
		var act: bool = bs[i] > 0
		if act:
			p.set_level((bs[i] - 1) % 4)
			p.coins = (bs[i] - 1) / 4
		if act != p.active:
			if act and not p.has_meta("want_join") and is_local(p) and not p.active and p.has_meta("left_by_pad"):
				continue
			p.set_active(act)
			if act:
				p.reset_to_start()
			on_player_activity_changed(p)
	players[0].apply_net(s[11])
	var cs: PackedInt32Array = s[12]
	catches = Array(cs)
	goal_hit = s[13]
	biggest = s[14]
	var ex: PackedFloat32Array = s[15]
	if ex.size() >= 12:
		rain = ex[0]
		daylight = ex[1]
		frenzy_t = ex[2]
		frenzy_pos = Vector3(ex[3], 0.0, ex[4])
		map_state = int(ex[5])
		map_pos = Vector3(ex[6], 0.0, ex[7])
		legend_stamina = ex[8]
		streak = int(ex[9])
		theme = clampi(int(ex[10]), 0, THEMES.size() - 1)
		legend_state = int(ex[11])


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"fanfare":
			fanfare(false)
		"burst":
			burst(args[0], args[1], args[2], false)
		"ripple":
			ripple(args[0], args[1], false)
		"leap":
			leap(args[0], args[1], args[2], false)
		"popup":
			popup(args[0], args[1], args[2], false, args[3])
		"center":
			_show_center(args[0], args[1], false)
		"board":
			day_summary = args[0]
			summary_day = args[1]
		"journal":
			journal_counts = args[0]
			journal_best = args[1]
			journal_text = ""
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR player paused the game")


## A / Enter on this machine (VR: the trigger or A) moves on from the sunset screen.
func _continue_pressed() -> bool:
	if state != "over":
		return false
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for p in players:
		if is_local(p) and p.active and p.action_pressed():
			return true
	if players.size() > 0 and players[0].vr and players[0].action_pressed():
		return true
	return false


## Bot hook: same as pressing A on the sunset screen.
func debug_continue() -> void:
	if net.mode == "client":
		net.send_action("continue", [])
	else:
		_on_continue()


func _on_continue() -> void:
	if state == "over" and state_t > 1.0:
		_start_day(day + 1)


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://fishing_lake_best.cfg")
	return int(cfg.get_value("best", "score", 0))


func _save_best(s: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "score", s)
	cfg.save("user://fishing_lake_best.cfg")


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
	center_label = _make_label(42)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.offset_left = 60
	center_label.offset_right = -60
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -64
	help_label.offset_bottom = -12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Boat: left stick / arrows (WASD on the TV) row · right stick / mouse camera · A / Space / Enter net & splash · X / F / slash call a fish · Start / Esc menu\n" \
		+ "Split screen P1 fishes: WASD walk · mouse aim · hold Space / LMB to cast, hold again to reel · Shift / RMB pull back  ·  More boats: press A on another controller"


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


func clock_text() -> String:
	var s := int(ceilf(maxf(time_left, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


func _theme_name() -> String:
	var n: String = _theme()["name"]
	if raining():
		n = "RAIN"
	elif is_night():
		n = "STARRY NIGHT"
	return n


func event_line() -> String:
	var a = players[0]
	if a.line_state == "fight" and a.hooked_kind() == FishScript.LEGEND:
		return "OLD WHISKERS HOOKED!  stamina %s" % _bar(legend_stamina * 1.2)
	if frenzy_t > 0.0:
		return "FISH FRENZY %ds - double points in the bubbles!" % int(ceilf(frenzy_t))
	if map_state == 1:
		return "TREASURE MAP: a boat must find the red X"
	if map_state == 2:
		return "BUOY DROPPED: cast next to the yellow buoy!"
	if legend_state == 1:
		return "OLD WHISKERS is in the lake!"
	return ""


func hud_text(p) -> String:
	if net.mode == "client" and not synced:
		return "Syncing with the VR player..."
	var line := "DAY %d - %s   SUNSET IN %s\nSCORE %d / %d%s" % [day, _theme_name(), clock_text(), score, target,
		"   STREAK x%d" % streak if streak >= 2 else ""]
	if state == "over":
		return line + "\nSUNSET - press A / Enter for another day"
	var ev := event_line()
	if ev != "":
		line += "\n" + ev
	var a = players[0]
	var ls: String = a.line_state
	if p.index == 0:
		if ls == "fight":
			line += "\nLINE TENSION %s" % _bar(float(a.tension))
		return line
	var nxt: int = p.next_level_coins()
	line += "\n%s  coins %d%s" % [BoatScript.LEVEL_NAMES[p.level], p.coins, (" (upgrade at %d)" % nxt) if nxt > 0 else " (max!)"]
	if ls == "fight":
		line += "\nFISH ON! Line tension %s" % _bar(float(a.tension))
	if golden_bait:
		line += "\nGOLDEN BAIT is ready!"
	return line


## The contextual "what do I do now?" tip for each player (big text at the bottom of their view).
func tip_text(p) -> String:
	if net.mode == "client" and not synced:
		return ""
	if state == "over":
		return "Press A for another day!"
	var a = players[0]
	if p.index == 0:
		var h: String = a.hint
		if a.line_state == "ready" and frenzy_t > 0.0:
			h += "\nAim for the BUBBLES - double points!"
		elif a.line_state == "ready" and map_state == 2:
			h += "\nCast next to the YELLOW BUOY!"
		return h
	var bp: Vector3 = p.global_position
	if a.line_state == "fight":
		var near := _flat_dist(bp, a.lure_pos) < 5.0
		if a.hooked_kind() == FishScript.LEGEND:
			return "Press A right next to OLD WHISKERS to SPLASH him tired!" if near else "OLD WHISKERS IS HOOKED! Row to him and SPLASH (A)!"
		return "Press A now - SPLASH next to the fish to help land it!" if near else "Fish on! Row over and SPLASH (A) next to it to help"
	var np: Vector3 = p.net_point()
	for t in treasures:
		if t.kind >= 0 and _flat_dist(t.position, np) < p.net_reach() + 1.0:
			return "Press A to scoop the %s!" % str(t.info()["name"]).to_upper()
	if map_state == 1:
		if _flat_dist(bp, map_pos) < 3.5:
			return "Press A to drop a buoy on the X!"
		return "Row to the big RED X (follow the red light) and press A there"
	if legend_state == 1 and a.line_state == "waiting":
		return "OLD WHISKERS is here - row close and press X to call him to the bobber!"
	if frenzy_t > 0.0:
		return "FISH FRENZY! Herd fish into the bubbles - A splashes them away from you"
	if a.line_state == "waiting":
		for f in fish:
			if f.kind >= 0 and FishScript.is_species(f.kind) and _flat_dist(f.position, bp) < 9.0:
				return "Press X to call a fish to the red bobber!"
		return "The bobber is out: row near fish, then press X to call one"
	if day == 1 and state_t < 30.0:
		return "Row with the left stick - look for floating treasure!"
	return "Look for floating treasure (A scoops it) - coins upgrade your boat!"


func update_tip(p, l: Label) -> void:
	var t := tip_text(p)
	if l.text != t:
		l.text = t


func _bar(v: float) -> String:
	var n := int(clampf(v, 0.0, 1.2) / 1.2 * 10.0)
	return "[" + "#".repeat(n) + "-".repeat(10 - n) + "]"


func _update_board() -> void:
	if state == "over" and summary_day == day and day_summary != "":
		if board_text != day_summary:
			board_text = day_summary
			lake.board_label.text = day_summary
		_update_journal_board()
		return
	var counts := {}
	for k in catches:
		var ki: int = k
		counts[ki] = int(counts.get(ki, 0)) + 1
	var lines: Array[String] = []
	for k in FishScript.TYPES.size():
		if counts.has(k):
			var d: Dictionary = FishScript.TYPES[k]
			lines.append("%s x%d" % [str(d["name"]), int(counts[k])])
	var t := "DAY %d - %s\nSCORE %d / %d%s\nSUNSET IN %s%s\n%s" % [day, _theme_name(), score, target,
		"  GOAL!" if goal_hit else "", clock_text(), ("   STREAK x%d" % streak) if streak >= 2 else "",
		", ".join(lines) if not lines.is_empty() else "(no catches yet)"]
	if biggest != "":
		t += "\nBIGGEST: " + biggest
	var ev := event_line()
	if ev != "":
		t += "\n" + ev
	if t != board_text:
		board_text = t
		lake.board_label.text = t
	_update_journal_board()


func _update_journal_board() -> void:
	var lines: Array[String] = ["FISH JOURNAL   %d / %d found" % [_journal_found(), _species_total()]]
	for k in FishScript.TYPES.size():
		if not FishScript.is_species(k):
			continue
		var d: Dictionary = FishScript.TYPES[k]
		var c := journal_counts[k] if k < journal_counts.size() else 0
		if c > 0:
			var bk := journal_best[k] if k < journal_best.size() else 0.0
			lines.append("%s%s  x%d  (best %.1f kg)" % ["NEW! " if new_today.has(k) else "", str(d["name"]), c, bk])
		else:
			lines.append("? ? ? - %s" % str(d["hint"]))
	var t := "\n".join(lines)
	if t != journal_text:
		journal_text = t
		lake.journal_label.text = t


func _update_vr_text() -> void:
	if help_label.modulate.a > 0.0 and day >= 2:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if players.is_empty() or not players[0].vr_like() or players[0].xr_camera == null:
		return
	var a = players[0]
	var cam: Node3D = a.xr_camera
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 44
		vr_center.outline_size = 26
		vr_center.pixel_size = 0.0022
		vr_center.no_depth_test = false
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 1100.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_center)
	vr_center.no_depth_test = false  # nearer things (rod, bobber) must pass in front of the text
	vr_center.text = _vr_short(center_label.text)
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, cam, self, 0.25, 1.8)
	# Casting hint: a panel low in front while the rod is ready (below the centre banner).
	if vr_hint == null:
		vr_hint = Label3D.new()
		vr_hint.font_size = 40
		vr_hint.outline_size = 22
		vr_hint.pixel_size = 0.002
		vr_hint.no_depth_test = false
		vr_hint.render_priority = 8
		vr_hint.outline_render_priority = 7
		vr_hint.width = 900.0
		vr_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_hint)
	vr_hint.no_depth_test = false
	var ls: String = a.line_state
	var show_panel := state == "play" and (ls == "ready" or ls == "landing") and center_label.modulate.a < 0.05
	vr_hint.visible = show_panel
	if show_panel:
		vr_hint.text = tip_text(a)
		vr_hint.modulate = a.hint_col
		VrText.follow(vr_hint, cam, self, -0.45, 1.6)
	# While the line is out, the hint floats above the bobber: that's where the angler is looking.
	if bobber_label == null:
		bobber_label = Label3D.new()
		bobber_label.font_size = 56
		bobber_label.outline_size = 18
		bobber_label.width = 700.0
		bobber_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bobber_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		bobber_label.render_priority = 6
		add_child(bobber_label)
	var out := ls == "waiting" or ls == "bite" or ls == "fight"
	bobber_label.visible = out and state == "play"
	if bobber_label.visible:
		var lp: Vector3 = a.lure_pos
		var dist := cam.global_position.distance_to(lp)
		var t: String = a.hint
		if ls == "fight":
			t += "\n%s" % _bar(float(a.tension))
			if a.hooked_kind() == FishScript.LEGEND and legend_stamina > 0.0:
				t += "\nWHISKERS %s" % _bar(legend_stamina * 1.2)
		bobber_label.text = t
		bobber_label.modulate = a.hint_col
		bobber_label.pixel_size = clampf(dist * 0.00055, 0.002, 0.009)
		bobber_label.global_position = Vector3(lp.x, 0.55 + dist * 0.035, lp.z)
		face_label(bobber_label)
		if not a.vr:
			bobber_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED


## The VR angler only needs the headline: drop the TV boat players' instructions and keep at most
## two short lines (the family found the full announcements too much text to read in VR).
func _vr_short(text: String) -> String:
	var keep: PackedStringArray = []
	var trigger := ""
	for line in text.split("\n", false):
		var l := line.strip_edges()
		var low := l.to_lower()
		if low.begins_with("trigger"):
			trigger = "Trigger: " + l.get_slice(":", 1).strip_edges()  # how the angler carries on
			continue
		if l == "" or low.begins_with("boats") or low.contains("left stick") or low.contains("press a") \
				or low.contains("press x") or low.contains("(a)") or low.contains("enter:"):
			continue
		if keep.size() < 2:
			keep.append(l)
	if trigger != "":
		keep.append(trigger)
	return "\n".join(keep)

