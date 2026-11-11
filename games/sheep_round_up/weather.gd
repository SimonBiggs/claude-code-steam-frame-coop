extends Node3D
## SHEEP ROUND-UP SEASONS AND WEATHER (second pass, seasons.gd), drawn the same on every machine from the field's
## seed and the calendar: the grass colour of the season, falling rain / snow / blossom / leaves, and for a windy
## field everything blows one way (the sheep drift that way too: main.gd _sim_sheep).
##   weather.show_field(season, kind, wind)    weather.ground_color(season)

const Seasons := preload("res://games/sheep_round_up/seasons.gd")

var season := ""
var kind := ""
var parts: CPUParticles3D


func _ready() -> void:
	name = "Weather"


static func ground_color(s: String) -> Color:
	return (Seasons.SEASON_LOOK.get(s, Seasons.SEASON_LOOK.summer) as Dictionary).ground


func show_field(s: String, k: String, wind: Vector2) -> void:
	season = s
	kind = k
	if parts != null:
		parts.queue_free()
		parts = null
	var what := ""
	match k:
		"rainy":
			what = "rain"
		"snowy":
			what = "snow"
		"windy":
			what = "leaves" if s == "autumn" else ("blossom" if s == "spring" else "")
		_:
			what = "blossom" if s == "spring" else ("leaves" if s == "autumn" else "")
	if what == "":
		return
	parts = CPUParticles3D.new()
	parts.name = "Falling"
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	parts.emission_box_extents = Vector3(10.0, 0.2, 10.0)
	parts.position = Vector3(0.0, 7.0, 0.0)
	parts.direction = Vector3(wind.x, -1.0, wind.y) if k == "windy" else Vector3.DOWN
	parts.spread = 8.0
	parts.gravity = Vector3.ZERO
	var mesh: Mesh
	var col := Color.WHITE
	match what:
		"rain":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.02, 0.35, 0.02)
			mesh = bm
			col = Color(0.65, 0.8, 1.0)
			parts.amount = 220
			parts.initial_velocity_min = 11.0
			parts.initial_velocity_max = 13.0
			parts.lifetime = 0.7
		"snow":
			var sm := SphereMesh.new()
			sm.radius = 0.05
			sm.height = 0.1
			sm.radial_segments = 6
			sm.rings = 3
			mesh = sm
			parts.amount = 160
			parts.initial_velocity_min = 1.0
			parts.initial_velocity_max = 1.6
			parts.lifetime = 5.0
		_:
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.12, 0.02, 0.09)
			mesh = bm2
			col = Color(1.0, 0.7, 0.85) if what == "blossom" else Color(0.95, 0.55, 0.15)
			parts.amount = 60
			parts.initial_velocity_min = 1.2
			parts.initial_velocity_max = 2.0
			parts.lifetime = 5.0
			parts.angular_velocity_min = -180.0
			parts.angular_velocity_max = 180.0
	if k == "windy":
		parts.initial_velocity_min += 2.0
		parts.initial_velocity_max += 3.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	(mesh as PrimitiveMesh).material = mat
	parts.mesh = mesh
	parts.preprocess = parts.lifetime
	add_child(parts)
