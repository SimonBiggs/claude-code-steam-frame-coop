extends Node3D
## The TV crew's "manual": five big blueprint boards on the workshop walls, one per puzzle module.
## Their content is on MANUAL_LAYER, which the pilot's cameras never draw, so the crew have to read
## it out loud. Boards for modules this rocket doesn't need just snooze. Titles and the status bulb
## are on the normal layer so the pilot can see which board their friends are standing at.
## A bouncing arrow (crew only) hangs over every board that still needs reading.

const P := preload("res://games/rocket_workshop/puzzles.gd")
const BOARDS := {
	"fuel": [Vector3(-10.92, 1.9, -1.5), 90.0],
	"wires": [Vector3(-10.92, 1.9, 4.8), 90.0],
	"gauge": [Vector3(10.92, 1.9, -1.5), -90.0],
	"switches": [Vector3(10.92, 1.9, 4.8), -90.0],
	"symbols": [Vector3(0.0, 1.9, 7.92), 180.0],
	"alien": [Vector3(-8.2, 1.9, 7.92), 180.0],
	"crank": [Vector3(8.2, 1.9, 7.92), 180.0],
}
## Simple mode (main.simple): the boards are PICTURES only (glowing buttons, plugs in their sockets,
## shapes in a row, the dial's needle, switches up or down), no words. A board turns green when its
## puzzle is done and goes grey when this rocket doesn't need it. With nobody on the TV, update_solo()
## floats a small copy of the current blueprint behind the pilot's desk (pilot only).
const INK := Color(0.95, 0.97, 1.0)
const PAPER := Color(0.16, 0.35, 0.66)
const PAPER_OFF := Color(0.3, 0.32, 0.38)
const PAPER_DONE := Color(0.2, 0.55, 0.3)

var main
var boards := {}  # type -> {root, content, stamp, lamp, key, arrow}
var t := 0.0
var glow_mats := {}  # colour id -> pulsing material (simple mode's glowing buttons)
var solo: Node3D
var solo_content: Node3D
var solo_key := ""


func _ready() -> void:
	for type in BOARDS:
		var b: Array = BOARDS[type]
		var root := Node3D.new()
		root.position = b[0]
		root.rotation.y = deg_to_rad(b[1])
		add_child(root)
		var frame := MeshInstance3D.new()
		frame.mesh = main.box_mesh(Vector3(3.4, 2.45, 0.1))
		frame.material_override = main.make_material(Color(0.55, 0.36, 0.22), 0.0)
		root.add_child(frame)
		var paper := MeshInstance3D.new()
		paper.mesh = main.box_mesh(Vector3(3.2, 2.25, 0.02))
		var paper_mat: StandardMaterial3D = main.make_material(PAPER, 0.05)
		paper.material_override = paper_mat
		paper.position.z = 0.06
		root.add_child(paper)
		var sign := MeshInstance3D.new()
		sign.mesh = main.box_mesh(Vector3(2.2, 0.42, 0.08))
		sign.material_override = main.make_material(Color(0.98, 0.85, 0.45), 0.0)
		sign.position = Vector3(0, 1.48, 0.02)
		root.add_child(sign)
		var title := Label3D.new()
		title.text = P.TITLES[type]
		title.font_size = 72
		title.pixel_size = 0.004
		title.outline_size = 0
		title.modulate = Color(0.35, 0.2, 0.1)
		title.position = Vector3(0, 1.48, 0.07)
		title.visible = not main.simple
		root.add_child(title)
		var lamp := MeshInstance3D.new()
		lamp.mesh = main.sphere_mesh(0.14)
		var lm: StandardMaterial3D = main.make_material(Color(0.3, 0.3, 0.3), 0.01)
		lamp.material_override = lm
		lamp.position = Vector3(1.35, 1.48, 0.1)
		root.add_child(lamp)
		var content := Node3D.new()
		content.position.z = 0.08
		root.add_child(content)
		var stamp := _label(root, "DONE!", Vector3(0.2, 0.0, 0.2), 150, Color(0.4, 1.0, 0.45))
		stamp.rotation.z = 0.25
		stamp.outline_size = 30
		stamp.visible = false
		if main.simple:
			stamp.text = ""
		main.set_layers(stamp, main.MANUAL_LAYER)
		var arrow := MeshInstance3D.new()
		arrow.mesh = main.cyl_mesh(0.22, 0.0, 0.45, 10)
		arrow.material_override = main.make_material(Color(1.0, 0.6, 0.15), 1.6)
		arrow.position = Vector3(0, 2.05, 0.35)
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(arrow)
		main.set_layers(arrow, main.MANUAL_LAYER)
		boards[type] = {"root": root, "content": content, "stamp": stamp, "lamp": lm, "key": "", "arrow": arrow, "paper": paper_mat}


