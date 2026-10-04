extends Node
## Party Board HUD, built from the replicated state on every machine:
##  - TV (shared view): round pill, "whose turn" pill with a hint, a card per player along the bottom
##    (colour, name, CPU tag, coins, stars, items, rank; the current player's card is raised), a join
##    prompt, banners and toasts, and the title screen (logo, roster, saved stats).
##  - VR: a world-locked SCOREBOARD standing behind the island (where the VR player always looks:
##    round, whose turn, everyone's coins / stars), the player's own coins and stars on the back of
##    the left glove, VR banners / toasts.
##  - 3D (every machine): a bouncing marker over the current token and the "steps left" counter.

const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Rules := preload("res://games/party_board/rules.gd")

var main: Node
var cards_row: HBoxContainer
var cards := {}  # pid -> PanelContainer
var round_label: Label
var final_badge: Control
var turn_pill: PanelContainer
var turn_label: Label
var hint_label: Label
var join_pill: Control
var title_box: Control
var title_roster: Label
var title_stats: Label
var vr_board: Node3D
var vr_title: Label3D
var vr_turn: Label3D
var vr_rows: Array[Label3D] = []
var vr_dots: Array[MeshInstance3D] = []
var glove_label: Label3D
const GLOVE_POS := Vector3(0.06, 0.05, 0.05)  ## left-controller space; MENU is at (-0.15, 0.02, 0.12)
var marker: Node3D
var steps_label: Label3D
var _t := 0.0
var _marker_pid := -1


func _ready() -> void:
	if main.tv_ui != null:
		_build_tv(main.tv_ui)
	if main.vr_rig != null:
		_build_vr()
	_build_3d()


# --- TV ---------------------------------------------------------------------------------------------

