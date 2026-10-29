extends RefCounted
## Tower Stack's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["wren", "tower"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"wren":  # Wren: a round brown builder bird with a perky tail and a blue hard hat
			var brown := Color(0.62, 0.42, 0.25)
			pic._poly([[0.22, 0.55 + bob], [0.06, 0.2 + bob], [0.16, 0.18 + bob], [0.32, 0.5 + bob]], brown.darkened(0.2))
			pic._circle(0.5, 0.58 + bob, 0.3, brown)
			pic._circle(0.55, 0.66 + bob, 0.17, Color(0.95, 0.85, 0.7))
			pic._poly([[0.78, 0.48 + bob], [0.97, 0.53 + bob], [0.78, 0.58 + bob]], Color(1.0, 0.65, 0.2))
			pic._eye(0.64, 0.46 + bob, 0.065)
			var flap := sin(t * 9.0) * 0.07
			pic._poly([[0.36, 0.58 + bob], [0.14, 0.5 + bob - flap], [0.3, 0.76 + bob]], brown.darkened(0.3))
			pic._poly([[0.3, 0.32 + bob], [0.72, 0.32 + bob], [0.66, 0.15 + bob], [0.36, 0.15 + bob]], Color(0.25, 0.55, 0.95))
			pic._poly([[0.24, 0.35 + bob], [0.8, 0.35 + bob], [0.8, 0.3 + bob], [0.24, 0.3 + bob]], Color(0.2, 0.45, 0.85))
			pic._poly([[0.47, 0.32 + bob], [0.55, 0.32 + bob], [0.53, 0.15 + bob], [0.49, 0.15 + bob]], Color(1.0, 0.85, 0.3))
			pic.draw_line(pic._p(0.4, 0.86 + bob), pic._p(0.38, 0.97), Color(1.0, 0.65, 0.2), 0.025 * size.x)
			pic.draw_line(pic._p(0.56, 0.86 + bob), pic._p(0.58, 0.97), Color(1.0, 0.65, 0.2), 0.025 * size.x)
		"tower":  # a jelly-block tower in color under a red roof, with a little flag
			var wob := sin(t * 3.0) * 0.015
			for k in 3:
				var y0 := 0.94 - 0.2 * (k + 1)
				var x0 := 0.3 + wob * (k + 1)
				var col := color.lightened(0.15 * k) if k != 1 else color.darkened(0.15)
				pic._poly([[x0, y0], [x0 + 0.4, y0], [x0 + 0.4, y0 + 0.19], [x0, y0 + 0.19]], col)
				pic._circle(x0 + 0.14, y0 + 0.08, 0.025, Color(0.1, 0.1, 0.15))
				pic._circle(x0 + 0.26, y0 + 0.08, 0.025, Color(0.1, 0.1, 0.15))
			var tx := 0.3 + wob * 4.0
			pic._poly([[tx - 0.05, 0.34], [tx + 0.45, 0.34], [tx + 0.2, 0.12]], Color(0.9, 0.3, 0.3))
			pic.draw_line(pic._p(tx + 0.2, 0.13), pic._p(tx + 0.2, 0.02), Color(0.4, 0.3, 0.25), 0.02 * size.x)
			pic._poly([[tx + 0.2, 0.02], [tx + 0.34, 0.05 + sin(t * 6.0) * 0.01], [tx + 0.2, 0.08]], Color(1.0, 0.85, 0.3))
