extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Sky Robot",
	"you_vr": "the Giant",
	"you": "a Sky Robot",
	"do": {"tv": ["A", "Run and jump: grab a shiny bolt!"], "vr": ["HANDS", "Pick up a bolt for the robots!"]},
	"start": "phase() == 'play'",
	"rise": "sum(Array(st('bolts', PackedInt32Array()))) + st('cp', 0)",
}
