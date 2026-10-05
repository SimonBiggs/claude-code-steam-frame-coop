extends Node3D
## MINI GOLF PARTY: putt the ball into the hole. Five short, cosy holes in a garden, one gimmick
## each (a straight practice putt, a bumper in a bend, a windmill, a hill, a loop-the-loop).
## Everyone plays AT ONCE (no waiting for turns): whenever your ball has stopped you can putt again.
## - VR golfer (slot 0, host): a real putter in the right hand; swing it through the ball. A
##   teleports you behind your ball; the left stick walks. A ghost glove shows the swing on the first
##   hole. Toys round the tee: spare balls to throw (right trigger), a duck, bushes, the flag, the
##   windmill sails.
## - TV players (slots 1..6, or 0 too in local play without a headset): aim with the left stick
##   (the arrow starts pointing the right way), hold A to grow the arrow, let go to putt.
## - Sink it: a cheer, confetti and a little flag for that hole on the board, or a gold star if it
##   took only a few putts. No numbers anywhere. After six putts the ball hops in by itself.
## Modes as in games/engine_template: local (split-screen fallback, one shared TV view), host (VR on
## the Steam Frame), client (the TV machine mirrors the host; its players putt via net.request).

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
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const Course := preload("res://games/mini_golf_party/course.gd")
const Ball := preload("res://games/mini_golf_party/ball.gd")
const Putter := preload("res://games/mini_golf_party/putter.gd")
const GhostHand := preload("res://games/mini_golf_party/ghost_hand.gd")
const Props := preload("res://games/mini_golf_party/props.gd")

const GAME_ID := "mini_golf_party"
const MAX_STROKES := 6
const HOLE_TIME := 150.0  ## then every ball still out hops in (keeps the party moving)
const CHARGE_TIME := 1.2  ## seconds of holding A for the biggest putt
const VR_GAIN := 1.7  ## ball speed / putter head speed
## Card marks per hole: 0 = not yet, 1 = flag (holed), 2 = star (few putts), 3 = hole in one.

# --- The networking contract ---
var net: Node
var ready_to_play := false
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var awards: Awards
var sky: SkyKit.SkyRig

var course: Course
var props: Props
var balls := {}  # slot -> Ball
var putter: Putter  # host: the VR golfer's club; TV machine: a copy drawn from the snapshot
var ghost: GhostHand
var vr_avatar: VrRig.Avatar
var board: Node3D  # the flag / star board over the hole (every machine)
var arrows := {}  # slot -> Node3D
var aim := {}  # slot -> float (angle on the XZ plane, Vector2(x, z).angle())
var power := {}  # slot -> float 0..1
var remote_aim := {}  # host: slot -> Vector3(angle, power, showing)
var putted := {}  # slot -> true once this player has putted (the A prompt goes away)
var was_resting := {}  # slot -> bool (TV aim resets to the hole when the ball stops)
var sent_t := {}  # TV machine: slot -> seconds to hide the arrow after sending a putt
var rest_flags := {}  # TV machine: slot -> resting (from the snapshot)
var sink_log: Array = []  # [hole, slot, strokes, mark] (bots: the design check)
var hole_t := 0.0
var phase_t := 0.0
var vr_putt_cool := 0.0
var vr_idle := 0.0
var send_t := 0.0
var fade: MeshInstance3D
var fade_mat: StandardMaterial3D
var hud: Control
var chips: HBoxContainer
var prompt: Control
var join_prompt: Control
var results_ui: Control
var vr_results: Node
var vr_banner: Node3D
var tv_banner: Control


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
	save.defaults = {"best_stars": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("stars", "STAR GOLFER", "%s gold stars", "stars")
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
		add_child(vr_rig)
		vr_rig.place(Vector3(0.6, 0.0, 2.0), 0.0)
		putter = Putter.new()
		putter.color = Party.COLORS[0]
		add_child(putter)
		ghost = GhostHand.new()
		add_child(ghost)
		_make_fade()
	_build_world(vr_rig != null)
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		split.set_shared(true)  # one picture of the whole hole: everyone sees every ball
		_make_hud(split.shared_hud())
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			add_child(vr_avatar)
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
			putter = Putter.new()
			putter.color = Party.COLORS[0]
			putter.visible = false
			add_child(putter)
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	if mode != "client":
		_start_course()
	elif net.state_has("hole"):
		_build_hole(int(net.state_get("hole", 0)))
	if vr_rig != null:
		HudKit.vr_banner(self, vr_rig.camera, "PUTT IT IN!", "", {"duration": 3.0})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Mini Golf Party: %s mode%s" % [mode, " with a VR golfer" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	var lawn := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 22.0
	disc.bottom_radius = 22.0
	disc.height = 0.2
	disc.radial_segments = 32
	lawn.mesh = disc
	lawn.material_override = MeshKit.material(Course.GRASS)
	lawn.position.y = -0.105
	add_child(lawn)
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 22, Vector3.ZERO, 18.0, 7.0, 0.9, 1.4, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 18, Vector3.ZERO, 7.0, 4.5, 0.8, 1.2, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 50, Vector3.ZERO, 6.5, 3.4, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0), Color(1.0, 1.0, 1.0)]), 5))
	course = Course.new()
	course.name = "Course"
	add_child(course)
	props = Props.new()
	props.main = self
	add_child(props)
	board = Node3D.new()
	add_child(board)


