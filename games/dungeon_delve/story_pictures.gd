extends RefCounted
## Dungeon Delve's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["cinder", "hoard", "friend", "rumble", "soot", "soot_happy", "healer_ring"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"cinder":  # Cinder: a round little orange baby dragon who keeps the dungeon's treasure, puffing smoke rings
			var body := Color(1.0, 0.55, 0.2)
			var belly := Color(1.0, 0.88, 0.6)
			var flap := sin(t * 8.0) * 0.06
			pic._poly([[0.36, 0.5 + bob], [0.12, 0.26 + bob - flap], [0.2, 0.46 + bob], [0.08, 0.5 + bob - flap * 0.5], [0.3, 0.62 + bob]], Color(0.95, 0.35, 0.3))
			pic._poly([[0.3, 0.78 + bob], [0.06, 0.86 + bob], [0.02, 0.76 + bob], [0.26, 0.68 + bob]], body.darkened(0.15))
			pic._poly([[0.02, 0.76 + bob], [0.0, 0.68 + bob], [0.08, 0.74 + bob]], Color(0.95, 0.35, 0.3))
			pic._circle(0.45, 0.66 + bob, 0.22, body)
			pic._circle(0.5, 0.71 + bob, 0.13, belly)
			pic._circle(0.64, 0.4 + bob, 0.19, body)
			pic._circle(0.76, 0.47 + bob, 0.1, body.lightened(0.1))
			pic._circle(0.8, 0.44 + bob, 0.018, Color(0.45, 0.2, 0.1))
			pic._poly([[0.54, 0.26 + bob], [0.5, 0.12 + bob], [0.6, 0.23 + bob]], belly)
			pic._poly([[0.66, 0.23 + bob], [0.68, 0.09 + bob], [0.74, 0.25 + bob]], belly)
			pic._eye(0.66, 0.37 + bob, 0.065)
			pic._circle(0.62, 0.47 + bob, 0.03, Color(1.0, 0.5, 0.55, 0.7))
			pic.draw_arc(pic._p(0.74, 0.5 + bob), 0.05 * size.x, 0.2, 2.6, 10, Color(0.45, 0.2, 0.1), 0.012 * size.x)
			for x in [0.36, 0.54]:
				pic._circle(x, 0.88 + bob * 0.5, 0.055, body.darkened(0.15))
			for k in 2:  # smoke rings drifting up from the nose
				var f := fmod(t * 0.5 + k * 0.5, 1.0)
				pic.draw_arc(pic._p(0.86 + f * 0.08, 0.36 - f * 0.28), (0.03 + f * 0.04) * size.x, 0.0, TAU, 16,
					Color(0.85, 0.85, 0.9, 0.8 * (1.0 - f)), 0.014 * size.x)
			pic._circle(0.2, 0.9, 0.04 + 0.01 * sin(t * 4.0), color.lightened(0.3))
		"soot":  # Soot, Cinder's grumpy big purple cousin who took her treasure (story.gd)
			_soot(pic, kind, t, bob, size)
		"soot_happy":  # Soot after the ending: a big smile and little hearts
			_soot(pic, kind, t, bob, size)
		"healer_ring":  # the HEALER hero's heal ring: a pink heart in a spreading soft green ring, little "+" sparkles
			var f := fmod(t * 0.8, 1.0)
			pic.draw_arc(pic._p(0.5, 0.55), (0.18 + 0.28 * f) * size.x, 0.0, TAU, 32, Color(0.45, 1.0, 0.55, 1.0 - f), 0.03 * size.x)
			pic.draw_arc(pic._p(0.5, 0.55), 0.34 * size.x, 0.0, TAU, 32, Color(0.45, 1.0, 0.55, 0.5), 0.02 * size.x)
			var hc := Color(1.0, 0.45, 0.65)
			var hy := 0.5 + bob
			pic._circle(0.42, hy, 0.1, hc)
			pic._circle(0.58, hy, 0.1, hc)
			pic._poly([[0.31, hy + 0.04], [0.69, hy + 0.04], [0.5, hy + 0.27]], hc)
			pic._circle(0.39, hy - 0.03, 0.035, Color(1.0, 0.8, 0.88))
			for k in 3:  # "+" sparkles floating up
				var g := fmod(t * 0.6 + k * 0.33, 1.0)
				var sx := 0.2 + 0.3 * k
				var sy := 0.35 - 0.25 * g
				var sc := Color(0.6, 1.0, 0.65, 1.0 - g)
				pic.draw_line(pic._p(sx - 0.03, sy), pic._p(sx + 0.03, sy), sc, 0.015 * size.x)
				pic.draw_line(pic._p(sx, sy - 0.03), pic._p(sx, sy + 0.03), sc, 0.015 * size.x)
		"hoard":  # Cinder's hoard: a glittering heap of gold coins with gems, growing as the family plays
			var gold := Color(1.0, 0.8, 0.28)
			pic._poly([[0.1, 0.86], [0.5, 0.42 + bob * 0.3], [0.9, 0.86]], gold.darkened(0.2))
			for k in 9:
				var x := 0.22 + 0.07 * k
				var y := 0.8 - 0.22 * (1.0 - absf(x - 0.5) / 0.32) + bob * 0.3
				pic._circle(x, y, 0.06, gold)
				pic._circle(x - 0.015, y - 0.015, 0.025, gold.lightened(0.4))
			pic._poly([[0.42, 0.5 + bob], [0.48, 0.42 + bob], [0.54, 0.5 + bob], [0.48, 0.58 + bob]], Color(0.4, 0.95, 1.0))
			pic._poly([[0.62, 0.62 + bob], [0.67, 0.56 + bob], [0.72, 0.62 + bob], [0.67, 0.68 + bob]], Color(1.0, 0.4, 0.6))
			for k2 in 3:  # sparkles
				var f := fmod(t * 0.8 + k2 * 0.33, 1.0)
				pic._circle(0.3 + 0.2 * k2, 0.35 - 0.1 * f, 0.02 * (1.0 - f), Color(1.0, 1.0, 0.8, 1.0 - f))
		"friend":  # one of Cinder's lost friends hopping out of its open gold cage, hearts popping (color = the friend)
			var gold := Color(1.0, 0.8, 0.3)
			for k in 5:  # the cage's bars, lifted up and away
				var x := 0.22 + 0.14 * k
				pic.draw_line(pic._p(x, 0.02), pic._p(x, 0.3), gold, 0.025 * size.x)
			pic.draw_line(pic._p(0.18, 0.3), pic._p(0.82, 0.3), gold, 0.03 * size.x)
			pic._poly([[0.12, 0.92], [0.88, 0.92], [0.84, 0.86], [0.16, 0.86]], gold.darkened(0.3))
			var hop := -absf(sin(t * 5.0)) * 0.08
			pic._circle(0.5, 0.66 + hop, 0.2, color)
			pic._circle(0.36, 0.48 + hop, 0.07, color.darkened(0.1))
			pic._circle(0.64, 0.48 + hop, 0.07, color.darkened(0.1))
			pic._circle(0.5, 0.72 + hop, 0.11, color.lightened(0.35))
			pic._eye(0.43, 0.6 + hop, 0.045)
			pic._eye(0.57, 0.6 + hop, 0.045)
			pic.draw_arc(pic._p(0.5, 0.69 + hop), 0.05 * size.x, 0.3, 2.8, 10, Color(0.35, 0.15, 0.1), 0.014 * size.x)
			for k2 in 3:  # hearts floating up
				var f := fmod(t * 0.7 + k2 * 0.33, 1.0)
				var hx := 0.2 + 0.3 * k2
				var hy := 0.55 - 0.4 * f
				var hc := Color(1.0, 0.35, 0.45, 1.0 - f)
				pic._circle(hx - 0.02, hy, 0.025, hc)
				pic._circle(hx + 0.02, hy, 0.025, hc)
				pic._poly([[hx - 0.045, hy + 0.01], [hx + 0.045, hy + 0.01], [hx, hy + 0.06]], hc)
		"rumble":  # a rumbly ceiling: a rock falling onto a flashing orange circle on the floor
			var ring := Color(1.0, 0.35, 0.2)
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 0.12], [0.8, 0.16], [0.6, 0.1], [0.4, 0.17], [0.2, 0.11], [0.0, 0.15]], Color(0.4, 0.36, 0.42))
			var flash := 0.55 + 0.45 * absf(sin(t * 6.0))
			pic.draw_set_transform(pic._p(0.5, 0.82), 0.0, Vector2(1.0, 0.35))
			pic.draw_circle(Vector2.ZERO, 0.3 * size.x, Color(ring.r, ring.g, ring.b, 0.45 * flash))
			pic.draw_arc(Vector2.ZERO, 0.3 * size.x, 0.0, TAU, 32, ring, 0.03 * size.x)
			pic.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var fall := fmod(t * 0.6, 1.0)
			var ry := 0.22 + 0.5 * fall * fall
			pic._circle(0.5, ry, 0.09, Color(0.62, 0.58, 0.55))
			pic._circle(0.54, ry - 0.03, 0.04, Color(0.75, 0.72, 0.7))
			for k3 in 3:  # little crumbs shaken loose
				pic._circle(0.3 + 0.2 * k3, 0.2 + fmod(t * 0.9 + k3 * 0.3, 1.0) * 0.3, 0.015, Color(0.55, 0.5, 0.5))

