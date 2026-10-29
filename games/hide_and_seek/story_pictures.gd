extends RefCounted
## Hide And Seek's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["puppy"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"puppy":  # Pip (Hide and Seek): a round puppy face (fur = color), floppy brown ears, a pink tongue
			var ear := Color(0.38, 0.24, 0.16)
			var wag := sin(t * 5.0) * 0.03
			pic._poly([[0.22, 0.3 + bob], [0.34, 0.26 + bob], [0.3, 0.62 + bob + wag], [0.16, 0.58 + bob + wag]], ear)
			pic._poly([[0.78, 0.3 + bob], [0.66, 0.26 + bob], [0.7, 0.62 + bob - wag], [0.84, 0.58 + bob - wag]], ear)
			pic._circle(0.5, 0.5 + bob, 0.28, color)
			pic._circle(0.5, 0.64 + bob, 0.14, Color(1.0, 0.93, 0.82))
			pic._eye(0.4, 0.45 + bob, 0.055)
			pic._eye(0.6, 0.45 + bob, 0.055)
			pic._circle(0.5, 0.58 + bob, 0.045, Color(0.2, 0.12, 0.1))
			if fmod(t, 1.6) < 1.0:
				pic._poly([[0.46, 0.68 + bob], [0.54, 0.68 + bob], [0.54, 0.78 + bob], [0.5, 0.8 + bob], [0.46, 0.78 + bob]], Color(1.0, 0.5, 0.6))
			pic._poly([[0.3, 0.76 + bob], [0.7, 0.76 + bob], [0.68, 0.8 + bob], [0.32, 0.8 + bob]], Color(0.9, 0.2, 0.25))
