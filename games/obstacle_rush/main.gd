extends Node3D
## OBSTACLE RUSH: a bouncy toy obstacle course on a picnic table.
## - TV players (slots 1..6, or 0 too in local play without a headset) are wobbly jelly-bean RUNNERS:
##   left stick runs, A jumps. Get to the finish flag! A bonk is a comical tumble; falling off just
##   pops you back at the last checkpoint with a boing. Nobody is ever out.
## - The VR player (slot 0, host) is the GIANT at the side of the table: grab bouncy balls from the
##   bucket by your right hip (right trigger) and throw them at the runners; touch anything to play
##   with it (boop runners, hold or spin the spinner, poke bounce pads, lift doors, flick the flag).
##   Left stick walks along the table. (giant.gd)
## - Four short courses, one new thing each (course.gd): gaps, a spinner, bounce pads, doors (some
##   are pretend), then the golden crown. When everyone is at the flag: cheers, confetti, a flag on the
##   board goes up, next course. No timers, no numbers: four flags show how far the show has got.
##   Stragglers hop to the finish by themselves after a while, so nobody waits long.
## - PRACTICE (the first course): the TV runners get a glowing ring over the first gap; the giant gets
##   a glowing target on the course and a see-through ghost glove that shows the throw (ghost_hand.gd).
## - Text: the TV shows one short line at most (A Jump!, the course name); VR gets one short headline.
## - CPU runners fill up to three runners (solo VR: the giant plays with three CPU runners).
## Modes as in games/engine_template: local (split screen without a headset), host (VR on the Steam
## Frame, simulates everything), client (the TV machine: its runners move locally and instantly, the
## rest is mirrored from snapshots).

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
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const Course := preload("res://games/obstacle_rush/course.gd")
const Runner := preload("res://games/obstacle_rush/runner.gd")
const RunnerLook := preload("res://games/obstacle_rush/runner_look.gd")
const CpuBrain := preload("res://games/obstacle_rush/cpu_brain.gd")
const Giant := preload("res://games/obstacle_rush/giant.gd")
const GhostHand := preload("res://games/obstacle_rush/ghost_hand.gd")

