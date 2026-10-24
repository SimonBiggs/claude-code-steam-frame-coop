extends Node3D
## QUIZ SHOW: a family TV quiz in a little studio. Everyone answers every question with the four
## coloured buttons (A green, B red, X blue, Y yellow); quick right answers score more. Wrong answers
## never cost points. The VR player stands at a desk and slaps big coloured buttons; TV and Deck
## players use their pads; everyone sees the scores on the podiums.
## A show: LEVEL vote (KIDS / FAMILY / BRAINIACS / SURPRISE ME: teaches the buttons by doing) ->
## WARM-UP -> PICTURE PUZZLE (tiles drop away) -> TRUE OR FALSE (streaks) -> THE BIG FINAL (double
## points) -> results with awards; A / the trigger starts the next show.
## Questions: question_bank.gd (bank_a/b/c.gd, bank_tf.gd, pictures.gd). Rounds: rounds.gd. Points: scoring.gd.
## Engine: core/party.gd seats, core/split_view.gd (one shared view), core/camera_rig.gd shots,
## core/vr_rig.gd, the state store (everything the screens show), net.request (answers from any
## machine), core/save.gd (best score, recent questions), core/hud_kit.gd / core/awards.gd / core/hints.gd.
## Many machines: any number of TV machines and Decks; a flat host (no VR) plays slot 0 itself.

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
const QuestionBank := preload("res://games/quiz_show/question_bank.gd")
const Pictures := preload("res://games/quiz_show/pictures.gd")
const Rounds := preload("res://games/quiz_show/rounds.gd")
const Scoring := preload("res://games/quiz_show/scoring.gd")

const GAME_ID := "quiz_show"
const SCREEN := Vector3(0.0, 3.0, -4.5)  ## centre of the big screen (faces +Z)
const SCREEN_SIZE := Vector2(6.6, 4.4)
const DESK := Vector3(0.0, 0.0, 2.2)  ## the VR player's feet (and slot 0's podium on a flat host)
const DESK_TOP := 0.95
const BUTTON_R := 0.085
const PODIUMS: Array[Vector3] = [Vector3(0.0, 0.0, 2.2), Vector3(-1.8, 0.0, 1.9), Vector3(1.8, 0.0, 1.9),
	Vector3(-3.4, 0.0, 1.3), Vector3(3.4, 0.0, 1.3), Vector3(-4.8, 0.0, 0.5), Vector3(4.8, 0.0, 0.5)]
const TILE_COLS := 4
const TILE_ROWS := 3
const LOOKS: Array[String] = ["knight", "mage", "archer", "bard", "pirate", "chef", "astronaut"]
const RECENT_KEEP := 300  ## question ids remembered across shows (not asked again soon)
const INTRO := {
	"title": "QUIZ SHOW",
	"goal": "Answer with the coloured buttons. Quick and right = more points!",
	"vr": {"role": "THE DESK", "controls": [["SLAP", "a coloured button"], ["L-STICK", "Walk"]]},
	"tv": {"role": "CONTESTANTS", "controls": [["A", "Green"], ["B", "Red"], ["X", "Blue"], ["Y", "Yellow"]],
		"tips": ["Press A to join!"]},
}

var show_length := "show"  ## bots set "short"
var reveal_time := Rounds.REVEAL  ## bots shorten these
var intro_time := Rounds.ROUND_INTRO

# --- The networking contract (see docs/engine/systems.md) ---
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
var hints: Hints
var awards: Awards

var flat_host := false
var cam: CameraRig  # the shared TV view's camera
var vr_avatar: VrRig.Avatar  # TV machine: the VR player as seen from here
var avatars := {}  # slot -> Node3D at its podium (every contestant except the VR player)
var podiums := {}  # slot -> {node, score: Label3D, light: MeshInstance3D}
# Big screen (every machine: the VR player reads it; the TV sees it in the picture round)
var scr_question: Label3D
var scr_info: Label3D
var scr_center: Label3D
var scr_tiles: Array = []  # [{panel: MeshInstance3D, label: Label3D}]
var pic_root: Node3D
var pic_id := ""
var pic_cover: Array[Node3D] = []
var pic_order: Array[int] = []
# VR desk
var desk_buttons: Array[Node3D] = []
var desk_labels: Array[Label3D] = []
var desk_score: Label3D
var vr_press_t := 0.0
# TV HUD
var hud: Control
var ui_top: Control
var ui_cat: Control
var ui_count: Label
var ui_question: Label
var ui_bottom: Control
var ui_chips: HBoxContainer
var ui_tiles: Array = []  # [{panel, label, pickers: HBoxContainer}]
var ui_timer: HudKit.TimerPill
var join_prompt: Control
var results_ui: Control
var vr_results: Node
var vr_banner: Node3D
var tv_banner: Control
# Host / local: the show
var bank: QuestionBank
var q_correct := -1
var q_kind := ""
var q_tier := 1
var level := 1
var round_i := -1  # index into Rounds.ORDER (-1 = the level vote)
var q_n := 0  # question number in this round (1-based)
var phase_t := 0.0  # seconds into this phase
var ask_time := 10.0
var all_in_t := -1.0
var picks := {}  # slot -> answer index
var pick_frac := {}  # slot -> share of time left when they answered
var pick_reveal := {}  # slot -> share of picture tiles gone when they answered
var streak := {}  # slot -> right answers in a row (true or false round)
var best_streak := {}


