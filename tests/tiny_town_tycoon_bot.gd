extends Node
## Headless bot for games/tiny_town_tycoon. The mayor (a fake-VR glove with BOT_VR=1, else the flat
## cursor mayor in slot 0) lays out roads and buildings from the tray; TV bot drivers pick vehicles
## and follow their job arrows (A* along the town's roads) to deliver, build and put out a fire. The
## town should grow past its first milestone (TT_FAST=1), then the town is saved and reloaded.
## Local:     TT_FAST=1 godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/tiny_town_tycoon_bot.tscn
## Networked: DUO_PORT=8070 DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=8070 DUO_JOIN=127.0.0.1 BOT_PLAYERS=3 ...
## SIMPLE_MODE (Defs.SIMPLE_MODE): no island select, events, goals or results; the mayor does the
## practice first (road from the glowing spot, then the house beside it), new blocks unlock one at a
## time, drivers get a vehicle without a menu and bring the bricks, and the fake VR glove touches the
## toys (clouds, balloon, windmill, sheep, a house) and picks a tree up and replants it.
## VISUAL TEACHING (SIMPLE_MODE): records the picture cues (cue_move, cue_pick_*, cue_build_*, cue_drive,
## cue_plug, cue_learned_*), the glowing arrows (spot_arrow, tray_arrow), the ghost hand and the join
## cue; unplugs and replugs P2's pad in local mode (bolt), checks the pause banner is just PAUSED (and
## not drawn under the pause menu's own PAUSED), checks a seat's cues reset when its player leaves, and
## prints BOT: ERROR on how-to text anywhere in the game's HUD / VR text (BOT_VR=1: the fake-VR mayor).

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
var simple := Defs.SIMPLE_MODE
var toy_list: Array = []  ## SIMPLE_MODE VR: toys still to touch
var tree_state := ""  ## SIMPLE_MODE VR: "", "grab", "carry", "done"
var tree_from := -1
var saw_complete := false
var toys_started := false
var toy_wait := 0.0
var seen := {}  ## SIMPLE_MODE: cues / arrows seen on this machine
var bad_text := {}  ## SIMPLE_MODE: how-to text found (reported once each)
var unplug_dev := -1
var unplug_slot := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	BotKit.vr_host_plays()  # a networked VR host (not a flat one) without a headset: the fake VR mayor plays
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
	if not host and BotKit.lead_machine():
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
			if simple:
				kit.assert_true(get_tree().paused and main.tv_banner != null, "Start pauses")
				kit.assert_true(main.pause_menu.panel.visible and not main.tv_banner.visible,
					"SIMPLE: the pause menu says PAUSED once (no second PAUSED banner under it)")
				_check_pause_banner()
			else:
				kit.assert_true(get_tree().paused and main.tv_banner != null and main.tv_banner.visible, "Start pauses and shows the banner")
			_press_any("start"))
		kit.at(t0 + 13.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes")
			kit.allow_pause = false)
	if not client and not simple:
		kit.at(30.0, "a small fire breaks out", func() -> void:
			kit.assert_true(main.debug_event("fire"), "a fire started"))
		kit.at(20.0, "a festival (if there's a park)", func() -> void: main.debug_event("festival"))
	if not client and not simple:
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
	if simple:
		kit.every(0.1, _record)
		kit.every(0.5, _scan_text)
		_simple_timeline()


func _join() -> void:
	if host:
		# A flat host (TV / Deck hosting, no headset): slot 0 is the mayor's seat on this machine, so someone
		# here presses A to be the flat mayor (the drivers are on the joining machines). A headset host needs nobody.
		if not main.net.has_vr:
			kit.join_bot(main.party)
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
	if main.phase() == "complete":
		saw_complete = true
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
	if simple:
		var pr: Array[Vector2i] = []
		for c in main.practice_road:
			pr.append(c)
		kit.assert_true(pr.size() == 3, "SIMPLE: the practice starts with a road to draw from a glowing spot")
		plan.clear()
		plan.append(["road", pr])
		plan.append(["practice_house", []])
		plan.append(["road", row])
		plan.append(["road", col])
		for k in ["house", "house", "farm", "house", "park", "house", "windmill", "house", "house", "shop", "house", "house", "water",
				"house", "bakery", "house", "house", "school"]:
			plan.append([String(k), []])
		kit.info("plan: %d steps" % plan.size())
		return
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
	if get_tree().paused:
		return  # the mayor's A presses would press the pause menu's highlighted button (Resume) now
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
		if kind == "practice_house":
			if main.practice != 1:
				if main.practice >= 2:
					step += 1
					continue
				return []
			return ["house", [main.practice_house]]
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
			if simple and placed >= 6 and orbit_t >= 2.5 and _vr_toys(delta):
				return
			kit.vr_trigger(rig, 0.0)
			if step_t > 0.0 or orbit_t < 2.5:
				return
			# touch a house with the left glove once (speech bubble)
			if not touched and placed >= 6 and not simple:
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


