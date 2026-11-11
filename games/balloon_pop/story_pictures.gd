extends RefCounted
## Balloon Pop's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["seller", "icecream", "carousel", "ferris", "tent", "dart", "pump", "balloonmagnet", "popburst", "parade", "nightsky"]


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
		"dart":  # Poppy's gift: a dart flying at a balloon
			pic._circle(0.68, 0.34 + bob, 0.2, Color(0.95, 0.08, 0.3))
			pic._circle(0.62, 0.28 + bob, 0.05, Color(1.0, 0.7, 0.75))
			pic.draw_line(pic._p(0.68, 0.54 + bob), pic._p(0.7, 0.66 + bob), Color(0.9, 0.9, 0.95), 1.5)
			var tip := Vector2(0.5 + sin(t * 3.0) * 0.02, 0.5)
			pic.draw_line(pic._p(0.12, 0.85), pic._p(tip.x, tip.y), Color(0.55, 0.4, 0.25), 4.0)
			pic._poly([[tip.x, tip.y], [tip.x - 0.1, tip.y + 0.02], [tip.x - 0.06, tip.y + 0.07]], Color(0.8, 0.8, 0.85))
			pic._poly([[0.12, 0.85], [0.06, 0.72], [0.2, 0.8]], color)
			pic._poly([[0.12, 0.85], [0.25, 0.9], [0.17, 0.76]], color)
		"pump":  # Poppy's gift: a pump puffing up a balloon
			var puff := 0.16 + 0.04 * (0.5 + 0.5 * sin(t * 3.0))
			pic._poly([[0.12, 0.92], [0.42, 0.92], [0.38, 0.86], [0.16, 0.86]], Color(0.3, 0.3, 0.35))
			pic._poly([[0.22, 0.86], [0.32, 0.86], [0.32, 0.42], [0.22, 0.42]], color)
			pic.draw_line(pic._p(0.27, 0.42), pic._p(0.27, 0.26 + bob * 0.5), Color(0.3, 0.3, 0.35), 3.0)
			pic._poly([[0.16, 0.24 + bob * 0.5], [0.38, 0.24 + bob * 0.5], [0.38, 0.29 + bob * 0.5], [0.16, 0.29 + bob * 0.5]], Color(0.3, 0.3, 0.35))
			pic.draw_line(pic._p(0.32, 0.8), pic._p(0.62, 0.78), Color(0.25, 0.25, 0.3), 3.0)
			pic._circle(0.7, 0.5, puff * 1.6, Color(1.0, 0.45, 0.8))
			pic._circle(0.66, 0.42, 0.04, Color(1.0, 0.85, 0.95))
		"balloonmagnet":  # Poppy's gift: a horseshoe magnet pulling balloons in
			var pull := 0.5 + 0.5 * sin(t * 2.5)
			pic.draw_arc(pic._p(0.3, 0.55), 0.18 * size.x, PI * 0.5, PI * 1.5, 16, Color(0.95, 0.15, 0.2), 0.1 * size.x)
			pic._poly([[0.3, 0.32], [0.46, 0.32], [0.46, 0.42], [0.3, 0.42]], Color(0.85, 0.85, 0.9))
			pic._poly([[0.3, 0.68], [0.46, 0.68], [0.46, 0.78], [0.3, 0.78]], Color(0.85, 0.85, 0.9))
			var mcols: Array[Color] = [Color(0.15, 0.3, 0.95), Color(1.0, 0.85, 0.1), Color(0.55, 1.0, 0.15)]
			for k in 3:
				pic._circle(0.88 - pull * 0.12, 0.3 + k * 0.22 + bob, 0.08, mcols[k])
				pic.draw_line(pic._p(0.56, 0.3 + k * 0.22), pic._p(0.66, 0.3 + k * 0.22), Color(1.0, 0.85, 0.3), 1.5)
		"popburst":  # Poppy's gift: POP POP - a star burst popping balloons round it
			var spin := t * 1.5
			for k in 8:
				var a := spin + k * TAU / 8.0
				pic.draw_line(pic._p(0.5, 0.5), pic._p(0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3), Color(1.0, 0.9, 0.4), 3.0)
			pic._circle(0.5, 0.5, 0.14, color)
			var cols2: Array[Color] = [Color(0.95, 0.08, 0.3), Color(0.15, 0.3, 0.95), Color(0.55, 1.0, 0.15), Color(1.0, 0.36, 0.0)]
			for k in 4:
				var a2 := k * TAU / 4.0 + PI * 0.25
				pic._circle(0.5 + cos(a2) * 0.38, 0.5 + sin(a2) * 0.38 + bob, 0.07, cols2[k])
		"parade":  # Poppy's balloon parade: a line of balloons on strings marching across the sky
			var pcols: Array[Color] = [Color(0.95, 0.08, 0.3), Color(1.0, 0.36, 0.0), Color(1.0, 0.85, 0.1), Color(0.55, 1.0, 0.15),
				Color(0.15, 0.3, 0.95), Color(0.75, 0.4, 1.0)]
			for k in 6:
				var x := 0.1 + k * 0.16
				var y := 0.38 + sin(t * 2.0 + k * 0.9) * 0.06
				pic.draw_line(pic._p(x, y + 0.1), pic._p(x + 0.02, 0.85), Color(0.9, 0.9, 0.95), 1.5)
				pic._circle(x, y, 0.08, pcols[k])
			pic._poly([[0.0, 0.85], [1.0, 0.85], [1.0, 0.9], [0.0, 0.9]], color)
		"nightsky":  # a starry night: a moon and twinkling stars
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.08, 0.1, 0.25))
			pic._circle(0.62, 0.4 + bob, 0.22, Color(1.0, 0.95, 0.7))
			pic._circle(0.72, 0.34 + bob, 0.2, Color(0.08, 0.1, 0.25))
			for k in 6:
				var tw := 0.02 + 0.015 * (0.5 + 0.5 * sin(t * 3.0 + k * 1.7))
				pic._circle(0.12 + fmod(k * 0.37, 0.8), 0.15 + fmod(k * 0.53, 0.75), tw, Color(1.0, 1.0, 0.85))
