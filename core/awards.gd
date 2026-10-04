extends RefCounted
## Per-player stat tracking, an award picker with fun titles (MVP, LIFESAVER, SPEED DEMON...), a
## polished end-of-round / end-of-game results screen for the TV and a short VR summary.
##
##   const Awards := preload("res://core/awards.gd")
##   var awards := Awards.new()
##   awards.set_player(0, "KNIGHT", 0)            # index, name, colour (Color, palette name or player index)
##   awards.add(2, "damage", 35)                   # during play (host)
##   awards.add(1, "revives")
##   awards.best(3, "best_time", 41.2, true)       # keep the lowest
##   var data := awards.results({"title": "VICTORY!", "score_stat": "score", "style": "victory"})
##   net.event("results", [data])                  # plain data: send it to the TV
##   var screen := Awards.results_screen(ui_root, data, {"party": party})   # any local seat continues
##   await screen.continued
##   Awards.vr_summary(self, null, data, null, {"rig": vr_rig})            # or (self, xr_camera, data, hand_r)
##
## Stats are free-form names; the catalogue below gives the common ones titles. define() adds your own.

const UiKit := preload("res://core/ui_kit.gd")
const UiInput := preload("res://core/ui_input.gd")
const HudKit := preload("res://core/hud_kit.gd")

## [id, TITLE, description ("%s" = value), stat, "max"/"min", minimum value, icon]
const CATALOGUE := [
	["mvp", "MVP", "Top score: %s", "score", "max", 1.0, "crown"],
	["heavy_hitter", "HEAVY HITTER", "%s damage dealt", "damage", "max", 1.0, "sword"],
	["lifesaver", "LIFESAVER", "%s revives", "revives", "max", 1.0, "plus"],
	["guardian", "GUARDIAN ANGEL", "%s HP healed", "healing", "max", 1.0, "heart"],
	["iron_wall", "IRON WALL", "Took %s hits and kept going", "damage_taken", "max", 1.0, "shield"],
	["shield_wall", "SHIELD WALL", "%s attacks blocked", "blocks", "max", 1.0, "shield"],
	["sharpshooter", "SHARPSHOOTER", "%s hits", "hits", "max", 3.0, "eye"],
	["critical", "CRITICAL!", "%s critical hits", "crits", "max", 1.0, "bolt"],
	["monster_masher", "MONSTER MASHER", "%s monsters defeated", "kills", "max", 1.0, "skull"],
	["archmage", "ARCHMAGE", "%s spells cast", "spells", "max", 1.0, "star"],
	["treasure_hunter", "TREASURE HUNTER", "%s treasures found", "pickups", "max", 1.0, "gem"],
	["moneybags", "MONEYBAGS", "%s coins", "coins", "max", 1.0, "coin"],
	["speed_demon", "SPEED DEMON", "Fastest time: %s s", "best_time", "min", 0.001, "clock"],
	["quick_draw", "QUICK DRAW", "Answered in %s s", "fastest_answer", "min", 0.001, "bolt"],
	["brainiac", "BRAINIAC", "%s right answers", "correct", "max", 1.0, "check"],
	["on_fire", "ON FIRE", "%s in a row", "best_streak", "max", 3.0, "fire"],
	["clutch", "CLUTCH", "%s last-second saves", "clutch", "max", 1.0, "star"],
	["team_player", "TEAM PLAYER", "%s assists", "assists", "max", 1.0, "person"],
	["explorer", "EXPLORER", "%s m explored", "distance", "max", 10.0, "flag"],
	["master_builder", "MASTER BUILDER", "%s things built", "builds", "max", 1.0, "bag"],
	["super_sleuth", "SUPER SLEUTH", "%s clues found", "clues", "max", 1.0, "eye"],
	["hole_in_one", "HOLE IN ONE", "%s holes in one", "holes_in_one", "max", 1.0, "flag"],
	["lucky_dice", "LUCKY DICE", "Rolled %s sixes", "sixes", "max", 1.0, "star"],
	["bouncy", "BOUNCY", "%s jumps", "jumps", "max", 10.0, "arrow_up"],
	["butterfingers", "BUTTERFINGERS", "Dropped it %s times", "drops", "max", 2.0, "drop"],
	["daredevil", "DAREDEVIL", "%s tumbles (and still smiling)", "falls", "max", 2.0, "exclaim"],
	["too_brave", "TOO BRAVE", "Knocked out %s times", "deaths", "max", 2.0, "skull"],
]

