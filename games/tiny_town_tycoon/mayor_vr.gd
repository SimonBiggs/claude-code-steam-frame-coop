extends Node3D
## The VR mayor's tools (host with a headset, or BOT_VR=1):
## - a BUILD TRAY beside the right hand (never towards the face) with every building block; locked
##   blocks are grey with the town size that unlocks them, the ISLANDS sign goes back to island select
## - grab a block with the right trigger, hold it over the island: a ghost shows where it goes (green =
##   fine, red = not there) and turns to face the nearest road; twist the hand (or press A) to turn
##   it; let go to place it (a blueprint the crane builds)
## - roads, rails and the bulldozer are tools: they stay in the hand; hold the trigger and draw over
##   the island; touch the tray (or press A) to put them back
## - touch a building with either glove: a speech bubble says what it needs
## - the MAYOR'S BOARD (left, far enough to read comfortably) shows coins, citizens, the town size
##   and the island's goals
## - the right stick turns the table (the rig orbits round it), the left stick walks round it.
## The tray and board are world-locked and glide after the player only when they walk or turn away.
## SIMPLE_MODE: the tray holds only what's unlocked (ROAD + HOUSE at first), as little models with no
## words; a new block arrives with a sparkle. No board, no ISLANDS sign, no bulldozer, no speech bubbles
## (touching things makes them react instead: props.gd), and a "not there" is just a buzz.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const Sim := preload("res://games/tiny_town_tycoon/sim.gd")
const VrRig := preload("res://core/vr_rig.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const VrMenu := preload("res://core/vr_menu.gd")

const COLS := 6
const PITCH := 0.07  ## tray spacing (metres)
const PIECE := 0.046  ## a tray block's size
const GRAB_R := 0.055
const TRAY_OFFSET := Vector3(0.36, 0.0, -0.2)  ## from the player's feet, in their facing frame
const BOARD_OFFSET := Vector3(-0.52, 0.0, -0.62)
const TWIST_STEP := PI / 3.0

var main: Node
var rig: VrRig
var town: Town
var station: Node3D  ## follows the player lazily; holds the tray and the board
var tray: Node3D
var slots: Array[Dictionary] = []  ## {kind, node, piece, base, label}
var board: Node3D
var board_title: Label3D
var board_stats: Label3D
var board_goals: Label3D
var held := ""
var held_mi: MeshInstance3D
var ghost: MeshInstance3D
var ghost_on := false
var ghost_ok := false
var ghost_cell := Vector2i(-99, -99)
var ghost_why := ""
var rot := 0
var manual := false
var roll0 := 0.0
var rot0 := 0
var paint_last := Vector2i(-99, -99)
var bubble: Node3D
var bubble_title: Label3D
var bubble_body: Label3D
var bubble_id := 0
var bubble_t := 0.0
var island_menu: Node
var hover := -1
var _nope_t := 0.0
var _st_moving := true
var _snow := false
var _tray_key := ""
var _sparkle_kind := ""
var _sparkle_t := 0.0


func setup(p_main: Node, p_rig: VrRig, p_town: Town) -> void:
	main = p_main
	rig = p_rig
	town = p_town
	station = Node3D.new()
	station.name = "Station"
	add_child(station)
	tray = Node3D.new()
	tray.name = "Tray"
	station.add_child(tray)
	tray.position = TRAY_OFFSET
	_build_tray()
	_build_board()
	ghost = MeshInstance3D.new()
	ghost.name = "Ghost"
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)
	held_mi = MeshInstance3D.new()
	held_mi.name = "Held"
	held_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	held_mi.visible = false
	add_child(held_mi)


# --- Tray and board ---------------------------------------------------------------------------------

func _tray_kinds() -> Array[String]:
	var out: Array[String] = []
	if Defs.SIMPLE_MODE:
		var n := clampi(int(main.net.state_get("unl", 2)), 2, Defs.SIMPLE_TRAY.size())
		for i in n:
			out.append(Defs.SIMPLE_TRAY[i])
		return out
	for k in Defs.TRAY:
		out.append(k)
	out.append("islands")
	return out


