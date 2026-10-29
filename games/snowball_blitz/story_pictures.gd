extends RefCounted
## Snowball Blitz's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a
## picture here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Snowmen use the shared "snowman", snow bunnies Whack-a-Mole's "bunny", balloon snowmen Coach's "balloon",
## Bobo's fish Fishing Lake's "fish": any picture works in every game.)

const NAMES: Array[String] = ["polarbear", "igloo", "sledman", "snowking", "yeti", "cocoamug", "scarf", "mittens"]

const SNOW := Color(0.96, 0.98, 1.0)
const SHADE := Color(0.78, 0.86, 0.96)
const COAL := Color(0.12, 0.12, 0.16)
const CARROT := Color(1.0, 0.5, 0.1)
const GOLD := Color(1.0, 0.82, 0.2)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"polarbear":  # Bobo: a round polar bear cub in a woolly hat (in `color`), waving
			var wave := sin(t * 4.0) * 0.05
			pic._circle(0.5, 0.7 + bob, 0.22, SNOW)  # body
			pic._circle(0.5, 0.74 + bob, 0.12, Color(1.0, 0.97, 0.9))
			pic._circle(0.28, 0.5 + wave + bob, 0.07, SNOW)  # waving paw
			pic._circle(0.74, 0.76 + bob, 0.07, SHADE)
			pic._circle(0.33, 0.24 + bob, 0.07, SNOW)  # ears
			pic._circle(0.67, 0.24 + bob, 0.07, SNOW)
			pic._circle(0.33, 0.24 + bob, 0.035, Color(0.95, 0.7, 0.75))
			pic._circle(0.67, 0.24 + bob, 0.035, Color(0.95, 0.7, 0.75))
			pic._circle(0.5, 0.4 + bob, 0.19, SNOW)  # head
			pic._circle(0.5, 0.47 + bob, 0.08, Color(1.0, 0.95, 0.88))  # muzzle
			pic._circle(0.5, 0.44 + bob, 0.03, COAL)  # nose
			pic._eye(0.43, 0.36 + bob, 0.035)
			pic._eye(0.57, 0.36 + bob, 0.035)
			pic._poly([[0.46, 0.5 + bob], [0.54, 0.5 + bob], [0.5, 0.53 + bob]], Color(0.9, 0.35, 0.4))
			pic._poly([[0.32, 0.27 + bob], [0.68, 0.27 + bob], [0.62, 0.15 + bob], [0.5, 0.11 + bob], [0.38, 0.15 + bob]], color)  # hat
			pic._circle(0.5, 0.09 + bob, 0.04, Color.WHITE)
			pic._poly([[0.3, 0.57 + bob], [0.7, 0.57 + bob], [0.68, 0.62 + bob], [0.32, 0.62 + bob]], color.darkened(0.15))  # scarf
		"igloo":  # a snow-brick igloo with a warm glowing door (flag in `color`)
			pic._poly([[0.06, 0.86], [0.94, 0.86], [0.9, 0.9], [0.1, 0.9]], SHADE)
			_dome(pic, 0.5, 0.84 + bob, 0.36, SNOW)
			for i in 3:  # brick lines
				var y := 0.76 - i * 0.1 + bob
				var w := sqrt(maxf(0.0, 0.36 * 0.36 - pow(0.84 + bob - y, 2.0)))
				pic._poly([[0.5 - w, y], [0.5 + w, y], [0.5 + w, y + 0.012], [0.5 - w, y + 0.012]], SHADE)
			_dome(pic, 0.5, 0.86 + bob, 0.12, Color(1.0, 0.75, 0.35).lerp(Color(1.0, 0.9, 0.5), 0.5 + 0.5 * sin(t * 3.0)))
			pic._poly([[0.5, 0.48 + bob], [0.52, 0.48 + bob], [0.52, 0.3 + bob], [0.5, 0.3 + bob]], COAL)
			pic._poly([[0.52, 0.3 + bob], [0.66, 0.34 + bob + sin(t * 5.0) * 0.015], [0.52, 0.38 + bob]], color)
		"sledman":  # a snowman whizzing on a red sled
			var x := sin(t * 3.0) * 0.03
			pic._poly([[0.14 + x, 0.78 + bob], [0.82 + x, 0.78 + bob], [0.9 + x, 0.7 + bob], [0.86 + x, 0.84 + bob], [0.18 + x, 0.84 + bob]], Color(0.9, 0.2, 0.2))
			pic._poly([[0.12 + x, 0.88 + bob], [0.88 + x, 0.88 + bob], [0.94 + x, 0.82 + bob], [0.92 + x, 0.9 + bob], [0.12 + x, 0.9 + bob]], Color(0.5, 0.3, 0.15))
			_snowman(pic, 0.48 + x, 0.74 + bob, 0.9)
			for i in 3:  # speed lines
				pic._poly([[0.02, 0.5 + i * 0.1 + bob], [0.12, 0.5 + i * 0.1 + bob], [0.12, 0.51 + i * 0.1 + bob], [0.02, 0.51 + i * 0.1 + bob]], Color(1, 1, 1, 0.7))
		"snowking":  # the Snow King: a big snowman with a gold crown and a blue cape
			pic._poly([[0.22, 0.4 + bob], [0.78, 0.4 + bob], [0.86, 0.9 + bob], [0.14, 0.9 + bob]], Color(0.25, 0.4, 0.85))
			_snowman(pic, 0.5, 0.92 + bob, 1.2)
			pic._poly([[0.36, 0.2 + bob], [0.64, 0.2 + bob], [0.66, 0.06 + bob], [0.58, 0.13 + bob], [0.5, 0.03 + bob], [0.42, 0.13 + bob], [0.34, 0.06 + bob]], GOLD)
			pic._circle(0.5, 0.15 + bob, 0.025, Color(0.9, 0.2, 0.3))
		"yeti":  # a big friendly-ish furry yeti, arms up
			var fur := Color(0.9, 0.93, 1.0)
			var arm := sin(t * 3.0) * 0.04
			pic._circle(0.18, 0.3 + arm + bob, 0.09, fur)
			pic._circle(0.82, 0.3 - arm + bob, 0.09, fur)
			pic._poly([[0.2, 0.36 + bob], [0.32, 0.5 + bob], [0.26, 0.56 + bob], [0.12, 0.38 + bob]], fur)
			pic._poly([[0.8, 0.36 + bob], [0.68, 0.5 + bob], [0.74, 0.56 + bob], [0.88, 0.38 + bob]], fur)
			pic._circle(0.5, 0.66 + bob, 0.26, fur)
			pic._circle(0.5, 0.36 + bob, 0.18, fur)
			pic._circle(0.5, 0.4 + bob, 0.12, Color(0.55, 0.7, 0.9))  # face
			pic._eye(0.45, 0.37 + bob, 0.035)
			pic._eye(0.55, 0.37 + bob, 0.035)
			pic._poly([[0.42, 0.45 + bob], [0.58, 0.45 + bob], [0.55, 0.49 + bob], [0.45, 0.49 + bob]], COAL)
			pic._poly([[0.46, 0.45 + bob], [0.48, 0.45 + bob], [0.47, 0.47 + bob]], Color.WHITE)
			pic._poly([[0.52, 0.45 + bob], [0.54, 0.45 + bob], [0.53, 0.47 + bob]], Color.WHITE)
			pic._circle(0.38, 0.9 + bob, 0.07, Color(0.55, 0.7, 0.9))
			pic._circle(0.62, 0.9 + bob, 0.07, Color(0.55, 0.7, 0.9))
		"cocoamug":  # Bobo's mug of hot cocoa with marshmallows and steam
			pic._poly([[0.24, 0.4 + bob], [0.68, 0.4 + bob], [0.64, 0.86 + bob], [0.28, 0.86 + bob]], Color(0.9, 0.25, 0.25))
			pic._circle(0.74, 0.6 + bob, 0.1, Color(0.9, 0.25, 0.25))
			pic._circle(0.74, 0.6 + bob, 0.045, Color(0.82, 0.88, 0.98))
			pic._poly([[0.26, 0.4 + bob], [0.66, 0.4 + bob], [0.655, 0.46 + bob], [0.265, 0.46 + bob]], Color(0.45, 0.25, 0.12))
			pic._circle(0.38, 0.4 + bob, 0.04, Color.WHITE)
			pic._circle(0.5, 0.39 + bob, 0.045, Color(1.0, 0.85, 0.9))
			for i in 3:
				var y := 0.32 - fmod(t * 0.4 + i * 0.33, 1.0) * 0.26
				pic._circle(0.34 + i * 0.12, y + bob, 0.03, Color(1.0, 1.0, 1.0, 0.55))
		"scarf":  # a long stripy scarf (stripes in `color`)
			for i in 7:
				var x := 0.14 + i * 0.1
				var y := 0.42 + sin(i * 0.9 + t * 2.0) * 0.04 + bob
				pic._poly([[x, y], [x + 0.1, y + 0.01], [x + 0.1, y + 0.13], [x, y + 0.12]], color if i % 2 == 0 else Color.WHITE)
			pic._poly([[0.74, 0.55 + bob], [0.84, 0.55 + bob], [0.82, 0.86 + bob], [0.72, 0.86 + bob]], color)
			for i in 4:
				pic._poly([[0.73 + i * 0.025, 0.86 + bob], [0.745 + i * 0.025, 0.86 + bob], [0.74 + i * 0.025, 0.93 + bob]], color.darkened(0.2))
		"mittens":  # a pair of mittens on a string (in `color`)
			pic._poly([[0.26, 0.3 + bob], [0.5, 0.18 + bob], [0.74, 0.3 + bob]], Color(0.4, 0.3, 0.25))
			for side in [-1.0, 1.0]:
				var cx: float = 0.5 + side * 0.2
				pic._circle(cx, 0.52 + bob, 0.14, color)
				pic._poly([[cx - 0.14, 0.52 + bob], [cx + 0.14, 0.52 + bob], [cx + 0.12, 0.74 + bob], [cx - 0.12, 0.74 + bob]], color)
				pic._circle(cx - side * 0.15, 0.58 + bob, 0.06, color)  # thumb
				pic._poly([[cx - 0.13, 0.72 + bob], [cx + 0.13, 0.72 + bob], [cx + 0.13, 0.8 + bob], [cx - 0.13, 0.8 + bob]], Color.WHITE)
				pic._circle(cx, 0.5 + bob, 0.03, Color(1, 1, 1, 0.6))


## A snowman standing on (x, foot), `k` times the normal size.
static func _snowman(pic, x: float, foot: float, k: float) -> void:
	pic._circle(x, foot - 0.13 * k, 0.13 * k, SNOW)
	pic._circle(x, foot - 0.32 * k, 0.1 * k, SNOW)
	pic._circle(x, foot - 0.47 * k, 0.075 * k, SNOW)
	pic._eye(x - 0.03 * k, foot - 0.49 * k, 0.018 * k)
	pic._eye(x + 0.03 * k, foot - 0.49 * k, 0.018 * k)
	pic._poly([[x, foot - 0.46 * k], [x + 0.09 * k, foot - 0.45 * k], [x, foot - 0.44 * k]], CARROT)
	for i in 3:
		pic._circle(x, foot - (0.26 + i * 0.05) * k, 0.012 * k, COAL)


## A half dome (an igloo shape) standing on y = base.
static func _dome(pic, x: float, base: float, r: float, c: Color) -> void:
	var pts: Array = []
	for i in 13:
		var a := PI * i / 12.0
		pts.append([x + cos(a) * r, base - sin(a) * r])
	pic._poly(pts, c)
