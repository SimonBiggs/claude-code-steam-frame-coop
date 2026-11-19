extends Node3D
## SKY BOTS: GIZMO TOWN, the home island in the clouds. Granny Gizmo waits by the SKY LAMP (it glows brighter with every
## spark brought home), and the town GROWS: every spark and every gold gear builds the next thing (PIECES: a cottage, a
## windmill, a fountain, a tree house, a rocket, a big wheel, a rainbow arch, a balloon, a train ...), and stays (saved).
## The season dresses it (core/season_kit.gd props round the edge + its drift; the grass follows the season).
## The robots run about here between islands; the pick orbs float over the front.
## Chapter two: the town grows past its ten pieces onto two little ISLETS floating beside it (ISLET_PIECES: a snowman,
## a lighthouse, a clock tower, a jungle hut, a bandstand, a hat shop ...), every LITTLE BOT rescued from a bot box
## comes to live here (they toddle about the back of the town), and the Sky Lamp grows a halo ring for each far
## island's spark.

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Contrast := preload("res://core/contrast.gd")
const Level := preload("res://games/sky_bots/level.gd")

const R := 7.0  ## the island's top radius
const CENTER := Vector3(0.0, 0.0, -1.0)
const PIECES: Array[String] = ["cottage", "windmill", "fountain", "treehouse", "rocket", "bigwheel", "rainbow", "balloon",
	"train", "cottage2"]
## Where each piece stands (angle round the island's back, radius).
const SPOTS: Array[Vector2] = [Vector2(-2.7, 5.2), Vector2(-2.35, 5.4), Vector2(-2.0, 5.5), Vector2(-1.15, 5.5),
	Vector2(-0.8, 5.4), Vector2(-0.45, 5.2), Vector2(-1.57, 3.2), Vector2(-3.0, 4.6), Vector2(-0.15, 4.6), Vector2(-2.5, 3.2)]
const ISLET_PIECES: Array[String] = ["snowman", "lighthouse", "clocktower", "junglehut", "bandstand", "hatshop", "snowman2",
	"lighthouse2"]
const ISLETS: Array[Vector3] = [Vector3(-12.0, -0.6, -4.0), Vector3(12.0, -0.6, -4.0)]  ## (each islet's top middle)
const ISLET_R := 3.4
const TINY_MAX := 24  ## little bots shown walking about the town (the rest are indoors)
const LAMP_AT := Vector3(0.0, 0.0, -4.9)
const GIZMO_AT := Vector3(2.4, 0.0, -2.2)
const DRIFT := {"spring": Color(1.0, 0.75, 0.85), "summer": Color(1.0, 1.0, 0.7), "autumn": Color(0.95, 0.55, 0.2),
	"winter": Color(0.97, 0.98, 1.0)}

var season := "spring"
var shown := 0
var pieces: Array[Node3D] = []
var lamp_glow: MeshInstance3D
var lamp_light: OmniLight3D
var gizmo: Node3D
var wheel: Node3D
var windmill: Node3D
var _season_nodes: Array[Node] = []
var islets: Array[Node3D] = []
var halos: Array[Node3D] = []
var tinies: Array[Node3D] = []
var tiny_shown := 0


