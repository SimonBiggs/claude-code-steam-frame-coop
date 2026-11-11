extends RefCounted
## Paper Planes' story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Pip is the shared "bird", TODAY'S SKY the shared "sun", COMET Dragon Rider's... any picture works in every game.)

const NAMES: Array[String] = ["glider", "paperdart", "stuntplane", "swallowplane", "goose", "hangar"]

const PAPER := Color(1.0, 0.98, 0.92)
const FOLD := Color(0.82, 0.8, 0.74)
const INK := Color(0.2, 0.22, 0.3)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"glider":  # a wide paper glider floating along (its wing edge in `color`)
			var tilt := sin(t * 1.5) * 0.03
			pic._poly([[0.1, 0.5 + bob - tilt], [0.9, 0.5 + bob + tilt], [0.5, 0.38 + bob]], PAPER)
			pic._poly([[0.1, 0.5 + bob - tilt], [0.9, 0.5 + bob + tilt], [0.5, 0.62 + bob]], FOLD)
			pic._poly([[0.1, 0.5 + bob - tilt], [0.9, 0.5 + bob + tilt], [0.9, 0.53 + bob + tilt], [0.1, 0.53 + bob - tilt]], color)
			for i in 3:  # soft air puffs under it
				var x := 0.25 + i * 0.25 - fmod(t * 0.2, 0.25)
				pic._circle(x, 0.75 + bob, 0.035, Color(1, 1, 1, 0.55))
		"paperdart":  # a long, thin dart zooming right with speed lines
			pic._poly([[0.12, 0.42 + bob], [0.9, 0.5 + bob], [0.3, 0.5 + bob]], PAPER)
			pic._poly([[0.12, 0.58 + bob], [0.9, 0.5 + bob], [0.3, 0.5 + bob]], FOLD)
			pic._poly([[0.3, 0.49 + bob], [0.9, 0.5 + bob], [0.3, 0.52 + bob]], color)
			for i in 3:
				var w := 0.12 + fmod(t * 0.6 + i * 0.3, 0.12)
				pic._poly([[0.02, 0.4 + i * 0.1 + bob], [0.02 + w, 0.4 + i * 0.1 + bob], [0.02 + w, 0.415 + i * 0.1 + bob], [0.02, 0.415 + i * 0.1 + bob]], color.lightened(0.3))
		"stuntplane":  # a plane on a loop-de-loop (a dotted circle behind it)
			for i in 12:
				var a := TAU * i / 12.0
				pic._circle(0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3 + bob, 0.025, color)
			var at := t * 1.6
			var px := 0.5 + cos(at) * 0.3
			var py := 0.5 + sin(at) * 0.3 + bob
			var fx := -sin(at) * 0.16
			var fy := cos(at) * 0.16
			pic._poly([[px + fx, py + fy], [px - fx + fy * 0.6, py - fy - fx * 0.6], [px - fx - fy * 0.6, py - fy + fx * 0.6]], PAPER)
			pic._circle(px, py, 0.03, color.darkened(0.3))
		"swallowplane":  # a swallow-tailed fold: pointed wings and a forked tail
			pic._poly([[0.5, 0.25 + bob], [0.86, 0.52 + bob], [0.56, 0.5 + bob]], PAPER)
			pic._poly([[0.5, 0.25 + bob], [0.14, 0.52 + bob], [0.44, 0.5 + bob]], PAPER)
			pic._poly([[0.44, 0.5 + bob], [0.56, 0.5 + bob], [0.62, 0.82 + bob], [0.5, 0.66 + bob], [0.38, 0.82 + bob]], FOLD)
			pic._poly([[0.48, 0.3 + bob], [0.52, 0.3 + bob], [0.52, 0.64 + bob], [0.48, 0.64 + bob]], color)
		"goose":  # a brown goose flying, wings flapping, a black neck
			var flap := sin(t * 5.0) * 0.12
			pic._poly([[0.4, 0.5 + bob], [0.28, 0.28 + flap + bob], [0.56, 0.48 + bob]], Color(0.55, 0.45, 0.37))
			pic._circle(0.48, 0.55 + bob, 0.15, Color(0.42, 0.33, 0.27))
			pic._circle(0.38, 0.6 + bob, 0.09, Color(0.85, 0.82, 0.76))  # pale tummy
			pic._poly([[0.58, 0.5 + bob], [0.76, 0.36 + bob], [0.8, 0.4 + bob], [0.62, 0.56 + bob]], Color(0.12, 0.12, 0.14))
			pic._circle(0.8, 0.36 + bob, 0.06, Color(0.12, 0.12, 0.14))
			pic._poly([[0.84, 0.34 + bob], [0.94, 0.37 + bob], [0.85, 0.39 + bob]], Color(0.95, 0.65, 0.2))  # beak
			pic._circle(0.79, 0.34 + bob, 0.015, Color.WHITE)
			pic._poly([[0.36, 0.5 + bob], [0.54, 0.46 + bob], [0.72, 0.18 - flap + bob]], Color(0.5, 0.4, 0.33))
		"hangar":  # Pip's hangar: a round-roofed shed with paper planes parked in front
			pic._circle(0.5, 0.52 + bob, 0.3, color)
			pic._poly([[0.2, 0.52 + bob], [0.8, 0.52 + bob], [0.8, 0.78 + bob], [0.2, 0.78 + bob]], color)
			pic._poly([[0.36, 0.5 + bob], [0.64, 0.5 + bob], [0.64, 0.78 + bob], [0.36, 0.78 + bob]], INK)
			pic._poly([[0.1, 0.78 + bob], [0.9, 0.78 + bob], [0.9, 0.82 + bob], [0.1, 0.82 + bob]], Color(0.45, 0.7, 0.35))
			for i in 3:
				var x := 0.2 + i * 0.3
				pic._poly([[x - 0.09, 0.86 + bob], [x + 0.09, 0.86 + bob], [x, 0.8 + bob]], PAPER)
			pic._poly([[0.42, 0.62 + bob], [0.58, 0.62 + bob], [0.5, 0.56 + bob]], PAPER)
