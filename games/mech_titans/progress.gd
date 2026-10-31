extends RefCounted
## Mech Titans in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "mech_titans"  # the game's core/save.gd game_id
const WHO := "momo"  # Momo, the Titans' first kaiju friend: every kaiju they help home joins her (story_pictures.gd)
const GROWS := "sanctuary"  # the Kaiju Sanctuary on the hills (story_pictures.gd sanctuary)
const COLOR := Color(1.0, 0.42, 0.25)
const Sanctuary := preload("res://games/mech_titans/sanctuary.gd")
## Save layout (core/save.gd use_layout). v2 (2026-10-31, titans-deep): the KAIJU SANCTUARY. data["sanct"] =
## {"hearts": int, "bosses": {boss id: n}}; old saves get one heart for every round a kaiju went home before
## (data["rounds"], or the friends list if that's longer), so a family that played keeps its unlocks.
const SAVE_VERSION := 2


static func migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		var friends: Variant = data.get("friends", [])
		var n := maxi(int(data.get("rounds", 0)), (friends as Array).size() if friends is Array else 0)
		var s: Variant = data.get("sanct")
		if not (s is Dictionary):
			s = {"hearts": 0, "bosses": {}}
		(s as Dictionary)["hearts"] = maxi(int((s as Dictionary).get("hearts", 0)), n)
		data["sanct"] = s
	return data


## Old saves and what they must read as after migrating (core/progress.gd layout_problems).
static func migration_samples() -> Array:
	return [
		[1, {"rounds": 7, "friends": [["lizard", "", ""], ["jelly", "", ""]], "best_round": 7, "daily": "2026-10-30"},
			{"sanct/hearts": 7, "rounds": 7, "best_round": 7, "daily": "2026-10-30"}],
		[1, {"rounds": 1, "friends": [["lizard", "", ""], ["eel", "", ""], ["moth", "", ""]]}, {"sanct/hearts": 3}],
		[1, {"parts": 5}, {"sanct/hearts": 0, "parts": 5}],
	]


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: the Kaiju Sanctuary's hearts (every lost kaiju sent home; a boss counts 3) + everything it has
## unlocked (frames, upgrades, BRAVE, homes on the hills); daily: TODAY'S KAIJU went home today (main.gd
## _make_friends saves the date when the golden kaiju goes home: the daily is finished, not started).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var friends: Variant = data.get("friends", [])
	var h := Sanctuary.hearts(data)
	var old := maxi(int(data.get("rounds", 0)), (friends as Array).size() if friends is Array else 0)
	h = maxi(h, old)
	return {"grown": h + Sanctuary.unlock_count(h), "daily": String(data.get("daily", "")) == today,
		"hearts": h, "unlocks": Sanctuary.unlock_count(h)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"parts": 120, "cleared": [], "stars": [], "owned": [], "paint": "classic", "paints": ["classic"], "turn": "smooth",
		"friends": [["lizard", "", ""], ["lizard", "ffd24a", "ffb020"], ["slimelet", "", ""]], "best_round": 3, "rounds": 3,
		"daily": today, "sanct": {"hearts": 9, "bosses": {"king_sizzle": 1}}, "frame": "sprinter", "mode": "gentle", "mega_ok": false}
