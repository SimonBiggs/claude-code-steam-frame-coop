extends Node
## Headless bot for games/starship_crew. TV bots (BOT_PLAYERS, default 2) move their crosshair with
## the stick towards the nearest rock / alien and zap with A. The fake VR pilot (BOT_VR=1) waits a
## moment (the ghost glove shows the move), takes the flight stick with the right hand and steers
## through the rings, and now and then lets go to press the toys with the left hand.
## Design check: all four missions get done and the ship docks (results); both practice targets get
## done; the pilot flew through rings; the gunners zapped things; the TV machine mirrors it all.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 12000 res://tests/starship_crew_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## SC_MISSION=n starts at mission n (0..3).

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
				kit.join_bot(main.party))
	kit.every(4.0, _report)
	kit.every(0.5, _results)
	var end := 125.0 if host else (115.0 if client else 160.0)
	if OS.has_environment("BOT_END"):
		end = float(OS.get_environment("BOT_END"))
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _results() -> String:
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
	for id in main.space.zappables():
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
	rig.camera.position = Vector3(0.0, 1.2, 0.0)
	vr_t += delta
	match vr_step:
		"wait":  # let the ghost glove show the move first
			kit.vr_reach(rig, VrRig.RIGHT, Vector3(0.5, 0.6, 0.25), 1.0, delta)
			if vr_t > 3.5:
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
			if rid >= 0:
				var rp: Vector3 = sp.objs[rid]["p"]
				aim = ((Vector2(rp.x, rp.y) - sp.off) / 1.5).limit_length(1.0)
			kit.vr_reach(rig, VrRig.RIGHT, grab_at + Vector3(aim.x, aim.y, 0.0) * 0.1, 0.6, delta)
			if main.results_showing() or (vr_t > 25.0 and String(main.net.state_get("phase", "")) != "play"):
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
	return "BOT %s: mission %d phase %s stars %d off (%.1f,%.1f) objs %d rings %d pops %s lasers %d" % [
		main.net.mode, int(main.net.state_get("mission", 0)), String(main.net.state_get("phase", "")),
		int(main.net.state_get("stars", 0)), main.space.off.x, main.space.off.y, main.space.objs.size(),
		main.log_rings, str(main.log_pops), main.lasers_seen]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
		kit.assert_true(main.lasers_seen > 0, "%s: lasers were drawn (%d)" % [mode, main.lasers_seen])
	kit.assert_true(seen_missions.size() >= 3, "%s: played through several missions (%d)" % [mode, seen_missions.size()])
	if mode == "client":
		kit.assert_true(max_objs >= 3, "client mirrors the space objects (%d)" % max_objs)
		return
	kit.assert_true(saw_results, "%s: the ship docked and the results showed" % mode)
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
		kit.assert_true(main.ghost.shown, "the ghost glove showed the stick move")
		kit.assert_true(main.log_toys.size() >= 3, "the pilot pressed toys (%s)" % str(main.log_toys.keys()))
