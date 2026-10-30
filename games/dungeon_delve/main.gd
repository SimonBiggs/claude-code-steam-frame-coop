extends Node3D
## DUNGEON DELVE: a little dungeon full of cute monsters, a few short rooms in a row.
## - The VR player (slot 0, host) is the KNIGHT, inside the dungeon at full size, with a big toy
##   sword in the right hand: swing it through slimes and bats and they poof into confetti. The left
##   hand picks up pots by touching them (flick to throw). Left stick walks, right stick snap-turns.
## - TV players (slots 1..6, or 0 too in local play without a headset) are little HEROES seen from
##   above: left stick walks, A bonks whatever is in front of them (monsters, pots, chests...).
## - Clear a room and a golden key flies into the gate, the gate opens, walk on into the next room.
##   One new thing per room: practice, slimes, bats (they swoop low for the heroes), the Slime King
##   (he gets smaller with every bop), then the treasure room: open the big chest, everyone cheers.
## - No failure: a slime bump just makes a hero dizzy for two seconds; no numbers: gold keys show
##   how far you got.
## - PRACTICE: the knight gets a glowing straw dummy and a ghost hand swinging a sword through it
##   (ghost_hand.gd); the heroes get one glowing pot to bonk.
## - Everything in reach does something: pots, torches, chests, a friendly skeleton (dungeon.gd).
## - Text: VR gets one short headline on the far wall; the TV shows one short line at most.
## Modes as in games/engine_template: local (one shared TV view), host (VR on the Steam Frame,
## simulates everything), client (the TV machine: mirrors the host, moves its own heroes).
## DIFFICULTY: all of the above is GENTLE. The practice room also has an orange BRAVE and a red
## HEROIC pad: stand on one until it fills and the deep dungeon starts (deep.gd: procedural floors,
## hearts, knock-outs and revives, keys, puzzles, traps, monsters with tells, three bosses, loot, a
## shop, unlocks saved between runs). Env DD_MODE=brave|heroic starts there (tests, launchers),
## DD_FLOOR=n on floor n (0..11), DD_SEED=n a fixed dungeon.

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
const Dungeon := preload("res://games/dungeon_delve/dungeon.gd")
const Monsters := preload("res://games/dungeon_delve/monsters.gd")
const Hero := preload("res://games/dungeon_delve/hero.gd")
const VrHands := preload("res://games/dungeon_delve/vr_hands.gd")
const GhostHand := preload("res://games/dungeon_delve/ghost_hand.gd")
const Deep := preload("res://games/dungeon_delve/deep.gd")

const GAME_ID := "dungeon_delve"
const StoryCard := preload("res://core/story_card.gd")
const CINDER_COLOR := "ff9a40"  ## Cinder, the baby dragon who keeps the dungeon's treasure (story_pictures.gd cinder)
const NAMES: Array[String] = ["DUNGEON DELVE", "SLIMES!", "BATS!", "SLIME KING!", "TREASURE!"]
const MOODS: Array[String] = ["town", "overworld", "overworld", "party", "town"]
const GATES := Dungeon.ROOMS - 1
const BONK_REACH := 0.7

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

var dungeon: Dungeon
var monsters: Monsters
var deep: Deep  ## BRAVE / HEROIC (every machine)
var heroes := {}  ## slot -> Hero (every machine)
var hands: VrHands
var ghost: GhostHand
var avatar: VrRig.Avatar
var arrow: Node3D  ## glowing arrow at the open gate
var blink_mat: StandardMaterial3D

# Host
var pot_fly := {}  ## prop id -> {"p", "v"}
var poke_cd := {}  ## prop id -> seconds
var phase_t := 0.0
var open_t := -1.0
var straggle_t := -1.0
var send_t := 0.0
var log_bops := {}  ## bots: slot -> monsters bopped
var log_pokes := {}  ## bots: prop kind -> pokes
var log_rooms := {}  ## bots: rooms entered
var log_dizzy := 0
var log_throws := 0
var story_count := 0  ## story cards shown on this machine (bots)

