extends Node
## The board game's rules and flow (host / local only; the TV machine just draws the state store).
## title (setup menu, roster) -> intro (how to play, the STAR, turn order) -> rounds: every player
## takes a turn (items -> dice -> hop round the board, branch choices, passing the STAR / a shop ->
## the space's effect) -> a minigame for everyone -> ... -> the final turns (double coins) -> the
## ceremony (bonus stars, winner crowned, awards) -> back to the title for another party.
## The flow runs on a Sequencer (sequencer.gd), so it pauses with the game and never awaits timers.
## CPU players (filling up to 4 seats) are decided here too; late TV joiners take over a CPU seat or
## join at the next turn with catch-up coins; players who leave are replaced by a CPU.

const Seq := preload("res://games/party_board/sequencer.gd")
const Rules := preload("res://games/party_board/rules.gd")
const BD := preload("res://games/party_board/board_data.gd")
const Awards := preload("res://core/awards.gd")
const Hints := preload("res://core/hints.gd")

const CPU_NAMES := ["BOBO", "PIP", "MIMI", "TUTU", "ZAZA", "LULU", "KIKI"]
const MIN_SEATS := 4

var main: Node
var seq: Seq
var rng := RandomNumberGenerator.new()
var pl := {}  ## pid -> player record (published as the "players" state)
var order: Array[int] = []
var turn_i := 0
var round_n := 0
var rounds := 10
var kid := false
var menu_seq := 0
var menu_pid := -1
var menu_answer := ""
var dice_id := 0
var dice_n := 1
var dice_values: Array = []
var branch_done := false
var duel := {}
var duel_t := 0.0
var mg_played: Array = []
var mg_cycle: Array = []
var takeover := {}  # pid -> true: a human takes this CPU seat after the current turn
var shop_used := false
var game_on := false
var bot_land: Array = []  ## bots: space types to pretend the next landings are ("event", "duel"...)


func _ready() -> void:
	seq = Seq.new()
	seq.name = "Seq"
	add_child(seq)
	rng.randomize()


func _w(seconds: float) -> float:
	return seconds * (0.55 if main.quick else 1.0)


# --- Title ------------------------------------------------------------------------------------------

## Fresh title screen: setup menu, roster with CPU fill.
func begin() -> void:
	seq.clear()
	game_on = false
	var net: Node = main.net
	var turns: int = main.rounds_override if main.rounds_override > 0 else int((net.state_get("settings", {}) as Dictionary).get("turns", 10))
	net.state_set("settings", {"turns": turns, "kid": bool((net.state_get("settings", {}) as Dictionary).get("kid", false))})
	net.state_set("vr", main.vr_rig != null)
	net.state_set("saved", {"parties": int(main.save.data["parties"]), "giant_wins": int(main.save.data["giant_wins"]),
		"best_stars": int(main.save.data["best_stars"])})
	for k in ["menu", "dice", "branch", "duel", "mg", "mg_phase", "mg_result", "ceremony", "results", "final", "steps_left"]:
		net.state_set(k, null)
	net.state_set("cur", -1)
	net.state_set("step", "")
	net.state_set("round", 0)
	net.state_set("sky", "day")
	net.state_set("music", "town")
	_roster()
	net.state_set("star", -1)
	net.state_set("phase", "title")


## Title screen roster: the humans here now, CPUs up to MIN_SEATS.
func _roster() -> void:
	pl.clear()
	var humans: Array[int] = []
	if main.vr_rig != null:
		humans.append(0)
	for s in main.party.active_slots():
		if not humans.has(s):
			humans.append(s)
	for h in humans:
		pl[h] = _new_record(h, false)
	var pid := 0
	while pl.size() < MIN_SEATS and pid < 7:
		if not pl.has(pid):
			pl[pid] = _new_record(pid, true)
		pid += 1
	_publish()


func _new_record(pid: int, cpu: bool) -> Dictionary:
	return {"pid": pid, "name": _name_for(pid, cpu), "cpu": cpu, "coins": Rules.START_COINS, "stars": 0, "items": [],
		"space": 0, "mg_wins": 0, "mg_coins": 0, "events": 0, "max_coins": Rules.START_COINS, "duel_wins": 0,
		"stars_bought": 0, "hops": 0, "items_bought": 0, "sixes": 0, "bonus": []}


func _name_for(pid: int, cpu: bool) -> String:
	if cpu:
		return String(CPU_NAMES[pid % CPU_NAMES.size()])
	if pid == 0 and main.vr_rig != null:
		return "GIANT"
	return main.party.name_of(pid)


func _publish() -> void:
	var arr: Array = []
	var keys: Array = pl.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = pl[k]
		r["max_coins"] = maxi(int(r["max_coins"]), int(r["coins"]))
		arr.append(r)
	main.net.state_set("players", arr)


