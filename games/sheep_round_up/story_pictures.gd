extends RefCounted
## Sheep Round Up's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["shepherd", "sheep"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"shepherd":  # Bo (Sheep Round-Up): a round face under a bonnet (color) with a bow, curls and a crook
			pic.draw_arc(pic._p(0.84, 0.22 + bob), 0.08 * size.x, PI, TAU, 10, Color(0.55, 0.36, 0.2), 0.035 * size.x)
			pic.draw_line(pic._p(0.92, 0.22 + bob), pic._p(0.92, 0.95), Color(0.55, 0.36, 0.2), 0.035 * size.x)
			for cx in [0.26, 0.74, 0.3, 0.7]:
				pic._circle(cx, 0.68 + bob if cx < 0.28 or cx > 0.72 else 0.76 + bob, 0.07, Color(0.95, 0.75, 0.35))
			pic._circle(0.5, 0.6 + bob, 0.25, Color(0.98, 0.8, 0.64))
			var bon := []
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				bon.append([0.5 + cos(a) * 0.34, 0.52 + bob + sin(a) * 0.34])
			pic._poly(bon, color)
			pic._poly([[0.16, 0.52 + bob], [0.84, 0.52 + bob], [0.8, 0.46 + bob], [0.2, 0.46 + bob]], color.lightened(0.3))
			pic._poly([[0.22, 0.6 + bob], [0.12, 0.7 + bob], [0.18, 0.74 + bob]], color.lightened(0.15))
			pic._eye(0.41, 0.6 + bob, 0.05)
			pic._eye(0.59, 0.6 + bob, 0.05)
			pic.draw_arc(pic._p(0.5, 0.68 + bob), 0.08 * size.x, 0.3, PI - 0.3, 10, Color(0.4, 0.15, 0.12), 0.022 * size.x)
			pic._circle(0.34, 0.7 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
			pic._circle(0.66, 0.7 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
		"sheep":  # a fluffy sheep (wool = color) with a dark face, hopping
			var hop := absf(sin(t * 4.0)) * 0.03
			for leg in [0.32, 0.44, 0.58, 0.7]:
				pic.draw_line(pic._p(leg, 0.7 - hop), pic._p(leg, 0.9 - hop), Color(0.2, 0.18, 0.2), 0.05 * size.x)
			for b in [[0.36, 0.5, 0.15], [0.52, 0.45, 0.17], [0.66, 0.52, 0.15], [0.45, 0.62, 0.15], [0.62, 0.64, 0.14], [0.3, 0.62, 0.12]]:
				pic._circle(b[0], b[1] - hop, b[2], color)
			var face := Color(0.22, 0.2, 0.24) if color.get_luminance() > 0.4 else Color(0.08, 0.08, 0.1)
			pic._circle(0.22, 0.48 - hop, 0.12, face)
			pic._poly([[0.12, 0.4 - hop], [0.02, 0.44 - hop], [0.12, 0.47 - hop]], face)
			pic._eye(0.19, 0.45 - hop, 0.04)
			pic._circle(0.25, 0.37 - hop, 0.06, color)
