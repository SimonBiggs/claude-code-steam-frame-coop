extends Node3D
## A bouncing, glowing arrow pointing down at "the next thing to do" for ONE player: it lives on a
## render layer only that player's camera (or headset) sees. Call point(pos, scale) every frame, or hide_arrow().

var color := Color(1.0, 0.85, 0.2)
var layer := 1
var t := 0.0
var arrow: Node3D
var ring: MeshInstance3D
var mat: StandardMaterial3D
var ring_mat: StandardMaterial3D
var target := Vector3.ZERO
var scale_k := 1.0
var shown := false


func _ready() -> void:
	top_level = true
	arrow = Node3D.new()
	add_child(arrow)
	mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.render_priority = 5
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.32
	cone.height = 0.42
	cone.radial_segments = 10
	cone.rings = 1
	head.mesh = cone
	head.material_override = mat
	head.position.y = 0.21
	head.rotation.x = PI  # point down
	arrow.add_child(head)
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.4, 0.14)
	shaft.mesh = bm
	shaft.material_override = mat
	shaft.position.y = 0.6
	arrow.add_child(shaft)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.4
	tm.outer_radius = 0.5
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	ring_mat = mat.duplicate()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	add_child(ring)
	_set_layers(self)
	visible = false


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		n.layers = layer
	if n is GeometryInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_layers(c)


func point(pos: Vector3, k: float = 1.0) -> void:
	target = pos
	scale_k = k
	shown = true


func hide_arrow() -> void:
	shown = false


func _process(delta: float) -> void:
	t += delta
	visible = shown
	if not shown:
		return
	global_position = target
	scale = Vector3.ONE * scale_k
	arrow.position.y = 0.25 + absf(sin(t * 4.0)) * 0.35
	arrow.rotation.y = t * 2.0
	var pulse := fmod(t * 1.2, 1.0)
	ring.scale = Vector3.ONE * (0.6 + pulse * 0.9)
	ring_mat.albedo_color.a = 1.0 - pulse
	mat.emission_energy_multiplier = 2.0 + sin(t * 8.0)