func on_human_joined(slot: int) -> void:
	var phase := String(main.net.state_get("phase", ""))
	if phase == "title":
		_roster()
		return
	if not game_on:  # the results are up: the next party's roster picks them up
		return
	if pl.has(slot):
		if bool(pl[slot]["cpu"]):
			if int(main.net.state_get("cur", -1)) == slot and String(main.net.state_get("phase", "")) == "board":
				takeover[slot] = true
				main.fx("toast", ["%s takes over from %s next turn!" % [main.party.name_of(slot), String(pl[slot]["name"])], slot, "person"])
			else:
				_take_over(slot)
		return
	if pl.size() >= 7:
		return
	var avg := 0
	for k in pl:
		avg += int(pl[k]["coins"])
	avg = maxi(Rules.START_COINS, avg / maxi(1, pl.size()))
	var r := _new_record(slot, false)
	r["coins"] = avg
	pl[slot] = r
	order.append(slot)
	main.net.state_set("order", order.duplicate())
	_publish()
	main.fx("toast", ["%s joined the party with %d coins!" % [String(r["name"]), avg], slot, "person"])
	main.fx("sfx", ["party_horn", -4.0])


func _take_over(slot: int) -> void:
	var was := String(pl[slot]["name"])
	pl[slot]["cpu"] = false
	pl[slot]["name"] = _name_for(slot, false)
	takeover.erase(slot)
	_publish()
	main.fx("toast", ["%s takes over from %s!" % [String(pl[slot]["name"]), was], slot, "person"])


func on_human_left(slot: int) -> void:
	if String(main.net.state_get("phase", "")) == "title":
		_roster()
		return
	if not game_on:
		return
	if pl.has(slot) and not bool(pl[slot]["cpu"]) and not (slot == 0 and main.vr_rig != null):
		pl[slot]["cpu"] = true
		pl[slot]["name"] = _name_for(slot, true)
		_publish()
		main.fx("toast", ["%s left - %s plays for them" % [main.party.name_of(slot), String(pl[slot]["name"])], slot, "person"])


func _cpu(pid: int) -> bool:
	return bool((pl.get(pid, {}) as Dictionary).get("cpu", true))


# --- Requests ---------------------------------------------------------------------------------------

func on_request(slot: int, action: String, args: Array) -> void:
	var net: Node = main.net
	match action:
		"setup":
			if String(net.state_get("phase", "")) != "title" or args.is_empty():
				return
			var cfg: Dictionary = net.state_get("settings", {})
			match String(args[0]):
				"start":
					start_game()
				"turns":
					var i: int = Rules.TURN_CHOICES.find(int(cfg.get("turns", 10)))
					cfg["turns"] = int(Rules.TURN_CHOICES[(i + 1) % Rules.TURN_CHOICES.size()])
					net.state_set("settings", cfg)
					main.fx("sfx", ["ui_toggle"])
				"kid":
					cfg["kid"] = not bool(cfg.get("kid", false))
					net.state_set("settings", cfg)
					main.fx("sfx", ["ui_toggle"])
		"menu":
			if args.size() >= 2 and int(args[0]) == menu_seq and slot == menu_pid:
				menu_answer = String(args[1])
		"dice_hit":
			var d: Dictionary = net.state_get("dice", {})
			if int(d.get("pid", -1)) == slot and String(d.get("mode", "")) == "tv" and dice_values.size() < dice_n:
				_add_die(_roll_value())
		"branch_sel":
			var br: Dictionary = net.state_get("branch", {})
			if int(br.get("pid", -1)) == slot and not args.is_empty():
				var opts: Array = br.get("options", [])
				br["sel"] = clampi(int(args[0]), 0, opts.size() - 1)
				net.state_set("branch", br)
				main.board.set_arrow_sel(int(br["sel"]))
				main.fx("sfx", ["ui_move", -6.0])
		"branch_go":
			var br2: Dictionary = net.state_get("branch", {})
			if int(br2.get("pid", -1)) == slot and not args.is_empty():
				var opts2: Array = br2.get("options", [])
				br2["sel"] = clampi(int(args[0]), 0, opts2.size() - 1)
				net.state_set("branch", br2)
				branch_done = true
		"duel_hit":
			_duel_hit(slot)
		"again":
			if String(net.state_get("phase", "")) == "results":
				begin()
		_:
			main.runner.on_request(slot, action, args)


# --- Starting a party ------------------------------------------------------------------------------

