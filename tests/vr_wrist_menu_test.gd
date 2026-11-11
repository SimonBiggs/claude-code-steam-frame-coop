extends Node
## core/net.gd's VR wrist MENU / RESUME / ARCADE buttons with the fake VR rig (core/vr_rig.gd).
## 2026-11-11: a player HOLDING the trigger (shooting, popping, reeling) whose right-hand ray swept across the
## left-wrist MENU paused the game, and the same hold then went back to the arcade 1.5 s later.
## Run: godot-test --headless --path . --fixed-fps 60 res://tests/vr_wrist_menu_test.tscn
## Prints "VR WRIST MENU TEST: PASS" / "FAIL"; exit code = number of failures.
const VrRig := preload("res://core/vr_rig.gd")
const UiKit := preload("res://core/ui_kit.gd")

var fails: Array[String] = []
var main: TestMain
var net: TestNet
var rig: VrRig


## Stands in for a game's main.gd: toggle_vr_pause like the 17 games that have one.
class TestMain extends Node3D:
	var net: Node
	var vr_rig: Node
	var toggles := 0

	func toggle_vr_pause() -> void:
		toggles += 1
		get_tree().paused = not get_tree().paused


## core/net.gd, but going to the arcade is only counted (the test keeps running).
class TestNet extends "res://core/net.gd":
	var left := 0

	func go_to_arcade() -> void:
		if has_meta("leaving"):
			return
		set_meta("leaving", true)
		left += 1

	## Back from the "arcade" (a test step): the next leave counts again.
	func come_back() -> void:
		remove_meta("leaving")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = TestMain.new()
	main.name = "Main"
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	rig = VrRig.new()
	rig.fit_mode = "none"
	rig.locomotion = false
	rig.make_mirror = false
	main.vr_rig = rig
	main.add_child(rig)
	net = TestNet.new()
	net.name = "Net"
	net.main = main
	main.net = net
	main.add_child(net)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


## Hands in a relaxed pose, the right hand pointing straight ahead (away from the wrist).
func _rest() -> void:
	rig.camera.position = Vector3(0, 1.6, 0)
	rig.camera.basis = Basis()
	rig.hand_l.position = Vector3(-0.25, 1.1, -0.3)
	rig.hand_l.basis = Basis()
	rig.hand_r.position = Vector3(0.25, 1.1, -0.3)
	rig.hand_r.basis = Basis()


## Right hand `dist` metres from `target`, its ray passing `side` metres beside it.
func _point(target: Vector3, dist: float = 0.36, side: float = 0.0) -> void:
	var from := target + Vector3(0.3, 0.05, -0.2).normalized() * dist
	var hr: Node3D = rig.hand_r
	hr.global_position = from
	var aim := target + Vector3(0.0, 0.0, side) - from
	hr.global_basis = UiKit.aim(aim.normalized(), Vector3.UP)


func _frames(n: int, each: Callable = Callable()) -> void:
	for i in n:
		if each.is_valid():
			each.call(i)
		await get_tree().process_frame


func _menu_pos() -> Vector3:
	return rig.wrist_menu_position()


func _arcade_pos() -> Vector3:
	var a := rig.hand_l.get_node_or_null("WristArcade") as Node3D
	return a.global_position if a != null else _menu_pos()


