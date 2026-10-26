extends RefCounted
## StoryCard: short story beats told with a picture and one short line, for every game's light story.
## Never blocks play and never needs a button: the card slides in, stays a few seconds, slides out.
## A newer card replaces the one showing. TV: a card at the top of each view (under the timer), so the
## picture and the words are big on a Deck too. VR: a world-space card a little below eye level.
##   const StoryCard := preload("res://core/story_card.gd")
##   StoryCard.show(huds_array, {"who": "PIP", "line": "The wind took my letters!", "pic": "bird",
##       "color": Color(1, 0.7, 0.3), "duration": 4.0})
##   StoryCard.show_vr(self, vr_rig.camera, same_opts)   # opts.vr_height: card height vs the eyes (-0.22)
##   StoryCard.picture("envelope", 96.0, color)   # just the picture Control (results screens, maps)
## Pictures (drawn in code, no textures): bird, envelope, cloud, storm, house, sprite (a wind sprite),
## sun, wave, tree, castle, kaiju (a friendly monster face in `color`), penguin (Tumble, with a scarf),
## snowman, tophat, beanie, gift (a present), and the Kitchen Rush guest faces granny, kid, pirate, robot,
## alien, knight; anything else is a core/ui_kit.gd icon kind ("star", "heart", "crown"...).
## Keep lines short and kind: kids read the screen.

const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")

const PICTURES: Array[String] = ["bird", "envelope", "cloud", "storm", "house", "sprite", "sun", "wave", "tree", "castle", "kaiju",
	"penguin", "snowman", "tophat", "beanie", "gift", "granny", "kid", "pirate", "robot", "alien", "knight"]


## Show a story card on one view root or an Array of them. Returns the first card made (or null).
static func show(root: Variant, opts: Dictionary) -> Control:
	if root is Array:
		var first: Control = null
		for r in root:
			var c := show(r, opts)
			if first == null:
				first = c
		return first
	var parent := root as Control
	if parent == null or not is_instance_valid(parent):
		return null
	for old in parent.get_children():
		if old is Card:
			(old as Card).leave()
	var c := Card.new()
	c.opts = opts
	parent.add_child(c)
	return c


## The VR card (a HudKit VrCard): title = who, body = the line. Returns it.
static func show_vr(world: Node, cam: Node3D, opts: Dictionary) -> Node3D:
	if world == null or cam == null:
		return null
	return HudKit.vr_card(world, cam, String(opts.get("who", "")), String(opts.get("line", "")),
		{"duration": float(opts.get("duration", 4.0)), "color": opts.get("color", "accent"), "width": 1.0,
		"height": float(opts.get("vr_height", -0.22)), "title_size": 0.07, "body_size": 0.055})


## A picture Control `px` pixels square (see PICTURES; other names use UiKit icons).
static func picture(kind: String, px: float = 96.0, color: Color = Color(1.0, 0.75, 0.3)) -> Control:
	return StoryCardPics.make(kind, px, color)


class Card extends Control:
	const UiKit := preload("res://core/ui_kit.gd")
	var opts := {}
	var panel: PanelContainer
	var t := 0.0
	var leaving := false
	var _s := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_s = UiKit.scale_of(self)
		var col: Color = UiKit.color_of(opts.get("color", "accent"), UiKit.ACCENT)
		panel = UiKit.panel("dialogue")
		panel.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.BG_DEEP, _s, 24.0, Color(col.r, col.g, col.b, 0.7), 3.0, 18.0, Vector2(22, 16)))
		add_child(panel)
		var row := UiKit.hbox(18, _s)
		panel.add_child(row)
		var disc := PanelContainer.new()
		disc.add_theme_stylebox_override("panel", UiKit.stylebox(col.darkened(0.45), _s, 200.0, col.lightened(0.3), 4.0, 0.0, Vector2(6, 6)))
		disc.custom_minimum_size = Vector2(112, 112) * _s
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(disc)
		disc.add_child(StoryCardPics.make(String(opts.get("pic", "star")), 92.0 * _s, col.lightened(0.15)))
		var v := UiKit.vbox(4, _s)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(v)
		var who := String(opts.get("who", ""))
		if who != "":
			v.add_child(UiKit.label(who, "heading", col.lightened(0.45)))
		var line := UiKit.paragraph(String(opts.get("line", "")), "body")
		line.add_theme_font_size_override("font_size", UiKit.font_size("body", _s) + int(4 * _s))
		line.custom_minimum_size.x = 520.0 * _s
		v.add_child(line)
		resized.connect(_place)
		panel.resized.connect(_place)
		_place.call_deferred()
		modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.25)
		var snd := String(opts.get("sound", "ui_notify"))
		if snd != "":
			UiKit.sound(snd, -6.0)

	func _place() -> void:
		if panel == null:
			return
		var w := minf(panel.get_combined_minimum_size().x, size.x - 40.0 * _s)
		panel.size = Vector2(w, panel.get_combined_minimum_size().y)
		var y := float(opts.get("y", 0.13)) * size.y
		panel.position = Vector2((size.x - w) * 0.5, y)

	func leave() -> void:
		if leaving:
			return
		leaving = true
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)

	func _process(delta: float) -> void:
		t += delta
		if not leaving and t > float(opts.get("duration", 4.0)):
			leave()


