extends Node3D
## PIP, the family's puppy (story.gd), hiding somewhere on the map each round: a little sitting dog made
## of spheres, his tail wagging (faster when someone is close), his ears twitching now and then. When he's
## found he hops, spins and pops away (main.gd shows the hearts and the story card). Same on every machine
## (main.gd sets `spot` / `found` from the host's snapshot).

const Story := preload("res://games/hide_and_seek/story.gd")

var tail: Node3D
var ears: Array[Node3D] = []
var body: Node3D
var t := 0.0
var excite := 0.0  # 0..1: someone is close (wag faster)
var hop_t := -1.0  # found: hop time


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var fur := Story.PIP_COLOR
	var light := Color(1.0, 0.92, 0.8)
	var dark := Color(0.35, 0.22, 0.15)
	_ball(body, Vector3(0, 0.2, 0), Vector3(0.2, 0.2, 0.26), fur)  # body
	_ball(body, Vector3(0, 0.18, -0.12), Vector3(0.13, 0.13, 0.12), light)  # tummy
	for s in [-1.0, 1.0]:
		_ball(body, Vector3(0.1 * s, 0.05, -0.15), Vector3(0.06, 0.05, 0.09), light)  # front paws
		_ball(body, Vector3(0.14 * s, 0.07, 0.1), Vector3(0.08, 0.07, 0.11), fur)  # back legs
	_ball(body, Vector3(0, 0.43, -0.12), Vector3(0.15, 0.14, 0.14), fur)  # head
	_ball(body, Vector3(0, 0.4, -0.25), Vector3(0.08, 0.065, 0.08), light)  # muzzle
	_ball(body, Vector3(0, 0.43, -0.32), Vector3(0.03, 0.025, 0.025), dark)  # nose
	for s in [-1.0, 1.0]:
		_ball(body, Vector3(0.06 * s, 0.48, -0.25), Vector3(0.025, 0.03, 0.02), Color(0.1, 0.08, 0.08))  # eyes
		var ear := Node3D.new()
		ear.position = Vector3(0.12 * s, 0.53, -0.1)
		body.add_child(ear)
		_ball(ear, Vector3(0.02 * s, -0.08, 0), Vector3(0.05, 0.11, 0.04), dark)
		ears.append(ear)
	_ball(body, Vector3(0, 0.33, -0.27), Vector3(0.035, 0.02, 0.03), Color(1.0, 0.45, 0.5))  # tongue
	# A red collar with a gold tag.
	var collar := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.115
	tm.rings = 12
	tm.ring_segments = 6
	collar.mesh = tm
	collar.material_override = _mat(Color(0.9, 0.2, 0.25))
	collar.position = Vector3(0, 0.33, -0.1)
	collar.rotation = Vector3(0.35, 0, 0)
	body.add_child(collar)
	_ball(body, Vector3(0, 0.27, -0.2), Vector3(0.025, 0.025, 0.01), Color(1.0, 0.85, 0.2), 0.6)
	tail = Node3D.new()
	tail.position = Vector3(0, 0.25, 0.24)
	body.add_child(tail)
	_ball(tail, Vector3(0, 0.08, 0.04), Vector3(0.035, 0.1, 0.035), fur)
	_ball(tail, Vector3(0, 0.17, 0.07), Vector3(0.03, 0.03, 0.03), light)


func _mat(c: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _ball(parent: Node3D, at: Vector3, radii: Vector3, c: Color, glow: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = _mat(c, glow)
	mi.position = at
	mi.scale = radii
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Hide at a spot (facing out into the room: `yaw`), or show that he's been found.
func hide_at(spot: Vector3, yaw: float) -> void:
	position = spot
	rotation = Vector3(0, yaw, 0)
	hop_t = -1.0
	visible = true
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.scale = Vector3.ONE


func found() -> void:
	if hop_t < 0.0 and visible:
		hop_t = 0.0


## The middle of Pip (the torch aims here).
func center() -> Vector3:
	return global_position + Vector3.UP * 0.3


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	tail.rotation.z = sin(t * lerpf(6.0, 18.0, excite)) * lerpf(0.5, 0.9, excite)
	for i in ears.size():
		ears[i].rotation.x = 0.4 * maxf(0.0, sin(t * 0.9 + i * 0.7) - 0.85) * 6.0
	body.position.y = absf(sin(t * 3.0)) * 0.015 * (1.0 + 3.0 * excite)
	if hop_t >= 0.0:
		hop_t += delta
		body.position.y = absf(sin(hop_t * 9.0)) * 0.35
		body.rotation.y = hop_t * 10.0
		if hop_t > 1.0:
			body.scale = Vector3.ONE * maxf(0.01, 1.0 - (hop_t - 1.0) * 4.0)
		if hop_t > 1.25:
			visible = false
