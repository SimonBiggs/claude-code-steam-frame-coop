extends Node
## Headless bot for games/dungeon_delve. TV bots (BOT_PLAYERS, default 2) walk to the practice pot,
## then to the nearest monster (bats once they swoop low) and bonk with A; when the gate opens they
## walk through it; in the treasure room they bonk the big chest. The fake VR knight (BOT_VR=1)
## waits while the ghost hand shows the swing, slices the dummy, walks to monsters with the left stick
## and swings the sword through them, grabs a pot with the left hand and flicks it, pokes the torch,
## chest and skeleton of each cleared room, and opens the treasure (then touches it again: AGAIN).
## Design check: every room gets entered, the treasure gets opened and the results show; the practice
## targets got done; knight and heroes bopped monsters; props reacted; the TV machine mirrors it all;
## everything stays inside the walls.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 12000 res://tests/dungeon_delve_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## DD_ROOM=n starts in room n (0..4).
## DEEP (BRAVE / HEROIC): DD_MODE=brave|heroic starts the deep dungeon; tests/dungeon_delve_deep_bot.gd
## plays it (fights, loot, keys, puzzles, secrets, revives, shop, stairs). BOT_GOAL=zone ends the test
## as soon as the first boss is beaten and the next zone is reached (floors 1-4 + shops + the Slime
## King); BOT_GOAL=floor after the first floor; DD_FLOOR=3 starts on the first boss floor.
## Checks: the floors went by in order, monsters died, keys opened doors, the boss fell (zone goal),
## knocked-out heroes got back up (or none were), heroes stayed on walkable ground, the TV machine
## built the same kind of floor and mirrored monsters and hearts. Flat host: DUO_FLAT_HOST=1 on the host.

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Dungeon := preload("res://games/dungeon_delve/dungeon.gd")
const DeepBot := preload("res://tests/dungeon_delve_deep_bot.gd")
const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var results_t := -1.0
var again_sent := false
var max_mons := 0
var bonk_cd := {}
var vr_step := "wait"
var vr_t := 0.0
var swing_side := 1.0
var poke_list: Array[int] = []
var thrown := false
var outside := 0
var brain: DeepBot
var deep_mode := OS.get_environment("DD_MODE") if OS.has_environment("DD_MODE") else ""
var goal := OS.get_environment("BOT_GOAL") if OS.has_environment("BOT_GOAL") else ""
var off_floor := 0
var max_foes := 0
var floors_seen := {}
var goal_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/dungeon_delve/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	brain = DeepBot.new()
	brain.kit = kit
	brain.main = main
	add_child(brain)
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party)
		elif not main.net.has_vr:
			kit.join_bot(main.party))  # a flat host: one pad player here, in slot 0
	kit.every(4.0, _report)
	kit.every(0.25, _watch)
	var end := 150.0 if host else (140.0 if client else 170.0)
	if OS.has_environment("BOT_END"):
		end = float(OS.get_environment("BOT_END"))
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _watch() -> String:
	if main.monsters == null:
		return ""
	if main.deep != null and main.deep.active:
		var dp = main.deep
		if not dp.f.is_empty():
			floors_seen[dp.built_key] = true
			max_foes = maxi(max_foes, dp.foes.mons.size())
			for h in main.heroes.values():
				if not FloorGen.walkable(dp.view.rects, dp.view.obst, h.position, 0.05) and FloorGen.room_at(dp.f, h.position) >= 0:
					off_floor += 1
		if main.net.mode != "client" and not goal_done:
			var t: Dictionary = dp.tally
			var reached := false
			if goal == "zone":
				reached = int(t["bosses"]) >= 1 and (t["floors"] as Array).has(FloorGen.FLOORS_PER_ZONE)
			elif goal == "floor":
				reached = (t["floors"] as Array).size() >= 2
			if reached:
				goal_done = true
				kit.info("GOAL reached: %s" % goal)
				_checks()
				kit.finish()
		return ""
	max_mons = maxi(max_mons, main.monsters.count())
	for h in main.heroes.values():
		var p: Vector3 = h.position
		if absf(p.x) > Dungeon.HALF or p.z > Dungeon.HALF or p.z < -(Dungeon.ROOMS - 1) * Dungeon.ROOM - Dungeon.HALF:
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
	if main == null or not main.ready_to_play or main.dungeon == null:
		return
	if main.deep != null and main.deep.active:
		brain.tick(delta)
		var idx := 0
		for slot in main.party.local_slots():
			brain.hero(slot, delta, idx)
			idx += 1
		if main.vr_rig != null:
			brain.knight(delta)
		return
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


func _phase() -> String:
	return String(main.net.state_get("phase", ""))


