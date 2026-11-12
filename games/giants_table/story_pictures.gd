extends RefCounted
## Giant's Table's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Gifts also use "pie" from Fruit Catch, "scarf" from Snowball Blitz, "bunting" from Cannon Cove and "daisy"
## from Bee Garden; Sparky's crown is the shared "crown" icon.)

const NAMES: Array[String] = ["sparky", "ladder", "goblin", "cake", "teddy", "lantern", "gooball", "barrel", "candle", "cupcake",
	"flowerpot"]

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

		"gooball":  # a wobbly pink goo ball flying with a splat trail (the goblins' catapult trick)
			var c := Color(1.0, 0.3, 0.85) if color == Color.WHITE else color
			var wob := sin(t * 8.0) * 0.03
			for k in 3:
				pic._circle(0.2 + k * 0.1, 0.8 - k * 0.1, 0.03 + k * 0.012, Color(c.r, c.g, c.b, 0.5))
			pic._circle(0.58, 0.42 + bob, 0.24 + wob, c)
			pic._circle(0.5, 0.34 + bob, 0.07, c.lightened(0.45))
			pic._circle(0.78, 0.58 + bob, 0.06, c)
			pic._circle(0.38, 0.6 + bob, 0.05, c)
			pic._eye(0.52, 0.42 + bob, 0.05)
			pic._eye(0.66, 0.42 + bob, 0.05)
		"barrel":  # a round wooden barrel rolling along, with iron hoops and a dust puff
			var wood := Color(0.75, 0.48, 0.24) if color == Color.WHITE else Color(0.75, 0.48, 0.24).lerp(color, 0.25)
			var hoop := Color(0.35, 0.35, 0.4)
			pic._circle(0.18, 0.84, 0.06, Color(0.85, 0.8, 0.7, 0.6))
			pic._circle(0.1, 0.8, 0.04, Color(0.85, 0.8, 0.7, 0.45))
			pic._circle(0.55, 0.55 + bob, 0.32, wood)
			pic._circle(0.55, 0.55 + bob, 0.26, wood.lightened(0.12))
			var a := t * 3.0
			for k in 4:
				var ang := a + k * PI * 0.5
				pic._poly([[0.55, 0.55 + bob], [0.55 + cos(ang) * 0.27, 0.55 + bob + sin(ang) * 0.27],
					[0.55 + cos(ang + 0.12) * 0.27, 0.55 + bob + sin(ang + 0.12) * 0.27]], wood.darkened(0.25))
			pic._circle(0.55, 0.55 + bob, 0.06, hoop)
			pic._poly([[0.2, 0.9], [0.95, 0.9], [0.95, 0.94], [0.2, 0.94]], Color(0.5, 0.35, 0.2))
		"candle":  # a fat red candle with a happy little flame
			var c := Color(0.95, 0.3, 0.3) if color == Color.WHITE else color.lerp(Color(0.95, 0.3, 0.3), 0.5)
			pic._poly([[0.2, 0.86], [0.8, 0.86], [0.74, 0.94], [0.26, 0.94]], Color(0.85, 0.7, 0.3))  # the dish
			pic._poly([[0.36, 0.4 + bob], [0.64, 0.4 + bob], [0.64, 0.88], [0.36, 0.88]], c)
			pic._poly([[0.36, 0.4 + bob], [0.64, 0.4 + bob], [0.64, 0.46 + bob], [0.36, 0.46 + bob]], c.lightened(0.3))
			pic._poly([[0.42, 0.46 + bob], [0.46, 0.46 + bob], [0.46, 0.6 + bob], [0.42, 0.58 + bob]], c.lightened(0.4))  # a drip
			pic._poly([[0.49, 0.32 + bob], [0.51, 0.32 + bob], [0.51, 0.4 + bob], [0.49, 0.4 + bob]], Color(0.2, 0.15, 0.1))
			_flame(pic, 0.5, 0.33 + bob, 0.14, 0.2 + sin(t * 9.0) * 0.02, sin(t * 5.0) * 0.02, FLAME_MID)
			_flame(pic, 0.5, 0.33 + bob, 0.07, 0.1, 0.0, FLAME_IN)
		"cupcake":  # a cupcake in a stripy paper case, swirly icing and a cherry on top
			var icing := Color(1.0, 0.7, 0.85) if color == Color.WHITE else color.lightened(0.35)
			pic._poly([[0.26, 0.56 + bob], [0.74, 0.56 + bob], [0.66, 0.9 + bob], [0.34, 0.9 + bob]], Color(0.45, 0.7, 1.0))
			for k in 4:
				var x := 0.32 + k * 0.12
				pic._poly([[x, 0.58 + bob], [x + 0.04, 0.58 + bob], [x + 0.03, 0.88 + bob], [x - 0.0, 0.88 + bob]], Color(0.3, 0.55, 0.95))
			pic._circle(0.5, 0.52 + bob, 0.25, icing)
			pic._circle(0.5, 0.4 + bob, 0.18, icing.lightened(0.15))
			pic._circle(0.5, 0.3 + bob, 0.11, icing.lightened(0.25))
			pic._circle(0.5, 0.17 + bob, 0.07, Color(0.9, 0.12, 0.2))
			pic._poly([[0.5, 0.11 + bob], [0.56, 0.02 + bob], [0.58, 0.04 + bob], [0.52, 0.12 + bob]], Color(0.3, 0.55, 0.2))
			for k in 5:
				pic._circle(0.34 + k * 0.08, 0.5 + bob + 0.04 * (k % 2), 0.018, [Color(1, 0.9, 0.2), Color(0.3, 0.8, 1), Color(0.4, 0.9, 0.4)][k % 3])
		"flowerpot":  # a clay flowerpot with three bright flowers
			var pot := Color(0.8, 0.42, 0.25)
			for k in 3:
				var x := 0.3 + k * 0.2
				var y := 0.28 + 0.06 * (k % 2) + bob + sin(t * 2.0 + k) * 0.015
				pic._poly([[x - 0.015, y], [x + 0.015, y], [x + 0.015, 0.62], [x - 0.015, 0.62]], Color(0.3, 0.6, 0.25))
				var fc: Color = [Color(1.0, 0.4, 0.6), Color(1.0, 0.85, 0.2), Color(0.55, 0.6, 1.0)][k] if color == Color.WHITE else color.lerp([Color(1.0, 0.4, 0.6), Color(1.0, 0.85, 0.2), Color(0.55, 0.6, 1.0)][k], 0.6)
				for j in 5:
					var a := j * TAU / 5.0 + t * 0.5
					pic._circle(x + cos(a) * 0.06, y + sin(a) * 0.06, 0.045, fc)
				pic._circle(x, y, 0.035, Color(1.0, 0.95, 0.6))
			pic._poly([[0.42, 0.5], [0.3, 0.44], [0.44, 0.56]], Color(0.35, 0.7, 0.3))  # a leaf
			pic._poly([[0.2, 0.6], [0.8, 0.6], [0.8, 0.68], [0.2, 0.68]], pot.lightened(0.15))
			pic._poly([[0.25, 0.68], [0.75, 0.68], [0.68, 0.95], [0.32, 0.95]], pot)

## A flame shape standing on (x, base): w wide, h tall, its tip swaying by `sway`.
static func _flame(pic, x: float, base: float, w: float, h: float, sway: float, c: Color) -> void:
	pic._poly([[x - w * 0.3, base], [x - w * 0.5, base - h * 0.3], [x - w * 0.36, base - h * 0.62], [x + sway, base - h],
		[x + w * 0.36, base - h * 0.62], [x + w * 0.5, base - h * 0.3], [x + w * 0.3, base]], c)
