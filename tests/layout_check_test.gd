extends SceneTree
## core/layout_check.gd catches what it should and nothing else (run headless:
## godot-test --headless --path . -s res://tests/layout_check_test.gd). Prints LAYOUT CHECK: PASS / FAIL.
const LayoutCheck := preload("res://core/layout_check.gd")
const HudKit := preload("res://core/hud_kit.gd")


func _initialize() -> void:
	_run.call_deferred()


func _label(parent: Node, text: String, pos: Vector2, size := Vector2(200, 40)) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	l.position = pos
	l.size = size
	return l


func _run() -> void:
	var fails: Array[String] = []
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	_label(ui, "SCORE 12", Vector2(20, 20))
	_label(ui, "0:42", Vector2(400, 20))
	await process_frame
	await process_frame
	var p := LayoutCheck.problems(root)
	if not p.is_empty():
		fails.append("two labels apart are fine, got %s" % [p])
	var over := _label(ui, "POPPY SAYS HI", Vector2(30, 25))
	await process_frame
	p = LayoutCheck.problems(root)
	if not p.any(func(s: String) -> bool: return s.begins_with("overlap")):
		fails.append("a label over the score is caught, got %s" % [p])
	over.modulate.a = 0.0
	await process_frame
	if not LayoutCheck.problems(root).is_empty():
		fails.append("a faded-out label doesn't count")
	over.queue_free()
	var vr := root.get_visible_rect()
	var cut := _label(ui, "CUT OFF", Vector2(vr.size.x - 40, 100))
	await process_frame
	p = LayoutCheck.problems(root)
	if not p.any(func(s: String) -> bool: return s.begins_with("cut")):
		fails.append("a label past the right edge is caught, got %s" % [p])
	cut.queue_free()
	# A scrolled-away row of a list is clipped, not "cut off".
	var sc := ScrollContainer.new()
	ui.add_child(sc)
	sc.position = Vector2(20, 200)
	sc.size = Vector2(300, 100)
	var v := VBoxContainer.new()
	sc.add_child(v)
	for i in 40:
		var l := Label.new()
		l.text = "ROW %d" % i
		v.add_child(l)
	await process_frame
	await process_frame
	p = LayoutCheck.problems(root)
	if not p.is_empty():
		fails.append("rows scrolled out of a list are fine, got %s" % [p])
	# Centred text in a wide label only counts the words.
	sc.queue_free()
	var wide := _label(ui, "HI", Vector2(0, 600), Vector2(vr.size.x, 40))
	wide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(ui, "LEFT", Vector2(10, 600))
	await process_frame
	p = LayoutCheck.problems(root)
	if not p.is_empty():
		fails.append("a centred word doesn't overlap a label at the far left, got %s" % [p])
	# A label under a story card's panel (group layout_cover) is hidden; the card's own text isn't.
	var cover := PanelContainer.new()
	cover.add_to_group(LayoutCheck.COVER_GROUP)
	ui.add_child(cover)
	cover.position = Vector2(0, 590)
	cover.size = Vector2(300, 80)
	var own := Label.new()
	own.text = "CARD LINE"
	cover.add_child(own)
	await process_frame
	p = LayoutCheck.problems(root)
	if not p.any(func(s: String) -> bool: return s.begins_with("covered") and s.contains("LEFT")):
		fails.append("a label under a story card is caught, got %s" % [p])
	if p.any(func(s: String) -> bool: return s.contains("CARD LINE")):
		fails.append("the card's own line is not 'covered', got %s" % [p])
	# Split screen: a big centre word over both views crosses the line; HudKit.split_center gives each view its own.
	ui.queue_free()
	await process_frame
	var ui2 := Control.new()
	ui2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui2)
	var cams: Array[Camera3D] = []
	for i in 2:
		var c := SubViewportContainer.new()
		c.stretch = true
		ui2.add_child(c)
		c.position = Vector2(i * vr.size.x * 0.5, 0)
		c.size = Vector2(vr.size.x * 0.5 - 2.0, vr.size.y)
		var sv := SubViewport.new()
		c.add_child(sv)
		var cam := Camera3D.new()
		sv.add_child(cam)
		cam.current = true
		cams.append(cam)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var word := Label.new()
	word.text = "HOORAY!"
	word.add_theme_font_size_override("font_size", int(vr.size.y * 0.06))
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(word)
	word.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	p = LayoutCheck.problems(root)
	if not p.any(func(s: String) -> bool: return s.begins_with("divider")):
		fails.append("a big word across two split views is caught, got %s" % [p])
	HudKit.split_center(word)
	for i in 4:
		await process_frame
	p = LayoutCheck.problems(root)
	if not p.is_empty():
		fails.append("split_center puts the word in each view, got %s" % [p])
	var shown := word.find_children("ViewCopy*", "Label", false, false).filter(func(c: Node) -> bool: return (c as Label).is_visible_in_tree())
	if shown.size() != 2:
		fails.append("split_center shows one copy per view, got %d" % shown.size())
	word.text = ""
	await process_frame
	await process_frame
	shown = word.find_children("ViewCopy*", "Label", false, false).filter(func(c: Node) -> bool: return (c as Label).is_visible_in_tree())
	if not shown.is_empty():
		fails.append("an emptied centre word hides its copies")
	# A pop-up word right in front of a camera stays small and inside that view.
	var world := Node3D.new()
	root.add_child(world)
	var cam0 := cams[0]
	cam0.get_viewport().world_3d = root.find_world_3d()
	cams[1].get_viewport().world_3d = root.find_world_3d()
	cams[1].global_position = Vector3(0, 0, 50)
	cam0.global_position = Vector3.ZERO
	var near := HudKit.popup(world, Vector3(0.0, 0.0, -0.4), "TORNADO BURST!", {"size": 1.5})
	var edge := HudKit.popup(world, Vector3(0.9, 0.0, -2.0), "STAR! +15")
	for i in 6:
		await process_frame
	for l in [near, edge]:
		var lab := l as Label3D
		var vh := 2.0 * absf(lab.global_position.z) * tan(deg_to_rad(cam0.fov) * 0.5)
		var vs := cam0.get_viewport().get_visible_rect().size
		var vw := vh * vs.x / vs.y
		var tw := 0.0
		var th := 0.0
		var sz := lab.font.get_multiline_string_size(lab.text, HORIZONTAL_ALIGNMENT_CENTER, -1, lab.font_size)
		tw = sz.x * lab.pixel_size * lab.scale.x
		th = sz.y * lab.pixel_size * lab.scale.y
		if th > vh * 0.14 or tw > vw * 0.85:
			fails.append("pop-up \"%s\" stays small next to a camera (%.0f%% of the view high, %.0f%% wide)" % [lab.text, 100.0 * th / vh, 100.0 * tw / vw])
		if absf(lab.global_position.x) + tw * 0.5 > vw * 0.5 + 0.01:
			fails.append("pop-up \"%s\" stays inside the view (x %.2f, half width %.2f, view half %.2f)" % [lab.text, lab.global_position.x, tw * 0.5, vw * 0.5])
	print("LAYOUT CHECK: PASS" if fails.is_empty() else "LAYOUT CHECK: FAIL\n  " + "\n  ".join(fails))
	quit(0 if fails.is_empty() else 1)
