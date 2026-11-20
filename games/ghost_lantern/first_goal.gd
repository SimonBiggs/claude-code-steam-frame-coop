extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Ghost Vacuumer",
	"you_vr": "the Lantern Keeper",
	"you": "a Ghost Hunter",
	"do": {"tv": ["RT", "Hold to vacuum a glowing ghost!"], "vr": ["HANDS", "Shine your lantern on the ghost!"]},
	"done_tv": "sum(v('tv_catches', {})) > 0 or v('caught', 0) > 0",
	"done_vr": "not v('practice', false) or v('caught', 0) > 0",
	"target": "nearest('ghosts')",
	"seats": {0: {"you": "the Lantern Keeper", "do": ["RT", "Hold RT, shine the lantern on a ghost!"], "as": "vr"}},  # flat P1 (no headset) plays the VR role
}
