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
const Realm := preload("res://games/crystal_saga/realm.gd")

const GAME_ID := "crystal_saga"
const LUMI := "LUMI"
const LUMI_COLOR := Color(0.55, 0.85, 1.0)
const DAILY_NAME := "TODAY'S QUEST!"
const SHARDS_PER_PLACE := 3
const MAX_LEVEL := 3
const LEVELUP_ZONES: Array[int] = [1, 3]  ## the party picks a skill after clearing these

## Skills: a SPELL or a SWORD TRICK each; the party shares them (levels 0..3, saved). places: Willowbrook places
## needed before Lumi offers it (the village grows, new magic appears).
const SKILLS := {
	"splash": {"type": "spell", "pic": "bigfire", "name": "BIG FIRE!", "color": Color(1.0, 0.55, 0.2), "places": 0},
	"ice": {"type": "spell", "pic": "snowflake", "name": "ICE!", "color": Color(0.6, 0.9, 1.0), "places": 0},
	"twin": {"type": "spell", "pic": "twin", "name": "TWIN SPARK!", "color": Color(0.8, 0.55, 1.0), "places": 0},
	"heal": {"type": "spell", "pic": "heart", "name": "HEALING!", "color": Color(1.0, 0.55, 0.65), "places": 1},
	"star": {"type": "spell", "pic": "starrain", "name": "STAR RAIN!", "color": Color(1.0, 0.92, 0.45), "places": 4},
	"long": {"type": "trick", "pic": "longsword", "name": "LONG SWORD!", "color": Color(0.75, 0.9, 1.0), "places": 0},
	"spin": {"type": "trick", "pic": "spin", "name": "SPIN!", "color": Color(0.5, 1.0, 0.8), "places": 0},
	"mighty": {"type": "trick", "pic": "mighty", "name": "MIGHTY!", "color": Color(1.0, 0.8, 0.3), "places": 0},
	"bubble": {"type": "trick", "pic": "bubbleshield", "name": "BUBBLE!", "color": Color(0.6, 0.85, 1.0), "places": 3},
}
const SPELLS: Array[String] = ["splash", "ice", "twin", "heal", "star"]
const TRICKS: Array[String] = ["long", "spin", "mighty", "bubble"]
## What Willowbrook's growth unlocks (shown as a story card the journey it happens): [places, kind, id].
const UNLOCKS: Array = [[1, "skill", "heal"], [2, "hero", "healer"], [3, "skill", "bubble"], [4, "skill", "star"],
	[5, "hero", "bard"]]

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
	"map": "Where shall we go?",
	"new_hero": "A new hero!",
	"new_magic": "New magic to learn!",
	"quest_done": "Thank you, heroes!",
	"guardian": "A crystal guardian!",
	"brave": "Brave mode! Tough!",
	"gentle": "Gentle mode.",
	"crystal_home": "A crystal comes home!",
	"realm_done": "Every crystal is home!",
	"help_me": "Help me, heroes!",
	"go": "Go, heroes! Go!",
	"new_road": "A new road opens!",
}


## The save (progress.gd SAVE_VERSION 2): restored = journeys finished; world = the family's realm seed;
## daily = {date: true} when TODAY'S QUEST was finished; cleared = realm slots whose guardian was beaten;
## classes = {seat: hero}; hard = BRAVE mode; seen_unlocks = UNLOCKS already announced.
static func save_defaults() -> Dictionary:
	return {"restored": 0, "world": -1, "daily": {}, "skills": {}, "shards": 0, "seen_places": 0, "journeys": 0,
		"cleared": [], "classes": {}, "hard": false, "seen_unlocks": 0}


## Which journey to play next: {"seed", "tier", "daily", "region"}. region: a realm slot (the map stones' pick;
## TODAY'S QUEST picks its own). journeys: journeys started so far (a new road every time).
static func journey(journeys: int, world: int, daily_due: bool, date: String = "", region: int = 0,
		cleared: Array = [], hard: bool = false) -> Dictionary:
	var realm := Realm.generate(world)
	if daily_due:
		var ds := daily_seed(date)
		var slot := Realm.daily_slot(realm, cleared, ds)
		return {"seed": ds, "tier": Realm.tier_of(realm, slot, cleared, hard), "daily": true, "region": slot}
	if not Realm.is_open(realm, region, cleared):
		region = int(Realm.choices(realm, cleared)[0])
	return {"seed": Seeded.derive(world, "journey%d" % journeys), "tier": Realm.tier_of(realm, region, cleared, hard),
		"daily": false, "region": region}


