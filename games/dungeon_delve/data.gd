extends RefCounted
## DUNGEON DELVE: every table the game reads (themes, stages, hero classes, monsters, bosses, loot,
## blessings, shop, upgrades, hats, texts). Plain constants and small static helpers only, so it
## hot-reloads safely and both machines agree on everything.

const TILE := 1.5  ## metres per dungeon tile

# --- Themes ---------------------------------------------------------------------------------------
## floor / wall / top: stone colours; accent: theme decoration; torch: flame + baked light colour;
## glow: second light colour (crystals, lava, ice); amb: baked ambient light (how bright a room is
## away from torches); enemies: ids from ENEMIES; boss: id from BOSSES; deco: decoration style.
const THEMES: Array[Dictionary] = [
	{"id": "crypt", "name": "MOSSY CRYPT", "sub": "Something squishy lives down here...",
		"floor": Color(0.42, 0.44, 0.40), "floor2": Color(0.36, 0.40, 0.33), "wall": Color(0.50, 0.52, 0.48),
		"top": Color(0.60, 0.63, 0.56), "accent": Color(0.36, 0.62, 0.26), "torch": Color(1.0, 0.62, 0.28),
		"glow": Color(0.55, 1.0, 0.45), "amb": Color(0.52, 0.56, 0.62), "env": Color(0.85, 0.88, 0.95),
		"enemies": ["slime", "bat", "skeleton", "skel_archer", "shroom"], "boss": "slime_king", "deco": "moss"},
	{"id": "mines", "name": "CRYSTAL MINES", "sub": "Shiny crystals and sneaky goblins",
		"floor": Color(0.46, 0.36, 0.28), "floor2": Color(0.40, 0.31, 0.25), "wall": Color(0.52, 0.41, 0.32),
		"top": Color(0.62, 0.50, 0.40), "accent": Color(0.50, 0.75, 1.0), "torch": Color(1.0, 0.76, 0.42),
		"glow": Color(0.55, 0.65, 1.0), "amb": Color(0.50, 0.50, 0.62), "env": Color(0.86, 0.86, 0.98),
		"enemies": ["goblin", "slinger", "spider", "cave_bat", "pebble"], "boss": "skeleton_knight", "deco": "crystal"},
	{"id": "forge", "name": "LAVA FORGE", "sub": "Hot hot hot! Mind the lava",
		"floor": Color(0.34, 0.30, 0.30), "floor2": Color(0.28, 0.25, 0.25), "wall": Color(0.40, 0.34, 0.32),
		"top": Color(0.50, 0.42, 0.38), "accent": Color(1.0, 0.45, 0.12), "torch": Color(1.0, 0.52, 0.22),
		"glow": Color(1.0, 0.45, 0.15), "amb": Color(0.58, 0.46, 0.42), "env": Color(0.98, 0.86, 0.80),
		"enemies": ["lava_slime", "bot", "crab", "fire_bat", "pebble"], "boss": "lava_golem", "deco": "lava"},
	{"id": "halls", "name": "FROZEN HALLS", "sub": "Brrr! Slippery penguins ahead",
		"floor": Color(0.66, 0.76, 0.86), "floor2": Color(0.58, 0.70, 0.82), "wall": Color(0.72, 0.82, 0.92),
		"top": Color(0.86, 0.92, 0.98), "accent": Color(0.6, 0.9, 1.0), "torch": Color(0.55, 0.85, 1.0),
		"glow": Color(0.55, 0.9, 1.0), "amb": Color(0.58, 0.64, 0.76), "env": Color(0.88, 0.92, 1.0),
		"enemies": ["penguin", "wolf", "ghost", "ice_slime", "bunny"], "boss": "frost_dragon", "deco": "ice"},
	{"id": "vault", "name": "TREASURE VAULT", "sub": "The grumpy king guards his gold",
		"floor": Color(0.56, 0.46, 0.32), "floor2": Color(0.50, 0.40, 0.28), "wall": Color(0.62, 0.52, 0.36),
		"top": Color(0.78, 0.66, 0.42), "accent": Color(1.0, 0.82, 0.3), "torch": Color(1.0, 0.8, 0.4),
		"glow": Color(1.0, 0.85, 0.35), "amb": Color(0.58, 0.52, 0.46), "env": Color(0.98, 0.92, 0.84),
		"enemies": ["mimic_small", "ghost", "skeleton", "goblin"], "boss": "king_grumble", "deco": "gold"},
]

