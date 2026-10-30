extends RefCounted
## Treasure Dig in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "treasure_dig"  # the game's core/save.gd game_id
const WHO := "pirate"  # the story friend (a story picture)
const GROWS := "crown"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.95, 0.35, 0.35)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: Captain Peg's relics found (they stay on the pedestals for good, up to 10); daily: TODAY'S ISLAND dug today
## (data.daily is {date: score}, the newest 30 days).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var relics: Variant = data.get("relics", [])
	var days: Variant = data.get("daily", {})
	return {"grown": (relics as Array).size() if relics is Array else 0,
		"daily": days is Dictionary and (days as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 42, "world": 123456, "islands": 7, "relics": [0, 1, 2], "daily": {today: 35},
		"visits": {"sunny": 3, "jungle": 2, "ice": 1, "volcano": 1}}
