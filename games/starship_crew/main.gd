extends Node3D
## STARSHIP CREW: fly a little starship home through space.
## - The VR player (slot 0, host) is the PILOT in the cockpit: take the flight stick (touch it, or
##   squeeze the trigger on it) and move the hand to slide the ship through the glowing rings.
##   Everything on the dashboard does something when touched (cockpit.gd).
## - TV players (slots 1..6, or 0 too in local play without a headset) are the GUNNERS: each moves
##   a crosshair in their colour with the left stick and zaps space rocks and silly aliens with A.
## - Rings, rocks and aliens all give stars; eight stars fill the dashboard and finish a mission.
##   A TRIP is four short missions, the last one always HOME to the space station (the ship docks by
##   itself). The very first trip is the lessons, one new thing each: rings (with practice), a rock
##   shower, silly aliens, home. After that every trip is seeded (story.gd, missiongen.gd): three
##   missions picked from rings / rocks / aliens / STAR PARTY at a new planet each, a little harder
##   every trip; the day's first trip opens with TODAY'S MISSION. No failure: a rock that reaches the
##   ship just bounces off the shield. No numbers: stars and planet lamps show the progress.
## - STORY: CAPTAIN WHISKERS (a space cat) talks in picture cards. Every trip home builds the station
##   a new part that stays (saved); the pilot has a little glowing model of it on the dashboard.
##   Planets visited go on the captain's star map. One RUN telemetry line per mission (and on quit).
## - PRACTICE: the pilot gets a glowing ring that waits, and a ghost glove that shows how to push the
##   stick towards it (ghost_hand.gd); the gunners get one glowing rock that waits to be zapped.
## - Text: VR gets one short headline far out in front; the TV shows one short line at most.
## - Solo VR: a CPU gunner zaps now and then. Local play without a headset: a robot autopilot flies.
## - SECOND PASS (deep.gd): GENTLE / BRAVE / HARD once a session and CAPTAIN WHISKERS' SHIP MODULES before every
##   mission from the second of a seeded trip, both on big pick orbs in space ahead of the ship (picks.gd: the pilot
##   steers onto one and holds it, a gunner zaps one); warned ROCK STREAMS and SOLAR FLARES told by steady shapes
##   standing up in space (hazards.gd); seasonal STAR SECTORS (season.gd); CREW FRIENDS join and fly beside the ship
##   (crew.gd). State: "deep" [mode, gift, season, crew], "hz" (the surprise showing); events "orbs" (sticky), "take",
##   "banner", "zonehit".
## Modes as in games/engine_template: local (one shared TV view), host (VR on the Steam Frame,
## simulates everything), client (the TV machine: mirrors the host, sends its zaps to the host).

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
const Art := preload("res://games/starship_crew/art.gd")
const Space := preload("res://games/starship_crew/space.gd")
const Cockpit := preload("res://games/starship_crew/cockpit.gd")
const GhostHand := preload("res://games/starship_crew/ghost_hand.gd")
const MissionGen := preload("res://games/starship_crew/missiongen.gd")
const Story := preload("res://games/starship_crew/story.gd")
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/starship_crew/deep.gd")
const PicksScript := preload("res://games/starship_crew/picks.gd")
const HazardsScript := preload("res://games/starship_crew/hazards.gd")
const SeasonScript := preload("res://games/starship_crew/season.gd")
const CrewScript := preload("res://games/starship_crew/crew.gd")
const SeasonKit := preload("res://core/season_kit.gd")

const GAME_ID := "starship_crew"
const NEED := MissionGen.NEED  ## stars per mission
const MISSIONS := Story.MISSIONS
const STEER_SPEED := MissionGen.STEER
## The TV camera never moves (the ship stays at the origin), so the host can aim the TV crosshairs too.
const CAM_POS := MissionGen.CAM_POS
const CAM_LOOK := MissionGen.CAM_LOOK
const CAM_FOV := MissionGen.CAM_FOV
const ASPECT := MissionGen.ASPECT
const CROSS_SPEED := 1.3
const CPU_COLOR := Color(1.0, 0.95, 0.6)

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

var space: Space
var cockpit: Cockpit
var ghost: GhostHand
var avatar: VrRig.Avatar
var shield: MeshInstance3D
var shield_mat: ShaderMaterial
var beam_mats := {}  ## colour html -> material

# Host
var vel := Vector2.ZERO
var mission_t := 0.0
var phase_t := 0.0
var cpu_t := 3.0
var trip_no := 0  ## trips home before this one (0 = the lessons)
var trip_plan: Array = []  ## story.gd trip(): this trip's four missions
var plan: Dictionary = {}  ## missiongen.gd: the mission's timeline (this lap)
var plan_t := 0.0
var plan_i := 0
var lap := 0
var daily_trip := false
var story_rng := RandomNumberGenerator.new()
var tel := {}  ## this mission's numbers for the RUN line
var prac_ring := -1
var prac_rock := -1
var station := -1
var log_rings := 0  ## bots: rings flown through
var log_pops := {}  ## bots: slot -> things zapped
var log_toys := {}  ## bots: toys pressed

# TV
var cross := {}  ## slot -> Vector2 (-1..1 screen, y up)
var cross_ui := {}  ## slot -> Crosshair
var far_cross := {}  ## other machines' gunners: slot -> Vector2 (host: as they report it; TV machine: from snapshots)
var far_ui := {}  ## slot -> Crosshair (a dimmer copy of another machine's crosshair)
var cross_send_t := 0.0
var zapped := {}  ## slot -> true once they zapped (the "A Zap!" pill goes away)
var cross_layer: Control
var hud: Control
var star_row: HBoxContainer
var flag_row: HBoxContainer
var pill: Control
var pill_text := ""
var results_ui: Control
var tv_banner: Control
var shake := 0.0
var lasers_seen := 0  ## bots (TV machine): laser beams drawn

# VR
var headline: Label3D
var headline_t := 0.0
var vr_story: Node3D
var stories_shown := 0  ## bots: story cards shown here
var runs_logged := 0  ## bots: RUN lines written
var demo_tilt := Vector2.ZERO

# Second pass (deep.gd)
var picks: Node  # picks.gd (host decides; every machine shows the orbs)
var hazards: Node3D  # hazards.gd (every machine draws the "hz" state)
var season_node: Node3D  # season.gd
var crew_node: Node3D  # crew.gd
var module: Node3D  # this mission's ship module, drawn on the ship
var mode := "brave"  # every machine (from the "deep" state)
var gift := ""  # every machine: this mission's module ("" none)
var season := ""
var mode_picked := false  # host: the mode was picked this session
var gift_mission := -1  # host: the mission the module was picked for
var hz_list: Array = []  # host: this lap's surprises (deep.gd hazards())
var hz_i := 0
var hz_now := {}
var hz_hit := false
var hz_count := 0  # this mission (RUN line)
var hz_hits := 0
var dizzy_t := 0.0  # host: seconds the ship steers slowly after a hit
var zone_hits := 0  # bots: surprises that hit the ship (whole session)
var surprises_seen := 0  # bots: surprises told (whole session)