## Titles for players who didn't win anything (everyone goes home with something).
const CONSOLATION := [["GOOD SPORT", "Always there for the team", "heart"], ["TEAM SPIRIT", "Kept everyone smiling", "star"],
	["LUCKY CHARM", "The team's secret weapon", "gem"], ["BEST CHEERS", "Loudest cheers on the couch", "music"],
	["RISING STAR", "Next time is yours!", "star"], ["HEART OF GOLD", "Kind to friends and foes", "heart"]]

var players := {}     ## index -> {name, color}
var stats := {}       ## index -> {stat: float}
var custom: Array = []  ## define()d awards (checked first)


## Name and colour a player (colour: Color, palette name or player index; default their player colour).
func set_player(index: int, player_name: String, color: Variant = null) -> void:
	players[index] = {"name": player_name, "color": UiKit.color_of(color if color != null else index)}
	if not stats.has(index):
		stats[index] = {}


## Add to a stat (creates the player with a default name if needed).
func add(index: int, stat: String, amount: float = 1.0) -> void:
	_ensure(index)
	var d: Dictionary = stats[index]
	d[stat] = float(d.get(stat, 0.0)) + amount


## Set a stat outright.
func set_stat(index: int, stat: String, value: float) -> void:
	_ensure(index)
	(stats[index] as Dictionary)[stat] = value


## Keep the best value of a stat (highest, or lowest when lower_is_better: lap times, answer times).
func best(index: int, stat: String, value: float, lower_is_better: bool = false) -> void:
	_ensure(index)
	var d: Dictionary = stats[index]
	if not d.has(stat) or (value < float(d[stat]) if lower_is_better else value > float(d[stat])):
		d[stat] = value


## A player's stat (0 if never set).
func get_stat(index: int, stat: String) -> float:
	if not stats.has(index):
		return 0.0
	return float((stats[index] as Dictionary).get(stat, 0.0))


## Sum of a stat over everyone.
func total(stat: String) -> float:
	var t := 0.0
	for i in stats:
		t += float((stats[i] as Dictionary).get(stat, 0.0))
	return t


## Clear all stats (keeps players).
func reset() -> void:
	for i in stats:
		stats[i] = {}


## Add a game-specific award (checked before the catalogue). mode "max" or "min".
func define(id: String, title: String, desc_fmt: String, stat: String, mode: String = "max", min_value: float = 1.0, icon: String = "star") -> void:
	custom.append([id, title, desc_fmt, stat, mode, min_value, icon])


