extends RefCounted
## Fruit Catch's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Apples use Whack-a-Mole's "apple": any picture works in every game.)

const NAMES: Array[String] = ["squirrel", "acorn", "orange", "pear", "plum", "pie", "juice", "crumble", "jamjar", "fruitbowl", "sapling"]

const RED := Color(0.95, 0.15, 0.15)
const ORANGE := Color(1.0, 0.55, 0.05)
const GREEN := Color(0.72, 0.88, 0.2)
const PURPLE := Color(0.62, 0.22, 0.85)
const LEAF := Color(0.25, 0.7, 0.25)
const STALK := Color(0.4, 0.26, 0.14)
const CRUST := Color(0.92, 0.7, 0.38)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"squirrel":  # Nutmeg: a round red squirrel with a huge curly tail and a little chef's hat
			var fur := Color(0.85, 0.45, 0.18)
			var sway := sin(t * 2.5) * 0.03
			pic._circle(0.27 + sway, 0.42 + bob, 0.2, fur.darkened(0.1))  # tail
			pic._circle(0.22 + sway, 0.26 + bob, 0.13, fur.darkened(0.1))
			pic._circle(0.25 + sway, 0.42 + bob, 0.1, fur.lightened(0.25))
			pic._circle(0.56, 0.68 + bob, 0.2, fur)  # body
			pic._circle(0.58, 0.74 + bob, 0.11, Color(1.0, 0.9, 0.75))
			pic._poly([[0.48, 0.3 + bob], [0.53, 0.16 + bob], [0.58, 0.3 + bob]], fur.darkened(0.15))  # ears
			pic._poly([[0.68, 0.3 + bob], [0.74, 0.16 + bob], [0.78, 0.31 + bob]], fur.darkened(0.15))
			pic._circle(0.63, 0.42 + bob, 0.17, fur)  # head
			pic._circle(0.66, 0.5 + bob, 0.08, Color(1.0, 0.9, 0.75))
			pic._eye(0.58, 0.39 + bob, 0.045)
			pic._eye(0.71, 0.39 + bob, 0.045)
			pic._circle(0.66, 0.46 + bob, 0.025, Color(0.25, 0.12, 0.1))
			pic._poly([[0.62, 0.53 + bob], [0.7, 0.53 + bob], [0.66, 0.56 + bob]], Color(0.9, 0.35, 0.4))
			pic._circle(0.66, 0.17 + bob, 0.08, Color.WHITE)  # chef's hat
			pic._circle(0.59, 0.2 + bob, 0.06, Color.WHITE)
			pic._circle(0.73, 0.2 + bob, 0.06, Color.WHITE)
			pic._poly([[0.58, 0.22 + bob], [0.74, 0.22 + bob], [0.73, 0.28 + bob], [0.59, 0.28 + bob]], Color.WHITE)
			pic._circle(0.47, 0.72 + bob, 0.05, color)  # holding a fruit
		"acorn":  # the orchard's seed
			pic._circle(0.5, 0.58 + bob, 0.22, Color(0.75, 0.5, 0.25))
			pic._poly([[0.26, 0.48 + bob], [0.74, 0.48 + bob], [0.7, 0.36 + bob], [0.5, 0.3 + bob], [0.3, 0.36 + bob]], Color(0.45, 0.3, 0.15))
			pic._poly([[0.48, 0.3 + bob], [0.52, 0.3 + bob], [0.54, 0.2 + bob], [0.5, 0.2 + bob]], STALK)
			pic._circle(0.42, 0.56 + bob, 0.05, Color(1.0, 1.0, 1.0, 0.35))
		"orange":
			_fruit(pic, bob, ORANGE, 0.27)
			for i in 6:
				pic._circle(0.38 + i * 0.05, 0.62 + bob + sin(i * 2.0) * 0.08, 0.012, ORANGE.darkened(0.25))
		"pear":
			pic._circle(0.5, 0.64 + bob, 0.24, GREEN)
			pic._circle(0.5, 0.4 + bob, 0.15, GREEN)
			_stalk(pic, bob, 0.24)
			pic._circle(0.42, 0.6 + bob, 0.05, Color(1.0, 1.0, 1.0, 0.4))
		"plum":
			_fruit(pic, bob, PURPLE, 0.25)
			pic._poly([[0.5, 0.36 + bob], [0.53, 0.36 + bob], [0.53, 0.8 + bob], [0.5, 0.8 + bob]], PURPLE.darkened(0.25))
		"pie":  # a golden pie with a lattice; the filling in `color`
			_pie(pic, bob, color, t)
		"crumble":
			_pie(pic, bob, color, t)
			for i in 9:
				pic._circle(0.26 + fmod(i * 0.37, 0.48), 0.48 + bob + fmod(i * 0.23, 0.1), 0.045, CRUST.lightened(0.2))
		"juice":  # a tall glass of juice (in `color`) with a straw
			pic._poly([[0.3, 0.25 + bob], [0.7, 0.25 + bob], [0.64, 0.86 + bob], [0.36, 0.86 + bob]], Color(0.85, 0.95, 1.0, 0.6))
			pic._poly([[0.32, 0.38 + bob], [0.68, 0.38 + bob], [0.635, 0.84 + bob], [0.365, 0.84 + bob]], color)
			pic._poly([[0.56, 0.08 + bob], [0.6, 0.08 + bob], [0.55, 0.6 + bob], [0.51, 0.6 + bob]], Color(1.0, 0.4, 0.55))
			for i in 3:
				var y := 0.8 - fmod(t * 0.3 + i * 0.33, 1.0) * 0.38
				pic._circle(0.42 + i * 0.07, y + bob, 0.02, color.lightened(0.5))
		"jamjar":  # a jar of jam (in `color`) with a gingham lid
			pic._poly([[0.28, 0.34 + bob], [0.72, 0.34 + bob], [0.74, 0.84 + bob], [0.26, 0.84 + bob]], Color(0.85, 0.95, 1.0, 0.5))
			pic._poly([[0.3, 0.42 + bob], [0.7, 0.42 + bob], [0.72, 0.82 + bob], [0.28, 0.82 + bob]], color)
			pic._poly([[0.22, 0.22 + bob], [0.78, 0.22 + bob], [0.74, 0.36 + bob], [0.26, 0.36 + bob]], Color(0.95, 0.2, 0.25))
			for i in 4:
				pic._circle(0.3 + i * 0.13, 0.29 + bob, 0.035, Color.WHITE)
			pic._poly([[0.36, 0.55 + bob], [0.64, 0.55 + bob], [0.64, 0.7 + bob], [0.36, 0.7 + bob]], Color(1.0, 0.97, 0.85))
		"fruitbowl":  # a bowl heaped with every fruit
			pic._circle(0.36, 0.5 + bob, 0.12, RED)
			pic._circle(0.62, 0.48 + bob, 0.12, ORANGE)
			pic._circle(0.49, 0.4 + bob, 0.11, PURPLE)
			pic._circle(0.5, 0.56 + bob, 0.1, GREEN)
			pic._poly([[0.14, 0.56 + bob], [0.86, 0.56 + bob], [0.74, 0.8 + bob], [0.26, 0.8 + bob]], Color(0.3, 0.65, 1.0))
			pic._poly([[0.38, 0.8 + bob], [0.62, 0.8 + bob], [0.6, 0.86 + bob], [0.4, 0.86 + bob]], Color(0.2, 0.5, 0.85))
		"sapling":  # a little orchard tree (fruit in `color`) on a hill
			pic._poly([[0.1, 0.9], [0.9, 0.9], [0.75, 0.8], [0.25, 0.8]], Color(0.4, 0.75, 0.3))
			pic._poly([[0.47, 0.85], [0.53, 0.85], [0.52, 0.5 + bob], [0.48, 0.5 + bob]], STALK)
			pic._circle(0.5, 0.4 + bob, 0.22, LEAF)
			pic._circle(0.36, 0.48 + bob, 0.13, LEAF.darkened(0.1))
			pic._circle(0.64, 0.48 + bob, 0.13, LEAF.darkened(0.1))
			for i in 4:
				pic._circle(0.36 + (i % 2) * 0.26 + i * 0.02, 0.32 + (i / 2) * 0.16 + bob, 0.045, color)