func start_game() -> void:
	var net: Node = main.net
	var cfg: Dictionary = net.state_get("settings", {})
	rounds = main.rounds_override if main.rounds_override > 0 else int(cfg.get("turns", 10))
	kid = bool(cfg.get("kid", false))
	_roster()
	for k in pl:
		pl[k] = _new_record(int(k), bool(pl[k]["cpu"]))
	order.clear()
	for k in pl:
		order.append(int(k))
	order.shuffle()
	mg_played.clear()
	mg_cycle.clear()
	takeover.clear()
	game_on = true
	round_n = 0
	turn_i = 0
	main.awards = Awards.new()
	for k in pl:
		main.awards.set_player(int(k), String(pl[k]["name"]), main.color_of(int(k)))
	net.state_set("rounds", rounds)
	net.state_set("order", order.duplicate())
	net.state_set("final", false)
	_publish()
	var spots: Array = main.data.star_spots().filter(func(s: int) -> bool: return main.data.distance(0, s) >= 6)
	net.state_set("star", int(spots[rng.randi() % spots.size()]))
	net.state_set("phase", "intro")
	net.state_set("music", "party")
	net.state_set("step", "overview")
	main.fx("sfx", ["party_horn"])
	main.fx("banner", ["LET'S PARTY!", "Collect the most STARS to win!", "victory", 2.6])
	seq.wait(_w(1.0))
	seq.add(func() -> void: main.net.event("intro", []); main.hints.intro(main.INTRO, {"duration": _w(9.0), "min_time": 1.0}))
	seq.until(func() -> bool: return not main.hints.intro_showing(), _w(10.0))
	seq.add(func() -> void:
		main.net.state_set("cur", -1)
		main.net.state_set("step", "star_intro")
		main.fx("banner", ["HERE IS THE STAR!", "Pass it with %d coins to buy it" % Rules.STAR_PRICE, "info", 2.6])
		main.fx("sfx", ["sparkle"]))
	seq.wait(_w(2.6))
	seq.add(func() -> void:
		var names: PackedStringArray = []
		for p in order:
			names.append(String(pl[p]["name"]))
		main.net.state_set("step", "overview")
		main.fx("banner", ["TURN ORDER", " > ".join(names), "default", 2.8])
		main.fx("sfx", ["drumroll", -4.0]))
	seq.wait(_w(2.8))
	seq.add(_start_round)


# --- Rounds and turns ------------------------------------------------------------------------------

func _start_round() -> void:
	var net: Node = main.net
	round_n += 1
	turn_i = 0
	net.state_set("round", round_n)
	net.state_set("phase", "board")
	net.state_set("music", "tension" if bool(net.state_get("final", false)) else "party")
	main.fx("banner", ["ROUND %d" % round_n, "of %d" % rounds, "default", 1.8])
	seq.wait(_w(1.6))
	if rounds >= 5 and round_n == rounds - 2:
		seq.add(func() -> void:
			main.net.state_set("final", true)
			main.net.state_set("music", "tension")
			main.net.state_set("sky", "sunset")
			main.fx("banner", ["FINAL 3 TURNS!", "Blue and red spaces are worth DOUBLE now!", "boss", 3.0]))
		seq.wait(_w(3.0))
	if kid and round_n > 1:
		seq.add(_catch_up)
	seq.add(_next_turn)


## Kid mode: the player in last place gets a few coins.
func _catch_up() -> void:
	var worst := -1
	var ws := 1 << 30
	for k in pl:
		var sc := int(pl[k]["stars"]) * 1000 + int(pl[k]["coins"])
		if sc < ws:
			ws = sc
			worst = int(k)
	if worst >= 0:
		_coins(worst, Rules.CATCH_UP_COINS)
		main.fx("banner", ["CATCH-UP COINS!", "%s gets %d coins. Go go go!" % [String(pl[worst]["name"]), Rules.CATCH_UP_COINS], "level", 2.2])
		seq.wait(_w(2.2))


func _next_turn() -> void:
	if turn_i >= order.size():
		_round_over()
		return
	var pid: int = order[turn_i]
	turn_i += 1
	if not pl.has(pid):
		seq.add(_next_turn)
		return
	_turn(pid)


func _turn(pid: int) -> void:
	var net: Node = main.net
	shop_used = false
	dice_n = 1
	net.state_set("cur", pid)
	net.state_set("step", "start")
	net.state_set("steps_left", 0)
	main.fx("sfx", ["bell", -6.0])
	seq.wait(_w(1.1))
	if not (pl[pid]["items"] as Array).is_empty():
		seq.add(func() -> void: _item_phase(pid))
	seq.add(func() -> void: _roll(pid))
	seq.add(func() -> void: _end_turn(pid))


func _end_turn(pid: int) -> void:
	main.net.state_set("step", "end")
	main.net.state_set("steps_left", 0)
	if takeover.has(pid):
		_take_over(pid)
	seq.wait(_w(0.7))
	seq.add(_next_turn)


func _round_over() -> void:
	main.net.state_set("cur", -1)
	main.net.state_set("step", "overview")
	seq.wait(_w(0.6))
	seq.add(func() -> void: main.runner.start(_pick_minigames(), _after_minigames))


func _after_minigames() -> void:
	if round_n >= rounds:
		seq.add(_game_over)
	else:
		seq.add(_start_round)


## Which minigames to play after this round: forced (PB_MINIGAME), all of them spread over the rounds
## (PB_ALL_MINIGAMES), or a random one not played lately.
func _pick_minigames() -> Array:
	var ids: Array = main.runner.ids()
	if ids.is_empty():
		return []
	if main.mg_force != "" and ids.has(main.mg_force):
		return [main.mg_force]
	if main.mg_all:
		if mg_cycle.is_empty() and mg_played.is_empty():
			mg_cycle = ids.duplicate()
		var left := maxi(1, rounds - round_n + 1)
		var take := int(ceil(float(mg_cycle.size()) / float(left)))
		var out: Array = []
		for i in take:
			if not mg_cycle.is_empty():
				out.append(mg_cycle.pop_front())
		for id in out:
			mg_played.append(id)
		return out if not out.is_empty() else [ids[rng.randi() % ids.size()]]
	var fresh: Array = ids.filter(func(id: String) -> bool: return not mg_played.has(id))
	if fresh.is_empty():
		mg_played.clear()
		fresh = ids.duplicate()
	var pick: String = fresh[rng.randi() % fresh.size()]
	mg_played.append(pick)
	return [pick]


