extends RefCounted
## MYSTERY MANOR cases (pure data, host only; every machine gets the case through the state store).
## Kept visual, like Guess Who, so nobody needs to read: six suspects, each with a HAT and a COAT
## COLOUR. Three hat shapes x two colours = six different suspects. Two clues are hidden in the manor:
## a scrap of the culprit's coat (its colour) and the culprit's dropped hat (its shape). Each clue on its
## own fits two or three suspects; both together fit exactly one. The stolen thing is hidden too.
## check() is the deduction checker (the bot runs it over hundreds of seeds).

const Manor := preload("res://games/mystery_manor/manor.gd")

## Hats whose colours don't depend on the coat (core/creatures.gd _hat), with clearly different shapes.
const HATS: Array[String] = ["chef", "crown", "tricorn", "viking", "straw", "hard_hat"]  ## not deerstalker: the players (detectives) wear it
const COLOURS: Array[Color] = [Color(0.9, 0.22, 0.22), Color(0.25, 0.45, 0.95), Color(0.25, 0.75, 0.3),
	Color(0.98, 0.8, 0.2), Color(0.65, 0.35, 0.9)]
## Stolen things: id, title (the case card), what to build (see main.gd _make_item).
const ITEMS := [
	{"id": "cake", "title": "THE MISSING CAKE"},
	{"id": "gem", "title": "THE MISSING JEWEL"},
	{"id": "chest", "title": "THE MISSING TREASURE"},
	{"id": "star", "title": "THE MISSING GOLD STAR"},
	{"id": "candle", "title": "THE MISSING MAGIC CANDLE"},
	{"id": "heart", "title": "THE MISSING RUBY HEART"},
]
## Which clue is which (index into case.spots and the "found" list).
const CLUE_COLOUR := 0
const CLUE_HAT := 1
const CLUE_ITEM := 2


## A new case. {seed, suspects: [[hat, colour index]], culprit, item, spots: [colour, hat, item] (Manor.SPOTS
## indices, three different rooms, never the hall where the suspects wait)}.
static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var hats := HATS.duplicate()
	_shuffle(hats, rng)
	var cols: Array[int] = []
	for i in COLOURS.size():
		cols.append(i)
	_shuffle_i(cols, rng)
	var suspects: Array = []
	for h in 3:
		for c in 2:
			suspects.append([String(hats[h]), cols[c]])
	_shuffle(suspects, rng)
	var rooms: Array[int] = []
	for r in Manor.ROOMS.size():
		if r != Manor.HALL and not Manor.spots_in_room(r).is_empty():
			rooms.append(r)
	_shuffle_i(rooms, rng)
	var spots: Array[int] = []
	for k in 3:
		var in_room := Manor.spots_in_room(rooms[k])
		spots.append(in_room[rng.randi() % in_room.size()])
	return {"seed": seed_value, "suspects": suspects, "culprit": rng.randi() % suspects.size(),
		"item": rng.randi() % ITEMS.size(), "spots": spots}


## Suspects that fit the clues found so far (found: [colour?, hat?, item?]).
static func fits(case: Dictionary, found: Array) -> Array[int]:
	var sus: Array = case["suspects"]
	var c: Array = sus[int(case["culprit"])]
	var out: Array[int] = []
	for i in sus.size():
		var s: Array = sus[i]
		if found.size() > CLUE_COLOUR and bool(found[CLUE_COLOUR]) and int(s[1]) != int(c[1]):
			continue
		if found.size() > CLUE_HAT and bool(found[CLUE_HAT]) and String(s[0]) != String(c[0]):
			continue
		out.append(i)
	return out


## The deduction checker: "" when the case is fair, else what is wrong.
static func check(case: Dictionary) -> String:
	var sus: Array = case["suspects"]
	if sus.size() != 6:
		return "want 6 suspects"
	var seen := {}
	for s in sus:
		var key := str(s)
		if seen.has(key):
			return "two suspects look the same: %s" % key
		seen[key] = true
	if fits(case, [true, true, false]).size() != 1:
		return "both clues don't point to exactly one suspect"
	if fits(case, [true, false, false]).size() < 2:
		return "the coat clue alone already gives it away"
	if fits(case, [false, true, false]).size() < 2:
		return "the hat clue alone already gives it away"
	if not fits(case, [true, true, false]).has(int(case["culprit"])):
		return "the clues point away from the culprit"
	var spots: Array = case["spots"]
	var rooms := {}
	for sp in spots:
		var r := int((Manor.SPOTS[int(sp)] as Dictionary)["room"])
		if r == Manor.HALL or rooms.has(r):
			return "clues must be in three different rooms, not the hall"
		rooms[r] = true
	return ""


static func colour_of(case: Dictionary, suspect: int) -> Color:
	var s: Array = (case["suspects"] as Array)[suspect]
	return COLOURS[int(s[1])]


static func hat_of(case: Dictionary, suspect: int) -> String:
	var s: Array = (case["suspects"] as Array)[suspect]
	return String(s[0])


static func title(case: Dictionary) -> String:
	return String((ITEMS[int(case["item"])] as Dictionary)["title"])


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


static func _shuffle_i(a: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := a[i]
		a[i] = a[j]
		a[j] = t
