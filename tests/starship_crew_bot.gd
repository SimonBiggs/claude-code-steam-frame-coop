extends Node
## Headless bot for games/starship_crew. TV bots (BOT_PLAYERS, default 2) move their crosshair with
## the stick towards the nearest rock / alien and zap with A. The fake VR pilot (BOT_VR=1) waits a
## moment (the ghost glove shows the move), takes the flight stick with the right hand and steers
## through the rings, and now and then lets go to press the toys with the left hand.
## Design check: all four missions get done and the ship docks (results); both practice targets get
## done; the pilot flew through rings; the gunners zapped things; the TV machine mirrors it all.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 12000 res://tests/starship_crew_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## SC_MISSION=n starts at mission n (0..3). SC_TRIPS=n flies trip n (default 0: the lessons, then AGAIN
## flies trip 1, a seeded one); the family's save isn't touched by the trip count then.
## Story checks: Captain Whiskers' cards show, one RUN line per mission, the station grows a part on the
## way home and the TV machine's cockpit model follows.
## Second pass (default SC_TRIPS=1 and SC_SURPRISES_NOW=1: a seeded trip with picks and early surprises): the mode
## pick and the module picks happen on the pick orbs (TV gunners zap one a moment after they open; the fake pilot
## steers onto one and holds it), warned rock streams / solar flares are told on every machine and the pilot (bot or
## robot autopilot) slides out of them, the star sector and the crew friends show on every machine.

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Deep := preload("res://games/starship_crew/deep.gd")

var kit: BotKit
var main: Node
var want := 2
var seen_missions := {}
var saw_results := false
var again_t := -1.0
var zap_cd := {}
var max_objs := 0
var vr_step := "wait"
var vr_t := 0.0
var toy_i := 0
var grab_at := Vector3.ZERO
var again_done := 0
var orbs_t := 0.0  ## seconds the pick orbs have been up here
var orb_want := -1  ## the orb this machine's bots go for
var saw_orbs := 0
var saw_tells := {}
var dodges := 0  ## the fake pilot slid out of a surprise
var short := false  ## the run ends before the whole trip (solo VR host BOT_END=62, a 60 s local run): check progress


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_environment("SC_TRIPS"):
		OS.set_environment("SC_TRIPS", "1")
	if not OS.has_environment("SC_SURPRISES_NOW") and OS.get_environment("SC_TRIPS") != "0":
		OS.set_environment("SC_SURPRISES_NOW", "1")
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/starship_crew/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party)
		elif not main.net.has_vr:
			kit.join_bot(main.party))  # a flat host (TV / Deck hosting): one pad hero here, in slot 0
	kit.every(4.0, _report)
	kit.every(0.5, _results)
	var full := 150.0 if host else (130.0 if client else 185.0)  # (a client ends well before its host: a late joiner too)  # (+ the pick orbs: the mode once, a module each mission)  # the whole trip: four missions, then docking
	var end: float = preload("res://tests/bot_end.gd").end_at(full)  # (BOT_END, --quit-after, the runner's deadline)
	short = end < full - 1.0
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _results() -> String:
	if main == null or not is_instance_valid(main) or main.space == null:
		return ""
	seen_missions[int(main.net.state_get("mission", 0))] = true
	max_objs = maxi(max_objs, main.space.objs.size())
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or main.cockpit.again_on, "the AGAIN button shows in VR")
			again_t = kit.t
		if kit.t - again_t > 4.0 and main.vr_rig == null:
			var slots: Array[int] = main.party.local_slots()
			if not slots.is_empty():
				kit.slot_press(main.party, slots[0], "accept")
	return ""


func _process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.space == null:
		return
	if main.picks != null and main.picks.showing():
		if orbs_t == 0.0:
			saw_orbs += 1
			orb_want = (saw_orbs + 1) % main.picks.orbs.orbs.size()
		orbs_t += delta
	else:
		orbs_t = 0.0
	for t in main.hazards.tells_now():
		saw_tells[str(t)] = true
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


## A TV gunner: push the crosshair at the nearest rock / alien and zap when it's on it.
func _tv_bot(slot: int, delta: float) -> void:
	if not main.cross.has(slot):
		return
	zap_cd[slot] = float(zap_cd.get(slot, 0.0)) - delta
	var best := Vector2(9, 9)
	var c: Vector2 = main.cross[slot]
	if main.picks.showing():  # the pick orbs: aim at one a moment after they open (the pilot gets a go first)
		var w: Vector3 = main.picks.orb_position(orb_want)
		if orbs_t > 2.5 and w != Vector3.INF and slot == main.party.local_slots()[0]:
			best = main.project(w)
		else:
			kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
			return
	for id in ([] if main.picks.showing() else main.space.zappables()):
		var uv: Vector2 = main.project(main.space.world_pos(id))
		if absf(uv.x) < 0.9 and absf(uv.y) < 0.85 and uv.distance_to(c) < best.distance_to(c):
			best = uv
	if best.x > 5.0:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	var d := best - c
	var mv := (d / 0.15).limit_length(1.0)
	kit.slot_stick(main.party, slot, "left", Vector2(mv.x, -mv.y))  # pad y DOWN
	if d.length() < 0.07 and float(zap_cd[slot]) <= 0.0:
		zap_cd[slot] = 0.35
		kit.slot_press(main.party, slot, "accept")


