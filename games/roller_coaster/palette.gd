extends RefCounted
## What must be seen in Roller Coaster (Coaster Crew), and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The builder (and the TV) look down on the tabletop park: the train's cars (each with its dark seat well,
## train.gd seat_color) and the red rails run over the park's grass and sandy paths.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const Train := preload("res://games/roller_coaster/train.gd")
const Deep := preload("res://games/roller_coaster/deep.gd")


static func key_colors() -> Dictionary:
	var cars := Contrast.named("car", Party.COLORS)
	cars.merge({"bot car": Train.BOT_CAR, "guest car": Train.GUEST_CAR})
	var out := {"rail": Track.RAIL_COL}
	for k in cars:
		out[k] = {"color": cars[k], "rim": Train.seat_color(cars[k])}
	# The warned weather's steady discs (hazards.gd) lie on the grass along the track.
	out["gust disc"] = Deep.GUST_COLOR
	out["sleepy disc"] = Deep.SLEEPY_COLOR
	return out


## The park's grass in every season (season.gd tints the table) and the sandy paths.
static func backgrounds() -> Dictionary:
	var out := {"park grass": Track.PARK_GRASS, "park path": Track.PARK_PATH}
	for s in Deep.SEASONS:
		out["%s grass" % s] = Deep.season_data(s).grass
	return out
