extends RefCounted
## Whack-a-Mole in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const Deep := preload("res://games/whack_a_mole/deep.gd")
const SAVE_ID := "whack_a_mole"  # the game's core/save.gd game_id
const WHO := "farmer"  # the story friend (a story picture)
const GROWS := "moleden"  # what the family grows (a story picture): veg beds and Fig's holiday garden of moles
const COLOR := Color(0.55, 0.85, 0.35)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every full veg bed in Farmer Fig's garden (beds is {crop id: times grown}, like Story.beds_grown) + every mole
## on holiday in the deckchairs round it (deep.gd holiday(moles_total)); daily: TODAY'S PATCH finished today
## (data.daily is {date: best score}, the newest 30 days, stamped when the daily round ENDS).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var beds: Variant = data.get("beds", {})
	var n := 0
	if beds is Dictionary:
		for v in (beds as Dictionary).values():
			n += int(v) if v is int or v is float else 0
	var days: Variant = data.get("daily", {})
	var mt: Variant = data.get("moles_total", 0)
	n += Deep.holiday(int(mt) if mt is int or mt is float else 0)
	return {"grown": n, "daily": days is Dictionary and (days as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best": 31, "world": 123456, "beds": {"LETTUCE": 2, "CARROTS": 1}, "cur": "PUMPKINS", "fill": 10, "rounds": 8,
		"stars": {"LETTUCE": 3, "CARROTS": 2}, "daily": {today: 27}, "met": {}, "bunnies": 1, "kings": 0,
		"mode": "gentle", "gift": "sleepy", "moles_total": 140}
