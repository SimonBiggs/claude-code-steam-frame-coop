extends RefCounted

const Contrast := preload("res://core/contrast.gd")
## Cannon Cove colours the game and palette.gd (tests/contrast_test.gd) both read, so they can't drift.

## The gunner (P1) and up to six deckhands.
const PLAYER_COLORS: Array[Color] = [Color(0.25, 0.45, 0.95), Color(1.0, 0.75, 0.2), Color(1.0, 0.45, 0.8),
	Color(0.35, 0.9, 0.4), Color(0.3, 0.9, 0.95), Color(1.0, 0.5, 0.15), Color(0.7, 0.45, 1.0)]
## Deckhands' dark trousers (player.gd: always seen below the coat).
const DECKHAND_TROUSERS := Color(0.25, 0.22, 0.3)
## Cannonballs (ball.gd): ours, the pirates', the golden mega ball, and the smoke trail each leaves.
const BALL := Color(0.1, 0.1, 0.12)
const ENEMY_BALL := Color(0.25, 0.08, 0.08)
const MEGA_BALL := Color(1.0, 0.8, 0.2)
const SMOKE := Color(1.0, 0.9, 0.7, 0.55)
const ENEMY_SMOKE := Color(1.0, 0.5, 0.35, 0.6)
const MEGA_SMOKE := Color(1.0, 0.85, 0.3, 0.8)
## The golden ball wears the ink outline (it vanished on the dawn horizon).
const OUTLINE := Contrast.OUTLINE
## Pirate ships' hulls (enemy_ship.gd; the sails are KINDS' last entry).
const HULL := Color(0.32, 0.2, 0.12)
const TREASURE_HULL := Color(0.45, 0.28, 0.12)
## The boarders' shirts, the sea monster's skin.
const BOARDER_SHIRT := Color(0.9, 0.15, 0.15)
const TENTACLE_SKIN := Color(0.55, 0.25, 0.75)
const KRAKEN_SKIN := Color(0.5, 0.2, 0.62)
## Floating targets (target.gd): the raft, the bullseye's red, the supply barrel's glowing band, the chest's gold lid.
const RAFT := Color(0.6, 0.42, 0.22)
const BULLSEYE := Color(0.95, 0.15, 0.12)
const SUPPLY_RING := Color(0.4, 1.0, 0.5)
const CHEST_GOLD := Color(1.0, 0.78, 0.2)
## Our deck's planks (world.gd DECK_SHADER: mix(DECK_DARK, DECK_WOOD) per plank) and the sea (SEA_SHADER: deep ..
## shallow by wave height, darkened by the mood's night).
const DECK_WOOD := Color(0.78, 0.55, 0.3)
const DECK_DARK := Color(0.55, 0.36, 0.18)
const SEA_DEEP := Color(0.02, 0.3, 0.52)
const SEA_SHALLOW := Color(0.08, 0.72, 0.78)
const SEA_NIGHT_DIM := 0.45


## What the sea shader draws for c at a mood's night value.
static func sea_at(c: Color, night: float) -> Color:
	var k := lerpf(1.0, SEA_NIGHT_DIM, night)
	return Color(c.r * k, c.g * k, c.b * k)
