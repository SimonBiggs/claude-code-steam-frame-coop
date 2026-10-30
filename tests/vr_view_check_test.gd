extends SceneTree
## core/vr_view_check.gd and the VR UI placement it guards (UiKit.vr_place / vr_spot / vr_ride, HudKit's VR cards)
## (run headless: godot-test --headless --path . -s res://tests/vr_view_check_test.gd). Prints VR VIEW CHECK: PASS / FAIL.
const VrViewCheck := preload("res://core/vr_view_check.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")

var fails: Array[String] = []
var world: Node3D
var origin: XROrigin3D
var cam: XRCamera3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		await physics_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("  FAIL ", what)


func _clear_ui() -> void:
	for c in world.get_children():
		if c != origin and not c is StaticBody3D:
			c.free()


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	origin = XROrigin3D.new()
	world.add_child(origin)
	cam = XRCamera3D.new()
	origin.add_child(cam)
	cam.position = Vector3(0, 1.6, 0)
	await _frames(2)

	# 1. a story-card-sized card in the open: nothing to report, 0.5-3.8 m away, facing the head
	var c := HudKit.vr_card(world, cam, "HELLO", "a line", {"width": 1.0, "height": -0.22})
	await _frames(20)
	var probs := VrViewCheck.problems(root)
	_check(probs.is_empty(), "a card in the open is fine: %s" % [probs])
	var d := cam.global_position.distance_to(c.global_position)
	_check(d > 2.0 and d < 3.0, "a card sits ~2.6 m away (%.2f)" % d)

	# 2. it rides with the rig (a dragon, a kart, a teleport)
	origin.global_position += Vector3(5, 0, 0)
	await _frames(2)
	d = cam.global_position.distance_to(c.global_position)
	_check(d > 2.0 and d < 3.0, "a card rides along when the rig moves (%.2f m after a 5 m move)" % d)
	origin.global_position = Vector3.ZERO
	_clear_ui()
	await _frames(2)

	# 3. a wall 1.5 m in front: a new card comes in front of it, and nothing is hidden
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	wall.add_child(mi)
	world.add_child(wall)
	wall.global_position = Vector3(0, 1.6, -1.5)
	await _frames(3)
	c = HudKit.vr_card(world, cam, "BEHIND?", "", {"width": 1.0, "height": -0.22})
	await _frames(20)
	d = cam.global_position.distance_to(c.global_position)
	_check(d < 1.45, "a card comes in front of a wall 1.5 m away (%.2f m)" % d)
	probs = VrViewCheck.problems(root)
	_check(probs.is_empty(), "nothing hidden behind the wall: %s" % [probs])
	_clear_ui()
	wall.free()
	await _frames(2)

	# 4. the check catches: too far, facing away, hidden, words in the face, glued to the head
	var far := UiKit.label3d("FAR AWAY", 0.07)
	world.add_child(far)
	far.global_position = cam.global_position + Vector3(0, 0, -6)
	far.set_meta("vr_placed", true)
	await _frames(1)
	probs = VrViewCheck.problems(root)
	_check(", ".join(probs).contains("from the head"), "a panel 6 m away is reported: %s" % [probs])
	far.global_position = cam.global_position + Vector3(0, 0, -2.5)
	far.rotation.y = PI  # its back to the player (mirrored writing)
	await _frames(1)
	probs = VrViewCheck.problems(root)
	_check(", ".join(probs).contains("doesn't face"), "a panel facing away is reported: %s" % [probs])
	far.rotation.y = 0.0
	var wall2 := StaticBody3D.new()
	var shape2 := CollisionShape3D.new()
	shape2.shape = box
	wall2.add_child(shape2)
	world.add_child(wall2)
	wall2.global_position = cam.global_position + Vector3(0, 0, -1.2)
	await _frames(3)
	probs = VrViewCheck.problems(root)
	_check(", ".join(probs).contains("hidden behind"), "a panel behind a wall is reported: %s" % [probs])
	wall2.free()
	far.free()
	var tag := UiKit.label3d("P2", 0.2)
	world.add_child(tag)
	tag.global_position = cam.global_position + Vector3(0, 0, -0.3)
	await _frames(1)
	probs = VrViewCheck.problems(root)
	_check(", ".join(probs).contains("in the face"), "a name tag 0.3 m in front of the eyes is reported: %s" % [probs])
	tag.free()
	var glued := UiKit.label3d("GLUED", 0.05)
	cam.add_child(glued)
	glued.position = Vector3(0, 0, -1)
	await _frames(1)
	probs = VrViewCheck.problems(root)
	_check(", ".join(probs).contains("glued"), "text under the XR camera is reported: %s" % [probs])
	glued.free()
	await _frames(1)

	# 5. a new banner / PAUSED card takes the place of the last one; two cards don't share a spot
	HudKit.vr_banner(world, cam, "ONE", "", {"sound": ""})
	HudKit.vr_banner(world, cam, "TWO", "", {"sound": ""})
	HudKit.vr_paused(world, cam, "")
	HudKit.vr_paused(world, cam, "")
	await _frames(30)
	probs = VrViewCheck.problems(root)
	_check(not ", ".join(probs).contains("drawn over"), "banners / PAUSED cards don't pile up: %s" % [probs])
	_clear_ui()
	HudKit.vr_card(world, cam, "STORY", "a line", {"width": 1.0})
	HudKit.vr_card(world, cam, "TITLE", "", {"width": 1.0})
	await _frames(30)
	probs = VrViewCheck.problems(root)
	_check(not ", ".join(probs).contains("drawn over"), "a second card steps out of the first one's spot: %s" % [probs])
	_clear_ui()

	# 6. games use the shared PAUSED card (no hand-made ones left to pile up)
	for dir in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/main.gd" % dir
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains("vr_card(self, vr_rig.camera, \"PAUSED\""):
			_check(false, "%s: use HudKit.vr_paused for the VR PAUSED card" % path)

	print("VR VIEW CHECK: %s%s" % ["PASS" if fails.is_empty() else "FAIL", "" if fails.is_empty() else " (%d)" % fails.size()])
	quit(0 if fails.is_empty() else 1)
