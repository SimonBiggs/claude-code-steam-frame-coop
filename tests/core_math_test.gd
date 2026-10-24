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
	print("CORE MATH: %s" % ("PASS" if fails.is_empty() else "FAIL " + "; ".join(fails)))
	quit(1 if not fails.is_empty() else 0)
