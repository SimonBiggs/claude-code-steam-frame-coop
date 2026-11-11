extends Node3D
## PENALTY SHOOTOUT seasonal pitch (deep.gd SEASONS, Seeded.season on the host; synced in the snapshot): every machine
## dresses the stadium the same - spring blossom, summer sunflowers, autumn leaves and pumpkins, winter snow and
## snowmen - with things drifting down over the far pitch and the stands (never in front of the keeper's face: they
## stay beyond the penalty spot) and a few seasonal props along the touchlines and right of the goal, well clear of
## every kick's path and of Leo's corner on the left. One merged mesh + one CPUParticles3D: cheap on the Frame.
##   set_season(name)

const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")
const Deep := preload("res://games/penalty_shootout/deep.gd")

## Props: right of the goal (behind the line) and along both touchlines towards the strikers.
const SPOTS: Array[Vector3] = [Vector3(8.0, 0, -1.5), Vector3(9.6, 0, -0.6), Vector3(11.2, 0, -1.8), Vector3(12.8, 0, -0.8),
	Vector3(-17.0, 0, 14.0), Vector3(17.0, 0, 15.0), Vector3(-18.0, 0, 22.0), Vector3(18.0, 0, 24.0)]

var main
var season := ""
var props: MeshInstance3D
var drift: CPUParticles3D


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	var sd := Deep.season_data(s)
	var parts: Array = []
	for i in SPOTS.size():
		_prop(parts, s, SPOTS[i], i)
	props = MeshInstance3D.new()
	props.name = "SeasonProps"
	props.mesh = MeshKit.merge(parts)
	props.material_override = MeshKit.vertex_material(main.mats)
	props.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(props)
	drift = CPUParticles3D.new()
	drift.name = "SeasonDrift"
	drift.amount = 90
	drift.lifetime = 9.0
	drift.preprocess = 9.0
	drift.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drift.emission_box_extents = Vector3(30.0, 0.5, 16.0)
	drift.position = Vector3(0.0, 14.0, 30.0)  # from z 14 to 46: beyond the spot, over the far pitch and the stands
	drift.direction = Vector3(0.3, -1.0, 0.0)
	drift.spread = 25.0
	drift.gravity = Vector3(0.0, -0.4, 0.0)
	drift.initial_velocity_min = 1.0
	drift.initial_velocity_max = 2.0
	drift.angular_velocity_min = -90.0
	drift.angular_velocity_max = 90.0
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.12) if s != "winter" else Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = sd.drift
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	drift.mesh = q
	drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drift)
	print("Penalty Shootout: %s pitch" % s)


func _prop(parts: Array, s: String, at: Vector3, i: int) -> void:
	match s:
		"winter":  # a snowman with a carrot nose and a scarf
			var w := Color(0.96, 0.97, 1.0)
			parts.append([MeshKit.sphere(0.5, 10), MeshKit.at(at + Vector3(0, 0.45, 0)), w])
			parts.append([MeshKit.sphere(0.36, 10), MeshKit.at(at + Vector3(0, 1.1, 0)), w])
			parts.append([MeshKit.sphere(0.25, 10), MeshKit.at(at + Vector3(0, 1.6, 0)), w])
			parts.append([MeshKit.cyl(0.0, 0.05, 0.25, 6), MeshKit.at(at + Vector3(0, 1.62, 0.3), Vector3.ONE, Vector3(PI * 0.5, 0, 0)),
				Color(1.0, 0.5, 0.1)])
			parts.append([MeshKit.cyl(0.3, 0.3, 0.1, 10), MeshKit.at(at + Vector3(0, 1.38, 0)), [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 1.0)][i % 2]])
			parts.append([MeshKit.cyl(0.9, 1.1, 0.25, 12), MeshKit.at(at + Vector3(0.3, 0.06, 0.2)), w])  # a snow pile
		"autumn":  # a pumpkin on a pile of leaves
			parts.append([MeshKit.cyl(0.8, 1.0, 0.18, 10), MeshKit.at(at + Vector3(0, 0.05, 0)), Color(0.9, 0.45, 0.12)])
			parts.append([MeshKit.sphere(0.4, 10), MeshKit.at(at + Vector3(0.2, 0.38, 0), Vector3(1.25, 0.85, 1.25)), Color(1.0, 0.55, 0.1)])
			parts.append([MeshKit.cyl(0.04, 0.05, 0.18, 6), MeshKit.at(at + Vector3(0.2, 0.78, 0)), Color(0.3, 0.5, 0.15)])
			parts.append([MeshKit.sphere(0.25, 8), MeshKit.at(at + Vector3(-0.45, 0.25, 0.3), Vector3(1.2, 0.85, 1.2)), Color(0.95, 0.7, 0.15)])
		"spring":  # a tub of pink and white flowers
			parts.append([MeshKit.cyl(0.45, 0.35, 0.5, 10), MeshKit.at(at + Vector3(0, 0.25, 0)), Color(0.55, 0.32, 0.18)])
			for k in 6:
				var a := float(k) * TAU / 6.0
				parts.append([MeshKit.sphere(0.16, 8), MeshKit.at(at + Vector3(cos(a) * 0.25, 0.6 + 0.08 * (k % 2), sin(a) * 0.25)),
					[Color(1.0, 0.6, 0.8), Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.3)][k % 3]])
		_:  # summer: a tall sunflower
			parts.append([MeshKit.cyl(0.04, 0.05, 1.6, 6), MeshKit.at(at + Vector3(0, 0.8, 0)), Color(0.3, 0.6, 0.2)])
			parts.append([MeshKit.cyl(0.42, 0.42, 0.06, 14), MeshKit.at(at + Vector3(0, 1.75, 0.05), Vector3.ONE, Vector3(PI * 0.5, 0, 0)),
				Color(1.0, 0.85, 0.15)])
			parts.append([MeshKit.cyl(0.2, 0.2, 0.08, 12), MeshKit.at(at + Vector3(0, 1.75, 0.1), Vector3.ONE, Vector3(PI * 0.5, 0, 0)),
				Color(0.4, 0.25, 0.1)])