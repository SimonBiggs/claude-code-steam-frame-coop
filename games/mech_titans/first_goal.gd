extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	# SIMPLE_MODE with no how-to words (its bot fails on words): the TV card is the button + a picture, VR just the arrow
	"wordless": true,
	"icon": "bolt",
	"you_tv": "the Titan Crew",
	"you_vr": "TITAN-1's Pilot",
	"you": "a Titan Crew",
	"do": {"tv": ["L-STICK", "Go to the glowing ring or target!"], "vr": ["HANDS", "Punch the glowing target!"]},
	"start": "phase() == 'play'",
	# score, a support ring flown through, or (VR) a practice target done
	"rise_tv": "st('score', 0) + v('toys').rings_popped",
	"rise_vr": "st('score', 0) + v('toys').rings_popped - v('missions').practice_parts.size()",
}
