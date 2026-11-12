extends Node3D
## OBSTACLE RUSH: COACH JELLY'S GIFTS at work on every machine (deep.gd GIFTS; the course's gift comes in the "deep"
## state, the runners' bubbles in the "shields" state). The gift is the whole team's for one course:
##   SPRING SHOES   a springy coil under every runner's feet (runner.gd: jump higher).
##   GLIDE CAPE     a little cape on every runner's back (runner.gd: fall slowly).
##   STAR MAGNET    a magnet over every runner's head (main.gd: grab stars from further).
##   BUBBLE         a see-through bubble round every runner who still has one (runner.gd: the next bonk pops it).
##   ZOOM SHOES     orange shoes (runner.gd: run faster).
## Cheap: one shared mesh per look, see-through under the VR cards (UiKit.VR_PRIO_UNDER_UI).
##   set_gift(id), set_shields(ids), follow(runners) every frame

const UiKit := preload("res://core/ui_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/obstacle_rush/deep.gd")

const BUBBLE_R := 0.85

var main
var gift := ""
var looks := {}  # runner id -> Node3D (the gift's look on that runner)
var bubbles := {}  # runner id -> MeshInstance3D
var shield_ids: Array = []


func _ready() -> void:
	name = "Gifts"


## Every machine: this course's gift ("" none).
func set_gift(id: String) -> void:
	if id == gift:
		return
	gift = id
	for k in looks:
		if is_instance_valid(looks[k]):
			(looks[k] as Node).queue_free()
	looks.clear()
	if id != "bubble":
		set_shields([])


## Every machine: the runners who still have a bubble.
func set_shields(ids: Array) -> void:
	shield_ids = ids.duplicate()
	for id in bubbles.keys():
		if not shield_ids.has(id):
			var b: MeshInstance3D = bubbles[id]
			if is_instance_valid(b):
				main.confetti(b.global_position, Color(0.75, 1.0, 1.0), 14)
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


## Every frame: the bubbles ride with their runners; each runner wears the gift.
func follow(runners: Dictionary, clock: float) -> void:
	for id in bubbles:
		var b: MeshInstance3D = bubbles[id]
		if not is_instance_valid(b):
			continue
		if not runners.has(id) or not is_instance_valid(runners[id]):
			b.visible = false
			continue
		var r: Node3D = runners[id]
		b.visible = r.visible
		b.position = r.position + Vector3(0.0, 0.6, 0.0)
		var s := 1.0 + 0.04 * sin(clock * 4.0 + float(id))
		b.scale = Vector3(s, s * 1.1, s)
	if gift == "" or gift == "bubble":
		return
	for id in runners:
		var r = runners[id]
		if not is_instance_valid(r) or r.body == null:
			continue
		if looks.has(id) and is_instance_valid(looks[id]):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "GiftLook"
		mi.mesh = _look_mesh(gift)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if gift == "springs":
			r.add_child(mi)  # under the feet (not spinning with a tumble)
		else:
			r.body.add_child(mi)
		looks[id] = mi
	for id in looks.keys():
		if not runners.has(id):
			if is_instance_valid(looks[id]):
				(looks[id] as Node).queue_free()
			looks.erase(id)


static func _look_mesh(id: String) -> Mesh:
	return ResCache.get_or_make("rush_gift_%s" % id, func() -> Resource:
		var b := MeshKit.Builder.new()
		var col: Color = Deep.gift(id).get("color", Color.WHITE)
		match id:
			"springs":  # a coil under each foot
				for s in [-1.0, 1.0]:
					for k in 3:
						b.torus(0.09, 0.025, MeshKit.at(Vector3(s * 0.15, -0.02 - 0.06 * k, 0.0)), col, 10, 4)
			"cape":  # a cape down the back (the runner's back is +Z)
				b.box(Vector3(0.62, 0.7, 0.04), MeshKit.at(Vector3(0.0, 0.6, 0.38), Vector3.ONE, Vector3(0.18, 0.0, 0.0)), col)
				b.box(Vector3(0.5, 0.08, 0.1), MeshKit.at(Vector3(0.0, 0.95, 0.33)), col.darkened(0.25))
			"magnet":  # a horseshoe magnet over the head
				b.box(Vector3(0.1, 0.26, 0.1), MeshKit.at(Vector3(-0.13, 1.5, 0.0)), col)
				b.box(Vector3(0.1, 0.26, 0.1), MeshKit.at(Vector3(0.13, 1.5, 0.0)), col)
				b.box(Vector3(0.36, 0.1, 0.1), MeshKit.at(Vector3(0.0, 1.66, 0.0)), col)
				b.box(Vector3(0.1, 0.07, 0.1), MeshKit.at(Vector3(-0.13, 1.35, 0.0)), Color(0.9, 0.92, 0.95))
				b.box(Vector3(0.1, 0.07, 0.1), MeshKit.at(Vector3(0.13, 1.35, 0.0)), Color(0.9, 0.92, 0.95))
			_:  # zoom shoes: orange shoes with a white stripe
				for s in [-1.0, 1.0]:
					b.box(Vector3(0.2, 0.12, 0.32), MeshKit.at(Vector3(s * 0.15, 0.06, -0.04)), col)
					b.box(Vector3(0.21, 0.04, 0.1), MeshKit.at(Vector3(s * 0.15, 0.09, -0.04)), Color(1, 1, 1))
		var m := b.build()
		return m) as Mesh


static func _bubble_mesh() -> Mesh:
	return ResCache.get_or_make("rush_bubble", func() -> Resource:
		var sm := SphereMesh.new()
		sm.radius = BUBBLE_R
		sm.height = BUBBLE_R * 2.0
		sm.radial_segments = 20
		sm.rings = 10
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.6, 1.0, 0.95, 0.22)
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under the VR cards
		sm.material = m
		return sm) as Mesh
