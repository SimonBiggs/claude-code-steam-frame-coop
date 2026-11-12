extends RefCounted
## What must be seen in Snowman Maker, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The builders, the snowballs (white, with a frosty outline: snowman.gd BALL_OUTLINE) and the supply boxes are on
## the garden snow; the builders also skate on the village rink's ice. Second pass (deep.gd): the sunbeam and snow-slide
## tells glow on the snow (each its own colour), Tumble's gift orbs float over the snow, and out of season the snow
## globe's golden stand sits on the season's ground outside the glass.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Snowman := preload("res://games/snowman_maker/snowman.gd")
const Story := preload("res://games/snowman_maker/story.gd")
const Village := preload("res://games/snowman_maker/village.gd")
const Deep := preload("res://games/snowman_maker/deep.gd")


static func key_colors() -> Dictionary:
	var out := Contrast.humanoids(Party.COLORS, Story.LOOKS, "builder")
	out["sunbeam tell"] = Deep.SUN_COLOR
	out["snow slide tell"] = Deep.SLIDE_COLOR
	return out


static func backgrounds() -> Dictionary:
	return {"snow": Snowman.GROUND_SNOW, "rink ice": Village.ICE}


static func groups() -> Array:
	var keys := {"snowball": {"color": Snowman.SNOW, "rim": Snowman.BALL_OUTLINE}}
	keys.merge(Contrast.named("box", Story.BOX_COLORS))
	var gifts := {}
	for g in Deep.GIFTS:
		gifts["%s orb" % g.id] = g.color
	var outside := {}
	for s in Deep.SEASONS:
		if bool(Deep.SEASONS[s].globe):
			outside["%s ground" % s] = Deep.SEASONS[s].ground
	return [{"keys": keys, "bgs": {"snow": Snowman.GROUND_SNOW}}, {"keys": gifts, "bgs": {"snow": Snowman.GROUND_SNOW}},
		{"keys": {"globe stand": Deep.STAND_COLOR}, "bgs": outside}]
