extends Node
# Headless test for Kitchen Rush: an autopilot button-chef (host/local) and autopilot runners (client/local).
# The chef uses the real button-chef actions (cursor + grab + chop); runners walk with bot_move and press_use().
# BOT_PLAYERS=N (1..6): N TV runners join (local split screen, or on the TV machine when networked). The last
# one joins through a fake controller pressing Start (the real drop-in path); with N >= 3 that controller is
# later "unplugged" (the runner should leave after 15 s) and plugged back in (it should rejoin).
const L := preload("res://games/kitchen_rush/layout.gd")
const M := preload("res://games/kitchen_rush/main.gd")

var main
var t := 0.0
var chef_t := 0.0
var use_t := {}
var last_pos := {}
var stuck_t := {}
var max_shift := 0
var joined := false
var log_t := 0.0
var want_players := 1
var next_join := 2
var join_at := 3.0
const FAKE_PAD := 60
var unplug_stage := 0
var max_active := 0


func _ready() -> void:
	main = load("res://games/kitchen_rush/main.tscn").instantiate()
	add_child(main)
	var default_players := 2 if OS.has_environment("DUO_JOIN") else 1
	want_players = clampi(int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else default_players, 1, 6)
	print("BOT: %d TV runner(s) requested" % want_players)


func _physics_process(delta: float) -> void:
	t += delta
	if not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if OS.has_environment("KR_LAZY") and mode != "client":
		# Game-over test: nobody cooks and customers run out of patience fast; then press Enter to restart.
		for c in main._waiting_customers():
			c.patience = minf(c.patience, 0.5)
		if main.game_over and main.game_over_t > 2.5 and not Engine.has_meta("kr_restarted"):
			Engine.set_meta("kr_restarted", true)
			print("BOT: game over seen, pressing Enter to restart")
			var e := InputEventKey.new()
			e.physical_keycode = KEY_ENTER
			e.pressed = true
			Input.parse_input_event(e)
		if Engine.has_meta("kr_restarted") and not main.game_over and t < 1.0 and not has_meta("said"):
			set_meta("said", true)
			print("BOT: restarted into a fresh kitchen")
		return
	if mode != "client":
		_chef(delta)
	if mode != "host":
		for i in range(1, main.players.size()):
			var p = main.players[i]
			if p.active:
				_runner(p, delta)
		_join_players(mode)
	if main.shift > max_shift:
		max_shift = main.shift
		print("BOT: reached shift %d (%s)" % [max_shift, mode])
	log_t -= delta
	if log_t <= 0.0:
		log_t = 5.0
		var carry := []
		for i in range(1, main.players.size()):
			carry.append(main.players[i].carry_kind)
		var act := []
		for i in range(1, main.players.size()):
			if main.players[i].active:
				act.append("P%d" % (i + 1))
		max_active = maxi(max_active, act.size())
		print("BOT t=%.0f runners=%s views=%d mode=%s shift=%d coins=%d served=%d/%d total=%d angry=%d items=%d customers=%d fire=%s raccoon=%s carry=%s" % [
			t, act, _views(), mode, main.shift, main.coins, main.served_shift, main.shift_target(), main.served_total, main.angry,
			main.all_items().size(), main._waiting_customers().size(), main.fire_on, main.raccoon.visible, carry])
		if mode == "host":
			print("   snapshot bytes: %d" % var_to_bytes(main.make_snapshot()).size())
		if mode != "host":
			print("   runner1 at %s next=%s need=%s" % [main.players[1].global_position.snapped(Vector3.ONE * 0.1), _next_ingredient(1), _needed_recipes()])


func _views() -> int:
	var n := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			n += 1
	return n


## Bring in the extra TV players one at a time, then exercise unplug / replug of the last one.
func _join_players(mode: String) -> void:
	if t < join_at or (mode == "client" and not main.synced):
		return
	if next_join <= want_players:
		join_at = t + 0.7
		if next_join == want_players and next_join >= 3:
			# Pretend P2 (and the split-screen chef) already own controllers, so the new one is a new player.
			if main.players[1].joy < 0:
				main.players[1].joy = FAKE_PAD + 1
			if mode == "local" and main.players[0].joy < 0:
				main.players[0].joy = FAKE_PAD + 2
			print("BOT: fake controller %d presses Start to join" % FAKE_PAD)
			var e := InputEventJoypadButton.new()
			e.device = FAKE_PAD
			e.button_index = JOY_BUTTON_START
			e.pressed = true
			Input.parse_input_event(e)
			var e2 := e.duplicate() as InputEventJoypadButton
			e2.pressed = false
			Input.parse_input_event(e2)
		else:
			print("BOT: debug_join(%d)" % next_join)
			main.debug_join(next_join)
		next_join += 1
		return
	if want_players < 3:
		return
	var p = main.players[want_players]
	if unplug_stage == 0 and t > 12.0:
		unplug_stage = 1
		print("BOT: P%d joy=%d paused=%s, unplugging controller %d" % [want_players + 1, p.joy, get_tree().paused, FAKE_PAD])
		main._on_joy_changed(FAKE_PAD, false)
	elif unplug_stage == 1 and not p.active:
		unplug_stage = 2
		print("BOT: P%d left after unplug (t=%.1f)" % [want_players + 1, t])
		main._on_joy_changed(FAKE_PAD, true)
	elif unplug_stage == 2 and p.active:
		unplug_stage = 3
		print("BOT: P%d rejoined after replug (t=%.1f) joy=%d" % [want_players + 1, t, p.joy])


