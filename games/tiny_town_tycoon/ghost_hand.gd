extends Node3D
## SIMPLE_MODE practice for the mayor: SHOWS how to build instead of text (host only).
##   step 0: a glowing spot at the end of the first street and see-through road tiles beyond it. On the
##           VR host a see-through hand reaches to the ROAD in the tray, pinches it, and draws the
##           road from the glowing spot along the tiles. Done when the mayor draws any road.
##   step 1: a glowing spot beside the new road; the hand takes a HOUSE from the tray and puts it
##           down there. Done when the mayor places a house.
## main.gd owns the step (main.practice) and the cells; this file only draws. The hand loops while
## the mayor's hand is empty; the spot stays until the step is done.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const CYCLE := 5.0

var main: Node
var hand: Node3D
var fingers: Array[Node3D] = []
var mat: StandardMaterial3D
var carried: MeshInstance3D
var spot: MeshInstance3D
var tiles: Array[MeshInstance3D] = []
var house_ghost: MeshInstance3D
var t := 0.0
var shown := false  ## bots: the hand has been on screen


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.95, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hand = Node3D.new()
	add_child(hand)
	_part(hand, Vector3(0, 0.03, 0.01), Vector3(0.045, 0.02, 0.055))  # palm
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.03 + i * 0.02, 0.025, -0.042)
		hand.add_child(f)
		fingers.append(f)
		_part(f, Vector3(0, 0, -0.022), Vector3(0.008, 0.008, 0.026))
	var thumb := Node3D.new()
	thumb.position = Vector3(0.045, 0.025, 0.0)
	thumb.rotation.y = -0.7
	hand.add_child(thumb)
	fingers.append(thumb)
	_part(thumb, Vector3(0, 0, -0.018), Vector3(0.009, 0.009, 0.022))
	carried = MeshInstance3D.new()
	carried.material_override = Art.ghost_mat(Color(1.0, 0.95, 0.5, 0.6))
	carried.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(carried)
	spot = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = Defs.CELL * 0.36
	tm.outer_radius = Defs.CELL * 0.5
	tm.rings = 20
	tm.ring_segments = 6
	spot.mesh = tm
	spot.material_override = MeshKit.material(Color(1.0, 0.9, 0.35), 2.5)
	spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spot)
	var bm := BoxMesh.new()
	bm.size = Vector3(Defs.CELL * 0.9, 0.003, Defs.CELL * 0.9)
	for i in 3:
		var tile := MeshInstance3D.new()
		tile.mesh = bm
		tile.material_override = Art.ghost_mat(Color(1.0, 0.95, 0.6, 0.45))
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tile)
		tiles.append(tile)
	house_ghost = MeshInstance3D.new()
	house_ghost.mesh = Art.building_mesh("house", 0, 1, false)
	house_ghost.material_override = Art.ghost_mat(Color(1.0, 0.95, 0.6, 0.45))
	house_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	house_ghost.scale = Vector3.ONE * Defs.CELL
	add_child(house_ghost)
	_hide_all()


