extends RefCounted
## Heads-up display pieces in one consistent style, for TV views and VR:
##   banner      big centred title + subtitle with a wipe-in band ("ROUND 2", "VICTORY!")
##   toast       small stacked notifications ("P2 found a key!")
##   popup       3D world popups: damage numbers, crits, heals, "+100" (face the VR player, billboard on TV)
##   bar3d       HP bars that follow 3D objects (one draw call each)
##   scoreboard  standings with animated rank changes and count-up scores
##   countdown   "3, 2, 1, GO!"
##   timer       a clock pill that turns red near the end
##   VrCard      a world-space card (title + body) for VR banners, toasts, summaries
##
##   const HudKit := preload("res://core/hud_kit.gd")
##   HudKit.banner(ui_root, "WAVE 3", "The goblins are angry!")
##   HudKit.damage(self, enemy.global_position + Vector3.UP, 42, true)   # crit
##   var hp := HudKit.bar3d(enemy, {"max": 30, "name": "GOBLIN"}); hp.set_value(12)
##
## TV functions take `root`: a UiKit.ui_root (or any Control), or an Array of roots (every split-screen
## view) - then they return the node made for the first one.

const UiKit := preload("res://core/ui_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const VrText := preload("res://core/vr_text.gd")
const Me := preload("res://core/hud_kit.gd")

## Banner styles: [accent colour, title colour, sound].
const BANNER_STYLES := {
	"default": [UiKit.ACCENT, UiKit.TEXT, "ui_open"],
	"victory": [UiKit.GOLD, Color(1.0, 0.93, 0.6), "fanfare"],
	"defeat": [UiKit.BAD, Color(1.0, 0.75, 0.72), "gameover"],
	"info": [UiKit.INFO, UiKit.TEXT, "ui_open"],
	"boss": [UiKit.MAGIC, Color(1.0, 0.7, 0.85), "alarm"],
	"level": [UiKit.GOOD, Color(0.85, 1.0, 0.85), "level_up"],
}

## Popup styles: [colour, size multiplier, outline colour].
const POPUP_STYLES := {
	"damage": [Color(1.0, 0.42, 0.36), 1.0, Color(0.25, 0.0, 0.0)],
	"crit": [Color(1.0, 0.82, 0.22), 1.55, Color(0.45, 0.05, 0.0)],
	"heal": [UiKit.GOOD, 1.0, Color(0.0, 0.2, 0.05)],
	"score": [UiKit.GOLD, 1.0, Color(0.3, 0.18, 0.0)],
	"xp": [UiKit.MAGIC, 0.9, Color(0.15, 0.0, 0.3)],
	"miss": [UiKit.TEXT_DIM, 0.8, Color(0.05, 0.05, 0.1)],
	"bad": [UiKit.BAD, 1.0, Color(0.2, 0.0, 0.0)],
	"info": [UiKit.TEXT, 0.9, Color(0.02, 0.02, 0.06)],
}


# --- Banners ---------------------------------------------------------------------------------------

## Big centred title (+ optional subtitle) on a band that wipes in, holds, and wipes out.
## opts: style ("default", "victory", "defeat", "info", "boss", "level"), duration (s, 0 = stay until
## dismiss()), color (accent), y (0..1 vertical centre, default 0.36), sound (name or "" for none).
static func banner(root: Variant, title: String, subtitle: String = "", opts: Dictionary = {}) -> Control:
	if root is Array:
		var first: Control = null
		var arr: Array = root
		for r in arr:
			var o := opts.duplicate()
			if first != null:
				o["sound"] = ""
			var b := banner(r, title, subtitle, o)
			if first == null:
				first = b
		return first
	var parent := root as Control
	if parent == null:
		return null
	var style := String(opts.get("style", "default"))
	var st: Array = BANNER_STYLES.get(style, BANNER_STYLES["default"])
	var b := BannerFx.new()
	b.title = title
	b.subtitle = subtitle
	b.accent = UiKit.color_of(opts.get("color", st[0]), st[0])
	b.title_color = st[1]
	b.duration = float(opts.get("duration", 2.6))
	b.y_ratio = float(opts.get("y", 0.36))
	parent.add_child(b)
	var snd := String(opts.get("sound", st[2]))
	if snd != "":
		UiKit.sound(snd)
	return b


# --- Toasts ----------------------------------------------------------------------------------------

## A small notification that slides in and stacks (max 4). opts: color (edge colour, Color / palette
## name / player index), icon (UiKit icon kind), sub (second line), duration (3 s), where ("top_right",
## "top_left", "top", "bottom"), sound ("" none).
static func toast(root: Variant, text: String, opts: Dictionary = {}) -> Control:
	if root is Array:
		var first: Control = null
		var arr: Array = root
		for r in arr:
			var o := opts.duplicate()
			if first != null:
				o["sound"] = ""
			var t := toast(r, text, o)
			if first == null:
				first = t
		return first
	var parent := root as Control
	if parent == null:
		return null
	var s := UiKit.scale_of(parent)
	var where := String(opts.get("where", "top_right"))
	var stack := _toast_stack(parent, where, s)
	var col := UiKit.color_of(opts.get("color", "accent"), UiKit.ACCENT)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match where:  # hug the screen edge the stack sits on
		"top_left":
			holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		"top", "bottom":
			holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_:
			holder.size_flags_horizontal = Control.SIZE_SHRINK_END
	var card := UiKit.tinted_panel(col, s, "toast")
	holder.add_child(card)
	var row := UiKit.hbox(12, s)
	card.add_child(row)
	var ic := String(opts.get("icon", ""))
	if ic != "":
		var icon := UiKit.icon(ic, col, 34.0 * s)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var col_box := UiKit.vbox(0, s)
	row.add_child(col_box)
	var l := UiKit.label(text, "body")
	l.add_theme_font_override("font", UiKit.font(true))
	l.add_theme_font_size_override("font_size", UiKit.font_size("small", s) + int(2 * s))
	col_box.add_child(l)
	var sub := String(opts.get("sub", ""))
	if sub != "":
		col_box.add_child(UiKit.label(sub, "tiny", "dim"))
	stack.add_child(holder)
	if where == "bottom":
		stack.move_child(holder, 0)
	card.resized.connect(func() -> void: holder.custom_minimum_size = card.size)
	card.size = card.get_combined_minimum_size()
	holder.custom_minimum_size = card.size
	var from_x := 60.0 * s * (-1.0 if where == "top_left" else 1.0)
	card.position.x = from_x
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel()
	tw.tween_property(card, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	var dur := float(opts.get("duration", 3.0))
	var out := card.create_tween()
	out.tween_interval(dur)
	out.tween_property(card, "modulate:a", 0.0, 0.3)
	out.tween_callback(holder.queue_free)
	# keep at most 4
	var live: Array[Node] = []
	for c in stack.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	while live.size() > 4:
		var old: Node = live.pop_front() if where != "bottom" else live.pop_back()
		old.queue_free()
	var snd := String(opts.get("sound", "ui_open"))
	if snd != "":
		UiKit.sound(snd, -4.0, 1.2)
	return holder


static func _toast_stack(parent: Control, where: String, s: float) -> VBoxContainer:
	var n := "HudToasts_" + where
	var stack := parent.get_node_or_null(n) as VBoxContainer
	if stack != null:
		return stack
	stack = UiKit.vbox(10, s)
	stack.name = n
	parent.add_child(stack)
	var m := 28.0 * s
	match where:
		"top_left":
			stack.set_anchors_preset(Control.PRESET_TOP_LEFT)
			stack.position = Vector2(m, m)
		"top":
			stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
			stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
			stack.offset_top = m * 3.0
			stack.alignment = BoxContainer.ALIGNMENT_BEGIN
		"bottom":
			stack.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
			stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
			stack.offset_top = -m * 6.0
			stack.offset_bottom = -m * 6.0
		_:
			stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			stack.offset_left = -m
			stack.offset_right = -m
			stack.offset_top = m
	return stack


# --- World popups ----------------------------------------------------------------------------------

## Floating 3D text at `pos` that pops, rises and fades. opts: style (see POPUP_STYLES), color, size
## (multiplier; 1 = ~0.3 m tall), rise (m, default 0.9), time (s), camera (face this camera once;
## default: the VR camera when this viewport renders VR, otherwise billboard), layers.
static func popup(world: Node, pos: Vector3, text: String, opts: Dictionary = {}) -> Label3D:
	var style := String(opts.get("style", "info"))
	var st: Array = POPUP_STYLES.get(style, POPUP_STYLES["info"])
	var col := UiKit.color_of(opts.get("color", st[0]), st[0])
	var size := float(opts.get("size", 1.0)) * float(st[1])
	var l := Label3D.new()
	l.text = text
	l.font = UiKit.font(true)
	l.font_size = 72
	l.pixel_size = 0.0045 * size
	l.outline_size = 22
	l.modulate = col
	var oc: Color = st[2]
	l.outline_modulate = Color(oc.r, oc.g, oc.b, 0.95)
	l.no_depth_test = true
	l.render_priority = UiKit.VR_PRIO_TEXT
	l.outline_render_priority = UiKit.VR_PRIO_TEXT - 1
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.layers = int(opts.get("layers", 1))
	world.add_child(l)
	var jitter := Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15)) * size
	l.global_position = pos + jitter
	var face_cam: Node3D = opts.get("camera", UiKit.xr_camera(world))
	if face_cam != null and is_instance_valid(face_cam):
		var to := l.global_position - face_cam.global_position
		to.y = 0.0
		if to.length() > 0.01:
			l.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var rise := float(opts.get("rise", 0.9)) * maxf(0.7, size * 0.8)
	var life := float(opts.get("time", 1.1 if style != "crit" else 1.4))
	l.scale = Vector3.ONE * 0.3
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "scale", Vector3.ONE * (1.25 if style == "crit" else 1.0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "global_position", l.global_position + Vector3.UP * rise, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if style == "crit":
		t.tween_property(l, "scale", Vector3.ONE, 0.2).set_delay(0.16)
		var wob := l.create_tween()
		for k in 4:
			wob.tween_property(l, "rotation:z", 0.12 * (1.0 if k % 2 == 0 else -1.0), 0.05)
		wob.tween_property(l, "rotation:z", 0.0, 0.05)
	t.tween_property(l, "modulate:a", 0.0, life * 0.4).set_delay(life * 0.6)
	t.tween_property(l, "outline_modulate:a", 0.0, life * 0.4).set_delay(life * 0.6)
	t.chain().tween_callback(l.queue_free)
	return l


## Damage number ("42", or "42!" bigger and golden when crit). Pass a negative amount for heals.
static func damage(world: Node, pos: Vector3, amount: int, crit: bool = false, opts: Dictionary = {}) -> Label3D:
	if amount < 0:
		return heal(world, pos, -amount, opts)
	var o := opts.duplicate()
	o["style"] = "crit" if crit else "damage"
	return popup(world, pos, ("%d!" % amount) if crit else str(amount), o)


## Green "+30".
static func heal(world: Node, pos: Vector3, amount: int, opts: Dictionary = {}) -> Label3D:
	var o := opts.duplicate()
	o["style"] = "heal"
	return popup(world, pos, "+%d" % amount, o)


## Gold "+100".
static func score(world: Node, pos: Vector3, amount: int, opts: Dictionary = {}) -> Label3D:
	var o := opts.duplicate()
	o["style"] = "score"
	return popup(world, pos, "+%d" % amount, o)


## Grey "MISS".
static func miss(world: Node, pos: Vector3, opts: Dictionary = {}) -> Label3D:
	var o := opts.duplicate()
	o["style"] = "miss"
	return popup(world, pos, "MISS", o)


# --- 3D bars ---------------------------------------------------------------------------------------

## An HP bar that floats above `target` (added as its child, so it follows for free). opts: value, max,
## kind ("hp", "mp", "xp" or a colour via color), width (m, 0.9), height (m, 0.11), offset (Vector3,
## default 1.9 m up), name (text above the bar), hide_full (true: hidden while full), layers.
## bar.set_value(v, max) animates like UiKit.Bar.
static func bar3d(target: Node3D, opts: Dictionary = {}) -> Bar3D:
	var b := Bar3D.new()
	b.kind = String(opts.get("kind", "hp"))
	if opts.has("color"):
		b.fill_color = UiKit.color_of(opts["color"])
	b.width = float(opts.get("width", 0.9))
	b.height = float(opts.get("height", 0.11))
	b.hide_full = bool(opts.get("hide_full", false))
	b.max_value = float(opts.get("max", 1.0))
	b.value = float(opts.get("value", b.max_value))
	b.shown = b.value
	b.ghost = b.value
	b.label_text = String(opts.get("name", ""))
	b.vis_layers = int(opts.get("layers", 1))
	b.position = opts.get("offset", Vector3(0, 1.9, 0))
	target.add_child(b)
	return b


# --- Scoreboard ------------------------------------------------------------------------------------

## Standings with animated rank changes. rows: [{id, name, score, color, sub}], sorted for you.
## opts: title, compact (small corner board), ascending (lower is better, e.g. times), format ("%d"),
## width, anchor ("center", "top_left", "top_right", ...), max_rows. Update with board.set_rows(rows).
static func scoreboard(root: Control, rows: Array, opts: Dictionary = {}) -> Scoreboard:
	var b := Scoreboard.new()
	b.title_text = String(opts.get("title", "" if bool(opts.get("compact", false)) else "STANDINGS"))
	b.compact = bool(opts.get("compact", false))
	b.ascending = bool(opts.get("ascending", false))
	b.fmt = String(opts.get("format", "%d"))
	b.width = float(opts.get("width", 300.0 if b.compact else 620.0))
	b.anchor = String(opts.get("anchor", "top_left" if b.compact else "center"))
	b.max_rows = int(opts.get("max_rows", 8))
	root.add_child(b)
	b.set_rows(rows)
	return b


## Sort standings rows (Dictionaries with "score") best first and add "rank" (ties share a rank).
static func rank_rows(rows: Array, ascending: bool = false) -> Array:
	var out := rows.duplicate(true)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := float(a.get("score", 0.0))
		var sb := float(b.get("score", 0.0))
		return sa < sb if ascending else sa > sb)
	var rank := 0
	var prev := INF
	for i in out.size():
		var s := float(out[i].get("score", 0.0))
		if i == 0 or s != prev:
			rank = i + 1
		prev = s
		out[i]["rank"] = rank
	return out


