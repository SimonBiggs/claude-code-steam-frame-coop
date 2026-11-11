extends RefCounted
## What must be seen in Paint and Guess: every paint on the dark painting surface (core/contrast.gd;
## tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Canvas := preload("res://games/paint_and_guess/canvas.gd")


static func key_colors() -> Dictionary:
	var out := {}
	for i in Canvas.COLORS.size():
		out["%s paint" % Canvas.COLOR_NAMES[i].to_lower()] = Canvas.COLORS[i]
	return out


static func backgrounds() -> Dictionary:
	return {"canvas": Canvas.SURFACE}
