extends Node3D
## WARNING RINGS (shared: Duo Arena's boss slams and pads, Snowball Blitz's Snow King and Yeti): a pulsing ring on the
## ground that grows in, then stays until the attack it TELLS lands. Every machine draws its own (the host sends the
## numbers in an event), so a boss's tell reads the same on the TV, the Decks and in VR.
##   var rings := WarnRings.new(); add_child(rings)
##   rings.warn(pos, radius, colour, secs)      count() -> rings showing now

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

var _warns: Array = []  # [node, age, secs, radius]


func _ready() -> void:
	if name.is_empty() or name.begins_with("@"):
		name = "WarnRings"


static func ring_mesh() -> ArrayMesh:
	return ResCache.get_or_make("warn_ring_v1", func() -> Resource:
		var b := MeshKit.builder()
		b.torus(1.0, 0.07, MeshKit.at(Vector3.ZERO), Color.WHITE, 40, 4)
		b.torus(0.6, 0.04, MeshKit.at(Vector3.ZERO), Color.WHITE, 28, 4)
		b.torus(0.25, 0.03, MeshKit.at(Vector3.ZERO), Color.WHITE, 16, 4)
		return b.build()) as ArrayMesh


## Every machine: a pulsing ring at pos (on the ground under it) for secs.
func warn(pos: Vector3, radius: float, col: Color, secs: float, ground_y: float = 0.08) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ring_mesh()
	mi.material_override = MeshKit.material(col, 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius * 0.2, 1.0, radius * 0.2)
	add_child(mi)
	if is_inside_tree():
		mi.global_position = Vector3(pos.x, ground_y, pos.z)
	else:
		mi.position = Vector3(pos.x, ground_y, pos.z)
	_warns.append([mi, 0.0, maxf(secs, 0.3), radius])


func count() -> int:
	return _warns.size()


func _process(delta: float) -> void:
	var keep: Array = []
	for w in _warns:
		var n: MeshInstance3D = w[0]
		w[1] = float(w[1]) + delta
		if float(w[1]) >= float(w[2]) or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			continue
		var grow := minf(1.0, float(w[1]) / 0.3)
		var k := (0.9 + 0.1 * absf(sin(float(w[1]) * 12.0))) * grow
		n.scale = Vector3(float(w[3]) * k, 1.0, float(w[3]) * k)
		keep.append(w)
	_warns = keep