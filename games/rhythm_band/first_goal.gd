extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Guitarist",
	"you_vr": "the Drummer",
	"you": "in the Band",
	"do": {"tv": ["A", "Press as a ball reaches its ring!"], "vr": ["HANDS", "Hit a drum as its ball lands!"]},
	"start": "v('state') == 'play' or v('state') == 'practice'",
	"done": "v('band_hits', 0) > 0 or v('prac_first_done', -1.0) >= 0.0",
	"miss": "v('band_misses', 0)",
}