static func _fruit(pic, bob: float, c: Color, r: float) -> void:
	pic._circle(0.5, 0.58 + bob, r, c)
	_stalk(pic, bob, 0.58 - r)
	pic._circle(0.42, 0.5 + bob, r * 0.22, Color(1.0, 1.0, 1.0, 0.4))


static func _stalk(pic, bob: float, top: float) -> void:
	pic._poly([[0.49, top + 0.02 + bob], [0.52, top + 0.02 + bob], [0.54, top - 0.08 + bob], [0.51, top - 0.08 + bob]], STALK)
	pic._poly([[0.53, top - 0.04 + bob], [0.66, top - 0.1 + bob], [0.6, top - 0.01 + bob]], LEAF)


static func _pie(pic, bob: float, c: Color, t: float) -> void:
	pic._poly([[0.12, 0.56 + bob], [0.88, 0.56 + bob], [0.78, 0.78 + bob], [0.22, 0.78 + bob]], Color(0.85, 0.85, 0.9))  # dish
	pic._poly([[0.16, 0.56 + bob], [0.84, 0.56 + bob], [0.76, 0.42 + bob], [0.24, 0.42 + bob]], c)
	pic._poly([[0.16, 0.56 + bob], [0.84, 0.56 + bob], [0.82, 0.6 + bob], [0.18, 0.6 + bob]], CRUST.darkened(0.1))
	for i in 4:
		var x := 0.28 + i * 0.14
		pic._poly([[x, 0.42 + bob], [x + 0.04, 0.42 + bob], [x + 0.03, 0.56 + bob], [x - 0.01, 0.56 + bob]], CRUST)
	pic._poly([[0.22, 0.47 + bob], [0.78, 0.47 + bob], [0.8, 0.5 + bob], [0.2, 0.5 + bob]], CRUST)
	for i in 3:  # steam
		var y := 0.36 - fmod(t * 0.4 + i * 0.33, 1.0) * 0.28
		pic._circle(0.36 + i * 0.14, y + bob, 0.03, Color(1.0, 1.0, 1.0, 0.5))
