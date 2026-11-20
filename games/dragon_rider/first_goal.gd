extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Bubble Gunner",
	"you_vr": "the Dragon Rider",
	"you": "a Dragon Rider",
	"do": {"tv": ["RT", "Pop a balloon with bubbles!"], "vr": ["HANDS", "Steer through a glowing ring!"]},
	"start": "v('phase', '') == 'fly'",
	"rise": "[sum(v('gstats', {})), v('rings_got', 0)][int(get('device') == 'vr')]",
	"target": "nearest('dr_targets')",
}
