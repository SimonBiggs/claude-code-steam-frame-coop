extends RefCounted
## Balloon Pop's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["seller", "icecream", "carousel", "ferris", "tent"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"seller":  # Poppy (Balloon Pop): a smiling face in a pink party hat, holding a bunch of balloons
			var cols: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.3), Color(0.35, 0.65, 1.0), Color(0.5, 0.9, 0.45)]
			for k in 4:
				var bx := 0.72 + (k % 2) * 0.14 + sin(t * 2.0 + k) * 0.015
				var by := 0.16 + (k / 2) * 0.15 + bob
				pic.draw_line(pic._p(bx, by + 0.08), pic._p(0.74, 0.72 + bob), Color(0.9, 0.9, 0.95), 1.5)
				pic._circle(bx, by, 0.08, cols[k])
			pic._circle(0.42, 0.58 + bob, 0.27, Color(1.0, 0.85, 0.72))
			pic._poly([[0.22, 0.4 + bob], [0.62, 0.4 + bob], [0.42, 0.06 + bob]], color)
			pic._circle(0.42, 0.06 + bob, 0.05, Color(1.0, 0.9, 0.4))
			for k in 3:
				pic._circle(0.3 + k * 0.12, 0.38 + bob, 0.035, Color(1.0, 0.9, 0.4))
			pic._eye(0.34, 0.56 + bob, 0.055)
			pic._eye(0.5, 0.56 + bob, 0.055)
			pic._circle(0.28, 0.66 + bob, 0.04, Color(1.0, 0.55, 0.6))
			pic._circle(0.56, 0.66 + bob, 0.04, Color(1.0, 0.55, 0.6))
			pic.draw_arc(pic._p(0.42, 0.66 + bob), 0.09 * size.x, 0.3, PI - 0.3, 10, Color(0.6, 0.2, 0.25), 2.5)
		"icecream":
			pic._poly([[0.34, 0.5 + bob], [0.66, 0.5 + bob], [0.5, 0.95 + bob]], Color(0.88, 0.62, 0.32))
			pic.draw_line(pic._p(0.4, 0.6 + bob), pic._p(0.58, 0.75 + bob), Color(0.7, 0.45, 0.2), 2.0)
			pic.draw_line(pic._p(0.6, 0.6 + bob), pic._p(0.44, 0.78 + bob), Color(0.7, 0.45, 0.2), 2.0)
			pic._circle(0.5, 0.45 + bob, 0.18, Color(1.0, 0.75, 0.85))
			pic._circle(0.5, 0.28 + bob, 0.15, Color(0.55, 0.35, 0.25))
			pic._circle(0.5, 0.12 + bob, 0.05, Color(0.9, 0.15, 0.2))
		"carousel":
			var spin := t * 1.5
			pic._poly([[0.5, 0.08 + bob], [0.9, 0.32 + bob], [0.1, 0.32 + bob]], Color(0.4, 0.7, 1.0))
			for k in 3:
				pic._poly([[0.5, 0.08 + bob], [0.23 + k * 0.27, 0.32 + bob], [0.36 + k * 0.27, 0.32 + bob]], white)
			pic._poly([[0.12, 0.84], [0.88, 0.84], [0.88, 0.92], [0.12, 0.92]], Color(0.95, 0.85, 0.6))
			for k in 3:
				var hx := 0.5 + sin(spin + k * TAU / 3.0) * 0.3
				var hy := 0.6 + sin(spin * 2.0 + k) * 0.04
				pic.draw_line(pic._p(hx, 0.32 + bob), pic._p(hx, 0.84), Color(1.0, 0.85, 0.3), 2.0)
				pic._circle(hx, hy, 0.07, [Color(1.0, 0.35, 0.4), Color(0.5, 0.9, 0.45), Color(0.85, 0.5, 1.0)][k])
		"ferris":
			pic.draw_line(pic._p(0.5, 0.48), pic._p(0.25, 0.95), Color(0.75, 0.75, 0.82), 3.0)
			pic.draw_line(pic._p(0.5, 0.48), pic._p(0.75, 0.95), Color(0.75, 0.75, 0.82), 3.0)
			pic.draw_arc(pic._p(0.5, 0.48), 0.36 * size.x, 0.0, TAU, 32, Color(1.0, 0.8, 0.25), 3.0)
			for k in 8:
				var a := k * TAU / 8.0 + t * 0.6
				var q := Vector2(0.5 + cos(a) * 0.36, 0.48 + sin(a) * 0.36)
				pic.draw_line(pic._p(0.5, 0.48), pic._p(q.x, q.y), white, 1.5)
				pic._circle(q.x, q.y + 0.04, 0.05, [Color(1.0, 0.35, 0.4), Color(0.35, 0.65, 1.0), Color(0.5, 0.9, 0.45), Color(1.0, 0.55, 0.15)][k % 4])
		"tent":
			for k in 5:
				var x0 := 0.15 + k * 0.14
				pic._poly([[x0, 0.45], [x0 + 0.14, 0.45], [x0 + 0.14, 0.9], [x0, 0.9]], Color(0.95, 0.25, 0.3) if k % 2 == 0 else white)
			pic._poly([[0.08, 0.47 + bob * 0.5], [0.92, 0.47 + bob * 0.5], [0.5, 0.12 + bob * 0.5]], Color(0.95, 0.25, 0.3))
			pic._poly([[0.42, 0.9], [0.58, 0.9], [0.5, 0.62]], Color(0.2, 0.15, 0.2))
			pic.draw_line(pic._p(0.5, 0.12 + bob * 0.5), pic._p(0.5, 0.0 + bob * 0.5), white, 2.0)
			pic._poly([[0.5, 0.0 + bob * 0.5], [0.66, 0.04 + bob * 0.5], [0.5, 0.08 + bob * 0.5]], Color(1.0, 0.85, 0.3))
