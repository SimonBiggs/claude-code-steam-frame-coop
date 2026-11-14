extends Node3D
const VrText := preload("res://core/vr_text.gd")
const Who := preload("res://core/who.gd")  # who joined / left (names, not "TV player")
## Snowball Blitz: defend the snow fort in the village square from waves of mischievous snowmen.
## VR player (host): the team's sniper, throwing real snowballs with their hands.
## TV players: lob charged snowballs and pack the fort walls back up. Hot cocoa warms you up.
##
## SIMPLE_MODE (the family: "all of the games have become too complicated", "simple games are the fun
## games", "everything's being driven by text"): defend the snow fort from waddling snowmen by
## throwing snowballs - the VR player with real hands, the TV players with one press.
##  - PRACTICE first: the VR player gets glowing target snowmen close by, one at a time, and a
##    see-through ghost hand (core/ghost_hand.gd) that scoops snow and throws; each TV player gets one
##    glowing target in front of them, with a bobbing glowing arrow over it.
##  - One new thing per wave: 1 a few slow plain snowmen that don't throw, 2 they throw (harmless
##    splats; the pan lid still blocks), 3 sled riders, 4 snow bunnies, 5 giants (MEGA SNOWBALL drops),
##    6 balloon snowmen, 7 the SNOW KING, 8-9 a mix, 10 the YETI finale, then endless.
##  - Everything beside the VR player reacts to touch (props.gd): snow piles to scoop, icicles that
##    tinkle and snap off to throw, a snowy tree that dumps its snow, a sled to shove, a bell, and the
##    fort wall puffs (and packs up) when patted.
##  - Off: warmth / freezing / hot cocoa, wall packing (the walls snow back up by themselves), charged
##    lobs (a TV press just throws, with a gentle aim assist), shield snowmen, weather events, fort
##    upgrades, streaks, score / fort / warmth readouts, the minimap, popups, hint panels and awards.
##    Text: one short headline ("WAVE 2!"); game over restarts by itself.
##  - No how-to words (visual teaching): each TV view has a pulsing glowing button in that player's
##    own controls plus an icon under the crosshair (hud.gd): RT / CLICK / SPACE / ENTER + a snowball
##    until they've thrown twice; STICK / MOUSE / an arrow key + an arrow, with a big glowing arrow
##    round the crosshair, when every snowman is off screen (until they've turned to one twice); a
##    pulsing bolt when their controller is unplugged. The ghost hand stops once the VR player has hit
##    two practice targets; a MEGA SNOWBALL has a bobbing arrow over it. PAUSED has no sentence, and
##    the small WAVE n at the top hides while the big headline shows. Each cue goes after two goes
##    (cue_did / cue_learned).
##
## STORY + DEPTH (simple mode): BOBO the polar bear cub lives in the snowy village; each game is a SIEGE
## made from a seed (siegegen.gd: the gates the snowmen march in from, which new kind each wave brings,
## the gaps), and the snowmen want to pinch one of Bobo's things (cocoa, scarf, mittens, fish), shown on
## picture cards (story_pictures.gd). Every game where a wave is beaten builds an IGLOO in Bobo's village
## round the square (saved; igloos grow a stage each play-day, the more igloos the bigger the next siege).
## TODAY'S BLIZZARD: the first game each day is the same siege on every machine and builds a golden
## igloo. Telemetry: one RUN line per game and on quit. Networked: the host spawns the snowmen as before
## and sends the village and the story cards as events (every machine builds the igloos itself).
##
## PICKS (core/pick_orbs.gd: glowing picture orbs in a row in front of the fort; throw a snowball at one - the VR player
## too - or walk into it): the first game of a visit VOTES GENTLE / BRAVE / HARD after the practice (picks.gd: everyone
## votes on core/pick_flow.gd, the most votes, a tie stays gentler; SB_MODE=... skips
## it; the family's last mode is saved and sits in the middle), which shapes the siege (siegegen.gd MODE_NUM) and the
## bosses (bosses.gd). After every cleared wave BOBO'S GIFTS (gifts.gd): three seeded gift orbs, each player takes one
## (they stack, capped); the middle one is taken for anyone who doesn't choose in time. BOSS TELLS (bosses.gd): the
## Snow King's and the Yeti's big attacks glow and put a ring on the snow first (core/warn_rings.gd, every machine).
## Events: "orbs" [stage, entries] and "gifts" {slot: gifts} are sticky (a late machine catches up), "take" [i, slot],
## "warn" [boss net id, pos, radius, colour, secs]. SB_WAVE=n jumps to wave n after the picks (What's New "try").
##
## THIRD PASS: SEASONS (seasons.gd: the square dresses for the season, SeasonKit / ARCADE_SEASON; net state "season"),
## WARNED SURPRISES (tricks.gd: SNOW SLIDE lines and ICICLES circles, seeded per siege, told on warn rings + a card
## first; events "trick" [wave, kind, plan] / "trick_go" [wave, kind, plan], net state "trick" "tell:W:kind" /
## "go:W:kind"; SB_TRICK=slide|icicles puts one in every wave from wave 1 for tests and What's New), and BOBO'S
## FRIENDS (rink.gd: a seeded visitor per siege who stays to skate on the growing pond once STAY_WAVES waves are held;
## save.data.rink; sticky event "rink" [ids, visitor]).
const SIMPLE_MODE := true
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const SiegeGen := preload("res://games/snowball_blitz/siegegen.gd")
const Seeded := preload("res://core/seeded.gd")
const Save := preload("res://core/save.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const PicksScript := preload("res://games/snowball_blitz/picks.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const Gifts := preload("res://games/snowball_blitz/gifts.gd")
const Bosses := preload("res://games/snowball_blitz/bosses.gd")
const Looks := preload("res://games/snowball_blitz/looks.gd")
const Tricks := preload("res://games/snowball_blitz/tricks.gd")
const Seasons := preload("res://games/snowball_blitz/seasons.gd")
const Rink := preload("res://games/snowball_blitz/rink.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const ORB_ROW := Vector3(0.0, 0.0, -4.4)  # the pick orbs float in a row here (in front of the VR player, inside the fort)
const ORB_GAP := 2.4
const ORB_Y := 2.0  # (above the walls and the props round the VR player, seen from every start spot)
const GAME_ID := "snowball_blitz"
const VILLAGE_CHEERS := {1: "Our first igloo!", 5: "Five igloos!", 10: "Ten igloos!", 24: "A whole village!"}
const KIND_PICS := {"snowman": "snowman", "sled": "sledman", "bunny": "bunny", "giant": "snowman", "balloon": "balloon", "king": "snowking", "yeti": "yeti"}
const PropsScript := preload("res://games/snowball_blitz/props.gd")
const GhostHand := preload("res://core/ghost_hand.gd")
const VR_PRACTICE := 3  # glowing targets the VR player knocks over before the snowmen come
## Simple mode: the one new kind each wave brings (it joins the mix from the next wave on).
const SIMPLE_NEW := {3: "sled", 4: "bunny", 5: "giant", 6: "balloon"}
const SIMPLE_KING := 7
const SIMPLE_FINALE := 10

const PlayerScript := preload("res://games/snowball_blitz/player.gd")
const SnowmanScript := preload("res://games/snowball_blitz/snowman.gd")
const SnowballScript := preload("res://games/snowball_blitz/snowball.gd")
const CocoaScript := preload("res://games/snowball_blitz/cocoa.gd")
const WorldScript := preload("res://games/snowball_blitz/world.gd")
const HudScript := preload("res://games/snowball_blitz/hud.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const ClassicSeats := preload("res://core/classic_seats.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const JoinInputScript := preload("res://games/snowball_blitz/join_input.gd")
const DirectorScript := preload("res://games/snowball_blitz/director.gd")

## Waves 4 and 8 bring the Snow King; wave 12 is the finale with the YETI. Then endless mode.
const FINALE_WAVE := 12
const MEGA_R := 0.45
const MEGA_DMG := 6.0
const MEGA_SPLASH := 2.6
const EXTRA_SOUNDS := {
	"whoosh": [0.4, 300.0, 900.0, 0.25, "sine", 0.6],
	"thud": [0.4, 160.0, 40.0, 0.6, "saw", 0.6],
	"fanfare": [1.6, 392.0, 1568.0, 0.4, "tri", 0.0],
	"roar": [0.9, 150.0, 45.0, 0.6, "saw", 0.45],
	"bell": [1.4, 1318.0, 1310.0, 0.4, "sine", 0.0],
	"tinkle": [0.22, 2637.0, 3136.0, 0.25, "sine", 0.0],
	"whump": [0.35, 140.0, 50.0, 0.5, "sine", 0.7],
	"crunch": [0.12, 420.0, 180.0, 0.3, "saw", 0.85],
}

const ARENA_RADIUS := 20.0
const FORT_RADIUS := 6.0
const SEGMENTS := 8
const SEG_MAX := 100.0
const SEG_WIDTH := 3.4
const SEG_DEPTH := 0.9
const SEG_HEIGHT := 1.25
const GRAVITY := 12.0
const BOSS_EVERY := 4
const MAX_TV_PLAYERS := 6  # TV players are indices 1..6 when networked (0..5 in local split screen)
const PLAYER_COLORS: Array[Color] = Looks.PLAYER_COLORS  # (looks.gd: palette.gd reads it)
const SCARF_COLORS: Array[Color] = [Color(0.9, 0.2, 0.25), Color(0.2, 0.55, 0.95), Color(0.95, 0.75, 0.2), Color(0.3, 0.75, 0.4), Color(0.75, 0.35, 0.85)]
const BUBBLE_SHADER := """
shader_type canvas_item;
uniform vec4 ring_color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
void fragment() {
	float r = length(UV - 0.5);
	vec4 c = texture(TEXTURE, UV);
	float inside = 1.0 - smoothstep(0.485, 0.5, r);
	float ring = smoothstep(0.45, 0.47, r);
	COLOR = vec4(mix(c.rgb, ring_color.rgb, ring), inside);
}
"""

# Instance copies of the constants (other scripts read them through `main`).
var gravity := GRAVITY
var fort_r := FORT_RADIUS
var arena_radius := ARENA_RADIUS
var seg_max := SEG_MAX
var segments := SEGMENTS

var players: Array = []
## Any number of TV machines (TV, Steam Decks) may join, and a flat host (no VR) works (docs/MULTI_MACHINE.md).
var multi_machine := true
## Which machine drives which TV player (core/classic_seats.gd; core/net.gd checks it too).
var seats: ClassicSeats
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var mats := {}
var meshes := {}
var cameras: Array[Camera3D] = []
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var ghost_cam: Camera3D
var ghost_nodes := {}
var synced := false
var net_ids := 0

var wave := 0
var score := 0
var to_spawn := 0
var spawn_timer := 0.0
var break_timer := 4.0
var in_break := true
var game_over := false
var game_over_time := 0.0
var cocoa_timer := 14.0
var repair_score := 0.0
var stats := []
var view_grid: GridContainer
var join_listener: Node
var pad_memory := {}  # joypad device id -> player index it last controlled (rejoins on reconnect)
var boss_hp := -1.0  # fraction, -1 when no Snow King is around
var boss_name := ""
var dir_node: Node

var seg_hp: Array[float] = []
var seg_nodes: Array = []  # per segment: {stack, mat, bar, bar_mat, shape}

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_hurt_mat: StandardMaterial3D
var vr_hurt := 0.0
var simple := SIMPLE_MODE  # other scripts read main.simple
var props: Node3D  # simple mode: touchable things beside the VR player (props.gd)
var ghost_hand: GhostHand  # simple mode: the practice ghost hand (VR player only)
var ghost_ball: MeshInstance3D  # the ghost snowball it makes and throws
var ghost_fly_from := Vector3.ZERO
var ghost_fly_vel := Vector3.ZERO
var practice := SIMPLE_MODE  # simple mode: target practice before wave 1 (mirrored to the TV)
var practice_t := 0.0
var vr_hits := 0
var vr_target_t := 1.0
var tv_given := {}  # player index -> true once their practice target appeared
var simple_new_left := 0
# --- Bobo's village + the seeded siege (host / local own them; TV machines get the village + cards) ---
var save: Node
var siege := {}
var wave_spawned := 0  # spawns of this wave's plan used so far
var built := false  # this game's igloo is built (once per game)
var logged := false  # this game's RUN line is written
var siege_t := 0.0
var village: Node3D
var village_list: Array = []  # [[built play-day, golden, waves beaten, want], ...]
var village_days := 0
var village_count := -1
var story_queue: Array = []  # [line, pic, color]
var story_t := 0.0
## gentle / brave / hard (the MODE pick; siegegen.gd MODE_NUM, bosses.gd). The host's pick rules every machine: set on
## the host / local game it goes out as net state "mode", and a TV machine takes it from there (_on_state_changed)
## (2026-11-12: a TV machine kept its own "brave" until a gift pick told it). Never set it on a client by hand.
var game_mode := "brave":
	set(v):
		game_mode = v
		if net != null and net.mode != "client":
			net.state_set("mode", v)
var orbs: PickOrbs  # the pick orbs (every machine draws them)
var picks: Node  # picks.gd: the MODE vote on those orbs (core/pick_flow.gd, everyone votes)
var rings: WarnRings  # boss warning rings (every machine)
var pick_stage := ""  # host / local: "mode" or "gift" while orbs are up
var pick_ids: Array = []
var pick_t := 0.0
var picked := {}  # slot -> orb index (this pick)
var gifts_taken := {}  # slot -> [gift ids] this game (telemetry)
var season := ""  # this game's season (seasons.gd; every machine)
var seasons_node: Node3D
var rink: Node3D  # Bobo's friends' skating pond (rink.gd; every machine)
var friend := ""  # this siege's visitor (rink.gd id)
var friend_stayed := false
var trick := {}  # host / local: this wave's surprise (tricks.gd), {} when none
var trick_t := 0.0  # host: seconds to its tell (phase "wait"), then to its going off ("tell")
var trick_phase := ""  # "", "wait", "tell", "go"
var trick_log: Array = []  # every machine: [wave, kind, told (siege_t), went (siege_t)] (bots check the tell came first)
var tricks_done := 0
var slides: Array = []  # every machine: rolling snow slide balls [{node, from, dir, len, t}]


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	var will_vr := xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	WorldScript.build(self, ARENA_RADIUS, will_vr)
	seasons_node = Seasons.new()
	add_child(seasons_node)
	rink = Rink.new()
	rink.name = "Rink"
	add_child(rink)
	rink.attach(get_node("Pond"))
	_build_fort()
	_build_hud()
	if SIMPLE_MODE:
		props = PropsScript.new()
		props.main = self
		add_child(props)
	orbs = PickOrbs.new()
	orbs.collision_layer = 0  # (snowballs ask orbs.nearest_hit: no physics bodies here)
	orbs.on_hit = func(i: int, by) -> void: on_orb_hit(i, by)
	add_child(orbs)
	rings = WarnRings.new()
	add_child(rings)
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	picks = PicksScript.new()
	picks.main = self
	add_child(picks)
	net.sticky_event("village")  # a machine that joins later gets the latest one (core/net.gd)
	net.sticky_event("orbs")
	net.sticky_event("gifts")
	net.sticky_event("rink")
	seats = ClassicSeats.new(self, {
		"no_keys": -2,  # player.gd key_set -2: controller only
		"free_actions": ["restart", "pause"],
		"is_local": _is_local_tv,
		"keys": func(p) -> int: return p.keys() if p.keys() >= 0 else -2,
		"seat_free": func(p) -> bool: return _is_local_tv(p) and not p.active and p.joy < 0 and p.keys() < 0 and not p.has_meta(ClassicSeats.WANT),
		"ghost": _seat_ghost,
		"deactivate": func(p) -> void: _deactivate_player(p.index),
		"layout": _sync_view_visibility,
		"full": func() -> void: sound("miss", -8.0),  # no words: nothing happens
	})
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.has_environment("DUO_JOIN"):
		_show_center("Connecting to the VR player…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if will_vr or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	if seats.deck_alone():
		seats.deck_solo(0)  # a Deck on its own: one full-screen player
	elif mode == "client":
		players[1].set_meta(ClassicSeats.WANT, true)  # ask the host for P2's seat (it may hand out another one)
	ready_to_play = true
	_ensure_party()
	if SIMPLE_MODE:
		_show_center("SNOWBALL BLITZ!", 2.5)
		if mode != "client":
			_start_siege()
		return
	if mode == "host":
		_show_center("Waiting for the TV players to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED!", 1.5)
	else:
		_show_center("SNOWBALL BLITZ\nDefend the fort!", 2.5)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


# --- Shared materials, meshes and effects ------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## Cached materials by name, shared by every snowman/snowball so the GPU can batch them.
func mat(mat_name: String) -> StandardMaterial3D:
	if mats.has(mat_name):
		return mats[mat_name]
	var m: StandardMaterial3D
	match mat_name:
		"snow":
			m = make_material(Looks.SNOW_BODY, 0.0)
			m.roughness = 0.9
			m.rim_enabled = true
			m.rim = 0.5
		"fort":
			m = make_material(Looks.FORT, 0.0)
			m.roughness = 0.95
		"coal":
			m = make_material(Color(0.06, 0.06, 0.08), 0.0)
		"carrot":
			m = make_material(Color(1.0, 0.5, 0.12), 0.25)
		"hat":
			m = make_material(Color(0.12, 0.1, 0.14), 0.0)
		"hat_band":
			m = make_material(Color(0.85, 0.15, 0.2), 0.3)
		"stick":
			m = make_material(Color(0.4, 0.25, 0.15), 0.0)
		"crown":
			m = make_material(Color(1.0, 0.8, 0.25), 1.2)
			m.metallic = 0.8
			m.roughness = 0.3
		"gem":
			m = make_material(Color(0.4, 0.8, 1.0), 3.0)
		"sled":
			m = make_material(Color(0.85, 0.2, 0.2), 0.0)
		"snowball":
			m = make_material(Looks.SNOWBALL, 0.35)
		"enemy_ball":
			m = make_material(Looks.ENEMY_BALL, 1.4)
		"ice":
			m = make_material(Color(0.6, 0.85, 1.0, 0.45), 0.6)
			UiKit.see_through(m)
			m.roughness = 0.1
		"thaw":
			m = make_material(Color(1.0, 0.65, 0.3, 0.35), 1.0)
			UiKit.see_through(m)
		"skin":
			m = make_material(Color(1.0, 0.8, 0.65), 0.0)
		"lid":
			m = make_material(Color(0.8, 0.82, 0.86), 0.0)
			m.metallic = 0.9
			m.roughness = 0.25
		"mug":
			m = make_material(Color(0.85, 0.2, 0.2), 0.0)
		"cocoa":
			m = make_material(Color(0.4, 0.22, 0.12), 0.0)
		"cocoa_ring":
			m = make_material(Color(1.0, 0.65, 0.3), 2.0)
		"steam":
			m = make_material(Color(1, 1, 1, 0.35), 0.0)
			UiKit.see_through(m)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_:
			if mat_name.begins_with("scarf"):
				m = make_material(SCARF_COLORS[int(mat_name.substr(5)) % SCARF_COLORS.size()], 0.15)
			else:
				m = make_material(Color.MAGENTA, 0.0)
	mats[mat_name] = m
	return m


func sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if meshes.has(key):
		return meshes[key]
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	meshes[key] = sm
	return sm


## Local-only puff of snow (both machines make their own for snowball splats).
func puff(pos: Vector3, color: Color, amount: int = 10, size: float = 0.08) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = make_material(color, 0.3) if color != Color(1, 1, 1) else mat("snowball")
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Networked burst: shown here and on the TV.
func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.1) -> void:
	puff(pos, color, amount, size)
	if net:
		net.event("burst", [pos, color, amount, size])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	if not sfx.has_meta("sb_sounds") and sfx.has_method("add_sound"):
		sfx.set_meta("sb_sounds", true)
		for k in EXTRA_SOUNDS:
			sfx.add_sound(k, EXTRA_SOUNDS[k])
	sfx.play(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Floating 3D text that rises and fades; shown on both machines.
func popup(pos: Vector3, text: String, color: Color) -> void:
	if SIMPLE_MODE:
		return  # no floating numbers or words: the splats and sounds say it
	HudKit.popup(self, pos, text, {"color": color, "outline": Color(0, 0, 0, 0.85), "size": 1.38, "lift": 1.4, "time": 1.35})
	if net:
		net.event("popup", [pos, text, color])


## A snowman collapses: a burst of snow, a pile that slowly settles, and its hat flying off.
func collapse_fx(pos: Vector3, size: float, kind: String) -> void:
	puff(pos + Vector3.UP * size, Color(1, 1, 1), 26 + int(size * 14.0), 0.1 * size)
	var pile := MeshInstance3D.new()
	pile.mesh = sphere_mesh(0.6)
	pile.material_override = mat("snow")
	pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pile)
	pile.global_position = pos
	pile.scale = Vector3(1.0, 1.4, 1.0) * size
	var carrot := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.05
	cm.height = 0.32
	cm.radial_segments = 8
	cm.rings = 1
	carrot.mesh = cm
	carrot.material_override = mat("carrot")
	pile.add_child(carrot)
	carrot.position = Vector3(0.1, 0.5, -0.2)
	carrot.rotation = Vector3(-1.2, randf() * TAU, 0.3)
	carrot.scale = Vector3.ONE / size
	var t := pile.create_tween()
	t.tween_property(pile, "scale", Vector3(1.5, 0.45, 1.5) * size, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.0)
	t.tween_property(pile, "scale", Vector3(1.6, 0.02, 1.6) * size, 2.0)
	t.tween_callback(pile.queue_free)
	if kind != "sled":
		var hat := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.19 * size
		hm.bottom_radius = 0.22 * size
		hm.height = 0.34 * size
		hm.radial_segments = 10
		hat.mesh = hm
		hat.material_override = mat("crown" if kind == "king" else "hat")
		add_child(hat)
		var start := pos + Vector3.UP * 2.0 * size
		hat.global_position = start
		var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 1.5 * size
		var ht := hat.create_tween().set_parallel()
		ht.tween_property(hat, "global_position:x", start.x + side.x, 0.9)
		ht.tween_property(hat, "global_position:z", start.z + side.z, 0.9)
		ht.tween_property(hat, "global_position:y", start.y + 1.2 * size, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ht.tween_property(hat, "global_position:y", pos.y + 0.15, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD).set_delay(0.35)
		ht.tween_property(hat, "rotation", Vector3(randf_range(3, 8), randf_range(-3, 3), randf_range(2, 5)), 0.9)
		ht.chain().tween_interval(2.5)
		ht.chain().tween_callback(hat.queue_free)
	if net:
		net.event("collapse", [pos, size, kind])


# --- The fort ----------------------------------------------------------------

func seg_center(i: int) -> Vector3:
	var a := TAU * i / SEGMENTS
	return Vector3(cos(a), 0, sin(a)) * FORT_RADIUS


func _build_fort() -> void:
	for i in SEGMENTS:
		seg_hp.append(SEG_MAX)
		var a := TAU * i / SEGMENTS
		var radial := Vector3(cos(a), 0, sin(a))
		var tangent := Vector3(-sin(a), 0, cos(a))
		var root := Node3D.new()
		add_child(root)
		root.global_transform = Transform3D(Basis(tangent, Vector3.UP, -radial), radial * FORT_RADIUS)
		var stack := Node3D.new()
		root.add_child(stack)
		var m := mat("fort").duplicate() as StandardMaterial3D
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(SEG_WIDTH, SEG_HEIGHT, SEG_DEPTH)
		wall.mesh = bm
		wall.material_override = m
		wall.position.y = SEG_HEIGHT / 2.0
		stack.add_child(wall)
		# Snow-block crenellations along the top.
		var merlon := BoxMesh.new()
		merlon.size = Vector3(0.6, 0.35, SEG_DEPTH * 0.9)
		for x in [-1.2, 0.0, 1.2]:
			var mi := MeshInstance3D.new()
			mi.mesh = merlon
			mi.material_override = m
			mi.position = Vector3(x, SEG_HEIGHT + 0.17, 0)
			stack.add_child(mi)
		# Health bar above the wall (shown when damaged).
		var bar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(SEG_WIDTH * 0.8, 0.08, 0.08)
		bar.mesh = bb
		var bar_mat := make_material(Color(0.4, 1.0, 0.5), 2.0)
		bar.material_override = bar_mat
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.position.y = SEG_HEIGHT + 0.75
		root.add_child(bar)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(SEG_WIDTH, SEG_HEIGHT + 0.4, SEG_DEPTH)
		cs.shape = shape
		cs.position.y = (SEG_HEIGHT + 0.4) / 2.0
		body.add_child(cs)
		root.add_child(body)
		seg_nodes.append({"stack": stack, "mat": m, "bar": bar, "bar_mat": bar_mat, "shape": cs, "shown": 1.0})
	# A snowy mound in the middle: the VR player's scooping spot.
	var mound := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 1.6
	tm.rings = 24
	tm.ring_segments = 8
	mound.mesh = tm
	mound.material_override = mat("snow")
	mound.scale = Vector3(1.0, 0.6, 1.0)
	add_child(mound)


func _update_fort_visuals(delta: float) -> void:
	for i in SEGMENTS:
		var n: Dictionary = seg_nodes[i]
		var frac := seg_hp[i] / SEG_MAX
		var shown: float = lerpf(n.shown, frac, 1.0 - exp(-10.0 * delta))
		n.shown = shown
		var stack: Node3D = n.stack
		stack.scale = Vector3(1.0, maxf(0.08, shown), 1.0)
		var m: StandardMaterial3D = n.mat
		m.albedo_color = Color(0.62, 0.7, 0.9).lerp(Color(0.9, 0.94, 1.0), frac)
		if director().ice_walls():
			# ICE WALLS upgrade: shiny, blue and faintly glowing.
			m.albedo_color = m.albedo_color.lerp(Color(0.6, 0.85, 1.0), 0.6)
			if not m.emission_enabled:
				m.emission_enabled = true
				m.emission = Color(0.3, 0.6, 1.0)
				m.emission_energy_multiplier = 0.3
				m.metallic = 0.4
				m.roughness = 0.25
		var bar: MeshInstance3D = n.bar
		bar.visible = frac < 0.97 and not SIMPLE_MODE  # simple mode: the wall's height shows it
		bar.scale = Vector3(maxf(frac, 0.02), 1.0, 1.0)
		var bm: StandardMaterial3D = n.bar_mat
		bm.albedo_color = Color(1.0, 0.3, 0.2).lerp(Color(0.4, 1.0, 0.5), frac)
		bm.emission = bm.albedo_color
		var cs: CollisionShape3D = n.shape
		var off := frac < 0.15
		if cs.disabled != off:
			cs.set_deferred("disabled", off)


func fort_fraction() -> float:
	var total := 0.0
	for h in seg_hp:
		total += h
	return total / (SEG_MAX * SEGMENTS)


## Which standing fort wall (if any) does a ball at p touch?
func seg_hit(p: Vector3, r: float) -> int:
	var flat := Vector2(p.x, p.z)
	var d := flat.length()
	if absf(d - FORT_RADIUS) > SEG_DEPTH / 2.0 + r:
		return -1
	var a := atan2(p.z, p.x)
	var i := posmod(roundi(a / (TAU / SEGMENTS)), SEGMENTS)
	if seg_hp[i] <= 0.0:
		return -1
	var c := seg_center(i)
	var tangent := Vector3(-sin(TAU * i / SEGMENTS), 0, cos(TAU * i / SEGMENTS))
	if absf((p - c).dot(tangent)) > SEG_WIDTH / 2.0 + r:
		return -1
	var top := (SEG_HEIGHT + 0.35) * maxf(0.08, seg_hp[i] / SEG_MAX)
	return i if p.y < top + r else -1


func damage_segment(i: int, amount: float) -> void:
	if seg_hp[i] <= 0.0:
		return
	if director().ice_walls():
		amount *= 0.65
	seg_hp[i] = maxf(0.0, seg_hp[i] - amount)
	if seg_hp[i] <= 0.0:
		var c := seg_center(i)
		burst(c + Vector3.UP * 0.6, Color(0.85, 0.92, 1.0), 30, 0.14)
		sound("big_kill", -3.0, 0.9)
		popup(c + Vector3.UP * 2.2, "WALL DOWN!", Color(1.0, 0.45, 0.35))
		print("Fort wall %d knocked down (fort %d%%)" % [i, int(fort_fraction() * 100.0)])


func repair_segment(i: int, amount: float, who: int) -> void:
	if i < 0 or i >= SEGMENTS or game_over:
		return
	var before := seg_hp[i]
	seg_hp[i] = minf(SEG_MAX, seg_hp[i] + amount)
	var gained := seg_hp[i] - before
	stat_add(who, "packed", gained)
	repair_score += gained * 0.5
	if repair_score >= 1.0:
		score += int(repair_score)
		repair_score -= int(repair_score)
	if before < SEG_MAX and seg_hp[i] >= SEG_MAX:
		popup(seg_center(i) + Vector3.UP * 2.0, "PACKED!", Color(0.7, 0.9, 1.0))
		sound("pickup", -4.0, 0.8)


## Nearest damaged wall segment within reach of pos, or -1.
func repair_target(pos: Vector3) -> int:
	var best := -1
	var best_d := 2.6
	for i in SEGMENTS:
		if seg_hp[i] >= SEG_MAX - 0.5:
			continue
		var c := seg_center(i)
		var dd := Vector2(pos.x - c.x, pos.z - c.z).length()
		if dd < best_d:
			best_d = dd
			best = i
	return best


## Little puffs while a player packs snow onto a wall (local only).
func pack_puff(i: int, color: Color) -> void:
	var c := seg_center(i) + Vector3.UP * (0.4 + SEG_HEIGHT * seg_hp[i] / SEG_MAX)
	var tangent := Vector3(-sin(TAU * i / SEGMENTS), 0, cos(TAU * i / SEGMENTS))
	puff(c + tangent * randf_range(-1.4, 1.4), Color(1, 1, 1) if randf() < 0.7 else color.lightened(0.5), 5, 0.06)
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	sfx.play("zap", -16.0, 0.35)


# --- Snowballs ---------------------------------------------------------------

func spawn_ball(origin: Vector3, v: Vector3, r: float, dmg: float, team: String, owner_index: int, visual_only: bool = false, look: String = "") -> void:
	var b := SnowballScript.new()
	b.look = look
	b.main = self
	b.vel = v
	b.radius = r
	b.damage = dmg
	b.team = team
	b.owner_index = owner_index
	b.visual_only = visual_only
	add_child(b)
	b.global_position = origin
	var from_remote: bool = owner_index >= 0 and players[owner_index].remote
	if not visual_only and not from_remote:
		net.event("ball", [origin, v, r, team] if look == "" else [origin, v, r, team, look])


## A player threw: on the TV machine it's drawn right away and the host makes the real one.
func player_throw(p, origin: Vector3, v: Vector3, r: float, dmg: float, look: String = "") -> void:
	stat_add(p.index, "thrown", 1)
	if net.mode == "client":
		spawn_ball(origin, v, r, dmg, "p", p.index, true)
		net.send_action("throw", [origin, v, r, dmg], p.index)
	else:
		spawn_ball(origin, v, r, dmg, "p", p.index, false, look)


## Initial velocity for a lob from `from` that lands on `to` (flight time from the distance).
func lob_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var flight := clampf(from.distance_to(to) / speed, 0.35, 2.2)
	return (to - from) / flight + Vector3.UP * 0.5 * GRAVITY * flight


## VR aim assist (kids' arms get tired): a throw roughly towards a snowman (within 14 degrees) is bent
## onto a lob that reaches it at the same throwing speed, keeping a bit of the real throw.
func assist_aim(from: Vector3, v: Vector3, extra_deg: float = 0.0) -> Vector3:
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() < 0.5:
		return v
	var best_angle := deg_to_rad(14.0 + extra_deg)  # (AIM HELP gifts reach further)
	var best_pt := Vector3.ZERO
	var found := false
	var aims: Array = get_tree().get_nodes_in_group("snowmen")
	if orbs != null:
		aims = aims + orbs.orbs  # the pick orbs too (little ones hit their gift)
	for s in aims:
		if not is_instance_valid(s):
			continue
		if not (s is PickOrbs.Orb) and s.dead:
			continue
		var pt: Vector3 = s.global_position if s is PickOrbs.Orb else s.global_position + Vector3.UP * s.height * 0.5
		if not (s is PickOrbs.Orb):
			for bn in s.balloon_nodes:
				if bn.visible:
					pt = bn.global_position  # balloon snowmen: aim for the balloons
					break
		var to: Vector3 = pt - from
		to.y = 0.0
		if to.length() < 1.0 or to.length() > 30.0:
			continue
		var ang := flat.angle_to(to)
		if ang < best_angle:
			best_angle = ang
			best_pt = pt
			found = true
	if not found:
		return v
	var to2 := best_pt - from
	var hd := Vector2(to2.x, to2.z).length()
	var hspeed := maxf(flat.length(), 6.0)
	var flight := clampf(hd / hspeed, 0.15, 2.5)
	var ideal := Vector3(to2.x, 0.0, to2.z).normalized() * (hd / flight) + Vector3.UP * ((to2.y + 0.5 * GRAVITY * flight * flight) / flight)
	return v.lerp(ideal, 0.7)


## Called by every snowball each step. Returns true if it hit something (and should vanish).
## The host applies the damage; visual-only balls just splat.
func ball_step(b) -> bool:
	var p: Vector3 = b.global_position
	var r: float = b.radius
	var real: bool = not b.visual_only and net.mode != "client"
	if p.y <= r * 0.5:
		puff(Vector3(p.x, 0.05, p.z), Color(1, 1, 1), 6, 0.05)
		if b.team == "p" and real:
			if r >= MEGA_R * 0.9:
				_mega_splash(Vector3(p.x, 0.0, p.z), b.owner_index)
			else:
				director().on_miss(b.owner_index)
		elif r >= MEGA_R * 0.9:
			puff(Vector3(p.x, 0.2, p.z), Color(1, 1, 1), 30, 0.12)
		return true
	if b.team == "p":
		var oi := orbs.nearest_hit(p, r) if orbs != null and not orbs.orbs.is_empty() else -1
		if oi >= 0:  # a pick orb: the thrower takes it (the host decides)
			puff(p, orbs.color_of(oi), 12, 0.07)
			if real and b.owner_index >= 0 and b.owner_index < players.size():
				on_orb_hit(oi, players[b.owner_index])
			return true
		for s in get_tree().get_nodes_in_group("snowmen"):
			if s.dead:
				continue
			var bi: int = s.balloon_hit(p, r)
			if bi >= 0:
				if real:
					s.pop_balloon(bi)
					stat_add(b.owner_index, "pops", 1)
					director().on_hit(b.owner_index, p)
				return true
			if not s.hit_test(p, r):
				continue
			puff(p, Color(1, 1, 1), 10, 0.07)
			if real:
				_on_snowman_hit(s, b)
			elif r >= MEGA_R * 0.9:
				puff(p, Color(1, 1, 1), 30, 0.12)
			return true
		return false
	for pl in players:
		if pl.active and not pl.is_down and pl.lid_blocks(p, r):
			puff(p, Color(0.8, 0.9, 1.0), 10, 0.06)
			if real:
				pl.on_block()
				stat_add(pl.index, "blocked", 1)
				sound("zap", -6.0, 0.6)
				popup(p + Vector3.UP * 0.3, "BLOCKED!", Color(0.8, 0.9, 1.0))
			return true
	var si := seg_hit(p, r)
	if si >= 0:
		puff(p, Color(0.8, 0.9, 1.0), 8, 0.07)
		if real:
			damage_segment(si, b.damage * 0.6 * Gifts.team_armor(_party_gifts()))  # (WARM HAT gifts: the walls feel it less)
		return true
	for pl in players:
		if pl.active and not pl.is_down and pl.hit_test(p, r):
			puff(p, Color(0.8, 0.9, 1.0), 10, 0.07)
			if real:
				var v: Vector3 = b.vel
				pl.take_damage(b.damage, p - v.normalized() * 6.0)
			return true
	return false


func _on_snowman_hit(s, b) -> void:
	var who: int = b.owner_index
	if s.kind == "target" and not s.has_meta("tv") and who != 0:
		return  # the VR player's practice targets are theirs to knock over
	var mega: bool = b.radius >= MEGA_R * 0.9
	if mega:
		_mega_splash(s.global_position, who)
	if s.shield_blocks(b.vel):
		s.hit_shield(mega)
		stat_add(who, "hits", 1)
		if s.shield_hp > 0:
			director().hint("Their ICE SHIELD blocks flat throws - LOB a high one over it, or hit them from the side!", 4.0, "shield_tip")
			return
	director().on_hit(who, s.global_position + Vector3.UP * s.height)
	s.take_hit(b.damage, b.vel, who)
	sound("hit", -6.0, 1.3 if b.radius < 0.15 else 0.9)
	if who >= 0 and who < players.size():
		stat_add(who, "hits", 1)
		var p = players[who]
		if p.remote:
			net.event("hitmark", [who])
		else:
			p.on_ball_hit()
		# The VR sniper gets a little cheer for long throws.
		if p.vr or (who == 0 and net.mode == "host"):
			var dist: float = s.global_position.distance_to(p.global_position)
			if dist > 10.0 and not s.dead:
				popup(s.global_position + Vector3.UP * (s.height + 0.4), "SNIPE!", Color(1.0, 0.85, 0.4))


## A MEGA SNOWBALL landed: knocks every snowman nearby.
func _mega_splash(pos: Vector3, who: int) -> void:
	print("Mega splash by P%d" % (who + 1))
	puff(pos + Vector3.UP * 0.4, Color(1, 1, 1), 40, 0.14)
	net.event("burst", [pos + Vector3.UP * 0.4, Color(1, 1, 1), 40, 0.14])
	sound("thud", 0.0)
	popup(pos + Vector3.UP * 2.0, "MEGA SPLASH!", Color(0.7, 0.9, 1.0))
	for s in get_tree().get_nodes_in_group("snowmen"):
		if s.dead:
			continue
		var to: Vector3 = s.global_position - pos
		to.y = 0.0
		if to.length() < MEGA_SPLASH + s.radius():
			if s.shield_hp > 0:
				s.hit_shield(true)
			s.take_hit(MEGA_DMG * 0.5, to.normalized() * 8.0 if to.length() > 0.01 else Vector3.FORWARD, who)
	for p in players:
		if p.camera and not p.vr:
			p.shake = maxf(p.shake, 0.35)


## A glowing MEGA SNOWBALL to pick up (next throw is a giant one).
func drop_mega(pos: Vector3) -> void:
	if net.mode == "client":
		return
	for c in get_tree().get_nodes_in_group("cocoa"):
		if c.kind == "mega":
			return  # one at a time
	var c := CocoaScript.new()
	c.main = self
	c.kind = "mega"
	c.net_id = next_net_id()
	c.position = Vector3(pos.x, 0, pos.z)
	add_child(c)


func director() -> Node:
	if dir_node == null or not is_instance_valid(dir_node):
		dir_node = DirectorScript.new()
		dir_node.main = self
		add_child(dir_node)
	return dir_node


## The yeti stomps: everyone's view shakes.
func yeti_stomp(pos: Vector3) -> void:
	for p in players:
		if p.camera and not p.vr:
			p.shake = maxf(p.shake, 0.6)
		if p.vr:
			p.hand_l.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.2, 0.0)
			p.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.2, 0.0)
	popup(pos + Vector3.UP * 5.0, "STOMP!", Color(0.7, 0.85, 1.0))


# --- Snowmen and waves -------------------------------------------------------

func nearest_player(pos: Vector3):
	var best = null
	var best_d := INF
	for p in players:
		if p.is_down or not p.active:
			continue
		var dd: float = pos.distance_squared_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = p
	return best


func _nearest_seg(pos: Vector3) -> int:
	return posmod(roundi(atan2(pos.z, pos.x) / (TAU / SEGMENTS)), SEGMENTS)


func _spawn_snowman(kind: String, pos: Vector3, grace: float = 0.8) -> Node3D:
	var s := SnowmanScript.new()
	s.setup(kind, wave, self, _nearest_seg(pos))
	if SIMPLE_MODE and wave <= 2 and kind == "snowman":
		s.speed *= 0.55 if wave <= 1 else 0.8  # gentle start: slow waddlers
		if wave <= 1:
			s.throw_cd = 1.0e9  # wave 1: they don't throw yet
	if SIMPLE_MODE and kind != "target":
		var num := SiegeGen.mode_num(game_mode)
		s.speed *= float(num.speed)  # gentle: slower, softer; hard: quicker, harder (siegegen.gd MODE_NUM)
		s.hit_k = float(num.hit)
	s.net_id = next_net_id()
	s.spawn_grace = grace
	s.position = pos
	if kind == "yeti":
		s.max_hp *= 1.0 + 0.25 * extra_players()
		s.hp = s.max_hp
	add_child(s)
	director().on_snowman_spawned(kind)
	return s


func summon_minions(pos: Vector3, count: int, kind: String = "snowman") -> void:
	for i in count:
		var a := randf() * TAU
		_spawn_snowman(kind, pos + Vector3(cos(a), 0, sin(a)) * 2.5, 0.6)
	burst(pos + Vector3.UP * 2.0, Color(0.6, 0.85, 1.0), 20, 0.12)
	sound("wave", -4.0, 0.6)


func on_snowman_collapsed(s, who: int) -> void:
	var pos: Vector3 = s.global_position
	var pts: int = s.d.points
	score += pts
	if s.kind == "target":
		_on_target_down(s)
	if who >= 0 and who < players.size():
		stat_add(who, "felled", 1)
	var size: float = s.s
	if size > 1.5:
		sound("big_kill", 0.0, 1.6 / size)
	else:
		sound("kill", -4.0, 1.3)
	collapse_fx(pos, size, s.kind)
	popup(pos + Vector3.UP * (size * 2.4 + 0.3), "+%d" % pts, Color(1.0, 0.9, 0.6))
	if s.kind != "king" and s.kind != "yeti" and s.kind != "target" and randf() < (0.25 if s.kind == "giant" else (0.0 if SIMPLE_MODE else 0.03)):
		drop_mega.call_deferred(pos)
	for p in players:
		if p.camera and not p.vr:
			p.shake = maxf(p.shake, clampf(0.1 + size * 0.15 - p.global_position.distance_to(pos) * 0.01, 0.0, 0.6))
	if s.kind == "yeti":
		boss_hp = -1.0
		_show_center("THE YETI IS DOWN!", 2.5)
		sound("fanfare", 0.0)
		for i in 4:
			_drop_cocoa.call_deferred(pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	elif s.kind == "king":
		boss_hp = -1.0
		_show_center("THE SNOW KING MELTED!", 2.5)
		for i in 3:
			_drop_cocoa.call_deferred(pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	elif randf() < float(s.d.cocoa):
		_drop_cocoa.call_deferred(pos)


func _pick_kind() -> String:
	if SIMPLE_MODE:
		return _pick_simple_kind()
	var r := randf()
	if wave >= 3 and r < 0.1 + wave * 0.012:
		return "giant"
	if wave >= 2 and r < 0.34:
		return "sled"
	if wave >= 2 and r < 0.44:
		return "bunny"
	if wave >= 3 and r < 0.54:
		return "balloon"
	if wave >= 4 and r < 0.63:
		return "shield"
	return "snowman"


func _spawn_wave_snowman() -> void:
	if SIMPLE_MODE and not siege.is_empty():
		_spawn_planned()
		return
	var best_pos := Vector3.ZERO
	var best_d := -1.0
	for attempt in 3:
		var a := randf() * TAU
		var pos := Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 1.0)
		var dd := INF
		for p in players:
			dd = minf(dd, pos.distance_to(p.global_position))
		if dd > best_d:
			best_d = dd
			best_pos = pos
	var kind := _pick_kind()
	if kind == "bunny":
		var side := Vector3(best_pos.z, 0.0, -best_pos.x).normalized()
		for i in 3:
			_spawn_snowman("bunny", best_pos + side * (i - 1) * 1.1)
		return
	_spawn_snowman(kind, best_pos)


## Simple mode: the next snowman of this wave's seeded plan (siegegen.gd) walks in at its gate. A bigger
## party gets extra snowmen: the plan goes round again from its start. Sets the gap to the next one.
func _spawn_planned() -> void:
	var plan := SiegeGen.wave_plan(siege, wave)
	var spawns: Array = plan.spawns
	var sp: Array = spawns[wave_spawned % spawns.size()]
	wave_spawned += 1
	var pos := SiegeGen.spawn_pos(plan, sp)
	var kind := String(sp[1])
	if kind == "bunny":
		var side := Vector3(pos.z, 0.0, -pos.x).normalized()
		for i in 3:
			_spawn_snowman("bunny", pos + side * (i - 1) * 1.1)
	else:
		_spawn_snowman(kind, pos)
	var nx: Array = spawns[wave_spawned % spawns.size()]
	spawn_timer = float(nx[0]) / (1.0 + 0.15 * extra_players())
	if wave_spawned == maxi(1, to_spawn / 2):
		_give_megas(2)  # MEGA x2 gifts: another one halfway


## Simple mode without a siege (never in play; kept for old saves of the code): mostly plain snowmen.
func _pick_simple_kind() -> String:
	if simple_new_left > 0 and (randf() < 0.5 or to_spawn <= simple_new_left):
		simple_new_left -= 1
		return SIMPLE_NEW.get(wave, "snowman")
	var pool: Array[String] = []
	for w in SIMPLE_NEW:
		if wave > w:
			pool.append(SIMPLE_NEW[w])
	if pool.is_empty() or randf() < 0.55:
		return "snowman"
	return pool.pick_random()


func _simple_boss() -> String:
	return SiegeGen.boss_for(wave)


func _start_simple_wave() -> void:
	wave += 1
	in_break = false
	if siege.is_empty():
		_start_siege()
	var plan := SiegeGen.wave_plan(siege, wave)
	to_spawn = int((plan.spawns as Array).size() * (1.0 + 0.22 * extra_players()))
	wave_spawned = 0
	simple_new_left = 0
	spawn_timer = float((plan.spawns as Array)[0][0])
	trick = (siege.get("tricks", {}) as Dictionary).get(wave, {}).duplicate(true)
	trick_phase = "wait" if not trick.is_empty() else ""
	trick_t = float(trick.get("at", 0.0))
	var nk := SiegeGen.new_kind(siege, wave)
	if nk != "":
		_story_for_all("Look out!", KIND_PICS.get(nk, "snowman"), Color(0.6, 0.85, 1.0))
	_give_megas(1)
	print("Wave %d started (simple, %d snowmen)" % [wave, to_spawn])
	sound("wave")
	var boss := _simple_boss()
	director().on_wave_started(wave, boss)
	var head := "WAVE %d!" % wave
	if boss != "":  # (the plan already sends half as many snowmen with a boss)
		_spawn_snowman(boss, SiegeGen.boss_pos(plan), 1.5)
		head = "THE YETI!" if boss == "yeti" else "SNOW KING!"
		sound("roar", 0.0, 0.7 if boss == "yeti" else 1.0)
	_show_center(head, 2.0)


func _end_simple_wave() -> void:
	in_break = true
	break_timer = 4.0
	for i in SEGMENTS:
		seg_hp[i] = SEG_MAX  # fresh snow on every wall
	director().on_wave_cleared(wave)
	sound("clear")
	if wave >= Rink.STAY_WAVES:
		_friend_stays()
	if wave == SIMPLE_FINALE and not director().won:
		director().won = true
		break_timer = 10.0
		sound("fanfare", 0.0)
		print("VICTORY: the village is safe (simple)")
		_show_center("VICTORY!", 6.0)
		_story_for_all("Thank you!", "polarbear", SiegeGen.WANT_COLORS[int(siege.get("want", 0))])
		_story_for_all("My %s is safe!" % SiegeGen.WANT_NAMES[int(siege.get("want", 0))].to_lower(), SiegeGen.WANTS[int(siege.get("want", 0))], SiegeGen.WANT_COLORS[int(siege.get("want", 0))])
		_build_igloo()
		_log_run("victory")
		return
	_show_center("HOORAY!", 2.0)
	print("Wave %d cleared, fort %d%%" % [wave, int(fort_fraction() * 100.0)])
	_begin_pick("gift")


# --- Simple mode: target practice ----------------------------------------------

## Host / local: one glowing target at a time for the VR player, one for each TV player. The snowmen
## come once they're all down (a solo VR player gets a few extra targets while the TV is away).
func _update_practice(delta: float) -> void:
	practice_t += delta
	var crew_ready: bool = net.mode != "host" or net.connected
	var vr_on: bool = players[0].vr and players[0].active
	var vr_alive := false
	var tv_alive := false
	for s in get_tree().get_nodes_in_group("snowmen"):
		if s.kind == "target" and not s.dead:
			if s.has_meta("tv"):
				tv_alive = true
			else:
				vr_alive = true
	if vr_on and not vr_alive and (vr_hits < VR_PRACTICE or not crew_ready):
		vr_target_t -= delta
		if vr_target_t <= 0.0:
			vr_target_t = 0.8
			_spawn_vr_target()
	for p in players:
		if p.active and not p.vr and not p.ghost and (not p.remote or net.connected) and not tv_given.has(p.index):
			tv_given[p.index] = true
			_spawn_tv_target(p)
			tv_alive = true
	var vr_done := not vr_on or vr_hits >= VR_PRACTICE
	if crew_ready and ((vr_done and not tv_alive) or practice_t > 45.0):
		_end_practice()
	elif not crew_ready and vr_done and practice_t > 40.0:
		_end_practice()  # solo VR: the snowmen come anyway (TV players can still drop in)


func _spawn_vr_target() -> void:
	var cam: Node3D = players[0].xr_camera
	var head := cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var ang: float = [0.0, 0.55, -0.55][vr_hits % 3]
	var dist: float = [3.0, 3.6, 4.2][vr_hits % 3]
	_place_target(Vector3(head.x, 0.0, head.z) + fwd.rotated(Vector3.UP, ang) * dist, head, false)


func _spawn_tv_target(p) -> void:
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3.FORWARD
	_place_target(p.global_position + fwd * 4.5, p.global_position, true)


func _place_target(pos: Vector3, look_from: Vector3, tv: bool) -> void:
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > FORT_RADIUS - 1.2:
		flat = flat.normalized() * (FORT_RADIUS - 1.2)
	pos = Vector3(flat.x, 0.0, flat.y)
	var s := _spawn_snowman("target", pos, 0.5)
	var d := look_from - pos
	s.rotation.y = atan2(-d.x, -d.z)
	if tv:
		s.set_meta("tv", true)
	sound("pickup", -6.0, 1.4)
	burst(pos + Vector3.UP * 1.0, Color(1.0, 0.85, 0.4), 12, 0.07)


func _on_target_down(s) -> void:
	sound("pickup", -2.0, 1.2)
	burst(s.global_position + Vector3.UP * 1.6, Color(1.0, 0.85, 0.35), 18, 0.08)
	if not s.has_meta("tv"):
		vr_hits += 1
		cue_did(players[0], "throw")
		vr_target_t = 0.8
	print("Practice target down (VR %d)" % vr_hits)


func _end_practice() -> void:
	practice = false
	for s in get_tree().get_nodes_in_group("snowmen"):
		if s.kind == "target":
			puff(s.global_position + Vector3.UP, Color(1, 1, 1), 16, 0.08)
			net.event("burst", [s.global_position + Vector3.UP, Color(1, 1, 1), 16, 0.08])
			s.remove_from_group("snowmen")
			s.queue_free()
	in_break = true
	break_timer = 2.0
	if ghost_hand:
		ghost_hand.hide_demo()
	print("Practice over (VR hits %d, %.0f s)" % [vr_hits, practice_t])
	if SIMPLE_MODE and wave == 0 and not Engine.has_meta("sb_mode_set") and net.forced_mode("SB_MODE") == "":
		_begin_pick("mode")
	else:
		_skip_to_env_wave()


## VR practice: the ghost hand scoops and throws at the current target until the VR player has hit two.
func _update_ghost_hand(delta: float) -> void:
	var p = players[0]
	if not p.vr:
		return
	var aim := Vector3.ZERO
	if practice and not cue_learned(p, "throw") and not p.holding:
		for s in get_tree().get_nodes_in_group("snowmen"):
			if s.kind == "target" and not s.has_meta("tv") and not s.dead:
				aim = s.global_position + Vector3.UP * 1.0
	if ghost_hand == null:
		if aim == Vector3.ZERO:
			return
		ghost_hand = GhostHand.new()
		ghost_hand.layers = p.viewmodel_layer()
		add_child(ghost_hand)
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		sm.radial_segments = 10
		sm.rings = 5
		ghost_ball = ghost_hand.prop(sm, Color(1.0, 1.0, 1.0, 0.6), false)
	_ghost_demo(aim != Vector3.ZERO, p.xr_camera.global_position, aim, delta)


## The ghost hand's loop: reach down to the snow, squeeze (a snowball appears), lift it back over the
## shoulder, swing towards the glowing target (aim) and let go (the ghost snowball flies off). It fades
## in after the thrower has been idle for a moment. head: the headset position.
func _ghost_demo(want: bool, head: Vector3, aim: Vector3, delta: float) -> void:
	if not ghost_hand.gate(want, delta, 1.5):
		return
	var t := ghost_hand.play("throw", 3.2, delta)
	var fwd := Vector3(aim.x - head.x, 0.0, aim.z - head.z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var feet_y := maxf(head.y - 1.15, 0.25)
	var low := head + fwd * 0.4 + right * 0.2 + Vector3.UP * (feet_y - head.y)  # down at the snow
	var back := head + right * 0.25 - fwd * 0.12 + Vector3.UP * 0.02  # wound up beside the ear
	var out := head + right * 0.15 + fwd * 0.55 + Vector3.UP * 0.12  # arm out towards the target
	var k := GhostHand.track([[0.0, low + Vector3.UP * 0.35], [0.7, low, 0.0], [1.0, low, 1.0], [1.8, back, 1.0],
		[2.15, out, 1.0, 0.4], [2.35, out, 0.0]], t)  # ...swing! let go
	var holding := t > 0.85 and t < 2.15
	if t >= 2.15 and ghost_fly_vel == Vector3.ZERO:
		ghost_fly_from = out + fwd * 0.08
		ghost_fly_vel = (aim - ghost_fly_from).normalized() * 9.0 + Vector3.UP * 2.0
	ghost_hand.set_alpha(ghost_hand.fade(2.85))
	# Palm down, fingers pointing at the target.
	ghost_hand.pose(Transform3D(UiKit.aim(fwd, Vector3.UP), k.p), k.grip)
	if holding:
		ghost_fly_vel = Vector3.ZERO
		ghost_ball.visible = true
		ghost_ball.global_position = k.p + Vector3.DOWN * 0.03 - ghost_hand.hand.global_basis.z * 0.05
	elif ghost_fly_vel != Vector3.ZERO and t >= 2.15:
		var ft := t - 2.15
		ghost_ball.visible = ft < 0.9
		ghost_ball.global_position = ghost_fly_from + ghost_fly_vel * ft + Vector3.DOWN * 4.0 * ft * ft
	else:
		ghost_ball.visible = false


## Simple mode picture cues: a player has done `key` once more ("throw", "turn"); its cue goes after two.
func cue_did(p, key: String) -> void:
	var done: Dictionary = p.get_meta("cue_done", {})
	done[key] = int(done.get(key, 0)) + 1
	p.set_meta("cue_done", done)


func cue_learned(p, key: String) -> bool:
	var done: Dictionary = p.get_meta("cue_done", {})
	return int(done.get(key, 0)) >= 2


## Simple mode: the walls slowly snow back up by themselves (no packing rules to learn).
func _regrow_walls(delta: float) -> void:
	var rate := 1.5 + Gifts.team_walls(_party_gifts())  # (WALLS gifts: faster)
	for i in SEGMENTS:
		seg_hp[i] = minf(SEG_MAX, seg_hp[i] + rate * delta)


func _start_wave() -> void:
	if SIMPLE_MODE:
		_start_simple_wave()
		return
	wave += 1
	in_break = false
	to_spawn = int((4 + wave * 3) * (1.0 + 0.22 * extra_players()))
	spawn_timer = 0.5
	print("Wave %d started" % wave)
	sound("wave")
	if wave == 3:
		create_tween().tween_property(help_label, "modulate:a", 0.0, 1.0)
	var boss := ""
	if wave == FINALE_WAVE:
		boss = "yeti"
	elif wave % BOSS_EVERY == 0:
		boss = "king" if (wave / BOSS_EVERY) % 2 == 1 or wave < FINALE_WAVE else "yeti"
	director().on_wave_started(wave, boss)
	if boss != "":
		to_spawn /= 2
		var a := randf() * TAU
		_spawn_snowman(boss, Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 1.0), 1.5)
		if boss == "yeti" and wave == FINALE_WAVE:
			_show_center("FINAL WAVE!\nTHE YETI IS COMING!", 2.5)
			sound("roar", 0.0, 0.7)
		elif boss == "yeti":
			_show_center("WAVE %d\nTHE YETI IS BACK!" % wave, 2.0)
		else:
			_show_center("WAVE %d\nTHE SNOW KING APPROACHES!" % wave, 2.0)
	elif wave < FINALE_WAVE:
		_show_center("WAVE %d of %d" % [wave, FINALE_WAVE], 1.4)
	else:
		_show_center("WAVE %d\nENDLESS" % wave, 1.4)


func _end_wave() -> void:
	if SIMPLE_MODE:
		_end_simple_wave()
		return
	in_break = true
	break_timer = 5.0
	for i in SEGMENTS:
		seg_hp[i] = minf(SEG_MAX, seg_hp[i] + 25.0)
	for p in players:
		if not p.active:
			continue
		if p.is_down:
			p.revive(0.5)
		else:
			p.heal(30.0)
	var upgrade: String = director().on_wave_cleared(wave)
	if wave == FINALE_WAVE and not director().won:
		director().won = true
		break_timer = 14.0
		score += 2000
		sound("fanfare", 0.0)
		print("VICTORY: the village is safe (score %d)" % score)
		_show_center("VICTORY!\nThe YETI is beaten and the village is safe!\n+2000\n\n%s\n\nEndless snowball fight next…" % director().awards_text(), 13.0)
		return
	_show_center("WAVE %d CLEARED!\nThe fort gets a fresh layer of snow%s" % [wave, upgrade], 2.6)
	sound("clear")
	print("Wave %d cleared, score %d, fort %d%%" % [wave, score, int(fort_fraction() * 100.0)])


func _drop_cocoa(pos: Vector3) -> void:
	if SIMPLE_MODE:
		return  # no warmth to top up
	if get_tree().get_nodes_in_group("cocoa").size() >= 5 + extra_players():
		return
	var c := CocoaScript.new()
	c.main = self
	c.net_id = next_net_id()
	c.position = Vector3(pos.x, 0, pos.z)
	add_child(c)


func _update_cocoa(delta: float) -> void:
	if not in_break:
		cocoa_timer -= delta
		if cocoa_timer <= 0.0:
			cocoa_timer = randf_range(14.0, 20.0) / (1.0 + 0.2 * extra_players())
			var a := randf() * TAU
			_drop_cocoa(Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 4.5))
	for c in get_tree().get_nodes_in_group("cocoa"):
		if c.is_queued_for_deletion():
			continue
		var at: Vector3 = c.grab_point()
		for p in players:
			if not p.active or p.is_down:
				continue
			var got := false
			if p.vr:
				got = p.hand_l.global_position.distance_to(at) < 0.45 or p.hand_r.global_position.distance_to(at) < 0.45 \
					or Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < 0.8
			else:
				got = Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < 1.1
			if got and c.kind == "mega":
				if p.mega:
					continue
				p.mega = true
				if p.vr:
					p.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.15, 0.0)
				burst(at, Color(0.7, 0.9, 1.0), 20, 0.09)
				sound("pickup", 0.0, 0.6)
				popup(at + Vector3.UP * 0.8, "MEGA SNOWBALL!", Color(0.7, 0.9, 1.0))
				director().hint("MEGA SNOWBALL! Your next throw is GIANT and splashes every snowman nearby!", 4.0, "mega")
				c.queue_free()
				break
			if got:
				p.heal(45.0)
				if p.vr:
					p.hand_l.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.1, 0.0)
				stat_add(p.index, "cocoa", 1)
				burst(at, Color(1.0, 0.7, 0.4), 14, 0.07)
				sound("pickup", -2.0, 0.9)
				popup(at + Vector3.UP * 0.8, "COCOA! +WARMTH", Color(1.0, 0.75, 0.45))
				c.queue_free()
				break


