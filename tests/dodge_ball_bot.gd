extends Node
## Headless bot for games/dodge_ball (Soft Dodgeball).
## BOT_PLAYERS=n TV runners (default 2) run to loose balls and throw them at the giant's belly.
## BOT_VR=1 (local / host): a fake VR giant grabs balls from the tray and flings them at runners.
## BOT_HOST_VR=1 on the TV machine: the host has a (fake) VR giant, so hits are not checked.
## BOT_SOLO=1 with BOT_VR=1: nobody joins on the TV (VR alone: CPU runners fill in).
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/dodge_ball_bot.tscn
## Networked: DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).
## Second pass (deep.gd): the runners walk under a pick orb and stand there (the VR giant alone reaches into one), and
## run out of TumTum's warned tricks (DB_TRICKS_NOW is set: tricks from a round's first seconds, round 1 too;
## BOT_NO_TRICKS=1 for none).

const BotKit := preload("res://tests/bot_kit.gd")
const Telemetry := preload("res://core/telemetry.gd")
const Seeded := preload("res://core/seeded.gd")
const Deep := preload("res://games/dodge_ball/deep.gd")

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
var cpu_throws := 0  # most CPU giant throws seen in one round (host / local only: round_stats)
var inside_cushion := false
var start_unix := 0.0
var saw_orbs := false
var saw_vr_orbs := false
var dodged := 0  # times a bot runner ran out of a told trick


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	if not OS.has_environment("BOT_NO_TRICKS"):
		OS.set_environment("DB_TRICKS_NOW", "1")
	main = load("res://games/dodge_ball/main.tscn").instantiate()
	main.set("round_time", 18.0)
	main.set("results_wait", 6.0)
	add_child(main)
	kit.main = main
	kit.watch_state(main.net)  # phases counted as they happen (kit.seen): a 0.25 s poll misses quick ones under load
	want = 0 if OS.has_environment("BOT_SOLO") else BotKit.bot_players(2, 6)  # BOT_SOLO: VR alone
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV runners press A on their pads" % want, _join)
	if not host and want > 0 and BotKit.lead_machine():
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
		kit.at(58.0, "host checks", _checks)
		kit.at(62.0, "finish", kit.finish)
	else:
		kit.at(42.0 if client else 44.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.5, _watch_results)
	kit.every(0.25, _watch_cushions)
	start_unix = Time.get_unix_time_from_system() - 1.0


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
	max_tv = maxi(max_tv, int(main.net.state_get("tv_score", 0)))
	max_giant = maxi(max_giant, int(main.net.state_get("giant_score", 0)))
	if main.round_stats is Dictionary:
		cpu_throws = maxi(cpu_throws, int(main.round_stats.get("cpu_throws", 0)))
	if main.picks != null and main.picks.showing():
		saw_orbs = true
		saw_vr_orbs = saw_vr_orbs or bool(main.picks.vr_row)
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
	var here := Vector2(a.position.x, a.position.z)
	# Pick orbs over the court: walk under one (each bot its own) and stand there.
	if main.picks.showing() and not main.picks.vr_row and not main.picks.spots.is_empty():
		var sp: Vector3 = main.picks.spots[slot % main.picks.spots.size()]
		kit.slot_stick(main.party, slot, "left", _toward(slot, a.position, Vector3(sp.x, 0.0, sp.z), 0.25))
		return
	# A trick told: run out of it.
	for e in main.hazards.tells_now():
		if Deep.inside(e, here, Deep.HIT_PAD + Deep.ESCAPE_PAD):
			var q := Deep.escape(main.rd, e, here)
			if q != Vector2.INF:
				if float(hold_t.get("dodge%d" % slot, -1.0)) < 0.0:
					dodged += 1
				hold_t["dodge%d" % slot] = 1.0
				kit.slot_stick(main.party, slot, "left", _toward(slot, a.position, Vector3(q.x, 0.0, q.y), 0.1))
				return
	hold_t["dodge%d" % slot] = -1.0
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


