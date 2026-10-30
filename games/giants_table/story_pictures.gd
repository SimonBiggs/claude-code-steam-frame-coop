extends RefCounted
## Giant's Table's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Gifts also use "pie" from Fruit Catch, "scarf" from Snowball Blitz, "bunting" from Cannon Cove and "daisy"
## from Bee Garden; Sparky's crown is the shared "crown" icon.)

const NAMES: Array[String] = ["sparky", "ladder", "goblin", "cake", "teddy", "lantern"]

const FLAME := Color(1.0, 0.55, 0.12)
const FLAME_MID := Color(1.0, 0.78, 0.25)
const FLAME_IN := Color(1.0, 0.95, 0.6)
const WOOD := Color(0.55, 0.34, 0.16)
const GOBLIN := Color(0.45, 0.78, 0.3)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"sparky":  # the campfire's little flame: a happy face in the flames, on two crossed logs
			var c := FLAME if color == Color.WHITE else color.lerp(FLAME, 0.5)
			pic._poly([[0.18, 0.86], [0.24, 0.78], [0.82, 0.92], [0.76, 1.0]], WOOD)
			pic._poly([[0.82, 0.86], [0.76, 0.78], [0.18, 0.92], [0.24, 1.0]], WOOD.darkened(0.15))
			var sway := sin(t * 5.0) * 0.03
			_flame(pic, 0.5, 0.84, 0.36, 0.72 + sin(t * 7.0) * 0.03, sway, c)
			_flame(pic, 0.5, 0.84, 0.26, 0.52 + sin(t * 9.0 + 1.0) * 0.03, -sway, FLAME_MID)
			_flame(pic, 0.5, 0.84, 0.15, 0.3, sway * 0.5, FLAME_IN)
			pic._eye(0.41, 0.56 + bob, 0.055)
			pic._eye(0.59, 0.56 + bob, 0.055)
			pic._poly([[0.42, 0.66 + bob], [0.58, 0.66 + bob], [0.55, 0.72 + bob], [0.45, 0.72 + bob]], Color(0.55, 0.12, 0.08))
			pic._circle(0.35, 0.65 + bob, 0.035, Color(1.0, 0.45, 0.4, 0.8))
			pic._circle(0.65, 0.65 + bob, 0.035, Color(1.0, 0.45, 0.4, 0.8))
		"ladder":  # a wooden ladder up the table edge, a little goblin peeking over the top
			var c := WOOD if color == Color.WHITE else WOOD.lerp(color, 0.25)
			pic._poly([[0.0, 0.3], [1.0, 0.3], [1.0, 0.38], [0.0, 0.38]], Color(0.7, 0.48, 0.25))  # the table top
			pic._poly([[0.3, 0.2], [0.36, 0.2], [0.36, 1.0], [0.3, 1.0]], c)
			pic._poly([[0.64, 0.2], [0.7, 0.2], [0.7, 1.0], [0.64, 1.0]], c)
			for k in 5:
				var y := 0.32 + k * 0.15
				pic._poly([[0.33, y], [0.67, y], [0.67, y + 0.04], [0.33, y + 0.04]], c.lightened(0.15))
			var peek := 0.24 - absf(sin(t * 2.0)) * 0.08
			pic._circle(0.5, peek + 0.02, 0.12, GOBLIN)
			pic._poly([[0.38, peek], [0.24, peek - 0.08], [0.4, peek + 0.06]], GOBLIN)  # ears
			pic._poly([[0.62, peek], [0.76, peek - 0.08], [0.6, peek + 0.06]], GOBLIN)
			pic._eye(0.45, peek, 0.035)
			pic._eye(0.55, peek, 0.035)
		"goblin":  # a cheeky little green goblin with big ears and a pointy hat
			var c := GOBLIN if color == Color.WHITE else color.lerp(GOBLIN, 0.5)
			var y := 0.58 + bob
			pic._poly([[0.32, y - 0.04], [0.06, y - 0.2], [0.3, y + 0.1]], c.darkened(0.1))
			pic._poly([[0.68, y - 0.04], [0.94, y - 0.2], [0.7, y + 0.1]], c.darkened(0.1))
			pic._circle(0.5, y, 0.25, c)
			pic._poly([[0.3, y - 0.17], [0.7, y - 0.17], [0.5, y - 0.5 + sin(t * 3.0) * 0.03]], Color(0.8, 0.25, 0.25))
			pic._eye(0.41, y - 0.03, 0.07)
			pic._eye(0.59, y - 0.03, 0.07)
			pic._poly([[0.38, y + 0.1], [0.62, y + 0.1], [0.56, y + 0.16], [0.44, y + 0.16]], Color(0.2, 0.3, 0.1))
			pic._poly([[0.44, y + 0.1], [0.48, y + 0.1], [0.46, y + 0.14]], Color.WHITE)  # a tooth
		"cake":  # a two-layer birthday cake with a candle
			var icing := Color(1.0, 0.75, 0.85) if color == Color.WHITE else color.lightened(0.3)
			pic._poly([[0.14, 0.62 + bob], [0.86, 0.62 + bob], [0.86, 0.88 + bob], [0.14, 0.88 + bob]], Color(0.75, 0.5, 0.3))
			pic._poly([[0.14, 0.6 + bob], [0.86, 0.6 + bob], [0.86, 0.68 + bob], [0.14, 0.68 + bob]], icing)
			pic._poly([[0.26, 0.42 + bob], [0.74, 0.42 + bob], [0.74, 0.62 + bob], [0.26, 0.62 + bob]], Color(0.8, 0.55, 0.32))
			pic._poly([[0.26, 0.4 + bob], [0.74, 0.4 + bob], [0.74, 0.47 + bob], [0.26, 0.47 + bob]], icing)
			for k in 4:
				pic._circle(0.22 + k * 0.19, 0.76 + bob, 0.025, [Color(1, 0.3, 0.3), Color(0.3, 0.6, 1), Color(1, 0.85, 0.2), Color(0.4, 0.85, 0.4)][k])
			pic._poly([[0.48, 0.24 + bob], [0.52, 0.24 + bob], [0.52, 0.4 + bob], [0.48, 0.4 + bob]], Color(0.4, 0.7, 1.0))
			var fl := 0.9 + sin(t * 12.0) * 0.1
			pic._poly([[0.5, 0.24 + bob - 0.1 * fl], [0.54, 0.21 + bob], [0.5, 0.25 + bob], [0.46, 0.21 + bob]], FLAME_MID)
		"teddy":  # a soft brown teddy bear waving
			var c := Color(0.7, 0.48, 0.28) if color == Color.WHITE else color.lerp(Color(0.7, 0.48, 0.28), 0.6)
			var wave := sin(t * 4.0) * 0.06
			pic._circle(0.5, 0.7 + bob, 0.2, c)  # tummy
			pic._circle(0.5, 0.72 + bob, 0.11, c.lightened(0.3))
			pic._circle(0.3, 0.88 + bob, 0.08, c)  # feet
			pic._circle(0.7, 0.88 + bob, 0.08, c)
			pic._circle(0.3, 0.62 + bob, 0.07, c)  # arm
			pic._circle(0.74, 0.5 + bob - wave, 0.07, c)  # waving arm
			pic._circle(0.33, 0.2 + bob, 0.08, c)  # ears
			pic._circle(0.67, 0.2 + bob, 0.08, c)
			pic._circle(0.5, 0.36 + bob, 0.2, c)  # head
			pic._circle(0.5, 0.42 + bob, 0.08, c.lightened(0.3))
			pic._circle(0.5, 0.4 + bob, 0.03, Color(0.15, 0.1, 0.08))
			pic._eye(0.42, 0.31 + bob, 0.035)
			pic._eye(0.58, 0.31 + bob, 0.035)
			pic._poly([[0.4, 0.52 + bob], [0.6, 0.52 + bob], [0.5, 0.58 + bob]], Color(0.9, 0.3, 0.35))  # bow
		"lantern":  # a glowing paper lantern on a post
			var glow := Color(1.0, 0.8, 0.35) if color == Color.WHITE else color
			var pulse := 0.85 + sin(t * 3.0) * 0.15
			pic._circle(0.5, 0.42 + bob, 0.3 * pulse, Color(glow.r, glow.g, glow.b, 0.25))
			pic._poly([[0.48, 0.0], [0.52, 0.0], [0.52, 0.2 + bob], [0.48, 0.2 + bob]], Color(0.3, 0.2, 0.12))
			pic._poly([[0.36, 0.2 + bob], [0.64, 0.2 + bob], [0.6, 0.25 + bob], [0.4, 0.25 + bob]], Color(0.3, 0.2, 0.12))
			pic._poly([[0.38, 0.25 + bob], [0.62, 0.25 + bob], [0.68, 0.42 + bob], [0.62, 0.6 + bob], [0.38, 0.6 + bob], [0.32, 0.42 + bob]], glow)
			pic._poly([[0.44, 0.3 + bob], [0.56, 0.3 + bob], [0.6, 0.42 + bob], [0.56, 0.55 + bob], [0.44, 0.55 + bob], [0.4, 0.42 + bob]], glow.lightened(0.5))
			pic._poly([[0.4, 0.6 + bob], [0.6, 0.6 + bob], [0.56, 0.65 + bob], [0.44, 0.65 + bob]], Color(0.3, 0.2, 0.12))


## A flame shape standing on (x, base): w wide, h tall, its tip swaying by `sway`.
static func _flame(pic, x: float, base: float, w: float, h: float, sway: float, c: Color) -> void:
	pic._poly([[x - w * 0.3, base], [x - w * 0.5, base - h * 0.3], [x - w * 0.36, base - h * 0.62], [x + sway, base - h],
		[x + w * 0.36, base - h * 0.62], [x + w * 0.5, base - h * 0.3], [x + w * 0.3, base]], c)
