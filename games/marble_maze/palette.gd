extends RefCounted
## What must be seen in Marble Maze, and every floor it rolls on (core/contrast.gd; tests/contrast_test.gd).
## Worlds never recolour the floor, so the floors are every THEME's two checker colours.

const Contrast := preload("res://core/contrast.gd")
const Levels := preload("res://games/marble_maze/levels.gd")
const Worlds := preload("res://games/marble_maze/worlds.gd")
const Board := preload("res://games/marble_maze/board.gd")


static func key_colors() -> Dictionary:
	# The players' marbles (slot 0 is the giant, who tilts the board; its solo marble is P2's colour).
	var out := Contrast.named("marble", Worlds.PLAYER_COLORS.slice(1))
	out = Contrast.merge(out, Contrast.named("warning", Worlds.EVENT_COLORS))
	# Third pass: a moving wall's track is its warning, painted on the floor.
	return Contrast.merge(out, {"moving wall track": Board.TRACK_COLOR})


static func backgrounds() -> Dictionary:
	var out := {}
	for th in Levels.THEMES:
		out["%s floor" % th] = Levels.THEMES[th][0]
		out["%s floor 2" % th] = Levels.THEMES[th][1]
	out["magnet tile"] = Board.MAGNET_FLOOR  # third pass: marbles roll over magnet tiles too
	return out
