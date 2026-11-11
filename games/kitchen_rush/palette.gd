extends RefCounted
## What must be seen in Kitchen Rush, and the floor and counter it is on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/kitchen_rush/looks.gd")
const Item := preload("res://games/kitchen_rush/item.gd")
const Nights := preload("res://games/kitchen_rush/nights.gd")


## The runners and the kitchen events' warning rings on the checked floor.
static func key_colors() -> Dictionary:
	return Contrast.merge(Contrast.named("runner", Looks.PLAYER_COLORS), Contrast.named("warning", Nights.EVENT_COLORS))


static func backgrounds() -> Dictionary:
	return {"floor tile": Looks.FLOOR_A, "floor tile 2": Looks.FLOOR_B}


static func groups() -> Array:
	var food := {}
	var chopped := {}
	for k in Item.INFO:
		food[String(k)] = Item.INFO[k][1]
		if int(Item.INFO[k][2]) > 0:
			chopped[String(k)] = Item.INFO[k][1]
	# Ingredients, plates and invitations sit on the counter and the pass; only things that are chopped go on the
	# chopping board.
	return [{"keys": food, "bgs": {"counter": Looks.COUNTER_TOP, "pass": Looks.PASS_STRIP}},
		{"keys": chopped, "bgs": {"chopping board": Looks.BOARD}}]
