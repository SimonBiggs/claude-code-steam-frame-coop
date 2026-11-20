extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	# SIMPLE_MODE with no how-to words (its bot fails on words): the TV card is the button + a picture, VR just the arrow
	"wordless": true,
	"icon": "star",
	"you": "a Party Island player",
	"do": {"tv": ["A", "On your turn, press A to roll!"], "vr": ["HANDS", "Throw the big dice onto the board!"]},
	"start": "phase() == 'board'",
	# a turn taken (host / local)
	"rise": "(v('flow').turn_i + v('flow').round_n * 10) if v('flow') != null else 0",
}
