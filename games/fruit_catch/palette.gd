extends RefCounted
## What must be seen in Fruit Catch, and what it is seen against (core/contrast.gd; tests/contrast_test.gd).
## The catchers run on the orchard grass; the fruit (and the rotten apple to dodge) falls past the big tree's leaves
## and the day sky, onto the grass. Second pass (deep.gd): the windfall and wasp tells glow on the grass (each its own
## colour), the wasp flies over the grass, and Nutmeg's gift orbs float over the grass in front of the giant.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Art := preload("res://games/fruit_catch/art.gd")
const Deep := preload("res://games/fruit_catch/deep.gd")


static func key_colors() -> Dictionary:
	var out := Contrast.humanoids(Party.COLORS, Art.LOOKS)
	out["windfall tell"] = Deep.WINDFALL_COLOR
	out["wasp tell"] = Deep.WASP_COLOR
	return out


static func backgrounds() -> Dictionary:
	return {"grass": Art.GROUND}


static func groups() -> Array:
	var gifts := {}
	for g in Deep.GIFTS:
		gifts["%s orb" % g.id] = g.color
	return [{"keys": Contrast.named("fruit", Art.FRUIT_COLORS),
		"bgs": Contrast.merge(Contrast.merge(backgrounds(), {"leaves": Art.LEAF}), Contrast.sky("day"))},
		# the rotten windfall apples land on their own brown circle
		{"keys": {"rotten apple": Art.FRUIT_COLORS[Art.ROTTEN]}, "bgs": {"windfall circle": Deep.WINDFALL_COLOR.lerp(Art.GROUND, 0.55)}},
		{"keys": gifts, "bgs": {"grass": Art.GROUND}}]
