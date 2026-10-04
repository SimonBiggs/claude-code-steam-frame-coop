extends Node3D
## The pilot's control desk. Only the pilot (VR, or player 1's mouse/controller pointer in split
## screen) sees the controls: they're on PANEL_LAYER, which the TV cameras don't draw, and the
## TV machine never builds them at all.
## Hands (from operator.panel_hands()) are points in space: touching a button with any hand presses
## it; plugs, the pressure dial and the launch lever are grabbed with the grip (VR right trigger,
## mouse button / A for the pointer) and moved. The host's main.gd decides what's right or wrong.
##
## Surface layout (metres, x right, y away from the pilot along the sloped top):
##   SHAPES (2x2 buttons)  |            | PRESSURE dial + SET |  LAUNCH
##   FUEL MIX (4 colours)  |   PLUGS    | SWITCHES x5 + CHECK |  lever
## Two cockpit wings angle in towards the pilot either side of the desk:
##   left: ALIEN HELLO (a hologram alien + BEEP / BOOP / ZORP buttons)
##   right: THRUSTER CRANK (grab the handle and wind it round, then press GO)
## Every control lives on a "deck" (the main surface or a wing) and uses that deck's local x/y.

const P := preload("res://games/rocket_workshop/puzzles.gd")
const TILT := -1.0471976  # surface pitched 30 degrees towards the pilot
const AREAS := {
	"symbols": [Vector2(-0.55, 0.185), Vector2(0.5, 0.31), "SHAPES", Color(0.42, 0.35, 0.62)],
	"fuel": [Vector2(-0.55, -0.185), Vector2(0.5, 0.31), "FUEL MIX", Color(0.6, 0.35, 0.28)],
	"wires": [Vector2(0.0, 0.0), Vector2(0.5, 0.68), "PLUGS", Color(0.27, 0.45, 0.58)],
	"gauge": [Vector2(0.49, 0.185), Vector2(0.38, 0.31), "PRESSURE", Color(0.55, 0.47, 0.22)],
	"switches": [Vector2(0.49, -0.185), Vector2(0.38, 0.31), "SWITCHES", Color(0.27, 0.5, 0.33)],
	"lever": [Vector2(0.775, 0.0), Vector2(0.15, 0.68), "LAUNCH", Color(0.6, 0.25, 0.25)],
}
const SOCKET_X: Array[float] = [-0.18, -0.06, 0.06, 0.18]
const SOCKET_Y := 0.19
const PLUG_REST_Y := -0.17
const ANCHOR_Y := -0.31
const DIAL_C := Vector2(0.44, 0.165)
const DIAL_R := 0.06
const LEVER_PIVOT := Vector3(0.775, -0.06, 0.0)
const LEVER_LEN := 0.17
const LEVER_MAX := 0.6
const WING_SIZE := Vector2(0.62, 0.5)
const WING_X := 1.2
const WING_YAW := 0.7  # radians the wings turn in towards the pilot
const WING_AREAS := {
	"alien": ["l", Vector2(0.0, 0.0), Vector2(0.6, 0.48), "ALIEN HELLO", Color(0.3, 0.42, 0.6)],
	"crank": ["r", Vector2(0.0, 0.0), Vector2(0.6, 0.48), "THRUSTER CRANK", Color(0.55, 0.38, 0.22)],
}
const HELLO_X: Array[float] = [-0.18, 0.0, 0.18]
const HELLO_Y := -0.14
const ALIEN_AT := Vector2(0.0, 0.08)
const CRANK_C := Vector2(-0.06, 0.04)
const CRANK_R := 0.1
const GO_POS := Vector2(0.2, -0.15)

var main
var detail := true
var top := 0.9
var body: MeshInstance3D
var surface: Node3D
var screen_root: Node3D
var screen: Label3D
var controls := {}  # key -> {pos: Vector2, r, h, kind: "button" | "grab", cap: Node3D}
var area_nodes := {}  # area -> {plate: StandardMaterial3D, lamp: StandardMaterial3D}
var touching := {}  # "hand|key" -> true while a hand is inside a button
var grip_was := {}
var grabs := {}  # hand id -> grabbed control key
var press_t := {}
var plug_nodes: Array = []
var cables: Array = []
var plug_drag := {}  # colour -> local position while carried
var fuel_dots: Array = []
var shape_holders: Array = []
var needle: Node3D
var switch_pivots: Array = []
var switch_lamps: Array = []
var lever_pivot: Node3D
var lever_pull := 0.0
var lever_fired := false
var shown_rocket := -1
var wing_l: Node3D
var wing_r: Node3D
var wing_bodies: Array = []
var alien_holder: Node3D
var alien_beam: MeshInstance3D
var crank_wheel: Node3D
var crank_handle: Node3D
var crank_label: Label3D
var crank_acc := 0.0
var crank_last := 0.0
var crank_turns := 0
var anim_t := 0.0


