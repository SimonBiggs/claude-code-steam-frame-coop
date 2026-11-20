extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Little Boat",
	"you_vr": "the Big Splasher",
	"you": "a Duck Rescuer",
	"do": {"tv": ["L-STICK", "Bump a duck, sail it to the plug!"], "vr": ["TRIGGER", "Grab a duck, throw it in the plug!"]},
	"start": "phase() == 'play'",
	"rise": "st('score', 0)",
}
