extends RefCounted
## DUO ARENA picture-first PICKS: glowing orbs that float in a row in front of the start (zone.gd builds them,
## main.gd decides). Shoot an orb (or walk into it) to take it. Little coloured dots circle an orb for every player
## who took it. Nobody chooses? When the time runs out, the middle orb (it glows brightest) is taken for whoever
## hasn't, so little ones are never stuck.
##   MODE   (team, the first game of a visit): GENTLE (a heart: for little ones), BRAVE (a star), HARD (a flame).
##          Everyone votes (team_picks.gd on core/pick_flow.gd's vote mode: the most votes, a tie stays gentler);
##          the family's last choice is the middle orb next time.
##   HERO   (each player, before wave 1): a loadout for the whole run (BLASTER, SPRAYER, BOOMER, TANK, ZOOMER).
##   PERK   (each player, after every wave): three of the unlocked perks, seeded per run and wave; they stack.
##   GIFT   (team, after every boss instead of a perk): NOVA'S GIFTS (deep.gd), everyone votes (team_picks.gd).
## Unlocks for good as the family clears waves (saved "waves"): unlocked().
## Effects are [stat, "mul"|"add", amount] on the player's personal stats (player.gd add_personal, synced).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/duo_arena/deep.gd")

const OFFER := 3
## core/ui_kit.gd icon kinds the orbs use as pictures (StoryCard draws any of them; the gen test checks they exist).
const UI_ICONS: Array[String] = ["heart", "star", "bolt", "play", "shield", "clock", "gem"]  # ("fireball" is Elemental Bender's story picture)
const WAIT := {"mode": 10.0, "hero": 12.0, "perk": 12.0, "gift": 12.0}
## Stages the whole team votes on together (team_picks.gd: everyone votes, core/pick_flow.gd).
const TEAM_STAGES: Array[String] = ["mode", "gift"]
const MAX_NAME := 9
## Caps so stacked perks never break the game.
const CAPS := {"fire_rate": [0.35, 2.0], "damage": [0.5, 4.0], "speed": [0.8, 1.6], "armor": [0.4, 1.0],
	"dash_cd": [0.35, 1.0], "max_hp": [-10.0, 150.0]}

const MODES: Array[Dictionary] = PickOrbs.MODES  # (one place for every game: core/pick_orbs.gd)
const HEROES: Array[Dictionary] = [
	{"id": "blaster", "name": "BLASTER", "pic": "blasterhero", "color": Color(0.35, 0.8, 1.0), "waves": 0, "fx": []},
	{"id": "sprayer", "name": "SPRAYER", "pic": "sprayhero", "color": Color(0.5, 1.0, 0.4), "waves": 0,
		"fx": [["fire_rate", "mul", 0.55], ["damage", "mul", 0.65]]},
	{"id": "boomer", "name": "BOOMER", "pic": "boomhero", "color": Color(1.0, 0.55, 0.2), "waves": 2,
		"fx": [["fire_rate", "mul", 1.7], ["damage", "mul", 2.1]]},
	{"id": "tank", "name": "TANK", "pic": "tankhero", "color": Color(0.75, 0.6, 1.0), "waves": 6,
		"fx": [["max_hp", "add", 40.0], ["armor", "mul", 0.75], ["speed", "mul", 0.9]]},
	{"id": "zoomer", "name": "ZOOMER", "pic": "zoomhero", "color": Color(1.0, 0.85, 0.3), "waves": 12,
		"fx": [["speed", "mul", 1.3], ["dash_cd", "mul", 0.55], ["max_hp", "add", -10.0]]},
]
const PERKS: Array[Dictionary] = [
	{"id": "rapid", "name": "RAPID", "pic": "bolt", "color": Color(1.0, 0.9, 0.3), "waves": 0, "fx": [["fire_rate", "mul", 0.85]]},
	{"id": "heavy", "name": "HEAVY", "pic": "fireball", "color": Color(1.0, 0.45, 0.2), "waves": 0, "fx": [["damage", "mul", 1.3]]},
	{"id": "tough", "name": "TOUGH", "pic": "heart", "color": Color(1.0, 0.4, 0.55), "waves": 0, "fx": [["max_hp", "add", 25.0]]},
	{"id": "swift", "name": "SWIFT", "pic": "play", "color": Color(0.4, 1.0, 0.9), "waves": 0, "fx": [["speed", "mul", 1.1]]},
	{"id": "armor", "name": "ARMOR", "pic": "shield", "color": Color(0.7, 0.75, 0.9), "waves": 4, "fx": [["armor", "mul", 0.8]]},
	{"id": "dash", "name": "DASH", "pic": "clock", "color": Color(0.6, 0.6, 1.0), "waves": 10, "fx": [["dash_cd", "mul", 0.75]]},
	{"id": "mega", "name": "MEGA", "pic": "gem", "color": Color(0.9, 0.5, 1.0), "waves": 20,
		"fx": [["damage", "mul", 1.2], ["fire_rate", "mul", 0.9]]},
]


