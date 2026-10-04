extends Node
## The TV side's HUD and menus (every TV view gets its own UiKit root):
## - a town card (coins, citizens, happiness, town size) and the island's goals on every view
## - drivers: a job card (what to do, where) with an arrow pointing the way, plus a glowing ring at
##   the target that only their own view shows (town_view markers)
## - the flat mayor (local play, slot 0): the picked building, its price and what's under the cursor
## - menus: island select (title card), vehicle pick per driver
## - the TV machine also draws the VR mayor's held piece as a ghost on the board.
## SIMPLE_MODE: no numbers, no goals, no words on the job card (just the arrow; the glowing ring in the
## world shows where), no vehicle menu (each driver gets the next free toy vehicle, X swaps it).

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiMenu := preload("res://core/ui_menu.gd")

const VEHICLE_ICONS := {"truck": "bag", "bus": "person", "fire": "fire", "crane": "plus", "police": "shield"}

var main: Node
var views := {}  ## slot -> Dictionary of controls (slot -1 = the shared view)
var select_menu: Control
var select_slot := -99
var title_card: Control
var vehicle_menus := {}  ## slot -> UiMenu
var _ghost: MeshInstance3D
var _ghost_key := ""
var _no_veh_t := {}  ## slot -> seconds without a vehicle (the pick menu opens after a moment)


func setup(p_main: Node) -> void:
	main = p_main


func root_of(slot: int) -> Control:
	var v: Dictionary = views.get(slot, {})
	return v.get("root", null)


func all_roots() -> Array:
	var out: Array = []
	for k in views:
		var r: Control = views[k].get("root", null)
		if r != null and is_instance_valid(r):
			out.append(r)
	return out


func menu_open(slot: int) -> bool:
	return UiMenu.slot_busy(slot)


# --- Building the views ------------------------------------------------------------------------------

func make_view(slot: int, parent: Control) -> void:
	remove_view(slot)
	var ui := UiKit.ui_root(parent)
	var v := {"root": ui}
	views[slot] = v
	# town card, top left
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(20.0, 16.0)
	card.visible = not Defs.SIMPLE_MODE
	var row := UiKit.hbox()
	card.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(main.party.name_of(slot), slot))
	row.add_child(UiKit.icon("coin", "gold", 30.0))
	v["coins"] = UiKit.label("0", "number")
	row.add_child(v["coins"])
	row.add_child(UiKit.icon("person", "info", 30.0))
	v["pop"] = UiKit.label("0", "number")
	row.add_child(v["pop"])
	row.add_child(UiKit.icon("heart", "bad", 28.0))
	v["happy"] = UiKit.label("60%", "body")
	row.add_child(v["happy"])
	v["tier"] = UiKit.badge("HAMLET", "accent")
	row.add_child(v["tier"])
	# goals, top right
	var gcard := UiKit.panel("card")
	ui.add_child(gcard)
	gcard.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gcard.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	gcard.offset_left = -20.0
	gcard.offset_right = -20.0
	gcard.offset_top = 16.0
	var gbox := UiKit.vbox(4)
	gcard.add_child(gbox)
	v["goals_card"] = gcard
	v["goals"] = gbox
	if slot >= 1:
		_make_job_card(ui, v)
	elif slot == 0:
		_make_piece_card(ui, v)
	else:
		var jp := UiKit.panel("pill")
		jp.add_child(UiKit.prompts([["A", "Join" if Defs.SIMPLE_MODE else "Join and drive a vehicle"]]))
		ui.add_child(jp)
		jp.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		jp.grow_horizontal = Control.GROW_DIRECTION_BOTH
		jp.grow_vertical = Control.GROW_DIRECTION_BEGIN
		jp.offset_top = -60.0
		jp.offset_bottom = -60.0
		v["join"] = jp
	refresh()


