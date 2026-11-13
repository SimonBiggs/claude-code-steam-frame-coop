extends Node3D
## SOFT DODGEBALL: TUMTUM'S BALL GIFTS at work on every machine (deep.gd GIFTS; the round's gift comes in the "deep"
## state, the runners' bubbles in the "shields" state):
##   SQUISHY BALL   every ball looks big and squishy (main.gd scales the ball meshes; a runner's belly hit counts more).
##   CURVE BALL     a runner's throw curves to the belly (main.gd: no wobble, a bigger belly target).
##   BUBBLE SHIELD  a see-through bubble round every runner who still has one (their first hit just pops it).
##   SPEEDY SHOES   runners run faster (main.gd).
##   BALL MAGNET    runners grab balls from further and loose balls roll to them (host, main.gd).
## Cheap: one shared bubble mesh, see-through under the VR cards (UiKit.VR_PRIO_UNDER_UI).
##   set_gift(id), set_shields(ids), follow(avatars) every frame

const UiKit := preload("res://core/ui_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Deep := preload("res://games/dodge_ball/deep.gd")

const BUBBLE_R := 0.75

var main
var gift := ""
var bubbles := {}  # runner id -> MeshInstance3D
var shield_ids: Array = []


func _ready() -> void:
	name = "Gifts"


## Every machine: this round's gift ("" none).
func set_gift(id: String) -> void:
	if id == gift:
		return
	gift = id
	if id != "shield":
		set_shields([])


## Every machine: the runners who still have a bubble.
func set_shields(ids: Array) -> void:
	shield_ids = ids.duplicate()
	for id in bubbles.keys():
		if not shield_ids.has(id):
			var b: MeshInstance3D = bubbles[id]
			if is_instance_valid(b):
				main.burst(b.global_position, Color(0.75, 1.0, 1.0), 16, 0.08)
				main.sfx.play_at("pop", b.global_position, -4.0, 1.4)
				b.queue_free()
			bubbles.erase(id)
	for id in shield_ids:
		if not bubbles.has(id):
			var b := MeshInstance3D.new()
			b.name = "Bubble%d" % int(id)
			b.mesh = _bubble_mesh()
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(b)
			bubbles[id] = b


## Every frame: the bubbles ride with their runners (hidden while a runner is out).
func follow(avatars: Dictionary, clock: float) -> void:
	for id in bubbles:
		var b: MeshInstance3D = bubbles[id]
		if not is_instance_valid(b):
			continue
		if not avatars.has(id) or not is_instance_valid(avatars[id]):
			b.visible = false
			continue
		var a: Node3D = avatars[id]
		b.visible = a.visible
		b.position = a.position + Vector3(0.0, 0.85, 0.0)
		var s := 1.0 + 0.04 * sin(clock * 4.0 + float(id))
		b.scale = Vector3(s, s * 1.15, s)


static func _bubble_mesh() -> Mesh:
	return ResCache.get_or_make("dodge_bubble", func() -> Resource:
		var sm := SphereMesh.new()
		sm.radius = BUBBLE_R
		sm.height = BUBBLE_R * 2.0
		sm.radial_segments = 20
		sm.rings = 10
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		UiKit.see_through(m)
		m.albedo_color = Color(0.6, 1.0, 0.95, 0.22)
		m.rim_enabled = false
		m.cull_mode = BaseMaterial3D.CULL_BACK
		sm.material = m
		return sm) as Mesh
