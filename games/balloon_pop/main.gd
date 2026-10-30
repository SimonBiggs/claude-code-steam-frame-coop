extends Node3D
## BALLOON POP: colourful balloons float up from the grass all around everyone. Pop them!
## VR player: punch a balloon, or touch it with the right glove and squeeze the trigger. A gentle
## touch boops it away (it wobbles). TV players: run into balloons, jump (A) for the high ones.
## Gold balloons are worth 3, grey grumpy ones take a point away. One team score, 2 minutes, then a
## big confetti finish and the next round starts by itself.
## STORY (story.gd): POPPY'S FAIR. The wind blew Poppy the balloon seller's balloons all over the park;
## every point is a ticket that builds the ride Poppy is making round the park (fair.gd). A finished ride
## stays (saved) and the team picks the next one by popping one of two big balloons carrying the rides.
## Each ride brings its own special balloons (ice, twins, grumpies, giants, rockets...).
## DEPTH: rounds come from a seed (wavegen.gd: rings, lines, rainbows, hearts, stacks; pop a whole set
## for a bonus), every balloon proven reachable by both the VR player and the TV players; three goal
## stars per round; TODAY'S SKY first each day (the same sky and balloons on every machine).
## TELEMETRY: one RUN line per round (and on quit) via core/telemetry.gd.
## Built on the shared engine like games/engine_template (party, split view, camera rig, VR rig,
## state store, awards, hud kit). Host / local simulate; the TV machine mirrors snapshots.

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
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")
const Balloon := preload("res://games/balloon_pop/balloon.gd")
const WaveGen := preload("res://games/balloon_pop/wavegen.gd")
const Story := preload("res://games/balloon_pop/story.gd")
const Fair := preload("res://games/balloon_pop/fair.gd")

const GAME_ID := "balloon_pop"
const ARENA := WaveGen.ARENA
const SPEED := WaveGen.TV_SPEED
const JUMP_V := 7.5
const GRAVITY := 18.0
const MAX_BALLOONS := 24  # on screen at once (wavegen.gd keeps the reachable ones under its CAP)
const TOP := 6.0  # balloons that float this high fly away
const POINTS := WaveGen.POINTS
const ICE_TIME := 4.0
const ICE_SLOW := 0.3
const HIT_CD := 0.35  # a giant can't be hit again this soon
const PICK_WAIT := 20.0
const PRACTICE_WAIT := 9.0
const CHOICE_SPOTS: Array[Vector3] = [Vector3(-1.1, 1.25, 0.7), Vector3(1.1, 1.25, 0.7)]
const LOOKS: Array[String] = ["knight", "mage", "archer", "bard", "pirate", "chef", "astronaut"]

var round_time := 120.0  ## seconds per round (bots shorten it before adding the game)
var results_wait := 12.0  ## seconds of confetti + results before the next round starts by itself
var fresh_save := false  ## bots: start a brand-new fair
var need_scale := 1.0  ## bots: smaller rides so a short round finishes one

# --- The networking contract ---
var net: Node
var ready_to_play := false
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

var avatars := {}  # slot -> Node3D: TV players (every machine)
var last_pos := {}  # slot -> Vector3, for walk animation
var net_target := {}  # slot -> [pos, yaw]: where another machine's player is (smoothed towards every frame)
var flat_host := false  # this machine hosts without VR: slot 0 is a pad / keyboard player here, like local play
var vel_y := {}  # slot -> float: local jump speed
var cams := {}  # slot -> CameraRig
var group_cam: CameraRig
var huds := {}  # slot -> UiKit root (-1 = shared view)
var score_labels := {}  # slot -> Label
var timers := {}  # slot -> HudKit.TimerPill
var star_icons := {}  # hud slot -> [3 icons]
var ride_pics := {}  # hud slot -> [picture holder, bar, ride shown]
var join_prompt: Control
var vr_avatar: VrRig.Avatar  # TV machine: the VR player
var vr_label: Label3D  # host: score on the back of the left glove
var vr_banner: Node3D
var vr_story: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var fair: Fair
var balloons := {}  # id -> Balloon node
var next_id := 0
var time_left := 0.0
var results_t := 0.0
var total_popped := 0
var popped_by_vr := 0
var popped_by_tv := 0
var boop_cd := {}  # id -> float: a balloon was just booped (no repeat boops every frame)
var hit_cd := {}  # id -> float: a giant was just hit
# --- Host: this round ---
var round_def := {}  # wavegen.gd round
var round_desc := {}  # {k: story / daily, ride, seed}
var run := {}  # this round's numbers for telemetry
var elapsed := 0.0
var spawn_i := 0
var daily_due := false
var last_ride := ""
var phase_t := 0.0  # seconds in the practice / pick phase
var ice_t := 0.0
var set_left := {}  # set id -> balloons not popped yet
var set_broken := {}  # set id -> true: one floated away
var set_seen := {}  # set id -> true: its first balloon is out


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
		save.data.world = Seeded.fresh_seed()  # this family's own fair rounds
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
		vr_rig.bounds = Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0)
		add_child(vr_rig)
		vr_rig.place(Vector3(WaveGen.VR_HOME.x, 0.0, WaveGen.VR_HOME.y), 0.0)
		vr_label = UiKit.label3d("", 0.035, "gold", true)
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
		group_cam.group_min_distance = 9.0
		add_child(group_cam)
		group_cam.follow_group([], -60.0, 0.0, 0.0)
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
		_publish_fair()
		print("Poppy's fair: %d rides built, building %s (%d tickets), daily %s (world %d)" % [Story.rides_built(save.data.rides),
			String(save.data.cur), int(save.data.fill), daily_due, int(save.data.world)])
		_start_round(true)
	if vr_rig != null:
		hints.hint("vr_pop", "Punch or squeeze!", {"to": "vr", "icon": "star"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	if mode != "client" and int(save.data.rounds) == 0 and Story.rides_built(save.data.rides) == 0:
		_story(_poppy("The wind took my balloons!"))
	print("Balloon Pop: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA + 14.0
	disc.bottom_radius = ARENA + 14.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.45, 0.78, 0.36))
	ground.position.y = -0.1
	add_child(ground)
	# A bright ring of fence-like bushes, trees outside (beyond Poppy's fair), flowers inside: one draw call per kind.
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 16, Vector3.ZERO, ARENA + 12.0, ARENA + 8.0, 0.8, 1.3, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 18, Vector3.ZERO, ARENA + 2.5, ARENA + 0.8, 0.8, 1.2, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, ARENA - 0.5, 1.0, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 5))
	fair = Fair.new()
	fair.name = "Fair"
	fair.sfx = sfx
	add_child(fair)


