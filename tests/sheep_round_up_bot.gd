extends Node
## Headless bot for games/sheep_round_up. BOT_PLAYERS=n sheepdogs drop in with virtual pads
## (default 2); they run behind sheep to push them through the gates and bark now and then.
## BOT_VR=1 (local / host): a fake farmer grabs sheep with the right glove and drops them in the pen.
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/sheep_round_up_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")
const SheepScript := preload("res://games/sheep_round_up/sheep.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var grabs := 0
var vr_drop_t := 0.0
var bark_t := 0.0
var max_home := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/sheep_round_up/main.tscn").instantiate()
	main.set("round_time", 22.0)
	main.set("results_wait", 4.0)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host:
		kit.at(t0 + 6.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 6.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and main.tv_banner.visible, "Start pauses and shows the banner")
			_press("start"))
		kit.at(t0 + 7.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused and not main.tv_banner.visible, "Start again resumes everyone")
			kit.allow_pause = false)
	kit.drop_in_out(main.party, t0 + 9.0, 3.0, func(slot: int) -> bool:
		return main.dogs.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		kit.at(31.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(40.0, "finish", kit.finish)
	else:
		kit.at(36.0 if client else 37.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.5, _watch_results)


func _watch_results() -> String:
	max_home = maxi(max_home, int(main.net.state_get("home", 0)))
	if main.results_showing() and not saw_results:
		saw_results = true
		kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
		kit.assert_true(main.results_ui == null or (main.results_ui.get("data") as Dictionary).has("title"),
			"the results screen has the round's results")
		kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
	return ""


func _join() -> void:
	if main.net.mode == "host":
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
	bark_t -= delta
	var bark := bark_t <= 0.0
	if bark:
		bark_t = 2.5
	for slot in main.party.local_slots():
		_steer(slot, bark)
	if main.vr_rig != null:
		_drive_vr(delta)


## A gate's outside point nearest to p (sheep go in through the middle of a side).
func _gate_for(p: Vector3) -> Vector3:
	var pen: float = main.PEN
	if absf(p.x) > absf(p.z):
		return Vector3(signf(p.x) * (pen + 0.3), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(p.z) * (pen + 0.3))


## Run to the spot behind the nearest loose sheep (away from its gate), then push it in.
func _steer(slot: int, bark: bool) -> void:
	if not main.dogs.has(slot):
		return
	var d: Node3D = main.dogs[slot]
	var s := _nearest_sheep(d.position, slot)
	var v := Vector2.ZERO
	if s != null:
		var gate := _gate_for(s.position)
		var away := s.position - gate
		away.y = 0.0
		var target := s.position + away.normalized() * 1.0
		if d.position.distance_to(target) < 0.6 or away.length() < 0.5:
			target = gate - away.normalized() * 1.5  # drive it through the gate
		var to := target - d.position
		to.y = 0.0
		if to.length() > 0.1:
			to = to.normalized()
			var cam: Camera3D = main.split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			v = Vector2(to.dot(r), -to.dot(f))
		if bark and d.position.distance_to(s.position) < 3.0:
			kit.slot_press(main.party, slot, "accept")
	kit.slot_stick(main.party, slot, "left", v)


## Fake farmer: walk towards a loose sheep, reach down with the right glove, pull the trigger,
## carry it over the pen and let go.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	var head: Vector3 = rig.head_position()
	if int(main.held) >= 0:
		kit.vr_stick(rig, Vector2.ZERO)
		var over := Vector3(0.0, 1.0, 0.0)
		if kit.vr_reach(rig, 1, over, 3.0, delta):
			vr_drop_t += delta
			if vr_drop_t > 0.25:
				kit.vr_trigger(rig, 0.0)
		return
	vr_drop_t = 0.0
	var s := _nearest_sheep(head, -1)
	if s == null:
		kit.vr_stick(rig, Vector2.ZERO)
		kit.vr_trigger(rig, 0.0)
		return
	var d := s.position - head
	d.y = 0.0
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	if d.length() > 1.5:
		kit.vr_stick(rig, Vector2(d.normalized().dot(r), d.normalized().dot(f)))
	else:
		kit.vr_stick(rig, Vector2.ZERO)
	var close: bool = kit.vr_reach(rig, 1, s.position + Vector3.UP * 0.35, 4.0, delta)
	if close and rig.fake_trigger < 0.5:
		kit.vr_trigger(rig, 1.0)
		grabs += 1
	elif not close:
		kit.vr_trigger(rig, 0.0)


func _nearest_sheep(from: Vector3, slot: int) -> Node3D:
	var best: Node3D = null
	var bd := INF
	var i := 0
	for o in main.sheep:
		var s: Node3D = o
		i += 1
		if not is_instance_valid(s) or bool(s.get("penned")) or int(s.get("state")) != SheepScript.WALK:
			continue
		var dd := from.distance_to(s.position)
		if slot >= 0:
			dd += float((i + slot) % 3) * 2.0  # dogs spread over different sheep
		if dd < bd:
			bd = dd
			best = s
	return best


func _report() -> String:
	return "BOT %s: players %s, round %d, sheep home %d/%d, time %d, phase %s, VR grabs %d" % [main.net.mode,
		str(main.party.active_slots()), int(main.net.state_get("round", 0)), int(main.net.state_get("home", 0)),
		int(main.net.state_get("total", 0)), int(main.net.state_get("time", 0)), str(main.net.state_get("phase", "")), grabs]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(max_home > 0 or int(main.net.state_get("round", 0)) >= 2, "%s: sheep got into the pen" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	kit.assert_true(main.sheep.size() >= 5, "%s: the flock is on the field (%d)" % [mode, main.sheep.size()])
	if main.vr_rig != null:
		kit.assert_true(grabs > 0, "fake farmer grabbed sheep")
