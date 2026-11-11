extends RefCounted
## What must be seen in Rhythm Band (core/contrast.gd; tests/contrast_test.gd): the guitar balls on the see-through
## road (normal and STAR POWER, over the night and the stage's back wall), and the drummer's balls against them.

const Contrast := preload("res://core/contrast.gd")
const Highway := preload("res://games/rhythm_band/highway.gd")
const Drummer := preload("res://games/rhythm_band/drummer.gd")
const Stage := preload("res://games/rhythm_band/stage.gd")


static func _behind() -> Dictionary:
	return {"night": Stage.NIGHT, "back wall": Stage.BACK_WALL}


static func key_colors() -> Dictionary:
	var out := Contrast.named("lane ball", Highway.LANE_COLORS)
	out["gold ball"] = Highway.GOLD_NOTE
	return out


## The road as drawn over what is behind it.
static func backgrounds() -> Dictionary:
	var out := {}
	var behind := _behind()
	for b in behind:
		out["road over %s" % b] = Contrast.over(Highway.ROAD, behind[b])
		out["star road over %s" % b] = Contrast.over(Highway.STAR_ROAD, behind[b])
	return out


static func groups() -> Array:
	var balls := {}
	for i in Drummer.PAD_COLORS.size():
		balls["drum ball %d" % (i + 1)] = Drummer.note_color(i)
	return [{"keys": balls, "bgs": Contrast.merge(_behind(), {"stage": Stage.STAGE_FLOOR})}]
