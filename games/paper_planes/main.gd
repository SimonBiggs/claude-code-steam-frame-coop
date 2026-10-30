extends Node3D
## PAPER PLANES: Pip the post bird's letters blew away! Everyone flies (TV / Deck) or throws (VR)
## paper planes through hoops to carry them home, one team score.
## VR: grab a plane from the paper stack beside you (touch it, or pull the trigger anywhere) and
## throw it with a flick (or let go of the trigger). TV: each player flies a little plane with the
## left stick. Built on the shared engine (see games/engine_template).
##
## Each round: PICK A BREEZE (fly or throw through one of three gates: two helpful breezes, or
## today's DAILY SKY), then a FLIGHT: seeded formations of hoops (games/paper_planes/skygen.gd) for
## `round_time` s, with 1-3 star goals. Story: five chapters x three flights (story.gd); a flight
## with a star builds a piece of that chapter's place in the valley (saved, it stays). Later
## chapters bring numbered chain hoops, tiny hoops, grumpy clouds (bump = combo lost) and Gust's
## golden hoop. Quick passes build a COMBO (x2, x3). Stars unlock trails, golden planes, crowns.
## Every flight writes one telemetry line (core/telemetry.gd) so goals can be tuned from real play.

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
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Telemetry := preload("res://core/telemetry.gd")
const Meshes := preload("res://games/paper_planes/meshes.gd")
const SkyGen := preload("res://games/paper_planes/skygen.gd")
const Story := preload("res://games/paper_planes/story.gd")

const GAME_ID := "paper_planes"
const SAVE_VERSION := 2
const VR_FEET := Vector3(0.0, 0.0, 5.0)
const FLY_SPEED := 6.5  ## TV planes always fly forward
const TURN_RATE := 1.9
const PITCH_MAX := 0.65
const DART_SCALE := 0.3  ## the VR player's paper planes are 30 cm long
const MAX_DARTS := 10
const STACK_OFFSET := Vector3(0.5, 0.0, -0.35)  ## from the VR rig's origin: right, a bit ahead
const STACK_TOP := 0.95
const SIGN_POS := Vector3(0.0, 8.0, -19.0)
const FORM_TIME := 22.0  ## a formation's leftovers make way for the next one after this long (half that with 2 left)
const COMBO_TIME := 5.0  ## seconds between passes to keep the combo going
const CHAIN_BONUS := 5
const BIG_SCALE := 1.3
## The places of the valley (story chapters 0-4): position, yaw (they face the middle of the park).
const PLACES := [[Vector3(-16.0, 0.0, -3.0), 1.2], [Vector3(16.0, 0.0, -6.0), -1.2], [Vector3(-14.5, 0.0, -17.0), 0.7],
	[Vector3(14.5, 0.0, -18.0), -0.7], [Vector3(-9.0, 10.5, -26.0), 0.3]]

var round_time := 100.0  ## seconds per flight (bots shorten it)
var pick_time := 14.0  ## seconds to pick a breeze (then the first gate is picked for you)
var results_wait := 12.0  ## then the next round starts by itself
var force_chapter := -1  ## tests: fly this chapter instead of the save's


class Hoop:
	var id := 0
	var kind := 0  # skygen.gd kinds: 0 plain, 1 rainbow, 2 chain, 3 tiny, 4 gate, 5 gold
	var ci := 0  # colour (plain), number (chain), gate index (gate)
	var node: Node3D
	var mesh: MeshInstance3D
	var label: Label3D
	var home := Vector3.ZERO
	var amp := 1.0
	var phase := 0.0
	var yaw0 := 0.0
	var wob := 0.0
	var age := 0.0
	var target := Vector3.ZERO
	var target_yaw := 0.0


class Dart:  # one of the VR player's paper planes
	var id := 0
	var node: Node3D
	var body: Node3D
	var state := 0  # 0 held, 1 flying, 2 landed
	var hand := 1
	var ci := 0
	var vel := Vector3.ZERO
	var prev := Vector3.ZERO
	var t := 0.0
	var size := 1.0
	var target := Vector3.ZERO
	var dir := Vector3.FORWARD


class Flyer:  # a TV player's plane
	var slot := 0
	var node: Node3D
	var body: Node3D
	var trail: CPUParticles3D
	var look := ""
	var yaw := PI
	var pitch := 0.0
	var roll := 0.0
	var loop_t := -1.0
	var prev := Vector3.ZERO
	var target := Vector3.ZERO
	var target_yaw := PI
	var target_pitch := 0.0
	var has_target := false
	var bop_cd := 0.0
	var cloud_cd := 0.0
	var cam_ready := false


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

var hoops := {}  # id -> Hoop
var darts := {}  # id -> Dart
var flyers := {}  # slot -> Flyer
var held: Array = [null, null]  # VR: the Dart in each hand
var hand_cd := PackedFloat32Array([0.0, 0.0])
var next_id := 0
var clock := 0.0
var time_left := 0.0
var results_t := 0.0
var send_t := 0.0
var stack_node: Node3D
var stack_mesh: MeshInstance3D
var stack_wob := 0.0
var ground: MeshInstance3D
var sign_score: Label3D
var sign_time: Label3D
var sign_chapter: Label3D
var huds := {}  # slot -> UiKit root (-1 = shared view)
var score_labels := {}
var goal_labels := {}
var star_icons := {}  # slot -> Array of 3 icon Controls
var combo_labels := {}
var timers := {}
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var throws := 0  # host: darts thrown (bots read it)
var hoops_passed := 0  # host / local: hoops flown through this session
var scored_by := {}  # host / local: slot -> hoops this session (gates not counted; bots)
# --- The story flight (host simulates; every machine builds clouds / village / looks from net state) ---
var layout := {}  # SkyGen.flight() of the current flight
var layout_key := ""
var form_i := -1
var form_t := 0.0
var chain_next := 1
var chain_len := 0
var combo := 0
var last_pass_t := -100.0
var clouds: Array = []  # [{node, pos, zap}]
var cloud_key := ""
var gust: Node3D
var pip: Node3D
var pip_talk := 0.0
var village_nodes: Array = []
var village_shown: Array = []
var story_queue: Array = []  # host: [seconds left, beat]
var tele := {}  # host: what happened this flight (core/telemetry.gd)
var flights_done := 0  # host: flights finished this session (bots)
var gate_picked := ""  # host: the last breeze / DAILY picked (bots)


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
	save.version = SAVE_VERSION
	save.defaults = Story.save_defaults()
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("party")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("rainbow", "RAINBOW ACE", "%s rainbow hoops", "rainbows")
	awards.define("chain", "CHAIN CHAMP", "%s chains", "chains")
	awards.define("gold", "GOLD CATCHER", "%s golden hoops", "golds")
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
		vr_rig.bounds = Rect2(-4.0, 2.5, 8.0, 5.0)
		add_child(vr_rig)
		vr_rig.place(VR_FEET, 0.0)
		hints.set_vr_rig(vr_rig, self)
	_build_world()
	if vr_rig != null or mode == "client":
		stack_node = Node3D.new()
		stack_node.name = "PaperStack"
		add_child(stack_node)
		stack_mesh = MeshKit.instance(Meshes.stack(), false)
		stack_node.add_child(stack_mesh)
		stack_node.position = VR_FEET + STACK_OFFSET
		stack_node.visible = vr_rig != null
	if mode != "host" or flat_host:  # every machine with a screen of its own (a flat host too)
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		var sc := split.shared_camera()
		sc.position = Vector3(0.0, 9.0, 17.0)
		UiKit.look(sc, Vector3(0.0, 2.5, -4.0), Vector3.UP)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
		sfx.play_loop("wind", -20.0)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	if vr_rig != null:
		awards.set_player(0, "THROWER")
		hints.hint("vr_grab", "Grab a plane. Throw it!", {"to": "vr", "icon": "play"})
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		_publish_progress()
		_start_pick()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Paper Planes: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world() -> void:
	sky = SkyKit.apply(self, "day", vr_rig != null)
	ground = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 45.0
	disc.bottom_radius = 45.0
	disc.height = 0.2
	disc.radial_segments = 40
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.5, 0.78, 0.38))
	ground.position.y = -0.1
	add_child(ground)
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 22, Vector3(0.0, 0.0, -4.0), 34.0, 24.0, 1.2, 1.9, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 14, Vector3(0.0, 0.0, -4.0), 22.0, 14.0, 1.0, 1.5, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 60, Vector3(0.0, 0.0, -4.0), 16.0, 1.0, 0.8, 1.2,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0), Color(1.0, 1.0, 1.0)]), 5))
	# The launch deck the VR player stands on.
	var b := MeshKit.Builder.new()
	b.cylinder(1.3, 1.4, 0.12, MeshKit.at(Vector3(0.0, 0.06, 0.0)), Color(0.85, 0.65, 0.42), 24)
	b.cylinder(1.0, 1.0, 0.02, MeshKit.at(Vector3(0.0, 0.13, 0.0)), Color(0.95, 0.85, 0.55), 24)
	var deck := MeshKit.instance(b.build(), false)
	deck.position = VR_FEET
	add_child(deck)
	# The big world-locked scoreboard in the sky (readable from VR, seen by the TV planes too).
	sign_score = UiKit.label3d("0", 2.4, "gold", true)
	sign_score.outline_size = 26
	sign_score.position = SIGN_POS
	add_child(sign_score)
	sign_time = UiKit.label3d("", 0.9, "text", true)
	sign_time.outline_size = 26
	sign_time.position = SIGN_POS + Vector3(0.0, -1.9, 0.0)
	add_child(sign_time)
	sign_chapter = UiKit.label3d("", 0.75, "accent", true)
	sign_chapter.outline_size = 22
	sign_chapter.position = SIGN_POS + Vector3(0.0, 1.9, 0.0)
	add_child(sign_chapter)
	# Pip the post bird (flies around; comes close when talking).
	pip = Creatures.monster("bird", {"color": Color(1.0, 0.62, 0.25), "color2": Color(1.0, 0.9, 0.7), "scale": 0.9})
	pip.name = "Pip"
	var cap := MeshKit.Builder.new()
	cap.cylinder(0.2, 0.22, 0.12, MeshKit.at(Vector3(0.0, 0.0, 0.0)), Color(0.25, 0.45, 0.95), 12)
	cap.box(Vector3(0.2, 0.03, 0.14), MeshKit.at(Vector3(0.0, -0.05, 0.18)), Color(0.2, 0.35, 0.8))
	cap.box(Vector3(0.36, 0.24, 0.02), MeshKit.at(Vector3(0.0, -0.55, 0.45), Vector3.ONE, Vector3(0.3, 0.0, 0.0)), Color(1.0, 1.0, 0.95))
	var cap_mi := MeshKit.instance(cap.build(), false)
	cap_mi.position = Vector3(0.0, Creatures.height_of(pip) * 0.95, 0.0)
	pip.add_child(cap_mi)
	add_child(pip)
	pip.position = Vector3(6.0, 6.0, -6.0)
	var pa: Variant = Creatures.anim(pip)
	if pa != null:
		pa.set("flying", true)
	gust = MeshKit.instance(Meshes.gust(), false)
	gust.name = "Gust"
	gust.scale = Vector3.ONE * 1.8
	gust.visible = false
	add_child(gust)
	_build_village([0, 0, 0, 0, 0])


