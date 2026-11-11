extends RefCounted
## Kitchen Rush's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["granny", "kid", "pirate", "robot", "alien", "knight", "pizzanight", "pancakes", "picnic", "quickknife",
	"bigpot", "helpermouse", "skates", "ovensmoke", "spill", "fairylights", "fishtank", "piano", "cafestar", "chandelier"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"granny", "kid", "pirate", "robot", "alien", "knight":
			_guest(pic, kind, t, bob, color)
		_:
			_cafe(pic, kind, t, bob, color)


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


## Second pass pictures (nights.gd): theme nights, chef gifts, kitchen events, the growing café.
static func _cafe(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var w := 0.02 * size.x
	match kind:
		"pizzanight":
			pic._circle(0.5, 0.55 + bob, 0.36, Color(0.95, 0.72, 0.38))
			pic._circle(0.5, 0.55 + bob, 0.3, Color(0.95, 0.3, 0.2))
			for i in 6:
				var a := TAU * i / 6.0 + t * 0.3
				pic._circle(0.5 + cos(a) * 0.17, 0.55 + bob + sin(a) * 0.17, 0.05, Color(0.7, 0.1, 0.1))
			pic._circle(0.5, 0.55 + bob, 0.06, Color(1.0, 0.92, 0.45))
		"pancakes":
			pic._poly([[0.12, 0.86], [0.88, 0.86], [0.8, 0.92], [0.2, 0.92]], Color(0.95, 0.95, 1.0))
			for i in 4:
				var y := 0.8 - i * 0.1 + bob
				pic._poly([[0.2, y], [0.8, y], [0.78, y - 0.08], [0.22, y - 0.08]], Color(0.95, 0.7, 0.38))
			pic._poly([[0.25, 0.42 + bob], [0.75, 0.42 + bob], [0.7, 0.48 + bob], [0.3, 0.48 + bob]], Color(0.55, 0.28, 0.08))
			for i in 3:
				pic._circle(0.38 + i * 0.12, 0.37 + bob, 0.045, Color(0.42, 0.2, 0.7))
		"picnic":
			pic._poly([[0.18, 0.5 + bob], [0.82, 0.5 + bob], [0.75, 0.88 + bob], [0.25, 0.88 + bob]], Color(0.75, 0.5, 0.25))
			for i in 4:
				var x := 0.18 + i * 0.16
				pic._poly([[x, 0.42 + bob], [x + 0.16, 0.42 + bob], [x + 0.16, 0.52 + bob], [x, 0.52 + bob]], Color(0.95, 0.3, 0.35) if i % 2 == 0 else Color.WHITE)
			pic.draw_arc(pic._p(0.5, 0.45 + bob), 0.25 * size.x, PI, TAU, 16, Color(0.6, 0.38, 0.2), w * 1.5)
		"quickknife":
			pic._poly([[0.2, 0.62 + bob], [0.75, 0.3 + bob], [0.82, 0.38 + bob], [0.3, 0.7 + bob]], Color(0.85, 0.9, 0.95))
			pic._poly([[0.12, 0.68 + bob], [0.3, 0.6 + bob], [0.34, 0.7 + bob], [0.16, 0.78 + bob]], Color(0.55, 0.3, 0.15))
			for i in 3:  # speed lines
				var y2 := 0.25 + i * 0.1
				pic.draw_line(pic._p(0.62 + i * 0.06, y2), pic._p(0.9, y2 - 0.04), Color(1.0, 1.0, 0.6, 0.8), w)
		"bigpot":
			pic._poly([[0.18, 0.45 + bob], [0.82, 0.45 + bob], [0.76, 0.86 + bob], [0.24, 0.86 + bob]], Color(0.85, 0.5, 0.2))
			pic._poly([[0.14, 0.4 + bob], [0.86, 0.4 + bob], [0.86, 0.47 + bob], [0.14, 0.47 + bob]], Color(0.95, 0.7, 0.3))
			for i in 3:
				var k := fmod(t * 0.6 + i * 0.33, 1.0)
				pic._circle(0.35 + i * 0.15, 0.32 - k * 0.22, 0.06 * (1.0 - k * 0.6), Color(1, 1, 1, 0.8 - k * 0.6))
		"helpermouse":
			pic._circle(0.5, 0.62 + bob, 0.24, Color(0.72, 0.7, 0.76))
			pic._circle(0.3, 0.38 + bob, 0.11, Color(0.72, 0.7, 0.76))
			pic._circle(0.7, 0.38 + bob, 0.11, Color(0.72, 0.7, 0.76))
			pic._circle(0.3, 0.38 + bob, 0.06, Color(1.0, 0.7, 0.75))
			pic._circle(0.7, 0.38 + bob, 0.06, Color(1.0, 0.7, 0.75))
			pic._eye(0.42, 0.58 + bob, 0.04)
			pic._eye(0.58, 0.58 + bob, 0.04)
			pic._circle(0.5, 0.7 + bob, 0.035, Color(1.0, 0.5, 0.6))
		"skates":
			pic._poly([[0.25, 0.3 + bob], [0.5, 0.3 + bob], [0.55, 0.6 + bob], [0.82, 0.62 + bob], [0.82, 0.74 + bob], [0.22, 0.74 + bob]], Color(0.4, 0.95, 0.75))
			for x in [0.3, 0.52, 0.74]:
				pic._circle(x, 0.82 + bob, 0.07, Color(1.0, 0.85, 0.3))
		"ovensmoke":
			pic._poly([[0.2, 0.62], [0.8, 0.62], [0.8, 0.92], [0.2, 0.92]], Color(0.45, 0.45, 0.5))
			pic._poly([[0.3, 0.7], [0.7, 0.7], [0.7, 0.86], [0.3, 0.86]], Color(1.0, 0.55, 0.2))
			for i in 4:
				var k2 := fmod(t * 0.5 + i * 0.25, 1.0)
				pic._circle(0.35 + 0.1 * i, 0.5 - k2 * 0.35, 0.09 + k2 * 0.05, Color(0.8, 0.8, 0.85, 0.9 - k2 * 0.5))
		"spill":
			pic._circle(0.5, 0.72, 0.3, Color(0.45, 0.75, 1.0, 0.8))
			pic._circle(0.65, 0.66, 0.15, Color(0.6, 0.85, 1.0, 0.8))
			pic._poly([[0.15, 0.3 + bob], [0.4, 0.22 + bob], [0.5, 0.48 + bob], [0.25, 0.56 + bob]], Color(0.95, 0.75, 0.2))
			pic._circle(0.55 + 0.05 * sin(t * 3.0), 0.5, 0.04, Color(0.6, 0.85, 1.0))
		"fairylights":
			pic.draw_arc(pic._p(0.5, 0.1), 0.45 * size.x, 0.4, PI - 0.4, 16, Color(0.3, 0.3, 0.3), w * 0.5)
			for i in 7:
				var a3 := 0.5 + (PI - 1.0) * i / 6.0
				var on := fmod(t * 2.0 + i * 0.5, 1.0) < 0.7
				var bc: Color = [Color(1.0, 0.85, 0.3), Color(1.0, 0.45, 0.6), Color(0.45, 0.85, 1.0)][i % 3]
				pic._circle(0.5 + cos(a3) * 0.45, 0.1 + sin(a3) * 0.45 + 0.04, 0.05, bc if on else bc.darkened(0.4))
		"fishtank":
			pic._poly([[0.12, 0.3], [0.88, 0.3], [0.88, 0.85], [0.12, 0.85]], Color(0.45, 0.8, 1.0, 0.85))
			pic._poly([[0.12, 0.8], [0.88, 0.8], [0.88, 0.85], [0.12, 0.85]], Color(0.9, 0.8, 0.5))
			var fx := 0.5 + 0.25 * sin(t)
			pic._circle(fx, 0.55 + bob, 0.08, Color(1.0, 0.55, 0.1))
			pic._poly([[fx + 0.07, 0.55 + bob], [fx + 0.16, 0.48 + bob], [fx + 0.16, 0.62 + bob]], Color(1.0, 0.55, 0.1))
		"piano":
			pic._poly([[0.12, 0.25 + bob], [0.88, 0.25 + bob], [0.88, 0.85 + bob], [0.12, 0.85 + bob]], Color(0.15, 0.1, 0.12))
			pic._poly([[0.16, 0.55 + bob], [0.84, 0.55 + bob], [0.84, 0.72 + bob], [0.16, 0.72 + bob]], Color(0.97, 0.97, 0.95))
			for i in 6:
				pic._poly([[0.22 + i * 0.11, 0.55 + bob], [0.27 + i * 0.11, 0.55 + bob], [0.27 + i * 0.11, 0.64 + bob], [0.22 + i * 0.11, 0.64 + bob]], Color(0.08, 0.08, 0.1))
		"cafestar":
			var pts: Array = []
			for i in 10:
				var a4 := -PI / 2.0 + TAU * i / 10.0 + 0.1 * sin(t)
				var rr := 0.38 if i % 2 == 0 else 0.17
				pts.append([0.5 + cos(a4) * rr, 0.55 + bob + sin(a4) * rr])
			pic._poly(pts, Color(1.0, 0.8, 0.2))
		"chandelier":
			pic.draw_line(pic._p(0.5, 0.05), pic._p(0.5, 0.35 + bob), Color(0.8, 0.65, 0.25), w)
			pic._poly([[0.15, 0.4 + bob], [0.85, 0.4 + bob], [0.7, 0.55 + bob], [0.3, 0.55 + bob]], Color(1.0, 0.8, 0.3))
			for i in 5:
				var on2 := fmod(t * 1.5 + i * 0.3, 1.0) < 0.8
				pic._circle(0.2 + i * 0.15, 0.33 + bob, 0.05, Color(1.0, 0.95, 0.7) if on2 else Color(1.0, 0.8, 0.5))