func _ready() -> void:
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"  # RPCs resolve to /root/Main/Net on every machine
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
	save.defaults = {"best": 0, "recent": []}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("quiz")
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
		vr_rig.bounds = Rect2(-1.2, 1.4, 2.4, 1.8)  # a little room behind the desk
		add_child(vr_rig)
		vr_rig.place(DESK, 0.0)
		hints.set_vr_rig(vr_rig, self)
	_build_world()
	_build_screen()
	_build_desk()
	if mode != "host" or flat_host:  # every machine with a screen of its own
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		split.set_shared(true)  # a quiz is one shared screen
		cam = CameraRig.new()
		cam.camera = split.shared_camera()
		add_child(cam)
		_camera_shot(false, 0.0)
		_make_hud(split.shared_hud())
		hints.add_view(hud, -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)  # fake VR in bots
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	if mode != "client":
		bank = QuestionBank.new()
		net.state_set("vr", vr_rig != null)
		net.state_set("best", int(save.data["best"]))
		net.state_set("scores", {})
		_new_show()
	hints.intro(INTRO, {"duration": 8.0})
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	ready_to_play = true
	_refresh_all()
	print("Quiz Show: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world() -> void:
	SkyKit.apply(self, "night", vr_rig != null)
	var b := MeshKit.Builder.new()
	# floor: a dark stage with a lit circle, the back wall, and coloured light strips
	b.cylinder(9.0, 9.0, 0.2, MeshKit.at(Vector3(0.0, -0.1, 0.0)), Color(0.13, 0.12, 0.22), 40)
	b.cylinder(3.2, 3.2, 0.04, MeshKit.at(Vector3(0.0, 0.01, 1.4)), Color(0.3, 0.22, 0.5), 40)
	b.box(Vector3(14.0, 7.0, 0.3), MeshKit.at(Vector3(0.0, 3.5, -5.2)), Color(0.1, 0.1, 0.2))
	for k in 7:
		var x := -6.0 + k * 2.0
		b.box(Vector3(0.12, 6.0, 0.06), MeshKit.at(Vector3(x, 3.2, -5.0)), Rounds.LETTER_COLORS[k % 4].darkened(0.2))
	b.box(Vector3(7.0, 0.5, 0.6), MeshKit.at(Vector3(0.0, 0.25, -4.4)), Color(0.18, 0.17, 0.3))  # screen stand
	var mi := MeshInstance3D.new()
	mi.mesh = b.build()
	mi.material_override = MeshKit.material(Color.WHITE)
	add_child(mi)
	for k in 3:
		var l := OmniLight3D.new()
		l.light_color = [Color(1.0, 0.7, 0.9), Color(0.7, 0.85, 1.0), Color(1.0, 0.95, 0.7)][k]
		l.omni_range = 9.0
		l.light_energy = 1.4
		l.position = Vector3(-4.0 + k * 4.0, 4.5, 2.0)
		add_child(l)


## Big screen: question on top, the picture (or the category) in the middle, the four answers below.
func _build_screen() -> void:
	var back := UiKit.panel3d(SCREEN_SIZE, Color(0.05, 0.06, 0.14), Color(1.0, 0.8, 0.3, 0.8), 0.12)
	back.position = SCREEN
	add_child(back)
	scr_info = UiKit.label3d("", 0.13, "gold", true)
	scr_info.position = SCREEN + Vector3(0.0, 1.95, 0.03)
	add_child(scr_info)
	scr_question = UiKit.label3d("", 0.24, "text", true, 6.1)
	scr_question.position = SCREEN + Vector3(0.0, 1.45, 0.03)
	add_child(scr_question)
	scr_center = UiKit.label3d("", 0.36, "gold", true, 5.0)
	scr_center.position = SCREEN + Vector3(0.0, 0.1, 0.03)
	add_child(scr_center)
	for i in 4:
		var t := {}
		var pos := SCREEN + Vector3(-1.62 + 3.24 * (i % 2), -1.35 - 0.56 * int(i / 2), 0.03)
		var p := UiKit.panel3d(Vector2(3.1, 0.48), Rounds.LETTER_COLORS[i].darkened(0.35), Rounds.LETTER_COLORS[i], 0.08)
		p.position = pos
		add_child(p)
		var l := UiKit.label3d("", 0.17, "white", true)
		l.position = pos + Vector3(0.0, 0.0, 0.02)
		add_child(l)
		t["panel"] = p
		t["label"] = l
		scr_tiles.append(t)
	pic_root = Node3D.new()
	pic_root.position = SCREEN + Vector3(0.0, -0.95, 0.35)
	add_child(pic_root)


## The VR player's desk: four big buttons in a row with the answer written behind each.
func _build_desk() -> void:
	var b := MeshKit.Builder.new()
	var d := DESK + Vector3(0.0, 0.0, -0.42)
	b.box(Vector3(1.15, DESK_TOP, 0.42), MeshKit.at(d + Vector3(0.0, DESK_TOP * 0.5, 0.0)), Color(0.2, 0.18, 0.34))
	b.box(Vector3(1.2, 0.04, 0.46), MeshKit.at(d + Vector3(0.0, DESK_TOP, 0.0)), Color(1.0, 0.8, 0.3))
	b.box(Vector3(1.0, 0.25, 0.02), MeshKit.at(d + Vector3(0.0, DESK_TOP * 0.55, -0.22)), Color(0.36, 0.55, 1.0))
	var desk := MeshInstance3D.new()
	desk.mesh = b.build()
	desk.material_override = MeshKit.material(Color.WHITE)
	add_child(desk)
	for i in 4:
		var bt := Node3D.new()
		bt.position = d + Vector3(-0.39 + 0.26 * i, DESK_TOP + 0.03, 0.04)
		add_child(bt)
		var base := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = BUTTON_R
		cyl.bottom_radius = BUTTON_R * 1.1
		cyl.height = 0.05
		cyl.radial_segments = 20
		base.mesh = cyl
		base.material_override = MeshKit.material(Rounds.LETTER_COLORS[i], 0.6)
		base.name = "Cap"
		bt.add_child(base)
		desk_buttons.append(bt)
		var l := UiKit.label3d("", 0.03, "white", true, 0.24)
		l.position = d + Vector3(-0.39 + 0.26 * i, DESK_TOP + 0.09, -0.14)
		l.rotation = Vector3(-0.5, 0.0, 0.0)
		add_child(l)
		desk_labels.append(l)
	desk_score = UiKit.label3d("", 0.045, "gold", true)
	desk_score.position = d + Vector3(0.0, DESK_TOP + 0.2, -0.2)
	desk_score.rotation = Vector3(-0.3, 0.0, 0.0)
	add_child(desk_score)
	desk.visible = vr_rig != null or net.mode == "client"  # the TV sees the VR player's desk too
	_set_desk_visible(false)


func _set_desk_visible(on: bool) -> void:
	for n in desk_buttons:
		n.visible = on
	for n in desk_labels:
		n.visible = on
	desk_score.visible = on


## A podium (and an avatar, unless it is the VR player) for every contestant seat.
func _ensure_podium(slot: int) -> void:
	if podiums.has(slot):
		return
	var at: Vector3 = PODIUMS[clampi(slot, 0, PODIUMS.size() - 1)]
	var node := Node3D.new()
	node.position = at
	node.rotation.y = atan2(at.x - SCREEN.x, at.z - SCREEN.z)  # +Z points away from the screen
	add_child(node)
	var col := party.color_of(slot)
	var is_vr := slot == 0 and bool(net.state_get("vr", false))
	var p := {"node": node}
	if not is_vr:
		var b := MeshKit.Builder.new()
		b.box(Vector3(0.9, 0.9, 0.5), MeshKit.at(Vector3(0.0, 0.45, -0.45)), Color(0.18, 0.17, 0.3))
		b.box(Vector3(0.92, 0.12, 0.52), MeshKit.at(Vector3(0.0, 0.62, -0.45)), col)
		var mi := MeshInstance3D.new()
		mi.mesh = b.build()
		mi.material_override = MeshKit.material(Color.WHITE)
		node.add_child(mi)
		var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": col, "seed": slot})
		a.position = Vector3(0.0, 0.0, 0.05)
		a.rotation.y = PI  # creatures face +Z: turn to the screen
		node.add_child(a)
		HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.3, 0.16)
		avatars[slot] = a
	# score on the front (towards the screen and the TV camera), and an answer light
	var s := UiKit.label3d("0", 0.13, col, true)
	s.position = Vector3(0.0, 0.42, -0.71 if not is_vr else -0.66)
	s.rotation.y = PI
	node.add_child(s)
	p["score"] = s
	var light := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 12
	sm.rings = 6
	light.mesh = sm
	light.material_override = MeshKit.material(Color(0.3, 0.3, 0.35))
	light.position = Vector3(0.0, 1.02 if is_vr else 0.75, -0.68 if not is_vr else -0.42)
	node.add_child(light)
	p["light"] = light
	podiums[slot] = p


