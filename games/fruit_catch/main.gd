extends Node3D
## FRUIT CATCH: a giant tree drops fruit. TV players run about with baskets on their heads to catch it.
## The VR player grabs the low branches and shakes them to drop fruit, catches fruit with a glove and
## throws (or dunks) it into the big bowl. Rotten apples splat (a TV player who catches one gets dizzy).
## One team score, 2-minute rounds, a results card, then the next round starts by itself.
## Built on the engine template (games/engine_template): party seats, split view, VR rig, state store.
## Story: NUTMEG the squirrel (by the bowl) cooks for the forest friends. Each round is a seeded HARVEST
## (harvestgen.gd): the tree drops fruit on a schedule and Nutmeg asks for dishes in turn (a recipe of
## fruit: picture + count on every HUD and on the sign for VR). Finished dishes plant a tree in the
## ORCHARD round the park (saved; trees grow a stage each day the family plays). TODAY'S HARVEST: the
## first round each day is the same gold harvest on every machine (golden tree). Telemetry: one RUN line
## per round and on quit. Networked: the host sends [seed, level, daily, secs] ("harvest"), the dish
## number, the fruit got so far and the orchard as state; every machine rebuilds the rest.

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
const Art := preload("res://games/fruit_catch/art.gd")
const G := preload("res://games/fruit_catch/harvestgen.gd")
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")
const NUTMEG_POS := Vector3(2.35, 0.0, 2.1)  ## Nutmeg's stump, right of the bowl
const ORCHARD_CHEERS := {1: "Our first tree!", 5: "Five trees!", 10: "Ten trees!", 20: "A big orchard!", 36: "A whole forest!"}

const GAME_ID := "fruit_catch"
const ARENA := 8.5
const SPEED := 4.8
const TRUNK_R := 0.9
const BRANCHES := 5
const BRANCH_ANCHOR := Vector3(0.0, 3.4, 0.0)  ## where the branches leave the trunk (radius 0.45)
const TIP_RADIUS := 2.2  ## branch tips: how far from the trunk...
const TIP_HEIGHT := 1.45  ## ...and how high (an easy reach, standing or sitting)
const DROP_HEIGHT := 4.1  ## fruit appears under the leaves
const FALL_G := 2.6  ## slow, floaty fall
const HANG_TIME := 0.45  ## fruit wiggles before it falls
const MAX_FRUIT := 18
const BOWL_POS := Vector3(1.25, 0.0, 2.4)  ## front right of the VR player
const SIGN_POS := Vector3(-1.6, 0.0, 1.6)  ## the score sign, front left of the VR player
const BOWL_TOP := 0.8
const BOWL_R := 0.75
const VR_START := Vector3(0.0, 0.0, 3.05)
const BASKET_UP := 0.08  ## basket top above the avatar's head
const LOOKS: Array[String] = ["farmer", "chef", "villager", "princess", "pirate", "athlete", "bard"]
enum { HANG, FALL, HELD, THROWN }

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