func _ready() -> void:
	position = Vector3(0, 0, -0.5)
	var wood: StandardMaterial3D = main.make_material(Color(0.62, 0.42, 0.28), 0.0)
	body = MeshInstance3D.new()
	body.mesh = main.box_mesh(Vector3(1.9, 1.0, 0.75))
	body.material_override = wood
	add_child(body)
	surface = Node3D.new()
	surface.basis = Basis(Vector3.RIGHT, TILT)
	add_child(surface)
	var slab := MeshInstance3D.new()
	slab.mesh = main.box_mesh(Vector3(1.86, 0.8, 0.06))
	slab.material_override = main.make_material(Color(0.22, 0.24, 0.3), 0.0)
	slab.position = Vector3(0, 0, -0.031)
	surface.add_child(slab)
	screen_root = Node3D.new()
	add_child(screen_root)
	var back := MeshInstance3D.new()
	back.mesh = main.box_mesh(Vector3(1.15, 0.36, 0.05))
	back.material_override = main.make_material(Color(0.12, 0.16, 0.22), 0.0)
	screen_root.add_child(back)
	var frame := MeshInstance3D.new()
	frame.mesh = main.box_mesh(Vector3(1.22, 0.42, 0.04))
	frame.material_override = main.make_material(Color(0.95, 0.6, 0.2), 0.0)
	frame.position.z = -0.02
	screen_root.add_child(frame)
	wing_l = _build_wing(-1.0)
	wing_r = _build_wing(1.0)
	if detail:
		_build_controls()
		_build_wing_controls()
		screen = Label3D.new()
		screen.font_size = 40
		screen.pixel_size = 0.0017
		screen.outline_size = 12
		screen.width = 640.0
		screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		screen.modulate = Color(0.75, 1.0, 0.8)
		screen.position.z = 0.03
		screen_root.add_child(screen)
		main.set_layers(screen, main.PANEL_LAYER)
	set_top(top)


## Desk height (the pilot may be sitting down): moves the sloped top, the body and the screen.
func set_top(h: float) -> void:
	top = clampf(h, 0.5, 1.25)
	surface.position = Vector3(0, top, 0)
	var bh := top - 0.12
	body.scale = Vector3(1, bh, 1)
	body.position = Vector3(0, bh / 2.0, -0.02)
	screen_root.position = Vector3(0, top + 0.32, -0.75)  # far enough to focus on, low enough to see the rocket over it
	for side in [-1.0, 1.0]:
		var wing: Node3D = wing_l if side < 0.0 else wing_r
		if wing == null:
			continue
		var yaw: float = -side * WING_YAW
		wing.position = Vector3(side * WING_X, top - 0.03, 0.18)
		wing.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, TILT)
		var wb: MeshInstance3D = wing_bodies[0 if side < 0.0 else 1]
		var wh := top - 0.15
		wb.scale = Vector3(1, wh, 1)
		wb.position = Vector3(side * WING_X, wh / 2.0, 0.18 - 0.05)
		wb.rotation.y = yaw
	if screen != null:
		screen.pixel_size = 0.0026  # big and clear from the pilot's spot
		screen.no_depth_test = true
		screen.render_priority = 5


## A cockpit wing: a small sloped console turned in towards the pilot (side -1 = left, 1 = right).
func _build_wing(side: float) -> Node3D:
	var wb := MeshInstance3D.new()
	wb.mesh = main.box_mesh(Vector3(0.6, 1.0, 0.42))
	wb.material_override = main.make_material(Color(0.62, 0.42, 0.28), 0.0)
	add_child(wb)
	wing_bodies.append(wb)
	var wing := Node3D.new()
	add_child(wing)
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	slab.mesh = main.box_mesh(Vector3(WING_SIZE.x + 0.04, WING_SIZE.y + 0.04, 0.06))
	slab.material_override = main.make_material(Color(0.22, 0.24, 0.3), 0.0)
	slab.position = Vector3(0, 0, -0.027)
	wing.add_child(slab)
	return wing


