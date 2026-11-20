extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you": "an Elemental Bender",
	"do": {"tv": ["RT", "Bend at the glowing dummy!"], "vr": ["TRIGGER", "Hold, then punch at the dummy!"]},
	"rise": "st('score', 0)",
	"target": "nearest('eb_enemy')",
}
