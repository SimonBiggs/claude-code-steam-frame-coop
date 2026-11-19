extends RefCounted
## Marble Maze's story card pictures (Bobo's gift marbles, worlds.gd MARBLES). core/story_pictures.gd finds this file
## by itself. Drawn in a unit box: pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) /
## pic.draw_*(...), size = pic.size, t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["heavymarble", "bouncymarble", "magnetmarble", "stickymarble", "zoomymarble",
	"mmmagnet", "mmclock", "mmwarp", "mmisland", "mmpinball", "mmcup", "mmwatch"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	if kind.begins_with("mm"):
		_draw_place(pic, kind, t, bob, color)
		return
	var cols := {"heavymarble": Color(0.62, 0.68, 0.8), "bouncymarble": Color(1.0, 0.45, 0.8), "magnetmarble": Color(1.0, 0.3, 0.3),
		"stickymarble": Color(0.55, 0.95, 0.3), "zoomymarble": Color(1.0, 0.75, 0.15)}
	var c: Color = cols.get(kind, color)
	var x := 0.5
	var y := 0.55 + bob
	var r := 0.27
	match kind:
		"heavymarble":
			y = 0.6
			pic._poly([[0.12, 0.9], [0.88, 0.9], [0.88, 0.95], [0.12, 0.95]], Color(0.45, 0.35, 0.25))
			for i in 3:  # thud lines
				var lx := 0.2 + i * 0.3
				pic.draw_line(pic._p(lx - 0.04, 0.84), pic._p(lx + 0.04, 0.78), Color(0.3, 0.3, 0.35), 0.02 * size.x)
		"bouncymarble":
			var h := absf(sin(t * 3.0))
			y = 0.72 - h * 0.3
			pic.draw_arc(pic._p(0.5, 0.95), 0.22 * size.x, PI, TAU, 16, Color(1.0, 0.75, 0.9), 0.02 * size.x)
		"magnetmarble":
			x = 0.62
			# A red / silver horseshoe magnet on the left, pulling.
			pic.draw_arc(pic._p(0.2, 0.55), 0.13 * size.x, PI * 0.5, PI * 1.5, 16, Color(0.9, 0.15, 0.15), 0.07 * size.x)
			pic._poly([[0.19, 0.38], [0.29, 0.38], [0.29, 0.46], [0.19, 0.46]], Color(0.85, 0.85, 0.9))
			pic._poly([[0.19, 0.64], [0.29, 0.64], [0.29, 0.72], [0.19, 0.72]], Color(0.85, 0.85, 0.9))
			for i in 3:
				var a := fmod(t * 0.8 + i / 3.0, 1.0)
				pic.draw_arc(pic._p(0.33 + a * 0.05, 0.55), (0.04 + a * 0.06) * size.x, -0.8, 0.8, 8, Color(1.0, 0.9, 0.3, 1.0 - a), 0.012 * size.x)
		"stickymarble":
			for i in 3:  # drips
				var dx := 0.38 + i * 0.12
				var dl := 0.08 + 0.04 * sin(t * 2.0 + i)
				pic._poly([[dx - 0.025, y + 0.18], [dx + 0.025, y + 0.18], [dx + 0.02, y + 0.24 + dl], [dx - 0.02, y + 0.24 + dl]], c.darkened(0.15))
				pic._circle(dx, y + 0.24 + dl, 0.03, c.darkened(0.15))
		"zoomymarble":
			x = 0.58
			for i in 3:  # speed lines
				var ly := y - 0.14 + i * 0.14
				var off := fmod(t * 2.0 + i * 0.3, 1.0) * 0.06
				pic.draw_line(pic._p(0.08 + off, ly), pic._p(0.3 + off, ly), Color(1.0, 1.0, 1.0, 0.85), 0.025 * size.x)
	pic._circle(x, y, r, c)
	pic._circle(x - r * 0.35, y - r * 0.38, r * 0.28, c.lightened(0.55))  # shine
	if kind == "heavymarble":
		pic._poly([[x - r, y - 0.03], [x + r, y - 0.03], [x + r * 0.97, y + 0.04], [x - r * 0.97, y + 0.04]], c.darkened(0.35))
	pic._eye(x - 0.08, y + 0.02, 0.045)
	pic._eye(x + 0.08, y + 0.02, 0.045)
	pic.draw_arc(pic._p(x, y + 0.1), 0.06 * size.x, 0.3, PI - 0.3, 10, Color(0.3, 0.1, 0.12), 0.02 * size.x)