# --- Menus (one player chooses) -------------------------------------------------------------------

## Ask `pid` to choose; CPU players answer with cpu_pick (an id) after a short think.
func _ask(pid: int, title: String, items: Array, cpu_pick: String, kind: String = "") -> void:
	menu_seq += 1
	menu_pid = pid
	menu_answer = ""
	main.net.state_set("step", "menu")
	main.net.state_set("menu", {"seq": menu_seq, "pid": pid, "title": title, "items": items, "kind": kind})
	if _cpu(pid):
		var s := menu_seq
		seq.wait(_w(rng.randf_range(0.9, 1.6)))
		seq.add(func() -> void:
			if menu_seq == s and menu_answer == "":
				menu_answer = cpu_pick)
	seq.until(func() -> bool: return menu_answer != "", 45.0, func() -> void: menu_answer = cpu_pick)
	seq.add(func() -> void: main.net.state_set("menu", {}))


# --- Items -------------------------------------------------------------------------------------------

func _item_phase(pid: int) -> void:
	var items: Array = pl[pid]["items"]
	var list: Array = []
	for it in items:
		var info: Dictionary = Rules.ITEMS.get(String(it), {})
		list.append({"id": String(it), "text": "USE " + String(info.get("name", it)), "icon": String(info.get("icon", "bag")),
			"desc": String(info.get("desc", "")), "icon_color": info.get("color", Color.WHITE)})
	list.append({"id": "roll", "text": "JUST ROLL THE DICE", "icon": "play", "desc": "Keep your items for later."})
	_ask(pid, "YOUR ITEMS", list, _cpu_item(pid), "items")
	seq.add(func() -> void: _use_item(pid, menu_answer))


func _cpu_item(pid: int) -> String:
	var items: Array = pl[pid]["items"]
	var star := int(main.net.state_get("star", 0))
	var dist: int = main.data.distance(int(pl[pid]["space"]), star)
	if items.has("pipe") and dist > 7:
		return "pipe"
	if items.has("double") and dist > 3:
		return "double"
	if items.has("steal") and _richest_other(pid) >= 0 and int(pl[_richest_other(pid)]["coins"]) >= 8:
		return "steal"
	if items.has("swap"):
		for k in pl:
			if int(k) != pid and main.data.distance(int(pl[k]["space"]), star) + 4 < dist:
				return "swap"
	return "roll"


func _richest_other(pid: int) -> int:
	var best := -1
	var bc := -1
	for k in pl:
		if int(k) != pid and int(pl[k]["coins"]) > bc:
			bc = int(pl[k]["coins"])
			best = int(k)
	return best


func _use_item(pid: int, id: String) -> void:
	if id == "roll" or not (pl[pid]["items"] as Array).has(id):
		return
	(pl[pid]["items"] as Array).erase(id)
	_publish()
	main.net.state_set("step", "item")
	main.fx("banner", [Rules.item_name(id) + "!", String((Rules.ITEMS[id] as Dictionary)["desc"]), "info", 2.0])
	main.fx("sfx", ["power_up", -3.0])
	seq.wait(_w(1.2))
	match id:
		"double":
			dice_n = 2
		"pipe":
			seq.add(func() -> void:
				var star := int(main.net.state_get("star", 0))
				var before: Array = main.data.prev_of(star)
				var to := int(before[0]) if not before.is_empty() else star
				_move_to(pid, to)
				main.fx("sfx", ["warp"]))
			seq.wait(_w(1.6))
		"steal", "swap":
			var others: Array = []
			for k in pl:
				if int(k) != pid:
					others.append({"id": str(k), "text": String(pl[k]["name"]), "right": "%d COINS" % int(pl[k]["coins"]),
						"icon": "person", "icon_color": main.color_of(int(k))})
			var cpu_pick := str(_richest_other(pid)) if id == "steal" else str(_closest_to_star(pid))
			_ask(pid, "STEAL FROM WHO?" if id == "steal" else "SWAP WITH WHO?", others, cpu_pick, "target")
			seq.add(func() -> void:
				var target := int(menu_answer)
				if not pl.has(target):
					return
				if id == "steal":
					var n := mini(5, int(pl[target]["coins"]))
					_coins(target, -n)
					_coins(pid, n)
					main.fx("banner", ["SNEAKY!", "%s took %d coins from %s" % [String(pl[pid]["name"]), n, String(pl[target]["name"])], "default", 2.0])
				else:
					_swap_places(pid, target))
			seq.wait(_w(1.8))


func _closest_to_star(pid: int) -> int:
	var star := int(main.net.state_get("star", 0))
	var best := -1
	var bd := 9999
	for k in pl:
		if int(k) == pid:
			continue
		var d: int = main.data.distance(int(pl[k]["space"]), star)
		if d < bd:
			bd = d
			best = int(k)
	return best


