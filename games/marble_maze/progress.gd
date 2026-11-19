extends RefCounted
## Marble Maze in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "marble_maze"  # the game's core/save.gd game_id
const WHO := "kaiju"  # Bobo, the friendly little monster
const GROWS := "gem"  # the shiny marbles in Bobo's jar
const COLOR := Color(0.72, 0.5, 1.0)
const Story := preload("res://games/marble_maze/story.gd")
## Save layout (core/save.gd use_layout). v2 (2026-11-19, deep3-marble): twelve places instead of seven, so story_i
## moves onto the new list (Story.migrate_story_i: the same place and maze; "places" lit counts the new list), plus
## TODAY'S RACE: race = {date: [[secs, marbles], ...] best first}, race_best = [secs, date, marbles], cups =
## [[date, medal], ...] (Bobo's trophy shelf), ghost = {d, legs} (the best run of today, raced again), races.
const SAVE_VERSION := 2


static func migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		var old := maxi(0, int(data.get("story_i", 0)))
		var i := Story.migrate_story_i(old)
		data["story_i"] = i
		if int(data.get("places", 0)) > 0:
			data["places"] = Story.places_lit(i)
		for k in ["race", "ghost"]:
			if not (data.get(k) is Dictionary):
				data[k] = {}
		for k in ["race_best", "cups"]:
			if not (data.get(k) is Array):
				data[k] = []
		data["races"] = int(data.get("races", 0))
	return data


## Old saves and what they must read as after migrating (core/progress.gd layout_problems).
static func migration_samples() -> Array:
	return [
		[1, {"story_i": 1, "places": 0, "world": 5}, {"story_i": 1, "places": 0, "race": {}, "cups": []}],
		[1, {"story_i": 13, "places": 4, "world": 5}, {"story_i": 22, "places": 7}],  # CASTLE 2 -> CASTLE 2
		[1, {"story_i": 22, "places": 7, "world": 5}, {"story_i": 37, "places": 12}],  # lap 2 FLOWER PARK 2
	]


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every shiny marble ever found (shinies = {name: count}; the jar keeps the newest 200) plus the gift marbles on
## Bobo's marble run (rack: one per maze cleared with a gift marble, second pass);
## daily: TODAY'S MAZE cleared today (daily = {date: true}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var shinies: Variant = data.get("shinies", {})
	var jar: Variant = data.get("jar", [])
	var n := 0
	if shinies is Dictionary:
		for k in shinies:
			n += int(shinies[k])
	var daily: Variant = data.get("daily", {})
	var rack: Variant = data.get("rack", [])
	var cups: Variant = data.get("cups", [])
	return {"grown": maxi(n, (jar as Array).size() if jar is Array else 0) + ((rack as Array).size() if rack is Array else 0)
		+ ((cups as Array).size() if cups is Array else 0),
		"daily": (daily as Dictionary).has(today) if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"lessons_done": true, "story_i": 5, "world": 777, "shinies": {"SUNNY": 1, "OCEAN": 1, "GOLDEN": 1}, "places": 1,
		"daily": {today: true}, "mazes": 14, "falls": 6, "jar": [0, 1, -1],
		"mode": "brave", "gift": "magnet", "rack": [0, 2, 2, 1], "gifts": {"magnet": 2, "heavy": 1}, "events": 9,
		"race": {today: [[64.2, 2]]}, "race_best": [64.2, today, 2], "cups": [[today, "silver"]], "ghost": {}, "races": 1}
