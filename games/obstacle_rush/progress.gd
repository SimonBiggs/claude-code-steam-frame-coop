extends RefCounted
## Obstacle Rush in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "obstacle_rush"  # the game's core/save.gd game_id
const WHO := "coach"  # Coach Jelly
const GROWS := "person"  # the fans in the stands (a UiKit icon)
const COLOR := Color(1.0, 0.55, 0.25)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every fan the family has won (they stay in the stands); daily: TODAY'S COURSE cleared today (daily = {date: true}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	return {"grown": int(data.get("fans", 0)),
		"daily": (daily as Dictionary).has(today) if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"crowns": 3, "shows": 3, "fans": 22, "stars": 15, "courses": 7, "world": 31337, "daily": {today: true}}
