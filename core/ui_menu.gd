extends PanelContainer
## Controller-navigable TV menu bound to ONE player's input, so up to 6 players can each drive their own
## menu at once (split screen or a shared screen). Vertical lists, grids, tabs, scrolling, disabled items
## with reasons, descriptions, confirm/cancel, sounds, mouse hover/click and keyboard.
##
##   const UiMenu := preload("res://core/ui_menu.gd")
##   var m := UiMenu.open(ui_root, {"title": "COMMAND", "player": 2, "device": joy, "keys": UiMenu.KEYS_NONE,
##       "items": [{"id": "attack", "text": "Attack", "icon": "sword"},
##                 {"id": "fire", "text": "Fireball", "right": "6 MP", "disabled": true, "reason": "Not enough MP"},
##                 "Run"]})
##   m.chosen.connect(func(id: String, item: Dictionary) -> void: print(id))
##   # with core/party.gd (the usual way): {"party": party, "slot": slot, "items": [...]}
##
## Items: a String, or a Dictionary with id, text, desc, disabled, reason, icon, icon_color, right
## (right-aligned detail), badge, badge_color, color, data (anything). Tabs: opts "tabs" =
## [{"title": "ITEMS", "items": [...]}, ...]. Input: `device` (joypad id, PAD_ANY or PAD_NONE) and `keys`
## (KEYS_WASD, KEYS_ARROWS, KEYS_ALL or KEYS_NONE); bots and the network can call press("down") etc.
## The VR equivalent is core/vr_menu.gd (UiMenu.vr(...) makes one).

signal chosen(id: String, item: Dictionary)      ## a usable item was confirmed
signal cancelled()                                ## B / back
signal rejected(id: String, item: Dictionary)     ## tried to confirm a disabled item
signal focus_changed(id: String, item: Dictionary)
signal tab_changed(index: int)
signal closed()

const UiKit := preload("res://core/ui_kit.gd")
const Me := preload("res://core/ui_menu.gd")
const VrMenuScript := preload("res://core/vr_menu.gd")

const UiInput := preload("res://core/ui_input.gd")

const PAD_NONE := UiInput.PAD_NONE        ## no controller
const PAD_ANY := UiInput.PAD_ANY          ## any controller (shared "press A" screens)
const KEYS_NONE := UiInput.KEYS_NONE      ## no keyboard
const KEYS_WASD := UiInput.KEYS_WASD      ## WASD move, Space/F confirm, X/Backspace back, Q/E tabs
const KEYS_ARROWS := UiInput.KEYS_ARROWS  ## arrows move, Enter confirm, Backspace/Delete back, PgUp/PgDn tabs
const KEYS_ALL := UiInput.KEYS_ALL        ## both key sets

# --- Options (set via setup()/open() or directly before adding to the tree) ---
var party: Node = null            ## core/party.gd: read this seat's input through the party (see bind_party)
var slot := -1                    ## the party seat driving this menu
var device := PAD_NONE
var keys := KEYS_ALL
var mouse := true                 ## hover/click items with the mouse
var title_text := ""
var player := -1                  ## player index: tints the menu and shows a "P3" badge (-1 = none)
var accent := UiKit.ACCENT        ## focus colour (player colour when `player` is set)
var columns := 1                  ## > 1 = grid
var wrap := true                  ## wrap around at the ends
var max_rows := 6                 ## visible rows before scrolling
var width := 560.0                ## at UI scale 1
var close_on_choose := true
var allow_cancel := true
var free_on_close := true
var show_prompts := true
var show_desc := -1               ## -1 auto (when any item has desc/reason), 0 no, 1 yes
var sounds := true
var anchor := "center"            ## center, top, bottom, left, right, top_left, top_right, bottom_left, bottom_right, none
var margin := 36.0                ## distance from the view edge for edge anchors (scale 1)
var cancel_text := "Back"
var confirm_text := "Select"
var input_enabled := true         ## false = only press()/choose() drive it (e.g. a remote mirror)

# --- State ---
var tabs: Array = []              ## [{"title": String, "items": Array}]
var tab := 0
var items: Array = []             ## normalised items of the current tab
var index := 0
var reader: UiInput
var is_open := false

