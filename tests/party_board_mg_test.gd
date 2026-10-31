extends SceneTree
## PARTY BOARD minigames: proves every SIMPLE_MODE minigame is winnable by a small child, fair across player
## counts and playable by the VR giant - by PLAYING them, headless and fast-forwarded (no window, no network).
##   godot-test --headless --path . -s res://tests/party_board_mg_test.gd      (SEEDS=20 for more)
## Each minigame (games/party_board/mg_runner.gd SIMPLE_GAMES) runs on a stand-in for main.gd with:
##   - a SMALL CHILD in one seat (it moves late, wobbles, pushes the stick only part way, presses late, misses,
##     and presses at random) against the game's own kid-gentle CPUs, for 1-6 players, the child in every seat
##     in turn: the child must win at least a third of a fair share at every player count, and always alone;
##   - all CPUs in 4 seats: every seat must score about the same (the arena is fair to where you start);
##   - 2 and 6 players: each player must still get a fair amount to do with 6 (more coins / moles / balloons);
##   - a VR GIANT (a gloved hand reaching for the game's bot_vr_goal, bobbing up and down) with 3 CPUs: the giant
##     must be able to score, and the islanders must be able to beat it.
## Also: every simple minigame is one motion or one button (its META), at most 25 seconds, and has a picture cue.
## Prints "SCRIPT ERROR: ..." for each failure, then "BOT RESULT: PASS/FAIL".

const MgRunner := preload("res://games/party_board/mg_runner.gd")
const DT := 1.0 / 30.0


class FakeFlow:
	extends RefCounted
	func is_kid() -> bool:
		return true


class FakeSfx:
	extends RefCounted
	func play(_s: String, _db: float = 0.0, _p: float = 1.0) -> void:
		pass


class FakeRunner:
	extends RefCounted
	const TEAM_COLORS := [Color(1.0, 0.4, 0.38), Color(0.35, 0.6, 1.0)]


## The VR giant's hands: both reach for the minigame's goal and bob up and down (pumps, taps and swats).
class FakeGiant:
	extends Node3D
	var mg: Node3D
	var t := 0.0
	func hand_pos(h: int) -> Vector3:
		if mg == null:
			return Vector3.ZERO
		var g: Vector3 = mg.call("bot_vr_goal")
		if g == Vector3.INF:
			g = Vector3(0, 2.0, 2.0)
		return mg.position + g + Vector3(0.3 * h, 0.7 * sin(t * 7.0 + h), 0)


class FakeMain:
	extends Node3D
	var simple := true
	var quick := false
	var vr_rig = null
	var giant = null
	var flow := FakeFlow.new()
	var sfx := FakeSfx.new()
	var runner := FakeRunner.new()
	var humans := {}  ## pid -> true: input comes from `inputs`
	var inputs := {}  ## pid -> {move, pressed, held}
	func is_cpu(pid: int) -> bool:
		return not humans.has(pid)
	func pad_input(pid: int) -> Dictionary:
		return inputs.get(pid, {"move": Vector3.ZERO, "pressed": false, "held": false})
	func color_of(pid: int) -> Color:
		return Color.from_hsv(fmod(pid * 0.17, 1.0), 0.7, 1.0)
	func name_of(pid: int) -> String:
		return "P%d" % (pid + 1)
	func look_of(_pid: int) -> Array:
		return ["farmer", "none", Color(0.4, 0.3, 0.2)]
	func fx(_kind: String, _args: Array) -> void:
		pass
	func burst(_at: Vector3, _c: Color, _n: int = 16) -> void:
		pass
	func to_world(p: Vector3) -> Vector3:
		return p
	func to_board(p: Vector3) -> Vector3:
		return p


var fails := 0
var main: FakeMain
var rng := RandomNumberGenerator.new()
# the child's memory
var _goal := Vector3.ZERO
var _goal_t := 0.0
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _press_at := -1.0
var _bite_seen := false


