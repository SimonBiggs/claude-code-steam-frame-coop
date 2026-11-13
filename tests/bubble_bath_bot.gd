extends Node
## Headless bot for games/bubble_bath. BOT_PLAYERS=n TV boats (default 2) collect ducks and sail them
## to the plug-hole. BOT_VR=1 (local / host): a fake VR player slaps the water with the left glove and
## grabs ducks with the right glove (trigger) and throws them at the plug-hole.
## Local:      godot-test --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/bubble_bath_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).
## Second pass: the mode pick and Mama Duck's gift pick on the pick orbs (boats sail under one, the VR glove reaches
## into one), warned surprises from a short round's first seconds (main.bot_surprises) that the boats sail out of,
## the season and Mama's pond. Phases are counted with kit.watch_state (never polled).

const BotKit := preload("res://tests/bot_kit.gd")
const BathGen := preload("res://games/bubble_bath/bathgen.gd")

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
var escapes := 0  # frames a boat sailed out of a told surprise

const Deep := preload("res://games/bubble_bath/deep.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/bubble_bath/main.tscn").instantiate()
	main.set("round_time", 16.0)  # short rounds: results and round 2 happen in the test
	if not OS.has_environment("DUO_JOIN"):
		main.set("bot_surprises", true)  # warned surprises from 3 s into the short rounds (the host decides them)
	add_child(main)
	kit.watch_state(main.net)  # count phases as they happen (picks, results)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	kit.at(t0 + 4.0, "P2 presses Y: one shared view", func() -> void: _press_y())
	kit.at(t0 + 5.0, "shared?", func() -> void:
		if main.split != null and not main.flat_host and BotKit.lead_machine():
			kit.assert_true(main.split.is_shared(), "Y switched to the shared view"))
	kit.at(t0 + 8.0, "P2 presses Y again: split screen", func() -> void: _press_y())
	kit.at(t0 + 9.0, "split?", func() -> void:
		if main.split != null and not main.flat_host and BotKit.lead_machine():
			kit.assert_true(not main.split.is_shared(), "Y switched back to split screen"))
	if not host and BotKit.lead_machine():
		kit.at(t0 + 10.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 10.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and not main.tv_banner.visible, "Start pauses the game (on_pause_changed made the banner; the open pause menu alone says PAUSED)")
			_press("start"))
		kit.at(t0 + 11.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused and not main.tv_banner.visible, "Start again resumes")
			kit.allow_pause = false)
	kit.drop_in_out(main.party, t0 + 12.0, 3.0, func(slot: int) -> bool:
		return main.boats.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		kit.at(43.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(47.0, "finish", kit.finish)
	else:
		kit.at(42.0 if client else 45.0, "finish", func() -> void:
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
	if not BotKit.lead_machine():
		return  # one machine tests the shared view (BotKit.lead_machine)
	if not main.flat_host:
		_press("y")


func _press(action: String) -> void:
	var slots: Array[int] = main.party.local_slots()
	if not slots.is_empty():
		kit.slot_press(main.party, slots[0], action)


func _picking() -> bool:
	return String(main.net.state_get("phase", "")) == "pick" and not main.picks.orbs.orbs.is_empty()


## The orb this seat goes for (each seat its own, so the first one there decides).
func _orb_for(slot: int) -> Vector3:
	var n: int = main.picks.orbs.orbs.size()
	return main.picks.orb_position(posmod(slot + 1, maxi(1, n))) if n > 0 else Vector3.INF


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
	var target: Vector3 = main.drain
	var train_n: int = (main.trains.get(slot, []) as Array).size() if main.net.mode != "client" else 0
	var duck := _nearest_duck(b.position, true)
	if duck != null and train_n < 2 and (main.net.mode != "client" or fmod(kit.t + slot, 8.0) < 5.0):
		target = duck.position
	var slow := 1.0
	if _picking() and _orb_for(slot) != Vector3.INF:
		target = _orb_for(slot)  # sail under an orb (and stay there)
		slow = clampf(Vector2(target.x - b.position.x, target.z - b.position.z).length() / 0.8, 0.15, 1.0)
	var away := _out_of_tells(b.position)
	if away != Vector3.INF:
		target = away  # a surprise is told here: sail out of it
		escapes += 1
	var d := target - b.position
	d.y = 0.0
	# Sail round the sponge islands: push sideways off any island just ahead.
	for o in main.islands:
		var to := Vector3(o.x, 0.0, o.y) - Vector3(b.position.x, 0.0, b.position.z)
		var ahead := to.dot(d.normalized()) if d.length() > 0.01 else -1.0
		if ahead > 0.0 and ahead < d.length() + 0.2 and to.length() < float(o.z) + 1.0:
			var side := d.normalized().cross(Vector3.UP)
			var lat := to.dot(side)
			if absf(lat) < float(o.z) + 0.45:
				d = d.normalized() - side * signf(lat if lat != 0.0 else 1.0) * 1.5
	var v := Vector2.ZERO
	if d.length() > 0.05 and main.split != null:
		d = d.normalized()
		var cam: Camera3D = main.split.active_camera(slot)
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		v = Vector2(d.dot(r), -d.dot(f)) * slow
	kit.slot_stick(main.party, slot, "left", v)


## A point out of the surprise told where the boat is (Vector3.INF: none here).
func _out_of_tells(p: Vector3) -> Vector3:
	for e in main.hazards.tells_now():
		var pad: float = Deep.BOAT_R + 0.35
		if not Deep.inside(e, Vector2(p.x, p.z), pad):
			continue
		var c := Vector3(float(e.x), p.y, float(e.z))
		if String(e.kind) == "whale":
			var out := Vector3(p.x - c.x, 0.0, p.z - c.z)
			out = out.normalized() if out.length() > 0.05 else Vector3.BACK
			return c + out * (float(e.r) + 1.0)
		var dir := Vector3(float(e.dx), 0.0, float(e.dz)).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var lat := (p - c).dot(side)
		var s := signf(lat) if absf(lat) > 0.05 else 1.0
		var on_line := p - side * lat
		var to := on_line + side * s * (float(e.r) + 1.0)
		if absf(to.x) > main.HX - 0.4 or absf(to.z) > main.HZ - 0.4:
			to = on_line - side * s * (float(e.r) + 1.0)  # (the other side has room)
		return to
	return Vector3.INF


## Fake VR: slap the water with the left glove now and then; grab a duck with the right glove and
## fling it at the plug-hole.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig)  # the standard fake player (VrRig.fake_eye, x world_scale)
	var head: Vector3 = rig.head_position()
	if _picking():  # reach into an orb with the right glove and hold it there
		var o := _orb_for(0)
		kit.vr_reach(rig, 1, o if o != Vector3.INF else head + Vector3(0.25, -0.5, -0.35), 2.5, delta)
		kit.vr_reach(rig, 0, head + Vector3(-0.25, -0.5, -0.3), 3.0, delta)
		vr_phase = "rest"
		return
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
			var aim: Vector3 = main.drain + Vector3.UP * 1.2
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
	return "BOT %s: players %s, ducks %d, score %d/%d, total %d, vr throws %d, longest train %d, islands %d, phase %s, mode %s, gift %s, surprise %s, escapes %d" % [main.net.mode,
		str(main.party.active_slots()), main.ducks.size(), int(main.net.state_get("score", 0)), int(main.net.state_get("goal", 0)),
		int(main.net.state_get("total", 0)), vr_throws, max_train, main.islands.size(), String(main.net.state_get("phase", "")), main.mode,
		main.gift, str(main.hazards.tells_now().map(func(e: Dictionary) -> String: return String(e.kind))), escapes]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(kit.seated(), kit.seated_want(want, host_p), "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.boats.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("total", 0)) > 0, "%s: ducks went down the plug" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	kit.assert_true(main.ducks.size() > 0, "%s: ducks float in the tub" % mode)
	kit.assert_true(not main.plan.is_empty() and int(main.plan.n) >= 2, "%s: the seeded bath is built (round %d)" % [mode, int(main.plan.get("n", 0))])
	kit.assert_eq(main.islands.size(), main.island_root.get_child_count(), "%s: the sponge islands are in the tub" % mode)
	kit.assert_true(main.mama != null and main.mama.get_child_count() > 0, "%s: Mama Duck sits on the rim" % mode)
	kit.assert_true(BathGen.check(main.plan).is_empty(), "%s: this round's bath is fair (%s)" % [mode, str(BathGen.check(main.plan))])
	kit.assert_true(int(main.net.state_get("goal", 0)) > 0, "%s: Mama Duck set a duck goal" % mode)
	# Second pass.
	kit.assert_true(kit.seen("phase", "pick") > 0, "%s: the team picked on the pick orbs (%d picks)" % [mode, kit.seen("phase", "pick")])
	kit.assert_true(kit.seen("phase", "results") > 0, "%s: a round ended with results" % mode)
	kit.check_host_mode(main.net, main.mode)
	kit.assert_true(Deep.MODES.has(main.mode) and main.season != "" and main.pond.season == main.season, "%s: the mode (%s) and the season (%s) are set" % [mode, main.mode, main.season])
	kit.assert_true(main.pond.water != null and main.pond.get_node_or_null("SeasonProps") != null, "%s: Mama's pond and the season's props are built" % mode)
	kit.assert_true(int(main.pond.count) == Deep.pond(int(main.save.data.goals)) if mode != "client" else int(main.pond.count) == int(main.net.state_get("pond", 0)), "%s: Mama's pond has its pieces (%d)" % [mode, int(main.pond.count)])
	kit.assert_true(not main.hazards.seen.is_empty(), "%s: a warned surprise showed its rings on the water (%s)" % [mode, str(main.hazards.seen)])
	kit.assert_true(main.gift != "" and not Deep.gift(main.gift).is_empty(), "%s: Mama Duck's gift is on for round 2 (%s)" % [mode, main.gift])
	if mode != "client":
		var stages: Array = main.picks.history.map(func(h: Array) -> String: return String(h[0]))
		kit.assert_true(stages.has("mode") or BotKit.mode_forced(main.net, "BB_MODE"), "the mode pick was taken (%s)" % str(main.picks.history))
		kit.assert_true(stages.has("gift"), "Mama Duck's gift pick was taken (%s)" % str(main.picks.history))
		kit.assert_true(String(main.save.data.mode) != "" or BotKit.mode_forced(main.net, "BB_MODE"), "the mode is saved")
		kit.assert_true(int(main.hz_count) > 0 or int(main.save.data.surprises) > 0, "the host told surprises (%d)" % int(main.save.data.surprises))
	if mode != "client":
		kit.assert_true(int(main.save.data.days) >= 1 and int(main.save.data.rounds) >= 2, "rounds and play-days are saved")
		kit.assert_true(int(main.save.data.goals) > 0 and main.family_root.get_child_count() > 0, "the team reached a goal and a toy sits on the rim (%d goals)" % int(main.save.data.goals))
	if mode != "client":
		kit.assert_true(max_train > 0 or main.net.mode == "host", "boats towed ducks")
	if main.vr_rig != null:
		kit.assert_true(vr_throws > 0, "fake VR player grabbed and threw ducks")
		kit.assert_true(int(main.splashes) > 3, "the fake VR glove splashed the water (%d)" % int(main.splashes))
	if mode == "client" and main.vr_avatar != null:
		kit.assert_true(int(main.splashes) > 3, "client: splashes from the VR player arrived (%d)" % int(main.splashes))
		kit.assert_true(main.vr_avatar != null, "client: the VR player is drawn on the TV")
