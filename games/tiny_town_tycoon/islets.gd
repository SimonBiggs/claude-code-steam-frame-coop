extends Node3D
## TINY TOWN TYCOON: BENNY'S ARCHIPELAGO (deep.gd ISLETS). Every ISLET_EVERY wishes the townsfolk get (any town, saved:
## wishes_total) a little islet rises out of the sea round the island for good, each with its own thing: a palm, a
## lighthouse, a windmill, a camp tent, flowers, a castle, a treehouse, a fountain. They sit in the sea between the
## island and the table's edge (deep.gd islet_spot), away from the mayor's side. The newest one pops up with a splash.
## One merged mesh (rebuilt only when one is added): cheap on the Frame and the Decks.
##   set_count(n, celebrate)

const MeshKit := preload("res://core/mesh_kit.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Deep := preload("res://games/tiny_town_tycoon/deep.gd")

const SAND := Color(0.96, 0.88, 0.62)
const GRASS := Color(0.45, 0.76, 0.34)

var main
var count := -1
var mesh_node: MeshInstance3D


func set_count(n: int, celebrate: bool) -> void:
	n = clampi(n, 0, Deep.ISLETS.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	if mesh_node != null and is_instance_valid(mesh_node):
		mesh_node.queue_free()
	mesh_node = null
	if n == 0:
		return
	var b := MeshKit.Builder.new()
	for i in n:
		build_islet(b, String(Deep.ISLETS[i].id), Deep.islet_spot(i), i)
	mesh_node = MeshKit.instance(b.build(), false)
	mesh_node.name = "Islets"
	add_child(mesh_node)
	if grew and celebrate and main != null:
		var at := Deep.islet_spot(n - 1) + Vector3(0.0, 0.03, 0.0)
		main.view.call("burst", at, Color(0.6, 0.9, 1.0), 24, 1.2)
		main.sfx.play_at("splash", at, -2.0)


## One islet at `at` (on the sea): a sandy shore, a grassy top and its thing.
static func build_islet(b: MeshKit.Builder, id: String, at: Vector3, i: int) -> void:
	var r := Deep.ISLET_R
	var top := at.y + 0.012
	b.cylinder(r * 0.85, r, 0.016, MeshKit.at(at + Vector3(0, 0.0, 0)), SAND, 16)
	b.cylinder(r * 0.62, r * 0.72, 0.01, MeshKit.at(at + Vector3(0, 0.009, 0)), GRASS, 14)
	var c := Vector3(at.x, top + 0.002, at.z)
	match id:
		"palm":
			b.tube(c, c + Vector3(0.006, 0.05, 0.0), 0.003, 0.0022, Color(0.55, 0.38, 0.22), 6)
			for k in 5:
				var a := k * TAU / 5.0
				b.cone(0.006, 0.026, MeshKit.at(c + Vector3(0.006 + cos(a) * 0.011, 0.048, sin(a) * 0.011), Vector3(1.0, 1.0, 0.35),
					Vector3(0.0, -a, PI * 0.5 + 0.35)), Color(0.3, 0.7, 0.3), 5)
			b.sphere(0.004, MeshKit.at(c + Vector3(0.004, 0.044, 0.004)), Color(0.5, 0.33, 0.15), 6)
		"lighthouse":
			b.sphere(0.02, MeshKit.at(c, Vector3(1.2, 0.5, 1.2)), Color(0.6, 0.6, 0.62), 8)
			for k in 4:
				b.cylinder(0.0085 - k * 0.0008, 0.009 - k * 0.0008, 0.012, MeshKit.at(c + Vector3(0, 0.012 + k * 0.012, 0)),
					Color(0.95, 0.95, 0.95) if k % 2 == 0 else Color(0.9, 0.25, 0.2), 10)
			b.cylinder(0.006, 0.006, 0.008, MeshKit.at(c + Vector3(0, 0.06, 0)), Color(1.0, 0.9, 0.35), 10, true)
			b.cone(0.008, 0.008, MeshKit.at(c + Vector3(0, 0.068, 0)), Color(0.9, 0.25, 0.2), 10)
		"windmill":
			b.cylinder(0.006, 0.009, 0.035, MeshKit.at(c + Vector3(0, 0.0175, 0)), Color(0.95, 0.9, 0.8), 8)
			b.cone(0.008, 0.01, MeshKit.at(c + Vector3(0, 0.04, 0)), Color(0.75, 0.3, 0.25), 8)
			for k in 4:
				var a2 := k * PI * 0.5 + 0.3
				b.box(Vector3(0.004, 0.02, 0.001), MeshKit.at(c + Vector3(cos(a2) * 0.01, 0.033 + sin(a2) * 0.01, 0.01), Vector3.ONE,
					Vector3(0, 0, a2 - PI * 0.5)), Color(0.98, 0.98, 0.95))
		"tent":
			b.cone(0.016, 0.022, MeshKit.at(c + Vector3(0, 0.011, 0)), Color(1.0, 0.55, 0.2), 4)
			b.cylinder(0.006, 0.006, 0.002, MeshKit.at(c + Vector3(0.022, 0.001, 0.01)), Color(0.4, 0.3, 0.25), 8)
			b.cone(0.004, 0.008, MeshKit.at(c + Vector3(0.022, 0.006, 0.01)), Color(1.0, 0.6, 0.1), 6, true)
		"flowers":
			var cols: Array[Color] = [Color(1.0, 0.4, 0.6), Color(1.0, 0.95, 0.4), Color(0.75, 0.5, 1.0), Color(1.0, 1.0, 1.0)]
			for k in 9:
				var a3 := k * 2.4
				var d := 0.008 + (k % 3) * 0.009
				b.sphere(0.0045, MeshKit.at(c + Vector3(cos(a3) * d, 0.004, sin(a3) * d)), cols[k % cols.size()], 6)
		"castle":
			b.box(Vector3(0.028, 0.02, 0.028), MeshKit.at(c + Vector3(0, 0.01, 0)), Color(0.82, 0.8, 0.76))
			for k in 4:
				var q := Vector3((k % 2) * 2 - 1, 0, (k / 2) * 2 - 1) * 0.014
				b.cylinder(0.006, 0.006, 0.03, MeshKit.at(c + q + Vector3(0, 0.015, 0)), Color(0.85, 0.83, 0.8), 8)
				b.cone(0.007, 0.012, MeshKit.at(c + q + Vector3(0, 0.036, 0)), Color(0.35, 0.45, 0.9), 8)
			b.box(Vector3(0.0006, 0.016, 0.0006), MeshKit.at(c + Vector3(0, 0.028, 0)), Color(0.4, 0.3, 0.2))
			b.box(Vector3(0.008, 0.005, 0.0006), MeshKit.at(c + Vector3(0.004, 0.034, 0)), Color(1.0, 0.85, 0.2))
		"treehouse":
			b.cylinder(0.004, 0.005, 0.045, MeshKit.at(c + Vector3(0, 0.0225, 0)), Color(0.5, 0.33, 0.2), 8)
			b.sphere(0.02, MeshKit.at(c + Vector3(0, 0.05, 0)), Color(0.3, 0.65, 0.3), 10)
			b.box(Vector3(0.016, 0.012, 0.016), MeshKit.at(c + Vector3(0.0, 0.032, 0.01)), Color(0.75, 0.5, 0.3))
			b.cone(0.012, 0.008, MeshKit.at(c + Vector3(0.0, 0.042, 0.01)), Color(0.85, 0.3, 0.25), 4)
		_:  # a fountain
			b.cylinder(0.02, 0.022, 0.006, MeshKit.at(c + Vector3(0, 0.003, 0)), Color(0.8, 0.8, 0.82), 14)
			b.cylinder(0.017, 0.017, 0.002, MeshKit.at(c + Vector3(0, 0.0065, 0)), Color(0.4, 0.75, 1.0), 14)
			b.cylinder(0.003, 0.004, 0.018, MeshKit.at(c + Vector3(0, 0.012, 0)), Color(0.8, 0.8, 0.82), 8)
			b.sphere(0.006, MeshKit.at(c + Vector3(0, 0.024, 0)), Color(0.55, 0.85, 1.0), 8)