## Pick up to `max_awards` awards, spreading them so as many players as possible get one, most
## remarkable first. opts: consolation (true: everyone without an award gets a friendly title),
## only (Array of award ids to consider). Returns [{id, title, desc, player, name, color, value, icon}].
func pick(max_awards: int = 6, opts: Dictionary = {}) -> Array:
	var only: Array = opts.get("only", [])
	var cands: Array = []
	var defs: Array = custom.duplicate()
	defs.append_array(CATALOGUE)
	var k := 0
	for def in defs:
		var d: Array = def
		k += 1
		if not only.is_empty() and not only.has(d[0]):
			continue
		var stat := String(d[3])
		var lower := String(d[4]) == "min"
		var winner := -1
		var top := 0.0
		var sum := 0.0
		var n := 0
		var tie := false
		for i in stats:
			var sd: Dictionary = stats[i]
			if not sd.has(stat):
				continue
			var v := float(sd[stat])
			if lower and v <= 0.0:
				continue
			sum += v
			n += 1
			if winner < 0 or (v < top if lower else v > top):
				winner = int(i)
				top = v
				tie = false
			elif v == top:
				tie = true
		if winner < 0 or (not lower and top < float(d[5])) or tie and n > 1:
			continue
		var mean_others := (sum - top) / maxf(1.0, float(n - 1))
		var standout := 2.5  # the only one who did it at all
		if n > 1:
			standout = (mean_others / maxf(0.001, top)) if lower else (top / maxf(0.001, mean_others))
		standout = minf(standout, 10.0) + (100.0 if k <= custom.size() else 0.0) + (0.5 if d[0] == "mvp" else 0.0)
		cands.append({"id": d[0], "title": d[1], "desc": String(d[2]) % _fmt(top), "player": winner, "value": top,
			"icon": d[6], "score": standout})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	var out: Array = []
	var has := {}
	for c in cands:  # one each first
		if out.size() >= max_awards:
			break
		if not has.has(c.player):
			has[c.player] = true
			out.append(c)
	for c in cands:  # then the rest of the best
		if out.size() >= max_awards:
			break
		if not out.has(c):
			out.append(c)
	if bool(opts.get("consolation", true)):
		var ci := 0
		for i in players:
			if out.size() >= max_awards + players.size():
				break
			if not has.has(i):
				var cs: Array = CONSOLATION[(int(i) + ci) % CONSOLATION.size()]
				ci += 1
				out.append({"id": "consolation", "title": cs[0], "desc": cs[1], "player": int(i), "value": 0.0, "icon": cs[2], "score": 0.0})
	for a in out:
		var p: Dictionary = players.get(a.player, {"name": "P%d" % (int(a.player) + 1), "color": UiKit.player_color(int(a.player))})
		a["name"] = p["name"]
		a["color"] = p["color"]
		a.erase("score")
	return out


## Standings rows for HudKit.scoreboard / the results screen, ranked by `stat`.
func standings(stat: String = "score", ascending: bool = false) -> Array:
	var rows: Array = []
	for i in _all_indices():
		var p: Dictionary = players.get(i, {"name": "P%d" % (int(i) + 1), "color": UiKit.player_color(int(i))})
		rows.append({"id": int(i), "name": p["name"], "color": p["color"], "score": get_stat(int(i), stat)})
	return HudKit.rank_rows(rows, ascending)


## Everything the results screens need, as plain data (safe to send with net.event). opts: title,
## subtitle, style ("victory", "defeat", "neutral"), score_stat ("score"), ascending, max_awards (6),
## stats ([[label, value], ...] team facts like [["TIME", "4:12"]]), continue ("Continue"),
## score_format ("%d PTS"), consolation.
func results(opts: Dictionary = {}) -> Dictionary:
	return {
		"title": String(opts.get("title", "RESULTS")),
		"subtitle": String(opts.get("subtitle", "")),
		"style": String(opts.get("style", "neutral")),
		"rows": standings(String(opts.get("score_stat", "score")), bool(opts.get("ascending", false))),
		"awards": pick(int(opts.get("max_awards", 6)), {"consolation": bool(opts.get("consolation", true))}),
		"stats": opts.get("stats", []),
		"continue": String(opts.get("continue", "Continue")),
		"score_format": String(opts.get("score_format", "%d")),
	}


## The TV results screen. data: from results() (or hand-made with the same keys). opts: party (+ slot,
## default -1 = any seat on this machine) or device / keys (who can continue; default anyone),
## min_time (s before Continue works, 2.5), keep (don't close on continue). Connect `continued`.
static func results_screen(root: Control, data: Dictionary, opts: Dictionary = {}) -> ResultsScreen:
	var r := ResultsScreen.new()
	r.data = data
	r.party = opts.get("party", null)
	r.slot = int(opts.get("slot", -1))
	r.device = int(opts.get("device", UiInput.PAD_ANY))
	r.keys = int(opts.get("keys", UiInput.KEYS_ALL))
	r.min_time = float(opts.get("min_time", 2.5))
	r.keep = bool(opts.get("keep", false))
	root.add_child(r)
	return r


