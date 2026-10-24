extends Node3D
## ELEMENTAL BENDER: pooled visual effects (every machine; purely visual).
## - Puffs: ONE MultiMeshInstance3D holds every little glowing ball (trails, bursts, auras, dust).
##   They move, shrink and recycle in a ring buffer, so a busy fight is still one draw call instead of
##   hundreds of tweened nodes (the source game's puff nodes were too heavy for the Steam Frame).
## - Rings: an expanding glowing torus (specials, Spirit State).
## - Spikes: a ring of stone spikes bursting out of the ground (Earthquake), one MultiMesh per quake.

const E := preload("res://games/elemental_bender/elem.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

var capacity := 640
var mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _size := PackedFloat32Array()
var _col := PackedColorArray()
var _next := 0
var _buf := PackedFloat32Array()
var _quakes: Array = []  # [MultiMeshInstance3D, age, centre, Array[Vector3] spots]


## Call before adding to the tree to shrink the pool (VR: fewer puffs).
func setup(cap: int) -> void:
	capacity = cap


func _ready() -> void:
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ResCache.get_or_make("eb_puff_mesh_v1", func() -> Resource:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 8
		s.rings = 4
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.material = m
		return s)
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
	add_child(_mmi)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_life.resize(capacity)
	_max.resize(capacity)
	_size.resize(capacity)
	_col.resize(capacity)
	_buf.resize(capacity * 16)


## One glowing ball at `pos` that drifts with `vel` and shrinks away over `life` seconds.
func puff(pos: Vector3, color: Color, size: float, life: float, vel: Vector3 = Vector3.ZERO) -> void:
	var i := _next
	_next = (_next + 1) % capacity
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_max[i] = maxf(life, 0.01)
	_size[i] = size
	_col[i] = Color(color.r, color.g, color.b, 0.85)


## A burst of `n` puffs flying outwards.
func burst(pos: Vector3, color: Color, n: int, speed: float = 4.0, size: float = 0.3, life: float = 0.5) -> void:
	for k in n:
		var v := Vector3(randf_range(-1, 1), randf_range(0.2, 1.5), randf_range(-1, 1)) * speed
		puff(pos, color, size, life * randf_range(0.7, 1.1), v)


## An expanding glowing ring on the ground plus a ring of puffs.
func ring(pos: Vector3, color: Color, radius: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ResCache.get_or_make("eb_ring_mesh_v1", func() -> Resource:
		var t := TorusMesh.new()
		t.inner_radius = 0.85
		t.outer_radius = 1.0
		t.rings = 24
		t.ring_segments = 6
		return t)
	mi.material_override = E.mat(Color(color.r, color.g, color.b, 0.6), 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.5
	mi.scale = Vector3(0.5, 2.0, 0.5)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 2.0, radius), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(mi.queue_free)
	for k in 20:
		var d := Vector3(cos(k * TAU / 20.0), 0.1, sin(k * TAU / 20.0))
		puff(pos + Vector3.UP * 0.6, color, 0.35, life, d * radius / life)


## Earthquake: three rings of stone spikes burst out of the ground and sink back.
func spikes(pos: Vector3, radius: float) -> void:
	var spots: Array[Vector3] = []
	var cols := PackedColorArray()
	for ring_i in 3:
		var r := radius * (ring_i + 1) / 3.0
		var n := 8 + ring_i * 5
		for k in n:
			var a := k * TAU / n + ring_i * 0.3
			spots.append(Vector3(cos(a) * r, float(ring_i), sin(a) * r))  # y = ring index (delay)
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = ResCache.get_or_make("eb_spike_mesh_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cone(0.5, 2.0, MeshKit.at(Vector3.ZERO), E.ROCK, 5)
		return b.build())
	m.instance_count = spots.size()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	_quakes.append([mi, 0.0, pos, spots])
	burst(pos + Vector3.UP * 0.3, Color(0.6, 0.5, 0.35), 24, 6.0, 0.4, 0.6)


func _process(delta: float) -> void:
	var n := 0
	for i in capacity:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		_pos[i] += _vel[i] * delta
		var k := _life[i] / _max[i]
		var s := _size[i] * (k * (2.0 - k))  # ease out to nothing
		var p := _pos[i]
		var c := _col[i]
		var o := n * 16
		_buf[o] = s
		_buf[o + 1] = 0.0
		_buf[o + 2] = 0.0
		_buf[o + 3] = p.x
		_buf[o + 4] = 0.0
		_buf[o + 5] = s
		_buf[o + 6] = 0.0
		_buf[o + 7] = p.y
		_buf[o + 8] = 0.0
		_buf[o + 9] = 0.0
		_buf[o + 10] = s
		_buf[o + 11] = p.z
		_buf[o + 12] = c.r
		_buf[o + 13] = c.g
		_buf[o + 14] = c.b
		_buf[o + 15] = c.a
		n += 1
	if n > 0:
		mm.buffer = _buf
	mm.visible_instance_count = n
	_step_quakes(delta)


func _step_quakes(delta: float) -> void:
	for q in _quakes.duplicate():
		var mi: MultiMeshInstance3D = q[0]
		var age: float = float(q[1]) + delta
		q[1] = age
		var spots: Array[Vector3] = q[3]
		if age > 1.5 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_quakes.erase(q)
			continue
		for k in spots.size():
			var sp := spots[k]
			var t := age - sp.y * 0.1
			var y := -1.2
			if t > 0.0:
				if t < 0.12:
					y = lerpf(-1.2, 0.6, t / 0.12)
				elif t < 0.72:
					y = 0.6
				else:
					y = lerpf(0.6, -1.5, minf((t - 0.72) / 0.4, 1.0))
			var b := Basis.from_euler(Vector3(0.2 * sin(k * 1.7), k * 2.3, 0.2 * cos(k * 1.3)))
			mi.multimesh.set_instance_transform(k, Transform3D(b, Vector3(sp.x, y, sp.z)))