func _swap_places(a: int, b: int) -> void:
	var sa := int(pl[a]["space"])
	pl[a]["space"] = int(pl[b]["space"])
	pl[b]["space"] = sa
	_publish()
	main.fx("sfx", ["teleport"])
	main.fx("banner", ["SWAP!", "%s and %s swap places!" % [String(pl[a]["name"]), String(pl[b]["name"])], "info", 2.0])


func _move_to(pid: int, space: int) -> void:
	pl[pid]["space"] = space
	_publish()


# --- Dice ----------------------------------------------------------------------------------------

func _roll_value() -> int:
	return rng.randi_range(1, 6)


func _roll(pid: int) -> void:
	var net: Node = main.net
	dice_id += 1
	dice_values = []
	var mode := "cpu" if _cpu(pid) else ("vr" if main.is_local_vr(pid) else "tv")
	net.state_set("dice", {"id": dice_id, "pid": pid, "n": dice_n, "mode": mode, "values": []})
	net.state_set("step", "roll")
	if mode == "cpu":
		for i in dice_n:
			seq.wait(_w(rng.randf_range(0.8, 1.3)))
			seq.add(func() -> void: _add_die(_roll_value()))
	elif mode == "tv":
		seq.until(func() -> bool: return dice_values.size() >= dice_n, 30.0, func() -> void:
			while dice_values.size() < dice_n:
				_add_die(_roll_value()))
	else:
		seq.until(func() -> bool: return dice_values.size() >= dice_n, 60.0, func() -> void:
			while dice_values.size() < dice_n:
				_add_die(_roll_value()))
	seq.wait(_w(0.9))
	seq.add(func() -> void: _start_move(pid))


func _add_die(v: int) -> void:
	dice_values.append(v)
	var d: Dictionary = main.net.state_get("dice", {})
	d["values"] = dice_values.duplicate()
	main.net.state_set("dice", d)
	main.fx("sfx", ["dice", -2.0])
	var pid := int(d.get("pid", -1))
	if v == 6 and pl.has(pid):
		pl[pid]["sixes"] = int(pl[pid]["sixes"]) + 1
		main.awards.add(pid, "sixes")


## Host, VR: the physical dice came to rest (dice.gd).
func on_vr_dice(id: int, values: Array) -> void:
	if id != dice_id:
		return
	for v in values:
		if dice_values.size() < dice_n:
			_add_die(int(v))


# --- Moving ------------------------------------------------------------------------------------------

func _start_move(pid: int) -> void:
	var total := 0
	for v in dice_values:
		total += int(v)
	if dice_n == 2 and dice_values.size() == 2 and int(dice_values[0]) == int(dice_values[1]):
		total += 5
		main.fx("banner", ["DOUBLES!", "+5 bonus steps... no wait, +5 coins!", "level", 1.8])
		_coins(pid, 5)
		total -= 5
	main.net.state_set("dice", {})
	main.net.state_set("steps_left", total)
	main.net.state_set("step", "move")
	seq.add(func() -> void: _hop(pid))


func _hop(pid: int) -> void:
	var net: Node = main.net
	var left := int(net.state_get("steps_left", 0))
	if left <= 0:
		seq.add(func() -> void: _land(pid))
		return
	var here := int(pl[pid]["space"])
	var options: Array = main.data.next_of(here)
	if options.size() > 1:
		_choose_branch(pid, here, options)
		seq.add(func() -> void:
			var br: Dictionary = main.net.state_get("branch", {})
			var to := int(options[clampi(int(br.get("sel", 0)), 0, options.size() - 1)])
			main.net.state_set("branch", {})
			main.board.hide_arrows()
			main.net.event("arrows", [])
			main.net.state_set("step", "move")
			_hop_to(pid, to))
	else:
		_hop_to(pid, int(options[0]))


func _hop_to(pid: int, to: int) -> void:
	var net: Node = main.net
	pl[pid]["space"] = to
	pl[pid]["hops"] = int(pl[pid]["hops"]) + 1
	_publish()
	var left := int(net.state_get("steps_left", 0)) - 1
	net.state_set("steps_left", left)
	seq.wait(_w(0.36))
	var star := int(net.state_get("star", -1))
	if to == star:
		seq.add(func() -> void: _star_offer(pid))
	elif main.data.type_of(to) == "shop" and left > 0 and not shop_used:
		seq.add(func() -> void: _shop(pid, true))
	seq.add(func() -> void: _hop(pid))


func _choose_branch(pid: int, here: int, options: Array) -> void:
	var net: Node = main.net
	branch_done = false
	var star := int(net.state_get("star", 0))
	var best := 0
	var bd := 9999
	for i in options.size():
		var d: int = main.data.distance(int(options[i]), star)
		if d < bd:
			bd = d
			best = i
	net.state_set("branch", {"pid": pid, "from": here, "options": options.duplicate(), "sel": 0})
	net.state_set("step", "branch")
	main.board.show_arrows(here, options, 0)
	net.event("arrows", [here, options])
	main.fx("sfx", ["ui_open", -4.0])
	if _cpu(pid):
		seq.wait(_w(0.7))
		seq.add(func() -> void:
			on_request(pid, "branch_sel", [best]))
		seq.wait(_w(0.6))
		seq.add(func() -> void: branch_done = true)
	seq.until(func() -> bool: return branch_done, 40.0, func() -> void: branch_done = true)


