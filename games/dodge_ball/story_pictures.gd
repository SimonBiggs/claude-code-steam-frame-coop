extends RefCounted
## Soft Dodgeball's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## The park's other things use other games' pictures (daisy, sunflower, sapling, balloon, bunny).

const NAMES: Array[String] = ["tumtum", "squishball", "goldball", "cushion", "toadstool", "duckling"]

const SKIN := Color(1.0, 0.82, 0.68)
const JUMPER := Color(1.0, 0.6, 0.25)
const HAIR := Color(0.55, 0.3, 0.15)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"tumtum":  # TumTum the friendly giant: big round tummy with a target on it, waving
			var wave := sin(t * 5.0) * 0.06
			pic._circle(0.5, 0.78 + bob, 0.3, JUMPER)  # tummy
			pic._circle(0.5, 0.8 + bob, 0.15, Color(1.0, 0.25, 0.3))  # the target
			pic._circle(0.5, 0.8 + bob, 0.1, Color.WHITE)
			pic._circle(0.5, 0.8 + bob, 0.05, Color(1.0, 0.25, 0.3))
			pic._circle(0.2, 0.62 + bob, 0.07, SKIN)  # left mitten
			pic._circle(0.84, 0.42 + bob + wave, 0.07, SKIN)  # waving mitten
			pic._poly([[0.7, 0.62 + bob], [0.78, 0.6 + bob], [0.86, 0.44 + bob + wave], [0.8, 0.42 + bob + wave]], JUMPER)
			pic._circle(0.5, 0.36 + bob, 0.21, SKIN)  # head
			pic._poly([[0.29, 0.32 + bob], [0.36, 0.17 + bob], [0.5, 0.13 + bob], [0.64, 0.17 + bob], [0.71, 0.32 + bob], [0.6, 0.24 + bob], [0.4, 0.24 + bob]], HAIR)
			pic._eye(0.42, 0.34 + bob, 0.045)
			pic._eye(0.58, 0.34 + bob, 0.045)
			pic._circle(0.36, 0.42 + bob, 0.035, Color(1.0, 0.6, 0.6))  # cheeks
			pic._circle(0.64, 0.42 + bob, 0.035, Color(1.0, 0.6, 0.6))
			pic._poly([[0.42, 0.44 + bob], [0.58, 0.44 + bob], [0.5, 0.5 + bob]], Color(0.65, 0.15, 0.2))  # big smile
		"squishball":  # a soft ball bouncing and squishing
			var h := absf(sin(t * 3.5))
			var sq := 1.0 - 0.25 * (1.0 - h) * (1.0 - h)
			var y := 0.78 - h * 0.4 + bob
			pic._poly([[0.3, 0.9], [0.7, 0.9], [0.62, 0.93], [0.38, 0.93]], Color(0, 0, 0, 0.25))  # shadow
			var pts: Array = []
			for i in 16:
				var a := TAU * float(i) / 16.0
				pts.append([0.5 + cos(a) * 0.17 / sq, y + sin(a) * 0.17 * sq])
			pic._poly(pts, color)
			pic._circle(0.44, y - 0.06 * sq, 0.045, Color(1, 1, 1, 0.7))  # shine
		"goldball":  # TODAY'S PARK: a golden ball with twinkles
			pic._circle(0.5, 0.55 + bob, 0.27, Color(1.0, 0.78, 0.2))
			pic._circle(0.5, 0.55 + bob, 0.21, Color(1.0, 0.86, 0.35))
			pic._circle(0.42, 0.46 + bob, 0.06, Color(1, 1, 1, 0.75))
			for i in 4:
				var a := t * 1.5 + TAU * float(i) / 4.0
				var tw := 0.02 + 0.015 * absf(sin(t * 4.0 + float(i)))
				var cx := 0.5 + cos(a) * 0.38
				var cy := 0.55 + sin(a) * 0.38 + bob
				pic._poly([[cx, cy - tw * 2.0], [cx + tw, cy], [cx, cy + tw * 2.0], [cx - tw, cy]], Color(1.0, 0.95, 0.6))
		"cushion":  # a puffy park cushion to hide behind
			var puff := 1.0 + 0.03 * sin(t * 2.5)
			for b in [[0.3, 0.62, 0.16], [0.5, 0.52, 0.2], [0.7, 0.62, 0.16], [0.5, 0.68, 0.18]]:
				pic._circle(b[0], b[1] + bob, b[2] * puff, color)
			pic._circle(0.42, 0.48 + bob, 0.05, color.lightened(0.4))
			pic._eye(0.44, 0.6 + bob, 0.04)  # a sleepy happy face
			pic._eye(0.56, 0.6 + bob, 0.04)
			pic._poly([[0.46, 0.68 + bob], [0.54, 0.68 + bob], [0.5, 0.71 + bob]], color.darkened(0.4))
		"toadstool":  # a red toadstool with white spots
			pic._poly([[0.42, 0.55 + bob], [0.58, 0.55 + bob], [0.6, 0.88 + bob], [0.4, 0.88 + bob]], Color(0.98, 0.94, 0.85))
			var cap: Array = []
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				cap.append([0.5 + cos(a) * 0.32, 0.56 + sin(a) * 0.26 + bob])
			pic._poly(cap, Color(0.9, 0.2, 0.2))
			for s in [[0.38, 0.45, 0.04], [0.55, 0.38, 0.05], [0.66, 0.5, 0.035], [0.47, 0.52, 0.03]]:
				pic._circle(s[0], s[1] + bob, s[2], Color.WHITE)
			pic._eye(0.46, 0.68 + bob, 0.03)
			pic._eye(0.54, 0.68 + bob, 0.03)
		"duckling":  # a little yellow duckling waddling
			var wad := sin(t * 6.0) * 0.02
			var y := Color(1.0, 0.88, 0.3)
			pic._circle(0.48 + wad, 0.66 + bob, 0.22, y)  # body
			pic._poly([[0.28 + wad, 0.6 + bob], [0.18 + wad, 0.5 + bob], [0.3 + wad, 0.68 + bob]], y)  # tail
			pic._circle(0.62 + wad, 0.38 + bob, 0.14, y)  # head
			pic._eye(0.66 + wad, 0.35 + bob, 0.035)
			pic._poly([[0.74 + wad, 0.38 + bob], [0.86 + wad, 0.41 + bob], [0.74 + wad, 0.44 + bob]], Color(1.0, 0.55, 0.15))  # beak
			pic._poly([[0.4 + wad, 0.62 + bob], [0.56 + wad, 0.6 + bob], [0.5 + wad, 0.72 + bob]], y.darkened(0.12))  # wing
			pic._poly([[0.42, 0.87 + bob], [0.5, 0.87 + bob], [0.46, 0.92 + bob]], Color(1.0, 0.55, 0.15))  # feet
			pic._poly([[0.52, 0.87 + bob], [0.6, 0.87 + bob], [0.56, 0.92 + bob]], Color(1.0, 0.55, 0.15))
