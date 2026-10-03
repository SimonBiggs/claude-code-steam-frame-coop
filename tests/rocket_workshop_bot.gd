extends Node
## Headless bot for Rocket Workshop.
## Pilot (local / host): reads the answers from the host's puzzle state and works the desk with a fake
## hand (operator.bot_hand): taps buttons, drags plugs, the dial and the launch lever. The first module
## gets one deliberate mistake so the "burp" path runs too.
## Crew (local player 2, or the TV machine's players): carry fuel canisters to the hatch, hold ACTION
## at leaky pipes, otherwise stroll to the active blueprint boards. On the TV machine it also wakes P3.
## Local run: after two launches (or 45 s) it runs the clock out, checks the end screen and presses Enter.

const P := preload("res://games/rocket_workshop/puzzles.gd")

var main
var t := 0.0
var next_report := 0.0
var steps: Array = []  # {pos: Vector3 (desk-local), grip: bool, dur: float}
var step_t := 0.0
var plan_wait := 0.0
var did_wrong := false
var hand := Vector3(0, 0, 0.15)
var grip := false
var forced_over := false
var over_t := 0.0


func _ready() -> void:
	if Engine.has_meta("rw_bot_restarts"):
		print("Bot: game restarted")
		var up := InputEventKey.new()
		up.physical_keycode = KEY_ENTER
		up.pressed = false
		Input.parse_input_event(up)
	main = load("res://games/rocket_workshop/main.tscn").instantiate()
	add_child(main)


func _physics_process(delta: float) -> void:
	t += delta
	if not is_instance_valid(main) or not main.is_inside_tree() or not main.ready_to_play:
		return
	if main.net.mode != "client":
		_pilot(delta)
	for p in main.players:
		if p.index > 0 and not p.remote:
			_crew(p)
	_check_over(delta)
	if t >= next_report:
		next_report += 5.0
		_report()


func _report() -> void:
	var ms: Array[String] = []
	for m in main.modules:
		ms.append("%s%s" % [m.type, "+" if m.done else "-"])
	var ps: Array[String] = []
	for p in main.players:
		if p.index > 0:
			ps.append("P%d%s(%.0f,%.0f)" % [p.index + 1, "" if p.active else "idle", p.global_position.x, p.global_position.z])
	print("t=%.0f mode=%s phase=%s rocket=%d launched=%d time=%.0f burps=%d modules=[%s] %s" % [t, main.net.mode, main.phase,
		main.rocket_n, main.launched, main.time_left, main.mistakes, " ".join(ms), " ".join(ps)])


# --- Pilot -------------------------------------------------------------------

func _pilot(delta: float) -> void:
	var op = main.players[0]
	if steps.is_empty():
		plan_wait -= delta
		if plan_wait <= 0.0:
			plan_wait = 0.3
			_plan()
	if not steps.is_empty():
		var s: Dictionary = steps[0]
		grip = s.grip
		hand = hand.move_toward(s.pos, 1.5 * delta)
		step_t += delta
		if step_t >= float(s.dur) and hand.distance_to(s.pos) < 0.002:
			steps.pop_front()
			step_t = 0.0
	op.bot_hand = {"pos": main.panel.to_world(hand), "grip": grip}


func _at(key: String) -> Vector3:
	return main.panel.control_local(key)


func _tap(key: String) -> void:
	var p := _at(key)
	steps.append({"pos": Vector3(p.x, p.y, 0.12), "grip": false, "dur": 0.1})
	steps.append({"pos": p, "grip": false, "dur": 0.12})
	steps.append({"pos": Vector3(p.x, p.y, 0.12), "grip": false, "dur": 0.08})


func _drag(key: String, to: Vector3) -> void:
	var p := _at(key)
	steps.append({"pos": Vector3(p.x, p.y, 0.12), "grip": false, "dur": 0.1})
	steps.append({"pos": p, "grip": false, "dur": 0.1})
	steps.append({"pos": p, "grip": true, "dur": 0.15})
	steps.append({"pos": to, "grip": true, "dur": 0.2})
	steps.append({"pos": to, "grip": false, "dur": 0.15})
	steps.append({"pos": Vector3(to.x, to.y, 0.12), "grip": false, "dur": 0.1})


