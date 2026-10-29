extends RefCounted
## Coaster Crew's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (The new rides use Ice Cream's "carousel" / "ferris", Snowball Blitz's "fountain" and Cannon Cove's "bunting": any picture works anywhere.)

const NAMES: Array[String] = ["bear", "blueprint", "ticket", "coastercar", "loopdeloop", "splashpool"]

const FUR := Color(0.72, 0.48, 0.28)
const MUZZLE := Color(0.96, 0.85, 0.68)
const GOLD := Color(1.0, 0.8, 0.2)
const RAIL := Color(0.92, 0.22, 0.25)
const WATER := Color(0.3, 0.65, 1.0)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"bear":  # Buttons: a round teddy bear park keeper in a red conductor's cap, waving
			var wave := sin(t * 5.0) * 0.06
			pic._circle(0.5, 0.82 + bob, 0.2, Color(0.25, 0.45, 0.85))  # blue waistcoat body
			pic._circle(0.44, 0.78 + bob, 0.025, GOLD)  # buttons!
			pic._circle(0.44, 0.88 + bob, 0.025, GOLD)
			pic._circle(0.83 + wave, 0.62 + bob, 0.07, FUR)  # waving paw
			pic._circle(0.3, 0.27 + bob, 0.08, FUR)  # ears
			pic._circle(0.7, 0.27 + bob, 0.08, FUR)
			pic._circle(0.3, 0.27 + bob, 0.04, MUZZLE)
			pic._circle(0.7, 0.27 + bob, 0.04, MUZZLE)
			pic._circle(0.5, 0.46 + bob, 0.23, FUR)  # head
			pic._circle(0.5, 0.54 + bob, 0.1, MUZZLE)
			pic._circle(0.5, 0.5 + bob, 0.035, Color(0.2, 0.12, 0.1))  # nose
			pic._poly([[0.45, 0.58 + bob], [0.55, 0.58 + bob], [0.5, 0.62 + bob]], Color(0.75, 0.3, 0.35))
			pic._eye(0.41, 0.41 + bob, 0.045)
			pic._eye(0.59, 0.41 + bob, 0.045)
			pic._poly([[0.3, 0.3 + bob], [0.7, 0.3 + bob], [0.66, 0.16 + bob], [0.34, 0.16 + bob]], Color(0.9, 0.2, 0.25))  # cap
			pic._poly([[0.28, 0.3 + bob], [0.78, 0.3 + bob], [0.78, 0.34 + bob], [0.28, 0.34 + bob]], Color(0.2, 0.2, 0.3))  # peak
			pic._circle(0.5, 0.23 + bob, 0.03, GOLD)
		"blueprint":  # Buttons' plan: a blue sheet with a white coaster drawn on it
			pic._poly([[0.12, 0.2 + bob], [0.88, 0.2 + bob], [0.88, 0.8 + bob], [0.12, 0.8 + bob]], Color(0.2, 0.42, 0.85))
			pic._circle(0.12, 0.5 + bob, 0.06, Color(0.15, 0.32, 0.7))  # rolled edges
			pic._circle(0.88, 0.5 + bob, 0.06, Color(0.15, 0.32, 0.7))
			var prev := Vector2(0.2, 0.68)
			for i in range(1, 13):
				var x := 0.2 + i * 0.05
				var y := 0.68 - 0.3 * sin(i / 12.0 * PI) * (1.0 if i < 7 else 0.6) + 0.04 * sin(t * 3.0 + i)
				pic._poly([[prev.x, prev.y + bob], [x, y + bob], [x, y + 0.025 + bob], [prev.x, prev.y + 0.025 + bob]], Color(1, 1, 1, 0.9))
				prev = Vector2(x, y)
			pic._circle(0.3 + fmod(t * 0.2, 0.5), 0.3 + bob, 0.03, color)  # a glowing dot running along
		"ticket":  # a golden ticket with a star
			var tilt := sin(t * 2.0) * 0.03
			pic._poly([[0.12, 0.32 + tilt + bob], [0.88, 0.28 - tilt + bob], [0.88, 0.72 - tilt + bob], [0.12, 0.76 + tilt + bob]], GOLD)
			pic._poly([[0.18, 0.38 + tilt + bob], [0.82, 0.34 - tilt + bob], [0.82, 0.66 - tilt + bob], [0.18, 0.7 + tilt + bob]], GOLD.lightened(0.3))
			var pts: Array = []
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0 + t * 0.6
				var r := 0.14 if i % 2 == 0 else 0.06
				pts.append([0.5 + cos(a) * r, 0.52 + sin(a) * r + bob])
			pic._poly(pts, color if color != Color.WHITE else Color(1.0, 0.45, 0.2))
			pic._circle(0.24, 0.53 + bob, 0.03, GOLD.darkened(0.3))
			pic._circle(0.76, 0.51 + bob, 0.03, GOLD.darkened(0.3))
		"coastercar":  # a coaster car on its rails, riders with hands up
			var dip := sin(t * 3.0) * 0.03
			pic._poly([[0.05, 0.78 + bob], [0.95, 0.7 + bob], [0.95, 0.74 + bob], [0.05, 0.82 + bob]], RAIL)
			pic._poly([[0.2, 0.5 + dip + bob], [0.8, 0.46 + dip + bob], [0.82, 0.7 + dip + bob], [0.18, 0.74 + dip + bob]], color)
			pic._circle(0.3, 0.76 + dip + bob, 0.05, Color(0.25, 0.25, 0.3))
			pic._circle(0.7, 0.73 + dip + bob, 0.05, Color(0.25, 0.25, 0.3))
			for i in 2:
				var x := 0.38 + i * 0.26
				pic._circle(x, 0.4 + dip + bob, 0.08, Color(1.0, 0.82, 0.68))
				pic._eye(x - 0.03, 0.39 + dip + bob, 0.02)
				pic._eye(x + 0.03, 0.39 + dip + bob, 0.02)
				var up := 0.06 * absf(sin(t * 4.0 + i))
				pic._poly([[x - 0.09, 0.42 + dip + bob], [x - 0.13, 0.2 - up + dip + bob], [x - 0.1, 0.19 - up + dip + bob], [x - 0.06, 0.42 + dip + bob]], Color(1.0, 0.82, 0.68))
				pic._poly([[x + 0.09, 0.42 + dip + bob], [x + 0.13, 0.2 - up + dip + bob], [x + 0.1, 0.19 - up + dip + bob], [x + 0.06, 0.42 + dip + bob]], Color(1.0, 0.82, 0.68))
		"loopdeloop":  # a big red loop with a tiny car racing round it
			for i in 24:
				var a := TAU * i / 24.0
				pic._circle(0.5 + cos(a) * 0.26, 0.48 + sin(a) * 0.26 + bob, 0.035, RAIL)
			pic._poly([[0.05, 0.76 + bob], [0.95, 0.76 + bob], [0.95, 0.8 + bob], [0.05, 0.8 + bob]], RAIL)
			var ca := t * 3.0
			pic._circle(0.5 + cos(ca) * 0.26, 0.48 + sin(ca) * 0.26 + bob, 0.07, color)
		"splashpool":  # a car splashing down into a blue pool
			pic._poly([[0.05, 0.2 + bob], [0.45, 0.62 + bob], [0.45, 0.66 + bob], [0.05, 0.24 + bob]], RAIL)
			pic._circle(0.5, 0.74 + bob, 0.26, WATER)
			pic._poly([[0.2, 0.74 + bob], [0.8, 0.74 + bob], [0.8, 1.0 + bob], [0.2, 1.0 + bob]], WATER)
			pic._circle(0.45, 0.6 + bob, 0.07, color)
			for i in 6:
				var a := -PI * 0.9 + PI * 0.8 * i / 5.0
				var r := 0.18 + 0.1 * fmod(t * 1.5 + i * 0.2, 1.0)
				pic._circle(0.5 + cos(a) * r, 0.62 + sin(a) * r + bob, 0.03, Color(0.85, 0.95, 1.0))