## Colour for a rank (1 gold, 2 silver, 3 bronze, else dim).
static func rank_color(rank: int) -> Color:
	match rank:
		1:
			return UiKit.GOLD
		2:
			return UiKit.SILVER
		3:
			return UiKit.BRONZE
	return UiKit.TEXT_DIM


## "1ST", "2ND", "3RD", "4TH"...
static func ordinal(n: int) -> String:
	var suffix := "TH"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "ST"
			2:
				suffix = "ND"
			3:
				suffix = "RD"
	return "%d%s" % [n, suffix]


# --- Countdown and timer ---------------------------------------------------------------------------

## "3, 2, 1, GO!" in the middle of the view. opts: step (s per number, 0.8), go ("GO!"), sound
## ("tick"), go_sound ("go"), color. Connect `finished` (emitted on GO) and `tick(n)`.
static func countdown(root: Variant, from: int = 3, opts: Dictionary = {}) -> Countdown:
	if root is Array:
		var first: Countdown = null
		var arr: Array = root
		for r in arr:
			var o := opts.duplicate()
			if first != null:
				o["sound"] = ""
				o["go_sound"] = ""
			var c := countdown(r, from, o)
			if first == null:
				first = c
		return first
	var c := Countdown.new()
	c.from = from
	c.step = float(opts.get("step", 0.8))
	c.go_text = String(opts.get("go", "GO!"))
	c.tick_sound = String(opts.get("sound", "tick"))
	c.go_sound = String(opts.get("go_sound", "go"))
	c.accent = UiKit.color_of(opts.get("color", "accent"), UiKit.ACCENT)
	(root as Control).add_child(c)
	return c


