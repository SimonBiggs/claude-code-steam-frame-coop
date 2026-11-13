extends RefCounted
## What must be seen in Fishing Lake (core/contrast.gd; tests/contrast_test.gd): every fish under the water, seen
## through it (lake.gd WATER_ALPHA of the water covers the fish and the lake bed alike), at every time of day and in
## the rain. Boots and treasure chests are not counted (they lie hidden on the bottom until hooked).

const Contrast := preload("res://core/contrast.gd")
const Lake := preload("res://games/fishing_lake/lake.gd")
const Fish := preload("res://games/fishing_lake/fish.gd")
const Angler := preload("res://games/fishing_lake/angler.gd")
const Seasons := preload("res://games/fishing_lake/seasons.gd")
const WHISKERS_RING := Seasons.WHISKERS_RING

const PHASES := {"morning": 0.0, "midday": 0.5, "sunset": 1.0, "night": 1.45}
const RAIN := {"": 0.0, " rain": 1.0}


## [name, water colour] for every time of day, dry and raining.
static func waters() -> Array:
	var out := []
	for ph in PHASES:
		for r in RAIN:
			out.append([String(ph) + String(r), Lake.water_color(Lake.daylight(PHASES[ph], RAIN[r]))])
	return out


## What a colour under the water looks like from above.
static func under(c: Color, water: Color) -> Color:
	return c.lerp(water, Lake.WATER_ALPHA)


static func key_colors() -> Dictionary:
	var w: Color = waters()[0][1]
	return _fish(w)


static func _fish(water: Color) -> Dictionary:
	var out := {}
	for i in Fish.TYPES.size():
		var t: Dictionary = Fish.TYPES[i]
		if t.get("junk", false):
			continue
		if i == Fish.LEGEND:  # a dark shadow on purpose, always marked by his floating label (fish.gd)
			out[String(t.name).to_lower()] = {"color": under(t.col, water), "rim": Fish.LEGEND_ICON}
		else:
			out[String(t.name).to_lower()] = under(t.col, water)
	return out


static func backgrounds() -> Dictionary:
	var w: Color = waters()[0][1]
	return {"lake bed (morning)": under(Lake.BED, w)}


## The same fish over the same bed, under every other sky.
static func groups() -> Array:
	var out := []
	var ws := waters()
	for i in range(1, ws.size()):
		out.append({"keys": _fish(ws[i][1]), "bgs": {"lake bed (%s)" % ws[i][0]: under(Lake.BED, ws[i][1])}})
	# The bobber floats on top of the water.
	var surfaces := {}
	for w in ws:
		surfaces["water (%s)" % w[0]] = under(Lake.BED, w[1])
	out.append({"keys": {"bobber": {"color": Angler.BOBBER_TOP, "rim": Angler.BOBBER_BOTTOM}}, "bgs": surfaces})
	# Third pass: a flock's warn ring (seasons.gd RING) glows on the water at every time of day; Old Whiskers' ring too.
	out.append({"keys": {"flock ring": Seasons.RING, "whiskers ring": WHISKERS_RING}, "bgs": surfaces})
	return out
