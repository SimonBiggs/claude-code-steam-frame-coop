extends Node3D
## WHACK-A-MOLE: a big friendly table full of holes, silly moles pop up, everyone bonks them.
## VR player: a giant soft mallet in the right hand (the left glove can slap moles too).
## TV players: tiny hammer-kids running ON the table, A = BONK. One shared score, 2-minute rounds,
## moles get faster, a golden mole is worth 5. Built on the engine template (games/engine_template).

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
const ResCache := preload("res://core/res_cache.gd")
const Props := preload("res://games/whack_a_mole/props.gd")

const GAME_ID := "whack_a_mole"
const KID_SPEED := 2.2
const KID_SCALE := 0.33
const BONK_REACH := 0.42
const LOOKS: Array[String] = ["farmer", "chef", "pirate", "knight", "astronaut", "bard", "viking"]
const PRACTICE_HOLE := 9  # front row, just left of the middle: right in front of the VR player
const MOLE_DOWN := -0.5  # mole y offset when hidden (inside the table)
# Mole states
const HIDDEN := 0
const UP := 1
const BONKED := 2
const LEAVING := 3

var round_time := 120.0  ## seconds per round (bots shorten it before adding the game)

# --- The networking contract ---
var net: Node
var ready_to_play := false
var flat_host := false  # this machine hosts without VR: slot 0 is a pad / keyboard player here, like local play
var net_target := {}  # slot -> [pos, yaw]: where another machine's player is (smoothed towards every frame)
# --- Engine modules (names core/ looks for) ---
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

var holes := PackedVector3Array()
var moles: Array[Node3D] = []  # one per hole (every machine)
var mole_bodies: Array[MeshInstance3D] = []
var mole_mesh: ArrayMesh
var gold_mesh: ArrayMesh
# Mole simulation (host / local); the TV machine fills m_h / m_flags from snapshots.
var m_state := PackedInt32Array()
var m_gold := PackedByteArray()
var m_h := PackedFloat32Array()  # 0 hidden .. 1 fully up
var m_t := PackedFloat32Array()
var vis_h := PackedFloat32Array()  # every machine: smoothed height for drawing
var shown_state := PackedInt32Array()  # every machine: last drawn state (for pop-up sounds)
var practice_ring: MeshInstance3D
var table: MeshInstance3D
var board_label: Label3D

