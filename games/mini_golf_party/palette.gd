extends RefCounted
## What must be seen in Mini Golf Party, and what it rolls on (core/contrast.gd; tests/contrast_test.gd).
## The balls (each player's colour, course.gd ball_tint) and the cup roll / sit on the greens' two stripes.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Course := preload("res://games/mini_golf_party/course.gd")


static func key_colors() -> Dictionary:
	var out := {}
	for i in Party.COLORS.size():
		out["ball %d" % (i + 1)] = Course.ball_tint(Party.COLORS[i])
	out["cup"] = Course.CUP
	return out


static func backgrounds() -> Dictionary:
	return {"green": Course.GREEN, "green 2": Course.GREEN2}
