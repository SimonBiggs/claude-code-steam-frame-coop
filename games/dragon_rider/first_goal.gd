extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Bubble Gunner",
	"you_vr": "the Dragon Rider",
	"you": "a Dragon Rider",
	"do": {"tv": ["RT", "Pop a balloon with bubbles!"], "vr": ["HANDS", "Steer through a glowing ring!"]},
	"start": "v('phase', '') == 'fly'",
	"rise_tv": "sum(v('gstats', {}))",
	"rise_vr": "v('rings_got', 0)",
	"target": "nearest('dr_targets')",
	"seats": {0: {"you": "the Dragon Rider", "do": ["L-STICK", "Steer through a glowing ring!"], "as": "vr"}},  # flat P1 (no headset) plays the VR role
}
