extends RefCounted
## CRYSTAL SAGA game data: classes, skills, items, equipment, monsters, formations, summons and the
## level curve. Plain constants plus a few pure helpers, identical on the host and the TV machine
## (both compute derived stats from the same member dictionaries).
## Easy difficulty by default: monsters are slow to act and hit softly, KO'd friends get back up after
## every battle, and a wiped party simply wakes up at the last save crystal with everything kept.

const ELEMENTS: Array[String] = ["fire", "ice", "thunder", "earth", "water", "holy"]
const ELEMENT_COLORS := {
	"fire": Color(1.0, 0.45, 0.15), "ice": Color(0.55, 0.85, 1.0), "thunder": Color(1.0, 0.92, 0.3),
	"earth": Color(0.75, 0.55, 0.3), "water": Color(0.25, 0.6, 1.0), "holy": Color(1.0, 0.95, 0.75), "": Color(1, 1, 1),
}

## Party classes. look = core/creatures.gd humanoid options (class + colours). g = growth per level.
## wtype = which weapons they can hold. icon = UiKit icon kind for menus.
const CLASSES := {
	"hero": {"name": "HERO", "title": "Hero of Light", "icon": "sword", "wtype": "sword",
		"hp": 84, "mp": 16, "atk": 14, "def": 8, "mag": 10, "spd": 12,
		"g": {"hp": 11.0, "mp": 2.5, "atk": 2.2, "def": 1.4, "mag": 1.6, "spd": 0.6},
		"look": {"class": "knight", "hat": "none", "hair_style": "spiky", "hair": Color(0.97, 0.82, 0.46),
			"outfit": Color(0.25, 0.42, 0.9), "outfit2": Color(1.0, 0.82, 0.32), "cape": Color(0.9, 0.2, 0.25),
			"offhand": "round_shield", "seed": 7},
		"skills": [], "desc": "The VR player: a real sword, a real shield and the power of the Crystal."},
	"knight": {"name": "KNIGHT", "title": "Knight", "icon": "shield", "wtype": "sword",
		"hp": 92, "mp": 8, "atk": 13, "def": 12, "mag": 4, "spd": 9,
		"g": {"hp": 12.5, "mp": 1.2, "atk": 2.0, "def": 1.9, "mag": 0.6, "spd": 0.4},
		"look": {"class": "knight", "seed": 21},
		"skills": ["provoke", "guard"], "desc": "Big shield, big heart. Keeps monsters away from friends."},
	"black_mage": {"name": "BLACK MAGE", "title": "Black Mage", "icon": "fire", "wtype": "rod",
		"hp": 56, "mp": 26, "atk": 6, "def": 5, "mag": 15, "spd": 10,
		"g": {"hp": 7.5, "mp": 4.0, "atk": 0.8, "def": 0.9, "mag": 2.4, "spd": 0.5},
		"look": {"class": "mage", "outfit": Color(0.2, 0.28, 0.65), "outfit2": Color(1.0, 0.82, 0.3),
			"hat": "wizard", "hair": Color(0.13, 0.11, 0.12), "eye_color": Color(1.0, 0.85, 0.2), "seed": 33},
		"skills": ["fire", "ice", "thunder"], "desc": "Fire, Ice and Thunder spells. Find the monster's weakness!"},
	"white_mage": {"name": "WHITE MAGE", "title": "White Mage", "icon": "heart", "wtype": "rod",
		"hp": 60, "mp": 28, "atk": 6, "def": 6, "mag": 13, "spd": 10,
		"g": {"hp": 8.0, "mp": 4.0, "atk": 0.8, "def": 1.0, "mag": 2.1, "spd": 0.5},
		"look": {"class": "healer", "seed": 44},
		"skills": ["cure", "protect", "raise"], "desc": "Heals friends, shields them and wakes up KO'd heroes."},
	"thief": {"name": "THIEF", "title": "Thief", "icon": "key", "wtype": "dagger",
		"hp": 66, "mp": 12, "atk": 11, "def": 7, "mag": 6, "spd": 15,
		"g": {"hp": 9.0, "mp": 1.8, "atk": 1.9, "def": 1.1, "mag": 0.8, "spd": 0.9},
		"look": {"class": "thief", "seed": 55},
		"skills": ["steal", "double"], "desc": "Super fast. Steals treasure and strikes twice."},
	"ranger": {"name": "RANGER", "title": "Ranger", "icon": "arrow_up", "wtype": "bow",
		"hp": 66, "mp": 12, "atk": 12, "def": 7, "mag": 7, "spd": 12,
		"g": {"hp": 9.0, "mp": 1.8, "atk": 2.0, "def": 1.1, "mag": 0.9, "spd": 0.6},
		"look": {"class": "archer", "seed": 66},
		"skills": ["aim", "arrow_rain"], "desc": "Never misses. Arrow Rain hits every monster at once."},
	"bard": {"name": "BARD", "title": "Bard", "icon": "music", "wtype": "harp",
		"hp": 62, "mp": 20, "atk": 8, "def": 7, "mag": 10, "spd": 11,
		"g": {"hp": 8.5, "mp": 3.0, "atk": 1.2, "def": 1.1, "mag": 1.6, "spd": 0.6},
		"look": {"class": "bard", "seed": 77},
		"skills": ["haste", "lullaby"], "desc": "Songs that make friends fast and monsters sleepy."},
}
## The order classes are offered in.
const PICKABLE: Array[String] = ["knight", "black_mage", "white_mage", "thief", "ranger", "bard"]
## Member ids 7 and 8 are the AI friends who travel with a lone hero.
const AI_MEMBERS := {7: {"name": "MIRA", "cls": "white_mage"}, 8: {"name": "BRAM", "cls": "knight"}}

