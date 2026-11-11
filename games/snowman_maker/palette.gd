extends RefCounted
## What must be seen in Snowman Maker, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The builders, the snowballs (white, with a frosty outline: snowman.gd BALL_OUTLINE) and the supply boxes are on
## the garden snow; the builders also skate on the village rink's ice.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Snowman := preload("res://games/snowman_maker/snowman.gd")
const Story := preload("res://games/snowman_maker/story.gd")
const Village := preload("res://games/snowman_maker/village.gd")


static func key_colors() -> Dictionary:
	return Contrast.humanoids(Party.COLORS, Story.LOOKS, "builder")


static func backgrounds() -> Dictionary:
	return {"snow": Snowman.GROUND_SNOW, "rink ice": Village.ICE}


static func groups() -> Array:
	var keys := {"snowball": {"color": Snowman.SNOW, "rim": Snowman.BALL_OUTLINE}}
	keys.merge(Contrast.named("box", Story.BOX_COLORS))
	return [{"keys": keys, "bgs": {"snow": Snowman.GROUND_SNOW}}]
