extends Node
## Headless bot for games/dodge_ball (Soft Dodgeball).
## BOT_PLAYERS=n TV runners (default 2) run to loose balls and throw them at the giant's belly.
## BOT_VR=1 (local / host): a fake VR giant grabs balls from the tray and flings them at runners.
## BOT_HOST_VR=1 on the TV machine: the host has a (fake) VR giant, so hits are not checked.
## BOT_SOLO=1 with BOT_VR=1: nobody joins on the TV (VR alone: CPU runners fill in).
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/dodge_ball_bot.tscn
## Networked: DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).

const BotKit := preload("res://tests/bot_kit.gd")

var kit: BotKit
var main: Node
var want := 2
var vr_phase := "reach"
var vr_t := 0.0
var vr_throws := 0
var vr_grabs := 0
var hold_t := {}
var saw_results := false
var round_at_results := 0
var max_tv := 0
var max_giant := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/dodge_ball/main.tscn").instantiate()
	main.set("round_time", 18.0)
	main.set("results_wait", 6.0)
	add_child(main)
	kit.main = main
	want = 0 if OS.has_environment("BOT_SOLO") else BotKit.bot_players(2, 6)  # BOT_SOLO: VR alone
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV runners press A on their pads" % want, _join)
	if not host and want > 0:
		kit.at(t0 + 6.0, "P pauses with Start", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 6.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused, "Start pauses the game")
			_press("start"))
		kit.at(t0 + 7.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	if want > 0:
		kit.drop_in_out(main.party, t0 + 9.0, 3.0, func(slot: int) -> bool:
			return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot) and main.throw_prompts.has(slot))
	if host:
		kit.at(38.0, "host checks", _checks)
		kit.at(42.0, "finish", kit.finish)
	else:
		kit.at(31.0 if client else 34.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.5, _watch_results)


func _watch_results() -> String:
	if main.results_showing() and not saw_results:
		saw_results = true
		round_at_results = int(main.net.state_get("round", 0))
		kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
		kit.assert_true(main.results_ui == null or (main.results_ui.get("data") as Dictionary).has("title"),
			"the results screen has the round's results")
		kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
		return "results are up (nobody presses anything: the next round must start by itself)"
	return ""


func _join() -> void:
	if main.net.mode == "host":
		if main.flat:
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
	max_tv = maxi(max_tv, int(main.net.state_get("tv_score", 0)))
	max_giant = maxi(max_giant, int(main.net.state_get("giant_score", 0)))
	for slot in main.party.local_slots():
		_steer(slot, delta)
	if main.vr_rig != null:
		_drive_vr(delta)


## Run to the nearest loose ball; when holding one for a moment, press A to throw it.
func _steer(slot: int, delta: float) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	var v := Vector2.ZERO
	if main._holding(slot) >= 0 or _client_holding(slot):
		hold_t[slot] = float(hold_t.get(slot, 0.0)) + delta
		if float(hold_t[slot]) > 0.6:
			hold_t[slot] = 0.0
			kit.slot_press(main.party, slot, "accept")
	else:
		hold_t[slot] = 0.0
		var goal := _nearest_loose(a.position)
		if goal != null:
			var d := goal.position - a.position
			d.y = 0.0
			if d.length() > 0.1:
				d = d.normalized()
				var cam: Camera3D = main.split.active_camera(slot)
				var f := -cam.global_basis.z
				f.y = 0.0
				f = f.normalized()
				var r := Vector3(-f.z, 0.0, f.x)
				v = Vector2(d.dot(r), -d.dot(f))
	kit.slot_stick(main.party, slot, "left", v)


func _client_holding(slot: int) -> bool:
	for b in main.balls:
		if int(b.holder) == slot:
			return true
	return false


