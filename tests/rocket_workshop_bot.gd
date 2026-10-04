extends Node
## Headless bot for Rocket Workshop.
## Pilot (local / host): reads the answers from the host's puzzle state and works the desk with a fake
## hand (operator.bot_hand, world space): taps buttons, drags plugs, the dial, winds the crank on the
## right wing, says hello to the alien on the left wing and pulls the launch lever. The first module
## gets one deliberate mistake so the "burp" path runs too.
## Crew (local players, or the TV machine's players): carry fuel canisters and paint pots to the hatch,
## pick up loose bolts, chase the space cat into its basket, hold ACTION at leaky pipes, otherwise
## stroll to the active blueprint boards. BOT_PLAYERS=N: crew to have (local: up to 5; TV: up to 6).
## First session (local / host): the bot picks each rocket's modules so every type gets used, fires a
## comet and the random event picker, checks the launch cam reaches space, then (local) runs the clock
## out, checks the end screen and awards, and presses Enter. The second session is left natural.
## BOT_COUNT=1: just count what the pilot's camera draws a few seconds in, then quit.

const P := preload("res://games/rocket_workshop/puzzles.gd")
const PLAN := [
	["alien", "crank", "paint", "bolts"],
	["fuel", "wires", "symbols", "cat", "canister"],
	["gauge", "switches", "pipe", "paint"],
]

var main
var t := 0.0
var next_report := 0.0
var steps: Array = []  # {pos: Vector3 (world), grip: bool, dur: float}
var step_t := 0.0
var plan_wait := 0.0
var did_wrong := false
var wrong_types := {}  # first session: one deliberate mistake on each brand-new desk module too
var hand := Vector3(0, 1.4, 0)
var grip := false
var forced_over := false
var over_t := 0.0
var planned := -1
var events_done := {}
var cam_checked := false
var join_t := 0.0
var counted := false


func _ready() -> void:
	if Engine.has_meta("rw_bot_restarts"):
		print("Bot: game restarted")
		var up := InputEventKey.new()
		up.physical_keycode = KEY_ENTER
		up.pressed = false
		Input.parse_input_event(up)
	main = load("res://games/rocket_workshop/main.tscn").instantiate()
	add_child(main)


func _first_session() -> bool:
	return not Engine.has_meta("rw_bot_restarts") and main.net.mode != "client"


func _physics_process(delta: float) -> void:
	t += delta
	if not is_instance_valid(main) or not main.is_inside_tree() or not main.ready_to_play:
		return
	if OS.has_environment("BOT_COUNT"):
		_count()
		return
	_party(delta)
	if main.net.mode != "client":
		_force_plan()
		_pilot(delta)
		_events()
	for p in main.players:
		if p.index > 0 and not p.remote and not p.ghost:
			_crew(p)
	_check_cam()
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
		if p.index > 0 and p.active:
			ps.append("P%d(%.0f,%.0f)" % [p.index + 1, p.global_position.x, p.global_position.z])
	var snap := ""
	if main.net.mode == "host":
		snap = " snapshot=%dB" % var_to_bytes(main.make_snapshot()).size()
	print("t=%.0f mode=%s phase=%s rocket=%d launched=%d time=%.0f burps=%d stars=%d modules=[%s] %s%s" % [t, main.net.mode, main.phase,
		main.rocket_n, main.launched, main.time_left, main.mistakes, main.stars, " ".join(ms), " ".join(ps), snap])


## What the pilot's camera would draw (VR performance check).
func _count() -> void:
	if counted or t < 8.0:
		return
	counted = true
	var mask: int = 0xFFFFF & ~main.MANUAL_LAYER
	var c := {"mesh": 0, "multimesh": 0, "label": 0, "particles": 0, "lights": 0}
	_count_node(main, mask, c)
	print("COUNT ", c, " modules=", main.modules.size())
	get_tree().quit()


func _count_node(n: Node, mask: int, c: Dictionary) -> void:
	if n is VisualInstance3D and (n as Node3D).is_visible_in_tree() and ((n as VisualInstance3D).layers & mask) != 0:
		if n is MeshInstance3D:
			c.mesh += 1
		elif n is MultiMeshInstance3D:
			c.multimesh += 1
		elif n is Label3D:
			c.label += 1
		elif n is CPUParticles3D:
			c.particles += 1
		elif n is Light3D:
			c.lights += 1
	for ch in n.get_children():
		_count_node(ch, mask, c)


# --- Party: bring in BOT_PLAYERS crew --------------------------------------------

func _party(delta: float) -> void:
	if main.net.mode == "host":
		return
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else (1 if main.net.mode == "local" else 2)
	want = clampi(want, 1, main.players.size() - 1)
	join_t -= delta
	if join_t > 0.0 or t < 2.0:
		return
	var have := 0
	for p in main.players:
		if p.index > 0 and (p.active or p.has_meta("want_join")):
			have += 1
	if have < want:
		join_t = 1.5
		var p = main.debug_join()
		if p != null:
			print("Bot: P%d joins the crew" % (p.index + 1))


