extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Tiny Runner",
	"you_vr": "the Giant Builder",
	"you": "a Block Builder",
	"do": {"tv": ["A", "Jump over to the flag!"], "vr": ["TRIGGER", "Grab a plank, drop it in the gap!"]},
	"done_tv": "v('ring_state', 0) >= 2 or v('first_flag_t', -1.0) >= 0.0",
	"done_vr": "v('place_total', 0) > 0",
}
