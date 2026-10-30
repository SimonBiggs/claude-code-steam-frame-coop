extends RefCounted
## Bubble Bath in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "bubble_bath"  # the game's core/save.gd game_id
const WHO := "mamaduck"  # the story friend (a story picture): Mama Duck
const GROWS := "beachball"  # what the family grows (a story picture or a UiKit icon): bath toys on the rim
const COLOR := Color(1.0, 0.8, 0.2)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every toy Mama Duck has been given (goals; the rim keeps the newest 12); daily: a TODAY'S BATH round finished today (daily_done; "daily" only
## says it started, so the next round isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var toys: Variant = data.get("toys", [])
	return {"grown": maxi(int(data.get("goals", 0)), (toys as Array).size() if toys is Array else 0),
		"daily": String(data.get("daily_done", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 27, "toys": [["boat", 1, true], ["beachball", 1, false], ["starfish", 2, true]], "goals": 3, "days": 2,
		"last_day": today, "daily": today, "daily_done": today, "baths": 5, "rounds": 11, "ducks": 140, "golden": 2}
