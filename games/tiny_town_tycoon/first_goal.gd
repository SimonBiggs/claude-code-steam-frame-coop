extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	# SIMPLE_MODE with no how-to words (its bot fails on words): the TV card is the button + a picture, VR just the arrow
	"wordless": true,
	"icon": "flag",
	"you_tv": "a Town Driver",
	"you_vr": "the Mayor",
	"you": "a Town Driver",
	"do": {"tv": ["L-STICK", "Drive to the glowing spot!"], "vr": ["TRIGGER", "Grab a road block, draw a street!"]},
	"start": "phase() == 'play'",
	"rise": "main.town.buildings.size() + sum(v('sim', {}).get('counters'))",
}