func _room() -> int:
	return int(main.net.state_get("room", 0))


## Through doorways: head for the middle of the gate first.
func _waypoint(from: Vector3, to: Vector3) -> Vector3:
	var a := Dungeon.room_of(from)
	var b := Dungeon.room_of(to)
	if a == b:
		return to
	var wz := Dungeon.wall_z(mini(a, b))
	var side := 1.0 if from.z > wz else -1.0
	if absf(from.x) > 0.5 and absf(from.z - wz) > 0.3:
		return Vector3(0.0, 0.0, wz + side * 1.0)
	return Vector3(0.0, 0.0, wz - side * 1.5)


## A TV hero.
func _tv_bot(slot: int, delta: float) -> void:
	if not main.heroes.has(slot):
		return
	var h = main.heroes[slot]
	var pos: Vector3 = h.position
	bonk_cd[slot] = float(bonk_cd.get(slot, 0.0)) - delta
	var target := Vector3.INF
	var phase := _phase()
	var room := _room()
	var dg = main.dungeon
	match phase:
		"practice":
			if not dg.is_used(0):
				target = dg.prop_center(0)
		"fight":
			var best := INF
			for id in main.monsters.mons:
				var c: Vector3 = main.monsters.center_of(id)
				var d := pos.distance_to(Vector3(c.x, 0.0, c.z))
				if Dungeon.room_of(c) == room and d < best:
					best = d
					target = c
		"cleared":
			if int(main.net.state_get("open", 0)) > room:
				target = Dungeon.center(room + 1) + Vector3(-1.5 + slot * 0.5, 0.0, 1.0)
		"treasure":
			target = dg.prop_center(dg.big_id) + Vector3(0.0, 0.0, 1.6)
	if target == Vector3.INF:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	var wp := _waypoint(pos, target)
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	var reach := 0.75 if phase in ["fight", "practice"] else 0.3
	if wp == target and to.length() < reach:
		kit.slot_stick(main.party, slot, "left", Vector2(to.x, to.z).normalized() * 0.2)
		var low: bool = target.y < 1.4
		if (low or phase != "fight") and float(bonk_cd[slot]) <= 0.0:
			bonk_cd[slot] = 0.45
			kit.slot_press(main.party, slot, "accept")
		return
	if phase == "treasure" and to.length() < 0.6 and float(bonk_cd[slot]) <= 0.0:
		bonk_cd[slot] = 0.45
		kit.slot_press(main.party, slot, "accept")
	var v := Vector2(to.x, to.z).normalized()
	kit.slot_stick(main.party, slot, "left", v)


## The fake VR knight.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	var dg = main.dungeon
	rig.camera.position = Vector3(0.0, 1.5, 0.0)
	vr_t += delta
	var head: Vector3 = rig.head_position()
	var feet := Vector3(head.x, 0.0, head.z)
	var phase := _phase()
	var room := _room()
	kit.vr_stick(rig, Vector2.ZERO)
	var rest_r := head + Vector3(0.25, -0.5, -0.25)
	var rest_l := head + Vector3(-0.25, -0.5, -0.25)
	match phase:
		"practice":
			if vr_t > 3.5 and not dg.is_used(dg.dummy_id):
				_swing(rig, dg.prop_center(dg.dummy_id), delta)
			else:
				kit.vr_reach(rig, VrRig.RIGHT, rest_r, 2.0, delta)
		"fight":
			# First fight: grab a pot with the left hand and flick it at a slime.
			if room == 1 and not thrown and main.hands.held_pot < 0:
				var pid := _pot_in(room)
				if pid >= 0:
					kit.vr_reach(rig, VrRig.LEFT, dg.prop_center(pid), 6.0, delta)
			elif main.hands.held_pot >= 0:
				kit.vr_reach(rig, VrRig.LEFT, head + Vector3(-0.3, 0.0, -2.0), 8.0, delta)
				if vr_t > 1.0:
					vr_t = 0.0
			else:
				if main.log_throws > 0:
					thrown = true
				kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)
			var best := INF
			var target := Vector3.INF
			for id in main.monsters.mons:
				var c: Vector3 = main.monsters.center_of(id)
				var d := feet.distance_to(Vector3(c.x, 0.0, c.z))
				if d < best:
					best = d
					target = c
			if target != Vector3.INF:
				var want_at := target + Vector3(0.0, 0.0, 0.75)
				var to := Vector3(want_at.x - feet.x, 0.0, want_at.z - feet.z)
				if to.length() > 0.5:
					kit.vr_stick(rig, Vector2(to.x, -to.z).normalized())
				_swing(rig, target, delta)
		"cleared":
			if poke_list.is_empty() and int(main.net.state_get("open", 0)) <= room:
				for id in dg.props.size():
					var k: int = dg.props[id]["kind"]
					if int(dg.props[id]["room"]) == room and k in [Dungeon.TORCH, Dungeon.CHEST, Dungeon.SKEL]:
						poke_list.append(id)
			if not poke_list.is_empty():
				var pid2: int = poke_list[0]
				if kit.vr_reach(rig, VrRig.LEFT, dg.prop_center(pid2), 8.0, delta) or vr_t > 1.5:
					poke_list.pop_front()
					vr_t = 0.0
					kit.vr_reach(rig, VrRig.LEFT, rest_l, 1000.0, 1.0)
			elif int(main.net.state_get("open", 0)) > room:
				kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)
				var goal := Dungeon.center(room + 1) + Vector3(0.6, 0.0, 1.5)
				var wp := _waypoint(feet, goal)
				var to2 := Vector3(wp.x - feet.x, 0.0, wp.z - feet.z)
				if to2.length() > 0.2:
					kit.vr_stick(rig, Vector2(to2.x, -to2.z).normalized())
		"treasure", "results":
			var bc: Vector3 = dg.prop_center(dg.big_id)
			var stand := bc + Vector3(0.6, 0.0, 1.4)
			var to3 := Vector3(stand.x - feet.x, 0.0, stand.z - feet.z)
			if to3.length() > 0.3:
				kit.vr_stick(rig, Vector2(to3.x, -to3.z).normalized())
			elif phase == "treasure" or (saw_results and kit.t - results_t > 6.0 and not again_sent):
				if kit.vr_reach(rig, VrRig.LEFT, bc, 3.0, delta) and phase == "results":
					again_sent = true
			else:
				kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)


