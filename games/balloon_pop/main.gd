extends Node3D
## BALLOON POP: colourful balloons float up from the grass all around everyone. Pop them!
## VR player: punch a balloon, or touch it with the right glove and squeeze the trigger. A gentle
## touch boops it away (it wobbles). TV players: run into balloons, jump (A) for the high ones.
## Gold balloons are worth 3, grey grumpy ones take a point away. One team score, 2 minutes, then a
## big confetti finish and the next round starts by itself.
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
const Balloon := preload("res://games/balloon_pop/balloon.gd")

const GAME_ID := "balloon_pop"
const ARENA := 7.0
const SPEED := 5.0
const JUMP_V := 7.5
const GRAVITY := 18.0
const MAX_BALLOONS := 16
const TOP := 6.0  # balloons that float this high fly away
const POINTS: Array[int] = [1, 3, -1]  # NORMAL, GOLD, GRUMPY
const LOOKS: Array[String] = ["knight", "mage", "archer", "bard", "pirate", "chef", "astronaut"]

var round_time := 120.0  ## seconds per round (bots shorten it before adding the game)
var results_wait := 12.0  ## seconds of confetti + results before the next round starts by itself

# --- The networking contract ---
var net: Node
var ready_to_play := false
# --- Engine modules (names core/ looks for) ---
var party: Party
## Any number of TV machines (TV, Steam Decks) may join (core/net.gd multi_machine).
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
var vel_y := {}  # slot -> float: local jump speed
var cams := {}  # slot -> CameraRig
var group_cam: CameraRig
var huds := {}  # slot -> UiKit root (-1 = shared view)
var score_labels := {}  # slot -> Label
var timers := {}  # slot -> HudKit.TimerPill
var join_prompt: Control
var vr_avatar: VrRig.Avatar  # TV machine: the VR player
var vr_label: Label3D  # host: score on the back of the left glove
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var balloons := {}  # id -> Balloon node
var next_id := 0
var spawn_t := 0.0
var send_t := 0.0
var time_left := 0.0
var results_t := 0.0
var total_popped := 0
var popped_by_vr := 0
var popped_by_tv := 0
var boop_cd := {}  # id -> float: a balloon was just booped (no repeat boops every frame)


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
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0)
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, 2.0), 0.0)
		vr_label = UiKit.label3d("", 0.035, "gold", true)
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
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	awards.set_player(0, "GIANT" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		_start_round()
	if vr_rig != null:
		hints.hint("vr_pop", "Punch or squeeze!", {"to": "vr", "icon": "star"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
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
	# A bright ring of fence-like bushes, trees outside, flowers inside: one draw call per kind.
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 16, Vector3.ZERO, ARENA + 10.0, ARENA + 3.0, 0.8, 1.3, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 18, Vector3.ZERO, ARENA + 2.5, ARENA + 0.8, 0.8, 1.2, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, ARENA - 0.5, 1.0, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 5))


# --- HUD ------------------------------------------------------------------------------------

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
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		join_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE)
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
			l.text = str(score)
			UiKit.pop_in(l)
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if vr_label != null:
		vr_label.text = "POP %d" % score


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
	vel_y.erase(slot)
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


func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot):
		var a: Node3D = avatars[slot]
		a.position = pos
		a.rotation.y = yaw


func on_request(_slot: int, action: String, _args: Array) -> void:
	if action == "next_round" and String(net.state_get("phase", "")) == "results" and results_t > 2.0:
		_start_round()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", "", {"width": 1.1, "distance": 2.2})
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
			tv_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		(tv_banner.find_child("Why", true, false) as Label).text = "by %s" % party.name_of(by_slot)
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"score", "best":
			_refresh_hud()
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
		"round":
			HudKit.banner(_all_huds(), "BALLOON POP", "Pop them all!", {"duration": 2.5})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "BALLOON POP", "", {"duration": 2.5, "sound": "", "distance": 2.5})
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds ---------------------------------------------------------------------------------

func _start_round() -> void:
	for id in balloons.keys():
		(balloons[id] as Node).queue_free()
	balloons.clear()
	awards.reset()
	time_left = round_time
	spawn_t = 0.0
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	_practice_balloons()


