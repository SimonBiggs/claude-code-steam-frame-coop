extends Node3D
## BUBBLE BATH: a giant bathtub full of bubbles and rubber ducks.
## TV players steer tiny boats: touch a duck and it follows you in a little duck train; drive into
## the glowing plug-hole and every duck in your train goes down the drain for the team score.
## The VR player is the big splasher: slap the water to make waves that push boats and ducks, pull
## the trigger to grab a duck and throw it (a duck that lands in the plug-hole scores too), touch the
## tap for a new duck. Two minute rounds, a results screen, then the next round starts by itself.
## Built on the engine template (core/ party, split view, camera rig, VR rig, state store, awards).
## STORY + DEPTH: MAMA DUCK sits on the far rim. Every round's bath comes from a seed (bathgen.gd: where the plug-hole
## is, the sponge islands boats sail round, where ducks pop up, where boats start, when golden ducks (worth 3) come,
## the team's duck goal; one new thing a round, checked by a validator). Reaching the goal puts a bath TOY on the side
## rim (saved), a duckling joins Mama Duck each play-day, and with ten toys she wears a crown. TODAY'S BATH: the first
## bath each day is the same on every machine and its toys wear a gold star. Picture cards (story_pictures.gd) tell it.
## Telemetry: one RUN line per round and on quit. Networked: the host sets "bath" = [seed, round, daily] in the state
## store and every machine rebuilds the same bath from it; toys + ducklings go as "family", cards as "story" events.

const NetScript := preload("res://core/net.gd")
const BathGen := preload("res://games/bubble_bath/bathgen.gd")
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")
const MAMA := "MAMA DUCK"
const MAMA_COLOR := Color(1.0, 0.8, 0.2)
const TOY_LINES := {"boat": "A toy boat!", "beachball": "A beach ball!", "starfish": "A starfish!", "whale": "A squirty whale!",
	"soapbar": "Bubbly soap!", "fish": "A little fish!"}
const TOY_COLORS := {"boat": Color(0.95, 0.3, 0.25), "beachball": Color(0.35, 0.65, 1.0), "starfish": Color(1.0, 0.55, 0.25),
	"whale": Color(0.35, 0.65, 1.0), "soapbar": Color(1.0, 0.6, 0.8), "fish": Color(1.0, 0.55, 0.15)}
const BUBBLE_TINTS: Array[Color] = [Color(0.55, 0.45, 0.7), Color(0.75, 0.4, 0.6), Color(0.35, 0.6, 0.8), Color(0.45, 0.7, 0.45), Color(0.8, 0.65, 0.3)]
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
const HudKit := preload("res://core/hud_kit.gd")
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Art := preload("res://games/bubble_bath/art.gd")

const GAME_ID := "bubble_bath"
const HX := 4.2  # inside half-size of the tub (x)
const HZ := 2.7  # inside half-size of the tub (z)
const WATER_Y := 0.8
const RIM_Y := 1.05
const DRAIN := Vector3(0.0, WATER_Y, 0.0)
const DRAIN_R := 0.55
const TAP := Vector3(-1.1, 0.0, HZ + 0.15)
const BOAT_R := 0.3
const BOAT_ACCEL := 7.0
const BOAT_MAX := 2.8
const DUCK_R := 0.17
const MAX_TRAIN := 5
const DUCKS_ON_WATER := 10
const GRAB_R := 0.3
const WAVE_R := 1.6
const BUBBLES := 60
enum { FLOAT, TOW, HELD, FLY, SINK }
const LOOKS: Array[String] = ["pirate", "knight", "chef", "astronaut", "bard", "mage", "archer"]
const INTRO := {
	"title": "BUBBLE BATH",
	"goal": "Bring the ducks to the plug!",
	"vr": {"role": "THE BIG SPLASHER", "controls": [["HANDS", "Splash"], ["TRIGGER", "Grab + throw"], ["L-STICK", "Walk"]]},
	"tv": {"role": "THE BOATS", "controls": [["L-STICK", "Steer"], ["Y", "Split / shared view"]]},
}

var round_time := 120.0  ## seconds per round (bots shorten it before adding the game)

# --- The networking contract ---
var net: Node
var ready_to_play := false
var flat_host := false  # this machine hosts without VR: slot 0 is a pad / keyboard player here, like local play
var net_target := {}  # slot -> [pos, yaw]: where another machine's player is (smoothed towards every frame)
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
var sky: SkyKit.SkyRig

var boats := {}  # slot -> Node3D (every machine)
var boat_vel := {}  # slot -> Vector3 (machine that steers it)
var trains := {}  # slot -> Array of duck ids (host / local)
var cams := {}
var group_cam: CameraRig
var huds := {}
var score_labels := {}
var timers := {}
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var vr_label: Label3D
var board: Label3D  # big world-locked score over the far end of the tub
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node

var ducks := {}  # id -> Node3D
var duck_vel := {}  # id -> Vector3 (host / local)
var duck_state := {}  # id -> FLOAT / TOW / ...
var duck_t := {}  # id -> seconds in its current state
var duck_by := {}  # id -> slot that last threw / splashed it (-1 = nobody)
var duck_cd := {}  # id -> squeak cooldown
var next_duck := 0
var held := -1  # duck id in the VR player's right glove
var spawn_t := 0.0
var tap_cd := 0.0
var splash_cd: Array[float] = [0.0, 0.0]
var hand_was_wet: Array[bool] = [false, false]

var water: MeshInstance3D
var water_mat: ShaderMaterial
var ripples: Array[Vector4] = []
var drain_spin: MeshInstance3D
var drain_arrow: MeshInstance3D
var tap_handle: MeshInstance3D
var bubble_mm: MultiMesh
var bubble_pos: Array[Vector3] = []
var bubble_life: Array[float] = []  # < 0: popped, counting up to respawn
var clock := 0.0
var send_t := 0.0
var time_left := 0.0
var results_t := 0.0
var total_ducks := 0
var splashes := 0  # splashes made on this machine (bots)
# --- The seeded bath + Mama Duck's family (host / local own the save; every machine builds from "bath" / "family") ---
var drain := DRAIN  # this round's plug-hole (bathgen.gd)
var plan := {}  # this round's bath (every machine, rebuilt from the "bath" state)
var islands: Array = []  # [Vector3(x, z, r)] sponge islands (every machine)
var island_root: Node3D
var bath_seed := 0
var bath_daily := false
var bath_round := 0  # rounds in this bath (host / local)
var spot_i := 0  # next duck spot (host / local)
var golden_left: Array = []  # golden ducks still to come this round: Vector2(when 0..1, spot)
var duck_gold := {}  # id -> true for golden ducks (every machine)
var round_t := 0.0
var goal := 0
var goal_hit := false
var golden_caught := 0
var mama: Node3D
var family_root: Node3D
var family_key := ""
var story_queue: Array = []
var story_t := 0.0