func _make_fade() -> void:
	fade = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.3
	s.height = 0.6
	s.radial_segments = 12
	s.rings = 6
	fade.mesh = s
	fade_mat = StandardMaterial3D.new()
	fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fade_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	fade_mat.render_priority = 10
	fade.material_override = fade_mat
	fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fade.visible = false
	vr_rig.camera.add_child(fade)


## VR comfort: a quick blink to black and back around a teleport / new hole.
func blink() -> void:
	if fade == null:
		return
	fade.visible = true
	fade_mat.albedo_color.a = 1.0
	var tw := create_tween()
	tw.tween_property(fade_mat, "albedo_color:a", 0.0, 0.45).set_delay(0.1)
	tw.tween_callback(func() -> void: fade.visible = false)


# --- Holes (host / local decide; every machine builds the course from "hole") -----------------

func _start_course() -> void:
	awards.reset()
	for s in _ball_slots():
		awards.set_player(s, _name_of(s))
	net.state_set("card", {})
	var first := 0
	if OS.has_environment("MGP_HOLE") and not has_meta("started"):
		first = clampi(int(OS.get_environment("MGP_HOLE")) - 1, 0, Course.HOLES - 1)  # debug: start at hole N
	set_meta("started", true)
	_go_hole(first)


func _go_hole(i: int) -> void:
	hole_t = 0.0
	net.state_set("phase", "play")
	net.state_set("hole", i)  # the TV machine builds it when this arrives
	_build_hole(i)


func _build_hole(i: int) -> void:
	course.build(i)
	props.move_to(Vector3(course.tee.x, 0.0, course.tee.y))
	var tw := Vector3(course.tee.x, 0.0, course.tee.y)
	board.position = Vector3(course.cup.x, 0.0, course.cup.y - 0.9)
	_refresh_board()
	if net.mode != "client":
		var slots := _ball_slots()
		for k in slots.size():
			var b := _ensure_ball(slots[k])
			b.strokes = 0
			b.place(_tee_spot(k, slots.size()))
	aim.clear()
	was_resting.clear()
	if vr_rig != null:
		var r := course.bounds().grow(2.5)
		vr_rig.bounds = r
		var fwd := (course.aim_point(course.tee) - course.tee).normalized()
		var feet := tw - Vector3(fwd.x, 0.0, fwd.y) * 0.55 + Vector3(-fwd.y, 0.0, fwd.x) * 0.25
		vr_rig.place(feet, atan2(-fwd.x, -fwd.y))
		blink()
	if split != null:
		_frame_camera()
		if i > 0:
			HudKit.banner([hud], "HOLE %d" % (i + 1), "", {"duration": 1.6})
	vr_idle = 0.0


func _tee_spot(k: int, n: int) -> Vector2:
	var off := (float(k) - float(n - 1) * 0.5) * 0.12
	return course.tee + Vector2(off, 0.0)


