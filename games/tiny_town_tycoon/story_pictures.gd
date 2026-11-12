extends RefCounted
## Tiny Town Tycoon's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["beaver", "island", "boat", "crane", "twinhouses", "happypark", "sleepyfog"]


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
		"crane":  # SPEEDY CRANE: a yellow crane truck lifting a brick, speed lines behind it
			var yel := Color(1.0, 0.8, 0.15)
			pic._poly([[0.0, 0.92], [1.0, 0.92], [1.0, 1.0], [0.0, 1.0]], Color(0.45, 0.45, 0.5))
			pic._poly([[0.25, 0.7], [0.8, 0.7], [0.8, 0.86], [0.25, 0.86]], yel)
			pic._poly([[0.62, 0.58], [0.8, 0.58], [0.8, 0.7], [0.62, 0.7]], yel.darkened(0.1))
			pic._poly([[0.65, 0.6], [0.77, 0.6], [0.77, 0.67], [0.65, 0.67]], Color(0.7, 0.9, 1.0))
			pic._circle(0.34, 0.88, 0.065, Color(0.2, 0.2, 0.22))
			pic._circle(0.7, 0.88, 0.065, Color(0.2, 0.2, 0.22))
			pic.draw_line(pic._p(0.4, 0.7), pic._p(0.2, 0.18 + bob), yel.darkened(0.2), 0.05 * size.x)
			pic.draw_line(pic._p(0.2, 0.18 + bob), pic._p(0.2, 0.36 + bob), Color(0.3, 0.3, 0.3), 0.012 * size.x)
			pic._poly([[0.12, 0.36 + bob], [0.28, 0.36 + bob], [0.28, 0.46 + bob], [0.12, 0.46 + bob]], Color(0.85, 0.42, 0.32))
			for k in 3:
				var ly := 0.72 + k * 0.06
				pic.draw_line(pic._p(0.86 + fmod(t * 0.3, 0.06), ly), pic._p(0.98, ly), white, 0.02 * size.x)
		"twinhouses":  # DOUBLE HOUSES: two little houses side by side, a sparkle between them
			pic._poly([[0.0, 0.88], [1.0, 0.88], [1.0, 1.0], [0.0, 1.0]], Color(0.45, 0.76, 0.34))
			for k in 2:
				var x0 := 0.08 + k * 0.48
				var wall := Color(1.0, 0.92, 0.75) if k == 0 else Color(0.85, 0.92, 1.0)
				pic._poly([[x0, 0.55], [x0 + 0.36, 0.55], [x0 + 0.36, 0.88], [x0, 0.88]], wall)
				pic._poly([[x0 - 0.04, 0.56], [x0 + 0.18, 0.34 + bob * (1 - 2 * k)], [x0 + 0.4, 0.56]], Color(0.9, 0.35, 0.3))
				pic._poly([[x0 + 0.13, 0.7], [x0 + 0.23, 0.7], [x0 + 0.23, 0.88], [x0 + 0.13, 0.88]], Color(0.55, 0.35, 0.2))
			pic._circle(0.5, 0.2 + bob, 0.05, Color(1.0, 0.9, 0.3))
			pic._poly([[0.5, 0.08 + bob], [0.53, 0.2 + bob], [0.5, 0.32 + bob], [0.47, 0.2 + bob]], Color(1.0, 0.95, 0.5))
		"happypark":  # HAPPY PARK: a round tree, a bench and three balloons
			pic._poly([[0.0, 0.84], [1.0, 0.84], [1.0, 1.0], [0.0, 1.0]], Color(0.45, 0.76, 0.34))
			pic._poly([[0.27, 0.55], [0.33, 0.55], [0.33, 0.86], [0.27, 0.86]], Color(0.55, 0.38, 0.22))
			pic._circle(0.3, 0.45, 0.18, Color(0.3, 0.68, 0.3))
			pic._poly([[0.52, 0.74], [0.82, 0.74], [0.82, 0.78], [0.52, 0.78]], Color(0.7, 0.45, 0.25))
			pic._poly([[0.54, 0.78], [0.57, 0.78], [0.57, 0.86], [0.54, 0.86]], Color(0.5, 0.32, 0.18))
			pic._poly([[0.77, 0.78], [0.8, 0.78], [0.8, 0.86], [0.77, 0.86]], Color(0.5, 0.32, 0.18))
			var bcols: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.25), Color(0.4, 0.75, 1.0)]
			for k in 3:
				var bx := 0.6 + k * 0.12
				var by := 0.22 + (k % 2) * 0.08 + bob
				pic.draw_line(pic._p(bx, by + 0.08), pic._p(0.68, 0.72), Color(0.95, 0.95, 0.95), 1.5)
				pic._circle(bx, by, 0.07, bcols[k])
		"sleepyfog":  # SLEEPY FOG: a soft lilac cloud low over the grass with sleepy Zs
			pic._poly([[0.0, 0.84], [1.0, 0.84], [1.0, 1.0], [0.0, 1.0]], Color(0.45, 0.76, 0.34))
			var fog := Color(0.86, 0.82, 1.0)
			for k in 5:
				pic._circle(0.14 + k * 0.18, 0.7 + (k % 2) * 0.04, 0.14, fog.darkened(0.04 * (k % 2)))
			pic._poly([[0.05, 0.7], [0.95, 0.7], [0.95, 0.86], [0.05, 0.86]], fog)
			pic._eye(0.4, 0.68, 0.04)
			pic._eye(0.6, 0.68, 0.04)
			for k in 3:
				var zx := 0.6 + k * 0.1
				var zy := 0.42 - k * 0.12 + bob
				var zs := 0.035 + k * 0.012
				pic.draw_polyline(PackedVector2Array([pic._p(zx, zy), pic._p(zx + zs, zy), pic._p(zx, zy + zs), pic._p(zx + zs, zy + zs)]),
					Color(0.62, 0.38, 1.0), 0.012 * size.x)
