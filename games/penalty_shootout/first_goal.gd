extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Striker",
	"you_vr": "the Goalkeeper",
	"you": "a Footballer",
	"do": {"tv": ["A", "Hold A, let go to shoot!"], "vr": ["HANDS", "Touch the ball to save it!"]},
	# practice rings hit, keeper practice saves, shots, saves
	"rise": "v('sp_hits', 0) + v('kp_step', 0) + v('shots_total', 0) + v('saves', 0)",
}
