extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Balloon Jumper",
	"you_vr": "the Balloon Giant",
	"you": "a Balloon Popper",
	"do": {"tv": ["A", "Jump into a balloon to pop it!"], "vr": ["HANDS", "Punch a balloon to pop it!"]},
	"start": "phase() == 'play' or phase() == 'practice'",
	"rise": "v('total_popped', 0)",
	"target": "nearest_of(v('balloons', {}))",
}
