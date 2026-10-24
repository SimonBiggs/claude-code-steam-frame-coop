extends Node
## Headless bot for games/mini_golf_party. TV bots (BOT_PLAYERS, default 2) aim with the stick at the
## hole's aim point and hold A for about the right power; the fake VR golfer (BOT_VR=1) teleports
## to its ball with A and swings the putter through it, and plays with the toys (duck, spare ball).
## Design check: every hole gets holed by the aiming bots within par + 3 on average.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 12000 res://tests/mini_golf_party_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## MGP_HOLE=n starts at hole n.

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

var kit: BotKit
var main: Node
var want := 2
var hold := {}  # slot -> seconds left holding A
var vr_step := "idle"
var vr_t := 0.0
var vr_speed := 1.0
var vr_putts := 0
var toy_step := 0
var saw_results := false
var holes_seen := {}
var again_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/mini_golf_party/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party))
	kit.every(3.0, _report)
	kit.every(0.5, _results)
	var end := 150.0 if host else (140.0 if client else 190.0)
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _results() -> String:
	holes_seen[int(main.net.state_get("hole", 0))] = true
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
			again_t = kit.t
		if kit.t - again_t > 3.0:
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


## Speed a putt needs to reach `to` from `from` on this hole.
func _speed_for(from: Vector2, to: Vector2) -> float:
	var c = main.course
	var d := from.distance_to(to)
	var v := sqrt(2.0 * 1.15 * d) + 0.15
	if c.gimmick == "hill" and from.y > c.hill_z - 0.2 and to.y < c.hill_z:
		v = sqrt(v * v + 2.0 * 9.8 * 5.0 / 7.0 * c.hill_h + 0.6)
	if c.gimmick == "loop" and from.y > c.loop_z:
		v = 3.6
	if c.gimmick == "windmill" and from.y > c.mill_z:
		v = maxf(v, 2.2)
	return minf(v, 3.9)


func _tv_bot(slot: int, delta: float) -> void:
	if not main.balls.has(slot):
		return
	var b = main.balls[slot]
	var arrow_on: bool = main.arrows.has(slot) and (main.arrows[slot] as Node3D).visible
	var bp := Vector2(b.position.x, b.position.z)
	var to: Vector2 = main.course.aim_point(bp)
	if hold.has(slot):
		hold[slot] = float(hold[slot]) - delta
		if float(hold[slot]) <= 0.0:
			kit.slot_hold(main.party, slot, "accept", false)
			hold.erase(slot)
		return
	if not arrow_on:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	# Point the stick at the target (pad y DOWN = +Z on this course), then charge.
	var dir := (to - bp).normalized()
	kit.slot_stick(main.party, slot, "left", dir)
	if absf(angle_difference(float(main.aim.get(slot, 0.0)), dir.angle())) > 0.05:
		return
	kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
	var v := _speed_for(bp, to)
	var p := clampf((v - 0.35) / 3.6, 0.05, 1.0)
	hold[slot] = p * main.CHARGE_TIME
	kit.slot_hold(main.party, slot, "accept", true)


## Fake VR golfer: A to stand behind the ball, wind back, swing through.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.5
	vr_t += delta
	_toys(rig, delta)
	if toy_step in [1, 2, 3]:
		return
	if not main.balls.has(0):
		return
	var b = main.balls[0]
	var bp := Vector2(b.pos.x, b.pos.y)
	var to: Vector2 = main.course.aim_point(bp)
	var fwd := Vector3(to.x - bp.x, 0.0, to.y - bp.y).normalized()
	var reach: float = main.putter.MAX_REACH
	match vr_step:
		"idle":
			if b.resting() and main.results_showing() == false and String(main.net.state_get("phase", "")) == "play":
				kit.vr_a(rig, true)
				vr_step = "teleport"
				vr_t = 0.0
		"teleport":
			kit.vr_a(rig, false)
			if vr_t > 0.3:
				vr_step = "wind"
				vr_t = 0.0
				vr_speed = _speed_for(bp, to) / main.VR_GAIN
		"wind":
			var start: Vector3 = b.position - fwd * (reach + 0.25)
			start.y = 0.8
			if kit.vr_reach(rig, VrRig.RIGHT, start, 1.5, delta) or vr_t > 2.0:
				vr_step = "swing"
				vr_t = 0.0
		"swing":
			var end: Vector3 = b.position - fwd * (reach - 0.3)
			end.y = 0.8
			kit.vr_reach(rig, VrRig.RIGHT, end, vr_speed, delta)
			if not b.resting():
				vr_putts += 1
				vr_step = "wait"
			elif vr_t > 2.0:
				vr_step = "idle"
		"wait":
			if b.resting() or b.state == "cup":
				vr_step = "idle"


## Once: poke the duck with the left glove, then throw a spare ball.
func _toys(rig, delta: float) -> void:
	var p = main.props
	match toy_step:
		0:
			if kit.t > 8.0 and main.vr_rig != null:
				toy_step = 1
				main.vr_rig.place(p.anchor + Vector3(0.6, 0.0, 0.4), 0.0)
		1:
			if kit.vr_reach(rig, VrRig.LEFT, p.duck.global_position + Vector3.UP * 0.15, 2.0, delta):
				toy_step = 2
		2:
			var s: Vector3 = p.spares[0].global_position
			if kit.vr_reach(rig, VrRig.RIGHT, s, 2.0, delta):
				kit.vr_trigger(rig, 1.0)
				toy_step = 3
				vr_t = 0.0
		3:
			kit.vr_reach(rig, VrRig.RIGHT, rig.hand_point(VrRig.RIGHT) + Vector3(0.0, 0.5, -1.0), 3.0, delta)
			if vr_t > 0.4:
				kit.vr_trigger(rig, 0.0)
				toy_step = 4
				vr_step = "idle"


func _report() -> String:
	var parts: Array[String] = []
	for s in main.balls:
		var b = main.balls[s]
		parts.append("%d:%s/%d" % [int(s), String(b.state), int(b.strokes)])
	return "BOT %s: hole %d phase %s balls %s" % [main.net.mode, int(main.net.state_get("hole", 0)) + 1,
		String(main.net.state_get("phase", "")), ", ".join(parts)]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(holes_seen.size() >= 3, "%s: played through several holes (%d)" % [mode, holes_seen.size()])
	if mode == "client":
		kit.assert_true(main.balls.size() >= want, "client mirrors the balls")
		return
	kit.assert_true(saw_results, "%s: the course ended with the results" % mode)
	# Design check: aiming bots hole out within par + 3 (6 putts = automatic pick-up).
	var per_hole := {}
	for e in main.sink_log:
		var h: int = e[0]
		if not per_hole.has(h):
			per_hole[h] = []
		(per_hole[h] as Array).append(int(e[2]))
	for h in per_hole:
		var arr: Array = per_hole[h]
		var tot := 0
		for n in arr:
			tot += int(n)
		var avg := float(tot) / arr.size()
		var par: int = main.Course.hole_def(int(h))["par"]
		kit.info("hole %d: putts %s (par %d)" % [int(h) + 1, str(arr), par])
		kit.assert_true(avg <= par + 3, "hole %d is completable within par+3 (avg %.1f)" % [int(h) + 1, avg])
	if main.vr_rig != null:
		kit.assert_true(vr_putts > 0, "the fake VR golfer putted with the club")
		kit.assert_true(main.ghost.shown, "the ghost glove showed the swing")
		kit.assert_true(main.props.touched.has("duck"), "the duck was poked")
		kit.assert_true(main.props.touched.has("spare"), "a spare ball was grabbed")