## A gunner's crosshair: a ring in the player's colour.
class Crosshair extends Control:
	var col := Color.WHITE
	var kick := 0.0

	func _process(delta: float) -> void:
		if kick > 0.0:
			kick = maxf(0.0, kick - delta * 4.0)
			queue_redraw()

	func _draw() -> void:
		var r := 30.0 * (1.0 + kick * 0.5)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 11.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 6.0)
		for k in 4:
			var d := Vector2.RIGHT.rotated(k * PI * 0.5)
			draw_line(d * (r - 12.0), d * (r + 12.0), col, 5.0)
		draw_circle(Vector2.ZERO, 5.0, col)


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
	net.sticky_event("orbs")  # a machine joining mid-pick sees the orbs (picks.gd)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = Story.save_defaults()
	add_child(save)
	if int(save.data.world) < 0:
		save.data.world = Seeded.fresh_seed()  # this family's own trips
		save.mark_dirty()
	story_rng.seed = Seeded.fresh_seed()
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("space")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("zapper", "SUPER ZAPPER", "%s space rocks zapped", "zaps")
	awards.define("alien_pal", "ALIEN FRIEND", "%s silly aliens spun", "ufos")
	awards.define("ace", "ACE PILOT", "%s rings flown", "rings")
	awards.define("honker", "HONK HONK", "%s honks", "honks")
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	var flat: bool = mode == "host" and not net.has_vr  # flat host (TV / Deck hosting): slot 0 is a pad gunner (the robot flies) here
	if VrRig.wanted(mode) and not flat:
		vr_rig = VrRig.new()
		vr_rig.locomotion = false
		vr_rig.turn_mode = "none"
		vr_rig.eye_height = 1.2  # seated in the cockpit
		vr_rig.fit_limits = Vector2(-0.6, 0.6)
		add_child(vr_rig)
		vr_rig.camera.far = 1200.0
		vr_rig.place(Vector3(0.0, 0.0, 0.12), 0.0)
	sky = SkyKit.apply(self, "space", vr_rig != null)
	space = Space.new()
	space.name = "Space"
	add_child(space)
	cockpit = Cockpit.new()
	cockpit.name = "Cockpit"
	add_child(cockpit)
	cockpit.setup(self, vr_rig)
	_build_shield()
	picks = PicksScript.new()
	picks.main = self
	add_child(picks)
	hazards = HazardsScript.new()
	hazards.main = self
	add_child(hazards)
	season_node = SeasonScript.new()
	season_node.name = "Season"
	season_node.main = self
	add_child(season_node)
	crew_node = CrewScript.new()
	crew_node.name = "Crew"
	crew_node.main = self
	add_child(crew_node)
	if vr_rig != null:
		ghost = GhostHand.new()
		add_child(ghost)
		awards.set_player(0, "PILOT")
	if mode != "host" or vr_rig == null:
		split = SplitView.new()
		split.camera_far = 1200.0
		add_child(split)
		split.bind_party(party)
		split.set_shared(true)
		var sc := split.shared_camera()
		sc.fov = CAM_FOV
		sc.global_transform = _cam_xf()
		_make_hud(split.shared_hud())
		if mode == "client":
			avatar = VrRig.Avatar.new()
			add_child(avatar)
			split.set_bubble(VrRig.build_mirror(self, avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
		else:
			cockpit.add_robot()
	party.allow_slot0 = mode != "client" and vr_rig == null
	if mode != "client":
		_start_show()
	else:
		space.set_planet(Story.planet_look(int(net.state_get("planet", -1))))
		space.station_parts = int(net.state_get("parts", 0))
		cockpit.set_station(space.station_parts)
		_on_state_changed("deep", net.state_get("deep", []))
		_on_state_changed("hz", net.state_get("hz", []))
		var orb_args: Variant = net.sticky_last("orbs")
		if orb_args is Array and (orb_args as Array).size() >= 3:
			apply_event("orbs", orb_args)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Starship Crew: %s mode%s" % [mode, " with a VR pilot" if vr_rig != null else ""])


static func _cam_xf() -> Transform3D:
	return MissionGen.cam_xf()


func _build_shield() -> void:
	shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 10
	shield.mesh = sm
	shield.scale = Vector3(4.6, 2.6, 6.0)
	shield.position = Vector3(0.0, 0.3, 0.3)
	var sh := Shader.new()
	sh.code = Space.GLOW_SHADER
	shield_mat = ShaderMaterial.new()
	shield_mat.shader = sh
	shield_mat.set_shader_parameter("col", Color(0.4, 0.8, 1.0, 0.0))
	shield.material_override = shield_mat
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.visible = false
	add_child(shield)


# --- The show (host / local) -----------------------------------------------------------------------

func _start_show() -> void:
	awards.reset()
	if vr_rig != null:
		awards.set_player(0, "PILOT")
	for s in _crew_slots():
		awards.set_player(s, party.name_of(s))
	space.clear()
	space.speed = 10.0
	station = -1
	cockpit.show_again(false)
	net.state_set("missions", 0)
	var first := 0
	if OS.has_environment("SC_MISSION") and not has_meta("started"):
		first = clampi(int(OS.get_environment("SC_MISSION")), 0, MISSIONS - 1)
	if not has_meta("started"):
		net.state_set("practice", 0 if first == 0 else 3)
		net.state_set("missions", first)
	trip_no = int(save.data.trips)
	if OS.has_environment("SC_TRIPS"):
		trip_no = int(OS.get_environment("SC_TRIPS")) + (int(get_meta("again", 0)) if has_meta("started") else 0)
	daily_trip = trip_no > 0 and not (save.data.daily as Dictionary).has(Seeded.today()) and not OS.has_environment("BOT_NO_DAILY")
	season = SeasonKit.override("starship_crew", Seeded.season(), Deep.SEASONS)
	if OS.has_environment("SC_MODE"):
		mode = Deep.mode_of(OS.get_environment("SC_MODE"))
		mode_picked = true
	elif String(save.data.mode) != "":
		mode = Deep.mode_of(String(save.data.mode))
	gift = ""
	gift_mission = -1
	hz_now = {}
	net.state_set("hz", [])
	_send_deep()
	trip_plan = Story.trip(trip_no, int(save.data.world), daily_trip)
	var parts := Story.parts_for(trip_no)
	net.state_set("parts", parts)
	space.station_parts = parts
	cockpit.set_station(parts)
	set_meta("started", true)
	print("Captain Whiskers: trip %d (tier %d), %d planets on the map, world %d%s" % [trip_no, Story.tier_for(trip_no),
		(save.data.planets as Array).size(), int(save.data.world), ", TODAY'S MISSION first" if daily_trip else ""])
	if trip_no == 0:
		_story(_captain(String(Story.LINES.welcome)))
	elif daily_trip:
		_story(_captain(String(Story.LINES.daily), "star"))
	else:
		_story(_captain(Story.pick(story_rng, "new_trip")))
	if not has_meta("sector_told"):  # the season's star sector, once a session
		set_meta("sector_told", true)
		var sd := Deep.season_data(season)
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_inside_tree():
				_story(_captain(String(sd.line), String(sd.pic))))
	_next_mission(first)


func _go_mission(i: int) -> void:
	mission_t = 0.0
	var m: Dictionary = trip_plan[i]
	lap = 0
	if trip_no < 1 or i != gift_mission:
		gift = "" if not OS.has_environment("SC_GIFT") or trip_no < 1 else String(OS.get_environment("SC_GIFT"))
	_send_deep()
	plan = MissionGen.generate(int(m.s), String(m.k), Deep.tier(int(m.tier), mode, bool(m.get("daily", false)) or trip_no < 1), lap)
	_plan_surprises()
	hz_count = 0
	hz_hits = 0
	plan_t = 0.0
	plan_i = 0
	space.speed = float(plan.speed)
	tel = {"rings": 0, "missed": 0, "zaps": 0, "ufos": 0, "bumps": 0}
	net.state_set("stars", 0)
	net.state_set("planet", int(m.planet))
	net.state_set("mname", Story.mission_name(m))
	net.state_set("mission", i)
	net.state_set("phase", "play")
	space.set_planet(Story.planet_look(int(m.planet)))
	if i > 0:
		_story(_captain(Story.pick(story_rng, String(m.k)), "captain"))
	if i == 0 and int(net.state_get("practice", 0)) != 3:
		var pr := int(net.state_get("practice", 0))
		if vr_rig == null:
			pr |= 1  # no pilot to teach: the robot flies
		if pr & 1 == 0:
			prac_ring = space.add(Space.RING, Vector3(space.off.x + 4.0, space.off.y, -16.0), true)
		if pr & 2 == 0:
			prac_rock = space.add(Space.ROCK, Vector3(space.off.x - 3.0, space.off.y + 1.6, -24.0), true)
		net.state_set("practice", pr)
	music.play_mood("space")


func _mission_done() -> void:
	var m := int(net.state_get("mission", 0))
	_telemetry("done")
	save.data.missions = int(save.data.missions) + 1
	var pl := int((trip_plan[m] as Dictionary).planet)
	if pl >= 0:  # a new planet for the captain's star map
		var pname := Story.planet_name(pl)
		var map: Array = save.data.planets
		if not map.has(pname):
			map.append(pname)
			while map.size() > Story.STAR_MAP_MAX:
				map.remove_at(0)
		var look := Story.planet_look(pl)
		_story({"who": Story.CAPTAIN, "line": String(Story.LINES.planet) % pname, "pic": "planet", "color": look[0], "duration": 3.5})
	if bool((trip_plan[m] as Dictionary).get("daily", false)):
		(save.data.daily as Dictionary)[Seeded.today()] = true
	var crew_before := Deep.crew(int(save.data.crew_xp))
	save.data.crew_xp = int(save.data.crew_xp) + 1
	if Deep.crew(int(save.data.crew_xp)) > crew_before:  # a new crew friend joins and flies beside the ship
		var friend: Dictionary = Deep.CREW[crew_before]
		get_tree().create_timer(3.8).timeout.connect(func() -> void:
			if is_inside_tree():
				_story({"who": Story.CAPTAIN, "line": "%s joins the crew!" % String(friend.name), "pic": String(friend.pic), "color": friend.color, "duration": 3.5}))  # who-ok: a story crew friend, not a player
	_clear_surprise()
	gift = ""
	_send_deep()
	save.mark_dirty()
	net.state_set("missions", m + 1)
	if m + 1 >= MISSIONS:
		net.state_set("phase", "dock")
		space.station_parts = Story.parts_for(trip_no + 1)  # the new part is already built when we get home
		net.state_set("parts", space.station_parts)
		station = space.add(Space.STATION, Vector3(space.off.x * 0.5, space.off.y * 0.5, -120.0))
	else:
		net.state_set("phase", "cheer")
	phase_t = 0.0
	sound_at("fanfare", Vector3(0, 1, -3), -4.0)
	sound_at("applause", Vector3(0, 1, -3), -6.0)
	_pulse_both(0.6, 0.2)


func _arrived() -> void:
	if not OS.has_environment("SC_TRIPS"):
		save.data["trips"] = int(save.data["trips"]) + 1
	set_meta("again", int(get_meta("again", 0)) + 1)
	save.mark_dirty()
	cockpit.set_station(space.station_parts)
	var parts_before := Story.parts_for(trip_no)
	if space.station_parts > parts_before:
		var part: Dictionary = Story.PARTS[space.station_parts - 1]
		_story(_captain(String(part.line), String(part.pic)))
	else:
		_story(_captain(Story.pick(story_rng, "docked")))
	sound_at("party_horn", Vector3(0, 1, -4), -2.0)
	sound_at("cheer", Vector3(0, 1, -4), -2.0)
	confetti(Vector3(0, 2.5, -6), Color(1.0, 0.5, 0.7), 60)
	net.event("confetti", [Vector3(0, 2.5, -6), Color(1.0, 0.5, 0.7), 60])
	var data := awards.results({"title": "HOME SWEET HOME!", "style": "victory", "score_stat": "stars",
		"score_format": "%d STARS", "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


func _crew_slots() -> Array[int]:
	var out: Array[int] = []
	for s in party.active_slots():
		if s != 0 or vr_rig == null:
			out.append(s)
	return out


# --- Host rules --------------------------------------------------------------------------------------

func _host_step(delta: float) -> void:
	var phase := String(net.state_get("phase", "play"))
	var mission := int(net.state_get("mission", 0))
	# Steering: the pilot's hands, or the robot autopilot.
	var want := Vector2.ZERO
	if vr_rig != null:
		cockpit.update_vr(delta)
		want = cockpit.steer
		_ghost(delta)
	else:
		want = _autopilot()
		cockpit.steer = cockpit.steer.lerp(want, 1.0 - exp(-6.0 * delta))
	if phase == "dock" or phase == "results":
		want = Vector2.ZERO
	dizzy_t = maxf(0.0, dizzy_t - delta)
	var steer_speed := Deep.steer_speed(gift) * (0.5 if dizzy_t > 0.0 else 1.0)  # (TURBO: faster; a hit: dizzy)
	vel = vel.move_toward(want * steer_speed, Deep.accel(gift) * delta)
	space.off += vel * delta
	if phase == "pick":  # a lined-up orb gently holds the ship (picks.gd)
		space.off += picks.hold_pull() * minf(1.0, Deep.ORB_PULL * delta)
	# Rings gently pull the ship in when it's close (kids get them more often).
	var rid := space.next_ring()
	if rid >= 0:
		var rp: Vector3 = space.objs[rid]["p"]
		var to := Vector2(rp.x, rp.y) - space.off
		if rp.z > Deep.pull_z(gift) and to.length() < Deep.pull_r(gift) and not bool(space.objs[rid]["held"]) \
				and (hz_now.is_empty() or not Deep.inside(hz_now, Vector2(rp.x, rp.y))):  # not the practice ring, never into a surprise
			space.off += to * minf(1.0, Deep.pull(gift) * delta)
	if station >= 0 and space.objs.has(station):
		var sp: Vector3 = space.objs[station]["p"]
		space.off = space.off.lerp(Vector2(sp.x, sp.y), minf(1.0, 0.7 * delta))
		space.speed = clampf(-(sp.z + 4.0) / 3.0, 2.0 if phase == "dock" else 0.0, 10.0)
		if phase == "dock" and sp.z > -6.0:
			_arrived()
	space.off = space.off.clamp(-Space.LIMIT, Space.LIMIT)
	for e in space.step(delta):
		_space_event(e)
	_practice()
	mission_t += delta
	if phase == "play":
		_spawn(mission, delta)
		_tick_surprises()
		_cpu_crew(delta)
		if int(net.state_get("stars", 0)) >= NEED:
			_mission_done()
	elif phase == "cheer":
		phase_t += delta
		if phase_t > 4.0:
			_next_mission(mission + 1)
	elif phase == "pick":
		picks.tick(delta)
	elif phase == "dock":
		_cpu_crew(delta)
	elif phase == "results":
		phase_t += delta
		if phase_t > 45.0:
			_start_show()


func _autopilot() -> Vector2:
	if not hz_now.is_empty():  # a surprise is told: slide out of it first
		var safe := Deep.escape(hz_now, space.off)
		if safe != Vector2.INF and safe != space.off:
			return ((safe - space.off) / 0.8).limit_length(1.0)
	var rid := prac_ring if space.objs.has(prac_ring) else space.next_ring()
	if rid >= 0:
		var rp: Vector3 = space.objs[rid]["p"]
		if rp.z > -80.0:
			return ((Vector2(rp.x, rp.y) - space.off) / 2.0).limit_length(1.0)
	return (-space.off / 6.0).limit_length(0.5)


func _spawn(mission: int, delta: float) -> void:
	if mission == 0 and int(net.state_get("practice", 3)) != 3 and mission_t < 40.0:
		return
	plan_t += delta
	var ev: Array = plan.events
	while plan_i < ev.size() and float(ev[plan_i][0]) <= plan_t:
		_spawn_one(ev[plan_i])
		plan_i += 1
	if plan_t >= float(plan.len):  # the next lap of the same mission
		lap += 1
		plan = MissionGen.generate(int(plan.seed), String(plan.kind), int(plan.tier), lap)
		plan_t -= float(plan.len)
		plan_i = 0
		_plan_surprises()


## One thing from the mission's timeline: rings at their place on the path; rocks and aliens near the ship.
func _spawn_one(e: Array) -> void:
	match int(e[1]):
		Space.RING:
			space.add(Space.RING, Vector3(float(e[2]), float(e[3]), Space.SPAWN_Z))
		Space.ROCK:
			var id := space.add(Space.ROCK, Vector3(space.off.x + float(e[2]), space.off.y + float(e[3]), Space.SPAWN_Z + float(e[4])))
			space.objs[id]["v"] = Vector3(float(e[5]), float(e[6]), float(e[7]))
		Space.UFO:
			var ufos := 0
			for id in space.objs:
				if int(space.objs[id]["kind"]) == Space.UFO:
					ufos += 1
			if ufos < 3 + int(plan.tier) / 2:
				var uid := space.add(Space.UFO, Vector3(space.off.x + float(e[2]), space.off.y + float(e[3]), Space.UFO_Z))
				space.objs[uid]["sway"] = float(e[8])


## The practice ring waits until the pilot lines up with it, then flies through.
func _practice() -> void:
	if prac_ring >= 0 and space.objs.has(prac_ring) and bool(space.objs[prac_ring]["held"]):
		var rp: Vector3 = space.objs[prac_ring]["p"]
		if Vector2(rp.x, rp.y).distance_to(space.off) < 1.6:
			space.release(prac_ring, 12.0)
			sound_at("whoosh", Vector3(0, 1.2, -8), -4.0, 1.2)


func _space_event(e: Array) -> void:
	var id: int = e[1]
	match String(e[0]):
		"ring":
			var p := Vector3(0.0, Space.SHIP_Y, -0.5)
			if bool(e[2]):
				log_rings += 1
				tel.rings = int(tel.get("rings", 0)) + 1
				sound_at("ding", p, -2.0, 1.3)
				sound_at("whoosh", p, -6.0, 1.4)
				confetti(p + Vector3(0, 0, -3), Color(0.5, 1.0, 0.95), 30)
				net.event("confetti", [p + Vector3(0, 0, -3), Color(0.5, 1.0, 0.95), 30])
				_pulse_both(0.5, 0.1)
				awards.add(0, "rings")
				if id == prac_ring:
					prac_ring = -1
					net.state_set("practice", int(net.state_get("practice", 0)) | 1)
					show_headline("YES!")
				_add_stars(2 + Deep.extra_star(gift), p + Vector3(0, 0, -3), 0)
			else:
				sound_at("whoosh", p, -12.0, 0.8)
				tel.missed = int(tel.get("missed", 0)) + 1
				if id == prac_ring:  # missed the practice ring somehow: another one waits
					prac_ring = space.add(Space.RING, Vector3(space.off.x - 4.0, space.off.y, -16.0), true)
		"bump":
			var w := space.world_pos(id)
			sound_at("bounce", w, -2.0, 0.9)
			sound_at("boing", w, -6.0, 0.8)
			_bump_fx()
			tel.bumps = int(tel.get("bumps", 0)) + 1
			net.event("bump", [])
			_pulse_both(0.4, 0.12)


func _cpu_crew(delta: float) -> void:
	if not _crew_slots().is_empty():
		return
	cpu_t -= delta
	if cpu_t > 0.0:
		return
	cpu_t = 2.4
	var pick := -1
	if prac_rock >= 0 and space.objs.has(prac_rock):
		if mission_t < 6.0:
			return
		pick = prac_rock
	else:
		var ids := space.zappables()
		ids.shuffle()
		for id in ids:
			if (space.objs[id]["p"] as Vector3).z > -60.0:
				pick = id
				break
	if pick >= 0:
		zap(-1, project(space.world_pos(pick)))


## Where a world point shows on the TV screen (-1..1, y up), or far off-screen behind the camera.
static func project(w: Vector3) -> Vector2:
	return MissionGen.project(w)


static func screen_ray(uv: Vector2) -> Vector3:
	return MissionGen.screen_ray(uv)


## Host: a gunner (slot, or -1 = the CPU gunner) zaps at a point on the TV screen. Generous aim.
func zap(slot: int, uv: Vector2) -> void:
	if picks != null and picks.active():  # the orbs are up: a zap only picks (never a stray rock)
		if picks.zap_at(slot, uv):
			var c0: Color = CPU_COLOR if slot < 0 else party.color_of(slot)
			var f0: Vector3 = Art.TURRETS[0 if uv.x < 0.0 else 1]
			var t0 := CAM_POS + screen_ray(uv) * 25.0
			laser(f0, t0, c0)
			net.event("laser", [f0, t0, c0])
		return
	var best := -1
	var best_s := INF
	var t := tan(deg_to_rad(CAM_FOV) * 0.5)
	for id in space.zappables():
		var w := space.world_pos(id)
		var q := _cam_xf().affine_inverse() * w
		if q.z > -2.0:
			continue
		var s := project(w)
		var d := Vector2((s.x - uv.x) * ASPECT, s.y - uv.y).length()
		var tol := Deep.zap_tol(gift) + float(space.objs[id]["r"]) / (-q.z * t)  # (MEGA LASER: much easier)
		if d < tol and d - tol < best_s:
			best_s = d - tol
			best = id
	var col: Color = CPU_COLOR if slot < 0 else party.color_of(slot)
	var from: Vector3 = Art.TURRETS[0 if uv.x < 0.0 else 1]
	var to := CAM_POS + screen_ray(uv) * 90.0
	if best >= 0:
		to = space.world_pos(best)
	laser(from, to, col)
	net.event("laser", [from, to, col])
	sound_at("laser", from, -8.0, randf_range(1.1, 1.3))
	if best >= 0:
		_pop(best, slot, col)


func _pop(id: int, slot: int, col: Color) -> void:
	var w := space.world_pos(id)
	var kind: int = space.objs[id]["kind"]
	space.remove(id)
	log_pops[slot] = int(log_pops.get(slot, 0)) + 1
	tel.zaps = int(tel.get("zaps", 0)) + 1
	if kind == Space.UFO:
		tel.ufos = int(tel.get("ufos", 0)) + 1
	pop_fx(w, col, kind)
	net.event("pop", [w, col, kind])
	if kind == Space.UFO:
		sound_at("boing", w, 0.0, 1.4)
		sound_at("party_horn", w, -8.0, 1.2)
		if slot >= 0:
			awards.add(slot, "ufos")
	else:
		sound_at("pop", w, -2.0, randf_range(0.8, 1.1))
		sound_at("sparkle", w, -6.0)
		if slot >= 0:
			awards.add(slot, "zaps")
	if id == prac_rock:
		prac_rock = -1
		net.state_set("practice", int(net.state_get("practice", 0)) | 2)
	_add_stars((2 if kind == Space.UFO else 1) + Deep.extra_star(gift), w, slot)


func _add_stars(n: int, from: Vector3, slot: int) -> void:
	if String(net.state_get("phase", "play")) != "play":
		return
	net.state_set("stars", mini(NEED, int(net.state_get("stars", 0)) + n))
	save.data.stars = int(save.data.stars) + n
	if slot >= 0:
		awards.add(slot, "stars", n)
	fly_stars(from, n)
	net.event("star", [from, n])


## Host: a toy in the cockpit was touched.
func on_toy(k: String) -> void:
	log_toys[k] = true
	var p := Vector3(0.0, 0.9, -0.6)
	match k:
		"honk":
			sound_at("honk", p, -2.0, randf_range(0.9, 1.1))
			awards.add(0, "honks")
		"disco":
			sound_at("power_up", p, -6.0)
		"bubbles":
			sound_at("bubbles", p, -2.0)
		"bobble":
			sound_at("boing", p, -6.0, 1.6)
		"again":
			on_request(0, "again", [])
			return
	toy_fx(k)
	net.event("toy", [k])


func _pulse_both(a: float, d: float) -> void:
	if vr_rig != null:
		vr_rig.pulse(VrRig.RIGHT, a, d)
		vr_rig.pulse(VrRig.LEFT, a, d)


## Host / local: a player asked for something (from any machine).
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"zap":
			if args.size() >= 2 and String(net.state_get("phase", "")) in ["play", "dock", "cheer", "pick"]:
				zap(slot, Vector2(float(args[0]), float(args[1])))
		"again":
			if String(net.state_get("phase", "")) == "results":
				_start_show()


# --- Every machine --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if net.mode != "client":
		_host_step(delta)
	if split != null:
		_gunners(delta)
	if ghost != null and ghost.visible and cockpit.held_by < 0:
		cockpit.steer = demo_tilt
	cockpit.animate(delta)
	space.animate(delta)
	if picks != null:
		picks.follow()
	cockpit.set_progress(int(net.state_get("stars", 0)), int(net.state_get("missions", 0)))
	if String(net.state_get("phase", "")) == "play":
		space.planet_near = float(net.state_get("stars", 0)) / float(NEED)
	_headline(delta)
	if shield.visible or gift == "shield":
		var c: Color = shield_mat.get_shader_parameter("col")
		var floor_a := 0.22 if gift == "shield" else 0.0  # (BUBBLE SHIELD: a steady faint bubble all mission)
		c.a = maxf(floor_a, c.a - delta * 1.5)
		shield_mat.set_shader_parameter("col", c)
		shield.visible = c.a > 0.0
	if split != null:
		shake = maxf(0.0, shake - delta * 2.0)
		var sc := split.shared_camera()
		sc.global_transform = _cam_xf()
		if shake > 0.0:
			sc.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.25
		_update_pill()


func _ghost(delta: float) -> void:
	var playing := String(net.state_get("phase", "play")) == "play"
	var practicing := prac_ring >= 0 and space.objs.has(prac_ring) and bool(space.objs[prac_ring]["held"])
	var idle := cockpit.idle_t > 30.0 and cockpit.held_t > 0.0
	var on := playing and cockpit.held_by < 0 and (practicing or idle) and mission_t > 1.0
	var dir := Vector2(1.0, 0.0)
	if practicing:
		var rp: Vector3 = space.objs[prac_ring]["p"]
		dir = (Vector2(rp.x, rp.y) - space.off).limit_length(1.0)
		if dir.length() < 0.3:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
	else:
		var rid := space.next_ring()
		if rid >= 0:
			var rp2: Vector3 = space.objs[rid]["p"]
			var d2 := Vector2(rp2.x, rp2.y) - space.off
			if d2.length() > 0.3:
				dir = d2.normalized()
	demo_tilt = ghost.show_demo(on, cockpit.handle_point(), dir, delta)


## TV: each local gunner moves a crosshair with the left stick and zaps with A.
func _gunners(delta: float) -> void:
	var playing := String(net.state_get("phase", "")) in ["play", "dock", "cheer", "pick"]
	for slot in party.local_slots():
		if not cross.has(slot):
			_add_cross(slot)
		var c: Vector2 = cross[slot]
		var mv := party.stick(slot, "move")
		if mv.length() > 0.15:
			c += Vector2(mv.x, -mv.y) * CROSS_SPEED * delta
			c = c.clamp(Vector2(-0.95, -0.9), Vector2(0.95, 0.9))
			cross[slot] = c
		var ui: Crosshair = cross_ui[slot]
		var sz := cross_layer.size
		ui.position = Vector2((c.x + 1.0) * 0.5 * sz.x, (1.0 - c.y) * 0.5 * sz.y)
		ui.visible = playing
		if playing and (party.just_pressed(slot, "accept") or party.just_pressed(slot, "rt")):
			zapped[slot] = true
			ui.kick = 1.0
			party.rumble(slot, 0.2, 0.0, 0.08)
			net.request(slot, "zap", [c.x, c.y])
	for slot in cross.keys():
		if not party.is_local(int(slot)):
			_remove_cross(int(slot))
	# Many machines: tell the host where our crosshairs are, and draw the other machines' ones (dimmer).
	cross_send_t -= delta
	if net.mode == "client" and cross_send_t <= 0.0:
		cross_send_t = 1.0 / 15.0
		for slot in cross:
			var c2: Vector2 = cross[slot]
			net.send_state(Vector3(c2.x, c2.y, 0.0), 0.0, 0.0, int(slot))
	for slot in far_cross:
		if party.is_local(int(slot)) or not party.is_active(int(slot)):
			continue
		if not far_ui.has(slot):
			var g := Crosshair.new()
			g.col = party.color_of(int(slot))
			g.modulate.a = 0.6
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cross_layer.add_child(g)
			far_ui[slot] = g
		var fc: Vector2 = far_cross[slot]
		var gu: Crosshair = far_ui[slot]
		var want := Vector2((fc.x + 1.0) * 0.5 * cross_layer.size.x, (1.0 - fc.y) * 0.5 * cross_layer.size.y)
		gu.position = gu.position.lerp(want, 1.0 - exp(-15.0 * delta))
		gu.visible = playing
	for slot in far_ui.keys():
		if not far_cross.has(slot) or party.is_local(int(slot)) or not party.is_active(int(slot)):
			(far_ui[slot] as Node).queue_free()
			far_ui.erase(slot)


## Host: a TV machine's gunner moved their crosshair (x, y in pos).
func on_remote_state(slot: int, pos: Vector3, _yaw: float, _pitch: float) -> void:
	if party.is_active(slot) and not party.is_local(slot):
		far_cross[slot] = Vector2(pos.x, pos.y)


func _add_cross(slot: int) -> void:
	var ui := Crosshair.new()
	ui.col = party.color_of(slot)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross_layer.add_child(ui)
	cross_ui[slot] = ui
	# start spot by seat, not by how many are local here: other machines' gunners don't land on ours
	cross[slot] = Vector2(-0.45 + 0.15 * slot, 0.1 - 0.12 * (slot % 2))
	if vr_rig == null and net.mode != "client":
		awards.set_player(slot, party.name_of(slot))


func _remove_cross(slot: int) -> void:
	if cross_ui.has(slot):
		(cross_ui[slot] as Node).queue_free()
	cross_ui.erase(slot)
	cross.erase(slot)


func _on_player_joined(slot: int, _device: int) -> void:
	sfx.play("ui_notify", -6.0)
	if net.mode != "client" and (slot != 0 or vr_rig == null):
		awards.set_player(slot, party.name_of(slot))


func _on_player_left(slot: int) -> void:
	_remove_cross(slot)
	far_cross.erase(slot)


# --- Effects (every machine) -------------------------------------------------------------------------

func laser(from: Vector3, to: Vector3, col: Color) -> void:
	lasers_seen += 1
	var key := col.to_html(false)
	if not beam_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col.lightened(0.3)
		beam_mats[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = Art.beam()
	mi.material_override = beam_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var ln := from.distance_to(to)
	var thick := 2.2 if gift == "mega" else 1.0  # (MEGA LASER: a fat beam)
	mi.global_transform = Transform3D(UiKit.face(to - from).scaled(Vector3(thick, thick, ln)), from)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.05, 0.05, ln), 0.2)
	tw.tween_callback(mi.queue_free)


func pop_fx(w: Vector3, col: Color, kind: int) -> void:
	confetti(w, col, 40 if kind == Space.UFO else 24)
	if kind == Space.UFO:  # the saucer spins away into the distance, wheee
		var mi := MeshKit.instance(Art.ufo(), false)
		add_child(mi)
		mi.global_position = w
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", w + Vector3(randf_range(-20, 20), 18.0, -40.0), 1.4)
		tw.tween_property(mi, "rotation", Vector3(2.0, 18.0, 1.0), 1.4)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.2, 1.4)
		tw.chain().tween_callback(mi.queue_free)


## Stars fly from where they were won into the dashboard.
func fly_stars(from: Vector3, n: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	for k in n:
		var mi := MeshInstance3D.new()
		mi.mesh = Art.star()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = from
		mi.scale = Vector3.ONE * 0.5
		var to := Vector3(-0.3 + k * 0.6, 1.2, -1.2)
		var tw := mi.create_tween()
		tw.tween_interval(k * 0.15)
		tw.tween_property(mi, "global_position", to, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mi, "scale", Vector3.ONE * 0.06, 0.7)
		tw.tween_callback(mi.queue_free)
	sfx.play_at("pickup", from.lerp(Vector3(0, 1, -1), 0.7), -8.0, 1.2)


func toy_fx(k: String) -> void:
	cockpit.toy_fx(k)
	if k == "bubbles":
		var cp := CPUParticles3D.new()
		cp.one_shot = true
		cp.amount = 24
		cp.lifetime = 2.5
		cp.explosiveness = 0.4
		cp.direction = Vector3(0, 0.3, -1)
		cp.spread = 25.0
		cp.initial_velocity_min = 2.0
		cp.initial_velocity_max = 4.0
		cp.gravity = Vector3.ZERO
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 10
		sm.rings = 5
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.7, 0.9, 1.0, 0.45)
		m.metallic_specular = 1.0
		sm.material = m
		cp.mesh = sm
		add_child(cp)
		cp.position = Vector3(0.0, 1.2, -2.2)
		cp.emitting = true
		get_tree().create_timer(3.0).timeout.connect(cp.queue_free)


func _bump_fx() -> void:
	shield.visible = true
	shield_mat.set_shader_parameter("col", Color(0.4, 0.8, 1.0, 0.6))
	shake = 1.0


func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	if net.mode == "host":
		net.event("sfx", [n, p, db, pitch])


func confetti(p: Vector3, col: Color, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = amount
	cp.lifetime = 1.4
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 180.0
	cp.initial_velocity_min = 3.0
	cp.initial_velocity_max = 7.0
	cp.gravity = Vector3.ZERO
	cp.damping_min = 2.0
	cp.damping_max = 4.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.04)
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


# --- VR headline ----------------------------------------------------------------------------------

## VR: one short headline far out in front of the ship (world-locked, facing the pilot).
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
		headline.position = Vector3(0.0, 2.6, -7.0)
		add_child(headline)
	headline.text = text
	headline.visible = true
	headline_t = secs


func _headline(delta: float) -> void:
	if headline == null or not headline.visible or headline_t < 0.0:
		return
	headline_t -= delta
	if headline_t <= 0.0:
		headline.visible = false


# --- TV HUD -------------------------------------------------------------------------------------------

func _make_hud(parent: Control) -> void:
	cross_layer = Control.new()
	UiKit.pin(cross_layer, Control.PRESET_FULL_RECT, false)
	cross_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cross_layer)
	hud = UiKit.ui_root(parent)
	var card := UiKit.panel("card")
	hud.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var col := VBoxContainer.new()
	card.add_child(col)
	flag_row = UiKit.hbox(6)
	col.add_child(flag_row)
	star_row = UiKit.hbox(4)
	col.add_child(star_row)
	pill = UiKit.panel("pill")
	hud.add_child(pill)
	UiKit.pin(pill, Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_top = -60.0
	pill.offset_bottom = -60.0
	_refresh_hud()


func _update_pill() -> void:
	var want := ""
	if party.local_slots().is_empty():
		want = "Join"
	else:
		for s in party.local_slots():
			if not zapped.has(s):
				want = "Zap!"
	if String(net.state_get("phase", "")) == "results":
		want = ""
	if want != pill_text:
		pill_text = want
		for c in pill.get_children():
			c.queue_free()
		if want != "":
			pill.add_child(UiKit.prompts([["A", want]]))
	pill.visible = want != ""


## Top-left: four planet flags (missions done) and eight stars (this mission). No numbers.
func _refresh_hud() -> void:
	if star_row == null:
		return
	for c in star_row.get_children():
		c.queue_free()
	for c in flag_row.get_children():
		c.queue_free()
	var stars := int(net.state_get("stars", 0))
	var done := int(net.state_get("missions", 0))
	for k in MISSIONS:
		flag_row.add_child(UiKit.icon("flag", "gold" if k < done else "dim", 30.0))
	for k in NEED:
		star_row.add_child(UiKit.icon("star", "gold" if k < stars else "dim", 34.0))


# --- Store, results, pause ----------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"stars", "missions":
			_refresh_hud()
		"planet":
			space.set_planet(Story.planet_look(int(value)))
		"deep":
			var dv: Array = value if value is Array else []
			if dv.size() >= 4:
				mode = Deep.mode_of(String(dv[0]))
				var new_gift := String(dv[1])
				season = String(dv[2])
				if season_node != null and season != "":
					season_node.set_season(season)
				if crew_node != null:
					crew_node.set_count(int(dv[3]), true)
				if new_gift != gift:
					gift = new_gift
					_set_module(gift)
					if gift != "":
						var gd := Deep.gift(gift)
						_banner(String(gd.name), "victory")
		"hz":
			var hz := Deep.unpack(value if value is Array else [])
			if hazards != null:
				hazards.show_now(hz)
			if not hz.is_empty():
				surprises_seen += 1
				_banner(String(Deep.KIND_NAMES[String(hz.kind)]), "warning")
		"parts":
			space.station_parts = int(value)
			cockpit.set_station(int(value))
			space.refresh_station()
		"phase":
			var ph := String(value)
			if ph == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
			match ph:
				"play":
					var m := int(net.state_get("mission", 0))
					var mname := String(net.state_get("mname", "GO!"))
					music.play_mood("space")
					if split != null:
						HudKit.banner([hud], mname, "", {"duration": 1.8})
					if m == 0 and int(net.state_get("practice", 3)) & 1 == 0:
						show_headline("FLY THROUGH THE RING!", 6.0)
					else:
						show_headline(mname)
				"cheer":
					music.play_mood("victory")
					show_headline("HOORAY!")
				"pick":
					if headline != null:
						headline.visible = false  # (the pick banner and the orbs say it)
				"dock":
					music.play_mood("victory")
					show_headline("HOME!")


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	if split != null:
		var screen := Awards.results_screen(hud, data, {"party": party, "min_time": 5.0})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "again"))
		results_ui = screen
	if vr_rig != null:
		show_headline("HOME SWEET HOME!", 8.0)
		cockpit.show_again(true)


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	cockpit.show_again(false)


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