func _init() -> void:
	main = FakeMain.new()
	root.add_child(main)
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 10
	var t0 := Time.get_ticks_msec()
	for id in MgRunner.SIMPLE_GAMES:
		var sc: GDScript = load(MgRunner.MG_DIR + String(id) + ".gd")
		_expect(sc != null, "%s exists" % id)
		if sc == null:
			continue
		var meta: Dictionary = sc.get_script_constant_map().get("META", {})
		_check_meta(String(id), meta)
		var limit := minf(float(meta.get("time", 25.0)), MgRunner.SIMPLE_MAX_TIME)
		var line := PackedStringArray()
		var per_player := {}
		for n in [1, 2, 3, 4, 5, 6]:
			var child_wins := 0
			var games := 0
			var total := 0.0
			for s in seeds:
				var child: int = s % int(n)
				var r := _play(sc, String(id), int(n), child, 1000 + s * 17 + int(n), limit, false)
				games += 1
				if (r.winners as Array).has(child):
					child_wins += 1.0
				for p in n:
					total += float((r.scores as Dictionary).get(p, 0.0))
			var share := float(child_wins) / float(games)
			per_player[n] = total / float(games * n)
			line.append("%d:%.0f%%" % [n, share * 100.0])
			if n == 1:
				_expect(child_wins == games, "%s: a small child playing alone always wins (%d/%d)" % [id, child_wins, games])
			else:
				_expect(share >= 1.0 / float(n) / 3.0, "%s: a small child wins with %d players (%.0f%%, fair share %.0f%%)" % [
					id, n, share * 100.0, 100.0 / n])
		_expect(float(per_player[6]) >= 0.35 * float(per_player[2]), "%s: still plenty to do with 6 players (%.1f each vs %.1f with 2)" % [
			id, float(per_player[6]), float(per_player[2])])
		# Seat fairness: four identical CPUs, every seat about the same.
		var seat := [0.0, 0.0, 0.0, 0.0]
		for s in seeds * 2:
			var r2 := _play(sc, String(id), 4, -1, 5000 + s * 31, limit, false)
			for p in 4:
				seat[p] += float((r2.scores as Dictionary).get(p, 0.0))
		var mean: float = (seat[0] + seat[1] + seat[2] + seat[3]) / 4.0
		for p in 4:
			_expect(mean <= 0.0 or absf(seat[p] - mean) <= 0.35 * mean, "%s: seat %d scores like the others (%s)" % [id, p + 1, str(seat)])
		# The VR giant with three CPU islanders.
		var g_scored := 0
		var g_wins := 0
		for s in seeds:
			var r3 := _play(sc, String(id), 4, -1, 9000 + s * 13, limit, true)
			if float((r3.scores as Dictionary).get(0, 0.0)) > 0.0:
				g_scored += 1
			if (r3.winners as Array) == [0]:
				g_wins += 1
		_expect(g_scored >= seeds / 2, "%s: the VR giant can score (%d/%d games)" % [id, g_scored, seeds])
		_expect(g_wins < seeds, "%s: the islanders can beat the VR giant (giant won %d/%d)" % [id, g_wins, seeds])
		print("mg fair: %-14s child wins %s | per player 2p %.1f 6p %.1f | seats %s | giant scored %d/%d won %d" % [
			id, " ".join(line), float(per_player[2]), float(per_player[6]), str(seat), g_scored, seeds, g_wins])
	print("mg fair: %d failures in %.1f s" % [fails, (Time.get_ticks_msec() - t0) / 1000.0])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	main.free()
	quit(0 if fails == 0 else 1)


func _check_meta(id: String, meta: Dictionary) -> void:
	var tv: Array = meta.get("tv", [])
	var buttons := 0
	var stick := 0
	for c in tv:
		var k := String((c as Array)[0])
		if k == "A":
			buttons += 1
		elif k.contains("STICK"):
			stick += 1
	_expect(buttons + stick >= 1 and buttons + stick <= 2 and buttons <= 1, "%s: one motion and at most one button %s" % [id, str(tv)])
	_expect(["catch", "mash", "pop"].has(String(meta.get("cue", ""))), "%s: has a picture cue (%s)" % [id, String(meta.get("cue", ""))])
	_expect(String(meta.get("format", "ffa")) == "ffa", "%s: free for all" % id)
	_expect(float(meta.get("time", 99.0)) <= MgRunner.SIMPLE_MAX_TIME, "%s: short (%.0f s)" % [id, float(meta.get("time", 99.0))])