## Third pass: the new places' and the race's pictures.
static func _draw_place(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var w := 0.02 * size.x
	match kind:
		"mmmagnet":  # a red horseshoe magnet pulling a little marble
			pic.draw_arc(pic._p(0.42, 0.5 + bob), 0.2 * size.x, PI * 0.5, PI * 1.5, 20, Color(0.9, 0.15, 0.15), 0.11 * size.x)
			pic._poly([[0.38, 0.22 + bob], [0.52, 0.22 + bob], [0.52, 0.34 + bob], [0.38, 0.34 + bob]], Color(0.9, 0.9, 0.95))
			pic._poly([[0.38, 0.66 + bob], [0.52, 0.66 + bob], [0.52, 0.78 + bob], [0.38, 0.78 + bob]], Color(0.9, 0.9, 0.95))
			var mx := 0.8 - fmod(t * 0.3, 1.0) * 0.18
			pic._circle(mx, 0.5, 0.08, Color(0.3, 0.6, 1.0))
			pic._circle(mx - 0.025, 0.47, 0.025, Color(0.75, 0.88, 1.0))
		"mmclock":  # a clock face with ticking hands
			pic._circle(0.5, 0.52 + bob, 0.34, Color(1.0, 0.6, 0.15))
			pic._circle(0.5, 0.52 + bob, 0.28, Color(1, 1, 0.95))
			for k in 12:
				var a := k * TAU / 12.0
				pic._circle(0.5 + cos(a) * 0.23, 0.52 + bob + sin(a) * 0.23, 0.015, Color(0.2, 0.2, 0.25))
			var ah := t * 1.5
			pic.draw_line(pic._p(0.5, 0.52 + bob), pic._p(0.5 + sin(ah) * 0.2, 0.52 + bob - cos(ah) * 0.2), Color(0.15, 0.15, 0.2), w * 1.5)
			pic.draw_line(pic._p(0.5, 0.52 + bob), pic._p(0.5 + sin(ah / 12.0) * 0.13, 0.52 + bob - cos(ah / 12.0) * 0.13), Color(0.15, 0.15, 0.2), w * 2.0)
		"mmwarp":  # a swirly purple warp hole
			for k in 4:
				var rr := 0.34 - k * 0.07
				pic.draw_arc(pic._p(0.5, 0.55 + bob), rr * size.x, t * (2.0 + k) + k, t * (2.0 + k) + k + PI * 1.4, 18,
					Color(0.75, 0.4, 1.0).lerp(Color(0.3, 0.1, 0.5), k / 4.0), 0.05 * size.x)
			pic._circle(0.5, 0.55 + bob, 0.07, Color(0.15, 0.05, 0.25))
		"mmisland":  # a floating island with a plank and a cloud
			pic._poly([[0.15, 0.55 + bob], [0.6, 0.55 + bob], [0.45, 0.8 + bob], [0.3, 0.8 + bob]], Color(0.55, 0.42, 0.3))
			pic._poly([[0.15, 0.5 + bob], [0.6, 0.5 + bob], [0.6, 0.56 + bob], [0.15, 0.56 + bob]], Color(0.45, 0.8, 0.4))
			pic._poly([[0.6, 0.51 + bob], [0.9, 0.51 + bob], [0.9, 0.54 + bob], [0.6, 0.54 + bob]], Color(0.75, 0.55, 0.32))
			for k in 3:
				pic._circle(0.62 + k * 0.08, 0.22 + (k % 2) * 0.03, 0.07, Color(1, 1, 1))
			pic._circle(0.35, 0.44 + bob, 0.06, Color(1.0, 0.3, 0.3))
		"mmpinball":  # bumpers and a marble bouncing between them
			for k in 3:
				var bx := 0.25 + k * 0.25
				var by := 0.6 if k % 2 == 0 else 0.4
				pic._circle(bx, by + bob, 0.1, Color(1.0, 0.3, 0.6))
				pic._circle(bx, by + bob, 0.05, Color(1.0, 0.95, 0.4))
			var f := fmod(t * 0.7, 1.0)
			pic._circle(0.15 + f * 0.7, 0.25 + absf(sin(f * TAU * 1.5)) * 0.15, 0.06, Color(0.3, 0.6, 1.0))
		"mmcup":  # a trophy cup in the card's colour (gold / silver / bronze)
			pic._poly([[0.28, 0.25 + bob], [0.72, 0.25 + bob], [0.62, 0.55 + bob], [0.38, 0.55 + bob]], color)
			pic.draw_arc(pic._p(0.27, 0.36 + bob), 0.08 * size.x, PI * 0.5, PI * 1.5, 12, color.darkened(0.15), 0.035 * size.x)
			pic.draw_arc(pic._p(0.73, 0.36 + bob), 0.08 * size.x, -PI * 0.5, PI * 0.5, 12, color.darkened(0.15), 0.035 * size.x)
			pic._poly([[0.46, 0.55 + bob], [0.54, 0.55 + bob], [0.54, 0.7 + bob], [0.46, 0.7 + bob]], color.darkened(0.2))
			pic._poly([[0.34, 0.7 + bob], [0.66, 0.7 + bob], [0.66, 0.78 + bob], [0.34, 0.78 + bob]], color.darkened(0.3))
			pic._circle(0.4, 0.33 + bob, 0.035, color.lightened(0.6))
		"mmwatch":  # a stopwatch, its hand sweeping
			pic._poly([[0.45, 0.12 + bob], [0.55, 0.12 + bob], [0.55, 0.2 + bob], [0.45, 0.2 + bob]], Color(1.0, 0.8, 0.25))
			pic._circle(0.5, 0.55 + bob, 0.33, Color(1.0, 0.8, 0.25))
			pic._circle(0.5, 0.55 + bob, 0.27, Color(1, 1, 0.95))
			var a2 := t * 3.0
			pic.draw_line(pic._p(0.5, 0.55 + bob), pic._p(0.5 + sin(a2) * 0.22, 0.55 + bob - cos(a2) * 0.22), Color(0.9, 0.2, 0.2), w * 1.5)
			pic._circle(0.5, 0.55 + bob, 0.03, Color(0.15, 0.15, 0.2))
