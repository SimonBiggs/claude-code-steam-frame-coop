extends Node3D
const VrText := preload("res://core/vr_text.gd")
## Cannon Cove: our pirate ship against waves of pirate ships, boarders and a sea monster.
## The VR gunner (player 1) swings and fires the cannons; the TV deckhands (players 2 to 7, drop-in:
## press A on a spare controller to join) keep the cannons loaded, patch leaks and shoot boarders. Gold for every ship sunk; the game ends when
## the hold fills with water and the ship goes down.
##
## SIMPLE_MODE (the family: "all of the games have become too complicated", "everything's being driven
## by text"): the VR gunner aims and fires at pirate ships; the deckhands carry cannonballs to the cannons.
##  - TARGET PRACTICE first, exactly as before (Simon's favourite), plus a see-through ghost hand
##    (ghost_hand.gd) that shows reach, squeeze, swing, let go instead of the hint text.
##  - One new thing per wave: 1-2 a few slow ships whose shots don't hurt, 3 shots make LEAKS (one at a
##    time: a glowing ring, the deckhands' arrow), 4 BOARDERS (one at a time), 5 the SEA MONSTER's
##    tentacles, 6 the KRAKEN. Bonus seas after that bring back the bomb boats.
##  - Everything beside the gunner reacts to touch (props.gd): a bell to ring, a rope to swing, a barrel
##    that wobbles, Polly squawks when poked, and spare cannonballs / the barrel can be picked up and
##    thrown overboard (SPLASH) - or at boarders and tentacles.
##  - Off: hint panels, the help panel, gold / water / ammo numbers (the sea rises up the hull instead,
##    and the cannon's rack shows its balls), the treasure ship and golden balls, supply barrels,
##    streaks and bonuses, parrot speech bubbles, crew awards. Text: one short headline ("WAVE 2!").
const SIMPLE_MODE := true

const World := preload("res://games/cannon_cove/world.gd")
const PlayerScript := preload("res://games/cannon_cove/player.gd")
const CannonScript := preload("res://games/cannon_cove/cannon.gd")
const BallScript := preload("res://games/cannon_cove/ball.gd")
const ShipScript := preload("res://games/cannon_cove/enemy_ship.gd")
const TentacleScript := preload("res://games/cannon_cove/tentacle.gd")
const BoarderScript := preload("res://games/cannon_cove/boarder.gd")
const LeakScript := preload("res://games/cannon_cove/leak.gd")
const TargetScript := preload("res://games/cannon_cove/target.gd")
const KrakenScript := preload("res://games/cannon_cove/kraken.gd")
const ParrotScript := preload("res://games/cannon_cove/parrot.gd")
const GuideScript := preload("res://games/cannon_cove/guide.gd")
const HudScript := preload("res://games/cannon_cove/hud.gd")
const PropsScript := preload("res://games/cannon_cove/props.gd")
const GhostHandScript := preload("res://games/cannon_cove/ghost_hand.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")

const GRAVITY := 9.8
const MAX_LEAKS := 7
const LEAK_RATE := 1.25  # % of the hold per second per leak (two deckhands)
const MAX_PLAYERS := 7  # the gunner (index 0) plus up to six deckhands (indices 1..6)
const PLAYER_COLORS: Array[Color] = [Color(0.25, 0.45, 0.95), Color(1.0, 0.75, 0.2), Color(1.0, 0.45, 0.8),
	Color(0.35, 0.9, 0.4), Color(0.3, 0.9, 0.95), Color(1.0, 0.5, 0.15), Color(0.7, 0.45, 1.0)]
const KEYS2_DEVICE := -2  # pseudo device id for the second keyboard set (arrows + Enter/Shift) on the TV
const CANNON_SPOTS := [
	[Vector3(-3.55, 0.85, 1.0), Vector3.LEFT],
	[Vector3(-3.55, 0.85, 6.0), Vector3.LEFT],
	[Vector3(3.55, 0.85, 1.0), Vector3.RIGHT],
	[Vector3(3.55, 0.85, 6.0), Vector3.RIGHT],
]
## Extra sounds made with core/sfx.gd's synth: [seconds, start Hz, end Hz, volume, wave, noise]
const EXTRA_SOUNDS := {
	"cannon": [0.9, 140.0, 28.0, 0.85, "saw", 0.75],
	"splash": [0.5, 900.0, 160.0, 0.35, "sine", 0.9],
	"musket": [0.2, 700.0, 120.0, 0.4, "square", 0.75],
	"dry": [0.06, 1900.0, 1500.0, 0.25, "square", 0.3],
	"coin": [0.3, 988.0, 1976.0, 0.3, "square", 0.0],
	"creak": [0.6, 150.0, 80.0, 0.4, "saw", 0.35],
	"hammer": [0.07, 520.0, 220.0, 0.4, "square", 0.6],
	"load": [0.18, 260.0, 620.0, 0.35, "tri", 0.15],
	"tentacle": [0.9, 95.0, 55.0, 0.55, "saw", 0.25],
	"rope": [0.4, 1200.0, 400.0, 0.2, "sine", 0.7],
	"bell": [1.3, 880.0, 860.0, 0.32, "sine", 0.0],
	"squawk": [0.22, 1300.0, 2300.0, 0.22, "saw", 0.3],
	"thunder": [1.8, 70.0, 28.0, 0.75, "saw", 0.9],
	"cheer": [0.9, 520.0, 1250.0, 0.28, "tri", 0.45],
	"roar": [1.5, 130.0, 45.0, 0.75, "saw", 0.45],
	"bullseye": [0.55, 784.0, 1568.0, 0.35, "tri", 0.0],
	"golden": [0.7, 1046.0, 2093.0, 0.3, "sine", 0.0],
	"clang": [0.3, 1700.0, 1550.0, 0.35, "square", 0.25],
	"kaboom": [1.2, 110.0, 22.0, 0.9, "saw", 0.8],
	"firework": [0.45, 300.0, 2400.0, 0.25, "sine", 0.6],
}
## The voyage: five waves, then the Kraken; after that the "bonus seas" go on forever.
const BOSS_WAVE := 6
const WAVE_NAMES := ["", "CALM SEAS", "RAIDERS!", "FIRE SHIPS!", "MONSTER WATERS", "THE STORM", "THE KRAKEN"]
const PRACTICE_HITS := 3

var players: Array = []
var cameras: Array[Camera3D] = []
var cannons: Array = []
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var net: Node
var ready_to_play := false
var synced := false
var net_ids := 0
var ghost_nodes := {}
var ghost_cam: Camera3D
var vr_center: Label3D
var music  # core/music.gd (an AudioStreamPlayer)
var sfx: Node
var sea: Node3D
var sea_level := World.BASE_SEA
var gauge: Label3D
var gulls: Array[Node3D] = []
var t_world := 0.0

var wave := 0
var gold := 0
var water := 0.0
var ships_to_spawn := 0
var tentacles_to_spawn := 0
var spawn_timer := 0.0
var break_timer := 5.0
var in_break := true
var game_over := false
var game_over_time := 0.0
var hammer_t := 0.0

# The voyage.
var phase := "practice"  # practice, wave, break, victory
var parts: Dictionary = {}  # pieces of the world that animate (see world.gd build())
var spawn_queue: Array[String] = []
var practice_hits := 0
var practice_t := 0.0
var practice_spawn_t := 1.0
var practice_free_t := 0.0
var event_t := 25.0
var event_flip := false
var golden_balls := 0
var streak := 0
var last_sink_t := -10.0
var stats: Array = []
var mood := "sunset"
var mood_k: Dictionary = {}
var lightning_t := 8.0
var flash_t := 0.0
var victory_t := 0.0
var parrot: Node3D
var parrot_t := 0.0
var announced := {}
var gunner_grabbed := false
var gunner_fired := false
var vr_hint: Label3D
var stats_label: Label
var stats_text := ""
var help_panel: PanelContainer
var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var join_t := 0.0
var view_grid: GridContainer
var view_count := 0
var say_t := 0.0
var simple := SIMPLE_MODE  # other scripts read main.simple
var props: Node3D  # simple mode: touchable things beside each cannon (props.gd)
var ghost_hand: Node3D  # simple mode: the practice ghost hand (VR gunner only)


func _ready() -> void:
	randomize()
	parts = World.build(self)
	sea = parts.sea
	_build_cannons()
	_build_extras()
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
		# TV machine: join the VR gunner's game as the deckhands, or fall back to local split screen.
		_show_center("Connecting to the VR gunner…", 0.0)
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
	update_manned()
	ready_to_play = true
	print("Cannon Cove: %s mode" % mode)
	_rejoin_party()
	if SIMPLE_MODE:
		_show_center("ALL ABOARD!" if mode == "client" else "CANNON COVE!", 2.0)
		parrot_say("")
		return
	if mode == "host":
		_show_center("CANNON COVE\nTARGET PRACTICE while the TV crew joins!\nGrab the glowing cannon handle and shoot the target", 6.0)
	elif mode == "client":
		_show_center("ALL ABOARD!", 1.5)
	else:
		_show_center("CANNON COVE\nTarget practice first - then the pirates come!", 4.0)
	parrot_say("SQUAWK! Shoot the target!")


func next_net_id() -> int:
	net_ids += 1
	return net_ids


# --- World -------------------------------------------------------------------

func _build_cannons() -> void:
	for i in CANNON_SPOTS.size():
		var c := CannonScript.new()
		c.main = self
		c.index = i
		c.outboard = CANNON_SPOTS[i][1]
		c.position = CANNON_SPOTS[i][0]
		c.ammo = 2
		add_child(c)
		cannons.append(c)


func _build_extras() -> void:
	# The hold's water gauge, floating by the main mast where everyone (VR too) can see it.
	gauge = Label3D.new()
	gauge.font_size = 72
	gauge.outline_size = 26
	gauge.pixel_size = 0.006
	gauge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gauge.position = Vector3(0, 3.4, -1.0)
	add_child(gauge)
	# Seagulls circling overhead.
	var white := World.mat(Color(0.98, 0.98, 0.98))
	for i in 4:
		var g := Node3D.new()
		for s in [-1.0, 1.0]:
			var wing := World.box(g, Vector3(0.7, 0.04, 0.22), Vector3(s * 0.33, 0, 0), white)
			wing.rotation.z = s * 0.35
		World.box(g, Vector3(0.12, 0.12, 0.4), Vector3.ZERO, white)
		add_child(g)
		gulls.append(g)
	parrot = ParrotScript.new()
	parrot.main = self
	parrot.perches = parts.parrot_perches
	if SIMPLE_MODE:
		gauge.visible = false  # the sea rising up the hull shows the water instead
		if parts.has("pile_sign"):
			parts.pile_sign.visible = false
		props = PropsScript.new()
		props.main = self
		add_child(props)
		parrot.perches = props.perches()  # on a post right beside the gunner, within reach
	parrot.scale = Vector3.ONE * 1.4
	add_child(parrot)
	for i in MAX_PLAYERS:
		stats.append({"shots": 0, "hits": 0, "sinks": 0, "loads": 0, "patches": 0, "splashes": 0, "monster": 0,
			"kegs": 0, "best_streak": 0})


func _animate_world(delta: float) -> void:
	t_world += delta
	sea_level = lerpf(World.BASE_SEA, World.SUNK_SEA, clampf(water / 100.0, 0.0, 1.0))
	sea.position.y = sea_level
	for i in gulls.size():
		var a := t_world * (0.25 + i * 0.04) + i * 1.7
		var r := 14.0 + i * 5.0
		var g := gulls[i]
		g.position = Vector3(cos(a) * r, 13.0 + i * 1.5 + sin(t_world * 0.7 + i) * 0.6, sin(a) * r - 2.0)
		g.rotation = Vector3(0.0, -a, 0.25)
		var flap := sin(t_world * 6.0 + i) * 0.4
		var w0: Node3D = g.get_child(0)
		var w1: Node3D = g.get_child(1)
		w0.rotation.z = -0.35 - flap
		w1.rotation.z = 0.35 + flap
	gauge.text = "WATER IN THE HOLD  %d%%" % int(water)
	gauge.modulate = Color(0.5, 0.85, 1.0) if water < 60.0 else Color(1.0, 0.4, 0.3)
	_animate_ship(delta)
	_update_mood(delta)


## Sails billow, flags flap, the wheel turns, lanterns flicker and the gold pile grows.
func _animate_ship(delta: float) -> void:
	var sails: Array = parts.get("sails", [])
	for i in sails.size():
		var s: Node3D = sails[i]
		s.scale = Vector3(1.0, 1.0, 1.0 + 0.6 * sin(t_world * 1.3 + i))
	var flags: Array = parts.get("flags", [])
	for i in flags.size():
		var f: Node3D = flags[i]
		f.rotation.y = sin(t_world * 4.0 + i * 2.0) * 0.3
	var wheel: Node3D = parts.get("wheel")
	if wheel:
		wheel.rotation.z = sin(t_world * 0.35) * 0.6
	var lm: StandardMaterial3D = parts.get("lantern_mat")
	if lm:
		lm.emission_energy_multiplier = 2.6 + sin(t_world * 9.0) * 0.3 + sin(t_world * 23.0) * 0.2 + mood_value("night") * 1.5
	var wm: StandardMaterial3D = parts.get("window_mat")
	if wm:
		wm.emission_energy_multiplier = 1.5 + mood_value("night") * 1.5
	var beam: Node3D = parts.get("beam")
	if beam:
		beam.rotation.y = t_world * 0.6
	var pile: Node3D = parts.get("gold_pile")
	if pile:
		var k := clampf(float(gold) / 1500.0, 0.0, 1.0)
		pile.scale = pile.scale.lerp(Vector3(1.0, 0.05 + k * 0.9, 0.62 + k * 0.2), 1.0 - exp(-3.0 * delta))
	var gb: Node3D = parts.get("golden_ball")
	if gb:
		gb.visible = golden_balls > 0
		gb.position.y = 1.32 + sin(t_world * 3.0) * 0.08


