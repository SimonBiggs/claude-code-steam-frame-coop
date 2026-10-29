extends RefCounted
## WHACK-A-MOLE story and progression: FARMER FIG's garden. Cheeky moles keep popping up in Fig's veg
## patch; every point the team bonks becomes a veg in the bed Fig is growing (the plants round the
## table sprout and grow while you play). A full bed stays in the garden for good (saved, so the garden
## grows over days). Then the team CHOOSES the next crop: two seed packets pop up, bonk one. Each crop
## brings its own VISITOR moles (carrots: speedy, pumpkins: helmets, strawberries: bunnies - don't bonk!
## melons: the KING). Moles already met keep visiting a little. More beds -> quicker, busier rounds
## (roundgen.gd level). After every crop has a bed, beds grow again into GIANT veg (bonus lap).
## The first round each day is TODAY'S PATCH: the same moles on every machine all day.
## Round stars (1-3) are the readable challenge; the best per crop is saved.
## Lines are a few words (kids read them; picture first). Pure data + small functions.

const Seeded := preload("res://core/seeded.gd")
const RoundGen := preload("res://games/whack_a_mole/roundgen.gd")

const FIG_COLOR := Color(0.55, 0.85, 0.35)
## Crops in unlock order. need: beds grown before it can be offered. kinds: visitor mole chances.
## pic: core/story_card.gd picture. color: the bed's veg colour.
const CROPS: Array[Dictionary] = [
	{"id": "LETTUCE", "pic": "lettuce", "color": Color(0.45, 0.85, 0.35), "need": 0, "kinds": {}, "gold": 0.06,
		"intro": "Moles in my lettuce!", "done": "Crunchy lettuce!"},
	{"id": "CARROTS", "pic": "carrot", "color": Color(1.0, 0.55, 0.15), "need": 1, "kinds": {RoundGen.SPEEDY: 0.3}, "gold": 0.06,
		"intro": "Speedy moles! Quick!", "done": "Carrots! Crunch!"},
	{"id": "PUMPKINS", "pic": "pumpkin", "color": Color(1.0, 0.5, 0.1), "need": 1, "kinds": {RoundGen.HELMET: 0.25}, "gold": 0.06,
		"intro": "Helmets! Bonk twice!", "done": "Big round pumpkins!"},
	{"id": "SUNFLOWERS", "pic": "sunflower", "color": Color(1.0, 0.85, 0.2), "need": 2, "kinds": {}, "gold": 0.16,
		"intro": "Golden moles love sun!", "done": "Sunflowers! So tall!"},
	{"id": "STRAWBERRIES", "pic": "strawberry", "color": Color(0.95, 0.2, 0.3), "need": 3, "kinds": {RoundGen.BUNNY: 0.22}, "gold": 0.06,
		"intro": "Bunnies are friends!", "done": "Sweet strawberries!"},
	{"id": "CORN", "pic": "corn", "color": Color(1.0, 0.9, 0.35), "need": 4, "kinds": {RoundGen.SPEEDY: 0.18, RoundGen.HELMET: 0.15}, "gold": 0.06,
		"intro": "Fast ones and helmets!", "done": "Corn! Pop pop!"},
	{"id": "MELONS", "pic": "melon", "color": Color(0.35, 0.7, 0.3), "need": 5, "kinds": {RoundGen.HELMET: 0.12}, "gold": 0.06, "king": true,
		"intro": "The MOLE KING is coming!", "done": "Juicy melons!"},
	{"id": "APPLES", "pic": "apple", "color": Color(0.9, 0.15, 0.2), "need": 6, "kinds": {RoundGen.SPEEDY: 0.12, RoundGen.BUNNY: 0.12}, "gold": 0.08, "king": true,
		"intro": "Everyone's here!", "done": "An apple tree!"},
]
const FIRST_CROP := "LETTUCE"
## The first time each visitor kind shows up, Fig points at it (picture = a mole in that look).
const KIND_LINES := {RoundGen.GOLD: "Golden! Five points!", RoundGen.HELMET: "Helmet! Bonk bonk!",
	RoundGen.SPEEDY: "Zoom! A speedy one!", RoundGen.BUNNY: "A bunny! Don't bonk!", RoundGen.KING: "The KING! All bonk!"}
