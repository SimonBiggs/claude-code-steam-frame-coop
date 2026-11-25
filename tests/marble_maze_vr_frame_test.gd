extends "res://tests/vr_frame_kit.gd"
## VR FRAME guard for Marble Maze: its fake VR run (BOT_VR=1, the bot playing) must stay within these per-frame budgets
## (see tests/vr_frame_kit.gd for what is counted and why: 2026-11-19 slow VR night). Raise a budget only with a reason.
## Measured 2026-11-25 (hot streak branch): 3.8 redraws (the TV edge arrows), 0 added, 38 processing, 6 physics, 0 2D VPs.


func _setup() -> void:
	GAME = "marble_maze"
	WARM_S = 30.0
	MAX_REDRAWS = 6.0
	MAX_ADDED = 2.0
	MAX_PROCESSING = 50
	MAX_PHYSICS = 10
	MAX_VP2D = 0
