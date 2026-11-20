extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Guesser",
	"you_vr": "the Artist",
	"you": "a Painter",
	"do": {"tv": ["A", "Pick what's being painted!"], "vr": ["TRIGGER", "Hold it on the easel to paint!"]},
	"start": "v('state', '') == 'draw'",
	# VR: a stroke painted; TV: the first guesser's points
	"rise_tv": "v('players')[1].score if v('players', []).size() > 1 else 0",
	"rise_vr": "v('next_stroke_id', 1)",
	"seats": {0: {"you": "the Artist", "do": ["A", "Hold A and move the stick to paint!"], "as": "vr"}},  # flat P1 (no headset) plays the VR role
}
