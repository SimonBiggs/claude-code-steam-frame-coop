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
## STORY + DEPTH (saga.gd, sagagen.gd): LUMI the crystal fairy; every journey is a new SEEDED road (forest,
## cave and glade props, rocks, monster waves, the giant) one tier harder each time; the party LEVELS UP after
## the forest and the giant (two glowing stones: a spell or a sword trick; touch or shoot one; kept for good);
## crystal SHARDS (each place cleared, each chest) bring Willowbrook's places back and they stay; the first
## journey of the day is TODAY'S QUEST. One RUN telemetry line per journey (and on quit).
## Networked: the host sends "plan" [seed, tier, daily] and every machine rebuilds the same world.
## CS_ZONE=n starts in zone n (0..4) for tests; CS_JOURNEYS=n plays as if n journeys were done (tier).

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
const Seeded := preload("res://core/seeded.gd")
const SagaGen := preload("res://games/crystal_saga/sagagen.gd")
const Saga := preload("res://games/crystal_saga/saga.gd")
const StoryCard := preload("res://core/story_card.gd")
const Telemetry := preload("res://core/telemetry.gd")
const Realm := preload("res://games/crystal_saga/realm.gd")
const Classes := preload("res://games/crystal_saga/classes.gd")
const Layout := preload("res://games/crystal_saga/progress.gd")

const GAME_ID := "crystal_saga"
const MOODS: Array[String] = ["town", "overworld", "dungeon", "boss", "cosy"]
const SKIES: Array[String] = ["dawn", "day", "dungeon", "sunset", "sunset"]
const SHOT_COLOR := {"magic": Color(0.75, 0.5, 1.0), "arrow": Color(1.0, 0.9, 0.5), "slash": Color(0.6, 0.9, 1.0),
	"fire": Color(1.0, 0.5, 0.15), "heal": Color(1.0, 0.6, 0.75), "note": Color(1.0, 0.8, 0.35), "star": Color(1.0, 0.95, 0.5)}