## The valley's places, built up to their stage (from net state "village"); a new piece pops in.
func _build_village(stages: Array) -> void:
	for c in PLACES.size():
		var stage := int(stages[c]) if c < stages.size() else 0
		var shown := int(village_shown[c]) if c < village_shown.size() else -1
		if stage == shown:
			continue
		if c < village_nodes.size() and is_instance_valid(village_nodes[c]):
			(village_nodes[c] as Node3D).queue_free()
		var mi := MeshKit.instance(Meshes.place(c, stage), true)
		mi.name = "Place%d" % c
		mi.position = PLACES[c][0]
		mi.rotation.y = PLACES[c][1]
		add_child(mi)
		while village_nodes.size() <= c:
			village_nodes.append(null)
			village_shown.append(-1)
		village_nodes[c] = mi
		if shown >= 0 and stage > shown:  # built just now: pop + confetti
			mi.scale = Vector3.ONE * 0.3
			var tw := mi.create_tween()
			tw.tween_property(mi, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			burst(mi.position + Vector3.UP * 2.5, Meshes.RAINBOW, 50, 1.2)
			sfx.play_at("achievement", mi.position, 0.0)
			HudKit.popup(self, mi.position + Vector3.UP * 4.5, "BUILT!", {"style": "crit", "size": 3.0, "time": 2.5})
		village_shown[c] = stage


# --- HUD ----------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var col := UiKit.vbox(4)
	card.add_child(col)
	var row := UiKit.hbox()
	col.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	row.add_child(UiKit.icon("star", "gold", 38.0))
	var l := UiKit.label("0", "number")
	row.add_child(l)
	score_labels[slot] = l
	var g := UiKit.label("", "heading", "dim")
	row.add_child(g)
	goal_labels[slot] = g
	var row2 := UiKit.hbox(6)
	col.add_child(row2)
	var stars: Array = []
	for i in 3:
		var ic := UiKit.icon("star", "gold", 30.0)
		row2.add_child(ic)
		stars.append(ic)
	star_icons[slot] = stars
	var cb := UiKit.label("", "heading", "gold")
	row2.add_child(cb)
	combo_labels[slot] = cb
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time)), "warn": 10})
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		UiKit.pin(join_prompt, Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	_refresh_hud()


func _flight() -> Dictionary:
	var f: Variant = net.state_get("flight", {})
	return f if f is Dictionary else {}


func _breeze() -> String:
	return String(_flight().get("breeze", ""))


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	var fl := _flight()
	var goals: Array = fl.get("goals", [])
	var playing := String(net.state_get("phase", "")) != "pick" and not goals.is_empty()
	var got := Story.stars_for(score, goals) if playing else 0
	var goal_text := ""
	if playing:
		goal_text = "/ %d" % int(goals[got]) if got < goals.size() else "WOW!"
	var c := int(net.state_get("combo", 0))
	var mult := _mult(c)
	for slot in score_labels:
		var l: Label = score_labels[slot]
		if is_instance_valid(l):
			l.text = str(score)
		var g: Label = goal_labels.get(slot)
		if g != null and is_instance_valid(g):
			g.text = goal_text
		var cb: Label = combo_labels.get(slot)
		if cb != null and is_instance_valid(cb):
			cb.text = ("COMBO x%d" % mult) if mult > 1 else ""
		var st: Array = star_icons.get(slot, [])
		for i in st.size():
			var ic: Control = st[i]
			if is_instance_valid(ic):
				ic.visible = playing
				ic.modulate = Color.WHITE if i < got else Color(1.0, 1.0, 1.0, 0.22)
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if sign_score != null:
		sign_score.text = str(score) + ((" x%d" % mult) if mult > 1 else "")
	if sign_chapter != null:
		sign_chapter.text = _flight_title(fl)


func _flight_title(fl: Dictionary) -> String:
	match String(fl.get("mode", "")):
		"pick":
			return "PICK A BREEZE!"
		"daily":
			return "DAILY SKY"
		"bonus":
			return "BONUS SKY"
		"story":
			return "%s  %d/%d" % [Story.chapter(int(fl.get("chapter", 0))).name, int(fl.get("flight", 0)) + 1, Story.FLIGHTS_PER_CHAPTER]
	return ""


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


# --- TV players ---------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	_ensure_flyer(slot)
	if party.is_local(slot) and split != null:
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("fly", "Fly through the hoops!", {"to": slot, "icon": "star"})
	awards.set_player(slot, party.name_of(slot))
	_refresh_hud()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	if flyers.has(slot):
		var f: Flyer = flyers[slot]
		f.node.queue_free()
		flyers.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	goal_labels.erase(slot)
	star_icons.erase(slot)
	combo_labels.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_hud()


func _ensure_flyer(slot: int) -> Flyer:
	if flyers.has(slot):
		return flyers[slot]
	var f := Flyer.new()
	f.slot = slot
	f.node = Node3D.new()
	f.node.name = "Plane%d" % slot
	add_child(f.node)
	f.body = Node3D.new()
	f.node.add_child(f.body)
	_apply_look(f)
	if vr_rig == null:  # nameplates billboard: TV only
		HudKit.nameplate(f.node, party.name_of(slot), slot, 0.6, 0.18)
	var lane := float((slot - 1) % 5) - 2.0
	f.node.position = Vector3(lane * 3.0, 3.0 + absf(lane) * 0.4, -15.0)
	f.prev = f.node.position
	f.target = f.node.position
	f.node.basis = Basis.from_euler(Vector3(0.0, f.yaw, 0.0))
	flyers[slot] = f
	return f


func _unlocks() -> Array:
	var u: Variant = net.state_get("unlocks", [])
	return u if u is Array else []


## The plane, pilot and trail of a flyer, dressed in what the stars unlocked (rebuilt when that changes).
func _apply_look(f: Flyer) -> void:
	var un := _unlocks()
	var key := ",".join(PackedStringArray(un.map(func(x: Variant) -> String: return str(x))))
	if f.look == key and f.body.get_child_count() > 0:
		return
	f.look = key
	for c in f.body.get_children():
		c.queue_free()
	if f.trail != null and is_instance_valid(f.trail):
		f.trail.queue_free()
	var col := party.color_of(f.slot)
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.plane()
	mi.material_override = Meshes.plane_material(Meshes.GOLD_COLOR if un.has("gold") else col.lerp(Color.WHITE, 0.2))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.body.add_child(mi)
	var popts := {"class": "pilot", "outfit": col, "seed": f.slot, "scale": 0.3, "lod": "far"}
	if un.has("crown"):
		popts["hat"] = "crown"
	var pilot := Creatures.humanoid(popts)
	pilot.position = Vector3(0.0, 0.0, 0.12)
	pilot.rotation.y = PI  # creatures face +Z, the plane's nose is -Z
	f.body.add_child(pilot)
	var trail := CPUParticles3D.new()
	var comet := un.has("comet_trail")
	trail.amount = 28 if comet else 16
	trail.lifetime = 1.1 if comet else 0.6
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.1
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.4 if comet else 1.0
	trail.scale_amount_curve = ResCache.get_or_make("pp_trail_curve_v1", func() -> Resource:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		return curve)
	var sparkle := un.has("sparkle_trail")
	var rainbow := un.has("rainbow_trail")
	var tcol := Color.WHITE if rainbow else col.lerp(Color.WHITE, 0.5)
	trail.mesh = ResCache.get_or_make("pp_trail_%s_%s" % [tcol.to_html(false), str(sparkle)], func() -> Resource:
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 6
		sm.rings = 3
		var m := MeshKit.material(tcol, 1.6 if sparkle else 1.0).duplicate() as StandardMaterial3D
		if rainbow:
			m.vertex_color_use_as_albedo = true
		sm.material = m
		return sm)
	if rainbow:
		trail.color_ramp = ResCache.get_or_make("pp_trail_rainbow_v1", func() -> Resource:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0])
			g.colors = PackedColorArray([Meshes.RAINBOW[0]])
			for i in range(1, Meshes.RAINBOW.size()):
				g.add_point(float(i) / float(Meshes.RAINBOW.size() - 1), Meshes.RAINBOW[i])
			return g)
	trail.position = Vector3(0.0, 0.0, 0.5)
	f.node.add_child(trail)
	f.trail = trail


