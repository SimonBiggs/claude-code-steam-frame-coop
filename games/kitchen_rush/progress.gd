extends RefCounted
## Kitchen Rush in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "kitchen_rush"  # the game's core/save.gd game_id
const WHO := "granny"  # Gran, whose café it is
const GROWS := "gift"  # the thank-you gifts on Gran's shelf
const COLOR := Color(0.94, 0.72, 0.9)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every party served (one gift each; the shelf keeps the newest 500); daily: TODAY'S PARTY done today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var gifts: Variant = data.get("gifts", [])
	return {"grown": maxi(int(data.get("rounds", 0)), (gifts as Array).size() if gifts is Array else 0),
		"daily": String(data.get("daily", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"gifts": [["teapot", false, "granny"], ["balloon", true, "kid"], ["teapot", true, "granny"]],
		"visits": {"granny": 2, "kid": 1}, "rounds": 3, "best_round": 3, "served": 24, "daily": today}