## The VR summary: title, the top three and the awards on a card in front of the VR player; the
## trigger (or A) continues. Connect `continued`. opts: rig (a core/vr_rig.gd VrRig: then cam/hand may
## be null), min_time, layers.
static func vr_summary(world: Node, cam: Node3D, data: Dictionary, hand: Node3D = null, opts: Dictionary = {}) -> VrSummary:
	var s := VrSummary.new()
	s.data = data
	s.cam = cam
	s.hand = hand
	s.rig = opts.get("rig", null)
	if s.rig != null:
		s.cam = s.rig.get("camera")
		s.hand = s.rig.get("hand_r")
	s.min_time = float(opts.get("min_time", 2.5))
	s.vis_layers = int(opts.get("layers", 1))
	world.add_child(s)
	return s


func _ensure(index: int) -> void:
	if not stats.has(index):
		stats[index] = {}
	if not players.has(index):
		players[index] = {"name": "P%d" % (index + 1), "color": UiKit.player_color(index)}


func _all_indices() -> Array:
	var ids: Array = players.keys()
	for i in stats:
		if not ids.has(i):
			ids.append(i)
	ids.sort()
	return ids


static func _fmt(v: float) -> String:
	if absf(v - round(v)) < 0.001:
		return str(int(round(v)))
	return "%.1f" % v