## Play one round: n walkers (pids 0..n-1; with a giant pid 0 is the giant and walkers are 1..n-1), the child in
## seat `child` (-1 = all CPUs). Returns {scores, winners}.
func _play(sc: GDScript, id: String, n: int, child: int, seed_value: int, limit: float, with_giant: bool) -> Dictionary:
	rng.seed = seed_value
	main.humans.clear()
	main.inputs.clear()
	if child >= 0:
		main.humans[child] = true
	var fg: FakeGiant = null
	if with_giant:
		fg = FakeGiant.new()
		main.add_child(fg)
		main.giant = fg
	var pids: Array = []
	for p in n:
		pids.append(p)
	var mg: Node3D = sc.new()
	mg.setup(main, {"id": id, "seed": seed_value, "pids": pids, "teams": {}, "giant": with_giant, "format": "ffa", "n": 1}, true)
	main.add_child(mg)
	if fg != null:
		fg.mg = mg
	mg.begin_play()
	_goal_t = 0.0
	_wander_t = 0.0
	_press_at = -1.0
	_bite_seen = false
	var t := 0.0
	while t < limit:
		t += DT
		if fg != null:
			fg.t = t
		if child >= 0:
			main.inputs[child] = _child_input(mg, id, child)
		mg.tick(DT)
		if mg.finished():
			break
	var scores := {}
	var best := 0.0
	for p in pids:
		scores[p] = float(mg.score.get(p, 0.0))
		best = maxf(best, float(scores[p]))
	var winners: Array = []
	if best > 0.0:
		for p in pids:
			if float(scores[p]) == best:
				winners.append(p)
	mg.free()
	if fg != null:
		main.giant = null
		fg.free()
	return {"scores": scores, "winners": winners}


## A small child: late to notice where to go, wobbly, gentle on the stick, late and patchy on the button, and
## sometimes pressing just for fun.
func _child_input(mg: Node3D, id: String, pid: int) -> Dictionary:
	var me: Vector3 = mg.call("where", pid)
	_goal_t -= DT
	if _goal_t <= 0.0:
		_goal_t = rng.randf_range(0.7, 1.1)
		_goal = mg.call("cpu_move", pid)
	_wander_t -= DT
	if _wander_t <= -2.0 and rng.randf() < 0.1 * DT * 30.0 / 30.0:
		_wander_t = 0.5
		var a := rng.randf() * TAU
		_wander = Vector3(cos(a), 0, sin(a))
	var mv := Vector3.ZERO
	if _wander_t > 0.0:
		mv = _wander * 0.7
	else:
		var d := _goal - me
		d.y = 0.0
		if d.length() > 0.3:
			mv = d.normalized().rotated(Vector3.UP, rng.randf_range(-0.5, 0.5)) * 0.75
	var press := rng.randf() < 0.3 * DT  # just for fun
	match id:
		"kart_dash":
			press = rng.randf() < rng.randf_range(3.0, 5.0) * DT
		"fish_pond":
			var biting := int((mg.get("state") as Dictionary).get(pid, 0)) == 1
			if biting and not _bite_seen:
				_bite_seen = true
				_press_at = rng.randf_range(0.5, 1.3) if rng.randf() < 0.75 else -1.0
			if not biting:
				_bite_seen = false
			if _press_at > 0.0:
				_press_at -= DT
				if _press_at <= 0.0:
					press = true
					_press_at = -1.0
		"star_stack":
			var off: float = absf(float(mg.call("swing_x", pid)) - float(mg.call("top_off", pid)))
			press = press or (off < 0.5 and rng.randf() < 0.06)
		_:
			if bool(mg.call("cpu_press", pid)):
				press = press or rng.randf() < 0.5
	return {"move": mv, "pressed": press, "held": press}


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: mg fair: " + what)
