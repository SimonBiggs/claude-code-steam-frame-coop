extends RefCounted
## Obstacle Rush's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["coach", "balloon", "springshoes", "glidecape", "starmagnet", "swinglog", "risingwater", "medal"]


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
		"springshoes":  # two green shoes on bouncy springs
			var hop := absf(sin(t * 4.0)) * 0.08
			for k in 2:
				var x := 0.3 + k * 0.4
				for c in 4:  # the coil
					var y := 0.86 - c * 0.07
					pic.draw_line(pic._p(x - 0.08, y), pic._p(x + 0.08, y - 0.035), Color(0.8, 0.82, 0.88), 3.0)
				pic._poly([[x - 0.14, 0.62 - hop + bob], [x + 0.16, 0.62 - hop + bob], [x + 0.16, 0.54 - hop + bob], [x + 0.02, 0.46 - hop + bob], [x - 0.14, 0.46 - hop + bob]], Color(0.35, 0.85, 0.45))
				pic._poly([[x - 0.14, 0.62 - hop + bob], [x + 0.16, 0.62 - hop + bob], [x + 0.16, 0.66 - hop + bob], [x - 0.14, 0.66 - hop + bob]], Color(0.95, 0.95, 0.95))
		"glidecape":  # a purple cape floating down
			var flap := sin(t * 3.0) * 0.04
			pic._poly([[0.36, 0.2 + bob], [0.64, 0.2 + bob], [0.82 + flap, 0.82 + bob], [0.5, 0.74 + bob], [0.18 - flap, 0.82 + bob]], Color(0.7, 0.4, 1.0))
			pic._poly([[0.36, 0.2 + bob], [0.64, 0.2 + bob], [0.6, 0.28 + bob], [0.4, 0.28 + bob]], Color(0.5, 0.25, 0.8))
			pic._circle(0.5, 0.24 + bob, 0.04, Color(1.0, 0.85, 0.3))
		"starmagnet":  # a red horseshoe magnet pulling a star
			pic._poly([[0.12, 0.3 + bob], [0.26, 0.3 + bob], [0.26, 0.62 + bob], [0.12, 0.62 + bob]], Color(0.95, 0.3, 0.3))
			pic._poly([[0.12, 0.62 + bob], [0.44, 0.62 + bob], [0.44, 0.76 + bob], [0.12, 0.76 + bob]], Color(0.95, 0.3, 0.3))
			pic._poly([[0.3, 0.3 + bob], [0.44, 0.3 + bob], [0.44, 0.62 + bob], [0.3, 0.62 + bob]], Color(0.95, 0.3, 0.3))
			pic._poly([[0.12, 0.22 + bob], [0.26, 0.22 + bob], [0.26, 0.3 + bob], [0.12, 0.3 + bob]], Color(0.9, 0.92, 0.95))
			pic._poly([[0.3, 0.22 + bob], [0.44, 0.22 + bob], [0.44, 0.3 + bob], [0.3, 0.3 + bob]], Color(0.9, 0.92, 0.95))
			var sx := 0.74 - fposmod(t * 0.15, 0.12)
			var pts := []
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				var rr := 0.14 if i % 2 == 0 else 0.06
				pts.append([sx + cos(a) * rr, 0.42 + bob + sin(a) * rr])
			pic._poly(pts, Color(1.0, 0.86, 0.25))
		"swinglog":  # a log swinging on two ropes
			var sw := sin(t * 2.0) * 0.12
			pic.draw_line(pic._p(0.1, 0.1), pic._p(0.9, 0.1), Color(0.55, 0.35, 0.2), 4.0)
			pic.draw_line(pic._p(0.3, 0.1), pic._p(0.3 + sw, 0.62), Color(0.95, 0.9, 0.75), 2.0)
			pic.draw_line(pic._p(0.7, 0.1), pic._p(0.7 + sw, 0.62), Color(0.95, 0.9, 0.75), 2.0)
			pic._poly([[0.16 + sw, 0.58], [0.84 + sw, 0.58], [0.84 + sw, 0.76], [0.16 + sw, 0.76]], Color(0.62, 0.4, 0.22))
			pic._circle(0.84 + sw, 0.67, 0.09, Color(0.9, 0.75, 0.5))
			pic._circle(0.84 + sw, 0.67, 0.04, Color(0.62, 0.4, 0.22))
		"risingwater":  # blue water rising with a splash
			var lv := 0.62 - (0.5 + 0.5 * sin(t * 1.5)) * 0.12
			var wv := []
			wv.append([0.05, 0.92])
			for i in 9:
				var x := 0.05 + i * 0.1125
				wv.append([x, lv + sin(t * 4.0 + i) * 0.025])
			wv.append([0.95, 0.92])
			pic._poly(wv, Color(0.2, 0.45, 1.0))
			pic._circle(0.32, lv - 0.12 + bob, 0.04, Color(0.6, 0.8, 1.0))
			pic._circle(0.62, lv - 0.18 + bob, 0.05, Color(0.6, 0.8, 1.0))
			pic.draw_line(pic._p(0.5, 0.2), pic._p(0.5, 0.38), Color(1, 1, 1), 3.0)
			pic._poly([[0.42, 0.32], [0.58, 0.32], [0.5, 0.42]], Color(1, 1, 1))
		"medal":  # a gold medal on a ribbon
			var sway := sin(t * 2.0) * 0.03
			pic._poly([[0.32, 0.08], [0.44, 0.08], [0.56 + sway, 0.5 + bob], [0.46 + sway, 0.52 + bob]], Color(0.3, 0.55, 1.0))
			pic._poly([[0.56, 0.08], [0.68, 0.08], [0.54 + sway, 0.52 + bob], [0.44 + sway, 0.5 + bob]], Color(0.95, 0.3, 0.35))
			pic._circle(0.5 + sway, 0.68 + bob, 0.2, Color(1.0, 0.8, 0.25))
			pic._circle(0.5 + sway, 0.68 + bob, 0.14, Color(1.0, 0.9, 0.5))
			var sp := []
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				var rr := 0.1 if i % 2 == 0 else 0.045
				sp.append([0.5 + sway + cos(a) * rr, 0.68 + bob + sin(a) * rr])
			pic._poly(sp, Color(1.0, 0.75, 0.15))