func on_player_frozen(p) -> void:
	popup(p.global_position + Vector3.UP * 2.2, "P%d FROZE!" % (p.index + 1), Color(0.6, 0.85, 1.0))


func stat_add(who: int, key: String, amount: float) -> void:
	if who < 0 or who > MAX_TV_PLAYERS:
		return
	var st := stats_for(who)
	st[key] = st.get(key, 0.0) + amount


func stats_for(who: int) -> Dictionary:
	while stats.size() <= who:
		stats.append({})
	return stats[who]


## How many players (VR + TV) are in the game right now.
func party_size() -> int:
	var n := 0
	for p in players:
		if p.active:
			n += 1
	return n


## Extra players beyond the classic VR + 2 TV players: used to scale the waves.
func extra_players() -> int:
	return clampi(party_size() - 3, 0, 4)


func boss_text() -> String:
	if boss_hp < 0.0:
		return ""
	return "%s %d%%" % [boss_name if boss_name != "" else "SNOW KING", int(boss_hp * 100.0)]


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_ensure_party()
	_update_fort_visuals(delta)
	_update_vr_center()
	_update_vr_hurt(delta)
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -17.0
	if music.has_method("play_track"):
		music.play_track(1 if boss_hp >= 0.0 else maxi(wave - 1, 0) / 3)
	director().tick(delta)
	_update_story(delta)
	_update_slides(delta)
	siege_t += delta
	if props:
		props.tick(delta)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	_check_join(delta)
	if net.mode == "client":
		seats.sync()
		seats.request_joins(delta)
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		var vr_restart: bool = players[0].vr_trigger_held()
		if game_over_time > 1.5 and (_restart_pressed() or vr_restart or (SIMPLE_MODE and game_over_time > 7.0)):
			get_tree().reload_current_scene()
		return
	if SIMPLE_MODE:
		_update_ghost_hand(delta)
		if practice:
			_update_practice(delta)
			return
		_regrow_walls(delta)
		_trick_tick(delta)
		if pick_stage != "":
			_pick_tick(delta)
			return  # the orbs hold the game until everyone has picked (or the time runs out)
	if net.mode == "host" and not net.connected and not SIMPLE_MODE:
		if wave == 0:
			director().howto()  # the VR player reads how to play while waiting
		return  # hold the waves until a TV player joins
	if wave == 0:
		director().howto()
	_update_cocoa(delta)
	boss_hp = -1.0
	for s in get_tree().get_nodes_in_group("snowmen"):
		if (s.kind == "king" or s.kind == "yeti") and not s.dead:
			boss_hp = maxf(0.0, s.hp / s.max_hp)
			boss_name = "THE YETI" if s.kind == "yeti" else "SNOW KING"
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
	elif to_spawn > 0:
		spawn_timer -= delta
		var alive := get_tree().get_nodes_in_group("snowmen").size()
		var extra := extra_players()
		if spawn_timer <= 0.0 and alive < 6 + wave + extra * 2:
			spawn_timer = maxf(0.45, (1.8 - wave * 0.1) / (1.0 + 0.15 * extra))
			_spawn_wave_snowman()  # (simple mode: the plan sets the next gap)
			to_spawn -= 1
	elif get_tree().get_nodes_in_group("snowmen").is_empty():
		_end_wave()
	var all_down := true
	for p in players:
		if p.active and not p.is_down:
			all_down = false
	if all_down:
		_on_game_over("EVERYONE FROZE SOLID!")
	elif fort_fraction() <= 0.0:
		_on_game_over("THE FORT FELL!")


