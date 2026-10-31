extends Node3D
## MECH TITANS: giant friendly robot vs cute kaiju (Pacific Rim meets Power Rangers, kid-friendly).
## The VR player pilots TITAN-1 from its cockpit (mech.gd + cockpit.gd + pilot.gd); TV players fly and
## drive support vehicles (support.gd): jets, rescue trucks, repair drones and stun tanks that paint
## weak spots with target lasers for the Titan's TRIPLE-damage beam. Kaiju (kaiju.gd + kaiju_ai.gd +
## bosses.gd) telegraph every attack, get dizzy when beaten and go home. Nine missions (missions.gd,
## data.gd) with stars, parts and hangar upgrades saved with core/save.gd.
## Modes like every engine game: host (headset or DUO_HOST) / TV machine (DUO_JOIN) / local split screen
## (no headset: slot 0 is a TV seat that pilots the Titan in third person).
## Phases (net store "phase"): "hangar" (mission select, upgrades, paint, vehicle choice) ->
## "briefing" (Commander Sunny) -> "play" -> "results" -> hangar.
## Files: data.gd (tables), city.gd, mech.gd, cockpit.gd, pilot.gd, kaiju.gd, kaiju_ai.gd, bosses.gd,
## combat.gd (rules), support.gd (vehicles, AI, citizens), missions.gd (flow, stars), fx.gd.
##
## SIMPLE_MODE (data.gd; on): no hangar, briefing, shop, stars or results. The game starts straight in
## round 1: a PRACTICE moment (VR: a ghost hand, ghost_hand.gd, shows a punch at a glowing target, then
## at another; TV: one glowing ring each to fly / drive through, toys.gd), then ONE slow friendly kaiju
## to punch until it's dizzy and goes home. A cheer, then the next round, which unlocks one new thing
## (round 2 the beam, round 3 the dash; TV players get one new vehicle per round, Y swaps). The Titan
## never loses: a knock-down is a quick sit-down. Everything in reach reacts (toys.gd): cockpit
## buttons, horn, bobblehead, fuzzy dice, wipers; outside, buildings wobble and trees can be picked up
## and thrown. Text: one short headline in VR (a name or a cheer), no how-to words on the TV.
## VISUAL TEACHING (SIMPLE_MODE, teach.gd + cue.gd): low in each TV player's view a pulsing glowing
## button in that player's own controls plus a picture (punch / beam / dash for the TV pilot; fly through
## the ring, shoot / repair / stun, pick people up / take them to the shelter, swap vehicle for the
## support team), a glowing edge arrow when that thing is off screen, a glowing 3D arrow over the
## practice bat / the dash ring / a dizzy kaiju, glowing buttons on the VR controllers for the dash, and
## a pulsing A + plus + person on the shared view. Each cue goes once its player has done it twice and
## comes back for the next player in that seat. Lost controller / full party / someone leaving: soft
## sounds (and a pulsing bolt). Pause: just PAUSED.
## DEEP (titans-deep): made rounds are DISTRICTS with their own hazards (districts.gd), every fifth one a BOSS
## KAIJU with a crown and a big readable move (bigboss.gd); between made rounds glowing PODS land in front of
## the Titan (picks.gd): walk into one to take an UPGRADE for the session (upgrades.gd); at the start the family
## picks a FRAME (frames.gd) and, before the first made round, GENTLE / BRAVE / MEGA (roundgen.gd MODES), once
## those are open. Every kaiju sent home moves into the saved KAIJU SANCTUARY (sanctuary.gd): hearts that grow
## homes on the hills and unlock frames, upgrades and BRAVE. deep.gd runs hazards and upgrade effects.
## Net store: "mode", "frame", "upg" (upgrades taken), "pick" (the pods), "dome", "sanct_h" (sanctuary hearts).

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
const Dialogue := preload("res://core/dialogue.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const Data := preload("res://games/mech_titans/data.gd")
const City := preload("res://games/mech_titans/city.gd")
const Mech := preload("res://games/mech_titans/mech.gd")
const Pilot := preload("res://games/mech_titans/pilot.gd")
const Fx := preload("res://games/mech_titans/fx.gd")
const Combat := preload("res://games/mech_titans/combat.gd")
const Support := preload("res://games/mech_titans/support.gd")
const Missions := preload("res://games/mech_titans/missions.gd")
const Kaiju := preload("res://games/mech_titans/kaiju.gd")
const Toys := preload("res://games/mech_titans/toys.gd")
const GhostHand := preload("res://games/mech_titans/ghost_hand.gd")
const Teach := preload("res://games/mech_titans/teach.gd")
const RoundGen := preload("res://games/mech_titans/roundgen.gd")
const Creatures := preload("res://core/creatures.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Telemetry := preload("res://core/telemetry.gd")
const Frames := preload("res://games/mech_titans/frames.gd")
const Upgrades := preload("res://games/mech_titans/upgrades.gd")
const Sanctuary := preload("res://games/mech_titans/sanctuary.gd")
const BigBoss := preload("res://games/mech_titans/bigboss.gd")
const Districts := preload("res://games/mech_titans/districts.gd")
const Picks := preload("res://games/mech_titans/picks.gd")
const Deep := preload("res://games/mech_titans/deep.gd")
## Where the kaiju friends stand and cheer (just outside the east and west edges), up to this many.
const PARADE_MAX := 8
const PARADE_X := 68.0

const SIMPLE_MODE := Data.SIMPLE_MODE
const CHEER_TIME := 5.5  ## SIMPLE_MODE: seconds of cheering between rounds

const TV_MASK := 0xFFFFF & ~Data.LAYER_VR_ONLY
## Support vehicles' name tags: slot s's tag is on TAG_LAYER_0 << (s - 1), so its own view leaves it out.
const TAG_LAYER_0 := 1 << 10
const TAG_LAYERS := 0x3F << 10
const VR_MASK := 0xFFFFF & ~Data.LAYER_EXTERIOR & ~Data.LAYER_TV_ONLY & ~VrRig.AVATAR_LAYER & ~TAG_LAYERS

# --- The networking contract ---
var net: Node
var ready_to_play := false
var players: Array = []  ## core/net.gd reads it (the wrist menu); this game uses vr_rig + Party seats
# --- Engine modules ---
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
var dlg: Dialogue
var sky: SkyKit.SkyRig
# --- Game ---
var world_root: Node3D
var city: City
var mech: Mech
var pilot: Pilot
var fx: Fx
var combat: Combat
var support: Support
var missions: Missions
var toys: Toys
var ghost: GhostHand
var teach: Teach  ## SIMPLE_MODE: picture cues instead of how-to words
var pause_menu: Node
var built_map := -1
var test_hp_scale := 1.0  ## bots: shorter fights
var auto_launch := -1  ## bots: launch this mission straight from the hangar
var test_boss_only := false  ## bots: skip the mini waves
var test_practice := false  ## bots: keep the PRACTICE warm-up even when skipping the waves
var results_t := 0.0
var briefing_t := 0.0

var cams := {}  ## slot -> CameraRig
var group_cam: CameraRig
var huds := {}  ## slot -> UiKit root (-1 = shared view)
var hud_w := {}  ## slot -> {widget name: Control}
var vr_avatar: VrRig.Avatar
var vr_menu: Node
var tv_menu: Node
var tv_menu_slot := -1
var menu_page := "main"
var vr_menu_page := "main"
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var turn_mode := "smooth"
var _hud_t := 0.0
var _prev_reboot := false
var parade: Node3D  ## SIMPLE_MODE: the kaiju friends made so far, waving from the city's edges
var parade_key := ""
var test_start_round := 0  ## bots (SIMPLE_MODE): start at this round (3+ = the made rounds)
var story_count := 0  ## story pictures shown on this machine (bots)
var momo_hello := false  ## host: Momo said hello this session
var friends_today := 0  ## host: kaiju sent home as friends this session (Momo cheers the first)
const MOMO_COLOR := "74d99a"  ## Momo, the Titans' first kaiju friend (story_pictures.gd momo)
var deep: Deep  ## hazards, upgrade effects, sanctuary homes (every machine)
var picks: Picks  ## the pods (every machine)
var pick_queue: Array[String] = []  ## host: pods still to land before the next round ("mode", "upgrade")
var pick_t := 0.0  ## host: seconds the pods have stood
var pick_done_t := -1.0  ## host: a pod was taken; carry on when this runs out
var pick_wait := Picks.WAIT
var picks_taken := 0  ## host (bots)
var mode_picked := false  ## host: GENTLE / BRAVE / MEGA chosen this session


func _ready() -> void:
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	pause_menu = menu
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = Data.GAME_ID
	save.version = Data.SAVE_VERSION
	save.defaults = {"parts": 0, "cleared": [], "stars": [], "owned": [], "paint": "classic", "paints": ["classic"], "turn": "smooth",
		"friends": [], "best_round": 0, "rounds": 0, "daily": "", "sanct": {"hearts": 0, "bosses": {}}, "frame": "titan",
		"mode": "gentle", "mega_ok": false, "best": {}}
	save.use_layout(preload("res://games/mech_titans/progress.gd"))  # SAVE_VERSION 2: the Kaiju Sanctuary (migrate_save)
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("overworld")
	music.prepare(["battle", "boss", "victory", "tension"])
	awards = Awards.new()
	awards.define("rescuer", "CITY HERO", "%s citizens saved", "rescues")
	awards.define("stunner", "STUN MASTER", "%s kaiju stunned", "stuns")
	awards.define("finisher", "SUPER PUNCH", "%s finishing punches", "finishers")
	awards.define("spotter", "SHARP SPOTTER", "%s weak spots painted", "assists")
	awards.define("firefighter", "FIREFIGHTER", "%s fires put out", "fires")
	hints = Hints.new()
	add_child(hints)
	hints.bind_party(party)
	dlg = Dialogue.new()
	add_child(dlg)
	dlg.bind_party(party)
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	var flat: bool = mode == "host" and not net.has_vr  # flat host (TV / Deck hosting): slot 0 is a pad player here
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	sky = SkyKit.apply(self, "day", VrRig.wanted(mode) and not flat)
	fx = Fx.new()
	world_root.add_child(fx)
	mech = Mech.new()
	world_root.add_child(mech)
	mech.position = Data.MECH_START
	mech.simulated = mode != "client"
	mech.stomped.connect(_on_stomp)
	combat = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self, null, mech, fx)
	support = Support.new()
	support.name = "Support"
	support.main = self
	world_root.add_child(support)
	deep = Deep.new()
	deep.setup(self)
	world_root.add_child(deep)
	picks = Picks.new()
	picks.name = "Pods"
	picks.main = self
	world_root.add_child(picks)
	if mode != "client":
		missions = Missions.new()
		missions.name = "Missions"
		missions.main = self
		add_child(missions)
	pilot = Pilot.new()
	pilot.party = party
	turn_mode = String(save.data.get("turn", "smooth"))
	pilot.turn_mode = turn_mode
	if VrRig.wanted(mode) and not flat:
		vr_rig = VrRig.new()
		vr_rig.locomotion = false  # the Titan walks; the pilot stands in its cockpit
		vr_rig.turn_mode = "none"
		mech.cockpit.add_child(vr_rig)
		vr_rig.place(mech.cockpit.to_global(Vector3(0, 0, 0.1)), mech.yaw)
		vr_rig.camera.cull_mask = VR_MASK
		_mask_mirror(vr_rig.mirror, VR_MASK)
		mech.cockpit.attach_vignette(vr_rig.camera)
		hints.set_vr_rig(vr_rig, self)
		dlg.set_vr_rig(vr_rig)
		pilot.rig = vr_rig
		pilot.mode = "vr"
	if SIMPLE_MODE:
		teach = Teach.new()
		add_child(teach)
		teach.setup(self)
	if mode != "host" or vr_rig == null:
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		split.camera_far = 900.0
		split.shared_camera().cull_mask = TV_MASK
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 40.0
		add_child(group_cam)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		dlg.add_tv_view(huds[-1], -1)
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			world_root.add_child(vr_avatar)
			var m := VrRig.build_mirror(self, vr_avatar.head, false)
			_mask_mirror(m, VR_MASK | Data.LAYER_VR_ONLY)
			split.set_bubble(m, UiKit.player_color(0), "TITAN PILOT")
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror, UiKit.player_color(0), "TITAN PILOT")
	if SIMPLE_MODE:
		toys = Toys.new()
		toys.name = "Toys"
		world_root.add_child(toys)
		toys.setup(self)
		mech.cockpit.simplify()
		if vr_rig != null:
			ghost = GhostHand.new()
			ghost.name = "GhostHand"
			ghost.main = self
			mech.cockpit.add_child(ghost)
	party.allow_slot0 = mode != "client" and vr_rig == null
	awards.set_player(0, "TITAN")
	if mode != "client":
		combat.hp_scale = test_hp_scale
		_publish_save()
		var first := _first_uncleared()
		net.state_set("sel", first)
		_set_map(first)
		net.state_set("phase", "hangar")
		net.state_set("veh", {})
		_refresh_ai()
	if SIMPLE_MODE:
		# No how-to card: everyone learns by doing in the practice moment. One headline.
		if split != null:
			HudKit.banner(_all_huds(), "MECH TITANS", "", {"duration": 2.5})
		if vr_rig != null:
			cockpit_message("MECH TITANS", UiKit.ACCENT, 2.5)
	else:
		# The how-to card is for the TV views only: the VR pilot learns by doing (the PRACTICE warm-up at
		# the start of a mission) and gets a short cockpit headline instead of a wall of text.
		hints.intro(Data.INTRO, {"duration": 12.0, "vr_card": "none"})
		if vr_rig != null:
			cockpit_message("WELCOME, PILOT!", UiKit.ACCENT, 4.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Mech Titans: %s mode%s" % [mode, " with a VR pilot" if vr_rig != null else ""])
	if mode != "client" and auto_launch >= 0 and not SIMPLE_MODE:
		net.state_set("sel", auto_launch)
		_set_map(auto_launch)
	if mode != "client" and SIMPLE_MODE:
		net.state_set("run_seed", Seeded.fresh_seed())  # this session's made rounds (roundgen.gd)
		_publish_friends()
		_deep_start()


func _mask_mirror(vp: SubViewport, mask: int) -> void:
	if vp == null:
		return
	for c in vp.get_children():
		if c is Camera3D:
			(c as Camera3D).cull_mask = mask


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	# A round cut short (back to the arcade, a quit) still writes its telemetry line.
	if SIMPLE_MODE and net != null and net.mode != "client" and String(net.state_get("phase", "")) == "play" and missions != null:
		_round_telemetry(int(net.state_get("mission", 0)), "quit")


# --- Made rounds, kaiju friends, story pictures (SIMPLE_MODE) -----------------------------------

## The mission / round table entry for i (SIMPLE_MODE: lessons, then seeded rounds from roundgen.gd;
## every machine reads the host's "round_info" so it's the same everywhere).
func mission_info(i: int) -> Dictionary:
	if not SIMPLE_MODE:
		return Data.mission(i)
	var ri: Variant = net.state_get("round_info", {})
	if ri is Dictionary and int((ri as Dictionary).get("index", -1)) == i:
		return ri
	return RoundGen.make(i, int(net.state_get("run_seed", 0)), _friend_count(), String(net.state_get("mode", "gentle")))


## This round's lost-kaiju look ({} for the lessons and the full game).
func round_variant() -> Dictionary:
	if not SIMPLE_MODE or net == null:
		return {}
	return mission_info(int(net.state_get("mission", net.state_get("map", 0)))).get("variant", {})


func _friend_count() -> int:
	if save == null:
		return 0
	return (save.data.get("friends", []) as Array).size()


## Host: the friends made so far (the last few, for the hills) for every machine.
func _publish_friends() -> void:
	var f: Array = save.data.get("friends", [])
	var h := Sanctuary.hearts(save.data)
	net.state_set("friends_list", f.slice(maxi(0, f.size() - Sanctuary.parade_size(h))))
	net.state_set("friends_n", f.size())
	net.state_set("sanct_h", h)


## Every machine: the kaiju friends waving from the north hills.
func _build_parade(list: Array) -> void:
	var key := var_to_str(list)
	if key == parade_key and parade != null:
		return
	parade_key = key
	if parade != null:
		parade.queue_free()
	parade = Node3D.new()
	parade.name = "FriendsParade"
	world_root.add_child(parade)
	for i in list.size():
		var e: Array = list[i]
		var info: Dictionary = Data.KAIJU.get(String(e[0]), Data.KAIJU["lizard"])
		var opts := {"color": info["color"], "lod": "far"}
		if e.size() > 1 and String(e[1]) != "":
			opts["color"] = Color.html(String(e[1]))
			opts["color2"] = Color.html(String(e[2])) if e.size() > 2 else opts["color"]
		var crowned := e.size() > 3 and String(e[3]) != ""  # a boss kaiju keeps its crown in the sanctuary
		if crowned:
			opts["boss"] = true
		var m := Creatures.monster(String(info["monster"]), opts)
		var h := maxf(0.2, Creatures.height_of(m))
		m.scale = Vector3.ONE * ((8.0 if crowned else 6.0) / h)
		# Along the east and west edges of the city, facing in (the Titan and the planes see them).
		var side := -1.0 if i % 2 == 0 else 1.0
		m.position = Vector3(side * PARADE_X, 0.0, 24.0 - 11.0 * float(i / 2))
		m.rotation.y = -side * PI * 0.5  # creatures face +Z: turn them towards the middle
		parade.add_child(m)
		var a: Variant = Creatures.anim(m)
		if a != null:
			a.call("play", "wave")
		m.set_meta("phase", float(i) * 0.7)


## Every machine: friends wave now and then, and cheer while the round's cheer plays.
func _animate_parade(delta: float) -> void:
	if parade == null:
		return
	var cheering := String(net.state_get("phase", "")) == "results"
	for m in parade.get_children():
		var ph := float(m.get_meta("phase", 0.0)) + delta
		m.set_meta("phase", ph)
		if ph > (1.3 if cheering else 6.0):
			m.set_meta("phase", 0.0)
			var a: Variant = Creatures.anim(m)
			if a != null:
				a.call("play", "cheer" if cheering else "wave")


## Host: a story picture on every machine (one or two capital words: SIMPLE_MODE has no how-to text).
func story(beat: Dictionary) -> void:
	show_story(beat)
	if net.mode == "host":
		net.event("story", [beat])


func show_story(beat: Dictionary) -> void:
	story_count += 1
	var opts := beat.duplicate()
	opts["color"] = Color.html(String(beat.get("color", "ffd25a")))
	opts["sound"] = String(beat.get("sound", "ui_notify"))
	if split != null:
		StoryCard.show(_all_huds(), opts)
	if vr_rig != null:
		StoryCard.show_vr(self, vr_rig.camera, opts)


func _kaiju_color(m: Dictionary) -> String:
	var v: Dictionary = m.get("variant", {})
	var steps: Array = m.get("steps", [{}])
	var bosses: Array = (steps[0] as Dictionary).get("boss", ["lizard"]) if not steps.is_empty() else ["lizard"]
	var c: Color = v.get("color", Data.KAIJU.get(String(bosses[0]), Data.KAIJU["lizard"])["color"])
	return c.to_html(false)


## Host: the round's kaiju went home: they're friends now (saved), maybe a new place opens.
func _make_friends(i: int) -> void:
	var m := mission_info(i)
	var v: Dictionary = m.get("variant", {})
	var friends: Array = save.data["friends"]
	var before := friends.size()
	var steps: Array = m.get("steps", [])
	var bosses: Array = (steps[0] as Dictionary).get("boss", []) if not steps.is_empty() else []
	var bb := String(m.get("bigboss", ""))
	for b in bosses:
		var e: Array = [String(b), "", ""]
		if v.has("color"):
			e = [String(b), (v["color"] as Color).to_html(false), (v.get("color2", v["color"]) as Color).to_html(false)]
		if bb != "":
			e.append(bb)  # crowned in the sanctuary
		friends.append(e)
	# The Kaiju Sanctuary: hearts (a boss counts BOSS_HEARTS), what they unlock, the best made round per difficulty.
	var sanct: Dictionary = save.data["sanct"]
	var h_before := int(sanct.get("hearts", 0))
	var h_after := h_before + Sanctuary.hearts_for(m)
	sanct["hearts"] = h_after
	var rmode := String(m.get("mode", "gentle"))
	if bb != "":
		var bc: Dictionary = sanct.get("bosses", {})
		bc[bb] = int(bc.get(bb, 0)) + 1
		sanct["bosses"] = bc
		if rmode != "gentle" and not bool(save.data.get("mega_ok", false)):
			save.data["mega_ok"] = true
			pending_unlocks.append({"kind": "mode", "id": "mega", "name": "MEGA"})
	if bool(m.get("gen", false)):
		var best: Dictionary = save.data["best"]
		best[rmode] = maxi(int(best.get(rmode, 0)), int(m.get("lap", 0)) + 1)
	pending_unlocks.append_array(Sanctuary.unlocks_between(h_before, h_after))
	while friends.size() > 60:
		friends.pop_front()
	save.data["best_round"] = maxi(int(save.data["best_round"]), i + 1)
	save.data["rounds"] = int(save.data["rounds"]) + 1
	if bool(m.get("daily", false)):
		save.data["daily"] = Seeded.today()  # TODAY'S KAIJU went home (the Trophy Hall's daily tick)
	save.mark_dirty()
	_publish_friends()
	var who := String(m.get("name", "")) if bool(m.get("gen", false)) else String(Data.KAIJU.get(String(bosses[0]) if not bosses.is_empty() else "lizard", Data.KAIJU["lizard"])["name"])
	story({"who": "NEW FRIEND!", "line": who, "pic": "kaiju", "color": _kaiju_color(m), "duration": 3.5, "sound": "achievement"})
	var opened := RoundGen.place_opened(before, friends.size())
	_unlock_cards(4.0 if opened == "" else 7.8)
	if opened != "":
		get_tree().create_timer(3.8).timeout.connect(func() -> void:
			story({"who": "NEW PLACE!", "line": String(Data.PLACES[opened]["name"]), "pic": "castle", "color": "7ad7ff", "duration": 3.5, "sound": "fanfare"}))
	friends_today += 1
	# Momo cheers the session's first friend and the golden one (a new place is bigger news: its card goes instead;
	# the next round starts after CHEER_TIME, so there's room for one more card).
	if opened == "" and (friends_today == 1 or bool(m.get("daily", false))):
		var golden := bool(m.get("daily", false))
		get_tree().create_timer(3.8).timeout.connect(func() -> void:
			story({"who": "MOMO", "line": "GOLDEN FRIEND!" if golden else "YAY!", "pic": "momo",
				"color": "ffd25a" if golden else MOMO_COLOR, "duration": 3.0}))


var pending_unlocks: Array = []  ## host: sanctuary unlocks still to show as story cards


## Host: the sanctuary's new unlocks, one story card each (3.8 s apart), starting `delay` s from now.
func _unlock_cards(delay: float) -> void:
	var list := pending_unlocks.duplicate()
	pending_unlocks.clear()
	for k in list.size():
		var u: Dictionary = list[k]
		var card := {}
		match String(u["kind"]):
			"frame":
				var paint: Dictionary = Data.PAINTS[String(Frames.info(String(u["id"]))["paint"])]
				card = {"who": "NEW TITAN!", "line": String(u["name"]), "pic": "titanframe", "color": (paint["main"] as Color).to_html(false)}
			"upgrade":
				card = {"who": "NEW POWER!", "line": String(u["name"]), "pic": "titanpod", "color": (Upgrades.info(String(u["id"]))["color"] as Color).to_html(false)}
			"mode":
				card = {"who": "NEW!", "line": String(u["name"]), "pic": "crownkaiju" if String(u["id"]) == "mega" else "star",
					"color": (Picks.MODE_COLORS[String(u["id"])] as Color).to_html(false)}
			_:
				card = {"who": "SANCTUARY", "line": "GROWS!", "pic": "sanctuary", "color": MOMO_COLOR}
		card["duration"] = 3.4
		card["sound"] = "fanfare"
		get_tree().create_timer(delay + 3.8 * k).timeout.connect(func() -> void: story(card))


## Host: one line per round for tuning from real play (core/telemetry.gd).
func _round_telemetry(i: int, how: String) -> void:
	var m := mission_info(i)
	var steps: Array = m.get("steps", [])
	Telemetry.run(Data.GAME_ID, {"round": i + 1, "made": bool(m.get("gen", false)), "daily": bool(m.get("daily", false)),
		"name": String(m.get("name", "")), "place": String(m.get("place", "")), "sky": String(m.get("sky", "")),
		"kaiju": (steps[0] as Dictionary).get("boss", []) if not steps.is_empty() else [], "hp": float(m.get("hp", 1.0)),
		"seconds": int(missions.time), "reboots": missions.reboots, "tv_players": party.player_count(), "vr": vr_rig != null,
		"friends": _friend_count(), "end": how, "mode": String(m.get("mode", "gentle")), "boss": String(m.get("bigboss", "")),
		"frame": String(net.state_get("frame", "titan")), "upg": upg_list(), "hazards": deep.hazards_landed, "hazard_hits": deep.hazards_hit,
		"hearts": Sanctuary.hearts(save.data)})


# --- World ------------------------------------------------------------------------------------------

## Host: show mission i's city on every machine (a new "map_gen" always rebuilds it fresh).
func _set_map(i: int) -> void:
	if SIMPLE_MODE and net.mode != "client":
		net.state_set("round_info", RoundGen.make(i, int(net.state_get("run_seed", 0)), _friend_count(), String(net.state_get("mode", "gentle"))))
	net.state_set("map", i)
	net.state_set("map_gen", int(net.state_get("map_gen", 0)) + 1)


## Every machine: build the city for mission i (hangar preview and the mission itself).
func _build_map(i: int) -> void:
	if i == built_map and city != null:
		return
	built_map = i
	var m := mission_info(i)
	if toys != null:
		toys.reset_world()
	if combat != null:
		combat.clear()
	if city != null:
		city.queue_free()
	city = City.new()
	city.name = "City"
	world_root.add_child(city)
	city.build(String(m["place"]), int(m["seed"]), String(m["sky"]) == "night" or String(m["sky"]) == "space", String(m["protect"]))
	combat.setup(self, city, mech, fx)
	support.setup(self, city)
	mech.city = city
	support.build_citizens(int(m["rescue"]))
	var preset := String(m["sky"])
	sky.set_preset(preset, 0.0)
	if vr_rig != null:
		VrRig.apply_vr_performance(self)
	sfx.stop_all_loops(0.5)
	match preset:
		"stormy":
			sfx.play_loop("rain", -14.0)
		"space":
			sfx.play_loop("space", -16.0)
		"snowy":
			sfx.play_loop("wind", -18.0)
	if city.has_water:
		sfx.play_loop("waves", -20.0)
	_place_mech_at_start()
	if net.state_has("bld"):
		city.apply_states(net.state_get("bld", PackedByteArray()))
	if net.state_has("cit"):
		support.apply_citizens(net.state_get("cit", PackedByteArray()))


func _place_mech_at_start() -> void:
	mech.position = Data.MECH_START
	mech.yaw = 0.0
	mech.rotation = Vector3.ZERO
	mech.velocity = Vector3.ZERO
	for id in support.vehicles:
		var v: Support.Vehicle = support.vehicles[id]
		var p := support._spawn_point(int(id), v.kind)
		v.global_position = p + Vector3(0, float(Data.VEHICLE_INFO[v.kind]["alt"]), 0)


# --- Upgrades and tools (host reads the save) ---------------------------------------------------------

func has_upgrade(id: String) -> bool:
	if SIMPLE_MODE:
		return false  # no shop: everyone has the same friendly Titan
	var s: Dictionary = net.state_get("save", {})
	return (s.get("owned", []) as Array).has(id)


func beam_mult() -> float:
	if SIMPLE_MODE:
		return float(frame_info()["beam"]) * (Upgrades.BEAM_MULT if has_upg("beam") else 1.0)
	return 1.8 if has_upgrade("beam3") else (1.4 if has_upgrade("beam2") else 1.0)


## The session's upgrades (upgrades.gd ids, every machine).
func upg_list() -> Array:
	var u: Variant = net.state_get("upg", []) if net != null else []
	return u if u is Array else []


func has_upg(id: String) -> bool:
	return upg_list().has(id)


## The Titan's frame this session (frames.gd).
func frame_info() -> Dictionary:
	return Frames.info(String(net.state_get("frame", "titan")) if net != null else "titan")


## Punch damage multiplier: frame x SUPER PUNCH.
func punch_mult() -> float:
	if not SIMPLE_MODE:
		return 1.0
	return float(frame_info()["punch"]) * (Upgrades.PUNCH_MULT if has_upg("power") else 1.0)


## Host: the Titan's walk / dash / sit-down from its frame, upgrades and the district (moon: longer dashes).
func _apply_deep() -> void:
	if not SIMPLE_MODE or mech == null:
		return
	var f := frame_info()
	mech.speed_mult = float(f["speed"]) * (Upgrades.LEGS_MULT if has_upg("legs") else 1.0)
	var place := String(mission_info(int(net.state_get("mission", 0))).get("place", "downtown"))
	mech.dash_dist = 20.0 * float(f["dash"]) * float(Districts.info(place)["dash"]) * (1.2 if has_upg("jets") else 1.0)
	mech.reboot_time = 1.5 if has_upg("repair") else 3.0


func energy_mult() -> float:
	return 0.7 if has_upgrade("battery") else 1.0


func armour_taken_mult() -> float:
	if SIMPLE_MODE:
		# the difficulty (roundgen.gd curve dmg: gentle hits are soft) and the frame's armour
		return float(mission_info(int(net.state_get("mission", 0))).get("dmg", 0.6)) / float(frame_info()["armour"])
	return 1.0


func tools_available() -> Array[String]:
	var out: Array[String] = ["fist"]
	for t in ["claw", "foam", "drill"]:
		if has_upgrade(t):
			out.append(t)
	return out


func _apply_upgrades() -> void:
	mech.armour_max = 160.0 if has_upgrade("armour3") else (130.0 if has_upgrade("armour2") else 100.0)
	mech.armour = mech.armour_max
	mech.energy_max = 130.0 if has_upgrade("battery") else 100.0
	mech.energy = mech.energy_max
	mech.dash_dist = 28.0 if has_upgrade("thrusters") else 20.0
	mech.rebooting = 0.0
	mech.set_tool("fist")
	mech.cockpit.set_tool("fist")


## The tool lever (VR) / Y (TV pilot): next or previous unlocked arm tool.
func cycle_tool(dir: int) -> void:
	if SIMPLE_MODE:
		return  # no arm tools: the fist is all you need
	var list := tools_available()
	if list.size() <= 1:
		cockpit_message("MORE TOOLS IN THE HANGAR", UiKit.TEXT_DIM, 1.5)
		sfx.play("ui_error", -6.0)
		return
	var i := list.find(mech.tool)
	var t := list[(i + dir + list.size()) % list.size()]
	mech.set_tool(t)
	mech.cockpit.set_tool(t)
	var info: Dictionary = Data.TOOL_INFO[t]
	cockpit_message(String(info["name"]), info["color"], 1.5)
	sfx.play("equip", 0.0, 0.8)
	pulse(0, 0.5, 0.08)


## SIMPLE_MODE: may the pilot use `move` ("beam" / "dash") this round? Always true otherwise.
func move_ok(move: String) -> bool:
	if not SIMPLE_MODE:
		return true
	return Data.simple_has(move, int(net.state_get("mission", 0)))


## SIMPLE_MODE: the vehicles TV players may use this round (all of them otherwise).
func vehicle_kinds() -> Array[String]:
	if not SIMPLE_MODE:
		return Data.VEHICLES
	return Data.simple_vehicles(int(net.state_get("mission", 0)))


# --- Players ------------------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.camera.cull_mask = TV_MASK & ~tag_layer(slot)  # never this player's own name tag
		c.party = party
		c.slot = slot
		c.pitch = -0.3
		add_child(c)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		dlg.add_tv_view(huds[slot], slot)
		if slot == 0:
			c.pivot_height = 9.0
			c.follow(mech, 26.0, 0.0)
			pilot.mode = "pad"
			pilot.slot = 0
			pilot.cam = c.camera
			if not SIMPLE_MODE:
				hints.hint("pilot_tv", "You pilot the TITAN! X punch, RT beam, LB block", {"to": 0, "times": 1})
		elif not SIMPLE_MODE:
			hints.hint("support_%d" % slot, "X: paint weak spots with your target laser!", {"to": slot, "icon": "eye"})
	if slot > 0:
		awards.set_player(slot, party.name_of(slot))
	if net.mode != "client" and slot > 0:
		var veh: Dictionary = (net.state_get("veh", {}) as Dictionary).duplicate()
		if not veh.has(slot):
			veh[slot] = _free_kind(veh)
			net.state_set("veh", veh)
		_refresh_ai()
	_refresh_group()
	_refresh_menus()
	sfx.play("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	if teach != null:
		teach.player_left(slot)  # whoever takes this seat next sees the picture cues again
	if cams.has(slot):
		(cams[slot] as Node).queue_free()
		cams.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
		hud_w.erase(slot)
	hints.remove_view(slot)
	if slot == 0:
		pilot.mode = "vr" if vr_rig != null else "auto"
	if net.mode != "client" and slot > 0:
		var veh: Dictionary = (net.state_get("veh", {}) as Dictionary).duplicate()
		veh.erase(slot)
		net.state_set("veh", veh)
		_refresh_ai()
	_refresh_group()
	_refresh_menus()


func _free_kind(veh: Dictionary) -> String:
	var kinds := vehicle_kinds()
	var used := []
	for k in veh:
		if int(k) < Support.AI_BASE:
			used.append(String(veh[k]))
	for kind in kinds:
		if not used.has(kind):
			return kind
	return kinds[veh.size() % kinds.size()]


## Host: AI vehicles fill in for the jobs no TV player is doing (always at least a jet, truck and drone,
## plus a tank when the mission's boss needs stun shells), fewer as more TV players join.
func _refresh_ai() -> void:
	if net.mode == "client":
		return
	var veh: Dictionary = (net.state_get("veh", {}) as Dictionary).duplicate()
	var humans: Array = []
	for k in veh.keys():
		if int(k) >= Support.AI_BASE:
			veh.erase(k)
		else:
			humans.append(String(veh[k]))
	var needed: Array[String] = ["jet", "truck", "drone"]
	var m := mission_info(int(net.state_get("map", 0)))
	for st in m["steps"]:
		var d: Dictionary = st
		if d.has("boss") and ((d["boss"] as Array).has("moth") or (d["boss"] as Array).has("crab")):
			needed.append("tank")
	if SIMPLE_MODE:
		# Helpers only of the kinds the TV players have unlocked (round 1: one jet).
		var ok := Data.simple_vehicles(int(net.state_get("map", 0)))
		var keep: Array[String] = []
		for kind in needed:
			if ok.has(kind):
				keep.append(kind)
		needed = keep
	var room := maxi(0, 4 - humans.size())
	var id := Support.AI_BASE
	for kind in needed:
		if room <= 0:
			break
		if humans.has(kind):
			continue
		veh[id] = kind
		id += 1
		room -= 1
	net.state_set("veh", veh)


func on_vehicle_made(id: int, v: Node3D) -> void:
	if cams.has(id) and id > 0:
		var c: CameraRig = cams[id]
		var kind: String = (v as Support.Vehicle).kind
		c.pivot_height = 2.5
		c.follow(v, 13.0 if kind != "drone" else 10.0, 0.0)
		_refresh_vehicle_hud(id)
	_refresh_group()


func _refresh_group() -> void:
	if group_cam == null:
		return
	var t: Array = [mech]
	for id in support.vehicles:
		if int(id) < Support.AI_BASE:
			t.append(support.vehicles[id])
	if String(net.state_get("phase", "hangar")) == "hangar":
		# Hangar: a slow cinematic pan across the Titan's front.
		group_cam.shot_look(mech.global_position + Vector3(18.0, 13.0, -22.0), mech.global_position + Vector3(0, 7.0, 0), 1.0,
			Vector3(-1.0, 0.0, 0.0))
	else:
		group_cam.follow_group(t, -42.0, 0.0)


## The render layer of slot's name tag (other TV views see it; its own view and VR don't).
func tag_layer(slot: int) -> int:
	return TAG_LAYER_0 << clampi(slot - 1, 0, 5) if slot >= 1 else 0


func view_camera(slot: int) -> Camera3D:
	return split.active_camera(slot) if split != null else null


func slot_busy(slot: int) -> bool:
	return UiMenu.slot_busy(slot) or dlg.is_playing() or hints.intro_showing()


# --- Feedback helpers (called by combat / support / missions on the host) ----------------------------

func pulse(hand: int, amp: float, dur: float) -> void:
	if vr_rig != null:
		vr_rig.pulse(hand, amp, dur)
	elif pilot.mode == "pad" and party.is_local(0):
		party.rumble(0, amp * 0.6, amp, dur)


func cockpit_rattle(amount: float) -> void:
	mech.cockpit.rattle(amount)


func cockpit_message(text: String, color: Color = UiKit.ACCENT, time: float = 1.4) -> void:
	mech.cockpit.message(text, color, time)


func cockpit_sparks() -> void:
	mech.cockpit.sparks()


func hint_vr(id: String, text: String) -> void:
	if SIMPLE_MODE:
		return  # show, don't tell
	if vr_rig != null:
		hints.hint(id, text, {"to": "vr", "times": 1})
	elif pilot.mode == "pad":
		hints.hint(id, text, {"to": 0, "times": 1})


func hint_tv(id: String, text: String, slot: int = -1) -> void:
	if SIMPLE_MODE:
		return
	if net.mode == "host":
		net.event("hint", [id, text, slot])
	_hint_tv_local(id, text, slot)


func _hint_tv_local(id: String, text: String, slot: int) -> void:
	if split == null:
		return
	if slot >= 0:
		if party.is_local(slot):
			hints.hint(id, text, {"to": slot, "times": 2})
	else:
		hints.hint(id, text, {"to": "tv", "times": 2})


## Every machine: a big banner (TV) / cockpit headline (VR).
func announce(title: String, sub: String, style: String) -> void:
	if SIMPLE_MODE:
		sub = ""  # one short line on the TV
	if split != null:
		HudKit.banner(_all_huds(), title, sub, {"style": style, "duration": 2.4})
	var c := UiKit.ACCENT
	match style:
		"defeat":
			c = UiKit.BAD
		"victory":
			c = UiKit.GOOD
		"info":
			c = UiKit.INFO
		"boss":
			c = Color(1.0, 0.5, 0.4)
	cockpit_message(title, c, 2.2)


## Commander Sunny on the radio (TV toast; the pilot hears the radio blip).
func radio(text: String) -> void:
	if net.mode == "host":
		net.event("radio", [text])
	_radio_local(text)


func _radio_local(text: String) -> void:
	sfx.play("computer", -8.0, 1.3)
	if split != null and not SIMPLE_MODE:
		HudKit.toast(_all_huds(), "%s: %s" % [Data.COMMANDER, text], {"icon": "flag", "color": "gold", "duration": 4.0})


func tv_shake(amount: float) -> void:
	for slot in cams:
		var c: CameraRig = cams[slot]
		var d := 1.0
		if slot > 0 and support.vehicles.has(slot):
			d = 0.7
		c.shake(amount * d)
	if group_cam != null:
		group_cam.shake(amount * 0.6)


func _on_stomp(pos: Vector3, strength: float) -> void:
	if city != null:
		city.squash_at(pos, 3.5)
	if deep != null and net.mode != "client":
		deep.on_stomp(pos)
	sfx.play_at("land", pos, -2.0 + strength * 4.0, 0.42 + randf() * 0.05)
	if vr_rig != null:
		mech.cockpit.rattle(0.12 * strength)
		vr_rig.pulse(VrRig.LEFT, 0.12 * strength, 0.05)
		vr_rig.pulse(VrRig.RIGHT, 0.12 * strength, 0.05)
	for slot in cams:
		var c: CameraRig = cams[slot]
		var cam_pos := c.camera.global_position
		if cam_pos.distance_to(pos) < 40.0:
			c.shake(0.12 * strength)


# --- HUD (TV views) ---------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var w := {}
	hud_w[slot] = w
	# Top left: score + objective.
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var v := UiKit.vbox()
	card.add_child(v)
	var row := UiKit.hbox()
	v.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	row.add_child(UiKit.icon("star", "gold", 30.0))
	var score := UiKit.label("0", "number")
	row.add_child(score)
	w["score"] = score
	var obj := UiKit.label("", "small", "dim")
	obj.custom_minimum_size.x = 330.0
	obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(obj)
	w["objective"] = obj
	# Top right: the Titan and the city.
	var card2 := UiKit.panel("card")
	ui.add_child(card2)
	UiKit.pin(card2, Control.PRESET_TOP_RIGHT)
	card2.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card2.offset_right = -24.0
	card2.offset_left = -24.0
	card2.offset_top = 20.0
	var v2 := UiKit.vbox()
	card2.add_child(v2)
	v2.add_child(UiKit.label("TITAN ARMOUR", "small", "dim"))
	var ab := UiKit.bar("hp", 240.0, 18.0)
	v2.add_child(ab)
	w["armour"] = ab
	var cl := UiKit.label("CITY DAMAGE 0%", "small")
	v2.add_child(cl)
	w["city"] = cl
	var ll := UiKit.label("", "small")
	v2.add_child(ll)
	w["landmark"] = ll
	var rl := UiKit.label("", "small", "good")
	v2.add_child(rl)
	w["rescue"] = rl
	# Top centre: the boss.
	var boss := UiKit.panel("pill")
	ui.add_child(boss)
	UiKit.pin(boss, Control.PRESET_CENTER_TOP)
	boss.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss.offset_top = 120.0 if slot >= 0 else 20.0
	var bv := UiKit.vbox()
	boss.add_child(bv)
	var bn := UiKit.label("", "small", Color(1.0, 0.6, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	bv.add_child(bn)
	var bb := UiKit.bar("hp", 340.0, 16.0, Color(1.0, 0.4, 0.35))
	bv.add_child(bb)
	boss.visible = false
	if SIMPLE_MODE:
		# No score, objective, armour or city readouts; the boss bar without a name.
		card.visible = false
		card2.visible = false
		bn.visible = false
	w["boss"] = boss
	w["boss_name"] = bn
	w["boss_bar"] = bb
	if slot >= 0:
		# Bottom: what my buttons do; centre: the crosshair.
		var bottom := UiKit.panel("pill")
		ui.add_child(bottom)
		UiKit.pin(bottom, Control.PRESET_CENTER_BOTTOM)
		bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
		bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
		bottom.offset_top = -24.0
		bottom.offset_bottom = -24.0
		bottom.visible = not SIMPLE_MODE  # SIMPLE_MODE: no button words: the picture cue (teach.gd) instead
		w["bottom"] = bottom
		var cross := UiKit.icon("plus", Color(1, 1, 1, 0.8), 28.0)
		ui.add_child(cross)
		UiKit.pin(cross, Control.PRESET_CENTER)
		cross.position -= Vector2(14.0, 14.0)
		w["cross"] = cross
		_refresh_vehicle_hud(slot)
		if teach != null:
			teach.add_view(slot, ui)
	elif teach != null:
		w["join"] = teach.make_join(ui)  # no words: a pulsing A + plus + person in the corner
	else:
		var jp := UiKit.panel("pill")
		jp.add_child(UiKit.prompts([["A", "Join the support team"]]))
		ui.add_child(jp)
		UiKit.pin(jp, Control.PRESET_CENTER_BOTTOM)
		jp.grow_horizontal = Control.GROW_DIRECTION_BOTH
		jp.grow_vertical = Control.GROW_DIRECTION_BEGIN
		jp.offset_top = -60.0
		jp.offset_bottom = -60.0
		w["join"] = jp
	_refresh_hud()


func _refresh_vehicle_hud(slot: int) -> void:
	if not hud_w.has(slot):
		return
	var w: Dictionary = hud_w[slot]
	var bottom: Control = w.get("bottom", null)
	if bottom == null:
		return
	for c in bottom.get_children():
		c.queue_free()
	if SIMPLE_MODE:
		return  # no button words: the picture cue low in the view (teach.gd) shows what to do
	var row := UiKit.hbox()
	bottom.add_child(row)
	if slot == 0:
		row.add_child(UiKit.label("TITAN-1", "body", "info"))
		row.add_child(UiKit.prompts([["X", "Punch"], ["RT", "Beam"], ["LB", "Block"], ["A", "Dash"], ["Y", "Tool"]]))
		return
	var v: Support.Vehicle = support.vehicles.get(slot, null)
	if v == null:
		return
	var info: Dictionary = Data.VEHICLE_INFO[v.kind]
	row.add_child(UiKit.icon(String(info["icon"]), info["color"], 30.0))
	row.add_child(UiKit.label(String(info["name"]), "body", info["color"]))
	row.add_child(UiKit.prompts([["A", String(info["a"])], ["X", "Laser"], ["B", String(info["b"])], ["Y", "Switch"]]))


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	var cd := int(net.state_get("cdmg", 0))
	var lm := int(net.state_get("landmark", -1))
	var resc := int(net.state_get("rescued", 0))
	var rtot := int(net.state_get("rescue_total", 0))
	var obj := String(net.state_get("objective", ""))
	var phase := String(net.state_get("phase", "hangar"))
	for slot in hud_w:
		var w: Dictionary = hud_w[slot]
		if not is_instance_valid(w.get("score")):
			continue
		(w["score"] as Label).text = "%d" % score
		(w["objective"] as Label).text = obj if phase == "play" else ("HANGAR: pick a mission!" if phase == "hangar" else "")
		(w["city"] as Label).text = "CITY DAMAGE %d%%" % cd
		(w["city"] as Label).modulate = UiKit.hp_color(1.0 - cd / 100.0)
		(w["landmark"] as Label).visible = lm >= 0
		(w["landmark"] as Label).text = "%s %d%%" % [_landmark_title(), lm]
		(w["rescue"] as Label).visible = rtot > 0
		(w["rescue"] as Label).text = "SAVED %d / %d" % [resc * 3, rtot * 3]
		if w.has("join"):
			(w["join"] as Control).visible = party.local_slots().is_empty()
	if vr_rig != null:
		mech.cockpit.set_objective(obj if phase == "play" else "")
		var info := "CITY DAMAGE %d%%" % cd
		if lm >= 0:
			info = "%s %d%%" % [_landmark_title(), lm]
		mech.cockpit.set_info(info, UiKit.hp_color(1.0 - cd / 100.0) if lm < 0 else UiKit.hp_color(lm / 100.0))


func _landmark_title() -> String:
	var m := mission_info(int(net.state_get("map", 0)))
	return {"hospital": "HOSPITAL", "plant": "POWER PLANT", "dome": "MOON DOME"}.get(String(m["protect"]), "")


## Every frame (cheap): armour bars, the boss bar, the cockpit dials.
func _tick_hud(delta: float) -> void:
	_hud_t -= delta
	if _hud_t > 0.0:
		return
	_hud_t = 0.1
	var boss: Kaiju = null
	for id in combat.kaiju:
		var k: Kaiju = combat.kaiju[id]
		if not k.is_mini and k.state != "home" and k.state != "gone" and (boss == null or k.hp > boss.hp):
			boss = k
	var boss_name := ""
	var frac := 0.0
	if boss != null:
		boss_name = String(boss.info["name"])
		if boss.kind == "mega":
			boss_name += "  PHASE %d" % boss.phase
		if boss.state == "dizzy":
			boss_name = "%s IS DIZZY!" % String(boss.info["name"])
		frac = boss.hp / maxf(boss.hp_max, 1.0)
	for slot in hud_w:
		var w: Dictionary = hud_w[slot]
		if not is_instance_valid(w.get("armour")):
			continue
		(w["armour"] as UiKit.Bar).set_value(mech.armour, mech.armour_max)
		(w["boss"] as Control).visible = boss != null
		if boss != null:
			(w["boss_name"] as Label).text = boss_name
			(w["boss_bar"] as UiKit.Bar).set_value(frac * 100.0, 100.0)
	var ck := mech.cockpit
	ck.set_armour(mech.armour, mech.armour_max)
	ck.set_energy(mech.energy, mech.energy_max)
	ck.set_boss(boss_name, frac)
	var reboot := mech.rebooting > 0.0
	if reboot != _prev_reboot:
		_prev_reboot = reboot
		if not reboot and net.mode != "client" and String(net.state_get("phase", "")) == "play":
			var back := "UP AGAIN!" if SIMPLE_MODE else "TITAN BACK ONLINE!"
			announce(back, "", "victory")
			if net.mode == "host":
				net.event("announce", [back, "", "victory"])


# --- Hangar menus ---------------------------------------------------------------------------------------

func _progress() -> Dictionary:
	return net.state_get("save", {})


func _publish_save() -> void:
	var d: Dictionary = save.data.duplicate(true)
	net.state_set("save", d)


func _first_uncleared() -> int:
	var cleared: Array = save.data.get("cleared", [])
	for i in Data.MISSIONS.size():
		if not cleared.has(i):
			return i
	return Data.MISSIONS.size() - 1


func _mission_unlocked(i: int) -> bool:
	var cleared: Array = _progress().get("cleared", [])
	return i == 0 or cleared.has(i - 1) or cleared.has(i)


func _stars_of(i: int) -> int:
	var stars: Array = _progress().get("stars", [])
	return int(stars[i]) if i < stars.size() else 0


func _menu_items(page: String, vr: bool) -> Array:
	var p := _progress()
	var parts := int(p.get("parts", 0))
	var sel := int(net.state_get("sel", 0))
	var items: Array = []
	match page:
		"main":
			var m := mission_info(sel)
			items.append({"id": "launch", "text": "LAUNCH: %s" % String(m["name"]), "icon": "play", "desc": Data.PLACES[m["place"]]["name"]})
			items.append({"id": "missions", "text": "CHOOSE MISSION", "icon": "flag", "right": "%d / %d" % [sel + 1, Data.MISSIONS.size()]})
			items.append({"id": "upgrades", "text": "UPGRADES", "icon": "bolt", "right": "%d PARTS" % parts})
			items.append({"id": "paint", "text": "PAINT JOB", "icon": "star"})
			if vr:
				items.append({"id": "turn", "text": "TURNING: %s" % turn_mode.to_upper(), "icon": "arrow_right", "desc": "Smooth or snap turns"})
		"missions":
			for i in Data.MISSIONS.size():
				var mm := mission_info(i)
				var ok := _mission_unlocked(i)
				items.append({"id": "m%d" % i, "text": "%d. %s" % [i + 1, String(mm["name"])], "right": "%d/3" % _stars_of(i) if ok else "",
					"disabled": not ok, "reason": "Finish mission %d first" % i, "icon": "star" if _stars_of(i) > 0 else "flag"})
		"upgrades":
			var owned: Array = p.get("owned", [])
			var cleared: Array = p.get("cleared", [])
			for id in Data.UPGRADE_ORDER:
				var u: Dictionary = Data.UPGRADES[id]
				var have := owned.has(id)
				var need := int(u["need"])
				var reason := ""
				if have:
					reason = "Already yours"
				elif need >= 0 and not cleared.has(need):
					reason = "Clear mission %d first" % (need + 1)
				elif u.has("requires") and not owned.has(String(u["requires"])):
					reason = "Needs %s" % String(Data.UPGRADES[String(u["requires"])]["name"])
				elif parts < int(u["cost"]):
					reason = "Not enough parts"
				items.append({"id": "u_" + id, "text": String(u["name"]), "right": "OWNED" if have else "%d" % int(u["cost"]),
					"desc": String(u["desc"]), "disabled": reason != "", "reason": reason, "icon": "check" if have else "bolt"})
		"paint":
			var paints: Array = p.get("paints", ["classic"])
			var total_stars := 0
			for s in p.get("stars", []):
				total_stars += int(s)
			for id in Data.PAINT_ORDER:
				var pi: Dictionary = Data.PAINTS[id]
				var have := paints.has(id)
				var reason := ""
				if not have and total_stars < int(pi["stars"]):
					reason = "Needs %d stars" % int(pi["stars"])
				elif not have and parts < int(pi["cost"]):
					reason = "Not enough parts"
				var cur := String(p.get("paint", "classic")) == id
				items.append({"id": "p_" + id, "text": String(pi["name"]), "right": "ON" if cur else ("" if have else "%d" % int(pi["cost"])),
					"disabled": reason != "", "reason": reason, "icon": "check" if cur else "star", "icon_color": pi["main"]})
	return items


func _menu_title(page: String) -> String:
	return {"main": "TITAN HANGAR", "missions": "MISSIONS", "upgrades": "UPGRADES  %d PARTS" % int(_progress().get("parts", 0)),
		"paint": "PAINT SHOP"}.get(page, "HANGAR")


## Open / rebuild the hangar menus for the current phase.
func _refresh_menus() -> void:
	var hangar := String(net.state_get("phase", "")) == "hangar" and ready_to_play and not SIMPLE_MODE
	# TV: one menu on the shared screen, driven by the first seat on this machine.
	if split != null:
		var seats := party.local_slots()
		var want_slot: int = seats[0] if hangar and not seats.is_empty() else -1
		if tv_menu != null and is_instance_valid(tv_menu) and (want_slot < 0 or want_slot != tv_menu_slot):
			tv_menu.queue_free()
			tv_menu = null
		if want_slot >= 0:
			split.set_shared(true)
			var items := _menu_items(menu_page, false)
			if tv_menu == null or not is_instance_valid(tv_menu):
				tv_menu_slot = want_slot
				tv_menu = UiMenu.open(huds[-1], {"title": _menu_title(menu_page), "party": party, "slot": want_slot,
					"items": items, "anchor": "left", "close_on_choose": false, "allow_cancel": menu_page != "main", "width": 520.0, "max_rows": 7})
				tv_menu.chosen.connect(func(id: String, _it: Dictionary) -> void: _menu_chosen(id, false, tv_menu_slot))
				tv_menu.cancelled.connect(func() -> void: _menu_back(false))
			else:
				tv_menu.call("set_items", items)
		elif split != null and not hangar:
			split.set_shared(false)
	# VR: a world-space menu in front of the cockpit.
	if vr_rig != null:
		if hangar:
			var vitems := _menu_items(vr_menu_page, true)
			if vr_menu == null or not is_instance_valid(vr_menu):
				vr_menu = VrMenu.open(self, {"title": _menu_title(vr_menu_page), "rig": vr_rig, "items": vitems,
					"close_on_choose": false, "allow_cancel": vr_menu_page != "main", "distance": 1.6, "max_rows": 6, "layers": Data.LAYER_VR_ONLY})
				vr_menu.chosen.connect(func(id: String, _it: Dictionary) -> void: _menu_chosen(id, true, 0))
			else:
				vr_menu.call("set_items", vitems)
		elif vr_menu != null and is_instance_valid(vr_menu):
			vr_menu.call("close")
			vr_menu.queue_free()
			vr_menu = null


func _reopen_menu(vr: bool) -> void:
	if vr:
		if vr_menu != null and is_instance_valid(vr_menu):
			vr_menu.queue_free()
		vr_menu = null
	elif tv_menu != null and is_instance_valid(tv_menu):
		tv_menu.queue_free()
		tv_menu = null
	_refresh_menus()


func _menu_back(vr: bool) -> void:
	if vr:
		vr_menu_page = "main"
	else:
		menu_page = "main"
	_reopen_menu(vr)


func _menu_chosen(id: String, vr: bool, slot: int) -> void:
	if id == "__back":
		_menu_back(vr)
		return
	match id:
		"missions", "upgrades", "paint":
			if vr:
				vr_menu_page = id
			else:
				menu_page = id
			_reopen_menu(vr)
		"launch":
			net.request(slot, "hangar", ["launch", ""])
		"turn":
			turn_mode = "snap" if turn_mode == "smooth" else "smooth"
			pilot.turn_mode = turn_mode
			save.data["turn"] = turn_mode
			save.mark_dirty()
			_reopen_menu(true)
		_:
			if id.begins_with("m"):
				net.request(slot, "hangar", ["select", id.substr(1)])
				if vr:
					vr_menu_page = "main"
				else:
					menu_page = "main"
				_reopen_menu(vr)
			elif id.begins_with("u_"):
				net.request(slot, "hangar", ["buy", id.substr(2)])
			elif id.begins_with("p_"):
				net.request(slot, "hangar", ["paint", id.substr(2)])


## Host: hangar actions from any machine.
func _hangar(action: String, arg: String) -> void:
	if String(net.state_get("phase", "")) != "hangar":
		return
	match action:
		"select":
			var i := clampi(int(arg), 0, Data.MISSIONS.size() - 1)
			if _mission_unlocked(i):
				net.state_set("sel", i)
				_set_map(i)
				_refresh_ai()
		"launch":
			_launch(int(net.state_get("sel", 0)))
		"buy":
			if not Data.UPGRADES.has(arg) or has_upgrade(arg):
				return
			var u: Dictionary = Data.UPGRADES[arg]
			if int(save.data["parts"]) < int(u["cost"]):
				return
			save.data["parts"] = int(save.data["parts"]) - int(u["cost"])
			(save.data["owned"] as Array).append(arg)
			save.mark_dirty()
			_publish_save()
			net.event("bought", [String(u["name"])])
			_bought_fx(String(u["name"]))
		"paint":
			if not Data.PAINTS.has(arg):
				return
			var paints: Array = save.data["paints"]
			if not paints.has(arg):
				var pi: Dictionary = Data.PAINTS[arg]
				if int(save.data["parts"]) < int(pi["cost"]):
					return
				save.data["parts"] = int(save.data["parts"]) - int(pi["cost"])
				paints.append(arg)
			save.data["paint"] = arg
			save.mark_dirty()
			_publish_save()


func _bought_fx(what: String) -> void:
	sfx.play("kaching", 0.0)
	if split != null:
		HudKit.toast(_all_huds(), "NEW: %s" % what, {"icon": "bolt", "color": "gold"})
	cockpit_message("NEW: " + what, UiKit.ACCENT, 2.0)


# --- Phases (host decides) --------------------------------------------------------------------------------

func _launch(i: int) -> void:
	if int(net.state_get("map", -1)) != i:
		_set_map(i)
	net.state_set("mission", i)
	_refresh_ai()
	net.state_set("phase", "briefing")
	briefing_t = 0.0
	_apply_upgrades()
	awards.reset()
	missions.start(i)  # resets the score / meters; steps begin once the briefing is over
	if SIMPLE_MODE:
		_start_play()  # no briefing
		return
	missions.active = false
	_play_briefing(i)


func _play_briefing(i: int) -> void:
	var lines: Array = []
	var m := mission_info(i)
	lines.append({"speaker": Data.COMMANDER, "color": Data.COMMANDER_COLOR, "text": "MISSION %d: %s" % [i + 1, String(m["name"])], "auto": 2.5})
	for t in m["brief"]:
		lines.append({"speaker": Data.COMMANDER, "color": Data.COMMANDER_COLOR, "text": String(t), "auto": 5.0})
	dlg.play(lines, {"skippable": true})
	if not dlg.line_started.is_connected(_on_dlg_line):
		dlg.line_started.connect(_on_dlg_line)
	if not dlg.finished.is_connected(_on_briefing_done):
		dlg.finished.connect(_on_briefing_done)


func _on_dlg_line(index: int, _line: Dictionary) -> void:
	if net.mode == "host":
		net.event("dlg", [index])


func _on_briefing_done() -> void:
	if net.mode == "client" or String(net.state_get("phase", "")) != "briefing":
		return
	_start_play()


func _start_play() -> void:
	net.state_set("phase", "play")
	missions.active = true
	sfx.play("go", 0.0)
	if SIMPLE_MODE:
		_apply_deep()
		deep.round_start()
		_refresh_all_vehicle_huds()
		net.event("unlocks", [])
		var r := int(net.state_get("mission", 0))
		var rm := mission_info(r)
		var later := 0.0
		if not momo_hello:  # Momo says hello once a session, before the first lost kaiju's card (SIMPLE: two capital words)
			momo_hello = true
			story({"who": "HI! MOMO!", "line": "HELP!", "pic": "momo", "color": MOMO_COLOR, "duration": 3.5})
			later = 3.6
		if bool(rm.get("gen", false)) and later > 0.0:
			get_tree().create_timer(later).timeout.connect(func() -> void:
				if String(net.state_get("phase", "")) == "play":
					story(_round_card(rm)))
		elif bool(rm.get("gen", false)):
			# A made round: the lost kaiju's picture (TODAY'S KAIJU for the daily golden one).
			story(_round_card(rm))
		var kinds := vehicle_kinds()
		if r > 0 and kinds.size() > Data.simple_vehicles(r - 1).size():
			# A new vehicle this round: its name + Y on the TV.
			var info: Dictionary = Data.VEHICLE_INFO[kinds[kinds.size() - 1]]
			_new_vehicle_toast(String(info["name"]))
			net.event("newveh", [String(info["name"])])
	else:
		announce("MISSION START!", "Go, Titans!", "level")
		if net.mode == "host":
			net.event("announce", ["MISSION START!", "Go, Titans!", "level"])
	if vr_rig != null:
		vr_rig.guard_trigger()


## The made round's story card: the lost kaiju (TODAY'S KAIJU for the golden one), or a BOSS KAIJU with its crown.
func _round_card(rm: Dictionary) -> Dictionary:
	var bb := String(rm.get("bigboss", ""))
	if bb != "":
		return {"who": "BIG BOSS!", "line": String(rm.get("name", "")), "pic": "crownkaiju",
			"color": (BigBoss.LIST[bb]["color"] as Color).to_html(false), "duration": 3.4, "sound": "drumroll"}
	return {"who": "TODAY'S KAIJU" if bool(rm.get("daily", false)) else String(rm.get("name", "")),
		"line": String(rm.get("name", "")) if bool(rm.get("daily", false)) else "HELP!",
		"pic": "kaiju", "color": _kaiju_color(rm), "duration": 3.2}


## Host: missions.gd finished the mission.
func mission_finished(i: int, win: bool, stars: int, parts: int, data: Dictionary) -> void:
	var cleared: Array = save.data["cleared"]
	if win and not cleared.has(i):
		cleared.append(i)
	var st: Array = save.data["stars"]
	while st.size() < Data.MISSIONS.size():
		st.append(0)
	st[i] = maxi(int(st[i]), stars)
	save.data["parts"] = int(save.data["parts"]) + parts
	save.mark_dirty()
	_publish_save()
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0


## SIMPLE_MODE (host): the round's kaiju went home. Cheer for a moment, then the next round.
func round_cleared(i: int) -> void:
	_round_telemetry(i, "home")
	_make_friends(i)
	net.state_set("results", {"win": true, "mission": i, "simple": true})
	net.state_set("phase", "results")
	results_t = 0.0
	combat.announce("HOORAY!", "", "victory")


## SIMPLE_MODE (host): a fresh city and the next round (it unlocks one new thing).
func _next_round() -> void:
	combat.clear()
	var next := int(net.state_get("mission", 0)) + 1
	net.state_set("sel", next)
	net.state_set("bld", PackedByteArray())
	net.state_set("cit", PackedByteArray())
	net.state_set("rings", {})
	_set_map(next)
	_launch(next)


# --- Deep flow: frame / difficulty / upgrade pods (host) -------------------------------------------------------

## Host, session start: FRAME pods when the family has two or more frames, then round 1 (or the bot's round).
func _deep_start() -> void:
	var h := Sanctuary.hearts(save.data)
	var fr := String(save.data.get("frame", "titan"))
	if not Frames.unlocked(h).has(fr):
		fr = "titan"
	var try := OS.get_environment("MT_TRY")
	var md := OS.get_environment("MT_MODE")
	if md == "" and try == "mega":
		md = "mega" if bool(save.data.get("mega_ok", false)) else ""
	if md != "" and RoundGen.valid_mode(md):
		net.state_set("mode", md)
		mode_picked = true
	else:
		net.state_set("mode", "gentle")
	if OS.has_environment("MT_FRAME") and Frames.valid(OS.get_environment("MT_FRAME")):
		fr = OS.get_environment("MT_FRAME")
	net.state_set("frame", fr)
	var u: Array = []
	for id in OS.get_environment("MT_UPG").split(",", false):
		if Upgrades.index_of(id) >= 0 and not u.has(id):
			u.append(id)
	net.state_set("upg", u)
	if OS.has_environment("MT_PICK_WAIT"):
		pick_wait = maxf(1.0, float(OS.get_environment("MT_PICK_WAIT")))
	var start := test_start_round
	if try == "boss":
		start = RoundGen.LESSONS + RoundGen.BOSS_EVERY - 1  # What's New: straight to the first boss kaiju
	elif try == "pods":
		start = RoundGen.LESSONS
		pick_queue.append("upgrade")
	if start == 0 and not OS.has_environment("MT_NO_PICKS") and Frames.unlocked(h).size() >= 2:
		pick_queue.push_front("frame")
	if pick_queue.is_empty():
		_launch(start)
	else:
		set_meta("pick_then", start)
		_continue_picks()


## Host: the round's cheer is over: pods before the next round (difficulty once, then an upgrade), or go on.
func _after_cheer() -> void:
	var next := int(net.state_get("mission", 0)) + 1
	pick_queue.clear()
	if next >= RoundGen.LESSONS and not OS.has_environment("MT_NO_PICKS"):
		if not mode_picked and next == RoundGen.LESSONS and Sanctuary.hearts(save.data) >= Sanctuary.BRAVE_HEARTS:
			pick_queue.append("mode")
		if not _upgrade_offer(next).is_empty():
			pick_queue.append("upgrade")
	if pick_queue.is_empty():
		_next_round()
		return
	set_meta("pick_then", -1)
	_continue_picks()


func _upgrade_offer(next: int) -> Array:
	return Upgrades.offer(int(net.state_get("run_seed", 0)), next, Upgrades.unlocked(Sanctuary.hearts(save.data)), upg_list())


## Host: land the next pods in the queue, or start the round.
func _continue_picks() -> void:
	if pick_queue.is_empty():
		net.state_set("pick", {})
		var then := int(get_meta("pick_then", -1))
		if then >= 0:
			set_meta("pick_then", -1)
			_launch(then)
		else:
			_next_round()
		return
	var kind: String = pick_queue.pop_front()
	var ids: Array = []
	var def := 0
	match kind:
		"frame":
			ids = Frames.unlocked(Sanctuary.hearts(save.data))
			if ids.size() > 3:
				# three pods: the frame you had, then the newest ones
				var cur := String(net.state_get("frame", "titan"))
				var rest: Array = ids.filter(func(x: Variant) -> bool: return String(x) != cur)
				ids = [cur] + rest.slice(rest.size() - 2)
			def = maxi(0, ids.find(String(net.state_get("frame", "titan"))))
		"mode":
			ids = ["gentle", "brave"]
			if bool(save.data.get("mega_ok", false)):
				ids.append("mega")
			def = 0
		_:
			var next := int(net.state_get("mission", 0)) + 1 if int(get_meta("pick_then", -1)) < 0 else int(get_meta("pick_then", 0))
			ids = _upgrade_offer(next)
			def = ids.size() / 2
	if ids.size() < 2 and kind != "upgrade" or ids.is_empty():
		_continue_picks()
		return
	pick_t = 0.0
	pick_done_t = -1.0
	var n := int(net.state_get("pick_n", 0)) + 1
	net.state_set("pick_n", n)
	combat.clear()
	mech.velocity = Vector3.ZERO
	net.state_set("pick", {"n": n, "kind": kind, "ids": ids, "def": def, "wait": pick_wait,
		"at": Picks.places(mech.global_position, mech.forward(), ids.size(), city)})
	net.state_set("phase", "pick")


## Host, phase "pick": someone walked / flew into a pod, or time's up (the default pod).
func _pick_tick(delta: float) -> void:
	if pick_done_t >= 0.0:
		pick_done_t -= delta
		if pick_done_t < 0.0:
			_continue_picks()
		return
	pick_t += delta
	var hit := picks.touched(mech, support.vehicles)
	if not hit.is_empty():
		_take_pick(int(hit[0]), int(hit[1]))
	elif pick_t > pick_wait:
		_take_pick(int((net.state_get("pick", {}) as Dictionary).get("def", 0)), -1)


func _take_pick(i: int, by: int) -> void:
	var p: Dictionary = net.state_get("pick", {})
	var ids: Array = p.get("ids", [])
	if i < 0 or i >= ids.size():
		return
	var id := String(ids[i])
	var kind := String(p.get("kind", "upgrade"))
	picks.taken = true
	picks_taken += 1
	var at: Vector3 = (p.get("at", []) as Array)[i]
	var col := Picks.pod_color(kind, id)
	combat.emit_fx("burst", ["stars", at + Vector3.UP * 6.0, 5.0])
	combat.emit_fx("ring", [at + Vector3.UP * 0.5, 9.0, col])
	combat.emit_fx("sfx", ["power_up", at, 6.0, 0.8])
	var pic := "titanpod"
	match kind:
		"frame":
			net.state_set("frame", id)
			save.data["frame"] = id
			pic = "titanframe"
			_publish_save()
		"mode":
			net.state_set("mode", id)
			save.data["mode"] = id
			mode_picked = true
			pic = "crownkaiju" if id == "mega" else ("star" if id == "brave" else "heart")
		_:
			var u := upg_list().duplicate()
			if not u.has(id):
				u.append(id)
			net.state_set("upg", u)
			if id == "dome":
				net.state_set("dome", true)
	save.mark_dirty()
	_apply_deep()
	story({"who": Picks.pod_name(kind, id), "line": "YAY!" if by >= 0 else "GO!", "pic": pic, "color": col.to_html(false),
		"duration": 2.6, "sound": "achievement"})
	pick_done_t = 1.6


func _refresh_all_vehicle_huds() -> void:
	for slot in hud_w:
		_refresh_vehicle_hud(int(slot))


func _new_vehicle_toast(vname: String) -> void:
	_refresh_all_vehicle_huds()
	if split != null and not SIMPLE_MODE:  # SIMPLE_MODE: Y + an arrow + the new vehicle (teach.gd)
		HudKit.toast(_all_huds(), "NEW: %s  (Y)" % vname, {"icon": "star", "color": "gold", "duration": 4.0})
	sfx.play("reveal", -4.0)


func _back_to_hangar() -> void:
	combat.clear()
	var data: Dictionary = net.state_get("results", {})
	var next := int(net.state_get("sel", 0))
	if bool(data.get("win", false)):
		next = mini(int(data.get("mission", 0)) + 1, Data.MISSIONS.size() - 1)
	net.state_set("sel", next)
	net.state_set("bld", PackedByteArray())
	net.state_set("cit", PackedByteArray())
	_set_map(next)  # a fresh (repaired) city on every machine
	net.state_set("phase", "hangar")
	_refresh_ai()
	_apply_upgrades()


# --- State changes (every machine) -------------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"map_gen":
			built_map = -2
			_build_map(int(net.state_get("map", 0)))
		"bld":
			if city != null:
				var changed := city.apply_states(value)
				if net.mode == "client":
					for i in changed:
						var rec: Dictionary = city.buildings[i]
						if int(rec["state"]) == City.STATE_RUBBLE:
							fx.debris(rec["pos"], rec["size"], [rec["wall"], rec["roof"]], 20)
		"cit":
			if city != null:
				support.apply_citizens(value)
		"veh":
			support.sync(value)
			_refresh_group()
		"save":
			var d: Dictionary = value
			if SIMPLE_MODE:
				mech.set_paint(String(frame_info()["paint"]))  # the frame's paint (frames.gd)
			else:
				mech.set_paint(String(d.get("paint", "classic")))
			_refresh_menus()
		"frame":
			mech.set_paint(String(Frames.info(String(value))["paint"]))
		"pick":
			if picks != null:
				picks.sync(value)
		"sel":
			_refresh_menus()
		"score", "cdmg", "landmark", "rescued", "rescue_total", "objective":
			_refresh_hud()
		"phase":
			_on_phase(String(value))
		"boss_intro":
			var arr: Array = value
			_boss_intro(arr[1])
		"rings":
			if toys != null:
				toys.sync_rings(value)
		"round_info":
			if net.mode == "client" and value is Dictionary and int((value as Dictionary).get("index", -1)) == int(net.state_get("map", -1)):
				built_map = -2  # a made round arrived after the map: build it with the right look
				_build_map(int(net.state_get("map", 0)))
		"friends_list":
			if value is Array and world_root != null:
				_build_parade(value)


func _on_phase(phase: String) -> void:
	_refresh_menus()
	_refresh_hud()
	_refresh_group()
	match phase:
		"hangar":
			_hide_results()
			music.play_mood("overworld")
			if split != null and not SIMPLE_MODE:
				HudKit.banner(_all_huds(), "TITAN HANGAR", "Pick a mission, buy upgrades. Y: change vehicle", {"duration": 3.0})
		"briefing":
			music.play_mood("tension")
			if split != null:
				split.set_shared(false)
		"play":
			music.play_mood("battle")
			if SIMPLE_MODE:
				_refresh_all_vehicle_huds()
			if net.mode == "client" and dlg.is_playing():
				dlg.stop()
		"results":
			_show_results(net.state_get("results", {}))
		"pick":
			_hide_results()
			music.play_mood("overworld")
			sfx.play("reveal", -2.0)


func _boss_intro(list: Array) -> void:
	for i in list.size():
		var k: String = list[i]
		var info: Dictionary = Data.KAIJU.get(k, {})
		if info.is_empty():
			continue
		if SIMPLE_MODE and list.size() == 1:
			var rm := mission_info(int(net.state_get("mission", 0)))
			if bool(rm.get("gen", false)):
				info = info.duplicate()
				info["name"] = String(rm.get("name", info["name"]))  # TINY ZAPPY, PINK WOBBLES...
		var delay := float(i) * 2.6
		get_tree().create_timer(delay + 0.5).timeout.connect(func() -> void:
			if split != null and SIMPLE_MODE:
				HudKit.banner(_all_huds(), String(info["name"]), "", {"style": "boss", "duration": 2.4})
			elif split != null:
				HudKit.banner(_all_huds(), String(info["name"]), String(info["title"]), {"style": "boss", "duration": 2.4})
				HudKit.toast(_all_huds(), String(info["tip"]), {"icon": "eye", "color": "warn", "duration": 6.0})
			cockpit_message(String(info["name"]) + "!", Color(1.0, 0.5, 0.4), 2.4)
			sfx.play("drumroll", -4.0))


func _show_results(data: Dictionary) -> void:
	_hide_results()
	if data.is_empty():
		return
	if SIMPLE_MODE:
		# A cheer instead of a results screen: music and stars bursting round the Titan.
		music.play_mood("victory")
		sfx.play("cheer", -2.0)
		for k in 6:
			var a := k * TAU / 6.0
			fx.burst("stars", mech.chest_world() + Vector3(cos(a) * 6.0, 4.0 + (k % 2) * 3.0, sin(a) * 6.0), 3.0)
		return
	music.play_mood("victory" if bool(data.get("win", false)) else "defeat")
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(huds[-1], data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "continue", []))
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
		card.continued.connect(func() -> void: net.request(0, "continue", []))
		vr_results = card


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
	vr_results = null


## True while results are on screen (bots).
func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- Requests (host / local) ------------------------------------------------------------------------------

func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"hold":
			var v: Support.Vehicle = support.vehicles.get(slot, null)
			if v != null and not party.is_local(slot):
				v.hold_a = bool(args[0])
				v.hold_x = bool(args[1])
		"vehicle_next":
			var veh: Dictionary = (net.state_get("veh", {}) as Dictionary).duplicate()
			var kinds := vehicle_kinds()
			if veh.has(slot) and kinds.size() > 1:
				var i := kinds.find(String(veh[slot]))
				veh[slot] = kinds[(i + 1) % kinds.size()]
				net.state_set("veh", veh)
				_refresh_ai()
		"hangar":
			_hangar(String(args[0]), String(args[1]))
		"dlg_next":
			if dlg.is_playing():
				dlg.advance()
		"continue":
			if results_showing():
				_back_to_hangar()


## Host: a TV seat moved its vehicle.
func on_remote_state(slot: int, pos: Vector3, yaw: float, pitch: float) -> void:
	support.remote_state(slot, pos, yaw, pitch)


func on_client_joined() -> void:
	sfx.play("ui_notify", -6.0)


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "Paused by %s" % ("the pilot" if by_slot == 0 else Who.seat(self, by_slot))
	if SIMPLE_MODE:
		why = ""  # just PAUSED (no sentence)
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_paused(self, vr_rig.camera, "" if SIMPLE_MODE else "Wrist MENU: carry on", {"width": 1.1})
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
			UiKit.pin(tv_banner, Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		var wl := tv_banner.find_child("Why", true, false) as Label
		wl.text = why
		wl.visible = why != ""
		# the pause menu open on this machine already says PAUSED: don't draw a second one under it
		var menu_open: bool = pause_menu != null and pause_menu.get("panel") != null and (pause_menu.panel as Control).visible
		tv_banner.visible = paused and not (SIMPLE_MODE and menu_open)
		if paused:
			UiKit.pop_in(tv_banner)
	if paused:
		Engine.time_scale = 1.0


# --- Game loop ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play or city == null:
		return
	var phase := String(net.state_get("phase", "hangar"))
	_animate_parade(delta)
	if net.mode == "client":
		mech.client_tick(delta)
		combat.client_tick(delta)
		support.client_tick(delta)
	else:
		var out := pilot.update(delta, mech, combat)
		var intent: Dictionary = out["intent"]
		if phase != "play" and phase != "pick":  # pods: walk the Titan into one
			intent.erase("move")
			intent.erase("move_world")
			intent.erase("turn")
			intent.erase("snap")
			intent.erase("face")
			intent["dash"] = false
		if not move_ok("dash"):
			intent["dash"] = false
		mech.simulate(delta, intent)
		if teach != null:
			teach.note_pilot(out, intent, phase)
		combat.tick(delta)
		if phase == "play":
			combat.pilot_actions(delta, out)
			support.tick(delta)
			missions.tick(delta)
		else:
			mech.beam_on = false
			mech.foam_on = false
			combat._set_beam_sound(false)
		if mech.finish_reboot_if_due():
			pass
		if phase == "briefing":
			briefing_t += delta
			if briefing_t > 60.0 or (not dlg.is_playing() and briefing_t > 1.0):
				_start_play()
		elif phase == "results":
			results_t += delta
			if SIMPLE_MODE and results_t > CHEER_TIME:
				_after_cheer()
			elif results_t > 40.0:
				_back_to_hangar()
		elif phase == "pick":
			_pick_tick(delta)
		elif phase == "hangar" and auto_launch >= 0 and not dlg.is_playing():
			var al := auto_launch
			auto_launch = -1
			_launch(al)
	support.drive_local(delta, phase == "play" or phase == "hangar" or phase == "pick")
	if deep != null:
		if net.mode != "client":
			deep.host_tick(delta, phase)
		deep.visual_tick(delta)
	support.visual_tick(delta)
	_tick_hud(delta)
	if teach != null:
		teach.tick(delta)
	if ghost != null:
		var pk := missions.practice_kind if missions != null else ""
		var gk := "punch" if pk.begins_with("punch") else ("beam" if pk == "beam" else "")
		ghost.show_move(gk if phase == "play" else "", missions.practice_target if missions != null else Vector3.ZERO, delta)
	if vr_rig != null:
		var vig := clampf(mech.speed / Mech.WALK_SPEED * 0.55 + mech.turning * 0.75 + (0.9 if mech.dash_t > 0.0 else 0.0), 0.0, 1.0)
		mech.cockpit.set_vignette(vig)


# --- Networking -------------------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	return [pose, mech.pack_net(), combat.pack_kaiju(), support.pack(), combat.pack_boulders()]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or city == null or s.size() < 5:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	if split != null and (s[0] as PackedFloat32Array).is_empty():
		split.clear_bubble()  # a flat host: no VR player to show in the bubble
	mech.apply_net(s[1])
	combat.apply_kaiju(s[2])
	support.apply(s[3])
	combat.apply_boulders(s[4])


func apply_event(kind: String, args: Array) -> void:
	if combat == null:
		return
	match kind:
		"story":
			if args.size() > 0 and args[0] is Dictionary:
				show_story(args[0])
		"fx":
			combat.play_fx(String(args[0]), args[1])
		"announce":
			announce(String(args[0]), String(args[1]), String(args[2]))
		"spin":
			support.on_spin_event(int(args[0]))
		"squash":
			if city != null:
				city.squash_at(args[0], float(args[1]))
		"radio":
			_radio_local(String(args[0]))
		"hint":
			_hint_tv_local(String(args[0]), String(args[1]), int(args[2]))
		"unlocks":
			_refresh_all_vehicle_huds()
		"newveh":
			_new_vehicle_toast(String(args[0]))
		"bought":
			_bought_fx(String(args[0]))
		"dlg":
			_client_dialogue(int(args[0]))


## TV machine: mirror the host's briefing line by line.
func _client_dialogue(index: int) -> void:
	if not dlg.is_playing():
		var m := mission_info(int(net.state_get("mission", 0)))
		var lines: Array = [{"speaker": Data.COMMANDER, "color": Data.COMMANDER_COLOR, "text": "MISSION %d: %s" % [int(net.state_get("mission", 0)) + 1, String(m["name"])]}]
		for t in m["brief"]:
			lines.append({"speaker": Data.COMMANDER, "color": Data.COMMANDER_COLOR, "text": String(t)})
		dlg.play(lines, {"remote": true})
		if not dlg.advance_requested.is_connected(_client_advance):
			dlg.advance_requested.connect(_client_advance)
	dlg.show_line(index)


func _client_advance() -> void:
	var seats := party.local_slots()
	net.request(seats[0] if not seats.is_empty() else 1, "dlg_next", [])
