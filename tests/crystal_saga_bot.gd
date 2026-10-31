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
## CS_ZONE=n starts in zone n (0..4); CS_JOURNEYS=n plays a later (harder) journey. Each run starts from a fresh
## test save (BOT_KEEP_SAVE=1 keeps it: skills, shards and Willowbrook's places carry on).
## Saga checks: the road came from the plan (sagagen.gd) and the TV machine built the same one; the party levelled up
## at the glowing stones (TV bots shoot one, the VR bot touches one); shards were found; Lumi's story cards showed
## on every machine; one RUN telemetry line per journey.
## saga-deep checks: TV bots bonk a hero statue first (each seat becomes a hero), shoot a MAP stone when the stones
## are up (CS_JOURNEYS=3 BOT_NO_DAILY=1: several regions open; the VR bot touches the second stone, so the world
## is rebuilt for another region on every machine), find the region's quest things (shoot / touch them), and fight
## the crystal guardian; with CS_TRY=guardian (or a deep CS_REGION) the guardian's tells (rain / roll / call) show.

const BotKit := preload("res://tests/bot_kit.gd")
const BotEnd := preload("res://tests/bot_end.gd")
const VrRig := preload("res://core/vr_rig.gd")
const World := preload("res://games/crystal_saga/world.gd")
const Save := preload("res://core/save.gd")

const POKE_KINDS: Array[int] = [World.WELL, World.CHICKEN, World.FLOWER, World.SIGN, World.CHEST, World.CRYSTAL,
	World.MUSHROOM, World.HOUSE, World.TREE, World.VILLAGER, World.FRIEND, World.QUEST, World.GIVER]

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
var saw_choose := 0
var saw_offer_client := false
var plan_ok := true
var first_road := 0  ## the first journey's road (a hash), once the party is in the forest
var statue_done := {}  ## slot -> true once it bonked its hero statue
var saw_map := 0
var saw_map_client := false
var saw_tells := {}  ## tell kinds seen drawn on this machine
var quest_max := 0
var region_changes := 0
var last_biome := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	if not OS.has_environment("BOT_KEEP_SAVE") and not OS.has_environment("DUO_JOIN"):
		Save.erase("crystal_saga")
	main = load("res://games/crystal_saga/main.tscn").instantiate()
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
	kit.every(5.0, _report)
	kit.every(0.25, _watch)
	var end := 150.0 if host else (140.0 if client else 300.0)
	if OS.has_environment("BOT_END"):
		end = float(OS.get_environment("BOT_END"))
	end = BotEnd.within_deadline(end)
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _watch() -> String:
	if main.monsters == null:
		return ""
	max_mons = maxi(max_mons, main.monsters.count())
	saw_restored = saw_restored or bool(main.net.state_get("restored", false))
	if _phase() == "choose":
		saw_choose += 1
		if main.world.offer.size() >= 2 and main.world.choice_ids.size() == 3 and (main.world.props[main.world.choice_ids[0]]["node"] as Node3D).visible:
			saw_offer_client = true
	if _phase() == "map":
		saw_map += 1
		if main.world.offer_kind == "region" and (main.world.props[main.world.choice_ids[0]]["node"] as Node3D).visible:
			saw_map_client = true
	for t in main.monsters._tell_nodes:
		saw_tells[String(t[3])] = true
	quest_max = maxi(quest_max, int(main.net.state_get("quest", 0)))
	var bio := int(main.plan.get("biome", -1))
	if last_biome >= 0 and bio != last_biome:
		region_changes += 1
	last_biome = bio
	if first_road == 0 and _zone() >= 1:
		first_road = var_to_str(main.world.plan.get("props", [])).hash()
	var pl: Array = main.net.state_get("plan", [])
	if not pl.is_empty() and int(main.world.plan.get("seed", -1)) != int(pl[0]) and _phase() != "results":
		plan_ok = false
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
			if slot > 0 and not statue_done.has(slot) and w.statue_ids.size() == 5:
				# Become a hero first: bonk a statue (seat 1 a healer when unlocked, else mage / archer / knight ...).
				var sid: int = w.statue_ids[(slot + 1) % 3 if slot < 4 else slot % 5]
				if not (w.props[sid]["hero"] as Node3D).visible:
					sid = w.statue_ids[slot % 3]
				target = w.prop_center(sid)
				reach = 1.15
				if main.heroes[slot].cls == String(w.props[sid]["class"]) or kit.t > 45.0:
					statue_done[slot] = true
			elif not w.is_used(w.stone_id):
				target = w.prop_center(w.stone_id)
		"map":
			if main.vr_rig == null and w.offer.size() >= 2 and w.offer_kind == "region":
				target = w.prop_center(w.choice_ids[slot % w.offer.size()])
				reach = 3.5
		"fight", "boss":
			target = _nearest_monster(pos)
			if _phase() == "boss":
				reach = 3.0 if slot == 0 else 5.5
		"orb":
			if not w.is_used(w.orb_id) and main.vr_rig == null:
				target = w.prop_center(w.orb_id)
		"cleared":
			var qt := _quest_target(pos)
			if qt != Vector3.INF and _zone() in [1, 2]:
				target = qt
			elif int(main.net.state_get("open", 0)) > _zone() and (main.vr_rig == null or (poked_zone == _zone() and poke_list.is_empty())):
				target = World.center(_zone() + 1) + Vector3(-2.0 + slot * 0.6, 0.0, 4.0)
				reach = 0.3
		"crystal":
			if main.vr_rig == null:
				target = w.prop_center(w.big_id)
		"choose":
			if main.vr_rig == null and w.offer.size() >= 2:
				target = w.prop_center(w.choice_ids[slot % w.offer.size()])
				reach = 3.0
	if target == Vector3.INF:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	var wp := _waypoint(pos, target)
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if wp == target and to.length() < reach:
		# Close enough: face it and shoot. The push must turn the hero: past core/party.gd's 0.2 deadzone AND hero.gd's
		# 0.2 turn threshold after it (0.5 -> 0.375); the old 0.2 push did nothing, so a hero shot whichever way it
		# arrived (the TV heroes shot past the cave orb for 100 s, 2026-10-29).
		kit.slot_stick(main.party, slot, "left", Vector2(to.x, to.z).normalized() * 0.5 if to.length() > 0.3 else Vector2.ZERO)
		if reach > 0.5 and float(shoot_cd[slot]) <= 0.0:
			shoot_cd[slot] = 0.5
			kit.slot_press(main.party, slot, "accept")
		return
	var steer := _around_rocks(pos, to)
	kit.slot_stick(main.party, slot, "left", Vector2(steer.x, steer.z).normalized())