func _on_game_over(reason: String) -> void:
	game_over = true
	game_over_time = 0.0
	sound("gameover")
	print("Game over (%s): wave %d, score %d" % [reason, wave, score])
	if SIMPLE_MODE:
		_show_center("OH NO!", 0.0)  # it starts again by itself
		if net.mode != "client":
			_build_igloo()
			_log_run({"THE FORT FELL!": "fort", "EVERYONE FROZE SOLID!": "frozen"}.get(reason, "ended"))
		return
	var best := _load_best()
	var best_line := "Best: wave %d  ·  score %d" % [best.wave, best.score]
	if score > int(best.score):
		best_line = "NEW BEST SCORE!  (previous %d)" % best.score
		_save_best(wave, score)
	var saved := "The village was saved!  ·  " if director().won else ""
	_show_center("%s\nWave %d  ·  Score %d\n%s%s\n\n%s\n\nPress A / Enter (VR: trigger) to play again" % [reason, wave, score, saved, best_line, director().awards_text()], 0.0)


func _load_best() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load("user://snowball_blitz_best.cfg")
	return {"wave": cfg.get_value("best", "wave", 0), "score": cfg.get_value("best", "score", 0)}


func _save_best(best_wave: int, best_score: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "wave", best_wave)
	cfg.set_value("best", "score", best_score)
	cfg.save("user://snowball_blitz_best.cfg")


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
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