## Fake VR pilot.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	var ck = main.cockpit
	kit.vr_head_home(rig)  # the standard fake player (VrRig.fake_pose)
	vr_t += delta
	match vr_step:
		"wait":  # let the ghost glove show the move first
			kit.vr_reach(rig, VrRig.RIGHT, Vector3(0.5, 0.6, 0.25), 1.0, delta)
			# (the ghost glove shows on the first mission's practice ring; a lone pilot steers onto the picks before that)
			var alone: bool = main._crew_slots().is_empty() and main.picks.showing()
			if String(main.net.state_get("phase", "")) != "play" and not alone and vr_t > 1.0:
				vr_t = 0.0
			if vr_t > 3.5 or (alone and vr_t > 1.5):
				vr_step = "reach"
				vr_t = 0.0
		"reach":
			if kit.vr_reach(rig, VrRig.RIGHT, ck.handle_point(), 1.0, delta) or vr_t > 2.0:
				kit.vr_trigger(rig, 1.0)
				grab_at = rig.hand_point(VrRig.RIGHT)
				vr_step = "fly"
				vr_t = 0.0
		"fly":
			var sp = main.space
			var rid: int = main.prac_ring if sp.objs.has(main.prac_ring) else sp.next_ring()
			var aim := Vector2.ZERO
			var tells: Array = main.hazards.tells_now()
			if main.picks.showing() and main.picks.spots.size() > orb_want and orb_want >= 0:  # steer onto an orb and hold
				aim = ((main.picks.spots[orb_want] - sp.off) / 1.2).limit_length(1.0)
			elif not tells.is_empty():  # a surprise is told: slide out of it
				var safe := Deep.escape(tells[0], sp.off)
				if safe != Vector2.INF and safe != sp.off:
					aim = ((safe - sp.off) / 0.8).limit_length(1.0)
					dodges += 1
			elif rid >= 0:
				var rp: Vector3 = sp.objs[rid]["p"]
				aim = ((Vector2(rp.x, rp.y) - sp.off) / 1.5).limit_length(1.0)
			kit.vr_reach(rig, VrRig.RIGHT, grab_at + Vector3(aim.x, aim.y, 0.0) * 0.1, 0.6, delta)
			if main.results_showing() or (vr_t > 25.0 and not String(main.net.state_get("phase", "")) in ["play", "pick"]):
				kit.vr_trigger(rig, 0.0)
				kit.vr_reach(rig, VrRig.RIGHT, Vector3(0.3, 0.75, -0.05), 1000.0, 1.0)
				vr_step = "toys"
				vr_t = 0.0
		"toys":
			var spots: Array[Vector3] = []
			for k in ["honk", "disco", "bubbles"]:
				spots.append((ck.toys[k] as Node3D).global_position + Vector3(0, 0.04, 0))
			spots.append(ck.bobble.global_position + Vector3(0, 0.08, 0))
			if ck.again_on and kit.t - again_t > 4.0:
				spots = [ck.again_btn.global_position + Vector3(0, 0.05, 0)]
			var spot: Vector3 = spots[toy_i % spots.size()]
			if kit.vr_reach(rig, VrRig.LEFT, spot, 1.0, delta) or vr_t > 2.0:
				toy_i += 1
				vr_t = 0.0
				kit.vr_reach(rig, VrRig.LEFT, Vector3(-0.3, 0.75, -0.05), 1000.0, 1.0)
				if toy_i % 5 == 0 and not main.results_showing():
					vr_step = "reach"


