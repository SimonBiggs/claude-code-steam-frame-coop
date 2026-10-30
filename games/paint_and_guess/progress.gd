extends RefCounted
## Paint and Guess in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "paint_and_guess"  # the game's core/save.gd game_id
const WHO := "smudge"  # Smudge, who keeps the gallery
const GROWS := "goldframe"  # the paintings in Smudge's gallery
const COLOR := Color(1.0, 0.7, 0.4)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every painting ever kept (the gallery wall keeps the newest ones); daily: TODAY'S GALLERY finished today (daily_done; "daily" only
## says it started, so the next round isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var gallery: Variant = data.get("gallery", [])
	return {"grown": maxi(int(data.get("paintings", 0)), (gallery as Array).size() if gallery is Array else 0),
		"daily": String(data.get("daily_done", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"gallery": [["CAT", 1, true, []], ["SUN", 2, false, []]], "paintings": 6, "games": 4, "days": 2,
		"last_day": today, "daily": today, "daily_done": today, "masterpieces": 1}
