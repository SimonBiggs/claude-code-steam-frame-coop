extends RefCounted
## Party Board's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["toucan"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"toucan":  # Mango (Party Board): a black toucan with a huge orange beak and a party hat
			pic._circle(0.42, 0.6 + bob, 0.27, Color(0.12, 0.12, 0.16))
			pic._circle(0.42, 0.68 + bob, 0.15, Color(1.0, 0.95, 0.8))
			pic._poly([[0.52, 0.42 + bob], [0.98, 0.5 + bob], [0.9, 0.6 + bob], [0.55, 0.6 + bob]], Color(1.0, 0.6, 0.15))
			pic._poly([[0.52, 0.42 + bob], [0.98, 0.5 + bob], [0.75, 0.47 + bob]], Color(1.0, 0.85, 0.25))
			pic._circle(0.97, 0.53 + bob, 0.03, Color(0.15, 0.1, 0.1))
			pic._circle(0.46, 0.42 + bob, 0.08, Color(0.45, 0.8, 1.0))
			pic._eye(0.47, 0.42 + bob, 0.045)
			pic._poly([[0.26, 0.32 + bob], [0.46, 0.32 + bob], [0.34, 0.06 + bob]], color)
			pic._circle(0.34, 0.06 + bob, 0.04, white)
			var flap := sin(t * 6.0) * 0.05
			pic._poly([[0.22, 0.58 + bob], [0.08, 0.72 + bob - flap], [0.3, 0.78 + bob]], Color(0.2, 0.2, 0.26))
