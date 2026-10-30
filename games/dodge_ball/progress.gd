extends RefCounted
## Dodge Ball in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "dodge_ball"  # the game's core/save.gd game_id (CourtGen.GAME_ID)
const WHO := "tumtum"  # the story friend (a story picture): TumTum the friendly giant
const GROWS := "toadstool"  # what the family grows (a story picture or a UiKit icon): things planted in the park
const COLOR := Color(1.0, 0.6, 0.3)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: everything ever planted in the park (park_total; the park keeps the newest); daily: TODAY'S PARK finished today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var park: Variant = data.get("park", [])
	return {"grown": maxi(int(data.get("park_total", 0)), (park as Array).size() if park is Array else 0),
		"daily": String(data.get("daily", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"park": [["daisy", 1, true], ["sunflower", 1, false], ["toadstool", 2, true]], "park_total": 3, "rounds": 3,
		"days": 2, "last_day": today, "daily": today, "sessions": 3, "belly_total": 4, "best_runners": 2}
