extends RefCounted
## Snowball Blitz in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "snowball_blitz"  # the game's core/save.gd game_id
const WHO := "polarbear"  # the story friend (a story picture)
const GROWS := "igloo"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.3, 0.6, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every igloo built in Bobo's village (the village shows the newest ones); daily: TODAY'S BLIZZARD won an igloo today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var village: Variant = data.get("village", [])
	return {"grown": maxi(int(data.get("igloos", 0)), (village as Array).size() if village is Array else 0),
		"daily": String(data.get("daily", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"village": [[1, false, 3, 0], [2, true, 4, 2], [3, true, 5, 1]], "igloos": 3, "days": 3, "last_day": today,
		"daily": today, "games": 6, "best_wave": 5, "wins": 2}
