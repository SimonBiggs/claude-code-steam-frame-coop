extends Node
## Arena director: surprise arena events (meteor shower, gold rush, dino stampede, power surge, Fishwort
## dives), the team combo, per-player stats and end-of-round awards, short "how do I…" hints (TV + VR),
## the cheering crowd and the arena's mood colour. The host decides; the TV machine mirrors the small
## state in snapshots (pack/unpack) and gets one-off events ("hint", "meteor", "fireworks").

const VrText := preload("res://core/vr_text.gd")

const COMBO_TIME := 3.0
const COMBO_MILESTONES := [5, 10, 15, 20, 30, 40, 50, 75, 100]
const METEOR_FALL := 1.6
const METEOR_RADIUS := 2.3
const EVENTS := {
	"meteor": ["METEOR SHOWER!", "Run out of the RED CIRCLES before the rocks land!", 13.0],
	"gold": ["GOLD RUSH!", "GOLDEN monsters are worth TRIPLE points - get them!", 20.0],
	"stampede": ["DINO STAMPEDE!", "A herd of dinosaurs is coming - stick together!", 6.0],
	"surge": ["POWER SURGE!", "Your co-op BEAM is SUPER strong - stand close together!", 15.0],
	"dive": ["FISHWORT DIVES!", "VR player: SLICE the fish with your SWORD! Everyone: shoot it!", 26.0],
}
const MOODS := {
	"": Vector3(0.15, 0.75, 1.0),
	"meteor": Vector3(1.0, 0.35, 0.08),
	"gold": Vector3(1.0, 0.75, 0.15),
	"stampede": Vector3(0.35, 1.0, 0.3),
	"surge": Vector3(0.7, 1.0, 1.0),
	"dive": Vector3(0.3, 0.55, 1.0),
	"boss": Vector3(1.0, 0.12, 0.4),
	"victory": Vector3(1.0, 0.85, 0.3),
}
const KIND_HINTS := {
	"runner": "RUNNERS are fast but weak - shoot them quick!",
	"brute": "BRUTES are big and tough - everyone shoot the same one!",
	"spitter": "SPITTERS shoot green orbs: dodge them, or block them with the VR SHIELD!",
	"splitter": "SPLITTERS burst into little runners when they pop!",
	"dino": "DINOSAURS charge when they ROAR - dash out of the way!",
	"raptor": "RAPTORS! Little fast dinos that hunt in packs!",
	"ptero": "PTERODACTYLS fly up high and swoop down - aim UP! Their shadow shows where they are.",
	"ankylo": "ARMORED ANKYLO! Bullets bounce off. VR: SLICE it with the SWORD! TV: DASH into it!",
}
const BOSS_HINTS := {
	"boss": "ORB OVERLORD! When the RED RING appears, get out before it SLAMS!",
	"rex": "KING REX! When he rears up, run out of the red ring! He calls raptors to help!",
	"omega": "THE FINAL BOSS! Everyone together - and watch out for Fishwort!",
}
const AWARDS := [
	["MVP", "points"],
	["LIFESAVER", "revives"],
	["SWORD MASTER", "slices"],
	["SHELL CRACKER", "cracks"],
	["FISH FIGHTER", "fish"],
	["DINO HUNTER", "dinos"],
	["SHARPSHOOTER", "kills"],
	["COLLECTOR", "pickups"],
	["NEVER GIVES UP", "downs"],
]