# --- HUD ------------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	# Every view: the team score with the round's three goal stars, and Poppy's ride with its tickets.
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var col := UiKit.vbox()
	card.add_child(col)
	var row := UiKit.hbox()
	col.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	var l := UiKit.label("0", "number")
	l.custom_minimum_size.x = 64.0
	row.add_child(l)
	score_labels[slot] = l
	var icons: Array = []
	for k in 3:  # the round's goal stars (dim until earned)
		var ic := UiKit.icon("star", Color(0.4, 0.4, 0.5), 34.0)
		row.add_child(ic)
		icons.append(ic)
	star_icons[slot] = icons
	var row2 := UiKit.hbox()  # the ride Poppy is building and how many tickets it has
	col.add_child(row2)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(44.0, 44.0)
	row2.add_child(holder)
	var bar := UiKit.bar("xp", 150.0, 18.0, Color(1.0, 0.45, 0.7))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(bar)
	ride_pics[slot] = [holder, bar, ""]
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})
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
		if is_instance_valid(l) and l.text != str(score):
			l.text = str(score)
			UiKit.pop_in(l)
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	var g: Array = net.state_get("goal", [])
	var got := WaveGen.stars(score, g) if g.size() == 3 else 0
	if vr_label != null:
		vr_label.text = "POP %d %s" % [score, "*".repeat(got)]
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
	var fs: Dictionary = net.state_get("fair", {})
	var cur := String(fs.get("cur", ""))
	for slot in ride_pics:
		var rp: Array = ride_pics[slot]
		var holder: Control = rp[0]
		if not is_instance_valid(holder):
			continue
		if String(rp[2]) != cur:
			rp[2] = cur
			for c in holder.get_children():
				c.queue_free()
			if cur != "":
				var r := Story.ride(cur)
				holder.add_child(StoryCard.picture(String(r.pic), 40.0, r.color))
		var bar: UiKit.Bar = rp[1]
		bar.visible = cur != ""
		bar.set_value(float(fs.get("fill", 0)), maxf(1.0, float(fs.get("need", 1))))


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


func _banner(title: String, sub: String = "", dur: float = 1.8) -> void:
	HudKit.banner(_all_huds(), title, sub, {"duration": dur})
	if vr_rig != null:
		HudKit.vr_banner(self, vr_rig.camera, title, sub, {"duration": dur, "sound": "", "distance": 2.0})  # 3.2 m: just behind the story card


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 1.2
		c.pitch = -0.3
		add_child(c)
		c.follow(a, 6.5, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("jump", "A = JUMP", {"to": slot, "button": "A"})
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
	vel_y.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	star_icons.erase(slot)
	ride_pics.erase(slot)
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
	a.position = Vector3(-3.0 + slot, 0.0, -1.0)
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.35, 0.18)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


func _refresh_group() -> void:
	if group_cam != null:
		group_cam.set_targets(avatars.values())


## Local TV players run with the left stick (camera relative) and jump with A. Their own movement
## is instant on their machine; the TV machine sends positions to the host 30 times a second.
var send_t := 0.0