func _nearest_loose(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for b in main.balls:
		if int(b.holder) >= 0 or int(b.tray) >= 0 or float(b.hop) > 0.0 or (main.net.mode != "client" and bool(b.danger)):
			continue
		var n: Node3D = b.node
		if n.position.z < -4.4:
			continue
		var dd := from.distance_to(n.position)
		if dd < bd:
			bd = dd
			best = n
	return best


## Fake VR giant: reach for a tray ball, pull the trigger, swing back, fling it at a runner.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position = Vector3(0.0, 1.6, 0.0)
	rig.camera.basis = Basis()
	rig.hand_l.position = Vector3(-0.3, 1.0, -0.3)
	vr_t += delta
	match vr_phase:
		"reach":
			kit.vr_trigger(rig, 0.0)
			var tb: int = main._nearest_tray_ball(rig.hand_point(1))
			if tb >= 0 and vr_t > 0.4:
				var p: Vector3 = main.balls[tb].node.position
				if kit.vr_reach(rig, 1, p, 2.5, delta) or rig.hand_point(1).distance_to(p) < 0.12:
					kit.vr_trigger(rig, 1.0)
					vr_phase = "grab"
					vr_t = 0.0
		"grab":
			if vr_t > 0.15:
				if main._holding(main.GIANT) >= 0:
					vr_grabs += 1
					vr_phase = "windup"
				else:
					vr_phase = "reach"
				vr_t = 0.0
		"windup":
			var back: Vector3 = rig.global_transform * Vector3(0.35, 1.7, 0.25)
			if kit.vr_reach(rig, 1, back, 2.0, delta) or vr_t > 1.0:
				vr_phase = "fling"
				vr_t = 0.0
		"fling":
			var aim := Vector3(0.0, 0.0, 3.0)
			for id in main.avatars:
				aim = (main.avatars[id] as Node3D).position
				break
			var hp: Vector3 = rig.hand_point(1)
			var dir := (aim - hp)
			dir.y = 0.0
			var goal := hp + dir.normalized() + Vector3(0.0, 0.25, 0.0)
			kit.vr_reach(rig, 1, goal, 8.0, delta)
			if vr_t > 0.12:
				kit.vr_trigger(rig, 0.0)
				vr_throws += 1
				vr_phase = "reach"
				vr_t = 0.0


func _report() -> String:
	return "BOT %s: runners %s, runners %d : %d giant, round %d, phase %s, out %s, vr grabs %d throws %d" % [
		main.net.mode, str(main.avatars.keys()), int(main.net.state_get("tv_score", 0)),
		int(main.net.state_get("giant_score", 0)), int(main.net.state_get("round", 0)),
		str(main.net.state_get("phase", "")), str(main.out.keys()), vr_grabs, vr_throws] + _ball_debug()


func _ball_debug() -> String:
	var s := " | giant %s | av %s |" % [str(main.cpu_g), str(main.avatars.values().map(func(a: Node3D) -> Vector3: return a.position.snapped(Vector3.ONE * 0.1)))]
	for b in main.balls:
		s += " [%s h%d t%d th%d]" % [str(b.node.position.snapped(Vector3.ONE * 0.1)), b.holder, b.tray, b.thrower]
	return s


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	elif mode == "local":  # (the host checks after the TV machine has gone)
		var host_p := 0
		kit.assert_eq(main.party.player_count(), want + host_p, "%s: all %d players are seated" % [mode, want])
	if main.flat:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(saw_results, "%s: the round ended with results" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: the next round started by itself" % mode)
	kit.assert_true(max_tv > 0, "%s: runners hit the giant's belly (%d)" % [mode, max_tv])
	if OS.has_environment("BOT_VR") and mode != "client":
		kit.info("the fake VR giant hit runners %d times (aim is luck: not checked)" % max_giant)
	elif not (mode == "client" and OS.has_environment("BOT_HOST_VR")):
		kit.assert_true(max_giant > 0, "%s: the giant hit runners (%d)" % [mode, max_giant])
	if want == 0 and main.vr_rig != null:
		kit.assert_eq(main.cpu.size(), 2, "VR alone: two CPU runners fill in")
	if main.vr_rig != null:
		kit.assert_true(vr_grabs > 0 and vr_throws > 0, "fake VR giant grabbed and threw balls")
	elif mode != "client":
		kit.assert_true(main.g_cpu, "no VR: the computer is the giant")
