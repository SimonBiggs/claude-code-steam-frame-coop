extends RefCounted
## CRYSTAL SAGA heroes for the TV / Deck party. Behind the spawn in Willowbrook stand hero statues: bonk one (A)
## to become that hero (kept for that seat, saved). Locked statues stay dark until Willowbrook has grown enough
## (places brought back with crystal shards, saga.gd places_for).
##  KNIGHT  a sword SLASH (short reach, hits everything just in front), pops up quicker when bumped.
##  MAGE    a magic spark (far), with a little splash where it lands.
##  ARCHER  an arrow (farthest), quick on her feet.
##  HEALER  a healing spark: her shots also wake up dizzy friends near her and give them a moment of safety.
##  BARD    a music note: what it hits, and monsters right next to it, stop to listen (freeze) a moment.
## The VR player is always the big knight with his real sword; classes are for the TV / Deck heroes.

const ORDER: Array[String] = ["knight", "mage", "archer", "healer", "bard"]
## look: Creatures humanoid class; shot: main.gd shot kind; reach: shot range (m); places: Willowbrook places
## needed to unlock; pic: story picture; speed: walk speed factor; dizzy: dizzy time factor.
const INFO := {
	"knight": {"name": "KNIGHT", "look": "knight", "weapon": "sword", "shot": "slash", "reach": 3.2, "places": 0,
		"pic": "knight", "color": Color(0.75, 0.82, 1.0), "speed": 1.0, "dizzy": 0.6},
	"mage": {"name": "MAGE", "look": "mage", "weapon": "staff", "shot": "magic", "reach": 11.0, "places": 0,
		"pic": "wizard", "color": Color(0.8, 0.6, 1.0), "speed": 1.0, "dizzy": 1.0},
	"archer": {"name": "ARCHER", "look": "archer", "weapon": "bow", "shot": "arrow", "reach": 13.0, "places": 0,
		"pic": "archer", "color": Color(0.55, 0.95, 0.55), "speed": 1.12, "dizzy": 1.0},
	"healer": {"name": "HEALER", "look": "healer", "weapon": "rod", "shot": "heal", "reach": 10.0, "places": 2,
		"pic": "healer", "color": Color(1.0, 0.6, 0.7), "speed": 1.0, "dizzy": 0.8},
	"bard": {"name": "BARD", "look": "bard", "weapon": "lute", "shot": "note", "reach": 10.0, "places": 5,
		"pic": "bard", "color": Color(1.0, 0.75, 0.35), "speed": 1.05, "dizzy": 1.0},
}
const HEAL_R := 3.0  ## a healer's spark wakes dizzy friends this near her
const NOTE_R := 1.6  ## a bard's note freezes monsters this near what it hits
const NOTE_FREEZE := 1.6


static func info(id: String) -> Dictionary:
	return INFO.get(id, INFO["mage"])


static func valid(id: String) -> bool:
	return INFO.has(id)


static func unlocked(places: int) -> Array:
	var out: Array = []
	for id in ORDER:
		if places >= int(INFO[id]["places"]):
			out.append(id)
	return out


## A seat's starting hero (before anyone picks): slot 0 (local play without a headset) a knight, then mage,
## archer, mage, archer ... (as before classes).
static func default_for(slot: int) -> String:
	return ["knight", "mage", "archer", "mage", "archer", "mage", "archer"][slot % 7]


## The hero a seat plays: its saved pick if unlocked, else the default.
static func of(classes: Dictionary, slot: int, places: int) -> String:
	var id := String(classes.get(str(slot), default_for(slot)))
	if not valid(id) or places < int(INFO[id]["places"]):
		return default_for(slot)
	return id


## Class rules the tests check.
static func self_check() -> Array:
	var why: Array = []
	if unlocked(0).size() < 3:
		why.append("fewer than three heroes to start with")
	if unlocked(99).size() != ORDER.size():
		why.append("not every hero unlocks")
	for id in ORDER:
		var inf: Dictionary = INFO[id]
		if String(inf.name).length() > 8:
			why.append("hero name too long: %s" % inf.name)
		if float(inf.reach) < 3.0 or float(inf.speed) > 1.2 or float(inf.dizzy) <= 0.3:
			why.append("hero %s is unfair" % id)
	if of({"1": "bard"}, 1, 0) != default_for(1):
		why.append("a locked hero can be played")
	return why