## The stick that walks runner slot from p to goal (zero when within near).
func _toward(slot: int, p: Vector3, goal: Vector3, near: float) -> Vector2:
	var d := goal - p
	d.y = 0.0
	if d.length() < near:
		return Vector2.ZERO
	d = d.normalized()
	var cam: Camera3D = main.split.active_camera(slot)
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var r := Vector3(-f.z, 0.0, f.x)
	return Vector2(d.dot(r), -d.dot(f))


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
	kit.vr_head_home(rig)  # the standard fake player (VrRig.fake_pose)
	rig.camera.basis = Basis()
	rig.hand_l.position = Vector3(-0.3, 1.0, -0.3)
	vr_t += delta
	if main.picks.showing() and main.picks.vr_row:  # the small orbs in front of the giant: reach into one and stay
		kit.vr_trigger(rig, 0.0)
		var op: Vector3 = main.picks.orb_position(0)
		if op != Vector3.INF and vr_t > 1.0:
			kit.vr_reach(rig, 1, op, 1.2, delta)
		vr_phase = "reach"
		return
	if main.picks.showing():
		kit.vr_trigger(rig, 0.0)
		vr_phase = "reach"
		vr_t = 0.0
		return
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
	kit.check_host_mode(main.net, main.mode)  # the TV plays at the host's difficulty (2026-11-12)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	elif mode == "local":  # (the host checks after the TV machine has gone)
		var host_p := 0
		kit.assert_eq(kit.seated(), kit.seated_want(want, host_p), "%s: all %d players are seated" % [mode, want])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(kit.seen("phase", "results") > 0, "%s: the round ended with results" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: the next round started by itself" % mode)
	kit.assert_true(max_tv > 0, "%s: runners hit the giant's belly (%d)" % [mode, max_tv])
	if OS.has_environment("BOT_VR") and mode != "client":
		kit.info("the fake VR giant hit runners %d times (aim is luck: not checked)" % max_giant)
	elif not (mode == "client" and OS.has_environment("BOT_HOST_VR")):
		# The gentle giant aims with a wobble on purpose, so in a short networked run (BOT_DEADLINE) it could miss every
		# runner: "the giant hit runners (0)" failed about 1 run in 3 (2026-10-30). What's checked is that it plays:
		# the computer giant throws at runners (host / local); hits are only reported.
		if mode == "client":
			kit.info("the giant hit runners %d times (seen on the client)" % max_giant)
		else:
			kit.assert_true(cpu_throws > 0 or max_giant > 0, "%s: the computer giant threw at runners (%d throws, %d hits)" % [mode, cpu_throws, max_giant])
	if want == 0 and main.vr_rig != null:
		kit.assert_eq(main.cpu.size(), 2, "VR alone: two CPU runners fill in")
	if main.vr_rig != null:
		kit.assert_true(vr_grabs > 0 and vr_throws > 0, "fake VR giant grabbed and threw balls")
	elif mode != "client":
		kit.assert_true(main.g_cpu, "no VR: the computer is the giant")
	_story_checks(mode)


## The seeded park round, TumTum's story cards, the park that grows, fair throws and the RUN lines.
func _story_checks(mode: String) -> void:
	var rd: Dictionary = main.rd
	kit.assert_true(not rd.is_empty(), "%s: this round's park is built" % mode)
	_deep_checks(mode)
	kit.assert_eq(int(rd.get("code", -1)), int(main.net.state_get("court", -2)), "%s: the round matches the host's code" % mode)
	kit.assert_eq(main.world.cushions.size(), (rd.get("cushions", []) as Array).size(), "%s: every cushion is drawn" % mode)
	kit.assert_true(not inside_cushion, "%s: no runner ever stood inside a cushion" % mode)
	kit.assert_true(not main.story_shown.is_empty(), "%s: TumTum's story cards showed (%s)" % [mode, str(main.story_shown)])
	var items: Array = main.net.state_get("park", [])
	kit.assert_eq(main.park.things.size(), mini(items.size(), 23), "%s: the park shows every thing in it" % mode)
	kit.info("%s: park %d things, story pictures %s, round %s (level %d%s)" % [mode, items.size(), str(main.story_shown),
		str(rd.get("name", "")), int(rd.get("level", 0)), ", TODAY'S PARK" if bool(rd.get("daily", false)) else ""])
	if mode == "client":
		return
	kit.assert_true(main.story_shown.has("tumtum"), "%s: TumTum said hello" % mode)
	kit.assert_true(int(main.save.data.rounds) >= 1 and items.size() >= 1, "%s: a finished round planted something in the park" % mode)
	kit.assert_true(String(main.save.data.daily) == Seeded.today(), "%s: TODAY'S PARK was played today" % mode)
	var runs := Telemetry.read("dodge_ball")
	var rounds := 0
	for r in runs:
		if str(r.get("end", "")) == "round" and float(r.get("t", 0.0)) >= start_unix:
			rounds += 1
	kit.assert_true(rounds >= 1, "%s: a RUN line per round (%d)" % [mode, rounds])
	if main.g_cpu and main.aimed.size() >= 2:
		var lo := 1 << 30
		var hi := 0
		for id in main.aimed:
			lo = mini(lo, int(main.aimed[id]))
			hi = maxi(hi, int(main.aimed[id]))
		kit.assert_true(hi - lo <= maxi(2, ceili(float(hi) * 0.25)), "%s: TumTum shares his throws out fairly %s" % [mode, str(main.aimed)])


func _watch_cushions() -> String:
	var rd: Dictionary = main.rd
	for id in main.avatars:
		var a: Node3D = main.avatars[id]
		for c in rd.get("cushions", []):
			if Vector2(a.position.x - float(c[0]), a.position.z - float(c[1])).length() < float(c[2]) + 0.2:
				inside_cushion = true
				return "runner %d is inside a cushion at %s" % [int(id), str(a.position)]
	return ""


## Second pass: picks, tricks, seasons, toys (deep.gd).
func _deep_checks(mode: String) -> void:
	kit.assert_true(saw_orbs, "%s: the pick orbs showed" % mode)
	kit.assert_true(main.season_node != null and main.season_node.season != "", "%s: the park is dressed for the season (%s)" % [mode, main.season])
	kit.assert_true(main.toys_node != null and main.toys_node.count >= 0, "%s: TumTum's toys are drawn (%d)" % [mode, main.toys_node.count])
	kit.assert_true(Deep.MODES.has(main.mode), "%s: a mode is set (%s)" % [mode, main.mode])
	if not OS.has_environment("BOT_NO_TRICKS"):
		kit.assert_true(not main.hazards.seen.is_empty(), "%s: TumTum's tricks were told %s" % [mode, str(main.hazards.seen)])
	kit.info("%s: mode %s, gift %s, season %s, tricks seen %s, bots ran out of %d tells, vr orbs %s" % [mode, main.mode, main.gift,
		main.season, str(main.hazards.seen), dodged, str(saw_vr_orbs)])
	if mode == "client":
		return
	var stages: Array = main.picks.history.map(func(h: Array) -> String: return String(h[0]))
	kit.assert_true(stages.has("mode"), "%s: the mode was picked %s" % [mode, str(main.picks.history)])
	kit.assert_true(stages.has("gift"), "%s: a gift was picked before round 2 %s" % [mode, str(main.picks.history)])
	var people: bool = main._people() > 0
	var by_someone := false
	for h in main.picks.history:
		if int(h[2]) >= 0:
			by_someone = true
	if people or main.vr_rig != null:
		kit.assert_true(by_someone, "%s: a player really picked an orb (not just the wait) %s" % [mode, str(main.picks.history)])
	if main.vr_rig != null and not people:
		kit.assert_true(saw_vr_orbs, "%s: VR alone: the orbs float in front of the giant" % mode)
	kit.assert_true(String(main.save.data.mode) != "", "%s: the mode is saved" % mode)
