extends RefCounted
## Kart Race in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "kart_race"  # the game's core/save.gd game_id
const WHO := "robot"  # Bolt, the friendly robot who builds the tracks
const GROWS := "partyhat"  # the hats won on the Grand Tour
const COLOR := Color(0.55, 0.75, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: hats won on the Grand Tour (the drivers wear them for good); daily: TODAY'S TRACK finished today
## (daily = {date, time, ghost, ...}: the date of today's best run).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	return {"grown": int(data.get("hats", 0)),
		"daily": String((daily as Dictionary).get("date", "")) == today if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 4242, "story_i": 7, "hats": 2, "champs": 2, "golds": 3, "races": 9, "tours": 0,
		"daily": {"date": today, "time": 61.5, "ghost": [], "laps": 3, "frac": 1.0}}
