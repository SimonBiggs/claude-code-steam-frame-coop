extends RefCounted
## Cannon Cove in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const Deep := preload("res://games/cannon_cove/deep.gd")
const SAVE_ID := "cannon_cove"  # the game's core/save.gd game_id
const WHO := "parrot"  # the story friend (a story picture): Polly the parrot
const GROWS := "harbour"  # what the family grows (a story picture): treasures on the stern shelf and Polly's harbour
const COLOR := Color(0.95, 0.2, 0.15)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every treasure ever won (total; the shelf keeps the newest 13) + every piece of Polly's harbour (deep.gd
## harbour(total)); daily: a TODAY'S VOYAGE finished today (daily_done; "daily" only says it started, so the next round
## isn't the daily).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var treasures: Variant = data.get("treasures", [])
	var tot: Variant = data.get("total", 0)
	var n := maxi(int(tot) if tot is int or tot is float else 0, (treasures as Array).size() if treasures is Array else 0)
	return {"grown": n + Deep.harbour(n),
		"daily": String(data.get("daily_done", "")) == today, "played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"treasures": [["doubloon", 1, true], ["pearl", 2, false], ["anchor", 3, true]], "total": 3, "days": 3,
		"last_day": today, "daily": today, "daily_done": today, "voyages": 5, "best_wave": 4, "kraken_wins": 0,
		"mode": "gentle", "gift": "net"}