func _wanted_mood() -> String:
	if phase == "victory":
		return "dawn"
	if wave <= 2:
		return "sunset"
	if wave <= 4:
		return "dusk"
	if wave == 5:
		return "storm"
	if wave == BOSS_WAVE:
		return "night"
	if wave == BOSS_WAVE + 1:
		return "dawn"
	return ["sunset", "dusk", "storm", "night"][(wave - BOSS_WAVE - 2) % 4]


func mood_value(key: String) -> float:
	return float(mood_k.get(key, 0.0))


## Glides the sky, sun, sea and clouds towards the current wave's mood (same on both machines).
func _update_mood(delta: float) -> void:
	mood = _wanted_mood()
	var m: Dictionary = World.MOODS[mood]
	var k := 1.0 - exp(-0.6 * delta)
	if mood_k.is_empty():
		k = 1.0
	for key in m:
		var v = m[key]
		if v is Color:
			var cur: Color = mood_k.get(key, v)
			mood_k[key] = cur.lerp(v, k)
		else:
			var cf: float = mood_k.get(key, v)
			mood_k[key] = lerpf(cf, float(v), k)
	var sky: ProceduralSkyMaterial = parts.sky
	var flash := 0.0
	if mood == "storm":
		flash = _lightning(delta)
	sky.sky_top_color = (mood_k.top as Color).lerp(Color(0.85, 0.88, 1.0), flash * 0.6)
	sky.sky_horizon_color = (mood_k.horizon as Color).lerp(Color(0.9, 0.92, 1.0), flash * 0.5)
	sky.ground_horizon_color = mood_k.ground
	var sun: DirectionalLight3D = parts.sun
	sun.light_color = mood_k.sun
	sun.light_energy = mood_value("sun_e") + flash * 1.6
	var e: Environment = parts.env
	e.ambient_light_energy = mood_value("amb") + flash * 0.6
	e.fog_light_color = mood_k.fog
	var sm: ShaderMaterial = parts.sea_mat
	sm.set_shader_parameter("chop", mood_value("chop"))
	sm.set_shader_parameter("night", mood_value("night"))
	var fm: StandardMaterial3D = parts.far_mat
	fm.albedo_color = Color(0.25, 0.42, 0.55).lerp(Color(0.05, 0.1, 0.18), mood_value("night"))
	var cm: StandardMaterial3D = parts.clouds_mat
	cm.albedo_color = mood_k.cloud
	cm.emission = mood_k.cloud
	var night := mood_value("night")
	var stars: Node3D = parts.stars
	stars.visible = night > 0.05
	(parts.stars_mat as StandardMaterial3D).albedo_color.a = clampf(night * 1.2 - 0.2, 0.0, 1.0)
	var moon: Node3D = parts.moon
	moon.visible = night > 0.05
	(parts.moon_mat as StandardMaterial3D).albedo_color.a = night
	(parts.beam_mat as StandardMaterial3D).albedo_color.a = 0.06 + night * 0.2


## Storm: lightning flickers now and then (each machine on its own - it's only scenery).
func _lightning(delta: float) -> float:
	lightning_t -= delta
	if lightning_t <= 0.0:
		lightning_t = randf_range(7.0, 15.0)
		flash_t = 0.35
		get_tree().create_timer(randf_range(0.5, 1.2)).timeout.connect(func() -> void:
			_sfx().play("thunder", -4.0, randf_range(0.8, 1.1)))
	flash_t = maxf(0.0, flash_t - delta)
	if flash_t <= 0.0:
		return 0.0
	return 1.0 if (flash_t > 0.25 or (flash_t > 0.08 and flash_t < 0.14)) else 0.25


func make_material(color: Color, glow: float) -> StandardMaterial3D:
	return World.mat(color, glow)


## Keeps deckhands and boarders out of the cannons.
func cannon_obstacles() -> Array:
	var out := []
	for c in cannons:
		var p: Vector3 = c.global_position
		out.append([Vector2(p.x, p.z), 0.75])
	return out


func update_manned() -> void:
	var s: int = players[0].station if not players.is_empty() else 1
	for c in cannons:
		c.manned = c.index == s


# --- Effects (each one shows here and is sent to the other machine) ----------

func _sfx() -> Node:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
		for k in EXTRA_SOUNDS:
			var d: Array = EXTRA_SOUNDS[k]
			sfx.streams[k] = sfx._make(d[0], d[1], d[2], d[3], d[4], d[5])
	return sfx


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_sfx().play(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 72
	l.outline_size = 26
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.8, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.6)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.6)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


func _particles(pos: Vector3, color: Color, amount: int, size: float, speed: float, gravity: float, life: float, spread: float = 180.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := World.mat(color, 1.0)
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


func smoke(pos: Vector3, size: float) -> void:
	_particles(pos, Color(0.95, 0.92, 0.88), 14, 0.35 * size, 3.0, -1.0, 1.0, 40.0)
	_particles(pos, Color(1.0, 0.7, 0.2), 8, 0.18 * size, 6.0, 0.0, 0.25, 30.0)
	if net:
		net.event("smoke", [pos, size])


func splash(pos: Vector3, size: float) -> void:
	_particles(pos, Color(0.7, 0.9, 1.0), int(18 * size), 0.16 * size, 8.0 * size, 14.0, 0.9, 25.0)
	_sfx().play("splash", -6.0, randf_range(0.8, 1.2))
	if net:
		net.event("splash", [pos, size])


func explosion(pos: Vector3, color: Color, size: float) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 14
	sm.rings = 7
	ball.mesh = sm
	var mat := World.mat(color, 5.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.3
	var t := ball.create_tween().set_parallel()
	t.tween_property(ball, "scale", Vector3.ONE * 3.0 * size, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_delay(0.1)
	t.chain().tween_callback(ball.queue_free)
	_particles(pos, Color(0.55, 0.35, 0.2), int(14 * size), 0.12, 9.0 * size, 18.0, 1.0)  # splinters
	_particles(pos, Color(0.9, 0.88, 0.85), 10, 0.4 * size, 2.5, -1.5, 1.2, 60.0)  # smoke
	if net:
		net.event("boom", [pos, color, size])


func musket_fx(shooter: int, from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist > 0.5:
		var tracer := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, dist)
		tracer.mesh = bm
		var mat := World.mat(Color(1.0, 0.9, 0.5), 3.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tracer.material_override = mat
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tracer)
		var start := from + (to - from).normalized() * 0.6
		tracer.look_at_from_position((start + to) * 0.5, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
		var t := tracer.create_tween()
		t.tween_property(mat, "albedo_color:a", 0.0, 0.15)
		t.tween_callback(tracer.queue_free)
	_particles(from + (to - from).normalized() * 0.9 + Vector3.DOWN * 0.15, Color(0.95, 0.95, 0.9), 6, 0.1, 1.5, -0.5, 0.6, 40.0)
	_sfx().play("musket", -6.0, randf_range(0.9, 1.15))
	if net:
		net.event("musket", [shooter, from, to])


func grapple_fx(from: Vector3, to: Vector3) -> void:
	var rope := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, from.distance_to(to))
	rope.mesh = bm
	rope.material_override = World.mat(Color(0.75, 0.6, 0.35))
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope)
	rope.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	get_tree().create_timer(1.6).timeout.connect(rope.queue_free)
	_sfx().play("rope", -4.0)
	if net:
		net.event("grapple", [from, to])


func add_shake(pos: Vector3, amount: float) -> void:
	for p in players:
		var falloff := clampf(1.0 - p.global_position.distance_to(pos) / 25.0, 0.2, 1.0)
		p.shake = maxf(p.shake, amount * falloff)


## A cannonball (or, on the client, its look-alike). Mega = a golden cannonball.
func spawn_ball(origin: Vector3, vel: Vector3, enemy: bool, visual_only: bool, mega: bool = false) -> void:
	var b := BallScript.new()
	b.main = self
	b.vel = vel
	b.enemy = enemy
	b.mega = mega
	b.visual_only = visual_only
	b.position = origin
	add_child(b)
	if not visual_only and net:
		net.event("ball", [origin, vel, enemy, mega])


## Colourful paper bits (celebrations).
func confetti(pos: Vector3, broadcast: bool = true) -> void:
	var cols := [Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 1.0), Color(0.5, 1.0, 0.4), Color(1.0, 0.5, 0.9)]
	for i in 3:
		_particles(pos, cols[(i + randi()) % cols.size()], 10, 0.09, 7.0, 6.0, 1.6, 70.0)
	if broadcast and net:
		net.event("confetti", [pos])


## A fountain of gold coins (sinking a ship).
func coins_fx(pos: Vector3, broadcast: bool = true) -> void:
	_particles(pos, Color(1.0, 0.82, 0.2), 16, 0.12, 9.0, 16.0, 1.3, 35.0)
	if broadcast and net:
		net.event("coins", [pos])


## A firework bursting in the sky (victory).
func fireworks(pos: Vector3, broadcast: bool = true) -> void:
	var col := Color.from_hsv(randf(), 0.7, 1.0)
	_particles(pos, col, 28, 0.14, 11.0, 3.0, 1.6, 180.0)
	_particles(pos, Color(1.0, 1.0, 0.85), 10, 0.08, 6.0, 2.0, 1.0, 180.0)
	_sfx().play("firework", -4.0, randf_range(0.8, 1.2))
	if broadcast and net:
		net.event("firework", [pos])


## Three dolphins leap alongside the ship (just for fun).
func dolphins(side: float, z0: float) -> void:
	var body_mat := World.mat(Color(0.45, 0.55, 0.7), 0.0, 0.3)
	var belly_mat := World.mat(Color(0.9, 0.92, 0.95))
	for i in 3:
		var d := Node3D.new()
		var b := World.sphere(d, 0.5, Vector3.ZERO, body_mat, 10)
		b.scale = Vector3(0.55, 0.55, 1.8)
		var belly := World.sphere(d, 0.4, Vector3(0, -0.12, 0), belly_mat, 8)
		belly.scale = Vector3(0.5, 0.4, 1.6)
		var fin := World.box(d, Vector3(0.06, 0.45, 0.35), Vector3(0, 0.38, 0.1), body_mat)
		fin.rotation.x = -0.5
		var tail := World.box(d, Vector3(0.8, 0.06, 0.3), Vector3(0, 0, 0.95), body_mat)
		tail.rotation.x = 0.2
		World.sphere(d, 0.06, Vector3(0.2, 0.12, -0.6), World.mat(Color.BLACK), 4)
		World.sphere(d, 0.06, Vector3(-0.2, 0.12, -0.6), World.mat(Color.BLACK), 4)
		add_child(d)
		var x := side * (8.5 + i * 1.6)
		var start := Vector3(x, sea_level - 1.0, z0 + i * 2.5)
		d.position = start
		var tw := d.create_tween()
		for j in 4:
			var a := start - Vector3(0, 0, j * 7.0)
			tw.tween_callback(func() -> void: d.position = a)
			tw.tween_method(func(k: float) -> void:
				d.position = a + Vector3(0, sin(k * PI) * 2.6, -k * 7.0)
				d.rotation.x = cos(k * PI) * 0.9, 0.0, 1.0, 1.1).set_delay(0.25 * i)
		tw.tween_callback(d.queue_free)
	_sfx().play("splash", -10.0, 1.4)


## Polly the parrot says something (on both machines).
func parrot_say(text: String) -> void:
	if parrot == null or not is_instance_valid(parrot):
		return
	if SIMPLE_MODE:
		text = ""  # just a squawk and a flap, no speech bubble
	parrot_t = 0.0
	parrot.say(text)
	if net:
		net.event("parrot", [text])


# --- Players -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	# All seven crew slots exist from the start (so snapshots and net indices line up); the gunner and
	# player 2 start active, players 3-7 drop in when someone presses A on a spare controller.
	_ensure_players(mode)


## Creates any missing player slots (also after a hot reload that raised MAX_PLAYERS).
func _ensure_players(mode: String) -> void:
	while players.size() < MAX_PLAYERS:
		var i := players.size()
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		p.main = self
		p.ghost = mode == "client" and i == 0
		p.remote = mode == "host" and i >= 1
		if i == 0:
			p.station = 1
			p.position = cannons[1].stand_pos()
			p.key_set = 1 if mode == "local" else 0
			p.mouse_look = mode != "local"
		else:
			p.position = spawn_pos(i)
			p.key_set = 0 if i == 1 else -1
			p.mouse_look = i == 1
		add_child(p)
		players.append(p)
		if i >= 2:
			p.set_active(false)


func spawn_pos(i: int) -> Vector3:
	var pos := Vector3(-1.2 + 2.4 * ((i - 1) % 2), 0.0, -3.2 + 1.4 * ((i - 1) / 2))
	return World.constrain(pos, 0.35, cannon_obstacles())


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.4
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_vr_mirror(xr_cam: XRCamera3D) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	vp.add_to_group("gdev_capture")
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)
	return vp


## VR: the gunner is in the headset (main viewport). Otherwise one split-screen view per local player.
func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 is the gunner in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
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
	elif (OS.has_environment("CC_FAKE_VR") or OS.has_environment("BOT_VR")) and mode != "client":
		# Tests: the VR gunner's code runs without a headset; the bot moves the head and hands.
		print("Fake VR: the bot drives the VR gunner")
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		cam.position = Vector3(0, 1.25, 0)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		origin.add_child(left)
		left.position = Vector3(-0.25, 0.9, -0.2)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		origin.add_child(right)
		right.position = Vector3(0.25, 0.9, -0.2)
		players[0].fake_vr = true
		players[0].attach_xr(origin, cam, left, right)
	else:
		print("No VR headset: split screen")
	_ensure_view_grid()
	for p in players:
		if p.active:
			_ensure_view(p)
	if mode == "client":
		_add_bubble(players[1].hud, _build_ghost_mirror())
	_layout_views()