# --- Stages ---------------------------------------------------------------------------------------
## The run: 4 themes x (3 floors + a boss lair + the camp), then the final vault. Stage numbers
## start at 1 (DD_FLOOR=<n> starts there). Stage 0 is the lobby (the camp at the dungeon gate).
## Each entry: {kind: "floor" | "boss" | "camp", theme, floor (1-3 in its theme), depth (1-12 for floors)}.
static func stages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in 4:
		for f in 3:
			out.append({"kind": "floor", "theme": t, "floor": f + 1, "depth": t * 3 + f + 1})
		out.append({"kind": "boss", "theme": t, "floor": 4, "depth": t * 3 + 3})
		out.append({"kind": "camp", "theme": t + 1, "floor": 0, "depth": t * 3 + 3})
	out.append({"kind": "boss", "theme": 4, "floor": 4, "depth": 12})
	return out


## Stage info for stage number n (1-based); n <= 0 or past the end gives the lobby.
static func stage(n: int) -> Dictionary:
	var all := stages()
	if n < 1 or n > all.size():
		return {"kind": "lobby", "theme": 0, "floor": 0, "depth": 0}
	return all[n - 1]


static func stage_count() -> int:
	return stages().size()


## First stage number of a theme (0 = Mossy Crypt floor 1).
static func theme_first_stage(theme: int) -> int:
	return 1 + theme * 5


## "FLOOR 4 - CRYSTAL MINES", "SLIME KING'S LAIR", "CAMP".
static func stage_title(n: int) -> String:
	var s := stage(n)
	match String(s["kind"]):
		"floor":
			return "FLOOR %d - %s" % [int(s["depth"]), String(THEMES[int(s["theme"])]["name"])]
		"boss":
			var b: Dictionary = BOSSES[String(THEMES[int(s["theme"])]["boss"])]
			return String(b["lair"])
		"camp":
			return "CAMP"
	return "THE DUNGEON GATE"


