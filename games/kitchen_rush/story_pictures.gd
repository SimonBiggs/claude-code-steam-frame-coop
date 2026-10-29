extends RefCounted
## Kitchen Rush's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["granny", "kid", "pirate", "robot", "alien", "knight"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"granny", "kid", "pirate", "robot", "alien", "knight":
			_guest(pic, kind, t, bob, color)


## A round friendly guest face with their hat (the Kitchen Rush party guests).
static func _guest(pic, who: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var skin := {"granny": Color(0.98, 0.82, 0.78), "kid": Color(1.0, 0.75, 0.55), "pirate": Color(0.95, 0.75, 0.55),
		"robot": Color(0.72, 0.76, 0.82), "alien": Color(0.45, 0.95, 0.4), "knight": Color(0.95, 0.8, 0.65)}.get(who, color) as Color
	var y := 0.58 + bob
	if who == "knight":
		pic._circle(0.5, y - 0.04, 0.33, Color(0.75, 0.77, 0.82))
		pic._poly([[0.47, y - 0.36], [0.53, y - 0.36], [0.6, y - 0.52], [0.4, y - 0.52]], Color(0.95, 0.2, 0.25))
	if who == "robot":
		pic._poly([[0.22, y - 0.25], [0.78, y - 0.25], [0.78, y + 0.27], [0.22, y + 0.27]], skin)
		pic.draw_line(pic._p(0.5, y - 0.25), pic._p(0.5, y - 0.4), Color(0.4, 0.4, 0.45), 0.02 * size.x)
		pic._circle(0.5, y - 0.42, 0.05, Color(1.0, 0.25, 0.25) if fmod(t, 1.0) < 0.5 else Color(0.6, 0.15, 0.15))
		pic._poly([[0.3, y - 0.08], [0.43, y - 0.08], [0.43, y + 0.02], [0.3, y + 0.02]], Color(0.4, 0.9, 1.0))
		pic._poly([[0.57, y - 0.08], [0.7, y - 0.08], [0.7, y + 0.02], [0.57, y + 0.02]], Color(0.4, 0.9, 1.0))
		pic._poly([[0.38, y + 0.13], [0.62, y + 0.13], [0.62, y + 0.17], [0.38, y + 0.17]], Color(0.25, 0.25, 0.3))
		return
	if who == "alien":
		for x in [0.35, 0.65]:
			pic.draw_line(pic._p(0.5 + (x - 0.5) * 0.6, y - 0.22), pic._p(x, y - 0.42), Color(0.3, 0.75, 0.3), 0.02 * size.x)
			pic._circle(x, y - 0.43, 0.05, Color(1.0, 0.4, 0.9))
	pic._circle(0.5, y, 0.28 if who != "knight" else 0.2, skin)
	if who == "granny":
		pic._circle(0.5, y - 0.3, 0.1, Color(0.92, 0.92, 0.95))
		pic._circle(0.3, y - 0.18, 0.1, Color(0.92, 0.92, 0.95))
		pic._circle(0.7, y - 0.18, 0.1, Color(0.92, 0.92, 0.95))
	var er := 0.055 if who != "knight" else 0.045
	pic._eye(0.4, y - 0.03, er)
	pic._eye(0.6, y - 0.03, er)
	if who == "alien":
		pic._eye(0.5, y - 0.15, 0.045)
	if who == "granny":
		pic.draw_arc(pic._p(0.4, y - 0.03), 0.075 * size.x, 0.0, TAU, 14, Color(0.75, 0.6, 0.2), 0.015 * size.x)
		pic.draw_arc(pic._p(0.6, y - 0.03), 0.075 * size.x, 0.0, TAU, 14, Color(0.75, 0.6, 0.2), 0.015 * size.x)
	pic.draw_arc(pic._p(0.5, y + 0.07), 0.09 * size.x, 0.3, PI - 0.3, 10, Color(0.35, 0.1, 0.12), 0.022 * size.x)
	pic._circle(0.32, y + 0.08, 0.035, Color(1.0, 0.55, 0.65, 0.7))
	pic._circle(0.68, y + 0.08, 0.035, Color(1.0, 0.55, 0.65, 0.7))
	match who:
		"kid":
			pic._poly([[0.25, y - 0.18], [0.75, y - 0.18], [0.65, y - 0.3], [0.35, y - 0.3]], Color(0.3, 0.6, 1.0))
			var spin := sin(t * 10.0) * 0.18
			pic.draw_line(pic._p(0.5, y - 0.3), pic._p(0.5, y - 0.38), Color(0.3, 0.3, 0.3), 0.02 * size.x)
			pic.draw_line(pic._p(0.5 - spin, y - 0.39), pic._p(0.5 + spin, y - 0.39), Color(1.0, 0.3, 0.3), 0.04 * size.x)
		"pirate":
			pic._poly([[0.15, y - 0.2], [0.85, y - 0.2], [0.72, y - 0.42], [0.5, y - 0.36], [0.28, y - 0.42]], Color(0.12, 0.1, 0.12))
			pic._circle(0.5, y - 0.3, 0.035, Color.WHITE)
			pic._circle(0.6, y - 0.03, 0.065, Color(0.08, 0.08, 0.1))
			pic.draw_line(pic._p(0.6, y - 0.03), pic._p(0.78, y - 0.2), Color(0.08, 0.08, 0.1), 0.015 * size.x)
		"knight":
			pic._poly([[0.3, y - 0.07], [0.7, y - 0.07], [0.7, y - 0.03], [0.3, y - 0.03]], Color(0.75, 0.77, 0.82, 0.6))
