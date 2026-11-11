extends RefCounted
## Snowball Blitz colours the game and palette.gd (tests/contrast_test.gd) both read, so they can't drift.
## White snowmen, snowballs and the MEGA SNOWBALL vanished on the snow (2026-11 contrast sweep): they wear the ink
## outline (core/contrast.gd outline, OUTLINE) - snowmen stay snow-white.

const Contrast := preload("res://core/contrast.gd")

const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.35, 0.3), Color(0.3, 0.7, 1.0), Color(0.5, 0.85, 0.35),
	Color(1.0, 0.82, 0.25), Color(0.75, 0.45, 1.0), Color(1.0, 0.55, 0.15), Color(0.3, 0.95, 0.85)]
const OUTLINE := Contrast.OUTLINE
## Snowmen's bodies (main.mat "snow"), the yeti's fur, the fort walls.
const SNOW_BODY := Color(0.95, 0.97, 1.0)
const YETI_FUR := Color(0.82, 0.9, 1.0)
const FORT := Color(0.88, 0.93, 1.0)
## Thrown snowballs: the players' and the snowmen's (icy, glowing).
const SNOWBALL := Color(1.0, 1.0, 1.0)
const ENEMY_BALL := Color(0.6, 0.85, 1.0)
## The MEGA SNOWBALL pickup and the glowing ring round it on the snow (was pale sky blue: vanished on the snow).
const MEGA_BALL := Color(0.8, 0.92, 1.0)
const MEGA_RING := Color(0.3, 0.75, 1.0)
## The square's snow (world.gd ground shader: mix(SNOW_SHADE, SNOW, 0.55..1) with noise).
const SNOW := Color(0.86, 0.9, 1.0)
const SNOW_SHADE := Color(0.62, 0.68, 0.86)
const SNOW_MIN_MIX := 0.55


## The darkest snow the ground shader draws.
static func snow_dark() -> Color:
	return SNOW_SHADE.lerp(SNOW, SNOW_MIN_MIX)


## The sky [top, horizon] at night (-1 morning .. 0 dusk .. 1 aurora night), sunny = the sunshine event.
static func sky(night: float, sunny: bool) -> Array[Color]:
	var top := Color(0.12, 0.12, 0.32)
	var hor := Color(0.95, 0.55, 0.45)
	if night >= 0.0:
		top = top.lerp(Color(0.02, 0.03, 0.1), night)
		hor = hor.lerp(Color(0.18, 0.16, 0.38), night)
	else:
		top = top.lerp(Color(0.35, 0.55, 0.9), -night)
		hor = hor.lerp(Color(1.0, 0.82, 0.62), -night)
	if sunny:
		top = top.lerp(Color(0.4, 0.6, 0.95), 0.7)
		hor = hor.lerp(Color(1.0, 0.9, 0.7), 0.7)
	return [top, hor]