func _build_wing_controls() -> void:
	for area in WING_AREAS:
		var a: Array = WING_AREAS[area]
		var deck: Node3D = wing_l if a[0] == "l" else wing_r
		var holder := Node3D.new()
		deck.add_child(holder)
		var c: Vector2 = a[1]
		var size: Vector2 = a[2]
		# The wing's own slab doubles as this module's coloured plate (one less draw call).
		var pm: StandardMaterial3D = main.make_material(a[4], 0.0)
		(deck.get_node("Slab") as MeshInstance3D).material_override = pm
		var lamp := MeshInstance3D.new()
		lamp.mesh = main.sphere_mesh(0.016)
		var lm: StandardMaterial3D = main.make_material(Color(0.2, 0.2, 0.2), 0.01)
		lamp.material_override = lm
		lamp.position = Vector3(c.x + size.x / 2.0 - 0.035, c.y + size.y / 2.0 - 0.035, 0.012)
		holder.add_child(lamp)
		_flat_label(holder, a[3], Vector2(c.x - 0.03, c.y + size.y / 2.0 - 0.035), 30)
		area_nodes[area] = {"plate": pm, "lamp": lm, "color": a[4]}
		if area == "alien":
			# Hologram projector with the alien floating above it, and three hello buttons.
			var proj := MeshInstance3D.new()
			proj.mesh = main.cyl_mesh(0.05, 0.065, 0.03, 16)
			proj.material_override = main.make_material(Color(0.35, 0.38, 0.45), 0.0)
			proj.rotation.x = PI / 2.0
			proj.position = Vector3(ALIEN_AT.x, ALIEN_AT.y, 0.015)
			holder.add_child(proj)
			alien_beam = MeshInstance3D.new()
			alien_beam.mesh = main.cyl_mesh(0.085, 0.035, 0.18, 14)
			var bm: StandardMaterial3D = main.make_material(Color(0.4, 0.95, 1.0, 0.18), 1.2)
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			alien_beam.material_override = bm
			alien_beam.rotation.x = PI / 2.0
			alien_beam.position = Vector3(ALIEN_AT.x, ALIEN_AT.y, 0.12)
			alien_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(alien_beam)
			alien_holder = Node3D.new()
			alien_holder.rotation.x = -TILT  # the alien stands upright in the world
			alien_holder.position = Vector3(ALIEN_AT.x, ALIEN_AT.y, 0.1)
			holder.add_child(alien_holder)
			for i in 3:
				_button(holder, "hello%d" % i, Vector2(HELLO_X[i], HELLO_Y), 0.055, P.HELLO_COLORS[i], false)
				controls["hello%d" % i].deck = deck
				_flat_label(controls["hello%d" % i].cap, P.HELLO_WORDS[i], Vector2(0, 0), 26, Color(0.1, 0.1, 0.15), 0.027)
		else:
			# A big wheel with a handle on its rim, a turn counter and a GO button.
			crank_wheel = Node3D.new()
			crank_wheel.position = Vector3(CRANK_C.x, CRANK_C.y, 0.0)
			holder.add_child(crank_wheel)
			var disc := MeshInstance3D.new()
			disc.mesh = main.cyl_mesh(CRANK_R + 0.025, CRANK_R + 0.025, 0.025, 20)
			disc.material_override = main.make_material(Color(0.75, 0.72, 0.68), 0.0)
			disc.rotation.x = PI / 2.0
			disc.position.z = 0.0125
			crank_wheel.add_child(disc)
			var spoke := MeshInstance3D.new()
			spoke.mesh = main.box_mesh(Vector3(CRANK_R * 2.0, 0.02, 0.012))
			spoke.material_override = main.make_material(Color(0.95, 0.55, 0.2), 0.2)
			spoke.position.z = 0.03
			crank_wheel.add_child(spoke)
			crank_handle = Node3D.new()
			holder.add_child(crank_handle)
			var knob := MeshInstance3D.new()
			knob.mesh = main.capsule_mesh(0.026, 0.11)  # a stubby handle sticking up off the wheel
			knob.rotation.x = PI / 2.0
			knob.material_override = main.make_material(Color(0.95, 0.25, 0.2), 0.4)
			knob.position.z = 0.075
			crank_handle.add_child(knob)
			controls["crank"] = {"pos": CRANK_C, "r": 0.04, "h": 0.07, "kind": "grab", "cap": crank_handle, "deck": deck}
			crank_label = _flat_label(holder, "TURNS\n0", Vector2(0.2, 0.08), 40, Color(0.75, 1.0, 0.8))
			_button(holder, "crank_go", GO_POS, 0.045, Color(0.3, 0.85, 0.4), false)
			controls["crank_go"].deck = deck
			_flat_label(controls["crank_go"].cap, "GO", Vector2(0, 0), 30, Color(0.1, 0.2, 0.1), 0.027)
		main.set_layers(holder, main.PANEL_LAYER)


# --- Building the controls --------------------------------------------------

