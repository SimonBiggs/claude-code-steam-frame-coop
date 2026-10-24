extends Node
## Headless bot for games/bubble_bath. BOT_PLAYERS=n TV boats (default 2) collect ducks and sail them
## to the plug-hole. BOT_VR=1 (local / host): a fake VR player slaps the water with the left glove and
## grabs ducks with the right glove (trigger) and throws them at the plug-hole.
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/bubble_bath_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).

const BotKit := preload("res://tests/bot_kit.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var vr_phase := "seek"
var vr_t := 0.0
var vr_target: Node3D
var vr_throws := 0
var vr_splashes := 0
var slap_t := 0.0
var max_train := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/bubble_bath/main.tscn").instantiate()
	main.set("round_time", 16.0)  # short rounds: results and round 2 happen in the test
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	kit.at(t0 + 4.0, "P2 presses Y: one shared view", func() -> void: _press_y())
	kit.at(t0 + 5.0, "shared?", func() -> void:
		if main.split != null and not main.flat_host:
			kit.assert_true(main.split.is_shared(), "Y switched to the shared view"))
	kit.at(t0 + 8.0, "P2 presses Y again: split screen", func() -> void: _press_y())
	kit.at(t0 + 9.0, "split?", func() -> void:
		if main.split != null and not main.flat_host:
			kit.assert_true(not main.split.is_shared(), "Y switched back to split screen"))
	if not host:
		kit.at(t0 + 10.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 10.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and main.tv_banner.visible, "Start pauses the game")
			_press("start"))
		kit.at(t0 + 11.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused and not main.tv_banner.visible, "Start again resumes")
			kit.allow_pause = false)
	kit.drop_in_out(main.party, t0 + 12.0, 3.0, func(slot: int) -> bool:
		return main.boats.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		kit.at(34.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(38.0, "finish", kit.finish)
	else:
		kit.at(33.0 if client else 36.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
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


## The view (split / shared) is shared by every machine: on a flat host the client's Y presses toggle it too.
func _press_y() -> void:
	if not main.flat_host:
		_press("y")


func _press(action: String) -> void:
	var slots: Array[int] = main.party.local_slots()
	if not slots.is_empty():
		kit.slot_press(main.party, slots[0], action)


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	for slot in main.party.local_slots():
		_steer(slot)
	if main.vr_rig != null:
		_drive_vr(delta)
	for slot in main.trains:
		max_train = maxi(max_train, (main.trains[slot] as Array).size())


## Sail to the nearest duck; with 2+ ducks in tow (or none left), sail to the plug-hole.
func _steer(slot: int) -> void:
	if not main.boats.has(slot):
		return
	var b: Node3D = main.boats[slot]
	var target: Vector3 = main.DRAIN
	var train_n: int = (main.trains.get(slot, []) as Array).size() if main.net.mode != "client" else 0
	var duck := _nearest_duck(b.position, true)
	if duck != null and train_n < 2 and (main.net.mode != "client" or fmod(kit.t + slot, 8.0) < 5.0):
		target = duck.position
	var d := target - b.position
	d.y = 0.0
	var v := Vector2.ZERO
	if d.length() > 0.05 and main.split != null:
		d = d.normalized()
		var cam: Camera3D = main.split.active_camera(slot)
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		v = Vector2(d.dot(r), -d.dot(f))
	kit.slot_stick(main.party, slot, "left", v)


## Fake VR: slap the water with the left glove now and then; grab a duck with the right glove and
## fling it at the plug-hole.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	var head: Vector3 = rig.head_position()
	slap_t += delta
	var lp: Vector3 = rig.hand_point(0)
	if fmod(slap_t, 2.0) < 0.4:
		kit.vr_reach(rig, 0, Vector3(head.x - 0.3, main.WATER_Y - 0.15, head.z - 0.6), 4.0, delta)
	else:
		kit.vr_reach(rig, 0, Vector3(head.x - 0.3, main.WATER_Y + 0.3, head.z - 0.5), 4.0, delta)
	if lp.y < main.WATER_Y and fmod(slap_t, 2.0) < 0.1:
		vr_splashes += 1
	vr_t += delta
	match vr_phase:
		"seek":
			if vr_target == null or not is_instance_valid(vr_target) or vr_t > 4.0:
				vr_target = _nearest_duck(head, false)
				vr_t = 0.0
			if vr_target != null and kit.vr_reach(rig, 1, vr_target.position + Vector3.UP * 0.1, 4.0, delta):
				kit.vr_trigger(rig, 1.0)
				vr_phase = "grab"
				vr_t = 0.0
		"grab":
			if int(main.held) >= 0:
				vr_phase = "throw"
				vr_t = 0.0
			elif vr_t > 0.3:
				kit.vr_trigger(rig, 0.0)
				vr_phase = "seek"
				vr_t = 0.0
		"throw":
			var aim: Vector3 = main.DRAIN + Vector3.UP * 1.2
			kit.vr_reach(rig, 1, aim, 5.0, delta)
			if vr_t > 0.25:
				kit.vr_trigger(rig, 0.0)
				vr_throws += 1
				vr_phase = "rest"
				vr_t = 0.0
		"rest":
			kit.vr_reach(rig, 1, head + Vector3(0.25, -0.5, -0.35), 3.0, delta)
			if vr_t > 0.8:
				vr_phase = "seek"
				vr_t = 0.0


func _nearest_duck(from: Vector3, floating_only: bool) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for id in main.ducks:
		var s: Node3D = main.ducks[id]
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var st: int = int(main.duck_state.get(id, 0))
		if st == 4 or st == 2 or (floating_only and st != 0):
			continue
		var dd := from.distance_to(s.position)
		if dd < bd:
			bd = dd
			best = s
	return best


func _report() -> String:
	return "BOT %s: players %s, ducks %d, score %d, total %d, vr throws %d, longest train %d" % [main.net.mode,
		str(main.party.active_slots()), main.ducks.size(), int(main.net.state_get("score", 0)),
		int(main.net.state_get("total", 0)), vr_throws, max_train]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(main.party.player_count(), want + host_p, "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.boats.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("total", 0)) > 0, "%s: ducks went down the plug" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	kit.assert_true(main.ducks.size() > 0, "%s: ducks float in the tub" % mode)
	if mode != "client":
		kit.assert_true(max_train > 0 or main.net.mode == "host", "boats towed ducks")
	if main.vr_rig != null:
		kit.assert_true(vr_throws > 0, "fake VR player grabbed and threw ducks")
		kit.assert_true(int(main.splashes) > 3, "the fake VR glove splashed the water (%d)" % int(main.splashes))
	if mode == "client" and main.vr_avatar != null:
		kit.assert_true(int(main.splashes) > 3, "client: splashes from the VR player arrived (%d)" % int(main.splashes))
		kit.assert_true(main.vr_avatar != null, "client: the VR player is drawn on the TV")
