extends Node3D
## OBSTACLE RUSH: COACH JELLY'S MEDAL HALL (deep.gd). Every show the family finishes hangs a medal on the hall's boards
## behind the grandstand for good: a bronze one on a green ribbon for a GENTLE show, silver on blue for BRAVE, gold on
## red for HARD. The left board fills first (HALL_ROW x 3), then a second board goes up on the right; every
## deep.gd TROPHY_EVERY medals a little gold cup appears on top. Saved on the host (medals) and sent as the "medals"
## state [total, [mode of each shown medal, oldest first]], so every machine draws the same hall. The newest medal
## swings in. One merged mesh for the boards, one per medal row: cheap.
##   set_medals(total, modes)

const MeshKit := preload("res://core/mesh_kit.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/obstacle_rush/deep.gd")

const TABLE_Y := -3.5  # (giant.gd TABLE_Y)
const Z := -7.9  # just in front of the table's far edge, behind the flag board's poles (main.gd board z -7.8)
const BOARD_X: Array[float] = [-13.5, 13.5]  # the two boards' middles (the flag board is x -6..7)
const BOARD_W := 8.6
const BOARD_BOTTOM := 3.1  # above the table: over the grandstand's back rail (stands.gd: 2.9)
const BOARD_H := 3.5  # low enough for the TV view over it to the course's near side
const ROWS := 3
const PER_BOARD := Deep.HALL_ROW * ROWS
const WOOD := Color(0.62, 0.42, 0.26)
const WOOD_DARK := Color(0.45, 0.3, 0.18)

var total := -1
var shown: Array = []
var boards: MeshInstance3D
var medals_mi: MeshInstance3D
var newest: Node3D
var swing := 0.0
var _t := 0.0


func set_medals(n: int, modes: Array) -> void:
	if n == total and var_to_str(modes) == var_to_str(shown):
		return
	var grew := total >= 0 and n > total
	total = n
	shown = modes.duplicate()
	for node in [boards, medals_mi, newest]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	newest = null
	var count := mini(shown.size(), PER_BOARD * BOARD_X.size())
	var b := MeshKit.Builder.new()
	var n_boards := 1 if count <= PER_BOARD else 2
	for k in n_boards:
		var cx: float = BOARD_X[k]
		var y0 := TABLE_Y + BOARD_BOTTOM
		b.box(Vector3(BOARD_W, BOARD_H, 0.2), MeshKit.at(Vector3(cx, y0 + BOARD_H * 0.5, Z - 0.15)), WOOD)
		b.box(Vector3(BOARD_W + 0.3, 0.25, 0.3), MeshKit.at(Vector3(cx, y0 + BOARD_H + 0.1, Z - 0.15)), WOOD_DARK)
		for s in [-1.0, 1.0]:
			b.cylinder(0.12, 0.14, BOARD_BOTTOM + BOARD_H, MeshKit.at(Vector3(cx + s * (BOARD_W * 0.5 - 0.3), TABLE_Y + (BOARD_BOTTOM + BOARD_H) * 0.5, Z - 0.3)), WOOD_DARK, 8)
		for row in ROWS:  # a hook rail per row
			b.box(Vector3(BOARD_W - 0.6, 0.06, 0.08), MeshKit.at(Vector3(cx, _row_y(row) + 0.42, Z - 0.02)), Color(0.85, 0.8, 0.7))
	for k in Deep.trophies(n):  # little gold cups on top
		var tx: float = BOARD_X[0] - BOARD_W * 0.5 + 1.2 + k * 2.0
		var ty := TABLE_Y + BOARD_BOTTOM + BOARD_H + 0.22
		b.cylinder(0.25, 0.3, 0.15, MeshKit.at(Vector3(tx, ty + 0.08, Z - 0.15)), Color(1.0, 0.82, 0.25), 12)
		b.cylinder(0.05, 0.05, 0.3, MeshKit.at(Vector3(tx, ty + 0.3, Z - 0.15)), Color(1.0, 0.82, 0.25), 6)
		b.cylinder(0.32, 0.16, 0.42, MeshKit.at(Vector3(tx, ty + 0.65, Z - 0.15)), Color(1.0, 0.82, 0.25), 14)
	boards = MeshKit.instance(b.build(), false)
	boards.name = "HallBoards"
	add_child(boards)
	var mb := MeshKit.Builder.new()
	var added := 0
	for i in count:
		if grew and i == count - 1:
			continue  # the newest one swings in by itself
		_medal(mb, _spot(i), String(shown[i]), Vector3.ZERO)
		added += 1
	if added > 0:
		medals_mi = MeshKit.instance(mb.build(), false)
		medals_mi.name = "Medals"
		add_child(medals_mi)
	if grew and count > 0:
		var one := MeshKit.Builder.new()
		_medal(one, Vector3.ZERO, String(shown[count - 1]), Vector3.ZERO)
		newest = Node3D.new()
		newest.name = "NewMedal"
		newest.position = _spot(count - 1) + Vector3(0.0, 0.42, 0.0)
		var mi := MeshKit.instance(one.build(), false)
		mi.position = Vector3(0.0, -0.42, 0.0)
		newest.add_child(mi)
		add_child(newest)
		swing = 1.0


func _process(delta: float) -> void:
	_t += delta
	if newest != null and is_instance_valid(newest):
		swing = move_toward(swing, 0.0, delta * 0.4)
		newest.rotation.z = sin(_t * 5.0) * 0.5 * swing
		var s := 1.0 + swing * 0.4
		newest.scale = Vector3(s, s, s)


func _row_y(row: int) -> float:
	return TABLE_Y + BOARD_BOTTOM + BOARD_H - 0.75 - row * 1.1


## Medal i's middle (the left board first, oldest top left).
func _spot(i: int) -> Vector3:
	var k := i / PER_BOARD
	var j := i % PER_BOARD
	var cx: float = BOARD_X[mini(k, BOARD_X.size() - 1)]
	var x := cx - BOARD_W * 0.5 + 0.8 + float(j % Deep.HALL_ROW) * ((BOARD_W - 1.6) / float(Deep.HALL_ROW - 1))
	return Vector3(x, _row_y(j / Deep.HALL_ROW), Z + 0.05)


## A medal at p: a disc facing the course on a V ribbon in its mode's colour.
static func _medal(b: MeshKit.Builder, p: Vector3, mode: String, _rot: Vector3) -> void:
	var ribbon := PickOrbs.mode_color(Deep.mode_of(mode), Color(0.4, 0.6, 1.0))
	b.box(Vector3(0.12, 0.42, 0.03), MeshKit.at(p + Vector3(-0.09, 0.24, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.35)), ribbon)
	b.box(Vector3(0.12, 0.42, 0.03), MeshKit.at(p + Vector3(0.09, 0.24, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.35)), ribbon)
	var disc := Deep.medal_color(mode)
	b.cylinder(0.27, 0.27, 0.07, MeshKit.at(p, Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), disc, 16)
	b.star(5, 0.15, 0.07, 0.03, MeshKit.at(p + Vector3(0.0, 0.0, 0.05)), disc.lightened(0.35), true)