# TV
var hud: Control
var key_row: HBoxContainer
var pill: Control
var pill_text := ""
var bonked := {}  ## slot -> true once they bonked (the "A Bonk!" pill goes away)
var results_ui: Control
var tv_banner: Control
var cam_z := 0.0
var deep_cam := Vector3.ZERO
var deep_cam_h := 12.0
var shake := 0.0
var _moved_pots := {}

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
	save.defaults = {"treasures": 0, "daily": ""}  # daily: the date TODAY'S DUNGEON was last played (deep.gd finish)
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
	music.prepare(["victory", "overworld", "party"])
	awards = Awards.new()
	awards.define("bopper", "SLIME BOPPER", "%s monsters bopped", "bops")
	awards.define("smasher", "POT SMASHER", "%s pots smashed", "pots")
	awards.define("pal", "SKELETON PAL", "%s bony rattles", "rattles")
	awards.define("finder", "TREASURE FINDER", "%s chests opened", "chests")
	awards.define("helper", "BEST BUDDY", "%s seconds helping friends up", "helps")
	awards.define("rich", "GOLD DIGGER", "%s gold found", "gold")
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	dungeon = Dungeon.new()
	dungeon.name = "Dungeon"
	add_child(dungeon)
	dungeon.build()
	monsters = Monsters.new()
	monsters.name = "Monsters"
	add_child(monsters)
	var flat: bool = mode == "host" and not net.has_vr  # flat host (TV / Deck hosting): slot 0 is a pad player here
	if VrRig.wanted(mode) and not flat:
		vr_rig = VrRig.new()
		vr_rig.move_speed = 1.8
		vr_rig.turn_mode = "snap"
		vr_rig.move_filter = func(from: Vector3, to: Vector3) -> Vector3: return walk_clamp(from, to, 0.25)
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, 2.9), 0.0)
		hands = VrHands.new()
		add_child(hands)
		hands.setup(self, vr_rig)
		ghost = GhostHand.new()
		add_child(ghost)
		_build_blink()
	sky = SkyKit.apply(self, "dungeon", vr_rig != null)
	sky.env.ambient_light_energy = 1.2
	_build_arrow()
	if mode != "host" or vr_rig == null:
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		split.set_shared(true)
		split.shared_camera().fov = 55.0
		_make_hud(split.shared_hud())
		if mode == "client":
			avatar = VrRig.Avatar.new()
			add_child(avatar)
			var sw := MeshKit.instance(VrHands.sword_mesh(), false)
			avatar.hands[1].add_child(sw)
			split.set_bubble(VrRig.build_mirror(self, avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode != "client" and vr_rig == null
	deep = Deep.new()
	deep.name = "Deep"
	add_child(deep)
	deep.setup(self)
	if mode != "client":
		net.state_set("vr", vr_rig != null)
		_start_show()
	else:
		dungeon.set_open(int(net.state_get("open", 0)))
		dungeon.set_used(int(net.state_get("used", 0)))
		for k in net.state_all():
			deep.on_state(String(k), net.state_get(String(k)))  # a late joiner: build the deep floor now
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Dungeon Delve: %s mode%s" % [mode, " with a VR knight" if vr_rig != null else ""])


# --- The show (host / local) ---------------------------------------------------------------------

func _start_show() -> void:
	if deep.active:
		deep.stop()
	net.state_set("mode", "gentle")
	awards.reset()
	if vr_rig != null:
		awards.set_player(0, "KNIGHT")
	for s in heroes:
		awards.set_player(int(s), party.name_of(int(s)))
	monsters.clear()
	pot_fly.clear()
	if hands != null:
		hands.reset()
	var first := 0
	if OS.has_environment("DD_ROOM") and not has_meta("started"):
		first = clampi(int(OS.get_environment("DD_ROOM")), 0, Dungeon.ROOMS - 1)
	var used := 0
	if vr_rig == null or first > 0:
		used |= 1 << dungeon.dummy_id
	if first > 0:
		used |= 1  # the practice pot
	set_meta("started", true)
	net.state_set("used", used)
	net.state_set("open", first)
	var at := Dungeon.entrance(first)
	if vr_rig != null:
		if has_meta("shown"):
			blink(func() -> void: vr_rig.place(at + Vector3(0.0, 0.0, -0.3) if first > 0 else Vector3(0.0, 0.0, 2.9), 0.0))
		elif first > 0:
			vr_rig.place(at + Vector3(0.0, 0.0, -0.3), 0.0)
	if not has_meta("shown"):  # Cinder says hello once a session, after the DUNGEON DELVE banner
		get_tree().create_timer(2.2).timeout.connect(func() -> void:
			story({"who": "HI! I'M CINDER!", "line": "Find my treasure!", "pic": "cinder", "color": CINDER_COLOR, "duration": 3.5}))
	set_meta("shown", true)
	for s in heroes:
		_warp_hero(int(s), at)
	_enter_room(first)
	# DD_MODE (tests, launchers: also opens HEROIC) or DD_TRY (the arcade's What's New "try this": just the jump,
	# HEROIC stays locked until the Slime King falls).
	var try_mode := OS.get_environment("DD_MODE") if OS.has_environment("DD_MODE") else OS.get_environment("DD_TRY")
	if try_mode != "" and not has_meta("deep_mode_started"):
		set_meta("deep_mode_started", true)
		var dm := try_mode
		if dm in ["brave", "daily"] or (dm == "heroic" and (OS.has_environment("DD_MODE") or deep.heroic_unlocked())):
			deep.start_run(dm)


## Bodies stay inside whichever dungeon is on (gentle rooms or a deep floor).
func walk_clamp(from: Vector3, to: Vector3, r: float) -> Vector3:
	if deep != null and deep.active:
		if vr_rig != null and r == 0.25 and not deep._alive(0) and deep.stats.has(0):
			return from  # a knocked-out knight waits for a friend
		return deep.view.clamp(from, to, r)
	return dungeon.walk_clamp(from, to, r)


func _enter_room(r: int) -> void:
	log_rooms[r] = true
	net.state_set("room", r)
	net.state_set("spawn", Dungeon.entrance(r))
	straggle_t = 3.5 if r > 0 else -1.0
	phase_t = 0.0
	var c := Dungeon.center(r)
	var n := heroes.size()
	match r:
		0:
			net.state_set("phase", "practice")
		1:
			for i in clampi(3 + n, 4, 8):
				monsters.spawn(Monsters.SLIME, c + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.5, -0.5)), r)
			net.state_set("phase", "fight")
		2:
			for i in clampi(3 + n / 2, 3, 6):
				monsters.spawn(Monsters.BAT, c + Vector3(randf_range(-2.5, 2.5), 1.7, randf_range(-2.5, 1.0)), r)
			for i in 2:
				monsters.spawn(Monsters.SLIME, c + Vector3(randf_range(-3.0, 3.0), 0.0, -3.0), r)
			net.state_set("phase", "fight")
		3:
			monsters.spawn(Monsters.KING, c + Vector3(0.0, 0.0, -1.5), r)
			net.state_set("phase", "fight")
		_:
			net.state_set("phase", "treasure")


