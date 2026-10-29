extends Node3D
## WHACK-A-MOLE: a big friendly table full of holes, silly moles pop up, everyone bonks them.
## VR player: a giant soft mallet in the right hand (the left glove can slap moles too).
## TV players: tiny hammer-kids running ON the table, A = BONK. One shared score, 2-minute rounds,
## moles get faster, a golden mole is worth 5. Built on the engine template (games/engine_template).
## STORY (story.gd): FARMER FIG's garden. Every point grows veg in the bed round the table that Fig is
## growing (garden.gd); a full bed stays (saved) and the team picks the next crop by bonking one of two
## seed packets. Each crop brings its visitor moles (speedy, helmet, bunny - don't bonk!, the KING).
## Rounds are seeded (roundgen.gd: wave shapes, rising with the garden), with 1-3 STARS to earn; the
## first round each day is TODAY'S PATCH (the same on every machine). One RUN line per round.

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
const HudKit := preload("res://core/hud_kit.gd")
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Props := preload("res://games/whack_a_mole/props.gd")
const RoundGen := preload("res://games/whack_a_mole/roundgen.gd")
const Story := preload("res://games/whack_a_mole/story.gd")
const Garden := preload("res://games/whack_a_mole/garden.gd")
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")

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
const SEED_HOLES: Array[int] = [5, 6]  ## the two seed packets in the pick phase (middle row)
const PICK_WAIT := 15.0  ## nobody picks: the first packet is planted

var round_time := 120.0  ## seconds per round (bots shorten it before adding the game)
var fresh_save := false  ## bots: start a brand-new garden
var need_scale := 1.0  ## bots: smaller beds so a short round fills one

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
var kind_meshes := {}  # roundgen kind -> mesh (seed packets: "seed:<crop>")
# Mole simulation (host / local); the TV machine fills m_h / m_flags from snapshots.
var m_state := PackedInt32Array()
var m_kind := PackedByteArray()  # roundgen.gd kind
var m_hits := PackedByteArray()  # bonks still needed (helmet 2, king 5)
var m_h := PackedFloat32Array()  # 0 hidden .. 1 fully up
var m_t := PackedFloat32Array()
var vis_h := PackedFloat32Array()  # every machine: smoothed height for drawing
var shown_state := PackedInt32Array()  # every machine: last drawn state (for pop-up sounds)
var shown_kind := PackedByteArray()  # every machine: last drawn kind (helmet off: the mesh changes)
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
# Story and seeded rounds (host owns the save; every machine draws the garden from net state "garden").
var garden: Garden
var round_def := {}  # roundgen.gd round being played
var round_desc := {}  # {k: story/daily, crop, seed}
var spawn_i := 0
var elapsed := 0.0
var pick_t := 0.0
var daily_due := false
var last_crop := ""
var run := {}  # this round's numbers for the RUN line
var stars_mi: Array[MeshInstance3D] = []
var star_on: StandardMaterial3D
var star_off: StandardMaterial3D
var star_icons := {}  # hud slot -> [3 icons]
var crop_pics := {}  # hud slot -> [picture holder, bar]
var vr_story: Node3D


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
	if fresh_save:
		save.data = Story.save_defaults().duplicate(true)
	if int(save.data.world) < 0:
		save.data.world = Seeded.fresh_seed()  # this family's own garden rounds
		save.mark_dirty()
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
		var dd: Dictionary = save.data.daily
		daily_due = not dd.has(Seeded.today()) and not OS.has_environment("BOT_NO_DAILY")
		_publish_garden()
		print("Fig's garden: %d beds grown, growing %s (%d veg), daily %s (world %d)" % [Story.beds_grown(save.data.beds),
			String(save.data.cur), int(save.data.fill), daily_due, int(save.data.world)])
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
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, 8.5, 5.2, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 5))
	table = MeshKit.instance(Props.table_mesh())
	add_child(table)
	garden = Garden.new()
	garden.sfx = sfx
	add_child(garden)
	holes = Props.holes()
	var n := holes.size()
	m_state.resize(n)
	m_kind.resize(n)
	m_hits.resize(n)
	m_h.resize(n)
	m_t.resize(n)
	vis_h.resize(n)
	shown_state.resize(n)
	shown_kind.resize(n)
	for i in n:
		var root := Node3D.new()
		root.position = holes[i] + Vector3(0.0, MOLE_DOWN, 0.0)
		add_child(root)
		var body := MeshKit.instance(_kind_mesh(i, RoundGen.NORMAL), false)
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
	# Three goal stars on top of the board: they light up as the team passes each star's score.
	var sb := MeshKit.builder()
	sb.star(5, 0.16, 0.07, 0.05, Transform3D.IDENTITY, Color.WHITE)
	var star_mesh := sb.build()
	star_on = MeshKit.material(Color(1.0, 0.85, 0.2), 1.2)
	star_off = MeshKit.material(Color(0.35, 0.35, 0.45))
	for k in 3:
		var st := MeshInstance3D.new()
		st.mesh = star_mesh
		st.material_override = star_off
		st.position = Vector3(-0.42 + 0.42 * k, 3.12, -Props.HALF.y - 1.25)
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(st)
		stars_mi.append(st)
	_refresh_hud()


