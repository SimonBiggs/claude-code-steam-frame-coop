extends "res://tests/vr_frame_kit.gd"
## VR FRAME guard for this game: its fake VR run (BOT_VR=1, the bot playing) must stay within these per-frame budgets
## (see tests/vr_frame_kit.gd for what is counted and why: 2026-11-19 slow VR night). Raise a budget only with a reason.


func _setup() -> void:
	GAME = "sky_bots"
	WARM_S = 30.0
	MAX_REDRAWS = 8.0
	MAX_ADDED = 2.0
	MAX_PROCESSING = 65
	MAX_PHYSICS = 12
	MAX_VP2D = 0