func _ensure_view_grid() -> GridContainer:
	if view_grid != null and is_instance_valid(view_grid):
		return view_grid
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_grid = GridContainer.new()
	view_grid.add_theme_constant_override("h_separation", 4)
	view_grid.add_theme_constant_override("v_separation", 4)
	layer.add_child(view_grid)
	view_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return view_grid


## True for a crew member who is played on this machine with a flat screen view.
func _is_local_flat(p) -> bool:
	return not (p.vr or p.remote or p.ghost)


## Lazily builds a player's split-screen view (camera, SubViewport and HUD).
func _ensure_view(p) -> void:
	if p.has_meta("view") or not _is_local_flat(p):
		return
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ensure_view_grid().add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(vp)
	var cam := Camera3D.new()
	cam.far = 900.0
	vp.add_child(cam)
	cam.current = true
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud


## Split-screen grid: 1 view full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (7 as 4x2). Empty cells
## invite another player to join. More views render at a lower 3D resolution with fewer shadows.
func _layout_views() -> void:
	if view_grid == null or not is_instance_valid(view_grid):
		return
	var views: Array = []
	for p in players:
		if p.has_meta("view"):
			var v: Control = p.get_meta("view")
			v.visible = p.active
			if p.active:
				views.append(v)
	var n := views.size()
	var cols := 1 if n <= 1 else (2 if n <= 4 else (3 if n <= 6 else 4))
	var rows := int(ceil(float(maxi(n, 1)) / float(cols)))
	view_grid.columns = cols
	for i in views.size():
		view_grid.move_child(views[i], i)
	var scale_3d := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for v in views:
		var vp: SubViewport = v.get_child(0)
		vp.scaling_3d_scale = scale_3d
		vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
	# Empty grid cells: "press A to join" cards.
	var free_cells := cols * rows - n if n >= 3 and net.mode != "host" else 0
	var cards: Array = view_grid.get_children().filter(func(c: Node) -> bool: return c.has_meta("join_card"))
	while cards.size() < free_cells:
		var card := _make_join_card()
		view_grid.add_child(card)
		cards.append(card)
	for i in cards.size():
		var card: Control = cards[i]
		card.visible = i < free_cells
		view_grid.move_child(card, -1)
	if not players[0].vr:
		for c in get_children():
			if c is DirectionalLight3D:
				c.shadow_enabled = n <= 4
				c.directional_shadow_max_distance = 40.0 if n <= 2 else 25.0
	if n != view_count:
		view_count = n
		print("Split screen: %d view(s), %d column(s), 3D scale %.2f" % [n, cols, scale_3d])


func _make_join_card() -> Control:
	var card := PanelContainer.new()
	card.set_meta("join_card", true)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.18)
	card.add_theme_stylebox_override("panel", sb)
	var l := _make_label(30)
	l.text = "MORE CREW?\nPress A on a spare controller to join"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	card.add_child(l)
	return card


## Client: a camera following the VR gunner's replicated head, shown as a round picture-in-picture.
func _build_ghost_mirror() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(400, 400)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	add_child(vp)
	ghost_cam = Camera3D.new()
	ghost_cam.fov = 90.0
	ghost_cam.cull_mask = players[0].camera_cull_mask()
	vp.add_child(ghost_cam)
	ghost_cam.current = true
	return vp


func _add_bubble(hud: Control, source: SubViewport) -> void:
	if hud == null:
		return
	var bubble := TextureRect.new()
	bubble.texture = source.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bubble)
	bubble.size = Vector2(240, 240)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	var tag := Label.new()
	tag.text = "GUNNER (VR)"
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	bubble.add_child(tag)
	tag.position = Vector2(50, 240)


## The base controls, as before: player 2 gets the first controller (and the keyboard + mouse);
## in split screen the flat gunner gets the second. Other controllers join with A (see _poll_joins).
func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	if net.mode == "local":
		players[1].joy = pads[0] if pads.size() > 0 else -1  # deckhand
		players[0].joy = pads[1] if pads.size() > 1 else -1  # flat gunner
	elif net.mode == "client":
		players[1].joy = pads[0] if pads.size() > 0 else -1
	elif not players[0].vr:
		players[0].joy = pads[0] if pads.size() > 0 else -1
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


## Which player (index) a device drives on this machine, or -1.
func device_owner(device: int) -> int:
	for p in players:
		if p.ghost or p.remote:
			continue
		if device >= 0 and p.joy == device:
			return p.index
		if device == KEYS2_DEVICE and p.key_set == 1 and p.index >= 1:
			return p.index
	return -1


func _base_player(p) -> bool:
	return p.index == 0 or p.index == 1


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or net.mode == "host" and players[0].vr:
		return
	var owner := device_owner(device)
	if connected:
		print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
		if owner >= 0:
			return
		# A player who lost this controller gets it back; otherwise refill the base slots as before.
		for p in players:
			if _is_local_flat(p) and p.get_meta("lost_pad", -1) == device and not p.active and p.joy < 0:
				p.remove_meta("lost_pad")
				_join_player(p, device)
				return
		if net.mode == "local":
			if players[1].joy < 0:
				players[1].joy = device
			elif players[0].joy < 0:
				players[0].joy = device
		elif net.mode == "client" and players[1].joy < 0:
			players[1].joy = device
		elif net.mode == "host" and not players[0].vr and players[0].joy < 0:
			players[0].joy = device
		return
	print("Joypad %d disconnected" % device)
	if owner < 0:
		return
	var p = players[owner]
	p.joy = -1
	if _base_player(p):
		return  # still has the keyboard
	# A drop-in player without a keyboard: their deckhand leaves until the controller comes back.
	p.set_meta("lost_pad", device)
	_leave_player(p)


## Drop-in join: a spare controller (or the arrow keys on the TV) pressing A / Enter.
func _poll_joins(delta: float) -> void:
	join_t -= delta
	if game_over or join_t > 0.0 or get_tree().paused or net.mode == "host":
		return
	for id in Input.get_connected_joypads():
		if not (Input.is_joy_button_pressed(id, JOY_BUTTON_A) or Input.is_joy_button_pressed(id, JOY_BUTTON_X)):
			continue
		var owner := device_owner(id)
		if owner < 0:
			var p = _free_slot()
			if p != null:
				_join_player(p, id)
		elif not players[owner].active and net.mode == "client":
			join_t = 1.0
			net.send_action("join", [], owner)  # the host hasn't answered yet: ask again
		return
	if net.mode == "client":
		var keys2 := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SLASH)
		if keys2:
			var owner := device_owner(KEYS2_DEVICE)
			if owner < 0:
				var p = _free_slot()
				if p != null:
					_join_player(p, KEYS2_DEVICE)
			elif not players[owner].active:
				join_t = 1.0
				net.send_action("join", [], owner)


func _free_slot():
	for p in players:
		if p.index >= 2 and _is_local_flat(p) and not p.active and p.joy < 0 and p.key_set < 0 and not p.has_meta("lost_pad"):
			return p
	for p in players:  # reuse a slot whose controller never came back
		if p.index >= 2 and _is_local_flat(p) and not p.active and p.joy < 0 and p.key_set < 0:
			p.remove_meta("lost_pad")
			return p
	return null


## Gives player p the device and brings them aboard (on the TV the host confirms via snapshots).
func _join_player(p, device: int) -> void:
	join_t = 0.6
	if device == KEYS2_DEVICE:
		p.key_set = 1
	elif device >= 0:
		p.joy = device
	_remember_party()
	print("Player %d joins with %s" % [p.index + 1, "the arrow keys" if device == KEYS2_DEVICE else "controller %d" % device])
	if net.mode == "client":
		net.send_action("join", [], p.index)
		_show_center(("PLAYER %d!" if SIMPLE_MODE else "PLAYER %d IS COMING ABOARD!") % (p.index + 1), 1.2, false)
	else:
		p.position = spawn_pos(p.index)
		p.set_active(true)
		on_player_activity_changed(p)
		_show_center(("PLAYER %d!" if SIMPLE_MODE else "PLAYER %d JOINED THE CREW!") % (p.index + 1), 1.5)


func _leave_player(p) -> void:
	if p.key_set == 1 and p.index >= 2:
		p.key_set = -1
	p.reset_crew_state()
	_remember_party()
	if net.mode == "client":
		net.send_action("leave", [], p.index)
	elif p.active:
		p.set_active(false)
		on_player_activity_changed(p)
		if not SIMPLE_MODE:
			_show_center("Player %d left the crew" % (p.index + 1), 1.5)


## Keeps who-joined-with-what across scene reloads (restart, reconnect) so the crew stays aboard.
func _remember_party() -> void:
	var party := {}
	for p in players:
		if p.index >= 2 and _is_local_flat(p):
			if p.joy >= 0:
				party[p.joy] = p.index
			elif p.key_set == 1:
				party[KEYS2_DEVICE] = p.index
	Engine.set_meta("cc_party", party)


func _rejoin_party() -> void:
	if net.mode == "host" or not Engine.has_meta("cc_party"):
		return
	var party: Dictionary = Engine.get_meta("cc_party")
	var pads := Input.get_connected_joypads()
	for dev in party:
		var d: int = dev
		var idx: int = party[dev]
		if idx < 2 or idx >= players.size() or device_owner(d) >= 0:
			continue
		if d >= 0 and not pads.has(d):
			continue
		if d == KEYS2_DEVICE and net.mode != "client":
			continue
		_join_player(players[idx], d)


## Test hook: brings player `index` aboard without a device (tests/cannon_cove_bot.gd drives them).
func debug_join(index: int) -> bool:
	if index < 1 or index >= players.size():
		return false
	var p = players[index]
	match net.mode:
		"host":
			on_p2_action("join", [], index)
		"client":
			net.send_action("join", [], index)
		_:
			if not p.active:
				p.position = spawn_pos(index)
				p.set_active(true)
				on_player_activity_changed(p)
	return true


func on_player_activity_changed(p) -> void:
	if p.active and _is_local_flat(p):
		_ensure_view(p)
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active
	_layout_views()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


func deckhands() -> Array:
	return players.filter(func(p): return not p.gunner and p.active)


## Deckhands beyond the classic two (0..4): used to scale the enemies to the size of the crew.
func crew_extra() -> int:
	return maxi(0, deckhands().size() - 2)


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_update_vr_center()
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(1 if wave == BOSS_WAVE else maxi(wave - 1, 0) / 2)
	_animate_world(delta)
	_check_say(delta)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head if players[0].net_head != Transform3D() else players[0].ghost_head.global_transform
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	_update_guides()
	if props:
		props.tick(delta)
	if players.size() < MAX_PLAYERS:
		_ensure_players(net.mode)
	_poll_joins(delta)
	if net.mode == "client":
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		var vr_restart: bool = players[0].vr and (players[0].hand_r.is_button_pressed("ax_button") or players[0].hand_l.is_button_pressed("ax_button"))
		if game_over_time > 1.5 and (_restart_pressed() or vr_restart or (SIMPLE_MODE and game_over_time > 7.0)):
			get_tree().reload_current_scene()
		return
	_update_crew(delta)
	_update_coach(delta)
	if phase == "practice":
		_update_practice(delta)
		return
	if net.mode == "host" and not net.connected:
		return  # hold the waves until the deckhands join
	_update_water(delta)
	_random_events(delta)
	if phase == "victory":
		victory_t -= delta
		if victory_t <= 0.0:
			phase = "break"
			in_break = true
			break_timer = 4.0
			_show_center("BONUS SEAS!" if SIMPLE_MODE else "BONUS SEAS!\nKeep sailing - how much gold can you grab?", 3.0)
		return
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0 and not spawn_queue.is_empty():
		_spawn_next()
	if spawn_queue.is_empty() and get_tree().get_nodes_in_group("ships").is_empty() \
			and get_tree().get_nodes_in_group("tentacles").is_empty() and get_tree().get_nodes_in_group("boarders").is_empty() \
			and get_tree().get_nodes_in_group("krakens").is_empty():
		_end_wave()


# --- Target practice (before wave 1; the VR gunner practises while the TV crew joins) --------

func _update_practice(delta: float) -> void:
	var crew_ready: bool = net.mode != "host" or net.connected
	if crew_ready:
		practice_t += delta
	var have := false
	for tg in get_tree().get_nodes_in_group("targets"):
		if tg.kind == "practice":
			have = true
	if not have:
		practice_spawn_t -= delta
		if practice_spawn_t <= 0.0:
			practice_spawn_t = 1.2
			_spawn_target("practice")
	# Free practice balls, so nobody has to fetch anything yet.
	var c = cannons[players[0].station]
	var carried := false
	for p in deckhands():
		if p.carrying:
			carried = true
	if c.ammo <= 0 and not carried:
		practice_free_t += delta
		if practice_free_t > 1.4:
			practice_free_t = 0.0
			c.ammo += 1
			if not SIMPLE_MODE:
				popup(c.global_position + Vector3.UP * 1.3, "FREE PRACTICE BALL", Color(0.7, 1.0, 0.7))
			sound("load", -4.0, 1.2)
	else:
		practice_free_t = 0.0
	if crew_ready and (practice_hits >= PRACTICE_HITS or practice_t > 70.0):
		_end_practice()


func _spawn_target(kind: String) -> void:
	var tg := TargetScript.new()
	tg.main = self
	tg.kind = kind
	tg.net_id = next_net_id()
	var pos: Vector3
	if kind == "practice":
		var c = cannons[players[0].station]
		var dist: float = [15.0, 20.0, 26.0, 18.0][practice_hits % 4]
		var dir: Vector3 = Basis(Vector3.UP, randf_range(-0.45, 0.45)) * c.outboard
		pos = Vector3(c.global_position.x, 0.0, c.global_position.z) + dir * dist
	else:
		var side := -1.0 if randf() < 0.5 else 1.0
		pos = Vector3(side * randf_range(20.0, 30.0), 0.0, randf_range(-26.0, -14.0))
		tg.drift = Vector3(0, 0, randf_range(1.2, 1.8))
	pos.y = sea_level
	tg.position = pos
	add_child(tg)
	if kind != "practice":
		splash(pos, 1.5)
		if SIMPLE_MODE:
			return  # it just bobs by: shoot it!
		var what := "A SUPPLY BARREL!\nGunner: shoot it for free cannonballs!" if kind == "supply" else "A TREASURE CHEST!\nGunner: shoot it for gold!"
		_show_center(what, 2.2)
		parrot_say("SQUAWK! Shoot the barrel!" if kind == "supply" else "SQUAWK! TREASURE!")