# --- Chef ---------------------------------------------------------------------

func _needed_recipes() -> Array:
	var cs: Array = main._waiting_customers()
	cs.sort_custom(func(a, b) -> bool: return a.frac < b.frac)
	var need := []
	for c in cs:
		need.append(c.recipe)
	for it in main.all_items():
		if it.is_plate() and it.recipe != "":
			need.erase(it.recipe)
	for i in range(1, main.players.size()):
		var ck: String = main.players[i].carry_kind
		if ck.begins_with("plate:"):
			need.erase(ck.substr(6))
	return need


func _subset(a: Array, b: Array) -> bool:
	for k in a:
		if not b.has(k):
			return false
	return true


func _plan() -> Dictionary:
	var need := _needed_recipes()
	var plan := {}
	for h in 2:
		var p = main._home_plate(h)
		if p == null or p.recipe != "":
			continue
		var r := ""
		for cand in need:
			if _subset(p.contents, M.RECIPES[cand]):
				r = cand
				break
		if r != "":
			need.erase(r)
		plan[h] = r
	return plan


func _spot_of(it) -> int:
	var best := 0
	var best_d := INF
	for i in L.spot_count():
		var d: float = main.flat_dist(it.global_position, L.spot_pos(i))
		if d < best_d:
			best_d = d
			best = i
	return best


func _chef(delta: float) -> void:
	chef_t -= delta
	if chef_t > 0.0 or main.game_over:
		return
	chef_t = 0.15
	var chef = main.players[0]
	var plan := _plan()
	var held = chef.held[0]
	if held != null:
		if held.is_plate():
			chef.cursor = 4
			chef.do_grab()
			return
		for h in plan:
			var p = main._home_plate(h)
			if plan[h] != "" and held.is_ready() and M.RECIPES[plan[h]].has(held.kind) and not p.contents.has(held.kind):
				chef.cursor = 5 if h == 0 else 7
				chef.do_grab()
				return
		var slot: int = main.free_pass_slot(Vector3.ZERO)
		if not _wanted(held.kind, plan) or slot < 0:
			chef.cursor = 4
		else:
			chef.cursor = slot
		chef.do_grab()
		return
	for h in plan:
		var p = main._home_plate(h)
		if plan[h] == "":
			if p.contents.size() > 0:
				chef.cursor = 5 if h == 0 else 7
				chef.do_grab()
				return
			continue
		for k in M.RECIPES[plan[h]]:
			if p.contents.has(k):
				continue
			var it = _counter_item(k)
			if it == null:
				continue
			chef.cursor = _spot_of(it)
			if it.needs_chop():
				if not main.fire_on:
					chef.do_chop()
					return
				continue
			chef.do_grab()
			return
	# Pass clogged with things nobody needs: bin one.
	if main.free_pass_slot(Vector3.ZERO) < 0:
		for i in 4:
			var it2 = main.item_at(L.PASS_SLOTS[i], 0.15)
			if it2 != null and not _wanted(it2.kind, plan):
				chef.cursor = i
				chef.do_grab()
				return


func _wanted(kind: String, plan: Dictionary) -> bool:
	for h in plan:
		if plan[h] != "" and M.RECIPES[plan[h]].has(kind):
			return true
	return false


func _counter_item(kind: String):
	for it in main.all_items():
		if it.holder == -1 and not it.is_plate() and it.kind == kind:
			return it
	return null


# --- Runners ------------------------------------------------------------------

func _next_ingredient(index: int) -> String:
	var need := _needed_recipes().slice(0, 2)
	var missing := []
	for r in need:
		for k in M.RECIPES[r]:
			missing.append(k)
	for h in 2:
		var p = main._home_plate(h)
		if p != null and p.recipe == "":
			for k in p.contents:
				missing.erase(k)
	for it in main.all_items():
		if not it.is_plate() and it.holder == -1:
			missing.erase(it.kind)
		elif not it.is_plate() and it.holder == 0:
			missing.erase(it.kind)
	for i in range(1, main.players.size()):
		missing.erase(main.players[i].carry_kind)
	if missing.is_empty():
		return ""
	return missing[(index - 1) % missing.size()]