func _room_cleared() -> void:
	var r := int(net.state_get("room", 0))
	net.state_set("phase", "cleared")
	open_t = 1.4
	var from := Dungeon.center(r) + Vector3(0.0, 1.6, 0.0)
	var to := Vector3(0.0, 0.95, Dungeon.wall_z(r) + 0.15)
	key_fx(from, to)
	net.event("key", [from, to])
	sound_at("fanfare", from, -4.0)
	sound_at("sparkle", from, -4.0)
	_pulse_both(0.5, 0.15)


func _open_treasure(id: int) -> void:
	net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
	_react(id)
	var p := dungeon.prop_center(id)
	for k in 3:
		confetti(p + Vector3(0, 0.6 + k * 0.4, 0), Color(1.0, 0.85, 0.2), 60)
	net.event("gold", [p])
	sound_at("chest", p, 0.0)
	sound_at("fanfare", p, -2.0)
	sound_at("cheer", p, -2.0)
	sound_at("applause", p, -6.0)
	_pulse_both(0.7, 0.3)
	net.state_set("phase", "yay")
	phase_t = 0.0
	save.data["treasures"] = int(save.data["treasures"]) + 1
	save.mark_dirty()
	story({"who": "CINDER", "line": "For you! Yay!", "pic": "cinder", "color": "ffd25a", "duration": 3.5})
	for s in heroes:
		net.event("cheer", [int(s)])
		(heroes[s] as Hero).anim.play("cheer", 2.0)


## Host: a picture card on every machine (a word or two and one short line: no how-to text).
func story(beat: Dictionary) -> void:
	show_story(beat)
	if net.mode == "host":
		net.event("story", [beat])


func show_story(beat: Dictionary) -> void:
	story_count += 1
	var opts := beat.duplicate()
	opts["color"] = Color.html(String(beat.get("color", "ffd25a")))
	if hud != null and is_instance_valid(hud):
		StoryCard.show([hud], opts)
	if vr_rig != null and vr_rig.camera != null:
		StoryCard.show_vr(self, vr_rig.camera, opts)
	print("Story card: %s - %s" % [String(beat.get("who", "")), String(beat.get("line", ""))])


func _results() -> void:
	end_results("TREASURE!", "victory", "")


## Host: the results screen (the gentle treasure, or the end of a deep run).
func end_results(title: String, style: String, subtitle: String, team: Array = []) -> void:
	var opts := {"title": title, "style": style, "score_stat": "bops", "score_format": "%d BOPS", "continue": "Again!", "stats": team}
	if subtitle != "":
		opts["subtitle"] = subtitle
	var data := awards.results(opts)
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


# --- Host rules ----------------------------------------------------------------------------------

