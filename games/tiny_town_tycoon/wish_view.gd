extends Node3D
## Every machine: the townsfolk's WISH BUBBLES and the MIST over the districts that haven't opened yet.
## A wish (wishes.gd, published by the host as the "wish" state: [id, kind index, x, z, home]) is a
## glassy bubble bobbing over the house (or over the resource) with a tiny spinning model of the
## building inside and two thought-dots; a land wish also has a glowing ring pulsing on its resource.
## The mist is soft cloud puffs over every cell of a closed district; when a district opens its puffs
## rise, swell and vanish (open_district()).

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")

const BUBBLE_R := 0.038
const BUBBLE_UP := 0.095
const PUFFS := 2  ## per misty cell
const LEAVE_T := 1.8

var main: Node
var town: Town
var _bubbles := {}  ## wish id -> Node3D
var _wish_val: Array = []
var _mist: MultiMeshInstance3D
var _puff_xf: Array[Transform3D] = []
var _puff_d := PackedByteArray()
var _mist_key := ""
var _leaving := {}  ## district -> seconds since it started to clear
var _t := 0.0
var _bubble_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _dot_mesh: SphereMesh


func setup(p_main: Node, p_town: Town) -> void:
	main = p_main
	town = p_town
	_bubble_mat = StandardMaterial3D.new()
	_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_mat.albedo_color = Color(0.92, 0.97, 1.0, 0.42)
	_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_mat.rim_enabled = false
	_ring_mat = MeshKit.material(Color(1.0, 0.9, 0.4), 2.2)
	_dot_mesh = SphereMesh.new()
	_dot_mesh.radius = 0.006
	_dot_mesh.height = 0.012
	_dot_mesh.radial_segments = 8
	_dot_mesh.rings = 4
	_dot_mesh.material = MeshKit.material(Color(1, 1, 1))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 0.7
	puff.radial_segments = 10
	puff.rings = 5
	puff.material = MeshKit.material(Color(0.95, 0.96, 1.0))
	mm.mesh = puff
	_mist = MultiMeshInstance3D.new()
	_mist.name = "Mist"
	_mist.multimesh = mm
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mist)


## The mist over district k starts to clear (every machine, from the "mist" effect).
func open_district(k: int) -> void:
	if not _leaving.has(k):
		_leaving[k] = 0.0


func _process(delta: float) -> void:
	if town == null:
		return
	_t += delta
	var key := "%d:%d" % [town.open_mask, town.dist_version]
	if key != _mist_key and _leaving.is_empty():
		_mist_key = key
		_rebuild_mist()
	if not _leaving.is_empty():
		_clear_mist(delta)
	var wv: Variant = main.net.state_get("wish", [])
	var wl: Array = wv if wv is Array else []
	if wl != _wish_val:
		_wish_val = wl.duplicate(true)
		_sync_bubbles()
	for id in _bubbles:
		var n: Node3D = _bubbles[id]
		var inner: Node3D = n.get_meta("inner")
		inner.rotation.y = _t * 1.4 + float(id)
		var ph := float(id) * 1.7
		n.position = n.get_meta("base") + Vector3(0, sin(_t * 2.2 + ph) * 0.004, 0)
		var age := _t - float(n.get_meta("born"))
		var pop := minf(1.0, age * 3.0)
		n.scale = Vector3.ONE * (pop + sin(minf(age * 3.0, 1.0) * PI) * 0.25)
		if n.has_meta("ring"):
			var ring: Node3D = n.get_meta("ring")
			ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * 4.0))


# --- Mist ----------------------------------------------------------------------------------------------

func _rebuild_mist() -> void:
	_puff_xf.clear()
	_puff_d.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = town.seed_value * 7 + 3
	for z in Defs.GRID:
		for x in Defs.GRID:
			if town.is_open(x, z):
				continue
			var t := town.terrain(x, z)
			if t == Defs.T_WATER:
				continue
			var c := Defs.cell_center(x, z)
			for k in PUFFS:
				var s := Defs.CELL * rng.randf_range(0.9, 1.35)
				var off := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)) * Defs.CELL
				var y := rng.randf_range(0.01, 0.026)
				_puff_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * 0.8, s)), c + off + Vector3(0, y, 0)))
				_puff_d.append(town.district(x, z))
	var mm := _mist.multimesh
	mm.instance_count = _puff_xf.size()
	for i in _puff_xf.size():
		mm.set_instance_transform(i, _puff_xf[i])
	_mist.visible = not _puff_xf.is_empty()