func _runner(p, delta: float) -> void:
	var cd: float = use_t.get(p.index, 0.0) - delta
	use_t[p.index] = cd
	var c: String = p.carry_kind
	var idle := Vector3(-1.5 + float((p.index - 1) % 4), 0.0, -1.6 - 0.6 * floorf(p.index / 4.0))
	var goal := idle
	if c == "":
		var plate = null
		var need := _needed_recipes_with_plates()
		for it in main.all_items():
			if it.is_plate() and it.recipe != "" and it.holder == -1 and need.has(it.recipe):
				plate = it
		if main.fire_on and main.ext_holder == -1 and p.index == want_players:
			goal = L.EXT_POS + Vector3(0, 0, 1.0)
		elif plate != null:
			goal = Vector3(plate.global_position.x, 0.0, -0.8)
		else:
			var kind := _next_ingredient(p.index)
			if kind != "":
				goal = L.source_stand(kind)
	elif c == "extinguisher":
		goal = L.STOVE + Vector3(0, 0, 1.4) if main.fire_on else L.EXT_POS + Vector3(0, 0, 1.0)
	elif c.begins_with("plate:"):
		for cu in main._waiting_customers():
			if cu.recipe == c.substr(6):
				goal = cu.serve_point()
	else:
		var slot: int = main.free_pass_slot(p.global_position)
		if slot >= 0:
			goal = Vector3(L.PASS_SLOTS[slot].x, 0.0, -0.8)
	_walk(p, goal, delta)
	if main.flat_dist(p.global_position, goal) < 0.7 and cd <= 0.0:
		var r: Dictionary = main.resolve(p)
		if r.has("act") and r["act"] != "return" and r["act"] != "put_ext":
			p.press_use()
			use_t[p.index] = 0.45


## Plates that some waiting customer still wants (counting plates already being carried).
func _needed_recipes_with_plates() -> Array:
	var need := []
	for c in main._waiting_customers():
		need.append(c.recipe)
	for i in range(1, main.players.size()):
		var ck: String = main.players[i].carry_kind
		if ck.begins_with("plate:"):
			need.erase(ck.substr(6))
	return need


func _walk(p, goal: Vector3, delta: float) -> void:
	var pos: Vector3 = p.global_position
	var wp := goal
	var inside := pos.z > -6.0
	var goal_inside := goal.z > -6.0
	if inside != goal_inside:
		if inside:
			wp = Vector3(0, 0, -6.9) if absf(pos.x) < 0.5 and pos.z < -4.75 else Vector3(0, 0, -5.0)
		else:
			wp = Vector3(0, 0, -5.0) if absf(pos.x) < 0.5 and pos.z > -7.15 else Vector3(0, 0, -6.9)
	elif inside:
		# Go round the counter on the garden side.
		var crossing := (pos.z > -0.7 or goal.z > -0.7) and signf(pos.x) != signf(goal.x) and absf(pos.x - goal.x) > 0.5
		if (absf(goal.x) > 1.8 and absf(pos.x) < 1.8 and goal.z > -0.7) or (absf(pos.x) > 1.8 and absf(goal.x) < 1.8 and pos.z > -0.7) or crossing:
			var side := signf(goal.x if absf(goal.x) > 1.8 else pos.x)
			var corner := Vector3(side * 1.95, 0, -0.95)
			if main.flat_dist(pos, corner) > 0.3 and pos.z > -0.85:
				wp = corner
			elif pos.z > -0.85 and absf(pos.x) < 1.8:
				wp = Vector3(pos.x, 0, -1.0)
	var to: Vector3 = wp - pos
	to.y = 0.0
	if to.length() < 0.15:
		p.bot_move = Vector3.ZERO
		return
	p.bot_move = to.normalized() * minf(1.0, to.length() * 2.0)
	p.yaw = atan2(-to.x, -to.z)
	# Unstick: if we haven't moved for a while, sidestep.
	var lp: Vector3 = last_pos.get(p.index, pos)
	if pos.distance_to(lp) < 0.01:
		stuck_t[p.index] = stuck_t.get(p.index, 0.0) + delta
	else:
		stuck_t[p.index] = 0.0
	last_pos[p.index] = pos
	if stuck_t.get(p.index, 0.0) > 0.6:
		p.bot_move = Basis(Vector3.UP, PI / 2.0) * p.bot_move + Vector3(0, 0, -0.5)