func _build_tray() -> void:
	for c in tray.get_children():
		c.queue_free()
	slots.clear()
	hover = -1
	var kinds := _tray_kinds()
	var rows := int(ceil(kinds.size() / float(COLS)))
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(COLS * PITCH + 0.03, 0.012, rows * PITCH + 0.03)
	back.mesh = bm
	back.material_override = MeshKit.material(Color(0.55, 0.38, 0.24))
	back.position = Vector3(0, -0.012, 0)
	tray.add_child(back)
	for i in kinds.size():
		var kind := kinds[i]
		var col := i % COLS
		var row := i / COLS
		var n := Node3D.new()
		n.position = Vector3((col - (COLS - 1) * 0.5) * PITCH, 0.0, (row - (rows - 1) * 0.5) * PITCH)
		tray.add_child(n)
		var base := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(PITCH - 0.008, 0.006, PITCH - 0.008)
		base.mesh = tm
		base.position.y = -0.003
		n.add_child(base)
		var piece := MeshInstance3D.new()
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind == "islands":
			piece.mesh = MeshKit.prop("sign")
			piece.scale = Vector3.ONE * 0.05
		else:
			piece.mesh = Art.piece_mesh(kind, _snow)
			piece.scale = Vector3.ONE * (PIECE / float(Defs.size_of(kind) if not Defs.is_tool_kind(kind) else 1))
		n.add_child(piece)
		if Defs.SIMPLE_MODE:
			base.material_override = MeshKit.material(Color(0.98, 0.93, 0.82))
			slots.append({"kind": kind, "node": n, "piece": piece, "base": base, "label": null})
			continue
		var label := UiKit.label3d("", 0.0075, "text", true, PITCH)
		label.position = Vector3(0.0, 0.004, PITCH * 0.42)
		label.rotation = Vector3(-1.1, 0.0, 0.0)
		label.no_depth_test = false
		n.add_child(label)
		slots.append({"kind": kind, "node": n, "piece": piece, "base": base, "label": label})
	_tray_key = ""
	refresh_tray()


func refresh_tray() -> void:
	if Defs.SIMPLE_MODE:
		if slots.size() != _tray_kinds().size():
			_build_tray()
		return
	var key := "%d_%d_%s" % [int(main.net.state_get("tier", 0)), int(main.net.state_get("coins", 0)) / 5, str(main.net.state_get("free", false))]
	if key == _tray_key:
		return
	_tray_key = key
	for s in slots:
		var kind := String(s["kind"])
		var label: Label3D = s["label"]
		var base: MeshInstance3D = s["base"]
		var piece: MeshInstance3D = s["piece"]
		if kind == "islands":
			label.text = "ISLANDS"
			base.material_override = MeshKit.material(Color(0.6, 0.8, 1.0))
			continue
		var d := Defs.def(kind)
		var why := _locked(kind)
		if why != "":
			label.text = "%s\n%s" % [String(d.get("name", kind)), why]
			label.modulate = Color(0.7, 0.7, 0.75)
			base.material_override = MeshKit.material(Color(0.45, 0.45, 0.5))
			piece.material_override = Art.ghost_mat(Color(0.75, 0.75, 0.8, 0.6))
		else:
			var cost := Defs.cost_of(kind)
			label.text = String(d.get("name", kind)) + ("\n%d COINS" % cost if cost > 0 else "\nFREE")
			var poor := cost > int(main.net.state_get("coins", 0)) and not bool(main.net.state_get("free", false))
			label.modulate = Color(1.0, 0.65, 0.6) if poor else Color(1, 1, 1)
			base.material_override = MeshKit.material(Color(0.98, 0.93, 0.82) if not poor else Color(0.95, 0.78, 0.74))
			piece.material_override = null


