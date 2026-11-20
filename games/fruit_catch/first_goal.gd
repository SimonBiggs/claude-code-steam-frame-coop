extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Fruit Catcher",
	"you_vr": "the Tree Shaker",
	"you": "a Fruit Catcher",
	"do": {"tv": ["L-STICK", "Run under the falling fruit!"], "vr": ["GRIP", "Grab a branch and shake it!"]},
	"start": "phase() == 'play'",
	"rise": "st('caught', 0) + st('score', 0)",
}
