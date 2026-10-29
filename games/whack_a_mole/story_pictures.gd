extends RefCounted
## Whack A Mole's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["farmer", "mole", "bunny", "lettuce", "carrot", "pumpkin", "sunflower", "strawberry", "corn", "melon", "apple"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"farmer":  # Farmer Fig (Whack-a-Mole): a round face under a big straw hat, a sprig on top
			pic._circle(0.5, 0.6 + bob, 0.26, Color(0.98, 0.78, 0.6))
			pic._poly([[0.08, 0.42 + bob], [0.92, 0.42 + bob], [0.8, 0.36 + bob], [0.2, 0.36 + bob]], Color(0.95, 0.8, 0.35))
			pic._poly([[0.28, 0.37 + bob], [0.72, 0.37 + bob], [0.66, 0.16 + bob], [0.34, 0.16 + bob]], Color(0.95, 0.8, 0.35))
			pic._poly([[0.28, 0.33 + bob], [0.72, 0.33 + bob], [0.71, 0.28 + bob], [0.29, 0.28 + bob]], color)
			pic._eye(0.41, 0.58 + bob, 0.05)
			pic._eye(0.59, 0.58 + bob, 0.05)
			pic.draw_arc(pic._p(0.5, 0.66 + bob), 0.09 * size.x, 0.3, PI - 0.3, 10, Color(0.4, 0.15, 0.12), 0.022 * size.x)
			pic._circle(0.33, 0.68 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
			pic._circle(0.67, 0.68 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
			pic.draw_line(pic._p(0.62, 0.17 + bob), pic._p(0.7, 0.04 + bob), Color(0.3, 0.6, 0.25), 0.025 * size.x)
			pic._circle(0.72, 0.05 + bob, 0.04, Color(0.4, 0.8, 0.3))
		"mole", "bunny":  # a cheeky mole (fur = color) or a white bunny peeking from a hole
			pic._poly([[0.12, 0.82], [0.88, 0.82], [0.8, 0.94], [0.2, 0.94]], Color(0.35, 0.22, 0.12))
			var fur := color if kind == "mole" else Color(0.97, 0.97, 1.0)
			if kind == "bunny":
				for x in [0.38, 0.62]:
					pic._poly([[x - 0.06, 0.35 + bob], [x, 0.02 + bob], [x + 0.06, 0.35 + bob]], fur)
					pic._poly([[x - 0.03, 0.33 + bob], [x, 0.1 + bob], [x + 0.03, 0.33 + bob]], Color(1.0, 0.7, 0.78))
			pic._circle(0.5, 0.58 + bob, 0.27, fur)
			pic._poly([[0.23, 0.6 + bob], [0.77, 0.6 + bob], [0.77, 0.85], [0.23, 0.85]], fur)
			pic._circle(0.5, 0.68 + bob, 0.14, fur.lightened(0.35))
			pic._eye(0.41, 0.5 + bob, 0.055)
			pic._eye(0.59, 0.5 + bob, 0.055)
			pic._circle(0.5, 0.6 + bob, 0.05, Color(1.0, 0.55, 0.65))
			if kind == "mole":
				pic._poly([[0.46, 0.66 + bob], [0.54, 0.66 + bob], [0.54, 0.71 + bob], [0.46, 0.71 + bob]], white)
		"lettuce", "carrot", "pumpkin", "sunflower", "strawberry", "corn", "melon", "apple":
			_veg(pic, kind, t, bob, color)


## Farmer Fig's crops (Whack-a-Mole garden beds).
static func _veg(pic, v: String, t: float, bob: float, _color: Color) -> void:
	var size: Vector2 = pic.size
	var leaf := Color(0.35, 0.75, 0.3)
	match v:
		"lettuce":
			for b in [[0.32, 0.6, 0.2], [0.68, 0.6, 0.2], [0.5, 0.5, 0.24], [0.5, 0.68, 0.2]]:
				pic._circle(b[0], b[1] + bob, b[2], Color(0.45, 0.85, 0.35).darkened(0.1 * b[2]))
			pic._circle(0.5, 0.56 + bob, 0.12, Color(0.75, 0.95, 0.5))
		"carrot":
			pic._poly([[0.36, 0.3 + bob], [0.64, 0.3 + bob], [0.5, 0.95 + bob]], Color(1.0, 0.55, 0.15))
			for a in [-0.12, 0.0, 0.12]:
				pic._poly([[0.47, 0.3 + bob], [0.53, 0.3 + bob], [0.5 + a, 0.06 + bob]], leaf)
		"pumpkin":
			for b in [[0.3, 0.2], [0.7, 0.2], [0.5, 0.25]]:
				pic._circle(b[0], 0.6 + bob, b[1], Color(1.0, 0.5, 0.1).lightened(0.1 if b[0] == 0.5 else 0.0))
			pic._poly([[0.46, 0.38 + bob], [0.54, 0.38 + bob], [0.56, 0.24 + bob], [0.5, 0.24 + bob]], Color(0.4, 0.55, 0.2))
		"sunflower":
			pic.draw_line(pic._p(0.5, 0.55), pic._p(0.5, 0.98), leaf, 0.05 * size.x)
			for i in 10:
				var a := i * TAU / 10.0 + t * 0.4
				pic._circle(0.5 + cos(a) * 0.2, 0.4 + sin(a) * 0.2 + bob, 0.09, Color(1.0, 0.85, 0.2))
			pic._circle(0.5, 0.4 + bob, 0.14, Color(0.5, 0.3, 0.12))
		"strawberry":
			pic._poly([[0.22, 0.4 + bob], [0.78, 0.4 + bob], [0.72, 0.6 + bob], [0.5, 0.92 + bob], [0.28, 0.6 + bob]], Color(0.95, 0.2, 0.3))
			for p in [[0.38, 0.5], [0.6, 0.5], [0.5, 0.62], [0.42, 0.74], [0.58, 0.72]]:
				pic._circle(p[0], p[1] + bob, 0.018, Color(1.0, 0.9, 0.5))
			pic._poly([[0.3, 0.4 + bob], [0.5, 0.28 + bob], [0.7, 0.4 + bob], [0.5, 0.46 + bob]], leaf)
		"corn":
			pic._poly([[0.38, 0.2 + bob], [0.62, 0.2 + bob], [0.64, 0.75 + bob], [0.36, 0.75 + bob]], Color(1.0, 0.88, 0.3))
			for y in 5:
				for x in 2:
					pic._circle(0.45 + x * 0.1, 0.27 + y * 0.1 + bob, 0.035, Color(1.0, 0.95, 0.5))
			pic._poly([[0.36, 0.95 + bob], [0.28, 0.4 + bob], [0.46, 0.75 + bob]], leaf)
			pic._poly([[0.64, 0.95 + bob], [0.72, 0.4 + bob], [0.54, 0.75 + bob]], leaf)
		"melon":
			pic._circle(0.5, 0.58 + bob, 0.34, Color(0.3, 0.65, 0.3))
			for x in [-0.2, 0.0, 0.2]:
				pic.draw_line(pic._p(0.5 + x * 0.6, 0.26 + bob), pic._p(0.5 + x, 0.58 + bob), Color(0.55, 0.85, 0.45), 0.03 * size.x)
				pic.draw_line(pic._p(0.5 + x, 0.58 + bob), pic._p(0.5 + x * 0.6, 0.9 + bob), Color(0.55, 0.85, 0.45), 0.03 * size.x)
		"apple":
			pic._circle(0.39, 0.6 + bob, 0.24, Color(0.9, 0.15, 0.2))
			pic._circle(0.61, 0.6 + bob, 0.24, Color(0.9, 0.15, 0.2))
			pic._circle(0.38, 0.52 + bob, 0.07, Color(1.0, 0.5, 0.5, 0.7))
			pic.draw_line(pic._p(0.5, 0.4 + bob), pic._p(0.54, 0.22 + bob), Color(0.45, 0.28, 0.15), 0.03 * size.x)
			pic._poly([[0.54, 0.28 + bob], [0.72, 0.2 + bob], [0.6, 0.34 + bob]], leaf)
