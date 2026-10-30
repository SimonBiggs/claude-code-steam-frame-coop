extends RefCounted
## The Family Trophy Hall: every story game's friend (Wren, Granny Boo, Nutmeg, Kiko...) with a tiny picture of how
## far the family has grown their world, and today's golden star (done = bright gold star with a tick; still to do =
## a softly glowing star, "play me today"). Pictures and numbers only: little ones can't read yet.
## Data: core/progress.gd (each game's games/<game>/progress.gd reads its own save; no game scene is loaded).
## TV / Deck: the arcade's first tab (a trophy and "★ 3 / 36"), one pressable tile per game, today's stars first.
## VR: vr_panel(), a picture wall beside the game list (drawn into a SubViewport, re-drawn only when it changes).

const UiKit := preload("res://core/ui_kit.gd")
const StoryCard := preload("res://core/story_card.gd")
const Progress := preload("res://core/progress.gd")

const GOLD := Color(1.0, 0.82, 0.3)
const MAX_PICS := 5  # growth pictures on a tile; the number says the rest


## The game ids the hall shows, in arcade order, today's unfinished golden stars first.
static func order(games: Array, rows: Dictionary) -> Array[int]:
	var todo: Array[int] = []
	var done: Array[int] = []
	for i in games.size():
		var id := String(games[i].id)
		if not Progress.has(id):
			continue
		if bool((rows.get(id, {}) as Dictionary).get("daily", false)):
			done.append(i)
		else:
			todo.append(i)
	todo.append_array(done)
	return todo


## How many golden stars are done today, out of how many.
static func stars(rows: Dictionary) -> Vector2i:
	var n := 0
	var of := 0
	for id in Progress.ids():
		of += 1
		if bool((rows.get(id, {}) as Dictionary).get("daily", false)):
			n += 1
	return Vector2i(n, of)


## A picture that draws once and then stands still (dozens of tiles: only the friend in focus moves).
static func still(kind: String, px: float, color: Color) -> Control:
	var p := StoryCard.picture(kind, px, color)
	p.set_process(false)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## The friend on a round coloured disc.
static func friend(id: String, px: float, animate: bool) -> Control:
	var s = Progress.script_of(id)
	var col: Color = s.COLOR
	var disc := PanelContainer.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_stylebox_override("panel", UiKit.stylebox(col.darkened(0.55), 1.0, px, col.lightened(0.2), maxf(2.0, px * 0.04), 0.0, Vector2(px * 0.06, px * 0.06)))
	disc.custom_minimum_size = Vector2(px, px)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pic := StoryCard.picture(String(s.WHO), px * 0.82, col.lightened(0.15)) if animate else still(String(s.WHO), px * 0.82, col.lightened(0.15))
	pic.name = "Friend"
	disc.add_child(pic)
	return disc


## Today's golden star: done = full gold with a tick, to do = a glowing outline that gently pulses.
static func star(done: bool, px: float) -> Control:
	var box := Control.new()
	box.name = "StarDone" if done else "StarToDo"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(px, px)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := UiKit.icon("star", GOLD if done else Color(0.35, 0.3, 0.2, 0.6), px)  # to do: a dark star waiting to light up
	box.add_child(st)
	if done:
		var tick := UiKit.icon("check", Color(0.35, 1.0, 0.45), px * 0.5)
		tick.position = Vector2(px * 0.52, px * 0.52)
		box.add_child(tick)
	else:
		var glow := UiKit.icon("star", Color(GOLD, 0.0), px)
		glow.name = "Glow"
		box.add_child(glow)
		box.ready.connect(func() -> void:
			var tw := glow.create_tween().set_loops()
			tw.tween_property(glow, "color", Color(GOLD, 0.4), 0.8).set_trans(Tween.TRANS_SINE)
			tw.tween_property(glow, "color", Color(GOLD, 0.0), 0.8).set_trans(Tween.TRANS_SINE))
	return box


## How far the family has grown it: up to MAX_PICS little pictures of what grows, then the number.
static func growth(id: String, grown: int, px: float, font: int, max_pics: int = MAX_PICS) -> Control:
	var s = Progress.script_of(id)
	var col: Color = s.COLOR
	var digits := str(grown).length()
	max_pics = maxi(1, max_pics - maxi(0, digits - 2))  # a big number takes the room of a picture or two
	if digits >= 4:
		font = int(font * 0.8)
	var row := HBoxContainer.new()
	row.name = "Growth"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(px * 0.08))
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for k in maxi(1, mini(grown, max_pics)):
		var p := still(String(s.GROWS), px, col)
		if grown <= 0:
			p.modulate = Color(1, 1, 1, 0.5)  # nothing grown yet: a faint promise (0.25 vanished on the dark tile)
		row.add_child(p)
	var num := Label.new()
	num.name = "Grown"
	num.text = str(grown)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_size_override("font_size", font)
	num.add_theme_color_override("font_color", GOLD if grown > 0 else Color(0.6, 0.62, 0.75))
	num.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.12))
	num.add_theme_constant_override("outline_size", maxi(4, font / 6))
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	return row


