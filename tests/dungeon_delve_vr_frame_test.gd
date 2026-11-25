extends "res://tests/vr_frame_kit.gd"
## VR FRAME guard for Dungeon Delve's deep dungeon (BRAVE, fake VR knight + bot heroes): the per-frame budgets of
## tests/vr_frame_kit.gd. 2026-11-25 baseline: 1.4 redraws, 0.4 added, 43 processing, 2 physics (the "what now?"
## guide pill and gold chevrons included). Raise a budget only with a reason.


func _setup() -> void:
	GAME = "dungeon_delve"
	WARM_S = 25.0
	MAX_REDRAWS = 6.0
	MAX_ADDED = 2.0
	MAX_PROCESSING = 60
	MAX_PHYSICS = 6
	MAX_VP2D = 0
	EXTRA_ENV = {"DD_MODE": "brave"}
