extends Node3D
## ELEMENTAL BENDER: defend the island temple from waves of masked Shadow Raiders with the four
## elements. Ported from the single-player flat game in ~/GodotProjects/elemental-bender (same look,
## feel, numbers and content) onto the shared arcade engine.
## - The counter cycle AIR > EARTH > WATER > FIRE > AIR: a counter hit does x2 (yellow "!" number),
##   the same element x0.5 (grey). Each raider's head orb shows its element.
## - Specials: Tornado Burst (air), Healing Tide (water), Earthquake (earth), Fire Nova (fire).
## - Knock raiders off the island into the sea: "Ring out!" (+50).
## - Hits and kills fill the TEAM's spirit meter; when it is full anyone can enter SPIRIT STATE
##   (12 s: all four elements at once, full chi, 70% less damage).
## - A Shadow General (boss) every 5th wave, who swaps element every 5 seconds.
## - PRACTICE first: one dummy per element, glowing in the colour that beats it; hit it with the
##   right element and it pops, the next appears. Then wave 1. Between waves a short breather + heal.
##   Everyone down at once = the temple falls: results with awards, then play again or the arcade.
## Roles:
## - TV players (slots 1..6, drop in with A): bender.gd, third-person chase cameras in split screen.
## - VR player (slot 0 on the host): vr_bender.gd, the MASTER BENDER bending with the hands.
## - Local play without a headset: slot 0 is a normal TV bender (party.allow_slot0).
## Network: host-authoritative raiders, damage, health, score, spirit; TV benders move on the TV
## machine and ask the host for every attack (request "fire"/"special"/...); shots and effects are
## sent as small events and drawn as visual ghosts; raiders as ghost copies from 30 Hz snapshots.
## STORY + DEPTH (wavegen.gd, temple_story.gd, story_pictures.gd): KIKO, the little temple fox, sits in the middle
## of the temple and tells the story on picture cards. Every wave's raiders step out of SHADOW PORTALS on the island
## (seeded: they open in the breather before the wave, the first in front of the temple), and the waves teach the
## elements one at a time (wave 1 and 2: one element each, Kiko shows what beats it; then two, three, all four).
## tests/elemental_bender_gen_test.gd proves every wave fair for small kids. Every wave cleared grows the SPIRIT TREE
## beside the temple (saved over days), every Shadow General beaten hangs a glowing fruit on it, a stone LANTERN
## joins the temple ring every play-day, and Kiko wears a crown after WaveGen.CROWN_GENERALS Generals.
## TODAY'S RAIDERS: the first game each day uses the day's seed on every machine. Telemetry: one RUN line per wave
## cleared, at game over and on quit. Networked: sticky events "gates" [temple seed, wave] and "temple" [waves,
## fruit, days, crown] (machines that join late get them too); every machine rebuilds the portals and the tree.
## EB_FAST=1: short practice, small waves (tests). EB_SEED=n: play temple seed n.

