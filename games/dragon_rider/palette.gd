extends RefCounted
## What must be seen in Dragon Rider: the rings, balloons and stranded critters against every sky, cloud and sea
## the routes fly through (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Course := preload("res://games/dragon_rider/course.gd")
const World := preload("res://games/dragon_rider/world.gd")


## Each wears the ink outline (course.gd OUTLINE).
static func key_colors() -> Dictionary:
	var cols := {"next ring": Course.RING_NEXT, "later ring": Course.RING_LATER, "final ring": Course.RING_FINAL,
		"golden balloon": Course.GOLDEN_BALLOON}
	cols.merge(Contrast.named("balloon", Course.BALLOON_COLORS))
	cols.merge(Contrast.named("critter", Course.CRITTER_COLORS))
	var out := {}
	for k in cols:
		out[k] = {"color": cols[k], "rim": Course.OUTLINE}
	return out


## Every palette's sky (top, horizon), clouds and the sea far below, and the white cloud pad a critter sits on.
static func backgrounds() -> Dictionary:
	var out := {"critter cloud pad": Course.CLOUD_PAD}
	for k in ["top", "hor", "cloud", "sea_top", "sea_deep"]:
		out.merge(Contrast.field(k, World.PALETTES, k))
	return out
