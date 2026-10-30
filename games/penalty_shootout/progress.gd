extends RefCounted
## Penalty Shootout in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "penalty_shootout"  # the game's core/save.gd game_id
const WHO := "lion"  # the story friend (a story picture)
const GROWS := "trophy"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(1.0, 0.72, 0.25)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every prize Leo has won for his fan club; daily: TODAY'S MATCH played today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var prizes: Variant = data.get("prizes", [])
	return {"grown": maxi(int(data.get("goals", 0)), (prizes as Array).size() if prizes is Array else 0),
		"daily": String(data.get("daily", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"prizes": [["scarf", 1, true], ["balloon", 2, false], ["drum", 3, true]], "goals": 3, "days": 3,
		"last_day": today, "daily": today, "cups": 5, "matches": 9, "stars": 12, "best_stars": 3}
