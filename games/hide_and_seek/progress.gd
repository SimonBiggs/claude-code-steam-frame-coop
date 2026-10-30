extends RefCounted
## Hide and Seek in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "hide_and_seek"  # the game's core/save.gd game_id
const WHO := "puppy"  # Pip the puppy
const GROWS := "beachball"  # Pip's toys piled up by his kennel
const COLOR := Color(0.95, 0.72, 0.42)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every toy Pip has brought home (they stay by his kennel); daily: TODAY'S HOUSE played today (daily = {date: finds}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	return {"grown": int(data.get("toys", 0)),
		"daily": (daily as Dictionary).has(today) if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 98765, "houses": 6, "toys": 9, "pips": 9, "daily": {today: 4}, "best_finds": 4}
