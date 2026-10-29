extends RefCounted
## BALLOON POP story and progression: POPPY'S FAIR. A gust blew Poppy the balloon seller's balloons all
## over the park; every point the team pops is a prize ticket, and tickets build Poppy's fair round the
## park, one ride at a time (fair.gd draws it: the ride being built rises out of the grass while you pop).
## A finished ride stays for good (saved, so the fair grows over days). Then the team CHOOSES the next
## ride: two big balloons float up carrying little models of the rides - pop the one you want. Each ride
## brings its own SPECIAL balloons (ice cream: ICE balloons, carousel: TWINS, castle: GRUMPY ones, big
## top: GIANTS, hot-air balloon: ROCKETS, fireworks: a bit of everything); special balloons already met
## keep visiting a little. More rides -> busier waves with more shapes (wavegen.gd level). After every
## ride is built, rides are built again and get lights (a bonus lap).
## The first round each day is TODAY'S SKY: the same sky and balloons on every machine all day.
## Round stars (1-3) are the readable challenge; the best per ride is saved.
## Lines are a few words (kids read them; picture first). Pure data + small functions.

const Seeded := preload("res://core/seeded.gd")
const WaveGen := preload("res://games/balloon_pop/wavegen.gd")

const POPPY_COLOR := Color(1.0, 0.45, 0.7)
## Rides in unlock order. need: rides built before it can be offered. kinds: special balloon chances.
## pic: core/story_card.gd picture. color: the ride's main colour.
const RIDES: Array[Dictionary] = [
	{"id": "BUNTING", "pic": "flag", "color": Color(1.0, 0.35, 0.4), "need": 0, "kinds": {}, "gold": 0.08,
		"intro": "Pop pop pop!", "done": "Flags! Hooray!"},
	{"id": "ICECREAM", "pic": "icecream", "color": Color(1.0, 0.75, 0.85), "need": 1, "kinds": {WaveGen.ICE: 0.16}, "gold": 0.08,
		"intro": "Ice balloons! Brrr!", "done": "Ice cream! Yum!"},
	{"id": "CAROUSEL", "pic": "carousel", "color": Color(0.4, 0.7, 1.0), "need": 1, "kinds": {WaveGen.TWINS: 0.18}, "gold": 0.08,
		"intro": "Twins! Pop pop pop!", "done": "Round and round!"},
	{"id": "CASTLE", "pic": "castle", "color": Color(0.75, 0.5, 1.0), "need": 2, "kinds": {}, "gold": 0.08, "grumpy": 0.16,
		"intro": "Grumpy ones! Don't pop!", "done": "Bouncy castle!"},
	{"id": "BIGTOP", "pic": "tent", "color": Color(0.95, 0.25, 0.3), "need": 3, "kinds": {}, "gold": 0.08, "giants": 2,
		"intro": "GIANTS! Hit hit hit!", "done": "The big top!"},
	{"id": "FERRIS", "pic": "ferris", "color": Color(1.0, 0.8, 0.25), "need": 4, "kinds": {}, "gold": 0.16, "rainbow": 2.0,
		"intro": "Rainbows! Pop them all!", "done": "A big wheel!"},
	{"id": "HOTAIR", "pic": "balloon", "color": Color(1.0, 0.55, 0.15), "need": 5, "kinds": {WaveGen.ROCKET: 0.22}, "gold": 0.08,
		"intro": "Rockets! Zoom!", "done": "Up up and away!"},
	{"id": "FIREWORKS", "pic": "star", "color": Color(0.3, 0.9, 0.6), "need": 6,
		"kinds": {WaveGen.ROCKET: 0.08, WaveGen.TWINS: 0.08, WaveGen.ICE: 0.08}, "gold": 0.1, "giants": 1, "grumpy": 0.08,
		"intro": "Everything at once!", "done": "FIREWORKS!"},
]
const FIRST_RIDE := "BUNTING"
## The first time the family meets each special balloon, Poppy shows it (picture = a balloon that colour).
const KIND_LINES := {WaveGen.GOLD: "Gold! Three points!", WaveGen.GRUMPY: "Grumpy! Don't pop!",
	WaveGen.ROCKET: "Rocket! Quick!", WaveGen.ICE: "Ice! Everything slows!", WaveGen.TWINS: "Twins! Pop pop pop!",
	WaveGen.GIANT: "GIANT! Hit it 3 times!"}
const KIND_COLORS := {WaveGen.GOLD: Color(1.0, 0.82, 0.2), WaveGen.GRUMPY: Color(0.45, 0.47, 0.52),
	WaveGen.ROCKET: Color(1.0, 0.45, 0.15), WaveGen.ICE: Color(0.7, 0.9, 1.0), WaveGen.TWINS: Color(1.0, 0.45, 0.8),
	WaveGen.GIANT: Color(0.6, 0.35, 1.0)}
