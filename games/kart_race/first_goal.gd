extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you": "a Kart Racer",
	"do": {"tv": ["A", "Hold A to go! Drive through the ring"], "vr": ["TRIGGER", "Hold the wheel, pull to go!"]},
	"start": "v('practice_gate', -1) >= 0 or v('state', '') == 'race'",
	# a practice ring popped, or ten seconds of real racing
	"done": "v('practice_gate', -1) > 0 or (v('state', '') == 'race' and v('state_t', 0.0) > 10.0)",
}