## Skills. target: enemy / enemies / ally / allies / ko_ally / self. kind: phys, magic, heal, revive,
## status, steal. power = flat bonus; mult = physical multiplier; status + secs for buffs / ailments.
const SKILLS := {
	"provoke": {"name": "Provoke", "mp": 3, "target": "self", "kind": "status", "status": "provoke", "secs": 14.0,
		"icon": "exclaim", "desc": "Monsters attack ME for a while."},
	"guard": {"name": "Guard", "mp": 6, "target": "allies", "kind": "status", "status": "guard", "secs": 14.0,
		"icon": "shield", "desc": "Everyone takes less damage."},
	"fire": {"name": "Fire", "mp": 4, "target": "enemy", "kind": "magic", "elem": "fire", "power": 14,
		"icon": "fire", "desc": "Burn one monster. Slimes and plants hate it!"},
	"ice": {"name": "Ice", "mp": 4, "target": "enemy", "kind": "magic", "elem": "ice", "power": 14,
		"icon": "drop", "desc": "Freeze one monster. Great on fire beasts."},
	"thunder": {"name": "Thunder", "mp": 7, "target": "enemies", "kind": "magic", "elem": "thunder", "power": 9,
		"icon": "bolt", "desc": "Zap EVERY monster. Flyers fall fast."},
	"cure": {"name": "Cure", "mp": 4, "target": "ally", "kind": "heal", "power": 32,
		"icon": "heart", "desc": "Heal one friend. Hurts skeletons and ghosts!"},
	"protect": {"name": "Protect", "mp": 6, "target": "allies", "kind": "status", "status": "protect", "secs": 25.0,
		"icon": "shield", "desc": "A magic shield on everyone."},
	"raise": {"name": "Raise", "mp": 9, "target": "ko_ally", "kind": "revive",
		"icon": "plus", "desc": "Wake up a KO'd friend."},
	"steal": {"name": "Steal", "mp": 0, "target": "enemy", "kind": "steal",
		"icon": "bag", "desc": "Swipe an item from a monster."},
	"double": {"name": "Double Strike", "mp": 4, "target": "enemy", "kind": "phys", "hits": 2, "mult": 0.8,
		"icon": "sword", "desc": "Two quick hits."},
	"aim": {"name": "Aim", "mp": 3, "target": "enemy", "kind": "phys", "mult": 1.7, "sure": true,
		"icon": "eye", "desc": "A careful shot that always lands hard."},
	"arrow_rain": {"name": "Arrow Rain", "mp": 7, "target": "enemies", "kind": "phys", "mult": 0.75,
		"icon": "arrow_down", "desc": "Arrows on EVERY monster."},
	"haste": {"name": "Haste Song", "mp": 6, "target": "allies", "kind": "status", "status": "haste", "secs": 22.0,
		"icon": "music", "desc": "Everyone's turn comes faster."},
	"lullaby": {"name": "Lullaby", "mp": 5, "target": "enemies", "kind": "status", "status": "sleep", "secs": 9.0,
		"chance": 0.65, "icon": "music", "desc": "Sing the monsters to sleep."},
	# The hero's rune spells (drawn in the air in VR, picked from a menu without a headset).
	"h_fire": {"name": "Fire Rune", "mp": 4, "target": "enemy", "kind": "magic", "elem": "fire", "power": 16,
		"icon": "fire", "desc": "Draw a CIRCLE."},
	"h_thunder": {"name": "Thunder Rune", "mp": 6, "target": "enemies", "kind": "magic", "elem": "thunder", "power": 10,
		"icon": "bolt", "desc": "Draw a ZIGZAG."},
	"h_cure": {"name": "Cure Rune", "mp": 5, "target": "allies", "kind": "heal", "power": 20,
		"icon": "heart", "desc": "Draw a line UP."},
}
const HERO_RUNES := {"circle": "h_fire", "zigzag": "h_thunder", "up": "h_cure"}