## Builds pictures (a tiny indirection so Card, an inner class, can reach the outer static func).
class StoryCardPics:
	static func make(kind: String, px: float, color: Color) -> Control:
		if not PICTURES.has(kind):
			var ic := UiKit.icon(kind, color, px)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return ic
		var p := Picture.new()
		p.kind = kind
		p.color = color
		p.custom_minimum_size = Vector2(px, px)
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return p


## Simple friendly vector pictures, drawn in a unit box scaled to the control.
class Picture extends Control:
	var kind := "bird"
	var color := Color(1.0, 0.75, 0.3)
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _p(x: float, y: float) -> Vector2:
		return Vector2(x, y) * size

	func _circle(x: float, y: float, r: float, c: Color) -> void:
		draw_circle(_p(x, y), r * size.x, c)

	func _poly(pts: Array, c: Color) -> void:
		var arr := PackedVector2Array()
		for q in pts:
			arr.append(_p(q[0], q[1]))
		draw_colored_polygon(arr, c)

	func _eye(x: float, y: float, r: float) -> void:
		_circle(x, y, r, Color.WHITE)
		_circle(x + r * 0.2, y, r * 0.55, Color(0.1, 0.1, 0.15))

	func _draw() -> void:
		var bob := sin(t * 3.0) * 0.02
		var white := Color(1.0, 1.0, 1.0)
		match kind:
			"bird":
				_circle(0.5, 0.55 + bob, 0.3, color)
				_circle(0.5, 0.62 + bob, 0.18, color.lightened(0.45))
				_poly([[0.78, 0.45 + bob], [0.98, 0.52 + bob], [0.78, 0.58 + bob]], Color(1.0, 0.6, 0.15))
				_eye(0.62, 0.42 + bob, 0.07)
				var flap := sin(t * 9.0) * 0.08
				_poly([[0.3, 0.55 + bob], [0.05, 0.4 + bob - flap], [0.22, 0.7 + bob]], color.darkened(0.25))
				# Pip's postie cap.
				_poly([[0.32, 0.3 + bob], [0.68, 0.3 + bob], [0.62, 0.17 + bob], [0.38, 0.17 + bob]], Color(0.25, 0.45, 0.95))
				_poly([[0.6, 0.3 + bob], [0.8, 0.3 + bob], [0.68, 0.25 + bob]], Color(0.2, 0.35, 0.8))
			"envelope":
				_poly([[0.1, 0.28 + bob], [0.9, 0.28 + bob], [0.9, 0.78 + bob], [0.1, 0.78 + bob]], white)
				_poly([[0.1, 0.28 + bob], [0.9, 0.28 + bob], [0.5, 0.58 + bob]], Color(0.88, 0.9, 0.96))
				_circle(0.5, 0.58 + bob, 0.07, Color(0.95, 0.3, 0.35))
			"cloud", "storm":
				var c := white if kind == "cloud" else Color(0.45, 0.47, 0.6)
				for b in [[0.3, 0.55, 0.17], [0.5, 0.45, 0.22], [0.7, 0.55, 0.17], [0.5, 0.62, 0.17]]:
					_circle(b[0], b[1] + bob, b[2], c)
				if kind == "storm":
					_eye(0.42, 0.5 + bob, 0.05)
					_eye(0.58, 0.5 + bob, 0.05)
					if fmod(t, 1.4) < 0.25:
						_poly([[0.52, 0.72], [0.42, 0.88], [0.5, 0.86], [0.44, 1.0], [0.6, 0.82], [0.52, 0.83]], Color(1.0, 0.9, 0.3))
			"house":
				_poly([[0.2, 0.5], [0.8, 0.5], [0.8, 0.88], [0.2, 0.88]], color)
				_poly([[0.12, 0.52], [0.5, 0.18], [0.88, 0.52]], Color(0.85, 0.3, 0.3))
				_poly([[0.43, 0.65], [0.57, 0.65], [0.57, 0.88], [0.43, 0.88]], Color(0.45, 0.28, 0.15))
				_poly([[0.26, 0.58], [0.38, 0.58], [0.38, 0.7], [0.26, 0.7]], Color(1.0, 0.9, 0.5))
			"sprite":
				_circle(0.5, 0.48 + bob, 0.27, Color(0.75, 0.9, 1.0))
				for i in 3:
					var a := t * 2.0 + i * TAU / 3.0
					_circle(0.5 + cos(a) * 0.36, 0.48 + sin(a) * 0.36 + bob, 0.06, Color(0.85, 0.95, 1.0, 0.8))
				_eye(0.42, 0.44 + bob, 0.055)
				_eye(0.58, 0.44 + bob, 0.055)
				draw_arc(_p(0.5, 0.55 + bob), 0.08 * size.x, 0.2, PI - 0.2, 10, Color(0.2, 0.3, 0.5), 0.02 * size.x)
			"sun":
				for i in 8:
					var a := t * 0.5 + i * TAU / 8.0
					draw_line(_p(0.5, 0.5), _p(0.5 + cos(a) * 0.45, 0.5 + sin(a) * 0.45), Color(1.0, 0.8, 0.2), 0.05 * size.x)
				_circle(0.5, 0.5, 0.25, Color(1.0, 0.85, 0.3))
			"wave":
				_poly([[0.05, 0.6 + bob], [0.3, 0.45], [0.55, 0.6 - bob], [0.8, 0.45], [0.95, 0.6], [0.95, 0.9], [0.05, 0.9]], Color(0.3, 0.6, 1.0))
				_circle(0.75, 0.25, 0.1, Color(1.0, 0.85, 0.3))
			"tree":
				_poly([[0.44, 0.6], [0.56, 0.6], [0.56, 0.92], [0.44, 0.92]], Color(0.5, 0.32, 0.18))
				_circle(0.5, 0.42, 0.28, Color(0.35, 0.75, 0.35))
				for a in [[0.4, 0.35], [0.62, 0.45], [0.48, 0.55]]:
					_circle(a[0], a[1], 0.05, Color(0.95, 0.3, 0.3))
			"penguin":
				_circle(0.5, 0.58 + bob, 0.3, Color(0.12, 0.14, 0.22))
				_circle(0.5, 0.64 + bob, 0.21, white)
				_circle(0.5, 0.3 + bob, 0.2, Color(0.12, 0.14, 0.22))
				_eye(0.43, 0.28 + bob, 0.055)
				_eye(0.57, 0.28 + bob, 0.055)
				_poly([[0.44, 0.36 + bob], [0.56, 0.36 + bob], [0.5, 0.43 + bob]], Color(1.0, 0.65, 0.15))
				_poly([[0.3, 0.44 + bob], [0.7, 0.44 + bob], [0.7, 0.5 + bob], [0.3, 0.5 + bob]], Color(0.92, 0.2, 0.25))
				_poly([[0.6, 0.48 + bob], [0.7, 0.48 + bob], [0.68, 0.66 + bob], [0.6, 0.64 + bob]], Color(0.92, 0.2, 0.25))
				var wave := sin(t * 6.0) * 0.06
				_poly([[0.22, 0.5 + bob], [0.1, 0.62 + bob - wave], [0.24, 0.7 + bob]], Color(0.12, 0.14, 0.22))
				_poly([[0.38, 0.86], [0.48, 0.86], [0.43, 0.92]], Color(1.0, 0.65, 0.15))
				_poly([[0.52, 0.86], [0.62, 0.86], [0.57, 0.92]], Color(1.0, 0.65, 0.15))
			"snowman":
				_circle(0.5, 0.72, 0.21, white)
				_circle(0.5, 0.43 + bob * 0.5, 0.15, white)
				_circle(0.5, 0.2 + bob, 0.11, white)
				_eye(0.46, 0.18 + bob, 0.03)
				_eye(0.54, 0.18 + bob, 0.03)
				_poly([[0.5, 0.21 + bob], [0.66, 0.23 + bob], [0.5, 0.25 + bob]], Color(1.0, 0.5, 0.1))
				_poly([[0.4, 0.1 + bob], [0.6, 0.1 + bob], [0.57, -0.02 + bob], [0.43, -0.02 + bob]], Color(0.1, 0.1, 0.14))
				for k in 2:
					_circle(0.5, 0.4 + k * 0.08 + bob * 0.5, 0.018, Color(0.1, 0.1, 0.14))
				draw_line(_p(0.36, 0.42), _p(0.16, 0.32 - bob), Color(0.45, 0.28, 0.15), 0.025 * size.x)
				draw_line(_p(0.64, 0.42), _p(0.84, 0.32 + bob), Color(0.45, 0.28, 0.15), 0.025 * size.x)
			"tophat":
				_poly([[0.15, 0.72 + bob], [0.85, 0.72 + bob], [0.85, 0.8 + bob], [0.15, 0.8 + bob]], Color(0.1, 0.1, 0.14))
				_poly([[0.28, 0.25 + bob], [0.72, 0.25 + bob], [0.72, 0.74 + bob], [0.28, 0.74 + bob]], Color(0.1, 0.1, 0.14))
				_poly([[0.28, 0.58 + bob], [0.72, 0.58 + bob], [0.72, 0.68 + bob], [0.28, 0.68 + bob]], Color(0.95, 0.2, 0.25))
			"beanie":
				var dome: Array = []
				for i in 13:
					var a := PI + PI * i / 12.0
					dome.append([0.5 + cos(a) * 0.36, 0.74 + sin(a) * 0.4 + bob])
				_poly(dome, Color(0.9, 0.22, 0.28))
				_poly([[0.1, 0.7 + bob], [0.9, 0.7 + bob], [0.9, 0.84 + bob], [0.1, 0.84 + bob]], white)
				_circle(0.5, 0.3 + bob, 0.09, white)
			"kaiju":
				for k in 3:  # back spikes
					var x := 0.32 + k * 0.18
					_poly([[x - 0.07, 0.3 + bob], [x, 0.1 + bob], [x + 0.07, 0.3 + bob]], color.lightened(0.35))
				_circle(0.5, 0.55 + bob, 0.33, color)
				_circle(0.5, 0.68 + bob, 0.2, color.lightened(0.4))
				_eye(0.39, 0.47 + bob, 0.08)
				_eye(0.61, 0.47 + bob, 0.08)
				draw_arc(_p(0.5, 0.64 + bob), 0.11 * size.x, 0.25, PI - 0.25, 12, Color(0.2, 0.1, 0.12), 0.025 * size.x)
				_poly([[0.44, 0.7 + bob], [0.47, 0.75 + bob], [0.5, 0.7 + bob]], Color.WHITE)
				_poly([[0.5, 0.7 + bob], [0.53, 0.75 + bob], [0.56, 0.7 + bob]], Color.WHITE)
				_circle(0.3, 0.6 + bob, 0.04, Color(1.0, 0.55, 0.65, 0.8))
				_circle(0.7, 0.6 + bob, 0.04, Color(1.0, 0.55, 0.65, 0.8))
			"gift":
				_poly([[0.18, 0.45 + bob], [0.82, 0.45 + bob], [0.82, 0.9 + bob], [0.18, 0.9 + bob]], color)
				_poly([[0.12, 0.34 + bob], [0.88, 0.34 + bob], [0.88, 0.47 + bob], [0.12, 0.47 + bob]], color.lightened(0.2))
				_poly([[0.45, 0.34 + bob], [0.55, 0.34 + bob], [0.55, 0.9 + bob], [0.45, 0.9 + bob]], Color(0.95, 0.3, 0.4))
				_circle(0.4, 0.27 + bob, 0.09, Color(0.95, 0.3, 0.4))
				_circle(0.6, 0.27 + bob, 0.09, Color(0.95, 0.3, 0.4))
				_circle(0.5, 0.31 + bob, 0.05, Color(1.0, 0.5, 0.55))
			"granny", "kid", "pirate", "robot", "alien", "knight":
				_guest(kind, bob)
			"castle":
				_poly([[0.2, 0.45], [0.8, 0.45], [0.8, 0.85], [0.2, 0.85]], Color(0.85, 0.88, 1.0))
				for x in [0.2, 0.44, 0.68]:
					_poly([[x, 0.35], [x + 0.12, 0.35], [x + 0.12, 0.45], [x, 0.45]], Color(0.85, 0.88, 1.0))
				_poly([[0.42, 0.62], [0.58, 0.62], [0.58, 0.85], [0.42, 0.85]], Color(0.5, 0.55, 0.85))
				for b in [[0.15, 0.85, 0.12], [0.35, 0.9, 0.14], [0.65, 0.9, 0.14], [0.85, 0.85, 0.12]]:
					_circle(b[0], b[1], b[2], white)


	## A round friendly guest face with their hat (the Kitchen Rush party guests).
	func _guest(who: String, bob: float) -> void:
		var skin := {"granny": Color(0.98, 0.82, 0.78), "kid": Color(1.0, 0.75, 0.55), "pirate": Color(0.95, 0.75, 0.55),
			"robot": Color(0.72, 0.76, 0.82), "alien": Color(0.45, 0.95, 0.4), "knight": Color(0.95, 0.8, 0.65)}.get(who, color) as Color
		var y := 0.58 + bob
		if who == "knight":
			_circle(0.5, y - 0.04, 0.33, Color(0.75, 0.77, 0.82))
			_poly([[0.47, y - 0.36], [0.53, y - 0.36], [0.6, y - 0.52], [0.4, y - 0.52]], Color(0.95, 0.2, 0.25))
		if who == "robot":
			_poly([[0.22, y - 0.25], [0.78, y - 0.25], [0.78, y + 0.27], [0.22, y + 0.27]], skin)
			draw_line(_p(0.5, y - 0.25), _p(0.5, y - 0.4), Color(0.4, 0.4, 0.45), 0.02 * size.x)
			_circle(0.5, y - 0.42, 0.05, Color(1.0, 0.25, 0.25) if fmod(t, 1.0) < 0.5 else Color(0.6, 0.15, 0.15))
			_poly([[0.3, y - 0.08], [0.43, y - 0.08], [0.43, y + 0.02], [0.3, y + 0.02]], Color(0.4, 0.9, 1.0))
			_poly([[0.57, y - 0.08], [0.7, y - 0.08], [0.7, y + 0.02], [0.57, y + 0.02]], Color(0.4, 0.9, 1.0))
			_poly([[0.38, y + 0.13], [0.62, y + 0.13], [0.62, y + 0.17], [0.38, y + 0.17]], Color(0.25, 0.25, 0.3))
			return
		if who == "alien":
			for x in [0.35, 0.65]:
				draw_line(_p(0.5 + (x - 0.5) * 0.6, y - 0.22), _p(x, y - 0.42), Color(0.3, 0.75, 0.3), 0.02 * size.x)
				_circle(x, y - 0.43, 0.05, Color(1.0, 0.4, 0.9))
		_circle(0.5, y, 0.28 if who != "knight" else 0.2, skin)
		if who == "granny":
			_circle(0.5, y - 0.3, 0.1, Color(0.92, 0.92, 0.95))
			_circle(0.3, y - 0.18, 0.1, Color(0.92, 0.92, 0.95))
			_circle(0.7, y - 0.18, 0.1, Color(0.92, 0.92, 0.95))
		var er := 0.055 if who != "knight" else 0.045
		_eye(0.4, y - 0.03, er)
		_eye(0.6, y - 0.03, er)
		if who == "alien":
			_eye(0.5, y - 0.15, 0.045)
		if who == "granny":
			draw_arc(_p(0.4, y - 0.03), 0.075 * size.x, 0.0, TAU, 14, Color(0.75, 0.6, 0.2), 0.015 * size.x)
			draw_arc(_p(0.6, y - 0.03), 0.075 * size.x, 0.0, TAU, 14, Color(0.75, 0.6, 0.2), 0.015 * size.x)
		draw_arc(_p(0.5, y + 0.07), 0.09 * size.x, 0.3, PI - 0.3, 10, Color(0.35, 0.1, 0.12), 0.022 * size.x)
		_circle(0.32, y + 0.08, 0.035, Color(1.0, 0.55, 0.65, 0.7))
		_circle(0.68, y + 0.08, 0.035, Color(1.0, 0.55, 0.65, 0.7))
		match who:
			"kid":
				_poly([[0.25, y - 0.18], [0.75, y - 0.18], [0.65, y - 0.3], [0.35, y - 0.3]], Color(0.3, 0.6, 1.0))
				var spin := sin(t * 10.0) * 0.18
				draw_line(_p(0.5, y - 0.3), _p(0.5, y - 0.38), Color(0.3, 0.3, 0.3), 0.02 * size.x)
				draw_line(_p(0.5 - spin, y - 0.39), _p(0.5 + spin, y - 0.39), Color(1.0, 0.3, 0.3), 0.04 * size.x)
			"pirate":
				_poly([[0.15, y - 0.2], [0.85, y - 0.2], [0.72, y - 0.42], [0.5, y - 0.36], [0.28, y - 0.42]], Color(0.12, 0.1, 0.12))
				_circle(0.5, y - 0.3, 0.035, Color.WHITE)
				_circle(0.6, y - 0.03, 0.065, Color(0.08, 0.08, 0.1))
				draw_line(_p(0.6, y - 0.03), _p(0.78, y - 0.2), Color(0.08, 0.08, 0.1), 0.015 * size.x)
			"knight":
				_poly([[0.3, y - 0.07], [0.7, y - 0.07], [0.7, y - 0.03], [0.3, y - 0.03]], Color(0.75, 0.77, 0.82, 0.6))