var avatars := {}  # slot -> Node3D: TV players (every machine)
var baskets := {}  # slot -> Node3D on the avatar's head
var last_pos := {}
var dizzy := {}  # slot -> seconds left (caught a rotten apple)
var boop_t := {}  # slot -> cooldown for the VR player's boop
var cams := {}
var group_cam: CameraRig
var huds := {}
var score_labels := {}
var timers := {}
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var crown: Node3D
var bowl: Node3D
var bowl_pile: Array[MeshInstance3D] = []
var sign_label: Label3D  # the score + clock on the trunk (world-locked, readable from VR and TV)
var branch_nodes: Array[Node3D] = []
var branch_rest: Array[Vector3] = []  # rest tip positions
var branch_off: Array[Vector3] = []  # tip displacement (spring)
var branch_vel: Array[Vector3] = []
var branch_hand: Array[int] = []  # which VR hand holds the branch (-1)
var branch_energy: Array[float] = []
var fruits := {}  # id -> Dictionary {node, shadow, kind, state, vel, hand, t}
var next_fruit := 0
var send_t := 0.0
var time_left := 0.0
var results_t := 0.0
var total_caught := 0
var dunks := 0  # host: fruit in the bowl (bots)
var shakes := 0  # host: fruit shaken off a branch (bots)
var in_bowl := 0  # this round's fruit in the bowl (drawn as a pile)
var combo := 0
var combo_t := 0.0
var touch_t := 0.0  # cooldown for trunk / bowl touches
var grabbed_once := false
var clock := 0.0
var frenzy := false
# --- Harvest (story + procedural rounds) ---
var session_seed := 0
var session_round := 0  # host: rounds played this session (sets the level)
var harvest := {}  # every machine: this round's harvest (rebuilt from the "harvest" state)
var drop_i := 0  # host: next scheduled drop
var round_clock := 0.0  # host: seconds into the round
var shake_rng := RandomNumberGenerator.new()
var dishes_done := 0  # host: dishes finished this round
var rotten_caught := 0  # host: this round (telemetry)
var caught_round := 0  # host: this round (telemetry)
var round_live := false  # host: a round is being played (for the quit RUN line)
var shakes_round := 0  # host: fruit shaken down this round (telemetry)
var recipe_rows := {}  # slot -> HBoxContainer on the HUD
var sign_recipe: Node3D  # the recipe on the sign's lower board (VR + TV)
var orchard: Node3D
var orchard_count := -1
var nutmeg: Node3D
var nutmeg_hop := 0.0
var story_queue: Array = []  # beats waiting to show: [line, pic, color]
var story_t := 0.0


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
	# orchard: [[fruit kind, play-day planted, golden, dishes], ...]; days: days played; daily: the date
	# TODAY'S HARVEST was done.
	save.defaults = {"best": 0, "orchard": [], "trees": 0, "dishes": 0, "days": 0, "last_day": "", "daily": "", "sessions": 0}
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
		vr_rig.bounds = Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0)
		vr_rig.move_filter = func(_from: Vector3, to: Vector3) -> Vector3: return _push_out(to, 0.3)
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
		group_cam.group_min_distance = 11.0
		add_child(group_cam)
		group_cam.follow_group([], -32.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	awards.set_player(0, "GIANT" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		_begin_session()
		_start_round()
	if vr_rig != null:
		hints.hint("vr_shake", "Grab a branch and SHAKE!", {"to": "vr"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Fruit Catch: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA + 16.0
	disc.bottom_radius = ARENA + 16.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.45, 0.75, 0.35))
	ground.position.y = -0.1
	add_child(ground)
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 18, Vector3.ZERO, ARENA + 14.0, ARENA + 5.0, 0.8, 1.3, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 16, Vector3.ZERO, ARENA + 2.5, ARENA + 0.8, 0.8, 1.2, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, ARENA - 0.5, 4.5, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 5))
	crown = Node3D.new()
	crown.name = "Tree"
	add_child(crown)
	crown.add_child(MeshKit.instance(Art.tree(), not vr))
	for k in BRANCHES:
		var a := PI * 0.5 + k * TAU / BRANCHES
		var tip := Vector3(cos(a) * TIP_RADIUS, TIP_HEIGHT, sin(a) * TIP_RADIUS)
		var b := Node3D.new()
		b.position = BRANCH_ANCHOR + Vector3(cos(a), 0.0, sin(a)) * 0.45
		add_child(b)
		b.add_child(MeshKit.instance(Art.branch(b.position.distance_to(tip)), false))
		branch_nodes.append(b)
		branch_rest.append(tip)
		branch_off.append(Vector3.ZERO)
		branch_vel.append(Vector3.ZERO)
		branch_hand.append(-1)
		branch_energy.append(0.0)
		_pose_branch(k)
	bowl = Node3D.new()
	bowl.position = BOWL_POS
	add_child(bowl)
	bowl.add_child(MeshKit.instance(Art.bowl(BOWL_TOP, BOWL_R)))
	var post := Node3D.new()  # a wooden sign with the score and the clock, turned to face the VR player
	post.position = SIGN_POS
	var d := SIGN_POS - VR_START
	post.basis = Basis(Vector3.UP, atan2(-d.x, -d.z))
	add_child(post)
	post.add_child(MeshKit.instance(Art.sign_post(), not vr))
	sign_label = UiKit.label3d("0", 0.32, "gold", true)
	sign_label.position = Vector3(0.0, 2.1, 0.08)
	post.add_child(sign_label)
	sign_recipe = Node3D.new()  # the dish's fruit and counts on the lower board
	sign_recipe.position = Vector3(0.0, Art.SIGN_LOW_Y, 0.08)
	post.add_child(sign_recipe)
	nutmeg = Node3D.new()
	nutmeg.name = "Nutmeg"
	nutmeg.position = NUTMEG_POS
	var nd := VR_START - NUTMEG_POS
	nutmeg.basis = Basis(Vector3.UP, atan2(nd.x, nd.z))
	add_child(nutmeg)
	nutmeg.add_child(MeshKit.instance(Art.stump()))
	var sq := MeshKit.instance(Art.squirrel())
	sq.name = "Body"
	sq.position.y = Art.STUMP_TOP
	sq.scale = Vector3.ONE * Art.NUTMEG_SCALE
	nutmeg.add_child(sq)
	orchard = Node3D.new()
	orchard.name = "Orchard"
	add_child(orchard)


## Point branch k at its (displaced) tip.
func _pose_branch(k: int) -> void:
	var b: Node3D = branch_nodes[k]
	var tip: Vector3 = branch_rest[k] + branch_off[k]
	UiKit.look(b, tip, Vector3.UP)
	var rest_len := b.position.distance_to(branch_rest[k])
	var s := 1.0  # the branches breathe until someone grabs one: "touch me"
	if vr_rig != null and not grabbed_once:
		s = 1.0 + 0.08 * sin(clock * 5.0 + k)
	b.scale = Vector3(s, s, b.position.distance_to(tip) / rest_len)


func branch_tip(k: int) -> Vector3:
	return branch_rest[k] + branch_off[k]


## Keep feet out of the trunk and the bowl.
func _push_out(p: Vector3, r: float) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() < TRUNK_R + r:
		flat = flat.normalized() * (TRUNK_R + r) if flat.length() > 0.01 else Vector2(0.0, TRUNK_R + r)
	var bd := flat - Vector2(BOWL_POS.x, BOWL_POS.z)
	if bd.length() < BOWL_R + r:
		flat = Vector2(BOWL_POS.x, BOWL_POS.z) + bd.normalized() * (BOWL_R + r)
	var nd := flat - Vector2(NUTMEG_POS.x, NUTMEG_POS.z)  # Nutmeg's stump
	if nd.length() < Art.STUMP_R + r:
		flat = Vector2(NUTMEG_POS.x, NUTMEG_POS.z) + nd.normalized() * (Art.STUMP_R + r)
	return Vector3(flat.x, p.y, flat.y)


# --- HUD ---------------------------------------------------------------------------------

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
	row.add_child(UiKit.icon("dot", Color(0.95, 0.15, 0.15), 34.0))
	var l := UiKit.label("0", "number")
	row.add_child(l)
	score_labels[slot] = l
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})
	var rc := UiKit.panel("card")  # Nutmeg's recipe: the dish, then each fruit's picture and count
	rc.name = "Recipe"
	ui.add_child(rc)
	UiKit.pin(rc, Control.PRESET_BOTTOM_LEFT)
	rc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	rc.offset_left = 24.0
	rc.offset_bottom = -20.0
	rc.offset_top = -20.0
	var rr := UiKit.hbox()
	rc.add_child(rr)
	recipe_rows[slot] = rr
	_refresh_recipe_row(slot)
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


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	for slot in score_labels:
		var l: Label = score_labels[slot]
		if is_instance_valid(l):
			l.text = "%d" % score
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if sign_label != null:
		var t := int(net.state_get("time", 0))
		sign_label.text = "%d\n%d:%02d" % [score, t / 60, t % 60]


## Every machine: every HUD's recipe row and the sign.
func _refresh_recipes() -> void:
	for slot in recipe_rows:
		_refresh_recipe_row(slot)
	_refresh_sign_recipe()


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