const MAP_WAIT := 25.0  ## seconds before Lumi picks the first map stone

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
var plan := {}  ## this journey's road (sagagen.gd)
var journey := {}  ## host: {"seed", "tier", "daily"} (saga.gd journey())
var journeys_done := 0  ## host: finished journeys (save "restored", or CS_JOURNEYS)
var levelups := 0  ## host: level-ups this journey
var journey_t := 0.0
var journey_shards := 0
var picks: Array = []  ## host: skills picked this journey (telemetry)
var spin_cd := 0.0
var story_q: Array = []  ## host: story beats waiting their turn
var story_t := 0.0
var stories_shown := 0
var runs_logged := 0
var tel_open := false  ## a journey is under way (a RUN line is owed)
var tel_base: Array = [0, 0, 0, 0]  ## hits, dizzy, knocks, stomps when this journey started
var tel_tells := {}  ## log_tells when this journey started
var vr_story: Node3D
# saga-deep
var realm := {}  ## the family's map (realm.gd; every machine, from net state "realm")
var star_hits := 0  ## host: party hits towards the next STAR RAIN
var log_tells := {}  ## host: guardian attacks started (bots, telemetry)
var log_classes := {}  ## host: hero statue picks
var log_regions: Array = []  ## host: regions picked on the map stones
var quest_log := 0  ## host: quest things found this session
var map_card: Control  ## TV: the realm map shown while the stones are up
var quest_card: Control  ## TV: the picture quest log (top right)
var shard_label: Label
var skill_row: HBoxContainer

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
	net.sticky_event("story")  # a machine that joins later gets Lumi's latest card (core/net.gd)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = Saga.save_defaults()
	save.use_layout(Layout)
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
	awards.define("shardy", "SHARD SEEKER", "%s crystal shards", "shards")
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	monsters = Monsters.new()
	monsters.name = "Monsters"
	add_child(monsters)
	if mode != "client":
		if int(save.data.world) < 0:
			save.data.world = Seeded.fresh_seed()  # this family's own roads
			save.mark_dirty()
		_choose_journey()
	else:
		_plan_from_state()
	_make_world()
	_build_beam()
	var flat: bool = mode == "host" and not net.has_vr  # flat host (TV / Deck hosting): slot 0 is a pad player here
	if VrRig.wanted(mode) and not flat:
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
	if mode != "host" or vr_rig == null:
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		split.set_shared(true)
		split.shared_camera().fov = 55.0
		split.shared_camera().cull_mask &= ~World.ARCH_LAYER  # (the cave arches filled this high camera's view)
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
	party.allow_slot0 = mode != "client" and vr_rig == null
	if mode != "client":
		net.state_set("vr", vr_rig != null)
		_start_journey()
	else:
		_apply_world_state()
		_apply_zone_look(int(net.state_get("zone", 0)))
		if bool(net.state_get("restored", false)):
			_beam_look(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Crystal Saga: %s mode%s" % [mode, " with a VR hero" if vr_rig != null else ""])


# --- The journey (host / local) ------------------------------------------------------------------

## Host: which road this journey takes: the region on the first map stone (the next new one), or TODAY'S QUEST
## first each day. CS_REGION=n forces a realm slot, CS_HARD=1 brave mode, CS_JOURNEYS=n pretends n regions beaten.
func _choose_journey() -> void:
	journeys_done = int(save.data.restored)
	if OS.has_environment("CS_JOURNEYS"):
		journeys_done += int(OS.get_environment("CS_JOURNEYS"))
	realm = Realm.generate(int(save.data.world))
	var cleared := _cleared()
	var daily_due := journeys_done > 0 and not (save.data.daily as Dictionary).has(Seeded.today()) and not OS.has_environment("BOT_NO_DAILY")
	var want := int(Realm.choices(realm, cleared)[0])
	journey = Saga.journey(journeys_done, int(save.data.world), daily_due, "", want, cleared, _hard())
	if OS.has_environment("CS_REGION"):
		journey.region = clampi(int(OS.get_environment("CS_REGION")), 0, Realm.SIZE - 1)
		journey.tier = Realm.tier_of(realm, int(journey.region), cleared, _hard())
	plan = Saga.plan_for(journey, int(save.data.world), _hard())


## Host: realm slots beaten (the save's, plus CS_JOURNEYS pretend ones for tests).
func _cleared() -> Array:
	var out: Array = (save.data.cleared as Array).duplicate()
	if OS.has_environment("CS_JOURNEYS") and not realm.is_empty():
		for i in Realm.clear_order(realm, int(OS.get_environment("CS_JOURNEYS"))):
			if not out.has(i):
				out.append(i)
	return out


func _hard() -> bool:
	return bool(save.data.hard) or OS.has_environment("CS_HARD")


## Client: the host's road.
func _plan_from_state() -> void:
	var pl: Array = net.state_get("plan", [0, 0, false, 1, "", false, 0])
	journey = {"seed": int(pl[0]), "tier": int(pl[1]), "daily": bool(pl[2]), "region": int(pl[6]) if pl.size() > 6 else 0}
	plan = SagaGen.generate(int(pl[0]), int(pl[1]), int(pl[3]) if pl.size() > 3 else 1, String(pl[4]) if pl.size() > 4 else "",
		bool(pl[5]) if pl.size() > 5 else false)


## Host: the plan as the net store carries it (every machine rebuilds it with sagagen.gd generate()).
func _plan_state() -> Array:
	return [int(journey.seed), int(journey.tier), bool(journey.daily), int(plan.biome), String(plan.names[1]), bool(plan.hard),
		int(journey.get("region", 0))]


## Every machine: the family's realm from the net store ([world seed, cleared slots]).
func _realm_state() -> void:
	var rs: Array = net.state_get("realm", [])
	if rs.size() >= 2 and (realm.is_empty() or int(realm.seed) != int(rs[0])):
		realm = Realm.generate(int(rs[0]))
	if world != null and not realm.is_empty() and rs.size() >= 2:
		world.set_realm(realm, rs[1], Realm.open_slots(realm, rs[1]))


## Every machine: (re)build the world for `plan`; Willowbrook keeps the places already brought back.
func _make_world() -> void:
	if world != null:
		remove_child(world)
		world.queue_free()
	world = World.new()
	world.name = "World"
	add_child(world)
	monsters.skins = plan.get("skins", ["slime", "mushroom", "bat"])
	world.build(plan, int(net.state_get("village", Saga.places_for(int(save.data.shards)) if net.mode != "client" else 0)))
	monsters.giant_look = plan.giant_look
	monsters.speed = float(plan.speed)
	monsters.stomp_gap = plan.stomp
	monsters.guardian = plan.guardian
	_realm_state()
	world.set_heroes_unlocked(Classes.unlocked(int(net.state_get("village", 0))))
	world.set_brave(bool(net.state_get("hard", false)), bool(net.state_get("brave_ok", false)))
	if beam != null:
		beam.position = world.prop_center(world.big_id) + Vector3(0.0, 40.5, 0.0)


## Client (and after a rebuild): make the world match the replicated state.
func _apply_world_state() -> void:
	world.set_open(int(net.state_get("open", 0)))
	world.set_used(int(net.state_get("used", 0)), int(net.state_get("used2", 0)))
	world.set_village(int(net.state_get("village", 0)), false)
	world.restored = 1.0 if bool(net.state_get("restored", false)) else 0.0
	_show_offer()
	world.set_quest_count(int(net.state_get("quest", 0)))
	world.set_heroes_unlocked(Classes.unlocked(int(net.state_get("village", 0))))
	world.set_brave(bool(net.state_get("hard", false)), bool(net.state_get("brave_ok", false)))
	_realm_state()


## Every machine: the stones from the net store "offer" ([zone, ids...]: skills, or realm slots in the village).
func _show_offer() -> void:
	var off: Array = net.state_get("offer", [])
	var z := int(off[0]) if not off.is_empty() else 0
	var ids := off.slice(1)
	var bios: Array = []
	if z == 0 and not realm.is_empty():
		for slot in ids:
			bios.append(int(realm.regions[clampi(int(slot), 0, Realm.SIZE - 1)].biome))
	world.set_offer(z, ids, bios)


## Host: mark a prop used (props 0..61 in "used", the rest in "used2").
func _use(id: int) -> void:
	if id < 0:
		return
	if id < World.USED_SPLIT:
		net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
	else:
		net.state_set("used2", int(net.state_get("used2", 0)) | (1 << (id - World.USED_SPLIT)))


func _team() -> int:
	return maxi(1, heroes.size() + (1 if vr_rig != null else 0))


func _start_journey() -> void:
	if has_meta("started"):
		_choose_journey()
	if world == null or int(world.plan.get("seed", -1)) != int(plan.seed) or int(world.plan.get("tier", -1)) != int(plan.tier):
		_make_world()
	net.state_set("plan", _plan_state())
	net.state_set("realm", [int(save.data.world), _cleared()])
	_realm_state()
	net.state_set("offer", [])
	net.state_set("quest", 0)
	net.state_set("used2", 0)
	net.state_set("hard", _hard())
	net.state_set("brave_ok", int(save.data.restored) >= 1 or _hard())
	world.set_brave(_hard(), bool(net.state_get("brave_ok", false)))
	world.set_offer(0, [])
	levelups = 0
	journey_t = 0.0
	journey_shards = 0
	picks = []
	var hits0 := 0
	for k in log_hits:
		hits0 += int(log_hits[k])
	tel_base = [hits0, log_dizzy, log_knocks, log_stomps]
	tel_tells = log_tells.duplicate()  # (the log_ counters run for the whole session: bots)
	tel_open = true
	net.state_set("skills", (save.data.skills as Dictionary).duplicate())
	net.state_set("shards", int(save.data.shards))
	net.state_set("village", Saga.places_for(int(save.data.shards)))
	world.set_village(Saga.places_for(int(save.data.shards)), false)
	world.set_heroes_unlocked(Classes.unlocked(Saga.places_for(int(save.data.shards))))
	_send_classes()
	_apply_skills()
	_journey_story()
	save.data.journeys = int(save.data.journeys) + 1
	save.mark_dirty()
	print("Crystal Saga: journey %d seed %d tier %d%s: %s" % [journeys_done, int(journey.seed), int(journey.tier),
		" TODAY'S QUEST" if bool(journey.daily) else "", ", ".join(plan.names)])
	awards.reset()
	if vr_rig != null:
		awards.set_player(0, "HERO")
	for s in heroes:
		awards.set_player(int(s), party.name_of(int(s)))
	monsters.clear()
	monsters.clear_tells()
	shots.clear()
	star_hits = 0
	if hands != null:
		hands.reset()
	var first := 0
	if OS.has_environment("CS_ZONE") and not has_meta("started"):
		first = clampi(int(OS.get_environment("CS_ZONE")), 0, World.ZONES - 1)
	if OS.has_environment("CS_TRY") and OS.get_environment("CS_TRY") == "guardian" and not has_meta("started"):
		first = 3  # What's New: straight to the region's crystal guardian
	if first > 0 and not has_meta("started"):
		log_regions.append(int(journey.get("region", 0)))
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
		show_headline(Saga.DAILY_NAME if bool(journey.daily) else "CRYSTAL SAGA", 4.0)


## Host: Lumi's words as a journey starts, and sparkles on Willowbrook's newly mended places.
func _journey_story() -> void:
	var r := Seeded.rng(int(journey.seed), "story")
	if int(save.data.journeys) == 0:
		_say(_lumi(Saga.LINES.hello))
		_say(_lumi(Saga.LINES.broken, "shard"))
		_say(_lumi(Saga.LINES.help, "sun"))
	elif bool(journey.daily):
		_say(_lumi(Saga.LINES.daily, "star"))
	else:
		_say(_lumi(Saga.pick(r, "start")))
	var village := Saga.places_for(int(save.data.shards))
	var seen := int(save.data.seen_places)
	if village > seen:
		for i in range(seen, village):
			sparkle_all(world.place_center(i), Color(1.0, 0.9, 0.5), 50)
		_say(_lumi(Saga.LINES.village, String(Saga.PLACES[village - 1].pic)))
		sound_at("sparkle", world.place_center(village - 1), 0.0)
		save.data.seen_places = village
	# What Willowbrook's growth unlocked: new heroes on the statues, new magic for the stones.
	var seen_u := int(save.data.seen_unlocks)
	for u in Saga.unlocks_between(seen_u, village):
		if String(u[1]) == "hero":
			var inf := Classes.info(String(u[2]))
			_say({"who": String(inf.name), "line": Saga.LINES.new_hero, "pic": String(inf.pic), "color": inf.color, "duration": 3.5})
		else:
			var sk: Dictionary = Saga.SKILLS[String(u[2])]
			_say({"who": String(sk.name), "line": Saga.LINES.new_magic, "pic": String(sk.pic), "color": sk.color, "duration": 3.5})
	save.data.seen_unlocks = Saga.unlock_count(village)


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
			if z == 1:
				var q: Dictionary = plan.quest
				_react(world.giver_id)
				_say({"who": String(q.giver), "line": Saga.LINES.help_me, "pic": String(q.giver_pic), "color": Saga.LUMI_COLOR, "duration": 3.0}, true)
				_quest_card(false)
		3:
			monsters.giant_hits = SagaGen.giant_hits(plan, _team())
			var gid := monsters.spawn(Monsters.GIANT, World.center(z) + Vector3(0.0, 0.0, -3.5))
			if _quest_done():  # the quest giver's gift: the guardian's mist starts a quarter smaller
				monsters.mons[gid]["hits"] = float(monsters.giant_hits) * 0.25
				monsters.mons[gid]["sz"] = 0.75
			net.state_set("phase", "boss")
			var q: Dictionary = plan.quest
			_say({"who": String(plan.names[3]), "line": Saga.LINES.guardian, "pic": "guardian",
				"color": plan.giant_look[1], "duration": 3.5}, true)
			if _quest_done():
				_say({"who": String(q.giver), "line": Saga.LINES.go, "pic": String(q.giver_pic), "color": Saga.LUMI_COLOR, "duration": 3.0})
		_:
			net.state_set("phase", "crystal")


## The forest's and the cave's monster waves, from the plan: how many come out depends on the team.
func _spawn_wave(z: int, w: int) -> void:
	var c := World.center(z)
	var waves: Array = plan.waves[z]
	if w >= waves.size():
		return
	var wave: Array = waves[w]
	var feet := _player_feet()
	var at: Array = []
	for i in SagaGen.wave_count(wave, _team()):
		var m: Array = wave[2][i]
		var p := Vector3(float(m[1]), float(m[2]), float(m[3]))
		for f in feet:  # never right on top of a hero: step back a little
			var d := Vector2(p.x - (f as Vector3).x, p.z - (f as Vector3).z)
			if d.length() < 1.6:
				p += Vector3(0.0, 0.0, -2.0 if p.z - 2.0 > c.z - World.HALF_L + 1.0 else 2.0)
		monsters.spawn(int(m[0]), p)
		at.append(p)
	if w > 0:
		for p4 in at:
			sparkle_all((p4 as Vector3) + Vector3(0.0, 0.4, 0.0), Color(0.8, 0.6, 1.0), 14)
		sound_at("whoosh", c, -2.0, 0.6)
		sound_at("pop", c, -4.0, 0.7)
		show_headline("MORE!", 2.0)


## Host: a place is cleared: a crystal shard, then (after the forest and the giant) the party levels up.
func _region_done(zone: int) -> void:
	_gain_shard(World.center(zone) + Vector3(0.0, 1.6, -3.0), -1)
	if zone in Saga.LEVELUP_ZONES:
		var ids := Saga.offer(int(journey.seed), levelups, save.data.skills, Saga.places_for(int(save.data.shards)))
		if not ids.is_empty():
			levelups += 1
			net.state_set("offer", [zone] + ids)
			world.set_offer(zone, ids)
			net.state_set("phase", "choose")
			phase_t = 0.0
			for cid in world.choice_ids:
				sparkle_all(world.prop_center(cid), Color(0.9, 0.8, 1.0), 40)
			sound_at("power_up", World.center(zone) + Vector3(0.0, 1.0, -4.4), -2.0, 1.2)
			_say(_lumi(Saga.LINES.levelup, "star"))
			return
	_zone_cleared()


## Host: the party learns (or strengthens) a skill: from a level-up stone (slot), or Lumi's pick (-1).
func _learn(id: String, slot: int) -> void:
	if String(net.state_get("phase", "")) != "choose":
		return
	if Saga.SKILLS.has(id):
		var skills: Dictionary = save.data.skills
		var was := Saga.level(skills, id)
		skills[id] = mini(was + 1, Saga.MAX_LEVEL)
		save.mark_dirty()
		picks.append(id)
		net.state_set("skills", skills.duplicate())
		_apply_skills()
		var info: Dictionary = Saga.SKILLS[id]
		var line: String = Saga.LINES.stronger if was > 0 else (Saga.LINES.new_spell if info.type == "spell" else Saga.LINES.new_trick)
		_say({"who": String(info.name), "line": line, "pic": String(info.pic), "color": info.color, "duration": 3.5}, true)
		show_headline(String(info.name), 2.5)
		var cid := world.choice_ids[0]
		for c0 in world.choice_ids:
			if world.skill_on(c0) == id:
				cid = c0
		var c := world.prop_center(cid)
		for k in 3:
			sparkle_all(c + Vector3(0.0, k * 0.5, 0.0), info.color, 40)
		sound_at("power_up", c, 0.0)
		sound_at("fanfare", c, -6.0)
		_pulse_both(0.7, 0.3)
		if slot >= 0:
			awards.add(slot, "picks")
	net.state_set("offer", [])
	world.set_offer(0, [])
	_zone_cleared()


func _lvl(id: String) -> int:
	return Saga.level(net.state_get("skills", {}), id)


## Host: skills that change the hero's gear (the LONG SWORD).
func _apply_skills() -> void:
	if hands != null:
		hands.set_blade(VrHands.BLADE * (1.0 + 0.2 * _lvl("long")))
	for s in heroes:
		_hero_gear(heroes[s] as Hero)


## A TV hero's class and the party's HEALING / BUBBLE: shorter dizzy spells, longer safety after.
func _hero_gear(h: Hero) -> void:
	h.dizzy_mult = float(Classes.info(h.cls).dizzy) * (1.0 - 0.2 * _lvl("heal"))
	h.safe_bonus = 0.8 * _lvl("bubble")


## Host: a crystal shard (a place cleared, a chest opened): it flies up and sparkles; it's kept for good.
func _gain_shard(at: Vector3, slot: int) -> void:
	save.data.shards = int(save.data.shards) + 1
	save.mark_dirty()
	journey_shards += 1
	net.state_set("shards", int(save.data.shards))
	for k in 3:
		sparkle_all(at + Vector3(0.0, k * 0.4, 0.0), Color(0.6, 0.9, 1.0), 24)
	sound_at("ding", at, -2.0, 1.5)
	sound_at("coin", at, -6.0, 1.3)
	if slot >= 0:
		awards.add(slot, "shards")
	if journey_shards == 1:
		_say(_lumi(Saga.LINES.shard, "shard"))


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
	_use(world.big_id)
	phase_t = 0.0
	var p := world.prop_center(world.big_id)
	sound_at("power_up", p, 0.0)
	sound_at("sparkle", p, 0.0)
	_pulse_both(0.8, 0.4)
	save.data["restored"] = int(save.data["restored"]) + 1
	if bool(journey.daily):
		(save.data.daily as Dictionary)[Seeded.today()] = true
	var slot := int(journey.get("region", 0))
	var was_open := Realm.open_slots(realm, _cleared())
	var newly := not (save.data.cleared as Array).has(slot)
	if newly:
		(save.data.cleared as Array).append(slot)
	save.mark_dirty()
	net.state_set("realm", [int(save.data.world), _cleared()])
	var bio := Realm.biome(realm, slot)
	_say({"who": String(realm.regions[slot].name), "line": Saga.LINES.crystal_home, "pic": String(bio.pic), "color": bio.glow, "duration": 3.5})
	for o in Realm.open_slots(realm, _cleared()):
		if not was_open.has(o):
			var b2 := Realm.biome(realm, int(o))
			_say({"who": String(realm.regions[int(o)].name), "line": Saga.LINES.new_road, "pic": String(b2.pic), "color": b2.glow, "duration": 3.0})
	if newly and (save.data.cleared as Array).size() == Realm.SIZE:
		_say(_lumi(Saga.LINES.realm_done, "rainbow"))
	var r := Seeded.rng(int(journey.seed), "end")
	_say(_lumi(Saga.pick(r, "restored"), "sun"), true)
	var was := int(net.state_get("village", 0))
	var now := Saga.places_for(int(save.data.shards))
	if now > was:
		net.state_set("village", now)
		world.set_village(now, true)
		for i in range(was, now):
			_say({"who": "WILLOWBROOK", "line": String(Saga.PLACES[i].line), "pic": String(Saga.PLACES[i].pic),
				"color": Color(1.0, 0.85, 0.45), "duration": 3.5})


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
	_telemetry("done")
	var data := awards.results({"title": "LIGHT RESTORED!", "style": "victory", "score_stat": "poofs",
		"score_format": "%d POOFS", "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


# --- The realm map, heroes, quests, brave mode (host) -----------------------------------------------

## Host: practice is done: the MAP stones by the gate show where the party can go (when there is a choice and it
## isn't TODAY'S QUEST), else off to the journey's region.
func _after_practice() -> void:
	var opts := Realm.choices(realm, _cleared())
	if bool(journey.daily) or opts.size() < 2 or OS.has_environment("CS_REGION") or OS.has_environment("CS_NO_MAP"):
		_pick_region(int(journey.get("region", 0)), -1)
		return
	net.state_set("offer", [0] + opts)
	_show_offer()
	net.state_set("phase", "map")
	phase_t = 0.0
	for cid in world.choice_ids:
		if (world.props[cid]["node"] as Node3D).visible:
			sparkle_all(world.prop_center(cid), Color(1.0, 0.9, 0.5), 30)
	sound_at("power_up", World.center(0) + Vector3(0.0, 1.0, -6.6), -4.0, 0.9)
	_say(_lumi(Saga.LINES.map, "star"), true)


## Host: the party picked a region (a map stone; slot -1: Lumi's pick). A different road: the world is rebuilt
## for it (behind a blink for the VR hero), then the village gate opens.
func _pick_region(region: int, by: int) -> void:
	if not String(net.state_get("phase", "")) in ["practice", "map"]:
		return
	net.state_set("offer", [])
	world.set_offer(0, [])
	var cleared := _cleared()
	if not bool(journey.daily):
		journey.region = region
		journey.tier = Realm.tier_of(realm, region, cleared, _hard())
	log_regions.append(int(journey.region))
	var np := Saga.plan_for(journey, int(save.data.world), _hard())
	if int(np.biome) != int(plan.biome) or int(np.tier) != int(plan.tier) or bool(np.hard) != bool(plan.hard):
		plan = np
		net.state_set("plan", _plan_state())
		if vr_rig != null:
			blink(func() -> void:
				_make_world()
				_apply_world_state())
		else:
			_make_world()
			_apply_world_state()
	var bio := Realm.biome(realm, int(journey.region))
	_say({"who": String(plan.names[1]), "line": Saga.pick(Seeded.rng(int(journey.seed), "start"), "start"), "pic": String(bio.pic),
		"color": bio.glow, "duration": 3.0}, true)
	if by >= 0:
		awards.add(by, "picks")
	print("Crystal Saga: off to %s (realm slot %d, tier %d%s)" % [plan.names[1], int(journey.region), int(journey.tier), " BRAVE" if _hard() else ""])
	_zone_cleared()


## Every machine: the hero a seat plays (net store "classes": {seat: hero}).
func _class_of(slot: int) -> String:
	var cl: Dictionary = net.state_get("classes", {})
	return String(cl.get(str(slot), Classes.default_for(slot)))


## Host: every seat's hero (saved picks, if unlocked) to every machine.
func _send_classes() -> void:
	var places := Saga.places_for(int(save.data.shards))
	var out := {}
	for s in range(0, 7):
		out[str(s)] = Classes.of(save.data.classes, s, places)
	net.state_set("classes", out)


## Host: a hero bonked a statue: that seat becomes that hero (kept). Locked ones just go "tock".
func _statue(id: int, slot: int) -> void:
	var cls := String(world.props[id]["class"])
	var c := world.prop_center(id)
	var places := int(net.state_get("village", 0))
	if not Classes.unlocked(places).has(cls):
		sound_at("tock", c, -2.0, 0.8)
		sparkle_all(c, Color(0.6, 0.6, 0.65), 10)
		return
	if not heroes.has(slot) or (slot == 0 and vr_rig != null):
		sound_at("sparkle", c, -6.0)
		return
	(save.data.classes as Dictionary)[str(slot)] = cls
	save.mark_dirty()
	log_classes[slot] = cls
	_send_classes()
	var inf := Classes.info(cls)
	sparkle_all((heroes[slot] as Hero).position + Vector3(0.0, 0.7, 0.0), inf.color, 40)
	sparkle_all(c, inf.color, 24)
	sound_at("power_up", c, -4.0, 1.3)
	_say({"who": String(inf.name), "line": party.name_of(slot), "pic": String(inf.pic), "color": inf.color, "duration": 2.5}, true)


## Host: the BRAVE flag: gentle <-> brave (kept; the next road is a tier harder, tells a little quicker).
func _toggle_brave(slot: int) -> void:
	if not bool(net.state_get("brave_ok", false)):
		return
	save.data.hard = not bool(save.data.hard)
	save.mark_dirty()
	net.state_set("hard", _hard())
	world.set_brave(_hard(), true)
	var c := world.prop_center(world.banner_id)
	sparkle_all(c, Color(1.0, 0.4, 0.2) if _hard() else Color(0.6, 1.0, 0.6), 36)
	sound_at("fanfare" if _hard() else "sparkle", c, -4.0)
	_say(_lumi(Saga.LINES.brave if _hard() else Saga.LINES.gentle, "fire" if _hard() else "heart"), true)
	if slot >= 0:
		awards.add(slot, "flags")


func _quest_done() -> bool:
	return int(net.state_get("quest", 0)) >= int((plan.get("quest", {}) as Dictionary).get("need", 3))


## Host: a quest thing found (poked, touched or sparked): the giver's dots fill; the last one: thank you, a shard,
## and the guardian will start weaker.
func _quest_found(id: int, slot: int) -> void:
	if _quest_done():
		_use(id)  # a spare one: still a sparkle
		sparkle_all(world.prop_center(id), Color(1.0, 0.9, 0.5), 20)
		return
	_use(id)
	quest_log += 1
	var c := world.prop_center(id)
	var n := int(net.state_get("quest", 0)) + 1
	net.state_set("quest", n)
	world.set_quest_count(n)
	sparkle_all(c + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.9, 0.5), 30)
	sound_at("ding", c, -2.0, 1.0 + 0.15 * n)
	sound_at("sparkle", c, -6.0)
	if slot >= 0:
		awards.add(slot, "finds")
	if _quest_done():
		var q: Dictionary = plan.quest
		_react(world.giver_id)
		_say({"who": String(q.giver), "line": Saga.LINES.quest_done, "pic": String(q.giver_pic), "color": Saga.LUMI_COLOR, "duration": 3.5}, true)
		_gain_shard(world.prop_center(world.giver_id) + Vector3(0.0, 1.2, 0.0), slot)
		sound_at("fanfare", c, -4.0)
		show_headline("THANK YOU!", 2.5)
	else:
		_quest_card(false)


## Host: the quest as a picture card (the giver, what to find, how many found).
func _quest_card(now: bool) -> void:
	var q: Dictionary = plan.get("quest", {})
	if q.is_empty():
		return
	var line := "%d / %d" % [int(net.state_get("quest", 0)), int(q.need)]
	_say({"who": String(q.giver), "line": line, "pic": String(q.item_pic), "color": Saga.LUMI_COLOR, "duration": 2.5}, now)


# --- Host rules ----------------------------------------------------------------------------------

func _host_step(delta: float) -> void:
	var phase := String(net.state_get("phase", ""))
	var zone := int(net.state_get("zone", 0))
	phase_t += delta
	journey_t += delta
	spin_cd = maxf(0.0, spin_cd - delta)
	knock_cd = maxf(0.0, knock_cd - delta)
	story_t -= delta
	if story_t <= 0.0 and not story_q.is_empty():
		story_t = 3.6
		_story(story_q.pop_front())
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
	for tl in monsters.new_tells:
		log_tells[String(tl[0])] = int(log_tells.get(String(tl[0]), 0)) + 1
		net.event("tell", tl)
		var tp: Vector3 = (tl[1] as Array)[0] if not (tl[1] as Array).is_empty() else World.center(3)
		match String(tl[0]):
			"rain":
				sound_at("magic", tp, -2.0, 0.6)
			"roll":
				sound_at("buff", tp, 0.0, 0.45)
			"call":
				sound_at("bell", tp, -4.0, 0.7)
	for ld in monsters.landed:
		var pts: Array = ld[1]
		match String(ld[0]):
			"rain":
				for q in pts:
					sparkle_all((q as Vector3) + Vector3(0.0, 0.3, 0.0), Color(0.5, 0.85, 1.0), 18)
				sound_at("crash", pts[0], -4.0, 1.4)
			"roll":
				sound_at("whoosh", pts[1], 0.0, 0.5)
				sound_at("land", pts[1], 0.0, 0.6)
				shake = maxf(shake, 0.5)
				net.event("shake", [0.5])
			"call":
				for q2 in pts:
					sparkle_all((q2 as Vector3) + Vector3(0.0, 0.4, 0.0), Color(0.5, 1.0, 0.5), 20)
				sound_at("pop", pts[0], -2.0, 0.8)
	for st in monsters.stomps:
		log_stomps += 1
		log_tells["stomp"] = int(log_tells.get("stomp", 0)) + 1
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
				_after_practice()
		"map":
			if phase_t > MAP_WAIT:
				var off0: Array = net.state_get("offer", [])
				_pick_region(int(off0[1]) if off0.size() > 1 else int(journey.get("region", 0)), -1)
		"fight":
			if monsters.count() == 0 and phase_t > 0.5 and wave < (plan.waves[zone] as Array).size() - 1:
				wave += 1
				phase_t = 0.0
				_spawn_wave(zone, wave)
			elif monsters.count() == 0 and phase_t > 0.5:
				if zone == 2 and not _thunder_learned():
					net.state_set("phase", "orb")
					phase_t = 0.0
				else:
					_region_done(zone)
		"orb":
			if _thunder_learned() or (world.is_used(world.orb_id) and phase_t > 25.0):
				_region_done(zone)
		"boss":
			if monsters.count() == 0 and phase_t > 0.5:
				_region_done(zone)
		"choose":
			if phase_t > 30.0:  # nobody picked: Lumi picks the spell
				var off: Array = net.state_get("offer", [])
				_learn(String(off[1]) if off.size() > 1 else "", -1)
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


## Host: a monster was hit (slot 0 = the VR hero / a local knight, 1+ = a TV hero). src: what hit it
## ("sword", "fire", "magic", "arrow", "slash", "thunder"; "splash" / "spin" are skill follow-ups).
func hit_monster(id: int, slot: int, at: Vector3, src: String = "") -> bool:
	if not monsters.mons.has(id):
		return false
	var kind: int = monsters.mons[id]["kind"]
	var res := monsters.hit(id, 1.0 + 0.5 * _lvl("mighty") if kind == Monsters.GIANT else 1.0)
	if res != "" and not src in ["splash", "spin", ""]:
		_skill_followups(id, slot, at, src)
	if res == "":
		return false
	log_hits[slot] = int(log_hits.get(slot, 0)) + 1
	if src == "note":
		_note_freeze(at)
	if not src in ["splash", "spin", "star", ""]:
		_star_rain_tick(slot)
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


## BARD: a note makes the monsters round where it lands stop to listen (never the guardian).
func _note_freeze(at: Vector3) -> void:
	for other in monsters.mons.keys():
		var c: Vector3 = monsters.center_of(other)
		if c.distance_to(at) < Classes.NOTE_R and int(monsters.mons[other]["kind"]) != Monsters.GIANT:
			monsters.freeze(int(other), Classes.NOTE_FREEZE)
			sparkle_all(c + Vector3(0.0, 0.3, 0.0), SHOT_COLOR["note"], 10)
	sound_at("ding", at, -8.0, 1.6)


## HEALER: her spark wakes dizzy friends near her (and the VR hero feels a warm buzz).
func _heal_wave(pos: Vector3, slot: int) -> void:
	var woke := 0
	for s in heroes:
		var h: Hero = heroes[s]
		if int(s) != slot and h.dizzy_t > 0.0 and h.position.distance_to(pos) < Classes.HEAL_R:
			h.wake()
			net.event("wake", [int(s)])
			sparkle_all(h.position + Vector3(0.0, 0.8, 0.0), SHOT_COLOR["heal"], 18)
			woke += 1
	if woke > 0:
		sound_at("power_up", pos, -8.0, 1.6)
		awards.add(slot, "heals")


## STAR RAIN: every few hits by the party, stars fall on the nearest monsters.
func _star_rain_tick(slot: int) -> void:
	var lv := _lvl("star")
	if lv <= 0:
		return
	star_hits += 1
	if star_hits < 7 - lv:
		return
	star_hits = 0
	var near: Array = []
	for id in monsters.mons:
		near.append(int(id))
	for i in mini(lv + 1, near.size()):
		var mid: int = near[i]
		if not monsters.mons.has(mid):
			continue
		var c: Vector3 = monsters.center_of(mid)
		bolt_fx(c + Vector3(0.0, 5.0, 0.0), c, "star", 0.35)
		net.event("bolt", [c + Vector3(0.0, 5.0, 0.0), c, "star", 0.35])
		shots.append({"t": 0.35, "mon": mid, "prop": -1, "slot": slot, "at": c, "kind": "star"})
	sound_at("sparkle", World.center(int(net.state_get("zone", 0))), -2.0, 1.4)


## (MIGHTY: each hit on the giant counts 1.5 / 2 / 2.5.)
## Host: what the party's skills add to a hit: BIG FIRE splashes, ICE freezes, SPIN (the VR sword) whirls.
func _skill_followups(id: int, slot: int, at: Vector3, src: String) -> void:
	var splash := _lvl("splash")
	if splash > 0 and src in ["fire", "magic"]:
		var rad := 0.8 + 0.6 * splash
		sparkle_all(at, Color(1.0, 0.55, 0.2), 20 + 10 * splash)
		for other in monsters.mons.keys():
			if int(other) != id and monsters.mons.has(other) and monsters.center_of(other).distance_to(at) < rad:
				hit_monster(int(other), slot, monsters.center_of(other), "splash")
	var ice := _lvl("ice")
	if ice > 0:
		var rad2 := 1.5 + 0.5 * ice
		for other2 in monsters.mons.keys():
			var c2: Vector3 = monsters.center_of(other2)
			# (Never the giant: one TV hero tapping A would keep him frozen for good, and he'd never stomp.)
			if c2.distance_to(at) < rad2 and not monsters.frozen(int(other2)) and int(monsters.mons[other2]["kind"]) != Monsters.GIANT:
				monsters.freeze(int(other2), 1.5 + ice)
				sparkle_all(c2, Color(0.7, 0.95, 1.0), 16)
		sound_at("ding", at, -8.0, 2.2)
	var spin := _lvl("spin")
	if spin > 0 and src == "sword" and spin_cd <= 0.0 and vr_rig != null:
		spin_cd = 1.2
		_spin_at(vr_rig.head_position(), 1.0 + 0.5 * spin, 0)


## SPIN: every monster round `at` (within rad) is hit, with a ring of sparkles.
func _spin_at(at: Vector3, rad: float, slot: int) -> int:
	var n := 0
	for k in 10:
		var a := TAU * k / 10.0
		sparkle_all(Vector3(at.x + cos(a) * rad, 0.6, at.z + sin(a) * rad), Color(0.5, 1.0, 0.8), 6)
	sound_at("whoosh", at, -2.0, 1.3)
	for other in monsters.mons.keys():
		if not monsters.mons.has(other):
			continue
		var c: Vector3 = monsters.center_of(other)
		if Vector2(c.x - at.x, c.z - at.z).length() < rad + monsters.radius_of(other):
			if hit_monster(int(other), slot, c, "spin"):
				n += 1
	return n


## TWIN SPARK: up to `count` more bolts at the next-nearest monsters in reach (not `skip`).
func _twin_bolts(from: Vector3, pos: Vector3, reach: float, count: int, skip: int, kind: String, slot: int) -> void:
	if count <= 0:
		return
	var near: Array = []
	for id in monsters.mons:
		if int(id) == skip:
			continue
		var c: Vector3 = monsters.center_of(id)
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
		if d < reach:
			near.append([d, int(id), c])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in mini(count, near.size()):
		_launch(from, near[i][2], kind, slot, int(near[i][1]), -1)


func _giant_friendly(at: Vector3) -> void:
	_use(world.friend_id)
	for mid in monsters.mons.keys():  # the helpers he called pop into sparkles too
		if bool(monsters.mons[mid]["minion"]):
			sparkle_all(monsters.center_of(mid), Color(0.6, 1.0, 0.7), 20)
			monsters.remove(int(mid))
	monsters.clear_tells()
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
	if poke_cd.has(id) or (world.is_used(id) and kind in [World.CHEST, World.DUMMY, World.STONE, World.TARGET, World.QUEST]):
		return false
	if kind == World.FRIEND and not world.is_used(id):
		return false
	if kind == World.CHOICE and world.region_on(id) >= 0:
		if phase != "map":
			return false
		_pick_region(world.region_on(id), slot)
		return true
	if kind == World.CHOICE:
		var skill := world.skill_on(id)
		if phase != "choose" or skill == "":
			return false
		_learn(skill, slot)
		return true
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
		World.ROCK:
			sound_at("tock", c, -2.0, 0.7)
			sparkle_all(c + Vector3(0.0, 0.3, 0.0), Color(0.75, 0.72, 0.68), 10)
		World.CRYSTAL:
			poke_cd[id] = 0.4
			var notes: Array[float] = [1.0, 1.122, 1.26, 1.335, 1.498, 1.682, 1.888, 2.0]
			sound_at("ding", c, -2.0, notes[id % notes.size()])
			sound_at("sparkle", c, -10.0, 1.4)
			sparkle_all(c, Color(0.6, 0.9, 1.0), 12)
			awards.add(slot, "chimes")
		World.CHEST:
			_use(id)
			sparkle_all(c + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.85, 0.2), 44)
			sound_at("chest", c, -2.0)
			sound_at("coin", c, -4.0)
			awards.add(slot, "chests")
			_gain_shard(c + Vector3(0.0, 0.6, 0.0), slot)
		World.VILLAGER:
			poke_cd[id] = 2.0
			sound_at("bell", c, -8.0, 1.4)
			sound_at("sparkle", c + Vector3(0.0, 1.0, 0.0), -10.0)
		World.QUEST:
			_quest_found(id, slot)
		World.GIVER:
			poke_cd[id] = 3.0
			sound_at("bell", c, -6.0, 1.2)
			_quest_card(true)
		World.STATUE:
			poke_cd[id] = 0.8
			_statue(id, slot)
		World.BANNER:
			poke_cd[id] = 1.2
			_toggle_brave(slot)
		World.MAP:
			poke_cd[id] = 2.0
			sound_at("sparkle", c, -4.0, 0.9)
			sparkle_all(c + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.9, 0.5), 30)
			_say(_lumi(Saga.LINES.map, "star"), true)
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
				_use(id)
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
	_use(id)
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
	knock_cd = 2.5 + 0.6 * _lvl("bubble")
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
	if int(aim[0]) >= 0:
		_twin_bolts(from, head, 14.0, _lvl("twin"), int(aim[0]), "fire", 0)


