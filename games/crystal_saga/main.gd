extends Node3D
## CRYSTAL SAGA: a short, magical Final-Fantasy-style journey. The VR player IS the hero.
## - The VR hero (slot 0, host) walks a path north through five places, at full size under a big sky:
##   Willowbrook village -> the forest -> the crystal cave -> the Stone Giant's glade -> the shrine of
##   the Crystal of Light. A beam of dim purple light rises from the broken crystal: you can see where
##   you're going from everywhere. Restore it at the end: the shards spin together, the beam turns gold,
##   the sky brightens, everyone cheers.
## - Fights are real time and physical: swing the SWORD (right hand) through cute monsters and they
##   poof into sparkles; RAISE YOUR LEFT HAND above your head and a fireball flies at the nearest one.
##   In the cave a golden orb gives THUNDER: the sword glows, raise it to the sky and lightning strikes
##   every monster near you. No menus, numbers or game over: a bump is just a sparkly "boing".
## - TV players (slots 1..6, or 0 too in local play without a headset) are the hero's PARTY, seen
##   from above and behind: little mages and archers. Left stick walks, A shoots a magic spark or an
##   arrow at the nearest monster in front (or pokes the thing in front of them).
## - The Stone Giant is big and grumpy in a cloud of dark mist; he stomps (a glowing ring grows on the
##   ground first). Every hit shrinks the mist; when it's gone he's friendly and waves.
## - PRACTICE in the village: a ghost hand swings a sword through the glowing training dummy, then
##   raises the hand to send a fireball at a glowing target; the TV heroes shoot a glowing stone.
## - Everything in reach does something (world.gd): the well, chickens, flowers, signposts, houses,
##   trees, mushrooms, crystals that chime, chests, villagers who wave and point north.
## - Text: VR gets one short headline ahead of the hero; the TV one short line at most.
## Modes as in games/engine_template: local (one shared TV view), host (VR on the Steam Frame,
## simulates everything), client (the TV machine: mirrors the host, moves its own heroes).
## CS_ZONE=n starts in zone n (0..4) for tests.

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Save := preload("res://core/save.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const World := preload("res://games/crystal_saga/world.gd")
const Monsters := preload("res://games/crystal_saga/monsters.gd")
const Hero := preload("res://games/crystal_saga/hero.gd")
const VrHands := preload("res://games/crystal_saga/vr_hands.gd")
const GhostHand := preload("res://games/crystal_saga/ghost_hand.gd")

const GAME_ID := "crystal_saga"
const NAMES: Array[String] = ["WILLOWBROOK", "WHISPER WOOD", "CRYSTAL CAVE", "STONE GIANT!", "THE CRYSTAL!"]
const MOODS: Array[String] = ["town", "overworld", "dungeon", "boss", "cosy"]
const SKIES: Array[String] = ["dawn", "day", "dungeon", "sunset", "sunset"]
const SHOT_RANGE := {"magic": 11.0, "arrow": 13.0, "slash": 3.2}
const SHOT_COLOR := {"magic": Color(0.75, 0.5, 1.0), "arrow": Color(1.0, 0.9, 0.5), "slash": Color(0.6, 0.9, 1.0),
	"fire": Color(1.0, 0.5, 0.15)}

# --- The networking contract ---
var net: Node
var ready_to_play := false
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var awards: Awards
var sky: SkyKit.SkyRig

var world: World
var monsters: Monsters
var heroes := {}  ## slot -> Hero (every machine)
var hands: VrHands
var ghost: GhostHand
var avatar: VrRig.Avatar
var arrow: Node3D  ## glowing arrow on the ground towards the open barrier
var beam: MeshInstance3D  ## the crystal's beam of light (dim purple -> gold)
var beam_mat: StandardMaterial3D
var blink_mat: StandardMaterial3D

# Host
var phase_t := 0.0
var open_t := -1.0
var straggle_t := -1.0
var send_t := 0.0
var knock_cd := 0.0
var wave := 0
var wave_at := {}  ## villager prop id -> when they last waved by themselves
var shots: Array = []  ## pending hits: {"t", "mon", "prop", "slot", "at"}
var poke_cd := {}  ## prop id -> seconds
var log_hits := {}  ## bots: slot -> monster hits
var log_pokes := {}  ## bots: prop kind -> pokes
var log_zones := {}
var log_dizzy := 0
var log_knocks := 0
var log_stomps := 0

# TV
var hud: Control
var gem_row: HBoxContainer
var pill: Control
var pill_text := ""
var shot_once := {}  ## slot -> true once they pressed A (the "A Shoot!" pill goes away)
var results_ui: Control
var tv_banner: Control
var cam_pos := Vector3(0.0, 9.0, 14.0)
var shake := 0.0

# VR
var headline: Label3D
var headline_t := 0.0


func _ready() -> void:
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = {"restored": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
	music.prepare(["overworld", "dungeon", "boss", "victory"])
	awards = Awards.new()
	awards.define("hero", "HERO OF LIGHT", "%s monsters poofed", "poofs")
	awards.define("chimer", "CRYSTAL CHIMER", "%s crystals chimed", "chimes")
	awards.define("pal", "CHICKEN PAL", "%s chicken hops", "chickens")
	awards.define("finder", "TREASURE FINDER", "%s chests opened", "chests")
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build()
	monsters = Monsters.new()
	monsters.name = "Monsters"
	add_child(monsters)
	_build_beam()
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		vr_rig.move_speed = 2.0
		vr_rig.turn_mode = "snap"
		vr_rig.move_filter = func(from: Vector3, to: Vector3) -> Vector3: return world.walk_clamp(from, to, 0.25)
		add_child(vr_rig)
		vr_rig.place(World.entrance(0), 0.0)
		hands = VrHands.new()
		add_child(hands)
		hands.setup(self, vr_rig)
		ghost = GhostHand.new()
		add_child(ghost)
		_build_blink()
	sky = SkyKit.apply(self, SKIES[0], vr_rig != null)
	_build_arrow()
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		split.set_shared(true)
		split.shared_camera().fov = 55.0
		_make_hud(split.shared_hud())
		if mode == "client":
			avatar = VrRig.Avatar.new()
			add_child(avatar)
			avatar.hands[1].add_child(MeshKit.instance(VrHands.sword_mesh(), false))
			var fl := MeshKit.instance(VrHands.flame_mesh(), false)
			fl.position = Vector3(0.0, 0.07, 0.02)
			avatar.hands[0].add_child(fl)
			split.set_bubble(VrRig.build_mirror(self, avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	if mode != "client":
		net.state_set("vr", vr_rig != null)
		_start_journey()
	else:
		world.set_open(int(net.state_get("open", 0)))
		world.set_used(int(net.state_get("used", 0)))
		_apply_zone_look(int(net.state_get("zone", 0)))
		if bool(net.state_get("restored", false)):
			world.restored = 1.0
			_beam_look(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Crystal Saga: %s mode%s" % [mode, " with a VR hero" if vr_rig != null else ""])


# --- The journey (host / local) ------------------------------------------------------------------

func _start_journey() -> void:
	awards.reset()
	if vr_rig != null:
		awards.set_player(0, "HERO")
	for s in heroes:
		awards.set_player(int(s), party.name_of(int(s)))
	monsters.clear()
	shots.clear()
	if hands != null:
		hands.reset()
	var first := 0
	if OS.has_environment("CS_ZONE") and not has_meta("started"):
		first = clampi(int(OS.get_environment("CS_ZONE")), 0, World.ZONES - 1)
	set_meta("started", true)
	var used := 0
	if first > 0:
		used |= (1 << world.dummy_id) | (1 << world.target_id) | (1 << world.stone_id)
	if first > 2:
		used |= 1 << world.orb_id
	if first > 3:
		used |= 1 << world.friend_id
	net.state_set("used", used)
	net.state_set("open", first)
	net.state_set("thunder", first > 2)
	net.state_set("restored", false)
	net.state_set("step", 0)
	world.restored = 0.0
	_beam_look(0.0)
	var at := World.entrance(first)
	if vr_rig != null:
		if has_meta("shown"):
			blink(func() -> void: vr_rig.place(at, 0.0))
		else:
			vr_rig.place(at, 0.0)
	set_meta("shown", true)
	for s in heroes:
		_warp_hero(int(s), at)
	_enter_zone(first)
	if first == 0:
		show_headline("CRYSTAL SAGA", 4.0)


func _enter_zone(z: int) -> void:
	log_zones[z] = true
	net.state_set("zone", z)
	net.state_set("spawn", World.entrance(z))
	straggle_t = 3.5 if z > 0 else -1.0
	phase_t = 0.0
	wave = 0
	match z:
		0:
			net.state_set("phase", "practice")
		1, 2:
			_spawn_wave(z, 0)
			net.state_set("phase", "fight")
		3:
			monsters.giant_hits = clampi(16 + 2 * heroes.size(), 16, 28)
			monsters.spawn(Monsters.GIANT, World.center(z) + Vector3(0.0, 0.0, -3.5))
			net.state_set("phase", "boss")
		_:
			net.state_set("phase", "crystal")


## Two waves of monsters in the forest and in the cave (more friends, more monsters).
func _spawn_wave(z: int, w: int) -> void:
	var c := World.center(z)
	var n := heroes.size() + (1 if vr_rig != null else 0)
	var at: Array = []
	if z == 1:
		for i in clampi(2 + n, 3, 7):
			var kind := Monsters.MUSHY if (i + w) % 3 == 2 else Monsters.SLIME
			var p := c + Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-5.5, -1.0) if w == 0 else randf_range(-6.0, 3.0))
			monsters.spawn(kind, p)
			at.append(p)
	else:
		for i in clampi(2 + n / 2, 3, 5):
			var p2 := c + Vector3(randf_range(-2.5, 2.5), 1.9, randf_range(-3.0, 2.0))
			monsters.spawn(Monsters.BAT, p2)
			at.append(p2)
		for i in 1 + w:
			var p3 := c + Vector3(randf_range(-3.0, 3.0), 0.0, -4.5 + w * 3.0)
			monsters.spawn(Monsters.SLIME, p3)
			at.append(p3)
	if w > 0:
		for p4 in at:
			sparkle_all((p4 as Vector3) + Vector3(0.0, 0.4, 0.0), Color(0.8, 0.6, 1.0), 14)
		sound_at("whoosh", c, -2.0, 0.6)
		sound_at("pop", c, -4.0, 0.7)
		show_headline("MORE!", 2.0)


func _zone_cleared() -> void:
	var z := int(net.state_get("zone", 0))
	net.state_set("phase", "cleared")
	open_t = 1.2
	var p := Vector3(0.0, 1.5, World.wall_z(z))
	sound_at("fanfare", p, -4.0)
	sound_at("sparkle", p, -2.0)
	for k in 3:
		sparkle_all(p + Vector3(-3.0 + k * 3.0, 0.0, 0.3), Color(1.0, 0.9, 0.5), 30)
	_pulse_both(0.5, 0.15)


func _restore() -> void:
	net.state_set("phase", "restore")
	net.state_set("restored", true)
	net.state_set("used", int(net.state_get("used", 0)) | (1 << world.big_id))
	phase_t = 0.0
	var p := world.prop_center(world.big_id)
	sound_at("power_up", p, 0.0)
	sound_at("sparkle", p, 0.0)
	_pulse_both(0.8, 0.4)
	save.data["restored"] = int(save.data["restored"]) + 1
	save.mark_dirty()


func _yay() -> void:
	net.state_set("phase", "yay")
	phase_t = 0.0
	var p := world.prop_center(world.big_id)
	for k in 4:
		sparkle_all(p + Vector3(0.0, k * 0.8, 0.0), Color(1.0, 0.9, 0.4), 60)
	sound_at("fanfare", p, 0.0)
	sound_at("cheer", p, -2.0)
	sound_at("applause", p, -6.0)
	for s in heroes:
		net.event("cheer", [int(s)])
		(heroes[s] as Hero).anim.play("cheer", 2.0)


func _results() -> void:
	var data := awards.results({"title": "LIGHT RESTORED!", "style": "victory", "score_stat": "poofs",
		"score_format": "%d POOFS", "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


# --- Host rules ----------------------------------------------------------------------------------

func _host_step(delta: float) -> void:
	var phase := String(net.state_get("phase", ""))
	var zone := int(net.state_get("zone", 0))
	phase_t += delta
	knock_cd = maxf(0.0, knock_cd - delta)
	for k in poke_cd.keys():
		poke_cd[k] = float(poke_cd[k]) - delta
		if float(poke_cd[k]) <= 0.0:
			poke_cd.erase(k)
	if hands != null:
		hands.update(delta, bool(net.state_get("thunder", false)))
		_ghost(delta, phase)
	_step_shots(delta)
	_villagers_wave()
	# Monsters chase the party; bumps make heroes dizzy and give the VR hero a sparkly boing.
	var targets: Array = []
	for s in heroes:
		var h: Hero = heroes[s]
		if h.dizzy_t <= 0.0 and h.safe_t <= 0.0:
			targets.append([h.position, int(s)])
	if vr_rig != null:
		var hp := vr_rig.head_position()
		targets.append([Vector3(hp.x, 0.0, hp.z), -1])
	for b in monsters.step(delta, targets):
		var key: int = b[1]
		if key < 0:
			_knock_vr()
		elif heroes.has(key) and (heroes[key] as Hero).dizzy_t <= 0.0:
			log_dizzy += 1
			(heroes[key] as Hero).get_dizzy()
			net.event("dizzy", [key])
			sound_at("boing", (heroes[key] as Hero).position, -2.0, 0.8)
	for w in monsters.windups:
		sound_at("buff", w, 0.0, 0.6)
	for st in monsters.stomps:
		log_stomps += 1
		stomp_fx(st)
		net.event("stomp", [st])
		sound_at("crash", st, -2.0, 0.6)
		sound_at("land", st, 0.0, 0.5)
	match phase:
		"practice":
			var hero_ok := vr_rig == null or world.is_used(world.target_id)
			var party_ok := heroes.is_empty() or world.is_used(world.stone_id)
			if vr_rig != null and int(net.state_get("step", 0)) == 0 and world.is_used(world.dummy_id):
				net.state_set("step", 1)
				show_headline("HAND UP!", 8.0)
			if hero_ok and party_ok and (vr_rig != null or not heroes.is_empty()) and phase_t > 1.0:
				_zone_cleared()
		"fight":
			if monsters.count() == 0 and phase_t > 0.5 and wave == 0:
				wave = 1
				phase_t = 0.0
				_spawn_wave(zone, 1)
			elif monsters.count() == 0 and phase_t > 0.5:
				if zone == 2 and not _thunder_learned():
					net.state_set("phase", "orb")
					phase_t = 0.0
				else:
					_zone_cleared()
		"orb":
			if _thunder_learned() or (world.is_used(world.orb_id) and phase_t > 25.0):
				_zone_cleared()
		"boss":
			if monsters.count() == 0 and phase_t > 0.5:
				_zone_cleared()
		"cleared":
			if open_t > 0.0:
				open_t -= delta
				if open_t <= 0.0:
					net.state_set("open", zone + 1)
					sound_at("door", Vector3(0.0, 1.0, World.wall_z(zone)), 0.0)
					sound_at("whoosh", Vector3(0.0, 1.0, World.wall_z(zone)), -4.0, 0.7)
			elif int(net.state_get("open", 0)) > zone:
				for p in _player_feet():
					if (p as Vector3).z < World.wall_z(zone) - 0.8:
						_enter_zone(zone + 1)
						break
		"restore":
			if phase_t > 4.5:
				_yay()
		"yay":
			if phase_t > 5.0:
				_results()
		"results":
			if phase_t > 90.0:
				_start_journey()
	if straggle_t > 0.0:
		straggle_t -= delta
		if straggle_t <= 0.0:
			var at := World.entrance(zone)
			for s in heroes:
				if World.zone_of((heroes[s] as Hero).position) < zone:
					_warp_hero(int(s), at)
			if vr_rig != null and World.zone_of(vr_rig.head_position()) < zone:
				blink(func() -> void: vr_rig.place(at, 0.0))


## Villagers wave and point north by themselves when someone walks up to them.
func _villagers_wave() -> void:
	if int(net.state_get("zone", 0)) != 0:
		return
	for id in world.props.size():
		if int(world.props[id]["kind"]) != World.VILLAGER or poke_cd.has(id) or float(wave_at.get(id, -99.0)) > Time.get_ticks_msec() * 0.001 - 12.0:
			continue
		var c := world.prop_center(id)
		for p in _player_feet():
			var pp: Vector3 = p
			if Vector2(pp.x - c.x, pp.z - c.z).length() < 2.2:
				wave_at[id] = Time.get_ticks_msec() * 0.001
				poke_cd[id] = 2.0
				_react(id)
				sound_at("bell", c, -10.0, 1.6)
				break


func _thunder_learned() -> bool:
	if not world.is_used(world.orb_id):
		return false
	return vr_rig == null or hands.thunders > 0


func _player_feet() -> Array:
	var out: Array = []
	for s in heroes:
		out.append((heroes[s] as Hero).position)
	if vr_rig != null:
		out.append(vr_rig.head_position())
	return out


func _ghost(delta: float, phase: String) -> void:
	var mode := ""
	var target := Vector3.ZERO
	if phase == "practice" and phase_t > 1.0:
		if not world.is_used(world.dummy_id):
			mode = "swing"
			target = world.prop_center(world.dummy_id)
		elif not world.is_used(world.target_id):
			mode = "fire"
	elif phase == "orb" and world.is_used(world.orb_id) and hands.thunders == 0:
		mode = "thunder"
	elif phase in ["fight", "boss"] and hands.idle_t > 25.0 and monsters.count() > 0:
		var best := INF
		for id in monsters.mons:
			var c: Vector3 = monsters.center_of(id)
			var d := c.distance_to(vr_rig.head_position())
			if d < best:
				best = d
				target = c
		mode = "swing" if best < 4.0 else ""
	ghost.show_demo(mode, target, vr_rig.head_position(), vr_rig.head_yaw(), delta)


## Host: a monster was hit (slot 0 = the VR hero / a local knight, 1+ = a TV hero).
func hit_monster(id: int, slot: int, at: Vector3) -> bool:
	if not monsters.mons.has(id):
		return false
	var kind: int = monsters.mons[id]["kind"]
	var res := monsters.hit(id)
	if res == "":
		return false
	log_hits[slot] = int(log_hits.get(slot, 0)) + 1
	if res == "poof":
		awards.add(slot, "poofs")
		if kind == Monsters.GIANT:
			_giant_friendly(at)
		else:
			sparkle_all(at, Color(0.7, 1.0, 0.8), 30)
			sound_at("pop", at, 0.0, randf_range(0.9, 1.15))
			sound_at("sparkle", at, -6.0)
	else:
		sound_at("sword_hit", at, -4.0, 0.8)
		sound_at("boing", at, -6.0, 0.6)
		sparkle_all(at, Color(0.7, 0.4, 1.0), 14)
	return true


func _giant_friendly(at: Vector3) -> void:
	net.state_set("used", int(net.state_get("used", 0)) | (1 << world.friend_id))
	for k in 3:
		sparkle_all(at + Vector3(0.0, k * 0.8, 0.0), Color(0.8, 0.5, 1.0), 50)
	sparkle_all(world.prop_center(world.friend_id), Color(1.0, 0.9, 0.5), 40)
	sound_at("party_horn", at, -2.0)
	sound_at("cheer", at, -4.0)
	_react(world.friend_id)
	show_headline("FRIENDS!", 3.0)
	shake = 0.8
	net.event("shake", [0.8])


## Host: someone poked a prop (sword, glove, or a TV hero). Returns true if something happened.
func prop_poke(id: int, slot: int) -> bool:
	var p: Dictionary = world.props[id]
	var kind: int = p["kind"]
	var c := world.prop_center(id)
	var phase := String(net.state_get("phase", ""))
	if kind == World.BIG:
		if phase == "crystal":
			_restore()
			return true
		if phase == "results" and phase_t > 3.0:
			on_request(slot, "again", [])
			return true
		return false
	if poke_cd.has(id) or (world.is_used(id) and kind in [World.CHEST, World.DUMMY, World.STONE, World.TARGET]):
		return false
	if kind == World.FRIEND and not world.is_used(id):
		return false
	poke_cd[id] = 0.6
	log_pokes[kind] = int(log_pokes.get(kind, 0)) + 1
	match kind:
		World.WELL:
			sound_at("splash", c, -2.0)
			sparkle_all(c + Vector3(0.0, 0.2, 0.0), Color(0.5, 0.75, 1.0), 26)
		World.CHICKEN:
			poke_cd[id] = 1.0
			sound_at("honk", c, -6.0, 1.8)
			sound_at("whoosh", c, -10.0, 1.6)
			awards.add(slot, "chickens")
		World.FLOWER:
			sound_at("sparkle", c, -4.0, 1.3)
			sound_at("pop", c, -10.0, 1.5)
			sparkle_all(c, Color(1.0, 0.6, 0.8), 22)
		World.SIGN:
			sound_at("whoosh", c, -4.0, 1.4)
			sound_at("tick", c, -8.0)
		World.HOUSE:
			sound_at("tock", c, -2.0, 0.8)
			sound_at("boing", c, -12.0, 0.7)
		World.TREE:
			sound_at("whoosh", c, -4.0, 0.7)
			sparkle_all(c + Vector3(0.0, 1.0, 0.0), Color(0.5, 0.85, 0.35), 18)
		World.MUSHROOM:
			sound_at("boing", c, -2.0, 1.0)
		World.CRYSTAL:
			poke_cd[id] = 0.4
			var notes: Array[float] = [1.0, 1.122, 1.26, 1.335, 1.498, 1.682, 1.888, 2.0]
			sound_at("ding", c, -2.0, notes[id % notes.size()])
			sound_at("sparkle", c, -10.0, 1.4)
			sparkle_all(c, Color(0.6, 0.9, 1.0), 12)
			awards.add(slot, "chimes")
		World.CHEST:
			net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
			sparkle_all(c + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.85, 0.2), 44)
			sound_at("chest", c, -2.0)
			sound_at("coin", c, -4.0)
			awards.add(slot, "chests")
		World.VILLAGER:
			poke_cd[id] = 2.0
			sound_at("bell", c, -8.0, 1.4)
			sound_at("sparkle", c + Vector3(0.0, 1.0, 0.0), -10.0)
		World.FRIEND:
			poke_cd[id] = 1.5
			sound_at("boing", c, -2.0, 0.5)
			sound_at("cheer", c, -10.0)
		World.DUMMY:
			sound_at("sword_hit", c, -4.0)
			sound_at("boing", c, -6.0, 1.2)
			if slot == 0 and vr_rig != null:
				_practice_done(id, c)
		World.STONE:
			sound_at("tock", c, -2.0, 1.3)
			_practice_done(id, c)
		World.TARGET:
			sound_at("fire", c, -2.0)
			_practice_done(id, c)
		World.ORB:
			if world.is_used(id):
				sound_at("ding", c, -4.0, 2.0)
			else:
				net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
				net.state_set("thunder", true)
				sparkle_all(c, Color(1.0, 0.95, 0.4), 60)
				sound_at("power_up", c, 0.0)
				sound_at("bell", c, -4.0)
				show_headline("THUNDER!", 3.0)
				if sky != null:
					sky.flash(0.6)
				net.event("flash", [0.6])
	_react(id)
	return true


func _practice_done(id: int, c: Vector3) -> void:
	net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
	sparkle_all(c, Color(1.0, 0.85, 0.3), 36)
	sound_at("ding", c, -2.0, 1.2)
	sound_at("sparkle", c, -4.0)
	if id != world.stone_id:
		show_headline("YES!", 2.0)


func _react(id: int) -> void:
	world.react(id)
	net.event("prop", [id])


func _knock_vr() -> void:
	if knock_cd > 0.0:
		return
	knock_cd = 2.5
	log_knocks += 1
	var hp := vr_rig.head_position()
	var fwd := vr_rig.head_forward()
	sparkle_all(hp + fwd * 0.6 - Vector3(0.0, 0.2, 0.0), Color(1.0, 0.9, 0.5), 30)
	sound_at("boing", hp, 0.0, 0.7)
	sound_at("sparkle", hp, -4.0)
	_pulse_both(0.8, 0.2)
	if blink_mat != null:
		blink_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.0)
		var tw := create_tween()
		tw.tween_property(blink_mat, "albedo_color:a", 0.45, 0.12)
		tw.tween_property(blink_mat, "albedo_color:a", 0.0, 0.6)
		tw.tween_callback(func() -> void: blink_mat.albedo_color = Color(0, 0, 0, 0))


# --- Spells and shots (host) ---------------------------------------------------------------------

## Host: the VR hero raised the left hand. A fireball flies at the nearest thing in front.
func cast_fire(from: Vector3) -> void:
	awards.add(0, "spells")
	var fwd := vr_rig.head_forward()
	var head := vr_rig.head_position()
	var aim := _aim(head, fwd, 14.0, 0.85, [world.target_id, world.orb_id, world.big_id])
	var to: Vector3 = aim[1]
	if int(aim[0]) < 0 and int(aim[2]) < 0:
		to = head + fwd * 8.0 + Vector3(0.0, -0.3, 0.0)
	sound_at("fire", from, -2.0, 1.1)
	sound_at("whoosh", from, -6.0, 1.2)
	_launch(from, to, "fire", 0, int(aim[0]), int(aim[2]))


## Host: the VR hero raised the glowing sword. Lightning strikes every monster near.
func cast_thunder(tip: Vector3) -> void:
	awards.add(0, "spells")
	var head := vr_rig.head_position()
	var pts: Array = [tip]
	for id in monsters.mons.keys():
		var c: Vector3 = monsters.center_of(id)
		if Vector2(c.x - head.x, c.z - head.z).length() < 7.5:
			pts.append(c)
			hit_monster(int(id), 0, c)
	if pts.size() == 1:
		pts.append(head + vr_rig.head_forward() * 3.0 + Vector3(0.0, -1.4, 0.0))
	thunder_fx(pts)
	net.event("thunder", [pts])
	if sky != null:
		sky.flash(0.8)
	net.event("flash", [0.8])
	sound_at("zap", tip, 0.0, 0.7)
	sound_at("crash", tip, -6.0, 1.4)
	shake = 0.5


## The best thing to shoot at from `from` along `fwd`: [monster id, point, prop id] (ids -1 if none).
## prop_ids: things that count as targets too (practice targets, the orb, the crystal).
func _aim(from: Vector3, fwd: Vector3, reach: float, min_dot: float, prop_ids: Array) -> Array:
	var best := INF
	var out: Array = [-1, from + fwd * reach, -1]
	for id in monsters.mons:
		var c: Vector3 = monsters.center_of(id)
		var d := Vector3(c.x - from.x, 0.0, c.z - from.z)
		var dist := d.length()
		if dist > reach + monsters.radius_of(id):
			continue
		var dot := d.normalized().dot(fwd) if dist > 0.01 else 1.0
		if dot < min_dot and dist > 1.2:
			continue
		var score := dist * (2.0 - dot)
		if score < best:
			best = score
			out = [int(id), c, -1]
	if int(out[0]) >= 0:
		return out
	for pid in prop_ids:
		if world.is_used(pid) and pid != world.orb_id:
			continue
		var pc := world.prop_center(pid)
		var d2 := Vector3(pc.x - from.x, 0.0, pc.z - from.z)
		if d2.length() < reach and d2.normalized().dot(fwd) > min_dot - 0.1 and d2.length() < best:
			best = d2.length()
			out = [-1, pc, pid]
	return out


func _launch(from: Vector3, to: Vector3, kind: String, slot: int, mon: int, prop: int) -> void:
	var t := clampf(from.distance_to(to) / 16.0, 0.12, 0.6)
	bolt_fx(from, to, kind, t)
	net.event("bolt", [from, to, kind, t])
	shots.append({"t": t, "mon": mon, "prop": prop, "slot": slot, "at": to, "kind": kind})


func _step_shots(delta: float) -> void:
	var keep: Array = []
	for s in shots:
		var d: Dictionary = s
		d["t"] = float(d["t"]) - delta
		if float(d["t"]) > 0.0:
			keep.append(d)
			continue
		var mon: int = d["mon"]
		var at: Vector3 = d["at"]
		var hit := false
		if mon >= 0 and monsters.mons.has(mon):
			hit = hit_monster(mon, int(d["slot"]), monsters.center_of(mon))
		elif int(d["prop"]) >= 0:
			hit = prop_poke(int(d["prop"]), int(d["slot"]))
		if not hit:
			sparkle_all(at, SHOT_COLOR.get(String(d["kind"]), Color.WHITE), 10)
			sound_at("pop", at, -12.0, 1.5)
	shots = keep


## Host / local: a player asked for something (from any machine).
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"shoot":
			if args.size() >= 2:
				_shoot(slot, args[0], float(args[1]))
		"again":
			if String(net.state_get("phase", "")) == "results":
				_start_journey()


## Host: a TV hero pressed A: poke the thing right in front, else shoot at the nearest monster.
func _shoot(slot: int, pos: Vector3, yaw: float) -> void:
	net.event("shoot", [slot])
	if heroes.has(slot) and not party.is_local(slot):
		(heroes[slot] as Hero).bonk_anim()
	awards.add(slot, "hits")
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var kind := Hero.shot_of(slot)
	var from := pos + Vector3(0.0, 0.8, 0.0) + fwd * 0.4
	var aim := _aim(pos, fwd, float(SHOT_RANGE[kind]), 0.55, [world.stone_id, world.orb_id, world.big_id])
	if int(aim[0]) < 0 and int(aim[2]) < 0:
		# Nothing to shoot: poke what's right in front (a chest, a chicken, the well...).
		var at := pos + fwd * 0.7
		var zone := World.zone_of(pos)
		var best := -1
		var bd := INF
		for id in world.props.size():
			var p: Dictionary = world.props[id]
			if absi(int(p["zone"]) - zone) > 1 or int(p["kind"]) in World.SPELL_ONLY:
				continue
			var c := world.prop_center(id)
			var dd := Vector2(c.x - at.x, c.z - at.z).length()
			if c.y < 2.4 and dd < float(p["r"]) + 0.6 and dd < bd:
				bd = dd
				best = id
		if best >= 0 and prop_poke(best, slot):
			return
	sound_at("bow" if kind == "arrow" else ("magic" if kind == "magic" else "sword"), from, -6.0, randf_range(1.0, 1.2))
	_launch(from, aim[1], kind, slot, int(aim[0]), int(aim[2]))


func _warp_hero(slot: int, at: Vector3) -> void:
	var p := at + _spawn_offset(slot)
	if party.is_local(slot) and heroes.has(slot):
		(heroes[slot] as Hero).position = p
	net.event("warp", [slot, p])
	sparkle_all(p + Vector3(0, 0.5, 0), party.color_of(slot), 16)


static func _spawn_offset(slot: int) -> Vector3:
	var xs: Array[float] = [0.0, -1.4, 1.4, -2.4, 2.4, -3.3, 3.3]
	return Vector3(xs[slot % xs.size()], 0.0, 0.9 if slot % 2 == 0 else 0.5)


func _pulse_both(a: float, d: float) -> void:
	if vr_rig != null:
		vr_rig.pulse(VrRig.RIGHT, a, d)
		vr_rig.pulse(VrRig.LEFT, a, d)


# --- Every machine -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_sync_heroes()
	_step_owned(delta)
	if net.mode != "client":
		_host_step(delta)
	for h in heroes.values():
		(h as Hero).animate(delta)
	monsters.animate(delta)
	world.animate(delta, int(net.state_get("zone", 0)))
	_animate_arrow()
	_headline(delta)
	if beam_mat != null:
		beam.rotation.y += delta * 0.3
	if split != null:
		_tv_camera(delta)
		_update_pill()


## Heroes for every TV seat (not slot 0 when a VR hero plays).
func _sync_heroes() -> void:
	var vr_on := bool(net.state_get("vr", false))
	var want := {}
	for s in party.active_slots():
		if s == 0 and vr_on:
			continue
		want[s] = true
		if not heroes.has(s):
			var h := Hero.new()
			h.owned = party.is_local(s)
			add_child(h)
			h.setup(s, party.color_of(s))
			var sp: Vector3 = net.state_get("spawn", World.entrance(0))
			h.position = sp + _spawn_offset(s)
			heroes[s] = h
			if net.mode != "client":
				awards.set_player(s, party.name_of(s))
	for s in heroes.keys():
		if not want.has(s):
			(heroes[s] as Node).queue_free()
			heroes.erase(s)


## Every machine: local pads drive their own heroes.
func _step_owned(delta: float) -> void:
	var phase := String(net.state_get("phase", ""))
	var can_move := phase != "results"
	var clamp := func(from: Vector3, to: Vector3) -> Vector3: return world.walk_clamp(from, to, Hero.RADIUS)
	for s in heroes:
		var h: Hero = heroes[s]
		h.owned = party.is_local(int(s))
		if not h.owned:
			continue
		var mv := party.stick(int(s), "move") if can_move else Vector2.ZERO
		var dir := Vector3(mv.x, 0.0, mv.y)
		if dir.length() < 0.15:
			dir = Vector3.ZERO
		h.step(delta, dir.limit_length(1.0), clamp)
		if can_move and h.dizzy_t <= 0.0 and h.bonk_cd <= 0.0 and (party.just_pressed(int(s), "accept") or party.just_pressed(int(s), "rt")):
			h.bonk_cd = 0.35
			h.bonk_anim()
			shot_once[int(s)] = true
			party.rumble(int(s), 0.2, 0.0, 0.06)
			net.request(int(s), "shoot", [h.position, h.rotation.y])
	send_t -= delta
	if net.mode == "client" and send_t <= 0.0:
		send_t = 1.0 / 30.0
		for s in heroes:
			var h2: Hero = heroes[s]
			if h2.owned:
				net.send_state(h2.position, h2.rotation.y, 1.0 if h2.dizzy_t > 0.0 else 0.0, int(s))


## Host: a TV machine's hero moved.
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if heroes.has(slot):
		var h: Hero = heroes[slot]
		h.set_remote(pos, yaw, h.dizzy_t > 0.0)


func _on_player_joined(_slot: int, _device: int) -> void:
	sfx.play("ui_notify", -6.0)


## TV: one camera above and behind the party, gliding after them.
func _tv_camera(delta: float) -> void:
	var sum := Vector3.ZERO
	var n := 0
	for h in heroes.values():
		sum += (h as Hero).position
		n += 1
	if avatar != null and avatar.visible:
		var ap := avatar.head.global_position
		sum += Vector3(ap.x, 0.0, ap.z)
		n += 1
	var zone := int(net.state_get("zone", 0))
	var c := World.center(zone) + Vector3(0.0, 0.0, 3.0) if n == 0 else sum / n
	c.x *= 0.5
	c.z = clampf(c.z, World.wall_z(World.ZONES - 1) + 4.0, 4.0)
	var high := 11.0 if zone == 3 else 8.5
	var want := c + Vector3(0.0, high, high * 0.95)
	cam_pos = cam_pos.lerp(want, 1.0 - exp(-2.5 * delta))
	var cam := split.shared_camera()
	cam.global_transform = Transform3D(Basis.looking_at(cam_pos + Vector3(0.0, -high, -high * 0.95 - 1.5) - cam_pos, Vector3.UP), cam_pos)
	shake = maxf(0.0, shake - delta * 2.0)
	if shake > 0.0:
		cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.15


func _apply_zone_look(zone: int) -> void:
	if sky != null:
		sky.set_preset("day" if bool(net.state_get("restored", false)) else SKIES[zone], 3.0)


# --- Effects (every machine) ---------------------------------------------------------------------

func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	if net.mode == "host":
		net.event("sfx", [n, p, db, pitch])


## Host: sparkles here and on the TV machine.
func sparkle_all(p: Vector3, col: Color, amount: int) -> void:
	sparkle(p, col, amount)
	net.event("sparkle", [p, col, amount])


func sparkle(p: Vector3, col: Color, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = amount
	cp.lifetime = 1.2
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 180.0
	cp.initial_velocity_min = 1.5
	cp.initial_velocity_max = 3.5
	cp.gravity = Vector3(0, -2.0, 0)
	cp.damping_min = 1.0
	cp.damping_max = 2.0
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = MeshKit.vertex_material(true)
	cp.mesh = sm
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(1.0, 1.0, 0.8), col.lightened(0.4)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	cp.color_initial_ramp = g
	add_child(cp)
	cp.position = p
	cp.emitting = true
	get_tree().create_timer(1.6).timeout.connect(cp.queue_free)


## A spark, arrow, slash or fireball flying from -> to in t seconds.
func bolt_fx(from: Vector3, to: Vector3, kind: String, t: float) -> void:
	var col: Color = SHOT_COLOR.get(kind, Color.WHITE)
	var b := MeshKit.Builder.new()
	match kind:
		"arrow":
			b.cylinder(0.015, 0.015, 0.6, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(-PI * 0.5, 0.0, 0.0)), Color(0.6, 0.4, 0.25), 4)
			b.cone(0.04, 0.1, MeshKit.at(Vector3(0.0, 0.0, -0.33), Vector3.ONE, Vector3(-PI * 0.5, 0.0, 0.0)), Color(0.85, 0.9, 1.0), 4, true)
		"fire":
			b.sphere(0.16, MeshKit.at(Vector3.ZERO), Color(1.0, 0.55, 0.15), 10, true)
			b.sphere(0.09, MeshKit.at(Vector3(0.0, 0.0, 0.12)), Color(1.0, 0.9, 0.4), 8, true)
		"slash":
			b.torus(0.3, 0.03, MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.0, 0.4)), col, 16, 4, true)
		_:
			b.star(4, 0.12, 0.05, 0.03, MeshKit.at(Vector3.ZERO), col, true)
	var m := MeshKit.instance(b.build(), false)
	add_child(m)
	m.global_position = from
	if from.distance_to(to) > 0.05:
		m.look_at_from_position(from, to, Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.FORWARD)
	var tw := m.create_tween()
	tw.tween_property(m, "global_position", to, t)
	tw.tween_callback(m.queue_free)
	if kind == "fire":
		var tr := CPUParticles3D.new()
		tr.amount = 16
		tr.lifetime = 0.35
		tr.local_coords = false
		tr.gravity = Vector3(0.0, 1.0, 0.0)
		tr.initial_velocity_max = 0.3
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = MeshKit.vertex_material(true)
		tr.mesh = sm
		tr.color = Color(1.0, 0.6, 0.2)
		m.add_child(tr)


## Lightning: a jagged glowing bolt from the sky to each point.
func thunder_fx(pts: Array) -> void:
	var b := MeshKit.Builder.new()
	for p in pts:
		var at: Vector3 = p
		var prev := at + Vector3(randf_range(-0.5, 0.5), 9.0, randf_range(-0.5, 0.5))
		for i in 6:
			var k := float(i + 1) / 6.0
			var nxt := prev.lerp(at, k) + Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.35, 0.35)) * (1.0 - k)
			if i == 5:
				nxt = at
			b.tube(prev, nxt, 0.06, 0.04, Color(1.0, 0.95, 0.5), 5, true)
			prev = nxt
	var m := MeshKit.instance(b.build(), false)
	add_child(m)
	var tw := m.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(m, "scale", Vector3(0.1, 1.0, 0.1), 0.15)
	tw.tween_callback(m.queue_free)
	for p2 in pts:
		sparkle(p2, Color(1.0, 0.95, 0.5), 14)


