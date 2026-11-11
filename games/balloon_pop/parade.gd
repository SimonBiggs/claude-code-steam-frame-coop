extends Node3D
## POPPY'S BALLOON PARADE (skies.gd): a ring of balloons on strings circling slowly high over the fair. One joins for
## every round with a star (two for three stars, one more for today's sky); it grows over days (save "parade") and
## unlocks Poppy's gifts. Every machine draws it from the host's net state "parade" (a number). One draw call (a
## MultiMesh); the newest balloon bounces in when it joins.

const Balloon := preload("res://games/balloon_pop/balloon.gd")
const Skies := preload("res://games/balloon_pop/skies.gd")
const ResCache := preload("res://core/res_cache.gd")

const RADIUS := 9.0
const HEIGHT := 8.2
const SPEED := 0.05  # rad / s

var count := 0
var mm: MultiMeshInstance3D
var t := 0.0
var join_t := 9.0  # seconds since the newest joined (it bounces in)


func _ready() -> void:
	name = "Parade"
	mm = MultiMeshInstance3D.new()
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.mesh = _mesh()
	m.instance_count = Skies.PARADE_DRAWN
	m.visible_instance_count = 0
	mm.multimesh = m
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)


## The parade's size (every machine, from the host's state).
func set_count(n: int) -> void:
	if n > count and count > 0:
		join_t = 0.0
	count = maxi(0, n)
	var shown := mini(count, Skies.PARADE_DRAWN)
	mm.multimesh.visible_instance_count = shown
	for i in shown:
		mm.multimesh.set_instance_color(i, Balloon.COLORS[i % Balloon.COLORS.size()])
	_place()


func _process(delta: float) -> void:
	t += delta
	join_t += delta
	if count > 0:
		_place()


func _place() -> void:
	var shown := mini(count, Skies.PARADE_DRAWN)
	for i in shown:
		var a := t * SPEED + i * TAU / maxf(12.0, float(shown))
		var y := HEIGHT + sin(t * 0.8 + i * 1.3) * 0.25
		var s := 1.0
		if i == shown - 1 and join_t < 1.2:
			s = 1.0 + sin(join_t * 10.0) * 0.4 * (1.0 - join_t / 1.2)
		var b := Basis(Vector3.UP, -a).scaled(Vector3.ONE * s * 1.6)
		mm.multimesh.set_instance_transform(i, Transform3D(b, Vector3(sin(a) * RADIUS, y, -cos(a) * RADIUS)))


## One balloon on a string, white (the instance colour tints it).
static func _mesh() -> Mesh:
	return ResCache.get_or_make("bp_parade_v1", func() -> Resource:
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.72
		sm.radial_segments = 12
		sm.rings = 6
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.3
		m.rim_enabled = true
		m.rim = 0.4
		sm.material = m
		return sm)