# --- Hero classes ---------------------------------------------------------------------------------
## look/weapon/offhand: core/creatures.gd humanoid; atk: the RT attack; x / y: the two skills.
## atk.type: "melee" (arc in front) or "shot" (projectile kind `proj`).
const CLASSES := {
	"paladin": {"name": "PALADIN", "look": "knight", "weapon": "sword", "offhand": "shield", "hp": 140, "speed": 4.4,
		"icon": "shield", "desc": "Sword and shield. Heals friends with a Holy Nova.",
		"atk": {"type": "melee", "dmg": 13, "range": 2.3, "arc": 120.0, "cd": 0.45},
		"x": {"id": "bash", "name": "SHIELD BASH", "cd": 5.0, "icon": "shield", "desc": "Charge forward and knock monsters back"},
		"y": {"id": "nova", "name": "HOLY NOVA", "cd": 12.0, "icon": "star", "desc": "Push monsters away and heal everyone near"}},
	"warrior": {"name": "WARRIOR", "look": "viking", "weapon": "axe", "offhand": "round_shield", "hp": 130, "speed": 4.6,
		"icon": "sword", "desc": "Big axe, big heart. Spins like a top!",
		"atk": {"type": "melee", "dmg": 14, "range": 2.3, "arc": 130.0, "cd": 0.5},
		"x": {"id": "spin", "name": "SPIN ATTACK", "cd": 5.0, "icon": "sword", "desc": "Spin and hit everything around you"},
		"y": {"id": "leap", "name": "LEAP SLAM", "cd": 8.0, "icon": "arrow_up", "desc": "Jump forward and stun monsters where you land"}},
	"archer": {"name": "ARCHER", "look": "archer", "weapon": "none", "offhand": "bow", "hp": 100, "speed": 4.9,
		"icon": "eye", "desc": "Shoots from far away. Never misses (well, almost).",
		"atk": {"type": "shot", "dmg": 10, "proj": "arrow", "speed": 20.0, "cd": 0.34},
		"x": {"id": "volley", "name": "PIERCING VOLLEY", "cd": 6.0, "icon": "arrow_right", "desc": "Five arrows that fly through monsters"},
		"y": {"id": "rain", "name": "ARROW RAIN", "cd": 9.0, "icon": "arrow_down", "desc": "Arrows rain down where you aim"}},
	"mage": {"name": "MAGE", "look": "mage", "weapon": "staff", "offhand": "none", "hp": 95, "speed": 4.6,
		"icon": "fire", "desc": "Fireballs and frost. Stand back and blast!",
		"atk": {"type": "shot", "dmg": 11, "proj": "bolt", "speed": 15.0, "cd": 0.42},
		"x": {"id": "fireball", "name": "FIREBALL", "cd": 5.0, "icon": "fire", "desc": "A big ball of fire that goes BOOM"},
		"y": {"id": "frost", "name": "FROST NOVA", "cd": 10.0, "icon": "drop", "desc": "Freeze every monster around you"}},
	"cleric": {"name": "CLERIC", "look": "healer", "weapon": "rod", "offhand": "none", "hp": 110, "speed": 4.6,
		"icon": "plus", "desc": "Heals friends and helps them up twice as fast.",
		"atk": {"type": "shot", "dmg": 9, "proj": "holy", "speed": 13.0, "cd": 0.42},
		"x": {"id": "heal", "name": "HEALING CIRCLE", "cd": 7.0, "icon": "heart", "desc": "Heal every friend near you"},
		"y": {"id": "revive", "name": "GUARDIAN LIGHT", "cd": 14.0, "icon": "star", "desc": "Help up every downed friend nearby and shield them"}},
	"rogue": {"name": "ROGUE", "look": "thief", "weapon": "dagger", "offhand": "dagger", "hp": 100, "speed": 5.3,
		"icon": "bolt", "desc": "Super fast. Dashes through monsters.",
		"atk": {"type": "melee", "dmg": 9, "range": 1.9, "arc": 100.0, "cd": 0.26},
		"x": {"id": "dash", "name": "SHADOW DASH", "cd": 4.0, "icon": "bolt", "desc": "Dash forward, hurting everything you pass"},
		"y": {"id": "backstab", "name": "SNEAKY STRIKE", "cd": 9.0, "icon": "eye", "desc": "Turn invisible: your next hit is a triple hit"}},
	"bard": {"name": "BARD", "look": "bard", "weapon": "lute", "offhand": "none", "hp": 105, "speed": 4.8,
		"icon": "music", "desc": "Songs that make friends stronger.",
		"atk": {"type": "shot", "dmg": 8, "proj": "note", "speed": 12.0, "cd": 0.36},
		"x": {"id": "song", "name": "BRAVE SONG", "cd": 10.0, "icon": "music", "desc": "Friends nearby hit harder and run faster"},
		"y": {"id": "lullaby", "name": "LULLABY", "cd": 11.0, "icon": "clock", "desc": "Send nearby monsters to sleep"}},
}
## The order of the class menu.
const CLASS_ORDER: Array[String] = ["warrior", "archer", "mage", "cleric", "rogue", "bard", "paladin"]
## Unlocked from the start; the rest unlock by beating bosses (see UNLOCKS).
const START_CLASSES: Array[String] = ["warrior", "archer", "mage", "cleric"]
## boss id -> class it unlocks.
const UNLOCKS := {"slime_king": "rogue", "skeleton_knight": "bard"}
## Weapon nouns per class (loot names read like "SHINY AXE").
const WEAPON_NAMES := {"paladin": "SWORD", "warrior": "AXE", "archer": "BOW", "mage": "STAFF", "cleric": "WAND",
	"rogue": "DAGGERS", "bard": "LUTE"}

