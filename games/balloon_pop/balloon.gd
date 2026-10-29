extends Node3D
## One balloon (visual only, same on every machine): a shiny body, a knot and a string.
## It inflates with a bounce when it appears, sways while it floats, and wobbles when booped.
## The host moves it; the TV machine moves it from snapshots. Kinds (wavegen.gd): plain, GOLD (glows),
## GRUMPY (a cross face), ROCKET (long, with fins, zooms), ICE (frosty, glows pale blue), TWINS (three
## round balloons on one string), MINI (a little one from twins), GIANT (big; shrinks with each hit),
## CHOICE (a big white balloon carrying a little model of a ride: pop it to build that ride).

const ResCache := preload("res://core/res_cache.gd")
const WaveGen := preload("res://games/balloon_pop/wavegen.gd")
const Fair := preload("res://games/balloon_pop/fair.gd")

const NORMAL := WaveGen.NORMAL
const GOLD := WaveGen.GOLD
const GRUMPY := WaveGen.GRUMPY
const ROCKET := WaveGen.ROCKET
const ICE := WaveGen.ICE
const TWINS := WaveGen.TWINS
const MINI := WaveGen.MINI
const GIANT := WaveGen.GIANT
const CHOICE := WaveGen.CHOICE
const RADIUS := 0.3
const COLORS: Array[Color] = [Color(1.0, 0.25, 0.3), Color(0.25, 0.6, 1.0), Color(0.3, 0.9, 0.4),
	Color(1.0, 0.55, 0.15), Color(0.75, 0.4, 1.0), Color(1.0, 0.45, 0.8), Color(0.2, 0.9, 0.9)]
const GOLD_COLOR := Color(1.0, 0.82, 0.2)
const GRUMPY_COLOR := Color(0.45, 0.47, 0.52)
const ROCKET_COLOR := Color(1.0, 0.45, 0.15)
const ICE_COLOR := Color(0.72, 0.9, 1.0)
const CHOICE_COLOR := Color(0.98, 0.98, 1.0)
## Body size per kind (x = round, y = tall), relative to a plain balloon.
const SHAPE := {ROCKET: Vector2(0.75, 1.35), TWINS: Vector2(0.62, 0.62), MINI: Vector2(0.65, 0.65), GIANT: Vector2(1.85, 1.85),
	CHOICE: Vector2(1.35, 1.35)}

var kind := NORMAL
var color := Color.WHITE
var squish := 0.0  # 1 = just booped: wobbles, then settles
var push := Vector3.ZERO  # host: drift from a boop
var rise := 0.5  # host: m/s upwards
var phase := 0.0
var hp := 1  # hits left (a giant takes three)
var ride := ""  # CHOICE: the ride it carries
var col := 0
var set_id := -1  # host: the wave set it belongs to (wavegen.gd), -1 = none
var body: Node3D
var _t := 0.0
var _grow := 0.0


static func color_for(c: int, k: int) -> Color:
	match k:
		GOLD:
			return GOLD_COLOR
		GRUMPY:
			return GRUMPY_COLOR
		ROCKET:
			return ROCKET_COLOR
		ICE:
			return ICE_COLOR
		CHOICE:
			return CHOICE_COLOR
	return COLORS[absi(c) % COLORS.size()]


## How far from the middle a touch counts (main.gd: gloves and TV players).
static func reach_of(k: int, hits_left: int = 3) -> float:
	var r := RADIUS * float((SHAPE.get(k, Vector2.ONE) as Vector2).x)
	if k == TWINS:
		r = RADIUS * 1.2
	elif k == GIANT:
		r *= _giant_size(hits_left)
	return r


static func _giant_size(hits_left: int) -> float:
	return [0.55, 0.7, 0.85, 1.0][clampi(hits_left, 0, 3)]


## id: the balloon's number; k: kind; c: colour index (wavegen.gd); ride_id: a CHOICE's ride.
func setup(id: int, k: int, c: int = -1, ride_id: String = "") -> void:
	kind = k
	col = c if c >= 0 else id % COLORS.size()
	color = color_for(col, k)
	phase = float(id) * 1.7
	hp = WaveGen.HITS[k] if k < WaveGen.HITS.size() else 1
	ride = ride_id
	body = Node3D.new()
	add_child(body)
	var shape: Vector2 = SHAPE.get(k, Vector2.ONE)
	var glow := k == GOLD or k == ICE
	var bodies: Array[Vector3] = [Vector3.ZERO]
	if k == TWINS:
		bodies = [Vector3(-0.15, 0.02, 0.0), Vector3(0.15, 0.02, 0.0), Vector3(0.0, 0.26, 0.0)]
	for off in bodies:
		var mi := MeshInstance3D.new()
		mi.mesh = _body_mesh()
		mi.material_override = _shiny(color, glow)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = off
		mi.scale = Vector3(shape.x, shape.y, shape.x)
		body.add_child(mi)
	if k == ROCKET:  # three fins and a white stripe
		for f in 3:
			var fin := MeshInstance3D.new()
			fin.mesh = _bar_mesh()
			fin.material_override = _shiny(Color(1.0, 1.0, 1.0), false)
			fin.rotation = Vector3(0.0, f * TAU / 3.0, PI * 0.5)
			fin.position = Vector3(cos(f * TAU / 3.0) * 0.2, -0.3, -sin(f * TAU / 3.0) * 0.2)
			fin.scale = Vector3(1.4, 2.5, 1.0)
			body.add_child(fin)
	if k == CHOICE and ride != "":  # the ride it builds, hanging under it
		var model := MeshInstance3D.new()
		model.mesh = Fair.ride_mesh(ride)
		model.scale = Vector3.ONE * 0.16
		model.position.y = -RADIUS * shape.y * 1.25 - 0.75
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model)
		var pm := Fair.part_mesh(ride)
		if pm != null:
			var part := MeshInstance3D.new()
			part.mesh = pm
			part.position = model.position + Fair.part_pivot(ride) * 0.16
			part.scale = Vector3.ONE * 0.16
			add_child(part)
	var knot := MeshInstance3D.new()
	knot.mesh = _knot_mesh()
	knot.material_override = _shiny(color.darkened(0.2), false)
	knot.position.y = -RADIUS * 1.22 * shape.y + (-0.02 if k == TWINS else 0.0)
	knot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(knot)
	var s := MeshInstance3D.new()
	s.mesh = _string_mesh()
	s.material_override = _shiny(Color(0.95, 0.95, 0.95), false)
	s.position.y = -RADIUS * 1.25 * shape.y - 0.3
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


## A giant was hit (hits left): it shrinks a bit and wobbles.
func hit(left: int) -> void:
	hp = left
	squish = 1.0


func _process(delta: float) -> void:
	_t += delta
	_grow = minf(1.0, _grow + delta * 2.5)
	# Inflate with an overshoot, then wobble while squished.
	var g := 1.0 + sin(_grow * PI) * 0.25 if _grow < 1.0 else 1.0
	g *= minf(1.0, _grow * 1.6)
	if kind == GIANT:
		g *= _giant_size(hp)
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
