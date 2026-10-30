extends RefCounted
## Mech Titans in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "mech_titans"  # the game's core/save.gd game_id
const WHO := "kaiju"  # the kaiju the Titans help home (they become friends)
const GROWS := "heart"  # the kaiju friends on the hills
const COLOR := Color(1.0, 0.42, 0.25)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every round a kaiju went home as a friend (the hills keep the newest 60 friends);
## daily: TODAY'S KAIJU went home today (main.gd _make_friends saves the date).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var friends: Variant = data.get("friends", [])
	return {"grown": maxi(int(data.get("rounds", 0)), (friends as Array).size() if friends is Array else 0),
		"daily": String(data.get("daily", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"parts": 120, "cleared": [], "stars": [], "owned": [], "paint": "classic", "paints": ["classic"], "turn": "smooth",
		"friends": [["lizard", "", ""], ["lizard", "ffd24a", "ffb020"], ["slimelet", "", ""]], "best_round": 3, "rounds": 3,
		"daily": today}
