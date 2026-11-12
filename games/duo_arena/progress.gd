extends RefCounted
## Duo Arena in the arcade's Family Trophy Hall (arcade/hall.gd). core/progress.gd finds this file by itself and
## reads the game's save through core/save.gd (the game's scene is never loaded). See core/progress.gd.

const SAVE_ID := "duo_arena"  # the game's core/save.gd game_id
const WHO := "nova"  # the story friend (a story picture): Nova the arena's little light-bot
const GROWS := "neoncity"  # what the family grows: Neon City's lights (one per wave cleared, zone.gd pylons)
const COLOR := Color(0.35, 0.85, 1.0)


## data: the raw save (no defaults filled in: always .get with a default). today: Seeded.today().
## grown: waves cleared over all days (city lights, new towers) + bosses beaten + Nova's friends saved (deep.gd);
## zones: arenas unlocked by those waves;
## daily: TODAY'S ARENA played to its end today (daily_done; "daily" only says it started).
static func progress_summary(data: Dictionary, today: String) -> Dictionary:
	var bosses: Variant = data.get("bosses", {})
	var beaten := 0
	if bosses is Dictionary:
		for k in bosses:
			beaten += maxi(0, int(bosses[k]))
	var waves := maxi(0, int(data.get("waves", 0)))
	var zones := 0
	for need in [0, 3, 8, 15, 25]:  # arenagen.gd ZONES unlocks
		if waves >= need:
			zones += 1
	var fr: Variant = data.get("friends", {})
	var friends: int = (fr as Dictionary).size() if fr is Dictionary else 0
	return {"grown": waves + beaten + friends, "zones": zones, "friends": friends, "daily": String(data.get("daily_done", "")) == today,
		"played": String(data.get("last_day", "")) == today}


## A save as the game writes it after a few days (tests/progress_test.gd: it must read as grown > 0, daily done).
static func sample(today: String) -> Dictionary:
	return {"best_wave": 9, "best_score": 12000, "days": 3, "last_day": today, "daily": today, "daily_done": today,
		"games": 6, "waves": 17, "bosses": {"boss": 2, "rex": 1}, "mode": "gentle", "hero": "sprayer", "friends": {"sprout": 1},
		"best_today": [today, 6]}