# --- Networking -----------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var s := space.pack()
	var xs := PackedFloat32Array()  # every gunner's crosshair: slot, x, y (each machine draws the others')
	for slot in cross:
		var c: Vector2 = cross[slot]
		xs.append_array([float(slot), snappedf(c.x, 0.005), snappedf(c.y, 0.005)])
	for slot in far_cross:
		if party.is_active(int(slot)):
			var c2: Vector2 = far_cross[slot]
			xs.append_array([float(slot), snappedf(c2.x, 0.005), snappedf(c2.y, 0.005)])
	return [pose, space.off, cockpit.steer, space.speed, s[0], s[1], s[2], xs]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var dt := get_process_delta_time()
	if avatar != null:
		avatar.apply_pose(s[0])
	if split != null and (s[0] as PackedFloat32Array).is_empty():
		split.clear_bubble()  # a flat host: no VR player to show in the bubble
		if cockpit.avatar_seat == null:
			cockpit.add_robot()  # ... and the robot flies, like on the host
	var off: Vector2 = s[1]
	space.off = off if space.off.distance_to(off) > 5.0 else space.off.lerp(off, 1.0 - exp(-20.0 * dt))
	var st: Vector2 = s[2]
	cockpit.steer = st
	space.speed = float(s[3])
	space.unpack([s[4], s[5], s[6]], dt)
	if s.size() > 7:
		var xs: PackedFloat32Array = s[7]
		far_cross.clear()
		var i := 0
		while i + 2 < xs.size():
			if not party.is_local(int(xs[i])):
				far_cross[int(xs[i])] = Vector2(xs[i + 1], xs[i + 2])
			i += 3


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"confetti":
			confetti(args[0], args[1], int(args[2]))
		"laser":
			laser(args[0], args[1], args[2])
		"pop":
			pop_fx(args[0], args[1], int(args[2]))
		"star":
			fly_stars(args[0], int(args[1]))
		"toy":
			toy_fx(String(args[0]))
		"bump":
			_bump_fx()
		"zonehit":
			_zone_fx(String(args[0]))
		"orbs":
			if picks != null:
				var sp: Array = []
				for v in (args[2] if args.size() > 2 else []):
					sp.append(v)
				picks.show_row(String(args[0]), args[1] if args.size() > 1 else [], sp)
		"take":
			if picks != null:
				picks.take_fx(int(args[0]), int(args[1]))
		"banner":
			_banner(String(args[0]), String(args[1]))
		"story":
			show_story({"who": String(args[0]), "line": String(args[1]), "pic": String(args[2]),
				"color": Color.from_string(String(args[3]), Story.CAPTAIN_COLOR), "duration": 3.5})


