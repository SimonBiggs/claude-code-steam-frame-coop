extends RefCounted
## PARTY BOARD's boards, items, trophies and costumes (pure data + tiny helpers; every machine).
## BOARDS: Mango takes the party to five places, all on the same island shape (board_data.gd) dressed up
## differently (board_view.gd): PARTY ISLAND, SWEET SHOP, PIRATE COVE, HAUNTED HOUSE and SPACE STATION. Each
## has its own SPECIAL space and ONE board event that happens once per party (partygen.gd picks the round):
##   island  VOLCANO space: the volcano puffs and the STAR lands a few hops ahead of you.  Event RAINBOW: every
##           red space turns blue for the rest of the party.
##   sweet   CANDY space: a sugar rush, roll again.  Event CANDY RAIN: everyone gets a present (an item).
##   pirate  CANNON space: BOOM, you fly CANNON_HOPS spaces forward.  Event TREASURE: a chest appears just
##           ahead of whoever is last; the first to pass it gets a STAR.
##   haunted GHOST space: a friendly ghost swaps you with whoever is nearest the STAR.  Event BOO: the STAR
##           flies to just ahead of whoever is last.
##   space   WARP pads (always two or more): step on one, pop out of another.  Event ROCKET: everyone rolls
##           two dice this round.
## Boards unlock as the family has parties (UNLOCK); TODAY'S PARTY can visit any board, and playing it unlocks
## it. Party Board is SIMPLE_MODE: every word here is one or two UPPERCASE words (tests/party_board_gen_test.gd).
## ITEMS (from PRESENT spaces, the catch-up gift and CANDY RAIN; hold one at a time): 2 DICE, SWAP (with whoever
## is nearest the STAR), WARP (to just before the STAR). TROPHIES go on Mango's trophy wall (saved); some put a
## new hat on the tokens (HATS: costumes, core/creatures.gd hat names).

const BOARDS: Array[Dictionary] = [
	{"id": "island", "name": "PARTY ISLAND", "pic": "toucan", "sky": "day", "music": "party", "unlock": 0,
		"special": "volcano", "event": "rainbow", "event_word": "RAINBOW!", "event_pic": "rainbowisle",
		"color": Color(0.35, 0.8, 0.45)},
	{"id": "sweet", "name": "SWEET SHOP", "pic": "sweetshop", "sky": "day", "music": "party", "unlock": 1,
		"special": "candy", "event": "candy_rain", "event_word": "CANDY RAIN!", "event_pic": "gift",
		"color": Color(1.0, 0.55, 0.78)},
	{"id": "pirate", "name": "PIRATE COVE", "pic": "pirateship", "sky": "day", "music": "party", "unlock": 2,
		"special": "cannon", "event": "treasure", "event_word": "TREASURE!", "event_pic": "pirateship",
		"color": Color(0.95, 0.75, 0.3)},
	{"id": "haunted", "name": "HAUNTED HOUSE", "pic": "hauntedhouse", "sky": "sunset", "music": "mystery", "unlock": 3,
		"special": "ghost", "event": "boo", "event_word": "BOO!", "event_pic": "friendlyghost",
		"color": Color(0.65, 0.45, 0.95)},
	{"id": "space", "name": "SPACE STATION", "pic": "spacestation", "sky": "night", "music": "party", "unlock": 5,
		"special": "warp", "event": "rocket", "event_word": "ROCKET!", "event_pic": "rocket",
		"color": Color(0.4, 0.8, 1.0)},
]

## The special spaces: tile colour, emblem colour, a short word (bots / telemetry only).
const SPECIALS := {
	"volcano": {"tile": Color(1.0, 0.45, 0.15), "emb": Color(1.0, 0.9, 0.4)},
	"candy": {"tile": Color(1.0, 0.5, 0.8), "emb": Color(1, 1, 1)},
	"cannon": {"tile": Color(0.35, 0.35, 0.42), "emb": Color(1.0, 0.8, 0.3)},
	"ghost": {"tile": Color(0.62, 0.45, 0.95), "emb": Color(1, 1, 1)},
	"warp": {"tile": Color(0.2, 0.85, 0.95), "emb": Color(1, 1, 1)},
}
const SPECIAL_IDS: Array[String] = ["volcano", "candy", "cannon", "ghost", "warp"]
const GIFT_COLORS := [Color(0.35, 0.85, 0.45), Color(1.0, 0.95, 0.5)]  ## PRESENT space: tile, ribbon
const CANNON_HOPS := 5
const VOLCANO_STAR := Vector2i(3, 6)  ## the VOLCANO space: the STAR lands this many hops ahead
const EVENT_STAR := Vector2i(3, 5)  ## TREASURE / BOO: this many hops ahead of whoever is last