## Teach by doing: one low balloon right in front of every player at the start of each round.
func _practice_balloons() -> void:
	if vr_rig != null:
		var f := vr_rig.head_forward()
		_spawn(Balloon.NORMAL, vr_rig.head_position() + f * 0.6 + Vector3.DOWN * 0.5, 0.15)
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * 1.5
		_spawn(Balloon.NORMAL, Vector3(a.position.x, 0.6, a.position.z) + off, 0.15)


func _end_round() -> void:
	var score := int(net.state_get("score", 0))
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)
	var data := awards.results({"title": "HOORAY!", "subtitle": "%d balloons popped!" % score,
		"style": "victory", "stats": [["BEST", str(int(net.state_get("best", 0)))]], "score_format": "%d POPS"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	finale()


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
	if net.mode != "host":
		_move_local_players(delta)
	_animate_avatars(delta)
	if net.mode == "client":
		return
	if results_showing():
		results_t += delta
		if results_t > results_wait:
			_start_round()  # play again by itself
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		var secs := maxi(0, int(ceil(time_left)))
		net.state_set("time", secs)
		if secs <= 5 and secs > 0:
			sound("tick", -2.0, 1.0 + (5 - secs) * 0.08)
	if time_left <= 0.0:
		_end_round()
		return
	spawn_t -= delta
	if spawn_t <= 0.0 and balloons.size() < MAX_BALLOONS:
		spawn_t = randf_range(0.35, 0.7)
		_spawn_random()
	_simulate(delta)


func _spawn_random() -> void:
	var r := randf()
	var kind := Balloon.GOLD if r < 0.12 else (Balloon.GRUMPY if r < 0.27 else Balloon.NORMAL)
	var center := Vector3.ZERO
	var near := false
	# Plenty of balloons pop up right around the players, the rest anywhere in the park.
	var pick := randf()
	if vr_rig != null and pick < 0.4:
		center = vr_rig.head_position()
		near = true
	elif not avatars.is_empty() and pick < 0.75:
		var keys := avatars.keys()
		center = (avatars[keys[randi() % keys.size()]] as Node3D).position
		near = true
	var pos: Vector3
	if near:
		var ang := randf() * TAU
		pos = Vector3(center.x, 0.0, center.z) + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(0.7, 2.2)
	else:
		var ang2 := randf() * TAU
		pos = Vector3(cos(ang2), 0.0, sin(ang2)) * randf_range(0.5, ARENA - 0.5)
	var flat := Vector2(pos.x, pos.z).limit_length(ARENA - 0.3)
	_spawn(kind, Vector3(flat.x, 0.35, flat.y), randf_range(0.3, 0.55))


func _spawn(kind: int, pos: Vector3, rise: float) -> void:
	next_id += 1
	var b := _make_balloon(next_id, kind, pos)
	b.rise = rise
	sound_at("bounce", pos, -10.0, 1.6)


func _make_balloon(id: int, kind: int, pos: Vector3) -> Node3D:
	var b := Balloon.new()
	b.setup(id, kind)
	add_child(b)
	b.position = pos
	balloons[id] = b
	return b


## Host / local: float, drift, react to gloves, and pop when touched by a player.
func _simulate(delta: float) -> void:
	for id in boop_cd.keys():
		boop_cd[id] = float(boop_cd[id]) - delta
		if float(boop_cd[id]) <= 0.0:
			boop_cd.erase(id)
	var t := Time.get_ticks_msec() * 0.001
	for id in balloons.keys():
		var b: Node3D = balloons[id]
		var p := b.position
		p.y += float(b.get("rise")) * delta
		p.x += sin(t * 0.7 + float(b.get("phase"))) * 0.15 * delta
		var push: Vector3 = b.get("push")
		p += push * delta
		b.set("push", push * exp(-2.5 * delta))
		var flat := Vector2(p.x, p.z).limit_length(ARENA + 1.0)
		p = Vector3(flat.x, maxf(0.3, p.y), flat.y)
		b.position = p
		if p.y > TOP:
			balloons.erase(id)
			b.queue_free()
			continue
		var by := _check_touch(int(id), b)
		if by >= 0:
			_pop(int(id), by)


## Who pops the balloon (slot), or -1. A gentle VR touch boops it away instead.
func _check_touch(id: int, b: Node3D) -> int:
	var c := b.position
	if vr_rig != null:
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			var hand: int = h
			var hp := vr_rig.hand_point(hand)
			if hp.distance_to(c) > Balloon.RADIUS + 0.1:
				continue
			if vr_rig.hand_speed(hand) > 1.5:
				return 0  # punch!
			if hand == VrRig.RIGHT and vr_rig.trigger_value() > 0.6:
				return 0  # squeeze!
			if not boop_cd.has(id):
				boop_cd[id] = 0.4
				var away := c - hp
				away.y = maxf(away.y, 0.0) + 0.2
				b.set("push", away.normalized() * 1.4)
				b.call("boop")
				vr_rig.pulse(hand, 0.25, 0.05)
				sound_at("bounce", c, -4.0, randf_range(0.8, 1.0))
				net.event("boop", [id])
	for slot in avatars:
		var a: Node3D = avatars[slot]
		if Vector2(a.position.x - c.x, a.position.z - c.z).length() < 0.75 and c.y > a.position.y - 0.3 and c.y < a.position.y + 1.75:
			return int(slot)
	return -1


func _pop(id: int, by: int) -> void:
	var b: Node3D = balloons[id]
	balloons.erase(id)
	var kind: int = b.get("kind")
	var col: Color = b.get("color")
	var pos := b.position
	b.queue_free()
	var pts: int = POINTS[kind]
	var score := maxi(0, int(net.state_get("score", 0)) + pts)
	net.state_set("score", score)
	total_popped += 1
	net.state_set("popped", total_popped)
	if by == 0 and vr_rig != null:
		popped_by_vr += 1
		var hand := vr_rig.touching_any(pos, 0.6)
		vr_rig.pulse(hand if hand >= 0 else VrRig.RIGHT, 0.8 if kind != Balloon.GRUMPY else 0.4, 0.1)
	else:
		popped_by_tv += 1
		if party.is_local(by):
			party.rumble(by, 0.4, 0.6, 0.15)
	awards.add(by, "score", float(pts))
	pop_fx(pos, col, kind, by)


## Burst, points and sound on every machine (the host sends it as an event).
func pop_fx(pos: Vector3, color: Color, kind: int, by: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 22 if kind == Balloon.GOLD else 14
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
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
	var pts: int = POINTS[kind]
	if pts > 0:
		HudKit.score(self, pos + Vector3.UP * 0.3, pts, {"color": "gold" if kind == Balloon.GOLD else color, "size": 1.4 if kind == Balloon.GOLD else 1.1})
	else:
		HudKit.popup(self, pos + Vector3.UP * 0.3, "-1", {"style": "bad", "size": 1.1})
	sfx.play_at("pop", pos, 2.0, randf_range(0.85, 1.25))
	if kind == Balloon.GOLD:
		sfx.play_at("coin", pos, 0.0, 1.0)
	elif kind == Balloon.GRUMPY:
		sfx.play_at("boing", pos, -2.0, 0.6)
	if by > 0 and avatars.has(by):
		Creatures.anim(avatars[by]).play("cheer" if kind != Balloon.GRUMPY else "hurt", 0.5)
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

## Host, 30 Hz: VR pose + balloons (id, kind, position).
func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var kinds := PackedByteArray()
	var pos := PackedVector3Array()
	for id in balloons:
		var b: Node3D = balloons[id]
		ids.append(int(id))
		kinds.append(int(b.get("kind")))
		pos.append(b.position)
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	return [pose, ids, kinds, pos]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 4:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	var ids: PackedInt32Array = s[1]
	var kinds: PackedByteArray = s[2]
	var pos: PackedVector3Array = s[3]
	var seen := {}
	for i in ids.size():
		seen[ids[i]] = true
		var b: Node3D = balloons[ids[i]] if balloons.has(ids[i]) else _make_balloon(ids[i], kinds[i], pos[i])
		b.position = b.position.lerp(pos[i], 0.5)
	for id in balloons.keys():
		if not seen.has(id):
			(balloons[id] as Node).queue_free()
			balloons.erase(id)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"pop":
			var id_pos: Vector3 = args[0]
			_remove_near(id_pos)
			pop_fx(args[0], args[1], int(args[2]), int(args[3]))
		"boop":
			var id: int = int(args[0])
			if balloons.has(id):
				(balloons[id] as Node3D).call("boop")
				sound_at("bounce", (balloons[id] as Node3D).position, -4.0, 0.9)
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