# --- Star and shop ------------------------------------------------------------------------------------

func _star_offer(pid: int) -> void:
	var coins := int(pl[pid]["coins"])
	if coins < Rules.STAR_PRICE:
		main.fx("banner", ["THE STAR!", "You need %d coins... come back richer!" % Rules.STAR_PRICE, "info", 2.0])
		main.fx("sfx", ["crowd_oh", -6.0])
		seq.wait(_w(2.0))
		return
	main.net.state_set("music", "shop")
	_ask(pid, "BUY THE STAR?", [{"id": "yes", "text": "YES! (%d COINS)" % Rules.STAR_PRICE, "icon": "star", "icon_color": Color(1, 0.85, 0.3)},
		{"id": "no", "text": "NO THANKS", "icon": "cross"}], "yes", "star")
	seq.add(func() -> void:
		main.net.state_set("music", "tension" if bool(main.net.state_get("final", false)) else "party")
		if menu_answer != "yes":
			return
		_coins(pid, -Rules.STAR_PRICE)
		pl[pid]["stars"] = int(pl[pid]["stars"]) + 1
		pl[pid]["stars_bought"] = int(pl[pid]["stars_bought"]) + 1
		_publish()
		main.fx("star_fx", [pid, 1])
		main.fx("banner", ["%s GOT A STAR!" % String(pl[pid]["name"]), "", "victory", 2.6])
		seq.wait(_w(2.8))
		seq.add(_move_star))


func _move_star() -> void:
	var cur := int(main.net.state_get("star", -1))
	var spots: Array = main.data.star_spots().filter(func(s: int) -> bool: return s != cur and main.data.distance(cur, s) >= 5 and main.data.distance(s, cur) >= 5)
	if spots.is_empty():
		spots = main.data.star_spots().filter(func(s: int) -> bool: return s != cur)
	var to := int(spots[rng.randi() % spots.size()])
	main.net.state_set("star", to)
	main.net.state_set("step", "star_move")
	main.fx("sfx", ["whoosh"])
	main.fx("banner", ["THE STAR FLEW AWAY!", "Find it at its new spot!", "info", 2.0])
	seq.wait(_w(2.2))
	seq.add(func() -> void: main.net.state_set("step", "move"))


func _shop(pid: int, passing: bool) -> void:
	var coins := int(pl[pid]["coins"])
	var items: Array = pl[pid]["items"]
	var cheapest := 99
	for id in Rules.ITEMS:
		cheapest = mini(cheapest, Rules.item_price(String(id)))
	if coins < cheapest or items.size() >= Rules.MAX_ITEMS:
		if not passing:
			main.fx("banner", ["ITEM SHOP", "Bag full!" if items.size() >= Rules.MAX_ITEMS else "Not enough coins... next time!", "info", 1.8])
			seq.wait(_w(1.8))
		return
	shop_used = true
	main.net.state_set("music", "shop")
	var list: Array = []
	for id in Rules.ITEM_ORDER:
		var info: Dictionary = Rules.ITEMS[id]
		var price := int(info["price"])
		list.append({"id": String(id), "text": String(info["name"]), "right": "%d COINS" % price, "icon": String(info["icon"]),
			"icon_color": info["color"], "desc": String(info["desc"]), "disabled": price > coins, "reason": "Not enough coins"})
	list.append({"id": "leave", "text": "NO THANKS", "icon": "cross", "desc": "Keep your coins."})
	_ask(pid, "ITEM SHOP  -  %d COINS" % coins, list, _cpu_shop(pid), "shop")
	seq.add(func() -> void:
		main.net.state_set("music", "tension" if bool(main.net.state_get("final", false)) else "party")
		var id := menu_answer
		if not Rules.ITEMS.has(id) or Rules.item_price(id) > int(pl[pid]["coins"]):
			return
		_coins(pid, -Rules.item_price(id))
		(pl[pid]["items"] as Array).append(id)
		pl[pid]["items_bought"] = int(pl[pid]["items_bought"]) + 1
		_publish()
		main.fx("sfx", ["kaching"])
		main.fx("toast", ["%s bought %s!" % [String(pl[pid]["name"]), Rules.item_name(id)], pid, "bag"]))


func _cpu_shop(pid: int) -> String:
	var coins := int(pl[pid]["coins"])
	if coins >= Rules.STAR_PRICE + 5 and rng.randf() < 0.5:
		return "double"
	if coins >= 15 + 10 and rng.randf() < 0.5:
		return "pipe"
	if coins >= 12:
		return ["double", "steal", "swap"][rng.randi() % 3]
	return "leave"


# --- Landing -----------------------------------------------------------------------------------------