## Called every frame on both machines with the current rocket's modules.
func update_boards(modules: Array, rocket_n: int) -> void:
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	t += get_process_delta_time()
	for type in boards:
		var b: Dictionary = boards[type]
		var m: Dictionary = {}
		for mod in modules:
			if mod.type == type:
				m = mod
		var key := "%d:%s" % [rocket_n, "on" if not m.is_empty() else "off"]
		if key != b.key:
			b.key = key
			_rebuild(b, type, m)
		var done: bool = not m.is_empty() and m.done
		if main.simple:
			var pm: StandardMaterial3D = b.paper
			pm.albedo_color = PAPER_OFF if m.is_empty() else (PAPER_DONE if done else PAPER)
		var stamp: Label3D = b.stamp
		stamp.visible = done
		var arrow: MeshInstance3D = b.arrow
		arrow.visible = not m.is_empty() and not done
		if arrow.visible:
			arrow.position.y = 2.05 + absf(sin(t * 3.0)) * 0.25
			arrow.rotation.y = t * 2.0
		var lm: StandardMaterial3D = b.lamp
		if m.is_empty():
			lm.albedo_color = Color(0.3, 0.3, 0.3)
			lm.emission_energy_multiplier = 0.0
		elif done:
			lm.albedo_color = Color(0.3, 1.0, 0.4)
			lm.emission = lm.albedo_color
			lm.emission_energy_multiplier = 2.0
		else:
			lm.albedo_color = Color(1.0, 0.6, 0.15)
			lm.emission = lm.albedo_color
			lm.emission_energy_multiplier = 0.6 + 2.4 * blink
	for c in glow_mats:
		var gm: StandardMaterial3D = glow_mats[c]
		gm.emission_energy_multiplier = 0.4 + 2.6 * blink


func _rebuild(b: Dictionary, type: String, m: Dictionary) -> void:
	var content: Node3D = b.content
	for c in content.get_children():
		c.queue_free()
	if main.simple:
		if not m.is_empty():
			build_pictures(content, m)
	elif m.is_empty():
		_label(content, "Not needed for this rocket\n\nZzz...", Vector3(0, 0, 0), 56, Color(0.7, 0.75, 0.85))
	else:
		match type:
			"fuel":
				_build_fuel(content, m)
			"wires":
				_build_wires(content, m)
			"symbols":
				_build_symbols(content, m)
			"gauge":
				_build_gauge(content, m)
			"switches":
				_build_switches(content, m)
			"alien":
				_build_alien(content, m)
			"crank":
				_build_crank(content, m)
		if m.has("rows") and (m.rows as Array).size() > 1:
			_label(content, "Ask the pilot: what is this rocket called?", Vector3(0, -0.98, 0), 34, Color(1.0, 0.85, 0.4))
	main.set_layers(content, main.MANUAL_LAYER)


# --- Simple mode: picture blueprints ---------------------------------------------

