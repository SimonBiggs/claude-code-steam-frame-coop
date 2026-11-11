extends RefCounted
## What must be seen in Whack-a-Mole, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The TV kids run on the table's grassy top (and the lawn round it); every kind of mole pops out of a dark hole
## in that top.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Props := preload("res://games/whack_a_mole/props.gd")


static func key_colors() -> Dictionary:
	return Contrast.humanoids(Party.COLORS, Props.LOOKS)


static func backgrounds() -> Dictionary:
	return {"table top": Props.TOP, "lawn": Props.LAWN}


static func groups() -> Array:
	return [{"keys": Contrast.named("mole", Props.KIND_FUR), "bgs": {"table top": Props.TOP, "hole": Props.HOLE}}]
