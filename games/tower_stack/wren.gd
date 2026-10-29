extends Node3D
## WREN, Tower Stack's builder bird: a round brown bird in a blue hard hat. She perches on the gold
## hoop (the job's goal height), hops onto every finished tower to cheer, flutters when the tower
## wobbles. Purely visual and local: every machine moves its own Wren from the same states / events
## (main.gd calls perch() / visit() / flutter() / party()).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const BROWN := Color(0.62, 0.42, 0.25)
const SCALE := 1.4

var home := Vector3(-1.55, 1.2, 0.0)  # where she perches (main.gd: on the hoop)
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _fly_t := 1.0
var _fly_len := 1.0
var _back_t := -1.0  # seconds until she flies home again (after a visit)
var _party_t := 0.0
var _flap := 0.0
var _t := 0.0
var _body: Node3D
var _wings: Array[Node3D] = []


func _ready() -> void:
	name = "Wren"
	scale = Vector3.ONE * SCALE
	_body = Node3D.new()
	add_child(_body)
	_body.add_child(MeshKit.instance(_body_mesh()))
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.09 * side, 0.12, -0.01)
		_body.add_child(pivot)
		var w := MeshKit.instance(_wing_mesh(), false)
		w.position = Vector3(0.05 * side, -0.02, 0.0)
		pivot.add_child(w)
		_wings.append(pivot)
	position = home
	_to = home
	_from = home


static func _body_mesh() -> Mesh:
	return ResCache.get_or_make("tower_stack_wren", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.ellipsoid(Vector3(0.12, 0.11, 0.13), MeshKit.at(Vector3(0, 0.11, 0)), BROWN, 12)
		b.ellipsoid(Vector3(0.08, 0.07, 0.05), MeshKit.at(Vector3(0, 0.09, 0.09)), Color(0.95, 0.85, 0.7), 10)
		b.sphere(0.085, MeshKit.at(Vector3(0, 0.23, 0.05)), BROWN, 12)
		b.cone(0.03, 0.08, Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0.22, 0.16)), Color(1.0, 0.65, 0.2), 8)
		for sx in [-1.0, 1.0]:
			b.sphere(0.024, MeshKit.at(Vector3(0.045 * sx, 0.25, 0.115)), Color(1, 1, 1), 8)
			b.sphere(0.014, MeshKit.at(Vector3(0.048 * sx, 0.25, 0.132)), Color(0.05, 0.05, 0.1), 6)
			b.capsule_between(Vector3(0.04 * sx, 0.02, 0.0), Vector3(0.045 * sx, -0.06, 0.02), 0.012, Color(1.0, 0.65, 0.2), 6)
		b.box(Vector3(0.06, 0.03, 0.16), Transform3D(Basis.from_euler(Vector3(0.9, 0, 0)), Vector3(0, 0.2, -0.15)), BROWN.darkened(0.25))
		# The blue hard hat with a yellow stripe and brim.
		b.dome(0.085, MeshKit.at(Vector3(0, 0.27, 0.04)), Color(0.25, 0.55, 0.95), 12)
		b.cylinder(0.11, 0.11, 0.015, MeshKit.at(Vector3(0, 0.27, 0.05)), Color(0.2, 0.45, 0.85), 14)
		b.box(Vector3(0.025, 0.02, 0.17), MeshKit.at(Vector3(0, 0.345, 0.04)), Color(1.0, 0.85, 0.3))
		return b.build())


static func _wing_mesh() -> Mesh:
	return ResCache.get_or_make("tower_stack_wren_wing", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.ellipsoid(Vector3(0.03, 0.08, 0.1), MeshKit.at(Vector3(0, -0.02, -0.02)), BROWN.darkened(0.3), 8)
		return b.build())


## Sit on the hoop (it moves with each job's goal height).
func perch(at: Vector3) -> void:
	home = at
	if _back_t < 0.0:
		_fly(at)


## Hop over to `at` (the top of a finished tower), cheer, then fly home after `stay` seconds.
func visit(at: Vector3, stay: float = 3.0) -> void:
	_fly(at)
	_back_t = stay + _fly_len
	_party_t = stay


func flutter() -> void:
	_fly(position + Vector3(0.0, 0.6, 0.0))
	_back_t = 0.6


func party(secs: float = 2.0) -> void:
	_party_t = secs


func _fly(at: Vector3) -> void:
	_from = position
	_to = at
	_fly_len = clampf(_from.distance_to(_to) / 3.0, 0.35, 1.6)
	_fly_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _back_t >= 0.0:
		_back_t -= delta
		if _back_t < 0.0:
			_fly(home)
	var flying := _fly_t < 1.0
	if flying:
		_fly_t = minf(1.0, _fly_t + delta / _fly_len)
		var k := _fly_t * _fly_t * (3.0 - 2.0 * _fly_t)
		position = _from.lerp(_to, k) + Vector3.UP * sin(_fly_t * PI) * (0.4 + _from.distance_to(_to) * 0.15)
		var d := _to - _from
		if Vector2(d.x, d.z).length() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), minf(1.0, delta * 8.0))
	else:
		rotation.y = lerp_angle(rotation.y, 0.0, minf(1.0, delta * 3.0))  # face the TV and the giant
	_party_t -= delta
	var hop := 0.0
	if _party_t > 0.0 and not flying:
		hop = absf(sin(_t * 9.0)) * 0.12
	_body.position.y = hop + sin(_t * 2.5) * 0.008
	_body.rotation.z = sin(_t * 1.3) * 0.08 if not flying else 0.0
	_flap = 1.0 if flying or _party_t > 0.0 else maxf(0.0, _flap - delta * 3.0)
	for i in _wings.size():
		var sgn := -1.0 if i == 0 else 1.0
		var ang := (sin(_t * 26.0) * 0.9 + 0.5) * _flap
		_wings[i].rotation = Vector3(0.0, 0.0, -ang * sgn)
