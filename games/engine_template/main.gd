extends Node3D
## ENGINE TEMPLATE ("Star Catch"): the smallest complete game on the shared engine. Copy this folder
## to start a new game, then replace the gameplay. Read docs/engine/systems.md and
## docs/engine/presentation.md alongside it.
## Stars pop up around a little park and everyone catches them: TV players run into them, the VR
## player touches them with a glove. Rounds last `round_time` seconds and end with a results screen
## (awards for everyone) on the TV and a summary card in VR; A / the trigger starts the next round.
## Y on a controller swaps between split screen and one shared view. The best score is saved.
## Systems: net modes (local / host / TV machine), core/party.gd drop-in seats, core/split_view.gd views
## + VR bubble, core/camera_rig.gd follow + group cameras, core/vr_rig.gd (or its Avatar on the TV),
## the state store (score, time, phase, results), net.request (TV -> host), snapshots, events, core/save.gd.
## Presentation: core/sky_kit.gd, core/mesh_kit.gd props, core/creatures.gd players, core/music.gd
## moods, core/sfx.gd, core/ui_kit.gd HUD roots, core/hud_kit.gd (popups, timer, toasts, banners),
## core/hints.gd (how-to-play cards + hints), core/awards.gd (results).

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
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")

const GAME_ID := "engine_template"
const ARENA := 8.0
const SPEED := 4.5
const MAX_STARS := 6
const LOOKS: Array[String] = ["knight", "mage", "archer", "bard", "pirate", "chef", "astronaut"]
const INTRO := {
	"title": "STAR CATCH",
	"goal": "Catch as many falling stars as you can before the clock runs out!",
	"vr": {"role": "THE STAR GIANT", "controls": [["GLOVES", "Touch a star"], ["L-STICK", "Walk"], ["R-STICK", "Turn"]]},
	"tv": {"role": "THE STAR RUNNERS", "controls": [["L-STICK", "Run"], ["R-STICK", "Look"], ["Y", "Split / shared view"],
		["START", "Pause"]], "tips": ["Run into the gold stars!"]},
}

var round_time := 60.0  ## seconds per round (bots shorten it before adding the game)

# --- The networking contract (see docs/engine/systems.md) ---
var net: Node
var ready_to_play := false
# --- Engine modules (these member names are what core/ looks for) ---
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var hints: Hints
var awards: Awards
var sky: SkyKit.SkyRig

var avatars := {}  # slot -> Node3D (a Creatures.humanoid): TV players (every machine)
var last_pos := {}  # slot -> Vector3, to animate walking on every machine
var cams := {}  # slot -> CameraRig: one per local view
var group_cam: CameraRig  # the shared view's camera
var huds := {}  # slot -> UiKit root (-1 = the shared view's)
var score_labels := {}  # slot -> Label
var timers := {}  # slot -> HudKit.TimerPill
var join_prompt: Control  # "Press A to join" on the shared view
var vr_avatar: VrRig.Avatar  # TV machine: the VR player as seen from the TV
var vr_label: Label3D  # host: score on the back of the VR player's left glove
var vr_banner: Node3D  # host: "PAUSED" card in front of the VR player
var tv_banner: Control  # TV: "PAUSED" card over every view
var results_ui: Control  # TV: the results screen (on the shared view)
var vr_results: Node  # host: the VR results card
var stars := {}  # id -> Node3D
var next_star := 0
var star_t := 0.0
var send_t := 0.0  # TV machine: positions go to the host 30 times a second
var time_left := 0.0  # host / local: the round clock
var results_t := 0.0
var total_caught := 0  # host / local: stars caught over all rounds


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
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = {"best": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)  # synthesise every sound in the background now: no hitch on first use
	music = MusicScript.new()
	add_child(music)
	music.play_mood("party")
	music.prepare(["victory"])
	awards = Awards.new()
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
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0)
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, ARENA * 0.6), 0.0)
		vr_label = UiKit.label3d("", 0.03, "gold", true)
		vr_label.position = Vector3(0.0, 0.05, 0.06)  # back of the hand, clear of the wrist MENU
		vr_label.rotation = Vector3(-1.2, 0.0, 0.0)
		vr_rig.hand_l.add_child(vr_label)
		hints.set_vr_rig(vr_rig, self)
	_build_world(vr_rig != null)
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 9.0
		add_child(group_cam)
		group_cam.follow_group([], -60.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			add_child(vr_avatar)
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)  # fake VR in bots
	# Local play without a headset: someone on the TV plays slot 0 ("P1") too.
	party.allow_slot0 = mode == "local" and vr_rig == null
	awards.set_player(0, "GIANT" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		net.state_set("shared", false)
		_start_round()
	hints.intro(INTRO, {"duration": 10.0})
	if vr_rig != null:
		hints.hint("vr_touch", "Touch the stars with your gloves!", {"to": "vr", "icon": "star"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Star Catch: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)  # environment, sun, clouds (VR-safe when vr is true)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA + 14.0
	disc.bottom_radius = ARENA + 14.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.45, 0.72, 0.36))
	ground.position.y = -0.1
	add_child(ground)
	# A ring of trees and bushes round the park, flowers inside: one draw call per kind.
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 18, Vector3.ZERO, ARENA + 10.0, ARENA + 2.0, 0.8, 1.3, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 16, Vector3.ZERO, ARENA + 3.0, ARENA + 0.8, 0.8, 1.2, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, ARENA - 0.5, 1.0, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 5))
	for k in 4:
		var lamp := MeshKit.instance(MeshKit.prop("lamp_post"))
		var a := k * TAU / 4.0 + 0.4
		lamp.position = Vector3(cos(a), 0.0, sin(a)) * (ARENA + 0.6)
		add_child(lamp)


