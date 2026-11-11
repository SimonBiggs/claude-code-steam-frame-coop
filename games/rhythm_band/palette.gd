extends RefCounted
## What must be seen in Rhythm Band (core/contrast.gd; tests/contrast_test.gd): the guitar balls on the see-through
## road (normal and STAR POWER, over the night and the stage's back wall), and the drummer's balls against them;
## second pass: the change tells on the stage floor, Doodle's gift orbs, the season's drifting things.

const Contrast := preload("res://core/contrast.gd")
const Highway := preload("res://games/rhythm_band/highway.gd")
const Drummer := preload("res://games/rhythm_band/drummer.gd")
const Stage := preload("res://games/rhythm_band/stage.gd")
const Deep := preload("res://games/rhythm_band/deep.gd")


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
	var gifts := {}
	for g in Deep.GIFTS:
		gifts["%s orb" % g.id] = g.color
	return [{"keys": balls, "bgs": Contrast.merge(_behind(), {"stage": Stage.STAGE_FLOOR})},
		# Second pass: the warned changes glow on the stage floor (each kind its own colour)
		{"keys": {"fast tell": Deep.FAST_COLOR, "slow tell": Deep.SLOW_COLOR, "solo tell": Deep.SOLO_COLOR}, "bgs": {"stage": Stage.STAGE_FLOOR}},
		# Doodle's gift orbs float in front of the drummer: over the stage, the night and the back wall
		{"keys": gifts, "bgs": Contrast.merge(_behind(), {"stage": Stage.STAGE_FLOOR})},
		# the season's drifting things over the night sky
		{"keys": _drift(), "bgs": {"night": Stage.NIGHT}}]


static func _drift() -> Dictionary:
	var out := {}
	for s in Deep.SEASONS:
		out["%s drift" % s] = Deep.SEASONS[s].drift
	return out