func _part(parent: Node3D, pos: Vector3, radii: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _hide_all() -> void:
	hand.visible = false
	carried.visible = false
	spot.visible = false
	house_ghost.visible = false
	for tile in tiles:
		tile.visible = false


func _grip(k: float) -> void:
	for i in fingers.size():
		fingers[i].rotation.x = -k * (1.1 if i < 4 else 0.6)


func update_demo(delta: float) -> void:
	var step: int = main.practice
	if step >= 2 or not main.playing() or main.practice_road.is_empty():
		_hide_all()
		t = 0.0
		return
	t += delta
	var pulse := 1.0 + sin(t * 6.0) * 0.12
	# the glowing spot and see-through targets (every host view: VR and the flat mayor)
	var road: Array = main.practice_road
	var a: Vector2i = road[0]
	var target_cell: Vector2i = a if step == 0 else main.practice_house
	var sc := Defs.cell_center(target_cell.x, target_cell.y)
	spot.visible = true
	spot.position = sc + Vector3(0, 0.003, 0)
	spot.scale = Vector3(pulse, 0.3, pulse)
	for i in tiles.size():
		var tile := tiles[i]
		tile.visible = step == 0 and i < road.size()
		if tile.visible:
			var c: Vector2i = road[i]
			tile.position = Defs.cell_center(c.x, c.y) + Vector3(0, 0.002, 0)
	house_ghost.visible = step == 1 and main.practice_house.x >= 0
	if house_ghost.visible:
		house_ghost.position = sc + Vector3(0, 0.001, 0)
		house_ghost.rotation.y = int(main.town.auto_rot("house", target_cell.x, target_cell.y)) * PI * 0.5
	# the hand (VR mayor only, while their hand is empty)
	var mayor: Node = main.mayor
	if mayor == null or String(mayor.get("held")) != "" or (main.props != null and main.props.holding()):
		hand.visible = false
		carried.visible = false
		return
	var kind := "road" if step == 0 else "house"
	var tray: Vector3 = mayor.call("tray_point", kind)
	if tray == Vector3.ZERO:
		hand.visible = false
		carried.visible = false
		return
	shown = true
	hand.visible = true
	var ph := fposmod(t, CYCLE)
	var up := Vector3(0, 0.1, 0)
	var start := tray + up
	var over := sc + Vector3(0, 0.03, 0)
	var pos := start
	var grip := 0.0
	var holding := false
	if ph < 1.0:
		pos = start.lerp(tray + Vector3(0, 0.015, 0), smoothstep(0.0, 1.0, ph))
	elif ph < 1.3:
		pos = tray + Vector3(0, 0.015, 0)
		grip = (ph - 1.0) / 0.3
		holding = ph > 1.15
	elif ph < 2.4:
		var k := smoothstep(1.3, 2.4, ph)
		pos = (tray + Vector3(0, 0.015, 0)).lerp(over, k) + Vector3(0, sin(k * PI) * 0.08, 0)
		grip = 1.0
		holding = true
	elif ph < 3.9:
		grip = 1.0
		holding = true
		if step == 0:
			var k2 := (ph - 2.4) / 1.5 * float(road.size() - 1)
			var i0 := clampi(int(k2), 0, road.size() - 1)
			var i1 := clampi(i0 + 1, 0, road.size() - 1)
			var c0: Vector2i = road[i0]
			var c1: Vector2i = road[i1]
			pos = Defs.cell_center(c0.x, c0.y).lerp(Defs.cell_center(c1.x, c1.y), k2 - i0) + Vector3(0, 0.03, 0)
		else:
			var k3 := smoothstep(2.4, 3.0, ph)
			pos = over.lerp(sc + Vector3(0, 0.012, 0), k3)
			if ph > 3.0:
				grip = 0.0
				holding = false
				pos = (sc + Vector3(0, 0.012, 0)).lerp(sc + Vector3(0, 0.08, 0), smoothstep(3.0, 3.9, ph))
	else:
		pos = hand.position.lerp(sc + Vector3(0, 0.12, 0), 0.1)
		hand.visible = ph < 4.6
	hand.position = pos
	var head: Vector3 = main.vr_rig.head_position() if main.vr_rig != null else Defs.CENTER + Vector3(0, 0.6, 1.0)
	var to := pos - head
	hand.rotation = Vector3(-0.35, atan2(-to.x, -to.z), 0.0)
	_grip(grip)
	carried.visible = holding and hand.visible
	if carried.visible:
		if carried.get_meta("kind", "") != kind:
			carried.set_meta("kind", kind)
			carried.mesh = Art.piece_mesh(kind, false)
		carried.position = pos + Vector3(0, -0.012, 0)
		carried.scale = Vector3.ONE * 0.04