## A clock pill (top centre by default) showing m:ss; turns red and pulses under `warn` seconds.
## opts: seconds (start value), count_down (true: runs by itself and emits `timeout`), warn (10),
## anchor ("top", "top_left", "top_right", "bottom"), label (text before the time, e.g. "TIME").
static func timer(root: Control, opts: Dictionary = {}) -> TimerPill:
	var t := TimerPill.new()
	t.time_left = float(opts.get("seconds", 60.0))
	t.running = bool(opts.get("count_down", true))
	t.warn = float(opts.get("warn", 10.0))
	t.anchor = String(opts.get("anchor", "top"))
	t.prefix = String(opts.get("label", ""))
	root.add_child(t)
	return t


## "1:05" (or "0:09.5" with tenths under 10 s when tenths is true).
static func clock_text(seconds: float, tenths: bool = false) -> String:
	var s := maxf(0.0, seconds)
	if tenths and s < 10.0:
		return "0:%04.1f" % s
	var whole := int(ceil(s))
	return "%d:%02d" % [whole / 60, whole % 60]


# --- Party status, nameplates, objectives, speech bubbles ------------------------------------------

## A player status card: colour edge, name, level badge, HP (and MP) bars. opts: player (index, for the
## colour), name, level, hp [value, max], mp [value, max], icon (UiKit icon kind), width (300).
## Update with card.set_hp(v, max) / set_mp / set_level / set_status("POISONED", "bad") / set_active(true).
static func status_card(root: Control, opts: Dictionary = {}) -> StatusCard:
	var c := StatusCard.new()
	c.opts = opts
	root.add_child(c)
	return c


## A row of status cards along the bottom (or top) of a view, one per member (opts as status_card).
## Returns the HBoxContainer; its children are the StatusCards in order.
static func party_bar(root: Control, members: Array, where: String = "bottom") -> HBoxContainer:
	var s := UiKit.scale_of(root)
	var row := UiKit.hbox(14, s)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)
	var m := 20.0 * s
	if where == "top":
		row.set_anchors_preset(Control.PRESET_TOP_WIDE)
		row.offset_top = m
		row.offset_bottom = m
		row.grow_vertical = Control.GROW_DIRECTION_END
	else:
		row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		row.offset_top = -m
		row.offset_bottom = -m
		row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var w := minf(300.0, (root.size.x / s - 40.0) / maxf(1.0, members.size()) - 14.0) if root.size.x > 10.0 else 300.0
	for mem in members:
		var o: Dictionary = (mem as Dictionary).duplicate()
		o["width"] = float(o.get("width", w))
		status_card(row, o)
	return row


## A player-coloured name label floating over a 3D object (Y-billboarded so every TV camera can read
## it). Added as a child of `target` at `height` metres.
static func nameplate(target: Node3D, text: String, color: Variant = "text", height: float = 2.1, size_m: float = 0.16) -> Label3D:
	var l := UiKit.label3d(text, size_m, color, true)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.no_depth_test = false
	l.position = Vector3(0, height, 0)
	target.add_child(l)
	return l


## An objectives checklist (top-left by default): items are Strings or {id, text, done}. Tick them
## with list.set_done(id) (animated); list.set_items(...) replaces them.
static func objectives(root: Control, items: Array, opts: Dictionary = {}) -> Objectives:
	var o := Objectives.new()
	o.title_text = String(opts.get("title", "GOALS"))
	o.anchor = String(opts.get("anchor", "top_left"))
	root.add_child(o)
	o.set_items(items)
	return o


## A speech bubble over a 3D object: rounded panel + text, Y-billboarded so it reads from every camera
## (TV and VR). Auto-hides after `duration` (0 = stays; call hide_bubble()). opts: color (edge),
## height (m above the target), width (m), duration, size (text height m).
static func bubble3d(target: Node3D, text: String, opts: Dictionary = {}) -> Bubble3D:
	var b := Bubble3D.new()
	b.text = text
	b.accent = UiKit.color_of(opts.get("color", "text"), UiKit.TEXT)
	b.width = float(opts.get("width", 1.4))
	b.duration = float(opts.get("duration", 3.5))
	b.text_size = float(opts.get("size", 0.09))
	b.position = Vector3(0, float(opts.get("height", 2.4)), 0)
	target.add_child(b)
	return b


# --- VR equivalents --------------------------------------------------------------------------------

## A world-space card in front of the VR player (lazy-follows, never on the camera). opts: width (m),
## color (accent), duration (0 = stays; then call hide_card()), distance, height, layers, follow.
static func vr_card(world: Node, cam: Node3D, title: String, body: String = "", opts: Dictionary = {}) -> VrCard:
	var c := VrCard.new()
	c.cam = cam
	c.width = float(opts.get("width", 1.3))
	c.accent = UiKit.color_of(opts.get("color", "accent"), UiKit.ACCENT)
	c.duration = float(opts.get("duration", 0.0))
	c.distance = float(opts.get("distance", 1.6))
	c.height = float(opts.get("height", 0.05))
	c.vis_layers = int(opts.get("layers", 1))
	c.follow = bool(opts.get("follow", true))
	c.title_size = float(opts.get("title_size", 0.085))
	c.body_size = float(opts.get("body_size", 0.05))
	world.add_child(c)
	c.set_text(title, body)
	return c


## VR banner: a big card for a couple of seconds. opts as banner() (style, duration, sound) + vr_card's.
static func vr_banner(world: Node, cam: Node3D, title: String, subtitle: String = "", opts: Dictionary = {}) -> VrCard:
	var style := String(opts.get("style", "default"))
	var st: Array = BANNER_STYLES.get(style, BANNER_STYLES["default"])
	var o := opts.duplicate()
	o["color"] = opts.get("color", st[0])
	o["duration"] = float(opts.get("duration", 2.6))
	o["title_size"] = 0.12
	var c := vr_card(world, cam, title, subtitle, o)
	c.title_color = st[1]
	var snd := String(opts.get("sound", st[2]))
	if snd != "":
		UiKit.sound(snd)
	return c


## VR toast: a small card low in the view for a few seconds.
static func vr_toast(world: Node, cam: Node3D, text: String, opts: Dictionary = {}) -> VrCard:
	var o := opts.duplicate()
	o["width"] = float(opts.get("width", 0.9))
	o["duration"] = float(opts.get("duration", 3.0))
	o["height"] = float(opts.get("height", -0.32))
	o["title_size"] = 0.055
	return vr_card(world, cam, text, String(opts.get("sub", "")), o)


