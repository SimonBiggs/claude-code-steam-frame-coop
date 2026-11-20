extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "the Coaster Crew",
	"you_vr": "the Builder",
	"you": "the Coaster Crew",
	"do": {"tv": ["A", "Press A to add track, then Y to ride!"], "vr": ["GRIP", "Grab the glowing piece onto the track!"]},
	"start": "phase() == 'build' or phase() == 'ride'",
	"rise": "st('track', []).size() + st('score', 0)",
}