# --- First session: pick the modules so every type gets a turn --------------------

func _force_plan() -> void:
	if not _first_session() or main.phase != "intro" or main.rocket_n == planned:
		return
	planned = main.rocket_n
	if main.rocket_n > PLAN.size():
		return
	var types: Array = PLAN[main.rocket_n - 1]
	var mods: Array = []
	for type in types:
		mods.append(P.make(type, main.rocket_n + 2))
	main.modules = mods
	main.time_left = 240.0
	main.start_time = 240.0
	main.events_left = 0
	main.panel.shown_rocket = -1
	for b in main.manual.boards.values():
		b.key = ""
	if main.rocket_n > 1:
		main.phase_t = minf(main.phase_t, 1.0)  # short intros, so the first session reaches rocket 3
	print("Bot: rocket %d gets %s" % [main.rocket_n, ", ".join(types)])


## Rocket 2: a golden comet; rocket 3: let main's random event picker run twice.
func _events() -> void:
	if not _first_session() or main.phase != "work" or events_done.has(main.rocket_n):
		return
	events_done[main.rocket_n] = true
	if main.rocket_n == 2:
		main.time_left += 15.0
		main.spawn_comet()
		main.net.event("comet", [])
		print("Bot: comet!")
	elif main.rocket_n == 3:
		main.events_left = 2
		main.event_at = main.time_left + 1.0
		main._maybe_event()
		main.event_at = main.time_left + 1.0
		main._maybe_event()


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
	op.bot_hand = {"pos": hand, "grip": grip}


func _at(key: String, lift: float = 0.0) -> Vector3:
	return main.panel.control_world(key, lift)


func _tap(key: String) -> void:
	steps.append({"pos": _at(key, 0.12), "grip": false, "dur": 0.1})
	steps.append({"pos": _at(key), "grip": false, "dur": 0.12})
	steps.append({"pos": _at(key, 0.12), "grip": false, "dur": 0.08})


## Grab `key`, move through the given points (deck keys, e.g. "sock2" or "crank@3.1"), let go.
func _drag(key: String, path: Array) -> void:
	steps.append({"pos": _at(key, 0.12), "grip": false, "dur": 0.1})
	steps.append({"pos": _at(key), "grip": false, "dur": 0.1})
	steps.append({"pos": _at(key), "grip": true, "dur": 0.15})
	for k in path:
		steps.append({"pos": _at(k), "grip": true, "dur": 0.05})
	var last: String = path[path.size() - 1]
	steps.append({"pos": _at(last), "grip": true, "dur": 0.15})
	steps.append({"pos": _at(last), "grip": false, "dur": 0.15})
	steps.append({"pos": _at(last, 0.12), "grip": false, "dur": 0.1})


func _plan() -> void:
	if main.phase == "ready":
		print("Bot: pulling the launch lever")
		_drag("lever", ["lever_pulled"])
		return
	if main.phase != "work":
		return
	for m in main.modules:
		if m.done or P.is_job(m.type):
			continue
		var wrong := not did_wrong
		did_wrong = true
		if (m.type == "crank" or m.type == "alien") and not wrong_types.has(m.type) and _first_session():
			wrong_types[m.type] = true
			wrong = true
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
					_drag("plug%d" % int(order[0]), ["sock1"])
					return
				for i in order.size():
					if int(placed[i]) < 0:
						_drag("plug%d" % int(order[i]), ["sock%d" % i])
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
				_drag("dial", ["dial%d" % int(m.answer)])
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
			"alien":
				var answer := int(m.answer)
				if wrong:
					_tap("hello%d" % ((answer + 1) % 3))
					return
				print("Bot: the alien says %s" % P.HELLO_WORDS[answer])
				_tap("hello%d" % answer)
			"crank":
				var turns := int(m.answer)
				var acc: float = main.panel.crank_acc
				if wrong:
					turns += 1
				var path: Array = []
				var a := acc + 0.45
				while a < acc + turns * TAU + 0.4:
					path.append("crank@%.3f" % a)
					a += 0.45
				print("Bot: winding the crank %d times" % turns)
				_drag("crank", path)
				_tap("crank_go")
		return


# --- Crew --------------------------------------------------------------------

