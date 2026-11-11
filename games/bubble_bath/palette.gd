extends RefCounted
## What must be seen in Bubble Bath, and what it floats on (core/contrast.gd; tests/contrast_test.gd).
## The players' boats (player-coloured hull with a darker stripe, art.gd boat_band), the rubber ducks to catch, the golden ducks and
## the sponge islands to sail round, all on the bath water (deep blue, white crests).

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Art := preload("res://games/bubble_bath/art.gd")


static func key_colors() -> Dictionary:
	var out := {}
	for i in Party.COLORS.size():
		out["boat %d" % (i + 1)] = {"color": Party.COLORS[i], "rim": Art.boat_band(Party.COLORS[i])}
	out.merge({"duck": Art.DUCK_YELLOW, "golden duck": Art.DUCK_GOLD, "sponge": {"color": Art.SPONGE, "rim": Art.SPONGE_TOP}})
	return out


static func backgrounds() -> Dictionary:
	return {"water": Art.WATER_DEEP, "water crest": Art.WATER_CREST}
