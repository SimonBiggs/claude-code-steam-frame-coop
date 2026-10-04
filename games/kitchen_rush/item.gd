extends Node3D
## An ingredient or a plate. The host owns the real ones; the TV machine draws ghosts from snapshots.

const L := preload("res://games/kitchen_rush/layout.gd")

# name, colour, chops needed
const INFO := {
	"bun": ["BUN", Color(0.96, 0.66, 0.28), 0],
	"patty": ["PATTY", Color(0.55, 0.29, 0.17), 0],
	"dough": ["DOUGH", Color(1.0, 0.92, 0.74), 0],
	"lettuce": ["LETTUCE", Color(0.38, 0.86, 0.3), 3],
	"tomato": ["TOMATO", Color(0.96, 0.2, 0.16), 3],
	"cucumber": ["CUCUMBER", Color(0.18, 0.62, 0.26), 3],
	"cheese": ["CHEESE", Color(1.0, 0.84, 0.2), 2],
	"plate": ["PLATE", Color(0.97, 0.97, 1.0), 0],
}

# Snapshots send small ints instead of strings (keeps a 30 Hz snapshot under the network MTU).
const KINDS := ["bun", "patty", "dough", "lettuce", "tomato", "cucumber", "cheese", "plate"]
const RECIPE_NAMES := ["SALAD", "TOASTIE", "BURGER", "PIZZA"]

var main
var kind := "lettuce"
var net_id := 0
var chops := 0
var holder := -1  # -1 nobody, 0 chef, 1-2 runner
var contents: Array = []  # plates: ingredient kinds in the order they were stacked
var recipe := ""  # plates: set when the stack matches a recipe ("DING!")
var home := -1  # plates: which plate spot it belongs to (-1 once it's a finished plate)
var chop_cd := 0.0
var ghost := false
var net_target := Vector3.ZERO
var net_started := false
var highlight := false
var squash := 0.0  # a chop squashes it for a moment
var visual: Node3D
var visual_key := ""
var label: Label3D


static func display_name(k: String) -> String:
	return INFO[k][0] if INFO.has(k) else k.to_upper()


static func color_of(k: String) -> Color:
	return INFO[k][1] if INFO.has(k) else Color.WHITE


static func chops_needed(k: String) -> int:
	return INFO[k][2] if INFO.has(k) else 0


func _ready() -> void:
	add_to_group("kr_items")
	net_target = position
	_rebuild()


func is_plate() -> bool:
	return kind == "plate"


func is_ready() -> bool:
	return chops >= chops_needed(kind)


func needs_chop() -> bool:
	return not is_plate() and not is_ready()


func _process(delta: float) -> void:
	chop_cd -= delta
	var key := "%s|%d|%s|%s" % [kind, chops, ",".join(PackedStringArray(contents)), recipe]
	if key != visual_key:
		_rebuild()
	if visual:
		var s := 1.18 if highlight else 1.0
		squash = maxf(0.0, squash - delta * 5.0)
		var want := Vector3(s * (1.0 + 0.35 * squash), s * (1.0 - 0.45 * squash), s * (1.0 + 0.35 * squash))
		visual.scale = visual.scale.lerp(want, 1.0 - exp(-14.0 * delta)) if squash <= 0.0 else want
	if holder >= 1 and holder < main.players.size():
		# Carried by a runner: always follow that runner (instant for our own runner on the TV).
		var p = main.players[holder]
		global_position = p.carry_point()
		rotation.y = p.yaw
		return
	if ghost:
		if not net_started:
			net_started = true
			global_position = net_target
		global_position = global_position.lerp(net_target, 1.0 - exp(-18.0 * delta))


static func kind_from(i: int) -> String:
	return KINDS[i] if i >= 0 and i < KINDS.size() else "plate"


static func recipe_from(i: int) -> String:
	return RECIPE_NAMES[i] if i >= 0 and i < RECIPE_NAMES.size() else ""


## Snapshot entry, packed as floats: [id, kind, x, y, z, chops, holder, recipe, contents...]
func net_state() -> PackedFloat32Array:
	var p := global_position
	var a := PackedFloat32Array([net_id, KINDS.find(kind), p.x, p.y, p.z, chops, holder, RECIPE_NAMES.find(recipe)])
	for k in contents:
		a.append(KINDS.find(k))
	return a


func apply_net(st: PackedFloat32Array) -> void:
	net_target = Vector3(st[2], st[3], st[4])
	chops = int(st[5])
	holder = int(st[6])
	recipe = recipe_from(int(st[7]))
	var c: Array = []
	for i in range(8, st.size()):
		c.append(kind_from(int(st[i])))
	if c != contents:
		contents = c


