extends RefCounted
## Party Board's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["toucan", "rainbowisle", "sweetshop", "pirateship", "hauntedhouse", "friendlyghost",
	"spacestation", "trophywall"]


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
		"rainbowisle":  # PARTY ISLAND's RAINBOW: a rainbow over a little green island
			var bands: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.65, 0.25), Color(1.0, 0.9, 0.3),
				Color(0.4, 0.85, 0.4), Color(0.35, 0.6, 1.0), Color(0.65, 0.45, 0.95)]
			for k in bands.size():
				var r := 0.42 - k * 0.045
				var pts: Array = []
				for s in 17:
					var a := PI + PI * float(s) / 16.0
					pts.append([0.5 + cos(a) * r, 0.62 + bob + sin(a) * r])
				for s in 17:
					var a := TAU - PI * float(s) / 16.0
					pts.append([0.5 + cos(a) * (r - 0.045), 0.62 + bob + sin(a) * (r - 0.045)])
				pic._poly(pts, bands[k])
			pic._poly([[0.12, 0.78 + bob], [0.88, 0.78 + bob], [0.78, 0.68 + bob], [0.22, 0.68 + bob]], Color(0.4, 0.78, 0.35))
			pic._poly([[0.05, 0.86], [0.95, 0.86], [0.95, 0.95], [0.05, 0.95]], Color(0.3, 0.6, 0.95))
		"sweetshop":  # SWEET SHOP: a cupcake hill with a cherry and a lollipop
			pic._poly([[0.22, 0.6 + bob], [0.78, 0.6 + bob], [0.7, 0.92 + bob], [0.3, 0.92 + bob]], Color(0.75, 0.5, 0.3))
			for k in 4:
				pic._poly([[0.3 + k * 0.11, 0.62 + bob], [0.34 + k * 0.11, 0.62 + bob], [0.33 + k * 0.1, 0.9 + bob], [0.31 + k * 0.1, 0.9 + bob]], Color(0.6, 0.38, 0.22))
			pic._circle(0.38, 0.55 + bob, 0.14, Color(1.0, 0.72, 0.85))
			pic._circle(0.62, 0.55 + bob, 0.14, Color(1.0, 0.72, 0.85))
			pic._circle(0.5, 0.45 + bob, 0.16, Color(1.0, 0.8, 0.9))
			pic._circle(0.5, 0.26 + bob, 0.07, Color(0.9, 0.15, 0.25))
			pic._circle(0.48, 0.24 + bob, 0.02, white)
			for k in 5:
				pic._circle(0.38 + k * 0.06, 0.5 + bob + 0.03 * sin(k * 2.0), 0.015, [Color(0.4, 0.8, 1.0), Color(1.0, 0.9, 0.3), Color(0.5, 0.9, 0.5)][k % 3])
		"pirateship":  # PIRATE COVE: a little ship with a smiling flag on the waves
			var rock := sin(t * 2.0) * 0.02
			pic._poly([[0.15, 0.62 + rock], [0.85, 0.62 - rock], [0.74, 0.8 - rock], [0.26, 0.8 + rock]], Color(0.6, 0.38, 0.22))
			pic._poly([[0.15, 0.62 + rock], [0.85, 0.62 - rock], [0.84, 0.66 - rock], [0.16, 0.66 + rock]], Color(0.95, 0.75, 0.3))
			pic._poly([[0.48, 0.62], [0.52, 0.62], [0.52, 0.14], [0.48, 0.14]], Color(0.45, 0.3, 0.2))
			pic._poly([[0.26, 0.2 + bob], [0.48, 0.18 + bob], [0.48, 0.56 + bob], [0.24, 0.54 + bob]], Color(0.97, 0.95, 0.88))
			pic._poly([[0.52, 0.14], [0.74, 0.18 + bob], [0.52, 0.24]], Color(0.15, 0.15, 0.2))
			pic._circle(0.6, 0.19 + bob * 0.5, 0.025, white)
			pic._poly([[0.0, 0.8], [1.0, 0.8], [1.0, 1.0], [0.0, 1.0]], Color(0.25, 0.6, 0.85))
			for k in 5:
				pic._circle(0.1 + k * 0.2, 0.8 + 0.01 * sin(t * 3.0 + k), 0.06, Color(0.4, 0.75, 0.95))
		"hauntedhouse":  # HAUNTED HOUSE: a crooked purple house with glowing windows and a moon
			pic._circle(0.8, 0.18, 0.1, Color(1.0, 0.95, 0.7))
			pic._poly([[0.22, 0.5 + bob], [0.72, 0.5 + bob], [0.7, 0.92], [0.24, 0.92]], Color(0.42, 0.32, 0.55))
			pic._poly([[0.16, 0.52 + bob], [0.47, 0.18 + bob], [0.78, 0.52 + bob]], Color(0.28, 0.2, 0.38))
			var glow := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.6, 0.2), 0.5 + 0.5 * sin(t * 4.0))
			pic._poly([[0.3, 0.6 + bob], [0.4, 0.6 + bob], [0.4, 0.7 + bob], [0.3, 0.7 + bob]], glow)
			pic._poly([[0.54, 0.6 + bob], [0.64, 0.6 + bob], [0.64, 0.7 + bob], [0.54, 0.7 + bob]], glow)
			pic._poly([[0.42, 0.78], [0.52, 0.78], [0.52, 0.92], [0.42, 0.92]], Color(0.2, 0.14, 0.25))
			pic._circle(0.8, 0.82 + bob, 0.08, Color(1.0, 0.55, 0.15))
			pic._poly([[0.79, 0.73 + bob], [0.81, 0.73 + bob], [0.81, 0.76 + bob], [0.79, 0.76 + bob]], Color(0.3, 0.6, 0.25))
		"friendlyghost":  # the friendly ghost (HAUNTED HOUSE): round, smiling, waving
			var wave := sin(t * 3.0) * 0.03
			var pts: Array = []
			for s in 13:
				var a := PI + PI * float(s) / 12.0
				pts.append([0.5 + cos(a) * 0.28, 0.45 + bob + sin(a) * 0.28])
			for s in 7:
				var x := 0.78 - float(s) * (0.56 / 6.0)
				pts.append([x, 0.86 + bob + (0.05 if s % 2 == 0 else -0.01) + wave])
			pic._poly(pts, Color(0.97, 0.97, 1.0))
			pic._circle(0.42, 0.42 + bob, 0.045, Color(0.15, 0.15, 0.25))
			pic._circle(0.58, 0.42 + bob, 0.045, Color(0.15, 0.15, 0.25))
			pic._poly([[0.42, 0.55 + bob], [0.58, 0.55 + bob], [0.5, 0.62 + bob]], Color(0.95, 0.45, 0.55))
			pic._circle(0.36, 0.52 + bob, 0.03, Color(1.0, 0.7, 0.8))
			pic._circle(0.64, 0.52 + bob, 0.03, Color(1.0, 0.7, 0.8))
		"spacestation":  # SPACE STATION: a dome with an antenna, a planet ring and stars
			for k in 6:
				var tw := 0.5 + 0.5 * sin(t * 3.0 + k * 1.7)
				pic._circle(0.1 + fmod(k * 0.37, 0.85), 0.1 + fmod(k * 0.23, 0.35), 0.012 + 0.01 * tw, Color(1, 1, 0.8))
			var pts2: Array = []
			for s in 17:
				var a := PI + PI * float(s) / 16.0
				pts2.append([0.5 + cos(a) * 0.3, 0.72 + bob + sin(a) * 0.3])
			pic._poly(pts2, Color(0.75, 0.85, 1.0))
			pic._poly([[0.12, 0.72 + bob], [0.88, 0.72 + bob], [0.84, 0.82 + bob], [0.16, 0.82 + bob]], Color(0.55, 0.6, 0.72))
			pic._circle(0.5, 0.58 + bob, 0.08, Color(0.4, 0.8, 1.0))
			pic._poly([[0.49, 0.42 + bob], [0.51, 0.42 + bob], [0.51, 0.22 + bob], [0.49, 0.22 + bob]], Color(0.6, 0.6, 0.65))
			pic._circle(0.5, 0.2 + bob, 0.035, Color(1.0, 0.3, 0.3).lerp(Color(1.0, 0.9, 0.4), 0.5 + 0.5 * sin(t * 6.0)))
		"trophywall":  # Mango's TROPHY WALL: shelves of shiny cups
			pic._poly([[0.12, 0.12], [0.88, 0.12], [0.88, 0.92], [0.12, 0.92]], Color(0.55, 0.36, 0.22))
			for row in 3:
				var y := 0.38 + row * 0.25
				pic._poly([[0.1, y], [0.9, y], [0.9, y + 0.04], [0.1, y + 0.04]], Color(0.75, 0.52, 0.32))
				for k in 3:
					var x := 0.27 + k * 0.23
					var shine := Color(1.0, 0.82, 0.25).lightened(0.25 * maxf(0.0, sin(t * 3.0 + row + k * 1.3)))
					pic._poly([[x - 0.07, y - 0.15], [x + 0.07, y - 0.15], [x + 0.03, y - 0.06], [x - 0.03, y - 0.06]], shine)
					pic._poly([[x - 0.015, y - 0.06], [x + 0.015, y - 0.06], [x + 0.015, y - 0.02], [x - 0.015, y - 0.02]], shine)
					pic._poly([[x - 0.05, y - 0.02], [x + 0.05, y - 0.02], [x + 0.05, y], [x - 0.05, y]], Color(0.3, 0.25, 0.3))