func _banner(title: String, sub: String = "", style: String = "default") -> void:
	HudKit.banner(_all_huds(), title, sub, {"duration": 2.2, "style": style})
	if vr_rig != null:
		HudKit.vr_banner(self, vr_rig.camera, title, sub, {"duration": 2.2, "sound": "", "distance": 2.6, "style": style})


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 1.0
		c.pitch = -0.38
		add_child(c)
		c.follow(a, 6.5, 0.0)
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
	baskets.erase(slot)
	last_pos.erase(slot)
	net_target.erase(slot)
	dizzy.erase(slot)
	boop_t.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	recipe_rows.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_group()
	_refresh_hud()


func _ensure_avatar(slot: int) -> Node3D:
	if avatars.has(slot) and is_instance_valid(avatars[slot]):
		return avatars[slot]
	var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": slot, "hat": "none"})
	a.name = "Avatar%d" % slot
	add_child(a)
	var ang := 0.9 + slot * 0.9
	a.position = Vector3(cos(ang), 0.0, sin(ang)) * 4.5
	var bk := Node3D.new()
	bk.add_child(MeshKit.instance(Art.basket()))
	bk.position.y = Creatures.height_of(a) - 0.12
	a.add_child(bk)
	baskets[slot] = bk
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.55, 0.18)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


func basket_top(slot: int) -> Vector3:
	var a: Node3D = avatars[slot]
	return a.position + Vector3.UP * (Creatures.height_of(a) + BASKET_UP)


func _refresh_group() -> void:
	if group_cam != null:
		group_cam.set_targets(avatars.values())


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
			var speed := SPEED * (0.35 if float(dizzy.get(slot, 0.0)) > 0.0 else 1.0)
			var p := a.position + dir * speed * delta
			p.y = 0.0
			a.position = _push_out(p.limit_length(ARENA), 0.35)
			Creatures.anim(a).face(dir)
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)
		if party.just_pressed(slot, "y"):
			net.request(slot, "toggle_view")


func _animate_avatars(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.3 else 0.0)
		last_pos[slot] = a.position
		var dz: float = dizzy.get(slot, 0.0)
		var bk: Node3D = baskets.get(slot)
		if dz > 0.0:
			dizzy[slot] = dz - delta
			if bk != null:
				bk.rotation.z = sin(clock * 14.0) * 0.25
		elif bk != null:
			bk.rotation.z = lerpf(bk.rotation.z, 0.0, delta * 8.0)


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
	match action:
		"toggle_view":
			net.state_set("shared", not bool(net.state_get("shared", false)))
		"next_round":
			if String(net.state_get("phase", "")) == "results":
				_start_round()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", "", {"width": 1.4, "distance": 2.4})
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
		"shared":
			if split != null and String(net.state_get("phase", "play")) == "play":
				split.set_shared(bool(value))
		"score", "best":
			_refresh_hud()
		"time":
			_refresh_hud()
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
		"round":
			if harvest.get("daily", false):
				_banner("TODAY'S HARVEST!", "", "victory")
		"harvest":
			var hv: Array = value
			if net.mode == "client" or harvest.is_empty() or int(harvest.seed) != int(hv[0]) or int(harvest.level) != int(hv[1]):
				harvest = G.harvest(int(hv[0]), int(hv[1]), bool(hv[2]), float(hv[3]))
			_refresh_recipes()
			if bool(hv[2]):
				_story("TODAY'S HARVEST!", "fruitbowl", Color(1.0, 0.8, 0.2))
			_story("Let's make %s!" % _dish_name(0), G.DISH_PICS[int((harvest.dishes as Array)[0][0])], _dish_color(int((harvest.dishes as Array)[0][0])))
			if (harvest.wind as Vector2).length() > 0.3:
				_story("Breezy day!", "cloud", Color(0.6, 0.85, 1.0))
		"dish":
			_refresh_recipes()
			var d := int(value)
			var dishes: Array = harvest.get("dishes", [])
			if d > 0 and d <= dishes.size():
				var prev := int((dishes[d - 1] as Array)[0])
				_story("Yum! %s!" % G.DISH_NAMES[prev], G.DISH_PICS[prev], _dish_color(prev))
				if d < dishes.size():
					var nx := int((dishes[d] as Array)[0])
					_story(("Bonus! " if d >= 3 else "Now ") + "%s!" % G.DISH_NAMES[nx], G.DISH_PICS[nx], _dish_color(nx))
				else:
					_story("What a feast!", "fruitbowl", Color(1.0, 0.8, 0.3))
		"got":
			_refresh_recipes()
		"orchard":
			var list: Array = value if value is Array else []
			var grown := orchard_count >= 0 and list.size() > orchard_count
			_build_orchard(list)
			if grown:
				var n := list.size()
				_story(ORCHARD_CHEERS.get(n, "A new tree!"), "sapling", Art.FRUIT_COLORS[int((list[n - 1] as Array)[0])])
		"days":
			_build_orchard(net.state_get("orchard", []))
		"grew":
			if bool(value):
				_story("Our trees grew!", "sapling", Color(1.0, 0.6, 0.7))
		"frenzy":
			if bool(value):
				_banner("FRUIT STORM!", "", "warning")
		"bowl":
			_set_pile(int(value))
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------

## Host: a new session. Count the play-day (trees grow a stage each day), pick the session seed, show the orchard.
func _begin_session() -> void:
	session_seed = int(OS.get_environment("FC_SEED")) if OS.has_environment("FC_SEED") else Seeded.fresh_seed()
	shake_rng = Seeded.rng(session_seed, "shake")
	var grew := false
	if String(save.data.last_day) != Seeded.today():
		save.data.days = int(save.data.days) + 1
		save.data.last_day = Seeded.today()
		for e in save.data.orchard:
			if G.tree_stage(int(e[1]), int(save.data.days)) > G.tree_stage(int(e[1]), int(save.data.days) - 1):
				grew = true
	save.data.sessions = int(save.data.sessions) + 1
	save.mark_dirty()
	net.state_set("days", int(save.data.days))
	net.state_set("orchard", (save.data.orchard as Array).duplicate(true))
	net.state_set("grew", grew)
	print("Fruit Catch orchard: %d trees (%d planted in all), day %d, today's harvest %s, session seed %d" % [
		(save.data.orchard as Array).size(), int(save.data.trees), int(save.data.days),
		"done" if String(save.data.daily) == Seeded.today() else "due", session_seed])