var main
# Team combo.
var combo := 0
var combo_t := 0.0
var best_combo := 0
# Events (host decides; name mirrored for the HUD).
var event_name := ""
var event_t := 0.0
var pending_event := ""
var pending_t := 0.0
var last_event := ""
var waves_since_event := 0
var meteor_t := 0.0
var impacts: Array = []  # host: [pos, time left]
var dives_left := 0
var dive_t := 0.0
var gold_left := 0
var frenzy := false  # finale: Fishwort keeps diving
# Players.
var stats := {}  # player index -> {kills, points, revives, ...}
var told := {}  # hints already shown this game (key -> true or next allowed time)
# Look and feel.
var mood := ""
var mood_col := Vector3(0.15, 0.75, 1.0)
var cheer_level := 0.0
var cheer_hold := 0.0
var fireworks_t := 0.0
var fireworks_cd := 0.0
# Mirrored state for the TV HUD.
var boss_name := ""
var boss_frac := -1.0
var left := 0
# UI.
var layer: CanvasLayer
var hint_label: Label
var combo_label: Label
var boss_label: Label
var boss_bar: ProgressBar
var hint_3d: Label3D
var hint_tween: Tween
var shown_combo := 0


func _ready() -> void:
	name = "Director"


# --- Per frame ----------------------------------------------------------------

func tick(delta: float) -> void:
	_ensure_ui()
	if main.net.mode != "client" and not main.game_over:
		_host_tick(delta)
	cheer_hold = maxf(0.0, cheer_hold - delta)
	if cheer_hold <= 0.0:
		cheer_level = maxf(0.0, cheer_level - delta * 0.35)
	var mats: Array = main.get_meta("crowd_mats", [])
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("cheer", cheer_level)
	var want: Vector3 = MOODS.get(mood, MOODS[""])
	mood_col = mood_col.lerp(want, 1.0 - exp(-3.0 * delta))
	var floor_mat: ShaderMaterial = main.get_meta("floor_mat", null)
	if floor_mat != null:
		var pulse := 1.0
		if mood == "surge":
			pulse = 1.4 + 0.6 * sin(Time.get_ticks_msec() * 0.012)
		floor_mat.set_shader_parameter("line_color", mood_col * pulse)
	var edge_mat: StandardMaterial3D = main.get_meta("edge_mat", null)
	if edge_mat != null:
		var c := Color(mood_col.x, mood_col.y, mood_col.z)
		edge_mat.albedo_color = c
		edge_mat.emission = c
	if fireworks_t > 0.0:
		fireworks_t -= delta
		fireworks_cd -= delta
		if fireworks_cd <= 0.0:
			fireworks_cd = 0.22
			var a := randf() * TAU
			var r := randf_range(6.0, 16.0)
			var cols: Array[Color] = main.PLAYER_COLORS
			_local_burst(Vector3(cos(a) * r, randf_range(7.0, 13.0), sin(a) * r), cols.pick_random(), 28, 0.22)
	_update_ui(delta)


func _host_tick(delta: float) -> void:
	if combo > 0:
		combo_t -= delta
		if combo_t <= 0.0:
			combo = 0
	if pending_event != "":
		pending_t -= delta
		if pending_t <= 0.0:
			var ev := pending_event
			pending_event = ""
			start_event(ev)
	if event_name != "":
		event_t -= delta
		_event_tick(delta)
		if event_t <= 0.0:
			end_event()
	if frenzy and main.sky_fish != null and main.sky_fish.alive:
		dive_t -= delta
		if dive_t <= 0.0:
			dive_t = 14.0
			_dive_now()
	for i in range(impacts.size() - 1, -1, -1):
		impacts[i][1] -= delta
		if impacts[i][1] <= 0.0:
			_meteor_impact(impacts[i][0])
			impacts.remove_at(i)
	_check_bash()
	# Boss and wave progress, for the HUD on both machines.
	boss_name = ""
	boss_frac = -1.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_boss():
			boss_name = e.boss_name()
			boss_frac = clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
			break
	left = main.to_spawn + get_tree().get_nodes_in_group("enemies").size()


# --- Waves & events -------------------------------------------------------------

