extends RefCounted
## Giant's Table colours the game and palette.gd (tests/contrast_test.gd) both read, so they can't drift.

const Contrast := preload("res://core/contrast.gd")

## The giant (P1) and the knights.
const PLAYER_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(1.0, 0.72, 0.2), Color(1.0, 0.45, 0.75),
	Color(0.95, 0.3, 0.28), Color(0.68, 0.45, 1.0), Color(0.3, 0.92, 0.95), Color(0.96, 0.96, 0.92)]
## Goblins wear the ink outline (goblin.gd): green goblins vanished on the green meadow.
const GOBLIN_OUTLINE := Contrast.OUTLINE
## Every knight's steel helmet (knight.gd): it shows a gold knight on the sandy river bank.
const KNIGHT_HELM := Color(0.82, 0.84, 0.9)
const ARMOR := Color(0.62, 0.64, 0.7)