## Status effects: duration in seconds (real-time battles), colour and short label for the HUD.
const STATUS := {
	"poison": {"label": "POISON", "color": Color(0.7, 0.4, 1.0), "bad": true},
	"sleep": {"label": "ZZZ", "color": Color(0.6, 0.75, 1.0), "bad": true},
	"haste": {"label": "HASTE", "color": Color(1.0, 0.85, 0.3), "bad": false},
	"protect": {"label": "PROTECT", "color": Color(0.5, 0.9, 1.0), "bad": false},
	"guard": {"label": "GUARD", "color": Color(0.7, 0.8, 1.0), "bad": false},
	"provoke": {"label": "TAUNT", "color": Color(1.0, 0.5, 0.3), "bad": false},
	"defend": {"label": "DEFEND", "color": Color(0.8, 0.85, 0.95), "bad": false},
}

## Consumables (kind: heal, mp, revive, cure, full) and their shop prices.
const ITEMS := {
	"potion": {"name": "Potion", "kind": "heal", "power": 60, "price": 20, "icon": "potion", "target": "ally",
		"desc": "Heals 60 HP."},
	"hi_potion": {"name": "Hi-Potion", "kind": "heal", "power": 180, "price": 70, "icon": "potion", "target": "ally",
		"desc": "Heals 180 HP."},
	"ether": {"name": "Ether", "kind": "mp", "power": 30, "price": 50, "icon": "drop", "target": "ally",
		"desc": "Restores 30 MP."},
	"phoenix": {"name": "Phoenix Down", "kind": "revive", "power": 50, "price": 80, "icon": "plus", "target": "ko_ally",
		"desc": "Wakes up a KO'd friend."},
	"antidote": {"name": "Antidote", "kind": "cure", "status": "poison", "price": 10, "icon": "check", "target": "ally",
		"desc": "Cures poison."},
	"elixir": {"name": "Elixir", "kind": "full", "price": 0, "icon": "star", "target": "ally",
		"desc": "Full HP and MP!"},
}

## Equipment. slot weapon/armor; types = wtype allowed (armor fits everyone); atk / def / mag bonuses.
const EQUIP := {
	"bronze_sword": {"name": "Bronze Sword", "slot": "weapon", "types": ["sword"], "atk": 4, "price": 0},
	"iron_sword": {"name": "Iron Sword", "slot": "weapon", "types": ["sword"], "atk": 10, "price": 120},
	"mythril_sword": {"name": "Mythril Sword", "slot": "weapon", "types": ["sword"], "atk": 18, "price": 380},
	"crystal_blade": {"name": "Crystal Blade", "slot": "weapon", "types": ["sword"], "atk": 30, "price": 0},
	"oak_rod": {"name": "Oak Rod", "slot": "weapon", "types": ["rod"], "atk": 2, "mag": 4, "price": 0},
	"silver_rod": {"name": "Silver Rod", "slot": "weapon", "types": ["rod"], "atk": 3, "mag": 9, "price": 110},
	"star_rod": {"name": "Star Rod", "slot": "weapon", "types": ["rod"], "atk": 5, "mag": 16, "price": 360},
	"dagger": {"name": "Dagger", "slot": "weapon", "types": ["dagger"], "atk": 4, "price": 0},
	"kris": {"name": "Kris", "slot": "weapon", "types": ["dagger"], "atk": 9, "price": 100},
	"mythril_dagger": {"name": "Mythril Dagger", "slot": "weapon", "types": ["dagger"], "atk": 16, "price": 340},
	"short_bow": {"name": "Short Bow", "slot": "weapon", "types": ["bow"], "atk": 4, "price": 0},
	"long_bow": {"name": "Long Bow", "slot": "weapon", "types": ["bow"], "atk": 10, "price": 120},
	"elven_bow": {"name": "Elven Bow", "slot": "weapon", "types": ["bow"], "atk": 17, "price": 370},
	"lute": {"name": "Lute", "slot": "weapon", "types": ["harp"], "atk": 3, "mag": 3, "price": 0},
	"harp": {"name": "Harp", "slot": "weapon", "types": ["harp"], "atk": 6, "mag": 7, "price": 110},
	"golden_harp": {"name": "Golden Harp", "slot": "weapon", "types": ["harp"], "atk": 10, "mag": 13, "price": 350},
	"cloth": {"name": "Cloth Tunic", "slot": "armor", "types": [], "def": 1, "price": 0},
	"leather": {"name": "Leather Vest", "slot": "armor", "types": [], "def": 4, "price": 60},
	"chain": {"name": "Chain Mail", "slot": "armor", "types": [], "def": 8, "price": 160},
	"mythril_mail": {"name": "Mythril Mail", "slot": "armor", "types": [], "def": 13, "price": 420},
	"crystal_mail": {"name": "Crystal Mail", "slot": "armor", "types": [], "def": 20, "price": 0},
}
const START_WEAPON := {"sword": "bronze_sword", "rod": "oak_rod", "dagger": "dagger", "bow": "short_bow", "harp": "lute"}