## The plan for a journey (sagagen.gd generate() for its region of the family's realm).
static func plan_for(j: Dictionary, world: int, hard: bool) -> Dictionary:
	var realm := Realm.generate(world)
	var slot := clampi(int(j.get("region", 0)), 0, Realm.SIZE - 1)
	return SagaGen.generate(int(j.seed), int(j.tier), int(realm.regions[slot].biome), String(realm.regions[slot].name), hard)


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


## The stones of a level-up: [spell id, trick id, one more] (fewer when little is left to learn). Unlearned
## first; only skills Willowbrook has unlocked (places).
static func offer(seed_value: int, round_no: int, skills: Dictionary, places: int = 99) -> Array:
	var r := Seeded.rng(seed_value, "offer%d" % round_no)
	var out: Array = []
	for pool in [SPELLS, TRICKS]:
		var best := _lowest(pool, skills, places, out)
		if not best.is_empty():
			out.append(String(Seeded.pick(r, best)))
	var all: Array = SPELLS + TRICKS
	var third := _lowest(all, skills, places, out)
	if not third.is_empty():
		out.append(String(Seeded.pick(r, third)))
	return out


static func _lowest(pool: Array, skills: Dictionary, places: int, skip: Array) -> Array:
	var best: Array = []
	var low := MAX_LEVEL
	for id in pool:
		if skip.has(id) or places < int(SKILLS[id].places):
			continue
		var l := level(skills, id)
		if l < low:
			low = l
			best = [id]
		elif l == low and l < MAX_LEVEL:
			best.append(id)
	return best


## Unlocks reached at `places` (UNLOCKS entries), from index `from`.
static func unlocks_between(from: int, places: int) -> Array:
	var out: Array = []
	for i in range(from, UNLOCKS.size()):
		if places >= int(UNLOCKS[i][0]):
			out.append(UNLOCKS[i])
	return out


static func unlock_count(places: int) -> int:
	var n := 0
	for u in UNLOCKS:
		n += 1 if places >= int(u[0]) else 0
	return n


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
	if int(journey(0, 77, false).tier) != 0 or int(journey(0, 77, false).region) != 0:
		why.append("the first journey isn't the gentle meadow")
	if int(journey(0, 77, false, "", 5).region) != 0:
		why.append("a closed region can be picked")
	if int(journey(0, 77, false, "", 0, [], true).tier) != 1:
		why.append("brave mode isn't a tier harder")
	# Level-ups: a spell and a trick, unlearned first, until everything is at the top level.
	var skills := {}
	var rounds := 0
	while rounds < 40:
		var o := offer(5, rounds, skills)
		if o.is_empty():
			break
		if o.size() >= 2 and (not SPELLS.has(String(o[0])) or not TRICKS.has(String(o[1]))):
			why.append("an offer isn't a spell and a trick: %s" % str(o))
		var dup := {}
		for id in o:
			if dup.has(id):
				why.append("an offer shows %s twice" % id)
			dup[id] = true
		for id in o.slice(0, 2):
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
	for o2 in [offer(9, 0, {}, 0), offer(9, 1, {"splash": 3, "ice": 3, "twin": 3}, 0)]:
		for id2 in o2:
			if int(SKILLS[id2].places) > 0:
				why.append("a locked skill is offered: %s" % id2)
	if offer(9, 0, {}, 99).size() != 3:
		why.append("a level-up doesn't show three stones")
	if SKILLS.size() < 6 or SKILLS.size() > 10:
		why.append("%d skills (6 to 10 to choose from)" % SKILLS.size())
	for u in UNLOCKS:
		if String(u[1]) == "skill" and not SKILLS.has(String(u[2])):
			why.append("unlock of a missing skill %s" % u[2])
		if String(u[1]) == "skill" and int(SKILLS[String(u[2])].places) != int(u[0]):
			why.append("unlock %s doesn't match its skill" % u[2])
	if unlocks_between(0, 0).size() != 0 or unlocks_between(0, 99).size() != UNLOCKS.size():
		why.append("unlocks_between is off")
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