## Soot, Cinder's big purple cousin (story.gd): grumpy brows, or a big happy smile after the ending.
static func _soot(pic, kind: String, t: float, bob: float, size: Vector2) -> void:
	var body := Color(0.55, 0.4, 0.85)
	var belly := Color(0.85, 0.78, 1.0)
	var happy := kind == "soot_happy"
	var flap := sin(t * (8.0 if happy else 4.0)) * 0.06
	pic._poly([[0.36, 0.5 + bob], [0.08, 0.2 + bob - flap], [0.18, 0.44 + bob], [0.04, 0.48 + bob - flap * 0.5], [0.3, 0.62 + bob]], Color(0.35, 0.25, 0.6))
	pic._poly([[0.3, 0.78 + bob], [0.06, 0.86 + bob], [0.02, 0.76 + bob], [0.26, 0.68 + bob]], body.darkened(0.15))
	pic._circle(0.45, 0.66 + bob, 0.24, body)
	pic._circle(0.5, 0.72 + bob, 0.14, belly)
	pic._circle(0.64, 0.4 + bob, 0.2, body)
	pic._circle(0.77, 0.47 + bob, 0.11, body.lightened(0.1))
	pic._poly([[0.54, 0.25 + bob], [0.48, 0.08 + bob], [0.6, 0.22 + bob]], belly)
	pic._poly([[0.67, 0.22 + bob], [0.7, 0.05 + bob], [0.75, 0.24 + bob]], belly)
	pic._eye(0.66, 0.37 + bob, 0.065)
	if happy:
		pic.draw_arc(pic._p(0.74, 0.48 + bob), 0.07 * size.x, 0.2, 2.9, 12, Color(0.25, 0.12, 0.3), 0.016 * size.x)
		pic._circle(0.6, 0.48 + bob, 0.035, Color(1.0, 0.55, 0.7, 0.75))
		for k in 3:  # little hearts: he's got friends now
			var f := fmod(t * 0.7 + k * 0.33, 1.0)
			var hc := Color(1.0, 0.4, 0.6, 1.0 - f)
			pic._circle(0.86 + 0.02 * k, 0.3 - 0.25 * f, 0.022, hc)
	else:
		pic.draw_line(pic._p(0.58, 0.29 + bob), pic._p(0.72, 0.33 + bob), Color(0.2, 0.1, 0.25), 0.025 * size.x)  # a cross brow
		pic.draw_arc(pic._p(0.75, 0.54 + bob), 0.05 * size.x, 3.5, 5.9, 10, Color(0.25, 0.12, 0.3), 0.014 * size.x)  # a pout
		for k in 2:  # grumpy smoke puffs
			var f2 := fmod(t * 0.5 + k * 0.5, 1.0)
			pic._circle(0.88 + f2 * 0.06, 0.4 - f2 * 0.3, 0.025 + f2 * 0.03, Color(0.5, 0.45, 0.55, 0.8 * (1.0 - f2)))
	for x in [0.36, 0.54]:
		pic._circle(x, 0.9 + bob * 0.5, 0.06, body.darkened(0.15))