func _build_controls() -> void:
	var holder := Node3D.new()
	surface.add_child(holder)
	for area in AREAS:
		var a: Array = AREAS[area]
		var c: Vector2 = a[0]
		var size: Vector2 = a[1]
		var plate := MeshInstance3D.new()
		plate.mesh = main.box_mesh(Vector3(size.x - 0.012, size.y - 0.012, 0.006))
		var pm: StandardMaterial3D = main.make_material(a[3], 0.0)
		plate.material_override = pm
		plate.position = Vector3(c.x, c.y, 0.003)
		holder.add_child(plate)
		var lamp := MeshInstance3D.new()
		lamp.mesh = main.sphere_mesh(0.014)
		var lm: StandardMaterial3D = main.make_material(Color(0.2, 0.2, 0.2), 0.01)
		lamp.material_override = lm
		lamp.position = Vector3(c.x + size.x / 2.0 - 0.03, c.y + size.y / 2.0 - 0.03, 0.012)
		holder.add_child(lamp)
		_flat_label(holder, a[2], Vector2(c.x - (0.02 if area != "lever" else 0.0), c.y + size.y / 2.0 - 0.032), 26)
		area_nodes[area] = {"plate": pm, "lamp": lm, "color": a[3]}
	# Shape buttons.
	var shape_pos: Array[Vector2] = [Vector2(-0.65, 0.225), Vector2(-0.45, 0.225), Vector2(-0.65, 0.095), Vector2(-0.45, 0.095)]
	for i in 4:
		_button(holder, "shape%d" % i, shape_pos[i], 0.045, Color(0.92, 0.92, 0.95))
		var sh := Node3D.new()
		sh.rotation.x = -TILT  # shapes stand upright in the world
		controls["shape%d" % i].cap.add_child(sh)
		sh.position = Vector3(0, 0, 0.035)
		shape_holders.append(sh)
	# Fuel colour buttons and the "mixed so far" dots.
	for i in 4:
		_button(holder, "fuel%d" % i, Vector2(-0.715 + i * 0.11, -0.25), 0.043, P.COLORS[i])
		var dot := MeshInstance3D.new()
		dot.mesh = main.sphere_mesh(0.018)
		dot.position = Vector3(-0.67 + i * 0.08, -0.115, 0.012)
		dot.visible = false
		holder.add_child(dot)
		fuel_dots.append(dot)
	# Wire sockets (numbered) and four coloured plugs on cables.
	for i in 4:
		var s := MeshInstance3D.new()
		s.mesh = main.cyl_mesh(0.03, 0.03, 0.014, 14)
		s.material_override = main.make_material(Color(0.08, 0.08, 0.1), 0.0)
		s.rotation.x = PI / 2.0
		s.position = Vector3(SOCKET_X[i], SOCKET_Y, 0.007)
		holder.add_child(s)
		var ring := MeshInstance3D.new()
		ring.mesh = main.cyl_mesh(0.036, 0.036, 0.008, 14)
		ring.material_override = main.make_material(Color(0.85, 0.75, 0.3), 0.3)
		ring.rotation.x = PI / 2.0
		ring.position = Vector3(SOCKET_X[i], SOCKET_Y, 0.004)
		holder.add_child(ring)
		_flat_label(holder, str(i + 1), Vector2(SOCKET_X[i], SOCKET_Y + 0.06), 40)
		var anchor := MeshInstance3D.new()
		anchor.mesh = main.box_mesh(Vector3(0.05, 0.03, 0.02))
		anchor.material_override = main.make_material(Color(0.15, 0.15, 0.18), 0.0)
		anchor.position = Vector3(SOCKET_X[i], ANCHOR_Y, 0.01)
		holder.add_child(anchor)
		var cable := MeshInstance3D.new()
		cable.mesh = main.cyl_mesh(0.007, 0.007, 1.0, 6)
		cable.material_override = main.make_material(P.COLORS[i].darkened(0.2), 0.0)
		holder.add_child(cable)
		cables.append(cable)
		var plug := Node3D.new()
		holder.add_child(plug)
		var pb := MeshInstance3D.new()
		pb.mesh = main.cyl_mesh(0.022, 0.026, 0.06, 12)
		pb.material_override = main.make_material(P.COLORS[i], 0.15)
		pb.rotation.x = PI / 2.0
		pb.position.z = 0.03
		plug.add_child(pb)
		plug.position = Vector3(SOCKET_X[i], PLUG_REST_Y, 0.0)
		plug_nodes.append(plug)
		controls["plug%d" % i] = {"pos": Vector2(SOCKET_X[i], PLUG_REST_Y), "r": 0.03, "h": 0.06, "kind": "grab", "cap": plug, "deck": surface}
	# Pressure dial with numbers 1-9 and a SET button.
	var face := MeshInstance3D.new()
	face.mesh = main.cyl_mesh(0.105, 0.105, 0.012, 24)
	face.material_override = main.make_material(Color(0.97, 0.95, 0.88), 0.0)
	face.rotation.x = PI / 2.0
	face.position = Vector3(DIAL_C.x, DIAL_C.y, 0.006)
	holder.add_child(face)
	for v in range(1, 10):
		var a := _dial_angle(v)
		_flat_label(holder, str(v), DIAL_C + Vector2(sin(a), cos(a)) * 0.088, 20, Color(0.15, 0.15, 0.2), 0.013)
	needle = Node3D.new()
	needle.position = Vector3(DIAL_C.x, DIAL_C.y, 0.014)
	holder.add_child(needle)
	var nb := MeshInstance3D.new()
	nb.mesh = main.box_mesh(Vector3(0.008, DIAL_R, 0.006))
	nb.material_override = main.make_material(Color(0.2, 0.2, 0.25), 0.0)
	nb.position = Vector3(0, DIAL_R / 2.0, 0)
	needle.add_child(nb)
	var knob := MeshInstance3D.new()
	knob.mesh = main.sphere_mesh(0.022)
	knob.material_override = main.make_material(Color(0.95, 0.3, 0.25), 0.3)
	knob.position = Vector3(0, DIAL_R, 0.012)
	needle.add_child(knob)
	controls["dial"] = {"pos": DIAL_C, "r": 0.03, "h": 0.04, "kind": "grab", "cap": needle, "deck": surface}
	_button(holder, "set", Vector2(0.615, 0.105), 0.035, Color(0.3, 0.85, 0.4))
	_flat_label(holder, "SET", Vector2(0.615, 0.05), 20)
	# Five flip switches with lamps, and a CHECK button.
	for i in P.SWITCH_COUNT:
		var x := 0.33 + i * 0.055
		var base := MeshInstance3D.new()
		base.mesh = main.box_mesh(Vector3(0.04, 0.06, 0.012))
		base.material_override = main.make_material(Color(0.15, 0.15, 0.18), 0.0)
		base.position = Vector3(x, -0.2, 0.006)
		holder.add_child(base)
		var pivot := Node3D.new()
		pivot.position = Vector3(x, -0.2, 0.012)
		holder.add_child(pivot)
		var stick := MeshInstance3D.new()
		stick.mesh = main.cyl_mesh(0.006, 0.008, 0.05, 6)
		stick.material_override = main.make_material(Color(0.85, 0.85, 0.9), 0.0)
		stick.rotation.x = PI / 2.0
		stick.position.z = 0.025
		pivot.add_child(stick)
		var tip := MeshInstance3D.new()
		tip.mesh = main.sphere_mesh(0.012)
		tip.material_override = main.make_material(Color(0.95, 0.95, 1.0), 0.0)
		tip.position.z = 0.05
		pivot.add_child(tip)
		switch_pivots.append(pivot)
		var lamp := MeshInstance3D.new()
		lamp.mesh = main.sphere_mesh(0.013)
		var lm: StandardMaterial3D = main.make_material(Color(0.2, 0.2, 0.2), 0.01)
		lamp.material_override = lm
		lamp.position = Vector3(x, -0.125, 0.01)
		holder.add_child(lamp)
		switch_lamps.append(lm)
		_flat_label(holder, str(i + 1), Vector2(x, -0.265), 20)
		controls["sw%d" % i] = {"pos": Vector2(x, -0.2), "r": 0.022, "h": 0.05, "kind": "button", "cap": null, "deck": surface}
	_button(holder, "check", Vector2(0.625, -0.2), 0.03, Color(0.3, 0.85, 0.4))
	_flat_label(holder, "CHECK", Vector2(0.625, -0.255), 18)
	# The big launch lever.
	var slot := MeshInstance3D.new()
	slot.mesh = main.box_mesh(Vector3(0.035, 0.4, 0.008))
	slot.material_override = main.make_material(Color(0.08, 0.08, 0.1), 0.0)
	slot.position = LEVER_PIVOT + Vector3(0, 0, 0.004)
	holder.add_child(slot)
	lever_pivot = Node3D.new()
	lever_pivot.position = LEVER_PIVOT
	holder.add_child(lever_pivot)
	var arm := MeshInstance3D.new()
	arm.mesh = main.cyl_mesh(0.01, 0.012, LEVER_LEN, 8)
	arm.material_override = main.make_material(Color(0.7, 0.72, 0.78), 0.0)
	arm.rotation.x = PI / 2.0
	arm.position.z = LEVER_LEN / 2.0
	lever_pivot.add_child(arm)
	var handle := MeshInstance3D.new()
	handle.mesh = main.sphere_mesh(0.034)
	handle.material_override = main.make_material(Color(0.95, 0.2, 0.2), 0.4)
	handle.position.z = LEVER_LEN
	lever_pivot.add_child(handle)
	controls["lever"] = {"pos": Vector2(LEVER_PIVOT.x, LEVER_PIVOT.y), "r": 0.04, "h": LEVER_LEN, "kind": "grab", "cap": lever_pivot, "deck": surface}
	main.set_layers(holder, main.PANEL_LAYER)


