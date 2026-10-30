extends SceneTree
## core/layout_check.gd catches what it should and nothing else (run headless:
## godot-test --headless --path . -s res://tests/layout_check_test.gd). Prints LAYOUT CHECK: PASS / FAIL.
const LayoutCheck := preload("res://core/layout_check.gd")


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
	print("LAYOUT CHECK: PASS" if fails.is_empty() else "LAYOUT CHECK: FAIL\n  " + "\n  ".join(fails))
	quit(0 if fails.is_empty() else 1)