class ResultsScreen extends Control:
	## End-of-round results: title band, standings that slide in with counting scores, award cards
	## popping in one by one, team stats, and a "Continue" prompt once everyone has had a look.
	signal continued()
	const UiKit := preload("res://core/ui_kit.gd")
	const UiInput := preload("res://core/ui_input.gd")
	const HudKit := preload("res://core/hud_kit.gd")
	var data := {}
	var party: Node = null
	var slot := -1
	var device := -2
	var keys := 2
	var min_time := 2.5
	var keep := false
	var t := 0.0
	var reader: UiInput
	var _s := 1.0
	var _footer: Control
	var _cards: Array[Control] = []
	var _done := false
	var _revealed := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_s = UiKit.scale_of(self)
		reader = UiInput.for_party(party, slot) if party != null else UiInput.new(device, keys)
		reader.latch()
		var style := String(data.get("style", "neutral"))
		var accent: Color = {"victory": UiKit.GOLD, "defeat": UiKit.BAD}.get(style, UiKit.ACCENT)
		var dim := ColorRect.new()
		dim.color = Color(0.01, 0.015, 0.04, 0.72)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.modulate.a = 0.0
		UiKit.fade(dim, 1.0, 0.35)
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var outer := UiKit.vbox(18, _s)
		outer.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(outer)
		# title
		var head := UiKit.hbox(18, _s)
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		var tr1 := UiKit.icon("trophy", accent, 64.0 * _s)
		tr1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tr1)
		var title := UiKit.label(String(data.get("title", "RESULTS")), "banner", accent.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER)
		title.add_theme_font_size_override("font_size", int(UiKit.font_size("banner", _s) * 0.8))
		head.add_child(title)
		var tr2 := UiKit.icon("trophy", accent, 64.0 * _s)
		tr2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tr2)
		outer.add_child(head)
		UiKit.pop_in(head)
		var sub := String(data.get("subtitle", ""))
		if sub != "":
			var sl := UiKit.label(sub, "subtitle", null, HORIZONTAL_ALIGNMENT_CENTER)
			outer.add_child(sl)
		# team stats pills
		var st: Array = data.get("stats", [])
		if not st.is_empty():
			var srow := UiKit.hbox(14, _s)
			srow.alignment = BoxContainer.ALIGNMENT_CENTER
			for pair in st:
				var a: Array = pair
				srow.add_child(UiKit.badge("%s  %s" % [str(a[0]), str(a[1])], "accent", _s))
			outer.add_child(srow)
		# body: standings + awards
		var vp := get_viewport().get_visible_rect().size
		var wide := vp.x / maxf(1.0, vp.y) > 1.3 and vp.x >= 1000.0 * _s
		var body: BoxContainer
		if wide:
			body = UiKit.hbox(36, _s)
		else:
			body = UiKit.vbox(18, _s)
		body.alignment = BoxContainer.ALIGNMENT_CENTER
		outer.add_child(body)
		var rows: Array = data.get("rows", [])
		if not rows.is_empty():
			var holder := UiKit.panel("default")
			holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			body.add_child(holder)
			var bv := UiKit.vbox(8, _s)
			holder.add_child(bv)
			bv.add_child(UiKit.label("STANDINGS", "small", "dim", HORIZONTAL_ALIGNMENT_CENTER))
			var board := HudKit.Scoreboard.new()
			board.title_text = ""
			board.width = 560.0 if wide else 640.0
			board.anchor = "none"
			board.fmt = String(data.get("score_format", "%d"))
			board.max_rows = 8
			board.add_theme_stylebox_override("panel", UiKit.stylebox(Color(0, 0, 0, 0), _s, 0.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2.ZERO))
			bv.add_child(board)
			board.set_rows(rows)
		var awards: Array = data.get("awards", [])
		if not awards.is_empty():
			var ap := UiKit.vbox(10, _s)
			body.add_child(ap)
			ap.add_child(UiKit.label("AWARDS", "small", "dim", HORIZONTAL_ALIGNMENT_CENTER))
			var grid := GridContainer.new()
			grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.columns = 2 if awards.size() > 3 or not wide else 1
			if not wide and awards.size() > 4:
				grid.columns = 3
			grid.add_theme_constant_override("h_separation", int(14 * _s))
			grid.add_theme_constant_override("v_separation", int(12 * _s))
			ap.add_child(grid)
			for a in awards:
				var card := _award_card(a)
				grid.add_child(card)
				_cards.append(card)
		_footer = UiKit.prompts([[String(reader.glyphs()["confirm"]), String(data.get("continue", "Continue"))]], _s)
		_footer.modulate.a = 0.0
		outer.add_child(_footer)
		UiKit.sound("fanfare" if style == "victory" else ("gameover" if style == "defeat" else "ui_open"))

	func _award_card(a: Dictionary) -> Control:
		var col := UiKit.color_of(a.get("color", "accent"), UiKit.ACCENT)
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := UiKit.tinted_panel(col, _s, "card")
		holder.add_child(card)
		var h := UiKit.hbox(14, _s)
		card.add_child(h)
		var disc := PanelContainer.new()
		disc.custom_minimum_size = Vector2(64, 64) * _s
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		disc.add_theme_stylebox_override("panel", UiKit.stylebox(col.darkened(0.55), _s, 200.0, col, 3.0, 0.0, Vector2.ZERO))
		var ic := UiKit.icon(String(a.get("icon", "star")), UiKit.GOLD, 40.0 * _s)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		disc.add_child(ic)
		h.add_child(disc)
		var v := UiKit.vbox(2, _s)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(v)
		var tl := UiKit.label(String(a.get("title", "")), "heading", UiKit.GOLD.lightened(0.2))
		tl.add_theme_font_size_override("font_size", int(UiKit.font_size("heading", _s) * 0.8))
		v.add_child(tl)
		var nb := UiKit.badge(String(a.get("name", "")), col, _s)
		nb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(nb)
		var dl := UiKit.label(String(a.get("desc", "")), "tiny", "dim")
		v.add_child(dl)
		card.resized.connect(func() -> void: holder.custom_minimum_size = card.size)
		card.size = card.get_combined_minimum_size()
		holder.custom_minimum_size = card.size
		card.modulate.a = 0.0
		return holder

	func _process(delta: float) -> void:
		t += delta
		# reveal the award cards one by one after the standings
		var due := int((t - 0.9) / 0.4) + 1
		while _revealed < _cards.size() and _revealed < due:
			var holder := _cards[_revealed]
			var card := holder.get_child(0) as Control
			if card != null:
				card.pivot_offset_ratio = Vector2(0.5, 0.5)
				UiKit.pop_in(card, 0.0, 0.6, 0.35)
			UiKit.sound("ui_select", -3.0, 1.0 + _revealed * 0.08)
			_revealed += 1
		var ready_now := t >= min_time
		if ready_now and _footer.modulate.a < 1.0:
			_footer.modulate.a = minf(1.0, _footer.modulate.a + delta * 3.0)
		if not ready_now or _done:
			return
		var acts := reader.poll(delta)
		if acts.has("confirm"):
			finish()

	func _input(ev: InputEvent) -> void:
		if reader != null:
			reader.note_event(ev)

	## Continue now (as if A was pressed).
	func finish() -> void:
		if _done:
			return
		_done = true
		UiKit.sound("ui_select")
		continued.emit()
		if not keep:
			var tw := create_tween()
			tw.tween_property(self, "modulate:a", 0.0, 0.3)
			tw.tween_callback(queue_free)


