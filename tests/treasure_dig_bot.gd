extends Node
## Headless bot for games/treasure_dig. TV bots run to sparkles (or loose treasure), dig with A and
## carry what they find to the chest. BOT_VR=1: a fake giant points the telescope and pulls the
## trigger, pokes sparkles with its left glove, grabs treasure with the right and drops / throws it
## into the chest. BOT_PLAYERS=n TV players (default 2).
## Second pass (deep.gd): TV bots run into a pick orb (mode, island, Peg's tool), the giant alone touches one with
## a glove; checks the mode, the tool, warned events on every machine, the season's dress and the museum.
## Local:     godot-test --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/treasure_dig_bot.tscn
## Networked: DUO_PORT=81xx DUO_HOST=1 ... & DUO_PORT=81xx DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).
const UiKit := preload("res://core/ui_kit.gd")

const BotKit := preload("res://tests/bot_kit.gd")
const Deep := preload("res://games/treasure_dig/deep.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var results_seen_t := -1.0
var results_checked := false
var t := 0.0
var dig_t := {}  # slot -> seconds until the next A
var wander := {}  # slot -> Vector3 (client: somewhere to look)
var vr_phase := "aim"
var vr_t := 0.0
var vr_target := Vector3.ZERO
var vr_throw := false
var max_items_seen := 0
var max_sparkles_seen := 0
var saw_pick := false  # round 2 starts with Peg's two island signposts
var max_maps := 0
var saw_x := false
var kinds_seen := {}
var orbs_seen := {}  # stage -> true (every machine)
var events_max := 0
var vr_took := false
var was_down := false  # a local digger sat bonked (every machine)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/treasure_dig/main.tscn").instantiate()
	main.set("round_time", 12.0)
	main.set("fresh_save", true)  # a brand-new collection every run (story.gd)
	main.set("pick_wait_scale", 0.35)  # short waits on the pick orbs
	main.set("event_scale", 5.0)  # a few warned events even in a short round
	add_child(main)
	kit.main = main
	want = 0 if OS.has_environment("BOT_SOLO") else BotKit.bot_players(2, 6)  # BOT_SOLO=1 BOT_VR=1: the giant alone
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host and want > 0 and BotKit.lead_machine():
		kit.at(t0 + 8.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 8.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and not main.tv_banner.visible, "Start pauses and shows the banner (on_pause_changed made the banner; the open pause menu alone says PAUSED)")
			_press("start"))
		kit.at(t0 + 9.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused and not main.tv_banner.visible, "Start again resumes")
			kit.allow_pause = false)
	if want > 0:
		kit.drop_in_out(main.party, t0 + 10.0, 3.0, func(slot: int) -> bool:
			return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		var end := float(OS.get_environment("BOT_HOST_END")) if OS.has_environment("BOT_HOST_END") else 37.0  # late-join tests
		kit.at(end - 9.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(end, "finish", kit.finish)
	else:
		# Clients leave a little before the host (BOT_HOST_END given to every machine: tools/multibot.ts --env); a machine
		# that joined late (BOT_LATE) counts its clock from its own start.
		var fin := 31.0 if client else 36.0
		if client and OS.has_environment("BOT_HOST_END"):
			fin = float(OS.get_environment("BOT_HOST_END")) - 4.0 - float(OS.get_environment("BOT_LATE") if OS.has_environment("BOT_LATE") else "0")
		kit.at(fin, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.5, _continue_results)


func _continue_results() -> String:
	if not main.results_showing():
		results_seen_t = -1.0
		return ""
	if results_seen_t < 0.0:
		results_seen_t = t
		saw_results = true
	elif t - results_seen_t > 3.2:
		if not results_checked:
			results_checked = true
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


func _press(action: String) -> void:
	var slots: Array[int] = main.party.local_slots()
	if not slots.is_empty():
		kit.slot_press(main.party, slots[0], action)


func _physics_process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	max_items_seen = maxi(max_items_seen, main.items.size())
	if main.picks != null and main.picks.showing():
		orbs_seen[main.picks.orbs.stage] = true
	saw_pick = saw_pick or orbs_seen.has("island")
	events_max = maxi(events_max, main.events.seen)
	for sl in main.stunned:
		was_down = was_down or float(main.stunned[sl]) > 0.0
	max_maps = maxi(max_maps, int(main.net.state_get("maps", 0)))
	saw_x = saw_x or main.net.state_get("x", false) is Vector3
	if main.island.has("kind"):
		kinds_seen[String(main.island.kind)] = true
	var sp := 0
	for n in main.sparkle_nodes:
		if n.visible:
			sp += 1
	max_sparkles_seen = maxi(max_sparkles_seen, sp)
	for slot in main.party.local_slots():
		_steer(slot, delta)
	if main.vr_rig != null:
		_drive_vr(delta)


## TV bot: carrying -> chest; else loose treasure; else the nearest sparkle; dig when there.
func _steer(slot: int, delta: float) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	var target := Vector3.INF
	var carrying := false
	for id in main.items:
		if int(main.items[id]["carrier"]) == slot:
			carrying = true
	if String(main.net.state_get("phase", "")) == "orbs":
		target = main.picks.orb_position(slot % 3) if main.picks.showing() else Vector3.INF  # run into a pick orb
		if target != Vector3.INF:
			target.y = 0.0
		else:
			target = a.position
	elif slot == main.party.local_slots()[0] and _drop_spot() != Vector3.INF:
		target = _drop_spot()  # the clumsy digger: runs under a falling coconut (tests the bonk on every machine)
	elif carrying:
		target = Vector3.ZERO
	else:
		target = _nearest_loose(a.position)
		if target == Vector3.INF:
			target = _nearest_sparkle(a.position)
		if target == Vector3.INF and not main.hidden.is_empty():
			target = main.hidden[slot % main.hidden.size()][0]
		if target == Vector3.INF:
			if not wander.has(slot) or a.position.distance_to(wander[slot]) < 0.6:
				var ang := randf() * TAU
				wander[slot] = Vector3(cos(ang), 0.0, sin(ang)) * randf_range(2.0, 5.5)
			target = wander[slot]
	var d := target - a.position
	d.y = 0.0
	var v := Vector2.ZERO
	if d.length() > 0.35:
		d = d.normalized()
		var cam: Camera3D = main.split.active_camera(slot)
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		v = Vector2(d.dot(r), -d.dot(f))
	kit.slot_stick(main.party, slot, "left", v)
	dig_t[slot] = float(dig_t.get(slot, 0.0)) - delta
	if not carrying and float(dig_t[slot]) <= 0.0 and (target - a.position).length() < 1.0:
		dig_t[slot] = 0.6
		kit.slot_press(main.party, slot, "accept")


## The first falling coconut being told now (beach-local), or INF.
func _drop_spot() -> Vector3:
	for e in main.events.hits_now():
		if String(e.kind) == "drop" and not (e.data as Array).is_empty():
			return e.data[0]
	return Vector3.INF


func _nearest_loose(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for id in main.items:
		if int(main.items[id]["carrier"]) != -1:
			continue
		var p: Vector3 = (main.items[id]["node"] as Node3D).position
		if from.distance_to(p) < bd:
			bd = from.distance_to(p)
			best = Vector3(p.x, 0.0, p.z)
	return best


func _nearest_sparkle(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for n in main.sparkle_nodes:
		if n.visible and from.distance_to(n.position) < bd:
			bd = from.distance_to(n.position)
			best = n.position
	return best


## Fake giant: aim + trigger at buried treasure, poke the sparkle, grab treasure, chest it.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig)  # the standard fake player (VrRig.fake_eye, x world_scale)
	vr_t += delta
	var beach: Node3D = main.beach
	if String(main.net.state_get("phase", "")) == "orbs":  # touch the right-hand pick orb with a glove
		var o: Vector3 = main.picks.orb_global(2) if main.picks.showing() else Vector3.INF
		if o != Vector3.INF and main.party.player_count() == 0:
			kit.vr_reach(rig, 1, o, 2.0, delta)
			vr_took = vr_took or main.picks.chosen_by == 0
		return
	match vr_phase:
		"aim":
			if main.hidden.is_empty():
				return
			vr_target = main.hidden[0][0]
			var g := beach.to_global(vr_target)
			var hr: Node3D = rig.hand_r
			hr.global_basis = UiKit.aim((g - hr.global_position).normalized(), Vector3.UP)
			kit.vr_trigger(rig, 1.0 if vr_t > 0.2 and vr_t < 0.4 else 0.0)
			if vr_t > 0.6:
				_vr_next("poke")
		"poke":
			kit.vr_reach(rig, 0, beach.to_global(vr_target + Vector3.UP * 0.1), 1.5, delta)
			if vr_t > 1.5:
				kit.vr_reach(rig, 0, beach.to_global(Vector3(-3.0, 4.0, 5.0)), 3.0, delta)
			if vr_t > 2.0:
				_vr_next("grab")
		"grab":
			var held := _vr_held()
			if held >= 0:
				vr_throw = not vr_throw
				_vr_next("throw" if vr_throw else "carry")
				return
			var p := _nearest_loose(Vector3.ZERO)
			if p == Vector3.INF or vr_t > 3.0:
				_vr_next("aim")
				return
			kit.vr_reach(rig, 1, beach.to_global(p + Vector3.UP * 0.4), 1.5, delta)
		"carry":
			# (the glove that holds it: the left one can pick treasure up while poking)
			kit.vr_reach(rig, _held_hand(), beach.to_global(Vector3(0.0, 2.0, 0.0)), 2.5, delta)
			if _vr_held() < 0 or vr_t > 5.0:
				_vr_next("aim")
		"throw":
			if vr_t < 0.5:
				return
			kit.vr_reach(rig, _held_hand(), beach.to_global(Vector3(0.0, 6.0, 0.0)), 5.0, delta)
			if _vr_held() < 0 or vr_t > 1.5:
				_vr_next("aim")


func _vr_next(phase: String) -> void:
	vr_phase = phase
	vr_t = 0.0
	kit.vr_trigger(main.vr_rig, 0.0)


func _held_hand() -> int:
	var id := _vr_held()
	return clampi(int(main.items[id]["carrier"]) - 10, 0, 1) if id >= 0 else 1


func _vr_held() -> int:
	for id in main.items:
		if int(main.items[id]["carrier"]) >= 10:
			return int(id)
	return -1


func _vr_took_any() -> bool:
	for h in main.picks.history:
		if int(h[2]) == 0:
			return true
	return false


func _report() -> String:
	return "BOT %s: players %s, items %d, sparkles %d, score %d, found %d, round %d, stats %s" % [main.net.mode,
		str(main.party.active_slots()), main.items.size(), main.sparkles.size(), int(main.net.state_get("score", 0)),
		int(main.net.state_get("found", 0)), int(main.net.state_get("round", 0)), str(main.stats)]


func _checks() -> void:
	var mode: String = main.net.mode
	# Second pass (deep.gd) on every machine.
	kit.assert_true(orbs_seen.has("mode") or mode == "client", "%s: the mode was picked on the pick orbs (%s)" % [mode, str(orbs_seen.keys())])
	kit.assert_true(orbs_seen.has("gift") or mode == "client", "%s: Peg's tools were offered on the pick orbs" % mode)
	kit.assert_true(String(main.net.state_get("mode", "")) in ["gentle", "brave", "hard"], "%s: a mode reached this machine (%s)" % [mode, str(main.net.state_get("mode", ""))])
	kit.assert_true(main.gift != "" or orbs_seen.has("gift") or main.results_showing(), "%s: a tool was picked (%s)" % [mode, main.gift])
	kit.assert_true(events_max > 0, "%s: warned events were told by rings here (%d)" % [mode, events_max])
	kit.assert_true(main.deco_node != null and is_instance_valid(main.deco_node), "%s: the island wears the %s dress" % [mode, main.season])
	if mode == "client":
		kit.info("client: a local digger sat bonked: %s" % was_down)
	kit.assert_true(main.museum_node != null and is_instance_valid(main.museum_node), "%s: Peg's museum stands" % mode)
	if mode != "client":
		kit.info("events fired %s, stats %s, picks %s" % [str(main.events.fired), str(main.stats), str(main.picks.history)])
		kit.assert_true(not main.events.fired.is_empty(), "host: events happened")
		kit.assert_true(Deep.museum_total(main.save.data.museum) > 0, "host: banked treasure went into the museum (%s)" % str(main.save.data.museum))
		kit.assert_true(String(main.save.data.mode) == main.mode, "host: the mode was saved")
		if int(main.events.fired.get("drop", 0)) > 0 and kit.tv_players() > 0:
			kit.assert_true(int(main.stats.bonks) > 0, "host: the clumsy digger under a coconut was bonked")
		if main.vr_rig != null and want == 0:
			kit.assert_true(vr_took or _vr_took_any(), "solo giant: a glove took a pick orb")
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
	else:
		var host_p := 1 if main.flat_host else 0
		kit.assert_eq(kit.seated(), kit.seated_want(want, host_p), "%s: all %d TV players (+%d on the host) are seated" % [mode, want, host_p])
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	kit.assert_true(int(main.net.state_get("found", 0)) > 0, "%s: treasure was dug up" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	kit.assert_true(saw_results, "%s: the results were shown" % mode)
	kit.assert_true(main.island.has("spots") and not main.x_node == null, "%s: the island came from islandgen.gd (%s)" % [mode, str(kinds_seen.keys())])
	if mode != "client":
		kit.assert_true(saw_pick, "%s: round 2 began with the island pick orbs" % mode)
		kit.assert_true(int(main.save.data.islands) >= 1, "%s: the islands done were saved" % mode)
		kit.info("map pieces banked (most in a round): %d, X shown: %s, relics: %s" % [max_maps, saw_x, str(main.save.data.relics)])
		if kit.tv_players() > 0:  # (a giant alone - solo VR host, the Frame - digs fewer in a short bot round)
			kit.assert_true(max_maps >= 1, "%s: map pieces were dug up and banked" % mode)
	if mode == "client":
		kit.assert_true(max_items_seen > 0, "client: treasure items mirrored from the host")
		kit.assert_true(max_sparkles_seen > 0, "client: sparkles mirrored from the host")
	elif kit.tv_players() > 0:  # solo VR (a host alone): the giant plays alone, like BOT_PLAYERS=0
		kit.assert_true(int(main.stats["tv_digs"]) > 0, "TV players dug up treasure")
	else:
		kit.assert_true(int(main.net.state_get("score", 0)) > 0 or int(main.net.state_get("round", 0)) >= 2, "the giant alone filled the chest")
	if main.vr_rig != null:
		kit.assert_true(int(main.stats["sparkles"]) > 0, "the giant's telescope made sparkles")
		kit.assert_true(int(main.stats["giant_digs"]) > 0, "the giant poked treasure out of the sand")
		kit.assert_true(int(main.stats["giant_banks"]) + int(main.stats["throws"]) > 0, "the giant put / threw treasure in the chest")
