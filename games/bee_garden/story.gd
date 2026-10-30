extends RefCounted
## BEE GARDEN story: QUEEN BEA (a round queen bee in a little gold crown) keeps the hive. Every full
## round the honey jars go on her JAR SHELF by the hive and stay there (saved); new flower seeds arrive
## as the shelf fills (sunflowers, then sun lilies), and a decoration moves into the garden each round
## (saved too, so the garden keeps growing from one evening to the next). Each round she has a favourite
## flower (its pollen makes a drop of extra honey) - shown as a picture, never a sentence to read.
## The first garden of each day is TODAY'S GARDEN (the same bed on every machine all day); later ones
## come from this family's own world seed. Pure data and rules (no nodes); the test checks them.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "bee_garden"
const QUEEN := "QUEEN BEA"
const QUEEN_COLOR := Color(1.0, 0.78, 0.2)
## Flower kinds arrive as the jar shelf fills: [kind, jars needed, picture].
const KIND_UNLOCKS := [[0, 0, "daisy"], [1, 4, "sunflower"], [2, 20, "lily"]]
const KIND_PICS: Array[String] = ["daisy", "sunflower", "lily"]
const SHELF_SLOTS := 32   # jars the shelf shows (4 shelves of 8); after that every jar is a gold one
const DECOR_START := 2    # the gnome and the bird bath are there from the start (props.gd)
const DECOR_MAX := 8      # world.gd DECOR
## Short lines (kids read them; <= 26 letters).
const LINES := {
	"hello": "Hello, busy bees!",
	"today": "Today's garden!",
	"fav": "I love these today!",
	"jars": "More jars for my shelf!",
	"seeds": "New seeds for you!",
	"decor": "Look who moved in!",
	"rain": "Rain! Drink up, flowers!",
	"golden": "A golden flower!",
	"aphid": "Bump the aphid away!",
	"hot": "Hot day! Water lots!",
}


static func save_defaults() -> Dictionary:
	return {"world": -1, "jars": 0, "rounds": 0, "gardens": 0, "decor": DECOR_START, "daily": "", "daily_done": "", "best_round": 0}


## How many seed kinds the tray offers with `jars` on the shelf.
static func kinds_for(jars: int) -> int:
	var n := 0
	for u in KIND_UNLOCKS:
		if jars >= int(u[1]):
			n += 1
	return clampi(n, 1, 3)


## The garden seed for a new session: TODAY'S GARDEN when it's the first garden today, else the
## family's own next garden. Returns [seed, is_today].
static func garden_seed(save: Dictionary, date: String = "") -> Array:
	var day := date if date != "" else Seeded.today()
	if String(save.get("daily", "")) != day:
		return [daily_seed(day), true]
	return [Seeded.derive(int(save.get("world", 0)), int(save.get("gardens", 0))), false]


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## The generator spec for this family's save.
static func spec(save: Dictionary, bees: int = 1) -> Dictionary:
	return {"kinds": kinds_for(int(save.get("jars", 0))), "level": int(save.get("rounds", 0)), "bees": bees}


## Jars on the shelf drawn as [plain, gold]: the first SHELF_SLOTS are honey jars; past that, each
## further jar turns one plain jar gold (so the shelf keeps changing as it fills).
static func shelf(jars: int) -> Array:
	var shown := mini(jars, SHELF_SLOTS)
	var gold := clampi(jars - SHELF_SLOTS, 0, SHELF_SLOTS)
	return [shown - gold, gold]
