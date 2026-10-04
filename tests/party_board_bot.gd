extends Node
## Headless bot for games/party_board: plays a short party (3 rounds) to the results screen.
## TV seats (BOT_PLAYERS, default 2) drop in with virtual pads, start the party from the setup menu,
## stop their dice blocks with A, choose in menus, pick branches, duel, get READY and play every
## minigame with their sticks. BOT_VR=1 (local / host): a fake VR player throws the physical dice with
## its right glove, picks from VR menus and plays the minigames with its gloves.
## The host forces a few landings (event, shop, duel, red, blue) and puts the STAR in reach so every
## space type, the shop and the star purchase happen. PB_MINIGAME=<id> / PB_ALL_MINIGAMES=1 pick the
## minigames (main.gd reads them). PB_ROUNDS overrides the 3 rounds.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 12000 res://tests/party_board_bot.tscn
## Networked: DUO_PORT=8030 DUO_HOST=1 ... & DUO_PORT=8030 DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")

var kit: BotKit
var main: Node
var want := 2
var host := false
var client := false
var seen := {}  # "step:event", "menu:shop", "mg:coin_catch", "phase:results"...
var _menu_t := 0.0
var _vr_phase := ""  # fake VR dice throw: "" / "reach" / "carry"
var _vr_t := 0.0
var _star_rigged := false
var _press_t := {}  # slot -> next time this seat may press A
var _finish_at := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	kit.verbose = false
	main = load("res://games/party_board/main.tscn").instantiate()
	main.set("rounds_override", int(OS.get_environment("PB_ROUNDS")) if OS.has_environment("PB_ROUNDS") else 3)
	main.set("quick", true)
	main.set("mg_time_scale", 0.4)
	add_child(main)
	kit.main = main
	main.net.state_changed.connect(_on_state)
	want = BotKit.bot_players(2, 6)
	client = OS.has_environment("DUO_JOIN")
	host = OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	kit.at(t0 + 4.0, "start the party", _start)
	if host:
		kit.at(t0 + 14.0, "host: start anyway if the TV machine didn't", _start_direct)
	kit.every(3.0, _report)
	kit.every(0.1, _watch)


func _join() -> void:
	if main.net.mode == "host":
		return
	for i in want:
		kit.join_bot(main.party)


func _start() -> void:
	if String(main.net.state_get("phase", "")) != "title":
		return
	if main.flow != null:
		main.flow.bot_land = ["shop", "event", "duel", "red", "blue", "event", "event"]
	var seats: Array[int] = main.party.local_slots()
	if main.menus.setup_tv != null and is_instance_valid(main.menus.setup_tv):
		kit.assert_true(String(main.menus.setup_tv.focused_id()) == "start", "the setup menu opens on START")
		kit.slot_press(main.party, main.menus.setup_tv_slot, "accept")
	elif main.vr_rig != null and main.menus.setup_vr != null and is_instance_valid(main.menus.setup_vr):
		main.menus.setup_vr.confirm(0)
	elif not seats.is_empty() or main.flow != null:
		main.net.request(seats[0] if not seats.is_empty() else 0, "setup", ["start"])


func _start_direct() -> void:
	if main.flow != null and String(main.net.state_get("phase", "")) == "title":
		main.flow.bot_land = ["shop", "event", "duel", "red", "blue", "event", "event"]
		main.flow.on_request(0, "setup", ["start"])


## Record every replicated step, menu and phase as it happens.
func _on_state(key: String, value: Variant) -> void:
	match key:
		"phase", "step":
			seen[key + ":" + String(value if value != null else "")] = true
		"menu":
			if value is Dictionary and not (value as Dictionary).is_empty():
				seen["menu:" + String((value as Dictionary).get("kind", ""))] = true


## Record what happened and finish once the results are up.
func _watch() -> String:
	var phase := String(main.net.state_get("phase", ""))
	seen["phase:" + phase] = true
	seen["step:" + String(main.net.state_get("step", ""))] = true
	var m: Dictionary = main.net.state_get("menu", {}) if main.net.state_get("menu", {}) is Dictionary else {}
	if not m.is_empty():
		seen["menu:" + String(m.get("kind", ""))] = true
	var mg: Dictionary = main.net.state_get("mg", {}) if main.net.state_get("mg", {}) is Dictionary else {}
	if not mg.is_empty():
		seen["mg:" + String(mg.get("id", ""))] = true
		if String(main.net.state_get("mg_phase", "")) == "result" and not seen.has("res:%d" % int(mg.get("n", 0))):
			seen["res:%d" % int(mg.get("n", 0))] = true
			var res: Dictionary = main.net.state_get("mg_result", {})
			var parts: PackedStringArray = []
			for r in res.get("rows", []):
				parts.append("%s=%d(+%d)" % [main.name_of(int(r["pid"])), int(r["score"]), int(r["coins"])])
			kit.info("%s: %s  %s" % [String(mg.get("id", "")), String(res.get("title", "")), " ".join(parts)])
	if main.flow != null and not _star_rigged and phase == "board" and String(main.net.state_get("step", "")) == "roll" \
			and int(main.net.state_get("round", 0)) >= 1 and seen.has("menu:shop"):
		_star_rigged = true
		main.flow.bot_star_ahead(int(main.net.state_get("cur", 0)))
	if phase == "results" and _finish_at < 0.0:
		_finish_at = kit.t + (6.0 if host else 5.0)
		kit.info("results are up")
	if _finish_at > 0.0 and kit.t >= _finish_at and _finish_at < 1e8:
		_checks()
		if main.net.mode == "local":
			# PLAY AGAIN from the results screen goes back to the title / setup menu.
			_finish_at = 2e9
			var seats: Array[int] = main.party.local_slots()
			if main.ceremony.results_ui != null and not seats.is_empty():
				kit.slot_press(main.party, seats[0], "accept")
			else:
				main.net.request(0, "again", [])
			kit.at(kit.t + 3.0, "back at the title?", func() -> void:
				kit.assert_eq(String(main.net.state_get("phase", "")), "title", "PLAY AGAIN goes back to the title")
				kit.finish())
		else:
			_finish_at = 1e9
			kit.finish()
	return ""


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or get_tree().paused:
		return
	for slot in main.party.local_slots():
		if slot == 0 and main.vr_rig != null:
			continue
		_drive_tv(slot)
	if main.vr_rig != null:
		_drive_vr(delta)