var _vbox: VBoxContainer
var _header: HBoxContainer
var _title_label: Label
var _tab_row: HBoxContainer
var _scroll: ScrollContainer
var _grid: GridContainer
var _up_arrow: Control
var _down_arrow: Control
var _desc_panel: PanelContainer
var _desc_label: Label
var _prompts: Control
var _rows: Array[Control] = []
var _sb_item: StyleBoxFlat
var _sb_focus: StyleBoxFlat
var _sb_off: StyleBoxFlat
var _sb_off_focus: StyleBoxFlat
var _s := 1.0
var _scroll_tween: Tween
var _close_tween: Tween
var _built := false
var _start_focus: Variant = null


# --- Construction ----------------------------------------------------------------------------------

## Make a menu with `opts` (see setup), add it under `parent` (ideally a UiKit.ui_root) and open it.
static func open(parent: Node, opts: Dictionary) -> Me:
	var m: Me = Me.new()
	m.setup(opts)
	parent.add_child(m)
	return m


## Make a VR menu (core/vr_menu.gd) under `world`: opts as for setup plus cam, hand, distance, height.
static func vr(world: Node, opts: Dictionary) -> Node3D:
	var m: Node3D = VrMenuScript.new()
	m.call("setup", opts)
	world.add_child(m)
	return m


## Configure from a Dictionary: title, items, tabs, columns, party + slot (a core/party.gd seat drives
## it; the usual way), or device + keys (a raw joypad id / key set), mouse, player, width,
## max_rows, close_on_choose, allow_cancel, free_on_close, prompts, desc, wrap, anchor, margin,
## start (id or index to focus first), sounds, cancel_text, confirm_text, accent.
func setup(opts: Dictionary) -> Me:
	title_text = String(opts.get("title", title_text))
	if opts.has("party"):
		party = opts["party"]
		slot = int(opts.get("slot", slot))
		if not opts.has("player") and player < 0:
			player = slot
	device = int(opts.get("device", device))
	keys = int(opts.get("keys", keys))
	mouse = bool(opts.get("mouse", mouse))
	player = int(opts.get("player", player))
	columns = maxi(1, int(opts.get("columns", columns)))
	wrap = bool(opts.get("wrap", wrap))
	max_rows = maxi(1, int(opts.get("max_rows", max_rows)))
	width = float(opts.get("width", width if columns == 1 else maxf(width, 150.0 * columns + 80.0)))
	close_on_choose = bool(opts.get("close_on_choose", close_on_choose))
	allow_cancel = bool(opts.get("allow_cancel", allow_cancel))
	free_on_close = bool(opts.get("free_on_close", free_on_close))
	show_prompts = bool(opts.get("prompts", show_prompts))
	if opts.has("desc"):
		show_desc = 1 if bool(opts["desc"]) else 0
	sounds = bool(opts.get("sounds", sounds))
	anchor = String(opts.get("anchor", anchor))
	margin = float(opts.get("margin", margin))
	cancel_text = String(opts.get("cancel_text", cancel_text))
	confirm_text = String(opts.get("confirm_text", confirm_text))
	input_enabled = bool(opts.get("input", input_enabled))
	if player >= 0:
		accent = UiKit.player_color(player)
	if opts.has("accent"):
		accent = UiKit.color_of(opts["accent"], accent)
	if opts.has("tabs"):
		tabs = []
		for t in opts["tabs"]:
			var td: Dictionary = t
			tabs.append({"title": String(td.get("title", "")), "items": normalize(td.get("items", []))})
	elif opts.has("items"):
		tabs = [{"title": "", "items": normalize(opts["items"])}]
	_start_focus = opts.get("start", null)
	if _built:
		_rebuild_all()
	return self


## Turn Strings / partial Dictionaries into full item Dictionaries (see UiKit.normalize_items).
static func normalize(list: Variant) -> Array:
	return UiKit.normalize_items(list)


