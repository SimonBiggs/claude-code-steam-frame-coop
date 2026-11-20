extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Sheepdog",
	"you_vr": "the Farmer",
	"you": "a Sheepdog",
	"do": {"tv": ["L-STICK", "Run behind a sheep, push it to the pen!"], "vr": ["TRIGGER", "Grab a sheep, drop it in the pen!"]},
	"start": "phase() == 'play'",
	"rise": "st('home', 0)",
	"target": "nearest_of(v('sheep', []))",
}