func _land(pid: int) -> void:
	var net: Node = main.net
	var sp := int(pl[pid]["space"])
	var type: String = main.data.type_of(sp)
	if not bot_land.is_empty():
		type = String(bot_land.pop_front())
	var mult := 2 if bool(net.state_get("final", false)) else 1
	net.state_set("step", "land")
	match type:
		"blue", "start":
			_coins(pid, Rules.BLUE_COINS * mult)
			main.fx("space_fx", [sp, Color(0.4, 0.7, 1.0)])
		"red":
			_coins(pid, -(Rules.RED_COINS_KID if kid else Rules.RED_COINS) * mult)
			main.fx("space_fx", [sp, Color(1.0, 0.35, 0.35)])
		"event":
			main.fx("space_fx", [sp, Color(0.4, 1.0, 0.5)])
			seq.add(func() -> void: _event(pid))
		"shop":
			main.fx("space_fx", [sp, Color(1.0, 0.75, 0.3)])
			if not shop_used:
				seq.add(func() -> void: _shop(pid, false))
		"duel":
			main.fx("space_fx", [sp, Color(0.75, 0.5, 1.0)])
			seq.add(func() -> void: _duel_start(pid))
	seq.wait(_w(0.9))


func _coins(pid: int, n: int) -> void:
	if not pl.has(pid) or n == 0:
		return
	var before := int(pl[pid]["coins"])
	var after := maxi(0, before + n)
	pl[pid]["coins"] = after
	_publish()
	if after != before:
		main.fx("coins", [pid, after - before])
		if after > before:
			main.awards.add(pid, "coins", after - before)


# --- Events ------------------------------------------------------------------------------------------

func _event(pid: int) -> void:
	var net: Node = main.net
	var sp := int(pl[pid]["space"])
	var zone := String((main.data.spaces[sp] as Dictionary)["zone"])
	var ev := Rules.pick_event(zone, rng)
	pl[pid]["events"] = int(pl[pid]["events"]) + 1
	main.awards.add(pid, "events")
	net.state_set("step", "event")
	main.fx("sfx", ["reveal"])
	var info: Dictionary = Rules.EVENTS[ev]
	main.fx("banner", [String(info["title"]), String(info["text"]), "level", 2.6])
	seq.wait(_w(2.0))
	match ev:
		"coin_rain":
			seq.add(func() -> void:
				for k in pl:
					_coins(int(k), 6 if int(k) == pid else 2)
				main.fx("sfx", ["kaching"]))
		"party":
			seq.add(func() -> void:
				for k in pl:
					_coins(int(k), 3)
					main.fx("anim", [int(k), "cheer", 1.2])
				main.fx("sfx", ["party_horn"]))
		"treasure":
			seq.add(func() -> void:
				main.fx("sfx", ["chest"])
				_coins(pid, rng.randi_range(4, 12)))
		"gift":
			seq.add(func() -> void:
				var items: Array = pl[pid]["items"]
				if items.size() < Rules.MAX_ITEMS:
					var id: String = Rules.ITEM_ORDER[rng.randi() % Rules.ITEM_ORDER.size()]
					items.append(id)
					_publish()
					main.fx("toast", ["%s got a %s!" % [String(pl[pid]["name"]), Rules.item_name(id)], pid, "bag"])
					main.fx("sfx", ["achievement"])
				else:
					_coins(pid, 5))
		"dragon":
			seq.add(func() -> void:
				var star := int(main.net.state_get("star", 0))
				var before: Array = main.data.prev_of(star)
				_move_to(pid, int(before[0]) if not before.is_empty() else star)
				main.fx("sfx", ["whoosh"]))
			seq.wait(_w(1.6))
		"whirlwind":
			seq.add(func() -> void:
				var others: Array = pl.keys().filter(func(k: int) -> bool: return k != pid)
				if not others.is_empty():
					_swap_places(pid, int(others[rng.randi() % others.size()])))
			seq.wait(_w(1.4))
		"star_shuffle":
			seq.add(_move_star)
		"volcano":
			seq.add(func() -> void:
				var hit := 0
				main.fx("shake", [0.6])
				main.fx("sfx", ["explosion", -4.0])
				for k in pl:
					var s := int(pl[k]["space"])
					if s >= BD.RING and s < BD.RING + BD.TRAIL_POINTS.size():
						_coins(int(k), -(1 if kid else 3))
						hit += 1
				if hit == 0:
					main.fx("toast", ["Nobody was on the trail. Phew!", -1, "fire"]))
	seq.wait(_w(1.2))


# --- Duel: Quick Draw ---------------------------------------------------------------------------------

func _duel_start(pid: int) -> void:
	var others: Array = []
	for k in pl:
		if int(k) != pid:
			others.append({"id": str(k), "text": String(pl[k]["name"]), "right": "%d COINS" % int(pl[k]["coins"]),
				"icon": "person", "icon_color": main.color_of(int(k))})
	main.fx("banner", ["DUEL!", "Pick someone for a QUICK DRAW!", "boss", 1.8])
	seq.wait(_w(1.2))
	_ask(pid, "DUEL WHO?", others, str(_richest_other(pid)), "duel")
	seq.add(func() -> void:
		var b := int(menu_answer)
		if not pl.has(b):
			return
		duel = {"a": pid, "b": b, "phase": "ready", "winner": -1, "foul": -1}
		main.net.state_set("duel", duel.duplicate())
		main.net.state_set("step", "duel")
		main.fx("banner", ["QUICK DRAW!", "Wait for DRAW... then press A / pull the TRIGGER first!", "boss", 2.6])
		duel_t = 0.0)
	seq.wait(_w(2.4) + rng.randf_range(1.0, 2.6))
	seq.add(func() -> void:
		if duel.is_empty() or int(duel.get("winner", -1)) >= 0:
			return
		duel["phase"] = "draw"
		main.net.state_set("duel", duel.duplicate())
		main.fx("banner", ["DRAW!", "", "victory", 1.0])
		main.fx("sfx", ["buzzer"])
		for who in [int(duel["a"]), int(duel["b"])]:
			if _cpu(who):
				var react := rng.randf_range(0.6, 1.25) if kid else rng.randf_range(0.38, 0.95)
				var w: int = who
				get_tree().create_timer(react, false).timeout.connect(func() -> void: _duel_hit(w)))
	seq.until(func() -> bool: return duel.is_empty() or int(duel.get("winner", -1)) >= 0, 6.0, func() -> void:
		if not duel.is_empty():
			_duel_hit(int(duel["a"]) if rng.randf() < 0.5 else int(duel["b"])))
	seq.add(_duel_end)