func _frame_camera() -> void:
	var cam := split.shared_camera()
	var b := course.bounds()
	var c := b.get_center()
	var l := b.size.y
	var w := b.size.x
	var pos := Vector3(c.x, 1.0 + l * 0.6 + w * 0.35, b.end.y + 0.9 + l * 0.2)
	cam.fov = 55.0
	cam.global_position = pos
	cam.look_at(Vector3(c.x, 0.0, c.y - l * 0.08), Vector3.UP)


## Slots that have a ball: the VR golfer (host) plus everyone seated.
func _ball_slots() -> Array[int]:
	var out: Array[int] = []
	if vr_rig != null:
		out.append(0)
	for s in party.active_slots():
		if not out.has(s):
			out.append(s)
	return out


func _ensure_ball(slot: int) -> Ball:
	if balls.has(slot):
		return balls[slot]
	var b := Ball.new()
	b.slot = slot
	b.color = Party.COLORS[slot % Party.COLORS.size()]
	b.course = course
	if net.mode == "client":
		b.set_meta("mirror", true)
	add_child(b)
	balls[slot] = b
	return b


func _remove_ball(slot: int) -> void:
	if balls.has(slot):
		(balls[slot] as Node).queue_free()
		balls.erase(slot)
	if arrows.has(slot):
		(arrows[slot] as Node).queue_free()
		arrows.erase(slot)


func _name_of(slot: int) -> String:
	return "GOLFER" if slot == 0 and (vr_rig != null or net.mode == "client") else party.name_of(slot)


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	if net.mode != "client" and course.outline.size() > 0:
		var b := _ensure_ball(slot)
		if b.state == "rest" and b.strokes == 0:
			b.place(_tee_spot(balls.size() - 1, maxi(balls.size(), 4)))
		awards.set_player(slot, _name_of(slot))
	_refresh_hud()
	sfx.play("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	if net.mode != "client":
		_remove_ball(slot)
	_refresh_hud()
	_refresh_board()


# --- Putting (host / local) -----------------------------------------------------------------

func do_putt(slot: int, v: Vector2) -> void:
	if not balls.has(slot) or String(net.state_get("phase", "play")) != "play":
		return
	var b: Ball = balls[slot]
	if not b.resting():
		return
	b.putt(v)
	var p := b.position
	_sound_at("ball_hit", p, -2.0, clampf(0.8 + v.length() * 0.1, 0.8, 1.3))


func _sink(slot: int, b: Ball) -> void:
	var hole := int(net.state_get("hole", 0))
	var mark := 1
	if b.strokes == 1:
		mark = 3
	elif b.strokes <= course.par:
		mark = 2
	var card: Dictionary = net.state_get("card", {}).duplicate(true)
	var row: Array = card.get(slot, [0, 0, 0, 0, 0])
	while row.size() < Course.HOLES:
		row.append(0)
	row[hole] = mark
	card[slot] = row
	net.state_set("card", card)
	sink_log.append([hole, slot, b.strokes, mark])
	if mark >= 2:
		awards.add(slot, "stars")
	if mark == 3:
		awards.add(slot, "holes_in_one")
	celebrate(slot, Vector3(course.cup.x, 0.05, course.cup.y), mark)


## Every machine: confetti, a cheer, the duck hops, the flag waves.
func celebrate(slot: int, p: Vector3, mark: int) -> void:
	var col: Color = Party.COLORS[slot % Party.COLORS.size()]
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = 40 if mark >= 2 else 24
	cp.lifetime = 1.2
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 35.0
	cp.initial_velocity_min = 2.0
	cp.initial_velocity_max = 3.5
	cp.gravity = Vector3(0.0, -4.0, 0.0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, 0.008)
	bm.material = MeshKit.vertex_material(true)
	cp.mesh = bm
	cp.color_ramp = null
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.7), Color(0.5, 0.9, 1.0)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	cp.color_initial_ramp = g
	add_child(cp)
	cp.position = p
	cp.emitting = true
	get_tree().create_timer(1.6).timeout.connect(cp.queue_free)
	sfx.play("swish", 0.0)
	sfx.play("cheer" if mark >= 2 else "applause", -3.0)
	if mark == 3:
		sfx.play("fanfare", -2.0)
		HudKit.popup(self, p + Vector3.UP * 0.6, "HOLE IN ONE!", {"style": "score", "color": col, "size": 1.4})
	elif mark == 2:
		HudKit.popup(self, p + Vector3.UP * 0.5, "*", {"style": "score", "color": "gold", "size": 1.6})
	props.cheer()
	course.flag_wave = 1.2
	if vr_rig != null and slot == 0:
		vr_rig.pulse(VrRig.RIGHT, 0.7, 0.15)
	if net.mode == "host":
		net.event("sink", [slot, p, mark])


