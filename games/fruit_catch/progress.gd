extends RefCounted
## Fruit Catch in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "fruit_catch"  # the game's core/save.gd game_id
const WHO := "squirrel"  # the story friend (a story picture): Nutmeg the squirrel
const GROWS := "sapling"  # what the family grows (a story picture or a UiKit icon): trees in the orchard
const COLOR := Color(0.85, 0.45, 0.18)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every orchard tree ever planted (trees; the orchard keeps the newest 36); daily: TODAY'S HARVEST finished today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var orchard: Variant = data.get("orchard", [])
	return {"grown": maxi(int(data.get("trees", 0)), (orchard as Array).size() if orchard is Array else 0),
		"daily": String(data.get("daily", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 52, "orchard": [[0, 1, true, 2], [1, 1, false, 1], [2, 2, true, 3]], "trees": 3, "dishes": 6, "days": 2,
		"last_day": today, "daily": today, "sessions": 3}
