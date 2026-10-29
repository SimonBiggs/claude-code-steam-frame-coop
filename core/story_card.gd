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
## alien, knight; Kart Race's kart (a little race kart in `color`), partyhat, cowboy (hat), wizard (hat);
## Whack-a-Mole's farmer (Fig), mole (fur = color), bunny and crops lettuce, carrot, pumpkin, sunflower,
## strawberry, corn, melon, apple; Party Board's toucan (Mango);
## Fishing Lake's fish (body = color) and otter (Ollie, who keeps the fish book); Hide and Seek's puppy (Pip:
## fur = color, floppy ears, a wagging tongue); Obstacle Rush's coach (Coach Jelly: an orange jelly bean in a blue
## cap with a whistle) and balloon (in color); Sheep Round-Up's shepherd (Bo: a bonnet in color, curls, a crook)
## and sheep (wool = color); Starship Crew's captain (Captain Whiskers: a ginger cat in a bubble helmet), planet
## (in color, with a ring), station (the space station wheel) and rocket; Balloon Pop's seller (Poppy: a smiling
## face in a party hat with a bunch of balloons) and her fair rides icecream, carousel, ferris (the big wheel) and
## tent (the big top); Tiny Town Tycoon's beaver (Benny the builder beaver in a yellow hard hat), island (a little
## green island with a palm in the sea) and boat (a sailing boat on the waves, sail in color); Crystal Saga's lumi
## (Lumi: a little glowing crystal fairy), shard (a crystal shard), the skills bigfire, snowflake (ice), twin (two
## sparks), longsword, spin (a sword in a whirl), mighty (a big golden sword), and Willowbrook's windmill, fountain
## and rainbow; Rocket Workshop's engineer (Sprocket: a teal robot in an orange hard hat with a spanner) and
## toyrocket (the rocket with its nose and fins in color); Tower Stack's wren (Wren: a little brown builder bird in
## a blue hard hat) and tower (a stack of jelly blocks in color under a red roof); anything else is a core/ui_kit.gd icon kind ("star", "heart", "crown"...).
## Keep lines short and kind: kids read the screen.

const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")

