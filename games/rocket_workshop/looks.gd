extends RefCounted
## Rocket Workshop colours the game and palette.gd (tests/contrast_test.gd) both read, so they can't drift.

## The pilot (P1) and the TV crew (P3 a brighter green: the old one vanished on the yard grass).
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.55, 0.25), Color(0.3, 0.65, 1.0), Color(0.6, 0.95, 0.3),
	Color(1.0, 0.4, 0.6), Color(0.75, 0.5, 1.0), Color(1.0, 0.85, 0.25), Color(0.3, 0.9, 0.85)]
## The workshop's plank floor (world.gd FLOOR_SHADER: mix(FLOOR_A, FLOOR_B, up to FLOOR_MIX), seams darker by
## SEAM_DARK) and the yard's grass.
const FLOOR_A := Color(0.72, 0.5, 0.32)
const FLOOR_B := Color(0.58, 0.38, 0.22)
const FLOOR_MIX := 0.7
const SEAM_DARK := 0.4
const GRASS := Color(0.45, 0.72, 0.35)
## The crew's jobs (jobs.gd): the fuel canister, the loose bolts, the paint pots (COLORS lids on these pots) and
## the space cat.
const CANISTER := Color(0.95, 0.3, 0.25)
const BOLT := Color(1.0, 0.8, 0.3)
const PAINT_POT := Color(0.85, 0.85, 0.9)
const CAT_FUR := Color(1.0, 0.62, 0.25)
