extends RefCounted
## Treasure Dig's story card pictures (core/story_pictures.gd finds this file by itself). Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["bigspade", "detector", "horseshoe", "museum", "coconut", "tidewave", "goldgem"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"bigspade":  # a big shovel: wooden handle, shiny blade
			pic.draw_line(pic._p(0.7, 0.1 + bob), pic._p(0.45, 0.55 + bob), Color(0.6, 0.4, 0.22), 6.0)
			pic._poly([[0.58, 0.1 + bob], [0.82, 0.1 + bob], [0.82, 0.16 + bob], [0.58, 0.16 + bob]], Color(0.6, 0.4, 0.22))
			pic._poly([[0.3, 0.5 + bob], [0.55, 0.62 + bob], [0.42, 0.92 + bob], [0.18, 0.8 + bob]], Color(0.75, 0.78, 0.85))
			pic._poly([[0.33, 0.55 + bob], [0.48, 0.62 + bob], [0.4, 0.8 + bob]], Color(0.95, 0.97, 1.0))
		"detector":  # a metal detector over the sand, beeping rings
			pic._poly([[0.05, 0.85], [0.95, 0.85], [0.95, 0.95], [0.05, 0.95]], Color(0.95, 0.85, 0.6))
			pic.draw_line(pic._p(0.75, 0.15 + bob), pic._p(0.4, 0.7 + bob), Color(0.5, 0.5, 0.55), 4.0)
			pic._poly([[0.72, 0.12 + bob], [0.86, 0.12 + bob], [0.86, 0.26 + bob], [0.72, 0.26 + bob]], Color(0.25, 0.25, 0.3))
			pic.draw_set_transform(pic._p(0.38, 0.74 + bob), 0.0, Vector2(1.0, 0.35))
			pic.draw_circle(Vector2.ZERO, 0.14 * size.x, Color(0.3, 0.75, 1.0))
			pic.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var k := fmod(t * 1.5, 1.0)
			pic.draw_arc(pic._p(0.38, 0.88), (0.08 + k * 0.2) * size.x, PI, TAU, 16, Color(1.0, 0.9, 0.3, 1.0 - k), 3.0)
			pic._circle(0.38, 0.9, 0.04, Color(1.0, 0.82, 0.2))
		"horseshoe":  # a golden lucky horseshoe
			pic.draw_arc(pic._p(0.5, 0.45 + bob), 0.3 * size.x, PI * 0.95, TAU + PI * 0.05, 24, Color(1.0, 0.8, 0.2), 0.12 * size.x)
			pic.draw_arc(pic._p(0.5, 0.45 + bob), 0.3 * size.x, PI * 0.95, TAU + PI * 0.05, 24, Color(1.0, 0.92, 0.5), 0.03 * size.x)
			for k in 4:
				var a := PI * 1.15 + k * PI * 0.23
				pic._circle(0.5 + cos(a) * 0.3, 0.45 + bob + sin(a) * 0.3, 0.025, Color(0.5, 0.35, 0.1))
			pic._poly([[0.14, 0.5 + bob], [0.26, 0.5 + bob], [0.26, 0.82 + bob], [0.14, 0.82 + bob]], Color(1.0, 0.8, 0.2))
			pic._poly([[0.74, 0.5 + bob], [0.86, 0.5 + bob], [0.86, 0.82 + bob], [0.74, 0.82 + bob]], Color(1.0, 0.8, 0.2))
		"museum":  # Peg's museum: a hut with a red roof and glass cases of treasure
			pic._poly([[0.1, 0.88], [0.9, 0.88], [0.9, 0.96], [0.1, 0.96]], Color(0.95, 0.85, 0.6))
			pic._poly([[0.2, 0.42], [0.8, 0.42], [0.8, 0.88], [0.2, 0.88]], Color(0.85, 0.65, 0.42))
			pic._poly([[0.12, 0.44], [0.5, 0.12 + bob * 0.3], [0.88, 0.44]], Color(0.8, 0.22, 0.2))
			for k in 3:
				var x := 0.27 + k * 0.17
				pic._poly([[x, 0.56], [x + 0.13, 0.56], [x + 0.13, 0.78], [x, 0.78]], Color(0.75, 0.9, 1.0))
				pic._circle(x + 0.065, 0.72, 0.045, [Color(1.0, 0.8, 0.2), Color(0.4, 0.85, 1.0), Color(0.95, 0.3, 0.35)][k])
			pic.draw_line(pic._p(0.5, 0.14), pic._p(0.5, 0.0), Color(0.5, 0.35, 0.2), 2.0)
			pic._poly([[0.5, 0.0], [0.64 + sin(t * 4.0) * 0.02, 0.04], [0.5, 0.08]], Color(0.95, 0.25, 0.2))
		"coconut":  # a coconut falling past a palm leaf
			pic._poly([[0.05, 0.2], [0.45, 0.1], [0.35, 0.25]], Color(0.3, 0.7, 0.3))
			pic._circle(0.55, 0.55 + bob * 2.0, 0.24, Color(0.45, 0.28, 0.15))
			for k in 3:
				pic._circle(0.48 + k * 0.07, 0.42 + bob * 2.0, 0.03, Color(0.2, 0.12, 0.06))
		"tidewave":  # a big blue wave rolling onto the sand
			pic._poly([[0.0, 0.85], [1.0, 0.85], [1.0, 1.0], [0.0, 1.0]], Color(0.95, 0.85, 0.6))
			var x0 := 0.1 + sin(t * 1.5) * 0.05
			pic._poly([[0.0, 0.9], [0.0, 0.35], [x0 + 0.35, 0.2], [x0 + 0.65, 0.35], [x0 + 0.55, 0.5], [x0 + 0.45, 0.42],
				[x0 + 0.5, 0.7], [x0 + 0.8, 0.9]], Color(0.15, 0.4, 0.95))
			pic._poly([[x0 + 0.35, 0.2], [x0 + 0.65, 0.35], [x0 + 0.55, 0.4]], Color(0.9, 0.97, 1.0))
		"goldgem":  # Polly's golden gem with a sparkle
			pic._poly([[0.5, 0.15 + bob], [0.82, 0.42 + bob], [0.5, 0.88 + bob], [0.18, 0.42 + bob]], Color(1.0, 0.75, 0.1))
			pic._poly([[0.5, 0.15 + bob], [0.64, 0.42 + bob], [0.5, 0.88 + bob], [0.36, 0.42 + bob]], Color(1.0, 0.9, 0.45))
			var s := 0.06 + 0.03 * sin(t * 5.0)
			pic._poly([[0.78, 0.18 - s], [0.78 + s * 0.4, 0.18], [0.78, 0.18 + s], [0.78 - s * 0.4, 0.18]], Color(1.0, 1.0, 1.0))