## The TV machine (and local play) flies its own planes instantly and tells the host where they are.
func _fly_local(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var phase := String(net.state_get("phase", "play"))
	var steering := phase != "results"
	var magnet := _breeze() == "magnet"
	for slot in party.local_slots():
		if not flyers.has(slot):
			continue
		var f: Flyer = flyers[slot]
		var mv := party.stick(slot, "move") if steering else Vector2.ZERO
		var yaw_rate := -mv.x * TURN_RATE
		var want_pitch := -mv.y * PITCH_MAX
		var p := f.node.position
		var fwd := _forward(f.yaw, f.pitch)
		# A gentle helping hand towards a hoop just ahead (a stronger one with the MAGNET breeze).
		var aim: Variant = _assist_target(p, fwd, 15.0 if magnet else 11.0, 0.8 if magnet else 0.5)
		if aim != null:
			var d: Vector3 = (aim as Vector3) - p
			var k := 2.2 if magnet else 1.4
			yaw_rate += clampf(wrapf(atan2(-d.x, -d.z) - f.yaw, -PI, PI) * k, -0.9 * k / 1.4, 0.9 * k / 1.4)
			if absf(mv.y) < 0.3:
				want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH_MAX, PITCH_MAX)
		# Stay in the sky over the park.
		if absf(p.x) > 14.0 or p.z < -21.0 or p.z > 11.0:
			var c := Vector3(-p.x, 0.0, -4.0 - p.z)
			yaw_rate += clampf(wrapf(atan2(-c.x, -c.z) - f.yaw, -PI, PI) * 2.0, -TURN_RATE, TURN_RATE)
		if p.y < 1.0:
			want_pitch = maxf(want_pitch, 0.35)
		elif p.y > 9.5:
			want_pitch = minf(want_pitch, -0.3)
		f.yaw = wrapf(f.yaw + yaw_rate * delta, -PI, PI)
		f.pitch = lerpf(f.pitch, want_pitch, 1.0 - exp(-3.0 * delta))
		f.roll = lerpf(f.roll, clampf(yaw_rate * 0.45, -0.8, 0.8), 1.0 - exp(-5.0 * delta))
		f.prev = p
		p += _forward(f.yaw, f.pitch) * FLY_SPEED * delta
		f.node.position = p
		f.node.basis = Basis.from_euler(Vector3(f.pitch, f.yaw, 0.0))
		if net.mode == "client":
			if send:
				net.send_state(p, f.yaw, f.pitch, slot)
		elif _passable():
			var id := _check_pass(f.prev, p, 0.3)
			if id >= 0:
				_score_hoop(id, slot, p)
		_chase_camera(f, delta)


func _chase_camera(f: Flyer, delta: float) -> void:
	if split == null:
		return
	var cam := split.camera(f.slot)
	if cam == null:
		return
	var p := f.node.position
	var flat := Vector3(-sin(f.yaw), 0.0, -cos(f.yaw))
	var want := p - flat * 4.4 + Vector3.UP * (1.4 - f.pitch * 1.5)
	if not f.cam_ready:
		f.cam_ready = true
		cam.global_position = want
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-5.0 * delta))
	var look := p + _forward(f.yaw, f.pitch) * 3.0 + Vector3.UP * 0.3
	if cam.global_position.distance_to(look) > 0.1:
		UiKit.look(cam, look, Vector3.UP)


## Every machine: planes the host only hears about glide to their reported spot; barrel rolls.
func _animate_flyers(delta: float) -> void:
	for slot in flyers:
		var f: Flyer = flyers[slot]
		f.bop_cd -= delta
		f.cloud_cd -= delta
		if f.has_target and not party.is_local(int(slot)):
			var k := 1.0 - exp(-15.0 * delta)
			var old_yaw := f.yaw
			f.node.position = f.node.position.lerp(f.target, k)
			f.yaw = lerp_angle(f.yaw, f.target_yaw, k)
			f.pitch = lerpf(f.pitch, f.target_pitch, k)
			var rate := wrapf(f.yaw - old_yaw, -PI, PI) / maxf(delta, 0.001)
			f.roll = lerpf(f.roll, clampf(rate * 0.45, -0.8, 0.8), 1.0 - exp(-5.0 * delta))
			f.node.basis = Basis.from_euler(Vector3(f.pitch, f.yaw, 0.0))
		var spin := 0.0
		if f.loop_t >= 0.0:
			f.loop_t += delta / 0.7
			spin = ease(minf(f.loop_t, 1.0), -2.0) * TAU
			if f.loop_t >= 1.0:
				f.loop_t = -1.0
				spin = 0.0
		f.body.rotation = Vector3(0.0, 0.0, f.roll + spin)


## Host: a TV player's plane moved on the TV machine.
func on_remote_state(slot: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if not party.is_active(slot):
		return  # a late (unreliable) packet from a player who just left: don't bring back a ghost plane
	var f := _ensure_flyer(slot)
	var from := f.target if f.has_target else pos
	f.target = pos
	f.target_yaw = yaw
	f.target_pitch = pitch
	if not f.has_target:
		f.has_target = true
		f.node.position = pos
	if _passable():
		var id := _check_pass(from, pos, 0.3)
		if id >= 0:
			_score_hoop(id, slot, pos)


## Host: one machine left. core/party.gd frees just its seats (player_left removes their planes and
## views); this game keeps no other per-machine state.
func on_machine_left(peer: int) -> void:
	for slot in party.slots_of(peer):
		if flyers.has(slot):
			(flyers[slot] as Flyer).has_target = false


## TV machine: the VR player as seen from here (only when the host has one), plus the little window into their view.
func _make_vr_avatar() -> void:
	vr_avatar = VrRig.Avatar.new()
	add_child(vr_avatar)
	if split != null:
		split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))