## The Stone Giant's stomp: a ring of dust and a TV shake.
func stomp_fx(p: Vector3) -> void:
	for i in 8:
		var a := TAU * i / 8.0
		sparkle(p + Vector3(cos(a) * 2.0, 0.2, sin(a) * 2.0), Color(0.75, 0.65, 0.5), 8)
	shake = 1.0
	if vr_rig != null:
		_pulse_both(0.6, 0.25)


func _build_arrow() -> void:
	var b := MeshKit.Builder.new()
	b.box(Vector3(0.3, 0.04, 0.6), MeshKit.at(Vector3(0, 0, 0.25)), Color(0.4, 1.0, 0.7), true)
	b.cone(0.35, 0.45, MeshKit.at(Vector3(0, 0, -0.25), Vector3(1.0, 1.0, 0.1), Vector3(-PI * 0.5, 0, 0)), Color(0.4, 1.0, 0.7), 3, true)
	arrow = MeshKit.instance(b.build(), false)
	arrow.visible = false
	add_child(arrow)


func _animate_arrow() -> void:
	var zone := int(net.state_get("zone", 0))
	var phase := String(net.state_get("phase", ""))
	var on := phase == "cleared" and int(net.state_get("open", 0)) > zone
	var base := World.wall_z(zone) + 1.6
	if phase == "orb" and not world.is_used(world.orb_id):
		on = true
		base = world.prop_center(world.orb_id).z + 1.6
	elif phase == "crystal":
		on = true
		base = world.prop_center(world.big_id).z + 2.6
	arrow.visible = on
	if on:
		arrow.position = Vector3(0.0, 0.05, base - fmod(Time.get_ticks_msec() * 0.004, 1.0) * 0.8)


