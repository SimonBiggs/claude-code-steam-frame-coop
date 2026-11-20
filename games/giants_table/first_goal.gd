extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a tiny Knight",
	"you_vr": "the Giant",
	"you": "a Village Guard",
	"do": {"tv": ["RT", "Bonk a goblin with your sword!"], "vr": ["GRIP", "Grab a goblin and throw it!"]},
	# goblins beaten or caught (core/rescue.gd successes, host / local); goblins that reached the fire = misses
	"rise": "v('rescue').successes if v('rescue') != null else 0",
	"miss": "v('game_lost', 0)",
	"target": "nearest('goblins')",
}
