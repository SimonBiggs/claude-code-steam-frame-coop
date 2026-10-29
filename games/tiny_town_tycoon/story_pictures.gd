extends RefCounted
## Tiny Town Tycoon's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["beaver", "island", "boat"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"beaver":  # Benny (Tiny Town Tycoon): a brown beaver in a yellow hard hat, big front teeth
			var fur := Color(0.62, 0.4, 0.24)
			pic._poly([[0.3, 0.72 + bob], [0.7, 0.72 + bob], [0.8, 0.98], [0.2, 0.98]], fur.darkened(0.1))
			pic._poly([[0.66, 0.9], [0.95, 0.8], [0.98, 0.95], [0.7, 0.99]], Color(0.4, 0.27, 0.18))
			pic._circle(0.3, 0.32 + bob, 0.07, fur.darkened(0.15))
			pic._circle(0.7, 0.32 + bob, 0.07, fur.darkened(0.15))
			pic._circle(0.5, 0.5 + bob, 0.25, fur)
			pic._circle(0.5, 0.62 + bob, 0.13, Color(0.85, 0.68, 0.5))
			pic._eye(0.41, 0.46 + bob, 0.055)
			pic._eye(0.59, 0.46 + bob, 0.055)
			pic._circle(0.5, 0.56 + bob, 0.045, Color(0.2, 0.12, 0.1))
			pic._poly([[0.45, 0.66 + bob], [0.55, 0.66 + bob], [0.55, 0.75 + bob], [0.45, 0.75 + bob]], white)
			pic.draw_line(pic._p(0.5, 0.66 + bob), pic._p(0.5, 0.75 + bob), Color(0.7, 0.7, 0.7), 1.5)
			# the hard hat
			pic._poly([[0.26, 0.32 + bob], [0.74, 0.32 + bob], [0.68, 0.16 + bob], [0.5, 0.11 + bob], [0.32, 0.16 + bob]], Color(1.0, 0.82, 0.15))
			pic._poly([[0.2, 0.33 + bob], [0.8, 0.33 + bob], [0.8, 0.37 + bob], [0.2, 0.37 + bob]], Color(0.95, 0.7, 0.1))
			pic._poly([[0.47, 0.12 + bob], [0.53, 0.12 + bob], [0.53, 0.32 + bob], [0.47, 0.32 + bob]], Color(1.0, 0.9, 0.45))
		"island":
			pic._poly([[0.0, 0.7], [1.0, 0.7], [1.0, 1.0], [0.0, 1.0]], Color(0.3, 0.62, 0.9))
			for k in 4:
				var wx := k * 0.27 + fmod(t * 0.08, 0.27)
				pic.draw_arc(pic._p(wx, 0.8), 0.06 * size.x, PI, TAU, 8, Color(0.8, 0.92, 1.0), 2.0)
			pic._poly([[0.12, 0.72], [0.3, 0.6], [0.7, 0.58], [0.9, 0.72]], Color(0.98, 0.88, 0.6))
			pic._poly([[0.22, 0.64], [0.38, 0.5], [0.62, 0.49], [0.8, 0.64]], Color(0.45, 0.78, 0.35))
			pic.draw_line(pic._p(0.56, 0.52), pic._p(0.6, 0.24 + bob), Color(0.55, 0.38, 0.22), 0.04 * size.x)
			for a in [-2.6, -1.9, -1.2, -0.5]:
				var tip := Vector2(0.6 + cos(a) * 0.2, 0.24 + bob + sin(a) * 0.1 + 0.08)
				pic._poly([[0.6, 0.22 + bob], [tip.x, tip.y], [0.6 + cos(a) * 0.1, 0.27 + bob]], Color(0.3, 0.7, 0.3))
			pic._circle(0.82, 0.18, 0.08, Color(1.0, 0.85, 0.3))
		"boat":
			var rock := sin(t * 2.0) * 0.02
			pic._poly([[0.0, 0.76], [1.0, 0.76], [1.0, 1.0], [0.0, 1.0]], Color(0.3, 0.62, 0.9))
			pic._poly([[0.15, 0.62 + rock], [0.85, 0.62 - rock], [0.72, 0.8], [0.28, 0.8]], Color(0.85, 0.3, 0.25))
			pic._poly([[0.15, 0.62 + rock], [0.85, 0.62 - rock], [0.84, 0.66 - rock], [0.16, 0.66 + rock]], white)
			pic.draw_line(pic._p(0.5, 0.62), pic._p(0.5, 0.14 + bob), Color(0.5, 0.35, 0.2), 0.03 * size.x)
			pic._poly([[0.53, 0.18 + bob], [0.53, 0.56], [0.82, 0.56]], color)
			pic._poly([[0.47, 0.24 + bob], [0.47, 0.56], [0.24, 0.56]], white)
			pic._poly([[0.5, 0.14 + bob], [0.64, 0.17 + bob], [0.5, 0.2 + bob]], Color(1.0, 0.85, 0.3))
			for k in 3:
				var wx2 := k * 0.4 + fmod(t * 0.1, 0.4)
				pic.draw_arc(pic._p(wx2, 0.86), 0.07 * size.x, PI, TAU, 8, Color(0.8, 0.92, 1.0), 2.0)
