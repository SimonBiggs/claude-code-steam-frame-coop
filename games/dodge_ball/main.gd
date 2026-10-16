extends Node3D
## SOFT DODGEBALL: the VR player is a friendly giant on a stage who throws big squishy balls at the
## runners on the court below. A runner who is hit turns into a puff of feathers and pops back 3 s
## later. Runners pick balls up (run over them) and throw them back (A) at the target on the giant's
## belly. Giant scores for hits, runners score for belly hits. Rounds of ROUND_TIME s, then results
## and an automatic next round.
## Modes: VR giant + TV runners (host / TV machine), VR alone (two CPU runners fill in), and no VR
## (a CPU giant on the stage). The host simulates the balls; TV runners move locally.

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const World := preload("res://games/dodge_ball/world.gd")

const STAGE_H := 0.9  # the giant's stage height
const STAGE_FRONT := -4.6  # z of the stage's front edge (the stage is behind it, towards -Z)
const GIANT_FEET := Vector3(0.0, STAGE_H, -6.4)
const TRAY_Z := -5.25
const TRAY_Y := STAGE_H + 0.95
const COURT_X := 6.3
const COURT_Z := Vector2(-3.9, 6.3)  # runners' z range
const WALL_X := 7.3
const WALL_Z := Vector2(-9.0, 7.3)
const BALL_R := 0.2
const BALLS := 6
const GRAV := 9.0
const SPEED := 4.8
const OUT_TIME := 3.0
const SAFE_TIME := 1.5  # blinking after popping back: can't be hit
const GIANT := 100  # holder / thrower code for the giant (runners use their slot numbers)
const CPU_IDS: Array[int] = [10, 11]
const LOOKS: Array[String] = ["knight", "mage", "archer", "bard", "pirate", "chef", "astronaut"]
const BALL_COLORS: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.75, 0.2), Color(0.35, 0.85, 0.45),
	Color(0.35, 0.65, 1.0), Color(0.85, 0.45, 1.0), Color(1.0, 0.55, 0.85)]

var round_time := 120.0  ## seconds per round (bots shorten it)
var results_wait := 12.0  ## seconds the results stay up before the next round starts by itself

# --- Networking contract ---
var net: Node
var ready_to_play := false
var players: Array = []
# --- Engine modules ---
var party: Party
var split: SplitView
var vr_rig: VrRig
var sfx: Node
var music: Node
var awards: Awards
var sky: SkyKit.SkyRig
var world: World

var avatars := {}  # runner id (party slot or CPU id) -> Node3D
var last_pos := {}
var vels := {}  # runner id -> smoothed ground velocity (the giant leads its throws a little)
var g_vel := Vector3.ZERO  # host: the giant's smoothed head velocity (runners lead their throws)
var cams := {}
var group_cam: CameraRig
var huds := {}
var score_labels := {}  # slot -> [runners Label, giant Label]
var timers := {}
var join_prompt: Control
var tv_banner: Control
var vr_banner: Node3D
var results_ui: Control
var vr_results: Node
var vr_board: Label3D  # host VR: the big scoreboard far across the court

var balls: Array = []  # of Ball
var out := {}  # runner id -> seconds left (host); client: id -> true
var safe := {}  # runner id -> seconds of blinking left
var cpu := {}  # CPU runner id -> {"goal": Vector3, "t": float, "hold": float}
var send_t := 0.0
var time_left := 0.0
var results_t := 0.0
var clock := 0.0

# The giant (host decides; every machine draws it)
var g_head := GIANT_FEET + Vector3(0.0, 1.55, 0.0)
var g_yaw := PI
var g_hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var g_cpu := false  # no VR player: the computer is the giant
var cpu_g := {"t": 2.5, "ball": -1, "phase": 0, "aim": -1, "sway": 0.0}
var _snap_giant: PackedVector3Array = PackedVector3Array()


