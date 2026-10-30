extends RefCounted
## Tiny Town Tycoon in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "tiny_town_tycoon"  # the game's core/save.gd game_id
const WHO := "beaver"  # the story friend (a story picture)
const GROWS := "house"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.75, 0.5, 0.3)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: the buildings in Benny's home town (towns.home, or towns.meadow in older saves: {"town": {"b": [...]}});
## daily: the family sailed to TODAY'S ISLAND today (today_date).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var towns: Variant = data.get("towns", {})
	var home: Variant = {}
	if towns is Dictionary:
		home = (towns as Dictionary).get("meadow", (towns as Dictionary).get("home", {}))
	var t: Variant = (home as Dictionary).get("town", {}) if home is Dictionary else {}
	var b: Variant = (t as Dictionary).get("b", []) if t is Dictionary else []
	return {"grown": (b as Array).size() if b is Array else 0, "daily": String(data.get("today_date", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	var town := {"island": 0, "b": [[1, [0, 3, 4, 0]], [2, [1, 6, 4, 0]], [3, [0, 5, 7, 1]]], "next_id": 4, "seed": 4242}
	return {"stars": {}, "towns": {"home": {"town": town, "coins": 120, "tier": 1, "counters": {}, "goals": [], "hour": 9.0,
		"wishes": 4}, "today": {"town": {"b": []}}}, "last": 0, "home_seed": 4242, "today_date": today, "met_benny": true}
