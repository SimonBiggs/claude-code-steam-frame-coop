extends Node
## Headless bot for games/balloon_pop. TV bots run at balloons and jump for the high ones; a fake VR
## player (BOT_VR=1, local / host) walks over, squeezes with the right glove and punches with the left.
## BOT_PLAYERS=n TV players (default 2).
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/balloon_pop_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).

const BotKit := preload("res://tests/bot_kit.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var saw_finale := false
var jumps := 0
var vr_t := 0.0


var jump_peak := 0.0
var jump_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/balloon_pop/main.tscn").instantiate()
	main.set("round_time", 14.0)
	main.set("results_wait", 4.0)  # the next round starts by itself (nobody presses anything)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host and BotKit.lead_machine():
		kit.at(t0 + 6.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 6.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and not main.tv_banner.visible, "Start pauses (on_pause_changed made the banner; the open pause menu alone says PAUSED)")
			_press("start"))
		kit.at(t0 + 7.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused and not main.tv_banner.visible, "Start again resumes")
			kit.allow_pause = false)
	kit.drop_in_out(main.party, t0 + 8.0, 3.0, func(slot: int) -> bool:
		return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	kit.at(t0 + 3.0, "P2 jumps", func() -> void: _press("a"))
	# Sample the jump height over half a second (networked runs are not frame-locked).
	for i in 10:
		kit.at(t0 + 3.05 + i * 0.05, "", func() -> void:
			if get_tree().paused:
				jump_paused = true  # another machine paused everyone (tools/multibot.ts runs): nobody moves
			var slots: Array[int] = main.party.local_slots()
			if not slots.is_empty() and main.avatars.has(slots[0]):
				jump_peak = maxf(jump_peak, (main.avatars[slots[0]] as Node3D).position.y))
	kit.at(t0 + 3.6, "in the air?", func() -> void:
		var slots: Array[int] = main.party.local_slots()
		if not slots.is_empty() and main.avatars.has(slots[0]) and not jump_paused:
			kit.assert_true(jump_peak > 0.5, "A makes a TV player jump"))
	if host:
		kit.at(22.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(30.0, "finish", kit.finish)
	else:
		kit.at(24.0 if client else 26.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.25, _watch_results)


func _watch_results() -> String:
	if main.results_showing() and not saw_results:
		saw_results = true
		kit.assert_true(main.balloons.is_empty(), "the finale popped every balloon")
		kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
		kit.assert_true(main.results_ui == null or (main.results_ui.get("data") as Dictionary).has("title"),
			"the results screen has the round's results (also for a TV machine that joins late)")
		kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
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
	if main == null or not main.ready_to_play or get_tree().paused:
		return
	for slot in main.party.local_slots():
		_steer(slot)
	if main.vr_rig != null:
		_drive_vr(delta)


## Run at the nearest friendly balloon; jump when it is overhead.
func _steer(slot: int) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	var b := _nearest(a.position, true)
	var v := Vector2.ZERO
	if b != null:
		var d := b.position - a.position
		d.y = 0.0
		if d.length() > 0.1:
			var dn := d.normalized()
			var cam: Camera3D = main.split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			v = Vector2(dn.dot(r), -dn.dot(f))
		if d.length() < 1.0 and b.position.y > 1.3 and a.position.y < 0.01:
			kit.slot_press(main.party, slot, "a")
			jumps += 1
	kit.slot_stick(main.party, slot, "left", v)


## Fake VR: walk to the nearest balloon; right glove squeezes (slow + trigger), left glove punches.
func _drive_vr(delta: float) -> void:
	vr_t += delta
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	var head: Vector3 = rig.head_position()
	var b := _nearest(head, true)
	if b == null:
		kit.vr_stick(rig, Vector2.ZERO)
		kit.vr_trigger(rig, 0.0)
		return
	var d := b.position - head
	d.y = 0.0
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	kit.vr_stick(rig, Vector2(d.normalized().dot(r), d.normalized().dot(f)) if d.length() > 0.5 else Vector2.ZERO)
	if d.length() < 1.0 and b.position.y < 2.4:
		var squeeze := int(vr_t / 4.0) % 2 == 0
		if squeeze:
			kit.vr_trigger(rig, 1.0)
			kit.vr_reach(rig, 1, b.position, 1.0, delta)
		else:
			kit.vr_trigger(rig, 0.0)
			kit.vr_reach(rig, 0, b.position, 3.0, delta)
	else:
		kit.vr_trigger(rig, 0.0)


func _nearest(from: Vector3, friendly: bool) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for id in main.balloons:
		var b: Node3D = main.balloons[id]
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if friendly and int(b.get("kind")) == 2:
			continue
		var dd := from.distance_to(b.position)
		if dd < bd:
			bd = dd
			best = b
	return best


func _report() -> String:
	return "BOT %s: players %s, balloons %d, score %d, popped %d (vr %d, tv %d), round %d, jumps %d" % [main.net.mode,
		str(main.party.active_slots()), main.balloons.size(), int(main.net.state_get("score", 0)),
		int(main.net.state_get("popped", 0)), main.popped_by_vr, main.popped_by_tv,
		int(main.net.state_get("round", 0)), jumps]


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
	kit.assert_true(int(main.net.state_get("popped", 0)) > 0, "%s: balloons were popped" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended and round 2 started by itself" % mode)
	if mode != "client":
		kit.assert_true(main.popped_by_tv > 0, "TV players popped balloons")
	if main.vr_rig != null:
		kit.assert_true(main.popped_by_vr > 0, "the fake VR player popped balloons")
