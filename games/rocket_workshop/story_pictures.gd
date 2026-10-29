extends RefCounted
## Rocket Workshop's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["engineer"]


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