func _start_round() -> void:
	for id in fruits.keys():
		_free_fruit(int(id))
	awards.reset()
	time_left = round_time
	frenzy = false
	session_round += 1
	var daily := String(save.data.daily) != Seeded.today()
	var lv := G.DAILY_LEVEL if daily else G.level(session_round, int(save.data.trees))
	var seed_value := G.daily_seed() if daily else G.round_seed(session_seed, session_round)
	harvest = G.harvest(seed_value, lv, daily, round_time)
	drop_i = 0
	round_clock = 0.0
	dishes_done = 0
	rotten_caught = 0
	caught_round = 0
	shakes_round = 0
	round_live = true
	print("Fruit Catch harvest: level %d, seed %d%s, dishes %s, %d drops, wind %.2f" % [lv, seed_value,
		" (TODAY'S HARVEST)" if daily else "", str(harvest.dishes), (harvest.drops as Array).size(), (harvest.wind as Vector2).length()])
	net.state_set("frenzy", false)
	net.state_set("score", 0)
	net.state_set("bowl", 0)
	net.state_set("got", [0, 0, 0, 0])
	net.state_set("dish", 0)
	net.state_set("harvest", [seed_value, lv, daily, round_time])
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	music.play_mood("party")


## Host: one RUN line per round (end = "round") or when the game closes mid-round (end = "quit").
func _run_line(end: String) -> void:
	if harvest.is_empty():
		return
	round_live = false
	Telemetry.run(GAME_ID, {"end": end, "round": session_round, "level": int(harvest.level), "seed": int(harvest.seed),
		"daily": bool(harvest.daily), "secs": snappedf(round_time - maxf(time_left, 0.0), 0.1), "dishes": dishes_done,
		"dish_list": (harvest.dishes as Array).map(func(d: Array) -> int: return int(d[0])), "got": net.state_get("got", []),
		"score": int(net.state_get("score", 0)), "caught": caught_round, "rotten": rotten_caught, "dunks": int(net.state_get("bowl", 0)),
		"shakes": shakes_round, "players": party.active_slots().size(), "vr": vr_rig != null, "mode": String(net.mode),
		"wind": snappedf((harvest.wind as Vector2).length(), 0.01), "trees": int(save.data.trees),
		"orchard": (save.data.orchard as Array).size(), "days": int(save.data.days), "best": int(save.data.best)})


func _exit_tree() -> void:
	if round_live and net != null and net.mode != "client":
		_run_line("quit")
		save.save_now()