func _locked(kind: String) -> String:
	if Defs.SIMPLE_MODE:
		return "" if _tray_kinds().has(kind) else "locked"
	if bool(main.net.state_get("free", false)):
		return ""
	var t := int(Defs.def(kind).get("tier", 0))
	return "" if int(main.net.state_get("tier", 0)) >= t else Defs.TIERS[clampi(t, 0, Defs.TIERS.size() - 1)]


func _build_board() -> void:
	if Defs.SIMPLE_MODE:
		return
	board = Node3D.new()
	board.name = "Board"
	station.add_child(board)
	board.position = BOARD_OFFSET
	board.rotation = Vector3(-0.15, atan2(-BOARD_OFFSET.x, -BOARD_OFFSET.z), 0.0)
	var panel := UiKit.panel3d(Vector2(0.5, 0.3), UiKit.BG, Color(1, 0.85, 0.4, 0.5), 0.03)
	board.add_child(panel)
	board_title = UiKit.label3d("", 0.03, "gold", true, 0.46)
	board_title.position = Vector3(0, 0.11, 0.003)
	board.add_child(board_title)
	board_stats = UiKit.label3d("", 0.021, "text", true, 0.46)
	board_stats.position = Vector3(0, 0.06, 0.003)
	board.add_child(board_stats)
	board_goals = UiKit.label3d("", 0.018, "text", false, 0.46)
	board_goals.position = Vector3(0, -0.04, 0.003)
	board.add_child(board_goals)
	refresh_board()


func refresh_board() -> void:
	if Defs.SIMPLE_MODE:
		refresh_tray()
		return
	if board_title == null:
		return
	var net: Node = main.net
	var isl := Defs.island(int(net.state_get("island", 0)))
	var tier := clampi(int(net.state_get("tier", 0)), 0, Defs.TIERS.size() - 1)
	board_title.text = "MAYOR OF %s" % String(isl["name"])
	var coins := "FREE BUILD" if bool(net.state_get("free", false)) else "COINS %d" % int(net.state_get("coins", 0))
	board_stats.text = "%s     CITIZENS %d     HAPPY %d%%\nA %s" % [coins, int(net.state_get("pop", 0)), int(net.state_get("happy", 60)), Defs.TIERS[tier]]
	if tier + 1 < Defs.TIERS.size():
		board_stats.text += "  -  %s at %d citizens" % [Defs.TIERS[tier + 1], Defs.TIER_POP[tier + 1]]
	var lines: PackedStringArray = []
	for g in net.state_get("goals", []):
		var ga: Array = g
		lines.append(("DONE  " if bool(ga[3]) else "") + "%s  (%d/%d)" % [String(ga[0]), int(ga[1]), int(ga[2])])
	if lines.is_empty():
		lines.append("Build anything you like!")
	board_goals.text = "\n".join(lines)
	refresh_tray()


func built(_id: int) -> void:
	rig.pulse(VrRig.LEFT, 0.25, 0.05)


## SIMPLE_MODE: a new block joined the tray: it bounces and sparkles for a while (no words).
func unlocked(kind: String) -> void:
	refresh_tray()
	_sparkle_kind = kind
	_sparkle_t = 8.0
	for s in slots:
		if String(s["kind"]) == kind:
			var n: Node3D = s["node"]
			var p := CPUParticles3D.new()
			p.name = "Sparkle"
			p.amount = 10
			p.lifetime = 0.9
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = PITCH * 0.4
			p.direction = Vector3.UP
			p.spread = 40.0
			p.gravity = Vector3(0, 0.02, 0)
			p.initial_velocity_min = 0.02
			p.initial_velocity_max = 0.05
			p.mesh = Art.spark_mesh(Color(1.0, 0.9, 0.4))
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.5
			n.add_child(p)
			p.emitting = true
			get_tree().create_timer(_sparkle_t).timeout.connect(func() -> void:
				if is_instance_valid(p):
					p.emitting = false
					p.get_tree().create_timer(1.2).timeout.connect(p.queue_free))
	rig.pulse(VrRig.RIGHT, 0.4, 0.15)