# --- Monsters -------------------------------------------------------------------------------------
## kind: core/creatures.gd monster; ai: melee | hopper | ranged | flyer | charger | tank | mimic.
## hp / dmg at theme 0; speed m/s; r: body radius (m); proj: projectile kind for ranged ones.
const ENEMIES := {
	"slime": {"name": "SLIME", "kind": "slime", "color": Color(0.45, 0.9, 0.4), "ai": "hopper", "hp": 26, "dmg": 8, "speed": 2.4, "r": 0.45, "scale": 1.0, "coins": 3},
	"bat": {"name": "BAT", "kind": "bat", "color": Color(0.55, 0.45, 0.7), "ai": "flyer", "hp": 16, "dmg": 6, "speed": 3.6, "r": 0.4, "scale": 1.0, "coins": 2},
	"skeleton": {"name": "SKELETON", "kind": "skeleton", "weapon": "sword", "ai": "melee", "hp": 36, "dmg": 10, "speed": 2.6, "r": 0.4, "scale": 1.0, "coins": 4},
	"skel_archer": {"name": "SKELETON ARCHER", "kind": "skeleton", "weapon": "bow", "ai": "ranged", "proj": "arrow_e", "hp": 26, "dmg": 8, "speed": 2.4, "r": 0.4, "scale": 1.0, "coins": 4},
	"shroom": {"name": "SPORE SHROOM", "kind": "mushroom", "color": Color(0.95, 0.4, 0.45), "ai": "ranged", "proj": "spore", "hp": 28, "dmg": 7, "speed": 1.8, "r": 0.4, "scale": 1.1, "coins": 3},
	"goblin": {"name": "GOBLIN", "kind": "goblin", "weapon": "club", "ai": "melee", "hp": 34, "dmg": 9, "speed": 3.0, "r": 0.4, "scale": 1.0, "coins": 5},
	"slinger": {"name": "GOBLIN SLINGER", "kind": "goblin", "weapon": "none", "color2": Color(0.4, 0.5, 0.75), "ai": "ranged", "proj": "rock", "hp": 26, "dmg": 8, "speed": 2.8, "r": 0.4, "scale": 1.0, "coins": 5},
	"spider": {"name": "SPIDER", "kind": "spider", "color": Color(0.35, 0.3, 0.45), "ai": "melee", "hp": 22, "dmg": 8, "speed": 3.8, "r": 0.45, "scale": 1.0, "coins": 3},
	"cave_bat": {"name": "CRYSTAL BAT", "kind": "bat", "color": Color(0.5, 0.55, 0.95), "ai": "flyer", "hp": 18, "dmg": 7, "speed": 3.8, "r": 0.4, "scale": 1.0, "coins": 2},
	"pebble": {"name": "PEBBLE GOLEM", "kind": "golem", "color": Color(0.55, 0.5, 0.5), "ai": "tank", "hp": 80, "dmg": 13, "speed": 1.7, "r": 0.6, "scale": 0.8, "coins": 8},
	"lava_slime": {"name": "LAVA SLIME", "kind": "slime", "color": Color(1.0, 0.5, 0.15), "ai": "hopper", "hp": 30, "dmg": 9, "speed": 2.6, "r": 0.45, "scale": 1.05, "coins": 3},
	"bot": {"name": "FORGE BOT", "kind": "robot", "color": Color(0.7, 0.5, 0.35), "ai": "ranged", "proj": "bolt_e", "hp": 40, "dmg": 9, "speed": 2.2, "r": 0.45, "scale": 0.9, "coins": 6},
	"crab": {"name": "MAGMA CRAB", "kind": "crab", "color": Color(0.9, 0.35, 0.2), "ai": "tank", "hp": 55, "dmg": 11, "speed": 2.2, "r": 0.5, "scale": 1.2, "coins": 6},
	"fire_bat": {"name": "FIRE BAT", "kind": "bat", "color": Color(1.0, 0.45, 0.2), "ai": "flyer", "hp": 20, "dmg": 8, "speed": 4.0, "r": 0.4, "scale": 1.0, "coins": 2},
	"penguin": {"name": "PENGUIN", "kind": "penguin", "ai": "charger", "hp": 34, "dmg": 10, "speed": 2.6, "r": 0.45, "scale": 1.0, "coins": 4},
	"wolf": {"name": "SNOW WOLF", "kind": "wolf", "color": Color(0.9, 0.93, 1.0), "ai": "charger", "hp": 38, "dmg": 11, "speed": 3.4, "r": 0.5, "scale": 1.0, "coins": 5},
	"ghost": {"name": "GHOST", "kind": "ghost", "color": Color(0.8, 0.9, 1.0), "ai": "ranged", "proj": "orb", "hp": 28, "dmg": 9, "speed": 2.4, "r": 0.45, "scale": 1.0, "coins": 4},
	"ice_slime": {"name": "ICE SLIME", "kind": "slime", "color": Color(0.55, 0.85, 1.0), "ai": "hopper", "hp": 30, "dmg": 9, "speed": 2.6, "r": 0.45, "scale": 1.05, "coins": 3},
	"bunny": {"name": "SNOW BUNNY", "kind": "bunny", "color": Color(0.95, 0.95, 1.0), "ai": "hopper", "hp": 20, "dmg": 7, "speed": 3.6, "r": 0.4, "scale": 1.0, "coins": 2},
	"mimic_small": {"name": "MIMIC", "kind": "mimic", "ai": "mimic", "hp": 50, "dmg": 12, "speed": 2.8, "r": 0.5, "scale": 0.9, "coins": 10},
	"mimic": {"name": "MIMIC", "kind": "mimic", "ai": "mimic", "hp": 70, "dmg": 12, "speed": 2.8, "r": 0.55, "scale": 1.0, "coins": 20},
	"key_goblin": {"name": "KEY GOBLIN", "kind": "goblin", "weapon": "none", "color": Color(1.0, 0.85, 0.3), "ai": "melee", "hp": 60, "dmg": 8, "speed": 2.4, "r": 0.45, "scale": 1.25, "coins": 15},
}
## Monster index (for snapshots: one byte). Order never changes during a run.
static func enemy_ids() -> Array[String]:
	var out: Array[String] = []
	for k in ENEMIES:
		out.append(String(k))
	for k in BOSSES:
		out.append(String(k))
	return out


