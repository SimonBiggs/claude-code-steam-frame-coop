extends RefCounted
## Duo Arena colours the game and palette.gd (tests/contrast_test.gd) both read, so they can't drift.

## Player suits (slot order).
const PLAYER_COLORS: Array[Color] = [Color(0.3, 0.7, 1.0), Color(1.0, 0.75, 0.25), Color(1.0, 0.45, 0.85),
	Color(0.55, 1.0, 0.25), Color(0.95, 0.95, 1.0), Color(0.7, 0.45, 1.0), Color(0.25, 1.0, 0.85)]
## Pickups by kind ("spread" is the default prism).
const PICKUP_COLORS := {"health": Color(0.3, 1.0, 0.45), "rapid": Color(1.0, 0.6, 0.15), "bubble": Color(0.45, 0.65, 1.0),
	"bomb": Color(1.0, 0.25, 0.35), "spread": Color(0.3, 0.9, 1.0)}
## A boss's slam ring on the floor.
const BOSS_WARN := Color(1.0, 0.1, 0.1)
