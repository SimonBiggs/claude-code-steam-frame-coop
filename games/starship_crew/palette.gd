extends RefCounted
## What must be seen in Starship Crew, and what it is seen against (core/contrast.gd; tests/contrast_test.gd).
## Rings to fly through, space rocks and the alien saucer, out against the space sky and every mission's planet; the
## second pass's warned surprises (rock-stream orange, solar-flare pink), the pick orbs' module colours and the crew
## friends' pods, against the same space in every star sector (the sector dust is decoration, never a background).

const Contrast := preload("res://core/contrast.gd")
const Art := preload("res://games/starship_crew/art.gd")
const Story := preload("res://games/starship_crew/story.gd")
const Deep := preload("res://games/starship_crew/deep.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")


static func key_colors() -> Dictionary:
	var out := {"ring": Art.RING_TINT, "saucer": {"color": Art.UFO_BODY, "rim": Art.UFO_RIM}}
	out.merge(Contrast.named("rock", Art.ROCK_COLORS))
	out["rock stream"] = {"color": Deep.STREAM_COLOR, "rim": Deep.INK}  # (hazards.gd: ink edges)
	out["solar flare"] = {"color": Deep.FLARE_COLOR, "rim": Deep.INK}
	for g in Deep.GIFTS:  # the pick orbs' names: the module's colour with PickOrbs' dark outline
		out["module " + String(g.id)] = {"color": g.color, "rim": PickOrbs.LABEL_OUTLINE}
	return out


static func backgrounds() -> Dictionary:
	var out := Contrast.sky("space")
	out.merge(Contrast.named("planet", Story.PLANET_COLS))
	out["home planet"] = Story.HOME_LOOK[0]
	return out
