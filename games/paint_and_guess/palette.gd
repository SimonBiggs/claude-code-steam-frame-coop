extends RefCounted
## What must be seen in Paint and Guess: every paint on the dark painting surface (core/contrast.gd;
## tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Canvas := preload("res://games/paint_and_guess/canvas.gd")
const Deep := preload("res://games/paint_and_guess/deep.gd")


static func key_colors() -> Dictionary:
	var out := {}
	for i in Canvas.COLORS.size():
		out["%s paint" % Canvas.COLOR_NAMES[i].to_lower()] = Canvas.COLORS[i]
	return out


static func backgrounds() -> Dictionary:
	return {"canvas": Canvas.SURFACE}


## The surprises' tells (hazards.gd: steady circles / bands) lie on bare canvas only (deep.gd problems()).
static func groups() -> Array:
	return [{"keys": {"drip tell": Deep.DRIP_COLOR, "wind tell": Deep.WIND_COLOR}, "bgs": {"canvas": Canvas.SURFACE}}]
