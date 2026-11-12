extends RefCounted
## Duo Arena's story card pictures (core/story_pictures.gd finds this file by itself). Drawn in a unit box:
## pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r); t = the picture's clock, bob = its gentle bob,
## color = the card's colour (Color.WHITE = the picture's own colours).
## NOVA is the arena's little light-bot: the monsters dimmed Neon City, and every wave the family clears lights a
## city light again (zone.gd pylons; GROWS "neoncity").

const NAMES: Array[String] = ["nova", "neoncity", "junglezone", "lavazone", "icezone", "starzone", "orbking", "kingrex",
	"omegaorb", "blasterhero", "sprayhero", "boomhero", "tankhero", "zoomhero",
	"sproutbot", "emberbot", "flurrybot", "cometbot", "novazap", "fallcrate", "lightpark"]

const NOVA := Color(0.35, 0.85, 1.0)
const DARK := Color(0.08, 0.09, 0.16)
const FRIEND_LOOKS := {"sproutbot": [Color(0.45, 1.0, 0.5), 0], "emberbot": [Color(1.0, 0.55, 0.25), 1],
	"flurrybot": [Color(0.8, 0.95, 1.0), 2], "cometbot": [Color(1.0, 0.85, 0.35), 3]}
const HERO_GUNS := {"blasterhero": 0, "sprayhero": 1, "boomhero": 2, "tankhero": 3, "zoomhero": 4}


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"nova":  # a round little light-bot: a glowing screen face, an antenna with a star, tiny jet flames
			var c := NOVA if color == Color.WHITE else NOVA.lerp(color, 0.3)
			var fl := 0.03 * sin(t * 12.0)
			pic._poly([[0.42, 0.82 + bob], [0.58, 0.82 + bob], [0.5, 0.97 + fl + bob]], Color(1.0, 0.6, 0.2))
			pic._poly([[0.47, 0.82 + bob], [0.53, 0.82 + bob], [0.5, 0.9 + fl + bob]], Color(1.0, 0.95, 0.5))
			pic._poly([[0.49, 0.22 + bob], [0.51, 0.22 + bob], [0.51, 0.08 + bob], [0.49, 0.08 + bob]], Color(0.8, 0.85, 0.95))
			pic._circle(0.5, 0.07 + bob, 0.045, Color(1.0, 0.9, 0.3).lightened(0.2 * absf(sin(t * 4.0))))
			pic._circle(0.5, 0.52 + bob, 0.32, c)
			pic._circle(0.5, 0.52 + bob, 0.27, c.lightened(0.25))
			pic._circle(0.5, 0.5 + bob, 0.2, DARK)
			pic._circle(0.42, 0.47 + bob, 0.045, NOVA.lightened(0.5))
			pic._circle(0.58, 0.47 + bob, 0.045, NOVA.lightened(0.5))
			pic._poly([[0.42, 0.57 + bob], [0.58, 0.57 + bob], [0.5, 0.62 + bob]], NOVA.lightened(0.5))
			pic._circle(0.17, 0.55 + bob, 0.06, c)
			pic._circle(0.83, 0.55 + bob, 0.06, c)
		"neoncity":  # night towers with lit windows (more light as the family plays)
			var c := NOVA if color == Color.WHITE else color
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.06, 0.05, 0.16))
			var hs := [0.45, 0.7, 0.35, 0.82, 0.55, 0.4]
			for k in 6:
				var x0 := 0.04 + k * 0.16
				var top := 1.0 - float(hs[k])
				pic._poly([[x0, 1.0], [x0 + 0.13, 1.0], [x0 + 0.13, top], [x0, top]], Color(0.15, 0.15, 0.28))
				for row in int(float(hs[k]) * 8.0):
					var lit := (k * 3 + row) % 3 != 0
					pic._poly([[x0 + 0.03, top + 0.05 + row * 0.1], [x0 + 0.1, top + 0.05 + row * 0.1],
						[x0 + 0.1, top + 0.09 + row * 0.1], [x0 + 0.03, top + 0.09 + row * 0.1]],
						c if lit else Color(0.1, 0.1, 0.2))
			pic._circle(0.82, 0.14 + bob * 0.3, 0.07, Color(1.0, 0.95, 0.8))
		"junglezone":  # palm leaves, a mud geyser and a little dino
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.1, 0.25, 0.12))
			pic._poly([[0.0, 0.82], [1.0, 0.82], [1.0, 1.0], [0.0, 1.0]], Color(0.3, 0.5, 0.2))
			for k in 5:
				var a := -1.2 + k * 0.6
				pic._poly([[0.22, 0.3], [0.22 + cos(a) * 0.22, 0.3 + sin(a) * 0.1 + 0.08], [0.22 + cos(a) * 0.2, 0.3 + sin(a) * 0.1 + 0.02]], Color(0.3, 0.8, 0.3))
			pic._poly([[0.2, 0.3], [0.24, 0.3], [0.26, 0.84], [0.18, 0.84]], Color(0.5, 0.35, 0.2))
			var g := 0.1 * absf(sin(t * 2.0))
			pic._poly([[0.62, 0.82], [0.74, 0.82], [0.7, 0.45 - g], [0.66, 0.45 - g]], Color(0.6, 0.5, 0.3))
			pic._circle(0.68, 0.45 - g + bob, 0.07, Color(0.65, 0.55, 0.35))
			pic._circle(0.88, 0.72, 0.07, Color(0.35, 0.85, 0.3))
			pic._circle(0.92, 0.66, 0.045, Color(0.35, 0.85, 0.3))
			pic._eye(0.93, 0.65, 0.015)
		"lavazone":  # a dark rim, glowing lava and a bubbling vent
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.2, 0.06, 0.05))
			pic._poly([[0.0, 0.7], [0.3, 0.55], [0.5, 0.62], [0.7, 0.5], [1.0, 0.65], [1.0, 1.0], [0.0, 1.0]], Color(0.3, 0.12, 0.1))
			pic._poly([[0.0, 0.85], [1.0, 0.8], [1.0, 1.0], [0.0, 1.0]], Color(1.0, 0.4, 0.05))
			for k in 3:
				var y := 0.8 - fmod(t * 0.3 + k * 0.33, 1.0) * 0.5
				pic._circle(0.3 + k * 0.2, y, 0.035, Color(1.0, 0.6, 0.15))
			pic._circle(0.5, 0.82, 0.12, Color(1.0, 0.75, 0.2))
		"icezone":  # an icy rink, snowflakes and a frost puff
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.2, 0.3, 0.5))
			pic._poly([[0.0, 0.7], [1.0, 0.7], [1.0, 1.0], [0.0, 1.0]], Color(0.75, 0.9, 1.0))
			pic._poly([[0.2, 0.8], [0.45, 0.78], [0.42, 0.82], [0.22, 0.83]], Color(1.0, 1.0, 1.0))
			for k in 5:
				var x := 0.12 + k * 0.19
				var y := fmod(t * 0.15 + k * 0.21, 0.6)
				pic._circle(x, y + 0.05, 0.025, Color.WHITE)
			pic._circle(0.7, 0.62 + bob, 0.1, Color(0.9, 0.97, 1.0))
			pic._circle(0.78, 0.56 + bob, 0.08, Color(0.9, 0.97, 1.0))
		"starzone":  # a deck floating in space with stars and a zap pad
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.05, 0.03, 0.12))
			for k in 9:
				var tw := 0.5 + 0.5 * sin(t * 3.0 + k)
				pic._circle(fmod(k * 0.37, 1.0), fmod(k * 0.23, 0.6), 0.012 + 0.01 * tw, Color(1.0, 1.0, 0.9))
			pic._poly([[0.05, 0.78], [0.95, 0.78], [0.85, 0.9], [0.15, 0.9]], Color(0.35, 0.3, 0.5))
			pic._circle(0.5, 0.8, 0.09 + 0.02 * sin(t * 8.0), Color(0.85, 0.5, 1.0))
			pic._circle(0.75, 0.3 + bob, 0.12, Color(0.6, 0.4, 0.9))
		"orbking":  # the ORB OVERLORD: a big pink orb with a crown and a cross face
			var c := Color(1.0, 0.2, 0.6) if color == Color.WHITE else color
			pic._circle(0.5, 0.58 + bob, 0.32, c)
			pic._circle(0.42, 0.5 + bob, 0.08, c.lightened(0.4))
			pic._poly([[0.3, 0.32 + bob], [0.35, 0.16 + bob], [0.43, 0.27 + bob], [0.5, 0.12 + bob], [0.57, 0.27 + bob], [0.65, 0.16 + bob], [0.7, 0.32 + bob]], Color(1.0, 0.82, 0.25))
			pic._eye(0.4, 0.56 + bob, 0.05)
			pic._eye(0.6, 0.56 + bob, 0.05)
			pic._poly([[0.33, 0.47 + bob], [0.46, 0.51 + bob], [0.45, 0.48 + bob]], DARK)
			pic._poly([[0.67, 0.47 + bob], [0.54, 0.51 + bob], [0.55, 0.48 + bob]], DARK)
			pic._poly([[0.42, 0.72 + bob], [0.58, 0.72 + bob], [0.5, 0.68 + bob]], DARK)
		"kingrex":  # KING REX: a big red dino head with a crown and teeth
			var c := Color(0.95, 0.25, 0.3) if color == Color.WHITE else color
			var jaw := 0.04 * absf(sin(t * 3.0))
			pic._poly([[0.12, 0.45 + bob], [0.75, 0.35 + bob], [0.9, 0.5 + bob], [0.85, 0.6 + bob], [0.15, 0.65 + bob]], c)
			pic._poly([[0.2, 0.66 + bob + jaw], [0.82, 0.62 + bob + jaw], [0.75, 0.78 + bob + jaw], [0.25, 0.8 + bob + jaw]], c.darkened(0.2))
			for k in 5:
				pic._poly([[0.3 + k * 0.1, 0.64 + bob], [0.36 + k * 0.1, 0.64 + bob], [0.33 + k * 0.1, 0.71 + bob]], Color.WHITE)
			pic._eye(0.6, 0.45 + bob, 0.05)
			pic._poly([[0.35, 0.37 + bob], [0.4, 0.2 + bob], [0.48, 0.32 + bob], [0.55, 0.18 + bob], [0.62, 0.3 + bob], [0.68, 0.2 + bob], [0.7, 0.36 + bob]], Color(1.0, 0.82, 0.25))
		"omegaorb":  # the OMEGA OVERLORD: a golden orb with rings round it
			var c := Color(1.0, 0.78, 0.2) if color == Color.WHITE else color
			for k in 3:
				var a := t * 1.5 + k * TAU / 3.0
				pic._circle(0.5 + cos(a) * 0.4, 0.55 + sin(a) * 0.12 + bob, 0.05, Color(1.0, 0.4, 0.6))
			pic._circle(0.5, 0.55 + bob, 0.3, c)
			pic._circle(0.42, 0.47 + bob, 0.07, c.lightened(0.4))
			pic._eye(0.4, 0.55 + bob, 0.055)
			pic._eye(0.6, 0.55 + bob, 0.055)
			pic._poly([[0.38, 0.7 + bob], [0.62, 0.7 + bob], [0.5, 0.76 + bob]], DARK)
		"blasterhero", "sprayhero", "boomhero", "tankhero", "zoomhero":
			_hero(pic, int(HERO_GUNS[kind]), t, bob, color)
		"sproutbot", "emberbot", "flurrybot", "cometbot":
			_friend(pic, FRIEND_LOOKS[kind][0] if color == Color.WHITE else color, int(FRIEND_LOOKS[kind][1]), t, bob)
		"novazap":  # Nova zapping a little monster with a light bolt
			pic._circle(0.28, 0.35 + bob, 0.17, NOVA)
			pic._circle(0.28, 0.35 + bob, 0.11, DARK)
			pic._circle(0.25, 0.33 + bob, 0.025, NOVA.lightened(0.5))
			pic._circle(0.32, 0.33 + bob, 0.025, NOVA.lightened(0.5))
			var zz := 0.02 * sin(t * 20.0)
			pic._poly([[0.42, 0.42 + bob], [0.58, 0.5 + zz], [0.52, 0.55], [0.72, 0.68 + zz], [0.56, 0.58], [0.6, 0.52 - zz], [0.44, 0.46 + bob]], Color(1.0, 0.95, 0.45))
			pic._circle(0.78, 0.74, 0.14, Color(0.6, 0.3, 0.8))
			pic._eye(0.74, 0.72, 0.03)
			pic._eye(0.83, 0.72, 0.03)
			for k in 4:
				var a := t * 3.0 + k * PI * 0.5
				pic._circle(0.78 + cos(a) * 0.2, 0.74 + sin(a) * 0.2, 0.02, Color(1.0, 1.0, 0.7))
		"fallcrate":  # a wooden crate falling into a ring on the floor
			pic._poly([[0.1, 0.84], [0.9, 0.84], [0.8, 0.94], [0.2, 0.94]], Color(1.0, 0.6, 0.1, 0.6))
			var y := fmod(t * 0.5, 1.0) * 0.4 + bob
			pic._poly([[0.32, 0.2 + y], [0.68, 0.2 + y], [0.68, 0.52 + y], [0.32, 0.52 + y]], Color(0.75, 0.5, 0.25))
			pic._poly([[0.32, 0.2 + y], [0.68, 0.52 + y], [0.64, 0.52 + y], [0.32, 0.24 + y]], Color(0.55, 0.35, 0.15))
			pic._poly([[0.3, 0.33 + y], [0.7, 0.33 + y], [0.7, 0.37 + y], [0.3, 0.37 + y]], Color(0.55, 0.35, 0.15))
		"lightpark":  # Nova's city growing: new towers with bright windows and the friends' round houses
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.06, 0.05, 0.16))
			var hs := [0.5, 0.75, 0.6]
			for k in 3:
				var x0 := 0.08 + k * 0.3
				var top := 0.9 - float(hs[k])
				pic._poly([[x0, 0.9], [x0 + 0.18, 0.9], [x0 + 0.18, top], [x0, top]], Color(0.18, 0.2, 0.35))
				for row in 4:
					pic._poly([[x0 + 0.04, top + 0.06 + row * 0.1], [x0 + 0.14, top + 0.06 + row * 0.1],
						[x0 + 0.14, top + 0.1 + row * 0.1], [x0 + 0.04, top + 0.1 + row * 0.1]], NOVA.lightened(0.2 * absf(sin(t * 2.0 + row + k))))
			var cs := [Color(0.45, 1.0, 0.5), Color(1.0, 0.55, 0.25), Color(0.8, 0.95, 1.0), Color(1.0, 0.85, 0.35)]
			for k in 4:
				pic._circle(0.14 + k * 0.24, 0.95, 0.09, cs[k])
				pic._circle(0.14 + k * 0.24, 0.8 + bob * (1.0 if k % 2 == 0 else -1.0), 0.04, cs[k].lightened(0.3))
		_:
			pic._circle(0.5, 0.5, 0.3, color)