## Host: the VR hero raised the glowing sword. Lightning strikes every monster near.
func cast_thunder(tip: Vector3) -> void:
	awards.add(0, "spells")
	var head := vr_rig.head_position()
	var pts: Array = [tip]
	for id in monsters.mons.keys():
		var c: Vector3 = monsters.center_of(id)
		if Vector2(c.x - head.x, c.z - head.z).length() < 7.5:
			pts.append(c)
			hit_monster(int(id), 0, c, "thunder")
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
			hit = hit_monster(mon, int(d["slot"]), monsters.center_of(mon), String(d["kind"]))
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
	var hero_cls := (heroes[slot] as Hero).cls if heroes.has(slot) else Classes.default_for(slot)
	var kind := String(Classes.info(hero_cls).shot)
	var from := pos + Vector3(0.0, 0.8, 0.0) + fwd * 0.4
	var reach := float(Classes.info(hero_cls).reach) * (1.0 + 0.2 * _lvl("long"))
	if kind == "heal":
		_heal_wave(pos, slot)
	if _lvl("spin") > 0 and spin_cd <= 0.0:  # SPIN: a whirl hits everything right round the hero
		var near := false
		for id in monsters.mons:
			var mc: Vector3 = monsters.center_of(id)
			near = near or Vector2(mc.x - pos.x, mc.z - pos.z).length() < 1.0 + 0.5 * _lvl("spin") + monsters.radius_of(id)
		if near:
			spin_cd = 0.6 if _team() > 1 else 0.4
			_spin_at(pos, 1.0 + 0.5 * _lvl("spin"), slot)
	var targets: Array = [world.stone_id, world.orb_id, world.big_id]
	if String(net.state_get("phase", "")) in ["choose", "map"]:
		targets.append_array(world.choice_ids)
	for qid in world.quest_ids:  # a spark lights a lantern, rings a bell, finds a lost lamb from afar
		if not world.is_used(qid):
			targets.append(qid)
	var aim := _aim(pos, fwd, reach, 0.55, targets)
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
	sound_at("bow" if kind == "arrow" else ("sword" if kind == "slash" else "magic"), from, -6.0, randf_range(1.0, 1.2))
	_launch(from, aim[1], kind, slot, int(aim[0]), int(aim[2]))
	if int(aim[0]) >= 0:
		_twin_bolts(from, pos, reach, _lvl("twin"), int(aim[0]), kind, slot)


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
			h.setup(s, party.color_of(s), _class_of(s))
			_hero_gear(h)
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
	cam.global_transform = Transform3D(UiKit.face(cam_pos + Vector3(0.0, -high, -high * 0.95 - 1.5) - cam_pos), cam_pos)
	shake = maxf(0.0, shake - delta * 2.0)
	if shake > 0.0:
		cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.15