const PICTURES: Array[String] = ["bird", "envelope", "cloud", "storm", "house", "sprite", "sun", "wave", "tree", "castle", "kaiju",
	"penguin", "snowman", "tophat", "beanie", "gift", "granny", "kid", "pirate", "robot", "alien", "knight",
	"kart", "partyhat", "cowboy", "wizard",
	"farmer", "mole", "bunny", "lettuce", "carrot", "pumpkin", "sunflower", "strawberry", "corn", "melon", "apple",
	"toucan", "fish", "otter", "puppy", "coach", "balloon", "shepherd", "sheep",
	"beaver", "island", "boat",
	"captain", "planet", "station", "rocket", "seller", "icecream", "carousel", "ferris", "tent",
	"lumi", "shard", "bigfire", "snowflake", "twin", "longsword", "spin", "mighty", "windmill", "fountain", "rainbow",
	"engineer", "toyrocket",
	"wren", "tower"]


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
			"kart":
				var roll := t * 8.0
				_poly([[0.12, 0.6 + bob], [0.88, 0.6 + bob], [0.82, 0.74 + bob], [0.18, 0.74 + bob]], color)
				_poly([[0.62, 0.48 + bob], [0.82, 0.48 + bob], [0.88, 0.6 + bob], [0.6, 0.6 + bob]], color.lightened(0.25))
				_poly([[0.1, 0.44 + bob], [0.24, 0.44 + bob], [0.24, 0.6 + bob], [0.1, 0.6 + bob]], color.darkened(0.2))
				_circle(0.42, 0.42 + bob, 0.12, Color(0.97, 0.97, 1.0))
				_poly([[0.44, 0.38 + bob], [0.56, 0.38 + bob], [0.56, 0.45 + bob], [0.44, 0.45 + bob]], Color(0.2, 0.6, 1.0))
				for x in [0.27, 0.73]:
					_circle(x, 0.78, 0.1, Color(0.1, 0.1, 0.12))
					draw_line(_p(x, 0.78), _p(x + cos(roll) * 0.07, 0.78 + sin(roll) * 0.07), Color(0.85, 0.85, 0.9), 0.02 * size.x)
				for k in 3:
					var x := 0.02 - fmod(t * 0.6 + k * 0.33, 1.0) * 0.1
					_circle(0.06 + x, 0.66 + k * 0.04, 0.025, Color(1.0, 1.0, 1.0, 0.6))
			"partyhat":
				_poly([[0.2, 0.86 + bob], [0.8, 0.86 + bob], [0.5, 0.14 + bob]], color)
				for k in 3:
					var y := 0.36 + k * 0.18
					var w := (y - 0.14) / 0.72 * 0.3
					_poly([[0.5 - w, y + bob], [0.5 + w, y + bob], [0.5 + w + 0.025, y + 0.06 + bob], [0.5 - w - 0.025, y + 0.06 + bob]], Color(1.0, 0.95, 0.4))
				_circle(0.5, 0.13 + bob, 0.08, white)
			"cowboy":
				_poly([[0.05, 0.66 + bob], [0.95, 0.66 + bob], [0.85, 0.76 + bob], [0.15, 0.76 + bob]], Color(0.6, 0.38, 0.2))
				_poly([[0.3, 0.68 + bob], [0.7, 0.68 + bob], [0.66, 0.3 + bob], [0.5, 0.38 + bob], [0.34, 0.3 + bob]], Color(0.68, 0.45, 0.25))
				_poly([[0.31, 0.58 + bob], [0.69, 0.58 + bob], [0.69, 0.64 + bob], [0.31, 0.64 + bob]], Color(0.95, 0.3, 0.3))
			"wizard":
				_poly([[0.08, 0.8 + bob], [0.92, 0.8 + bob], [0.82, 0.88 + bob], [0.18, 0.88 + bob]], color.darkened(0.2))
				_poly([[0.26, 0.82 + bob], [0.74, 0.82 + bob], [0.6, 0.35 + bob], [0.72, 0.1 + bob], [0.5, 0.3 + bob]], color)
				for st_p in [[0.45, 0.6], [0.58, 0.42], [0.5, 0.74]]:
					_circle(st_p[0], st_p[1] + bob, 0.035 + 0.01 * sin(t * 5.0 + st_p[0] * 9.0), Color(1.0, 0.92, 0.35))
			"farmer":  # Farmer Fig (Whack-a-Mole): a round face under a big straw hat, a sprig on top
				_circle(0.5, 0.6 + bob, 0.26, Color(0.98, 0.78, 0.6))
				_poly([[0.08, 0.42 + bob], [0.92, 0.42 + bob], [0.8, 0.36 + bob], [0.2, 0.36 + bob]], Color(0.95, 0.8, 0.35))
				_poly([[0.28, 0.37 + bob], [0.72, 0.37 + bob], [0.66, 0.16 + bob], [0.34, 0.16 + bob]], Color(0.95, 0.8, 0.35))
				_poly([[0.28, 0.33 + bob], [0.72, 0.33 + bob], [0.71, 0.28 + bob], [0.29, 0.28 + bob]], color)
				_eye(0.41, 0.58 + bob, 0.05)
				_eye(0.59, 0.58 + bob, 0.05)
				draw_arc(_p(0.5, 0.66 + bob), 0.09 * size.x, 0.3, PI - 0.3, 10, Color(0.4, 0.15, 0.12), 0.022 * size.x)
				_circle(0.33, 0.68 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
				_circle(0.67, 0.68 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
				draw_line(_p(0.62, 0.17 + bob), _p(0.7, 0.04 + bob), Color(0.3, 0.6, 0.25), 0.025 * size.x)
				_circle(0.72, 0.05 + bob, 0.04, Color(0.4, 0.8, 0.3))
			"mole", "bunny":  # a cheeky mole (fur = color) or a white bunny peeking from a hole
				_poly([[0.12, 0.82], [0.88, 0.82], [0.8, 0.94], [0.2, 0.94]], Color(0.35, 0.22, 0.12))
				var fur := color if kind == "mole" else Color(0.97, 0.97, 1.0)
				if kind == "bunny":
					for x in [0.38, 0.62]:
						_poly([[x - 0.06, 0.35 + bob], [x, 0.02 + bob], [x + 0.06, 0.35 + bob]], fur)
						_poly([[x - 0.03, 0.33 + bob], [x, 0.1 + bob], [x + 0.03, 0.33 + bob]], Color(1.0, 0.7, 0.78))
				_circle(0.5, 0.58 + bob, 0.27, fur)
				_poly([[0.23, 0.6 + bob], [0.77, 0.6 + bob], [0.77, 0.85], [0.23, 0.85]], fur)
				_circle(0.5, 0.68 + bob, 0.14, fur.lightened(0.35))
				_eye(0.41, 0.5 + bob, 0.055)
				_eye(0.59, 0.5 + bob, 0.055)
				_circle(0.5, 0.6 + bob, 0.05, Color(1.0, 0.55, 0.65))
				if kind == "mole":
					_poly([[0.46, 0.66 + bob], [0.54, 0.66 + bob], [0.54, 0.71 + bob], [0.46, 0.71 + bob]], white)
			"lettuce", "carrot", "pumpkin", "sunflower", "strawberry", "corn", "melon", "apple":
				_veg(kind, bob)
			"puppy":  # Pip (Hide and Seek): a round puppy face (fur = color), floppy brown ears, a pink tongue
				var ear := Color(0.38, 0.24, 0.16)
				var wag := sin(t * 5.0) * 0.03
				_poly([[0.22, 0.3 + bob], [0.34, 0.26 + bob], [0.3, 0.62 + bob + wag], [0.16, 0.58 + bob + wag]], ear)
				_poly([[0.78, 0.3 + bob], [0.66, 0.26 + bob], [0.7, 0.62 + bob - wag], [0.84, 0.58 + bob - wag]], ear)
				_circle(0.5, 0.5 + bob, 0.28, color)
				_circle(0.5, 0.64 + bob, 0.14, Color(1.0, 0.93, 0.82))
				_eye(0.4, 0.45 + bob, 0.055)
				_eye(0.6, 0.45 + bob, 0.055)
				_circle(0.5, 0.58 + bob, 0.045, Color(0.2, 0.12, 0.1))
				if fmod(t, 1.6) < 1.0:
					_poly([[0.46, 0.68 + bob], [0.54, 0.68 + bob], [0.54, 0.78 + bob], [0.5, 0.8 + bob], [0.46, 0.78 + bob]], Color(1.0, 0.5, 0.6))
				_poly([[0.3, 0.76 + bob], [0.7, 0.76 + bob], [0.68, 0.8 + bob], [0.32, 0.8 + bob]], Color(0.9, 0.2, 0.25))
			"toucan":  # Mango (Party Board): a black toucan with a huge orange beak and a party hat
				_circle(0.42, 0.6 + bob, 0.27, Color(0.12, 0.12, 0.16))
				_circle(0.42, 0.68 + bob, 0.15, Color(1.0, 0.95, 0.8))
				_poly([[0.52, 0.42 + bob], [0.98, 0.5 + bob], [0.9, 0.6 + bob], [0.55, 0.6 + bob]], Color(1.0, 0.6, 0.15))
				_poly([[0.52, 0.42 + bob], [0.98, 0.5 + bob], [0.75, 0.47 + bob]], Color(1.0, 0.85, 0.25))
				_circle(0.97, 0.53 + bob, 0.03, Color(0.15, 0.1, 0.1))
				_circle(0.46, 0.42 + bob, 0.08, Color(0.45, 0.8, 1.0))
				_eye(0.47, 0.42 + bob, 0.045)
				_poly([[0.26, 0.32 + bob], [0.46, 0.32 + bob], [0.34, 0.06 + bob]], color)
				_circle(0.34, 0.06 + bob, 0.04, white)
				var flap := sin(t * 6.0) * 0.05
				_poly([[0.22, 0.58 + bob], [0.08, 0.72 + bob - flap], [0.3, 0.78 + bob]], Color(0.2, 0.2, 0.26))
			"fish":  # a friendly fish swimming right, body = color
				var wag := sin(t * 6.0) * 0.05
				_poly([[0.22, 0.52 + bob], [0.04, 0.32 + bob + wag], [0.06, 0.72 + bob + wag]], color.darkened(0.25))
				var body := []
				for i in 20:
					var a := TAU * float(i) / 20.0
					body.append([0.52 + cos(a) * 0.34, 0.52 + bob + sin(a) * 0.22])
				_poly(body, color)
				_poly([[0.42, 0.34 + bob], [0.6, 0.2 + bob], [0.62, 0.34 + bob]], color.darkened(0.2))
				_circle(0.52, 0.6 + bob, 0.1, color.lightened(0.35))
				_eye(0.72, 0.46 + bob, 0.06)
				_circle(0.84, 0.58 + bob, 0.02, Color(0.15, 0.1, 0.1))
			"otter":  # Ollie: a round brown otter face with a cream muzzle and whiskers
				var fur := Color(0.62, 0.42, 0.25)
				_circle(0.24, 0.24 + bob, 0.09, fur.darkened(0.15))
				_circle(0.76, 0.24 + bob, 0.09, fur.darkened(0.15))
				_circle(0.5, 0.52 + bob, 0.36, fur)
				_circle(0.5, 0.66 + bob, 0.2, Color(0.95, 0.86, 0.7))
				_eye(0.37, 0.44 + bob, 0.07)
				_eye(0.63, 0.44 + bob, 0.07)
				_circle(0.5, 0.58 + bob, 0.06, Color(0.15, 0.1, 0.1))
				for sy in [-0.03, 0.03]:
					draw_line(_p(0.38, 0.66 + bob + sy), _p(0.12, 0.62 + bob + sy * 2.0), Color(0.3, 0.2, 0.15), 2.0)
					draw_line(_p(0.62, 0.66 + bob + sy), _p(0.88, 0.62 + bob + sy * 2.0), Color(0.3, 0.2, 0.15), 2.0)
				_poly([[0.44, 0.74 + bob], [0.56, 0.74 + bob], [0.5, 0.8 + bob]], Color(0.75, 0.35, 0.4))
			"coach":  # Coach Jelly (Obstacle Rush): an orange jelly bean in a blue cap, with a whistle
				var bean := Color(1.0, 0.55, 0.25)
				var pts := []
				for i in 24:
					var a := TAU * float(i) / 24.0
					pts.append([0.5 + cos(a) * 0.28, 0.58 + bob + sin(a) * (0.36 if sin(a) > 0.0 else 0.3)])
				_poly(pts, bean)
				_circle(0.5, 0.7 + bob, 0.15, bean.lightened(0.4))
				_eye(0.42, 0.46 + bob, 0.065)
				_eye(0.58, 0.46 + bob, 0.065)
				_circle(0.36, 0.56 + bob, 0.035, Color(1.0, 0.55, 0.6))
				_circle(0.64, 0.56 + bob, 0.035, Color(1.0, 0.55, 0.6))
				_poly([[0.24, 0.32 + bob], [0.76, 0.32 + bob], [0.7, 0.18 + bob], [0.3, 0.18 + bob]], Color(0.25, 0.45, 0.95))
				_poly([[0.66, 0.32 + bob], [0.92, 0.33 + bob], [0.72, 0.27 + bob]], Color(0.2, 0.35, 0.8))
				draw_line(_p(0.4, 0.3 + bob), _p(0.5, 0.62 + bob), Color(0.95, 0.3, 0.35), 2.0)
				var toot := 0.02 * sin(t * 12.0)
				_poly([[0.5, 0.6 + bob], [0.66 + toot, 0.6 + bob], [0.66 + toot, 0.66 + bob], [0.5, 0.66 + bob]], Color(0.8, 0.82, 0.88))
				_circle(0.5, 0.63 + bob, 0.04, Color(0.8, 0.82, 0.88))
			"balloon":
				var sway := sin(t * 2.0) * 0.03
				draw_line(_p(0.5 + sway, 0.62 + bob), _p(0.5, 0.95), Color(0.9, 0.9, 0.95), 2.0)
				var bl := []
				for i in 20:
					var a := TAU * float(i) / 20.0
					bl.append([0.5 + sway + cos(a) * 0.24, 0.36 + bob + sin(a) * 0.29])
				_poly(bl, color)
				_circle(0.42 + sway, 0.26 + bob, 0.06, color.lightened(0.5))
				_poly([[0.46 + sway, 0.67 + bob], [0.54 + sway, 0.67 + bob], [0.5 + sway, 0.62 + bob]], color.darkened(0.2))
			"seller":  # Poppy (Balloon Pop): a smiling face in a pink party hat, holding a bunch of balloons
				var cols: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.3), Color(0.35, 0.65, 1.0), Color(0.5, 0.9, 0.45)]
				for k in 4:
					var bx := 0.72 + (k % 2) * 0.14 + sin(t * 2.0 + k) * 0.015
					var by := 0.16 + (k / 2) * 0.15 + bob
					draw_line(_p(bx, by + 0.08), _p(0.74, 0.72 + bob), Color(0.9, 0.9, 0.95), 1.5)
					_circle(bx, by, 0.08, cols[k])
				_circle(0.42, 0.58 + bob, 0.27, Color(1.0, 0.85, 0.72))
				_poly([[0.22, 0.4 + bob], [0.62, 0.4 + bob], [0.42, 0.06 + bob]], color)
				_circle(0.42, 0.06 + bob, 0.05, Color(1.0, 0.9, 0.4))
				for k in 3:
					_circle(0.3 + k * 0.12, 0.38 + bob, 0.035, Color(1.0, 0.9, 0.4))
				_eye(0.34, 0.56 + bob, 0.055)
				_eye(0.5, 0.56 + bob, 0.055)
				_circle(0.28, 0.66 + bob, 0.04, Color(1.0, 0.55, 0.6))
				_circle(0.56, 0.66 + bob, 0.04, Color(1.0, 0.55, 0.6))
				draw_arc(_p(0.42, 0.66 + bob), 0.09 * size.x, 0.3, PI - 0.3, 10, Color(0.6, 0.2, 0.25), 2.5)
			"icecream":
				_poly([[0.34, 0.5 + bob], [0.66, 0.5 + bob], [0.5, 0.95 + bob]], Color(0.88, 0.62, 0.32))
				draw_line(_p(0.4, 0.6 + bob), _p(0.58, 0.75 + bob), Color(0.7, 0.45, 0.2), 2.0)
				draw_line(_p(0.6, 0.6 + bob), _p(0.44, 0.78 + bob), Color(0.7, 0.45, 0.2), 2.0)
				_circle(0.5, 0.45 + bob, 0.18, Color(1.0, 0.75, 0.85))
				_circle(0.5, 0.28 + bob, 0.15, Color(0.55, 0.35, 0.25))
				_circle(0.5, 0.12 + bob, 0.05, Color(0.9, 0.15, 0.2))
			"carousel":
				var spin := t * 1.5
				_poly([[0.5, 0.08 + bob], [0.9, 0.32 + bob], [0.1, 0.32 + bob]], Color(0.4, 0.7, 1.0))
				for k in 3:
					_poly([[0.5, 0.08 + bob], [0.23 + k * 0.27, 0.32 + bob], [0.36 + k * 0.27, 0.32 + bob]], white)
				_poly([[0.12, 0.84], [0.88, 0.84], [0.88, 0.92], [0.12, 0.92]], Color(0.95, 0.85, 0.6))
				for k in 3:
					var hx := 0.5 + sin(spin + k * TAU / 3.0) * 0.3
					var hy := 0.6 + sin(spin * 2.0 + k) * 0.04
					draw_line(_p(hx, 0.32 + bob), _p(hx, 0.84), Color(1.0, 0.85, 0.3), 2.0)
					_circle(hx, hy, 0.07, [Color(1.0, 0.35, 0.4), Color(0.5, 0.9, 0.45), Color(0.85, 0.5, 1.0)][k])
			"ferris":
				draw_line(_p(0.5, 0.48), _p(0.25, 0.95), Color(0.75, 0.75, 0.82), 3.0)
				draw_line(_p(0.5, 0.48), _p(0.75, 0.95), Color(0.75, 0.75, 0.82), 3.0)
				draw_arc(_p(0.5, 0.48), 0.36 * size.x, 0.0, TAU, 32, Color(1.0, 0.8, 0.25), 3.0)
				for k in 8:
					var a := k * TAU / 8.0 + t * 0.6
					var q := Vector2(0.5 + cos(a) * 0.36, 0.48 + sin(a) * 0.36)
					draw_line(_p(0.5, 0.48), _p(q.x, q.y), white, 1.5)
					_circle(q.x, q.y + 0.04, 0.05, [Color(1.0, 0.35, 0.4), Color(0.35, 0.65, 1.0), Color(0.5, 0.9, 0.45), Color(1.0, 0.55, 0.15)][k % 4])
			"tent":
				for k in 5:
					var x0 := 0.15 + k * 0.14
					_poly([[x0, 0.45], [x0 + 0.14, 0.45], [x0 + 0.14, 0.9], [x0, 0.9]], Color(0.95, 0.25, 0.3) if k % 2 == 0 else white)
				_poly([[0.08, 0.47 + bob * 0.5], [0.92, 0.47 + bob * 0.5], [0.5, 0.12 + bob * 0.5]], Color(0.95, 0.25, 0.3))
				_poly([[0.42, 0.9], [0.58, 0.9], [0.5, 0.62]], Color(0.2, 0.15, 0.2))
				draw_line(_p(0.5, 0.12 + bob * 0.5), _p(0.5, 0.0 + bob * 0.5), white, 2.0)
				_poly([[0.5, 0.0 + bob * 0.5], [0.66, 0.04 + bob * 0.5], [0.5, 0.08 + bob * 0.5]], Color(1.0, 0.85, 0.3))
			"beaver":  # Benny (Tiny Town Tycoon): a brown beaver in a yellow hard hat, big front teeth
				var fur := Color(0.62, 0.4, 0.24)
				_poly([[0.3, 0.72 + bob], [0.7, 0.72 + bob], [0.8, 0.98], [0.2, 0.98]], fur.darkened(0.1))
				_poly([[0.66, 0.9], [0.95, 0.8], [0.98, 0.95], [0.7, 0.99]], Color(0.4, 0.27, 0.18))
				_circle(0.3, 0.32 + bob, 0.07, fur.darkened(0.15))
				_circle(0.7, 0.32 + bob, 0.07, fur.darkened(0.15))
				_circle(0.5, 0.5 + bob, 0.25, fur)
				_circle(0.5, 0.62 + bob, 0.13, Color(0.85, 0.68, 0.5))
				_eye(0.41, 0.46 + bob, 0.055)
				_eye(0.59, 0.46 + bob, 0.055)
				_circle(0.5, 0.56 + bob, 0.045, Color(0.2, 0.12, 0.1))
				_poly([[0.45, 0.66 + bob], [0.55, 0.66 + bob], [0.55, 0.75 + bob], [0.45, 0.75 + bob]], white)
				draw_line(_p(0.5, 0.66 + bob), _p(0.5, 0.75 + bob), Color(0.7, 0.7, 0.7), 1.5)
				# the hard hat
				_poly([[0.26, 0.32 + bob], [0.74, 0.32 + bob], [0.68, 0.16 + bob], [0.5, 0.11 + bob], [0.32, 0.16 + bob]], Color(1.0, 0.82, 0.15))
				_poly([[0.2, 0.33 + bob], [0.8, 0.33 + bob], [0.8, 0.37 + bob], [0.2, 0.37 + bob]], Color(0.95, 0.7, 0.1))
				_poly([[0.47, 0.12 + bob], [0.53, 0.12 + bob], [0.53, 0.32 + bob], [0.47, 0.32 + bob]], Color(1.0, 0.9, 0.45))
			"island":
				_poly([[0.0, 0.7], [1.0, 0.7], [1.0, 1.0], [0.0, 1.0]], Color(0.3, 0.62, 0.9))
				for k in 4:
					var wx := k * 0.27 + fmod(t * 0.08, 0.27)
					draw_arc(_p(wx, 0.8), 0.06 * size.x, PI, TAU, 8, Color(0.8, 0.92, 1.0), 2.0)
				_poly([[0.12, 0.72], [0.3, 0.6], [0.7, 0.58], [0.9, 0.72]], Color(0.98, 0.88, 0.6))
				_poly([[0.22, 0.64], [0.38, 0.5], [0.62, 0.49], [0.8, 0.64]], Color(0.45, 0.78, 0.35))
				draw_line(_p(0.56, 0.52), _p(0.6, 0.24 + bob), Color(0.55, 0.38, 0.22), 0.04 * size.x)
				for a in [-2.6, -1.9, -1.2, -0.5]:
					var tip := Vector2(0.6 + cos(a) * 0.2, 0.24 + bob + sin(a) * 0.1 + 0.08)
					_poly([[0.6, 0.22 + bob], [tip.x, tip.y], [0.6 + cos(a) * 0.1, 0.27 + bob]], Color(0.3, 0.7, 0.3))
				_circle(0.82, 0.18, 0.08, Color(1.0, 0.85, 0.3))
			"boat":
				var rock := sin(t * 2.0) * 0.02
				_poly([[0.0, 0.76], [1.0, 0.76], [1.0, 1.0], [0.0, 1.0]], Color(0.3, 0.62, 0.9))
				_poly([[0.15, 0.62 + rock], [0.85, 0.62 - rock], [0.72, 0.8], [0.28, 0.8]], Color(0.85, 0.3, 0.25))
				_poly([[0.15, 0.62 + rock], [0.85, 0.62 - rock], [0.84, 0.66 - rock], [0.16, 0.66 + rock]], white)
				draw_line(_p(0.5, 0.62), _p(0.5, 0.14 + bob), Color(0.5, 0.35, 0.2), 0.03 * size.x)
				_poly([[0.53, 0.18 + bob], [0.53, 0.56], [0.82, 0.56]], color)
				_poly([[0.47, 0.24 + bob], [0.47, 0.56], [0.24, 0.56]], white)
				_poly([[0.5, 0.14 + bob], [0.64, 0.17 + bob], [0.5, 0.2 + bob]], Color(1.0, 0.85, 0.3))
				for k in 3:
					var wx2 := k * 0.4 + fmod(t * 0.1, 0.4)
					draw_arc(_p(wx2, 0.86), 0.07 * size.x, PI, TAU, 8, Color(0.8, 0.92, 1.0), 2.0)
			"captain":  # Captain Whiskers (Starship Crew): a ginger space cat in a glass bubble helmet
				var fur := Color(1.0, 0.62, 0.25)
				_poly([[0.25, 0.72 + bob], [0.75, 0.72 + bob], [0.82, 0.98], [0.18, 0.98]], Color(0.92, 0.94, 1.0))
				_circle(0.5, 0.84 + bob, 0.05, Color(1.0, 0.4, 0.4))
				_poly([[0.28, 0.4 + bob], [0.3, 0.16 + bob], [0.44, 0.3 + bob]], fur)
				_poly([[0.72, 0.4 + bob], [0.7, 0.16 + bob], [0.56, 0.3 + bob]], fur)
				_poly([[0.31, 0.36 + bob], [0.32, 0.22 + bob], [0.41, 0.31 + bob]], Color(1.0, 0.7, 0.75))
				_poly([[0.69, 0.36 + bob], [0.68, 0.22 + bob], [0.59, 0.31 + bob]], Color(1.0, 0.7, 0.75))
				_circle(0.5, 0.48 + bob, 0.23, fur)
				for sx in [-1.0, 1.0]:
					_poly([[0.5 + sx * 0.04, 0.27 + bob], [0.5 + sx * 0.1, 0.27 + bob], [0.5 + sx * 0.07, 0.36 + bob]], fur.darkened(0.25))
				_circle(0.5, 0.56 + bob, 0.1, Color(1.0, 0.93, 0.82))
				_eye(0.41, 0.45 + bob, 0.06)
				_eye(0.59, 0.45 + bob, 0.06)
				_poly([[0.47, 0.53 + bob], [0.53, 0.53 + bob], [0.5, 0.57 + bob]], Color(1.0, 0.5, 0.6))
				for sy in [-0.025, 0.025]:
					draw_line(_p(0.38, 0.56 + bob + sy), _p(0.16, 0.53 + bob + sy * 2.0), Color(0.35, 0.25, 0.2), 2.0)
					draw_line(_p(0.62, 0.56 + bob + sy), _p(0.84, 0.53 + bob + sy * 2.0), Color(0.35, 0.25, 0.2), 2.0)
				draw_arc(_p(0.5, 0.47 + bob), 0.36 * size.x, 0.0, TAU, 40, Color(0.75, 0.92, 1.0, 0.9), 3.0)
				_circle(0.36, 0.26 + bob, 0.05, Color(1.0, 1.0, 1.0, 0.55))
			"planet":
				_circle(0.5, 0.5 + bob, 0.3, color)
				_poly([[0.22, 0.42 + bob], [0.78, 0.4 + bob], [0.8, 0.47 + bob], [0.2, 0.49 + bob]], color.lightened(0.25))
				_circle(0.42, 0.6 + bob, 0.06, color.darkened(0.2))
				draw_arc(_p(0.5, 0.52 + bob), 0.44 * size.x, 0.35, PI - 0.35, 24, Color(1.0, 0.9, 0.6), 4.0)
				for st in [[0.12, 0.15], [0.86, 0.2], [0.88, 0.85], [0.1, 0.8]]:
					_circle(st[0], st[1], 0.02 + 0.01 * sin(t * 4.0 + st[0] * 9.0), white)
			"station":
				var spin := t * 0.6
				draw_arc(_p(0.5, 0.5), 0.36 * size.x, 0.0, TAU, 40, Color(1.0, 0.95, 0.88), 0.07 * size.x)
				for k in 6:
					var a := spin + k * TAU / 6.0
					draw_line(_p(0.5, 0.5), _p(0.5 + cos(a) * 0.36, 0.5 + sin(a) * 0.36), Color(1.0, 0.62, 0.78), 0.03 * size.x)
				_circle(0.5, 0.5, 0.12, Color(0.6, 0.85, 1.0))
				draw_arc(_p(0.5, 0.5), 0.12 * size.x, 0.0, TAU, 24, Color(1.0, 0.9, 0.4), 3.0)
				for k in 8:
					var a2 := spin + k * TAU / 8.0
					_circle(0.5 + cos(a2) * 0.36, 0.5 + sin(a2) * 0.36, 0.03, [Color(1, 0.5, 0.6), Color(0.5, 0.9, 1), Color(1, 0.9, 0.4)][k % 3])
			"engineer":  # Sprocket (Rocket Workshop): a teal robot with a screen face, orange hard hat and a spanner
				var teal := Color(0.3, 0.8, 0.85)
				_poly([[0.3, 0.78 + bob], [0.7, 0.78 + bob], [0.72, 0.98], [0.28, 0.98]], teal.darkened(0.15))
				_poly([[0.2, 0.32 + bob], [0.8, 0.32 + bob], [0.8, 0.78 + bob], [0.2, 0.78 + bob]], teal)
				_poly([[0.27, 0.4 + bob], [0.73, 0.4 + bob], [0.73, 0.71 + bob], [0.27, 0.71 + bob]], Color(0.08, 0.12, 0.18))
				var blink := 0.2 if fmod(t, 3.0) < 0.12 else 1.0
				for ex in [0.4, 0.6]:
					draw_set_transform(_p(ex, 0.52 + bob), 0.0, Vector2(1.0, blink))
					draw_circle(Vector2.ZERO, 0.055 * size.x, Color(0.5, 1.0, 0.95))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_arc(_p(0.5, 0.6 + bob), 0.08 * size.x, 0.4, PI - 0.4, 10, Color(0.5, 1.0, 0.95), 0.02 * size.x)
				_poly([[0.22, 0.33 + bob], [0.78, 0.33 + bob], [0.7, 0.16 + bob], [0.3, 0.16 + bob]], Color(1.0, 0.6, 0.15))
				_poly([[0.12, 0.35 + bob], [0.88, 0.35 + bob], [0.88, 0.3 + bob], [0.12, 0.3 + bob]], Color(0.95, 0.5, 0.1))
				draw_line(_p(0.62, 0.17 + bob), _p(0.68, 0.04 + bob), Color(0.6, 0.6, 0.65), 0.02 * size.x)
				_circle(0.68, 0.04 + bob, 0.035, Color(1.0, 0.3, 0.3) if fmod(t, 1.0) < 0.5 else Color(0.6, 0.15, 0.15))
				var sw := sin(t * 4.0) * 0.04
				draw_line(_p(0.86, 0.86 + sw), _p(0.92, 0.6 + sw), Color(0.75, 0.75, 0.8), 0.05 * size.x)
				draw_arc(_p(0.92, 0.57 + sw), 0.05 * size.x, PI * 0.9, PI * 2.1, 10, Color(0.75, 0.75, 0.8), 0.035 * size.x)
			"wren":  # Wren (Tower Stack): a round brown builder bird with a perky tail and a blue hard hat
				var brown := Color(0.62, 0.42, 0.25)
				_poly([[0.22, 0.55 + bob], [0.06, 0.2 + bob], [0.16, 0.18 + bob], [0.32, 0.5 + bob]], brown.darkened(0.2))
				_circle(0.5, 0.58 + bob, 0.3, brown)
				_circle(0.55, 0.66 + bob, 0.17, Color(0.95, 0.85, 0.7))
				_poly([[0.78, 0.48 + bob], [0.97, 0.53 + bob], [0.78, 0.58 + bob]], Color(1.0, 0.65, 0.2))
				_eye(0.64, 0.46 + bob, 0.065)
				var flap := sin(t * 9.0) * 0.07
				_poly([[0.36, 0.58 + bob], [0.14, 0.5 + bob - flap], [0.3, 0.76 + bob]], brown.darkened(0.3))
				_poly([[0.3, 0.32 + bob], [0.72, 0.32 + bob], [0.66, 0.15 + bob], [0.36, 0.15 + bob]], Color(0.25, 0.55, 0.95))
				_poly([[0.24, 0.35 + bob], [0.8, 0.35 + bob], [0.8, 0.3 + bob], [0.24, 0.3 + bob]], Color(0.2, 0.45, 0.85))
				_poly([[0.47, 0.32 + bob], [0.55, 0.32 + bob], [0.53, 0.15 + bob], [0.49, 0.15 + bob]], Color(1.0, 0.85, 0.3))
				draw_line(_p(0.4, 0.86 + bob), _p(0.38, 0.97), Color(1.0, 0.65, 0.2), 0.025 * size.x)
				draw_line(_p(0.56, 0.86 + bob), _p(0.58, 0.97), Color(1.0, 0.65, 0.2), 0.025 * size.x)
			"tower":  # a jelly-block tower in color under a red roof, with a little flag
				var wob := sin(t * 3.0) * 0.015
				for k in 3:
					var y0 := 0.94 - 0.2 * (k + 1)
					var x0 := 0.3 + wob * (k + 1)
					var col := color.lightened(0.15 * k) if k != 1 else color.darkened(0.15)
					_poly([[x0, y0], [x0 + 0.4, y0], [x0 + 0.4, y0 + 0.19], [x0, y0 + 0.19]], col)
					_circle(x0 + 0.14, y0 + 0.08, 0.025, Color(0.1, 0.1, 0.15))
					_circle(x0 + 0.26, y0 + 0.08, 0.025, Color(0.1, 0.1, 0.15))
				var tx := 0.3 + wob * 4.0
				_poly([[tx - 0.05, 0.34], [tx + 0.45, 0.34], [tx + 0.2, 0.12]], Color(0.9, 0.3, 0.3))
				draw_line(_p(tx + 0.2, 0.13), _p(tx + 0.2, 0.02), Color(0.4, 0.3, 0.25), 0.02 * size.x)
				_poly([[tx + 0.2, 0.02], [tx + 0.34, 0.05 + sin(t * 6.0) * 0.01], [tx + 0.2, 0.08]], Color(1.0, 0.85, 0.3))
			"rocket", "toyrocket":  # toyrocket: the nose and fins in color
				var trim := color if kind == "toyrocket" else Color(0.95, 0.3, 0.35)
				var flame := 0.04 * sin(t * 20.0)
				_poly([[0.42, 0.78 + bob], [0.58, 0.78 + bob], [0.5, 0.95 + bob + flame]], Color(1.0, 0.6, 0.2))
				_poly([[0.38, 0.3 + bob], [0.62, 0.3 + bob], [0.62, 0.78 + bob], [0.38, 0.78 + bob]], Color(0.95, 0.96, 1.0))
				_poly([[0.38, 0.3 + bob], [0.62, 0.3 + bob], [0.5, 0.08 + bob]], trim)
				_poly([[0.38, 0.6 + bob], [0.24, 0.8 + bob], [0.38, 0.78 + bob]], trim)
				_poly([[0.62, 0.6 + bob], [0.76, 0.8 + bob], [0.62, 0.78 + bob]], trim)
				_circle(0.5, 0.45 + bob, 0.07, Color(0.5, 0.85, 1.0))
			"lumi":  # Lumi (Crystal Saga): a little crystal fairy, glowing, with wings that flutter
				var flap := 0.06 * sin(t * 12.0)
				_poly([[0.42, 0.5 + bob], [0.12, 0.28 + bob - flap], [0.18, 0.62 + bob]], Color(0.8, 0.95, 1.0, 0.8))
				_poly([[0.58, 0.5 + bob], [0.88, 0.28 + bob - flap], [0.82, 0.62 + bob]], Color(0.8, 0.95, 1.0, 0.8))
				_circle(0.5, 0.52 + bob, 0.3, Color(0.55, 0.85, 1.0, 0.25))
				_poly([[0.5, 0.56 + bob], [0.64, 0.74 + bob], [0.5, 0.94 + bob], [0.36, 0.74 + bob]], Color(0.6, 0.85, 1.0))
				_circle(0.5, 0.44 + bob, 0.16, Color(0.95, 0.98, 1.0))
				_poly([[0.42, 0.3 + bob], [0.5, 0.12 + bob], [0.58, 0.3 + bob]], Color(0.55, 0.85, 1.0))
				_eye(0.44, 0.44 + bob, 0.045)
				_eye(0.56, 0.44 + bob, 0.045)
				draw_arc(_p(0.5, 0.5 + bob), 0.05 * size.x, 0.3, PI - 0.3, 8, Color(0.3, 0.4, 0.6), 0.02 * size.x)
				_circle(0.5, 0.12 + bob, 0.03 + 0.01 * sin(t * 6.0), Color(1.0, 1.0, 0.7))
			"shard":  # a crystal shard (Crystal Saga), sparkling
				_poly([[0.5, 0.08 + bob], [0.7, 0.4 + bob], [0.6, 0.9 + bob], [0.4, 0.9 + bob], [0.3, 0.4 + bob]], Color(0.55, 0.85, 1.0))
				_poly([[0.5, 0.08 + bob], [0.56, 0.42 + bob], [0.5, 0.9 + bob], [0.3, 0.4 + bob]], Color(0.8, 0.95, 1.0))
				var tw := 0.5 + 0.5 * sin(t * 5.0)
				_circle(0.72, 0.22, 0.03 * tw + 0.01, white)
				_circle(0.26, 0.66, 0.025 * (1.0 - tw) + 0.01, white)
			"bigfire":  # BIG FIRE: a fireball with a flame on top
				var fl := 0.03 * sin(t * 14.0)
				_poly([[0.3, 0.55 + bob], [0.42, 0.1 + bob + fl], [0.5, 0.3 + bob], [0.6, 0.05 + bob - fl], [0.72, 0.55 + bob]], Color(1.0, 0.75, 0.2))
				_circle(0.5, 0.62 + bob, 0.28, Color(1.0, 0.45, 0.12))
				_circle(0.5, 0.64 + bob, 0.16, Color(1.0, 0.85, 0.35))
			"snowflake":  # ICE
				for k in 3:
					var a := k * PI / 3.0 + t * 0.4
					var d := Vector2(cos(a), sin(a)) * 0.38
					draw_line(_p(0.5 - d.x, 0.5 - d.y), _p(0.5 + d.x, 0.5 + d.y), Color(0.75, 0.95, 1.0), 0.06 * size.x)
					for sgn in [-1.0, 1.0]:
						var tip: Vector2 = Vector2(0.5, 0.5) + d * 0.7 * float(sgn)
						var n: Vector2 = Vector2(-d.y, d.x) * 0.3
						draw_line(_p(tip.x, tip.y), _p(tip.x + n.x + d.x * 0.25 * sgn, tip.y + n.y + d.y * 0.25 * sgn), Color(0.75, 0.95, 1.0), 0.04 * size.x)
						draw_line(_p(tip.x, tip.y), _p(tip.x - n.x + d.x * 0.25 * sgn, tip.y - n.y + d.y * 0.25 * sgn), Color(0.75, 0.95, 1.0), 0.04 * size.x)
				_circle(0.5, 0.5, 0.07, white)
			"twin":  # TWIN SPARK: two sparks side by side
				for k in 2:
					var cx := 0.32 + k * 0.36
					var cy := 0.5 + (0.08 if k == 0 else -0.08) + bob
					var col := Color(0.85, 0.6, 1.0) if k == 0 else Color(0.6, 0.85, 1.0)
					var pts := []
					for i in 8:
						var a := i * TAU / 8.0 + t * 2.0
						var rr := 0.2 if i % 2 == 0 else 0.08
						pts.append([cx + cos(a) * rr, cy + sin(a) * rr])
					_poly(pts, col)
			"longsword", "spin", "mighty":  # sword tricks: a long sword, a sword in a whirl, a big golden sword
				var blade := Color(0.85, 0.92, 1.0) if kind != "mighty" else Color(1.0, 0.85, 0.3)
				var top := 0.06 if kind == "longsword" else 0.2
				var w := 0.05 if kind != "mighty" else 0.08
				if kind == "spin":
					draw_arc(_p(0.5, 0.55), 0.36 * size.x, t * 4.0, t * 4.0 + PI * 1.5, 20, Color(0.5, 1.0, 0.8), 0.05 * size.x)
				_poly([[0.5 - w, 0.68], [0.5 - w, top + 0.06], [0.5, top], [0.5 + w, top + 0.06], [0.5 + w, 0.68]], blade)
				_poly([[0.32, 0.68], [0.68, 0.68], [0.68, 0.74], [0.32, 0.74]], Color(1.0, 0.8, 0.3))
				_poly([[0.46, 0.74], [0.54, 0.74], [0.54, 0.9], [0.46, 0.9]], Color(0.4, 0.28, 0.55))
				_circle(0.5, 0.92, 0.04, Color(0.5, 0.85, 1.0))
				if kind == "mighty":
					for k in 3:
						var a := t * 2.0 + k * TAU / 3.0
						_circle(0.5 + cos(a) * 0.3, 0.4 + sin(a) * 0.2, 0.035, Color(1.0, 1.0, 0.7))
			"windmill":  # Willowbrook's windmill, sails turning
				_poly([[0.38, 0.4], [0.62, 0.4], [0.68, 0.95], [0.32, 0.95]], Color(0.96, 0.92, 0.82))
				_poly([[0.34, 0.42], [0.5, 0.24], [0.66, 0.42]], Color(0.8, 0.35, 0.28))
				_poly([[0.45, 0.78], [0.55, 0.78], [0.55, 0.95], [0.45, 0.95]], Color(0.5, 0.32, 0.2))
				for k in 4:
					var a := t * 1.5 + k * PI * 0.5
					var d := Vector2(cos(a), sin(a))
					var n := Vector2(-d.y, d.x) * 0.06
					var c0 := Vector2(0.5, 0.42)
					_poly([[c0.x + n.x * 0.3, c0.y + n.y * 0.3], [c0.x + d.x * 0.4 + n.x, c0.y + d.y * 0.4 + n.y], [c0.x + d.x * 0.4 - n.x, c0.y + d.y * 0.4 - n.y]], Color(0.95, 0.9, 0.8))
				_circle(0.5, 0.42, 0.04, Color(0.75, 0.3, 0.25))
			"fountain":  # a sparkly fountain
				_poly([[0.12, 0.72], [0.88, 0.72], [0.8, 0.92], [0.2, 0.92]], Color(0.82, 0.82, 0.88))
				_poly([[0.17, 0.72], [0.83, 0.72], [0.8, 0.77], [0.2, 0.77]], Color(0.4, 0.7, 1.0))
				_poly([[0.46, 0.4], [0.54, 0.4], [0.56, 0.72], [0.44, 0.72]], Color(0.85, 0.85, 0.9))
				for k in 5:
					var ph := fmod(t * 0.8 + k * 0.2, 1.0)
					var dx := (k - 2) * 0.09 * ph
					_circle(0.5 + dx * 2.0, 0.36 - sin(ph * PI) * 0.22 + ph * 0.3, 0.035, Color(0.6, 0.85, 1.0))
			"rainbow":
				var cols: Array = [Color(1.0, 0.35, 0.35), Color(1.0, 0.65, 0.25), Color(1.0, 0.95, 0.35), Color(0.4, 0.9, 0.4), Color(0.4, 0.65, 1.0), Color(0.7, 0.45, 1.0)]
				for k in 6:
					draw_arc(_p(0.5, 0.8), (0.42 - k * 0.05) * size.x, PI, TAU, 24, cols[k], 0.05 * size.x)
				for cl in [[0.14, 0.8, 0.09], [0.24, 0.84, 0.08], [0.76, 0.84, 0.08], [0.86, 0.8, 0.09]]:
					_circle(cl[0], cl[1], cl[2], white)
			"shepherd":  # Bo (Sheep Round-Up): a round face under a bonnet (color) with a bow, curls and a crook
				draw_arc(_p(0.84, 0.22 + bob), 0.08 * size.x, PI, TAU, 10, Color(0.55, 0.36, 0.2), 0.035 * size.x)
				draw_line(_p(0.92, 0.22 + bob), _p(0.92, 0.95), Color(0.55, 0.36, 0.2), 0.035 * size.x)
				for cx in [0.26, 0.74, 0.3, 0.7]:
					_circle(cx, 0.68 + bob if cx < 0.28 or cx > 0.72 else 0.76 + bob, 0.07, Color(0.95, 0.75, 0.35))
				_circle(0.5, 0.6 + bob, 0.25, Color(0.98, 0.8, 0.64))
				var bon := []
				for i in 13:
					var a := PI + PI * float(i) / 12.0
					bon.append([0.5 + cos(a) * 0.34, 0.52 + bob + sin(a) * 0.34])
				_poly(bon, color)
				_poly([[0.16, 0.52 + bob], [0.84, 0.52 + bob], [0.8, 0.46 + bob], [0.2, 0.46 + bob]], color.lightened(0.3))
				_poly([[0.22, 0.6 + bob], [0.12, 0.7 + bob], [0.18, 0.74 + bob]], color.lightened(0.15))
				_eye(0.41, 0.6 + bob, 0.05)
				_eye(0.59, 0.6 + bob, 0.05)
				draw_arc(_p(0.5, 0.68 + bob), 0.08 * size.x, 0.3, PI - 0.3, 10, Color(0.4, 0.15, 0.12), 0.022 * size.x)
				_circle(0.34, 0.7 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
				_circle(0.66, 0.7 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
			"sheep":  # a fluffy sheep (wool = color) with a dark face, hopping
				var hop := absf(sin(t * 4.0)) * 0.03
				for leg in [0.32, 0.44, 0.58, 0.7]:
					draw_line(_p(leg, 0.7 - hop), _p(leg, 0.9 - hop), Color(0.2, 0.18, 0.2), 0.05 * size.x)
				for b in [[0.36, 0.5, 0.15], [0.52, 0.45, 0.17], [0.66, 0.52, 0.15], [0.45, 0.62, 0.15], [0.62, 0.64, 0.14], [0.3, 0.62, 0.12]]:
					_circle(b[0], b[1] - hop, b[2], color)
				var face := Color(0.22, 0.2, 0.24) if color.get_luminance() > 0.4 else Color(0.08, 0.08, 0.1)
				_circle(0.22, 0.48 - hop, 0.12, face)
				_poly([[0.12, 0.4 - hop], [0.02, 0.44 - hop], [0.12, 0.47 - hop]], face)
				_eye(0.19, 0.45 - hop, 0.04)
				_circle(0.25, 0.37 - hop, 0.06, color)
			"castle":
				_poly([[0.2, 0.45], [0.8, 0.45], [0.8, 0.85], [0.2, 0.85]], Color(0.85, 0.88, 1.0))
				for x in [0.2, 0.44, 0.68]:
					_poly([[x, 0.35], [x + 0.12, 0.35], [x + 0.12, 0.45], [x, 0.45]], Color(0.85, 0.88, 1.0))
				_poly([[0.42, 0.62], [0.58, 0.62], [0.58, 0.85], [0.42, 0.85]], Color(0.5, 0.55, 0.85))
				for b in [[0.15, 0.85, 0.12], [0.35, 0.9, 0.14], [0.65, 0.9, 0.14], [0.85, 0.85, 0.12]]:
					_circle(b[0], b[1], b[2], white)


	## Farmer Fig's crops (Whack-a-Mole garden beds).
	func _veg(v: String, bob: float) -> void:
		var leaf := Color(0.35, 0.75, 0.3)
		match v:
			"lettuce":
				for b in [[0.32, 0.6, 0.2], [0.68, 0.6, 0.2], [0.5, 0.5, 0.24], [0.5, 0.68, 0.2]]:
					_circle(b[0], b[1] + bob, b[2], Color(0.45, 0.85, 0.35).darkened(0.1 * b[2]))
				_circle(0.5, 0.56 + bob, 0.12, Color(0.75, 0.95, 0.5))
			"carrot":
				_poly([[0.36, 0.3 + bob], [0.64, 0.3 + bob], [0.5, 0.95 + bob]], Color(1.0, 0.55, 0.15))
				for a in [-0.12, 0.0, 0.12]:
					_poly([[0.47, 0.3 + bob], [0.53, 0.3 + bob], [0.5 + a, 0.06 + bob]], leaf)
			"pumpkin":
				for b in [[0.3, 0.2], [0.7, 0.2], [0.5, 0.25]]:
					_circle(b[0], 0.6 + bob, b[1], Color(1.0, 0.5, 0.1).lightened(0.1 if b[0] == 0.5 else 0.0))
				_poly([[0.46, 0.38 + bob], [0.54, 0.38 + bob], [0.56, 0.24 + bob], [0.5, 0.24 + bob]], Color(0.4, 0.55, 0.2))
			"sunflower":
				draw_line(_p(0.5, 0.55), _p(0.5, 0.98), leaf, 0.05 * size.x)
				for i in 10:
					var a := i * TAU / 10.0 + t * 0.4
					_circle(0.5 + cos(a) * 0.2, 0.4 + sin(a) * 0.2 + bob, 0.09, Color(1.0, 0.85, 0.2))
				_circle(0.5, 0.4 + bob, 0.14, Color(0.5, 0.3, 0.12))
			"strawberry":
				_poly([[0.22, 0.4 + bob], [0.78, 0.4 + bob], [0.72, 0.6 + bob], [0.5, 0.92 + bob], [0.28, 0.6 + bob]], Color(0.95, 0.2, 0.3))
				for p in [[0.38, 0.5], [0.6, 0.5], [0.5, 0.62], [0.42, 0.74], [0.58, 0.72]]:
					_circle(p[0], p[1] + bob, 0.018, Color(1.0, 0.9, 0.5))
				_poly([[0.3, 0.4 + bob], [0.5, 0.28 + bob], [0.7, 0.4 + bob], [0.5, 0.46 + bob]], leaf)
			"corn":
				_poly([[0.38, 0.2 + bob], [0.62, 0.2 + bob], [0.64, 0.75 + bob], [0.36, 0.75 + bob]], Color(1.0, 0.88, 0.3))
				for y in 5:
					for x in 2:
						_circle(0.45 + x * 0.1, 0.27 + y * 0.1 + bob, 0.035, Color(1.0, 0.95, 0.5))
				_poly([[0.36, 0.95 + bob], [0.28, 0.4 + bob], [0.46, 0.75 + bob]], leaf)
				_poly([[0.64, 0.95 + bob], [0.72, 0.4 + bob], [0.54, 0.75 + bob]], leaf)
			"melon":
				_circle(0.5, 0.58 + bob, 0.34, Color(0.3, 0.65, 0.3))
				for x in [-0.2, 0.0, 0.2]:
					draw_line(_p(0.5 + x * 0.6, 0.26 + bob), _p(0.5 + x, 0.58 + bob), Color(0.55, 0.85, 0.45), 0.03 * size.x)
					draw_line(_p(0.5 + x, 0.58 + bob), _p(0.5 + x * 0.6, 0.9 + bob), Color(0.55, 0.85, 0.45), 0.03 * size.x)
			"apple":
				_circle(0.39, 0.6 + bob, 0.24, Color(0.9, 0.15, 0.2))
				_circle(0.61, 0.6 + bob, 0.24, Color(0.9, 0.15, 0.2))
				_circle(0.38, 0.52 + bob, 0.07, Color(1.0, 0.5, 0.5, 0.7))
				draw_line(_p(0.5, 0.4 + bob), _p(0.54, 0.22 + bob), Color(0.45, 0.28, 0.15), 0.03 * size.x)
				_poly([[0.54, 0.28 + bob], [0.72, 0.2 + bob], [0.6, 0.34 + bob]], leaf)


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
