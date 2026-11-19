extends SceneTree
## PICK PULL: VR hands pick orbs the easy ways too (core/pick_flow.gd, shared by every game's picks). 2026-11-19, a
## guest in the Steam Frame couldn't pick GENTLE / BRAVE / HARD in Rhythm Band: the hand rested in an orb when it popped
## up (never a pick until it leaves) and they kept pressing buttons. Checks, on the shared flow with a fake game:
##  - a hand resting in an orb: no pick by itself, the line under the row says "pull the trigger", a pull picks it;
##  - a pull held since before the orbs came up never picks (let go first);
##  - pointing at an orb and pulling picks it; a burst of presses doesn't (press_ok);
##  - reaching in and staying still still picks (dwell), with a ring filling up meanwhile;
##  - no VR hands (flat players): no how-to line, the trigger does nothing here.
##   godot-test --headless --path . -s res://tests/pick_pull_test.gd     Prints PICK PULL: PASS / FAIL.

const PickFlow := preload("res://core/pick_flow.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const UiKit := preload("res://core/ui_kit.gd")

var fails := 0
const DT := 1.0 / 60.0


class FakeNet extends RefCounted:
	var mode := "local"

	func event(_k: String, _a: Variant = null) -> void:
		pass

	func state_set(_k: String, _v: Variant) -> void:
		pass

	func state_get(_k: String, d: Variant = null) -> Variant:
		return d


class FakeMain extends Node3D:
	var net := FakeNet.new()


class Flow extends "res://core/pick_flow.gd":
	var hands := {}  # id -> [point, slot, "hand"]
	var ctrl: Node3D

	func takers() -> Dictionary:
		return hands

	func pull_controllers() -> Array:
		return [ctrl]

	func pull_down(c: Node3D) -> bool:
		return float(c.get_meta("trigger", 0.0)) > 0.6


var main: FakeMain
var flow: Flow


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("PICK PULL: FAIL ", what)


func _initialize() -> void:
	Engine.set_meta("save_test_mode", true)
	_go.call_deferred()


func _go() -> void:
	main = FakeMain.new()
	root.add_child(main)
	flow = Flow.new()
	flow.main = main
	main.add_child(flow)
	flow.ctrl = Node3D.new()
	main.add_child(flow.ctrl)
	_run()
	print("PICK PULL: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails else 0)


func _begin() -> void:
	flow.start("mode", ["gentle", "brave", "hard"], func(_s: String, _o: Variant, _sl: int) -> void: pass)
	flow.orbs.show_orbs("mode", PickOrbs.MODES, Vector3(0, 0, -1.0), 0.5, 1.2, {"scale": 0.35})


func _ticks(seconds: float) -> void:
	for i in int(seconds / DT):
		flow.tick(DT)
		if flow.chosen >= 0:
			return


func _orb(i: int) -> Vector3:
	return flow.orb_position(i)


## The controller's -Z towards `at`.
func _aim(at: Vector3) -> void:
	flow.ctrl.global_basis = UiKit.aim((at - flow.ctrl.global_position).normalized())


func _pull() -> void:
	flow.ctrl.set_meta("trigger", 1.0)
	_ticks(DT * 2)
	flow.ctrl.set_meta("trigger", 0.0)


func _run() -> void:
	# 1. A hand resting in BRAVE (orb 1) as the orbs pop up, the trigger held from play.
	flow.ctrl.set_meta("trigger", 1.0)
	_begin()
	flow.hands = {"r": [_orb(1), 0, "hand"]}
	flow.ctrl.global_position = _orb(1) + Vector3(0, -0.05, 0.1)
	_ticks(2.0)
	_expect(flow.chosen < 0, "1. a hand resting in an orb (and a held pull) picked by itself: %d" % flow.chosen)
	_expect(flow.orbs.hint_text() == PickFlow.VR_HINT_INSIDE, "1. the line under the row says to pull the trigger (got '%s')" % flow.orbs.hint_text())
	flow.ctrl.set_meta("trigger", 0.0)  # let go of the held pull
	_ticks(DT * 3)
	_expect(flow.chosen < 0, "1. letting go picks nothing")
	_pull()
	_expect(flow.chosen == 1, "1. a pull with the hand resting in BRAVE picks BRAVE (chosen %d)" % flow.chosen)
	_ticks(2.0)  # finish
	_expect(flow.orbs.hint_text() == "", "1. the line goes once picked")

	# 2. Pointing at HARD (orb 2) from 40 cm away, hand outside every orb, then pulling.
	_begin()
	flow.hands = {"r": [Vector3(0.6, 0.6, 0.0), 0, "hand"]}
	_ticks(1.0)
	_expect(flow.orbs.hint_text() == PickFlow.VR_HINT, "2. the line says reach in or point and pull (got '%s')" % flow.orbs.hint_text())
	var from := _orb(2) + Vector3(0.0, -0.1, 0.4)
	flow.ctrl.global_position = from
	_aim(_orb(2))
	flow.note_press(0)  # 2a. a burst: a press just before
	_pull()
	_expect(flow.chosen < 0, "2a. a pull right after another press (a burst) doesn't pick")
	OS.delay_msec(int(flow.press_gap * 1000.0) + 100)  # (press_ok counts real time)
	_ticks(0.2)
	_pull()
	_expect(flow.chosen == 2, "2. point at HARD + pull picks HARD (chosen %d)" % flow.chosen)
	_ticks(2.0)

	# 3. Reaching into GENTLE (orb 0) and staying: the ring fills, then it picks.
	_begin()
	flow.hands = {"r": [Vector3(0.6, 0.6, 0.0), 0, "hand"]}
	flow.ctrl.global_position = Vector3(0.6, 0.6, 0.3)
	_aim(Vector3(0.6, 0.6, 1.0))  # pointing away from the row
	_ticks(1.0)
	flow.hands = {"r": [_orb(0), 0, "hand"]}
	_ticks(flow.hand_dwell * 0.5)
	var f := flow.orbs.fill_of(0)
	_expect(flow.chosen < 0 and f > 0.1 and f < 0.95, "3. half way through the dwell the ring is part full (%.2f, chosen %d)" % [f, flow.chosen])
	_ticks(flow.hand_dwell)
	_expect(flow.chosen == 0, "3. reaching in and staying picks GENTLE (chosen %d)" % flow.chosen)
	_ticks(2.0)

	# 4. No VR hands (a flat player walking): no line, the trigger does nothing.
	_begin()
	flow.hands = {"p": [Vector3(5, 0, 5), 0, "foot"]}
	_ticks(1.0)
	_expect(flow.orbs.hint_text() == "", "4. flat players: no VR how-to line (got '%s')" % flow.orbs.hint_text())
	flow.ctrl.global_position = _orb(1) + Vector3(0, 0, 0.4)
	_aim(_orb(1))
	_pull()
	_expect(flow.chosen < 0, "4. no VR hands: a pull doesn't pick")
