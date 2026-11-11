extends RefCounted
## What must be seen in Block Builders: the runners and every kind of block on each theme's grass, dirt and rock
## (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Art := preload("res://games/block_builders/art.gd")
const Themes := preload("res://games/block_builders/themes.gd")


## Runners (P2..; P1 is the builder) show their darker legs; every block kind.
static func key_colors() -> Dictionary:
	var out := {}
	for i in range(1, Art.PLAYER_COLORS.size()):
		out["runner %d" % (i + 1)] = {"color": Art.PLAYER_COLORS[i], "rim": Art.runner_legs(Art.PLAYER_COLORS[i])}
	for i in Art.KINDS.size():  # (ink-outlined once placed: course.gd)
		out[Art.KINDS[i]] = {"color": Art.KIND_COLORS[i], "rim": Art.BLOCK_OUTLINE}
	return out


## Every theme's grass tops (each tone), dirt and rock (the islands' sides).
static func backgrounds() -> Dictionary:
	var out := {}
	for t in Themes.THEMES:
		var th: Dictionary = Themes.THEMES[t]
		for i in (th.grass as Array).size():
			out["%s grass %d" % [t, i + 1]] = th.grass[i]
		out["%s dirt" % t] = th.dirt
		out["%s rock" % t] = th.rock
	return out
