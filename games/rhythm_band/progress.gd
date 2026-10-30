extends RefCounted
## Rhythm Band in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "rhythm_band"  # the game's core/save.gd game_id
const WHO := "frog"  # the story friend (a story picture)
const GROWS := "fanclub"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(1.0, 0.4, 0.6)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every fan the frog's band has won (the fan club keeps the newest ones); daily: TODAY'S SONG finished today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var fans: Variant = data.get("fans", [])
	return {"grown": maxi(int(data.get("fans_total", 0)), (fans as Array).size() if fans is Array else 0),
		"daily": String(data.get("daily", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 4200, "fans": [[0, 1, false], [2, 2, true], [1, 3, true]], "fans_total": 7, "songs": 7, "days": 3,
		"last_day": today, "daily": today, "sessions": 4}
