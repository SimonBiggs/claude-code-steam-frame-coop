extends Node
## Headless bot for games/snowman_maker. BOT_PLAYERS=n TV players (default 2) roll snowballs to the
## build circle and carry carrots / hats; BOT_VR=1 adds a fake VR builder that lifts balls onto
## each other and puts carrots and hats on.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/snowman_maker_bot.tscn
## Networked: DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")
const Snowman := preload("res://games/snowman_maker/snowman.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var vr_task := ""
var vr_target := Vector3.ZERO
var vr_wait := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/snowman_maker/main.tscn").instantiate()
	main.set("round_time", 26.0)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	if OS.has_environment("BOT_VR") and OS.has_environment("BOT_PLAYERS") and int(OS.get_environment("BOT_PLAYERS")) == 0:
		want = 0
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A" % want, _join)
	if not host:
		kit.at(t0 + 8.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 8.6, "paused?", func() -> void:
			if not main.party.local_slots().is_empty():
				kit.assert_true(get_tree().paused, "Start pauses")
			_press("start"))
		kit.at(t0 + 9.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	if want > 0:
		kit.drop_in_out(main.party, t0 + 11.0, 3.0, func(slot: int) -> bool:
			return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		kit.at(29.0, "host checks (the TV machine is still connected)", _checks)
		var end := float(OS.get_environment("BOT_HOST_END")) if OS.has_environment("BOT_HOST_END") else 35.0  # late-join tests
		kit.at(end, "finish", kit.finish)
	else:
		kit.at(31.0 if client else 36.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.5, _continue_results)
	kit.every(0.5, func() -> String:
		if main.vr_rig != null and main.results_showing():
			kit.vr_trigger(main.vr_rig, 0.0 if main.vr_rig.fake_trigger > 0.5 else 1.0)
		return "")


func _continue_results() -> String:
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.results_ui == null or (main.results_ui.get("data") as Dictionary).has("title"),
				"the results screen has the round's results")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
			return "RESULTS UP"
		_press("accept")
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
	var slots: Array[int] = main.party.local_slots()
	for i in slots.size():
		_steer(slots[i], i)
	if main.vr_rig != null:
		_drive_vr(delta)


# --- TV bots --------------------------------------------------------------------------------

## A snowman (as seen on this machine) with 3 balls missing something: [node, kind] or [].
func _needy() -> Array:
	for sid in main.stack_nodes:
		var n: Snowman = main.stack_nodes[sid]
		if is_instance_valid(n) and n.radii.size() == 3 and not n.done:
			return [n, 0 if not n.carrot else 1]
	return []


## Where the bot wants to walk.
func _tv_goal(slot: int, idx: int) -> Vector3:
	var a: Node3D = main.avatars[slot]
	var need := _needy()
	if idx == 0 and not need.is_empty() and main.vr_rig == null:
		var kind: int = need[1]
		if int(main.carry.get(slot, -1)) == kind:
			return (need[0] as Node3D).position
		return main.BOX_POS[kind]
	# Push the nearest loose ball to the biggest one in the circle (or to the circle).
	var anchor := _anchor()
	var best: Node3D = null
	var bd := INF
	for id in main.balls:
		var b: Dictionary = main.balls[id]
		var n: Node3D = b["n"]
		if n == anchor or n.position.y > float(b["r"]) + 0.05:
			continue
		var d := a.position.distance_to(n.position) + float(b["r"]) * 4.0
		if d < bd:
			bd = d
			best = n
	if best == null:
		return Vector3(0.0, 0.0, -3.0)
	var goal: Vector3 = anchor.position if anchor != null else main.YARD
	var dir := goal - best.position
	dir.y = 0.0
	if dir.length() < 0.05:
		return best.position
	dir = dir.normalized()
	var r := best.scale.x
	var behind := best.position - dir * (r + 0.3)
	var rel := a.position - best.position
	rel.y = 0.0
	if rel.dot(dir) > -0.1 and Vector2(a.position.x - behind.x, a.position.z - behind.z).length() > 0.3:
		var side := Vector3(-dir.z, 0.0, dir.x)
		if rel.dot(side) < 0.0:
			side = -side
		return best.position + side * (r + 0.8) - dir * (r + 0.6)
	if Vector2(a.position.x - behind.x, a.position.z - behind.z).length() > 0.25:
		return behind
	return best.position + dir * 2.0


## The thing to build on: an unfinished snowman, else the biggest loose ball in the circle.
func _anchor() -> Node3D:
	for sid in main.stack_nodes:
		var n: Snowman = main.stack_nodes[sid]
		if is_instance_valid(n) and n.radii.size() < 3 and not n.done:
			return n
	var best: Node3D = null
	var br := 0.0
	for id in main.balls:
		var b: Dictionary = main.balls[id]
		var n: Node3D = b["n"]
		if Vector2(n.position.x, n.position.z).length() < 3.0 and float(b["r"]) > br:
			br = float(b["r"])
			best = n
	return best


func _steer(slot: int, idx: int) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	var d := _tv_goal(slot, idx) - a.position
	d.y = 0.0
	var v := Vector2.ZERO
	if d.length() > 0.1:
		d = d.normalized()
		var cam: Camera3D = main.split.active_camera(slot)
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		v = Vector2(d.dot(r), -d.dot(f))
	kit.slot_stick(main.party, slot, "left", v)


# --- Fake VR builder ------------------------------------------------------------------------

func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	if rig.hand_r.position == Vector3.ZERO:
		kit.vr_idle(rig)
	rig.hand_l.position = Vector3(-0.45, 1.5, 0.25)  # the left hand waves up and back, clear of the right
	vr_wait -= delta
	if vr_wait > 0.0:
		kit.vr_stick(rig, Vector2.ZERO)
		return
	var holding: bool = main.held_ball >= 0 or main.held_item >= 0
	if not holding:
		kit.vr_trigger(rig, 0.0)
		var need := _needy()
		if not need.is_empty():
			vr_task = "box"
			vr_target = main.BOX_POS[int(need[1])] + Vector3.UP * (main.BOX_TOP + 0.1)
		else:
			var pick := _vr_pick_ball()
			if pick == null:
				kit.vr_stick(rig, Vector2.ZERO)
				return
			vr_task = "ball"
			vr_target = pick.position
		if _walk_to(rig, vr_target) and kit.vr_reach(rig, 1, vr_target, 3.0, delta):
			kit.vr_trigger(rig, 1.0)
			vr_wait = 0.15
		return
	# Holding: carry it to where it goes.
	var drop := Vector3.ZERO
	if main.held_item >= 0:
		var need := _needy()
		if need.is_empty():
			kit.vr_trigger(rig, 0.0)
			return
		drop = (need[0] as Snowman).head_world()
	else:
		var anchor := _vr_anchor()
		if anchor == null:
			kit.vr_trigger(rig, 0.0)  # nothing to stack on: put it down
			vr_wait = 0.4
			return
		var top := anchor.scale.x * 2.0 if not (anchor is Snowman) else Snowman.top_y((anchor as Snowman).radii)
		drop = Vector3(anchor.position.x, top + 0.35, anchor.position.z)
	if _walk_to(rig, drop) and kit.vr_reach(rig, 1, drop, 1.2, delta):
		kit.vr_trigger(rig, 0.0)
		vr_wait = 0.4


func _vr_pick_ball() -> Node3D:
	var anchor := _vr_anchor()
	var head: Vector3 = main.vr_rig.head_position()
	var best: Node3D = null
	var bd := INF
	for id in main.balls:
		var n: Node3D = (main.balls[id] as Dictionary)["n"]
		if n == anchor:
			continue
		var d := Vector2(n.position.x - head.x, n.position.z - head.z).length() + Vector2(n.position.x, n.position.z).length()
		if d < bd:
			bd = d
			best = n
	return best


func _vr_anchor() -> Node3D:
	for sid in main.stack_nodes:
		var n: Snowman = main.stack_nodes[sid]
		if is_instance_valid(n) and n.radii.size() < 3 and not n.done:
			return n
	var best: Node3D = null
	var bd := INF
	for id in main.balls:
		var b: Dictionary = main.balls[id]
		if int(b["s"]) != 0 or int(id) == main.held_ball:
			continue
		var n: Node3D = b["n"]
		var d := Vector2(n.position.x, n.position.z).length()
		if d < bd:
			bd = d
			best = n
	return best


## Walk the fake VR player until the target is within arm's reach; true when there.
func _walk_to(rig: Node, target: Vector3) -> bool:
	var head: Vector3 = rig.head_position()
	var d := target - head
	d.y = 0.0
	if d.length() < 0.55:
		kit.vr_stick(rig, Vector2.ZERO)
		return true
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	var n := d.normalized()
	kit.vr_stick(rig, Vector2(n.dot(r), n.dot(f)))
	return false


func _report() -> String:
	var sizes := 0
	for sid in main.stack_nodes:
		sizes += (main.stack_nodes[sid] as Snowman).radii.size()
	return "BOT %s: players %s, loose balls %d, snowmen %d (%d balls), score %d, carry %s, helpers %d" % [main.net.mode,
		str(main.party.active_slots()), main.balls.size(), main.stack_nodes.size(), sizes,
		int(main.net.state_get("score", 0)), str(main.carry), main.helpers.size()] + _where()


func _where() -> String:
	var out := ""
	if main.vr_rig != null:
		var h: Vector3 = main.vr_rig.head_position()
		var rp: Vector3 = main.vr_rig.hand_point(1)
		out += " VR(%.1f,%.1f) hand(%.1f,%.1f,%.1f) ball%d item%d" % [h.x, h.z, rp.x, rp.y, rp.z, main.held_ball, main.held_item]
	for slot in main.avatars:
		var p: Vector3 = (main.avatars[slot] as Node3D).position
		out += " P%d(%.1f,%.1f)" % [slot, p.x, p.z]
	for sid in main.stack_nodes:
		var n: Snowman = main.stack_nodes[sid]
		out += " S%d(%.1f,%.1f n%d %s%s%s)" % [sid, n.position.x, n.position.z, n.radii.size(), "C" if n.carrot else "", "H" if n.hat else "", "D" if n.done else ""]
	for id in main.balls:
		var b: Dictionary = main.balls[id]
		var p: Vector3 = (b["n"] as Node3D).position
		out += " b%d(%.1f,%.1f r%.2f)" % [id, p.x, p.z, float(b["r"])]
	return out


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	kit.assert_true(saw_results, "%s: the results showed" % mode)
	kit.assert_eq(main.stack_nodes.size(), (main.net.state_get("stacks", {}) as Dictionary).size(),
		"%s: every snowman in the store is drawn" % mode)
	if mode != "client":
		kit.assert_true(main.total_rolled > 1.0, "%s: snow was rolled" % mode)
		kit.assert_true(main.total_stacked > 0, "%s: snowballs were stacked" % mode)
	if main.vr_rig != null:
		kit.assert_true(main.total_made > 0, "%s: the VR builder finished a snowman" % mode)