# --- Story and telemetry ------------------------------------------------------------------------------

## A story beat: Captain Whiskers (or a picture) and a few words, on every machine.
func _story(beat: Dictionary) -> void:
	if net.mode == "host":
		net.event("story", [beat.get("who", ""), beat.get("line", ""), beat.get("pic", ""), (beat.get("color", Story.CAPTAIN_COLOR) as Color).to_html()])
	show_story(beat)


func show_story(beat: Dictionary) -> void:
	stories_shown += 1
	if hud != null:
		StoryCard.show([hud], beat)
	if vr_rig != null:
		if vr_story != null and is_instance_valid(vr_story):
			vr_story.queue_free()
		vr_story = StoryCard.show_vr(self, vr_rig.camera, beat)


func _captain(line: String, pic: String = "captain") -> Dictionary:
	return {"who": Story.CAPTAIN, "line": line, "pic": pic, "color": Story.CAPTAIN_COLOR, "duration": 3.5}


## Host: one RUN line per mission (or quit mid-mission): how the family really plays (balance).
func _telemetry(end: String) -> void:
	if trip_plan.is_empty() or tel.is_empty():
		return
	var mi := int(net.state_get("mission", 0))
	var m: Dictionary = trip_plan[clampi(mi, 0, trip_plan.size() - 1)]
	var info := tel.duplicate()
	info.merge({"end": end, "trip": trip_no, "mission": mi, "kind": String(m.k), "tier": int(m.tier), "seed": int(m.s),
		"daily": bool(m.get("daily", false)), "secs": snappedf(mission_t, 0.1), "laps": lap, "stars": int(net.state_get("stars", 0)),
		"crew": _crew_slots().size(), "vr": vr_rig != null,
		"difficulty": mode, "gift": gift, "season": season, "surprises": hz_count, "hits": hz_hits,
		"friends": Deep.crew(int(save.data.crew_xp)), "picks": picks.history.size() if picks != null else 0, "mode": String(net.mode), "planets": (save.data.planets as Array).size()})
	Telemetry.run(GAME_ID, info)
	runs_logged += 1
	tel = {}