func _apply_zone_look(zone: int) -> void:
	if sky != null:
		var want: String = SKIES[zone]
		var sk: Array = plan.get("sky", [])
		if zone in [1, 2] and sk.size() == 2:
			want = String(sk[zone - 1])
		sky.set_preset("day" if bool(net.state_get("restored", false)) else want, 3.0)


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
	preload("res://core/vr_layer.gd").mark(mi)  # on the headset: never on the TV cameras


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
	var col := UiKit.vbox(6)
	card.add_child(col)
	gem_row = UiKit.hbox(6)
	col.add_child(gem_row)
	var row2 := UiKit.hbox(8)
	col.add_child(row2)
	row2.add_child(StoryCard.picture("shard", 34.0, Color(0.6, 0.9, 1.0)))
	shard_label = UiKit.label("0", "heading", Color(0.75, 0.92, 1.0))
	row2.add_child(shard_label)
	skill_row = UiKit.hbox(4)
	row2.add_child(skill_row)
	# The picture quest log: who asked, what to find, a dot for each (no words: the little ones follow it too).
	quest_card = UiKit.panel("card")
	hud.add_child(quest_card)
	UiKit.pin(quest_card, Control.PRESET_TOP_RIGHT)
	quest_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quest_card.offset_left = -24.0
	quest_card.offset_right = -24.0
	quest_card.offset_top = 20.0
	pill = UiKit.panel("pill")
	hud.add_child(pill)
	UiKit.pin(pill, Control.PRESET_CENTER_BOTTOM)
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
	# Crystal shards found (they mend Willowbrook) and the party's skills (a picture each, a dot per level).
	shard_label.text = str(int(net.state_get("shards", 0)))
	_refresh_quest_card()
	for c2 in skill_row.get_children():
		c2.queue_free()
	var skills: Dictionary = net.state_get("skills", {})
	for id in Saga.SKILLS:
		var l := Saga.level(skills, id)
		if l <= 0:
			continue
		var box := UiKit.vbox(0)
		box.add_child(StoryCard.picture(String(Saga.SKILLS[id].pic), 34.0, Saga.SKILLS[id].color))
		var dots := UiKit.hbox(2)
		dots.alignment = BoxContainer.ALIGNMENT_CENTER
		for k in l:
			dots.add_child(UiKit.icon("dot", "gold", 9.0))
		box.add_child(dots)
		skill_row.add_child(box)
	if bool(net.state_get("hard", false)):
		skill_row.add_child(UiKit.icon("fire", Color(1.0, 0.5, 0.2), 34.0))


