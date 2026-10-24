extends Node
## Headless bot for games/obstacle_rush. TV bots (BOT_PLAYERS, default 2) steer their runner with
## the stick and A, using the same route brain as the CPU runners. The fake VR giant (BOT_VR=1)
## grabs balls from the bucket and throws them (first at the practice target, then at runners),
## and pokes the spinner, pads, doors, flag and a runner with its gloves.
## Design check: every course gets finished on foot (not only by the hop-in), and the show ends
## with the results; the giant's practice target gets hit.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 15000 res://tests/obstacle_rush_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## OR_COURSE=n starts at course n (0..3).

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CpuBrain := preload("res://games/obstacle_rush/cpu_brain.gd")

var kit: BotKit
var main: Node
var want := 2
var brains := {}  # slot -> CpuBrain
var seen_courses := {}
var saw_results := false
var again_t := -1.0
var vr_step := "idle"
var vr_t := 0.0
var vr_throws := 0
var pokes := {}
var throw_to := Vector3.ZERO
var poke_i := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/obstacle_rush/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party))
	kit.every(4.0, _report)
	kit.every(0.5, _results)
	var end := 150.0 if host else (140.0 if client else 230.0)
	if OS.has_environment("BOT_END"):
		end = float(OS.get_environment("BOT_END"))
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _results() -> String:
	seen_courses[int(main.net.state_get("course", 0))] = true
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or (main.again_btn != null and main.again_btn.visible), "the AGAIN button shows in VR")
			again_t = kit.t
		if kit.t - again_t > 4.0:
			var slots: Array[int] = main.party.local_slots()
			if not slots.is_empty():
				kit.slot_press(main.party, slots[0], "accept")
			elif main.vr_rig != null:
				main.net.request(0, "again")
	return ""


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.course == null:
		return
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


## A TV bot: think like a CPU runner, then push the stick and press A like a person.
func _tv_bot(slot: int, delta: float) -> void:
	if not main.runners.has(slot):
		return
	var r = main.runners[slot]
	if not brains.has(slot):
		var b := CpuBrain.new()
		b.reset(slot * 17 + 3)
		brains[slot] = b
	var br: CpuBrain = brains[slot]
	br.think(r, main.course, delta)
	for e in r.events:
		if String(e[0]) == "fake" and int(e[1]) < main.course.doors.size():
			var d: Dictionary = main.course.doors[int(e[1])]
			br.bonked_door(float(d["x"]), float(d["z"]))
	var cam: Camera3D = main.split.active_camera(slot)
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var right := Vector3(-f.z, 0.0, f.x)
	var mv := Vector2(br.out_move.dot(right), br.out_move.dot(f))  # pad y DOWN is backwards
	kit.slot_stick(main.party, slot, "left", Vector2(mv.x, -mv.y))
	if br.out_jump:
		kit.slot_press(main.party, slot, "accept")


## Fake VR giant: throw balls (practice target first), then poke things.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	var g = main.giant
	rig.camera.position.y = 1.55 * g.S
	vr_t += delta
	match vr_step:
		"idle":
			if String(main.net.state_get("phase", "")) != "play":
				return
			if vr_t > 2.0 and main.course_t > 2.5:
				vr_step = "reach"
				vr_t = 0.0
		"reach":
			var i: int = g._free_ball()
			if i < 0:
				vr_step = "poke"
				return
			if kit.vr_reach(rig, VrRig.RIGHT, g.balls[i].global_position, 30.0, delta) or vr_t > 2.0:
				kit.vr_trigger(rig, 1.0)
				vr_step = "wind"
				vr_t = 0.0
				throw_to = main.course.target_pos if main.course.target != null else _runner_target()
		"wind":
			var hp: Vector3 = rig.hand_point(VrRig.RIGHT)
			kit.vr_reach(rig, VrRig.RIGHT, Vector3(hp.x, 1.0, 6.0), 30.0, delta)
			if vr_t > 0.4:
				vr_step = "throw"
				vr_t = 0.0
		"throw":
			# Swing towards the target fast enough for a lob (ball speed ~ hand speed * 0.85).
			var hp2: Vector3 = rig.hand_point(VrRig.RIGHT)
			var to: Vector3 = throw_to + Vector3(0.0, 4.0, 0.0) - hp2
			kit.vr_reach(rig, VrRig.RIGHT, hp2 + to.normalized() * 2.0, 16.0, delta)
			if vr_t > 0.12:
				kit.vr_trigger(rig, 0.0)
				if OS.has_environment("BOT_DEBUG"):
					kit.info("throw from %s hand v %s to %s" % [hp2, rig.hand_velocity(VrRig.RIGHT), throw_to])
					get_tree().create_timer(0.5).timeout.connect(func() -> void:
						for b in main.giant.balls:
							kit.info("  ball %s v %s" % [b.global_position, b.linear_velocity]))
				vr_throws += 1
				vr_step = "poke" if vr_throws % 3 == 0 else "idle"
				vr_t = 0.0
		"poke":
			var spot: Vector3 = _poke_spot()
			if spot == Vector3.INF:
				vr_step = "idle"
				return
			if kit.vr_reach(rig, VrRig.LEFT, spot, 25.0, delta) or vr_t > 2.5:
				if vr_t > 0.3:
					pokes[poke_i] = true
					poke_i += 1
					vr_step = "idle"
					vr_t = 0.0
					kit.vr_reach(rig, VrRig.LEFT, spot + Vector3(0, 4, 3), 1000.0, 1.0)


