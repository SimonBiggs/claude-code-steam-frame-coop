extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Deckhand",
	"you_vr": "the Gunner",
	"you": "a Pirate",
	"do": {"tv": ["A", "Carry a cannonball to a cannon!"], "vr": ["GRIP", "Pull the cannon back, let go!"]},
	"rise_tv": "sum(v('stats', []))",
	"rise_vr": "v('practice_hits', 0) + sum(v('stats', []))",
}
