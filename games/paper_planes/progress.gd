extends RefCounted
## Paper Planes in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "paper_planes"  # the game's core/save.gd game_id
const WHO := "bird"  # Pip the post bird
const GROWS := "envelope"  # the letters delivered (stamps)
const COLOR := Color(1.0, 0.7, 0.28)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every stamp won (stars = {"chapter-flight": best stars} plus extra_stamps from bonus skies);
## daily: TODAY'S SKY flown today (daily = {Seeded.daily_key(): best score}, "daily:" + date).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var stars: Variant = data.get("stars", {})
	var n := int(data.get("extra_stamps", 0))
	if stars is Dictionary:
		for k in stars:
			n += int(stars[k])
	var daily: Variant = data.get("daily", {})
	return {"grown": n, "daily": (daily as Dictionary).has("daily:" + today) if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 14, "chapter": 1, "flight": 1, "stars": {"0-0": 3, "0-1": 2, "0-2": 3, "1-0": 1}, "misses": 0, "laps": 0,
		"daily": {"daily:" + today: 9}, "flights": 7, "extra_stamps": 0}