var avatars := {}  # slot -> Node3D (TV kids, every machine)
var last_pos := {}
var cams := {}
var group_cam: CameraRig
var huds := {}
var score_labels := {}
var timers := {}
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var mallet: Node3D
var mallet_head: Node3D
var mallet_prev := Vector3.ZERO
var mallet_vel := Vector3.ZERO
var thump_cd := 0.0
var hop_cd := {}  # slot -> seconds before that kid can be bopped again
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var send_t := 0.0
var time_left := 0.0
var spawn_t := 0.0
var practice_t := 0.0
var results_t := 0.0
var total_whacked := 0
var vr_whacks := 0


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
	if net.machine_kind == "deck":
		party.allow_keyboard = false  # a Steam Deck: one player on its built-in controls; more pads may drop in
	party.player_joined.connect(_on_player_joined)
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = {"best": 0}
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
		vr_rig.bounds = Rect2(-4.0, -4.0, 8.0, 8.0)
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, Props.HALF.y + 0.5), 0.0)
		var m := Props.mallet()
		mallet = m[0]
		mallet_head = m[1]
		vr_rig.hand_r.add_child(mallet)
		hints.set_vr_rig(vr_rig, self)
	_build_world(vr_rig != null)
	if mode != "host" or flat_host:  # every machine with a screen of its own (a flat host too)
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 4.5
		add_child(group_cam)
		group_cam.follow_group([], -50.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	awards.set_player(0, "GIANT" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		_start_round(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	_title_card(String(net.state_get("phase", "")))
	print("Whack-a-Mole: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 22.0
	disc.bottom_radius = 22.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.47, 0.75, 0.38))
	ground.position.y = -0.1
	add_child(ground)
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 16, Vector3.ZERO, 18.0, 8.0, 0.8, 1.3, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, 7.0, 3.0, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 5))
	table = MeshKit.instance(Props.table_mesh())
	add_child(table)
	holes = Props.holes()
	mole_mesh = Props.mole_mesh(false)
	gold_mesh = Props.mole_mesh(true)
	var n := holes.size()
	m_state.resize(n)
	m_gold.resize(n)
	m_h.resize(n)
	m_t.resize(n)
	vis_h.resize(n)
	shown_state.resize(n)
	for i in n:
		var root := Node3D.new()
		root.position = holes[i] + Vector3(0.0, MOLE_DOWN, 0.0)
		add_child(root)
		var body := MeshKit.instance(mole_mesh, false)
		root.add_child(body)
		root.visible = false
		moles.append(root)
		mole_bodies.append(body)
	# The glowing ring round the practice mole.
	practice_ring = MeshInstance3D.new()
	var tb := MeshKit.builder()
	tb.torus(0.26, 0.03, Transform3D.IDENTITY, Color(1.0, 0.95, 0.3), 24, 6, true)
	practice_ring.mesh = tb.build()
	practice_ring.position = holes[PRACTICE_HOLE] + Vector3(0.0, 0.03, 0.0)
	practice_ring.visible = false
	add_child(practice_ring)
	# The big score board behind the table (world-locked, far from the VR player's eyes).
	var post := MeshKit.builder()
	post.rounded_box(Vector3(3.0, 1.1, 0.12), 0.08, MeshKit.at(Vector3(0.0, 2.35, -Props.HALF.y - 1.3)), Color(0.25, 0.3, 0.6))
	for s in [-1.0, 1.0]:
		var sf: float = s
		post.cylinder(0.06, 0.06, 1.9, MeshKit.at(Vector3(sf * 1.3, 0.95, -Props.HALF.y - 1.35)), Color(0.9, 0.9, 0.95), 8)
	add_child(MeshKit.instance(post.build(), false))
	board_label = Label3D.new()
	board_label.font = UiKit.font(true)
	board_label.font_size = 128
	board_label.pixel_size = 0.0034
	board_label.outline_size = 26
	board_label.outline_modulate = Color(0.02, 0.02, 0.08)
	board_label.modulate = Color(1.0, 0.92, 0.35)
	board_label.double_sided = false
	board_label.no_depth_test = false
	board_label.position = Vector3(0.0, 2.35, -Props.HALF.y - 1.23)
	add_child(board_label)
	_refresh_hud()


# --- HUD -------------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	if slot < 0:
		var card := UiKit.panel("card")
		ui.add_child(card)
		card.position = Vector2(24.0, 20.0)
		var row := UiKit.hbox()
		card.add_child(row)
		row.add_child(UiKit.icon("star", "gold", 40.0))
		var l := UiKit.label("0", "number")
		row.add_child(l)
		score_labels[slot] = l
		timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		UiKit.pin(join_prompt, Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	else:
		var pill := UiKit.panel("pill")
		pill.add_child(UiKit.prompts([["A", "BONK!"]]))
		ui.add_child(pill)
		UiKit.pin(pill, Control.PRESET_CENTER_BOTTOM)
		pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
		pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
		pill.offset_top = -40.0
		pill.offset_bottom = -40.0
	_refresh_hud()


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0)) if net != null else 0
	for slot in score_labels:
		var l: Label = score_labels[slot]
		if is_instance_valid(l):
			l.text = "%d" % score
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if board_label != null:
		var t := int(net.state_get("time", int(round_time)))
		board_label.text = "SCORE %d\n%s" % [score, HudKit.clock_text(float(t))]


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