# --- Bosses ---------------------------------------------------------------------------------------
## kind: creatures monster (boss: true); hp at 1 player in normal mode; patterns: see bosses.gd.
const BOSSES := {
	"slime_king": {"name": "THE SLIME KING", "sub": "Bouncy ruler of the Mossy Crypt", "lair": "SLIME KING'S LAIR",
		"kind": "slime", "color": Color(0.45, 0.95, 0.45), "scale": 1.6, "hp": 520, "dmg": 14, "speed": 2.2, "r": 1.6,
		"patterns": ["hop_slam", "slime_rain", "summon", "hop_slam"], "minion": "slime", "hat": "viking"},
	"skeleton_knight": {"name": "SIR RATTLEBONES", "sub": "The Skeleton Knight of the Crystal Mines", "lair": "THE BONE THRONE",
		"kind": "skeleton", "color": Color(0.95, 0.93, 0.86), "scale": 1.5, "hp": 640, "dmg": 15, "speed": 2.8, "r": 1.0,
		"patterns": ["sword_combo", "charge", "bone_volley", "summon", "sword_combo"], "minion": "skeleton", "hat": "wizard"},
	"lava_golem": {"name": "MAGMA MOUNTAIN", "sub": "The Lava Golem of the Forge", "lair": "THE GREAT FURNACE",
		"kind": "golem", "color": Color(0.45, 0.32, 0.3), "scale": 1.3, "hp": 820, "dmg": 17, "speed": 1.8, "r": 1.6,
		"patterns": ["ground_pound", "lava_rocks", "fire_wave", "ground_pound", "summon"], "minion": "lava_slime", "hat": "top_hat"},
	"frost_dragon": {"name": "FROSTBITE", "sub": "The Frost Dragon of the Frozen Halls", "lair": "THE ICE THRONE",
		"kind": "dragon", "color": Color(0.6, 0.85, 1.0), "scale": 0.75, "hp": 980, "dmg": 18, "speed": 2.6, "r": 1.8,
		"patterns": ["breath", "ice_shards", "swoop", "breath", "summon"], "minion": "ice_slime", "hat": "halo"},
	"king_grumble": {"name": "KING GRUMBLE", "sub": "The grumpiest treasure chest in the world", "lair": "THE TREASURE VAULT",
		"kind": "mimic", "color": Color(0.85, 0.6, 0.3), "scale": 1.5, "hp": 1250, "dmg": 18, "speed": 3.0, "r": 1.7,
		"patterns": ["chomp_charge", "coin_storm", "ground_pound", "summon", "chomp_charge", "coin_storm"], "minion": "mimic_small", "hat": "crown"},
}