## Items: id, menu word, menu icon (core/ui_kit.gd), colour.
const ITEMS: Array[Dictionary] = [
	{"id": "double", "word": "2 DICE", "icon": "plus", "color": Color(1.0, 0.85, 0.3)},
	{"id": "swap", "word": "SWAP", "icon": "arrow_right", "color": Color(0.5, 0.75, 1.0)},
	{"id": "warp", "word": "WARP", "icon": "bolt", "color": Color(0.75, 0.5, 1.0)},
]

## Trophies on Mango's wall: id, the cup's colour, the picture on it (story card / ui_kit icon), the hat it
## puts on the tokens ("" = none) and Mango's line when it's won.
const TROPHIES: Array[Dictionary] = [
	{"id": "win_island", "color": Color(0.35, 0.8, 0.45), "pic": "toucan", "hat": "party", "line": "ISLAND CUP!"},
	{"id": "win_sweet", "color": Color(1.0, 0.55, 0.78), "pic": "sweetshop", "hat": "chef", "line": "SWEET CUP!"},
	{"id": "win_pirate", "color": Color(0.95, 0.75, 0.3), "pic": "pirateship", "hat": "tricorn", "line": "PIRATE CUP!"},
	{"id": "win_haunted", "color": Color(0.65, 0.45, 0.95), "pic": "hauntedhouse", "hat": "wizard", "line": "SPOOKY CUP!"},
	{"id": "win_space", "color": Color(0.4, 0.8, 1.0), "pic": "spacestation", "hat": "space_helmet", "line": "SPACE CUP!"},
	{"id": "star5", "color": Color(1.0, 0.85, 0.3), "pic": "star", "hat": "crown", "line": "FIVE STARS!"},
	{"id": "daily3", "color": Color(1.0, 0.6, 0.2), "pic": "sun", "hat": "flower", "line": "THREE DAYS!"},
	{"id": "items", "color": Color(0.75, 0.5, 1.0), "pic": "gift", "hat": "", "line": "ALL PRESENTS!"},
	{"id": "mg_all", "color": Color(0.45, 0.85, 1.0), "pic": "trophy", "hat": "top_hat", "line": "ALL GAMES!"},
	{"id": "underdog", "color": Color(1.0, 0.45, 0.45), "pic": "heart", "hat": "bow", "line": "COMEBACK!"},
	{"id": "giant", "color": Color(1.0, 0.75, 0.5), "pic": "crown", "hat": "", "line": "GIANT WINS!"},
	{"id": "festival", "color": Color(1.0, 0.6, 0.15), "pic": "trophywall", "hat": "halo", "line": "BIG PARTY!"},
]


static func board(id: String) -> Dictionary:
	for b in BOARDS:
		if b.id == id:
			return b
	return BOARDS[0]


static func board_index(id: String) -> int:
	for i in BOARDS.size():
		if BOARDS[i].id == id:
			return i
	return 0


static func ids() -> Array[String]:
	var out: Array[String] = []
	for b in BOARDS:
		out.append(String(b.id))
	return out


## The boards this family can play: unlocked by parties played, plus any board TODAY'S PARTY visited.
static func unlocked(parties: int, visited: Array) -> Array[String]:
	var out: Array[String] = []
	for b in BOARDS:
		if parties >= int(b.unlock) or visited.has(b.id):
			out.append(String(b.id))
	return out


static func item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


static func item_ids() -> Array[String]:
	var out: Array[String] = []
	for it in ITEMS:
		out.append(String(it.id))
	return out


static func trophy(id: String) -> Dictionary:
	for t in TROPHIES:
		if t.id == id:
			return t
	return {}


## Hats the tokens may wear: every hat a won trophy gave (in trophy order).
static func hats(trophies: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for t in TROPHIES:
		if trophies.has(t.id) and String(t.hat) != "" and not out.has(String(t.hat)):
			out.append(String(t.hat))
	return out


## Which hat each seat wears this party (pid 0..6 -> hat, "" = the token's own look): the won hats shared
## round the seats, starting somewhere new each party.
static func seat_hats(won: Array, seed_value: int) -> Array:
	var out: Array = []
	for pid in 7:
		out.append(String(won[(pid + absi(seed_value)) % won.size()]) if not won.is_empty() else "")
	return out
