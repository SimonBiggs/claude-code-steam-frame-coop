extends RefCounted
## Kart Race in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "kart_race"  # the game's core/save.gd game_id
const WHO := "boltbot"  # Bolt, the friendly robot who builds the tracks (story_pictures.gd)
const GROWS := "shelf"  # Bolt's trophy shelf (cups won), the hats won on the Grand Tour and Bolt's race town
const Deep := preload("res://games/kart_race/deep.gd")
const Cups := preload("res://games/kart_race/cups.gd")
const COLOR := Color(0.55, 0.75, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: hats won on the Grand Tour + cups on BOLT'S TROPHY SHELF (any medal, cups.gd shelf) + buildings in BOLT'S RACE
## TOWN (deep.gd town_size of the races finished); "medals" / "gold_cups" / "parts" / "town" say the same in detail. daily: TODAY'S TRACK finished today (daily = {date, time, ghost, ...}: the date of
## today's best run, stamped when the race is finished).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	var shelf: Variant = data.get("shelf", {})
	var medals := Cups.medals(shelf)
	var town := Deep.town_size(maxi(0, int(data.get("races", 0)))).x
	return {"grown": maxi(0, int(data.get("hats", 0))) + medals + town, "town": town,
		"daily": String((daily as Dictionary).get("date", "")) == today if daily is Dictionary else false,
		"medals": medals, "gold_cups": Cups.golds(shelf), "parts": Cups.parts_unlocked(shelf).size()}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 4242, "story_i": 7, "hats": 2, "champs": 2, "golds": 3, "races": 9, "tours": 0,
		"daily": {"date": today, "time": 61.5, "ghost": [], "laps": 3, "frac": 1.0},
		"shelf": {"candy:gentle": 3, "ice:gentle": 1}, "garage": {"1": {"cls": "light", "part": "spoiler"}}, "laps": {}, "mode": "gentle", "cups": 2}
