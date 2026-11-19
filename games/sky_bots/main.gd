extends Node3D
## SKY BOTS: a cheerful co-op robot platformer in the clouds.
## - Every TV / Deck player is a little tin ROBOT with a propeller cap (robot.gd): left stick runs, A jumps, hold A
##   while falling to hover, X punches. Falling off just pops you back at your last checkpoint flag. Nobody is ever out.
## - GIZMO TOWN (hub.gd) is home: GRANNY GIZMO's Sky Lamp went dark when CRANKY CRAB took its sparks (story.gd). The
##   team picks an island on pick orbs (picks.gd, core/pick_flow.gd): MEADOW HOP, GEAR WORKS, CRAB COVE (each opens
##   when the one before is cleared) and TODAY'S ISLAND. GENTLE / BRAVE / HARD once a session.
## - Every island is generated (levelgen.gd; check() proves it can be finished): hops, movers, lifts, GRUMBLE bots (they
##   wind up on a warn line before they charge), ZAP PADS (they flash on a warn ring before they buzz), BOLTS to collect,
##   one SECRET room behind a cracked wall with a GOLD GEAR, and the SPARK at the end. Crab Cove ends with CRANKY CRAB
##   (boss.gd): it tells its stomp with warn rings, then it's dizzy - punch it!
## - The VR player (slot 0, host) is the GIANT looking down on the island like a toy diorama (giant.gd): lifts the lifts,
##   flicks grumbles off, pokes the crab and the cracked wall, picks up bolts. A ghost glove (core/ghost_hand.gd) shows
##   how to lift a lift. Solo VR: CPU buddies BIP and BOP (brain.gd) run the islands and the giant helps them.
## - A spark brought home lights the Sky Lamp and builds Gizmo Town; each gold gear builds more (saved).
## - CHAPTER TWO (after Crab Cove): SNOWY PEAKS (spring pads), JUNGLE JUMBLE (wind fans), CLOCKWORK KEEP (conveyor
##   belts, and KING KEYWIND: he tells his charge with a warn line, dashes, bonks the rim, then he's dizzy). Every island
##   has two BOT BOXES with LITTLE BOTS inside (bump, punch or pound them open): they move to Gizmo Town and sew costume
##   HATS (hats.gd; Y in town swaps your hat). New moves: X in the air DASHES, B in the air GROUND POUNDS.
## - One RUN telemetry line per island (and on quit). The season dresses the town (core/season_kit.gd).
## Modes as in games/engine_template: local (split screen), host (VR on the Steam Frame, simulates everything), client
## (a TV / Deck machine: its robots move locally and instantly, the rest is mirrored from snapshots).

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const Save := preload("res://core/save.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const StoryCard := preload("res://core/story_card.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Seeded := preload("res://core/seeded.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Telemetry := preload("res://core/telemetry.gd")
const GhostHand := preload("res://core/ghost_hand.gd")
const G := preload("res://games/sky_bots/levelgen.gd")
const Level := preload("res://games/sky_bots/level.gd")
const Robot := preload("res://games/sky_bots/robot.gd")
const Brain := preload("res://games/sky_bots/brain.gd")
const Giant := preload("res://games/sky_bots/giant.gd")
const Boss := preload("res://games/sky_bots/boss.gd")
const Hub := preload("res://games/sky_bots/hub.gd")
const Hats := preload("res://games/sky_bots/hats.gd")
const Story := preload("res://games/sky_bots/story.gd")
const PicksScript := preload("res://games/sky_bots/picks.gd")

const GAME_ID := "sky_bots"
const HUB_WAIT := 5.0  ## seconds in Gizmo Town before the pick orbs pop up
const CHEER_TIME := 5.0
const BUDDIES := 2  ## solo VR: CPU buddies BIP and BOP
const VR_CARD_UP := 0.25
const CLOUD_Y := Giant.FLOOR_Y
const ISLE_COLORS: Array[Color] = [Color(0.5, 0.9, 0.45), Color(0.6, 0.75, 1.0), Color(1.0, 0.6, 0.45), Color(0.85, 0.93, 1.0),
	Color(0.35, 0.8, 0.5), Color(0.75, 0.55, 0.95)]

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
var sky: SkyKit.SkyRig

var level: Level
var hub: Hub
var giant: Giant
var boss: Boss
var picks: Node
var ghost: GhostHand
var robots := {}  ## rid -> Robot (slot 0..6 people, 10+ CPU buddies)
var brains := {}  ## rid -> Brain (host: CPU buddies)
var cams := {}  ## slot -> CameraRig
var group_cam: CameraRig  ## the shared view (nobody seated on this screen): frames all the robots
var huds := {}  ## slot -> UiKit root (-1 = the shared view)
var bolt_labels := {}  ## slot -> Label
var tiny_labels := {}  ## slot -> Label (little bots let out on this island)
var hat_prompts := {}  ## slot -> Control (Y: swap hat, in Gizmo Town)
var gear_pics := {}  ## slot -> Control
var prompts := {}  ## slot -> Control
var join_prompt: Control
var tv_banner: Control
var headline: Label3D
var headline_t := 0.0
var used := {}  ## slot -> {"jump": true, "punch": true} (the button prompt goes when both were used)
var built_key := ""  ## var_to_str of the island description built here ("" = the town)
var phase_t := 0.0
var island_t := 0.0
var send_t := 0.0
var hint_t := 0.0
var asked := {}  ## TV machine: bolts already asked for
var run := {}  ## host: this island's numbers (telemetry)
var told := {}  ## host: feature hints told this session
var mode := "brave"
var season := "spring"
var mode_picked := false
var session_seed := 0
var finish_log: Array = []  ## [island, rid, seconds] (bots)
var force_island := -1  ## bots / What's New: start straight on this island (SKY_ISLAND)
var hub_wait := HUB_WAIT  ## bots shorten it


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
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = Story.save_defaults()
	add_child(save)
	if int(save.data.world) < 0:
		save.data.world = Seeded.fresh_seed()  # this family's own islands
		save.mark_dirty()
	if Story.fix_save(save.data):
		save.mark_dirty()
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
	music.prepare(["victory", "overworld", "boss"])
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(m: String) -> void:
	var flat: bool = m == "host" and not net.has_vr
	if VrRig.wanted(m) and not flat:
		vr_rig = VrRig.new()
		add_child(vr_rig)
	_build_world(vr_rig != null)
	giant = Giant.new()
	add_child(giant)
	giant.setup(self, vr_rig, m != "client")
	if vr_rig != null:
		ghost = GhostHand.new()
		ghost.look = GhostHand.Look.GLOVE
		ghost.size = Giant.S
		add_child(ghost)
	if m != "host" or vr_rig == null:
		split = SplitView.new()
		split.camera_far = 900.0
		add_child(split)
		split.bind_party(party)
		var sc := split.shared_camera()
		sc.global_position = Vector3(0.0, 9.0, 13.0)
		UiKit.look(sc, Vector3(0.0, 0.5, -1.0), Vector3.UP)
		group_cam = CameraRig.new()
		group_cam.camera = sc
		group_cam.group_min_distance = 12.0
		add_child(group_cam)
		group_cam.follow_group([], -40.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		if m == "client":
			giant.make_avatar()
			split.set_bubble(VrRig.build_mirror(self, giant.avatar_head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = m != "client" and vr_rig == null
	picks = PicksScript.new()
	picks.main = self
	add_child(picks)
	net.sticky_event("orbs")  # a machine joining mid-pick sees the orbs
	if m != "client":
		if OS.has_environment("SKY_ISLAND"):  # (bots, screenshots, What's New "try": straight onto an island)
			force_island = clampi(int(OS.get_environment("SKY_ISLAND")), 0, G.ISLANDS)
		_begin_session()
	else:
		for k in ["deep", "hubp", "ldesc", "wall", "gear", "goal_on", "bolts", "cp", "boxes", "hats"]:
			if net.state_has(k):
				_on_state_changed(k, net.state_get(k, null))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Sky Bots: %s mode%s" % [m, " with a VR giant" if vr_rig != null else ""])


# --- World ------------------------------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	# The cloud floor far below (the giant stands on it): one soft disc and puffs.
	var b := MeshKit.Builder.new()
	b.cylinder(220.0, 220.0, 0.4, MeshKit.at(Vector3(0, CLOUD_Y - 0.2, 0)), Color(0.93, 0.95, 1.0), 40)
	var r := Seeded.rng(7, "clouds")
	for k in 40:
		var a := r.randf() * TAU
		var d := r.randf_range(12.0, 70.0)
		var p := Vector3(cos(a) * d, CLOUD_Y, sin(a) * d)
		if absf(p.x) < 40.0 and p.z > 2.0 and p.z < 14.0:
			continue  # (keep the giant's walk clear)
		b.sphere(r.randf_range(2.0, 4.5), MeshKit.at(p, Vector3(1.6, 0.6, 1.2)), Color(1.0, 1.0, 1.0), 10)
	add_child(MeshKit.instance(b.build(), false))
	hub = Hub.new()
	hub.name = "Hub"
	add_child(hub)
	hub.build(season)
	level = Level.new()
	level.name = "Level"
	add_child(level)


func _on_hot_reload() -> void:
	pass


# --- The session (host / local decide; every machine builds from "ldesc") -----------------------------------------

func _begin_session() -> void:
	session_seed = Seeded.fresh_seed()
	season = SeasonKit.override(GAME_ID, Seeded.season(), SeasonKit.SEASONS)
	mode = G.mode_of(String(save.data.mode) if String(save.data.mode) != "" else "brave")
	if net.forced_mode("SKY_MODE") != "":
		mode = G.mode_of(net.forced_mode("SKY_MODE"))
		mode_picked = true
	if force_island >= 0:
		mode_picked = true
	_send_deep()
	_send_hub(false)
	hub.build(season)
	hub.apply(Story.power(save.data), false)
	hub.set_lamp(_sparks_lit())
	hub.set_tiny(int(save.data.tiny), false)
	_send_hats()
	if not bool(save.data.intro):
		save.data.intro = true
		save.mark_dirty()
		for k in ["intro1", "intro2", "intro3"]:
			_story(k)
	else:
		_story("back")
	_go_hub()


func _send_deep() -> void:
	net.state_set("deep", [mode, season])
	net.state_set("mode", mode)  # (the shared "host's difficulty" key: tests/bot_kit.gd check_host_mode)


## Host: how far Gizmo Town has grown, for every machine.
func _send_hub(pop: bool) -> void:
	net.state_set("hubp", [Story.power(save.data), _sparks_lit(), pop, int(save.data.tiny)])


func _sparks_lit() -> int:
	return Story.sparks_lit(int(save.data.cleared))


func phase() -> String:
	return String(net.state_get("phase", "hub"))


func _go_hub() -> void:
	phase_t = 0.0
	if boss != null:
		boss.queue_free()
		boss = null
	net.state_set("ldesc", {})
	net.state_set("phase", "hub")
	_build_island({})
	music.play_mood("town")


## Host: put up the pick orbs in the town.
func _start_pick(stage: String) -> void:
	var entries: Array = []
	var opts: Array = []
	var def := 1
	if stage == "mode":
		opts = PickOrbs.mode_ids(mode)
		for id in opts:
			var md := PickOrbs.mode(String(id))
			entries.append({"id": id, "name": md.name, "pic": md.pic, "color": md.color})
		def = opts.find(mode)
		_story("mode")
	else:
		var today_done := String(save.data.daily_done) == Seeded.today()
		var open := Story.pick_set(int(save.data.cleared), today_done)
		var sug := Story.suggest(int(save.data.cleared), today_done)
		for i in open:
			opts.append(int(i))
			if int(i) == 0:
				entries.append({"id": "daily", "name": "TODAY", "pic": "skyisland", "color": Color(1.0, 0.85, 0.35)})
			else:
				entries.append({"id": "isle%d" % int(i), "name": G.ISLAND_NAMES[int(i) - 1], "pic": G.ISLAND_PICS[int(i) - 1],
					"color": ISLE_COLORS[int(i) - 1]})
		def = maxi(0, opts.find(sug))
		_story("pick" if not opts.has(0) or today_done else "daily")
	net.state_set("phase", "pick")
	sound_at("bell", Hub.CENTER + Vector3(0, 2, 2), -6.0, 1.3)
	picks.begin(stage, entries, opts, vr_rig != null and _people() == 0, def, _on_picked)


func _on_picked(stage: String, opt: Variant, _slot: int) -> void:
	if stage == "mode":
		mode = G.mode_of(String(opt))
		mode_picked = true
		save.data.mode = mode
		save.mark_dirty()
		_send_deep()
		var beat := Story.line("mode")
		beat.line = String(PickOrbs.MODE_LINES.get(mode, "Let's go!"))
		beat.pic = String(PickOrbs.mode(mode).pic)
		beat.color = PickOrbs.mode_color(mode)
		_story_beat(beat)
		print("Picked mode: %s" % mode)
		net.state_set("phase", "hub")
		phase_t = hub_wait - 1.0
		return
	_go_island(int(opt))


## Nobody here could take a pick (no robot that's a person, no VR giant): the suggested one comes sooner.
func pick_nobody() -> bool:
	return vr_rig == null and _people() == 0


func _people() -> int:
	var n := 0
	for rid in robots:
		n += 1 if int(rid) < 10 else 0
	return n


## Host: off to island i (0 = TODAY'S ISLAND).
func _go_island(i: int) -> void:
	var desc: Dictionary
	if i == 0:
		desc = G.daily_desc(mode)
		save.data.daily = Seeded.today()
	else:
		var visits: Array = save.data.visits
		desc = {"i": i, "s": Seeded.derive(int(save.data.world), "island %d visit %d" % [i, int(visits[i])]), "m": mode}
		visits[i] = int(visits[i]) + 1
		save.data.visits = visits
		if OS.has_environment("SKY_SEED") and not has_meta("seeded"):  # (bots, screenshots: replay one island)
			set_meta("seeded", true)
			desc.s = int(OS.get_environment("SKY_SEED"))
	save.mark_dirty()
	island_t = 0.0
	told.clear()
	net.state_set("wall", false)
	net.state_set("gear", false)
	net.state_set("bolts", PackedInt32Array())
	net.state_set("cp", 0)
	net.state_set("boxes", 0)
	net.state_set("ldesc", desc)
	_build_island(desc)
	net.state_set("goal_on", (level.lv.boss as Dictionary).is_empty())
	net.state_set("phase", "play")
	run = {"island": i, "seed": int(desc.s), "attempt": int(level.lv.get("attempt", 0)), "bolts": 0, "falls": 0, "bumps": 0,
		"zaps": 0, "pops": 0, "punches": 0, "jumps": 0, "gear": false, "lifts": 0, "flicks": 0, "crab_hits": 0, "tiny": 0,
		"springs": 0, "dashes": 0, "pounds": 0, "boss": String((level.lv.boss as Dictionary).get("kind", ""))}
	for rid in brains:
		(brains[rid] as Brain).reset()
	print("Sky Bots island %d (%s): seed %d, %s, attempt %d, %d platforms, %d bolts" % [i, G.island_name(desc), int(desc.s), mode,
		int(level.lv.get("attempt", 0)), (level.lv.plats as Array).size(), (level.lv.bolts as Array).size()])


## Every machine: build island d ({} = Gizmo Town).
func _build_island(d: Dictionary) -> void:
	built_key = var_to_str(d) if not d.is_empty() else ""
	asked.clear()
	if d.is_empty():
		level.build({}, "meadow", season, net.mode != "client")
		level.lv = {}
		level.visible = false
		hub.visible = true
		hub.process_mode = Node.PROCESS_MODE_INHERIT
		_place_all_hub()
		if ghost != null:
			ghost.hide_demo()
		_refresh_hud()  # (the island's bolt card goes away in town)
		return
	var lv := G.generate(d)
	hub.visible = false
	hub.process_mode = Node.PROCESS_MODE_DISABLED  # (its floor's collision goes too: robots fell onto the hidden town)
	level.visible = true
	level.build(lv, G.theme_of(d), season, net.mode != "client")
	level.set_bolts(net.state_get("bolts", PackedInt32Array()) if net.mode == "client" else PackedInt32Array())
	level.set_boxes(int(net.state_get("boxes", 0)) if net.mode == "client" else 0)
	if boss != null:
		boss.queue_free()
		boss = null
	if not (lv.boss as Dictionary).is_empty():
		boss = Boss.new()
		boss.name = "CrankyCrab"
		add_child(boss)
		boss.setup(self, lv.boss, G.mode_of(String(d.get("m", "brave"))), net.mode != "client")
	var ids := robots.keys()
	ids.sort()
	var n := 0
	for rid in ids:
		var r: Robot = robots[rid]
		r.checkpoint = 0
		if r.owned:
			r.place(_start_spot(n))
		n += 1
	if split != null:
		HudKit.banner(_all_huds(), G.island_name(d), "", {"duration": 2.2})
	show_headline(G.island_name(d) + "!")
	for slot in cams:
		var c: CameraRig = cams[slot]
		c.yaw = -PI * 0.5
		c.snap()
	music.play_mood("overworld")
	_refresh_hud()


func _start_spot(n: int) -> Vector3:
	var s: Vector3 = level.lv.start
	return s + Vector3(-float(n % 3) * 0.7, 0.1, (float(n / 3) - 0.5) * 0.9 if n >= 3 else (float(n) - 1.0) * 0.8)


func _place_all_hub() -> void:
	var ids := robots.keys()
	ids.sort()
	var n := 0
	for rid in ids:
		var r: Robot = robots[rid]
		if r.owned:
			r.place(Hub.spawn(n, ids.size()))
			r.rotation.y = PI
		n += 1


## Where a robot that fell pops back: its checkpoint flag on an island, the town's front in Gizmo Town.
func respawn_point(r: Robot) -> Vector3:
	if level.lv.is_empty():
		return Hub.spawn(int(r.rid) % 7, 7)
	var cps: Array = level.lv.cps
	var k := clampi(r.checkpoint, 0, cps.size() - 1)
	var off := Vector3(-float(int(r.rid) % 3) * 0.4, 0.3, (float(int(r.rid) % 3) - 1.0) * 0.5)
	if brains.has(r.rid):
		(brains[r.rid] as Brain).respawned(level.lv, k)
	return (cps[k][1] as Vector3) + off


func fall_y() -> float:
	return (float(level.lv.low_y) - G.FALL_BELOW) if not level.lv.is_empty() else -4.0


## Robot r's gadgets this physics frame (robot.gd step): a belt's push under its feet (x) and a fan's updraft (y).
func gadget_push(r: Robot, on_floor: bool) -> Vector3:
	if level.lv.is_empty() or phase() != "play":
		return Vector3.ZERO
	var out := Vector3(0.0, G.fan_up(level.lv, r.position + Vector3.UP * 0.3), 0.0)
	if on_floor:
		out.x = G.belt_push(level.lv, r.position)
	return out


# --- Robots ---------------------------------------------------------------------------------------------------------

## Host: the robots that should exist: everyone seated (not the VR giant), plus BIP and BOP when only the giant plays.
func _sync_robots() -> void:
	var want: Array[int] = []
	for s in party.active_slots():
		if s != 0 or vr_rig == null:
			want.append(s)
	if want.is_empty() and vr_rig != null:
		for k in BUDDIES:
			want.append(10 + k)
	for rid in want:
		if not robots.has(rid):
			var owned := rid >= 10 or party.is_local(rid)
			var r := _make_robot(rid, owned)
			if owned:
				r.place(_join_spot(rid))
	for rid in robots.keys():
		if not want.has(int(rid)):
			_remove_robot(int(rid))


func _join_spot(rid: int) -> Vector3:
	if level.lv.is_empty():
		return Hub.spawn(rid % 7, 7)
	var cps: Array = level.lv.cps
	var k := int(net.state_get("cp", 0))
	return (cps[clampi(k, 0, cps.size() - 1)][1] as Vector3) + Vector3(0, 0.3, 0)


func _make_robot(rid: int, owned: bool) -> Robot:
	var r := Robot.new()
	r.main = self
	r.rid = rid
	r.owned = owned
	r.is_cpu = rid >= 10
	r.color = Robot.CPU_COLORS[(rid - 10) % Robot.CPU_COLORS.size()] if rid >= 10 else party.color_of(rid)
	r.name = "Robot%d" % rid
	add_child(r)
	r.place(_join_spot(rid))
	robots[rid] = r
	if rid >= 10 and net.mode != "client":
		brains[rid] = Brain.new()
	HudKit.nameplate(r, _name_of(rid), rid if rid < 10 else Robot.CPU_COLORS[(rid - 10) % Robot.CPU_COLORS.size()], 1.6, 0.26)
	if rid < 10 and party.is_local(rid) and split != null:
		_add_view(rid, r)
	return r


func _remove_robot(rid: int) -> void:
	if robots.has(rid):
		(robots[rid] as Node).queue_free()
		robots.erase(rid)
	brains.erase(rid)
	if cams.has(rid):
		(cams[rid] as Node).queue_free()
		cams.erase(rid)
	if huds.has(rid):
		var h: Control = huds[rid]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(rid)
	bolt_labels.erase(rid)
	tiny_labels.erase(rid)
	hat_prompts.erase(rid)
	gear_pics.erase(rid)
	prompts.erase(rid)


func _add_view(slot: int, r: Robot) -> void:
	var c := CameraRig.new()
	c.camera = split.camera(slot)
	c.party = party
	c.slot = slot
	c.pivot_height = 1.0
	c.distance = 7.0
	c.pitch = -0.42
	c.yaw = -PI * 0.5
	c.auto_behind = 0.8
	add_child(c)
	c.follow(r, 7.0, 0.0)
	cams[slot] = c
	_make_hud(slot, split.hud(slot))


func _name_of(rid: int) -> String:
	if rid >= 10:
		return Robot.CPU_NAMES[(rid - 10) % Robot.CPU_NAMES.size()]
	return party.name_of(rid)


func _on_player_joined(slot: int, _device: int) -> void:
	if net.mode == "client":
		if party.is_local(slot) and not robots.has(slot):
			_make_robot(slot, true)
	else:
		_sync_robots()
	sfx.play("ui_notify", -6.0)
	_refresh_hud()


func _on_player_left(slot: int) -> void:
	if net.mode == "client" or robots.has(slot):
		_remove_robot(slot)
	if net.mode != "client":
		_sync_robots()
	_refresh_hud()


## Host: one machine left: its seats leave through core/party.gd (player_left for each).
func on_machine_left(_peer: int) -> void:
	pass


# --- The game loop ----------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not ready_to_play:
		return
	level.physics(delta)
	if net.mode == "client":
		_step_owned(delta)
		return
	_sync_robots()
	var ph := phase()
	for rid in brains:
		var r: Robot = robots.get(rid)
		if r == null:
			continue
		var br: Brain = brains[rid]
		if ph == "play":
			br.think(r, level, boss, delta)
			r.inp_move = br.out_move
			r.inp_hold = br.out_hold
			if br.out_jump:
				r.inp_jump = true
			if br.out_punch:
				r.inp_punch = true
			if br.stuck_t > 12.0 and String(((level.lv.route as Array)[br.k] as Dictionary).act) != "boss":
				br.warps += 1  # a CPU buddy really stuck: hops on to its next step (never a person)
				br.stuck_t = 0.0
				r.place(br.target(level, br.k) + Vector3(0, 0.4, 0))
				br.k = mini(br.k + 1, (level.lv.route as Array).size() - 1)
		else:
			r.inp_move = Vector3.ZERO
	_step_owned(delta)
	giant.step(delta)
	match ph:
		"hub":
			phase_t += delta
			if phase_t > hub_wait and (not robots.is_empty() or vr_rig != null):
				if not mode_picked:
					_start_pick("mode")
				elif force_island >= 0:
					var fi := force_island
					force_island = -1
					_go_island(fi)
				else:
					var open := Story.pick_set(int(save.data.cleared), String(save.data.daily_done) == Seeded.today())
					if open.size() <= 1:
						_go_island(1)
					else:
						_start_pick("island")
		"pick":
			picks.tick(delta)
		"play":
			island_t += delta
			var tells: Array = level.host_grumbles(delta, robots.values())
			for tl in tells:
				_grumble_tell(tl[0], tl[1], float(tl[2]))
			if boss != null and boss.alive():
				boss.host_step(delta, robots.values())
			hint_t -= delta
			if hint_t <= 0.0:
				hint_t = 0.5
				_feature_hints()
		"cheer":
			phase_t += delta
			if phase_t > CHEER_TIME:
				_go_hub()
				_send_hub(true)


## Every machine: pads drive this machine's robots; owned robots move here and check what they touch.
func _step_owned(delta: float) -> void:
	var ph := phase()
	var free := ph == "play" or ph == "hub" or ph == "pick"
	for slot in party.local_slots():
		if not robots.has(slot):
			continue
		var r: Robot = robots[slot]
		var mv := party.stick(slot, "move") if free else Vector2.ZERO
		var dir := Vector3.ZERO
		if mv.length() > 0.15 and split != null:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var right := Vector3(-f.z, 0.0, f.x)
			dir = (right * mv.x - f * mv.y).limit_length(1.0)
		r.inp_move = dir
		r.inp_hold = free and party.pressed(slot, "accept")
		if free and party.just_pressed(slot, "accept"):
			r.inp_jump = true
			_used(slot, "jump")
		if free and party.just_pressed(slot, "x"):
			r.inp_punch = true
			_used(slot, "punch")
		if free and party.just_pressed(slot, "b"):
			r.inp_pound = true
		if ph != "play" and party.just_pressed(slot, "y"):  # in Gizmo Town: swap to the next hat
			_ask("hat", r, [])
	var hats: Array = net.state_get("hats", [])
	for rid in robots:
		var r: Robot = robots[rid]
		r.show_hat(int(hats[_hat_slot(int(rid))]) if hats.size() > _hat_slot(int(rid)) else 0)
		if not r.owned:
			continue
		r.step(delta)
		for e in r.events:
			_robot_event(r, e)
		r.events.clear()
		if ph == "play":
			_robot_rules(r)
	send_t -= delta
	if net.mode == "client" and send_t <= 0.0:
		send_t = 1.0 / 30.0
		for slot in party.local_slots():
			if robots.has(slot):
				var r: Robot = robots[slot]
				net.send_state(r.position, r.rotation.y, float(r.state_bits()), slot)


func _used(slot: int, what: String) -> void:
	var u: Dictionary = used.get(slot, {})
	u[what] = true
	used[slot] = u


## The machine running robot r: bolts, the gear, the spark, zaps, grumbles, the crab, checkpoint flags.
func _robot_rules(r: Robot) -> void:
	var mid := r.position + Vector3.UP * 0.5
	var k := level.bolt_at(mid)
	if k >= 0:
		_ask("bolt", r, [k])
	if not level.gear_got and (level.lv.gear as Vector3) != Vector3.INF and mid.distance_to(level.lv.gear) < G.TOUCH + 0.2:
		_ask("gear", r, [])
	if level.goal_on and Vector2(r.position.x - (level.lv.goal as Vector3).x, r.position.z - (level.lv.goal as Vector3).z).length() < 1.1 \
			and absf(r.position.y - (level.lv.goal as Vector3).y) < 1.6:
		_ask("goal", r, [])
	if r.safe_t <= 0.0:
		var z := level.zapped(r.position)
		if z >= 0:
			var zp: Vector3 = ((level.lv.zaps as Array)[z] as Dictionary).pos
			r.bump(r.position - zp + Vector3(0, 0, 0.01), 0.8)
			_local_sound("zap", r.position, -4.0, 1.2)
			_stat("zaps")
	for i in level.grumbles.size():
		if not level.grumble_alive(i):
			continue
		var gp := level.grumble_pos(i)
		var rel := r.position - gp
		if Vector2(rel.x, rel.z).length() < 0.8 and absf(rel.y) < 0.95:
			if rel.y > 0.4 and r.velocity.y < 0.0:  # hopped on it
				r.hop(7.0)
				_ask("pop", r, [i])
			elif r.safe_t <= 0.0:
				r.bump(rel, 1.0 if level.grumble_charging(i) else 0.7)
	if boss != null and boss.alive():
		var rel2 := r.position - boss.position
		if Vector2(rel2.x, rel2.z).length() < 1.4 and absf(rel2.y) < 1.8:
			if boss.state == "dizzy" and rel2.y > 0.8 and r.velocity.y < 0.0:
				r.hop(8.0)
				_ask("crab", r, [])
			elif boss.state != "dizzy" and r.safe_t <= 0.0:
				r.bump(rel2, 1.0)
	if r.is_on_floor():
		var sp := G.spring_at(level.lv, r.position)
		if sp >= 0:
			r.spring()
			level.spring_boing(sp)
			_local_sound("boing", r.position, -4.0, 1.4)
			_stat("springs")
			if net.mode == "host":
				net.event("boing", [sp])
			elif net.mode == "client":
				net.request(r.rid if r.rid < 10 else 1, "boing", [sp])
	var bx := level.box_near(r.position, G.BOX_R)
	if bx >= 0:
		_ask("box", r, [bx])
	var cp := G.checkpoint_for(level.lv, r.position, r.checkpoint)
	if cp != r.checkpoint:
		r.checkpoint = cp
		if cp > int(net.state_get("cp", 0)):
			_ask("cp", r, [cp])
			_local_sound("ding", r.position, -6.0, 1.3)


func _robot_event(r: Robot, e: Array) -> void:
	var p := r.position
	match String(e[0]):
		"jump":
			_local_sound("jump", p, -10.0, randf_range(1.2, 1.4))
			_stat("jumps")
		"land":
			_local_sound("land", p, -16.0, 1.5)
		"hover":
			_local_sound("whoosh", p, -12.0, 1.8)
		"fell":
			_local_sound("boing", p, -2.0, 0.8)
			_stat("falls")
		"bump":
			_local_sound("bounce", p, -4.0, 1.3)
			_stat("bumps")
		"dash":
			_local_sound("whoosh", p, -6.0, 1.2)
			_stat("dashes")
		"pound_start":
			_local_sound("whoosh", p, -8.0, 0.7)
		"pound":
			_local_sound("land", p, 0.0, 0.6)
			_stat("pounds")
			if cams.has(r.rid):
				(cams[r.rid] as CameraRig).shake(0.2)
			if phase() != "play":
				return
			for i in level.grumbles.size():
				if level.grumble_alive(i) and Vector2(level.grumble_pos(i).x - p.x, level.grumble_pos(i).z - p.z).length() < G.POUND_R \
						and absf(level.grumble_pos(i).y - p.y) < 0.8:
					_ask("pop", r, [i])
			var bx := level.box_near(p, G.POUND_R)
			if bx >= 0:
				_ask("box", r, [bx])
			if level.near_wall(p + Vector3.UP * 0.5, 1.2):
				_ask("wall", r, [])
			if boss != null and boss.state == "dizzy" and Vector2(boss.position.x - p.x, boss.position.z - p.z).length() < 2.2:
				_ask("crab", r, [])
		"punch":
			_local_sound("swish", p, -8.0, 1.4)
			_stat("punches")
			if phase() != "play":
				return
			var at: Vector3 = e[1]
			for i in level.grumbles.size():
				if level.grumble_alive(i) and at.distance_to(level.grumble_pos(i) + Vector3(0, 0.4, 0)) < 1.15:
					_ask("pop", r, [i])
			if level.near_wall(at, 0.7) or level.near_wall(r.position + Vector3.UP * 0.5, 1.0):
				_ask("wall", r, [])
			if boss != null and boss.state == "dizzy" and at.distance_to(boss.position + Vector3(0, 0.7, 0)) < 1.9:
				_ask("crab", r, [])


## Robot r (owned here) wants something from the host (asked once per thing on the TV machine).
func _ask(what: String, r: Robot, args: Array) -> void:
	if net.mode == "client":
		var key := "%s:%s" % [what, str(args)]
		if what == "bolt":
			if asked.has(key):
				return
			asked[key] = true
			sfx.play_at("coin", r.position, -4.0, 1.3)
		elif what == "crab" or what == "pop" or what == "cp" or what == "hat":
			if asked.has(key) and Time.get_ticks_msec() - int(asked[key]) < 400:
				return
			asked[key] = Time.get_ticks_msec()
		elif what == "goal":
			if asked.has(key) and Time.get_ticks_msec() - int(asked[key]) < 500:
				return
			asked[key] = Time.get_ticks_msec()
		elif asked.has(key):
			return
		else:
			asked[key] = true
		net.request(r.rid if r.rid < 10 else 1, what, args)
	else:
		on_request(r.rid, what, args)


func _local_sound(n: String, p: Vector3, db: float, pitch: float) -> void:
	if net.mode == "client":
		sfx.play_at(n, p, db, pitch)
		net.request(party.local_slots()[0] if not party.local_slots().is_empty() else 1, "snd", [n, p, db, pitch])
	else:
		sound_at(n, p, db, pitch)


func _stat(what: String) -> void:
	if net.mode == "client":
		return
	if run.has(what) and run[what] is int:
		run[what] = int(run[what]) + 1


# --- Host rules -------------------------------------------------------------------------------------------------

func on_request(slot: int, action: String, args: Array) -> void:
	var playing := phase() == "play"
	match action:
		"snd":
			if args.size() >= 4:
				sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
				net.event_except(net.sender_peer(), "sfx", [String(args[0]), args[1], float(args[2]), float(args[3])])
		"bolt":
			if playing and args.size() >= 1:
				take_bolt(int(args[0]), slot)
		"gear":
			if playing:
				_take_gear(slot)
		"goal":
			if playing and level.goal_on:
				_island_cleared(slot)
		"cp":
			if playing and args.size() >= 1 and int(args[0]) > int(net.state_get("cp", 0)):
				net.state_set("cp", int(args[0]))
		"pop":
			if playing and args.size() >= 1:
				pop_grumble(int(args[0]), str(slot))
		"wall":
			if playing:
				break_wall(str(slot))
		"crab":
			if playing:
				boss_hit(str(slot))
		"box":
			if playing and args.size() >= 1:
				open_box(int(args[0]), slot)
		"boing":
			if args.size() >= 1:
				level.spring_boing(int(args[0]))
				net.event_except(net.sender_peer(), "boing", [int(args[0])])
		"hat":
			if not playing:
				next_hat(slot)
		"stat":
			if args.size() >= 1:
				_stat(String(args[0]))


## Host: bolt k taken (by a robot, or the giant's hand).
func take_bolt(k: int, _by: int) -> void:
	if level.bolt_taken(k) or k < 0 or k >= (level.lv.bolts as Array).size():
		return
	var bits: PackedInt32Array = level.bolt_bits.duplicate()
	var w := k >> 5
	while bits.size() <= w:
		bits.append(0)
	bits[w] = bits[w] | (1 << (k & 31))
	level.set_bolts(bits)
	net.state_set("bolts", bits)
	run["bolts"] = int(run.get("bolts", 0)) + 1
	var p: Vector3 = (level.lv.bolts as Array)[k]
	sound_at("coin", p, -4.0, 1.2 + randf() * 0.15)
	_refresh_hud()


func _take_gear(by: int) -> void:
	if level.gear_got:
		return
	level.set_gear(true)
	net.state_set("gear", true)
	run["gear"] = true
	var g: Vector3 = level.lv.gear
	sound_at("sparkle", g, 0.0)
	sound_at("fanfare", g, -8.0, 1.2)
	confetti(g, Level.GEAR_COLOR, 40)
	if net.mode == "host":
		net.event("confetti", [g, Level.GEAR_COLOR, 40])
	var isle := int((level.lv.desc as Dictionary).i)
	if isle > 0 and not int(save.data.gear_isles) & (1 << (isle - 1)):
		save.data.gear_isles = int(save.data.gear_isles) | (1 << (isle - 1))
	save.data.gears = int(save.data.gears) + 1
	save.mark_dirty()
	_story("gear")
	print("Gold gear found by %d" % by)


## Host: bot box i opens (a robot bumped / punched / pounded it, or the giant's finger): its little bot is rescued and
## moves to Gizmo Town; every few rescues the little bots sew a new hat. A boss's box opens once the boss is beaten.
func open_box(i: int, _by: int) -> void:
	var bl: Array = level.lv.get("boxes", [])
	if i < 0 or i >= bl.size() or level.box_open(i):
		return
	if boss != null and boss.alive() and String((level.lv.plats as Array)[int((bl[i] as Dictionary).p)].k) == "arena":
		return
	var bits := level.box_bits | (1 << i)
	level.set_boxes(bits)
	net.state_set("boxes", bits)
	run["tiny"] = int(run.get("tiny", 0)) + 1
	var before := Hats.unlocked(int(save.data.tiny))
	save.data.tiny = int(save.data.tiny) + 1
	save.mark_dirty()
	var p: Vector3 = (bl[i] as Dictionary).pos + Vector3(0, 0.6, 0)
	sound_at("pop", p, -2.0, 1.3)
	sound_at("sparkle", p, -4.0, 1.2)
	confetti(p, Level.BOX_COLOR, 24)
	if net.mode == "host":
		net.event("confetti", [p, Level.BOX_COLOR, 24])
	if Hats.unlocked(int(save.data.tiny)) > before:
		var beat := Story.line("hat")
		beat.pic = Hats.PICS[Hats.unlocked(int(save.data.tiny)) - 1]
		_story_beat(beat)
		_send_hats()
	elif not told.has("tiny"):
		_story("tiny")
	told["tiny"] = true
	_refresh_hud()


## Which hats entry robot rid uses (people by slot 0..6, CPU buddies after them).
func _hat_slot(rid: int) -> int:
	return rid if rid < 10 else 7 + (rid - 10) % 3


## Host: every robot's hat (state "hats", 10 entries): a player's own pick (saved), else Hats.default_for its slot.
func _send_hats() -> void:
	var picked: Dictionary = save.data.hats
	var n := Hats.unlocked(int(save.data.tiny))
	var out: Array = []
	for k in 10:
		var h := Hats.default_for(k, int(save.data.tiny))
		if picked.has(str(k)):
			h = int(picked[str(k)])
		out.append(clampi(h, 0, n - 1))
	net.state_set("hats", out)


## Host: the player in slot swaps to their next hat (Y in Gizmo Town).
func next_hat(slot: int) -> void:
	var n := Hats.unlocked(int(save.data.tiny))
	if n <= 1 or slot < 0 or slot > 6:
		return
	var hats: Array = net.state_get("hats", [])
	var cur := int(hats[slot]) if hats.size() > slot else 0
	var picked: Dictionary = save.data.hats
	picked[str(slot)] = (cur + 1) % n
	save.data.hats = picked
	save.mark_dirty()
	_send_hats()
	if robots.has(slot):
		sound_at("power_up", (robots[slot] as Node3D).position + Vector3.UP, -6.0, 1.4)


func pop_grumble(i: int, who: String) -> void:
	if not level.grumble_alive(i):
		return
	level.pop_grumble(i)
	run["pops"] = int(run.get("pops", 0)) + 1
	if who == "giant":
		run["flicks"] = int(run.get("flicks", 0)) + 1
	var p := level.grumble_pos(i) + Vector3(0, 0.5, 0)
	sound_at("pop", p, 0.0, 0.9)
	sound_at("boing", p, -6.0, 1.5)
	confetti(p, Level.GRUMBLE_COLOR, 24)
	if net.mode == "host":
		net.event("confetti", [p, Level.GRUMBLE_COLOR, 24])


func break_wall(_who: String) -> void:
	if level.wall_broken:
		return
	level.break_wall()
	net.state_set("wall", true)
	var w: Vector3 = (level.lv.secret as Dictionary).wall
	sound_at("explosion", w, -10.0, 1.6)
	sound_at("sparkle", w, -2.0)
	confetti(w + Vector3(0, 1, 0), Level.CRACK_COLOR, 30)
	if net.mode == "host":
		net.event("confetti", [w + Vector3(0, 1, 0), Level.CRACK_COLOR, 30])


## Host: a robot touched the spark: the island is done for everyone.
func _island_cleared(by: int) -> void:
	var d: Dictionary = level.lv.desc
	var isle := int(d.i)
	net.state_set("phase", "cheer")
	phase_t = 0.0
	finish_log.append([isle, by, snappedf(island_t, 0.1)])
	var g: Vector3 = level.lv.goal
	sound_at("fanfare", g, -2.0)
	sound_at("applause", g, -4.0)
	for k in 3:
		var col: Color = [Level.SPARK_COLOR, Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 0.7)][k]
		confetti(g + Vector3(k - 1.0, 2.0, 0), col, 36)
		if net.mode == "host":
			net.event("confetti", [g + Vector3(k - 1.0, 2.0, 0), col, 36])
	level.set_goal(false)
	net.state_set("goal_on", false)
	var first_spark := false
	if isle > 0:
		first_spark = not int(save.data.cleared) & (1 << (isle - 1))
		save.data.cleared = int(save.data.cleared) | (1 << (isle - 1))
	else:
		save.data.daily_done = Seeded.today()
	save.data.sparks = int(save.data.sparks) + 1
	save.data.bolts = int(save.data.bolts) + int(run.get("bolts", 0))
	save.data.best_bolts = maxi(int(save.data.best_bolts), int(run.get("bolts", 0)))
	save.mark_dirty()
	_telemetry("clear")
	if first_spark and _sparks_lit() == G.ISLANDS:
		_story("all_keys")
	elif first_spark and isle == 3:
		_story("all_sparks")
		_story("chapter2")  # (the far islands open: Snowy Peaks next)
	else:
		_story("spark")
	if vr_rig != null:
		vr_rig.pulse(VrRig.RIGHT, 0.6, 0.2)
		vr_rig.pulse(VrRig.LEFT, 0.6, 0.2)
	print("Sky Bots: island %d cleared by %d after %.1f s (%d bolts, gear %s)" % [isle, by, island_t, int(run.get("bolts", 0)), str(run.get("gear", false))])


## Host: one RUN line per island (or quit mid-island): how the family really plays (balance).
func _telemetry(end: String) -> void:
	if net.mode == "client" or level.lv.is_empty():
		return
	var info := run.duplicate()
	var warps := 0
	for rid in brains:
		warps += (brains[rid] as Brain).warps
	info.merge({"end": end, "mode": net.mode, "vr": vr_rig != null, "flat_host": net.mode == "host" and vr_rig == null,
		"people": _people(), "players": _people() + (1 if vr_rig != null else 0), "robots": robots.size(), "pmode": mode,
		"season": season, "name": G.island_name(level.lv.desc), "played_s": snappedf(island_t, 0.1),
		"bolts_all": (level.lv.bolts as Array).size(), "lifts": giant.lifts_used if giant != null else 0,
		"flicks_all": giant.flicks if giant != null else 0, "crab_stomps": boss.stomps if boss != null else 0,
		"cpu_warps": warps, "sparks": int(save.data.sparks), "gears": int(save.data.gears), "grown": Story.power(save.data),
		"tiny_all": int(save.data.tiny), "hats": Hats.unlocked(int(save.data.tiny)) - 1, "boxes_all": (level.lv.get("boxes", []) as Array).size(),
		"cp": int(net.state_get("cp", 0))}, true)
	Telemetry.run(GAME_ID, info)


func _exit_tree() -> void:
	if ready_to_play and net != null and net.mode != "client" and phase() == "play":
		_telemetry("quit")


## Host: the first time a robot comes near something new this session, Granny Gizmo says what it is.
func _feature_hints() -> void:
	if robots.is_empty():
		return
	var front := -INF
	for r in robots.values():
		front = maxf(front, (r as Node3D).position.x)
	var feats := {}
	for p in level.lv.plats:
		if String(p.k) == "lift":
			feats["lift"] = minf(float(feats.get("lift", INF)), float((p.c as Vector3).x))
	for gd in level.lv.grumbles:
		feats["grumble"] = minf(float(feats.get("grumble", INF)), float(gd.x0))
	for z in level.lv.zaps:
		feats["zap"] = minf(float(feats.get("zap", INF)), float((z.pos as Vector3).x))
	for sp in level.lv.get("springs", []):
		feats["spring"] = minf(float(feats.get("spring", INF)), float((sp.pos as Vector3).x) - 2.0)
	for f in level.lv.get("fans", []):
		feats["fan"] = minf(float(feats.get("fan", INF)), float(f.x0))
	for bt in level.lv.get("belts", []):
		var bp: Dictionary = (level.lv.plats as Array)[int(bt.p)]
		feats["belt"] = minf(float(feats.get("belt", INF)), float((bp.c as Vector3).x) - float((bp.s as Vector2).x) * 0.5)
	if not (level.lv.get("boxes", []) as Array).is_empty() and int(save.data.tiny) < 3:
		feats["tiny_box"] = float(((level.lv.boxes as Array)[0].pos as Vector3).x)
	if int(save.data.tiny) >= 1 and island_t > 20.0:
		feats["moves"] = -INF  # (once a session, after the first rescue: the air moves)
	if not (level.lv.secret as Dictionary).is_empty():
		feats["secret_hint"] = float(((level.lv.secret as Dictionary).wall as Vector3).x)
	for f in feats:
		if not told.has(f) and front > float(feats[f]) - 7.0:
			told[f] = true
			_story(String(f))
			return


func _grumble_tell(p: Vector3, dir: Vector3, length: float) -> void:
	_show_line_tell(p, dir, length)
	if net.mode == "host":
		net.event("tell", [p, dir, length])


func _show_line_tell(p: Vector3, dir: Vector3, length: float) -> void:
	level.rings.shape("line", p + Vector3(0, 0.05, 0), dir, Vector2(length + 0.4, 1.1), Level.WARN_COLOR, 0.9, {"style": "flash", "y": p.y + 0.06})
	sfx.play_at("alarm", p, -14.0, 1.6)


# --- Cranky Crab (boss.gd calls these on the host) -----------------------------------------------------------------

func boss_woke() -> void:
	_story("crab" if boss == null or boss.kind == "crab" else "king")
	music.play_mood("boss")
	if net.mode == "host":
		net.event("mood", ["boss"])


func boss_tell(p: Vector3, r: float, secs: float) -> void:
	_show_ring(p, r, secs)
	if net.mode == "host":
		net.event("ring", [p, r, secs])


func _show_ring(p: Vector3, r: float, secs: float) -> void:
	level.rings.warn(p, r, Boss.RING_COLOR, secs, p.y + 0.06)
	sfx.play_at("alarm", p, -10.0, 1.1)


## King Keywind tells his charge: a warn line from p along dir (every machine).
func boss_line(p: Vector3, dir: Vector3, length: float, secs: float) -> void:
	_show_boss_line(p, dir, length, secs)
	if net.mode == "host":
		net.event("bline", [p, dir, length, secs])


func _show_boss_line(p: Vector3, dir: Vector3, length: float, secs: float) -> void:
	level.rings.shape("line", p + Vector3(0, 0.05, 0) + dir * (length * 0.5), dir, Vector2(length + 1.2, 2.6), Boss.RING_COLOR, secs,
		{"style": "flash", "y": p.y + 0.06})
	sfx.play_at("alarm", p, -10.0, 0.9)


## King Keywind bonked into the arena's rim (every machine: a clang and a shake).
func boss_bonk(p: Vector3) -> void:
	_bonk(p)
	if net.mode == "host":
		net.event("bonk", [p])


func _bonk(p: Vector3) -> void:
	sfx.play_at("hit", p, -2.0, 0.6)
	sfx.play_at("explosion", p, -12.0, 1.4)
	for slot in cams:
		(cams[slot] as CameraRig).shake(0.25)


func boss_stomp(p: Vector3, r: float) -> void:
	_shock(p, r)
	if net.mode == "host":
		net.event("shock", [p, r])


## Every machine: the stomp bumps this machine's robots inside the ring.
func _shock(p: Vector3, r: float) -> void:
	sfx.play_at("explosion", p, -8.0, 0.6)
	for rid in robots:
		var rb: Robot = robots[rid]
		if rb.owned and Vector2(rb.position.x - p.x, rb.position.z - p.z).length() < r and absf(rb.position.y - p.y) < 1.2:
			rb.bump(rb.position - p, 1.1)
	for slot in cams:
		(cams[slot] as CameraRig).shake(0.35)


## Host: a hit on the crab (a robot id, or "giant"). True if it counted.
func boss_hit(who: String) -> bool:
	if boss == null or not boss.hit(who):
		return false
	run["crab_hits"] = int(run.get("crab_hits", 0)) + 1
	var p := boss.position + Vector3(0, 1.2, 0)
	sound_at("hit", p, 0.0, 1.0)
	confetti(p, Color(1.0, 0.9, 0.4), 20)
	if net.mode == "host":
		net.event("confetti", [p, Color(1.0, 0.9, 0.4), 20])
	if not boss.alive():
		if boss.kind == "king":
			save.data.kings = int(save.data.kings) + 1
		else:
			save.data.crabs = int(save.data.crabs) + 1
		save.mark_dirty()
		level.set_goal(true)
		net.state_set("goal_on", true)
		_story("crab_down" if boss.kind == "crab" else "king_down")
		sound_at("fanfare", p, -4.0, 0.9)
		music.play_mood("overworld")
		if net.mode == "host":
			net.event("mood", ["overworld"])
	return true


# --- The giant's helpers ------------------------------------------------------------------------------------------

func on_lift_grabbed() -> void:
	run["lifts"] = int(run.get("lifts", 0)) + 1


## A little hop for robot rid (the giant's finger).
func boop(rid: int) -> void:
	var r: Robot = robots.get(rid)
	if r == null:
		return
	if r.owned:
		r.hop(5.0)
	else:
		net.event("boop", [rid])
	sound_at("pop", r.position, -6.0, 1.6)


# --- Every machine: animation, VR extras, HUD ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	for r in robots.values():
		(r as Robot).animate(delta)
	level.animate(delta)
	if boss != null:
		boss.animate(delta)
	if hub.visible:
		hub.animate(delta)
	_headline(delta)
	if ghost != null:
		_ghost(delta)
	for slot in prompts:
		var pr: Control = prompts[slot]
		if is_instance_valid(pr):
			var u: Dictionary = used.get(slot, {})
			pr.visible = not (u.has("jump") and u.has("punch")) and phase() == "play"
	var hats_open := Hats.unlocked(int((net.state_get("hubp", [0, 0, false, 0]) as Array)[3]) if (net.state_get("hubp", []) as Array).size() >= 4 else 0) > 1
	for slot in hat_prompts:
		var hpr: Control = hat_prompts[slot]
		if is_instance_valid(hpr):
			hpr.visible = hats_open and phase() == "hub"
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if group_cam != null:
		var targets: Array = robots.values()
		if targets.is_empty() and hub.visible and is_instance_valid(hub.gizmo):
			targets = [hub.gizmo]
		var key := str(targets.map(func(n: Node) -> int: return n.get_instance_id()))
		if key != String(group_cam.get_meta("key", "")):
			group_cam.set_meta("key", key)
			group_cam.set_targets(targets)


## VR practice: the see-through glove reaches the nearest lift's handle, grips and lifts it, until the giant has
## lifted one (and again after a long while without).
func _ghost(delta: float) -> void:
	var lifts: Array = level.lifts() if not level.lv.is_empty() else []
	var on := phase() == "play" and giant.held_lift < 0 and giant.lifts_used == 0 and not lifts.is_empty() and island_t > 2.0
	if not ghost.gate(on, delta):
		return
	var hx := vr_rig.head_position().x
	var best := int(lifts[0])
	for i in lifts:
		if absf(level.handle_point(int(i)).x - hx) < absf(level.handle_point(best).x - hx):
			best = int(i)
	var hp := level.handle_point(best)
	var cycle := 3.2
	var t := ghost.play("lift", cycle, delta)
	var k: Dictionary = GhostHand.track([[0.0, hp + Vector3(0, 2.0, 2.0), 0.0], [0.8, hp, 0.0], [1.1, hp, 1.0],
		[2.3, hp + Vector3(0, 2.5, 0), 1.0], [2.7, hp + Vector3(0, 2.5, 0), 0.0]], t)
	ghost.set_alpha(ghost.fade(cycle, 0.3, 0.5))
	ghost.pose(Transform3D(GhostHand.yaw_to(Vector3(0, 0, -1)), k.p), float(k.grip))


## VR: one short headline, far away over the island, facing the giant (turned on Y only).
func show_headline(text: String) -> void:
	if vr_rig == null:
		return
	if headline == null:
		headline = Label3D.new()
		headline.font_size = 96
		headline.outline_size = 26
		headline.modulate = Color(1.0, 0.92, 0.35)
		headline.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		headline.double_sided = false
		headline.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(headline)
	headline.text = text
	headline.visible = true
	headline_t = 3.0
	var cam := vr_rig.camera
	var f := vr_rig.head_forward()
	headline.pixel_size = 0.0035 * Giant.S
	headline.global_position = cam.global_position + f * 2.6 * Giant.S + Vector3.UP * 0.25 * Giant.S
	var d := headline.global_position - cam.global_position
	headline.global_basis = Basis(Vector3.UP, atan2(-d.x, -d.z))


func _headline(delta: float) -> void:
	if headline == null or not headline.visible or headline_t < 0.0:
		return
	headline_t -= delta
	if headline_t <= 0.0:
		headline.visible = false


func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var row := UiKit.hbox(8)
	card.add_child(row)
	row.add_child(StoryCard.picture("boltnut", 40.0))
	var l := UiKit.label("0", "number")
	row.add_child(l)
	bolt_labels[slot] = l
	var gp := StoryCard.picture("goldgear", 40.0)
	row.add_child(gp)
	gear_pics[slot] = gp
	row.add_child(StoryCard.picture("tinybot", 40.0))
	var tl := UiKit.label("0", "number")
	row.add_child(tl)
	tiny_labels[slot] = tl
	if slot >= 0:
		var pr := UiKit.panel("pill")
		pr.add_child(UiKit.prompts([["A", "Jump"], ["X", "Punch"]]))
		ui.add_child(pr)
		_bottom(pr)
		prompts[slot] = pr
		var hp := UiKit.panel("pill")
		hp.add_child(UiKit.prompts([["Y", "Hat"]]))
		ui.add_child(hp)
		_bottom(hp)
		hp.visible = false
		hat_prompts[slot] = hp
	else:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		_bottom(join_prompt)
	_refresh_hud()


func _bottom(c: Control) -> void:
	UiKit.pin(c, Control.PRESET_CENTER_BOTTOM)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_top = -60.0
	c.offset_bottom = -60.0


## Top-left on every view: this island's bolts and its gold gear (bright once found). Hidden in Gizmo Town.
func _refresh_hud() -> void:
	var on_island := not level.lv.is_empty()
	var got := ((level.lv.bolts as Array).size() - level.bolts_left()) if on_island else 0
	for slot in bolt_labels:
		var l: Label = bolt_labels[slot]
		if is_instance_valid(l):
			l.text = str(got)
			(l.get_parent().get_parent() as Control).visible = on_island
	var opened := 0
	if on_island:
		for i in (level.lv.get("boxes", []) as Array).size():
			opened += 1 if level.box_open(i) else 0
	for slot in tiny_labels:
		var tl: Label = tiny_labels[slot]
		if is_instance_valid(tl):
			tl.text = "%d/%d" % [opened, (level.lv.get("boxes", []) as Array).size()] if on_island else "0"
	for slot in gear_pics:
		var gp: Control = gear_pics[slot]
		if is_instance_valid(gp):
			gp.modulate = Color(1, 1, 1, 1) if level.gear_got else Color(0.35, 0.35, 0.4, 0.6)


## A story beat (story.gd key): Granny Gizmo (or Cranky Crab) and a few words, on every machine.
func _story(key: String) -> void:
	_story_beat(Story.line(key))


func _story_beat(beat: Dictionary) -> void:
	if net.mode == "host":
		net.event("story", [beat.get("who", ""), beat.get("line", ""), beat.get("pic", ""), (beat.get("color", Story.COLOR) as Color).to_html()])
	show_story(beat)


func show_story(beat: Dictionary) -> void:
	if not huds.is_empty():
		StoryCard.show(_all_huds(), beat)
	if vr_rig != null:
		var vb := beat.duplicate()
		vb["vr_height"] = VR_CARD_UP
		vb["world_scale"] = Giant.S
		StoryCard.show_vr(self, vr_rig.camera, vb)


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


## Every machine, when the pick orbs pop up (picks.gd show_row).
func pick_banner() -> void:
	if split != null:
		HudKit.banner(_all_huds(), "PICK ONE!", "", {"duration": 2.4, "color": Color(1.0, 0.85, 0.3)})
	show_headline("PICK ONE!")


func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	if net.mode == "host":
		net.event("sfx", [n, p, db, pitch])


## Every machine: a burst of confetti.
func confetti(p: Vector3, col: Color, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = amount
	cp.lifetime = 1.3
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 50.0
	cp.initial_velocity_min = 3.0
	cp.initial_velocity_max = 6.0
	cp.gravity = Vector3(0.0, -9.0, 0.0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.14, 0.03)
	bm.material = MeshKit.vertex_material(true)
	cp.mesh = bm
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.7), Color(0.5, 0.9, 1.0)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	cp.color_initial_ramp = g
	add_child(cp)
	cp.position = p
	cp.emitting = true
	get_tree().create_timer(1.7).timeout.connect(cp.queue_free)


# --- Store, pause -------------------------------------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"ldesc":
			if net.mode == "client" and value is Dictionary:
				var d: Dictionary = value
				var k := var_to_str(d) if not d.is_empty() else ""
				if k != built_key:
					_build_island(d)
		"bolts":
			if value is PackedInt32Array:
				level.set_bolts(value)
				_refresh_hud()
		"gear":
			level.set_gear(bool(value))
			_refresh_hud()
		"wall":
			if bool(value):
				level.break_wall()
		"goal_on":
			level.set_goal(bool(value))
		"cp":
			level.light_flags(int(value))
		"boxes":
			level.set_boxes(int(value))
			_refresh_hud()
		"deep":
			var dv: Array = value if value is Array else []
			if dv.size() >= 2:
				mode = String(dv[0])
				if String(dv[1]) != season:
					season = String(dv[1])
					hub.build(season)
					var hp: Array = net.state_get("hubp", [0, 0, false])
					hub.apply(int(hp[0]), false)
					hub.set_lamp(int(hp[1]))
		"hubp":
			var hv: Array = value if value is Array else []
			if hv.size() >= 3:
				hub.apply(int(hv[0]), bool(hv[2]))
				hub.set_lamp(int(hv[1]))
				if hv.size() >= 4:
					hub.set_tiny(int(hv[3]), bool(hv[2]))
				if bool(hv[2]):
					sfx.play_at("sparkle", Hub.LAMP_AT + Vector3(0, 4, 0), -2.0)
		"phase":
			if String(value) == "cheer":
				music.play_mood("victory")
				show_headline("HOORAY!")
			_refresh_hud()


func on_pause_changed(paused: bool, _by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			show_headline("PAUSED")
			headline_t = -1.0
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


# --- Networking -----------------------------------------------------------------------------------------------------

func on_remote_state(slot: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if robots.has(slot):
		(robots[slot] as Robot).set_remote(pos, yaw, int(pitch))


func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var st := PackedInt32Array()
	for rid in robots:
		var r: Robot = robots[rid]
		ids.append(int(rid))
		pos.append(r.position)
		yaw.append(r.rotation.y)
		st.append(r.state_bits())
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	return [pose, ids, pos, yaw, st, level.pack() if not level.lv.is_empty() else [], boss.pack() if boss != null else PackedFloat32Array()]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var dt := get_process_delta_time()
	giant.apply_pose(s[0], dt)
	if split != null and (s[0] as PackedFloat32Array).is_empty():
		split.clear_bubble()  # a flat host: no VR player to show in the bubble
	var ids: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var yaw: PackedFloat32Array = s[3]
	var st: PackedInt32Array = s[4]
	var seen := {}
	for i in ids.size():
		var rid := ids[i]
		seen[rid] = true
		if party.is_local(rid):
			continue
		if not robots.has(rid):
			var r := _make_robot(rid, false)
			r.position = pos[i]
		(robots[rid] as Robot).set_remote(pos[i], yaw[i], st[i])
	for rid in robots.keys():
		if not seen.has(rid) and not party.is_local(int(rid)):
			_remove_robot(int(rid))
	if (s[5] as Array).size() > 0:
		level.unpack(s[5])
	if boss != null:
		boss.unpack(s[6])


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"confetti":
			confetti(args[0], args[1], int(args[2]))
		"boop":
			var r: Robot = robots.get(int(args[0]))
			if r != null and r.owned:
				r.hop(5.0)
		"tell":
			_show_line_tell(args[0], args[1], float(args[2]))
		"ring":
			_show_ring(args[0], float(args[1]), float(args[2]))
		"shock":
			_shock(args[0], float(args[1]))
		"bline":
			_show_boss_line(args[0], args[1], float(args[2]), float(args[3]))
		"bonk":
			_bonk(args[0])
		"boing":
			level.spring_boing(int(args[0]))
		"mood":
			music.play_mood(String(args[0]))
		"orbs":
			if picks != null:
				picks.show_row(String(args[0]), args[1], args[2], bool(args[3]) if args.size() > 3 else false, int(args[4]) if args.size() > 4 else 1)
		"take":
			if picks != null:
				picks.take_fx(int(args[0]), int(args[1]))
		"story":
			if args.size() >= 4:
				show_story({"who": String(args[0]), "line": String(args[1]), "pic": String(args[2]),
					"color": Color.from_string(String(args[3]), Story.COLOR), "duration": 3.5})