func _rebuild() -> void:
	visual_key = "%s|%d|%s|%s" % [kind, chops, ",".join(PackedStringArray(contents)), recipe]
	if visual:
		visual.queue_free()
	visual = Node3D.new()
	add_child(visual)
	if is_plate():
		_build_plate()
		return
	var need := chops_needed(kind)
	if need > 0 and chops >= need:
		_build_chopped()
	elif chops > 0:
		# Partly chopped: the ingredient falls apart into more and more pieces.
		var pieces := chops + 1
		for i in pieces:
			var piece := _raw_mesh()
			piece.scale = Vector3.ONE * (0.82 - 0.08 * chops)
			piece.position.x = (i - (pieces - 1) * 0.5) * (0.045 + 0.01 * chops)
			piece.rotation.z = (i - (pieces - 1) * 0.5) * 0.25
			visual.add_child(piece)
	else:
		visual.add_child(_raw_mesh())


func _mi(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = main.mat(color)
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _sphere(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 14
	s.rings = 7
	return s


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 1
	return c


## One whole raw ingredient, resting on y = 0.
func _raw_mesh() -> Node3D:
	var root := Node3D.new()
	var col := color_of(kind)
	match kind:
		"bun":
			root.add_child(_mi(_sphere(0.075, 0.075), col, Vector3(0, 0.045, 0)))
			root.add_child(_mi(_cyl(0.072, 0.025), col.darkened(0.15), Vector3(0, 0.0125, 0)))
		"patty":
			root.add_child(_mi(_cyl(0.07, 0.03), col, Vector3(0, 0.015, 0)))
		"dough":
			root.add_child(_mi(_sphere(0.075, 0.06), col, Vector3(0, 0.03, 0)))
		"lettuce":
			root.add_child(_mi(_sphere(0.08, 0.13), col, Vector3(0, 0.065, 0)))
			root.add_child(_mi(_sphere(0.05, 0.08), col.lightened(0.3), Vector3(0.02, 0.1, 0.02)))
		"tomato":
			root.add_child(_mi(_sphere(0.06, 0.11), col, Vector3(0, 0.055, 0)))
			root.add_child(_mi(_cyl(0.02, 0.02), Color(0.2, 0.6, 0.2), Vector3(0, 0.115, 0)))
		"cucumber":
			var cap := CapsuleMesh.new()
			cap.radius = 0.035
			cap.height = 0.22
			cap.radial_segments = 12
			cap.rings = 3
			var c := _mi(cap, col, Vector3(0, 0.035, 0))
			c.rotation.z = PI / 2.0
			root.add_child(c)
		"cheese":
			var b := BoxMesh.new()
			b.size = Vector3(0.13, 0.06, 0.09)
			root.add_child(_mi(b, col, Vector3(0, 0.03, 0)))
	return root


## Fully chopped: a neat little pile of slices.
func _build_chopped() -> void:
	var col := color_of(kind)
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(cos(a) * 0.045, 0.008 + (i % 3) * 0.012, sin(a) * 0.045)
		var mesh: Mesh
		if kind == "cheese":
			var b := BoxMesh.new()
			b.size = Vector3(0.035, 0.035, 0.035)
			mesh = b
		elif kind == "lettuce":
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.06, 0.01, 0.045)
			mesh = b2
		else:
			mesh = _cyl(0.032, 0.014)
		var m := _mi(mesh, col if i % 2 == 0 else col.lightened(0.2), p)
		m.rotation.y = a
		visual.add_child(m)
	var spark := _mi(_cyl(0.075, 0.004), Color(1.0, 1.0, 0.7), Vector3(0, 0.002, 0))
	spark.material_override = main.mat(Color(1.0, 1.0, 0.6), 1.2)
	visual.add_child(spark)


## A plate with the stacked ingredients; glows gold once it's a finished dish.
func _build_plate() -> void:
	visual.add_child(_mi(_cyl(0.13, 0.02), Color(0.97, 0.97, 1.0), Vector3(0, 0.01, 0)))
	visual.add_child(_mi(_cyl(0.1, 0.022), Color(0.85, 0.9, 1.0), Vector3(0, 0.012, 0)))
	var y := 0.025
	for k in contents:
		var col := color_of(k)
		var h := 0.025
		var r := 0.095
		match k:
			"bun":
				h = 0.035
			"patty":
				h = 0.028
				r = 0.085
			"dough":
				r = 0.11
				h = 0.018
			"cheese":
				h = 0.012
			"lettuce", "tomato", "cucumber":
				h = 0.016
		visual.add_child(_mi(_cyl(r, h), col, Vector3(0, y + h * 0.5, 0)))
		y += h
	if contents.size() > 0 and contents[contents.size() - 1] == "bun" and contents.has("patty"):
		visual.add_child(_mi(_sphere(0.095, 0.08), color_of("bun"), Vector3(0, y + 0.02, 0)))
	if recipe != "":
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.13
		tm.outer_radius = 0.15
		tm.rings = 16
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = main.mat(Color(1.0, 0.8, 0.2), 2.5)
		ring.position.y = 0.012
		visual.add_child(ring)
		label = Label3D.new()
		label.text = recipe
		label.font_size = 40
		label.outline_size = 14
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1.0, 0.9, 0.4)
		label.position.y = 0.28
		label.no_depth_test = true
		visual.add_child(label)