func _host_step(delta: float) -> void:
	var phase := String(net.state_get("phase", ""))
	var room := int(net.state_get("room", 0))
	if deep.active and phase != "results":
		deep.host_step(delta)
		return
	if phase in ["practice", "cleared"] and room == 0 and not deep.active:
		deep.lobby_step(delta)
	if phase == "results" and vr_rig != null and phase_t > 4.0 and (vr_rig.a_pressed() or vr_rig.trigger_pressed()) and deep.active:
		on_request(0, "again", [])
		return
	phase_t += delta
	for k in poke_cd.keys():
		poke_cd[k] = float(poke_cd[k]) - delta
		if float(poke_cd[k]) <= 0.0:
			poke_cd.erase(k)
	if hands != null:
		hands.update(delta)
		_ghost(delta, phase)
	# Monsters chase heroes and the knight; bumps make heroes dizzy.
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
		var mp: Vector3 = monsters.mons[b[0]]["p"]
		if key < 0:
			sound_at("boing", mp, -4.0, 1.3)
			_pulse_both(0.3, 0.08)
		elif heroes.has(key) and (heroes[key] as Hero).dizzy_t <= 0.0:
			log_dizzy += 1
			(heroes[key] as Hero).get_dizzy()
			net.event("dizzy", [key])
			sound_at("boing", mp, -2.0, 0.8)
			sound_at("faint", mp, -10.0, 1.3)
	_step_pots(delta)
	# Rooms.
	match phase:
		"practice":
			var knight_ok := vr_rig == null or dungeon.is_used(dungeon.dummy_id)
			var heroes_ok := heroes.is_empty() or dungeon.is_used(0)
			if knight_ok and heroes_ok and (vr_rig != null or not heroes.is_empty()) and phase_t > 1.0:
				_room_cleared()
		"fight":
			if monsters.count() == 0 and phase_t > 0.5:
				_room_cleared()
		"cleared":
			if open_t > 0.0:
				open_t -= delta
				if open_t <= 0.0:
					net.state_set("open", room + 1)
					sound_at("door", Vector3(0.0, 1.0, Dungeon.wall_z(room)), 0.0)
			elif int(net.state_get("open", 0)) > room:
				for p in _player_feet():
					if (p as Vector3).z < Dungeon.wall_z(room) - 0.8:
						_enter_room(room + 1)
						break
		"yay":
			if phase_t > 4.0:
				_results()
		"results":
			if phase_t > 60.0:
				_start_show()
	# Stragglers catch up (a pop for heroes, a blink for the knight).
	if straggle_t > 0.0:
		straggle_t -= delta
		if straggle_t <= 0.0:
			var at := Dungeon.entrance(room)
			for s in heroes:
				if Dungeon.room_of((heroes[s] as Hero).position) < room:
					_warp_hero(int(s), at)
			if vr_rig != null and Dungeon.room_of(vr_rig.head_position()) < room:
				blink(func() -> void: vr_rig.place(at + Vector3(0.0, 0.0, -0.3), 0.0))


func _player_feet() -> Array:
	var out: Array = []
	for s in heroes:
		out.append((heroes[s] as Hero).position)
	if vr_rig != null:
		out.append(vr_rig.head_position())
	return out


func _ghost(delta: float, phase: String) -> void:
	var on := false
	var target := Vector3.ZERO
	if phase == "practice" and not dungeon.is_used(dungeon.dummy_id) and phase_t > 1.0:
		on = true
		target = dungeon.prop_center(dungeon.dummy_id)
	elif phase == "fight" and hands.idle_t > 25.0 and monsters.count() > 0:
		var best := INF
		for id in monsters.mons:
			var c: Vector3 = monsters.center_of(id)
			var d := c.distance_to(vr_rig.head_position())
			if d < best:
				best = d
				target = c
		on = best < 4.0
	ghost.show_demo(on, target, vr_rig.head_position(), delta)


## Host: bop a monster (slot 0 = the knight, -1 = a thrown pot). Returns true if it counted.
func hit_monster(id: int, slot: int, at: Vector3) -> bool:
	if not monsters.mons.has(id):
		return false
	var kind: int = monsters.mons[id]["kind"]
	var room: int = monsters.mons[id]["room"]
	var res := monsters.hit(id)
	if res == "":
		return false
	var who := maxi(slot, 0)
	log_bops[slot] = int(log_bops.get(slot, 0)) + 1
	awards.add(who, "bops")
	if res == "poof":
		var col := Color(0.6, 0.9, 1.0) if kind == Monsters.KING else Color(0.6, 1.0, 0.6)
		var n := 90 if kind == Monsters.KING else 36
		poof_fx(at, col, n)
		net.event("poof", [at, col, n])
		sound_at("pop", at, 0.0, randf_range(0.9, 1.15))
		sound_at("sparkle", at, -6.0)
		if kind == Monsters.KING:
			sound_at("party_horn", at, -2.0)
			sound_at("cheer", at, -4.0)
	else:
		sound_at("boing", at, 0.0, 0.7)
		sound_at("sword_hit", at, -8.0, 1.3)
		poof_fx(at, Color(0.6, 0.9, 1.0), 14)
		net.event("poof", [at, Color(0.6, 0.9, 1.0), 14])
		var hits: int = monsters.mons[id]["hits"]
		if hits == 2 or hits == 4:
			var mp: Vector3 = monsters.mons[id]["p"]
			monsters.spawn(Monsters.SLIME, Dungeon.room_clamp(mp + Vector3(randf_range(-1.5, 1.5), 0.0, 1.2), room, 0.4), room)
			sound_at("spit", mp, -4.0, 1.4)
	return true