func _sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	if net.mode == "host":
		net.event("sfx", [n, p, db, pitch])


## Host / local: a player asked for something (from any machine).
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"putt":
			if args.size() > 0 and args[0] is Vector2:
				putted[slot] = true
				do_putt(slot, args[0])
		"again":
			if String(net.state_get("phase", "")) == "results":
				_start_course()


## Host: a TV player's aim arrow (so the VR golfer sees it too).
func on_remote_state(slot: int, pos: Vector3, _yaw: float, _pitch: float) -> void:
	remote_aim[slot] = pos


# --- Game loop -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not ready_to_play or net.mode == "client":
		return
	_sync_balls()
	var phase := String(net.state_get("phase", "play"))
	if vr_rig != null:
		_vr_golfer(delta)
	for s in balls:
		var b: Ball = balls[s]
		b.step(delta)
	var list: Array = balls.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Ball = list[i]
			var c: Ball = list[j]
			if a.state in ["rest", "roll"] and c.state in ["rest", "roll"] and Ball.knock(a, c):
				_sound_at("ball_hit", a.position, -12.0, 1.6)
	for s in balls:
		var b: Ball = balls[s]
		for e in b.events:
			_ball_event(int(s), b, e)
		b.events.clear()
	if phase == "play":
		hole_t += delta
		_hole_rules()
	elif phase == "cheer":
		phase_t += delta
		if phase_t > 3.0:
			var h := int(net.state_get("hole", 0))
			if h + 1 >= Course.HOLES:
				_end_course()
			else:
				_go_hole(h + 1)
	elif phase == "results":
		phase_t += delta
		if phase_t > 40.0:
			_start_course()


func _ball_event(slot: int, b: Ball, e: Array) -> void:
	match String(e[0]):
		"wall":
			_sound_at("bounce", b.position, clampf(-14.0 + float(e[1]) * 4.0, -14.0, -2.0), 1.4)
		"bump":
			_sound_at("boing", b.position, -3.0)
		"loop":
			_sound_at("whoosh", b.position, 0.0, 1.2)
		"back":
			_sound_at("crowd_oh", b.position, -8.0)
		"reset":
			_sound_at("splash", b.position, -4.0)
		"cup":
			_sink(slot, b)


func _hole_rules() -> void:
	if balls.is_empty():
		return
	var all_in := true
	for s in balls:
		var b: Ball = balls[s]
		if b.state != "cup":
			all_in = false
			# Too many putts (or the hole has gone on too long): it hops in by itself.
			if b.resting() and (b.strokes >= MAX_STROKES or hole_t > HOLE_TIME):
				b.strokes = maxi(b.strokes, course.par + 1)
				b.place(course.cup)
				b.state = "cup"
				b.sink_t = 0.0
				_sound_at("boing", b.position, -4.0, 1.3)
				_sink(int(s), b)
	if all_in:
		net.state_set("phase", "cheer")
		phase_t = 0.0


func _sync_balls() -> void:
	if course.outline.is_empty():
		return
	var want := _ball_slots()
	for s in want:
		if not balls.has(s):
			var b := _ensure_ball(s)
			b.place(_tee_spot(want.find(s), maxi(want.size(), 4)))
	for s in balls.keys():
		if not want.has(int(s)):
			_remove_ball(int(s))


