extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you": "a Neon Defender",
	"do": {"tv": ["RT", "Shoot the glowing target!"], "vr": ["TRIGGER", "Shoot the glowing target!"]},
	"rise": "v('practice_step', 0) + v('score', 0)",
	"target": "v('practice_target')",
}
