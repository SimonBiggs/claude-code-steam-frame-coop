extends Node
## Runs the minigames after every round, on every machine.
## Host / local: start(ids, done) plays them one by one:
##   howto (a how-to card with the controls for each role + READY! check; everyone can already
##   practise in the arena) -> countdown (3, 2, 1, GO!) -> play (the clock runs) -> result (places,
##   coins via turn_flow.give_minigame_coins) -> the next one, then done.call().
## Every machine builds the minigame diorama from the "mg" state ({id, seed, pids, teams, giant, n})
## and shows the cards from "mg_phase" / "mg_ready" / "mg_time" / "mg_result"; the TV machine mirrors
## the arena from snapshots and effects (main.fx("mg_fx", ...)).
## The arena sits under main.stage at ARENA_POS (board units): on the VR table that is right in front
## of the GIANT, within reach; the TV camera looks at it from the north, the giant looming behind.

const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Rules := preload("res://games/party_board/rules.gd")

## Every minigame, in the order PB_ALL_MINIGAMES plays them.
const GAMES := ["coin_catch", "hot_potato", "memory_tiles", "falling_platforms", "kart_dash", "balloon_pop",
	"sheep_herding", "treasure_dive"]
const MG_DIR := "res://games/party_board/minigames/"
const ARENA_POS := Vector3(0.0, 0.0, 11.5)
const VR_CARD_H := 0.55  ## rough height of a VR how-to / result card (metres), to keep it above the board
const FORMAT_NAMES := {"ffa": "FREE FOR ALL", "giant": "GIANT VS ISLANDERS", "teams": "TEAM GAME"}
const TEAM_NAMES := ["RED TEAM", "BLUE TEAM"]
const TEAM_COLORS := [Color(1.0, 0.4, 0.38), Color(0.35, 0.6, 1.0)]

var main: Node
var mg: Node3D  ## the running minigame (every machine)
var mg_seq := -1
# Host flow
var _queue: Array = []
var _done: Callable
var _phase := ""
var _t := 0.0
var _limit := 40.0
var _n := 0
var _last_sec := -1
# UI (every machine)
var _howto_tv: Control
var _howto_vr: Node3D
var _ready_row: HBoxContainer
var _result_tv: Control
var _result_vr: Node3D
var _board: Control  ## TV: live scores
var _timer: Control
var _vr_scores: Label3D
var _score_t := 0.0


## The minigames that exist (loaded lazily, so they hot-reload).
func ids() -> Array:
	var out: Array = []
	for id in GAMES:
		if ResourceLoader.exists(MG_DIR + id + ".gd"):
			out.append(id)
	return out


func script_of(id: String) -> GDScript:
	if not GAMES.has(id) or not ResourceLoader.exists(MG_DIR + id + ".gd"):
		return null
	return load(MG_DIR + id + ".gd") as GDScript


func meta(id: String) -> Dictionary:
	var sc := script_of(id)
	if sc == null:
		return {}
	return sc.get_script_constant_map().get("META", {})


func _w(s: float) -> float:
	return s * (0.5 if main.quick else 1.0)


# --- Host flow ------------------------------------------------------------------------------------------------

func start(list: Array, done: Callable) -> void:
	_queue = list.duplicate()
	_done = done
	_next()


func _next() -> void:
	var net: Node = main.net
	if _queue.is_empty():
		_phase = ""
		net.state_set("mg_phase", "")
		net.state_set("mg", {})
		var d := _done
		_done = Callable()
		if d.is_valid():
			d.call()
		return
	var id := String(_queue.pop_front())
	if script_of(id) == null:
		_next()
		return
	var m := meta(id)
	_n += 1
	var pids: Array = []
	for p in main.pids():
		pids.append(int(p))
	var giant: bool = main.has_vr() and pids.has(0)
	var format := String(m.get("format", "ffa"))
	if format == "giant" and not giant:
		format = "ffa"
	var teams := {}
	if format == "giant":
		for p in pids:
			teams[p] = 0 if int(p) == 0 else 1
	elif format == "teams":
		var mix: Array = pids.duplicate()
		mix.shuffle()
		if giant:  # the giant first, so the teams stay even
			mix.erase(0)
			mix.push_front(0)
		for i in mix.size():
			teams[int(mix[i])] = i % 2
	var cfg := {"id": id, "seed": randi() % 100000, "pids": pids, "teams": teams, "giant": giant, "format": format, "n": _n}
	net.state_set("mg_result", {})
	net.state_set("mg_ready", [])
	net.state_set("mg", cfg)
	net.state_set("phase", "minigame")
	net.state_set("music", String(m.get("music", "party")))
	net.state_set("mg_phase", "howto")
	_limit = float(m.get("time", 40.0)) * float(main.mg_time_scale)
	net.state_set("mg_time", int(ceil(_limit)))
	_phase = "howto"
	_t = 0.0
	main.fx("sfx", ["reveal"])


