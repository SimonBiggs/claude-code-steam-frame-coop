extends RefCounted
## What must be seen in Obstacle Rush, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The jelly-bean runners (player colours and the CPU palette), the giant's beach balls and the stars are on the
## candy-coloured course floors; every one of them has an ink outline (runner_look.gd OUTLINE).

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Course := preload("res://games/obstacle_rush/course.gd")
const Look := preload("res://games/obstacle_rush/runner_look.gd")


static func key_colors() -> Dictionary:
	var out := Contrast.merge(Contrast.named("runner", Party.COLORS), Contrast.named("cpu runner", Look.CPU_COLORS))
	for i in Course.BALL_COLORS.size():
		out["beach ball %d" % (i + 1)] = Course.ball_color(i)
	out["star"] = Course.STAR_COLOR
	for k in out:  # (each with the ink outline: runner_look.gd OUTLINE)
		out[k] = {"color": out[k], "rim": Look.OUTLINE}
	return out


static func backgrounds() -> Dictionary:
	return Contrast.named("candy floor", Course.CANDY)