# --- HUD -------------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	# Every view: the team score with the round's three goal stars, and Fig's crop with its bed filling.
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var col := UiKit.vbox()
	card.add_child(col)
	var row := UiKit.hbox()
	col.add_child(row)
	var l := UiKit.label("0", "number")
	l.custom_minimum_size.x = 70.0
	row.add_child(l)
	score_labels[slot] = l
	var icons: Array = []
	for k in 3:  # the round's goal stars (dim until earned)
		var ic := UiKit.icon("star", Color(0.4, 0.4, 0.5), 34.0)
		row.add_child(ic)
		icons.append(ic)
	star_icons[slot] = icons
	var row2 := UiKit.hbox()  # the crop Fig is growing and how full its bed is
	col.add_child(row2)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(44.0, 44.0)
	row2.add_child(holder)
	var bar := UiKit.bar("xp", 150.0, 18.0, Color(0.5, 0.85, 0.35))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(bar)
	crop_pics[slot] = [holder, bar, ""]
	if slot < 0:
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
	if net == null:
		return
	var g: Array = net.state_get("goal", [])
	var got := RoundGen.stars(score, g) if g.size() == 3 else 0
	for k in stars_mi.size():
		stars_mi[k].material_override = star_on if k < got else star_off
	for slot in star_icons:
		var icons: Array = star_icons[slot]
		for k in icons.size():
			var ic: Control = icons[k]
			if is_instance_valid(ic):
				var want := Color(1.0, 0.85, 0.2) if k < got else Color(0.4, 0.4, 0.5)
				if ic.get("color") != want:
					ic.set("color", want)
					ic.queue_redraw()
					if k < got:
						UiKit.pop_in(ic)
	var gs: Dictionary = net.state_get("garden", {})
	var cur := String(gs.get("cur", ""))
	for slot in crop_pics:
		var cp: Array = crop_pics[slot]
		var holder: Control = cp[0]
		if not is_instance_valid(holder):
			continue
		if String(cp[2]) != cur:
			cp[2] = cur
			for c in holder.get_children():
				c.queue_free()
			if cur != "":
				holder.add_child(StoryCard.picture(String(Story.crop(cur).pic), 40.0))
		var bar: UiKit.Bar = cp[1]
		bar.visible = cur != ""
		bar.set_value(float(gs.get("fill", 0)), maxf(1.0, float(gs.get("need", 1))))


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
	star_icons.erase(slot)
	crop_pics.erase(slot)
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
	var playing := phase == "play" or phase == "practice" or phase == "pick"
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
	var why := "Paused by %s" % Who.seat(self, by_slot)
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
		"score", "best", "goal":
			_refresh_hud()
		"offers":  # the seed packets show the crops on offer (redraw them if they popped first)
			for h in SEED_HOLES:
				shown_kind[h] = 255
		"garden":
			if garden != null and value is Dictionary:
				garden.apply(value)
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

