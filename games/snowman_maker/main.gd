extends Node3D
## SNOWMAN MAKER: a snowy garden. TV players roll snowballs (they grow as they roll); the VR player
## lifts them with the right trigger and stacks them into snowmen, then adds a carrot nose and a hat
## from the two boxes. Every finished snowman cheers and dances. Make as many as you can in 3 minutes.
## Rolling a ball into another ball (or a half-built snowman) makes them stack, so TV players (and the no-VR local
## game) can build too; TV players run into a box to carry a carrot or hat to a snowman.
## STORY + DEPTH: Tumble the penguin gets the village ready for the Winter Fair. Each round is a snow
## day in a seeded garden (games/snowman_maker/gardengen.gd: boxes, pines, ice, deep drifts, spawns);
## visitors wish for a snowman with a certain hat (a picture in a bubble), a granted wish counts double;
## star goals per day; days with a star build the village round the garden (saved); unlocks dress the
## snowmen; the first game of each date is the DAILY GARDEN. Tumble helps a lone builder.
## Story data: story.gd; village meshes: village.gd. One telemetry line per day (core/telemetry.gd).
## Built on the engine template: net modes, party seats, split view, VR rig, state store, awards.

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
const Snowman := preload("res://games/snowman_maker/snowman.gd")
const Story := preload("res://games/snowman_maker/story.gd")
const GardenGen := preload("res://games/snowman_maker/gardengen.gd")
const Village := preload("res://games/snowman_maker/village.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Telemetry := preload("res://core/telemetry.gd")

const GAME_ID := "snowman_maker"
const ARENA := 9.0
const SPEED := 4.2
const BODY_R := 0.32  # TV players / helpers push balls from this far
const BALL_MIN := 0.16
const BALL_MAX := 0.42
const GROW := 0.03  # radius gained per metre rolled
const MAX_FREE := 6
const YARD := Vector3(0.0, 0.0, 0.0)  # the glowing build circle in front of the VR player
const YARD_R := 1.8
const VR_START := Vector3(0.0, 0.0, 2.3)
const BOX_TOP := 0.5
const SIGN_POS := Vector3(2.9, 0.0, -1.2)
const CARROT := 0  # item kinds: 0 carrot, 1.. hats (story.gd)
const HAT := 1
const TREE_R := 0.5  # gardengen.gd TREE_R
const HAT_PICS := ["", "tophat", "beanie", "crown"]
const HAT_COLORS := [Color(1.0, 0.55, 0.15), Color(0.95, 0.25, 0.3), Color(0.9, 0.22, 0.28), Color(1.0, 0.8, 0.2)]
const BOX_COLORS := [Color(0.75, 0.5, 0.25), Color(0.3, 0.3, 0.4), Color(0.85, 0.2, 0.3), Color(0.95, 0.75, 0.2)]
const GROUND := 0
const HELD := 1
const FLYING := 2
const LOOKS: Array[String] = ["farmer", "chef", "pirate", "bard", "villager", "princess", "viking"]
const INTRO := {
	"title": "SNOWMAN MAKER",
	"goal": "Roll, stack, decorate!",
	"vr": {"role": "THE BUILDER", "controls": [["TRIGGER", "Grab + lift"], ["L-STICK", "Walk"]]},
	"tv": {"role": "THE ROLLERS", "controls": [["L-STICK", "Roll snow"]], "tips": ["Push snowballs to the circle!"]},
}

var round_time := 150.0  ## seconds per snow day (bots shorten it)
var force_chapter := -1  ## tests: play this chapter's garden (progress isn't saved)

# --- Networking contract / engine modules ---
var net: Node
var ready_to_play := false
var flat_host := false  # this machine hosts without VR: slot 0 is a pad / keyboard player here, like local play
var net_target := {}  # slot -> [pos, yaw]: where another machine's player is (smoothed towards every frame)
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

var avatars := {}  # slot -> Node3D
var last_pos := {}  # slot -> Vector3
var cams := {}  # slot -> CameraRig
var group_cam: CameraRig
var huds := {}  # slot -> UiKit root (-1 = shared view)
var score_labels := {}
var timers := {}
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var sign_label: Label3D
var sign_time: Label3D
var boxes: Array[Node3D] = []
var box_pos: Array[Vector3] = []  # this garden's boxes (every machine builds them from the seed)
var box_kind: Array[int] = []
var sign_node: Node3D
var sign_wob := 0.0
var sign_day: Label3D
var setup_msec := 0
var box_bounce: Array[float] = []

# --- The snow day (every machine builds the garden from net state "day": {seed, chapter, ...}) ---
var garden := {}
var garden_key := ""
var garden_root: Node3D
var star_icons := {}  # slot -> [3 star icons]
var goal_labels := {}
var wish_boxes := {}  # slot -> [panel, picture holder]
var wish_shown := -2
var visitor: Node3D
var visitor_bubble: Node3D
var visitor_hat: MeshInstance3D
var visitor_cheer := 0.0
var village_nodes: Array = []
var village_shown: Array = []
var story_queue: Array = []  # host: [seconds left, beat]
var vr_story: Node3D
var tele := {}  # host: this day's telemetry
var clock := 0.0
var wishes_granted := 0
var snowmen_made := 0

# --- World objects (host simulates; the TV machine mirrors) ---
var balls := {}  # id -> {n: Node3D, m: MeshInstance3D, r, s, v, off, by, tgt}
var stack_data := {}  # host: id -> {pos, radii, carrot, hat, done}
var stack_nodes := {}  # every machine: id -> Snowman
var items := {}  # id -> {n: Node3D, k, s, v, off, tgt}
var carry := {}  # slot -> CARROT / HAT (host decides; mirrored)
var carry_nodes := {}  # slot -> Node3D
var helpers: Array = []  # [{n, ball, goal, t, tgt}]
var next_id := 0
var spawn_t := 0.0
var send_t := 0.0
var time_left := 0.0
var results_t := 0.0
var held_ball := -1
var held_item := -1
var touch_cd := {}  # key -> seconds left (wobble / puff / crunch cooldowns)
var total_made := 0
var total_rolled := 0.0  # over all rounds (bots)
var total_stacked := 0


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
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.add_recipe("crunch", {"len": 0.12, "peak": 0.5, "layers": [{"w": "noise", "len": 0.12, "dec": 30.0, "lp": 2400.0, "hp": 300.0, "hold": 5000.0}]})
	sfx.add_recipe("puff", {"len": 0.25, "peak": 0.45, "layers": [{"w": "noise", "len": 0.25, "dec": 14.0, "lp": 1500.0, "lp1": 400.0}]})
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("cosy")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("rolled", "SNOW ROLLER", "%s m of snow rolled", "rolled")
	awards.define("stacked", "MASTER BUILDER", "%s snowballs stacked", "stacked")
	awards.define("dressed", "FASHION STAR", "%s carrots and hats", "dressed")
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


func _exit_tree() -> void:
	XRServer.world_scale = 1.0
	if not tele.is_empty() and net != null and net.mode != "client":  # left mid-day: still one line
		_telemetry("quit")


func _setup(mode: String) -> void:
	flat_host = mode == "host" and not net.has_vr
	if VrRig.wanted(mode) and not flat_host:
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-ARENA + 1.0, -ARENA + 1.0, ARENA * 2.0 - 2.0, ARENA * 2.0 - 2.0)
		vr_rig.glove_color = Color(0.3, 0.75, 1.0)
		add_child(vr_rig)
		vr_rig.place(VR_START, 0.0)
		hints.set_vr_rig(vr_rig, self)
	_build_world(vr_rig != null)
	if mode != "host" or flat_host:  # every machine with a screen of its own (a flat host too)
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 10.0
		add_child(group_cam)
		group_cam.follow_group([], -55.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	awards.set_player(0, "BUILDER" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		_publish_progress()
		_start_round()
	hints.intro(INTRO, {"duration": 6.0})
	if vr_rig != null:
		hints.hint("vr_grab", "Pull the trigger to lift snow!", {"to": "vr"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	setup_msec = Time.get_ticks_msec()
	print("Snowman Maker: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, String(Story.chapter(int(_day().get("chapter", 0))).sky), vr)
	sky.set_snow(true)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA + 16.0
	disc.bottom_radius = ARENA + 16.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.93, 0.96, 1.0))
	ground.position.y = -0.1
	add_child(ground)
	# Glowing build circle.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = YARD_R - 0.08
	tm.outer_radius = YARD_R + 0.08
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.material_override = MeshKit.material(Color(0.35, 0.8, 1.0), 1.5)
	ring.position = YARD + Vector3.UP * 0.01
	add_child(ring)
	# Pines and bushes round the garden, out of reach: one draw call per kind.
	add_child(MeshKit.scatter_random(MeshKit.prop("pine"), 26, Vector3.ZERO, ARENA + 12.0, ARENA + 2.5, 0.9, 1.5, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 14, Vector3.ZERO, ARENA + 2.4, ARENA + 1.2, 0.8, 1.2,
		PackedColorArray([Color(0.95, 0.97, 1.0)]), 4))
	# The score sign (world-locked, big, far from the eyes, turned to face the VR start).
	var post := MeshKit.Builder.new()
	post.cylinder(0.06, 0.06, 2.0, MeshKit.at(Vector3(0.0, 1.0, 0.0)), Color(0.45, 0.3, 0.15))
	post.rounded_box(Vector3(1.9, 1.0, 0.08), 0.06, MeshKit.at(Vector3(0.0, 2.2, 0.0)), Color(0.55, 0.36, 0.2))
	post.box(Vector3(2.0, 0.1, 0.16), MeshKit.at(Vector3(0.0, 2.72, 0.0)), Color(0.97, 0.98, 1.0))
	sign_node = Node3D.new()
	sign_node.position = SIGN_POS
	var d := SIGN_POS - (VR_START + Vector3.UP * 1.5)
	sign_node.basis = Basis(Vector3.UP, atan2(-d.x, -d.z))
	add_child(sign_node)
	sign_node.add_child(MeshKit.instance(post.build(), false))
	sign_label = UiKit.label3d("0", 0.42, "gold", true)
	sign_label.outline_size = 26
	sign_label.position = Vector3(0.0, 2.32, 0.06)
	sign_node.add_child(sign_label)
	sign_time = UiKit.label3d("3:00", 0.16, "text", true)
	sign_time.outline_size = 26
	sign_time.position = Vector3(0.0, 1.88, 0.06)
	sign_node.add_child(sign_time)
	sign_day = UiKit.label3d("", 0.12, "accent", true)
	sign_day.outline_size = 22
	sign_day.position = Vector3(0.0, 2.95, 0.06)
	sign_node.add_child(sign_day)
	_build_village(net.state_get("village", [0, 0, 0, 0, 0]))


## Every machine: build this snow day's garden from {seed, chapter} (boxes, pines, ice, drifts).
func _apply_garden(seed_v: int, chap: int) -> void:
	var key := "%d:%d" % [seed_v, chap]
	if key == garden_key:
		return
	garden_key = key
	garden = GardenGen.garden(seed_v, chap)
	if garden_root != null:
		garden_root.queue_free()
	garden_root = Node3D.new()
	garden_root.name = "Garden"
	add_child(garden_root)
	boxes.clear()
	box_pos.clear()
	box_kind.clear()
	box_bounce.clear()
	for bx in garden.boxes:
		var k := int(bx.kind)
		var box := Node3D.new()
		box.position = bx.pos
		var to := VR_START - (bx.pos as Vector3)
		box.rotation.y = atan2(to.x, to.z)
		garden_root.add_child(box)
		var b := MeshKit.Builder.new()
		var col: Color = BOX_COLORS[clampi(k, 0, BOX_COLORS.size() - 1)]
		b.rounded_box(Vector3(0.6, BOX_TOP, 0.5), 0.05, MeshKit.at(Vector3(0.0, BOX_TOP * 0.5, 0.0)), col)
		b.box(Vector3(0.62, 0.06, 0.52), MeshKit.at(Vector3(0.0, BOX_TOP - 0.06, 0.0)), col.lightened(0.3))
		box.add_child(MeshKit.instance(b.build(), false))
		for j in 3:  # what is inside, poking out
			var mi := MeshInstance3D.new()
			if k == CARROT:
				mi.mesh = Snowman.carrot_mesh()
				mi.position = Vector3(-0.16 + j * 0.16, BOX_TOP + 0.02, 0.0)
				mi.rotation = Vector3(-1.2 + j * 0.2, 0.3 * j, 0.0)
			else:
				mi.mesh = Snowman.hat_of(k)
				mi.position = Vector3(-0.15 + j * 0.15, BOX_TOP - 0.02 + j * 0.03, 0.0)
				mi.rotation.z = -0.3 + j * 0.3
				mi.scale = Vector3.ONE * 0.8
			box.add_child(mi)
		boxes.append(box)
		box_pos.append(bx.pos)
		box_kind.append(k)
		box_bounce.append(0.0)
	var pines: Array = []
	for t in garden.trees:
		pines.append(Transform3D(Basis(Vector3.UP, (t as Vector3).x * 1.7).scaled(Vector3.ONE * 1.1), t))
	if not pines.is_empty():
		garden_root.add_child(MeshKit.scatter(Village.snowy_pine(), pines))
	for kind in ["ice", "drifts"]:
		var xs: Array = []
		for q in garden.get(kind, []):
			var rad := float(q[1])
			xs.append(Transform3D(Basis.from_scale(Vector3(rad, 1.0, rad)), (q[0] as Vector3) + Vector3.UP * 0.005))
		if not xs.is_empty():
			var mm := MeshKit.scatter(Village.ice_patch() if kind == "ice" else Village.drift(), xs)
			mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			garden_root.add_child(mm)
	if visitor != null:
		visitor.position = garden.visitor
	wish_shown = -2  # rebuild the visitor for this garden


## The box position holding `kind` (or the first box).
func box_for(kind: int) -> Vector3:
	var i := box_kind.find(kind)
	return box_pos[i] if i >= 0 else (box_pos[0] if not box_pos.is_empty() else Vector3(-1.0, 0.0, 1.5))


## The village round the garden, built up to its stages (net state "village"); a new piece pops in.
func _build_village(stages: Array) -> void:
	for c in Village.PLACES.size():
		var stage := int(stages[c]) if c < stages.size() else 0
		var shown := int(village_shown[c]) if c < village_shown.size() else -1
		if stage == shown:
			continue
		if c < village_nodes.size() and is_instance_valid(village_nodes[c]):
			(village_nodes[c] as Node3D).queue_free()
		var mi := MeshKit.instance(Village.place(c, stage), true)
		mi.name = "Place%d" % c
		mi.position = Village.PLACES[c][0]
		mi.rotation.y = float(Village.PLACES[c][1])
		add_child(mi)
		while village_nodes.size() <= c:
			village_nodes.append(null)
			village_shown.append(-1)
		village_nodes[c] = mi
		if shown >= 0 and stage > shown:  # built just now: pop + confetti
			mi.scale = Vector3.ONE * 0.3
			var tw := mi.create_tween()
			tw.tween_property(mi, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_burst(mi.position + Vector3.UP * 2.5, 50, [Color(1.0, 0.3, 0.4), Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 1.0)], 5.0)
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
	row.add_child(StoryCard.picture("snowman", 44.0))
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
	# The visitor's wish: a picture of the hat they want (no words: little ones read pictures).
	var wish := UiKit.panel("card")
	ui.add_child(wish)
	UiKit.pin(wish, Control.PRESET_TOP_RIGHT)
	wish.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wish.offset_left = -24.0
	wish.offset_right = -24.0
	wish.offset_top = 96.0
	var wrow := UiKit.hbox(8)
	wish.add_child(wrow)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(84, 84)
	wrow.add_child(StoryCard.picture("heart", 44.0, Color(1.0, 0.45, 0.6)))
	wrow.add_child(holder)
	wish.visible = false
	wish_boxes[slot] = [wish, holder]
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time)), "warn": 15})
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


