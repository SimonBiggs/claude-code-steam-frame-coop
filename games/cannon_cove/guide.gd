extends Node3D
## A bouncing, glowing arrow that points down at "the next thing to do" for ONE player: it lives on
## that player's view-model render layer, so only their own camera (or headset) sees it.
## Call point(world_pos) every frame, or hide_arrow().

const World := preload("res://games/cannon_cove/world.gd")

var color := Color(1.0, 0.85, 0.2)
var size := 1.0
var layer := 1
var t := 0.0
var arrow: Node3D
var ring: MeshInstance3D
var mat: StandardMaterial3D
var target := Vector3.ZERO
var shown := false
var scale_k := 1.0


func _ready() -> void:
	top_level = true
	arrow = Node3D.new()
	add_child(arrow)
	mat = World.mat(color, 2.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.render_priority = 5
	var head := World.cyl(arrow, 0.0, 0.32 * size, 0.42 * size, Vector3(0, 0.21 * size, 0), mat, 10)
	head.rotation.x = PI  # point down
	World.box(arrow, Vector3(0.14, 0.4, 0.14) * size, Vector3(0, 0.6 * size, 0), mat)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.4 * size
	tm.outer_radius = 0.5 * size
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := World.mat(color, 2.0)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.no_depth_test = false
	rm.render_priority = 5
	ring.material_override = rm
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
	shown = true
	scale_k = k


func hide_arrow() -> void:
	shown = false


func _process(delta: float) -> void:
	t += delta
	visible = shown
	if not shown:
		return
	global_position = target
	scale = Vector3.ONE * scale_k
	arrow.position.y = 0.25 * size + absf(sin(t * 4.0)) * 0.35 * size
	arrow.rotation.y = t * 2.0
	var pulse := fmod(t * 1.2, 1.0)
	ring.scale = Vector3.ONE * (0.6 + pulse * 0.9)
	(ring.material_override as StandardMaterial3D).albedo_color.a = 1.0 - pulse
	mat.emission_energy_multiplier = 2.0 + sin(t * 8.0) * 1.0
