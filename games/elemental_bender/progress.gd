extends RefCounted
## Elemental Bender in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "elemental_bender"  # the game's core/save.gd game_id
const WHO := "kiko"  # the story friend (a story picture): Kiko the temple fox
const GROWS := "spirittree"  # what the family grows (a story picture or a UiKit icon): the Spirit Tree
const COLOR := Color(1.0, 0.85, 0.3)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: waves cleared over all days (they grow the Spirit Tree, WaveGen.tree_stage); daily: TODAY'S RAIDERS played to the end today (daily_done; "daily" only
## says it started, so the next round isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	return {"grown": maxi(0, int(data.get("waves", 0))), "daily": String(data.get("daily_done", "")) == today,
		"played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best_wave": 6, "best_score": 900, "days": 3, "last_day": today, "daily": today, "daily_done": today, "games": 5, "waves": 14,
		"fruit": [0, 2], "generals": 2, "best_today": [today, 6], "raiders": 80}
