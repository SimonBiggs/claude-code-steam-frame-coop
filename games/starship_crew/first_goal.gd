extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Gunner",
	"you_vr": "the Pilot",
	"you": "a Gunner",
	"do": {"tv": ["A", "Put your crosshair on a rock, press A!"], "vr": ["TRIGGER", "Grab the stick, fly through a ring!"]},
	"start": "phase() == 'play'",
	"rise": "st('stars', 0)",
}