## The nearest quest thing still to find in this zone (INF: none, or the quest is done).
func _quest_target(from: Vector3) -> Vector3:
	var w = main.world
	if int(main.net.state_get("quest", 0)) >= int((main.plan.get("quest", {}) as Dictionary).get("need", 3)):
		return Vector3.INF
	var best := Vector3.INF
	for qid in w.quest_ids:
		if w.is_used(qid) or int(w.props[qid]["zone"]) != _zone():
			continue
		var c: Vector3 = w.prop_center(qid)
		if best == Vector3.INF or from.distance_to(c) < from.distance_to(best):
			best = c
	return best


## Walk round the rocks in the way: slide sideways past any blocker just ahead.
func _around_rocks(pos: Vector3, to: Vector3) -> Vector3:
	var dir := Vector3(to.x, 0.0, to.z).normalized()
	for b in main.world.blockers:
		var c: Vector2 = b[0]
		var r: float = b[1]
		var rel := Vector3(c.x - pos.x, 0.0, c.y - pos.z)
		var ahead := rel.dot(dir)
		if ahead <= 0.0 or ahead > r + 1.4 or ahead > to.length():
			continue
		var side := rel - dir * ahead
		if side.length() < r + 0.45:
			var away := -side.normalized() if side.length() > 0.01 else Vector3(-dir.z, 0.0, dir.x)
			return (dir * 0.4 + away).normalized()
	return dir