## VR countdown: numbers on a card in front of the VR player. Returns a Countdown-like node with the
## same `finished` / `tick` signals.
static func vr_countdown(world: Node, cam: Node3D, from: int = 3, opts: Dictionary = {}) -> VrCountdown:
	var c := VrCountdown.new()
	c.cam = cam
	c.from = from
	c.step = float(opts.get("step", 0.8))
	c.go_text = String(opts.get("go", "GO!"))
	c.tick_sound = String(opts.get("sound", "tick"))
	c.go_sound = String(opts.get("go_sound", "go"))
	c.vis_layers = int(opts.get("layers", 1))
	world.add_child(c)
	return c


# --- Classes ---------------------------------------------------------------------------------------

class BannerFx extends Control:
	## The banner: a horizontal band that wipes open, a big title that pops in, a subtitle that fades in.
	const UiKit := preload("res://core/ui_kit.gd")
	var title := ""
	var subtitle := ""
	var accent := Color.WHITE
	var title_color := Color.WHITE
	var duration := 2.6
	var y_ratio := 0.36
	var t := 0.0
	var open_k := 0.0       ## 0..1 band width
	var close_k := 0.0      ## 0..1 closing
	var closing := false
	var _title: Label
	var _sub: Label
	var _s := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_s = UiKit.scale_of(self)
		_title = UiKit.label(title, "banner", title_color, HORIZONTAL_ALIGNMENT_CENTER)
		_title.pivot_offset_ratio = Vector2(0.5, 0.5)
		_title.add_theme_color_override("font_outline_color", Color(accent.r * 0.25, accent.g * 0.2, accent.b * 0.25, 0.95))
		add_child(_title)
		_sub = UiKit.label(subtitle, "subtitle", null, HORIZONTAL_ALIGNMENT_CENTER)
		_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_sub)
		_title.modulate.a = 0.0
		_sub.modulate.a = 0.0
		var max_w := size.x * 0.92 if size.x > 10.0 else 1700.0 * _s
		var fs := UiKit.font_size("banner", _s)
		var tw := UiKit.font(true, 2).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > max_w and tw > 0.0:
			_title.add_theme_font_size_override("font_size", int(fs * max_w / tw))  # long titles shrink to fit

	## Close now (also used when duration is 0).
	func dismiss() -> void:
		closing = true

	func _process(delta: float) -> void:
		t += delta
		open_k = minf(1.0, open_k + delta / 0.28)
		if duration > 0.0 and t > duration:
			closing = true
		if closing:
			close_k = minf(1.0, close_k + delta / 0.3)
			if close_k >= 1.0:
				queue_free()
		var ease_open := 1.0 - pow(1.0 - open_k, 3.0)
		var title_k := clampf((t - 0.08) / 0.3, 0.0, 1.0)
		var sub_k := clampf((t - 0.3) / 0.3, 0.0, 1.0)
		var fade := 1.0 - close_k
		_title.modulate.a = title_k * fade
		var pop := 1.0 + (1.0 - title_k) * 0.35 - sin(title_k * PI) * 0.06
		_title.scale = Vector2.ONE * pop
		_sub.modulate.a = sub_k * fade
		var ts := _title.get_combined_minimum_size()
		var ss := _sub.get_combined_minimum_size() if subtitle != "" else Vector2.ZERO
		var cy := size.y * y_ratio
		var total := ts.y + (ss.y + 6.0 * _s if subtitle != "" else 0.0)
		_title.size = Vector2(size.x, ts.y)
		_title.position = Vector2(0, cy - total * 0.5)
		_sub.size = Vector2(size.x * 0.8, ss.y)
		_sub.position = Vector2(size.x * 0.1, cy - total * 0.5 + ts.y + 6.0 * _s)
		set_meta("band", Vector3(cy, total * 0.5 + 26.0 * _s, ease_open * (1.0 - close_k * 0.6)))
		queue_redraw()

	func _draw() -> void:
		if not has_meta("band"):
			return
		var b: Vector3 = get_meta("band")
		var cy := b.x
		var half_h := b.y * (1.0 - close_k)
		var k := b.z
		if half_h < 1.0 or k <= 0.0:
			return
		var cx := size.x * 0.5
		var half_w := size.x * 0.5 * k
		var bg := Color(0.02, 0.025, 0.06, 0.72 * (1.0 - close_k))
		var clear := Color(bg.r, bg.g, bg.b, 0.0)
		var fade_w := half_w * 0.35
		_hband(cx, cy - half_h, cy + half_h, half_w, fade_w, bg, clear)
		var line := Color(accent.r, accent.g, accent.b, 0.95 * (1.0 - close_k))
		var lw := maxf(2.0, 3.0 * _s)
		_hband(cx, cy - half_h - lw, cy - half_h, half_w, fade_w, line, Color(line.r, line.g, line.b, 0.0))
		_hband(cx, cy + half_h, cy + half_h + lw, half_w, fade_w, line, Color(line.r, line.g, line.b, 0.0))

	## A horizontal strip from y0 to y1, solid in the middle and fading out at both ends.
	func _hband(cx: float, y0: float, y1: float, half_w: float, fade_w: float, solid: Color, clear: Color) -> void:
		var xs: Array[float] = [cx - half_w, cx - half_w + fade_w, cx + half_w - fade_w, cx + half_w]
		var cs: Array[Color] = [clear, solid, solid, clear]
		for i in 3:
			draw_polygon(PackedVector2Array([Vector2(xs[i], y0), Vector2(xs[i + 1], y0), Vector2(xs[i + 1], y1), Vector2(xs[i], y1)]),
				PackedColorArray([cs[i], cs[i + 1], cs[i + 1], cs[i]]))