const CHEERS: Array[String] = ["Pop pop hooray!", "What a team!", "My fair grows!", "Super popping!", "Wheee!"]
const PICK_LINE := "Pop the next ride!"
const SET_LINE := "Pop the whole set!"
const OLD_KIND_CHANCE := 0.05  ## special balloons met before keep visiting a bit
const OLD_GRUMPY := 0.06
const SKIES: Array[String] = ["day", "dawn", "sunset", "snowy"]


static func ride(id: String) -> Dictionary:
	for r in RIDES:
		if r.id == id:
			return r
	return RIDES[0]


static func ride_index(id: String) -> int:
	for i in RIDES.size():
		if RIDES[i].id == id:
			return i
	return 0


## The save's default data (core/save.gd fills missing keys from this).
## rides: {ride id: times built}; cur: the ride being built ("" = pick next); fill: tickets in it.
static func save_defaults() -> Dictionary:
	return {"best": 0, "world": -1, "rides": {}, "cur": FIRST_RIDE, "fill": 0, "rounds": 0, "stars": {},
		"daily": {}, "met": {}, "sets": 0, "giants": 0, "carry": 0}


static func rides_built(rides: Dictionary) -> int:
	var n := 0
	for k in rides:
		n += int(rides[k])
	return n


## Tickets a ride needs: a bit more for every ride already built.
static func ride_need(built: int) -> int:
	return 30 + 6 * mini(built, 10)


## The two rides to choose from after one is finished: open rides (need <= rides built), the least built
## first (new rides before lit-up ones), never the ride just finished when that can be helped.
static func offers(world: int, rides: Dictionary, last: String = "") -> Array:
	var done := rides_built(rides)
	var rng := Seeded.rng(world, "offers%d" % done)
	var open: Array = []
	for r in RIDES:
		if int(r.need) <= done:
			open.append(r.id)
	var pool: Array = open.filter(func(id: String) -> bool: return id != last)
	if pool.size() < 2:
		pool = open.duplicate()
	pool = Seeded.shuffled(rng, pool)
	pool.sort_custom(func(a: String, b: String) -> bool:
		var ta := int(rides.get(a, 0))
		var tb := int(rides.get(b, 0))
		if ta != tb:
			return ta < tb
		return ride_index(a) > ride_index(b))  # newest first among equals
	return pool.slice(0, 2)


## The round spec for wavegen.gd. met: {kind: true} special balloons the family has met.
static func spec(ride_id: String, built: int, met: Dictionary, players: int, time: float) -> Dictionary:
	var r := ride(ride_id)
	var kinds: Dictionary = (r.kinds as Dictionary).duplicate()
	for k in met:
		var kk := int(k)
		if kk in [WaveGen.ROCKET, WaveGen.ICE, WaveGen.TWINS] and not kinds.has(kk):
			kinds[kk] = OLD_KIND_CHANCE
	var lap := built / RIDES.size()
	var grumpy := float(r.get("grumpy", 0.0))
	if grumpy == 0.0 and met.has(WaveGen.GRUMPY):
		grumpy = OLD_GRUMPY
	var giants := int(r.get("giants", 0))
	if giants == 0 and met.has(WaveGen.GIANT) and built % 3 == 1:
		giants = 1
	return {"time": time, "level": built + lap, "players": players, "kinds": kinds, "gold": float(r.gold),
		"grumpy": grumpy, "giants": giants, "rainbow": float(r.get("rainbow", 0.0)), "name": r.id}


## Kinds a round of this spec may hold (for the validator).
static func allowed(sp: Dictionary) -> Array:
	var out: Array = [WaveGen.NORMAL, WaveGen.GOLD]
	for k in sp.kinds:
		out.append(int(k))
	if float(sp.get("grumpy", 0.0)) > 0.0:
		out.append(WaveGen.GRUMPY)
	if int(sp.get("giants", 0)) > 0:
		out.append(WaveGen.GIANT)
	return out


## TODAY'S SKY: the same on every machine all day (pass `date` in tests): a sky and a mix of specials.
static func daily_spec(players: int, time: float, date: String = "") -> Dictionary:
	var r := Seeded.rng(daily_seed(date), "daily")
	var kinds := {}
	var pool: Array = [WaveGen.ROCKET, WaveGen.ICE, WaveGen.TWINS]
	for k in Seeded.shuffled(r, pool).slice(0, r.randi_range(1, 2)):
		kinds[k] = 0.12
	return {"time": time, "level": 4, "players": players, "kinds": kinds, "gold": 0.12, "grumpy": 0.08 if r.randf() < 0.6 else 0.0,
		"giants": 1 if r.randf() < 0.5 else 0, "rainbow": 1.0, "name": "TODAY", "sky": SKIES[r.randi() % SKIES.size()]}


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed("balloon_pop", date)