static func list(stage: String) -> Array[Dictionary]:
	match stage:
		"mode":
			return MODES
		"hero":
			return HEROES
		"gift":
			return Deep.GIFTS
	return PERKS


static func find(stage: String, id: String) -> Dictionary:
	for d in list(stage):
		if String(d.id) == id:
			return d
	return {}


static func unlocked(stage: String, waves_total: int) -> Array[String]:
	var out: Array[String] = []
	for d in list(stage):
		if waves_total >= int(d.waves):
			out.append(String(d.id))
	return out


## The orbs of a stage: mode -> all three (the family's last mode in the middle); hero -> the unlocked heroes
## (up to 5); perk -> OFFER seeded perks for wave n of the run.
static func offer(stage: String, run_seed: int, n: int, open: Array, middle: String = "") -> Array:
	if stage == "perk":
		var pool := Seeded.shuffled(Seeded.rng(Seeded.derive(run_seed, "perks%d" % n), "offer"), open.duplicate())
		return pool.slice(0, mini(OFFER, pool.size()))
	var ids: Array = open.duplicate()
	if middle != "" and ids.has(middle) and ids.size() >= 2:
		ids.erase(middle)
		ids.insert(ids.size() / 2, middle)
	return ids.slice(0, 5)


## The orb taken for whoever didn't choose (the middle one).
static func default_pick(ids: Array) -> String:
	return "" if ids.is_empty() else String(ids[ids.size() / 2])


## Problems with an offer (empty = fair).
static func check_offer(stage: String, ids: Array, open: Array) -> Array[String]:
	var why: Array[String] = []
	var want := mini(OFFER, open.size()) if stage == "perk" else mini(5, open.size())
	if ids.size() != want:
		why.append("%s: %d orbs (want %d)" % [stage, ids.size(), want])
	var seen := {}
	for id in ids:
		if seen.has(id):
			why.append("%s: %s twice" % [stage, id])
		seen[id] = true
		if not open.has(id):
			why.append("%s: %s before it is unlocked" % [stage, id])
		var d := find(stage, String(id))
		if d.is_empty():
			why.append("%s: no pick called %s" % [stage, id])
		elif String(d.name).length() > MAX_NAME:
			why.append("%s: %s's name is too long for an orb" % [stage, id])
	return why


## Apply a pick's effects to a player (host; personal stats travel in snapshots), within CAPS.
static func apply(p, stage: String, id: String) -> void:
	for fx in find(stage, id).get("fx", []):
		p.add_personal(String(fx[0]), String(fx[1]), float(fx[2]))
	clamp_personal(p.personal)


static func clamp_personal(personal: Dictionary) -> void:
	for k in CAPS:
		if personal.has(k):
			personal[k] = clampf(float(personal[k]), float(CAPS[k][0]), float(CAPS[k][1]))


## Problems with the pick lists (empty = fine): names fit, pictures exist (has_pic), every effect's stat is capped,
## a fully stacked player (every perk, 20 waves of picks) stays inside the caps.
static func check_lists(has_pic: Callable) -> Array[String]:
	var why: Array[String] = []
	for stage in ["mode", "hero", "perk", "gift"]:
		var ids := {}
		for d in list(stage):
			if ids.has(d.id):
				why.append("%s: %s twice" % [stage, d.id])
			ids[d.id] = true
			if String(d.name).length() > MAX_NAME:
				why.append("%s: %s's name is too long" % [stage, d.id])
			if not bool(has_pic.call(String(d.pic))):
				why.append("%s: no picture %s" % [stage, d.pic])
			for fx in d.fx:
				if not CAPS.has(String(fx[0])):
					why.append("%s %s: %s has no cap" % [stage, d.id, fx[0]])
	if unlocked("hero", 0).size() < 2:
		why.append("a new family has only one hero")
	if unlocked("perk", 0).size() < OFFER:
		why.append("a new family has fewer than %d perks" % OFFER)
	return why