## Shops: id -> item / equipment ids for sale.
const SHOPS := {
	"pip": ["potion", "ether", "antidote", "phoenix", "iron_sword", "silver_rod", "kris", "long_bow", "harp", "leather", "chain"],
	"hopper": ["potion", "hi_potion", "ether", "phoenix", "antidote", "mythril_sword", "star_rod", "mythril_dagger",
		"elven_bow", "golden_harp", "chain", "mythril_mail"],
}

## Monsters. model = Creatures.monster kind (or "king" = a shadowy king humanoid); scale; colours.
## moves = ids in MOVES. weak / resist = elements. drops = [[item, chance]]. undead: Cure hurts it.
const MONSTERS := {
	"slime": {"name": "Slime", "model": "slime", "scale": 1.5, "color": Color(0.45, 0.88, 0.5),
		"hp": 34, "atk": 8, "def": 3, "mag": 4, "spd": 7, "xp": 6, "gil": 6, "weak": ["fire"], "moves": ["tackle"],
		"drops": [["potion", 0.25]], "steal": "potion"},
	"bat": {"name": "Bat", "model": "bat", "scale": 1.5, "color": Color(0.6, 0.42, 0.85), "fly": true,
		"hp": 28, "atk": 9, "def": 3, "mag": 4, "spd": 12, "xp": 7, "gil": 5, "weak": ["thunder"], "moves": ["bite", "tackle"],
		"drops": [["antidote", 0.3]], "steal": "antidote"},
	"mushroom": {"name": "Shroomy", "model": "mushroom", "scale": 1.5, "color": Color(1.0, 0.45, 0.4),
		"hp": 40, "atk": 8, "def": 4, "mag": 7, "spd": 6, "xp": 9, "gil": 8, "weak": ["fire"], "moves": ["tackle", "spores"],
		"drops": [["potion", 0.3]], "steal": "ether"},
	"wolf": {"name": "Wolfie", "model": "wolf", "scale": 1.35, "color": Color(0.62, 0.64, 0.7),
		"hp": 52, "atk": 11, "def": 5, "mag": 3, "spd": 11, "xp": 12, "gil": 10, "weak": ["fire"], "moves": ["bite", "tackle"],
		"drops": [["potion", 0.3]], "steal": "potion"},
	"bee": {"name": "Buzzy", "model": "bee", "scale": 1.6, "color": Color(1.0, 0.85, 0.25), "fly": true,
		"hp": 30, "atk": 10, "def": 3, "mag": 4, "spd": 13, "xp": 8, "gil": 7, "weak": ["ice"], "moves": ["sting"],
		"drops": [["antidote", 0.35]], "steal": "antidote"},
	"king_slime": {"name": "King Slime", "model": "slime", "scale": 2.2, "boss": true, "color": Color(0.4, 0.75, 1.0),
		"hp": 150, "atk": 11, "def": 5, "mag": 6, "spd": 7, "xp": 40, "gil": 60, "weak": ["fire"], "moves": ["tackle", "bounce"],
		"drops": [["hi_potion", 1.0]], "steal": "ether"},
	# Crystal Caverns
	"crystal_slime": {"name": "Gem Slime", "model": "slime", "scale": 1.6, "color": Color(0.55, 0.85, 1.0),
		"hp": 70, "atk": 15, "def": 9, "mag": 8, "spd": 8, "xp": 20, "gil": 16, "weak": ["thunder"], "resist": ["ice"],
		"moves": ["tackle", "bounce"], "drops": [["ether", 0.25]], "steal": "ether"},
	"spider": {"name": "Spinny", "model": "spider", "scale": 1.5, "color": Color(0.55, 0.4, 0.7),
		"hp": 64, "atk": 16, "def": 7, "mag": 6, "spd": 12, "xp": 22, "gil": 15, "weak": ["fire"], "moves": ["bite", "web"],
		"drops": [["antidote", 0.4]], "steal": "antidote"},
	"crab": {"name": "Rock Crab", "model": "crab", "scale": 1.6, "color": Color(0.9, 0.45, 0.35),
		"hp": 80, "atk": 15, "def": 14, "mag": 4, "spd": 7, "xp": 24, "gil": 20, "weak": ["thunder"], "resist": ["fire"],
		"moves": ["pinch"], "drops": [["potion", 0.4]], "steal": "hi_potion"},
	"cave_bat": {"name": "Cave Bat", "model": "bat", "scale": 1.5, "color": Color(0.35, 0.3, 0.5), "fly": true,
		"hp": 54, "atk": 15, "def": 6, "mag": 6, "spd": 14, "xp": 18, "gil": 12, "weak": ["thunder"], "moves": ["bite", "tackle"],
		"drops": [["antidote", 0.3]], "steal": "potion"},
	"crystal_wyrm": {"name": "Crystal Wyrm", "model": "dragon", "scale": 1.0, "boss": true, "color": Color(0.45, 0.85, 1.0),
		"color2": Color(0.85, 0.95, 1.0), "hp": 620, "atk": 20, "def": 10, "mag": 16, "spd": 9, "xp": 260, "gil": 300,
		"weak": ["thunder"], "resist": ["ice"], "moves": ["claw", "crystal_breath", "tail"], "drops": [["hi_potion", 1.0]],
		"steal": "elixir"},
	# Sky Bridge
	"hawk": {"name": "Sky Hawk", "model": "bird", "scale": 1.7, "color": Color(0.85, 0.6, 0.35), "fly": true,
		"hp": 105, "atk": 22, "def": 9, "mag": 8, "spd": 15, "xp": 42, "gil": 26, "weak": ["thunder"], "moves": ["peck", "gale_small"],
		"drops": [["potion", 0.4]], "steal": "hi_potion"},
	"cloud_bee": {"name": "Cloud Bee", "model": "bee", "scale": 1.7, "color": Color(0.85, 0.9, 1.0), "fly": true,
		"hp": 90, "atk": 21, "def": 8, "mag": 8, "spd": 16, "xp": 38, "gil": 22, "weak": ["ice"], "moves": ["sting"],
		"drops": [["antidote", 0.4]], "steal": "ether"},
	"puff_frog": {"name": "Puff Frog", "model": "frog", "scale": 1.6, "color": Color(0.5, 0.85, 0.75),
		"hp": 125, "atk": 20, "def": 12, "mag": 12, "spd": 9, "xp": 45, "gil": 30, "weak": ["thunder"], "resist": ["water"],
		"moves": ["tackle", "bubble"], "drops": [["ether", 0.35]], "steal": "hi_potion"},
	"thunder_roc": {"name": "Thunder Roc", "model": "bird", "scale": 1.0, "boss": true, "color": Color(1.0, 0.85, 0.25),
		"color2": Color(0.3, 0.35, 0.6), "fly": true, "hp": 1250, "atk": 28, "def": 13, "mag": 22, "spd": 12, "xp": 640,
		"gil": 600, "weak": ["ice"], "resist": ["thunder"], "moves": ["peck", "gale", "bolt_call"], "drops": [["elixir", 1.0]],
		"steal": "hi_potion"},
	# Shadow Castle
	"skeleton": {"name": "Bonehead", "model": "skeleton", "scale": 1.35, "undead": true,
		"hp": 160, "atk": 28, "def": 13, "mag": 8, "spd": 10, "xp": 78, "gil": 40, "weak": ["fire", "holy"], "moves": ["slash", "bone_throw"],
		"drops": [["phoenix", 0.25]], "steal": "phoenix"},
	"ghost": {"name": "Boo", "model": "ghost", "scale": 1.5, "color": Color(0.85, 0.9, 1.0), "fly": true, "undead": true,
		"hp": 130, "atk": 24, "def": 10, "mag": 20, "spd": 13, "xp": 74, "gil": 36, "weak": ["holy", "thunder"], "moves": ["spook", "chill"],
		"drops": [["ether", 0.4]], "steal": "ether"},
	"shadow_goblin": {"name": "Shadow Goblin", "model": "goblin", "scale": 1.3, "color": Color(0.45, 0.4, 0.65),
		"hp": 170, "atk": 30, "def": 14, "mag": 8, "spd": 11, "xp": 82, "gil": 50, "weak": ["holy"], "moves": ["bonk", "tackle"],
		"drops": [["hi_potion", 0.3]], "steal": "hi_potion"},
	"shadow_wolf": {"name": "Shadow Wolf", "model": "wolf", "scale": 1.4, "color": Color(0.3, 0.25, 0.45),
		"hp": 150, "atk": 31, "def": 12, "mag": 6, "spd": 15, "xp": 80, "gil": 44, "weak": ["holy", "fire"], "moves": ["bite", "howl"],
		"drops": [["potion", 0.5]], "steal": "hi_potion"},
	"mimic": {"name": "Mimic", "model": "mimic", "scale": 1.6, "color": Color(0.7, 0.45, 0.25),
		"hp": 260, "atk": 33, "def": 18, "mag": 10, "spd": 9, "xp": 160, "gil": 220, "weak": ["thunder"], "moves": ["chomp", "tackle"],
		"drops": [["elixir", 1.0]], "steal": "elixir"},
	"shadow_king": {"name": "Shadow King", "model": "king", "scale": 2.3, "boss": true,
		"hp": 1900, "atk": 38, "def": 16, "mag": 30, "spd": 11, "xp": 0, "gil": 0, "weak": ["holy"], "resist": ["fire", "ice"],
		"moves": ["royal_slash", "shadow_flare", "dark_wave"], "drops": [], "steal": "elixir"},
	"shadow_dragon": {"name": "Shadow Dragon", "model": "dragon", "scale": 1.15, "boss": true, "color": Color(0.32, 0.2, 0.5),
		"color2": Color(0.85, 0.3, 0.6), "hp": 2600, "atk": 42, "def": 17, "mag": 34, "spd": 12, "xp": 3000, "gil": 2000,
		"weak": ["holy", "water"], "resist": ["fire"], "moves": ["claw", "doom_breath", "tail", "dark_wave"], "drops": [], "steal": "elixir"},
}

