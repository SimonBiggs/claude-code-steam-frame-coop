extends RefCounted
## Bee Garden's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["queenbee", "hive", "honeyjar", "daisy", "lily"]


static func draw(pic, kind: String, t: float, bob: float, _color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"queenbee":  # Queen Bea (Bee Garden): a round fuzzy bee in a little gold crown, wings buzzing
			var flap := absf(sin(t * 18.0)) * 0.06
			pic._circle(0.27, 0.36 + bob - flap, 0.15, Color(0.9, 0.97, 1.0, 0.8))
			pic._circle(0.73, 0.36 + bob - flap, 0.15, Color(0.9, 0.97, 1.0, 0.8))
			pic._circle(0.5, 0.6 + bob, 0.3, Color(1.0, 0.8, 0.15))
			for y in [0.6, 0.76]:
				pic._poly([[0.23, y - 0.035 + bob], [0.77, y - 0.035 + bob], [0.74, y + 0.035 + bob], [0.26, y + 0.035 + bob]], Color(0.2, 0.14, 0.08))
			pic._eye(0.41, 0.48 + bob, 0.06)
			pic._eye(0.59, 0.48 + bob, 0.06)
			pic.draw_arc(pic._p(0.5, 0.52 + bob), 0.07 * size.x, 0.3, PI - 0.3, 10, Color(0.45, 0.2, 0.1), 2.5)
			pic._circle(0.33, 0.55 + bob, 0.035, Color(1.0, 0.55, 0.5, 0.7))
			pic._circle(0.67, 0.55 + bob, 0.035, Color(1.0, 0.55, 0.5, 0.7))
			for sx in [-1.0, 1.0]:
				pic.draw_line(pic._p(0.5 + sx * 0.08, 0.33 + bob), pic._p(0.5 + sx * 0.18, 0.2 + bob), Color(0.2, 0.14, 0.08), 2.0)
				pic._circle(0.5 + sx * 0.18, 0.2 + bob, 0.025, Color(0.2, 0.14, 0.08))
			var gold := Color(1.0, 0.85, 0.2)
			pic._poly([[0.36, 0.33 + bob], [0.64, 0.33 + bob], [0.66, 0.16 + bob], [0.58, 0.24 + bob], [0.5, 0.12 + bob], [0.42, 0.24 + bob], [0.34, 0.16 + bob]], gold)
			pic._circle(0.5, 0.27 + bob, 0.025, Color(1.0, 0.35, 0.45))
		"hive":  # a striped straw skep with a door and two bees
			for k in 5:
				var w := 0.36 - absf(k - 1.5) * 0.04 - (0.08 if k == 0 else 0.0)
				pic._poly([[0.5 - w, 0.28 + k * 0.12], [0.5 + w, 0.28 + k * 0.12], [0.5 + w, 0.4 + k * 0.12], [0.5 - w, 0.4 + k * 0.12]],
					Color(1.0, 0.78, 0.3) if k % 2 == 0 else Color(0.9, 0.62, 0.2))
			pic._circle(0.5, 0.26, 0.16, Color(1.0, 0.78, 0.3))
			pic._circle(0.5, 0.78, 0.08, Color(0.25, 0.15, 0.08))
			for k in 2:
				var a := t * 2.0 + k * PI
				var bx := 0.5 + cos(a) * 0.38
				var by := 0.3 + sin(a) * 0.12
				pic._circle(bx, by, 0.05, Color(1.0, 0.85, 0.15))
				pic._circle(bx, by - 0.04, 0.03, Color(0.9, 0.97, 1.0, 0.8))
		"honeyjar":  # a jar of golden honey with a red lid and a honeycomb label
			pic._poly([[0.26, 0.3 + bob], [0.74, 0.3 + bob], [0.78, 0.9 + bob], [0.22, 0.9 + bob]], Color(1.0, 0.68, 0.1))
			pic._poly([[0.3, 0.34 + bob], [0.38, 0.34 + bob], [0.36, 0.84 + bob], [0.28, 0.84 + bob]], Color(1.0, 0.85, 0.45, 0.8))
			pic._poly([[0.22, 0.18 + bob], [0.78, 0.18 + bob], [0.78, 0.3 + bob], [0.22, 0.3 + bob]], Color(0.9, 0.25, 0.25))
			var hx := []
			for i in 6:
				var a := i * TAU / 6.0
				hx.append([0.52 + cos(a) * 0.11, 0.6 + bob + sin(a) * 0.11])
			pic._poly(hx, Color(1.0, 0.95, 0.75))
			pic._circle(0.52, 0.6 + bob, 0.04, Color(1.0, 0.68, 0.1))
		"daisy", "lily":
			var leaf2 := Color(0.35, 0.75, 0.3)
			pic.draw_line(pic._p(0.5, 0.5), pic._p(0.5, 0.98), leaf2, 0.05 * size.x)
			pic._poly([[0.5, 0.8], [0.72, 0.68], [0.52, 0.86]], leaf2)
			var n := 12 if kind == "daisy" else 6
			var pc := Color(1.0, 0.55, 0.75) if kind == "daisy" else Color(1.0, 0.95, 0.55)
			for i in n:
				var a := i * TAU / n + t * 0.3
				var rr := 0.22 if kind == "daisy" else 0.24
				pic._circle(0.5 + cos(a) * rr, 0.42 + sin(a) * rr + bob, 0.075 if kind == "daisy" else 0.11, pc)
			pic._circle(0.5, 0.42 + bob, 0.12, Color(1.0, 0.85, 0.25) if kind == "daisy" else Color(1.0, 0.6, 0.1))
			if kind == "lily":
				for i in 5:
					var a2 := t * 3.0 + i * TAU / 5.0
					pic._circle(0.5 + cos(a2) * 0.36, 0.42 + sin(a2) * 0.36 + bob, 0.02, Color(1.0, 0.95, 0.5))
