extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Treasure Digger",
	"you_vr": "the Giant",
	"you": "a Treasure Digger",
	"do": {"tv": ["A", "Run to a sparkle and press A to dig!"], "vr": ["TRIGGER", "Point the telescope at the sand, pull!"]},
	"start": "phase() == 'play'",
	"rise": "st('found', 0) + st('score', 0)",
}
