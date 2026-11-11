extends RefCounted
## What must be seen in Sheep Round-Up, and every ground it sits on (core/contrast.gd; tests/contrast_test.gd).
## 2026-11: white sheep vanished on the old snowy winter grass; the winter grass is frosty green since.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Seasons := preload("res://games/sheep_round_up/seasons.gd")
const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")


static func key_colors() -> Dictionary:
	var out := {}
	for b in FieldGen.BREEDS:
		out["%s sheep" % b.id] = b.wool  # (not the face: it is too small to count)
	for i in Party.COLORS.size():
		out["dog %d" % (i + 1)] = Seasons.dog_color(Party.COLORS[i])
	return Contrast.merge(out, Contrast.named("warning", Seasons.EVENT_COLORS))


## The field's grass every season (weather.gd ground_color reads SEASON_LOOK).
static func backgrounds() -> Dictionary:
	return Contrast.field("grass", Seasons.SEASON_LOOK, "ground")