func _sparkle(delta: float) -> void:
	if _sparkle_t <= 0.0:
		return
	_sparkle_t -= delta
	for i in slots.size():
		if String(slots[i]["kind"]) == _sparkle_kind and i != hover:
			var k := 1.0 + absf(sin(_sparkle_t * 5.0)) * 0.25 * clampf(_sparkle_t, 0.0, 1.0)
			(slots[i]["node"] as Node3D).scale = Vector3.ONE * k


# --- Phases --------------------------------------------------------------------------------------------

func on_phase(p: String) -> void:
	_drop()
	if island_menu != null and is_instance_valid(island_menu):
		island_menu.call("close")
	island_menu = null
	station.visible = p == "play"
	var snow := bool(Defs.island(int(main.net.state_get("island", 0))).get("snow", false))
	if snow != _snow:
		_snow = snow
		_build_tray()
	if p == "select":
		var m := VrMenu.open(main, {"title": "PICK AN ISLAND", "rig": rig, "items": main.hud.call("island_items"),
			"start": str(int(main.net.state_get("island", 0))), "distance": 1.4, "height": 0.1})
		m.chosen.connect(func(id: String, _item: Dictionary) -> void: main.net.request(0, "pick_island", [int(id)]))
		m.focus_changed.connect(func(id: String, _item: Dictionary) -> void: main.net.request(0, "preview", [int(id)]))
		island_menu = m
	refresh_board()


# --- Per frame -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if rig == null or get_tree().paused:
		return
	_turn_table(delta)
	_follow(delta)
	if main.phase() != "play":
		ghost.visible = false
		held_mi.visible = false
		_hide_bubble(delta, true)
		return
	_hover_tray()
	_sparkle(delta)
	if held == "":
		_idle_hands()
	elif Defs.is_tool_kind(held):
		_hold_tool()
	else:
		_hold_building()
	_hide_bubble(delta, false)
	_nope_t = maxf(0.0, _nope_t - delta)


## Right stick: turn the table (the player orbits round its centre, so the town turns in front of them).
func _turn_table(delta: float) -> void:
	var x := rig.stick_right().x
	if absf(x) < 0.2:
		return
	var a := -x * 1.2 * delta
	var t := Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
	rig.global_transform = t * rig.global_transform
	station.global_transform = t * station.global_transform


## The tray and board stay put while the player looks about; they glide back beside them only when
## they walk away. Their height follows the head (always well below the eyes).
func _follow(delta: float) -> void:
	var head := rig.head_position()
	var yaw := rig.head_yaw()
	var target_pos := Vector3(head.x, clampf(head.y - 0.55, Defs.TABLE_Y + 0.08, Defs.TABLE_Y + 0.38), head.z)
	var cur_yaw := station.rotation.y
	var far := Vector2(station.global_position.x - head.x, station.global_position.z - head.z).length() > 0.5
	# Never follow head turns: looking right at the tray made it swing away (Simon). It stays fixed
	# beside the table unless the player walks away (the right stick turns rig and station together).
	var turned := false
	var dy := absf(station.global_position.y - target_pos.y) > 0.12
	if far or turned or dy:
		_st_moving = true
	if _st_moving:
		var k := 1.0 - exp(-5.0 * delta)
		station.global_position = station.global_position.lerp(target_pos, k)
		station.rotation = Vector3(0.0, lerp_angle(cur_yaw, yaw, k), 0.0)
		if station.global_position.distance_to(target_pos) < 0.01 and absf(wrapf(yaw - station.rotation.y, -PI, PI)) < 0.03:
			_st_moving = false


func _hover_tray() -> void:
	var p := rig.hand_point(VrRig.RIGHT)
	var best := -1
	var bd := GRAB_R
	if station.visible and not rig.in_wrist_zone(p, 0.08):
		for i in slots.size():
			var n: Node3D = slots[i]["node"]
			var d := n.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = i
	if best != hover:
		if hover >= 0 and hover < slots.size():
			(slots[hover]["node"] as Node3D).scale = Vector3.ONE
		hover = best
		if hover >= 0:
			(slots[hover]["node"] as Node3D).scale = Vector3.ONE * 1.18
			rig.pulse(VrRig.RIGHT, 0.12, 0.02)
			UiKit.sound("ui_move", -10.0)


