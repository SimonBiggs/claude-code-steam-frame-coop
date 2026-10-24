extends Node
## Headless bot for games/fruit_catch (FRUIT CATCH), built like tests/engine_template_bot.gd.
## BOT_PLAYERS=n: TV players with virtual pads (default 2); they run under good fruit and dodge rotten
## apples. BOT_VR=1 (local / host): a fake VR player shakes a branch with the right glove, catches
## fruit with the left glove and puts it in the bowl.
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/fruit_catch_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).

const BotKit := preload("res://tests/bot_kit.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var vr_t := 0.0
var vr_caught := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/fruit_catch/main.tscn").instantiate()
	main.set("round_time", 16.0)
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
	kit.at(t0 + 7.0, "P2 presses Y again: split screen", func() -> void: _press_y())
	if not host:
		kit.at(t0 + 9.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 9.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and main.tv_banner.visible, "Start pauses")
			_press("start"))
		kit.at(t0 + 10.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	kit.drop_in_out(main.party, t0 + 11.0, 3.0, func(slot: int) -> bool:
		return main.avatars.has(slot) and main.baskets.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		kit.at(27.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(37.0, "finish", kit.finish)
	else:
		kit.at(31.0 if client else 27.0, "finish", func() -> void:
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


## Run under the lowest good fruit (where its shadow is), relative to the camera this slot sees.
func _steer(slot: int) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	var target := Vector3.INF
	var bd := INF
	for id in main.fruits:
		var f: Dictionary = main.fruits[id]
		if int(f.kind) == 4:
			continue
		var p: Vector3 = (f.node as Node3D).position
		var d := Vector2(p.x - a.position.x, p.z - a.position.z).length() + p.y
		if d < bd:
			bd = d
			target = p
	var v := Vector2.ZERO
	if target != Vector3.INF:
		var d := target - a.position
		d.y = 0.0
		if d.length() > 0.15:
			d = d.normalized()
			var cam: Camera3D = main.split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			v = Vector2(d.dot(r), -d.dot(f))
	kit.slot_stick(main.party, slot, "left", v)


## Fake VR: the right glove shakes branch 0 for 4 s then pulls away (it springs free); the left glove
## catches nearby fruit and dunks it in the bowl.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	kit.vr_stick(rig, Vector2.ZERO)
	vr_t += delta
	var tip: Vector3 = main.branch_rest[0]
	var cyc := fmod(vr_t, 6.0)
	if cyc < 4.0:
		var shake := Vector3(sin(vr_t * 18.0) * 0.25, cos(vr_t * 14.0) * 0.1, 0.0)
		kit.vr_reach(rig, 1, tip + shake, 6.0, delta)
	else:
		kit.vr_reach(rig, 1, Vector3(0.9, 1.1, 4.0), 4.0, delta)
	var held := false
	for id in main.fruits:
		var f: Dictionary = main.fruits[id]
		if int(f.state) == 2 and int(f.hand) == 0:
			held = true
	if held:
		if kit.vr_reach(rig, 0, main.BOWL_POS + Vector3.UP * (main.BOWL_TOP + 0.05), 1.5, delta):
			pass
		return
	var head: Vector3 = rig.head_position()
	var best: Vector3 = Vector3.INF
	for id in main.fruits:
		var f: Dictionary = main.fruits[id]
		var p: Vector3 = (f.node as Node3D).position
		if int(f.kind) == 4 or int(f.state) != 1:
			continue
		if Vector2(p.x - head.x, p.z - head.z).length() < 1.6 and p.y < 2.6 and p.y > 0.5:
			best = p
	if best != Vector3.INF:
		kit.vr_reach(rig, 0, best, 8.0, delta)
	else:
		kit.vr_reach(rig, 0, head + Vector3(-0.5, -0.6, 0.6), 3.0, delta)


func _report() -> String:
	return "BOT %s: players %s, fruit %d, score %d, caught %d, shakes %d, dunks %d" % [main.net.mode,
		str(main.party.active_slots()), main.fruits.size(), int(main.net.state_get("score", 0)),
		int(main.net.state_get("caught", 0)), main.shakes, main.dunks]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(main.party.player_count(), want + host_p, "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("caught", 0)) > 0, "%s: fruit was caught" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended and round 2 started" % mode)
	if main.vr_rig != null:
		kit.assert_true(main.shakes > 0, "the VR player shook fruit off a branch")
		kit.assert_true(main.dunks > 0, "the VR player put fruit in the bowl")