## Host: the VR golfer's putter, swing hits, teleport to the ball, the ghost-glove practice.
func _vr_golfer(delta: float) -> void:
	var holding := props.holding()
	putter.visible = not holding
	putter.follow(vr_rig.hand_r, 0.0, delta)
	vr_putt_cool = maxf(0.0, vr_putt_cool - delta)
	if not balls.has(0):
		return
	var b: Ball = balls[0]
	var to := course.aim_point(b.pos) - b.pos
	var fwd := Vector3(to.x, 0.0, to.y).normalized() if to.length() > 0.01 else Vector3.FORWARD
	if vr_rig.a_pressed() and b.state in ["rest", "roll"]:
		var feet := b.position - fwd * 0.5 + Vector3(-fwd.z, 0.0, fwd.x) * 0.2
		feet.y = 0.0
		vr_rig.place(feet, atan2(-fwd.x, -fwd.z))
		blink()
		sfx.play("teleport", -10.0)
	var playing := String(net.state_get("phase", "play")) == "play"
	if b.resting() and playing and not holding:
		vr_idle += delta
		var head := putter.head_pos
		var d := Vector2(b.pos.x - head.x, b.pos.y - head.z)
		var hv := Vector2(putter.head_vel.x, putter.head_vel.z)
		if vr_putt_cool <= 0.0 and d.length() < Course.BALL_R + 0.075 and hv.length() > 0.2 and hv.dot(d) > 0.0:
			var v := hv * VR_GAIN
			var ang := v.angle_to(to)
			if absf(ang) < 0.3:
				v = v.rotated(ang * 0.5)  # a little help for kids
			do_putt(0, v)
			putted[0] = true
			vr_idle = 0.0
			vr_putt_cool = 0.6
			vr_rig.pulse(VrRig.RIGHT, 0.8, 0.08)
	else:
		vr_idle = 0.0
	var demo := playing and b.resting() and not holding and (
		(int(net.state_get("hole", 0)) == 0 and not putted.has(0)) or vr_idle > 25.0)
	ghost.show_demo(demo, b.position, fwd, delta)


func on_spare_grabbed() -> void:
	putter.hide_now(true)


func on_spare_released() -> void:
	putter.hide_now(false)


func _end_course() -> void:
	var stars := 0
	var card: Dictionary = net.state_get("card", {})
	for s in card:
		for m in card[s]:
			if int(m) >= 2:
				stars += 1
	if stars > int(save.data["best_stars"]):
		save.data["best_stars"] = stars
		save.mark_dirty()
	var data := awards.results({"title": "WHAT A PARTY!", "style": "victory",
		"stats": [["STARS", str(stars)], ["BEST", str(int(save.data["best_stars"]))]], "score_format": "%d STARS"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


# --- Every machine: TV input, arrows, the board -----------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_tv_input(delta)
	_update_arrows()
	if prompt != null:
		var need := false
		for s in party.local_slots():
			if not putted.has(s):
				need = true
		prompt.visible = need and String(net.state_get("phase", "play")) == "play"
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()


func _tv_input(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "play")) == "play"
	for slot in party.local_slots():
		if not balls.has(slot):
			continue
		var b: Ball = balls[slot]
		sent_t[slot] = maxf(0.0, float(sent_t.get(slot, 0.0)) - delta)
		var resting: bool = (rest_flags.get(slot, false) if net.mode == "client" else b.resting()) and float(sent_t[slot]) <= 0.0
		var bp := Vector2(b.position.x, b.position.z)
		if resting and not bool(was_resting.get(slot, false)) or not aim.has(slot):
			aim[slot] = (course.aim_point(bp) - bp).angle()
		was_resting[slot] = resting
		if not resting or not playing:
			power[slot] = 0.0
		else:
			var st := party.stick(slot, "move")
			if st.length() > 0.35:
				aim[slot] = lerp_angle(float(aim[slot]), st.angle(), 1.0 - exp(-10.0 * delta))
			if party.pressed(slot, "accept"):
				power[slot] = minf(1.0, float(power.get(slot, 0.0)) + delta / CHARGE_TIME)
			elif float(power.get(slot, 0.0)) > 0.03:
				var v := Vector2.from_angle(float(aim[slot])) * (0.35 + float(power[slot]) * 3.6)
				power[slot] = 0.0
				putted[slot] = true
				sent_t[slot] = 0.5 if net.mode == "client" else 0.0
				net.request(slot, "putt", [v])
			else:
				power[slot] = 0.0
		if net.mode == "client" and send:
			net.send_state(Vector3(float(aim.get(slot, 0.0)), float(power.get(slot, 0.0)), 1.0 if resting and playing else 0.0), 0.0, 0.0, slot)


func _update_arrows() -> void:
	var show := {}
	for slot in party.local_slots():
		if balls.has(slot) and aim.has(slot):
			var resting: bool = rest_flags.get(slot, false) if net.mode == "client" else (balls[slot] as Ball).resting()
			if resting and float(sent_t.get(slot, 0.0)) <= 0.0 and String(net.state_get("phase", "play")) == "play":
				show[slot] = Vector2(float(aim[slot]), float(power.get(slot, 0.0)))
	if net.mode == "host":
		for slot in remote_aim:
			var ra: Vector3 = remote_aim[slot]
			if balls.has(slot) and ra.z > 0.5 and (balls[slot] as Ball).resting():
				show[slot] = Vector2(ra.x, ra.y)
	for slot in arrows.keys():
		if not show.has(slot):
			(arrows[slot] as Node3D).visible = false
	for slot in show:
		var a := _arrow(int(slot))
		var ap: Vector2 = show[slot]
		var b: Ball = balls[slot]
		a.visible = true
		a.position = b.position + Vector3(0.0, -Course.BALL_R + 0.012, 0.0)
		var dir := Vector2.from_angle(ap.x)
		a.rotation = Vector3(0.0, atan2(-dir.x, -dir.y), 0.0)
		var len := 0.25 + ap.y * 1.1
		a.scale = Vector3(1.0 + ap.y * 0.6, 1.0, len)
		var m: StandardMaterial3D = a.get_meta("mat")
		m.emission_energy_multiplier = 0.4 + ap.y * 2.5 + (0.3 * sin(Time.get_ticks_msec() * 0.008) if ap.y == 0.0 else 0.0)


func _arrow(slot: int) -> Node3D:
	if arrows.has(slot):
		return arrows[slot]
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.box(Vector3(0.035, 0.008, 0.75), MeshKit.at(Vector3(0.0, 0.0, -0.08 - 0.375)), Color.WHITE)
	b.polygon(PackedVector2Array([Vector2(-0.06, 0.0), Vector2(0.06, 0.0), Vector2(0.0, 0.14)]), 0.008,
		Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -0.82)), Color.WHITE)
	var mi := MeshKit.instance(b.build(), false)
	var col: Color = Party.COLORS[slot % Party.COLORS.size()]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.5
	mi.material_override = m
	n.set_meta("mat", m)
	n.add_child(mi)
	add_child(n)
	arrows[slot] = n
	return n


