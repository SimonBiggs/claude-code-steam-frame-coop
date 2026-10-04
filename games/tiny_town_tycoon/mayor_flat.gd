extends Node3D
## The flat mayor: local play without a headset, slot 0 on the TV builds with a cursor.
## L-stick moves the cursor over the island, LB / RB pick a building block, A builds (hold A and move
## to draw roads / rails / bulldoze), X turns the building, B grabs the bulldozer (B again: back),
## R-stick turns and zooms the view. The HUD card (hud.gd) shows the block, its price and what the
## building under the cursor needs.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const Sim := preload("res://games/tiny_town_tycoon/sim.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const UiMenu := preload("res://core/ui_menu.gd")

const SLOT := 0
const CURSOR_SPEED := 5.5  ## cells per second

var main: Node
var town: Town
var cam: Camera3D
var cur := Vector2(Defs.GRID * 0.5, Defs.GRID * 0.5 + 2.0)  ## cursor, in cells (continuous)
var pick := 0  ## index into Defs.TRAY
var rot := 0
var manual := false
var cam_yaw := 0.0
var cam_dist := 0.75
var cursor_mi: MeshInstance3D
var ghost: MeshInstance3D
var paint_last := Vector2i(-99, -99)
var _prev_pick := 0
var _cam_pos := Vector3.ZERO
var _cam_at := Vector3.ZERO
var _ghost_key := ""


func setup(p_main: Node, p_town: Town, p_cam: Camera3D) -> void:
	main = p_main
	town = p_town
	cam = p_cam
	cursor_mi = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = Defs.CELL * 0.5
	tm.outer_radius = Defs.CELL * 0.62
	tm.rings = 20
	tm.ring_segments = 6
	cursor_mi.mesh = tm
	cursor_mi.material_override = MeshKit.material(Color(0.3, 0.9, 1.0), 1.5)
	cursor_mi.scale = Vector3(1, 0.25, 1)
	cursor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cursor_mi)
	ghost = MeshInstance3D.new()
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	_cam_at = Defs.CENTER
	_cam_pos = Defs.CENTER + Vector3(0, 0.6, 0.6)


func kind() -> String:
	return Defs.TRAY[clampi(pick, 0, Defs.TRAY.size() - 1)]


func select(k: String) -> void:
	var i := Defs.TRAY.find(k)
	if i >= 0:
		pick = i
		manual = false


## The footprint corner under the cursor for the picked block.
func cell() -> Vector2i:
	var s := 1 if Defs.is_tool_kind(kind()) else Defs.size_of(kind())
	var off := (s - 1) * 0.5
	return Vector2i(floori(cur.x - off), floori(cur.y - off))


## Tests: put the cursor on a cell.
func move_to(c: Vector2i) -> void:
	var s := 1 if Defs.is_tool_kind(kind()) else Defs.size_of(kind())
	cur = Vector2(c.x + s * 0.5, c.y + s * 0.5)


func tick(delta: float, playing: bool) -> void:
	var party: Node = main.party
	var busy: bool = UiMenu.slot_busy(SLOT) or not party.is_local(SLOT)
	cursor_mi.visible = playing
	ghost.visible = playing
	if playing and not busy:
		_input_tick(delta)
	_camera(delta)
	if playing:
		_draw()


