extends RefCounted
## What must be seen in Hide and Seek: the golden stars on every floor of
## the house (each room's floor and its pattern's own colours, every theme's garden), the castle and the spaceship
## (core/contrast.gd; tests/contrast_test.gd). Not counted: the spaceship's thin glowing guide line and its striped
## cargo-bay edge (always half black and yellow), Pip's toys by the kennel (a trophy shelf, not play), and the
## hiding critters themselves: blending into a floor of your own colour is the game (no outline on purpose).

const Contrast := preload("res://core/contrast.gd")
const Story := preload("res://games/hide_and_seek/story.gd")
const MapHouse := preload("res://games/hide_and_seek/map_house.gd")
const MapCastle := preload("res://games/hide_and_seek/map_castle.gd")
const MapShip := preload("res://games/hide_and_seek/map_ship.gd")

const _NOT_FLOORS := ["GUIDE", "HAZARD", "HAZARD_DARK"]
const _PATTERN_ONLY := 4  # map_house LOOK pattern 4 (puzzle mats) never shows the room's own colour


static func key_colors() -> Dictionary:
	return {"star": Story.STAR_COLOR}


static func backgrounds() -> Dictionary:
	var out := Contrast.field("garden", Story.THEMES, "ground")
	for room in MapHouse.LOOK:
		if room != "garden" and int(MapHouse.LOOK[room][2]) != _PATTERN_ONLY:  # (the garden's ground is the theme's)
			out["%s floor" % room] = MapHouse.LOOK[room][1]
	out.merge(Contrast.named("house pattern", MapHouse.PATTERN))
	out.merge(Contrast.named("castle", MapCastle.FLOORS))
	for k in MapShip.FLOORS:
		if not _NOT_FLOORS.has(k):
			out["ship %s" % k] = MapShip.FLOORS[k]
	return out