func _exit_tree() -> void:
	if net != null and net.mode != "client" and String(net.state_get("phase", "")) == "play":
		_telemetry("quit")


# --- Second pass: picks, surprises, modules, crew (deep.gd, picks.gd, hazards.gd, crew.gd) ---------------------

## Host: the mode, the module, the season and the crew for every machine.
func _send_deep() -> void:
	var friends := Deep.crew(int(save.data.crew_xp))
	if OS.has_environment("SC_CREW"):  # (tests / screenshots: show this many friends, never saved)
		friends = clampi(int(OS.get_environment("SC_CREW")), 0, Deep.CREW.size())
	net.state_set("deep", [mode, gift, season, friends])
	net.state_set("mode", mode)  # (the bots check a TV machine plays at it: tests/bot_kit.gd check_host_mode)


## Nobody here could take a pick (no pilot, no gunner): the middle comes sooner.
func pick_nobody() -> bool:
	return vr_rig == null and _crew_slots().is_empty()


## Host: the next mission, after the mode pick (once a session, from the first seeded trip) or a module pick (every
## mission from the second of a seeded trip).
func _next_mission(i: int) -> void:
	if trip_no >= 1 and not mode_picked:
		_start_pick("mode", i)
	elif trip_no >= 1 and i >= 1 and gift_mission != i and not OS.has_environment("SC_GIFT"):
		_start_pick("gift", i)
	else:
		_go_mission(i)


