extends RefCounted
## Ghost Lantern colours the game and palette.gd (tests/contrast_test.gd) both read, so they can't drift.

## P1 (lantern) + up to six TV ghost hunters P2..P7.
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.82, 0.4), Color(0.45, 1.0, 0.7), Color(1.0, 0.55, 0.9),
	Color(0.45, 0.8, 1.0), Color(1.0, 0.6, 0.3), Color(0.8, 1.0, 0.35), Color(0.75, 0.6, 1.0)]