# --- Players and views -------------------------------------------------------

## How many player nodes this mode has: the VR player + six TV players networked, six in split screen.
func _player_count(mode: String) -> int:
	return MAX_TV_PLAYERS + 1 if mode != "local" else MAX_TV_PLAYERS


func _spawn_spot(i: int, mode: String) -> Vector3:
	var tv: Array[Vector3] = [Vector3(-2.2, 0, 2.6), Vector3(2.2, 0, 2.6), Vector3(0, 0, 3.6), Vector3(-3.6, 0, 0.8),
		Vector3(3.6, 0, 0.8), Vector3(0, 0, -2.8)]
	if mode == "local":
		if i == 0:
			return Vector3(-2.0, 0, 2.6)
		if i == 1:
			return Vector3(2.0, 0, 2.6)
		return tv[clampi(i, 0, tv.size() - 1)]
	if i == 0:
		return Vector3.ZERO
	return tv[clampi(i - 1, 0, tv.size() - 1)]


## Creates any missing player nodes (lazily, so a hot reload of an older game grows the party too).
## Networked: VR player + TV players 2-7. Local split screen: players 1-6. As before, only the first
## two start in the game; the others wait (inactive) until someone presses A / Start on a controller.
func _build_players(mode: String) -> void:
	for i in range(players.size(), _player_count(mode)):
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		p.main = self
		p.remote = mode == "host" and i >= 1
		p.ghost = mode == "client" and i == 0
		if i == 0 and (mode == "local" or (mode == "host" and not net.has_vr)):
			p.mouse_look = true  # local P1 / a flat host's own player (no VR)
		elif mode != "local" and i == 2:
			p.key_set = 0
			p.mouse_look = true
		elif i >= 2:
			p.key_set = -2  # extra players are controller-only
		p.position = _spawn_spot(i, mode)
		add_child(p)
		players.append(p)
		if i >= 2:
			p.set_active(false)


