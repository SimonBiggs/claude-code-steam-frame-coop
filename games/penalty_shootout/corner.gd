extends Node3D
## LEO'S TROPHY CORNER (deep.gd CORNER): every CORNER_EVERY star goals Leo's corner behind his prizes gets a new piece
## for good - FLAGS, a CUP CABINET, a FOUNTAIN, a RAINBOW ARCH, a BELL, FAIRY LIGHTS, a DISCO BALL and a golden LION
## STATUE. Every machine builds the same from the piece count (main.gd sends it with Leo's family). The newest piece
## pops in. One merged mesh; the disco ball and the fountain's water turn slowly.
##   set_pieces(n, pop)

const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")
const Deep := preload("res://games/penalty_shootout/deep.gd")

var main
var count := -1
var body: MeshInstance3D
var spinner: Node3D
var t := 0.0


func set_pieces(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.CORNER.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	for c in get_children():
		c.queue_free()
	body = null
	spinner = null
	if n == 0:
		return
	var parts: Array = []
	var spin: Array = []
	for i in n:
		_piece(parts, spin, Deep.CORNER[i], Deep.corner_spot(i))
	body = MeshInstance3D.new()
	body.name = "TrophyCorner"
	body.mesh = MeshKit.merge(parts)
	body.material_override = MeshKit.vertex_material(main.mats)
	add_child(body)
	if not spin.is_empty():
		spinner = Node3D.new()
		add_child(spinner)
		for s in spin:
			var mi := MeshInstance3D.new()
			mi.mesh = MeshKit.merge([[s[1], Transform3D.IDENTITY, s[2]]])
			mi.material_override = MeshKit.vertex_material(main.mats, true)
			mi.position = s[0]
			spinner.add_child(mi)
	if grew and pop:
		var at := Deep.corner_spot(n - 1)
		main.burst(at + Vector3(0, 1.5, 0), Color(1.0, 0.85, 0.3), 30, false)


func _piece(parts: Array, spin: Array, kind: String, at: Vector3) -> void:
	var gold := Color(1.0, 0.82, 0.2)
	match kind:
		"flags":
			for k in 3:
				var p := at + Vector3((k - 1) * 0.5, 0, 0)
				parts.append([MeshKit.cyl(0.03, 0.03, 2.2, 6), MeshKit.at(p + Vector3(0, 1.1, 0)), Color(0.9, 0.9, 0.9)])
				parts.append([MeshKit.box(Vector3(0.45, 0.3, 0.02)), MeshKit.at(p + Vector3(0.24, 1.95, 0)),
					[Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 1.0), Color(1.0, 0.85, 0.15)][k]])
		"cabinet":
			parts.append([MeshKit.box(Vector3(1.2, 1.6, 0.5)), MeshKit.at(at + Vector3(0, 0.8, 0)), Color(0.45, 0.28, 0.15)])
			parts.append([MeshKit.box(Vector3(1.0, 1.3, 0.05)), MeshKit.at(at + Vector3(0, 0.85, 0.26)), Color(0.75, 0.9, 1.0)])
			for k in 3:
				parts.append([MeshKit.cyl(0.1, 0.05, 0.25, 8), MeshKit.at(at + Vector3((k - 1) * 0.32, 0.6 + 0.45 * (k % 2), 0.1)), gold])
		"fountain":
			parts.append([MeshKit.cyl(0.8, 0.9, 0.4, 14), MeshKit.at(at + Vector3(0, 0.2, 0)), Color(0.75, 0.75, 0.8)])
			parts.append([MeshKit.cyl(0.7, 0.7, 0.05, 14), MeshKit.at(at + Vector3(0, 0.38, 0)), Color(0.3, 0.6, 1.0)])
			parts.append([MeshKit.cyl(0.1, 0.12, 0.9, 8), MeshKit.at(at + Vector3(0, 0.8, 0)), Color(0.75, 0.75, 0.8)])
			spin.append([at + Vector3(0, 1.3, 0), MeshKit.sphere(0.25, 10), Color(0.5, 0.8, 1.0)])
		"arch":
			var cols: Array[Color] = [Color(1, 0.3, 0.3), Color(1, 0.6, 0.2), Color(1, 0.9, 0.2), Color(0.3, 0.9, 0.4), Color(0.3, 0.6, 1)]
			for k in 9:
				var a := PI * float(k) / 8.0
				for c in cols.size():
					var r := 0.9 - 0.12 * c
					parts.append([MeshKit.box(Vector3(0.12, 0.12, 0.12)), MeshKit.at(at + Vector3(cos(a) * r, 0.2 + sin(a) * r * 1.4, 0)), cols[c]])
		"bell":
			parts.append([MeshKit.box(Vector3(0.1, 2.0, 0.1)), MeshKit.at(at + Vector3(-0.5, 1.0, 0)), Color(0.4, 0.25, 0.12)])
			parts.append([MeshKit.box(Vector3(0.1, 2.0, 0.1)), MeshKit.at(at + Vector3(0.5, 1.0, 0)), Color(0.4, 0.25, 0.12)])
			parts.append([MeshKit.box(Vector3(1.2, 0.12, 0.12)), MeshKit.at(at + Vector3(0, 2.0, 0)), Color(0.4, 0.25, 0.12)])
			parts.append([MeshKit.cyl(0.12, 0.35, 0.45, 12), MeshKit.at(at + Vector3(0, 1.65, 0)), gold])
		"lights":
			for k in 7:
				var x := (k - 3) * 0.3
				parts.append([MeshKit.sphere(0.08, 6), MeshKit.at(at + Vector3(x, 2.0 - 0.15 * cos(x * 1.4), 0)),
					[Color(1, 0.4, 0.4), Color(0.4, 1, 0.5), Color(0.4, 0.7, 1), Color(1, 0.9, 0.3)][k % 4]])
			parts.append([MeshKit.cyl(0.03, 0.03, 2.2, 6), MeshKit.at(at + Vector3(-1.0, 1.1, 0)), Color(0.9, 0.9, 0.9)])
			parts.append([MeshKit.cyl(0.03, 0.03, 2.2, 6), MeshKit.at(at + Vector3(1.0, 1.1, 0)), Color(0.9, 0.9, 0.9)])
		"disco":
			parts.append([MeshKit.cyl(0.03, 0.03, 2.4, 6), MeshKit.at(at + Vector3(0, 1.2, 0)), Color(0.85, 0.85, 0.9)])
			spin.append([at + Vector3(0, 2.6, 0), MeshKit.sphere(0.35, 8), Color(0.85, 0.9, 1.0)])
		_:  # statue: a golden lion on a plinth
			parts.append([MeshKit.box(Vector3(1.0, 0.6, 0.8)), MeshKit.at(at + Vector3(0, 0.3, 0)), Color(0.75, 0.75, 0.8)])
			parts.append([MeshKit.sphere(0.4, 10), MeshKit.at(at + Vector3(0, 0.95, 0), Vector3(1.2, 0.9, 0.9)), gold])
			parts.append([MeshKit.sphere(0.32, 10), MeshKit.at(at + Vector3(0, 1.45, 0.15)), gold.darkened(0.15)])
			parts.append([MeshKit.sphere(0.22, 10), MeshKit.at(at + Vector3(0, 1.45, 0.3)), gold])


func _process(delta: float) -> void:
	t += delta
	if spinner != null:
		for c in spinner.get_children():
			(c as Node3D).rotation.y = t * 0.8
			(c as Node3D).position.y += sin(t * 2.0) * 0.0015