## Host: a new round. The first of a session starts with the practice mole; when Fig's bed is full the
## team picks the next crop (seed packets) before the moles come.
func _start_round(practice: bool) -> void:
	for i in holes.size():
		m_state[i] = HIDDEN
		m_h[i] = 0.0
		m_kind[i] = 0
	awards.reset()
	time_left = round_time
	spawn_t = 1.5
	practice_t = 0.0
	round_def = {}
	net.state_set("score", 0)
	net.state_set("goal", [])
	net.state_set("time", int(ceil(time_left)))
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	net.state_set("level", 0)
	if practice:
		_pop_mole(PRACTICE_HOLE, RoundGen.NORMAL, 9999.0)
		net.state_set("phase", "practice")
	else:
		_after_practice()


## Host: the practice is over (or there was none): pick seeds if the bed is full, else play.
func _after_practice() -> void:
	if String(save.data.cur) == "":
		_start_pick()
	else:
		_start_play()


## Host: two seed packets pop up; bonk one to plant it (nobody does: the first one after PICK_WAIT).
func _start_pick() -> void:
	var offers := Story.offers(int(save.data.world), save.data.beds, last_crop)
	if offers.size() < 2:
		_plant(String(offers[0]) if not offers.is_empty() else Story.FIRST_CROP)
		_start_play()
		return
	net.state_set("offers", offers)
	pick_t = 0.0
	for k in SEED_HOLES.size():
		var h: int = SEED_HOLES[k]
		if m_state[h] != HIDDEN:  # the practice mole may still be there
			m_state[h] = HIDDEN
			m_h[h] = 0.0
		_pop_mole(h, RoundGen.SEED, 9999.0)
	net.state_set("phase", "pick")
	_story(_fig(Story.PICK_LINE, "gift"))


## Host: a seed packet was bonked (k = 0 / 1): plant it, the other one goes down, the moles come.
func _pick(k: int) -> void:
	var offers: Array = net.state_get("offers", [])
	if String(net.state_get("phase", "")) != "pick" or offers.is_empty():
		return
	var id := String(offers[clampi(k, 0, offers.size() - 1)])
	for h in SEED_HOLES:
		if m_state[h] == UP:
			m_state[h] = LEAVING
	_plant(id)
	_start_play()


func _plant(id: String) -> void:
	save.data.cur = id
	save.data.fill = mini(int(save.data.get("carry", 0)), _need() / 2)
	save.data.carry = 0
	save.mark_dirty()
	_publish_garden()
	net.event("planted", [id])
	planted(id)


## Every machine: a crop was just planted (seeds sparkle over its bed).
func planted(id: String) -> void:
	if garden != null:
		garden.cheer(Story.crop_index(id))
	sound("power_up", -4.0)


func _need() -> int:
	return maxi(3, int(Story.bed_need(Story.beds_grown(save.data.beds)) * need_scale))


## Host: tell every machine what the garden looks like.
func _publish_garden() -> void:
	var gs := {"beds": (save.data.beds as Dictionary).duplicate(), "cur": String(save.data.cur),
		"fill": int(save.data.fill), "need": _need()}
	net.state_set("garden", gs)
	if garden != null and net.mode != "client":
		garden.apply(gs)  # (state_set may not echo to the host itself)


## Host: points the team bonked go into Fig's bed; a full bed stays for good and the next round picks seeds.
func _grow(pts: int) -> void:
	if pts <= 0:
		return
	if String(save.data.cur) == "":
		save.data.carry = int(save.data.get("carry", 0)) + pts  # bed full this round: a head start for the next
		return
	save.data.fill = int(save.data.fill) + pts
	if int(save.data.fill) >= _need():
		var id := String(save.data.cur)
		var beds: Dictionary = save.data.beds
		beds[id] = int(beds.get(id, 0)) + 1
		last_crop = id
		save.data.cur = ""
		save.data.fill = 0
		run["bed_done"] = id
		var c := Story.crop(id)
		_story(_fig(String(c.done), String(c.pic), c.color))
	save.mark_dirty()
	_publish_garden()