func _is_local_tv(p) -> bool:
	return not p.remote and not p.ghost and not p.vr


## Lazily grows the party / views / input hook (safe to call every frame).
func _ensure_party() -> void:
	if join_listener == null or not is_instance_valid(join_listener):
		join_listener = JoinInputScript.new()
		join_listener.main = self
		add_child(join_listener)
	if players.size() < _player_count(net.mode):
		_build_players(net.mode)
		_ensure_views()
		_sync_view_visibility()


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.6
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 throws snowballs in VR")
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
		if mode == "local":
			_build_flat_window(players[1])
	elif OS.has_environment("BOT_VR") and mode != "client":
		# Test bots: the real VR code with XR nodes the bot moves by hand (no headset, no extra window).
		print("BOT_VR: fake VR snowball thrower")
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		origin.add_child(left)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		origin.add_child(right)
		preload("res://core/vr_rig.gd").fake_stand(cam, left, right, 1.0)  # the standard fake player (BOT_VR_SEATED / BOT_VR_EYE)
		players[0].attach_xr(origin, cam, left, right)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: split screen")
	_ensure_views()
	_sync_view_visibility()


## A split-screen view for every TV player on this machine, in a grid (hidden until they join).
func _ensure_views() -> void:
	if view_grid == null:
		var layer := CanvasLayer.new()
		layer.layer = -1
		add_child(layer)
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.05, 0.1)
		layer.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view_grid = GridContainer.new()
		view_grid.add_theme_constant_override("h_separation", 4)
		view_grid.add_theme_constant_override("v_separation", 4)
		layer.add_child(view_grid)
		view_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for p in players:
		if not _is_local_tv(p):
			continue
		if p.has_meta("view"):
			var old: Control = p.get_meta("view")
			if is_instance_valid(old) and old.get_parent() != view_grid and old is SubViewportContainer:
				old.reparent(view_grid, false)  # views made by an older version of this script
			continue
		if p.camera != null:
			continue  # e.g. player 2's own window when VR runs without a TV machine
		if players[0].vr and p.index >= 2:
			continue  # VR without a TV machine: only player 2's window (no screen for more)
		_build_view(p)


func _build_view(p) -> void:
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_grid.add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(vp)
	var cam := Camera3D.new()
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
	if net.mode == "client":
		if ghost_cam == null:
			_build_ghost_mirror()
		_add_bubble(hud, mirror_vp, PLAYER_COLORS[0])


func _sync_view_visibility() -> void:
	for p in players:
		if p.has_meta("view"):
			var v: Control = p.get_meta("view")
			v.visible = p.active and _is_local_tv(p)
	_layout_views()


## 1 view full screen, 2 side by side, 3-4 as 2x2, 5-6 as 3x2. More views: lower 3D resolution.
func _layout_views() -> void:
	if view_grid == null:
		return
	var shown: Array[SubViewportContainer] = []
	for c in view_grid.get_children():
		var svc := c as SubViewportContainer
		if svc != null and svc.visible:
			shown.append(svc)
	var n := shown.size()
	view_grid.columns = 1 if n <= 1 else (2 if n <= 4 else 3)
	var scale_3d := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for svc in shown:
		for c in svc.get_children():
			var vp := c as SubViewport
			if vp != null:
				vp.scaling_3d_scale = scale_3d
				vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
	for c in get_children():
		var sun := c as DirectionalLight3D
		if sun != null and sun.shadow_enabled:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if n <= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 45.0 if n <= 4 else 30.0
		var we := c as WorldEnvironment
		if we != null and we.environment != null:
			if not we.has_meta("base_glow"):
				we.set_meta("base_glow", we.environment.glow_enabled)
			we.environment.glow_enabled = bool(we.get_meta("base_glow")) and n <= 4


## Low-res copy of the VR view, recorded by gdev (group gdev_capture) so others can watch.
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


## Client: a camera that follows the VR player's replicated head, for the bubble view.
func _build_ghost_mirror() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
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


## Round picture-in-picture of the VR player's view on the TV player's HUD.
func _add_bubble(hud: Control, source: SubViewport, color: Color) -> void:
	var bubble := TextureRect.new()
	bubble.texture = source.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = BUBBLE_SHADER
	m.set_shader_parameter("ring_color", color)
	bubble.material = m
	hud.add_child(bubble)
	bubble.size = Vector2(260, 260)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 30)
	var tag := Label.new()
	tag.text = "P1 (VR)"
	tag.add_theme_font_size_override("font_size", 24)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_color_override("font_color", color)
	bubble.add_child(tag)
	tag.position = Vector2(90, 262)


## VR without a TV machine: player 2 gets a window on this device.
func _build_flat_window(p) -> void:
	var win := Window.new()
	win.title = "Snowball Blitz - Player 2"
	win.size = Vector2i(1920, 1080)
	win.world_3d = get_world_3d()
	win.msaa_3d = Viewport.MSAA_2X
	win.content_scale_size = Vector2i(1920, 1080)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.scaling_3d_scale = 0.6
	add_child(win)
	var cam := Camera3D.new()
	win.add_child(cam)
	cam.current = true
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	win.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud
	if mirror_vp:
		_add_bubble(hud, mirror_vp, PLAYER_COLORS[0])


## Controllers fill these players in order at the start (as before): networked P2 then P3,
## local split screen P2 then P1. Any further controller joins with A / Start.
func _base_slots() -> Array[int]:
	var slots: Array[int] = []
	if net.mode == "client":
		slots = [1, 2]
	elif net.mode == "local" and players.size() > 1:
		slots.append(1)
		if not players[0].vr:
			slots.append(0)
	elif net.mode == "host" and not players.is_empty() and not players[0].vr:
		slots.append(0)  # flat host (no VR): the host's own player
	return slots


