extends Node3D
## Queen Bea's JAR SHELF behind the hive: every honey jar the family ever filled stands on it (saved,
## story.gd), four shelves of eight; past that the jars turn gold one by one. QUEEN BEA herself sits on
## the hive roof: a round bee in a gold crown who bobs, buzzes her wings and does a happy spin when a
## round's jars go up on the shelf. Same on the host and every TV (the jar count comes in the snapshot).
## Where it stands must match gardengen.gd OBSTACLES (bees never fly through it; the test checks).

const W := preload("res://games/bee_garden/world.gd")
const Story := preload("res://games/bee_garden/story.gd")

const POS := Vector3(-5.5, W.LAWN_Y, -2.35)
const BOARDS: Array[float] = [1.2, 2.1, 3.0, 3.9]   # board heights above the lawn
const WIDTH := 2.0

var jars := -1
var jar_mesh: MeshInstance3D
var queen: Node3D
var wings: Array[Node3D] = []
var t := 0.0
var spin := 0.0


func _ready() -> void:
	name = "JarShelf"
	position = POS
	var st := W._st()
	var wood := Color(0.62, 0.42, 0.25)
	for sx in [-1.0, 1.0]:
		W.vbox(st, Vector3(sx * (WIDTH * 0.5 + 0.04), 2.2, 0.0), Vector3(0.08, 4.4, 0.5), wood.darkened(0.15))
	W.vbox(st, Vector3(0, 2.2, -0.24), Vector3(WIDTH + 0.16, 4.4, 0.04), wood.darkened(0.3))
	for y in BOARDS:
		W.vbox(st, Vector3(0, y - 0.03, 0.0), Vector3(WIDTH + 0.08, 0.06, 0.5), wood)
	W.vbox(st, Vector3(0, 4.42, 0.0), Vector3(WIDTH + 0.2, 0.06, 0.56), wood.darkened(0.1))
	var mi := MeshInstance3D.new()
	mi.mesh = W.vmesh(st)
	add_child(mi)
	jar_mesh = MeshInstance3D.new()
	jar_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(jar_mesh)
	_build_queen()
	set_jars(0)


## Show `n` jars ever filled (rebuilds the jar mesh only when it changes).
func set_jars(n: int) -> void:
	if n == jars:
		return
	jars = n
	var sh: Array = Story.shelf(n)
	var total: int = int(sh[0]) + int(sh[1])
	var st := W._st()
	for i in total:
		var gold := i < int(sh[1])
		var row := i / 8
		var col := i % 8
		var p := Vector3(-WIDTH * 0.5 + 0.125 + col * 0.25, BOARDS[row] + 0.13, 0.05)
		W.vcyl(st, p, 0.095, 0.095, 0.24, Color(1.0, 0.85, 0.3) if gold else Color(1.0, 0.65, 0.1), 10)
		W.vcyl(st, p + Vector3(0, 0.14, 0), 0.105, 0.105, 0.05, Color(1.0, 0.9, 0.35) if gold else Color(0.9, 0.28, 0.28), 10)
		W.vbox(st, p + Vector3(0, 0.0, 0.096), Vector3(0.1, 0.08, 0.005), Color(1.0, 0.97, 0.85))
	if total > 0:
		jar_mesh.mesh = W.vmesh(st, 0.15)
	else:
		jar_mesh.mesh = null


## A round's jars went up on the shelf: Queen Bea spins with joy.
func cheer() -> void:
	spin = 1.0


func _build_queen() -> void:
	queen = Node3D.new()
	queen.name = "QueenBea"
	add_child(queen)
	var st := W._st()
	var yellow := Color(1.0, 0.8, 0.15)
	var dark := Color(0.18, 0.12, 0.07)
	W.vsphere(st, Vector3.ZERO, Vector3(0.26, 0.24, 0.32), yellow, 12, 7)
	for z in [0.02, 0.16]:
		W.vsphere(st, Vector3(0, 0, z), Vector3(0.265, 0.245, 0.04), dark, 12, 5)
	W.vsphere(st, Vector3(0, 0.05, -0.3), Vector3(0.17, 0.17, 0.16), yellow, 10, 6)
	for sx in [-1.0, 1.0]:
		W.vsphere(st, Vector3(sx * 0.07, 0.1, -0.43), Vector3(0.045, 0.05, 0.03), Color.WHITE, 8, 4)
		W.vsphere(st, Vector3(sx * 0.07, 0.1, -0.455), Vector3(0.025, 0.03, 0.015), dark, 6, 3)
		W.vsphere(st, Vector3(sx * 0.11, 0.0, -0.42), Vector3(0.035, 0.02, 0.01), Color(1.0, 0.55, 0.55), 6, 3)
		W.vcyl(st, Vector3(sx * 0.06, 0.28, -0.36), 0.008, 0.012, 0.16, dark, 4)
		W.vsphere(st, Vector3(sx * 0.07, 0.36, -0.37), Vector3(0.025, 0.025, 0.025), dark, 6, 3)
	# The crown: a gold band with five points and a pink jewel.
	var gold := Color(1.0, 0.85, 0.2)
	W.vcyl(st, Vector3(0, 0.25, -0.28), 0.1, 0.1, 0.07, gold, 12)
	for k in 5:
		var a := k * TAU / 5.0
		W.vcyl(st, Vector3(cos(a) * 0.085, 0.32, -0.28 + sin(a) * 0.085), 0.0, 0.03, 0.08, gold, 5)
	W.vsphere(st, Vector3(0, 0.25, -0.385), Vector3(0.025, 0.025, 0.012), Color(1.0, 0.35, 0.5), 6, 3)
	var body := MeshInstance3D.new()
	body.mesh = W.vmesh(st)
	queen.add_child(body)
	for sx in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(sx * 0.12, 0.2, 0.02)
		wing.set_meta("side", sx)
		queen.add_child(wing)
		var wm := W.mesh_node(wing, W.sphere(0.2, 8), W.cmat(Color(0.92, 0.97, 1.0)), Vector3(sx * 0.16, 0.0, 0.0), Vector3(1.0, 0.12, 0.55))
		wm.transparency = 0.35
		wings.append(wing)
	# She sits on the hive roof (world.gd HIVE_POS), facing the garden.
	queen.position = W.HIVE_POS + Vector3(0.0, 1.42, 0.0) - POS
	queen.rotation.y = -PI * 0.5


func _process(delta: float) -> void:
	t += delta
	if queen == null:
		return
	spin = maxf(0.0, spin - delta * 0.6)
	queen.position.y = W.HIVE_POS.y + 1.42 - POS.y + sin(t * 2.2) * 0.04 + sin(spin * PI) * 0.5
	queen.rotation.y = -PI * 0.5 + (1.0 - spin) * TAU * (1.0 if spin > 0.0 else 0.0)
	for w in wings:
		w.rotation.z = float(w.get_meta("side")) * (0.2 + sin(t * (60.0 if spin > 0.0 else 9.0)) * 0.35)