## SIMPLE_MODE: the left glove touches each toy once, then the right hand moves a tree. True while busy.
func _vr_toys(delta: float) -> bool:
	var rig = main.vr_rig
	var props = main.props
	if props == null:
		return false
	if toy_list.is_empty() and not toys_started:
		toys_started = true
		toy_list = ["cloud", "balloon", "windmill", "sheep", "building"]
	if not toy_list.is_empty():
		var what := String(toy_list[0])
		var at := Vector3.ZERO
		if what == "building":
			var houses: Array = main.town.of_kind("house", false)
			if houses.is_empty():
				toy_list.pop_front()
				return true
			at = main.town.center_of(houses[0]) + Vector3(0, 0.025, 0)
		else:
			at = props.bot_targets()[what]
		var lo: Vector3 = rig.hand_point(VrRig.LEFT) - rig.hand(VrRig.LEFT).global_position
		if kit.vr_reach(rig, VrRig.LEFT, at - lo, 3.0, delta) or props.touched.has(what):
			toy_wait += delta
			if not props.touched.has(what) and toy_wait < 0.6:
				return true  # give the toys a frame or two to feel the glove
			kit.assert_true(props.touched.has(what), "SIMPLE: touching the %s makes it react" % what)
			toy_wait = 0.0
			toy_list.pop_front()
			rig.hand_l.position = Vector3(-0.45, 0.7, 0.25)
		return true
	if tree_state == "done":
		return false
	var po: Vector3 = rig.hand_point(VrRig.RIGHT) - rig.hand(VrRig.RIGHT).global_position
	match tree_state:
		"":
			# the tree nearest the player
			var best := -1
			var bd := INF
			for i in main.town.trees.size():
				if main.town.trees[i] > 0:
					var c := Defs.cell_center(i % Defs.GRID, i / Defs.GRID)
					var d := c.distance_to(rig.camera.global_position)
					if d < bd:
						bd = d
						best = i
			if best < 0:
				tree_state = "done"
				return false
			tree_from = best
			tree_state = "grab"
		"grab":
			var c2 := Defs.cell_center(tree_from % Defs.GRID, tree_from / Defs.GRID) + Vector3(0, 0.02, 0)
			if kit.vr_reach(rig, VrRig.RIGHT, c2 - po, 2.0, delta):
				kit.vr_trigger(rig, 1.0)
				tree_state = "carry"
				step_t = 0.2
		"carry":
			if step_t > 0.0:
				return true
			if not props.holding():
				kit.info("tree grab failed")
				kit.vr_trigger(rig, 0.0)
				tree_state = "done"
				return false
			# a free grass cell a little way off
			var to := Vector2i(-1, -1)
			var fc := Vector2i(tree_from % Defs.GRID, tree_from / Defs.GRID)
			for r in range(2, 6):
				for d2 in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
					var cc: Vector2i = fc + d2
					if to.x < 0 and Defs.inside(cc.x, cc.y) and props.can_plant(cc.x, cc.y) and main.town.trees[cc.x + cc.y * Defs.GRID] == 0:
						to = cc
			if to.x < 0:
				to = fc
			var target := Defs.cell_center(to.x, to.y) + Vector3(0, 0.03, 0)
			if kit.vr_reach(rig, VrRig.RIGHT, target - po, 1.5, delta):
				kit.vr_trigger(rig, 0.0)
				tree_state = "done"
				get_tree().create_timer(0.3).timeout.connect(func() -> void:
					kit.assert_true(props.touched.has("tree_grab") and not props.holding(), "SIMPLE: the right hand picked a tree up and let it go")
					kit.assert_true(int(main.town.trees[to.x + to.y * Defs.GRID]) > 0, "SIMPLE: the tree was replanted where it was put"))
	return true


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


# --- SIMPLE_MODE: visual teaching ---------------------------------------------------------------------