func _day() -> Dictionary:
	var d: Variant = net.state_get("day", {})
	return d if d is Dictionary else {}


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	var goals: Array = _day().get("goals", [])
	var got := Story.stars_for(score, goals) if not goals.is_empty() else 0
	var goal_text := ""
	if not goals.is_empty():
		goal_text = "/ %d" % int(goals[got]) if got < goals.size() else "WOW!"
	for slot in score_labels:
		var l: Label = score_labels[slot]
		if is_instance_valid(l):
			l.text = str(score)
		var g: Label = goal_labels.get(slot)
		if g != null and is_instance_valid(g):
			g.text = goal_text
		var st: Array = star_icons.get(slot, [])
		for i in st.size():
			var ic: Control = st[i]
			if is_instance_valid(ic):
				ic.visible = not goals.is_empty()
				ic.modulate = Color.WHITE if i < got else Color(1.0, 1.0, 1.0, 0.22)
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if sign_label != null:
		sign_label.text = str(score)
	if sign_day != null:
		sign_day.text = _day_title(_day())
	_refresh_wish_hud()


func _day_title(d: Dictionary) -> String:
	match String(d.get("mode", "")):
		"daily":
			return "DAILY GARDEN"
		"bonus":
			return "SNOW DAY"
		"story":
			return "%s  %d/%d" % [Story.chapter(int(d.get("chapter", 0))).name, int(d.get("day", 0)) + 1, Story.DAYS_PER_CHAPTER]
	return ""


## The wish picture on every view (hidden while nobody is wishing).
func _refresh_wish_hud() -> void:
	var w: Dictionary = net.state_get("wish", {}) if net.state_get("wish", {}) is Dictionary else {}
	var hat := int(w.get("hat", 0))
	for slot in wish_boxes:
		var pair: Array = wish_boxes[slot]
		if not is_instance_valid(pair[0]):
			continue
		var panel: Control = pair[0]
		var holder: Control = pair[1]
		panel.visible = hat > 0 and not results_showing()
		if int(holder.get_meta("hat", -1)) != hat and hat > 0:
			holder.set_meta("hat", hat)
			for c in holder.get_children():
				c.queue_free()
			var pic := StoryCard.picture(HAT_PICS[hat], holder.custom_minimum_size.x, HAT_COLORS[hat])
			holder.add_child(pic)
			UiKit.pop_in(panel)


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
		c.pitch = -0.5
		add_child(c)
		c.follow(a, 6.5, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("roll", "Push snowballs to the circle!", {"to": slot})
	awards.set_player(slot, party.name_of(slot))
	_refresh_group()
	_refresh_hud()
	sfx.play("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	for d in [avatars, cams, carry_nodes]:
		var dict: Dictionary = d
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	last_pos.erase(slot)
	net_target.erase(slot)
	carry.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	goal_labels.erase(slot)
	star_icons.erase(slot)
	wish_boxes.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_group()
	_refresh_hud()


func _ensure_avatar(slot: int) -> Node3D:
	if avatars.has(slot) and is_instance_valid(avatars[slot]):
		return avatars[slot]
	var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": slot,
		"hat": "beanie"})
	a.name = "Avatar%d" % slot
	add_child(a)
	a.position = GardenGen.player_start(slot)
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.35, 0.18)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


