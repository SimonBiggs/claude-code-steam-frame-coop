extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Paper Plane Pilot",
	"you_vr": "the Plane Thrower",
	"you": "a Paper Plane Flyer",
	"do": {"tv": ["L-STICK", "Fly through a hoop!"], "vr": ["TRIGGER", "Grab a plane and throw it!"]},
	"start": "phase() == 'play'",
	"rise": "v('hoops_passed', 0) + st('score', 0)",
	"target": "nearest_of(v('hoops', {}))",
}