## Monster moves. kind phys/magic; target one/all; power multiplier; status + chance; windup seconds.
const MOVES := {
	"tackle": {"name": "Tackle", "kind": "phys", "target": "one", "power": 1.0, "windup": 1.2},
	"bounce": {"name": "Big Bounce", "kind": "phys", "target": "all", "power": 0.7, "windup": 1.5},
	"bite": {"name": "Bite", "kind": "phys", "target": "one", "power": 1.1, "status": "poison", "chance": 0.25, "windup": 1.1},
	"spores": {"name": "Sleepy Spores", "kind": "magic", "target": "all", "power": 0.3, "status": "sleep", "chance": 0.35, "windup": 1.4},
	"sting": {"name": "Sting", "kind": "phys", "target": "one", "power": 1.0, "status": "poison", "chance": 0.3, "windup": 1.0},
	"web": {"name": "Sticky Web", "kind": "magic", "target": "one", "power": 0.4, "status": "sleep", "chance": 0.5, "windup": 1.2},
	"pinch": {"name": "Pinch", "kind": "phys", "target": "one", "power": 1.2, "windup": 1.2},
	"claw": {"name": "Claw", "kind": "phys", "target": "one", "power": 1.25, "windup": 1.3},
	"tail": {"name": "Tail Swipe", "kind": "phys", "target": "all", "power": 0.75, "windup": 1.6},
	"crystal_breath": {"name": "Crystal Breath", "kind": "magic", "target": "all", "power": 0.9, "elem": "ice", "windup": 1.8},
	"peck": {"name": "Peck", "kind": "phys", "target": "one", "power": 1.1, "windup": 1.0},
	"gale_small": {"name": "Gust", "kind": "magic", "target": "all", "power": 0.55, "windup": 1.4},
	"bubble": {"name": "Bubble", "kind": "magic", "target": "one", "power": 1.0, "elem": "water", "windup": 1.2},
	"gale": {"name": "Gale", "kind": "magic", "target": "all", "power": 0.8, "windup": 1.7},
	"bolt_call": {"name": "Thunderclap", "kind": "magic", "target": "one", "power": 1.4, "elem": "thunder", "windup": 1.6},
	"slash": {"name": "Rusty Slash", "kind": "phys", "target": "one", "power": 1.1, "windup": 1.1},
	"bone_throw": {"name": "Bone Throw", "kind": "phys", "target": "one", "power": 0.9, "windup": 1.0},
	"spook": {"name": "Boo!", "kind": "magic", "target": "one", "power": 0.8, "status": "sleep", "chance": 0.3, "windup": 1.2},
	"chill": {"name": "Chilly Touch", "kind": "magic", "target": "one", "power": 1.1, "elem": "ice", "windup": 1.2},
	"bonk": {"name": "Club Bonk", "kind": "phys", "target": "one", "power": 1.2, "windup": 1.2},
	"howl": {"name": "Howl", "kind": "magic", "target": "all", "power": 0.5, "windup": 1.4},
	"chomp": {"name": "Chomp", "kind": "phys", "target": "one", "power": 1.4, "windup": 1.3},
	"royal_slash": {"name": "Royal Slash", "kind": "phys", "target": "one", "power": 1.2, "windup": 1.4},
	"shadow_flare": {"name": "Shadow Flare", "kind": "magic", "target": "one", "power": 1.3, "windup": 1.6},
	"dark_wave": {"name": "Dark Wave", "kind": "magic", "target": "all", "power": 0.8, "windup": 1.9},
	"doom_breath": {"name": "Shadow Breath", "kind": "magic", "target": "all", "power": 0.95, "windup": 2.0},
}

