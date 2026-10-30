extends RefCounted
## Ghost Lantern in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "ghost_lantern"  # the game's core/save.gd game_id
const WHO := "grannyboo"  # Granny Boo, the old ghost whose house it is
const GROWS := "jar"  # the ghost jars on her shelf
const COLOR := Color(1.0, 0.6, 0.75)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every ghost ever kept in a jar (the shelf); daily: TODAY'S HOUSE finished today (daily = {date: night}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	return {"grown": int(data.get("kept", 0)),
		"daily": (daily as Dictionary).has(today) if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 123456, "houses": 5, "kept": 17, "jars": {"snoozy": 8, "zippy": 6, "peekaboo": 3},
		"daily": {today: 3}, "best_night": 3, "nights": 6}