func _ready() -> void:
	theme_type_variation = "PanelContainer"
	mouse_filter = Control.MOUSE_FILTER_STOP if mouse else Control.MOUSE_FILTER_IGNORE
	if get_theme_constant("scale_pct", "UiKit") <= 0:
		theme = UiKit.theme(UiKit.scale_for_size(get_viewport().get_visible_rect().size))  # not under a UiRoot
	reader = _make_reader()
	_build()
	_built = true
	_rebuild_all()
	open_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _built and absf(UiKit.scale_of(self) - _s) > 0.01:
		_rebuild_all()  # the view was resized (e.g. split screen re-layout): restyle at the new scale
	elif what == NOTIFICATION_EXIT_TREE:
		_set_busy(false)


func _input(event: InputEvent) -> void:
	if reader != null:
		reader.note_event(event)


# --- Public API ------------------------------------------------------------------------------------

## Drive this menu from a core/party.gd seat (its pad or keyboard, with the party's join/unpause
## guards). The menu takes the seat's colour and "P3" badge unless `player` was set.
func bind_party(p_party: Node, p_slot: int) -> void:
	_set_busy(false)
	party = p_party
	slot = p_slot
	if player < 0:
		player = p_slot
		accent = UiKit.player_color(p_slot)
	if reader != null:
		reader = _make_reader()
		reader.latch()
	if is_open:
		_set_busy(true)
	if _built:
		_rebuild_all()


## True while an open menu is driven by this party seat (games: skip that seat's gameplay input).
static func slot_busy(p_slot: int) -> bool:
	if not Engine.has_meta("ui_menu_busy"):
		return false
	var d: Dictionary = Engine.get_meta("ui_menu_busy")
	return int(d.get("slot:%d" % p_slot, 0)) > 0


## Show (again) with a pop-in, latch held buttons (a held A from the last screen must not confirm).
func open_menu() -> void:
	if _close_tween != null and _close_tween.is_valid():
		_close_tween.kill()  # re-opened while closing
	visible = true
	is_open = true
	_set_busy(true)
	if reader != null:
		reader.latch()
	UiKit.pop_in(self, 0.0, 0.9, 0.26)
	_sound("ui_open")


## Close (pop-out, then free unless free_on_close is false).
func close() -> void:
	if not is_open:
		return
	is_open = false
	_set_busy(false)
	closed.emit()
	var t := UiKit.pop_out(self, false, 0.0, 0.18)
	_close_tween = t
	t.chain().tween_callback(func() -> void:
		visible = false
		if free_on_close:
			queue_free())


## Inject an action as if pressed: "up", "down", "left", "right", "confirm", "cancel", "tab_prev",
## "tab_next" (bots, network mirrors, on-screen buttons).
func press(action: String) -> void:
	if not is_open:
		return
	match action:
		"up":
			_move(0, -1)
		"down":
			_move(0, 1)
		"left":
			if columns > 1:
				_move(-1, 0)
			elif tabs.size() > 1:
				set_tab(tab - 1)
		"right":
			if columns > 1:
				_move(1, 0)
			elif tabs.size() > 1:
				set_tab(tab + 1)
		"confirm":
			confirm()
		"cancel":
			cancel()
		"tab_prev":
			set_tab(tab - 1)
		"tab_next":
			set_tab(tab + 1)


## Confirm the focused item (or `at` index).
func confirm(at: int = -1) -> void:
	if items.is_empty() or not is_open:
		return
	if at >= 0:
		focus(at)
	var it: Dictionary = items[index]
	if it.disabled:
		_sound("ui_error")
		if index < _rows.size():
			UiKit.shake(_rows[index])
		_show_desc(it, true)
		rejected.emit(String(it.id), it)
		return
	_sound("ui_select")
	if index < _rows.size():
		UiKit.pulse(_rows[index])
	chosen.emit(String(it.id), it)
	if close_on_choose:
		close()


## Cancel (if allowed).
func cancel() -> void:
	if not allow_cancel:
		return
	_sound("ui_back")
	cancelled.emit()
	close()