func _crew(p) -> void:
	if not p.active:
		p.bot_action = false
		return
	p.bot_action = false
	var target := Vector3.INF
	var working: bool = main.phase == "work" or main.phase == "ready"
	var can: Dictionary = main.module("canister")
	var pipe: Dictionary = main.module("pipe")
	var bolts: Dictionary = main.module("bolts")
	var paint: Dictionary = main.module("paint")
	var cat: Dictionary = main.module("cat")
	var mine := -1  # 0 canister, 1 paint, 2 cat being carried by p
	if working and not can.is_empty() and not can.done and int(can.carrier) == p.index:
		mine = 0
	elif working and not paint.is_empty() and not paint.done and int(paint.carrier) == p.index:
		mine = 1
	elif working and not cat.is_empty() and not cat.done and int(cat.carrier) == p.index:
		mine = 2
	var role: int = (p.index - 1) % 3
	if mine == 1 and int(paint.carry) != int(paint.answer):
		target = P.PAINT_SPOTS[int(paint.answer)]  # grabbed the wrong pot on the way past: swap it
	elif mine == 0 or mine == 1:
		target = main.HATCH_POS
	elif mine == 2:
		target = P.CAT_BASKET
	elif working and not cat.is_empty() and not cat.done and int(cat.carrier) < 0:
		target = cat.pos
	elif working and not paint.is_empty() and not paint.done and int(paint.carrier) < 0 and role != 1:
		target = P.PAINT_SPOTS[int(paint.answer)]
	elif working and not can.is_empty() and not can.done and int(can.carrier) < 0 and role != 2:
		target = can.pos
	elif working and not bolts.is_empty() and not bolts.done:
		var spots: Array = bolts.spots
		var got: Array = bolts.got
		var best := INF
		for i in 3:
			if bool(got[i]):
				continue
			var at: Vector3 = P.BOLT_SPOTS[int(spots[i])]
			var d: float = (at - (p.global_position as Vector3)).length() + (0.0 if i == role else 4.0)
			if d < best:
				best = d
				target = at
	elif working and not pipe.is_empty() and not pipe.done:
		var spot: Vector3 = P.PIPE_SPOTS[int(pipe.spot)]
		var inward := Vector3(-signf(spot.x), 0, 0) if absf(spot.z) < 7.0 else Vector3(0, 0, -1)
		target = Vector3(spot.x, 0, spot.z) + inward * 1.2
		if Vector2(p.global_position.x - target.x, p.global_position.z - target.z).length() < 0.6:
			p.bot_action = true
	elif working and not paint.is_empty() and not paint.done and int(paint.carrier) < 0:
		target = P.PAINT_SPOTS[int(paint.answer)]
	elif working and not can.is_empty() and not can.done and int(can.carrier) < 0:
		target = can.pos
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
	if OS.has_environment("BOT_DEBUG") and Engine.get_physics_frames() % 120 == 0:
		print("DBG P%d pos=%s target=%s route=%s" % [p.index + 1, pos, target, _route(pos, Vector3(target.x, 0.0, target.z))])
	target = _route(pos, Vector3(target.x, 0.0, target.z))
	var to := target - pos
	to.y = 0.0
	if to.length() > 0.3:
		p.bot_move = to.normalized()
		p.yaw = atan2(-to.x, -to.z)
	else:
		p.bot_move = Vector3.ZERO


## Simple way-finding: through the launch doorway, and round the pilot's booth.
func _route(pos: Vector3, target: Vector3) -> Vector3:
	if (pos.z > -6.15) != (target.z > -6.15) and absf(pos.x) > 3.0:
		return Vector3(clampf(pos.x, -2.5, 2.5), 0, -6.15)
	var lo := Vector2(-1.7, -1.6)
	var hi := Vector2(1.7, 1.35)
	var steps_n := 12
	for i in steps_n + 1:
		var q := pos.lerp(target, float(i) / steps_n)
		if q.x > lo.x and q.x < hi.x and q.z > lo.y and q.z < hi.y:
			if absf(pos.x) < 1.9:
				return Vector3(2.4 * (1.0 if pos.x >= 0.0 else -1.0), 0, pos.z)
			return Vector3(pos.x, 0, target.z)
	return target


# --- Launch cam -------------------------------------------------------------------

func _check_cam() -> void:
	if cam_checked or main.phase != "launch" or main.launch_t < 7.0:
		return
	for p in main.players:
		if p.index > 0 and p.active and p.camera != null and not p.remote:
			cam_checked = true
			var y: float = p.camera.global_position.y
			print("Bot: launch cam at y=%.0f (%s), env %s" % [y, "in space" if y < -1000.0 else "NOT in space", "set" if p.camera.environment != null else "none"])
			break


# --- End screen and restart (local runs) ---------------------------------------

func _check_over(delta: float) -> void:
	if main.net.mode != "local":
		return
	if not forced_over and not Engine.has_meta("rw_bot_restarts") and (main.phase == "work" or main.phase == "ready") \
			and (main.launched >= 3 or t > 52.0):
		forced_over = true
		print("Bot: letting the clock run out to test the end screen")
		main.time_left = 0.3
	# Speed up the launch cinematics a little once the space camera has been seen.
	if main.phase == "launch" and cam_checked and main.launch_t > 7.5 and main.launch_t < 9.8:
		main.launch_t = 9.8
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