## Host: someone poked a prop (sword, hand, or a hero's bonk). Returns true if something happened.
func prop_poke(id: int, slot: int) -> bool:
	var p: Dictionary = dungeon.props[id]
	var kind: int = p["kind"]
	var c := dungeon.prop_center(id)
	var phase := String(net.state_get("phase", ""))
	if kind == Dungeon.BIG:
		if phase == "treasure" and not dungeon.is_used(id):
			_open_treasure(id)
			return true
		if phase == "results" and phase_t > 3.0:
			on_request(slot, "again", [])
			return true
		return false
	if poke_cd.has(id) or (dungeon.is_used(id) and kind in [Dungeon.POT, Dungeon.CHEST]):
		return false
	poke_cd[id] = 0.6
	log_pokes[kind] = int(log_pokes.get(kind, 0)) + 1
	var who := maxi(slot, 0)
	match kind:
		Dungeon.POT:
			_break_pot(id, c)
			awards.add(who, "pots")
			return true
		Dungeon.TORCH:
			sound_at("fire", c, -4.0, 1.2)
			sound_at("whoosh", c, -6.0, 0.8)
		Dungeon.CHEST:
			net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
			confetti(c + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.2), 40)
			net.event("confetti", [c + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.2), 40])
			sound_at("chest", c, -2.0)
			sound_at("coin", c, -4.0)
			awards.add(who, "chests")
		Dungeon.SKEL:
			poke_cd[id] = 1.2
			sound_at("dice", c, -2.0, 1.4)
			sound_at("tock", c, -6.0, 1.6)
			sound_at("boing", c, -10.0, 1.8)
			awards.add(who, "rattles")
		Dungeon.DUMMY:
			sound_at("sword_hit", c, -4.0)
			sound_at("boing", c, -6.0, 1.2)
			if slot == 0 and not dungeon.is_used(id):
				net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
				confetti(c, Color(1.0, 0.85, 0.3), 30)
				net.event("confetti", [c, Color(1.0, 0.85, 0.3), 30])
				show_headline("YES!", 2.0)
				sound_at("ding", c, -2.0, 1.2)
	_react(id)
	return true


func _react(id: int) -> void:
	dungeon.react(id)
	net.event("prop", [id])


func _break_pot(id: int, at: Vector3) -> void:
	pot_fly.erase(id)
	if hands != null and hands.held_pot == id:
		hands.held_pot = -1
	net.state_set("used", int(net.state_get("used", 0)) | (1 << id))
	confetti(at, Color(0.95, 0.55, 0.35), 36)
	net.event("confetti", [at, Color(0.95, 0.55, 0.35), 36])
	sound_at("crash", at, -10.0, 1.6)
	sound_at("pop", at, -4.0, 0.8)
	sound_at("sparkle", at, -8.0)


## Host: the knight flicked a pot.
func throw_pot(id: int, from: Vector3, v: Vector3) -> void:
	log_throws += 1
	pot_fly[id] = {"p": from, "v": v.limit_length(9.0)}
	sound_at("whoosh", from, -4.0, 1.2)


func _step_pots(delta: float) -> void:
	for id in pot_fly.keys():
		var f: Dictionary = pot_fly[id]
		var v: Vector3 = f["v"]
		var p: Vector3 = f["p"]
		v.y -= 9.8 * delta
		var np := p + v * delta
		var kept := dungeon.walk_clamp(p, np, 0.15)
		var smash := np.y < 0.12 or Vector2(kept.x - np.x, kept.z - np.z).length() > 0.01
		for mid in monsters.mons.keys():
			var c: Vector3 = monsters.center_of(mid)
			if c.distance_to(np) < monsters.radius_of(mid) + 0.25:
				hit_monster(int(mid), -1, c)
				smash = true
				break
		f["v"] = v
		f["p"] = np
		(dungeon.props[id]["node"] as Node3D).global_position = np
		if smash:
			_break_pot(int(id), np)


## Host / local: a player asked for something (from any machine).
func on_request(slot: int, action: String, args: Array) -> void:
	if action != "again" and deep.active:
		deep.on_request(slot, action, args)
		return
	match action:
		"bonk":
			if args.size() >= 2:
				_bonk(slot, args[0], float(args[1]))
		"again":
			if String(net.state_get("phase", "")) == "results":
				_start_show()


## Host: a hero bonks what's in front of them (generous: anything within reach, low enough).
func _bonk(slot: int, pos: Vector3, yaw: float) -> void:
	if deep.try_hat(slot, pos + Vector3(sin(yaw), 0.0, cos(yaw)) * 0.6):
		net.event("bonk", [slot])
		return
	net.event("bonk", [slot])
	if heroes.has(slot) and not party.is_local(slot):
		(heroes[slot] as Hero).bonk_anim()
	var at := pos + Vector3(sin(yaw), 0.0, cos(yaw)) * BONK_REACH
	var hit := false
	for id in monsters.mons.keys():
		var c: Vector3 = monsters.center_of(id)
		if c.y < 1.5 and Vector2(c.x - at.x, c.z - at.z).length() < 0.6 + monsters.radius_of(id) * 0.6:
			hit = hit_monster(int(id), slot, c) or hit
	var room := Dungeon.room_of(pos)
	for id in dungeon.props.size():
		var p: Dictionary = dungeon.props[id]
		if absi(int(p["room"]) - room) > 1 or pot_fly.has(id) or (hands != null and hands.held_pot == id):
			continue
		var c2 := dungeon.prop_center(id)
		if c2.y < 2.0 and Vector2(c2.x - at.x, c2.z - at.z).length() < float(p["r"]) + 0.5:
			hit = prop_poke(id, slot) or hit
	if not hit:
		sound_at("swish", at, -10.0, randf_range(1.1, 1.3))