func _end_round() -> void:
	for id in fruits.keys():
		_free_fruit(int(id))
	var score := int(net.state_get("score", 0))
	var planted := _plant_tree()
	_run_line("round")
	var title := "YUM! %d FRUIT!" % score
	if dishes_done > 0:
		title = "%d DISH%s!" % [dishes_done, "" if dishes_done == 1 else "ES"]
	var data := awards.results({"title": title, "subtitle": "A new tree!" if planted else "Great catching, team!",
		"style": "victory", "stats": [["FRUIT", str(score)], ["BEST", str(int(net.state_get("best", 0)))],
		["TREES", str((save.data.orchard as Array).size())]], "score_format": "%d FRUIT"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	sound("fanfare")


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
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
		_move_local_players(delta)
	_follow_remote(delta)
	_animate_avatars(delta)
	_animate_fruit_visuals(delta)
	_animate_nutmeg(delta)
	_update_story(delta)
	if net.mode == "client":
		for k in BRANCHES:
			_pose_branch(k)
		return
	_update_branches(delta)
	if results_showing():
		results_t += delta
		if results_t > 12.0:
			_start_round()  # play again by itself
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
		if time_left <= 5.5 and time_left > 0.0:
			sound("tick", -4.0)
	if time_left <= 0.0:
		_end_round()
		return
	round_clock += delta
	if not frenzy and round_clock >= float(harvest.storm_at):
		frenzy = true
		net.state_set("frenzy", true)
	combo_t -= delta
	if combo_t <= 0.0:
		combo = 0
	touch_t -= delta
	var drops: Array = harvest.drops
	while drop_i < drops.size() and float(drops[drop_i][0]) <= round_clock:  # the harvest's schedule
		if not (vr_rig != null and G.vr_skips(drop_i)):  # a giant shakes down the rest
			_drop_scheduled(drops[drop_i])
		drop_i += 1
	if vr_rig != null:
		_vr_hands(delta)
	_simulate_fruit(delta)


## Branch springs, and the VR player's grabs (host / local).
func _update_branches(delta: float) -> void:
	for k in BRANCHES:
		var h := branch_hand[k]
		if h >= 0 and vr_rig != null:
			var to := vr_rig.hand_point(h) - branch_rest[k]
			if to.length() > 1.25 or results_showing():
				branch_hand[k] = -1  # pulled too far: it springs out of your hand
				vr_rig.pulse(h, 0.6, 0.08)
				fx("snap", branch_tip(k), Color.WHITE, k)
				if not results_showing():
					_drop_fruit(k)
				continue
			var target := to.limit_length(0.9)
			branch_vel[k] = (target - branch_off[k]) / maxf(delta, 0.001)
			branch_off[k] = target
			branch_energy[k] += vr_rig.hand_speed(h) * delta
			if branch_energy[k] > 0.8:
				branch_energy[k] = 0.0
				vr_rig.pulse(h, 0.35, 0.05)
				if not results_showing():
					shakes += 1
					shakes_round += 1
					_drop_fruit(k)
		else:
			branch_vel[k] += (-branch_off[k] * 45.0 - branch_vel[k] * 3.5) * delta
			branch_off[k] += branch_vel[k] * delta
		_pose_branch(k)


## VR hands: grab branches, catch and carry fruit, touch the trunk, the bowl and the TV players.
func _vr_hands(delta: float) -> void:
	for h in 2:
		var p := vr_rig.hand_point(h)
		var busy := branch_hand.has(h) or _held_by(h) >= 0
		if not busy:
			for k in BRANCHES:
				if branch_hand[k] < 0 and p.distance_to(branch_tip(k)) < 0.42:
					branch_hand[k] = h
					branch_energy[k] = 0.0
					grabbed_once = true
					vr_rig.pulse(h, 0.5, 0.06)
					fx("grab", branch_tip(k), Color.WHITE, k)
					busy = true
					break
		if touch_t <= 0.0 and vr_rig.hand_speed(h) > 1.0:
			if Vector2(p.x, p.z).length() < 0.75 and p.y < 4.0:
				touch_t = 0.8
				vr_rig.pulse(h, 0.4, 0.05)
				_drop_fruit(randi() % BRANCHES)
			elif Vector2(p.x - BOWL_POS.x, p.z - BOWL_POS.z).length() < BOWL_R + 0.1 and p.y < BOWL_TOP + 0.15:
				touch_t = 0.6
				fx("bowl", BOWL_POS, Color.WHITE, 0)
			elif p.distance_to(NUTMEG_POS + Vector3.UP * (Art.STUMP_TOP + 0.4 * Art.NUTMEG_SCALE)) < 0.5:
				touch_t = 0.8
				vr_rig.pulse(h, 0.3, 0.05)
				fx("nutmeg", NUTMEG_POS + Vector3.UP * Art.STUMP_TOP, Color.WHITE, 0)
		for slot in avatars:
			var cd: float = boop_t.get(slot, 0.0)
			if cd > 0.0:
				boop_t[slot] = cd - delta * 0.5
			elif p.distance_to(basket_top(slot)) < 0.35:
				boop_t[slot] = 1.0
				vr_rig.pulse(h, 0.3, 0.04)
				fx("boop", basket_top(slot), Color.WHITE, int(slot))


func _held_by(h: int) -> int:
	for id in fruits:
		var f: Dictionary = fruits[id]
		if int(f.state) == HELD and int(f.hand) == h:
			return int(id)
	return -1


# --- Fruit --------------------------------------------------------------------------------

## Drop a fruit from under branch k's part of the crown (host / local).
func _drop_fruit(k: int) -> void:
	if fruits.size() >= MAX_FRUIT:
		return
	var a := PI * 0.5 + k * TAU / BRANCHES + randf_range(-0.7, 0.7)
	var pos := Vector3(cos(a), 0.0, sin(a)) * randf_range(1.3, 4.6) + Vector3.UP * DROP_HEIGHT
	var kind := G.shake_kind(shake_rng, need_left(), float(harvest.get("rotten", 0.15)))
	_spawn_drop(k, kind, pos)


## Host: the next fruit in the harvest's schedule ([t, branch, kind, x, z]); its branch shakes first.
func _drop_scheduled(d: Array) -> void:
	var k := int(d[1])
	branch_vel[k] += Vector3(randf_range(-1.0, 1.0), 2.5, randf_range(-1.0, 1.0))
	_spawn_drop(k, int(d[2]), Vector3(float(d[3]), DROP_HEIGHT, float(d[4])))


func _spawn_drop(k: int, kind: int, pos: Vector3) -> void:
	if fruits.size() >= MAX_FRUIT:
		return
	next_fruit += 1
	var f := _make_fruit(next_fruit, kind, pos)
	f.state = HANG
	f.t = HANG_TIME
	fx("drop", pos, Color.WHITE, k)


func _make_fruit(id: int, kind: int, pos: Vector3) -> Dictionary:
	var n := MeshKit.instance(Art.fruit(kind), false)
	add_child(n)
	n.position = pos
	var sh := MeshInstance3D.new()
	sh.mesh = Art.shadow_mesh()
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sh)
	sh.position = Vector3(pos.x, 0.02, pos.z)
	var f := {"node": n, "shadow": sh, "kind": kind, "state": FALL, "vel": Vector3.ZERO, "hand": -1, "t": 0.0, "home": pos}
	fruits[id] = f
	return f


func _free_fruit(id: int) -> void:
	if not fruits.has(id):
		return
	var f: Dictionary = fruits[id]
	(f.node as Node).queue_free()
	(f.shadow as Node).queue_free()
	fruits.erase(id)


## Every machine: spin, wiggle and shadows.
func _animate_fruit_visuals(delta: float) -> void:
	for id in fruits:
		var f: Dictionary = fruits[id]
		var n: Node3D = f.node
		n.rotation.y += delta * 2.5
		var sh: Node3D = f.shadow
		sh.position = Vector3(n.position.x, 0.02, n.position.z)
		var s := clampf(1.3 - n.position.y * 0.15, 0.5, 1.3)
		sh.scale = Vector3(s, 1.0, s)
		sh.visible = n.position.y > 0.25


func _simulate_fruit(delta: float) -> void:
	for id in fruits.keys():
		var f: Dictionary = fruits[id]
		var n: Node3D = f.node
		var st := int(f.state)
		f.t = float(f.t) - delta
		match st:
			HANG:
				var home: Vector3 = f.home
				n.position = home + Vector3(sin(clock * 40.0) * 0.06, 0.0, 0.0)
				if float(f.t) <= 0.0:
					f.state = FALL
			FALL:
				var v: Vector3 = f.vel
				v.y = maxf(v.y - FALL_G * delta, -5.0)
				f.vel = v
				var w: Vector2 = harvest.get("wind", Vector2.ZERO)
				n.position += (v + Vector3(w.x, 0.0, w.y)) * delta  # the breeze (harvestgen.gd plans for it)
				if _in_bowl(n.position):  # fell straight in: it bounces off the fruit pile
					fx("land", n.position, Art.FRUIT_COLORS[int(f.kind)], int(f.kind))
					_free_fruit(int(id))
					continue
			HELD:
				if vr_rig == null:
					f.state = FALL
					continue
				var h := int(f.hand)
				n.position = vr_rig.hand_point(h) + Vector3.UP * 0.05
				if _in_bowl(n.position):
					_score_bowl(int(id), n.position)
					continue
				if float(f.t) < 0.0 and vr_rig.hand_speed(h) > 2.2:
					f.state = THROWN
					f.t = 0.4
					f.vel = vr_rig.hand_velocity(h) * 1.25 + Vector3.UP * 0.6
					sound("whoosh", -6.0)
			THROWN:
				var v: Vector3 = f.vel
				v.y -= 9.0 * delta
				var to := Vector2(BOWL_POS.x - n.position.x, BOWL_POS.z - n.position.z)
				if v.y < 0.0 and to.length() < 1.6 and n.position.y > BOWL_TOP:  # a friendly nudge into the bowl
					v.x += to.x * 4.0 * delta
					v.z += to.y * 4.0 * delta
				f.vel = v
				n.position += v * delta
				if _in_bowl(n.position):
					_score_bowl(int(id), n.position)
					continue
		if not fruits.has(id):
			continue
		st = int(f.state)
		if st == FALL or st == THROWN:
			if _try_catch(int(id), f):
				continue
			if n.position.y < 0.12 or Vector2(n.position.x, n.position.z).length() > ARENA + 4.0:
				fx("land", Vector3(n.position.x, 0.1, n.position.z), Art.FRUIT_COLORS[int(f.kind)], int(f.kind))
				_free_fruit(int(id))


func _in_bowl(p: Vector3) -> bool:
	return Vector2(p.x - BOWL_POS.x, p.z - BOWL_POS.z).length() < BOWL_R - 0.05 and p.y < BOWL_TOP + 0.15 and p.y > BOWL_TOP - 0.5


## A basket or a glove caught it?
func _try_catch(id: int, f: Dictionary) -> bool:
	var n: Node3D = f.node
	var p := n.position
	var rotten := int(f.kind) == Art.ROTTEN
	for slot in avatars:
		var top := basket_top(int(slot))
		if Vector2(p.x - top.x, p.z - top.z).length() < 0.6 and p.y < top.y + 0.35 and p.y > top.y - 0.35:
			if rotten:
				rotten_caught += 1
				fx("splat", top, Art.FRUIT_COLORS[Art.ROTTEN], int(slot))
			else:
				_add_score(1, int(slot), top, Art.FRUIT_COLORS[int(f.kind)])
				_count_fruit(int(f.kind), top)
			_free_fruit(id)
			return true
	if vr_rig != null and (int(f.state) == FALL or float(f.t) < 0.0):
		var h := vr_rig.touching_any(p, 0.3)
		if h >= 0 and not branch_hand.has(h) and _held_by(h) < 0:
			if rotten:
				vr_rig.pulse(h, 0.8, 0.12)
				fx("splat", p, Art.FRUIT_COLORS[Art.ROTTEN], 0)
				_free_fruit(id)
			else:
				vr_rig.pulse(h, 0.5, 0.06)
				f.state = HELD
				f.hand = h
				f.t = 0.3
				fx("grab", p, Art.FRUIT_COLORS[int(f.kind)], -1)
				hints.hint("vr_bowl", "Throw it in the BOWL!", {"to": "vr"})
			return true
	return false


func _score_bowl(id: int, p: Vector3) -> void:
	var f: Dictionary = fruits[id]
	var h := int(f.hand)
	if vr_rig != null and h >= 0:
		vr_rig.pulse(h, 0.7, 0.1)
	dunks += 1
	_free_fruit(id)
	net.state_set("bowl", int(net.state_get("bowl", 0)) + 1)
	_add_score(2, 0, Vector3(BOWL_POS.x, BOWL_TOP + 0.2, BOWL_POS.z), Art.FRUIT_COLORS[int(f.kind)])
	_count_fruit(int(f.kind), Vector3(BOWL_POS.x, BOWL_TOP + 0.2, BOWL_POS.z))


func _add_score(amount: int, by: int, pos: Vector3, color: Color) -> void:
	combo += 1
	combo_t = 1.5
	total_caught += 1
	caught_round += 1
	net.state_set("caught", total_caught)
	awards.add(by, "score", amount)
	var score := int(net.state_get("score", 0)) + amount
	net.state_set("score", score)
	fx("catch" if amount == 1 else "dunk", pos, color, by, combo)
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)