func _run() -> void:
	_rest()
	rig.fake_trigger = 0.0
	await _frames(20)
	_check(rig.hand_l.get_node_or_null("WristMenu") != null, "the wrist MENU button is on the left glove")
	_check(_menu_pos().distance_to((rig.hand_l.get_node("WristMenu") as Node3D).global_position) < 0.001,
		"VrRig.wrist_menu_position() is where core/net.gd puts the MENU button")

	# 1. A trigger held for play (here from straight ahead), then the ray sweeps across MENU and rests on it.
	rig.fake_trigger = 1.0
	await _frames(10, func(_i: int) -> void: _rest())
	await _frames(40, func(i: int) -> void: _point(_menu_pos(), 0.36, lerpf(-0.3, 0.3, i / 39.0)))
	await _frames(40, func(_i: int) -> void: _point(_menu_pos()))
	_check(not get_tree().paused and main.toggles == 0, "1. a HELD trigger sweeping across MENU (and resting on it) doesn't pause")
	rig.fake_trigger = 0.0
	await _frames(5, func(_i: int) -> void: _rest())

	# 1b. Pointing counts only within arm's reach: a fresh pull at MENU from 1.5 m away does nothing.
	await _frames(5, func(_i: int) -> void: _point(_menu_pos(), 1.5))
	rig.fake_trigger = 1.0
	await _frames(10, func(_i: int) -> void: _point(_menu_pos(), 1.5))
	_check(not get_tree().paused, "1b. a pull pointing at MENU from 1.5 m away doesn't pause")
	rig.fake_trigger = 0.0
	await _frames(5, func(_i: int) -> void: _rest())

	# 2. A fresh pull that starts on MENU pauses.
	await _frames(5, func(_i: int) -> void: _point(_menu_pos()))
	rig.fake_trigger = 1.0
	await _frames(5, func(_i: int) -> void: _point(_menu_pos()))
	_check(get_tree().paused and main.toggles == 1, "2. a fresh pull on MENU pauses")

	# 3. Holding that same pull for 3 s (still on the button, then away) never leaves; letting go doesn't resume.
	await _frames(90, func(_i: int) -> void: _point(_menu_pos()))
	await _frames(90, func(_i: int) -> void: _rest())
	_check(net.left == 0, "3. the pull that paused, held 3 s, doesn't go to the arcade")
	rig.fake_trigger = 0.0
	await _frames(10, func(_i: int) -> void: _rest())
	_check(get_tree().paused, "3b. letting go of the pull that paused doesn't resume")

	# 4. A NEW pull while paused, held 1.5 s, leaves (not before).
	rig.fake_trigger = 1.0
	await _frames(60, func(_i: int) -> void: _rest())
	_check(net.left == 0, "4a. a new pull held 1 s hasn't left yet")
	await _frames(40, func(_i: int) -> void: _rest())
	_check(net.left == 1, "4. a new pull held 1.5 s while paused goes to the arcade")
	rig.fake_trigger = 0.0
	await _frames(5, func(_i: int) -> void: _rest())
	net.come_back()

	# 6. Tap RESUME (a quick fresh pull on the button) resumes.
	await _frames(5, func(_i: int) -> void: _point(_menu_pos(), 0.36, -0.03))
	rig.fake_trigger = 1.0
	await _frames(6, func(_i: int) -> void: _point(_menu_pos(), 0.36, -0.03))
	rig.fake_trigger = 0.0
	await _frames(5, func(_i: int) -> void: _point(_menu_pos(), 0.36, -0.03))
	_check(not get_tree().paused, "6. a quick pull on RESUME resumes")
	await _frames(5, func(_i: int) -> void: _rest())

	# 5. Touching MENU (held 0.35 s) pauses; a brush (0.2 s) doesn't.
	var t0 := main.toggles
	await _frames(12, func(_i: int) -> void: rig.hand_r.global_position = _menu_pos())
	_check(not get_tree().paused, "5a. brushing MENU for 0.2 s doesn't pause")
	await _frames(18, func(_i: int) -> void: rig.hand_r.global_position = _menu_pos())
	_check(get_tree().paused and main.toggles == t0 + 1, "5. touching MENU for 0.35 s pauses")
	await _frames(10, func(_i: int) -> void: _rest())

	# 7. Point at ARCADE and pull (a fresh pull) leaves at once.
	var left0 := net.left
	await _frames(5, func(_i: int) -> void: _point(_arcade_pos()))
	rig.fake_trigger = 1.0
	await _frames(3, func(_i: int) -> void: _point(_arcade_pos()))
	_check(net.left == left0 + 1, "7. point at ARCADE and pull goes to the arcade")
	rig.fake_trigger = 0.0
	await _frames(5, func(_i: int) -> void: _rest())
	net.come_back()

	# 8. A held trigger swept onto ARCADE while paused (the pull began before the pause) doesn't leave.
	get_tree().paused = false
	await _frames(5, func(_i: int) -> void: _rest())
	rig.fake_trigger = 1.0
	await _frames(5, func(_i: int) -> void: _rest())
	get_tree().paused = true  # the menu / B-Y button paused under a held trigger
	await _frames(10, func(_i: int) -> void: _rest())
	await _frames(30, func(_i: int) -> void: _point(_arcade_pos()))
	await _frames(90, func(_i: int) -> void: _rest())
	_check(net.left == left0 + 1, "8. a trigger held from before the pause, swept onto ARCADE and held, doesn't leave")
	rig.fake_trigger = 0.0
	get_tree().paused = false
	await _frames(3)

	print("VR WRIST MENU TEST: %s (%d checks failed)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	get_tree().quit(fails.size())