## Summons (giant guardians freed with the crystal shards). Unlocked through the story.
const SUMMONS := {
	"titan": {"name": "TITAN", "elem": "earth", "power": 46, "color": Color(0.8, 0.6, 0.35), "desc": "Earth guardian"},
	"phoenix": {"name": "PHOENIX", "elem": "fire", "power": 40, "heal": true, "color": Color(1.0, 0.5, 0.2), "desc": "Fire bird: also heals and revives"},
	"leviathan": {"name": "LEVIATHAN", "elem": "water", "power": 54, "color": Color(0.25, 0.6, 1.0), "desc": "Sea serpent"},
}
const SUMMON_ORDER: Array[String] = ["titan", "phoenix", "leviathan"]

## Areas: display name, sky preset, music mood, battle-floor colour.
const AREAS := {
	"village": {"name": "WILLOWBROOK", "sub": "A cosy village", "sky": "day", "music": "town", "floor": Color(0.42, 0.68, 0.34)},
	"forest": {"name": "WHISPERING FOREST", "sub": "Mind the slimes!", "sky": "dawn", "music": "forest", "floor": Color(0.3, 0.55, 0.3)},
	"caverns": {"name": "CRYSTAL CAVERNS", "sub": "Something glitters below", "sky": "dungeon", "music": "dungeon",
		"floor": Color(0.3, 0.3, 0.42)},
	"skybridge": {"name": "SKY BRIDGE", "sub": "Hold on to your hats", "sky": "sunset", "music": "sky", "floor": Color(0.85, 0.78, 0.7)},
	"castle": {"name": "SHADOW CASTLE", "sub": "The final shard waits", "sky": "stormy", "music": "castle", "floor": Color(0.35, 0.32, 0.4)},
}
const AREA_ORDER: Array[String] = ["village", "forest", "caverns", "skybridge", "castle"]