func _simple_timeline() -> void:
	if not client:
		# the flat mayor (local, or on a flat host) picks blocks with RB / LB
		kit.at(26.0, "the flat mayor presses RB", func() -> void:
			if main.flat != null:
				kit.slot_press(main.party, 0, "rb"))
		kit.at(26.5, "the flat mayor presses LB", func() -> void:
			if main.flat != null:
				kit.slot_press(main.party, 0, "lb"))
	if host or client:
		return
	kit.at(20.0, "P2's controller is unplugged (bolt)", func() -> void:
		for sl in main.party.local_slots():
			if sl >= 1 and main.party.device_of(sl) >= 0:
				unplug_slot = sl
				unplug_dev = main.party.device_of(sl)
				main.party.remove_virtual_pad(unplug_dev)
				return)
	kit.at(21.0, "bolt?", func() -> void:
		if unplug_slot < 0:
			return
		kit.assert_true(main.party.is_lost(unplug_slot), "SIMPLE: P%d's controller is away" % (unplug_slot + 1))
		kit.assert_eq(String(main.hud.views[unplug_slot]["cue"].key), "plug", "SIMPLE: a pulsing bolt shows in P%d's view" % (unplug_slot + 1))
		main.party.replug_virtual_pad(unplug_dev))
	kit.at(22.0, "bolt gone?", func() -> void:
		if unplug_slot < 0:
			return
		kit.assert_true(not main.party.is_lost(unplug_slot), "SIMPLE: the controller is back")
		kit.assert_true(String(main.hud.views[unplug_slot]["cue"].key) != "plug", "SIMPLE: the bolt goes when it's back"))
	kit.at(24.0, "the VR player pauses (banner on the TV)", func() -> void:
		main.on_pause_changed(true, 0)
		kit.assert_true(main.tv_banner != null and main.tv_banner.visible, "SIMPLE: a pause from the other machine shows the PAUSED banner")
		_check_pause_banner()
		main.on_pause_changed(false, 0))
	kit.drop_in_out(main.party, 30.0, 6.0, func(sl: int) -> bool: return main.hud.views.has(sl))
	kit.at(37.5, "the late player's cues were forgotten?", func() -> void:
		for sl in main.cue_done:
			kit.assert_true(int(sl) == 0 or main.party.is_active(int(sl)), "SIMPLE: a seat's cues reset when its player leaves (P%d)" % (int(sl) + 1)))


## The pause banner says PAUSED and nothing else.
func _check_pause_banner() -> void:
	if main.tv_banner == null:
		return
	var words: Array[String] = []
	for l in main.tv_banner.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text != "":
			words.append((l as Label).text)
	if main.tv_banner.visible:
		kit.assert_true(words == ["PAUSED"], "SIMPLE: the pause banner is just PAUSED (%s)" % str(words))


func _see(what: String) -> void:
	if not seen.has(what):
		seen[what] = true
		kit.info("saw %s" % what)


## Every 0.1 s: which cues, arrows and hands are showing on this machine.
func _record() -> String:
	if main == null or not main.ready_to_play or main.hud == null:
		return ""
	for sl in main.hud.views:
		var v: Dictionary = main.hud.views[sl]
		if v.has("cue"):
			for k in v["cue"].shown:
				_see("cue_" + String(k))
		if v.has("join") and (v["join"] as Control).is_visible_in_tree():
			_see("join_cue")
	for sl in main.cue_done:
		for k in main.cue_done[sl]:
			if main.cue_learned(int(sl), String(k)):
				_see("cue_learned_" + String(k))
	if main.spot_arrow != null and main.spot_arrow.visible and main.practice < 2:
		_see("spot_arrow")
	if main.tray_arrow != null and main.tray_arrow.visible and main.tray_arrow_kind != "":
		_see("tray_arrow_" + String(main.tray_arrow_kind))
	if main.ghost_hand != null and main.ghost_hand.shown:
		_see("ghost_hand")
	return ""


## How-to words: a sentence (3+ words or lower-case words) or a known instruction word.
func _is_instruction(t: String) -> bool:
	var txt := t.strip_edges()
	if txt == "":
		return false
	for w in ["Join", "Pick", "Build", "Paused by", "Start:", "menu", "drive", "Drive", "Press", "Hold", "Follow"]:
		if txt.contains(w):
			return true
	var re := RegEx.create_from_string("[a-z]{2,}")
	if re.search(txt) != null:
		return true
	return txt.split(" ", false).size() >= 3


## Every 0.5 s: no how-to text in the game's HUD or VR text (the core pause menu is not the game's).
func _scan_text() -> String:
	if main == null or not main.ready_to_play:
		return ""
	var nodes: Array = main.find_children("*", "Label", true, false)
	nodes.append_array(main.find_children("*", "Label3D", true, false))
	nodes.append_array(main.find_children("*", "RichTextLabel", true, false))
	for n in nodes:
		if main.pause_menu != null and main.pause_menu.is_ancestor_of(n):
			continue
		if not (n as Node).call("is_visible_in_tree"):
			continue
		var t := String(n.get("text"))
		if _is_instruction(t) and not bad_text.has(t):
			bad_text[t] = true
			printerr("BOT: ERROR: how-to text in SIMPLE_MODE: \"%s\" (%s)" % [t, str(main.get_path_to(n))])
			kit.assert_true(false, "SIMPLE: no how-to text (\"%s\")" % t)
	return ""


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
		kit.assert_eq(kit.seated(), kit.seated_want(want), "%s: all %d players are seated" % [mode, want])
	kit.assert_true(main.town.buildings.size() >= 8, "%s: the mayor built a town (%d buildings)" % [mode, main.town.buildings.size()])
	var veh: Dictionary = main.fleet.vehicles
	kit.assert_true(veh.size() >= 4, "%s: vehicles drive about (%d)" % [mode, veh.size()])
	for s in main.party.local_slots():
		if s >= 1:
			kit.assert_true(main.fleet.vehicle_of(s) != null, "%s: P%d has a vehicle" % [mode, s + 1])
	if simple:
		_cue_checks()
	if client:
		var lay := 0
		for i in main.town.lay.size():
			lay += 1 if main.town.lay[i] != Defs.L_NONE else 0
		kit.assert_true(lay > 10, "TV machine: the roads arrived (%d)" % lay)
		return
	if simple:
		_simple_checks()
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