class Ball:
	var node: Node3D
	var mesh: MeshInstance3D
	var blob: MeshInstance3D
	var vel := Vector3.ZERO
	var holder := -1  # -1 free, GIANT = the giant's hand, else a runner id
	var thrower := -1
	var danger := false  # thrown and not yet touched the floor
	var tray := -1  # tray slot it rests in
	var hop := 0.0  # seconds left of a magic hop back to the tray
	var rest := 0.0  # seconds lying still on the court
	var target := Vector3.ZERO  # TV machine: snapshot position
	var squish := 0.0


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
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("party")
	music.prepare(["victory"])
	awards = Awards.new()
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	if VrRig.wanted(mode):
		Engine.physics_ticks_per_second = 90
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-3.2, -8.4, 6.4, 3.6)
		vr_rig.floor_height = STAGE_H
		add_child(vr_rig)
		vr_rig.place(GIANT_FEET, PI)
	g_cpu = mode != "client" and vr_rig == null
	world = World.new()
	add_child(world)
	world.build(self, vr_rig != null)
	world.show_giant_head(vr_rig == null)
	for i in BALLS:
		_make_ball(i)
	if vr_rig != null:
		vr_board = UiKit.label3d("", 0.9, "text", true)
		vr_board.outline_size = 26
		vr_board.position = Vector3(0.0, 4.2, WALL_Z.y + 1.0)
		vr_board.rotation.y = PI  # reads from +Z: turn it to face the giant at -Z
		add_child(vr_board)
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 11.0
		add_child(group_cam)
		group_cam.follow_group([], -35.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
	party.allow_slot0 = mode == "local" and vr_rig == null
	if vr_rig != null:
		awards.set_player(0, "GIANT")
	if mode != "client":
		for i in BALLS:
			_to_tray(balls[i], i)
		_start_round()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Soft Dodgeball: %s mode%s" % [mode, " with a VR giant" if vr_rig != null else ""])


func _make_ball(i: int) -> void:
	var b := Ball.new()
	b.node = Node3D.new()
	b.node.name = "Ball%d" % i
	b.mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	b.mesh.mesh = sm
	b.mesh.material_override = MeshKit.material(BALL_COLORS[i % BALL_COLORS.size()], 0.25)
	b.node.add_child(b.mesh)
	add_child(b.node)
	b.blob = world.make_blob(BALL_R * 1.3)
	add_child(b.blob)
	b.node.position = Vector3(0.0, 0.5, 0.0)
	b.target = b.node.position
	balls.append(b)


# --- HUD ------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.offset_top = 16.0
	var row := UiKit.hbox()
	card.add_child(row)
	row.add_child(UiKit.icon("person", "gold", 34.0))
	var tv := UiKit.label("0", "number", "gold")
	row.add_child(tv)
	row.add_child(UiKit.label("  :  ", "number", "dim"))
	var gl := UiKit.label("0", "number", "bad")
	row.add_child(gl)
	row.add_child(UiKit.label("GIANT", "heading", "bad"))
	score_labels[slot] = [tv, gl]
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		join_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	_refresh_hud()


func _refresh_hud() -> void:
	var tv := int(net.state_get("tv_score", 0))
	var gs := int(net.state_get("giant_score", 0))
	for slot in score_labels:
		var ls: Array = score_labels[slot]
		if is_instance_valid(ls[0]):
			(ls[0] as Label).text = str(tv)
			(ls[1] as Label).text = str(gs)
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if vr_board != null:
		vr_board.text = "YOU %d   THEM %d\n%s" % [gs, tv, HudKit.clock_text(float(net.state_get("time", 0)))]


func _all_huds() -> Array:
	var out_h: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out_h.append(huds[k])
	return out_h


# --- Players --------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.slot = slot
		c.pivot_height = 1.0
		c.pitch = -0.38
		c.yaw = 0.0  # behind the runner, looking at the giant
		add_child(c)
		c.follow(a, 7.0, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
	if slot > 0 or vr_rig == null:
		awards.set_player(slot, party.name_of(slot))
	_refresh_group()
	_refresh_hud()
	sfx.play("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	_drop_held(slot)
	for d in [avatars, cams]:
		var dict: Dictionary = d
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	last_pos.erase(slot)
	out.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	timers.erase(slot)
	_refresh_group()
	_refresh_hud()


func _ensure_avatar(id: int) -> Node3D:
	if avatars.has(id) and is_instance_valid(avatars[id]):
		return avatars[id]
	var col: Color = party.color_of(id) if id < 10 else Color(0.6, 0.6, 0.65)
	var a := Creatures.humanoid({"class": LOOKS[id % LOOKS.size()], "outfit": col, "seed": id})
	a.name = "Runner%d" % id
	add_child(a)
	a.position = Vector3(-3.0 + 1.5 * float(id % 5), 0.0, 3.0)
	HudKit.nameplate(a, party.name_of(id) if id < 10 else "CPU", id if id < 10 else "dim", Creatures.height_of(a) + 0.35, 0.18)
	avatars[id] = a
	last_pos[id] = a.position
	return a


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
		var mv := party.stick(slot, "move") if playing and not out.has(slot) else Vector2.ZERO
		if mv != Vector2.ZERO:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			a.position = _clamp_court(a.position + dir * SPEED * delta)
			Creatures.anim(a).face(dir)
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)
		if playing and (party.just_pressed(slot, "accept") or party.just_pressed(slot, "rt") or party.just_pressed(slot, "x")):
			net.request(slot, "throw")


func _clamp_court(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -COURT_X, COURT_X), 0.0, clampf(p.z, COURT_Z.x, COURT_Z.y))


func _animate_avatars(delta: float) -> void:
	for id in avatars:
		var a: Node3D = avatars[id]
		var prev: Vector3 = last_pos.get(id, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		var vv := (a.position - prev) / maxf(delta, 0.001)
		vels[id] = (vels.get(id, Vector3.ZERO) as Vector3).lerp(vv, 1.0 - exp(-8.0 * delta))
		Creatures.anim(a).walk(v if v > 0.3 else 0.0)
		last_pos[id] = a.position
		var hidden := out.has(id)
		var blink := safe.has(id) and fmod(clock * 8.0, 1.0) < 0.35
		a.visible = not hidden and not blink


func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot):
		var a: Node3D = avatars[slot]
		a.position = _clamp_court(pos)
		a.rotation.y = yaw


func on_request(slot: int, action: String, _args: Array) -> void:
	match action:
		"throw":
			if String(net.state_get("phase", "")) == "play":
				_runner_throw(slot)
		"next_round":
			if String(net.state_get("phase", "")) == "results":
				_start_round()


func on_pause_changed(paused: bool, _by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", "", {"width": 1.1})
			vr_banner.process_mode = Node.PROCESS_MODE_ALWAYS
		elif vr_banner != null and is_instance_valid(vr_banner):
			vr_banner.call("hide_card")
	if split != null:
		if tv_banner == null:
			var ui := UiKit.ui_root(self, 6)
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
			tv_banner = UiKit.panel("accent")
			ui.add_child(tv_banner)
			tv_banner.add_child(UiKit.title("PAUSED"))
			tv_banner.set_anchors_preset(Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)
	if not paused and vr_rig != null:
		vr_rig.guard_trigger()


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"tv_score", "giant_score":
			_refresh_hud()
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
			_refresh_hud()
		"round":
			HudKit.banner(_all_huds(), "DODGE!", "Throw at the belly!", {"duration": 2.5})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "THROW!", "", {"duration": 2.0, "sound": ""})
			sfx.play("whistle", -4.0)
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------

func _start_round() -> void:
	awards.reset()
	time_left = round_time
	out.clear()
	safe.clear()
	for i in balls.size():
		var b: Ball = balls[i]
		b.holder = -1
		_to_tray(b, i)
	net.state_set("tv_score", 0)
	net.state_set("giant_score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	if vr_rig != null:
		vr_rig.recenter()


func _end_round() -> void:
	var tv := int(net.state_get("tv_score", 0))
	var gs := int(net.state_get("giant_score", 0))
	var title := "RUNNERS WIN!" if tv > gs else ("GIANT WINS!" if gs > tv else "A DRAW!")
	var data := awards.results({"title": title, "subtitle": "Runners %d  -  Giant %d" % [tv, gs], "style": "victory",
		"score_format": "%d PTS"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	for i in balls.size():
		var b: Ball = balls[i]
		_drop_ball(b)


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	sfx.play("fanfare", -3.0)
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(huds[-1], data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 1, "next_round"))
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
		music.play_mood("party")
	elif vr_rig != null:
		music.play_mood("party")


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- Game loop -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	clock += delta
	if net.mode != "host":
		_move_local_players(delta)
	if net.mode == "client":
		_client_smooth(delta)
	else:
		_host_tick(delta)
	_animate_avatars(delta)
	world.update_giant(g_head, g_yaw, g_hands, delta)
	for b: Ball in balls:
		b.squish = move_toward(b.squish, 0.0, delta * 4.0)
		var s := sin(b.squish * PI) * 0.35
		b.mesh.scale = Vector3(1.0 + s, 1.0 - s, 1.0 + s)
		var fy := _floor_at(b.node.position)
		b.blob.position = Vector3(b.node.position.x, fy + 0.02, b.node.position.z)
		b.blob.visible = b.node.visible


func _host_tick(delta: float) -> void:
	var playing := not results_showing()
	_update_giant(delta, playing)
	for i in balls.size():
		_ball_physics(balls[i], i, delta)
	if vr_rig != null:
		_vr_hands(delta)
	_update_cpu_runners(delta, playing)
	for id in out.keys():
		out[id] = float(out[id]) - delta
		if float(out[id]) <= 0.0:
			out.erase(id)
			safe[id] = SAFE_TIME
			if avatars.has(id):
				pop_back(id)
	for id in safe.keys():
		safe[id] = float(safe[id]) - delta
		if float(safe[id]) <= 0.0:
			safe.erase(id)
	if not playing:
		results_t += delta
		if results_t > results_wait:
			_start_round()  # play again by itself
		return
	_runner_pickups()
	_runner_hits()
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
		if time_left <= 5.5 and time_left > 0.5:
			sound("tick", -4.0)
	if time_left <= 0.0:
		sound("whistle")
		_end_round()


func _floor_at(p: Vector3) -> float:
	return STAGE_H if p.z < STAGE_FRONT and absf(p.x) < World.STAGE_HALF_W else 0.0


func _fwd() -> Vector3:
	return Vector3(-sin(g_yaw), 0.0, -cos(g_yaw))


## The belly target's centre (every machine).
func target_point() -> Vector3:
	return g_head + Vector3(0.0, -0.68, 0.0) + _fwd() * 0.36


func _torso_center() -> Vector3:
	return g_head + Vector3(0.0, -0.72, 0.0)


func _tray_pos(k: int) -> Vector3:
	return Vector3(-1.0 + 0.4 * float(k), TRAY_Y, TRAY_Z)


func _to_tray(b: Ball, k: int) -> void:
	b.tray = k
	b.vel = Vector3.ZERO
	b.danger = false
	b.hop = 0.0
	b.thrower = -1
	b.rest = 0.0
	b.node.position = _tray_pos(k)


func _free_tray_slot() -> int:
	var used := {}
	for o: Ball in balls:
		if o.tray >= 0:
			used[o.tray] = true
		if o.hop > 0.0:
			used[int(o.rest)] = true  # a hopping ball keeps its slot in `rest`
	for k in BALLS:
		if not used.has(k):
			return k
	return 0


func _tray_count() -> int:
	var n := 0
	for o: Ball in balls:
		if o.tray >= 0 or o.hop > 0.0:
			n += 1
	return n


## Ballistic velocity from `from` to `to` in `t` seconds.
func _lob(from: Vector3, to: Vector3, t: float) -> Vector3:
	return (to - from) / t + Vector3(0.0, 0.5 * GRAV * t, 0.0)


func _hop_home(b: Ball) -> void:
	var k := _free_tray_slot()
	b.hop = 0.8
	b.rest = float(k)
	b.vel = _lob(b.node.position, _tray_pos(k), 0.8)
	b.danger = false
	b.thrower = -1
	sound_at("boing", b.node.position, -6.0, 1.3)


func _ball_physics(b: Ball, i: int, delta: float) -> void:
	if b.holder >= 0:
		if b.holder == GIANT:
			return  # the hand code places it
		if avatars.has(b.holder):
			var a: Node3D = avatars[b.holder]
			b.node.position = a.position + Vector3(0.0, Creatures.height_of(a) + 0.3, 0.0)
		else:
			b.holder = -1
		return
	if b.tray >= 0:
		b.node.position = _tray_pos(b.tray) + Vector3(0.0, 0.02 * sin(clock * 3.0 + float(i)), 0.0)
		return
	var p := b.node.position
	b.vel.y -= GRAV * delta
	p += b.vel * delta
	if b.hop > 0.0:
		b.hop -= delta
		b.node.position = p
		if b.hop <= 0.0:
			_to_tray(b, int(b.rest))
			b.squish = 0.6
		return
	var fy := _floor_at(p)
	if p.y < fy + BALL_R:
		p.y = fy + BALL_R
		if b.vel.y < -1.2:
			if b.vel.y < -3.0:
				_boing(i, p, clampf(-b.vel.y / 8.0, 0.2, 1.0))
			b.vel.y = -b.vel.y * 0.55
		else:
			b.vel.y = 0.0
		b.danger = false
		b.vel.x *= 1.0 - minf(1.0, 2.0 * delta)
		b.vel.z *= 1.0 - minf(1.0, 2.0 * delta)
	# Walls and the stage's front face
	if absf(p.x) > WALL_X:
		p.x = signf(p.x) * WALL_X
		b.vel.x = -b.vel.x * 0.6
	if p.z > WALL_Z.y:
		p.z = WALL_Z.y
		b.vel.z = -b.vel.z * 0.6
	if p.z < WALL_Z.x:
		p.z = WALL_Z.x
		b.vel.z = -b.vel.z * 0.6
	if b.node.position.z >= STAGE_FRONT and p.z < STAGE_FRONT and p.y < STAGE_H + BALL_R * 0.5:
		p.z = STAGE_FRONT
		b.vel.z = absf(b.vel.z) * 0.5
	b.node.position = p
	# The giant's belly and body
	if b.thrower != GIANT and b.thrower >= 0 and b.danger and not results_showing():
		if p.distance_to(target_point()) < 0.42:
			_belly_hit(b, i)
			return
	var tc := _torso_center()
	if p.distance_to(tc) < 0.5:
		var n := (p - tc).normalized()
		b.node.position = tc + n * 0.5
		b.vel = b.vel.bounce(n) * 0.5 if b.vel.dot(n) < 0.0 else b.vel
		b.danger = false
		_boing(i, p, 0.5)
	# Resting: on the stage it hops back to the tray; on the court the runners get it (or the giant
	# gets it back if it lies around too long while the tray is nearly empty).
	if b.vel.length() < 0.6 and p.y < _floor_at(p) + BALL_R + 0.05:
		b.rest += delta
		if p.z < STAGE_FRONT + 0.1 and b.rest > 0.4:
			_hop_home(b)
		elif b.rest > 7.0 and _tray_count() < 2:
			_hop_home(b)
	else:
		b.rest = 0.0


func _boing(i: int, p: Vector3, strength: float) -> void:
	var b: Ball = balls[i]
	b.squish = strength
	sfx.play_at("boing", p, -10.0 + 8.0 * strength, randf_range(0.9, 1.2))
	net.event("boing", [i, p, strength])


func _belly_hit(b: Ball, i: int) -> void:
	var who := b.thrower
	b.danger = false
	b.thrower = -1
	var n := _fwd()
	b.vel = n * 3.0 + Vector3(randf_range(-1.0, 1.0), 3.5, 0.0)
	b.node.position = target_point() + n * 0.45
	balls[i] = b
	net.state_set("tv_score", int(net.state_get("tv_score", 0)) + 1)
	if who < 10:
		awards.add(who, "score")
	if vr_rig != null:
		vr_rig.pulse(VrRig.LEFT, 0.8, 0.2)
		vr_rig.pulse(VrRig.RIGHT, 0.8, 0.2)
	belly_fx(target_point(), who)


## The belly target was hit (every machine).
func belly_fx(p: Vector3, who: int) -> void:
	world.wobble_belly()
	burst(p, Color(1.0, 0.85, 0.3), 24, 0.1)
	sfx.play_at("ding", p, 0.0, 1.0)
	sfx.play_at("cheer", p, -6.0)
	var col: Color = party.color_of(who) if who >= 0 and who < 10 else Color(1.0, 0.85, 0.3)
	HudKit.score(self, p + Vector3.UP * 0.5, 1, {"color": col, "size": 2.0})
	net.event("belly", [p, who])


# --- The giant -------------------------------------------------------------------------------

func _update_giant(delta: float, playing: bool) -> void:
	var before := g_head
	_move_giant(delta, playing)
	g_vel = g_vel.lerp((g_head - before) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))


func _move_giant(delta: float, playing: bool) -> void:
	if vr_rig != null:
		g_head = vr_rig.head_position()
		g_yaw = vr_rig.head_yaw()
		g_hands[0] = vr_rig.hand_point(VrRig.LEFT)
		g_hands[1] = vr_rig.hand_point(VrRig.RIGHT)
		return
	# CPU giant: sways side to side, grabs a ball from the tray, winds up and lobs it at a runner.
	cpu_g["sway"] = float(cpu_g["sway"]) + delta
	var sway := sin(float(cpu_g["sway"]) * 0.8) * 1.4
	var head_goal := GIANT_FEET + Vector3(sway, 1.6 + 0.05 * sin(clock * 2.0), 0.0)
	g_head = g_head.lerp(head_goal, 1.0 - exp(-3.0 * delta))
	g_yaw = PI
	var rest_l := g_head + Vector3(-0.45, -0.75, 0.25)
	var rest_r := g_head + Vector3(0.45, -0.75, 0.25)
	var bi: int = int(cpu_g["ball"])
	cpu_g["t"] = float(cpu_g["t"]) - delta
	var hand_goal := rest_r
	match int(cpu_g["phase"]):
		0:  # waiting
			if playing and float(cpu_g["t"]) <= 0.0:
				var aim := _pick_runner()
				var tb := _nearest_tray_ball(g_hands[1])
				if aim >= 0 and tb >= 0:
					cpu_g["ball"] = tb
					cpu_g["aim"] = aim
					cpu_g["phase"] = 1
					cpu_g["t"] = 0.5
				else:
					cpu_g["t"] = 0.5
		1:  # reach for the ball
			if bi >= 0:
				var b: Ball = balls[bi]
				if b.tray < 0 or b.holder >= 0:
					cpu_g["phase"] = 0
				else:
					hand_goal = b.node.position
					if g_hands[1].distance_to(b.node.position) < 0.15 or float(cpu_g["t"]) <= 0.0:
						b.tray = -1
						b.holder = GIANT
						cpu_g["phase"] = 2
						cpu_g["t"] = 0.7
						sound_at("pickup", b.node.position, -4.0)
		2:  # wind up, then throw
			hand_goal = g_head + Vector3(0.5, 0.25, -0.35)
			if bi >= 0:
				var b: Ball = balls[bi]
				b.node.position = g_hands[1]
				if float(cpu_g["t"]) <= 0.0:
					var aim: int = int(cpu_g["aim"])
					var to := Vector3(randf_range(-3.0, 3.0), 0.5, randf_range(0.0, 4.0))
					if avatars.has(aim):
						var lead: Vector3 = vels.get(aim, Vector3.ZERO) * 0.7
						to = (avatars[aim] as Node3D).position + lead + Vector3(randf_range(-0.4, 0.4), 0.6, randf_range(-0.4, 0.4))
					_release(b, _lob(b.node.position, to, 1.0))
					cpu_g["phase"] = 0
					cpu_g["ball"] = -1
					cpu_g["t"] = randf_range(0.9, 1.8)
	g_hands[1] = g_hands[1].move_toward(hand_goal, 4.0 * delta) if g_hands[1] != Vector3.ZERO else hand_goal
	g_hands[0] = g_hands[0].lerp(rest_l, 1.0 - exp(-5.0 * delta)) if g_hands[0] != Vector3.ZERO else rest_l


func _pick_runner() -> int:
	var ids: Array = []
	for id in avatars:
		if not out.has(id) and not safe.has(id):
			ids.append(id)
	if ids.is_empty():
		return -1
	return int(ids[randi() % ids.size()])


func _nearest_tray_ball(from: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in balls.size():
		var b: Ball = balls[i]
		if b.tray >= 0 and b.holder < 0:
			var d := from.distance_to(b.node.position)
			if d < bd:
				bd = d
				best = i
	return best


func _release(b: Ball, v: Vector3) -> void:
	b.holder = -1
	b.tray = -1
	b.vel = v
	b.thrower = GIANT
	b.danger = v.length() > 2.0
	b.rest = 0.0
	sound_at("whoosh", b.node.position, -2.0, 0.9)


## VR hands: the right hand grabs with the trigger and throws on release; any hand bats balls it
## touches (fast = a swat that can hit runners, slow = a push).
func _vr_hands(_delta: float) -> void:
	var held := -1
	for i in balls.size():
		var b: Ball = balls[i]
		if b.holder == GIANT:
			held = i
	var rp := vr_rig.hand_point(VrRig.RIGHT)
	if held >= 0:
		var b: Ball = balls[held]
		b.node.position = rp + (vr_rig.hand_r.global_basis.y * -0.02)
		if not vr_rig.trigger_down():
			var v := vr_rig.hand_velocity(VrRig.RIGHT) * 1.5
			if v.length() > 1.5:
				v = _assist(b.node.position, v)
			_release(b, v)
			b.squish = 0.4
	elif vr_rig.trigger_down() and String(net.state_get("phase", "")) == "play":
		var best := -1
		var bd := 0.3
		for i in balls.size():
			var b: Ball = balls[i]
			if b.holder >= 0 or b.hop > 0.0:
				continue
			var d := b.node.position.distance_to(rp)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			var b: Ball = balls[best]
			b.holder = GIANT
			b.tray = -1
			b.squish = 0.5
			vr_rig.pulse(VrRig.RIGHT, 0.5, 0.06)
			sound_at("pickup", b.node.position, -3.0)
	for h in 2:
		var hp := vr_rig.hand_point(h)
		var hv := vr_rig.hand_velocity(h)
		for i in balls.size():
			var b: Ball = balls[i]
			if b.holder >= 0 or b.hop > 0.0:
				continue
			var d := b.node.position - hp
			if d.length() > BALL_R + 0.08:
				continue
			var n := d.normalized() if d.length() > 0.01 else _fwd()
			if b.tray >= 0:
				if b.squish < 0.1:  # balls on the tray just squish (reaching for one never knocks it off)
					b.squish = 0.4
					sound_at("boing", b.node.position, -12.0, 1.5)
				continue
			if hv.length() > 1.3:
				b.vel = _assist(b.node.position, hv * 1.4 + n * 1.0)
				b.thrower = GIANT
				b.danger = true
				sound_at("ball_hit", b.node.position, -2.0)
			else:
				b.vel = b.vel.bounce(n) * 0.4 + hv + n * 0.8 if b.vel.dot(n) < 0.0 else b.vel + n * 0.8
				b.thrower = -1
				b.danger = false
			b.node.position = hp + n * (BALL_R + 0.09)
			b.squish = 0.5
			b.rest = 0.0
			vr_rig.pulse(h, 0.35, 0.05)
	world.touch_props(self, [vr_rig.hand_point(VrRig.LEFT), vr_rig.hand_point(VrRig.RIGHT)],
		[vr_rig.hand_speed(VrRig.LEFT), vr_rig.hand_speed(VrRig.RIGHT)])


## Kids throw a bit wild: bend a throw gently towards the runner nearest its line.
func _assist(from: Vector3, v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length() < 0.5:
		return v
	var best := Vector3.ZERO
	var ba := deg_to_rad(30.0)
	for id in avatars:
		if out.has(id):
			continue
		var to: Vector3 = (avatars[id] as Node3D).position - from
		to.y = 0.0
		var ang := flat.angle_to(to)
		if ang < ba:
			ba = ang
			best = to
	if best == Vector3.ZERO:
		return v
	var nf := flat.normalized().slerp(best.normalized(), 0.6) * flat.length()
	return Vector3(nf.x, v.y, nf.z)


# --- Runners ---------------------------------------------------------------------------------

func _holding(id: int) -> int:
	for i in balls.size():
		if (balls[i] as Ball).holder == id:
			return i
	return -1


func _runner_pickups() -> void:
	for id in avatars:
		if out.has(id) or _holding(int(id)) >= 0:
			continue
		var a: Node3D = avatars[id]
		for i in balls.size():
			var b: Ball = balls[i]
			if b.holder >= 0 or b.tray >= 0 or b.hop > 0.0 or (b.danger and b.thrower == GIANT):
				continue
			var p := b.node.position
			if p.y < 1.2 and Vector2(p.x - a.position.x, p.z - a.position.z).length() < 0.8:
				b.holder = int(id)
				b.thrower = -1
				b.danger = false
				b.squish = 0.6
				sound_at("pickup", p, -2.0, 1.2)
				if party.is_active(int(id)):
					party.rumble(int(id), 0.3, 0.0, 0.1)
				break


func _runner_throw(id: int) -> void:
	var i := _holding(id)
	if i < 0 or out.has(id):
		return
	var b: Ball = balls[i]
	var from := b.node.position
	var t := clampf(from.distance_to(target_point()) / 8.5, 0.55, 1.2)
	var wobble := Vector2.from_angle(randf() * TAU) * randf_range(0.0, 0.45)  # not every throw is perfect
	var to := target_point() + Vector3(g_vel.x, 0.0, g_vel.z) * t + Vector3(wobble.x, wobble.y, 0.0)
	b.holder = -1
	b.vel = _lob(from, to, t)
	b.thrower = id
	b.danger = true
	b.rest = 0.0
	b.squish = 0.5
	sound_at("whoosh", from, -2.0, 1.2)
	if avatars.has(id):
		Creatures.anim(avatars[id]).play("attack", 0.4)
	net.event("anim", [id, "attack"])


func _runner_hits() -> void:
	for i in balls.size():
		var b: Ball = balls[i]
		if b.holder >= 0 or not b.danger or b.thrower != GIANT:
			continue
		var p := b.node.position
		for id in avatars:
			if out.has(id) or safe.has(id):
				continue
			var a: Node3D = avatars[id]
			if p.y < Creatures.height_of(a) + 0.4 and Vector2(p.x - a.position.x, p.z - a.position.z).length() < 0.6:
				_hit_runner(int(id), b)
				break


func _hit_runner(id: int, b: Ball) -> void:
	b.danger = false
	b.thrower = -1
	b.vel = Vector3(-b.vel.x * 0.25, 2.5, -b.vel.z * 0.25)
	b.squish = 0.8
	_drop_held(id)
	out[id] = OUT_TIME
	net.state_set("giant_score", int(net.state_get("giant_score", 0)) + 1)
	if vr_rig != null:
		awards.add(0, "hits")
		vr_rig.pulse(VrRig.RIGHT, 0.6, 0.12)
	if party.is_active(id):
		party.rumble(id, 0.6, 0.8, 0.3)
		awards.add(id, "deaths")
	var a: Node3D = avatars[id]
	puff(a.position + Vector3.UP * 0.6, party.color_of(id) if id < 10 else Color(0.7, 0.7, 0.7))


func _drop_held(id: int) -> void:
	var i := _holding(id)
	if i >= 0:
		_drop_ball(balls[i])


func _drop_ball(b: Ball) -> void:
	if b.holder >= 0:
		b.holder = -1
		b.vel = Vector3(randf_range(-1.0, 1.0), 2.0, randf_range(-1.0, 1.0))
		b.thrower = -1
		b.danger = false


## A runner was hit: a puff of feathers (every machine).
func puff(p: Vector3, color: Color) -> void:
	burst(p, Color(1.0, 1.0, 1.0), 30, 0.12, true)
	burst(p, color, 10, 0.1)
	sfx.play_at("pop", p, 0.0, 0.9)
	sfx.play_at("crowd_oh", p, -8.0)
	net.event("puff", [p, color])


## A runner pops back in (every machine).
func pop_back(id: int) -> void:
	if avatars.has(id):
		var a: Node3D = avatars[id]
		a.scale = Vector3(0.2, 0.2, 0.2)
		a.create_tween().tween_property(a, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		sfx.play_at("boing", a.position, -2.0, 1.4)
	net.event("back", [id])


func burst(p: Vector3, color: Color, amount: int, size: float, feathers: bool = false) -> void:
	var c := CPUParticles3D.new()
	c.one_shot = true
	c.amount = amount
	c.lifetime = 1.6 if feathers else 0.6
	c.explosiveness = 1.0
	c.spread = 180.0
	c.direction = Vector3.UP
	c.initial_velocity_min = 1.5 if feathers else 2.5
	c.initial_velocity_max = 3.5 if feathers else 5.0
	c.gravity = Vector3(0.0, -1.2, 0.0) if feathers else Vector3(0.0, -9.0, 0.0)
	c.damping_min = 2.0 if feathers else 0.0
	c.damping_max = 3.0 if feathers else 0.0
	c.angular_velocity_min = -300.0
	c.angular_velocity_max = 300.0
	var m: PrimitiveMesh
	var mat: StandardMaterial3D = MeshKit.material(color, 0.6)
	if feathers:
		var q := QuadMesh.new()
		q.size = Vector2(size, size * 2.0)
		m = q
		mat = mat.duplicate() as StandardMaterial3D
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * size * 0.7
		m = bm
	m.material = mat
	c.mesh = m
	add_child(c)
	c.position = p
	c.emitting = true
	get_tree().create_timer(2.0).timeout.connect(c.queue_free)


# --- CPU runners (VR alone: someone to throw at) -------------------------------------------------

func _update_cpu_runners(delta: float, playing: bool) -> void:
	var want := vr_rig != null and party.player_count() == 0
	for k in CPU_IDS.size():
		var id: int = CPU_IDS[k]
		if want and not avatars.has(id):
			_ensure_avatar(id)
			cpu[id] = {"goal": Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(0.0, 5.0)), "t": 0.0, "hold": 0.0}
			_refresh_group()
		elif not want and avatars.has(id):
			_drop_held(id)
			(avatars[id] as Node).queue_free()
			avatars.erase(id)
			last_pos.erase(id)
			out.erase(id)
			cpu.erase(id)
			_refresh_group()
	for id in cpu:
		if not avatars.has(id) or out.has(id) or not playing:
			continue
		var a: Node3D = avatars[id]
		var st: Dictionary = cpu[id]
		st["t"] = float(st["t"]) - delta
		var goal: Vector3 = st["goal"]
		if _holding(int(id)) >= 0:
			st["hold"] = float(st["hold"]) + delta
			if float(st["hold"]) > 1.4:
				st["hold"] = 0.0
				_runner_throw(int(id))
		else:
			var near := -1
			var nd := 6.0
			for i in balls.size():
				var b: Ball = balls[i]
				if b.holder < 0 and b.tray < 0 and b.hop <= 0.0 and b.node.position.z > COURT_Z.x - 0.5:
					var d := b.node.position.distance_to(a.position)
					if d < nd:
						nd = d
						near = i
			if near >= 0:
				goal = (balls[near] as Ball).node.position
		# Dodge: step sideways from a dangerous ball coming this way.
		for b: Ball in balls:
			if b.danger and b.thrower == GIANT and b.node.position.distance_to(a.position) < 4.0 and randf() < 0.5:
				var side := Vector3(b.vel.z, 0.0, -b.vel.x).normalized()
				goal = a.position + side * 2.0
				st["t"] = 0.6
		if float(st["t"]) <= 0.0 or a.position.distance_to(goal) < 0.4:
			goal = Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-2.0, 5.5))
			st["t"] = randf_range(1.5, 3.0)
		st["goal"] = goal
		var dir := goal - a.position
		dir.y = 0.0
		if dir.length() > 0.2:
			dir = dir.normalized()
			a.position = _clamp_court(a.position + dir * SPEED * 0.6 * delta)
			Creatures.anim(a).face(dir)


# --- Sounds ----------------------------------------------------------------------------------

func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)
	net.event("snd", [sound_name, volume_db, pitch])


func sound_at(sound_name: String, p: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(sound_name, p, volume_db, pitch)
	net.event("snd3", [sound_name, p, volume_db, pitch])


# --- Networking ------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var gp := PackedVector3Array([g_head, g_hands[0], g_hands[1], Vector3(g_yaw, 0.0, 0.0)])
	var bp := PackedVector3Array()
	var bh := PackedInt32Array()
	for b: Ball in balls:
		bp.append(b.node.position)
		bh.append(b.holder)
	var outs := PackedInt32Array()
	for id in out:
		outs.append(int(id))
	for id in safe:
		outs.append(-1 - int(id))  # negative: blinking
	var cids := PackedInt32Array()
	var cpos := PackedVector3Array()
	for id in cpu:
		if avatars.has(id):
			cids.append(int(id))
			cpos.append((avatars[id] as Node3D).position)
	return [gp, bp, bh, outs, cids, cpos]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 6:
		return
	_snap_giant = s[0]
	var bp: PackedVector3Array = s[1]
	var bh: PackedInt32Array = s[2]
	for i in mini(bp.size(), balls.size()):
		var b: Ball = balls[i]
		b.target = bp[i]
		b.holder = bh[i]
	var outs: PackedInt32Array = s[3]
	out.clear()
	safe.clear()
	for id in outs:
		if id >= 0:
			out[id] = true
		else:
			safe[-1 - id] = true
	var cids: PackedInt32Array = s[4]
	var cpos: PackedVector3Array = s[5]
	var seen := {}
	for k in cids.size():
		seen[cids[k]] = true
		var a := _ensure_avatar(cids[k])
		if not cpu.has(cids[k]):
			cpu[cids[k]] = {}
			_refresh_group()
		a.position = a.position.lerp(cpos[k], 0.5)
	for id in cpu.keys():
		if not seen.has(id):
			if avatars.has(id):
				(avatars[id] as Node).queue_free()
				avatars.erase(id)
				last_pos.erase(id)
			cpu.erase(id)
			_refresh_group()


func _client_smooth(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	if _snap_giant.size() >= 4:
		g_head = g_head.lerp(_snap_giant[0], k)
		g_hands[0] = g_hands[0].lerp(_snap_giant[1], k)
		g_hands[1] = g_hands[1].lerp(_snap_giant[2], k)
		g_yaw = lerp_angle(g_yaw, _snap_giant[3].x, k)
	for b: Ball in balls:
		if b.holder >= 0 and b.holder != GIANT and party.is_local(b.holder) and avatars.has(b.holder):
			var a: Node3D = avatars[b.holder]
			b.node.position = a.position + Vector3(0.0, Creatures.height_of(a) + 0.3, 0.0)  # my own ball: instant
		elif b.node.position.distance_to(b.target) > 3.0:
			b.node.position = b.target
		else:
			b.node.position = b.node.position.lerp(b.target, k)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"boing":
			var i: int = int(args[0])
			if i < balls.size():
				(balls[i] as Ball).squish = float(args[2])
			sfx.play_at("boing", args[1], -10.0 + 8.0 * float(args[2]), randf_range(0.9, 1.2))
		"belly":
			belly_fx(args[0], int(args[1]))
		"puff":
			puff(args[0], args[1])
		"back":
			pop_back(int(args[0]))
		"anim":
			if avatars.has(int(args[0])):
				Creatures.anim(avatars[int(args[0])]).play(String(args[1]), 0.4)
		"snd":
			sfx.play(String(args[0]), float(args[1]), float(args[2]))
		"snd3":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