func _banner(title: String, sub: String = "", dur: float = 1.8) -> void:
	HudKit.banner(_all_huds(), title, sub, {"duration": dur})
	if vr_rig != null:
		HudKit.vr_banner(self, vr_rig.camera, title, sub, {"duration": dur, "sound": ""})


func _title_card(phase: String) -> void:
	if phase == "practice":
		_banner("WHACK-A-MOLE!", "Bonk the mole!", 3.0)
		if vr_rig != null:
			hints.hint("vr_whack", "Swing the mallet!", {"to": "vr"})


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 0.3
		c.pitch = -0.55
		add_child(c)
		c.follow(a, 2.6, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
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
	net_target.erase(slot)
	hop_cd.erase(slot)
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
	var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": slot,
		"weapon": "hammer", "scale": KID_SCALE})
	a.name = "Kid%d" % slot
	add_child(a)
	a.position = Vector3(-1.2 + 0.6 * float(slot % 5), Props.TABLE_Y, -0.36 + 0.72 * float((slot / 5) % 2))
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.12, 0.09)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


func _refresh_group() -> void:
	if group_cam != null:
		var t: Array = avatars.values()
		if t.is_empty():
			t = [table]
		group_cam.set_targets(t)


func _move_local_players(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var phase := String(net.state_get("phase", "play"))
	var playing := phase == "play" or phase == "practice"
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
			var p := a.position + dir * KID_SPEED * delta
			p.x = clampf(p.x, -Props.HALF.x + 0.1, Props.HALF.x - 0.1)
			p.z = clampf(p.z, -Props.HALF.y + 0.1, Props.HALF.y - 0.1)
			p.y = Props.TABLE_Y
			a.position = p
			Creatures.anim(a).face(dir)
		if playing and (party.just_pressed(slot, "accept") or party.just_pressed(slot, "x") or party.just_pressed(slot, "rt")):
			Creatures.anim(a).play("attack", 0.35)
			sfx.play_at("swish", a.position, -6.0, randf_range(1.1, 1.3))
			net.request(slot, "bonk", [a.position])
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)


func _animate_avatars(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v / KID_SCALE * 0.6 if v > 0.1 else 0.0)
		last_pos[slot] = a.position


## Host: a player on another machine moved.
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot) and not party.is_local(slot):
		if not net_target.has(slot):
			(avatars[slot] as Node3D).position = pos  # first update: no glide in from the spawn point
		net_target[slot] = [pos, yaw]


## Every machine: other machines' players glide to where their machine (or the host) says they are.
func _follow_remote(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	for slot in net_target:
		if not avatars.has(slot) or party.is_local(slot):
			continue
		var a: Node3D = avatars[slot]
		var t: Array = net_target[slot]
		a.position = a.position.lerp(t[0], k)
		a.rotation.y = lerp_angle(a.rotation.y, float(t[1]), k)


## Host: one machine left. core/party.gd frees just its seats (player_left for each removes their
## avatars, views and per-player state); only that machine's leftovers are dropped here.
func on_machine_left(peer: int) -> void:
	for slot in party.slots_of(peer):
		net_target.erase(slot)


## TV machine: the VR player (only when the host has one) with their mallet, plus the window into their view.
func _make_vr_avatar() -> void:
	vr_avatar = VrRig.Avatar.new()
	add_child(vr_avatar)
	var m2 := Props.mallet()
	mallet = m2[0]
	mallet_head = m2[1]
	vr_avatar.hands[1].add_child(mallet)
	if split != null:
		split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))


