extends RefCounted
## PARTY BOARD minigames: what each little island's walkers stand on (mg_base.gd build_island and the minigames'
## own floors use these; palette.gd checks the players and hazards on them, core/contrast.gd).

## Each minigame island's grass (mg_base = the default build()).
const GRASS := {
	"mg_base": Color(0.45, 0.75, 0.38), "hot_potato": Color(0.62, 0.72, 0.36), "coin_catch": Color(0.5, 0.78, 0.38),
	"paint_splash": Color(0.5, 0.75, 0.42), "mole_bop": Color(0.48, 0.76, 0.36), "fish_pond": Color(0.46, 0.74, 0.36),
	"balloon_pop": Color(0.5, 0.8, 0.4), "kart_dash": Color(0.5, 0.74, 0.38), "sheep_herding": Color(0.52, 0.8, 0.4),
	"memory_tiles": Color(0.55, 0.7, 0.45), "star_stack": Color(0.52, 0.78, 0.42),
}
const SAND := Color(0.93, 0.84, 0.6)  ## every island's beach ring (and TREASURE DIVE's sandy floor)
const KART_ROAD: Array[Color] = [Color(0.42, 0.42, 0.46), Color(0.48, 0.48, 0.52)]  ## KART DASH lanes
const MEMORY_BLANK := Color(0.95, 0.95, 0.92)  ## MEMORY TILES: a hidden tile
const PLATFORM_TOP := Color(0.45, 0.75, 0.4)  ## FALLING PLATFORMS: the grassy top of a stepping stone
const PLATFORM_WARN := Color(1.0, 0.25, 0.1)  ## FALLING PLATFORMS: the ring round a stone about to drop