func _build_tv(ui: Control) -> void:
	var s := UiKit.scale_of(ui)
	var rp := UiKit.panel("pill")
	ui.add_child(rp)
	rp.position = Vector2(26, 22) * s
	var rrow := UiKit.hbox(10, s)
	rp.add_child(rrow)
	rrow.add_child(UiKit.icon("flag", "accent", 26.0 * s))
	round_label = UiKit.label("PARTY BOARD", "body", "text")
	rrow.add_child(round_label)
	final_badge = UiKit.badge("FINAL TURNS!", "bad", s, "fire")
	final_badge.visible = false
	rrow.add_child(final_badge)
	turn_pill = UiKit.panel("card")
	ui.add_child(turn_pill)
	turn_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	turn_pill.offset_top = 18.0 * s
	var tv := UiKit.vbox(2, s)
	turn_pill.add_child(tv)
	turn_label = UiKit.label("", "heading", null, HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(turn_label)
	hint_label = UiKit.label("", "small", "dim", HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(hint_label)
	turn_pill.visible = false
	cards_row = UiKit.hbox(12, s)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ui.add_child(cards_row)
	cards_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cards_row.offset_top = -18.0 * s
	cards_row.offset_bottom = -18.0 * s
	cards_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	join_pill = UiKit.panel("pill")
	join_pill.add_child(UiKit.prompts([["A", "on a spare controller: JOIN!"]], s))
	ui.add_child(join_pill)
	join_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	join_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	join_pill.offset_left = -24.0 * s
	join_pill.offset_right = -24.0 * s
	join_pill.offset_top = 22.0 * s
	_build_title(ui, s)


func _build_title(ui: Control, s: float) -> void:
	title_box = UiKit.vbox(14, s)
	ui.add_child(title_box)
	title_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	title_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	title_box.offset_left = 70.0 * s
	var logo := UiKit.label("PARTY BOARD", "banner", "accent")
	logo.add_theme_color_override("font_outline_color", Color(0.35, 0.1, 0.3))
	logo.add_theme_constant_override("outline_size", int(18 * s))
	title_box.add_child(logo)
	title_box.add_child(UiKit.label("A party on Party Island!  Roll, hop, shop, play minigames - collect the most STARS.", "body", "text"))
	var card := UiKit.panel("card")
	title_box.add_child(card)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var v := UiKit.vbox(6, s)
	card.add_child(v)
	v.add_child(UiKit.label("PLAYERS", "small", "dim"))
	title_roster = UiKit.label("", "body")
	v.add_child(title_roster)
	title_stats = UiKit.label("", "small", "dim")
	title_box.add_child(title_stats)
	UiKit.slide_in(title_box, Vector2(-80, 0) * s)


func _refresh_cards() -> void:
	if cards_row == null:
		return
	var ps: Array = main.roster()
	var want := {}
	for p in ps:
		want[int((p as Dictionary)["pid"])] = true
	for pid in cards.keys():
		if not want.has(pid):
			(cards[pid] as Node).queue_free()
			cards.erase(pid)
	var ranks := ranks_of(ps)
	var cur := int(main.net.state_get("cur", -1))
	var s := UiKit.scale_of(main.tv_ui)
	var n := maxi(1, ps.size())
	var w := minf(250.0, 1800.0 / n - 12.0)
	for p in ps:
		var pd: Dictionary = p
		var pid := int(pd["pid"])
		var card: PanelContainer = cards.get(pid, null)
		if card == null or not is_instance_valid(card):
			card = _make_card(pid, s, w)
			cards[pid] = card
			cards_row.add_child(card)
			UiKit.pop_in(card)
		(card.find_child("Name", true, false) as Label).text = String(pd.get("name", "P%d" % (pid + 1)))
		(card.find_child("Cpu", true, false) as Control).visible = bool(pd.get("cpu", false))
		(card.find_child("Coins", true, false) as Label).text = str(int(pd.get("coins", 0)))
		(card.find_child("Stars", true, false) as Label).text = str(int(pd.get("stars", 0)))
		var rk := card.find_child("Rank", true, false) as Label
		rk.text = HudKit.ordinal(int(ranks.get(pid, 1)))
		rk.add_theme_color_override("font_color", HudKit.rank_color(int(ranks.get(pid, 1))))
		var items := card.find_child("Items", true, false) as HBoxContainer
		for c in items.get_children():
			c.queue_free()
		for it in pd.get("items", []):
			var info: Dictionary = Rules.ITEMS.get(String(it), {})
			items.add_child(UiKit.icon(String(info.get("icon", "bag")), info.get("color", Color.WHITE), 24.0 * s))
		var on := pid == cur and String(main.net.state_get("phase", "")) == "board"
		card.modulate = Color(1, 1, 1, 1) if on or cur < 0 else Color(0.82, 0.82, 0.86, 0.92)
		var lift: Control = card.get_meta("lift")
		lift.custom_minimum_size.y = (18.0 if on else 0.0) * s
	if join_pill != null:
		join_pill.visible = ps.size() < 7 and main.net.mode != "host"


func _make_card(pid: int, s: float, w: float) -> PanelContainer:
	var col: Color = main.color_of(pid)
	var holder := VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", 0)
	var card := UiKit.tinted_panel(col, s, "card")
	card.custom_minimum_size.x = w * s
	holder.add_child(card)
	var lift := Control.new()
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lift)
	var v := UiKit.vbox(2, s)
	card.add_child(v)
	var top := UiKit.hbox(6, s)
	v.add_child(top)
	var dot := UiKit.icon("person", col, 24.0 * s)
	top.add_child(dot)
	var nm := UiKit.label("", "body", col.lightened(0.3))
	nm.name = "Name"
	nm.add_theme_font_override("font", UiKit.font(true))
	top.add_child(nm)
	var cpu := UiKit.badge("CPU", "dim", s * 0.8)
	cpu.name = "Cpu"
	top.add_child(cpu)
	top.add_child(UiKit.spacer())
	var rank := UiKit.label("1ST", "small", "accent")
	rank.name = "Rank"
	top.add_child(rank)
	var mid := UiKit.hbox(8, s)
	v.add_child(mid)
	mid.add_child(UiKit.icon("star", "gold", 28.0 * s))
	var st := UiKit.label("0", "number", "gold")
	st.name = "Stars"
	mid.add_child(st)
	mid.add_child(UiKit.spacer(8.0 * s))
	mid.add_child(UiKit.icon("coin", Color(1.0, 0.75, 0.25), 26.0 * s))
	var co := UiKit.label("0", "number")
	co.name = "Coins"
	mid.add_child(co)
	var items := UiKit.hbox(4, s)
	items.name = "Items"
	items.custom_minimum_size.y = 24.0 * s
	v.add_child(items)
	var wrap := PanelContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	wrap.add_child(holder)
	wrap.set_meta("lift", lift)
	return wrap


## pid -> rank (1 = best): stars first, then coins.
static func ranks_of(ps: Array) -> Dictionary:
	var rows: Array = []
	for p in ps:
		var pd: Dictionary = p
		rows.append([int(pd["pid"]), int(pd.get("stars", 0)) * 1000 + int(pd.get("coins", 0))])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var out := {}
	var rank := 0
	var last := -1
	for i in rows.size():
		var r: Array = rows[i]
		if int(r[1]) != last:
			rank = i + 1
			last = int(r[1])
		out[int(r[0])] = rank
	return out


func _refresh_turn() -> void:
	var phase := String(main.net.state_get("phase", ""))
	var cur := int(main.net.state_get("cur", -1))
	var step := String(main.net.state_get("step", ""))
	var who: String = main.name_of(cur) if cur >= 0 else ""
	var title := ""
	var hint := ""
	if phase == "board" and cur >= 0:
		title = "%s'S TURN" % who
		hint = _hint_for(step, cur, false)
	if turn_pill != null:
		turn_pill.visible = title != ""
		turn_label.text = title
		if cur >= 0:
			turn_label.add_theme_color_override("font_color", (main.color_of(cur) as Color).lightened(0.25))
		hint_label.text = hint
		hint_label.visible = hint != ""
	if vr_turn != null:
		var vh := _hint_for(step, cur, true) if phase == "board" and cur >= 0 else ""
		vr_turn.text = (title + ("\n" + vh if vh != "" else "")) if title != "" else ""
		if cur >= 0:
			vr_turn.modulate = (main.color_of(cur) as Color).lightened(0.35)


## What the player whose turn it is should do now (for the TV pill or the VR scoreboard).
func _hint_for(step: String, cur: int, vr: bool) -> String:
	var me_vr: bool = vr and main.is_local_vr(cur)
	var me_tv: bool = (not vr) and main.is_local_tv(cur)
	var who: String = main.name_of(cur)
	match step:
		"roll":
			var d: Dictionary = main.net.state_get("dice", {})
			if String(d.get("mode", "")) == "vr":
				return "Grab the dice with the TRIGGER and THROW it!" if me_vr else "The Giant throws the dice!"
			if me_tv:
				return "Press A to hit the dice block!"
			return "%s rolls the dice..." % who
		"move":
			return "%d to go!" % int(main.net.state_get("steps_left", 0))
		"branch":
			if me_vr:
				return "Point at an arrow and pull the TRIGGER"
			if me_tv:
				return "Pick a path with the STICK, then A"
			return "%s picks a path..." % who
		"menu":
			return "Choose with your controller!" if (me_tv or me_vr) else "%s is choosing..." % who
		"event":
			return "Something is happening!"
		"duel":
			return "QUICK DRAW DUEL!"
		"item":
			return "Item time!"
	return ""


func _refresh_round() -> void:
	var r := int(main.net.state_get("round", 0))
	var n := int(main.net.state_get("rounds", 10))
	var phase := String(main.net.state_get("phase", "title"))
	var text := "PARTY BOARD" if r <= 0 or phase == "title" else "ROUND %d / %d" % [mini(r, n), n]
	if round_label != null:
		round_label.text = text
		final_badge.visible = bool(main.net.state_get("final", false)) and phase != "title"
	if vr_title != null:
		vr_title.text = text + ("   FINAL TURNS!" if bool(main.net.state_get("final", false)) and phase != "title" else "")


func _refresh_title() -> void:
	var phase := String(main.net.state_get("phase", "title"))
	if title_box != null:
		title_box.visible = phase == "title"
		var lines: PackedStringArray = []
		for p in main.roster():
			var pd: Dictionary = p
			lines.append("%s%s" % [String(pd.get("name", "")), "  (CPU)" if bool(pd.get("cpu", false)) else ""])
		var cfg: Dictionary = main.net.state_get("settings", {})
		title_roster.text = "\n".join(lines) + "\n\n%d TURNS     KID MODE %s" % [int(cfg.get("turns", 10)), "ON" if bool(cfg.get("kid", false)) else "OFF"]
		var st: Dictionary = main.net.state_get("saved", {})
		title_stats.text = "Parties played: %d     Giant wins: %d     Record: %d stars" % [int(st.get("parties", 0)),
			int(st.get("giant_wins", 0)), int(st.get("best_stars", 0))]
	if cards_row != null:
		cards_row.visible = phase in ["board", "intro", "title"]


# --- VR -------------------------------------------------------------------------------------------

func _build_vr() -> void:
	var rig: Node3D = main.vr_rig
	vr_board = Node3D.new()
	vr_board.name = "VrScoreboard"
	main.add_child(vr_board)
	vr_board.position = Vector3(0.0, main.TABLE_Y + 0.72, -1.32)
	var bg := UiKit.panel3d(Vector2(1.7, 1.12), UiKit.BG)
	bg.position = Vector3(0, 0, -0.01)
	vr_board.add_child(bg)
	var b := MeshKit.Builder.new()
	b.cylinder(0.025, 0.025, main.TABLE_Y + 0.2, MeshKit.at(Vector3(-0.75, -(main.TABLE_Y + 0.2) * 0.5 - 0.5, -0.03)), Color(0.55, 0.38, 0.25), 8)
	b.cylinder(0.025, 0.025, main.TABLE_Y + 0.2, MeshKit.at(Vector3(0.75, -(main.TABLE_Y + 0.2) * 0.5 - 0.5, -0.03)), Color(0.55, 0.38, 0.25), 8)
	vr_board.add_child(MeshKit.instance(b.build(), false))
	vr_title = UiKit.label3d("PARTY BOARD", 0.07, "accent", true)
	vr_title.position = Vector3(0, 0.45, 0)
	vr_board.add_child(vr_title)
	vr_turn = UiKit.label3d("", 0.055, "text", true, 1.6)
	vr_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vr_turn.position = Vector3(0, 0.3, 0)
	vr_board.add_child(vr_turn)
	for i in 7:
		var l := UiKit.label3d("", 0.05, "text", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector3(-0.66, 0.13 - i * 0.092, 0)
		l.visible = false
		vr_board.add_child(l)
		vr_rows.append(l)
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.024
		sm.height = 0.048
		sm.radial_segments = 10
		sm.rings = 5
		dot.mesh = sm
		dot.position = Vector3(-0.72, 0.13 - i * 0.092, 0)
		dot.visible = false
		vr_board.add_child(dot)
		vr_dots.append(dot)
	# Coins and stars on the back of the left glove, kept to the RIGHT of the hand: core/net.gd's MENU
	# button sits at (-0.15, 0.02, 0.12) from the left controller and they overlapped (play-test).
	# Short lines (max ~9 characters, ~0.11 m wide) centred at x = +0.06 stay > 0.14 m from it.
	glove_label = UiKit.label3d("", 0.022, "gold", true)
	glove_label.position = GLOVE_POS
	glove_label.rotation = Vector3(-1.2, 0.0, 0.0)
	rig.hand_l.add_child(glove_label)


func _refresh_vr() -> void:
	if vr_board == null:
		return
	var ps: Array = main.roster()
	var ranks := ranks_of(ps)
	var cur := int(main.net.state_get("cur", -1))
	for i in vr_rows.size():
		var l := vr_rows[i]
		var dot := vr_dots[i]
		if i >= ps.size():
			l.visible = false
			dot.visible = false
			continue
		var pd: Dictionary = ps[i]
		var pid := int(pd["pid"])
		var items: Array = pd.get("items", [])
		var you := " (YOU)" if pid == 0 else ""
		l.text = "%s  %-12s  STARS %d   COINS %d%s" % [HudKit.ordinal(int(ranks.get(pid, 1))),
			String(pd.get("name", "")) + you + (" CPU" if bool(pd.get("cpu", false)) else ""), int(pd.get("stars", 0)),
			int(pd.get("coins", 0)), ("   ITEMS %d" % items.size()) if not items.is_empty() else ""]
		l.modulate = (main.color_of(pid) as Color).lightened(0.35) if pid == cur else Color(0.95, 0.95, 0.95)
		l.visible = true
		dot.material_override = MeshKit.material(main.color_of(pid), 1.0)
		dot.visible = true
	var me: Dictionary = main.player(0)
	if glove_label != null:
		var its: PackedStringArray = []
		for it in me.get("items", []):
			its.append(Rules.item_name(String(it)))
		glove_label.text = "COINS %d\nSTARS %d%s" % [int(me.get("coins", 0)), int(me.get("stars", 0)),
			("\nITEMS %d" % its.size()) if not its.is_empty() else ""] if not me.is_empty() else ""


## Hide the VR scoreboard while a minigame shows its own.
func set_vr_board_visible(on: bool) -> void:
	if vr_board != null:
		vr_board.visible = on


# --- 3D marker over the current token -----------------------------------------------------------------

func _build_3d() -> void:
	marker = Node3D.new()
	marker.name = "TurnMarker"
	var b := MeshKit.Builder.new()
	b.cone(0.38, 0.6, MeshKit.at(Vector3(0, 0, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(1, 1, 1), 10, true)
	b.torus(0.32, 0.06, MeshKit.at(Vector3(0, 0.32, 0)), Color(1, 1, 1), 14, 5, true)
	var mi := MeshKit.instance(b.build(), false)
	mi.name = "Mesh"
	marker.add_child(mi)
	marker.visible = false
	main.stage.add_child(marker)
	steps_label = UiKit.label3d("", 0.9, Color(1, 1, 1), true)
	steps_label.outline_size = 18
	if main.vr_rig == null:
		steps_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	steps_label.visible = false
	main.stage.add_child(steps_label)


func _process(delta: float) -> void:
	_t += delta
	var cur := int(main.net.state_get("cur", -1))
	var phase := String(main.net.state_get("phase", ""))
	var show: bool = cur >= 0 and phase == "board" and main.tokens.has(cur)
	marker.visible = show
	if show:
		var t: Node3D = main.tokens[cur]
		if cur != _marker_pid:
			_marker_pid = cur
			var mi := marker.get_node("Mesh") as MeshInstance3D
			mi.material_override = MeshKit.material(main.color_of(cur), 1.5)
		marker.position = t.position + Vector3(0, 2.75 + 0.18 * sin(_t * 4.0), 0)
		marker.rotation.y += delta * 2.0
		var left := int(main.net.state_get("steps_left", 0))
		steps_label.visible = left > 0 and String(main.net.state_get("step", "")) in ["move", "branch", "menu"]
		steps_label.text = str(left)
		steps_label.position = t.position + Vector3(0, 3.7, 0)
		if main.vr_rig != null:  # VR: turn on Y only towards the head (a Label3D reads from +Z)
			var d: Vector3 = steps_label.global_position - main.vr_rig.camera.global_position
			steps_label.global_basis = Basis(Vector3.UP, atan2(-d.x, -d.z)).scaled(steps_label.global_basis.get_scale())
	else:
		steps_label.visible = false


# --- Replicated state -------------------------------------------------------------------------------

func on_state(key: String, _value: Variant) -> void:
	match key:
		"players":
			_refresh_cards()
			_refresh_vr()
			_refresh_title()
		"cur", "step", "dice", "steps_left":
			_refresh_turn()
			_refresh_cards()
			_refresh_vr()
		"round", "rounds", "final":
			_refresh_round()
		"phase":
			_refresh_round()
			_refresh_title()
			_refresh_turn()
			_refresh_cards()
			set_vr_board_visible(String(_value) != "minigame")
		"settings", "saved":
			_refresh_title()


# --- Banners and toasts (every screen on this machine) ------------------------------------------------

func banner(title: String, sub: String, style: String = "default", dur: float = 2.4) -> void:
	if main.tv_ui != null:
		HudKit.banner(main.tv_ui, title, sub, {"style": style, "duration": dur})
	if main.vr_rig != null:
		HudKit.vr_banner(main, main.vr_rig.camera, title, sub, main.vr_ui_opts(0.4, {"style": style, "duration": dur,
			"sound": "" if main.tv_ui != null else HudKit.BANNER_STYLES.get(style, HudKit.BANNER_STYLES["default"])[2]}, 0.15))


func toast(text: String, pid: int = -1, icon: String = "") -> void:
	if main.tv_ui != null:
		HudKit.toast(main.tv_ui, text, {"color": pid if pid >= 0 else "accent", "icon": icon})
	if main.vr_rig != null:
		HudKit.vr_toast(main, main.vr_rig.camera, text, main.vr_ui_opts(0.15,
			{"color": main.color_of(pid) if pid >= 0 else UiKit.ACCENT}, -0.25))