## Builds the picture for module m into c (board space: about 3.2 x 2.25, facing +Z).
func build_pictures(c: Node3D, m: Dictionary) -> void:
	match str(m.type):
		"fuel":
			var answer: Array = m.answer
			var r := 0.42 if answer.size() == 1 else 0.32
			for k in answer.size():
				var x := (k - (answer.size() - 1) / 2.0) * 1.1
				_pic_button(c, int(answer[k]), Vector3(x, 0.0, 0.0), r)
		"wires":
			var order: Array = m.order
			for i in order.size():
				var x := (i - 1.5) * 0.7
				_disc(c, Vector3(x, 0.15, 0.0), 0.24, Color(0.85, 0.75, 0.3), 0.3)
				_disc(c, Vector3(x, 0.15, 0.02), 0.19, Color(0.06, 0.06, 0.08), 0.0)
				var col := int(order[i])
				if col >= 0:
					_blob(c, col, Vector3(x, 0.15, 0.1), 0.17)
					var cable := MeshInstance3D.new()
					cable.mesh = main.box_mesh(Vector3(0.06, 0.7, 0.03))
					cable.material_override = main.color_mat(P.COLORS[col].darkened(0.2), 0.0)
					cable.position = Vector3(x, -0.3, 0.06)
					c.add_child(cable)
		"symbols":
			var order: Array = m.order
			for i in order.size():
				var x := (i - (order.size() - 1) / 2.0) * 1.15
				var holder := Node3D.new()
				holder.position = Vector3(x, 0.0, 0.2)
				c.add_child(holder)
				holder.add_child(main.shape_node(int(order[i]), 0.42))
				if i + 1 < order.size():  # an arrow: this one first, then the next
					var arrow := MeshInstance3D.new()
					arrow.mesh = main.cyl_mesh(0.0, 0.12, 0.22, 8)
					arrow.material_override = main.color_mat(Color(1.0, 0.85, 0.3), 0.6)
					arrow.rotation.z = -PI / 2.0
					arrow.position = Vector3(x + 0.575, 0.0, 0.06)
					c.add_child(arrow)
		"gauge":
			_build_gauge(c, m)
		"switches":
			var pat: Array = m.answer
			for k in pat.size():
				var on: bool = pat[k]
				var x := (k - (pat.size() - 1) / 2.0) * 0.55
				var base := MeshInstance3D.new()
				base.mesh = main.box_mesh(Vector3(0.3, 0.5, 0.06))
				base.material_override = main.color_mat(Color(0.12, 0.12, 0.15), 0.0)
				base.position = Vector3(x, -0.15, 0.03)
				c.add_child(base)
				var stick := MeshInstance3D.new()
				stick.mesh = main.box_mesh(Vector3(0.08, 0.32, 0.06))
				stick.material_override = main.color_mat(Color(0.9, 0.9, 0.95), 0.0)
				stick.position = Vector3(x, -0.15 + (0.14 if on else -0.14), 0.09)
				c.add_child(stick)
				var lamp := MeshInstance3D.new()
				lamp.mesh = main.sphere_mesh(0.1)
				lamp.material_override = main.color_mat(Color(0.3, 1.0, 0.4), 1.5) if on else main.color_mat(Color(0.3, 0.15, 0.15), 0.0)
				lamp.position = Vector3(x, 0.4, 0.06)
				c.add_child(lamp)