func _button(parent: Node3D, key: String, pos: Vector2, r: float, color: Color, ring_too: bool = true) -> void:
	if ring_too:
		var ring := MeshInstance3D.new()
		ring.mesh = main.cyl_mesh(r + 0.008, r + 0.008, 0.012, 16)
		ring.material_override = main.make_material(Color(0.1, 0.1, 0.12), 0.0)
		ring.rotation.x = PI / 2.0
		ring.position = Vector3(pos.x, pos.y, 0.006)
		parent.add_child(ring)
	var cap := Node3D.new()
	cap.position = Vector3(pos.x, pos.y, 0.0)
	parent.add_child(cap)
	var m := MeshInstance3D.new()
	m.mesh = main.cyl_mesh(r, r, 0.025, 16)
	m.material_override = main.make_material(color, 0.25)
	m.rotation.x = PI / 2.0
	m.position.z = 0.0125
	cap.add_child(m)
	controls[key] = {"pos": pos, "r": r, "h": 0.025, "kind": "button", "cap": cap, "deck": surface}


func _flat_label(parent: Node3D, text: String, pos: Vector2, font: int, color: Color = Color(1, 0.97, 0.88), z: float = 0.008) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = 0.0012
	l.outline_size = 6 if color.v > 0.5 else 0
	l.modulate = color
	l.position = Vector3(pos.x, pos.y, z)
	parent.add_child(l)
	return l


func _dial_angle(v: int) -> float:
	return deg_to_rad(-135.0 + (v - 1) * 270.0 / 8.0)


# --- Positions the bot (and anyone else) can aim for --------------------------

## The deck (main surface or a wing) a control key lives on.
func deck_of(key: String) -> Node3D:
	if key.begins_with("crank"):
		return wing_r
	if key.begins_with("hello"):
		return wing_l
	return surface


