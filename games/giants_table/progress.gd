extends RefCounted
## Giant's Table in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "giants_table"  # the game's core/save.gd game_id
const WHO := "sparky"  # Sparky, the little fire friend
const GROWS := "cake"  # the villagers' thank-you gifts
const COLOR := Color(1.0, 0.6, 0.2)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every night the village was saved (one gift each; the rim keeps the newest 12); daily: TODAY'S RAID ran today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var gifts: Variant = data.get("gifts", [])
	return {"grown": maxi(int(data.get("nights", 0)), (gifts as Array).size() if gifts is Array else 0),
		"daily": String(data.get("daily", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"days": 3, "last_day": today, "daily": today, "games": 5, "nights": 4, "best_wave": 6, "goblins": 40,
		"gifts": [["pie", 1, true], ["cake", 1, false], ["teddy", 2, true], ["scarf", 3, true]]}