func _warp_hero(slot: int, at: Vector3) -> void:
	var p := at + _spawn_offset(slot)
	if party.is_local(slot) and heroes.has(slot):
		(heroes[slot] as Hero).position = p
	net.event("warp", [slot, p])
	poof_fx(p + Vector3(0, 0.5, 0), party.color_of(slot), 16)
	net.event("poof", [p + Vector3(0, 0.5, 0), party.color_of(slot), 16])


static func _spawn_offset(slot: int) -> Vector3:
	var xs: Array[float] = [0.0, -1.3, 1.3, -2.1, 2.1, -2.9, 2.9]
	return Vector3(xs[slot % xs.size()], 0.0, 0.5 if slot % 2 == 0 else 0.2)


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
	deep.process(delta)
	if net.mode != "client":
		deep.host_visuals()
	var focus := int(net.state_get("room", 0))
	if not deep.active:
		dungeon.animate(delta, focus)
	_animate_arrow(delta)
	_headline(delta)
	var big: Node3D = dungeon.props[dungeon.big_id]["node"]
	big.scale = Vector3.ONE * (2.0 + (0.08 * sin(Time.get_ticks_msec() * 0.006) if results_showing() else 0.0))
	if split != null:
		_tv_camera(delta)
		_update_pill()


## Heroes for every TV seat (not slot 0 when a VR knight plays).
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
			var sp: Vector3 = net.state_get("spawn", Dungeon.entrance(0))
			if deep.active and not deep.f.is_empty():
				sp = deep.FloorGen.room_center(deep.f, maxi(0, deep._focus_room()))
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
	var clamp := func(from: Vector3, to: Vector3) -> Vector3: return dungeon.walk_clamp(from, to, Hero.RADIUS)
	for s in heroes:
		var h: Hero = heroes[s]
		h.owned = party.is_local(int(s))
		if not h.owned:
			continue
		if deep.active:
			deep.owned_input(delta, h, int(s))
			continue
		var mv := party.stick(int(s), "move") if can_move else Vector2.ZERO
		var dir := Vector3(mv.x, 0.0, mv.y)
		if dir.length() < 0.15:
			dir = Vector3.ZERO
		h.step(delta, dir.limit_length(1.0), clamp)
		if can_move and h.dizzy_t <= 0.0 and h.bonk_cd <= 0.0 and (party.just_pressed(int(s), "accept") or party.just_pressed(int(s), "rt")):
			h.bonk_cd = 0.3
			h.bonk_anim()
			bonked[int(s)] = true
			party.rumble(int(s), 0.2, 0.0, 0.06)
			net.request(int(s), "bonk", [h.position, h.rotation.y])
	send_t -= delta
	if net.mode == "client" and send_t <= 0.0:
		send_t = 1.0 / 30.0
		for s in heroes:
			var h2: Hero = heroes[s]
			if h2.owned:
				net.send_state(h2.position, h2.rotation.y, 1.0 if h2.dizzy_t > 0.0 else 0.0, int(s))


## Host: a TV machine's hero moved (the host decides dizziness itself).
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if heroes.has(slot):
		var h: Hero = heroes[slot]
		h.set_remote(pos, yaw, h.dizzy_t > 0.0)


func _on_player_joined(slot: int, _device: int) -> void:
	sfx.play("ui_notify", -6.0)


