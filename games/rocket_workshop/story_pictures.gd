extends RefCounted
## Rocket Workshop's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["engineer", "boosters", "rocketfins", "parachute", "meteor"]


static func draw(pic, kind: String, t: float, bob: float, _color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"engineer":  # Sprocket (Rocket Workshop): a teal robot with a screen face, orange hard hat and a spanner
			var teal := Color(0.3, 0.8, 0.85)
			pic._poly([[0.3, 0.78 + bob], [0.7, 0.78 + bob], [0.72, 0.98], [0.28, 0.98]], teal.darkened(0.15))
			pic._poly([[0.2, 0.32 + bob], [0.8, 0.32 + bob], [0.8, 0.78 + bob], [0.2, 0.78 + bob]], teal)
			pic._poly([[0.27, 0.4 + bob], [0.73, 0.4 + bob], [0.73, 0.71 + bob], [0.27, 0.71 + bob]], Color(0.08, 0.12, 0.18))
			var blink := 0.2 if fmod(t, 3.0) < 0.12 else 1.0
			for ex in [0.4, 0.6]:
				pic.draw_set_transform(pic._p(ex, 0.52 + bob), 0.0, Vector2(1.0, blink))
				pic.draw_circle(Vector2.ZERO, 0.055 * size.x, Color(0.5, 1.0, 0.95))
				pic.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			pic.draw_arc(pic._p(0.5, 0.6 + bob), 0.08 * size.x, 0.4, PI - 0.4, 10, Color(0.5, 1.0, 0.95), 0.02 * size.x)
			pic._poly([[0.22, 0.33 + bob], [0.78, 0.33 + bob], [0.7, 0.16 + bob], [0.3, 0.16 + bob]], Color(1.0, 0.6, 0.15))
			pic._poly([[0.12, 0.35 + bob], [0.88, 0.35 + bob], [0.88, 0.3 + bob], [0.12, 0.3 + bob]], Color(0.95, 0.5, 0.1))
			pic.draw_line(pic._p(0.62, 0.17 + bob), pic._p(0.68, 0.04 + bob), Color(0.6, 0.6, 0.65), 0.02 * size.x)
			pic._circle(0.68, 0.04 + bob, 0.035, Color(1.0, 0.3, 0.3) if fmod(t, 1.0) < 0.5 else Color(0.6, 0.15, 0.15))
			var sw := sin(t * 4.0) * 0.04
			pic.draw_line(pic._p(0.86, 0.86 + sw), pic._p(0.92, 0.6 + sw), Color(0.75, 0.75, 0.8), 0.05 * size.x)
			pic.draw_arc(pic._p(0.92, 0.57 + sw), 0.05 * size.x, PI * 0.9, PI * 2.1, 10, Color(0.75, 0.75, 0.8), 0.035 * size.x)
		"boosters":  # Sprocket's gift: a white rocket with two orange boosters and big flames
			var fl := 0.06 * sin(t * 18.0)
			for bx in [0.3, 0.7]:
				pic._poly([[bx - 0.06, 0.78 + bob], [bx + 0.06, 0.78 + bob], [bx, 0.97 + fl + bob]], Color(1.0, 0.75, 0.2))
				pic._poly([[bx - 0.07, 0.38 + bob], [bx + 0.07, 0.38 + bob], [bx + 0.07, 0.78 + bob], [bx - 0.07, 0.78 + bob]], Color(1.0, 0.55, 0.2))
				pic._poly([[bx - 0.07, 0.38 + bob], [bx + 0.07, 0.38 + bob], [bx, 0.28 + bob]], Color(0.95, 0.35, 0.2))
			pic._poly([[0.4, 0.82 + bob], [0.6, 0.82 + bob], [0.5, 0.99 + fl + bob]], Color(1.0, 0.85, 0.3))
			pic._poly([[0.38, 0.3 + bob], [0.62, 0.3 + bob], [0.62, 0.82 + bob], [0.38, 0.82 + bob]], Color(0.95, 0.95, 0.98))
			pic._poly([[0.38, 0.3 + bob], [0.62, 0.3 + bob], [0.5, 0.06 + bob]], Color(0.95, 0.3, 0.3))
			pic._circle(0.5, 0.48 + bob, 0.07, Color(0.4, 0.75, 1.0))
		"rocketfins":  # Sprocket's gift: a rocket with big blue swept fins
			pic._poly([[0.36, 0.62 + bob], [0.14, 0.92 + bob], [0.36, 0.84 + bob]], Color(0.35, 0.7, 1.0))
			pic._poly([[0.64, 0.62 + bob], [0.86, 0.92 + bob], [0.64, 0.84 + bob]], Color(0.35, 0.7, 1.0))
			pic._poly([[0.36, 0.28 + bob], [0.64, 0.28 + bob], [0.64, 0.86 + bob], [0.36, 0.86 + bob]], Color(0.95, 0.95, 0.98))
			pic._poly([[0.36, 0.28 + bob], [0.64, 0.28 + bob], [0.5, 0.04 + bob]], Color(0.25, 0.5, 1.0))
			pic._poly([[0.46, 0.55 + bob], [0.54, 0.55 + bob], [0.54, 0.9 + bob], [0.46, 0.9 + bob]], Color(0.35, 0.7, 1.0))
			pic._circle(0.5, 0.45 + bob, 0.07, Color(0.4, 0.75, 1.0))
		"parachute":  # Sprocket's gift: a striped red and white parachute with a little rocket swinging under it
			var sw2 := sin(t * 2.0) * 0.03
			var cols: Array[Color] = [Color(1.0, 0.4, 0.45), Color(1.0, 0.97, 0.95)]
			for k in 6:
				var a0 := PI + PI * k / 6.0
				var a1 := PI + PI * (k + 1) / 6.0
				pic._poly([[0.5, 0.42 + bob], [0.5 + cos(a0) * 0.4, 0.42 + sin(a0) * 0.32 + bob], [0.5 + cos(a1) * 0.4, 0.42 + sin(a1) * 0.32 + bob]], cols[k % 2])
			for sx in [0.12, 0.5, 0.88]:
				pic.draw_line(pic._p(sx, 0.42 + bob), pic._p(0.5 + sw2, 0.72 + bob), Color(0.4, 0.4, 0.45), 0.012 * size.x)
			pic._poly([[0.44 + sw2, 0.72 + bob], [0.56 + sw2, 0.72 + bob], [0.56 + sw2, 0.94 + bob], [0.44 + sw2, 0.94 + bob]], Color(0.95, 0.95, 0.98))
			pic._poly([[0.44 + sw2, 0.72 + bob], [0.56 + sw2, 0.72 + bob], [0.5 + sw2, 0.64 + bob]], Color(0.95, 0.3, 0.3))
		"meteor":  # a purple space rock with an orange glowing crack, a fiery tail behind it
			for k in 4:
				var o := 0.07 * k
				pic._poly([[0.62 - o, 0.36 - o], [0.94 - o * 0.4, 0.06 + o * 0.2], [0.7 - o, 0.46 - o]], Color(1.0, 0.55 + 0.1 * k, 0.15, 0.85 - 0.15 * k))
			pic._circle(0.42, 0.6 + bob, 0.27, Color(0.42, 0.36, 0.5))
			pic._circle(0.52, 0.5 + bob, 0.1, Color(0.5, 0.44, 0.58))
			pic._circle(0.32, 0.72 + bob, 0.07, Color(0.33, 0.28, 0.4))
			pic.draw_line(pic._p(0.3, 0.55 + bob), pic._p(0.45, 0.62 + bob), Color(1.0, 0.55, 0.15), 0.025 * size.x)
			pic.draw_line(pic._p(0.45, 0.62 + bob), pic._p(0.52, 0.76 + bob), Color(1.0, 0.55, 0.15), 0.025 * size.x)