func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	var slots := _base_slots()
	for i in slots.size():
		var slot: int = slots[i]
		players[slot].joy = pads[i] if i < pads.size() else -1
		if i < pads.size():
			pad_memory[pads[i]] = slot


func _player_with_pad(device: int):
	for p in players:
		if p.joy == device and _is_local_tv(p):
			return p
	return null


## Each controller belongs to exactly one player (by device id). Unplugging a controller-only
## player makes them leave; plugging the same controller back in rejoins them.
func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play:
		return
	if connected:
		if _player_with_pad(device) != null:
			return
		var back: int = pad_memory.get(device, -1)
		if back >= 0 and back < players.size() and _is_local_tv(players[back]) and players[back].joy < 0:
			players[back].joy = device
			print("Controller %d reconnected: P%d" % [device, back + 1])
			if not players[back].active and not players[back].has_keyboard():
				_request_join(back)
			return
		for slot in _base_slots():
			if players[slot].joy < 0:
				players[slot].joy = device
				pad_memory[device] = slot
				return
		print("Controller %d connected: press A / Start to join" % device)
	else:
		var p = _player_with_pad(device)
		if p == null:
			return
		p.joy = -1
		pad_memory[device] = p.index
		print("Controller %d disconnected (P%d)" % [device, p.index + 1])
		if p.active and not p.has_keyboard():
			_request_leave(p.index)


## The first TV player slot that's free for a new controller, or -1 when the party is full.
func _free_slot() -> int:
	for p in players:
		if _is_local_tv(p) and not p.active and p.joy < 0 and p.camera != null:
			return p.index
	return -1


## Called by join_input.gd: A / Start on a controller that isn't playing yet joins the game.
func handle_join_input(event: InputEvent) -> bool:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or not ready_to_play or game_over or get_tree().paused or net.mode == "host":
		return false
	if b.button_index != JOY_BUTTON_A and b.button_index != JOY_BUTTON_START:
		return false
	var p = _player_with_pad(b.device)
	if p != null:
		if p.active:
			return false
		_request_join(p.index)
		return true
	var slot := _free_slot()
	if slot < 0:
		return false
	players[slot].joy = b.device
	pad_memory[b.device] = slot
	print("Controller %d is now P%d" % [b.device, slot + 1])
	_request_join(slot)
	return true


## A waiting player with a keyboard or controller joins by holding throw (as P3 always could).
func _check_join(_delta: float) -> void:
	if game_over or net.mode == "host":
		return
	for p in players:
		if p.active or not _is_local_tv(p) or p.camera == null or p.has_meta(ClassicSeats.WANT):
			continue
		if (p.joy >= 0 or p.has_keyboard()) and p._throw_held():
			_request_join(p.index)


func _request_join(i: int) -> void:
	if net.mode == "client":
		players[i].set_meta(ClassicSeats.WANT, true)  # seats.request_joins asks the host until it's ours
		seats.ask_soon()
	else:
		_activate_player(i)


func _request_leave(i: int) -> void:
	if net.mode == "client":
		net.send_action("leave", [], i)
	else:
		_deactivate_player(i)


## Test hooks: spawn a kind, start a weather event, jump to a wave, grant every fort upgrade.
func debug_spawn(kind: String) -> void:
	if net.mode == "client":
		return
	var a := randf() * TAU
	var at := Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 1.0)
	if kind == "bunny":
		for i in 3:
			_spawn_snowman("bunny", at + Vector3(i - 1, 0, 0))
	else:
		_spawn_snowman(kind, at)


func debug_event(ev: String) -> void:
	director().start_event(ev)


func debug_skip_to_wave(n: int) -> void:
	if net.mode == "client":
		return
	for sm in get_tree().get_nodes_in_group("snowmen"):
		sm.remove_from_group("snowmen")
		sm.queue_free()
	to_spawn = 0
	if practice:
		_end_practice()
	if pick_stage != "":
		_finish_pick()
	wave = n - 1
	in_break = true
	break_timer = 0.5


func debug_upgrades() -> void:
	for w in director().UPGRADES:
		var u: Array = director().UPGRADES[w]
		if not director().upgrades.has(u[0]):
			director().upgrades.append(u[0])


## Test hook (bots / scripted demos): TV player i joins as if they pressed A on a new controller.
func debug_join(i: int) -> void:
	if i >= 0 and i < players.size() and _is_local_tv(players[i]) and not players[i].active:
		_request_join(i)


## Host / local: a player joins (fresh and warm).
func _activate_player(i: int) -> void:
	if i < 0 or i >= players.size() or players[i].active:
		return
	var p = players[i]
	p.set_active(true)
	p.hp = PlayerScript.MAX_HP
	if p.is_down:
		p.is_down = false
		p._apply_down_pose(false)
	p.invuln_t = 2.0
	if p.remote:
		p.net_started = false  # snap to the TV player's next reported position
	elif not p.vr:
		p.global_position = _spawn_spot(i, net.mode)
	_show_center(("PLAYER %d!" % (i + 1)) if SIMPLE_MODE else Who.joined(Who.seat(self, i)), 1.5)
	print("Net: player %d joined the game (%d playing)" % [i + 1, party_size()])
	on_player_activity_changed(p)


## Host / local: a player leaves (their controller was unplugged).
func _deactivate_player(i: int) -> void:
	if i < 0 or i >= players.size() or not players[i].active:
		return
	var p = players[i]
	p.set_active(false)
	p.charging = false
	p.repairing = false
	if p.is_down:
		p.is_down = false
		p._apply_down_pose(false)
	if not SIMPLE_MODE:
		_show_center(Who.left(Who.seat(self, i)), 1.5)
	print("Net: player %d left the game (%d playing)" % [i + 1, party_size()])
	on_player_activity_changed(p)


func on_player_activity_changed(p) -> void:
	_sync_view_visibility()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ----------------------------

func on_client_joined() -> void:
	if not seats.first_machine():
		return  # another machine: its players join when they ask ("join")
	if SIMPLE_MODE:
		sound("pickup", 0.0, 0.8)
		_show_center("HELLO TV!", 1.5)
		return
	# (no "they joined" line: each seat's join says WHO, core/who.gd)


## Host: one machine left: only its players leave (and their seats become free).
func on_machine_left(peer: int) -> void:
	seats.machine_left(peer)


## TV machine: seat p is another machine's now (on: mirrored from the snapshots, no view here) or ours again.
func _seat_ghost(p, on: bool) -> void:
	p.net_started = false  # snap to the first mirrored position, no glide
	p.charging = false
	if not on:
		_ensure_views()
	on_player_activity_changed(p)


## Host: the LAST machine left (multi_machine games get this only then).
func on_client_left() -> void:
	seats.all_left()  # each machine asks for its players again when it reconnects
	if SIMPLE_MODE:
		return  # keep playing; they can drop back in
	_show_center(Who.left(net.last_left_name) + " - waiting for them to come back…", 0.0)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	index = seats.host_action(action, args, index)  # many machines: who drives which seat (core/classic_seats.gd)
	if index < 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"throw":
			if not p.active or p.is_down:
				return
			stat_add(index, "thrown", 1)
			var r: float = clampf(args[2], 0.05, 0.3)
			var dmg: float = clampf(args[3], 0.5, 3.0)  # (BIG BALLS gifts: up to 1.6 x 1.6)
			if p.mega and float(args[2]) >= MEGA_R * 0.9:
				p.mega = false
				r = MEGA_R
				dmg = MEGA_DMG
			spawn_ball(args[0], args[1], r, dmg, "p", index)
		"repair":
			if p.active and not p.is_down:
				repair_segment(int(args[0]), clampf(float(args[1]), 0.0, 8.0), index)
		"join":
			_activate_player(index)
		"leave":
			_deactivate_player(index)
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, Who.paused_by(net.machine_name_of(net.sender_peer())))
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	if SIMPLE_MODE:
		who = ""  # no explaining sentence: just PAUSED
	var title := ("PAUSED\n" + who) if who != "" else "PAUSED"
	_show_center(title if paused else "", 0.0, false)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Press the menu button to resume")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		var st := [p.global_position, p.yaw, p.pitch, p.hp, p.is_down, p.revive_progress, p.active, p.held_amount()]
		if p.index == 0:
			st.append_array([p.head_transform(), p.hand_transform(), p.left_hand_transform()])  # drawn on the TV
		if p.mega:
			st.append(true)  # MEGA SNOWBALL ready (left out when false: small snapshots)
		ps.append(st)
	var sm := []
	for s in get_tree().get_nodes_in_group("snowmen"):
		if not s.dead:
			var item := [s.net_id, s.kind, s.global_position, s.rotation.y, s.hp / s.max_hp, s.bashing]
			if s.net_aux() != 0:
				item.append(s.net_aux())  # balloons / shield, only for those kinds
			sm.append(item)
	var ck := []
	for c in get_tree().get_nodes_in_group("cocoa"):
		ck.append([c.net_id, c.global_position, c.kind] if c.kind != "cocoa" else [c.net_id, c.global_position])
	var snap := [wave, score, game_over, seg_hp, ps, sm, ck, boss_hp, director().pack(), boss_name if boss_hp >= 0.0 else ""]
	if props:
		snap.append_array([props.pack(), practice])
	return snap


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	wave = s[0]
	score = s[1]
	game_over = s[2]
	var hp_list: Array = s[3]
	for i in mini(SEGMENTS, hp_list.size()):
		seg_hp[i] = float(hp_list[i])
	var ps: Array = s[4]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_ghosts(s[5], "snowman")
	_sync_ghosts(s[6], "cocoa")
	boss_hp = s[7]
	if s.size() > 9:
		director().unpack(s[8])
		boss_name = s[9]
	if s.size() > 11 and props:
		props.unpack(s[10])
		practice = s[11]


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
	if kind == "snowman":
		var s := SnowmanScript.new()
		s.setup(item[1], maxi(wave, 1), self, 0)
		s.ghost = true
		s.net_id = item[0]
		s.position = item[2]
		s.rotation.y = item[3]
		add_child(s)
		return s
	var c := CocoaScript.new()
	c.main = self
	c.ghost = true
	c.net_id = item[0]
	c.position = item[1]
	if item.size() > 2:
		c.kind = item[2]
	add_child(c)
	return c


func apply_event(kind: String, args: Array) -> void:
	if seats.handle_event(kind, args):
		return
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			puff(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2])
		"collapse":
			collapse_fx(args[0], args[1], args[2])
		"ball":
			spawn_ball(args[0], args[1], args[2], 1.0, args[3], -1, true, args[4] if args.size() > 4 else "")
		"center":
			_show_center(args[0], args[1])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR player paused the game")
		"hurt":
			var hi: int = args[0]
			players[hi].on_remote_hurt(args[1])
		"hitmark":
			var mi: int = args[0]
			if players[mi].hud:
				players[mi].hud.hit_marker()
		"hint", "catapult":
			director().client_event(kind, args)
		"prop":
			if props:
				props.client_event(args)
		"village":
			_build_village(args[0], int(args[1]))
		"rink":
			rink.show_friends(args[0])
			rink.set_visitor(String(args[1]))
		"trick":
			_trick_show(int(args[0]), args[1])
		"trick_go":
			_trick_fx(int(args[0]), args[1])
		"story":
			_story(args[0], args[1], args[2], args.size() > 3 and bool(args[3]))
		"orbs":
			if (args[1] as Array).is_empty():
				orbs.clear()
			else:
				orbs.show_orbs(String(args[0]), args[1], ORB_ROW, ORB_GAP, ORB_Y)
		"take":
			if picks.vote_row():
				picks.take_fx(int(args[0]), int(args[1]))  # (the MODE vote's winner)
			else:
				_take_fx(int(args[0]), int(args[1]))
		"gifts":
			var all: Dictionary = args[0]
			for k in all:
				if int(k) >= 0 and int(k) < players.size():
					players[int(k)].gifts = (all[k] as Dictionary).duplicate()
			if args.size() > 1:
				game_mode = String(args[1])
		"warn":
			var g = ghost_nodes.get("snowman:%d" % int(args[0]))
			if g != null and is_instance_valid(g):
				g.tell_glow(float(args[4]))
			rings.warn(args[1], float(args[2]), args[3], float(args[4]))


# --- HUD ---------------------------------------------------------------------

func _make_label(font: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_constant_override("outline_size", maxi(6, font / 5))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1, 0.95))
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(30)
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 18
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = HudKit.split_center(_make_label(58))  # a copy in each split view, never across the line
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label = _make_label(22)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 70
	help_label.offset_bottom = 170
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Controller: left stick move · right stick look · hold RT to charge a snowball, let go to throw · hold X / LB at a crumbling wall to pack it\n" \
		+ "Keyboard: P1 WASD + mouse, hold click / Space to throw, E / right-click to pack  ·  P2 arrows, Enter throw, Ctrl pack\n" \
		+ "More controllers: press A / Start to join (up to 6 TV players)  ·  Grab hot cocoa to warm up · stand next to a frozen friend to thaw them\n" \
		+ "Survive %d waves and beat the YETI to save the village!" % FINALE_WAVE
	help_label.visible = not SIMPLE_MODE


func _show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_label.text = text
	if SIMPLE_MODE and text.strip_edges() != "":
		info_label.visible = false  # one headline at a time (_update_hud shows it again)
	center_label.add_theme_font_size_override("font_size", 58 if text.count("\n") < 6 else 36)
	center_label.modulate.a = 1.0
	if center_tween:
		center_tween.kill()
	if duration > 0.0:
		center_tween = create_tween()
		center_tween.tween_interval(duration)
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.5)


func _update_hud() -> void:
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the VR player…"
		return
	if SIMPLE_MODE:
		info_label.text = "WAVE %d" % wave if wave > 0 and not practice else ""
		# One headline at a time: the small WAVE n hides while the big one ("WAVE 3!") shows.
		info_label.visible = not (center_label.modulate.a > 0.05 and center_label.text.strip_edges() != "")
		return
	var wave_text := ("WAVE %d / %d" % [wave, FINALE_WAVE]) if wave <= FINALE_WAVE and not director().won else ("WAVE %d  ENDLESS" % wave)
	info_label.text = "%s      SCORE %d      FORT %d%%" % [wave_text, score, int(fort_fraction() * 100.0)]
	var boss := boss_text()
	if boss != "":
		info_label.text += "      " + boss
	var ev: String = director().event_name
	if ev != "":
		info_label.text += "\n" + str(director().EVENTS[ev][0])


## VR can't show 2D overlays: mirror the centre banner on a panel in front of the VR player.
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
		vr_center.position = Vector3(0.0, -0.1, -1.8)
		vr_center.modulate = Color(1.0, 0.95, 0.85)
		players[0].xr_camera.add_child(vr_center)
		players[0]._set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.text = preload("res://core/vr_text.gd").short(center_label.text)  # no walls of text in VR
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, players[0].xr_camera, self, -0.1, 1.8)


