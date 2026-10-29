extends RefCounted
## CRYSTAL SAGA story: LUMI, a little glowing crystal fairy from Willowbrook, asks the heroes to bring
## back the Crystal of Light. Every journey north (sagagen.gd: a new seeded road each time) ends at the
## shrine; on the way the party finds CRYSTAL SHARDS (one for every place cleared, one in every chest).
## Back home every few shards bring a place of Willowbrook back to life: the windmill, the fountain,
## the flower garden ... and they STAY (saved), so the village grows journey after journey.
## The party LEVELS UP twice a journey (after the forest and after the giant): two glowing stones, a
## SPELL and a SWORD TRICK (pictures, no words); touch or shoot one. Skills are kept and grow to
## level 3. Journeys get one tier harder as they go (sagagen.gd TIERS). The first journey of each day
## is TODAY'S QUEST: the same road on every machine all day.

const Seeded := preload("res://core/seeded.gd")
const SagaGen := preload("res://games/crystal_saga/sagagen.gd")

const GAME_ID := "crystal_saga"
const LUMI := "LUMI"
const LUMI_COLOR := Color(0.55, 0.85, 1.0)
const DAILY_NAME := "TODAY'S QUEST!"
const SHARDS_PER_PLACE := 3
const MAX_LEVEL := 3
const LEVELUP_ZONES: Array[int] = [1, 3]  ## the party picks a skill after clearing these

## Skills: a SPELL or a SWORD TRICK each; the party shares them (levels 0..3, saved).
const SKILLS := {
	"splash": {"type": "spell", "pic": "bigfire", "name": "BIG FIRE!", "color": Color(1.0, 0.55, 0.2)},
	"ice": {"type": "spell", "pic": "snowflake", "name": "ICE!", "color": Color(0.6, 0.9, 1.0)},
	"twin": {"type": "spell", "pic": "twin", "name": "TWIN SPARK!", "color": Color(0.8, 0.55, 1.0)},
	"long": {"type": "trick", "pic": "longsword", "name": "LONG SWORD!", "color": Color(0.75, 0.9, 1.0)},
	"spin": {"type": "trick", "pic": "spin", "name": "SPIN!", "color": Color(0.5, 1.0, 0.8)},
	"mighty": {"type": "trick", "pic": "mighty", "name": "MIGHTY!", "color": Color(1.0, 0.8, 0.3)},
}
const SPELLS: Array[String] = ["splash", "ice", "twin"]
const TRICKS: Array[String] = ["long", "spin", "mighty"]

## Willowbrook's places, in the order shards bring them back (world.gd builds them).
const PLACES: Array[Dictionary] = [
	{"id": "windmill", "pic": "windmill", "line": "The windmill is back!"},
	{"id": "fountain", "pic": "fountain", "line": "A sparkly fountain!"},
	{"id": "garden", "pic": "sunflower", "line": "The flower garden!"},
	{"id": "lanterns", "pic": "star", "line": "Lanterns! So bright!"},
	{"id": "bakery", "pic": "house", "line": "The bakery is back!"},
	{"id": "pond", "pic": "wave", "line": "The duck pond!"},
	{"id": "market", "pic": "gift", "line": "The market is open!"},
	{"id": "tower", "pic": "castle", "line": "The tall tower!"},
	{"id": "statue", "pic": "knight", "line": "A hero statue! You!"},
	{"id": "rainbow", "pic": "rainbow", "line": "A crystal rainbow!"},
]

const LINES := {
	"hello": "Hi! I'm Lumi!",
	"broken": "The Crystal broke!",
	"help": "Bring back the light!",
	"daily": "TODAY'S QUEST!",
	"start": ["Off we go, heroes!", "A new road north!", "Adventure time!", "Follow the light!"],
	"levelup": "LEVEL UP! Pick one!",
	"new_spell": "A new spell!",
	"new_trick": "A new sword trick!",
	"stronger": "Even stronger!",
	"shard": "A crystal shard!",
	"restored": ["The light is back!", "You did it, heroes!", "Hooray! Light!"],
	"village": "Look! Willowbrook!",
}