## Draw the round's fruit piled up in the bowl (every machine).
func _set_pile(count: int) -> void:
	in_bowl = count
	var want := mini(count, 14)
	while bowl_pile.size() < want:
		var i := bowl_pile.size()
		var m := MeshKit.instance(Art.fruit(i % 4), false)
		var a := i * 2.4
		var r := 0.5 * sqrt(float(i % 7 + 1) / 7.0)
		m.position = Vector3(cos(a) * r, BOWL_TOP + 0.05 + (i / 7) * 0.2, sin(a) * r)
		bowl.add_child(m)
		bowl_pile.append(m)
		_bounce(m, 1.5)
	while bowl_pile.size() > want:
		var m: MeshInstance3D = bowl_pile.pop_back()
		m.queue_free()


# --- Nutmeg's dishes and the orchard ---------------------------------------------------------

## The current dish's recipe ([apples, oranges, pears, plums]; empty past the last dish). Every machine.
func current_need() -> Array:
	var dishes: Array = harvest.get("dishes", [])
	var d := int(net.state_get("dish", 0))
	return (dishes[d] as Array)[1] if d < dishes.size() else [0, 0, 0, 0]


## How many more of each fruit the dish needs.
func need_left() -> Array:
	var need := current_need()
	var got: Array = net.state_get("got", [0, 0, 0, 0])
	var out := []
	for k in G.GOOD:
		out.append(maxi(0, int(need[k]) - int(got[k] if k < got.size() else 0)))
	return out


## Host: a good fruit was caught or dunked: does Nutmeg's dish need it?
func _count_fruit(kind: int, pos: Vector3) -> void:
	if kind < 0 or kind >= G.GOOD or int(need_left()[kind]) <= 0:
		return
	var got: Array = (net.state_get("got", [0, 0, 0, 0]) as Array).duplicate()
	got[kind] = int(got[kind]) + 1
	net.state_set("got", got)
	fx("need", pos, Art.FRUIT_COLORS[kind], kind)
	for k in G.GOOD:
		if int(need_left()[k]) > 0:
			return
	_dish_done()


