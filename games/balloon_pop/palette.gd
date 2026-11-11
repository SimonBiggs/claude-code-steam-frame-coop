extends RefCounted
## What must be seen in Balloon Pop, and every sky and grass it floats on (core/contrast.gd; tests/contrast_test.gd).
## 2026-11: the blue balloon vanished on the day sky and the green one on the grass; both were retuned.

const Contrast := preload("res://core/contrast.gd")
const Balloon := preload("res://games/balloon_pop/balloon.gd")
const Skies := preload("res://games/balloon_pop/skies.gd")
const Story := preload("res://games/balloon_pop/story.gd")
const WaveGen := preload("res://games/balloon_pop/wavegen.gd")


static func key_colors() -> Dictionary:
	var out := {}
	for i in Balloon.COLORS.size():
		out["%s balloon" % Balloon.COLOR_NAMES[i]] = Balloon.COLORS[i]
	out.merge({"gold balloon": Balloon.GOLD_COLOR, "grumpy balloon": Balloon.GRUMPY_COLOR,
		"rocket balloon": Balloon.ROCKET_COLOR, "ice balloon": Balloon.ICE_COLOR, "ride choice balloon": Balloon.CHOICE_COLOR})
	for k in Story.KIND_COLORS:
		out["%s card balloon" % WaveGen.KIND_NAMES[int(k)]] = Story.KIND_COLORS[k]
	return out


static func backgrounds() -> Dictionary:
	return Skies.backgrounds()


## The wind stripe (see-through, on the grass only).
static func groups() -> Array:
	return [{"keys": {"wind stripe": Skies.gust_stripe()}, "bgs": Contrast.named("grass", Skies.GROUND)}]