func build(the_season: String) -> void:
	season = the_season
	for c in get_children():
		c.queue_free()
	pieces.clear()
	_season_nodes.clear()
	islets.clear()
	halos.clear()
	tinies.clear()
	tiny_shown = 0
	shown = 0
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = R
	cy.height = 0.8
	cs.shape = cy
	cs.position = CENTER + Vector3(0, -0.4, 0)
	body.add_child(cs)
	var b := MeshKit.Builder.new()
	var top: Color = Level.MEADOW_TOPS.get(season, Level.MEADOW_TOPS.spring)
	b.cylinder(R, R, 0.25, MeshKit.at(CENTER + Vector3(0, -0.125, 0)), top, 36)
	b.cylinder(R, R - 0.3, 0.6, MeshKit.at(CENTER + Vector3(0, -0.55, 0)), Color(0.58, 0.4, 0.25), 36)
	b.cone(R - 0.4, 5.0, MeshKit.at(CENTER + Vector3(0, -0.85 - 2.5, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.52, 0.44, 0.4), 14)
	# A path of round stepping stones from the front to the lamp.
	for k in 5:
		b.cylinder(0.45, 0.45, 0.06, MeshKit.at(CENTER + Vector3(0, 0.03, 4.5 - k * 1.5)), Color(0.85, 0.82, 0.76), 12)
	# The Sky Lamp: a striped tower with a glass lamp on top.
	for k in 6:
		b.cylinder(0.55 - k * 0.04, 0.6 - k * 0.04, 0.6, MeshKit.at(LAMP_AT + Vector3(0, 0.3 + k * 0.6, 0)), Color(0.95, 0.95, 0.98) if k % 2 == 0 else Color(0.35, 0.65, 1.0), 14)
	b.cylinder(0.65, 0.65, 0.15, MeshKit.at(LAMP_AT + Vector3(0, 3.65, 0)), Color(0.3, 0.32, 0.4), 14)
	b.cone(0.6, 0.6, MeshKit.at(LAMP_AT + Vector3(0, 4.85, 0)), Color(0.35, 0.65, 1.0), 14)
	add_child(MeshKit.instance(b.build()))
	lamp_glow = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	lamp_glow.mesh = sm
	lamp_glow.position = LAMP_AT + Vector3(0, 4.2, 0)
	add_child(lamp_glow)
	lamp_light = OmniLight3D.new()
	lamp_light.position = lamp_glow.position
	lamp_light.light_color = Level.SPARK_COLOR
	add_child(lamp_light)
	gizmo = Node3D.new()
	gizmo.position = GIZMO_AT
	gizmo.rotation.y = -0.5
	add_child(gizmo)
	var gm := MeshKit.instance(gizmo_mesh(), false)
	Contrast.outline(gm, Contrast.OUTLINE)
	gizmo.add_child(gm)
	for i in PIECES.size():
		var n := _piece(PIECES[i])
		var sp := SPOTS[i]
		n.position = CENTER + Vector3(cos(sp.x) * sp.y, 0.0, sin(sp.x) * sp.y)
		var to_mid := CENTER - n.position
		n.rotation.y = atan2(to_mid.x, to_mid.z)
		n.visible = false
		add_child(n)
		pieces.append(n)
	for k in ISLETS.size():
		var isl := _islet(ISLETS[k], top)
		add_child(isl)
		isl.visible = false
		islets.append(isl)
	for i in ISLET_PIECES.size():
		var n := _piece(ISLET_PIECES[i])
		var isl_c := ISLETS[i % 2]
		var a := -PI * 0.5 + (float(i / 2) - 1.5) * 0.9
		n.position = isl_c + Vector3(cos(a) * 2.0, 0.0, sin(a) * 2.0 + 0.6)
		n.rotation.y = atan2(-(n.position.x - isl_c.x), 1.0) * 0.5
		n.visible = false
		add_child(n)
		pieces.append(n)
	for k in 3:  # the far islands' halo rings round the lamp
		var h := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.75 + k * 0.28
		tm.outer_radius = 0.85 + k * 0.28
		tm.rings = 24
		tm.ring_segments = 6
		h.mesh = tm
		h.material_override = MeshKit.material([Color(0.85, 0.93, 1.0), Color(0.45, 0.9, 0.55), Color(0.8, 0.6, 1.0)][k], 1.5)
		h.position = LAMP_AT + Vector3(0, 4.2, 0)
		h.visible = false
		add_child(h)
		halos.append(h)
	_dress()
	set_lamp(0)


## Season props on the island's front edge and the season's drift (core/season_kit.gd).
func _dress() -> void:
	var sb := MeshKit.Builder.new()
	var spots := [Vector3(-5.6, 0, 1.4), Vector3(5.6, 0, 1.4), Vector3(-4.2, 0, 3.6), Vector3(4.2, 0, 3.6), Vector3(5.8, 0, -1.6),
		Vector3(-5.8, 0, -1.6)]
	for i in spots.size():
		SeasonKit.prop(sb, season, CENTER + (spots[i] as Vector3), i, 0.8, (CENTER - (spots[i] as Vector3)).normalized())
	var mi := MeshKit.instance(sb.build(), false)
	add_child(mi)
	var d := SeasonKit.drift(DRIFT.get(season, DRIFT.spring), season, {"box": Vector3(9.0, 0.5, 7.0), "at": CENTER + Vector3(0, 8, 0),
		"amount": 60})
	add_child(d)


## Granny Gizmo: a round teapot robot with a spout, a lid like a little hat, glasses and two wheels.
static func gizmo_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var teal := Color(0.45, 0.82, 0.85)
	b.ellipsoid(Vector3(0.62, 0.55, 0.62), MeshKit.at(Vector3(0, 0.75, 0)), teal, 18)
	b.cylinder(0.08, 0.14, 0.6, MeshKit.at(Vector3(0.65, 0.95, 0), Vector3.ONE, Vector3(0, 0, -0.9)), teal.darkened(0.1), 8)
	b.torus(0.25, 0.06, MeshKit.at(Vector3(-0.62, 0.85, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), teal.darkened(0.1), 14, 6)
	b.cylinder(0.38, 0.45, 0.14, MeshKit.at(Vector3(0, 1.32, 0)), Color(1.0, 0.6, 0.7), 16)
	b.sphere(0.1, MeshKit.at(Vector3(0, 1.45, 0)), Color(1.0, 0.85, 0.3), 8)
	b.rounded_box(Vector3(0.6, 0.3, 0.06), 0.1, MeshKit.at(Vector3(0, 0.88, 0.58)), Color(0.12, 0.15, 0.22))
	for s in [-1.0, 1.0]:
		b.sphere(0.06, MeshKit.at(Vector3(s * 0.13, 0.9, 0.62)), Color(0.45, 1.0, 0.95), 8, true)
		b.torus(0.1, 0.02, MeshKit.at(Vector3(s * 0.13, 0.9, 0.63), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.85, 0.3), 12, 4)
		b.cylinder(0.16, 0.16, 0.1, MeshKit.at(Vector3(s * 0.32, 0.16, 0.1), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.25, 0.25, 0.3), 12)
	b.box(Vector3(0.16, 0.03, 0.02), MeshKit.at(Vector3(0, 0.8, 0.62)), Color(0.45, 1.0, 0.95))
	return b.build()


func _piece(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = id
	var b := MeshKit.Builder.new()
	match id:
		"cottage", "cottage2":
			var wall := Color(1.0, 0.92, 0.75) if id == "cottage" else Color(0.8, 0.9, 1.0)
			b.box(Vector3(1.4, 1.1, 1.2), MeshKit.at(Vector3(0, 0.55, 0)), wall)
			b.wedge(Vector3(1.6, 0.7, 1.4), MeshKit.at(Vector3(0, 1.45, 0)), Color(0.9, 0.35, 0.3) if id == "cottage" else Color(0.35, 0.55, 0.9))
			b.box(Vector3(0.35, 0.6, 0.05), MeshKit.at(Vector3(0, 0.3, 0.61)), Color(0.55, 0.35, 0.2))
			b.box(Vector3(0.3, 0.3, 0.05), MeshKit.at(Vector3(0.42, 0.7, 0.61)), Color(1.0, 0.9, 0.5), true)
		"windmill":
			b.cylinder(0.4, 0.6, 2.2, MeshKit.at(Vector3(0, 1.1, 0)), Color(0.95, 0.9, 0.82), 10)
			b.cone(0.5, 0.6, MeshKit.at(Vector3(0, 2.5, 0)), Color(0.9, 0.4, 0.35), 10)
			windmill = Node3D.new()
			windmill.position = Vector3(0, 2.0, 0.5)
			n.add_child(windmill)
			var wb := MeshKit.Builder.new()
			for k in 4:
				wb.box(Vector3(0.22, 1.1, 0.04), MeshKit.at(Vector3(0, 0.55, 0), Vector3.ONE, Vector3(0, 0, 0)).rotated(Vector3.BACK, TAU * k / 4.0), Color(1.0, 0.97, 0.9))
			windmill.add_child(MeshKit.instance(wb.build(), false))
		"fountain":
			b.cylinder(0.9, 1.0, 0.35, MeshKit.at(Vector3(0, 0.17, 0)), Color(0.82, 0.82, 0.86), 16)
			b.cylinder(0.8, 0.8, 0.05, MeshKit.at(Vector3(0, 0.33, 0)), Color(0.4, 0.75, 1.0), 16)
			b.cylinder(0.12, 0.16, 0.8, MeshKit.at(Vector3(0, 0.6, 0)), Color(0.82, 0.82, 0.86), 8)
			b.sphere(0.25, MeshKit.at(Vector3(0, 1.05, 0)), Color(0.55, 0.85, 1.0), 10, true)
		"treehouse":
			b.cylinder(0.18, 0.25, 1.8, MeshKit.at(Vector3(0, 0.9, 0)), Color(0.55, 0.38, 0.22), 8)
			b.sphere(0.9, MeshKit.at(Vector3(0, 2.3, 0)), Color(0.35, 0.7, 0.3), 12)
			b.box(Vector3(0.9, 0.6, 0.7), MeshKit.at(Vector3(0, 1.6, 0.3)), Color(0.8, 0.55, 0.3))
			b.wedge(Vector3(1.0, 0.4, 0.8), MeshKit.at(Vector3(0, 2.1, 0.3)), Color(0.9, 0.35, 0.3))
		"rocket":
			b.cylinder(0.32, 0.32, 1.4, MeshKit.at(Vector3(0, 1.0, 0)), Color(0.95, 0.95, 0.98), 12)
			b.cone(0.32, 0.6, MeshKit.at(Vector3(0, 2.0, 0)), Color(1.0, 0.35, 0.35), 12)
			b.sphere(0.14, MeshKit.at(Vector3(0, 1.3, 0.28)), Color(0.4, 0.75, 1.0), 8, true)
			for k in 3:
				var a := TAU * k / 3.0
				b.wedge(Vector3(0.08, 0.5, 0.4), MeshKit.at(Vector3(cos(a) * 0.35, 0.45, sin(a) * 0.35), Vector3.ONE, Vector3(0, -a, 0)), Color(1.0, 0.35, 0.35))
			b.cylinder(0.6, 0.6, 0.1, MeshKit.at(Vector3(0, 0.05, 0)), Color(0.4, 0.42, 0.5), 14)
		"bigwheel":
			b.box(Vector3(0.12, 2.0, 0.12), MeshKit.at(Vector3(-0.5, 1.0, 0), Vector3.ONE, Vector3(0, 0, -0.25)), Color(0.85, 0.85, 0.9))
			b.box(Vector3(0.12, 2.0, 0.12), MeshKit.at(Vector3(0.5, 1.0, 0), Vector3.ONE, Vector3(0, 0, 0.25)), Color(0.85, 0.85, 0.9))
			wheel = Node3D.new()
			wheel.position = Vector3(0, 1.9, 0.12)
			n.add_child(wheel)
			var whb := MeshKit.Builder.new()
			whb.torus(1.0, 0.05, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.85, 0.3), 24, 4)
			var cols := [Color(1.0, 0.45, 0.5), Color(0.45, 0.75, 1.0), Color(0.55, 0.9, 0.45), Color(1.0, 0.75, 0.3)]
			for k in 6:
				var a := TAU * k / 6.0
				whb.box(Vector3(0.28, 0.24, 0.24), MeshKit.at(Vector3(cos(a), sin(a), 0.05)), cols[k % 4])
			wheel.add_child(MeshKit.instance(whb.build(), false))
		"rainbow":
			var rc := [Color(1.0, 0.4, 0.4), Color(1.0, 0.75, 0.3), Color(1.0, 0.95, 0.4), Color(0.5, 0.9, 0.45), Color(0.45, 0.7, 1.0)]
			for k in rc.size():
				b.torus(1.6 - k * 0.12, 0.07, MeshKit.at(Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(0, 0, 0)).rotated(Vector3.RIGHT, PI * 0.5), rc[k], 28, 4)
		"balloon":
			b.sphere(0.6, MeshKit.at(Vector3(0, 2.6, 0)), Color(1.0, 0.5, 0.65), 14)
			b.box(Vector3(0.4, 0.3, 0.4), MeshKit.at(Vector3(0, 1.5, 0)), Color(0.7, 0.5, 0.3))
			b.cylinder(0.02, 0.02, 0.8, MeshKit.at(Vector3(0, 2.0, 0)), Color(0.4, 0.3, 0.2), 4)
		"train":
			b.box(Vector3(1.2, 0.6, 0.6), MeshKit.at(Vector3(0, 0.45, 0)), Color(0.35, 0.55, 0.95))
			b.box(Vector3(0.5, 0.5, 0.6), MeshKit.at(Vector3(-0.35, 0.95, 0)), Color(0.35, 0.55, 0.95))
			b.cylinder(0.12, 0.15, 0.4, MeshKit.at(Vector3(0.35, 1.0, 0)), Color(0.25, 0.25, 0.3), 8)
			for s in [-0.4, 0.4]:
				b.cylinder(0.16, 0.16, 0.7, MeshKit.at(Vector3(s, 0.16, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.9, 0.3, 0.3), 10)
			b.box(Vector3(2.4, 0.05, 0.5), MeshKit.at(Vector3(0, 0.02, 0)), Color(0.5, 0.4, 0.3))
		"snowman", "snowman2":
			b.sphere(0.5, MeshKit.at(Vector3(0, 0.45, 0)), Color(0.97, 0.98, 1.0), 12)
			b.sphere(0.36, MeshKit.at(Vector3(0, 1.1, 0)), Color(0.97, 0.98, 1.0), 12)
			b.cone(0.06, 0.3, MeshKit.at(Vector3(0, 1.12, 0.45), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.55, 0.2), 6)
			b.cylinder(0.25, 0.25, 0.3, MeshKit.at(Vector3(0, 1.55, 0)), Color(0.2, 0.2, 0.25) if id == "snowman" else Color(0.9, 0.3, 0.35), 10)
			b.torus(0.3, 0.07, MeshKit.at(Vector3(0, 0.82, 0)), Color(0.9, 0.3, 0.35) if id == "snowman" else Color(0.35, 0.6, 1.0), 14, 5)
		"lighthouse", "lighthouse2":
			for k in 4:
				b.cylinder(0.45 - k * 0.05, 0.5 - k * 0.05, 0.6, MeshKit.at(Vector3(0, 0.3 + k * 0.6, 0)), Color(0.97, 0.97, 0.98) if k % 2 == 0 else Color(0.95, 0.35, 0.35), 12)
			b.sphere(0.3, MeshKit.at(Vector3(0, 2.6, 0)), Color(1.0, 0.92, 0.5), 10, true)
			b.cone(0.38, 0.4, MeshKit.at(Vector3(0, 3.05, 0)), Color(0.3, 0.32, 0.4), 12)
		"clocktower":
			b.box(Vector3(1.0, 2.6, 1.0), MeshKit.at(Vector3(0, 1.3, 0)), Color(0.72, 0.56, 0.3))
			b.cylinder(0.4, 0.4, 0.06, MeshKit.at(Vector3(0, 2.0, 0.51), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.97, 0.95, 0.88), 16)
			b.box(Vector3(0.05, 0.3, 0.03), MeshKit.at(Vector3(0, 2.12, 0.55)), Color(0.15, 0.15, 0.2))
			b.box(Vector3(0.22, 0.05, 0.03), MeshKit.at(Vector3(0.09, 2.0, 0.55)), Color(0.15, 0.15, 0.2))
			b.wedge(Vector3(1.2, 0.7, 1.2), MeshKit.at(Vector3(0, 2.95, 0)), Color(0.55, 0.4, 0.9))
		"junglehut":
			for k in 4:
				b.cylinder(0.06, 0.06, 0.8, MeshKit.at(Vector3(-0.45 + (k % 2) * 0.9, 0.4, -0.4 + (k / 2) * 0.8)), Color(0.5, 0.35, 0.2), 5)
			b.box(Vector3(1.2, 0.6, 1.0), MeshKit.at(Vector3(0, 1.1, 0)), Color(0.8, 0.62, 0.38))
			b.cone(0.95, 0.8, MeshKit.at(Vector3(0, 1.8, 0)), Color(0.35, 0.65, 0.3), 8)
		"bandstand":
			b.cylinder(1.0, 1.0, 0.2, MeshKit.at(Vector3(0, 0.1, 0)), Color(0.95, 0.92, 0.85), 14)
			for k in 6:
				var a := TAU * k / 6.0
				b.cylinder(0.05, 0.05, 1.3, MeshKit.at(Vector3(cos(a) * 0.85, 0.85, sin(a) * 0.85)), Color(0.97, 0.97, 0.97), 5)
			b.cone(1.15, 0.6, MeshKit.at(Vector3(0, 1.8, 0)), Color(1.0, 0.45, 0.55), 14)
		"hatshop":
			b.box(Vector3(1.4, 1.1, 1.1), MeshKit.at(Vector3(0, 0.55, 0)), Color(0.98, 0.85, 0.9))
			b.box(Vector3(1.6, 0.12, 1.3), MeshKit.at(Vector3(0, 1.16, 0)), Color(0.55, 0.4, 0.9))
			b.cylinder(0.22, 0.22, 0.04, MeshKit.at(Vector3(0, 1.24, 0)), Color(0.15, 0.15, 0.2), 12)
			b.cylinder(0.14, 0.14, 0.32, MeshKit.at(Vector3(0, 1.42, 0)), Color(0.15, 0.15, 0.2), 12)
			b.box(Vector3(0.35, 0.6, 0.05), MeshKit.at(Vector3(-0.3, 0.3, 0.56)), Color(0.55, 0.35, 0.2))
			b.box(Vector3(0.4, 0.35, 0.05), MeshKit.at(Vector3(0.3, 0.65, 0.56)), Color(0.6, 0.85, 1.0), true)
	n.add_child(MeshKit.instance(b.build()))
	return n


## A little floating islet beside the town (it shows once the town has grown onto it).
func _islet(c: Vector3, top: Color) -> Node3D:
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.cylinder(ISLET_R, ISLET_R, 0.25, MeshKit.at(c + Vector3(0, -0.125, 0)), top, 24)
	b.cylinder(ISLET_R, ISLET_R - 0.3, 0.5, MeshKit.at(c + Vector3(0, -0.5, 0)), Color(0.58, 0.4, 0.25), 24)
	b.cone(ISLET_R - 0.4, 3.0, MeshKit.at(c + Vector3(0, -0.75 - 1.5, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.52, 0.44, 0.4), 10)
	# A little rope bridge back to the town's edge.
	var to := CENTER + Vector3(signf(c.x) * (R - 0.3), 0.0, -2.0)
	var from := c + Vector3(-signf(c.x) * (ISLET_R - 0.3), 0.0, 0.0)
	var mid := (to + from) * 0.5 - Vector3(0, 0.25, 0)
	var d := to - from
	b.box(Vector3(d.length(), 0.08, 0.7), Transform3D(Basis.looking_at(Vector3(d.z, 0, -d.x).normalized(), Vector3.UP), mid), Color(0.7, 0.52, 0.32))
	n.add_child(MeshKit.instance(b.build()))
	return n


## Every machine: n little bots rescued so far (the first TINY_MAX toddle about the back of the town; new ones pop up).
func set_tiny(n: int, pop: bool) -> void:
	var want := mini(n, TINY_MAX)
	while tinies.size() < want:
		var i := tinies.size()
		var t := Node3D.new()
		t.add_child(MeshKit.instance(Level.tiny_mesh(Level.TINY_COLORS[i % Level.TINY_COLORS.size()]), false))
		t.set_meta("i", i)
		add_child(t)
		if pop and i >= tiny_shown:
			t.scale = Vector3.ONE * 0.01
			create_tween().tween_property(t, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tinies.append(t)
	tiny_shown = want


## How far the town has grown (story.gd power). New pieces pop up.
func apply(power: int, pop: bool) -> void:
	var want := clampi(power, 0, pieces.size())
	for k in islets.size():
		islets[k].visible = want > PIECES.size() + k
	for i in pieces.size():
		var n := pieces[i]
		var on := i < want
		if on and not n.visible and pop and i >= shown:
			n.scale = Vector3.ONE * 0.01
			create_tween().tween_property(n, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3 * (i - shown))
		n.visible = on
	shown = want


## The Sky Lamp glows brighter with every island's spark (sparks: the islands cleared, 0..3).
func set_lamp(sparks: int) -> void:
	for i in halos.size():
		halos[i].visible = sparks > 3 + i
	var k := clampf(float(sparks) / 3.0, 0.0, 1.0)
	lamp_glow.material_override = MeshKit.material(Color(0.5, 0.55, 0.6).lerp(Level.SPARK_COLOR, k), 0.3 + 3.0 * k)
	lamp_light.light_energy = 0.2 + 2.0 * k
	lamp_light.omni_range = 4.0 + 6.0 * k


func animate(_delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if windmill != null:
		windmill.rotation.z = now * 1.2
	if wheel != null:
		wheel.rotation.z = now * 0.4
	for i in halos.size():
		halos[i].rotation = Vector3(0.5 + i * 0.4, now * (0.6 + i * 0.3), 0.2 * i)
	for t in tinies:  # little bots toddle round the back of the town, each on its own loop
		var i := int(t.get_meta("i"))
		var a := now * (0.25 + 0.03 * (i % 5)) * (1.0 if i % 2 == 0 else -1.0) + i * 1.7
		var rr := 2.6 + float(i % 4) * 0.7
		t.position = CENTER + Vector3(cos(a) * rr, absf(sin(now * 9.0 + i)) * 0.06, -absf(sin(a)) * rr * 0.75 - 0.6)
		t.rotation.y = a + (PI if i % 2 == 0 else 0.0)
	if gizmo != null:
		gizmo.position.y = absf(sin(now * 2.0)) * 0.06
		gizmo.rotation.z = sin(now * 1.3) * 0.06


## Where robots stand in the hub (round the front middle).
static func spawn(n: int, count: int) -> Vector3:
	var a := (float(n) - float(count - 1) * 0.5) * 0.9
	return CENTER + Vector3(a, 0.05, 3.2)
