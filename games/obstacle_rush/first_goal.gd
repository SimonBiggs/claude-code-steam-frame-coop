extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Jelly-Bean Runner",
	"you_vr": "the Giant",
	"you": "an Obstacle Runner",
	"do": {"tv": ["A", "Run and jump to the glowing ring!"], "vr": ["TRIGGER", "Grab a ball and throw it!"]},
	"start": "phase() == 'play'",
	"rise_tv": "v('ring_done', {}).size() + v('finish_log', []).size()",
	"rise_vr": "v('giant').throws if v('giant') != null else 0",
}
