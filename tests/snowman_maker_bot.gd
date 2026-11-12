extends Node
## Headless bot for games/snowman_maker. BOT_PLAYERS=n TV players (default 2) roll snowballs to the
## build circle and carry carrots / hats; BOT_VR=1 adds a fake VR builder that lifts balls onto
## each other and puts carrots and hats on.
## Local:     godot-test --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/snowman_maker_bot.tscn
## Networked: DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).
## BOT_CHAPTER=n plays chapter n's garden (pines 1+, ice 2+, drifts 3+, crowns 4; 5 = mixed).
## Second pass (games/snowman_maker/deep.gd): the TV players walk under a pick orb (the mode pick before day 1, Tumble's
## gift pick before day 2); a VR builder alone reaches into one and holds it there. Surprises start at 3 s from day 1
## (main.bot_surprises): the TV players step out of a sunbeam's circle and off a slide's band while it is told.

const BotKit := preload("res://tests/bot_kit.gd")
const Snowman := preload("res://games/snowman_maker/snowman.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var vr_task := ""
var vr_target := Vector3.ZERO
var vr_wait := 0.0
var vr_placed := 0  ## balls / carrots / hats the fake VR builder put on a snowman
var deep := {}  # second-pass things seen (picks, surprises, season, town)
var pick_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/snowman_maker/main.tscn").instantiate()
	var rt := float(OS.get_environment("BOT_ROUND")) if OS.has_environment("BOT_ROUND") else 26.0  # BOT_ROUND=150: a real day
	main.set("round_time", rt)
	main.set("bot_surprises", true)
	if OS.has_environment("BOT_CHAPTER"):
		main.set("force_chapter", int(OS.get_environment("BOT_CHAPTER")))
	add_child(main)
	kit.main = main
	kit.watch_state(main.net)  # phases counted as they happen (kit.seen): a 0.25 s poll misses quick ones under load
	want = BotKit.bot_players(2, 6)
	if OS.has_environment("BOT_VR") and OS.has_environment("BOT_PLAYERS") and int(OS.get_environment("BOT_PLAYERS")) == 0:
		want = 0
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A" % want, _join)
	if not host and BotKit.lead_machine():
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
	if want > 0 and not OS.has_environment("BOT_LATE"):  # (a late joiner's drop-in would still sit at the host's seat count)
		kit.drop_in_out(main.party, t0 + 11.0, 3.0, func(slot: int) -> bool:
			return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		# (the mode pick before day 1 and Tumble's gift pick before day 2 take a few seconds each)
		kit.at(rt + 14.0, "host checks (the TV machine is still connected)", _checks)
		var end := float(OS.get_environment("BOT_HOST_END")) if OS.has_environment("BOT_HOST_END") else rt + 20.0  # late-join tests
		kit.at(end, "finish", kit.finish)
	else:
		var fin := rt + 16.0
		if OS.has_environment("BOT_LATE"):  # a machine joining a game already running leaves before the host does
			fin = maxf(t0 + 14.0, rt + 20.0 - float(OS.get_environment("BOT_LATE")) - 4.0)
		kit.at(fin, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.2, _watch_deep)
	kit.every(0.5, _continue_results)
	kit.every(0.5, func() -> String:
		if main.vr_rig != null and main.results_showing():
			kit.vr_trigger(main.vr_rig, 0.0 if main.vr_rig.fake_trigger > 0.5 else 1.0)
		return "")


func _watch_deep() -> String:
	if main.picks != null and main.picks.showing():
		deep["orbs_seen"] = true
	if main.hazards != null:
		for k in main.hazards.seen:
			deep["told_" + String(k)] = true
		if not main.hazards.now.is_empty() and main.hazards.rings.count() < 1:
			deep["untold"] = true  # a surprise without its steady tell on the snow
	if main.season_node != null and String(main.season_node.season) != "":
		deep["dressed"] = String(main.season_node.season)
	if main.town != null and main.town.count >= 0:
		deep["town"] = main.town.count
	return ""


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
	if main.picks != null and main.picks.showing():
		pick_t += delta
	else:
		pick_t = 0.0
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
			return [n, 0 if not n.carrot else int(main._wish_hat())]
	return []


## Where the bot wants to walk.
func _tv_goal(slot: int, idx: int) -> Vector3:
	var a: Node3D = main.avatars[slot]
	var need := _needy()
	if idx == 0 and not need.is_empty() and main.vr_rig == null:
		var kind: int = need[1]
		if int(main.carry.get(slot, -1)) == kind:
			return (need[0] as Node3D).position
		return main.box_for(kind)
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
	var goal := _tv_goal(slot, idx)
	if main.picks != null and main.picks.showing() and pick_t > 0.5:
		var o: Vector3 = main.picks.orb_position(slot % 3)  # walk under a pick orb (each player its own)
		if o != Vector3.INF:
			goal = o
	elif main.hazards != null and not main.hazards.now.is_empty():
		var away := _escape(a.position, main.hazards.now)
		if away != Vector3.INF:
			goal = away
	var d := goal - a.position
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


## Where to step to get out of a told surprise (INF: already clear).
func _escape(p: Vector3, hz: Dictionary) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if not main.Deep.inside(hz, flat, 0.7):
		return Vector3.INF
	var out := Vector2.ZERO
	if String(hz.kind) == "sun":
		out = (flat - Vector2(float(hz.x), float(hz.z))).normalized()
	else:
		var dir := Vector2(float(hz.dx), float(hz.dz)).normalized()
		var n := Vector2(-dir.y, dir.x)
		out = n if (flat - Vector2(float(hz.x), float(hz.z))).dot(n) >= 0.0 else -n
	if out == Vector2.ZERO:
		out = Vector2(1.0, 0.0)
	var to := flat + out * 2.5
	if to.length() > main.ARENA - 0.8:
		to = flat - out * 2.5  # (cornered: the other side)
	return Vector3(to.x, 0.0, to.y)


# --- Fake VR builder ------------------------------------------------------------------------

func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig)  # the standard fake player (VrRig.fake_eye, x world_scale)
	if rig.hand_r.position == Vector3.ZERO:
		kit.vr_idle(rig)
	rig.hand_l.position = Vector3(-0.45, 1.5, 0.25)  # the left hand waves up and back, clear of the right
	if main.picks != null and main.picks.showing():
		# A VR builder alone reaches into an orb on purpose and holds it (with TV players: after they've had a go).
		kit.vr_stick(rig, Vector2.ZERO)
		kit.vr_trigger(rig, 0.0)
		var o: Vector3 = main.picks.orb_position(1)
		if o != Vector3.INF and (kit.tv_players() == 0 or pick_t > 5.0) and pick_t > 1.0:
			kit.vr_reach(rig, 1, o, 1.5, delta)
		else:
			var h: Vector3 = rig.head_position()
			kit.vr_reach(rig, 1, h + Vector3(0.5, -0.5, 0.3), 3.0, delta)
		return
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
			vr_target = main.box_for(int(need[1])) + Vector3.UP * (main.BOX_TOP + 0.1)
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
		vr_placed += 1


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
	print("BOT DEEP: mode=%s %s picks=%s town=%s gift=%s difficulty=%s" % [mode, str(deep), str(main.picks.history), str(main.town.count), main.gift, main.difficulty])
	kit.assert_true(deep.has("orbs_seen"), "%s: the pick orbs showed" % mode)
	if mode != "client":
		var stages: Array = main.picks.history.map(func(h: Array) -> String: return String(h[0]))
		kit.assert_true(stages.has("mode"), "%s: the mode pick was taken (%s)" % [mode, str(main.picks.history)])
		kit.assert_true(stages.has("gift") or int(main.session_round) < 2, "%s: Tumble's gift pick came before day 2 (%s)" % [mode, str(main.picks.history)])
		if kit.tv_players() > 0 or main.vr_rig != null:
			kit.assert_true(main.picks.history.any(func(h: Array) -> bool: return int(h[2]) >= 0), "%s: a player really took a pick (%s)" % [mode, str(main.picks.history)])
		var runs: Array = main.Telemetry.read("snowman_maker")
		kit.assert_true(not runs.is_empty() and runs[runs.size() - 1].has("difficulty") and runs[runs.size() - 1].has("surprises"),
			"%s: the telemetry line has the second-pass fields" % mode)
	kit.assert_true(deep.has("told_sun") or deep.has("told_slide"), "%s: a surprise was told on the snow (%s)" % [mode, str(deep)])
	kit.assert_true(not deep.has("untold"), "%s: no surprise went without its tell (%s)" % [mode, str(deep)])
	kit.assert_true(String(deep.get("dressed", "")) != "" and String(deep.get("dressed", "")) == String(main.season), "%s: the garden is dressed for the season (%s)" % [mode, str(deep)])
	kit.assert_true(main.town != null and main.town.count >= 0, "%s: Tumble's snow town is built" % mode)
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(kit.seated(), kit.seated_want(want, host_p), "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	kit.assert_true(kit.seen("phase", "results") > 0, "%s: the results showed" % mode)
	kit.assert_eq(main.stack_nodes.size(), (main.net.state_get("stacks", {}) as Dictionary).size(),
		"%s: every snowman in the store is drawn" % mode)
	if mode != "client":
		kit.assert_true(main.total_rolled > 1.0, "%s: snow was rolled" % mode)
		kit.assert_true(main.total_stacked > 0, "%s: snowballs were stacked" % mode)
	if main.vr_rig != null:
		# Progress, not a whole snowman: under load the VR builder sometimes has not finished one by the check
		# (failed ~1 run in 5 in parallel runs, 2026-10-30).
		kit.assert_true(main.total_made > 0 or vr_placed > 0, "%s: the VR builder built (%d snowmen made, %d pieces placed)" % [mode, main.total_made, vr_placed])
	# The snow day: a seeded garden on every machine, the same one; the story HUD; the visitor.
	var d: Dictionary = main.net.state_get("day", {})
	kit.assert_true(not main.garden.is_empty() and main.garden_key == "%d:%d" % [int(d.get("seed", -1)), int(d.get("chapter", -1))],
		"%s: this machine built the day's garden (%s)" % [mode, main.garden_key])
	kit.assert_eq(main.boxes.size(), (main.Story.chapter(int(d.get("chapter", 0))).hats as Array).size() + 1, "%s: a carrot box + one per hat" % mode)
	kit.assert_true((d.get("goals", []) as Array).size() == 3, "%s: the day has star goals" % mode)
	kit.assert_true(main.visitor != null and is_instance_valid(main.visitor), "%s: a visitor is wishing" % mode)
	if main.split != null:
		kit.assert_true(main.star_icons.has(-1), "%s: the stars show on the TV" % mode)
	if mode != "client":
		var runs: Array = main.Telemetry.read("snowman_maker")
		kit.assert_true(not runs.is_empty() and runs[runs.size() - 1].has("stars"), "%s: a telemetry line per day" % mode)