## Push the VR left stick towards a WORLD direction (relative to where the head looks).
func _walk(rig: Node, dir: Vector3) -> void:
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	var head: Vector3 = rig.head_position()
	var d := _around_rocks(Vector3(head.x, 0.0, head.z), Vector3(dir.x, 0.0, dir.z))
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
		"choose", "map":
			if w.offer.size() >= 2:
				var sc: Vector3 = w.prop_center(w.choice_ids[1 if phase == "map" else 0])
				var to6 := Vector3(sc.x - feet.x, 0.0, sc.z + 0.7 - feet.z)
				if to6.length() > 0.3:
					_walk(rig, to6)
				kit.vr_reach(rig, VrRig.LEFT, sc, 3.0, delta)
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
	return "BOT %s: zone %d phase %s open %d monsters %d heroes %d hits %s pokes %s dizzy %d stomps %d shards %d skills %s quest %d region %s tells %s classes %s%s" % [
		main.net.mode, _zone(), _phase(), int(main.net.state_get("open", 0)), main.monsters.count(),
		main.heroes.size(), str(main.log_hits), str(main.log_pokes), main.log_dizzy, main.log_stomps,
		int(main.net.state_get("shards", 0)), str(main.net.state_get("skills", {})), int(main.net.state_get("quest", 0)),
		main.plan.get("names", ["", "?"])[1], str(main.log_tells if main.net.mode != "client" else saw_tells), str(main.log_classes), vr]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_eq(outside, 0, "%s: heroes stayed on the path" % mode)
	if mode != "host":
		kit.assert_eq(kit.seated(), kit.seated_want(want), "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(plan_ok, "%s: the world was built from the journey's plan" % mode)
	if mode != "local":
		print("BOT AGREE road=%d" % first_road)  # every machine built the same (first) road
		print("BOT AGREE biome=%d" % int(main.plan.get("biome", -1)))  # ... and ended in the same region
	kit.assert_true(main.stories_shown > 0, "%s: Lumi's story cards showed (%d)" % [mode, main.stories_shown])
	if mode == "client":
		kit.assert_true(saw_choose == 0 or saw_offer_client, "client showed the level-up stones")
		kit.assert_true(max_mons >= 2, "client mirrors the monsters (%d)" % max_mons)
		kit.assert_true(int(main.net.state_get("open", 0)) >= 2 or saw_results, "client saw barriers open")
		kit.assert_true(saw_map == 0 or saw_map_client, "client showed the map stones")
		if main.log_regions.is_empty() and OS.has_environment("CS_TRY"):
			kit.assert_true(not saw_tells.is_empty(), "client drew the guardian's tells (%s)" % str(saw_tells))
		return
	var first := int(OS.get_environment("CS_ZONE")) if OS.has_environment("CS_ZONE") else 0
	for z in range(first, World.ZONES):
		kit.assert_true(main.log_zones.has(z), "%s: zone %d was entered" % [mode, z])
	kit.assert_true(saw_restored, "%s: the Crystal of Light was restored" % mode)
	if first <= 1:
		kit.assert_true(saw_choose > 0 and not (main.save.data.skills as Dictionary).is_empty(), "%s: the party levelled up (%s)" % [mode, str(main.save.data.skills)])
	kit.assert_true(int(main.save.data.shards) > 0, "%s: crystal shards were found (%d)" % [mode, int(main.save.data.shards)])
	kit.assert_true(main.runs_logged > 0, "%s: a RUN telemetry line was written" % mode)
	kit.assert_true(saw_results, "%s: the results showed" % mode)
	var atk: Array = (main.plan.get("guardian", {}) as Dictionary).get("attacks", [])
	kit.assert_true(main.log_stomps > 0 or first > 3 or not atk.has("stomp") or not main.log_tells.is_empty(), "%s: the guardian stomped (%d) %s" % [mode, main.log_stomps, str(main.log_tells)])
	if OS.has_environment("CS_TRY") or OS.has_environment("CS_REGION"):
		var fancy := 0
		for k in main.log_tells:
			fancy += 1 if String(k) != "stomp" else 0
		kit.assert_true(fancy > 0 or atk == ["stomp"], "%s: the crystal guardian showed its tells (%s, attacks %s)" % [mode, str(main.log_tells), str(atk)])
		kit.assert_true(not saw_tells.is_empty() or atk == ["stomp"], "%s: the tells were drawn (%s)" % [mode, str(saw_tells)])
	if first <= 1:
		kit.assert_true(quest_max > 0, "%s: quest things were found (%d)" % [mode, quest_max])
	if first == 0 and not main.heroes.is_empty() and not (main.heroes.size() == 1 and main.heroes.has(0)):
		kit.assert_true(not main.log_classes.is_empty(), "%s: TV heroes picked heroes at the statues (%s)" % [mode, str(main.log_classes)])
	if saw_map > 0:
		kit.assert_true(not main.log_regions.is_empty(), "%s: a region was picked on the map (%s)" % [mode, str(main.log_regions)])
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