func _refresh_group() -> void:
	if group_cam != null:
		var t: Array = avatars.values()
		if t.is_empty():
			t = [stack_anchor()]
		group_cam.set_targets(t)


## Something for the empty shared view to look at.
func stack_anchor() -> Node3D:
	return boxes[0] if not boxes.is_empty() else self


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
			a.position = _out_of_trees(p.limit_length(ARENA - 0.3), BODY_R)
			Creatures.anim(a).face(dir)
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)


## Push a point (a player, a helper, a snowball of radius `rad`) out of the garden's pines.
func _out_of_trees(p: Vector3, rad: float) -> Vector3:
	for t in garden.get("trees", []):
		var tp: Vector3 = t
		var d := Vector2(p.x - tp.x, p.z - tp.z)
		var need := TREE_R + rad
		if d.length() < need:
			if d.length() < 0.001:
				d = Vector2(1.0, 0.0)
			var push := d.normalized() * need
			p.x = tp.x + push.x
			p.z = tp.z + push.y
	return p


func _animate_avatars(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.3 else 0.0)
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


## TV machine: the VR player as seen from here (only when the host has one), plus the little window into their view.
func _make_vr_avatar() -> void:
	vr_avatar = VrRig.Avatar.new()
	add_child(vr_avatar)
	if split != null:
		split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))


func on_request(_slot: int, action: String, _args: Array) -> void:
	if action == "next_round" and results_showing():
		_start_round()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "%s paused" % party.name_of(by_slot)
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_paused(self, vr_rig.camera, "", {"width": 1.0})
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
		"score":
			_refresh_hud()
		"time":
			for slot in timers:
				if not is_instance_valid(timers[slot]):
					continue
				var t: HudKit.TimerPill = timers[slot]
				t.set_time(float(value))
			if sign_time != null:
				var s := maxi(0, int(value))
				sign_time.text = "%d:%02d" % [s / 60, s % 60]
		"stacks":
			_sync_stacks(value)
		"day":
			var d: Dictionary = value if value is Dictionary else {}
			_apply_garden(int(d.get("seed", 0)), int(d.get("chapter", 0)))
			_refresh_hud()
			if sky != null:
				sky.set_preset(String(Story.chapter(int(d.get("chapter", 0))).sky))
				sky.set_snow(true)
		"wish":
			_refresh_wish_hud()
			_sync_stacks(net.state_get("stacks", {}))
		"village":
			_build_village(value)
		"unlocks":
			_sync_stacks(net.state_get("stacks", {}))
		"made":
			if Time.get_ticks_msec() - setup_msec > 2000:  # not for a TV machine that just (re)joined
				_celebrate()
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------

func _start_round() -> void:
	for id in balls.keys():
		_free_ball(int(id))
	for id in items.keys():
		_free_item(int(id))
	held_ball = -1
	held_item = -1
	stack_data.clear()
	carry.clear()
	awards.reset()
	time_left = round_time
	spawn_t = 0.0
	wishes_granted = 0
	snowmen_made = 0
	# Which day: the daily garden (first game of the date), the story, or bonus days.
	var nx := Story.next_round(save.data, Seeded.daily_key())
	var mode := String(nx[0])
	var chap := int(nx[1])
	var day_n := int(nx[2])
	if force_chapter >= 0:
		mode = "test"
		chap = force_chapter
	var seed_v := Seeded.daily_seed(GAME_ID) if mode == "daily" else Seeded.fresh_seed()
	var builders := _builders()
	var misses := int(save.data["misses"]) if mode == "story" or mode == "bonus" else 0
	var laps := int(save.data["laps"]) if mode == "bonus" else 0
	var goals := Story.goals(builders, chap, misses, laps, round_time)
	_apply_garden(seed_v, chap)
	net.state_set("stacks", {})
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("day", {"mode": mode, "chapter": chap, "day": day_n, "seed": seed_v, "goals": goals, "builders": builders})
	net.state_set("wish", {"i": 0, "hat": int(garden.wishes[0][0]), "v": int(garden.wishes[0][1])})
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	tele = {"mode": mode, "chapter": chap, "day": day_n, "seed": seed_v, "goals": goals, "builders": builders,
		"tv_players": party.player_count(), "vr": vr_rig != null, "flat_host": flat_host, "misses_before": misses,
		"seconds": round_time, "t0": clock, "helpers": 0}
	if vr_rig != null:
		vr_rig.guard_trigger()
	for k in 4:
		_spawn_ball()
	# What Tumble (or the chapter's friend) says.
	var ch := Story.chapter(chap)
	var first := 6.5 if int(net.state_get("round", 0)) <= 1 else 0.8  # after the how-to-play card
	if mode == "daily":
		_story(_tumble_beat("Today's garden! The same for everyone.", 4.0), first)
	elif mode == "story" and day_n == 0 and misses == 0:
		_story(_chapter_beat(chap, "intro"), first)
		if String(ch.new) != "":
			_story(_tumble_beat(String(ch.new), 4.0), first + 4.8)
	elif misses > 0:
		_story(_tumble_beat(Story.TUMBLE_RETRY[misses % Story.TUMBLE_RETRY.size()]), first)
	else:
		_story(_tumble_beat(Story.TUMBLE_LINES[int(save.data["days"]) % Story.TUMBLE_LINES.size()]), first)


## Host: more builders joined during the day: the star goals grow with them (never shrink mid-day).
func _rescale_goals() -> void:
	var d := _day()
	if d.is_empty() or results_showing() or _builders() <= int(d.get("builders", 1)):
		return
	var nd := d.duplicate()
	var misses := int(tele.get("misses_before", 0))
	var laps := int(save.data["laps"]) if String(d.get("mode", "")) == "bonus" else 0
	nd["builders"] = _builders()
	nd["goals"] = Story.goals(_builders(), int(d.get("chapter", 0)), misses, laps, round_time)
	net.state_set("day", nd)
	if not tele.is_empty():
		tele["builders"] = _builders()
		tele["goals"] = nd["goals"]
		tele["tv_players"] = maxi(int(tele.get("tv_players", 0)), party.player_count())


## Everyone building this day: TV players + the VR builder (at least one).
func _builders() -> int:
	return maxi(1, party.player_count() + (1 if vr_rig != null else 0))


func _end_round(how: String = "time") -> void:
	if held_ball >= 0 and balls.has(held_ball):
		(balls[held_ball] as Dictionary)["s"] = FLYING
	held_ball = -1
	var score := int(net.state_get("score", 0))
	var d := _day()
	var goals: Array = d.get("goals", [1, 2, 3])
	var stars := Story.stars_for(score, goals)
	var mode := String(d.get("mode", "story"))
	var chap := int(d.get("chapter", 0))
	var day_n := int(d.get("day", 0))
	var stars_d: Dictionary = save.data["stars"]
	var before := Story.flakes(stars_d, int(save.data["extra_flakes"]))
	var adv := {}
	if mode == "story":
		var key := "%d-%d" % [chap, day_n]
		stars_d[key] = maxi(int(stars_d.get(key, 0)), stars)
		adv = Story.advance(chap, day_n, int(save.data["laps"]), int(save.data["misses"]), stars)
	elif mode == "bonus":
		save.data["extra_flakes"] = int(save.data["extra_flakes"]) + stars
		adv = Story.advance(Story.MIXED, day_n, int(save.data["laps"]), int(save.data["misses"]), stars)
	elif mode == "daily":
		var daily: Dictionary = save.data["daily"]
		var dk := Seeded.daily_key()
		daily[dk] = maxi(int(daily.get(dk, 0)), score)
		save.data["extra_flakes"] = int(save.data["extra_flakes"]) + stars
		for k in daily.keys():  # keep the last two weeks only
			if daily.size() > 14 and String(k) < dk:
				daily.erase(k)
	if not adv.is_empty():
		save.data["chapter"] = int(adv.chapter)
		save.data["day"] = int(adv.day)
		save.data["laps"] = int(adv.laps)
		save.data["misses"] = int(adv.misses)
	if mode != "test":
		save.data["days"] = int(save.data["days"]) + 1
		save.data["made"] = int(save.data["made"]) + snowmen_made
		save.data["wishes"] = int(save.data["wishes"]) + wishes_granted
		if score > int(save.data["best"]):
			save.data["best"] = score
		save.mark_dirty()
	var after := Story.flakes(stars_d, int(save.data["extra_flakes"]))
	var news := Story.newly_unlocked(before, after)
	_publish_progress()
	net.state_set("best", int(save.data["best"]))
	tele["chapter_done"] = bool(adv.get("chapter_done", false))
	_telemetry(how)
	# The results screen.
	var titles := ["NEARLY!", "LOVELY SNOWMEN!", "SUPER BUILDERS!", "SNOW AMAZING!"]
	var stats: Array = [["SNOWMEN", str(snowmen_made)], ["WISHES", str(wishes_granted)], ["STARS", "%d OF 3" % stars]]
	if stars < 3:
		stats.append(["NEXT STAR", str(int(goals[stars]))])
	if mode == "daily":
		stats.append(["BEST TODAY", str(int(net.state_get("daily_best", score)))])
	else:
		stats.append(["BEST", str(int(save.data["best"]))])
	stats.append(["SNOWFLAKES", str(after)])
	for n in news:
		stats.append(["NEW!", n])
	var sub := "%d points together!" % score
	if mode == "story" and stars > 0:
		sub = "A new piece of the %s!" % String(Story.chapter(chap).place).to_lower()
	var data := awards.results({"title": titles[stars], "subtitle": sub, "style": "victory", "stats": stats,
		"score_format": "%d"})
	data["stars"] = stars
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	# Story beats.
	if bool(adv.get("story_done", false)):
		_story(_chapter_beat(4, "done", 5.0), 1.5)
		_story(_tumble_beat("Every friend came to the fair! Thank you!", 5.0), 7.0)
	elif bool(adv.get("chapter_done", false)):
		_story(_chapter_beat(chap, "done", 5.0), 1.5)
	elif stars == 0 and mode != "daily":
		_story(_tumble_beat(Story.TUMBLE_RETRY[int(save.data["misses"]) % Story.TUMBLE_RETRY.size()]), 1.5)
	for i in news.size():
		_story({"who": "NEW!", "line": "You unlocked %s!" % String(news[i]).to_lower(), "pic": "star", "color": "ffd24d", "duration": 3.5}, 6.5 + i * 4.0)