## One of Nova's friends: a round light-bot like her in its own colour, with its sign on top (0 a leaf, 1 a flame,
## 2 a snowflake, 3 a star with a tail).
static func _friend(pic, c: Color, sign_kind: int, t: float, bob: float) -> void:
	pic._circle(0.5, 0.56 + bob, 0.3, c)
	pic._circle(0.5, 0.56 + bob, 0.25, c.lightened(0.25))
	pic._circle(0.5, 0.54 + bob, 0.18, DARK)
	pic._circle(0.43, 0.51 + bob, 0.04, c.lightened(0.5))
	pic._circle(0.57, 0.51 + bob, 0.04, c.lightened(0.5))
	pic._poly([[0.43, 0.6 + bob], [0.57, 0.6 + bob], [0.5, 0.65 + bob]], c.lightened(0.5))
	pic._poly([[0.49, 0.27 + bob], [0.51, 0.27 + bob], [0.51, 0.16 + bob], [0.49, 0.16 + bob]], Color(0.8, 0.85, 0.95))
	var y := 0.12 + bob
	match sign_kind:
		0:
			pic._poly([[0.5, y + 0.03], [0.62, y - 0.06], [0.66, y - 0.1], [0.56, y - 0.02]], Color(0.3, 0.85, 0.3))
			pic._poly([[0.5, y + 0.03], [0.4, y - 0.04], [0.36, y - 0.08], [0.46, y - 0.02]], Color(0.3, 0.85, 0.3))
		1:
			var f := 0.02 * sin(t * 10.0)
			pic._poly([[0.42, y + 0.04], [0.58, y + 0.04], [0.5, y - 0.12 - f]], Color(1.0, 0.45, 0.1))
			pic._poly([[0.46, y + 0.04], [0.54, y + 0.04], [0.5, y - 0.05 - f]], Color(1.0, 0.9, 0.4))
		2:
			for k in 3:
				var a := k * PI / 3.0 + t * 0.5
				var nx := -sin(a) * 0.012
				var ny := cos(a) * 0.012
				pic._poly([[0.5 - cos(a) * 0.08 + nx, y - sin(a) * 0.08 + ny], [0.5 + cos(a) * 0.08 + nx, y + sin(a) * 0.08 + ny],
					[0.5 + cos(a) * 0.08 - nx, y + sin(a) * 0.08 - ny], [0.5 - cos(a) * 0.08 - nx, y - sin(a) * 0.08 - ny]], Color.WHITE)
				pic._circle(0.5 + cos(a) * 0.08, y + sin(a) * 0.08, 0.018, Color.WHITE)
				pic._circle(0.5 - cos(a) * 0.08, y - sin(a) * 0.08, 0.018, Color.WHITE)
		_:
			pic._poly([[0.5, y - 0.02], [0.2, y + 0.06], [0.22, y + 0.02]], Color(1.0, 0.9, 0.5, 0.6))
			var pts: Array = []
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0
				var rr := 0.07 if k % 2 == 0 else 0.03
				pts.append([0.5 + cos(a) * rr, y + sin(a) * rr])
			pic._poly(pts, Color(1.0, 0.9, 0.3))
	pic._circle(0.17, 0.58 + bob, 0.055, c)
	pic._circle(0.83, 0.58 + bob, 0.055, c)