## The beam of light rising from the Crystal of Light: everyone can see where the journey goes.
func _build_beam() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.5
	cm.height = 80.0
	cm.radial_segments = 10
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam_mat = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam = MeshInstance3D.new()
	beam.mesh = cm
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	beam.position = world.prop_center(world.big_id) + Vector3(0.0, 40.5, 0.0)
	_beam_look(0.0)


func _beam_look(k: float) -> void:
	if beam_mat == null:
		return
	beam_mat.albedo_color = Color(0.55, 0.3, 0.8, 0.35).lerp(Color(1.0, 0.85, 0.4, 0.6), k)
	beam.scale = Vector3(lerpf(0.6, 2.2, k), 1.0, lerpf(0.6, 2.2, k))


## VR: fade to black, do something (move the hero), fade back. A comfortable "teleport".
func _build_blink() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 12
	sm.rings = 6
	sm.flip_faces = true
	blink_mat = StandardMaterial3D.new()
	blink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blink_mat.render_priority = 100
	blink_mat.albedo_color = Color(0, 0, 0, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = blink_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vr_rig.camera.add_child(mi)


func blink(then: Callable) -> void:
	if blink_mat == null:
		then.call()
		return
	blink_mat.albedo_color = Color(0, 0, 0, 0)
	var tw := create_tween()
	tw.tween_property(blink_mat, "albedo_color:a", 1.0, 0.18)
	tw.tween_callback(then)
	tw.tween_interval(0.1)
	tw.tween_property(blink_mat, "albedo_color:a", 0.0, 0.3)


# --- VR headline ---------------------------------------------------------------------------------

## VR: one short headline, world-locked a few metres ahead of the hero and up high, facing them on Y.
func show_headline(text: String, secs: float = 3.0) -> void:
	if vr_rig == null:
		return
	if headline == null:
		headline = Label3D.new()
		headline.font_size = 96
		headline.pixel_size = 0.006
		headline.outline_size = 26
		headline.modulate = Color(1.0, 0.92, 0.35)
		headline.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		headline.double_sided = false
		headline.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(headline)
	var head := vr_rig.head_position()
	var at := head + vr_rig.head_forward() * 4.5
	at.y = head.y + 1.1
	headline.position = at
	var d := at - head
	headline.basis = Basis(Vector3.UP, atan2(-d.x, -d.z))
	headline.text = text
	headline.visible = true
	headline_t = secs


func _headline(delta: float) -> void:
	if headline == null or not headline.visible or headline_t < 0.0:
		return
	headline_t -= delta
	if headline_t <= 0.0:
		headline.visible = false


# --- TV HUD --------------------------------------------------------------------------------------

func _make_hud(parent: Control) -> void:
	hud = UiKit.ui_root(parent)
	var card := UiKit.panel("card")
	hud.add_child(card)
	card.position = Vector2(24.0, 20.0)
	gem_row = UiKit.hbox(6)
	card.add_child(gem_row)
	pill = UiKit.panel("pill")
	hud.add_child(pill)
	pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_top = -60.0
	pill.offset_bottom = -60.0
	_refresh_hud()


## Top-left: a gem per place passed, and a star once the Crystal of Light shines again.
func _refresh_hud() -> void:
	if gem_row == null:
		return
	for c in gem_row.get_children():
		c.queue_free()
	var open := int(net.state_get("open", 0))
	for k in World.ZONES - 1:
		gem_row.add_child(UiKit.icon("gem", "gold" if k < open else "dim", 34.0))
	gem_row.add_child(UiKit.icon("star", "gold" if bool(net.state_get("restored", false)) else "dim", 34.0))


func _update_pill() -> void:
	var want := ""
	if party.local_slots().is_empty():
		want = "Join"
	else:
		for s in party.local_slots():
			if heroes.has(s) and not shot_once.has(s):
				want = "Shoot!"
	if String(net.state_get("phase", "")) == "results":
		want = ""
	if want != pill_text:
		pill_text = want
		for c in pill.get_children():
			c.queue_free()
		if want != "":
			pill.add_child(UiKit.prompts([["A", want]]))
	pill.visible = want != ""


# --- Store, results, pause -----------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"open":
			world.set_open(int(value))
			_refresh_hud()
		"used":
			world.set_used(int(value))
		"zone":
			_apply_zone_look(int(value))
		"restored":
			_refresh_hud()
			if bool(value):
				var tw := create_tween()
				tw.tween_property(world, "restored", 1.0, 3.5).set_trans(Tween.TRANS_SINE)
				tw.parallel().tween_method(_beam_look, 0.0, 1.0, 3.5)
				_apply_zone_look(4)
			else:
				world.restored = 0.0
				_beam_look(0.0)
		"phase":
			var ph := String(value)
			_refresh_hud()
			if ph == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
			var z := int(net.state_get("zone", 0))
			match ph:
				"practice":
					music.play_mood(MOODS[0])
					if split != null:
						HudKit.banner([hud], NAMES[0], "", {"duration": 2.0})
					if vr_rig != null:
						get_tree().create_timer(4.0).timeout.connect(func() -> void:
							if String(net.state_get("phase", "")) == "practice" and not world.is_used(world.dummy_id):
								show_headline("SWING!", 6.0))
				"fight", "boss", "crystal":
					music.play_mood(MOODS[z])
					if split != null:
						HudKit.banner([hud], NAMES[z], "", {"duration": 1.8})
					show_headline(NAMES[z])
				"orb":
					show_headline("TOUCH THE ORB!" if not world.is_used(world.orb_id) else "SWORD UP!", 5.0)
				"cleared":
					show_headline("ONWARD!", 2.5)
				"restore":
					music.play_mood("victory")
					if split != null:
						HudKit.banner([hud], "LIGHT!", "", {"duration": 3.0})
				"yay":
					show_headline("HOORAY!", 5.0)


func _show_results(data: Dictionary) -> void:
	_hide_results()
	if split != null and not data.is_empty():
		var screen := Awards.results_screen(hud, data, {"party": party, "min_time": 5.0})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "again"))
		results_ui = screen
	show_headline("AGAIN?", 90.0)


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


