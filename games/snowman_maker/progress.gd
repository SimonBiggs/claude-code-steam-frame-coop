extends RefCounted
## Snowman Maker in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "snowman_maker"  # the game's core/save.gd game_id
const WHO := "penguin"  # the story friend (a story picture)
const GROWS := "snowman"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(0.557, 0.773, 1.0)  # Tumble's "8ec5ff"


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every snowman the family has made for Tumble's Winter Fair; daily: TODAY'S GARDEN finished today
## (data.daily is {Seeded.daily_key(): best score}, the last two weeks).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var days: Variant = data.get("daily", {})
	return {"grown": int(data.get("made", 0)), "daily": days is Dictionary and (days as Dictionary).has("daily:" + today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 1800, "chapter": 1, "day": 1, "stars": {"0-0": 3, "0-1": 2, "0-2": 3, "1-0": 1}, "misses": 0, "laps": 0,
		"daily": {"daily:" + today: 1500}, "days": 5, "extra_flakes": 2, "made": 11, "wishes": 9}
