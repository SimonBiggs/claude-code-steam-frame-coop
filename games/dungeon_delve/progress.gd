extends RefCounted
## Dungeon Delve in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "dungeon_delve"  # the game's core/save.gd game_id
const WHO := "cinder"  # the story friend: Cinder, the baby dragon who shares the dungeon's treasure (story_pictures.gd)
const GROWS := "trophy"  # what the family grows (a story picture or a UiKit icon): treasures found
const COLOR := Color(0.95, 0.8, 0.65)
const Relics := preload("res://games/dungeon_delve/relics.gd")
const Classes := preload("res://games/dungeon_delve/classes.gd")


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: big treasure chests opened (the gentle run) + deep dungeon victories (deep.wins) + everything Cinder's
## hoard has unlocked (heroes past the knight, relics past the starting ones) + one per 100 gold in her hoard
## (deep.hoard); "hoard" / "unlocks" say the same for anyone who wants the detail. daily: TODAY'S DUNGEON played
## today (daily, deep.gd finish) or a depth record for today (deep.best["daily:" + today]).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var deep: Variant = data.get("deep", {})
	var wins := 0
	var hoard := 0
	var today_best := false
	var runs := 0
	if deep is Dictionary:
		var w: Variant = (deep as Dictionary).get("wins", {})
		if w is Dictionary:
			for k in w:
				wins += maxi(0, int(w[k]))
		var b: Variant = (deep as Dictionary).get("best", {})
		today_best = b is Dictionary and (b as Dictionary).has("daily:" + today)
		hoard = maxi(0, int((deep as Dictionary).get("hoard", 0)))
		runs = maxi(0, int((deep as Dictionary).get("runs", 0)))
	var unlocks := Classes.unlocked(hoard).size() - Classes.unlocked(0).size() + Relics.unlocked(hoard).size() - Relics.unlocked(0).size()
	return {"grown": maxi(0, int(data.get("treasures", 0))) + wins + unlocks + hoard / 100,
		"daily": String(data.get("daily", "")) == today or today_best, "hoard": hoard, "unlocks": unlocks, "runs": runs}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"treasures": 4, "daily": today, "deep": {"best": {"brave": 5, "heroic": 0, "daily:" + today: 3},
		"bosses": {"brave": 1, "heroic": 0}, "wins": {"brave": 0, "heroic": 0}, "hat": {"0": "party"}, "runs": 3, "hoard": 320, "cls": {"1": "archer"}}}