func host_tick(delta: float) -> void:
	if _phase == "" or mg == null or not is_instance_valid(mg):
		return
	var net: Node = main.net
	_t += delta
	match _phase:
		"howto":
			mg.tick(delta)
			var ready_all := true
			var ready: Array = net.state_get("mg_ready", [])
			for p in main.pids():
				if not main.is_cpu(int(p)) and not ready.has(int(p)):
					ready_all = false
			if (_t > _w(2.5) and ready_all) or _t > _w(14.0):
				_phase = "countdown"
				_t = 0.0
				mg.begin_play()
				net.state_set("mg_phase", "countdown")
		"countdown":
			if _t > 2.9:
				_phase = "play"
				_t = 0.0
				_last_sec = -1
				net.state_set("mg_phase", "play")
		"play":
			mg.tick(delta)
			var left := maxf(0.0, _limit - _t)
			var sec := int(ceil(left))
			if sec != _last_sec:
				_last_sec = sec
				net.state_set("mg_time", sec)
				if sec <= 5 and sec > 0:
					main.fx("sfx", ["tick", -6.0])
			if left <= 0.0 or mg.finished():
				_finish()
		"result":
			if _t > _w(4.5):
				_phase = ""
				_next()


func _finish() -> void:
	_phase = "result"
	_t = 0.0
	var net: Node = main.net
	var cfg: Dictionary = net.state_get("mg", {})
	var kid: bool = main.flow.is_kid()
	var rows: Array = []
	var tw: int = mg.team_winner()
	var title := ""
	var sub := ""
	if tw == -2:
		var ranked: Array = []
		for p in mg.pids:
			ranked.append({"pid": p, "score": float(mg.score.get(p, 0.0))})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
		var place := 0
		var prev := INF
		var table: Array = Rules.MG_PLACE_COINS_KID if kid else Rules.MG_PLACE_COINS
		var anyone := false
		for i in ranked.size():
			var r: Dictionary = ranked[i]
			if float(r["score"]) != prev:
				place = i + 1
			prev = float(r["score"])
			if float(r["score"]) > 0.0:
				anyone = true
			r["place"] = place
		var winners: PackedStringArray = []
		for r in ranked:
			var rd: Dictionary = r
			var win: bool = anyone and int(rd["place"]) == 1
			var coins: int = int(table[mini(int(rd["place"]) - 1, table.size() - 1)]) if anyone else (Rules.MG_LOSE_KID if kid else Rules.MG_LOSE)
			rows.append({"pid": int(rd["pid"]), "place": int(rd["place"]), "coins": coins, "win": win, "score": int(rd["score"])})
			if win:
				winners.append(main.name_of(int(rd["pid"])))
		title = ("%s WINS!" % winners[0]) if winners.size() == 1 else ("%s WIN!" % " & ".join(winners) if not winners.is_empty() else "NOBODY SCORED!")
		sub = "Coins for everyone by place!"
	else:
		var teams: Dictionary = cfg.get("teams", {})
		var format := String(cfg.get("format", "teams"))
		for p in mg.pids:
			var team := int(teams.get(p, teams.get(str(p), 1)))
			var win := tw == team
			var coins := Rules.MG_LOSE_KID if kid else Rules.MG_LOSE
			if win:
				coins = Rules.MG_SOLO_WIN if format == "giant" and team == 0 else Rules.MG_TEAM_WIN
			elif tw == -1:
				coins = Rules.MG_TEAM_WIN / 2
			rows.append({"pid": int(p), "place": 1 if win or tw == -1 else 2, "coins": coins, "win": win, "score": int(mg.score.get(p, 0.0))})
		if format == "giant":
			title = "THE GIANT WINS!" if tw == 0 else ("THE ISLANDERS WIN!" if tw == 1 else "IT'S A DRAW!")
		else:
			title = ("%s WINS!" % TEAM_NAMES[tw]) if tw >= 0 else "IT'S A DRAW!"
		sub = "Teamwork pays off!"
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["place"]) < int(b["place"]))
	main.flow.give_minigame_coins(rows)
	net.state_set("mg_result", {"rows": rows, "title": title, "sub": sub})
	net.state_set("mg_phase", "result")
	main.fx("sfx", ["time_up", -3.0])
	main.fx("sfx", ["fanfare", -4.0])


