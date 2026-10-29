extends "res://tests/engine_ui/part_base.gd"
## Engine test part: the VR-only render layer (core/vr_layer.gd + core/vr_layer_guard.gd).
## - every core VR-only helper (VR card / banner / toast / countdown, VrMenu, StoryCard.show_vr, the
##   Awards VR summary, VrText.follow, UiKit.vr_place) puts everything it draws on VrLayer.LAYER only;
## - the guard strips the layer from flat (TV / Deck) cameras, even ones a game keeps resetting, and
##   gives it to XR cameras and VR mirrors (cameras a RemoteTransform3D under an XR camera drives);
## - no game uses bits 18-19 (VR-only UI / VrRig.AVATAR_LAYER) for its own layers (source lint).
## The bug this guards: in solo VR the TV split view saw the back of every VR story card (2.6 s dark box).

const VrLayer := preload("res://core/vr_layer.gd")
const VrRig := preload("res://core/vr_rig.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const VrMenu := preload("res://core/vr_menu.gd")
const VrText := preload("res://core/vr_text.gd")
const StoryCard := preload("res://core/story_card.gd")
const Awards := preload("res://core/awards.gd")

const LAYERISH := ["layer", "LAYER", "cull_mask", "_BITS", "BODIES", "_MASK", "_BIT"]


func run() -> void:
	tag = "vr_layer"
	var L := VrLayer.LAYER
	check(L == 1 << 18 and UiKit.VR_LAYER == L and L != VrRig.AVATAR_LAYER, "one VR-only layer (bit 18), shared by UiKit")
	_lint_games()
	var guard := get_node_or_null("/root/VrLayerGuard")
	var own_guard: Node = null
	if guard == null:  # services not started in this run: test the script directly
		own_guard = load("res://core/vr_layer_guard.gd").new()
		add_child(own_guard)
	var world := Node3D.new()
	add_child(world)
	var head := Node3D.new()
	head.position = Vector3(0, 1.6, 0)
	world.add_child(head)
	var made := {}
	made["vr_card"] = HudKit.vr_card(world, head, "HELLO", "a line")
	made["vr_banner"] = HudKit.vr_banner(world, head, "ROUND 2", "go", {"sound": ""})
	made["vr_toast"] = HudKit.vr_toast(world, head, "nice")
	made["vr_countdown"] = HudKit.vr_countdown(world, head, 3, {"sound": "", "go_sound": ""})
	made["story_card"] = StoryCard.show_vr(world, head, {"who": "TEST", "line": "a line", "pic": "castle", "duration": 30.0})
	made["vr_menu"] = VrMenu.open(world, {"title": "PICK", "cam": head, "items": ["One", "Two"], "sounds": false, "haptics": false})
	made["awards_vr"] = Awards.vr_summary(world, head, {"title": "RESULTS", "rows": []})
	var text := Label3D.new()
	text.text = "VR TEXT"
	world.add_child(text)
	made["vr_text_follow"] = text
	var placed := MeshInstance3D.new()
	placed.mesh = QuadMesh.new()
	world.add_child(placed)
	made["ui_kit_vr_place"] = placed
	# cameras: a TV split-view camera, a game that keeps resetting its mask, the XR camera, a VR mirror
	var tv_vp := SubViewport.new()
	tv_vp.size = Vector2i(64, 64)
	world.add_child(tv_vp)
	var tv_cam := Camera3D.new()
	tv_vp.add_child(tv_cam)
	var origin := XROrigin3D.new()
	world.add_child(origin)
	var xr_cam := XRCamera3D.new()
	xr_cam.cull_mask = 1  # a whitelist that never named the VR layer
	origin.add_child(xr_cam)
	var mirror_vp := SubViewport.new()
	mirror_vp.size = Vector2i(64, 64)
	world.add_child(mirror_vp)
	var mirror_cam := Camera3D.new()
	mirror_cam.cull_mask = 0xFFFFF & ~L
	mirror_vp.add_child(mirror_cam)
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(mirror_cam)
	var rig_mirror := VrRig.build_mirror(world, xr_cam, false, 64)
	var rig_mirror_cam := rig_mirror.get_child(0) as Camera3D
	for i in 6:
		VrText.follow(text, xr_cam, world, 0.0, 1.8)
		UiKit.vr_follow(placed, xr_cam, 1.6, 0.0, 0.016)
		tv_cam.cull_mask = 0xFFFFF  # like a game setting its TV camera every frame
		await get_tree().process_frame
	await get_tree().process_frame
	for k in made:
		var bad := _off_layer(made[k], L)
		check(bad.is_empty(), "%s draws on the VR layer only%s" % [k, ("" if bad.is_empty() else " (not: %s)" % ", ".join(bad))])
	check(tv_cam.cull_mask & L == 0, "a TV camera never draws the VR layer (mask %x)" % tv_cam.cull_mask)
	check(xr_cam.cull_mask & L != 0, "the XR camera draws the VR layer")
	check(mirror_cam.cull_mask & L != 0 and mirror_cam.is_in_group(VrLayer.GROUP_VIEW), "a mirror driven from the XR camera draws the VR layer")
	check(rig_mirror_cam != null and rig_mirror_cam.cull_mask & L != 0, "VrRig.build_mirror's camera draws the VR layer")
	world.queue_free()
	if own_guard != null:
		own_guard.queue_free()
	await get_tree().process_frame


## Names of VisualInstance3Ds under n (incl. n; not inside SubViewports) not exactly on layer L.
func _off_layer(n: Node, L: int) -> Array:
	var out := []
	if n == null or not is_instance_valid(n):
		return ["(missing)"]
	if n is VisualInstance3D and (n as VisualInstance3D).layers != L:
		out.append("%s=%x" % [n.name, (n as VisualInstance3D).layers])
	for c in n.get_children():
		if not c is Viewport:
			out.append_array(_off_layer(c, L))
	return out


## Games keep their own layer schemes; bits 18-19 belong to the engine (VR-only UI, VR avatar).
func _lint_games() -> void:
	var bad := []
	var files := 0
	var shift := RegEx.create_from_string("(\\d+)\\s*<<\\s*(\\d+)\\b")
	var shift_var := RegEx.create_from_string("(\\d+)\\s*<<\\s*\\(\\s*(\\d+)\\s*\\+")
	var hex := RegEx.create_from_string("0x([0-9A-Fa-f]{5,6})\\b")
	for dir in DirAccess.get_directories_at("res://games"):
		for f in DirAccess.get_files_at("res://games/" + dir):
			if not f.ends_with(".gd"):
				continue
			files += 1
			var path := "res://games/%s/%s" % [dir, f]
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var line := lines[i]
				var hash_at := line.find("#")
				if hash_at >= 0:
					line = line.substr(0, hash_at)
				if line.contains("AVATAR") or not LAYERISH.any(func(w: String) -> bool: return line.contains(w)):
					continue
				var hit := false
				for m in shift.search_all(line):
					hit = hit or (int(m.get_string(1)) << int(m.get_string(2))) & (3 << 18) != 0
				for m in shift_var.search_all(line):
					hit = hit or (int(m.get_string(1)) << (int(m.get_string(2)) + 6)) & (3 << 18) != 0  # + a player index up to 6
				for m in hex.search_all(line):
					var v := m.get_string(1).hex_to_int()
					hit = hit or (v != 0xFFFFF and v & (3 << 18) != 0)
				if hit:
					bad.append("%s:%d" % [path.trim_prefix("res://games/"), i + 1])
	check(files > 100, "linted %d game scripts" % files)
	check(bad.is_empty(), "no game uses render bits 18-19 for its own layers%s" % ("" if bad.is_empty() else ": " + ", ".join(bad)))