class VrSummary extends Node3D:
	## The VR results card: title, top three, awards, "TRIGGER: continue".
	signal continued()
	const UiKit := preload("res://core/ui_kit.gd")
	const UiInput := preload("res://core/ui_input.gd")
	const HudKit := preload("res://core/hud_kit.gd")
	var data := {}
	var cam: Node3D
	var hand: Node3D
	var rig: Node = null
	var min_time := 2.5
	var vis_layers := 1
	var t := 0.0
	var card: Node3D
	var reader: UiInput
	var _done := false

	func _ready() -> void:
		reader = UiInput.for_rig(rig) if rig != null else UiInput.new(UiInput.PAD_NONE, UiInput.KEYS_NONE, hand)
		reader.latch()
		var lines: PackedStringArray = []
		var rows: Array = data.get("rows", [])
		for i in mini(3, rows.size()):
			var r: Dictionary = rows[i]
			lines.append("%s   %s   %s" % [HudKit.ordinal(int(r.get("rank", i + 1))), str(r.get("name", "")),
				String(data.get("score_format", "%d")) % int(float(r.get("score", 0.0)))])
		var awards: Array = data.get("awards", [])
		if not awards.is_empty():
			lines.append("")
			for k in mini(4, awards.size()):
				var a: Dictionary = awards[k]
				lines.append("%s: %s" % [str(a.get("title", "")), str(a.get("name", ""))])
		lines.append("")
		lines.append("TRIGGER: continue")
		var style := String(data.get("style", "neutral"))
		var col: Color = {"victory": UiKit.GOLD, "defeat": UiKit.BAD}.get(style, UiKit.ACCENT)
		card = HudKit.vr_card(get_parent(), cam, String(data.get("title", "RESULTS")), "\n".join(lines),
			{"width": 1.4, "color": col, "distance": 1.6, "height": 0.0, "layers": vis_layers, "title_size": 0.11})
		(card as HudKit.VrCard).title_color = col.lightened(0.4)

	func _process(delta: float) -> void:
		t += delta
		if _done or t < min_time:
			return
		if reader.poll(delta).has("confirm"):
			finish()

	## Continue now.
	func finish() -> void:
		if _done:
			return
		_done = true
		UiKit.sound("ui_select")
		continued.emit()
		if card != null and is_instance_valid(card):
			card.call("hide_card")
		queue_free()