## Try to take the hovered block. True if the hand now holds something.
func _grab_hovered() -> bool:
	if hover < 0:
		return false
	var kind := String(slots[hover]["kind"])
	if kind == "islands":
		main.net.request(0, "menu")
		rig.pulse(VrRig.RIGHT, 0.4, 0.06)
		return false
	var why := _locked(kind)
	if why != "":
		nope("Unlocks when you're a %s!" % why)
		return false
	if not Defs.SIMPLE_MODE and not bool(main.net.state_get("free", false)) and Defs.cost_of(kind) > int(main.net.state_get("coins", 0)):
		nope("Not enough coins yet: %d needed" % Defs.cost_of(kind))
		return false
	if kind == _sparkle_kind:
		_sparkle_t = minf(_sparkle_t, 0.2)
	held = kind
	held_mi.mesh = (slots[hover]["piece"] as MeshInstance3D).mesh
	held_mi.scale = (slots[hover]["piece"] as MeshInstance3D).scale
	held_mi.material_override = null
	held_mi.visible = true
	manual = false
	rot = 0
	rot0 = 0
	roll0 = _roll()
	paint_last = Vector2i(-99, -99)
	rig.pulse(VrRig.RIGHT, 0.5, 0.06)
	UiKit.sound("ui_select", -4.0)
	if Defs.SIMPLE_MODE:
		pass
	elif Defs.is_tool_kind(kind):
		var tip := "Hold the trigger and draw over the island!" if kind != "bulldozer" else "Hold the trigger and sweep to clear roads and buildings."
		main.hints.hint("tool_" + kind, tip, {"to": "vr", "icon": "plus"})
	else:
		main.hints.hint("place", "Hold it over the island and let go. Twist your hand to turn it!", {"to": "vr", "icon": "check"})
	return true


func _drop() -> void:
	held = ""
	if held_mi != null:
		held_mi.visible = false
	if ghost != null:
		ghost.visible = false
	ghost_on = false
	paint_last = Vector2i(-99, -99)


## The hand's twist (roll about where it points), for turning a held building.
func _roll() -> float:
	var b := rig.hand(VrRig.RIGHT).global_basis
	var f := -b.z
	var right := Vector3(-f.z, 0.0, f.x)
	if right.length() < 0.01:
		return 0.0
	right = right.normalized()
	var up := right.cross(f).normalized()
	return atan2(b.x.dot(up), b.x.dot(right))


## The cell (footprint corner) under a point held over the island, or (-99, -99).
func _cell_under(p: Vector3, size: int) -> Vector2i:
	if p.y < Defs.GROUND_Y - 0.04 or p.y > Defs.GROUND_Y + 0.3:
		return Vector2i(-99, -99)
	var off := (size - 1) * Defs.CELL * 0.5
	var c := Defs.world_cell(p - Vector3(off, 0.0, off))
	if not Defs.inside(c.x, c.y) or not Defs.inside(c.x + size - 1, c.y + size - 1):
		return Vector2i(-99, -99)
	return c


func _carry_mesh() -> void:
	var p := rig.hand_point(VrRig.RIGHT)
	held_mi.global_position = p + Vector3(0.0, -0.012, 0.0)
	held_mi.rotation = Vector3(0.0, rig.head_yaw() + rot * PI * 0.5, 0.0)