func vr_hurt_flash() -> void:
	vr_hurt = 1.0


## A frosty shell around the VR player's head that flashes when they're hit.
func _update_vr_hurt(delta: float) -> void:
	if players.is_empty() or not players[0].vr:
		return
	var p = players[0]
	if vr_hurt_mat == null:
		var shell := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		sphere.radial_segments = 16
		sphere.rings = 8
		shell.mesh = sphere
		vr_hurt_mat = StandardMaterial3D.new()
		vr_hurt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vr_hurt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # see-through-ok: the hurt flash round the head tints the whole view
		vr_hurt_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		vr_hurt_mat.no_depth_test = false
		vr_hurt_mat.render_priority = 20
		vr_hurt_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.0)
		shell.material_override = vr_hurt_mat
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.xr_camera.add_child(shell)
		p._set_layers(shell, p.viewmodel_layer())
	vr_hurt = maxf(0.0, vr_hurt - delta * 3.0)
	var cold := 0.25 if p.is_down else (0.08 if p.hp < 30.0 else 0.0)
	vr_hurt_mat.albedo_color.a = maxf(vr_hurt * 0.35, cold)


# --- Bobo's village and the seeded siege ---------------------------------------------------------

## Any machine: a TV machine plays at the host's mode.
func _on_state_changed(key: String, value: Variant) -> void:
	if key == "mode" and net.mode == "client" and SiegeGen.MODE_NUM.has(String(value)):
		game_mode = String(value)
	if key == "season" and net.mode == "client":
		_apply_season(String(value))


## Host / local: a new game. Count the play-day (igloos grow a stage each day), pick the siege (TODAY'S
## BLIZZARD first each day), show the village and tell the story.
func _start_siege() -> void:
	if save == null:
		save = Save.new()
		save.game_id = GAME_ID
		# village: [[play-day built, golden, waves beaten, want], ...]; days: days played; daily: the date
		# TODAY'S BLIZZARD was played.
		save.defaults = {"village": [], "igloos": 0, "days": 0, "last_day": "", "daily": "", "games": 0, "best_wave": 0, "wins": 0,
			"mode": "brave", "rink": []}  # rink: Bobo's friends who stayed to skate (rink.gd ids, oldest first); mode: the family's last GENTLE / BRAVE / HARD pick (the middle orb next visit)
		add_child(save)
	var today := Seeded.today()
	var new_day := String(save.data.last_day) != today
	if new_day:
		save.data.days = int(save.data.days) + 1
		save.data.last_day = today
	save.data.games = int(save.data.games) + 1
	save.mark_dirty()
	var daily := String(save.data.daily) != today
	var lv := SiegeGen.DAILY_LEVEL if daily else SiegeGen.level(int(save.data.igloos))
	var seed_value := SiegeGen.daily_seed() if daily else Seeded.fresh_seed()
	if OS.has_environment("SB_SEED"):
		seed_value = int(OS.get_environment("SB_SEED"))
	game_mode = net.forced_mode("SB_MODE") if SiegeGen.MODE_NUM.has(net.forced_mode("SB_MODE")) else String(save.data.mode)
	if not SiegeGen.MODE_NUM.has(game_mode):
		game_mode = "brave"
	siege = _make_siege(seed_value, lv, daily)
	_apply_season(SeasonKit.override(GAME_ID, Seeded.season(), Seasons.SEASONS))
	net.state_set("season", season)  # (local too: bots watch it)
	friend = Rink.pick(int(siege.seed), season)
	friend_stayed = false
	tricks_done = 0
	trick = {}
	trick_phase = ""
	gifts_taken = {}
	_send_gifts()
	if net.mode == "host":
		net.event("orbs", ["", []])  # (no orbs yet: a machine joining now knows that at once)
	siege_t = 0.0
	built = false
	logged = false
	print("Snowball Blitz siege: seed %d level %d%s mode %s want %s new %s gates %s | village %d igloos, day %d" % [
		seed_value, lv, " (TODAY'S BLIZZARD)" if daily else "", game_mode, SiegeGen.WANT_NAMES[int(siege.want)], str(siege.new),
		str((siege.waves as Array).map(func(w: Dictionary) -> int: return (w.gates as Array).size())),
		(save.data.village as Array).size(), int(save.data.days)])
	village_days = int(save.data.days)
	_build_village(save.data.village, village_days)
	_send_village()
	_send_rink()
	print("Snowball Blitz: %s, visitor %s, surprises %s, %d friends skating" % [season, friend,
		str((siege.tricks as Dictionary).keys().map(func(n: int) -> String: return "%d:%s" % [n, siege.tricks[n].kind])),
		(save.data.rink as Array).size()])
	var want := int(siege.want)
	if daily:
		_story_for_all("TODAY'S BLIZZARD!", "igloo", Color(1.0, 0.85, 0.3))
	_story_for_all("Hi! I'm Bobo!", "polarbear", SiegeGen.WANT_COLORS[want])
	_story_for_all(Seasons.LINES[season], Seasons.PICS[season], Seasons.CARD_COLORS[season])
	if new_day and not (save.data.village as Array).is_empty():
		_story_for_all("Our igloos grew!", "igloo", Color(0.6, 0.85, 1.0))
	var fr := Rink.find(friend)
	_story_for_all("%s is here!" % fr.name, String(fr.pic), fr.body)
	_story_for_all(_want_line(), SiegeGen.WANTS[want], SiegeGen.WANT_COLORS[want])  # last: the card a late joiner sees (sticky "story")


func _want_line() -> String:
	return "Save my %s!" % SiegeGen.WANT_NAMES[int(siege.get("want", 0))].to_lower()


## Host / local: this game's igloo joins the village (once per game, when at least one wave was beaten).
func _build_igloo() -> void:
	if built or siege.is_empty() or save == null:
		return
	var beaten := wave - (0 if in_break else 1)
	if director().won:
		beaten = maxi(beaten, SIMPLE_FINALE)
	save.data.best_wave = maxi(int(save.data.best_wave), beaten)
	if director().won:
		save.data.wins = int(save.data.wins) + 1
	if beaten < 1:
		save.mark_dirty()
		return
	built = true
	var list: Array = save.data.village
	list.append([int(save.data.days), bool(siege.daily), beaten, int(siege.want)])
	while list.size() > SiegeGen.VILLAGE_KEEP:
		list.pop_front()
	save.data.igloos = int(save.data.igloos) + 1
	if siege.daily:
		save.data.daily = Seeded.today()
	save.mark_dirty()
	_build_village(list, int(save.data.days))
	_send_village()
	var n := list.size()
	_story_for_all(VILLAGE_CHEERS.get(n, "A new igloo!"), "igloo", Color(1.0, 0.85, 0.3) if siege.daily else SiegeGen.WANT_COLORS[int(siege.want)])
	print("Snowball Blitz: igloo %d built (%d waves beaten%s)" % [n, beaten, ", golden" if siege.daily else ""])


func _send_village() -> void:
	if net and net.mode != "client" and save != null:
		net.event("village", [(save.data.village as Array).duplicate(true), int(save.data.days)])


## One RUN line per game (and on quit).
func _log_run(end: String) -> void:
	if logged or siege.is_empty():
		return
	logged = true
	Telemetry.run(GAME_ID, {"end": end, "wave": wave, "seed": int(siege.seed), "level": int(siege.level),
		"daily": bool(siege.daily), "secs": snappedf(siege_t, 0.1), "score": score, "won": director().won,
		"players": party_size(), "vr": not players.is_empty() and players[0].vr, "net": net.mode,
		"fort": snappedf(fort_fraction(), 0.01), "igloos": (save.data.village as Array).size() if save else 0,
		"days": int(save.data.days) if save else 0, "mode": game_mode, "gifts": _gift_counts(),
		"season": season, "friend": friend, "stayed": friend_stayed, "tricks": tricks_done,
		"rink": (save.data.rink as Array).size() if save else 0})


func _exit_tree() -> void:
	if net and net.mode != "client" and SIMPLE_MODE and not siege.is_empty() and not game_over:
		_log_run("quit")


## Every machine: Bobo's igloos round the square (each grows a stage every play-day; today's is golden).
func _build_village(list: Array, days: int) -> void:
	village_list = list.duplicate(true)
	village_days = days
	if village == null:
		village = Node3D.new()
		village.name = "Village"
		add_child(village)
	if village_count == list.size() and village.get_child_count() == list.size() and village.get_meta("days", -1) == days:
		return
	for c in village.get_children():
		village.remove_child(c)
		c.queue_free()
	village.set_meta("days", days)
	for i in mini(list.size(), SiegeGen.VILLAGE_SLOTS):
		var e: Array = list[i]
		var ig := _igloo(SiegeGen.igloo_stage(int(e[0]), days), bool(e[1]), SiegeGen.WANT_COLORS[int(e[3]) % SiegeGen.WANT_COLORS.size()])
		ig.position = SiegeGen.village_slot(i)
		UiKit.look(ig, Vector3.ZERO, Vector3.UP)
		village.add_child(ig)
		if village_count >= 0 and i >= village_count:
			ig.scale = Vector3.ONE * 0.05
			ig.create_tween().tween_property(ig, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			puff(ig.position + Vector3.UP, Color(1, 1, 1), 30, 0.14)
	village_count = list.size()


## One igloo: stage 1 a small dome, 2 a full igloo with a door, 3 a lit door and a flag in `flag`.
func _igloo(stage: int, golden: bool, flag: Color) -> Node3D:
	var root := Node3D.new()
	var snow: StandardMaterial3D = make_material(Color(1.0, 0.85, 0.35) if golden else Color(0.93, 0.96, 1.0), 0.6 if golden else 0.0)
	var k := 0.7 if stage <= 1 else 1.0
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 1.3 * k
	dm.height = 2.6 * k
	dm.is_hemisphere = true
	dm.radial_segments = 16
	dm.rings = 6
	dome.mesh = dm
	dome.material_override = snow
	root.add_child(dome)
	if stage >= 2:
		var door := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.45
		cm.height = 0.9
		cm.radial_segments = 10
		door.mesh = cm
		door.material_override = snow
		door.rotation_degrees = Vector3(90, 0, 0)
		door.position = Vector3(0, 0.35, -1.2)  # faces the fort (look() turns -Z to the square)
		root.add_child(door)
		var hole := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.33
		hm.height = 0.66
		hm.radial_segments = 8
		hm.rings = 4
		hole.mesh = hm
		hole.material_override = make_material(Color(1.0, 0.7, 0.3), 2.5) if stage >= 3 else make_material(Color(0.25, 0.3, 0.45), 0.0)
		hole.scale = Vector3(1.0, 1.0, 0.3)
		hole.position = Vector3(0, 0.35, -1.65)
		root.add_child(hole)
	if stage >= 3:
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.03
		pm.bottom_radius = 0.03
		pm.height = 1.1
		pole.mesh = pm
		pole.material_override = make_material(Color(0.4, 0.3, 0.2), 0.0)
		pole.position = Vector3(0, 1.3 * k + 0.5, 0)
		root.add_child(pole)
		var fl := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.5, 0.32, 0.03)
		fl.mesh = fm
		fl.material_override = make_material(flag, 0.4)
		fl.position = Vector3(0.27, 1.3 * k + 0.88, 0)
		root.add_child(fl)
	return root


## Host / local: a story card on every machine.
## urgent (the pick prompts): to the front of the queue, shown now.
func _story_for_all(line: String, pic: String, color: Color, urgent: bool = false) -> void:
	_story(line, pic, color, urgent)
	if net and net.mode == "host":
		net.event("story", [line, pic, color, true] if urgent else [line, pic, color])


func _story(line: String, pic: String, color: Color, urgent: bool = false) -> void:
	if urgent:
		story_queue = story_queue.filter(func(q: Array) -> bool: return not (q.size() > 3 and bool(q[3])))  # an older prompt is stale now
		story_queue.push_front([line, pic, color, true])
		story_t = minf(story_t, 0.2)
	elif story_queue.size() < 7:
		story_queue.append([line, pic, color])


func _update_story(delta: float) -> void:
	story_t -= delta
	if story_t > 0.0 or story_queue.is_empty() or players.is_empty():
		return
	var b: Array = story_queue.pop_front()
	story_t = 2.6
	var opts := {"who": "BOBO", "line": b[0], "pic": b[1], "color": b[2], "duration": 2.4,
		"vr_height": -0.55}  # (VR: under the boss, never over it; clear of pick orbs by itself: UiKit.vr_dodge)
	var huds: Array = []
	for p in players:
		if p.hud != null and is_instance_valid(p.hud) and p.hud.is_visible_in_tree():
			huds.append(p.hud)
	if not huds.is_empty():
		StoryCard.show(huds, opts)
	if players[0].vr and players[0].xr_camera != null:
		StoryCard.show_vr(self, players[0].xr_camera, opts)


# --- Picks (core/pick_orbs.gd): MODE (team, the first game of a visit), BOBO'S GIFTS (each player, after every wave) ---

func _pick_players() -> Array:
	return players.filter(func(p) -> bool: return p.active and not p.ghost and (not p.remote or net.connected))


func _party_gifts() -> Array:
	var out: Array = []
	for p in players:
		if p.active and not p.gifts.is_empty():
			out.append(p.gifts)
	return out


## Host / local: the pick orbs in front of the fort ("mode" after the practice on the first game of a visit, "gift"
## after every cleared wave).
func _begin_pick(stage: String) -> void:
	if net.mode == "client":
		return
	var ids: Array = []
	if stage == "mode":
		ids = PickOrbs.mode_ids(game_mode)
	else:
		ids = Gifts.offer(int(siege.get("seed", 0)), wave, Gifts.unlocked(int(save.data.igloos) if save else 0))
	if ids.is_empty() or _pick_players().is_empty():
		return
	pick_ids = ids
	pick_stage = stage
	pick_t = float(Gifts.WAIT[stage]) * (Gifts.GENTLE_WAIT if game_mode == "gentle" and stage != "mode" else 1.0)
	picked = {}
	var entries := _orb_entries(stage, ids)
	if stage == "mode":  # everyone votes (picks.gd)
		picks.begin(ids, _mode_voted)
	else:
		orbs.show_orbs(stage, entries, ORB_ROW, ORB_GAP, ORB_Y)
		if net.mode == "host":
			net.event("orbs", [stage, entries])
	var mid: Dictionary = entries[entries.size() / 2]
	_story_for_all("Pick how brave!" if stage == "mode" else "Pick a gift!", String(mid.pic) if stage == "mode" else "gift",
		mid.color, true)
	sound("bell", -4.0, 1.2)
	print("PICK %s: %s (%.0f s)" % [stage, ids, pick_t])