func _may_press(slot: int, gap: float = 0.5) -> bool:
	if kit.t < float(_press_t.get(slot, 0.0)):
		return false
	_press_t[slot] = kit.t + gap
	return true


## A TV seat: dice, menus, branches, duels, minigames.
func _drive_tv(slot: int) -> void:
	var phase := String(main.net.state_get("phase", ""))
	var step := String(main.net.state_get("step", ""))
	var party: Node = main.party
	if phase == "board":
		kit.slot_stick(party, slot, "left", Vector2.ZERO)
		if step == "roll":
			var d: Dictionary = main.net.state_get("dice", {})
			if int(d.get("pid", -1)) == slot and _may_press(slot, 0.7):
				kit.slot_press(party, slot, "accept")
		elif step == "menu":
			var tm = main.menus.tv_menu
			if tm != null and is_instance_valid(tm) and int((main.net.state_get("menu", {}) as Dictionary).get("pid", -1)) == slot:
				if _may_press(slot, 0.8):
					var items: Array = tm.items
					var pick := 0
					while pick < items.size() and bool((items[pick] as Dictionary).get("disabled", false)):
						pick += 1
					if pick == 0:
						kit.slot_press(party, slot, "accept")
					else:
						tm.confirm(mini(pick, items.size() - 1))
		elif step == "branch":
			var br: Dictionary = main.net.state_get("branch", {})
			if int(br.get("pid", -1)) == slot and _may_press(slot, 0.8):
				kit.slot_press(party, slot, "accept")
		elif step == "duel":
			var du: Dictionary = main.net.state_get("duel", {})
			if String(du.get("phase", "")) == "draw" and (int(du.get("a", -1)) == slot or int(du.get("b", -1)) == slot) and _may_press(slot, 0.3):
				kit.slot_press(party, slot, "accept")
	elif phase == "minigame":
		var mph := String(main.net.state_get("mg_phase", ""))
		if mph == "howto":
			if _may_press(slot, 1.0):
				kit.slot_press(party, slot, "accept")
		var mg: Node = main.runner.mg
		if mg == null or not is_instance_valid(mg) or mph != "play" and mph != "howto":
			kit.slot_stick(party, slot, "left", Vector2.ZERO)
			return
		# Steer like a CPU would (the minigame knows where a good spot is).
		var goal: Vector3 = mg.cpu_move(slot)
		var at: Vector3 = mg.where(slot)
		var dv := goal - at
		dv.y = 0.0
		var v := Vector2.ZERO
		if dv.length() > 0.3:
			dv = dv.normalized()
			v = Vector2(-dv.x, -dv.z)  # main.tv_dir: board = (-x, 0, -y)
		kit.slot_stick(party, slot, "left", v)
		if mph == "play" and mg.cpu_press(slot) and _may_press(slot, 0.12):
			kit.slot_press(party, slot, "accept")