func _duel_hit(slot: int) -> void:
	if duel.is_empty() or int(duel.get("winner", -1)) >= 0:
		return
	if slot != int(duel["a"]) and slot != int(duel["b"]):
		return
	var other := int(duel["b"]) if slot == int(duel["a"]) else int(duel["a"])
	if String(duel["phase"]) == "ready":
		duel["winner"] = other
		duel["foul"] = slot
	else:
		duel["winner"] = slot
	main.net.state_set("duel", duel.duplicate())


func _duel_end() -> void:
	if duel.is_empty():
		return
	var w := int(duel["winner"])
	var l := int(duel["b"]) if w == int(duel["a"]) else int(duel["a"])
	var foul := int(duel.get("foul", -1))
	main.fx("sfx", ["sword_hit"])
	main.fx("anim", [w, "victory", 1.6])
	main.fx("anim", [l, "hurt", 0.6])
	var sub := ("%s pressed too early!" % String(pl[foul]["name"])) if foul >= 0 else "Fastest hands on the island!"
	main.fx("banner", ["%s WINS THE DUEL!" % String(pl[w]["name"]), sub, "victory", 2.4])
	pl[w]["duel_wins"] = int(pl[w]["duel_wins"]) + 1
	main.awards.add(w, "duel_wins")
	if kid:
		_coins(w, Rules.DUEL_STAKE)
	else:
		var n := mini(Rules.DUEL_STAKE, int(pl[l]["coins"]))
		_coins(l, -n)
		_coins(w, maxi(n, 2))
	duel = {}
	main.net.state_set("duel", {})
	seq.wait(_w(2.4))
	seq.add(func() -> void: main.net.state_set("step", "land"))


## Bots: put the STAR one hop ahead of `pid` and give them enough coins to buy it.
func bot_star_ahead(pid: int) -> void:
	if not pl.has(pid):
		return
	var ahead: Array = main.data.next_of(int(pl[pid]["space"]))
	pl[pid]["coins"] = maxi(int(pl[pid]["coins"]), Rules.STAR_PRICE + 8)
	_publish()
	main.net.state_set("star", int(ahead[0]))


# --- Minigame coins (mg_runner.gd calls these) ----------------------------------------------------------

func give_minigame_coins(rows: Array) -> void:
	for r in rows:
		var rd: Dictionary = r
		var pid := int(rd["pid"])
		if not pl.has(pid):
			continue
		var c := int(rd.get("coins", 0))
		_coins(pid, c)
		pl[pid]["mg_coins"] = int(pl[pid]["mg_coins"]) + c
		if bool(rd.get("win", false)):
			pl[pid]["mg_wins"] = int(pl[pid]["mg_wins"]) + 1
			main.awards.add(pid, "mg_wins")
	_publish()


func is_kid() -> bool:
	return kid


# --- The end ------------------------------------------------------------------------------------------

func _game_over() -> void:
	main.ceremony_start(pl.duplicate(true))


## The ceremony gave out bonus stars (ceremony flow calls this).
func add_bonus_star(pid: int, why: String) -> void:
	if not pl.has(pid):
		return
	pl[pid]["stars"] = int(pl[pid]["stars"]) + 1
	(pl[pid]["bonus"] as Array).append(why)
	_publish()


func record(pid: int) -> Dictionary:
	return pl.get(pid, {})


func finish_game(winners: Array) -> void:
	game_on = false
	var sd: Dictionary = main.save.data
	sd["parties"] = int(sd["parties"]) + 1
	var wins: Dictionary = sd["wins"]
	for w in winners:
		var nm := String(pl[int(w)]["name"])
		wins[nm] = int(wins.get(nm, 0)) + 1
		if int(w) == 0 and main.vr_rig != null:
			sd["giant_wins"] = int(sd["giant_wins"]) + 1
	for k in pl:
		sd["best_stars"] = maxi(int(sd["best_stars"]), int(pl[k]["stars"]))
		sd["most_coins"] = maxi(int(sd["most_coins"]), int(pl[k]["max_coins"]))
	var played: Dictionary = sd["mg_played"]
	for id in mg_played:
		played[String(id)] = int(played.get(String(id), 0)) + 1
	main.save.mark_dirty()
