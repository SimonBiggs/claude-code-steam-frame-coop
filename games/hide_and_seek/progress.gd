extends RefCounted
## Hide and Seek in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "hide_and_seek"  # the game's core/save.gd game_id
const WHO := "puppy"  # Pip the puppy
const GROWS := "gardenparty"  # Pip's garden party: neighbour friends from PIP'S STREET (+ his toys by the kennel)
const COLOR := Color(0.95, 0.72, 0.42)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: every toy Pip has brought home (they stay by his kennel) + every friend at his garden party (street.gd);
## friends: friends at the party; daily: TODAY'S STREET finished today (daily_done; older saves: the daily = {date: finds}
## map, also stamped when the daily round finished).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var daily: Variant = data.get("daily", {})
	var party: Variant = data.get("party", [])
	var friends := (party as Array).size() if party is Array else 0
	return {"grown": maxi(0, int(data.get("toys", 0))) + friends, "friends": friends,
		"daily": String(data.get("daily_done", "")) == today or ((daily as Dictionary).has(today) if daily is Dictionary else false)}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"world": 98765, "houses": 6, "toys": 9, "pips": 9, "daily": {today: 4}, "best_finds": 4, "party": [0, 3, 5], "friends_found": 4,
		"streets": 1, "daily_done": today}