func _hold_building() -> void:
	_carry_mesh()
	var s := Defs.size_of(held)
	var c := _cell_under(rig.hand_point(VrRig.RIGHT), s)
	var r := _roll()
	if rig.a_pressed():
		manual = true
		rot = posmod(rot + 1, 4)
		rot0 = rot
		roll0 = r
		UiKit.sound("ui_tick", -6.0)
	var steps := int(round(wrapf(r - roll0, -PI, PI) / TWIST_STEP))
	if steps != 0:
		manual = true
		rot = posmod(rot0 - steps, 4)
	if c.x < -50:
		ghost.visible = false
		ghost_on = false
		held_mi.visible = true
	else:
		if not manual:
			rot = town.auto_rot(held, c.x, c.y)
			rot0 = rot
			roll0 = r
		ghost_why = main.place_problem(held, c.x, c.y)
		_show_ghost(held, c, rot, ghost_why == "")
		held_mi.visible = false
	if rig.trigger_released() or not rig.trigger_down():
		if ghost_on and ghost_ok:
			main.net.request(0, "place", [held, ghost_cell.x, ghost_cell.y, rot])
			rig.pulse(VrRig.RIGHT, 0.7, 0.08)
			if not Defs.SIMPLE_MODE:
				main.hints.hint("crane_vr", "The crane brings bricks to build it. Touch buildings to see what they need!", {"to": "vr", "icon": "plus"})
		elif ghost_on:
			nope(ghost_why)
		else:
			UiKit.sound("ui_back", -8.0)
		_drop()


func _hold_tool() -> void:
	_carry_mesh()
	var p := rig.hand_point(VrRig.RIGHT)
	if rig.a_pressed() or (rig.trigger_pressed() and hover >= 0):
		var same := hover >= 0 and String(slots[hover]["kind"]) == held
		_drop()
		UiKit.sound("ui_back", -8.0)
		if rig.trigger_down() and hover >= 0 and not same:
			_grab_hovered()
		return
	var c := _cell_under(p, 1)
	if c.x < -50:
		ghost.visible = false
		ghost_on = false
		held_mi.visible = true
		paint_last = Vector2i(-99, -99)
		return
	held_mi.visible = true
	var ok := _tool_ok(held, c)
	_show_ghost(held, c, 0, ok)
	if rig.trigger_down():
		if c != paint_last:
			var cells := PackedInt32Array()
			for cc in _line(paint_last, c):
				cells.append(cc.x + cc.y * Defs.GRID)
			paint_last = c
			main.net.request(0, "paint", [held, cells])
			rig.pulse(VrRig.RIGHT, 0.2 if ok else 0.08, 0.03)
	else:
		paint_last = Vector2i(-99, -99)


func _tool_ok(kind: String, c: Vector2i) -> bool:
	if kind == "bulldozer":
		var b := town.building_at(c.x, c.y)
		return town.layer(c.x, c.y) != Defs.L_NONE or (not b.is_empty() and String(b["kind"]) != "hall")
	return town.can_place(kind, c.x, c.y) == ""


## Cells from a to b in 4-connected steps (b alone if a isn't a recent neighbour).
func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if a.x < -50 or absi(a.x - b.x) + absi(a.y - b.y) > 8:
		out.append(b)
		return out
	var cur := a
	while cur != b:
		if absi(b.x - cur.x) >= absi(b.y - cur.y):
			cur.x += signi(b.x - cur.x)
		else:
			cur.y += signi(b.y - cur.y)
		out.append(cur)
	return out


func _show_ghost(kind: String, c: Vector2i, r: int, ok: bool) -> void:
	var key := "%s_%d" % [kind, 1 if ok else 0]
	if not ghost.has_meta("key") or String(ghost.get_meta("key")) != key:
		ghost.set_meta("key", key)
		if Defs.is_tool_kind(kind):
			var bm := BoxMesh.new()
			bm.size = Vector3(1.0, 0.06, 1.0)
			ghost.mesh = bm
		else:
			ghost.mesh = Art.building_mesh(kind, 0, 1, _snow)
		ghost.material_override = Art.ghost_mat(Color(0.4, 1.0, 0.5, 0.5) if ok else Color(1.0, 0.35, 0.3, 0.5))
	var s := 1 if Defs.is_tool_kind(kind) else Defs.size_of(kind)
	var center := Defs.foot_center(c.x, c.y, s)
	ghost.transform = Transform3D(Basis(Vector3.UP, r * PI * 0.5).scaled(Vector3.ONE * Defs.CELL), center + Vector3(0, 0.001, 0))
	ghost.visible = true
	if c != ghost_cell and ghost_on:
		UiKit.sound("ui_tick", -14.0, 1.4 if ok else 0.8)
	ghost_on = true
	ghost_ok = ok
	ghost_cell = c