# --- Projectiles ----------------------------------------------------------------------------------
## color, r (hit radius m), len (visual stretch), team default; pierce = passes through monsters.
const PROJECTILES := {
	"arrow": {"color": Color(1.0, 0.95, 0.75), "r": 0.25, "len": 3.0},
	"bolt": {"color": Color(0.6, 0.6, 1.0), "r": 0.3, "len": 1.6},
	"holy": {"color": Color(1.0, 0.95, 0.55), "r": 0.3, "len": 1.2},
	"note": {"color": Color(1.0, 0.55, 0.8), "r": 0.3, "len": 1.0},
	"fireball": {"color": Color(1.0, 0.5, 0.15), "r": 0.45, "len": 1.2},
	"volley": {"color": Color(0.7, 1.0, 0.6), "r": 0.25, "len": 3.0},
	"arrow_e": {"color": Color(1.0, 0.4, 0.3), "r": 0.25, "len": 2.6},
	"spore": {"color": Color(0.85, 0.5, 1.0), "r": 0.3, "len": 1.0},
	"rock": {"color": Color(0.8, 0.65, 0.45), "r": 0.28, "len": 1.0},
	"bolt_e": {"color": Color(1.0, 0.6, 0.2), "r": 0.3, "len": 1.8},
	"orb": {"color": Color(0.6, 0.95, 1.0), "r": 0.32, "len": 1.0},
	"slime_ball": {"color": Color(0.5, 1.0, 0.45), "r": 0.38, "len": 1.0},
	"bone": {"color": Color(1.0, 0.95, 0.85), "r": 0.3, "len": 1.5},
	"ice": {"color": Color(0.6, 0.95, 1.0), "r": 0.32, "len": 2.0},
	"coin_shot": {"color": Color(1.0, 0.82, 0.3), "r": 0.3, "len": 1.0},
	"ember": {"color": Color(1.0, 0.4, 0.1), "r": 0.35, "len": 1.0},
}
## Kinds that belong to heroes (everything else is a monster shot).
const HERO_SHOTS: Array[String] = ["arrow", "bolt", "holy", "note", "fireball", "volley"]

# --- Loot -----------------------------------------------------------------------------------------
const RARITIES: Array[Dictionary] = [
	{"id": "common", "name": "COMMON", "color": Color(0.88, 0.88, 0.86), "weight": 60, "power": [1, 2]},
	{"id": "rare", "name": "RARE", "color": Color(0.35, 0.62, 1.0), "weight": 28, "power": [3, 4]},
	{"id": "epic", "name": "EPIC", "color": Color(0.78, 0.42, 1.0), "weight": 10, "power": [5, 7]},
	{"id": "legendary", "name": "LEGENDARY", "color": Color(1.0, 0.62, 0.15), "weight": 2, "power": [8, 10]},
]
const ADJECTIVES := {"common": ["TRUSTY", "STURDY", "HANDY"], "rare": ["SHINY", "SPARKLY", "BRAVE"],
	"epic": ["GLOWING", "MIGHTY", "DAZZLING"], "legendary": ["LEGENDARY", "STARFORGED", "HEROIC"]}
## Weapon effects (epic and legendary weapons get one).
const AFFIXES: Array[Dictionary] = [
	{"id": "sparks", "name": "OF SPARKS", "desc": "Hits zap a nearby monster"},
	{"id": "frost", "name": "OF FROST", "desc": "Hits slow monsters down"},
	{"id": "ember", "name": "OF EMBERS", "desc": "Hits set monsters on fire"},
	{"id": "hugs", "name": "OF HUGS", "desc": "Hits heal you a little"},
	{"id": "luck", "name": "OF LUCK", "desc": "+15% critical hits"},
]
## Trinkets: stat and value per power point.
const TRINKETS: Array[Dictionary] = [
	{"id": "ring", "name": "HEART RING", "stat": "hp", "per": 6, "fmt": "+%d MAX HP", "icon": "heart"},
	{"id": "boots", "name": "BOUNCY BOOTS", "stat": "speed", "per": 2, "fmt": "+%d%% SPEED", "icon": "arrow_up"},
	{"id": "amulet", "name": "STAR AMULET", "stat": "cdr", "per": 3, "fmt": "SKILLS %d%% FASTER", "icon": "star"},
	{"id": "clover", "name": "LUCKY CLOVER", "stat": "crit", "per": 2, "fmt": "+%d%% CRITICAL HITS", "icon": "gem"},
	{"id": "pouch", "name": "COIN POUCH", "stat": "gold", "per": 5, "fmt": "+%d%% COINS", "icon": "coin"},
]


static func rarity(id: String) -> Dictionary:
	for r in RARITIES:
		if String(r["id"]) == id:
			return r
	return RARITIES[0]


static func rarity_index(id: String) -> int:
	for i in RARITIES.size():
		if String(RARITIES[i]["id"]) == id:
			return i
	return 0


