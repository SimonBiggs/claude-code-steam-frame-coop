extends RefCounted
## Starship Crew in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "starship_crew"  # the game's core/save.gd game_id
const WHO := "captain"  # the story friend (a story picture)
const GROWS := "station"  # what the family grows (a story picture or a UiKit icon)
const COLOR := Color(1.0, 0.62, 0.25)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every trip home to Captain Whiskers' space station (each one adds a part); daily: TODAY'S MISSION done today
## (data.daily is {date: true}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var days: Variant = data.get("daily", {})
	return {"grown": int(data.get("trips", 0)), "daily": days is Dictionary and bool((days as Dictionary).get(today, false))}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"trips": 4, "world": 123456, "daily": {today: true}, "planets": ["ZOOBLE", "WIBBLON", "SNORP"], "stars": 40,
		"missions": 16}
