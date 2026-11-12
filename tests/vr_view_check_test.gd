extends SceneTree
## core/vr_view_check.gd and the VR UI placement it guards (UiKit.vr_place / vr_spot / vr_ride, HudKit's VR cards)
## (run headless: godot-test --headless --path . -s res://tests/vr_view_check_test.gd). Prints VR VIEW CHECK: PASS / FAIL.
const VrViewCheck := preload("res://core/vr_view_check.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const VrRig := preload("res://core/vr_rig.gd")

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
	# 5a. a nearer banner that shows up AFTER a story card (Ghost Lantern's NIGHT 2 at 1.7 m over Granny Boo's card at
	# 2.56 m): drawn over it although the two sit at different depths, and the card steps out of its way
	var story := HudKit.vr_card(world, cam, "GRANNY BOO", "a line", {"width": 1.0, "height": -0.22})
	await _frames(20)
	var night := Label3D.new()
	night.font_size = 48
	night.pixel_size = 0.0026
	night.text = "NIGHT 2"
	world.add_child(night)
	UiKit.VrText.follow(night, cam, world, -0.1, 1.7)
	_check(VrViewCheck.overlap(cam.global_position, night, story), "a near banner over a far card counts as drawn over")
	for i in 30:
		UiKit.VrText.follow(night, cam, world, -0.1, 1.7)
		await _frames(1)
	probs = VrViewCheck.problems(root)
	_check(not ", ".join(probs).contains("drawn over"), "a card steps out of a banner that shows up after it: %s" % [probs])
	_clear_ui()

	# 5b. see-through scenery (a lake's water) behind a card must draw under it, not be blended over it
	var lake := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	lake.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.albedo_color = Color(0.2, 0.5, 0.7, 0.8)
	lake.material_override = wm
	world.add_child(lake)
	lake.global_position = Vector3(0, 0.0, 0)
	var low := HudKit.vr_card(world, cam, "OLLIE", "a line", {"width": 1.0, "height": -0.6})
	await _frames(20)
	probs = VrViewCheck.problems(root)
	_check(", ".join(probs).contains("washed out"), "blended water behind a card (priority 0) is reported: %s" % [probs])
	wm.render_priority = UiKit.VR_PRIO_UNDER_UI
	await _frames(1)
	probs = VrViewCheck.problems(root)
	_check(not ", ".join(probs).contains("washed out"), "water at VR_PRIO_UNDER_UI is fine: %s" % [probs])
	lake.free()
	low = null
	_clear_ui()

	# 5c. a card never covers a pick orb (core/pick_orbs.gd KEEP_CLEAR; UiKit.vr_dodge moves VR UI clear of them)
	var orbs := PickOrbs.new()
	world.add_child(orbs)
	var ents: Array = []
	for id in PickOrbs.MODE_IDS:
		ents.append(PickOrbs.mode(id))
	# a row just where a story card goes (0.35 m under the eyes, beyond the card)
	orbs.show_orbs("mode", ents, Vector3(0, 0, -4.2), 1.6, cam.global_position.y - 0.4)
	await _frames(3)
	var over := UiKit.label3d("RIGHT OVER THE PICKS", 0.12)
	world.add_child(over)
	over.global_position = Vector3(0, cam.global_position.y - 0.35, -2.56)
	over.set_meta("vr_placed", true)
	await _frames(1)
	probs = VrViewCheck.problems(root)
	_check(", ".join(probs).contains("drawn over the pick"), "a panel over a pick orb is reported: %s" % [probs])
	over.free()
	await _frames(1)
	var sc := StoryCard.show_vr(world, cam, {"who": "PIP", "line": "Pick one!", "pic": "bird", "duration": 30.0})
	await _frames(40)
	probs = VrViewCheck.problems(root)
	_check(not ", ".join(probs).contains("drawn over the pick"), "a story card shown during a pick sits clear of the orbs: %s" % [probs])
	_check(probs.is_empty(), "the moved story card is still fine to read: %s" % [probs])
	_check(absf(sc.global_position.y - (cam.global_position.y - 0.35)) > 0.1, "the story card moved off its usual spot (y %.2f)" % sc.global_position.y)
	orbs.clear()
	await _frames(40)
	# the card already up, then the picks come: it glides clear
	var ok := false
	orbs.show_orbs("mode", ents, Vector3(0, 0, -4.2), 1.6, cam.global_position.y - 0.4)
	for i in 400:
		await _frames(1)
		if i > 3 and not ", ".join(VrViewCheck.problems(root)).contains("drawn over the pick"):
			ok = true
			break
	_check(ok, "a card already up glides clear when the picks come: %s" % [VrViewCheck.problems(root)])
	# picks at eye level, nowhere above: the card goes under them
	orbs.show_orbs("mode", ents, Vector3(0, 0, -4.2), 1.6, cam.global_position.y)
	await _frames(1)
	sc = StoryCard.show_vr(world, cam, {"who": "PIP", "line": "Up high!", "pic": "bird", "duration": 30.0})
	for i in 400:  # (the first card glides; headless frames are short)
		await _frames(1)
		probs = VrViewCheck.problems(root)
		if i > 30 and probs.is_empty():
			break
	_check(probs.is_empty(), "picks at eye level, two cards up: both clear of the picks and of each other: %s" % [probs])
	orbs.free()
	_clear_ui()
	await _frames(2)

	# 6. games use the shared PAUSED card (no hand-made ones left to pile up)
	for dir in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/main.gd" % dir
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains("vr_card(self, vr_rig.camera, \"PAUSED\""):
			_check(false, "%s: use HudKit.vr_paused for the VR PAUSED card" % path)

	# 7. the fake VR head stands where a real Steam Frame player's head is (VrViewCheck.head_problems, VrRig.fake_stand)
	_check(VrViewCheck.head_problems(cam).is_empty(), "a head 1.6 m up under an XROrigin3D is a real one")
	var flat := Camera3D.new()
	world.add_child(flat)
	flat.position = Vector3(0, 6, 8)
	var rider := XRCamera3D.new()
	flat.add_child(rider)
	rider.current = false
	_check(not VrViewCheck.head_problems(rider).is_empty(), "a head riding on a flat camera is reported")
	flat.free()
	XRServer.world_scale = 10.0
	_check(not VrViewCheck.head_problems(cam).is_empty(), "1.6 world units up in a x10 world (ant's eyes) is reported")
	VrRig.fake_stand(cam, null, null, 10.0)
	_check(VrViewCheck.head_problems(cam).is_empty() and is_equal_approx(cam.position.y, 16.0), "fake_stand times world_scale: %.2f" % cam.position.y)
	XRServer.world_scale = 20.0  # a game scales its world later: FakeTracking moves the head like real tracking
	await _frames(2)
	_check(is_equal_approx(cam.position.y, 32.0), "FakeTracking rescales the head with world_scale: %.2f" % cam.position.y)
	XRServer.world_scale = 1.0
	await _frames(2)
	_check(is_equal_approx(cam.position.y, 1.6), "and back at world_scale 1: %.2f" % cam.position.y)
	OS.set_environment("BOT_VR_SEATED", "1")
	VrRig.fake_stand(cam)
	_check(is_equal_approx(cam.position.y, VrRig.FAKE_EYE_SEATED) and VrViewCheck.head_problems(cam).is_empty(), "BOT_VR_SEATED sits the fake player down: %.2f" % cam.position.y)
	OS.unset_environment("BOT_VR_SEATED")
	var head_at := VrRig.fake_head_at(world, Vector3(1, 0.8, 2), PI)
	_check(head_at.get_parent() is XROrigin3D and head_at.global_position.distance_to(Vector3(1, 0.8 + VrRig.FAKE_EYE, 2)) < 0.01 and VrViewCheck.head_problems(head_at).is_empty(), "fake_head_at stands on the VR spawn: %s" % head_at.global_position)
	_check((-head_at.global_basis.z).dot(Vector3.BACK) > 0.99, "fake_head_at faces its yaw")
	head_at.get_parent().free()
	VrRig.fake_stand(cam)
	# no game or bot stands its fake head by hand (a hand-typed 1.5 / 1.2 m, not times world_scale, 2026-11-12)
	var hand_typed := RegEx.create_from_string("(xr_camera|rig\\.camera)\\.position(\\.y)? = (Vector3\\(0(\\.0)?, )?1\\.[0-9]")
	var files: Array[String] = []
	for dir in DirAccess.get_directories_at("res://games"):
		for f in DirAccess.get_files_at("res://games/" + dir):
			if f.ends_with(".gd"):
				files.append("res://games/%s/%s" % [dir, f])
	for f in DirAccess.get_files_at("res://tests"):
		if f.ends_with("_bot.gd"):
			files.append("res://tests/" + f)
	for path in files:
		var m := hand_typed.search(FileAccess.get_file_as_string(path))
		if m != null:
			_check(false, "%s: a fake VR head stood by hand (%s): use VrRig.fake_stand / kit.vr_head_height / kit.vr_idle" % [path, m.get_string()])

	print("VR VIEW CHECK: %s%s" % ["PASS" if fails.is_empty() else "FAIL", "" if fails.is_empty() else " (%d)" % fails.size()])
	quit(0 if fails.is_empty() else 1)
