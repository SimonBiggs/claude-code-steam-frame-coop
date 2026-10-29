extends Node
## Engine-wide VR layer rule (a service, core/services.gd): every frame, every XR camera and VR view
## draws core/vr_layer.gd's LAYER and every other camera (TV / Deck split views, spy glasses, maps)
## leaves it out, whatever cull_mask the game set. Also makes a camera that a RemoteTransform3D under
## an XR camera drives (the games' gdev VR mirrors) a VR view. Runs last (process_priority) and while
## paused, so a game resetting cull_mask in its own _process can't undo it before the frame is drawn.

const VrLayer := preload("res://core/vr_layer.gd")

var cams: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100000
	get_tree().node_added.connect(_on_node_added)
	_sweep(get_tree().root)


func _sweep(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_sweep(c)


func _on_node_added(n: Node) -> void:
	if n is Camera3D:
		if not cams.has(n):
			cams.append(n)
		VrLayer.fix_camera(n)
	elif n is RemoteTransform3D:
		_check_follow.call_deferred(n)


## A camera driven from an XR camera is a mirror of the VR view.
func _check_follow(rt: RemoteTransform3D) -> void:
	if not is_instance_valid(rt) or not rt.is_inside_tree() or not rt.get_parent() is XRCamera3D:
		return
	var target := rt.get_node_or_null(rt.remote_path)
	if target is Camera3D:
		target.add_to_group(VrLayer.GROUP_VIEW)
		VrLayer.fix_camera(target)


func _process(_delta: float) -> void:
	for i in range(cams.size() - 1, -1, -1):
		var c = cams[i]
		if not is_instance_valid(c):
			cams.remove_at(i)
		elif c.is_inside_tree():
			VrLayer.fix_camera(c)
		else:
			cams.remove_at(i)  # node_added brings it back if it re-enters
