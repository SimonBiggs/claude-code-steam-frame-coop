extends SceneTree
## ARCADE FRAME TIME: the arcade menu must stay cheap every frame, flat and in VR. 2026-11-19 the hub cost 60-75 ms a
## frame (7-11 fps in the Steam Frame, "very glitchy"): the What's New / Trophy Hall boards' ~190 "still" story
## pictures all redrew every frame (re-triangulating their polygons), because their set_process(false) ran before
## add_child and Godot switches _process back on at NOTIFICATION_READY. Checks, on every tab and with the VR walls:
##  - at most MAX_PROCESSING nodes under the arcade run _process (a still picture that animates shows up here first);
##  - the best of several 30-frame windows averages under FLAT_MS / VR_MS of process time per frame (Godot's own
##    TIME_PROCESS: every _process; headless draws nothing and paces frames itself, so wall time can't see the cost and
##    the processing count above is what catches redrawing pictures).
##   godot-test --headless --path . -s res://tests/arcade_frame_time_test.gd     Prints ARCADE FRAME TIME: PASS / FAIL.

const MAX_PROCESSING := 8
const FLAT_MS := 8.0  # VR runs at 90 Hz = 11.1 ms for everything, rendering included
const VR_MS := 8.0  # (headless base ~2.3 ms: services + tree; the arcade ~1 ms)
const WINDOWS := 6
const WINDOW_FRAMES := 30

var fails := 0
var frames := 0
var arcade: Node
var step := "load"
var tab := 0
var wait := 0
var win_sum := 0.0
var win_frames := 0
var best_ms := INF
var windows := 0
var report: Array[String] = []


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("ARCADE FRAME TIME: FAIL ", what)


func _initialize() -> void:
	Engine.set_meta("save_test_mode", true)  # never the family's saves
	OS.set_environment("DUO_SOLO", "1")
	if not OS.has_environment("DUO_PORT"):
		OS.set_environment("DUO_PORT", str(20000 + randi() % 10000))
	arcade = load("res://arcade.tscn").instantiate()
	root.add_child.call_deferred(arcade)


## Nodes under the arcade that run _process every frame.
func _processing() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [arcade]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != arcade and n.is_processing():
			out.append("%s (%s)" % [arcade.get_path_to(n), n.get_class()])
		stack.append_array(n.get_children(true))
	return out


func _check_processing(where: String) -> void:
	var p := _processing()
	_expect(p.size() <= MAX_PROCESSING, "%s: %d nodes run _process every frame (max %d; a still picture from StoryCard.picture(..., false)?): %s" % [where, p.size(), MAX_PROCESSING, ", ".join(p.slice(0, 6))])


## Times WINDOWS windows of WINDOW_FRAMES frames; true when done (best window kept: a busy machine slows some).
func _measure() -> bool:
	win_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	win_frames += 1
	if win_frames < WINDOW_FRAMES:
		return false
	best_ms = minf(best_ms, win_sum / WINDOW_FRAMES)
	win_frames = 0
	win_sum = 0.0
	windows += 1
	return windows >= WINDOWS


func _process(_delta: float) -> bool:
	frames += 1
	if frames > 3000:
		_expect(false, "timed out in step %s" % step)
		return _finish()
	match step:
		"load":
			if arcade.is_inside_tree() and bool(arcade.get("hall_ready")) and arcade.get("grid") != null:
				step = "tabs"
				wait = 5
		"tabs":  # every tab once: none may leave pictures animating
			wait -= 1
			if wait > 0:
				return false
			if tab > 0:
				_check_processing("tab %d" % (tab - 1))
			var n: int = arcade.tabs().size()
			if tab >= n:
				step = "flat"
				for want in ["new", "hall"]:  # time the heaviest boards: What's New, then the Trophy Hall (the default)
					var k: int = arcade._tab_of(want)
					if k >= 0:
						arcade._show_category(k, true)
				return false
			arcade._show_category(tab, true)
			tab += 1
			wait = 4
		"flat":
			if _measure():
				report.append("flat %.2f ms" % best_ms)
				_expect(best_ms < FLAT_MS, "flat menu: %.1f ms a frame (budget %.1f)" % [best_ms, FLAT_MS])
				arcade._build_vr_view()
				arcade.vr_cam.position = Vector3(0, 1.6, 0)
				best_ms = INF
				windows = 0
				step = "vr"
				wait = 20
		"vr":
			wait -= 1
			if wait > 0:
				return false
			if _measure():
				report.append("VR %.2f ms" % best_ms)
				_expect(best_ms < VR_MS, "VR lobby: %.1f ms a frame (budget %.1f)" % [best_ms, VR_MS])
				_check_processing("VR lobby")
				return _finish()
	return false


func _finish() -> bool:
	print("ARCADE FRAME TIME: %s (%s)" % ["PASS" if fails == 0 else "FAIL", ", ".join(report)])
	quit(1 if fails else 0)
	return true