func _end_round() -> void:
	var score := int(net.state_get("score", 0))
	var g: Array = round_def.get("goal", [1, 2, 3])
	var st := RoundGen.stars(score, g)
	var daily := String(round_desc.get("k", "")) == "daily"
	var key := "TODAY" if daily else String(round_desc.get("crop", ""))
	var best_st: Dictionary = save.data.stars
	if not daily:
		best_st[key] = maxi(int(best_st.get(key, 0)), st)
	else:
		var dd: Dictionary = save.data.daily
		dd[Seeded.today()] = maxi(int(dd.get(Seeded.today(), 0)), score)
		while dd.size() > 30:
			var keys := dd.keys()
			keys.sort()
			dd.erase(keys[0])
	save.data.rounds = int(save.data.rounds) + 1
	save.mark_dirty()
	var stats: Array = [["STARS", "%d / 3" % st], ["BEST", str(int(net.state_get("best", 0)))]]
	var data := awards.results({"title": "%d POINTS!" % score, "subtitle": ["Keep bonking!", "One star!", "Two stars!", "THREE STARS!"][st],
		"style": "victory", "stats": stats, "score_format": "%d", "max_awards": 3, "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	for i in holes.size():
		if m_state[i] == UP:
			m_state[i] = LEAVING
	_telemetry("round", score, st)
	if not run.has("bed_done"):
		_story(_fig(Story.CHEERS[int(save.data.rounds) % Story.CHEERS.size()] if st > 0 else "Nearly! Again!", "farmer"))


func _exit_tree() -> void:
	if ready_to_play and net != null and net.mode != "client" and String(net.state_get("phase", "")) == "play":
		var score := int(net.state_get("score", 0))
		_telemetry("quit", score, RoundGen.stars(score, round_def.get("goal", [])))


## One RUN line per round (or quit mid-round): how the family really plays (balance).
func _telemetry(end: String, score: int, st: int) -> void:
	if round_def.is_empty() or net.mode == "client":
		return
	var info := run.duplicate()
	info.merge({"end": end, "mode": net.mode, "flat_host": flat_host, "vr": vr_rig != null,
		"players": party.player_count() + (1 if vr_rig != null else 0), "kind": String(round_desc.get("k", "")),
		"crop": String(round_desc.get("crop", "")), "seed": int(round_desc.get("seed", 0)), "level": int(round_def.get("level", 0)),
		"time": int(round_def.get("time", 0)), "played_s": int(elapsed), "score": score, "max": int(round_def.get("max", 0)),
		"goal": round_def.get("goal", []), "stars": st, "moles": (round_def.spawns as Array).size(),
		"beds": Story.beds_grown(save.data.beds), "fill": int(save.data.fill), "need": _need()}, true)
	Telemetry.run(GAME_ID, info)


## A story beat: Fig (or a crop / mole picture) and a few words, on every machine.
func _story(beat: Dictionary) -> void:
	if net.mode != "client":
		net.event("story", [beat.get("who", ""), beat.get("line", ""), beat.get("pic", ""), (beat.get("color", Story.FIG_COLOR) as Color).to_html()])
	show_story(beat)


func show_story(beat: Dictionary) -> void:
	StoryCard.show(_all_huds(), beat)
	if vr_rig != null:
		if vr_story != null and is_instance_valid(vr_story):
			vr_story.queue_free()
		vr_story = StoryCard.show_vr(self, vr_rig.camera, beat)


func _fig(line: String, pic: String = "farmer", color: Color = Story.FIG_COLOR) -> Dictionary:
	return {"who": "FIG", "line": line, "pic": pic, "color": color, "duration": 3.5}


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
			_after_practice()
		return
	if phase == "pick":
		pick_t += delta
		if pick_t > PICK_WAIT:
			_pick(0)
		return
	if round_def.is_empty():
		return
	elapsed += delta
	time_left = float(round_def.time) - elapsed
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if time_left <= 0.0:
		_end_round()
		return
	var p := clampf(elapsed / float(round_def.time), 0.0, 1.0)
	var level := int(p * 3.0)
	if level > int(net.state_get("level", 0)):
		net.state_set("level", level)
		net.state_set("faster", int(net.state_get("faster", 0)) + 1)  # a counter, so every round shows it
	var spawns: Array = round_def.spawns
	while spawn_i < spawns.size() and float(spawns[spawn_i][0]) <= elapsed:
		_spawn(spawns[spawn_i])
		spawn_i += 1


## Host: the generated round's next mole [t, hole, kind, stay]. Its hole is free (roundgen.gd checks
## that); if a helmet or the king held a hole longer, another free hole takes it.
func _spawn(s: Array) -> void:
	var h := int(s[1])
	if m_state[h] != HIDDEN or m_t[h] > 0.0:
		var free: Array[int] = []
		for i in holes.size():
			if m_state[i] == HIDDEN and m_t[i] <= 0.0:
				free.append(i)
		if free.is_empty():
			run["skipped"] = int(run.get("skipped", 0)) + 1
			return
		h = free[randi() % free.size()]
	var kind := int(s[2])
	_pop_mole(h, kind, float(s[3]))
	if kind != RoundGen.NORMAL and kind != RoundGen.KING:
		_meet(kind)
	elif kind == RoundGen.KING:
		_meet(kind)
		net.state_set("faster", int(net.state_get("faster", 0)) + 1)


## Host: the first time the family meets a kind of mole, Fig points at it (saved).
func _meet(kind: int) -> void:
	var met: Dictionary = save.data.met
	if met.has(str(kind)) or not Story.KIND_LINES.has(kind):
		return
	met[str(kind)] = true
	save.mark_dirty()
	_story({"who": "FIG", "line": String(Story.KIND_LINES[kind]), "pic": "bunny" if kind == RoundGen.BUNNY else ("crown" if kind == RoundGen.KING else "mole"),
		"color": Props.KIND_CARD[kind], "duration": 3.0})


## Host: the moles come: this round's moles are made from a seed (TODAY'S PATCH first each day).
func _start_play() -> void:
	if m_state[PRACTICE_HOLE] == UP and m_kind[PRACTICE_HOLE] == RoundGen.NORMAL:
		m_t[PRACTICE_HOLE] = minf(m_t[PRACTICE_HOLE], 2.0)  # nobody bonked it: it goes down like any mole
	var players := maxi(1, party.player_count() + (1 if vr_rig != null else 0))
	var sp: Dictionary
	if daily_due:
		daily_due = false
		sp = Story.daily_spec(players, round_time)
		round_desc = {"k": "daily", "crop": String(save.data.cur), "seed": Story.daily_seed()}
		_banner("TODAY!", "", 2.0)
	else:
		var met := {}
		for k in save.data.met:
			met[int(k)] = true
		var cur := String(save.data.cur)
		sp = Story.spec(cur, Story.beds_grown(save.data.beds), met, players, round_time)
		round_desc = {"k": "story", "crop": cur, "seed": Seeded.derive(int(save.data.world), "r%d" % int(save.data.rounds))}
	var t0 := Time.get_ticks_usec()
	round_def = RoundGen.generate(int(round_desc.seed), sp)
	run = {"gen_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01), "bunny_bonked": 0, "bunny_saved": 0, "king": 0,
		"missed": 0, "bonked": 0, "vr_bonked": 0}
	elapsed = 0.0
	spawn_i = 0
	time_left = float(round_def.time)
	net.state_set("goal", round_def.goal)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	var c := Story.crop(String(round_desc.crop))
	if round_desc.k == "story" and int(save.data.fill) == 0:
		_story(_fig(String(c.intro), String(c.pic), c.color))
	print("Whack-a-Mole round: %s %s seed %d, %d moles, goal %s (%.1f ms)" % [round_desc.k, round_desc.crop, int(round_desc.seed),
		(round_def.spawns as Array).size(), str(round_def.goal), float(run.gen_ms)])


func _pop_mole(i: int, kind: int, stay: float) -> void:
	m_state[i] = UP
	m_kind[i] = kind
	m_hits[i] = RoundGen.HITS[kind]
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
					_left_alone(i)
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


## Host: a mole went home un-bonked. A bunny left alone says thank you with a carrot (+2).
func _left_alone(i: int) -> void:
	if String(net.state_get("phase", "")) != "play" or run.is_empty():
		return
	if m_kind[i] == RoundGen.BUNNY:
		run["bunny_saved"] = int(run.bunny_saved) + 1
		save.data.bunnies = int(save.data.bunnies) + 1
		_add_points(-1, RoundGen.POINTS[RoundGen.BUNNY])
		bunny_fx(i, true)
		net.event("bunny", [i, true])
	elif m_kind[i] != RoundGen.SEED:
		run["missed"] = int(run.missed) + 1


## Host: points for the team (by = who, -1 = a bunny's gift): the score, the best, Fig's bed.
func _add_points(by: int, pts: int) -> void:
	if by >= 0:
		awards.add(by, "score", float(pts))
	var score := int(net.state_get("score", 0)) + pts
	net.state_set("score", score)
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)
	_grow(pts)


## Every machine: a bunny went home happy (left alone: a carrot and +2) or got bonked (a giggle, 0).
func bunny_fx(i: int, happy: bool) -> void:
	var pos := holes[i] + Vector3(0.0, 0.35, 0.0)
	if happy:
		HudKit.score(self, pos, RoundGen.POINTS[RoundGen.BUNNY], {"color": Color(1.0, 0.55, 0.15), "size": 1.3})
		sfx.play_at("sparkle", pos, -2.0, 1.3)
		var carrot := MeshKit.instance(Garden.plant_mesh("CARROTS"), false)
		carrot.position = holes[i]
		add_child(carrot)
		var tw := create_tween()
		tw.tween_property(carrot, "position", holes[i] + Vector3(0.0, 0.5, 0.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(carrot, "scale", Vector3.ZERO, 0.4).set_delay(0.5)
		tw.tween_callback(carrot.queue_free)
	else:
		sfx.play_at("boing", pos, -2.0, 1.8)  # a giggly boing, no points
		mole_bodies[i].scale = Vector3(0.8, 1.3, 0.8)


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
		var top := base.y + 0.46 * m_h[i] * (1.5 if m_kind[i] == RoundGen.KING else 1.0)
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
	var phase := String(net.state_get("phase", ""))
	var kind := int(m_kind[i])
	if kind == RoundGen.SEED:
		if phase == "pick":
			m_state[i] = BONKED
			m_t[i] = 0.5
			whack_fx(i, by, 0)
			net.event("whack", [i, by, 0])
			_pick(SEED_HOLES.find(i))
		return
	if kind == RoundGen.BUNNY:  # oops, a friend: it giggles and hops home (no points)
		m_state[i] = LEAVING
		m_t[i] = 0.0
		run["bunny_bonked"] = int(run.get("bunny_bonked", 0)) + 1
		bunny_fx(i, false)
		net.event("bunny", [i, false])
		return
	var was_practice := phase == "practice"
	total_whacked += 1
	run["bonked"] = int(run.get("bonked", 0)) + 1
	if by == 0 and vr_rig != null:
		vr_whacks += 1
		run["vr_bonked"] = int(run.get("vr_bonked", 0)) + 1
	net.state_set("whacked", total_whacked)
	var pts: int = RoundGen.POINTS[kind]
	if m_hits[i] > 1:  # a helmet clonks off / the king wobbles: still up, bonk again
		m_hits[i] -= 1
		m_t[i] = maxf(m_t[i], 0.9)
		pts = 0
		if kind == RoundGen.HELMET:
			m_kind[i] = RoundGen.BARE
		else:
			pts = 1  # every bonk on the king counts
		clonk_fx(i, by, kind)
		net.event("clonk", [i, by, kind])
		if pts > 0 and not was_practice:
			_add_points(by, pts)
		return
	if kind == RoundGen.KING:
		pts = RoundGen.POINTS[RoundGen.KING] - (RoundGen.HITS[RoundGen.KING] - 1)
		run["king"] = 1
		save.data.kings = int(save.data.kings) + 1
	m_state[i] = BONKED
	m_t[i] = 0.35
	if not was_practice:
		_add_points(by, pts)
	else:
		awards.add(by, "score", float(pts))
	whack_fx(i, by, pts)
	net.event("whack", [i, by, pts])
	if was_practice:
		_after_practice()


## Every machine: a helmet popped off (it flies off, clonk!) or the king took a bonk (he wobbles).
func clonk_fx(i: int, by: int, kind: int) -> void:
	var body := mole_bodies[i]
	body.scale = Vector3(1.3, 0.7, 1.3)
	var pos := holes[i] + Vector3(0.0, 0.45, 0.0)
	sfx.play_at("hit" if kind == RoundGen.HELMET else "boing", pos, 0.0, 0.8 if kind == RoundGen.KING else 1.4)
	if kind == RoundGen.HELMET:
		var hm := MeshInstance3D.new()
		var b := MeshKit.builder()
		b.dome(0.155, Transform3D.IDENTITY, Color(0.95, 0.25, 0.25), 12)
		hm.mesh = b.build()
		hm.position = pos
		add_child(hm)
		var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-0.4, 0.4)).normalized() * 0.6
		var tw := create_tween().set_parallel()
		tw.tween_property(hm, "position", pos + side + Vector3(0.0, 0.5, 0.0), 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_property(hm, "rotation", Vector3(2.0, 0.0, 3.0), 0.6)
		tw.chain().tween_property(hm, "position", pos + side * 1.5 + Vector3(0.0, -0.6, 0.0), 0.35).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(hm.queue_free)
	else:
		HudKit.score(self, pos + Vector3.UP * 0.3, 1, {"color": party.color_of(by) if by >= 0 else "gold", "size": 1.0})
	if by >= 0 and avatars.has(by):
		Creatures.anim(avatars[by]).play("cheer", 0.4)


## Every machine: the juicy bit. Squash, burst, "+1", sound, kids cheer.
func whack_fx(i: int, by: int, pts: int) -> void:
	var gold := pts >= 5  # golden moles and the king: the big kaching
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
	if pts > 0:
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
		var kind := int(m_kind[i])
		if st != shown_state[i] or (st == UP and kind != shown_kind[i]):
			if st == UP:
				var gold := kind == RoundGen.GOLD or kind == RoundGen.KING
				mole_bodies[i].mesh = _kind_mesh(i, kind)
				var big := 1.5 if kind == RoundGen.KING else (1.7 if kind == RoundGen.SEED else 1.0)
				root.scale = Vector3.ONE * big
				if st != shown_state[i]:
					mole_bodies[i].scale = Vector3(0.8, 1.25, 0.8)
					sfx.play_at("sparkle" if gold else "pop", holes[i], -8.0 if not gold else 0.0, randf_range(1.2, 1.5))
					if kind == RoundGen.KING:
						sfx.play_at("fanfare", holes[i], -4.0)
			shown_state[i] = st
			shown_kind[i] = kind
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


## The mesh for a mole of this kind in hole i (seed packets: the crop offered in that hole). Cached.
func _kind_mesh(i: int, kind: int) -> Mesh:
	var key: Variant = kind
	if kind == RoundGen.SEED:
		var offers: Array = net.state_get("offers", []) if net != null else []
		var k := SEED_HOLES.find(i)
		var id := String(offers[k]) if k >= 0 and k < offers.size() else Story.FIRST_CROP
		key = "seed:" + id
		if not kind_meshes.has(key):
			kind_meshes[key] = Props.seed_mesh(Story.crop(id).color, Garden.icon_mesh(id))
	elif not kind_meshes.has(key):
		kind_meshes[key] = Props.kind_mesh(kind)
	return kind_meshes[key]


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
		flags[i] = m_state[i] | (m_kind[i] << 2)  # state 2 bits, kind 3 bits
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
		m_kind[i] = (flags[i] >> 2) & 7


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
		"clonk":
			clonk_fx(int(args[0]), int(args[1]), int(args[2]))
		"bunny":
			bunny_fx(int(args[0]), bool(args[1]))
		"planted":
			planted(String(args[0]))
		"story":
			show_story({"who": String(args[0]), "line": String(args[1]), "pic": String(args[2]),
				"color": Color.html(String(args[3])), "duration": 3.5})
		"swing":
			var ss := int(args[0])
			if avatars.has(ss) and not party.is_local(ss):
				Creatures.anim(avatars[ss]).play("attack", 0.35)
