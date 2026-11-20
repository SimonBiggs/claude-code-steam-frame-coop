extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Runner",
	"you_vr": "Giant TumTum",
	"you": "a Dodgeball Player",
	"do": {"tv": ["A", "Grab a ball, throw it at the belly!"], "vr": ["TRIGGER", "Grab a ball, throw it at a runner!"]},
	"start": "phase() == 'play'",
	"rise_tv": "st('tv_score', 0)",
	"rise_vr": "st('giant_score', 0) + v('giant_throws', 0)",
}