## Focus an item by index (clamped) or by id (String).
func focus(which: Variant) -> void:
	var i := -1
	if which is String or which is StringName:
		for k in items.size():
			if String(items[k].id) == String(which):
				i = k
				break
	else:
		i = int(which)
	if i < 0 or items.is_empty():
		return
	i = clampi(i, 0, items.size() - 1)
	var changed := i != index
	index = i
	_refresh_focus()
	if changed:
		focus_changed.emit(String(items[index].id), items[index])


## Programmatically choose by id (as if the player confirmed it).
func choose_id(id: String) -> void:
	focus(id)
	confirm()


## Switch tab (wraps).
func set_tab(i: int) -> void:
	if tabs.size() <= 1:
		return
	var n := posmod(i, tabs.size())
	if n == tab:
		return
	tab = n
	index = 0
	_sound("ui_move", -2.0, 1.15)
	_rebuild_all()
	tab_changed.emit(tab)


## Replace the items of the current tab (keeps focus on the same index when possible).
func set_items(list: Array) -> void:
	if tabs.is_empty():
		tabs = [{"title": "", "items": []}]
	tabs[tab]["items"] = normalize(list)
	if _built:
		_rebuild_all()


## Enable/disable one item by id, with a reason shown when someone tries it.
func set_disabled(id: String, disabled: bool, reason: String = "") -> void:
	for it in items:
		if String(it.id) == id:
			it["disabled"] = disabled
			it["reason"] = reason
	_rebuild_items()


## The focused item's id ("" when empty).
func focused_id() -> String:
	return "" if items.is_empty() else String(items[index].id)


## True while any open menu holds this controller (games: skip gameplay input for that pad).
static func device_busy(dev: int) -> bool:
	if not Engine.has_meta("ui_menu_busy"):
		return false
	var d: Dictionary = Engine.get_meta("ui_menu_busy")
	return int(d.get(dev, 0)) > 0 or int(d.get(PAD_ANY, 0)) > 0


# --- Building --------------------------------------------------------------------------------------

func _build() -> void:
	_vbox = UiKit.vbox()
	add_child(_vbox)
	_header = UiKit.hbox()
	_vbox.add_child(_header)
	_title_label = UiKit.label("", "heading")
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_title_label)
	_tab_row = UiKit.hbox(8)
	_vbox.add_child(_tab_row)
	_up_arrow = UiKit.icon("arrow_up", "dim", 18.0)
	_up_arrow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vbox.add_child(_up_arrow)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if mouse else Control.MOUSE_FILTER_IGNORE
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_arrows())
	_vbox.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_grid)
	_down_arrow = UiKit.icon("arrow_down", "dim", 18.0)
	_down_arrow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vbox.add_child(_down_arrow)
	_desc_panel = UiKit.panel("tooltip")
	_vbox.add_child(_desc_panel)
	_desc_label = UiKit.paragraph("", "small", "dim")
	_desc_panel.add_child(_desc_label)


func _restyle() -> void:
	_s = UiKit.scale_of(self)
	var a := accent
	_sb_item = UiKit.stylebox(Color(1, 1, 1, 0.035), _s, 12.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(14, 9))
	_sb_focus = UiKit.stylebox(Color(a.r, a.g, a.b, 0.2), _s, 12.0, a, 3.0, 0.0, Vector2(14, 9))
	_sb_off = UiKit.stylebox(Color(1, 1, 1, 0.015), _s, 12.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(14, 9))
	_sb_off_focus = UiKit.stylebox(Color(1, 1, 1, 0.05), _s, 12.0, UiKit.TEXT_OFF, 3.0, 0.0, Vector2(14, 9))
	if player >= 0:
		add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.BG, _s, 20.0, a, 3.0, 16.0, Vector2(22, 18)))
	var vw := get_viewport().get_visible_rect().size.x if is_inside_tree() else 1920.0
	custom_minimum_size.x = minf(width * _s, vw * 0.94)
	_apply_anchor()


