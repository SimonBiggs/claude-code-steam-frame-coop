extends RefCounted
## PIP'S STREET (Hide and Seek, second pass): the family's houses are a STREET of neighbours. Every house on the
## street has a NEIGHBOUR FRIEND who hides with Pip (housegen.gd places them on fair hiding spots). Find a friend
## and they come to PIP'S GARDEN PARTY: they sit round the picnic blanket in every house's garden for good (saved
## as `party`), and the party grows decorations as more friends come (bunting, balloons, a cake, lanterns).
## Each house on a street has a TWIST, rising along the street:
##   SNEAKY - the friend sneaks to a new hiding spot once (when the seeker gets close, or half way through);
##   DARK   - the friend hides in a DARK ROOM (no lamp, curtains shut): only their glowing eyes and your torch;
##   TWINS  - two friends hide in the house.
## A street is STREET_LEN houses; then a new street starts (a bit harder). TODAY'S STREET is the daily round: a
## daily house with two friends and a twist, the same on every machine all day (daily_done once it is finished).
## Pure data + small functions: main.gd, housegen.gd and tests/hide_and_seek_gen_test.gd use it.

const Seeded := preload("res://core/seeded.gd")
const Story := preload("res://games/hide_and_seek/story.gd")

const SNEAKY := 1
const DARK := 2
const TWINS := 4
const STREET_LEN := 6
const FRIEND_POINTS := 25
## Twists for the houses along a street (first street); later streets add more (twist()).
const ALONG := [0, SNEAKY, DARK, TWINS, SNEAKY | DARK, TWINS | SNEAKY]

## The neighbours: id (index), name, story picture, body kind (friend.gd), fur, light patch.
const FRIENDS: Array[Dictionary] = [
	{"name": "BUN", "pic": "bunny", "kind": "bunny", "fur": Color(0.92, 0.9, 0.88), "light": Color(1.0, 0.8, 0.85)},
	{"name": "KIT", "pic": "kitten", "kind": "kitten", "fur": Color(0.6, 0.62, 0.68), "light": Color(0.95, 0.95, 0.97)},
	{"name": "SPIKE", "pic": "hedgehog", "kind": "hedgehog", "fur": Color(0.5, 0.36, 0.24), "light": Color(0.95, 0.85, 0.7)},
	{"name": "HOOT", "pic": "owl", "kind": "owl", "fur": Color(0.62, 0.45, 0.3), "light": Color(0.96, 0.9, 0.78)},
	{"name": "TESS", "pic": "tortoise", "kind": "tortoise", "fur": Color(0.45, 0.68, 0.35), "light": Color(0.75, 0.55, 0.3)},
	{"name": "FIZZ", "pic": "frog", "kind": "frog", "fur": Color(0.4, 0.8, 0.35), "light": Color(0.85, 0.95, 0.6)},
	{"name": "NUTMEG", "pic": "squirrel", "kind": "squirrel", "fur": Color(0.82, 0.45, 0.2), "light": Color(1.0, 0.88, 0.72)},
	{"name": "POM", "pic": "hamster", "kind": "hamster", "fur": Color(0.95, 0.72, 0.4), "light": Color(1.0, 0.95, 0.85)},
]

## The garden party's decorations: friends at the party needed, story picture, one line.
const DECOR: Array[Dictionary] = [
	{"id": "blanket", "need": 1, "pic": "gardenparty", "line": "A garden party!"},
	{"id": "bunting", "need": 2, "pic": "bunting", "line": "Party flags!"},
	{"id": "balloons", "need": 4, "pic": "balloon", "line": "Party balloons!"},
	{"id": "cake", "need": 6, "pic": "cake", "line": "A party cake!"},
	{"id": "lanterns", "need": 8, "pic": "lantern", "line": "Party lanterns!"},
]


static func friend(i: int) -> Dictionary:
	return FRIENDS[posmod(i, FRIENDS.size())]


## Which street (0-based) and which house on it (0..STREET_LEN-1) house number n is.
static func street_of(n: int) -> int:
	return maxi(0, n) / STREET_LEN


static func slot_of(n: int) -> int:
	return posmod(n, STREET_LEN)


## The twist bits for a house on a street: the first street climbs ALONG; later streets add SNEAKY to the first
## house and DARK to the twin houses.
static func twist(street: int, slot: int) -> int:
	var t: int = ALONG[posmod(slot, STREET_LEN)]
	if street >= 1 and slot == 0:
		t |= SNEAKY
	if street >= 2 and (t & TWINS) != 0:
		t |= DARK
	return t


static func friends_needed(tw: int) -> int:
	return 2 if (tw & TWINS) != 0 else 1


## The friends hiding in house n: the street's neighbours in a seeded order, friends not at the party yet first
## (so every friend comes to the party in time), then the street order.
static func pick_friends(world: int, n: int, party: Array, count: int) -> Array:
	var order: Array = Seeded.shuffled(Seeded.rng(world, "street%d" % street_of(n)), range(FRIENDS.size()))
	var out: Array = []
	for f in order:
		if out.size() < count and not party.has(f):
			out.append(f)
	var k := slot_of(n)
	while out.size() < count:
		var f: int = order[(k + out.size() * 3) % order.size()]
		if not out.has(f):
			out.append(f)
		k += 1
	return out


## Add the street (friends, twist, street, slot) to a house spec from Story.house_spec.
static func dress(spec: Dictionary, world: int, n: int, party: Array) -> Dictionary:
	var sp := spec.duplicate()
	var st := street_of(n)
	var sl := slot_of(n)
	var tw := twist(st, sl)
	sp["twist"] = tw
	sp["friends"] = pick_friends(world, n, party, friends_needed(tw))
	sp["street"] = st
	sp["slot"] = sl
	return sp


## TODAY'S STREET: today's house (Story.daily) with two neighbours and a twist, the same all day everywhere.
static func daily(date: String = "") -> Dictionary:
	var sp := Story.daily(date)
	var r := Seeded.rng(int(sp.seed), "street")
	var tw: int = TWINS | ([SNEAKY, DARK, SNEAKY | DARK][r.randi() % 3] as int)
	var all: Array = Seeded.shuffled(r, range(FRIENDS.size()))
	sp["twist"] = tw
	sp["friends"] = [all[0], all[1]]
	sp["street"] = -1
	sp["slot"] = -1
	return sp


## Decorations the party has with this many friends (indices into DECOR).
static func decor(friends: int) -> Array:
	var out: Array = []
	for i in DECOR.size():
		if friends >= int(DECOR[i].need):
			out.append(i)
	return out


## The decoration a new friend count just brought (-1 if none).
static func new_decor(before: int, after: int) -> int:
	for i in DECOR.size():
		var need := int(DECOR[i].need)
		if before < need and after >= need:
			return i
	return -1


## Short words for a twist (story cards; picture first).
static func twist_cards(tw: int) -> Array:
	var out: Array = []
	if (tw & DARK) != 0:
		out.append({"who": "DARK ROOM", "line": "Use your torch!", "pic": "darkroom", "color": Color(0.55, 0.5, 0.9)})
	if (tw & SNEAKY) != 0:
		out.append({"who": "SNEAKY!", "line": "They move once!", "pic": "pawprints", "color": Color(0.95, 0.7, 0.4)})
	return out