func _tv_camera(delta: float) -> void:
	if deep.active and not deep.f.is_empty():
		var ct: Array = deep.camera_target()
		var want_at: Vector3 = ct[0]
		var hgt: float = ct[1]
		deep_cam = deep_cam.lerp(want_at, 1.0 - exp(-3.0 * delta)) if deep_cam.distance_to(want_at) < 20.0 else want_at
		deep_cam_h = lerpf(deep_cam_h, hgt, 1.0 - exp(-2.0 * delta))
		var cam2 := split.shared_camera()
		var p2 := deep_cam + Vector3(0.0, deep_cam_h, deep_cam_h * 0.5)
		cam2.global_transform = Transform3D(UiKit.face(deep_cam + Vector3(0.0, 0.0, -0.3) - p2), p2)
		shake = maxf(0.0, shake - delta * 2.0)
		if shake > 0.0:
			cam2.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.15
		return
	var zs := 0.0
	var n := 0
	for h in heroes.values():
		zs += (h as Hero).position.z
		n += 1
	if avatar != null and avatar.visible:
		zs += avatar.head.global_position.z
		n += 1
	var room := int(net.state_get("room", 0))
	var want := Dungeon.center(room).z if n == 0 else zs / n
	want = clampf(want, Dungeon.center(Dungeon.ROOMS - 1).z, 0.0)
	if String(net.state_get("phase", "")) != "cleared":
		want = lerpf(want, Dungeon.center(room).z, 0.7)
	cam_z = lerpf(cam_z, want, 1.0 - exp(-2.5 * delta))
	var cam := split.shared_camera()
	var pos := Vector3(0.0, 10.5, cam_z + 5.0)
	cam.global_transform = Transform3D(UiKit.face(Vector3(0.0, 0.0, cam_z - 0.3) - pos), pos)
	shake = maxf(0.0, shake - delta * 2.0)
	if shake > 0.0:
		cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.15


# --- Effects (every machine) ---------------------------------------------------------------------

func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	if net.mode == "host":
		net.event("sfx", [n, p, db, pitch])


func confetti(p: Vector3, col: Color, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = amount
	cp.lifetime = 1.3
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 180.0
	cp.initial_velocity_min = 2.0
	cp.initial_velocity_max = 4.5
	cp.gravity = Vector3(0, -3.0, 0)
	cp.damping_min = 1.0
	cp.damping_max = 2.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 0.015)
	bm.material = MeshKit.vertex_material(true)
	cp.mesh = bm
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.7), Color(0.5, 0.9, 1.0)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	cp.color_initial_ramp = g
	add_child(cp)
	cp.position = p
	cp.emitting = true
	get_tree().create_timer(1.8).timeout.connect(cp.queue_free)


## A monster poofs: a puff of confetti and a little shake on the TV.
func poof_fx(p: Vector3, col: Color, amount: int) -> void:
	confetti(p, col, amount)
	if amount >= 60:
		shake = 0.8


