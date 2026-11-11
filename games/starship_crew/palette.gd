extends RefCounted
## What must be seen in Starship Crew, and what it is seen against (core/contrast.gd; tests/contrast_test.gd).
## Rings to fly through, space rocks and the alien saucer, out against the space sky and every mission's planet.

const Contrast := preload("res://core/contrast.gd")
const Art := preload("res://games/starship_crew/art.gd")
const Story := preload("res://games/starship_crew/story.gd")


static func key_colors() -> Dictionary:
	var out := {"ring": Art.RING_TINT, "saucer": {"color": Art.UFO_BODY, "rim": Art.UFO_RIM}}
	out.merge(Contrast.named("rock", Art.ROCK_COLORS))
	return out


static func backgrounds() -> Dictionary:
	var out := Contrast.sky("space")
	out.merge(Contrast.named("planet", Story.PLANET_COLS))
	out["home planet"] = Story.HOME_LOOK[0]
	return out