func _input_tick(delta: float) -> void:
	var party: Node = main.party
	var mv: Vector2 = party.stick(SLOT, "move")
	if mv.length() > 0.12:
		var f := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw)) * -1.0
		var r := Vector3(-f.z, 0.0, f.x)
		var d := r * mv.x - f * mv.y
		cur += Vector2(d.x, d.z) * CURSOR_SPEED * delta
		cur.x = clampf(cur.x, 0.5, Defs.GRID - 0.5)
		cur.y = clampf(cur.y, 0.5, Defs.GRID - 0.5)
	var look: Vector2 = party.stick(SLOT, "look")
	cam_yaw -= look.x * 1.8 * delta
	cam_dist = clampf(cam_dist + look.y * 0.6 * delta, 0.35, 1.4)
	if party.just_pressed(SLOT, "rb"):
		pick = posmod(pick + 1, Defs.TRAY.size())
		manual = false
		main.sound("ui_move", -6.0)
	if party.just_pressed(SLOT, "lb"):
		pick = posmod(pick - 1, Defs.TRAY.size())
		manual = false
		main.sound("ui_move", -6.0)
	if party.just_pressed(SLOT, "back"):
		if kind() == "bulldozer":
			pick = _prev_pick
		else:
			_prev_pick = pick
			select("bulldozer")
		main.sound("ui_toggle", -6.0)
	if party.just_pressed(SLOT, "x"):
		manual = true
		rot = posmod(rot + 1, 4)
		main.sound("ui_tick", -6.0)
	if party.just_pressed(SLOT, "select"):
		main.net.request(SLOT, "menu")
	var k := kind()
	var c := cell()
	if Defs.is_tool_kind(k):
		if party.pressed(SLOT, "accept"):
			if c != paint_last:
				var cells := PackedInt32Array()
				if paint_last.x > -50 and absi(paint_last.x - c.x) + absi(paint_last.y - c.y) <= 3:
					var p := paint_last
					while p != c:
						if absi(c.x - p.x) >= absi(c.y - p.y):
							p.x += signi(c.x - p.x)
						else:
							p.y += signi(c.y - p.y)
						cells.append(p.x + p.y * Defs.GRID)
				else:
					cells.append(c.x + c.y * Defs.GRID)
				paint_last = c
				main.net.request(SLOT, "paint", [k, cells])
		else:
			paint_last = Vector2i(-99, -99)
	elif party.just_pressed(SLOT, "accept"):
		if not manual:
			rot = town.auto_rot(k, c.x, c.y)
		main.net.request(SLOT, "place", [k, c.x, c.y, rot])


func _camera(delta: float) -> void:
	if cam == null:
		return
	var at := Vector3(Defs.HALF * 2.0 * (cur.x / Defs.GRID) - Defs.HALF, Defs.GROUND_Y, Defs.HALF * 2.0 * (cur.y / Defs.GRID) - Defs.HALF).lerp(Defs.CENTER, 0.3)
	var pos := at + Vector3(sin(cam_yaw), 0.0, cos(cam_yaw)) * cam_dist * 0.75 + Vector3.UP * cam_dist
	var k := 1.0 - exp(-6.0 * delta)
	_cam_at = _cam_at.lerp(at, k)
	_cam_pos = _cam_pos.lerp(pos, k)
	if main.split != null and main.split.is_shared():
		return
	cam.global_position = _cam_pos
	cam.look_at(_cam_at, Vector3.UP)


func _draw() -> void:
	var k := kind()
	var c := cell()
	var s := 1 if Defs.is_tool_kind(k) else Defs.size_of(k)
	var center := Defs.foot_center(c.x, c.y, s)
	cursor_mi.position = center + Vector3(0, 0.002, 0)
	cursor_mi.scale = Vector3(s, 0.25, s)
	var ok := true
	if Defs.is_tool_kind(k):
		if k == "bulldozer":
			var b := town.building_at(c.x, c.y)
			ok = town.layer(c.x, c.y) != Defs.L_NONE or (not b.is_empty() and String(b["kind"]) != "hall")
		else:
			ok = main.place_problem(k, c.x, c.y) == ""
	else:
		ok = main.place_problem(k, c.x, c.y) == ""
		if not manual:
			rot = town.auto_rot(k, c.x, c.y)
	var key := "%s_%d" % [k, 1 if ok else 0]
	if key != _ghost_key:
		_ghost_key = key
		if Defs.is_tool_kind(k):
			var bm := BoxMesh.new()
			bm.size = Vector3(1.0, 0.06, 1.0)
			ghost.mesh = bm
		else:
			ghost.mesh = Art.building_mesh(k, 0, 1, bool(Defs.island(town.island).get("snow", false)))
		ghost.material_override = Art.ghost_mat(Color(0.4, 1.0, 0.5, 0.5) if ok else Color(1.0, 0.35, 0.3, 0.5))
	ghost.transform = Transform3D(Basis(Vector3.UP, rot * PI * 0.5).scaled(Vector3.ONE * Defs.CELL), center + Vector3(0, 0.001, 0))


## For the HUD card: [title, line, info].
func info() -> Array:
	var k := kind()
	var d := Defs.def(k)
	var c := cell()
	var title := "%s  %s" % [String(d.get("name", k)), ("%d COINS" % Defs.cost_of(k)) if Defs.cost_of(k) > 0 else "FREE"]
	var why: String = main.place_problem(k, c.x, c.y)
	if Defs.is_tool_kind(k):
		why = ""
	var line := String(d.get("desc", "")) if why == "" else why
	var b := town.building_at(int(cur.x), int(cur.y))
	var inf := ""
	if not b.is_empty():
		inf = "%s: %s" % [Defs.building_name(String(b["kind"]), int(b["id"])), Sim.needs_text(b)]
	return [title, line, inf]