## Local (deck) position of a control's touch / grab point.
func control_local(key: String) -> Vector3:
	if key.begins_with("sock"):
		return Vector3(SOCKET_X[int(key.substr(4))], SOCKET_Y, 0.04)
	if key.begins_with("plug"):
		var plug: Node3D = plug_nodes[int(key.substr(4))]
		return plug.position + Vector3(0, 0, 0.05)
	if key == "dial":
		var a := _dial_angle(_dial_value())
		return Vector3(DIAL_C.x + sin(a) * DIAL_R, DIAL_C.y + cos(a) * DIAL_R, 0.03)
	if key.begins_with("dial"):  # "dial7": where the knob sits for value 7
		var a := _dial_angle(int(key.substr(4)))
		return Vector3(DIAL_C.x + sin(a) * DIAL_R, DIAL_C.y + cos(a) * DIAL_R, 0.03)
	if key == "lever":
		return _lever_handle()
	if key == "lever_pulled":
		return LEVER_PIVOT + Vector3(0, -sin(LEVER_MAX), cos(LEVER_MAX)) * LEVER_LEN
	if key == "crank":
		return _crank_point(crank_acc)
	if key.begins_with("crank@"):  # "crank@6.5": where the handle sits after winding 6.5 radians
		return _crank_point(float(key.substr(6)))
	var c: Dictionary = controls[key]
	var p: Vector2 = c.pos
	return Vector3(p.x, p.y, c.h)


## World position of a control, optionally lifted off its deck (for the bot's hovering hand).
func control_world(key: String, lift: float = 0.0) -> Vector3:
	var deck := deck_of(key)
	return deck.global_transform * (control_local(key) + Vector3(0, 0, lift))


func to_world(local: Vector3) -> Vector3:
	return surface.global_transform * local


func _lever_handle() -> Vector3:
	var rot := lerpf(-LEVER_MAX, LEVER_MAX, lever_pull)
	return LEVER_PIVOT + Vector3(0, -sin(rot), cos(rot)) * LEVER_LEN


func _crank_point(acc: float) -> Vector3:
	return Vector3(CRANK_C.x + cos(acc) * CRANK_R, CRANK_C.y + sin(acc) * CRANK_R, 0.075)


func _decks() -> Array:
	return [surface, wing_l, wing_r]


func _deck_size(deck: Node3D) -> Vector2:
	return Vector2(1.86, 0.8) if deck == surface else WING_SIZE


## Split-screen pointer: where a camera ray lands on the desk (surface or wings), lifted off it when
## dragging. Vector3.INF when it misses everything.
func pointer_point(from: Vector3, dir: Vector3, lifted: bool) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for deck in _decks():
		var d3: Node3D = deck
		if d3 == null:
			continue
		var n := d3.global_basis.z.normalized()
		var hit = Plane(n, d3.global_position).intersects_ray(from, dir)
		if hit == null:
			continue
		var local: Vector3 = d3.global_transform.affine_inverse() * (hit as Vector3)
		var half := _deck_size(d3) / 2.0 + Vector2(0.06, 0.06)
		var dist := from.distance_to(hit as Vector3)
		var inside := absf(local.x) < half.x and absf(local.y) < half.y
		if not inside and d3 != surface:
			continue
		if not inside:
			dist += 100.0  # off the desk: fall back to the main surface's plane
		if dist < best_d:
			best_d = dist
			local.z = 0.1 if lifted else 0.0
			best = d3.global_transform * local
	return best


# --- Hands ------------------------------------------------------------------

func update_panel(delta: float) -> void:
	anim_t += delta
	if not detail or not is_inside_tree():
		return
	if shown_rocket != main.rocket_n:
		shown_rocket = main.rocket_n
		_refresh()
	if main.net.mode != "client" and not main.players.is_empty():
		_handle_hands(main.players[0].panel_hands())
	_update_visuals(delta)


func _refresh() -> void:
	plug_drag.clear()
	lever_pull = 0.0
	reset_crank()
	var m: Dictionary = main.module("symbols")
	for i in 4:
		var h: Node3D = shape_holders[i]
		for c in h.get_children():
			c.queue_free()
		if not m.is_empty():
			var layout: Array = m.layout
			h.add_child(main.shape_node(int(layout[i]), 0.05))
		main.set_layers(h, main.PANEL_LAYER)
	if alien_holder != null:
		for c in alien_holder.get_children():
			c.queue_free()
		var al: Dictionary = main.module("alien")
		if not al.is_empty():
			var cast: Array = al.cast
			var a: Array = cast[int(al.pick)]
			alien_holder.add_child(main.alien_node(int(a[0]), int(a[1]), int(a[2]), 0.17))
		main.set_layers(alien_holder, main.PANEL_LAYER)


## After the pause menu: a trigger still held must be let go before it grabs anything again.
func block_held_grips() -> void:
	for id in ["l", "r", "p", "bot"]:
		grip_was[id] = true
	grabs.clear()
	lever_fired = false


func reset_crank() -> void:
	crank_acc = 0.0
	crank_turns = 0
	for id in grabs.keys():
		if grabs[id] == "crank":
			grabs.erase(id)


