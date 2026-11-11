extends RefCounted
## What must be seen in Bee Garden (core/contrast.gd; tests/contrast_test.gd): the bees and the warning rings over
## every season's lawn and the bed, the flowers and their fruit on the soil, the wasp by the hive on the lawn and
## an aphid on a plant's green.

const Contrast := preload("res://core/contrast.gd")
const W := preload("res://games/bee_garden/world.gd")
const GardenGen := preload("res://games/bee_garden/gardengen.gd")
const Pest := preload("res://games/bee_garden/pest.gd")


static func key_colors() -> Dictionary:
	var out := Contrast.named("bee", W.PLAYER_COLORS.slice(1))
	out.merge({"wasp warning": GardenGen.WASP_WARN, "storm warning": GardenGen.STORM_WARN,
		"wasp": {"color": Pest.WASP, "rim": Pest.WASP_DARK}})
	return out


static func backgrounds() -> Dictionary:
	return Contrast.merge(Contrast.named("lawn", _lawns()), {"soil": W.SOIL})


static func _lawns() -> Dictionary:
	var out := {}
	for i in W.SEASONS.size():
		out[W.SEASONS[i].to_lower()] = W.SEASON_LAWN[i]
	return out


static func groups() -> Array:
	var flowers := {}
	for k in W.KINDS:
		flowers["%s petals" % k.name] = k.petal
		flowers["%s fruit" % k.name] = k.fruit_color
	return [
		{"keys": flowers, "bgs": {"soil": W.SOIL}},
		{"keys": {"aphid": Pest.APHID}, "bgs": {"stem": W.PLANT_GREEN, "leaf": W.LEAF_GREEN}},
	]