# --- Blessings (shrines) ----------------------------------------------------------------------
const BLESSINGS: Array[Dictionary] = [
	{"id": "might", "name": "BLESSING OF MIGHT", "desc": "Everyone hits 25% harder", "icon": "sword"},
	{"id": "life", "name": "BLESSING OF LIFE", "desc": "+30 max HP and a full heal", "icon": "heart"},
	{"id": "gold", "name": "BLESSING OF GOLD", "desc": "Monsters drop 50% more coins", "icon": "coin"},
	{"id": "haste", "name": "BLESSING OF HASTE", "desc": "Run faster, skills recharge faster", "icon": "bolt"},
	{"id": "thorns", "name": "BLESSING OF THORNS", "desc": "Monsters that hit you get hurt", "icon": "shield"},
	{"id": "luck", "name": "BLESSING OF LUCK", "desc": "Better treasure and more crits", "icon": "gem"},
	{"id": "spring", "name": "BLESSING OF SPRING", "desc": "Everyone slowly heals", "icon": "plus"},
]


static func blessing(id: String) -> Dictionary:
	for b in BLESSINGS:
		if String(b["id"]) == id:
			return b
	return BLESSINGS[0]


# --- Camp shop and upgrades -------------------------------------------------------------------
const SHOP: Array[Dictionary] = [
	{"id": "potion", "name": "HEALTH POTION", "cost": 30, "icon": "potion", "desc": "Drink with B (VR: touch the red bottle on your shield)"},
	{"id": "box", "name": "TREASURE BOX", "cost": 90, "icon": "bag", "desc": "A random RARE or better item for you"},
	{"id": "royal", "name": "ROYAL TREASURE BOX", "cost": 220, "icon": "gem", "desc": "A random EPIC or better item for you"},
]
const UPGRADES: Array[Dictionary] = [
	{"id": "vit", "name": "HEARTY STEW", "desc": "+20 max HP", "costs": [50, 80, 120], "icon": "heart"},
	{"id": "pow", "name": "WHETSTONE", "desc": "+15% damage", "costs": [60, 100, 150], "icon": "sword"},
	{"id": "cdr", "name": "FOCUS TEA", "desc": "Skills recharge 12% faster", "costs": [60, 100, 140], "icon": "clock"},
	{"id": "belt", "name": "POTION BELT", "desc": "Carry one more potion", "costs": [45, 90], "icon": "potion"},
]


static func upgrade(id: String) -> Dictionary:
	for u in UPGRADES:
		if String(u["id"]) == id:
			return u
	return UPGRADES[0]


# --- Hats (cosmetics, unlocked by milestones; saved) -------------------------------------------
## [hat (core/creatures.gd HATS or "class"), name, how to unlock, unlock key in the save's "hats"]
const HATS: Array = [
	["class", "CLASS HAT", "Always yours"],
	["party", "PARTY HAT", "Finish your first delve"],
	["viking", "VIKING HELMET", "Beat the Slime King"],
	["wizard", "WIZARD HAT", "Beat Sir Rattlebones"],
	["top_hat", "TOP HAT", "Beat Magma Mountain"],
	["halo", "HALO", "Beat Frostbite"],
	["crown", "GOLDEN CROWN", "Beat King Grumble"],
	["flower", "FLOWER", "Find 3 secret rooms"],
	["bow", "BIG BOW", "Open 25 chests"],
]

# --- Texts ----------------------------------------------------------------------------------------
const TITLE := "DUNGEON DELVE"
const BLURB := "Team up to explore magical dungeons, bash cute monsters and find treasure!"
const INTRO := {
	"title": "DUNGEON DELVE",
	"goal": "Explore the dungeon together, find the KEY, open the gate and take the stairs down!",
	"vr": {"role": "YOU ARE THE PALADIN", "controls": [["SWING", "Swing your sword at monsters"],
		["SHIELD", "Hold up your left hand to block arrows"], ["PUSH", "Push your shield forward to bash"],
		["A", "Holy Nova: heal your friends"], ["TOUCH", "Grab treasure with your hands"],
		["L-STICK", "Walk"], ["R-STICK", "Turn"]]},
	"tv": {"role": "YOU ARE THE HEROES", "controls": [["L-STICK", "Move"], ["R-STICK", "Aim"], ["RT", "Attack"],
		["A", "Dodge roll"], ["X", "Skill 1"], ["Y", "Skill 2"], ["B", "Drink a potion"]],
		"tips": ["Stand next to a friend who is down to help them up!"]},
}
const CHEERS: Array[String] = ["NICE!", "GREAT HIT!", "WOW!", "SUPER!", "AWESOME!", "BRILLIANT!"]