# --- HUD (every TV view gets a UiKit root: it scales itself to the view) -------------------------

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
	row.add_child(UiKit.icon("star", "gold", 34.0))
	var l := UiKit.label("0", "number")
	row.add_child(l)
	score_labels[slot] = l
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})  # re-synced every second
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join the game"]]))
		ui.add_child(join_prompt)
		join_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	_refresh_hud()


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	for slot in score_labels:
		var l: Label = score_labels[slot]
		if is_instance_valid(l):
			l.text = "%d   BEST %d" % [score, int(net.state_get("best", 0))]
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if vr_label != null:
		vr_label.text = "STARS %d" % score


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 1.0
		c.pitch = -0.45
		add_child(c)
		c.follow(a, 6.0, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("catch", "Run into the gold stars!", {"to": slot, "icon": "star"})
	awards.set_player(slot, party.name_of(slot))
	_refresh_group()
	_refresh_hud()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	for d in [avatars, cams]:
		var dict: Dictionary = d
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	last_pos.erase(slot)
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


func _ensure_avatar(slot: int) -> Node3D:
	if avatars.has(slot) and is_instance_valid(avatars[slot]):
		return avatars[slot]
	var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": slot})
	a.name = "Avatar%d" % slot
	add_child(a)
	a.position = Vector3(-3.0 + slot, 0.0, 2.0)
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.35, 0.18)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


func _refresh_group() -> void:
	if group_cam != null:
		group_cam.set_targets(avatars.values())


## Local TV players run with their left stick, relative to their camera. The TV machine moves its
## own players instantly and tells the host where they are (net.send_state).
func _move_local_players(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "play")) == "play"
	for slot in party.local_slots():
		if not avatars.has(slot):
			continue
		var a: Node3D = avatars[slot]
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		if mv != Vector2.ZERO:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			var p := a.position + dir * SPEED * delta
			p.y = 0.0
			a.position = p.limit_length(ARENA)
			Creatures.anim(a).face(dir)  # creatures face +Z
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)
		if party.just_pressed(slot, "y"):
			net.request(slot, "toggle_view")


## Every machine: walk / idle animation from how far each avatar moved this frame.
func _animate_avatars(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.3 else 0.0)
		last_pos[slot] = a.position


## Host: a TV player moved on the TV machine (core/net.gd calls this for engine-style games).
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot):
		var a: Node3D = avatars[slot]
		a.position = pos
		a.rotation.y = yaw


## Host / local: a player asked for something (net.request from any machine lands here).
func on_request(_slot: int, action: String, _args: Array) -> void:
	match action:
		"toggle_view":
			net.state_set("shared", not bool(net.state_get("shared", false)))
		"next_round":
			if String(net.state_get("phase", "")) == "results":
				_start_round()


## Every machine: the game was paused or resumed (wrist MENU, or a TV pause menu). Nothing in
## the paused game processes, so the banners are made to process while paused.
func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "Paused by %s  -  %s" % [party.name_of(by_slot), "wrist MENU: carry on" if vr_rig != null else "Start: menu"]
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", why, {"width": 1.1})
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
			tv_banner.set_anchors_preset(Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		(tv_banner.find_child("Why", true, false) as Label).text = why
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


## Every machine: a replicated value changed (the UI reacts the same way everywhere).
func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"shared":
			if split != null and String(net.state_get("phase", "play")) == "play":
				split.set_shared(bool(value))
		"score", "best":
			_refresh_hud()
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
		"round":
			HudKit.banner(_all_huds(), "ROUND %d" % int(value), "Catch the stars!", {"duration": 2.0})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "ROUND %d" % int(value), "Catch the stars!", {"duration": 2.0, "sound": ""})
		"new_best":
			HudKit.toast(_all_huds(), "NEW BEST: %d STARS!" % int(value), {"icon": "trophy", "color": "gold"})
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds (host / local decide; every machine shows them through the state store) --------------