func _disc(c: Node3D, pos: Vector3, r: float, color: Color, glow: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = main.cyl_mesh(r, r, 0.04, 20)
	mi.material_override = main.color_mat(color, glow)
	mi.rotation.x = PI / 2.0
	mi.position = pos
	c.add_child(mi)
	return mi


## A big round button like the desk's, glowing and pulsing.
func _pic_button(c: Node3D, color_id: int, pos: Vector3, r: float) -> void:
	_disc(c, pos, r + 0.06, Color(0.1, 0.1, 0.12), 0.0)
	if not glow_mats.has(color_id):
		glow_mats[color_id] = main.make_material(P.COLORS[color_id], 1.0)
	var cap := _disc(c, pos + Vector3(0, 0, 0.06), r, Color.WHITE, 0.0)
	cap.material_override = glow_mats[color_id]


## Simple mode, solo pilot: m is the blueprint to show ({} hides it). Pilot-only (PANEL_LAYER).
func update_solo(m: Dictionary, panel: Node3D) -> void:
	if m.is_empty():
		if solo != null:
			solo.visible = false
		return
	if solo == null:
		solo = Node3D.new()
		solo.name = "SoloBlueprint"
		add_child(solo)
		var frame := MeshInstance3D.new()
		frame.mesh = main.box_mesh(Vector3(3.4, 2.45, 0.1))
		frame.material_override = main.make_material(Color(0.55, 0.36, 0.22), 0.0)
		solo.add_child(frame)
		var paper := MeshInstance3D.new()
		paper.mesh = main.box_mesh(Vector3(3.2, 2.25, 0.02))
		paper.material_override = main.make_material(PAPER, 0.05)
		paper.position.z = 0.06
		solo.add_child(paper)
		solo_content = Node3D.new()
		solo_content.position.z = 0.08
		solo.add_child(solo_content)
		solo.scale = Vector3.ONE * 0.28
		main.set_layers(solo, main.PANEL_LAYER)
	solo.visible = true
	var top: float = panel.top
	solo.global_position = Vector3(0, top + 0.42, -1.55)  # just behind the desk, under the rocket
	var key := "%d:%s" % [main.rocket_n, m.type]
	if key != solo_key:
		solo_key = key
		for ch in solo_content.get_children():
			ch.queue_free()
		build_pictures(solo_content, m)
		main.set_layers(solo_content, main.PANEL_LAYER)


func _label(parent: Node3D, text: String, pos: Vector3, font: int, color: Color = INK) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = 0.004
	l.outline_size = maxi(8, font / 6)
	l.outline_modulate = Color(0.05, 0.1, 0.25)
	l.modulate = color
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = pos
	parent.add_child(l)
	return l


func _blob(parent: Node3D, color_id: int, pos: Vector3, r: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = main.sphere_mesh(r)
	mi.material_override = main.color_mat(P.COLORS[color_id], 0.3)
	mi.position = pos
	mi.scale = Vector3(1, 1, 0.5)
	parent.add_child(mi)


func _row_ys(count: int) -> Array:
	match count:
		1:
			return [0.05]
		2:
			return [0.3, -0.38]
	return [0.42, -0.08, -0.58]


func _build_fuel(c: Node3D, m: Dictionary) -> void:
	_label(c, "Press these colour buttons (any order):", Vector3(0, 0.88, 0), 36)
	var rows: Array = m.rows
	var ys := _row_ys(rows.size())
	var r := 0.17 if rows.size() == 1 else 0.11
	for i in rows.size():
		var row: Array = rows[i]
		var y: float = ys[i]
		var rname: String = row[0]
		var recipe: Array = row[1]
		var x0 := -0.25 if rname != "" else 0.0
		if rname != "":
			_label(c, rname + ":", Vector3(-1.05, y, 0), 48, Color(1.0, 0.9, 0.5))
		var step := r * 2.6
		for k in recipe.size():
			var x := x0 + (k - (recipe.size() - 1) / 2.0) * step
			_blob(c, int(recipe[k]), Vector3(x, y + 0.05, 0.02), r)
			_label(c, P.COLOR_NAMES[int(recipe[k])], Vector3(x, y - r - 0.04, 0.03), 20 if rows.size() > 1 else 26)


func _build_wires(c: Node3D, m: Dictionary) -> void:
	_label(c, "Plug each colour into its socket:", Vector3(0, 0.88, 0), 36)
	var order: Array = m.order
	for i in order.size():
		var y := 0.5 - i * 0.36
		var col := int(order[i])
		_label(c, "SOCKET %d" % (i + 1), Vector3(-0.65, y, 0), 48)
		_blob(c, col, Vector3(0.25, y, 0.02), 0.12)
		_label(c, P.COLOR_NAMES[col], Vector3(0.85, y, 0), 48, P.COLORS[col].lightened(0.3))
	if order.size() < 4:
		for col in 4:
			if not order.has(col):
				_label(c, "Leave the %s plug alone!" % P.COLOR_NAMES[col], Vector3(0, -0.72, 0), 34, Color(1.0, 0.75, 0.7))


func _build_symbols(c: Node3D, m: Dictionary) -> void:
	_label(c, "Press the shape buttons in this order:", Vector3(0, 0.88, 0), 36)
	var order: Array = m.order
	for i in order.size():
		var x := (i - (order.size() - 1) / 2.0) * 0.72
		var id := int(order[i])
		_label(c, str(i + 1), Vector3(x, 0.5, 0), 72, Color(1.0, 0.9, 0.5))
		var holder := Node3D.new()
		holder.position = Vector3(x, 0.0, 0.15)
		c.add_child(holder)
		holder.add_child(main.shape_node(id, 0.36))
		_label(c, P.SHAPE_NAMES[id], Vector3(x, -0.45, 0), 34)


func _build_gauge(c: Node3D, m: Dictionary) -> void:
	if not main.simple:
		_label(c, "Turn the dial to this number, then press SET:", Vector3(0, 0.88, 0), 34)
	var rows: Array = m.rows
	var xs: Array = [[0.0], [-0.75, 0.75], [-1.05, 0.0, 1.05]][rows.size() - 1]
	var rad := 0.5 if rows.size() == 1 else 0.36
	for i in rows.size():
		var row: Array = rows[i]
		var x: float = xs[i]
		var rname: String = row[0]
		var target := int(row[1])
		var center := Vector3(x, 0.05, 0.02)
		if rname != "":
			_label(c, rname, Vector3(x, 0.62, 0), 40, Color(1.0, 0.9, 0.5))
		var face := MeshInstance3D.new()
		face.mesh = main.cyl_mesh(rad, rad, 0.03, 28)
		face.material_override = main.color_mat(Color(0.97, 0.95, 0.88), 0.0)
		face.rotation.x = PI / 2.0
		face.position = center
		c.add_child(face)
		for v in range(1, 10):
			var a := deg_to_rad(-135.0 + (v - 1) * 33.75)
			var l := _label(c, str(v), center + Vector3(sin(a), cos(a), 0) * rad * 0.78 + Vector3(0, 0, 0.03), 22 if rows.size() > 1 else 30, Color(0.15, 0.15, 0.25))
			l.outline_size = 0
		var ta := deg_to_rad(-135.0 + (target - 1) * 33.75)
		var needle := MeshInstance3D.new()
		needle.mesh = main.box_mesh(Vector3(0.035, rad * 0.62, 0.02))
		needle.material_override = main.color_mat(Color(0.95, 0.25, 0.2), 0.3)
		needle.position = center + Vector3(sin(ta), cos(ta), 0) * rad * 0.31 + Vector3(0, 0, 0.04)
		needle.rotation.z = -ta
		c.add_child(needle)
		if main.simple:  # a glowing dot where the needle points
			var dot := MeshInstance3D.new()
			dot.mesh = main.sphere_mesh(0.07)
			dot.material_override = main.color_mat(Color(1.0, 0.85, 0.2), 1.5)
			dot.position = center + Vector3(sin(ta), cos(ta), 0) * rad * 0.98 + Vector3(0, 0, 0.05)
			c.add_child(dot)
		else:
			_label(c, str(target), Vector3(x, center.y - rad - 0.16, 0), 64, Color(1.0, 0.9, 0.5))


func _build_switches(c: Node3D, m: Dictionary) -> void:
	_label(c, "Flip the switches like this, then press CHECK:", Vector3(0, 0.88, 0), 32)
	var rows: Array = m.rows
	var ys := _row_ys(rows.size())
	for i in rows.size():
		var row: Array = rows[i]
		var y: float = ys[i]
		var rname: String = row[0]
		var pat: Array = row[1]
		var x0 := 0.3 if rname != "" else 0.0
		if rname != "":
			_label(c, rname + ":", Vector3(-1.05, y, 0), 44, Color(1.0, 0.9, 0.5))
		for k in pat.size():
			var on: bool = pat[k]
			var x := x0 + (k - 2) * 0.3
			var box := MeshInstance3D.new()
			box.mesh = main.box_mesh(Vector3(0.22, 0.3, 0.04))
			box.material_override = main.color_mat(Color(0.3, 0.85, 0.4) if on else Color(0.45, 0.15, 0.15), 0.4 if on else 0.0)
			box.position = Vector3(x, y + 0.02, 0.02)
			c.add_child(box)
			_label(c, "UP" if on else "DOWN", Vector3(x, y + 0.02, 0.05), 22)
			_label(c, str(k + 1), Vector3(x, y - 0.21, 0.0), 22)


func _build_alien(c: Node3D, m: Dictionary) -> void:
	_label(c, "Ask the pilot: what does YOUR alien look like?", Vector3(0, 0.9, 0), 32)
	_label(c, "Find it here, then tell them which hello button to press!", Vector3(0, 0.72, 0), 26, Color(1.0, 0.9, 0.55))
	var cast: Array = m.cast
	var n := cast.size()
	var cols := 4 if n <= 4 else 3
	for i in n:
		var a: Array = cast[i]
		var col := i % cols
		var row := i / cols
		var x := (col - (cols - 1) / 2.0) * (0.78 if cols == 4 else 1.0)
		var y := 0.05 if n <= 4 else (0.32 - row * 0.86)
		var holder := Node3D.new()
		holder.position = Vector3(x, y + 0.12, 0.12)
		c.add_child(holder)
		holder.add_child(main.alien_node(int(a[0]), int(a[1]), int(a[2]), 0.32))
		var word := int(a[3])
		_label(c, P.HELLO_WORDS[word], Vector3(x, y - 0.2, 0.04), 46, P.HELLO_COLORS[word].lightened(0.2))
		var eyes := int(a[1])
		var desc := "%s, %d eye%s,\n%s" % [P.ALIEN_COLOR_NAMES[int(a[0])], eyes, "" if eyes == 1 else "s", P.ALIEN_TOPS[int(a[2])]]
		_label(c, desc, Vector3(x, y - 0.36, 0.04), 18, Color(0.85, 0.9, 1.0))


func _build_crank(c: Node3D, m: Dictionary) -> void:
	_label(c, "Wind the crank round this many times, then press GO:", Vector3(0, 0.88, 0), 30)
	var rows: Array = m.rows
	var xs: Array = [[0.0], [-0.75, 0.75], [-1.05, 0.0, 1.05]][rows.size() - 1]
	for i in rows.size():
		var row: Array = rows[i]
		var x: float = xs[i]
		var rname: String = row[0]
		var turns := int(row[1])
		if rname != "":
			_label(c, rname, Vector3(x, 0.55, 0), 40, Color(1.0, 0.9, 0.5))
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.26
		tm.outer_radius = 0.32
		tm.rings = 20
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = main.color_mat(Color(0.95, 0.55, 0.2), 0.3)
		ring.rotation.x = PI / 2.0
		ring.position = Vector3(x, 0.02, 0.03)
		c.add_child(ring)
		var head := MeshInstance3D.new()
		head.mesh = main.cyl_mesh(0.0, 0.08, 0.14, 8)
		head.material_override = ring.material_override
		head.position = Vector3(x + 0.29, 0.02, 0.05)
		head.rotation.z = PI
		c.add_child(head)
		_label(c, str(turns), Vector3(x, 0.02, 0.06), 110, Color(1.0, 0.95, 0.6))
		_label(c, "TIMES", Vector3(x, -0.45, 0), 40)
