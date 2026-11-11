extends RefCounted
## Penalty Shootout's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Leo's prizes also use "scarf" from Snowball Blitz, "balloon", "bunting" from Cannon Cove and "trophy" from Mini
## Golf Party.)

const NAMES: Array[String] = ["lion", "lioncub", "football", "drum", "foamhand", "biggloves", "curveboots", "mudpatch", "star"]

const FUR := Color(1.0, 0.72, 0.25)
const MANE := Color(0.85, 0.42, 0.1)
const SHIRT := Color(0.15, 0.35, 0.95)
const CREAM := Color(1.0, 0.9, 0.7)
const WHITE := Color(0.98, 0.98, 1.0)
const DARK := Color(0.1, 0.1, 0.12)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"lion":  # Leo: a big friendly lion in a blue football shirt, waving (gold all over when the card asks)
			var fur := FUR if color == Color.WHITE else FUR.lerp(color, 0.25)
			pic._poly(_ellipse(0.5, 0.86 + bob, 0.3, 0.16, 16), SHIRT)  # shirt
			pic._poly([[0.42, 0.78 + bob], [0.58, 0.78 + bob], [0.58, 0.86 + bob], [0.42, 0.86 + bob]], WHITE)  # shirt number
			var wave := sin(t * 5.0) * 0.08
			pic._poly([[0.78, 0.78 + bob], [0.86, 0.74 + bob], [0.94 + wave * 0.5, 0.5 + bob], [0.86, 0.48 + bob]], fur)  # waving arm
			pic._circle(0.92 + wave * 0.5, 0.46 + bob, 0.05, CREAM)
			_lion_head(pic, 0.5, 0.42 + bob, 1.0, fur, t)
		"lioncub":  # a tiny lion cub fan with a little mane, bouncing and cheering
			var hop := absf(sin(t * 4.5)) * 0.05
			pic._poly(_ellipse(0.5, 0.8 + bob - hop, 0.2, 0.12, 14), FUR)
			pic._poly([[0.3, 0.66 + bob - hop], [0.22, 0.48 + bob - hop], [0.28, 0.46 + bob - hop], [0.36, 0.64 + bob - hop]], FUR)  # arms up
			pic._poly([[0.7, 0.66 + bob - hop], [0.78, 0.48 + bob - hop], [0.72, 0.46 + bob - hop], [0.64, 0.64 + bob - hop]], FUR)
			_lion_head(pic, 0.5, 0.52 + bob - hop, 0.7, FUR.lightened(0.1), t)
		"football":  # a black and white football spinning, gold when the card asks (TODAY'S MATCH)
			var base := WHITE if color == Color.WHITE else WHITE.lerp(color, 0.45)
			var y := 0.52 - absf(sin(t * 3.0)) * 0.1 + bob
			pic._circle(0.5, y, 0.3, base)
			var spin := t * 1.2
			pic._poly(_ngon(0.5, y, 0.1, 5, spin), DARK)
			for k in 5:
				var a := spin + TAU * k / 5.0
				pic._poly(_ngon(0.5 + cos(a) * 0.22, y + sin(a) * 0.22, 0.06, 5, spin + PI), DARK)
			pic._circle(0.4, y - 0.12, 0.04, Color(1, 1, 1, 0.6))
			pic._poly(_ellipse(0.5, 0.88, 0.22 - (0.52 - y) * 0.4, 0.035, 12), Color(0, 0, 0, 0.25))  # shadow
		"drum":  # a big red supporters' drum with a beater bouncing on it
			pic._poly([[0.2, 0.42 + bob], [0.8, 0.42 + bob], [0.8, 0.8 + bob], [0.2, 0.8 + bob]], Color(0.9, 0.2, 0.2))
			for k in 4:
				var x := 0.2 + k * 0.2
				pic._poly([[x, 0.44 + bob], [x + 0.2, 0.78 + bob], [x + 0.17, 0.78 + bob], [x - 0.03, 0.44 + bob]], Color(1.0, 0.85, 0.3))
			pic._poly(_ellipse(0.5, 0.42 + bob, 0.3, 0.08, 18), Color(0.95, 0.92, 0.85))
			pic._poly(_ellipse(0.5, 0.8 + bob, 0.3, 0.07, 18), Color(0.7, 0.12, 0.12))
			var hit := absf(sin(t * 6.0))
			var bx := 0.62
			var by := 0.12 + hit * 0.18 + bob
			pic._poly([[bx - 0.015, by], [bx + 0.015, by], [bx + 0.12, by - 0.16], [bx + 0.09, by - 0.17]], Color(0.6, 0.4, 0.2))
			pic._circle(bx, by + 0.02, 0.05, WHITE)
			if hit < 0.25:
				for k in 3:
					pic._circle(0.3 + k * 0.2, 0.3 + bob, 0.02, Color(1, 1, 1, 0.8))  # boom
		"foamhand":  # a giant foam pointing hand (number one!) waving
			var c := Color(0.25, 0.75, 1.0) if color == Color.WHITE else color.lerp(Color(0.25, 0.75, 1.0), 0.5)
			var sway := sin(t * 3.0) * 0.04
			pic._poly([[0.36 + sway, 0.6 + bob], [0.68 + sway, 0.6 + bob], [0.66, 0.92 + bob], [0.38, 0.92 + bob]], c.darkened(0.15))  # cuff
			pic._poly(_ellipse(0.52 + sway, 0.52 + bob, 0.2, 0.15, 16), c)  # fist
			pic._poly([[0.44 + sway * 1.5, 0.48 + bob], [0.56 + sway * 1.5, 0.48 + bob], [0.56 + sway * 2.0, 0.1 + bob], [0.44 + sway * 2.0, 0.1 + bob]], c)  # finger
			pic._circle(0.5 + sway * 2.0, 0.1 + bob, 0.06, c)
			pic._poly(_ellipse(0.7 + sway, 0.5 + bob, 0.06, 0.09, 10), c)  # thumb
			pic._poly([[0.44, 0.74 + bob], [0.6, 0.74 + bob], [0.6, 0.8 + bob], [0.44, 0.8 + bob]], WHITE)  # "1" stripe
		"biggloves":  # two giant green goalkeeper gloves clapping together
			var clap := absf(sin(t * 3.0)) * 0.06
			for side in [-1.0, 1.0]:
				var cx: float = 0.5 + side * (0.17 + clap)
				var g := Color(0.3, 1.0, 0.5)
				pic._poly(_ellipse(cx, 0.5 + bob, 0.16, 0.2, 16), g)  # palm
				for k in 4:
					var fx := cx - 0.1 + k * 0.067
					pic._poly([[fx - 0.03, 0.42 + bob], [fx + 0.03, 0.42 + bob], [fx + 0.03, 0.2 + bob], [fx - 0.03, 0.2 + bob]], g)
					pic._circle(fx, 0.2 + bob, 0.03, g)
				pic._poly(_ellipse(cx - side * 0.15, 0.5 + bob, 0.05, 0.08, 10), g.darkened(0.1))  # thumb
				pic._poly([[cx - 0.14, 0.68 + bob], [cx + 0.14, 0.68 + bob], [cx + 0.12, 0.8 + bob], [cx - 0.12, 0.8 + bob]], WHITE)  # cuff
		"curveboots":  # a bright football boot and a ball bending round in a curve of dots
			var c2 := Color(1.0, 0.5, 0.85)
			pic._poly([[0.12, 0.62 + bob], [0.3, 0.5 + bob], [0.36, 0.62 + bob], [0.5, 0.66 + bob], [0.52, 0.78 + bob], [0.12, 0.78 + bob]], c2)
			for k in 4:
				pic._circle(0.18 + k * 0.1, 0.8 + bob, 0.025, DARK)  # studs
			pic._poly([[0.28, 0.6 + bob], [0.44, 0.66 + bob], [0.44, 0.68 + bob], [0.28, 0.62 + bob]], WHITE)  # laces
			for k in 6:  # the banana path
				var f := float(k) / 5.0
				pic._circle(0.55 + f * 0.3, 0.6 - f * 0.4 + sin(f * PI) * -0.12 + bob, 0.018, Color(1, 1, 1, 0.5 + 0.1 * k))
			var by := 0.2 + bob + sin(t * 3.0) * 0.02
			pic._circle(0.85, by, 0.09, WHITE)
			pic._poly(_ngon(0.85, by, 0.035, 5, t * 2.0), DARK)
		"star":  # Leo's big gold star, turning and twinkling (the card's colour when it asks)
			var gold := Color(1.0, 0.85, 0.25) if color == Color.WHITE else color
			var pts: Array = []
			for k in 10:
				var a := -PI * 0.5 + TAU * k / 10.0 + sin(t * 1.5) * 0.12
				var r := 0.36 if k % 2 == 0 else 0.15
				pts.append([0.5 + cos(a) * r, 0.52 + bob + sin(a) * r])
			pic._poly(pts, gold)
			pic._circle(0.42, 0.44 + bob, 0.04, Color(1, 1, 1, 0.7))
			for k in 3:
				var tw := 0.5 + 0.5 * sin(t * 4.0 + k * 2.1)
				pic._circle(0.18 + k * 0.32, 0.16 + 0.05 * (k % 2), 0.02 + 0.015 * tw, Color(1, 1, 0.8, 0.8))
		"mudpatch":  # a big brown puddle of mud with a ball stuck in it and splats flying
			var mud := Color(0.62, 0.36, 0.16)
			pic._poly(_ellipse(0.5, 0.72 + bob, 0.4, 0.15, 18), mud)
			pic._poly(_ellipse(0.42, 0.7 + bob, 0.18, 0.06, 12), mud.darkened(0.25))
			pic._circle(0.58, 0.62 + bob, 0.12, WHITE)
			pic._poly(_ngon(0.58, 0.6 + bob, 0.04, 5, 0.3), DARK)
			pic._poly(_ellipse(0.58, 0.72 + bob, 0.16, 0.05, 12), mud)  # sunk in
			for k in 3:
				var up := fmod(t * 0.8 + k * 0.33, 1.0)
				pic._circle(0.3 + k * 0.2, 0.55 - up * 0.3 + bob, 0.03 * (1.0 - up * 0.5), mud.lightened(0.1))