func _move_local_players(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "play")) != "results"
	for slot in party.local_slots():
		if not avatars.has(slot):
			continue
		var a: Node3D = avatars[slot]
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		var p := a.position
		if mv != Vector2.ZERO:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			p += dir * SPEED * delta
			Creatures.anim(a).face(dir)
		var vy: float = vel_y.get(slot, 0.0)
		if p.y <= 0.001 and playing and party.just_pressed(slot, "a"):
			vy = JUMP_V
			Creatures.anim(a).play("jump")
			sound("jump", -4.0, randf_range(0.95, 1.1))
		vy -= GRAVITY * delta
		p.y = maxf(0.0, p.y + vy * delta)
		if p.y <= 0.0:
			vy = 0.0
		vel_y[slot] = vy
		var flat := Vector2(p.x, p.z).limit_length(ARENA)
		a.position = Vector3(flat.x, p.y, flat.y)
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)


func _animate_avatars(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.3 and a.position.y < 0.05 else 0.0)
		last_pos[slot] = a.position


## Host: a player on another machine moved.
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot) and not party.is_local(slot):
		if not net_target.has(slot):
			(avatars[slot] as Node3D).position = pos
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


## Host: one machine left. core/party.gd frees just its seats (player_left removes their avatars).
func on_machine_left(peer: int) -> void:
	for slot in party.slots_of(peer):
		net_target.erase(slot)
		vel_y.erase(slot)


func on_request(_slot: int, action: String, _args: Array) -> void:
	if action == "next_round" and String(net.state_get("phase", "")) == "results" and results_t > 2.0:
		_start_round(false)


