extends RefCounted
## FISHING LAKE story: OLLIE THE OTTER keeps the lake's FISH BOOK, one page for every kind of fish (12).
## Every day on the lake is a new seeded lake (lakegen.gd: weather, fishing spots, who swims where).
## Each morning Ollie wishes for one fish - a missing page first - and the lake is shaped so it can be
## caught: a glowing picture of it floats over the spot where it lives. Every fish you ever catch goes in
## the book for good (saved, on the picture board by the jetty: caught fish in colour, missing ones as
## dark shadows). More days fished = more fish to find (rain and eels, then moonfish nights and OLD
## WHISKERS, then koi and the GOLDEN FISH). The first day each day is TODAY'S LAKE (the same everywhere).
## Pure data + small functions; lines are a few words (kids read them, picture first).

const Seeded := preload("res://core/seeded.gd")
const LakeGen := preload("res://games/fishing_lake/lakegen.gd")
const FishScript := preload("res://games/fishing_lake/fish.gd")

const OLLIE := Color(0.62, 0.42, 0.25)
const MILESTONES := {4: "A third of the book!", 6: "Half the book!", 9: "Nearly full!", 12: "The book is full!"}


static func save_defaults() -> Dictionary:
	# book: fish name -> [times caught, best kg]; days: days fished; daily: date -> fish caught.
	return {"world": -1, "days": 0, "book": {}, "daily": {}, "wishes": 0, "migrated": false}


## The level (0..3) after `days` days fished: what can swim in the lake.
static func level(days: int) -> int:
	return clampi(days, 0, 3)


static func found(book: Dictionary) -> Array:
	var out: Array = []
	for k in LakeGen.species():
		if int((book.get(FishScript.TYPES[k].name, [0, 0.0]) as Array)[0]) > 0:
			out.append(k)
	return out


static func missing(book: Dictionary, lvl: int) -> Array:
	var have := found(book)
	var out: Array = []
	for k in LakeGen.species():
		if LakeGen.unlocked(k, lvl) and not have.has(k):
			out.append(k)
	return out


## Ollie's wish for a normal day: a missing page (one of the first two missing, by the seed), else any
## fish that's unlocked (a new record to chase).
static func pick_wish(book: Dictionary, lvl: int, seed_value: int) -> int:
	var r := Seeded.rng(seed_value, "wish")
	var miss := missing(book, lvl)
	if not miss.is_empty():
		return int(miss[r.randi() % mini(2, miss.size())])
	var all: Array = []
	for k in LakeGen.species():
		if LakeGen.unlocked(k, lvl) and k != LakeGen.LEGEND:
			all.append(k)
	return int(Seeded.pick(r, all))


## TODAY'S LAKE (shaped the same for everyone): the wish is a missing page this lake has, else any fish it has.
static func pick_daily_wish(book: Dictionary, lake: Dictionary) -> int:
	var can := LakeGen.catchable(lake)
	can.erase(LakeGen.LEGEND)
	for k in missing(book, int(lake.level)):
		if can.has(k):
			return int(k)
	return -1 if can.is_empty() else int(Seeded.pick(Seeded.rng(int(lake.seed), "wish"), can))


## Add a catch: returns true when it's a new page.
static func add(book: Dictionary, kind: int, kg: float) -> bool:
	var nm: String = FishScript.TYPES[kind].name
	var e: Array = (book.get(nm, [0, 0.0]) as Array).duplicate()
	var first := int(e[0]) == 0
	e[0] = int(e[0]) + 1
	e[1] = maxf(float(e[1]), snappedf(kg, 0.01))
	book[nm] = e
	return first


static func fish_color(kind: int) -> Color:
	return FishScript.TYPES[kind].col if kind >= 0 else OLLIE