## Random battles per area (the visible monsters on the map pick one of these).
const FORMATIONS := {
	"forest": [["slime", "slime"], ["slime", "bat"], ["mushroom", "slime"], ["wolf"], ["bee", "bee"], ["bat", "mushroom", "slime"],
		["wolf", "slime"]],
	"caverns": [["crystal_slime", "crystal_slime"], ["spider", "cave_bat"], ["crab"], ["cave_bat", "cave_bat", "crystal_slime"],
		["spider", "crab"]],
	"skybridge": [["hawk", "cloud_bee"], ["puff_frog"], ["cloud_bee", "cloud_bee"], ["hawk"], ["puff_frog", "cloud_bee"]],
	"castle": [["skeleton", "ghost"], ["shadow_goblin", "shadow_goblin"], ["shadow_wolf", "ghost"], ["skeleton", "skeleton"],
		["shadow_goblin", "shadow_wolf"]],
}
## Story battles.
const STORY_BATTLES := {
	"tobi": {"enemies": ["slime", "king_slime", "slime"], "boss": false, "music": "battle", "title": "SAVE TOBI!"},
	"wyrm": {"enemies": ["crystal_wyrm"], "boss": true, "music": "boss", "title": "CRYSTAL WYRM"},
	"roc": {"enemies": ["thunder_roc"], "boss": true, "music": "boss", "title": "THUNDER ROC"},
	"mimic": {"enemies": ["mimic"], "boss": false, "music": "battle", "title": "IT'S A MIMIC!"},
	"king": {"enemies": ["shadow_king"], "boss": true, "music": "king", "title": "THE SHADOW KING"},
	"dragon": {"enemies": ["shadow_dragon"], "boss": true, "music": "boss", "title": "SHADOW DRAGON"},
}


# --- Helpers ----------------------------------------------------------------------------------------

## XP needed to go from `lv` to lv + 1.
static func xp_to_next(lv: int) -> int:
	return 12 + lv * lv * 7