static func _forward(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


# --- Hoops (host / local simulate; the TV machine mirrors) -------------------------------------

func _make_hoop(id: int, kind: int, ci: int, pos: Vector3) -> Hoop:
	var h := Hoop.new()
	h.id = id
	h.kind = kind
	h.ci = ci
	h.node = Node3D.new()
	h.node.name = "Hoop%d" % id
	add_child(h.node)
	h.node.position = pos
	if _breeze() == "big" and kind != SkyGen.GATE:
		h.node.scale = Vector3.ONE * BIG_SCALE
	h.mesh = MeshKit.instance(Meshes.hoop(kind, ci), false)
	h.mesh.scale = Vector3.ONE * 0.01
	h.node.add_child(h.mesh)
	if kind == SkyGen.RAINBOW or kind == SkyGen.GOLD:
		var sp := CPUParticles3D.new()
		sp.amount = 12
		sp.lifetime = 1.2
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = 1.0
		sp.gravity = Vector3(0.0, 0.4, 0.0)
		sp.initial_velocity_max = 0.2
		sp.mesh = ResCache.get_or_make("pp_sparkle_v1", func() -> Resource:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.07
			bm.material = MeshKit.material(Color(1.0, 0.95, 0.6), 2.0)
			return bm)
		h.node.add_child(sp)
	if kind == SkyGen.CHAIN or kind == SkyGen.GATE:
		h.label = UiKit.label3d("", 0.75 if kind == SkyGen.CHAIN else 0.45, Meshes.CHAIN_COLOR.lightened(0.4) if kind == SkyGen.CHAIN else "text", true)
		h.label.outline_size = 22
		h.label.position = Vector3(0.0, Meshes.radius(kind) + (0.6 if kind == SkyGen.CHAIN else 0.75), 0.0)
		h.label.double_sided = true
		if vr_rig == null:
			h.label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		h.node.add_child(h.label)
		_label_hoop(h)
	h.target = pos
	hoops[id] = h
	return h


## The words on a hoop: a chain hoop's number, a gate's breeze (or DAILY SKY with today's best).
func _label_hoop(h: Hoop) -> void:
	if h.label == null:
		return
	if h.kind == SkyGen.CHAIN:
		h.label.text = str(h.ci)
		return
	var gates: Variant = net.state_get("gates", [])
	var id := String(gates[h.ci]) if gates is Array and h.ci < (gates as Array).size() else ""
	if id == Story.DAILY_GATE:
		var best := int(net.state_get("daily_best", 0))
		h.label.text = "DAILY SKY" + ("\nBEST %d" % best if best > 0 else "")
		h.label.modulate = Color(0.45, 0.85, 1.0)
	elif Story.BREEZES.has(id):
		h.label.text = String(Story.BREEZES[id][0])
		h.label.modulate = Story.BREEZES[id][2]


func _spawn_spec(spec: Dictionary) -> Hoop:
	next_id += 1
	var home: Vector3 = spec.pos
	var h := _make_hoop(next_id, int(spec.kind), int(spec.ci), home)
	h.home = home
	h.amp = float(spec.amp)
	h.phase = float(spec.phase)
	h.yaw0 = float(spec.yaw)
	_move_hoop(h)
	return h


func _move_hoop(h: Hoop) -> void:
	var t := clock
	if h.kind == SkyGen.GOLD:
		var p := SkyGen.gold_pos(t + h.phase)
		h.node.position = p
		h.node.rotation.y = SkyGen.yaw_to_vr(p)
		return
	var amp := h.amp * (0.4 if _breeze() == "slow" else 1.0)
	h.node.position = h.home + Vector3(sin(t * 0.33 + h.phase) * SkyGen.DRIFT.x, sin(t * 0.51 + h.phase * 1.7) * SkyGen.DRIFT.y,
		sin(t * 0.26 + h.phase * 0.6) * SkyGen.DRIFT.z) * amp
	h.node.rotation.y = h.yaw0 + sin(t * 0.21 + h.phase) * 0.3 * amp


## Every machine: pop-in, wobble and the rainbow's spin; Gust rides along with the golden hoop.
func _animate_hoops(delta: float) -> void:
	var gold: Hoop = null
	for id in hoops:
		var h: Hoop = hoops[id]
		h.age += delta
		h.wob = move_toward(h.wob, 0.0, delta * 1.4)
		var grow := clampf(h.age / 0.5, 0.0, 1.0)
		var s := (1.0 + sin(grow * PI) * 0.25) * grow if grow < 1.0 else 1.0
		s *= 1.0 + sin(clock * 20.0) * 0.14 * h.wob
		if h.kind == SkyGen.GATE:
			s *= 1.0 + sin(clock * 3.0 + h.ci) * 0.04
		h.mesh.scale = Vector3.ONE * maxf(s, 0.01)
		if h.kind == SkyGen.RAINBOW or h.kind == SkyGen.GOLD:
			h.mesh.rotation.z += delta * 1.2
		if h.kind == SkyGen.GOLD:
			gold = h
	gust.visible = gold != null
	if gold != null:
		var want := gold.node.position + Vector3(0.0, 1.9, 0.0) - gold.node.global_basis.x * 0.8
		gust.position = gust.position.lerp(want, 1.0 - exp(-6.0 * delta)) if gust.position.distance_to(want) < 6.0 else want
		gust.rotation.y = gold.node.rotation.y
		gust.position.y += sin(clock * 4.0) * 0.004


## Which hoop the segment from -> to flies through (its id), or -1.
func _check_pass(from: Vector3, to: Vector3, margin: float) -> int:
	if from.is_equal_approx(to):
		return -1
	var picking := String(net.state_get("phase", "")) == "pick"
	for id in hoops:
		var h: Hoop = hoops[id]
		if h.age < 0.4 or (picking != (h.kind == SkyGen.GATE)):
			continue
		var inv := h.node.global_transform.affine_inverse()
		var a := inv * from
		var b := inv * to
		if (a.z > 0.0) == (b.z > 0.0):
			continue
		var c := a.lerp(b, a.z / (a.z - b.z))
		if Vector2(c.x, c.y).length() < Meshes.radius(h.kind) + margin:
			return int(id)
	return -1


## Hoops can be flown through now (gates while picking, the rest while flying).
func _passable() -> bool:
	var ph := String(net.state_get("phase", ""))
	return ph == "play" or ph == "pick"


## The centre of the best hoop ahead of `pos` along `dir` (within `max_angle` rad), or null.
func _assist_target(pos: Vector3, dir: Vector3, max_dist: float, max_angle: float) -> Variant:
	var best: Variant = null
	var best_a := max_angle
	for id in hoops:
		var h: Hoop = hoops[id]
		if h.age < 0.4:
			continue
		var d := h.node.position - pos
		if d.length() > max_dist or d.length() < 0.3:
			continue
		var a := dir.angle_to(d)
		var facing := absf(d.normalized().dot(h.node.global_basis.z.normalized()))
		if a < best_a and facing > 0.35:
			best_a = a
			best = h.node.position
	return best


static func _mult(c: int) -> int:
	return 3 if c >= 10 else (2 if c >= 4 else 1)


func _score_hoop(id: int, by: int, pos: Vector3) -> void:
	var h: Hoop = hoops[id]
	if h.kind == SkyGen.GATE:
		_pick_gate(h, by)
		return
	hoops.erase(id)
	var at := h.node.position
	h.node.queue_free()
	hoops_passed += 1
	scored_by[by] = int(scored_by.get(by, 0)) + 1
	# Combo: passes close together multiply.
	var window := COMBO_TIME * (1.6 if _breeze() == "streak" else 1.0)
	combo = combo + 1 if clock - last_pass_t <= window else 1
	last_pass_t = clock
	tele["max_combo"] = maxi(int(tele.get("max_combo", 0)), combo)
	net.state_set("combo", combo)
	var mult := _mult(combo)
	var pts: int = int(SkyGen.POINTS[h.kind]) * mult
	var kname: String = ["plain", "rainbow", "chain", "tiny", "gate", "gold"][h.kind]
	var kinds: Dictionary = tele.get("kinds", {})
	kinds[kname] = int(kinds.get(kname, 0)) + 1
	tele["kinds"] = kinds
	var extra := ""
	if h.kind == SkyGen.CHAIN:
		if h.ci == chain_next:
			chain_next += 1
			if chain_next > chain_len:
				pts += CHAIN_BONUS * mult
				extra = "CHAIN!"
				tele["chains"] = int(tele.get("chains", 0)) + 1
				awards.add(by, "chains")
		elif chain_next <= chain_len:
			chain_next = 99  # out of order: this chain's bonus is gone
			tele["chain_breaks"] = int(tele.get("chain_breaks", 0)) + 1
	if h.kind == SkyGen.GOLD:
		tele["golds"] = int(tele.get("golds", 0)) + 1
		awards.add(by, "golds")
		extra = "GOLD!"
	awards.add(by, "score", pts)
	if h.kind == SkyGen.RAINBOW:
		awards.add(by, "rainbows")
	var score := int(net.state_get("score", 0)) + pts
	net.state_set("score", score)
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)
	hoop_fx(at, h.kind, h.ci, by, pts, extra)
	net.event("pass", [id, at, by, h.kind, h.ci, pts, extra])


## Burst, "+1", sounds, rumble: on both machines.
func hoop_fx(at: Vector3, kind: int, ci: int, by: int, pts: int, extra: String = "") -> void:
	var cols: Array[Color] = [Meshes.HOOP_COLORS[ci % Meshes.HOOP_COLORS.size()], Color.WHITE]
	match kind:
		SkyGen.RAINBOW:
			cols = Meshes.RAINBOW.duplicate()
		SkyGen.CHAIN:
			cols = [Meshes.CHAIN_COLOR, Color.WHITE]
		SkyGen.TINY:
			cols = [Meshes.TINY_COLOR, Color.WHITE]
		SkyGen.GOLD:
			cols = [Meshes.GOLD_COLOR, Color(1.0, 1.0, 0.7)]
	var big := kind == SkyGen.RAINBOW or kind == SkyGen.GOLD or extra != ""
	burst(at, cols, 40 if big else 22, 1.0 if big else 0.7)
	HudKit.score(self, at + Vector3.UP * 1.1, pts, {"color": "gold" if big else party.color_of(by), "size": 3.0 if big else 2.2})
	if extra != "":
		HudKit.popup(self, at + Vector3.UP * 2.0, extra, {"style": "crit", "size": 2.6, "time": 1.6})
	sfx.play_at("ding", at, 0.0, 1.0 + randf() * 0.15 + (0.1 * (ci - 1) if kind == SkyGen.CHAIN else 0.0))
	sfx.play("sparkle", -6.0)
	if big:
		sfx.play("achievement", -2.0)
	if sign_score != null:
		var tw := sign_score.create_tween()
		sign_score.scale = Vector3.ONE * 1.3
		tw.tween_property(sign_score, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if by >= 0 and party.is_local(by):
		party.rumble(by, 0.4, 0.7, 0.25)
	if by == 0 and vr_rig != null:
		vr_rig.pulse(VrRig.LEFT, 0.6, 0.1)
		vr_rig.pulse(VrRig.RIGHT, 0.6, 0.1)


func burst(at: Vector3, cols: Array[Color], amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.initial_velocity_min = 3.0 * speed
	p.initial_velocity_max = 6.0 * speed
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	# Cached: one confetti mesh, one colour ramp per palette (no allocations per burst).
	p.mesh = ResCache.get_or_make("pp_confetti_v1", func() -> Resource:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.12, 0.02)
		bm.material = MeshKit.vertex_material(true)
		return bm)
	var key := "pp_ramp"
	for c in cols:
		key += "_" + c.to_html(false)
	p.color_initial_ramp = ResCache.get_or_make(key, func() -> Resource:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0])
		g.colors = PackedColorArray([cols[0]])
		for i in range(1, cols.size()):
			g.add_point(float(i) / float(cols.size() - 1), cols[i])
		return g)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	add_child(p)
	p.position = at
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


