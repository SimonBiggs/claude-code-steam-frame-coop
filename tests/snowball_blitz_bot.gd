extends Node
## Headless bot for Snowball Blitz. The first local player snipes the nearest snowman with charged
## lobs; the second local player packs the most damaged fort wall (and throws when the fort is fine).
## On the client it also wakes player 3 by "pressing" throw.

var main
var t := 0.0
var next_report := 0.0
var cycle := {}  # player index -> seconds into the current charge/throw cycle


func _ready() -> void:
	if Engine.has_meta("sb_bot_restarts"):
		print("Bot: game restarted")
		var up := InputEventKey.new()
		up.physical_keycode = KEY_ENTER
		up.pressed = false
		Input.parse_input_event(up)
	main = load("res://games/snowball_blitz/main.tscn").instantiate()
	add_child(main)


func _physics_process(delta: float) -> void:
	t += delta
	if not main.ready_to_play:
		return
	for p in main.players:
		if p.ghost or p.remote:
			continue
		if not p.active:
			p.bot_throw = t > 4.0 and fmod(t, 2.0) < 0.3
			continue
		if p.index == 1 and _repair_role(p):
			continue
		_throw_role(p, delta)
	_check_restart()
	if t >= next_report:
		next_report += 5.0
		_report()


func _report() -> void:
	var ps: Array[String] = []
	for p in main.players:
		ps.append("P%d%s hp=%d%s%s" % [p.index + 1, "" if p.active else "(idle)", int(p.hp), " DOWN" if p.is_down else "",
			" repairing" if p.repairing else ""])
	print("t=%.0f mode=%s wave=%d score=%d fort=%d%% snowmen=%d cocoa=%d balls=%d over=%s | %s" % [t, main.net.mode, main.wave, main.score,
		int(main.fort_fraction() * 100.0), get_tree().get_nodes_in_group("snowmen").size(), get_tree().get_nodes_in_group("cocoa").size(),
		main.get_children().filter(func(c): return c.get("spin") != null).size(), main.game_over, ", ".join(ps)])


## Walk to the most damaged wall and pack it. Returns false when nothing needs packing.
func _repair_role(p) -> bool:
	var worst := -1
	var worst_hp := 75.0
	for i in main.segments:
		if main.seg_hp[i] < worst_hp:
			worst_hp = main.seg_hp[i]
			worst = i
	if worst < 0 and not p.repairing:
		p.bot_repair = false
		p.bot_move = Vector3.ZERO
		return false
	if worst < 0:
		worst = p.repair_seg
	var spot: Vector3 = main.seg_center(worst) * ((main.fort_r - 1.1) / main.fort_r)
	var to: Vector3 = spot - p.global_position
	to.y = 0.0
	p.bot_throw = false
	if to.length() > 0.5:
		p.bot_move = to.normalized()
		p.bot_repair = false
	else:
		p.bot_move = Vector3.ZERO
		p.bot_repair = main.seg_hp[worst] < main.seg_max
		p.yaw = atan2(-(main.seg_center(worst) - p.global_position).x, -(main.seg_center(worst) - p.global_position).z)
	return true


func _throw_role(p, delta: float) -> void:
	p.bot_repair = false
	p.bot_move = Vector3.ZERO
	var best = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("snowmen"):
		var dd: float = s.global_position.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = s
	var c: float = cycle.get(p.index, 0.0) + delta
	cycle[p.index] = c
	if best == null:
		p.bot_throw = false
		return
	var target: Vector3 = best.global_position + Vector3.UP * best.height * 0.45
	var eye: Vector3 = p.global_position + Vector3.UP * 1.5
	var flat := Vector2(target.x - eye.x, target.z - eye.z)
	p.yaw = atan2(-flat.x, -flat.y)
	p.pitch = _solve_pitch(flat.length(), target.y - eye.y, 24.0)
	# Hold for a full charge, then release.
	p.bot_throw = c < 1.0
	if c > 1.15:
		cycle[p.index] = 0.0


## Pitch that lands a full-charge throw at horizontal distance dist and height dy (numeric search).
func _solve_pitch(dist: float, dy: float, speed: float) -> float:
	var best := 0.0
	var best_err := INF
	for k in 40:
		var pitch := -0.4 + k * 0.03
		var v := Vector2(cos(pitch) * speed, sin(pitch) * speed + 1.5)
		var x := 0.5 * cos(pitch)
		var y := 0.5 * sin(pitch)
		var err := INF
		for i in 200:
			v.y -= main.gravity * 0.02
			x += v.x * 0.02
			y += v.y * 0.02
			if x >= dist:
				err = absf(y - dy)
				break
			if y < -2.0:
				break
		if err < best_err:
			best_err = err
			best = pitch
	return best


var over_t := 0.0
## After a game over, press Enter (once per run) to check that restarting works.
func _check_restart() -> void:
	if not main.game_over:
		over_t = 0.0
		return
	over_t += get_physics_process_delta_time()
	var restarts: int = Engine.get_meta("sb_bot_restarts", 0)
	if restarts >= 1 or over_t < 3.0:
		return
	Engine.set_meta("sb_bot_restarts", restarts + 1)
	print("Bot: pressing Enter to restart")
	if true:
		var e := InputEventKey.new()
		e.physical_keycode = KEY_ENTER
		e.pressed = true
		Input.parse_input_event(e)