## Host: one telemetry line for this day (also when the game is left mid-day).
func _telemetry(how: String) -> void:
	if tele.is_empty():
		return
	var t := tele.duplicate(true)
	var goals: Array = t.get("goals", [1, 2, 3])
	t["score"] = int(net.state_get("score", 0))
	t["stars"] = Story.stars_for(int(t["score"]), goals)
	t["snowmen"] = snowmen_made
	t["wishes"] = wishes_granted
	t["stacked"] = total_stacked
	t["rolled_m"] = int(total_rolled)
	t["end"] = how
	t["played_s"] = int(clock - float(t.get("t0", clock)))
	t.erase("t0")
	tele = {}
	Telemetry.run(GAME_ID, t)


## Host: share the saved progress (village pieces, unlocks, today's best) with every machine.
func _publish_progress() -> void:
	var stars_d: Dictionary = save.data["stars"]
	net.state_set("village", Story.village(stars_d))
	var flakes := Story.flakes(stars_d, int(save.data["extra_flakes"]))
	net.state_set("flakes", flakes)
	net.state_set("unlocks", Story.unlocked(flakes))
	var daily: Dictionary = save.data["daily"]
	net.state_set("daily_best", int(daily.get(Seeded.daily_key(), 0)))


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


## Every machine: the card on each TV view and in VR.
func show_story(beat: Dictionary) -> void:
	var opts := beat.duplicate()
	opts["color"] = Color.html(String(beat.get("color", "8ec5ff")))
	if split != null:
		StoryCard.show(_all_huds(), opts)
	if vr_rig != null:
		if vr_story != null and is_instance_valid(vr_story):
			vr_story.call("hide_card")
		opts["vr_height"] = 0.18  # above the hints (they sit low)
		vr_story = StoryCard.show_vr(self, vr_rig.camera, opts)


func _tumble_beat(line: String, duration: float = 3.5) -> Dictionary:
	return {"who": "TUMBLE", "line": line, "pic": "penguin", "color": "8ec5ff", "duration": duration}


func _chapter_beat(chap: int, line_key: String, duration: float = 4.5) -> Dictionary:
	var ch := Story.chapter(chap)
	var colors := ["8ec5ff", "7fd36a", "9fd8ff", "f2a7c3", "c9a0ff", "8ec5ff"]
	return {"who": String(ch.who), "line": String(ch[line_key]), "pic": String(ch.pic), "color": colors[clampi(chap, 0, 5)], "duration": duration}


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	sfx.play("cheer", -2.0)
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


# --- Game loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if split != null:
		_move_local_players(delta)
	_follow_remote(delta)
	_animate_avatars(delta)
	clock += delta
	_animate_visitor(delta)
	for k in boxes.size():
		box_bounce[k] = maxf(0.0, box_bounce[k] - delta * 3.0)
		var s := sin(box_bounce[k] * PI * 3.0) * box_bounce[k] * 0.2
		boxes[k].scale = Vector3(1.0 + s, 1.0 - s, 1.0 + s)
	_update_carry_visuals(delta)
	sign_wob = maxf(0.0, sign_wob - delta * 1.2)
	if sign_node != null:
		sign_node.rotation.z = sin(sign_wob * 18.0) * sign_wob * 0.12
	for key in touch_cd.keys():
		touch_cd[key] = float(touch_cd[key]) - delta
		if float(touch_cd[key]) <= 0.0:
			touch_cd.erase(key)
	if net.mode == "client":
		_mirror_motion(delta)
		return
	_run_story_queue(delta)
	_rescale_goals()
	if results_showing():
		results_t += delta
		if results_t > 12.0:
			_start_round()  # play again by itself
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if time_left <= 0.0:
		_end_round()
		return
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = 1.0
		if _free_count() < MAX_FREE:
			_spawn_ball()
	_update_helpers(delta)
	if vr_rig != null:
		_vr_hands()
	_simulate_balls(delta)
	_simulate_items(delta)
	_tv_carry()


func _free_count() -> int:
	return balls.size()


# --- Snowballs ------------------------------------------------------------------------------

func _spawn_ball() -> void:
	var spots: Array = garden.get("spawns", [])
	for attempt in 12:
		var p: Vector3 = spots[randi() % spots.size()] if not spots.is_empty() else Vector3(cos(attempt), 0.0, sin(attempt)) * 5.0
		if _space_free(p, 1.2):
			next_id += 1
			var b := _make_ball(next_id, p, BALL_MIN)
			b["pop"] = 0.0
			fx("pop", [p], "pop", -12.0)
			return


func _space_free(p: Vector3, gap: float) -> bool:
	for id in balls:
		var n: Node3D = (balls[id] as Dictionary)["n"]
		if _flat(n.position - p) < gap:
			return false
	for id in stack_data:
		var sp: Vector3 = (stack_data[id] as Dictionary)["pos"]
		if _flat(sp - p) < gap + 0.3:
			return false
	for slot in avatars:
		if _flat((avatars[slot] as Node3D).position - p) < gap:
			return false
	return _flat(p - VR_START) > 1.5


func _make_ball(id: int, p: Vector3, r: float) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var m := MeshInstance3D.new()
	m.mesh = Snowman.ball_mesh()
	m.material_override = Snowman.snow_material()
	n.add_child(m)
	n.position = Vector3(p.x, r if p.y < r else p.y, p.z)
	n.scale = Vector3.ONE * r
	var b := {"n": n, "m": m, "r": r, "s": GROUND, "v": Vector3.ZERO, "off": Vector3.ZERO, "by": -1,
		"tgt": n.position, "pop": 1.0, "sq": 0.0}
	balls[id] = b
	return b


func _free_ball(id: int) -> void:
	if balls.has(id):
		((balls[id] as Dictionary)["n"] as Node).queue_free()
		balls.erase(id)
	if held_ball == id:
		held_ball = -1


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## Everything that pushes snowballs along the ground: [position, slot, radius, is_hand].
func _pushers() -> Array:
	var out: Array = []
	if String(net.state_get("phase", "play")) != "play":
		return out
	for slot in avatars:
		out.append([(avatars[slot] as Node3D).position, int(slot), BODY_R, false])
	for h in helpers:
		out.append([((h as Dictionary)["n"] as Node3D).position, -1, BODY_R, false])
	if vr_rig != null:
		out.append([vr_rig.hand_point(VrRig.LEFT), 0, 0.07, true])  # the right glove grabs instead
	return out