func _apply_anchor() -> void:
	var m := margin * _s
	var presets := {"center": Control.PRESET_CENTER, "top": Control.PRESET_CENTER_TOP, "bottom": Control.PRESET_CENTER_BOTTOM,
		"left": Control.PRESET_CENTER_LEFT, "right": Control.PRESET_CENTER_RIGHT, "top_left": Control.PRESET_TOP_LEFT,
		"top_right": Control.PRESET_TOP_RIGHT, "bottom_left": Control.PRESET_BOTTOM_LEFT, "bottom_right": Control.PRESET_BOTTOM_RIGHT}
	if not presets.has(anchor) or not (get_parent() is Control) or get_parent() is Container:
		return
	var p: int = presets[anchor]
	set_anchors_preset(p)
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	if anchor.contains("left"):
		grow_horizontal = Control.GROW_DIRECTION_END
		offset_left = m
		offset_right = m
	elif anchor.contains("right"):
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		offset_left = -m
		offset_right = -m
	if anchor.begins_with("top"):
		grow_vertical = Control.GROW_DIRECTION_END
		offset_top = m
		offset_bottom = m
	elif anchor.begins_with("bottom"):
		grow_vertical = Control.GROW_DIRECTION_BEGIN
		offset_top = -m
		offset_bottom = -m
	size = Vector2.ZERO  # shrink to the minimum, growing in the chosen directions


