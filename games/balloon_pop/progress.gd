extends RefCounted
## Balloon Pop in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "balloon_pop"  # the game's core/save.gd game_id
const WHO := "seller"  # the story friend (a story picture): Poppy the balloon seller
const GROWS := "carousel"  # what the family grows (a story picture or a UiKit icon): Poppy's fair rides
const COLOR := Color(1.0, 0.45, 0.7)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every ride built at Poppy's fair (rides: {ride id: times built}); daily: TODAY'S SKY popped today.
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var rides: Variant = data.get("rides", {})
	var built := 0
	if rides is Dictionary:
		for k in rides:
			built += maxi(0, int(rides[k]))
	var daily: Variant = data.get("daily", {})
	return {"grown": built, "daily": daily is Dictionary and (daily as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 41, "world": 123456, "rides": {"BUNTING": 1, "ICECREAM": 1, "CAROUSEL": 1}, "cur": "CASTLE", "fill": 12,
		"rounds": 9, "stars": {"BUNTING": 3, "ICECREAM": 2}, "daily": {today: 38}, "met": {"0": true}, "sets": 2, "giants": 0, "carry": 0}
