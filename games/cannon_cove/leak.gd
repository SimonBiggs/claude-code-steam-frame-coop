extends Node3D
## A hole in the deck spraying water. Deckhands hold the use button next to it to hammer a plank over it.

const World := preload("res://games/cannon_cove/world.gd")

const PATCH_TIME := 1.8
const RANGE := 1.7

var main
var net_id := 0
var ghost := false
var progress := 0.0
var fill: MeshInstance3D
var label: Label3D
var spray: CPUParticles3D
var t := 0.0


func _ready() -> void:
	add_to_group("leaks")
	var hole := World.cyl(self, 0.45, 0.45, 0.04, Vector3(0, 0.02, 0), World.mat(Color(0.08, 0.05, 0.03)), 12)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 4:
		var splinter := World.box(self, Vector3(0.08, 0.06, 0.4), Vector3(0, 0.04, 0), World.mat(Color(0.7, 0.5, 0.28)))
		splinter.rotation.y = i * PI / 2.0 + 0.4
		splinter.position = Basis(Vector3.UP, i * PI / 2.0 + 0.4) * Vector3(0.45, 0.04, 0)
	spray = CPUParticles3D.new()
	spray.amount = 16
	spray.lifetime = 0.8
	spray.direction = Vector3.UP
	spray.spread = 14.0
	spray.initial_velocity_min = 3.0
	spray.initial_velocity_max = 4.5
	spray.gravity = Vector3(0, -9.8, 0)
	spray.scale_amount_min = 0.6
	spray.scale_amount_max = 1.2
	var drop := SphereMesh.new()
	drop.radius = 0.08
	drop.height = 0.16
	drop.radial_segments = 6
	drop.rings = 3
	var water := World.mat(Color(0.35, 0.75, 1.0), 0.8, 0.1)
	drop.material = water
	spray.mesh = drop
	add_child(spray)
	fill = World.cyl(self, 0.6, 0.6, 0.03, Vector3(0, 0.05, 0), World.mat(Color(0.3, 1.0, 0.4, 0.7), 1.5), 16)
	(fill.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.visible = false
	label = Label3D.new()
	label.text = "LEAK!"
	label.font_size = 64
	label.outline_size = 26
	label.pixel_size = 0.006
	label.modulate = Color(0.45, 0.85, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 1.6
	add_child(label)


func _process(delta: float) -> void:
	t += delta
	label.position.y = 1.5 + sin(t * 4.0) * 0.12
	fill.visible = progress > 0.01
	var s := maxf(progress, 0.02)
	fill.scale = Vector3(s, 1.0, s)
	label.text = "PATCHING %d%%" % int(progress * 100.0) if progress > 0.01 else "LEAK!"


## Snapshot: [id, pos, progress]
func net_state() -> Array:
	return [net_id, position, progress]


func apply_net(item: Array) -> void:
	position = item[1]
	progress = item[2]
