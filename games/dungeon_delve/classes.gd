extends RefCounted
## DUNGEON DELVE heroes for the deep dungeon. In the practice room three hero statues stand by the right
## wall: bonk one (A) to become that hero. Locked ones wear a padlock until Cinder's hoard is big enough.
##  KNIGHT: one more heart, starts with SHIELD BASH, a sword bonk (hits round the front).
##  ARCHER: A shoots an arrow (far, one monster), starts with DASH, runs a little faster.
##  WIZARD: A throws a magic spark that pops on everything near where it lands and goes through shields,
##          one heart less, starts with 3 bombs and a potion.
## The VR player is always the big knight (his real sword); classes are for TV / Deck heroes.

const ORDER: Array[String] = ["knight", "archer", "wizard"]
const INFO := {
	"knight": {"name": "KNIGHT", "icon": "shield", "color": Color(0.75, 0.82, 1.0), "hoard": 0, "hearts": 1, "abil": "bash",
		"bombs": 0, "pots": 0, "speed": 1.0, "shot": "", "look": {"weapon": "sword", "offhand": "round_shield"}},
	"archer": {"name": "ARCHER", "icon": "arrow_right", "color": Color(0.5, 0.95, 0.5), "hoard": 60, "hearts": 0, "abil": "dash",
		"bombs": 0, "pots": 0, "speed": 1.1, "shot": "arrow", "look": {"weapon": "none", "offhand": "bow"}},
	"wizard": {"name": "WIZARD", "icon": "bolt", "color": Color(0.8, 0.6, 1.0), "hoard": 200, "hearts": -1, "abil": "",
		"bombs": 3, "pots": 1, "speed": 1.0, "shot": "bolt", "look": {"weapon": "staff", "offhand": "none"}},
}
const SHOT_SPEED := {"arrow": 13.0, "bolt": 8.5}
const SHOT_CD := {"": 0.4, "arrow": 0.42, "bolt": 0.6}  ## seconds between A presses


static func info(id: String) -> Dictionary:
	return INFO.get(id, INFO["knight"])


static func unlocked(hoard: int) -> Array:
	var out: Array = []
	for id in ORDER:
		if hoard >= int(INFO[id]["hoard"]):
			out.append(id)
	return out


static func valid(id: String) -> bool:
	return INFO.has(id)