func _simulate_balls(delta: float) -> void:
	var pushers := _pushers()
	for id in balls.keys():
		if not balls.has(id):
			continue
		var b: Dictionary = balls[id]
		var n: Node3D = b["n"]
		var r: float = b["r"]
		b["pop"] = minf(1.0, float(b["pop"]) + delta * 3.0)
		b["sq"] = maxf(0.0, float(b["sq"]) - delta * 3.0)
		match int(b["s"]):
			GROUND:
				var p := n.position
				var start := p
				for q in pushers:
					var qp: Vector3 = q[0]
					var rad: float = q[2]
					if bool(q[3]) and (qp.y > p.y + r or qp.distance_to(p) > r + rad):
						continue
					var d := Vector2(p.x - qp.x, p.z - qp.z)
					var need := r + rad
					if d.length() < need:
						if d.length() < 0.001:
							d = Vector2(0.0, 1.0)
						var push := d.normalized() * (need - d.length())
						p.x += push.x
						p.z += push.y
						b["by"] = int(q[1])
				var under := GardenGen.ground_at(garden, p)
				var slide: Vector3 = b.get("slide", Vector3.ZERO)
				if under == "ice":  # icy: keeps sliding the way it was pushed
					var pushed := (p - start) / maxf(delta, 0.001)
					pushed.y = 0.0
					if pushed.length() > 0.2:
						slide = pushed.limit_length(5.0)
					else:
						p += slide * delta
					slide *= exp(-0.9 * delta)
					if slide.length() < 0.05:
						slide = Vector3.ZERO
				else:
					slide = Vector3.ZERO
				var before_tree := p
				p = _out_of_trees(p, r)
				if not before_tree.is_equal_approx(p):
					slide = slide.bounce(Vector3(p.x - before_tree.x, 0.0, p.z - before_tree.z).normalized()) * 0.6 if slide.length() > 0.01 else slide
				var fl := Vector2(p.x, p.z)
				if fl.length() > ARENA - r:
					fl = fl.normalized() * (ARENA - r)
					p.x = fl.x
					p.z = fl.y
					slide = Vector3.ZERO
				b["slide"] = slide
				var dist := _flat(p - start)
				if dist > 0.0005:
					var grow := 0.0 if under == "ice" else (GROW * 3.0 if under == "drifts" else GROW)
					r = minf(BALL_MAX, r + dist * grow)
					b["r"] = r
					p.y = r
					n.position = p
					_roll(b, start, p)
					var by := int(b["by"])
					total_rolled += dist
					if by >= 0:
						awards.add(by, "rolled", dist)
					if not touch_cd.has("crunch%d" % id):
						touch_cd["crunch%d" % id] = 0.22
						sfx.play_at("crunch", p, -8.0, 1.5 - r * 1.6)
					if _bump_ball(int(id)):
						continue
			HELD:
				var h := vr_rig.hand(VrRig.RIGHT)
				n.position = h.global_transform * (b["off"] as Vector3)
			FLYING:
				var v: Vector3 = b["v"]
				v.y -= 9.8 * delta
				b["v"] = v
				n.position += v * delta
				if v.y < 0.0 and _try_snap(int(id), false):
					continue
				if n.position.y <= r:
					n.position.y = r
					b["s"] = GROUND
					b["sq"] = clampf(-v.y * 0.25, 0.3, 1.0)
					b["v"] = Vector3.ZERO
					fx("puff", [n.position - Vector3.UP * r * 0.8], "puff", -6.0)
		if balls.has(id):
			var sq := sin(float(b["sq"]) * PI * 3.0) * float(b["sq"]) * 0.3
			n.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq) * r * _ease_pop(float(b["pop"]))


static func _ease_pop(t: float) -> float:
	if t >= 1.0:
		return 1.0
	return maxf(0.01, t + sin(t * PI) * 0.45)


func _roll(b: Dictionary, from: Vector3, to: Vector3) -> void:
	var d := to - from
	d.y = 0.0
	var l := d.length()
	if l < 0.0001:
		return
	var m: MeshInstance3D = b["m"]
	var axis := Vector3(d.z, 0.0, -d.x) / l
	m.basis = (Basis(axis, l / maxf(0.05, float(b["r"]))) * m.basis).orthonormalized()


## A rolling ball ran into another ball or a half-built snowman: they stack (biggest at the
## bottom). Finished snowmen just bump it away.
## True when the ball was used up.
func _bump_ball(id: int) -> bool:
	var b: Dictionary = balls[id]
	var n: Node3D = b["n"]
	var r: float = b["r"]
	for sid in stack_data.keys():
		var st: Dictionary = stack_data[sid]
		var radii: Array[float] = st["radii"]
		var sp: Vector3 = st["pos"]
		var d := Vector2(n.position.x - sp.x, n.position.z - sp.z)
		if d.length() < r + radii[0]:
			if not bool(st["done"]) and radii.size() < 3:
				_add_to_stack(int(sid), id, int(b["by"]))
				return true
			_push_out(n, d, r + radii[0])
	for oid in balls.keys():
		if int(oid) == id:
			continue
		var o: Dictionary = balls[oid]
		if int(o["s"]) != GROUND:
			continue
		var on: Node3D = o["n"]
		var orr: float = o["r"]
		var d := Vector2(n.position.x - on.position.x, n.position.z - on.position.z)
		if d.length() < r + orr:
			var sid := _ball_to_stack(int(oid))
			_add_to_stack(sid, id, int(b["by"]))
			return true
	return false


func _push_out(n: Node3D, d: Vector2, need: float) -> void:
	if d.length() < 0.001:
		d = Vector2(1.0, 0.0)
	var push := d.normalized() * (need - d.length())
	n.position.x += push.x
	n.position.z += push.y


## A loose ground ball becomes the base of a new snowman.
func _ball_to_stack(id: int) -> int:
	var b: Dictionary = balls[id]
	var p: Vector3 = (b["n"] as Node3D).position
	var r: float = b["r"]
	_free_ball(id)
	next_id += 1
	var radii: Array[float] = [r]
	stack_data[next_id] = {"pos": Vector3(p.x, 0.0, p.z), "radii": radii, "carrot": false, "hat": 0, "done": false}
	return next_id


func _add_to_stack(sid: int, ball_id: int, by: int) -> void:
	var st: Dictionary = stack_data[sid]
	var b: Dictionary = balls[ball_id]
	var radii: Array[float] = st["radii"]
	radii.append(float(b["r"]))
	radii.sort()
	radii.reverse()  # the biggest always ends up at the bottom: it always looks like a snowman
	_free_ball(ball_id)
	total_stacked += 1
	if by >= 0:
		awards.add(by, "stacked")
	var top := Snowman.top_y(radii)
	fx("puff", [(st["pos"] as Vector3) + Vector3.UP * top], "boing", -2.0, 0.8 + radii.size() * 0.15)
	if vr_rig != null:
		vr_rig.pulse(VrRig.RIGHT, 0.6, 0.1)
	if radii.size() == 3:
		hints.hint("dress", "Now a carrot and a hat!", {"to": "all"})
	_publish_stacks()


## Release / flight: drop the ball on a snowman or a loose ball below it. lenient = just let go.
func _try_snap(id: int, lenient: bool) -> bool:
	var b: Dictionary = balls[id]
	var n: Node3D = b["n"]
	var r: float = b["r"]
	var reach := 0.5 if lenient else 0.32
	for sid in stack_data.keys():
		var st: Dictionary = stack_data[sid]
		var radii: Array[float] = st["radii"]
		if bool(st["done"]) or radii.size() >= 3:
			continue
		var sp: Vector3 = st["pos"]
		var top := Snowman.top_y(radii)
		var close := _flat(n.position - sp) < maxf(reach, radii[radii.size() - 1] * 0.9)
		var above := n.position.y > top - r * 0.6 and (lenient or n.position.y - r <= top + 0.05)
		if close and above:
			_add_to_stack(int(sid), id, int(b["by"]) if not lenient else 0)
			return true
	for oid in balls.keys():
		if int(oid) == id:
			continue
		var o: Dictionary = balls[oid]
		if int(o["s"]) != GROUND:
			continue
		var on: Node3D = o["n"]
		var orr: float = o["r"]
		var top := orr * 2.0
		var close := _flat(n.position - on.position) < maxf(reach, orr * 0.9)
		var above := n.position.y > top - r * 0.6 and (lenient or n.position.y - r <= top + 0.05)
		if close and above:
			var sid := _ball_to_stack(int(oid))
			_add_to_stack(sid, id, 0)
			return true
	return false


# --- Snowmen (the store holds them, so late joiners get them all) ----------------------------

func _publish_stacks() -> void:
	var out := {}
	for sid in stack_data:
		var st: Dictionary = stack_data[sid]
		var p: Vector3 = st["pos"]
		var flags := (1 if bool(st["carrot"]) else 0) | (4 if bool(st["done"]) else 0) | (int(st["hat"]) << 3)
		out[sid] = [snappedf(p.x, 0.01), snappedf(p.z, 0.01), PackedFloat32Array(st["radii"] as Array), flags]
	net.state_set("stacks", out)


## Every machine: build / update / remove the snowman visuals from the store.
func _sync_stacks(value: Variant) -> void:
	var data: Dictionary = value if value is Dictionary else {}
	for sid in data:
		var e: Array = data[sid]
		var node: Snowman
		var fresh := false
		if stack_nodes.has(sid) and is_instance_valid(stack_nodes[sid]):
			node = stack_nodes[sid]
		else:
			fresh = true
			node = Snowman.new()
			add_child(node)
			stack_nodes[sid] = node
		var p := Vector3(float(e[0]), 0.0, float(e[1]))
		node.position = p
		var to := VR_START - p
		node.rotation.y = atan2(to.x, to.z)  # face the builder
		var radii: Array[float] = []
		for x in (e[2] as PackedFloat32Array):
			radii.append(x)
		var flags := int(e[3])
		var was_done := node.done
		node.set_data(radii, flags & 1 != 0, flags >> 3, flags & 4 != 0, _wish_hat(), _looks())
		if node.done and not was_done and not fresh:  # (a TV machine joining late: no cheer storm)
			_cheer_fx(node)
	for sid in stack_nodes.keys():
		if not data.has(sid):
			(stack_nodes[sid] as Node).queue_free()
			stack_nodes.erase(sid)


## The hat the current visitor wishes for (1 = top hat when nobody wishes).
func _wish_hat() -> int:
	var w: Variant = net.state_get("wish", {})
	return maxi(1, int((w as Dictionary).get("hat", 1))) if w is Dictionary else 1


