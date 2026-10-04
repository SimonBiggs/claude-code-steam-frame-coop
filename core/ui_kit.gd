extends RefCounted
## The arcade's visual language for TV (2D) and VR (3D) UI, all generated in code.
##
##   const UiKit := preload("res://core/ui_kit.gd")
##   var ui := UiKit.ui_root(self)                      # full-screen themed root (CanvasLayer + Control)
##   var card := UiKit.panel("card")                     # rounded panel with a soft shadow
##   card.add_child(UiKit.label("Hello!", "title"))
##   ui.add_child(card)
##   UiKit.pop_in(card)
##
## Everything is sized by a Theme built for the view's scale (1.0 = a 1920x1080 view; a 3x2 split-screen
## cell gets ~0.55). A UiRoot swaps its theme when its viewport resizes, so text and panels always fit.
## Use theme type variations (label kinds, panel styles) instead of per-node overrides where you can.
## The built-in font has no symbol glyphs (no hearts, stars or arrows): use Icon for shapes.

const Me := preload("res://core/ui_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")

const VERSION := "v3"  # bump when the theme changes (cached themes survive hot reloads)

# --- Palette -------------------------------------------------------------------------------------

const BG := Color(0.075, 0.085, 0.15, 0.94)          ## main glass panel
const BG_CARD := Color(0.13, 0.15, 0.245, 0.97)      ## cards / list rows
const BG_DEEP := Color(0.035, 0.04, 0.075, 0.96)     ## dialogue boxes, overlays
const TEXT := Color(0.97, 0.96, 0.93)                ## normal text
const TEXT_DIM := Color(0.68, 0.71, 0.8)             ## secondary text
const TEXT_OFF := Color(0.46, 0.48, 0.55)            ## disabled text
const OUTLINE := Color(0.02, 0.02, 0.06, 0.92)       ## text outline
const ACCENT := Color(1.0, 0.8, 0.28)                ## focus rings, highlights (gold)
const GOOD := Color(0.38, 0.88, 0.47)                ## success / heal / correct
const BAD := Color(1.0, 0.36, 0.36)                  ## damage / wrong / danger
const INFO := Color(0.38, 0.72, 1.0)                 ## info / mana
const WARN := Color(1.0, 0.62, 0.22)                 ## warnings / fire
const MAGIC := Color(0.72, 0.52, 1.0)                ## magic / rare
const GOLD := Color(1.0, 0.82, 0.3)                  ## coins, 1st place
const SILVER := Color(0.8, 0.84, 0.9)                ## 2nd place
const BRONZE := Color(0.86, 0.56, 0.33)              ## 3rd place
const HP_FULL := Color(0.38, 0.9, 0.45)
const HP_MID := Color(1.0, 0.82, 0.25)
const HP_LOW := Color(1.0, 0.33, 0.3)
const MP := Color(0.36, 0.62, 1.0)
const XP := Color(0.98, 0.78, 0.3)

## Player colours by party slot: exactly core/party.gd's Party.COLORS (slot 0 = the VR player "P1" blue,
## P2 gold, P3 pink, P4 green, P5 white, P6 purple, P7 teal).
const PartyScript := preload("res://core/party.gd")
const PLAYER_COLORS: Array[Color] = PartyScript.COLORS

## Named colours for options like {"color": "good"}.
const NAMED := {"text": TEXT, "dim": TEXT_DIM, "off": TEXT_OFF, "accent": ACCENT, "good": GOOD, "bad": BAD,
	"info": INFO, "warn": WARN, "magic": MAGIC, "gold": GOLD, "silver": SILVER, "bronze": BRONZE, "hp": HP_FULL,
	"mp": MP, "xp": XP, "white": Color.WHITE}

## Font sizes at scale 1.0 (a 1920x1080 view).
const SIZES := {"banner": 112, "title": 64, "heading": 42, "number": 38, "body": 30, "small": 24, "tiny": 19}

## Label kinds -> theme type variation names.
const LABEL_KINDS := {"banner": "BannerLabel", "title": "TitleLabel", "heading": "HeadingLabel", "number": "NumberLabel",
	"body": "Label", "small": "SmallLabel", "tiny": "TinyLabel", "dim": "DimLabel", "accent": "AccentLabel",
	"subtitle": "SubtitleLabel"}

## Panel styles -> theme type variation names.
const PANEL_STYLES := {"default": "PanelContainer", "glass": "PanelContainer", "card": "CardPanel", "accent": "AccentPanel",
	"toast": "ToastPanel", "pill": "PillPanel", "dialogue": "DialoguePanel", "flat": "FlatPanel", "danger": "DangerPanel",
	"success": "SuccessPanel", "info": "InfoPanel", "tooltip": "TooltipPanel", "clear": "ClearPanel"}


## Player colour for a party slot / player index (wraps; same as Party.color_of(slot)).
static func player_color(index: int) -> Color:
	return PLAYER_COLORS[posmod(index, PLAYER_COLORS.size())]


## A colour from a Color, a palette name ("good", "bad", "accent"...) or a player index (int).
static func color_of(c: Variant, fallback: Color = TEXT) -> Color:
	if c is Color:
		return c
	if c is String or c is StringName:
		return NAMED.get(String(c), fallback)
	if c is int:
		return player_color(c)
	return fallback


## HP colour for a 0..1 fraction (green -> yellow -> red).
static func hp_color(frac: float) -> Color:
	if frac > 0.5:
		return HP_MID.lerp(HP_FULL, (frac - 0.5) * 2.0)
	return HP_LOW.lerp(HP_MID, clampf(frac * 2.0, 0.0, 1.0))


# --- Scale -----------------------------------------------------------------------------------------

## UI scale for a view of this size: 1.0 at 1920x1080, ~0.7 for a half-screen, never below 0.55.
static func scale_for_size(size: Vector2) -> float:
	if size.x < 2.0 or size.y < 2.0:
		return 1.0
	return clampf(sqrt((size.x / 1920.0) * (size.y / 1080.0)), 0.55, 1.6)


## UI scale of the view a node is drawn in (the theme's scale when the node is under a UiRoot).
static func scale_of(node: Node) -> float:
	if node is Control:
		var pct := (node as Control).get_theme_constant("scale_pct", "UiKit")
		if pct > 0:
			return pct / 100.0
	if node != null and node.is_inside_tree():
		return scale_for_size(node.get_viewport().get_visible_rect().size)
	return 1.0


## Font size of a kind ("title", "body", ...) at a scale.
static func font_size(kind: String, s: float = 1.0) -> int:
	return maxi(8, int(round(float(SIZES.get(kind, 30)) * s)))


# --- Fonts and theme -------------------------------------------------------------------------------

## The default font (Open Sans SemiBold built into Godot), optionally emboldened and letter-spaced.
static func font(bold: bool = false, spacing: int = 0) -> Font:
	var key := "ui_font_%s_%d_%s" % [bold, spacing, VERSION]
	return ResCache.get_or_make(key, func() -> Resource:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		if bold:
			f.variation_embolden = 0.7
		if spacing != 0:
			f.set_spacing(TextServer.SPACING_GLYPH, spacing)
		return f)


