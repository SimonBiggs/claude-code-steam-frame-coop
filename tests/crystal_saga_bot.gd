extends Node
## Headless bot for games/crystal_saga. TV bots (BOT_PLAYERS, default 2) shoot the practice stone,
## then walk towards the nearest monster and press A (shoot), go through each opened barrier, shoot the
## orb if the VR hero hasn't touched it, and shoot the Crystal of Light at the end.
## The fake VR hero (BOT_VR=1) waits while the ghost hand shows the swing, slices the dummy, raises the
## left hand at the glowing target (fireball), walks to monsters with the left stick and swings the
## sword through them (raising the left hand now and then), touches the cave's orb and raises the sword
## (thunder), pokes the touchable things of each place it passes, fights the Stone Giant, then touches
## the Crystal of Light (and again on the results: AGAIN).
## Design check: every zone gets entered, the crystal is restored and the results show; the practice
## and the ghost hand happened; sword, fire and thunder all hit; props reacted; the giant stomped; the
## TV machine mirrors it all; everyone stays on the path.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 30000 res://tests/crystal_saga_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## CS_ZONE=n starts in zone n (0..4).

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const World := preload("res://games/crystal_saga/world.gd")

const POKE_KINDS: Array[int] = [World.WELL, World.CHICKEN, World.FLOWER, World.SIGN, World.CHEST, World.CRYSTAL,
	World.MUSHROOM, World.HOUSE, World.TREE, World.VILLAGER, World.FRIEND]

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var results_t := -1.0
var again_sent := false
var max_mons := 0
var saw_restored := false
var shoot_cd := {}
var vr_t := 0.0
var raise_t := 0.0
var swing_side := 1.0
var poke_list: Array[int] = []
var poked_zone := -1
var outside := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/crystal_saga/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party))
	kit.every(5.0, _report)
	kit.every(0.25, _watch)
	var end := 240.0 if host else (230.0 if client else 300.0)
	if OS.has_environment("BOT_END"):
		end = float(OS.get_environment("BOT_END"))
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _watch() -> String:
	if main.monsters == null:
		return ""
	max_mons = maxi(max_mons, main.monsters.count())
	saw_restored = saw_restored or bool(main.net.state_get("restored", false))
	for h in main.heroes.values():
		var p: Vector3 = h.position
		if absf(p.x) > World.HALF_W + 0.01 or p.z > World.HALF_L or p.z < World.wall_z(World.ZONES - 1) - 0.01:
			outside += 1
	if main.results_showing() and not saw_results:
		saw_results = true
		results_t = kit.t
		kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
	if saw_results and main.results_showing() and kit.t - results_t > 6.0 and main.vr_rig == null and not again_sent:
		var slots: Array[int] = main.party.local_slots()
		if not slots.is_empty() and main.net.mode == "local":
			again_sent = true
			kit.slot_press(main.party, slots[0], "accept")
	return ""


func _process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.world == null:
		return
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


func _phase() -> String:
	return String(main.net.state_get("phase", ""))


func _zone() -> int:
	return int(main.net.state_get("zone", 0))


## Through a barrier: head for its middle first.
func _waypoint(from: Vector3, to: Vector3) -> Vector3:
	var a := World.zone_of(from)
	var b := World.zone_of(to)
	if a == b:
		return to
	var wz := World.wall_z(mini(a, b))
	var side := 1.0 if from.z > wz else -1.0
	if absf(from.x) > 1.0 and absf(from.z - wz) > 0.3:
		return Vector3(0.0, 0.0, wz + side * 1.0)
	return Vector3(0.0, 0.0, wz - side * 1.5)


func _nearest_monster(from: Vector3) -> Vector3:
	var best := INF
	var target := Vector3.INF
	for id in main.monsters.mons:
		var c: Vector3 = main.monsters.center_of(id)
		var d := from.distance_to(Vector3(c.x, 0.0, c.z))
		if World.zone_of(c) == _zone() and d < best:
			best = d
			target = c
	return target