func on_pause_changed(paused: bool, by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_paused(self, vr_rig.camera, "", {"width": 1.1, "distance": 2.2})
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
		"score", "best", "goal":
			_refresh_hud()
		"fair":
			if fair != null and value is Dictionary:
				fair.apply(value)
			_refresh_hud()
		"sky":
			if sky != null and String(value) != "":
				sky.set_preset(String(value), 2.0)
		"ice":
			if int(value) > 0:
				_banner("BRRR!", "", 1.2)
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
		"round":
			if int(value) <= 1:
				_banner("BALLOON POP", "Pop them all!", 2.5)
		"phase":
			var ph := String(value)
			if ph == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
				if ph == "play":
					_banner("TODAY'S SKY!" if bool(net.state_get("daily", false)) else "GO!", "", 1.4)
					sound("go")


# --- Rounds -------------------------------------------------------------------------------

## Host: a new round. The first of a session starts with practice balloons; when Poppy's ride is
## finished the team picks the next ride (two big balloons) before the waves come.
func _start_round(practice: bool) -> void:
	for id in balloons.keys():
		(balloons[id] as Node).queue_free()
	balloons.clear()
	awards.reset()
	round_def = {}
	time_left = round_time
	phase_t = 0.0
	ice_t = 0.0
	net.state_set("score", 0)
	net.state_set("goal", [])
	net.state_set("daily", false)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	if String(save.data.cur) == "":
		_start_pick()
	elif practice:
		net.state_set("phase", "practice")
		_practice_balloons()
	else:
		_start_play()


## Teach by doing: one low balloon right in front of every player at the start of a session.
func _practice_balloons() -> void:
	if vr_rig != null:
		var f := vr_rig.head_forward()
		_spawn(Balloon.NORMAL, vr_rig.head_position() + f * 0.6 + Vector3.DOWN * 0.5, 0.05, 0)
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * 1.5
		_spawn(Balloon.NORMAL, Vector3(a.position.x, 0.6, a.position.z) + off, 0.05, int(slot) + 1)


## Host: two big balloons carry the rides on offer; pop one to build it (nobody does: the first one).
func _start_pick() -> void:
	var offers := Story.offers(int(save.data.world), save.data.rides, last_ride)
	if offers.size() < 2:
		_plant(String(offers[0]) if not offers.is_empty() else Story.FIRST_RIDE)
		_start_play()
		return
	net.state_set("offers", offers)
	phase_t = 0.0
	for k in 2:
		next_id += 1
		var b := _make_balloon(next_id, WaveGen.CHOICE, CHOICE_SPOTS[k], k, String(offers[k]))
		b.rise = 0.0
	net.state_set("phase", "pick")
	_story(_poppy(Story.PICK_LINE))


## Host: a ride balloon was popped (k = 0 / 1): build it, the other one floats away, the waves come.
func _pick(k: int) -> void:
	var offers: Array = net.state_get("offers", [])
	if String(net.state_get("phase", "")) != "pick" or offers.is_empty():
		return
	var id := String(offers[clampi(k, 0, offers.size() - 1)])
	for bid in balloons.keys():
		var b: Node3D = balloons[bid]
		if int(b.get("kind")) == WaveGen.CHOICE:
			b.set("rise", 2.5)  # off it goes
	_plant(id)
	_start_play()


func _plant(id: String) -> void:
	save.data.cur = id
	save.data.fill = mini(int(save.data.get("carry", 0)), _need() / 2)
	save.data.carry = 0
	save.mark_dirty()
	_publish_fair()
	net.event("planted", [Story.ride_index(id)])
	planted(Story.ride_index(id))


## Every machine: a ride was just chosen (its spot bounces, Poppy cheers).
func planted(i: int) -> void:
	if fair != null:
		fair.cheer(i)
	sound("power_up", -4.0)


func _need() -> int:
	return maxi(3, int(Story.ride_need(Story.rides_built(save.data.rides)) * need_scale))


## Host: tell every machine what the fair looks like.
func _publish_fair() -> void:
	var fs := {"rides": (save.data.rides as Dictionary).duplicate(), "cur": String(save.data.cur),
		"fill": int(save.data.fill), "need": _need()}
	net.state_set("fair", fs)
	if fair != null and net.mode != "client":
		fair.apply(fs)  # (state_set may not echo to the host itself)
	_refresh_hud()


## Host: tickets the team popped go into Poppy's ride; a finished ride stays for good and the next
## round starts with the ride pick.
func _grow(pts: int) -> void:
	if pts <= 0:
		return
	if String(save.data.cur) == "":
		save.data.carry = int(save.data.get("carry", 0)) + pts  # ride finished this round: a head start for the next
		return
	save.data.fill = int(save.data.fill) + pts
	if int(save.data.fill) >= _need():
		var id := String(save.data.cur)
		var rides: Dictionary = save.data.rides
		rides[id] = int(rides.get(id, 0)) + 1
		last_ride = id
		save.data.cur = ""
		save.data.fill = 0
		run["ride_done"] = id
		var r := Story.ride(id)
		_story(_poppy(String(r.done), String(r.pic), r.color))
	save.mark_dirty()
	_publish_fair()


## Host: the waves come: this round's balloons are made from a seed (TODAY'S SKY first each day).
func _start_play() -> void:
	var players := maxi(1, party.player_count() + (1 if vr_rig != null else 0))
	var sp: Dictionary
	if daily_due:
		daily_due = false
		sp = Story.daily_spec(players, round_time)
		round_desc = {"k": "daily", "ride": String(save.data.cur), "seed": Story.daily_seed()}
		net.state_set("sky", String(sp.sky))
		net.state_set("daily", true)
	else:
		var met := {}
		for k in save.data.met:
			met[int(k)] = true
		var cur := String(save.data.cur)
		sp = Story.spec(cur, Story.rides_built(save.data.rides), met, players, round_time)
		round_desc = {"k": "story", "ride": cur, "seed": Seeded.derive(int(save.data.world), "r%d" % int(save.data.rounds))}
		net.state_set("sky", "day")
	if sky != null and net.mode != "client":
		sky.set_preset(String(net.state_get("sky", "day")), 2.0)
	var t0 := Time.get_ticks_usec()
	round_def = WaveGen.generate(int(round_desc.seed), sp)
	run = {"gen_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01), "popped": 0, "vr_popped": 0, "grumpy": 0,
		"escaped": 0, "skipped": 0, "sets": 0, "sets_done": 0, "giants": 0, "ice": 0}
	elapsed = 0.0
	spawn_i = 0
	set_left.clear()
	set_broken.clear()
	set_seen.clear()
	for i in (round_def.sets as Array).size():
		set_left[i] = int(round_def.sets[i][2])
	time_left = float(round_def.time)
	net.state_set("goal", round_def.goal)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	var r := Story.ride(String(round_desc.ride))
	if round_desc.k == "story" and int(save.data.fill) == 0:
		_story(_poppy(String(r.intro), String(r.pic), r.color))
	print("Balloon Pop round: %s %s seed %d, %d balloons, %d sets, goal %s (%.1f ms)" % [round_desc.k, round_desc.ride,
		int(round_desc.seed), (round_def.spawns as Array).size(), (round_def.sets as Array).size(), str(round_def.goal), float(run.gen_ms)])


func _end_round() -> void:
	var score := int(net.state_get("score", 0))
	var g: Array = round_def.get("goal", [1, 2, 3])
	var st := WaveGen.stars(score, g)
	var daily := String(round_desc.get("k", "")) == "daily"
	if score > int(save.data["best"]):
		save.data["best"] = score
		net.state_set("best", score)
	if not daily:
		var best_st: Dictionary = save.data.stars
		var key := String(round_desc.get("ride", ""))
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
	if int(run.get("sets_done", 0)) > 0:
		stats.append(["SETS", str(int(run.sets_done))])
	var data := awards.results({"title": "%d POPS!" % score, "subtitle": ["Keep popping!", "One star!", "Two stars!", "THREE STARS!"][st],
		"style": "victory", "stats": stats, "score_format": "%d POPS", "max_awards": 3, "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	_telemetry("round", score, st)
	finale()
	if not run.has("ride_done"):
		_story(_poppy(Story.CHEERS[int(save.data.rounds) % Story.CHEERS.size()] if st > 0 else "Nearly! Again!"))
	round_def = {}


func _exit_tree() -> void:
	if ready_to_play and net != null and net.mode != "client" and String(net.state_get("phase", "")) == "play" and not round_def.is_empty():
		var score := int(net.state_get("score", 0))
		_telemetry("quit", score, WaveGen.stars(score, round_def.get("goal", [])))


## One RUN line per round (or quit mid-round): how the family really plays (balance).
func _telemetry(end: String, score: int, st: int) -> void:
	if round_def.is_empty() or net.mode == "client":
		return
	var info := run.duplicate()
	info.merge({"end": end, "mode": net.mode, "flat_host": flat_host, "vr": vr_rig != null,
		"players": party.player_count() + (1 if vr_rig != null else 0), "kind": String(round_desc.get("k", "")),
		"ride": String(round_desc.get("ride", "")), "seed": int(round_desc.get("seed", 0)), "level": int(round_def.get("level", 0)),
		"time": int(round_def.get("time", 0)), "played_s": int(elapsed), "score": score, "max": int(round_def.get("max", 0)),
		"goal": round_def.get("goal", []), "stars": st, "balloons": (round_def.spawns as Array).size(),
		"sky": String(net.state_get("sky", "day")), "rides": Story.rides_built(save.data.rides), "fill": int(save.data.fill),
		"need": _need()}, true)
	Telemetry.run(GAME_ID, info)


## A story beat: Poppy (or a ride / balloon picture) and a few words, on every machine.
func _story(beat: Dictionary) -> void:
	if net.mode != "client":
		net.event("story", [beat.get("who", ""), beat.get("line", ""), beat.get("pic", ""), (beat.get("color", Story.POPPY_COLOR) as Color).to_html()])
	show_story(beat)


func show_story(beat: Dictionary) -> void:
	StoryCard.show(_all_huds(), beat)
	if vr_rig != null:
		if vr_story != null and is_instance_valid(vr_story):
			vr_story.queue_free()
		vr_story = StoryCard.show_vr(self, vr_rig.camera, beat)


func _poppy(line: String, pic: String = "seller", color: Color = Story.POPPY_COLOR) -> Dictionary:
	return {"who": "POPPY", "line": line, "pic": pic, "color": color, "duration": 3.5}


## Host: the first time the family meets a special balloon, Poppy shows it (saved).
func _meet(key: String, line: String, color: Color) -> void:
	var met: Dictionary = save.data.met
	if met.has(key):
		return
	met[key] = true
	save.mark_dirty()
	_story({"who": "POPPY", "line": line, "pic": "balloon", "color": color, "duration": 3.0})


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
		split.set_shared(false)
	if music != null and String(net.state_get("phase", "")) == "play":
		music.play_mood("party")


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- Game loop --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if split != null:
		_move_local_players(delta)
	_follow_remote(delta)
	_animate_avatars(delta)
	if net.mode == "client":
		return
	var phase := String(net.state_get("phase", ""))
	if phase == "results":
		results_t += delta
		if results_t > results_wait:
			_start_round(false)  # play again by itself
		return
	if phase == "practice":
		phase_t += delta
		_simulate(delta)
		if phase_t > PRACTICE_WAIT or (phase_t > 1.0 and balloons.is_empty()):
			_start_play()
		return
	if phase == "pick":
		phase_t += delta
		_simulate(delta)
		if phase_t > PICK_WAIT and String(net.state_get("phase", "")) == "pick":
			_pick(0)
		return
	if round_def.is_empty():
		return
	elapsed += delta
	time_left = float(round_def.time) - elapsed
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		var secs := maxi(0, int(ceil(time_left)))
		net.state_set("time", secs)
		if secs <= 5 and secs > 0:
			sound("tick", -2.0, 1.0 + (5 - secs) * 0.08)
	if time_left <= 0.0:
		_end_round()
		return
	var spawns: Array = round_def.spawns
	while spawn_i < spawns.size() and float(spawns[spawn_i][0]) <= elapsed:
		_spawn_planned(spawns[spawn_i])
		spawn_i += 1
	_simulate(delta)


## Host: the round's next balloon [t, kind, x, z, y0, rise, colour, set] (wavegen.gd proved it fair).
func _spawn_planned(s: Array) -> void:
	var set_id := int(s[7])
	if balloons.size() >= MAX_BALLOONS:
		run["skipped"] = int(run.get("skipped", 0)) + 1
		if set_id >= 0:
			set_broken[set_id] = true
		return
	var kind := int(s[1])
	var b := _spawn(kind, Vector3(float(s[2]), float(s[4]), float(s[3])), float(s[5]), int(s[6]))
	b.set_id = set_id
	if set_id >= 0 and not set_seen.has(set_id):
		set_seen[set_id] = true
		run["sets"] = int(run.get("sets", 0)) + 1
		_meet("set", Story.SET_LINE, Balloon.COLORS[int(s[6])])
	if Story.KIND_LINES.has(kind):
		_meet(str(kind), String(Story.KIND_LINES[kind]), Story.KIND_COLORS.get(kind, Color.WHITE))


func _spawn(kind: int, pos: Vector3, rise: float, col: int) -> Balloon:
	next_id += 1
	var b := _make_balloon(next_id, kind, pos, col)
	b.rise = rise
	sound_at("bounce", pos, -10.0, 1.6 if kind != WaveGen.GIANT else 0.8)
	return b


func _make_balloon(id: int, kind: int, pos: Vector3, col: int = -1, ride: String = "") -> Balloon:
	var b := Balloon.new()
	b.setup(id, kind, col, ride)
	add_child(b)
	b.position = pos
	balloons[id] = b
	return b


## Host / local: float, drift, react to gloves, and pop when touched by a player.
func _simulate(delta: float) -> void:
	for cd in [boop_cd, hit_cd]:
		var d: Dictionary = cd
		for id in d.keys():
			d[id] = float(d[id]) - delta
			if float(d[id]) <= 0.0:
				d.erase(id)
	if ice_t > 0.0:
		ice_t -= delta
	var slow := ICE_SLOW if ice_t > 0.0 else 1.0
	var t := Time.get_ticks_msec() * 0.001
	for id in balloons.keys():
		if not balloons.has(id):
			continue  # popped this frame (a choice pick lets the other one go)
		var b: Balloon = balloons[id]
		var p := b.position
		p.y += b.rise * delta * (slow if b.kind != WaveGen.CHOICE else 1.0)
		if b.kind == WaveGen.CHOICE and b.rise == 0.0:
			p.y = CHOICE_SPOTS[0].y + sin(t * 1.5 + b.phase) * 0.08
		else:
			p.x += sin(t * 0.7 + b.phase) * 0.15 * delta
		p += b.push * delta
		b.push = b.push * exp(-2.5 * delta)
		var flat := Vector2(p.x, p.z).limit_length(ARENA + 1.0)
		p = Vector3(flat.x, maxf(0.3, p.y), flat.y)
		b.position = p
		if p.y > TOP:
			if b.kind != WaveGen.CHOICE:
				run["escaped"] = int(run.get("escaped", 0)) + 1
			if b.set_id >= 0:
				set_broken[b.set_id] = true
			balloons.erase(id)
			b.queue_free()
			continue
		var by := _check_touch(int(id), b)
		if by >= 0:
			_hit(int(id), by)


## Who touched the balloon hard enough to pop it (slot), or -1. A gentle VR touch boops it away instead.
func _check_touch(id: int, b: Balloon) -> int:
	var c := b.position
	var r := Balloon.reach_of(b.kind, b.hp)
	if hit_cd.has(id):
		return -1
	if vr_rig != null:
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			var hand: int = h
			var hp := vr_rig.hand_point(hand)
			if hp.distance_to(c) > r + 0.1:
				continue
			if vr_rig.hand_speed(hand) > 1.5:
				return 0  # punch!
			if hand == VrRig.RIGHT and vr_rig.trigger_value() > 0.6:
				return 0  # squeeze!
			if not boop_cd.has(id):
				boop_cd[id] = 0.4
				var away := c - hp
				away.y = maxf(away.y, 0.0) + 0.2
				b.push = away.normalized() * 1.4
				b.boop()
				vr_rig.pulse(hand, 0.25, 0.05)
				sound_at("bounce", c, -4.0, randf_range(0.8, 1.0))
				net.event("boop", [id])
	var extra := r - Balloon.RADIUS
	for slot in avatars:
		var a: Node3D = avatars[slot]
		if Vector2(a.position.x - c.x, a.position.z - c.z).length() < 0.45 + r and c.y > a.position.y - 0.3 - extra and c.y < a.position.y + 1.75 + extra:
			return int(slot)
	return -1


## A balloon was hit: a giant loses a hit (and bounces away from whoever hit it), anything else pops.
func _hit(id: int, by: int) -> void:
	var b: Balloon = balloons[id]
	if b.hp > 1:
		b.hp -= 1
		hit_cd[id] = HIT_CD
		var from := vr_rig.head_position() if by == 0 and vr_rig != null else ((avatars[by] as Node3D).position if avatars.has(by) else b.position + Vector3.DOWN)
		var away := b.position - from
		away.y = 0.3
		b.push = away.normalized() * 2.0
		b.hit(b.hp)
		if by == 0 and vr_rig != null:
			vr_rig.pulse(VrRig.RIGHT, 0.6, 0.08)
		elif party.is_local(by):
			party.rumble(by, 0.3, 0.5, 0.12)
		hit_fx(id, b.hp)
		return
	_pop(id, by)


## Every machine: a giant took a hit (it shrinks a little, boing).
func hit_fx(id: int, left: int) -> void:
	if balloons.has(id):
		var b: Balloon = balloons[id]
		b.hit(left)
		sfx.play_at("boing", b.position, 0.0, 0.7 + (3 - left) * 0.15)
		HudKit.popup(self, b.position + Vector3.UP * 0.8, str(left), {"style": "gold", "size": 1.3})
	if net.mode != "client":
		net.event("hit", [id, left])


func _pop(id: int, by: int) -> void:
	var b: Balloon = balloons[id]
	balloons.erase(id)
	var kind := b.kind
	var col: Color = b.color
	var pos := b.position
	var set_id := b.set_id
	var ci := b.col
	b.queue_free()
	if kind == WaveGen.CHOICE:
		pop_fx(pos, col, kind, by)
		_pick(ci)
		return
	total_popped += 1
	net.state_set("popped", total_popped)
	if by == 0 and vr_rig != null:
		popped_by_vr += 1
		run["vr_popped"] = int(run.get("vr_popped", 0)) + 1
		var hand := vr_rig.touching_any(pos, 0.6)
		vr_rig.pulse(hand if hand >= 0 else VrRig.RIGHT, 0.8 if kind != WaveGen.GRUMPY else 0.4, 0.1)
	else:
		popped_by_tv += 1
		if party.is_local(by):
			party.rumble(by, 0.4, 0.6, 0.15)
	if String(net.state_get("phase", "")) == "practice":
		pop_fx(pos, col, kind, by)
		return
	var pts: int = POINTS[kind]
	var score := maxi(0, int(net.state_get("score", 0)) + pts)
	net.state_set("score", score)
	run["popped"] = int(run.get("popped", 0)) + 1
	awards.add(by, "score", float(pts))
	_grow(pts)
	match kind:
		WaveGen.GRUMPY:
			run["grumpy"] = int(run.get("grumpy", 0)) + 1
		WaveGen.GIANT:
			run["giants"] = int(run.get("giants", 0)) + 1
			save.data.giants = int(save.data.giants) + 1
		WaveGen.ICE:  # brrr: everything floats up slowly for a bit
			run["ice"] = int(run.get("ice", 0)) + 1
			ice_t = ICE_TIME
			net.state_set("ice", int(net.state_get("ice", 0)) + 1)
		WaveGen.TWINS:  # three little ones pop out
			for k in WaveGen.TWIN_MINIS:
				var a := k * TAU / WaveGen.TWIN_MINIS
				var m := _spawn(WaveGen.MINI, pos + Vector3(cos(a) * 0.5, 0.1, sin(a) * 0.5), 0.3, ci)
				m.push = Vector3(cos(a), 0.4, sin(a)) * 1.2
	if set_id >= 0 and set_left.has(set_id):
		set_left[set_id] = int(set_left[set_id]) - 1
		if int(set_left[set_id]) <= 0 and not set_broken.has(set_id):
			_set_done(pos)
	pop_fx(pos, col, kind, by)


## Host: every balloon of a set was popped before one floated away: bonus!
func _set_done(pos: Vector3) -> void:
	run["sets_done"] = int(run.get("sets_done", 0)) + 1
	save.data.sets = int(save.data.sets) + 1
	save.mark_dirty()
	net.state_set("score", int(net.state_get("score", 0)) + WaveGen.SET_BONUS)
	_grow(WaveGen.SET_BONUS)
	set_fx(pos)


## Every machine: a whole set popped (a big gold "ALL!" and a little confetti).
func set_fx(pos: Vector3) -> void:
	HudKit.popup(self, pos + Vector3.UP * 0.8, "ALL! +%d" % WaveGen.SET_BONUS, {"style": "gold", "size": 1.6})
	_confetti(pos + Vector3.UP * 0.5, 30, 1.5)
	sfx.play_at("coin", pos, 0.0, 1.3)
	if net.mode != "client":
		net.event("set", [pos])


## Burst, points and sound on every machine (the host sends it as an event).
func pop_fx(pos: Vector3, color: Color, kind: int, by: int) -> void:
	var big := kind == WaveGen.GOLD or kind == WaveGen.GIANT or kind == WaveGen.CHOICE
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 34 if kind == WaveGen.GIANT else (22 if big else 14)
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0 if kind == WaveGen.GIANT else 4.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.mesh = ResCache.get_or_make("bp_bit_%s" % color.to_html(false), func() -> Resource:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.09, 0.02)
		bm.material = MeshKit.material(color, 1.0)
		return bm)
	add_child(p)
	p.position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	var pts: int = POINTS[kind] if kind < POINTS.size() else 0
	if kind == WaveGen.CHOICE:
		pass
	elif pts > 0:
		HudKit.score(self, pos + Vector3.UP * 0.3, pts, {"color": "gold" if kind == WaveGen.GOLD else color, "size": 1.4 if pts > 1 else 1.1})
	else:
		HudKit.popup(self, pos + Vector3.UP * 0.3, "-1", {"style": "bad", "size": 1.1})
	sfx.play_at("pop", pos, 2.0, randf_range(0.85, 1.25) * (0.6 if kind == WaveGen.GIANT else (1.4 if kind == WaveGen.MINI else 1.0)))
	match kind:
		WaveGen.GOLD:
			sfx.play_at("coin", pos, 0.0, 1.0)
		WaveGen.GRUMPY:
			sfx.play_at("boing", pos, -2.0, 0.6)
		WaveGen.ICE:
			sfx.play_at("power_up", pos, -4.0, 0.6)
		WaveGen.GIANT, WaveGen.CHOICE:
			sfx.play_at("fanfare", pos, -4.0, 1.0)
			_confetti(pos, 30, 1.5)
	if by >= 0 and avatars.has(by):
		Creatures.anim(avatars[by]).play("cheer" if kind != WaveGen.GRUMPY else "hurt", 0.5)
	if net.mode != "client":
		net.event("pop", [pos, color, kind, by])


## The big finish: every balloon left pops, and confetti rains everywhere (every machine).
func finale() -> void:
	for id in balloons.keys():
		var b: Node3D = balloons[id]
		_confetti(b.position, 10, 0.8)
		b.queue_free()
	balloons.clear()
	var centers: Array[Vector3] = [Vector3(0.0, 4.0, 0.0)]
	if vr_rig != null:
		centers.append(vr_rig.head_position() + Vector3.UP * 1.5)
	for slot in avatars:
		centers.append((avatars[slot] as Node3D).position + Vector3.UP * 3.0)
	for c in centers:
		_confetti(c, 60, 3.0)
	sound("cheer", 0.0)
	if net.mode != "client":
		net.event("finale", [])


func _confetti(pos: Vector3, amount: int, life: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.9
	p.spread = 180.0
	p.gravity = Vector3(0.0, -2.0, 0.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.damping_min = 1.0
	p.damping_max = 2.0
	# Shared resources: the finale makes ~20 of these at once (no per-burst allocations).
	p.color_initial_ramp = ResCache.get_or_make("bp_confetti_ramp_v1", func() -> Resource:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
		g.colors = PackedColorArray(Balloon.COLORS.slice(0, 6))
		return g)
	p.mesh = ResCache.get_or_make("bp_confetti_mesh_v1", func() -> Resource:
		var qm := QuadMesh.new()
		qm.size = Vector2(0.08, 0.05)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		qm.material = m
		return qm)
	add_child(p)
	p.position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


func sound_at(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(sound_name, pos, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: VR pose + balloons (id, kind, position, colour / choice index, hits left) + players.
func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var kinds := PackedByteArray()
	var pos := PackedVector3Array()
	var cols := PackedByteArray()
	for id in balloons:
		var b: Balloon = balloons[id]
		ids.append(int(id))
		kinds.append(b.kind)
		pos.append(b.position)
		cols.append(b.col | (b.hp << 4))
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	# Every player avatar (slot, position, yaw): each machine sees the other machines' players.
	var slots := PackedByteArray()
	var apos := PackedVector3Array()
	var ayaw := PackedFloat32Array()
	for slot in avatars:
		var a: Node3D = avatars[slot]
		slots.append(int(slot))
		apos.append(a.position)
		ayaw.append(a.rotation.y)
	return [pose, ids, kinds, pos, slots, apos, ayaw, cols]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()  # only when the host has a VR player (not on a flat host)
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var slots: PackedByteArray = s[4]
	var apos: PackedVector3Array = s[5]
	var ayaw: PackedFloat32Array = s[6]
	for i in slots.size():
		var slot: int = slots[i]
		if avatars.has(slot) and not party.is_local(slot):
			if not net_target.has(slot):
				(avatars[slot] as Node3D).position = apos[i]
			net_target[slot] = [apos[i], ayaw[i]]
	var ids: PackedInt32Array = s[1]
	var kinds: PackedByteArray = s[2]
	var pos: PackedVector3Array = s[3]
	var cols: PackedByteArray = s[7] if s.size() > 7 else PackedByteArray()
	var offers: Array = net.state_get("offers", [])
	var seen := {}
	for i in ids.size():
		seen[ids[i]] = true
		var c := int(cols[i]) & 15 if i < cols.size() else -1
		var b: Balloon
		if balloons.has(ids[i]):
			b = balloons[ids[i]]
		else:
			var ride := String(offers[c]) if kinds[i] == WaveGen.CHOICE and c >= 0 and c < offers.size() else ""
			b = _make_balloon(ids[i], kinds[i], pos[i], c, ride)
		if i < cols.size() and b.kind == WaveGen.GIANT and b.hp != int(cols[i]) >> 4:
			b.hit(int(cols[i]) >> 4)
		b.position = b.position.lerp(pos[i], 0.5)
	for id in balloons.keys():
		if not seen.has(id):
			(balloons[id] as Node).queue_free()
			balloons.erase(id)


## TV machine: the VR player as seen from here, plus the little window into their view.
func _make_vr_avatar() -> void:
	vr_avatar = VrRig.Avatar.new()
	add_child(vr_avatar)
	if split != null:
		split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"pop":
			var id_pos: Vector3 = args[0]
			_remove_near(id_pos)
			pop_fx(args[0], args[1], int(args[2]), int(args[3]))
		"boop":
			var id: int = int(args[0])
			if balloons.has(id):
				(balloons[id] as Balloon).boop()
				sound_at("bounce", (balloons[id] as Node3D).position, -4.0, 0.9)
		"hit":
			hit_fx(int(args[0]), int(args[1]))
		"set":
			set_fx(args[0])
		"planted":
			planted(int(args[0]))
		"story":
			show_story({"who": args[0], "line": args[1], "pic": args[2], "color": Color.html(String(args[3])), "duration": 3.5})
		"finale":
			finale()


## TV machine: hide the popped balloon right away instead of waiting for the next snapshot.
func _remove_near(p: Vector3) -> void:
	for id in balloons.keys():
		var b: Node3D = balloons[id]
		if b.position.distance_to(p) < 0.45:
			b.queue_free()
			balloons.erase(id)
			return
