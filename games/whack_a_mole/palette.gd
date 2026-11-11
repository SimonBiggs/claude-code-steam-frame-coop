extends RefCounted
## What must be seen in Whack-a-Mole, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The TV kids run on the table's grassy top (and the lawn round it, in every season's colour: deep.gd SEASONS); every
## kind of mole pops out of a dark hole in that top; the warned tricks' rings (deep.gd) glow on that top; the holiday
## moles lounge in their deckchairs on the lawn.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Props := preload("res://games/whack_a_mole/props.gd")
const Deep := preload("res://games/whack_a_mole/deep.gd")


static func key_colors() -> Dictionary:
	return Contrast.humanoids(Party.COLORS, Props.LOOKS)


static func backgrounds() -> Dictionary:
	var out := {"table top": Props.TOP}
	for s in Props.LAWNS:
		out["%s lawn" % s] = Props.LAWNS[s]
	return out


static func groups() -> Array:
	var lawns := {}
	for s in Props.LAWNS:
		lawns["%s lawn" % s] = Props.LAWNS[s]
	return [{"keys": Contrast.named("mole", Props.KIND_FUR), "bgs": {"table top": Props.TOP, "hole": Props.HOLE}},
		{"keys": {"gold trick warning": Deep.GOLD_COLOR, "stampede warning": Deep.HERD_COLOR}, "bgs": {"table top": Props.TOP}},
		{"keys": {"deckchair": Props.DECK_CHAIR}, "bgs": lawns}]