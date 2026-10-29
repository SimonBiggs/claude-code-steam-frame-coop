extends RefCounted
## Obstacle Rush's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["coach", "balloon"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"coach":  # Coach Jelly (Obstacle Rush): an orange jelly bean in a blue cap, with a whistle
			var bean := Color(1.0, 0.55, 0.25)
			var pts := []
			for i in 24:
				var a := TAU * float(i) / 24.0
				pts.append([0.5 + cos(a) * 0.28, 0.58 + bob + sin(a) * (0.36 if sin(a) > 0.0 else 0.3)])
			pic._poly(pts, bean)
			pic._circle(0.5, 0.7 + bob, 0.15, bean.lightened(0.4))
			pic._eye(0.42, 0.46 + bob, 0.065)
			pic._eye(0.58, 0.46 + bob, 0.065)
			pic._circle(0.36, 0.56 + bob, 0.035, Color(1.0, 0.55, 0.6))
			pic._circle(0.64, 0.56 + bob, 0.035, Color(1.0, 0.55, 0.6))
			pic._poly([[0.24, 0.32 + bob], [0.76, 0.32 + bob], [0.7, 0.18 + bob], [0.3, 0.18 + bob]], Color(0.25, 0.45, 0.95))
			pic._poly([[0.66, 0.32 + bob], [0.92, 0.33 + bob], [0.72, 0.27 + bob]], Color(0.2, 0.35, 0.8))
			pic.draw_line(pic._p(0.4, 0.3 + bob), pic._p(0.5, 0.62 + bob), Color(0.95, 0.3, 0.35), 2.0)
			var toot := 0.02 * sin(t * 12.0)
			pic._poly([[0.5, 0.6 + bob], [0.66 + toot, 0.6 + bob], [0.66 + toot, 0.66 + bob], [0.5, 0.66 + bob]], Color(0.8, 0.82, 0.88))
			pic._circle(0.5, 0.63 + bob, 0.04, Color(0.8, 0.82, 0.88))
		"balloon":
			var sway := sin(t * 2.0) * 0.03
			pic.draw_line(pic._p(0.5 + sway, 0.62 + bob), pic._p(0.5, 0.95), Color(0.9, 0.9, 0.95), 2.0)
			var bl := []
			for i in 20:
				var a := TAU * float(i) / 20.0
				bl.append([0.5 + sway + cos(a) * 0.24, 0.36 + bob + sin(a) * 0.29])
			pic._poly(bl, color)
			pic._circle(0.42 + sway, 0.26 + bob, 0.06, color.lightened(0.5))
			pic._poly([[0.46 + sway, 0.67 + bob], [0.54 + sway, 0.67 + bob], [0.5 + sway, 0.62 + bob]], color.darkened(0.2))