func on_wave_started(wave: int, boss_kind: String) -> void:
	if event_name != "dive":
		end_event()  # a Fishwort dive may finish its run into the next wave
	frenzy = false
	gold_left = 0
	if boss_kind != "":
		mood = "boss"
		hint(BOSS_HINTS.get(boss_kind, "BOSS INCOMING!"), 5.0, "boss_" + boss_kind)
		if boss_kind == "omega":
			frenzy = true
			dive_t = 9.0
		return
	mood = ""
	waves_since_event += 1
	if wave < 3:
		return
	if randf() < 0.55 or waves_since_event >= 2:
		var choices: Array[String] = ["meteor", "gold", "stampede", "surge"]
		if main.sky_fish != null and main.sky_fish.alive:
			choices.append("dive")
		choices.erase(last_event)
		pending_event = choices.pick_random()
		pending_t = 4.0


func on_wave_cleared() -> void:
	if event_name != "dive":
		end_event()
	pending_event = ""
	frenzy = false
	if event_name == "":
		mood = ""


func start_event(ev: String) -> void:
	if not EVENTS.has(ev) or main.net.mode == "client":
		return
	end_event()
	var info: Array = EVENTS[ev]
	event_name = ev
	event_t = info[2]
	last_event = ev
	waves_since_event = 0
	mood = ev
	print("Event: %s" % ev)
	main._show_center(info[0], 2.0)
	hint(info[1], 5.0)
	main.sound("wave", 0.0, 1.3)
	match ev:
		"meteor":
			meteor_t = 1.0
		"gold":
			gold_left = 8
			for i in 3:
				main.spawn_enemy_at("grunt", main.edge_point(), true)
		"stampede":
			_stampede()
		"surge":
			cheer(0.6)
		"dive":
			dives_left = 3
			dive_t = 1.5


func end_event() -> void:
	if event_name == "":
		return
	print("Event over: %s" % event_name)
	event_name = ""
	dives_left = 0
	if mood != "boss":
		mood = ""


func _event_tick(delta: float) -> void:
	match event_name:
		"meteor":
			meteor_t -= delta
			if meteor_t <= 0.0 and event_t > METEOR_FALL:
				meteor_t = randf_range(0.5, 0.9)
				_spawn_meteor()
		"dive":
			dive_t -= delta
			if dive_t <= 0.0 and dives_left > 0:
				dives_left -= 1
				dive_t = 8.5
				_dive_now()


## Gold rush: the next few monsters come out golden.
func take_golden() -> bool:
	if gold_left > 0:
		gold_left -= 1
		return true
	return false


## Beam strength multiplier (power surge).
func beam_mult() -> float:
	return 3.0 if event_name == "surge" else 1.0


func beam_color() -> Color:
	return Color(1.0, 0.9, 0.4) if event_name == "surge" else Color(0.7, 1.0, 0.95)


func _stampede() -> void:
	var a := randf() * TAU
	var kinds: Array[String] = ["dino", "raptor", "dino", "ankylo"]
	if main.wave >= 6:
		kinds.append("dino")
	for i in kinds.size():
		var aa := a + (i - kinds.size() * 0.5) * 0.12
		var pos: Vector3 = Vector3(cos(aa), 0.0, sin(aa)) * (main.ARENA_RADIUS - 1.5)
		main.spawn_enemy_at(kinds[i], pos)
	main.sound("roar", 2.0, 0.9)
	main.add_shake(Vector3(cos(a), 0.0, sin(a)) * 12.0, 0.4)


func _dive_now() -> void:
	var targets: Array = main.players.filter(func(p) -> bool: return p.active and not p.is_down)
	if targets.is_empty() or main.sky_fish == null:
		return
	# Prefer the VR player (they have the sword), but sometimes visit the TV players.
	var target = targets[0] if targets[0].vr and randf() < 0.6 else targets.pick_random()
	main.sky_fish.start_dive(target.global_position)


# --- Meteors ----------------------------------------------------------------