func _start_pick(stage: String, mission: int) -> void:
	var entries: Array = []
	var opts: Array = []
	if stage == "mode":
		opts = PickOrbs.mode_ids(Deep.mode_of(String(save.data.mode)) if String(save.data.mode) != "" else "brave")
		for id in opts:
			var md := PickOrbs.mode(String(id))
			entries.append({"id": id, "name": md.name, "pic": md.pic, "color": md.color})
		_story(_captain("Easy or tricky?"))
	else:
		opts = Deep.gift_choices(Story.parts_for(trip_no), String(save.data.last_gift),
			Seeded.derive(int(save.data.world), "gift%d/%d" % [trip_no, mission]))
		for id in opts:
			var gd := Deep.gift(String(id))
			entries.append({"id": id, "name": gd.name, "pic": gd.pic, "color": gd.color})
		_story(_captain("A new ship part!", "gift"))
	_clear_surprise()
	net.state_set("mission", mission)
	net.state_set("phase", "pick")
	net.state_set("stars", 0)
	_banner_all("PICK ONE!", "default")
	picks.begin(stage, entries, opts, func(st: String, opt: Variant, slot: int) -> void: _on_picked(st, opt, slot, mission))
	sound_at("power_up", Vector3(0, 1.2, -4), -8.0, 1.3)


