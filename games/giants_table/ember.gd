extends "res://games/giants_table/toss.gd"
## A glowing ember from the village campfire, dropped by a goblin. Knights carry it home by
## walking over it; the giant can pick it up and drop it back into the fire.

var t := 0.0
var orb: MeshInstance3D
var light: OmniLight3D


func _ready() -> void:
	add_to_group("embers")
	radius = 0.3
	center_h = 0.3
	orb = MeshInstance3D.new()
	orb.mesh = W.sphere(0.2, 10)
	orb.material_override = W.mat(Color(1.0, 0.55, 0.15), 5.0)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.position.y = 0.3
	add_child(orb)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 1.2
	light.omni_range = 2.0
	light.position.y = 0.4
	add_child(light)


func _physics_process(delta: float) -> void:
	t += delta
	orb.position.y = 0.3 + sin(t * 4.0) * 0.06
	orb.scale = Vector3.ONE * (1.0 + sin(t * 9.0) * 0.08)
	if ghost:
		ghost_update(delta)
		return
	if flying:
		fly(delta)


func _landed(impact: float) -> void:
	super._landed(impact)
	main.ember_landed(self)


func _fell_off() -> void:
	main.ember_home(self, "The ember floated home!")


func net_item() -> Array:
	return [net_id, "ember", global_position, 0.0]