## The arcade Theme for a UI scale (cached per 0.05 step). UiRoot assigns it for you.
static func theme(s: float = 1.0) -> Theme:
	var q := clampf(snappedf(s, 0.05), 0.4, 2.0)
	return ResCache.get_or_make("ui_theme_%d_%s" % [int(q * 100.0), VERSION], func() -> Resource: return Me._build_theme(q))


## A rounded StyleBoxFlat in the arcade style (also handy for _draw: `sb.draw(get_canvas_item(), rect)`).
static func stylebox(bg: Color, s: float = 1.0, radius: float = 16.0, border: Color = Color(1, 1, 1, 0.08),
		border_w: float = 2.0, shadow: float = 0.0, margin: Vector2 = Vector2(18, 12)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(round(radius * s)))
	sb.corner_detail = 6
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	if border.a > 0.0 and border_w > 0.0:
		sb.border_color = border
		sb.set_border_width_all(maxi(1, int(round(border_w * s))))
	if shadow > 0.0:
		sb.shadow_color = Color(0, 0, 0, 0.42)
		sb.shadow_size = int(round(shadow * s))
		sb.shadow_offset = Vector2(0, round(shadow * 0.35 * s))
	sb.content_margin_left = round(margin.x * s)
	sb.content_margin_right = round(margin.x * s)
	sb.content_margin_top = round(margin.y * s)
	sb.content_margin_bottom = round(margin.y * s)
	return sb


static func _build_theme(s: float) -> Theme:
	var t := Theme.new()
	var regular := font(false)
	var bold := font(true)
	var bold_wide := font(true, 2)
	t.default_font = regular
	t.default_font_size = font_size("body", s)
	t.set_constant("scale_pct", "UiKit", int(round(s * 100.0)))

	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", OUTLINE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("outline_size", "Label", maxi(2, int(round(6.0 * s))))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", maxi(1, int(round(3.0 * s))))
	t.set_constant("shadow_outline_size", "Label", maxi(2, int(round(6.0 * s))))
	t.set_font_size("font_size", "Label", font_size("body", s))
	t.set_font("font", "Label", regular)
	var kinds := {
		"BannerLabel": [bold_wide, "banner", 16.0, TEXT],
		"TitleLabel": [bold_wide, "title", 11.0, TEXT],
		"HeadingLabel": [bold, "heading", 8.0, TEXT],
		"NumberLabel": [bold, "number", 7.0, TEXT],
		"SubtitleLabel": [regular, "heading", 7.0, TEXT_DIM.lightened(0.25)],
		"SmallLabel": [regular, "small", 5.0, TEXT],
		"TinyLabel": [regular, "tiny", 4.0, TEXT_DIM],
		"DimLabel": [regular, "small", 5.0, TEXT_DIM],
		"AccentLabel": [bold, "heading", 8.0, ACCENT],
	}
	for k in kinds:
		var d: Array = kinds[k]
		t.set_type_variation(k, "Label")
		var f: Font = d[0]
		t.set_font("font", k, f)
		t.set_font_size("font_size", k, font_size(String(d[1]), s))
		t.set_constant("outline_size", k, maxi(2, int(round(float(d[2]) * s))))
		t.set_constant("shadow_outline_size", k, maxi(2, int(round(float(d[2]) * s))))
		var c: Color = d[3]
		t.set_color("font_color", k, c)

	# Panels
	var panels := {
		"PanelContainer": stylebox(BG, s, 20.0, Color(1, 1, 1, 0.09), 2.0, 16.0, Vector2(24, 20)),
		"CardPanel": stylebox(BG_CARD, s, 14.0, Color(1, 1, 1, 0.07), 2.0, 6.0, Vector2(16, 12)),
		"AccentPanel": stylebox(BG, s, 20.0, ACCENT, 3.0, 16.0, Vector2(24, 20)),
		"ToastPanel": _toast_box(s, ACCENT),
		"PillPanel": stylebox(Color(0.18, 0.2, 0.3, 0.96), s, 200.0, Color(1, 1, 1, 0.1), 2.0, 0.0, Vector2(14, 4)),
		"DialoguePanel": stylebox(BG_DEEP, s, 24.0, Color(1, 1, 1, 0.13), 3.0, 22.0, Vector2(34, 24)),
		"FlatPanel": stylebox(Color(1, 1, 1, 0.045), s, 12.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(14, 10)),
		"DangerPanel": stylebox(Color(0.25, 0.06, 0.08, 0.95), s, 20.0, BAD, 3.0, 16.0, Vector2(24, 20)),
		"SuccessPanel": stylebox(Color(0.06, 0.2, 0.1, 0.95), s, 20.0, GOOD, 3.0, 16.0, Vector2(24, 20)),
		"InfoPanel": stylebox(Color(0.06, 0.12, 0.25, 0.95), s, 20.0, INFO, 3.0, 16.0, Vector2(24, 20)),
		"TooltipPanel": stylebox(Color(0, 0, 0, 0.28), s, 12.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(16, 10)),
		"ClearPanel": stylebox(Color(0, 0, 0, 0), s, 0.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(0, 0)),
	}
	for k in panels:
		if k != "PanelContainer":
			t.set_type_variation(k, "PanelContainer")
		var sb: StyleBoxFlat = panels[k]
		t.set_stylebox("panel", k, sb)
	t.set_stylebox("panel", "Panel", panels["PanelContainer"])

	# Buttons (mouse-driven screens; controller menus use core/ui_menu.gd)
	t.set_stylebox("normal", "Button", stylebox(BG_CARD, s, 14.0, Color(1, 1, 1, 0.08), 2.0, 4.0, Vector2(22, 12)))
	t.set_stylebox("hover", "Button", stylebox(BG_CARD.lightened(0.12), s, 14.0, Color(1, 1, 1, 0.18), 2.0, 6.0, Vector2(22, 12)))
	t.set_stylebox("pressed", "Button", stylebox(ACCENT.darkened(0.35), s, 14.0, ACCENT, 2.0, 2.0, Vector2(22, 12)))
	t.set_stylebox("disabled", "Button", stylebox(Color(0.1, 0.11, 0.16, 0.8), s, 14.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(22, 12)))
	var focus := stylebox(Color(0, 0, 0, 0), s, 16.0, ACCENT, 4.0, 0.0, Vector2(0, 0))
	focus.draw_center = false
	focus.expand_margin_left = round(3.0 * s)
	focus.expand_margin_right = round(3.0 * s)
	focus.expand_margin_top = round(3.0 * s)
	focus.expand_margin_bottom = round(3.0 * s)
	t.set_stylebox("focus", "Button", focus)
	t.set_font("font", "Button", bold)
	t.set_font_size("font_size", "Button", font_size("body", s))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_OFF)
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_constant("outline_size", "Button", maxi(2, int(round(5.0 * s))))

	# Progress bars (UiKit.Bar is nicer; this keeps plain ProgressBars on-style)
	t.set_stylebox("background", "ProgressBar", stylebox(Color(0, 0, 0, 0.55), s, 8.0, Color(1, 1, 1, 0.1), 2.0, 0.0, Vector2(0, 0)))
	t.set_stylebox("fill", "ProgressBar", stylebox(ACCENT, s, 8.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(0, 0)))
	t.set_font_size("font_size", "ProgressBar", font_size("small", s))

	# Thin, quiet scroll bars
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, stylebox(Color(1, 1, 1, 0.04), s, 6.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(4, 4)))
		t.set_stylebox("grabber", bar, stylebox(Color(1, 1, 1, 0.25), s, 6.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(4, 4)))
		t.set_stylebox("grabber_highlight", bar, stylebox(Color(1, 1, 1, 0.4), s, 6.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(4, 4)))
		t.set_stylebox("grabber_pressed", bar, stylebox(ACCENT, s, 6.0, Color(0, 0, 0, 0), 0.0, 0.0, Vector2(4, 4)))

	# Containers: comfortable spacing
	t.set_constant("separation", "VBoxContainer", int(round(10.0 * s)))
	t.set_constant("separation", "HBoxContainer", int(round(12.0 * s)))
	t.set_constant("h_separation", "GridContainer", int(round(12.0 * s)))
	t.set_constant("v_separation", "GridContainer", int(round(10.0 * s)))
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		t.set_constant(side, "MarginContainer", int(round(24.0 * s)))

	# RichTextLabel (rarely needed; the built-in font has no bold face, so bold uses the variation)
	t.set_font("normal_font", "RichTextLabel", regular)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_font_size("normal_font_size", "RichTextLabel", font_size("body", s))
	t.set_font_size("bold_font_size", "RichTextLabel", font_size("body", s))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", OUTLINE)
	t.set_constant("outline_size", "RichTextLabel", maxi(2, int(round(5.0 * s))))
	return t