class Bar3D extends Node3D:
	## A world-space bar (background, trailing ghost chip, fill, gloss) in ONE ImmediateMesh draw call,
	## Y-billboarded so it reads from every TV camera and the headset, plus an optional name label.
	const UiKit := preload("res://core/ui_kit.gd")
	const ResCache := preload("res://core/res_cache.gd")
	var kind := "hp"
	var fill_color := Color(0, 0, 0, 0)
	var width := 0.9
	var height := 0.11
	var hide_full := false
	var value := 1.0
	var max_value := 1.0
	var shown := 1.0
	var ghost := 1.0
	var ghost_hold := 0.0
	var flash := 0.0
	var label_text := ""
	var vis_layers := 1
	var mesh_node: MeshInstance3D
	var name_label: Label3D
	var _im: ImmediateMesh

	func _ready() -> void:
		_im = ImmediateMesh.new()
		mesh_node = MeshInstance3D.new()
		mesh_node.mesh = _im
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_node.layers = vis_layers
		add_child(mesh_node)
		if label_text != "":
			name_label = UiKit.label3d(label_text, height * 0.75, "text", true)
			name_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			name_label.no_depth_test = false
			name_label.position = Vector3(0, height * 1.15, 0)
			name_label.layers = vis_layers
			add_child(name_label)
		_redraw()

	## Set the value (and optionally the max); animate=false jumps.
	func set_value(v: float, new_max: float = -1.0, animate: bool = true) -> void:
		if new_max > 0.0:
			max_value = new_max
		var old := value
		value = clampf(v, 0.0, max_value)
		if not animate:
			shown = value
			ghost = value
		elif value < old:
			ghost = maxf(ghost, shown)
			ghost_hold = 0.4
			flash = 1.0
		set_process(true)
		_redraw()

	func _material() -> StandardMaterial3D:
		return ResCache.get_or_make("hud_bar3d_mat_" + UiKit.VERSION, func() -> Resource:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			m.billboard_keep_scale = true
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.render_priority = 6
			return m)

	func _color() -> Color:
		if fill_color.a > 0.0:
			return fill_color
		match kind:
			"mp":
				return UiKit.MP
			"xp":
				return UiKit.XP
		return UiKit.hp_color(shown / maxf(0.001, max_value))

	func _process(delta: float) -> void:
		var busy := false
		if absf(shown - value) > 0.001 * max_value:
			shown = lerpf(shown, value, 1.0 - exp(-10.0 * delta))
			busy = true
		else:
			shown = value
		if ghost_hold > 0.0:
			ghost_hold -= delta
			busy = true
		elif ghost > shown + 0.001 * max_value:
			ghost = move_toward(ghost, shown, max_value * 0.9 * delta)
			busy = true
		else:
			ghost = shown
		if flash > 0.0:
			flash = maxf(0.0, flash - delta * 4.0)
			busy = true
		_redraw()
		if not busy:
			set_process(false)

	func _redraw() -> void:
		if _im == null:
			return
		var full := value >= max_value - 0.0001 and ghost >= max_value - 0.0001
		visible = not (hide_full and full)
		_im.clear_surfaces()
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material())
		var hw := width * 0.5
		var hh := height * 0.5
		_rrect(Vector2(-hw, -hh), Vector2(hw, hh), Color(0.02, 0.025, 0.05, 0.85), 0.0)
		var inset := height * 0.16
		var x0 := -hw + inset
		var inner_w := width - inset * 2.0
		var ih := hh - inset
		var mx := maxf(0.001, max_value)
		if ghost > shown + 0.0001:
			_rrect(Vector2(x0, -ih), Vector2(x0 + maxf(ih * 2.0, inner_w * ghost / mx), ih), Color(1.0, 0.95, 0.85, 0.85), 0.001)
		if shown > 0.0001:
			var c := _color().lerp(Color.WHITE, flash * 0.6)
			var x1 := x0 + maxf(ih * 2.0, inner_w * shown / mx)
			_rrect(Vector2(x0, -ih), Vector2(x1, ih), c, 0.002)
			_rrect(Vector2(x0 + ih * 0.6, ih * 0.15), Vector2(x1 - ih * 0.6, ih * 0.7), Color(1, 1, 1, 0.3), 0.003)
		_im.surface_end()

	## A rounded rectangle (fan) between corners a and b at depth z.
	func _rrect(a: Vector2, b: Vector2, c: Color, z: float) -> void:
		var half := (b - a) * 0.5
		if half.x <= 0.0 or half.y <= 0.0:
			return
		var mid := (a + b) * 0.5
		var r := minf(half.x, half.y)
		var pts := UiKit._rounded_rect(half, r, 4)
		var n := pts.size()
		for i in n:
			var p0 := pts[i] + mid
			var p1 := pts[(i + 1) % n] + mid
			for p in [mid, p1, p0]:
				var v: Vector2 = p
				_im.surface_set_color(c)
				_im.surface_set_normal(Vector3.BACK)
				_im.surface_add_vertex(Vector3(v.x, v.y, z))