func _handle_hands(hands: Array) -> void:
	var invs := {}
	for deck in _decks():
		if deck != null:
			invs[deck] = (deck as Node3D).global_transform.affine_inverse()
	var seen := {}
	for h in hands:
		var id: String = h.id
		var wp: Vector3 = h.pos
		var grip: bool = h.grip
		var pointer: bool = h.pointer
		var was: bool = grip_was.get(id, false)
		grip_was[id] = grip
		if grabs.has(id):
			var key: String = grabs[id]
			var t: Transform3D = invs[deck_of(key)]
			var lp: Vector3 = t * wp
			if grip:
				_drag(key, lp)
			else:
				_release(key, lp)
				grabs.erase(id)
			continue
		if grip and not was:
			var key := _grab_target(wp, invs, pointer)
			if key != "":
				grabs[id] = key
				main.players[0].haptic(id, 0.4)
				main.local_sound("click", -6.0, 1.2)
				if key == "crank":
					var t: Transform3D = invs[wing_r]
					var lp: Vector3 = t * wp
					crank_last = atan2(lp.y - CRANK_C.y, lp.x - CRANK_C.x)
				continue
		for key in controls:
			var c: Dictionary = controls[key]
			if c.kind != "button":
				continue
			var t: Transform3D = invs[c.deck]
			var lp: Vector3 = t * wp
			var cp: Vector2 = c.pos
			var r: float = c.r
			var hh: float = c.h
			var inside := Vector2(lp.x, lp.y).distance_to(cp) < r + 0.012 and lp.z < hh + 0.02 and lp.z > -0.12
			if not inside:
				continue
			var tk: String = id + "|" + key
			seen[tk] = true
			if not touching.has(tk):
				_press(key, id)
	touching = seen


func _grab_target(wp: Vector3, invs: Dictionary, pointer: bool) -> String:
	var best := ""
	var best_d := 0.055 if pointer else 0.07
	var keys: Array[String] = ["dial", "lever"]
	if controls.has("crank"):
		keys.append("crank")
	var wires: Dictionary = main.module("wires")
	if not wires.is_empty() and not wires.done:
		var placed: Array = wires.placed
		for i in 4:
			if not placed.has(i):
				keys.append("plug%d" % i)
	for key in keys:
		var t: Transform3D = invs[deck_of(key)]
		var lp: Vector3 = t * wp
		var at := control_local(key)
		var d := INF
		if pointer:
			if absf(lp.z) < 0.25:
				d = Vector2(lp.x - at.x, lp.y - at.y).length()
		else:
			d = lp.distance_to(at)
		if key == "crank":
			d -= 0.015  # the crank knob is easy to catch
		if d < best_d:
			best_d = d
			best = key
	return best


func _press(key: String, hand_id: String) -> void:
	press_t[key] = 0.18
	main.players[0].haptic(hand_id, 0.5)
	if key.begins_with("fuel"):
		main.on_panel("fuel", [int(key.substr(4))])
	elif key.begins_with("shape"):
		main.on_panel("shape", [int(key.substr(5))])
	elif key.begins_with("sw"):
		main.on_panel("switch", [int(key.substr(2))])
	elif key.begins_with("hello"):
		main.on_panel("hello", [int(key.substr(5))])
	else:
		main.on_panel(key, [])


func _drag(key: String, lp: Vector3) -> void:
	if key.begins_with("plug"):
		plug_drag[int(key.substr(4))] = Vector3(clampf(lp.x, -0.88, 0.88), clampf(lp.y, -0.38, 0.38), 0.0)
	elif key == "dial":
		var a := atan2(lp.x - DIAL_C.x, lp.y - DIAL_C.y)
		var v := clampi(roundi((rad_to_deg(a) + 135.0) / 270.0 * 8.0) + 1, 1, 9)
		if v != _dial_value():
			main.on_panel("dial", [v])
			main.local_sound("click", -10.0, 0.8 + v * 0.08)
			main.players[0].haptic("r", 0.2)
	elif key == "lever":
		var rot := atan2(-(lp.y - LEVER_PIVOT.y), maxf(lp.z - LEVER_PIVOT.z, 0.04))
		lever_pull = clampf((rot + LEVER_MAX) / (2.0 * LEVER_MAX), 0.0, 1.0)
		if lever_pull > 0.85 and not lever_fired:
			lever_fired = true
			main.players[0].haptic("r", 1.0)
			main.on_panel("lever", [])
	elif key == "crank":
		var off := Vector2(lp.x - CRANK_C.x, lp.y - CRANK_C.y)
		if off.length() < 0.012:
			return  # too close to the axle to tell which way it's turning
		var a := atan2(off.y, off.x)
		crank_acc += wrapf(a - crank_last, -PI, PI)
		crank_last = a
		var turns := int(absf(crank_acc) / TAU)
		if turns != crank_turns:
			crank_turns = turns
			main.on_panel("crank", [turns])
			main.players[0].haptic("r", 0.7)


func _release(key: String, lp: Vector3) -> void:
	if key.begins_with("plug"):
		var color := int(key.substr(4))
		plug_drag.erase(color)
		for s in 4:
			if Vector2(lp.x - SOCKET_X[s], lp.y - SOCKET_Y).length() < 0.055:
				main.on_panel("plug", [color, s])
				break
	elif key == "lever":
		lever_fired = false


func _dial_value() -> int:
	var m: Dictionary = main.module("gauge")
	return 1 if m.is_empty() else int(m.value)


