extends RefCounted
## Starship Crew's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["captain", "planet", "station"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"captain":  # Captain Whiskers (Starship Crew): a ginger space cat in a glass bubble helmet
			var fur := Color(1.0, 0.62, 0.25)
			pic._poly([[0.25, 0.72 + bob], [0.75, 0.72 + bob], [0.82, 0.98], [0.18, 0.98]], Color(0.92, 0.94, 1.0))
			pic._circle(0.5, 0.84 + bob, 0.05, Color(1.0, 0.4, 0.4))
			pic._poly([[0.28, 0.4 + bob], [0.3, 0.16 + bob], [0.44, 0.3 + bob]], fur)
			pic._poly([[0.72, 0.4 + bob], [0.7, 0.16 + bob], [0.56, 0.3 + bob]], fur)
			pic._poly([[0.31, 0.36 + bob], [0.32, 0.22 + bob], [0.41, 0.31 + bob]], Color(1.0, 0.7, 0.75))
			pic._poly([[0.69, 0.36 + bob], [0.68, 0.22 + bob], [0.59, 0.31 + bob]], Color(1.0, 0.7, 0.75))
			pic._circle(0.5, 0.48 + bob, 0.23, fur)
			for sx in [-1.0, 1.0]:
				pic._poly([[0.5 + sx * 0.04, 0.27 + bob], [0.5 + sx * 0.1, 0.27 + bob], [0.5 + sx * 0.07, 0.36 + bob]], fur.darkened(0.25))
			pic._circle(0.5, 0.56 + bob, 0.1, Color(1.0, 0.93, 0.82))
			pic._eye(0.41, 0.45 + bob, 0.06)
			pic._eye(0.59, 0.45 + bob, 0.06)
			pic._poly([[0.47, 0.53 + bob], [0.53, 0.53 + bob], [0.5, 0.57 + bob]], Color(1.0, 0.5, 0.6))
			for sy in [-0.025, 0.025]:
				pic.draw_line(pic._p(0.38, 0.56 + bob + sy), pic._p(0.16, 0.53 + bob + sy * 2.0), Color(0.35, 0.25, 0.2), 2.0)
				pic.draw_line(pic._p(0.62, 0.56 + bob + sy), pic._p(0.84, 0.53 + bob + sy * 2.0), Color(0.35, 0.25, 0.2), 2.0)
			pic.draw_arc(pic._p(0.5, 0.47 + bob), 0.36 * size.x, 0.0, TAU, 40, Color(0.75, 0.92, 1.0, 0.9), 3.0)
			pic._circle(0.36, 0.26 + bob, 0.05, Color(1.0, 1.0, 1.0, 0.55))
		"planet":
			pic._circle(0.5, 0.5 + bob, 0.3, color)
			pic._poly([[0.22, 0.42 + bob], [0.78, 0.4 + bob], [0.8, 0.47 + bob], [0.2, 0.49 + bob]], color.lightened(0.25))
			pic._circle(0.42, 0.6 + bob, 0.06, color.darkened(0.2))
			pic.draw_arc(pic._p(0.5, 0.52 + bob), 0.44 * size.x, 0.35, PI - 0.35, 24, Color(1.0, 0.9, 0.6), 4.0)
			for st in [[0.12, 0.15], [0.86, 0.2], [0.88, 0.85], [0.1, 0.8]]:
				pic._circle(st[0], st[1], 0.02 + 0.01 * sin(t * 4.0 + st[0] * 9.0), white)
		"station":
			var spin := t * 0.6
			pic.draw_arc(pic._p(0.5, 0.5), 0.36 * size.x, 0.0, TAU, 40, Color(1.0, 0.95, 0.88), 0.07 * size.x)
			for k in 6:
				var a := spin + k * TAU / 6.0
				pic.draw_line(pic._p(0.5, 0.5), pic._p(0.5 + cos(a) * 0.36, 0.5 + sin(a) * 0.36), Color(1.0, 0.62, 0.78), 0.03 * size.x)
			pic._circle(0.5, 0.5, 0.12, Color(0.6, 0.85, 1.0))
			pic.draw_arc(pic._p(0.5, 0.5), 0.12 * size.x, 0.0, TAU, 24, Color(1.0, 0.9, 0.4), 3.0)
			for k in 8:
				var a2 := spin + k * TAU / 8.0
				pic._circle(0.5 + cos(a2) * 0.36, 0.5 + sin(a2) * 0.36, 0.03, [Color(1, 0.5, 0.6), Color(0.5, 0.9, 1), Color(1, 0.9, 0.4)][k % 3])
