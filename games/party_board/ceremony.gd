extends Node
## The end of the party: bonus stars (MOST COINS, MINIGAME STAR, HAPPENING STAR), a drum roll, the
## winner crowned on the board, then the results (standings + awards) and PLAY AGAIN.
## Host / local: run(records) drives it on turn_flow's sequencer and publishes the "ceremony" and
## "results" states. Every machine: on_state() shows the results screen (TV) / summary card (VR),
## crowns the winners' tokens and points the TV camera at them.

const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Awards := preload("res://core/awards.gd")

const BONUS := [
	["max_coins", "MOST COINS STAR", "Richest moment of the party:\n%s!"],
	["mg_wins", "MINIGAME STAR", "Most minigames won:\n%s!"],
	["events", "HAPPENING STAR", "Most event spaces:\n%s!"],
]

var main: Node
var results_ui: Control
var vr_results: Node
var _crowned: Array = []


## Host / local: the last minigame is over.
func run(records: Dictionary) -> void:
	var flow: Node = main.flow
	var seq: Node = flow.seq
	var net: Node = main.net
	net.state_set("phase", "ceremony")
	net.state_set("cur", -1)
	net.state_set("step", "overview")
	net.state_set("music", "tension")
	net.state_set("sky", "sunset")
	main.fx("banner", ["THE PARTY IS OVER!", "Time for the BONUS STARS...", "boss", 2.6])
	main.fx("sfx", ["drumroll", -2.0])
	seq.wait(flow._w(2.8))
	for b in BONUS:
		var stat := String((b as Array)[0])
		var title := String((b as Array)[1])
		var text := String((b as Array)[2])
		seq.add(func() -> void:
			var best := _best(records, stat)
			if best.is_empty():
				main.fx("banner", [title, "Nobody this time!", "info", 2.0])
				return
			var names: PackedStringArray = []
			for pid in best:
				names.append(String((records[pid] as Dictionary)["name"]))
				flow.add_bonus_star(int(pid), title)
				main.fx("star_fx", [int(pid), 1])
			net.state_set("cur", int(best[0]))
			main.fx("banner", [title, text % " & ".join(names), "level", 2.8]))
		seq.wait(flow._w(3.2))
	seq.add(func() -> void:
		net.state_set("cur", -1)
		main.fx("banner", ["AND THE WINNER IS...", "", "boss", 2.4])
		main.fx("sfx", ["drumroll"]))
	seq.wait(flow._w(2.6))
	seq.add(_crown)


## Players with the most `stat` (ties all get it); nobody when everyone has 0.
func _best(records: Dictionary, stat: String) -> Array:
	var best: Array = []
	var bv := 0
	for pid in records:
		var v := int((records[pid] as Dictionary).get(stat, 0))
		if v > bv:
			bv = v
			best = [int(pid)]
		elif v == bv and v > 0:
			best.append(int(pid))
	return best


## Host: rank by stars, then coins; crown the winner(s); publish the results.
func _crown() -> void:
	var flow: Node = main.flow
	var net: Node = main.net
	var recs: Array = []
	for pid in flow.pl:
		recs.append(flow.pl[pid])
	recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["stars"]) != int(b["stars"]):
			return int(a["stars"]) > int(b["stars"])
		return int(a["coins"]) > int(b["coins"]))
	var rows: Array = []
	var winners: Array = []
	var rank := 0
	for i in recs.size():
		var r: Dictionary = recs[i]
		if i == 0 or int(r["stars"]) != int((recs[i - 1] as Dictionary)["stars"]) or int(r["coins"]) != int((recs[i - 1] as Dictionary)["coins"]):
			rank = i + 1
		if rank == 1:
			winners.append(int(r["pid"]))
		rows.append({"id": int(r["pid"]), "name": "%s  (%d coins)" % [String(r["name"]), int(r["coins"])],
			"color": main.color_of(int(r["pid"])), "score": int(r["stars"]), "rank": rank})
	var names: PackedStringArray = []
	for w in winners:
		names.append(String((flow.pl[w] as Dictionary)["name"]))
	# Awards: game-specific titles first.
	var aw: Awards = main.awards
	aw.define("pb_stars", "STAR COLLECTOR", "%s stars", "stars_total", "max", 1.0, "star")
	aw.define("pb_duel", "QUICK DRAW", "%s duels won", "duel_wins", "max", 1.0, "bolt")
	aw.define("pb_mg", "MINIGAME MASTER", "%s minigames won", "mg_wins", "max", 1.0, "trophy")
	aw.define("pb_shop", "BIG SPENDER", "%s items bought", "items_bought", "max", 1.0, "bag")
	aw.define("pb_hops", "MARATHON RUNNER", "%s spaces hopped", "hops", "max", 10.0, "flag")
	for pid in flow.pl:
		var r: Dictionary = flow.pl[pid]
		aw.add(int(pid), "stars_total", int(r["stars"]))
		aw.add(int(pid), "items_bought", int(r["items_bought"]))
		aw.add(int(pid), "hops", int(r["hops"]))
	var data := aw.results({"title": "%s WIN%s!" % [" & ".join(names), "" if winners.size() > 1 else "S"],
		"subtitle": "Thanks for playing PARTY BOARD!", "style": "victory", "score_format": "%d STARS",
		"stats": [["ROUNDS", str(int(net.state_get("rounds", 0)))], ["MINIGAMES", str(flow.mg_played.size())]],
		"continue": "Play again"})
	data["rows"] = rows
	net.state_set("winners", winners)
	net.state_set("results", data)
	net.state_set("phase", "results")
	net.state_set("music", "victory")
	main.fx("sfx", ["fanfare"])
	main.fx("sfx", ["applause", -4.0])
	for w in winners:
		main.fx("anim", [int(w), "victory", 6.0])
	flow.finish_game(winners)


# --- Every machine ------------------------------------------------------------------------------------

func on_state(key: String, value: Variant) -> void:
	match key:
		"phase":
			if String(value) == "results":
				_show(main.net.state_get("results", {}))
			else:
				_hide()
		"winners":
			_crown_tokens(value if value is Array else [])


func _crown_tokens(winners: Array) -> void:
	for pid in main.tokens:
		(main.tokens[pid] as Node).call("set_crown", winners.has(int(pid)))
	_crowned = winners.duplicate()


func _show(data: Dictionary) -> void:
	_hide()
	if data.is_empty():
		return
	if main.tv_ui != null:
		var screen := Awards.results_screen(main.tv_ui, data, {"party": main.party, "min_time": 4.0})
		screen.continued.connect(func() -> void:
			var seats: Array[int] = main.party.local_slots()
			main.net.request(seats[0] if not seats.is_empty() else 0, "again", []))
		results_ui = screen
	if main.vr_rig != null:
		var card := Awards.vr_summary(main, null, data, null, {"rig": main.vr_rig, "min_time": 4.0})
		card.continued.connect(func() -> void: main.net.request(0, "again", []))
		vr_results = card
	if not _crowned.is_empty():
		var t: Node3D = main.tokens.get(int(_crowned[0]), null)
		if t != null:
			main.cam_focus(t.position + Vector3(0, 1.2, 0), 9.0, 1.5)


func _hide() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
	vr_results = null


## True while the results are on screen (bots).
func showing() -> bool:
	return String(main.net.state_get("phase", "")) == "results"
