extends Node3D
## GRANNY BOO'S WINGS (second pass): one side room of a house (housegen.gd wing_for: the library or the ballroom)
## is dressed as a wing, the same on every machine from the house seed. Everything here is scenery players walk
## under or past (no collision: the hiding places stay housegen.gd's job, so the validator's map stays the real one):
##   attic       roof beams, a round moon window, hanging bulbs, dusty planks, cobwebs and a kite on the wall
##   cellar      stone floor, shelves of glowing jam jars up high, strings of onions, warm pipes, a dim lamp
##   greenhouse  a glass roof, hanging flower baskets that sway, ivy up the walls, green tiles, sunshine

const World := preload("res://games/ghost_lantern/world.gd")
const HouseGen := preload("res://games/ghost_lantern/housegen.gd")
const UiKit := preload("res://core/ui_kit.gd")

const NAMES := {"attic": "THE ATTIC", "cellar": "THE CELLAR", "greenhouse": "THE GREENHOUSE"}
const LINES := {"attic": "The attic is open!", "cellar": "Down to the cellar!", "greenhouse": "My greenhouse!"}
const TOP := 4.1  # just under the ceiling

var wing := {}
var swing: Array = []  # [node, phase] hanging baskets / bulbs
var t := 0.0


func build(w: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	swing.clear()
	wing = w.duplicate()
	if w.is_empty():
		return
	var xr: Array = HouseGen.ROOMS[String(w.room)]
	var x0 := float(xr[0]) + 0.2
	var x1 := float(xr[1]) - 0.2
	var cx := (x0 + x1) * 0.5
	var end_x := -HouseGen.HALF_X + 0.06 if String(w.room) == "library" else HouseGen.HALF_X - 0.06
	var root := Node3D.new()
	root.name = String(w.id).capitalize()
	add_child(root)
	match String(w.id):
		"attic":
			World.box(root, Vector3(x1 - x0, 0.01, 15.8), Vector3(cx, 0.006, 0.0), World.mat(World.WING_FLOORS.attic), false)
			for i in 6:  # floor planks
				World.box(root, Vector3(x1 - x0, 0.012, 0.03), Vector3(cx, 0.008, -6.6 + i * 2.6), World.mat(Color(0.3, 0.2, 0.14)), false)
			for i in 5:  # roof beams
				var bx := lerpf(x0 + 0.8, x1 - 0.8, float(i) / 4.0)
				World.box(root, Vector3(0.28, 0.32, 15.8), Vector3(bx, TOP - 0.1, 0.0), World.mat(Color(0.36, 0.24, 0.16)), false)
				var bulb := Node3D.new()
				bulb.position = Vector3(bx, TOP - 0.3, -2.0 + 4.0 * float(i % 2))
				root.add_child(bulb)
				World.cyl(bulb, 0.008, 0.008, 0.7, Vector3(0, -0.35, 0), World.mat(Color(0.15, 0.15, 0.15)), 4)
				World.ball(bulb, 0.09, Vector3(0, -0.75, 0), World.mat(Color(1.0, 0.85, 0.5), 4.0), 1.2)
				swing.append([bulb, float(i) * 1.7])
			World.cyl(root, 0.85, 0.85, 0.04, Vector3(end_x, 2.9, 0.0), World.mat(Color(0.75, 0.85, 1.0), 1.6), 20).rotation.z = PI / 2.0
			World.cyl(root, 0.95, 0.95, 0.03, Vector3(end_x, 2.9, 0.0), World.mat(Color(0.36, 0.24, 0.16)), 20).rotation.z = PI / 2.0
			var kite := World.box(root, Vector3(0.02, 0.9, 0.7), Vector3(end_x, 2.6, 4.6), World.mat(Color(1.0, 0.45, 0.45), 0.4), false)
			kite.rotation.x = PI / 4.0
			for z in [-7.8, 7.8]:  # cobwebs in the corners, up high
				for x in [x0 + 0.3, x1 - 0.3]:
					var web := World.box(root, Vector3(0.9, 0.9, 0.01), Vector3(x, TOP - 0.45, z), World.mat(Color(0.85, 0.85, 0.9, 1.0), 0.3), false)
					web.rotation.z = PI / 4.0
			_light(root, Vector3(cx, 3.2, 0.0), Color(1.0, 0.8, 0.55), 1.0, 9.0)
		"cellar":
			World.box(root, Vector3(x1 - x0, 0.01, 15.8), Vector3(cx, 0.006, 0.0), World.mat(World.WING_FLOORS.cellar), false)
			for i in 9:  # flagstones
				World.box(root, Vector3(0.03, 0.012, 15.8), Vector3(lerpf(x0 + 0.7, x1 - 0.7, float(i) / 8.0), 0.008, 0.0), World.mat(Color(0.22, 0.22, 0.26)), false)
			var jam: Array = [Color(1.0, 0.3, 0.35), Color(1.0, 0.65, 0.2), Color(0.6, 0.3, 0.8), Color(1.0, 0.85, 0.3)]
			for z in [-7.7, 7.7]:  # high shelves of glowing jam jars
				World.box(root, Vector3(x1 - x0 - 1.0, 0.06, 0.4), Vector3(cx, 2.6, z), World.mat(Color(0.4, 0.26, 0.16)), false)
				for k in 12:
					var jx := lerpf(x0 + 1.0, x1 - 1.0, float(k) / 11.0)
					World.cyl(root, 0.1, 0.1, 0.24, Vector3(jx, 2.75, z), World.mat(jam[k % 4], 1.4, 0.3), 10)
					World.cyl(root, 0.105, 0.105, 0.04, Vector3(jx, 2.89, z), World.mat(Color(0.9, 0.9, 0.85)), 10)
			for i in 4:  # onions on strings from the ceiling
				var on := Node3D.new()
				on.position = Vector3(lerpf(x0 + 1.5, x1 - 1.5, float(i) / 3.0), TOP, 3.5 - 7.0 * float(i % 2))
				root.add_child(on)
				World.cyl(on, 0.01, 0.01, 0.9, Vector3(0, -0.45, 0), World.mat(Color(0.7, 0.6, 0.4)), 4)
				for k in 4:
					World.ball(on, 0.08, Vector3(0.05 * (k % 2), -0.5 - 0.13 * k, 0), World.mat(Color(0.85, 0.6, 0.3)), 1.1)
				swing.append([on, float(i) * 2.1])
			var pipe := World.cyl(root, 0.08, 0.08, x1 - x0, Vector3(cx, TOP - 0.25, -6.9), World.mat(Color(0.7, 0.45, 0.3), 0.2, 0.3), 10)
			pipe.rotation.z = PI / 2.0
			_light(root, Vector3(cx, 3.0, 0.0), Color(1.0, 0.7, 0.4), 0.8, 8.0)
		"greenhouse":
			World.box(root, Vector3(x1 - x0, 0.01, 15.8), Vector3(cx, 0.006, 0.0), World.mat(World.WING_FLOORS.greenhouse), false)
			for i in 9:  # tiles
				World.box(root, Vector3(x1 - x0, 0.012, 0.03), Vector3(cx, 0.008, -7.0 + i * 1.75), World.mat(Color(0.85, 0.95, 0.85)), false)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.7, 1.0, 0.8, 0.25)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.render_priority = UiKit.VR_PRIO_UNDER_UI
			glass.emission_enabled = true
			glass.emission = Color(0.4, 0.7, 0.5)
			glass.emission_energy_multiplier = 0.4
			World.box(root, Vector3(x1 - x0, 0.03, 15.8), Vector3(cx, TOP + 0.02, 0.0), glass, false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for i in 7:  # white frame bars
				World.box(root, Vector3(0.08, 0.08, 15.8), Vector3(lerpf(x0, x1, float(i) / 6.0), TOP - 0.02, 0.0), World.mat(Color(0.95, 0.95, 0.95)), false)
			var petals: Array = [Color(1.0, 0.45, 0.6), Color(1.0, 0.85, 0.3), Color(0.7, 0.55, 1.0), Color(1.0, 0.6, 0.3)]
			for i in 6:  # hanging flower baskets
				var bk := Node3D.new()
				bk.position = Vector3(lerpf(x0 + 1.2, x1 - 1.2, float(i) / 5.0), TOP, -3.0 + 6.0 * float(i % 2))
				root.add_child(bk)
				World.cyl(bk, 0.01, 0.01, 0.8, Vector3(0, -0.4, 0), World.mat(Color(0.3, 0.3, 0.3)), 4)
				World.cyl(bk, 0.28, 0.18, 0.22, Vector3(0, -0.9, 0), World.mat(Color(0.75, 0.55, 0.3)), 10)
				World.ball(bk, 0.3, Vector3(0, -0.72, 0), World.mat(Color(0.3, 0.7, 0.3)), 0.7)
				for k in 5:
					var a := TAU * float(k) / 5.0
					World.ball(bk, 0.07, Vector3(cos(a) * 0.24, -0.66, sin(a) * 0.24), World.mat(petals[(i + k) % 4], 0.7))
				swing.append([bk, float(i) * 1.3])
			for z in [-7.92, 7.92]:  # ivy up the walls
				for k in 6:
					var vx := lerpf(x0 + 0.6, x1 - 0.6, float(k) / 5.0)
					World.cyl(root, 0.03, 0.03, 3.2, Vector3(vx, 1.8, z), World.mat(Color(0.25, 0.55, 0.25)), 5)
					for l in 4:
						World.ball(root, 0.12, Vector3(vx + 0.1 * (1 - 2 * (l % 2)), 0.8 + l * 0.8, z), World.mat(Color(0.35, 0.75, 0.3)), 0.4)
			_light(root, Vector3(cx, 3.6, 0.0), Color(1.0, 0.95, 0.75), 1.3, 10.0)


func _light(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)


func _process(delta: float) -> void:
	if swing.is_empty():
		return
	t += delta
	for s in swing:
		var n: Node3D = s[0]
		if is_instance_valid(n):
			n.rotation.z = sin(t * 0.9 + float(s[1])) * 0.06
			n.rotation.x = sin(t * 0.7 + float(s[1]) * 1.3) * 0.04