func on_target_hit(tg, pos: Vector3) -> void:
	if tg.gone:
		return
	tg.gone = true
	var kind: String = tg.kind
	explosion(pos + Vector3.UP, Color(1.0, 0.85, 0.3), 1.0)
	confetti(pos + Vector3.UP * 2.0)
	sound("bullseye")
	match kind:
		"practice":
			practice_hits += 1
			gold += 5
			var left := PRACTICE_HITS - practice_hits
			var msg := "BULLSEYE!" if left != 0 else "BULLSEYE!  PERFECT!"
			popup(pos + Vector3.UP * 3.0, msg, Color(1.0, 0.9, 0.3))
			if left > 0:
				parrot_say(["SQUAWK! Nice shot!", "Again! Again!", "Ooh, shiny shot!"][practice_hits % 3])
			elif net.mode == "host" and not net.connected and not SIMPLE_MODE:
				_show_center("GREAT SHOOTING, GUNNER!\nKeep practising while the deckhands on the TV join…", 4.0)
			print("Practice target hit (%d)" % practice_hits)
		"supply":
			for c in cannons:
				c.ammo = mini(c.MAX_AMMO, c.ammo + 1)
			popup(pos + Vector3.UP * 3.0, "FREE AMMO FOR EVERY CANNON!", Color(0.5, 1.0, 0.55))
			sound("load", 0.0, 1.3)
			parrot_say("SQUAWK! Cannonballs!")
			print("Supply barrel hit")
		_:
			gold += 40
			popup(pos + Vector3.UP * 3.0, "TREASURE!" if SIMPLE_MODE else "TREASURE!  +40 GOLD", Color(1.0, 0.85, 0.2))
			sound("coin", 0.0, 1.0)
			sound("coin", -2.0, 1.3)
			print("Treasure chest hit, gold %d" % gold)
	tg.queue_free()


func _end_practice() -> void:
	phase = "break"
	in_break = true
	break_timer = 7.0
	for tg in get_tree().get_nodes_in_group("targets"):
		splash(tg.global_position, 1.2)
		tg.queue_free()
	sound("bell", -2.0)
	if SIMPLE_MODE:
		_show_center("PIRATES!", 2.5)
	else:
		_show_center("GREAT SHOOTING!\nPirates are coming - deckhands, keep the cannons loaded!", 4.0)
	parrot_say("SQUAWK! PIRATES AHOY!")
	print("Practice over (%d hits)" % practice_hits)


## Supply barrels and treasure chests float by during the waves; dolphins visit now and then.
func _random_events(delta: float) -> void:
	if phase != "wave" or wave < 2:
		return
	event_t -= delta
	if event_t > 0.0:
		return
	event_t = randf_range(30.0, 45.0)
	event_flip = not event_flip
	if SIMPLE_MODE:
		_spawn_target("chest")  # a treasure chest bobbing by: just another thing to shoot (no free-ammo rule)
		return
	_spawn_target("supply" if event_flip else "chest")


func _plan_wave(w: int) -> Array[String]:
	var q: Array[String] = []
	if SIMPLE_MODE:
		return _plan_simple_wave(w)
	match w:
		1:
			q.assign(["raider", "raider"])
		2:
			q.assign(["raider", "raider", "raider"])
		3:
			q.assign(["raider", "fireship", "galleon", "fireship", "raider"])
		4:
			q.assign(["raider", "tentacle", "treasure", "galleon", "raider", "tentacle"])
		5:
			q.assign(["raider", "fireship", "galleon", "tentacle", "raider", "fireship", "galleon"])
		BOSS_WAVE:
			q.assign(["kraken", "wait", "raider"])
		_:
			var n := mini(3 + (w - BOSS_WAVE), 9)
			for i in n:
				q.append(["raider", "galleon", "raider", "fireship"][i % 4])
			for i in 1 + (w - BOSS_WAVE) / 2:
				q.insert(mini(q.size(), 2 + i * 2), "tentacle")
			if w % 2 == 0:
				q.insert(2, "treasure")
	# A bigger crew (more than two deckhands) faces a few more ships and tentacles.
	var extra := crew_extra()
	for i in extra / 2:
		q.append("raider")
	if extra >= 3 and w >= 3:
		q.append("tentacle")
	return q


## Simple mode: one new thing per wave. 1-2 slow ships (their shots don't hurt), 3 leaks, 4 boarders,
## 5 the sea monster's tentacles, 6 the Kraken; bonus seas bring back the bomb boats.
func _plan_simple_wave(w: int) -> Array[String]:
	var q: Array[String] = []
	match w:
		1:
			q.assign(["raider", "raider"])
		2:
			q.assign(["raider", "raider", "raider"])
		3:
			q.assign(["raider", "raider", "raider"])
		4:
			q.assign(["raider", "raider", "galleon", "raider"])
		5:
			q.assign(["raider", "tentacle", "raider", "tentacle", "galleon"])
		BOSS_WAVE:
			q.assign(["kraken", "wait", "raider"])
		_:
			var n := mini(3 + (w - BOSS_WAVE), 8)
			for i in n:
				q.append(["raider", "galleon", "raider", "fireship"][i % 4] if w > BOSS_WAVE + 1 else "raider")
			for i in 1 + (w - BOSS_WAVE) / 3:
				q.insert(mini(q.size(), 2 + i * 2), "tentacle")
	var extra := crew_extra()
	for i in extra / 2:
		q.append("raider")
	return q


## Simple mode: leaks only from wave 3 and few at a time (wave 3: one, then two, later three).
func leak_cap() -> int:
	if not SIMPLE_MODE:
		return MAX_LEAKS
	if wave < 3:
		return 0
	return 1 if wave == 3 else (2 if wave <= BOSS_WAVE else 3)


## Simple mode: boarders only from wave 4, one at a time (two from the Kraken on).
func boarder_cap() -> int:
	if not SIMPLE_MODE:
		return 99
	if wave < 4:
		return 0
	return (1 if wave < BOSS_WAVE else 2) + crew_extra() / 3


## Bouncing arrows: each local player sees their own, over the next thing to do.
func _update_guides() -> void:
	for p in players:
		var g: Node3D = p.get_meta("guide") if p.has_meta("guide") else null
		var want = null
		var k := 1.0
		if p.active and not p.ghost and not p.remote:
			if p.gunner:
				want = coach_point
				k = coach_scale
			else:
				want = deckhand_goal(p)
				if want != null:
					var w: Vector3 = want
					var flat := Vector2(w.x - p.global_position.x, w.z - p.global_position.z).length()
					if flat < 1.6 and not p.carrying:
						want = null  # you're there: the prompt says what to do
		if want == null:
			if g:
				g.hide_arrow()
			continue
		if g == null:
			g = GuideScript.new()
			g.color = p.color.lightened(0.25)
			g.layer = p.viewmodel_layer()
			add_child(g)
			p.set_meta("guide", g)
		g.point(want, k)


func _start_wave() -> void:
	wave += 1
	in_break = false
	phase = "wave"
	spawn_queue = _plan_wave(wave)
	spawn_timer = 0.5
	ships_to_spawn = spawn_queue.size()
	print("Wave %d started (%d deckhands, plan %s)" % [wave, deckhands().size(), spawn_queue])
	sound("wave")
	sound("bell", -4.0)
	if SIMPLE_MODE:
		var head_s := "WAVE %d!" % wave
		match wave:
			4:
				head_s = "BOARDERS!"
			5:
				head_s = "SEA MONSTER!"
			BOSS_WAVE:
				head_s = "THE KRAKEN!"
				golden_balls += 1  # one golden cannonball for the Kraken (the deckhands' arrow shows it)
		_show_center(head_s, 2.0)
		parrot_say("")
		return
	var title: String = WAVE_NAMES[wave] if wave < WAVE_NAMES.size() else "BONUS SEAS"
	var sub := "Pirates ahoy!"
	match wave:
		1:
			sub = "Two pirate ships. Gunner: put the gold ring on them and FIRE!"
		2:
			sub = "Raiders send BOARDERS - deckhands, muskets ready!"
		3:
			sub = "Little boats with BOMBS! Sink them before they ram us!\n(Deckhands: muskets work on them too)"
		4:
			sub = "The sea monster wakes… and a TREASURE SHIP sails by!"
		5:
			sub = "A storm! Hold on tight, me hearties!"
		BOSS_WAVE:
			sub = "Deckhands: shoot its TENTACLES. Gunner: hit its EYES when they open!"
			golden_balls += 1
			parrot_say("SQUAWK! A golden cannonball for the Kraken!")
		_:
			sub = "Everything the sea has got!"
	var head := "WAVE %d of %d" % [wave, BOSS_WAVE] if wave <= BOSS_WAVE else "BONUS WAVE %d" % (wave - BOSS_WAVE)
	_show_center("%s\n%s\n%s" % [head, title, sub], 3.5)
	if wave != BOSS_WAVE:
		parrot_say(["SQUAWK! Here they come!", "Battle stations!", "Ready the cannons!"][wave % 3])


func _end_wave() -> void:
	in_break = true
	phase = "break"
	break_timer = 7.0
	var bonus := 25 * wave
	gold += bonus
	print("Wave %d cleared, gold %d" % [wave, gold])
	sound("clear")
	sound("cheer", -4.0)
	sound("coin", -2.0, 1.0)
	if SIMPLE_MODE:
		_show_center("HOORAY!", 2.0)
		parrot_say("")
		confetti(Vector3(0, 6.0, 2.0))
		var ds := -1.0 if randf() < 0.5 else 1.0
		var dz2 := randf_range(4.0, 12.0)
		net.event("dolphins", [ds, dz2])
		dolphins(ds, dz2)
		return
	var next := wave + 1
	var preview := ""
	if next <= BOSS_WAVE:
		preview = "\nNext: %s" % WAVE_NAMES[next]
	_show_center("WAVE %d CLEARED!\n+%d GOLD bonus%s" % [wave, bonus, preview], 3.5)
	parrot_say("SQUAWK! Well done, crew!")
	confetti(Vector3(0, 6.0, 2.0))
	var dside := -1.0 if randf() < 0.5 else 1.0
	var dz := randf_range(4.0, 12.0)
	net.event("dolphins", [dside, dz])
	dolphins(dside, dz)


func _spawn_next() -> void:
	var kind: String = spawn_queue[0]
	var normal := 0
	for sh in get_tree().get_nodes_in_group("ships"):
		if not sh.is_fireship():
			normal += 1
	var cap := 2 + wave / 2 + (1 if crew_extra() >= 2 else 0)
	match kind:
		"wait":
			spawn_queue.pop_front()
			spawn_timer = 22.0
			return
		"tentacle":
			if get_tree().get_nodes_in_group("tentacles").size() >= 1 + wave / 4 + crew_extra() / 3 + (2 if wave == BOSS_WAVE else 0):
				return
			_spawn_tentacle(-1.0 if randf() < 0.5 else 1.0, 4.0 + floorf(wave / 3.0))
			spawn_timer = 5.0
		"kraken":
			_spawn_kraken()
			spawn_timer = 6.0
		"fireship":
			_spawn_ship(kind)
			spawn_timer = 4.0
		_:
			if normal >= cap:
				return
			_spawn_ship(kind)
			spawn_timer = 10.0 if wave == 1 else maxf(4.0, 9.0 - wave * 0.6)
	spawn_queue.pop_front()


func _spawn_ship(kind: String) -> void:
	var s := ShipScript.new()
	if kind == "raider" and wave >= (4 if SIMPLE_MODE else 2) and randf() < 0.15 + wave * 0.03:
		kind = "galleon"
	if SIMPLE_MODE and kind == "treasure":
		kind = "galleon"  # no treasure ship / golden-ball rules
	s.setup(kind, wave, self)
	s.calm = wave <= (2 if SIMPLE_MODE else 1)
	s.net_id = next_net_id()
	# Come in from port or starboard (where the cannons point), a little fore or aft.
	var side := -1.0 if randf() < 0.5 else 1.0
	var a := randf_range(-0.9, 0.9)
	var dir := Vector3(side * cos(a), 0.0, sin(a))
	var dist := 95.0 if kind != "fireship" else 70.0
	s.position = dir * dist + Vector3(0, sea_level, 0)
	s.heading = atan2(dir.x, dir.z)
	add_child(s)
	match kind:
		"fireship":
			if not announced.has("fireship"):
				announced["fireship"] = true
				_show_center("BOMB BOAT!" if SIMPLE_MODE else "FIRE SHIP!\nSink the bomb boat before it rams us!", 2.5)
			parrot_say("SQUAWK! BOMB BOAT!")
			sound("fuse", -6.0)
		"treasure":
			_show_center("A TREASURE SHIP!\nSink it before it gets away - it carries a GOLDEN cannonball!", 3.0)
			parrot_say("SQUAWK! GOLD! GOLD!")
			sound("golden", -2.0)


func _spawn_tentacle(side: float, hp: float, z: float = INF) -> Node3D:
	var t := TentacleScript.new()
	t.main = self
	t.net_id = next_net_id()
	t.side = side
	t.max_hp = hp
	t.hp = t.max_hp
	t.position = Vector3(t.side * randf_range(6.8, 8.0), sea_level, randf_range(-7.0, 7.0) if z == INF else z)
	add_child(t)
	sound("tentacle", 0.0, 0.8)
	if not announced.has("tentacle") and not SIMPLE_MODE:
		announced["tentacle"] = true
		_show_center("THE SEA MONSTER!\nShoot the tentacle before it smashes the deck!", 2.0)
	splash(t.position, 2.0)
	return t


