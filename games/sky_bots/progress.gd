extends RefCounted
## Sky Bots in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and reads
## the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "sky_bots"  # the game's core/save.gd game_id
const WHO := "gizmo"  # Granny Gizmo (a story picture)
const GROWS := "house"  # Gizmo Town grows
const COLOR := Color(0.55, 0.85, 1.0)


## data: the raw save (no defaults filled in). today: Seeded.today().
## grown: every spark brought home and every gold gear found (each builds something in Gizmo Town: story.gd power);
## daily: TODAY'S ISLAND finished today (the game stamps "daily_done" at its spark, "daily" when it starts).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	return {"grown": int(data.get("sparks", 0)) + int(data.get("gears", 0)), "daily": String(data.get("daily_done", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 4242, "cleared": 3, "visits": [2, 3, 2, 0], "sparks": 5, "gears": 2, "gear_isles": 3, "bolts": 140,
		"best_bolts": 33, "crabs": 0, "daily": today, "daily_done": today, "mode": "gentle", "intro": true, "grown": 7}
