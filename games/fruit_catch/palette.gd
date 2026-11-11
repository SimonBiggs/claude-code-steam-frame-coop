extends RefCounted
## What must be seen in Fruit Catch, and what it is seen against (core/contrast.gd; tests/contrast_test.gd).
## The catchers run on the orchard grass; the fruit (and the rotten apple to dodge) falls past the big tree's leaves
## and the day sky, onto the grass.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Art := preload("res://games/fruit_catch/art.gd")


static func key_colors() -> Dictionary:
	return Contrast.humanoids(Party.COLORS, Art.LOOKS)


static func backgrounds() -> Dictionary:
	return {"grass": Art.GROUND}


static func groups() -> Array:
	return [{"keys": Contrast.named("fruit", Art.FRUIT_COLORS),
		"bgs": Contrast.merge(Contrast.merge(backgrounds(), {"leaves": Art.LEAF}), Contrast.sky("day"))}]
