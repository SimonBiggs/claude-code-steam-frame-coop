extends Node
## Engine-level VR text rules, applied to every Label3D in every game (created by core/net.gd).
## In VR, text that ignores depth or billboards towards the camera hurts to look at:
## - no_depth_test draws far text over nearer things (hands, rods), which reads as wrong depth;
## - a billboard is turned separately for each eye, which looks cross-eyed.
## So while a VR camera is active, every Label3D gets depth testing, and billboarded ones are
## instead turned (yaw only) towards the player's head once per frame. A Label3D reads from +Z.
## Flat screens (the TV) are left alone: billboards are fine there.

var faced: Array[Label3D] = []
var active := false


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var vr := cam is XRCamera3D
	# Hitch log: in VR a slow frame can show as a black flash, so record every frame over 30 ms
	# (in game.log, with the time) to match against reports like "the screen goes black".
	if vr and delta > 0.03:
		print("[hitch] %d ms at %s" % [int(delta * 1000.0), Time.get_time_string_from_system()])
	if vr and not active:
		_sweep(get_tree().root)  # labels made before the guard started
	active = vr
	if not vr:
		return
	var head := cam.global_position
	for i in range(faced.size() - 1, -1, -1):
		var l := faced[i]
		if not is_instance_valid(l):
			faced.remove_at(i)
			continue
		if not l.is_visible_in_tree():
			continue
		var d := l.global_position - head
		d.y = 0.0
		if d.length() > 0.01:
			var sc := l.global_basis.get_scale()
			l.global_basis = Basis(Vector3.UP, atan2(-d.x, -d.z)).scaled(sc)  # +Z back at the head (other sign mirrors)


func _on_node_added(n: Node) -> void:
	if active and n is Label3D:
		_fix.call_deferred(n)  # after the game has finished setting it up


func _sweep(n: Node) -> void:
	if n is Label3D:
		_fix(n)
	for c in n.get_children():
		_sweep(c)


func _fix(l: Label3D) -> void:
	if not is_instance_valid(l):
		return
	l.no_depth_test = false
	if l.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		if not faced.has(l):
			faced.append(l)