func _clear_mist(delta: float) -> void:
	var mm := _mist.multimesh
	for k in _leaving.keys():
		_leaving[k] = float(_leaving[k]) + delta
	for i in _puff_xf.size():
		var k2 := int(_puff_d[i])
		if not _leaving.has(k2):
			continue
		var f := clampf(float(_leaving[k2]) / LEAVE_T - fmod(float(i) * 0.137, 0.4), 0.0, 1.0)
		var xf := _puff_xf[i]
		var grow := 1.0 + f * 0.8
		var shrink := 1.0 - smoothstep(0.55, 1.0, f)
		mm.set_instance_transform(i, Transform3D(xf.basis.scaled(Vector3.ONE * grow * maxf(shrink, 0.001)), xf.origin + Vector3(0, f * 0.12, 0)))
	var done := true
	for k3 in _leaving:
		done = done and float(_leaving[k3]) > LEAVE_T + 0.5
	if done:
		_leaving.clear()
		_mist_key = ""


# --- Wish bubbles -------------------------------------------------------------------------------------

func _sync_bubbles() -> void:
	var want := {}
	for w in _wish_val:
		var a: Array = w
		if a.size() >= 5:
			want[int(a[0])] = a
	for id in _bubbles.keys():
		if not want.has(id):
			var n: Node3D = _bubbles[id]
			n.queue_free()
			_bubbles.erase(id)
	for id in want:
		if not _bubbles.has(id):
			_bubbles[id] = _make_bubble(want[id])


func _make_bubble(a: Array) -> Node3D:
	var kind := Defs.kind_at(int(a[1]))
	var x := int(a[2])
	var z := int(a[3])
	var home := int(a[4])
	var root := Node3D.new()
	root.name = "Wish%d" % int(a[0])
	var base := Defs.cell_center(x, z)
	if home > 0:
		var b: Dictionary = town.buildings.get(home, {})
		if not b.is_empty():
			base = town.center_of(b)
	var up := BUBBLE_UP if home > 0 else BUBBLE_UP * 0.8
	root.set_meta("base", base + Vector3(0, up, 0))
	root.set_meta("born", _t)
	root.position = base + Vector3(0, up, 0)
	add_child(root)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BUBBLE_R
	sm.height = BUBBLE_R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	ball.mesh = sm
	ball.material_override = _bubble_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	var inner := Node3D.new()
	root.add_child(inner)
	root.set_meta("inner", inner)
	var s := Defs.size_of(kind)
	var model := MeshKit.instance(Art.building_mesh(kind, 0, 1, bool(Defs.island(town.island).get("snow", false))))
	var sc := Defs.CELL * 0.85 / float(s)
	model.scale = Vector3.ONE * sc
	model.position = Vector3(0, -BUBBLE_R * 0.62, 0)
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.add_child(model)
	for k in 2:
		var dot := MeshInstance3D.new()
		dot.mesh = _dot_mesh
		dot.scale = Vector3.ONE * (0.6 + k * 0.4)
		dot.position = Vector3(0.006 * (1 - k), -up + 0.03 + k * 0.016, 0.004)
		root.add_child(dot)
	var ring: Node3D = null
	if home == 0:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = Defs.CELL * 0.55
		tm.outer_radius = Defs.CELL * 0.68
		tm.rings = 24
		tm.ring_segments = 6
		mi.mesh = tm
		mi.material_override = _ring_mat
		mi.position = Vector3(0, -up + 0.004, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		ring = mi
	if ring != null:
		root.set_meta("ring", ring)
	return root


## The bubble for a wish (bots and effects), or null.
func bubble(id: int) -> Node3D:
	return _bubbles.get(id, null)


func bubble_count() -> int:
	return _bubbles.size()
