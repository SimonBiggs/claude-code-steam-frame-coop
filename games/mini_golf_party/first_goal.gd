extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you": "a Mini Golfer",
	"do": {"tv": ["A", "Hold A, then let go to putt!"], "vr": ["HANDS", "Swing the putter through the ball!"]},
	"start": "phase() == 'play'",
	"rise": "v('putted', {}).size() + v('sink_log', []).size()",
	"target": "v('balls', {}).get(local_slot(), null)",
}