static func save_defaults() -> Dictionary:
	return {"restored": 0, "world": -1, "daily": {}, "skills": {}, "shards": 0, "seen_places": 0, "journeys": 0}


static func tier_for(journeys: int) -> int:
	return clampi(journeys, 0, SagaGen.TIERS - 1)


## Which journey to play next: {"seed", "tier", "daily"}.
static func journey(journeys: int, world: int, daily_due: bool, date: String = "") -> Dictionary:
	if daily_due:
		return {"seed": daily_seed(date), "tier": tier_for(journeys), "daily": true}
	return {"seed": Seeded.derive(world, "journey%d" % journeys), "tier": tier_for(journeys), "daily": false}


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


static func level(skills: Dictionary, id: String) -> int:
	return clampi(int(skills.get(id, 0)), 0, MAX_LEVEL)


## The party's level: 1 + every skill level learned.
static func party_level(skills: Dictionary) -> int:
	var n := 1
	for id in SKILLS:
		n += level(skills, id)
	return n


## The two stones of a level-up: [spell id, trick id] (empty: nothing left to learn). Unlearned first.
static func offer(seed_value: int, round_no: int, skills: Dictionary) -> Array:
	var r := Seeded.rng(seed_value, "offer%d" % round_no)
	var out: Array = []
	for pool in [SPELLS, TRICKS]:
		var best: Array = []
		var low := MAX_LEVEL
		for id in pool:
			var l := level(skills, id)
			if l < low:
				low = l
				best = [id]
			elif l == low and l < MAX_LEVEL:
				best.append(id)
		if not best.is_empty():
			out.append(String(Seeded.pick(r, best)))
	return out


## Places of Willowbrook back from `shards` shards.
static func places_for(shards: int) -> int:
	return clampi(shards / SHARDS_PER_PLACE, 0, PLACES.size())


static func pick(r: RandomNumberGenerator, key: String) -> String:
	var v: Variant = LINES.get(key, "")
	if v is Array:
		return String(Seeded.pick(r, v))
	return String(v)


## Story rules the tests check.
static func self_check() -> Array:
	var why: Array = []
	var j1 := journey(3, 77, true, "2026-10-29")
	if not bool(j1.daily) or int(j1.seed) != daily_seed("2026-10-29"):
		why.append("TODAY'S QUEST doesn't use the day's seed")
	if int(journey(3, 77, false).seed) == int(journey(4, 77, false).seed):
		why.append("two journeys share a road")
	if tier_for(0) != 0 or tier_for(999) != SagaGen.TIERS - 1:
		why.append("tiers don't rise (or run past the last)")
	# Level-ups: a spell and a trick, unlearned first, until everything is at the top level.
	var skills := {}
	var rounds := 0
	while rounds < 40:
		var o := offer(5, rounds, skills)
		if o.is_empty():
			break
		if o.size() == 2 and (not SPELLS.has(String(o[0])) or not TRICKS.has(String(o[1]))):
			why.append("an offer isn't a spell and a trick: %s" % str(o))
		for id in o:
			for other in SKILLS:
				if level(skills, String(other)) < level(skills, String(id)) and SKILLS[other].type == SKILLS[id].type:
					why.append("offered %s before %s" % [id, other])
		var take: String = o[rounds % o.size()]
		skills[take] = level(skills, take) + 1
		rounds += 1
	if rounds != SKILLS.size() * MAX_LEVEL:
		why.append("skills run out after %d level-ups" % rounds)
	if party_level(skills) != 1 + SKILLS.size() * MAX_LEVEL:
		why.append("party level is off")
	if places_for(0) != 0 or places_for(SHARDS_PER_PLACE) != 1 or places_for(9999) != PLACES.size():
		why.append("places_for is off")
	for key in LINES:
		var v: Variant = LINES[key]
		for line in (v if v is Array else [v]):
			if String(line).length() > 24:
				why.append("line too long: %s" % line)
	for p in PLACES:
		if String(p.line).length() > 24:
			why.append("place line too long: %s" % p.line)
	for id in SKILLS:
		if String(SKILLS[id].name).length() > 14:
			why.append("skill name too long: %s" % SKILLS[id].name)
	return why
