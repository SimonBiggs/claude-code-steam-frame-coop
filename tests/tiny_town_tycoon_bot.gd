extends Node
## Headless bot for games/tiny_town_tycoon. The mayor (a fake-VR glove with BOT_VR=1, else the flat
## cursor mayor in slot 0) lays out roads and buildings from the tray; TV bot drivers pick vehicles
## and follow their job arrows (A* along the town's roads) to deliver, build and put out a fire. The
## town should grow past its first milestone (TT_FAST=1), then the town is saved and reloaded.
## Local:     TT_FAST=1 godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/tiny_town_tycoon_bot.tscn
## Networked: DUO_PORT=8070 DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=8070 DUO_JOIN=127.0.0.1 BOT_PLAYERS=3 ...

const BotKit := preload("res://tests/bot_kit.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const VrRig := preload("res://core/vr_rig.gd")
const UiMenu := preload("res://core/ui_menu.gd")
const Save := preload("res://core/save.gd")

var kit: BotKit
var main: Node
var want := 2
var host := false
var client := false
var plan: Array = []  ## [kind, cells: Array[Vector2i]] steps for the mayor
var step := 0
var step_t := 0.0
var vr_state := ""
var vr_path: Array[Vector2i] = []
var vr_i := 0
var placed := 0
var paths := {}  ## slot -> {"t": seconds to re-plan, "path": Array[Vector2i], "i": int}
var touched := false
var saw_results := false
var orbit_t := 0.0
var picked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	if not OS.has_environment("TT_KEEP_SAVE"):
		Save.erase("tiny_town_tycoon")  # a fresh island each run (test saves only)
	main = load("res://games/tiny_town_tycoon/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	client = OS.has_environment("DUO_JOIN")
	host = OS.has_environment("DUO_HOST")
	want = BotKit.bot_players(2, 6)
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d players press A on their pads" % want, _join)
	kit.at(t0 + 2.5, "pick the island", _pick)
	kit.at(t0 + 5.0, "island picked?", func() -> void:
		if not client:
			if String(main.phase()) != "play":
				kit.info("menu didn't pick: asking the host directly")
				main.net.request(0, "pick_island", [0])
		_make_plan())
	if not host:
		kit.at(t0 + 7.0, "P2 presses Y: one shared view", func() -> void: _press_driver("y"))
		kit.at(t0 + 8.0, "shared?", func() -> void:
			if main.split != null:
				kit.assert_true(main.split.is_shared(), "Y switched to the shared view"))
		kit.at(t0 + 10.0, "P2 presses Y again: split screen", func() -> void: _press_driver("y"))
		kit.at(t0 + 11.0, "split?", func() -> void:
			if main.split != null:
				kit.assert_true(not main.split.is_shared(), "Y switched back to split screen"))
		kit.at(t0 + 12.0, "Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press_any("start"))
		kit.at(t0 + 12.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and main.tv_banner.visible, "Start pauses and shows the banner")
			_press_any("start"))
		kit.at(t0 + 13.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	if not client:
		kit.at(30.0, "a small fire breaks out", func() -> void:
			kit.assert_true(main.debug_event("fire"), "a fire started"))
		kit.at(20.0, "a festival (if there's a park)", func() -> void: main.debug_event("festival"))
	if not client:
		kit.at(42.0, "the island's goals are all done (forced): results", func() -> void:
			for k in main.goals_done.size():
				main.goals_done[k] = true
			main._complete_island())
		kit.at(48.0, "back to the town after the results?", func() -> void:
			kit.assert_true(saw_results, "the island-complete results showed")
			kit.assert_eq(String(main.phase()), "play", "Continue goes back to the town"))
	if not host:
		kit.at(16.0, "a driver honks (A)", func() -> void: _press_driver("accept"))
	if client:
		kit.at(52.0, "finish", func() -> void:
			_checks()
			kit.finish())
	elif host:
		kit.at(50.0, "save + reload", _save_reload)
		var end := float(OS.get_environment("TT_HOST_END")) if OS.has_environment("TT_HOST_END") else 62.0
		kit.at(end - 4.0, "host checks", _checks)
		kit.at(end, "finish", kit.finish)
	else:
		kit.at(50.0, "save + reload", _save_reload)
		kit.at(57.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(3.0, _report)
	kit.every(0.5, _menus)


func _join() -> void:
	if host:
		return
	for i in want:
		kit.join_bot(main.party)


func _pick() -> void:
	if client:
		return
	if main.vr_rig != null and main.mayor != null and main.mayor.island_menu != null:
		kit.vr_a(main.vr_rig, true)
		get_tree().create_timer(0.2).timeout.connect(func() -> void: kit.vr_a(main.vr_rig, false))
	else:
		var seats: Array[int] = main.party.local_slots()
		if not seats.is_empty():
			kit.slot_press(main.party, seats[0], "accept")


func _press_driver(action: String) -> void:
	for s in main.party.local_slots():
		if s >= 1:
			kit.slot_press(main.party, s, action)
			return


func _press_any(action: String) -> void:
	var seats: Array[int] = main.party.local_slots()
	if not seats.is_empty():
		kit.slot_press(main.party, seats[0], action)


## Open menus: drivers take the suggested vehicle; results: continue.
func _menus() -> String:
	for s in main.party.local_slots():
		if s >= 1 and UiMenu.slot_busy(s) and main.phase() == "play":
			kit.slot_press(main.party, s, "accept")
	if main.phase() == "complete":
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the island-complete results show on the TV")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
		_press_any("accept")
		if main.vr_rig != null:
			kit.vr_trigger(main.vr_rig, 1.0)
			get_tree().create_timer(0.2).timeout.connect(func() -> void: kit.vr_trigger(main.vr_rig, 0.0))
	return ""


# --- The mayor's plan --------------------------------------------------------------------------------

func _make_plan() -> void:
	if client or (main.vr_rig == null and main.flat == null):
		return
	var town = main.town
	var hz := Defs.GRID / 2  # the starter street row (town.starter_town)
	var row: Array[Vector2i] = []
	for x in range(4, Defs.GRID - 4):
		if town.can_place("road", x, hz) == "" or town.has_road(x, hz):
			row.append(Vector2i(x, hz))
	plan.append(["road", row])
	var col: Array[Vector2i] = []
	for z in range(hz + 1, hz + 7):
		if town.can_place("road", 12, z) == "":
			col.append(Vector2i(12, z))
		else:
			break
	plan.append(["road", col])
	for k in ["windmill", "water", "house", "house", "farm", "shop", "house", "house", "park", "house", "house", "shop", "house", "house",
			"house", "windmill", "water", "bakery", "house", "house", "school"]:
		plan.append([String(k), []])
	kit.info("plan: %d steps" % plan.size())


## A free spot next to a road for a building, closest to the town centre.
func _spot(kind: String) -> Vector2i:
	var town = main.town
	var s := Defs.size_of(kind)
	var best := Vector2i(-1, -1)
	var bd := INF
	for z in Defs.GRID:
		for x in Defs.GRID:
			if main.place_problem(kind, x, z) != "":
				continue
			var b := {"kind": kind, "x": x, "z": z}
			if not town.on_road(b):
				continue
			# keep the street ends free for more roads
			var d := Vector2(x + s * 0.5, z + s * 0.5).distance_to(Vector2(Defs.GRID * 0.5, Defs.GRID * 0.5 + 1.0))
			if d < bd:
				bd = d
				best = Vector2i(x, z)
	return best


func _process(delta: float) -> void:
	if main == null or not main.ready_to_play or client:
		return
	if main.phase() != "play":
		if main.vr_rig != null:
			kit.vr_idle(main.vr_rig, 1.6)
		return
	step_t -= delta
	if main.vr_rig != null:
		_vr_mayor(delta)
	elif main.flat != null:
		_flat_mayor()


func _next_step() -> Array:
	while step < plan.size():
		var st: Array = plan[step]
		var kind := String(st[0])
		if Defs.is_tool_kind(kind):
			if (st[1] as Array).is_empty():
				step += 1
				continue
			return st
		if main.place_problem(kind, 0, 0).begins_with("Unlocks") or main.place_problem(kind, 0, 0).begins_with("Needs"):
			return []  # wait for the town to grow / earn
		var c := _spot(kind)
		if c.x < 0:
			step += 1
			continue
		return [kind, [c]]
	return []


func _flat_mayor() -> void:
	if step_t > 0.0:
		return
	var flat = main.flat
	if vr_state == "paint":
		if vr_i < vr_path.size():
			flat.move_to(vr_path[vr_i])
			vr_i += 1
			step_t = 0.05
			return
		kit.slot_hold(main.party, 0, "accept", false)
		vr_state = ""
		step += 1
		step_t = 0.3
		return
	var st := _next_step()
	if st.is_empty():
		step_t = 1.0
		return
	var kind := String(st[0])
	var cells: Array = st[1]
	flat.select(kind)
	if Defs.is_tool_kind(kind):
		vr_path.clear()
		for c in cells:
			vr_path.append(c)
		flat.move_to(vr_path[0])
		vr_i = 1
		vr_state = "paint"
		kit.slot_hold(main.party, 0, "accept", true)
		step_t = 0.1
		placed += 1
		return
	var cell: Vector2i = cells[0]
	flat.move_to(cell)
	flat.manual = false
	kit.slot_press(main.party, 0, "accept")
	placed += 1
	step += 1
	step_t = 0.5


## The fake VR mayor: reach to the tray, grab, carry to the cell, let go (or draw roads).
func _vr_mayor(delta: float) -> void:
	var rig = main.vr_rig
	var mayor = main.mayor
	rig.camera.position = Vector3(0.0, 1.6, 0.0)
	rig.camera.basis = Basis()
	if touched or placed < 6:
		rig.hand_l.position = Vector3(-0.45, 0.7, 0.25)  # resting by the side, away from the right hand's work
	# turn the table a little at the start, and back
	orbit_t += delta
	if orbit_t < 1.0:
		kit.vr_stick(rig, Vector2.ZERO, Vector2(0.6, 0.0))
	elif orbit_t < 2.0:
		kit.vr_stick(rig, Vector2.ZERO, Vector2(-0.6, 0.0))
	else:
		kit.vr_stick(rig, Vector2.ZERO, Vector2.ZERO)
	var palm_off: Vector3 = rig.hand_point(VrRig.RIGHT) - rig.hand(VrRig.RIGHT).global_position
	match vr_state:
		"":
			kit.vr_trigger(rig, 0.0)
			if step_t > 0.0 or orbit_t < 2.5:
				return
			# touch a house with the left glove once (speech bubble)
			if not touched and placed >= 6:
				var houses: Array = main.town.of_kind("house", true)
				if not houses.is_empty():
					var hc: Vector3 = main.town.center_of(houses[0])
					var lo: Vector3 = rig.hand_point(VrRig.LEFT) - rig.hand(VrRig.LEFT).global_position
					if kit.vr_reach(rig, VrRig.LEFT, hc + Vector3(0, 0.03, 0) - lo, 3.0, delta):
						touched = true
						kit.assert_true(mayor.bubble != null and mayor.bubble.visible, "touching a building shows its speech bubble")
					return
			var st := _next_step()
			if st.is_empty():
				step_t = 1.0
				return
			vr_path.clear()
			for c in st[1]:
				vr_path.append(c)
			vr_i = 0
			plan[step] = st
			vr_state = "to_tray"
		"to_tray":
			var kind := String(plan[step][0])
			var tp: Vector3 = mayor.tray_point(kind) + Vector3(0, 0.01, 0)
			if kit.vr_reach(rig, VrRig.RIGHT, tp - palm_off, 2.5, delta):
				kit.vr_trigger(rig, 1.0)
				vr_state = "grabbed"
				step_t = 0.1
		"grabbed":
			if step_t > 0.0:
				return
			if mayor.held == "":
				kit.info("grab failed (%s), retrying later" % String(plan[step][0]))
				vr_state = ""
				step_t = 1.0
				kit.vr_trigger(rig, 0.0)
				return
			if Defs.is_tool_kind(mayor.held):
				kit.vr_trigger(rig, 0.0)  # tools stay in the hand
			vr_state = "carry"
		"carry":
			var c: Vector2i = vr_path[vr_i]
			var s := 1 if Defs.is_tool_kind(mayor.held) else Defs.size_of(mayor.held)
			var target := Defs.foot_center(c.x, c.y, s) + Vector3(0, 0.05, 0)
			if kit.vr_reach(rig, VrRig.RIGHT, target - palm_off, 2.0 if vr_i == 0 else 0.6, delta):
				if Defs.is_tool_kind(mayor.held):
					kit.vr_trigger(rig, 1.0)
					vr_i += 1
					if vr_i >= vr_path.size():
						vr_state = "release"
						step_t = 0.1
				else:
					kit.vr_trigger(rig, 0.0)
					vr_state = "release"
					step_t = 0.2
		"release":
			if step_t > 0.0:
				return
			kit.vr_trigger(rig, 0.0)
			if mayor.held != "":
				kit.vr_a(rig, true)  # put the tool back
				get_tree().create_timer(0.1).timeout.connect(func() -> void: kit.vr_a(rig, false))
			placed += 1
			step += 1
			vr_state = ""
			step_t = 0.4


# --- Drivers ------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.phase() != "play":
		return
	for slot in main.party.local_slots():
		if slot >= 1:
			_drive(slot, delta)


func _drive(slot: int, delta: float) -> void:
	var v: Node3D = main.fleet.vehicle_of(slot)
	if v == null:
		return
	var card: Array = main.net.state_get("job%d" % slot, [])
	if card.size() < 8:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	var target := Vector3(Defs.dq(int(card[4])), Defs.GROUND_Y, Defs.dq(int(card[5])))
	var p: Dictionary = paths.get(slot, {"t": 0.0, "path": [] as Array[Vector2i], "i": 0, "goal": Vector3.INF})
	p["t"] = float(p["t"]) - delta
	if float(p["t"]) <= 0.0 or (p["goal"] as Vector3).distance_to(target) > 0.01:
		p["t"] = 1.0
		p["goal"] = target
		p["path"] = main.town.find_path(Defs.world_cell(v.position), Defs.world_cell(target))
		p["i"] = 0
	paths[slot] = p
	var path: Array[Vector2i] = p["path"]
	var aim := target
	var i := int(p["i"])
	while i < path.size():
		var cp := Defs.cell_center(path[i].x, path[i].y)
		if Vector2(cp.x - v.position.x, cp.z - v.position.z).length() < Defs.CELL * 0.45:
			i += 1
			continue
		aim = cp
		break
	p["i"] = i
	var d := aim - v.position
	d.y = 0.0
	var stick := Vector2.ZERO
	if d.length() > Defs.CELL * 0.15:
		d = d.normalized()
		var cam: Camera3D = main.view_camera(slot)
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		stick = Vector2(d.dot(r), -d.dot(f))
		if i >= path.size():
			stick *= 0.6
	kit.slot_stick(main.party, slot, "left", stick)


# --- Checks -------------------------------------------------------------------------------------------

func _save_reload() -> void:
	var town = main.town
	var n: int = town.buildings.size()
	var roads := 0
	for i in town.lay.size():
		roads += 1 if town.lay[i] != Defs.L_NONE else 0
	var coins: int = main.sim.coins
	var isl: int = main.island
	main.save_town()
	main.save.save_now()
	main.save.reload()
	main.island = -1
	main.town.clear()
	main.load_island(isl)
	var roads2 := 0
	for i in main.town.lay.size():
		roads2 += 1 if main.town.lay[i] != Defs.L_NONE else 0
	kit.assert_eq(main.town.buildings.size(), n, "the town reloads with all %d buildings" % n)
	kit.assert_eq(roads2, roads, "the town reloads with all its roads")
	kit.assert_eq(main.sim.coins, coins, "the coins reload")


func _report() -> String:
	var built := 0
	for id in main.town.buildings:
		if int(main.town.buildings[id]["stage"]) >= 1:
			built += 1
	var veh: Dictionary = main.fleet.vehicles
	var extra := ""
	if main.sim != null:
		extra = " deliveries %d loads %d passengers %d fires %d" % [int(main.sim.counters["deliveries"]), int(main.sim.counters["loads"]),
			int(main.sim.counters["passengers"]), int(main.sim.counters["fires"])]
	return "BOT %s %s: players %s, buildings %d (built %d), pop %d, coins %d, tier %d, vehicles %d, step %d/%d%s" % [main.net.mode,
		main.phase(), str(main.party.active_slots()), main.town.buildings.size(), built, int(main.net.state_get("pop", 0)),
		int(main.net.state_get("coins", 0)), int(main.net.state_get("tier", 0)), veh.size(), step, plan.size(), extra]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if not host:
		kit.assert_eq(main.party.player_count(), want, "%s: all %d players are seated" % [mode, want])
	kit.assert_true(main.town.buildings.size() >= 8, "%s: the mayor built a town (%d buildings)" % [mode, main.town.buildings.size()])
	var veh: Dictionary = main.fleet.vehicles
	kit.assert_true(veh.size() >= 4, "%s: vehicles drive about (%d)" % [mode, veh.size()])
	for s in main.party.local_slots():
		if s >= 1:
			kit.assert_true(main.fleet.vehicle_of(s) != null, "%s: P%d has a vehicle" % [mode, s + 1])
	if client:
		var lay := 0
		for i in main.town.lay.size():
			lay += 1 if main.town.lay[i] != Defs.L_NONE else 0
		kit.assert_true(lay > 10, "TV machine: the roads arrived (%d)" % lay)
		return
	kit.assert_true(int(main.sim.pop) >= Defs.TIER_POP[1], "the town grew past the first milestone (pop %d)" % int(main.sim.pop))
	kit.assert_true(int(main.sim.tier) >= 1, "the town became a VILLAGE")
	kit.assert_true(int(main.sim.counters["loads"]) > 0, "the crane brought bricks")
	kit.assert_true(int(main.sim.counters["deliveries"]) > 0, "trucks delivered food")
	kit.assert_true(int(main.sim.counters["fires"]) > 0, "the fire was put out")
	var player_jobs := 0
	for st in ["deliveries", "loads", "passengers", "fires", "helps", "visits"]:
		player_jobs += int(main.awards.total(st))
	if not host:
		kit.assert_true(player_jobs > 0, "bot drivers finished jobs (%d)" % player_jobs)
	if main.vr_rig != null:
		kit.assert_true(placed >= 6, "the fake VR mayor placed blocks from the tray (%d)" % placed)
