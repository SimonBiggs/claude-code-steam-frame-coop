extends RefCounted
## First goal (core/first_goal.gd): what a first-time player is and the one thing to do first.

const GOAL := {
	"you_tv": "a Hider",
	"you_vr": "the Seeker",
	"you": "a Hide-and-Seeker",
	# (local play without a headset: P1 seeks, so the TV line names both jobs)
	"do": {"tv": ["L-STICK", "Hide! Seeker: go and find them!"], "vr": ["TRIGGER", "Shine your torch on a hider!"]},
	"start": "phase() == 'count' or phase() == 'seek'",
	# a find, a squeak, or anyone safely hidden for a few seconds
	"rise": "v('finds', 0) + sum(v('squeaks', [])) + min(1.0, floor(sum(v('hidden_time', [])) / 3.0))",
}
