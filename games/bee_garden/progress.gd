extends RefCounted
## Bee Garden in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "bee_garden"  # the game's core/save.gd game_id (Story.GAME_ID)
const WHO := "queenbee"  # the story friend (a story picture): Queen Bea
const GROWS := "honeyjar"  # what the family grows (a story picture or a UiKit icon): jars on Queen Bea's shelf
const COLOR := Color(1.0, 0.78, 0.2)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every honey jar ever put on the shelf; daily: a round of TODAY'S GARDEN finished today (main.gd
## _round_complete_simple sets daily_done; "daily" only means it was planted, so the next garden isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	return {"grown": maxi(0, int(data.get("jars", 0))), "daily": String(data.get("daily_done", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 123456, "jars": 17, "rounds": 6, "gardens": 3, "decor": 4, "daily": today, "daily_done": today, "best_round": 3}
