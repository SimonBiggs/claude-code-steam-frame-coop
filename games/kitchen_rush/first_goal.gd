extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Kitchen Runner",
	"you_vr": "the Chef",
	"you": "a Cook",
	"do": {"tv": ["A", "Grab a BUN from the glowing crate!"], "vr": ["HANDS", "Chop the cheese on the board!"]},
	# chops, fetches, dishes, plates served (host / local)
	"rise": "sum(v('stats', []))",
	"seats": {0: {"you": "the Chef", "do": ["X", "Chop the cheese on the board!"], "as": "vr"}},  # flat P1 (no headset) plays the VR role
}