## A round little arena hero holding their gun (0 blaster, 1 sprayer, 2 boomer, 3 tank, 4 zoomer).
static func _hero(pic, gun: int, t: float, bob: float, color: Color) -> void:
	var cols := [Color(0.35, 0.8, 1.0), Color(0.5, 1.0, 0.4), Color(1.0, 0.55, 0.2), Color(0.75, 0.6, 1.0), Color(1.0, 0.85, 0.3)]
	var c: Color = cols[gun] if color == Color.WHITE else color
	var big := 1.15 if gun == 3 else 1.0
	pic._circle(0.4, 0.7 + bob * 0.5, 0.2 * big, c)  # body
	pic._circle(0.4, 0.38 + bob, 0.16, Color(1.0, 0.85, 0.7))  # head
	pic._poly([[0.24, 0.34 + bob], [0.56, 0.34 + bob], [0.52, 0.22 + bob], [0.28, 0.22 + bob]], c.darkened(0.2))  # helmet
	pic._eye(0.35, 0.4 + bob, 0.03)
	pic._eye(0.46, 0.4 + bob, 0.03)
	var y := 0.64 + bob * 0.5
	match gun:
		0:
			pic._poly([[0.5, y - 0.04], [0.82, y - 0.04], [0.82, y + 0.04], [0.5, y + 0.04]], Color(0.3, 0.3, 0.4))
			pic._circle(0.88, y, 0.04, c.lightened(0.4))
		1:
			pic._poly([[0.5, y - 0.06], [0.75, y - 0.06], [0.75, y + 0.06], [0.5, y + 0.06]], Color(0.3, 0.3, 0.4))
			for k in 3:
				var d := fmod(t * 2.0 + k * 0.33, 1.0)
				pic._circle(0.8 + d * 0.15, y + (k - 1) * 0.06 * d, 0.025, c.lightened(0.4))
		2:
			pic._poly([[0.5, y - 0.09], [0.78, y - 0.09], [0.78, y + 0.09], [0.5, y + 0.09]], Color(0.35, 0.3, 0.3))
			pic._circle(0.88, y, 0.08 + 0.01 * sin(t * 6.0), Color(1.0, 0.6, 0.2))
		3:
			pic._poly([[0.12, 0.52 + bob], [0.24, 0.48 + bob], [0.24, 0.9], [0.12, 0.86]], Color(0.6, 0.6, 0.75))  # shield
			pic._poly([[0.55, y - 0.05], [0.8, y - 0.05], [0.8, y + 0.05], [0.55, y + 0.05]], Color(0.3, 0.3, 0.4))
		_:
			pic._poly([[0.5, y - 0.04], [0.76, y - 0.04], [0.76, y + 0.04], [0.5, y + 0.04]], Color(0.3, 0.3, 0.4))
			for k in 3:
				pic._poly([[0.05, 0.6 + k * 0.08], [0.2, 0.6 + k * 0.08], [0.2, 0.62 + k * 0.08], [0.05, 0.62 + k * 0.08]], Color(1.0, 1.0, 1.0, 0.7))