func _runner_target() -> Vector3:
	for r in main.runners.values():
		if not r.done and r.position.x > -8.0:
			return r.position + Vector3(1.5, 0.0, 0.0)
	return Vector3(0, 0, 0)


func _poke_spot() -> Vector3:
	var c = main.course
	match poke_i % 5:
		0:
			if c.spinner != null:
				return Vector3(0.0, 1.85, 0.0)
		1:
			if not c.pads.is_empty():
				return c.pads[0] + Vector3(0, 0.4, 0)
		2:
			if not c.doors.is_empty():
				return Vector3(float(c.doors[0]["x"]), 1.1, float(c.doors[0]["z"]))
		3:
			return c.flag.global_position + Vector3(0.6, 2.4, 0)
		4:
			for r in main.runners.values():
				return r.position + Vector3(0, 0.6, 0)
	poke_i += 1
	return Vector3(0, 6, 4)


func _report() -> String:
	var parts: Array[String] = []
	for rid in main.runners:
		var r = main.runners[rid]
		parts.append("%d:(%.0f,%.0f)%s" % [int(rid), r.position.x, r.position.y, "*" if r.done else ""])
	return "BOT %s: course %d phase %s t %.0f flags %d runners %s" % [main.net.mode, int(main.net.state_get("course", 0)),
		String(main.net.state_get("phase", "")), main.course_t, int(main.net.state_get("flags", 0)), " ".join(parts)]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(seen_courses.size() >= 3, "%s: played through several courses (%d)" % [mode, seen_courses.size()])
	if mode == "client":
		kit.assert_true(main.runners.size() >= 3, "client mirrors the runners (%d)" % main.runners.size())
		kit.assert_true(main.course.checkpoints.size() > 0, "client built the course")
		return
	kit.assert_true(saw_results, "%s: the show ended with the results" % mode)
	var natural := {}
	var log_by_course := {}
	for e in main.finish_log:
		var c: int = e[0]
		if bool(e[2]):
			natural[c] = int(natural.get(c, 0)) + 1
		if not log_by_course.has(c):
			log_by_course[c] = []
		(log_by_course[c] as Array).append("%d%s@%.0f" % [int(e[1]), "" if bool(e[2]) else "(hop)", float(e[3])])
	for c in log_by_course:
		kit.info("course %d finishes: %s" % [int(c), str(log_by_course[c])])
	for c in range(int(OS.get_environment("OR_COURSE")) if OS.has_environment("OR_COURSE") else 0, 4):
		if log_by_course.has(c):
			kit.assert_true(int(natural.get(c, 0)) >= 1, "course %d is finishable on foot" % c)
	if main.vr_rig != null:
		kit.assert_true(vr_throws > 0, "the fake VR giant threw balls (%d)" % vr_throws)
		kit.assert_true(main.ghost.shown, "the ghost glove showed the throw")
		if not OS.has_environment("OR_COURSE"):
			kit.assert_true(int(main.net.state_get("target_hit", 0)) > 0, "the practice target got hit")
		kit.assert_true(pokes.size() >= 3, "the giant poked things (%d)" % pokes.size())
