extends RefCounted
## World-locked VR text. Panels stay put so the player can turn their head to read them, and glide
## back in front only when the player turns well away (more than 35 degrees) or walks off.
## Usage, every frame: VrText.follow(label, xr_camera, self, height_offset, distance)


static func follow(l: Label3D, cam: Node3D, world: Node, height: float, dist: float = 1.8) -> void:
	if l == null or cam == null or not is_instance_valid(l):
		return
	if l.get_parent() == cam:
		l.reparent(world)  # panels used to be glued to the headset
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # turning your head must not turn the text
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var target := cam.global_position + fwd * dist + Vector3(0.0, height, 0.0)
	if not l.has_meta("vr_placed"):
		l.set_meta("vr_placed", true)
		_place(l, cam, target)
		return
	var to := l.global_position - cam.global_position
	to.y = 0.0
	if fwd.angle_to(to.normalized()) > deg_to_rad(35.0) or to.length() > dist * 1.45 or to.length() < dist * 0.55:
		l.set_meta("vr_moving", true)
	if l.get_meta("vr_moving", false):
		var dt := cam.get_process_delta_time()
		_place(l, cam, l.global_position.lerp(target, 1.0 - exp(-4.0 * dt)))
		if l.global_position.distance_to(target) < 0.05 * dist:
			l.set_meta("vr_moving", false)


## Snap in front right away (e.g. when the game pauses, since nothing else moves then).
static func snap(l: Label3D) -> void:
	if l != null and is_instance_valid(l):
		l.remove_meta("vr_placed")


static func _place(l: Label3D, cam: Node3D, pos: Vector3) -> void:
	l.global_position = pos
	var face := pos - cam.global_position
	face.y = 0.0
	if face.length() > 0.01:
		l.global_basis = Basis(Vector3.UP, atan2(-face.x, -face.z)).scaled(l.global_basis.get_scale())  # front (+Z) towards the player