class Scoreboard extends PanelContainer:
	## Standings: rows slide to their new rank, scores count up, top three get medal colours.
	const UiKit := preload("res://core/ui_kit.gd")
	const HudKit := preload("res://core/hud_kit.gd")
	var title_text := "STANDINGS"
	var compact := false
	var ascending := false
	var fmt := "%d"
	var width := 620.0
	var anchor := "center"
	var max_rows := 8
	var rows: Array = []
	var _list: Control
	var _cards := {}     ## id -> PanelContainer
	var _scores := {}    ## id -> last shown score
	var _s := 1.0
	var _vbox: VBoxContainer

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_s = UiKit.scale_of(self)
		if compact:
			add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.05, 0.06, 0.11, 0.78), _s, 16.0, Color(1, 1, 1, 0.08), 2.0, 8.0, Vector2(12, 10)))
		_vbox = UiKit.vbox(10, _s)
		add_child(_vbox)
		if title_text != "":
			_vbox.add_child(UiKit.label(title_text, "small" if compact else "heading", "dim" if compact else null, HORIZONTAL_ALIGNMENT_CENTER))
		_list = Control.new()
		_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(_list)
		custom_minimum_size.x = width * _s
		var presets := {"center": Control.PRESET_CENTER, "top": Control.PRESET_CENTER_TOP, "top_left": Control.PRESET_TOP_LEFT,
			"top_right": Control.PRESET_TOP_RIGHT, "bottom_left": Control.PRESET_BOTTOM_LEFT, "bottom_right": Control.PRESET_BOTTOM_RIGHT,
			"left": Control.PRESET_CENTER_LEFT, "right": Control.PRESET_CENTER_RIGHT}
		if presets.has(anchor) and get_parent() is Control and not (get_parent() is Container):
			set_anchors_preset(presets[anchor])
			var m := 24.0 * _s
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
		_layout(false)

	func row_height() -> float:
		return UiKit.font_size("small" if compact else "body", _s) * (1.75 if compact else 2.15)

	## Replace the rows (Dictionaries with id/name, score, color, sub); animates rank changes.
	func set_rows(new_rows: Array) -> void:
		rows = HudKit.rank_rows(new_rows, ascending)
		if is_node_ready():
			_layout(true)

	func _layout(animate: bool) -> void:
		var gap := (5.0 if compact else 8.0) * _s
		var shown := mini(rows.size(), max_rows)
		var w := width * _s - (24.0 if compact else 48.0) * _s
		var seen := {}
		var fresh_ids := {}
		for i in rows.size():  # make/fill the cards first, so their real height is known
			var r: Dictionary = rows[i]
			var id := str(r.get("id", r.get("name", i)))
			if not _cards.has(id):
				var made := _make_card(r)
				_cards[id] = made
				_list.add_child(made)
				fresh_ids[id] = true
			_fill_card(_cards[id], r, id, animate and not fresh_ids.has(id))
		var rh := row_height()
		for id in _cards:
			rh = maxf(rh, (_cards[id] as PanelContainer).get_combined_minimum_size().y)
		_list.custom_minimum_size = Vector2(w, shown * rh + maxi(0, shown - 1) * gap)
		for i in rows.size():
			var r: Dictionary = rows[i]
			var id := str(r.get("id", r.get("name", i)))
			seen[id] = true
			var card: PanelContainer = _cards[id]
			var fresh := fresh_ids.has(id)
			card.size = Vector2(w, rh)
			card.visible = i < max_rows
			var target := Vector2(0, i * (rh + gap))
			if fresh:
				card.position = target + (Vector2(40.0 * _s, 0) if animate else Vector2.ZERO)
				card.modulate.a = 0.0 if animate else 1.0
				var tw := card.create_tween().set_parallel()
				tw.tween_property(card, "position", target, 0.35).set_delay(0.06 * i).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.06 * i)
			elif card.position != target:
				var tw2 := card.create_tween()
				tw2.tween_property(card, "position", target, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for id in _cards.keys():
			if not seen.has(id):
				var old: PanelContainer = _cards[id]
				_cards.erase(id)
				_scores.erase(id)
				UiKit.pop_out(old)

	func _make_card(r: Dictionary) -> PanelContainer:
		var col := UiKit.color_of(r.get("color", "text"), UiKit.TEXT)
		var card := UiKit.tinted_panel(col, _s, "toast")
		card.add_theme_stylebox_override("panel", _card_box(col))
		var h := UiKit.hbox(12, _s)
		h.name = "Row"
		card.add_child(h)
		var rank := PanelContainer.new()
		rank.name = "Rank"
		rank.custom_minimum_size = Vector2.ONE * row_height() * 0.62
		rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(rank)
		var rl := UiKit.label("", "small" if not compact else "tiny", null, HORIZONTAL_ALIGNMENT_CENTER)
		rl.name = "RankText"
		rl.add_theme_font_override("font", UiKit.font(true))
		rank.add_child(rl)
		var names := UiKit.vbox(0, _s)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(names)
		var nl := UiKit.label("", "small" if compact else "body", col.lightened(0.35))
		nl.name = "Name"
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		names.add_child(nl)
		var sub := UiKit.label("", "tiny", "dim")
		sub.name = "Sub"
		names.add_child(sub)
		var crown := UiKit.icon("crown", "gold", row_height() * 0.45)
		crown.name = "Crown"
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(crown)
		var sl := UiKit.label("", "small" if compact else "number", null, HORIZONTAL_ALIGNMENT_RIGHT)
		sl.name = "Score"
		h.add_child(sl)
		return card

	func _card_box(col: Color) -> StyleBoxFlat:
		var sb := UiKit.stylebox(Color(0.11, 0.13, 0.21, 0.94), _s, 12.0, Color(1, 1, 1, 0.06), 2.0, 0.0, Vector2(12, 4))
		sb.border_color = col
		sb.border_width_left = maxi(3, int(round(6.0 * _s)))
		return sb

	func _fill_card(card: PanelContainer, r: Dictionary, id: String, animate: bool) -> void:
		var rank := int(r.get("rank", 0))
		var rc := HudKit.rank_color(rank)
		var rank_box := card.find_child("Rank", true, false) as PanelContainer
		rank_box.add_theme_stylebox_override("panel", UiKit.stylebox(rc.darkened(0.5) if rank <= 3 else Color(1, 1, 1, 0.06), _s, 200.0,
			rc if rank <= 3 else Color(0, 0, 0, 0), 2.0, 0.0, Vector2(0, 0)))
		var rl := card.find_child("RankText", true, false) as Label
		rl.text = str(rank)
		rl.add_theme_color_override("font_color", rc.lightened(0.3) if rank <= 3 else UiKit.TEXT_DIM)
		(card.find_child("Name", true, false) as Label).text = str(r.get("name", id))
		var sub := card.find_child("Sub", true, false) as Label
		sub.text = str(r.get("sub", ""))
		sub.visible = sub.text != "" and not compact
		(card.find_child("Crown", true, false) as Control).visible = rank == 1 and rows.size() > 1
		var sl := card.find_child("Score", true, false) as Label
		var sc := float(r.get("score", 0.0))
		var prev := float(_scores.get(id, sc if not animate else 0.0))
		_scores[id] = sc
		if fmt.contains("%d") and absf(sc - prev) >= 1.0 and is_inside_tree():
			UiKit.count_up(sl, int(prev), int(sc), 0.6, fmt)
		elif fmt.contains("%d"):
			sl.text = fmt % int(sc)
		else:
			sl.text = fmt % sc


class Countdown extends Control:
	## Big numbers popping in the centre of a view with a draining ring, then GO!
	signal tick(n: int)
	signal finished()
	const UiKit := preload("res://core/ui_kit.gd")
	var from := 3
	var step := 0.8
	var go_text := "GO!"
	var tick_sound := "tick"
	var go_sound := "go"
	var accent := Color.WHITE
	var t := 0.0
	var current := -1
	var _label: Label
	var _s := 1.0
	var _done := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_s = UiKit.scale_of(self)
		_label = UiKit.label("", "banner", null, HORIZONTAL_ALIGNMENT_CENTER)
		_label.add_theme_font_size_override("font_size", int(UiKit.font_size("banner", _s) * 1.5))
		_label.pivot_offset_ratio = Vector2(0.5, 0.5)
		add_child(_label)

	func _process(delta: float) -> void:
		t += delta
		var k := int(t / step)
		if k != current:
			current = k
			var n := from - k
			if n > 0:
				_label.text = str(n)
				tick.emit(n)
				if tick_sound != "":
					UiKit.sound(tick_sound)
			elif n == 0:
				_label.text = go_text
				_label.add_theme_color_override("font_color", UiKit.GOOD.lightened(0.2))
				if go_sound != "":
					UiKit.sound(go_sound)
				if not _done:
					_done = true
					finished.emit()
		var local := fmod(t, step) / step
		var n2 := from - current
		var ls := _label.get_combined_minimum_size()
		_label.size = ls
		_label.position = (size - ls) * 0.5
		if n2 >= 0:
			_label.scale = Vector2.ONE * (1.0 + 0.6 * pow(1.0 - minf(1.0, local * 3.0), 2.0))
			_label.modulate.a = 1.0 - maxf(0.0, (local - 0.75) * 4.0) if n2 > 0 else 1.0 - maxf(0.0, (local - 0.4) * 1.7)
		if n2 < 0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var n := from - current
		if n <= 0:
			return
		var local := fmod(t, step) / step
		var c := size * 0.5
		var r := UiKit.font_size("banner", _s) * 0.95
		draw_arc(c, r, 0.0, TAU, 48, Color(0, 0, 0, 0.35), 10.0 * _s, true)
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - local), 48, accent, 8.0 * _s, true)


class TimerPill extends PanelContainer:
	## A "1:23" clock pill; red and pulsing under `warn` seconds. set_time(s) or let it count down.
	signal timeout()
	const UiKit := preload("res://core/ui_kit.gd")
	const HudKit := preload("res://core/hud_kit.gd")
	var time_left := 60.0
	var running := true
	var warn := 10.0
	var anchor := "top"
	var prefix := ""
	var _label: Label
	var _icon: Control
	var _s := 1.0
	var _last_whole := -1
	var _fired := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_s = UiKit.scale_of(self)
		add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.05, 0.06, 0.11, 0.85), _s, 200.0, Color(1, 1, 1, 0.12), 2.0, 8.0, Vector2(20, 6)))
		var h := UiKit.hbox(10, _s)
		add_child(h)
		_icon = UiKit.icon("clock", "text", 30.0 * _s)
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_icon)
		_label = UiKit.label("", "number")
		h.add_child(_label)
		var presets := {"top": Control.PRESET_CENTER_TOP, "top_left": Control.PRESET_TOP_LEFT, "top_right": Control.PRESET_TOP_RIGHT,
			"bottom": Control.PRESET_CENTER_BOTTOM}
		if get_parent() is Control and not (get_parent() is Container):
			set_anchors_preset(presets.get(anchor, Control.PRESET_CENTER_TOP))
			grow_horizontal = Control.GROW_DIRECTION_BOTH if anchor in ["top", "bottom"] else (Control.GROW_DIRECTION_END if anchor == "top_left" else Control.GROW_DIRECTION_BEGIN)
			grow_vertical = Control.GROW_DIRECTION_BEGIN if anchor == "bottom" else Control.GROW_DIRECTION_END
			var m := 20.0 * _s
			offset_top = -m if anchor == "bottom" else m
			offset_bottom = offset_top
			if anchor == "top_left":
				offset_left = m
				offset_right = m
			elif anchor == "top_right":
				offset_left = -m
				offset_right = -m
		pivot_offset_ratio = Vector2(0.5, 0.5)
		set_time(time_left)

	## Show this many seconds (also restarts the warning pulses).
	func set_time(seconds: float) -> void:
		time_left = seconds
		_fired = seconds <= 0.0 and _fired
		var txt := HudKit.clock_text(seconds, true)
		_label.text = (prefix + "  " + txt) if prefix != "" else txt
		var low := seconds <= warn
		var col := UiKit.BAD.lightened(0.15) if low else UiKit.TEXT
		_label.add_theme_color_override("font_color", col)
		_icon.set("color", col)
		var whole := int(ceil(seconds))
		if low and whole != _last_whole and seconds > 0.0:
			UiKit.pulse(self, 1.12)
			UiKit.sound("tick", -6.0, 1.3)
		_last_whole = whole

	func _process(delta: float) -> void:
		if not running:
			return
		if time_left > 0.0:
			set_time(maxf(0.0, time_left - delta))
		elif not _fired:
			_fired = true
			timeout.emit()


