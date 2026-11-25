extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Little Hero",
	"you_vr": "the Knight",
	"you": "a Dungeon Hero",
	"do": {"tv": ["A", "Bonk a pot!"], "vr": ["HANDS", "Swing your big sword!"]},
	"rise": "sum(v('log_bops', {})) + v('bonked', {}).size()",
}