func _start_round() -> void:
	for id in stars.keys():
		(stars[id] as Node).queue_free()
	stars.clear()
	awards.reset()
	time_left = round_time
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)


func _end_round() -> void:
	var data := awards.results({"title": "TIME'S UP!", "subtitle": "%d stars caught together" % int(net.state_get("score", 0)),
		"style": "victory", "stats": [["ROUND", str(int(net.state_get("round", 1)))], ["BEST", str(int(net.state_get("best", 0)))]],
		"score_format": "%d STARS"})
	net.state_set("results", data)  # set before "phase" so it is there when the phase changes
	net.state_set("phase", "results")
	results_t = 0.0


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	if split != null:
		split.set_shared(true)  # everyone looks at one results screen
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


## True while the results are on screen (bots).
func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- Game loop (host / local simulate; the TV machine draws) -------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if net.mode != "host":
		_move_local_players(delta)
	_animate_avatars(delta)
	for id in stars:
		(stars[id] as Node3D).rotation.y += delta * 2.0
	if net.mode == "client":
		return
	if results_showing():
		results_t += delta
		if results_t > 25.0:
			_start_round()  # nobody pressed A: carry on by itself
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))  # once a second: fine for the store
	if time_left <= 0.0:
		_end_round()
		return
	star_t -= delta
	if star_t <= 0.0 and stars.size() < MAX_STARS:
		star_t = 1.2
		_spawn_star()
	for id in stars.keys():
		var s: Node3D = stars[id]
		var by := _catcher(s.position)
		if by >= 0:
			_catch(int(id), by)


func _spawn_star() -> void:
	var ang := randf() * TAU
	var pos := Vector3(cos(ang), 0.0, sin(ang)) * randf_range(1.5, ARENA - 0.5) + Vector3.UP * randf_range(0.6, 1.4)
	next_star += 1
	_make_star(next_star, pos)


func _make_star(id: int, pos: Vector3) -> Node3D:
	var s := Node3D.new()
	var mi := MeshKit.instance(MeshKit.prop("star"), false)
	mi.material_override = MeshKit.glow_material()  # glowing gold
	mi.position.y = -0.3  # the prop's base is at its feet; centre the star on the node
	s.add_child(mi)
	add_child(s)
	s.position = pos
	stars[id] = s
	return s


## Who is touching the star: a TV player's body, or a VR glove (slot 0). -1 = nobody.
func _catcher(p: Vector3) -> int:
	if vr_rig != null and vr_rig.touching_any(p, 0.3) >= 0:
		return 0
	for slot in avatars:
		var a: Node3D = avatars[slot]
		if Vector2(a.position.x - p.x, a.position.z - p.z).length() < 0.7:
			return int(slot)
	return -1


func _catch(id: int, by: int) -> void:
	var s: Node3D = stars[id]
	stars.erase(id)
	if by == 0 and vr_rig != null:
		var hand := vr_rig.touching_any(s.position, 0.3)
		vr_rig.pulse(hand if hand >= 0 else VrRig.RIGHT, 0.5, 0.08)
	pop(s.position, party.color_of(by), by)
	s.queue_free()
	total_caught += 1
	net.state_set("caught", total_caught)
	awards.add(by, "score")
	var score := int(net.state_get("score", 0)) + 1
	net.state_set("score", score)
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)
		if score >= 5 and not bool(net.state_get("best_shown", false)):
			net.state_set("best_shown", true)  # one toast per session, not one per star
			net.state_set("new_best", score)


## A burst, a "+1" and a sound, on both machines (the host sends it as an event).
func pop(pos: Vector3, color: Color, by: int = -1) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.08
	bm.material = MeshKit.material(color, 2.0)
	p.mesh = bm
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)
	HudKit.score(self, pos + Vector3.UP * 0.3, 1, {"color": color if by >= 0 else "gold", "size": 1.2})
	sfx.play_at("coin", pos, 0.0, 1.0 + randf() * 0.1)
	if by > 0 and avatars.has(by):
		Creatures.anim(avatars[by]).play("cheer", 0.6)
	net.event("pop", [pos, color, by])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: what the TV machine must draw that it doesn't simulate itself.
func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	for id in stars:
		ids.append(int(id))
		pos.append((stars[id] as Node3D).position)
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	return [pose, ids, pos]


## TV machine: mirror the host's world.
func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	var ids: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var seen := {}
	for i in ids.size():
		seen[ids[i]] = true
		var st: Node3D = stars[ids[i]] if stars.has(ids[i]) else _make_star(ids[i], pos[i])
		st.position = st.position.lerp(pos[i], 0.5)
	for id in stars.keys():
		if not seen.has(id):
			(stars[id] as Node).queue_free()
			stars.erase(id)


## TV machine: one-off events from the host.
func apply_event(kind: String, args: Array) -> void:
	match kind:
		"pop":
			pop(args[0], args[1], int(args[2]) if args.size() > 2 else -1)