func on_pause_changed(paused: bool, _by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			show_headline("PAUSED", -1.0)
		elif headline != null:
			headline.visible = false
	if split != null:
		if tv_banner == null:
			var ui := UiKit.ui_root(self, 6)
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
			tv_banner = UiKit.panel("accent")
			ui.add_child(tv_banner)
			tv_banner.add_child(UiKit.title("PAUSED"))
			tv_banner.set_anchors_preset(Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


# --- Networking ----------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var slots := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var flags := PackedInt32Array()
	for s in heroes:
		var h: Hero = heroes[s]
		slots.append(int(s))
		pos.append(h.position)
		yaw.append(snappedf(h.rotation.y, 0.02))
		flags.append(1 if h.dizzy_t > 0.0 else 0)
	return [pose, slots, pos, yaw, flags, monsters.pack()]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 6:
		return
	if avatar != null:
		avatar.apply_pose(s[0])
	var slots: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var yaw: PackedFloat32Array = s[3]
	var flags: PackedInt32Array = s[4]
	for i in slots.size():
		var slot := slots[i]
		if heroes.has(slot) and not party.is_local(slot):
			(heroes[slot] as Hero).set_remote(pos[i], yaw[i], flags[i] & 1 != 0)
	monsters.unpack(s[5])


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"sparkle":
			sparkle(args[0], args[1], int(args[2]))
		"prop":
			world.react(int(args[0]))
		"bolt":
			bolt_fx(args[0], args[1], String(args[2]), float(args[3]))
		"thunder":
			thunder_fx(args[0])
		"stomp":
			stomp_fx(args[0])
		"flash":
			if sky != null:
				sky.flash(float(args[0]))
		"shake":
			shake = float(args[0])
		"shoot":
			var h: Hero = heroes.get(int(args[0]))
			if h != null and not party.is_local(int(args[0])):
				h.bonk_anim()
		"dizzy":
			var h2: Hero = heroes.get(int(args[0]))
			if h2 != null:
				h2.get_dizzy()
				if party.is_local(int(args[0])):
					party.rumble(int(args[0]), 0.4, 0.3, 0.2)
		"warp":
			var h3: Hero = heroes.get(int(args[0]))
			if h3 != null and party.is_local(int(args[0])):
				h3.position = args[1]
		"cheer":
			var h4: Hero = heroes.get(int(args[0]))
			if h4 != null:
				h4.anim.play("cheer", 2.0)
