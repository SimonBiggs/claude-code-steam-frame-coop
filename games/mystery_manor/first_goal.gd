extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "the Detective's Assistant",
	"you_vr": "the Detective",
	"you": "a Detective",
	"do": {"tv": ["L-STICK", "Run to a sparkly clue!"], "vr": ["L-STICK", "Walk to a sparkly clue!"]},
	"rise": "st('found', [false, false, false]).count(true)",
	"target": "nearest_of(v('clue_nodes', []))",
}