# --- Grumpy clouds (every machine builds them from the seed; the host decides bumps) -----------

func _layout_for(sky_state: Dictionary) -> Dictionary:
	var key := "%d:%d:%s" % [int(sky_state.get("seed", 0)), int(sky_state.get("chapter", 0)), str(sky_state.get("lucky", false))]
	if key != layout_key:
		layout_key = key
		layout = SkyGen.flight(int(sky_state.get("seed", 0)), int(sky_state.get("chapter", 0)), {"lucky": bool(sky_state.get("lucky", false))})
	return layout


func _build_clouds(sky_state: Dictionary) -> void:
	var form := int(sky_state.get("form", -1))
	var key := "%d:%d:%d" % [int(sky_state.get("seed", 0)), int(sky_state.get("chapter", 0)), form]
	if key == cloud_key:
		return
	cloud_key = key
	for c in clouds:
		var n: Node3D = c.node
		if is_instance_valid(n):
			var tw := n.create_tween()
			tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.4)
			tw.tween_callback(n.queue_free)
	clouds.clear()
	if form < 0:
		return
	var fl := _layout_for(sky_state)
	var forms: Array = fl.get("formations", [])
	if form >= forms.size():
		return
	for p in forms[form].get("clouds", []):
		var n := Node3D.new()
		n.name = "StormCloud"
		add_child(n)
		n.position = p
		n.rotation.y = SkyGen.yaw_to_vr(p) * 0.5
		var mi := MeshKit.instance(Meshes.storm_cloud(), false)
		n.add_child(mi)
		var zap := MeshKit.instance(Meshes.zap(), false)
		zap.position = Vector3(0.1, -0.9, 0.3)
		zap.visible = false
		n.add_child(zap)
		n.scale = Vector3.ONE * 0.01
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		clouds.append({"node": n, "pos": p, "zap": zap, "mesh": mi})


## Every machine: clouds bob and grumble (a little zap now and then is the "keep away" tell).
func _animate_clouds(_delta: float) -> void:
	for i in clouds.size():
		var c: Dictionary = clouds[i]
		var mi: Node3D = c.mesh
		mi.position.y = sin(clock * 1.3 + i) * 0.15
		var z: Node3D = c.zap
		z.visible = fmod(clock + i * 0.7, 2.4) < 0.18


## Host: planes and VR paper planes that fly into a grumpy cloud.
func _cloud_hits() -> void:
	if clouds.is_empty():
		return
	for slot in flyers:
		var f: Flyer = flyers[slot]
		if f.cloud_cd > 0.0:
			continue
		for i in clouds.size():
			if f.node.position.distance_to(clouds[i].pos) < SkyGen.CLOUD_R + 0.25:
				_cloud_bump(int(slot), i)
				break
	for id in darts:
		var d: Dart = darts[id]
		if d.state != 1:
			continue
		for i in clouds.size():
			if d.node.position.distance_to(clouds[i].pos) < SkyGen.CLOUD_R:
				d.state = 2
				d.t = 0.0
				d.vel = Vector3.ZERO
				tele["cloud_darts"] = int(tele.get("cloud_darts", 0)) + 1
				sfx.play_at("boing", d.node.position, -4.0, 0.7)
				break


func _cloud_bump(slot: int, ci: int) -> void:
	var f: Flyer = flyers[slot]
	f.cloud_cd = 2.0
	tele["cloud_hits"] = int(tele.get("cloud_hits", 0)) + 1
	if combo > 0:
		combo = 0
		net.state_set("combo", 0)
	cloud_fx(slot, ci)
	net.event("cloud", [slot, ci])


func cloud_fx(slot: int, ci: int) -> void:
	if flyers.has(slot):
		var f: Flyer = flyers[slot]
		f.loop_t = 0.0
		HudKit.popup(self, f.node.position + Vector3.UP * 0.9, "BUMP!", {"style": "miss", "size": 2.0})
		sfx.play_at("boing", f.node.position, 0.0, 0.7)
		if party.is_local(slot):
			party.rumble(slot, 0.7, 0.5, 0.3)
			if split != null and huds.has(slot):
				HudKit.toast(huds[slot], "Grumpy cloud! Combo lost", {"icon": "cross", "duration": 1.8, "where": "top"})
	if ci >= 0 and ci < clouds.size():
		var z: Node3D = clouds[ci].zap
		z.visible = true
		sfx.play_at("zap", clouds[ci].pos, -4.0)


# --- The VR player's paper planes (host / local) --------------------------------------------