func _drop_podium(slot: int) -> void:
	if podiums.has(slot):
		(podiums[slot]["node"] as Node).queue_free()
		podiums.erase(slot)
	avatars.erase(slot)


# --- TV camera ----------------------------------------------------------------------------

## Contestants (from the screen side, looking at the podiums) or the big screen (picture round).
func _camera_shot(screen: bool, blend: float = 1.0) -> void:
	if cam == null:
		return
	if screen:
		cam.shot_look(Vector3(0.0, 3.0, -1.9), SCREEN + Vector3(0.0, 0.0, 0.0), blend)
	else:
		cam.shot_look(Vector3(0.0, 3.4, -3.6), Vector3(0.0, 1.0, 1.4), blend)


# --- HUD (shared TV view) -------------------------------------------------------------------

func _make_hud(parent: Control) -> void:
	hud = UiKit.ui_root(parent)
	var top := UiKit.panel("card")
	hud.add_child(top)
	ui_top = top
	var tv := UiKit.vbox(6)
	top.add_child(tv)
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(row)
	ui_cat = UiKit.hbox(0)
	row.add_child(ui_cat)
	ui_count = UiKit.label("", "small", "dim")
	row.add_child(ui_count)
	ui_question = UiKit.paragraph("", "heading", null, HORIZONTAL_ALIGNMENT_CENTER)
	ui_question.custom_minimum_size = Vector2(1150.0, 0.0)
	tv.add_child(ui_question)
	UiKit.pin(top, Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16.0
	ui_timer = HudKit.timer(hud, {"seconds": 0.0, "count_down": false, "warn": 5.0, "anchor": "top_right"})
	var bottom := UiKit.vbox(10)
	hud.add_child(bottom)
	ui_bottom = bottom
	ui_chips = UiKit.hbox(10)
	ui_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(ui_chips)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	bottom.add_child(grid)
	for i in 4:
		var p := UiKit.tinted_panel(Rounds.LETTER_COLORS[i], 1.0, "card")
		p.custom_minimum_size = Vector2(560.0, 0.0)
		grid.add_child(p)
		var h := UiKit.hbox(12)
		p.add_child(h)
		h.add_child(UiKit.glyph(Rounds.LETTERS[i], 1.2))
		var l := UiKit.label("", "heading")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(l)
		var pk := UiKit.hbox(4)
		h.add_child(pk)
		ui_tiles.append({"panel": p, "label": l, "pickers": pk})
	UiKit.pin(bottom, Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_top = -18.0
	bottom.offset_bottom = -18.0
	join_prompt = UiKit.panel("pill")
	join_prompt.add_child(UiKit.prompts([["A", "Join the quiz"]]))
	hud.add_child(join_prompt)
	UiKit.pin(join_prompt, Control.PRESET_CENTER)
	join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	join_prompt.grow_vertical = Control.GROW_DIRECTION_BOTH


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	_ensure_podium(slot)
	awards.set_player(slot, party.name_of(slot))
	_refresh_all()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	_drop_podium(slot)
	_refresh_all()


## Everyone answering: the seated players, plus the VR player (not a party seat).
func contestants() -> Array[int]:
	var out: Array[int] = []
	if bool(net.state_get("vr", false)):
		out.append(0)
	for s in party.active_slots():
		if not out.has(int(s)):
			out.append(int(s))
	out.sort()
	return out


func on_machine_left(_peer: int) -> void:
	pass  # core/party.gd frees that machine's seats (player_left); their scores stay on the board


# --- Answers ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if bool(net.state_get("vr", false)) and not podiums.has(0):
		_ensure_podium(0)
	if split != null:
		_read_pads()
	if vr_rig != null:
		_read_vr(delta)
	if net.mode != "client":
		_run_show(delta)


## Pads on this machine: A B X Y answer (sent to the host, which decides).
func _read_pads() -> void:
	if String(net.state_get("phase", "")) != "ask" or net.just_unpaused():
		return
	var locked: Dictionary = net.state_get("locked", {})
	for slot in party.local_slots():
		if locked.has(slot):
			continue
		for i in 4:
			if party.just_pressed(slot, ["a", "b", "x", "y"][i]):
				net.request(slot, "answer", [i])
				sound("ui_select", -4.0, 1.0 + 0.08 * i)
				break


## The VR player slaps a desk button.
func _read_vr(delta: float) -> void:
	vr_press_t = maxf(0.0, vr_press_t - delta)
	for i in 4:
		var cap: Node3D = desk_buttons[i].get_node("Cap")
		cap.position.y = lerpf(cap.position.y, 0.0, 1.0 - exp(-10.0 * delta))
	if String(net.state_get("phase", "")) != "ask" or not desk_buttons[0].visible:
		return
	var locked: Dictionary = net.state_get("locked", {})
	if locked.has(0) or vr_press_t > 0.0:
		return
	for i in 4:
		var p := desk_buttons[i].global_position + Vector3.UP * 0.03
		var h := vr_rig.touching_any(p, BUTTON_R + 0.04)
		if h >= 0:
			vr_press_t = 0.4
			(desk_buttons[i].get_node("Cap") as Node3D).position.y = -0.025
			vr_rig.pulse(h, 0.6, 0.08)
			sound("ui_select", -2.0, 1.0 + 0.08 * i)
			on_request(0, "answer", [i])
			return


## Host / local: a player asked for something (net.request from any machine lands here).
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"answer":
			if String(net.state_get("phase", "")) != "ask" or picks.has(slot) or args.is_empty():
				return
			var i := clampi(int(args[0]), 0, 3)
			if q_kind == "lightning" and i > 1:
				return  # TRUE or FALSE: only green and red
			picks[slot] = i
			pick_frac[slot] = clampf(1.0 - phase_t / ask_time, 0.0, 1.0)
			pick_reveal[slot] = float(net.state_get("tiles", 0)) / float(TILE_COLS * TILE_ROWS)
			var locked: Dictionary = net.state_get("locked", {})
			locked[slot] = true
			net.state_set("locked", locked)
		"next_show":
			if String(net.state_get("phase", "")) == "results":
				_new_show()


# --- The show (host / local) ----------------------------------------------------------------

func _new_show() -> void:
	bank.new_show(save.data.get("recent", []))
	awards.reset()
	picks.clear()
	streak.clear()
	best_streak.clear()
	net.state_set("scores", {})
	net.state_set("show", int(net.state_get("show", 0)) + 1)
	round_i = -1
	q_n = 0
	_ask({"text": "Who is playing? Pick a level!", "answers": Rounds.LEVELS.duplicate(), "cat": "LEVEL", "correct": -1,
		"id": 0}, "level", 1)


func _ask(q: Dictionary, kind: String, tier: int) -> void:
	q_kind = kind
	q_tier = tier
	q_correct = int(q.get("correct", -1))
	picks.clear()
	pick_frac.clear()
	pick_reveal.clear()
	phase_t = 0.0
	all_in_t = -1.0
	ask_time = Rounds.answer_time(kind, tier)
	var info: Dictionary = Rounds.INFO[kind]
	var shown := {"text": String(q.text), "answers": q.answers, "cat": String(q.get("cat", "")), "kind": kind,
		"pic": String(q.get("pic", "")), "id": int(q.get("id", 0)), "round": String(info.title)}
	net.state_set("q", shown)
	net.state_set("qn", q_n)
	net.state_set("qt", Rounds.count(show_length, kind) if kind != "level" else 0)
	net.state_set("locked", {})
	net.state_set("reveal", {})
	net.state_set("tiles", 0)
	net.state_set("time", int(ceil(ask_time)))
	net.state_set("phase", "ask")


func _run_show(delta: float) -> void:
	phase_t += delta
	var phase := String(net.state_get("phase", ""))
	match phase:
		"ask":
			if contestants().is_empty():
				phase_t = minf(phase_t, 0.5)  # nobody is playing yet (or everyone left): the clock waits
			var left := maxf(0.0, ask_time - phase_t)
			if int(ceil(left)) != int(net.state_get("time", 0)):
				net.state_set("time", int(ceil(left)))
				if left <= 3.0 and left > 0.0:
					net.event("tick", [])
					sound("tick", -6.0)
			if q_kind == "picture":
				var want := mini(int(phase_t / (ask_time * 0.85) * float(TILE_COLS * TILE_ROWS)), TILE_COLS * TILE_ROWS - 2)
				if want != int(net.state_get("tiles", 0)):
					net.state_set("tiles", want)
			var everyone := not contestants().is_empty()
			for s in contestants():
				if not picks.has(s):
					everyone = false
			if everyone and all_in_t < 0.0:
				all_in_t = phase_t
			if left <= 0.0 or (all_in_t >= 0.0 and phase_t - all_in_t > Rounds.ALL_IN_LOCK):
				_reveal()
		"reveal":
			if phase_t > reveal_time:
				_next()
		"intro":
			if phase_t > intro_time:
				q_n = 0
				_next_question()
		"results":
			if phase_t > Rounds.RESULTS_AUTO:
				_new_show()


func _reveal() -> void:
	var gains := {}
	var scores: Dictionary = net.state_get("scores", {}).duplicate()
	if q_kind == "level":
		var votes := [0, 0, 0, 0]
		for s in picks:
			votes[int(picks[s])] += 1
		level = 1  # nobody voted: FAMILY
		var top := 0
		for i in 4:
			if int(votes[i]) > top:
				top = int(votes[i])
				level = i
		q_correct = level
	else:
		for s in contestants():
			var right: bool = picks.has(s) and int(picks[s]) == q_correct
			var st := int(streak.get(s, 0))
			if right:
				var pts := Scoring.points(q_kind, float(pick_frac.get(s, 0.0)), float(pick_reveal.get(s, 0.0)), st)
				gains[s] = pts
				scores[s] = int(scores.get(s, 0)) + pts
				awards.add(s, "score", pts)
				awards.add(s, "correct")
				if q_kind == "lightning":
					streak[s] = st + 1
					best_streak[s] = maxi(int(best_streak.get(s, 0)), st + 1)
					awards.set_stat(s, "best_streak", float(best_streak[s]))
				awards.best(s, "fastest_answer", snappedf(float(1.0 - float(pick_frac.get(s, 0.0))) * ask_time, 0.1), true)
			elif q_kind == "lightning":
				streak[s] = 0
	net.state_set("scores", scores)
	net.state_set("reveal", {"correct": q_correct, "picks": picks.duplicate(), "gains": gains})
	net.state_set("tiles", TILE_COLS * TILE_ROWS)
	net.state_set("phase", "reveal")
	phase_t = 0.0


func _next() -> void:
	if round_i < 0 or q_n >= Rounds.count(show_length, Rounds.ORDER[round_i]):
		round_i += 1
		if round_i >= Rounds.ORDER.size():
			_end_show()
			return
		net.state_set("round", Rounds.ORDER[round_i])
		net.state_set("phase", "intro")
		phase_t = 0.0
		return
	_next_question()


func _next_question() -> void:
	var kind: String = Rounds.ORDER[round_i]
	q_n += 1
	var tier := Rounds.tier_for(level, q_n - 1, kind)
	var q: Dictionary
	match kind:
		"picture":
			q = bank.pick_picture(tier)
		"lightning":
			q = bank.pick_tf(tier)
		_:
			q = bank.pick_mc("", tier)
	if q.is_empty():
		q = bank.pick_mc("", tier)
	_remember(int(q.get("id", 0)))
	_ask(q, kind, tier)


func _remember(id: int) -> void:
	var recent: Array = save.data.get("recent", [])
	recent.append(id)
	while recent.size() > RECENT_KEEP:
		recent.pop_front()
	save.data["recent"] = recent
	save.mark_dirty()


func _end_show() -> void:
	var scores: Dictionary = net.state_get("scores", {})
	var top := 0
	var winners: Array[int] = []
	for s in contestants():
		var v := int(scores.get(s, 0))
		awards.set_player(s, party.name_of(s))
		awards.set_stat(s, "score", float(v))
		if v > top:
			top = v
			winners = [s]
		elif v == top and v > 0:
			winners.append(s)
	var title := "WHAT A SHOW!"
	if contestants().size() == 1:
		title = "YOU SCORED %d!" % top
	elif winners.size() == 1:
		title = "%s WINS!" % party.name_of(winners[0])
	elif winners.size() > 1:
		title = "IT'S A TIE!"
	if top > int(save.data["best"]):
		save.data["best"] = top
		save.mark_dirty()
		net.state_set("best", top)
	var data := awards.results({"title": title, "subtitle": "Thanks for playing!", "style": "victory",
		"stats": [["BEST EVER", str(int(save.data["best"]))]], "score_format": "%d PTS", "continue": "New show"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


## True while the results are on screen (bots).
func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


## Host: the right answer of the question being asked (bots).
func current_correct() -> int:
	return q_correct


# --- What every machine shows (driven by the state store) --------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"phase":
			_on_phase(String(value))
		"q", "locked", "reveal", "scores", "time", "tiles", "vr":
			_refresh_all()


func _on_phase(phase: String) -> void:
	match phase:
		"intro":
			_hide_results()
			var info: Dictionary = Rounds.INFO.get(String(net.state_get("round", "warmup")), Rounds.INFO["warmup"])
			if hud != null:
				HudKit.banner(hud, String(info.title), String(info.sub), {"duration": intro_time, "color": info.color})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, String(info.title), String(info.sub), {"duration": intro_time, "color": info.color, "sound": ""})
			sound("fanfare", -4.0)
		"ask":
			_hide_results()
			sound("ding", -6.0)
		"reveal":
			sound("reveal", -4.0)
			var r: Dictionary = net.state_get("reveal", {})
			var gains: Dictionary = r.get("gains", {})
			var any_local_right := false
			for s in gains:
				if party.is_local(int(s)) or (int(s) == 0 and vr_rig != null):
					any_local_right = true
				if avatars.has(s):
					Creatures.anim(avatars[s]).play("cheer", 1.2)
			if String((net.state_get("q", {}) as Dictionary).get("kind", "")) != "level":
				sound("correct" if any_local_right or not gains.is_empty() else "wrong", -3.0)
		"results":
			_show_results(net.state_get("results", {}))
	_refresh_all()


func _refresh_all() -> void:
	if not ready_to_play:
		return
	var phase := String(net.state_get("phase", ""))
	var q: Dictionary = net.state_get("q", {})
	var r: Dictionary = net.state_get("reveal", {})
	var locked: Dictionary = net.state_get("locked", {})
	var scores: Dictionary = net.state_get("scores", {})
	var kind := String(q.get("kind", ""))
	var asking := phase == "ask" or phase == "reveal"
	var answers: Array = q.get("answers", [])
	var correct := int(r.get("correct", -1)) if phase == "reveal" else -1
	var picked: Dictionary = r.get("picks", {}) if phase == "reveal" else {}
	var gains: Dictionary = r.get("gains", {}) if phase == "reveal" else {}
	var cat := String(q.get("cat", ""))
	var info_text := String(q.get("round", ""))
	if int(net.state_get("qt", 0)) > 0:
		info_text += "   %d / %d" % [int(net.state_get("qn", 0)), int(net.state_get("qt", 0))]
	var show_pic := asking and kind == "picture"
	# big screen
	scr_info.text = (info_text + "   %ds" % int(net.state_get("time", 0))) if phase == "ask" else info_text
	scr_info.visible = asking
	scr_question.text = String(q.get("text", "")) if asking else ""
	scr_center.visible = asking and not show_pic
	scr_center.text = cat if kind == "warmup" or kind == "final" else ""
	if cat != "":
		scr_center.modulate = QuestionBank.category_color(cat)
	if phase == "reveal" and kind == "level":
		scr_center.text = "%s it is!" % Rounds.LEVELS[clampi(correct, 0, 3)]
		scr_center.modulate = Color(1.0, 0.8, 0.3)
	for i in 4:
		var t: Dictionary = scr_tiles[i]
		var on := asking and i < answers.size()
		(t.panel as Node3D).visible = on
		(t.label as Node3D).visible = on
		if on:
			(t.label as Label3D).text = String(answers[i])
			var dim := correct >= 0 and i != correct
			(t.panel as GeometryInstance3D).transparency = 0.75 if dim else 0.0
			(t.label as Label3D).modulate = Color(1, 1, 1, 0.35) if dim else Color.WHITE
	_refresh_picture(show_pic, String(q.get("pic", "")), int(q.get("id", 0)), int(net.state_get("tiles", 0)))
	# VR desk
	var desk_on := asking and (vr_rig != null or bool(net.state_get("vr", false)))
	_set_desk_visible(desk_on)
	for i in 4:
		desk_buttons[i].visible = desk_on and i < answers.size()
		desk_labels[i].visible = desk_buttons[i].visible
		desk_labels[i].text = String(answers[i]) if i < answers.size() else ""
	desk_score.text = ("LOCKED IN!" if locked.has(0) and phase == "ask" else "YOU: %d" % int(scores.get(0, 0)))
	# podiums
	for s in podiums:
		var p: Dictionary = podiums[s]
		(p.score as Label3D).text = str(int(scores.get(s, 0)))
		var col := Color(0.3, 0.3, 0.35)
		if phase == "ask" and locked.has(s):
			col = Color(1.0, 1.0, 1.0)
		elif phase == "reveal" and kind != "level":
			col = UiKit.GOOD if gains.has(s) else (UiKit.BAD if picked.has(s) else Color(0.3, 0.3, 0.35))
		elif phase == "reveal" and picked.has(s):
			col = Rounds.LETTER_COLORS[int(picked[s])]
		(p.light as GeometryInstance3D).material_override = MeshKit.material(col, 1.5 if col.v > 0.5 else 0.0)
	# TV
	if hud == null:
		return
	_camera_shot(show_pic, 1.0)
	ui_top.visible = asking
	ui_bottom.visible = asking or phase == "intro"
	join_prompt.visible = party.local_slots().is_empty() and phase != "results"
	ui_timer.visible = phase == "ask"
	ui_timer.set_time(float(net.state_get("time", 0)))
	ui_question.text = String(q.get("text", ""))
	ui_count.text = info_text
	for c in ui_cat.get_children():
		c.queue_free()
	if cat != "" and cat != "LEVEL":
		ui_cat.add_child(UiKit.badge(cat, QuestionBank.category_color(cat), 1.0, QuestionBank.category_icon(cat)))
	for i in 4:
		var t: Dictionary = ui_tiles[i]
		var panel: Control = t.panel
		panel.visible = asking and i < answers.size()
		if not panel.visible:
			continue
		(t.label as Label).text = String(answers[i])
		panel.modulate = Color(1, 1, 1, 0.35) if correct >= 0 and i != correct else Color.WHITE
		var pk: HBoxContainer = t.pickers
		for c in pk.get_children():
			c.queue_free()
		for s in picked:
			if int(picked[s]) == i:
				pk.add_child(UiKit.badge(party.name_of(int(s)), int(s)))
	_refresh_chips(phase, kind, locked, scores, gains, picked)


## The row of players above the answers: name, score, and whether they have answered.
func _refresh_chips(phase: String, kind: String, locked: Dictionary, scores: Dictionary, gains: Dictionary, picked: Dictionary) -> void:
	for c in ui_chips.get_children():
		c.queue_free()
	for s in contestants():
		var p := UiKit.tinted_panel(party.color_of(s), 1.0, "pill")
		var h := UiKit.hbox(8)
		p.add_child(h)
		var ic := "dot"
		var ic_col: Variant = "dim"
		if phase == "ask" and locked.has(s):
			ic = "lock"
			ic_col = "text"
		elif phase == "reveal" and kind != "level" and gains.has(s):
			ic = "check"
			ic_col = "good"
		elif phase == "reveal" and kind != "level" and picked.has(s):
			ic = "cross"
			ic_col = "bad"
		h.add_child(UiKit.icon(ic, ic_col, 24.0))
		h.add_child(UiKit.label(party.name_of(s), "small", party.color_of(s)))
		h.add_child(UiKit.label(str(int(scores.get(s, 0))), "small"))
		if gains.has(s):
			h.add_child(UiKit.label("+%d" % int(gains[s]), "small", "good"))
		ui_chips.add_child(p)


## The picture round: build the picture from its id (same on every machine) and drop the tiles
## in an order seeded by the question id.
func _refresh_picture(on: bool, id: String, qid: int, gone: int) -> void:
	pic_root.visible = on
	if not on:
		return
	if id != pic_id:
		pic_id = id
		for c in pic_root.get_children():
			c.queue_free()
		pic_cover.clear()
		if id == "":
			return
		var pic := Pictures.build(id, 1.9)
		pic_root.add_child(pic)
		var w := 3.2 / TILE_COLS
		var h := 2.1 / TILE_ROWS
		for k in TILE_COLS * TILE_ROWS:
			var tile := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(w - 0.03, h - 0.03, 0.05)
			tile.mesh = bm
			var c := Rounds.LETTER_COLORS[k % 4].darkened(0.25)
			tile.material_override = MeshKit.material(c)
			tile.position = Vector3(-1.6 + w * (k % TILE_COLS + 0.5), h * (int(k / TILE_COLS) + 0.5) - 0.05, 0.9)
			pic_root.add_child(tile)
			pic_cover.append(tile)
		var rng := RandomNumberGenerator.new()
		rng.seed = qid
		pic_order.clear()
		for k in pic_cover.size():
			pic_order.append(k)
		for k in range(pic_order.size() - 1, 0, -1):
			var j := rng.randi() % (k + 1)
			var tmp := pic_order[k]
			pic_order[k] = pic_order[j]
			pic_order[j] = tmp
	for k in pic_order.size():
		var tile: Node3D = pic_cover[pic_order[k]]
		var drop := k < gone
		if drop and tile.visible and tile.position.y > -5.0:
			var tw := tile.create_tween()
			tw.tween_property(tile, "position:y", tile.position.y - 3.0, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(func() -> void: tile.visible = false)
			tile.position.y -= 0.001  # mark it as falling (not -5: the tween owns it now)
			tile.set_meta("falling", true)
		elif not drop:
			tile.visible = true


# --- Results -------------------------------------------------------------------------------

func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	sound("applause", -4.0)
	if hud != null:
		var screen := Awards.results_screen(hud, data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "next_show"))
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
		card.continued.connect(func() -> void: net.request(0, "next_show"))
		vr_results = card


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
		music.play_mood("quiz")
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
		music.play_mood("quiz")
	vr_results = null


## Every machine: shared pause (wrist MENU or a TV pause menu).
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


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: only the VR player's pose moves; everything else is in the state store.
func make_snapshot() -> Array:
	return [vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.is_empty():
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		vr_avatar = VrRig.Avatar.new()
		add_child(vr_avatar)
		if split != null:
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)


func apply_event(kind: String, _args: Array) -> void:
	match kind:
		"tick":
			sound("tick", -6.0)
