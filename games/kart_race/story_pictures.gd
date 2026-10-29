extends RefCounted
## Kart Race's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["kart", "partyhat", "cowboy", "wizard"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"kart":
			var roll := t * 8.0
			pic._poly([[0.12, 0.6 + bob], [0.88, 0.6 + bob], [0.82, 0.74 + bob], [0.18, 0.74 + bob]], color)
			pic._poly([[0.62, 0.48 + bob], [0.82, 0.48 + bob], [0.88, 0.6 + bob], [0.6, 0.6 + bob]], color.lightened(0.25))
			pic._poly([[0.1, 0.44 + bob], [0.24, 0.44 + bob], [0.24, 0.6 + bob], [0.1, 0.6 + bob]], color.darkened(0.2))
			pic._circle(0.42, 0.42 + bob, 0.12, Color(0.97, 0.97, 1.0))
			pic._poly([[0.44, 0.38 + bob], [0.56, 0.38 + bob], [0.56, 0.45 + bob], [0.44, 0.45 + bob]], Color(0.2, 0.6, 1.0))
			for x in [0.27, 0.73]:
				pic._circle(x, 0.78, 0.1, Color(0.1, 0.1, 0.12))
				pic.draw_line(pic._p(x, 0.78), pic._p(x + cos(roll) * 0.07, 0.78 + sin(roll) * 0.07), Color(0.85, 0.85, 0.9), 0.02 * size.x)
			for k in 3:
				var x := 0.02 - fmod(t * 0.6 + k * 0.33, 1.0) * 0.1
				pic._circle(0.06 + x, 0.66 + k * 0.04, 0.025, Color(1.0, 1.0, 1.0, 0.6))
		"partyhat":
			pic._poly([[0.2, 0.86 + bob], [0.8, 0.86 + bob], [0.5, 0.14 + bob]], color)
			for k in 3:
				var y := 0.36 + k * 0.18
				var w := (y - 0.14) / 0.72 * 0.3
				pic._poly([[0.5 - w, y + bob], [0.5 + w, y + bob], [0.5 + w + 0.025, y + 0.06 + bob], [0.5 - w - 0.025, y + 0.06 + bob]], Color(1.0, 0.95, 0.4))
			pic._circle(0.5, 0.13 + bob, 0.08, white)
		"cowboy":
			pic._poly([[0.05, 0.66 + bob], [0.95, 0.66 + bob], [0.85, 0.76 + bob], [0.15, 0.76 + bob]], Color(0.6, 0.38, 0.2))
			pic._poly([[0.3, 0.68 + bob], [0.7, 0.68 + bob], [0.66, 0.3 + bob], [0.5, 0.38 + bob], [0.34, 0.3 + bob]], Color(0.68, 0.45, 0.25))
			pic._poly([[0.31, 0.58 + bob], [0.69, 0.58 + bob], [0.69, 0.64 + bob], [0.31, 0.64 + bob]], Color(0.95, 0.3, 0.3))
		"wizard":
			pic._poly([[0.08, 0.8 + bob], [0.92, 0.8 + bob], [0.82, 0.88 + bob], [0.18, 0.88 + bob]], color.darkened(0.2))
			pic._poly([[0.26, 0.82 + bob], [0.74, 0.82 + bob], [0.6, 0.35 + bob], [0.72, 0.1 + bob], [0.5, 0.3 + bob]], color)
			for st_p in [[0.45, 0.6], [0.58, 0.42], [0.5, 0.74]]:
				pic._circle(st_p[0], st_p[1] + bob, 0.035 + 0.01 * sin(t * 5.0 + st_p[0] * 9.0), Color(1.0, 0.92, 0.35))