# --- The Kraken (final wave) ----------------------------------------------------------------

func _spawn_kraken() -> void:
	var k := KrakenScript.new()
	k.main = self
	k.net_id = next_net_id()
	k.side = -1.0 if randf() < 0.5 else 1.0
	k.max_hp = 9.0 + 2.0 * crew_extra()
	k.hp = k.max_hp
	k.position = Vector3(k.side * k.DIST, sea_level, randf_range(-3.0, 4.0))
	add_child(k)
	sound("roar", 0.0, 0.8)
	add_shake(Vector3.ZERO, 0.5)
	print("The Kraken rises")


func kraken_summon(k) -> void:
	k.tentacles.clear()
	var n := 2 + (1 if crew_extra() >= 2 else 0)
	var zs := [-6.0, 5.0, -0.5]
	for i in n:
		k.tentacles.append(_spawn_tentacle(k.side, 3.0 + floorf(crew_extra() / 2.0), zs[i] + randf_range(-1.0, 1.0)))
	sound("roar", -2.0, 1.0)
	if not SIMPLE_MODE:
		_show_center("THE KRAKEN!\nDeckhands: shoot its TENTACLES so it opens its eyes!", 2.5)
	parrot_say("SQUAWK! Shoot the wiggly bits!")


func kraken_roar(k) -> void:
	sound("roar", -3.0, randf_range(0.8, 1.0))
	add_shake(Vector3.ZERO, 0.35)
	splash(Vector3(k.position.x * 0.6, sea_level, k.position.z), 2.0)


func kraken_eyes_open(_k) -> void:
	sound("roar", 0.0, 1.3)
	sound("bullseye", -2.0, 0.8)
	_show_center("NOW! FIRE!" if SIMPLE_MODE else "ITS EYES ARE OPEN!\nGUNNER: FIRE AT THE KRAKEN NOW!", 2.5)
	parrot_say("SQUAWK! NOW! NOW!")


func kraken_dive(k) -> void:
	splash(Vector3(k.position.x, sea_level, k.position.z), 3.0)
	sound("splash", 0.0, 0.5)
	if k.hp > 0.0 and not SIMPLE_MODE:
		_show_center("It dived! Watch the OTHER side…", 2.0)


func on_kraken_defeated(k) -> void:
	phase = "victory"
	victory_t = 16.0
	gold += 500
	stats[0].sinks += 1
	for tn in get_tree().get_nodes_in_group("tentacles"):
		tn.hit(99.0)
	for sh in get_tree().get_nodes_in_group("ships"):
		if not sh.sinking:
			sh.hit(99.0)  # the rest of the pirates go down with their monster
	for b in get_tree().get_nodes_in_group("boarders"):
		b.hit(99.0)
	var pos: Vector3 = k.head_center()
	explosion(pos, Color(0.9, 0.5, 1.0), 3.0)
	splash(Vector3(pos.x, sea_level, pos.z), 3.0)
	sound("kaboom", 0.0, 0.7)
	sound("cheer", 0.0)
	sound("clear", -2.0, 0.8)
	for i in 6:
		get_tree().create_timer(0.4 + i * 0.7).timeout.connect(func() -> void:
			fireworks(Vector3(randf_range(-14.0, 14.0), randf_range(14.0, 22.0), randf_range(-16.0, 10.0))))
	parrot_say("SQUAWK! WE BEAT THE KRAKEN!")
	print("VICTORY: the Kraken is beaten, gold %d" % gold)
	if SIMPLE_MODE:
		_show_center("VICTORY!", 5.0)
		return
	_show_center("VICTORY!\nYou beat the KRAKEN!  +500 GOLD", 6.0)
	_show_stats("THE COVE IS SAFE!", 16.0)


func spawn_boarder(ship) -> void:
	var b := BoarderScript.new()
	b.main = self
	b.net_id = next_net_id()
	var sp: Vector3 = ship.global_position
	var side := signf(sp.x) if absf(sp.x) > 1.0 else 1.0
	var z := clampf(sp.z * 0.3, -8.5, 8.0)
	b.swing_from = sp + Vector3.UP * 4.0
	b.swing_to = Vector3(side * 3.2, 0.0, z)
	add_child(b)
	grapple_fx(sp + Vector3.UP * 6.0, Vector3(side * World.HULL_HALF_W, 1.0, z))
	if not has_meta("boarders_announced") and not SIMPLE_MODE:
		set_meta("boarders_announced", true)
		_show_center("BOARDERS!\nDeckhands: shoot them with your muskets!", 2.0)


func boarder_count() -> int:
	return get_tree().get_nodes_in_group("boarders").size()


## Deckhands: auto-load cannons, patch leaks.
func _update_crew(delta: float) -> void:
	var patched_now := {}
	for p in deckhands():
		if p.carrying:
			var c = nearest_cannon(p.global_position, 1.9)
			if c != null and c.ammo < c.MAX_AMMO:
				_load(p, c)
		p.patching = false
		if p.use_held:
			var lk = nearest_leak(p.global_position, LeakScript.RANGE)
			if lk != null:
				lk.progress += delta / LeakScript.PATCH_TIME
				p.patching = true
				patched_now[lk] = true
				var who: Dictionary = lk.get_meta("patchers", {})
				who[p.index] = true
				lk.set_meta("patchers", who)
	if not patched_now.is_empty():
		hammer_t -= delta
		if hammer_t <= 0.0:
			hammer_t = 0.28
			sound("hammer", -4.0, randf_range(0.9, 1.2))
	for lk in get_tree().get_nodes_in_group("leaks"):
		if lk.progress >= 1.0:
			var pos: Vector3 = lk.global_position
			var age: float = lk.t
			var who: Dictionary = lk.get_meta("patchers", {})
			for i in who:
				var idx: int = i
				stats[idx].patches += 1
			lk.queue_free()
			if SIMPLE_MODE:
				gold += 5
				popup(pos + Vector3.UP * 1.2, "FIXED!", Color(0.5, 1.0, 0.5))
			elif age < 6.0:
				gold += 15
				popup(pos + Vector3.UP * 1.2, "SPEEDY PATCH! +15", Color(0.5, 1.0, 0.7))
				sound("cheer", -8.0, 1.3)
			else:
				gold += 5
				popup(pos + Vector3.UP * 1.2, "PATCHED! +5", Color(0.5, 1.0, 0.5))
			sound("clear", -6.0, 1.4)
			_particles(pos, Color(0.75, 0.55, 0.3), 10, 0.1, 4.0, 12.0, 0.6)
		elif not patched_now.has(lk):
			lk.progress = maxf(0.0, lk.progress - delta * 0.12)


func _load(p, c) -> void:
	c.ammo += 1
	p.carrying = false
	stats[p.index].loads += 1
	sound("load", -2.0)
	if p.golden:
		p.golden = false
		c.golden += 1
		sound("golden", -2.0)
		popup(c.global_position + Vector3.UP * 1.6, "GOLDEN!" if SIMPLE_MODE else "GOLDEN BALL LOADED!", Color(1.0, 0.85, 0.2))
		parrot_say("SQUAWK! Fire the golden one!")
	else:
		popup(c.global_position + Vector3.UP * 1.6, "LOADED!", Color(0.6, 1.0, 0.6))


func _update_water(delta: float) -> void:
	var leaks := get_tree().get_nodes_in_group("leaks").size()
	var rate := LEAK_RATE if deckhands().size() >= 2 else LEAK_RATE * 0.7
	if SIMPLE_MODE:
		rate *= 0.7  # gentler: one leak at a time to start with
	rate *= 1.0 + 0.08 * crew_extra()  # more hands patch faster, so holes let in a little more
	if leaks > 0:
		water += leaks * rate * delta
	else:
		water -= (4.0 if in_break else 1.2) * delta
	water = clampf(water, 0.0, 100.0)
	if water >= 75.0 and not has_meta("water_warned"):
		set_meta("water_warned", true)
		if not SIMPLE_MODE:
			_show_center("THE HOLD IS NEARLY FULL!\nPatch those leaks!", 2.0)
		parrot_say("SQUAWK! We're sinking!")
	elif water < 50.0 and has_meta("water_warned"):
		remove_meta("water_warned")
	if water >= 100.0:
		_on_game_over()


