extends Node3D
## One balloon (visual only, same on every machine): a shiny body, a knot and a string.
## It inflates with a bounce when it appears, sways while it floats, and wobbles when booped.
## The host moves it; the TV machine moves it from snapshots.

const ResCache := preload("res://core/res_cache.gd")

const NORMAL := 0
const GOLD := 1
const GRUMPY := 2
const RADIUS := 0.3
const COLORS: Array[Color] = [Color(1.0, 0.25, 0.3), Color(0.25, 0.6, 1.0), Color(0.3, 0.9, 0.4),
	Color(1.0, 0.55, 0.15), Color(0.75, 0.4, 1.0), Color(1.0, 0.45, 0.8), Color(0.2, 0.9, 0.9)]
const GOLD_COLOR := Color(1.0, 0.82, 0.2)
const GRUMPY_COLOR := Color(0.45, 0.47, 0.52)

var kind := NORMAL
var color := Color.WHITE
var squish := 0.0  # 1 = just booped: wobbles, then settles
var push := Vector3.ZERO  # host: drift from a boop
var rise := 0.5  # host: m/s upwards
var phase := 0.0
var body: Node3D
var _t := 0.0
var _grow := 0.0


static func color_for(id: int, k: int) -> Color:
	if k == GOLD:
		return GOLD_COLOR
	if k == GRUMPY:
		return GRUMPY_COLOR
	return COLORS[id % COLORS.size()]


func setup(id: int, k: int) -> void:
	kind = k
	color = color_for(id, k)
	phase = float(id) * 1.7
	body = Node3D.new()
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = _body_mesh()
	mi.material_override = _shiny(color, k == GOLD)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var knot := MeshInstance3D.new()
	knot.mesh = _knot_mesh()
	knot.material_override = _shiny(color.darkened(0.2), false)
	knot.position.y = -RADIUS * 1.22
	knot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(knot)
	var s := MeshInstance3D.new()
	s.mesh = _string_mesh()
	s.material_override = _shiny(Color(0.95, 0.95, 0.95), false)
	s.position.y = -RADIUS * 1.25 - 0.3
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	if k == GRUMPY:
		# A cross little face: two slanted brows and a frown (one shared dark material).
		var dark := _shiny(Color(0.08, 0.08, 0.1), false)
		for side in [-1.0, 1.0]:
			var brow := MeshInstance3D.new()
			brow.mesh = _bar_mesh()
			brow.material_override = dark
			brow.position = Vector3(0.1 * side, 0.1, RADIUS * 0.93)
			brow.rotation.z = -0.5 * side
			body.add_child(brow)
		var mouth := MeshInstance3D.new()
		mouth.mesh = _bar_mesh()
		mouth.material_override = dark
		mouth.position = Vector3(0.0, -0.08, RADIUS * 0.97)
		mouth.scale = Vector3(1.3, 1.0, 1.0)
		body.add_child(mouth)
	body.scale = Vector3.ONE * 0.01


func boop() -> void:
	squish = 1.0


func _process(delta: float) -> void:
	_t += delta
	_grow = minf(1.0, _grow + delta * 2.5)
	# Inflate with an overshoot, then wobble while squished.
	var g := 1.0 + sin(_grow * PI) * 0.25 if _grow < 1.0 else 1.0
	g *= minf(1.0, _grow * 1.6)
	squish = maxf(0.0, squish - delta * 1.6)
	var w := sin(_t * 22.0) * squish * 0.22
	if body != null:
		body.scale = Vector3(g * (1.0 + w), g * (1.0 - w), g * (1.0 + w))
	rotation.z = sin(_t * 1.3 + phase) * 0.12 + w * 0.6
	rotation.x = sin(_t * 1.1 + phase * 0.5) * 0.08
	if kind == GRUMPY:
		rotation.y = _t * 0.9 + phase  # turns slowly so everyone sees its cross face


# --- Shared resources (cached in Engine metadata, so they survive hot reloads) ---------------------

static func _body_mesh() -> Mesh:
	return ResCache.get_or_make("bp_body_v1", func() -> Resource:
		var m := SphereMesh.new()
		m.radius = RADIUS
		m.height = RADIUS * 2.4
		m.radial_segments = 16
		m.rings = 10
		return m)


static func _knot_mesh() -> Mesh:
	return ResCache.get_or_make("bp_knot_v1", func() -> Resource:
		var m := CylinderMesh.new()
		m.top_radius = 0.015
		m.bottom_radius = 0.05
		m.height = 0.07
		m.radial_segments = 8
		return m)


static func _string_mesh() -> Mesh:
	return ResCache.get_or_make("bp_string_v1", func() -> Resource:
		var m := CylinderMesh.new()
		m.top_radius = 0.006
		m.bottom_radius = 0.006
		m.height = 0.6
		m.radial_segments = 4
		m.rings = 1
		return m)


static func _bar_mesh() -> Mesh:
	return ResCache.get_or_make("bp_bar_v1", func() -> Resource:
		var m := BoxMesh.new()
		m.size = Vector3(0.11, 0.025, 0.03)
		return m)


static func _shiny(c: Color, glow: bool) -> StandardMaterial3D:
	return ResCache.get_or_make("bp_mat_%s_%s" % [c.to_html(false), str(glow)], func() -> Resource:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.25
		m.metallic_specular = 0.8
		m.rim_enabled = true
		m.rim = 0.4
		if glow:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 0.6
		return m) as StandardMaterial3D
