extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Ghost Vacuumer",
	"you_vr": "the Lantern Keeper",
	"you": "a Ghost Hunter",
	"do": {"tv": ["RT", "Hold to vacuum a glowing ghost!"], "vr": ["HANDS", "Shine your lantern on the ghost!"]},
	"done": "[sum(v('tv_catches', {})) > 0 or v('caught', 0) > 0, not v('practice', false) or v('caught', 0) > 0][int(get('device') == 'vr')]",
	"target": "nearest('ghosts')",
}
