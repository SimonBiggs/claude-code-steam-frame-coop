extends Node
## Headless bot for Hide and Seek. Same scene on host and client (so node paths match).
## Seeker (local / host): once the count is over, walks up to the nearest hider still hiding, aims the
## torch and clicks. In round 2 the seeker dawdles, so the hiders win on time.
## Hiders (local / client): each runs to a hiding spot while the seeker counts, disguises, and squeaks.
## BOT_PLAYERS=N (1..6): N TV hiders (P2..P{N+1}); extras join via main.debug_join(). In local mode with
## N >= 4 the bot also fakes a controller unplug/replug and a player leaving and rejoining.
const WorldScript := preload("res://games/hide_and_seek/world.gd")

var main
var t := 0.0
var last_print := -100.0
var click_t := 0.0
var near_t := 0.0
var bot_players := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else 1
var spots := {}  # player index -> hiding spot
var rounds_seen := {}


func _ready() -> void:
	main = load("res://games/hide_and_seek/main.tscn").instantiate()
	main.count_time = 5.0
	main.intro_time = 3.0
	main.seek_override = 25.0
	add_child(main)
	# Real controllers may be plugged into this machine: don't let someone's button presses join players.
	var no_join := Node.new()
	add_child(no_join)
	main.set_meta("join_input", no_join)


func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _aim(p, target: Vector3) -> void:
	var d: Vector3 = target - (p.global_position + Vector3.UP * p.EYE_HEIGHT)
	var flat := Vector2(d.x, d.z).length()
	if flat > 0.05:
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = atan2(d.y, flat)


func _walk_to(p, target: Vector3, keep: float, delta: float, speed: float) -> bool:
	var to: Vector3 = target - p.global_position
	to.y = 0.0
	if to.length() <= keep:
		return true
	var step: Vector3 = to.normalized() * minf(speed * delta, to.length() - keep)
	p.global_position += step
	return false


func _physics_process(delta: float) -> void:
	t += delta
	if main == null or main.players.size() < 2 or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	# Real controllers may be plugged into this machine (someone might be playing!): ignore them.
	var real := Input.get_connected_joypads()
	for p in main.players:
		if real.has(p.joy):
			p.joy = -1
	if bot_players >= 2 and mode != "host" and t > (6.0 if mode == "client" else 1.0) and not has_meta("joined"):
		set_meta("joined", true)
		for i in range(2, mini(bot_players, 6) + 1):
			print("BOT: P%d joins" % (i + 1))
			main.debug_join(i)
	if mode == "local" and bot_players >= 4:
		_test_pads()
	if not rounds_seen.has(main.round_no):
		rounds_seen[main.round_no] = true
		spots.clear()
	if mode != "client":
		_seeker(delta)
		if main.phase == "over" and main.over_t > 2.5:
			if main.round_no >= 2:
				main.seek_override = 25.0
			print("BOT: play again")
			main._start_round()
			if main.round_no == 2:
				main.seek_override = 8.0  # round 2: the seeker dawdles and the hiders win on time
	else:
		if main.phase == "over" and main.over_t > 2.5 and not has_meta("asked_%d" % main.round_no):
			set_meta("asked_%d" % main.round_no, true)
			print("BOT: client asks to play again")
			main.net.send_action("restart", [])
	if mode != "host":
		_hiders(delta)
	if t - last_print >= 4.0:
		last_print = t
		var act := []
		for p in main.players:
			if p.active:
				act.append("P%d%s%s" % [p.index + 1, "*" if p.found else "", "(%s)" % WorldScript.PROP_NAMES[p.prop_kind] if p.prop_kind >= 0 else ""])
		print("BOT t=%.0f mode=%s round=%d phase=%s left=%.0f hiding=%d views=%d players=%s scores=%s" % [
			t, mode, main.round_no, main.phase, main.phase_t, main.hiders_left(), main.view_count, act, main.round_scores])


func _seeker(delta: float) -> void:
	var s = main.players[0]
	if main.phase != "seek" or s.vr:
		s.bot_fire = false
		return
	if main.round_no == 2:
		s.bot_fire = false
		return  # dawdle
	var best = null
	var best_d := INF
	for h in main.players:
		if h.is_hiding():
			var d: float = h.global_position.distance_to(s.global_position)
			if d < best_d:
				best_d = d
				best = h
	if best == null:
		return
	# Torch from 2 m; if a wall is in the way, walk right up and bump into them instead.
	near_t = near_t + delta if best_d < 2.3 else 0.0
	s.collision_mask = 1 if near_t < 1.5 else 0  # the bot can't path-find round walls: let it squeeze through
	var there := _walk_to(s, best.global_position, 2.0 if near_t < 1.5 else 0.4, delta, 3.5)
	_aim(s, best.center())
	click_t -= delta
	if there and click_t <= 0.0:
		click_t = 0.4
		s.bot_fire = not s.bot_fire
	elif not there:
		s.bot_fire = false
		if randf() < 0.01:
			s.bot_fire = true  # an occasional miss (hits a decoy or nothing)


func _hiders(delta: float) -> void:
	var used := {}
	for p in main.players:
		if p.index == 0 or p.remote or p.ghost or not p.active:
			continue
		if not p.is_hiding() or (main.phase != "count" and main.phase != "seek"):
			p.bot_fire = false
			p.bot_alt = false
			continue
		if not spots.has(p.index):
			var choice: Vector3 = WorldScript.HIDE_SPOTS[(p.index * 5 + main.round_no * 3) % WorldScript.HIDE_SPOTS.size()]
			spots[p.index] = choice
		var spot: Vector3 = spots[p.index]
		used[spot] = true
		if p.prop_kind < 0:
			var there := _walk_to(p, spot, 0.2, delta, 5.0)
			if there and main.phase == "count" and (p.index + main.round_no) % 2 == 0:
				p.toggle_disguise()  # half of the hiders turn into furniture
		if main.phase == "seek":
			p.bot_alt = fmod(t + p.index * 0.7, 7.0) < 0.2  # squeak now and then


## Local only: fake a controller for P4, unplug and replug it; then P5 times out, leaves and rejoins.
func _test_pads() -> void:
	var p4 = main.players[3]
	var p5 = main.players[4]
	if t > 4.0 and not has_meta("unplug"):
		set_meta("unplug", true)
		p4.joy = 97
		main._on_joy_changed(97, false)
		print("BOT: unplugged P4's pad -> waiting=%s joy=%d" % [main.pad_wait.has(3), p4.joy])
	if t > 5.0 and not has_meta("replug"):
		set_meta("replug", true)
		main._on_joy_changed(97, true)
		print("BOT: replugged -> P4 joy=%d waiting=%s" % [p4.joy, main.pad_wait.has(3)])
		p4.joy = -1
	if t > 6.0 and not has_meta("leave"):
		set_meta("leave", true)
		p5.joy = 98
		main._on_joy_changed(98, false)
		main.pad_wait[4] = 0.3
	if t > 7.0 and not has_meta("left"):
		set_meta("left", true)
		print("BOT: P5 active after pad timeout = %s" % p5.active)
	if t > 8.0 and not has_meta("rejoin"):
		set_meta("rejoin", true)
		main.debug_join(4)
		print("BOT: P5 rejoined = %s (late=%s, phase=%s)" % [p5.active, p5.late, main.phase])