static func _orb_entries(stage: String, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var d: Dictionary = PickOrbs.mode(String(id)) if stage == "mode" else Gifts.find(String(id))
		out.append({"id": String(id), "name": String(d.get("name", id)), "pic": String(d.get("pic", "star")),
			"color": d.get("color", Color.WHITE)})
	return out


func _pick_tick(delta: float) -> void:
	if picks.active():  # the MODE: everyone votes (picks.gd); it calls _mode_voted
		picks.tick(delta)
		return
	pick_t -= delta
	for tch in orbs.touches(players):
		on_orb_hit(int(tch[0]), tch[1], "walk")
	if pick_stage == "":
		return
	var all := true
	for p in _pick_players():
		if not picked.has(p.index):
			all = false
	if all or pick_t <= 0.0:
		_finish_pick()


## Host / local: a player threw a snowball at (or walked into) orb i.
func on_orb_hit(i: int, p, how: String = "throw") -> void:
	if pick_stage == "" or net.mode == "client" or i < 0 or i >= pick_ids.size() or not (p in players):
		return
	if picks.active():
		picks.choose(i, p.index)  # the MODE: a vote (picks.gd)
		return
	if picked.has(p.index):
		return
	picked[p.index] = i
	_take_fx(i, p.index)
	if net.mode == "host":
		net.event("take", [i, p.index])
	sound("pickup", 0.0, 1.0 + 0.1 * i)
	var id := String(pick_ids[i])
	match pick_stage:
		"gift":
			Gifts.apply(p.gifts, id)
			var mine: Array = gifts_taken.get(p.index, [])
			mine.append(id)
			gifts_taken[p.index] = mine
			if id == "mega" and p.gifts.get("mega", 0.0) >= 1.0:
				p.mega = true  # one to throw right away
	print("PICK %s: P%d took %s (%s)" % [pick_stage, p.index + 1, id, how])


## Every machine: slot took orb i (a dot in their colour circles it, a puff of the orb's colour).
func _take_fx(i: int, slot: int) -> void:
	var at := orbs.take(i, PLAYER_COLORS[slot % PLAYER_COLORS.size()])
	if at != Vector3.INF:
		puff(at, orbs.color_of(i), 16, 0.09)


## Host / local: the MODE vote is in (picks.gd: the most votes, a tie stays gentler, nobody: the middle orb).
func _mode_voted(_stage: String, id: Variant, _by: int) -> void:
	game_mode = String(id)
	if save != null:
		save.data.mode = game_mode
		save.mark_dirty()
	print("PICK mode: the team voted %s" % game_mode)
	_finish_pick()


func _finish_pick() -> void:
	if picks.active():  # (cut short, e.g. SB_WAVE: the vote so far / the middle orb)
		picks.finish_now()
		return
	var di := pick_ids.find(Gifts.default_pick(pick_ids))
	if pick_stage != "mode":
		for p in _pick_players():
			if not picked.has(p.index):
				on_orb_hit(di, p, "middle")
	var stage := pick_stage
	pick_stage = ""
	orbs.clear()
	if net.mode == "host":
		net.event("orbs", ["", []])
	_send_gifts()
	break_timer = 2.0
	if stage == "mode":
		Engine.set_meta("sb_mode_set", true)
		var m := PickOrbs.mode(game_mode)
		_story_for_all(String(PickOrbs.MODE_LINES.get(game_mode, "Let's go!")), String(m.get("pic", "star")), m.get("color", Color.WHITE))
		if wave == 0 and not siege.is_empty():
			siege = _make_siege(int(siege.seed), int(siege.level), bool(siege.daily))  # the same seed, this mode
			print("Snowball Blitz siege: mode %s (%s)" % [game_mode, str((siege.waves as Array).map(func(w: Dictionary) -> int: return (w.spawns as Array).size()))])
		_skip_to_env_wave()


## Host: everyone's gifts (and the mode) to every machine (sticky: a late machine catches up).
func _send_gifts() -> void:
	if net == null or net.mode != "host":
		return
	var all := {}
	for p in players:
		if not p.gifts.is_empty():
			all[p.index] = p.gifts.duplicate()
	net.event("gifts", [all, game_mode])


## Host / local: MEGA gifts give their MEGA SNOWBALL (level 1: at the start of a wave, 2: halfway too).
func _give_megas(level: int) -> void:
	if net.mode == "client":
		return
	for p in players:
		if p.active and not p.is_down and float(p.gifts.get("mega", 0.0)) >= level and not p.mega:
			p.mega = true


## Telemetry: how many of each gift the party took this game.
func _gift_counts() -> Dictionary:
	var out := {}
	for k in gifts_taken:
		for id in gifts_taken[k]:
			out[id] = int(out.get(id, 0)) + 1
	return out


var _env_wave_done := false
## SB_WAVE=n (What's New "try"): jump to wave n once the picks are done.
func _skip_to_env_wave() -> void:
	if _env_wave_done or not OS.has_environment("SB_WAVE"):
		return
	_env_wave_done = true
	var n := int(OS.get_environment("SB_WAVE"))
	if n > 1:
		print("SB_WAVE: skip to wave %d" % n)
		debug_skip_to_wave(n)


## Host / local: a boss tells its next big attack: it glows and a ring lies on the snow until it lands (every machine).
func boss_tell(s, pos: Vector3, radius: float, col: Color, secs: float) -> void:
	s.tell_glow(secs)
	rings.warn(pos, radius, col, secs)
	if net.mode == "host":
		net.event("warn", [s.net_id, pos, radius, col, secs])
	sound("roar", -8.0, 1.4 if s.kind == "king" else 1.0)

# --- Third pass: seasons, Bobo's friends, warned surprises -----------------------------------------------

## Every machine: dress the square and the snowmen's hats for the season (seasons.gd).
func _apply_season(s: String) -> void:
	if not Seasons.SEASONS.has(s):
		return
	season = s
	seasons_node.set_season(s)
	mat("hat").albedo_color = Seasons.hat(s)


## Host / local: the siege for a seed in this game's mode, with its warned surprises (tricks.gd).
func _make_siege(seed_value: int, lv: int, daily: bool) -> Dictionary:
	var s := SiegeGen.siege(seed_value, lv, daily, game_mode)
	s.tricks = Tricks.plan(s)
	if OS.has_environment("SB_TRICK") and Tricks.KINDS.has(OS.get_environment("SB_TRICK")):
		s.tricks = _forced_tricks(OS.get_environment("SB_TRICK"), seed_value)
	return s


## SB_TRICK=slide|icicles (tests, What's New): that surprise in every plain wave from wave 1, quickly.
func _forced_tricks(kind: String, seed_value: int) -> Dictionary:
	var out := {}
	var r := Seeded.rng(seed_value, "forced")
	for n in range(1, 31):
		if Tricks.BOSS_WAVES.has(n):
			continue
		var t := Tricks.one(r, kind, game_mode)
		t.at = 4.0
		out[n] = t
	print("SB_TRICK=%s: a %s in every plain wave" % [kind, kind])
	return out


## Host / local: the friends who stayed and this siege's visitor, to every machine (sticky: late machines catch up).
func _send_rink() -> void:
	if save == null:
		return
	var ids: Array = (save.data.rink as Array).duplicate()
	var vis := "" if friend_stayed else friend
	rink.show_friends(ids)
	rink.set_visitor(vis)
	if net and net.mode == "host":
		net.event("rink", [ids, vis])


## Host / local: the family held the fort for STAY_WAVES waves: the visitor stays to skate (once per siege).
func _friend_stays() -> void:
	if friend_stayed or friend == "" or save == null:
		return
	friend_stayed = true
	var list: Array = save.data.rink
	list.append(friend)
	while list.size() > Rink.KEEP:
		list.pop_front()
	save.mark_dirty()
	_send_rink()
	var fr := Rink.find(friend)
	_story_for_all("%s stays to skate!" % fr.name, String(fr.pic), fr.body)
	sound("fanfare", -8.0, 1.3)
	if net.mode != "client":
		net.state_set("friend_stayed", "%s:%d" % [friend, list.size()])
	print("Snowball Blitz: %s stays to skate (%d friends on the pond)" % [friend, list.size()])


## Host / local: this wave's surprise: wait AT seconds, tell it (rings + a card) for TELL seconds, then it goes.
func _trick_tick(delta: float) -> void:
	if trick_phase == "" or trick.is_empty():
		return
	if trick_phase == "wait" and (in_break or game_over):
		trick_phase = ""  # the wave was over before its surprise: no surprise
		return
	trick_t -= delta
	if trick_t > 0.0:
		return
	match trick_phase:
		"wait":
			trick_phase = "tell"
			trick_t = float(trick.tell)
			_trick_show(wave, trick)
			_story_for_all(Tricks.NAMES[trick.kind], Tricks.PICS[trick.kind], Tricks.COLORS[trick.kind], true)
			sound("bell", -2.0, 0.7)
			if net.mode == "host":
				net.event("trick", [wave, trick])
			net.state_set("trick", "tell:%d:%s" % [wave, trick.kind])
		"tell":
			trick_phase = ""
			tricks_done += 1
			_trick_fx(wave, trick)
			if net.mode == "host":
				net.event("trick_go", [wave, trick])
			net.state_set("trick", "go:%d:%s" % [wave, trick.kind])
			if trick.kind == "icicles":
				get_tree().create_timer(0.4).timeout.connect(_icicles_land.bind(trick.duplicate(true)))


## Every machine: the told shapes on the snow (exactly tricks.gd zones()).
func _trick_show(w: int, t: Dictionary) -> void:
	var col: Color = Tricks.COLORS.get(String(t.kind), Color.ORANGE)
	for z in Tricks.zones(t):
		rings.shape(String(z.kind), z.pos, z.dir, z.size, col, float(t.tell), {"style": "disc", "stay": 0.4, "alpha": 0.5})
	trick_log.append([w, String(t.kind), siege_t, -1.0])
	print("SURPRISE told: wave %d %s for %.1f s" % [w, t.kind, float(t.tell)])


## Every machine: the surprise goes (a ball rolls / icicles drop); the host does the hits.
func _trick_fx(w: int, t: Dictionary) -> void:
	if not trick_log.is_empty() and int(trick_log[-1][0]) == w and float(trick_log[-1][3]) < 0.0:
		trick_log[-1][3] = siege_t
	else:
		trick_log.append([w, String(t.kind), -1.0, siege_t])  # (went without a tell seen here: the bot fails it)
	print("SURPRISE goes: wave %d %s" % [w, t.kind])
	if String(t.kind) == "slide":
		var ball := MeshInstance3D.new()
		ball.mesh = sphere_mesh(Tricks.SLIDE_R)
		ball.material_override = mat("snow")
		add_child(ball)
		_ink_outline(ball)
		slides.append({"node": ball, "from": t.from, "dir": t.dir, "len": float(t.len), "t": 0.0, "hit": {}})
		sound("roar", -6.0, 0.5)
	else:
		for z in Tricks.zones(t):
			for k in 4:
				var ic := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.12
				cm.bottom_radius = 0.0
				cm.height = 0.7
				cm.radial_segments = 6
				ic.mesh = cm
				ic.material_override = mat("ice")
				var off := Vector3(cos(k * 1.7), 0.0, sin(k * 1.7)) * Tricks.ICICLE_R * 0.55
				ic.position = (z.pos as Vector3) + off + Vector3.UP * 9.0
				add_child(ic)
				var tw := ic.create_tween()
				tw.tween_property(ic, "position:y", SEG_HEIGHT + 0.2, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				tw.tween_callback(func() -> void: puff(ic.position, Color(0.8, 0.9, 1.0), 10, 0.08))
				tw.tween_interval(0.4)
				tw.tween_callback(ic.queue_free)
		sound("thud", -4.0, 1.5)


## The rolling snow-slide ball is snow-white on the snow: the ink outline (core/contrast.gd, like the snowmen).
func _ink_outline(mi: MeshInstance3D) -> void:
	preload("res://core/contrast.gd").outline(mi)


## Host / local: the icicles land: a little snow off each told wall (never the last of it), a cold splat for anyone
## standing in a circle, a bonk for snowmen there.
func _icicles_land(t: Dictionary) -> void:
	if net.mode == "client" or not is_inside_tree():
		return
	var hit: float = float(Tricks.ICICLE_HIT.get(game_mode, 25.0))
	for i in t.get("segs", []):
		var si := int(i)
		seg_hp[si] = maxf(seg_hp[si] - hit, minf(seg_hp[si], Tricks.ICICLE_KEEP))
	for z in Tricks.zones(t):
		for p in players:
			if p.active and WarnRings.inside("circle", z.pos, z.dir, z.size, p.global_position, 0.3):
				p.take_damage(4.0, z.pos)
				print("SURPRISE: icicles splat P%d" % (p.index + 1))
		for s in get_tree().get_nodes_in_group("snowmen"):
			if not s.dead and WarnRings.inside("circle", z.pos, z.dir, z.size, s.global_position, s.radius()):
				s.take_hit(3.0, Vector3.UP, -1)


## Every machine: roll the snow slides; the host bowls over the snowmen in the way (a boss just wobbles).
func _update_slides(delta: float) -> void:
	for sl in slides.duplicate():
		sl.t = float(sl.t) + delta
		var d := float(sl.t) * Tricks.SLIDE_SPEED
		var node: MeshInstance3D = sl.node
		if d > float(sl.len) or not is_instance_valid(node):
			if is_instance_valid(node):
				puff(node.position, Color(1, 1, 1), 20, 0.12)
				node.queue_free()
			slides.erase(sl)
			continue
		var pos: Vector3 = (sl.from as Vector3) + (sl.dir as Vector3) * d + Vector3.UP * Tricks.SLIDE_R
		node.position = pos
		node.rotate(Vector3.UP.cross(sl.dir as Vector3).normalized(), delta * Tricks.SLIDE_SPEED / Tricks.SLIDE_R)
		if fmod(float(sl.t), 0.15) < delta:
			puff(pos - Vector3.UP * Tricks.SLIDE_R, Color(1, 1, 1), 4, 0.1)
		if net.mode == "client":
			continue
		for s in get_tree().get_nodes_in_group("snowmen"):
			if s.dead or (sl.hit as Dictionary).has(s.get_instance_id()):
				continue
			var to: Vector3 = s.global_position - pos
			to.y = 0.0
			if to.length() < Tricks.SLIDE_W * 0.5 + s.radius():
				sl.hit[s.get_instance_id()] = true
				s.take_hit(2.0 if s.is_boss() else 99.0, (sl.dir as Vector3) * 10.0 + to.normalized() * 4.0, -1)
				print("SURPRISE: the snow slide bowls over a %s" % s.kind)
		for p in players:
			if p.active and Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() < Tricks.SLIDE_W * 0.5:
				p.take_damage(4.0, pos)