## The board over the hole: one row per player, a coloured ball then a flag or a star per hole.
func _refresh_board() -> void:
	if board == null:
		return
	for c in board.get_children():
		c.queue_free()
	var card: Dictionary = net.state_get("card", {})
	var slots: Array = []
	for s in balls:
		slots.append(int(s))
	for s in card:
		if not slots.has(int(s)):
			slots.append(int(s))
	slots.sort()
	var b := MeshKit.Builder.new()
	var rows := maxi(1, slots.size())
	var h := 0.2 * rows + 0.12
	b.box(Vector3(0.06, 1.2, 0.06), MeshKit.at(Vector3(-0.75, 0.6, -0.03)), Course.WOOD)
	b.box(Vector3(0.06, 1.2, 0.06), MeshKit.at(Vector3(0.75, 0.6, -0.03)), Course.WOOD)
	b.panel(Vector2(1.7, h), 0.06, MeshKit.at(Vector3(0.0, 1.2 + h * 0.5, -0.04)), Color(0.98, 0.95, 0.85))
	for r in slots.size():
		var s: int = slots[r]
		var y := 1.2 + h - 0.16 - r * 0.2
		b.sphere(0.06, MeshKit.at(Vector3(-0.68, y, 0.0)), Party.COLORS[s % Party.COLORS.size()], 10)
		var row: Array = card.get(s, [])
		for k in Course.HOLES:
			var m := int(row[k]) if k < row.size() else 0
			var x := -0.42 + k * 0.27
			if m >= 2:
				b.star(5, 0.08 if m == 3 else 0.065, 0.032, 0.02, MeshKit.at(Vector3(x, y, 0.0)), Color(1.0, 0.85, 0.2), m == 3)
			elif m == 1:
				b.box(Vector3(0.012, 0.15, 0.012), MeshKit.at(Vector3(x - 0.04, y, 0.0)), Color.WHITE)
				b.box(Vector3(0.09, 0.06, 0.012), MeshKit.at(Vector3(x + 0.005, y + 0.04, 0.0)), Color(1.0, 0.35, 0.35))
			else:
				b.sphere(0.02, MeshKit.at(Vector3(x, y, 0.0)), Color(0.75, 0.72, 0.65) if k != int(net.state_get("hole", 0)) else Color(0.4, 0.8, 0.45), 6)
	board.add_child(MeshKit.instance(b.build(), false))


