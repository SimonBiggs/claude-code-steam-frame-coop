extends RefCounted
## Roller Coaster in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "roller_coaster"  # the game's core/save.gd game_id
const WHO := "bear"  # the story friend (a story picture)
const GROWS := "ticket"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.25, 0.5, 0.95)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: golden tickets on Buttons' park board (one per finished plan); daily: a TODAY'S COASTER plan finished today (daily_done; "daily" only
## says it started, so the next round isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	return {"grown": int(data.get("tickets", 0)), "daily": String(data.get("daily_done", "")) == today,
		"played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"decor": 3, "tickets": 5, "days": 3, "last_day": today, "daily": today, "daily_done": today, "rides": 8, "plans": 5, "coasters": 2}
