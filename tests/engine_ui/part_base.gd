extends Node
## Base for the engine test parts (tests/engine_ui/*_test.gd). The runner (tests/engine_ui_test.gd)
## adds each part as a child and awaits `run()`. Parts call check() and frames(); a failed check prints
## "FAIL" and counts towards the runner's exit code.

var failures := 0
var checks := 0
var tag := "part"


## Override: the part's test body (may await).
func run() -> void:
	pass


## Record one assertion.
func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("[%s] ok: %s" % [tag, what])
	else:
		failures += 1
		print("[%s] FAIL: %s" % [tag, what])


## Wait n process frames.
func frames(n: int = 1) -> void:
	for i in n:
		await get_tree().process_frame


## Wait roughly `seconds` of game time (fixed-fps runs advance 1/60 s per frame).
func wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