func _rebuild_all() -> void:
	_restyle()
	if tabs.is_empty():
		tabs = [{"title": "", "items": []}]
	tab = clampi(tab, 0, tabs.size() - 1)
	items = tabs[tab]["items"]
	_title_label.text = title_text
	_title_label.visible = title_text != ""
	for c in _header.get_children():
		if c != _title_label:
			c.queue_free()
	if player >= 0:
		var b := UiKit.badge("P%d" % (player + 1), accent, _s)
		_header.add_child(b)
		_header.move_child(b, 0)
	_header.visible = _title_label.visible or player >= 0
	# tabs
	for c in _tab_row.get_children():
		c.queue_free()
	_tab_row.visible = tabs.size() > 1
	if tabs.size() > 1:
		_tab_row.add_child(UiKit.glyph(_tab_key(true), _s))
		for i in tabs.size():
			var on := i == tab
			var pill := PanelContainer.new()
			pill.mouse_filter = Control.MOUSE_FILTER_STOP if mouse else Control.MOUSE_FILTER_IGNORE
			pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var c := accent if on else Color(1, 1, 1, 0.0)
			pill.add_theme_stylebox_override("panel", UiKit.stylebox(Color(c.r, c.g, c.b, 0.85) if on else Color(1, 1, 1, 0.05),
				_s, 200.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(12, 4)))
			var l := UiKit.label(String(tabs[i]["title"]), "small", Color(0.05, 0.05, 0.1) if on else UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
			if on:
				l.add_theme_constant_override("outline_size", 0)
				l.add_theme_font_override("font", UiKit.font(true))
			pill.add_child(l)
			var ti := i
			pill.gui_input.connect(func(ev: InputEvent) -> void:
				var mb := ev as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					set_tab(ti))
			_tab_row.add_child(pill)
		_tab_row.add_child(UiKit.glyph(_tab_key(false), _s))
	if _start_focus != null:
		var sf: Variant = _start_focus
		_start_focus = null
		index = 0
		_rebuild_items()
		focus(sf)
	else:
		index = clampi(index, 0, maxi(0, items.size() - 1))
		_rebuild_items()
	_rebuild_prompts()


func _tab_key(prev: bool) -> String:
	return String(_glyphs()["tab_prev" if prev else "tab_next"])


func _glyphs() -> Dictionary:
	return reader.glyphs() if reader != null else _make_reader().glyphs()


func _make_reader() -> UiInput:
	if party != null:
		return UiInput.for_party(party, slot)
	return UiInput.new(device, keys)


func _rebuild_items() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_rows.clear()
	_grid.columns = columns
	var grid_mode := columns > 1
	for i in items.size():
		var it: Dictionary = items[i]
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP if mouse else Control.MOUSE_FILTER_IGNORE
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var off: bool = it.disabled
		var text_col: Color = UiKit.TEXT_OFF if off else UiKit.color_of(it.get("color", null), UiKit.TEXT)
		if grid_mode:
			var cell := UiKit.vbox(4, _s)
			cell.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_child(cell)
			if String(it.icon) != "":
				var ic := UiKit.icon(String(it.icon), it.get("icon_color", "text") if not off else "off", 44.0 * _s)
				ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				cell.add_child(ic)
			var l := UiKit.label(String(it.text), "small", text_col, HORIZONTAL_ALIGNMENT_CENTER)
			l.name = "Text"
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.custom_minimum_size.x = 60.0 * _s
			cell.add_child(l)
			if String(it.badge) != "" or String(it.right) != "":
				var bt := String(it.badge) if String(it.badge) != "" else String(it.right)
				var bd := UiKit.badge(bt, it.get("badge_color", "accent") if not off else "off", _s)
				bd.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				cell.add_child(bd)
			row.custom_minimum_size = Vector2(0, 112.0 * _s)
		else:
			var h := UiKit.hbox(10, _s)
			row.add_child(h)
			var cur := UiKit.icon("play", accent, 18.0 * _s)
			cur.name = "Cursor"
			cur.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cur.modulate.a = 0.0
			h.add_child(cur)
			if String(it.icon) != "":
				var ic := UiKit.icon(String(it.icon), it.get("icon_color", "text") if not off else "off", 30.0 * _s)
				ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(ic)
			var l := UiKit.label(String(it.text), "body", text_col)
			l.name = "Text"
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			h.add_child(l)
			if String(it.right) != "":
				h.add_child(UiKit.label(String(it.right), "small", UiKit.TEXT_OFF if off else UiKit.TEXT_DIM))
			if String(it.badge) != "":
				var bd := UiKit.badge(String(it.badge), it.get("badge_color", "accent") if not off else "off", _s)
				bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(bd)
			if off:
				var lock := UiKit.icon("lock", "off", 22.0 * _s)
				lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(lock)
		var ii := i
		if mouse:
			row.mouse_entered.connect(func() -> void:
				if is_open and ii != index:
					_sound("ui_move", -4.0)
					focus(ii))
			row.gui_input.connect(func(ev: InputEvent) -> void:
				var mb := ev as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and is_open:
					confirm(ii))
		_grid.add_child(row)
		_rows.append(row)
	if items.is_empty():
		var empty := UiKit.label("(nothing here)", "small", "dim", HORIZONTAL_ALIGNMENT_CENTER)
		_grid.add_child(empty)
	var want_desc := show_desc == 1
	if show_desc == -1:
		for it in items:
			if String(it.desc) != "" or String(it.reason) != "":
				want_desc = true
	_desc_panel.visible = want_desc
	_desc_label.custom_minimum_size = Vector2(0, UiKit.font_size("small", _s) * 2.6)
	_refresh_focus(false)
	_fit_scroll.call_deferred()


func _rebuild_prompts() -> void:
	if _prompts != null and is_instance_valid(_prompts):
		_prompts.queue_free()
	_prompts = null
	if not show_prompts:
		return
	var g := _glyphs()
	var ok := String(g["confirm"])
	var back := String(g["cancel"])
	var pairs: Array = [[ok, confirm_text]]
	if allow_cancel:
		pairs.append([back, cancel_text])
	_prompts = UiKit.prompts(pairs, _s)
	_vbox.add_child(_prompts)


func _fit_scroll() -> void:
	if _rows.is_empty() or not is_instance_valid(_scroll):
		_scroll.custom_minimum_size.y = 0.0
		_update_arrows()
		return
	var rh := _rows[0].get_combined_minimum_size().y
	var sep := float(_grid.get_theme_constant("v_separation"))
	var rows_total := ceili(float(_rows.size()) / columns)
	var vh := get_viewport().get_visible_rect().size.y if is_inside_tree() else 1080.0
	var fit := maxi(2, int(vh * 0.6 / (rh + sep)))
	var shown := mini(rows_total, mini(max_rows, fit))
	_scroll.custom_minimum_size.y = shown * rh + maxi(0, shown - 1) * sep
	_ensure_visible(false)
	_update_arrows()


func _update_arrows() -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	var max_scroll := bar.max_value - bar.page
	_up_arrow.modulate.a = 1.0 if _scroll.scroll_vertical > 1 else 0.0
	_down_arrow.modulate.a = 1.0 if max_scroll > 1.0 and _scroll.scroll_vertical < max_scroll - 1.0 else 0.0
	var scrolling := max_scroll > 1.0
	_up_arrow.visible = scrolling
	_down_arrow.visible = scrolling


func _ensure_visible(animate: bool = true) -> void:
	if index >= _rows.size() or _scroll == null:
		return
	var row := _rows[index]
	var top := row.position.y
	var bottom := top + row.size.y
	var view_h := _scroll.size.y
	if view_h <= 1.0:
		view_h = _scroll.custom_minimum_size.y
	var target := float(_scroll.scroll_vertical)
	if top < target:
		target = top
	elif bottom > target + view_h:
		target = bottom - view_h
	if absf(target - _scroll.scroll_vertical) < 1.0:
		return
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	if animate:
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_scroll.scroll_vertical = int(target)


func _refresh_focus(animate: bool = true) -> void:
	for i in _rows.size():
		var row := _rows[i]
		var on := i == index and is_open
		var off: bool = items[i].disabled
		var sb: StyleBoxFlat
		if off:
			sb = _sb_off_focus if on else _sb_off
		else:
			sb = _sb_focus if on else _sb_item
		row.add_theme_stylebox_override("panel", sb)
		var cur := row.find_child("Cursor", true, false) as Control
		if cur != null:
			cur.modulate.a = 1.0 if on else 0.0
		var l := row.find_child("Text", true, false) as Label
		if l != null and not off:
			if on:
				l.add_theme_color_override("font_color", Color.WHITE)
			else:
				l.add_theme_color_override("font_color", UiKit.color_of(items[i].get("color", null), UiKit.TEXT))
	if index < items.size():
		_show_desc(items[index], false)
	if animate:
		_ensure_visible(true)


func _show_desc(it: Dictionary, highlight_reason: bool) -> void:
	if _desc_label == null:
		return
	var txt := String(it.desc)
	if it.disabled and String(it.reason) != "":
		txt = ("%s\n" % txt if txt != "" else "") + "Can't: " + String(it.reason)
		_desc_label.add_theme_color_override("font_color", UiKit.BAD.lightened(0.25) if highlight_reason else UiKit.TEXT_DIM)
	else:
		_desc_label.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	_desc_label.text = txt


# --- Input -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open or not input_enabled or reader == null:
		return
	for a in reader.poll(delta):
		press(a)


func _move(dx: int, dy: int) -> void:
	if items.is_empty():
		return
	var n := items.size()
	var i := index
	if columns > 1:
		var col := i % columns
		var row := i / columns
		var rows := ceili(float(n) / columns)
		if dx != 0:
			col += dx
			if col < 0 or col >= columns or row * columns + col >= n:
				if not wrap:
					return
				col = (columns - 1 if dx < 0 else 0)
				col = mini(col, n - 1 - row * columns)
		if dy != 0:
			row += dy
			if row < 0 or row >= rows:
				if not wrap:
					return
				row = rows - 1 if dy < 0 else 0
			while row * columns + col >= n and row > 0:
				row -= 1
		i = row * columns + col
	else:
		i += dy
		if i < 0 or i >= n:
			if not wrap:
				return
			i = posmod(i, n)
	if i != index:
		_sound("ui_move", -3.0)
		focus(i)


func _sound(name: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	if sounds:
		UiKit.sound(name, vol, pitch)


func _set_busy(on: bool) -> void:
	if not Engine.has_meta("ui_menu_busy"):
		Engine.set_meta("ui_menu_busy", {})
	var d: Dictionary = Engine.get_meta("ui_menu_busy")
	var was: bool = has_meta("busy_registered")
	var key: Variant = ("slot:%d" % slot) if party != null else device
	if on == was or (party == null and device == PAD_NONE):
		return
	if on:
		set_meta("busy_registered", key)
		d[key] = int(d.get(key, 0)) + 1
	else:
		var old_key: Variant = get_meta("busy_registered")
		remove_meta("busy_registered")
		d[old_key] = maxi(0, int(d.get(old_key, 0)) - 1)


