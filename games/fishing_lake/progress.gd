extends RefCounted
## Fishing Lake in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "fishing_lake"  # the game's core/save.gd game_id
const WHO := "otter"  # the story friend (a story picture): Ollie the otter
const GROWS := "fish"  # what the family grows (a story picture or a UiKit icon): pages in Ollie's fish book
const COLOR := Color(0.62, 0.42, 0.25)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: fish book pages found (book: {fish name: [times caught, best kg]}); daily: TODAY'S LAKE fished to sunset
## today (daily: {date: fish caught}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var book: Variant = data.get("book", {})
	var pages := 0
	if book is Dictionary:
		for k in book:
			var e: Variant = book[k]
			if e is Array and not (e as Array).is_empty() and int(e[0]) > 0:
				pages += 1
	var daily: Variant = data.get("daily", {})
	return {"grown": pages, "daily": daily is Dictionary and (daily as Dictionary).has(today)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 123456, "days": 4, "book": {"Minnow": [6, 0.3], "Stripy Perch": [2, 1.1], "Rainbow Trout": [1, 2.4]},
		"daily": {today: 7}, "wishes": 3, "last_wish": 2, "migrated": true}
