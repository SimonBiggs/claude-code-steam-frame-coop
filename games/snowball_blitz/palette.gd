extends RefCounted
## What must be seen in Snowball Blitz, and the snow and skies it is seen on (core/contrast.gd; tests/contrast_test.gd).
## Snowmen, the yeti, snowballs and the MEGA SNOWBALL are snow-white on snow: they wear the ink outline (looks.gd).

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/snowball_blitz/looks.gd")
const Bosses := preload("res://games/snowball_blitz/bosses.gd")
const Snowman := preload("res://games/snowball_blitz/snowman.gd")


static func _outlined(c: Color) -> Dictionary:
	return {"color": c, "rim": Looks.OUTLINE}


## Players, snowmen, snowballs, the MEGA SNOWBALL and its ring, and every boss warning ring.
static func key_colors() -> Dictionary:
	var out := Contrast.named("player", Looks.PLAYER_COLORS)
	out["snowman"] = _outlined(Looks.SNOW_BODY)
	out["yeti"] = _outlined(Looks.YETI_FUR)
	out["snowball"] = _outlined(Looks.SNOWBALL)
	out["enemy snowball"] = _outlined(Looks.ENEMY_BALL)
	out["mega snowball"] = _outlined(Looks.MEGA_BALL)
	out["mega ring"] = Looks.MEGA_RING
	for k in Bosses.LIST:
		for a in Bosses.LIST[k].attacks:
			out["%s %s ring" % [k, a]] = Bosses.tell_color(k, a)
	return out


## The square's snow (lightest and darkest) and the fort walls.
static func backgrounds() -> Dictionary:
	return {"snow": Looks.SNOW, "shaded snow": Looks.snow_dark(), "fort": Looks.FORT}


## Every sky: dusk, aurora night, morning, each with and without the sunshine event.
static func skies() -> Dictionary:
	var out := {}
	for n in [[-1.0, "morning"], [0.0, "dusk"], [1.0, "night"]]:
		for sunny in [false, true]:
			var sk := Looks.sky(n[0], sunny)
			var name := String(n[1]) + (" sunny" if sunny else "")
			out["%s sky" % name] = sk[0]
			out["%s horizon" % name] = sk[1]
	return out


static func groups() -> Array:
	return [
		# Balloon snowmen float over the walls on their balloons, against the sky; snowballs fly through it.
		{"keys": Contrast.merge(Contrast.named("balloon", Snowman.BALLOON_COLORS), {"snowball": _outlined(Looks.SNOWBALL),
			"enemy snowball": _outlined(Looks.ENEMY_BALL)}), "bgs": skies()},
	]
