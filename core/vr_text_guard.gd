extends Node
## Engine-level VR text rules, applied to every Label3D in every game (created by core/net.gd).
## In VR, text that ignores depth or billboards towards the camera hurts to look at:
## - no_depth_test draws far text over nearer things (hands, rods), which reads as wrong depth;
## - a billboard is turned separately for each eye, which looks cross-eyed.
## So while a VR camera is active, every Label3D gets depth testing, and billboarded ones are
## instead turned (yaw only) towards the player's head once per frame. A Label3D reads from +Z.
## Flat screens (the TV) are left alone: billboards are fine there.

var faced: Array[Label3D] = []
var fake_head: XRCamera3D = null
## Billboard labels nearer than this (metres, x world scale) to a camera fade out (_fix).
const NEAR_FADE := 0.7
var active := false
## Fallback capture mirror: scenes without their own gdev_capture SubViewport (e.g. the arcade lobby)
## would record black, because the VR main viewport's texture isn't readable. Follows the XR camera.
var mirror: SubViewport
var mirror_cam: Camera3D
var mirror_t := 0.0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var vr := cam is XRCamera3D
	var fake := false
	if not vr and OS.has_environment("BOT_VR"):
		# Fake VR (bots): the TV camera is current, but the headset's rules must hold so bots and VR shots see
		# what a real headset player sees (and the TV the same labels as with a real headset).
		var heads := get_tree().root.find_children("*", "XRCamera3D", true, false) if Engine.get_process_frames() % 30 == 0 or fake_head == null or not is_instance_valid(fake_head) else [fake_head]
		fake_head = heads[0] if not heads.is_empty() else null
		if fake_head != null and fake_head.is_inside_tree():
			cam = fake_head
			vr = true
			fake = true
	# Hitch log: in VR a slow frame can show as a black flash, so record every frame over 30 ms
	# (in game.log, with the time) to match against reports like "the screen goes black".
	if vr and not fake and delta > 0.03:
		print("[hitch] %d ms at %s" % [int(delta * 1000.0), Time.get_time_string_from_system()])
	if vr and (not active or get_meta("rules_v", 0) != 4):
		set_meta("rules_v", 4)  # bump when _fix changes, so a hot reload re-applies it to existing labels
		_sweep(get_tree().root)  # labels made before the guard started
	active = vr
	if not vr:
		return
	if not fake:
		_update_mirror(cam, delta)
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
	# A raised render priority draws text over see-through things (light beams, glass) even when
	# it's behind them; let transparent sorting by distance decide instead.
	l.render_priority = 0
	l.outline_render_priority = -1
	# Readable in the headset (Abigail: "the writing is very dark"): a solid dark outline, and dark
	# text colours lifted towards white.
	l.outline_size = maxi(l.outline_size, 12)
	l.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	var c := l.modulate
	if c.get_luminance() < 0.6:
		l.modulate = Color(c.lerp(Color.WHITE, 0.6), c.a)
	if l.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		if not faced.has(l):
			faced.append(l)
		# A name tag or pop-up word that comes within arm's length of a face (a TV player walking through the VR
		# player, Balloon Pop) filled the whole headset view with giant letters: it fades out up close (visibility
		# range is measured from each camera, so far-off TV cameras still see it). Not the VR player's own hand and
		# wrist labels (under the XROrigin3D).
		if l.visibility_range_begin == 0.0 and not _on_rig(l):
			var ws := maxf(XRServer.world_scale, 0.001)
			l.visibility_range_begin = NEAR_FADE * ws
			l.visibility_range_begin_margin = 0.2 * ws
			l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _update_mirror(cam: Camera3D, delta: float) -> void:
	var others := get_tree().get_nodes_in_group("gdev_capture").filter(func(n: Node) -> bool: return n != mirror)
	if not others.is_empty():
		if is_instance_valid(mirror):
			mirror.queue_free()  # the scene has its own mirror
			mirror = null
		return
	if not is_instance_valid(mirror):
		mirror = SubViewport.new()
		mirror.size = Vector2i(480, 480)  # small: it is an extra scene render on a phone-class GPU
		mirror.world_3d = get_tree().root.world_3d
		mirror.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mirror_cam = Camera3D.new()
		mirror_cam.fov = 90.0
		mirror_cam.add_to_group(preload("res://core/vr_layer.gd").GROUP_VIEW)
		mirror.add_child(mirror_cam)
		add_child(mirror)
		mirror.add_to_group("gdev_capture")
	mirror_cam.global_transform = cam.global_transform
	mirror_cam.current = true
	mirror_t -= delta
	if mirror_t <= 0.0:
		mirror_t = 1.0 / 5.0  # enough for frame-at; more caused visible jitter on the Frame
		mirror.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_rig(n: Node) -> bool:
	var x := n.get_parent()
	while x != null:
		if x is XROrigin3D:
			return true
		x = x.get_parent()
	return false
