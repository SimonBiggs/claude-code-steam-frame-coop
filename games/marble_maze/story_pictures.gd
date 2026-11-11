extends RefCounted
## Marble Maze's story card pictures (Bobo's gift marbles, worlds.gd MARBLES). core/story_pictures.gd finds this file
## by itself. Drawn in a unit box: pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) /
## pic.draw_*(...), size = pic.size, t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["heavymarble", "bouncymarble", "magnetmarble", "stickymarble", "zoomymarble"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var cols := {"heavymarble": Color(0.62, 0.68, 0.8), "bouncymarble": Color(1.0, 0.45, 0.8), "magnetmarble": Color(1.0, 0.3, 0.3),
		"stickymarble": Color(0.55, 0.95, 0.3), "zoomymarble": Color(1.0, 0.75, 0.15)}
	var c: Color = cols.get(kind, color)
	var x := 0.5
	var y := 0.55 + bob
	var r := 0.27
	match kind:
		"heavymarble":
			y = 0.6
			pic._poly([[0.12, 0.9], [0.88, 0.9], [0.88, 0.95], [0.12, 0.95]], Color(0.45, 0.35, 0.25))
			for i in 3:  # thud lines
				var lx := 0.2 + i * 0.3
				pic.draw_line(pic._p(lx - 0.04, 0.84), pic._p(lx + 0.04, 0.78), Color(0.3, 0.3, 0.35), 0.02 * size.x)
		"bouncymarble":
			var h := absf(sin(t * 3.0))
			y = 0.72 - h * 0.3
			pic.draw_arc(pic._p(0.5, 0.95), 0.22 * size.x, PI, TAU, 16, Color(1.0, 0.75, 0.9), 0.02 * size.x)
		"magnetmarble":
			x = 0.62
			# A red / silver horseshoe magnet on the left, pulling.
			pic.draw_arc(pic._p(0.2, 0.55), 0.13 * size.x, PI * 0.5, PI * 1.5, 16, Color(0.9, 0.15, 0.15), 0.07 * size.x)
			pic._poly([[0.19, 0.38], [0.29, 0.38], [0.29, 0.46], [0.19, 0.46]], Color(0.85, 0.85, 0.9))
			pic._poly([[0.19, 0.64], [0.29, 0.64], [0.29, 0.72], [0.19, 0.72]], Color(0.85, 0.85, 0.9))
			for i in 3:
				var a := fmod(t * 0.8 + i / 3.0, 1.0)
				pic.draw_arc(pic._p(0.33 + a * 0.05, 0.55), (0.04 + a * 0.06) * size.x, -0.8, 0.8, 8, Color(1.0, 0.9, 0.3, 1.0 - a), 0.012 * size.x)
		"stickymarble":
			for i in 3:  # drips
				var dx := 0.38 + i * 0.12
				var dl := 0.08 + 0.04 * sin(t * 2.0 + i)
				pic._poly([[dx - 0.025, y + 0.18], [dx + 0.025, y + 0.18], [dx + 0.02, y + 0.24 + dl], [dx - 0.02, y + 0.24 + dl]], c.darkened(0.15))
				pic._circle(dx, y + 0.24 + dl, 0.03, c.darkened(0.15))
		"zoomymarble":
			x = 0.58
			for i in 3:  # speed lines
				var ly := y - 0.14 + i * 0.14
				var off := fmod(t * 2.0 + i * 0.3, 1.0) * 0.06
				pic.draw_line(pic._p(0.08 + off, ly), pic._p(0.3 + off, ly), Color(1.0, 1.0, 1.0, 0.85), 0.025 * size.x)
	pic._circle(x, y, r, c)
	pic._circle(x - r * 0.35, y - r * 0.38, r * 0.28, c.lightened(0.55))  # shine
	if kind == "heavymarble":
		pic._poly([[x - r, y - 0.03], [x + r, y - 0.03], [x + r * 0.97, y + 0.04], [x - r * 0.97, y + 0.04]], c.darkened(0.35))
	pic._eye(x - 0.08, y + 0.02, 0.045)
	pic._eye(x + 0.08, y + 0.02, 0.045)
	pic.draw_arc(pic._p(x, y + 0.1), 0.06 * size.x, 0.3, PI - 0.3, 10, Color(0.3, 0.1, 0.12), 0.02 * size.x)
