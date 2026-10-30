extends RefCounted
## Dungeon Delve's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["cinder"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"cinder":  # Cinder: a round little orange baby dragon who keeps the dungeon's treasure, puffing smoke rings
			var body := Color(1.0, 0.55, 0.2)
			var belly := Color(1.0, 0.88, 0.6)
			var flap := sin(t * 8.0) * 0.06
			pic._poly([[0.36, 0.5 + bob], [0.12, 0.26 + bob - flap], [0.2, 0.46 + bob], [0.08, 0.5 + bob - flap * 0.5], [0.3, 0.62 + bob]], Color(0.95, 0.35, 0.3))
			pic._poly([[0.3, 0.78 + bob], [0.06, 0.86 + bob], [0.02, 0.76 + bob], [0.26, 0.68 + bob]], body.darkened(0.15))
			pic._poly([[0.02, 0.76 + bob], [0.0, 0.68 + bob], [0.08, 0.74 + bob]], Color(0.95, 0.35, 0.3))
			pic._circle(0.45, 0.66 + bob, 0.22, body)
			pic._circle(0.5, 0.71 + bob, 0.13, belly)
			pic._circle(0.64, 0.4 + bob, 0.19, body)
			pic._circle(0.76, 0.47 + bob, 0.1, body.lightened(0.1))
			pic._circle(0.8, 0.44 + bob, 0.018, Color(0.45, 0.2, 0.1))
			pic._poly([[0.54, 0.26 + bob], [0.5, 0.12 + bob], [0.6, 0.23 + bob]], belly)
			pic._poly([[0.66, 0.23 + bob], [0.68, 0.09 + bob], [0.74, 0.25 + bob]], belly)
			pic._eye(0.66, 0.37 + bob, 0.065)
			pic._circle(0.62, 0.47 + bob, 0.03, Color(1.0, 0.5, 0.55, 0.7))
			pic.draw_arc(pic._p(0.74, 0.5 + bob), 0.05 * size.x, 0.2, 2.6, 10, Color(0.45, 0.2, 0.1), 0.012 * size.x)
			for x in [0.36, 0.54]:
				pic._circle(x, 0.88 + bob * 0.5, 0.055, body.darkened(0.15))
			for k in 2:  # smoke rings drifting up from the nose
				var f := fmod(t * 0.5 + k * 0.5, 1.0)
				pic.draw_arc(pic._p(0.86 + f * 0.08, 0.36 - f * 0.28), (0.03 + f * 0.04) * size.x, 0.0, TAU, 16,
					Color(0.85, 0.85, 0.9, 0.8 * (1.0 - f)), 0.014 * size.x)
			pic._circle(0.2, 0.9, 0.04 + 0.01 * sin(t * 4.0), color.lightened(0.3))