class VrCard extends Node3D:
	## A world-space card: title + optional body on a rounded panel sized to fit, lazily following the
	## VR player's view (never on the camera, never billboarded). Fades in; auto-hides after `duration`.
	const UiKit := preload("res://core/ui_kit.gd")
	var cam: Node3D
	var width := 1.3
	var accent := Color.WHITE
	var title_color := Color(0.97, 0.96, 0.93):
		set(v):
			title_color = v
			if title_l != null:
				title_l.modulate = v
	var duration := 0.0
	var distance := 1.6
	var height := 0.05
	var vis_layers := 1
	var follow := true
	var title_size := 0.085
	var body_size := 0.05
	var t := 0.0
	var panel: MeshInstance3D
	var title_l: Label3D
	var body_l: Label3D
	var _hiding := false

	func _ready() -> void:
		panel = MeshInstance3D.new()
		panel.material_override = UiKit.vr_panel_material(UiKit.VR_PRIO_PANEL)
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(panel)
		title_l = UiKit.label3d("", title_size, title_color, true, width - 0.12)
		title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(title_l)
		body_l = UiKit.label3d("", body_size, "dim", false, width - 0.12)
		body_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(body_l)
		for c in get_children():
			(c as VisualInstance3D).layers = vis_layers
		if cam != null and is_instance_valid(cam):
			UiKit.vr_place(self, cam, distance, height)
		for c in get_children():
			(c as GeometryInstance3D).transparency = 1.0
		var tw := create_tween().set_parallel()
		for c in get_children():
			tw.tween_property(c, "transparency", 0.0, 0.22)

	## Change the text (resizes the panel).
	func set_text(title: String, body: String = "") -> void:
		if not is_node_ready():
			await ready
		title_l.text = title
		title_l.modulate = title_color
		body_l.text = body
		body_l.visible = body != ""
		var tw_px := (width - 0.12) / title_l.pixel_size
		var bw_px := (width - 0.12) / body_l.pixel_size
		var tl := UiKit.wrap_text(title, tw_px, title_l.font_size, true).count("\n") + 1
		var bl := (UiKit.wrap_text(body, bw_px, body_l.font_size).count("\n") + 1) if body != "" else 0
		var th := tl * title_l.font_size * title_l.pixel_size * 1.05
		var bh := bl * body_l.font_size * body_l.pixel_size * 1.1
		var pad := 0.07
		var h := pad * 2.0 + th + (bh + 0.03 if bl > 0 else 0.0)
		panel.mesh = UiKit.panel_mesh(Vector2(width, h), UiKit.BG, Color(accent.r, accent.g, accent.b, 0.7))
		title_l.position = Vector3(0, h * 0.5 - pad - th * 0.5, 0.004)
		body_l.position = Vector3(0, -h * 0.5 + pad + bh * 0.5, 0.004)

	## Fade out (and free unless free_after is false).
	func hide_card(free_after: bool = true) -> void:
		if _hiding:
			return
		_hiding = true
		var tw := create_tween().set_parallel()
		for c in get_children():
			tw.tween_property(c, "transparency", 1.0, 0.2)
		if free_after:
			tw.chain().tween_callback(queue_free)

	func _process(delta: float) -> void:
		t += delta
		if follow and cam != null and is_instance_valid(cam):
			UiKit.vr_follow(self, cam, distance, height, delta)
		if duration > 0.0 and t > duration:
			hide_card()


class VrCountdown extends Node3D:
	## "3, 2, 1, GO!" on a small card in front of the VR player.
	signal tick(n: int)
	signal finished()
	const UiKit := preload("res://core/ui_kit.gd")
	var cam: Node3D
	var from := 3
	var step := 0.8
	var go_text := "GO!"
	var tick_sound := "tick"
	var go_sound := "go"
	var vis_layers := 1
	var t := 0.0
	var current := -1
	var label: Label3D
	var _done := false

	func _ready() -> void:
		var bg := UiKit.panel3d(Vector2(0.5, 0.42), UiKit.BG)
		bg.layers = vis_layers
		add_child(bg)
		label = UiKit.label3d("", 0.24, "text", true)
		label.layers = vis_layers
		label.position.z = 0.004
		add_child(label)
		if cam != null and is_instance_valid(cam):
			UiKit.vr_place(self, cam, 1.5, 0.05)

	func _process(delta: float) -> void:
		t += delta
		var k := int(t / step)
		if k != current:
			current = k
			var n := from - k
			if n > 0:
				label.text = str(n)
				label.modulate = UiKit.TEXT
				tick.emit(n)
				if tick_sound != "":
					UiKit.sound(tick_sound)
			elif n == 0:
				label.text = go_text
				label.modulate = UiKit.GOOD.lightened(0.2)
				if go_sound != "":
					UiKit.sound(go_sound)
				if not _done:
					_done = true
					finished.emit()
			else:
				queue_free()
				return
		var local := fmod(t, step) / step
		label.scale = Vector3.ONE * (1.0 + 0.5 * pow(1.0 - minf(1.0, local * 3.0), 2.0))
		if cam != null and is_instance_valid(cam):
			UiKit.vr_follow(self, cam, 1.5, 0.05, delta)


