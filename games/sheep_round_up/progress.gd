extends RefCounted
## Sheep Round-Up in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "sheep_round_up"  # the game's core/save.gd game_id
const WHO := "shepherd"  # the story friend (a story picture)
const GROWS := "sheep"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.95, 0.45, 0.6)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every sheep that has gone home to Bo's farm for good; daily: TODAY'S FIELD played today
## (data.daily is {date: best result}, the newest 30 days).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var days: Variant = data.get("daily", {})
	return {"grown": int(data.get("home", 0)), "daily": days is Dictionary and (days as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 4, "level": 4, "home": 27, "breeds": {"white": 20, "lamb": 7}, "built": [], "rounds": 9,
		"world": 123456, "daily": {today: 12}, "stars": {"0": 3, "1": 2}, "tips": [], "met_bo": true}