static func _toast_box(s: float, edge: Color) -> StyleBoxFlat:
	var sb := stylebox(Color(0.085, 0.095, 0.16, 0.96), s, 14.0, Color(1, 1, 1, 0.08), 2.0, 10.0, Vector2(18, 10))
	sb.border_color = edge
	sb.border_width_left = maxi(3, int(round(7.0 * s)))
	sb.content_margin_left = round(24.0 * s)
	return sb


# --- Building blocks -------------------------------------------------------------------------------

## A full-screen themed UI root for a view. `parent` may be a CanvasLayer/Control (root added inside),
## e.g. `split.hud(slot)` from core/split_view.gd, or anything else, e.g. Main or a SubViewport (a
## CanvasLayer is made at `layer`). The root ignores the mouse, rescales with its viewport (and
## undoes a scaled parent such as SplitView's HUD roots), and is the place to add panels and HUDs.
static func ui_root(parent: Node, layer: int = 5, fixed_scale: float = 0.0) -> Control:
	var host: Node = parent
	if not (parent is CanvasLayer or parent is Control):
		var cl := CanvasLayer.new()
		cl.layer = layer
		cl.name = "UiLayer"
		parent.add_child(cl)
		host = cl
	var root := UiRoot.new()
	root.name = "UiRoot"
	root.fixed_scale = fixed_scale
	root.theme = theme(fixed_scale if fixed_scale > 0.0 else 1.0)
	host.add_child(root)
	return root


## A rounded panel. style: "default"/"glass", "card", "accent", "toast", "pill", "dialogue", "flat",
## "danger", "success", "info", "tooltip", "clear". Put content inside it (it sizes to its child).
static func panel(style: String = "default") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = PANEL_STYLES.get(style, "PanelContainer")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A panel whose border/edge is tinted (player-coloured cards, coloured toasts). Scale-aware.
static func tinted_panel(color: Color, s: float = 1.0, style: String = "accent") -> PanelContainer:
	var p := panel(style)
	var sb: StyleBoxFlat
	match style:
		"toast":
			sb = _toast_box(s, color)
		"card":
			sb = stylebox(BG_CARD, s, 14.0, color, 3.0, 6.0, Vector2(16, 12))
		"pill":
			sb = stylebox(color.darkened(0.55), s, 200.0, color, 2.0, 0.0, Vector2(14, 4))
		_:
			sb = stylebox(BG, s, 20.0, color, 3.0, 16.0, Vector2(24, 20))
	p.add_theme_stylebox_override("panel", sb)
	return p