## Unlocked snowman looks (story.gd UNLOCKS ids).
func _looks() -> Array:
	var u: Variant = net.state_get("unlocks", [])
	return u if u is Array else []


func _cheer_fx(node: Node3D) -> void:
	_burst(node.position + Vector3.UP * 1.2, 40, [Color(1.0, 0.3, 0.4), Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 1.0), Color(0.5, 1.0, 0.4)], 5.0)
	if _looks().has("fireworks"):
		for i in 3:
			_burst(node.position + Vector3(randf_range(-1.0, 1.0), 2.5 + i * 0.6, randf_range(-1.0, 1.0)), 30,
				[Color(1.0, 0.4, 0.8), Color(0.4, 1.0, 0.9), Color(1.0, 1.0, 0.5)], 6.0)
	sfx.play_at("party_horn", node.position, 0.0)
	sfx.play("cheer", -4.0)


## Every machine: the team made a snowman.
func _celebrate() -> void:
	_refresh_hud()
	var score := int(net.state_get("score", 0))
	if score <= 0:
		return
	HudKit.banner(_all_huds(), "SNOWMAN!", "", {"duration": 1.6, "style": "victory"})
	if vr_rig != null:
		HudKit.vr_banner(self, vr_rig.camera, "SNOWMAN!", "", {"duration": 1.6, "style": "victory", "distance": 2.4})


func _complete(sid: int) -> void:
	var st: Dictionary = stack_data[sid]
	st["done"] = true
	_publish_stacks()
	total_made += 1
	snowmen_made += 1
	var pts := 1
	var w: Dictionary = net.state_get("wish", {})
	if int(st["hat"]) == int(w.get("hat", -1)):  # the visitor's wish came true: worth double
		pts += 1
		wishes_granted += 1
		var i := int(w.get("i", 0)) + 1
		var wishes: Array = garden.get("wishes", [[1, 0]])
		var nxt: Array = wishes[i % wishes.size()]
		net.state_set("wish", {"i": i, "hat": int(nxt[0]), "v": int(nxt[1])})
		fx("wish", [], "achievement", -2.0)
	net.state_set("score", int(net.state_get("score", 0)) + pts)
	net.state_set("made", total_made)


## A carrot or hat touched a snowman's head (or a TV player brought one): put it on.
func _dress(sid: int, kind: int, by: int) -> void:
	var st: Dictionary = stack_data[sid]
	if kind == CARROT:
		st["carrot"] = true
	else:
		st["hat"] = kind
	awards.add(by, "dressed")
	var node: Snowman = stack_nodes.get(sid)
	fx("sparkle", [node.head_world() if node != null else (st["pos"] as Vector3)], "ding", 0.0, 1.2 if kind != CARROT else 1.0)
	if bool(st["carrot"]) and int(st["hat"]) > 0:
		_complete(sid)
	else:
		_publish_stacks()


## The snowman (not done, 3 balls, missing `kind`) whose head is nearest `p` within `reach`, or -1.
func _head_near(p: Vector3, kind: int, reach: float, flat: bool = false) -> int:
	var best := -1
	var bd := INF
	for sid in stack_data:
		var st: Dictionary = stack_data[sid]
		var radii: Array[float] = st["radii"]
		if bool(st["done"]) or radii.size() < 3 or (bool(st["carrot"]) if kind == CARROT else int(st["hat"]) > 0):
			continue
		var node: Snowman = stack_nodes.get(sid)
		if node == null:
			continue
		var d := _flat(p - node.position) if flat else p.distance_to(node.head_world())
		var lim := reach + (radii[0] if flat else radii[2])
		if d < lim and d < bd:
			bd = d
			best = int(sid)
	return best


# --- VR hands -----------------------------------------------------------------------------

func _vr_hands() -> void:
	var playing := String(net.state_get("phase", "play")) == "play"
	var rp := vr_rig.hand_point(VrRig.RIGHT)
	var grip_on := vr_rig.trigger_pressed() or vr_rig.a_pressed()
	var grip_held := vr_rig.trigger_down() or vr_rig.a_down()
	if playing and grip_on and held_ball < 0 and held_item < 0:
		_grab(rp)
	if not grip_held:
		if held_ball >= 0:
			_release_ball()
		if held_item >= 0:
			_release_item()
	# Touching things: snowmen wobble, boxes bounce, the snow puffs.
	for k in 2:
		var hp := vr_rig.hand_point(k)
		var hv := vr_rig.hand_velocity(k)
		for sid in stack_nodes:
			var node: Snowman = stack_nodes[sid]
			if not is_instance_valid(node) or node.radii.is_empty():
				continue
			var key := "w%d" % int(sid)
			if touch_cd.has(key):
				continue
			for i in node.radii.size():
				var c := node.position + Vector3.UP * Snowman.center_y(node.radii, i)
				if hp.distance_to(c) < node.radii[i] + 0.06:
					touch_cd[key] = 0.5
					var dir := Vector2(hv.x, hv.z)
					if dir.length() < 0.1:
						dir = Vector2(c.x - hp.x, c.z - hp.z)
					fx("wob", [int(sid), dir, clampf(0.4 + hv.length() * 0.4, 0.4, 1.0)], "boing", -10.0, 1.4)
					vr_rig.pulse(k, 0.25, 0.05)
					break
		for b in boxes.size():
			if not touch_cd.has("box%d" % b) and _flat(hp - box_pos[b]) < 0.36 and hp.y < BOX_TOP + 0.1:
				touch_cd["box%d" % b] = 0.4
				fx("box", [b], "bounce", -6.0)
				vr_rig.pulse(k, 0.2, 0.04)
		if not touch_cd.has("sign") and _flat(hp - SIGN_POS) < 0.25 + (1.0 if hp.y > 1.65 else 0.0) and hp.y < 2.8 \
				and absf((sign_node.global_transform.affine_inverse() * hp).z) < 0.2:
			touch_cd["sign"] = 0.6
			fx("sign", [], "bounce", -6.0, 0.7)
			vr_rig.pulse(k, 0.3, 0.05)
		if hp.y < 0.06 and not touch_cd.has("snow%d" % k) and vr_rig.hand_speed(k) > 0.3:
			touch_cd["snow%d" % k] = 0.3
			fx("puff", [Vector3(hp.x, 0.02, hp.z)], "crunch", -4.0)
			vr_rig.pulse(k, 0.2, 0.04)


func _grab(rp: Vector3) -> void:
	var h := vr_rig.hand(VrRig.RIGHT)
	# 1) a loose snowball
	var best := -1
	var bd := INF
	for id in balls:
		var b: Dictionary = balls[id]
		var d := rp.distance_to((b["n"] as Node3D).position) - float(b["r"])
		if d < 0.2 and d < bd:
			bd = d
			best = int(id)
	# 2) the top ball of an unfinished snowman
	var best_stack := -1
	for sid in stack_data:
		var st: Dictionary = stack_data[sid]
		if bool(st["done"]):
			continue
		var radii: Array[float] = st["radii"]
		var top_c := (st["pos"] as Vector3) + Vector3.UP * Snowman.center_y(radii, radii.size() - 1)
		var d := rp.distance_to(top_c) - radii[radii.size() - 1]
		if d < 0.2 and d < bd:
			bd = d
			best_stack = int(sid)
	if best_stack >= 0:
		best = _pop_top(best_stack)
	if best >= 0:
		var b: Dictionary = balls[best]
		b["s"] = HELD
		b["sq"] = 0.6
		var n: Node3D = b["n"]
		var off := h.global_transform.affine_inverse() * n.position
		if off.length() > float(b["r"]) + 0.05:  # keep it in the glove, not floating away
			off = off.normalized() * (float(b["r"]) + 0.05)
		b["off"] = off
		held_ball = best
		fx("", [], "pickup", -4.0, 1.3 - float(b["r"]))
		vr_rig.pulse(VrRig.RIGHT, 0.5, 0.08)
		return
	# 3) a carrot or a hat from a box
	for k in boxes.size():
		if _flat(rp - box_pos[k]) < 0.42 and rp.y < BOX_TOP + 0.35:
			next_id += 1
			var it := _make_item(next_id, box_kind[k], rp)
			it["s"] = HELD
			held_item = next_id
			fx("box", [k], "pickup", -2.0, 1.4)
			vr_rig.pulse(VrRig.RIGHT, 0.5, 0.08)
			hints.hint("vr_dress", "Put it on a snowman's head!", {"to": "vr"})
			return


## Take the top ball off an unfinished snowman; returns the new loose ball id.
func _pop_top(sid: int) -> int:
	var st: Dictionary = stack_data[sid]
	var radii: Array[float] = st["radii"]
	var p: Vector3 = st["pos"]
	var r: float = radii[radii.size() - 1]
	var c := p + Vector3.UP * Snowman.center_y(radii, radii.size() - 1)
	radii.pop_back()
	st["carrot"] = false
	st["hat"] = 0
	next_id += 1
	var id := next_id
	_make_ball(id, c, r)
	if radii.size() == 1:  # one ball left: a loose ball again
		stack_data.erase(sid)
		next_id += 1
		_make_ball(next_id, Vector3(p.x, 0.0, p.z), radii[0])
	_publish_stacks()
	return id


