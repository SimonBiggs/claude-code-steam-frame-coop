extends RefCounted
## Treasure Dig in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const Deep := preload("res://games/treasure_dig/deep.gd")
const SAVE_ID := "treasure_dig"  # the game's core/save.gd game_id
const WHO := "pirate"  # the story friend (a story picture)
const GROWS := "museum"  # what the family grows (a story picture or a UiKit icon): Peg's museum (games/treasure_dig/story_pictures.gd)
const COLOR := Color(0.95, 0.35, 0.35)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: Captain Peg's relics found (they stay on the pedestals for good, up to 10) + the glass cases in her museum
## (one every deep.gd CASE_EVERY treasures banked); daily: TODAY'S ISLAND dug today (data.daily is {date: score}, the
## newest 30 days, stamped when the island is finished).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var relics: Variant = data.get("relics", [])
	var days: Variant = data.get("daily", {})
	var museum: Variant = data.get("museum", {})
	return {"grown": ((relics as Array).size() if relics is Array else 0) + (Deep.cases(museum) if museum is Dictionary else 0),
		"daily": days is Dictionary and (days as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 42, "world": 123456, "islands": 7, "relics": [0, 1, 2], "daily": {today: 35},
		"visits": {"sunny": 3, "jungle": 2, "ice": 1, "volcano": 1}, "mode": "gentle", "gift": "detector",
		"museum": {"coins": 61, "gems": 22, "boots": 9, "maps": 6, "golden": 2}}
