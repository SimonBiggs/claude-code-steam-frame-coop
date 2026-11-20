extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Busy Bee",
	"you_vr": "the Gardener",
	"you": "a Gardener's Helper",
	"do": {"tv": ["L-STICK", "Fly into a glowing flower!"], "vr": ["TRIGGER", "Push a seed into the soil!"]},
	"start": "v('phase', '') == 'intro' or v('phase', '') == 'day'",
	"rise_tv": "v('stats', {}).get('pollen', 0)",
	"rise_vr": "v('stats', {}).get('planted', 0)",
}
