extends RefCounted
## Block Builders in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "block_builders"  # the game's core/save.gd game_id
const WHO := "cloud"  # the story friend (a story picture): Puff the little cloud
const GROWS := "cloud"  # what the family grows (a story picture or a UiKit icon): Puff's rescued cloud friends
const COLOR := Color(0.75, 0.88, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: cloud friends brought home (friends: [friend index, ...]); daily: TODAY'S SKY cleared today (daily: {date: true}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var friends: Variant = data.get("friends", [])
	var daily: Variant = data.get("daily", {})
	return {"grown": (friends as Array).size() if friends is Array else 0,
		"daily": daily is Dictionary and (daily as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"lessons_done": true, "adventure": 5, "world": 123456, "friends": [0, 1, 2, 3], "daily": {today: true},
		"courses": 15, "best_level": 12}