func _make_dart(id: int, ci: int) -> Dart:
	var d := Dart.new()
	d.id = id
	d.ci = ci
	d.node = Node3D.new()
	d.node.name = "Dart%d" % id
	add_child(d.node)
	d.body = MeshInstance3D.new()
	(d.body as MeshInstance3D).mesh = Meshes.plane()
	var tint: Color = Meshes.GOLD_COLOR if _unlocks().has("gold") else Meshes.HOOP_COLORS[ci % Meshes.HOOP_COLORS.size()].lerp(Color.WHITE, 0.45)
	(d.body as MeshInstance3D).material_override = Meshes.plane_material(tint)
	(d.body as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.body.scale = Vector3.ONE * DART_SCALE
	d.node.add_child(d.body)
	darts[id] = d
	return d


func _vr_hands(delta: float) -> void:
	var o := vr_rig.global_transform
	var sp := o * STACK_OFFSET
	sp.y = vr_rig.floor_height
	stack_node.global_position = sp
	stack_node.rotation.y = vr_rig.global_rotation.y
	stack_wob = move_toward(stack_wob, 0.0, delta * 2.0)
	stack_mesh.rotation = Vector3(sin(clock * 24.0) * 0.06 * stack_wob, 0.0, cos(clock * 21.0) * 0.06 * stack_wob)
	var top := sp + Vector3.UP * STACK_TOP
	var fwd := vr_rig.head_forward()
	for w in 2:
		hand_cd[w] -= delta
		var d: Dart = held[w]
		if d == null:
			var near := vr_rig.touching(w, top, 0.28)
			if near and stack_wob < 0.5:
				stack_wob = 1.0
				sfx.play("card", -8.0, 1.3)
			if (near and hand_cd[w] <= 0.0) or (w == VrRig.RIGHT and vr_rig.trigger_pressed()):
				_grab(w)
		else:
			var hv := vr_rig.hand_velocity(w)
			var flick := hv.length() > 2.4 and hv.dot(fwd) > 1.4
			if flick or (w == VrRig.RIGHT and vr_rig.trigger_released()):
				_throw(w)
			else:
				var hand := vr_rig.hand(w)
				var b := hand.global_basis.orthonormalized()
				d.node.global_transform = Transform3D(b, vr_rig.hand_point(w) - b.z * 0.07)
	# Everything in reach reacts: hoops wobble, TV planes do a barrel roll.
	for id in hoops:
		var h: Hoop = hoops[id]
		var hand_i := -1
		for w in 2:
			var lp := h.node.global_transform.affine_inverse() * vr_rig.hand_point(w)
			if absf(Vector2(lp.x, lp.y).length() - Meshes.radius(h.kind) - 0.1) < 0.2 and absf(lp.z) < 0.25:
				hand_i = w
		if hand_i >= 0 and h.wob < 0.4:
			h.wob = 1.0
			sfx.play_at("boing", h.node.position, -4.0)
			vr_rig.pulse(hand_i, 0.5, 0.08)
			net.event("wob", [int(id)])
	for slot in flyers:
		var f: Flyer = flyers[slot]
		if f.bop_cd <= 0.0 and vr_rig.touching_any(f.node.position, 0.55) >= 0:
			_bop(int(slot))


func _grab(w: int) -> void:
	next_id += 1
	var d := _make_dart(next_id, next_id % Meshes.HOOP_COLORS.size())
	d.hand = w
	held[w] = d
	d.node.global_position = vr_rig.hand_point(w)
	d.body.scale = Vector3.ONE * 0.05
	var tw := d.body.create_tween()
	tw.tween_property(d.body, "scale", Vector3.ONE * DART_SCALE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stack_wob = 1.0
	sfx.play("card", -2.0)
	vr_rig.pulse(w, 0.3, 0.05)
	_trim_darts()


func _throw(w: int) -> void:
	var d: Dart = held[w]
	held[w] = null
	hand_cd[w] = 0.6
	var hv := vr_rig.hand_velocity(w)
	var dir: Vector3 = hv.normalized() if hv.length() > 0.8 else -vr_rig.hand(w).global_basis.z
	dir = (dir + Vector3.UP * 0.08).normalized()
	d.vel = dir * clampf(hv.length() * 1.6, 4.5, 13.0)
	d.state = 1
	d.t = 0.0
	d.prev = d.node.global_position
	throws += 1
	tele["throws"] = int(tele.get("throws", 0)) + 1
	sfx.play_at("whoosh", d.prev, 0.0, 1.2)
	vr_rig.pulse(w, 0.5, 0.06)
	net.event("whoosh", [d.prev])


func _trim_darts() -> void:
	var loose: Array[int] = []
	for id in darts:
		if (darts[id] as Dart).state != 0:
			loose.append(int(id))
	loose.sort()
	while loose.size() > MAX_DARTS:
		var id: int = loose.pop_front()
		(darts[id] as Dart).node.queue_free()
		darts.erase(id)


func _fly_darts(delta: float) -> void:
	var passable := _passable()
	var magnet := _breeze() == "magnet"
	for id in darts.keys():
		if not darts.has(id):
			continue  # a gate pass started the flight and cleared the sky
		var d: Dart = darts[id]
		if d.state == 1:
			d.t += delta
			var v := d.vel
			var hs := Vector2(v.x, v.z).length()
			v.y += (-4.3 + minf(hs * 0.4, 3.6)) * delta
			v -= v * 0.07 * delta
			var aim: Variant = _assist_target(d.node.position, v, 18.0 if magnet else 14.0, 0.8 if magnet else 0.55)
			if aim != null:
				var want := ((aim as Vector3) - d.node.position).normalized()
				var dir := v.normalized()
				var ang := dir.angle_to(want)
				if ang > 0.001:
					v = dir.slerp(want, minf(1.0, (2.6 if magnet else 1.8) * delta / ang)) * v.length()
			d.vel = v
			d.prev = d.node.position
			var p := d.prev + v * delta
			_orient_dart(d, v.normalized(), sin(d.t * 9.0) * 0.25)
			d.node.position = p
			if passable:
				var hid := _check_pass(d.prev, p, 0.15)
				if hid >= 0:
					tele["dart_hits"] = int(tele.get("dart_hits", 0)) + 1
					_score_hoop(hid, 0, p)
					if not darts.has(id):
						continue
			if p.y < 0.04 or d.t > 8.0:
				d.state = 2
				d.t = 0.0
				d.node.position.y = maxf(0.03, p.y)
				var flat := Vector3(v.x, 0.0, v.z)
				_orient_dart(d, flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD, 0.0)
				sfx.play_at("pop", d.node.position, -12.0, 0.8)
		elif d.state == 2:
			d.t += delta
			if d.node.position.y > 0.05:  # bounced off a cloud: flutter down
				d.node.position.y = maxf(0.03, d.node.position.y - delta * 2.5)
			if d.t > 1.6:
				d.size = maxf(0.0, 1.0 - (d.t - 1.6) / 0.5)
				d.body.scale = Vector3.ONE * DART_SCALE * maxf(d.size, 0.01)
			if d.t > 2.1:
				d.node.queue_free()
				darts.erase(id)


static func _orient_dart(d: Dart, dir: Vector3, roll: float) -> void:
	if dir.length() < 0.01:
		return
	d.node.basis = UiKit.face(dir) * Basis(Vector3.FORWARD, roll)


func _bop(slot: int) -> void:
	var f: Flyer = flyers[slot]
	f.bop_cd = 1.5
	f.loop_t = 0.0
	sfx.play_at("boing", f.node.position, 0.0, 1.2)
	if vr_rig != null:
		vr_rig.pulse(maxi(vr_rig.touching_any(f.node.position, 0.6), 0), 0.5, 0.08)
	if party.is_local(slot):
		party.rumble(slot, 0.6, 0.3, 0.2)
	net.event("bop", [slot])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Story beats ----------------------------------------------------------------------------

## Host: tell a story beat on every machine after `delay` seconds.
func _story(beat: Dictionary, delay: float = 0.0) -> void:
	story_queue.append([delay, beat])


func _run_story_queue(delta: float) -> void:
	for i in range(story_queue.size() - 1, -1, -1):
		story_queue[i][0] -= delta
		if story_queue[i][0] <= 0.0:
			var beat: Dictionary = story_queue[i][1]
			story_queue.remove_at(i)
			show_story(beat)
			net.event("story", [beat])


## Every machine: the card on each TV view and in VR; Pip flies over to say it.
func show_story(beat: Dictionary) -> void:
	var opts := beat.duplicate()
	opts["color"] = Color.html(String(beat.get("color", "ffb347")))
	if split != null:
		StoryCard.show(_all_huds(), opts)
	if vr_rig != null:
		StoryCard.show_vr(self, vr_rig.camera, opts)
	pip_talk = float(beat.get("duration", 4.0))


func _pip_beat(line: String, duration: float = 3.5) -> Dictionary:
	return {"who": "PIP", "line": line, "pic": "bird", "color": "ffb347", "duration": duration}


func _chapter_beat(chap: int, line_key: String, duration: float = 4.5) -> Dictionary:
	var ch := Story.chapter(chap)
	var colors := ["ff7a6b", "e0503f", "4da6ff", "8c93b8", "9fd8ff", "ffb347"]
	return {"who": String(ch.who), "line": String(ch[line_key]), "pic": String(ch.pic), "color": colors[clampi(chap, 0, 5)], "duration": duration}


## Every machine: Pip circles the park, and flies close to the VR deck to talk.
func _animate_pip(delta: float) -> void:
	pip_talk = maxf(0.0, pip_talk - delta)
	var want: Vector3
	if pip_talk > 0.0:
		want = VR_FEET + Vector3(1.1, 2.2, -2.2) + Vector3(0.0, sin(clock * 5.0) * 0.12, 0.0)
	else:
		var a := clock * 0.25
		want = Vector3(sin(a) * 9.0, 6.5 + sin(a * 2.0) * 1.2, -5.0 + cos(a) * 7.0)
	var to := want - pip.position
	pip.position += to * minf(1.0, delta * (2.0 if pip_talk > 0.0 else 1.2))
	var face := VR_FEET + Vector3.UP * 1.6 - pip.position if pip_talk > 0.0 else to
	if Vector2(face.x, face.z).length() > 0.05:
		pip.rotation.y = lerp_angle(pip.rotation.y, atan2(face.x, face.z), 1.0 - exp(-4.0 * delta))


# --- Rounds: PICK A BREEZE, then a FLIGHT, then RESULTS ---------------------------------------

func _clear_sky() -> void:
	for id in hoops:
		(hoops[id] as Hoop).node.queue_free()
	hoops.clear()
	for id in darts:
		(darts[id] as Dart).node.queue_free()
	darts.clear()
	held = [null, null]


## The next story flight from the save: [chapter, flight, mode].
func _next_story() -> Array:
	var chap := mini(int(save.data["chapter"]), Story.MIXED)
	return [chap, int(save.data["flight"]), "bonus" if chap >= Story.MIXED else "story"]


## Host: share the saved progress (village pieces, unlocks, today's best) with every machine.
func _publish_progress() -> void:
	var stars: Dictionary = save.data["stars"]
	net.state_set("village", Story.village(stars))
	var stamps := Story.stamps(stars) + int(save.data.get("extra_stamps", 0))
	net.state_set("stamps", stamps)
	net.state_set("unlocks", Story.unlocked(stamps))
	var daily: Dictionary = save.data["daily"]
	net.state_set("daily_best", int(daily.get(Seeded.daily_key(), 0)))


func _start_pick() -> void:
	_clear_sky()
	awards.reset()
	combo = 0
	net.state_set("combo", 0)
	time_left = pick_time
	var choices := Story.gate_choices(Seeded.rng(Seeded.fresh_seed(), "gates"))
	net.state_set("gates", choices)
	var nx := _next_story()
	net.state_set("flight", {"mode": "pick", "chapter": nx[0], "flight": nx[1]})
	net.state_set("sky", {"seed": 0, "chapter": 0, "lucky": false, "form": -1})
	var gp := SkyGen.gate_positions()
	for i in gp.size():
		var h := _spawn_spec({"pos": gp[i], "kind": SkyGen.GATE, "ci": i, "amp": 0.12, "phase": i * 2.0, "yaw": SkyGen.yaw_to_vr(gp[i])})
		h.age = 0.0
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "pick")
	# What Pip says before this flight.
	var chap: int = nx[0]
	if chap < Story.MIXED and int(nx[1]) == 0 and int(save.data["misses"]) == 0:
		_story(_chapter_beat(chap, "intro"), 0.6)
	elif int(save.data["misses"]) > 0:
		_story(_pip_beat(Story.PIP_RETRY[int(save.data["misses"]) % Story.PIP_RETRY.size()]), 0.6)
	else:
		_story(_pip_beat(Story.PIP_LINES[int(save.data["flights"]) % Story.PIP_LINES.size()]), 0.6)
	if vr_rig != null:
		vr_rig.guard_trigger()


## Host: a gate was flown (or thrown) through: that breeze (or the DAILY SKY) it is.
func _pick_gate(h: Hoop, by: int) -> void:
	var gates: Array = net.state_get("gates", [])
	var choice := String(gates[h.ci]) if h.ci < gates.size() else String(gates[0])
	burst(h.node.position, [Color.WHITE, Meshes.GOLD_COLOR], 40, 1.0)
	net.event("gate", [h.node.position, by])
	sfx.play("magic", -2.0)
	_start_flight(choice, "gate" if by >= 0 else "timeout")


func _start_flight(choice: String, how: String) -> void:
	_clear_sky()
	gate_picked = choice
	var daily := choice == Story.DAILY_GATE
	var breeze := "" if daily else choice
	var nx := _next_story()
	var chap: int = Story.MIXED if daily else int(nx[0])
	if force_chapter >= 0 and not daily:
		chap = force_chapter
	var mode := "daily" if daily else String(nx[2])
	var seed_v := Seeded.daily_seed(GAME_ID) if daily else Seeded.fresh_seed()
	var lucky := breeze == "lucky"
	var secs := round_time * (1.2 if breeze == "tail" else 1.0)  # MORE TIME: +20% (100 s -> 120 s)
	var players := party.player_count() + (1 if vr_rig != null else 0)
	var misses := 0 if daily else int(save.data["misses"])
	var laps := int(save.data["laps"]) if mode == "bonus" else 0
	var goals := Story.goals(players, chap, misses, laps, secs)
	net.state_set("flight", {"mode": mode, "chapter": chap, "flight": int(nx[1]), "breeze": breeze, "goals": goals,
		"seed": seed_v, "lucky": lucky, "players": players})
	tele = {"mode": mode, "chapter": chap, "flight": int(nx[1]), "seed": seed_v, "breeze": breeze, "pick": how,
		"players": players, "vr": vr_rig != null, "tv_players": party.player_count(), "goals": goals,
		"misses_before": misses, "seconds": secs, "kinds": {}, "t0": clock}
	time_left = secs
	combo = 0
	last_pass_t = -100.0
	form_i = -1
	layout_key = ""
	_layout_for({"seed": seed_v, "chapter": chap, "lucky": lucky})
	net.state_set("combo", 0)
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	_next_formation()
	if chap < Story.MIXED and int(nx[1]) == 0 and String(Story.chapter(chap).new) != "" and not daily:
		_story(_pip_beat(String(Story.chapter(chap).new), 4.0), 2.6)
	elif daily:
		_story(_pip_beat("Today's sky! The same for everyone.", 3.5), 2.6)
	if vr_rig != null:
		vr_rig.guard_trigger()


## Host: the next formation of the flight (leftover hoops stay unless they're in the way).
func _next_formation() -> void:
	var forms: Array = layout.get("formations", [])
	if forms.is_empty():
		return
	form_i += 1
	form_t = 0.0
	var f: Dictionary = forms[form_i % forms.size()]
	var specs: Array = f.hoops
	var kept := 0
	for id in hoops.keys():
		var h: Hoop = hoops[id]
		# Up to two leftovers stay (someone may be about to fly through); the rest flutter away.
		var clash := h.kind == SkyGen.CHAIN or h.kind == SkyGen.GOLD or kept >= 2
		for s in specs:
			if h.node.position.distance_to(s.pos) < SkyGen.MIN_GAP:
				clash = true
		if not clash:
			kept += 1
		else:
			burst(h.node.position, [Color.WHITE], 12, 0.5)
			h.node.queue_free()
			hoops.erase(id)
	chain_next = 1
	chain_len = 0
	for s in specs:
		_spawn_spec(s)
		if int(s.kind) == SkyGen.CHAIN:
			chain_len += 1
	if bool(f.get("gold", false)):
		_spawn_spec({"pos": SkyGen.gold_pos(clock), "kind": SkyGen.GOLD, "ci": 0, "amp": 0.0, "phase": 0.0, "yaw": 0.0})
	var fl := _flight()
	net.state_set("sky", {"seed": int(fl.get("seed", 0)), "chapter": int(fl.get("chapter", 0)), "lucky": bool(fl.get("lucky", false)),
		"form": form_i % forms.size()})
	sfx.play("pop", -8.0, 1.3)


func _end_round(how: String = "time") -> void:
	var score := int(net.state_get("score", 0))
	var fl := _flight()
	var goals: Array = fl.get("goals", [1, 2, 3])
	var stars := Story.stars_for(score, goals)
	var mode := String(fl.get("mode", "story"))
	var chap := int(fl.get("chapter", 0))
	var fnum := int(fl.get("flight", 0))
	var stars_d: Dictionary = save.data["stars"]
	var before := Story.stamps(stars_d) + int(save.data.get("extra_stamps", 0))
	var adv := {}
	if mode == "story" and force_chapter < 0:
		var key := "%d-%d" % [chap, fnum]
		stars_d[key] = maxi(int(stars_d.get(key, 0)), stars)
		adv = Story.advance(chap, fnum, int(save.data["laps"]), int(save.data["misses"]), stars)
	elif mode == "bonus" and force_chapter < 0:
		save.data["extra_stamps"] = int(save.data.get("extra_stamps", 0)) + stars
		adv = Story.advance(Story.MIXED, fnum, int(save.data["laps"]), int(save.data["misses"]), stars)
	elif mode == "daily":
		var daily: Dictionary = save.data["daily"]
		var dk := Seeded.daily_key()
		daily[dk] = maxi(int(daily.get(dk, 0)), score)
		for k in daily.keys():  # keep the last few days only
			if daily.size() > 14 and String(k) < dk:
				daily.erase(k)
	if not adv.is_empty():
		save.data["chapter"] = int(adv.chapter)
		save.data["flight"] = int(adv.flight)
		save.data["laps"] = int(adv.laps)
		save.data["misses"] = int(adv.misses)
	save.data["flights"] = int(save.data["flights"]) + 1
	save.mark_dirty()
	flights_done += 1
	var after := Story.stamps(stars_d) + int(save.data.get("extra_stamps", 0))
	var news := Story.newly_unlocked(before, after)
	_publish_progress()
	# Telemetry: one line per flight.
	var t := tele.duplicate(true)
	t["score"] = score
	t["stars"] = stars
	t["end"] = how
	t["played_s"] = int(clock - float(t.get("t0", clock)))
	t.erase("t0")
	t["formations"] = form_i + 1
	t["chapter_done"] = bool(adv.get("chapter_done", false))
	Telemetry.run(GAME_ID, t)
	tele = {}
	# The results screen.
	var titles := ["NEARLY!", "LETTERS DELIVERED!", "GREAT FLYING!", "AMAZING!"]
	var stats: Array = [["POINTS", str(score)], ["STARS", "%d OF 3" % stars]]
	if stars < 3:
		stats.append(["NEXT STAR", str(int(goals[stars]))])
	if mode == "daily":
		stats.append(["BEST TODAY", str(int(net.state_get("daily_best", score)))])
	stats.append(["STAMPS", str(after)])
	for n in news:
		stats.append(["NEW!", n])
	var sub := "%d points together!" % score
	if mode == "story" and stars > 0:
		sub = "A new piece of the %s!" % String(Story.chapter(chap).place).to_lower()
	var data := awards.results({"title": titles[stars], "subtitle": sub,
		"style": "victory", "stats": stats, "score_format": "%d"})
	data["stars"] = stars
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	# Story beats.
	if bool(adv.get("story_done", false)):
		_story(_chapter_beat(4, "done", 5.0), 1.5)
		_story(_pip_beat("Every letter is home! Thank you, pilots!", 5.0), 7.0)
	elif bool(adv.get("chapter_done", false)):
		_story(_chapter_beat(chap, "done", 5.0), 1.5)
	elif stars == 0 and mode != "daily":
		_story(_pip_beat(Story.PIP_RETRY[int(save.data["misses"]) % Story.PIP_RETRY.size()]), 1.5)
	for i in news.size():
		_story({"who": "NEW!", "line": "You unlocked %s!" % String(news[i]).to_lower(), "pic": "star", "color": "ffd24d", "duration": 3.5}, 6.5 + i * 4.0)


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	for i in 3:
		burst(SIGN_POS + Vector3(randf_range(-5.0, 5.0), -3.0, 3.0), Meshes.RAINBOW, 50, 1.4)
	sfx.play("party_horn")
	sfx.play("cheer" if int(data.get("stars", 1)) > 0 else "boing", -4.0)
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


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


func on_request(_slot: int, action: String, _args: Array) -> void:
	if action == "next_round" and results_showing():
		_start_pick()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_paused(self, vr_rig.camera, "", {"width": 1.1})
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
		(tv_banner.find_child("Why", true, false) as Label).text = "by %s" % party.name_of(by_slot)
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"score", "best", "combo", "flight":
			_refresh_hud()
			if key == "flight" and value is Dictionary:
				var chap := int((value as Dictionary).get("chapter", 0))
				var ch := Story.chapter(chap)
				if sky != null and sky.preset != SkyKit.resolve(String(ch.sky)):
					sky.set_preset(String(ch.sky), 2.0)
				if ground != null:
					ground.material_override = MeshKit.material(ch.ground)
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
			if sign_time != null:
				sign_time.text = HudKit.clock_text(float(value))
			if int(value) <= 5 and int(value) > 0 and String(net.state_get("phase", "")) == "play":
				sfx.play("tick", -2.0)
		"round":
			var fl := _flight()
			var title := _flight_title(fl)
			var sub := "Fly through the hoops!"
			var breeze := String(fl.get("breeze", ""))
			if Story.BREEZES.has(breeze):
				sub = "Breeze: %s!" % String(Story.BREEZES[breeze][0])
			HudKit.banner(_all_huds(), title, sub, {"duration": 2.5})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, title, "Throw through the hoops!" if breeze == "" else sub, {"duration": 2.5, "sound": ""})
			sfx.play("go", -4.0)
		"gates", "daily_best":
			for id in hoops:
				_label_hoop(hoops[id])
		"sky":
			if value is Dictionary:
				_build_clouds(value)
		"village":
			if value is Array:
				_build_village(value)
		"unlocks":
			for slot in flyers:
				_apply_look(flyers[slot])
		"phase":
			match String(value):
				"results":
					_show_results(net.state_get("results", {}))
				"pick":
					_hide_results()
					music.play_mood("party")
					HudKit.banner(_all_huds(), "PICK A BREEZE!", "Fly through a gate", {"duration": 2.6, "style": "info"})
					if vr_rig != null:
						HudKit.vr_banner(self, vr_rig.camera, "PICK A BREEZE!", "Throw a plane through a gate", {"duration": 2.6, "sound": ""})
				_:
					_hide_results()
					music.play_mood("party")
			_refresh_hud()


