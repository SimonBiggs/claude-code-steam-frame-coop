extends SceneTree
## Regression checks for core helpers that guard against known bug patterns (run headless:
## godot --headless --path . -s res://tests/core_math_test.gd). Prints CORE MATH: PASS / FAIL lines.
const UiKit := preload("res://core/ui_kit.gd")

func _initialize() -> void:
	var fails: Array[String] = []
	# UiKit.face: no roll for ordinary directions (its y axis stays up), never NaN for vertical ones.
	for d in [Vector3(0, 0, -1), Vector3(1, 0.07, -3), Vector3(-2, -0.5, 1), Vector3(0.3, 0.2, 5)]:
		var b := UiKit.face(d)
		if b.y.dot(Vector3.UP) < 0.8:
			fails.append("face(%s) rolled: y=%s" % [d, b.y])
		if (-b.z).dot(d.normalized()) < 0.99:
			fails.append("face(%s) doesn't look along dir" % d)
	for d in [Vector3(0, -1, 0), Vector3(0, 1, 0.0001), Vector3(0.001, -1, 0)]:
		var b := UiKit.face(d)
		if not b.is_finite() or absf(b.determinant()) < 0.5:
			fails.append("face(%s) degenerate" % d)
	# UiKit.aim / aim_from / look: exactly Basis.looking_at for ordinary directions, finite for vertical ones.
	for d in [Vector3(0, 0, -1), Vector3(1, 0.07, -3), Vector3(-2, -0.5, 1), Vector3(0.3, -5.0, 0.2), Vector3(0.01, 1, 0)]:
		for front in [false, true]:
			if not UiKit.aim(d, Vector3.UP, front).is_equal_approx(Basis.looking_at(d, Vector3.UP, front)):
				fails.append("aim(%s, front=%s) differs from looking_at" % [d, front])
	for d in [Vector3(0, -1, 0), Vector3(0, 3, 0), Vector3(0, 1, 0.000001), Vector3.ZERO]:
		var b := UiKit.aim(d)
		var xf := UiKit.aim_from(Vector3(1, 2, 3), Vector3(1, 2, 3) + d)
		if not b.is_finite() or absf(b.determinant()) < 0.5 or not xf.is_finite():
			fails.append("aim(%s) degenerate" % d)
		if d != Vector3.ZERO and (-b.z).dot(d.normalized()) < 0.99:
			fails.append("aim(%s) doesn't look along dir" % d)
	var n3 := Node3D.new()
	n3.scale = Vector3(2, 2, 2)
	for target in [Vector3(0, -4, 0), Vector3(3, 1, -2), Vector3.ZERO]:
		UiKit.look(n3, target)
		if not n3.transform.is_finite() or not n3.scale.is_equal_approx(Vector3(2, 2, 2)):
			fails.append("look(-> %s) broke the node: %s" % [target, n3.transform])
	n3.free()
	# Raw looking_at / look_at go NaN or error when the direction is vertical (VR wrist buttons vanished once):
	# every aim goes through UiKit.aim / aim_from / look / face. Comments don't count.
	var raw_look := RegEx.create_from_string("(?m)^[^#\\n]*(\\blooking_at\\(|(^|[^A-Za-z0-9_])look_at\\()")
	for dir in ["res://core", "res://arcade", "res://games", "res://tests"]:
		for path in _gd_files(dir):
			if path in ["res://core/ui_kit.gd", "res://tests/core_math_test.gd"]:
				continue
			for m in raw_look.search_all(FileAccess.get_file_as_string(path)):
				fails.append("%s: %s (raw looking_at/look_at: use UiKit.aim / aim_from / look)" % [path, m.get_string().strip_edges()])
	# World-space UI order: panels below text both on the TV (labels at VR_PRIO_TEXT) and in VR, where
	# core/vr_text_guard.gd resets every Label3D to priority 0 (panels at 20 hid their own text).
	if not (UiKit.VR_PRIO_PANEL < UiKit.VR_PRIO_HILITE and UiKit.VR_PRIO_HILITE < 0 and UiKit.VR_PRIO_TEXT > 0):
		fails.append("VR UI priorities: panel %d, hilite %d must be < 0 (vr_text_guard puts labels at 0)" % [UiKit.VR_PRIO_PANEL, UiKit.VR_PRIO_HILITE])
	for depth in [false, true]:
		var pm := UiKit.panel3d(Vector2.ONE, UiKit.BG, Color.WHITE, 0.05, depth)
		var m: StandardMaterial3D = pm.material_override
		pm.free()
		if m.render_priority >= 0:
			fails.append("panel3d(depth_test=%s) priority %d would draw over VR text" % [depth, m.render_priority])
	# Storing null with set_meta ERASES the meta (Godot 4), so a later get_meta(key) errors every frame (the
	# "follow_udp" spam in core/net.gd): store a real value or remove_meta() instead.
	var null_meta := RegEx.create_from_string("set_meta\\([^,()]+,\\s*null\\s*\\)|set_meta\\(.*else null\\)")
	# get_meta(key, null) is the SAME as get_meta(key) in Godot 4 (null = "no default"): it errors when the key
	# is missing (arcade.gd "listen" / net.gd "follow_udp" spammed every Deck log every frame, 2026-10-24).
	# Use `get_meta(key) if has_meta(key) else null`.
	var null_default := RegEx.create_from_string("get_meta\\([^,()]+,\\s*null\\s*\\)")
	for dir in ["res://core", "res://arcade", "res://games"]:
		for path in _gd_files(dir):
			var src := FileAccess.get_file_as_string(path)
			for m in null_meta.search_all(src):
				fails.append("%s: %s (set_meta with null erases the meta)" % [path, m.get_string()])
			for m in null_default.search_all(src):
				fails.append("%s: %s (a null default is no default: errors when missing)" % [path, m.get_string()])
	print("CORE MATH: %s" % ("PASS" if fails.is_empty() else "FAIL " + "; ".join(fails)))
	quit(1 if not fails.is_empty() else 0)


static func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out