func on_request(slot: int, action: String, _args: Array) -> void:
	if action == "mg_ready" and _phase == "howto":
		var ready: Array = main.net.state_get("mg_ready", [])
		if not ready.has(slot):
			ready.append(slot)
			main.net.state_set("mg_ready", ready)
			main.fx("sfx", ["ui_select", -4.0])


# --- Every machine --------------------------------------------------------------------------------------------

func on_state(key: String, value: Variant) -> void:
	match key:
		"mg":
			_on_mg(value if value is Dictionary else {})
		"mg_phase":
			_on_phase(String(value) if value != null else "")
		"mg_ready":
			_refresh_ready()
		"mg_time":
			if _timer != null and is_instance_valid(_timer):
				_timer.call("set_time", float(value if value != null else 0))


func _on_mg(cfg: Dictionary) -> void:
	var n := int(cfg.get("n", -1))
	if cfg.is_empty() or n != mg_seq:
		_clear()
	if cfg.is_empty() or n == mg_seq:
		return
	mg_seq = n
	var id := String(cfg.get("id", ""))
	var sc := script_of(id)
	if sc == null:
		return
	mg = sc.new()
	mg.name = "Minigame"
	mg.setup(main, cfg, main.net.mode != "client")
	mg.position = ARENA_POS
	main.stage.add_child(mg)
	var m := meta(id)
	var cam: Array = m.get("cam", [13.0, 13.0])
	main.cam_look(ARENA_POS + Vector3(0, float(cam[0]), -float(cam[1])), ARENA_POS + Vector3(0, 0, 0.8), 2.0)
	_on_phase(String(main.net.state_get("mg_phase", "")))


func _clear() -> void:
	_hide_howto()
	_hide_result()
	for n: Variant in [_board, _timer]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_board = null
	_timer = null
	if _vr_scores != null and is_instance_valid(_vr_scores):
		_vr_scores.queue_free()
	_vr_scores = null
	if mg != null and is_instance_valid(mg):
		mg.queue_free()
	mg = null
	mg_seq = -1


func _on_phase(phase: String) -> void:
	if mg == null or not is_instance_valid(mg):
		return
	var id := String(mg.cfg.get("id", ""))
	match phase:
		"howto":
			_show_howto(id)
		"countdown":
			_hide_howto()
			_make_scores()
			if main.tv_ui != null:
				HudKit.countdown(main.tv_ui, 3)
			if main.vr_rig != null:
				HudKit.vr_countdown(main, main.vr_rig.camera, 3, {"sound": "" if main.tv_ui != null else "tick",
					"go_sound": "" if main.tv_ui != null else "go"})
		"play":
			_hide_howto()
			_make_scores()
			if main.tv_ui != null and (_timer == null or not is_instance_valid(_timer)):
				_timer = HudKit.timer(main.tv_ui, {"seconds": float(main.net.state_get("mg_time", 30)), "warn": 5.0})
		"result":
			_hide_howto()
			_show_result(main.net.state_get("mg_result", {}))


# --- How-to card (with the READY! check) ----------------------------------------------------------------------

