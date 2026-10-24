extends Node
## Headless bot for games/paper_planes. TV bots steer their planes through the nearest hoop; with
## BOT_VR=1 (local / host) a fake VR player grabs planes (trigger and touching the stack) and throws
## them at the hoops with a flick.
## Local:      godot-test --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/paper_planes_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var vt := 0.0  # fake VR throw cycle clock
var left_test := 0  # 0 not yet, 1 reaching for the stack, 2 holding, 3 done
var left_grabbed := false
var left_thrown := false
var max_hoops := 0  # scored hoops respawn after 1.2 s, so the count dips right after a score


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/paper_planes/main.tscn").instantiate()
	main.set("round_time", 28.0)
	main.set("results_wait", 6.0)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host:
		kit.at(t0 + 8.0, "P1 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 8.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and main.tv_banner.visible, "Start pauses and shows the banner")
			_press("start"))
		kit.at(t0 + 9.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	if OS.has_environment("BOT_VR"):
		kit.at(12.0, "fake VR: left glove reaches for the paper stack", func() -> void: left_test = 1)
	kit.drop_in_out(main.party, t0 + 11.0, 3.0, func(slot: int) -> bool:
		return main.flyers.has(slot) and main.huds.has(slot))
	if host:
		kit.at(40.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(50.0, "finish", kit.finish)
	else:
		kit.at(44.0 if client else 37.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(3.0, _report)
	kit.every(0.5, _continue_results)


func _continue_results() -> String:
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.results_ui == null or (main.results_ui.get("data") as Dictionary).has("title"),
				"the results screen has the round's results")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
		_press("accept")
	return ""


func _join() -> void:
	if main.net.mode == "host":
		if main.flat_host:
			kit.join_bot(main.party)  # a flat host (DUO_FLAT_HOST=1): one pad player here, in slot 0
		return
	for i in want:
		kit.join_bot(main.party)


func _press(action: String) -> void:
	var slots: Array[int] = main.party.local_slots()
	if not slots.is_empty():
		kit.slot_press(main.party, slots[0], action)


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	max_hoops = maxi(max_hoops, main.hoops.size())
	for slot in main.party.local_slots():
		_steer(slot)
	if main.vr_rig != null:
		_drive_vr(delta)


## Turn the stick towards the hoop: first to a spot in front of it, then through the middle.
func _steer(slot: int) -> void:
	if not main.flyers.has(slot):
		return
	var f = main.flyers[slot]
	var p: Vector3 = f.node.position
	var best: Node3D = null
	var bd := INF
	for id in main.hoops:
		var hn: Node3D = main.hoops[id].node
		var dd := hn.position.distance_to(p)
		if dd < bd:
			bd = dd
			best = hn
	if best == null:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	var n: Vector3 = best.global_basis.z
	var side := signf((p - best.position).dot(n))
	if side == 0.0:
		side = 1.0
	var aim := best.position
	if bd > 3.5:
		aim += n * side * 3.0
	var d := aim - p
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var dy := wrapf(want_yaw - float(f.yaw), -PI, PI)
	var v := Vector2(-clampf(dy * 2.5, -1.0, 1.0), -clampf(want_pitch / 0.65, -1.0, 1.0))
	kit.slot_stick(main.party, slot, "left", v)


## Fake VR: every 2 s pull the trigger (a plane appears), wind up, flick at the nearest hoop.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position = Vector3(0.0, 1.6, 0.0)
	if left_test == 1 or left_test == 2:
		_left_hand_test(rig, delta)
		return
	vt += delta
	var target := _nearest_hoop(rig.head_position())
	var rh: Node3D = rig.hand_r
	if vt < 0.05:
		rh.position = Vector3(0.2, 1.3, -0.3)
		rh.basis = Basis()
		kit.vr_trigger(rig, 1.0)
	elif vt < 0.5:
		rh.position = rh.position.move_toward(Vector3(0.3, 1.5, 0.2), 2.5 * delta)
	elif vt < 0.68:
		var dir := Vector3(0.0, 0.0, -1.0)
		if target != Vector3.INF:
			dir = ((rig as Node3D).global_basis.inverse() * (target - rh.global_position)).normalized()
		rh.position += dir * 6.0 * delta
	elif vt < 0.75:
		kit.vr_trigger(rig, 0.0)
	elif vt > 2.0:
		vt = 0.0
	if target != Vector3.INF:
		kit.vr_look_at(rig, target)


## Touch the stack with the left glove (no buttons on the Frame's left hand), then flick it.
func _left_hand_test(rig: Node, delta: float) -> void:
	var lh: Node3D = rig.hand_l
	if left_test == 1:
		var top: Vector3 = main.stack_node.global_position + Vector3.UP * 0.95
		if kit.vr_reach(rig, VrRig.LEFT, top, 1.5, delta) or main.held[0] != null:
			if main.held[0] != null:
				left_grabbed = true
				left_test = 2
				vt = 0.0
	elif left_test == 2:
		vt += delta
		if vt < 0.4:
			lh.position = lh.position.move_toward(Vector3(-0.2, 1.4, 0.1), 2.0 * delta)
		else:
			lh.position += Vector3(0.1, 0.0, -1.0) * 6.0 * delta
			if main.held[0] == null:
				left_thrown = true
				left_test = 3
				vt = 0.0
				lh.position = Vector3(-0.25, 1.1, -0.3)
			elif vt > 1.2:
				left_test = 3
				vt = 0.0


func _nearest_hoop(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for id in main.hoops:
		var hn: Node3D = main.hoops[id].node
		if hn.position.z > from.z - 1.0:
			continue
		var dd := from.distance_to(hn.position)
		if dd < bd:
			bd = dd
			best = hn.position
	return best


func _report() -> String:
	return "BOT %s: players %s, hoops %d, darts %d, score %d, round %d, scored_by %s, throws %d" % [main.net.mode,
		str(main.party.active_slots()), main.hoops.size(), main.darts.size(), int(main.net.state_get("score", 0)),
		int(main.net.state_get("round", 0)), str(main.scored_by), main.throws]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(main.party.player_count(), want + host_p, "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.flyers.has(0) and main.huds.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	kit.assert_true(max_hoops >= 3, "%s: hoops are in the sky" % mode)
	var ghosts := 0
	for s in main.flyers:
		if not main.party.is_active(int(s)):
			ghosts += 1
	kit.assert_eq(ghosts, 0, "%s: no plane is left behind by a player who quit" % mode)
	if mode != "client":
		var tv := 0
		for s in main.scored_by:
			if int(s) > 0 or main.vr_rig == null:
				tv += int(main.scored_by[s])
		kit.assert_true(tv > 0, "%s: TV planes flew through hoops (%d)" % [mode, tv])
	else:
		kit.assert_true(main.flyers.size() == main.party.player_count(), "client: every player (every machine's) has a plane")
	if main.vr_rig != null:
		kit.assert_true(main.throws > 3, "fake VR threw planes (%d)" % main.throws)
		kit.assert_true(int(main.scored_by.get(0, 0)) > 0, "a VR plane went through a hoop (%d)" % int(main.scored_by.get(0, 0)))
		kit.assert_true(left_grabbed, "touching the stack with the left glove takes a plane")
		kit.assert_true(left_thrown, "a flick of the left glove throws it")
