extends RefCounted
## Dragon Rider in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const Deep := preload("res://games/dragon_rider/deep.gd")
const SAVE_ID := "dragon_rider"  # the game's core/save.gd game_id
const WHO := "dragon"  # the story friend (a story picture): Sunny the dragon
const GROWS := "babydragon"  # what the family grows (a story picture): charms on the deck rail and baby dragons in Sunny's roost
const COLOR := Color(0.95, 0.45, 0.3)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every charm ever won (total; the rail keeps the newest 22) + every baby dragon hatched (deep.gd babies(total));
## daily: a TODAY'S FLIGHT finished today (daily_done; "daily" only
## says it started, so the next round isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var charms: Variant = data.get("charms", [])
	var tot: Variant = data.get("total", 0)
	var n := maxi(int(tot) if tot is int or tot is float else 0, (charms as Array).size() if charms is Array else 0)
	return {"grown": n + Deep.babies(n),
		"daily": String(data.get("daily_done", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"charms": [["bell", 1, true], ["ribbon", 2, false], ["bunny", 3, true]], "total": 3, "days": 3,
		"last_day": today, "daily": today, "daily_done": today, "flights": 4, "best_stage": 3, "mode": "gentle", "gift": "shield"}
