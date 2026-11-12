extends RefCounted
## What must be seen in Tiny Town Tycoon, and what it drives on (core/contrast.gd; tests/contrast_test.gd).
## The TV players drive the town's vehicles (their body is the vehicle's own colour; the driver's colour is a little
## flag) along the roads, and over the island's grass and sand where there are no roads yet.

const Contrast := preload("res://core/contrast.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const Deep := preload("res://games/tiny_town_tycoon/deep.gd")


static func key_colors() -> Dictionary:
	var out := Contrast.field("vehicle", Defs.V, "color")
	# The crane's yellow cab rides on a big dark chassis (art.gd CRANE_BASE).
	out["vehicle crane"] = {"color": out["vehicle crane"], "rim": Art.CRANE_BASE}
	# Benny's weather tells on the island (deep.gd: the gust band, the fog circle), on every island's ground.
	out["weather gust"] = Deep.GUST_COLOR
	out["weather fog"] = Deep.FOG_COLOR
	return out


## The road (asphalt and kerb) and every island's grass, grass2 and sand.
static func backgrounds() -> Dictionary:
	var out := {"asphalt": Art.ASPHALT, "kerb": Art.KERB}
	for k in ["grass", "grass2", "sand"]:
		out.merge(Contrast.field(k, Defs.ISLANDS, k))
	return out