## Host: the crew picked (or the middle one was taken for them).
func _on_picked(stage: String, opt: Variant, _slot: int, mission: int) -> void:
	if stage == "mode":
		mode_picked = true
		mode = Deep.mode_of(String(opt))
		save.data.mode = mode
		_story({"who": Story.CAPTAIN, "line": String(PickOrbs.MODE_LINES.get(mode, "Let's go!")), "pic": String(PickOrbs.mode(mode).pic),
			"color": PickOrbs.mode_color(mode), "duration": 3.0})
		_banner_all(PickOrbs.mode_name(mode), "victory")
		_send_deep()
	else:
		gift = String(opt)
		gift_mission = mission
		save.data.last_gift = gift
	save.mark_dirty()
	print("Picked %s: %s" % [stage, str(opt)])
	_next_mission(mission)


## Host: this lap's surprises.
func _plan_surprises() -> void:
	var spec := {"mode": mode, "season": season, "trip": trip_no}
	if OS.has_environment("SC_SURPRISES_NOW"):
		spec["trip"] = maxi(1, trip_no)
		if lap == 0:
			spec["first"] = Deep.SHORT_FIRST
	hz_list = Deep.hazards(plan, spec)
	hz_i = 0
	_clear_surprise()
	if not hz_list.is_empty():
		print("Starship Crew surprises: %s mode, %s, module %s, lap %d: %s" % [mode, season, gift if gift != "" else "none", lap,
			str(hz_list.map(func(e: Dictionary) -> String: return "%s@%.0f" % [e.kind, float(e.t)]))])