func _pot_in(room: int) -> int:
	var dg = main.dungeon
	for id in dg.props.size():
		if int(dg.props[id]["kind"]) == Dungeon.POT and int(dg.props[id]["room"]) == room and not dg.is_used(id):
			return id
	return -1


## Sweep the right hand side to side so the sword blade (pointing -Z) passes through the target.
func _swing(rig: Node, target: Vector3, delta: float) -> void:
	var p := target + Vector3(swing_side * 0.45, 0.0, 0.6)
	if kit.vr_reach(rig, VrRig.RIGHT, p, 5.0, delta):
		swing_side = -swing_side


func _report() -> String:
	if main.dungeon == null:
		return "waiting"
	if main.deep != null and main.deep.active:
		var dp = main.deep
		var hp := []
		var st: Dictionary = main.net.state_get("d_stats", {})
		for s in st:
			hp.append("%s:%d%s" % [s, int(st[s]["hp"]), "x" if bool(st[s]["down"]) else ""])
		var few := ""
		if dp.foes.mons.size() <= 2:
			for id in dp.foes.mons:
				var m: Dictionary = dp.foes.mons[id]
				few += " [k%d st%d %s hp%d]" % [int(m["kind"]), int(m["st"]), str(Vector3(m["p"]).snappedf(0.1)), int(m["hp"])]
			for h in main.heroes.values():
				few += " hero %s" % str(h.position.snappedf(0.1))
			if main.vr_rig != null:
				few += " knight %s swings %d" % [str(main.vr_rig.head_position().snappedf(0.1)), main.hands.swings]
		return few + " BOT %s DEEP %s room %d lock %d foes %d gold %d keys %d hp %s %s" % [main.net.mode, dp.built_key,
			dp._focus_room(), int(main.net.state_get("d_lock", -1)), dp.foes.mons.size(), int(main.net.state_get("d_gold", 0)),
			int(main.net.state_get("d_keys", 0)), str(hp), str(dp.tally) if main.net.mode != "client" else ""]
	return "BOT %s: room %d phase %s open %d monsters %d heroes %d bops %s pokes %s dizzy %d throws %d" % [
		main.net.mode, _room(), _phase(), int(main.net.state_get("open", 0)), main.monsters.count(),
		main.heroes.size(), str(main.log_bops), str(main.log_pokes), main.log_dizzy, main.log_throws]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if deep_mode != "":
		_deep_checks(mode)
		return
	kit.assert_eq(outside, 0, "%s: heroes stayed inside the dungeon" % mode)
	if mode != "host":
		kit.assert_eq(main.party.player_count(), kit.seated_want(want), "%s: all %d TV players are seated" % [mode, want])
	if mode == "client":
		kit.assert_true(max_mons >= 2, "client mirrors the monsters (%d)" % max_mons)
		kit.assert_true(int(main.net.state_get("open", 0)) >= 2 or saw_results or again_sent, "client saw gates open")
		return
	var first := int(OS.get_environment("DD_ROOM")) if OS.has_environment("DD_ROOM") else 0
	for r in range(first, Dungeon.ROOMS):
		kit.assert_true(main.log_rooms.has(r), "%s: room %d was entered" % [mode, r])
	kit.assert_true(saw_results, "%s: the treasure was found and the results showed" % mode)
	if not OS.has_environment("DD_ROOM"):
		if main.vr_rig != null:
			kit.assert_true(main.dungeon.is_used(main.dungeon.dummy_id) or main.log_rooms.size() > 1, "the knight did the practice")
			kit.assert_true(main.ghost.shown, "the ghost hand showed the swing")
	if main.vr_rig != null:
		kit.assert_true(main.hands.swings > 0, "the knight bopped monsters (%d)" % main.hands.swings)
		kit.assert_true(main.log_throws > 0, "the knight threw a pot (%d)" % main.log_throws)
		kit.assert_true(main.log_pokes.size() >= 3, "props reacted (%s)" % str(main.log_pokes))
	if mode == "local":
		var tv := 0
		for s in main.log_bops:
			if int(s) > 0 or main.vr_rig == null:
				tv += int(main.log_bops[s])
		kit.assert_true(tv > 0, "the TV heroes bopped monsters (%d)" % tv)


