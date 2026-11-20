extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Marble",
	"you_vr": "the Giant at the maze",
	"you": "a Marble Roller",
	"do": {"tv": ["L-STICK", "Roll through the glowing ring!"], "vr": ["GRIP", "Grab the handles and tilt!"]},
	"start": "v('state', '') == 'play'",
	"rise": "v('ring_hit', {}).size()",
	"done": "v('state', '') == 'clear'",
	"target": "v('ring_node')",
	"seats": {0: {"you": "the Giant at the maze", "do": ["L-STICK", "Tilt the table to roll to the ring!"], "as": "vr"}},  # flat P1 (no headset) plays the VR role
}
