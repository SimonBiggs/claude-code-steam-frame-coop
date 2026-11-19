extends RefCounted
## Sky Bots' story card pictures. core/story_pictures.gd finds this file by itself. Drawn in a unit box (y down):
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), t = the
## picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["gizmo", "skylamp", "skyspark", "goldgear", "crankycrab", "grumble", "zappad", "liftpad",
	"skyisland", "meadowisle", "gearisle", "coveisle", "skybot", "boltnut", "snowisle", "jungleisle", "clockisle", "kingkeywind",
	"springpad", "windfan", "beltpad", "tinybot", "botbox", "hattop", "hatcrown", "hatflower", "hatpirate", "hatchef", "hatbunny",
	"hatparty", "hatwizard"]


static func _gear(pic, cx: float, cy: float, r: float, col: Color, spin: float) -> void:
	var pts := []
	for i in 32:
		var a := TAU * float(i) / 32.0 + spin
		var rr := r * (1.0 if (i / 2) % 2 == 0 else 0.78)
		pts.append([cx + cos(a) * rr, cy + sin(a) * rr])
	pic._poly(pts, col)
	pic._circle(cx, cy, r * 0.32, col.darkened(0.45))


static func _isle(pic, bob: float, top: Color) -> void:
	pic._poly([[0.12, 0.58 + bob], [0.88, 0.58 + bob], [0.62, 0.92 + bob], [0.5, 0.97 + bob], [0.38, 0.92 + bob]], Color(0.55, 0.45, 0.4))
	pic._poly([[0.1, 0.52 + bob], [0.9, 0.52 + bob], [0.9, 0.6 + bob], [0.1, 0.6 + bob]], top)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"gizmo":  # Granny Gizmo: a teal teapot robot with a pink lid, glasses and a spout
			var teal := Color(0.45, 0.82, 0.85)
			var pts := []
			for i in 24:
				var a := TAU * float(i) / 24.0
				pts.append([0.5 + cos(a) * 0.3, 0.6 + bob + sin(a) * 0.26])
			pic._poly(pts, teal)
			pic._poly([[0.78, 0.6 + bob], [0.95, 0.38 + bob], [0.98, 0.42 + bob], [0.82, 0.68 + bob]], teal.darkened(0.1))
			pic.draw_arc(pic._p(0.2, 0.6 + bob), pic.size.x * 0.1, PI * 0.5, PI * 1.5, 12, teal.darkened(0.15), 4.0)
			pic._poly([[0.3, 0.36 + bob], [0.7, 0.36 + bob], [0.64, 0.28 + bob], [0.36, 0.28 + bob]], Color(1.0, 0.6, 0.7))
			pic._circle(0.5, 0.25 + bob, 0.04, Color(1.0, 0.85, 0.3))
			pic._poly([[0.32, 0.48 + bob], [0.68, 0.48 + bob], [0.68, 0.62 + bob], [0.32, 0.62 + bob]], Color(0.12, 0.15, 0.22))
			pic._circle(0.42, 0.55 + bob, 0.035, Color(0.45, 1.0, 0.95))
			pic._circle(0.58, 0.55 + bob, 0.035, Color(0.45, 1.0, 0.95))
			pic.draw_arc(pic._p(0.42, 0.55 + bob), pic.size.x * 0.06, 0, TAU, 14, Color(1.0, 0.85, 0.3), 2.0)
			pic.draw_arc(pic._p(0.58, 0.55 + bob), pic.size.x * 0.06, 0, TAU, 14, Color(1.0, 0.85, 0.3), 2.0)
		"skylamp":  # the Sky Lamp: a striped tower with a glowing lamp
			var glow := 0.5 + 0.5 * sin(t * 3.0)
			pic._circle(0.5, 0.22 + bob, 0.2 + glow * 0.04, Color(0.55, 0.95, 1.0, 0.35))
			pic._circle(0.5, 0.22 + bob, 0.12, Color(0.6, 0.97, 1.0))
			for k in 5:
				var y0 := 0.36 + k * 0.12
				pic._poly([[0.4 - k * 0.012, y0 + bob], [0.6 + k * 0.012, y0 + bob], [0.61 + k * 0.012, y0 + 0.12 + bob], [0.39 - k * 0.012, y0 + 0.12 + bob]],
					Color(0.95, 0.95, 0.98) if k % 2 == 0 else Color(0.35, 0.65, 1.0))
			pic._poly([[0.38, 0.12 + bob], [0.62, 0.12 + bob], [0.5, 0.02 + bob]], Color(0.35, 0.65, 1.0))
		"skyspark":  # a spark: a glowing lightning crystal
			var j := sin(t * 6.0) * 0.02
			pic._circle(0.5, 0.5 + bob, 0.3, Color(0.55, 0.95, 1.0, 0.3))
			pic._poly([[0.58 + j, 0.12 + bob], [0.3, 0.52 + bob], [0.48, 0.52 + bob], [0.4 - j, 0.9 + bob], [0.72, 0.44 + bob], [0.54, 0.44 + bob]], Color(0.6, 0.97, 1.0))
		"goldgear":  # a gold gear, spinning
			_gear(pic, 0.5, 0.52 + bob, 0.3, Color(1.0, 0.75, 0.15), t * 0.8)
		"crankycrab":  # Cranky Crab: an orange crab with cross eyebrows and snapping claws
			var crab := Color(1.0, 0.45, 0.3)
			var snap := absf(sin(t * 4.0)) * 0.05
			var pts := []
			for i in 20:
				var a := TAU * float(i) / 20.0
				pts.append([0.5 + cos(a) * 0.28, 0.62 + bob + sin(a) * 0.18])
			pic._poly(pts, crab)
			for s in [-1.0, 1.0]:
				pic._circle(0.5 + s * 0.38, 0.42 + bob, 0.1, crab)
				pic._poly([[0.5 + s * 0.38, 0.42 + bob], [0.5 + s * 0.5, 0.3 + bob - snap], [0.5 + s * 0.46, 0.42 + bob]], Color(0.95, 0.95, 0.95))
				pic.draw_line(pic._p(0.5 + s * 0.1, 0.48 + bob), pic._p(0.5 + s * 0.12, 0.3 + bob), crab, 4.0)
				pic._eye(0.5 + s * 0.12, 0.28 + bob, 0.06)
				pic.draw_line(pic._p(0.5 + s * 0.04, 0.2 + bob), pic._p(0.5 + s * 0.2, 0.24 + bob), Color(0.25, 0.1, 0.08), 3.0)
				for k in 3:
					pic.draw_line(pic._p(0.5 + s * 0.22, 0.68 + k * 0.05 + bob), pic._p(0.5 + s * 0.36, 0.76 + k * 0.05 + bob), crab.darkened(0.15), 3.0)
		"grumble":  # a grumpy red wind-up box bot
			var g := Color(0.85, 0.3, 0.32)
			var wob := sin(t * 10.0) * 0.015
			pic._poly([[0.22 + wob, 0.32 + bob], [0.78 + wob, 0.32 + bob], [0.78, 0.8 + bob], [0.22, 0.8 + bob]], g)
			pic._poly([[0.3, 0.45 + bob], [0.7, 0.45 + bob], [0.7, 0.6 + bob], [0.3, 0.6 + bob]], Color(0.12, 0.1, 0.12))
			pic._circle(0.4, 0.53 + bob, 0.04, Color(1.0, 0.9, 0.3))
			pic._circle(0.6, 0.53 + bob, 0.04, Color(1.0, 0.9, 0.3))
			pic.draw_line(pic._p(0.32, 0.38 + bob), pic._p(0.46, 0.43 + bob), Color(0.12, 0.1, 0.12), 3.0)
			pic.draw_line(pic._p(0.68, 0.38 + bob), pic._p(0.54, 0.43 + bob), Color(0.12, 0.1, 0.12), 3.0)
			pic._poly([[0.44, 0.2 + bob], [0.56, 0.2 + bob], [0.56, 0.32 + bob], [0.44, 0.32 + bob]], Color(0.8, 0.8, 0.85))
			pic._circle(0.3, 0.84 + bob, 0.06, Color(0.2, 0.2, 0.22))
			pic._circle(0.7, 0.84 + bob, 0.06, Color(0.2, 0.2, 0.22))
		"zappad":  # a zap pad with a flashing ring and a little bolt
			var on := fmod(t * 2.0, 1.0) < 0.5
			pic._circle(0.5, 0.62 + bob, 0.34, Color(1.0, 0.95, 0.2, 0.55 if on else 0.2))
			pic._circle(0.5, 0.62 + bob, 0.22, Color(0.32, 0.34, 0.4))
			pic._poly([[0.54, 0.38 + bob], [0.42, 0.62 + bob], [0.5, 0.62 + bob], [0.46, 0.84 + bob], [0.6, 0.56 + bob], [0.52, 0.56 + bob]], Color(1.0, 0.95, 0.3))
		"liftpad":  # a purple lift going up, with its yellow handle
			var up := fmod(t * 0.5, 1.0) * 0.2
			pic.draw_line(pic._p(0.5, 0.1), pic._p(0.5, 0.92), Color(0.8, 0.8, 0.85, 0.5), 3.0)
			pic._poly([[0.2, 0.62 - up], [0.8, 0.62 - up], [0.8, 0.72 - up], [0.2, 0.72 - up]], Color(0.62, 0.45, 0.95))
			pic._circle(0.84, 0.55 - up, 0.06, Color(1.0, 0.86, 0.25))
			pic._poly([[0.42, 0.3], [0.58, 0.3], [0.5, 0.16]], Color(1.0, 0.86, 0.25))
		"skyisland", "meadowisle", "gearisle", "coveisle", "snowisle", "jungleisle", "clockisle":  # a floating island
			var top := {"skyisland": Color(0.6, 0.85, 1.0), "meadowisle": Color(0.42, 0.76, 0.34), "gearisle": Color(0.5, 0.58, 0.7),
				"coveisle": Color(0.93, 0.82, 0.58), "snowisle": Color(0.92, 0.95, 1.0), "jungleisle": Color(0.3, 0.6, 0.42),
				"clockisle": Color(0.62, 0.45, 0.56)}[kind] as Color
			_isle(pic, bob, top)
			match kind:
				"meadowisle":
					pic._circle(0.35, 0.4 + bob, 0.1, Color(0.3, 0.65, 0.3))
					pic.draw_line(pic._p(0.35, 0.44 + bob), pic._p(0.35, 0.52 + bob), Color(0.5, 0.35, 0.2), 4.0)
					pic._circle(0.65, 0.48 + bob, 0.04, Color(1.0, 0.5, 0.6))
				"gearisle":
					_gear(pic, 0.5, 0.36 + bob, 0.14, Color(0.75, 0.8, 0.9), t)
				"coveisle":
					pic._circle(0.5, 0.42 + bob, 0.09, Color(1.0, 0.45, 0.3))
					pic._eye(0.46, 0.34 + bob, 0.03)
					pic._eye(0.54, 0.34 + bob, 0.03)
				"snowisle":  # a snowy mountain
					pic._poly([[0.22, 0.52 + bob], [0.5, 0.14 + bob], [0.78, 0.52 + bob]], Color(0.55, 0.62, 0.78))
					pic._poly([[0.4, 0.28 + bob], [0.5, 0.14 + bob], [0.6, 0.28 + bob], [0.55, 0.32 + bob], [0.5, 0.27 + bob], [0.45, 0.32 + bob]], Color(0.97, 0.98, 1.0))
				"jungleisle":  # a palm tree with big leaves
					pic.draw_line(pic._p(0.5, 0.52 + bob), pic._p(0.46, 0.26 + bob), Color(0.55, 0.38, 0.22), 6.0)
					for a in [-2.6, -1.9, -1.2, -0.5]:
						pic._poly([[0.46, 0.26 + bob], [0.46 + cos(a) * 0.24, 0.26 + sin(a) * 0.1 + 0.08 + bob], [0.46 + cos(a) * 0.12, 0.3 + bob]], Color(0.25, 0.7, 0.35))
				"clockisle":  # a clock face with turning hands
					pic._circle(0.5, 0.34 + bob, 0.15, Color(0.97, 0.95, 0.88))
					pic.draw_arc(pic._p(0.5, 0.34 + bob), pic.size.x * 0.15, 0, TAU, 20, Color(0.72, 0.56, 0.3), 4.0)
					pic.draw_line(pic._p(0.5, 0.34 + bob), pic._p(0.5 + cos(t) * 0.11, 0.34 + sin(t) * 0.11 + bob), Color(0.15, 0.15, 0.2), 3.0)
					pic.draw_line(pic._p(0.5, 0.34 + bob), pic._p(0.5 + cos(t * 0.2) * 0.07, 0.34 + sin(t * 0.2) * 0.07 + bob), Color(0.15, 0.15, 0.2), 4.0)
				_:
					pic._poly([[0.5, 0.18 + bob], [0.56, 0.32 + bob], [0.7, 0.33 + bob], [0.59, 0.42 + bob], [0.63, 0.56 - 0.1 + bob],
						[0.5, 0.4 + bob], [0.37, 0.46 + bob], [0.41, 0.42 + bob], [0.3, 0.33 + bob], [0.44, 0.32 + bob]], Color(1.0, 0.9, 0.35))
		"skybot":  # a little robot with a propeller cap, in the card's colour
			var spin := sin(t * 20.0) * 0.08  # (never past the cap's half width: the quad would cross itself)
			pic._poly([[0.5 - 0.12 - spin, 0.14 + bob], [0.5 + 0.12 + spin, 0.14 + bob], [0.5 + 0.12 + spin, 0.17 + bob], [0.5 - 0.12 - spin, 0.17 + bob]], color.lightened(0.3))
			pic.draw_line(pic._p(0.5, 0.17 + bob), pic._p(0.5, 0.24 + bob), Color(0.6, 0.62, 0.66), 3.0)
			pic._poly([[0.3, 0.24 + bob], [0.7, 0.24 + bob], [0.7, 0.5 + bob], [0.3, 0.5 + bob]], Color(0.86, 0.89, 0.93))
			pic._poly([[0.35, 0.3 + bob], [0.65, 0.3 + bob], [0.65, 0.44 + bob], [0.35, 0.44 + bob]], Color(0.1, 0.14, 0.22))
			pic._circle(0.44, 0.37 + bob, 0.035, Color(0.45, 1.0, 0.95))
			pic._circle(0.56, 0.37 + bob, 0.035, Color(0.45, 1.0, 0.95))
			pic._poly([[0.28, 0.52 + bob], [0.72, 0.52 + bob], [0.72, 0.84 + bob], [0.28, 0.84 + bob]], color)
			pic._circle(0.22, 0.66 + bob, 0.06, color)
			pic._circle(0.78, 0.66 + bob, 0.06, color)
		"kingkeywind":  # King Keywind: a purple tin king with a gold crown, a moustache and a turning wind-up key
			var kc := Color(0.55, 0.4, 0.9)
			var turn := sin(t * 3.0) * 0.06
			pic._poly([[0.62, 0.5 + bob], [0.9, 0.42 + bob - turn], [0.9, 0.62 + bob + turn], [0.62, 0.56 + bob]], Color(1.0, 0.82, 0.3))
			pic._poly([[0.25, 0.36 + bob], [0.75, 0.36 + bob], [0.78, 0.9 + bob], [0.22, 0.9 + bob]], kc)
			pic._poly([[0.3, 0.42 + bob], [0.7, 0.42 + bob], [0.7, 0.58 + bob], [0.3, 0.58 + bob]], Color(0.12, 0.12, 0.2))
			pic._circle(0.41, 0.5 + bob, 0.04, Color(1.0, 0.95, 0.5))
			pic._circle(0.59, 0.5 + bob, 0.04, Color(1.0, 0.95, 0.5))
			pic.draw_line(pic._p(0.34, 0.44 + bob), pic._p(0.46, 0.47 + bob), Color(0.95, 0.95, 0.95), 3.0)
			pic.draw_line(pic._p(0.66, 0.44 + bob), pic._p(0.54, 0.47 + bob), Color(0.95, 0.95, 0.95), 3.0)
			pic._poly([[0.36, 0.64 + bob], [0.5, 0.6 + bob], [0.64, 0.64 + bob], [0.5, 0.68 + bob]], Color(0.97, 0.97, 0.97))
			pic._poly([[0.28, 0.36 + bob], [0.3, 0.16 + bob], [0.4, 0.28 + bob], [0.5, 0.12 + bob], [0.6, 0.28 + bob], [0.7, 0.16 + bob], [0.72, 0.36 + bob]], Color(1.0, 0.82, 0.3))
		"springpad":  # a pink spring pad, squashing and throwing a little star up
			var sq := absf(sin(t * 3.0))
			for k in 4:
				var y := 0.82 - k * (0.08 + sq * 0.04)
				pic._poly([[0.3, y + bob], [0.7, y - 0.03 + bob], [0.7, y - 0.01 + bob], [0.3, y + 0.02 + bob]], Color(1.0, 0.3, 0.55))
			var ty := 0.82 - 4.0 * (0.08 + sq * 0.04)
			pic._poly([[0.24, ty + bob], [0.76, ty + bob], [0.76, ty - 0.06 + bob], [0.24, ty - 0.06 + bob]], Color(0.97, 0.97, 1.0))
			pic._circle(0.5, ty - 0.2 - sq * 0.15 + bob, 0.06, Color(1.0, 0.85, 0.3))
		"windfan":  # a wind fan blowing puffs up
			pic._circle(0.5, 0.78 + bob, 0.2, Color(0.85, 0.87, 0.92))
			for k in 4:
				var a := t * 6.0 + TAU * k / 4.0
				pic._poly([[0.5, 0.78 + bob], [0.5 + cos(a) * 0.17, 0.78 + sin(a) * 0.06 + bob], [0.5 + cos(a + 0.5) * 0.17, 0.78 + sin(a + 0.5) * 0.06 + bob]], Color(0.4, 0.85, 1.0))
			for k in 3:
				var up := fmod(t * 0.6 + k / 3.0, 1.0)
				pic._circle(0.35 + k * 0.15, 0.6 - up * 0.45 + bob, 0.05 + up * 0.03, Color(1, 1, 1, 0.9 - up * 0.6))
		"beltpad":  # a conveyor belt with arrows running along
			pic._poly([[0.1, 0.5 + bob], [0.9, 0.5 + bob], [0.9, 0.66 + bob], [0.1, 0.66 + bob]], Color(0.22, 0.22, 0.27))
			pic._circle(0.1, 0.58 + bob, 0.08, Color(0.6, 0.62, 0.7))
			pic._circle(0.9, 0.58 + bob, 0.08, Color(0.6, 0.62, 0.7))
			for k in 3:
				var x := 0.18 + fmod(t * 0.15 + k * 0.25, 0.64)
				pic._poly([[x, 0.53 + bob], [x + 0.07, 0.58 + bob], [x, 0.63 + bob]], Color(1.0, 0.78, 0.2))
		"tinybot":  # a little bot waving
			var wave := sin(t * 6.0) * 0.08
			pic._poly([[0.36, 0.56 + bob], [0.64, 0.56 + bob], [0.64, 0.84 + bob], [0.36, 0.84 + bob]], Color(0.5, 0.85, 1.0))
			pic._circle(0.5, 0.42 + bob, 0.17, Color(0.88, 0.9, 0.95))
			pic._poly([[0.38, 0.37 + bob], [0.62, 0.37 + bob], [0.62, 0.48 + bob], [0.38, 0.48 + bob]], Color(0.1, 0.14, 0.22))
			pic._circle(0.45, 0.42 + bob, 0.03, Color(0.45, 1.0, 0.95))
			pic._circle(0.55, 0.42 + bob, 0.03, Color(0.45, 1.0, 0.95))
			pic.draw_line(pic._p(0.5, 0.25 + bob), pic._p(0.5, 0.16 + bob), Color(0.6, 0.62, 0.66), 3.0)
			pic._circle(0.5, 0.15 + bob, 0.035, Color(1.0, 0.6, 0.8))
			pic.draw_line(pic._p(0.64, 0.62 + bob), pic._p(0.8, 0.48 + bob + wave), Color(0.5, 0.85, 1.0), 5.0)
		"botbox":  # an orange crate with a window: a little bot peeks out
			pic._poly([[0.22, 0.3 + bob], [0.78, 0.3 + bob], [0.78, 0.86 + bob], [0.22, 0.86 + bob]], Color(0.95, 0.55, 0.2))
			pic._poly([[0.22, 0.36 + bob], [0.78, 0.36 + bob], [0.78, 0.4 + bob], [0.22, 0.4 + bob]], Color(0.7, 0.38, 0.12))
			pic._poly([[0.22, 0.76 + bob], [0.78, 0.76 + bob], [0.78, 0.8 + bob], [0.22, 0.8 + bob]], Color(0.7, 0.38, 0.12))
			pic._circle(0.5, 0.58 + bob, 0.13, Color(0.6, 0.85, 1.0))
			pic._circle(0.46, 0.58 + bob, 0.025, Color(0.1, 0.14, 0.22))
			pic._circle(0.54, 0.58 + bob, 0.025, Color(0.1, 0.14, 0.22))
			var tw := absf(sin(t * 4.0))
			pic._circle(0.5, 0.2 + bob, 0.04 + tw * 0.03, Color(1.0, 0.9, 0.35))
		"hattop", "hatcrown", "hatflower", "hatpirate", "hatchef", "hatbunny", "hatparty", "hatwizard":  # a costume hat
			match kind:
				"hattop":
					pic._poly([[0.2, 0.72 + bob], [0.8, 0.72 + bob], [0.8, 0.78 + bob], [0.2, 0.78 + bob]], Color(0.15, 0.15, 0.2))
					pic._poly([[0.32, 0.3 + bob], [0.68, 0.3 + bob], [0.68, 0.72 + bob], [0.32, 0.72 + bob]], Color(0.15, 0.15, 0.2))
					pic._poly([[0.32, 0.6 + bob], [0.68, 0.6 + bob], [0.68, 0.67 + bob], [0.32, 0.67 + bob]], Color(0.9, 0.3, 0.35))
				"hatcrown":
					pic._poly([[0.22, 0.75 + bob], [0.22, 0.35 + bob], [0.36, 0.55 + bob], [0.5, 0.3 + bob], [0.64, 0.55 + bob], [0.78, 0.35 + bob], [0.78, 0.75 + bob]], Color(1.0, 0.8, 0.2))
					pic._circle(0.5, 0.65 + bob, 0.05, Color(0.9, 0.2, 0.4))
				"hatflower":
					for k in 6:
						var a := TAU * k / 6.0 + t * 0.5
						pic._circle(0.5 + cos(a) * 0.16, 0.5 + sin(a) * 0.16 + bob, 0.1, Color(1.0, 0.55, 0.75))
					pic._circle(0.5, 0.5 + bob, 0.09, Color(1.0, 0.85, 0.3))
				"hatpirate":
					pic._poly([[0.12, 0.62 + bob], [0.3, 0.4 + bob], [0.5, 0.32 + bob], [0.7, 0.4 + bob], [0.88, 0.62 + bob], [0.5, 0.7 + bob]], Color(0.18, 0.15, 0.15))
					pic._circle(0.5, 0.5 + bob, 0.06, Color(0.95, 0.95, 0.95))
				"hatchef":
					pic._poly([[0.34, 0.5 + bob], [0.66, 0.5 + bob], [0.66, 0.78 + bob], [0.34, 0.78 + bob]], Color(0.97, 0.97, 0.97))
					pic._circle(0.38, 0.42 + bob, 0.12, Color(0.97, 0.97, 0.97))
					pic._circle(0.5, 0.36 + bob, 0.14, Color(0.97, 0.97, 0.97))
					pic._circle(0.62, 0.42 + bob, 0.12, Color(0.97, 0.97, 0.97))
				"hatbunny":
					for s in [-1.0, 1.0]:
						pic._poly([[0.5 + s * 0.08, 0.8 + bob], [0.5 + s * 0.1, 0.2 + bob], [0.5 + s * 0.24, 0.24 + bob], [0.5 + s * 0.2, 0.8 + bob]], Color(0.97, 0.95, 0.97))
						pic._poly([[0.5 + s * 0.12, 0.7 + bob], [0.5 + s * 0.13, 0.3 + bob], [0.5 + s * 0.19, 0.32 + bob], [0.5 + s * 0.17, 0.7 + bob]], Color(1.0, 0.65, 0.75))
				"hatparty":
					pic._poly([[0.3, 0.8 + bob], [0.5, 0.2 + bob], [0.7, 0.8 + bob]], Color(0.4, 0.75, 1.0))
					pic._circle(0.5, 0.2 + bob, 0.06, Color(1.0, 0.85, 0.3))
					pic._circle(0.45, 0.55 + bob, 0.04, Color(1.0, 0.45, 0.6))
					pic._circle(0.56, 0.68 + bob, 0.04, Color(0.6, 1.0, 0.5))
				"hatwizard":
					pic._poly([[0.14, 0.78 + bob], [0.86, 0.78 + bob], [0.8, 0.84 + bob], [0.2, 0.84 + bob]], Color(0.35, 0.3, 0.75))
					pic._poly([[0.3, 0.78 + bob], [0.56, 0.14 + bob], [0.7, 0.78 + bob]], Color(0.35, 0.3, 0.75))
					pic._circle(0.52, 0.55 + bob, 0.05, Color(1.0, 0.9, 0.35))
		"boltnut":  # a gold bolt nut
			var pts := []
			for i in 6:
				var a := TAU * float(i) / 6.0 + t * 0.5
				pts.append([0.5 + cos(a) * 0.3, 0.52 + bob + sin(a) * 0.3])
			pic._poly(pts, Color(1.0, 0.8, 0.25))
			pic._circle(0.5, 0.52 + bob, 0.12, Color(0.55, 0.42, 0.15))