## The fake VR player.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	rig.camera.position.y = 1.55
	kit.vr_stick(rig, Vector2.ZERO)
	var phase := String(main.net.state_get("phase", ""))
	var step := String(main.net.state_get("step", ""))
	var vm = main.menus.vr_menu
	if vm != null and is_instance_valid(vm):
		_menu_t += delta
		if _menu_t > 0.8:
			_menu_t = 0.0
			var pick := 0
			while pick < vm.items.size() and bool((vm.items[pick] as Dictionary).get("disabled", false)):
				pick += 1
			vm.confirm(mini(pick, vm.items.size() - 1))
		return
	_menu_t = 0.0
	if phase == "board" and step == "roll" and int((main.net.state_get("dice", {}) as Dictionary).get("pid", -1)) == 0:
		_throw_dice(rig, delta)
		return
	if _vr_phase != "":
		_vr_phase = ""
		kit.vr_trigger(rig, 0.0)
	if phase == "board" and step == "branch" and int((main.net.state_get("branch", {}) as Dictionary).get("pid", -1)) == 0:
		if _may_press(100, 1.0):
			main.net.request(0, "branch_go", [0])
		return
	if phase == "board" and step == "duel":
		var du: Dictionary = main.net.state_get("duel", {})
		if String(du.get("phase", "")) == "draw" and (int(du.get("a", -1)) == 0 or int(du.get("b", -1)) == 0):
			kit.vr_trigger(rig, 1.0 if fmod(kit.t, 0.4) < 0.2 else 0.0)
		return
	if phase == "minigame":
		var mph := String(main.net.state_get("mg_phase", ""))
		if mph == "howto":
			kit.vr_trigger(rig, 1.0 if fmod(kit.t, 0.6) < 0.3 else 0.0)
		var mg: Node = main.runner.mg
		if mg != null and is_instance_valid(mg) and (mph == "play" or mph == "howto"):
			var g: Vector3 = mg.bot_vr_goal()
			if g != Vector3.INF:
				kit.vr_reach(rig, 1, mg.to_global(g), 1.6, delta)
			if mph == "play":
				kit.vr_trigger(rig, 1.0 if fmod(kit.t, 0.5) < 0.25 else 0.0)
		return
	if phase == "results":
		kit.vr_trigger(rig, 0.0)


## Grab a die off its pedestal with the right glove, swing towards the island, let go.
func _throw_dice(rig: Node, delta: float) -> void:
	var dice: Node = main.dice
	_vr_t += delta
	match _vr_phase:
		"":
			if dice.vr_waiting():
				_vr_phase = "reach"
				_vr_t = 0.0
				kit.vr_trigger(rig, 0.0)
		"reach":
			var target := Vector3.INF
			for i in dice.vr_dice.size():
				if dice._released_t[i] < 0.0:
					target = dice.pedestal(i)
					break
			if target == Vector3.INF:
				_vr_phase = ""
				return
			if kit.vr_reach(rig, 1, target, 1.5, delta) or _vr_t > 3.0:
				kit.vr_trigger(rig, 1.0)
				if dice._held >= 0:
					seen["vr:grab"] = true
					_vr_phase = "carry"
					_vr_t = 0.0
		"carry":
			var to: Vector3 = main.to_world(Vector3(0, 3.0, 2.0))
			kit.vr_reach(rig, 1, to, 2.2, delta)
			if _vr_t > 0.35:
				kit.vr_trigger(rig, 0.0)
				seen["vr:throw"] = true
				_vr_phase = ""


func _report() -> String:
	var ps: PackedStringArray = []
	for p in main.roster():
		var pd: Dictionary = p
		ps.append("%s %d*/%dc" % [String(pd["name"]), int(pd["stars"]), int(pd["coins"])])
	return "BOT %s: %s r%d %s/%s mg=%s | %s" % [main.net.mode, String(main.net.state_get("phase", "")), int(main.net.state_get("round", 0)),
		String(main.net.state_get("step", "")), String(main.net.state_get("mg_phase", "")),
		String((main.net.state_get("mg", {}) as Dictionary).get("id", "-")) if main.net.state_get("mg", {}) is Dictionary else "-", ", ".join(ps)]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(seen.has("phase:results"), "%s: the party reached the results screen" % mode)
	kit.assert_true(main.roster().size() >= 4, "%s: at least 4 players (CPUs fill up)" % mode)
	for s in ["step:roll", "step:move", "step:land", "phase:minigame"]:
		kit.assert_true(seen.has(s), "%s: saw %s" % [mode, s])
	if mode != "client":
		for s in ["step:event", "step:duel", "menu:shop", "menu:duel"]:
			kit.assert_true(seen.has(s), "%s: saw %s" % [mode, s])
		var bought := 0
		for p in main.roster():
			bought += int((p as Dictionary)["stars_bought"])
		kit.assert_true(bought > 0, "%s: someone bought a STAR" % mode)
	if main.split != null:
		kit.assert_true(main.ceremony.results_ui != null and is_instance_valid(main.ceremony.results_ui), "%s: the results screen shows on the TV" % mode)
	if main.vr_rig != null:
		kit.assert_true(main.ceremony.vr_results != null, "the results card shows in VR")
		kit.assert_true(seen.has("vr:throw"), "the fake VR player threw the dice")
	var mgs: PackedStringArray = []
	for k in seen:
		if String(k).begins_with("mg:"):
			mgs.append(String(k).substr(3))
	kit.info("minigames played: %s" % ", ".join(mgs))
	if OS.has_environment("PB_ALL_MINIGAMES") and mode != "client":
		for id in main.runner.ids():
			kit.assert_true(seen.has("mg:" + String(id)), "%s: played minigame %s" % [mode, id])
	if OS.has_environment("PB_MINIGAME"):
		kit.assert_true(seen.has("mg:" + OS.get_environment("PB_MINIGAME")), "%s: played %s" % [mode, OS.get_environment("PB_MINIGAME")])