## A lion's face: mane, face, ears, eyes, nose and smile. s = size, centred on (x, y).
static func _lion_head(pic, x: float, y: float, s: float, fur: Color, t: float) -> void:
	for k in 12:
		var a := TAU * k / 12.0 + sin(t * 2.0) * 0.05
		pic._circle(x + cos(a) * 0.22 * s, y + sin(a) * 0.22 * s, 0.1 * s, MANE)
	pic._circle(x, y, 0.22 * s, MANE)
	pic._circle(x - 0.15 * s, y - 0.16 * s, 0.06 * s, fur)  # ears
	pic._circle(x + 0.15 * s, y - 0.16 * s, 0.06 * s, fur)
	pic._circle(x, y + 0.01 * s, 0.17 * s, fur)
	pic._poly(_ellipse(x, y + 0.08 * s, 0.09 * s, 0.06 * s, 12), CREAM)  # muzzle
	pic._eye(x - 0.07 * s, y - 0.04 * s, 0.035 * s)
	pic._eye(x + 0.07 * s, y - 0.04 * s, 0.035 * s)
	pic._poly([[x - 0.035 * s, y + 0.04 * s], [x + 0.035 * s, y + 0.04 * s], [x, y + 0.08 * s]], Color(0.35, 0.18, 0.12))  # nose
	pic._poly([[x - 0.05 * s, y + 0.11 * s], [x + 0.05 * s, y + 0.11 * s], [x, y + 0.14 * s]], Color(0.6, 0.15, 0.15))  # smile


static func _ellipse(cx: float, cy: float, rx: float, ry: float, n: int) -> Array:
	var pts: Array = []
	for i in n:
		var a := TAU * i / n
		pts.append([cx + cos(a) * rx, cy + sin(a) * ry])
	return pts


static func _ngon(cx: float, cy: float, r: float, n: int, rot: float) -> Array:
	var pts: Array = []
	for i in n:
		var a := rot + TAU * i / n
		pts.append([cx + cos(a) * r, cy + sin(a) * r])
	return pts