func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"bonk":
			if avatars.has(slot):
				var a: Node3D = avatars[slot]
				if not party.is_local(slot):
					Creatures.anim(a).play("attack", 0.35)
				net.event("swing", [slot])  # every machine sees the swing (its own machine already played it)
				var at: Vector3 = args[0] if not args.is_empty() and args[0] is Vector3 else a.position
				var hole := _mole_near(at, BONK_REACH)
				if hole >= 0:
					_whack(hole, slot)
				else:
					net.event("thump", [at, 0.4])
					thump(at, 0.4)
		"next_round":
			if String(net.state_get("phase", "")) == "results":
				_start_round(false)


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "Paused by %s" % party.name_of(by_slot)
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
			UiKit.pin(tv_banner, Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		(tv_banner.find_child("Why", true, false) as Label).text = why
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"score", "best":
			_refresh_hud()
		"time":
			_refresh_hud()
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
			if int(value) <= 5 and int(value) > 0 and String(net.state_get("phase", "")) == "play":
				sound("tick", -4.0)
		"faster":
			_banner("FASTER!", "", 1.4)
			sound("power_up", -4.0)
		"phase":
			var ph := String(value)
			if ph == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
				if ph == "play":
					_banner("GO!", "", 1.2)
					sound("go")
				elif ready_to_play:
					_title_card(ph)


# --- Rounds -------------------------------------------------------------------------------

func _start_round(practice: bool) -> void:
	for i in holes.size():
		m_state[i] = HIDDEN
		m_h[i] = 0.0
		m_gold[i] = 0
	awards.reset()
	time_left = round_time
	spawn_t = 1.5
	practice_t = 0.0
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	net.state_set("level", 0)
	if practice:
		_pop_mole(PRACTICE_HOLE, false, 9999.0)
		net.state_set("phase", "practice")
	else:
		net.state_set("phase", "play")


func _end_round() -> void:
	var score := int(net.state_get("score", 0))
	var data := awards.results({"title": "%d POINTS!" % score, "subtitle": "Great bonking, team!",
		"style": "victory", "stats": [["BEST", str(int(net.state_get("best", 0)))]],
		"score_format": "%d", "max_awards": 3, "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	for i in holes.size():
		if m_state[i] == UP:
			m_state[i] = LEAVING


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	sound("fanfare")
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
		split.set_shared(false)
	if music != null and String(net.state_get("phase", "")) == "play":
		music.play_mood("party")


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- Game loop ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if split != null:
		_move_local_players(delta)
	_follow_remote(delta)
	_animate_avatars(delta)
	if net.mode != "client":
		_simulate(delta)
	_draw_moles(delta)
	if practice_ring != null:
		practice_ring.visible = String(net.state_get("phase", "")) == "practice"
		var s := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.008)
		practice_ring.scale = Vector3(s, 1.0, s)


func _simulate(delta: float) -> void:
	if vr_rig != null:
		_vr_mallet(delta)
	_update_moles(delta)
	var phase := String(net.state_get("phase", ""))
	if phase == "results":
		results_t += delta
		if results_t > 12.0:
			_start_round(false)  # automatic play again
		return
	if phase == "practice":
		practice_t += delta
		if practice_t > 15.0:
			_start_play()
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if time_left <= 0.0:
		_end_round()
		return
	var p := clampf(1.0 - time_left / round_time, 0.0, 1.0)
	var level := int(p * 3.0)
	if level > int(net.state_get("level", 0)):
		net.state_set("level", level)
		net.state_set("faster", int(net.state_get("faster", 0)) + 1)  # a counter, so every round shows it
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = lerpf(1.1, 0.45, p) * randf_range(0.8, 1.2)
		var up := 0
		for i in holes.size():
			if m_state[i] == UP:
				up += 1
		if up < int(lerpf(2.0, 5.0, p) + 0.5):
			var free: Array[int] = []
			for i in holes.size():
				if m_state[i] == HIDDEN and m_t[i] <= 0.0:
					free.append(i)
			if not free.is_empty():
				var any_gold := false
				for i in holes.size():
					any_gold = any_gold or (m_gold[i] == 1 and m_state[i] != HIDDEN)
				var gold := not any_gold and p > 0.05 and randf() < 0.08
				var stay := lerpf(2.0, 0.9, p) * (0.8 if gold else 1.0)
				_pop_mole(free[randi() % free.size()], gold, stay)


func _start_play() -> void:
	time_left = round_time
	spawn_t = 1.2
	if m_state[PRACTICE_HOLE] == UP:
		m_t[PRACTICE_HOLE] = minf(m_t[PRACTICE_HOLE], 2.0)  # nobody bonked it: it goes down like any mole
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")


func _pop_mole(i: int, gold: bool, stay: float) -> void:
	m_state[i] = UP
	m_gold[i] = 1 if gold else 0
	m_t[i] = stay


func _update_moles(delta: float) -> void:
	for i in holes.size():
		match m_state[i]:
			HIDDEN:
				m_h[i] = 0.0
				m_t[i] = maxf(0.0, m_t[i] - delta)  # a short rest before the hole is used again
			UP:
				m_h[i] = minf(1.0, m_h[i] + delta / 0.16)
				m_t[i] -= delta
				if m_t[i] <= 0.0:
					m_state[i] = LEAVING
			BONKED:
				m_t[i] -= delta
				if m_t[i] < 0.0:
					m_h[i] = maxf(0.0, m_h[i] - delta / 0.18)
				if m_h[i] <= 0.0:
					m_state[i] = HIDDEN
					m_t[i] = 0.4
			LEAVING:
				m_h[i] = maxf(0.0, m_h[i] - delta / 0.2)
				if m_h[i] <= 0.0:
					m_state[i] = HIDDEN
					m_t[i] = 0.4


## Host: is a mole up near this table point? Returns the hole or -1.
func _mole_near(p: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach
	for i in holes.size():
		if m_state[i] != UP or m_h[i] < 0.35:
			continue
		var d := Vector2(holes[i].x - p.x, holes[i].z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## Host: the VR player's mallet (and left glove) against the moles and the table.
func _vr_mallet(delta: float) -> void:
	thump_cd -= delta
	var hp := mallet_head.global_position
	mallet_vel = (hp - mallet_prev) / maxf(delta, 0.001)
	mallet_prev = hp
	var speed := mallet_vel.length()
	var phase := String(net.state_get("phase", ""))
	if phase == "results":
		return
	var hit := -1
	if speed > 0.6:
		hit = _mole_hit_by(hp, Props.HEAD_R + 0.12)
		if hit >= 0:
			_whack(hit, 0)
			vr_rig.pulse(VrRig.RIGHT, 0.8, 0.09)
			_squash_mallet()
			return
	var lp := vr_rig.hand_point(VrRig.LEFT)
	if vr_rig.hand_speed(VrRig.LEFT) > 0.6:
		hit = _mole_hit_by(lp, 0.14)
		if hit >= 0:
			_whack(hit, 0)
			vr_rig.pulse(VrRig.LEFT, 0.6, 0.08)
			return
	# Touching a hammer-kid with the mallet or a glove makes them hop.
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var c := a.position + Vector3(0.0, 0.2, 0.0)
		if float(hop_cd.get(slot, 0.0)) <= 0.0 and (hp.distance_to(c) < Props.HEAD_R + 0.15 or lp.distance_to(c) < 0.2):
			hop_cd[slot] = 0.8
			hop(int(slot))
			net.event("hop", [int(slot)])
			vr_rig.pulse(VrRig.LEFT if lp.distance_to(c) < 0.2 else VrRig.RIGHT, 0.3, 0.05)
	for slot in hop_cd.keys():
		hop_cd[slot] = float(hop_cd[slot]) - delta
	# Bonking the table itself: it wobbles, the kids hop.
	var on_table := absf(hp.x) < Props.HALF.x + 0.1 and absf(hp.z) < Props.HALF.y + 0.1
	if on_table and thump_cd <= 0.0 and mallet_vel.y < -0.8 and hp.y - Props.HEAD_R < Props.TABLE_Y + 0.05:
		thump_cd = 0.35
		var at := Vector3(hp.x, Props.TABLE_Y, hp.z)
		thump(at, 1.0)
		net.event("thump", [at, 1.0])
		vr_rig.pulse(VrRig.RIGHT, 0.4, 0.06)
		_squash_mallet()


func _mole_hit_by(p: Vector3, r: float) -> int:
	for i in holes.size():
		if m_state[i] != UP or m_h[i] < 0.3:
			continue
		var base := holes[i]
		var top := base.y + 0.46 * m_h[i]
		var dxz := Vector2(base.x - p.x, base.z - p.z).length()
		if dxz < r + 0.12 and p.y < top + r and p.y > base.y - 0.1:
			return i
	return -1


func _squash_mallet() -> void:
	if mallet_head == null:
		return
	mallet_head.scale = Vector3(1.25, 0.7, 1.25)
	var tw := create_tween()
	tw.tween_property(mallet_head, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Host: a mole got bonked by `by` (0 = the VR giant, or a TV slot).
func _whack(i: int, by: int) -> void:
	var pts := 5 if m_gold[i] == 1 else 1
	var was_practice := String(net.state_get("phase", "")) == "practice"
	m_state[i] = BONKED
	m_t[i] = 0.35
	total_whacked += 1
	if by == 0 and vr_rig != null:
		vr_whacks += 1
	net.state_set("whacked", total_whacked)
	awards.add(by, "score", float(pts))
	if not was_practice:
		var score := int(net.state_get("score", 0)) + pts
		net.state_set("score", score)
		if score > int(save.data["best"]):
			save.data["best"] = score
			save.mark_dirty()
			net.state_set("best", score)
	whack_fx(i, by, pts)
	net.event("whack", [i, by, pts])
	if was_practice:
		_start_play()


## Every machine: the juicy bit. Squash, burst, "+1", sound, kids cheer.
func whack_fx(i: int, by: int, pts: int) -> void:
	var gold := pts > 1
	var body := mole_bodies[i]
	body.scale = Vector3(1.5, 0.45, 1.5)
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3(1.1, 0.8, 1.1), 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var pos := holes[i] + Vector3(0.0, 0.3, 0.0)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 24 if gold else 14
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	var col := Color(1.0, 0.85, 0.2) if gold else party.color_of(by)
	p.mesh = ResCache.get_or_make("wam_bit_%s" % col.to_html(false), func() -> Resource:
		var bm := SphereMesh.new()
		bm.radius = 0.035
		bm.height = 0.07
		bm.radial_segments = 6
		bm.rings = 3
		bm.material = MeshKit.material(col, 1.5)
		return bm)
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	HudKit.score(self, pos + Vector3.UP * 0.25, pts, {"color": "gold" if gold else party.color_of(by), "size": 1.6 if gold else 1.1})
	if gold:
		sfx.play_at("kaching", pos, 2.0)
		sfx.play_at("sparkle", pos, 0.0)
	else:
		sfx.play_at("boing", pos, 0.0, randf_range(0.9, 1.2))
		sfx.play_at("pop", pos, -3.0, randf_range(0.8, 1.1))
	if by >= 0 and avatars.has(by):
		Creatures.anim(avatars[by]).play("cheer", 0.6)


## Every machine: something thumped the table: it wobbles and kids nearby hop.
func thump(at: Vector3, power: float) -> void:
	sfx.play_at("land", at, -2.0 + power * 2.0, randf_range(0.7, 0.9))
	if power >= 1.0 and table != null:
		table.scale = Vector3(1.0, 0.96, 1.0)
		var tw := create_tween()
		tw.tween_property(table, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		for slot in avatars:
			var a: Node3D = avatars[slot]
			if Vector2(a.position.x - at.x, a.position.z - at.z).length() < 0.9:
				Creatures.anim(a).play("jump", 0.5)
		for i in holes.size():  # moles that are up flinch
			if moles[i].visible and Vector2(holes[i].x - at.x, holes[i].z - at.z).length() < 0.8:
				mole_bodies[i].scale = Vector3(0.85, 1.2, 0.85)


## Every machine: the VR giant bopped a hammer-kid: they hop and giggle.
func hop(slot: int) -> void:
	if avatars.has(slot):
		var a: Node3D = avatars[slot]
		Creatures.anim(a).play("jump", 0.5)
		sfx.play_at("boing", a.position, -2.0, randf_range(1.4, 1.7))


## Every machine: place the moles from their heights (with a bouncy overshoot) and wiggle them.
func _draw_moles(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in holes.size():
		var target: float = m_h[i]
		vis_h[i] = lerpf(vis_h[i], target, minf(1.0, delta * 25.0))
		var st := m_state[i]
		var root := moles[i]
		if st != shown_state[i]:
			if st == UP:
				var gold := m_gold[i] == 1
				mole_bodies[i].mesh = gold_mesh if gold else mole_mesh
				mole_bodies[i].scale = Vector3(0.8, 1.25, 0.8)
				sfx.play_at("sparkle" if gold else "pop", holes[i], -8.0 if not gold else 0.0, randf_range(1.2, 1.5))
			shown_state[i] = st
		root.visible = vis_h[i] > 0.01
		if not root.visible:
			continue
		var e := _ease_back(vis_h[i])
		root.position = holes[i] + Vector3(0.0, lerpf(MOLE_DOWN, 0.0, e), 0.0)
		var body := mole_bodies[i]
		if st == UP:
			root.rotation = Vector3(0.0, 0.0, sin(t * 7.0 + i) * 0.12)
			body.scale = body.scale.lerp(Vector3.ONE, minf(1.0, delta * 10.0))
		elif st == BONKED:
			root.rotation = Vector3(0.0, t * 9.0, 0.0)  # dizzy spin
		else:
			root.rotation = Vector3.ZERO


static func _ease_back(x: float) -> float:
	var c1 := 1.9
	var c3 := c1 + 1.0
	var y := x - 1.0
	return 1.0 + c3 * y * y * y + c1 * y * y


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: VR pose + mole heights and states (12 holes: tiny).
func make_snapshot() -> Array:
	var flags := PackedByteArray()
	flags.resize(holes.size())
	for i in holes.size():
		flags[i] = m_state[i] | (m_gold[i] << 2)
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	# Every player avatar (slot, position, yaw): each machine sees the other machines' players.
	var av_slots := PackedByteArray()
	var av_pos := PackedVector3Array()
	var av_yaw := PackedFloat32Array()
	for slot in avatars:
		var a: Node3D = avatars[slot]
		av_slots.append(int(slot))
		av_pos.append(a.position)
		av_yaw.append(a.rotation.y)
	return [pose, m_h, flags, av_slots, av_pos, av_yaw]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 6:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var av_slots: PackedByteArray = s[3]
	var av_pos: PackedVector3Array = s[4]
	var av_yaw: PackedFloat32Array = s[5]
	for i in av_slots.size():
		var slot: int = av_slots[i]
		if avatars.has(slot) and not party.is_local(slot):
			if not net_target.has(slot):
				(avatars[slot] as Node3D).position = av_pos[i]
			net_target[slot] = [av_pos[i], av_yaw[i]]
	var h: PackedFloat32Array = s[1]
	var flags: PackedByteArray = s[2]
	for i in mini(h.size(), holes.size()):
		m_h[i] = h[i]
		m_state[i] = flags[i] & 3
		m_gold[i] = (flags[i] >> 2) & 1


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"whack":
			whack_fx(int(args[0]), int(args[1]), int(args[2]))
			if mallet_head != null and int(args[1]) == 0:
				_squash_mallet()
		"thump":
			thump(args[0], float(args[1]))
		"hop":
			hop(int(args[0]))
		"swing":
			var ss := int(args[0])
			if avatars.has(ss) and not party.is_local(ss):
				Creatures.anim(avatars[ss]).play("attack", 0.35)