## A label of a kind: "banner", "title", "heading", "number", "subtitle", "body", "small", "tiny",
## "dim", "accent". color: optional override (Color, palette name or player index).
static func label(text: String, kind: String = "body", color: Variant = null, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = LABEL_KINDS.get(kind, "Label")
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if color != null:
		l.add_theme_color_override("font_color", color_of(color))
	return l


## A centred title label (bold, letter-spaced).
static func title(text: String, color: Variant = null) -> Label:
	return label(text, "title", color, HORIZONTAL_ALIGNMENT_CENTER)


## A wrapped paragraph (fills the width it is given; set custom_minimum_size.x on it or its parent).
static func paragraph(text: String, kind: String = "body", color: Variant = null, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, kind, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


## VBox / HBox with the theme's spacing (or a custom one at scale 1).
static func vbox(separation: int = -1, s: float = 1.0) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if separation >= 0:
		b.add_theme_constant_override("separation", int(round(separation * s)))
	return b


static func hbox(separation: int = -1, s: float = 1.0) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if separation >= 0:
		b.add_theme_constant_override("separation", int(round(separation * s)))
	return b


## An empty control that expands (push things apart in a box).
static func spacer(min_size: float = 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(min_size, min_size)
	return c


## A pill badge with plain text ("LV 5", "x3", "NEW", "P2"), tinted by `color`. Optional icon kind.
static func badge(text: String, color: Variant = "accent", s: float = 1.0, icon_kind: String = "") -> PanelContainer:
	var c := color_of(color, ACCENT)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", stylebox(c.darkened(0.6), s, 200.0, c, 2.0, 0.0, Vector2(12, 3)))
	var row := hbox(6, s)
	p.add_child(row)
	if icon_kind != "":
		row.add_child(icon(icon_kind, c, 22.0 * s))
	var l := label(text, "small", c.lightened(0.45), HORIZONTAL_ALIGNMENT_CENTER)
	row.add_child(l)
	return p


## A controller/keyboard button glyph: "A" (green disc), "B" (red), "X" (blue), "Y" (yellow), or a key
## cap for anything longer ("LB", "START", "ENTER", "SPACE", "TRIGGER", "STICK").
static func glyph(button: String, s: float = 1.0) -> PanelContainer:
	var colors := {"A": Color(0.36, 0.78, 0.33), "B": Color(0.9, 0.32, 0.3), "X": Color(0.3, 0.55, 0.95), "Y": Color(0.95, 0.78, 0.2)}
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var up := button.to_upper()
	var round_btn := colors.has(up)
	var c: Color = colors.get(up, Color(0.85, 0.87, 0.93))
	var sb: StyleBoxFlat
	if round_btn:
		sb = stylebox(c.darkened(0.15), s, 200.0, c.lightened(0.35), 2.0, 0.0, Vector2(0, 0))
		p.custom_minimum_size = Vector2(38, 38) * s
	else:
		sb = stylebox(Color(0.2, 0.22, 0.3), s, 8.0, Color(0.85, 0.87, 0.93, 0.6), 2.0, 0.0, Vector2(10, 2))
		sb.border_width_bottom = maxi(2, int(round(4.0 * s)))
		p.custom_minimum_size = Vector2(38, 38) * s
	p.add_theme_stylebox_override("panel", sb)
	var l := label(up, "small", Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", font(true))
	l.add_theme_font_size_override("font_size", font_size("small" if round_btn else "tiny", s))
	p.add_child(l)
	return p


## A row of button prompts: pairs like [["A", "Select"], ["B", "Back"]].
static func prompts(pairs: Array, s: float = 1.0) -> HBoxContainer:
	var row := hbox(22, s)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in pairs:
		var a: Array = pair
		var item := hbox(8, s)
		item.add_child(glyph(String(a[0]), s))
		item.add_child(label(String(a[1]), "small", TEXT_DIM))
		row.add_child(item)
	return row


## A vector icon (no font glyphs needed). Kinds: heart, star, coin, gem, sword, shield, potion, skull,
## check, cross, arrow_up/down/left/right, play, clock, bolt, crown, lock, dot, plus, minus, flag, key,
## music, bag, fire, drop, eye, person, trophy, question, exclaim.
static func icon(kind: String, color: Variant = "text", px: float = 32.0) -> Control:
	var ic := Icon.new()
	ic.kind = kind
	ic.color = color_of(color)
	ic.custom_minimum_size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


## An animated bar. kind: "hp" (colour follows the fraction), "mp", "xp", "stamina", or any colour
## via `color`. Call bar.set_value(v, max). See the Bar class for options.
static func bar(kind: String = "hp", width: float = 300.0, height: float = 24.0, color: Variant = null) -> Bar:
	var b := Bar.new()
	b.kind = kind
	if color != null:
		b.fill_color = color_of(color)
	b.base_size = Vector2(width, height)
	return b


## A labelled stat bar: icon/name on the left, bar, and "80/100" text inside it.
static func stat_bar(name: String, kind: String = "hp", width: float = 300.0, color: Variant = null, s: float = 1.0) -> HBoxContainer:
	var row := hbox(10, s)
	var l := label(name, "small", TEXT_DIM)
	l.custom_minimum_size.x = 46.0 * s
	row.add_child(l)
	var b := bar(kind, width, 24.0, color)
	b.show_numbers = true
	b.name = "Bar"
	row.add_child(b)
	return row


## Turn a list of option Strings / partial Dictionaries into full item Dictionaries with id, text,
## disabled, desc, reason, icon, right, badge (used by menus, dialogue choices and the VR menu).
static func normalize_items(list: Variant) -> Array:
	var out: Array = []
	if not (list is Array):
		return out
	for it in list:
		var d: Dictionary
		if it is Dictionary:
			d = (it as Dictionary).duplicate()
		else:
			d = {"text": str(it)}
		if not d.has("text"):
			d["text"] = str(d.get("id", ""))
		if not d.has("id"):
			d["id"] = str(d["text"])
		d["id"] = str(d["id"])
		d["text"] = str(d["text"])
		d["disabled"] = bool(d.get("disabled", false))
		for k in ["desc", "reason", "icon", "right", "badge"]:
			d[k] = str(d.get(k, ""))
		out.append(d)
	return out


# --- Animation -------------------------------------------------------------------------------------

## Pop a control in: fade + overshoot scale from the centre. Returns the Tween.
## (Controls inside containers can't be scaled - containers reset scale - so those just fade.)
static func pop_in(c: Control, delay: float = 0.0, from_scale: float = 0.82, time: float = 0.32) -> Tween:
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	c.modulate.a = 0.0
	var scalable := not (c.get_parent() is Container)
	if scalable:
		c.scale = Vector2.ONE * from_scale
	var t := c.create_tween().set_parallel()
	t.tween_property(c, "modulate:a", 1.0, time * 0.6).set_delay(delay)
	if scalable:
		t.tween_property(c, "scale", Vector2.ONE, time).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


## Pop a control out (shrink + fade), freeing it afterwards unless free_after is false.
static func pop_out(c: Control, free_after: bool = true, delay: float = 0.0, time: float = 0.22) -> Tween:
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	var scalable := not (c.get_parent() is Container)
	var t := c.create_tween().set_parallel()
	t.tween_property(c, "modulate:a", 0.0, time).set_delay(delay)
	if scalable:
		t.tween_property(c, "scale", Vector2.ONE * 0.86, time).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if free_after:
		t.chain().tween_callback(c.queue_free)
	return t


## Slide a control in from `offset` pixels away (scaled), fading in.
static func slide_in(c: Control, offset: Vector2, delay: float = 0.0, time: float = 0.35) -> Tween:
	var end := c.position
	c.position = end + offset
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel()
	t.tween_property(c, "position", end, time).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 1.0, time * 0.7).set_delay(delay)
	return t


## Fade a CanvasItem's alpha to `to`.
static func fade(c: CanvasItem, to: float, time: float = 0.25, delay: float = 0.0) -> Tween:
	var t := c.create_tween()
	t.tween_property(c, "modulate:a", to, time).set_delay(delay)
	return t


## A quick attention pulse (scale up and back; fades brighter for controls inside containers).
static func pulse(c: Control, amount: float = 1.1, time: float = 0.24) -> Tween:
	c.pivot_offset_ratio = Vector2(0.5, 0.5)
	var t := c.create_tween()
	if c.get_parent() is Container:
		t.tween_property(c, "modulate", Color(1.35, 1.35, 1.35, c.modulate.a), time * 0.4)
		t.tween_property(c, "modulate", Color(1, 1, 1, c.modulate.a), time * 0.6)
	else:
		t.tween_property(c, "scale", Vector2.ONE * amount, time * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "scale", Vector2.ONE, time * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


## Shake a control sideways (wrong answer, disabled item). Works inside containers too (uses an offset
## that the container doesn't touch: the control's pivot rotation stays 0, we wobble `position.x`
## only when free, otherwise flash red).
static func shake(c: Control, strength: float = 10.0, time: float = 0.32) -> Tween:
	var t := c.create_tween()
	if c.get_parent() is Container:
		t.tween_property(c, "modulate", Color(1.5, 0.6, 0.6, c.modulate.a), time * 0.3)
		t.tween_property(c, "modulate", Color(1, 1, 1, c.modulate.a), time * 0.7)
		return t
	var x := c.position.x
	for i in 5:
		var k := (1.0 - i / 5.0) * strength * (1.0 if i % 2 == 0 else -1.0)
		t.tween_property(c, "position:x", x + k, time / 6.0)
	t.tween_property(c, "position:x", x, time / 6.0)
	return t


## Count a label up from `from` to `to` (score reveals). fmt gets the int, e.g. "%d PTS".
static func count_up(l: Label, from: int, to: int, time: float = 0.8, fmt: String = "%d", delay: float = 0.0) -> Tween:
	l.text = fmt % from
	var t := l.create_tween()
	t.tween_interval(delay)
	t.tween_method(func(v: float) -> void: l.text = fmt % int(round(v)), float(from), float(to), time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return t


# --- Sound ---------------------------------------------------------------------------------------

## Play a UI sound ("ui_move", "ui_select", ...) on a shared, always-processing sfx node under the root,
## so menus work in any game and while paused.
static func sound(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sfx: Node = tree.root.get_node_or_null("UiKitSfx")
	if sfx == null:
		if Engine.has_meta("ui_kit_sfx_pending"):
			return
		var n: Node = SfxScript.new()
		n.name = "UiKitSfx"
		n.process_mode = Node.PROCESS_MODE_ALWAYS
		Engine.set_meta("ui_kit_sfx_pending", true)
		tree.root.add_child.call_deferred(n)
		n.ready.connect(func() -> void: Engine.remove_meta("ui_kit_sfx_pending"), CONNECT_ONE_SHOT)
		return
	if sfx.is_node_ready():
		sfx.call("play", name, volume_db, pitch)


# --- VR (world-space) building blocks ------------------------------------------------------------

## Render priorities for world-space UI (higher draws on top; all of it skips the depth test).
const VR_PRIO_PANEL := 20
const VR_PRIO_HILITE := 21
const VR_PRIO_TEXT := 23


## A rounded-rectangle panel mesh in the XY plane (front = +Z), w x h metres, with a 1-2 cm border
## and a soft shadow rim. Vertex-coloured; draw it with vr_panel_material(). Cached per look.
static func panel_mesh(size: Vector2, fill: Color = BG, border: Color = Color(1, 1, 1, 0.16), radius: float = 0.05,
		border_w: float = 0.012) -> ArrayMesh:
	var key := "ui_pmesh_%s_%s_%s_%.3f_%.3f_%s" % [size, fill.to_html(), border.to_html(), radius, border_w, VERSION]
	return ResCache.get_or_make(key, func() -> Resource: return Me._make_panel_mesh(size, fill, border, radius, border_w))


static func _make_panel_mesh(size: Vector2, fill: Color, border: Color, radius: float, border_w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var r := minf(radius, minf(half.x, half.y))
	# soft shadow rim (fades out), border ring, fill
	var shadow := Color(0, 0, 0, 0.35 * fill.a)
	var rim := _rounded_rect(half + Vector2(0.025, 0.025), r + 0.025, 6)
	var outer := _rounded_rect(half, r, 6)
	var inner := _rounded_rect(half - Vector2(border_w, border_w), maxf(0.0, r - border_w), 6)
	_ring(st, rim, outer, Color(0, 0, 0, 0.0), shadow, -0.002)
	_ring(st, outer, inner, border, border, 0.0)
	_fan(st, inner, fill, fill.lightened(0.06), 0.001)
	return st.commit()


## Points of a rounded rectangle (counter-clockwise from the right), centred on the origin.
static func _rounded_rect(half: Vector2, r: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var centers: Array[Vector2] = [Vector2(half.x - r, half.y - r), Vector2(-half.x + r, half.y - r),
		Vector2(-half.x + r, -half.y + r), Vector2(half.x - r, -half.y + r)]
	for c in 4:
		for i in seg + 1:
			var a := (c * 0.25 + float(i) / seg * 0.25) * TAU
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * r)
	return pts


## Triangles between two matching outlines (outer -> inner), vertex colours per outline. Front = +Z.
static func _ring(st: SurfaceTool, outer: PackedVector2Array, inner: PackedVector2Array, c_out: Color, c_in: Color, z: float) -> void:
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var a := Vector3(outer[i].x, outer[i].y, z)
		var b := Vector3(outer[j].x, outer[j].y, z)
		var c := Vector3(inner[j].x, inner[j].y, z)
		var d := Vector3(inner[i].x, inner[i].y, z)
		_tri(st, a, c, b, c_out, c_in, c_out)
		_tri(st, a, d, c, c_out, c_in, c_in)


## A filled outline (fan from the centre), centre colour `c_mid` for a subtle sheen.
static func _fan(st: SurfaceTool, pts: PackedVector2Array, c_edge: Color, c_mid: Color, z: float) -> void:
	var n := pts.size()
	var mid := Vector3(0, 0, z)
	for i in n:
		var j := (i + 1) % n
		_tri(st, mid, Vector3(pts[j].x, pts[j].y, z), Vector3(pts[i].x, pts[i].y, z), c_mid, c_edge, c_edge)


## One triangle, clockwise seen from +Z (Godot's front face).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_normal(Vector3.BACK)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(Vector3.BACK)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(Vector3.BACK)
	st.set_color(cc)
	st.add_vertex(c)


## Unshaded, alpha-blended vertex-colour material for world-space UI (skips the depth test so the UI is
## never hidden inside scenery). priority: VR_PRIO_PANEL / VR_PRIO_HILITE.
## billboard: a BaseMaterial3D.BILLBOARD_* mode (FIXED_Y for speech bubbles seen from every TV camera).
static func vr_panel_material(priority: int = VR_PRIO_PANEL, depth_test: bool = false,
		billboard: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_DISABLED) -> StandardMaterial3D:
	return ResCache.get_or_make("ui_vrmat_%d_%s_%d_%s" % [priority, depth_test, billboard, VERSION], func() -> Resource:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = not depth_test
		m.render_priority = priority
		m.disable_fog = true
		m.billboard_mode = billboard
		m.billboard_keep_scale = true
		return m)


## A world-space panel node (MeshInstance3D) of w x h metres in the arcade style. Front faces +Z.
static func panel3d(size: Vector2, fill: Color = BG, border: Color = Color(1, 1, 1, 0.16), radius: float = 0.05) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = panel_mesh(size, fill, border, radius)
	mi.material_override = vr_panel_material(VR_PRIO_PANEL)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A world-space label in the arcade style. `height_m` is the rough cap height in metres; the label is
## never billboarded (VR rule) unless you set it yourself. Front faces +Z.
static func label3d(text: String, height_m: float = 0.06, color: Variant = "text", bold: bool = false, width_m: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font(bold)
	l.font_size = 64
	l.pixel_size = height_m / 64.0 * 1.35
	l.outline_size = 14
	l.modulate = color_of(color)
	l.outline_modulate = Color(0.02, 0.02, 0.06, 0.95)
	l.no_depth_test = false
	l.render_priority = VR_PRIO_TEXT
	l.outline_render_priority = VR_PRIO_TEXT - 1
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if width_m > 0.0:
		l.width = width_m / l.pixel_size
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Wrap `text` into lines that fit `width_px` at `size` px (for typewriter text in Label3D, which has no
## visible_characters: typing the pre-wrapped text keeps words from jumping between lines).
static func wrap_text(text: String, width_px: float, size: int, bold: bool = false) -> String:
	var f := font(bold)
	var out: PackedStringArray = []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var trial := word if line == "" else line + " " + word
			if line != "" and f.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width_px:
				out.append(line)
				line = word
			else:
				line = trial
		out.append(line)
	return "\n".join(out)


## Put a world-space node in front of a camera at `dist` metres (horizontal forward), `height` metres
## above eye level, facing the eyes (its +Z towards the camera). Uses vr_text's comfort factor.
static func vr_place(n: Node3D, cam: Node3D, dist: float = 1.6, height: float = -0.1) -> void:
	if n == null or cam == null or not n.is_inside_tree():
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var pos := cam.global_position + fwd * dist * VrText.COMFORT + Vector3(0.0, height * VrText.COMFORT, 0.0)
	_face(n, pos, cam)
	n.set_meta("vr_placed", true)
	n.set_meta("vr_moving", false)


## Lazy follow for world-space UI (same rules as core/vr_text.gd): stays put while the player looks
## around, glides back in front when they turn more than 35 degrees away or walk off. Call every frame.
static func vr_follow(n: Node3D, cam: Node3D, dist: float = 1.6, height: float = -0.1, delta: float = 0.016) -> void:
	if n == null or cam == null or not n.is_inside_tree() or not cam.is_inside_tree():
		return
	if not n.has_meta("vr_placed"):
		vr_place(n, cam, dist, height)
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var d := dist * VrText.COMFORT
	var target := cam.global_position + fwd * d + Vector3(0.0, height * VrText.COMFORT, 0.0)
	var to := n.global_position - cam.global_position
	to.y = 0.0
	if to.length() < 0.01 or fwd.angle_to(to.normalized()) > deg_to_rad(35.0) or to.length() > d * 1.45 or to.length() < d * 0.55:
		n.set_meta("vr_moving", true)
	if n.get_meta("vr_moving", false):
		_face(n, n.global_position.lerp(target, 1.0 - exp(-4.0 * delta)), cam)
		if n.global_position.distance_to(target) < 0.05 * d:
			n.set_meta("vr_moving", false)


static func _face(n: Node3D, pos: Vector3, cam: Node3D) -> void:
	n.global_position = pos
	var face := pos - cam.global_position
	var flat := Vector3(face.x, 0.0, face.z)
	if flat.length() < 0.01:
		return
	var yaw := atan2(-flat.x, -flat.z)
	# tilt slightly so panels below/above eye level face the eyes
	var pitch := atan2(-face.y, flat.length()) * 0.8
	var sc := n.global_basis.get_scale()
	n.global_basis = Basis.from_euler(Vector3(-pitch, yaw, 0.0), EULER_ORDER_YXZ).scaled(sc)


## The XR camera of the current viewport if it renders VR, else null (for picking VR vs TV behaviour).
static func xr_camera(node: Node) -> Camera3D:
	if node == null or not node.is_inside_tree():
		return null
	var vp := node.get_viewport()
	if vp == null or not vp.use_xr:
		return null
	return vp.get_camera_3d()


# --- Inner classes ---------------------------------------------------------------------------------

class UiRoot extends Control:
	## A full-rect, mouse-transparent root whose Theme follows its viewport's size.
	signal scale_changed(s: float)
	var ui_scale := 1.0
	var fixed_scale := 0.0  ## > 0: always use this scale

	var _queued := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		get_viewport().size_changed.connect(_queue_rescale)
		_rescale()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_queue_rescale()  # e.g. a SplitView HUD root that was re-scaled for a new layout

	func _queue_rescale() -> void:
		if not _queued:
			_queued = true
			_rescale.call_deferred()

	func _rescale() -> void:
		_queued = false
		if not is_inside_tree():
			return
		var s := fixed_scale
		if s <= 0.0:
			s = Me.scale_for_size(get_viewport().get_visible_rect().size)
			# a scaled parent (core/split_view.gd scales its HUD roots) already shrinks us: compensate
			var parent_scale := get_global_transform().get_scale().x / maxf(0.001, scale.x)
			if parent_scale > 0.05:
				s /= parent_scale
		if absf(s - ui_scale) < 0.025 and theme != null:
			return
		ui_scale = s
		theme = Me.theme(s)
		scale_changed.emit(s)


class Icon extends Control:
	## A crisp vector icon drawn in a square (see UiKit.icon for the kinds).
	var kind := "star":
		set(v):
			kind = v
			queue_redraw()
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	var outline := true

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		if r <= 0.5:
			return
		var c := size * 0.5
		var dark := Color(0.02, 0.02, 0.06, 0.85 * color.a)
		var w := maxf(1.5, r * 0.16)
		match kind:
			"heart":
				var pts := PackedVector2Array()
				for i in 40:
					var t := float(i) / 40.0 * TAU
					var x := 16.0 * pow(sin(t), 3.0)
					var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
					pts.append(c + Vector2(x, -y - 1.5) * r / 17.5)
				_poly(pts, color, dark, w)
			"star":
				_poly(_star(c, r * 0.98, r * 0.45, 5, -PI / 2.0), color, dark, w)
			"coin":
				draw_circle(c, r * 0.95, dark)
				draw_circle(c, r * 0.82, color)
				draw_circle(c, r * 0.58, color.darkened(0.18))
				draw_rect(Rect2(c + Vector2(-r * 0.1, -r * 0.36), Vector2(r * 0.2, r * 0.72)), color.lightened(0.3))
			"gem":
				var g := PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.3), c + Vector2(-r * 0.45, -r * 0.8), c + Vector2(r * 0.45, -r * 0.8),
					c + Vector2(r * 0.85, -r * 0.3), c + Vector2(0, r * 0.9)])
				_poly(g, color, dark, w)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.8), c + Vector2(0, -r * 0.3), c + Vector2(-r * 0.85, -r * 0.3)]), color.lightened(0.4))
			"sword":
				var blade := PackedVector2Array([c + Vector2(-r * 0.12, r * 0.25), c + Vector2(-r * 0.12, -r * 0.7), c + Vector2(0, -r * 0.95),
					c + Vector2(r * 0.12, -r * 0.7), c + Vector2(r * 0.12, r * 0.25)])
				_poly(blade, color.lightened(0.3), dark, w)
				draw_rect(Rect2(c + Vector2(-r * 0.5, r * 0.22), Vector2(r, r * 0.16)), color.darkened(0.2))
				draw_rect(Rect2(c + Vector2(-r * 0.09, r * 0.38), Vector2(r * 0.18, r * 0.45)), color.darkened(0.45))
				draw_circle(c + Vector2(0, r * 0.88), r * 0.12, color.darkened(0.2))
			"shield":
				var sh := PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.75), c + Vector2(r * 0.8, -r * 0.75), c + Vector2(r * 0.75, 0.0),
					c + Vector2(r * 0.4, r * 0.6), c + Vector2(0, r * 0.95), c + Vector2(-r * 0.4, r * 0.6), c + Vector2(-r * 0.75, 0.0)])
				_poly(sh, color, dark, w)
				draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.7), color.lightened(0.35), w)
			"potion":
				draw_circle(c + Vector2(0, r * 0.3), r * 0.64, dark)
				draw_circle(c + Vector2(0, r * 0.3), r * 0.55, color)
				draw_rect(Rect2(c + Vector2(-r * 0.2, -r * 0.75), Vector2(r * 0.4, r * 0.55)), Color(0.85, 0.9, 1.0, 0.9))
				draw_rect(Rect2(c + Vector2(-r * 0.28, -r * 0.95), Vector2(r * 0.56, r * 0.22)), Color(0.6, 0.4, 0.25))
				draw_circle(c + Vector2(-r * 0.2, r * 0.15), r * 0.13, color.lightened(0.5))
			"skull":
				draw_circle(c + Vector2(0, -r * 0.1), r * 0.8, dark)
				draw_circle(c + Vector2(0, -r * 0.1), r * 0.7, color)
				draw_rect(Rect2(c + Vector2(-r * 0.4, r * 0.3), Vector2(r * 0.8, r * 0.5)), color)
				draw_circle(c + Vector2(-r * 0.28, -r * 0.1), r * 0.2, dark)
				draw_circle(c + Vector2(r * 0.28, -r * 0.1), r * 0.2, dark)
				for k in 3:
					draw_line(c + Vector2((k - 1) * r * 0.22, r * 0.45), c + Vector2((k - 1) * r * 0.22, r * 0.78), dark, maxf(1.0, w * 0.6))
			"check":
				var ck := PackedVector2Array([c + Vector2(-r * 0.75, 0.0), c + Vector2(-r * 0.25, r * 0.55), c + Vector2(r * 0.8, -r * 0.6)])
				draw_polyline(ck, dark, w * 2.6, true)
				draw_polyline(ck, color, w * 1.6, true)
			"cross":
				for d in [Vector2(1, 1), Vector2(1, -1)]:
					var dv: Vector2 = d
					draw_line(c - dv * r * 0.62, c + dv * r * 0.62, dark, w * 2.6, true)
				for d in [Vector2(1, 1), Vector2(1, -1)]:
					var dv: Vector2 = d
					draw_line(c - dv * r * 0.62, c + dv * r * 0.62, color, w * 1.6, true)
			"arrow_up", "arrow_down", "arrow_left", "arrow_right", "play":
				var ang := {"arrow_up": -PI / 2.0, "arrow_down": PI / 2.0, "arrow_left": PI, "arrow_right": 0.0, "play": 0.0}
				var a: float = ang[kind]
				var tri := PackedVector2Array()
				for k in 3:
					var t := a + k * TAU / 3.0
					tri.append(c + Vector2(cos(t), sin(t)) * r * 0.8)
				_poly(tri, color, dark, w)
			"clock":
				draw_circle(c, r * 0.95, dark)
				draw_circle(c, r * 0.8, color)
				draw_line(c, c + Vector2(0, -r * 0.55), dark, w)
				draw_line(c, c + Vector2(r * 0.4, 0), dark, w)
			"bolt":
				var b := PackedVector2Array([c + Vector2(r * 0.2, -r), c + Vector2(-r * 0.55, r * 0.12), c + Vector2(-r * 0.05, r * 0.12),
					c + Vector2(-r * 0.25, r), c + Vector2(r * 0.6, -r * 0.18), c + Vector2(r * 0.08, -r * 0.18)])
				_poly(b, color, dark, w)
			"crown":
				var cr := PackedVector2Array([c + Vector2(-r * 0.85, r * 0.6), c + Vector2(-r * 0.85, -r * 0.45), c + Vector2(-r * 0.42, 0.0),
					c + Vector2(0, -r * 0.7), c + Vector2(r * 0.42, 0.0), c + Vector2(r * 0.85, -r * 0.45), c + Vector2(r * 0.85, r * 0.6)])
				_poly(cr, color, dark, w)
			"trophy":
				var cup := PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.8), c + Vector2(r * 0.6, -r * 0.8), c + Vector2(r * 0.5, -r * 0.1),
					c + Vector2(r * 0.12, r * 0.25), c + Vector2(r * 0.12, r * 0.55), c + Vector2(r * 0.45, r * 0.85), c + Vector2(-r * 0.45, r * 0.85),
					c + Vector2(-r * 0.12, r * 0.55), c + Vector2(-r * 0.12, r * 0.25), c + Vector2(-r * 0.5, -r * 0.1)])
				draw_arc(c + Vector2(-r * 0.62, -r * 0.4), r * 0.28, PI * 0.5, PI * 1.5, 10, color.darkened(0.2), w)
				draw_arc(c + Vector2(r * 0.62, -r * 0.4), r * 0.28, -PI * 0.5, PI * 0.5, 10, color.darkened(0.2), w)
				_poly(cup, color, dark, w)
			"lock":
				draw_arc(c + Vector2(0, -r * 0.2), r * 0.45, PI, TAU, 12, dark, w * 2.2)
				draw_arc(c + Vector2(0, -r * 0.2), r * 0.45, PI, TAU, 12, color.darkened(0.2), w * 1.3)
				var body := Rect2(c + Vector2(-r * 0.7, -r * 0.2), Vector2(r * 1.4, r * 1.1))
				draw_rect(body.grow(w * 0.6), dark)
				draw_rect(body, color)
				draw_circle(c + Vector2(0, r * 0.3), r * 0.15, dark)
			"key":
				draw_circle(c + Vector2(-r * 0.45, 0), r * 0.42, dark)
				draw_circle(c + Vector2(-r * 0.45, 0), r * 0.32, color)
				draw_circle(c + Vector2(-r * 0.45, 0), r * 0.13, dark)
				draw_line(c + Vector2(-r * 0.1, 0), c + Vector2(r * 0.9, 0), color, w * 1.4)
				draw_line(c + Vector2(r * 0.55, 0), c + Vector2(r * 0.55, r * 0.35), color, w * 1.2)
				draw_line(c + Vector2(r * 0.8, 0), c + Vector2(r * 0.8, r * 0.3), color, w * 1.2)
			"dot":
				draw_circle(c, r * 0.6, dark)
				draw_circle(c, r * 0.48, color)
			"plus", "minus":
				draw_line(c + Vector2(-r * 0.7, 0), c + Vector2(r * 0.7, 0), dark, w * 2.6)
				if kind == "plus":
					draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.7), dark, w * 2.6)
				draw_line(c + Vector2(-r * 0.7, 0), c + Vector2(r * 0.7, 0), color, w * 1.6)
				if kind == "plus":
					draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.7), color, w * 1.6)
			"flag":
				draw_line(c + Vector2(-r * 0.6, -r * 0.9), c + Vector2(-r * 0.6, r * 0.95), dark, w * 1.6)
				_poly(PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.85), c + Vector2(r * 0.8, -r * 0.5), c + Vector2(-r * 0.55, -r * 0.1)]), color, dark, w)
			"music":
				draw_circle(c + Vector2(-r * 0.35, r * 0.55), r * 0.3, color)
				draw_line(c + Vector2(-r * 0.08, r * 0.55), c + Vector2(-r * 0.08, -r * 0.8), color, w * 1.2)
				draw_line(c + Vector2(-r * 0.08, -r * 0.8), c + Vector2(r * 0.55, -r * 0.5), color, w * 1.6)
			"bag":
				draw_circle(c + Vector2(0, r * 0.25), r * 0.72, dark)
				draw_circle(c + Vector2(0, r * 0.25), r * 0.62, color)
				_poly(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.35), c + Vector2(r * 0.3, -r * 0.35), c + Vector2(r * 0.45, -r * 0.85),
					c + Vector2(-r * 0.45, -r * 0.85)]), color.darkened(0.15), dark, w)
			"fire", "drop":
				var f := PackedVector2Array()
				for i in 24:
					var t := float(i) / 24.0 * TAU
					var rad := r * 0.62
					var p := Vector2(sin(t) * rad, -cos(t) * rad)
					if p.y < 0.0:
						p.x *= (1.0 + p.y / rad) if kind == "drop" else (1.0 + p.y / rad * 0.85)
						p.y *= 1.55
					f.append(c + p + Vector2(0, r * 0.25))
				_poly(f, color, dark, w)
				if kind == "fire":
					draw_circle(c + Vector2(0, r * 0.45), r * 0.25, color.lightened(0.5))
			"eye":
				var e := PackedVector2Array()
				for i in 24:
					var t := float(i) / 24.0 * TAU
					e.append(c + Vector2(cos(t) * r * 0.9, sin(t) * r * 0.5))
				_poly(e, Color(0.95, 0.95, 1.0, color.a), dark, w)
				draw_circle(c, r * 0.38, color)
				draw_circle(c, r * 0.16, dark)
			"person":
				draw_circle(c + Vector2(0, -r * 0.42), r * 0.4, dark)
				draw_circle(c + Vector2(0, -r * 0.42), r * 0.32, color)
				draw_circle(c + Vector2(0, r * 0.75), r * 0.72, dark)
				draw_circle(c + Vector2(0, r * 0.75), r * 0.62, color)
			"question", "exclaim":
				draw_circle(c, r * 0.95, dark)
				draw_circle(c, r * 0.82, color)
				var f2 := Me.font(true)
				var fs := int(r * 1.3)
				var txt := "?" if kind == "question" else "!"
				var ts := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(f2, c + Vector2(-ts.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dark)
			_:
				draw_circle(c, r * 0.5, color)

	func _poly(pts: PackedVector2Array, fill: Color, edge: Color, w: float) -> void:
		draw_colored_polygon(pts, fill)
		if outline:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, edge, w, true)

	func _star(c: Vector2, ro: float, ri: float, n: int, rot: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in n * 2:
			var rad := ro if i % 2 == 0 else ri
			var a := rot + float(i) / (n * 2) * TAU
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
		return pts


class Bar extends Control:
	## An animated, rounded stat bar with a trailing "ghost" chip (recent damage drains after a beat),
	## optional numbers ("80/100") and segment ticks. HP bars recolour by fraction and pulse when low.
	## bar.set_value(hp, max_hp)   bar.set_value(v, -1, false)  # no animation
	var kind := "hp"                      ## "hp", "mp", "xp", "stamina" or "custom"
	var fill_color := Color(0, 0, 0, 0)   ## override colour (alpha 0 = from kind)
	var base_size := Vector2(300, 24)     ## size at UI scale 1 (custom_minimum_size follows the scale)
	var show_numbers := false             ## draw "value/max" inside the bar
	var prefix := ""                      ## text before the numbers, e.g. "HP"
	var segments := 0                     ## draw a tick every `segments` units (0 = none)
	var value := 1.0
	var max_value := 1.0
	var shown := 1.0                      ## displayed value (animates towards value)
	var ghost := 1.0                      ## trailing chip value
	var ghost_hold := 0.0
	var flash := 0.0
	var _sb_bg: StyleBoxFlat
	var _sb_fill: StyleBoxFlat
	var _sb_ghost: StyleBoxFlat
	var _s := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restyle()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			_restyle()

	func _restyle() -> void:
		_s = Me.scale_of(self)
		custom_minimum_size = base_size * _s
		var r := base_size.y * 0.5
		_sb_bg = Me.stylebox(Color(0.02, 0.025, 0.05, 0.78), _s, r, Color(1, 1, 1, 0.14), 2.0, 0.0, Vector2.ZERO)
		_sb_fill = Me.stylebox(Color.WHITE, _s, r, Color(0, 0, 0, 0), 0.0, 0.0, Vector2.ZERO)
		_sb_ghost = Me.stylebox(Color(1, 1, 1, 0.85), _s, r, Color(0, 0, 0, 0), 0.0, 0.0, Vector2.ZERO)
		queue_redraw()

	## Set the value (and optionally the max). animate=false jumps straight there.
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
			ghost_hold = 0.45
			flash = 1.0
		elif value > old:
			ghost = value  # gains fill smoothly with no chip
		set_process(true)
		queue_redraw()

	## Current fill colour.
	func current_color() -> Color:
		if fill_color.a > 0.0:
			return fill_color
		var frac := shown / maxf(0.001, max_value)
		match kind:
			"hp":
				return Me.hp_color(frac)
			"mp":
				return Me.MP
			"xp":
				return Me.XP
			"stamina":
				return Color(0.45, 0.95, 0.75)
		return Me.ACCENT

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
		var low := kind == "hp" and value > 0.0 and value / maxf(0.001, max_value) < 0.25
		queue_redraw()
		if not busy and not low:
			set_process(false)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if _sb_bg == null:
			return
		_sb_bg.draw(get_canvas_item(), rect)
		var inset := maxf(2.0, 3.0 * _s)
		var inner := rect.grow(-inset)
		var mx := maxf(0.001, max_value)
		var min_w := inner.size.y  # rounded ends need at least a circle's width
		if ghost > shown + 0.0001:
			var gw := maxf(min_w, inner.size.x * ghost / mx)
			_sb_ghost.bg_color = Color(1, 0.95, 0.85, 0.75)
			_sb_ghost.draw(get_canvas_item(), Rect2(inner.position, Vector2(gw, inner.size.y)))
		if shown > 0.0001:
			var fw := maxf(min_w, inner.size.x * shown / mx)
			var col := current_color()
			if kind == "hp" and value / mx < 0.25 and value > 0.0:
				col = col.lerp(Color.WHITE, 0.25 + 0.25 * sin(Time.get_ticks_msec() * 0.012))
			col = col.lerp(Color.WHITE, flash * 0.6)
			_sb_fill.bg_color = col
			var fr := Rect2(inner.position, Vector2(fw, inner.size.y))
			_sb_fill.draw(get_canvas_item(), fr)
			# glossy top band
			var band := Rect2(fr.position + Vector2(fr.size.y * 0.3, fr.size.y * 0.12), Vector2(maxf(0.0, fr.size.x - fr.size.y * 0.6), fr.size.y * 0.26))
			if band.size.x > 0.0:
				draw_rect(band, Color(1, 1, 1, 0.28))
		if segments > 0 and mx / segments < 60.0:
			var n := int(mx / segments)
			for i in range(1, n):
				var x := inner.position.x + inner.size.x * float(i * segments) / mx
				draw_line(Vector2(x, inner.position.y + 2), Vector2(x, inner.end.y - 2), Color(0, 0, 0, 0.35), maxf(1.0, _s * 1.5))
		if show_numbers or prefix != "":
			var txt := prefix
			if show_numbers:
				txt = ("%s %d/%d" % [prefix, int(round(value)), int(round(max_value))]).strip_edges()
			var f := Me.font(true)
			var fs := maxi(8, int(size.y * 0.66))
			var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var pos := Vector2((size.x - ts.x) * 0.5, (size.y + fs * 0.7) * 0.5)
			draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.22)), Me.OUTLINE)
			draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
