extends RefCounted
## Hide And Seek's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## PIP'S STREET (street.gd): the new neighbours (kitten, hedgehog, owl, tortoise, hamster; bunny, frog and squirrel
## come from other games), the street, the garden party, the dark room and a sneaky friend's paw prints.
## Second pass (deep.gd): Rumble the robot hoover, the pepper pot, SUPER NOSE, the HANKY gift, Pip's kennel.

const NAMES: Array[String] = ["puppy", "kitten", "hedgehog", "owl", "tortoise", "hamster", "street", "gardenparty", "darkroom", "pawprints",
	"hoover", "pepper", "nose", "hanky", "kennel"]


static func _house(pic, x: float, w: float, h: float, wall: Color, roof: Color, lit: bool) -> void:
	var base := 0.8
	pic._poly([[x, base], [x + w, base], [x + w, base - h], [x, base - h]], wall)
	pic._poly([[x - 0.03, base - h], [x + w + 0.03, base - h], [x + w / 2.0, base - h - w * 0.5]], roof)
	pic._poly([[x + w * 0.38, base], [x + w * 0.62, base], [x + w * 0.62, base - h * 0.45], [x + w * 0.38, base - h * 0.45]], Color(0.5, 0.3, 0.2))
	var win := Color(1.0, 0.9, 0.45) if lit else Color(0.6, 0.8, 1.0)
	pic._poly([[x + w * 0.15, base - h * 0.85], [x + w * 0.35, base - h * 0.85], [x + w * 0.35, base - h * 0.6], [x + w * 0.15, base - h * 0.6]], win)
	pic._poly([[x + w * 0.65, base - h * 0.85], [x + w * 0.85, base - h * 0.85], [x + w * 0.85, base - h * 0.6], [x + w * 0.65, base - h * 0.6]], win)


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
		"kitten":  # Kit: a grey kitten face with pointy ears and whiskers
			var fur := Color(0.62, 0.64, 0.7)
			pic._poly([[0.22, 0.42 + bob], [0.26, 0.14 + bob], [0.44, 0.3 + bob]], fur)
			pic._poly([[0.78, 0.42 + bob], [0.74, 0.14 + bob], [0.56, 0.3 + bob]], fur)
			pic._poly([[0.27, 0.36 + bob], [0.28, 0.22 + bob], [0.38, 0.31 + bob]], Color(1.0, 0.75, 0.8))
			pic._poly([[0.73, 0.36 + bob], [0.72, 0.22 + bob], [0.62, 0.31 + bob]], Color(1.0, 0.75, 0.8))
			pic._circle(0.5, 0.52 + bob, 0.27, fur)
			pic._circle(0.5, 0.64 + bob, 0.12, Color(0.95, 0.95, 0.97))
			var blink := 0.015 if fmod(t, 3.0) < 0.15 else 0.055
			pic._eye(0.4, 0.48 + bob, blink)
			pic._eye(0.6, 0.48 + bob, blink)
			pic._poly([[0.47, 0.58 + bob], [0.53, 0.58 + bob], [0.5, 0.62 + bob]], Color(1.0, 0.5, 0.6))
			for s in [-1.0, 1.0]:
				pic._poly([[0.5 + s * 0.1, 0.62 + bob], [0.5 + s * 0.32, 0.58 + bob], [0.5 + s * 0.32, 0.6 + bob]], Color(0.3, 0.3, 0.35))
				pic._poly([[0.5 + s * 0.1, 0.64 + bob], [0.5 + s * 0.32, 0.67 + bob], [0.5 + s * 0.32, 0.69 + bob]], Color(0.3, 0.3, 0.35))
		"hedgehog":  # Spike: a round spiky back, a pointy cream face, a black nose
			var spike := Color(0.38, 0.26, 0.18)
			for k in 9:
				var a := PI + PI * (k + 0.5) / 9.0
				var cx := 0.55 + cos(a) * 0.26
				var cy := 0.6 + sin(a) * 0.26 + bob
				pic._poly([[cx - 0.05, cy + 0.04], [cx + 0.05, cy + 0.04], [0.55 + cos(a) * 0.4, 0.6 + sin(a) * 0.4 + bob]], spike)
			pic._circle(0.55, 0.6 + bob, 0.27, spike.lightened(0.1))
			pic._poly([[0.42, 0.45 + bob], [0.42, 0.78 + bob], [0.1, 0.66 + bob]], Color(0.96, 0.86, 0.7))
			pic._circle(0.11, 0.66 + bob, 0.035, Color(0.1, 0.08, 0.08))
			pic._eye(0.3, 0.58 + bob, 0.04)
			pic._circle(0.4, 0.86, 0.04, Color(0.3, 0.2, 0.15))
			pic._circle(0.65, 0.86, 0.04, Color(0.3, 0.2, 0.15))
		"owl":  # Hoot: a round brown owl, big eyes, ear tufts, an orange beak
			var fur := Color(0.62, 0.45, 0.3)
			pic._poly([[0.26, 0.3 + bob], [0.3, 0.12 + bob], [0.4, 0.26 + bob]], fur)
			pic._poly([[0.74, 0.3 + bob], [0.7, 0.12 + bob], [0.6, 0.26 + bob]], fur)
			pic._circle(0.5, 0.52 + bob, 0.3, fur)
			pic._circle(0.5, 0.64 + bob, 0.18, Color(0.96, 0.9, 0.78))
			pic._circle(0.39, 0.42 + bob, 0.1, Color(1, 1, 1))
			pic._circle(0.61, 0.42 + bob, 0.1, Color(1, 1, 1))
			var blink := 0.015 if fmod(t, 2.6) < 0.15 else 0.055
			pic._eye(0.39, 0.42 + bob, blink)
			pic._eye(0.61, 0.42 + bob, blink)
			pic._poly([[0.46, 0.5 + bob], [0.54, 0.5 + bob], [0.5, 0.58 + bob]], Color(1.0, 0.65, 0.2))
		"tortoise":  # Tess: a green domed shell with a pattern, a smiling head poking out
			pic._circle(0.82, 0.62 + bob, 0.09, Color(0.75, 0.6, 0.35))
			pic._eye(0.84, 0.6 + bob, 0.025)
			pic._poly([[0.12, 0.72 + bob], [0.78, 0.72 + bob], [0.72, 0.5 + bob], [0.6, 0.38 + bob], [0.45, 0.34 + bob], [0.3, 0.38 + bob], [0.18, 0.5 + bob]], Color(0.35, 0.6, 0.3))
			for c in [[0.3, 0.56], [0.45, 0.48], [0.6, 0.56], [0.45, 0.63]]:
				pic._circle(float(c[0]), float(c[1]) + bob, 0.06, Color(0.5, 0.78, 0.4))
			for x in [0.22, 0.65]:
				pic._poly([[x, 0.72 + bob], [x + 0.08, 0.72 + bob], [x + 0.08, 0.82], [x, 0.82]], Color(0.75, 0.6, 0.35))
		"hamster":  # Pom: a round golden hamster with puffy cheeks
			var fur := Color(0.95, 0.72, 0.4)
			pic._circle(0.32, 0.3 + bob, 0.07, fur)
			pic._circle(0.68, 0.3 + bob, 0.07, fur)
			pic._circle(0.32, 0.3 + bob, 0.04, Color(1.0, 0.75, 0.8))
			pic._circle(0.68, 0.3 + bob, 0.04, Color(1.0, 0.75, 0.8))
			pic._circle(0.5, 0.55 + bob, 0.3, fur)
			var puff := 0.11 + sin(t * 3.0) * 0.01
			pic._circle(0.3, 0.62 + bob, puff, Color(1.0, 0.94, 0.84))
			pic._circle(0.7, 0.62 + bob, puff, Color(1.0, 0.94, 0.84))
			pic._eye(0.41, 0.5 + bob, 0.05)
			pic._eye(0.59, 0.5 + bob, 0.05)
			pic._circle(0.5, 0.6 + bob, 0.03, Color(1.0, 0.5, 0.6))
		"street":  # Pip's street: a row of little houses, the one in the middle lit up
			pic._poly([[0.0, 0.8], [1.0, 0.8], [1.0, 0.9], [0.0, 0.9]], Color(0.55, 0.55, 0.6))
			for k in 4:
				pic._poly([[0.06 + k * 0.26, 0.845], [0.16 + k * 0.26, 0.845], [0.16 + k * 0.26, 0.86], [0.06 + k * 0.26, 0.86]], Color(1, 1, 1))
			_house(pic, 0.04, 0.26, 0.3, Color(0.95, 0.75, 0.6), Color(0.8, 0.3, 0.3), false)
			_house(pic, 0.37, 0.26, 0.38 + bob * 0.2, Color(0.8, 0.88, 1.0), Color(0.3, 0.45, 0.8), true)
			_house(pic, 0.7, 0.26, 0.3, Color(0.85, 0.95, 0.75), Color(0.35, 0.6, 0.35), false)
		"gardenparty":  # Pip's garden party: a picnic blanket, a cake, flags overhead
			pic._poly([[0.0, 0.62], [1.0, 0.62], [1.0, 1.0], [0.0, 1.0]], Color(0.45, 0.75, 0.38))
			pic._poly([[0.15, 0.68], [0.85, 0.68], [0.95, 0.92], [0.05, 0.92]], Color(0.95, 0.35, 0.35))
			for k in 4:
				pic._poly([[0.18 + k * 0.18, 0.7], [0.27 + k * 0.18, 0.7], [0.3 + k * 0.18, 0.9], [0.2 + k * 0.18, 0.9]], Color(1, 1, 1, 0.6))
			pic._poly([[0.4, 0.74], [0.6, 0.74], [0.6, 0.62], [0.4, 0.62]], Color(1.0, 0.85, 0.9))
			pic._poly([[0.4, 0.62], [0.6, 0.62], [0.6, 0.6], [0.4, 0.6]], Color(0.95, 0.4, 0.6))
			pic._poly([[0.49, 0.6], [0.51, 0.6], [0.51, 0.52], [0.49, 0.52]], Color(1, 1, 1))
			pic._circle(0.5, 0.5 + sin(t * 9.0) * 0.005, 0.02, Color(1.0, 0.8, 0.2))
			var cols := [Color(1.0, 0.4, 0.4), Color(1.0, 0.85, 0.3), Color(0.4, 0.7, 1.0), Color(0.5, 0.9, 0.5)]
			for k in 7:
				var x := 0.08 + k * 0.13
				var y := 0.14 + absf(x - 0.5) * 0.12
				pic._poly([[x, y], [x + 0.1, y], [x + 0.05, y + 0.12 + bob * 0.3]], cols[k % 4])
			pic._circle(0.12, 0.42 + bob, 0.08, Color(0.95, 0.72, 0.42))
			pic._circle(0.88, 0.42 - bob, 0.08, Color(0.92, 0.9, 0.88))
		"darkroom":  # the dark room: dark walls, two glowing eyes, a torch beam
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.1, 0.1, 0.2))
			var a := 0.3 + sin(t * 1.5) * 0.08
			pic._poly([[0.05, 0.9], [0.14, 0.82], [0.5 + a, 0.25], [0.5 + a + 0.25, 0.5]], Color(1.0, 0.95, 0.6, 0.35))
			pic._poly([[0.02, 0.92], [0.1, 0.84], [0.17, 0.9], [0.1, 0.98]], Color(0.9, 0.3, 0.3))
			if fmod(t, 2.5) > 0.15:
				pic._circle(0.38, 0.45 + bob, 0.05, Color(1.0, 0.95, 0.5))
				pic._circle(0.54, 0.45 + bob, 0.05, Color(1.0, 0.95, 0.5))
				pic._circle(0.38, 0.45 + bob, 0.02, Color(0.1, 0.1, 0.1))
				pic._circle(0.54, 0.45 + bob, 0.02, Color(0.1, 0.1, 0.1))
		"pawprints":  # a sneaky friend: little paw prints tiptoeing across
			var n := int(fmod(t * 2.0, 6.0)) + 1
			for k in n:
				var x := 0.12 + k * 0.15
				var y := 0.62 - k * 0.07 + (0.06 if k % 2 == 0 else -0.06)
				pic._circle(x, y + bob, 0.05, color)
				for d in [-1.0, 0.0, 1.0]:
					pic._circle(x + d * 0.04, y - 0.06 + absf(d) * 0.015 + bob, 0.02, color)
		"hoover":  # Rumble the robot hoover: a round blue robot with big friendly eyes and a brush skirt
			var roll := sin(t * 3.0) * 0.03
			pic._poly([[0.12, 0.8], [0.88, 0.8], [0.84, 0.86], [0.16, 0.86]], Color(0.3, 0.3, 0.35))
			pic._circle(0.5 + roll, 0.6 + bob, 0.3, Color(0.25, 0.75, 0.95))
			pic._poly([[0.22 + roll, 0.68 + bob], [0.78 + roll, 0.68 + bob], [0.74 + roll, 0.76 + bob], [0.26 + roll, 0.76 + bob]], Color(0.15, 0.35, 0.55))
			pic._eye(0.4 + roll, 0.52 + bob, 0.07)
			pic._eye(0.6 + roll, 0.52 + bob, 0.07)
			pic._circle(0.5 + roll, 0.3 + bob, 0.04, Color(1.0, 0.35, 0.3) if fmod(t, 1.0) < 0.5 else Color(1.0, 0.85, 0.3))
			pic._poly([[0.49 + roll, 0.3 + bob], [0.51 + roll, 0.3 + bob], [0.51 + roll, 0.36 + bob], [0.49 + roll, 0.36 + bob]], Color(0.3, 0.3, 0.35))
			for k in 5:
				var x := 0.12 + k * 0.19 + fmod(t * 0.3, 0.19)
				pic._circle(x, 0.9, 0.025, Color(0.85, 0.85, 0.9, 0.7))
		"pepper":  # the pepper pot tipping a sneezy cloud
			pic._poly([[0.3, 0.85], [0.56, 0.85], [0.6, 0.45], [0.26, 0.45]], Color(0.92, 0.9, 0.86))
			pic._poly([[0.26, 0.45], [0.6, 0.45], [0.55, 0.32], [0.31, 0.32]], Color(0.75, 0.75, 0.8))
			pic._circle(0.37, 0.4, 0.02, Color(0.2, 0.2, 0.2))
			pic._circle(0.49, 0.4, 0.02, Color(0.2, 0.2, 0.2))
			pic._poly([[0.36, 0.62], [0.5, 0.62], [0.5, 0.7], [0.36, 0.7]], Color(1.0, 0.45, 0.2))
			for k in 6:
				var a := t * 1.5 + k * 1.05
				pic._circle(0.68 + cos(a) * 0.12, 0.25 + sin(a) * 0.08 + bob, 0.04 + 0.015 * (k % 3), Color(0.55, 0.4, 0.3, 0.75))
		"nose":  # SUPER NOSE: a big pink sniffing nose with sniff lines
			pic._circle(0.5, 0.55 + bob, 0.24, Color(1.0, 0.55, 0.7))
			pic._circle(0.42, 0.62 + bob, 0.06, Color(0.55, 0.2, 0.3))
			pic._circle(0.58, 0.62 + bob, 0.06, Color(0.55, 0.2, 0.3))
			pic._circle(0.44, 0.45 + bob, 0.05, Color(1.0, 0.8, 0.85))
			var s := fmod(t * 1.2, 1.0)
			for k in 3:
				var y := 0.22 + k * 0.1
				pic._poly([[0.08 + s * 0.1, y], [0.22 + s * 0.1, y - 0.02], [0.22 + s * 0.1, y + 0.02]], Color(1, 1, 1, 0.8 - s * 0.5))
				pic._poly([[0.92 - s * 0.1, y], [0.78 - s * 0.1, y - 0.02], [0.78 - s * 0.1, y + 0.02]], Color(1, 1, 1, 0.8 - s * 0.5))
		"hanky":  # HANKY: a spotty hanky waving (no sneezing!)
			var wv := sin(t * 3.0) * 0.04
			pic._poly([[0.2, 0.25 + wv], [0.8, 0.2 - wv], [0.84, 0.8 + wv], [0.18, 0.78 - wv]], color)
			for k in 4:
				pic._circle(0.32 + (k % 2) * 0.34, 0.38 + (k / 2) * 0.3 + bob, 0.05, Color(1, 1, 1, 0.85))
			pic._poly([[0.2, 0.25 + wv], [0.8, 0.2 - wv], [0.8, 0.24 - wv], [0.2, 0.29 + wv]], Color(1, 1, 1, 0.6))
		"kennel":  # Pip's kennel: a red roof, a round door and a flag that waves
			pic._poly([[0.0, 0.85], [1.0, 0.85], [1.0, 1.0], [0.0, 1.0]], Color(0.45, 0.75, 0.38))
			pic._poly([[0.2, 0.85], [0.8, 0.85], [0.8, 0.5], [0.2, 0.5]], Color(0.75, 0.5, 0.3))
			pic._poly([[0.12, 0.52], [0.88, 0.52], [0.5, 0.22]], Color(0.85, 0.25, 0.25))
			pic._circle(0.5, 0.72, 0.12, Color(0.2, 0.12, 0.08))
			pic._poly([[0.38, 0.85], [0.62, 0.85], [0.62, 0.72], [0.38, 0.72]], Color(0.2, 0.12, 0.08))
			pic._poly([[0.49, 0.22], [0.51, 0.22], [0.51, 0.06], [0.49, 0.06]], Color(0.4, 0.3, 0.2))
			pic._poly([[0.51, 0.06], [0.66, 0.1 + sin(t * 4.0) * 0.02], [0.51, 0.14]], Color(1.0, 0.85, 0.3))
			pic._circle(0.5, 0.74 + bob, 0.05, Color(0.95, 0.72, 0.42))
