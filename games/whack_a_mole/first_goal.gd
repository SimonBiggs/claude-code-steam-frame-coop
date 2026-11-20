extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Hammer Kid",
	"you_vr": "the Giant",
	"you": "a Hammer Kid",
	"do": {"tv": ["A", "Run to a mole and press A to bonk!"], "vr": ["HANDS", "Swing the mallet at a mole!"]},
	"start": "phase() == 'play' or phase() == 'practice'",
	"rise": "st('score', 0)",
}