const NetScript := preload("res://core/net.gd")
const Who := preload("res://core/who.gd")  # who joined / left (names, not "TV player")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const Save := preload("res://core/save.gd")
const UiKit := preload("res://core/ui_kit.gd")
const UiMenu := preload("res://core/ui_menu.gd")
const VrMenu := preload("res://core/vr_menu.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const E := preload("res://games/elemental_bender/elem.gd")
const World := preload("res://games/elemental_bender/world.gd")
const Fx := preload("res://games/elemental_bender/fx.gd")
const Looks := preload("res://games/elemental_bender/looks.gd")
const Bender := preload("res://games/elemental_bender/bender.gd")
const Raider := preload("res://games/elemental_bender/raider.gd")
const Projectile := preload("res://games/elemental_bender/projectile.gd")
const VrBender := preload("res://games/elemental_bender/vr_bender.gd")
const WaveGen := preload("res://games/elemental_bender/wavegen.gd")
const TempleStory := preload("res://games/elemental_bender/temple_story.gd")
const Pics := preload("res://games/elemental_bender/story_pictures.gd")
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")

const GAME_ID := "elemental_bender"
const MAX_ALIVE := 14
## Practice dummies in order: each one needs the next element (AIR, WATER, EARTH, FIRE).
const PRACTICE: Array[int] = [E.EARTH, E.FIRE, E.WATER, E.AIR]
const DUMMY_AT := Vector3(0.0, 0.0, -10.0)
const KIKO := "KIKO"
const KIKO_COLOR := Color(1.0, 0.6, 0.25)
const INTRO := {
	"title": "ELEMENTAL BENDER",
	"goal": "Defend the temple! FIRE beats AIR, AIR beats EARTH, EARTH beats WATER, WATER beats FIRE.",
	"vr": {"role": "THE MASTER BENDER", "controls": [["ORBS", "Touch one: element"], ["TRIGGER", "Hold + punch"],
		["BOTH HANDS", "Up, then slam down"], ["A", "Special / Spirit"]]},
	"tv": {"role": "THE BENDERS", "controls": [["RT", "Bend"], ["LT", "Special"], ["LB", "Switch element"],
		["B", "Dash"], ["A", "Jump"], ["L3", "Spirit State"]],
		"tips": ["Hit raiders with the element that beats their orb!"]},
}

# --- The networking contract ---
var net: Node
var ready_to_play := false
var party: Party
## Any number of TV machines (TV, Steam Decks) may join, and a flat host (no VR) works (docs/MULTI_MACHINE.md).
var multi_machine := true
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var hints: Hints
var awards: Awards
var sky: SkyKit.SkyRig

var world: World
var fx: Fx
var trail_interval := 0.03
var fast := OS.has_environment("EB_FAST")
var benders := {}  ## slot -> Bender (every machine)
var cams := {}  ## slot -> CameraRig (local views)
var huds := {}  ## slot -> UiKit root (-1 = the shared view)
var hud_parts := {}  ## slot -> {hp, chi, spirit, wave, chips, hint}
var master: VrBender  ## host / local: the VR master bender
var avatar: VrRig.Avatar  ## TV machine: the VR player as seen from the TV
var avatar_glow: MeshInstance3D
var raiders := {}  ## id -> Raider (host: real; TV machine: ghosts)
var next_id := 0
var dummy: Dummy
var shared_cam: CameraRig
var join_prompt: Control
var results_ui: Control
var vr_results: Node
var end_menu: Node
var tv_banner: Control
var vr_banner: Node3D
var vr_headline: Node3D

# Host / local game state
var wave := 0
var phase_t := 0.0
var to_spawn := 0
var spawn_t := 0.0
var spirit := 0.0  ## the team's spirit meter, 0..100 (snapshot on the TV machine)
var score := 0
var kills := 0
var practice_i := 0
var practice_wait := 0.0
var send_t := 0.0
var _targets_frame := -1
var _targets_cache: Array = [[], []]
var _vr_floor := World.DAIS_TOP
var _last_note := {}

# Story + depth (host / local decide; every machine shows)
var temple_story: TempleStory
var temple_seed := 0
var temple_daily := false
var wave_plan := {}
var spawn_i := 0
var story_queue: Array = []
var story_t := 0.0
var vr_story: Node3D
var run_logged := false
var game_t := 0.0
var wave_t := 0.0
var wave_downs := 0
var generals := 0  # Shadow Generals beaten this game
var seen_elements := {}  # elements Kiko has introduced this game

# Bots / design checks
var log_practice := 0
var log_waves := 0
var log_boss := false
var log_boss_swaps := 0
var log_counters := 0
var log_ring_outs := 0
var log_specials := {}
var log_spirits := 0
var log_tv_shots := 0
var log_vr_shots := 0
var log_hits_by := {}
var log_downs := 0
var log_story := 0
var log_gates := 0
var log_runs := 0


## The practice dummy (visual on every machine; the host decides when it pops).
class Dummy extends Node3D:
	var element := 0
	var dummy_id := 0
	var hit_radius := 0.7
	var hit_height := 1.1
	var dead := false
	var aura: MeshInstance3D
	var orb: MeshInstance3D
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		if aura != null:
			aura.scale = Vector3.ONE * (1.0 + 0.12 * sin(t * 6.0))
			aura.rotation.y += delta * 1.5
		if orb != null:
			orb.position.y = 2.25 + sin(t * 4.0) * 0.08


func _ready() -> void:
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"  # RPCs resolve to /root/Main/Net on both machines
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	save = Save.new()
	save.game_id = GAME_ID
	# days: play-days (lanterns), last_day, daily: the date TODAY'S RAIDERS ran, waves: waves cleared over all days
	# (the Spirit Tree), fruit: the element of every General beaten (oldest first), generals: how many.
	save.defaults = {"best_wave": 0, "best_score": 0, "days": 0, "last_day": "", "daily": "", "games": 0, "waves": 0,
		"fruit": [], "generals": 0, "best_today": [], "raiders": 0}
	add_child(save)
	net.sticky_event("gates")  # a machine that joins later gets the coming wave's portals (core/net.gd)
	net.sticky_event("temple")  # ... and the Spirit Tree, lanterns and Kiko's crown
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("overworld")
	music.prepare(["battle", "boss", "defeat"])
	awards = Awards.new()
	awards.define("counter", "ELEMENT MASTER", "%s super hits", "counters")
	awards.define("ringout", "RING OUT!", "%s raiders sent into the sea", "ringouts")
	awards.define("spirit", "SPIRIT GUIDE", "%s Spirit States", "spirits")
	hints = Hints.new()
	add_child(hints)
	hints.bind_party(party)
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	var flat: bool = mode == "host" and not net.has_vr  # flat host (TV / Deck hosting): slot 0 is a pad player here
	var vr := VrRig.wanted(mode) and not flat
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(vr and VrRig.headset_available())
	fx = Fx.new()
	fx.name = "Fx"
	if vr:
		fx.setup(400)
		trail_interval = 0.05
	add_child(fx)
	sky = SkyKit.apply(self, "sunset", vr and VrRig.headset_available())
	temple_story = TempleStory.new()
	temple_story.name = "TempleStory"
	temple_story.main = self
	add_child(temple_story)
	if vr:
		vr_rig = VrRig.new()
		vr_rig.move_speed = 2.2
		vr_rig.turn_mode = "snap"
		vr_rig.move_filter = _vr_walk_filter
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, World.DAIS_TOP, 2.6), 0.0)
		master = VrBender.new()
		master.name = "Master"
		add_child(master)
		master.setup(self, vr_rig)
		hints.set_vr_rig(vr_rig, self)
	if mode != "host" or not vr:
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		shared_cam = CameraRig.new()
		shared_cam.camera = split.shared_camera()
		add_child(shared_cam)
		shared_cam.shot_look(Vector3(0.0, 22.0, 30.0), Vector3(0.0, 0.0, -2.0), 0.0, Vector3(0.0, 0.0, 0.0))
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if mode == "client":
			avatar = VrRig.Avatar.new()
			add_child(avatar)
			avatar_glow = MeshKit.instance(Looks.orb(0.08, 10), false)
			avatar.hands[1].add_child(avatar_glow)
			split.set_bubble(VrRig.build_mirror(self, avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode != "client" and vr_rig == null
	if vr_rig != null:
		awards.set_player(0, "MASTER")
	if mode != "client":
		net.state_set("vr", vr_rig != null)
		net.state_set("best", int(save.data["best_wave"]))
		_start_temple(true)
		_start_practice()
	hints.intro(INTRO, {"duration": 10.0})
	if vr_rig != null:
		hints.hint("vr_punch", "Touch an orb, then TRIGGER + PUNCH!", {"to": "vr"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Elemental Bender: %s mode%s" % [mode, " with a VR master" if vr_rig != null else ""])


## VR walking: stay on the island, slide round the pillars and the training platforms.
func _vr_walk_filter(_from: Vector3, to: Vector3) -> Vector3:
	var p := Vector2(to.x, to.z)
	if p.length() > World.ISLAND_R - 1.5:
		p = p.normalized() * (World.ISLAND_R - 1.5)
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var c := Vector2(cos(a), sin(a)) * World.PILLAR_R
		if p.distance_to(c) < 0.95:
			p = c + (p - c).normalized() * 0.95
		var a2 := i * TAU / 4.0
		var c2 := Vector2(cos(a2), sin(a2)) * 19.0
		if p.distance_to(c2) < 3.4:
			p = c2 + (p - c2).normalized() * 3.4
	return Vector3(p.x, to.y, p.y)


# --- Game flow (host / local) -------------------------------------------------------------------

func _set_phase(p: String) -> void:
	phase_t = 0.0
	net.state_set("phase", p)


func phase() -> String:
	return String(net.state_get("phase", ""))


func _start_practice() -> void:
	practice_i = 0
	practice_wait = 1.5
	_set_phase("practice")
	net.state_set("wave", 0)
	net.state_set("score", 0)


func _start_breather(after_wave: bool) -> void:
	_set_phase("breather")
	if after_wave:
		var bonus := wave * 250
		score += bonus
		net.state_set("score", score)
		announce("WAVE %d CLEARED!" % wave, "+%d" % bonus, "victory")
		for f in fighters(true):
			_heal(f, 25.0)
		_wave_cleared()
	else:
		announce("GET READY!", "Here they come...", "info")
	_send_gates(wave + 1)  # the next wave's portals open now, so everyone sees where the raiders will come from


func _start_wave() -> void:
	wave += 1
	log_waves = maxi(log_waves, wave)
	_set_phase("fight")
	net.state_set("wave", wave)
	var n := maxi(1, fighters(true).size())
	wave_plan = WaveGen.plan(temple_seed, wave, n, fast)
	_send_gates(wave)
	var spawns: Array = wave_plan.spawns
	spawn_i = 0
	to_spawn = spawns.size()
	spawn_t = float(spawns[0][3]) if not spawns.is_empty() else 0.0
	wave_t = 0.0
	wave_downs = 0
	if bool(wave_plan.boss):
		to_spawn -= 1
		spawn_i = 1
		_spawn_raider(spawns[0], true)
		spawn_t = float(spawns[1][3]) if spawns.size() > 1 else 0.0
		log_boss = true
		net.state_set("boss", true)
		announce("WAVE %d" % wave, "The Shadow General approaches!", "boss")
	else:
		net.state_set("boss", false)
		announce("WAVE %d" % wave, "", "default")
	_wave_story()
	sound_all("wave", Vector3.ZERO, 0.0, 1.0)
	if vr_rig != null and wave == 1:
		hints.hint("vr_slam", "Both hands UP, then SLAM down!", {"to": "vr"})


func _game_over() -> void:
	_set_phase("over")
	# The raiders melt back into the shadows (no more hits on the results screen).
	for id in raiders.keys():
		var r: Raider = raiders[id]
		if is_instance_valid(r):
			spawn_fx(r.global_position, r.boss)
			net.event("spawn", [r.global_position, r.boss])
			r.dead = true
			r.queue_free()
	raiders.clear()
	_targets_frame = -1
	announce("THE TEMPLE HAS FALLEN", "Wave %d" % wave, "defeat")
	_story_for_all("Oh no! Let's try again!", "kiko", Color(0.65, 0.65, 0.8))
	_log_run("over")
	if wave > int(save.data["best_wave"]):
		save.data["best_wave"] = wave
		save.mark_dirty()
		net.state_set("best", wave)
	if score > int(save.data["best_score"]):
		save.data["best_score"] = score
		save.mark_dirty()
	if temple_daily:
		var bt: Array = save.data.best_today
		if bt.size() < 2 or String(bt[0]) != Seeded.today() or int(bt[1]) < wave:
			save.data.best_today = [Seeded.today(), wave]
			save.mark_dirty()


func _show_results_now() -> void:
	var data := awards.results({"title": "WAVE %d" % wave, "style": "defeat",
		"subtitle": ("TODAY'S RAIDERS: %d defeated" if temple_daily else "%d raiders defeated") % kills,
		"stats": [["WAVE", str(wave)], ["RAIDERS", str(kills)], ["BEST WAVE", str(int(save.data["best_wave"]))]],
		"score_format": "%d PTS"})
	net.state_set("results", data)
	_set_phase("results")


## Play again (no practice the second time round).
func _restart() -> void:
	for id in raiders.keys():
		(raiders[id] as Node).queue_free()
	raiders.clear()
	for c in get_children():
		if c is Projectile:
			c.queue_free()
	_clear_dummy()
	wave = 0
	score = 0
	kills = 0
	spirit = 0.0
	awards.reset()
	for f in fighters(false):
		f.set("hp", float(f.get("max_hp")))
		f.set("dead", false)
		f.set("spirit_t", 0.0)
	net.state_set("score", 0)
	net.state_set("wave", 0)
	net.state_set("spirit_ready", false)
	_start_temple(false)
	_start_breather(false)


func _host_step(delta: float) -> void:
	phase_t += delta
	game_t += delta
	wave_t += delta
	for s in benders:
		var b: Bender = benders[s]
		b.auth_step(delta)
	var everyone := fighters(false)
	var alive := fighters(true)
	match phase():
		"practice":
			_practice_step(delta)
		"breather":
			if phase_t > (1.5 if fast else 4.0) and not alive.is_empty():
				_start_wave()
		"fight":
			if to_spawn > 0:
				spawn_t -= delta
				var spawns: Array = wave_plan.get("spawns", [])
				if spawn_t <= 0.0 and raiders.size() < MAX_ALIVE and spawn_i < spawns.size():
					_spawn_raider(spawns[spawn_i], false)
					spawn_i += 1
					to_spawn -= 1
					spawn_t = float(spawns[spawn_i][3]) if spawn_i < spawns.size() else 0.0
			elif raiders.is_empty():
				_start_breather(true)
			if not everyone.is_empty() and alive.is_empty():
				_game_over()
		"over":
			if phase_t > 3.0:
				_show_results_now()
		"results":
			if phase_t > 60.0:
				_restart()


# --- Practice -------------------------------------------------------------------------------

func _practice_step(delta: float) -> void:
	if dummy == null:
		practice_wait -= delta
		if practice_wait <= 0.0 and practice_i < PRACTICE.size():
			_make_dummy(practice_i + 1, PRACTICE[practice_i], DUMMY_AT + Vector3((practice_i % 2) * 4.0 - 2.0, 0.0, 0.0))
			var need: int = E.beater(PRACTICE[practice_i])
			if vr_rig != null:
				_vr_headline("USE %s" % E.NAMES[need], "", {"duration": 3.0, "color": E.COLORS[need], "sound": ""})
	if practice_i >= PRACTICE.size() and dummy == null:
		_start_breather(false)
	elif phase_t > (25.0 if fast else 80.0):
		_clear_dummy()
		practice_i = PRACTICE.size()


func _make_dummy(id: int, e: int, pos: Vector3) -> void:
	_clear_dummy()
	dummy = Dummy.new()
	dummy.dummy_id = id
	dummy.element = e
	dummy.add_to_group("eb_enemy")
	add_child(dummy)
	dummy.position = pos
	dummy.add_child(MeshKit.instance(Looks.dummy(), false))
	var need := E.beater(e)
	dummy.orb = MeshKit.instance(Looks.orb(0.16), false)
	dummy.orb.material_override = E.mat(E.COLORS[e], 5.0)
	dummy.add_child(dummy.orb)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.9
	torus.rings = 20
	torus.ring_segments = 6
	dummy.aura = MeshInstance3D.new()
	dummy.aura.mesh = torus
	dummy.aura.material_override = E.mat(E.COLORS[need], 4.0)
	dummy.aura.position = Vector3(0, 1.1, 0)
	dummy.aura.rotation.x = 0.3
	dummy.add_child(dummy.aura)
	fx.burst(pos + Vector3.UP, E.COLORS[need], 16, 3.0, 0.3, 0.5)
	sfx.play_at("pop", pos, -2.0, 1.0)


func _clear_dummy() -> void:
	_targets_frame = -1
	if dummy != null and is_instance_valid(dummy):
		dummy.queue_free()
	dummy = null


## Host: a practice dummy was hit with `e`.
func _practice_hit(e: int, slot: int) -> void:
	if dummy == null or dummy.dead:
		return
	var pos := dummy.global_position + Vector3.UP * 1.2
	if E.multiplier(e, dummy.element) > 1.0:
		dummy.dead = true
		log_practice += 1
		practice_i += 1
		practice_wait = 0.8
		awards.add(slot, "score", 50)
		pop_fx(pos, E.COLORS[e], true)
		net.event("pop", [pos, E.COLORS[e], true])
		_clear_dummy()
	else:
		var need := E.beater(dummy.element)
		pop_fx(pos, E.COLORS[need], false)
		net.event("pop", [pos, E.COLORS[need], false])
		_note(slot, "Use %s!" % E.NAMES[need])


## A dummy popping (good) or bonking (wrong element), on every machine.
func pop_fx(pos: Vector3, c: Color, good: bool) -> void:
	if good:
		fx.burst(pos, c, 30, 6.0, 0.35, 0.6)
		fx.ring(pos - Vector3.UP * 1.0, c, 4.0, 0.5)
		sfx.play_at("correct", pos, 0.0, 1.0)
		sfx.play_at("pop", pos, 0.0, 0.8)
		_popup(pos, "POP!", {"style": "score", "size": 1.4})
	else:
		fx.burst(pos, Color(0.7, 0.7, 0.7), 8, 2.0, 0.2, 0.3)
		sfx.play_at("boing", pos, -2.0, 1.0)
		var need := 0
		for i in 4:
			if E.COLORS[i].is_equal_approx(c):
				need = i
		_popup(pos, "TRY %s" % E.NAMES[need], {"style": "info", "color": c})


# --- Raiders (host / local) --------------------------------------------------------------------

## Host / local: one raider of the wave plan ([element, portal, ranged, gap, jitter x, jitter z]) steps out.
func _spawn_raider(item: Array, is_boss: bool) -> void:
	var n := int(wave_plan.get("players", maxi(1, fighters(true).size())))
	var r := Raider.new()
	r.game = self
	next_id += 1
	r.id = next_id
	r.element = int(item[0])
	r.boss = is_boss
	r.ranged = is_boss or bool(item[2])
	r.max_hp = WaveGen.raider_hp(wave, n, is_boss) * (0.5 if fast else 1.0)
	r.speed = WaveGen.raider_speed(wave, is_boss)
	r.damage = (18.0 + wave) if is_boss else (8.0 + wave * 0.8)
	if is_boss:
		r.swap_order = wave_plan.get("boss_order", [])
		if not r.swap_order.is_empty():
			r.element = int(r.swap_order[0])
	r.hp = r.max_hp
	var gl: Array = wave_plan.get("gates", [])
	var base: Vector3 = gl[clampi(int(item[1]), 0, gl.size() - 1)] if not gl.is_empty() else world.spawn_points.pick_random()
	r.position = base + Vector3(float(item[4]), 0.5, float(item[5]))
	add_child(r)
	raiders[r.id] = r
	spawn_fx(r.position, is_boss)
	net.event("spawn", [r.position, is_boss])


func spawn_fx(pos: Vector3, is_boss: bool) -> void:
	fx.burst(pos + Vector3.UP * 0.5, Color(0.35, 0.1, 0.5), 18 if is_boss else 12, 2.5, 0.4 * (2.0 if is_boss else 1.0), 0.6)
	sfx.play_at("warp" if is_boss else "teleport", pos, -6.0, 0.7)


## Raider callback: the nearest standing fighter (TV benders and the VR master).
func nearest_fighter(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for f in fighters(true):
		var n: Node3D = f
		var d := n.global_position.distance_squared_to(from)
		if d < bd:
			bd = d
			best = n
	return best


## Everyone who fights (benders + the VR master); alive_only skips the knocked-down ones.
func fighters(alive_only: bool) -> Array:
	var out: Array = []
	for s in benders:
		var b: Bender = benders[s]
		if not alive_only or not b.dead:
			out.append(b)
	if master != null and (not alive_only or not master.dead):
		out.append(master)
	return out


func fighter_of(slot: int) -> Node3D:
	if slot == 0 and master != null:
		return master
	return benders.get(slot)


## Projectile callback: what a shot of `team` can hit here (cached per physics frame).
func targets_for(team: int) -> Array:
	var f := Engine.get_physics_frames()
	if f != _targets_frame:
		_targets_frame = f
		var en: Array = []
		for id in raiders:
			var r: Raider = raiders[id]
			if is_instance_valid(r) and not r.dead:
				en.append(r)
		if dummy != null and is_instance_valid(dummy) and not dummy.dead:
			en.append(dummy)
		_targets_cache = [en, fighters(true)]
	return _targets_cache[clampi(team, 0, 1)]


## Steer `dir` towards the best target within the cone `min_dot` (the VR player's punches).
func aim_assist(from: Vector3, dir: Vector3, min_dot: float) -> Vector3:
	var best := dir
	var best_score := -INF
	for t in targets_for(0):
		if not is_instance_valid(t):
			continue
		var n: Node3D = t
		var to: Vector3 = n.global_position + Vector3.UP * float(n.get("hit_height")) - from
		var d := to.length()
		if d > 35.0 or d < 0.1:
			continue
		var dot := (to / d).dot(dir)
		var flat := Vector3(to.x, 0.0, to.z).normalized().dot(Vector3(dir.x, 0.0, dir.z).normalized())
		if dot < min_dot and flat < min_dot + 0.04:
			continue
		var sc := flat * 2.0 - d / 35.0
		if sc > best_score:
			best_score = sc
			best = to / d
	return best


func on_raider_hit(r: Raider, amount: float, mult: float, slot: int) -> void:
	var pos := r.global_position + Vector3.UP * (r.hit_height * 2.2)
	damage_fx(pos, amount, mult)
	net.event("dmg", [pos, roundi(amount), mult])
	add_spirit(1.5)
	if slot >= 0:
		awards.add(slot, "damage", amount)
		log_hits_by[slot] = int(log_hits_by.get(slot, 0)) + 1
		if mult > 1.0:
			awards.add(slot, "counters")
			log_counters += 1


func damage_fx(pos: Vector3, amount: float, mult: float) -> void:
	if mult > 1.0:
		_popup(pos, "%d!" % roundi(amount), {"style": "crit", "size": 1.3})
	elif mult < 1.0:
		_popup(pos, str(roundi(amount)), {"style": "miss", "size": 1.0})
	else:
		_popup(pos, str(roundi(amount)), {"style": "damage", "size": 1.2})
	sfx.play_at("hit", pos, -4.0, 1.4 if mult > 1.0 else 1.0)


## World popups follow the VR text rules (HudKit turns them to the VR camera on Y only, never
## billboarded, depth-tested); in VR we also skip any that would pop up right in front of the eyes.
func _popup(pos: Vector3, text: String, opts: Dictionary) -> void:
	if vr_rig != null and VrRig.headset_available() and pos.distance_to(vr_rig.head_position()) < 1.4:
		return
	HudKit.popup(self, pos, text, opts)


func on_raider_died(r: Raider, ring_out: bool) -> void:
	raiders.erase(r.id)
	_targets_frame = -1
	kills += 1
	var pts := 100 * (10 if r.boss else 1)
	if ring_out:
		pts += 50
		log_ring_outs += 1
	score += pts
	net.state_set("score", score)
	add_spirit(30.0 if r.boss else 8.0)
	var by := r.last_hit_slot
	if by >= 0:
		awards.add(by, "kills")
		awards.add(by, "score", pts)
		if ring_out:
			awards.add(by, "ringouts")
	var pos := r.global_position
	poof_fx(pos, ring_out, r.boss, pts)
	net.event("poof", [pos, ring_out, r.boss, pts])
	if r.boss:
		announce("THE GENERAL IS DEFEATED!", "", "victory")
		_general_beaten(r.element)
	elif save != null and net.mode != "client":
		save.data.raiders = int(save.data.raiders) + 1


func poof_fx(pos: Vector3, ring_out: bool, boss: bool, pts: int) -> void:
	var c := Color(0.3, 0.1, 0.4)
	fx.burst(pos + Vector3.UP, c, 30 if boss else 16, 4.0, 0.35 * (2.0 if boss else 1.0), 0.6)
	sfx.play_at("big_kill" if boss else "kill", pos, -2.0, 1.0)
	if ring_out:
		fx.burst(Vector3(pos.x, -0.9, pos.z), Color(0.6, 0.85, 1.0), 20, 5.0, 0.3, 0.7)
		sfx.play_at("splash", Vector3(pos.x, 0.0, pos.z), 0.0, 1.0)
		_popup(Vector3(pos.x, 1.5, pos.z), "RING OUT!", {"style": "score", "size": 1.6})
	else:
		_popup(pos + Vector3.UP * 2.6, "+%d" % pts, {"style": "score", "size": 1.0})


func on_boss_swap(r: Raider) -> void:
	log_boss_swaps += 1
	fx.ring(r.global_position, E.COLORS[r.element], 4.0, 0.5)
	net.event("swap", [r.global_position, r.element])
	swap_fx(r.global_position, r.element)


func swap_fx(pos: Vector3, e: int) -> void:
	sfx.play_at("magic", pos, -2.0, 0.7)
	for s in huds:
		if int(s) >= 0 and is_instance_valid(huds[s]):
			HudKit.toast(huds[s], "The General turns to %s!" % E.NAMES[e], {"color": E.COLORS[e]})


func raider_melee(r: Raider, target: Node3D, dmg: float, push: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		return
	hurt_fighter(target, dmg, push)
	sound_all("hit", r.global_position, -4.0, 0.7)


## Host / local: hurt a fighter (a raider's punch or shot, or the sea).
func hurt_fighter(f: Node3D, dmg: float, push: Vector3) -> void:
	var was_dead := bool(f.get("dead"))
	var taken: float = f.call("take_hit", dmg, push)
	if taken <= 0.0:
		return
	var slot := int(f.get("slot"))
	awards.add(slot, "damage_taken", taken)
	if f is Bender:
		var b: Bender = f
		if not b.owned:
			net.event("hurt", [slot, push])
		sfx.play_at("hurt", b.global_position, -4.0, 1.0)
	elif f == master:
		sfx.play("hurt", -6.0, 1.0)
	if not was_dead and bool(f.get("dead")):
		log_downs += 1
		wave_downs += 1
		_note(slot, "Down! Back in 6...")
		sound_all("down", f.global_position, -2.0, 1.0)


func _heal(f: Node3D, amount: float) -> void:
	var mx := float(f.get("max_hp"))
	var hp := float(f.get("hp"))
	if bool(f.get("dead")):
		return
	f.set("hp", minf(mx, hp + amount))
	var pos := f.global_position + Vector3.UP * 2.0
	if f != master:
		_popup(pos, "+%d" % int(amount), {"style": "heal"})
		net.event("heal", [pos, int(amount)])


func on_revived(slot: int) -> void:
	var p := World.temple_spot(slot)
	if slot == 0 and master != null:
		p = master.global_position
	fx.ring(p, Color(1.0, 0.95, 0.7), 3.0, 0.5)
	sound_all("revive", p, -2.0, 1.0)


func on_spirit_faded(slot: int) -> void:
	_note(slot, "Spirit State fades...")


func add_spirit(amount: float) -> void:
	for f in fighters(false):
		if float(f.get("spirit_t")) > 0.0:
			return  # no filling while someone is in Spirit State
	var was := spirit
	spirit = minf(spirit + amount, 100.0)
	if was < 100.0 and spirit >= 100.0:
		net.state_set("spirit_ready", true)


func team_spirit() -> float:
	return spirit


func team_spirit_full() -> bool:
	return spirit >= 100.0


# --- Attacks (every machine asks; the host / local decides) ------------------------------------

## A bender attacked: the shots fly now on this machine; the host makes the real ones.
func bender_fire(slot: int, shots: Array) -> void:
	if slot == 0 and master != null:
		log_vr_shots += shots.size()
	else:
		log_tv_shots += shots.size()
	if net.mode == "client":
		for p in shots:
			_spawn_shot(p, slot, false)
		net.request(slot, "fire", [shots])
	else:
		fire_shots(shots, slot)


## Host / local: real shots (they deal damage), copied to the TV machine as one event.
func fire_shots(shots: Array, slot: int) -> void:
	var packed: Array = []
	for p in shots:
		_spawn_shot(p, slot, true)
		packed.append(E.pack_shot(p))
	net.event("shots", [slot, packed])


func _spawn_shot(p: Dictionary, slot: int, real: bool) -> void:
	var pr := Projectile.new()
	pr.game = self
	pr.real = real
	pr.owner_slot = slot
	pr.configure(p)
	add_child(pr)


func projectile_hit(pr: Projectile, target: Node3D, push: Vector3) -> void:
	if pr.team == 0:
		if target is Dummy:
			_practice_hit(pr.element, pr.owner_slot)
		elif target is Raider:
			(target as Raider).take_hit(pr.damage, pr.element, push, pr.effect, pr.owner_slot)
	else:
		hurt_fighter(target, pr.damage, push)


func bender_special(slot: int, e: int, pos: Vector3) -> void:
	if net.mode == "client":
		special_fx(e, pos, true)
		net.request(slot, "special", [e, pos])
	else:
		_do_special(slot, e, pos)


## Host / local: a special's effect on the raiders (and the caster), then the show everywhere.
func _do_special(slot: int, e: int, here: Vector3) -> void:
	log_specials[e] = int(log_specials.get(e, 0)) + 1
	awards.add(slot, "spells")
	special_fx(e, here, false)
	net.event("special", [slot, e, here])
	match e:
		E.AIR:
			for r in _raiders_near(here, 9.0):
				var away := r.global_position - here
				away.y = 0.0
				r.take_hit(12.0, E.AIR, away.normalized() * 26.0, "", slot)
		E.WATER:
			var f := fighter_of(slot)
			if f != null:
				_heal(f, 30.0)
			for r in _raiders_near(here, 7.5):
				r.take_hit(10.0, E.WATER, Vector3.ZERO, "freeze", slot)
		E.EARTH:
			for r in _raiders_near(here, 9.0):
				var away := r.global_position - here
				away.y = 0.0
				r.take_hit(24.0, E.EARTH, away.normalized() * 6.0, "stun", slot)
		E.FIRE:
			fire_shots(E.nova_shots(here), slot)


## The look and sound of a special (every machine). `local_nova`: the TV machine draws its own
## bender's Fire Nova (the host's copies of its own shots are skipped there).
func special_fx(e: int, here: Vector3, local_nova: bool) -> void:
	sfx.play_at("magic", here, 0.0, 1.0)
	match e:
		E.AIR:
			fx.ring(here, Color(1, 1, 1), 9.0, 0.5)
			sfx.play_at("whoosh", here, 0.0, 0.7)
		E.WATER:
			fx.ring(here, E.COLORS[E.WATER], 7.5, 0.6)
			for i in 20:
				var v := Vector3(randf_range(-1, 1), randf_range(1, 3), randf_range(-1, 1)) * 2.0
				fx.puff(here + Vector3.UP, Color(0.4, 1.0, 0.7), 0.2, 0.7, v)
			sfx.play_at("heal", here, 0.0, 1.0)
			sfx.play_at("ice", here, -4.0, 1.0)
		E.EARTH:
			fx.spikes(here, 9.0)
			sfx.play_at("crash", here, 0.0, 0.6)
			for s in cams:
				var c: CameraRig = cams[s]
				var b: Node3D = benders.get(s)
				if b != null and b.global_position.distance_to(here) < 14.0:
					c.shake(0.6)
		E.FIRE:
			sfx.play_at("explosion", here, -2.0, 1.2)
			if local_nova:
				for p in E.nova_shots(here):
					_spawn_shot(p, -1, false)
	_popup(here + Vector3.UP * 2.6, E.SPECIALS[e], {"style": "info", "color": E.COLORS[e], "size": 1.3})


func _raiders_near(p: Vector3, r: float) -> Array[Raider]:
	var out: Array[Raider] = []
	for id in raiders:
		var rd: Raider = raiders[id]
		if is_instance_valid(rd) and not rd.dead and rd.global_position.distance_to(p) < r:
			out.append(rd)
	return out


func bender_spirit(slot: int) -> void:
	if spirit < 100.0:
		_note(slot, "Spirit meter not full yet")
		return
	net.request(slot, "spirit", [])


func _do_spirit(slot: int) -> void:
	var f := fighter_of(slot)
	if f == null or spirit < 100.0 or bool(f.get("dead")):
		return
	spirit = 0.0
	net.state_set("spirit_ready", false)
	log_spirits += 1
	awards.add(slot, "spirits")
	f.set("spirit_t", E.SPIRIT_TIME)
	_heal(f, 40.0)
	var here := f.global_position
	for r in _raiders_near(here, 12.0):
		var away := r.global_position - here
		away.y = 0.0
		r.take_hit(20.0, -1, away.normalized() * 20.0, "stun", slot)
	spirit_fx(slot, here)
	net.event("spirit", [slot, here])


func spirit_fx(slot: int, here: Vector3) -> void:
	fx.ring(here, Color(0.8, 0.95, 1.0), 12.0, 0.8)
	sfx.play_at("power_up", here, 0.0, 1.0)
	sfx.play_at("sparkle", here, 0.0, 1.0)
	var who := "THE MASTER" if slot == 0 and bool(net.state_get("vr", false)) else party.name_of(slot)
	_banner_local("SPIRIT STATE!", who, "level")
	if cams.has(slot):
		(cams[slot] as CameraRig).shake(0.9)


func bender_elem(slot: int, e: int) -> void:
	if net.mode == "client":
		net.request(slot, "elem", [e])


func bender_dash(slot: int) -> void:
	if net.mode == "client":
		net.request(slot, "dash", [])


func bender_splash(slot: int) -> void:
	sfx.play_at("splash", World.temple_spot(slot), 0.0, 1.0)
	_note(slot, "Splash! Back to the temple.")
	net.request(slot, "splash", [])


func vr_element_changed(_e: int) -> void:
	pass


## The VR player feels a shake as a buzz (never move the VR camera).
func vr_shake(amount: float) -> void:
	if vr_rig != null:
		vr_rig.pulse(VrRig.LEFT, clampf(amount, 0.1, 1.0), 0.1)


## Host / local: a player asked for something (net.request from any machine lands here).
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"fire":
			if phase() in ["practice", "breather", "fight"]:
				var shots: Array = args[0]
				fire_shots(shots, slot)
		"special":
			_do_special(slot, int(args[0]), args[1])
		"spirit":
			_do_spirit(slot)
		"elem":
			var b: Bender = benders.get(slot)
			if b != null:
				b.element = int(args[0])
		"dash":
			var b2: Bender = benders.get(slot)
			if b2 != null:
				b2.invuln_t = maxf(b2.invuln_t, 0.3)
		"splash":
			var f := fighter_of(slot)
			if f != null and not bool(f.get("dead")):
				f.set("invuln_t", 0.0)
				hurt_fighter(f, 10.0, Vector3.ZERO)
		"again":
			if phase() == "results":
				_restart()
		"arcade":
			net.go_to_arcade()


# --- Players ----------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	sfx.play("ui_notify", -6.0)
	awards.set_player(slot, party.name_of(slot))


## Benders for every TV seat (not slot 0 when a VR master plays).
func _sync_benders() -> void:
	var vr_on := bool(net.state_get("vr", false))
	var want := {}
	for s in party.active_slots():
		if s == 0 and vr_on:
			continue
		want[s] = true
		if not benders.has(s):
			_add_bender(s)
	for s in benders.keys():
		if not want.has(s):
			_remove_bender(int(s))


func _add_bender(s: int) -> void:
	var b := Bender.new()
	b.game = self
	b.party = party
	b.slot = s
	b.owned = party.is_local(s)
	b.auth = net.mode != "client"
	b.band = party.color_of(s)
	b.show_name = not (vr_rig != null and VrRig.headset_available())
	b.name = "Bender%d" % s
	b.position = World.temple_spot(s)
	add_child(b)
	benders[s] = b
	if net.mode != "client":
		awards.set_player(s, party.name_of(s))
	if b.owned and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(s)
		c.party = party
		c.slot = s
		c.pivot_height = 1.7
		c.pitch = -0.25
		c.yaw = 0.0
		add_child(c)
		c.follow(b, 6.5, 0.0)
		cams[s] = c
		b.cam = c
		_make_hud(s, split.hud(s))
		hints.add_view(huds[s], s)
		hints.hint("counter", "Hit raiders with the element that beats their orb!", {"to": s, "icon": "star"})


func _remove_bender(s: int) -> void:
	if benders.has(s):
		(benders[s] as Node).queue_free()
		benders.erase(s)
	if cams.has(s):
		(cams[s] as Node).queue_free()
		cams.erase(s)
	if huds.has(s):
		var h: Control = huds[s]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(s)
	hud_parts.erase(s)
	hints.remove_view(s)


## Host: a TV machine's bender moved (core/net.gd calls this).
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	var b: Bender = benders.get(slot)
	if b != null and not b.owned:
		b.set_remote(pos, yaw)


# --- Main loop ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_sync_benders()
	var playing := phase() != "results" and phase() != "over"
	for s in benders:
		var b: Bender = benders[s]
		b.can_act = playing
	if master != null:
		master.can_act = playing
		master.step(delta)
		_vr_floor = lerpf(_vr_floor, World.ground_y(vr_rig.head_position()), 1.0 - exp(-8.0 * delta))
		vr_rig.floor_height = _vr_floor
	if net.mode != "client":
		_host_step(delta)
	else:
		_send_states(delta)
	world.animate(delta)
	temple_story.update_kiko(delta, _kiko_looks_at())
	_update_story(delta)
	# A pause undone from elsewhere (bots, the arcade) must not leave the PAUSED card up.
	if tv_banner != null and tv_banner.visible and not get_tree().paused:
		tv_banner.visible = false
	if split != null:
		_update_huds()
		if shared_cam != null and split.showing_shared():
			shared_cam.shot_look(Vector3(sin(Time.get_ticks_msec() * 0.00005) * 30.0, 22.0, cos(Time.get_ticks_msec() * 0.00005) * 30.0),
				Vector3(0.0, 0.0, -2.0), 0.0)


func _send_states(delta: float) -> void:
	send_t -= delta
	if send_t > 0.0:
		return
	send_t = 1.0 / 30.0
	for s in benders:
		var b: Bender = benders[s]
		if b.owned:
			net.send_state(b.global_position, b.visual_yaw(), 0.0, int(s))


func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)


## A sound here and on the TV machine.
func sound_all(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	net.event("sfx", [n, p, db, pitch])


# --- Text: banners, notes, HUD ------------------------------------------------------------------

## Host / local: a big banner on every TV view and a short headline in VR, here and on the TV machine.
func announce(title: String, sub: String, style: String) -> void:
	_banner_local(title, sub, style)
	net.event("banner", [title, sub, style])


func _banner_local(title: String, sub: String, style: String) -> void:
	var roots := _all_huds()
	if not roots.is_empty():
		HudKit.banner(roots, title, sub, {"style": style, "duration": 2.2})
	if vr_rig != null:
		_vr_headline(title, "", {"duration": 2.2, "style": style, "sound": ""})
	match style:
		"boss":
			music.play_mood("boss", 0.8)
		"defeat":
			music.play_mood("defeat")


## One VR headline at a time (a new one replaces the last, so cards never overlap).
func _vr_headline(title: String, sub: String, opts: Dictionary) -> void:
	if vr_headline != null and is_instance_valid(vr_headline):
		vr_headline.call("hide_card")
	vr_headline = HudKit.vr_banner(self, vr_rig.camera, title, sub, opts)


## A one-line note for one player (their own view, or a short card in VR).
func _note(slot: int, text: String) -> void:
	var now := Time.get_ticks_msec()
	var key := "%d:%s" % [slot, text]
	if now - int(_last_note.get(key, -10000)) < 1500:
		return
	_last_note[key] = now
	if slot == 0 and master != null:
		vr_note(text)
	elif huds.has(slot) and is_instance_valid(huds[slot]):
		HudKit.toast(huds[slot], text, {"duration": 1.6})
	elif net.mode == "host":
		net.event("note", [slot, text])


func tv_note(slot: int, text: String) -> void:
	_note(slot, text)


func vr_note(text: String) -> void:
	if vr_rig != null:
		HudKit.vr_toast(self, vr_rig.camera, text, {"duration": 1.5})


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]) and (int(k) >= 0 or split == null or split.showing_shared()):
			out.append(huds[k])
	return out


func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var parts := {}
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join the fight!"]]))
		ui.add_child(join_prompt)
		_anchor(join_prompt, 0.5, 1.0)
		join_prompt.offset_top = -70.0
		join_prompt.offset_bottom = -70.0
		hud_parts[slot] = parts
		return
	# Top left: who, health, chi.
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(20.0, 18.0)
	var v := UiKit.vbox()
	card.add_child(v)
	var row := UiKit.hbox()
	v.add_child(row)
	row.add_child(UiKit.badge(party.name_of(slot), slot))
	var hp := UiKit.bar("hp", 260, 22)
	row.add_child(hp)
	var chi := UiKit.bar("mp", 260, 14)
	v.add_child(chi)
	parts["hp"] = hp
	parts["chi"] = chi
	# Top centre: wave and score, and the team's spirit meter under it.
	var sp := UiKit.vbox()
	ui.add_child(sp)
	_anchor(sp, 0.5, 0.0)
	sp.offset_top = 14.0
	sp.offset_bottom = 14.0
	var pill := UiKit.panel("pill")
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sp.add_child(pill)
	var wl := UiKit.label("WAVE 0", "heading", "gold", HORIZONTAL_ALIGNMENT_CENTER)
	pill.add_child(wl)
	parts["wave"] = wl
	var sbar := UiKit.bar("xp", 300, 16, Color(1.0, 0.85, 0.3))
	sbar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sp.add_child(sbar)
	var sl := UiKit.label("", "small", "gold", HORIZONTAL_ALIGNMENT_CENTER)
	sp.add_child(sl)
	parts["spirit"] = sbar
	parts["spirit_l"] = sl
	# Bottom centre: the four elements (current one big) and a one-line hint.
	var bottom := UiKit.vbox()
	ui.add_child(bottom)
	_anchor(bottom, 0.5, 1.0)
	bottom.offset_top = -20.0
	bottom.offset_bottom = -20.0
	var hint := UiKit.label("", "body", "text", HORIZONTAL_ALIGNMENT_CENTER)
	bottom.add_child(hint)
	parts["hint"] = hint
	var chips := UiKit.hbox()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(chips)
	var chip_list: Array = []
	for i in 4:
		var c := UiKit.tinted_panel(E.COLORS[i].darkened(0.45))
		var l := UiKit.label(E.NAMES[i], "heading", E.COLORS[i].lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER)
		c.add_child(l)
		chips.add_child(c)
		chip_list.append(c)
	parts["chips"] = chip_list
	hud_parts[slot] = parts


## Pin a control to a point of its parent (0 / 0.5 / 1 on each axis), growing away from the edge.
## (Set the anchors directly: set_anchors_preset() after add_child left these controls at the
## parent's top-left corner inside UiKit roots.)
func _anchor(c: Control, x: float, y: float) -> void:
	c.anchor_left = x
	c.anchor_right = x
	c.anchor_top = y
	c.anchor_bottom = y
	var gh := Control.GROW_DIRECTION_END if x < 0.25 else (Control.GROW_DIRECTION_BEGIN if x > 0.75 else Control.GROW_DIRECTION_BOTH)
	var gv := Control.GROW_DIRECTION_END if y < 0.25 else (Control.GROW_DIRECTION_BEGIN if y > 0.75 else Control.GROW_DIRECTION_BOTH)
	c.grow_horizontal = gh
	c.grow_vertical = gv


func _update_huds() -> void:
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty() and phase() != "results"
	var ph := phase()
	for s in hud_parts:
		var slot := int(s)
		if slot < 0:
			continue
		var parts: Dictionary = hud_parts[s]
		var b: Bender = benders.get(slot)
		if b == null:
			continue
		(parts["hp"] as UiKit.Bar).set_value(b.hp, b.max_hp)
		(parts["chi"] as UiKit.Bar).set_value(b.chi, Bender.MAX_CHI)
		var sbar: UiKit.Bar = parts["spirit"]
		var sl: Label = parts["spirit_l"]
		var mine := b.spirit_t > 0.0
		if mine:
			sbar.set_value(b.spirit_t, E.SPIRIT_TIME)
			sl.text = "SPIRIT STATE  %d" % ceili(b.spirit_t)
		else:
			sbar.set_value(spirit, 100.0)
			sl.text = "SPIRIT READY!  CLICK A STICK" if spirit >= 100.0 else "SPIRIT"
		(parts["wave"] as Label).text = "WAVE %d    %d" % [int(net.state_get("wave", 0)), int(net.state_get("score", 0))]
		var chips: Array = parts["chips"]
		for i in 4:
			var c: Control = chips[i]
			c.modulate.a = 1.0 if i == b.element else 0.45
		var hint: Label = parts["hint"]
		if b.dead:
			hint.text = "Down! Back in a moment..."
			hint.modulate = Color(1, 0.6, 0.6)
		elif ph == "practice" and dummy != null:
			var need := E.beater(dummy.element)
			hint.text = "Hit the dummy with %s!   (LB / RB)" % E.NAMES[need]
			hint.modulate = E.COLORS[need].lightened(0.3)
		else:
			hint.text = "%s beats %s" % [E.NAMES[b.element], E.NAMES[E.BEATS[b.element]]]
			hint.modulate = E.COLORS[b.element].lightened(0.3)


## Every machine: a replicated value changed.
func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"phase":
			match String(value):
				"fight":
					if not bool(net.state_get("boss", false)):
						music.play_mood("battle", 0.8)
				"practice":
					music.play_mood("overworld", 0.8)
				"results":
					_show_results(net.state_get("results", {}))
			if String(value) != "results":
				_hide_results()
		"spirit_ready":
			if bool(value):
				for s in huds:
					if int(s) >= 0 and is_instance_valid(huds[s]):
						HudKit.toast(huds[s], "SPIRIT READY! Click a stick", {"color": "gold", "icon": "star"})
				if vr_rig != null:
					_vr_headline("SPIRIT READY!", "PRESS A", {"duration": 2.5, "style": "level", "sound": ""})
				sfx.play("achievement", -4.0)


# --- Results and the end menu ------------------------------------------------------------------

func _show_results(data: Dictionary) -> void:
	_hide_results()
	if data.is_empty():
		return
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(huds[-1], data, {"party": party, "min_time": 3.0})
		screen.continued.connect(_open_end_menu_tv)
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig, "min_time": 3.0})
		card.continued.connect(_open_end_menu_vr)
		vr_results = card


func _open_end_menu_tv() -> void:
	var seats := party.local_slots()
	var slot := seats[0] if not seats.is_empty() else -1
	var m := UiMenu.open(huds[-1], {"title": "AGAIN?", "party": party, "slot": slot,
		"items": [{"id": "again", "text": "PLAY AGAIN", "icon": "play"}, {"id": "arcade", "text": "ARCADE", "icon": "flag"}]})
	m.chosen.connect(func(id: String, _item: Dictionary) -> void: net.request(maxi(slot, 1), id, []))
	end_menu = m


func _open_end_menu_vr() -> void:
	var vm := VrMenu.open(self, {"title": "AGAIN?", "rig": vr_rig,
		"items": [{"id": "again", "text": "PLAY AGAIN"}, {"id": "arcade", "text": "ARCADE"}]})
	vm.chosen.connect(func(id: String, _item: Dictionary) -> void: net.request(0, id, []))
	end_menu = vm


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
	vr_results = null
	if end_menu != null and is_instance_valid(end_menu):
		end_menu.call("close")
	end_menu = null
	if split != null:
		split.set_shared(false)


## True while the results / end menu are up (bots).
func results_showing() -> bool:
	return phase() == "results"


## Bots: pick an end-menu item as if a player chose it.
func choose_end(id: String) -> void:
	var seats := party.local_slots()
	net.request(seats[0] if not seats.is_empty() else 0, id, [])


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "Paused by %s" % ("THE MASTER" if by_slot == 0 and vr_rig != null else Who.seat(self, by_slot))
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", "wrist MENU: carry on", {"width": 1.1})
			vr_banner.process_mode = Node.PROCESS_MODE_ALWAYS
		elif vr_banner != null and is_instance_valid(vr_banner):
			vr_banner.call("hide_card")
	if split != null:
		if tv_banner == null:
			var ui := UiKit.ui_root(self, 6)
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
			tv_banner = UiKit.panel("accent")
			ui.add_child(tv_banner)
			var v := UiKit.vbox()
			tv_banner.add_child(v)
			v.add_child(UiKit.title("PAUSED"))
			var l := UiKit.label("", "small", "dim", HORIZONTAL_ALIGNMENT_CENTER)
			l.name = "Why"
			v.add_child(l)
			_anchor(tv_banner, 0.5, 0.5)
		(tv_banner.find_child("Why", true, false) as Label).text = why
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


# --- Networking --------------------------------------------------------------------------------

## Host, 30 Hz: [vr pose, raiders, fighters, team]. Raiders: 8 floats each (id, x, y, z, yaw,
## element, flags, hp fraction); fighters: 10 floats (slot, hp, element, spirit_t, dead, down_t, x, y, z, yaw:
## other machines' benders are drawn from these);
## team: spirit, VR element, dummy id, dummy element, dummy x, z. About 14 * 32 + 7 * 24 bytes.
func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var rd := PackedFloat32Array()
	for id in raiders:
		var r: Raider = raiders[id]
		if not is_instance_valid(r):
			continue
		var p := r.global_position
		rd.append_array([float(r.id), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
			snappedf(r.visual_yaw(), 0.02), float(r.element), float(r.pack_flags()), snappedf(maxf(r.hp / r.max_hp, 0.0), 0.01)])
	var fd := PackedFloat32Array()
	for f in fighters(false):
		var n: Node3D = f
		var fp := n.global_position
		var fy: float = (n as Bender).visual_yaw() if n is Bender else 0.0
		fd.append_array([float(n.get("slot")), roundf(float(n.get("hp"))), float(n.get("element")),
			snappedf(float(n.get("spirit_t")), 0.1), 1.0 if bool(n.get("dead")) else 0.0, 0.0,
			snappedf(fp.x, 0.01), snappedf(fp.y, 0.01), snappedf(fp.z, 0.01), snappedf(fy, 0.02)])
	var team := PackedFloat32Array([roundf(spirit), float(master.element) if master != null else -1.0,
		float(dummy.dummy_id) if dummy != null else 0.0, float(dummy.element) if dummy != null else 0.0,
		dummy.position.x if dummy != null else 0.0, dummy.position.z if dummy != null else 0.0,
		1.0 if master != null and master.spirit_t > 0.0 else 0.0])
	return [pose, rd, fd, team]


## TV machine: mirror the host's world.
func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 4:
		return
	var team: PackedFloat32Array = s[3]
	if avatar != null:
		avatar.apply_pose(s[0])
		if split != null and (s[0] as PackedFloat32Array).is_empty():
			split.clear_bubble()  # a flat host: no VR player to show in the bubble
		var ve := int(team[1])
		avatar_glow.visible = ve >= 0
		if ve >= 0:
			avatar_glow.material_override = E.mat(E.COLORS[ve] if team[6] < 0.5 else Color(1, 1, 1), 3.0)
	spirit = team[0]
	# Raiders: ghosts glide to the host's spots.
	var rd: PackedFloat32Array = s[1]
	var seen := {}
	var i := 0
	while i + 7 < rd.size():
		var id := int(rd[i])
		seen[id] = true
		var pos := Vector3(rd[i + 1], rd[i + 2], rd[i + 3])
		var r: Raider = raiders.get(id)
		if r == null or not is_instance_valid(r):
			r = Raider.new()
			r.game = self
			r.ghost = true
			r.id = id
			r.element = int(rd[i + 5])
			r.boss = int(rd[i + 6]) & 1 != 0
			r.position = pos
			add_child(r)
			raiders[id] = r
		r.apply_remote(pos, rd[i + 4], int(rd[i + 5]), int(rd[i + 6]), rd[i + 7])
		i += 8
	for id in raiders.keys():
		if not seen.has(id):
			(raiders[id] as Node).queue_free()
			raiders.erase(id)
	# Every bender's health and Spirit State come from the host; other machines' benders also their
	# spot, facing and element (many machines: they are puppets here).
	var fd: PackedFloat32Array = s[2]
	var j := 0
	while j + 9 < fd.size():
		var b: Bender = benders.get(int(fd[j]))
		if b != null:
			b.hp = fd[j + 1]
			b.spirit_t = fd[j + 3]
			b.dead = fd[j + 4] > 0.5
			if not b.owned:
				b.element = int(fd[j + 2])
				b.set_remote(Vector3(fd[j + 6], fd[j + 7], fd[j + 8]), fd[j + 9])
		j += 10
	# The practice dummy.
	var did := int(team[2])
	if did == 0:
		_clear_dummy()
	elif dummy == null or dummy.dummy_id != did:
		_make_dummy(did, int(team[3]), Vector3(team[4], 0.0, team[5]))


## TV machine: one-off events from the host.
func apply_event(kind: String, args: Array) -> void:
	match kind:
		"shots":
			var slot := int(args[0])
			if slot >= 0 and party.is_local(slot):
				return  # we drew our own already
			for a in args[1]:
				_spawn_shot(E.unpack_shot(a), slot, false)
		"dmg":
			damage_fx(args[0], float(args[1]), float(args[2]))
		"poof":
			poof_fx(args[0], bool(args[1]), bool(args[2]), int(args[3]))
		"spawn":
			spawn_fx(args[0], bool(args[1]))
		"special":
			if not party.is_local(int(args[0])):
				special_fx(int(args[1]), args[2], false)
		"spirit":
			spirit_fx(int(args[0]), args[1])
		"swap":
			fx.ring(args[0], E.COLORS[int(args[1])], 4.0, 0.5)
			swap_fx(args[0], int(args[1]))
		"pop":
			pop_fx(args[0], args[1], bool(args[2]))
		"hurt":
			var b: Bender = benders.get(int(args[0]))
			if b != null and b.owned:
				b.feel_hit(args[1])
				sfx.play_at("hurt", b.global_position, -4.0, 1.0)
		"heal":
			_popup(args[0], "+%d" % int(args[1]), {"style": "heal"})
		"banner":
			_banner_local(String(args[0]), String(args[1]), String(args[2]))
		"note":
			_note(int(args[0]), String(args[1]))
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"story":
			_story(String(args[0]), String(args[1]), args[2])
		"gates":
			_show_gates(int(args[0]), int(args[1]))
		"temple":
			_show_temple(args)


func on_client_joined() -> void:
	print("Elemental Bender: a TV machine joined (wave %d)" % wave)


func on_client_left() -> void:
	print("Elemental Bender: the last TV machine left")


## Host: one machine went away (core/party.gd frees its seats; _sync_benders drops their benders).
func on_machine_left(peer: int) -> void:
	print("Elemental Bender: machine %d left" % peer)


func _exit_tree() -> void:
	_log_run("quit")


# --- Kiko's story, the seeded waves and the Spirit Tree --------------------------------------------

## Host / local, once per game (first: at the start, else PLAY AGAIN): count the play-day (a new lantern), pick the
## temple seed (TODAY'S RAIDERS first each day), grow the tree to its saved size and say hello.
func _start_temple(first: bool) -> void:
	var today := Seeded.today()
	var new_day := String(save.data.last_day) != today
	if new_day:
		save.data.days = int(save.data.days) + 1
		save.data.last_day = today
	save.data.games = int(save.data.games) + 1
	temple_daily = String(save.data.daily) != today
	temple_seed = WaveGen.daily_seed() if temple_daily else Seeded.fresh_seed()
	if OS.has_environment("EB_SEED"):
		temple_seed = int(OS.get_environment("EB_SEED"))
	if temple_daily:
		save.data.daily = today  # (one TODAY'S RAIDERS a day)
	save.mark_dirty()
	run_logged = false
	game_t = 0.0
	generals = 0
	seen_elements = {}
	_send_temple()
	print("Elemental Bender: temple seed %d%s | tree %d waves, %d fruit, day %d" % [temple_seed,
		" (TODAY'S RAIDERS)" if temple_daily else "", int(save.data.waves), (save.data.fruit as Array).size(), int(save.data.days)])
	if first:
		story_t = 3.0  # after the title
		if not Engine.has_meta("eb_said_hi"):
			Engine.set_meta("eb_said_hi", true)  # (once per session)
			_story_for_all("Hi! I'm Kiko! Save my temple!", "kiko", KIKO_COLOR)
		if new_day and int(save.data.days) > 1:
			_story_for_all("A new lantern!", "lantern", Color(1.0, 0.8, 0.35))
	if temple_daily:
		_story_for_all("TODAY'S RAIDERS!", "portal", Color(0.75, 0.5, 1.0))


## Host / local: the portals of wave n open on every machine (sticky: late machines get them too).
func _send_gates(n: int) -> void:
	_show_gates(temple_seed, n)
	if net.mode == "host":
		net.event("gates", [temple_seed, n])


func _show_gates(seed_value: int, n: int) -> void:
	log_gates += 1
	temple_story.set_gates(WaveGen.gates(seed_value, n) if n > 0 else [])


## Host / local: the Spirit Tree, lanterns and Kiko's crown on every machine (sticky).
func _send_temple() -> void:
	var d := [int(save.data.waves), (save.data.fruit as Array).duplicate(), int(save.data.days),
		int(save.data.generals) >= WaveGen.CROWN_GENERALS]
	_show_temple(d)
	if net.mode == "host":
		net.event("temple", d)


func _show_temple(d: Array) -> void:
	if d.size() >= 4:
		temple_story.set_keepsakes(int(d[0]), d[1], int(d[2]), bool(d[3]))


## A glowing burst where the tree grew or a fruit appeared (every machine, from temple_story.gd).
func tree_burst(pos: Vector3) -> void:
	fx.burst(pos, Color(1.0, 0.85, 0.4), 26, 4.0, 0.3, 0.8)
	sfx.play_at("sparkle", pos, -2.0, 1.0)


## Host / local: a wave is cleared: the Spirit Tree grows (saved), a RUN line.
func _wave_cleared() -> void:
	var before := WaveGen.tree_stage(int(save.data.waves))
	save.data.waves = int(save.data.waves) + 1
	save.mark_dirty()
	var after := WaveGen.tree_stage(int(save.data.waves))
	_send_temple()
	if after > before:
		_story_for_all("The Spirit Tree grew!", "spirittree", Color(1.0, 0.7, 0.85))
	elif wave <= 2:
		_story_for_all("You did it!", "kiko", Color(1.0, 0.85, 0.3))
	_log_run("wave")


## Host / local: a Shadow General is beaten: a glowing fruit on the Spirit Tree (saved), Kiko's crown at last.
func _general_beaten(e: int) -> void:
	generals += 1
	var k := int(save.data.generals) + 1
	save.data.generals = k
	var fruit: Array = save.data.fruit
	fruit.append(e)
	while fruit.size() > WaveGen.FRUIT_MAX:
		fruit.pop_front()
	save.data.fruit = fruit
	save.mark_dirty()
	_send_temple()
	_story_for_all("A glowing fruit!", "lightfruit", E.COLORS[e])
	if k == WaveGen.CROWN_GENERALS:
		_story_for_all("A crown for me!", "crown", Color(1.0, 0.85, 0.25))


## Host / local: Kiko's card for the wave that starts: the element that beats this wave's raiders while there is
## only one, a new element the first time it comes, the General.
func _wave_story() -> void:
	var pal: Array = wave_plan.get("palette", [])
	if bool(wave_plan.get("boss", false)):
		_story_for_all("The Shadow General!", "general", Color(0.75, 0.5, 1.0))
	elif pal.size() == 1:
		var e := int(pal[0])
		var need := E.beater(e)
		_story_for_all("%s raiders! Use %s!" % [E.NAMES[e], E.NAMES[need]], Pics.ELEMENT_PICS[need], E.COLORS[need])
	else:
		for e in pal:
			if not seen_elements.has(int(e)):
				var need2 := E.beater(int(e))
				_story_for_all("%s raiders! Use %s!" % [E.NAMES[int(e)], E.NAMES[need2]], Pics.ELEMENT_PICS[need2], E.COLORS[need2])
				break
	for e in pal:
		seen_elements[int(e)] = true


## Where Kiko looks: the VR master's head, else the nearest bender, else the front.
func _kiko_looks_at() -> Vector3:
	if vr_rig != null:
		return vr_rig.head_position()
	var best := Vector3(0.0, 0.0, -10.0)
	var bd := INF
	for s in benders:
		var b: Bender = benders[s]
		var d := b.global_position.length_squared()
		if d < bd:
			bd = d
			best = b.global_position
	return best


## Host / local: a story card on every machine.
func _story_for_all(line: String, pic: String, color: Color) -> void:
	_story(line, pic, color)
	if net != null and net.mode == "host":
		net.event("story", [line, pic, color])


func _story(line: String, pic: String, color: Color) -> void:
	if story_queue.size() < 5:
		story_queue.append([line, pic, color])


## One card at a time, on every view this machine shows (and in front of the VR master).
func _update_story(delta: float) -> void:
	story_t -= delta
	if story_t > 0.0 or story_queue.is_empty():
		return
	var b: Array = story_queue.pop_front()
	story_t = 3.0
	log_story += 1
	var opts := {"who": KIKO, "line": b[0], "pic": b[1], "color": b[2], "duration": 2.8}
	var roots := _all_huds()
	if not roots.is_empty():
		StoryCard.show(roots, opts)
	if vr_rig != null:
		if vr_story != null and is_instance_valid(vr_story):
			vr_story.queue_free()
		vr_story = StoryCard.show_vr(self, vr_rig.camera, opts)
	temple_story.cheer()  # Kiko bounces as she talks
	print("Story: %s (%s)" % [b[0], b[1]])


## One RUN line per wave cleared ("wave"), at game over ("over") and on quit (core/telemetry.gd).
func _log_run(end: String) -> void:
	if net == null or net.mode == "client" or wave <= 0 or run_logged or save == null:
		return
	run_logged = end != "wave"
	log_runs += 1
	Telemetry.run(GAME_ID, {"end": end, "wave": wave, "seed": temple_seed, "daily": temple_daily,
		"secs": snappedf(game_t, 0.1), "wave_secs": snappedf(wave_t, 0.1), "score": score, "kills": kills,
		"players": fighters(false).size(), "downs": wave_downs, "downs_game": log_downs, "vr": vr_rig != null,
		"flat": net.mode == "host" and vr_rig == null, "net": net.mode, "fast": fast,
		"portals": (wave_plan.get("gates", []) as Array).size(), "elements": wave_plan.get("palette", []),
		"generals": generals, "tree": WaveGen.tree_stage(int(save.data.waves)), "waves_total": int(save.data.waves),
		"fruit": (save.data.fruit as Array).size(), "days": int(save.data.days), "counters": log_counters,
		"spirits": log_spirits, "ring_outs": log_ring_outs})
