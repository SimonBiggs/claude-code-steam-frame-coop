extends RefCounted
## Bubble Bath's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Toys also use "boat" from Treasure Dig, "starfish" from Cannon Cove and "fish" from Fishing Lake.)

const NAMES: Array[String] = ["mamaduck", "duckling", "sponge", "bathtub", "beachball", "soapbar", "whale"]

const YELLOW := Color(1.0, 0.86, 0.15)
const ORANGE := Color(1.0, 0.5, 0.1)
const PINK := Color(1.0, 0.6, 0.8)
const BLUE := Color(0.35, 0.65, 1.0)
const WHITE := Color(0.98, 0.98, 1.0)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"mamaduck":  # a big rubber duck with a pink bow (yellow; another colour when the card asks, e.g. gold)
			var c := YELLOW if color == Color.WHITE else color.lerp(YELLOW, 0.4)
			_duck(pic, 0.5, 0.56 + bob, 1.0, c, sin(t * 3.0) * 0.03)
			pic._poly([[0.5, 0.2 + bob], [0.36, 0.13 + bob], [0.38, 0.27 + bob]], PINK)  # bow
			pic._poly([[0.5, 0.2 + bob], [0.64, 0.13 + bob], [0.62, 0.27 + bob]], PINK)
			pic._circle(0.5, 0.2 + bob, 0.035, PINK.darkened(0.2))
		"duckling":  # a tiny fluffy duckling paddling
			var c := YELLOW.lightened(0.25)
			var hop := absf(sin(t * 4.0)) * 0.04
			_duck(pic, 0.5, 0.6 + bob - hop, 0.75, c, 0.0)
		"sponge":  # a squishy yellow-green sponge island with holes
			var sq := 1.0 + sin(t * 2.5) * 0.04
			pic._poly([[0.14, 0.42 + bob], [0.86, 0.42 + bob], [0.86, 0.42 + 0.3 * sq + bob], [0.14, 0.42 + 0.3 * sq + bob]], Color(0.95, 0.85, 0.3))
			pic._poly([[0.14, 0.35 + bob], [0.86, 0.35 + bob], [0.86, 0.44 + bob], [0.14, 0.44 + bob]], Color(0.3, 0.75, 0.4))
			for h in [[0.28, 0.55], [0.5, 0.62], [0.7, 0.52], [0.4, 0.68], [0.78, 0.65]]:
				pic._circle(h[0], h[1] + bob, 0.03, Color(0.8, 0.65, 0.2))
			_waves(pic, 0.8, t)
		"bathtub":  # a tub of bubbles with a duck peeking out
			pic._poly([[0.1, 0.5], [0.9, 0.5], [0.82, 0.8], [0.18, 0.8]], WHITE)
			pic._poly([[0.1, 0.5], [0.9, 0.5], [0.9, 0.55], [0.1, 0.55]], Color(0.8, 0.85, 0.92))
			pic._circle(0.24, 0.86, 0.04, Color(1.0, 0.8, 0.3))
			pic._circle(0.76, 0.86, 0.04, Color(1.0, 0.8, 0.3))
			_duck(pic, 0.6, 0.42 + bob, 0.45, YELLOW, 0.0)
			for k in 5:
				var x := 0.18 + k * 0.15
				pic._circle(x, 0.47 + sin(t * 2.0 + k) * 0.015, 0.07 + 0.02 * (k % 2), Color(0.92, 0.95, 1.0, 0.9))
		"beachball":  # a striped beach ball bouncing
			var y := 0.5 - absf(sin(t * 3.0)) * 0.12 + bob
			var cols := [Color(0.95, 0.25, 0.25), WHITE, BLUE, WHITE, YELLOW, WHITE]
			for k in 6:
				var a0 := TAU * k / 6.0 + t * 0.8
				var pts: Array = [[0.5, y]]
				for s in 5:
					var a := a0 + TAU / 6.0 * s / 4.0
					pts.append([0.5 + cos(a) * 0.3, y + sin(a) * 0.3])
				pic._poly(pts, cols[k])
			pic._circle(0.5, y, 0.06, WHITE)
			pic._circle(0.4, y - 0.12, 0.04, Color(1, 1, 1, 0.7))
		"soapbar":  # a pink bar of soap blowing bubbles
			pic._poly([[0.16, 0.56 + bob], [0.76, 0.56 + bob], [0.8, 0.78 + bob], [0.2, 0.78 + bob]], PINK)
			pic._poly([[0.2, 0.52 + bob], [0.72, 0.52 + bob], [0.76, 0.58 + bob], [0.16, 0.58 + bob]], PINK.lightened(0.3))
			for k in 4:
				var f := fmod(t * 0.5 + k * 0.25, 1.0)
				pic._circle(0.55 + sin(f * 6.0 + k) * 0.1, 0.48 - f * 0.4, 0.04 + f * 0.05, Color(0.85, 0.92, 1.0, 1.0 - f * 0.7))
		"whale":  # a blue squirty bath whale with a spout
			pic._poly(_ellipse(0.48, 0.6 + bob, 0.32, 0.2, 18), BLUE)
			pic._poly(_ellipse(0.5, 0.68 + bob, 0.24, 0.1, 14), Color(0.75, 0.88, 1.0))
			pic._poly([[0.78, 0.58 + bob], [0.94, 0.44 + bob], [0.92, 0.66 + bob]], BLUE)  # tail
			pic._eye(0.3, 0.56 + bob, 0.04)
			var sp := 0.08 + absf(sin(t * 3.0)) * 0.06
			for k in 3:
				pic._circle(0.42 + (k - 1) * 0.06, 0.38 - sp - absf(k - 1) * 0.03 + bob, 0.035, Color(0.6, 0.85, 1.0))
			pic._poly([[0.41, 0.42 + bob], [0.43, 0.42 + bob], [0.43, 0.32 - sp + bob], [0.41, 0.32 - sp + bob]], Color(0.6, 0.85, 1.0))


## A rubber duck facing left: body, head, beak, eye, wing. s = size.
static func _duck(pic, x: float, y: float, s: float, c: Color, nod: float) -> void:
	pic._poly(_ellipse(x + 0.05 * s, y + 0.08 * s, 0.3 * s, 0.17 * s, 18), c)  # body
	pic._poly([[x + 0.3 * s, y], [x + 0.4 * s, y - 0.1 * s], [x + 0.33 * s, y + 0.1 * s]], c)  # tail
	pic._circle(x - 0.12 * s, y - 0.16 * s + nod, 0.14 * s, c)  # head
	pic._poly([[x - 0.24 * s, y - 0.16 * s + nod], [x - 0.38 * s, y - 0.12 * s + nod], [x - 0.24 * s, y - 0.08 * s + nod]], ORANGE)  # beak
	pic._eye(x - 0.14 * s, y - 0.2 * s + nod, 0.035 * s)
	pic._poly(_ellipse(x + 0.08 * s, y + 0.06 * s, 0.14 * s, 0.07 * s, 10), c.darkened(0.12))  # wing


static func _waves(pic, y: float, t: float) -> void:
	for k in 4:
		var x := 0.12 + k * 0.22
		var dy := sin(t * 2.0 + k) * 0.02
		pic._poly(_ellipse(x + 0.1, y + dy, 0.12, 0.04, 10), Color(0.5, 0.8, 1.0, 0.8))


static func _ellipse(cx: float, cy: float, rx: float, ry: float, n: int) -> Array:
	var pts: Array = []
	for i in n:
		var a := TAU * i / n
		pts.append([cx + cos(a) * rx, cy + sin(a) * ry])
	return pts