func _show_howto(id: String) -> void:
	_hide_howto()
	var m := meta(id)
	var format := String(mg.cfg.get("format", "ffa"))
	var giant: bool = mg.giant
	if main.tv_ui != null:
		var card := UiKit.panel("card")
		main.tv_ui.add_child(card)
		var v := UiKit.vbox()
		card.add_child(v)
		var top := UiKit.hbox()
		top.add_child(UiKit.badge(FORMAT_NAMES.get(format, "MINIGAME"), "accent"))
		top.add_child(UiKit.label("MINIGAME %d" % int(mg.cfg.get("n", 1)), "small", "dim"))
		v.add_child(top)
		v.add_child(UiKit.title(String(m.get("name", id.to_upper()))))
		var goal := UiKit.label(String(m.get("goal", "")), "body", "text", HORIZONTAL_ALIGNMENT_CENTER)
		goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal.custom_minimum_size.x = 720.0
		v.add_child(goal)
		var cols := UiKit.hbox()
		cols.add_theme_constant_override("separation", 40)
		v.add_child(cols)
		var tvc := UiKit.vbox()
		tvc.add_child(UiKit.label("ISLANDERS (TV)", "heading", "accent"))
		tvc.add_child(UiKit.prompts(m.get("tv", [])))
		cols.add_child(tvc)
		if giant:
			var vrc := UiKit.vbox()
			vrc.add_child(UiKit.label("THE GIANT (VR)", "heading", UiKit.PLAYER_COLORS[0]))
			var lines: PackedStringArray = []
			for c in m.get("vr", []):
				lines.append("%s: %s" % [String((c as Array)[0]), String((c as Array)[1])])
			var vl := UiKit.label("\n".join(lines), "small", "text")
			vrc.add_child(vl)
			cols.add_child(vrc)
		if not (mg.teams as Dictionary).is_empty():
			v.add_child(UiKit.label(_teams_text(), "small", "text", HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UiKit.label("Practise now!  Press A when you're READY", "small", "good", HORIZONTAL_ALIGNMENT_CENTER))
		_ready_row = UiKit.hbox()
		_ready_row.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(_ready_row)
		card.set_anchors_preset(Control.PRESET_CENTER_TOP)
		card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		card.offset_top = 30.0
		UiKit.pop_in(card)
		_howto_tv = card
		_refresh_ready()
	if main.vr_rig != null:
		# VR: a headline and one short line (the TV card has the details).
		var line := String(m.get("vr_line", "")) if giant else ""
		if line == "":
			line = String(m.get("goal", ""))
		if format == "giant":
			line = "YOU vs EVERYONE!  " + line
		elif format == "teams":
			line = ("RED TEAM!  " if int((mg.teams as Dictionary).get(0, 0)) == 0 else "BLUE TEAM!  ") + line
		# 1.5 m away, big letters, above the board (family play-test: "tiny and far away").
		_howto_vr = HudKit.vr_card(main, main.vr_rig.camera, String(m.get("name", id)), line + "  TRIGGER: ready!",
			main.vr_ui_opts(VR_CARD_H, {"width": 1.2, "title_size": 0.1, "body_size": 0.065}, 0.1))
		main.vr_rig.guard_trigger()


func _teams_text() -> String:
	var t: PackedStringArray = []
	for team in 2:
		var names: PackedStringArray = []
		for p in mg.pids:
			if int((mg.teams as Dictionary).get(p, -1)) == team:
				names.append("GIANT" if p == 0 and mg.giant else main.name_of(p))
		if mg.cfg.get("format", "") == "giant":
			t.append(("THE GIANT" if team == 0 else "ISLANDERS: ") + ("" if team == 0 else ", ".join(names)))
		else:
			t.append("%s: %s" % [TEAM_NAMES[team], ", ".join(names)])
	return "   VS   ".join(t)


func _refresh_ready() -> void:
	if _ready_row == null or not is_instance_valid(_ready_row):
		return
	for c in _ready_row.get_children():
		c.queue_free()
	var ready: Array = main.net.state_get("mg_ready", [])
	for p in main.pids():
		if main.is_cpu(int(p)):
			continue
		var ok := ready.has(int(p))
		_ready_row.add_child(UiKit.badge(("%s READY!" if ok else "%s ...") % main.name_of(int(p)), int(p) if ok else "dim", 1.0,
			"check" if ok else "clock"))


func _hide_howto() -> void:
	if _howto_tv != null and is_instance_valid(_howto_tv):
		UiKit.pop_out(_howto_tv, true)
	_howto_tv = null
	_ready_row = null
	if _howto_vr != null and is_instance_valid(_howto_vr):
		_howto_vr.call("hide_card")
	_howto_vr = null


# --- Live scores ------------------------------------------------------------------------------------------------

func _make_scores() -> void:
	if main.tv_ui != null and (_board == null or not is_instance_valid(_board)):
		_board = HudKit.scoreboard(main.tv_ui, _score_rows(), {"compact": true, "title": String(meta(String(mg.cfg["id"])).get("name", ""))})
	if main.vr_rig != null and (_vr_scores == null or not is_instance_valid(_vr_scores)):
		_vr_scores = UiKit.label3d("", 0.035, "text", true, 0.9)
		main.add_child(_vr_scores)
		# Floating over the far side of the arena, facing the giant: where they look while playing.
		_vr_scores.global_position = main.to_world(ARENA_POS + Vector3(0, 0, -7.5)) + Vector3(0, 0.3, 0)


func _score_rows() -> Array:
	var rows: Array = []
	if mg == null:
		return rows
	for p in mg.pids:
		var st: String = mg.status_of(p)
		rows.append({"id": str(p), "name": ("GIANT" if p == 0 and mg.giant else main.name_of(p)) + ("  " + st if st != "" else ""),
			"score": int(mg.score.get(p, 0.0)), "color": main.color_of(p)})
	return rows


func _process(delta: float) -> void:
	if mg == null or not is_instance_valid(mg):
		return
	_score_t -= delta
	if _score_t > 0.0:
		return
	_score_t = 0.25
	if _board != null and is_instance_valid(_board):
		_board.call("set_rows", _score_rows())
	if _vr_scores != null and is_instance_valid(_vr_scores):
		var lines: PackedStringArray = ["%s   TIME %d" % [String(meta(String(mg.cfg["id"])).get("name", "")), int(main.net.state_get("mg_time", 0))]]
		var parts: PackedStringArray = []
		for r in _score_rows():
			parts.append("%s %d" % [String((r as Dictionary)["name"]), int((r as Dictionary)["score"])])
		lines.append("   ".join(parts))
		_vr_scores.text = "\n".join(lines)


# --- Results ----------------------------------------------------------------------------------------------------

func _show_result(res: Dictionary) -> void:
	_hide_result()
	if res.is_empty():
		return
	var rows: Array = res.get("rows", [])
	if main.tv_ui != null:
		HudKit.banner(main.tv_ui, String(res.get("title", "")), String(res.get("sub", "")), {"style": "victory", "duration": 2.4})
		var sb_rows: Array = []
		for r in rows:
			var rd: Dictionary = r
			var p := int(rd["pid"])
			sb_rows.append({"id": str(p), "name": "GIANT" if p == 0 and mg.giant else main.name_of(p), "score": int(rd["coins"]),
				"color": main.color_of(p), "sub": "WINNER!" if bool(rd["win"]) else ""})
		_result_tv = HudKit.scoreboard(main.tv_ui, sb_rows, {"title": "COINS WON", "format": "+%d"})
	if main.vr_rig != null:
		var mine := ""
		for r in rows:
			var rd: Dictionary = r
			if int(rd["pid"]) == 0:
				mine = ("YOU WON!  +%d coins" if bool(rd["win"]) else "You got +%d coins") % int(rd["coins"])
		_result_vr = HudKit.vr_card(main, main.vr_rig.camera, String(res.get("title", "")), mine,
			main.vr_ui_opts(VR_CARD_H, {"width": 1.2, "title_size": 0.1, "body_size": 0.065}, 0.1))
	if main.cam != null:
		main.cam.shake(0.15)


func _hide_result() -> void:
	if _result_tv != null and is_instance_valid(_result_tv):
		_result_tv.queue_free()
	_result_tv = null
	if _result_vr != null and is_instance_valid(_result_vr):
		_result_vr.call("hide_card")
	_result_vr = null


# --- Input (local seats / the VR player): READY! ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if mg == null or String(main.net.state_get("mg_phase", "")) != "howto" or get_tree().paused:
		return
	var ready: Array = main.net.state_get("mg_ready", [])
	if main.split != null:
		for slot in main.party.local_slots():
			if slot == 0 and main.vr_rig != null:
				continue
			if not ready.has(slot) and main.party.just_pressed(slot, "accept"):
				main.net.request(slot, "mg_ready", [])
	if main.vr_rig != null and not ready.has(0) and (main.vr_rig.trigger_pressed() or main.vr_rig.a_pressed()):
		main.net.request(0, "mg_ready", [])
		main.vr_rig.pulse(1, 0.4, 0.05)


# --- Network ----------------------------------------------------------------------------------------------------

func snapshot() -> Array:
	if mg == null or not is_instance_valid(mg):
		return []
	return [mg_seq, mg.snapshot()]


func apply_snapshot(s: Variant) -> void:
	if not (s is Array) or (s as Array).size() < 2 or mg == null or not is_instance_valid(mg):
		return
	if int(s[0]) != mg_seq:
		return
	mg.apply_snapshot(s[1])


func on_fx(kind: String, args: Variant) -> void:
	if mg != null and is_instance_valid(mg):
		mg.on_fx(kind, args)