func _spawn_meteor() -> void:
	var pos := Vector3.ZERO
	var targets: Array = main.players.filter(func(p) -> bool: return p.active and not p.is_down)
	if not targets.is_empty() and randf() < 0.65:
		var tp: Vector3 = targets.pick_random().global_position
		var off := Vector2.from_angle(randf() * TAU) * randf_range(0.5, 3.0)
		pos = Vector3(tp.x + off.x, 0.0, tp.z + off.y)
	else:
		var a := randf() * TAU
		pos = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.0, main.ARENA_RADIUS - 3.0)
	var flat := Vector2(pos.x, pos.z).limit_length(main.ARENA_RADIUS - 2.0)
	pos = Vector3(flat.x, 0.0, flat.y)
	meteor_visual(pos, METEOR_FALL)
	main.net.event("meteor", [pos, METEOR_FALL])
	impacts.append([pos, METEOR_FALL])
	main.sound("meteor", -6.0)


## Both machines: a pulsing red warning circle and a burning rock falling into it.
func meteor_visual(pos: Vector3, fall: float) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = METEOR_RADIUS
	cyl.bottom_radius = METEOR_RADIUS
	cyl.height = 0.03
	cyl.radial_segments = 24
	disc.mesh = cyl
	var dm: StandardMaterial3D = main.make_material(Color(1.0, 0.15, 0.05), 2.0)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color.a = 0.35
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(disc)
	disc.global_position = pos + Vector3.UP * 0.06
	disc.scale = Vector3(0.2, 1.0, 0.2)
	var dt := disc.create_tween()
	dt.tween_property(disc, "scale", Vector3.ONE, fall * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dt.parallel().tween_property(dm, "albedo_color:a", 0.75, fall)
	dt.tween_callback(disc.queue_free)
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	sm.radial_segments = 10
	sm.rings = 5
	rock.mesh = sm
	rock.material_override = main.make_material(Color(1.0, 0.45, 0.1), 5.0)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(rock)
	var start := pos + Vector3(4.0, 24.0, -3.0)
	rock.global_position = start
	var trail := CPUParticles3D.new()
	trail.amount = 12
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 20.0
	trail.initial_velocity_min = 1.0
	trail.initial_velocity_max = 2.0
	trail.gravity = Vector3.ZERO
	var tm := BoxMesh.new()
	tm.size = Vector3.ONE * 0.22
	tm.material = main.make_material(Color(1.0, 0.6, 0.2), 3.0)
	trail.mesh = tm
	rock.add_child(trail)
	var rt := rock.create_tween()
	rt.tween_property(rock, "global_position", pos + Vector3.UP * 0.3, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	rt.tween_callback(rock.queue_free)


func _meteor_impact(pos: Vector3) -> void:
	main.explosion(pos + Vector3.UP * 0.3, Color(1.0, 0.45, 0.1), 0.7)
	main.sound("big_kill", -2.0, 1.1)
	main.add_shake(pos, 0.35)
	for p in main.players:
		if p.active and not p.is_down and p.global_position.distance_to(pos) < METEOR_RADIUS:
			p.take_damage(14.0, pos)
	for e in get_tree().get_nodes_in_group("enemies"):
		var to: Vector3 = e.global_position - pos
		to.y = 0.0
		if to.length() < METEOR_RADIUS + e.radius and e.lift < 1.5:
			e.hit(5.0, to.normalized() if to.length() > 0.01 else Vector3.RIGHT, 2.0)


# --- Dash bash (cracks ankylo shells) --------------------------------------

func on_dash(p) -> void:
	if main.net.mode == "client":
		return
	p.set_meta("bash_until", Time.get_ticks_msec() + 380)
	p.set_meta("bashed", [])


func _check_bash() -> void:
	var now := Time.get_ticks_msec()
	for p in main.players:
		if not p.active or now > int(p.get_meta("bash_until", 0)):
			continue
		var hit_ids: Array = p.get_meta("bashed", [])
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.armor <= 0 or hit_ids.has(e.net_id):
				continue
			var to: Vector3 = e.global_position - p.global_position
			to.y = 0.0
			if to.length() < e.radius + 1.2:
				hit_ids.append(e.net_id)
				e.bash(p)
		p.set_meta("bashed", hit_ids)


# --- Combo, stats, awards -------------------------------------------------------

## Host: a monster died. Returns the points after the combo bonus.
func on_kill(killer, e, points: int) -> int:
	combo += 1
	combo_t = COMBO_TIME
	best_combo = maxi(best_combo, combo)
	var mult := 1.0 + minf(float(combo - 1), 20.0) * 0.1
	var total := int(round(points * mult))
	if killer != null and is_instance_valid(killer):
		add_stat(killer, "kills", 1)
		add_stat(killer, "points", total)
		if e != null and e.is_dino():
			add_stat(killer, "dinos", 1)
	if e != null and e.is_boss():
		cheer(1.0, 4.0)
		main.sound("cheer", 0.0)
	else:
		cheer(0.12 + 0.02 * minf(combo, 20.0))
	if combo in COMBO_MILESTONES:
		main.popup(e.global_position + Vector3.UP * 3.0 if e != null else Vector3.UP * 3.0, "COMBO x%d!" % combo, Color(1.0, 0.85, 0.3))
		main.sound("combo", 0.0, 1.0 + combo * 0.004)
		cheer(0.9, 1.5)
		if combo >= 10:
			main.sound("cheer", -4.0)
		if combo == 5:
			hint("COMBO! Keep defeating monsters quickly for BONUS points!", 3.5, "combo")
		if combo >= 20:
			main.achievements().unlock("combo_king")
	return total


func add_stat(p, key: String, amount: int) -> void:
	if p == null or not is_instance_valid(p) or main.net.mode == "client":
		return
	var idx: int = p.index
	if not stats.has(idx):
		stats[idx] = {}
	var d: Dictionary = stats[idx]
	d[key] = int(d.get(key, 0)) + amount


func get_stat(idx: int, key: String) -> int:
	if not stats.has(idx):
		return 0
	return int(stats[idx].get(key, 0))


func on_revive(helper, downed) -> void:
	add_stat(helper, "revives", 1)
	if helper != null and is_instance_valid(helper):
		main.popup(downed.global_position + Vector3.UP * 2.4, "P%d SAVED P%d!" % [helper.index + 1, downed.index + 1], helper.color.lightened(0.3))
	cheer(0.8, 1.0)
	main.sound("cheer", -3.0, 1.1)
	hint("TEAMWORK! The crowd LOVES a rescue!", 3.0, "revive_cheer")


func on_down(p) -> void:
	add_stat(p, "downs", 1)
	main.wave_downs += 1
	hint_every("P%d is DOWN! Stand in their glowing ring to revive them!" % (p.index + 1), 3.5, "down", 9.0)


## Awards for the end screen: every player gets at least one.
func awards_text() -> String:
	var active: Array = main.players.filter(func(p) -> bool: return p.active)
	if active.is_empty():
		return ""
	var given := {}  # index -> Array of titles
	for p in active:
		given[p.index] = []
	for aw in AWARDS:
		var key: String = aw[1]
		var best = null
		var best_v := 0
		for p in active:
			var v := get_stat(p.index, key)
			var mine: Array = given[p.index]
			if v > best_v and mine.size() < 2:
				best_v = v
				best = p
		if best != null:
			given[best.index].append(aw[0])
	var lines: Array[String] = ["* AWARDS *"]
	for p in active:
		var mine: Array = given[p.index]
		if mine.is_empty():
			mine.append("TEAM PLAYER")
		var who := "P%d%s" % [p.index + 1, " (VR)" if p.index == 0 and main.net.mode == "host" else ""]
		lines.append("%s  %s  (%d kills)" % [who, " + ".join(PackedStringArray(mine)), get_stat(p.index, "kills")])
	if best_combo >= 5:
		lines.append("Best team combo: x%d" % best_combo)
	return "\n".join(lines)


# --- Hints -----------------------------------------------------------------------

## A short tip on the TV and in VR. With a key it is shown once per game.
func hint(text: String, duration: float = 4.0, key: String = "", vr_text: String = "") -> void:
	if key != "":
		if told.has(key):
			return
		told[key] = true
	if main.net.mode == "host":
		main.net.event("hint", [text, duration])
	show_hint(vr_text if vr_text != "" and _vr() else text, duration)


## Like hint(), but may repeat after `cooldown` seconds.
func hint_every(text: String, duration: float, key: String, cooldown: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(told.get(key, -1000.0)):
		return
	told[key] = now + cooldown
	if main.net.mode == "host":
		main.net.event("hint", [text, duration])
	show_hint(text, duration)


func show_hint(text: String, duration: float) -> void:
	_ensure_ui()
	hint_label.text = text
	var nodes: Array = [hint_label]
	if _vr():
		if hint_3d == null:
			hint_3d = Label3D.new()
			hint_3d.font_size = 40
			hint_3d.outline_size = 26
			hint_3d.pixel_size = 0.0022
			hint_3d.no_depth_test = false
			hint_3d.render_priority = 10
			hint_3d.outline_render_priority = 9
			hint_3d.width = 1100.0
			hint_3d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_3d.modulate = Color(0.75, 1.0, 0.85)
			main.add_child(hint_3d)
			main.players[0]._set_layers(hint_3d, main.players[0].viewmodel_layer())
		hint_3d.text = text
		VrText.follow(hint_3d, main.players[0].xr_camera, main, -0.62, 1.8)
		nodes.append(hint_3d)
	if hint_tween:
		hint_tween.kill()
	hint_tween = create_tween().set_parallel()
	for n in nodes:
		n.modulate.a = 1.0
		hint_tween.tween_property(n, "modulate:a", 0.0, 0.5).set_delay(duration)
	if hint_3d != null:
		hint_3d.outline_modulate = Color(0, 0, 0, 1)
		hint_tween.tween_property(hint_3d, "outline_modulate:a", 0.0, 0.5).set_delay(duration)


## Before wave 1: how to play. The VR player gets their own version (while waiting for the TV, too);
## the TV version goes out once the TV is connected.
const TV_HOWTO := "HOW TO PLAY: shoot the neon monsters together! Stay close - the BEAM between you zaps them. " \
	+ "Friend down? Stand in their ring. Spend XP by shooting the glowing buttons on the floor."
const VR_HOWTO := "HOW TO PLAY\nRIGHT TRIGGER: shoot   LEFT STICK: walk   RIGHT STICK: turn\n" \
	+ "LEFT HAND SHIELD bounces green orbs back\nReach over your LEFT SHOULDER for the SWORD - swing it!\n" \
	+ "TOUCH glowing pickups to grab them"


func howto() -> void:
	var tv_ready: bool = main.net.mode != "host" or main.net.connected
	if not told.has("howto_tv") and tv_ready:
		told["howto_tv"] = true
		if main.net.mode == "host":
			main.net.event("hint", [TV_HOWTO, 12.0])
		if not _vr():
			show_hint(TV_HOWTO, 12.0)
	if not told.has("howto_vr") and _vr():
		told["howto_vr"] = true
		show_hint(VR_HOWTO, 16.0)


func on_enemy_spawned(kind: String) -> void:
	if KIND_HINTS.has(kind):
		hint("NEW: " + KIND_HINTS[kind], 4.5, "kind_" + kind)


func on_pickup(kind: String) -> void:
	var tips := {
		"rapid": "RAPID FIRE! You shoot twice as fast for a while!",
		"bubble": "SHIELD BUBBLE! Nothing can hurt you for a few seconds!",
		"bomb": "MEGA BOMB! BOOM - it blasts every monster nearby!",
		"spread": "SPREAD SHOT! Three bullets at once!",
	}
	if tips.has(kind):
		hint(tips[kind], 3.0, "pickup_" + kind)


# --- Crowd, fireworks -----------------------------------------------------------

func cheer(amount: float, hold: float = 0.0) -> void:
	cheer_level = clampf(maxf(cheer_level, amount), 0.0, 1.0)
	cheer_hold = maxf(cheer_hold, hold)


func victory() -> void:
	mood = "victory"
	fireworks(8.0)
	if main.net.mode == "host":
		main.net.event("fireworks", [8.0])


func fireworks(seconds: float) -> void:
	fireworks_t = seconds
	cheer(1.0, seconds)
	mood = "victory"


func _local_burst(pos: Vector3, color: Color, amount: int, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.1
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -4, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = main.make_material(color, 4.0)
	p.mesh = m
	main.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	if randf() < 0.4:
		main.sfx_local("pickup", -14.0, randf_range(0.5, 0.8))


# --- Network --------------------------------------------------------------------

func pack() -> Array:
	return [combo, mood, boss_name, boss_frac, left, event_name, best_combo]


func unpack(a: Array) -> void:
	if a.size() < 7:
		return
	var new_combo: int = a[0]
	if new_combo > combo and new_combo >= 2:
		_pop_combo()
	combo = new_combo
	mood = a[1]
	boss_name = a[2]
	boss_frac = a[3]
	left = a[4]
	event_name = a[5]
	best_combo = a[6]


func client_event(kind: String, args: Array) -> void:
	match kind:
		"hint":
			show_hint(args[0], args[1])
		"meteor":
			meteor_visual(args[0], args[1])
		"fireworks":
			fireworks(args[0])


# --- TV overlay -------------------------------------------------------------------

func _vr() -> bool:
	return not main.players.is_empty() and main.players[0].vr


func _ensure_ui() -> void:
	if layer != null and is_instance_valid(layer):
		return
	layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hint_label = main._make_label(30)
	hint_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.85))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(hint_label)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_left = -820
	hint_label.offset_right = 820
	hint_label.offset_top = -360
	hint_label.offset_bottom = -255
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint_label.modulate.a = 0.0
	combo_label = main._make_label(44)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	layer.add_child(combo_label)
	combo_label.position = Vector2(34, 96)
	combo_label.pivot_offset = Vector2(80, 30)
	boss_label = main._make_label(28)
	boss_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.6))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(boss_label)
	boss_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_label.offset_left = -300
	boss_label.offset_right = 300
	boss_label.offset_top = 92
	boss_label.offset_bottom = 128
	boss_bar = ProgressBar.new()
	boss_bar.show_percentage = false
	boss_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.25, 0.4)
	fill.set_corner_radius_all(6)
	boss_bar.add_theme_stylebox_override("background", bg)
	boss_bar.add_theme_stylebox_override("fill", fill)
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(boss_bar)
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_bar.offset_left = -300
	boss_bar.offset_right = 300
	boss_bar.offset_top = 130
	boss_bar.offset_bottom = 152


func _pop_combo() -> void:
	if combo_label == null:
		return
	combo_label.scale = Vector2.ONE * 1.35
	var t := combo_label.create_tween()
	t.tween_property(combo_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_ui(_delta: float) -> void:
	if combo >= 2:
		if combo != shown_combo and main.net.mode != "client":
			_pop_combo()
		combo_label.text = "COMBO x%d" % combo
		combo_label.modulate.a = 1.0
	else:
		combo_label.modulate.a = maxf(0.0, combo_label.modulate.a - _delta * 2.0)
	shown_combo = combo
	var show_boss := boss_frac >= 0.0 and boss_name != ""
	boss_label.visible = show_boss
	boss_bar.visible = show_boss
	if show_boss:
		boss_label.text = boss_name
		boss_bar.value = boss_frac
	if hint_3d != null and _vr():
		VrText.follow(hint_3d, main.players[0].xr_camera, main, -0.62, 1.8)