func _plan() -> void:
	if main.phase == "ready":
		print("Bot: pulling the launch lever")
		_drag("lever", _at("lever_pulled"))
		return
	if main.phase != "work":
		return
	for m in main.modules:
		if m.done or P.is_job(m.type):
			continue
		var wrong := not did_wrong
		did_wrong = true
		if wrong:
			print("Bot: making a deliberate mistake on %s" % m.type)
		match m.type:
			"fuel":
				var answer: Array = m.answer
				var pressed: Array = m.pressed
				if wrong and pressed.is_empty():
					var c := 0
					while answer.count(c) == answer.size():
						c += 1
					for k in answer.size():
						_tap("fuel%d" % c)
					return
				var need := answer.duplicate()
				for c in pressed:
					need.erase(c)
				for c in need:
					_tap("fuel%d" % int(c))
			"wires":
				var order: Array = m.order
				var placed: Array = m.placed
				if wrong:
					_drag("plug%d" % int(order[0]), _at("sock1"))
					return
				for i in order.size():
					if int(placed[i]) < 0:
						_drag("plug%d" % int(order[i]), _at("sock%d" % i))
			"symbols":
				var layout: Array = m.layout
				var order: Array = m.order
				var step: int = m.step
				if wrong:
					for slot in 4:
						if int(layout[slot]) != int(order[step]):
							_tap("shape%d" % slot)
							return
				for k in range(step, order.size()):
					_tap("shape%d" % layout.find(order[k]))
			"gauge":
				if wrong:
					_tap("set")
					return
				_drag("dial", _at("dial%d" % int(m.answer)))
				_tap("set")
			"switches":
				var state: Array = m.state
				var answer: Array = m.answer
				if wrong and state != answer:
					_tap("check")
					return
				for i in state.size():
					if bool(state[i]) != bool(answer[i]):
						_tap("sw%d" % i)
				_tap("check")
		return


# --- Crew --------------------------------------------------------------------

func _crew(p) -> void:
	if not p.active:
		p.bot_action = main.net.mode == "client" and t > 4.0 and fmod(t, 2.0) < 0.3
		return
	p.bot_action = false
	var target := Vector3.INF
	var can: Dictionary = main.module("canister")
	var pipe: Dictionary = main.module("pipe")
	var working: bool = main.phase == "work" or main.phase == "ready"
	if working and not can.is_empty() and not can.done and int(can.carrier) in [-1, p.index]:
		target = main.HATCH_POS if int(can.carrier) == p.index else (can.pos as Vector3)
	elif working and not pipe.is_empty() and not pipe.done:
		var spot: Vector3 = P.PIPE_SPOTS[int(pipe.spot)]
		var inward := Vector3(-signf(spot.x), 0, 0) if absf(spot.z) < 7.0 else Vector3(0, 0, -1)
		target = Vector3(spot.x, 0, spot.z) + inward * 1.2
		if Vector2(p.global_position.x - target.x, p.global_position.z - target.z).length() < 0.6:
			p.bot_action = true
	else:
		for m in main.modules:
			if not m.done and main.manual.boards.has(m.type):
				var root: Node3D = main.manual.boards[m.type].root
				var front: Vector3 = root.global_position + root.global_basis.z * 2.5
				target = Vector3(front.x, 0, front.z)
				break
	if target == Vector3.INF:
		p.bot_move = Vector3.ZERO
		return
	var pos: Vector3 = p.global_position
	# Go round the walls either side of the big launch doorway.
	if (pos.z > -6.15) != (target.z > -6.15) and absf(pos.x) > 3.0:
		target = Vector3(clampf(pos.x, -2.5, 2.5), 0, -6.15)
	var to := target - pos
	to.y = 0.0
	if to.length() > 0.4:
		p.bot_move = to.normalized()
		p.yaw = atan2(-to.x, -to.z)
	else:
		p.bot_move = Vector3.ZERO


# --- End screen and restart (local runs) ---------------------------------------

func _check_over(delta: float) -> void:
	if main.net.mode != "local":
		return
	if not forced_over and not Engine.has_meta("rw_bot_restarts") and (main.phase == "work" or main.phase == "ready") \
			and (main.launched >= 2 or t > 45.0):
		forced_over = true
		print("Bot: letting the clock run out to test the end screen")
		main.time_left = 0.3
	if not main.game_over:
		over_t = 0.0
		return
	over_t += delta
	var restarts: int = Engine.get_meta("rw_bot_restarts", 0)
	if restarts >= 1 or over_t < 2.5:
		return
	Engine.set_meta("rw_bot_restarts", restarts + 1)
	print("Bot: end screen says: %s" % main.center_label.text.replace("\n", " | "))
	print("Bot: pressing Enter to play again")
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ENTER
	e.pressed = true
	Input.parse_input_event(e)
