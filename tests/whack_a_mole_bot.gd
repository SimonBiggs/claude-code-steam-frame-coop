extends Node
## Headless bot for games/whack_a_mole. BOT_PLAYERS=n TV kids drop in and run to moles and press A.
## BOT_VR=1 (local / host): a fake VR player walks up and swings the mallet down onto moles.
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/whack_a_mole_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).

const BotKit := preload("res://tests/bot_kit.gd")
const Story := preload("res://games/whack_a_mole/story.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var saw_practice := false
var saw_pick := false  # Fig's bed filled and the team bonked a seed packet (story.gd)
var saw_kinds := {}
var saw_moles := 0  # most moles in a generated round seen
var bonk_cd := {}
var swing_phase := 0  # fake VR: 0 = raise above a mole, 1 = swing down
var swing_hole := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/whack_a_mole/main.tscn").instantiate()
	main.set("round_time", 14.0)
	main.set("fresh_save", true)  # a brand-new garden every run
	main.set("need_scale", 0.15)  # tiny beds: round 1 fills one, round 2 starts with the seed pick
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host and BotKit.lead_machine():
		kit.at(t0 + 6.0, "P1 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 6.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and not main.tv_banner.visible, "Start pauses (on_pause_changed made the banner; the open pause menu alone says PAUSED)")
			_press("start"))
		kit.at(t0 + 7.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	kit.drop_in_out(main.party, t0 + 9.0, 3.0, func(slot: int) -> bool:
		return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		kit.at(24.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(34.0, "finish", kit.finish)
	else:
		kit.at(25.0 if client else 34.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.5, _continue_results)


func _continue_results() -> String:
	if String(main.net.state_get("phase", "")) == "practice":
		saw_practice = true
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
	if not main.ready_to_play:  # the TV machine is still connecting: try again shortly
		get_tree().create_timer(0.5).timeout.connect(_join)
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
	var ph := String(main.net.state_get("phase", ""))
	if ph == "practice":
		saw_practice = true
	if ph == "pick":
		saw_pick = true
	if not main.round_def.is_empty():
		saw_moles = maxi(saw_moles, (main.round_def.spawns as Array).size())
	for i in main.holes.size():
		if main.m_state[i] == 1:
			saw_kinds[int(main.m_kind[i])] = true
	for slot in main.party.local_slots():
		_steer(slot, delta)
	if main.vr_rig != null:
		_drive_vr(delta)


func _up_holes() -> Array[int]:
	var out: Array[int] = []
	for i in main.holes.size():
		if main.m_state[i] == 1 and main.m_h[i] > 0.5 and main.m_kind[i] != 4:  # never bonk a bunny (story.gd)
			out.append(i)
	return out


func _nearest_up(from: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in _up_holes():
		var p: Vector3 = main.holes[i]
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## Run to the nearest mole and press A when close.
func _steer(slot: int, delta: float) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	var i := _nearest_up(a.position)
	var v := Vector2.ZERO
	bonk_cd[slot] = float(bonk_cd.get(slot, 0.0)) - delta
	if i >= 0:
		var d: Vector3 = main.holes[i] - a.position
		d.y = 0.0
		if d.length() > 0.25:
			d = d.normalized()
			var cam: Camera3D = main.split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			v = Vector2(d.dot(r), -d.dot(f))
		if d.length() < 0.35 and float(bonk_cd[slot]) <= 0.0:
			bonk_cd[slot] = 0.3
			kit.slot_press(main.party, slot, "accept")
	kit.slot_stick(main.party, slot, "left", v)


## Fake VR: walk near a mole, raise the mallet above it, swing it down.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	if swing_hole < 0 or main.m_state[swing_hole] != 1:
		var head: Vector3 = rig.head_position()
		swing_hole = _nearest_up(head)
		swing_phase = 0
	if swing_hole < 0:
		kit.vr_stick(rig, Vector2.ZERO)
		return
	var hole: Vector3 = main.holes[swing_hole]
	var head2: Vector3 = rig.head_position()
	var d := hole - head2
	d.y = 0.0
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	if d.length() > 1.0:
		kit.vr_stick(rig, Vector2(d.normalized().dot(r), d.normalized().dot(f)))
	else:
		kit.vr_stick(rig, Vector2.ZERO)
	# Where the hand must be so the mallet head lands on the target.
	var hand: Node3D = rig.hand_r
	var off: Vector3 = main.mallet_head.global_position - hand.global_position
	var above := hole + Vector3(0.0, 0.75, 0.0) - off
	var on := hole + Vector3(0.0, 0.2, 0.0) - off
	if swing_phase == 0:
		if kit.vr_reach(rig, 1, above, 3.0, delta):
			swing_phase = 1
	else:
		if kit.vr_reach(rig, 1, on, 3.0, delta):
			swing_phase = 0


func _report() -> String:
	return "BOT %s: players %s, phase %s, moles up %d, score %d, whacked %d (VR %d), best %d, garden %s, kinds %s" % [main.net.mode,
		str(main.party.active_slots()), String(main.net.state_get("phase", "")), _up_holes().size(),
		int(main.net.state_get("score", 0)), int(main.net.state_get("whacked", 0)), main.vr_whacks,
		int(main.net.state_get("best", 0)), str(main.net.state_get("garden", {})), str(saw_kinds.keys())]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(main.party.player_count(), kit.seated_want(want, host_p), "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("whacked", 0)) > 1, "%s: moles were whacked" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	if main.vr_rig != null:
		kit.assert_true(main.vr_whacks > 0, "the fake VR player whacked moles with the mallet")
	if mode != "client":
		kit.assert_true(saw_practice, "the round started with a practice mole")
		kit.assert_true(saw_pick, "%s: Fig's bed filled and the next round began with the seed pick" % mode)
		kit.assert_true(Story.beds_grown(main.save.data.beds) >= 1, "%s: a bed grew in Fig's garden (%s)" % [mode, str(main.save.data.beds)])
		kit.assert_true(String(main.save.data.cur) not in [Story.FIRST_CROP, ""] or Story.beds_grown(main.save.data.beds) >= 2,
			"%s: a new crop was planted (%s, %s)" % [mode, String(main.save.data.cur), str(main.save.data.beds)])
		kit.assert_true(saw_moles > 5, "%s: the rounds came from roundgen.gd (%d moles)" % [mode, saw_moles])
	var gs: Dictionary = main.net.state_get("garden", {})
	kit.assert_true(gs.has("beds") and int(gs.get("need", 0)) > 0, "%s: the garden state reached this machine (%s)" % [mode, str(gs)])
	kit.assert_true(main.garden != null and main.garden.state.has("beds"), "%s: the garden is drawn" % mode)
	kit.assert_true((main.net.state_get("goal", []) as Array).size() == 3 or String(main.net.state_get("phase", "")) != "play", "%s: the star goal is known" % mode)