## A TV hero.
func _tv_bot(slot: int, delta: float) -> void:
	if not main.heroes.has(slot):
		return
	var h = main.heroes[slot]
	var pos: Vector3 = h.position
	shoot_cd[slot] = float(shoot_cd.get(slot, 0.0)) - delta
	var target := Vector3.INF
	var w = main.world
	var reach := 2.5 if slot == 0 else 4.0
	match _phase():
		"practice":
			if not w.is_used(w.stone_id):
				target = w.prop_center(w.stone_id)
		"fight", "boss":
			target = _nearest_monster(pos)
			if _phase() == "boss":
				reach = 3.0 if slot == 0 else 5.5
		"orb":
			if not w.is_used(w.orb_id) and main.vr_rig == null:
				target = w.prop_center(w.orb_id)
		"cleared":
			if int(main.net.state_get("open", 0)) > _zone() and (main.vr_rig == null or (poked_zone == _zone() and poke_list.is_empty())):
				target = World.center(_zone() + 1) + Vector3(-2.0 + slot * 0.6, 0.0, 4.0)
				reach = 0.3
		"crystal":
			if main.vr_rig == null:
				target = w.prop_center(w.big_id)
	if target == Vector3.INF:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	var wp := _waypoint(pos, target)
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if wp == target and to.length() < reach:
		# Close enough: face it (a light push) and shoot.
		kit.slot_stick(main.party, slot, "left", Vector2(to.x, to.z).normalized() * 0.2 if to.length() > 1.0 else Vector2.ZERO)
		if reach > 0.5 and float(shoot_cd[slot]) <= 0.0:
			shoot_cd[slot] = 0.5
			kit.slot_press(main.party, slot, "accept")
		return
	kit.slot_stick(main.party, slot, "left", Vector2(to.x, to.z).normalized())


## Push the VR left stick towards a WORLD direction (relative to where the head looks).
func _walk(rig: Node, dir: Vector3) -> void:
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	kit.vr_stick(rig, Vector2(d.dot(r), d.dot(f)))


## The fake VR hero.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	var w = main.world
	rig.camera.position.y = 1.5
	vr_t += delta
	raise_t += delta
	var head: Vector3 = rig.head_position()
	var feet := Vector3(head.x, 0.0, head.z)
	var phase := _phase()
	var zone := _zone()
	kit.vr_stick(rig, Vector2.ZERO)
	var fwd: Vector3 = rig.head_forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var rest_r: Vector3 = head + right * 0.25 + Vector3(0.0, -0.5, 0.0) + fwd * 0.25
	var rest_l: Vector3 = head - right * 0.25 + Vector3(0.0, -0.5, 0.0) + fwd * 0.25
	var up_l: Vector3 = head - right * 0.2 + Vector3(0.0, 0.25, 0.0) + fwd * 0.2
	var up_r: Vector3 = head + right * 0.2 + Vector3(0.0, 0.25, 0.0) + fwd * 0.2
	match phase:
		"practice":
			if vr_t > 3.5 and not w.is_used(w.dummy_id):
				_swing(rig, w.prop_center(w.dummy_id), delta)
			elif w.is_used(w.dummy_id) and not w.is_used(w.target_id):
				kit.vr_reach(rig, VrRig.RIGHT, rest_r, 3.0, delta)
				kit.vr_look_at(rig, w.prop_center(w.target_id))
				_raise(rig, VrRig.LEFT, up_l, rest_l, delta)
			else:
				kit.vr_reach(rig, VrRig.RIGHT, rest_r, 2.0, delta)
		"fight", "boss":
			var target := _nearest_monster(feet)
			if target != Vector3.INF:
				kit.vr_look_at(rig, Vector3(target.x, head.y, target.z))
				var gap := 2.0 if phase == "boss" else 0.75
				var to := Vector3(target.x - feet.x, 0.0, target.z - feet.z)
				if to.length() > gap + 0.3:
					_walk(rig, to)
				_swing(rig, target, delta)
				_raise(rig, VrRig.LEFT, up_l, rest_l, delta)
				if bool(main.net.state_get("thunder", false)) and fmod(kit.t, 5.0) < 0.6:
					kit.vr_reach(rig, VrRig.RIGHT, up_r, 8.0, delta)
		"orb":
			if not w.is_used(w.orb_id):
				var oc: Vector3 = w.prop_center(w.orb_id)
				var to2 := Vector3(oc.x - feet.x, 0.0, oc.z + 0.8 - feet.z)
				if to2.length() > 0.3:
					_walk(rig, to2)
				kit.vr_reach(rig, VrRig.LEFT, oc, 3.0, delta)
			else:
				kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)
				_raise(rig, VrRig.RIGHT, up_r, rest_r, delta)
		"cleared":
			if poked_zone != zone:
				poked_zone = zone
				poke_list.clear()
				for id in w.props.size():
					if int(w.props[id]["zone"]) == zone and int(w.props[id]["kind"]) in POKE_KINDS and (w.props[id]["node"] as Node3D).visible:
						poke_list.append(id)
				vr_t = 0.0
			kit.vr_reach(rig, VrRig.RIGHT, rest_r, 3.0, delta)
			if not poke_list.is_empty() and kit.t < 1e9:
				var pid: int = poke_list[0]
				var pc: Vector3 = w.prop_center(pid)
				var stand := Vector3(clampf(pc.x, -World.HALF_W + 0.6, World.HALF_W - 0.6), 0.0, pc.z + 0.6)
				var to3 := Vector3(stand.x - feet.x, 0.0, stand.z - feet.z)
				if to3.length() > 0.3:
					_walk(rig, to3)
				if kit.vr_reach(rig, VrRig.LEFT, pc, 6.0, delta) or vr_t > 6.0:
					poke_list.pop_front()
					vr_t = 0.0
					kit.vr_reach(rig, VrRig.LEFT, rest_l, 1000.0, 1.0)
			elif int(main.net.state_get("open", 0)) > zone:
				kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)
				var goal := World.center(zone + 1) + Vector3(0.6, 0.0, 4.0)
				var wp := _waypoint(feet, goal)
				var to4 := Vector3(wp.x - feet.x, 0.0, wp.z - feet.z)
				if to4.length() > 0.2:
					_walk(rig, to4)
		"crystal", "results", "restore", "yay":
			var bc: Vector3 = w.prop_center(w.big_id)
			var stand2 := bc + Vector3(0.4, 0.0, 1.5)
			stand2.y = 0.0
			var to5 := Vector3(stand2.x - feet.x, 0.0, stand2.z - feet.z)
			if to5.length() > 0.3:
				_walk(rig, to5)
			elif phase == "crystal" or (phase == "results" and saw_results and kit.t - results_t > 6.0 and not again_sent):
				if kit.vr_reach(rig, VrRig.LEFT, bc, 3.0, delta) and phase == "results":
					again_sent = true
			else:
				kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)


