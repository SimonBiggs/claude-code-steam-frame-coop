extends Node3D
## Something floating on the lake for the boats to scoop up with their nets.
## The host owns it; the TV machine mirrors kind + position from the snapshots.

const Lake := preload("res://games/fishing_lake/lake.gd")

const KINDS := [
	{"name": "Rubber Duck", "pts": 10, "col": Color(1.0, 0.85, 0.1)},
	{"name": "Message in a Bottle", "pts": 15, "col": Color(0.3, 0.75, 0.45)},
	{"name": "Water Lily", "pts": 5, "col": Color(1.0, 0.6, 0.85)},
	{"name": "Floating Crate", "pts": 20, "col": Color(0.7, 0.5, 0.3)},
]

var main
var kind := -1
var ghost := false
var drift := Vector3.ZERO
var t := 0.0
var net_pos := Vector3.ZERO
var built_kind := -2
var look: Node3D


func info() -> Dictionary:
	return KINDS[maxi(kind, 0)]


func spawn(k: int, pos: Vector3) -> void:
	kind = k
	position = pos
	drift = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * 0.15
	_rebuild()
	visible = true


func clear() -> void:
	kind = -1
	visible = false


func _rebuild() -> void:
	if built_kind == kind:
		return
	built_kind = kind
	if look != null:
		look.queue_free()
	look = Node3D.new()
	add_child(look)
	if kind < 0:
		return
	var col: Color = info()["col"]
	var mat: StandardMaterial3D = main.make_material(col, 0.25)
	match kind:
		0:
			var b := MeshInstance3D.new()
			b.mesh = main.sphere_mesh(0.22)
			b.scale = Vector3(1.0, 0.75, 1.25)
			b.material_override = mat
			look.add_child(b)
			var h := MeshInstance3D.new()
			h.mesh = main.sphere_mesh(0.13)
			h.material_override = mat
			h.position = Vector3(0, 0.22, 0.14)
			look.add_child(h)
			var beak := MeshInstance3D.new()
			beak.mesh = main.box_mesh(Vector3(0.08, 0.04, 0.1))
			beak.material_override = main.make_material(Color(1.0, 0.45, 0.1), 0.2)
			beak.position = Vector3(0, 0.2, 0.28)
			look.add_child(beak)
		1:
			var b := MeshInstance3D.new()
			b.mesh = main.cyl_mesh(0.08, 0.08, 0.36, 10)
			b.material_override = mat
			b.rotation.x = deg_to_rad(80.0)
			look.add_child(b)
			var paper := MeshInstance3D.new()
			paper.mesh = main.box_mesh(Vector3(0.08, 0.08, 0.2))
			paper.material_override = main.make_material(Color(1.0, 0.95, 0.8), 0.3)
			look.add_child(paper)
		2:
			var pad := MeshInstance3D.new()
			pad.mesh = main.cyl_mesh(0.32, 0.32, 0.03, 10)
			pad.material_override = main.make_material(Color(0.25, 0.6, 0.25), 0.0)
			look.add_child(pad)
			var flower := MeshInstance3D.new()
			flower.mesh = main.sphere_mesh(0.12)
			flower.scale = Vector3(1.0, 0.6, 1.0)
			flower.material_override = mat
			flower.position = Vector3(0, 0.07, 0)
			look.add_child(flower)
		_:
			var c := MeshInstance3D.new()
			c.mesh = main.box_mesh(Vector3(0.45, 0.35, 0.45))
			c.material_override = mat
			look.add_child(c)


func _process(delta: float) -> void:
	if kind < 0:
		visible = false
		return
	t += delta
	if ghost:
		if position.distance_to(net_pos) > 3.0:
			position = net_pos
		else:
			position = position.lerp(net_pos, 1.0 - exp(-8.0 * delta))
	if look != null:
		look.position.y = 0.04 + sin(t * 1.8) * 0.04
		look.rotation.y = t * 0.3
		look.rotation.z = sin(t * 1.3) * 0.08


## Host: drift slowly, bouncing off the shore and the jetty.
func sim(delta: float) -> void:
	if kind < 0 or ghost:
		return
	position += drift * delta
	var off := Vector3(position.x - Lake.LAKE_C.x, 0.0, position.z - Lake.LAKE_C.z)
	if off.length() > Lake.LAKE_R - 2.5:
		drift = -off.normalized() * drift.length()
	if position.z > Lake.JETTY_END_Z - 1.0 and absf(position.x) < 2.0:
		drift.z = -absf(drift.z)
	position.y = 0.0
