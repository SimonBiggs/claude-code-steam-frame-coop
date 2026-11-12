extends Node
## Headless bot for games/whack_a_mole. BOT_PLAYERS=n TV kids drop in and run to moles and press A.
## BOT_VR=1 (local / host): a fake VR player walks up and swings the mallet down onto moles.
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/whack_a_mole_bot.tscn
## Networked:  DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).
## Solo VR: BOT_SOLO=1 BOT_VR=1 (the giant alone, no TV kids).
## Second pass (deep.gd): TV bots run into a pick orb (mode, crop, hammer gift), the giant alone bonks one; one clumsy
## kid runs into a told stampede; checks the mode, the gift, warned tricks on every machine, the season's dress and the
## holiday garden.

const BotKit := preload("res://tests/bot_kit.gd")
const Story := preload("res://games/whack_a_mole/story.gd")
const Deep := preload("res://games/whack_a_mole/deep.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var saw_pick := false  # Fig's bed filled and the team bonked a seed packet (story.gd)
var saw_kinds := {}
var saw_moles := 0  # most moles in a generated round seen
var bonk_cd := {}
var swing_phase := 0  # fake VR: 0 = raise above a mole, 1 = swing down
var swing_hole := -1
var orbs_seen := {}  # stage -> true (every machine)
var tricks_max := 0
var was_down := false  # a local hammer-kid sat bumped (every machine)
var vr_took := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/whack_a_mole/main.tscn").instantiate()
	main.set("round_time", 14.0)
	main.set("fresh_save", true)  # a brand-new garden every run
	main.set("need_scale", 0.15)  # tiny beds: round 1 fills one, round 2 starts with the crop pick
	main.set("pick_wait_scale", 0.35)  # short waits on the pick orbs
	main.set("trick_scale", 6.0)  # a few warned tricks even in a short round
	main.set("holiday_every", 3)  # moles go on holiday quickly
	add_child(main)
	kit.main = main
	kit.watch_state(main.net)  # phases counted as they happen (kit.seen): a 0.25 s poll misses quick ones under load
	want = 0 if OS.has_environment("BOT_SOLO") else BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host and BotKit.lead_machine() and want > 0:  # (the giant alone has no pad to press Start with)
		kit.at(t0 + 6.0, "P1 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 6.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and not main.tv_banner.visible, "Start pauses (on_pause_changed made the banner; the open pause menu alone says PAUSED)")
			_press("start"))
		kit.at(t0 + 7.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	if want > 0:  # (solo VR stays solo)
		kit.drop_in_out(main.party, t0 + 9.0, 3.0, func(slot: int) -> bool:
			return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		var end := float(OS.get_environment("BOT_HOST_END")) if OS.has_environment("BOT_HOST_END") else 46.0  # late-join tests
		kit.at(end - 10.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(end, "finish", kit.finish)
	else:
		# Clients leave a little before the host (BOT_HOST_END given to every machine: tools/multibot.ts --env); a machine
		# that joined late (BOT_LATE) counts its clock from its own start.
		var fin := 37.0 if client else 44.0
		if client and OS.has_environment("BOT_HOST_END"):
			fin = float(OS.get_environment("BOT_HOST_END")) - 5.0 - float(OS.get_environment("BOT_LATE") if OS.has_environment("BOT_LATE") else "0")
		kit.at(fin, "finish", func() -> void:
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
		if main.vr_rig != null and kit.tv_players() == 0:
			kit.vr_click(main.vr_rig)  # solo VR: the VR player's trigger / A on the results card goes on
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
	if main.picks != null and main.picks.showing():
		orbs_seen[main.picks.orbs.stage] = true
	saw_pick = saw_pick or orbs_seen.has("crop")
	tricks_max = maxi(tricks_max, main.tricks.seen)
	for sl in main.stunned:
		was_down = was_down or float(main.stunned[sl]) > 0.0
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
	var goal := Vector3.INF
	if String(main.net.state_get("phase", "")) == "orbs":
		goal = main.picks.orb_position(slot % 3) if main.picks.showing() else Vector3.INF  # run into a pick orb
		if goal == Vector3.INF:
			goal = main.picks.orb_position(0) if main.picks.showing() else a.position
		i = -1
	elif slot == main.party.local_slots()[0] and _herd_spot() != Vector3.INF:
		goal = _herd_spot()  # the clumsy kid: runs into a told stampede (tests the bump on every machine)
		i = -1
	if goal != Vector3.INF:
		var dg: Vector3 = goal - a.position
		dg.y = 0.0
		if dg.length() > 0.05:
			v = _stick_to(slot, dg.normalized())
	if i >= 0:
		var d: Vector3 = main.holes[i] - a.position
		d.y = 0.0
		if d.length() > 0.25:
			v = _stick_to(slot, d.normalized())
		if d.length() < 0.35 and float(bonk_cd[slot]) <= 0.0:
			bonk_cd[slot] = 0.3
			kit.slot_press(main.party, slot, "accept")
	kit.slot_stick(main.party, slot, "left", v)


## The stick that walks this kid's way along `d` (seen from its camera).
func _stick_to(slot: int, d: Vector3) -> Vector2:
	var cam: Camera3D = main.split.active_camera(slot)
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var r := Vector3(-f.z, 0.0, f.x)
	return Vector2(d.dot(r), -d.dot(f))


## The middle of a stampede band being told now, or INF.
func _herd_spot() -> Vector3:
	for e in main.tricks.tells_now():
		if String(e.kind) == "stampede":
			var b := Deep.band(int(e.data))
			return Vector3(0.3, main.holes[0].y, (b[0] as Vector3).z)
	return Vector3.INF


## Fake VR: walk near a mole, raise the mallet above it, swing it down.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig)  # the standard fake player (VrRig.fake_eye, x world_scale)
	if String(main.net.state_get("phase", "")) == "orbs":  # the giant alone: bonk the right-hand pick orb with the mallet
		var o: Vector3 = main.picks.orb_position(mini(2, main.picks.orbs.orbs.size() - 1)) if main.picks.showing() else Vector3.INF
		kit.vr_stick(rig, Vector2.ZERO)
		if o != Vector3.INF and main.party.player_count() == 0:
			var off: Vector3 = main.mallet_head.global_position - rig.hand_r.global_position
			if kit.vr_reach(rig, 1, o - off + (Vector3(0.0, 0.35, 0.0) if swing_phase == 0 else Vector3.ZERO), 2.5, delta):
				swing_phase = 1 - swing_phase  # (a swing at the orb, like at a mole: a resting mallet never picks)
			vr_took = vr_took or main.picks.chosen_by == 0
		return
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


func _vr_took_any() -> bool:
	for h in main.picks.history:
		if int(h[2]) == 0:
			return true
	return false


func _checks() -> void:
	var mode: String = main.net.mode
	# Second pass (deep.gd) on every machine.
	kit.assert_true(orbs_seen.has("mode") or mode == "client", "%s: the mode was picked on the pick orbs (%s)" % [mode, str(orbs_seen.keys())])
	kit.assert_true(orbs_seen.has("gift") or mode == "client", "%s: Fig's hammer gifts were offered on the pick orbs" % mode)
	kit.assert_true(String(main.net.state_get("mode", "")) in ["gentle", "brave", "hard"], "%s: a mode reached this machine (%s)" % [mode, str(main.net.state_get("mode", ""))])
	kit.check_host_mode(main.net, String(main.mode))  # every machine plays at the host's mode (2026-11-12)
	kit.assert_true(tricks_max > 0, "%s: warned tricks were told by rings here (%d)" % [mode, tricks_max])
	kit.assert_true(main.shown_season == main.season and not main.season_nodes.is_empty(), "%s: the garden wears its %s dress" % [mode, main.season])
	kit.assert_true(main.garden.holiday_n > 0, "%s: moles went on holiday in Fig's garden (%d)" % [mode, main.garden.holiday_n])
	if mode == "client":
		kit.info("client: a local hammer-kid sat bumped: %s; gift %s" % [was_down, main.gift])
	else:
		kit.info("tricks fired %s, stats %s, picks %s" % [str(main.tricks.fired), str(main.stats), str(main.picks.history)])
		kit.assert_true(not main.tricks.fired.is_empty(), "host: tricks happened")
		kit.assert_true(String(main.save.data.mode) == main.mode, "host: the mode was saved")
		kit.assert_true(int(main.save.data.moles_total) > 0, "host: bonked moles were counted for the holiday garden")
		if int(main.tricks.fired.get("stampede", 0)) > 0 and not main.avatars.is_empty() and int(main.stats.herd) > 0:
			kit.assert_true(int(main.stats.bumped) > 0, "host: the clumsy kid in a stampede was bumped")
		if main.vr_rig != null and main.party.player_count() == 0:
			kit.assert_true(vr_took or _vr_took_any(), "solo giant: the mallet took a pick orb")
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(kit.seated(), kit.seated_want(want, host_p), "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("whacked", 0)) > 1, "%s: moles were whacked" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	if main.vr_rig != null:
		kit.assert_true(main.vr_whacks > 0, "the fake VR player whacked moles with the mallet")
	if mode != "client":
		kit.assert_true(kit.seen("phase", "practice") > 0, "the round started with a practice mole")
		kit.assert_true(saw_pick, "%s: Fig's bed filled and the next round began with the crop pick orbs" % mode)
		kit.assert_true(Story.beds_grown(main.save.data.beds) >= 1, "%s: a bed grew in Fig's garden (%s)" % [mode, str(main.save.data.beds)])
		kit.assert_true(String(main.save.data.cur) not in [Story.FIRST_CROP, ""] or Story.beds_grown(main.save.data.beds) >= 2,
			"%s: a new crop was planted (%s, %s)" % [mode, String(main.save.data.cur), str(main.save.data.beds)])
		kit.assert_true(saw_moles > 5, "%s: the rounds came from roundgen.gd (%d moles)" % [mode, saw_moles])
	var gs: Dictionary = main.net.state_get("garden", {})
	kit.assert_true(gs.has("beds") and int(gs.get("need", 0)) > 0, "%s: the garden state reached this machine (%s)" % [mode, str(gs)])
	kit.assert_true(main.garden != null and main.garden.state.has("beds"), "%s: the garden is drawn" % mode)
	kit.assert_true((main.net.state_get("goal", []) as Array).size() == 3 or String(main.net.state_get("phase", "")) != "play", "%s: the star goal is known" % mode)
