extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "the Hero's Party",
	"you_vr": "the Hero",
	"you": "a Crystal Hero",
	"do": {"tv": ["A", "Shoot a spark at the dummy!"], "vr": ["HANDS", "Swing your sword at the dummy!"]},
	"rise": "sum(v('log_hits', {}))",
}
