extends RefCounted
## Crystal Saga in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "crystal_saga"  # the game's core/save.gd game_id (Saga.GAME_ID)
const WHO := "lumi"  # the story friend (a story picture): Lumi the crystal fairy
const GROWS := "shard"  # what the family grows (a story picture or a UiKit icon): crystal shards (they rebuild Willowbrook)
const COLOR := Color(0.55, 0.85, 1.0)
const Realm := preload("res://games/crystal_saga/realm.gd")
## Save layout (core/save.gd use_layout). v2 (2026-10-31, saga-deep): the REALM. data["cleared"] = realm slots whose
## crystal guardian was beaten, "classes" = {seat: hero}, "hard" = BRAVE mode, "seen_unlocks" = Willowbrook unlocks
## announced. Old saves: every journey finished before (data["restored"]) beat one region, in the order the
## realm opens them (at most 3: the rest of the map is new adventure), so a family that played keeps going.
const SAVE_VERSION := 2


static func migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		var cleared: Variant = data.get("cleared")
		if not (cleared is Array):
			cleared = []
		var done := mini(int(data.get("restored", 0)), 3)
		if int(data.get("world", -1)) >= 0 and done > 0 and (cleared as Array).is_empty():
			cleared = Realm.clear_order(Realm.generate(int(data.world)), done)
		data["cleared"] = cleared
		if not (data.get("classes") is Dictionary):
			data["classes"] = {}
		data["hard"] = bool(data.get("hard", false))
		data["seen_unlocks"] = int(data.get("seen_unlocks", 0))
	return data


## Old saves and what they must read as after migrating (core/progress.gd layout_problems).
static func migration_samples() -> Array:
	var r := Realm.generate(123456)
	var two: Array = Realm.clear_order(r, 2)
	return [
		[1, {"restored": 2, "world": 123456, "daily": {"2026-10-30": true}, "skills": {"splash": 1}, "shards": 7, "journeys": 3},
			{"cleared": two, "restored": 2, "shards": 7, "hard": false}],
		[1, {"restored": 9, "world": 99, "shards": 30}, {"cleared": Realm.clear_order(Realm.generate(99), 3), "shards": 30}],
		[1, {"restored": 0, "world": -1}, {"hard": false, "seen_unlocks": 0}],
	]


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every crystal shard ever found (every 3 bring back a place of Willowbrook) + a big 3 for every region's
## crystal brought home; daily: TODAY'S QUEST's light restored today (daily: {date: true}, stamped when it's DONE).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	var cleared: Variant = data.get("cleared", [])
	var regions := (cleared as Array).size() if cleared is Array else 0
	return {"grown": maxi(0, int(data.get("shards", 0))) + 3 * regions, "daily": daily is Dictionary and (daily as Dictionary).has(today),
		"regions": regions}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"restored": 3, "world": 123456, "daily": {today: true}, "skills": {"splash": 2, "spin": 1}, "shards": 10,
		"seen_places": 3, "journeys": 4, "cleared": [0, 1, 3], "classes": {"1": "healer"}, "hard": false, "seen_unlocks": 2}