func _report() -> String:
	if main == null or not is_instance_valid(main) or main.space == null:
		return ""
	return "BOT %s: mission %d phase %s stars %d off (%.1f,%.1f) objs %d rings %d pops %s lasers %d mode %s gift %s orbs %d tells %d hits %d" % [
		main.net.mode, int(main.net.state_get("mission", 0)), String(main.net.state_get("phase", "")),
		int(main.net.state_get("stars", 0)), main.space.off.x, main.space.off.y, main.space.objs.size(),
		main.log_rings, str(main.log_pops), main.lasers_seen, main.mode, main.gift, saw_orbs, saw_tells.size(), main.zone_hits]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(kit.seated(), kit.seated_want(want), "%s: all %d TV players are seated" % [mode, want])
		kit.assert_true(main.lasers_seen > 0, "%s: lasers were drawn (%d)" % [mode, main.lasers_seen])
	kit.assert_true(seen_missions.size() >= (2 if short and kit.t < 50.0 else 3), "%s: played through several missions (%d%s)" % [mode, seen_missions.size(), ", short run" if short else ""])
	kit.assert_true(main.stories_shown >= 3, "%s: Captain Whiskers' story cards showed (%d)" % [mode, main.stories_shown])
	kit.assert_true(main.cockpit.model_parts == int(main.net.state_get("parts", -1)), "%s: the dashboard station model has every part (%d)" % [mode, main.cockpit.model_parts])
	var seeded: bool = OS.get_environment("SC_TRIPS") != "0"
	kit.assert_true(main.season_node.season != "" and main.season_node.islands.size() > 0, "%s: the star sector is dressed (%s)" % [mode, main.season_node.season])
	kit.assert_true(main.crew_node.count >= 0, "%s: the crew friends are built (%d)" % [mode, main.crew_node.count])
	if seeded:
		kit.assert_true(saw_orbs >= (1 if short else 2), "%s: the pick orbs showed (%d times)" % [mode, saw_orbs])
		kit.assert_true(saw_tells.size() >= 1, "%s: a warned surprise was told here (%d)" % [mode, saw_tells.size()])
	if mode == "client":
		kit.assert_true(max_objs >= 3, "client mirrors the space objects (%d)" % max_objs)
		if seeded:
			kit.assert_true(main.season_node.season == String((main.net.state_get("deep", ["", "", ""]) as Array)[2]), "client: the same star sector as the host")
		return
	if seeded:
		kit.assert_true(main.mode_picked, "%s: the mode was picked (%s)" % [mode, main.mode])
		kit.assert_true(main.picks.history.size() >= (1 if short else 3), "%s: picks were taken (%s)" % [mode, str(main.picks.history)])
		var chosen_by_someone: int = main.picks.history.filter(func(h: Array) -> bool: return int(h[2]) >= 0).size()
		kit.assert_true(chosen_by_someone >= 1, "%s: a player really chose a pick (%s)" % [mode, str(main.picks.history)])
		if main.vr_rig != null and kit.tv_players() == 0:
			kit.assert_true(main.picks.history.filter(func(h: Array) -> bool: return int(h[2]) == 0).size() >= 1, "solo VR: the pilot steered onto a pick (%s)" % str(main.picks.history))
		kit.assert_true(main.zone_hits <= main.surprises_seen, "%s: surprises hit the ship at most once each (%d hits, %d told)" % [mode, main.zone_hits, main.surprises_seen])
		if main.surprises_seen >= 3:
			kit.assert_true(main.zone_hits < main.surprises_seen, "%s: the pilot dodged some surprises (%d hits of %d)" % [mode, main.zone_hits, main.surprises_seen])
	if short:  # cut short before docking: a RUN line for every mission finished so far
		kit.assert_true(main.runs_logged >= 1 and main.runs_logged >= seen_missions.size() - 1, "%s: a RUN line for every finished mission (%d, missions seen %d, short run)" % [mode, main.runs_logged, seen_missions.size()])
	else:
		kit.assert_true(saw_results, "%s: the ship docked and the results showed" % mode)
		kit.assert_true(main.runs_logged >= 4, "%s: a RUN line for every mission (%d)" % [mode, main.runs_logged])
		kit.assert_true(int(main.net.state_get("parts", 0)) >= 1 + int(OS.get_environment("SC_TRIPS")), "%s: the station grew a part on the way home" % mode)
	if not OS.has_environment("SC_MISSION"):
		kit.assert_eq(int(main.net.state_get("practice", 0)), 3, "both practice targets got done")
	var tv_pops := 0
	for s in main.log_pops:
		if int(s) >= 0:
			tv_pops += int(main.log_pops[s])
	if mode == "local":
		kit.assert_true(tv_pops > 0, "the TV gunners zapped things (%d)" % tv_pops)
	kit.assert_true(main.log_rings > 0, "the ship flew through rings (%d)" % main.log_rings)
	if main.vr_rig != null:
		var steered_pick: bool = main.picks.history.any(func(h: Array) -> bool: return int(h[2]) == 0)
		kit.assert_true(main.ghost.shown or steered_pick, "the ghost glove showed the stick move (or the pilot already steered onto a pick: %s)" % str(main.picks.history))
		kit.assert_true(main.log_toys.size() >= 3, "the pilot pressed toys (%s)" % str(main.log_toys.keys()))