func _ready() -> void:
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.sticky_event("family")  # a machine that joins later gets the latest one (core/net.gd)
	net.state_changed.connect(_on_state_changed)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	# toys: [[kind, play-day, golden], ...]; days: days played; daily: the date TODAY'S BATH ran; goals: goals ever reached.
	save.defaults = {"best": 0, "toys": [], "goals": 0, "days": 0, "last_day": "", "daily": "", "daily_done": "", "baths": 0, "rounds": 0, "ducks": 0, "golden": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("party")
	music.prepare(["victory"])
	awards = Awards.new()
	hints = Hints.new()
	add_child(hints)
	hints.bind_party(party)
	for i in 8:
		ripples.append(Vector4(0.0, 0.0, -100.0, 0.0))
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	flat_host = mode == "host" and not net.has_vr
	if VrRig.wanted(mode) and not flat_host:
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-HX - 2.0, -HZ - 2.0, HX * 2.0 + 4.0, HZ * 2.0 + 4.0)
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, HZ + 0.35), 0.0)
		vr_label = UiKit.label3d("", 0.03, "gold", true)
		vr_label.position = Vector3(0.0, 0.05, 0.06)  # back of the hand, clear of the wrist MENU
		vr_label.rotation = Vector3(-1.2, 0.0, 0.0)
		vr_rig.hand_l.add_child(vr_label)
		hints.set_vr_rig(vr_rig, self)
	_build_world(vr_rig != null)
	if mode != "host" or flat_host:  # every machine with a screen of its own (a flat host too)
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 7.0
		add_child(group_cam)
		group_cam.follow_group([], -55.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	awards.set_player(0, "SPLASHER" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		net.state_set("shared", false)
		_start_bath()
		_start_round()
	elif net.state_get("bath", null) != null:
		_apply_bath(net.state_get("bath", null))  # joined mid-round: build the bath already playing
	hints.intro(INTRO, {"duration": 6.0})
	if vr_rig != null:
		hints.hint("vr_splash", "Splash the water!", {"to": "vr", "icon": "drop"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Bubble Bath: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	add_child(MeshKit.instance(Art.bathroom(HX, HZ, WATER_Y, RIM_Y, TAP)))
	water = Art.water(HX, HZ)
	water.position = Vector3(0.0, WATER_Y, 0.0)
	water_mat = water.material_override
	add_child(water)
	drain_spin = MeshKit.instance(Art.drain(DRAIN_R), false)
	drain_spin.position = drain + Vector3.UP * 0.02
	add_child(drain_spin)
	drain_arrow = MeshKit.instance(Art.arrow(), false)
	drain_arrow.position = drain + Vector3.UP * 0.9
	add_child(drain_arrow)
	tap_handle = MeshKit.instance(Art.tap_handle(), false)
	tap_handle.position = Vector3(TAP.x, RIM_Y + 0.42, TAP.z + 0.05)
	add_child(tap_handle)
	# Floating soap bubbles: one MultiMesh, popped by gloves and boats.
	bubble_mm = MultiMesh.new()
	bubble_mm.transform_format = MultiMesh.TRANSFORM_3D
	bubble_mm.mesh = Art.bubble_mesh()
	bubble_mm.instance_count = BUBBLES
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = bubble_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in BUBBLES:
		bubble_pos.append(_random_water_spot(0.6))
		bubble_life.append(randf() * 5.0)
	# The big score board, world-locked over the far end of the tub (reads from +Z: faces the VR player).
	board = UiKit.label3d("", 0.42, "gold", true)
	board.outline_size = 26
	board.position = Vector3(0.0, 2.6, -HZ - 1.2)
	add_child(board)
	island_root = Node3D.new()
	island_root.name = "Islands"
	add_child(island_root)
	# Mama Duck on the far rim, facing the tub; her ducklings and the bath toys are built by _build_family().
	mama = Node3D.new()
	mama.name = "MamaDuck"
	mama.position = BathGen.mama_slot(RIM_Y)
	mama.scale = Vector3.ONE * 3.2
	add_child(mama)
	family_root = Node3D.new()
	family_root.name = "Family"
	add_child(family_root)
	_build_family([], 0, false)


func _random_water_spot(margin: float) -> Vector3:
	for _i in 10:
		var p := Vector3(randf_range(-HX + margin, HX - margin), WATER_Y, randf_range(-HZ + margin, HZ - margin))
		if p.distance_to(drain) > 1.4:
			return p
	return Vector3(HX - 1.0, WATER_Y, 0.0)


# --- HUD ----------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var row := UiKit.hbox()
	card.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	row.add_child(UiKit.icon("drop", "gold", 34.0))
	var l := UiKit.label("0", "number")
	row.add_child(l)
	score_labels[slot] = l
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join the game"]]))
		ui.add_child(join_prompt)
		UiKit.pin(join_prompt, Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	_refresh_hud()


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	var g := int(net.state_get("goal", 0))
	var txt := "%d/%d" % [score, g] if g > 0 and score < g else str(score)
	for slot in score_labels:
		var l: Label = score_labels[slot]
		if is_instance_valid(l):
			if l.text != txt:
				UiKit.pulse(l, 1.25)
			l.text = txt
			l.modulate = Color(1.0, 0.9, 0.4) if g > 0 and score >= g else Color.WHITE
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if vr_label != null:
		vr_label.text = "DUCKS %d/%d" % [score, g] if g > 0 and score < g else "DUCKS %d" % score
	_refresh_board()


func _refresh_board() -> void:
	if board == null:
		return
	var t := int(net.state_get("time", 0))
	var score := int(net.state_get("score", 0))
	var g := int(net.state_get("goal", 0))
	board.text = ("DUCKS %d/%d" % [score, g] if g > 0 and score < g else "DUCKS %d" % score) + "\n%d:%02d" % [t / 60, t % 60]


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


# --- Players (boats) ------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var b := _ensure_boat(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 0.4
		c.pitch = -0.6
		add_child(c)
		c.follow(b, 4.5, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("ducks", "Touch ducks, then sail to the plug!", {"to": slot, "icon": "drop"})
	awards.set_player(slot, party.name_of(slot))
	_refresh_group()
	_refresh_hud()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	if trains.has(slot):
		for id in trains[slot]:
			if duck_state.has(id):
				duck_state[id] = FLOAT
		trains.erase(slot)
	for d in [boats, cams]:
		var dict: Dictionary = d
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	boat_vel.erase(slot)
	net_target.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_group()
	_refresh_hud()


func _ensure_boat(slot: int) -> Node3D:
	if boats.has(slot) and is_instance_valid(boats[slot]):
		return boats[slot]
	var b := Node3D.new()
	b.name = "Boat%d" % slot
	var body := Node3D.new()
	body.name = "Body"
	b.add_child(body)
	body.add_child(MeshKit.instance(Art.boat(party.color_of(slot)), false))
	var cap := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": slot})
	cap.scale = Vector3.ONE * 0.2
	cap.position = Vector3(0.0, 0.12, 0.12)
	body.add_child(cap)
	add_child(b)
	b.position = _start_of(slot)
	HudKit.nameplate(b, party.name_of(slot), slot, 0.85, 0.16)
	boats[slot] = b
	boat_vel[slot] = Vector3.ZERO
	trains[slot] = []
	return b


func _refresh_group() -> void:
	if group_cam != null:
		group_cam.set_targets(boats.values())


## Local TV players steer with the left stick, relative to their camera. Waves (splash events)
## push these boats on the machine that steers them, so it stays instant.
func _move_local_boats(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "play")) == "play"
	for slot in party.local_slots():
		if not boats.has(slot):
			continue
		var b: Node3D = boats[slot]
		var v: Vector3 = boat_vel.get(slot, Vector3.ZERO)
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		if mv != Vector2.ZERO and split != null:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			v += dir * BOAT_ACCEL * delta
			if v.length() > BOAT_MAX and v.dot(dir) > 0.0:
				v = v.limit_length(maxf(BOAT_MAX, v.length() - BOAT_ACCEL * 2.0 * delta))
		v *= maxf(0.0, 1.0 - 1.4 * delta)
		var p := b.position + v * delta
		var lim := Vector2(HX - BOAT_R, HZ - BOAT_R)
		if absf(p.x) > lim.x:
			p.x = clampf(p.x, -lim.x, lim.x)
			if absf(v.x) > 1.2:
				sfx.play_at("bounce", p, -6.0, 0.8)
			v.x *= -0.5
		if absf(p.z) > lim.y:
			p.z = clampf(p.z, -lim.y, lim.y)
			if absf(v.z) > 1.2:
				sfx.play_at("bounce", p, -6.0, 0.8)
			v.z *= -0.5
		var bumped := _push_off_islands(p, v, BOAT_R)
		if bumped.size() > 0:
			p = bumped[0]
			if (v as Vector3).length() > 1.2:
				sfx.play_at("bounce", p, -8.0, 1.2)
			v = bumped[1]
		p.y = WATER_Y
		b.position = p
		boat_vel[slot] = v
		if Vector2(v.x, v.z).length() > 0.25:
			b.rotation.y = lerp_angle(b.rotation.y, atan2(v.x, v.z), minf(1.0, 6.0 * delta))
		if net.mode == "client" and send:
			net.send_state(b.position, b.rotation.y, 0.0, slot)
		if party.just_pressed(slot, "y"):
			net.request(slot, "toggle_view")


## Every machine: boats bob and lean on the waves.
func _animate_boats() -> void:
	for slot in boats:
		var b: Node3D = boats[slot]
		var body := b.get_node_or_null("Body") as Node3D
		if body == null:
			continue
		var k := float(slot) * 1.7
		body.position.y = sin(clock * 3.0 + k) * 0.03
		body.rotation.z = sin(clock * 2.2 + k) * 0.08
		body.rotation.x = sin(clock * 1.7 + k) * 0.05


## Host: a player on another machine moved.
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if boats.has(slot) and not party.is_local(slot):
		if not net_target.has(slot):
			(boats[slot] as Node3D).position = pos  # first update: no glide in from the spawn point
		net_target[slot] = [pos, yaw]


## Every machine: other machines' players glide to where their machine (or the host) says they are.
func _follow_remote(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	for slot in net_target:
		if not boats.has(slot) or party.is_local(slot):
			continue
		var a: Node3D = boats[slot]
		var t: Array = net_target[slot]
		a.position = a.position.lerp(t[0], k)
		a.rotation.y = lerp_angle(a.rotation.y, float(t[1]), k)


## Host: one machine left. core/party.gd frees just its seats (player_left for each removes their
## avatars, views and per-player state); only that machine's leftovers are dropped here.
func on_machine_left(peer: int) -> void:
	for slot in party.slots_of(peer):
		net_target.erase(slot)


## TV machine: the VR player as seen from here (only when the host has one), plus the little window into their view.
func _make_vr_avatar() -> void:
	vr_avatar = VrRig.Avatar.new()
	add_child(vr_avatar)
	if split != null:
		split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))


func on_request(_slot: int, action: String, _args: Array) -> void:
	match action:
		"toggle_view":
			net.state_set("shared", not bool(net.state_get("shared", false)))
		"next_round":
			if String(net.state_get("phase", "")) == "results" and results_t > 2.0:
				_start_round()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "Paused by %s" % Who.seat(self, by_slot)
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", "Wrist MENU: carry on", {"width": 1.1})
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
		(tv_banner.find_child("Why", true, false) as Label).text = why
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"shared":
			if split != null and String(net.state_get("phase", "play")) == "play":
				split.set_shared(bool(value))
		"score", "best", "goal":
			_refresh_hud()
		"bath":
			if net.mode == "client" and value != null:
				_apply_bath(value)
		"time":
			_refresh_board()
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
		"round":
			HudKit.banner(_all_huds(), "SPLASH!", "", {"duration": 1.5})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "SPLASH!", "", {"duration": 1.5, "sound": ""})
			sound("go", -4.0)
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------

func _start_round() -> void:
	for id in ducks.keys():
		_remove_duck(int(id))
	for slot in trains:
		trains[slot] = []
	held = -1
	awards.reset()
	time_left = round_time
	results_t = 0.0
	bath_round += 1
	if save != null:
		save.data.rounds = int(save.data.rounds) + 1
		save.mark_dirty()
	var bath := [bath_seed, bath_round, bath_daily]
	net.state_set("bath", bath)
	_apply_bath(bath)
	spot_i = 0
	round_t = 0.0
	goal_hit = false
	golden_caught = 0
	golden_left = (plan.golden as Array).duplicate()
	goal = maxi(2, int(round(float(plan.goal) * minf(1.0, round_time / BathGen.ROUND_SECS))))
	for i in 6:
		_spawn_duck(_next_spot(), Vector3.ZERO, FLOAT)
	net.state_set("goal", goal)
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)


func _end_round() -> void:
	var score := int(net.state_get("score", 0))
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)
	if bath_daily:
		save.data["daily_done"] = Seeded.today()  # a TODAY'S BATH round finished (the Trophy Hall's golden star)
		save.mark_dirty()
	_log_round("time")
	var toys := (save.data.toys as Array).size()
	var data := awards.results({"title": "SPLASHTASTIC!", "subtitle": "%d ducks down the plug!" % score,
		"style": "victory", "stats": [["GOAL", "%d/%d" % [mini(score, goal), goal]], ["TOYS", str(toys)], ["BEST", str(int(net.state_get("best", 0)))]],
		"score_format": "%d DUCKS"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	if held >= 0 and duck_state.has(held):
		duck_state[held] = FLY
	held = -1


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	sound("cheer", -4.0)
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(huds[-1], data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "next_round"))
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
		card.continued.connect(func() -> void: net.request(0, "next_round"))
		vr_results = card


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
	vr_results = null
	if split != null:
		split.set_shared(bool(net.state_get("shared", false)))


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- Game loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	clock += delta
	if split != null:
		_move_local_boats(delta)
	_follow_remote(delta)
	_animate_boats()
	_animate_props(delta)
	_update_bubbles(delta)
	_update_story(delta)
	_animate_family()
	if net.mode == "client":
		_animate_client_ducks(delta)
		return
	if vr_rig != null:
		_vr_hands(delta)
	_update_ducks(delta)
	if results_showing():
		results_t += delta
		if results_t > 12.0:
			_start_round()  # play again by itself
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
		if time_left <= 5.5 and time_left > 0.0:
			sound("countdown", -4.0)
	if time_left <= 0.0:
		sound("time_up")
		_end_round()
		return
	spawn_t -= delta
	if spawn_t <= 0.0:
		var n := _floating_count()
		spawn_t = 0.5 if n < 5 else 1.2
		if n < DUCKS_ON_WATER:
			var p := _next_spot()
			_spawn_duck(p + Vector3.UP * 2.5, Vector3(0.0, -1.0, 0.0), FLY)
	round_t += delta
	if not golden_left.is_empty() and round_t >= float(golden_left[0].x) * round_time:
		var g: Vector2 = golden_left.pop_front()
		var spots: Array = plan.spots
		var sp: Vector2 = spots[int(g.y) % spots.size()]
		var gid := _spawn_duck(Vector3(sp.x, WATER_Y + 2.5, sp.y), Vector3(0.0, -1.0, 0.0), FLY, true)
		duck_by[gid] = -1
		_story_for_all("A golden duck!", "mamaduck", Color(1.0, 0.75, 0.1))
	_pick_up_and_deliver()


func _animate_props(delta: float) -> void:
	drain_spin.rotation.y -= delta * 3.0
	drain_arrow.position.y = drain.y + 0.9 + absf(sin(clock * 3.0)) * 0.25
	drain_arrow.rotation.y += delta * 1.5
	tap_handle.rotation.y = lerp_angle(tap_handle.rotation.y, 0.0, minf(1.0, delta * 2.0)) if tap_cd <= 0.0 else tap_handle.rotation.y + delta * 8.0
	tap_cd -= delta
	splash_cd[0] -= delta
	splash_cd[1] -= delta
	water_mat.set_shader_parameter("now", clock)


func _floating_count() -> int:
	var n := 0
	for id in duck_state:
		if int(duck_state[id]) != SINK:
			n += 1
	return n


# --- Ducks (host / local simulate; the TV machine mirrors them) ----------------------------------

func _spawn_duck(pos: Vector3, vel: Vector3, state: int, gold: bool = false) -> int:
	next_duck += 1
	if gold:
		duck_gold[next_duck] = true
	_make_duck(next_duck, pos)
	duck_vel[next_duck] = vel
	duck_state[next_duck] = state
	duck_t[next_duck] = 0.0
	duck_by[next_duck] = -1
	duck_cd[next_duck] = 0.0
	return next_duck


func _make_duck(id: int, pos: Vector3) -> Node3D:
	var d := Node3D.new()
	var mi := MeshKit.instance(Art.golden_duck() if duck_gold.has(id) else Art.duck(), false)
	mi.name = "Mesh"
	d.add_child(mi)
	add_child(d)
	d.position = pos
	d.rotation.y = randf() * TAU
	d.scale = Vector3.ONE * 1.3
	ducks[id] = d
	return d


func _remove_duck(id: int) -> void:
	if ducks.has(id):
		(ducks[id] as Node).queue_free()
	for dict in [ducks, duck_vel, duck_state, duck_t, duck_by, duck_cd, duck_gold]:
		(dict as Dictionary).erase(id)
	if held == id:
		held = -1


func _update_ducks(delta: float) -> void:
	for id in ducks.keys():
		var d: Node3D = ducks[id]
		var st: int = duck_state[id]
		var v: Vector3 = duck_vel[id]
		duck_t[id] = float(duck_t[id]) + delta
		duck_cd[id] = float(duck_cd[id]) - delta
		match st:
			FLOAT:
				v *= maxf(0.0, 1.0 - 1.1 * delta)
				var to_drain := drain - d.position
				to_drain.y = 0.0
				if to_drain.length() < 1.3:  # a gentle whirlpool
					v += (to_drain.normalized() + Vector3(-to_drain.z, 0.0, to_drain.x).normalized() * 0.6) * 0.7 * delta
				var p := d.position + v * delta
				v = _bounce_walls(p, v)
				p.x = clampf(p.x, -HX + DUCK_R, HX - DUCK_R)
				p.z = clampf(p.z, -HZ + DUCK_R, HZ - DUCK_R)
				var bumped := _push_off_islands(p, v, DUCK_R)
				if bumped.size() > 0:
					p = bumped[0]
					v = bumped[1]
				p.y = WATER_Y + sin(clock * 2.5 + float(id)) * 0.025
				d.position = p
				if v.length() > 0.3:
					d.rotation.y = lerp_angle(d.rotation.y, atan2(v.x, v.z), minf(1.0, 4.0 * delta))
				d.rotation.z = sin(clock * 2.0 + float(id)) * 0.1
				if Vector2(to_drain.x, to_drain.z).length() < DRAIN_R * 0.75:
					_sink(int(id), int(duck_by[id]))
			HELD:
				if vr_rig != null:
					d.position = vr_rig.hand_point(VrRig.RIGHT) + Vector3.DOWN * 0.12
					d.rotation.y = vr_rig.head_yaw() + PI
				v = Vector3.ZERO
			FLY:
				v.y -= 9.8 * delta
				var p := d.position + v * delta
				v = _bounce_walls(p, v)
				p.x = clampf(p.x, -HX + DUCK_R, HX - DUCK_R)
				p.z = clampf(p.z, -HZ + DUCK_R, HZ - DUCK_R)
				d.rotation.x += delta * 6.0
				if p.y <= WATER_Y and v.y < 0.0:
					p.y = WATER_Y
					d.rotation.x = 0.0
					var spd := v.length()
					splash(p, Vector3(v.x, 0.0, v.z) * 0.25, clampf(spd / 6.0, 0.3, 1.0))
					v = Vector3(v.x, 0.0, v.z) * 0.35
					duck_state[id] = FLOAT
					duck_t[id] = 0.0
					var fd := Vector2(p.x - drain.x, p.z - drain.z).length()
					if fd < DRAIN_R * 1.5 and int(duck_by[id]) >= 0:
						HudKit.popup(self, p + Vector3.UP * 0.6, "SPLASH SHOT!", {"color": "gold", "size": 1.3})
						_sink(int(id), int(duck_by[id]))
				d.position = p
			SINK:
				var t: float = duck_t[id]
				if t >= 0.0:
					var a := t * 12.0
					var r := maxf(0.0, DRAIN_R * 0.6 * (1.0 - t / 0.7))
					d.position = drain + Vector3(cos(a) * r, -t * 0.3, sin(a) * r)
					d.rotation.y = -a
					d.scale = Vector3.ONE * 1.3 * maxf(0.05, 1.0 - t / 0.8)
					if t > 0.8:
						_remove_duck(int(id))
						continue
		duck_vel[id] = v
	# Towed ducks follow their boat like a little train.
	for slot in trains:
		if not boats.has(slot):
			continue
		var leader: Vector3 = (boats[slot] as Node3D).position
		var gap := 0.55
		for id in trains[slot]:
			if not ducks.has(id):
				continue
			var d: Node3D = ducks[id]
			var off := d.position - leader
			off.y = 0.0
			if off.length() < 0.01:
				off = Vector3.BACK * gap
			var target := leader + off.normalized() * gap
			target.y = WATER_Y + sin(clock * 4.0 + float(id)) * 0.03
			d.position = d.position.lerp(target, minf(1.0, 12.0 * delta))
			var face := leader - d.position
			if face.length() > 0.05:
				d.rotation.y = atan2(face.x, face.z)
			leader = d.position
			gap = 0.38


func _bounce_walls(p: Vector3, v: Vector3) -> Vector3:
	if absf(p.x) > HX - DUCK_R and signf(v.x) == signf(p.x):
		v.x *= -0.6
	if absf(p.z) > HZ - DUCK_R and signf(v.z) == signf(p.z):
		v.z *= -0.6
	return v


## Boats scoop up free ducks they touch, and empty their train into the plug-hole.
func _pick_up_and_deliver() -> void:
	for slot in boats:
		var b: Node3D = boats[slot]
		var train: Array = trains.get(slot, [])
		for id in train.duplicate():
			if not ducks.has(id) or int(duck_state[id]) != TOW:
				train.erase(id)
		if train.size() < MAX_TRAIN:
			for id in ducks:
				if int(duck_state[id]) != FLOAT:
					continue
				var d: Node3D = ducks[id]
				if Vector2(d.position.x - b.position.x, d.position.z - b.position.z).length() < BOAT_R + DUCK_R + 0.12:
					duck_state[id] = TOW
					train.append(id)
					net.event("quack", [d.position, int(slot)])
					quack(d.position, int(slot))
					if train.size() >= MAX_TRAIN:
						break
		trains[slot] = train
		if not train.is_empty() and Vector2(b.position.x - drain.x, b.position.z - drain.z).length() < DRAIN_R + BOAT_R + 0.15:
			var n := 0
			var i := 0
			for id in train:
				n += 3 if duck_gold.has(id) else 1
				_sink(int(id), int(slot), -0.12 * i, false)
				i += 1
			trains[slot] = []
			_big_score(n, int(slot))


## A duck goes down the plug-hole: +1 for the team.
func _sink(id: int, by: int, delay: float = 0.0, popup: bool = true) -> void:
	if not duck_state.has(id) or int(duck_state[id]) == SINK:
		return
	duck_state[id] = SINK
	duck_t[id] = delay
	duck_vel[id] = Vector3.ZERO
	if held == id:
		held = -1
	var worth := 3 if duck_gold.has(id) else 1
	if worth > 1:
		golden_caught += 1
		if save != null:
			save.data.golden = int(save.data.golden) + 1
	total_ducks += worth
	net.state_set("total", total_ducks)
	if by >= 0:
		awards.add(by, "score", worth)
	net.state_set("score", int(net.state_get("score", 0)) + worth)
	if save != null:
		save.data.ducks = int(save.data.ducks) + worth
		save.mark_dirty()
	if popup:
		_big_score(worth, by)
	_check_goal()


## A gulp, sparkles and "+n" over the plug-hole, on every machine.
func _big_score(n: int, by: int) -> void:
	gulp(n, by)
	net.event("gulp", [n, by])


func gulp(n: int, by: int) -> void:
	var col: Color = party.color_of(by) if by > 0 else Color(1.0, 0.85, 0.2)
	HudKit.score(self, drain + Vector3.UP * 0.8, n, {"color": col, "size": 1.0 + 0.25 * n})
	burst(drain + Vector3.UP * 0.2, col, 10 + n * 6, 3.0)
	sfx.play_at("kaching" if n > 1 else "coin", drain, 0.0, 1.0 + 0.05 * n)
	if n >= 3:
		sfx.play_at("party_horn", drain, -3.0)
	var tw := create_tween()
	drain_arrow.scale = Vector3.ONE * 1.6
	tw.tween_property(drain_arrow, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if boats.has(by):
		_squash(boats[by] as Node3D)
	if vr_rig != null:
		vr_rig.pulse(VrRig.RIGHT, 0.3, 0.05)


## A duck joins a boat's train: squeak and a bounce.
func quack(pos: Vector3, slot: int) -> void:
	sfx.play_at("honk", pos, -4.0, 1.7 + randf() * 0.3)
	burst(pos + Vector3.UP * 0.2, Color(1.0, 0.9, 0.3), 6, 1.5)
	if boats.has(slot):
		_squash(boats[slot] as Node3D)


func _squash(n: Node3D) -> void:
	var body := n.get_node_or_null("Body") as Node3D
	if body == null:
		return
	body.scale = Vector3(1.25, 0.75, 1.25)
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# --- VR hands -------------------------------------------------------------------------------

func _vr_hands(_delta: float) -> void:
	var playing := not results_showing()
	for h in [VrRig.LEFT, VrRig.RIGHT]:
		var p := vr_rig.hand_point(h)
		var inside := absf(p.x) < HX and absf(p.z) < HZ
		var wet := inside and p.y < WATER_Y + 0.04
		var v := vr_rig.hand_velocity(h)
		if wet and splash_cd[h] <= 0.0:
			var spd := v.length()
			if spd > 0.7 or (not hand_was_wet[h] and spd > 0.35):
				splash_cd[h] = 0.2
				var strength := clampf(spd / 3.0, 0.3, 1.3)
				splash(Vector3(p.x, WATER_Y, p.z), Vector3(v.x, 0.0, v.z).limit_length(4.0) * 0.8, strength)
				vr_rig.pulse(h, 0.2 + 0.3 * minf(1.0, strength), 0.05)
				hints.hint("vr_grab", "Trigger: grab a duck!", {"to": "vr", "icon": "drop"})
		hand_was_wet[h] = wet
		# Bonk a duck with a glove: it squeaks and scoots.
		for id in ducks:
			var st: int = duck_state[id]
			if (st != FLOAT and st != TOW) or float(duck_cd[id]) > 0.0 or id == held:
				continue
			var d: Node3D = ducks[id]
			if p.distance_to(d.position + Vector3.UP * 0.12) < 0.2:
				duck_cd[id] = 0.5
				quack(d.position, -1)
				net.event("quack", [d.position, -1])
				if st == FLOAT:
					duck_vel[id] = (duck_vel[id] as Vector3) + Vector3(v.x, 0.0, v.z).limit_length(3.0)
					duck_by[id] = 0
		# Touch the tap: a fresh duck pops out.
		if tap_cd <= 0.0 and p.distance_to(tap_handle.position + Vector3.UP * 0.1) < 0.2:
			tap_cd = 1.5
			vr_rig.pulse(h, 0.5, 0.08)
			if playing and _floating_count() < DUCKS_ON_WATER + 6:
				var spout := Vector3(TAP.x, RIM_Y + 0.3, TAP.z - 0.45)
				var id := _spawn_duck(spout, Vector3(randf_range(-0.6, 0.6), 1.5, -1.6), FLY)
				duck_by[id] = 0
			tap(Vector3(TAP.x, RIM_Y + 0.3, TAP.z - 0.45))
			net.event("tap", [Vector3(TAP.x, RIM_Y + 0.3, TAP.z - 0.45)])
	if not playing:
		return
	# Grab and throw with the right glove.
	if held < 0 and vr_rig.trigger_pressed():
		var hp := vr_rig.hand_point(VrRig.RIGHT)
		var best := -1
		var bd := GRAB_R
		for id in ducks:
			var st: int = duck_state[id]
			if st == SINK or st == HELD:
				continue
			var dd := hp.distance_to((ducks[id] as Node3D).position + Vector3.UP * 0.1)
			if dd < bd:
				bd = dd
				best = int(id)
		if best >= 0:
			for slot in trains:
				(trains[slot] as Array).erase(best)
			held = best
			duck_state[best] = HELD
			vr_rig.pulse(VrRig.RIGHT, 0.6, 0.08)
			sfx.play_at("honk", hp, 0.0, 2.0)
			net.event("quack", [hp, -1])
			var d: Node3D = ducks[best]
			d.scale = Vector3(1.6, 1.0, 1.6)
			create_tween().tween_property(d, "scale", Vector3.ONE * 1.3, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			hints.hint("vr_throw", "Throw it in the plug!", {"to": "vr", "icon": "drop"})
	elif held >= 0 and not vr_rig.trigger_down():
		var v := vr_rig.hand_velocity(VrRig.RIGHT) * 1.4
		duck_vel[held] = v.limit_length(10.0)
		duck_state[held] = FLY
		duck_by[held] = 0
		duck_t[held] = 0.0
		if v.length() > 1.5:
			sfx.play_at("whoosh", vr_rig.hand_point(VrRig.RIGHT), -4.0)
		held = -1


## A splash: waves push nearby boats and ducks, droplets fly, the water ripples. Host / local
## run it and send it to the TV machine, which pushes its own boats the same way.
func splash(pos: Vector3, push: Vector3, strength: float) -> void:
	wave(pos, push, strength)
	net.event("splash", [pos, push, strength])


func wave(pos: Vector3, push: Vector3, strength: float) -> void:
	splashes += 1
	for slot in party.local_slots():
		if boats.has(slot):
			var b: Node3D = boats[slot]
			var f := _wave_force(b.position, pos, push, strength)
			if f != Vector3.ZERO:
				boat_vel[slot] = (boat_vel.get(slot, Vector3.ZERO) as Vector3) + f
				_squash(b)
	if net.mode != "client":
		for id in ducks:
			if int(duck_state[id]) == FLOAT:
				var f := _wave_force((ducks[id] as Node3D).position, pos, push, strength)
				if f != Vector3.ZERO:
					duck_vel[id] = (duck_vel[id] as Vector3) + f * 1.3
					duck_by[id] = 0
	ripples.pop_front()
	ripples.append(Vector4(pos.x, pos.z, clock, strength))
	water_mat.set_shader_parameter("rip", ripples)
	burst(pos + Vector3.UP * 0.05, Color(0.75, 0.92, 1.0), int(8 + strength * 14), 2.0 + strength * 2.0)
	sfx.play_at("splash", pos, -8.0 + strength * 6.0, 0.9 + randf() * 0.3)
	for i in BUBBLES:
		if bubble_life[i] >= 0.0 and Vector2(bubble_pos[i].x - pos.x, bubble_pos[i].z - pos.z).length() < 0.5 * strength + 0.2:
			bubble_life[i] = -2.0 - randf() * 3.0


func _wave_force(at: Vector3, from: Vector3, push: Vector3, strength: float) -> Vector3:
	var off := at - from
	off.y = 0.0
	var dist := off.length()
	if dist > WAVE_R:
		return Vector3.ZERO
	var fall := 1.0 - dist / WAVE_R
	var radial := off.normalized() if dist > 0.01 else Vector3.ZERO
	return (push + radial * strength * 2.2) * fall


## Water gushes from the tap (both machines).
func tap(pos: Vector3) -> void:
	sfx.play_at("splash", pos, -2.0, 1.4)
	sfx.play_at("honk", pos, -6.0, 2.2)
	burst(pos, Color(0.6, 0.85, 1.0), 16, 2.5)
	tap_cd = 1.5


## Droplets / sparkles (cheap one-shot particles).
func burst(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 50.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.mesh = ResCache.get_or_make("bb_drop_%s" % color.to_html(false), func() -> Resource:  # splashes are frequent
		var sm := SphereMesh.new()
		sm.radius = 0.04
		sm.height = 0.08
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = MeshKit.material(color, 0.6)
		return sm)
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Every machine: soap bubbles wobble and drift; gloves and boats pop them.
func _update_bubbles(delta: float) -> void:
	var pokers: Array[Vector3] = []
	if vr_rig != null:
		pokers.append(vr_rig.hand_point(VrRig.LEFT))
		pokers.append(vr_rig.hand_point(VrRig.RIGHT))
	for slot in boats:
		pokers.append((boats[slot] as Node3D).position + Vector3.UP * 0.1)
	var popped := 0
	for i in BUBBLES:
		var life := bubble_life[i] + delta
		var p := bubble_pos[i]
		if bubble_life[i] < 0.0 and life >= 0.0:
			p = _random_water_spot(0.4)  # respawn somewhere else
		p.x = clampf(p.x + sin(clock * 0.3 + i) * 0.05 * delta, -HX + 0.3, HX - 0.3)
		p.z = clampf(p.z + cos(clock * 0.25 + i * 1.3) * 0.05 * delta, -HZ + 0.3, HZ - 0.3)
		var s := 0.0
		if life >= 0.0:
			var grow := minf(1.0, life * 2.0)
			var base := 0.7 + 0.8 * fmod(float(i) * 0.618, 1.0)
			s = base * grow * (1.0 + sin(clock * 3.0 + i) * 0.08)
			for q in pokers:
				if q.distance_to(p + Vector3.UP * 0.12 * base) < 0.12 * base + 0.1:
					life = -2.0 - randf() * 4.0
					s = 0.0
					popped += 1
					break
		bubble_life[i] = life
		bubble_pos[i] = p
		var y := WATER_Y + 0.08 * maxf(s, 0.01)
		bubble_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s * (1.0 + sin(clock * 4.0 + i) * 0.06), s) + Vector3.ONE * 0.001), Vector3(p.x, y, p.z)))
	if popped > 0:
		sfx.play("pop", -10.0, 1.0 + randf() * 0.5)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	var sts := PackedByteArray()
	for id in ducks:
		ids.append(int(id))
		pos.append((ducks[id] as Node3D).position)
		sts.append(int(duck_state[id]) | (16 if duck_gold.has(id) else 0))  # 16: a golden duck
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	# Every player avatar (slot, position, yaw): each machine sees the other machines' players.
	var av_slots := PackedByteArray()
	var av_pos := PackedVector3Array()
	var av_yaw := PackedFloat32Array()
	for slot in boats:
		var a: Node3D = boats[slot]
		av_slots.append(int(slot))
		av_pos.append(a.position)
		av_yaw.append(a.rotation.y)
	return [pose, ids, pos, sts, av_slots, av_pos, av_yaw]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var av_slots: PackedByteArray = s[4]
	var av_pos: PackedVector3Array = s[5]
	var av_yaw: PackedFloat32Array = s[6]
	for i in av_slots.size():
		var slot: int = av_slots[i]
		if boats.has(slot) and not party.is_local(slot):
			if not net_target.has(slot):
				(boats[slot] as Node3D).position = av_pos[i]
			net_target[slot] = [av_pos[i], av_yaw[i]]
	var ids: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var sts: PackedByteArray = s[3]
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		if not ducks.has(id):
			if int(sts[i]) & 16:
				duck_gold[id] = true
			_make_duck(id, pos[i])
			duck_vel[id] = Vector3.ZERO
		duck_vel[id] = pos[i]  # the TV machine keeps the target position here
		duck_state[id] = int(sts[i]) & 15
	for id in ducks.keys():
		if not seen.has(id):
			(ducks[id] as Node).queue_free()
			ducks.erase(id)
			duck_vel.erase(id)
			duck_state.erase(id)
			duck_gold.erase(id)


## TV machine: glide each duck to its snapshot position, face where it goes, shrink when sinking.
func _animate_client_ducks(delta: float) -> void:
	for id in ducks:
		var d: Node3D = ducks[id]
		var target: Vector3 = duck_vel.get(id, d.position)
		var step := target - d.position
		d.position = d.position.lerp(target, minf(1.0, 15.0 * delta))
		if Vector2(step.x, step.z).length() > 0.01:
			d.rotation.y = lerp_angle(d.rotation.y, atan2(step.x, step.z), minf(1.0, 6.0 * delta))
		var sinking := int(duck_state.get(id, FLOAT)) == SINK
		d.scale = d.scale.lerp(Vector3.ONE * (0.1 if sinking else 1.3), minf(1.0, (3.0 if sinking else 10.0) * delta))


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"splash":
			wave(args[0], args[1], float(args[2]))
		"quack":
			quack(args[0], int(args[1]))
		"gulp":
			gulp(int(args[0]), int(args[1]))
		"tap":
			tap(args[0])
		"family":
			_build_family(args[0], int(args[1]), bool(args[2]))
		"cheer":
			cheer()
		"story":
			_story(args[0], args[1], args[2])


# --- The seeded bath and Mama Duck's family ------------------------------------------------------

## Host / local: a new bath (once per game). Count the play-day (a new duckling), pick the bath seed (TODAY'S BATH
## first each day), put the toys and ducklings on the rims and say hello.
func _start_bath() -> void:
	var today := Seeded.today()
	var new_day := String(save.data.last_day) != today
	if new_day:
		save.data.days = int(save.data.days) + 1
		save.data.last_day = today
	save.data.baths = int(save.data.baths) + 1
	bath_daily = String(save.data.daily) != today
	bath_seed = BathGen.daily_seed() if bath_daily else Seeded.fresh_seed()
	if OS.has_environment("BB_SEED"):
		bath_seed = int(OS.get_environment("BB_SEED"))
	if bath_daily:
		save.data.daily = today  # (one TODAY'S BATH a day)
	save.mark_dirty()
	bath_round = int(OS.get_environment("BB_ROUND")) - 1 if OS.has_environment("BB_ROUND") else 0  # tests: start at a later round
	print("Bubble Bath: bath seed %d%s | %d toys, day %d" % [bath_seed, " (TODAY'S BATH)" if bath_daily else "",
		(save.data.toys as Array).size(), int(save.data.days)])
	_build_family(save.data.toys, int(save.data.days), int(save.data.goals) >= BathGen.CROWN_TOYS)
	_send_family()
	story_t = 6.5  # after the intro card
	_story_for_all("Hi! I'm Mama Duck!", "mamaduck", MAMA_COLOR)
	if bath_daily:
		_story_for_all("TODAY'S BATH!", "bathtub", Color(1.0, 0.85, 0.3))
	if new_day and int(save.data.days) > 1:
		_story_for_all("A new duckling!", "duckling", Color(1.0, 0.9, 0.4))


## Every machine: build round bath[1] of bath seed bath[0] (the plug, the sponge islands, the bubble colour) and, on
## a new round, put this machine's boats at their starts.
func _apply_bath(bath: Variant) -> void:
	if not (bath is Array) or (bath as Array).size() < 3:
		return
	var new_round := plan.is_empty() or int(plan.n) != int(bath[1]) or bath_seed != int(bath[0])
	bath_seed = int(bath[0])
	bath_daily = bool(bath[2])
	plan = BathGen.plan(bath_seed, int(bath[1]))
	var d: Vector2 = plan.drain
	drain = Vector3(d.x, WATER_Y, d.y)
	if drain_spin != null:
		drain_spin.position = drain + Vector3.UP * 0.02
		drain_arrow.position = Vector3(drain.x, drain_arrow.position.y, drain.z)
	islands = plan.islands
	for c in island_root.get_children():
		island_root.remove_child(c)
		c.queue_free()
	for o in islands:
		var mi := MeshKit.instance(Art.sponge(float(o.z)), false)
		mi.position = Vector3(o.x, WATER_Y - 0.07, o.y)
		island_root.add_child(mi)
	var m := bubble_mm.mesh as SphereMesh
	if m != null and m.material is StandardMaterial3D:
		(m.material as StandardMaterial3D).emission = BUBBLE_TINTS[int(plan.tint) % BUBBLE_TINTS.size()]
	if new_round:
		for slot in party.local_slots():
			if boats.has(slot):
				(boats[slot] as Node3D).position = _start_of(slot)
				boat_vel[slot] = Vector3.ZERO
		if net.mode != "client":
			var n := int(plan.n)
			if n == 2:
				_story_for_all("A sponge island!", "sponge", Color(0.95, 0.85, 0.3))
			elif n == 3:
				_story_for_all("The plug moved!", "bathtub", Color(0.45, 0.85, 1.0))
			elif n > 3 and n % 3 == 1:
				_story_for_all("More islands!", "sponge", Color(0.95, 0.85, 0.3))
			_story_for_all("%d ducks, please!" % goal_for_story(), "mamaduck", MAMA_COLOR)


## The goal Mama Duck asks for at the start of a round (the round's plan, scaled for short test rounds).
func goal_for_story() -> int:
	return maxi(2, int(round(float(plan.goal) * minf(1.0, round_time / BathGen.ROUND_SECS))))


## Where a boat starts this round.
func _start_of(slot: int) -> Vector3:
	var starts: Array = plan.get("starts", [])
	if starts.is_empty():
		var a := slot * 1.3
		return Vector3(cos(a) * 2.5, WATER_Y, sin(a) * 1.6)
	var s: Vector2 = starts[posmod(slot, starts.size())]
	return Vector3(s.x, WATER_Y, s.y)


## Host / local: the next duck spot of this round's plan (in order, round and round).
func _next_spot() -> Vector3:
	var spots: Array = plan.get("spots", [])
	if spots.is_empty():
		return _random_water_spot(0.5)
	var s: Vector2 = spots[spot_i % spots.size()]
	spot_i += 1
	return Vector3(s.x, WATER_Y, s.y)


## Push a boat / duck of radius r off the sponge islands: [new position, new velocity], or [] when clear.
func _push_off_islands(p: Vector3, v: Vector3, r: float) -> Array:
	var hit := false
	for o in islands:
		var off := Vector2(p.x - o.x, p.z - o.y)
		var need := float(o.z) + r
		if off.length() < need:
			var nrm := off.normalized() if off.length() > 0.001 else Vector2.RIGHT
			p.x = o.x + nrm.x * need
			p.z = o.y + nrm.y * need
			var n3 := Vector3(nrm.x, 0.0, nrm.y)
			var into := v.dot(n3)
			if into < 0.0:
				v -= n3 * into * 1.5  # bounce off the squishy sponge
			hit = true
	return [p, v] if hit else []


## Host / local: the team reached Mama Duck's goal: a toy for the rim (once a round).
func _check_goal() -> void:
	if goal_hit or goal <= 0 or int(net.state_get("score", 0)) < goal or results_showing():
		return
	goal_hit = true
	var kind := BathGen.toy_for(int(save.data.goals))
	save.data.goals = int(save.data.goals) + 1
	var list: Array = save.data.toys
	list.append([kind, int(save.data.days), bath_daily])
	while list.size() > BathGen.TOY_KEEP:
		list.pop_front()
	save.mark_dirty()
	_build_family(list, int(save.data.days), int(save.data.goals) >= BathGen.CROWN_TOYS)
	_send_family()
	net.event("cheer", [])
	cheer()
	_story_for_all("Yay! Quack quack!", "mamaduck", MAMA_COLOR)
	_story_for_all(TOY_LINES.get(kind, "A new toy!"), kind, Color(1.0, 0.85, 0.3) if bath_daily else TOY_COLORS.get(kind, Color.WHITE))
	if int(save.data.goals) == BathGen.CROWN_TOYS:
		_story_for_all("A crown for me!", "crown", Color(1.0, 0.85, 0.25))


## Every machine: Mama Duck bounces and the toys sparkle when the goal is reached.
func cheer() -> void:
	sfx.play("party_horn", -2.0)
	sfx.play_at("honk", mama.position, 0.0, 1.2)
	burst(mama.position + Vector3.UP * 0.8, Color(1.0, 0.85, 0.3), 30, 3.0)
	mama.scale = Vector3(3.8, 2.6, 3.8)
	create_tween().tween_property(mama, "scale", Vector3.ONE * 3.2, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _send_family() -> void:
	if net != null and net.mode == "host" and save != null:
		net.event("family", [(save.data.toys as Array).duplicate(true), int(save.data.days), int(save.data.goals) >= BathGen.CROWN_TOYS])


## Every machine: Mama Duck (crowned with ten toys), a duckling per play-day beside her and the toys on the side rim.
func _build_family(toys: Array, days: int, crowned: bool) -> void:
	var key := var_to_str([toys, days, crowned])
	if key == family_key:
		return
	var grown := family_key != "" and toys.size() > 0
	family_key = key
	for c in mama.get_children():
		mama.remove_child(c)
		c.queue_free()
	mama.add_child(MeshKit.instance(Art.mama_duck(crowned), false))
	for c in family_root.get_children():
		family_root.remove_child(c)
		c.queue_free()
	for i in BathGen.ducklings(days):
		var d := MeshKit.instance(Art.duck(), false)
		d.name = "Duckling%d" % i
		d.position = BathGen.duckling_slot(i, RIM_Y)
		d.scale = Vector3.ONE * 0.9
		family_root.add_child(d)
	for i in mini(toys.size(), BathGen.TOY_KEEP):
		var e: Array = toys[i]
		var t := MeshKit.instance(Art.toy(String(e[0]), bool(e[2])), false)
		t.name = "Toy%d" % i
		t.position = BathGen.toy_slot(i, RIM_Y)
		t.rotation.y = -PI * 0.5  # facing into the tub
		t.scale = Vector3.ONE * 1.8
		family_root.add_child(t)
		if grown and i == toys.size() - 1:
			t.scale = Vector3.ONE * 0.05
			t.create_tween().tween_property(t, "scale", Vector3.ONE * 1.8, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Every machine: Mama Duck and the ducklings bob; the sponge islands squish gently.
func _animate_family() -> void:
	if mama == null:
		return
	mama.rotation.z = sin(clock * 1.3) * 0.06
	var i := 0
	for c in family_root.get_children():
		if c.name.begins_with("Duckling"):
			(c as Node3D).position.y = RIM_Y + absf(sin(clock * 3.0 + i * 0.7)) * 0.04
			i += 1
	var k := 0
	for c in island_root.get_children():
		(c as Node3D).position.y = WATER_Y - 0.07 + sin(clock * 1.6 + k) * 0.02
		k += 1


## Host / local: a story card on every machine.
func _story_for_all(line: String, pic: String, color: Color) -> void:
	_story(line, pic, color)
	if net != null and net.mode == "host":
		net.event("story", [line, pic, color])


func _story(line: String, pic: String, color: Color) -> void:
	if story_queue.size() < 4:
		story_queue.append([line, pic, color])


func _update_story(delta: float) -> void:
	story_t -= delta
	if story_t > 0.0 or story_queue.is_empty():
		return
	var b: Array = story_queue.pop_front()
	story_t = 2.6
	var opts := {"who": MAMA, "line": b[0], "pic": b[1], "color": b[2], "duration": 2.4}
	var views: Array = []
	for h in _all_huds():
		if (h as Control).is_visible_in_tree():
			views.append(h)
	if not views.is_empty():
		StoryCard.show(views, opts)
	if vr_rig != null:
		StoryCard.show_vr(self, vr_rig.camera, opts)
	if mama != null:
		_squash_mama()


func _squash_mama() -> void:
	sfx.play_at("honk", mama.position, -8.0, 1.0)
	mama.scale = Vector3(3.5, 2.9, 3.5)
	create_tween().tween_property(mama, "scale", Vector3.ONE * 3.2, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## One RUN line per round ("time") and on quit.
func _log_round(end: String) -> void:
	if net == null or net.mode == "client" or plan.is_empty():
		return
	Telemetry.run(GAME_ID, {"end": end, "round": bath_round, "seed": bath_seed, "daily": bath_daily, "secs": snappedf(round_t, 0.1),
		"score": int(net.state_get("score", 0)), "goal": goal, "goal_hit": goal_hit, "golden": golden_caught,
		"golden_plan": (plan.golden as Array).size(), "islands": islands.size(), "drain": [snappedf(drain.x, 0.01), snappedf(drain.z, 0.01)],
		"boats": boats.size(), "vr": vr_rig != null, "net": net.mode, "splashes": splashes,
		"toys": (save.data.toys as Array).size(), "goals": int(save.data.goals), "days": int(save.data.days)})


func _exit_tree() -> void:
	if ready_to_play and not results_showing() and round_t > 3.0:
		_log_round("quit")
