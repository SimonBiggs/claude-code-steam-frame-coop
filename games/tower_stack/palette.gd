extends RefCounted
## What must be seen in Tower Stack, and what it sits on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Looks := preload("res://games/tower_stack/looks.gd")
const TowerGen := preload("res://games/tower_stack/towergen.gd")
const Weather := preload("res://games/tower_stack/weather.gd")


static func key_colors() -> Dictionary:
	return Contrast.humanoids(Party.COLORS, Looks.LOOKS)


## Every ground theme's grass and path (the builders walk on it; warn rings are drawn on it).
static func backgrounds() -> Dictionary:
	var out := {}
	for g in TowerGen.GROUND_COLORS:
		out["%s grass" % g] = TowerGen.GROUND_COLORS[g][0]
		out["%s path" % g] = TowerGen.GROUND_COLORS[g][1]
	return out


static func groups() -> Array:
	return [
		# The blocks are swung and stacked up against the day sky.
		{"keys": Contrast.merge(Contrast.merge(Contrast.named("block", Looks.COLORS), Contrast.named("special block",
			Looks.SPECIAL_COLORS)), Contrast.merge(Contrast.named("balloon", Looks.BALLOON_COLORS), {"stone": Looks.STONE})),
			"bgs": Contrast.sky("day")},
		{"keys": Contrast.named("warning", Weather.COLORS), "bgs": backgrounds()},
	]