## Host: the dish is ready! A bonus, Nutmeg hops, and she asks for the next one.
func _dish_done() -> void:
	dishes_done += 1
	save.data.dishes = int(save.data.dishes) + 1
	save.mark_dirty()
	var bonus := 5
	var score := int(net.state_get("score", 0)) + bonus
	net.state_set("score", score)
	if score > int(save.data["best"]):
		save.data["best"] = score
		net.state_set("best", score)
	fx("dish", NUTMEG_POS + Vector3.UP * 1.2, Color(1.0, 0.85, 0.3), dishes_done)
	net.state_set("got", [0, 0, 0, 0])
	net.state_set("dish", int(net.state_get("dish", 0)) + 1)
	print("Fruit Catch dish %d done at %.1f s" % [dishes_done, round_clock])


## Host: the round's tree joins the orchard (one finished dish is enough). Returns true when planted.
func _plant_tree() -> bool:
	if dishes_done <= 0 or harvest.is_empty():
		return false
	var first: Array = (harvest.dishes as Array)[0]
	var kind := int(G.DISH_MAIN[int(first[0])])
	if kind < 0:
		kind = 0
	var list: Array = save.data.orchard
	list.append([kind, int(save.data.days), bool(harvest.daily), dishes_done])
	while list.size() > G.ORCHARD_KEEP:
		list.pop_front()
	save.data.trees = int(save.data.trees) + 1
	if harvest.daily:
		save.data.daily = Seeded.today()
	save.save_now()
	net.state_set("orchard", list.duplicate(true))
	return true


## Every machine: the orchard round the park (trees grow a stage each play-day).
func _build_orchard(list: Array) -> void:
	if orchard == null:
		return
	for c in orchard.get_children():
		c.queue_free()
	var days := int(net.state_get("days", 1))
	for i in mini(list.size(), G.ORCHARD_SLOTS):
		var e: Array = list[i]
		var t := MeshKit.instance(Art.orchard_tree(int(e[0]), G.tree_stage(int(e[1]), days), bool(e[2])))
		t.position = G.orchard_slot(i)
		t.rotation.y = i * 2.1
		orchard.add_child(t)
		if orchard_count >= 0 and i >= orchard_count:
			_bounce(t, 1.8)  # a new tree pops up
	orchard_count = list.size()


## Every machine: the dish's fruit pictures and counts on one HUD.
func _refresh_recipe_row(slot: int) -> void:
	var row: HBoxContainer = recipe_rows.get(slot)
	if row == null or not is_instance_valid(row):
		return
	for c in row.get_children():
		c.queue_free()
	var dishes: Array = harvest.get("dishes", [])
	var d := int(net.state_get("dish", 0))
	var card := row.get_parent() as Control
	card.visible = d < dishes.size()
	if not card.visible:
		return
	var dish := int((dishes[d] as Array)[0])
	row.add_child(StoryCard.picture(G.DISH_PICS[dish], 56.0, _dish_color(dish)))
	var need := current_need()
	var got: Array = net.state_get("got", [0, 0, 0, 0])
	for k in G.GOOD:
		if int(need[k]) <= 0:
			continue
		row.add_child(StoryCard.picture(G.KIND_PICS[k], 44.0, Art.FRUIT_COLORS[k]))
		var done := int(got[k]) >= int(need[k])
		row.add_child(UiKit.label("%d/%d" % [mini(int(got[k]), int(need[k])), int(need[k])], "number", "gold" if done else null))


## Every machine: the recipe on the sign's lower board (big and world-locked: the VR player reads it too).
func _refresh_sign_recipe() -> void:
	if sign_recipe == null:
		return
	for c in sign_recipe.get_children():
		c.queue_free()
	var need := current_need()
	var got: Array = net.state_get("got", [0, 0, 0, 0])
	var kinds: Array = []
	for k in G.GOOD:
		if int(need[k]) > 0:
			kinds.append(k)
	var cols := mini(kinds.size(), 2)  # up to 2 x 2 on the board
	var rows := (kinds.size() + 1) / 2
	var w := 1.3 / maxf(1.0, cols)
	var hh := 0.46 / maxf(1.0, rows)
	var sc := 1.0 if rows == 1 else 0.62
	for i in kinds.size():
		var k: int = kinds[i]
		var x := -0.65 + w * (i % cols + 0.5)
		var y := 0.23 - hh * (i / cols + 0.5)
		var fm := MeshKit.instance(Art.fruit(k), false)
		fm.position = Vector3(x - 0.2 * sc, y, 0.06)
		fm.scale = Vector3.ONE * sc
		sign_recipe.add_child(fm)
		var done := int(got[k]) >= int(need[k])
		var l := UiKit.label3d("%d/%d" % [mini(int(got[k]), int(need[k])), int(need[k])], 0.18 * sc, "gold" if done else "text", true)
		l.position = Vector3(x + 0.14 * sc, y, 0.05)
		sign_recipe.add_child(l)


func _dish_color(dish: int) -> Color:
	var k := int(G.DISH_MAIN[dish])
	return Art.FRUIT_COLORS[k] if k >= 0 else Color(1.0, 0.8, 0.3)


func _dish_name(d: int) -> String:
	var dishes: Array = harvest.get("dishes", [])
	return G.DISH_NAMES[int((dishes[d] as Array)[0])] if d < dishes.size() else ""


## Every machine: Nutmeg says something (beats wait their turn so none is missed).
func _story(line: String, pic: String, color: Color) -> void:
	story_queue.append([line, pic, color])


func _update_story(delta: float) -> void:
	story_t -= delta
	if story_t > 0.0 or story_queue.is_empty():
		return
	var b: Array = story_queue.pop_front()
	story_t = 2.6
	var opts := {"who": "NUTMEG", "line": b[0], "pic": b[1], "color": b[2], "duration": 2.5}
	StoryCard.show(_all_huds(), opts)
	if vr_rig != null:
		StoryCard.show_vr(self, vr_rig.camera, opts)


