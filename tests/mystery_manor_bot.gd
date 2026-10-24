extends Node
## Headless bot for games/mystery_manor: validates 300 generated cases (deduction checker), checks that
## every spawn, search spot, suspect place, doorway and stair in the manor can be reached on foot, then
## plays: TV bots walk the manor's nav paths to the clues, then to the last suspect and press A.
## BOT_PLAYERS=n TV players (default 2). BOT_VR=1: a fake VR detective walks too and taps the culprit.
## DUO_FLAT_HOST=1 on the host: one bot pad plays slot 0 there.
## Local:      godot-test --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/mystery_manor_bot.tscn
## Networked:  DUO_PORT=7996 DUO_HOST=1 ... & DUO_PORT=7996 DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")
const Manor := preload("res://games/mystery_manor/manor.gd")
const Case := preload("res://games/mystery_manor/case.gd")

var kit: BotKit
var main: Node
var want := 2
var paths := {}  # slot -> {target: Vector3, pts: PackedVector3Array, i: int, t: float}
var saw_results := false
var saw_step_back := false
var saw_solved := false
var max_found := 0
var vr_walked := 0.0
var vr_last := Vector3.INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/mystery_manor/main.tscn").instantiate()
	main.set("walk_speed", 7.0)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	if not client and not host:
		_validate_cases()
	kit.at(0.5, "connectivity", _connectivity)
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, _join)
	kit.every(2.0, _report)
	kit.every(0.25, _watch)
	if host:
		kit.at(45.0, "host checks", _checks)
		kit.at(52.0, "finish", kit.finish)
	else:
		kit.at(48.0 if client else 55.0, "finish", func() -> void:
			_checks()
			kit.finish())


func _validate_cases() -> void:
	var bad := 0
	for s in 300:
		var c := Case.generate(s * 7919 + 13)
		var why := Case.check(c)
		if why != "":
			bad += 1
			if bad < 5:
				kit.info("case %d: %s" % [s, why])
	kit.info("cases: %d of 300 fair" % (300 - bad))
	kit.assert_eq(bad, 0, "every generated case is fair (300 seeds; main also re-rolls unfair ones)")


func _connectivity() -> void:
	var m = main.manor
	if m == null:
		kit.assert_true(false, "the manor was built")
		return
	var starts := {0: Manor.VR_SPAWN, 1: (Manor.PORTALS[0] as Dictionary)["to"], 2: (Manor.PORTALS[2] as Dictionary)["to"]}
	var targets: Array = []
	for sp in Manor.SPOTS:
		targets.append([(sp as Dictionary)["stand"], "spot %s" % (sp as Dictionary)["name"]])
	for p in Manor.TV_SPAWNS:
		targets.append([p, "TV spawn"])
	for p in Manor.GATHER:
		targets.append([p, "suspect place"])
	for r in Manor.LOITER.size():
		for p in Manor.LOITER[r]:
			targets.append([p, "%s floor" % Manor.room_name(r)])
	for d in Manor.DOORS:
		targets.append([(d as Array)[2], "doorway %s-%s" % [Manor.room_name(int((d as Array)[0])), Manor.room_name(int((d as Array)[1]))]])
	for p in Manor.PORTALS:
		targets.append([(p as Dictionary)["zone"], "stairs %s" % (p as Dictionary)["label"]])
		targets.append([(p as Dictionary)["to"], "stairs arrival %s" % (p as Dictionary)["label"]])
	var bad := 0
	for t in targets:
		var p: Vector3 = t[0]
		var lv := Manor.level_of_y(p.y)
		var ok: bool = m.reachable(starts[lv], m.snap_walkable(p)) and m.snap_walkable(p).distance_to(Vector3(p.x, Manor.LEVEL_Y[lv], p.z)) < 0.6
		if not ok:
			bad += 1
			kit.info("can't reach %s at %s (nearest walkable %s)" % [t[1], p, m.snap_walkable(p)])
	for sp in Manor.SPOTS:
		var d: Dictionary = sp
		var at: Vector3 = d["pos"]
		var stand: Vector3 = d["stand"]
		var clue := at.lerp(Vector3(stand.x, at.y, stand.z), 0.45)
		if Vector2(clue.x - stand.x, clue.z - stand.z).length() > main.PICK_RANGE - 0.1:
			bad += 1
			kit.info("clue at %s is out of reach from where you stand" % d["name"])
	kit.assert_eq(bad, 0, "every spot, spawn, doorway and stair can be reached on foot (%d places)" % targets.size())


func _join() -> void:
	if main.net.mode == "host":
		if main.flat_host:
			kit.join_bot(main.party)
		return
	for i in want:
		kit.join_bot(main.party)


func _watch() -> String:
	var c: Dictionary = main.net.state_get("case", {})
	if c.is_empty():
		return ""
	var found: Array = main.net.state_get("found", [false, false, false])
	max_found = maxi(max_found, found.count(true))
	if bool(found[0]) or bool(found[1]):
		if main._still_suspects(c).size() < 6:
			saw_step_back = true
	var phase := String(main.net.state_get("phase", ""))
	if phase == "solved":
		saw_solved = true
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
		var slots: Array[int] = main.party.local_slots()
		if not slots.is_empty():
			kit.slot_press(main.party, slots[0], "accept")
		if main.vr_rig != null:
			kit.vr_trigger(main.vr_rig, 1.0 if Engine.get_process_frames() % 20 < 10 else 0.0)
	return ""


