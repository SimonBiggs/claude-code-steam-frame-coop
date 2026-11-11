extends RefCounted
## Kitchen Rush colours the game and palette.gd (tests/contrast_test.gd) both read, so they can't drift.

## Gran the chef (P1) and the runners.
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.45, 0.35), Color(0.3, 0.65, 1.0), Color(0.7, 0.45, 1.0),
	Color(0.35, 0.9, 0.4), Color(1.0, 0.82, 0.2), Color(1.0, 0.45, 0.8), Color(0.0, 0.7, 0.7)]  # deep teal: bright cyan vanished on the teal tiles
## The kitchen's checked floor tiles (kitchen.gd FLOOR_SHADER).
const FLOOR_A := Color(0.99, 0.95, 0.86)
const FLOOR_B := Color(0.55, 0.86, 0.82)
## The big counter's top, the chopping board on it and the pass strip (ingredients and plates sit on them).
## Mint top (white plates and dough vanished on the old white top) and a pastel-blue pass (buns, cheese and
## invitations vanished on the old gold strip).
const COUNTER_TOP := Color(0.6, 0.85, 0.8)
const BOARD := Color(0.85, 0.65, 0.4)
const PASS_STRIP := Color(0.55, 0.7, 0.95)