func _release_ball() -> void:
	var id := held_ball
	held_ball = -1
	if not balls.has(id):
		return
	var b: Dictionary = balls[id]
	var v := vr_rig.hand_velocity(VrRig.RIGHT)
	if v.length() < 2.5 and _try_snap(id, true):
		return
	b["s"] = FLYING
	b["v"] = v.limit_length(9.0)
	if v.length() > 2.0:
		fx("", [], "whoosh", -6.0)


# --- Carrots and hats -----------------------------------------------------------------------

func _make_item(id: int, kind: int, p: Vector3) -> Dictionary:
	var n := MeshInstance3D.new()
	n.mesh = Snowman.carrot_mesh() if kind == CARROT else Snowman.hat_of(kind)
	add_child(n)
	n.position = p
	var it := {"n": n, "k": kind, "s": FLYING, "v": Vector3.ZERO, "t": 0.0, "tgt": p}
	items[id] = it
	return it


func _free_item(id: int) -> void:
	if items.has(id):
		((items[id] as Dictionary)["n"] as Node).queue_free()
		items.erase(id)
	if held_item == id:
		held_item = -1


func _release_item() -> void:
	var id := held_item
	held_item = -1
	if not items.has(id):
		return
	var it: Dictionary = items[id]
	it["s"] = FLYING
	it["v"] = vr_rig.hand_velocity(VrRig.RIGHT).limit_length(9.0)


func _simulate_items(delta: float) -> void:
	for id in items.keys():
		var it: Dictionary = items[id]
		var n: Node3D = it["n"]
		var kind := int(it["k"])
		if int(it["s"]) == HELD:
			var h := vr_rig.hand(VrRig.RIGHT)
			n.position = h.global_transform * Vector3(0.0, 0.0, -0.06)
			var f := -h.global_basis.z
			n.basis = Basis(Vector3.UP, atan2(f.x, f.z))
		else:
			var v: Vector3 = it["v"]
			v.y -= 9.8 * delta
			it["v"] = v
			n.position += v * delta
			n.rotate_y(delta * 4.0)
		var sid := _head_near(n.position, kind, 0.2)
		if sid >= 0:
			if held_item == int(id):
				vr_rig.pulse(VrRig.RIGHT, 0.7, 0.1)
			_free_item(int(id))
			_dress(sid, kind, 0)
			continue
		if int(it["s"]) == FLYING and n.position.y < 0.03:
			fx("puff", [n.position], "puff", -8.0)
			_free_item(int(id))


## TV players run into a box to carry a carrot / hat, then run into a snowman to put it on.
func _tv_carry() -> void:
	for slot in avatars:
		var p: Vector3 = (avatars[slot] as Node3D).position
		if carry.has(slot):
			var kind := int(carry[slot])
			var sid := _head_near(p, kind, 0.55, true)
			if sid >= 0:
				carry.erase(slot)
				_dress(sid, kind, int(slot))
				continue
		for k in boxes.size():  # touching a box picks up (or swaps to) what is in it
			if _flat(p - box_pos[k]) < 0.75 and int(carry.get(slot, -1)) != box_kind[k]:
				carry[slot] = box_kind[k]
				fx("box", [k], "pickup", -4.0, 1.4)
				break


func _update_carry_visuals(delta: float) -> void:
	for slot in carry_nodes.keys():
		if not carry.has(slot) or not avatars.has(slot) or int((carry_nodes[slot] as Node).get_meta("k")) != int(carry.get(slot, -1)):
			(carry_nodes[slot] as Node).queue_free()
			carry_nodes.erase(slot)
	for slot in carry:
		if not avatars.has(slot):
			continue
		var a: Node3D = avatars[slot]
		if not carry_nodes.has(slot):
			var mi := MeshInstance3D.new()
			mi.mesh = Snowman.carrot_mesh() if int(carry[slot]) == CARROT else Snowman.hat_of(int(carry[slot]))
			mi.scale = Vector3.ONE * 1.6
			mi.set_meta("k", int(carry[slot]))
			add_child(mi)
			carry_nodes[slot] = mi
		var n: Node3D = carry_nodes[slot]
		n.position = a.position + Vector3.UP * (1.75 + sin(Time.get_ticks_msec() * 0.005) * 0.08)
		n.rotate_y(delta * 2.5)


# --- Visitors (every machine, from net state "wish") ------------------------------------------

func _animate_visitor(delta: float) -> void:
	var wv: Variant = net.state_get("wish", {})
	var w: Dictionary = wv if wv is Dictionary else {}
	var key := int(w.get("i", -1))
	if key != wish_shown and not garden.is_empty() and w.has("v"):
		wish_shown = key
		_make_visitor(int(w.get("v", 0)), int(w.get("hat", 1)), key > 0)
	if visitor == null or not is_instance_valid(visitor):
		return
	visitor_cheer = maxf(0.0, visitor_cheer - delta)
	var home: Vector3 = garden.get("visitor", Vector3(-2.7, 0.0, -0.9))
	visitor.position = home + Vector3.UP * (absf(sin(clock * 9.0)) * 0.35 if visitor_cheer > 0.0 else 0.0)
	var to := VR_START - home
	visitor.rotation.y = atan2(to.x, to.z) + (clock * 8.0 if visitor_cheer > 0.0 else 0.0)
	Creatures.anim(visitor).walk(0.0)
	if visitor_bubble != null:
		visitor_bubble.visible = String(net.state_get("phase", "play")) == "play"
		visitor_bubble.position.y = float(visitor_bubble.get_meta("y", 1.2)) + sin(clock * 2.5) * 0.06
		visitor_bubble.global_rotation.y = atan2(to.x, to.z)
	if visitor_hat != null:
		visitor_hat.rotation.y += delta * 1.5


## A visitor who wishes for a snowman with `hat` (a picture in a bubble over their head).
func _make_visitor(v: int, hat: int, fresh: bool) -> void:
	if visitor != null and is_instance_valid(visitor):
		visitor.queue_free()
	var info: Array = Story.VISITORS[clampi(v, 0, Story.VISITORS.size() - 1)]
	visitor = Creatures.monster(String(info[0]), {"scale": 1.0})
	visitor.name = "Visitor"
	add_child(visitor)
	visitor.position = garden.get("visitor", Vector3(-2.7, 0.0, -0.9))
	var h := Creatures.height_of(visitor)
	visitor_bubble = Node3D.new()
	visitor_bubble.set_meta("y", h + 0.15)
	visitor_bubble.position.y = h + 0.15
	visitor.add_child(visitor_bubble)
	var bub := MeshKit.instance(Village.bubble(), false)
	bub.scale = Vector3.ONE * 0.85
	visitor_bubble.add_child(bub)
	visitor_hat = MeshInstance3D.new()
	visitor_hat.mesh = Snowman.hat_of(maxi(1, hat))
	visitor_hat.position = Vector3(0.0, 0.62 * 0.85 - 0.08, 0.16)
	visitor_hat.scale = Vector3.ONE * 0.95
	visitor_bubble.add_child(visitor_hat)
	if fresh:  # a new friend arrives
		visitor.scale = Vector3.ONE * 0.2
		var tw := visitor.create_tween()
		tw.tween_property(visitor, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_burst(visitor.position + Vector3.UP * 0.6, 16, [Color(1, 1, 1)], 2.5)


# --- CPU helpers: Tumble helps a lone builder; two penguins roll for a VR builder alone ---------

func _update_helpers(delta: float) -> void:
	var want := 2 if vr_rig != null and avatars.is_empty() else (1 if _builders() <= 1 else 0)
	if not tele.is_empty():
		tele["helpers"] = maxi(int(tele.get("helpers", 0)), want)
	while helpers.size() < want:
		var n := _make_penguin(helpers.size() == 0)
		n.position = Vector3(randf_range(-3.0, 3.0), 0.0, -4.0)
		helpers.append({"n": n, "ball": -1, "goal": YARD, "t": 0.0, "tgt": n.position})
	while helpers.size() > want:
		var h: Dictionary = helpers.pop_back()
		(h["n"] as Node).queue_free()
	for h in helpers:
		var hd: Dictionary = h
		var n: Node3D = hd["n"]
		hd["t"] = float(hd["t"]) + delta
		var bid := int(hd["ball"])
		if not balls.has(bid) or int((balls[bid] as Dictionary)["s"]) != GROUND or float(hd["t"]) > 14.0 \
				or _flat((balls[bid]["n"] as Node3D).position - YARD) < YARD_R - 0.4:
			bid = _helper_pick(n.position)
			hd["ball"] = bid
			hd["t"] = 0.0
			var a := randf() * TAU
			hd["goal"] = YARD + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.3, 1.0)
		var to := Vector3.ZERO
		if bid >= 0:
			var b: Dictionary = balls[bid]
			var bp: Vector3 = (b["n"] as Node3D).position
			var r: float = b["r"]
			var dir: Vector3 = ((hd["goal"] as Vector3) - bp)
			dir.y = 0.0
			dir = dir.normalized()
			var behind := bp - dir * (r + BODY_R - 0.05)
			var rel := n.position - bp
			rel.y = 0.0
			if rel.dot(dir) > -0.1 and _flat(n.position - behind) > 0.3:  # in front: walk round it
				var side := Vector3(-dir.z, 0.0, dir.x)
				if rel.dot(side) < 0.0:
					side = -side
				to = (bp + side * (r + 0.7) - dir * (r + 0.6) - n.position)
			elif _flat(n.position - behind) > 0.25:
				to = behind - n.position
			else:
				to = dir
		else:
			to = Vector3(0.0, 0.0, -4.0) - n.position
			if to.length() < 0.5:
				to = Vector3.ZERO
		to.y = 0.0
		if to.length() > 0.01:
			to = to.normalized()
			n.position = _out_of_trees(n.position + to * 2.3 * delta, BODY_R)
			Creatures.anim(n).face(to)
			Creatures.anim(n).walk(2.3)
		else:
			Creatures.anim(n).walk(0.0)