## Where a bot should go: its share of the clues still out there, else the last suspect.
func _goal(index: int) -> Vector3:
	var c: Dictionary = main.net.state_get("case", {})
	var found: Array = main.net.state_get("found", [false, false, false])
	var open: Array[int] = []
	for k in 3:
		if not bool(found[k]) and k < main.clue_nodes.size():
			open.append(k)
	var left: Array[int] = main._still_suspects(c)
	if left.size() == 1 or open.is_empty():
		return main.suspects[left[0]].position + Vector3(1.0, 0.0, 0.0)
	var k := open[index % open.size()]
	var sp: Dictionary = Manor.SPOTS[int((c["spots"] as Array)[k])]
	return sp["stand"]


## Next waypoint towards `goal` from `from` (path recomputed when the goal, the level or the time changes).
func _waypoint(key: Variant, from: Vector3, goal: Vector3, delta: float) -> Vector3:
	var st: Dictionary = paths.get(key, {})
	st["t"] = float(st.get("t", 0.0)) - delta
	if not st.has("target") or (st["target"] as Vector3).distance_to(goal) > 0.5 or float(st["t"]) <= 0.0 \
			or Manor.level_of_y(from.y) != int(st.get("lv", -9)):
		st["target"] = goal
		st["pts"] = main.manor.path(from, goal)
		st["i"] = 0
		st["t"] = 1.5
		st["lv"] = Manor.level_of_y(from.y)
	var pts: PackedVector3Array = st["pts"]
	var i: int = st["i"]
	while i < pts.size() - 1 and (Vector2(pts[i].x - from.x, pts[i].z - from.z).length() < 0.3 or absf(pts[i].y - from.y) > 2.0):
		i += 1
	st["i"] = i
	paths[key] = st
	return pts[i] if i < pts.size() else goal


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or String(main.net.state_get("phase", "")) != "play":
		for slot in (main.party.local_slots() if main != null and main.party != null else []):
			kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	var n := 0
	for slot in main.party.local_slots():
		if not main.avatars.has(slot):
			continue
		var a: Node3D = main.avatars[slot]
		var goal := _goal(n)
		n += 1
		var wp := _waypoint(slot, a.position, goal, delta)
		var d := wp - a.position
		d.y = 0.0
		var v := Vector2.ZERO
		if d.length() > 0.05:
			d = d.normalized()
			var cam: Camera3D = main.split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			v = Vector2(d.dot(r), -d.dot(f))
		kit.slot_stick(main.party, slot, "left", v)
		var c: Dictionary = main.net.state_get("case", {})
		if main._still_suspects(c).size() == 1 and main._suspect_near(a.position, main.ACCUSE_RANGE) >= 0 and Engine.get_physics_frames() % 15 == 0:
			kit.slot_press(main.party, slot, "accept")
	if main.vr_rig != null:
		_drive_vr(delta, n)


## Fake VR detective: walks the nav path with the left stick, taps the last suspect with the right glove.
func _drive_vr(delta: float, index: int) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.6
	var head: Vector3 = rig.head_position()
	var feet := Vector3(head.x, rig.floor_height, head.z)
	if vr_last != Vector3.INF and feet.distance_to(vr_last) < 3.0:
		vr_walked += feet.distance_to(vr_last)
	vr_last = feet
	var c: Dictionary = main.net.state_get("case", {})
	var left: Array[int] = main._still_suspects(c)
	var goal := _goal(index)
	var wp := _waypoint("vr", feet, goal, delta)
	var d := wp - feet
	d.y = 0.0
	var f: Vector3 = rig.head_forward()
	var r := Vector3(-f.z, 0.0, f.x)
	kit.vr_stick(rig, Vector2(d.normalized().dot(r), d.normalized().dot(f)) if d.length() > 0.2 else Vector2.ZERO)
	if left.size() == 1 and feet.distance_to(main.suspects[left[0]].position) < 1.6:
		kit.vr_reach(rig, 1, main.suspects[left[0]].position + Vector3.UP * 0.65, 2.5, delta)


func _report() -> String:
	var c: Dictionary = main.net.state_get("case", {})
	return "BOT %s: phase %s, case %d, found %s, suspects left %s, players %s" % [main.net.mode,
		String(main.net.state_get("phase", "")), int(main.net.state_get("cases", 0)), str(main.net.state_get("found", [])),
		str(main._still_suspects(c)) if not c.is_empty() else "-", str(main.party.active_slots())]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_true(main.party.local_slots().size() == want, "client: all %d local players are seated" % want)
	else:
		kit.assert_eq(main.party.player_count(), kit.seated_want(want, (1 if main.flat_host else 0)), "%s: all players are seated" % mode)
	kit.assert_true(max_found >= 2, "%s: clues were found (%d)" % [mode, max_found])
	kit.assert_true(saw_step_back, "%s: suspects who don't match stepped back" % mode)
	kit.assert_true(saw_solved, "%s: the case was solved" % mode)
	kit.assert_true(saw_results, "%s: results were shown" % mode)
	kit.assert_true(int(main.net.state_get("cases", 0)) >= 2, "%s: a second case started" % mode)
	if main.vr_rig != null:
		kit.assert_true(vr_walked > 5.0, "the fake VR detective walked the manor (%.0f m)" % vr_walked)
