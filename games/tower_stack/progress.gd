extends RefCounted
## Tower Stack in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "tower_stack"  # the game's core/save.gd game_id
const WHO := "wren"  # the story friend (a story picture)
const GROWS := "tower"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.55, 0.75, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every building Wren's town has had (the town shows the newest ones); daily: TODAY'S TOWER built today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var town: Variant = data.get("town", [])
	return {"grown": maxi(int(data.get("built", 0)), (town as Array).size() if town is Array else 0),
		"daily": String(data.get("daily", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 9.5, "built": 14, "town": [{"b": 0}, {"b": 1}, {"b": 2}], "daily": today, "sessions": 4}
