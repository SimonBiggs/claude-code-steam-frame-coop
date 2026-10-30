extends RefCounted
## Mini Golf Party in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "mini_golf_party"  # the game's core/save.gd game_id
const WHO := "gopher"  # Gus the gopher
const GROWS := "sunflower"  # the gold-star flowers in Gus's garden
const COLOR := Color(0.25, 0.7, 0.4)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every gold star the family has won (a flower each in Gus's garden); daily: TODAY'S COURSE finished today (daily_done; "daily" only
## says it started, so the next round isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	return {"grown": int(data.get("stars_total", 0)), "daily": String(data.get("daily_done", "")) == today,
		"played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best_stars": 7, "days": 3, "last_day": today, "daily": today, "daily_done": today, "courses": 4, "stars_total": 18,
		"holes_in_one": 2, "level": 2}
