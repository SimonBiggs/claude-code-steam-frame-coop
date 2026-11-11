extends Node3D
## MINI GOLF PARTY seasonal garden (deep.gd SEASONS, Seeded.season on the host; synced in the "deep" state): every
## machine dresses Gus's lawn the same - the lawn's colour, a few seasonal things round the edge of the lawn (spring
## tulip tubs, summer sunflowers, autumn pumpkins on leaf piles, winter snowmen) and things drifting down in a ring
## round the lawn's edge (blossom, butterflies' pollen, leaves, snow: never over the green or in a VR golfer's face).
## One merged mesh + one CPUParticles3D: cheap on the Frame. The greens never change colour (balls stay easy to see).
##   set_season(name, lawn)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/mini_golf_party/deep.gd")

## Round the lawn's edge, never on a hole (deep_test checks), the garden corner (left) or the VR toys at the tee.
const SPOTS: Array[Vector2] = [Vector2(5.0, -3.2), Vector2(5.6, 0.2), Vector2(5.0, 3.4), Vector2(2.4, -5.6), Vector2(-1.4, -5.8),
	Vector2(3.0, 5.6)]

var season := ""
var props: MeshInstance3D
var drift: CPUParticles3D


func set_season(s: String, lawn: MeshInstance3D = null) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	var sd := Deep.season_data(s)
	if lawn != null:
		lawn.material_override = MeshKit.material(sd.lawn)
	var b := MeshKit.Builder.new()
	for i in SPOTS.size():
		_prop(b, s, Vector3(SPOTS[i].x, 0.0, SPOTS[i].y), i)
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = CPUParticles3D.new()
	drift.name = "SeasonDrift"
	drift.amount = 70
	drift.lifetime = 8.0
	drift.preprocess = 8.0
	drift.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	drift.emission_ring_axis = Vector3.UP
	drift.emission_ring_radius = 12.0
	drift.emission_ring_inner_radius = 6.5
	drift.emission_ring_height = 0.5
	drift.position = Vector3(0.0, 6.0, 0.0)
	drift.direction = Vector3(0.2, -1.0, 0.0)
	drift.spread = 15.0
	drift.gravity = Vector3(0.0, -0.3, 0.0)
	drift.initial_velocity_min = 0.5
	drift.initial_velocity_max = 0.9
	drift.angular_velocity_min = -90.0
	drift.angular_velocity_max = 90.0
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.08) if s != "winter" else Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = sd.drift
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	drift.mesh = q
	drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drift)
	print("Mini Golf Party: %s garden" % s)


func _prop(b: MeshKit.Builder, s: String, at: Vector3, i: int) -> void:
	match s:
		"winter":  # a snowman with a carrot nose and a scarf, on a snow pile
			var w := Color(0.97, 0.98, 1.0)
			b.cylinder(0.45, 0.55, 0.1, MeshKit.at(at + Vector3(0, 0.05, 0)), w, 12)
			b.sphere(0.3, MeshKit.at(at + Vector3(0, 0.3, 0)), w, 10)
			b.sphere(0.22, MeshKit.at(at + Vector3(0, 0.7, 0)), w, 10)
			b.sphere(0.15, MeshKit.at(at + Vector3(0, 1.0, 0)), w, 10)
			b.cone(0.03, 0.15, MeshKit.at(at + Vector3(0, 1.0, 0.16), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.5, 0.1), 6)
			b.cylinder(0.18, 0.18, 0.06, MeshKit.at(at + Vector3(0, 0.86, 0)), [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 1.0)][i % 2], 10)
		"autumn":  # a pumpkin on a pile of leaves
			b.cylinder(0.45, 0.55, 0.1, MeshKit.at(at + Vector3(0, 0.05, 0)), Color(0.9, 0.45, 0.12), 10)
			b.sphere(0.24, MeshKit.at(at + Vector3(0.1, 0.25, 0), Vector3(1.25, 0.85, 1.25)), Color(1.0, 0.55, 0.1), 10)
			b.cylinder(0.025, 0.03, 0.1, MeshKit.at(at + Vector3(0.1, 0.48, 0)), Color(0.3, 0.5, 0.15), 6)
			b.sphere(0.14, MeshKit.at(at + Vector3(-0.25, 0.16, 0.18), Vector3(1.2, 0.85, 1.2)), Color(0.95, 0.7, 0.15), 8)
		"spring":  # a tub of tulips
			b.cylinder(0.28, 0.22, 0.3, MeshKit.at(at + Vector3(0, 0.15, 0)), Color(0.55, 0.32, 0.18), 10)
			for k in 6:
				var a := float(k) * TAU / 6.0
				var top := at + Vector3(cos(a) * 0.14, 0.55 + 0.06 * (k % 2), sin(a) * 0.14)
				b.tube(top - Vector3(0, 0.25, 0), top, 0.012, 0.012, Color(0.3, 0.6, 0.25), 4)
				b.sphere(0.07, MeshKit.at(top, Vector3(1.0, 1.3, 1.0)), [Color(1.0, 0.4, 0.6), Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.3)][k % 3], 8)
		_:  # summer: two tall sunflowers
			for k in 2:
				var p := at + Vector3(k * 0.35 - 0.17, 0, k * 0.1)
				var h := 1.1 + 0.2 * k
				b.tube(p, p + Vector3(0, h, 0), 0.025, 0.02, Color(0.3, 0.6, 0.2), 6)
				b.cylinder(0.2, 0.2, 0.03, MeshKit.at(p + Vector3(0, h + 0.05, 0.03), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.85, 0.15), 14)
				b.cylinder(0.1, 0.1, 0.04, MeshKit.at(p + Vector3(0, h + 0.05, 0.05), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.4, 0.25, 0.1), 12)
