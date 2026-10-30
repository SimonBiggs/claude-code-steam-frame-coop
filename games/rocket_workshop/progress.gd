extends RefCounted
## Rocket Workshop in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "rocket_workshop"  # the game's core/save.gd game_id
const WHO := "engineer"  # the story friend (a story picture)
const GROWS := "toyrocket"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.25, 0.75, 0.8)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every rocket the crew has launched (Rocket Row keeps the newest models); daily: TODAY'S ROCKET launched today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var museum: Variant = data.get("museum", [])
	return {"grown": maxi(int(data.get("launched", 0)), (museum as Array).size() if museum is Array else 0),
		"daily": String(data.get("daily", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"launched": 6, "museum": [{"look": {}, "planet": 0, "date": today, "daily": false, "n": 1},
		{"look": {}, "planet": 1, "date": today, "daily": true, "n": 2}], "daily": today, "sessions": 3}
