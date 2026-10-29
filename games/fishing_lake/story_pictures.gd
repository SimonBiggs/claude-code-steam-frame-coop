extends RefCounted
## Fishing Lake's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["fish", "otter"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"fish":  # a friendly fish swimming right, body = color
			var wag := sin(t * 6.0) * 0.05
			pic._poly([[0.22, 0.52 + bob], [0.04, 0.32 + bob + wag], [0.06, 0.72 + bob + wag]], color.darkened(0.25))
			var body := []
			for i in 20:
				var a := TAU * float(i) / 20.0
				body.append([0.52 + cos(a) * 0.34, 0.52 + bob + sin(a) * 0.22])
			pic._poly(body, color)
			pic._poly([[0.42, 0.34 + bob], [0.6, 0.2 + bob], [0.62, 0.34 + bob]], color.darkened(0.2))
			pic._circle(0.52, 0.6 + bob, 0.1, color.lightened(0.35))
			pic._eye(0.72, 0.46 + bob, 0.06)
			pic._circle(0.84, 0.58 + bob, 0.02, Color(0.15, 0.1, 0.1))
		"otter":  # Ollie: a round brown otter face with a cream muzzle and whiskers
			var fur := Color(0.62, 0.42, 0.25)
			pic._circle(0.24, 0.24 + bob, 0.09, fur.darkened(0.15))
			pic._circle(0.76, 0.24 + bob, 0.09, fur.darkened(0.15))
			pic._circle(0.5, 0.52 + bob, 0.36, fur)
			pic._circle(0.5, 0.66 + bob, 0.2, Color(0.95, 0.86, 0.7))
			pic._eye(0.37, 0.44 + bob, 0.07)
			pic._eye(0.63, 0.44 + bob, 0.07)
			pic._circle(0.5, 0.58 + bob, 0.06, Color(0.15, 0.1, 0.1))
			for sy in [-0.03, 0.03]:
				pic.draw_line(pic._p(0.38, 0.66 + bob + sy), pic._p(0.12, 0.62 + bob + sy * 2.0), Color(0.3, 0.2, 0.15), 2.0)
				pic.draw_line(pic._p(0.62, 0.66 + bob + sy), pic._p(0.88, 0.62 + bob + sy * 2.0), Color(0.3, 0.2, 0.15), 2.0)
			pic._poly([[0.44, 0.74 + bob], [0.56, 0.74 + bob], [0.5, 0.8 + bob]], Color(0.75, 0.35, 0.4))
