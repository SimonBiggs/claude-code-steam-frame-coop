extends RefCounted
## Crystal Saga in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "crystal_saga"  # the game's core/save.gd game_id (Saga.GAME_ID)
const WHO := "lumi"  # the story friend (a story picture): Lumi the crystal fairy
const GROWS := "shard"  # what the family grows (a story picture or a UiKit icon): crystal shards (they rebuild Willowbrook)
const COLOR := Color(0.55, 0.85, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every crystal shard ever found (every 3 bring back a place of Willowbrook); daily: TODAY'S QUEST's light
## restored today (daily: {date: true}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	return {"grown": maxi(0, int(data.get("shards", 0))), "daily": daily is Dictionary and (daily as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"restored": 3, "world": 123456, "daily": {today: true}, "skills": {"splash": 2, "spin": 1}, "shards": 10,
		"seen_places": 3, "journeys": 4}