## Every machine: Nutmeg bobs on her stump, hops when a dish is ready and looks at whoever's nearest.
func _animate_nutmeg(delta: float) -> void:
	if nutmeg == null:
		return
	var body := nutmeg.get_node_or_null("Body") as Node3D
	if body == null:
		return
	nutmeg_hop = maxf(0.0, nutmeg_hop - delta)
	var hop := absf(sin(nutmeg_hop * 9.0)) * 0.35 * minf(1.0, nutmeg_hop)
	body.position.y = Art.STUMP_TOP + hop + absf(sin(clock * 2.2)) * 0.02
	body.rotation.z = sin(clock * 1.3) * 0.06


# --- Effects (host / local play them and send them; the TV machine plays the same) ---------

func fx(kind: String, pos: Vector3, color: Color, n: int = -1, m: int = 0) -> void:
	match kind:
		"catch":
			_burst(pos, color, 14, 3.0)
			HudKit.score(self, pos + Vector3.UP * 0.3, 1, {"color": color, "size": 1.4})
			sfx.play_at("coin", pos, 0.0, 1.0 + minf(m, 8) * 0.07)
			if baskets.has(n):
				_bounce(baskets[n], 1.6)
			if avatars.has(n):
				Creatures.anim(avatars[n]).play("cheer", 0.5)
		"dunk":
			_burst(pos, color, 22, 4.0)
			_burst(pos, Color(0.5, 0.85, 1.0), 10, 3.0)
			HudKit.score(self, pos + Vector3.UP * 0.4, 2, {"color": "gold", "size": 2.0})
			sfx.play_at("kaching", pos, 0.0, 1.0 + minf(m, 8) * 0.05)
			_wobble(bowl, 0.12)
		"splat":
			_burst(pos, color, 20, 3.5)
			sfx.play_at("spit", pos, 2.0, 0.7)
			sfx.play_at("splash", pos, -4.0, 1.4)
			if avatars.has(n):
				dizzy[n] = 1.5
				Creatures.anim(avatars[n]).hurt(Color(0.5, 0.35, 0.1), Vector3.UP)
		"land":
			_burst(pos, color, 8, 2.0)
			sfx.play_at("spit" if n == Art.ROTTEN else "bounce", pos, -8.0, 0.8 + randf() * 0.3)
		"drop":
			if crown != null:
				_wobble(crown, 0.03)
			sfx.play_at("pop", pos, -10.0, 0.7 + randf() * 0.4)
		"grab":
			sfx.play_at("pickup", pos, -4.0, 1.2)
		"snap":
			sfx.play_at("boing", pos, -2.0, 0.8)
		"bowl":
			_wobble(bowl, 0.1)
			sfx.play_at("boing", pos, -4.0, 0.6)
		"need":  # a fruit for Nutmeg's dish: a sparkle and a rising chime
			_burst(pos + Vector3.UP * 0.2, Color(1.0, 0.9, 0.4), 8, 2.0)
			sfx.play_at("pickup", pos, -6.0, 1.3 + n * 0.1)
		"dish":  # a dish is ready: Nutmeg hops, confetti
			nutmeg_hop = 1.2
			_burst(pos, Color(1.0, 0.85, 0.3), 26, 4.0)
			_burst(pos, Color(1.0, 0.5, 0.6), 14, 3.0)
			HudKit.score(self, pos + Vector3.UP * 0.3, 5, {"color": "gold", "size": 2.0})
			sfx.play_at("kaching", pos, 0.0, 1.2)
			sound("fanfare", -8.0)
		"nutmeg":  # the giant patted Nutmeg
			nutmeg_hop = 0.6
			sfx.play_at("boing", pos, -4.0, 1.8)
		"boop":
			sfx.play_at("boing", pos, -2.0, 1.5)
			if avatars.has(n):
				Creatures.anim(avatars[n]).play("jump", 0.5)
	if net.mode == "host":
		net.event("fx", [kind, pos, color, n, m])


func _burst(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = ResCache.get_or_make("fruit_catch_bit_%s" % color.to_html(false), func() -> Resource:
		var bm := SphereMesh.new()
		bm.radius = 0.05
		bm.height = 0.1
		bm.radial_segments = 6
		bm.rings = 3
		bm.material = MeshKit.material(color, 0.4)
		return bm)
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(0.9).timeout.connect(p.queue_free)


## Squash-and-stretch pop.
func _bounce(n: Node3D, amount: float) -> void:
	var tw := n.create_tween()
	n.scale = Vector3(amount, 1.0 / amount, amount)
	tw.tween_property(n, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _wobble(n: Node3D, amount: float) -> void:
	var tw := n.create_tween()
	tw.tween_property(n, "rotation:z", amount, 0.08)
	tw.tween_property(n, "rotation:z", -amount * 0.6, 0.12)
	tw.tween_property(n, "rotation:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	var kinds := PackedByteArray()
	for id in fruits:
		var f: Dictionary = fruits[id]
		ids.append(int(id))
		pos.append((f.node as Node3D).position)
		kinds.append(int(f.kind))
	var offs := PackedVector3Array(branch_off)
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
	return [pose, ids, pos, kinds, offs, av_slots, av_pos, av_yaw]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 8:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var av_slots: PackedByteArray = s[5]
	var av_pos: PackedVector3Array = s[6]
	var av_yaw: PackedFloat32Array = s[7]
	for i in av_slots.size():
		var slot: int = av_slots[i]
		if avatars.has(slot) and not party.is_local(slot):
			if not net_target.has(slot):
				(avatars[slot] as Node3D).position = av_pos[i]
			net_target[slot] = [av_pos[i], av_yaw[i]]
	var ids: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var kinds: PackedByteArray = s[3]
	var offs: PackedVector3Array = s[4]
	for k in mini(offs.size(), BRANCHES):
		branch_off[k] = offs[k]
	var seen := {}
	for i in ids.size():
		seen[ids[i]] = true
		if not fruits.has(ids[i]):
			_make_fruit(ids[i], kinds[i], pos[i])
		var n: Node3D = (fruits[ids[i]] as Dictionary).node
		n.position = n.position.lerp(pos[i], 0.6)
	for id in fruits.keys():
		if not seen.has(id):
			_free_fruit(int(id))


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"fx":
			fx(String(args[0]), args[1], args[2], int(args[3]), int(args[4]))