## The TV / Deck tile, inside the arcade's card Button (600 x 136): screenshot, friend, growth, star.
static func fill_tile(b: Button, id: String, row: Dictionary, thumb: Texture2D) -> void:
	var loaded := Progress.is_loaded(id)  # (not yet: the lobby is still loading the hall a few games a frame; screenshot only)
	var h := HBoxContainer.new()
	h.name = "Hall"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 14)
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -16
	h.offset_top = 12
	h.offset_bottom = -12
	if thumb:
		var pic := TextureRect.new()
		pic.texture = thumb
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(150, 112)
		pic.clip_contents = true
		h.add_child(pic)
	if not loaded:
		return
	var f := friend(id, 108.0, false)
	h.add_child(f)
	var g := growth(id, int(row.get("grown", 0)), 38.0, 40, 3)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(g)
	h.add_child(star(bool(row.get("daily", false)), 76.0))
	# Only the highlighted tile's friend moves (a hall of still pictures costs nothing per frame on a Deck).
	var pic_node := f.get_node("Friend")
	b.focus_entered.connect(func() -> void: pic_node.set_process(true))
	b.focus_exited.connect(func() -> void: pic_node.set_process(false))


## The hall tab: a trophy and today's golden stars "3 / 36" (numbers and pictures, no words).
static func tab(rows: Dictionary, on: bool, colour: Color, big: float = 1.0) -> Control:
	var p := PanelContainer.new()
	p.name = "HallTab"
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour if on else Color(0.1, 0.1, 0.18)
	sb.set_corner_radius_all(int(18 * big))
	sb.content_margin_left = 14 * big
	sb.content_margin_right = 14 * big
	sb.content_margin_top = 4 * big
	sb.content_margin_bottom = 4 * big
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var px := (30.0 if on else 26.0) * big
	h.add_child(UiKit.icon("trophy", Color(0.05, 0.05, 0.1) if on else GOLD, px))
	h.add_child(UiKit.icon("star", GOLD.lightened(0.3) if on else GOLD, px))
	var st := stars(rows)
	var l := Label.new()
	l.name = "Stars"
	l.text = "%d / %d" % [st.x, st.y]
	l.add_theme_font_size_override("font_size", int((26 if on else 22) * big))
	l.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1) if on else GOLD)
	h.add_child(l)
	return p


# --- VR -----------------------------------------------------------------------------------------

const VR_TILE := Vector2(250, 168)
const VR_COLS := 6


## The VR picture wall (a Sprite3D showing a SubViewport). Call vr_update(wall, games, rows, selected) to redraw it.
static func vr_panel() -> Sprite3D:
	var vp := SubViewport.new()
	vp.name = "HallView"
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var s := Sprite3D.new()
	s.name = "HallWall"
	s.add_child(vp)
	s.texture = vp.get_texture()
	s.pixel_size = 0.0016
	s.shaded = false
	s.double_sided = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


static func vr_update(wall: Sprite3D, games: Array, rows: Dictionary, selected: int) -> void:
	var vp := wall.get_node("HallView") as SubViewport
	for c in vp.get_children():
		vp.remove_child(c)
		c.queue_free()
	var list := order(games, rows)
	var n_rows := ceili(float(list.size()) / VR_COLS)
	var pad := 18.0
	var head := 84.0
	var size := Vector2(VR_COLS * (VR_TILE.x + 12) - 12 + pad * 2, head + n_rows * (VR_TILE.y + 12) - 12 + pad * 2)
	vp.size = Vector2i(size)
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.05, 0.05, 0.12, 0.92), 1.0, 28.0, Color(GOLD, 0.6), 4.0, 0.0, Vector2(pad, pad)))
	bg.size = size
	vp.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	bg.add_child(v)
	var top := CenterContainer.new()
	top.custom_minimum_size.y = head - 12
	top.add_child(tab(rows, false, GOLD, 2.0))
	v.add_child(top)
	var grid := GridContainer.new()
	grid.columns = VR_COLS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for i in list:
		var id := String(games[i].id)
		var row: Dictionary = rows.get(id, {})
		var col: Color = Progress.script_of(id).COLOR
		var t := PanelContainer.new()
		t.name = id
		t.custom_minimum_size = VR_TILE
		var on := i == selected
		t.add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.13, 0.12, 0.24) if on else Color(0.08, 0.08, 0.15), 1.0, 16.0,
			col if on else col.darkened(0.45), 6.0 if on else 2.0, 0.0, Vector2(10, 8)))
		grid.add_child(t)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 6)
		t.add_child(tv)
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 8)
		tv.add_child(th)
		var f := friend(id, 92.0, false)
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL | Control.SIZE_SHRINK_BEGIN
		th.add_child(f)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		th.add_child(sp)
		th.add_child(star(bool(row.get("daily", false)), 64.0))
		tv.add_child(growth(id, int(row.get("grown", 0)), 34.0, 34, 4))
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Re-draw a few times while the stars' glow starts and the pictures settle.
	wall.set_meta("hall_redraws", 3)
