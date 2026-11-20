extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Tower Helper",
	"you_vr": "the Giant",
	"you": "a Tower Helper",
	"do": {"tv": ["L-STICK", "Push a block onto the glowing pad!"], "vr": ["TRIGGER", "Grab a block, put it in a glowing spot!"]},
	"start": "phase() == 'play'",
	"rise": "st('fill', 0) + st('built', 0)",
}
