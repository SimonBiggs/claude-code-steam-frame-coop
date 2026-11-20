extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "the Rocket Crew",
	"you_vr": "the Pilot",
	"you": "the Rocket Crew",
	"do": {"tv": ["L-STICK", "Walk to a board, tell the pilot!"], "vr": ["HANDS", "Press the glowing button on the desk!"]},
	"start": "phase() == 'work'",
	"done": "phase() == 'ready' or phase() == 'launch'",
	"seats": {0: {"you": "the Pilot", "do": ["L-STICK", "Point at the glowing button, press A!"], "as": "vr"}},  # flat P1 (no headset) plays the VR role
}