const CHEERS: Array[String] = ["Bonk bonk!", "Great bonking!", "Hooray!", "My veg is growing!", "Super team!"]
const PICK_LINE := "Pick the seeds!"
const OLD_KIND_CHANCE := 0.06  ## visitor kinds met before keep visiting a bit in every round


static func crop(id: String) -> Dictionary:
	for c in CROPS:
		if c.id == id:
			return c
	return CROPS[0]


static func crop_index(id: String) -> int:
	for i in CROPS.size():
		if CROPS[i].id == id:
			return i
	return 0


## The save's default data (core/save.gd fills missing keys from this).
## beds: {crop id: times grown}; cur: the bed growing now ("" = pick next); fill: veg in it.
static func save_defaults() -> Dictionary:
	return {"best": 0, "world": -1, "beds": {}, "cur": FIRST_CROP, "fill": 0, "rounds": 0, "stars": {},
		"daily": {}, "met": {}, "bunnies": 0, "kings": 0}


static func beds_grown(beds: Dictionary) -> int:
	var n := 0
	for k in beds:
		n += int(beds[k])
	return n


## Veg a bed needs: a bit more for every bed already grown.
static func bed_need(beds_done: int) -> int:
	return 24 + 6 * mini(beds_done, 10)


## The two seed packets to choose from after a bed is full: open crops (need <= beds grown), the
## least-grown first (new crops before giant ones), never the bed just finished when that can be helped.
static func offers(world: int, beds: Dictionary, last: String = "") -> Array:
	var done := beds_grown(beds)
	var rng := Seeded.rng(world, "offers%d" % done)
	var open: Array = []
	for c in CROPS:
		if int(c.need) <= done:
			open.append(c.id)
	var pool: Array = open.filter(func(id: String) -> bool: return id != last)
	if pool.size() < 2:
		pool = open.duplicate()
	pool = Seeded.shuffled(rng, pool)
	pool.sort_custom(func(a: String, b: String) -> bool:
		var ta := int(beds.get(a, 0))
		var tb := int(beds.get(b, 0))
		if ta != tb:
			return ta < tb
		return crop_index(a) > crop_index(b))  # newest first among equals
	return pool.slice(0, 2)


## The round spec for roundgen.gd. met: {kind: true} visitor kinds the family has met.
static func spec(crop_id: String, beds_done: int, met: Dictionary, players: int, time: float) -> Dictionary:
	var c := crop(crop_id)
	var kinds: Dictionary = (c.kinds as Dictionary).duplicate()
	for k in met:
		var kk := int(k)
		if kk in [RoundGen.HELMET, RoundGen.SPEEDY, RoundGen.BUNNY] and not kinds.has(kk):
			kinds[kk] = OLD_KIND_CHANCE
	var lap := beds_done / CROPS.size()
	return {"time": time, "level": beds_done + lap, "players": players, "kinds": kinds, "gold": float(c.gold),
		"king": bool(c.get("king", false)) or lap >= 1 and beds_done % 3 == 2, "name": c.id}


## Kinds a round of this spec may hold (for the validator).
static func allowed(sp: Dictionary) -> Array:
	var out: Array = [RoundGen.NORMAL, RoundGen.GOLD]
	for k in sp.kinds:
		out.append(int(k))
	if bool(sp.get("king", false)):
		out.append(RoundGen.KING)
	return out


## TODAY'S PATCH: the same on every machine all day (pass `date` in tests). A mixed bag of visitors.
static func daily_spec(players: int, time: float, date: String = "") -> Dictionary:
	var sd := Seeded.daily_seed("whack_a_mole", date)
	var r := Seeded.rng(sd, "daily")
	var kinds := {}
	var pool: Array = [RoundGen.SPEEDY, RoundGen.HELMET, RoundGen.BUNNY]
	for k in Seeded.shuffled(r, pool).slice(0, r.randi_range(1, 2)):
		kinds[k] = 0.15
	var c: Dictionary = CROPS[r.randi() % CROPS.size()]
	return {"time": time, "level": 4, "players": players, "kinds": kinds, "gold": 0.1, "king": r.randf() < 0.5,
		"name": "TODAY", "crop": c.id}


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed("whack_a_mole", date)