# --- Visuals ----------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for area in area_nodes:
		var n: Dictionary = area_nodes[area]
		var base: Color = n.color
		var pm: StandardMaterial3D = n.plate
		var lm: StandardMaterial3D = n.lamp
		var state := "off"
		if area == "lever":
			state = "on" if main.phase == "ready" else ("done" if main.phase == "launch" else "off")
		else:
			var m: Dictionary = main.module(area)
			if not m.is_empty():
				state = "done" if m.done else "on"
		match state:
			"on":
				pm.albedo_color = base
				lm.albedo_color = Color(1.0, 0.6, 0.15)
				lm.emission = lm.albedo_color
				lm.emission_energy_multiplier = 0.5 + 2.0 * blink
			"done":
				pm.albedo_color = base.lerp(Color(0.3, 0.75, 0.35), 0.6)
				lm.albedo_color = Color(0.3, 1.0, 0.4)
				lm.emission = lm.albedo_color
				lm.emission_energy_multiplier = 2.0
			_:
				pm.albedo_color = base.darkened(0.55).lerp(Color(0.25, 0.25, 0.28), 0.5)
				lm.albedo_color = Color(0.15, 0.15, 0.15)
				lm.emission_energy_multiplier = 0.0
	for key in press_t.keys():
		var t: float = press_t[key] - delta
		press_t[key] = t
		var c: Dictionary = controls[key]
		var cap: Node3D = c.cap
		if cap != null:
			cap.position.z = -0.014 if t > 0.0 else 0.0
		if t <= 0.0:
			press_t.erase(key)
	# Fuel dots.
	var fuel: Dictionary = main.module("fuel")
	var pressed: Array = [] if fuel.is_empty() else fuel.pressed
	for i in fuel_dots.size():
		var dot: MeshInstance3D = fuel_dots[i]
		dot.visible = i < pressed.size()
		if dot.visible:
			dot.material_override = main.color_mat(P.COLORS[int(pressed[i])], 0.6)
	# Plugs and cables.
	var wires: Dictionary = main.module("wires")
	var placed: Array = [-1, -1, -1, -1] if wires.is_empty() else wires.placed
	for i in 4:
		var target := Vector3(SOCKET_X[i], PLUG_REST_Y, 0.0)
		var s := placed.find(i)
		if s >= 0:
			target = Vector3(SOCKET_X[s], SOCKET_Y, -0.02)
		elif plug_drag.has(i):
			target = plug_drag[i]
		var plug: Node3D = plug_nodes[i]
		plug.position = plug.position.lerp(target, 1.0 - exp(-25.0 * delta))
		var a := Vector3(SOCKET_X[i], ANCHOR_Y, 0.012)
		var b := plug.position + Vector3(0, 0, 0.012)
		var cable: MeshInstance3D = cables[i]
		var d := b - a
		var length := maxf(d.length(), 0.01)
		var y := d / length
		var x := y.cross(Vector3(0, 0, 1)).normalized()
		if x.length() < 0.5:
			x = Vector3.RIGHT
		var z := x.cross(y).normalized()
		cable.transform = Transform3D(Basis(x, y * length, z), (a + b) / 2.0)
	# Dial needle.
	var target_rot := -_dial_angle(_dial_value())
	needle.rotation.z = lerp_angle(needle.rotation.z, target_rot, 1.0 - exp(-20.0 * delta))
	# Switches.
	var sw: Dictionary = main.module("switches")
	for i in P.SWITCH_COUNT:
		var on: bool = false if sw.is_empty() else bool(sw.state[i])
		var pv: Node3D = switch_pivots[i]
		pv.rotation.x = lerpf(pv.rotation.x, -0.45 if on else 0.45, 1.0 - exp(-25.0 * delta))
		var lm: StandardMaterial3D = switch_lamps[i]
		lm.albedo_color = Color(0.3, 1.0, 0.4) if on else Color(0.25, 0.12, 0.12)
		lm.emission = lm.albedo_color
		lm.emission_energy_multiplier = 2.0 if on else 0.0
	# Lever springs back when let go.
	if not grabs.values().has("lever"):
		lever_pull = move_toward(lever_pull, 0.0, delta * 2.5)
	lever_pivot.rotation.x = lerpf(-LEVER_MAX, LEVER_MAX, lever_pull)
	# Wings: the hologram alien bobs and spins, the crank shows its turns.
	if alien_holder != null:
		alien_holder.position.z = 0.1 + sin(anim_t * 2.2) * 0.012
		alien_holder.rotation.y = sin(anim_t * 0.8) * 0.6
		var al: Dictionary = main.module("alien")
		alien_beam.visible = not al.is_empty() and not al.done
		alien_holder.visible = alien_beam.visible
	if crank_wheel != null:
		crank_wheel.rotation.z = crank_acc
		crank_handle.position = _crank_point(crank_acc) - Vector3(0, 0, 0.075)
		var cm: Dictionary = main.module("crank")
		if cm.is_empty():
			crank_label.text = "TURNS\n-"
		elif cm.done:
			crank_label.text = "TURNS\nDONE"
		else:
			crank_label.text = "TURNS\n%d" % crank_turns
	if screen:
		screen.text = main.screen_text()