## Host, every frame of a mission: tell the next surprise, set it off (did it catch the ship?), clear it.
func _tick_surprises() -> void:
	if hz_now.is_empty():
		if hz_i < hz_list.size() and plan_t >= float((hz_list[hz_i] as Dictionary).t):
			hz_now = hz_list[hz_i]
			hz_i += 1
			hz_hit = false
			hz_count += 1
			net.state_set("hz", Deep.pack(hz_now))
		return
	var since := plan_t - float(hz_now.t)
	if since >= float(hz_now.warn) and not hz_hit and Deep.inside(hz_now, space.off):
		hz_hit = true
		hz_hits += 1
		zone_hits += 1
		_zone_hit(String(hz_now.kind))
	if since >= Deep.span(hz_now):
		_clear_surprise()


func _clear_surprise() -> void:
	hz_now = {}
	hz_hit = false
	if net != null and not (net.state_get("hz", []) as Array).is_empty():
		net.state_set("hz", [])


## Host: a surprise caught the ship: a wobble, maybe a star off (BRAVE / HARD) and a dizzy ship (never with the shield).
func _zone_hit(kind: String) -> void:
	var lose := Deep.lose(mode, gift)
	if lose > 0 and String(net.state_get("phase", "")) == "play":
		net.state_set("stars", maxi(0, int(net.state_get("stars", 0)) - lose))
	dizzy_t = Deep.dizzy(mode, gift)
	sound_at("bounce" if kind == "stream" else "whoosh", Vector3(0, Space.SHIP_Y, -1.0), -2.0, 0.7)
	_pulse_both(0.7, 0.2)
	_zone_fx(kind)
	net.event("zonehit", [kind])


## Every machine: the shield flashes in the surprise's colour and the view shakes.
func _zone_fx(kind: String) -> void:
	shield.visible = true
	var c := HazardsScript.color_of(kind)
	shield_mat.set_shader_parameter("col", Color(c.r, c.g, c.b, 0.7))
	shake = 1.2


## Every machine: this mission's ship module, drawn on the ship (the shield is the bubble itself).
func _set_module(g: String) -> void:
	if module != null and is_instance_valid(module):
		module.queue_free()
	module = null
	if g == "":
		return
	module = Node3D.new()
	module.name = "Module"
	var col: Color = Deep.gift(g).get("color", Color.WHITE)
	match g:
		"turbo":  # two big orange flames from the engines
			for s in [-1.0, 1.0]:
				var f := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.36
				cm.height = 1.8
				cm.radial_segments = 12
				f.mesh = cm
				f.material_override = _glow_mat(col, 0.8)
				f.rotation = Vector3(-PI * 0.5, 0, 0)
				f.position = Vector3(s * 1.0, -0.4, 5.95)
				f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				module.add_child(f)
		"tractor":  # a soft green beam out of the nose
			var bm := MeshInstance3D.new()
			var cm2 := CylinderMesh.new()
			cm2.top_radius = 0.3
			cm2.bottom_radius = 2.4
			cm2.height = 10.0
			cm2.radial_segments = 16
			cm2.cap_top = false
			cm2.cap_bottom = false
			bm.mesh = cm2
			bm.material_override = _glow_mat(col, 0.16)
			bm.rotation = Vector3(-PI * 0.5, 0, 0)
			bm.position = Vector3(0, -0.15, -10.2)
			bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			module.add_child(bm)
		"mega", "boost":  # glowing tips on the wing turrets
			for tp in Art.TURRETS:
				var ball := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.32
				sm.height = 0.64
				sm.radial_segments = 12
				sm.rings = 6
				ball.mesh = sm
				ball.material_override = _glow_mat(col, 0.9)
				ball.position = (tp as Vector3) + Vector3(0, 0, -0.6)
				ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				module.add_child(ball)
	add_child(module)


func _glow_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under VR cards
	return m


## A banner on this machine: the TV / Deck HUD and the VR card (it moves clear of the pick orbs).
func _banner(title: String, style: String = "default") -> void:
	if hud != null:
		HudKit.banner([hud], title, "", {"duration": 2.2, "style": style})
	if vr_rig != null:
		if headline != null:
			headline.visible = false
		HudKit.vr_banner(self, vr_rig.camera, title, "", {"duration": 2.2, "sound": "", "distance": 2.4, "style": style})


## Host: a banner on every machine (one that doesn't come from a state change).
func _banner_all(title: String, style: String) -> void:
	_banner(title, style)
	if net.mode == "host":
		net.event("banner", [title, style])
