extends RefCounted
## Party Board in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "party_board"  # the game's core/save.gd game_id
const WHO := "toucan"  # Mango the toucan, the party host
const GROWS := "bunting"  # the pieces of Mango's festival
const COLOR := Color(1.0, 0.6, 0.15)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: festival pieces Mango has built on Party Island (they stay; eight make it complete) + the cups on Mango's
## TROPHY WALL (boards.gd TROPHIES: a cup for winning on each board, five stars, three daily parties...);
## daily: TODAY'S PARTY finished today (daily = {date: winner's name}).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var fest: Variant = data.get("festival", [])
	var daily: Variant = data.get("daily", {})
	var cups: Variant = data.get("trophies", {})
	return {"grown": ((fest as Array).size() if fest is Array else 0) + ((cups as Dictionary).size() if cups is Dictionary else 0),
		"daily": (daily as Dictionary).has(today) if daily is Dictionary else false}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"parties": 4, "giant_wins": 1, "best_stars": 3, "most_coins": 25, "wins": {"P1": 2, "P2": 2}, "mg_played": {},
		"world": 5150, "festival": ["bunting", "arch", "stage"], "flags": ["ff5a5a", "5ab4ff"], "daily": {today: "P1"},
		"boards_played": {"island": 2, "sweet": 1, "pirate": 1}, "boards_seen": ["haunted"], "last_board": "pirate",
		"trophies": {"win_island": today, "win_sweet": today}, "items_used": ["double", "warp"], "mg_won": ["coin_catch", "mole_bop"]}
