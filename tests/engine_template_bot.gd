extends Node
## Headless bot for games/engine_template (Star Catch), and the model bot for games built on the
## engine (tests/bot_kit.gd does the heavy lifting).
## BOT_PLAYERS=n: TV players that drop in with virtual pads (default 2). BOT_VR=1 (local / host):
## a fake VR player walks with the stick and grabs stars with its right glove.
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 1500 res://tests/engine_template_bot.tscn
## Networked:  DUO_PORT=7994 DUO_HOST=1 ... & DUO_PORT=7994 DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")

var kit: BotKit
var main: Node
var want := 2
var caught_by_vr := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)  # first: real controllers are ignored, saves go to user://test_saves/
	main = load("res://games/engine_template/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	kit.at(t0 + 4.0, "P2 presses Y: one shared view", func() -> void: _press_y())
	kit.at(t0 + 5.0, "shared?", func() -> void:
		if main.split != null:
			kit.assert_true(main.split.is_shared(), "Y switched to the shared view"))
	kit.at(t0 + 8.0, "P2 presses Y again: split screen", func() -> void: _press_y())
	kit.at(t0 + 9.0, "split?", func() -> void:
		if main.split != null:
			kit.assert_true(not main.split.is_shared(), "Y switched back to split screen"))
	if host:
		kit.at(20.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(30.0, "finish", kit.finish)
	else:
		kit.at(22.0 if client else 18.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)


func _join() -> void:
	if main.net.mode == "host":
		return
	for i in want:
		kit.join_bot(main.party)


func _press_y() -> void:
	var slots: Array[int] = main.party.local_slots()
	if not slots.is_empty():
		kit.slot_press(main.party, slots[0], "y")


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	for slot in main.party.local_slots():
		_steer(slot)
	if main.vr_rig != null:
		_drive_vr(delta)


## Push the slot's stick towards the nearest star, relative to the camera it sees.
func _steer(slot: int) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	var star := _nearest_star(a.position)
	var v := Vector2.ZERO
	if star != null:
		var d := star.position - a.position
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


## Fake VR: walk towards the nearest star with the left stick, grab it with the right glove.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	var head: Vector3 = rig.head_position()
	var star := _nearest_star(head)
	rig.camera.position.y = 1.6
	if star == null:
		kit.vr_stick(rig, Vector2.ZERO)
		return
	var d := star.position - head
	d.y = 0.0
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	if d.length() > 0.6:
		kit.vr_stick(rig, Vector2(d.normalized().dot(r), d.normalized().dot(f)))
	else:
		kit.vr_stick(rig, Vector2.ZERO)
	if d.length() < 1.0 and kit.vr_reach(rig, 1, star.position, 2.5, delta):
		caught_by_vr += 1


func _nearest_star(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for id in main.stars:
		var s: Node3D = main.stars[id]
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			continue
		var dd := from.distance_to(s.position)
		if dd < bd:
			bd = dd
			best = s
	return best


func _report() -> String:
	return "BOT %s: players %s, stars on the ground %d, score %d, best %d" % [main.net.mode,
		str(main.party.active_slots()), main.stars.size(), int(main.net.state_get("score", 0)),
		int(main.net.state_get("best", 0))]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(int(main.net.state_get("score", 0)) > 0, "%s: stars were caught" % mode)
	if main.vr_rig != null:
		kit.assert_true(caught_by_vr > 0 or int(main.net.state_get("score", 0)) > 0, "fake VR player played")