## A fresh member of class `cls` at level `lv`, full HP / MP, starting gear.
static func new_member(id: int, cls: String, member_name: String, lv: int = 1) -> Dictionary:
	var c: Dictionary = CLASSES.get(cls, CLASSES["knight"])
	var m := {"id": id, "name": member_name, "cls": cls, "lv": maxi(1, lv), "xp": 0,
		"weapon": START_WEAPON.get(String(c["wtype"]), "bronze_sword"), "armor": "cloth", "ko": false,
		"st": {}}
	var s := stats(m)
	m["hp"] = int(s["mhp"])
	m["mp"] = int(s["mmp"])
	return m


## Derived stats of a member dictionary: mhp, mmp, atk, def, mag, spd (class + level + gear).
static func stats(m: Dictionary) -> Dictionary:
	var c: Dictionary = CLASSES.get(String(m.get("cls", "knight")), CLASSES["knight"])
	var g: Dictionary = c["g"]
	var lv := int(m.get("lv", 1)) - 1
	var w: Dictionary = EQUIP.get(String(m.get("weapon", "")), {})
	var a: Dictionary = EQUIP.get(String(m.get("armor", "")), {})
	return {
		"mhp": int(round(float(c["hp"]) + float(g["hp"]) * lv)),
		"mmp": int(round(float(c["mp"]) + float(g["mp"]) * lv)),
		"atk": int(round(float(c["atk"]) + float(g["atk"]) * lv)) + int(w.get("atk", 0)),
		"def": int(round(float(c["def"]) + float(g["def"]) * lv)) + int(a.get("def", 0)) + int(w.get("def", 0)),
		"mag": int(round(float(c["mag"]) + float(g["mag"]) * lv)) + int(w.get("mag", 0)),
		"spd": int(round(float(c["spd"]) + float(g["spd"]) * lv)),
	}


## Can class `cls` use equipment `eq`?
static func can_equip(cls: String, eq: String) -> bool:
	if not EQUIP.has(eq):
		return false
	var e: Dictionary = EQUIP[eq]
	var types: Array = e["types"]
	if types.is_empty():
		return true
	var c: Dictionary = CLASSES.get(cls, {})
	return types.has(String(c.get("wtype", "")))


## How much better `eq` is than what the member wears (stat points; <= 0 = not an upgrade).
static func upgrade_value(m: Dictionary, eq: String) -> int:
	if not can_equip(String(m.get("cls", "")), eq):
		return -999
	var e: Dictionary = EQUIP[eq]
	var cur: Dictionary = EQUIP.get(String(m.get(String(e["slot"]), "")), {})
	var score_new := int(e.get("atk", 0)) + int(e.get("def", 0)) + int(e.get("mag", 0))
	var score_old := int(cur.get("atk", 0)) + int(cur.get("def", 0)) + int(cur.get("mag", 0))
	return score_new - score_old


## Short "+6 ATK" style text for equipment.
static func equip_text(eq: String) -> String:
	var e: Dictionary = EQUIP.get(eq, {})
	var parts: PackedStringArray = []
	for k in ["atk", "mag", "def"]:
		if int(e.get(k, 0)) > 0:
			parts.append("+%d %s" % [int(e[k]), String(k).to_upper()])
	return " ".join(parts)


## Display name of an item or equipment id.
static func item_name(id: String) -> String:
	if ITEMS.has(id):
		return String(ITEMS[id]["name"])
	if EQUIP.has(id):
		return String(EQUIP[id]["name"])
	return id.capitalize()


## Price of an item or equipment id.
static func price_of(id: String) -> int:
	if ITEMS.has(id):
		return int(ITEMS[id]["price"])
	if EQUIP.has(id):
		return int(EQUIP[id]["price"])
	return 0


## Who fits this equipment, as text ("SWORD", "ROD"...).
static func equip_for(eq: String) -> String:
	var e: Dictionary = EQUIP.get(eq, {})
	var types: Array = e.get("types", [])
	if types.is_empty():
		return "ANYONE"
	var names: PackedStringArray = []
	for cls in CLASSES:
		var c: Dictionary = CLASSES[cls]
		if types.has(String(c["wtype"])) and cls != "hero":
			names.append(String(c["name"]))
	if types.has("sword"):
		names.insert(0, "HERO")
	return " / ".join(names)


## Element multiplier for a monster: 2 = weak, 0.5 = resists.
static func element_mult(mon: Dictionary, elem: String) -> float:
	if elem == "":
		return 1.0
	var weak: Array = mon.get("weak", [])
	var res: Array = mon.get("resist", [])
	if weak.has(elem):
		return 2.0
	if res.has(elem):
		return 0.5
	return 1.0
