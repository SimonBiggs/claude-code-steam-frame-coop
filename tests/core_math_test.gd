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
	print("CORE MATH: %s" % ("PASS" if fails.is_empty() else "FAIL " + "; ".join(fails)))
	quit(1 if not fails.is_empty() else 0)