## TV: the quest log card (top right) while the party is in the region (zones 1..3).
func _refresh_quest_card() -> void:
	if quest_card == null:
		return
	for c in quest_card.get_children():
		c.queue_free()
	var q: Dictionary = plan.get("quest", {})
	var z := int(net.state_get("zone", 0))
	var ph := String(net.state_get("phase", ""))
	quest_card.visible = not q.is_empty() and z in [1, 2, 3] and ph != "results"
	if not quest_card.visible:
		return
	var row := UiKit.hbox(6)
	quest_card.add_child(row)
	row.add_child(StoryCard.picture(String(q.giver_pic), 40.0, Saga.LUMI_COLOR))
	row.add_child(StoryCard.picture(String(q.item_pic), 40.0, Color(1.0, 0.85, 0.4)))
	var found := int(net.state_get("quest", 0))
	var need := int(q.need)
	if found >= need:
		row.add_child(UiKit.icon("check", "gold", 30.0))
	else:
		var dots := UiKit.hbox(3)
		dots.alignment = BoxContainer.ALIGNMENT_CENTER
		for k in need:
			dots.add_child(UiKit.icon("dot", "gold" if k < found else "dim", 14.0))
		row.add_child(dots)


## TV: the realm map while the map stones are up: every region's picture where it sits, roads between them,
## a star on beaten ones, dim ones not reached yet (no words).
func _map_card(on: bool) -> void:
	if map_card != null and is_instance_valid(map_card):
		map_card.queue_free()
	map_card = null
	if not on or hud == null or realm.is_empty():
		return
	var rs: Array = net.state_get("realm", [0, []])
	var cleared: Array = rs[1] if rs.size() > 1 else []
	var open := Realm.open_slots(realm, cleared)
	var card := UiKit.panel("card")
	hud.add_child(card)
	var box := Control.new()
	var w := 300.0
	var h := 230.0
	box.custom_minimum_size = Vector2(w, h)
	card.add_child(box)
	UiKit.pin(card, Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.offset_top = 96.0
	card.offset_bottom = 96.0
	var spot := func(i: int) -> Vector2:
		if i < 0:
			return Vector2(w * 0.5, h - 18.0)
		return Vector2(w * 0.5 + float(realm.regions[i].x) * w * 0.4, h - 18.0 - int(realm.regions[i].depth) * (h - 40.0) / 4.0)
	for i in Realm.SIZE:
		var links: Array = (realm.regions[i].links as Array).duplicate()
		if int(realm.regions[i].depth) == 1:
			links.append(-1)
		for j in links:
			if int(j) < i:
				var ln := Line2D.new()
				ln.width = 4.0
				ln.default_color = Color(0.95, 0.85, 0.55, 0.8)
				ln.points = PackedVector2Array([spot.call(i), spot.call(int(j))])
				box.add_child(ln)
	var home := StoryCard.picture("house", 34.0, Color(1.0, 0.85, 0.5))
	box.add_child(home)
	home.position = spot.call(-1) - Vector2(17.0, 17.0)
	var off: Array = net.state_get("offer", [])
	for i2 in Realm.SIZE:
		var bio := Realm.biome(realm, i2)
		var pic := StoryCard.picture(String(bio.pic), 38.0, bio.glow)
		box.add_child(pic)
		pic.position = spot.call(i2) - Vector2(19.0, 19.0)
		if not open.has(i2):
			pic.modulate = Color(0.35, 0.35, 0.4, 0.8)
		if cleared.has(i2):
			var st := UiKit.icon("star", "gold", 18.0)
			box.add_child(st)
			st.position = spot.call(i2) + Vector2(8.0, -24.0)
		if off.slice(1).has(i2):
			var ring := UiKit.icon("arrow_down", "gold", 18.0)
			box.add_child(ring)
			ring.position = spot.call(i2) + Vector2(-9.0, -40.0)
	map_card = card


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
	if world == null:
		return
	match key:
		"plan":
			if net.mode == "client" and value is Array:
				var pl: Array = value
				var bio := int(pl[3]) if pl.size() > 3 else 1
				if int(pl[0]) != int(plan.get("seed", -1)) or int(pl[1]) != int(plan.get("tier", -1)) or bio != int(plan.get("biome", -1)) \
						or (pl.size() > 5 and bool(pl[5]) != bool(plan.get("hard", false))):
					_plan_from_state()
					_make_world()
					_apply_world_state()
				journey.daily = bool(pl[2])
				journey.region = int(pl[6]) if pl.size() > 6 else 0
			_refresh_hud()
		"realm":
			_realm_state()
		"classes":
			for hs in heroes:
				(heroes[hs] as Hero).set_class(_class_of(int(hs)))
				_hero_gear(heroes[hs] as Hero)
		"quest":
			world.set_quest_count(int(value))
			_refresh_hud()
		"used2":
			world.set_used(int(net.state_get("used", 0)), int(value))
		"hard", "brave_ok":
			world.set_brave(bool(net.state_get("hard", false)), bool(net.state_get("brave_ok", false)))
			_refresh_hud()
		"village":
			world.set_village(int(value), String(net.state_get("phase", "")) in ["restore", "yay", "results"])
			world.set_heroes_unlocked(Classes.unlocked(int(value)))
		"offer":
			_show_offer()
		"skills", "shards":
			_refresh_hud()
			if key == "skills":
				for hs2 in heroes:
					_hero_gear(heroes[hs2] as Hero)
		"open":
			world.set_open(int(value))
			_refresh_hud()
		"used":
			world.set_used(int(value), int(net.state_get("used2", 0)))
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
			_map_card(ph == "map")
			if ph == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
			var z := int(net.state_get("zone", 0))
			match ph:
				"practice":
					music.play_mood(MOODS[0])
					if split != null:
						HudKit.banner([hud], _zone_name(0), "", {"duration": 2.0})
					if vr_rig != null:
						get_tree().create_timer(4.0).timeout.connect(func() -> void:
							if String(net.state_get("phase", "")) == "practice" and not world.is_used(world.dummy_id):
								show_headline("SWING!", 6.0))
				"fight", "boss", "crystal":
					music.play_mood(MOODS[z])
					if split != null:
						HudKit.banner([hud], _zone_name(z), "", {"duration": 1.8})
					show_headline(_zone_name(z))
				"orb":
					show_headline("TOUCH THE ORB!" if not world.is_used(world.orb_id) else "SWORD UP!", 5.0)
				"choose":
					show_headline("PICK ONE!", 6.0)
					if split != null:
						HudKit.banner([hud], "LEVEL UP!", "", {"duration": 2.0})
				"map":
					show_headline("WHERE TO?", 6.0)
					if split != null:
						HudKit.banner([hud], "WHERE TO?", "", {"duration": 2.0})
				"cleared":
					show_headline("ONWARD!", 2.5)
				"restore":
					music.play_mood("victory")
					if split != null:
						HudKit.banner([hud], "LIGHT!", "", {"duration": 3.0})
				"yay":
					show_headline("HOORAY!", 5.0)


func _zone_name(z: int) -> String:
	var names: Array = plan.get("names", [])
	if z == 0 and bool(journey.get("daily", false)):
		return Saga.DAILY_NAME
	return String(names[z]) if z < names.size() else ""


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
			UiKit.pin(tv_banner, Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


# --- Story and telemetry -------------------------------------------------------------------------

func _lumi(line: String, pic: String = "lumi") -> Dictionary:
	return {"who": Saga.LUMI, "line": line, "pic": pic, "color": Saga.LUMI_COLOR, "duration": 3.5}


## Host: a story beat in its turn (now: straight away, ahead of the rest).
func _say(beat: Dictionary, now: bool = false) -> void:
	if now:
		story_q.push_front(beat)
		story_t = 0.0
	else:
		story_q.append(beat)


## Host: show a beat on every machine.
func _story(beat: Dictionary) -> void:
	if net.mode == "host":
		net.event("story", [beat.get("who", ""), beat.get("line", ""), beat.get("pic", ""), (beat.get("color", Saga.LUMI_COLOR) as Color).to_html()])
	show_story(beat)


func show_story(beat: Dictionary) -> void:
	stories_shown += 1
	if hud != null:
		StoryCard.show([hud], beat)
	if vr_rig != null:
		if vr_story != null and is_instance_valid(vr_story):
			vr_story.queue_free()
		vr_story = StoryCard.show_vr(self, vr_rig.camera, beat)


## Host: one RUN line per journey (or a quit mid-journey): how the family really plays.
func _telemetry(end: String) -> void:
	if not tel_open or net == null or net.mode == "client":
		return
	tel_open = false
	var poofs := 0
	for s in log_hits:
		poofs += int(log_hits[s])
	Telemetry.run(GAME_ID, {"end": end, "journey": journeys_done, "seed": int(journey.get("seed", 0)), "tier": int(journey.get("tier", 0)),
		"daily": bool(journey.get("daily", false)), "secs": snappedf(journey_t, 0.1), "zone": int(net.state_get("zone", 0)),
		"team": _team(), "vr": vr_rig != null, "mode": String(net.mode), "hits": poofs - int(tel_base[0]), "dizzy": log_dizzy - int(tel_base[1]),
		"knocks": log_knocks - int(tel_base[2]), "stomps": log_stomps - int(tel_base[3]), "shards": journey_shards, "shards_total": int(save.data.shards), "village": int(net.state_get("village", 0)),
		"picks": picks, "level": Saga.party_level(save.data.skills), "names": plan.get("names", []),
		"region": int(journey.get("region", 0)), "biome": String(Realm.BIOMES[int(plan.get("biome", 1))].id), "hard": _hard(),
		"quest": int(net.state_get("quest", 0)), "quest_need": int((plan.get("quest", {}) as Dictionary).get("need", 0)),
		"tells": _tells_this_journey(), "attacks": (plan.get("guardian", {}) as Dictionary).get("attacks", []),
		"classes": net.state_get("classes", {}), "cleared": (save.data.cleared as Array).size()})
	runs_logged += 1


func _tells_this_journey() -> Dictionary:
	var out := {}
	for k in log_tells:
		var n := int(log_tells[k]) - int(tel_tells.get(k, 0))
		if n > 0:
			out[k] = n
	return out


func _exit_tree() -> void:
	if net != null and ready_to_play and String(net.state_get("phase", "")) != "results" and journey_t > 5.0:
		_telemetry("quit")  # (not for a peek: opened and left at once)


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
	if split != null and (s[0] as PackedFloat32Array).is_empty():
		split.clear_bubble()  # a flat host: no VR player to show in the bubble
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
		"tell":
			monsters.show_tell(String(args[0]), args[1], float(args[2]))
		"wake":
			var h5: Hero = heroes.get(int(args[0]))
			if h5 != null:
				h5.wake()
		"story":
			show_story({"who": String(args[0]), "line": String(args[1]), "pic": String(args[2]), "color": Color.html(String(args[3])), "duration": 3.5})
