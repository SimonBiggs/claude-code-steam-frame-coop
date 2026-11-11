extends RefCounted
## What must be seen in Ghost Lantern, and every floor it is on (core/contrast.gd; tests/contrast_test.gd).
## A hopping ghost's warning ring is drawn in its own colour (ghost.gd), so the ghosts cover the rings too.

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/ghost_lantern/looks.gd")
const Ghost := preload("res://games/ghost_lantern/ghost.gd")
const World := preload("res://games/ghost_lantern/world.gd")


static func key_colors() -> Dictionary:
	return Contrast.merge(Contrast.named("hunter", Looks.PLAYER_COLORS), Contrast.field("ghost", Ghost.KINDS, "color"))


## The mansion's room floors (both tones) and the wings' floors.
static func backgrounds() -> Dictionary:
	var out := {}
	for room in World.FLOORS:
		out["%s floor" % room] = World.FLOORS[room][0]
		out["%s floor 2" % room] = World.FLOORS[room][1]
	return Contrast.merge(out, Contrast.named("floor", World.WING_FLOORS))