# --- Game loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	clock += delta
	if split != null:
		_fly_local(delta)
	_animate_flyers(delta)
	_animate_hoops(delta)
	_animate_clouds(delta)
	_animate_pip(delta)
	if net.mode == "client":
		_mirror_darts(delta)
		return
	_run_story_queue(delta)
	if vr_rig != null:
		_vr_hands(delta)
	_fly_darts(delta)
	for id in hoops:
		_move_hoop(hoops[id])
	var phase := String(net.state_get("phase", ""))
	if phase == "results":
		results_t += delta
		if results_t > results_wait:
			_start_pick()
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if phase == "pick":
		if time_left <= 0.0:
			var gates: Array = net.state_get("gates", [])
			_start_flight(String(gates[0]) if not gates.is_empty() else "big", "timeout")
		return
	_cloud_hits()
	if combo > 0 and clock - last_pass_t > COMBO_TIME * (1.6 if _breeze() == "streak" else 1.0):
		combo = 0
		net.state_set("combo", 0)
	form_t += delta
	var left := 0
	for id in hoops:
		if (hoops[id] as Hoop).kind != SkyGen.GOLD:
			left += 1
	if left <= 1 or (left <= 2 and form_t > FORM_TIME * 0.5) or form_t > FORM_TIME:
		_next_formation()
	if time_left <= 0.0:
		_end_round()