## SIMPLE_MODE: the picture cues and arrows this machine should have shown.
func _cue_checks() -> void:
	kit.info("cues seen: %s" % str(seen.keys()))
	var drivers := false
	for sl in main.party.local_slots():
		drivers = drivers or sl >= 1
	if drivers:
		kit.assert_true(seen.has("cue_drive"), "SIMPLE: a driver saw STICK + car + glowing ring")
		kit.assert_true(seen.has("cue_learned_drive"), "SIMPLE: a driver's drive cue went after two deliveries")
	if main.flat != null:
		kit.assert_true(seen.has("cue_move") or seen.has("cue_build_road"), "SIMPLE: the flat mayor saw a move / build cue")
		kit.assert_true(seen.has("cue_build_road") or seen.has("cue_build_house"), "SIMPLE: the flat mayor saw A + a block + the ring")
		kit.assert_true(seen.has("cue_pick_house"), "SIMPLE: the flat mayor saw RB + the house to pick")
		kit.assert_true(seen.has("cue_learned_build"), "SIMPLE: the build cue went after two builds")
		kit.assert_true(seen.has("cue_learned_pick"), "SIMPLE: the pick cue went after LB / RB twice")
	if main.flat != null or main.mayor != null:
		kit.assert_true(seen.has("spot_arrow"), "SIMPLE: a glowing arrow showed where to build")
	if main.mayor != null:
		kit.assert_true(seen.has("tray_arrow_road") and seen.has("tray_arrow_house"), "SIMPLE: a glowing arrow showed which tray block to grab")
		kit.assert_true(seen.has("cue_learned_grab"), "SIMPLE: the VR mayor grabbed blocks twice")
	if not host and not client:
		kit.assert_true(unplug_slot < 0 or seen.has("cue_plug"), "SIMPLE: the bolt showed for an unplugged pad")
	kit.assert_true(bad_text.is_empty(), "SIMPLE: no how-to text on this machine")


func _simple_checks() -> void:
	kit.assert_true(int(main.sim.pop) >= 8, "SIMPLE: people moved into the houses (pop %d)" % int(main.sim.pop))
	kit.assert_true(int(main.sim.unl) >= 4, "SIMPLE: new blocks joined the tray one at a time (%d unlocked)" % int(main.sim.unl))
	kit.assert_true(int(main.sim.counters["loads"]) > 0, "SIMPLE: bricks were brought to new buildings")
	kit.assert_true(not saw_complete, "SIMPLE: no island-complete awards screen")
	kit.assert_true((main.net.state_get("ev", {}) as Dictionary).is_empty(), "SIMPLE: no events with text banners")
	if main.mayor != null or main.flat != null:
		kit.assert_eq(int(main.practice), 2, "SIMPLE: the mayor finished the practice (a road, then a house beside it)")
	if main.mayor != null:
		kit.assert_true(main.ghost_hand.shown, "SIMPLE: the ghost hand showed the mayor how to build")
		kit.assert_true(main.mayor.board == null, "SIMPLE: no mayor's board of numbers in VR")
		for s in main.mayor.slots:
			kit.assert_true(Defs.SIMPLE_TRAY.find(String(s["kind"])) < int(main.sim.unl), "SIMPLE: the tray only holds unlocked blocks (%s)" % String(s["kind"]))
		kit.assert_true(toys_started and toy_list.is_empty(), "SIMPLE: the glove went round the toys")
	var player_jobs := 0
	for st in ["deliveries", "loads", "passengers", "fires", "helps", "visits"]:
		player_jobs += int(main.awards.total(st))
	if not host:
		kit.assert_true(player_jobs > 0, "bot drivers finished jobs (%d)" % player_jobs)
		kit.assert_true(int(main.awards.total("loads")) > 0, "SIMPLE: a driver brought bricks (the glowing delivery)")
	if main.vr_rig != null:
		kit.assert_true(placed >= 6, "the fake VR mayor placed blocks from the tray (%d)" % placed)
