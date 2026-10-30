extends RefCounted
## Marble Maze in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "marble_maze"  # the game's core/save.gd game_id
const WHO := "kaiju"  # Bobo, the friendly little monster
const GROWS := "gem"  # the shiny marbles in Bobo's jar
const COLOR := Color(0.72, 0.5, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every shiny marble ever found (shinies = {name: count}; the jar keeps the newest 200);
## daily: TODAY'S MAZE cleared today (daily = {date: true}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var shinies: Variant = data.get("shinies", {})
	var jar: Variant = data.get("jar", [])
	var n := 0
	if shinies is Dictionary:
		for k in shinies:
			n += int(shinies[k])
	var daily: Variant = data.get("daily", {})
	return {"grown": maxi(n, (jar as Array).size() if jar is Array else 0),
		"daily": (daily as Dictionary).has(today) if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"lessons_done": true, "story_i": 5, "world": 777, "shinies": {"SUNNY": 1, "OCEAN": 1, "GOLDEN": 1}, "places": 1,
		"daily": {today: true}, "mazes": 14, "falls": 6, "jar": [0, 1, -1]}