func _make_job_card(ui: Control, v: Dictionary) -> void:
	var jc := UiKit.panel("card")
	ui.add_child(jc)
	jc.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	jc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	jc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	jc.offset_top = -24.0
	jc.offset_bottom = -24.0
	var row := UiKit.hbox(14)
	jc.add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(64.0, 64.0)
	row.add_child(holder)
	var arrow := UiKit.icon("arrow_up", "gold", 60.0)
	holder.add_child(arrow)
	arrow.position = Vector2(2.0, 2.0)
	arrow.pivot_offset = Vector2(30.0, 30.0)
	var col := UiKit.vbox(2)
	row.add_child(col)
	col.visible = not Defs.SIMPLE_MODE  # SIMPLE_MODE: just the arrow
	var title := UiKit.label("", "heading", "gold")
	col.add_child(title)
	var line := UiKit.label("", "body")
	col.add_child(line)
	v["job"] = jc
	v["arrow"] = arrow
	v["job_title"] = title
	v["job_line"] = line
	v["job_key"] = ""


func _make_piece_card(ui: Control, v: Dictionary) -> void:
	var pc := UiKit.panel("card")
	ui.add_child(pc)
	pc.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.offset_top = -20.0
	pc.offset_bottom = -20.0
	var col := UiKit.vbox(4)
	pc.add_child(col)
	var title := UiKit.label("", "heading", "gold", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(title)
	var line := UiKit.label("", "small", null, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(line)
	var info := UiKit.label("", "small", "info", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(info)
	if Defs.SIMPLE_MODE:
		title.visible = false  # the ghost on the cursor shows the block: one line of buttons only
		line.visible = false
		info.visible = false
		col.add_child(UiKit.prompts([["LB", ""], ["RB", "Pick"], ["A", "Build"]]))
	else:
		col.add_child(UiKit.prompts([["LB", ""], ["RB", "Pick"], ["A", "Build"], ["X", "Turn"], ["B", "Bulldozer"], ["SELECT", "Islands"]]))
	v["piece"] = pc
	v["piece_title"] = title
	v["piece_line"] = line
	v["piece_info"] = info
	v["piece_key"] = ""


func remove_view(slot: int) -> void:
	if vehicle_menus.has(slot):
		var m: Node = vehicle_menus[slot]
		if is_instance_valid(m):
			m.queue_free()
		vehicle_menus.erase(slot)
	if select_slot == slot and select_menu != null and is_instance_valid(select_menu):
		select_menu.queue_free()
		select_menu = null
		select_slot = -99
	if views.has(slot):
		var r: Control = views[slot].get("root", null)
		if r != null and is_instance_valid(r):
			r.queue_free()
		views.erase(slot)
	if slot >= 1 and main.view != null:
		main.view.call("set_marker", slot, Vector3.ZERO, Color.WHITE, false)


# --- Refresh -------------------------------------------------------------------------------------------

func refresh() -> void:
	var net: Node = main.net
	var coins := int(net.state_get("coins", 0))
	var pop := int(net.state_get("pop", 0))
	var happy := int(net.state_get("happy", 60))
	var tier := clampi(int(net.state_get("tier", 0)), 0, Defs.TIERS.size() - 1)
	var goals: Array = net.state_get("goals", [])
	for slot in views:
		var v: Dictionary = views[slot]
		var r: Control = v.get("root", null)
		if r == null or not is_instance_valid(r):
			continue
		(v["coins"] as Label).text = "%d" % coins if not bool(net.state_get("free", false)) else "FREE"
		(v["pop"] as Label).text = "%d" % pop
		(v["happy"] as Label).text = "%d%%" % happy
		var tb: PanelContainer = v["tier"]
		var tl := tb.find_children("*", "Label", true, false)
		if not tl.is_empty():
			(tl[0] as Label).text = Defs.TIERS[tier]
		_fill_goals(v, goals)
		if v.has("join"):
			(v["join"] as Control).visible = main.party.local_slots().is_empty() or (main.party.local_slots().size() == 1 and main.party.local_slots()[0] == 0)


func _fill_goals(v: Dictionary, goals: Array) -> void:
	var box: VBoxContainer = v["goals"]
	var key := str(goals) + str(main.net.state_get("island", 0))
	if String(v.get("goals_key", "")) == key:
		return
	v["goals_key"] = key
	for c in box.get_children():
		c.queue_free()
	var isl := Defs.island(int(main.net.state_get("island", 0)))
	box.add_child(UiKit.label(String(isl["name"]), "small", "accent"))
	if goals.is_empty():
		box.add_child(UiKit.label("Build anything you like!", "small", "dim"))
	for g in goals:
		var ga: Array = g
		var row := UiKit.hbox(8)
		box.add_child(row)
		var done := bool(ga[3])
		row.add_child(UiKit.icon("check" if done else "star", "good" if done else "dim", 22.0))
		var txt := String(ga[0]) if done else "%s  %d/%d" % [String(ga[0]), int(ga[1]), int(ga[2])]
		row.add_child(UiKit.label(txt, "small", "good" if done else null))
	(v["goals_card"] as Control).visible = not Defs.SIMPLE_MODE


## Every frame: job cards and their arrows, the flat mayor's card, open menus.
func tick(delta: float) -> void:
	for slot in views:
		var v: Dictionary = views[slot]
		var r: Control = v.get("root", null)
		if r == null or not is_instance_valid(r):
			continue
		if v.has("job"):
			_tick_job(int(slot), v)
		if v.has("piece"):
			_tick_piece(v)
	if main.phase() == "select":
		_ensure_select_menu()
	else:
		for slot in main.party.local_slots():
			if slot < 1 or main.fleet.call("vehicle_of", slot) != null or main.party.is_pending(slot):
				_no_veh_t[slot] = 0.0
				continue
			_no_veh_t[slot] = float(_no_veh_t.get(slot, 0.0)) + delta
			if float(_no_veh_t[slot]) > 0.8 and not vehicle_menus.has(slot) and main.phase() == "play":
				if Defs.SIMPLE_MODE:
					main.net.request(slot, "vehicle", [_free_vehicle(slot, "")])
					_no_veh_t[slot] = -1.5  # asks again in a moment if it hasn't arrived
				else:
					open_vehicle_menu(slot)


func _tick_job(slot: int, v: Dictionary) -> void:
	var card: Array = main.net.state_get("job%d" % slot, [])
	var veh: Node3D = main.fleet.call("vehicle_of", slot)
	var jc: Control = v["job"]
	var show: bool = main.phase() == "play" and veh != null
	jc.visible = show
	if not show:
		main.view.call("set_marker", slot, Vector3.ZERO, Color.WHITE, false)
		return
	var arrow: Control = v["arrow"]
	if card.size() < 8:
		(v["job_title"] as Label).text = String(Defs.V.get(String(veh.get("kind")), {}).get("name", "DRIVER"))
		(v["job_line"] as Label).text = "Waiting for the next job... drive about and honk hello!"
		arrow.visible = false
		main.view.call("set_marker", slot, Vector3.ZERO, Color.WHITE, false)
		return
	var key := str(card)
	if String(v["job_key"]) != key:
		v["job_key"] = key
		(v["job_title"] as Label).text = String(card[2])
		(v["job_line"] as Label).text = String(card[3])
		UiKit.pulse(jc, 1.06)
		if int(card[1]) == 0 or String(card[0]) == "fire":
			main.sound("ui_notify", -8.0)
	var target := Vector3(Defs.dq(int(card[4])), Defs.GROUND_Y, Defs.dq(int(card[5])))
	main.view.call("set_marker", slot, target, main.party.color_of(slot), true)
	arrow.visible = true
	var cam: Camera3D = main.view_camera(slot)
	var to := target - veh.global_position
	to.y = 0.0
	if cam == null or to.length() < Defs.CELL * 1.2:
		arrow.rotation = 0.0
		arrow.modulate = Color(0.5, 1.0, 0.5)
		return
	arrow.modulate = Color(1, 1, 1)
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var r := Vector3(-f.z, 0.0, f.x)
	var d := to.normalized()
	arrow.rotation = atan2(d.dot(r), d.dot(f))


func _tick_piece(v: Dictionary) -> void:
	if main.flat == null:
		(v["piece"] as Control).visible = false
		return
	(v["piece"] as Control).visible = main.phase() == "play"
	var info: Array = main.flat.call("info")
	var key := str(info)
	if String(v["piece_key"]) == key:
		return
	v["piece_key"] = key
	(v["piece_title"] as Label).text = String(info[0])
	(v["piece_line"] as Label).text = String(info[1])
	(v["piece_info"] as Label).text = String(info[2])


# --- Phases and menus ------------------------------------------------------------------------------------

func on_phase(p: String) -> void:
	if p == "select":
		_show_title(true)
		for slot in vehicle_menus.keys():
			var m: Node = vehicle_menus[slot]
			if is_instance_valid(m):
				m.queue_free()
		vehicle_menus.clear()
	else:
		_show_title(false)
		if select_menu != null and is_instance_valid(select_menu):
			select_menu.queue_free()
		select_menu = null
		select_slot = -99
	refresh()


func _show_title(on: bool) -> void:
	if title_card != null and is_instance_valid(title_card):
		title_card.queue_free()
		title_card = null
	var root := root_of(-1)
	if not on or root == null:
		return
	title_card = UiKit.panel("accent")
	root.add_child(title_card)
	var v := UiKit.vbox(6)
	title_card.add_child(v)
	v.add_child(UiKit.label("TINY TOWN TYCOON", "banner", "gold", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("A cosy little town, built together", "subtitle", null, HORIZONTAL_ALIGNMENT_CENTER))
	title_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_card.offset_top = 90.0
	UiKit.pop_in(title_card)


func island_items() -> Array:
	var stars: Dictionary = main.net.state_get("stars", {})
	var items: Array = []
	for i in Defs.ISLANDS.size():
		var isl: Dictionary = Defs.ISLANDS[i]
		var got: Array = stars.get(String(isl["id"]), [])
		var n := 0
		for s in got:
			n += 1 if bool(s) else 0
		var goals: Array = isl["goals"]
		var right := "%d / %d STARS" % [n, goals.size()] if not goals.is_empty() else "SANDBOX"
		var lines: PackedStringArray = [String(isl["blurb"])]
		for g in goals:
			lines.append("- " + String((g as Array)[3]))
		items.append({"id": str(i), "text": String(isl["name"]), "desc": "\n".join(lines), "right": right,
			"icon": "star" if n < goals.size() or goals.is_empty() else "trophy", "icon_color": "gold" if n > 0 else "dim"})
	return items


func _ensure_select_menu() -> void:
	if main.split == null:
		return
	var seats: Array[int] = main.party.local_slots()
	if seats.is_empty():
		return
	if select_menu != null and is_instance_valid(select_menu) and select_slot == seats[0]:
		return
	if select_menu != null and is_instance_valid(select_menu):
		select_menu.queue_free()
	var slot := seats[0]
	select_slot = slot
	var m := UiMenu.open(root_of(-1), {"title": "PICK AN ISLAND", "party": main.party, "slot": slot, "items": island_items(),
		"desc": true, "anchor": "center", "start": str(int(main.net.state_get("island", 0))), "width": 560.0})
	m.chosen.connect(func(id: String, _item: Dictionary) -> void: main.net.request(slot, "pick_island", [int(id)]))
	m.focus_changed.connect(func(id: String, _item: Dictionary) -> void: main.net.request(slot, "preview", [int(id)]))
	select_menu = m


## SIMPLE_MODE: the next toy vehicle nobody else is driving (the crane first: it builds).
func _free_vehicle(slot: int, after: String) -> String:
	var taken := {}
	for s in main.party.active_slots():
		var k := String(main.net.state_get("veh%d" % s, ""))
		if k != "" and s != slot:
			taken[k] = true
	var order: Array[String] = ["crane", "truck", "bus", "fire", "police"]
	var start := order.find(after) + 1
	for i in order.size():
		var k2: String = order[(start + i) % order.size()]
		if not taken.has(k2) and k2 != after:
			return k2
	return order[start % order.size()]


## SIMPLE_MODE: X swaps to the next toy vehicle (no menu).
func next_vehicle(slot: int) -> void:
	var mine := String(main.net.state_get("veh%d" % slot, ""))
	if mine == "":
		return
	main.net.request(slot, "vehicle", [_free_vehicle(slot, mine)])
	main.sound("ui_toggle", -6.0)


func open_vehicle_menu(slot: int) -> void:
	if not views.has(slot) or main.phase() != "play":
		return
	if vehicle_menus.has(slot) and is_instance_valid(vehicle_menus[slot]):
		return
	var taken := {}
	for s in main.party.active_slots():
		var k := String(main.net.state_get("veh%d" % s, ""))
		if k != "" and s != slot:
			taken[k] = true
	var mine := String(main.net.state_get("veh%d" % slot, ""))
	var start := mine
	if start == "":
		start = "truck"
		var order: Array[String] = Defs.CORE_FLEET.duplicate()
		order.append("police")
		for k in order:
			if not taken.has(k):
				start = k
				break
	var items: Array = []
	for k in Defs.VEHICLES:
		var d: Dictionary = Defs.V[k]
		items.append({"id": k, "text": String(d["name"]), "desc": String(d["desc"]), "icon": String(VEHICLE_ICONS.get(k, "star")),
			"icon_color": d["color"], "right": "TAKEN" if taken.has(k) else ""})
	var m := UiMenu.open(root_of(slot), {"title": "PICK YOUR VEHICLE", "party": main.party, "slot": slot, "items": items,
		"desc": true, "start": start, "allow_cancel": mine != "", "anchor": "center"})
	m.chosen.connect(func(id: String, _item: Dictionary) -> void:
		main.net.request(slot, "vehicle", [id])
		main.hints.hint("drive_%d" % slot, "Follow the arrow and drive into the glowing ring!", {"to": slot, "icon": "arrow_up"}))
	m.closed.connect(func() -> void: vehicle_menus.erase(slot))
	vehicle_menus[slot] = m


# --- The VR mayor's ghost, drawn on the TV machine ------------------------------------------------------

func mayor_ghost(a: PackedInt32Array) -> void:
	if a.size() < 5:
		if _ghost != null:
			_ghost.visible = false
		return
	var kind := Defs.kind_at(a[0])
	if kind == "":
		return
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(_ghost)
	var ok := a[4] != 0
	var key := "%s_%d" % [kind, 1 if ok else 0]
	if key != _ghost_key:
		_ghost_key = key
		if Defs.is_tool_kind(kind):
			var bm := BoxMesh.new()
			bm.size = Vector3(1.0, 0.04, 1.0)
			_ghost.mesh = bm
		else:
			_ghost.mesh = Art.building_mesh(kind, 0, 1, false)
		_ghost.material_override = Art.ghost_mat(Color(0.4, 1.0, 0.5, 0.45) if ok else Color(1.0, 0.35, 0.3, 0.45))
	var s := Defs.size_of(kind) if not Defs.is_tool_kind(kind) else 1
	var c := Defs.foot_center(a[1], a[2], s)
	_ghost.transform = Transform3D(Basis(Vector3.UP, a[3] * PI * 0.5).scaled(Vector3.ONE * Defs.CELL), c + Vector3(0, 0.001, 0))
	_ghost.visible = true
