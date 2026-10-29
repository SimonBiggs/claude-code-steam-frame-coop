extends Node3D
## PUFF and his cloud friends (story.gd), drawn on every machine from numbers the host sends:
##  - PUFF, a little blue-white cloud with a face, bobs over the start;
##  - this course's LOST FRIEND sits on its side island (a cloud in its own colour, sad until found);
##  - every friend the family has rescued floats in a slow ring high over the course (saved: it grows).
## Cheap: one shared cloud mesh, tinted per friend with a material each (at most 16 + 2 clouds).

const MeshKit := preload("res://core/mesh_kit.gd")
const Story := preload("res://games/block_builders/story.gd")

var puff: Node3D
var lost: Node3D
var flock: Array[Node3D] = []
var rescued: Array = []
var lost_id := -1
var lost_pos := Vector3.ZERO
var start := Vector3.ZERO
var _t := 0.0
var _cheer := 0.0


func _ready() -> void:
	puff = _cloud(Story.PUFF_COLOR, 1.0)
	add_child(puff)
	lost = _cloud(Color.WHITE, 0.8)
	lost.visible = false
	add_child(lost)


## A round cloud with two eyes and a smile, about `size` units across, origin at its middle.
static func _cloud(col: Color, size: float) -> Node3D:
	var root := Node3D.new()
	var b := MeshKit.builder()
	for p in [Vector3(0, 0, 0), Vector3(-0.32, -0.06, 0.02), Vector3(0.32, -0.06, 0.02), Vector3(-0.16, 0.18, -0.04), Vector3(0.18, 0.16, -0.04)]:
		b.sphere(0.28 if p == Vector3.ZERO else 0.22, MeshKit.at(p), Color.WHITE, 10)
	var body := MeshKit.instance(b.build(), false)
	body.material_override = MeshKit.material(col, 0.25).duplicate()  # its own (tinted per friend)
	body.name = "Body"
	root.add_child(body)
	var f := MeshKit.builder()
	for sx in [-0.1, 0.1]:
		f.sphere(0.055, MeshKit.at(Vector3(sx, 0.04, 0.26)), Color(0.08, 0.08, 0.12), 8)
		f.sphere(0.018, MeshKit.at(Vector3(sx + 0.015, 0.06, 0.31)), Color.WHITE, 6)
	f.torus(0.07, 0.015, MeshKit.at(Vector3(0, -0.06, 0.26), Vector3(1, 1, 0.4), Vector3(PI * 0.5, 0, 0)), Color(0.35, 0.15, 0.2), 10, 4)
	var face := MeshKit.instance(f.build(), false)
	root.add_child(face)
	root.scale = Vector3.ONE * size
	return root


## The course changed (every machine): where Puff waits and where this course's friend is lost.
func set_course(start_pos: Vector3, friend_pos: Variant, friend_id: int) -> void:
	start = start_pos
	lost_id = friend_id
	if friend_pos is Vector3 and friend_id >= 0:
		lost_pos = friend_pos
		var col: Color = Story.FRIENDS[friend_id % Story.FRIENDS.size()][1]
		_tint(lost, col)
		lost.visible = true
	else:
		lost.visible = false


## The rescued friends (indices into story.gd FRIENDS); a new one flies up to the flock.
func set_rescued(list: Array) -> void:
	if var_to_str(list) == var_to_str(rescued):
		return
	var grew := list.size() > rescued.size() and _t > 1.0
	rescued = list.duplicate()
	while flock.size() < rescued.size():
		var c := _cloud(Color.WHITE, 0.7)
		add_child(c)
		flock.append(c)
	for i in flock.size():
		flock[i].visible = i < rescued.size()
		if i < rescued.size():
			var col: Color = Story.FRIENDS[int(rescued[i]) % Story.FRIENDS.size()][1]
			_tint(flock[i], col)
	if grew:
		lost.visible = false
		_cheer = 2.0
		if not flock.is_empty():
			flock[rescued.size() - 1].position = lost_pos


static func _tint(cloud: Node3D, col: Color) -> void:
	var m := (cloud.get_node("Body") as MeshInstance3D).material_override as StandardMaterial3D
	m.albedo_color = col
	if m.emission_enabled:
		m.emission = col


func _process(delta: float) -> void:
	_t += delta
	_cheer = maxf(0.0, _cheer - delta)
	puff.position = start + Vector3(-1.2, 2.6 + sin(_t * 1.6) * 0.15 + (sin(_t * 14.0) * 0.2 if _cheer > 0.0 else 0.0), -1.0)
	puff.rotation.y = sin(_t * 0.7) * 0.3
	if lost.visible:
		lost.position = lost_pos + Vector3(0, 0.9 + sin(_t * 2.2) * 0.12, 0)
		lost.rotation.z = sin(_t * 3.0) * 0.12  # a little worried wobble
	var n := rescued.size()
	for i in mini(n, flock.size()):
		var a := _t * 0.12 + TAU * float(i) / float(maxi(n, 1))
		var want := Vector3(cos(a) * 9.0, 7.0 + sin(_t * 1.3 + i) * 0.4, sin(a) * 4.0 - 1.0)
		flock[i].position = flock[i].position.lerp(want, minf(1.0, delta * 1.5))
