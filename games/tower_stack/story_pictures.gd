extends RefCounted
## Tower Stack's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["wren", "tower", "bouncyblock", "honeyblock", "balloonblock", "lighthouse", "clocktower",
	"birdnest", "gust", "quake"]


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
		"bouncyblock", "honeyblock", "balloonblock":  # the special blocks: a smiley jelly block with its own trick
			var hop := absf(sin(t * 4.0)) * 0.12 if kind == "bouncyblock" else 0.0
			var col := {"bouncyblock": Color(1.0, 0.4, 0.85), "honeyblock": Color(1.0, 0.72, 0.12), "balloonblock": Color(0.25, 0.85, 0.75)}[kind] as Color  # (== looks.gd SPECIAL_COLORS)
			var y0 := 0.42 - hop + bob
			if kind == "balloonblock":
				y0 = 0.5 + bob
				for sx in [0.22, 0.78]:
					pic.draw_line(pic._p(sx, y0 - 0.17), pic._p(sx + (0.06 if sx > 0.5 else -0.06), y0 + 0.08), Color(0.95, 0.95, 0.95), 0.012 * size.x)
					pic._circle(sx, y0 - 0.27 + sin(t * 2.0 + sx * 5.0) * 0.02, 0.12, Color(1.0, 0.3, 0.35) if sx < 0.5 else Color(1.0, 0.85, 0.25))
			pic._poly([[0.22, y0], [0.78, y0], [0.78, y0 + 0.48], [0.22, y0 + 0.48]], col)
			pic._eye(0.4, y0 + 0.18, 0.06)
			pic._eye(0.6, y0 + 0.18, 0.06)
			pic.draw_arc(pic._p(0.5, y0 + 0.28), 0.09 * size.x, 0.2, PI - 0.2, 10, col.darkened(0.55), 0.02 * size.x)
			match kind:
				"bouncyblock":
					for k in 3:  # the spring under it
						var yy := y0 + 0.5 + k * (0.1 + hop * 0.3)
						pic.draw_line(pic._p(0.3, yy), pic._p(0.7, yy + 0.05), Color(1, 1, 1), 0.025 * size.x)
				"honeyblock":
					var honey := Color(1.0, 0.58, 0.05)
					pic._poly([[0.2, y0 - 0.02], [0.8, y0 - 0.02], [0.8, y0 + 0.06], [0.2, y0 + 0.06]], honey)
					for d in [[0.3, 0.12], [0.55, 0.2], [0.7, 0.1]]:
						var drip: float = d[1] + sin(t * 2.0 + d[0] * 9.0) * 0.03
						pic._poly([[d[0] - 0.03, y0 + 0.04], [d[0] + 0.03, y0 + 0.04], [d[0] + 0.02, y0 + 0.04 + drip], [d[0] - 0.02, y0 + 0.04 + drip]], honey)
						pic._circle(d[0], y0 + 0.04 + drip, 0.03, honey)
		"lighthouse":  # a red and white striped lighthouse with a glowing lamp
			for k in 4:
				var y0 := 0.9 - 0.15 * (k + 1)
				pic._poly([[0.38 + 0.015 * k, y0], [0.62 - 0.015 * k, y0], [0.62 - 0.015 * (k - 1), y0 + 0.15], [0.38 + 0.015 * (k - 1), y0 + 0.15]],
					Color(0.9, 0.25, 0.25) if k % 2 == 0 else Color(1, 1, 1))
			pic._poly([[0.42, 0.22], [0.58, 0.22], [0.58, 0.3], [0.42, 0.3]], Color(1.0, 0.92, 0.4 + 0.3 * absf(sin(t * 3.0))))
			pic._poly([[0.38, 0.22], [0.62, 0.22], [0.5, 0.1]], Color(0.25, 0.3, 0.45))
			pic._poly([[0.58, 0.24], [0.95, 0.16 + sin(t) * 0.04], [0.95, 0.34 + sin(t) * 0.04]], Color(1.0, 0.95, 0.5, 0.4))
			pic._poly([[0.1, 0.9], [0.9, 0.9], [0.9, 0.97], [0.1, 0.97]], Color(0.3, 0.55, 0.95))
		"clocktower":  # a tall tower with a big clock face and a pointy roof
			pic._poly([[0.35, 0.3], [0.65, 0.3], [0.65, 0.95], [0.35, 0.95]], color.lightened(0.2))
			pic._poly([[0.3, 0.32], [0.7, 0.32], [0.5, 0.06]], Color(0.35, 0.45, 0.85))
			pic._circle(0.5, 0.5, 0.12, Color(1, 1, 0.95))
			var a := t * 1.5
			pic.draw_line(pic._p(0.5, 0.5), pic._p(0.5 + cos(a) * 0.09, 0.5 + sin(a) * 0.09), Color(0.1, 0.1, 0.15), 0.02 * size.x)
			pic.draw_line(pic._p(0.5, 0.5), pic._p(0.5, 0.42), Color(0.1, 0.1, 0.15), 0.025 * size.x)
			pic._poly([[0.45, 0.8], [0.55, 0.8], [0.55, 0.95], [0.45, 0.95]], Color(0.45, 0.3, 0.2))
		"birdnest":  # a twiggy nest on a branch with three blue eggs
			pic.draw_line(pic._p(0.05, 0.8), pic._p(0.95, 0.72), Color(0.45, 0.3, 0.2), 0.05 * size.x)
			for k in 3:
				pic._circle(0.38 + 0.12 * k, 0.5 + bob - (0.04 if k == 1 else 0.0), 0.09, Color(0.7, 0.88, 1.0))
			pic._poly([[0.2, 0.52], [0.8, 0.52], [0.7, 0.72], [0.3, 0.72]], Color(0.6, 0.42, 0.25))
			for k in 4:
				pic.draw_line(pic._p(0.22 + 0.04 * k, 0.56 + 0.04 * k), pic._p(0.78 - 0.04 * k, 0.58 + 0.04 * k), Color(0.45, 0.3, 0.18), 0.012 * size.x)
		"gust":  # a puffy cloud blowing hard: swooshy lines
			pic._circle(0.3, 0.42, 0.16, Color(0.92, 0.95, 1.0))
			pic._circle(0.45, 0.35, 0.18, Color(0.92, 0.95, 1.0))
			pic._circle(0.25, 0.52, 0.12, Color(0.92, 0.95, 1.0))
			pic._eye(0.38, 0.4, 0.04)
			pic._circle(0.56, 0.44, 0.05, Color(0.3, 0.3, 0.4))  # blowing mouth
			for k in 3:
				var x0 := 0.62 + fmod(t * 0.6 + k * 0.33, 1.0) * 0.12
				pic.draw_line(pic._p(x0, 0.36 + k * 0.1), pic._p(x0 + 0.28, 0.34 + k * 0.1), color.lightened(0.3), 0.03 * size.x)
		"quake":  # the round stage shaking: wiggle lines and a jumping block
			var sh := sin(t * 30.0) * 0.02
			pic._poly([[0.12 + sh, 0.78], [0.88 + sh, 0.78], [0.84 + sh, 0.88], [0.16 + sh, 0.88]], Color(0.75, 0.6, 0.45))
			pic._poly([[0.38 - sh, 0.42], [0.62 - sh, 0.42], [0.62 - sh, 0.72], [0.38 - sh, 0.72]], color)
			pic._eye(0.45 - sh, 0.53, 0.035)
			pic._eye(0.55 - sh, 0.53, 0.035)
			for side in [-1.0, 1.0]:
				for k in 2:
					var x: float = 0.5 + side * (0.22 + 0.08 * k)
					pic.draw_line(pic._p(x, 0.45), pic._p(x + side * 0.03, 0.55), Color(0.4, 0.3, 0.25), 0.02 * size.x)
					pic.draw_line(pic._p(x + side * 0.03, 0.55), pic._p(x, 0.65), Color(0.4, 0.3, 0.25), 0.02 * size.x)