class StatusCard extends PanelContainer:
	## One party member: colour edge, name + level badge, HP/MP bars, a status word, a glow when it's
	## their turn.
	const UiKit := preload("res://core/ui_kit.gd")
	var opts := {}
	var hp_bar: UiKit.Bar
	var mp_bar: UiKit.Bar
	var name_label: Label
	var level_badge: Control
	var status_label: Label
	var _s := 1.0
	var _col := Color.WHITE
	var _active := false
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_s = UiKit.scale_of(self)
		_col = UiKit.color_of(opts.get("color", int(opts.get("player", 0))), UiKit.ACCENT)
		custom_minimum_size.x = float(opts.get("width", 300.0)) * _s
		_restyle()
		var v := UiKit.vbox(6, _s)
		add_child(v)
		var top := UiKit.hbox(8, _s)
		v.add_child(top)
		var ic := String(opts.get("icon", ""))
		if ic != "":
			var icon := UiKit.icon(ic, _col, 28.0 * _s)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(icon)
		name_label = UiKit.label(String(opts.get("name", "P%d" % (int(opts.get("player", 0)) + 1))), "small", _col.lightened(0.4))
		name_label.add_theme_font_override("font", UiKit.font(true))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(name_label)
		status_label = UiKit.label("", "tiny", "bad")
		status_label.visible = false
		top.add_child(status_label)
		if opts.has("level"):
			level_badge = UiKit.badge("LV %d" % int(opts["level"]), _col, _s)
			top.add_child(level_badge)
		var bw := float(opts.get("width", 300.0)) - 40.0
		hp_bar = UiKit.bar("hp", bw, 20.0)
		hp_bar.show_numbers = true
		hp_bar.prefix = "HP"
		v.add_child(hp_bar)
		var hp: Array = opts.get("hp", [1, 1])
		hp_bar.set_value(float(hp[0]), float(hp[1]), false)
		if opts.has("mp"):
			mp_bar = UiKit.bar("mp", bw, 14.0)
			mp_bar.show_numbers = true
			mp_bar.prefix = "MP"
			v.add_child(mp_bar)
			var mp: Array = opts["mp"]
			mp_bar.set_value(float(mp[0]), float(mp[1]), false)

	func _restyle() -> void:
		var sb := UiKit.stylebox(Color(0.06, 0.07, 0.12, 0.88), _s, 14.0, Color(1, 1, 1, 0.08), 2.0, 8.0, Vector2(14, 10))
		sb.border_color = _col if _active else Color(_col.r, _col.g, _col.b, 0.6)
		sb.border_width_left = maxi(3, int(round(6.0 * _s)))
		if _active:
			sb.set_border_width_all(maxi(2, int(round(3.0 * _s))))
			sb.border_width_left = maxi(3, int(round(6.0 * _s)))
			sb.bg_color = Color(_col.r * 0.25, _col.g * 0.25, _col.b * 0.3, 0.92)
		add_theme_stylebox_override("panel", sb)

	## Set HP (animated).
	func set_hp(v: float, max_v: float = -1.0) -> void:
		hp_bar.set_value(v, max_v)

	## Set MP (animated; ignored if the card has no MP bar).
	func set_mp(v: float, max_v: float = -1.0) -> void:
		if mp_bar != null:
			mp_bar.set_value(v, max_v)

	## Set the level badge (pulses).
	func set_level(level: int) -> void:
		if level_badge != null:
			((level_badge.get_child(0) as HBoxContainer).get_child(-1) as Label).text = "LV %d" % level
			UiKit.pulse(level_badge)

	## Show a short status word ("POISON", "KO", "SHIELD"), or "" to clear. color: palette name / Color.
	func set_status(text: String, color: Variant = "bad") -> void:
		status_label.text = text
		status_label.visible = text != ""
		status_label.add_theme_color_override("font_color", UiKit.color_of(color, UiKit.BAD))

	## Highlight this card (e.g. it's this player's turn).
	func set_active(on: bool) -> void:
		if on == _active:
			return
		_active = on
		_restyle()
		if on:
			UiKit.pulse(self, 1.05)


class Objectives extends PanelContainer:
	## A small checklist: each goal gets a tick (and a green flash) when done.
	const UiKit := preload("res://core/ui_kit.gd")
	var title_text := "GOALS"
	var anchor := "top_left"
	var items: Array = []
	var _v: VBoxContainer
	var _rows := {}
	var _s := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_s = UiKit.scale_of(self)
		add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.05, 0.06, 0.11, 0.78), _s, 14.0, Color(1, 1, 1, 0.08), 2.0, 6.0, Vector2(14, 10)))
		_v = UiKit.vbox(6, _s)
		add_child(_v)
		var presets := {"top_left": Control.PRESET_TOP_LEFT, "top_right": Control.PRESET_TOP_RIGHT, "bottom_left": Control.PRESET_BOTTOM_LEFT,
			"bottom_right": Control.PRESET_BOTTOM_RIGHT, "left": Control.PRESET_CENTER_LEFT, "right": Control.PRESET_CENTER_RIGHT}
		if presets.has(anchor) and get_parent() is Control and not (get_parent() is Container):
			set_anchors_preset(presets[anchor])
			var m := 20.0 * _s
			grow_horizontal = Control.GROW_DIRECTION_BEGIN if anchor.contains("right") else Control.GROW_DIRECTION_END
			grow_vertical = Control.GROW_DIRECTION_BEGIN if anchor.begins_with("bottom") else Control.GROW_DIRECTION_END
			offset_left = -m if anchor.contains("right") else m
			offset_right = offset_left
			offset_top = -m if anchor.begins_with("bottom") else m
			offset_bottom = offset_top
		_rebuild()

	## Replace the goals: Strings or {id, text, done}.
	func set_items(list: Array) -> void:
		items = []
		for it in list:
			var d: Dictionary = it if it is Dictionary else {"text": str(it)}
			items.append({"id": str(d.get("id", d.get("text", ""))), "text": str(d.get("text", "")), "done": bool(d.get("done", false))})
		if is_node_ready():
			_rebuild()

	## Tick a goal (by id or text). Plays a sound and flashes the row.
	func set_done(id: String, done: bool = true) -> void:
		for it in items:
			if String(it.id) == id and bool(it.done) != done:
				it["done"] = done
				_style_row(it)
				if done and _rows.has(id):
					UiKit.pulse(_rows[id])
					UiKit.sound("correct", -6.0)

	## True when every goal is done.
	func all_done() -> bool:
		for it in items:
			if not bool(it.done):
				return false
		return not items.is_empty()

	func _rebuild() -> void:
		for c in _v.get_children():
			c.queue_free()
		_rows.clear()
		if title_text != "":
			_v.add_child(UiKit.label(title_text, "tiny", "dim"))
		for it in items:
			var row := UiKit.hbox(10, _s)
			var box := UiKit.icon("check" if bool(it.done) else "dot", "good" if bool(it.done) else "off", 24.0 * _s)
			box.name = "Box"
			box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(box)
			var l := UiKit.label(String(it.text), "small")
			l.name = "Text"
			row.add_child(l)
			_v.add_child(row)
			_rows[String(it.id)] = row
			_style_row(it)

	func _style_row(it: Dictionary) -> void:
		var row: Control = _rows.get(String(it.id), null)
		if row == null:
			return
		var done := bool(it.done)
		var box := row.get_node("Box")
		box.set("kind", "check" if done else "dot")
		box.set("color", UiKit.GOOD if done else UiKit.TEXT_OFF)
		(row.get_node("Text") as Label).add_theme_color_override("font_color", UiKit.TEXT_DIM if done else UiKit.TEXT)


class Bubble3D extends Node3D:
	## A speech bubble over a 3D object (panel + text, Y-billboarded, drawn on top).
	const UiKit := preload("res://core/ui_kit.gd")
	var text := ""
	var accent := Color.WHITE
	var width := 1.4
	var duration := 3.5
	var text_size := 0.09
	var t := 0.0
	var panel: MeshInstance3D
	var label: Label3D
	var _hiding := false

	func _ready() -> void:
		label = UiKit.label3d(text, text_size, "text", false, width - 0.16)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		var lines := UiKit.wrap_text(text, (width - 0.16) / label.pixel_size, label.font_size).count("\n") + 1
		var h := lines * label.font_size * label.pixel_size * 1.05 + 0.14
		panel = MeshInstance3D.new()
		panel.mesh = UiKit.panel_mesh(Vector2(width, h), Color(0.97, 0.96, 0.93, 0.96), accent, 0.07, 0.014)
		panel.material_override = UiKit.vr_panel_material(UiKit.VR_PRIO_PANEL, false, BaseMaterial3D.BILLBOARD_FIXED_Y)
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(panel)
		label.modulate = Color(0.08, 0.08, 0.14)
		label.outline_size = 0
		add_child(label)
		scale = Vector3.ONE * 0.2
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	## Pop the bubble away.
	func hide_bubble() -> void:
		if _hiding:
			return
		_hiding = true
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ONE * 0.1, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)

	func _process(delta: float) -> void:
		t += delta
		if duration > 0.0 and t > duration:
			hide_bubble()
