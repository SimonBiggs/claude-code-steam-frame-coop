extends Node3D
## The TV crew's "manual": five big blueprint boards on the workshop walls, one per puzzle module.
## Their content is on MANUAL_LAYER, which the pilot's cameras never draw, so the crew have to read
## it out loud. Boards for modules this rocket doesn't need just snooze. Titles and the status bulb
## are on the normal layer so the pilot can see which board their friends are standing at.

const P := preload("res://games/rocket_workshop/puzzles.gd")
const BOARDS := {
	"fuel": [Vector3(-10.92, 1.9, -1.5), 90.0],
	"wires": [Vector3(-10.92, 1.9, 4.8), 90.0],
	"gauge": [Vector3(10.92, 1.9, -1.5), -90.0],
	"switches": [Vector3(10.92, 1.9, 4.8), -90.0],
	"symbols": [Vector3(0.0, 1.9, 7.92), 180.0],
}
const INK := Color(0.95, 0.97, 1.0)

var main
var boards := {}  # type -> {root, content, stamp, lamp, key}


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
		paper.material_override = main.make_material(Color(0.16, 0.35, 0.66), 0.05)
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
		main.set_layers(stamp, main.MANUAL_LAYER)
		boards[type] = {"root": root, "content": content, "stamp": stamp, "lamp": lm, "key": ""}


## Called every frame on both machines with the current rocket's modules.
func update_boards(modules: Array, rocket_n: int) -> void:
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
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
		var stamp: Label3D = b.stamp
		stamp.visible = done
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


func _rebuild(b: Dictionary, type: String, m: Dictionary) -> void:
	var content: Node3D = b.content
	for c in content.get_children():
		c.queue_free()
	if m.is_empty():
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
		if m.has("rows") and (m.rows as Array).size() > 1:
			_label(content, "Ask the pilot: what is this rocket called?", Vector3(0, -0.98, 0), 34, Color(1.0, 0.85, 0.4))
	main.set_layers(content, main.MANUAL_LAYER)


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