## A golden key flies from the room into the gate's lock.
func key_fx(from: Vector3, to: Vector3) -> void:
	var b := MeshKit.Builder.new()
	b.torus(0.12, 0.035, MeshKit.at(Vector3(0, 0.2, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.82, 0.25), 14, 6, true)
	b.box(Vector3(0.05, 0.3, 0.05), MeshKit.at(Vector3(0, -0.05, 0)), Color(1.0, 0.82, 0.25), true)
	b.box(Vector3(0.1, 0.05, 0.05), MeshKit.at(Vector3(0.06, -0.15, 0)), Color(1.0, 0.82, 0.25), true)
	var k := MeshKit.instance(b.build(), false)
	add_child(k)
	k.global_position = from
	k.scale = Vector3.ONE * 0.2
	var tw := k.create_tween()
	tw.tween_property(k, "scale", Vector3.ONE * 1.6, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(k, "rotation:y", TAU, 1.0)
	tw.tween_property(k, "global_position", to, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(k, "scale", Vector3.ONE * 0.8, 0.8)
	tw.tween_callback(func() -> void: confetti(to, Color(1.0, 0.85, 0.3), 30))
	tw.tween_callback(k.queue_free)


func _build_arrow() -> void:
	var b := MeshKit.Builder.new()
	b.box(Vector3(0.3, 0.04, 0.6), MeshKit.at(Vector3(0, 0, 0.25)), Color(0.4, 1.0, 0.7), true)
	b.cone(0.35, 0.45, MeshKit.at(Vector3(0, 0, -0.25), Vector3(1.0, 1.0, 0.1), Vector3(-PI * 0.5, 0, 0)), Color(0.4, 1.0, 0.7), 3, true)
	arrow = MeshKit.instance(b.build(), false)
	arrow.visible = false
	add_child(arrow)


func _animate_arrow(_delta: float) -> void:
	var room := int(net.state_get("room", 0))
	var on := String(net.state_get("phase", "")) == "cleared" and int(net.state_get("open", 0)) > room
	arrow.visible = on
	if on:
		var t := Time.get_ticks_msec() * 0.004
		arrow.position = Vector3(0.0, 0.05, Dungeon.wall_z(room) + 1.4 - fmod(t, 1.0) * 0.8)


## VR: fade to black, do something (move the knight), fade back. Comfortable "teleport".
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


## VR: a short red flash when the knight gets hit (deep).
func hurt_flash() -> void:
	if blink_mat == null:
		return
	var tw := create_tween()
	blink_mat.albedo_color = Color(0.8, 0.05, 0.05, 0.0)
	tw.tween_property(blink_mat, "albedo_color:a", 0.35, 0.05)
	tw.tween_property(blink_mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: blink_mat.albedo_color = Color(0, 0, 0, 0))


func blink(then: Callable) -> void:
	if blink_mat == null:
		then.call()
		return
	var tw := create_tween()
	tw.tween_property(blink_mat, "albedo_color:a", 1.0, 0.18)
	tw.tween_callback(then)
	tw.tween_interval(0.1)
	tw.tween_property(blink_mat, "albedo_color:a", 0.0, 0.3)


# --- VR headline ---------------------------------------------------------------------------------

## VR: one short headline high on the far wall of the room (world-locked, facing back down the room).
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
	var c := Dungeon.center(int(net.state_get("room", 0)))
	headline.position = Vector3(0.0, 3.3, c.z - Dungeon.HALF + 0.3)
	if deep != null and deep.active and not deep.f.is_empty():
		var fr: int = deep._focus_room()
		var rc: Vector3 = deep.FloorGen.room_center(deep.f, maxi(fr, 0))
		headline.position = rc + Vector3(0.0, 2.6, -deep.FloorGen.HALF + 0.2)  # high on the room's far wall
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
	key_row = UiKit.hbox(6)
	card.add_child(key_row)
	pill = UiKit.panel("pill")
	hud.add_child(pill)
	UiKit.pin(pill, Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_top = -60.0
	pill.offset_bottom = -60.0
	_refresh_hud()


## Top-left: a key per gate, gold once it's open, and the trophy once the treasure is found.
func _refresh_hud() -> void:
	if key_row == null:
		return
	for c in key_row.get_children():
		c.queue_free()
	var open := int(net.state_get("open", 0))
	for k in GATES:
		key_row.add_child(UiKit.icon("key", "gold" if k < open else "dim", 34.0))
	var won := String(net.state_get("phase", "")) in ["yay", "results"]
	key_row.add_child(UiKit.icon("trophy", "gold" if won else "dim", 34.0))


func _update_pill() -> void:
	var want := ""
	if deep.active:
		pill.visible = false
		pill_text = "-"
		key_row.get_parent().visible = false
		return
	key_row.get_parent().visible = true
	if party.local_slots().is_empty():
		want = "Join"
	else:
		for s in party.local_slots():
			if heroes.has(s) and not bonked.has(s):
				want = "Bonk!"
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
	if deep != null:
		deep.on_state(key, value)
	match key:
		"open":
			dungeon.set_open(int(value))
			_refresh_hud()
		"used":
			dungeon.set_used(int(value))
		"phase":
			var ph := String(value)
			_refresh_hud()
			if ph == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
			var r := int(net.state_get("room", 0))
			match ph:
				"practice":
					music.play_mood(MOODS[0])
					if split != null:
						HudKit.banner([hud], NAMES[0], "", {"duration": 2.0})
					show_headline("SWING!", 6.0)
				"fight", "treasure":
					music.play_mood(MOODS[r])
					if split != null:
						HudKit.banner([hud], NAMES[r], "", {"duration": 1.8})
					show_headline(NAMES[r])
				"cleared":
					show_headline("YAY!", 2.5)
				"yay":
					music.play_mood("victory")
					show_headline("HOORAY!", 5.0)


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	if split != null and not data.is_empty():
		var screen := Awards.results_screen(hud, data, {"party": party, "min_time": 5.0})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "again"))
		results_ui = screen
	show_headline("AGAIN?", 60.0)


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
	var pots := PackedFloat32Array()
	var moving: Array = pot_fly.keys()
	if hands != null and hands.held_pot >= 0:
		moving.append(hands.held_pot)
	for id in moving:
		var pp: Vector3 = (dungeon.props[id]["node"] as Node3D).global_position
		pots.append_array([float(id), pp.x, pp.y, pp.z])
	return [pose, slots, pos, yaw, flags, monsters.pack(), pots, deep.deep_pack()]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
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
	var pots: PackedFloat32Array = s[6]
	var now := {}
	var i2 := 0
	while i2 + 3 < pots.size():
		var id := int(pots[i2])
		now[id] = true
		if id >= 0 and id < dungeon.props.size():
			(dungeon.props[id]["node"] as Node3D).global_position = Vector3(pots[i2 + 1], pots[i2 + 2], pots[i2 + 3])
		i2 += 4
	for id in _moved_pots:
		if not now.has(id):
			(dungeon.props[id]["node"] as Node3D).position = dungeon.props[id]["home"]
	_moved_pots = now
	if s.size() > 7:
		deep.deep_unpack(s[7])


func apply_event(kind: String, args: Array) -> void:
	if kind.begins_with("d_"):
		deep.apply_event(kind, args)
		return
	match kind:
		"story":
			show_story(args[0])
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"confetti":
			confetti(args[0], args[1], int(args[2]))
		"poof":
			poof_fx(args[0], args[1], int(args[2]))
		"prop":
			dungeon.react(int(args[0]))
		"key":
			key_fx(args[0], args[1])
		"gold":
			var p: Vector3 = args[0]
			for k in 3:
				confetti(p + Vector3(0, 0.6 + k * 0.4, 0), Color(1.0, 0.85, 0.2), 60)
		"bonk":
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