## A helper penguin; the first is Tumble (bigger, with a red scarf).
func _make_penguin(tumble: bool) -> Node3D:
	var n := Creatures.monster("penguin", {"scale": 1.25 if tumble else 1.1})
	n.name = "Tumble" if tumble else "Penguin"
	add_child(n)
	if tumble:
		var sc := MeshKit.instance(Village.scarf(), false)
		sc.position.y = Creatures.height_of(n) * 0.62
		sc.scale = Vector3.ONE * 1.25
		n.add_child(sc)
	return n


func _helper_pick(from: Vector3) -> int:
	var best := -1
	var bd := INF
	for id in balls:
		var b: Dictionary = balls[id]
		if int(b["s"]) != GROUND:
			continue
		var bp: Vector3 = (b["n"] as Node3D).position
		if _flat(bp - YARD) < YARD_R + 0.2:
			continue
		var taken := false
		for h in helpers:
			if int((h as Dictionary)["ball"]) == int(id):
				taken = true
		if taken:
			continue
		var d := _flat(bp - from)
		if d < bd:
			bd = d
			best = int(id)
	return best


# --- Effects (play here, and on the TV machine through an event) ------------------------------

func fx(kind: String, args: Array, sound: String = "", vol: float = 0.0, pitch: float = 1.0) -> void:
	_fx_local(kind, args, sound, vol, pitch)
	if net.mode == "host":
		net.event("fx", [kind, args, sound, vol, pitch])


func _fx_local(kind: String, args: Array, sound: String, vol: float, pitch: float) -> void:
	var at := Vector3.ZERO
	match kind:
		"puff":
			at = args[0]
			_burst(at, 10, [Color(1, 1, 1)], 1.6)
		"pop":
			at = args[0]
			_burst(at + Vector3.UP * 0.2, 8, [Color(1, 1, 1)], 2.0)
		"sparkle":
			at = args[0]
			_burst(at, 18, [Color(1.0, 0.9, 0.3), Color(1.0, 1.0, 1.0)], 3.0)
		"wob":
			var node: Snowman = stack_nodes.get(int(args[0]))
			if node != null and is_instance_valid(node):
				node.wobble(args[1], float(args[2]))
				at = node.position + Vector3.UP
		"box":
			var bi := int(args[0])
			if bi < box_bounce.size():
				box_bounce[bi] = 1.0
				at = box_pos[bi]
		"wish":
			visitor_cheer = 2.0
			if visitor != null:
				at = visitor.position + Vector3.UP
				_burst(at + Vector3.UP, 30, [Color(1.0, 0.45, 0.6), Color(1.0, 0.85, 0.3)], 4.0)
				HudKit.popup(self, at + Vector3.UP * 1.6, "+1", {"style": "crit", "size": 2.0, "time": 1.5})
		"sign":
			sign_wob = 1.0
			at = SIGN_POS + Vector3.UP * 1.5
	if sound != "":
		if at != Vector3.ZERO:
			sfx.play_at(sound, at, vol, pitch)
		else:
			sfx.play(sound, vol, pitch)


func _burst(pos: Vector3, amount: int, colors: Array, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	# Cached: one mesh per single colour, one shared vertex-coloured mesh + a ramp per palette.
	var multi := colors.size() > 1
	var key := ""
	for c in colors:
		key += (c as Color).to_html(false)
	p.mesh = ResCache.get_or_make("snowman_bit_%s" % ("multi" if multi else key), func() -> Resource:
		var bm := SphereMesh.new()
		bm.radius = 0.05
		bm.height = 0.1
		bm.radial_segments = 6
		bm.rings = 3
		if multi:
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.3, 0.3)
			bm.material = mat
		else:
			bm.material = MeshKit.material(colors[0] as Color, 0.6)
		return bm)
	if multi:
		p.color_initial_ramp = ResCache.get_or_make("snowman_ramp_%s" % key, func() -> Resource: return _ramp(colors))
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / float(maxi(1, colors.size() - 1)))
		cols.append(colors[i] as Color)
	g.offsets = offs
	g.colors = cols
	return g


# --- Networking ---------------------------------------------------------------------------

func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var bf := PackedFloat32Array()
	for id in balls:
		var b: Dictionary = balls[id]
		var p: Vector3 = (b["n"] as Node3D).position
		ids.append(int(id))
		bf.append_array([p.x, p.y, p.z, float(b["r"])])
	var iids := PackedInt32Array()
	var itf := PackedFloat32Array()
	for id in items:
		var it: Dictionary = items[id]
		var n: Node3D = it["n"]
		iids.append(int(id))
		itf.append_array([n.position.x, n.position.y, n.position.z, float(it["k"]), n.rotation.y])
	var hf := PackedFloat32Array()
	for h in helpers:
		var n: Node3D = (h as Dictionary)["n"]
		hf.append_array([n.position.x, n.position.z, n.rotation.y])
	var cr := PackedInt32Array()
	for slot in carry:
		cr.append_array([int(slot), int(carry[slot])])
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
	return [pose, ids, bf, iids, itf, hf, cr, av_slots, av_pos, av_yaw]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 10:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var av_slots: PackedByteArray = s[7]
	var av_pos: PackedVector3Array = s[8]
	var av_yaw: PackedFloat32Array = s[9]
	for i in av_slots.size():
		var slot: int = av_slots[i]
		if avatars.has(slot) and not party.is_local(slot):
			if not net_target.has(slot):
				(avatars[slot] as Node3D).position = av_pos[i]
			net_target[slot] = [av_pos[i], av_yaw[i]]
	var ids: PackedInt32Array = s[1]
	var bf: PackedFloat32Array = s[2]
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		var p := Vector3(bf[i * 4], bf[i * 4 + 1], bf[i * 4 + 2])
		var b: Dictionary = balls[id] if balls.has(id) else _make_ball(id, p, bf[i * 4 + 3])
		b["tgt"] = p
		b["r"] = bf[i * 4 + 3]
	for id in balls.keys():
		if not seen.has(id):
			_free_ball(int(id))
	var iids: PackedInt32Array = s[3]
	var itf: PackedFloat32Array = s[4]
	seen.clear()
	for i in iids.size():
		var id := iids[i]
		seen[id] = true
		var p := Vector3(itf[i * 5], itf[i * 5 + 1], itf[i * 5 + 2])
		var it: Dictionary = items[id] if items.has(id) else _make_item(id, int(itf[i * 5 + 3]), p)
		it["tgt"] = p
		(it["n"] as Node3D).rotation.y = itf[i * 5 + 4]
	for id in items.keys():
		if not seen.has(id):
			_free_item(int(id))
	var hf: PackedFloat32Array = s[5]
	var count := hf.size() / 3
	while helpers.size() < count:
		var n := _make_penguin(helpers.size() == 0)
		helpers.append({"n": n, "ball": -1, "goal": YARD, "t": 0.0, "tgt": Vector3(hf[helpers.size() * 3], 0.0, hf[helpers.size() * 3 + 1])})
		n.position = (helpers[helpers.size() - 1] as Dictionary)["tgt"]
	while helpers.size() > count:
		var h: Dictionary = helpers.pop_back()
		(h["n"] as Node).queue_free()
	for i in count:
		var h: Dictionary = helpers[i]
		h["tgt"] = Vector3(hf[i * 3], 0.0, hf[i * 3 + 1])
		(h["n"] as Node3D).rotation.y = hf[i * 3 + 2]
	var cr: PackedInt32Array = s[6]
	carry.clear()
	for i in cr.size() / 2:
		carry[cr[i * 2]] = cr[i * 2 + 1]


## TV machine: glide the mirrored objects towards their last snapshot positions.
func _mirror_motion(delta: float) -> void:
	var k := clampf(delta * 18.0, 0.0, 1.0)
	for id in balls:
		var b: Dictionary = balls[id]
		var n: Node3D = b["n"]
		var from := n.position
		n.position = from.lerp(b["tgt"] as Vector3, k)
		_roll(b, from, n.position)
		b["pop"] = minf(1.0, float(b["pop"]) + delta * 3.0)
		n.scale = Vector3.ONE * float(b["r"]) * _ease_pop(float(b["pop"]))
	for id in items:
		var it: Dictionary = items[id]
		var n: Node3D = it["n"]
		n.position = n.position.lerp(it["tgt"] as Vector3, k)
	for h in helpers:
		var hd: Dictionary = h
		var n: Node3D = hd["n"]
		var from := n.position
		n.position = from.lerp(hd["tgt"] as Vector3, k)
		Creatures.anim(n).walk(_flat(n.position - from) / maxf(delta, 0.001))


func apply_event(kind: String, args: Array) -> void:
	if kind == "fx":
		_fx_local(String(args[0]), args[1], String(args[2]), float(args[3]), float(args[4]))
	elif kind == "story":
		show_story(args[0])
