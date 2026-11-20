extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Snow Roller",
	"you_vr": "the Builder",
	"you": "a Snow Roller",
	"do": {"tv": ["L-STICK", "Push a snowball into the circle!"], "vr": ["TRIGGER", "Grab a snowball, stack it up!"]},
	"start": "phase() == 'play'",
	"rise": "st('stacks', {}).size() + st('score', 0)",
}