## A flight that's cut short (the arcade menu, a quit) still writes its telemetry line.
func _exit_tree() -> void:
	if net != null and net.mode != "client" and not tele.is_empty() and String(net.state_get("phase", "")) == "play":
		var t := tele.duplicate(true)
		t["score"] = int(net.state_get("score", 0))
		t["stars"] = Story.stars_for(int(t["score"]), t.get("goals", [1, 2, 3]))
		t["end"] = "quit"
		t["played_s"] = int(clock - float(t.get("t0", clock)))
		t.erase("t0")
		t["formations"] = form_i + 1
		Telemetry.run(GAME_ID, t)
		tele = {}


# --- Networking ---------------------------------------------------------------------------

func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var sp := stack_node.global_position if stack_node != null and vr_rig != null else Vector3(0.0, -50.0, 0.0)
	var hids := PackedInt32Array()
	var hf := PackedFloat32Array()
	var hk := PackedByteArray()
	for id in hoops:
		var h: Hoop = hoops[id]
		hids.append(int(id))
		var p := h.node.position
		hf.append_array([p.x, p.y, p.z, h.node.rotation.y, h.wob])
		hk.append(h.kind * 16 + h.ci)
	var dids := PackedInt32Array()
	var df := PackedFloat32Array()
	for id in darts:
		var d: Dart = darts[id]
		dids.append(int(id) * 8 + d.ci)
		var p := d.node.global_position
		var f := -d.node.global_basis.z
		df.append_array([p.x, p.y, p.z, f.x, f.y, f.z, d.size])
	# Every plane (slot, position, yaw, pitch): each machine sees the other machines' flyers.
	var fs := PackedByteArray()
	var fp := PackedVector3Array()
	var fa := PackedFloat32Array()
	for slot in flyers:
		var f: Flyer = flyers[slot]
		fs.append(int(slot))
		fp.append(f.node.position)
		fa.append_array([f.yaw, f.pitch])
	return [pose, sp, hids, hf, hk, dids, df, fs, fp, fa]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 10:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()  # only when the host has a VR player (not on a flat host)
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var fs: PackedByteArray = s[7]
	var fp: PackedVector3Array = s[8]
	var fa: PackedFloat32Array = s[9]
	for i in fs.size():
		var slot: int = fs[i]
		if flyers.has(slot) and not party.is_local(slot):
			var f: Flyer = flyers[slot]  # _animate_flyers glides it there
			if not f.has_target:
				f.has_target = true
				f.node.position = fp[i]
			f.target = fp[i]
			f.target_yaw = fa[i * 2]
			f.target_pitch = fa[i * 2 + 1]
	var sp: Vector3 = s[1]
	if stack_node != null:
		stack_node.visible = sp.y > -10.0
		stack_node.position = sp
	var hids: PackedInt32Array = s[2]
	var hf: PackedFloat32Array = s[3]
	var hk: PackedByteArray = s[4]
	var seen := {}
	for i in hids.size():
		var id := hids[i]
		seen[id] = true
		var p := Vector3(hf[i * 5], hf[i * 5 + 1], hf[i * 5 + 2])
		var h: Hoop = hoops[id] if hoops.has(id) else _make_hoop(id, hk[i] / 16, hk[i] % 16, p)
		h.target = p
		h.target_yaw = hf[i * 5 + 3]
		h.wob = maxf(h.wob, hf[i * 5 + 4])
	for id in hoops.keys():
		if not seen.has(id):
			(hoops[id] as Hoop).node.queue_free()
			hoops.erase(id)
	var dids: PackedInt32Array = s[5]
	var df: PackedFloat32Array = s[6]
	var dseen := {}
	for i in dids.size():
		var id := dids[i] / 8
		dseen[id] = true
		var o := i * 7
		var d: Dart = darts[id] if darts.has(id) else _make_dart(id, dids[i] % 8)
		d.target = Vector3(df[o], df[o + 1], df[o + 2])
		d.dir = Vector3(df[o + 3], df[o + 4], df[o + 5])
		d.size = df[o + 6]
		if d.state == 0:
			d.state = 1
			d.node.position = d.target
	for id in darts.keys():
		if not dseen.has(id):
			(darts[id] as Dart).node.queue_free()
			darts.erase(id)


## TV machine: hoops and the VR player's planes glide to their snapshot spots.
func _mirror_darts(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	for id in hoops:
		var h: Hoop = hoops[id]
		h.node.position = h.node.position.lerp(h.target, k)
		h.node.rotation.y = lerp_angle(h.node.rotation.y, h.target_yaw, k)
	for id in darts:
		var d: Dart = darts[id]
		d.node.position = d.node.position.lerp(d.target, k)
		_orient_dart(d, d.dir, 0.0)
		d.body.scale = Vector3.ONE * DART_SCALE * maxf(d.size, 0.01)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"pass":
			var id := int(args[0])
			if hoops.has(id):
				(hoops[id] as Hoop).node.queue_free()
				hoops.erase(id)
			hoop_fx(args[1], int(args[3]), int(args[4]), int(args[2]), int(args[5]), String(args[6]) if args.size() > 6 else "")
		"gate":
			burst(args[0], [Color.WHITE, Meshes.GOLD_COLOR], 40, 1.0)
			sfx.play("magic", -2.0)
		"story":
			if args.size() > 0 and args[0] is Dictionary:
				show_story(args[0])
		"cloud":
			cloud_fx(int(args[0]), int(args[1]))
		"whoosh":
			sfx.play_at("whoosh", args[0], 0.0, 1.2)
		"wob":
			if hoops.has(int(args[0])):
				var h: Hoop = hoops[int(args[0])]
				h.wob = 1.0
				sfx.play_at("boing", h.node.position, -4.0)
		"bop":
			var slot := int(args[0])
			if flyers.has(slot):
				var f: Flyer = flyers[slot]
				f.loop_t = 0.0
				sfx.play("boing", 0.0, 1.2)
				if party.is_local(slot):
					party.rumble(slot, 0.6, 0.3, 0.2)