# --- HUD (TV) -----------------------------------------------------------------------------------

func _make_hud(parent: Control) -> void:
	hud = UiKit.ui_root(parent)
	var card := UiKit.panel("card")
	hud.add_child(card)
	card.position = Vector2(24.0, 20.0)
	chips = UiKit.hbox()
	card.add_child(chips)
	prompt = UiKit.panel("pill")
	prompt.add_child(UiKit.prompts([["A", "Hold, let go!"]]))
	hud.add_child(prompt)
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt.offset_top = -60.0
	prompt.offset_bottom = -60.0
	join_prompt = UiKit.panel("pill")
	join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
	hud.add_child(join_prompt)
	join_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	join_prompt.offset_top = -60.0
	join_prompt.offset_bottom = -60.0
	_refresh_hud()


## Top-left: each player's colour and their stars so far (no numbers).
func _refresh_hud() -> void:
	if chips == null:
		return
	for c in chips.get_children():
		c.queue_free()
	var card: Dictionary = net.state_get("card", {})
	var slots: Array = []
	for s in balls:
		slots.append(int(s))
	slots.sort()
	for s in slots:
		var row := UiKit.hbox(4)
		row.add_child(UiKit.icon("dot", Party.COLORS[s % Party.COLORS.size()], 26.0))
		var marks: Array = card.get(s, [])
		for m in marks:
			if int(m) >= 2:
				row.add_child(UiKit.icon("star", "gold", 26.0))
			elif int(m) == 1:
				row.add_child(UiKit.icon("flag", "text", 22.0))
		chips.add_child(row)
		chips.add_child(UiKit.spacer(10.0))


# --- Store, results, pause -------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"hole":
			if net.mode == "client":
				_build_hole(int(value))
		"card":
			_refresh_board()
			_refresh_hud()
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
			if String(value) == "play":
				music.play_mood("town")


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	if split != null:
		var screen := Awards.results_screen(hud, data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "again"))
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
		card.continued.connect(func() -> void: net.request(0, "again"))
		vr_results = card


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
	vr_results = null


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


func on_pause_changed(paused: bool, _by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", "", {"width": 1.0})
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


# --- Networking ---------------------------------------------------------------------------

func make_snapshot() -> Array:
	var slots := PackedInt32Array()
	var pos := PackedVector3Array()
	var flags := PackedInt32Array()
	for s in balls:
		var b: Ball = balls[s]
		slots.append(int(s))
		pos.append(b.position)
		flags.append(1 if b.resting() else 0)
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var club := PackedVector3Array()
	if putter != null and putter.visible:
		club = PackedVector3Array([vr_rig.hand_r.global_position, putter.head_pos])
	return [pose, slots, pos, flags, course.mill_angle, props.spare_positions(), club]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	var slots: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var flags: PackedInt32Array = s[3]
	var seen := {}
	for i in slots.size():
		var slot := slots[i]
		seen[slot] = true
		var fresh := not balls.has(slot)
		var b := _ensure_ball(slot)
		b.target = pos[i]
		if fresh:
			b.position = pos[i]
			_refresh_hud()
			_refresh_board()
		rest_flags[slot] = flags[i] == 1
	for slot in balls.keys():
		if not seen.has(slot):
			_remove_ball(int(slot))
			_refresh_hud()
	course.mill_angle = float(s[4])
	props.set_spare_positions(s[5])
	var club: PackedVector3Array = s[6]
	putter.visible = club.size() == 2
	if club.size() == 2:
		putter.draw(club[0], club[1])


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"sink":
			celebrate(int(args[0]), args[1], int(args[2]))
		"prop":
			props.poke(String(args[0]))
