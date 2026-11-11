extends RefCounted
## What must be seen in Mini Golf Party, and what it rolls on (core/contrast.gd; tests/contrast_test.gd).
## The balls (each player's colour, course.gd ball_tint) and the cup roll / sit on the greens' two stripes. Second pass
## (deep.gd): the surprise tells (gust band, mole circle) and the mole himself on the greens, the balls on the pick
## green's pads, and the pick orbs over the greens and every season's lawn.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Course := preload("res://games/mini_golf_party/course.gd")
const Deep := preload("res://games/mini_golf_party/deep.gd")
const Hazards := preload("res://games/mini_golf_party/hazards.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")


static func _balls() -> Dictionary:
	var out := {}
	for i in Party.COLORS.size():
		out["ball %d" % (i + 1)] = Course.ball_tint(Party.COLORS[i])
	return out


static func key_colors() -> Dictionary:
	var out := _balls()
	out["cup"] = Course.CUP
	out["gust tell"] = Deep.GUST_COLOR
	out["mole tell"] = Deep.MOLE_COLOR
	out["mole"] = Hazards.FUR
	return out


static func backgrounds() -> Dictionary:
	return {"green": Course.GREEN, "green 2": Course.GREEN2}


static func groups() -> Array:
	var orbs := {}
	for g in Deep.GIFTS:
		orbs["%s orb" % g.id] = g.color
	for m in PickOrbs.MODE_IDS:
		orbs["%s orb" % m] = PickOrbs.mode_color(m)
	var lawns := {"pick green": Course.PICK_GREEN}
	for s in Deep.SEASONS:
		lawns["%s lawn" % s] = Deep.SEASONS[s].lawn
	return [
		# the balls roll onto the pick green's pads
		{"keys": _balls(), "bgs": {"pad": Course.PAD, "pick green": Course.PICK_GREEN}},
		# the pick orbs float over the pick green, seen against the green and every season's lawn
		{"keys": orbs, "bgs": lawns},
	]
