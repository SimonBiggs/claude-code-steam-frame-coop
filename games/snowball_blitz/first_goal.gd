extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Snowball Thrower",
	"you_vr": "the Sniper",
	"you": "a Snowball Thrower",
	"do": {"tv": ["RT", "Aim at a snowman, press RT to throw!"], "vr": ["HANDS", "Scoop snow, throw it at a snowman!"]},
	"rise": "v('score', 0)",
}