## Raise a hand above the head, then lower it again (a 2 s cycle).
func _raise(rig: Node, which: int, up: Vector3, rest: Vector3, delta: float) -> void:
	var t := fmod(raise_t, 2.0)
	kit.vr_reach(rig, which, up if t < 0.8 else rest, 6.0, delta)


## Sweep the right hand side to side so the blade (pointing -Z) passes through the target.
func _swing(rig: Node, target: Vector3, delta: float) -> void:
	var p := target + Vector3(swing_side * 0.45, 0.0, 0.6)
	if kit.vr_reach(rig, VrRig.RIGHT, p, 5.0, delta):
		swing_side = -swing_side


func _report() -> String:
	if main.world == null:
		return "waiting"
	var vr := ""
	if main.hands != null:
		vr = " swings %d fires %d thunders %d knocks %d" % [main.hands.swings, main.hands.fires, main.hands.thunders, main.log_knocks]
	return "BOT %s: zone %d phase %s open %d monsters %d heroes %d hits %s pokes %s dizzy %d stomps %d%s" % [
		main.net.mode, _zone(), _phase(), int(main.net.state_get("open", 0)), main.monsters.count(),
		main.heroes.size(), str(main.log_hits), str(main.log_pokes), main.log_dizzy, main.log_stomps, vr]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_eq(outside, 0, "%s: heroes stayed on the path" % mode)
	if mode != "host":
		kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	if mode == "client":
		kit.assert_true(max_mons >= 2, "client mirrors the monsters (%d)" % max_mons)
		kit.assert_true(int(main.net.state_get("open", 0)) >= 2 or saw_results, "client saw barriers open")
		return
	var first := int(OS.get_environment("CS_ZONE")) if OS.has_environment("CS_ZONE") else 0
	for z in range(first, World.ZONES):
		kit.assert_true(main.log_zones.has(z), "%s: zone %d was entered" % [mode, z])
	kit.assert_true(saw_restored, "%s: the Crystal of Light was restored" % mode)
	kit.assert_true(saw_results, "%s: the results showed" % mode)
	kit.assert_true(main.log_stomps > 0 or first > 3, "%s: the Stone Giant stomped (%d)" % [mode, main.log_stomps])
	if main.vr_rig != null:
		if first == 0:
			kit.assert_true(main.ghost.shown.has("swing") and main.ghost.shown.has("fire"), "the ghost hand showed swing and fire (%s)" % str(main.ghost.shown))
		kit.assert_true(main.hands.swings > 0, "the hero's sword hit monsters (%d)" % main.hands.swings)
		kit.assert_true(main.hands.fires > 0, "the hero cast fireballs (%d)" % main.hands.fires)
		if first <= 2:
			kit.assert_true(main.hands.thunders > 0, "the hero cast thunder (%d)" % main.hands.thunders)
		kit.assert_true(main.log_pokes.size() >= 6, "props reacted (%s)" % str(main.log_pokes))
	if mode == "local":
		var tv := 0
		for s in main.log_hits:
			if int(s) > 0 or main.vr_rig == null:
				tv += int(main.log_hits[s])
		kit.assert_true(tv > 0, "the TV party hit monsters (%d)" % tv)