## Snapshot: what the mayor holds over the board, for the TV machine's copy of the ghost.
func ghost_state() -> PackedInt32Array:
	if held == "" or not ghost_on:
		return PackedInt32Array()
	return PackedInt32Array([Defs.kind_index(held), ghost_cell.x, ghost_cell.y, rot, 1 if ghost_ok else 0])


# --- Touching buildings ------------------------------------------------------------------------------------

func _idle_hands() -> void:
	ghost.visible = false
	ghost_on = false
	if rig.trigger_pressed():
		if not _grab_hovered() and Defs.SIMPLE_MODE and main.props != null and hover < 0:
			main.props.try_grab_tree(rig.hand_point(VrRig.RIGHT))
		return
	if Defs.SIMPLE_MODE:
		return  # touching things makes them react (props.gd), no speech bubbles
	for h in [VrRig.LEFT, VrRig.RIGHT]:
		var p := rig.hand_point(int(h))
		if p.y > Defs.GROUND_Y + 0.09 or p.y < Defs.GROUND_Y - 0.03:
			continue
		var c := Defs.world_cell(p)
		var b := town.building_at(c.x, c.y)
		if not b.is_empty():
			_show_bubble(b)
			return


func _show_bubble(b: Dictionary) -> void:
	var id := int(b["id"])
	bubble_t = 3.5
	if bubble == null:
		bubble = Node3D.new()
		bubble.name = "Bubble"
		add_child(bubble)
		var panel := UiKit.panel3d(Vector2(0.27, 0.1), Color(1, 1, 1, 0.94), Color(0.2, 0.2, 0.3, 0.6), 0.03)
		bubble.add_child(panel)
		bubble_title = UiKit.label3d("", 0.016, Color(0.15, 0.25, 0.55), true, 0.25)
		bubble_title.outline_size = 0
		bubble_title.position = Vector3(0, 0.03, 0.002)
		bubble.add_child(bubble_title)
		bubble_body = UiKit.label3d("", 0.012, Color(0.15, 0.15, 0.2), false, 0.25)
		bubble_body.outline_size = 0
		bubble_body.position = Vector3(0, -0.012, 0.002)
		bubble.add_child(bubble_body)
	if id != bubble_id or not bubble.visible:
		bubble_id = id
		rig.pulse(VrRig.LEFT, 0.2, 0.04)
		rig.pulse(VrRig.RIGHT, 0.2, 0.04)
		UiKit.sound("ui_open", -8.0)
	bubble_title.text = Defs.building_name(String(b["kind"]), id)
	bubble_body.text = Sim.needs_text(b)
	var c := town.center_of(b) + Vector3(0, 0.14, 0)
	bubble.global_position = c
	var to := rig.head_position() - c
	bubble.rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)
	bubble.visible = true


func _hide_bubble(delta: float, now: bool) -> void:
	if bubble == null or not bubble.visible:
		return
	bubble_t -= delta
	if now or bubble_t <= 0.0:
		bubble.visible = false
	elif town.buildings.has(bubble_id):
		bubble_body.text = Sim.needs_text(town.buildings[bubble_id])


## A friendly "not there" with a buzz in the hand.
func nope(why: String) -> void:
	rig.pulse(VrRig.RIGHT, 0.35, 0.12)
	UiKit.sound("ui_error", -6.0)
	if _nope_t <= 0.0 and why != "" and not Defs.SIMPLE_MODE:
		_nope_t = 1.6
		HudKit.vr_toast(main, rig.camera, why, {"duration": 2.0})


# --- Bots ---------------------------------------------------------------------------------------------------

## World position of a tray block (tests reach for it).
func tray_point(kind: String) -> Vector3:
	for s in slots:
		if String(s["kind"]) == kind:
			return (s["node"] as Node3D).global_position
	return Vector3.ZERO
