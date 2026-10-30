extends RefCounted
## Mech Titans' story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["momo"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"momo":  # Momo: the Titans' first kaiju friend, a mint-green baby kaiju with soft back spikes, waving hello
			var skin := Color(0.45, 0.85, 0.6)
			var belly := Color(0.85, 1.0, 0.8)
			pic._poly([[0.3, 0.8 + bob], [0.04, 0.9 + bob], [0.08, 0.8 + bob], [0.28, 0.68 + bob]], skin.darkened(0.15))
			for k in 4:  # back spikes
				var x := 0.24 + k * 0.1
				var y := 0.5 - sin(k * 0.9) * 0.18 + 0.12
				pic._poly([[x - 0.05, y + 0.06 + bob], [x - 0.03, y - 0.08 + bob], [x + 0.05, y + 0.04 + bob]], Color(0.4, 0.6, 1.0))
			pic._circle(0.48, 0.68 + bob, 0.24, skin)
			pic._circle(0.52, 0.72 + bob, 0.15, belly)
			pic._circle(0.58, 0.34 + bob, 0.2, skin)
			pic._eye(0.52, 0.31 + bob, 0.06)
			pic._eye(0.67, 0.31 + bob, 0.06)
			pic.draw_arc(pic._p(0.6, 0.4 + bob), 0.06 * size.x, 0.3, 2.85, 12, Color(0.15, 0.3, 0.2), 0.014 * size.x)
			pic._circle(0.46, 0.4 + bob, 0.03, Color(1.0, 0.55, 0.6, 0.7))
			pic._circle(0.74, 0.4 + bob, 0.03, Color(1.0, 0.55, 0.6, 0.7))
			var wave := sin(t * 7.0) * 0.07
			pic._poly([[0.7, 0.6 + bob], [0.86 + wave * 0.3, 0.42 + bob + wave], [0.9 + wave * 0.3, 0.46 + bob + wave], [0.74, 0.66 + bob]], skin)
			pic._poly([[0.32, 0.62 + bob], [0.24, 0.72 + bob], [0.28, 0.75 + bob], [0.36, 0.68 + bob]], skin)
			for x in [0.38, 0.6]:
				pic._circle(x, 0.9 + bob * 0.5, 0.06, skin.darkened(0.15))
			pic._circle(0.88, 0.16 + bob, 0.035 + 0.01 * sin(t * 5.0), color.lightened(0.3))