func nearest_cannon(pos: Vector3, max_d: float):
	var best = null
	var best_d := max_d
	for c in cannons:
		var d := Vector2(pos.x - c.global_position.x, pos.z - c.global_position.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best


func nearest_leak(pos: Vector3, max_d: float):
	var best = null
	var best_d := max_d
	for lk in get_tree().get_nodes_in_group("leaks"):
		var d: float = Vector2(pos.x - lk.global_position.x, pos.z - lk.global_position.z).length()
		if d < best_d:
			best_d = d
			best = lk
	return best


## Host: a deckhand pressed or released "use".
func set_use(p, held: bool) -> void:
	p.use_held = held
	if not held:
		return
	if nearest_leak(p.global_position, LeakScript.RANGE) != null:
		return  # holding: patching
	if not p.carrying and p.global_position.distance_to(World.HOLD_POS) < 2.6:
		p.carrying = true
		if golden_balls > 0:
			golden_balls -= 1
			p.golden = true
			sound("golden", -2.0)
			popup(World.HOLD_POS + Vector3.UP * 2.6, "GOLDEN!" if SIMPLE_MODE else "GOLDEN CANNONBALL!", Color(1.0, 0.85, 0.2))
		else:
			sound("pickup", -4.0, 0.8)
		if not has_meta("first_ball"):
			set_meta("first_ball", true)
			print("Deckhand picked up a cannonball")
		return
	if p.carrying:
		var c = nearest_cannon(p.global_position, 2.8)
		if c != null and c.ammo < c.MAX_AMMO:
			_load(p, c)
		elif c != null:
			popup(c.global_position + Vector3.UP * 1.6, "FULL!", Color(1.0, 0.9, 0.5))
		else:
			p.carrying = false  # drop it (it rolls away)
			if p.golden:
				p.golden = false
				golden_balls += 1  # the golden one rolls back to the pile
			sound("dry", -6.0, 0.5)


func create_leak(pos: Vector3) -> void:
	var leaks := get_tree().get_nodes_in_group("leaks")
	if leak_cap() <= 0:
		return  # simple mode, waves 1-2: the shots just rock the boat
	if leaks.size() >= leak_cap():
		water = minf(100.0, water + (2.0 if SIMPLE_MODE else 4.0))
		return
	var p := World.constrain(pos, 0.5, cannon_obstacles())
	for lk in leaks:
		if lk.global_position.distance_to(p) < 1.0:
			water = minf(100.0, water + 3.0)  # the same hole got bigger
			return
	var leak := LeakScript.new()
	leak.main = self
	leak.net_id = next_net_id()
	leak.position = p
	add_child(leak)
	sound("creak", -2.0, randf_range(0.8, 1.1))
	if not has_meta("leak_announced") and not SIMPLE_MODE:
		set_meta("leak_announced", true)
		_show_center("WE'VE GOT A LEAK!\nDeckhands: hold USE next to it to patch it!", 2.5)
		parrot_say("SQUAWK! LEAK! LEAK!")


# --- Gunner -------------------------------------------------------------------

func gunner_fire(p) -> bool:
	if game_over or p.station < 0:
		return false
	var c = cannons[p.station]
	var fired: bool = c.fire()
	if fired:
		stats[0].shots += 1
		gunner_fired = true
	return fired


func ball_hit_test(pos: Vector3):
	for s in get_tree().get_nodes_in_group("ships"):
		if s.hit_test(pos):
			return s
	for k in get_tree().get_nodes_in_group("krakens"):
		if k.rise > 0.6 and k.state != "dying" and k.head_center().distance_to(pos) < k.HEAD_R + 1.4:
			return k
	for t in get_tree().get_nodes_in_group("tentacles"):
		if t.alive() and t.distance_to_point(pos) < 1.1:
			return t
	for tg in get_tree().get_nodes_in_group("targets"):
		if tg.hit_test(pos):
			return tg
	return null


func on_ball_hit(target, pos: Vector3, mega: bool = false) -> void:
	if target.is_in_group("targets"):
		on_target_hit(target, pos)
		_streak_hit(pos)
		return
	explosion(pos, Color(1.0, 0.6, 0.2), 1.2)
	sound("big_kill", -4.0, 1.3)
	add_shake(pos, 0.15)
	if mega:
		_mega_blast(pos, target)
	if target.is_in_group("krakens"):
		var r: String = target.hit(3.0 if mega else 1.0, mega)
		match r:
			"clang":
				sound("clang", 0.0, randf_range(0.8, 1.0))
				popup(pos + Vector3.UP * 2.0, "CLANG!" if SIMPLE_MODE else "CLANG! Its eyes are shut!", Color(0.8, 0.7, 1.0))
				return
			"dead":
				on_kraken_defeated(target)
			_:
				popup(pos + Vector3.UP * 2.0, ["OUCH!", "BULLSEYE!", "RIGHT IN THE EYE!"][randi() % 3], Color(1.0, 0.85, 0.3))
				sound("roar", -4.0, 1.5)
	elif target.is_in_group("tentacles"):
		target.hit(3.0)
		popup(pos + Vector3.UP, "SPLAT!", Color(0.9, 0.6, 1.0))
	else:
		target.hit(3.0 if mega else 1.0)
		if not target.sinking and is_instance_valid(target):
			popup(pos + Vector3.UP * 2.0, "HIT!", Color(1.0, 0.8, 0.3))
	stats[0].hits += 1
	_streak_hit(pos)


## A golden cannonball explodes in a huge golden blast that hurts everything nearby.
func _mega_blast(pos: Vector3, direct) -> void:
	explosion(pos, Color(1.0, 0.85, 0.2), 3.0)
	confetti(pos + Vector3.UP * 2.0)
	sound("kaboom", 0.0, 1.1)
	popup(pos + Vector3.UP * 4.0, "MEGA SHOT!", Color(1.0, 0.9, 0.2))
	add_shake(pos, 0.4)
	for s in get_tree().get_nodes_in_group("ships"):
		if s != direct and not s.sinking and s.global_position.distance_to(pos) < 12.0:
			s.hit(2.0)
	for t in get_tree().get_nodes_in_group("tentacles"):
		if t != direct and t.alive() and t.distance_to_point(pos) < 9.0:
			t.hit(3.0)


func _streak_hit(pos: Vector3) -> void:
	streak += 1
	stats[0].best_streak = maxi(int(stats[0].best_streak), streak)
	if SIMPLE_MODE:
		return  # no streak bonuses
	if streak in [3, 5, 8, 12] or (streak > 12 and streak % 5 == 0):
		var bonus := streak * 5
		gold += bonus
		popup(pos + Vector3.UP * 4.5, "HOT STREAK x%d!  +%d" % [streak, bonus], Color(1.0, 0.55, 0.2))
		sound("cheer", -4.0, 1.0 + streak * 0.02)
		parrot_say("SQUAWK! %d in a row!" % streak)


## Host: one of our cannonballs splashed into the sea (a miss). During practice the parrot says how
## to correct the aim.
func on_ball_splash(pos: Vector3) -> void:
	streak = 0
	var c = cannons[players[0].station] if not players.is_empty() else null
	if c == null:
		return
	var best = null
	var best_d := 9.0
	for tg in get_tree().get_nodes_in_group("targets"):
		var d: float = Vector2(tg.global_position.x - pos.x, tg.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = tg
	if best == null:
		return
	var from := Vector3(c.global_position.x, 0.0, c.global_position.z)
	var to_t: Vector3 = Vector3(best.global_position.x, 0.0, best.global_position.z) - from
	var to_s := Vector3(pos.x, 0.0, pos.z) - from
	var along := to_s.dot(to_t.normalized()) - to_t.length()
	var across := to_t.normalized().cross(to_s).y
	var vr: bool = players[0].vr or players[0].fake_vr
	var tip := "SO CLOSE!"
	if SIMPLE_MODE:
		# One or two words where it splashed; the gold ring on the sea shows the rest.
		if absf(along) > absf(across):
			tip = "TOO SHORT!" if along < 0.0 else "TOO FAR!"
		elif absf(across) > 2.5:
			tip = "MISSED!"
		popup(pos + Vector3.UP * 2.5, tip, Color(1.0, 1.0, 0.7))
		return
	if absf(along) > absf(across):
		if along < 0.0:
			tip = "TOO SHORT!\n" + ("Push the handle DOWN a little" if vr else "Aim a bit HIGHER")
		else:
			tip = "TOO FAR!\n" + ("Lift the handle UP a little" if vr else "Aim a bit LOWER")
	else:
		tip = "A BIT TO THE SIDE!\nSwing the barrel %s" % ("LEFT" if across < 0.0 else "RIGHT")
	popup(pos + Vector3.UP * 2.5, tip, Color(1.0, 1.0, 0.7))
	if phase == "practice":
		coach_tip = tip.replace("\n", " ")
		coach_tip_t = 4.0


func on_ship_sunk(s) -> void:
	gold += s.gold
	stats[0].sinks += 1
	var pos: Vector3 = s.global_position + Vector3.UP * 3.0
	popup(pos + Vector3.UP * 2.0, "SUNK!" if SIMPLE_MODE else "SUNK!  +%d GOLD" % s.gold, Color(1.0, 0.85, 0.2))
	explosion(pos, Color(1.0, 0.75, 0.3), 2.2)
	sound("big_kill", 0.0, 0.8)
	sound("coin", -2.0)
	splash(s.global_position, 2.5)
	coins_fx(pos)
	if t_world - last_sink_t < 5.0 and not SIMPLE_MODE:
		gold += 40
		popup(pos + Vector3.UP * 4.0, "DOUBLE SINK!  +40", Color(1.0, 0.55, 0.9))
		sound("cheer", -2.0)
	last_sink_t = t_world
	if s.kind == "treasure":
		golden_balls += 1
		sound("golden", 0.0)
		_show_center("TREASURE SHIP SUNK!\nA GOLDEN CANNONBALL is on the pile - deckhands, load it!", 3.0)
		parrot_say("SQUAWK! Golden ball! Golden ball!")
	else:
		parrot_say(["SQUAWK! Sunk 'em!", "Blow me down!", "Glug glug glug!", "Hooray!"][randi() % 4])
	print("Sunk a %s, gold %d" % [s.kind, gold])


## A fire ship blows up: shot (KABOOM, taking nearby pirates with it) or rammed into our hull.
func fireship_boom(s, reached: bool) -> void:
	if s.sinking:
		return
	s.sinking = true
	var pos: Vector3 = s.global_position + Vector3.UP * 1.0
	explosion(pos, Color(1.0, 0.45, 0.1), 2.6)
	splash(Vector3(pos.x, sea_level, pos.z), 2.0)
	sound("kaboom", 0.0, randf_range(0.9, 1.1))
	add_shake(pos, 0.9 if reached else 0.35)
	if reached:
		var side := signf(pos.x)
		var z := clampf(pos.z, -9.0, 8.0)
		create_leak(Vector3(side * 2.6, 0.0, z - 1.0))
		create_leak(Vector3(side * 2.2, 0.0, z + 1.2))
		water = minf(100.0, water + 5.0)
		popup(Vector3(side * 3.0, 2.5, z), "BOOM!" if SIMPLE_MODE else "BOOM! IT RAMMED US!", Color(1.0, 0.4, 0.3))
		parrot_say("SQUAWK! OUCH!")
	else:
		gold += s.gold
		popup(pos + Vector3.UP * 2.5, "KABOOM!" if SIMPLE_MODE else "KABOOM!  +%d" % s.gold, Color(1.0, 0.6, 0.2))
		var chain := 0
		for o in get_tree().get_nodes_in_group("ships"):
			if o != s and not o.sinking and o.global_position.distance_to(pos) < 13.0:
				o.hit(2.0)
				chain += 1
		for t in get_tree().get_nodes_in_group("tentacles"):
			if t.alive() and t.distance_to_point(pos) < 9.0:
				t.hit(2.0)
				chain += 1
		if chain > 0 and not SIMPLE_MODE:
			gold += 30
			popup(pos + Vector3.UP * 4.5, "CHAIN BLAST! +30", Color(1.0, 0.5, 0.9))
	s.queue_free()
	print("Fire ship %s" % ("rammed us" if reached else "blown up"))


func on_treasure_fleeing(_s) -> void:
	if SIMPLE_MODE:
		return
	_show_center("The treasure ship is getting away!\nQuick, gunner!", 2.0)
	parrot_say("SQUAWK! Don't let it escape!")


func on_treasure_escaped(_s) -> void:
	if not SIMPLE_MODE:
		popup(Vector3(0, 6.0, -4.0), "The treasure ship got away…", Color(0.9, 0.9, 0.9))
	sound("dry", -2.0, 0.6)


func enemy_ball_hit_deck(pos: Vector3) -> void:
	explosion(pos + Vector3.UP * 0.3, Color(1.0, 0.5, 0.2), 0.9)
	add_shake(pos, 0.5)
	sound("big_kill", -3.0, 1.1)
	create_leak(pos)


func on_tentacle_slam(_t, pos: Vector3) -> void:
	add_shake(pos, 0.6)
	sound("big_kill", -2.0, 0.6)
	_particles(pos + Vector3.UP * 0.3, Color(0.6, 0.85, 1.0), 16, 0.12, 6.0, 14.0, 0.8, 60.0)
	if net:
		net.event("slam", [pos])
	create_leak(pos)


func on_tentacle_killed(t) -> void:
	gold += 40
	popup(t.segs[t.SEGMENTS - 1].global_position + Vector3.UP, "BYE BYE!" if SIMPLE_MODE else "BYE BYE MONSTER!  +40", Color(0.9, 0.6, 1.0))
	sound("big_kill", 0.0, 0.7)
	sound("coin", -2.0, 1.2)
	splash(Vector3(t.position.x, sea_level, t.position.z), 2.5)
	print("Tentacle defeated, gold %d" % gold)


# --- Deckhand muskets ------------------------------------------------------------

## Nudges a musket shot towards a boarder, tentacle or bomb boat that's roughly in front.
func musket_aim(from: Vector3, dir: Vector3) -> Vector3:
	var best := dir
	var best_dot := cos(deg_to_rad(7.0))
	var targets := []
	for b in get_tree().get_nodes_in_group("boarders"):
		if b.alive():
			targets.append(b.global_position + Vector3.UP * 1.0)
	for t in get_tree().get_nodes_in_group("tentacles"):
		if t.alive():
			for i in range(2, t.SEGMENTS, 2):
				targets.append(t.segs[i].global_position)
	for s in get_tree().get_nodes_in_group("ships"):
		if s.is_fireship() and not s.sinking:
			targets.append(s.global_position + Vector3.UP * 0.9)
	for p in targets:
		var to: Vector3 = p - from
		var dist := to.length()
		if dist < 0.5 or dist > 40.0:
			continue
		var d := dir.dot(to / dist)
		if d > best_dot:
			best_dot = d
			best = to / dist
	return best


## [target or null, end point]
func musket_trace(from: Vector3, dir: Vector3) -> Array:
	var best_t := 45.0
	var target = null
	for b in get_tree().get_nodes_in_group("boarders"):
		var t: float = b.ray_hit(from, dir, best_t)
		if t < best_t:
			best_t = t
			target = b
	for tn in get_tree().get_nodes_in_group("tentacles"):
		if not tn.alive():
			continue
		var t: float = tn.ray_hit(from, dir, best_t)
		if t < best_t:
			best_t = t
			target = tn
	for s in get_tree().get_nodes_in_group("ships"):
		var t: float = s.ray_hit(from, dir, best_t)
		if t < best_t:
			best_t = t
			target = s
	return [target, from + dir * best_t]


func musket_shot(p, from: Vector3, dir: Vector3) -> void:
	var tr := musket_trace(from, dir)
	var target = tr[0]
	musket_fx(p.index, from, tr[1])
	if target == null:
		return
	if p.hud:
		p.hud.hit_marker()
	else:
		net.event("hitmark", [p.index])
	if target.is_in_group("boarders"):
		sound("hit", -4.0)
		if target.hit(1.0):
			gold += 10
			stats[p.index].splashes += 1
			popup(target.global_position + Vector3.UP * 2.0, "SPLASH!" if SIMPLE_MODE else "SPLASH! +10", Color(0.6, 0.9, 1.0))
			sound("dash", -4.0, 0.6)
			get_tree().create_timer(0.9).timeout.connect(func() -> void:
				if is_instance_valid(target):
					splash(Vector3(target.global_position.x, sea_level, target.global_position.z), 1.2))
	elif target.is_in_group("ships"):
		stats[p.index].kegs += 1
		popup(target.global_position + Vector3.UP * 3.0, "NICE SHOT!" if SIMPLE_MODE else "NICE SHOT, P%d!" % (p.index + 1), Color(1.0, 0.8, 0.4))
		target.hit(1.0)
	else:
		stats[p.index].monster += 1
		target.hit(1.0)
		sound("hit", -2.0, 0.6)


func boarder_stole(b, c) -> void:
	c.ammo = maxi(0, c.ammo - 1)
	c.golden = mini(c.golden, c.ammo)
	popup(c.global_position + Vector3.UP * 1.8, "HEY!" if SIMPLE_MODE else "HEY! STOLEN!", Color(1.0, 0.45, 0.4))
	sound("pickup", -6.0, 0.6)
	_particles(b.global_position + Vector3.UP, Color(0.15, 0.15, 0.15), 4, 0.1, 2.0, 9.0, 0.5)


## Simple mode: the VR gunner threw a spare cannonball (or the barrel) at a boarder: SPLASH!
func prop_bonk(b, pos: Vector3) -> void:
	sound("hit", -2.0, 0.8)
	popup(pos + Vector3.UP * 1.5, "BONK!", Color(1.0, 0.85, 0.4))
	if b.hit(9.0):
		gold += 10
		stats[0].splashes += 1
		get_tree().create_timer(0.9).timeout.connect(func() -> void:
			if is_instance_valid(b):
				splash(Vector3(b.global_position.x, sea_level, b.global_position.z), 1.2))


func boarder_hacked(_b, pos: Vector3) -> void:
	sound("hammer", -2.0, 0.6)
	create_leak(pos)


# --- Coaching: what to do next -----------------------------------------------------

var coach_text := ""
var coach_point = null  # Vector3 or null: where the gunner's guide arrow points
var coach_scale := 1.0
var coach_tip := ""
var coach_tip_t := 0.0
var gunner_guide: Node3D


## The most important thing for the gunner to shoot: [position, name] or [].
func _gunner_focus() -> Array:
	var best: Array = []
	var best_d := INF
	for k in get_tree().get_nodes_in_group("krakens"):
		if k.state == "dying" or k.rise < 0.8:
			continue
		if k.vulnerable():
			return [k.head_center(), "THE KRAKEN'S EYES"]
	for s in get_tree().get_nodes_in_group("ships"):
		if s.sinking:
			continue
		var d: float = Vector2(s.global_position.x, s.global_position.z).length()
		if s.is_fireship():
			d *= 0.4  # bomb boats first
		if d < best_d:
			best_d = d
			best = [s.global_position + Vector3.UP * (1.5 if s.is_fireship() else 3.0), "BOMB BOAT" if s.is_fireship() else ("TREASURE SHIP" if s.kind == "treasure" else "PIRATE SHIP")]
	for t in get_tree().get_nodes_in_group("tentacles"):
		if t.alive() and t.rise >= 1.0:
			var d: float = Vector2(t.position.x, t.position.z).length() * 0.5
			if d < best_d:
				best_d = d
				best = [t.segs[4].global_position, "TENTACLE"]
	for tg in get_tree().get_nodes_in_group("targets"):
		var d: float = Vector2(tg.global_position.x, tg.global_position.z).length() * (0.3 if tg.kind == "practice" else 0.8)
		if d < best_d:
			best_d = d
			best = [tg.global_position + Vector3.UP * 1.5, {"practice": "TARGET", "supply": "SUPPLY BARREL", "chest": "TREASURE CHEST"}[tg.kind]]
	return best


## Host / local: works out the gunner's hint (text + an arrow), shown in VR or on the flat HUD.
func _update_coach(delta: float) -> void:
	if players.is_empty() or players[0].ghost:
		return
	coach_tip_t -= delta
	var p = players[0]
	var c = cannons[p.station]
	var vr: bool = p.vr or p.fake_vr
	var holding: bool = vr and p.grab_hand != null
	var focus := _gunner_focus()
	coach_text = ""
	coach_point = null
	coach_scale = 1.0
	if SIMPLE_MODE:
		_update_ghost_hand(p, c, vr, holding, focus)
	if game_over:
		return
	if SIMPLE_MODE:
		_simple_coach(p, c, vr, holding, focus)
		return
	var hop := "Press A (or flick the left stick)" if vr else "LB / RB (Q / E)"
	if vr and not holding and stats[0].shots < 3:
		coach_text = "Reach out to the glowing HANDLE behind the cannon\nand HOLD the trigger to grab it"
		coach_point = c.handle_world()
		coach_scale = 0.22
		if p.reach_miss_t > 0.0:
			coach_text = "A bit closer! Touch the glowing handle\nwith your hand, then HOLD the trigger"
		return
	if c.ammo <= 0:
		var other = null
		for oc in cannons:
			if oc.ammo > 0 and (other == null or absf(oc.index - c.index) < absf(other.index - c.index)):
				other = oc
		if other != null:
			coach_text = "This cannon is EMPTY!\n%s to hop to a loaded cannon" % hop
			coach_point = other.global_position + Vector3.UP * 1.2
			coach_scale = 0.5
		else:
			coach_text = "All the cannons are EMPTY!\nThe deckhands are bringing cannonballs…"
		return
	if not focus.is_empty():
		var fpos: Vector3 = focus[0]
		var fname: String = focus[1]
		var my_side := -1.0 if p.station < 2 else 1.0
		if signf(fpos.x) != my_side and absf(fpos.x) > 4.0:
			var there := "STARBOARD (right)" if my_side < 0.0 else "PORT (left)"
			coach_text = "The %s is on the %s side!\n%s to hop over there" % [fname, there, hop]
			coach_point = cannons[2 if my_side < 0.0 else 0].global_position + Vector3.UP * 1.2
			coach_scale = 0.5
			return
		var dist: float = fpos.distance_to(c.global_position)
		coach_point = fpos + Vector3.UP * 1.0
		coach_scale = clampf(dist * 0.06, 0.6, 5.0)
		if coach_tip_t > 0.0:
			coach_text = coach_tip
		elif vr and holding and stats[0].shots < 3:
			var ring: Vector3 = c.land_ring.global_position
			var near: bool = Vector2(ring.x - fpos.x, ring.z - fpos.z).length() < 5.0
			coach_text = "LET GO of the trigger to FIRE!" if near else "Swing the handle to move the gold RING onto the %s" % fname
		elif vr and not holding and stats[0].shots < 6:
			coach_text = "Grab the handle (hold the trigger), aim the ring at the %s, let go to fire" % fname
		elif not vr and stats[0].shots < 3:
			coach_text = "Aim the gold RING at the %s and FIRE!" % fname
		elif fname == "BOMB BOAT" and dist < 45.0:
			coach_text = "BOMB BOAT coming! Sink it!"
		elif fname == "THE KRAKEN'S EYES":
			coach_text = "FIRE AT THE KRAKEN'S EYES!"
		elif c.golden > 0:
			coach_text = "GOLDEN BALL loaded - make it count!"
		else:
			coach_point = null if stats[0].shots > 8 else coach_point
		return
	for k in get_tree().get_nodes_in_group("krakens"):
		if not k.vulnerable() and k.state != "dying":
			coach_text = "Its eyes are shut! Shoot the TENTACLES first"


## Simple mode: the arrow does the coaching. The only words: "LET GO!" while the gold ring sits on the
## target during the first shots (VR), and the flat gunner's buttons until they've fired a few times.
func _simple_coach(p, c, vr: bool, holding: bool, focus: Array) -> void:
	if vr and not holding and stats[0].shots < 3:
		coach_point = c.handle_world()
		coach_scale = 0.22
		return
	if c.ammo <= 0:
		var other = null
		for oc in cannons:
			if oc.ammo > 0 and (other == null or absf(oc.index - c.index) < absf(other.index - c.index)):
				other = oc
		if other != null:
			coach_point = other.global_position + Vector3.UP * 1.2
			coach_scale = 0.5
		return
	if focus.is_empty():
		return
	var fpos: Vector3 = focus[0]
	var my_side := -1.0 if p.station < 2 else 1.0
	if signf(fpos.x) != my_side and absf(fpos.x) > 4.0:
		coach_point = cannons[2 if my_side < 0.0 else 0].global_position + Vector3.UP * 1.2
		coach_scale = 0.5
		return
	var dist: float = fpos.distance_to(c.global_position)
	coach_point = fpos + Vector3.UP * 1.0
	coach_scale = clampf(dist * 0.06, 0.6, 5.0)
	if vr and holding and stats[0].shots < 3:
		var ring: Vector3 = c.land_ring.global_position
		if Vector2(ring.x - fpos.x, ring.z - fpos.z).length() < 5.0:
			coach_text = "LET GO!"
	elif stats[0].shots > 8 and phase != "practice" and focus[1] != "THE KRAKEN'S EYES":
		coach_point = null


## Simple mode, VR: a see-through ghost hand at the handle shows reach, squeeze, swing, let go until the
## gunner has fired a few shots (only when they're idle: never over a hand that's busy).
func _update_ghost_hand(p, c, vr: bool, holding: bool, focus: Array) -> void:
	if not vr:
		return
	if ghost_hand == null:
		ghost_hand = GhostHandScript.new()
		add_child(ghost_hand)
		p._set_layers(ghost_hand, p.viewmodel_layer())
	var want: bool = not game_over and not holding and stats[0].shots < 3 and c.ammo > 0 and phase == "practice"
	var aim := Vector3.ZERO
	if not focus.is_empty():
		var fp: Vector3 = focus[0]
		aim = fp
	ghost_hand.show_demo(want, c, aim, get_process_delta_time())


## Where a deckhand's guide arrow points: the most useful job for them right now, or null.
func deckhand_goal(p):
	if game_over or p.gunner:
		return null
	if p.carrying:
		var best = null
		for c in cannons:
			if c.ammo >= c.MAX_AMMO:
				continue
			if p.golden and c.manned:
				best = c
				break
			if best == null or c.ammo < best.ammo or (c.ammo == best.ammo and c.manned):
				best = c
		return best.global_position + Vector3.UP * 1.0 if best != null else null
	var leaks := get_tree().get_nodes_in_group("leaks")
	var boarders := get_tree().get_nodes_in_group("boarders").filter(func(b): return b.alive())
	var want_boarders: bool = not boarders.is_empty() and (leaks.is_empty() or p.index % 2 == 0)
	if not leaks.is_empty() and not want_boarders:
		var lk = nearest_leak(p.global_position, 99.0)
		if lk != null:
			return lk.global_position + Vector3.UP * 0.4
	if want_boarders:
		var best = null
		var bd := INF
		for b in boarders:
			var d: float = b.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = b
		return best.global_position + Vector3.UP * 2.3
	if SIMPLE_MODE:
		if golden_balls > 0:
			return World.HOLD_POS + Vector3.UP * 1.4
		for t in get_tree().get_nodes_in_group("tentacles"):
			if t.alive() and t.rise >= 1.0 and p.index % 2 == 0:
				return t.segs[4].global_position + Vector3.UP * 0.6  # musket the wiggly bits
	for c in cannons:
		if c.ammo < c.MAX_AMMO:
			return World.HOLD_POS + Vector3.UP * 1.4
	return null


## What this player should do next (shown at the bottom of their screen). A leading "!" makes it red.
func player_prompt(p) -> String:
	if game_over:
		return ""
	if SIMPLE_MODE:
		return _simple_prompt(p)
	if p.gunner:
		var c = cannons[p.station]
		var keys := "Sticks aim · RT / A fire · LB / RB switch cannon"
		if p.joy < 0:
			keys = "WASD / mouse aim · SPACE / click fire · Q / E switch cannon" if p.key_set == 0 else "ARROWS aim · ENTER fire · , / . switch cannon"
		if coach_text != "":
			return ("!" if c.ammo <= 0 else "") + coach_text + "\n" + keys
		return "%s cannon: %d balls\n%s" % [c.side_name(), c.ammo, keys]
	var use: String = p.use_name()
	var lk = nearest_leak(p.global_position, LeakScript.RANGE)
	if lk != null:
		if p.patching:
			return "Hammering… %d%%" % int(lk.progress * 100.0)
		return "!HOLD %s TO PATCH THE LEAK!" % use
	if p.hands_full_t > 0.0:
		return "!Hands full! Load the cannonball first (or press %s away from things to drop it)" % use
	if p.carrying:
		if p.golden:
			return "GOLDEN CANNONBALL! Load it into the GUNNER'S cannon (follow the arrow)"
		var empty := _emptiest_cannon()
		return "Carry the cannonball to a cannon!  (%s needs it most - follow the arrow)" % empty
	if p.global_position.distance_to(World.HOLD_POS) < 2.6:
		if golden_balls > 0:
			return "PRESS %s TO GRAB THE GOLDEN CANNONBALL!" % use
		return "PRESS %s TO GRAB A CANNONBALL" % use
	for s in get_tree().get_nodes_in_group("ships"):
		if s.is_fireship() and not s.sinking and Vector2(s.global_position.x, s.global_position.z).length() < 28.0:
			return "!BOMB BOAT! Shoot its powder keg with your musket (%s)!" % p.fire_name()
	if not get_tree().get_nodes_in_group("boarders").is_empty():
		return "!BOARDERS! Shoot them with your musket (%s)" % p.fire_name()
	for k in get_tree().get_nodes_in_group("krakens"):
		if not k.vulnerable() and k.state != "dying" and not get_tree().get_nodes_in_group("tentacles").is_empty():
			return "!Shoot the Kraken's TENTACLES with your musket (%s)!" % p.fire_name()
	if not get_tree().get_nodes_in_group("leaks").is_empty():
		return "!Find the LEAK and patch it! (follow the arrow)"
	if golden_balls > 0:
		return "A GOLDEN cannonball is on the pile! Fetch it for the gunner"
	for c in cannons:
		if c.ammo <= 1:
			return "Fetch cannonballs from the pile at the front of the ship (follow the arrow)"
	if phase == "practice":
		return "Target practice! Fetch a cannonball from the pile and load the gunner's cannon"
	return "Shoot boarders · fetch cannonballs · patch leaks"


## Simple mode: one short line at most (the arrow shows where to go). A leading "!" makes it red.
func _simple_prompt(p) -> String:
	if p.gunner:
		var c = cannons[p.station]
		if c.ammo <= 0:
			return "!EMPTY!  " + ("LB / RB" if p.joy >= 0 or p.key_set < 0 else ("Q / E" if p.key_set == 0 else ", / ."))
		if stats[0].shots >= 3:
			return ""
		if p.joy >= 0 or p.key_set < 0:
			return "RT  FIRE"
		return "SPACE  FIRE" if p.key_set == 0 else "ENTER  FIRE"
	var use: String = p.use_name()
	var lk = nearest_leak(p.global_position, LeakScript.RANGE)
	if lk != null:
		return "" if p.patching else "!HOLD  %s" % use
	if p.carrying:
		return ""
	if p.global_position.distance_to(World.HOLD_POS) < 2.6:
		for c in cannons:
			if c.ammo < c.MAX_AMMO or golden_balls > 0:
				return "PRESS  %s" % use
		return ""
	if not get_tree().get_nodes_in_group("boarders").is_empty() or not get_tree().get_nodes_in_group("tentacles").is_empty():
		return "!%s  SHOOT" % p.fire_name()
	return ""


func _emptiest_cannon() -> String:
	var best = cannons[0]
	for c in cannons:
		if c.ammo < best.ammo or (c.ammo == best.ammo and c.manned):
			best = c
	return "%s %s" % [best.side_name(), "FORE" if best.index % 2 == 0 else "AFT"]


# --- Stats, awards and game over ---------------------------------------------------

func _award(i: int) -> String:
	var st: Dictionary = stats[i]
	if i == 0:
		var acc := float(st.hits) / maxf(1.0, float(st.shots))
		if st.best_streak >= 6:
			return "HOT SHOT"
		if acc >= 0.6 and st.shots >= 5:
			return "EAGLE EYE"
		if st.sinks >= 8:
			return "SHIP SINKER"
		return "BRAVE GUNNER"
	var cats := [["loads", "CANNONBALL COURIER"], ["patches", "MASTER CARPENTER"], ["splashes", "BOARDER BOUNCER"],
		["monster", "MONSTER TICKLER"], ["kegs", "BOMB SQUASHER"]]
	var best := "TRUSTY LOOKOUT"
	var best_score := 0.0
	for cat in cats:
		var key: String = cat[0]
		var mine := float(st[key])
		if mine <= 0.0:
			continue
		var top := 0.0
		for j in range(1, players.size()):
			top = maxf(top, float(stats[j][key]))
		var score := mine / maxf(1.0, top) + mine * 0.01
		if score > best_score:
			best_score = score
			best = cat[1]
	return best


func _stats_lines() -> String:
	var lines: Array[String] = []
	var g: Dictionary = stats[0]
	var acc := int(100.0 * float(g.hits) / maxf(1.0, float(g.shots)))
	lines.append("P1 GUNNER  ·  %d sunk  ·  %d%% hits  ·  best streak %d   -   %s!" % [g.sinks, acc, g.best_streak, _award(0)])
	for p in players:
		if p.index == 0:
			continue
		var st: Dictionary = stats[p.index]
		var any: bool = st.loads + st.patches + st.splashes + st.monster + st.kegs > 0
		if not p.active and not any:
			continue
		lines.append("P%d  ·  %d loaded  ·  %d patched  ·  %d boarders splashed   -   %s!" % [p.index + 1, st.loads, st.patches, st.splashes, _award(p.index)])
	return "\n".join(lines)


## Shows the crew's stats and fun awards on every screen (and in VR).
func _show_stats(title: String, duration: float) -> void:
	stats_text = title + "\n" + _stats_lines()
	_apply_stats(stats_text, duration)
	net.event("stats", [stats_text, duration])


func _apply_stats(text: String, duration: float) -> void:
	stats_text = text
	stats_label.text = text
	stats_label.modulate.a = 1.0
	if duration > 0.0:
		var tw := stats_label.create_tween()
		tw.tween_interval(duration)
		tw.tween_property(stats_label, "modulate:a", 0.0, 0.6)
		tw.tween_callback(func() -> void: stats_text = "")


func _on_game_over() -> void:
	if game_over:
		return
	game_over = true
	game_over_time = 0.0
	sound("gameover")
	print("Game over: wave %d, gold %d" % [wave, gold])
	var cfg := ConfigFile.new()
	cfg.load("user://cannon_cove_best.cfg")
	var best: int = cfg.get_value("best", "gold", 0)
	var best_line := "Best haul: %d gold" % best
	if gold > best:
		best_line = "NEW RECORD HAUL!  (previous %d)" % best
		cfg.set_value("best", "gold", gold)
		cfg.set_value("best", "wave", wave)
		cfg.save("user://cannon_cove_best.cfg")
	if SIMPLE_MODE:
		_show_center("OH NO!", 0.0)  # sets sail again by itself after a few seconds
		return
	_show_center("THE SHIP SANK!\nWave %d  ·  %d gold\n%s\nPress A or Enter to set sail again" % [wave, gold, best_line], 0.0)
	_show_stats("CREW AWARDS", 0.0)
	print("Stats:\n" + _stats_lines())


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			return true
	for p in players:
		if p.bot_fire and not p.ghost and not p.remote:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# --- Networked co-op -----------------------------------------------------------------

func on_client_joined() -> void:
	_show_center("ALL ABOARD!" if SIMPLE_MODE else "THE DECKHANDS ARE ABOARD!", 1.5)


func on_client_left() -> void:
	_show_center("" if SIMPLE_MODE else "The deckhands left - waiting for them to come back…", 0.0)
	for p in players:
		if p.index >= 2 and p.active:
			p.reset_crew_state()
			p.set_active(false)  # the TV rejoins them when it reconnects


## Host: a TV deckhand did something.
func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index < 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"use":
			set_use(p, args[0])
		"musket":
			if not has_meta("p2_fired"):
				set_meta("p2_fired", true)
				print("Net: a deckhand fired a musket")
			musket_shot(p, args[0], args[1])
		"join":
			if not p.active:
				p.set_active(true)
				_show_center(("PLAYER %d!" if SIMPLE_MODE else "PLAYER %d JOINED THE CREW!") % (index + 1), 1.5)
				print("Net: player %d joined the game (%d deckhands)" % [index + 1, deckhands().size()])
		"leave":
			if p.active and index >= 1:
				p.reset_crew_state()
				p.set_active(false)
				if not SIMPLE_MODE:
					_show_center("Player %d left the crew" % (index + 1), 1.5)
				print("Net: player %d left the game" % (index + 1))
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A deckhand opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Press the menu button to resume")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		ps.append(p.net_state())
	var cs := []
	for c in cannons:
		cs.append(c.net_state())
	var sh := []
	for s in get_tree().get_nodes_in_group("ships"):
		sh.append(s.net_state())
	var te := []
	for t in get_tree().get_nodes_in_group("tentacles"):
		te.append(t.net_state())
	var bo := []
	for b in get_tree().get_nodes_in_group("boarders"):
		bo.append(b.net_state())
	var lk := []
	for l in get_tree().get_nodes_in_group("leaks"):
		lk.append(l.net_state())
	var tg := []
	for t in get_tree().get_nodes_in_group("targets"):
		tg.append(t.net_state())
	var kr := []
	for k in get_tree().get_nodes_in_group("krakens"):
		kr.append(k.net_state())
	return [wave, gold, water, game_over, in_break, ps, cs, sh, te, bo, lk, phase, tg, kr, golden_balls, streak,
		props.net_state() if props else []]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	wave = s[0]
	gold = s[1]
	water = s[2]
	game_over = s[3]
	in_break = s[4]
	var ps: Array = s[5]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	var cs: Array = s[6]
	for i in mini(cannons.size(), cs.size()):
		cannons[i].apply_net(cs[i])
	_sync_ghosts(s[7], "ship")
	_sync_ghosts(s[8], "tentacle")
	_sync_ghosts(s[9], "boarder")
	_sync_ghosts(s[10], "leak")
	if s.size() > 15:
		phase = s[11]
		_sync_ghosts(s[12], "target")
		_sync_ghosts(s[13], "kraken")
		golden_balls = s[14]
		streak = s[15]
	if s.size() > 16 and props:
		props.apply_net(s[16])


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
	match kind:
		"ship":
			var s := ShipScript.new()
			s.setup(item[1], wave, self)
			s.ghost = true
			s.net_id = item[0]
			s.position = item[2]
			s.net_target = item[2]
			s.heading = item[3]
			add_child(s)
			return s
		"tentacle":
			var t := TentacleScript.new()
			t.main = self
			t.ghost = true
			t.net_id = item[0]
			t.position = item[1]
			t.side = item[6]
			t.deck_target = item[7]
			add_child(t)
			return t
		"target":
			var tg := TargetScript.new()
			tg.main = self
			tg.ghost = true
			tg.kind = item[1]
			tg.net_id = item[0]
			tg.position = item[2]
			add_child(tg)
			return tg
		"kraken":
			var k := KrakenScript.new()
			k.main = self
			k.ghost = true
			k.net_id = item[0]
			k.position = item[1]
			k.side = item[7]
			add_child(k)
			return k
		"boarder":
			var b := BoarderScript.new()
			b.main = self
			b.ghost = true
			b.net_id = item[0]
			b.position = item[1]
			b.net_target = item[1]
			add_child(b)
			return b
	var lk := LeakScript.new()
	lk.main = self
	lk.ghost = true
	lk.net_id = item[0]
	lk.position = item[1]
	add_child(lk)
	return lk


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			_sfx().play(args[0], args[1], args[2])
		"popup":
			popup(args[0], args[1], args[2])
		"smoke":
			smoke(args[0], args[1])
		"splash":
			splash(args[0], args[1])
		"boom":
			explosion(args[0], args[1], args[2])
		"ball":
			spawn_ball(args[0], args[1], args[2], true, args[3] if args.size() > 3 else false)
		"confetti":
			confetti(args[0], false)
		"coins":
			coins_fx(args[0], false)
		"firework":
			fireworks(args[0], false)
		"dolphins":
			dolphins(args[0], args[1])
		"parrot":
			if parrot:
				parrot.say(args[0])
		"stats":
			_apply_stats(args[0], args[1])
		"cannon_fx":
			var i: int = args[0]
			if i >= 0 and i < cannons.size():
				cannons[i].fire_fx()
		"musket":
			var shooter: int = args[0]
			var mine: bool = shooter < players.size() and not players[shooter].ghost and not players[shooter].remote
			if not mine:
				musket_fx(shooter, args[1], args[2])
		"grapple":
			grapple_fx(args[0], args[1])
		"slam":
			var pos: Vector3 = args[0]
			add_shake(pos, 0.6)
			_particles(pos + Vector3.UP * 0.3, Color(0.6, 0.85, 1.0), 16, 0.12, 6.0, 14.0, 0.8, 60.0)
		"center":
			_show_center(args[0], args[1])
		"say":
			claude_say(args[0])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR gunner paused the game")
		"prop":
			if props:
				props.apply_event(args)
		"hitmark":
			var hi: int = args[0]
			if hi < players.size() and players[hi].hud:
				players[hi].hud.hit_marker()


# --- HUD ----------------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
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
	center_label = _make_label(58)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.offset_bottom = -120
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# How to play: a panel for each role, shown until the first wave is over.
	help_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.16, 0.78)
	sb.border_color = Color(1.0, 0.8, 0.3, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	help_panel.add_theme_stylebox_override("panel", sb)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help_panel)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	help_panel.offset_top = 62
	help_label = _make_label(23)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help_label.text = "HOW TO PLAY  -  keep our ship afloat and sink the pirates!\n" \
		+ "DECKHANDS (TV):  move with the left stick,  look with the right stick\n" \
		+ "    1. Walk to the CANNONBALL pile at the front, press A to pick one up\n" \
		+ "    2. Walk to a cannon - it loads by itself (follow your ARROW)\n" \
		+ "    3. LEAK? Stand next to it and HOLD A to patch it\n" \
		+ "    4. BOARDERS, bomb boats, tentacles? Shoot them with RT (your musket)\n" \
		+ "GUNNER (VR):  grab the glowing handle (hold the trigger), aim the gold ring, LET GO to fire\n" \
		+ "    A or a left-stick flick hops to the next cannon  ·  flat: sticks aim, RT fire, LB/RB switch\n" \
		+ "MORE CREW: press A on another controller to jump in (up to 6 deckhands)"
	help_panel.add_child(help_label)
	if SIMPLE_MODE:
		help_panel.visible = false  # the arrows and the practice targets teach instead
	help_panel.resized.connect(func() -> void: help_panel.position.x = (help_panel.get_parent_area_size().x - help_panel.size.x) * 0.5)
	# End-of-voyage stats and awards.
	stats_label = _make_label(28)
	stats_label.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	layer.add_child(stats_label)
	stats_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stats_label.offset_top = -330
	stats_label.offset_bottom = -40
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


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


func wave_title() -> String:
	if phase == "practice":
		return "TARGET PRACTICE"
	if wave <= 0:
		return "GET READY"
	if wave <= BOSS_WAVE:
		return "WAVE %d/%d  %s" % [wave, BOSS_WAVE, WAVE_NAMES[wave]]
	return "BONUS WAVE %d" % (wave - BOSS_WAVE)


func _update_hud() -> void:
	var dt := get_process_delta_time()
	if SIMPLE_MODE:
		help_panel.visible = false
		if net.mode == "client" and not synced:
			info_label.text = ""
			return
		info_label.text = "" if phase == "practice" or wave <= 0 else ("WAVE %d" % wave)
		return
	var show_help := phase == "practice" or wave <= 1
	help_panel.modulate.a = clampf(help_panel.modulate.a + (dt if show_help else -dt * 0.7), 0.0, 1.0)
	help_panel.visible = help_panel.modulate.a > 0.0
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the VR gunner…"
		return
	var extra := ""
	if streak >= 3:
		extra = "     STREAK x%d" % streak
	if golden_balls > 0:
		extra += "     GOLDEN BALL ON THE PILE!"
	info_label.text = "%s     GOLD %d     WATER %d%%%s" % [wave_title(), gold, int(water), extra]


## VR can't show 2D overlays: mirror the centre banner on a world-locked Label3D, plus a lower
## "what to do next" hint (and the awards at the end).
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 48
		vr_center.outline_size = 26
		vr_center.no_depth_test = false
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.pixel_size = 0.0026
		vr_center.position = Vector3(0.0, 0.05, -1.8)
		players[0].xr_camera.add_child(vr_center)
		players[0]._set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.text = preload("res://core/vr_text.gd").short(center_label.text)  # no walls of text in VR
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, players[0].xr_camera, self, 0.08, 1.8)
	if vr_hint == null:
		vr_hint = Label3D.new()
		vr_hint.font_size = 40
		vr_hint.outline_size = 22
		vr_hint.no_depth_test = false
		vr_hint.render_priority = 10
		vr_hint.outline_render_priority = 9
		vr_hint.width = 800.0
		vr_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_hint.pixel_size = 0.0019
		vr_hint.modulate = Color(1.0, 0.95, 0.6)
		add_child(vr_hint)
		players[0]._set_layers(vr_hint, players[0].viewmodel_layer())
	var hint := coach_text
	var stats_mode: bool = stats_text != "" and (game_over or phase == "victory")
	if stats_mode != vr_hint.get_meta("stats_mode", false):
		vr_hint.set_meta("stats_mode", stats_mode)
		VrText.snap(vr_hint)  # jump to the new height
	if stats_mode:
		hint = stats_text
		vr_hint.modulate = Color(0.85, 0.97, 1.0)
		vr_hint.pixel_size = 0.0016
	else:
		vr_hint.modulate = Color(1.0, 0.95, 0.6) if not hint.contains("EMPTY") else Color(1.0, 0.55, 0.45)
		vr_hint.pixel_size = 0.0019
	vr_hint.text = hint
	vr_hint.visible = hint != ""
	VrText.follow(vr_hint, players[0].xr_camera, self, -0.5 if stats_mode else -0.3, 1.8)


# Messages from Claude (res://.dev/say.txt on the host), shown on the TV and in VR.
func _check_say(delta: float) -> void:
	say_t -= delta
	if say_t > 0.0:
		return
	say_t = 0.3
	var path := ProjectSettings.globalize_path("res://.dev/say.txt")
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path).strip_edges()
	DirAccess.remove_absolute(path)
	if text != "":
		claude_say(text)


func claude_say(text: String) -> void:
	if net:
		net.event("say", [text])
	_show_center("Claude: " + text, 5.0 + text.length() * 0.08, false)
	_sfx().play("pickup", -6.0, 0.8)
