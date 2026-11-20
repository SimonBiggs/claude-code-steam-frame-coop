extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Little Rower",
	"you_vr": "the Angler",
	"you": "a Fisher",
	"do": {"tv": ["L-STICK", "Row to a floating treasure!"], "vr": ["TRIGGER", "Flick your rod to cast!"]},
	"rise_tv": "v('scooped', 0) + v('catches', []).size()",
	"rise_vr": "v('catches', []).size()",
	"seats": {0: {"you": "the Angler", "do": ["A", "Hold A to cast, again to reel!"], "as": "vr"}},  # flat P1 (no headset) plays the VR role
}
