extends MeshInstance3D
## A soapy cannon bubble. On the host it pops balloons and storm sprites (main decides); on the TV
## machine it is just for show and vanishes when it reaches a target.

const LIFE := 1.9

var main
var vel := Vector3.ZERO
var life := LIFE
var owner_index := 1
var visual_only := false


func _process(delta: float) -> void:
	life -= delta
	global_position += vel * delta
	var s := minf(1.0, (LIFE - life) * 8.0) * (1.0 + sin(life * 25.0) * 0.06)
	scale = Vector3.ONE * s
	if life <= 0.0:
		queue_free()
		return
	for t in get_tree().get_nodes_in_group("dr_targets"):
		var n := t as Node3D
		var r: float = n.get_meta("radius", 1.4)
		if n.global_position.distance_squared_to(global_position) < (r + 0.35) * (r + 0.35):
			if not visual_only:
				main.on_bubble_hit(self, n)
			else:
				main.puff(global_position, Color(0.75, 0.95, 1.0), 5, 0.08)
			queue_free()
			return