func _deep_checks(mode: String) -> void:
	var dp = main.deep
	kit.assert_true(off_floor < 8, "%s: heroes stayed on walkable ground (%d)" % [mode, off_floor])
	if mode != "host":
		kit.assert_eq(main.party.local_slots().size(), want, "%s: all %d TV players here are seated" % [mode, want])
	if mode == "client":
		kit.assert_true(floors_seen.size() >= 1, "client built the deep floors (%d)" % floors_seen.size())
		kit.assert_true(max_foes >= 1, "client mirrors the monsters (%d)" % max_foes)
		kit.assert_true(not (main.net.state_get("d_stats", {}) as Dictionary).is_empty(), "client sees everyone's hearts")
		return
	var t: Dictionary = dp.tally
	var fl: Array = t["floors"]
	kit.assert_true(fl.size() >= 1, "%s: a deep floor started (%s)" % [mode, str(fl)])
	for i in range(1, fl.size()):
		kit.assert_true(int(fl[i]) == int(fl[i - 1]) + 1 or int(t["wipes"]) > 0, "%s: floors went down in order (%s)" % [mode, str(fl)])
	kit.assert_true(int(t["kills"]) > 0, "%s: monsters were beaten (%d)" % [mode, int(t["kills"])])
	if goal in ["zone", "floor"]:
		kit.assert_true(goal_done, "%s: the goal (%s) was reached: %s" % [mode, goal, str(t)])
		kit.assert_true(int(t["keys"]) >= 1 and int(t["doors"]) >= 1, "%s: a key opened a door (%d keys, %d doors)" % [mode, int(t["keys"]), int(t["doors"])])
	var pd: Dictionary = dp.progress()
	kit.assert_true(int(pd["runs"]) >= 1, "%s: the run was saved (%s)" % [mode, str(pd)])
	if goal == "zone":
		kit.assert_true(int(t["bosses"]) >= 1, "%s: the boss was beaten" % mode)
		kit.assert_true(int((pd["bosses"] as Dictionary).get(deep_mode, 0)) & 1 != 0, "%s: the boss win was saved (perk + hat unlocked)" % mode)
		kit.assert_true(dp.unlocked_hats().has("wizard") and int(dp.perks()["potion"]) == 1, "%s: the Slime King unlocks the wizard hat and a starting potion" % mode)
		kit.assert_true(int(t["bought"]) >= 1 or main.heroes.is_empty(), "%s: something was bought in a shop (%d)" % [mode, int(t["bought"])])
	if int(t["downs"]) > 0:
		kit.assert_true(int(t["revives"]) > 0 or int(t["wipes"]) > 0, "%s: knocked-out heroes got back up (%d downs, %d revives)" % [mode, int(t["downs"]), int(t["revives"])])
	if main.vr_rig != null:
		kit.assert_true(main.hands.swings > 0, "the knight hit monsters (%d)" % main.hands.swings)
	# The run ends and "Again!" goes back to the gentle practice room (crashed on the TV, 25 Oct).
	dp.finish(false)
	kit.assert_eq(String(main.net.state_get("phase", "")), "results", "%s: a finished run shows the results" % mode)
	main.on_request(0, "again", [])
	kit.assert_true(not dp.active and String(main.net.state_get("phase", "")) == "practice" and main.dungeon.visible, "%s: Again goes back to the gentle practice room" % mode)