const GAME_ID := "obstacle_rush"
const MIN_RUNNERS := 3
const HOP_IN_TIME := 70.0  ## after this, runners still on the course hop to the flag by themselves
const AFTER_FIRST := 35.0  ## ... or this long after the first person got there

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
var giant: Giant
var ghost: GhostHand
var runners := {}  ## rid -> Runner (slot 0..6 people, 10+ CPU)
var brains := {}  ## rid -> CpuBrain (host)
var cams := {}  ## slot -> CameraRig
var huds := {}  ## slot -> UiKit root (-1 = shared view)
var flag_rows := {}  ## slot -> HBoxContainer
var prompts := {}  ## slot -> Control ("A Jump!")
var join_prompt: Control
var jumped := {}  ## slot -> true once they jumped (the A prompt goes away)
var ring_done := {}  ## rid -> true (practice ring)
var board: Node3D  ## the four course flags behind the course
var board_flags: Array[Node3D] = []
var course_t := 0.0
var first_t := -1.0
var phase_t := 0.0
var send_t := 0.0
var finish_log: Array = []  ## [course, rid] (bots)
var headline: Label3D
var headline_t := 0.0
var again_btn: Node3D
var results_ui: Control
var tv_banner: Control
var built_key := Vector2i(-1, -1)


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
	save.defaults = {"crowns": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("party")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("speedy", "SPEEDY BEAN", "First to the flag %s times", "firsts")
	awards.define("bouncy", "BOUNCIEST", "%s big bonks", "tumbles", "max", 2.0)
	awards.define("hopper", "HOP STAR", "%s jumps", "jumps", "max", 5.0)
	awards.define("thrower", "BALL WIZARD", "%s bonks with a ball", "bonks")
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
	_build_world(vr_rig != null)
	giant = Giant.new()
	add_child(giant)
	giant.setup(self, vr_rig, mode != "client")
	if vr_rig != null:
		ghost = GhostHand.new()
		ghost.giant = giant
		add_child(ghost)
	if mode != "host":
		split = SplitView.new()
		split.camera_far = 900.0
		add_child(split)
		split.bind_party(party)
		var sc := split.shared_camera()
		sc.global_position = Vector3(-6.0, 14.0, 22.0)
		sc.look_at(Vector3(1.0, 0.0, 0.0), Vector3.UP)
		_make_hud(-1, split.shared_hud())
		if mode == "client":
			giant.make_avatar()
			split.set_bubble(VrRig.build_mirror(self, giant.avatar_head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	if mode != "client":
		_start_show()
	elif net.state_has("course"):
		_build_course(int(net.state_get("course", 0)), int(net.state_get("seed", 1)))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Obstacle Rush: %s mode%s" % [mode, " with a VR giant" if vr_rig != null else ""])


# --- World ------------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	var ty := Giant.TABLE_Y
	var floor_y := ty - 0.8 * Giant.S
	# The picnic table (with a gingham cloth) and the lawn far below: one mesh each.
	var b := MeshKit.Builder.new()
	b.box(Vector3(36.0, 0.8, 15.0), MeshKit.at(Vector3(0, ty - 0.4, -1.0)), Color(0.72, 0.5, 0.32))
	for i in 12:
		for j in 5:
			if (i + j) % 2 == 0:
				b.box(Vector3(3.0, 0.02, 3.0), MeshKit.at(Vector3(-16.5 + i * 3.0, ty + 0.01, -7.0 + j * 3.0)), Color(1.0, 0.55, 0.6))
	b.box(Vector3(36.0, 0.015, 15.0), MeshKit.at(Vector3(0, ty + 0.005, -1.0)), Color(0.98, 0.95, 0.92))
	for sx in [-16.0, 16.0]:
		for sz in [-7.0, 5.0]:
			b.box(Vector3(1.2, 0.8 * Giant.S - 0.8, 1.2), MeshKit.at(Vector3(sx, (floor_y + ty - 0.8) * 0.5, sz)), Color(0.6, 0.42, 0.27))
	add_child(MeshKit.instance(b.build()))
	var table := StaticBody3D.new()
	table.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(36.0, 0.8, 15.0)
	cs.shape = bs
	cs.position = Vector3(0, ty - 0.4, -1.0)
	table.add_child(cs)
	add_child(table)
	var lawn := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 260.0
	disc.bottom_radius = 260.0
	disc.height = 0.5
	disc.radial_segments = 32
	lawn.mesh = disc
	lawn.material_override = MeshKit.material(Color(0.45, 0.72, 0.36))
	lawn.position.y = floor_y - 0.25
	add_child(lawn)
	var trees := MeshKit.scatter_random(MeshKit.prop("tree"), 16, Vector3(0, floor_y, 0), 170.0, 60.0, 7.0, 11.0, PackedColorArray(), 3)
	add_child(trees)
	var bushes := MeshKit.scatter_random(MeshKit.prop("bush"), 14, Vector3(0, floor_y, 0), 55.0, 30.0, 6.0, 9.0, PackedColorArray(), 4)
	add_child(bushes)
	course = Course.new()
	course.name = "Course"
	add_child(course)
	_build_board()


## Four flags on poles behind the course: one goes up for every course done (every machine).
func _build_board() -> void:
	board = Node3D.new()
	board.position = Vector3(0.0, Giant.TABLE_Y, -6.2)
	add_child(board)
	for k in Course.COUNT:
		var pole := MeshKit.Builder.new()
		var x := -6.0 + k * 4.0
		pole.cylinder(0.09, 0.12, 7.5, MeshKit.at(Vector3(x, 3.75, 0)), Color(0.98, 0.97, 0.94), 8)
		pole.sphere(0.25, MeshKit.at(Vector3(x, 7.6, 0)), Color(1.0, 0.85, 0.3), 10)
		board.add_child(MeshKit.instance(pole.build()))
		var f := Node3D.new()
		f.position = Vector3(x, 1.2, 0)
		board.add_child(f)
		var fb := MeshKit.Builder.new()
		fb.box(Vector3(1.6, 1.0, 0.06), MeshKit.at(Vector3(0.82, 0, 0)), Course.CANDY[k])
		fb.star(5, 0.3, 0.13, 0.08, MeshKit.at(Vector3(0.82, 0, 0.04)), Color(1.0, 0.95, 0.5), true)
		f.add_child(MeshKit.instance(fb.build()))
		board_flags.append(f)


func _update_board(delta: float) -> void:
	var done := int(net.state_get("flags", 0))
	var t := Time.get_ticks_msec() * 0.001
	for k in board_flags.size():
		var f := board_flags[k]
		var want := 6.6 if k < done else 1.2
		f.position.y = lerpf(f.position.y, want, 1.0 - exp(-2.5 * delta))
		f.rotation.y = sin(t * 3.0 + k) * (0.25 if k < done else 0.05)
		f.scale = Vector3.ONE * (1.0 + (sin(t * 5.0) * 0.08 if k == int(net.state_get("course", 0)) and k >= done else 0.0))


# --- The show (host / local decide; every machine builds the course from "course" + "seed") ------

func _start_show() -> void:
	awards.reset()
	net.state_set("flags", 0)
	var first := 0
	if OS.has_environment("OR_COURSE") and not has_meta("started"):
		first = clampi(int(OS.get_environment("OR_COURSE")), 0, Course.COUNT - 1)
	set_meta("started", true)
	_go_course(first)


func _go_course(i: int) -> void:
	course_t = 0.0
	first_t = -1.0
	var seed_value := randi() % 100000 + 1
	net.state_set("done", {})
	net.state_set("phase", "play")
	net.state_set("seed", seed_value)
	net.state_set("course", i)
	_build_course(i, seed_value)


func _build_course(i: int, seed_value: int) -> void:
	built_key = Vector2i(i, seed_value)
	course.build(i, seed_value)
	ring_done.clear()
	var n := 0
	var ids := runners.keys()
	ids.sort()
	for rid in ids:
		var r: Runner = runners[rid]
		r.done = false
		r.checkpoint = 0
		if r.owned:
			r.place(course.start_spot(n, ids.size()))
		n += 1
		if brains.has(rid):
			(brains[rid] as CpuBrain).reset(int(rid) * 31 + seed_value)
	if split != null and i > 0:
		HudKit.banner(_all_huds(), Course.NAMES[i], "", {"duration": 1.8})
	if vr_rig != null:
		show_headline("THROW A BALL!" if i == 0 else Course.NAMES[i] + "!")
	for slot in cams:
		var c: CameraRig = cams[slot]
		c.yaw = -PI * 0.5
		c.snap()
	music.play_mood("party")


## Host: the runners who should exist: everyone seated plus CPU runners to make MIN_RUNNERS.
func _sync_runners() -> void:
	var want: Array[int] = []
	for s in party.active_slots():
		if s != 0 or vr_rig == null:
			want.append(s)
	var cpus := maxi(0, MIN_RUNNERS - want.size())
	for k in cpus:
		want.append(10 + k)
	for rid in want:
		if not runners.has(rid):
			var owned := rid >= 10 or party.is_local(rid)
			var r := _make_runner(rid, owned)
			if owned:
				var p := course.start_spot(runners.size() - 1, maxi(want.size(), 3))
				if course_t > 3.0:
					p = course.checkpoint_spot(0, rid)
				r.place(p)
	for rid in runners.keys():
		if not want.has(int(rid)):
			_remove_runner(int(rid))


func _make_runner(rid: int, owned: bool) -> Runner:
	var r := Runner.new()
	r.main = self
	r.rid = rid
	r.owned = owned
	r.is_cpu = rid >= 10
	r.speed_scale = 0.85 if rid >= 10 else 1.0
	if rid >= 10:
		r.look = RunnerLook.cpu_look(rid - 10)
	else:
		r.look = RunnerLook.player_look(rid, party.name_of(rid), party.color_of(rid))
	r.name = "Runner%d" % rid
	add_child(r)
	r.place(course.start_spot(0, 1))
	runners[rid] = r
	if rid >= 10 and net.mode != "client":
		var br := CpuBrain.new()
		br.reset(rid * 31 + int(net.state_get("seed", 1)))
		brains[rid] = br
	if rid < 10:
		if vr_rig == null:
			HudKit.nameplate(r, party.name_of(rid), rid, 1.75, 0.3)
		awards.set_player(rid, party.name_of(rid))
		if party.is_local(rid) and split != null:
			_add_view(rid, r)
	return r


func _remove_runner(rid: int) -> void:
	if runners.has(rid):
		(runners[rid] as Node).queue_free()
		runners.erase(rid)
	brains.erase(rid)
	if cams.has(rid):
		(cams[rid] as Node).queue_free()
		cams.erase(rid)
	if huds.has(rid):
		var h: Control = huds[rid]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(rid)
	flag_rows.erase(rid)
	prompts.erase(rid)


func _add_view(slot: int, r: Runner) -> void:
	var c := CameraRig.new()
	c.camera = split.camera(slot)
	c.party = party
	c.slot = slot
	c.pivot_height = 1.1
	c.distance = 6.0
	c.pitch = -0.38
	c.yaw = -PI * 0.5
	c.auto_behind = 1.2
	add_child(c)
	c.follow(r, 6.0, 0.0)
	cams[slot] = c
	_make_hud(slot, split.hud(slot))


## Runners still on the course (for the cloud's ball drops).
func runners_racing() -> Array:
	var out: Array = []
	for r in runners.values():
		if not (r as Runner).done:
			out.append(r)
	return out


func _name_of(rid: int) -> String:
	if rid >= 10:
		return RunnerLook.cpu_look(rid - 10)["name"]
	return party.name_of(rid)


# --- Players --------------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	if net.mode == "client":
		if party.is_local(slot) and not runners.has(slot):
			var r := _make_runner(slot, true)
			r.place(course.checkpoint_spot(0, slot))
	else:
		_sync_runners()
	sfx.play("ui_notify", -6.0)
	_refresh_hud()


func _on_player_left(slot: int) -> void:
	if net.mode == "client" or runners.has(slot):
		_remove_runner(slot)
	if net.mode != "client":
		_sync_runners()
	_refresh_hud()


# --- Host rules -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not ready_to_play:
		return
	if net.mode == "client":
		_step_owned(delta)
		return
	_sync_runners()
	var phase := String(net.state_get("phase", "play"))
	for rid in brains:
		var r: Runner = runners.get(rid)
		if r == null:
			continue
		var br: CpuBrain = brains[rid]
		br.think(r, course, delta)
		r.inp_move = br.out_move if phase == "play" else Vector3.ZERO
		if br.out_jump:
			r.inp_jump = true
	_step_owned(delta)
	course.step(delta, runners.values())
	giant.step(delta)
	if phase == "play":
		course_t += delta
		_finish_rules()
	elif phase == "cheer":
		phase_t += delta
		if phase_t > 4.0:
			var c := int(net.state_get("course", 0))
			if c + 1 >= Course.COUNT:
				_end_show()
			else:
				_go_course(c + 1)
	elif phase == "results":
		phase_t += delta
		if phase_t > 45.0:
			_start_show()


## Every machine: TV pads drive their own runners; owned runners move here.
func _step_owned(delta: float) -> void:
	var playing := String(net.state_get("phase", "play")) == "play"
	for slot in party.local_slots():
		if not runners.has(slot):
			continue
		var r: Runner = runners[slot]
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		var dir := Vector3.ZERO
		if mv.length() > 0.15 and split != null:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var right := Vector3(-f.z, 0.0, f.x)
			dir = (right * mv.x - f * mv.y).limit_length(1.0)
		r.inp_move = dir
		if playing and party.just_pressed(slot, "accept"):
			r.inp_jump = true
	for rid in runners:
		var r: Runner = runners[rid]
		if not r.owned:
			continue
		r.step(delta)
		for e in r.events:
			_runner_event(r, e)
		r.events.clear()
		_practice_ring(r)
	send_t -= delta
	if net.mode == "client" and send_t <= 0.0:
		send_t = 1.0 / 30.0
		for slot in party.local_slots():
			if runners.has(slot):
				var r: Runner = runners[slot]
				net.send_state(r.position, r.rotation.y, 1.0 if r.tumble_t > 0.0 else 0.0, slot)


func _runner_event(r: Runner, e: Array) -> void:
	var p := r.position
	match String(e[0]):
		"jump":
			_local_sound("jump", p, -10.0, randf_range(1.1, 1.3))
			if r.rid < 10:
				jumped[r.rid] = true
				_tell_host(r.rid, "stat", ["jumps"])
		"land":
			_local_sound("land", p, -16.0, 1.4)
		"pad":
			_local_sound("boing", p, -2.0, 1.0)
		"fell":
			_local_sound("boing", p, -2.0, 0.8)
		"bonk":
			_local_sound("crowd_oh", p, -10.0, 1.2)
			_local_sound("bounce", p, -4.0, 1.3)
			_tell_host(r.rid, "stat", ["tumbles"])
		"boop":
			_local_sound("pop", p, -6.0, 1.6)
		"fake":
			_local_sound("boing", p, 0.0, 0.7)
			var k := int(e[1])
			course.wobble_door(k)
			if brains.has(r.rid) and k < course.doors.size():
				(brains[r.rid] as CpuBrain).bonked_door(float(course.doors[k]["x"]), float(course.doors[k]["z"]))


## A runner's sound: played here, and passed on so the other machine hears it too.
func _local_sound(n: String, p: Vector3, db: float, pitch: float) -> void:
	if net.mode == "client":
		sfx.play_at(n, p, db, pitch)
		net.request(party.local_slots()[0] if not party.local_slots().is_empty() else 1, "snd", [n, p, db, pitch])
	else:
		sound_at(n, p, db, pitch)


func _tell_host(rid: int, action: String, args: Array) -> void:
	if net.mode == "client":
		net.request(rid, action, args)
	elif rid < 10:
		awards.add(rid, String(args[0]))


## TV practice: fly through the glowing ring over the first gap.
func _practice_ring(r: Runner) -> void:
	if course.ring == null or ring_done.has(r.rid):
		return
	if r.position.distance_to(course.ring_pos - Vector3(0.0, 0.55, 0.0)) < 1.0:
		ring_done[r.rid] = true
		_local_sound("ding", course.ring_pos, -2.0, 1.2)
		confetti(course.ring_pos, r.look.get("color", Color.WHITE), 20)


## Host: who reached the flag; stragglers hop in after a while.
func _finish_rules() -> void:
	var done: Dictionary = net.state_get("done", {})
	var changed := false
	var all_in := true
	for rid in runners:
		var r: Runner = runners[rid]
		if done.has(rid):
			continue
		var late := course_t > HOP_IN_TIME or (first_t >= 0.0 and course_t - first_t > AFTER_FIRST)
		var natural := course.finished(r.position)
		if natural or late:
			if not natural:
				_warp(r, Vector3(11.0, course.finish_y + 0.5, 0.0))
			done = done.duplicate()
			done[rid] = done.size()
			changed = true
			if done.size() == 1 and rid < 10:
				awards.add(rid, "firsts")
			if rid < 10 and first_t < 0.0:
				first_t = course_t
			if rid < 10:
				awards.add(rid, "stars")
			finish_log.append([int(net.state_get("course", 0)), int(rid), natural, course_t])
			_celebrate_finish(int(rid))
		else:
			all_in = false
	if changed:
		net.state_set("done", done)
	# The practice course waits for the giant's first good throw (not too long, though).
	if vr_rig != null and course.target != null and course_t < 25.0:
		all_in = false
	if all_in and not runners.is_empty():
		net.state_set("flags", int(net.state_get("course", 0)) + 1)
		net.state_set("phase", "cheer")
		phase_t = 0.0
		sound_at("applause", Vector3(10.0, 2.0, 0.0), -2.0)
		sound_at("fanfare", Vector3(10.0, 2.0, 0.0), -4.0)
		if vr_rig != null:
			vr_rig.pulse(VrRig.RIGHT, 0.6, 0.2)
			vr_rig.pulse(VrRig.LEFT, 0.6, 0.2)


func _warp(r: Runner, p: Vector3) -> void:
	if r.owned:
		r.place(p)
	else:
		net.event("warp", [r.rid, p])
	sound_at("boing", p, -4.0, 1.3)


func _celebrate_finish(rid: int) -> void:
	var r: Runner = runners.get(rid)
	if r == null:
		return
	var col: Color = r.look.get("color", Color.WHITE)
	var p := Vector3(Course.FINISH_X, course.finish_y + 3.4, 0.0)
	confetti(p, col, 36)
	sound_at("cheer", p, -4.0)
	sound_at("party_horn", p, -8.0)
	if net.mode == "host":
		net.event("confetti", [p, col, 36])


## Host: a ball hit a runner.
func bonk_runner(rid: int, v: Vector3, _ball: int) -> void:
	var r: Runner = runners.get(rid)
	if r == null:
		return
	if vr_rig != null:
		awards.add(0, "bonks")
		vr_rig.pulse(VrRig.RIGHT, 0.5, 0.08)
	sound_at("ball_hit", r.position, -2.0, 1.1)
	if r.owned:
		r.bonk(v, 1.0)
	else:
		net.event("knock", [rid, v])


## Host: the giant's finger touched a runner.
func boop_runner(rid: int) -> void:
	var r: Runner = runners.get(rid)
	if r == null:
		return
	if r.owned:
		r.boop()
	else:
		net.event("boop", [rid])
		sound_at("pop", r.position, -6.0, 1.6)


func on_course_touch(what: String, p: Vector3) -> void:
	match what:
		"spin":
			sound_at("whoosh", p, -4.0, 0.9)
		"pad":
			sound_at("boing", p, -4.0, 1.2)
		"door":
			sound_at("door", p, -6.0, 1.3)
		"flag":
			sound_at("swish", p, -6.0)
			confetti(p, Color(1.0, 0.4, 0.5), 16)
			if net.mode == "host":
				net.event("confetti", [p, Color(1.0, 0.4, 0.5), 16])


## Host: the again button (results) can be touched too.
func touch_extra(_hand: int, p: Vector3, now: Dictionary, before: Dictionary) -> void:
	if again_btn != null and again_btn.visible and p.distance_to(again_btn.global_position) < 1.4:
		now["again"] = true
		if not before.has("again"):
			sound_at("ui_select", p, -2.0)
			on_request(0, "again", [])


func on_throw() -> void:
	pass


## Host: a ball landed on the practice target.
func target_hit(p: Vector3) -> void:
	if course.target == null:
		return
	course.target.queue_free()
	course.target = null
	net.state_set("target_hit", int(net.state_get("target_hit", 0)) + 1)
	sound_at("sparkle", p, 0.0)
	sound_at("ding", p, -2.0, 1.4)
	confetti(p, Color(1.0, 0.9, 0.3), 40)
	if net.mode == "host":
		net.event("confetti", [p, Color(1.0, 0.9, 0.3), 40])
		net.event("target", [])
	if vr_rig != null:
		vr_rig.pulse(VrRig.RIGHT, 0.8, 0.12)
		show_headline("YES!")


func _end_show() -> void:
	save.data["crowns"] = int(save.data["crowns"]) + 1
	save.mark_dirty()
	var data := awards.results({"title": "WHAT A SHOW!", "style": "victory", "score_stat": "stars",
		"score_format": "%d STARS", "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	if net.mode == "host":
		net.event("sfx", [n, p, db, pitch])


## Every machine: a burst of confetti.
func confetti(p: Vector3, col: Color, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = amount
	cp.lifetime = 1.4
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 50.0
	cp.initial_velocity_min = 4.0
	cp.initial_velocity_max = 8.0
	cp.gravity = Vector3(0.0, -9.0, 0.0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 0.03)
	bm.material = MeshKit.vertex_material(true)
	cp.mesh = bm
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.7), Color(0.5, 0.9, 1.0)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	cp.color_initial_ramp = g
	add_child(cp)
	cp.position = p
	cp.emitting = true
	get_tree().create_timer(1.8).timeout.connect(cp.queue_free)


## Host / local: a player asked for something (from any machine).
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"again":
			if String(net.state_get("phase", "")) == "results":
				_start_show()
		"snd":
			if args.size() >= 4:
				sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"stat":
			if args.size() >= 1 and slot < 10:
				awards.add(slot, String(args[0]))


## Host: a TV player's runner moved on the TV machine.
func on_remote_state(slot: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if runners.has(slot):
		(runners[slot] as Runner).set_remote(pos, yaw, 1 if pitch > 0.5 else 0)


# --- Every machine: animation, VR extras, HUD ------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	for r in runners.values():
		(r as Runner).animate(delta)
	if net.mode == "client":
		course.animate(delta, runners.values())
	_update_board(delta)
	_headline(delta)
	if ghost != null:
		_ghost(delta)
	if again_btn != null and again_btn.visible:
		again_btn.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08)
	for slot in prompts:
		var pr: Control = prompts[slot]
		if is_instance_valid(pr):
			pr.visible = not jumped.has(slot) and String(net.state_get("phase", "play")) == "play"
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()


func _ghost(delta: float) -> void:
	var playing := String(net.state_get("phase", "play")) == "play"
	var first := int(net.state_get("course", 0)) == 0 and course.target != null and giant.throws == 0
	var idle := giant.throws > 0 and giant.last_throw_t > 30.0
	var on := playing and giant.held < 0 and (first or idle) and course_t > 1.5
	var to := course.target_pos if course.target != null else Vector3(vr_rig.head_position().x, 0.3, 0.0)
	ghost.show_demo(on, giant._home_spot(0), to, delta)


## VR: one short headline, far away over the course, facing the giant (turned on Y only).
func show_headline(text: String) -> void:
	if vr_rig == null:
		return
	if headline == null:
		headline = Label3D.new()
		headline.font_size = 96
		headline.outline_size = 26
		headline.modulate = Color(1.0, 0.92, 0.35)
		headline.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		headline.double_sided = false
		headline.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(headline)
	headline.text = text
	headline.visible = true
	headline_t = 3.0
	var cam := vr_rig.camera
	var f := vr_rig.head_forward()
	headline.pixel_size = 0.0035 * Giant.S
	headline.global_position = cam.global_position + f * 2.6 * Giant.S + Vector3.UP * 0.2 * Giant.S
	var d := headline.global_position - cam.global_position
	headline.global_basis = Basis(Vector3.UP, atan2(-d.x, -d.z))


func _headline(delta: float) -> void:
	if headline == null or not headline.visible or headline_t < 0.0:
		return
	headline_t -= delta
	if headline_t <= 0.0:
		headline.visible = false


func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var row := UiKit.hbox(6)
	card.add_child(row)
	flag_rows[slot] = row
	if slot >= 0:
		var pr := UiKit.panel("pill")
		pr.add_child(UiKit.prompts([["A", "Jump!"]]))
		ui.add_child(pr)
		_bottom(pr)
		prompts[slot] = pr
	else:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		_bottom(join_prompt)
	_refresh_hud()


func _bottom(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_top = -60.0
	c.offset_bottom = -60.0


## Top-left on every view: the four course flags (gold = done). No numbers.
func _refresh_hud() -> void:
	var done := int(net.state_get("flags", 0))
	for slot in flag_rows:
		var row: HBoxContainer = flag_rows[slot]
		if not is_instance_valid(row):
			continue
		for c in row.get_children():
			c.queue_free()
		for k in Course.COUNT:
			row.add_child(UiKit.icon("flag", "gold" if k < done else "dim", 28.0))


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


# --- Store, results, pause ----------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"course", "seed":
			var k := Vector2i(int(net.state_get("course", 0)), int(net.state_get("seed", 1)))
			if net.mode == "client" and k != built_key:
				_build_course(k.x, k.y)
		"flags":
			_refresh_hud()
		"done":
			var d: Dictionary = value if value is Dictionary else {}
			for rid in runners:
				var r: Runner = runners[rid]
				var was := r.done
				r.done = d.has(rid)
				if r.done and not was and r.owned:
					r.inp_move = Vector3.ZERO
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
			if String(value) == "cheer":
				music.play_mood("victory")
				if vr_rig != null:
					show_headline("HOORAY!")


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	for r in runners.values():
		var rn: Runner = r
		confetti(rn.position + Vector3(0, 2, 0), rn.look.get("color", Color.WHITE), 20)
	if split != null:
		var screen := Awards.results_screen(huds[-1], data, {"party": party, "min_time": 5.0})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "again"))
		results_ui = screen
	if vr_rig != null:
		show_headline("WHAT A SHOW!")
		headline_t = 6.0
		if again_btn == null:
			again_btn = Node3D.new()
			var b := MeshKit.Builder.new()
			b.cylinder(1.0, 1.1, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.3, 0.9, 0.4), 20, true)
			b.cylinder(1.3, 1.3, 0.25, MeshKit.at(Vector3(0, 0.0, 0)), Color(0.98, 0.97, 0.94), 20)
			again_btn.add_child(MeshKit.instance(b.build()))
			add_child(again_btn)
		again_btn.visible = true
		var hp := vr_rig.head_position()
		again_btn.global_position = Vector3(hp.x - 2.5, Giant.TABLE_Y, 4.2)


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if again_btn != null:
		again_btn.visible = false


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


func on_pause_changed(paused: bool, _by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			show_headline("PAUSED")
			headline_t = -1.0
		elif headline != null:
			headline.visible = false
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


# --- Networking -----------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var st := PackedInt32Array()
	for rid in runners:
		var r: Runner = runners[rid]
		ids.append(int(rid))
		pos.append(r.position)
		yaw.append(r.rotation.y)
		st.append(1 if r.tumble_t > 0.0 else 0)
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	return [pose, ids, pos, yaw, st, giant.pack(), course.pack()]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var dt := get_process_delta_time()
	giant.apply_pose(s[0], 1.0)
	var ids: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var yaw: PackedFloat32Array = s[3]
	var st: PackedInt32Array = s[4]
	var seen := {}
	for i in ids.size():
		var rid := ids[i]
		seen[rid] = true
		if party.is_local(rid):
			continue
		if not runners.has(rid):
			var r := _make_runner(rid, false)
			r.position = pos[i]
			r.done = (net.state_get("done", {}) as Dictionary).has(rid)
		(runners[rid] as Runner).set_remote(pos[i], yaw[i], st[i])
	for rid in runners.keys():
		if not seen.has(rid) and not party.is_local(int(rid)):
			_remove_runner(int(rid))
	giant.unpack(s[5], dt)
	course.unpack(s[6], dt, runners.values())


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"confetti":
			confetti(args[0], args[1], int(args[2]))
		"knock":
			var r: Runner = runners.get(int(args[0]))
			if r != null and r.owned:
				r.bonk(args[1], 1.0)
		"boop":
			var r2: Runner = runners.get(int(args[0]))
			if r2 != null and r2.owned:
				r2.boop()
		"warp":
			var r3: Runner = runners.get(int(args[0]))
			if r3 != null and r3.owned:
				r3.place(args[1])
		"target":
			if course.target != null:
				course.target.queue_free()
				course.target = null
